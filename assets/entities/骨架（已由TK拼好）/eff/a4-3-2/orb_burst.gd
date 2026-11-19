extends EffectBase

var _burst_depth := Vector3.ZERO

func _update_follow_position():
	if not is_instance_valid(_follow_target):
		return
	var orb := _follow_target as EntityBase
	var effects_layer := get_parent() as Node2D
	var offset := Vector2(_follow_offset.x, _follow_offset.y)
	position = effects_layer.to_local(orb.to_global(offset))
	_burst_depth = orb.get_depth_pos()
	_burst_depth.y += _follow_offset.z
	pos_3d = Vector3(position.x, position.y - _burst_depth.y, _burst_depth.y)

func _process(delta):
	super._process(delta)
	if not _was_hit_stop:
		_update_follow_position()

func get_depth_pos() -> Vector3:
	return _burst_depth
