extends Area2D
class_name SkillSlot

# ========== 导出变量 ==========
@export_group("纹理")
@export var texture_normal: Texture2D
@export var texture_pressed: Texture2D

@export_group("动画")
@export var press_scale: float = 0.9
@export var anim_duration: float = 0.5
@export_enum("Elastic:0", "Smooth:1") var anim_style: int = 0

@export_group("光环旋转")
@export var aura_rotate_speed: float = 6.0
@export var aura_rotate_on_press: bool = true

@export_group("基本属性")
@export var show_panel: bool = false
@export var show_aura: bool = false
@export var disabled: bool = false

@export_group("预输入配置")
@export var slot_id: int = 0
@export var action_name: String = "attack"
@export var action_priority: int = 1

@export_subgroup("类型设置")
@export var is_charging: bool = false

@export_subgroup("读秒相关")
@export var cool_down_time_now: float = 0 :
	set(value):
		cool_down_time_now = value
		if cool_down_time_now > 0:
			digit_display.visible = true
			digit_display.set_text(str(int(ceil(cool_down_time_now))))
			cd_progress_bar.value = cool_down_time_now / cool_down_time_max * 100
		else:
			digit_display.visible = false
			cd_progress_bar.value = 0
@export var cool_down_time_max: float = 0

@export_subgroup("充能相关")
@export var dot: int = -1 :
	set(value):
		dot = value
		if dot_panel:
			dot_panel._dot = dot
@export var dot_max: int = 4 :
	set(value):
		dot_max = value
		if dot_panel:
			dot_panel.max_dot = dot_max

@export_subgroup("计时相关")
@export var timer_progress: float = 0.0 :
	set(value):
		timer_progress = value
		_update_timer_frame()

# ========== 节点引用 ==========
@onready var visual_sprite     := $Icon
@onready var panel             := $Icon/ButtonPanel
@onready var dot_panel         := $Icon/DotPanelControl
@onready var digit_display     := $DigitDisplay
@onready var collision_shape   := $CollisionShape2D
@onready var timer             := $Icon/Timer
@onready var aura              := $Icon/Aura
@onready var cd_progress_bar   := $Icon/CDProgressBar
@onready var charging_progress := $Icon/ChargingProgress

# ========== 内部变量 ==========
var current_tween: Tween = null
var _button_pressed: bool = false
var _visual_pressed: bool = false
var can_press: bool = true
## 图标自适应缩放基准 (由 set_texture / _ready 计算)
var _base_icon_scale := Vector2.ONE
## 子节点原始缩放值 (首次 _apply_icon_scale 时捕获)
var _child_orig_scales: Dictionary = {}

# ========== 信号 ==========
signal pressed
signal button_released

# ========== 图标缩放 ==========
func _apply_icon_scale():
	if not visual_sprite or not texture_normal:
		return
	_base_icon_scale = Vector2(112, 112) / texture_normal.get_size()
	visual_sprite.scale = _base_icon_scale
	for c in visual_sprite.get_children():
		if not _child_orig_scales.has(c):
			_child_orig_scales[c] = c.scale
		c.scale = _child_orig_scales[c] / _base_icon_scale

# ========== 生命周期 ==========
func _ready():
	if not collision_shape:
		push_error("SkillSlot: 需要 CollisionShape2D 子节点")
		return
	
	if visual_sprite:
		visual_sprite.texture = texture_normal
		_apply_icon_scale()
	
	if panel:
		panel.visible = show_panel
	
	if dot_panel:
		dot_panel.visible = is_charging
		
	if visual_sprite and visual_sprite.material:
		visual_sprite.material = visual_sprite.material.duplicate(true)
		handle_icon_material(false)
	
	if timer:
		timer.stop()
		_update_timer_frame()
	
	if dot_panel:
		dot_panel.max_dot = dot_max
		dot_panel._dot = dot
		dot_panel.update_dots()
	
	if cd_progress_bar:
		cd_progress_bar.value = 0
	
	if charging_progress:
		charging_progress.visible = false

func _process(delta):
	if aura and show_aura:
		aura.visible = true
		aura.rotation += aura_rotate_speed * delta
	else:
		aura.visible = false
	
	_update_shader()

# ========== 由父节点调用的输入回调 ==========
func _press_visual():
	if _visual_pressed:
		return
	
	_visual_pressed = true
	var can_use = _can_press()
	_button_pressed = can_use
	
	_press_animation()
	
	if can_use:
		var buffer = get_node("/root/GlobalInputBuffer")
		if buffer:
			buffer.on_button_pressed(slot_id, action_name, action_priority)
		else:
			emit_signal("pressed")
	else:
		pass

func _release_visual():
	if not _visual_pressed:
		return
	
	_visual_pressed = false
	_button_pressed = false
	
	_release_animation()

# ========== 屏幕空间碰撞检测 ==========
func _is_point_inside_screen(screen_pos: Vector2) -> bool:
	if not collision_shape or not collision_shape.shape:
		return false
	
	var shape = collision_shape.shape
	var center = global_position
	
	if shape is RectangleShape2D:
		var half = shape.extents
		var rect = Rect2(center.x - half.x, center.y - half.y, half.x * 2, half.y * 2)
		return rect.has_point(screen_pos)
	
	elif shape is CircleShape2D:
		return (screen_pos - center).length() <= shape.radius
	
	elif shape is CapsuleShape2D:
		var r = shape.radius
		var h = shape.height / 2
		var local = screen_pos - center
		
		if abs(local.y) <= h:
			return abs(local.x) <= r
		else:
			var dy = abs(local.y) - h
			return local.x * local.x + dy * dy <= r * r
	
	return false

# ========== 公共查询方法 ==========
func is_finger_inside() -> bool:
	return _button_pressed

# ========== 动画 ==========
func _press_animation():
	if current_tween and current_tween.is_running():
		current_tween.kill()
	
	current_tween = create_tween()
	var trans_type = Tween.TRANS_ELASTIC if anim_style == 0 else Tween.TRANS_QUAD
	
	current_tween.tween_property(visual_sprite, "scale", 
		_base_icon_scale * press_scale, anim_duration)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(trans_type)
	
	if texture_pressed and visual_sprite:
		visual_sprite.texture = texture_pressed

func _release_animation():
	if current_tween and current_tween.is_running():
		current_tween.kill()
	
	current_tween = create_tween()
	var trans_type = Tween.TRANS_ELASTIC if anim_style == 0 else Tween.TRANS_QUAD
	
	current_tween.tween_property(visual_sprite, "scale", 
		_base_icon_scale, anim_duration)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(trans_type)
	
	if texture_normal and visual_sprite:
		visual_sprite.texture = texture_normal

# ========== 技能逻辑 ==========
func _can_press() -> bool:
	can_press = true
	if cool_down_time_now > 0:
		can_press = false
	if is_charging and dot <= 0:
		can_press = false
	return can_press

# ========== 视觉效果 ==========
func _update_shader():
	var should_gray = disabled or cool_down_time_now > 0 or (is_charging and dot <= 0)
	handle_icon_material(should_gray)

func handle_icon_material(is_gray: bool):
	if visual_sprite and visual_sprite.material is ShaderMaterial:
		visual_sprite.material.set_shader_parameter("is_gray", is_gray)
		visual_sprite.material.set_shader_parameter("darken", is_gray)

# ========== 计时器动画控制 ==========
func _update_timer_frame():
	if not timer:
		return
		
	if timer_progress <= 0.0:
		timer.visible = false
		return
		
	timer.visible = true
	timer.stop()
	
	var target_frame = ceili(timer_progress * 60) - 1
	target_frame = clamp(target_frame, 0, 59)
	timer.frame = target_frame

# ========== 公共接口 ==========
func set_cd(cd: float):
	cool_down_time_now = cd
	cool_down_time_max = cd

func force_release():
	if _visual_pressed:
		_release_visual()

func is_pressed() -> bool:
	return _button_pressed

func set_texture(t: Texture2D):
	texture_normal = t
	visual_sprite.texture = texture_normal
	_apply_icon_scale()
