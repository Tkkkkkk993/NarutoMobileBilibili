extends Node

# ============================================
# 深度排序配置
# ============================================

enum SortMode {
	Y_POSITION,      # Y 越小越靠前（俯视 RPG 默认，远处在上方，Y 小）
	Y_INVERSE,       # Y 越大越靠前（侧视或下屏 = 近）
	Z_POSITION,      # 基于 Z 高度（跳跃时覆盖）
	CUSTOM           # 自定义排序值
}

enum UpdateFrequency {
	EVERY_FRAME,     # 每帧更新
	ON_MOVE,         # 移动时更新（推荐）
	MANUAL           # 手动更新
}

# 置顶/置底偏移量
const DEPTH_OFFSET_TOP: float    = 1e6     # 顶层标记
const DEPTH_OFFSET_BOTTOM: float = -1e6    # 底层标记

# z_index 安全范围（Godot 3.x 为 -4096~4096，4.x 可达 int 极限，这里取通用安全值）
const Z_INDEX_MIN: int = -4096
const Z_INDEX_MAX: int =  4096
const Z_INDEX_STEP: int = 10               # 正常排序间隔

@export var sort_mode: SortMode = SortMode.Y_POSITION
@export var update_frequency: UpdateFrequency = UpdateFrequency.EVERY_FRAME
@export var y_sort_scale: float = 1.0
@export var z_sort_weight: float = 0.5
@export var debug_sort: bool = false

# 内部状态
var _entities: Array[Node2D] = []           # 所有可排序实体（缓存）
var _entity_last_pos: Dictionary = {}       # 位置快照，用于 ON_MOVE
var _sort_timer: float = 0.0
var _sort_interval: float = 0.05            # ON_MOVE 最小间隔
var _dirty: bool = false                    # 标记需要重排
var _initialized: bool = false

# ============================================
# 初始化
# ============================================
func _ready():
	_initialized = true
	_refresh_entity_list()                   # 首次收集实体
	print("DepthManager: 深度排序系统初始化 | 模式:%s | 频率:%s | 实体数:%d" % [
		_sort_mode_name(), _freq_name(), _entities.size()
	])

func _sort_mode_name() -> String:
	match sort_mode:
		SortMode.Y_POSITION: return "Y坐标"
		SortMode.Y_INVERSE:  return "Y反向"
		SortMode.Z_POSITION: return "Z高度"
		SortMode.CUSTOM:     return "自定义"
		_:                   return "未知"

func _freq_name() -> String:
	match update_frequency:
		UpdateFrequency.EVERY_FRAME: return "每帧"
		UpdateFrequency.ON_MOVE:     return "移动时"
		UpdateFrequency.MANUAL:      return "手动"
		_:                           return "未知"

# ============================================
# 核心排序逻辑
# ============================================
func _process(delta):
	if not _initialized:
		return

	match update_frequency:
		UpdateFrequency.EVERY_FRAME:
			_update_all_depths()
		UpdateFrequency.ON_MOVE:
			_sort_timer += delta
			if _sort_timer >= _sort_interval:
				_sort_timer = 0.0
				_update_moved_entities()
				if _dirty:                     # 强制标记（来自置顶/置底调用）
					_update_all_depths()
					_dirty = false
		UpdateFrequency.MANUAL:
			pass

func _update_all_depths():
	# 清理已释放的实体
	_cleanup_invalid_references()
	# 确保实体列表最新（动态增减时刷新）
	_refresh_entity_list()

	_entities.sort_custom(_depth_compare)

	if debug_sort and _entities.size() == 3:
		print("══════════ 深度排序 [%s模式 | %s] %d个对象 ══════════" % [
			_sort_mode_name(), _freq_name(), _entities.size()
		])
		print("  # │ 类型          │ 名称                      │ position.y │ 3D(x, y, z)             │ depth │ z_index")

	for i in range(_entities.size()):
		var entity = _entities[i]
		# 双重保险：再次检查有效性（_cleanup 已处理，但防止并发释放）
		if not is_instance_valid(entity):
			continue
		var target_z = clampi(i * Z_INDEX_STEP, Z_INDEX_MIN, Z_INDEX_MAX)
		var depth_val = _calculate_depth(entity)
		if entity.z_index != target_z:
			entity.z_index = target_z
		if debug_sort and _entities.size() == 3:
			var type_name = _get_type_name(entity)
			var p3d = _get_3d_pos(entity)
			print("%3d │ %-13s │ %-25s │ %10.1f │ (%7.1f,%7.1f,%7.1f) │ %6.1f │ %7d" % [
				i, type_name, entity.name, entity.position.y,
				p3d.x, p3d.y, p3d.z, depth_val, target_z
			])

	if debug_sort and _entities.size() == 3:
		print("═══════════════════════════════════════════════════════")


func _get_type_name(entity: Node2D) -> String:
	if entity is EntityBase:
		return "EntityBase"
	elif entity is EffectBase:
		return "EffectBase"
	elif entity.has_meta("sort_by_depth"):
		return "Sortable2D"
	return "Node2D"


func _get_3d_pos(entity: Node2D) -> Vector3:
	if entity.has_method("get_depth_pos"):
		return entity.get_depth_pos()
	if entity.has_method("get_position_3d"):
		return entity.get_position_3d()
	return Vector3(entity.position.x, entity.position.y, 0.0)

func _update_moved_entities():
	_cleanup_invalid_references()   # 先清理，避免遍历无效节点
	var any_moved = false
	for entity in _entities:
		if not is_instance_valid(entity):
			continue   # 防御性跳过（理论上已被清理）
		var last_pos: Vector2 = _entity_last_pos.get(entity, entity.position)
		if entity.position != last_pos:
			any_moved = true
			_entity_last_pos[entity] = entity.position
	if any_moved or _dirty:
		_update_all_depths()
		_dirty = false

func _depth_compare(a: Node2D, b: Node2D) -> bool:
	# 排序函数也可能遇到无效节点（极端情况），加保护
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	return _calculate_depth(a) < _calculate_depth(b)   # 越小越靠前

func _calculate_depth(entity: Node2D) -> float:
	if not is_instance_valid(entity):
		return 0.0
	var base: float = 0.0
	match sort_mode:
		SortMode.Y_POSITION:
			var pos3d = _get_3d_pos(entity)
			base = pos3d.y
		SortMode.Y_INVERSE:
			base = -entity.position.y * y_sort_scale
		SortMode.Z_POSITION:
			if entity.has_method("get_depth_pos"):
				var pos = entity.get_depth_pos()
				base = pos.y - pos.z * z_sort_weight
			else:
				base = entity.position.y
		SortMode.CUSTOM:
			base = entity.get_meta("custom_depth", entity.position.y)

	# 强制层级标记
	if entity.has_meta("depth_force_top") and entity.get_meta("depth_force_top"):
		base += DEPTH_OFFSET_TOP
	elif entity.has_meta("depth_force_bottom") and entity.get_meta("depth_force_bottom"):
		base += DEPTH_OFFSET_BOTTOM

	return base

# ============================================
# 实体管理（自动发现 + 手动注册）
# ============================================
func _cleanup_invalid_references():
	"""移除已释放的实体引用"""
	# 过滤列表
	var previous_count = _entities.size()
	_entities = _entities.filter(is_instance_valid)
	if _entities.size() != previous_count and debug_sort:
		print("[深度] 清理了 %d 个已释放实体" % (previous_count - _entities.size()))
	
	# 清理位置缓存
	var keys_to_remove = []
	for entity in _entity_last_pos.keys():
		if not is_instance_valid(entity):
			keys_to_remove.append(entity)
	for key in keys_to_remove:
		_entity_last_pos.erase(key)

func _refresh_entity_list():
	var tree = get_tree()
	if not tree:
		return
	var current = tree.current_scene
	if not current:
		return

	_entities.clear()
	_find_sortable_recursive(current)

func _find_sortable_recursive(node: Node):
	# 节点本身可能已失效，加保护
	if not is_instance_valid(node):
		return
	if node is Node2D:
		if _is_sortable(node):
			_entities.append(node)
	for child in node.get_children():
		_find_sortable_recursive(child)

func _is_sortable(entity: Node2D) -> bool:
	if not is_instance_valid(entity):
		return false
	if not entity.visible:
		return false
	if entity.has_meta("depth_frozen") and entity.get_meta("depth_frozen"):
		return false
	if entity.has_meta("sort_by_depth") or entity is EntityBase:
		return true
	return false

func register_entity(entity: Node2D):
	if not is_instance_valid(entity):
		return
	if not entity.has_meta("sort_by_depth"):
		entity.set_meta("sort_by_depth", true)
	_entity_last_pos[entity] = entity.position
	
	# 自动注销：实体离开场景树时自动清理
	if not entity.is_connected("tree_exited", _on_entity_exited):
		entity.tree_exited.connect(_on_entity_exited.bind(entity), CONNECT_ONE_SHOT)
	
	if debug_sort:
		print("[深度] 注册实体: " + entity.name)
	_dirty = true
	# 立即强制更新，确保新注册的实体（如特效）立即获得正确的 z_index
	force_update()

func _on_entity_exited(entity: Node2D):
	unregister_entity(entity)

func unregister_entity(entity: Node2D):
	_entity_last_pos.erase(entity)
	# 从列表中移除（如果存在）
	_entities.erase(entity)
	if debug_sort:
		print("[深度] 注销实体: " + entity.name)
	_dirty = true

func freeze_entity_depth(entity: Node2D, frozen: bool = true):
	if not is_instance_valid(entity):
		return
	if frozen:
		entity.set_meta("depth_frozen", true)
	else:
		entity.remove_meta("depth_frozen")
	_dirty = true

func force_update():
	_update_all_depths()

# ============================================
# 层级控制接口（已包含有效性检查）
# ============================================
func bring_to_top(entity: Node2D):
	"""将实体置于顶层（立即生效）"""
	if not is_instance_valid(entity):
		return

	_ensure_registered(entity)
	entity.set_meta("depth_force_top", true)
	entity.remove_meta("depth_force_bottom")   # 清除对立标记

	if debug_sort:
		print("[深度] %s → 顶层" % entity.name)

	_dirty = true
	if update_frequency != UpdateFrequency.EVERY_FRAME:
		force_update()

func send_to_bottom(entity: Node2D):
	"""将实体置于底层（立即生效）"""
	if not is_instance_valid(entity):
		return

	_ensure_registered(entity)
	entity.set_meta("depth_force_bottom", true)
	entity.remove_meta("depth_force_top")

	if debug_sort:
		print("[深度] %s → 底层" % entity.name)

	_dirty = true
	if update_frequency != UpdateFrequency.EVERY_FRAME:
		force_update()

func clear_depth_override(entity: Node2D):
	"""清除层级覆盖，恢复正常排序"""
	if not is_instance_valid(entity):
		return

	entity.remove_meta("depth_force_top")
	entity.remove_meta("depth_force_bottom")

	if debug_sort:
		print("[深度] %s → 正常排序" % entity.name)

	_dirty = true
	if update_frequency != UpdateFrequency.EVERY_FRAME:
		force_update()

func _ensure_registered(entity: Node2D):
	"""如果实体尚未注册，自动注册"""
	if not is_instance_valid(entity):
		return
	if not (entity.has_meta("sort_by_depth") or entity is EntityBase):
		register_entity(entity)

# ============================================
# 配置修改
# ============================================
func set_sort_mode(mode: SortMode):
	sort_mode = mode
	force_update()

func set_update_frequency(freq: UpdateFrequency):
	update_frequency = freq
