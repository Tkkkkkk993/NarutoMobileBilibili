extends TextureProgressBar

## 分割数（至少1）
@export var split_count: int = 1:
	set(value):
		split_count = max(value, 1)
		_update_dividers()

## 分布范围总宽度（像素），0 表示使用自身宽度
@export var range_width: float = 0.0:
	set(value):
		range_width = value
		_update_dividers()

## 分割条使用的纹理
@export var divider_texture: Texture2D:
	set(value):
		divider_texture = value
		_update_dividers()

## 分割条缩放倍数（基于纹理原始尺寸）
@export var divider_scale: float = 1.0:
	set(value):
		divider_scale = max(value, 0.01)
		_update_dividers()

# 缓存分割条节点，便于更新
var _divider_nodes: Array[TextureRect] = []


func _ready():
	_update_dividers()

## 更新所有分割条
func _update_dividers():
	# 清除旧分割条
	for node in _divider_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_divider_nodes.clear()

	var count = split_count
	if count <= 1:
		return  # 不需要分割条

	# 确定分布范围宽度（使用自身 size.x）
	var total_width = range_width if range_width > 0 else size.x
	if total_width <= 0:
		return

	var left_x = 0.0  # 相对于自身左上角
	var step = total_width / count
	var center_y = size.y / 2.0

	for i in range(count - 1):
		var pos_x = left_x + (i + 1) * step

		# 创建分割条 TextureRect
		var rect = TextureRect.new()
		rect.texture = divider_texture

		# 确定分割条尺寸
		if divider_texture:
			var tex_size = divider_texture.get_size()
			rect.size = tex_size * divider_scale
		else:
			# 无纹理时使用默认纯色条
			var image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			var tex = ImageTexture.create_from_image(image)
			rect.texture = tex
			rect.size = Vector2(10, 30) * divider_scale  # 默认尺寸

		rect.position = Vector2(
			pos_x - rect.size.x / 2.0,
			center_y - rect.size.y / 2.0
		)

		add_child(rect)
		_divider_nodes.append(rect)


### 手动刷新
#func _input(event):
	#if event is InputEventKey and event.pressed and event.keycode == KEY_U:
		#_update_dividers()
