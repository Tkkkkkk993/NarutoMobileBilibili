extends EffectBase

@onready var player = $SubViewportContainer/SubViewport/yandunS02/AnimationPlayer

func _ready():
	visible = true
	set_meta("sort_by_depth", true)
	
	play()

func play():
	player.play("hrn_90313_SKC_09_2")
	await get_tree().create_timer(8.0).timeout
	_on_animation_finished()
