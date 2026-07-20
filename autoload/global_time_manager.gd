extends Node

signal time_scale_changed(new_scale: float)

var is_time_stopped: bool = false
var _buffered_inputs: Array[Dictionary] = []
var _buffer_enabled: bool = false

var _tween: Tween = null

# 统一的时间缩放控制函数
# transition_in:  进入过渡时长（秒）。-1 表示只进入永不恢复。
# hold:           在目标缩放的保持时长（秒）。仅在 transition_in != -1 时有效。
# transition_out: 退出过渡时长（秒）。0 表示瞬间恢复。
# curve_power:    曲线幂次。1=线性，<1=先快后慢，>1=先慢后快。若为 -1 则瞬间跳变（无动画）。
func set_time_scale_animated(target_scale: float, transition_in: float, hold: float = 0.0, transition_out: float = 0.0, curve_power: float = 1.0):
	if _tween and _tween.is_valid():
		_tween.kill()
	
	var start_scale = Engine.time_scale
	
	# 无过渡（瞬间跳变）
	if curve_power == -1:
		Engine.time_scale = target_scale
		time_scale_changed.emit(target_scale)
		if transition_in == -1:
			return  # 永不恢复
		# 延迟恢复
		if transition_in > 0:
			get_tree().create_timer(transition_in, false, true).timeout.connect(
				func(): _restore_scale(start_scale, transition_out, true)
			)
		elif transition_in == 0:
			_restore_scale(start_scale, transition_out, true)
		return
	
	# 有过渡的情况
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	
	# 进入过渡
	_tween.tween_method(_update_scale.bind(start_scale, target_scale, curve_power), 0.0, 1.0, transition_in)
	
	if transition_in == -1:
		# 永不恢复，不需要后续
		return
	
	# 保持阶段
	if hold > 0:
		_tween.tween_interval(hold)
	
	# 退出过渡
	if transition_out > 0:
		_tween.tween_method(_update_scale.bind(target_scale, start_scale, curve_power), 0.0, 1.0, transition_out)
	else:
		_tween.tween_callback(func(): 
			Engine.time_scale = start_scale
			time_scale_changed.emit(start_scale)
		)
	
	_tween.finished.connect(func(): _tween = null)

func _update_scale(progress: float, from_scale: float, to_scale: float, power: float):
	var factor = ease(progress, power)
	var current = lerp(from_scale, to_scale, factor)
	Engine.time_scale = current
	time_scale_changed.emit(current)

func _restore_scale(original: float, out_time: float, instant_if_zero: bool = true):
	if out_time > 0:
		var t = create_tween()
		t.set_ignore_time_scale(true)
		t.tween_method(_update_scale.bind(Engine.time_scale, original, 1.0), 0.0, 1.0, out_time)
		t.finished.connect(func(): Engine.time_scale = original; time_scale_changed.emit(original))
	else:
		Engine.time_scale = original
		time_scale_changed.emit(original)

func start_time_stop_legacy(duration: float = 0.5):
	if is_time_stopped:
		return
	is_time_stopped = true
	_buffer_enabled = true
	Engine.time_scale = 0.0
	time_scale_changed.emit(0.0)
	get_tree().create_timer(duration, false).timeout.connect(_end_time_stop_legacy)

func _end_time_stop_legacy():
	Engine.time_scale = 1.0
	is_time_stopped = false
	_buffer_enabled = false
	time_scale_changed.emit(1.0)
	_flush_inputs()

func _flush_inputs():
	var player = _get_current_player()
	if player and player.has_method("replay_buffered_input"):
		_buffered_inputs.sort_custom(func(a, b): return a.priority > b.priority)
		for cmd in _buffered_inputs:
			player.replay_buffered_input(cmd["action"], cmd["pressed"])
	_buffered_inputs.clear()

func _get_current_player():
	var players = get_tree().get_nodes_in_group("player_entities")
	return players[0] if players.size() > 0 else null

func register_input(action: String, pressed: bool, priority: int):
	if not _buffer_enabled:
		return
	var highest = -1
	for cmd in _buffered_inputs:
		if cmd.priority > highest:
			highest = cmd.priority
	if priority > highest:
		_buffered_inputs = _buffered_inputs.filter(func(cmd): return cmd.priority >= priority)
	elif priority < highest:
		return
	_buffered_inputs.append({
		"action": action,
		"pressed": pressed,
		"priority": priority,
		"frame": Engine.get_frames_drawn()
	})

# ============================================
# 停帧：冻结场景树，只保留己方实体运行
# ============================================

var _freeze_frame_active: bool = false

func start_freeze_frame(duration: float):
	if _freeze_frame_active:
		return
	_freeze_frame_active = true

	get_tree().paused = true
	# 将所有玩家实体设为 PROCESS_MODE_ALWAYS，使其在暂停下继续运行
	var players = get_tree().get_nodes_in_group("player_entities")
	for p in players:
		_set_node_always(p)

	get_tree().create_timer(duration, false, true, true).timeout.connect(
		func(): _end_freeze_frame(players), CONNECT_ONE_SHOT
	)

func _set_node_always(node: Node):
	node.process_mode = PROCESS_MODE_ALWAYS
	for c in node.get_children():
		_set_node_always(c)

func _end_freeze_frame(players: Array):
	get_tree().paused = false
	for p in players:
		if is_instance_valid(p):
			p.process_mode = PROCESS_MODE_INHERIT
			for c in p.get_children():
				c.process_mode = PROCESS_MODE_INHERIT
	_freeze_frame_active = false

# ============================================
# 时停：只停倒计时，实体不受影响
# ============================================

var time_stop_active: bool = false

func start_time_stop(duration: float):
	if time_stop_active:
		return
	time_stop_active = true
	get_tree().create_timer(duration, false, true, true).timeout.connect(
		_end_time_stop, CONNECT_ONE_SHOT
	)

func _end_time_stop():
	time_stop_active = false
