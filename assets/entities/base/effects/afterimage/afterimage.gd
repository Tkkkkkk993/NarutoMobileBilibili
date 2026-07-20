extends EffectBase

@export var fade_time: float = 0.5
@export var hold_time: float = 0.0
@export var custom_modulate: Color = Color.WHITE

var _target: Node2D


func _ready():
	_target = extra_data.get("target", null) if extra_data else null
	if not _target:
		push_warning("Afterimage: 缺少 target")
		queue_free()
		return

	visible = true
	set_meta("sort_by_depth", true)
	var dm = get_node_or_null("/root/DepthManager")
	if dm and dm.has_method("register_entity"):
		dm.register_entity(self)

	_capture_and_spawn()


func _capture_and_spawn():
	if not _target.has_method("get_current_frame_texture"):
		queue_free()
		return
	var tex = _target.get_current_frame_texture()
	if not tex:
		queue_free()
		return

	var sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.modulate = custom_modulate
	sprite.z_index = 4095
	# 先应用 AnimatedSprite2D 自身的变换（scale/offset/flip）
	var asp = _target.get("animated_sprite") if "animated_sprite" in _target else null
	if asp and is_instance_valid(asp):
		sprite.scale = asp.scale
		sprite.offset = asp.offset
		sprite.flip_h = asp.flip_h
		sprite.flip_v = asp.flip_v
	else:
		sprite.centered = false
	if _target.visuals_node:
		sprite.position = _target.visuals_node.position
	var fd = _target.get("facing_direction")
	if fd != null:
		sprite.scale.x *= fd
	add_child(sprite)

	var tw = create_tween().set_ignore_time_scale(true)
	if hold_time > 0.0:
		tw.tween_interval(hold_time)
	tw.tween_property(sprite, "modulate:a", 0.0, fade_time)
	tw.tween_callback(queue_free)


func get_z_height() -> float:
	return pos_3d.z + 1.0

# 深度排序比目标稍后（降低 y 使其排在后一个深度）
func get_position_3d():
	return Vector3(pos_3d.x, pos_3d.y - 0.1, pos_3d.z)
