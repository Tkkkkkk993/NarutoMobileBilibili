extends Node2D
class_name EffectBase

var pos_3d := Vector3.ZERO
var extra_data: Dictionary = {}

var _follow_target: Node = null
var _follow_offset: Vector3 = Vector3.ZERO
var _flip_h: bool = false
var _was_hit_stop: bool = false
var _original_speed_scale: float = 1.0

func _enter_tree():
	visible = true
	set_meta("sort_by_depth", true)
	position = Vector2(pos_3d.x, pos_3d.y + pos_3d.z)
	call_deferred("_deferred_depth_register")

func _deferred_depth_register():
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var dm = get_node_or_null("/root/DepthManager")
	if dm and dm.has_method("register_entity"):
		dm.register_entity(self)

func _ready():
	visible = true
	if not has_meta("sort_by_depth"):
		set_meta("sort_by_depth", true)
		var dm = get_node_or_null("/root/DepthManager")
		if dm and dm.has_method("register_entity"):
			dm.register_entity(self)
	play()

func play():
	pass

func _process(delta):
	# ----- 新增：处理受击暂停 -----
	var hit_stop_active = false
	if _follow_target and is_instance_valid(_follow_target):
		# 尝试获取目标节点的 _hit_stop_active 属性（布尔值）
		if "_hit_stop_active" in _follow_target:
			hit_stop_active = _follow_target._hit_stop_active
		# 如果目标提供了方法，也可以这样：
		# elif _follow_target.has_method("is_hit_stop_active"):
		#     hit_stop_active = _follow_target.is_hit_stop_active()
	
	# 状态变化时调用对应的钩子
	if hit_stop_active != _was_hit_stop:
		_was_hit_stop = hit_stop_active
		if hit_stop_active:
			_on_hit_stop_start()
		else:
			_on_hit_stop_end()
	
	# 只有在非 hit stop 状态下才更新位置
	if not hit_stop_active:
		if _follow_target and is_instance_valid(_follow_target) and _follow_target.has_method("get_effect_pos"):
			var target_pos = _follow_target.get_effect_pos()
			target_pos.y = -target_pos.y
			var real_pos := _follow_offset
			real_pos.y = _follow_offset.z
			real_pos.z = _follow_offset.y
			pos_3d = target_pos + real_pos
		
		# 将 3D 坐标映射到 2D 平面
		position = Vector2(pos_3d.x, pos_3d.y + pos_3d.z)
	# ----------------------------

func _on_animation_finished():
	queue_free()

func get_z_height() -> float:
	return pos_3d.z

func get_position_3d():
	return pos_3d

func get_effect_pos():
	return pos_3d

func get_depth_pos() -> Vector3:
	# 特效坐标系：Z = 深度（等价于其它东西的 Y）
	# Y_POSITION 排序：depth 越大 → z_index 越大 → 渲染在前
	# z_offset > 0 → 在实体前面 → 需要更大 depth
	# z_offset < 0 → 在实体后面 → 需要更小 depth
	if _follow_target and is_instance_valid(_follow_target):
		var td = _follow_target.position_3d.y + _follow_target.position_3d.z
		return Vector3(pos_3d.x, td + pos_3d.z, 0.0)
	if has_meta("_spawn_entity"):
		var entity = get_meta("_spawn_entity")
		if is_instance_valid(entity) and entity is EntityBase:
			var ed = entity.position_3d.y + entity.position_3d.z
			return Vector3(pos_3d.x, ed + pos_3d.z, 0.0)
	return Vector3(pos_3d.x, pos_3d.z, 0.0)

func set_follow(target: Node, offset: Vector3 = Vector3.ZERO):
	if not target:
		push_warning("EffectBase.set_follow: target 为 null")
		return
	if not target.has_method("get_effect_pos"):
		push_error("EffectBase.set_follow: 目标对象必须实现 get_effect_pos()")
		return
	_follow_target = target
	_follow_offset = offset
	# 重置 hit stop 状态，避免残留状态影响新目标
	_was_hit_stop = false
	_update_follow_position()

func _update_follow_position():
	if _follow_target and is_instance_valid(_follow_target) and _follow_target.has_method("get_effect_pos"):
		var target_pos = _follow_target.get_effect_pos()
		pos_3d = Vector3(target_pos.x, target_pos.z, target_pos.y) + _follow_offset
		position = Vector2(pos_3d.x, pos_3d.y + pos_3d.z)

func set_flip_h(flip: bool):
	if _flip_h == flip:
		return
	_flip_h = flip
	var abs_scale_x = abs(scale.x)
	scale.x = -abs_scale_x if flip else abs_scale_x

# ----- 受击暂停的钩子方法（可被子类重写） -----
# 当目标进入 hit stop 时调用
func _on_hit_stop_start():
	var anim_sprite = get_node_or_null("AnimatedSprite2D")
	if anim_sprite and anim_sprite is AnimatedSprite2D:
		_original_speed_scale = anim_sprite.speed_scale
		anim_sprite.speed_scale = 0.0   # 暂停

func _on_hit_stop_end():
	var anim_sprite = get_node_or_null("AnimatedSprite2D")
	if anim_sprite and anim_sprite is AnimatedSprite2D:
		anim_sprite.speed_scale = _original_speed_scale   # 恢复速度
# ------------------------------------------------
