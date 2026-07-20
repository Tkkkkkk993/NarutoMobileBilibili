class_name VirtualJoystick
extends Control

## 简易虚拟摇杆，附带实用选项。
## 项目地址：https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot

# 导出变量

## 摇杆按下时按钮的颜色。
@export var pressed_color := Color.GRAY

## 输入在此范围内时输出为零。
@export_range(0, 200, 1) var deadzone_size : float = 12

## 摇杆头可到达的最大距离。
@export_range(0, 500, 1) var clampzone_size : float = 55

enum Joystick_mode {
	FIXED,     ## 位置固定。
	DYNAMIC,   ## 每次触摸时移动到触摸位置。
	FOLLOWING  ## 手指移出摇杆区域时跟随移动。
}

## 摇杆模式：固定 / 触摸时出现 / 仅在触摸时显示。
@export var joystick_mode := Joystick_mode.FIXED

enum Visibility_mode {
	ALWAYS,            ## 始终可见。
	TOUCHSCREEN_ONLY,  ## 仅触摸屏可见。
	WHEN_TOUCHED       ## 仅在触摸时可见。
}

## 可见性模式：始终 / 仅触摸屏 / 仅触摸时。
@export var visibility_mode := Visibility_mode.ALWAYS

## 启用输入动作（项目设置 → 输入映射）。
@export var use_input_actions := true

@export var action_left := "ui_left"
@export var action_right := "ui_right"
@export var action_up := "ui_up"
@export var action_down := "ui_down"

# 公共变量

## 是否正在接收输入。
var is_pressed := false

## 输出值（范围 -1..1）。
var output := Vector2.ZERO

# 私有变量

var _touch_index : int = -1
var _use_mouse_events : bool = false   # 是否模拟鼠标事件
var _mouse_pressed : bool = false      # 鼠标左键是否按下

@onready var _base := $Base
@onready var _tip := $Base/Tip

@onready var _base_default_position : Vector2 = _base.position
@onready var _tip_default_position : Vector2 = _tip.position

@onready var _default_color : Color = _tip.modulate

# 视觉效果相关
@onready var _normal_base_scale := Vector2.ONE
@onready var _pressed_base_scale := Vector2(1.2, 1.2)          # 底盘放大120%
@onready var _normal_tip_scale := Vector2.ONE
@onready var _pressed_tip_scale := Vector2(1.0 / 1.2, 1.0 / 1.2)  # 摇杆头反向缩小，保持视觉大小不变
@onready var _normal_modulate := Color(1, 1, 1, 1)
@onready var _pressed_modulate := Color(1, 1, 1, 0.9)

# 函数

func _ready() -> void:
	# 缩放时保持中心位置不变
	_base.pivot_offset = _base.size / 2
	
	# 决定使用鼠标还是触摸事件
	_use_mouse_events = ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch")
	# 自动适配，不输出错误
	
	if not DisplayServer.is_touchscreen_available() and visibility_mode == Visibility_mode.TOUCHSCREEN_ONLY :
		hide()
	
	if visibility_mode == Visibility_mode.WHEN_TOUCHED:
		hide()
	
	# 初始状态为未激活，应用虚化效果
	_deactivate_visuals()

func _input(event: InputEvent) -> void:
	if _use_mouse_events:
		_handle_mouse_events(event)
	else:
		_handle_touch_events(event)

func _handle_touch_events(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _is_point_inside_joystick_area(event.position) and _touch_index == -1:
				if joystick_mode == Joystick_mode.DYNAMIC or joystick_mode == Joystick_mode.FOLLOWING or (joystick_mode == Joystick_mode.FIXED and _is_point_inside_base(event.position)):
					if joystick_mode == Joystick_mode.DYNAMIC or joystick_mode == Joystick_mode.FOLLOWING:
						_move_base(event.position)
					if visibility_mode == Visibility_mode.WHEN_TOUCHED:
						show()
					_touch_index = event.index
					_activate_visuals()   # 激活视觉效果：底盘放大 + 摇杆头反向缩放 + 实化
					_update_joystick(event.position)
					get_viewport().set_input_as_handled()
		elif event.index == _touch_index:
			_reset()
			if visibility_mode == Visibility_mode.WHEN_TOUCHED:
				hide()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_update_joystick(event.position)
			get_viewport().set_input_as_handled()

func _handle_mouse_events(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_point_inside_joystick_area(event.position) and not _mouse_pressed:
					if joystick_mode == Joystick_mode.DYNAMIC or joystick_mode == Joystick_mode.FOLLOWING or (joystick_mode == Joystick_mode.FIXED and _is_point_inside_base(event.position)):
						if joystick_mode == Joystick_mode.DYNAMIC or joystick_mode == Joystick_mode.FOLLOWING:
							_move_base(event.position)
						if visibility_mode == Visibility_mode.WHEN_TOUCHED:
							show()
						_mouse_pressed = true
						_activate_visuals()
						_update_joystick(event.position)
						get_viewport().set_input_as_handled()
			else:
				if _mouse_pressed:
					_reset()
					if visibility_mode == Visibility_mode.WHEN_TOUCHED:
						hide()
					_mouse_pressed = false
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _mouse_pressed:
			_update_joystick(event.position)
			get_viewport().set_input_as_handled()

## 移动摇杆底盘到指定位置（全局坐标）
func _move_base(new_position: Vector2) -> void:
	_base.global_position = new_position - _base.pivot_offset * get_global_transform_with_canvas().get_scale()

## 移动摇杆头到指定位置（全局坐标）
func _move_tip(new_position: Vector2) -> void:
	_tip.global_position = new_position - _tip.pivot_offset * _base.get_global_transform_with_canvas().get_scale()

## 判断点是否在摇杆触摸区域内
func _is_point_inside_joystick_area(point: Vector2) -> bool:
	var x: bool = point.x >= global_position.x and point.x <= global_position.x + (size.x * get_global_transform_with_canvas().get_scale().x)
	var y: bool = point.y >= global_position.y and point.y <= global_position.y + (size.y * get_global_transform_with_canvas().get_scale().y)
	return x and y

## 获取摇杆底盘半径（考虑全局缩放）
func _get_base_radius() -> Vector2:
	return _base.size * _base.get_global_transform_with_canvas().get_scale() / 2

## 判断点是否在摇杆底盘内部
func _is_point_inside_base(point: Vector2) -> bool:
	var _base_radius = _get_base_radius()
	var center : Vector2 = _base.global_position + _base_radius
	var vector : Vector2 = point - center
	return vector.length_squared() <= _base_radius.x * _base_radius.x

## 根据触摸位置更新摇杆输出值和视觉位置
func _update_joystick(touch_position: Vector2) -> void:
	var _base_radius = _get_base_radius()
	var center : Vector2 = _base.global_position + _base_radius
	var vector : Vector2 = touch_position - center
	vector = vector.limit_length(clampzone_size)
	
	if joystick_mode == Joystick_mode.FOLLOWING and touch_position.distance_to(center) > clampzone_size:
		_move_base(touch_position - vector)
	
	_move_tip(center + vector)
	
	if vector.length_squared() > deadzone_size * deadzone_size:
		is_pressed = true
		output = (vector - (vector.normalized() * deadzone_size)) / (clampzone_size - deadzone_size)
	else:
		is_pressed = false
		output = Vector2.ZERO
	
	if use_input_actions:
		# 释放动作
		if output.x >= 0 and Input.is_action_pressed(action_left):
			Input.action_release(action_left)
		if output.x <= 0 and Input.is_action_pressed(action_right):
			Input.action_release(action_right)
		if output.y >= 0 and Input.is_action_pressed(action_up):
			Input.action_release(action_up)
		if output.y <= 0 and Input.is_action_pressed(action_down):
			Input.action_release(action_down)
		# 按下动作
		if output.x < 0:
			Input.action_press(action_left, -output.x)
		if output.x > 0:
			Input.action_press(action_right, output.x)
		if output.y < 0:
			Input.action_press(action_up, -output.y)
		if output.y > 0:
			Input.action_press(action_down, output.y)

## 重置摇杆状态（触摸结束时调用）
func _reset():
	is_pressed = false
	output = Vector2.ZERO
	_touch_index = -1
	_mouse_pressed = false
	_base.position = _base_default_position
	_tip.position = _tip_default_position
	_deactivate_visuals()   # 恢复虚化效果、底盘原始大小和摇杆头原始大小
	# 释放所有输入动作
	if use_input_actions:
		for action in [action_left, action_right, action_down, action_up]:
			if Input.is_action_pressed(action):
				Input.action_release(action)

## 激活视觉效果（按下时）：底盘放大，摇杆头反向缩放保持视觉大小不变，整个控件实化（不透明）
func _activate_visuals() -> void:
	_base.scale = _pressed_base_scale
	_tip.scale = _pressed_tip_scale
	_base.modulate = _pressed_modulate
	_tip.modulate = pressed_color   # 摇杆头使用按下颜色

## 取消视觉效果（释放时）：底盘恢复原始大小，摇杆头恢复原始大小，整个控件虚化（半透明）
func _deactivate_visuals() -> void:
	_base.scale = _normal_base_scale
	_tip.scale = _normal_tip_scale
	_base.modulate = _normal_modulate
	_tip.modulate = _default_color   # 恢复摇杆头默认颜色
