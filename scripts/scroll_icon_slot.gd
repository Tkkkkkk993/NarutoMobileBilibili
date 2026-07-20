extends Control
class_name ScrollIconSlot

@onready var vis_node: Sprite2D = $Icon
@onready var touch: TouchScreenButton = $Touch
@onready var digit_display := $DigitDisplay

@export var num: float = 0 :
	set(value):
		num = value
		if num > 0:
			digit_display.visible = true
			digit_display.set_text(str(int(num)))
		else:
			digit_display.visible = false

var texture_noready: Texture2D

func set_texture(texture: Texture2D) -> void:
	if vis_node:
		vis_node.texture = texture
	else:
		texture_noready = texture

func _ready() -> void:
	vis_node.texture = texture_noready
