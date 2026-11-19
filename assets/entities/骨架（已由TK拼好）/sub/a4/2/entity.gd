extends AnimatedSprite2DEntity
class_name 须佐佐助_a4刀

func _ready():
	res_path = "res://assets/entities/骨架（已由TK拼好）/sub/a4/2/main.tres"
	super._ready()

func _post_init():
	play_animation("idle")
	_apply_frame_data_forced("idle", 0)
	_process_effect_bindings("idle", 0)

func _process(delta):
	super._process(delta)
	if shadow_node and visuals_node:
		shadow_node.self_modulate.a = visuals_node.modulate.a

func die():
	if is_queued_for_deletion():
		return
	if is_instance_valid(parent_entity):
		var owner_script := parent_entity.get_node_or_null("VisualScriptComponent") as VisualScriptComponent
		if owner_script and is_same(owner_script._vs_get_variable("刀实体"), self):
			owner_script._vs_set_variable("刀实体", false)
	super.die()
