extends TouchScreenButton

# ========== 动画设置（移植自 SkillSlot） ==========
@export_group("动画设置")
@export var press_scale: float = 0.9
@export var anim_duration: float = 0.3
@export_enum("Elastic:0", "Smooth:1") var anim_style: int = 0

# ========== 内部变量 ==========
var current_tween: Tween = null
var _pending_texture: Texture2D = null
var o_scale

var _pressed: bool = false
var is_just_pressed: bool = false

@onready var vis: Sprite2D  = $"../Icon"

func _ready():
	if vis:
		press_scale *= vis.scale.x
		o_scale = vis.scale

func _on_button_pressed():
	_pressed = true
	is_just_pressed = true
	
	if current_tween and current_tween.is_running():
		current_tween.kill()
	
	current_tween = create_tween()
	
	var trans_type = Tween.TRANS_ELASTIC if anim_style == 0 else Tween.TRANS_QUAD
	
	current_tween.tween_property(vis, "scale", Vector2(press_scale, press_scale), anim_duration)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(trans_type)

func _on_button_released():
	_pressed = false
	if current_tween and current_tween.is_running():
		current_tween.kill()
		
	current_tween = create_tween()
	
	# 【核心修改2】：根据 anim_style 决定过渡曲线
	var trans_type = Tween.TRANS_ELASTIC if anim_style == 0 else Tween.TRANS_QUAD
	
	# 【核心修改3】：弹回时使用 EASE_OUT，而不是原来的 EASE_IN
	# EASE_OUT 配合 ELASTIC 会有非常完美的“果冻弹回”效果
	current_tween.tween_property(vis, "scale", o_scale, anim_duration)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(trans_type)

func set_texture(t: Texture2D):
	texture_normal = t
	if vis:
		vis.texture = texture_normal
	else:
		# 防止 _ready 还没执行时的 Nil 报错
		_pending_texture = t

func consume_press() -> bool:
	if is_just_pressed:
		is_just_pressed = false  # 取走后立刻设为 false，防止下一帧再触发
		return true
	return false
