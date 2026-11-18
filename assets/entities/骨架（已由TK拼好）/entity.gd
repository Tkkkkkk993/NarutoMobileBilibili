extends AnimatedSprite2DEntity
class_name 须佐佐助

func _ready():
	res_path = "res://assets/entities/骨架（已由TK拼好）/main.tres"
	super._ready()
	effects_container.register_effect("骨架_s1_铠甲消散", preload("res://assets/entities/骨架（已由TK拼好）/eff/s1/n/effects_base.tscn"), true)
