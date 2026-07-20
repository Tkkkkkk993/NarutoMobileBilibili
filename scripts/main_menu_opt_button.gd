extends Button

@onready var background: Control = $"../Background"

var original_font_size: float = 0.0
var target_font_size: float = 0.0
var current_font_size: float = 0.0

func _ready():
	original_font_size = get_theme_font_size("font_size")
	current_font_size = original_font_size
	target_font_size = original_font_size

	if background:
		background.modulate.a = 0.0
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	pressed.connect(_on_pressed)

func _on_pressed():
	release_focus()

func _process(_delta):
	var is_active = is_hovered() or has_focus()
	target_font_size = original_font_size * (1.2 if is_active else 1.0)

	# 背景透明度直接根据状态立即切换，无过渡
	if background:
		background.modulate.a = 1.0 if is_active else 0.0

	# 字体大小保持平滑动画
	var speed = 0.08
	if abs(current_font_size - target_font_size) > 0.01:
		current_font_size = lerp(current_font_size, target_font_size, speed)
		add_theme_font_size_override("font_size", int(round(current_font_size)))
