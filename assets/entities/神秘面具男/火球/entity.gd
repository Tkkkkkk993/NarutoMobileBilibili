extends AnimatedSprite2DEntity
class_name 火球

func _ready():
	res_path = "res://assets/entities/神秘面具男/火球/main.tres"
	super._ready()
	effects_container.register_effects({
		"baozha": preload("res://assets/entities/神秘面具男/虎皮4a(1)特效/起爆符爆炸/effects_base.tscn"),
	})
