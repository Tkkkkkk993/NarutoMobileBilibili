class_name DuelCamera extends Camera2D
# ============================================
# 导出变量
# ============================================
@export var target: Node2D
@export var follow_speed: float = 5.0
@export var follow_x_axis: bool = true
@export var follow_y_axis: bool = false
@export var facing_offset: float = 150.0
@export var offset_smooth_speed: float = 8.0
@export var use_limits: bool = false
@export var view_width: float = 1152.0

# ============================================
# 枚举定义
# ============================================
enum ShakeType { RANDOM, DIRECTIONAL, TRAUMA, SPRING, EXPLOSION, OSCILLATE }
enum TransitionType { LINEAR, EASE_IN, EASE_OUT, EASE_IN_OUT }
enum PulseWaveform { SINE, TRIANGLE, SQUARE }   # 新增 SQUARE 方波

# ============================================
# 震动系统
# ============================================
var _shake_active: bool = false
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_intensity: float = 0.0
var _shake_type: ShakeType = ShakeType.RANDOM
var _shake_direction: Vector2 = Vector2.ZERO
var _shake_trauma: float = 0.0
var _shake_decay: float = 1.5
var _shake_frequency: float = 20.0
var _shake_amplitude: Vector2 = Vector2.ONE
var _spring_displacement: Vector2 = Vector2.ZERO
var _spring_velocity: Vector2 = Vector2.ZERO
var _spring_stiffness: float = 300.0
var _spring_damping: float = 0.3
var _current_shake_offset: Vector2 = Vector2.ZERO
var _target_shake_offset: Vector2 = Vector2.ZERO
var _shake_recovery_speed: float = 15.0

# --- 振荡震动参数 ---
var _shake_osc_frequency: float = 2.0 
var _shake_osc_amplitude: float = 10.0 

# ============================================
# 放大震动系统（一次性）
# ============================================
var _zoom_shock_active: bool = false
var _zoom_shock_phase: int = 0
var _zoom_shock_phase_time: float = 0.0
var _zoom_shock_intensity: float = 0.0
var _zoom_shock_total_duration: float = 0.0
var _zoom_shock_enter_duration: float = 0.0
var _zoom_shock_exit_duration: float = 0.0
var _zoom_shock_enter_ease: TransitionType = TransitionType.EASE_OUT
var _zoom_shock_exit_ease: TransitionType = TransitionType.EASE_IN
var _current_zoom_multiplier: float = 1.0
var _original_zoom: Vector2 = Vector2.ONE
var _has_stored_original_zoom: bool = false

# ============================================
# 循环脉冲缩放系统（增强版）
# ============================================
var _pulse_zoom_active: bool = false
var _pulse_zoom_amplitude: float = 0.0
var _pulse_zoom_frequency: float = 2.0      # 每秒脉冲次数
var _pulse_zoom_duration: float = 0.0       # 持续时间（秒），0 表示无限
var _pulse_zoom_time: float = 0.0
var _pulse_zoom_waveform: PulseWaveform = PulseWaveform.SINE
var _pulse_zoom_multiplier: float = 1.0

# ============================================
# 镜头移动系统
# ============================================
var _camera_move_active: bool = false
var _camera_move_phase: int = 0
var _camera_move_phase_time: float = 0.0
var _move_duration: float = 0.0
var _move_enter_duration: float = 0.0
var _move_exit_duration: float = 0.0
var _move_enter_ease: TransitionType = TransitionType.EASE_OUT
var _move_exit_ease: TransitionType = TransitionType.EASE_IN
var _move_target_offset: Vector2 = Vector2.ZERO
var _move_current_offset: Vector2 = Vector2.ZERO
var _move_is_absolute: bool = false
var _move_abs_target_pos: Vector2 = Vector2.ZERO
var _move_abs_home_pos: Vector2 = Vector2.ZERO
var _move_abs_enter_start_pos: Vector2 = Vector2.ZERO
var _move_target_zoom: float = 1.0
var _move_current_zoom: float = 1.0

# ============================================
# 镜头旋转系统
# ============================================
var _rotate_active: bool = false
var _rotate_phase: int = 0
var _rotate_phase_time: float = 0.0
var _rotate_angle: float = 0.0
var _rotate_hold_duration: float = 0.0
var _rotate_enter_duration: float = 0.0
var _rotate_exit_duration: float = 0.0
var _rotate_enter_ease: TransitionType = TransitionType.EASE_OUT
var _rotate_exit_ease: TransitionType = TransitionType.EASE_IN
var _rotate_current_angle: float = 0.0

# ============================================
# 内部状态
# ============================================
var target_entity: EntityBase = null
var current_offset: float = 0.0
var target_offset: float = 0.0
var _prev_facing: int = 1

# ============================================
# 初始化
# ============================================
func _ready():
	make_current()
	_original_zoom = zoom
	_has_stored_original_zoom = true
	_pulse_zoom_multiplier = 1.0
	MatchConfig.controller_changed.connect(_on_controller_changed)
	if target:
		_setup_target()
	else:
		call_deferred("_auto_find_target")

func _setup_target():
	target_entity = target as EntityBase
	snap_to_target()

func _auto_find_target():
	var arena = get_parent()
	if not arena: return
	var main = arena.get_node_or_null("Main")
	if not main: return
	var entity_manager = main.get_node_or_null("EntityManager")
	if entity_manager and entity_manager.has_method("get_player_entity"):
		var player = entity_manager.get_player_entity()
		if player: set_target(player)

func _on_controller_changed(new_name: String):
	var arena = get_parent()
	if not arena: return
	var main = arena.get_node_or_null("Main")
	if not main: return
	var em = main.get_node_or_null("EntityManager")
	if not em or not em.has_method("get_entity"): return
	var e = em.get_entity(new_name)
	if e:
		target = e
		target_entity = e
		target_offset = 0.0
		print("摄像机平滑切换到: ", new_name)

# ============================================
# 核心逻辑
# ============================================
func _physics_process(delta):
	if not target or not is_instance_valid(target): return
	_update_facing_offset(delta)
	
	var current_facing: int = 1
	if target_entity and is_instance_valid(target_entity):
		current_facing = target_entity.get_facing()
	
	if current_facing != _prev_facing:
		# 清零偏移平滑速度
		current_offset = target_offset
		
		# 更新记录
		_prev_facing = current_facing
	
	# 更新循环脉冲缩放
	_update_pulse_zoom(delta)

	if target_entity and is_instance_valid(target_entity) and target_entity.entry_action != EntityBase.EntryAction.NONE:
		var target_pos = target.global_position
		if follow_x_axis:
			var desired_x = _calculate_constrained_x(target_pos.x)
			global_position.x = lerp(global_position.x, desired_x, follow_speed * delta)
		_process_shake(delta)
		_process_zoom_shock(delta)
		_process_camera_rotate(delta)
		_apply_final_transform_relative()
		return

	if _camera_move_active and _move_is_absolute:
		_process_camera_move(delta)
		_process_shake(delta)
		_process_zoom_shock(delta)
		_process_camera_rotate(delta)
		_apply_final_transform_absolute()
		return

	var target_pos = target.global_position
	if follow_x_axis:
		var desired_x = _calculate_constrained_x(target_pos.x)
		global_position.x = lerp(global_position.x, desired_x, follow_speed * delta)
	if follow_y_axis:
		global_position.y = lerp(global_position.y, target_pos.y, follow_speed * delta)

	_process_shake(delta)
	_process_zoom_shock(delta)
	_process_camera_move(delta)
	_process_camera_rotate(delta)
	_apply_final_transform_relative()

# ============================================
# 最终效果应用（包含脉冲乘数）
# ============================================
func _apply_final_transform_relative():
	offset = _current_shake_offset + _move_current_offset
	zoom = _original_zoom * _current_zoom_multiplier * _move_current_zoom * _pulse_zoom_multiplier
	rotation = deg_to_rad(_rotate_current_angle)

func _apply_final_transform_absolute():
	offset = _current_shake_offset
	zoom = _original_zoom * _current_zoom_multiplier * _move_current_zoom * _pulse_zoom_multiplier
	rotation = deg_to_rad(_rotate_current_angle)

# ============================================
# 循环脉冲缩放更新逻辑（支持持续时间与方波）
# ============================================
func _update_pulse_zoom(delta: float):
	if not _pulse_zoom_active:
		# 平滑回归到1.0（防止停止时突变，但停止时已强制设为1）
		_pulse_zoom_multiplier = lerp(_pulse_zoom_multiplier, 1.0, 10.0 * delta)
		if abs(_pulse_zoom_multiplier - 1.0) < 0.001:
			_pulse_zoom_multiplier = 1.0
		return
	
	# 持续时间检查
	if _pulse_zoom_duration > 0.0 and _pulse_zoom_time >= _pulse_zoom_duration:
		stop_pulse_zoom()
		return
	
	_pulse_zoom_time += delta
	var t = _pulse_zoom_time
	var f = _pulse_zoom_frequency
	var amp = _pulse_zoom_amplitude
	var factor: float = 1.0
	
	match _pulse_zoom_waveform:
		PulseWaveform.SINE:
			var sin_val = sin(2.0 * PI * f * t)
			factor = 1.0 + amp * (sin_val + 1.0) / 2.0
		PulseWaveform.TRIANGLE:
			var period = 1.0 / f
			var phase = fmod(t, period)
			var half_period = period / 2.0
			if phase <= half_period:
				var progress = phase / half_period
				factor = 1.0 + amp * progress
			else:
				var progress = (phase - half_period) / half_period
				factor = 1.0 + amp * (1.0 - progress)
		PulseWaveform.SQUARE:
			# 方波：半个周期放大，半个周期原样
			var period = 1.0 / f
			var phase = fmod(t, period)
			if phase < period / 2.0:
				factor = 1.0 + amp
			else:
				factor = 1.0
	
	_pulse_zoom_multiplier = factor

# ============================================
# 公共API - 循环脉冲缩放（增强版）
# ============================================
## 启动循环脉冲缩放
## @param amplitude       缩放幅度（0.2 = 放大到1.2倍）
## @param frequency_hz    脉冲频率（每秒完整脉冲次数）
## @param waveform        波形：0=SINE(平滑),1=TRIANGLE(线性),2=SQUARE(突然)
## @param duration        持续时间（秒），0或负数表示无限，直到手动停止
func start_pulse_zoom(amplitude: float, frequency_hz: float = 2.0, waveform: int = 0, duration: float = 0.0):
	if amplitude <= 0.0:
		stop_pulse_zoom()
		return
	_pulse_zoom_active = true
	_pulse_zoom_amplitude = amplitude
	_pulse_zoom_frequency = max(frequency_hz, 0.01)
	_pulse_zoom_waveform = waveform as PulseWaveform
	_pulse_zoom_duration = max(duration, 0.0)   # 0 表示无限
	_pulse_zoom_time = 0.0
	# 立即更新初始值，避免第一帧无变化
	_update_pulse_zoom(0.0)

## 停止循环脉冲缩放（立即恢复原样）
func stop_pulse_zoom():
	_pulse_zoom_active = false
	_pulse_zoom_multiplier = 1.0

## 检查是否正在脉冲缩放
func is_pulse_zoom_active() -> bool:
	return _pulse_zoom_active

# ============================================
# 镜头移动系统核心逻辑（原有，不变）
# ============================================
func _process_camera_move(delta: float):
	if not _camera_move_active:
		if not _move_is_absolute:
			_move_current_offset = _move_current_offset.lerp(Vector2.ZERO, 10.0 * delta)
			_move_current_zoom = lerp(_move_current_zoom, 1.0, 10.0 * delta)
		return
	_camera_move_phase_time += delta
	match _camera_move_phase:
		0: _process_move_enter(delta)
		1: _process_move_hold(delta)
		2: _process_move_exit(delta)

func _process_move_enter(_delta: float):
	if _move_enter_duration <= 0:
		if _move_is_absolute: global_position = _move_abs_target_pos
		else: _move_current_offset = _move_target_offset
		_move_current_zoom = _move_target_zoom
		_start_move_hold(); return
	var progress = clamp(_camera_move_phase_time / _move_enter_duration, 0.0, 1.0)
	var eased = _apply_easing(progress, _move_enter_ease)
	if _move_is_absolute: global_position = _move_abs_enter_start_pos.lerp(_move_abs_target_pos, eased)
	else: _move_current_offset = Vector2.ZERO.lerp(_move_target_offset, eased)
	_move_current_zoom = lerp(1.0, _move_target_zoom, eased)
	if progress >= 1.0: _start_move_hold()

func _process_move_hold(_delta: float):
	var hold_time = _move_duration - _move_enter_duration - _move_exit_duration
	if _move_is_absolute: global_position = _move_abs_target_pos
	if _camera_move_phase_time >= hold_time: _start_move_exit()

func _process_move_exit(_delta: float):
	if _move_exit_duration <= 0: _end_camera_move(); return
	var progress = clamp(_camera_move_phase_time / _move_exit_duration, 0.0, 1.0)
	var eased = _apply_easing(progress, _move_exit_ease)
	if _move_is_absolute:
		var target_pos = target.global_position
		var dest_pos = global_position
		if follow_x_axis: dest_pos.x = _calculate_constrained_x(target_pos.x)
		else: dest_pos.x = _move_abs_home_pos.x
		if follow_y_axis: dest_pos.y = target_pos.y
		else: dest_pos.y = _move_abs_home_pos.y
		global_position = global_position.lerp(dest_pos, eased)
	else:
		_move_current_offset = _move_target_offset.lerp(Vector2.ZERO, eased)
		_move_current_zoom = lerp(_move_target_zoom, 1.0, eased)
	if progress >= 1.0: _end_camera_move()

func _start_move_hold(): _camera_move_phase = 1; _camera_move_phase_time = 0.0
func _start_move_exit(): _camera_move_phase = 2; _camera_move_phase_time = 0.0
func _end_camera_move():
	_camera_move_active = false; _move_is_absolute = false
	_move_current_offset = Vector2.ZERO; _move_current_zoom = 1.0

# ============================================
# 公共API - 镜头移动（原有，不变）
# ============================================
func camera_move_snap_enter(target_world_pos: Vector2, target_zoom: float, hold_duration: float, exit_duration: float = 0.3, exit_ease: TransitionType = TransitionType.EASE_OUT):
	camera_move_to_absolute(target_world_pos, target_zoom, hold_duration + exit_duration, 0.0, exit_duration, TransitionType.LINEAR, exit_ease)

func camera_move_to_absolute(target_world_pos: Vector2, target_zoom: float, duration: float, enter_duration: float = 0.2, exit_duration: float = 0.3, enter_ease: TransitionType = TransitionType.EASE_OUT, exit_ease: TransitionType = TransitionType.EASE_IN):
	if not _camera_move_active: _move_abs_home_pos = global_position
	_move_abs_enter_start_pos = global_position
	_move_abs_target_pos = target_world_pos; _move_is_absolute = true
	_move_target_zoom = clamp(target_zoom, 0.1, 3.0); _move_duration = max(duration, 0.1)
	_move_enter_duration = max(enter_duration, 0.0); _move_exit_duration = max(exit_duration, 0.0)
	_move_enter_ease = enter_ease; _move_exit_ease = exit_ease
	_camera_move_active = true; _camera_move_phase = 0; _camera_move_phase_time = 0.0

func camera_move(target_offset: Vector2, target_zoom: float, duration: float, enter_duration: float = 0.2, exit_duration: float = 0.3, enter_ease: TransitionType = TransitionType.EASE_OUT, exit_ease: TransitionType = TransitionType.EASE_IN):
	_move_is_absolute = false; _move_target_offset = target_offset
	_move_target_zoom = clamp(target_zoom, 0.1, 3.0); _move_duration = max(duration, 0.1)
	_move_enter_duration = max(enter_duration, 0.0); _move_exit_duration = max(exit_duration, 0.0)
	_move_enter_ease = enter_ease; _move_exit_ease = exit_ease
	_camera_move_active = true; _camera_move_phase = 0; _camera_move_phase_time = 0.0

func stop_camera_move(immediate: bool = false):
	if immediate:
		_camera_move_active = false; _move_is_absolute = false
		_move_current_offset = Vector2.ZERO; _move_current_zoom = 1.0
	else:
		if _camera_move_phase < 2: _camera_move_phase = 2; _camera_move_phase_time = 0.0

# ============================================
# 镜头旋转系统
# ============================================
func _process_camera_rotate(delta: float):
	if not _rotate_active:
		_rotate_current_angle = lerp(_rotate_current_angle, 0.0, 10.0 * delta)
		if abs(_rotate_current_angle) < 0.1:
			_rotate_current_angle = 0.0
		return
	_rotate_phase_time += delta
	match _rotate_phase:
		0: _process_rotate_enter(delta)
		1: _process_rotate_hold(delta)
		2: _process_rotate_exit(delta)

func _process_rotate_enter(_delta: float):
	if _rotate_enter_duration <= 0:
		_rotate_current_angle = _rotate_angle
		_start_rotate_hold()
		return
	var progress = clamp(_rotate_phase_time / _rotate_enter_duration, 0.0, 1.0)
	_rotate_current_angle = lerp(0.0, _rotate_angle, _apply_easing(progress, _rotate_enter_ease))
	if progress >= 1.0:
		_start_rotate_hold()

func _process_rotate_hold(_delta: float):
	if _rotate_phase_time >= _rotate_hold_duration:
		_start_rotate_exit()

func _process_rotate_exit(_delta: float):
	if _rotate_exit_duration <= 0:
		_rotate_current_angle = 0.0
		_end_rotate()
		return
	var progress = clamp(_rotate_phase_time / _rotate_exit_duration, 0.0, 1.0)
	_rotate_current_angle = lerp(_rotate_angle, 0.0, _apply_easing(progress, _rotate_exit_ease))
	if progress >= 1.0:
		_end_rotate()

func _start_rotate_hold():
	_rotate_phase = 1; _rotate_phase_time = 0.0

func _start_rotate_exit():
	_rotate_phase = 2; _rotate_phase_time = 0.0

func _end_rotate():
	_rotate_active = false
	_rotate_current_angle = 0.0

func camera_rotate(angle_deg: float, hold_duration: float, enter_duration: float = 0.2, exit_duration: float = 0.3, enter_ease: TransitionType = TransitionType.EASE_OUT, exit_ease: TransitionType = TransitionType.EASE_IN):
	_rotate_angle = angle_deg
	_rotate_hold_duration = max(hold_duration, 0.0)
	_rotate_enter_duration = max(enter_duration, 0.0)
	_rotate_exit_duration = max(exit_duration, 0.0)
	_rotate_enter_ease = enter_ease
	_rotate_exit_ease = exit_ease
	_rotate_active = true
	_rotate_phase = 0
	_rotate_phase_time = 0.0

func stop_camera_rotate(immediate: bool = false):
	if immediate:
		_rotate_active = false
		_rotate_current_angle = 0.0
	else:
		if _rotate_phase < 2:
			_start_rotate_exit()

# ============================================
# 放大震动系统（原有，不变）
# ============================================
func _process_zoom_shock(delta: float):
	if not _zoom_shock_active:
		_current_zoom_multiplier = lerp(_current_zoom_multiplier, 1.0, 10.0 * delta); return
	_zoom_shock_phase_time += delta
	match _zoom_shock_phase:
		0: _process_zoom_enter(delta)
		1: _process_zoom_hold(delta)
		2: _process_zoom_exit(delta)

func _process_zoom_enter(_delta: float):
	if _zoom_shock_enter_duration <= 0: _current_zoom_multiplier = 1.0 + _zoom_shock_intensity; _start_zoom_hold(); return
	var progress = clamp(_zoom_shock_phase_time / _zoom_shock_enter_duration, 0.0, 1.0)
	_current_zoom_multiplier = lerp(1.0, 1.0 + _zoom_shock_intensity, _apply_easing(progress, _zoom_shock_enter_ease))
	if progress >= 1.0: _start_zoom_hold()

func _process_zoom_hold(_delta: float):
	var hold_time = _zoom_shock_total_duration - _zoom_shock_enter_duration - _zoom_shock_exit_duration
	if _zoom_shock_phase_time >= hold_time: _start_zoom_exit()

func _process_zoom_exit(_delta: float):
	if _zoom_shock_exit_duration <= 0: _current_zoom_multiplier = 1.0; _end_zoom_shock(); return
	var progress = clamp(_zoom_shock_phase_time / _zoom_shock_exit_duration, 0.0, 1.0)
	_current_zoom_multiplier = lerp(1.0 + _zoom_shock_intensity, 1.0, _apply_easing(progress, _zoom_shock_exit_ease))
	if progress >= 1.0: _end_zoom_shock()

func _start_zoom_hold(): _zoom_shock_phase = 1; _zoom_shock_phase_time = 0.0
func _start_zoom_exit(): _zoom_shock_phase = 2; _zoom_shock_phase_time = 0.0
func _end_zoom_shock(): _zoom_shock_active = false; _current_zoom_multiplier = 1.0

func zoom_shock_advanced(intensity: float, total_duration: float, enter_duration: float = 0.05, exit_duration: float = 0.15, enter_ease: TransitionType = TransitionType.EASE_OUT, exit_ease: TransitionType = TransitionType.EASE_IN):
	if not _has_stored_original_zoom: _original_zoom = zoom; _has_stored_original_zoom = true
	_zoom_shock_intensity = clamp(intensity, 0.0, 1.0); _zoom_shock_total_duration = max(total_duration, 0.02)
	_zoom_shock_enter_duration = max(enter_duration, 0.0); _zoom_shock_exit_duration = max(exit_duration, 0.0)
	_zoom_shock_enter_ease = enter_ease; _zoom_shock_exit_ease = exit_ease
	_zoom_shock_active = true; _zoom_shock_phase = 0; _zoom_shock_phase_time = 0.0

func zoom_shock(intensity: float, duration: float): zoom_shock_advanced(intensity, duration, 0.05, duration * 0.7)
func zoom_shock_instant(intensity: float, duration: float): zoom_shock_advanced(intensity, duration, 0.0, 0.0)
func zoom_shock_hold(intensity: float, hold_time: float): zoom_shock_advanced(intensity, hold_time, 0.0, 0.0)

# ============================================
# 震动系统（原有，不变）
# ============================================
func _process_shake(delta: float):
	if _shake_active:
		_calculate_target_shake(delta)
		_current_shake_offset = _target_shake_offset
	else:
		_target_shake_offset = Vector2.ZERO
		_current_shake_offset = _current_shake_offset.lerp(_target_shake_offset, _shake_recovery_speed * delta)
		if not _shake_active and _current_shake_offset.length() < 0.5:
			_current_shake_offset = Vector2.ZERO

func _calculate_target_shake(delta: float):
	var shake_offset = Vector2.ZERO
	match _shake_type:
		ShakeType.RANDOM: shake_offset = _calc_random_shake()
		ShakeType.DIRECTIONAL: shake_offset = _calc_directional_shake()
		ShakeType.TRAUMA: shake_offset = _calc_trauma_shake(delta)
		ShakeType.SPRING: shake_offset = _calc_spring_shake(delta)
		ShakeType.EXPLOSION: shake_offset = _calc_explosion_shake()
		ShakeType.OSCILLATE: shake_offset = _calc_oscillate_shake()

	_target_shake_offset = shake_offset
	_shake_time += delta
	
	if _shake_type != ShakeType.TRAUMA and _shake_type != ShakeType.SPRING:
		if _shake_duration > 0.0 and _shake_time >= _shake_duration:
			_shake_active = false

func _calc_random_shake() -> Vector2:
	var progress = _shake_time / _shake_duration
	var current_intensity = _shake_intensity * (1.0 - progress)
	var time = Time.get_ticks_msec() / 1000.0
	return Vector2((sin(time * _shake_frequency * 10) + randf_range(-0.5, 0.5)) * current_intensity * _shake_amplitude.x, (cos(time * _shake_frequency * 8) + randf_range(-0.5, 0.5)) * current_intensity * _shake_amplitude.y)

func _calc_directional_shake() -> Vector2:
	var progress = _shake_time / _shake_duration
	var envelope = pow(1.0 - progress, 2.0)
	var current_intensity = _shake_intensity * envelope
	var perp = Vector2(-_shake_direction.y, _shake_direction.x)
	var perp_jitter = randf_range(-0.3, 0.3) * current_intensity
	return (_shake_direction * current_intensity + perp * perp_jitter) * _shake_amplitude

func _calc_trauma_shake(delta: float) -> Vector2:
	_shake_trauma = max(0.0, _shake_trauma - _shake_decay * delta)
	if _shake_trauma <= 0.01: _shake_active = false; return Vector2.ZERO
	var shake_amount = _shake_trauma * _shake_trauma * _shake_intensity
	var time = Time.get_ticks_msec() / 1000.0
	return Vector2(_noise(time * _shake_frequency) * shake_amount * _shake_amplitude.x, _noise(time * _shake_frequency + 100) * shake_amount * _shake_amplitude.y)

func _calc_spring_shake(delta: float) -> Vector2:
	var force = -_spring_stiffness * _spring_displacement
	_spring_velocity += force * delta
	_spring_velocity *= (1.0 - _spring_damping)
	_spring_displacement += _spring_velocity * delta
	if _spring_displacement.length() < 0.5 and _spring_velocity.length() < 0.5: _shake_active = false
	return _spring_displacement * _shake_amplitude

func _calc_explosion_shake() -> Vector2:
	var progress = _shake_time / _shake_duration
	var envelope = exp(-progress * 5.0)
	var current_intensity = _shake_intensity * envelope
	return Vector2(randf_range(-1, 1) * current_intensity * _shake_amplitude.x, randf_range(-1, 1) * current_intensity * _shake_amplitude.y)

func _calc_oscillate_shake() -> Vector2:
	var time = Time.get_ticks_msec() / 1000.0
	var current_amp = _shake_osc_amplitude
	if _shake_duration > 0.0:
		var progress = _shake_time / _shake_duration
		current_amp *= (1.0 - progress)
	var y_offset = sin(time * _shake_osc_frequency * TAU) * current_amp
	return Vector2(0.0, y_offset) 

func _noise(t: float) -> float:
	return sin(t * 2.0) * 0.5 + sin(t * 3.7) * 0.25 + sin(t * 7.3) * 0.125

# ============================================
# 公共API - 震动控制（原有，不变）
# ============================================
func shake(intensity: float, duration: float): shake_random(intensity, duration)

func shake_random(intensity: float, duration: float, frequency: float = 20.0):
	_shake_type = ShakeType.RANDOM; _shake_intensity = intensity; _shake_duration = duration
	_shake_frequency = frequency; _shake_time = 0.0; _shake_active = true; _shake_amplitude = Vector2.ONE

func shake_directional(intensity: float, duration: float, direction: Vector2):
	_shake_type = ShakeType.DIRECTIONAL; _shake_intensity = intensity; _shake_duration = duration
	_shake_direction = direction.normalized(); _shake_time = 0.0; _shake_active = true; _shake_amplitude = Vector2.ONE

func shake_trauma(trauma: float, max_trauma: float = 1.0):
	_shake_type = ShakeType.TRAUMA; _shake_trauma = clamp(_shake_trauma + trauma, 0.0, max_trauma)
	_shake_intensity = 30.0; _shake_active = true; _shake_amplitude = Vector2.ONE

func shake_spring(initial_impulse: Vector2, stiffness: float = 300.0, damping: float = 0.3):
	_shake_type = ShakeType.SPRING; _spring_stiffness = stiffness; _spring_damping = damping
	_spring_displacement = Vector2.ZERO; _spring_velocity = initial_impulse; _shake_active = true; _shake_amplitude = Vector2.ONE

func shake_explosion(intensity: float, duration: float = 0.3):
	_shake_type = ShakeType.EXPLOSION; _shake_intensity = intensity; _shake_duration = duration
	_shake_time = 0.0; _shake_active = true; _shake_amplitude = Vector2.ONE

func shake_oscillate(amplitude: float, frequency: float, duration: float = -1.0):
	_shake_type = ShakeType.OSCILLATE
	_shake_osc_amplitude = amplitude
	_shake_osc_frequency = frequency
	_shake_duration = duration
	_shake_time = 0.0
	_shake_active = true
	_current_shake_offset = Vector2.ZERO

func stop_shake():
	_shake_active = false

# ============================================
# 辅助函数与相机控制（原有，不变）
# ============================================
func _apply_easing(progress: float, ease_type: TransitionType) -> float:
	match ease_type:
		TransitionType.LINEAR: return progress
		TransitionType.EASE_IN: return _ease_in_cubic(progress)
		TransitionType.EASE_OUT: return _ease_out_cubic(progress)
		TransitionType.EASE_IN_OUT: return _ease_in_out_cubic(progress)
	return progress

func _ease_in_cubic(x: float) -> float: return x * x * x
func _ease_out_cubic(x: float) -> float: return 1.0 - pow(1.0 - x, 3)
func _ease_in_out_cubic(x: float) -> float:
	if x < 0.5: return 4.0 * x * x * x
	else: return 1.0 - pow(-2.0 * x + 2.0, 3) / 2.0

func _calculate_constrained_x(target_x: float) -> float:
	var ideal_camera_x = target_x + current_offset
	if not use_limits:
		return ideal_camera_x

	# 动态获取当前实际的世界空间可见宽度
	var viewport_width = get_viewport().get_visible_rect().size.x
	var current_world_width = viewport_width / zoom.x
	var half_view = current_world_width / 2.0

	var min_camera_x = float(limit_left) + half_view
	var max_camera_x = float(limit_right) - half_view
	return clamp(ideal_camera_x, min_camera_x, max_camera_x)

func _update_facing_offset(delta):
	var facing: int = 1
	if target_entity and is_instance_valid(target_entity):
		facing = target_entity.get_facing()
	else:
		var diff = target.global_position.x - global_position.x
		if abs(diff) > 0.5: facing = 1 if diff > 0 else -1
	target_offset = facing * facing_offset
	current_offset = lerp(current_offset, target_offset, offset_smooth_speed * delta)

func set_target(new_target: Node2D):
	if not new_target or not is_instance_valid(new_target): return
	target = new_target; target_entity = new_target as EntityBase; snap_to_target()

func snap_to_target():
	if not target or not is_instance_valid(target): return
	var target_pos = target.global_position
	if follow_x_axis: global_position.x = _calculate_constrained_x(target_pos.x)
	if follow_y_axis: global_position.y = target_pos.y
	current_offset = 0.0; target_offset = 0.0

func set_camera_limits(left: float, right: float, top: float = -10000000, bottom: float = 10000000):
	limit_left = int(left); limit_right = int(right); limit_top = int(top); limit_bottom = int(bottom); use_limits = true
