# attack_box_editor.gd (坐标系修复版 - Y=深度, Z=高度)
@tool
extends Window

const ANIM_FPS := 60.0

# ==========================================
# 操作记录类（撤回重做）
# ==========================================
class EditorAction:
	var type: String
	var data: Dictionary
	var timestamp: int

	func _init(t: String, d: Dictionary):
		type = t
		data = d
		timestamp = Time.get_ticks_msec()

var _entity_instance: Node = null
var _animated_sprite: AnimatedSprite2D = null
var _anim_entity: EntityBase = null
var _is_anim_player_entity: bool = false
var _entity_scene_path: String = ""

var _attack_boxes: Dictionary = {}
var _current_box_id: String = ""

# ==========================================
# 画布变换
# ==========================================
var preview_root_position: Vector2 = Vector2(300, 300)
var _canvas_zoom: float = 1.0

# 拖拽状态
var _is_dragging: bool = false
var _drag_box_id: String = ""
var _drag_offset: Vector2 = Vector2.ZERO

# 画布平移状态
var _is_panning: bool = false
var _pan_start_mouse_pos: Vector2 = Vector2.ZERO
var _pan_start_offset: Vector2 = Vector2.ZERO

# UI 节点引用
var _box_list: ItemList
var _anim_selector: OptionButton
var _frame_selector: SpinBox
var _canvas: Control
var _draw_node: Node2D
var _interaction_layer: Control
var _preview_sprite: AnimatedSprite2D = null
var _preview_visuals: Node2D = null

# 存储原始 sprite 的 scale（setup 时从 _animated_sprite 获取，避免被预览节点影响）
var _sprite_scale: Vector2 = Vector2.ONE

# 属性编辑器引用
var _pos_x: SpinBox
var _pos_y: SpinBox
var _pos_z: SpinBox
var _size_x: SpinBox
var _size_y: SpinBox
var _size_z: SpinBox

var _copy_buffer: Dictionary = {}
var _has_unsaved_changes: bool = false

# 缩放控件
var handle_size: float = 16.0
const HANDLE_SIZE_MIN: float = 4.0
const HANDLE_SIZE_MAX: float = 48.0
var _handle_size_slider: HSlider
var _handle_size_value_label: Label

# 调整大小状态
var _is_resizing: bool = false
var _resize_handle: String = ""
var _resize_start_mouse: Vector2 = Vector2.ZERO

# 撤回重做系统
var undo_stack: Array = []
var redo_stack: Array = []
var max_undo_steps: int = 50
var is_recording_action: bool = true
var drag_prev_state: EditorAction = null
var _pending_property_action: Dictionary = {}  # {box_id, frame, prev_config_snapshot}

# 撤回/重做按钮
var _undo_button: Button
var _redo_button: Button

# 锚点数据（从帧数据JSON单独加载）: anim_name -> { frame_idx -> Vector2 }
var _anchor_data: Dictionary = {}

func _ready():
	size = Vector2(1400, 900)
	min_size = Vector2(900, 700)
	close_requested.connect(_on_close_requested)
	_update_title()
	_setup_ui()
	call_deferred("_center_window")


func _update_title():
	var base = "攻击框编辑器"
	if _entity_scene_path != "":
		var trimmed = _entity_scene_path.trim_prefix("res://assets/entities/")
		var last_slash = trimmed.rfind("/")
		var name = trimmed.substr(0, last_slash) if last_slash >= 0 else trimmed
		base += " - " + name
	title = base


func _center_window():
	var screen_size = DisplayServer.screen_get_size()
	position = Vector2((screen_size.x - size.x) / 2, (screen_size.y - size.y) / 2)

func _on_close_requested():
	if _has_unsaved_changes:
		_show_unsaved_dialog()
	else:
		queue_free()

func _input(event: InputEvent):
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed:
			if event.keycode == KEY_S:
				_on_save_data()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_Z:
				_on_undo_pressed()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_Y:
				_on_redo_pressed()
				get_viewport().set_input_as_handled()

func _show_unsaved_dialog():
	var dialog = ConfirmationDialog.new()
	dialog.title = "未保存的更改"
	dialog.dialog_text = "有未保存的更改，是否保存？"
	dialog.ok_button_text = "保存"
	dialog.cancel_button_text = "不保存"
	dialog.add_button("取消", false, "cancel")
	dialog.confirmed.connect(_on_save_and_exit.bind(dialog))
	dialog.canceled.connect(_on_exit_without_save.bind(dialog))
	dialog.custom_action.connect(_on_dialog_custom_action.bind(dialog))
	add_child(dialog)
	dialog.popup_centered()

func _on_save_and_exit(dialog: ConfirmationDialog):
	dialog.queue_free()
	_on_save_data()
	queue_free()

func _on_exit_without_save(dialog: ConfirmationDialog):
	dialog.queue_free()
	queue_free()

func _on_dialog_custom_action(action: String, dialog: ConfirmationDialog):
	if action == "cancel":
		dialog.queue_free()

func setup(entity: Node, visual_node: Node2D, scene_path: String):
	_entity_instance = entity
	_entity_scene_path = scene_path
	_update_title()
	
	# 检测实体类型
	if entity is EntityBase:
		_anim_entity = entity as EntityBase
		_is_anim_player_entity = _find_animation_player(entity) != null
	else:
		_is_anim_player_entity = false
	
	# AnimatedSprite2DEntity: visual_node 是 AnimatedSprite2D
	if visual_node is AnimatedSprite2D:
		_animated_sprite = visual_node as AnimatedSprite2D
		_sprite_scale = _animated_sprite.scale
	
	_load_data_and_setup()

func _load_data_and_setup():
	_load_existing_data()
	_load_anchor_data()
	_setup_entity_preview()
	_refresh_animation_list()
	if _anim_selector.item_count > 0:
		_anim_selector.select(0)
		_on_anim_selected(0)
	_has_unsaved_changes = false

# ==========================================
# UI 构建
# ==========================================
func _setup_ui():
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.offset_left = 10
	main_hbox.offset_top = 10
	main_hbox.offset_right = -10
	main_hbox.offset_bottom = -10
	add_child(main_hbox)

	# 左侧面板
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(280, 0)
	main_hbox.add_child(left_vbox)

	var left_title = Label.new()
	left_title.text = "攻击框列表"
	left_title.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(left_title)

	_box_list = ItemList.new()
	_box_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box_list.item_selected.connect(_on_box_selected)
	left_vbox.add_child(_box_list)

	var left_btn_hbox = HBoxContainer.new()
	left_vbox.add_child(left_btn_hbox)

	var add_btn = Button.new()
	add_btn.text = "添加攻击框"
	add_btn.pressed.connect(_on_add_box)
	left_btn_hbox.add_child(add_btn)

	var del_btn = Button.new()
	del_btn.text = "删除"
	del_btn.pressed.connect(_on_delete_box)
	left_btn_hbox.add_child(del_btn)

	# 中间编辑区
	var center_vbox = VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(center_vbox)

	var center_title = Label.new()
	center_title.text = "编辑区域（红色=有数据，灰色=无数据 | 左键拖拽/缩放 | 中键平移 | 滚轮缩放）"
	center_title.add_theme_font_size_override("font_size", 12)
	center_vbox.add_child(center_title)

	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	center_vbox.add_child(_canvas)

	# 绘制层
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
	_interaction_layer.z_as_relative = false
	_interaction_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_interaction_layer.gui_input.connect(_on_interaction_input)
	_canvas.add_child(_interaction_layer)

	# 右侧面板
	var right_vbox = VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(220, 0)
	main_hbox.add_child(right_vbox)

	var right_title = Label.new()
	right_title.text = "属性编辑"
	right_title.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(right_title)

	# 动画选择
	var anim_hbox = HBoxContainer.new()
	right_vbox.add_child(anim_hbox)
	var anim_label = Label.new()
	anim_label.text = "绑定动画:"
	anim_label.custom_minimum_size = Vector2(90, 0)
	anim_hbox.add_child(anim_label)

	_anim_selector = OptionButton.new()
	_anim_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_selector.item_selected.connect(_on_anim_selected)
	anim_hbox.add_child(_anim_selector)

	# 帧选择
	var frame_hbox = HBoxContainer.new()
	right_vbox.add_child(frame_hbox)
	var frame_label = Label.new()
	frame_label.text = "当前帧:"
	frame_label.custom_minimum_size = Vector2(90, 0)
	frame_hbox.add_child(frame_label)

	_frame_selector = SpinBox.new()
	_frame_selector.min_value = 0
	_frame_selector.max_value = 999
	_frame_selector.value_changed.connect(_on_frame_changed)
	_frame_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_hbox.add_child(_frame_selector)

	# 帧控制按钮
	var frame_btn_hbox = HBoxContainer.new()
	right_vbox.add_child(frame_btn_hbox)

	var prev_frame_btn = Button.new()
	prev_frame_btn.text = "< 上一帧"
	prev_frame_btn.pressed.connect(_on_prev_frame)
	frame_btn_hbox.add_child(prev_frame_btn)

	var next_frame_btn = Button.new()
	next_frame_btn.text = "下一帧 >"
	next_frame_btn.pressed.connect(_on_next_frame)
	frame_btn_hbox.add_child(next_frame_btn)

	# 复制粘贴
	right_vbox.add_child(HSeparator.new())
	var copy_paste_title = Label.new()
	copy_paste_title.text = "复制粘贴"
	right_vbox.add_child(copy_paste_title)

	var copy_paste_hbox = HBoxContainer.new()
	right_vbox.add_child(copy_paste_hbox)

	var copy_btn = Button.new()
	copy_btn.text = "复制当前帧"
	copy_btn.pressed.connect(_on_copy_frame)
	copy_paste_hbox.add_child(copy_btn)

	var paste_btn = Button.new()
	paste_btn.text = "粘贴到当前帧"
	paste_btn.pressed.connect(_on_paste_frame)
	copy_paste_hbox.add_child(paste_btn)

	# 撤回重做
	right_vbox.add_child(HSeparator.new())
	var undo_redo_title = Label.new()
	undo_redo_title.text = "撤回 / 重做"
	right_vbox.add_child(undo_redo_title)

	var undo_redo_hbox = HBoxContainer.new()
	right_vbox.add_child(undo_redo_hbox)

	_undo_button = Button.new()
	_undo_button.text = "撤回 (Ctrl+Z)"
	_undo_button.pressed.connect(_on_undo_pressed)
	undo_redo_hbox.add_child(_undo_button)

	_redo_button = Button.new()
	_redo_button.text = "重做 (Ctrl+Y)"
	_redo_button.pressed.connect(_on_redo_pressed)
	undo_redo_hbox.add_child(_redo_button)

	# 位置属性
	right_vbox.add_child(HSeparator.new())
	var pos_title = Label.new()
	pos_title.text = "位置偏移（相对于实体锚点）"
	pos_title.add_theme_color_override("font_color", Color.YELLOW)
	right_vbox.add_child(pos_title)

	_pos_x = _add_spinbox_row(right_vbox, "X:", -999999, 999999, 0, "左右偏移（水平），会自动根据朝向翻转")
	_pos_y = _add_spinbox_row(right_vbox, "Y:", -999999, 999999, 0, "前后深度（纵深），正值=前方")
	_pos_z = _add_spinbox_row(right_vbox, "Z:", -999999, 999999, 0, "上下高度（垂直），正值=上方")

	# 大小属性
	right_vbox.add_child(HSeparator.new())
	var size_title = Label.new()
	size_title.text = "攻击框大小（XYZ三轴）"
	size_title.add_theme_color_override("font_color", Color.YELLOW)
	right_vbox.add_child(size_title)

	_size_x = _add_spinbox_row(right_vbox, "宽(X):", 0, 999999, 50, "水平宽度（左右范围）")
	_size_y = _add_spinbox_row(right_vbox, "深(Y):", 0, 999999, 50, "前后深度范围（纵深碰撞用）")
	_size_z = _add_spinbox_row(right_vbox, "高(Z):", 0, 999999, 50, "垂直高度（上下范围）")

	_connect_value_signals()

	# 操作按钮
	right_vbox.add_child(HSeparator.new())

	var apply_btn = Button.new()
	apply_btn.text = "应用到当前帧"
	apply_btn.pressed.connect(_on_apply_to_frame)
	apply_btn.add_theme_color_override("font_color", Color.GREEN)
	right_vbox.add_child(apply_btn)

	var remove_frame_btn = Button.new()
	remove_frame_btn.text = "删除当前帧配置"
	remove_frame_btn.pressed.connect(_on_remove_frame_config)
	remove_frame_btn.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))
	right_vbox.add_child(remove_frame_btn)

	var save_btn = Button.new()
	save_btn.text = "保存所有数据"
	save_btn.pressed.connect(_on_save_data)
	save_btn.add_theme_color_override("font_color", Color.CYAN)
	right_vbox.add_child(save_btn)

	# 动画控制
	right_vbox.add_child(HSeparator.new())
	var anim_ctrl_title = Label.new()
	anim_ctrl_title.text = "动画预览"
	right_vbox.add_child(anim_ctrl_title)

	var anim_btn_hbox = HBoxContainer.new()
	right_vbox.add_child(anim_btn_hbox)

	var play_btn = Button.new()
	play_btn.text = "播放"
	play_btn.pressed.connect(_on_play_animation)
	anim_btn_hbox.add_child(play_btn)

	var stop_btn = Button.new()
	stop_btn.text = "停止"
	stop_btn.pressed.connect(_on_stop_animation)
	anim_btn_hbox.add_child(stop_btn)

	# ---- 控件大小配置 ----
	right_vbox.add_child(HSeparator.new())
	var handle_size_title = Label.new()
	handle_size_title.text = "控件设置"
	handle_size_title.add_theme_color_override("font_color", Color.YELLOW)
	right_vbox.add_child(handle_size_title)

	var handle_size_hbox = HBoxContainer.new()
	right_vbox.add_child(handle_size_hbox)
	var handle_size_label = Label.new()
	handle_size_label.text = "手柄大小:"
	handle_size_label.custom_minimum_size = Vector2(90, 0)
	handle_size_hbox.add_child(handle_size_label)

	_handle_size_slider = HSlider.new()
	_handle_size_slider.min_value = 0
	_handle_size_slider.max_value = 999999
	_handle_size_slider.value = handle_size
	_handle_size_slider.step = 1.0
	_handle_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_handle_size_slider.custom_minimum_size = Vector2(60, 0)
	_handle_size_slider.value_changed.connect(_on_handle_size_changed)
	handle_size_hbox.add_child(_handle_size_slider)

	_handle_size_value_label = Label.new()
	_handle_size_value_label.text = "%d px" % int(handle_size)
	_handle_size_value_label.custom_minimum_size = Vector2(50, 0)
	handle_size_hbox.add_child(_handle_size_value_label)

	# 说明按钮
	right_vbox.add_child(HSeparator.new())
	var help_btn = Button.new()
	help_btn.text = "说明"
	help_btn.pressed.connect(_on_help_button)
	right_vbox.add_child(help_btn)

	_update_undo_redo_buttons()

func _add_spinbox_row(parent: Control, label_text: String, min_v: float, max_v: float, default_v: float, tooltip: String = "") -> SpinBox:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(60, 0)
	label.tooltip_text = tooltip
	hbox.add_child(label)

	var spinbox = SpinBox.new()
	spinbox.min_value = min_v
	spinbox.max_value = max_v
	spinbox.value = default_v
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinbox.tooltip_text = tooltip
	hbox.add_child(spinbox)

	return spinbox

func _connect_value_signals():
	_pos_x.value_changed.connect(_on_property_changed)
	_pos_y.value_changed.connect(_on_property_changed)
	_pos_z.value_changed.connect(_on_property_changed)
	_size_x.value_changed.connect(_on_property_changed)
	_size_y.value_changed.connect(_on_property_changed)
	_size_z.value_changed.connect(_on_property_changed)

func _disconnect_value_signals():
	_pos_x.value_changed.disconnect(_on_property_changed)
	_pos_y.value_changed.disconnect(_on_property_changed)
	_pos_z.value_changed.disconnect(_on_property_changed)
	_size_x.value_changed.disconnect(_on_property_changed)
	_size_y.value_changed.disconnect(_on_property_changed)
	_size_z.value_changed.disconnect(_on_property_changed)

# ==========================================
# 说明按钮
# ==========================================
func _on_help_button():
	var dialog = AcceptDialog.new()
	dialog.title = "攻击框编辑器说明"
	dialog.size = Vector2(500, 220)
	dialog.min_size = Vector2(400, 180)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 140)
	dialog.add_child(scroll)

	var label = Label.new()
	label.custom_minimum_size.x = 460
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "=== 攻击框编辑器使用说明 ===\n\n"
	label.text += "触地攻击: 攻击框碰到脚底下的线\n"
	label.text += "2D视图显示X(水平)和Z(垂直)，Y通过面板编辑\n\n"
	label.text += "操作方式:\n"
	label.text += "  - 左键拖拽框中心: 移动攻击框(调整XZ位置)\n"
	label.text += "  - 左键拖拽边框手柄: 缩放攻击框(8方向)\n"
	label.text += "  - 中键拖拽: 平移画布\n"
	label.text += "  - 滚轮: 缩放画布\n"
	label.text += "  - Ctrl+Z: 撤回  Ctrl+Y: 重做\n\n"
	label.text += "颜色说明:\n"
	label.text += "  - 红色: 有数据的攻击框\n"
	label.text += "  - 灰色: 无数据的攻击框\n"
	label.text += "  - 紫色: 动画不匹配\n"
	label.text += "  - 青色线: 锚点水平线(地面参考)\n\n"
	label.text += "工作流程:\n"
	label.text += "  1. 选择动画和帧\n"
	label.text += "  2. 添加或选择攻击框\n"
	label.text += "  3. 调整位置和大小\n"
	label.text += "  4. 点击'应用到当前帧'\n"
	label.text += "  5. 保存数据"
	scroll.add_child(label)

	add_child(dialog)
	dialog.popup_centered()

# ==========================================
# 撤回重做系统
# ==========================================
func _record_action(action_type: String, action_data: Dictionary):
	if not is_recording_action:
		return
	var action = EditorAction.new(action_type, action_data)
	undo_stack.append(action)
	while undo_stack.size() > max_undo_steps:
		undo_stack.pop_front()
	redo_stack.clear()
	_update_undo_redo_buttons()

func _update_undo_redo_buttons():
	_undo_button.disabled = undo_stack.is_empty()
	_redo_button.disabled = redo_stack.is_empty()
	if not undo_stack.is_empty():
		var last_action = undo_stack.back() as EditorAction
		_undo_button.text = "撤回 (%s)" % _get_action_name(last_action.type)
	else:
		_undo_button.text = "撤回 (Ctrl+Z)"
	if not redo_stack.is_empty():
		var next_action = redo_stack.back() as EditorAction
		_redo_button.text = "重做 (%s)" % _get_action_name(next_action.type)
	else:
		_redo_button.text = "重做 (Ctrl+Y)"

func _get_action_name(action_type: String) -> String:
	match action_type:
		"move_box": return "移动"
		"resize_box": return "缩放"
		"apply_frame": return "应用帧"
		"remove_frame": return "删除帧"
		"add_box": return "添加"
		"delete_box": return "删除"
		"paste_frame": return "粘贴"
		"property_change": return "属性"
		_: return "操作"

func _on_undo_pressed():
	if undo_stack.is_empty():
		return
	_flush_pending_property()
	var action = undo_stack.pop_back() as EditorAction
	redo_stack.append(action)
	is_recording_action = false
	_apply_action_inverse(action)
	is_recording_action = true
	_update_undo_redo_buttons()

func _on_redo_pressed():
	if redo_stack.is_empty():
		return
	var action = redo_stack.pop_back() as EditorAction
	undo_stack.append(action)
	is_recording_action = false
	_apply_action(action)
	is_recording_action = true
	_update_undo_redo_buttons()

func _apply_action(action: EditorAction):
	match action.type:
		"move_box":
			_restore_box_frame_position(action.data.box_id, action.data.frame, action.data.new_position)
		"resize_box":
			_restore_box_frame_full(action.data.box_id, action.data.frame, action.data.new_position, action.data.new_size)
		"apply_frame":
			if action.data.new_has_config:
				_restore_box_frame_full(action.data.box_id, action.data.frame, action.data.new_position, action.data.new_size)
			else:
				_restore_box_frame_remove(action.data.box_id, action.data.frame)
		"remove_frame":
			_restore_box_frame_full(action.data.box_id, action.data.frame, action.data.removed_position, action.data.removed_size)
		"add_box":
			_restore_add_box(action.data.box_id, action.data.box_dict)
		"delete_box":
			_restore_delete_box(action.data.box_id, action.data.box_dict)
		"paste_frame":
			if action.data.new_has_config:
				_restore_box_frame_full(action.data.box_id, action.data.frame, action.data.new_position, action.data.new_size)
			else:
				_restore_box_frame_remove(action.data.box_id, action.data.frame)
		"property_change":
			if action.data.new_has_config:
				_restore_box_frame_full(action.data.box_id, action.data.frame, action.data.new_position, action.data.new_size)
			else:
				_restore_box_frame_remove(action.data.box_id, action.data.frame)

	_refresh_ui_after_undo()

func _apply_action_inverse(action: EditorAction):
	match action.type:
		"move_box":
			_restore_box_frame_position(action.data.box_id, action.data.frame, action.data.prev_position)
		"resize_box":
			_restore_box_frame_full(action.data.box_id, action.data.frame, action.data.prev_position, action.data.prev_size)
		"apply_frame":
			if action.data.prev_has_config:
				_restore_box_frame_full(action.data.box_id, action.data.frame, action.data.prev_position, action.data.prev_size)
			else:
				_restore_box_frame_remove(action.data.box_id, action.data.frame)
		"remove_frame":
			_restore_box_frame_remove(action.data.box_id, action.data.frame)
		"add_box":
			_restore_delete_box(action.data.box_id, action.data.box_dict)
		"delete_box":
			_restore_add_box(action.data.box_id, action.data.box_dict)
		"paste_frame":
			if action.data.prev_has_config:
				_restore_box_frame_full(action.data.box_id, action.data.frame, action.data.prev_position, action.data.prev_size)
			else:
				_restore_box_frame_remove(action.data.box_id, action.data.frame)
		"property_change":
			if action.data.prev_has_config:
				_restore_box_frame_full(action.data.box_id, action.data.frame, action.data.prev_position, action.data.prev_size)
			else:
				_restore_box_frame_remove(action.data.box_id, action.data.frame)

	_refresh_ui_after_undo()

# ---- 状态恢复辅助函数 ----

func _restore_box_frame_position(box_id: String, frame: int, new_pos: Dictionary):
	if not _attack_boxes.has(box_id):
		return
	var box_data = _attack_boxes[box_id] as AttackBoxData
	var config = box_data.get_frame_config(frame)
	if not config:
		return
	config.position.x = new_pos.get("x", 0)
	config.position.y = new_pos.get("y", 0)
	config.position.z = new_pos.get("z", 0)

func _restore_box_frame_full(box_id: String, frame: int, new_pos: Dictionary, new_size: Dictionary):
	if not _attack_boxes.has(box_id):
		return
	var box_data = _attack_boxes[box_id] as AttackBoxData
	var config = box_data.get_frame_config(frame)
	if not config:
		config = AttackBoxData.FrameConfig.new()
		box_data.set_frame_config(frame, config)
	config.position.x = new_pos.get("x", 0)
	config.position.y = new_pos.get("y", 0)
	config.position.z = new_pos.get("z", 0)
	config.size.x = new_size.get("x", 50)
	config.size.y = new_size.get("y", 50)
	config.size.z = new_size.get("z", 50)

func _restore_box_frame_remove(box_id: String, frame: int):
	if not _attack_boxes.has(box_id):
		return
	var box_data = _attack_boxes[box_id] as AttackBoxData
	box_data.remove_frame_config(frame)

func _restore_add_box(box_id: String, box_dict: Dictionary):
	var box = AttackBoxData.new()
	box.from_dict(box_dict)
	_attack_boxes[box.box_id] = box
	var display_name = box.box_name + " [" + box.bind_animation + "]"
	_box_list.add_item(display_name)
	_box_list.set_item_metadata(_box_list.item_count - 1, box.box_id)
	# 恢复选中状态
	if _current_box_id == "":
		_current_box_id = box.box_id
		_box_list.select(_box_list.item_count - 1)

func _restore_delete_box(box_id: String, _box_dict: Dictionary):
	if not _attack_boxes.has(box_id):
		return
	_attack_boxes.erase(box_id)
	for i in range(_box_list.item_count):
		if _box_list.get_item_metadata(i) == box_id:
			_box_list.remove_item(i)
			break

func _refresh_ui_after_undo():
	"""撤回/重做后刷新整个UI"""
	# 恢复选中状态
	if _current_box_id != "" and _attack_boxes.has(_current_box_id):
		# 尝试切到该攻击框绑定的动画
		var box_data = _attack_boxes[_current_box_id] as AttackBoxData
		if box_data.bind_animation != "":
			for i in range(_anim_selector.item_count):
				if _anim_selector.get_item_text(i) == box_data.bind_animation:
					if _anim_selector.selected != i:
						_anim_selector.select(i)
						_on_anim_selected(i)
					break
	_refresh_box_visuals()
	_draw_node.queue_redraw()
	_has_unsaved_changes = true

func _flush_pending_property():
	"""提交待定的属性修改为一个撤回记录"""
	if _pending_property_action.is_empty():
		return
	var box_id = _pending_property_action.box_id
	var frame = _pending_property_action.frame
	var prev_snapshot = _pending_property_action.prev_snapshot

	if _attack_boxes.has(box_id):
		var box_data = _attack_boxes[box_id] as AttackBoxData
		var current_config = box_data.get_frame_config(frame)

		var prev_has = prev_snapshot.has_config
		var prev_pos = prev_snapshot.position if prev_has else {"x": 0, "y": 0, "z": 0}
		var prev_size = prev_snapshot.size if prev_has else {"x": 50, "y": 50, "z": 50}

		var new_has = current_config != null
		var new_pos = _config_to_pos_dict(current_config) if new_has else {"x": 0, "y": 0, "z": 0}
		var new_size = _config_to_size_dict(current_config) if new_has else {"x": 50, "y": 50, "z": 50}

		# 检查是否有实际变化
		var changed = (prev_has != new_has) or (prev_pos.hash() != new_pos.hash()) or (prev_size.hash() != new_size.hash())
		if changed:
			_record_action("property_change", {
				"box_id": box_id,
				"frame": frame,
				"prev_has_config": prev_has,
				"prev_position": prev_pos,
				"prev_size": prev_size,
				"new_has_config": new_has,
				"new_position": new_pos,
				"new_size": new_size
			})
	_pending_property_action.clear()

func _config_to_pos_dict(config) -> Dictionary:
	return {"x": config.position.x, "y": config.position.y, "z": config.position.z}

func _config_to_size_dict(config) -> Dictionary:
	return {"x": config.size.x, "y": config.size.y, "z": config.size.z}

func _snapshot_frame_config(box_data: AttackBoxData, frame: int) -> Dictionary:
	"""快照当前帧配置用于撤回"""
	var config = box_data.get_frame_config(frame)
	if config:
		return {
			"has_config": true,
			"position": _config_to_pos_dict(config),
			"size": _config_to_size_dict(config)
		}
	return {"has_config": false}

# ==========================================
# 复制粘贴
# ==========================================
func _on_copy_frame():
	if not _current_box_id:
		push_warning("请先选择一个攻击框")
		return

	var box_data = _attack_boxes[_current_box_id]
	var current_frame = int(_frame_selector.value)

	if not box_data.is_active_at_frame(current_frame):
		push_warning("当前帧没有攻击框配置，无法复制")
		return

	var config = box_data.get_frame_config(current_frame)
	if not config:
		return

	var copied_config = AttackBoxData.FrameConfig.new()
	copied_config.position = config.position
	copied_config.size = config.size
	copied_config.pivot_offset = config.pivot_offset

	_copy_buffer["_last_copied"] = copied_config  # 使用固定key，支持跨攻击框粘贴

func _on_paste_frame():
	if not _current_box_id:
		push_warning("请先选择一个攻击框")
		return

	if not _copy_buffer.has("_last_copied"):
		push_warning("没有可粘贴的数据，请先复制")
		return

	var box_data = _attack_boxes[_current_box_id]
	var current_frame = int(_frame_selector.value)
	var copied_config = _copy_buffer["_last_copied"]

	# 快照修改前状态
	var prev_snapshot = _snapshot_frame_config(box_data, current_frame)

	var new_config = AttackBoxData.FrameConfig.new()
	new_config.position = copied_config.position
	new_config.size = copied_config.size
	new_config.pivot_offset = copied_config.pivot_offset

	box_data.set_frame_config(current_frame, new_config)
	_has_unsaved_changes = true
	_refresh_box_visuals()

	# 记录撤回
	_record_action("paste_frame", {
		"box_id": _current_box_id,
		"frame": current_frame,
		"prev_has_config": prev_snapshot.has_config,
		"prev_position": prev_snapshot.get("position", {"x": 0, "y": 0, "z": 0}),
		"prev_size": prev_snapshot.get("size", {"x": 50, "y": 50, "z": 50}),
		"new_has_config": true,
		"new_position": _config_to_pos_dict(new_config),
		"new_size": _config_to_size_dict(new_config)
	})

# ==========================================
# 数据加载与保存
# ==========================================
func _load_existing_data():
	if _entity_scene_path == "":
		push_error("实体场景路径为空")
		return

	var base_dir = _entity_scene_path.get_base_dir()
	var data_path = base_dir + "/attack_boxes.json"

	if not FileAccess.file_exists(data_path):
		return

	var file = FileAccess.open(data_path, FileAccess.READ)
	if file == null:
		push_error("无法打开文件: " + data_path)
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)

	if error != OK:
		push_error("JSON 解析错误: " + json.get_error_message())
		return

	var data = json.data
	if not data is Dictionary or not data.has("attack_boxes"):
		return

	var boxes_array = data["attack_boxes"]
	_attack_boxes.clear()
	_box_list.clear()

	# 加载控件大小配置
	if data.has("handle_size"):
		handle_size = data["handle_size"]
		_handle_size_slider.set_value_no_signal(handle_size)
		_handle_size_value_label.text = "%d px" % int(handle_size)

	for box_dict in boxes_array:
		if not box_dict is Dictionary:
			continue

		var box = AttackBoxData.new()
		box.from_dict(box_dict)
		_attack_boxes[box.box_id] = box

		var display_name = box.box_name if box.box_name != "" else box.box_id
		_box_list.add_item(display_name)
		_box_list.set_item_metadata(_box_list.item_count - 1, box.box_id)

func _on_save_data():
	_flush_pending_property()
	if _attack_boxes.is_empty():
		push_warning("没有攻击框可保存")
		return

	var data = {"attack_boxes": [], "handle_size": handle_size}

	for box in _attack_boxes.values():
		data["attack_boxes"].append(box.to_dict())

	var data_path = _entity_scene_path.get_base_dir() + "/attack_boxes.json"

	var file = FileAccess.open(data_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入文件: " + data_path)
		return

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	_has_unsaved_changes = false

# ==========================================
# 动画抽象接口（兼容 AnimatedSprite2D 和 AnimationPlayer）
# ==========================================
func _get_anim_names() -> PackedStringArray:
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap:
			var names = ap.get_animation_list()
			print("[attack_box] _get_anim_names: AnimationPlayer, anims=%s" % [str(names)])
			return names
	if _animated_sprite and _animated_sprite.sprite_frames:
		var names = _animated_sprite.sprite_frames.get_animation_names()
		print("[attack_box] _get_anim_names: AnimatedSprite2D, anims=%s" % [str(names)])
		return names
	print("[attack_box] _get_anim_names: empty")
	return PackedStringArray()

func _get_anim_frame_count(anim_name: String) -> int:
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap and ap.has_animation(anim_name):
			var anim = ap.get_animation(anim_name)
			var count = int(anim.length * ANIM_FPS)
			print("[attack_box] _get_anim_frame_count(%s) = %d" % [anim_name, count])
			return count
	if _animated_sprite and _animated_sprite.sprite_frames:
		var count = _animated_sprite.sprite_frames.get_frame_count(anim_name)
		print("[attack_box] _get_anim_frame_count(%s) = %d (sprite)" % [anim_name, count])
		return count
	print("[attack_box] _get_anim_frame_count(%s) = 0 (fallback)" % anim_name)
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
				print("[attack_box] _set_preview_frame(%s, %d): seek OK" % [anim_name, frame_idx])
			else:
				print("[attack_box] _set_preview_frame(%s, %d): anim not found" % [anim_name, frame_idx])
			return
		print("[attack_box] _set_preview_frame(%s, %d): no AnimationPlayer, fallback sprite" % [anim_name, frame_idx])
	if _preview_sprite:
		_preview_sprite.animation = anim_name
		_preview_sprite.frame = frame_idx

func _play_preview_anim():
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap and _anim_selector.selected >= 0:
			var anim_name = _anim_selector.get_item_text(_anim_selector.selected)
			if ap.has_animation(anim_name):
				ap.play(anim_name)
			return
	if _preview_sprite:
		_preview_sprite.play()

func _stop_preview_anim():
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap:
			ap.stop()
		return
	if _preview_sprite:
		_preview_sprite.stop()

func _get_preview_frame() -> int:
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap and ap.is_playing():
			return int(ap.current_animation_position / ANIM_FPS)
		return int(_frame_selector.value)
	if _preview_sprite:
		return _preview_sprite.frame
	return 0

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null

func _refresh_animation_list():
	_anim_selector.clear()
	var anims = _get_anim_names()
	for anim in anims:
		_anim_selector.add_item(anim)

# ==========================================
# 锚点数据加载
# ==========================================
func _load_anchor_data():
	_anchor_data.clear()
	if _entity_scene_path == "":
		print("[attack_box] _load_anchor_data: empty scene path")
		return

	var base_dir = _entity_scene_path.get_base_dir()
	var data_path = base_dir + "/entity_frame_data.json"

	if not FileAccess.file_exists(data_path):
		print("[attack_box] _load_anchor_data: file not found at %s" % data_path)
		return

	var file = FileAccess.open(data_path, FileAccess.READ)
	if file == null:
		push_error("[attack_box] _load_anchor_data: cannot open file")
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		push_error("[attack_box] _load_anchor_data: JSON parse error: " + json.get_error_message())
		return

	var data = json.data
	if not data is Dictionary or not data.has("animation_data"):
		push_warning("[attack_box] _load_anchor_data: no animation_data in JSON")
		return

	var anim_data = data["animation_data"]
	for anim_name in anim_data:
		var frames = anim_data[anim_name]
		_anchor_data[anim_name] = {}
		for frame_key in frames:
			var frame_dict = frames[frame_key]
			if frame_dict.has("anchor_point"):
				var ap = frame_dict["anchor_point"]
				_anchor_data[anim_name][int(frame_key)] = Vector2(ap.get("x", 0), ap.get("y", 0))
			else:
				_anchor_data[anim_name][int(frame_key)] = Vector2.ZERO
	print("[attack_box] _load_anchor_data: loaded %d animations" % _anchor_data.size())

# 获取原始锚点数据（未缩放）
func _get_raw_anchor() -> Vector2:
	if _anim_selector.selected < 0:
		return Vector2.ZERO
	var anim_name = _anim_selector.get_item_text(_anim_selector.selected)
	var frame_idx = int(_frame_selector.value)
	if _anchor_data.has(anim_name) and _anchor_data[anim_name].has(frame_idx):
		return _anchor_data[anim_name][frame_idx]
	return Vector2.ZERO

# 获取缩放后的锚点（乘以sprite scale）
func _get_scaled_anchor() -> Vector2:
	var raw = _get_raw_anchor()
	return raw * _sprite_scale

# ==========================================
# 预览与画布变换
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
		# AnimationPlayerEntity: 不需要 _preview_sprite，通过 AnimationPlayer 控制
		_preview_sprite = null
		_preview_visuals = _find_visuals_node(preview)
	else:
		_preview_sprite = _find_animated_sprite(preview)
		_preview_visuals = _find_visuals_node(preview)
		if _preview_sprite:
			_preview_sprite.frame_changed.connect(_on_preview_frame_changed)
			_preview_sprite.stop()

	# 确保 InteractionLayer 在最上层
	if _interaction_layer:
		_canvas.move_child(_interaction_layer, _canvas.get_child_count() - 1)

	call_deferred("_center_preview")

func _find_visuals_node(node: Node) -> Node2D:
	if node is Node2D and node.name == "Visuals":
		return node
	if node.has_node("Visuals"):
		return node.get_node("Visuals")
	for child in node.get_children():
		var found = _find_visuals_node(child)
		if found:
			return found
	return null

func _center_preview():
	if _is_anim_player_entity:
		if not _canvas.get_node_or_null("EntityPreview"):
			return
	elif not _preview_sprite:
		return
	await get_tree().process_frame
	_apply_canvas_transform()

func _apply_canvas_transform():
	var preview_root = _canvas.get_node("EntityPreview")
	if not preview_root: return

	# 实体预览：缩放并移动
	preview_root.position = preview_root_position * _canvas_zoom
	preview_root.scale = Vector2(_canvas_zoom, _canvas_zoom)

	# 应用锚点补偿（和运行时一致：visuals_node.position = -anchor * sprite_scale）
	_apply_anchor_compensation()

	# 绘制节点：只移动，不缩放（保证绘制大小不随缩放变化）
	_draw_node.position = preview_root_position * _canvas_zoom
	_draw_node.scale = Vector2(1, 1)

	_draw_node.queue_redraw()

# 应用锚点补偿到实体预览，使实体根节点对齐锚点位置（和运行时行为一致）
func _apply_anchor_compensation():
	if not _preview_visuals:
		return

	var anchor = _get_raw_anchor()
	# 运行时公式: visuals_node.position = -anchor * animated_sprite.scale
	_preview_visuals.position = Vector2(
		-anchor.x * _sprite_scale.x,
		-anchor.y * _sprite_scale.y
	)

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

# ==========================================
# 动画与帧控制
# ==========================================
func _on_anim_selected(index: int):
	_flush_pending_property()
	
	var anim_name = _anim_selector.get_item_text(index)
	var frame_count = _get_anim_frame_count(anim_name)
	print("[attack_box] _on_anim_selected: anim=%s, total_frames=%d" % [anim_name, frame_count])
	
	if _is_anim_player_entity:
		_set_preview_frame(anim_name, 0)
	else:
		if not _preview_sprite:
			return
		_preview_sprite.play(anim_name)
		_preview_sprite.stop()
		_preview_sprite.frame = 0

	_frame_selector.max_value = max(0, frame_count - 1)
	_frame_selector.value = 0

	# 切换动画时必须重新应用锚点补偿和画布变换
	_apply_canvas_transform()
	_refresh_box_visuals()

func _on_frame_changed(value: float):
	print("[attack_box] _on_frame_changed: frame=%d" % int(value))
	_flush_pending_property()
	if _is_anim_player_entity:
		var anim_name = _anim_selector.get_item_text(_anim_selector.selected) if _anim_selector.selected >= 0 else ""
		_set_preview_frame(anim_name, int(value))
	else:
		if _preview_sprite:
			_preview_sprite.frame = int(value)
	# 帧变化时重新应用锚点补偿
	_apply_canvas_transform()
	_refresh_box_visuals()

var _is_playing_anim: bool = false

func _process(_delta: float):
	if not _is_playing_anim:
		return
	if _is_anim_player_entity:
		var sprite_frame = _get_preview_frame()
		if sprite_frame != int(_frame_selector.value):
			_frame_selector.set_value_no_signal(sprite_frame)
			_apply_canvas_transform()
			_refresh_box_visuals()

func _on_prev_frame():
	var new_frame = int(_frame_selector.value) - 1
	if new_frame >= 0:
		_frame_selector.value = new_frame

func _on_next_frame():
	var new_frame = int(_frame_selector.value) + 1
	if new_frame <= _frame_selector.max_value:
		_frame_selector.value = new_frame

func _on_play_animation():
	_is_playing_anim = true
	_play_preview_anim()

func _on_stop_animation():
	_is_playing_anim = false
	_stop_preview_anim()

func _on_preview_frame_changed():
	if _is_anim_player_entity:
		_frame_selector.value = _get_preview_frame()
	elif _preview_sprite:
		_frame_selector.value = _preview_sprite.frame

# ==========================================
# 攻击框管理
# ==========================================
func _on_add_box():
	var dialog = AcceptDialog.new()
	dialog.title = "新建攻击框"

	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)

	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "攻击框名称"
	vbox.add_child(line_edit)

	var anim_hint = Label.new()
	var current_anim = "无"
	if _anim_selector.selected >= 0:
		current_anim = _anim_selector.get_item_text(_anim_selector.selected)
	anim_hint.text = "将绑定到动画: " + current_anim
	anim_hint.modulate = Color.YELLOW
	vbox.add_child(anim_hint)

	add_child(dialog)
	dialog.popup_centered()

	await dialog.confirmed

	var box_name = line_edit.text.strip_edges()
	if box_name == "":
		box_name = "AttackBox_" + str(randi() % 10000)

	var box = AttackBoxData.new()
	box.box_id = "box_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000)
	box.box_name = box_name

	if _anim_selector.selected >= 0:
		box.bind_animation = _anim_selector.get_item_text(_anim_selector.selected)
	else:
		push_error("没有可用的动画")
		dialog.queue_free()
		return

	_attack_boxes[box.box_id] = box

	var display_name = box.box_name + " [" + box.bind_animation + "]"
	_box_list.add_item(display_name)
	_box_list.set_item_metadata(_box_list.item_count - 1, box.box_id)

	_box_list.select(_box_list.item_count - 1)
	_on_box_selected(_box_list.item_count - 1)

	_has_unsaved_changes = true
	_record_action("add_box", {
		"box_id": box.box_id,
		"box_dict": box.to_dict()
	})
	dialog.queue_free()

func _on_delete_box():
	var selected = _box_list.get_selected_items()
	if selected.is_empty():
		return

	var idx = selected[0]
	var box_id = _box_list.get_item_metadata(idx)

	if not _attack_boxes.has(box_id):
		return

	var box_data = _attack_boxes[box_id]

	var confirm = ConfirmationDialog.new()
	confirm.title = "确认删除"
	confirm.dialog_text = "确定要删除攻击框 \"" + box_data.box_name + "\" 吗？\n此操作不可恢复！"
	confirm.get_ok_button().add_theme_color_override("font_color", Color.RED)

	add_child(confirm)
	confirm.popup_centered()

	await confirm.confirmed

	# 快照被删除的攻击框数据
	var deleted_snapshot = box_data.to_dict()

	_attack_boxes.erase(box_id)
	_box_list.remove_item(idx)

	if _current_box_id == box_id:
		_current_box_id = ""
		_refresh_box_visuals()

	_has_unsaved_changes = true

	# 记录撤回
	_record_action("delete_box", {
		"box_id": box_id,
		"box_dict": deleted_snapshot,
		"list_index": idx
	})
	confirm.queue_free()

func _on_remove_frame_config():
	if not _current_box_id:
		push_warning("请先选择一个攻击框")
		return

	if not _attack_boxes.has(_current_box_id):
		return

	_flush_pending_property()

	var box_data = _attack_boxes[_current_box_id]
	var current_frame = int(_frame_selector.value)

	if not box_data.is_active_at_frame(current_frame):
		push_warning("当前帧没有攻击框配置")
		return

	# 快照将被删除的配置
	var removed_config = box_data.get_frame_config(current_frame)
	var removed_pos = _config_to_pos_dict(removed_config)
	var removed_size = _config_to_size_dict(removed_config)

	box_data.remove_frame_config(current_frame)
	_has_unsaved_changes = true
	_refresh_box_visuals()
	_reset_property_panel()

	# 记录撤回
	_record_action("remove_frame", {
		"box_id": _current_box_id,
		"frame": current_frame,
		"removed_position": removed_pos,
		"removed_size": removed_size
	})

func _on_box_selected(index: int):
	_flush_pending_property()
	if index < 0 or index >= _box_list.item_count:
		return

	_current_box_id = _box_list.get_item_metadata(index)

	if not _attack_boxes.has(_current_box_id):
		return

	var box_data = _attack_boxes[_current_box_id]

	if box_data.bind_animation != "":
		var target_anim = box_data.bind_animation
		var found_index = -1

		for i in range(_anim_selector.item_count):
			if _anim_selector.get_item_text(i) == target_anim:
				found_index = i
				break

		if found_index >= 0:
			if _anim_selector.selected != found_index:
				_anim_selector.select(found_index)
				_on_anim_selected(found_index)

	_refresh_box_visuals()

func _on_apply_to_frame():
	if not _current_box_id:
		push_warning("请先选择一个攻击框")
		return

	if not _attack_boxes.has(_current_box_id):
		return

	_flush_pending_property()

	var box_data = _attack_boxes[_current_box_id]
	var frame = int(_frame_selector.value)

	# 快照修改前状态
	var prev_snapshot = _snapshot_frame_config(box_data, frame)

	var config = AttackBoxData.FrameConfig.new()
	config.position.x = _pos_x.value
	config.position.y = _pos_y.value
	config.position.z = _pos_z.value
	config.size.x = _size_x.value
	config.size.y = _size_y.value
	config.size.z = _size_z.value

	box_data.set_frame_config(frame, config)
	_has_unsaved_changes = true
	_refresh_box_visuals()

	# 记录撤回
	_record_action("apply_frame", {
		"box_id": _current_box_id,
		"frame": frame,
		"prev_has_config": prev_snapshot.has_config,
		"prev_position": prev_snapshot.get("position", {"x": 0, "y": 0, "z": 0}),
		"prev_size": prev_snapshot.get("size", {"x": 50, "y": 50, "z": 50}),
		"new_has_config": true,
		"new_position": _config_to_pos_dict(config),
		"new_size": _config_to_size_dict(config)
	})

# ==========================================
# 计算攻击框在画布上的显示位置
# 运行时公式: box.position = (config.x * facing - anchor.x * scale.x, config.z - anchor.y * scale.y - position_3d.y)
# 编辑器中 facing=1, position_3d.y=0
# ==========================================
func _get_box_display_pos(config) -> Vector2:
	var anchor = _get_scaled_anchor()
	return Vector2(
		config.position.x - anchor.x,
		config.position.z - anchor.y
	)

# ==========================================
# 可视化（绘制方式，参考信息点编辑器）
# ==========================================
func _refresh_box_visuals():
	_draw_node.queue_redraw()

	if not _current_box_id or not _attack_boxes.has(_current_box_id):
		return

	var box_data = _attack_boxes[_current_box_id]
	var current_frame = int(_frame_selector.value)

	if box_data.is_active_at_frame(current_frame):
		var config = box_data.get_frame_config(current_frame)
		_update_property_panel(config)
	else:
		_reset_property_panel()

func _on_canvas_draw():
	if _is_anim_player_entity:
		if not _canvas.get_node_or_null("EntityPreview"):
			return
	elif not _preview_sprite:
		return

	# 绘制坐标轴参考线（实体根=锚点位置）
	var axis_len = 50 * _canvas_zoom
	_draw_node.draw_line(Vector2(0, 0), Vector2(axis_len, 0), Color.RED, 1.0)
	_draw_node.draw_line(Vector2(0, 0), Vector2(0, axis_len), Color.GREEN, 1.0)

	# 绘制锚点水平线（实体根位置=角色脚底，从左到右贯穿整个画布）
	var line_start_x = -preview_root_position.x * _canvas_zoom
	var line_end_x = _canvas.size.x - preview_root_position.x * _canvas_zoom
	_draw_node.draw_line(
		Vector2(line_start_x, 0),
		Vector2(line_end_x, 0),
		Color(0, 0.8, 0.8, 0.6),
		2.0
	)

	# 只绘制当前选中的攻击框
	if _current_box_id == "" or not _attack_boxes.has(_current_box_id):
		return

	var current_anim = _anim_selector.get_item_text(_anim_selector.selected) if _anim_selector.selected >= 0 else ""
	var current_frame = int(_frame_selector.value)

	var box_data = _attack_boxes[_current_box_id]
	var anim_mismatch = box_data.bind_animation != "" and box_data.bind_animation != current_anim
	var has_config = box_data.is_active_at_frame(current_frame)

	if has_config:
		var config = box_data.get_frame_config(current_frame)
		_draw_attack_box(box_data, config, anim_mismatch, current_frame)
		# 绘制8方向缩放手柄（仅对当前选中有数据的攻击框）
		_draw_resize_handles(config)
	else:
		_draw_empty_box(box_data, anim_mismatch)

func _draw_attack_box(box_data: AttackBoxData, config: AttackBoxData.FrameConfig, anim_mismatch: bool, current_frame: int):
	# 使用运行时公式计算显示位置
	var display_pos = _get_box_display_pos(config) * _canvas_zoom
	var display_size = Vector2(config.size.x, config.size.z) * _canvas_zoom

	# 矩形左上角
	var rect_pos = display_pos - display_size / 2

	var color: Color
	var border_color: Color

	if anim_mismatch:
		color = Color(0.8, 0.4, 0.8, 0.3)
		border_color = Color.PURPLE
	else:
		color = Color(1, 0.2, 0.2, 0.3)
		border_color = Color.RED

	# 绘制填充矩形
	_draw_node.draw_rect(Rect2(rect_pos, display_size), color)
	# 绘制边框
	_draw_node.draw_rect(Rect2(rect_pos, display_size), border_color, false, 2.0)

	# 绘制标签
	var label_text = "%s [%d]\nXYZ:(%.0f,%.0f,%.0f)" % [
		box_data.box_name, current_frame,
		config.position.x, config.position.y, config.position.z
	]
	var label_pos = rect_pos + Vector2(0, -30)
	_draw_node.draw_string(ThemeDB.fallback_font, label_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, border_color)

	# 深度指示器
	if config.size.y > 0:
		var y_text = "Y深度: %.0f (±%.0f)" % [config.position.y, config.size.y / 2]
		var y_pos = rect_pos + Vector2(0, display_size.y + 15)
		_draw_node.draw_string(ThemeDB.fallback_font, y_pos, y_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.CYAN)

func _draw_empty_box(box_data: AttackBoxData, anim_mismatch: bool):
	var display_size = Vector2(50, 50) * _canvas_zoom
	var rect_pos = -display_size / 2

	var color = Color(0.5, 0.5, 0.5, 0.2)
	var border_color = Color.GRAY
	if anim_mismatch:
		color = Color(0.8, 0.4, 0.8, 0.2)
		border_color = Color.PURPLE

	_draw_node.draw_rect(Rect2(rect_pos, display_size), color)
	_draw_node.draw_rect(Rect2(rect_pos, display_size), border_color, false, 2.0)

	var label_text = box_data.box_name + " [无数据]"
	var label_pos = rect_pos + Vector2(0, -15)
	_draw_node.draw_string(ThemeDB.fallback_font, label_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, border_color)

# ==========================================
# 缩放手柄绘制
# ==========================================
func _draw_resize_handles(config: AttackBoxData.FrameConfig):
	"""绘制8方向缩放手柄（N S E W NE NW SE SW）"""
	var display_pos = _get_box_display_pos(config) * _canvas_zoom
	var display_size = Vector2(config.size.x, config.size.z) * _canvas_zoom
	var half_w = display_size.x / 2.0
	var half_h = display_size.y / 2.0

	if half_w < 2.0 or half_h < 2.0:
		return

	# 八个方向相对于中心的偏移（屏幕坐标）
	var dirs = {
		"N": Vector2(0, -half_h),
		"S": Vector2(0, half_h),
		"E": Vector2(half_w, 0),
		"W": Vector2(-half_w, 0),
		"NE": Vector2(half_w, -half_h),
		"NW": Vector2(-half_w, -half_h),
		"SE": Vector2(half_w, half_h),
		"SW": Vector2(-half_w, half_h)
	}

	for dir_name in dirs:
		var offset = dirs[dir_name]
		var handle_screen_pos = display_pos + offset

		# 边缘手柄用蓝色，角手柄用青色
		var resize_color: Color
		if dir_name.length() == 1:
			resize_color = Color(0.2, 0.5, 0.9, 0.9)
		else:
			resize_color = Color(0.2, 0.8, 0.8, 0.9)

		var h_size = handle_size * 0.7
		_draw_node.draw_rect(
			Rect2(handle_screen_pos - Vector2(h_size, h_size),
				  Vector2(h_size * 2, h_size * 2)),
			Color(0, 0, 0, 0.5)
		)
		_draw_node.draw_rect(
			Rect2(handle_screen_pos - Vector2(h_size - 2, h_size - 2),
				  Vector2((h_size - 2) * 2, (h_size - 2) * 2)),
			resize_color
		)

func _on_handle_size_changed(value: float):
	handle_size = value
	_handle_size_value_label.text = "%d px" % int(value)
	_draw_node.queue_redraw()

# ==========================================
# 8方向手柄位置计算 & 点击检测
# ==========================================
func _get_resize_handle_positions(config: AttackBoxData.FrameConfig) -> Dictionary:
	"""返回8个手柄的逻辑坐标字典 {方向名: Vector2}"""
	var display_pos = _get_box_display_pos(config)
	var half_w = config.size.x / 2.0
	var half_h = config.size.z / 2.0

	var dirs = {
		"N": Vector2(0, -half_h),
		"S": Vector2(0, half_h),
		"E": Vector2(half_w, 0),
		"W": Vector2(-half_w, 0),
		"NE": Vector2(half_w, -half_h),
		"NW": Vector2(-half_w, -half_h),
		"SE": Vector2(half_w, half_h),
		"SW": Vector2(-half_w, half_h)
	}

	var result = {}
	for dir_name in dirs:
		result[dir_name] = display_pos + dirs[dir_name]
	return result

func _get_clicked_resize_handle(logical_mouse: Vector2, config: AttackBoxData.FrameConfig) -> String:
	"""检测逻辑坐标点是否点击了某个缩放手柄，返回手柄名称或空字符串"""
	var threshold = handle_size * 0.7 / _canvas_zoom
	var handles = _get_resize_handle_positions(config)
	for dir_name in handles:
		var handle_pos = handles[dir_name]
		if logical_mouse.distance_to(handle_pos) < threshold:
			return dir_name
	return ""

func _get_handle_cursor(handle_name: String) -> int:
	"""根据手柄方向返回对应的鼠标光标"""
	match handle_name:
		"N", "S":
			return DisplayServer.CURSOR_VSIZE
		"E", "W":
			return DisplayServer.CURSOR_HSIZE
		"NE", "SW":
			return DisplayServer.CURSOR_FDIAGSIZE
		"NW", "SE":
			return DisplayServer.CURSOR_BDIAGSIZE
		_:
			return DisplayServer.CURSOR_ARROW

# ==========================================
# 缩放拖拽逻辑
# ==========================================
func _handle_resize_drag(mouse_pos: Vector2):
	"""处理缩放手柄拖拽，修改 config.size 和 config.position"""
	if not _is_resizing or _resize_handle == "":
		return
	if not _current_box_id or not _attack_boxes.has(_current_box_id):
		return

	var box_data = _attack_boxes[_current_box_id]
	var current_frame = int(_frame_selector.value)
	var config = box_data.get_frame_config(current_frame)
	if not config:
		return

	# 屏幕坐标 -> 逻辑坐标
	var logical_mouse = (mouse_pos / _canvas_zoom) - preview_root_position

	# 计算当前框的显示位置和半尺寸（逻辑坐标）
	var display_pos = _get_box_display_pos(config)
	var half_w = config.size.x / 2.0
	var half_h = config.size.z / 2.0

	# 四个边的固定位置（在拖拽开始时确定）
	var left_edge = display_pos.x - half_w
	var right_edge = display_pos.x + half_w
	var top_edge = display_pos.y - half_h
	var bottom_edge = display_pos.y + half_h

	# 根据手柄方向确定哪些边跟着鼠标移动
	var update_left = false
	var update_right = false
	var update_top = false
	var update_bottom = false

	match _resize_handle:
		"E": update_right = true
		"W": update_left = true
		"N": update_top = true
		"S": update_bottom = true
		"NE": update_right = true; update_top = true
		"NW": update_left = true; update_top = true
		"SE": update_right = true; update_bottom = true
		"SW": update_left = true; update_bottom = true

	# 用拖拽开始时的边位置作为固定边
	if update_left:
		left_edge = logical_mouse.x
	if update_right:
		right_edge = logical_mouse.x
	if update_top:
		top_edge = logical_mouse.y
	if update_bottom:
		bottom_edge = logical_mouse.y

	# 确保最小尺寸
	if right_edge - left_edge < 2.0:
		if update_right:
			right_edge = left_edge + 2.0
		else:
			left_edge = right_edge - 2.0
	if bottom_edge - top_edge < 2.0:
		if update_bottom:
			bottom_edge = top_edge + 2.0
		else:
			top_edge = bottom_edge - 2.0

	# 计算新的中心和尺寸
	var new_center = Vector2((left_edge + right_edge) / 2.0, (top_edge + bottom_edge) / 2.0)
	var new_size_x = right_edge - left_edge
	var new_size_z = bottom_edge - top_edge

	# 反算config.position
	var anchor = _get_scaled_anchor()
	config.position.x = new_center.x + anchor.x
	config.position.z = new_center.y + anchor.y
	config.size.x = new_size_x
	config.size.z = new_size_z

	# 更新面板
	_disconnect_value_signals()
	_pos_x.value = config.position.x
	_pos_z.value = config.position.z
	_size_x.value = config.size.x
	_size_z.value = config.size.z
	_connect_value_signals()

	_draw_node.queue_redraw()
	_has_unsaved_changes = true
	# 更新拖拽后的状态到 drag_prev_state
	if drag_prev_state != null and drag_prev_state.type == "resize_box":
		drag_prev_state.data["new_position"] = _config_to_pos_dict(config)
		drag_prev_state.data["new_size"] = _config_to_size_dict(config)

# ==========================================
# 交互逻辑（参考信息点编辑器，屏幕坐标 <-> 逻辑坐标转换）
# ==========================================
func _on_interaction_input(event: InputEvent):
	if not _canvas or not _canvas.get_node_or_null("EntityPreview"):
		return

	# --- 鼠标按键处理 ---
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

		# 左键处理
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _is_panning: return

				# 屏幕坐标 -> 逻辑坐标
				var logical_mouse = (mb.position / _canvas_zoom) - preview_root_position

				var current_frame = int(_frame_selector.value)

				# 只检测当前选中的攻击框
				if _current_box_id != "" and _attack_boxes.has(_current_box_id):
					var box_data = _attack_boxes[_current_box_id]
					if box_data.is_active_at_frame(current_frame):
						var config = box_data.get_frame_config(current_frame)
						if config:
							# === 优先级1：检测缩放手柄点击 ===
							var resize_handle = _get_clicked_resize_handle(logical_mouse, config)
							if resize_handle != "":
								_is_resizing = true
								_resize_handle = resize_handle
								_resize_start_mouse = mb.position
								# 记录拖拽前状态
								drag_prev_state = EditorAction.new("resize_box", {
									"box_id": _current_box_id,
									"frame": current_frame,
									"prev_position": _config_to_pos_dict(config),
									"prev_size": _config_to_size_dict(config),
									"new_position": _config_to_pos_dict(config),
									"new_size": _config_to_size_dict(config)
								})
								_draw_node.queue_redraw()
								return

							# === 优先级2：检测攻击框拖拽 ===
							var box_center = _get_box_display_pos(config)
							var box_half_size = Vector2(config.size.x, config.size.z) / 2
							var click_threshold = 10.0 / _canvas_zoom

							if logical_mouse.x >= box_center.x - box_half_size.x - click_threshold and \
							   logical_mouse.x <= box_center.x + box_half_size.x + click_threshold and \
							   logical_mouse.y >= box_center.y - box_half_size.y - click_threshold and \
							   logical_mouse.y <= box_center.y + box_half_size.y + click_threshold:
								_is_dragging = true
								_drag_box_id = _current_box_id
								_drag_offset = box_center - logical_mouse
								# 记录拖拽前状态
								drag_prev_state = EditorAction.new("move_box", {
									"box_id": _current_box_id,
									"frame": current_frame,
									"prev_position": _config_to_pos_dict(config),
									"new_position": _config_to_pos_dict(config)
								})
			else:
				# 左键释放
				if _is_dragging:
					_is_dragging = false
					_drag_box_id = ""
					_has_unsaved_changes = true
					_end_drag()
				if _is_resizing:
					_is_resizing = false
					_resize_handle = ""
					_has_unsaved_changes = true
					_end_drag()
					_draw_node.queue_redraw()

	# --- 鼠标移动处理 ---
	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion

		if _is_panning:
			var drag_delta = (mm.position - _pan_start_mouse_pos) / _canvas_zoom
			preview_root_position = _pan_start_offset + drag_delta
			_apply_canvas_transform()
			return

		elif _is_resizing and _resize_handle != "":
			_handle_resize_drag(mm.position)
			return

		elif _is_dragging and _drag_box_id != "":
			if not _attack_boxes.has(_drag_box_id):
				return

			var box_data = _attack_boxes[_drag_box_id]
			var current_frame = int(_frame_selector.value)
			var config = box_data.get_frame_config(current_frame)
			if not config:
				return

			var anchor = _get_scaled_anchor()

			# 屏幕坐标 -> 逻辑坐标
			var logical_mouse = (mm.position / _canvas_zoom) - preview_root_position
			var new_display_pos = logical_mouse + _drag_offset

			# 反算config.position: display_pos = config.x - anchor.x, config.z - anchor.y
			# 所以 config.x = display_pos.x + anchor.x, config.z = display_pos.y + anchor.y
			config.position.x = new_display_pos.x + anchor.x
			config.position.z = new_display_pos.y + anchor.y

			# 更新面板
			_disconnect_value_signals()
			_pos_x.value = config.position.x
			_pos_z.value = config.position.z
			_connect_value_signals()

			_draw_node.queue_redraw()
			_has_unsaved_changes = true
			# 更新拖拽后的状态到 drag_prev_state
			if drag_prev_state != null and drag_prev_state.type == "move_box":
				drag_prev_state.data["new_position"] = _config_to_pos_dict(config)
		else:
			# 悬停检测：更改光标
			_handle_hover_cursor(mm)

func _handle_hover_cursor(mm: InputEventMouseMotion):
	"""悬停时更改鼠标光标样式"""
	var logical_mouse = (mm.position / _canvas_zoom) - preview_root_position

	# 检测缩放手柄悬停
	if _current_box_id != "" and _attack_boxes.has(_current_box_id):
		var box_data = _attack_boxes[_current_box_id]
		var current_frame = int(_frame_selector.value)
		if box_data.is_active_at_frame(current_frame):
			var config = box_data.get_frame_config(current_frame)
			if config:
				var resize_handle = _get_clicked_resize_handle(logical_mouse, config)
				if resize_handle != "":
					DisplayServer.cursor_set_shape(_get_handle_cursor(resize_handle))
					return

	# 检测攻击框悬停（显示拖拽光标）
	if _current_box_id != "" and _attack_boxes.has(_current_box_id):
		var box_data = _attack_boxes[_current_box_id]
		var current_frame = int(_frame_selector.value)
		if box_data.is_active_at_frame(current_frame):
			var config = box_data.get_frame_config(current_frame)
			if config:
				var box_center = _get_box_display_pos(config)
				var box_half_size = Vector2(config.size.x, config.size.z) / 2
				var click_threshold = 10.0 / _canvas_zoom

				if logical_mouse.x >= box_center.x - box_half_size.x - click_threshold and \
				   logical_mouse.x <= box_center.x + box_half_size.x + click_threshold and \
				   logical_mouse.y >= box_center.y - box_half_size.y - click_threshold and \
				   logical_mouse.y <= box_center.y + box_half_size.y + click_threshold:
					DisplayServer.cursor_set_shape(DisplayServer.CURSOR_MOVE)
					return

	DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)

# ==========================================
# 拖拽结束记录
# ==========================================
func _end_drag():
	"""拖拽结束时记录撤回动作"""
	if drag_prev_state == null:
		return

	match drag_prev_state.type:
		"move_box":
			if drag_prev_state.data.prev_position.hash() != drag_prev_state.data.new_position.hash():
				_record_action("move_box", {
					"box_id": drag_prev_state.data.box_id,
					"frame": drag_prev_state.data.frame,
					"prev_position": drag_prev_state.data.prev_position,
					"new_position": drag_prev_state.data.new_position
				})
		"resize_box":
			if drag_prev_state.data.prev_position.hash() != drag_prev_state.data.new_position.hash() or \
			   drag_prev_state.data.prev_size.hash() != drag_prev_state.data.new_size.hash():
				_record_action("resize_box", {
					"box_id": drag_prev_state.data.box_id,
					"frame": drag_prev_state.data.frame,
					"prev_position": drag_prev_state.data.prev_position,
					"prev_size": drag_prev_state.data.prev_size,
					"new_position": drag_prev_state.data.new_position,
					"new_size": drag_prev_state.data.new_size
				})

	drag_prev_state = null

# ==========================================
# 属性面板
# ==========================================
func _update_property_panel(config: AttackBoxData.FrameConfig):
	_disconnect_value_signals()

	_pos_x.value = config.position.x
	_pos_y.value = config.position.y
	_pos_z.value = config.position.z
	_size_x.value = config.size.x
	_size_y.value = config.size.y
	_size_z.value = config.size.z

	_connect_value_signals()

func _reset_property_panel():
	_disconnect_value_signals()

	_pos_x.value = 0
	_pos_y.value = 0
	_pos_z.value = 0
	_size_x.value = 50
	_size_y.value = 50
	_size_z.value = 50

	_connect_value_signals()

func _on_property_changed(_value: float):
	if not _current_box_id:
		return

	if not _attack_boxes.has(_current_box_id):
		return

	var box_data = _attack_boxes[_current_box_id]
	var current_frame = int(_frame_selector.value)

	# 首次属性修改时快照原始状态
	if _pending_property_action.is_empty() or \
	   _pending_property_action.get("box_id") != _current_box_id or \
	   _pending_property_action.get("frame") != current_frame:
		_pending_property_action = {
			"box_id": _current_box_id,
			"frame": current_frame,
			"prev_snapshot": _snapshot_frame_config(box_data, current_frame)
		}

	var config = box_data.get_frame_config(current_frame)
	if not config:
		config = AttackBoxData.FrameConfig.new()
		box_data.set_frame_config(current_frame, config)

	config.position.x = _pos_x.value
	config.position.y = _pos_y.value
	config.position.z = _pos_z.value
	config.size.x = _size_x.value
	config.size.y = _size_y.value
	config.size.z = _size_z.value

	_has_unsaved_changes = true
	_refresh_box_visuals()

func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if _is_anim_player_entity:
			if _canvas and _canvas.get_node_or_null("EntityPreview"):
				_apply_canvas_transform()
		elif _preview_sprite and _canvas:
			_apply_canvas_transform()
