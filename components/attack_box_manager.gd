# attack_box_manager.gd (坐标系修复版 - Y=深度, Z=高度)

class_name AttackBoxManager
extends Node

var _attack_boxes: Dictionary = {}
var _active_boxes: Dictionary = {}  # box_id -> {node, instance_key, config, box_data}
var _entity: EntityBase = null

# Y轴深度碰撞检测配置（Y是前后深度）
var _y_collision_enabled: bool = true
var _debug_y_collision: bool = false

# 碰撞结果信息
class HitResult:
	var target: Node2D
	var target_entity: EntityBase
	var hitbox_index: int
	var hitbox_name: String
	var hitbox_data: Dictionary
	var attack_box_id: String
	var attack_box_name: String
	var attack_config: AttackBoxData.FrameConfig

	func _init(t: Node2D, idx: int, name: String, data: Dictionary, 
			   atk_id: String, atk_name: String, atk_cfg: AttackBoxData.FrameConfig):
		target = t
		target_entity = t as EntityBase
		hitbox_index = idx
		hitbox_name = name
		hitbox_data = data
		attack_box_id = atk_id
		attack_box_name = atk_name
		attack_config = atk_cfg

	# 获取受击框深度(Y轴)信息
	func get_hitbox_y_info() -> Dictionary:
		if hitbox_data.has("y_offset") and hitbox_data.has("y_depth"):
			return {
				"y_offset": hitbox_data.get("y_offset", 0.0),
				"y_depth": hitbox_data.get("y_depth", 50.0),
				"actual_y": hitbox_data.get("y_offset", 0.0)
			}
		if hitbox_data.has("z_offset") and hitbox_data.has("z_height"):
			return {
				"y_offset": hitbox_data.get("z_offset", 0.0),
				"y_depth": hitbox_data.get("z_height", 50.0),
				"actual_y": hitbox_data.get("z_offset", 0.0)
			}
		return {}

	# 获取受击框形状信息
	func get_hitbox_shape_info() -> Dictionary:
		var result = {
			"shape_type": hitbox_data.get("shape_type", "rectangle"),
			"position": hitbox_data.get("position", {}),
			"rotation": hitbox_data.get("rotation", 0.0),
			"scale": hitbox_data.get("scale", {"x": 1, "y": 1})
		}
		
		if result.shape_type == "rectangle":
			result.size = hitbox_data.get("size", {"width": 10, "height": 10})
		elif result.shape_type == "circle":
			result.radius = hitbox_data.get("radius", 5)
		
		return result


	# ==================== 新增：计算相交区域 ====================

	## 计算攻击框和受击框的相交区域
	## 返回一个包含相交信息的字典
	func get_intersection_area(
		atk_center: Vector2, atk_size: Vector2, 
		def_center: Vector2, def_size: Vector2
	) -> Dictionary:
		var rect_atk = Rect2(atk_center - atk_size / 2.0, atk_size)
		var rect_def = Rect2(def_center - def_size / 2.0, def_size)
		var inter_rect = rect_atk.intersection(rect_def)
		var result = {}
		
		if inter_rect.size.x <= 0 or inter_rect.size.y <= 0:
			result["has_intersection"] = false
			result["reason"] = "no_overlap"
			result["distance"] = atk_center.distance_to(def_center)
			return result

		result["has_intersection"] = true
		result["intersection_rect"] = inter_rect
		result["intersection_size"] = inter_rect.size
		result["intersection_center"] = inter_rect.get_center()
		result["intersection_area"] = inter_rect.get_area()
		result["center_distance"] = atk_center.distance_to(def_center)
		
		var atk_area = rect_atk.get_area()
		var def_area = rect_def.get_area()
		result["overlap_ratio_attack"] = inter_rect.get_area() / atk_area if atk_area > 0 else 0.0
		result["overlap_ratio_defense"] = inter_rect.get_area() / def_area if def_area > 0 else 0.0
		
		# 相交区域内的随机位置
		var rand_x = inter_rect.position.x + randf() * inter_rect.size.x
		var rand_y = inter_rect.position.y + randf() * inter_rect.size.y
		result["random_point"] = Vector2(rand_x, rand_y)
		
		return result


	func get_intersection_from_attacker(attacker: Node2D) -> Dictionary:
		var atk_center = attacker.global_position if is_instance_valid(attacker) else Vector2.ZERO
		var atk_size = Vector2(20, 20)
		
		if is_instance_valid(attack_config) and "size" in attack_config:
			var s = attack_config.size
			if s is Dictionary:
				atk_size = Vector2(s.get("width", 20), s.get("height", 20))
			elif s is Vector2:
				atk_size = s
		
		var def_info = get_hitbox_shape_info()
		var def_center = target.global_position if is_instance_valid(target) else Vector2.ZERO
		
		if def_info.has("position"):
			var pos = def_info.position
			if pos is Dictionary:
				def_center.x += pos.get("x", 0)
				def_center.y += pos.get("y", 0)
			elif pos is Vector2:
				def_center += pos
		
		var def_size = Vector2(10, 10)
		if def_info.has("size"):
			var s = def_info.size
			if s is Dictionary:
				def_size = Vector2(s.get("width", 10), s.get("height", 10))
			elif s is Vector2:
				def_size = s
		
		return get_intersection_area(atk_center, atk_size, def_center, def_size)

func _init(entity: EntityBase):
	_entity = entity
	name = "AttackBoxManager"

func _process(delta):
	_update_active_boxes()

func _update_active_boxes():
	if not _entity:
		return
	
	var current_anim = _entity.current_animation
	var current_frame = _entity.get_current_frame()
	
	var to_deactivate: Array[String] = []
	
	for box_id in _active_boxes.keys():
		var active_data = _active_boxes[box_id]
		var box_data = _attack_boxes.get(box_id)
		
		if not box_data:
			to_deactivate.append(box_id)
			continue
		
		var should_be_active = false
		if box_data.bind_animation == current_anim:
			if box_data.is_active_at_frame(current_frame):
				should_be_active = true
		
		if not should_be_active:
			to_deactivate.append(box_id)
		else:
			_update_box_transform(active_data.node, box_data, current_frame)
	
	for box_id in to_deactivate:
		_deactivate_box(box_id)
	
	for box_id in _attack_boxes.keys():
		var box_data = _attack_boxes[box_id]
		if box_data.bind_animation == current_anim:
			if box_data.is_active_at_frame(current_frame):
				if not _active_boxes.has(box_id):
					_activate_box(box_data, current_frame)

func _activate_box(box_data: AttackBoxData, frame: int):
	var box_id = box_data.box_id
	var config = box_data.get_frame_config(frame)
	if not config:
		return
	
	var box_area = Area2D.new()
	box_area.name = "AttackBox_" + box_id + "_" + str(frame)
	
	var box_node_id = box_area.get_instance_id()
	var instance_key = "%s_%s_%d_%d" % [box_id, box_data.bind_animation, frame, box_node_id]
	
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	# 配置使用 X(宽)/Z(高)，Y 是深度不显示在2D平面
	shape.size = Vector2(config.size.x, config.size.z)
	collision.shape = shape
	box_area.add_child(collision)
	
	_setup_collision_layers(box_area)
	
	_entity.add_child(box_area)
	
	var active_data = {
		"node": box_area,
		"instance_key": instance_key,
		"config": config,
		"box_data": box_data
	}
	_active_boxes[box_id] = active_data
	
	_update_box_transform(box_area, box_data, frame)
	
	if not box_area.area_entered.is_connected(_on_attack_box_area_entered):
		box_area.area_entered.connect(_on_attack_box_area_entered.bind(active_data))
	
	if not box_area.body_entered.is_connected(_on_attack_box_body_entered):
		box_area.body_entered.connect(_on_attack_box_body_entered.bind(active_data))
	
	if _debug_y_collision:
		print("[攻击框] 激活: %s | 帧:%d | 大小:(%.1f, %.1f)" % [box_id, frame, config.size.x, config.size.z])

func _deactivate_box(box_id: String):
	if not _active_boxes.has(box_id):
		return
	
	var active_data = _active_boxes[box_id]
	var box = active_data.node
	
	if box.area_entered.is_connected(_on_attack_box_area_entered):
		box.area_entered.disconnect(_on_attack_box_area_entered)
	if box.body_entered.is_connected(_on_attack_box_body_entered):
		box.body_entered.disconnect(_on_attack_box_body_entered)
	
	box.queue_free()
	_active_boxes.erase(box_id)
	
	if _debug_y_collision:
		print("[攻击框] 停用: %s" % box_id)

func _setup_collision_layers(box_area: Area2D):
	box_area.collision_layer = 0
	box_area.collision_mask = 0
	
	# 攻击框在第11层
	box_area.collision_layer = 1 << 11
	# 检测第12层的受击框
	box_area.collision_mask = (1 << 12)

func _update_box_transform(box: Area2D, box_data: AttackBoxData, frame: int):
	var config = box_data.get_frame_config(frame)
	if not config:
		return
	
	var facing = _entity.get_facing()
	
	var anchor_offset = _entity.current_anchor_offset
	
	# 锚点偏移需要根据朝向翻转
	if facing == -1:
		anchor_offset.x = -anchor_offset.x
	anchor_offset.y = -anchor_offset.y
	
	# 攻击框配置位置根据朝向翻转（X是左右）
	var x_pos = config.position.x * facing
	
	# 2D位置使用 X(左右)/Z(上下)，Y 是前后深度
	# 减去 position_3d.y 抵消父节点前后移动带来的坐标污染
	var anim_scale = _entity.get_anim_sprite_scale()
	var final_position = Vector2(
		x_pos - anchor_offset.x * anim_scale.x,
		config.position.z + anchor_offset.y * anim_scale.y - _entity.position_3d.y
	)
	box.position = final_position
	
	var collision = box.get_child(0) as CollisionShape2D
	if collision and collision.shape is RectangleShape2D:
		collision.shape.size = Vector2(config.size.x, config.size.z)
		collision.position = Vector2.ZERO

# ============================================
# 核心碰撞检测 - 检测受击框
# ============================================

func _on_attack_box_area_entered(area: Area2D, active_data: Dictionary):
	"""当攻击框检测到受击框进入时调用"""
	
	if not area.name.begins_with("HitboxArea"):
		return
	
	var parent = area.get_parent().get_parent().get_parent()
	if parent == _entity:
		return  # 不能打自己
	
	var box_data = active_data.box_data
	var instance_key = active_data.instance_key
	var config = active_data.config
	
	if box_data.has_triggered_instance(instance_key):
		return
	
	var hit_info = _get_hitbox_info_from_area(parent, area)
	if not hit_info:
		return  # 无法识别受击框
	
	# Y轴深度碰撞检测（Y是前后深度）
	if _y_collision_enabled:
		if not _check_y_overlap_detailed(parent, config, hit_info):
			return
	
	# 阵营检测
	if parent.has_method("get_team_id"):
		if not TeamManager.can_damage(_entity.get_team_id(), parent.get_team_id()):
			return
	
	# 创建详细碰撞结果
	var hit_result = HitResult.new(
		parent,
		hit_info.index,
		hit_info.name,
		hit_info.data,
		box_data.box_id,
		box_data.box_name,
		config
	)
	
	# 标记触发
	box_data.set_triggered_instance(instance_key)
	
	# 调用详细回调
	_entity._on_attack_hit_detailed(hit_result)
	
	if _debug_y_collision:
		print("[攻击框] %s 命中 %s 的 %s[%d] | Y深度:%.1f | 形状:%s" % [
			box_data.box_name,
			parent.name,
			hit_info.name,
			hit_info.index,
			hit_info.data.get("y_offset", hit_info.data.get("z_offset", 0.0)),
			hit_info.data.get("shape_type", "unknown")
		])

# ============================================
# 备用碰撞检测 - 检测物理体
# ============================================

func _on_attack_box_body_entered(body: Node2D, active_data: Dictionary):
	"""当攻击框检测到物理体进入时调用"""
	
	if body == _entity:
		return
	
	var box_data = active_data.box_data
	var instance_key = active_data.instance_key
	var config = active_data.config
	
	if box_data.has_triggered_instance(instance_key):
		return
	
	# 尝试找到受击框信息
	var hit_info = _find_best_hitbox_on_body(body)
	if not hit_info:
		return
	
	# Y轴深度检测
	if _y_collision_enabled:
		if not _check_y_overlap_detailed(body, config, hit_info):
			return
	
	# 阵营检测
	if body.has_method("get_team_id"):
		if not TeamManager.can_damage(_entity.get_team_id(), body.get_team_id()):
			return
	
	var hit_result = HitResult.new(
		body,
		hit_info.index,
		hit_info.name,
		hit_info.data,
		box_data.box_id,
		box_data.box_name,
		config
	)
	
	box_data.set_triggered_instance(instance_key)
	_entity._on_attack_hit_detailed(hit_result)

# ============================================
# 受击框信息获取
# ============================================

func _get_hitbox_info_from_area(entity: Node2D, hitbox_area: Area2D) -> Dictionary:
	"""从受击框Area2D获取详细信息"""
	var result = {
		"index": -1,
		"name": hitbox_area.name,
		"data": {},
		"entity": entity
	}
	
	# 1) 通过 hitbox_areas 数组查找
	if entity is EntityBase:
		var entity_base = entity as EntityBase
		# 在 hitbox_areas 数组中查找
		for i in range(entity_base.hitbox_areas.size()):
			if entity_base.hitbox_areas[i] == hitbox_area:
				result.index = i
				# 从 frame_data 获取数据
				result.data = _get_hitbox_data_from_frame_data(entity_base, i)
				return result
	
	# 2) 通过名称解析索引（如 "HitboxArea_0" -> 0）
	var index_from_name = _parse_hitbox_index_from_name(hitbox_area.name)
	if index_from_name >= 0:
		result.index = index_from_name
		if entity is EntityBase:
			result.data = _get_hitbox_data_from_frame_data(entity as EntityBase, index_from_name)
		else:
			# 构造基本数据
			result.data = _construct_default_hitbox_data(hitbox_area)
		return result
	
	# 3) 遍历所有子节点查找
	var sprite = _find_animated_sprite(entity)
	if sprite:
		var idx = 0
		for child in sprite.get_children():
			if child is Area2D and child.name.begins_with("HitboxArea"):
				if child == hitbox_area:
					result.index = idx
					if entity is EntityBase:
						result.data = _get_hitbox_data_from_frame_data(entity as EntityBase, idx)
					else:
						result.data = _construct_default_hitbox_data(hitbox_area)
					return result
				idx += 1
	
	return {}

func _get_hitbox_data_from_frame_data(entity: EntityBase, hitbox_index: int) -> Dictionary:
	"""从 FrameData 中获取受击框数据"""
	var current_anim = entity.current_animation
	var current_frame = entity.get_current_frame()
	
	# 检查 animation_frame_data
	if entity.animation_frame_data.has(current_anim):
		var frame_dict = entity.animation_frame_data[current_anim]
		if frame_dict.has(current_frame):
			var frame_data = frame_dict[current_frame] as FrameData
			if frame_data and hitbox_index < frame_data.hitboxes_data.size():
				var data = frame_data.hitboxes_data[hitbox_index].duplicate()
				# 兼容旧数据：将z_offset/z_height映射为y_offset/y_depth
				if data.has("z_offset") and not data.has("y_offset"):
					data["y_offset"] = data["z_offset"]
				if data.has("z_height") and not data.has("y_depth"):
					data["y_depth"] = data["z_height"]
				return data
	
	# 返回默认数据
	return _construct_default_hitbox_data(entity.hitbox_areas[hitbox_index] if hitbox_index < entity.hitbox_areas.size() else null)

func _construct_default_hitbox_data(hitbox_area: Area2D) -> Dictionary:
	"""构造默认受击框数据"""
	if not hitbox_area:
		return {}
	
	var data = {
		"area_name": hitbox_area.name,
		"position": {"x": hitbox_area.position.x, "y": hitbox_area.position.y},
		"rotation": hitbox_area.rotation,
		"scale": {"x": hitbox_area.scale.x, "y": hitbox_area.scale.y},
		"y_offset": 0.0,  # Y是前后深度
		"y_depth": 50.0,
		"shape_type": "unknown"
	}
	
	var shape_node = hitbox_area.get_child(0) as CollisionShape2D
	if shape_node and shape_node.shape:
		if shape_node.shape is RectangleShape2D:
			data.shape_type = "rectangle"
			# 注意：shape.size 是 Godot 2D 的，对应我们的 X 和 Z
			data.size = {
				"width": shape_node.shape.size.x,
				"height": shape_node.shape.size.y  # Godot 2D 的 Y 对应我们的 Z
			}
		elif shape_node.shape is CircleShape2D:
			data.shape_type = "circle"
			data.radius = shape_node.shape.radius
	
	return data

func _parse_hitbox_index_from_name(name: String) -> int:
	"""从受击框名称解析索引"""
	# 支持格式：HitboxArea_0, HitboxArea0, HitboxArea 0 等
	if name == "HitboxArea":
		return 0
	
	# 尝试提取数字
	var regex = RegEx.new()
	regex.compile("\\\\d+")
	var result = regex.search(name)
	if result:
		return int(result.get_string())
	
	return -1

func _find_best_hitbox_on_body(body: Node2D) -> Dictionary:
	"""在物理体上找到最佳匹配的受击框"""
	# 优先返回第一个受击框
	if body is EntityBase:
		var entity = body as EntityBase
		if entity.hitbox_areas.size() > 0:
			return {
				"index": 0,
				"name": entity.hitbox_areas[0].name,
				"data": _get_hitbox_data_from_frame_data(entity, 0),
				"entity": body
			}
	
	# 查找任何Area2D
	var sprite = _find_animated_sprite(body)
	if sprite:
		var idx = 0
		for child in sprite.get_children():
			if child is Area2D and child.name.begins_with("HitboxArea"):
				return {
					"index": idx,
					"name": child.name,
					"data": _construct_default_hitbox_data(child),
					"entity": body
				}
	
	return {}

func _find_animated_sprite(node: Node) -> Node:
	"""查找实体中承载受击框子节点的根节点（兼容 AnimatedSprite2D / AnimationPlayer 等）"""
	if node is AnimatedSprite2D:
		return node
	if node is EntityBase:
		# 优先返回 visuals_node（两种实体类型共用）
		if node.visuals_node:
			return node.visuals_node
	if node.has_node("Visuals/AnimatedSprite2D"):
		return node.get_node("Visuals/AnimatedSprite2D")
	if node.has_node("AnimatedSprite2D"):
		return node.get_node("AnimatedSprite2D")
	for child in node.get_children():
		var found = _find_animated_sprite(child)
		if found:
			return found
	return null

# ============================================
# Y轴深度碰撞检测（Y是前后深度）
# ============================================

func _check_y_overlap_detailed(target: Node2D, attack_config: AttackBoxData.FrameConfig, hit_info: Dictionary) -> bool:
	var target_y = 0.0
	var target_y_depth = 50.0
	var target_y_offset = 0.0
	
	# 从受击框数据获取 Y 深度信息
	if hit_info.has("data"):
		var data = hit_info.data
		# 优先使用新的y_offset/y_depth，兼容旧的z_offset/z_height
		target_y_offset = data.get("y_offset", data.get("z_offset", 0.0))
		target_y_depth = data.get("y_depth", data.get("z_height", 50.0))
	
	# 获取目标实体的基础Y深度（前后位置）
	if target.has_method("get_position_3d"):
		var pos_3d = target.get_position_3d()
		target_y = pos_3d.y + target_y_offset  # Y是前后深度
	elif target.has_meta("y_depth"):
		target_y = target.position.y + target_y_offset
	
	# 攻击框的Y（前后深度）范围
	var self_y = _entity.position_3d.y + attack_config.position.y  # Y是前后深度
	var self_y_min = self_y - attack_config.size.y / 2
	var self_y_max = self_y + attack_config.size.y / 2
	
	# 目标受击框的Y（前后深度）范围
	var target_y_min = target_y - target_y_depth / 2
	var target_y_max = target_y + target_y_depth / 2
	
	# 检查重叠
	var y_overlap = (self_y_min <= target_y_max) and (self_y_max >= target_y_min)
	
	if _debug_y_collision and not y_overlap:
		print("[Y轴判定] 未命中 | 攻击框Y:%.1f-%.1f | 受击框Y:%.1f-%.1f (偏移:%.1f)" % [
			self_y_min, self_y_max, target_y_min, target_y_max, target_y_offset
		])
	
	return y_overlap

# ============================================
# 公共API
# ============================================

func add_attack_box(box_data: AttackBoxData):
	_attack_boxes[box_data.box_id] = box_data

func remove_attack_box(box_id: String):
	_deactivate_box(box_id)
	_attack_boxes.erase(box_id)

func get_attack_box(box_id: String) -> AttackBoxData:
	return _attack_boxes.get(box_id, null)

func get_all_attack_boxes() -> Array[AttackBoxData]:
	return _attack_boxes.values()

func reset_all_triggers():
	for box in _attack_boxes.values():
		box.reset_trigger()

func clear():
	for box_id in _active_boxes.keys():
		_deactivate_box(box_id)
	_attack_boxes.clear()

func set_y_collision_enabled(enabled: bool):
	_y_collision_enabled = enabled

func set_debug_y_collision(enabled: bool):
	_debug_y_collision = enabled

func get_active_attack_boxes_info() -> Array[Dictionary]:
	var result = []
	for box_id in _active_boxes.keys():
		var data = _active_boxes[box_id]
		result.append({
			"box_id": box_id,
			"box_name": data.box_data.box_name,
			"position": data.node.global_position,
			"size": Vector2(data.config.size.x, data.config.size.z),  # X和Z
			"has_triggered": data.box_data.has_triggered_instance(data.instance_key)
		})
	return result
