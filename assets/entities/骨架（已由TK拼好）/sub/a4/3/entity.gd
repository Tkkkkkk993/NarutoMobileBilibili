extends AnimatedSprite2DEntity
class_name 须佐佐助_a4雷球

var _burst_played := false

func _ready():
	res_path = "res://assets/entities/骨架（已由TK拼好）/sub/a4/3/main.tres"
	super._ready()

func _post_init():
	play_animation("idle")
	await get_tree().create_timer(10.0).timeout
	die()

func get_blade_target() -> EntityBase:
	if not is_instance_valid(parent_entity):
		return null
	var owner_script := parent_entity.get_node_or_null("VisualScriptComponent") as VisualScriptComponent
	if not owner_script:
		return null
	var blade = owner_script._vs_get_variable("刀实体")
	if typeof(blade) != TYPE_OBJECT or not is_instance_valid(blade) or not blade is EntityBase or blade.is_queued_for_deletion():
		return null
	return blade if blade.parent_entity == parent_entity and blade.title == "扎刀" else null

func _process_effect_bindings(anim_name: String, frame_idx: int):
	if anim_name == "attack" and frame_idx == 0:
		if _burst_played:
			return
		_burst_played = true
	super._process_effect_bindings(anim_name, frame_idx)
