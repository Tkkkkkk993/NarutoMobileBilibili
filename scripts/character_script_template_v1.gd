# character_script_template_v1.gd
class_name CharacterScriptTemplateV1 extends AnimatedSprite2DEntity

# ============================================
# 角色专属状态变量
# ============================================
var _raw_input: Vector2 = Vector2.ZERO
var _waiting_for_land_anim: String = ""
var dot_flag: Array[bool]

# ============================================
# 初始化与资源路径
# ============================================
func _ready():
	dot_flag.resize(3)
	res_path = "res://assets/entities/YOUR_ENTITY_NAME/main.tres"
	super._ready()
	effects_container.register_effects({
		# "YOUR_EFFECT_KEY": preload("res://assets/entities/YOUR_CHARACTER_FOLDER/_effects/xxx.tscn"),
	})

func setup_icon():
	# skill_slot[1].set_texture(preload("res://assets/entities/YOUR_CHARACTER_FOLDER/icon/skill1.png"))
	# skill_slot[2].set_texture(preload("res://assets/entities/YOUR_CHARACTER_FOLDER/icon/skill2.png"))
	# skill_slot[3].set_texture(preload("res://assets/entities/YOUR_CHARACTER_FOLDER/icon/skill3.png"))
	pass

func _on_entry_end():
	# if entity_type == EntityType.PLAYER:
	#	 skill_slot[7].visible = true
	pass

# ============================================
# 攻击与滑动配置 (保留 Obito 配置，补充底层所需字段)
# ============================================
func _setup_slide_sequences():
	attack_configs = {
		"a1": {
			"can_turn_frames": [0],
			"cancel_window": [5, 6],
			"move_during_attack": 0.0,  # 底层移动系数
			"z_movement": "grounded",
			"air_cancel": false,
			"end_anim": "",
			"next_attack": "a2"
		}
	}
	
	slide_sequences = {
		"a1": [
			{"frame": 2, "speed": 1000, "resistance": 10.0, "direction_mode": "facing", "z_speed": 0},
		]
	}

# ============================================
# 通用底层逻辑：落地处理
# ============================================
func _on_landed():
	if not is_attacking:
		return
	if _waiting_for_land:
		_waiting_for_land = false
		if _waiting_for_land_anim != "":
			var end_anim = _waiting_for_land_anim
			_waiting_for_land_anim = ""
			print("[攻击] %s 落地 -> 播放结束动画 %s" % [current_attack, end_anim])
			current_attack = end_anim
			play_animation(end_anim)
			return
		print("[攻击] %s 落地 -> 切换到 idle" % current_attack)
		_reset_attack_state()
		play_animation("idle")
		return
	print("[攻击] %s 攻击中落地，继续攻击" % current_attack)

# ============================================
# 通用底层逻辑：输入处理
# ============================================
func _handle_input():
	_raw_input = Vector2.ZERO
	# 攻击输入
	if inputs[0]: _try_attack_input()
	if inputs[1]: _try_s1_input()
	if inputs[2]: _try_s2_input()
	if inputs[7]: _try_subs1_input()
	# 移动输入
	if _can_move() or is_attacking:
		if input_left: 
			_raw_input.x -= 1
			if not is_attacking: facing_direction = -1
		if input_right: 
			_raw_input.x += 1
			if not is_attacking: facing_direction = 1
		if input_up: _raw_input.y -= 1
		if input_down: _raw_input.y += 1
		if not is_attacking: is_running = _raw_input != Vector2.ZERO
		_handle_normal_movement(_raw_input)
		_handle_input_spe()

func _try_attack_input():
	# 非攻击状态下的初始攻击
	if not is_attacking:
		if current_animation in ["idle", "run"]:
			_perform_attack("a1")
		return
	# 攻击状态下的连招处理
	var cfg = attack_configs[current_attack]
	var next_attack = cfg.get("next_attack", "")
	if next_attack == "":
		print("[%s] 是终结技或不能接招" % current_attack)
		return
	# 浮空等待中的取消逻辑
	if _waiting_for_land:
		if not _can_air_cancel():
			print("[%s] 浮空等待中，无法取消" % current_attack)
			return
		print("[%s] 浮空窗口期取消 -> %s" % [current_attack, next_attack])
		_perform_attack(next_attack)
		return
	# 取消窗口检查
	if not _is_in_cancel_window():
		print("[%s] 第%d帧：不在取消窗口%s内" % [current_attack, get_current_frame(), str(cfg.cancel_window)])
		return
	print("[%s] 取消窗口内 -> %s" % [current_attack, next_attack])
	_perform_attack(next_attack)

# ============================================
# 通用底层逻辑：技能输入判定
# ============================================
func _try_s1_input():
	if not current_animation in ["idle", "run", "a1", "a2", "a3", "a3e", "a4", "a4b", "a4e", "s2", "s2b"]: return
	if cool_down_time[1].time > 0: return
	if is_sliding: stop_slide()
	if not is_grounded:
		_force_land_and_reset()
		stop_free_move()
	dot_flag[1] = false
	set_cd(1, 1, 10)
	_perform_attack("s1")

func _try_s2_input():
	if not current_animation in ["idle", "run", "a1", "a2", "a3", "a3e", "a4", "a4b", "a4e"]: return
	if cool_down_time[2].time > 0: return
	if is_sliding: stop_slide()
	if not is_grounded:
		_force_land_and_reset()
		stop_free_move()
	dot_flag[2] = false
	set_cd(2, 2, 10)
	_perform_attack("s2")

func _try_subs1_input():
	pass

func change_skill_dot(i: int, d: int):
	if !dot_flag[i]:
		change_ultimate_point(d)
		dot_flag[i] = true

# ============================================
# 通用底层逻辑：核心判定与状态工具
# ============================================
func _force_land_and_reset():
	super._force_land_and_reset()
	_waiting_for_land_anim = ""

func _can_air_cancel() -> bool:
	if current_attack.is_empty(): return false
	var cfg = attack_configs[current_attack]
	if not cfg.get("air_cancel", false): return false
	var current_frame = get_current_frame()
	if not (current_frame in cfg.cancel_window): return false
	if is_grounded: return false
	return true

func _is_in_cancel_window() -> bool:
	if current_attack.is_empty(): return false
	var cfg = attack_configs[current_attack]
	return get_current_frame() in cfg.cancel_window

func _handle_normal_movement(input_dir: Vector2):
	if is_attacking:
		is_running = input_dir != Vector2.ZERO
		return
	if input_dir.x != 0:
		facing_direction = 1 if input_dir.x > 0 else -1
	is_running = input_dir != Vector2.ZERO

# ============================================
# 通用底层逻辑：攻击执行与重置
# ============================================
func _perform_attack(attack_name: String):
	if not attack_name in attack_configs: return
	# 取消等待落地状态
	if _waiting_for_land:
		print("[%s] 取消等待落地，切换到 %s" % [current_attack, attack_name])
		_waiting_for_land = false
		_waiting_for_land_anim = ""
		animated_sprite.play()
	# 停止当前滑动
	if is_sliding: stop_slide()
	# 攻击初始化
	var cfg = attack_configs[attack_name]
	var z_move_type = cfg.get("z_movement", "grounded")
	if z_move_type == "grounded" and not is_grounded:
		print(attack_name)
		return
		
	current_attack = attack_name
	is_attacking = true
	slide_locked_facing = facing_direction
	current_slide_index = -1

	# 速度重置
	velocity_3d.x = 0
	velocity_3d.y = 0
	velocity_smoothed = Vector2.ZERO
	print("[%s] 开始 | 高度:%.2f | 下一招:%s | 空中取消:%s" % [attack_name, position_3d.z, cfg.get("next_attack", "无"), cfg.get("air_cancel", false)])
	play_animation(attack_name)

func _reset_attack_state():
	super._reset_attack_state()
	_waiting_for_land_anim = ""

# ============================================
# 通用底层逻辑：动画流转状态机
# ============================================
func _on_animation_finished():
	if not (current_animation in attack_configs):
		super._on_animation_finished()
		return
		
	var cfg = attack_configs[current_animation]
	# 地面状态下的动画结束
	if is_grounded:
		_handle_attack_end_on_ground(cfg)
		return
		
	# 空中状态下的动画结束
	if cfg.get("air_cancel", false):
		print("[%s] 动画结束（浮空可取消）-> 等待落地或取消" % current_animation)
		_waiting_for_land = true
		var end_anim = cfg.get("end_anim", "")
		if end_anim != "":
			_waiting_for_land_anim = end_anim
			print("[%s] 落地后将播放 %s" % [current_animation, end_anim])
		animated_sprite.pause()
	else:
		print("[%s] 动画结束（浮空不可取消）-> 等待落地" % current_animation)
		_waiting_for_land = true
		animated_sprite.pause()

func _handle_attack_end_on_ground(cfg: Dictionary):
	var end_anim = cfg.get("end_anim", "")
	if end_anim != "" and current_animation != end_anim:
		print("[%s] 动画结束（地面）-> 播放结束动画 %s" % [current_animation, end_anim])
		current_attack = end_anim
		play_animation(end_anim)
		return
		
	var next_attack = cfg.get("next_attack", "")
	if next_attack == "":
		print("[%s] 结束 -> idle" % current_animation)
	else:
		print("[%s] 结束（但配置可接%s）-> idle" % [current_animation, next_attack])
		
	_reset_attack_state()
	play_animation("idle")

func _on_frame_trigger(anim_name: String, frame_idx: int):
	_handle_anim(anim_name, frame_idx)
	if not anim_name in attack_configs: return
	var cfg = attack_configs[anim_name]
	if cfg.can_turn_frames.size() > 0:
		var last_can_turn = cfg.can_turn_frames[-1]
		if frame_idx == last_can_turn + 1:
			print("[%s] 朝向锁定:%d" % [anim_name, slide_locked_facing])

# ============================================
# 通用底层逻辑：物理移动
# ============================================
func _handle_movement(delta):
	# 等待落地时不处理移动
	if is_attacking:
		_handle_attack_physics(delta)
	elif !is_sliding:
		super._handle_movement(delta)

func _handle_attack_physics(delta):
	var cfg = attack_configs[current_attack]
	var speed_mult = cfg.get("move_during_attack", 0.0)
	var base_x = entity_data.move_speed_x if entity_data else 300.0
	var base_y = entity_data.move_speed_y if entity_data else 300.0
	var input_x = _raw_input.x
	var input_y = _raw_input.y
	var frame = get_current_frame()

	# 朝向处理
	var can_turn = frame in cfg.can_turn_frames
	if can_turn:
		if input_x != 0:
			var new_facing = 1 if input_x > 0 else -1
			if new_facing != facing_direction:
				facing_direction = new_facing
				slide_locked_facing = facing_direction
	else:
		facing_direction = slide_locked_facing

	# X轴移动限制
	if input_x != 0:
		var input_facing = 1 if input_x > 0 else -1
		if input_facing != slide_locked_facing:
			input_x = 0

	# 移动计算
	var z_move_type = cfg.get("z_movement", "grounded")
	var allow_xy_move = true
	match z_move_type:
		"grounded":
			if not is_grounded: allow_xy_move = false
		"airborne", "both":
			allow_xy_move = true

	if allow_xy_move:
		var target_vel = Vector2(
			input_x * base_x * speed_mult,
			input_y * base_y * speed_mult
		)
		if use_inertia:
			velocity_smoothed = velocity_smoothed.lerp(target_vel, inertia_speed * delta)
			velocity_3d.x = velocity_smoothed.x
			velocity_3d.y = velocity_smoothed.y
		else:
			velocity_3d.x = target_vel.x
			velocity_3d.y = target_vel.y
			velocity_smoothed = target_vel
	else:
		velocity_3d.x = lerp(velocity_3d.x, 0.0, 0.1)
		velocity_3d.y = lerp(velocity_3d.y, 0.0, 0.1)
	is_running = input_x != 0 or input_y != 0

# ============================================
# 角色专属帧逻辑与受击处理
# ============================================
func _handle_anim(anim_name: String, frame_idx: int):
	match anim_name:
		"s1":
			custom_body_state = BodyState.SUPER_ARMOR
		"s2":
			custom_body_state = BodyState.HARD
		_:
			custom_body_state = BodyState.NORMAL

	match anim_name:
		"a3":
			pass

func _on_animation_enter(anim_name: String):
	pass

func _on_attack_hit(hit_result: AttackBoxManager.HitResult):
	var target: EntityBase = hit_result.target
	var target_config = hit_result.hitbox_data
	var box_name = hit_result.attack_box_name
	var box_config = hit_result.attack_config
	var hit_eff_pos = calculate_intersection(hit_result, box_config.to_dict())
	
	match box_name:
		pass
