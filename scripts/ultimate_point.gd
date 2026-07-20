extends Control

@export var full_texture: Texture2D = preload("res://assets/UI/ultimate_point_1.png")
@export var full_plus_texture: Texture2D = preload("res://assets/UI/ultimate_point_2.png")
@export var empty_texture: Texture2D = preload("res://assets/UI/ultimate_point_0.png")
@onready var point_texture_rects: Array[TextureRect] = [$Point1, $Point2, $Point3, $Point4, $Point5, $Point6, $Point7, $Point8, $Point9, $Point10, $Point11, $Point12]

@export var max_point: int = 4 :
	set(value):
		max_point = clampi(value, 0, point_texture_rects.size())
		# 如果当前点数超过新的上限，自动削减
		if point > max_point:
			point = max_point
		update_points()

@export var point: int = 0 :
	set(value):
		point = clampi(value, 0, max_point)
		update_points()

func _ready():
	update_points()

func update_points():
	for i in point_texture_rects.size():
		var rect = point_texture_rects[i]
		if i >= max_point:
			# 索引超过上限，隐藏该槽位
			rect.visible = false
		else:
			# 在可用范围内，显示并根据 _point 设置纹理
			rect.visible = true
			if point >= max_point: rect.texture = full_plus_texture
			else: rect.texture = full_texture if i < point else empty_texture
