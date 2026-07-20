# info_point_editor.gd
@tool
extends Window

const ANIM_FPS := 60.0

# 数据结构
var _info_points: Array = []
var _current_point_id: String = ""
var _entity_scene_path: String = ""
var _has_unsaved_changes: bool = false
var _entity_instance: Node = null
var _anim_entity: EntityBase = null
var _is_anim_player_entity: bool = false

# ==========================================
# 视觉设置
# ==========================================
var preview_root_position: Vector2 = Vector2(300, 300) # 逻辑中心位置
var point_opacity: float = 1.0 
var _canvas_zoom: float = 1.0 # 当前画布缩放比例

# 拖拽状态
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

# 画布平移状态
var _is_panning: bool = false
var _pan_start_mouse_pos: Vector2 = Vector2.ZERO
var _pan_start_offset: Vector2 = Vector2.ZERO

# UI 引用
var _point_list: ItemList
var _canvas: Control
var _draw_node: Node2D
var _interaction_layer: Control
var _preview_sprite: AnimatedSprite2D
var _name_line_edit: LineEdit
var _pos_x_spin: SpinBox
var _pos_y_spin: SpinBox
var _ref_anim_selector: OptionButton
var _frame_spin: SpinBox

func _ready():
	size = Vector2(1100, 750)
	min_size = Vector2(800, 600)
	close_requested.connect(_on_close_requested)
	_update_title()
	_setup_ui()


func _update_title():
	var base = "信息点编辑器"
	if _entity_scene_path != "":
		var trimmed = _entity_scene_path.trim_prefix("res://assets/entities/")
		var last_slash = trimmed.rfind("/")
		var name = trimmed.substr(0, last_slash) if last_slash >= 0 else trimmed
		base += " - " + name
	title = base


func _on_close_requested():
	if _has_unsaved_changes:
		_show_save_dialog()
	else:
		queue_free()

func _show_save_dialog():
	var dialog = ConfirmationDialog.new()
	dialog.title = "未保存的更改"
	dialog.dialog_text = "有未保存的更改，是否保存？"
	dialog.ok_button_text = "保存"
	dialog.cancel_button_text = "不保存"
	dialog.add_button("取消", false, "cancel")
	dialog.confirmed.connect(_on_save_and_exit.bind(dialog))
	dialog.canceled.connect(_on_discard_and_exit.bind(dialog))
	dialog.custom_action.connect(_on_dialog_cancel.bind(dialog))
	add_child(dialog)
	dialog.popup_centered()

func _on_dialog_cancel(action: String, dialog: ConfirmationDialog):
	if action == "cancel":
		dialog.queue_free()

func _on_save_and_exit(dialog: ConfirmationDialog):
	dialog.queue_free()
	_on_save_data()
	queue_free()

func _on_discard_and_exit(dialog: ConfirmationDialog):
	dialog.queue_free()
	queue_free()

func _input(event: InputEvent):
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S and event.ctrl_pressed:
			_on_save_data()
			get_viewport().set_input_as_handled()

# ==========================================
# 外部调用接口
# ==========================================
func setup(entity: Node, visual_node: Node2D, scene_path: String):
	_entity_scene_path = scene_path
	_entity_instance = entity
	_update_title()
	
	# 检测实体类型
	if entity is EntityBase:
		_anim_entity = entity as EntityBase
		_is_anim_player_entity = _find_animation_player(entity) != null
	else:
		_is_anim_player_entity = false
	
	_load_existing_data()
	_setup_entity_preview()
	_refresh_list()
	_refresh_anim_selector()
	if _info_points.size() > 0:
		_point_list.select(0)
		_on_point_selected(0)
	popup_centered()

# ==========================================
# UI 构建
# ==========================================
func _setup_ui():
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 10)
	main_hbox.offset_left = 10
	main_hbox.offset_top = 10
	main_hbox.offset_right = -10
	main_hbox.offset_bottom = -10
	add_child(main_hbox)

	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size.x = 220
	main_hbox.add_child(left_vbox)

	left_vbox.add_child(_create_label("信息点列表 (名[动画_帧])", 14))
	_point_list = ItemList.new()
	_point_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_point_list.item_selected.connect(_on_point_selected)
	left_vbox.add_child(_point_list)

	var btn_hbox = HBoxContainer.new()
	left_vbox.add_child(btn_hbox)
	var add_btn = Button.new()
	add_btn.text = "添加当前帧"
	add_btn.pressed.connect(_on_add_point)
	btn_hbox.add_child(add_btn)
	var del_btn = Button.new()
	del_btn.text = "删除"
	del_btn.pressed.connect(_on_del_point)
	btn_hbox.add_child(del_btn)

	var center_vbox = VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(center_vbox)

	center_vbox.add_child(_create_label("画布 (中键平移 | 滚轮缩放 | 亮色=当前帧)", 12))
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	center_vbox.add_child(_canvas)

	# 绘制层 - Z-Index 设高，但不缩放节点本身
	_draw_node = Node2D.new()
	_draw_node.name = "DrawNode"
	_draw_node.z_index = 100
	_draw_node.z_as_relative = false
	_draw_node.draw.connect(_on_canvas_draw)
	_canvas.add_child(_draw_node)

	# 交互层
	_interaction_layer = ColorRect.new()
	_interaction_layer.name = "InteractionLayer"
	_interaction_layer.color = Color(0, 0, 0, 0)
	_interaction_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_interaction_layer.z_index = 101
	_interaction_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_interaction_layer.gui_input.connect(_on_interaction_input)
	_canvas.add_child(_interaction_layer)

	var right_vbox = VBoxContainer.new()
	right_vbox.custom_minimum_size.x = 200
	main_hbox.add_child(right_vbox)

	right_vbox.add_child(_create_label("属性编辑", 16))
	var name_hbox = HBoxContainer.new()
	right_vbox.add_child(name_hbox)
	name_hbox.add_child(_create_label("名称:", 14, 60))
	_name_line_edit = LineEdit.new()
	_name_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_line_edit.text_changed.connect(_on_name_changed)
	name_hbox.add_child(_name_line_edit)

	right_vbox.add_child(HSeparator.new())
	right_vbox.add_child(_create_label("坐标 (相对实体中心0,0)", 12))
	_pos_x_spin = _create_spinbox("X:", -999999, 999999, 0.1, right_vbox)
	_pos_y_spin = _create_spinbox("Y:", -999999, 999999, 0.1, right_vbox)
	_pos_x_spin.value_changed.connect(_on_pos_changed)
	_pos_y_spin.value_changed.connect(_on_pos_changed)

	right_vbox.add_child(HSeparator.new())
	right_vbox.add_child(_create_label("所属动画与帧 (修改会同步保存)", 12))
	var anim_hbox = HBoxContainer.new()
	right_vbox.add_child(anim_hbox)
	anim_hbox.add_child(_create_label("动画:", 14, 50))
	_ref_anim_selector = OptionButton.new()
	_ref_anim_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ref_anim_selector.item_selected.connect(_on_ref_anim_changed)
	anim_hbox.add_child(_ref_anim_selector)

	var frame_hbox = HBoxContainer.new()
	right_vbox.add_child(frame_hbox)
	frame_hbox.add_child(_create_label("帧:", 14, 50))
	_frame_spin = SpinBox.new()
	_frame_spin.min_value = 0
	_frame_spin.max_value = 0
	_frame_spin.step = 1
	_frame_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_spin.value_changed.connect(_on_frame_spin_changed)
	frame_hbox.add_child(_frame_spin)

	right_vbox.add_child(HSeparator.new())
	var save_btn = Button.new()
	save_btn.text = "保存数据"
	save_btn.pressed.connect(_on_save_data)
	save_btn.add_theme_color_override("font_color", Color.CYAN)
	right_vbox.add_child(save_btn)

func _create_label(text: String, size: int = 14, min_w: int = 0) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		lbl.custom_minimum_size.x = min_w
	return lbl

func _create_spinbox(label_text: String, min_v: float, max_v: float, step: float, parent: Control) -> SpinBox:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)
	hbox.add_child(_create_label(label_text, 14, 40))
	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spin)
	return spin

# ==========================================
# 数据加载与保存
# ==========================================
func _load_existing_data():
	_info_points.clear()
	var data_path = _entity_scene_path.get_base_dir() + "/info_points.json"
	if not FileAccess.file_exists(data_path):
		return
	var file = FileAccess.open(data_path, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()
	var data = json.data
	if data is Dictionary and data.has("points"):
		_info_points = data["points"]

func _on_save_data():
	var data = {"points": _info_points}
	var data_path = _entity_scene_path.get_base_dir() + "/info_points.json"
	var file = FileAccess.open(data_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		_has_unsaved_changes = false
		print("信息点已保存到: ", data_path)

# ==========================================
# 动画抽象接口（兼容 AnimatedSprite2D 和 AnimationPlayer）
# ==========================================
func _get_anim_names() -> PackedStringArray:
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap:
			var names = ap.get_animation_list()
			print("[info_point] _get_anim_names: AnimationPlayer found, anims=%s" % [str(names)])
			return names
	if _preview_sprite and _preview_sprite.sprite_frames:
		var names = _preview_sprite.sprite_frames.get_animation_names()
		print("[info_point] _get_anim_names: AnimatedSprite2D, anims=%s" % [str(names)])
		return names
	print("[info_point] _get_anim_names: no source found, return empty")
	return PackedStringArray()

func _get_anim_frame_count(anim_name: String) -> int:
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap and ap.has_animation(anim_name):
			var anim = ap.get_animation(anim_name)
			var count = int(anim.length * ANIM_FPS)
			print("[info_point] _get_anim_frame_count(%s) = %d" % [anim_name, count])
			return count
	if _preview_sprite and _preview_sprite.sprite_frames:
		var count = _preview_sprite.sprite_frames.get_frame_count(anim_name)
		print("[info_point] _get_anim_frame_count(%s) = %d (sprite)" % [anim_name, count])
		return count
	print("[info_point] _get_anim_frame_count(%s) = 0 (fallback)" % anim_name)
	return 0

func _set_preview_frame(anim_name: String, frame_idx: int):
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap:
			ap.stop()
			if ap.has_animation(anim_name):
				ap.play(anim_name)
				ap.seek(frame_idx / ANIM_FPS, true)
				ap.stop()
				print("[info_point] _set_preview_frame(%s, %d): AnimationPlayer seek OK" % [anim_name, frame_idx])
			else:
				print("[info_point] _set_preview_frame(%s, %d): anim not found" % [anim_name, frame_idx])
			return
		print("[info_point] _set_preview_frame(%s, %d): AnimationPlayer not found, fallback to sprite" % [anim_name, frame_idx])
	if _preview_sprite:
		_preview_sprite.animation = anim_name
		_preview_sprite.frame = frame_idx

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null

# ==========================================
# 预览与动画
# ==========================================
func _setup_entity_preview():
	for child in _canvas.get_children():
		if child.name == "EntityPreview":
			child.queue_free()
	if not _entity_instance:
		return

	# 实例化场景而非 duplicate()——避免 GLB 节点复制 BUG
	var preview
	if _is_anim_player_entity and _entity_scene_path and _entity_scene_path != "":
		preview = load(_entity_scene_path).instantiate()
	else:
		preview = _entity_instance.duplicate()
	preview.name = "EntityPreview"
	# 防止 EntityPreview 拦截鼠标事件（让 InteractionLayer 能接收事件）
	if preview is CollisionObject2D:
		(preview as CollisionObject2D).input_pickable = false
	_canvas.add_child(preview)
	
	if _is_anim_player_entity:
		_preview_sprite = null
	else:
		_preview_sprite = _find_animated_sprite(preview)
		if _preview_sprite:
			_preview_sprite.scale = Vector2(1, 1)
	
	# 确保 InteractionLayer 在最上层
	if _interaction_layer:
		_canvas.move_child(_interaction_layer, _canvas.get_child_count() - 1)
	
	call_deferred("_center_preview")

func _find_animated_sprite(node: Node) -> AnimatedSprite2D:
	if node is AnimatedSprite2D:
		return node
	if node.has_node("Visuals/AnimatedSprite2D"):
		return node.get_node("Visuals/AnimatedSprite2D")
	if node.has_node("AnimatedSprite2D"):
		return node.get_node("AnimatedSprite2D")
	for child in node.get_children():
		var found = _find_animated_sprite(child)
		if found:
			return found
	return null

func _center_preview():
	if _is_anim_player_entity:
		if not _canvas or not _canvas.get_node_or_null("EntityPreview"):
			return
	elif not _canvas or not _canvas.get_node_or_null("EntityPreview"):
		return
	await get_tree().process_frame
	_apply_canvas_transform()
	_update_preview_animation()

# 应用画布变换：实体缩放，但绘制节点不缩放
func _apply_canvas_transform():
	var preview_root = _canvas.get_node("EntityPreview")
	if not preview_root: return
	
	# 1. 实体预览：缩放并移动
	preview_root.position = preview_root_position * _canvas_zoom
	preview_root.scale = Vector2(_canvas_zoom, _canvas_zoom)
	
	# 2. 绘制节点：只移动，不缩放 (Scale保持1.0)
	# 这样我们在draw函数里画点时，点的大小才不会变
	_draw_node.position = preview_root_position * _canvas_zoom
	_draw_node.scale = Vector2(1, 1) 
	
	_draw_node.queue_redraw()

func _refresh_anim_selector():
	_ref_anim_selector.clear()
	var anims = _get_anim_names()
	for a in anims:
		_ref_anim_selector.add_item(a)
	if anims.size() > 0:
		_ref_anim_selector.select(0)
		_update_preview_animation()

func _update_preview_animation(force_anim_name: String = ""):
	if _is_anim_player_entity:
		# AnimationPlayerEntity: 通过 seek 设置帧
		var anim_name = force_anim_name
		if anim_name == "":
			if _ref_anim_selector.selected < 0:
				return
			anim_name = _ref_anim_selector.get_item_text(_ref_anim_selector.selected)
		if _frame_spin:
			_frame_spin.max_value = max(0, _get_anim_frame_count(anim_name) - 1)
		_set_preview_frame(anim_name, int(_frame_spin.value) if _frame_spin else 0)
		_draw_node.queue_redraw()
		return
	
	if not _preview_sprite:
		return
	var anim_name = force_anim_name
	if anim_name == "":
		if _ref_anim_selector.selected < 0:
			return
		anim_name = _ref_anim_selector.get_item_text(_ref_anim_selector.selected)
	
	if _frame_spin and _preview_sprite.sprite_frames.has_animation(anim_name):
		_frame_spin.max_value = max(0, _preview_sprite.sprite_frames.get_frame_count(anim_name) - 1)
		_preview_sprite.stop()
		_preview_sprite.animation = anim_name
		_preview_sprite.frame = int(_frame_spin.value)
	
	_draw_node.queue_redraw()

# ==========================================
# 数据与列表逻辑
# ==========================================
func _refresh_list():
	_point_list.clear()
	for pt in _info_points:
		var display_name = pt["name"] + " [" + pt.get("anim", "?") + "_" + str(pt.get("frame", 0)) + "]"
		_point_list.add_item(display_name)
		_point_list.set_item_metadata(_point_list.item_count - 1, pt["id"])

func _get_current_point_dict() -> Dictionary:
	if _current_point_id == "":
		return {}
	for pt in _info_points:
		if pt["id"] == _current_point_id:
			return pt
	return {}

func _on_add_point():
	var current_anim_name = ""
	var current_frame_idx = 0
	if _preview_sprite and _ref_anim_selector.selected >= 0:
		current_anim_name = _ref_anim_selector.get_item_text(_ref_anim_selector.selected)
		current_frame_idx = int(_frame_spin.value)
	var new_pt = {
		"id": "ip_" + str(Time.get_unix_time_from_system()),
		"name": "NewPoint_" + str(_info_points.size()),
		"anim": current_anim_name,
		"frame": current_frame_idx,
		"x": 0.0,
		"y": 0.0
	}
	_info_points.append(new_pt)
	_refresh_list()
	_point_list.select(_point_list.item_count - 1)
	_on_point_selected(_point_list.item_count - 1)
	_has_unsaved_changes = true

func _on_del_point():
	if _current_point_id == "":
		return
	var new_array = []
	for pt in _info_points:
		if pt["id"] != _current_point_id:
			new_array.append(pt)
	_info_points = new_array
	_current_point_id = ""
	_refresh_list()
	_update_property_panel({})
	_has_unsaved_changes = true

func _on_point_selected(index: int):
	if index < 0:
		return
	_current_point_id = _point_list.get_item_metadata(index)
	var pt = _get_current_point_dict()
	
	_frame_spin.value_changed.disconnect(_on_frame_spin_changed)
	_ref_anim_selector.item_selected.disconnect(_on_ref_anim_changed)
	
	_update_property_panel(pt)
	
	if pt.has("anim") and pt["anim"] != "":
		var target_anim = pt["anim"]
		var target_frame = pt.get("frame", 0)
		if _is_anim_player_entity:
			_frame_spin.max_value = max(0, _get_anim_frame_count(target_anim) - 1)
			_frame_spin.value = target_frame
			for i in range(_ref_anim_selector.item_count):
				if _ref_anim_selector.get_item_text(i) == target_anim:
					if _ref_anim_selector.selected != i:
						_ref_anim_selector.select(i)
					break
			_update_preview_animation(target_anim)
		elif _preview_sprite and _preview_sprite.sprite_frames.has_animation(target_anim):
			_frame_spin.max_value = max(0, _preview_sprite.sprite_frames.get_frame_count(target_anim) - 1)
			_frame_spin.value = target_frame
			for i in range(_ref_anim_selector.item_count):
				if _ref_anim_selector.get_item_text(i) == target_anim:
					if _ref_anim_selector.selected != i:
						_ref_anim_selector.select(i)
					break
			_update_preview_animation(target_anim)
			
	_frame_spin.value_changed.connect(_on_frame_spin_changed)
	_ref_anim_selector.item_selected.connect(_on_ref_anim_changed)
	
	_draw_node.queue_redraw()

func _update_property_panel(pt: Dictionary):
	_pos_x_spin.value_changed.disconnect(_on_pos_changed)
	_pos_y_spin.value_changed.disconnect(_on_pos_changed)
	_name_line_edit.text_changed.disconnect(_on_name_changed)
	
	if pt.is_empty():
		_name_line_edit.text = ""
		_pos_x_spin.value = 0
		_pos_y_spin.value = 0
	else:
		_name_line_edit.text = pt.get("name", "")
		_pos_x_spin.value = pt.get("x", 0)
		_pos_y_spin.value = pt.get("y", 0)
		
	_pos_x_spin.value_changed.connect(_on_pos_changed)
	_pos_y_spin.value_changed.connect(_on_pos_changed)
	_name_line_edit.text_changed.connect(_on_name_changed)

# ==========================================
# 属性修改回调
# ==========================================
func _on_name_changed(new_name: String):
	var pt = _get_current_point_dict()
	if pt.is_empty():
		return
	pt["name"] = new_name
	var idx = _point_list.get_selected_items()
	if idx.size() > 0:
		var display_name = new_name + " [" + pt.get("anim", "?") + "_" + str(pt.get("frame", 0)) + "]"
		_point_list.set_item_text(idx[0], display_name)
	_has_unsaved_changes = true

func _on_pos_changed(_val: float):
	var pt = _get_current_point_dict()
	if pt.is_empty():
		return
	pt["x"] = _pos_x_spin.value
	pt["y"] = _pos_y_spin.value
	_draw_node.queue_redraw()
	_has_unsaved_changes = true

func _on_ref_anim_changed(index: int):
	var anim_name = _ref_anim_selector.get_item_text(index) if index >= 0 else ""
	var total = _get_anim_frame_count(anim_name)
	print("[info_point] _on_ref_anim_changed: anim=%s, total_frames=%d" % [anim_name, total])
	_update_preview_animation()
	_sync_anim_frame_to_point()

func _sync_anim_frame_to_point():
	var pt = _get_current_point_dict()
	if pt.is_empty():
		return
	_has_unsaved_changes = true
	if _ref_anim_selector.selected >= 0:
		pt["anim"] = _ref_anim_selector.get_item_text(_ref_anim_selector.selected)
		pt["frame"] = int(_frame_spin.value)
		var idx = _point_list.get_selected_items()
		if idx.size() > 0:
			var display_name = pt.get("name", "") + " [" + pt.get("anim", "?") + "_" + str(pt.get("frame", 0)) + "]"
			_point_list.set_item_text(idx[0], display_name)

func _on_frame_spin_changed(value: float):
	var frame_idx = int(value)
	print("[info_point] _on_frame_spin_changed: frame=%d" % frame_idx)
	if _is_anim_player_entity:
		_set_preview_frame(_ref_anim_selector.get_item_text(_ref_anim_selector.selected) if _ref_anim_selector.selected >= 0 else "", frame_idx)
	elif _preview_sprite:
		_preview_sprite.frame = frame_idx
	_draw_node.queue_redraw()
	_sync_anim_frame_to_point()

# ==========================================
# 交互逻辑 (屏幕坐标 <-> 逻辑坐标 转换)
# ==========================================
func _on_interaction_input(event: InputEvent):
	if not _canvas or not _canvas.get_node_or_null("EntityPreview"):
		return

	# --- 1. 鼠标按键处理 ---
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		
		# 缩放处理 (滚轮)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var zoom_factor = 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9
			var old_zoom = _canvas_zoom
			_canvas_zoom = clamp(_canvas_zoom * zoom_factor, 0.1, 10.0)
			
			# 以鼠标为中心缩放
			var mouse_pos = mb.position
			var logical_mouse_before = (mouse_pos / old_zoom) - preview_root_position
			preview_root_position = (mouse_pos / _canvas_zoom) - logical_mouse_before
			
			_apply_canvas_transform()
			return

		# 平移处理 (中键)
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_panning = true
				_pan_start_mouse_pos = mb.position
				_pan_start_offset = preview_root_position
			else:
				_is_panning = false
		
		# 点拖拽处理 (左键)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _is_panning: return
				
				# 屏幕坐标 -> 逻辑坐标
				# 逻辑坐标 = (屏幕坐标 / 缩放) - 中心偏移
				var logical_mouse = (mb.position / _canvas_zoom) - preview_root_position
				
				for pt in _info_points:
					var pt_pos = Vector2(pt["x"], pt["y"])
					# 检测半径：由于点是固定屏幕大小(约14px)，检测范围也应该是固定的，稍微大一点如 20px
					# 转换到逻辑距离：屏幕距离 / 缩放
					var click_threshold_logic = 20.0 / _canvas_zoom
					
					if logical_mouse.distance_to(pt_pos) < click_threshold_logic:
						_is_dragging = true
						_drag_offset = pt_pos - logical_mouse
						for i in range(_point_list.item_count):
							if _point_list.get_item_metadata(i) == pt["id"]:
								_point_list.select(i)
								_on_point_selected(i)
								break
						return
			else:
				if _is_dragging:
					_is_dragging = false

	# --- 2. 鼠标移动处理 ---
	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		
		if _is_panning:
			# 平移：屏幕移动距离 / 缩放 = 逻辑移动距离
			var drag_delta = (mm.position - _pan_start_mouse_pos) / _canvas_zoom
			preview_root_position = _pan_start_offset + drag_delta
			_apply_canvas_transform()
			return
		
		elif _is_dragging:
			# 拖拽点：屏幕坐标 -> 逻辑坐标
			var logical_mouse = (mm.position / _canvas_zoom) - preview_root_position
			
			var new_local_pos = logical_mouse + _drag_offset
			var pt = _get_current_point_dict()
			if pt.is_empty():
				return
			pt["x"] = new_local_pos.x
			pt["y"] = new_local_pos.y
			
			_pos_x_spin.value_changed.disconnect(_on_pos_changed)
			_pos_y_spin.value_changed.disconnect(_on_pos_changed)
			_pos_x_spin.value = pt["x"]
			_pos_y_spin.value = pt["y"]
			_pos_x_spin.value_changed.connect(_on_pos_changed)
			_pos_y_spin.value_changed.connect(_on_pos_changed)
			
			_draw_node.queue_redraw()
			_has_unsaved_changes = true

# ==========================================
# 绘制逻辑 (手动处理缩放)
# ==========================================
func _on_canvas_draw():
	
	
	# 逻辑坐标 (x,y) 映射到节点的 (x * 缩放, y * 缩放) 处
	
	# 画坐标轴参考线 (需要缩放长度)
	var axis_len = 50 * _canvas_zoom
	_draw_node.draw_line(Vector2(0, 0), Vector2(axis_len, 0), Color.RED, 1.0)
	_draw_node.draw_line(Vector2(0, 0), Vector2(0, axis_len), Color.GREEN, 1.0)

	var current_preview_anim = ""
	var current_preview_frame = 0
	if _ref_anim_selector.selected >= 0:
		current_preview_anim = _ref_anim_selector.get_item_text(_ref_anim_selector.selected)
		current_preview_frame = int(_frame_spin.value)

	for pt in _info_points:
		# 计算绘制坐标 = 逻辑坐标 * 缩放系数
		var draw_pos = Vector2(pt["x"], pt["y"]) * _canvas_zoom
		
		var is_selected = (pt["id"] == _current_point_id)
		var is_current_frame = (pt.get("anim", "") == current_preview_anim and pt.get("frame", 0) == current_preview_frame)

		var color: Color
		var size: float = 14.0 # 固定屏幕像素大小
		
		if is_selected:
			color = Color(1.0, 1.0, 0.0, point_opacity) # 黄色
		elif is_current_frame:
			color = Color(1.0, 0.6, 0.0, point_opacity) # 橙色
		else:
			color = Color(0.5, 0.5, 0.5, point_opacity) # 灰色

		# 绘制菱形
		var points = PackedVector2Array([
			draw_pos + Vector2(0, -size),
			draw_pos + Vector2(size, 0),
			draw_pos + Vector2(0, size),
			draw_pos + Vector2(-size, 0)
		])
		_draw_node.draw_colored_polygon(points, color)

		if is_selected:
			var outline = PackedVector2Array(points)
			outline.append(points[0])
			_draw_node.draw_polyline(outline, Color.WHITE, 2.0)

		# 绘制十字线 (固定大小)
		var cross_size = 6.0
		var cross_color = Color.WHITE if is_selected else Color(0.8, 0.8, 0.8, 0.8)
		_draw_node.draw_line(draw_pos + Vector2(-cross_size, 0), draw_pos + Vector2(cross_size, 0), cross_color, 1.5)
		_draw_node.draw_line(draw_pos + Vector2(0, -cross_size), draw_pos + Vector2(0, cross_size), cross_color, 1.5)
		
		# 绘制文字
		_draw_node.draw_string(ThemeDB.fallback_font, draw_pos + Vector2(15, -10), pt["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if _is_anim_player_entity:
			if _canvas and _canvas.get_node_or_null("EntityPreview"):
				_apply_canvas_transform()
				if _ref_anim_selector.selected >= 0:
					_update_preview_animation()
		elif _preview_sprite and _canvas:
			_apply_canvas_transform()
			if _ref_anim_selector.selected >= 0:
				_update_preview_animation()
