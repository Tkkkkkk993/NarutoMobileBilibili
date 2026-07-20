extends Node

signal time_scale_changed(new_scale: float)

enum Priority {
	SUBSTITUTION = 0,
	ATTACK = 2,
	SKILL = 2,
	ULTIMATE = 3,
	SCROLL = 4,
	SUMMON = 4,
}

var is_time_stopped: bool = false
var _buffered_events: Array[Dictionary] = []
var _buffer_enabled: bool = false

func on_button_pressed(slot_id: int, action_name: String, priority: int) -> void:
	var player = _get_player()
	if not player:
		return
	if is_time_stopped:
		_buffer_event(slot_id, action_name, priority)
	else:
		if player.has_method("handle_button_press"):
			player.handle_button_press(slot_id, action_name, priority)

func start_time_stop(duration: float = 0.5) -> void:
	if is_time_stopped:
		return
	is_time_stopped = true
	_buffer_enabled = true
	Engine.time_scale = 0.0
	time_scale_changed.emit(0.0)
	get_tree().create_timer(duration, false).timeout.connect(_end_time_stop)

func _end_time_stop() -> void:
	Engine.time_scale = 1.0
	is_time_stopped = false
	_buffer_enabled = false
	time_scale_changed.emit(1.0)
	_flush_buffered()

func _buffer_event(slot_id: int, action_name: String, priority: int) -> void:
	var highest = -1
	for ev in _buffered_events:
		if ev.priority > highest:
			highest = ev.priority
	if priority > highest:
		_buffered_events = _buffered_events.filter(func(e): return e.priority >= priority)
	elif priority < highest:
		return
	# 移除同名按钮旧事件
	_buffered_events = _buffered_events.filter(func(e): return not (e.slot_id == slot_id and e.action_name == action_name))
	_buffered_events.append({
		"slot_id": slot_id,
		"action_name": action_name,
		"priority": priority,
		"frame": Engine.get_frames_drawn()
	})

func _flush_buffered() -> void:
	if _buffered_events.is_empty():
		return
	_buffered_events.sort_custom(func(a,b): 
		if a.priority != b.priority: return a.priority > b.priority
		return a.frame < b.frame
	)
	var player = _get_player()
	if player and player.has_method("handle_button_press"):
		for ev in _buffered_events:
			player.handle_button_press(ev.slot_id, ev.action_name, ev.priority)
	_buffered_events.clear()

func _get_player() -> Node:
	var players = get_tree().get_nodes_in_group("player_entities")
	return players[0] if players.size() > 0 else null
