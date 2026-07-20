extends Area2D
class_name Joystick

## 摇杆最大半径（像素，自动从背景图片计算）
var max_radius: float
## 死区（0~1，输出值小于此范围时归零）
@export var dead_zone: float = 0.2

@onready var background: TextureRect = $Background
@onready var handle: TextureRect = $Handle

var _pressed: bool = false
var _touch_index: int = -1
var _value: Vector2 = Vector2.ZERO
var _bg_center: Vector2          # 背景中心（相对于 Area2D 的局部坐标）

signal value_changed(new_value: Vector2)


func _ready():
	input_pickable = true
	_update_background_geometry()
	_reset()


## 动态获取背景的真实圆心和半径（自动适应缩放、锚点）
func _update_background_geometry():
	# 背景在 Area2D 局部坐标系中的矩形区域
	var bg_rect = Rect2(background.position, background.size)
	_bg_center = bg_rect.get_center() / 2
	
	# 视觉半径（取宽高中较小的一半，适合圆形背景）
	var visual_radius = min(bg_rect.size.x, bg_rect.size.y) / 2.0
	
	# 如果 Area2D 自身有缩放，逻辑半径也需要按比例缩放
	# 因为后续 to_local() 得到的坐标已经包含了 Area2D 的 scale 影响
	max_radius = visual_radius / scale.x   # 假设 x/y 缩放相同，否则取平均值


func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int):
	if event is InputEventScreenTouch:
		if event.pressed:
			_pressed = true
			_touch_index = event.index
			_update_handle(event.position)
			get_viewport().set_input_as_handled()
		else:
			if event.index == _touch_index:
				_reset()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _pressed and event.index == _touch_index:
		_update_handle(event.position)
		get_viewport().set_input_as_handled()


func _update_handle(screen_pos: Vector2):
	# 将屏幕坐标转换为 Area2D 的局部坐标
	var local_pos = to_local(screen_pos)
	# 相对于背景圆心的偏移
	var offset = local_pos - _bg_center
	var distance = offset.length()
	
	var direction = Vector2.ZERO
	if distance > 0:
		direction = offset / distance
	
	# 限制半径
	if distance > max_radius:
		offset = direction * max_radius
	
	# 【关键】手柄的位置 = 背景中心 + 限制后的偏移
	handle.position = _bg_center + offset
	
	# 计算输出值（单位向量 * 强度，带死区）
	var raw = offset / max_radius
	if raw.length() < dead_zone:
		_value = Vector2.ZERO
	else:
		# 将 [dead_zone, 1] 映射到 [0, 1]
		var normalized_len = (raw.length() - dead_zone) / (1.0 - dead_zone)
		_value = direction * normalized_len
	
	emit_signal("value_changed", _value)


func _reset():
	_pressed = false
	_touch_index = -1
	_value = Vector2.ZERO
	handle.position = _bg_center
	emit_signal("value_changed", _value)


## 获取当前摇杆值（单位向量，范围 0~1）
func get_value() -> Vector2:
	return _value


## 是否正在被触摸
func is_pressed() -> bool:
	return _pressed
