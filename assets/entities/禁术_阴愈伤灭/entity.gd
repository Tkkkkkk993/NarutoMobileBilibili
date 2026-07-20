extends AnimatedSprite2DEntity

func _ready():
	res_path = "res://assets/entities/禁术_阴愈伤灭/main.tres"
	enable_wall_collision = false
	aux_cd_value = 0
	super._ready()
	is_invincible = true

func _post_init():
	await get_tree().create_timer(0.1).timeout
	
	parent_entity.set_modifiers("addBodyState", BodyState.SUPER_ARMOR, 5)
	
	die()
