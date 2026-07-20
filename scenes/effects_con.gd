extends Node2D
class_name EffectsContainerBase

var _effect_scenes: Dictionary = {}

func register_effect(effect_name: String, scene: PackedScene, allow_overwrite: bool = false) -> bool:
	if _effect_scenes.has(effect_name) and not allow_overwrite:
		push_warning("特效名称 '%s' 已存在，若要覆盖请设置 allow_overwrite=true" % effect_name)
		return false
	_effect_scenes[effect_name] = scene
	return true

func register_effects(effects_dict: Dictionary, allow_overwrite: bool = false):
	for key in effects_dict:
		register_effect(key, effects_dict[key], allow_overwrite)

# 生成固定位置特效（增加 flip_h、data 参数）
func spawn_effect(effect_name: String, world_pos_3d: Vector3, flip_h: bool = false, data: Dictionary = {}) -> Node2D:
	var scene = _effect_scenes.get(effect_name)
	if scene == null:
		push_error("未注册的特效名称: ", effect_name)
		return null
	var effect = scene.instantiate()
	effect.pos_3d = Vector3(world_pos_3d.x, world_pos_3d.y, world_pos_3d.z)
	if not data.is_empty():
		effect.extra_data = data
	add_child(effect)
	if flip_h:
		effect.set_flip_h(true)
	return effect

# 生成跟随特效
func spawn_follow_effect(effect_name: String, target: Node, offset: Vector3 = Vector3.ZERO, initial_pos: bool = true, flip_h: bool = false, data: Dictionary = {}) -> Node2D:
	var scene = _effect_scenes.get(effect_name)
	if scene == null:
		push_error("未注册的特效名称: ", effect_name)
		return null
	
	if not target or not target.has_method("get_position_3d"):
		push_error("spawn_follow_effect: 目标必须实现 get_position_3d() 方法")
		return null
	
	var effect = scene.instantiate()
	
	if initial_pos:
		effect.pos_3d = target.get_position_3d() + offset
	else:
		effect.pos_3d = Vector3.ZERO
	
	if not data.is_empty():
		effect.extra_data = data
	
	add_child(effect)
	var real_off = offset
	#real_off.y = offset.z
	#real_off.z = offset.y
	effect.set_follow(target, real_off)
	if flip_h:
		effect.set_flip_h(true)
	return effect
