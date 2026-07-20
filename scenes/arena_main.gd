extends Node2D

# 墙体数据
var walls = [
	[-1000, -1000, 1000, 50],      # 上边界
	[-1000, 290, 1000, 1000],      # 下边界
	[-99999, -1000, -625, 1000],    # 左边界
	[625, -1000, 99999, 1000]       # 右边界
]

# 全局吸附列表 (类似墙体，但用于吸附效果)
# 每个元素为 Dictionary:
#   "name":          String   - 吸附名称（唯一标识）
#   "center":        Vector2  - 吸附中心点（X=横向, Y=深度）
#   "range":         Array    - 范围矩形 [x1, y1, x2, y2]（与墙体格式一致）
#   "force":         Vector2  - 吸力速度（X=横向, Y=深度）
#   "time_left":     float    - 剩余持续时间（秒）
#   "affected_teams": Array   - 可被吸入的阵营ID列表，空=全部阵营
var global_magnetisms: Array = []

# 实体管理器引用
var entity_manager: EntityManager = null

func _ready():
	# 查找或创建EntityManager
	entity_manager = get_node_or_null("EntityManager") as EntityManager
	if not entity_manager:
		entity_manager = EntityManager.new()
		entity_manager.name = "EntityManager"
		add_child(entity_manager)
		print("Main: 自动创建EntityManager")
	
	print("Main: 初始化完成，墙体数量: " + str(walls.size()))

func _process(delta):
	_process_global_magnetisms(delta)

func _process_global_magnetisms(delta: float):
	"""每帧更新全局吸附倒计时，到期自动移除"""
	for i in range(global_magnetisms.size() - 1, -1, -1):
		var mag = global_magnetisms[i]
		mag.time_left -= delta
		if mag.time_left <= 0:
			global_magnetisms.remove_at(i)
			print("[GlobalMagnetism] 吸附到期自动移除: %s" % mag.name)

# ============================================
# 公共API
# ============================================

## 获取实体管理器
func get_entity_manager() -> EntityManager:
	return entity_manager

func broadcast_global(msg: String, data: Dictionary = {}):
	if not entity_manager:
		return
	for e in entity_manager.get_all_entities():
		e._receive_broadcast(msg, data, true)

## 获取指定ID的实体（快捷方法）
func get_entity(id: String) -> EntityBase:
	if entity_manager:
		return entity_manager.get_entity(id)
	return null

## 获取玩家实体（快捷方法）
func get_player_entity() -> EntityBase:
	if entity_manager:
		return entity_manager.get_player_entity()
	return null

func point_walls(pos: Vector2) -> Vector2:
	var m = self
	if not m or not "walls" in m:
		return Vector2.ZERO
	
	var result_pos = pos
	for wall in m.walls:
		result_pos = push_out_of_wall(result_pos, wall)
	
	# 如果位置被修改了，返回新位置，否则返回 ZERO 表示没有碰撞
	return result_pos if result_pos != pos else Vector2.ZERO

func push_out_of_wall(pos: Vector2, wall: Array) -> Vector2:
	if wall.size() < 4:
		return pos
	
	var x1 = wall[0]
	var y1 = wall[1]
	var x2 = wall[2]
	var y2 = wall[3]
	
	var min_x = min(x1, x2)
	var max_x = max(x1, x2)
	var min_y = min(y1, y2)
	var max_y = max(y1, y2)
	
	# 检查是否在墙体范围内
	if not (pos.x >= min_x and pos.x <= max_x and pos.y >= min_y and pos.y <= max_y):
		return pos
	
	# 计算到各边的距离，推出到最近边
	var dist_left = pos.x - min_x
	var dist_right = max_x - pos.x
	var dist_top = pos.y - min_y
	var dist_bottom = max_y - pos.y
	
	var min_dist = min(dist_left, dist_right, dist_top, dist_bottom)
	var new_pos = pos
	var epsilon = 0.001
	
	if is_equal_approx(min_dist, dist_left):
		new_pos.x = min_x - epsilon
	elif is_equal_approx(min_dist, dist_right):
		new_pos.x = max_x + epsilon
	elif is_equal_approx(min_dist, dist_top):
		new_pos.y = min_y - epsilon
	elif is_equal_approx(min_dist, dist_bottom):
		new_pos.y = max_y + epsilon
	
	return new_pos

# ============================================
# 全局吸附系统
# ============================================

## 添加一个全局吸附区域
## @param name: 吸附名称（唯一标识，重复会覆盖旧的）
## @param center: 吸附中心点 Vector2（X=横向, Y=深度）
## @param range_rect: 范围矩形 Array [x1, y1, x2, y2]
## @param force: 吸力速度 Vector2（X=横向, Y=深度），单位/秒
## @param duration: 持续时间（秒）
## @param affected_teams: 可被吸入的阵营ID数组，空数组=全部阵营
func add_global_magnetism(mag_name: String, center: Vector2, range_rect: Array, force: Vector2, duration: float, affected_teams: Array = []):
	if range_rect.size() < 4:
		push_error("[GlobalMagnetism] 范围无效，需要 [x1, y1, x2, y2]")
		return
	
	# 同名则移除旧的
	remove_global_magnetism(mag_name)
	
	var mag = {
		"name": mag_name,
		"center": center,
		"range": range_rect,
		"force": force,
		"time_left": duration,
		"affected_teams": affected_teams.duplicate()
	}
	global_magnetisms.append(mag)
	print("[GlobalMagnetism] 添加吸附: %s, center=%s, duration=%.2f, teams=%s" % [mag_name, center, duration, affected_teams])

## 移除指定名称的全局吸附
func remove_global_magnetism(mag_name: String):
	for i in range(global_magnetisms.size() - 1, -1, -1):
		if global_magnetisms[i].name == mag_name:
			global_magnetisms.remove_at(i)
			print("[GlobalMagnetism] 移除吸附: %s" % mag_name)
			return true
	return false

## 检查坐标是否在全局吸附范围内
func is_pos_in_magnetism_range(pos: Vector2, mag: Dictionary) -> bool:
	var r = mag.range
	if r.size() < 4:
		return false
	var min_x = min(r[0], r[2])
	var max_x = max(r[0], r[2])
	var min_y = min(r[1], r[3])
	var max_y = max(r[1], r[3])
	return pos.x >= min_x and pos.x <= max_x and pos.y >= min_y and pos.y <= max_y

## 检查指定阵营是否可被该吸附吸入
## @param team_id: 实体阵营ID
## @param mag: 吸附数据字典
## @return: true=可被吸入（affected_teams 为空或包含该 team_id）
func is_team_affected_by_magnetism(team_id: int, mag: Dictionary) -> bool:
	var teams: Array = mag.get("affected_teams", [])
	if teams.is_empty():
		return true  # 空列表 = 全部阵营
	return team_id in teams
