extends TextureRect

var active_touches: Dictionary = {}  # touch_index -> SkillSlot

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_press(event)
		else:
			_handle_release(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_press(event):
	var slot = _get_slot_at(event.position)
	if slot:
		active_touches[event.index] = slot
		slot._press_visual()
		accept_event()

func _handle_release(event):
	if active_touches.has(event.index):
		var slot = active_touches[event.index]
		if is_instance_valid(slot):
			slot._release_visual()
		active_touches.erase(event.index)
		accept_event()

func _handle_drag(event):
	if active_touches.has(event.index):
		var slot = active_touches[event.index]
		if is_instance_valid(slot):
			if not slot._is_point_inside_screen(event.position):
				slot._release_visual()
				active_touches.erase(event.index)
				accept_event()
				return
			accept_event()

func _get_slot_at(pos: Vector2) -> SkillSlot:
	for i in range(get_child_count() - 1, -1, -1):
		var child = get_child(i)
		if child is SkillSlot and child._is_point_inside_screen(pos):
			return child
	return null
