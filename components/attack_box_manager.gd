# attack_box_manager.gd (坐标系修复版 - Y=深度, Z=高度)

class_name AttackBoxManager
extends Node

var _attack_boxes: Dictionary = {}
var _active_boxes: Dictionary = {}  # box_id -> {node, instance_key, config, box_data}
var _entity: EntityBase = null
# 上次检查时所在的动画与帧号 —— 用于计算"卡顿跨过的帧"，见 _update_active_boxes
var _last_box_anim: String = ""
var _last_box_frame: int = -1
# 动画尾巴补偿的待处理项：动画自然播完时由 queue_tail_boxes 记下，
# 下一个物理帧与当前帧的框一起开合并立即判定，见 _update_active_boxes 第 3 步
var _tail_anim: String = ""
var _tail_frames: Array[int] = []

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

func _physics_process(delta):
	# 判定框的开合、跟随与命中判定全部挂在物理帧上，不再挂渲染帧。
	# 挂渲染帧在 30 tick 下会丢命中，两条途径：
	#   一、框的存活期由渲染帧决定，只活一帧的框可能整个存活期落在两次物理步之间，
	#       物理服务器一次都采样不到它。
	#   二、命中靠 area_entered 信号，而该信号要到物理步之后的 flush 才派发；
	#       框若在派发前被释放，_deactivate_box 会把连接一起断掉，命中被静默丢掉。
	# 现在开合按物理帧采样、含 get_frames_passed 区间补偿，命中在本 tick 立即查询。
	_update_active_boxes()
	_update_dynamic_boxes(delta)
	_check_immediate_hits()

func _update_active_boxes():
	if not _entity:
		return
	
	var current_anim = _entity.current_animation
	var current_frame = _entity.get_current_frame()
	
	# 计算"上次检查以来经过的所有帧"。
	# 卡顿（生成特效等）会让动画一个 tick 跨过好几帧，而 is_active_at_frame() 是
	# **严格单帧匹配**（frame_configs.has(frame)）—— 只问"当前帧"的话，
	# 被跨过的那几帧绑定的攻击框永远不会激活。这里遍历整个区间补齐，
	# 保证"最终效果和没卡一样"。
	# 说明：区间末帧即 current_frame，所以下面的遍历结束时，
	#       框的变换停在当前帧的配置上（不会停在中间帧）。
	var passed: Array[int] = []
	if current_anim != _last_box_anim or _last_box_frame < 0:
		# 换了动画 / 首次检查：不猜上一个动画的历史，但新动画从第 0 帧到当前帧
		# 确实播过了（切换最多晚一个物理帧才被观察到），必须补上。
		# 只处理当前帧的话，挂第 0 帧的框在采样已经走到第 1、2 帧时会被整个跳过。
		var total_frames := _entity.get_animation_frame_count(current_anim)
		if total_frames > 0 and current_frame >= 0:
			for f in range(0, mini(current_frame, total_frames - 1) + 1):
				passed.append(f)
		else:
			passed.append(current_frame)
	else:
		passed = _entity.get_frames_passed(
			_last_box_frame, current_frame, _entity.get_animation_frame_count(current_anim))
	
	if _entity.debug_frame_pipeline and passed.size() > 1:
		print("[帧管线] 攻击框跳帧补偿: %s 跨 %d 帧 %s" % [current_anim, passed.size(), str(passed)])
	
	var to_deactivate: Array[String] = []
	
	# 1) 先按"当前帧"决定谁该关。关闭判据必须用当前帧，
	#    否则被补偿激活的中间帧框会一直亮着不灭。
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
	
	# 2) 再为"经过的每一帧"补齐该亮的框（含被卡顿跨过的帧），
	#    已激活的只更新变换，未激活的当场创建。
	for f in passed:
		_activate_boxes_for_frame(current_anim, f)
	
	# 3) 上一个动画的尾巴。动画自然播完时由 queue_tail_boxes 记下，
	#    在这里与当前帧的框一起开合，紧随其后的 _check_immediate_hits 会立刻判定它们。
	# 用 _tail_anim 而不是 current_anim：本帧之前退出链可能已经切到下一个动画了，
	# 尾巴属于旧动画，与当前动画是否还是它无关。
	if _tail_frames.size() > 0:
		for f in _tail_frames:
			_activate_boxes_for_frame(_tail_anim, f)
		_tail_frames.clear()
		_tail_anim = ""
	
	_last_box_anim = current_anim
	_last_box_frame = current_frame

## 把某个动画某一帧上绑定的攻击框补齐：已激活的只更新变换，未激活的当场创建。
## 跳帧补偿与动画尾巴补偿共用，保证两条路径的开合判据一致。
func _activate_boxes_for_frame(anim_name: String, frame: int) -> void:
	for box_id in _attack_boxes.keys():
		var box_data = _attack_boxes[box_id]
		if box_data.bind_animation != anim_name:
			continue
		if not box_data.is_active_at_frame(frame):
			continue
		if _active_boxes.has(box_id):
			_update_box_transform(_active_boxes[box_id].node, box_data, frame)
		else:
			_activate_box(box_data, frame)

## 非循环动画**自然播完**时由实体调用：记下"上次检查之后到末帧"这段尾巴。
##
## 卡顿可能让一次检查直接跨到动画末帧，尾巴上那几帧绑定的攻击框一次都没轮到，
## 表现就是"这一下没判定"。
## 不在信号里直接开框：direct_space_state 的查询只能在物理帧里做，
## 所以这里只登记，交给下一个物理帧与当前帧的框一起开合并立即判定。
## 只在自然播完时调用：被脚本打断的动画不走这条路，
## 补出来的框一定是真播过的那几帧，不会凭空多一个判定。
func queue_tail_boxes(anim_name: String) -> void:
	if not _entity or anim_name == "":
		return
	if _last_box_anim != anim_name or _last_box_frame < 0:
		return
	var total_frames := _entity.get_animation_frame_count(anim_name)
	if total_frames <= 0:
		return
	_tail_anim = anim_name
	_tail_frames.clear()
	for f in range(_last_box_frame + 1, total_frames):
		_tail_frames.append(f)

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
	
	# 同步当前帧配置，让 Y 轴深度碰撞使用最新 frame_configs
	if _active_boxes.has(box_data.box_id):
		_active_boxes[box_data.box_id]["config"] = config
	
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
	# 锚点补偿还要乘上 Visuals 自身的缩放（见 EntityBase.get_visuals_extra_scale）。
	# 攻击框挂在实体根下，不随 Visuals 缩放，锚点项不跟着乘的话补间放大 Visuals 后框会偏。
	# Visuals 缩放为 ±1 时该因子恒为 1，结果与加这一项之前一致。
	var visuals_extra = _entity.get_visuals_extra_scale()
	var final_position = Vector2(
		x_pos - anchor_offset.x * anim_scale.x * visuals_extra.x,
		config.position.z + anchor_offset.y * anim_scale.y * visuals_extra.y - _entity.position_3d.y
	)
	box.position = final_position
	
	var collision = box.get_child(0) as CollisionShape2D
	if collision and collision.shape is RectangleShape2D:
		collision.shape.size = Vector2(config.size.x, config.size.z)
		collision.position = Vector2.ZERO

# ============================================
# 动态攻击框（脚本创建，不受动画帧驱动）
# ============================================

var _dynamic_boxes: Dictionary = {}  # box_id -> active_data
var _dyn_seq: int = 0

## 创建动态攻击框，返回 box_id
##
## authored_space 决定 pos 的口径，两者不能混：
##   false —— pos 是「相对实体根」的 3D 偏移，x 横向、y 前后深度、z 高度且正数向上，
##            与图形化脚本里其它 3D 坐标同一口径（now_pos3d() 那一套）。
##            图形化脚本的 create_attack_box 走这条，跟随与高度才符合作者的预期。
##   true  —— pos 直接来自 attack_boxes.json 的帧配置，是「相对精灵锚点」的编辑器坐标，
##            必须按帧驱动攻击框那套公式还原（锚点补偿 + 抵消深度）。replay_attack_box 走这条，
##            这样再现出来的框和作者在编辑器里摆的完全一致。
##
## anims 非空时框的存活期绑在这些动画上：实体当前动画不在列表里时框立刻移除。
## 列表为空时只按 duration 计，duration 为 0 即常驻，与本参数加入之前一致。
## duration 与 anims 同时给出时两条判据都要满足，谁先到谁先移除。
func create_dynamic_box(box_name: String, pos: Vector3, size: Vector3, bind: bool, duration: float,
		authored_space: bool = false, anims: PackedStringArray = PackedStringArray()) -> String:
	if not _entity:
		return ""
	_dyn_seq += 1
	var box_id = "dyn_%s_%d" % [box_name, _dyn_seq]
	var box = AttackBoxData.new()
	box.box_id = box_id
	box.box_name = box_name
	var config = AttackBoxData.FrameConfig.new()
	config.position = pos
	config.size = size
	box.set_frame_config(0, config)

	var box_area = Area2D.new()
	box_area.name = "AttackBox_" + box_id
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(size.x, size.z)
	collision.shape = shape
	box_area.add_child(collision)
	_setup_collision_layers(box_area)

	# 脱手框的绝对深度：不绑定实体时在创建瞬间冻结，NAN 表示"不是脱手框"
	var detached_y: float = NAN
	if bind:
		_entity.add_child(box_area)
		if authored_space:
			_update_box_transform(box_area, box, 0)
		else:
			_apply_root_relative_offset(box_area, pos)
	else:
		# 不绑定：位置与深度都取创建瞬间的值，之后固定在世界里
		box_area.position = _compute_dynamic_world_pos(pos, authored_space)
		var parent = _entity.get_parent()
		if parent:
			parent.add_child(box_area)
		else:
			_entity.add_child(box_area)
		# 脱手：Y 轴深度冻结成绝对值，判定直接读它。
		# 不能写进 config.position.y —— 那里是「相对实体」的口径，判定还会再加一次实体当前深度，
		# 于是深度范围被推到两倍人物深度之外永远打不到人，而且实体前后一走框就跟着走。
		detached_y = _entity.position_3d.y + pos.y

	var instance_key = "%s_%d" % [box_id, box_area.get_instance_id()]
	var active_data = {
		"node": box_area,
		"instance_key": instance_key,
		"config": config,
		"box_data": box,
		"bind": bind,
		"authored_space": authored_space,
		"detached_y": detached_y,
		"duration": duration,  # 剩余秒数；<=0 表示常驻
		"anims": anims,        # 绑定的动画名；为空表示不按动画判存活
	}
	_dynamic_boxes[box_id] = active_data

	box_area.area_entered.connect(_on_attack_box_area_entered.bind(active_data))
	box_area.body_entered.connect(_on_attack_box_body_entered.bind(active_data))
	return box_id

## 按框名再现已存在的攻击框（取第一个匹配框的首帧配置），返回 box_id
func replay_dynamic_box(box_name: String, bind: bool, duration: float,
		anims: PackedStringArray = PackedStringArray()) -> String:
	if not _entity:
		return ""
	for box in _attack_boxes.values():
		if box.box_name == box_name:
			var frame = box.bind_frames[0] if box.bind_frames.size() > 0 else 0
			var config = box.get_frame_config(frame)
			if config:
				# 帧配置是编辑器坐标口径，authored_space 必须为 true
				return create_dynamic_box(box_name, config.position, config.size, bind, duration, true, anims)
			return ""
	return ""

## 按框名移除所有匹配的动态攻击框，返回移除数量
func remove_dynamic_box_by_name(box_name: String) -> int:
	var removed = 0
	for box_id in _dynamic_boxes.keys():
		if _dynamic_boxes[box_id].box_data.box_name == box_name:
			_remove_dynamic_box(box_id)
			removed += 1
	return removed

func clear_dynamic_boxes():
	for box_id in _dynamic_boxes.keys():
		_remove_dynamic_box(box_id)

func _update_dynamic_boxes(delta: float):
	if not _entity:
		return
	var to_remove: Array[String] = []
	for box_id in _dynamic_boxes.keys():
		var data = _dynamic_boxes[box_id]
		# 动画存活期：绑了动画列表的框只在列表内任一动画播放期间存在，动画切走即移除。
		# 建框时当前动画就不在列表里的话，下一个物理帧即移除 —— 判据只有一个，
		# 「框存在 <=> 当前动画在列表内」，不做"先留着看下一帧"的特殊照顾。
		var box_anims: PackedStringArray = data.get("anims", PackedStringArray())
		if box_anims.size() > 0 and not box_anims.has(_entity.current_animation):
			to_remove.append(box_id)
			continue
		if data.duration > 0.0:
			data.duration -= delta  # delta 已受时间缩放影响，时停中不流逝
			if data.duration <= 0.0:
				to_remove.append(box_id)
				continue
		if data.bind:
			if data.authored_space:
				_update_box_transform(data.node, data.box_data, 0)
			else:
				# 相对实体根的口径：每帧重摆一次，位置、朝向、高度都跟着实体走
				_apply_root_relative_offset(data.node, data.config.position)
	for box_id in to_remove:
		_remove_dynamic_box(box_id)

## 实体开始播一段动画时由 EntityBase 调用，把开合游标对齐到本次播放的起点。
##
## 帧驱动攻击框的开合靠 _last_box_anim / _last_box_frame 推出「上次检查之后经过的帧」，
## 而判据里把"换了动画"当成"新动画从第 0 帧一路播到当前帧"，于是带起始帧播放时，
## 起始帧之前那几帧上绑的框会被当成跨过了补开一次。
## 这里直接把游标落到「起始帧 - 1」，补偿区间就从起始帧开始。
##
## 起始帧为 0 且动画名没变（同名重播）时不写游标，沿用 _update_active_boxes 原判据，
## 行为与加起始帧之前一致。
func on_animation_play(anim_name: String, start_frame: int) -> void:
	if start_frame <= 0 and anim_name == _last_box_anim:
		return
	_last_box_anim = anim_name
	_last_box_frame = start_frame - 1

## 把动态攻击框摆到「相对实体根」的 3D 偏移上。
## 2D 判定平面不含深度：这里必须和帧驱动攻击框、受击框一样把父节点的深度抵消掉
## （_update_box_transform 与 _apply_hitbox_transforms 都减 position_3d.y），
## 深度只由 _check_y_overlap_detailed 那条 1D 判定负责。
## 不减深度的话框会比受击框低整整一个 position_3d.y，2D 相交直接错位。
func _apply_root_relative_offset(box: Area2D, offset: Vector3) -> void:
	box.position = Vector2(offset.x * _entity.get_facing(), -offset.z - _entity.position_3d.y)

func _remove_dynamic_box(box_id: String):
	if not _dynamic_boxes.has(box_id):
		return
	var data = _dynamic_boxes[box_id]
	var node = data.node
	if is_instance_valid(node):
		if node.area_entered.is_connected(_on_attack_box_area_entered):
			node.area_entered.disconnect(_on_attack_box_area_entered)
		if node.body_entered.is_connected(_on_attack_box_body_entered):
			node.body_entered.disconnect(_on_attack_box_body_entered)
		node.queue_free()
	_dynamic_boxes.erase(box_id)

## 计算不绑定攻击框的世界2D位置。
## authored_space=true 走帧驱动的锚点口径；false 走「相对实体根」的 3D 口径。
func _compute_dynamic_world_pos(offset: Vector3, authored_space: bool = false) -> Vector2:
	var facing = _entity.get_facing()
	if not authored_space:
		# 相对实体根：把框放进不含深度的 2D 判定平面，再叠加横向（随朝向）与高度（正数向上）。
		# 深度同样要减掉，理由见 _apply_root_relative_offset。
		return _entity.position + Vector2(offset.x * facing, -offset.z - _entity.position_3d.y)
	var anchor_offset = _entity.current_anchor_offset
	if facing == -1:
		anchor_offset.x = -anchor_offset.x
	anchor_offset.y = -anchor_offset.y
	var anim_scale = _entity.get_anim_sprite_scale()
	# 同 _update_box_transform：锚点项带上 Visuals 自身缩放，Visuals 为 ±1 时结果不变
	var visuals_extra = _entity.get_visuals_extra_scale()
	var local = Vector2(
		offset.x * facing - anchor_offset.x * anim_scale.x * visuals_extra.x,
		offset.z + anchor_offset.y * anim_scale.y * visuals_extra.y - _entity.position_3d.y
	)
	return _entity.position + local

# ============================================
# 核心碰撞检测 - 检测受击框
# ============================================

# ============================================
# 核心碰撞检测 - 每物理帧立即判定
# ============================================

## 对每个活着的框做一次显式形状查询，命中即走 _on_attack_box_area_entered。
##
## 为什么自己查而不等 area_entered：
##   引擎的 area_entered 在物理步**之后**的 flush 才派发。框若在派发之前被释放，
##   _deactivate_box 会把连接一并断掉，这一步的命中就被静默丢掉。只活一两个物理帧的框
##   必然踩中这一条，表现为「框明明压在对方身上却打不到」。
##   显式查询用的是本 tick 刚摆好的框变换，不依赖框活够久让物理服务器先发现它。
##
## 与信号路径并存不冲突：命中标记按 instance_key 去重，两条路径只有先到的那条算数。
func _check_immediate_hits():
	if not _entity:
		return
	var space := _entity.get_world_2d().direct_space_state
	if space == null:
		return
	# keys() 返回快照：命中回调可能删框（例如命中行里移除攻击框），不能直接遍历字典
	for table in [_active_boxes, _dynamic_boxes]:
		for box_id in table.keys():
			var active_data = table.get(box_id)
			if not (active_data is Dictionary):
				continue
			var box_data = active_data.get("box_data") as AttackBoxData
			if not box_data:
				continue
			var instance_key := str(active_data.get("instance_key", ""))
			if box_data.has_triggered_instance(instance_key):
				continue
			var box := active_data.get("node") as Area2D
			if not is_instance_valid(box):
				continue
			var shape_node := box.get_child(0) as CollisionShape2D
			if not shape_node or not shape_node.shape:
				continue
			
			var params := PhysicsShapeQueryParameters2D.new()
			params.shape = shape_node.shape
			params.transform = shape_node.global_transform
			params.collide_with_areas = true
			params.collide_with_bodies = false
			params.collision_mask = 1 << 12  # 第 12 层 = 受击框
			
			for hit in space.intersect_shape(params, 16):
				var area := hit.get("collider") as Area2D
				if not area:
					continue
				_on_attack_box_area_entered(area, active_data)
				if box_data.has_triggered_instance(instance_key):
					break

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
		if not _check_y_overlap_detailed(parent, config, hit_info, active_data):
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
		if not _check_y_overlap_detailed(body, config, hit_info, active_data):
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

func _check_y_overlap_detailed(target: Node2D, attack_config: AttackBoxData.FrameConfig, hit_info: Dictionary,
		active_data: Dictionary = {}) -> bool:
	var target_y = 0.0
	# 深度回退优先级：帧数据 > 实体属性(EntityData.hurtbox_y_depth) > 硬编码 50
	var target_y_depth = 50.0
	var target_y_offset = 0.0
	if _entity and _entity.entity_data:
		target_y_depth = _entity.entity_data.hurtbox_y_depth
	
	# 从受击框数据获取 Y 深度信息
	if hit_info.has("data"):
		var data = hit_info.data
		# 优先使用新的y_offset/y_depth，兼容旧的z_offset/z_height
		target_y_offset = data.get("y_offset", data.get("z_offset", 0.0))
		target_y_depth = data.get("y_depth", data.get("z_height", target_y_depth))
	
	# 获取目标实体的基础Y深度（前后位置）
	if target.has_method("get_position_3d"):
		var pos_3d = target.get_position_3d()
		target_y = pos_3d.y + target_y_offset  # Y是前后深度
	elif target.has_meta("y_depth"):
		target_y = target.position.y + target_y_offset
	
	# 攻击框的Y（前后深度）范围
	# 脱手框（不绑定实体）的深度在创建瞬间冻结，直接读绝对值；
	# 其余框的 position.y 是「相对实体」的偏移，必须叠加实体当前深度。
	var self_y: float
	var detached_y: float = float(active_data.get("detached_y", NAN))
	if not is_nan(detached_y):
		self_y = detached_y
	else:
		self_y = _entity.position_3d.y + attack_config.position.y  # Y是前后深度
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
	clear_dynamic_boxes()
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
