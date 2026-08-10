extends AnimatedSprite2DEntity
class_name 须佐佐助_a4雷球

func _ready():
	res_path = "res://assets/entities/骨架（已由TK拼好）/sub/a4/3/main.tres"
	super._ready()

func _post_init():
	play_animation("idle")
	await get_tree().create_timer(10.0).timeout
	die()
