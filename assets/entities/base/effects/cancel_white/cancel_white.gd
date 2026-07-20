extends EffectBase

var _target: Node2D


func _ready():
	_target = extra_data.get("target", null) if extra_data else null
	if not _target:
		push_warning("CancelWhite: 缺少 target")
		queue_free()
		return
	
	pos_3d.y -= 0.1
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
	# 先应用 AnimatedSprite2D 自身的变换（scale/offset/flip）
	var asp = _target.get("animated_sprite") if "animated_sprite" in _target else null
	if asp and is_instance_valid(asp):
		sprite.scale = asp.scale
		sprite.offset = asp.offset
		sprite.flip_h = asp.flip_h
		sprite.flip_v = asp.flip_v
		sprite.centered = asp.centered
	else:
		sprite.centered = false
	var fd = _target.get("facing_direction")
	if fd != null:
		sprite.scale.x *= fd
	# shader 变白，保留原 alpha
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://assets/entities/base/effects/cancel_white/white.gdshader")
	sprite.material = mat

	# 直接放在 visuals 位置，缩放+渐隐
	var anchor_pos = _target.visuals_node.position if _target.visuals_node else Vector2.ZERO
	sprite.position = anchor_pos
	add_child(sprite)

	# Phase 1 (0-0.15s): 只缩放；Phase 2 (0.15-0.3s): 缩放+渐隐
	var tw = create_tween().set_ignore_time_scale(true)
	tw.tween_property(sprite, "scale", sprite.scale * Vector2(1.15, 0.85), 0.3)
	tw.set_parallel(true)
	sprite.modulate.a = 1.0
	tw.tween_property(sprite, "modulate:a", 0.0, 0.15).set_delay(0.15)
	tw.set_parallel(false)
	tw.tween_callback(queue_free)
