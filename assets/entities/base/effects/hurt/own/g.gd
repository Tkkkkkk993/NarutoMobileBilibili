extends EffectBase

@onready var digit = $DigitDisplay

func _ready():
	visible = true
	set_meta("sort_by_depth", true)
	DepthManager.bring_to_top(self)
	
	var damage = extra_data.get("damage", 0)
	digit.set_text(str(damage))
	
	scale = Vector2(0.01, 0.01)
	
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1, 1), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var start_z = pos_3d.z
	tween.tween_property(self, "pos_3d:z", start_z - 60, 0.2).set_delay(0.5).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.2).set_delay(0.5)
	tween.finished.connect(queue_free)
