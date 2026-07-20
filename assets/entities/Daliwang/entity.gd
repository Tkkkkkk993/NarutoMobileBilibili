extends AnimatedSprite2DEntity
class_name 大力王

func _ready():
	res_path = "res://assets/entities/Daliwang/main.tres"
	super._ready()
	effects_container.register_effects({
		"ssn": preload("res://assets/entities/test_3d/effects_3d.tscn"),
	})
