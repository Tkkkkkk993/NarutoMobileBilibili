extends EffectBase

@onready var digit = $DigitDisplay

func _ready():
	visible = true
	set_meta("sort_by_depth", true)
	DepthManager.bring_to_top(self)
	
	var damage = extra_data.get("damage", 0)
	var kv_val = extra_data.get("kv", 0.0)
	digit.set_text(str(damage))
	
	var tween = create_tween()
	tween.set_parallel(true)
	var start_p = pos_3d
	var horiz = kv_val * 0.15
	tween.tween_method(func(t: float):
		pos_3d.x = start_p.x + horiz * t
		pos_3d.z = start_p.z - 40.0 * sin(t * PI)
	, 0.0, 1.0, 0.6)
	tween.tween_property(self, "modulate:a", 0.0, 0.3).set_delay(0.3)
	tween.finished.connect(queue_free)
