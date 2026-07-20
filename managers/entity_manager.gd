# entity_manager.gd
class_name EntityManager
extends Node2D

# ============================================
# 信号
# ============================================

## 当有新实体生成时发射（用于 when_a_entity_create 事件）
signal entity_spawned(entity: EntityBase)

# ============================================
# 实体定义配置
# ============================================

## 实体配置数据类
class EntityConfig:
	var id: String = ""           # 唯一标识（也是节点名）
	var scene_path: String = ""   # 实体场景路径
	var position: Vector2 = Vector2.ZERO
	var facing: int = 1           # 1=右, -1=左
	var team_id: int = 0          # 阵营ID
	var entity_type: EntityBase.EntityType = EntityBase.EntityType.ENEMY  # 是否由玩家控制
	var parent_entity: EntityBase = null
	var custom_data: Dictionary = {}  # 额外数据（如角色类型、颜色等）
	
	func _init(p_id: String, p_scene: String, p_pos: Vector2, 
			   p_team: int = 0, p_facing: int = 1, p_player: EntityBase.EntityType = EntityBase.EntityType.OBJECT,
			   parent: EntityBase = null):
		id = p_id
		scene_path = p_scene
		position = p_pos
		team_id = p_team
		facing = p_facing
		entity_type = p_player
		parent_entity = parent

# ============================================
# 导出变量
# ============================================

## 实体配置列表
@export var entity_definitions: Array[Dictionary] = [
	{
		"id": "Player1",
		"scene_path": "res://assets/entities/"+MatchConfig.p1_current_char+"/entity.tscn",
		"position": Vector2(-384, 190),
		"facing": 1,
		"team_id": 1,
		"entity_type": EntityBase.EntityType.PLAYER,
		"entry_action": EntityBase.EntryAction.DEFAULT,
		"scroll": MatchConfig.p1_current_scroll,
		"summon": MatchConfig.p1_current_summon,
		"controller": "res://assets/entities/彳亍/ai_controller.gd"
	},
	{
		"id": "Player2", 
		"scene_path": "res://assets/entities/"+MatchConfig.p2_current_char+"/entity.tscn",
		"position": Vector2(384, 190),
		"facing": -1,
		"team_id": 2,
		"entity_type": EntityBase.EntityType.ENEMY,
		"entry_action": EntityBase.EntryAction.DEFAULT,
		"scroll": MatchConfig.p2_current_scroll,
		"summon": MatchConfig.p2_current_summon,
		"controller": "res://assets/entities/彳亍/ai_controller.gd"
	}
]

## 实体生成容器路径（相对于Main）
@export var entities_container_path: String = "Entities"

# ============================================
# 内部状态
# ============================================

var _entities: Dictionary = {}          # id -> EntityBase 映射
var _player_entity: EntityBase = null   # 当前玩家控制的实体
var _is_initialized: bool = false

# ============================================
# 初始化
# ============================================

func _ready():
	# 延迟一帧初始化，确保父节点就绪
	call_deferred("_initialize_entities")

func _initialize_entities():
	if _is_initialized:
		return
	
	var main = get_parent()
	if not main:
		push_error("EntityManager: 必须在Main节点下")
		return
	
	# 获取或创建Entities容器
	var entities_container = main.get_node_or_null(entities_container_path)
	if not entities_container:
		entities_container = Node2D.new()
		entities_container.name = entities_container_path
		entities_container.y_sort_enabled = true  # 关键：启用Y-Sort
		main.add_child(entities_container)
		print("EntityManager: 创建Entities容器（Y-Sort已启用）")
	
	# 清空现有实体
	for child in entities_container.get_children():
		child.queue_free()
	_entities.clear()
	_player_entity = null
	
	# 生成配置的实体
	for def in entity_definitions:
		_spawn_entity(def, entities_container)
	
	_is_initialized = true
	
	# 通知摄像机找到玩家
	_notify_camera()
	
	print("EntityManager: 初始化完成，共生成 %d 个实体" % _entities.size())

func _spawn_entity(def: Dictionary, container: Node2D) -> EntityBase:
	var id = def.get("id", "")
	if id == "":
		push_error("EntityManager: 实体ID不能为空")
		return null
	
	if id in _entities:
		push_error("EntityManager: 实体ID重复: " + id)
		return null
	
	var scene_path = def.get("scene_path", "")
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_error("EntityManager: 场景路径无效: " + scene_path)
		return null
	
	# 加载并实例化
	var scene
	if LoadingManager.is_loaded(scene_path):
		scene = LoadingManager.get_resource(scene_path)
	else:
		scene = load(scene_path)
	var instance = scene.instantiate()
	
	if instance is EntityBase:
		instance.name = id
		instance.position = def.get("position", Vector2.ZERO)
		instance.entity_manager = self
		
		# 预设置
		instance.entity_type = def.get("entity_type", EntityBase.EntityType.ENEMY)
		instance.parent_entity = def.get("parent_entity", null)
		instance.entry_action = def.get("entry_action", EntityBase.EntryAction.NONE)
		instance.scroll_entity_path = "res://assets/entities/%s/entity.tscn" % def.get("scroll", "")
		instance.summon_entity_path = def.get("summon", [])
		
		# 训练教官
		#var script_path = def.get("controller", [])
		#if script_path:
			#var ai_node = Node.new()
			#var script = load(script_path)
			#ai_node.set_script(script)
			#instance.add_child(ai_node)
			#instance.is_ai_controlled = true
		
		# 预设置 res_path（让 _ready 能加载 entity_data）
		var res_path = def.get("res_path", "")
		if res_path == "":
			res_path = scene_path.get_base_dir() + "/main.tres"
		if ResourceLoader.exists(res_path):
			instance.res_path = res_path
	
	# 设置节点名（关键：用ID作为节点名）
	instance.name = id
	
	# 设置基础属性
	instance.position = def.get("position", Vector2.ZERO)
	
	# 添加到容器
	container.add_child(instance)
	
	# 配置EntityBase特有属性
	if instance is EntityBase:
		# 设置朝向
		var facing = def.get("facing", 1)
		instance.set_facing(facing)
		
		# 设置阵营
		var team_id = def.get("team_id", 0)
		instance.set_team(team_id)
		
		# 存储引用
		_entities[id] = instance
		
		# 标记玩家控制实体
		if def.get("entity_type", EntityBase.EntityType.ENEMY) == EntityBase.EntityType.PLAYER:
			if _player_entity != null:
				push_warning("EntityManager: 多个玩家实体，覆盖之前的: " + _player_entity.name)
			_player_entity = instance
			_setup_player_entity(instance)
		
		print("EntityManager: 生成实体 [%s] 位置:%s 朝向:%d 阵营:%s" % [
			id, instance.position, facing, instance.get_team_name()
		])
		
		# 广播实体生成事件（其他实体可通过 when_a_entity_create 监听）
		entity_spawned.emit(instance)
	else:
		push_warning("EntityManager: 实例化对象不是EntityBase: " + id)
	
	return instance

func _setup_player_entity(entity: EntityBase):
	"""设置玩家控制实体的特殊处理"""
	print("EntityManager: 玩家控制实体 -> " + entity.name)
	
	entity.entity_type = EntityBase.EntityType.PLAYER

func _notify_camera():
	"""通知摄像机跟踪玩家"""
	var arena = get_parent().get_parent()
	if not arena:
		return
	
	var camera = arena.get_node_or_null("Camera2D")
	if not camera:
		return
	
	if camera is DuelCamera and _player_entity:
		camera.set_target(_player_entity)
		print("EntityManager: 摄像机已绑定到玩家实体")

# ============================================
# 公共API
# ============================================

## 获取指定ID的实体
func get_entity(id: String) -> EntityBase:
	return _entities.get(id, null)

## 获取玩家控制的实体
func get_player_entity() -> EntityBase:
	return _player_entity

## 获取所有实体
func get_all_entities() -> Array[EntityBase]:
	var result: Array[EntityBase] = []
	result.assign(_entities.values())
	return result

## 获取指定阵营的所有实体
func get_entities_by_team(team_id: int) -> Array[EntityBase]:
	var result: Array[EntityBase] = []
	for entity in _entities.values():
		if entity.get_team_id() == team_id:
			result.append(entity)
	return result

## 切换玩家控制到另一个实体
func switch_player_control(entity_id: String) -> bool:
	var new_entity = get_entity(entity_id)
	if not new_entity:
		push_error("EntityManager: 找不到实体: " + entity_id)
		return false
	
	if _player_entity:
		_player_entity.entity_type = EntityBase.EntityType.ENEMY
	
	_player_entity = new_entity
	_player_entity.entity_type = EntityBase.EntityType.PLAYER
	_setup_player_entity(new_entity)
	
	# 更新摄像机
	var arena = get_parent().get_parent()
	if arena:
		var camera = arena.get_node_or_null("Camera2D")
		if camera is DuelCamera:
			camera.set_target(new_entity)
	
	print("EntityManager: 玩家控制切换到: " + entity_id)
	return true

## 动态添加实体（运行时生成）
func spawn_entity_runtime(config: EntityConfig) -> EntityBase:
	var def = {
		"id": config.id,
		"scene_path": config.scene_path,
		"position": config.position,
		"facing": config.facing,
		"team_id": config.team_id,
		"entity_type": config.entity_type,
		"parent_entity": config.parent_entity
	}
	
	var main = get_parent()
	var container = main.get_node_or_null(entities_container_path)
	if not container:
		push_error("EntityManager: Entities容器不存在")
		return null
	return _spawn_entity(def, container)

## 移除实体
func remove_entity(id: String) -> bool:
	if not id in _entities:
		return false
	
	var entity = _entities[id]
	
	# 如果是玩家实体，需要处理
	if entity == _player_entity:
		_player_entity = null
		# 可以在这里触发游戏结束或切换玩家
	
	entity.queue_free()
	_entities.erase(id)
	
	print("EntityManager: 移除实体: " + id)
	return true

## 检查是否初始化完成
func is_initialized() -> bool:
	return _is_initialized

## 获取实体数量
func get_entity_count() -> int:
	return _entities.size()
