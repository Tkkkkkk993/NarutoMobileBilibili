extends Button

# ========== 动画参数 ==========
@export var press_scale: float = 0.9
@export var anim_duration: float = 0.5
@export_enum("弹性 (Elastic):0", "平滑 (Smooth):1") var anim_style: int = 0

var _tween: Tween
var _base_scale: Vector2  # 用来记住你在编辑器里设置的拉伸形状

func _ready():
	# 记录节点最初始的缩放值（比如你在编辑器设的 1.2, 0.8）
	_base_scale = scale
	position -= size / 2 * scale
	
	button_down.connect(_on_pressed)
	button_up.connect(_on_released)
	
	call_deferred("_setup_pivot")

func _setup_pivot():
	pivot_offset = size / 2

func _on_pressed():
	_kill_tween()
	_tween = create_tween()
	var trans = Tween.TRANS_ELASTIC if anim_style == 0 else Tween.TRANS_QUAD
	# 基于初始拉伸形状，进行等比例缩小
	var target_scale = _base_scale * press_scale 
	_tween.tween_property(self, "scale", target_scale, anim_duration)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(trans)

func _on_released():
	_kill_tween()
	_tween = create_tween()
	var trans = Tween.TRANS_ELASTIC if anim_style == 0 else Tween.TRANS_QUAD
	# 松手时，准确回到你在编辑器里设置的拉伸形状，而不是 Vector2.ONE
	_tween.tween_property(self, "scale", _base_scale, anim_duration)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(trans)

func _kill_tween():
	if _tween and _tween.is_running():
		_tween.kill()
