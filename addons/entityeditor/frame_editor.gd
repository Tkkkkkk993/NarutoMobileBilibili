# frame_editor.gd V2有AI帮助，可能存在神秘隐患Bug！！
@tool
extends Window

const ANIM_FPS := 60.0

# ============================================
# 画布控制相关变量
# ============================================
enum CanvasTool { SELECT, PAN, ZOOM }
var current_tool: CanvasTool = CanvasTool.SELECT

var preview_root_position: Vector2 = Vector2(300, 300)
var _canvas_zoom: float = 1.0
var min_zoom: float = 0.1
var max_zoom: float = 5.0
var zoom_step: float = 0.1

var is_panning: bool = false
var pan_start_mouse: Vector2 = Vector2.ZERO
var pan_start_offset: Vector2 = Vector2.ZERO

# 撤回重做系统
var undo_stack: Array = []
var redo_stack: Array = []
var max_undo_steps: int = 50
var is_recording_action: bool = true
var drag_prev_state: EditorAction = null

# UI 引用 - 左面板
var _hitbox_list: ItemList
var _add_hitbox_btn: Button
var _del_hitbox_btn: Button

# UI 引用 - 中间画布
var _canvas: Control
var _draw_node: Node2D
var _interaction_layer: Control

# UI 引用 - 右面板
var _anim_selector: OptionButton
var _frame_selector: SpinBox
var _frame_info_label: Label
var _anchor_x_spinbox: SpinBox
var _anchor_y_spinbox: SpinBox
var _apply_anchor_all_button: Button
var _hitbox_pos_x_spinbox: SpinBox
var _hitbox_pos_y_spinbox: SpinBox
var _hitbox_rot_spinbox: SpinBox
var _hitbox_size_x_spinbox: SpinBox
var _hitbox_size_y_spinbox: SpinBox
var _hitbox_radius_spinbox: SpinBox
var _hitbox_size_container: VBoxContainer
var _hitbox_visible_checkbox: CheckBox

# 控件大小配置（可持久化）
var handle_size: float = 16.0  # 用户可调的控件大小，会保存到文件
const HANDLE_SIZE_MIN: float = 4.0
const HANDLE_SIZE_MAX: float = 48.0
var _handle_size_slider: HSlider
var _handle_size_value_label: Label

# 工具栏按钮
var tool_button_group: ButtonGroup = ButtonGroup.new()
var select_tool_button: Button
var pan_tool_button: Button
var zoom_label: Label
var reset_view_button: Button
var undo_button: Button
var redo_button: Button

var debug_button: Button
var copy_button: Button
var paste_button: Button

# ============================================
# 原有变量声明
# ============================================
var animated_sprite: AnimatedSprite2D = null
var _entity_instance: Node = null           # 原始实体实例
var _visual_node: Node2D = null             # 视觉参考节点
var _anim_entity: EntityBase = null         # 动画控制器（EntityBase 实例）
var _is_anim_player_entity: bool = false    # 是否为 AnimationPlayerEntity
var current_animation: String = ""
var current_frame: int = 0
var animation_data: Dictionary = {}
var hitbox_areas: Array[Area2D] = []

var animation_global_anchors: Dictionary = {}

var anchor_viz_color: Color = Color(1.0, 0.3, 0.3, 0.9)
var anchor_viz_size: float = 30.0

enum MouseMode { NONE, MOVE_ANCHOR, MOVE_HITBOX, ROTATE_HITBOX, SCALE_HITBOX, RESIZE_HITBOX_N, RESIZE_HITBOX_S, RESIZE_HITBOX_E, RESIZE_HITBOX_W, RESIZE_HITBOX_NE, RESIZE_HITBOX_NW, RESIZE_HITBOX_SE, RESIZE_HITBOX_SW }
var current_mouse_mode: MouseMode = MouseMode.NONE
var is_mouse_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_last_mouse_pos: Vector2 = Vector2.ZERO   # 上一帧鼠标逻辑位置
var drag_start_value: Variant = null
var drag_pivot_offset: Vector2 = Vector2.ZERO
var drag_anchor_pivot_offset: Vector2 = Vector2.ZERO
var selected_hitbox_index: int = -1
var debug_mode: bool = false
var _prev_hitbox_vis: Dictionary = {}  # 缓存每个受击框的 visible 状态
var _is_playing: bool = false  # 动画播放状态

var handle_base_size: float = 16.0
var handle_hover_size: float = 20.0
var handle_click_threshold: float = 50.0  # 增大以便更容易点到缩放手柄

var entity_scene_path: String = ""
var frame_data_file_path: String = ""
var is_data_modified: bool = false:
	set(v):
		is_data_modified = v
		_update_title()

var copied_frame_data: Dictionary = {}

var keyboard_move_speed: float = 1.0
var keyboard_fast_move_speed: float = 10.0
var keyboard_slow_move_speed: float = 0.1

# ============================================
# 操作记录类
# ============================================
class EditorAction:
	var type: String
	var data: Dictionary
	var timestamp: int

	func _init(t: String, d: Dictionary):
		type = t
		data = d
		timestamp = Time.get_ticks_msec()

func _ready():
	size = Vector2(1400, 900)
	min_size = Vector2(900, 700)
	close_requested.connect(_on_close_requested)
	_update_title()
	_setup_ui()
	call_deferred("_center_window")
	set_process_input(true)


func _update_title():
	var prefix = "*" if is_data_modified else ""
	var base = "帧数据编辑器V2.1"
	if entity_scene_path != "":
		var trimmed = entity_scene_path.trim_prefix("res://assets/entities/")
		var last_slash = trimmed.rfind("/")
		var name = trimmed.substr(0, last_slash) if last_slash >= 0 else trimmed
		base += " - " + name
	title = prefix + base


func _center_window():
	var screen_size = DisplayServer.screen_get_size()
	position = Vector2((screen_size.x - size.x) / 2, (screen_size.y - size.y) / 2)

# ==========================================
# UI 构建 - 三列布局
# ==========================================
func _setup_ui():
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.offset_left = 10
	main_hbox.offset_top = 10
	main_hbox.offset_right = -10
	main_hbox.offset_bottom = -10
	main_hbox.add_theme_constant_override("separation", 10)
	add_child(main_hbox)

	# ========== 左侧面板 ==========
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(280, 0)
	main_hbox.add_child(left_vbox)

	var left_title = Label.new()
	left_title.text = "受击框列表"
	left_title.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(left_title)

	_hitbox_list = ItemList.new()
	_hitbox_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hitbox_list.item_selected.connect(_on_hitbox_list_selected)
	left_vbox.add_child(_hitbox_list)

	var left_btn_hbox = HBoxContainer.new()
	left_vbox.add_child(left_btn_hbox)

	_add_hitbox_btn = Button.new()
	_add_hitbox_btn.text = "添加受击框"
	_add_hitbox_btn.pressed.connect(_on_add_hitbox)
	left_btn_hbox.add_child(_add_hitbox_btn)

	_del_hitbox_btn = Button.new()
	_del_hitbox_btn.text = "删除"
	_del_hitbox_btn.pressed.connect(_on_delete_hitbox)
	left_btn_hbox.add_child(_del_hitbox_btn)

	# ========== 中间画布 ==========
	var center_vbox = VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(center_vbox)

	var center_title = Label.new()
	center_title.text = "编辑区域（左键拖拽 | 中键平移 | 滚轮缩放 | Q选择 H平移）"
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

	# ========== 右侧面板 ==========
	var right_scroll = ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(220, 0)
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_hbox.add_child(right_scroll)

	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_scroll.add_child(right_vbox)

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
	_anim_selector.item_selected.connect(_on_animation_selected)
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
	_frame_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_selector.value_changed.connect(_on_frame_changed)
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

	# 帧信息
	_frame_info_label = Label.new()
	_frame_info_label.text = "帧: 0/0"
	right_vbox.add_child(_frame_info_label)

	# ---- 锚点区域 ----
	right_vbox.add_child(HSeparator.new())
	var anchor_title = Label.new()
	anchor_title.text = "锚点"
	anchor_title.add_theme_color_override("font_color", Color.YELLOW)
	right_vbox.add_child(anchor_title)

	_anchor_x_spinbox = _add_spinbox_row(right_vbox, "X:", -999999, 999999, 0, "锚点X坐标")
	_anchor_y_spinbox = _add_spinbox_row(right_vbox, "Y:", -999999, 999999, 0, "锚点Y坐标")
	_anchor_x_spinbox.step = 0.1
	_anchor_y_spinbox.step = 0.1
	_anchor_x_spinbox.value_changed.connect(_on_anchor_changed.bind("x"))
	_anchor_y_spinbox.value_changed.connect(_on_anchor_changed.bind("y"))

	_apply_anchor_all_button = Button.new()
	_apply_anchor_all_button.text = "设为全局锚点"
	_apply_anchor_all_button.tooltip_text = "将当前锚点设置应用到当前动画的所有帧"
	_apply_anchor_all_button.pressed.connect(_on_apply_anchor_all_pressed)
	right_vbox.add_child(_apply_anchor_all_button)

	# ---- 受击框属性 ----
	right_vbox.add_child(HSeparator.new())
	var hitbox_title = Label.new()
	hitbox_title.text = "受击框属性"
	hitbox_title.add_theme_color_override("font_color", Color.YELLOW)
	right_vbox.add_child(hitbox_title)

	_hitbox_pos_x_spinbox = _add_spinbox_row(right_vbox, "X:", -999999, 999999, 0, "受击框X位置")
	_hitbox_pos_y_spinbox = _add_spinbox_row(right_vbox, "Y:", -999999, 999999, 0, "受击框Y位置")
	_hitbox_pos_x_spinbox.step = 0.1
	_hitbox_pos_y_spinbox.step = 0.1
	_hitbox_pos_x_spinbox.value_changed.connect(_on_hitbox_position_changed.bind("x"))
	_hitbox_pos_y_spinbox.value_changed.connect(_on_hitbox_position_changed.bind("y"))

	_hitbox_rot_spinbox = _add_spinbox_row(right_vbox, "旋转:", -999999, 999999, 0, "受击框旋转角度")
	_hitbox_rot_spinbox.suffix = "°"
	_hitbox_rot_spinbox.step = 0.1
	_hitbox_rot_spinbox.value_changed.connect(_on_hitbox_rotation_changed)

	# 受击框可见性复选框
	var vis_hbox = HBoxContainer.new()
	right_vbox.add_child(vis_hbox)
	var vis_label = Label.new()
	vis_label.text = "可见:"
	vis_label.custom_minimum_size = Vector2(60, 0)
	vis_hbox.add_child(vis_label)
	_hitbox_visible_checkbox = CheckBox.new()
	_hitbox_visible_checkbox.button_pressed = true
	_hitbox_visible_checkbox.toggled.connect(_on_hitbox_visible_toggled)
	vis_hbox.add_child(_hitbox_visible_checkbox)

	# 受击框大小容器（根据形状类型动态切换）
	_hitbox_size_container = VBoxContainer.new()
	right_vbox.add_child(_hitbox_size_container)

	_hitbox_size_x_spinbox = _add_spinbox_row(_hitbox_size_container, "宽:", 0.001, 999999, 0, "矩形宽度")
	_hitbox_size_y_spinbox = _add_spinbox_row(_hitbox_size_container, "高:", 0.001, 999999, 0, "矩形高度")
	_hitbox_size_x_spinbox.step = 0.1
	_hitbox_size_y_spinbox.step = 0.1
	_hitbox_size_x_spinbox.value_changed.connect(_on_hitbox_size_changed.bind("x"))
	_hitbox_size_y_spinbox.value_changed.connect(_on_hitbox_size_changed.bind("y"))

	_hitbox_radius_spinbox = _add_spinbox_row(_hitbox_size_container, "半径:", 0.001, 999999, 0, "圆形半径")
	_hitbox_radius_spinbox.step = 0.1
	_hitbox_radius_spinbox.value_changed.connect(_on_hitbox_radius_changed)

	# ---- 复制粘贴 ----
	right_vbox.add_child(HSeparator.new())

	var copy_hbox = HBoxContainer.new()
	right_vbox.add_child(copy_hbox)

	copy_button = Button.new()
	copy_button.text = "复制当前帧"
	copy_button.tooltip_text = "复制当前帧的锚点和碰撞箱设置"
	copy_button.pressed.connect(_on_copy_pressed)
	copy_hbox.add_child(copy_button)

	paste_button = Button.new()
	paste_button.text = "粘贴到当前帧"
	paste_button.tooltip_text = "将复制的设置粘贴到当前帧"
	paste_button.pressed.connect(_on_paste_pressed)
	copy_hbox.add_child(paste_button)

	# ---- 撤回 / 重做 ----
	right_vbox.add_child(HSeparator.new())

	var undo_hbox = HBoxContainer.new()
	right_vbox.add_child(undo_hbox)

	undo_button = Button.new()
	undo_button.text = "撤回"
	undo_button.pressed.connect(_on_undo_pressed)
	undo_hbox.add_child(undo_button)

	redo_button = Button.new()
	redo_button.text = "重做"
	redo_button.pressed.connect(_on_redo_pressed)
	undo_hbox.add_child(redo_button)

	# ---- 动画预览 ----
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

	# ---- 工具栏 ----
	right_vbox.add_child(HSeparator.new())
	var tool_title = Label.new()
	tool_title.text = "工具"
	right_vbox.add_child(tool_title)

	var tool_hbox = HBoxContainer.new()
	right_vbox.add_child(tool_hbox)

	select_tool_button = Button.new()
	select_tool_button.text = "选择(Q)"
	select_tool_button.toggle_mode = true
	select_tool_button.button_pressed = true
	select_tool_button.button_group = tool_button_group
	select_tool_button.pressed.connect(_on_tool_selected.bind(CanvasTool.SELECT))
	tool_hbox.add_child(select_tool_button)

	pan_tool_button = Button.new()
	pan_tool_button.text = "平移(H)"
	pan_tool_button.toggle_mode = true
	pan_tool_button.button_group = tool_button_group
	pan_tool_button.pressed.connect(_on_tool_selected.bind(CanvasTool.PAN))
	tool_hbox.add_child(pan_tool_button)

	var tool_hbox2 = HBoxContainer.new()
	right_vbox.add_child(tool_hbox2)

	zoom_label = Label.new()
	zoom_label.text = "100%"
	zoom_label.custom_minimum_size.x = 60
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tool_hbox2.add_child(zoom_label)

	reset_view_button = Button.new()
	reset_view_button.text = "重置视图"
	reset_view_button.pressed.connect(_on_reset_view_pressed)
	tool_hbox2.add_child(reset_view_button)

	debug_button = Button.new()
	debug_button.text = "调试模式"
	debug_button.toggle_mode = true
	debug_button.button_pressed = debug_mode
	debug_button.pressed.connect(_on_debug_mode_toggled)
	right_vbox.add_child(debug_button)

	# ---- 控件大小配置 ----
	right_vbox.add_child(HSeparator.new())
	var handle_size_title = Label.new()
	handle_size_title.text = "控件设置"
	handle_size_title.add_theme_color_override("font_color", Color.YELLOW)
	right_vbox.add_child(handle_size_title)

	# 手柄大小滑杆
	var handle_size_hbox = HBoxContainer.new()
	right_vbox.add_child(handle_size_hbox)
	var handle_size_label = Label.new()
	handle_size_label.text = "手柄大小:"
	handle_size_label.custom_minimum_size = Vector2(90, 0)
	handle_size_hbox.add_child(handle_size_label)

	_handle_size_slider = HSlider.new()
	_handle_size_slider.min_value = HANDLE_SIZE_MIN
	_handle_size_slider.max_value = HANDLE_SIZE_MAX
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

	# ---- 说明 ----
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

# ==========================================
# 说明按钮
# ==========================================
func _on_help_button():
	var dialog = AcceptDialog.new()
	dialog.title = "帧数据编辑器说明"
	dialog.size = Vector2(600, 400)
	dialog.min_size = Vector2(400, 300)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	dialog.add_child(scroll)

	var label = Label.new()
	label.custom_minimum_size.x = 560
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "=== 帧数据编辑器V2 使用说明 ===\n\n"
	label.text += "本编辑器用于编辑实体的帧数据，包括锚点和受击框。\n\n"
	label.text += "操作方式:\n"
	label.text += "  - 左键拖拽: 移动受击框/锚点\n"
	label.text += "  - 中键拖拽: 平移画布\n"
	label.text += "  - 滚轮: 缩放画布\n"
	label.text += "  - Q: 选择工具\n"
	label.text += "  - H: 平移工具\n"
	label.text += "  - Ctrl+Z: 撤回\n"
	label.text += "  - Ctrl+Y: 重做\n"
	label.text += "  - Ctrl+0: 重置视图\n"
	label.text += "  - Tab: 切换选中受击框\n"
	label.text += "  - 方向键: 微调受击框位置\n"
	label.text += "  - Shift+方向键: 快速移动\n"
	label.text += "  - Ctrl+方向键: 精细移动\n\n"
	label.text += "颜色说明:\n"
	label.text += "  - 红色十字: 锚点\n"
	label.text += "  - 绿色圆: 位置手柄\n"
	label.text += "  - 紫色圆: 旋转手柄\n"
	label.text += "  - 蓝色方: 缩放手柄\n\n"
	label.text += "工作流程:\n"
	label.text += "  1. 选择动画和帧\n"
	label.text += "  2. 在左侧列表选择受击框\n"
	label.text += "  3. 在画布上拖拽或在右侧面板调整属性\n"
	label.text += "  4. 点击'应用到当前帧'\n"
	label.text += "  5. 保存数据"
	scroll.add_child(label)

	add_child(dialog)
	dialog.popup_centered()

# ==========================================
# 关闭与保存对话框
# ==========================================
func _on_close_requested():
	if is_data_modified:
		_show_unsaved_dialog()
	else:
		_cleanup_visualization_nodes()
		queue_free()

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
	save_frame_data()
	queue_free()

func _on_exit_without_save(dialog: ConfirmationDialog):
	dialog.queue_free()
	queue_free()

func _on_dialog_custom_action(action: String, dialog: ConfirmationDialog):
	if action == "cancel":
		dialog.queue_free()

# ==========================================
# 工具选择
# ==========================================
func _on_tool_selected(tool: CanvasTool):
	current_tool = tool
	_update_tool_buttons()

func _update_tool_buttons():
	select_tool_button.button_pressed = (current_tool == CanvasTool.SELECT)
	pan_tool_button.button_pressed = (current_tool == CanvasTool.PAN)

func _update_zoom_label():
	zoom_label.text = "%d%%" % int(_canvas_zoom * 100)

func _on_reset_view_pressed():
	_record_action("reset_view", {
		"prev_offset": preview_root_position,
		"prev_zoom": _canvas_zoom,
		"new_offset": Vector2(300, 300),
		"new_zoom": 1.0
	})
	preview_root_position = Vector2(300, 300)
	_canvas_zoom = 1.0
	_update_zoom_label()
	_apply_canvas_transform()

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
	undo_button.disabled = undo_stack.is_empty()
	redo_button.disabled = redo_stack.is_empty()
	if not undo_stack.is_empty():
		var last_action = undo_stack.back()
		undo_button.text = "撤回 (%s)" % _get_action_name(last_action.type)
	else:
		undo_button.text = "撤回"
	if not redo_stack.is_empty():
		var next_action = redo_stack.back()
		redo_button.text = "重做 (%s)" % _get_action_name(next_action.type)
	else:
		redo_button.text = "重做"

func _get_action_name(action_type: String) -> String:
	match action_type:
		"move_hitbox": return "移动"
		"rotate_hitbox": return "旋转"
		"scale_hitbox": return "缩放"
		"move_anchor": return "移动锚点"
		"reset_view": return "重置视图"
		"zoom": return "缩放"
		"pan": return "平移"
		"paste": return "粘贴"
		_: return "操作"

func _on_undo_pressed():
	if undo_stack.is_empty():
		return
	var action = undo_stack.pop_back()
	redo_stack.append(action)
	is_recording_action = false
	_apply_action_inverse(action)
	is_recording_action = true
	_update_undo_redo_buttons()

func _on_redo_pressed():
	if redo_stack.is_empty():
		return
	var action = redo_stack.pop_back()
	undo_stack.append(action)
	is_recording_action = false
	_apply_action(action)
	is_recording_action = true
	_update_undo_redo_buttons()

func _apply_action(action: EditorAction):
	match action.type:
		"move_hitbox":
			var index = action.data.index
			var new_pos = action.data.new_position
			if index < hitbox_areas.size():
				hitbox_areas[index].position = new_pos
				_update_hitbox_data_from_scene(animation_data[current_animation][current_frame])
		"rotate_hitbox":
			var index = action.data.index
			var new_rot = action.data.new_rotation
			if index < hitbox_areas.size():
				hitbox_areas[index].rotation = new_rot
				_update_hitbox_data_from_scene(animation_data[current_animation][current_frame])
		"scale_hitbox":
			var index = action.data.index
			var new_scale = action.data.new_scale
			if index < hitbox_areas.size():
				hitbox_areas[index].scale = new_scale
				_update_hitbox_data_from_scene(animation_data[current_animation][current_frame])
		"resize_hitbox":
			var index = action.data.index
			if index < hitbox_areas.size():
				var area = hitbox_areas[index]
				var shape_node = area.get_child(0) if area.get_child_count() > 0 else null
				if shape_node and shape_node is CollisionShape2D:
					if action.data.has("new_position"):
						area.position = action.data.new_position
					if action.data.has("new_size") and shape_node.shape is RectangleShape2D:
						var new_shape = RectangleShape2D.new()
						new_shape.size = action.data.new_size
						shape_node.shape = new_shape
					elif action.data.has("new_radius") and shape_node.shape is CircleShape2D:
						var new_shape = CircleShape2D.new()
						new_shape.radius = action.data.new_radius
						shape_node.shape = new_shape
				_update_hitbox_data_from_scene(animation_data[current_animation][current_frame])
		"move_anchor":
			var new_anchor = action.data.new_anchor
			_set_current_anchor(new_anchor)
			_anchor_x_spinbox.value = new_anchor.x
			_anchor_y_spinbox.value = new_anchor.y
		"reset_view", "pan", "zoom":
			preview_root_position = action.data.new_offset
			_canvas_zoom = action.data.new_zoom
			_update_zoom_label()
			_apply_canvas_transform()
		"paste":
			if animation_data[current_animation].has(current_frame):
				var frame_data = animation_data[current_animation][current_frame]
				frame_data.deserialize(action.data.pasted_data.duplicate(true))
				_restore_hitbox_shapes(frame_data)
				_anchor_x_spinbox.value = frame_data.anchor_point.x
				_anchor_y_spinbox.value = frame_data.anchor_point.y
	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

func _apply_action_inverse(action: EditorAction):
	match action.type:
		"move_hitbox":
			var index = action.data.index
			var prev_pos = action.data.prev_position
			if index < hitbox_areas.size():
				hitbox_areas[index].position = prev_pos
				_update_hitbox_data_from_scene(animation_data[current_animation][current_frame])
		"rotate_hitbox":
			var index = action.data.index
			var prev_rot = action.data.prev_rotation
			if index < hitbox_areas.size():
				hitbox_areas[index].rotation = prev_rot
				_update_hitbox_data_from_scene(animation_data[current_animation][current_frame])
		"scale_hitbox":
			var index = action.data.index
			var prev_scale = action.data.prev_scale
			if index < hitbox_areas.size():
				hitbox_areas[index].scale = prev_scale
				_update_hitbox_data_from_scene(animation_data[current_animation][current_frame])
		"resize_hitbox":
			var index = action.data.index
			if index < hitbox_areas.size():
				var area = hitbox_areas[index]
				var shape_node = area.get_child(0) if area.get_child_count() > 0 else null
				if shape_node and shape_node is CollisionShape2D:
					if action.data.has("prev_position"):
						area.position = action.data.prev_position
					if action.data.has("prev_size") and shape_node.shape is RectangleShape2D:
						var new_shape = RectangleShape2D.new()
						new_shape.size = action.data.prev_size
						shape_node.shape = new_shape
					elif action.data.has("prev_radius") and shape_node.shape is CircleShape2D:
						var new_shape = CircleShape2D.new()
						new_shape.radius = action.data.prev_radius
						shape_node.shape = new_shape
				_update_hitbox_data_from_scene(animation_data[current_animation][current_frame])
		"move_anchor":
			var prev_anchor = action.data.prev_anchor
			_set_current_anchor(prev_anchor)
			_anchor_x_spinbox.value = prev_anchor.x
			_anchor_y_spinbox.value = prev_anchor.y
		"reset_view", "pan", "zoom":
			preview_root_position = action.data.prev_offset
			_canvas_zoom = action.data.prev_zoom
			_update_zoom_label()
			_apply_canvas_transform()
		"paste":
			if animation_data[current_animation].has(current_frame):
				var frame_data = animation_data[current_animation][current_frame]
				frame_data.deserialize(action.data.prev_data.duplicate(true))
				_restore_hitbox_shapes(frame_data)
				_anchor_x_spinbox.value = frame_data.anchor_point.x
				_anchor_y_spinbox.value = frame_data.anchor_point.y
	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

# ==========================================
# setup_entity - 外部调用接口（兼容 AnimatedSprite2DEntity 和 AnimationPlayerEntity）
# ==========================================
func setup_entity(entity: Node, visual_node: Node2D, scene_path: String = ""):
	_entity_instance = entity
	_visual_node = visual_node
	entity_scene_path = scene_path
	_update_title()
	
	# 检测实体类型
	if entity is EntityBase:
		_anim_entity = entity as EntityBase
		_is_anim_player_entity = _find_animation_player(entity) != null
	else:
		_is_anim_player_entity = false
	
	if entity_scene_path != "":
		var base_path = entity_scene_path.get_basename()
		frame_data_file_path = base_path + "_frame_data.json"
		_load_frame_data()
	
	_create_preview()
	is_data_modified = false
	popup_centered()

# 兼容旧接口
func setup_animated_sprite(sprite: AnimatedSprite2D, scene_path: String = ""):
	setup_entity(null, sprite, scene_path)

func _create_preview():
	if _is_anim_player_entity:
		_create_anim_player_preview()
	else:
		_create_sprite_preview()

func _create_sprite_preview():
	if not _visual_node or not (_visual_node is AnimatedSprite2D):
		return
	
	var original_sprite = _visual_node as AnimatedSprite2D
	if not original_sprite.sprite_frames:
		return
	
	animated_sprite = AnimatedSprite2D.new()
	animated_sprite.name = "PreviewAnimatedSprite"
	animated_sprite.sprite_frames = original_sprite.sprite_frames.duplicate()
	animated_sprite.scale = Vector2.ONE
	animated_sprite.rotation = original_sprite.rotation
	animated_sprite.flip_h = original_sprite.flip_h
	animated_sprite.flip_v = original_sprite.flip_v
	animated_sprite.modulate = original_sprite.modulate
	animated_sprite.stop()
	
	_canvas.add_child(animated_sprite)
	_duplicate_hitbox_structure(original_sprite)
	_setup_animations()
	
	call_deferred("_center_preview")

func _create_anim_player_preview():
	if not _entity_instance:
		return
	
	# 实例化场景而非 duplicate()——避免 GLB 节点复制 BUG
	var preview
	if entity_scene_path and entity_scene_path != "":
		preview = load(entity_scene_path).instantiate()
	else:
		preview = _entity_instance.duplicate()
	preview.name = "EntityPreview"
	# 防止 EntityPreview 拦截鼠标事件（让 InteractionLayer 能接收事件）
	if preview is CollisionObject2D:
		(preview as CollisionObject2D).input_pickable = false
	_canvas.add_child(preview)
	
	# 确保 InteractionLayer 在最上层
	if _interaction_layer:
		_canvas.move_child(_interaction_layer, _canvas.get_child_count() - 1)
	
	# 找到预览实体中的 AnimationPlayer
	var ap = _find_animation_player(preview)
	if ap:
		ap.stop()
	
	# 收集实体中的受击框 Area2D
	hitbox_areas.clear()
	_collect_hitbox_areas(preview)
	
	# 设置动画数据
	_setup_animations_from_entity()
	
	call_deferred("_center_preview")

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null

func _collect_hitbox_areas(node: Node):
	for child in node.get_children():
		if child is Area2D and child.name.begins_with("HitboxArea"):
			hitbox_areas.append(child)
		_collect_hitbox_areas(child)
	
	_refresh_hitbox_list()

func _center_preview():
	if _is_anim_player_entity:
		if not _canvas.get_node_or_null("EntityPreview"):
			return
	else:
		if not animated_sprite:
			return
	await get_tree().process_frame
	_apply_canvas_transform()

func _duplicate_hitbox_structure(original_sprite: AnimatedSprite2D):
	hitbox_areas.clear()
	for child in original_sprite.get_children():
		if child is Area2D and child.name.begins_with("HitboxArea"):
			var new_area = Area2D.new()
			new_area.name = child.name
			new_area.position = child.position
			new_area.rotation = child.rotation
			new_area.scale = child.scale

			for shape_child in child.get_children():
				if shape_child is CollisionShape2D:
					var new_shape_node = CollisionShape2D.new()
					new_shape_node.name = shape_child.name
					new_shape_node.position = shape_child.position
					new_shape_node.rotation = shape_child.rotation
					new_shape_node.scale = shape_child.scale

					if shape_child.shape:
						if shape_child.shape is RectangleShape2D:
							var new_rect = RectangleShape2D.new()
							new_rect.size = shape_child.shape.size
							new_shape_node.shape = new_rect
						elif shape_child.shape is CircleShape2D:
							var new_circle = CircleShape2D.new()
							new_circle.radius = shape_child.shape.radius
							new_shape_node.shape = new_circle

					new_area.add_child(new_shape_node)

			animated_sprite.add_child(new_area)
			hitbox_areas.append(new_area)

	_refresh_hitbox_list()

# ==========================================
# 画布变换
# ==========================================
func _apply_canvas_transform():
	if _is_anim_player_entity:
		var preview_root = _canvas.get_node_or_null("EntityPreview")
		if not preview_root:
			return
		preview_root.position = preview_root_position * _canvas_zoom
		preview_root.scale = Vector2.ONE * _canvas_zoom
	else:
		if not animated_sprite:
			return
		animated_sprite.position = preview_root_position * _canvas_zoom
		animated_sprite.scale = Vector2.ONE * _canvas_zoom

	# 绘制节点：只移动，不缩放
	_draw_node.position = preview_root_position * _canvas_zoom
	_draw_node.scale = Vector2(1, 1)

	_draw_node.queue_redraw()

# ==========================================
# 坐标转换
# ==========================================
func _screen_to_logical(screen_pos: Vector2) -> Vector2:
	return (screen_pos / _canvas_zoom) - preview_root_position

func _logical_to_screen(logical_pos: Vector2) -> Vector2:
	return (logical_pos + preview_root_position) * _canvas_zoom

# ==========================================
# 交互逻辑
# ==========================================
func _on_interaction_input(event: InputEvent):
	if _is_anim_player_entity:
		if not _canvas.get_node_or_null("EntityPreview"):
			return
	else:
		if not animated_sprite:
			return

	# 鼠标按键处理
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton

		# 缩放处理 (滚轮)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var zoom_factor = 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9
			var old_zoom = _canvas_zoom
			_canvas_zoom = clamp(_canvas_zoom * zoom_factor, min_zoom, max_zoom)

			# 以鼠标为中心缩放
			var mouse_pos = mb.position
			var logical_mouse_before = (mouse_pos / old_zoom) - preview_root_position
			preview_root_position = (mouse_pos / _canvas_zoom) - logical_mouse_before

			_record_action("zoom", {
				"prev_offset": preview_root_position,
				"prev_zoom": old_zoom,
				"new_offset": preview_root_position,
				"new_zoom": _canvas_zoom
			})

			_update_zoom_label()
			_apply_canvas_transform()
			return

		# 平移处理 (中键)
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				is_panning = true
				pan_start_mouse = mb.position
				pan_start_offset = preview_root_position
				DisplayServer.cursor_set_shape(DisplayServer.CURSOR_DRAG)
			else:
				if is_panning:
					if pan_start_offset != preview_root_position:
						_record_action("pan", {
							"prev_offset": pan_start_offset,
							"prev_zoom": _canvas_zoom,
							"new_offset": preview_root_position,
							"new_zoom": _canvas_zoom
						})
				is_panning = false
				DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)

		# 左键处理
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_handle_left_button_press(mb)
			else:
				_handle_left_button_release(mb)

		# 右键取消
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if is_mouse_dragging:
				is_mouse_dragging = false
				current_mouse_mode = MouseMode.NONE
				if drag_prev_state != null and drag_prev_state.data.size() > 0:
					_apply_action_inverse(drag_prev_state)
				drag_prev_state = null
				_update_mouse_mode_button()
				_draw_node.queue_redraw()

	# 鼠标移动处理
	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion

		if is_panning:
			var drag_delta = (mm.position - pan_start_mouse) / _canvas_zoom
			preview_root_position = pan_start_offset + drag_delta
			_apply_canvas_transform()
		elif is_mouse_dragging:
			_handle_drag(mm)
		else:
			_handle_hover(mm)

func _handle_left_button_press(event: InputEventMouseButton):
	if _is_anim_player_entity:
		if not _canvas.get_node_or_null("EntityPreview"):
			return
	elif not animated_sprite:
		return

	var logical_mouse = _screen_to_logical(event.position)

	match current_tool:
		CanvasTool.SELECT:
			_handle_select_tool_press(logical_mouse)
		CanvasTool.PAN:
			is_panning = true
			pan_start_mouse = event.position
			pan_start_offset = preview_root_position
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_DRAG)

func _handle_left_button_release(event: InputEventMouseButton):
	if is_panning and current_tool == CanvasTool.PAN:
		if pan_start_offset != preview_root_position:
			_record_action("pan", {
				"prev_offset": pan_start_offset,
				"prev_zoom": _canvas_zoom,
				"new_offset": preview_root_position,
				"new_zoom": _canvas_zoom
			})
		is_panning = false
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)
	elif is_mouse_dragging:
		_end_drag()

func _handle_select_tool_press(logical_mouse: Vector2):
	# === 优先级1：检测锚点点击（锚点永远在最上层） ===
	if _is_point_near_anchor(logical_mouse):
		current_mouse_mode = MouseMode.MOVE_ANCHOR
		is_mouse_dragging = true
		drag_start_pos = logical_mouse
		drag_start_value = _get_current_anchor()
		drag_anchor_pivot_offset = logical_mouse - drag_start_value

		drag_prev_state = EditorAction.new("move_anchor", {
			"prev_anchor": drag_start_value,
			"new_anchor": drag_start_value
		})

		_update_mouse_mode_button()
		return

	# === 优先级2：检测手柄点击（缩放/旋转/位置） ===
	var handle_info = _get_clicked_handle(logical_mouse)
	if handle_info:
		selected_hitbox_index = handle_info.index
		current_mouse_mode = handle_info.type
		is_mouse_dragging = true
		drag_last_mouse_pos = logical_mouse
		drag_start_pos = logical_mouse
		drag_start_value = _get_current_hitbox_value(selected_hitbox_index, current_mouse_mode)

		var area = hitbox_areas[selected_hitbox_index]
		var shape_node = area.get_child(0) if area.get_child_count() > 0 else null
		var action_data = {
			"index": selected_hitbox_index,
			"prev_position": area.position,
			"prev_rotation": area.rotation,
			"prev_scale": area.scale,
			"new_position": area.position,
			"new_rotation": area.rotation,
			"new_scale": area.scale
		}
		# 对于 resize 模式，额外保存初始形状大小
		if shape_node and shape_node is CollisionShape2D:
			if shape_node.shape is RectangleShape2D:
				action_data["prev_size"] = shape_node.shape.size
			elif shape_node.shape is CircleShape2D:
				action_data["prev_radius"] = shape_node.shape.radius
		drag_prev_state = EditorAction.new(_get_action_type_from_mode(current_mouse_mode), action_data)

		_update_mouse_mode_button()
		_refresh_hitbox_list()
		_update_hitbox_property_panel()
		return

	# === 优先级3：检测受击框点击（拖拽移动） ===
	var hitbox_index = _get_clicked_hitbox(logical_mouse)
	if hitbox_index >= 0:
		selected_hitbox_index = hitbox_index
		current_mouse_mode = MouseMode.MOVE_HITBOX
		is_mouse_dragging = true
		drag_start_pos = logical_mouse
		drag_start_value = hitbox_areas[selected_hitbox_index].position
		drag_pivot_offset = logical_mouse - drag_start_value

		var area = hitbox_areas[selected_hitbox_index]
		drag_prev_state = EditorAction.new("move_hitbox", {
			"index": selected_hitbox_index,
			"prev_position": drag_start_value,
			"prev_rotation": area.rotation,
			"prev_scale": area.scale,
			"new_position": drag_start_value
		})

		_update_mouse_mode_button()
		_refresh_hitbox_list()
		_update_hitbox_property_panel()
		return

	# 点击空白处：取消所有控件的焦点
	_release_all_focus()

func _get_action_type_from_mode(mode: MouseMode) -> String:
	match mode:
		MouseMode.MOVE_HITBOX: return "move_hitbox"
		MouseMode.ROTATE_HITBOX: return "rotate_hitbox"
		MouseMode.SCALE_HITBOX: return "scale_hitbox"
		MouseMode.RESIZE_HITBOX_N, MouseMode.RESIZE_HITBOX_S, MouseMode.RESIZE_HITBOX_E, MouseMode.RESIZE_HITBOX_W,\
		MouseMode.RESIZE_HITBOX_NE, MouseMode.RESIZE_HITBOX_NW, MouseMode.RESIZE_HITBOX_SE, MouseMode.RESIZE_HITBOX_SW:
			return "resize_hitbox"
		_: return "unknown"

func _end_drag():
	if is_mouse_dragging:
		is_mouse_dragging = false

		if current_mouse_mode != MouseMode.NONE and drag_prev_state != null:
			is_data_modified = true

			match drag_prev_state.type:
				"move_hitbox":
					var area = hitbox_areas[drag_prev_state.data.index]
					if drag_prev_state.data.prev_position != area.position:
						_record_action("move_hitbox", {
							"index": drag_prev_state.data.index,
							"prev_position": drag_prev_state.data.prev_position,
							"new_position": area.position
						})
				"rotate_hitbox":
					var area = hitbox_areas[drag_prev_state.data.index]
					if drag_prev_state.data.prev_rotation != area.rotation:
						_record_action("rotate_hitbox", {
							"index": drag_prev_state.data.index,
							"prev_rotation": drag_prev_state.data.prev_rotation,
							"new_rotation": area.rotation
						})
				"scale_hitbox":
					var area = hitbox_areas[drag_prev_state.data.index]
					if drag_prev_state.data.prev_scale != area.scale:
						_record_action("scale_hitbox", {
							"index": drag_prev_state.data.index,
							"prev_scale": drag_prev_state.data.prev_scale,
							"new_scale": area.scale
						})
				"resize_hitbox":
					var area = hitbox_areas[drag_prev_state.data.index]
					var shape_node = area.get_child(0) if area.get_child_count() > 0 else null
					if shape_node and shape_node.shape is RectangleShape2D:
						if drag_prev_state.data.prev_size != shape_node.shape.size or drag_prev_state.data.prev_position != area.position:
							_record_action("resize_hitbox", {
								"index": drag_prev_state.data.index,
								"prev_size": drag_prev_state.data.prev_size,
								"new_size": shape_node.shape.size,
								"prev_position": drag_prev_state.data.prev_position,
								"new_position": area.position
							})
					elif shape_node and shape_node.shape is CircleShape2D:
						if drag_prev_state.data.prev_radius != shape_node.shape.radius:
							_record_action("resize_hitbox", {
								"index": drag_prev_state.data.index,
								"prev_radius": drag_prev_state.data.prev_radius,
								"new_radius": shape_node.shape.radius
							})
				"move_anchor":
					var new_anchor = _get_current_anchor()
					if drag_prev_state.data.prev_anchor != new_anchor:
						_record_action("move_anchor", {
							"prev_anchor": drag_prev_state.data.prev_anchor,
							"new_anchor": new_anchor
						})

			_save_current_frame_state()

		current_mouse_mode = MouseMode.NONE
		_update_mouse_mode_button()
		drag_prev_state = null
		drag_pivot_offset = Vector2.ZERO
		drag_anchor_pivot_offset = Vector2.ZERO

	_draw_node.queue_redraw()

func _handle_drag(event: InputEventMouseMotion):
	if not is_mouse_dragging:
		return
	
	var logical_mouse = _screen_to_logical(event.position)
	var delta_inc = logical_mouse - drag_last_mouse_pos
	drag_last_mouse_pos = logical_mouse
	
	match current_mouse_mode:
		MouseMode.MOVE_ANCHOR:
			_handle_anchor_drag(logical_mouse, delta_inc)          # 传递两个参数
		MouseMode.MOVE_HITBOX:
			_handle_hitbox_move_drag(logical_mouse, delta_inc)     # 传递两个参数
		MouseMode.ROTATE_HITBOX:
			_handle_hitbox_rotate_drag(logical_mouse, delta_inc)   # 传递两个参数
		MouseMode.SCALE_HITBOX:
			_handle_hitbox_scale_drag(logical_mouse, delta_inc)    # 传递两个参数
		MouseMode.RESIZE_HITBOX_N, MouseMode.RESIZE_HITBOX_S, MouseMode.RESIZE_HITBOX_E, MouseMode.RESIZE_HITBOX_W,\
		MouseMode.RESIZE_HITBOX_NE, MouseMode.RESIZE_HITBOX_NW, MouseMode.RESIZE_HITBOX_SE, MouseMode.RESIZE_HITBOX_SW:
			_handle_hitbox_resize_drag(logical_mouse, delta_inc)   # 传递两个参数

func _handle_hover(event: InputEventMouseMotion):
	var logical_mouse = _screen_to_logical(event.position)

	# 锚点优先级最高
	if _is_point_near_anchor(logical_mouse):
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_MOVE)
	elif _get_clicked_handle(logical_mouse) != null:
		var handle_info = _get_clicked_handle(logical_mouse)
		var m = handle_info.type
		if m == MouseMode.MOVE_HITBOX:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_MOVE)
		elif m == MouseMode.ROTATE_HITBOX:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_CROSS)
		elif m == MouseMode.RESIZE_HITBOX_N or m == MouseMode.RESIZE_HITBOX_S:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_VSIZE)
		elif m == MouseMode.RESIZE_HITBOX_E or m == MouseMode.RESIZE_HITBOX_W:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_HSIZE)
		elif m == MouseMode.RESIZE_HITBOX_NE or m == MouseMode.RESIZE_HITBOX_SW:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_FDIAGSIZE)
		elif m == MouseMode.RESIZE_HITBOX_NW or m == MouseMode.RESIZE_HITBOX_SE:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_BDIAGSIZE)
		else:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_POINTING_HAND)
	elif _get_clicked_hitbox(logical_mouse) >= 0:
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_MOVE)
	else:
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)

	_draw_node.queue_redraw()

func _handle_anchor_drag(logical_mouse: Vector2, _delta_inc: Vector2):
	var new_anchor = logical_mouse - drag_anchor_pivot_offset
	_set_current_anchor(new_anchor)
	_anchor_x_spinbox.set_value_no_signal(new_anchor.x)
	_anchor_y_spinbox.set_value_no_signal(new_anchor.y)
	if drag_prev_state != null:
		drag_prev_state.data.new_anchor = new_anchor
	_draw_node.queue_redraw()

func _handle_hitbox_move_drag(logical_mouse: Vector2, _delta_inc: Vector2):
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return
	var area = hitbox_areas[selected_hitbox_index]
	var new_position = logical_mouse - drag_pivot_offset
	area.position = new_position
	if animation_data[current_animation].has(current_frame):
		var frame_data = animation_data[current_animation][current_frame]
		if frame_data.hitboxes_data.size() > selected_hitbox_index:
			frame_data.hitboxes_data[selected_hitbox_index]["position"] = {
				"x": new_position.x,
				"y": new_position.y
			}
	if drag_prev_state != null:
		drag_prev_state.data.new_position = new_position
	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

func _handle_hitbox_rotate_drag(logical_mouse: Vector2, delta: Vector2):
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return
	var area = hitbox_areas[selected_hitbox_index]
	var center = area.position
	var start_angle = (drag_start_pos - center).angle()
	var current_angle = (logical_mouse - center).angle()
	var rotation_delta = current_angle - start_angle
	var new_rotation = drag_start_value + rotation_delta
	area.rotation = new_rotation
	if animation_data[current_animation].has(current_frame):
		var frame_data = animation_data[current_animation][current_frame]
		if frame_data.hitboxes_data.size() > selected_hitbox_index:
			frame_data.hitboxes_data[selected_hitbox_index]["rotation"] = new_rotation
	if drag_prev_state != null:
		drag_prev_state.data.new_rotation = new_rotation
	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

func _handle_hitbox_scale_drag(logical_mouse: Vector2, delta: Vector2):
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return
	var area = hitbox_areas[selected_hitbox_index]
	var shape_node = area.get_child(0)
	if not shape_node or not (shape_node is CollisionShape2D):
		return
	var center = area.position
	var start_distance = (drag_start_pos - center).length()
	var current_distance = (logical_mouse - center).length()
	if start_distance > 0:
		var scale_factor = current_distance / start_distance
		var new_scale = drag_start_value * scale_factor
		new_scale = Vector2(max(0.1, new_scale.x), max(0.1, new_scale.y))
		area.scale = new_scale
		if animation_data[current_animation].has(current_frame):
			var frame_data = animation_data[current_animation][current_frame]
			if frame_data.hitboxes_data.size() > selected_hitbox_index:
				frame_data.hitboxes_data[selected_hitbox_index]["scale"] = {
					"x": new_scale.x,
					"y": new_scale.y
				}
		if drag_prev_state != null:
			drag_prev_state.data.new_scale = new_scale
		_update_hitbox_property_panel()
		_draw_node.queue_redraw()

# 8方向缩放拖拽：拉伸一边时对边固定，边缘跟手
func _handle_hitbox_resize_drag(_logical_mouse: Vector2, delta_inc: Vector2):
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return
	var area = hitbox_areas[selected_hitbox_index]
	var shape_node = area.get_child(0) if area.get_child_count() > 0 else null
	if not shape_node or not (shape_node is CollisionShape2D):
		return

	# 将增量转到受击框的本地坐标系（未缩放、未旋转）
	var local_delta = delta_inc.rotated(-area.rotation)
	# 除以 area.scale，使 shape.size 的变化量对应视觉上的鼠标移动
	var shape_delta = Vector2(
		local_delta.x / max(area.scale.x, 0.001),
		local_delta.y / max(area.scale.y, 0.001)
	)

	if shape_node.shape is RectangleShape2D:
		var old_size = shape_node.shape.size
		var new_size = old_size

		# 根据手柄方向修改尺寸（增量方式，使用 shape_delta 确保跟手）
		match current_mouse_mode:
			MouseMode.RESIZE_HITBOX_N:
				new_size.y = max(1.0, old_size.y - shape_delta.y)
			MouseMode.RESIZE_HITBOX_S:
				new_size.y = max(1.0, old_size.y + shape_delta.y)
			MouseMode.RESIZE_HITBOX_E:
				new_size.x = max(1.0, old_size.x + shape_delta.x)
			MouseMode.RESIZE_HITBOX_W:
				new_size.x = max(1.0, old_size.x - shape_delta.x)
			MouseMode.RESIZE_HITBOX_NE:
				new_size.x = max(1.0, old_size.x + shape_delta.x)
				new_size.y = max(1.0, old_size.y - shape_delta.y)
			MouseMode.RESIZE_HITBOX_NW:
				new_size.x = max(1.0, old_size.x - shape_delta.x)
				new_size.y = max(1.0, old_size.y - shape_delta.y)
			MouseMode.RESIZE_HITBOX_SE:
				new_size.x = max(1.0, old_size.x + shape_delta.x)
				new_size.y = max(1.0, old_size.y + shape_delta.y)
			MouseMode.RESIZE_HITBOX_SW:
				new_size.x = max(1.0, old_size.x - shape_delta.x)
				new_size.y = max(1.0, old_size.y + shape_delta.y)

		if new_size == old_size:
			return

		var size_delta = new_size - old_size

		# 计算中心点移动量：对边固定，中心向拉的方向移动拉伸量的一半
		# center_offset 在受击框本地坐标系中，需要乘以 area.scale 才能在视觉上正确
		var center_offset = Vector2.ZERO
		match current_mouse_mode:
			MouseMode.RESIZE_HITBOX_N:
				center_offset = Vector2(0, -size_delta.y * area.scale.y / 2.0)
			MouseMode.RESIZE_HITBOX_S:
				center_offset = Vector2(0, size_delta.y * area.scale.y / 2.0)
			MouseMode.RESIZE_HITBOX_E:
				center_offset = Vector2(size_delta.x * area.scale.x / 2.0, 0)
			MouseMode.RESIZE_HITBOX_W:
				center_offset = Vector2(-size_delta.x * area.scale.x / 2.0, 0)
			MouseMode.RESIZE_HITBOX_NE:
				center_offset = Vector2(size_delta.x * area.scale.x / 2.0, -size_delta.y * area.scale.y / 2.0)
			MouseMode.RESIZE_HITBOX_NW:
				center_offset = Vector2(-size_delta.x * area.scale.x / 2.0, -size_delta.y * area.scale.y / 2.0)
			MouseMode.RESIZE_HITBOX_SE:
				center_offset = Vector2(size_delta.x * area.scale.x / 2.0, size_delta.y * area.scale.y / 2.0)
			MouseMode.RESIZE_HITBOX_SW:
				center_offset = Vector2(-size_delta.x * area.scale.x / 2.0, size_delta.y * area.scale.y / 2.0)

		# 应用中心点移动（旋转到受击框当前方向）
		if center_offset != Vector2.ZERO:
			area.position += center_offset.rotated(area.rotation)

		# 应用新的形状大小
		var new_shape = RectangleShape2D.new()
		new_shape.size = new_size
		shape_node.shape = new_shape

		# 更新 drag_prev_state（用于撤销）
		if drag_prev_state != null:
			drag_prev_state.data["new_size"] = new_size
			drag_prev_state.data["new_position"] = area.position

		# 保存到动画数据
		if animation_data[current_animation].has(current_frame):
			var frame_data = animation_data[current_animation][current_frame]
			if frame_data.hitboxes_data.size() > selected_hitbox_index:
				if not frame_data.hitboxes_data[selected_hitbox_index].has("size"):
					frame_data.hitboxes_data[selected_hitbox_index]["size"] = {}
				frame_data.hitboxes_data[selected_hitbox_index]["size"]["width"] = new_size.x
				frame_data.hitboxes_data[selected_hitbox_index]["size"]["height"] = new_size.y
				frame_data.hitboxes_data[selected_hitbox_index]["position"]["x"] = area.position.x
				frame_data.hitboxes_data[selected_hitbox_index]["position"]["y"] = area.position.y

	elif shape_node.shape is CircleShape2D:
		var old_radius = shape_node.shape.radius
		var dist = delta_inc.length() / max(area.scale.x, area.scale.y, 0.001)
		var current_mouse = _screen_to_logical(get_viewport().get_mouse_position())
		var dir_to_center = (area.position - current_mouse).normalized()
		var move_dir = delta_inc.normalized()
		var sign = 1.0 if dir_to_center.dot(move_dir) > 0 else -1.0
		var new_radius = max(0.5, old_radius + sign * dist)
		if new_radius != old_radius:
			var new_shape = CircleShape2D.new()
			new_shape.radius = new_radius
			shape_node.shape = new_shape
			if drag_prev_state != null:
				drag_prev_state.data["new_radius"] = new_radius
			if animation_data[current_animation].has(current_frame):
				var frame_data = animation_data[current_animation][current_frame]
				if frame_data.hitboxes_data.size() > selected_hitbox_index:
					frame_data.hitboxes_data[selected_hitbox_index]["radius"] = new_radius

	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

# ==========================================
# 键盘输入
# ==========================================
func _input(event: InputEvent):
	if not visible:
		return

	# 快捷键处理
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				_on_tool_selected(CanvasTool.SELECT)
				get_viewport().set_input_as_handled()
				return
			KEY_H:
				_on_tool_selected(CanvasTool.PAN)
				get_viewport().set_input_as_handled()
				return
			KEY_0:
				if event.ctrl_pressed:
					_on_reset_view_pressed()
					get_viewport().set_input_as_handled()
					return

		if event.ctrl_pressed:
			if event.keycode == KEY_S:
				_on_save_pressed()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_Z:
				_on_undo_pressed()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_Y:
				_on_redo_pressed()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_C:
				_on_copy_pressed()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_V:
				_on_paste_pressed()
				get_viewport().set_input_as_handled()
				return

		if event.keycode == KEY_TAB:
			if hitbox_areas.size() > 0:
				selected_hitbox_index = (selected_hitbox_index + 1) % hitbox_areas.size()
				_refresh_hitbox_list()
				_update_hitbox_property_panel()
				_draw_node.queue_redraw()
			get_viewport().set_input_as_handled()
			return

		if selected_hitbox_index >= 0 and selected_hitbox_index < hitbox_areas.size():
			var area = hitbox_areas[selected_hitbox_index]
			var move_delta = Vector2.ZERO
			var speed = keyboard_move_speed
			if event.shift_pressed:
				speed = keyboard_fast_move_speed
			elif event.ctrl_pressed:
				speed = keyboard_slow_move_speed

			match event.keycode:
				KEY_UP:
					move_delta.y = -speed
				KEY_DOWN:
					move_delta.y = speed
				KEY_LEFT:
					move_delta.x = -speed
				KEY_RIGHT:
					move_delta.x = speed
				_:
					return

			if move_delta != Vector2.ZERO:
				var prev_pos = area.position
				var new_position = area.position + move_delta
				_record_action("move_hitbox", {
					"index": selected_hitbox_index,
					"prev_position": prev_pos,
					"new_position": new_position
				})
				area.position = new_position
				if animation_data[current_animation].has(current_frame):
					var frame_data = animation_data[current_animation][current_frame]
					if frame_data.hitboxes_data.size() > selected_hitbox_index:
						frame_data.hitboxes_data[selected_hitbox_index]["position"] = {
							"x": new_position.x,
							"y": new_position.y
						}
				is_data_modified = true
				_update_hitbox_property_panel()
				_draw_node.queue_redraw()
				get_viewport().set_input_as_handled()

# ==========================================
# 碰撞检测辅助
# ==========================================
func _is_point_near_anchor(point: Vector2, threshold: float = -1.0) -> bool:
	if threshold < 0:
		threshold = (anchor_viz_size / 2.0 + 5.0) / _canvas_zoom
	var anchor = _get_current_anchor()
	return point.distance_to(anchor) < threshold

func _get_current_anchor() -> Vector2:
	if animation_data.has(current_animation) and animation_data[current_animation].has(current_frame):
		return animation_data[current_animation][current_frame].anchor_point
	return Vector2.ZERO

func _set_current_anchor(anchor: Vector2):
	if not animation_data[current_animation].has(current_frame):
		animation_data[current_animation][current_frame] = FrameData.new()
	animation_data[current_animation][current_frame].anchor_point = anchor
	# 如果当前使用全局锚点，同步更新全局锚点值和所有帧
	var use_global_anchor = animation_global_anchors.get(current_animation, null) != null
	if use_global_anchor:
		animation_global_anchors[current_animation] = anchor
		for frame_index in animation_data[current_animation]:
			animation_data[current_animation][frame_index].anchor_point = anchor

func _get_rotation_handle_position(index: int) -> Vector2:
	if index < 0 or index >= hitbox_areas.size():
		return Vector2.ZERO
	var area = hitbox_areas[index]
	var shape_node = area.get_child(0)
	if not shape_node or not (shape_node is CollisionShape2D):
		return Vector2.ZERO
	var handle_distance = 60.0
	if shape_node.shape is RectangleShape2D:
		var size = shape_node.shape.size * area.scale
		handle_distance = max(size.x, size.y) * 0.8
	elif shape_node.shape is CircleShape2D:
		var radius = shape_node.shape.radius * area.scale.x
		handle_distance = radius * 1.2
	handle_distance = max(handle_distance, 60.0)
	return area.position + Vector2(handle_distance, 0).rotated(area.rotation)

# 8方向缩放手柄位置计算
func _get_resize_handle_positions(index: int) -> Dictionary:
	"""返回8方向手柄的逻辑坐标字典 {方向名: Vector2}"""
	var result = {}
	if index < 0 or index >= hitbox_areas.size():
		return result
	var area = hitbox_areas[index]
	var shape_node = area.get_child(0) if area.get_child_count() > 0 else null
	if not shape_node or not (shape_node is CollisionShape2D):
		return result
	var half_w: float = 0.0
	var half_h: float = 0.0
	if shape_node.shape is RectangleShape2D:
		half_w = shape_node.shape.size.x * area.scale.x / 2.0
		half_h = shape_node.shape.size.y * area.scale.y / 2.0
	elif shape_node.shape is CircleShape2D:
		var r = shape_node.shape.radius * max(area.scale.x, area.scale.y)
		half_w = r
		half_h = r
	var dirs = {
		"N": Vector2(0, -1),
		"S": Vector2(0, 1),
		"E": Vector2(1, 0),
		"W": Vector2(-1, 0),
		"NE": Vector2(1, -1),
		"NW": Vector2(-1, -1),
		"SE": Vector2(1, 1),
		"SW": Vector2(-1, 1)
	}
	for dir_name in dirs:
		var offset = Vector2(dirs[dir_name].x * half_w, dirs[dir_name].y * half_h).rotated(area.rotation)
		result[dir_name] = area.position + offset
	return result

func _get_clicked_handle(point: Vector2):
	# 旋转手柄触控范围与绘制半径一致：handle_size * 0.8
	var rot_threshold = handle_size * 0.8 / _canvas_zoom
	# 优先检测旋转手柄（圆形手柄用距离检测）
	for i in range(hitbox_areas.size()):
		var rot_handle_pos = _get_rotation_handle_position(i)
		if rot_handle_pos != Vector2.ZERO and point.distance_to(rot_handle_pos) < rot_threshold:
			return {"index": i, "type": MouseMode.ROTATE_HITBOX}
	# 检测8方向缩放手柄（仅选中受击框显示）
	# 检测范围与绘制的手柄大小一致（handle_size * 0.7 绘制方框）
	var resize_threshold = handle_size * 0.7 / _canvas_zoom
	for i in range(hitbox_areas.size()):
		if i != selected_hitbox_index:
			continue
		var resize_handles = _get_resize_handle_positions(i)
		for dir_name in resize_handles:
			var handle_pos = resize_handles[dir_name]
			if point.distance_to(handle_pos) < resize_threshold:
				match dir_name:
					"N": return {"index": i, "type": MouseMode.RESIZE_HITBOX_N}
					"S": return {"index": i, "type": MouseMode.RESIZE_HITBOX_S}
					"E": return {"index": i, "type": MouseMode.RESIZE_HITBOX_E}
					"W": return {"index": i, "type": MouseMode.RESIZE_HITBOX_W}
					"NE": return {"index": i, "type": MouseMode.RESIZE_HITBOX_NE}
					"NW": return {"index": i, "type": MouseMode.RESIZE_HITBOX_NW}
					"SE": return {"index": i, "type": MouseMode.RESIZE_HITBOX_SE}
					"SW": return {"index": i, "type": MouseMode.RESIZE_HITBOX_SW}
	# 检测位置手柄（圆形用距离检测，与绘制半径 handle_size * 1.2 一致）
	var pos_threshold = handle_size * 1.2 / _canvas_zoom
	for i in range(hitbox_areas.size()):
		var area = hitbox_areas[i]
		if point.distance_to(area.position) < pos_threshold:
			return {"index": i, "type": MouseMode.MOVE_HITBOX}
	return null

func _get_clicked_hitbox(point: Vector2) -> int:
	if selected_hitbox_index >= 0 and selected_hitbox_index < hitbox_areas.size():
		var area = hitbox_areas[selected_hitbox_index]
		if _is_point_in_hitbox(point, area):
			return selected_hitbox_index
	for i in range(hitbox_areas.size()):
		if i == selected_hitbox_index:
			continue
		var area = hitbox_areas[i]
		if _is_point_in_hitbox(point, area):
			return i
	return -1

func _is_point_in_hitbox(point: Vector2, area: Area2D) -> bool:
	var shape_node = area.get_child(0)
	if not shape_node or not (shape_node is CollisionShape2D):
		return false
	var local_point = point - area.position
	local_point = local_point.rotated(-area.rotation) / area.scale
	if shape_node.shape is RectangleShape2D:
		var size = shape_node.shape.size
		var half_size = size * 0.5
		return abs(local_point.x) <= half_size.x and abs(local_point.y) <= half_size.y
	elif shape_node.shape is CircleShape2D:
		return local_point.length() <= shape_node.shape.radius
	return false

func _get_current_hitbox_value(index: int, mode: MouseMode):
	if index < 0 or index >= hitbox_areas.size():
		return null
	var area = hitbox_areas[index]
	match mode:
		MouseMode.MOVE_HITBOX:
			return area.position
		MouseMode.ROTATE_HITBOX:
			return area.rotation
		MouseMode.SCALE_HITBOX:
			return area.scale
		MouseMode.RESIZE_HITBOX_N, MouseMode.RESIZE_HITBOX_S, MouseMode.RESIZE_HITBOX_E, MouseMode.RESIZE_HITBOX_W,\
		MouseMode.RESIZE_HITBOX_NE, MouseMode.RESIZE_HITBOX_NW, MouseMode.RESIZE_HITBOX_SE, MouseMode.RESIZE_HITBOX_SW:
			return null  # resize 模式不从这里获取值，直接操作形状
	return null

# ==========================================
# 动画抽象接口（兼容 AnimatedSprite2D 和 AnimationPlayer）
# ==========================================
func _get_animation_names() -> PackedStringArray:
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap:
			var names = ap.get_animation_list()
			print("[frame] _get_animation_names: AnimationPlayer, anims=%s" % [str(names)])
			return names
	if animated_sprite and animated_sprite.sprite_frames:
		var names = animated_sprite.sprite_frames.get_animation_names()
		print("[frame] _get_animation_names: AnimatedSprite2D, anims=%s" % [str(names)])
		return names
	print("[frame] _get_animation_names: empty")
	return PackedStringArray()

func _get_frame_count(anim_name: String) -> int:
	if _is_anim_player_entity:
		var preview = _canvas.get_node_or_null("EntityPreview")
		if preview:
			var ap = _find_animation_player(preview)
			if ap and ap.has_animation(anim_name):
				var anim = ap.get_animation(anim_name)
				var count = int(anim.length * ANIM_FPS)
				print("[frame] _get_frame_count(%s)=%d" % [anim_name, count])
				return count
	elif animated_sprite and animated_sprite.sprite_frames:
		var count = animated_sprite.sprite_frames.get_frame_count(anim_name)
		print("[frame] _get_frame_count(%s)=%d (sprite)" % [anim_name, count])
		return count
	print("[frame] _get_frame_count(%s)=0" % anim_name)
	return 0

func _set_anim_frame(anim_name: String, frame_idx: int):
	if _is_anim_player_entity:
		var preview = _canvas.get_node_or_null("EntityPreview")
		if preview:
			var ap = _find_animation_player(preview)
			if ap:
				ap.stop()
				if ap.has_animation(anim_name):
					ap.play(anim_name)
					ap.seek(frame_idx / ANIM_FPS, true)
					ap.stop(false)
					print("[frame] _set_anim_frame(%s, %d): seek OK" % [anim_name, frame_idx])
				else:
					print("[frame] _set_anim_frame(%s, %d): anim not found" % [anim_name, frame_idx])
		return
	if animated_sprite:
		animated_sprite.animation = anim_name
		animated_sprite.frame = frame_idx

func _play_anim(anim_name: String = ""):
	if _is_anim_player_entity:
		var preview = _canvas.get_node_or_null("EntityPreview")
		if preview:
			var ap = _find_animation_player(preview)
			if ap and ap.has_animation(anim_name if anim_name != "" else current_animation):
				ap.play(anim_name if anim_name != "" else current_animation)
		return
	if animated_sprite:
		if anim_name != "":
			animated_sprite.play(anim_name)
		else:
			animated_sprite.play()

func _stop_anim():
	if _is_anim_player_entity:
		var preview = _canvas.get_node_or_null("EntityPreview")
		if preview:
			var ap = _find_animation_player(preview)
			if ap:
				ap.stop()
		return
	if animated_sprite:
		animated_sprite.stop()

func _get_current_anim_frame() -> int:
	if _is_anim_player_entity:
		var preview = _canvas.get_node_or_null("EntityPreview")
		if preview:
			var ap = _find_animation_player(preview)
			if ap and ap.is_playing():
				return int(ap.current_animation_position * ANIM_FPS)
		return current_frame
	if animated_sprite:
		return animated_sprite.frame
	return 0

func _get_current_anim_name() -> String:
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap:
			return ap.current_animation
		return current_animation
	if animated_sprite:
		return animated_sprite.animation
	return ""

# ==========================================
# 动画与帧控制
# ==========================================
func _setup_animations():
	if not animated_sprite or not animated_sprite.sprite_frames:
		return

	_anim_selector.clear()
	var sprite_frames = animated_sprite.sprite_frames
	var animations = sprite_frames.get_animation_names()

	for anim in animations:
		_anim_selector.add_item(anim)
		if not animation_data.has(anim):
			animation_data[anim] = {}
		if not animation_global_anchors.has(anim):
			animation_global_anchors[anim] = null

	if animations.size() > 0:
		current_animation = animations[0]
		animated_sprite.animation = current_animation
		animated_sprite.frame = 0
		_update_frame_selector()
		_load_current_frame_data()
		_update_anchor_editor()
		_update_hitbox_property_panel()

func _setup_animations_from_entity():
	_anim_selector.clear()
	var animations = _get_animation_names()

	for anim in animations:
		_anim_selector.add_item(anim)
		if not animation_data.has(anim):
			animation_data[anim] = {}
		if not animation_global_anchors.has(anim):
			animation_global_anchors[anim] = null

	if animations.size() > 0:
		current_animation = animations[0]
		_set_anim_frame(current_animation, 0)
		_update_frame_selector()
		_load_current_frame_data()
		_update_anchor_editor()
		_update_hitbox_property_panel()

func _update_frame_selector():
	if _is_anim_player_entity:
		var frame_count = _get_frame_count(current_animation)
		_frame_selector.max_value = max(0, frame_count - 1)
		_frame_selector.value = current_frame
		_frame_info_label.text = "帧: %d/%d" % [current_frame + 1, frame_count]
		return
	
	if not animated_sprite or not animated_sprite.sprite_frames:
		return
	var sprite_frames = animated_sprite.sprite_frames
	var frame_count = sprite_frames.get_frame_count(current_animation)
	_frame_selector.max_value = frame_count - 1
	_frame_selector.value = animated_sprite.frame
	_frame_info_label.text = "帧: %d/%d" % [animated_sprite.frame + 1, frame_count]
	current_frame = animated_sprite.frame

func _load_current_frame_data():
	if not current_animation in animation_data:
		animation_data[current_animation] = {}
	
	_prev_hitbox_vis.clear()

	var use_global_anchor = animation_global_anchors.get(current_animation, null) != null

	if use_global_anchor:
		var global_anchor = animation_global_anchors[current_animation]
		if not animation_data[current_animation].has(current_frame):
			animation_data[current_animation][current_frame] = FrameData.new()
		var frame_data = animation_data[current_animation][current_frame]
		frame_data.frame_index = current_frame
		frame_data.anchor_point = global_anchor
		_init_frame_hitbox_data(frame_data)
	else:
		if not animation_data[current_animation].has(current_frame):
			animation_data[current_animation][current_frame] = FrameData.new()
			var frame_data = animation_data[current_animation][current_frame]
			frame_data.frame_index = current_frame
			frame_data.anchor_point = Vector2.ZERO
			_update_hitbox_data_from_scene(frame_data)
		else:
			var frame_data = animation_data[current_animation][current_frame]
			_restore_hitbox_shapes(frame_data)

func _init_frame_hitbox_data(frame_data: FrameData):
	_prev_hitbox_vis.clear()
	if frame_data.hitboxes_data.size() == 0:
		_update_hitbox_data_from_scene(frame_data)
	else:
		_restore_hitbox_shapes(frame_data)

func _update_hitbox_data_from_scene(frame_data: FrameData):
	frame_data.hitboxes_data.clear()
	for area in hitbox_areas:
		var shape_node = area.get_child(0)
		if shape_node is CollisionShape2D:
			var shape_data = {
				"area_name": area.name,
				"position": {"x": area.position.x, "y": area.position.y},
				"rotation": area.rotation,
				"scale": {"x": area.scale.x, "y": area.scale.y},
				"visible": area.visible
			}
			if shape_node.shape is RectangleShape2D:
				shape_data["shape_type"] = "rectangle"
				shape_data["size"] = {
					"width": shape_node.shape.size.x,
					"height": shape_node.shape.size.y
				}
			elif shape_node.shape is CircleShape2D:
				shape_data["shape_type"] = "circle"
				shape_data["radius"] = shape_node.shape.radius
			frame_data.hitboxes_data.append(shape_data)

func _restore_hitbox_shapes(frame_data: FrameData):
	while frame_data.hitboxes_data.size() < hitbox_areas.size():
		frame_data.hitboxes_data.append({})

	for i in range(hitbox_areas.size()):
		var area = hitbox_areas[i]
		var hitbox_data = frame_data.hitboxes_data[i]

		if hitbox_data.has("position"):
			area.position = Vector2(
				hitbox_data["position"].get("x", area.position.x),
				hitbox_data["position"].get("y", area.position.y)
			)
		else:
			hitbox_data["position"] = {"x": area.position.x, "y": area.position.y}

		if hitbox_data.has("rotation"):
			area.rotation = hitbox_data.get("rotation", area.rotation)
		else:
			hitbox_data["rotation"] = area.rotation

		if hitbox_data.has("scale"):
			var scale_data = hitbox_data["scale"]
			area.scale = Vector2(
				scale_data.get("x", area.scale.x),
				scale_data.get("y", area.scale.y)
			)
		else:
			hitbox_data["scale"] = {"x": area.scale.x, "y": area.scale.y}

		var shape_node = area.get_child(0)
		if shape_node is CollisionShape2D:
			if not hitbox_data.has("shape_type"):
				if shape_node.shape is RectangleShape2D:
					hitbox_data["shape_type"] = "rectangle"
					hitbox_data["size"] = {
						"width": shape_node.shape.size.x,
						"height": shape_node.shape.size.y
					}
				elif shape_node.shape is CircleShape2D:
					hitbox_data["shape_type"] = "circle"
					hitbox_data["radius"] = shape_node.shape.radius

			if hitbox_data["shape_type"] == "rectangle":
				var new_shape = RectangleShape2D.new()
				if hitbox_data.has("size"):
					var size_data = hitbox_data["size"]
					new_shape.size = Vector2(
						size_data.get("width", 10),
						size_data.get("height", 10)
					)
				else:
					new_shape.size = Vector2(10, 10)
				shape_node.shape = new_shape
			elif hitbox_data["shape_type"] == "circle":
				var new_shape = CircleShape2D.new()
				new_shape.radius = hitbox_data.get("radius", 5)
				shape_node.shape = new_shape
		
		# 恢复可见性
		var is_visible = hitbox_data.get("visible", true)
		area.visible = is_visible
		_prev_hitbox_vis[i] = is_visible

func _update_anchor_editor():
	if not current_animation in animation_data:
		return

	var use_global_anchor = animation_global_anchors.get(current_animation, null) != null

	if use_global_anchor:
		var global_anchor = animation_global_anchors[current_animation]
		_anchor_x_spinbox.value = global_anchor.x
		_anchor_y_spinbox.value = global_anchor.y
		_apply_anchor_all_button.text = "取消全局锚点"
		_apply_anchor_all_button.tooltip_text = "取消全局锚点设置，恢复为每帧独立锚点"
	else:
		var frame_data = animation_data[current_animation].get(current_frame, null)
		if frame_data:
			_anchor_x_spinbox.value = frame_data.anchor_point.x
			_anchor_y_spinbox.value = frame_data.anchor_point.y
		_apply_anchor_all_button.text = "设为全局锚点"
		_apply_anchor_all_button.tooltip_text = "将当前锚点设置应用到当前动画的所有帧"

func _on_animation_selected(index: int):
	if is_data_modified and current_animation != "":
		_save_current_frame_state()
		_auto_save_frame_data()

	current_animation = _anim_selector.get_item_text(index)
	print("[frame] _on_animation_selected: anim=%s" % current_animation)
	
	if _is_anim_player_entity:
		_set_anim_frame(current_animation, 0)
		current_frame = 0
	else:
		animated_sprite.animation = current_animation
		animated_sprite.frame = 0

	_update_frame_selector()
	_load_current_frame_data()
	_update_anchor_editor()
	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

func _on_frame_changed(value: float):
	if is_data_modified and current_animation != "":
		_save_current_frame_state()
		_auto_save_frame_data()

	current_frame = int(value)
	print("[frame] _on_frame_changed: frame=%d" % current_frame)
	
	if _is_anim_player_entity:
		_set_anim_frame(current_animation, current_frame)
	else:
		animated_sprite.frame = current_frame
	
	_frame_info_label.text = "帧: %d/%d" % [current_frame + 1, int(_frame_selector.max_value) + 1]

	_load_current_frame_data()
	_update_anchor_editor()
	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

func _on_prev_frame():
	var new_frame = int(_frame_selector.value) - 1
	if new_frame >= 0:
		_frame_selector.value = new_frame

func _on_next_frame():
	var new_frame = int(_frame_selector.value) + 1
	if new_frame <= _frame_selector.max_value:
		_frame_selector.value = new_frame

func _process(_delta: float):
	# 播放动画时同步帧数据显示
	if not _is_playing:
		return
	
	if _is_anim_player_entity:
		var sprite_frame = _get_current_anim_frame()
		if sprite_frame != current_frame:
			current_frame = sprite_frame
			_frame_selector.set_value_no_signal(current_frame)
			var frame_count = _get_frame_count(current_animation)
			_frame_info_label.text = "帧: %d/%d" % [current_frame + 1, frame_count]
			_load_current_frame_data()
			_update_anchor_editor()
			_update_hitbox_property_panel()
			_draw_node.queue_redraw()
		return
	
	if not animated_sprite:
		return

	var sprite_frame = animated_sprite.frame
	if sprite_frame != current_frame:
		current_frame = sprite_frame
		# 静默更新UI，不触发auto_save
		_frame_selector.set_value_no_signal(current_frame)
		var sprite_frames = animated_sprite.sprite_frames
		var frame_count = sprite_frames.get_frame_count(current_animation)
		_frame_info_label.text = "帧: %d/%d" % [current_frame + 1, frame_count]
		_load_current_frame_data()
		_update_anchor_editor()
		_update_hitbox_property_panel()
		_draw_node.queue_redraw()

func _on_play_animation():
	if _is_anim_player_entity:
		if is_data_modified and current_animation != "":
			_save_current_frame_state()
		_play_anim()
		_is_playing = true
		return
	if animated_sprite:
		# 先保存当前帧修改
		if is_data_modified and current_animation != "":
			_save_current_frame_state()
		animated_sprite.play()
		_is_playing = true

func _on_stop_animation():
	if _is_anim_player_entity:
		_stop_anim()
		_is_playing = false
		current_frame = _get_current_anim_frame()
		_frame_selector.value = current_frame
		_load_current_frame_data()
		_update_anchor_editor()
		_update_hitbox_property_panel()
		_draw_node.queue_redraw()
		return
	if animated_sprite:
		animated_sprite.stop()
		_is_playing = false
		# 停止后同步当前帧显示
		current_frame = animated_sprite.frame
		_frame_selector.value = current_frame
		_load_current_frame_data()
		_update_anchor_editor()
		_update_hitbox_property_panel()
		_draw_node.queue_redraw()

func _on_anchor_changed(value: float, axis: String):
	var use_global_anchor = animation_global_anchors.get(current_animation, null) != null

	if use_global_anchor:
		var anchor = animation_global_anchors[current_animation]
		if anchor == null:
			anchor = Vector2.ZERO
			animation_global_anchors[current_animation] = anchor
		if axis == "x":
			anchor.x = value
		else:
			anchor.y = value
		# Vector2 是值类型，修改后必须写回字典
		animation_global_anchors[current_animation] = anchor
		for frame_index in animation_data[current_animation]:
			var frame_data = animation_data[current_animation][frame_index]
			frame_data.anchor_point = anchor
	else:
		if animation_data[current_animation].has(current_frame):
			var frame_data = animation_data[current_animation][current_frame]
			var anchor = frame_data.anchor_point
			if axis == "x":
				anchor.x = value
			else:
				anchor.y = value
			frame_data.anchor_point = anchor

	is_data_modified = true
	_draw_node.queue_redraw()

func _on_apply_anchor_all_pressed():
	var use_global_anchor = animation_global_anchors.get(current_animation, null) != null

	if use_global_anchor:
		animation_global_anchors[current_animation] = null
	else:
		var current_anchor = Vector2.ZERO
		if animation_data[current_animation].has(current_frame):
			var frame_data = animation_data[current_animation][current_frame]
			current_anchor = frame_data.anchor_point
		animation_global_anchors[current_animation] = current_anchor
		for frame_index in animation_data[current_animation]:
			var frame_data = animation_data[current_animation][frame_index]
			frame_data.anchor_point = current_anchor

	is_data_modified = true
	save_frame_data()
	_update_anchor_editor()
	_draw_node.queue_redraw()

# ==========================================
# 受击框属性面板
# ==========================================
func _update_hitbox_property_panel():
	# 断开信号避免循环
	_hitbox_pos_x_spinbox.value_changed.disconnect(_on_hitbox_position_changed)
	_hitbox_pos_y_spinbox.value_changed.disconnect(_on_hitbox_position_changed)
	_hitbox_rot_spinbox.value_changed.disconnect(_on_hitbox_rotation_changed)
	_hitbox_size_x_spinbox.value_changed.disconnect(_on_hitbox_size_changed)
	_hitbox_size_y_spinbox.value_changed.disconnect(_on_hitbox_size_changed)
	_hitbox_radius_spinbox.value_changed.disconnect(_on_hitbox_radius_changed)
	_hitbox_visible_checkbox.toggled.disconnect(_on_hitbox_visible_toggled)

	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		_hitbox_pos_x_spinbox.value = 0
		_hitbox_pos_y_spinbox.value = 0
		_hitbox_rot_spinbox.value = 0
		_hitbox_size_x_spinbox.value = 0
		_hitbox_size_y_spinbox.value = 0
		_hitbox_radius_spinbox.value = 0
		_hitbox_visible_checkbox.button_pressed = true
		_hide_all_size_editors()
		_reconnect_hitbox_signals()
		return

	var area = hitbox_areas[selected_hitbox_index]
	var shape_node = area.get_child(0) if area.get_child_count() > 0 else null

	_hitbox_pos_x_spinbox.value = area.position.x
	_hitbox_pos_y_spinbox.value = area.position.y
	_hitbox_rot_spinbox.value = rad_to_deg(area.rotation)

	# 读取可见性
	var is_visible = true
	if animation_data.has(current_animation) and animation_data[current_animation].has(current_frame):
		var fd = animation_data[current_animation][current_frame]
		if fd.hitboxes_data.size() > selected_hitbox_index:
			is_visible = fd.hitboxes_data[selected_hitbox_index].get("visible", true)
	_hitbox_visible_checkbox.button_pressed = is_visible

	if shape_node and shape_node is CollisionShape2D:
		if shape_node.shape is RectangleShape2D:
			_show_rectangle_size_editor()
			_hitbox_size_x_spinbox.value = shape_node.shape.size.x
			_hitbox_size_y_spinbox.value = shape_node.shape.size.y
		elif shape_node.shape is CircleShape2D:
			_show_circle_size_editor()
			_hitbox_radius_spinbox.value = shape_node.shape.radius
		else:
			_hide_all_size_editors()
	else:
		_hide_all_size_editors()

	_reconnect_hitbox_signals()

func _reconnect_hitbox_signals():
	_hitbox_pos_x_spinbox.value_changed.connect(_on_hitbox_position_changed.bind("x"))
	_hitbox_pos_y_spinbox.value_changed.connect(_on_hitbox_position_changed.bind("y"))
	_hitbox_rot_spinbox.value_changed.connect(_on_hitbox_rotation_changed)
	_hitbox_size_x_spinbox.value_changed.connect(_on_hitbox_size_changed.bind("x"))
	_hitbox_size_y_spinbox.value_changed.connect(_on_hitbox_size_changed.bind("y"))
	_hitbox_radius_spinbox.value_changed.connect(_on_hitbox_radius_changed)
	_hitbox_visible_checkbox.toggled.connect(_on_hitbox_visible_toggled)

func _show_rectangle_size_editor():
	# 隐藏半径编辑器，显示宽高编辑器
	_hitbox_size_x_spinbox.get_parent().visible = true
	_hitbox_size_y_spinbox.get_parent().visible = true
	_hitbox_radius_spinbox.get_parent().visible = false

func _show_circle_size_editor():
	_hitbox_size_x_spinbox.get_parent().visible = false
	_hitbox_size_y_spinbox.get_parent().visible = false
	_hitbox_radius_spinbox.get_parent().visible = true

func _hide_all_size_editors():
	_hitbox_size_x_spinbox.get_parent().visible = false
	_hitbox_size_y_spinbox.get_parent().visible = false
	_hitbox_radius_spinbox.get_parent().visible = false

func _on_hitbox_position_changed(value: float, axis: String):
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return
	var area = hitbox_areas[selected_hitbox_index]
	var new_pos = area.position
	if axis == "x":
		new_pos.x = value
	else:
		new_pos.y = value
	area.position = new_pos
	if animation_data[current_animation].has(current_frame):
		var frame_data = animation_data[current_animation][current_frame]
		if frame_data.hitboxes_data.size() > selected_hitbox_index:
			if not frame_data.hitboxes_data[selected_hitbox_index].has("position"):
				frame_data.hitboxes_data[selected_hitbox_index]["position"] = {}
			frame_data.hitboxes_data[selected_hitbox_index]["position"]["x"] = new_pos.x
			frame_data.hitboxes_data[selected_hitbox_index]["position"]["y"] = new_pos.y
	is_data_modified = true
	_draw_node.queue_redraw()

func _on_hitbox_rotation_changed(value: float):
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return
	var area = hitbox_areas[selected_hitbox_index]
	area.rotation = deg_to_rad(value)
	if animation_data[current_animation].has(current_frame):
		var frame_data = animation_data[current_animation][current_frame]
		if frame_data.hitboxes_data.size() > selected_hitbox_index:
			frame_data.hitboxes_data[selected_hitbox_index]["rotation"] = area.rotation
	is_data_modified = true
	_draw_node.queue_redraw()

func _on_hitbox_size_changed(value: float, axis: String):
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return
	var area = hitbox_areas[selected_hitbox_index]
	var shape_node = area.get_child(0)
	if shape_node and shape_node.shape is RectangleShape2D:
		var new_shape = RectangleShape2D.new()
		var current_size = shape_node.shape.size
		if axis == "x":
			new_shape.size = Vector2(value, current_size.y)
		else:
			new_shape.size = Vector2(current_size.x, value)
		shape_node.shape = new_shape
		if animation_data[current_animation].has(current_frame):
			var frame_data = animation_data[current_animation][current_frame]
			if frame_data.hitboxes_data.size() > selected_hitbox_index:
				if not frame_data.hitboxes_data[selected_hitbox_index].has("size"):
					frame_data.hitboxes_data[selected_hitbox_index]["size"] = {}
				frame_data.hitboxes_data[selected_hitbox_index]["size"]["width"] = new_shape.size.x
				frame_data.hitboxes_data[selected_hitbox_index]["size"]["height"] = new_shape.size.y
				frame_data.hitboxes_data[selected_hitbox_index]["shape_type"] = "rectangle"
		is_data_modified = true
		_draw_node.queue_redraw()

func _on_hitbox_radius_changed(value: float):
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return
	var area = hitbox_areas[selected_hitbox_index]
	var shape_node = area.get_child(0)
	if shape_node and shape_node.shape is CircleShape2D:
		var new_shape = CircleShape2D.new()
		new_shape.radius = value
		shape_node.shape = new_shape
		if animation_data[current_animation].has(current_frame):
			var frame_data = animation_data[current_animation][current_frame]
			if frame_data.hitboxes_data.size() > selected_hitbox_index:
				frame_data.hitboxes_data[selected_hitbox_index]["radius"] = value
				frame_data.hitboxes_data[selected_hitbox_index]["shape_type"] = "circle"
		is_data_modified = true
		_draw_node.queue_redraw()

func _on_hitbox_visible_toggled(pressed: bool):
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return
	if animation_data.has(current_animation) and animation_data[current_animation].has(current_frame):
		var frame_data = animation_data[current_animation][current_frame]
		if frame_data.hitboxes_data.size() > selected_hitbox_index:
			frame_data.hitboxes_data[selected_hitbox_index]["visible"] = pressed
			is_data_modified = true
	# 运行时同步可见性
	hitbox_areas[selected_hitbox_index].visible = pressed
	_draw_node.queue_redraw()

func _on_handle_size_changed(value: float):
	handle_size = value
	_handle_size_value_label.text = "%d px" % int(value)
	is_data_modified = true
	_draw_node.queue_redraw()

# ==========================================
# 受击框列表管理
# ==========================================
func _refresh_hitbox_list():
	_hitbox_list.clear()
	for i in range(hitbox_areas.size()):
		var area = hitbox_areas[i]
		var prefix = "● " if i == selected_hitbox_index else "○ "
		# 显示可见性状态
		var vis_status = ""
		if animation_data.has(current_animation) and animation_data[current_animation].has(current_frame):
			var fd = animation_data[current_animation][current_frame]
			if fd.hitboxes_data.size() > i:
				vis_status = "" if fd.hitboxes_data[i].get("visible", true) else " [隐藏]"
		_hitbox_list.add_item(prefix + area.name + vis_status)
		_hitbox_list.set_item_metadata(i, i)

	if selected_hitbox_index >= 0 and selected_hitbox_index < hitbox_areas.size():
		_hitbox_list.select(selected_hitbox_index)

func _on_hitbox_list_selected(index: int):
	if index < 0 or index >= hitbox_areas.size():
		return
	selected_hitbox_index = index
	_refresh_hitbox_list()
	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

func _on_add_hitbox():
	var new_index = hitbox_areas.size() + 1
	var new_area = Area2D.new()
	new_area.name = "HitboxArea" + str(new_index)
	new_area.position = Vector2.ZERO

	var new_shape_node = CollisionShape2D.new()
	new_shape_node.name = "CollisionShape2D"
	var new_rect = RectangleShape2D.new()
	new_rect.size = Vector2(20, 20)
	new_shape_node.shape = new_rect
	new_area.add_child(new_shape_node)

	if _is_anim_player_entity:
		var preview = _canvas.get_node_or_null("EntityPreview")
		if preview:
			# 找到 preview 中的 visuals_node 来添加受击框
			var target = preview.get_node_or_null("Visuals") if preview.has_node("Visuals") else preview
			target.add_child(new_area)
	else:
		animated_sprite.add_child(new_area)
	
	hitbox_areas.append(new_area)

	# 更新帧数据
	if animation_data.has(current_animation) and animation_data[current_animation].has(current_frame):
		var frame_data = animation_data[current_animation][current_frame]
		_update_hitbox_data_from_scene(frame_data)

	selected_hitbox_index = hitbox_areas.size() - 1
	is_data_modified = true
	_refresh_hitbox_list()
	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

func _on_delete_hitbox():
	if selected_hitbox_index < 0 or selected_hitbox_index >= hitbox_areas.size():
		return

	var area = hitbox_areas[selected_hitbox_index]
	area.queue_free()
	hitbox_areas.remove_at(selected_hitbox_index)

	if selected_hitbox_index >= hitbox_areas.size():
		selected_hitbox_index = hitbox_areas.size() - 1

	# 更新帧数据
	if animation_data.has(current_animation) and animation_data[current_animation].has(current_frame):
		var frame_data = animation_data[current_animation][current_frame]
		_update_hitbox_data_from_scene(frame_data)

	is_data_modified = true
	_refresh_hitbox_list()
	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

func _on_remove_frame_config():
	if animation_data.has(current_animation) and animation_data[current_animation].has(current_frame):
		animation_data[current_animation].erase(current_frame)
		is_data_modified = true
		_load_current_frame_data()
		_update_anchor_editor()
		_update_hitbox_property_panel()
		_draw_node.queue_redraw()

# ==========================================
# 保存当前帧状态
# ==========================================
func _save_current_frame_state():
	if not animation_data.has(current_animation):
		return
	if not animation_data[current_animation].has(current_frame):
		animation_data[current_animation][current_frame] = FrameData.new()

	var frame_data = animation_data[current_animation][current_frame]
	frame_data.frame_index = current_frame
	frame_data.anchor_point = _get_current_anchor()

	frame_data.hitboxes_data.clear()
	for i in range(hitbox_areas.size()):
		var area = hitbox_areas[i]
		var shape_node = area.get_child(0)
		if shape_node is CollisionShape2D:
			var hitbox_data = {
				"area_name": area.name,
				"position": {"x": area.position.x, "y": area.position.y},
				"rotation": area.rotation,
				"scale": {"x": area.scale.x, "y": area.scale.y},
				"visible": area.visible
			}
			if shape_node.shape is RectangleShape2D:
				hitbox_data["shape_type"] = "rectangle"
				hitbox_data["size"] = {
					"width": shape_node.shape.size.x,
					"height": shape_node.shape.size.y
				}
			elif shape_node.shape is CircleShape2D:
				hitbox_data["shape_type"] = "circle"
				hitbox_data["radius"] = shape_node.shape.radius
			frame_data.hitboxes_data.append(hitbox_data)

# ==========================================
# 数据保存与加载
# ==========================================
func _on_save_pressed():
	if not animation_data[current_animation].has(current_frame):
		animation_data[current_animation][current_frame] = FrameData.new()
	_save_current_frame_state()
	is_data_modified = true
	save_frame_data()

func _on_save_all_pressed():
	_save_current_frame_state()
	save_frame_data()

func save_frame_data():
	if frame_data_file_path == "":
		return

	var save_data = _build_save_data()
	var file = FileAccess.open(frame_data_file_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_data, "\t", true)
		file.store_string(json_string)
		file.close()
		is_data_modified = false
	else:
		push_error("保存失败: " + str(FileAccess.get_open_error()))

func _build_save_data() -> Dictionary:
	var save_data = {
		"entity_scene_path": entity_scene_path,
		"animation_data": {},
		"animation_global_anchors": {},
		"handle_size": handle_size,
		"save_time": Time.get_datetime_string_from_system()
	}

	for anim_name in animation_data:
		save_data["animation_data"][anim_name] = {}
		for frame_index in animation_data[anim_name]:
			var frame_data = animation_data[anim_name][frame_index]
			save_data["animation_data"][anim_name][str(frame_index)] = {
				"frame_index": frame_data.frame_index,
				"anchor_point": {
					"x": frame_data.anchor_point.x,
					"y": frame_data.anchor_point.y
				},
				"hitboxes_data": frame_data.hitboxes_data.duplicate(true)
			}

	for anim_name in animation_global_anchors:
		var anchor = animation_global_anchors[anim_name]
		if anchor != null:
			save_data["animation_global_anchors"][anim_name] = {
				"x": anchor.x,
				"y": anchor.y
			}
		else:
			save_data["animation_global_anchors"][anim_name] = null
	
	return save_data

func _on_export_data():
	_save_current_frame_state()
	var save_data = _build_save_data()
	var json_string = JSON.stringify(save_data, "\t", true)
	
	var dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.json", "JSON 数据文件")
	dialog.title = "导出帧数据"
	dialog.current_file = "frame_data_export.json"
	dialog.file_selected.connect(_on_export_file_selected.bind(json_string))
	add_child(dialog)
	dialog.popup_centered()

func _on_export_file_selected(path: String, json_string: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("帧数据已导出到: ", path)
	else:
		push_error("导出失败: " + str(FileAccess.get_open_error()))

func _on_import_data():
	var dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.json", "JSON 数据文件")
	dialog.title = "导入帧数据"
	dialog.file_selected.connect(_on_import_file_selected)
	add_child(dialog)
	dialog.popup_centered()

func _on_import_file_selected(path: String):
	if not FileAccess.file_exists(path):
		push_error("文件不存在: " + path)
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("无法读取文件: " + str(FileAccess.get_open_error()))
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("解析JSON失败: " + json.get_error_message())
		return
	
	var loaded_data = json.data
	if not loaded_data.has("animation_data"):
		push_error("无效的帧数据文件（缺少 animation_data）")
		return
	
	animation_data.clear()
	animation_global_anchors.clear()
	_prev_hitbox_vis.clear()
	
	for anim_name in loaded_data["animation_data"]:
		animation_data[anim_name] = {}
		var anim_data = loaded_data["animation_data"][anim_name]
		for frame_str in anim_data:
			var frame_index = int(frame_str)
			var frame_dict = anim_data[frame_str]
			var frame_data = FrameData.new()
			frame_data.frame_index = frame_dict.get("frame_index", frame_index)
			var anchor_dict = frame_dict.get("anchor_point", {})
			if anchor_dict:
				frame_data.anchor_point = Vector2(
					anchor_dict.get("x", 0),
					anchor_dict.get("y", 0)
				)
			frame_data.hitboxes_data = frame_dict.get("hitboxes_data", [])
			animation_data[anim_name][frame_index] = frame_data
	
	if loaded_data.has("animation_global_anchors"):
		for anim_name in loaded_data["animation_global_anchors"]:
			var anchor_dict = loaded_data["animation_global_anchors"][anim_name]
			if anchor_dict != null:
				animation_global_anchors[anim_name] = Vector2(
					anchor_dict.get("x", 0),
					anchor_dict.get("y", 0)
				)
			else:
				animation_global_anchors[anim_name] = null
	
	if loaded_data.has("handle_size"):
		handle_size = loaded_data["handle_size"]
		if _handle_size_slider:
			_handle_size_slider.set_value_no_signal(handle_size)
			_handle_size_value_label.text = "%d px" % int(handle_size)
	
	if animated_sprite and animated_sprite.sprite_frames:
		_load_current_frame_data()
		_update_frame_data_on_ui()
	
	is_data_modified = true
	save_frame_data()
	print("帧数据已导入自: ", path)

func _auto_save_frame_data():
	if frame_data_file_path == "":
		return
	_save_current_frame_state()
	save_frame_data()

func _load_frame_data():
	if frame_data_file_path == "" or not FileAccess.file_exists(frame_data_file_path):
		animation_data.clear()
		animation_global_anchors.clear()
		return

	var file = FileAccess.open(frame_data_file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var error = json.parse(json_string)

		if error == OK:
			var loaded_data = json.data
			animation_data.clear()
			animation_global_anchors.clear()

			if loaded_data.has("animation_data"):
				for anim_name in loaded_data["animation_data"]:
					animation_data[anim_name] = {}
					var anim_data = loaded_data["animation_data"][anim_name]
					for frame_str in anim_data:
						var frame_index = int(frame_str)
						var frame_dict = anim_data[frame_str]
						var frame_data = FrameData.new()
						frame_data.frame_index = frame_dict.get("frame_index", frame_index)
						var anchor_dict = frame_dict.get("anchor_point", {})
						if anchor_dict:
							frame_data.anchor_point = Vector2(
								anchor_dict.get("x", 0),
								anchor_dict.get("y", 0)
							)
						frame_data.hitboxes_data = frame_dict.get("hitboxes_data", [])
						animation_data[anim_name][frame_index] = frame_data

			if loaded_data.has("animation_global_anchors"):
				for anim_name in loaded_data["animation_global_anchors"]:
					var anchor_dict = loaded_data["animation_global_anchors"][anim_name]
					if anchor_dict != null:
						animation_global_anchors[anim_name] = Vector2(
							anchor_dict.get("x", 0),
							anchor_dict.get("y", 0)
						)
					else:
						animation_global_anchors[anim_name] = null

			# 加载控件大小配置
			if loaded_data.has("handle_size"):
				handle_size = loaded_data["handle_size"]
				if _handle_size_slider:
					_handle_size_slider.set_value_no_signal(handle_size)
					_handle_size_value_label.text = "%d px" % int(handle_size)

			if animated_sprite and animated_sprite.sprite_frames:
				_update_frame_data_on_ui()
		else:
			push_error("解析JSON失败: " + json.get_error_message())

func _update_frame_data_on_ui():
	if not current_animation in animation_data:
		return

	if animation_data[current_animation].has(current_frame):
		var frame_data = animation_data[current_animation][current_frame]
		_anchor_x_spinbox.value = frame_data.anchor_point.x
		_anchor_y_spinbox.value = frame_data.anchor_point.y

		var use_global_anchor = animation_global_anchors.get(current_animation, null) != null
		if use_global_anchor:
			_apply_anchor_all_button.text = "取消全局锚点"
			_apply_anchor_all_button.tooltip_text = "取消全局锚点设置，恢复为每帧独立锚点"
		else:
			_apply_anchor_all_button.text = "设为全局锚点"
			_apply_anchor_all_button.tooltip_text = "将当前锚点设置应用到当前动画的所有帧"

	_update_hitbox_property_panel()
	_draw_node.queue_redraw()

# ==========================================
# 复制粘贴
# ==========================================
func _on_copy_pressed():
	if animation_data[current_animation].has(current_frame):
		var frame_data = animation_data[current_animation][current_frame]
		copied_frame_data = frame_data.serialize().duplicate(true)

func _on_paste_pressed():
	if copied_frame_data.is_empty():
		return

	var prev_data = {}
	if animation_data[current_animation].has(current_frame):
		prev_data = animation_data[current_animation][current_frame].serialize().duplicate(true)

	if not animation_data[current_animation].has(current_frame):
		animation_data[current_animation][current_frame] = FrameData.new()

	var frame_data = animation_data[current_animation][current_frame]
	frame_data.deserialize(copied_frame_data)
	_restore_hitbox_shapes(frame_data)

	_anchor_x_spinbox.value = frame_data.anchor_point.x
	_anchor_y_spinbox.value = frame_data.anchor_point.y

	_update_hitbox_property_panel()
	is_data_modified = true

	_record_action("paste", {
		"prev_data": prev_data,
		"pasted_data": copied_frame_data.duplicate(true)
	})

	_draw_node.queue_redraw()

# ==========================================
# 鼠标模式与网格
# ==========================================
func _on_debug_mode_toggled():
	debug_mode = !debug_mode
	_draw_node.queue_redraw()

func _update_mouse_mode_button():
	# 鼠标模式不再需要按钮，但保留内部状态
	pass

func _release_all_focus():
	# 释放右侧面板所有 SpinBox 和 Slider 的焦点
	for spinbox in [_anchor_x_spinbox, _anchor_y_spinbox, _hitbox_pos_x_spinbox, _hitbox_pos_y_spinbox,
		_hitbox_rot_spinbox, _hitbox_size_x_spinbox, _hitbox_size_y_spinbox, _hitbox_radius_spinbox]:
		if spinbox:
			spinbox.release_focus()
	if _handle_size_slider:
		_handle_size_slider.release_focus()

# ==========================================
# 画布绘制
# ==========================================
func _on_canvas_draw():
	if _is_anim_player_entity:
		if not _canvas.get_node_or_null("EntityPreview"):
			return
	else:
		if not animated_sprite:
			return

	# 绘制坐标轴参考线
	var axis_len = 50 * _canvas_zoom
	_draw_node.draw_line(Vector2(0, 0), Vector2(axis_len, 0), Color.RED, 1.0)
	_draw_node.draw_line(Vector2(0, 0), Vector2(0, axis_len), Color.GREEN, 1.0)

	# 绘制锚点
	_draw_anchor()

	# 绘制受击框
	_draw_hitboxes()

	# 绘制手柄
	_draw_handles()

	# 调试信息
	if debug_mode:
		_draw_debug_info()

func _draw_anchor():
	var anchor_point = _get_current_anchor()
	var draw_pos = anchor_point * _canvas_zoom

	var half_size = anchor_viz_size / 2.0
	var line_width = 3.0

	# 背景圆
	_draw_node.draw_circle(draw_pos, half_size + 3, Color(0, 0, 0, 0.3))
	_draw_node.draw_arc(draw_pos, half_size, 0, PI * 2, 32, Color(0, 0, 0, 0.6), 3.0, true)

	# 十字线
	_draw_node.draw_line(
		Vector2(draw_pos.x - half_size, draw_pos.y),
		Vector2(draw_pos.x + half_size, draw_pos.y),
		Color(1.0, 1.0, 1.0, 1.0), line_width + 2
	)
	_draw_node.draw_line(
		Vector2(draw_pos.x - half_size, draw_pos.y),
		Vector2(draw_pos.x + half_size, draw_pos.y),
		anchor_viz_color, line_width
	)
	_draw_node.draw_line(
		Vector2(draw_pos.x, draw_pos.y - half_size),
		Vector2(draw_pos.x, draw_pos.y + half_size),
		Color(1.0, 1.0, 1.0, 1.0), line_width + 2
	)
	_draw_node.draw_line(
		Vector2(draw_pos.x, draw_pos.y - half_size),
		Vector2(draw_pos.x, draw_pos.y + half_size),
		anchor_viz_color, line_width
	)

	# 中心圆
	_draw_node.draw_circle(draw_pos, 8.0, Color(1.0, 1.0, 1.0, 1.0))
	_draw_node.draw_circle(draw_pos, 5.0, anchor_viz_color)

func _draw_hitboxes():
	for i in range(hitbox_areas.size()):
		var area = hitbox_areas[i]
		var shape_node = area.get_child(0) if area.get_child_count() > 0 else null
		if not shape_node or not (shape_node is CollisionShape2D):
			continue

		var is_selected = (i == selected_hitbox_index)
		var draw_pos = area.position * _canvas_zoom
		
		# 检查可见性
		var is_visible = true
		if animation_data.has(current_animation) and animation_data[current_animation].has(current_frame):
			var fd = animation_data[current_animation][current_frame]
			if fd.hitboxes_data.size() > i:
				is_visible = fd.hitboxes_data[i].get("visible", true)

		# 隐藏的受击框用灰色半透明显示
		var fill_color: Color
		var border_color: Color
		var border_width: float
		if not is_visible:
			fill_color = Color(0.3, 0.3, 0.3, 0.05)
			border_color = Color(0.5, 0.5, 0.5, 0.3)
			border_width = 1.0
		elif is_selected:
			fill_color = Color(0, 1, 0, 0.15)
			border_color = Color(0, 1, 0, 0.8)
			border_width = 2.0
		else:
			fill_color = Color(0, 0.5, 1, 0.1)
			border_color = Color(0, 0.5, 1, 0.5)
			border_width = 1.0

		if shape_node.shape is RectangleShape2D:
			var size = shape_node.shape.size * area.scale * _canvas_zoom
			# 旋转矩形
			var points = PackedVector2Array()
			var corners = [
				Vector2(-size.x/2, -size.y/2),
				Vector2(size.x/2, -size.y/2),
				Vector2(size.x/2, size.y/2),
				Vector2(-size.x/2, size.y/2)
			]
			for corner in corners:
				points.append(draw_pos + corner.rotated(area.rotation))
			_draw_node.draw_colored_polygon(points, fill_color)
			points.append(points[0])
			_draw_node.draw_polyline(points, border_color, border_width)

		elif shape_node.shape is CircleShape2D:
			var radius = shape_node.shape.radius * max(area.scale.x, area.scale.y) * _canvas_zoom
			_draw_node.draw_circle(draw_pos, radius, fill_color)
			_draw_node.draw_arc(draw_pos, radius, 0, PI * 2, 32, border_color, border_width, true)

		# 标签
		var label_text = area.name
		if not is_visible:
			label_text += " [隐藏]"
		_draw_node.draw_string(
			ThemeDB.fallback_font,
			draw_pos + Vector2(10, -10),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(1, 1, 0, 1) if is_selected else (Color(0.5, 0.5, 0.5, 0.5) if not is_visible else Color(0.8, 0.8, 0.8, 0.8))
		)

func _draw_handles():
	if hitbox_areas.size() == 0:
		return

	for i in range(hitbox_areas.size()):
		var area = hitbox_areas[i]
		var is_selected = (i == selected_hitbox_index)
		var area_draw_pos = area.position * _canvas_zoom

		# 位置手柄（中心）
		var handle_color = Color(0.2, 0.8, 0.2, 0.9) if not is_selected else Color(1.0, 1.0, 0.2, 1.0)
		var h_radius = handle_size * (1.2 if is_selected else 1.0)
		_draw_node.draw_circle(area_draw_pos, h_radius + 4, Color(0, 0, 0, 0.7))
		_draw_node.draw_circle(area_draw_pos, h_radius, handle_color)
		_draw_node.draw_circle(area_draw_pos, h_radius / 2, Color(1, 1, 1, 1))

		# 旋转手柄（右侧）
		var rot_handle_logical = _get_rotation_handle_position(i)
		if rot_handle_logical != Vector2.ZERO:
			var rot_handle_pos = rot_handle_logical * _canvas_zoom
			var rot_color = Color(0.8, 0.2, 0.8, 0.9) if not is_selected else Color(1.0, 1.0, 0.2, 1.0)
			_draw_node.draw_line(area_draw_pos, rot_handle_pos, Color(0.8, 0.2, 0.8, 0.5), 2.0)
			var rot_radius = handle_size * 0.8 * (1.2 if is_selected else 1.0)
			_draw_node.draw_circle(rot_handle_pos, rot_radius + 2, Color(0, 0, 0, 0.5))
			_draw_node.draw_circle(rot_handle_pos, rot_radius, rot_color)

		# 8方向缩放手柄（仅选中时显示）
		if not is_selected:
			continue

		# 计算受击框在世界空间的四个角和边中点
		var half_w: float = 0.0
		var half_h: float = 0.0
		var shape_node = area.get_child(0) if area.get_child_count() > 0 else null
		if shape_node and shape_node is CollisionShape2D:
			if shape_node.shape is RectangleShape2D:
				half_w = shape_node.shape.size.x * area.scale.x * _canvas_zoom / 2.0
				half_h = shape_node.shape.size.y * area.scale.y * _canvas_zoom / 2.0
			elif shape_node.shape is CircleShape2D:
				var r = shape_node.shape.radius * max(area.scale.x, area.scale.y) * _canvas_zoom
				half_w = r
				half_h = r
		if half_w < 1.0 or half_h < 1.0:
			continue

		var rot = area.rotation
		# 八个方向：N S E W NE NW SE SW
		var dirs = {
			"N": Vector2(0, -1),
			"S": Vector2(0, 1),
			"E": Vector2(1, 0),
			"W": Vector2(-1, 0),
			"NE": Vector2(1, -1),
			"NW": Vector2(-1, -1),
			"SE": Vector2(1, 1),
			"SW": Vector2(-1, 1)
		}
		for dir_name in dirs:
			var dir = dirs[dir_name]
			var offset = Vector2(dir.x * half_w, dir.y * half_h).rotated(rot)
			var handle_screen_pos = area_draw_pos + offset
			# 边缘手柄用蓝色，角手柄用青色
			var resize_color = Color(0.2, 0.5, 0.9, 0.9) if dir_name.length() == 1 else Color(0.2, 0.8, 0.8, 0.9)
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

func _draw_debug_info():
	if not debug_mode:
		return

	# 调试信息在画布右上角
	var debug_y = 20.0
	var debug_x = -200.0 + _canvas.size.x / _canvas_zoom - preview_root_position.x

	var debug_text = "缩放: %.0f%% | 受击框: %d | 选中: %d" % [
		_canvas_zoom * 100, hitbox_areas.size(), selected_hitbox_index
	]
	_draw_node.draw_string(
		ThemeDB.fallback_font,
		Vector2(debug_x, debug_y),
		debug_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0, 0.8)
	)

func _get_animated_sprite_size() -> Vector2:
	if _is_anim_player_entity:
		var preview = _canvas.get_node_or_null("EntityPreview")
		if preview and preview is Node2D:
			# 尝试获取预览实体的视觉大小
			var visuals = preview.get_node_or_null("Visuals") as Node2D
			if visuals:
				return visuals.get_rect().size if visuals.has_method("get_rect") else Vector2(100, 100)
		return Vector2(100, 100)
	if not animated_sprite:
		return Vector2(100, 100)
	var texture = animated_sprite.sprite_frames.get_frame_texture(current_animation, current_frame)
	if texture:
		return texture.get_size()
	return Vector2(100, 100)

# ==========================================
# 清理
# ==========================================
func _cleanup_visualization_nodes():
	# 所有可视化现在通过 _draw_node 绘制，无需单独清理
	pass

func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if _is_anim_player_entity:
			if _canvas and _canvas.get_node_or_null("EntityPreview"):
				_apply_canvas_transform()
		elif animated_sprite and _canvas:
			_apply_canvas_transform()
