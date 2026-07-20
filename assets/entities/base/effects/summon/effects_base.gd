extends EffectBase

@onready var sprite = $Sprite2D

func _ready():
	visible = true
	set_meta("sort_by_depth", true)
	
	play()

func play():
	var tween = create_tween()
	
	tween.tween_property(sprite, "scale", Vector2(0.8, 0.8), 0.0)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	tween.tween_callback(_on_animation_finished)
