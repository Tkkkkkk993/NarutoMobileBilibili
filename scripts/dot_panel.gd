extends Control

@export var full_texture: Texture2D = preload("res://assets/UI/dot_1.png")
@export var empty_texture: Texture2D = preload("res://assets/UI/dot_0.png")
@onready var dot_texture_rects: Array[TextureRect] = [$Dot1, $Dot2, $Dot3, $Dot4]

const dot_4_pos: Array[Vector2] = [
	Vector2(-6, 62),
	Vector2(17, 55),
	Vector2(40, 45),
	Vector2(57, 30)
]

const dot_3_pos: Array[Vector2] = [
	Vector2(7, 63),
	Vector2(33, 49),
	Vector2(55, 31)
]

var max_dot: int = 4 :
	set(value):
		max_dot = clampi(value, 0, dot_texture_rects.size())
		# 如果当前点数超过新的上限，自动削减
		if _dot > max_dot:
			_dot = max_dot
		update_dots()

var _dot: int = 0 :
	set(value):
		_dot = clampi(value, 0, max_dot)
		update_dots()

func _ready():
	update_dots()

func update_dots():
	for i in dot_texture_rects.size():
		var rect = dot_texture_rects[i]
		if i >= max_dot:
			# 索引超过上限，隐藏该槽位
			rect.visible = false
		else:
			# 在可用范围内，显示并根据 _dot 设置纹理
			rect.visible = true
			rect.texture = full_texture if i < _dot else empty_texture
			if max_dot == 4:
				dot_texture_rects[i].position = dot_4_pos[i]
			elif max_dot == 3:
				dot_texture_rects[i].position = dot_3_pos[i]
