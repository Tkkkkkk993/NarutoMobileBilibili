extends AnimatedSprite2DEntity
class_name 神秘面具男

func _ready():
	res_path = "res://assets/entities/神秘面具男/main.tres"
	super._ready()
	effects_container.register_effects({
		"out": preload("res://assets/entities/神秘面具男/虎皮4a(1)特效/反过来的（放出特效）/effects_base.tscn"),
		})
