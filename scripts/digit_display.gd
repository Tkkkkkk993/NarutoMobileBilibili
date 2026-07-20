extends Node2D
class_name DigitDisplay

# 静态缓存：同纹理+字符集配置只计算一次
static var _atlas_cache: Dictionary = {}

# 纹理（必须启用"可读"属性）
@export var texture: Texture2D :
	set(value):
		texture = value
		if is_inside_tree():
			_update_char_data()
# 字符集字符串
@export var char_set: String = "0123456789" :
	set(value):
		char_set = value
		if is_inside_tree():
			_update_char_data()
# 每行字符数
@export var columns: int = 10 :
	set(value):
		columns = value
		if is_inside_tree():
			_update_char_data()
# 总行数
@export var rows: int = 1 :
	set(value):
		rows = value
		if is_inside_tree():
			_update_char_data()
# 字符间额外间距
@export var spacing: int = 0
# 对齐方式：0左对齐，1居中，2右对齐
@export var alignment: int = 0
# 整体缩放倍数
@export var scale_factor: float = 1.0

var _char_regions: Dictionary = {}
var _char_widths: Dictionary = {}
var _is_data_valid: bool = false

func _ready():
	_update_char_data()

static func prewarm(texture: Texture2D, char_set: String, columns: int, rows: int) -> void:
	var key = texture.resource_path + "|" + char_set + "|" + str(columns) + "|" + str(rows)
	if _atlas_cache.has(key):
		return
	var img = texture.get_image()
	if not img:
		return
	var regions = {}
	var widths = {}
	_static_scan(img, char_set, columns, rows, regions, widths)
	_atlas_cache[key] = {regions = regions, widths = widths}

static func _static_scan(img: Image, char_set: String, columns: int, rows: int, regions: Dictionary, widths: Dictionary):
	var img_w = img.get_width()
	var img_h = img.get_height()
	var cell_w = img_w / float(columns)
	var cell_h = img_h / float(rows)
	for i in char_set.length():
		var ch = char_set[i]
		var col = i % columns
		var row = i / columns
		var sx = int(col * cell_w)
		var ex = mini(int((col + 1) * cell_w), img_w)
		var sy = int(row * cell_h)
		var ey = mini(int((row + 1) * cell_h), img_h)
		var rect = Rect2(sx, sy, ex - sx, ey - sy)
		var region = _static_find_region(img, rect)
		regions[ch] = region
		widths[ch] = region.size.x

static func _static_find_region(img: Image, cell_rect: Rect2) -> Rect2:
	var min_x = int(cell_rect.size.x)
	var max_x = 0
	var min_y = int(cell_rect.size.y)
	var max_y = 0
	var found = false
	for x in range(int(cell_rect.position.x), int(cell_rect.end.x)):
		for y in range(int(cell_rect.position.y), int(cell_rect.end.y)):
			if img.get_pixel(x, y).a > 0:
				found = true
				var lx = x - cell_rect.position.x
				var ly = y - cell_rect.position.y
				if lx < min_x: min_x = lx
				if lx > max_x: max_x = lx
				if ly < min_y: min_y = ly
				if ly > max_y: max_y = ly
	if not found:
		return Rect2(cell_rect.position + cell_rect.size / 2.0, Vector2(1, 1))
	return Rect2(cell_rect.position.x + min_x, cell_rect.position.y + min_y, max_x - min_x + 1, max_y - min_y + 1)

func _get_cache_key() -> String:
	return texture.resource_path + "|" + char_set + "|" + str(columns) + "|" + str(rows)

func _update_char_data():
	_char_regions.clear()
	_char_widths.clear()
	_is_data_valid = false
	
	if not texture or char_set.is_empty() or columns <= 0 or rows <= 0:
		return
	
	var key = _get_cache_key()
	if _atlas_cache.has(key):
		_char_regions = _atlas_cache[key].regions.duplicate()
		_char_widths = _atlas_cache[key].widths.duplicate()
		_is_data_valid = true
		return
	
	var img = texture.get_image()
	if not img:
		push_error("无法获取纹理图像数据，请确保纹理启用了\"可读\"属性。")
		_use_fallback_regions()
		return
	
	_calculate_char_regions(img)
	
	_atlas_cache[key] = {regions = _char_regions.duplicate(), widths = _char_widths.duplicate()}

func _calculate_char_regions(img: Image):
	var img_w = img.get_width()
	var img_h = img.get_height()
	var cell_width = img_w / float(columns)
	var cell_height = img_h / float(rows)
	
	for i in range(char_set.length()):
		var ch = char_set[i]
		var col = i % columns
		var row = i / columns
		
		# 优化1：绝对安全的边界计算，彻底解决越界报错
		var start_x = int(col * cell_width)
		var end_x = mini(int((col + 1) * cell_width), img_w)
		var start_y = int(row * cell_height)
		var end_y = mini(int((row + 1) * cell_height), img_h)
		
		var cell_rect = Rect2(start_x, start_y, end_x - start_x, end_y - start_y)
		var region = _find_content_region(img, cell_rect)
		
		_char_regions[ch] = region
		_char_widths[ch] = region.size.x
		
	_is_data_valid = true

func _find_content_region(img: Image, cell_rect: Rect2) -> Rect2:
	var min_x = int(cell_rect.size.x)
	var max_x = 0
	var min_y = int(cell_rect.size.y)
	var max_y = 0
	var found = false
	
	# 优化2：直接用算好的安全边界遍历，不再依赖可能越界的加法
	for x in range(int(cell_rect.position.x), int(cell_rect.end.x)):
		for y in range(int(cell_rect.position.y), int(cell_rect.end.y)):
			if img.get_pixel(x, y).a > 0:
				found = true
				var local_x = x - cell_rect.position.x
				var local_y = y - cell_rect.position.y
				if local_x < min_x: min_x = local_x
				if local_x > max_x: max_x = local_x
				if local_y < min_y: min_y = local_y
				if local_y > max_y: max_y = local_y
	
	if not found:
		return Rect2(cell_rect.position + cell_rect.size / 2.0, Vector2(1, 1))
	else:
		return Rect2(
			cell_rect.position.x + min_x,
			cell_rect.position.y + min_y,
			max_x - min_x + 1,
			max_y - min_y + 1
		)

func _use_fallback_regions():
	var cell_width = texture.get_width() / columns
	var cell_height = texture.get_height() / rows
	for i in range(char_set.length()):
		var ch = char_set[i]
		var col = i % columns
		var row = i / columns
		var region = Rect2(col * cell_width, row * cell_height, cell_width, cell_height)
		_char_regions[ch] = region
		_char_widths[ch] = cell_width
	_is_data_valid = true

func set_text(value: String):
	# 优化3：场景切换时的绝对防御，防止疯狂报错
	if not is_inside_tree() or not _is_data_valid:
		return
		
	# 计算总宽度用于对齐
	var total_width = 0
	for ch in value:
		if _char_widths.has(ch):
			total_width += _char_widths[ch] + spacing
	if value.length() > 0:
		total_width -= spacing
		
	var start_x = 0.0
	match alignment:
		1: start_x = -total_width / 2.0
		2: start_x = -float(total_width)
		
	var current_x = start_x
	var child_index = 0
	var children = get_children()
	
	# 优化4：对象池复用
	# 不再频繁 new() 和 queue_free()，而是复用现有的 Sprite2D
	for i in range(value.length()):
		var ch = value[i]
		if not _char_regions.has(ch):
			continue
			
		var region = _char_regions[ch]
		var sprite: Sprite2D
		
		# 如果有闲置的旧节点，直接拿来用
		if child_index < children.size():
			sprite = children[child_index]
			sprite.visible = true
		else:
			# 如果不够，才新建一个
			sprite = Sprite2D.new()
			add_child(sprite)
			children.append(sprite)
			
		# 更新属性
		sprite.texture = texture
		sprite.region_enabled = true
		sprite.region_rect = region
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.position = Vector2(current_x + region.size.x / 2.0, 0)
		
		current_x += region.size.x + spacing
		child_index += 1
		
	# 把多余没用到的字符节点隐藏起来（而不是销毁，留着下次用）
	for i in range(child_index, children.size()):
		children[i].visible = false
