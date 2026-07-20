@tool
extends Window

# ============================================
# 图形化脚本编辑器 - 重构版（修复空指针和显示问题）
# ============================================

enum BlockType {
	EVENT, ACTION, CONDITION, VALUE,
}

# 编辑器模式：积木画布 / 事件表
enum EditorMode {
	BLOCK, EVENT,
}

const SAVE_FILE_NAME = "visual_script.json"
const SAVE_VERSION = 2

var _category_colors: Dictionary = {}
var _undo_stack: Array = []
var _undo_index: int = -1
const MAX_UNDO = 50
const INT_MAX = 2147483647

var _block_defs = [
	{"type": BlockType.EVENT, "name": "on_game_start", "label": "当游戏开始", "category": "事件", "params": []},
	{"type": BlockType.EVENT, "name": "on_animation_playing", "label": "当动画播放 {anim_name}", "category": "事件", "params": [{"name": "anim_name", "type": "string", "default": "idle", "label": "动画名"}]},
	{"type": BlockType.EVENT, "name": "on_hit", "label": "当被攻击命中", "category": "事件", "params": [], "outputs": [{"name": "attacker", "type": "node", "label": "攻击者"}]},
	{"type": BlockType.EVENT, "name": "on_victory", "label": "当胜利时", "category": "事件", "params": []},
	{"type": BlockType.ACTION, "name": "play_animation", "label": "播放动画 {anim_name}", "category": "动作", "params": [{"name": "anim_name", "type": "string", "default": "idle", "label": "动画名"}]},
	{"type": BlockType.ACTION, "name": "move_by", "label": "移动 X:{dx} Y:{dy}", "category": "动作", "params": [{"name": "dx", "type": "number", "default": 0, "label": "X偏移"}, {"name": "dy", "type": "number", "default": 0, "label": "Y偏移"}]},
	{"type": BlockType.ACTION, "name": "set_velocity", "label": "设置速度 VX:{vx} VY:{vy}", "category": "动作", "params": [{"name": "vx", "type": "number", "default": 0, "label": "X速度"}, {"name": "vy", "type": "number", "default": 0, "label": "Y速度"}]},
	{"type": BlockType.ACTION, "name": "wait", "label": "等待 {duration} 秒", "category": "动作", "params": [{"name": "duration", "type": "number", "default": 1.0, "label": "秒数"}]},
	{"type": BlockType.ACTION, "name": "set_variable", "label": "设置 {var_name} = {value}", "category": "动作", "params": [{"name": "var_name", "type": "string", "default": "my_var", "label": "变量名"}, {"name": "value", "type": "number", "default": 0, "label": "值"}]},
	{"type": BlockType.ACTION, "name": "move_entity_pos3d_immd", "label": "3D传送实体 {target} 到 {pos}", "category": "动作", "params": [
		{"name": "target", "type": "node", "default": "", "label": "目标"},
		{"name": "pos", "type": "vector3", "default": Vector3.ZERO, "label": "位置"}
	]},
	{"type": BlockType.ACTION, "name": "tween_property", "label": "补间 {target} 属性 {prop} 到 {to} 耗时 {dur} 秒", "category": "动作", "params": [
		{"name": "target", "type": "node", "default": "", "label": "目标"},
		{"name": "prop", "type": "dropdown", "default": "scale", "label": "属性", "options": ["scale", "modulate", "modulate:a", "rotation", "position:x", "position:y"]},
		{"name": "to", "type": "number", "default": 1.0, "label": "目标值"},
		{"name": "dur", "type": "number", "default": 0.5, "label": "持续时间"},
		{"name": "ease", "type": "dropdown", "default": "缓出", "label": "缓动", "options": ["线性", "缓入", "缓出", "缓入缓出"]},
		{"name": "delay", "type": "number", "default": 0.0, "label": "延迟"}
	]},
	{"type": BlockType.CONDITION, "name": "if_condition", "label": "如果 {condition}", "category": "条件", "params": [{"name": "condition", "type": "bool", "default": true, "label": "条件"}]},
	{"type": BlockType.CONDITION, "name": "if_else", "label": "如果 {condition}", "category": "条件", "hide_in_event": true, "params": [{"name": "condition", "type": "bool", "default": true, "label": "条件"}]},
	{"type": BlockType.CONDITION, "name": "else_if", "label": "否则如果 {condition}", "category": "条件", "event_only": true, "params": [{"name": "condition", "type": "bool", "default": true, "label": "条件"}]},
	{"type": BlockType.CONDITION, "name": "else_block", "label": "否则", "category": "条件", "event_only": true, "params": []},
	{"type": BlockType.VALUE, "name": "number_value", "label": "{value}", "category": "值", "params": [{"name": "value", "type": "number", "default": 0, "label": "数值"}]},
	{"type": BlockType.VALUE, "name": "compare", "label": "{left} {op} {right}", "category": "值", "params": [{"name": "left", "type": "number", "default": "0", "label": "左"}, {"name": "op", "type": "dropdown", "default": ">", "label": "运算", "options": ["<", "=", ">"]}, {"name": "right", "type": "number", "default": "0", "label": "右"}]},
]

const BLOCK_HEIGHT: float = 40.0
const BLOCK_MIN_WIDTH: float = 160.0
const BLOCK_PADDING_H: float = 16.0
const BLOCK_LINE_HEIGHT: float = 28.0
const BLOCK_SNAP_DISTANCE: float = 20.0
const SLOT_HEIGHT: float = 24.0
const SLOT_SPACING: float = 8.0
const SLOT_MIN_WIDTH: float = 50.0
const SLOT_SNAP_DIST: float = 40.0
const INNER_PADDING: float = 8.0
const INNER_INDENT: float = 20.0
const MIN_INNER_HEIGHT: float = 30.0
const ELSE_HEADER_HEIGHT: float = 24.0
const DRAG_THRESHOLD: float = 5.0
const HAT_HEIGHT: float = 10.0
const BLOCK_DEFS_SAVE_PATH = "res://addons/entityeditor/block_defs.json"

# ---- 视觉增强常量 ----
const GRID_DOT_COLOR: Color = Color(0.5, 0.5, 0.5, 0.2)
const GRID_DOT_SIZE: float = 2.0
const GRID_SPACING: float = 32.0
const ZOOM_SMOOTH: float = 0.3

var _canvas: Control
var _grid_bg: Control
var _block_container: Node2D
var _interaction_layer: ColorRect
var _trash_area: Panel
var _z_group_counter: int = 0

var _cat_label: Label
var _category_list: ItemList
var _search_input: LineEdit
var _block_list: ItemList
var _prop_panel: VBoxContainer
var _right_panel: PanelContainer
var _right_scroll: ScrollContainer
var _right_panel_visible: bool = true

var _canvas_zoom: float = 1.0
var _target_zoom: float = 1.0
var _canvas_offset: Vector2 = Vector2.ZERO
var _target_offset: Vector2 = Vector2.ZERO

var _blocks: Array = []
var _block_id_counter: int = 0
var _blocks_by_id: Dictionary = {}
var _slot_block_ids: Dictionary = {}
var _inner_block_ids_set: Dictionary = {}
var _block_nodes: Dictionary = {}

var _dragging_block_ids: Array = []
var _drag_offsets: Dictionary = {}
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _pan_offset_start: Vector2 = Vector2.ZERO

var _potential_drag_id: int = -1
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_started: bool = false

var _selected_block_id: int = -1
var _hovered_block_id: int = -1
var _hover_slot_info: Dictionary = {}
var _inline_edit: LineEdit
var _editing_slot: Dictionary = {}  # {block_id, param_name}
var _output_port_info: Dictionary = {}
var _potential_output_drag: Dictionary = {}
var _mouse_logical: Vector2 = Vector2.ZERO
var _snap_line: Line2D
var _snap_touched_inner: bool = false
var _snap_touched_slot: bool = false
var _snap_touched_stack: bool = false

var _categories: Array = []
var _current_category: String = ""
var _filtered_block_defs: Array = []

var _entity_instance: Node = null
var _entity_scene_path: String = ""

var _undo_btn: Button = null
var _redo_btn: Button = null
var _event_undo_btn: Button = null
var _event_redo_btn: Button = null

var _context_menu: PopupMenu = null
var _context_menu_rclick_id: int = -1

var _dirty: bool = false
var _last_saved_json: String = ""
var _save_timer: Timer = null
var _save_pending: bool = false

# ---- 进度条相关 ----
var _progress_overlay: Panel = null
var _progress_bar: ProgressBar = null
var _progress_label: Label = null

# ---- 事件表相关状态 ----
var _current_mode: int = EditorMode.EVENT
var _events_data: Dictionary = {"rows": []}
var _event_row_id_counter: int = 1000
var _row_uid_counter: int = 1
## UI 状态（折叠等），与逻辑数据分离存储
var _ui_state: Dictionary = {}
var _event_tree: Tree = null
var _event_container: Control = null       # 事件模式下的中间容器（含 Tree + 工具栏）
var _event_toolbar: HBoxContainer = null
var _mode_block_btn: Button = null
var _mode_event_btn: Button = null

## 脚本运行模式: "both" | "blocks_only" | "events_only"
var _run_mode: String = "both"
var _run_mode_opt: OptionButton = null
var _selected_event_row_id: int = -1
var _event_node_map: Dictionary = {}   # 临时 ID → 节点字典引用（每次渲染重建）
var _event_node_id_counter: int = 0
var _event_clipboard: Dictionary = {}   # 剪贴板：{node: Dictionary, is_root: bool}
var _event_clipboard_cut: bool = false  # 标记剪切（粘贴后清空剪贴板）
var _event_context_menu: PopupMenu = null  # 事件树右键菜单

# ---- 事件表搜索相关 ----
var _event_search_input: LineEdit = null
var _event_search_prev_btn: Button = null
var _event_search_next_btn: Button = null
var _event_search_label: Label = null
var _event_search_text: String = ""
var _event_search_matches: Array = []  # [{item: TreeItem, orig_color: Color}]
var _event_search_current_index: int = -1
var _event_search_expanded: Array = []  # [{item, was_collapsed}] 跳转时展开过的祖先

# ---- 事件表拖拽相关 ----
var _drag_source_item: TreeItem = null   # 拖拽源 TreeItem
# 拖拽源用背景色高亮，cleanup 时直接 clear，避免 get_custom_color 默认值歧义
var _drag_source_node: Dictionary = {}   # 拖拽源节点数据
var _drag_target_item: TreeItem = null   # 拖拽目标 TreeItem
var _drag_hover_y: float = -1.0         # 当前鼠标 Y 位置（画白线用）
var _drag_in_progress: bool = false     # 是否正在拖拽中
var _drag_preview: Label = null         # 拖拽时跟随鼠标的预览标签
var _drag_attach_hover: bool = false    # 悬停在块中间：附加为子节点
var _prevent_drag_after_dialog: bool = false  # 对话框关闭后阻止一次拖拽
const DRAG_EDGE_THRESHOLD: int = 10     # 判定「缝隙」的像素阈值

func _ready():
	title = "图形化脚本编辑器"
	size = Vector2(1400, 900)
	min_size = Vector2(900, 700)
	close_requested.connect(_on_close_requested)
	if not _load_block_defs():
		_block_defs = _get_default_block_defs()
	_setup_ui()
	_setup_categories()
	_update_undo_redo_buttons()
	_center_window()

func _input(event: InputEvent):
	# 拖拽中按 Esc 取消
	if _drag_in_progress and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cleanup_drag()
		return
	if _inline_edit and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_inline_edit()
		_refresh_block_node(_editing_slot.get("block_id", -1))
		return
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_S and event.ctrl_pressed and not event.shift_pressed:
				_save_script()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_Z and event.ctrl_pressed and not event.shift_pressed:
				_undo()
				get_viewport().set_input_as_handled()
			elif (event.keycode == KEY_Y and event.ctrl_pressed) or (event.keycode == KEY_Z and event.ctrl_pressed and event.shift_pressed):
				_redo()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_F and event.ctrl_pressed and not event.shift_pressed:
				if _current_mode == EditorMode.EVENT and _event_search_input:
					_event_search_input.grab_focus()
					_event_search_input.select_all()
					get_viewport().set_input_as_handled()

func _center_window():
	var screen_size = DisplayServer.screen_get_size()
	position = Vector2((screen_size.x - size.x) / 2, (screen_size.y - size.y) / 2)

# ----------------------------------- UI 构建 ------------------------------------
func _setup_ui():
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 0)
	add_child(main_hbox)

	var left_panel = PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(260, 0)
	main_hbox.add_child(left_panel)

	var left_vbox = VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 4)
	left_panel.add_child(left_vbox)

	var left_title = Label.new()
	left_title.text = "积木块面板"
	left_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_title.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(left_title)

	var search_label = Label.new()
	search_label.text = "搜索:"
	search_label.add_theme_font_size_override("font_size", 12)
	left_vbox.add_child(search_label)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "输入关键词全局搜索积木..."
	_search_input.clear_button_enabled = true
	_search_input.text_changed.connect(_on_search_changed)
	left_vbox.add_child(_search_input)

	_cat_label = Label.new()
	_cat_label.text = "分类:"
	_cat_label.add_theme_font_size_override("font_size", 12)
	left_vbox.add_child(_cat_label)

	_category_list = ItemList.new()
	_category_list.custom_minimum_size = Vector2(0, 80)
	_category_list.select_mode = ItemList.SELECT_SINGLE
	_category_list.item_selected.connect(_on_category_selected)
	left_vbox.add_child(_category_list)

	var blk_label = Label.new()
	blk_label.text = "积木块:"
	blk_label.add_theme_font_size_override("font_size", 12)
	left_vbox.add_child(blk_label)

	_block_list = ItemList.new()
	_block_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_block_list.select_mode = ItemList.SELECT_SINGLE
	_block_list.item_selected.connect(_on_block_selected)
	_block_list.item_activated.connect(_on_block_activated)
	left_vbox.add_child(_block_list)

	var add_btn = Button.new()
	add_btn.text = "添加到画布"
	add_btn.pressed.connect(_on_add_block_pressed)
	left_vbox.add_child(add_btn)

	var edit_btn = Button.new()
	edit_btn.text = "编辑块定义"
	edit_btn.pressed.connect(_show_block_editor)
	left_vbox.add_child(edit_btn)

	var center_panel = PanelContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(center_panel)

	var center_vbox = VBoxContainer.new()
	center_vbox.add_theme_constant_override("separation", 2)
	center_panel.add_child(center_vbox)

	var canvas_title_bar = HBoxContainer.new()
	canvas_title_bar.add_theme_constant_override("separation", 8)
	center_vbox.add_child(canvas_title_bar)

	_undo_btn = Button.new()
	_undo_btn.text = "↩撤回"
	_undo_btn.add_theme_font_size_override("font_size", 12)
	_undo_btn.pressed.connect(_undo)
	canvas_title_bar.add_child(_undo_btn)

	_redo_btn = Button.new()
	_redo_btn.text = "↪重做"
	_redo_btn.add_theme_font_size_override("font_size", 12)
	_redo_btn.pressed.connect(_redo)
	canvas_title_bar.add_child(_redo_btn)

	# ---- 模式切换按钮组 ----
	_mode_block_btn = Button.new()
	_mode_block_btn.text = "积木模式"
	_mode_block_btn.toggle_mode = true
	_mode_block_btn.button_pressed = true
	_mode_block_btn.add_theme_font_size_override("font_size", 12)
	_mode_block_btn.pressed.connect(_on_mode_switch.bind(EditorMode.BLOCK))
	canvas_title_bar.add_child(_mode_block_btn)

	_mode_event_btn = Button.new()
	_mode_event_btn.text = "事件表模式"
	_mode_event_btn.toggle_mode = true
	_mode_event_btn.add_theme_font_size_override("font_size", 12)
	_mode_event_btn.pressed.connect(_on_mode_switch.bind(EditorMode.EVENT))
	canvas_title_bar.add_child(_mode_event_btn)

	# ---- 运行模式选择器 ----
	var run_mode_label = Label.new()
	run_mode_label.text = "运行:"
	run_mode_label.add_theme_font_size_override("font_size", 12)
	canvas_title_bar.add_child(run_mode_label)
	_run_mode_opt = OptionButton.new()
	_run_mode_opt.add_item("积木+事件表", 0)  # both
	_run_mode_opt.add_item("仅积木", 1)       # blocks_only
	_run_mode_opt.add_item("仅事件表", 2)     # events_only
	_run_mode_opt.select(0)
	_run_mode_opt.add_theme_font_size_override("font_size", 12)
	_run_mode_opt.tooltip_text = "控制运行时执行哪部分脚本（保存到 visual_script.json）"
	_run_mode_opt.item_selected.connect(_on_run_mode_changed)
	canvas_title_bar.add_child(_run_mode_opt)

	var title_sep = VSeparator.new()
	canvas_title_bar.add_child(title_sep)

	# ---------- 帮助按钮 ----------
	var help_btn = Button.new()
	help_btn.text = "?"
	help_btn.tooltip_text = "操作说明"
	help_btn.custom_minimum_size = Vector2(28, 22)
	help_btn.pressed.connect(_show_help_dialog)
	canvas_title_bar.add_child(help_btn)

	# ---------- 修复点：确保 _canvas 正确添加 ----------
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	center_vbox.add_child(_canvas)

	# 点阵网格背景
	_grid_bg = Control.new()
	_grid_bg.name = "GridBackground"
	_grid_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(_grid_bg)
	_grid_bg.draw.connect(_on_grid_draw)

	_block_container = Node2D.new()
	_block_container.name = "BlockContainer"
	_block_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.add_child(_block_container)

	_snap_line = Line2D.new()
	_snap_line.name = "SnapLine"
	_snap_line.width = 3.0
	_snap_line.default_color = Color.WHITE
	_snap_line.z_index = 100
	_snap_line.z_as_relative = false
	_snap_line.visible = false
	_canvas.add_child(_snap_line)

	_interaction_layer = ColorRect.new()
	_interaction_layer.name = "InteractionLayer"
	_interaction_layer.color = Color.TRANSPARENT
	_interaction_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_interaction_layer.z_index = 101
	_interaction_layer.z_as_relative = false
	_interaction_layer.gui_input.connect(_on_canvas_input)
	_canvas.add_child(_interaction_layer)

	_trash_area = Panel.new()
	_trash_area.name = "TrashArea"
	_trash_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trash_area.z_index = 102
	_trash_area.z_as_relative = false
	var trash_style = StyleBoxFlat.new()
	trash_style.bg_color = Color(0.2, 0.2, 0.2, 0.7)
	trash_style.border_color = Color(0.8, 0.3, 0.3)
	trash_style.set_border_width_all(2)
	trash_style.set_corner_radius_all(8)
	_trash_area.add_theme_stylebox_override("panel", trash_style)
	_canvas.add_child(_trash_area)

	var trash_label = Label.new()
	trash_label.text = "🗑 拖拽到此处删除"
	trash_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
	trash_label.add_theme_font_size_override("font_size", 14)
	trash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	trash_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trash_area.add_child(trash_label)

	_canvas.resized.connect(_on_canvas_resized)

	# ---- 事件表模式容器（与 _canvas 同级，初始隐藏） ----
	_event_container = VBoxContainer.new()
	_event_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_event_container.visible = false
	center_vbox.add_child(_event_container)

	_event_toolbar = HBoxContainer.new()
	_event_toolbar.add_theme_constant_override("separation", 6)
	_event_container.add_child(_event_toolbar)

	var ev_add_btn = Button.new()
	ev_add_btn.text = "+ 新增事件"
	ev_add_btn.add_theme_font_size_override("font_size", 12)
	ev_add_btn.pressed.connect(_on_event_add_row)
	_event_toolbar.add_child(ev_add_btn)

	var ev_add_group_btn = Button.new()
	ev_add_group_btn.text = "+ 添加分组"
	ev_add_group_btn.add_theme_font_size_override("font_size", 12)
	ev_add_group_btn.pressed.connect(_on_event_add_group)
	_event_toolbar.add_child(ev_add_group_btn)

	var ev_add_comment_btn = Button.new()
	ev_add_comment_btn.text = "+ 添加注释"
	ev_add_comment_btn.add_theme_font_size_override("font_size", 12)
	ev_add_comment_btn.pressed.connect(_on_event_add_comment)
	_event_toolbar.add_child(ev_add_comment_btn)

	_event_toolbar.add_child(VSeparator.new())

	var ev_del_btn = Button.new()
	ev_del_btn.text = "- 删除选中"
	ev_del_btn.add_theme_font_size_override("font_size", 12)
	ev_del_btn.pressed.connect(_on_event_delete_row)
	_event_toolbar.add_child(ev_del_btn)

	var ev_up_btn = Button.new()
	ev_up_btn.text = "↑ 上移"
	ev_up_btn.add_theme_font_size_override("font_size", 12)
	ev_up_btn.pressed.connect(_on_event_move_row.bind(-1))
	_event_toolbar.add_child(ev_up_btn)

	var ev_down_btn = Button.new()
	ev_down_btn.text = "↓ 下移"
	ev_down_btn.add_theme_font_size_override("font_size", 12)
	ev_down_btn.pressed.connect(_on_event_move_row.bind(1))
	_event_toolbar.add_child(ev_down_btn)

	var ev_convert_btn = Button.new()
	ev_convert_btn.text = "积木→事件表"
	ev_convert_btn.tooltip_text = "尝试将画布积木转换为事件表（开发中）"
	ev_convert_btn.add_theme_font_size_override("font_size", 12)
	ev_convert_btn.pressed.connect(_on_convert_blocks_to_events)
	_event_toolbar.add_child(ev_convert_btn)

	var ev_toggle_enabled_btn = Button.new()
	ev_toggle_enabled_btn.text = "启用/禁用"
	ev_toggle_enabled_btn.tooltip_text = "切换选中行的启用状态"
	ev_toggle_enabled_btn.add_theme_font_size_override("font_size", 12)
	ev_toggle_enabled_btn.pressed.connect(_on_event_toggle_enabled)
	_event_toolbar.add_child(ev_toggle_enabled_btn)

	var ev_move_under_btn = Button.new()
	ev_move_under_btn.text = "移动到块下"
	ev_move_under_btn.tooltip_text = "将选中的块移动到另一个块下面（作为其子块）"
	ev_move_under_btn.add_theme_font_size_override("font_size", 12)
	ev_move_under_btn.pressed.connect(_on_event_move_under)
	_event_toolbar.add_child(ev_move_under_btn)

	var ev_replace_btn = Button.new()
	ev_replace_btn.text = "替换块"
	ev_replace_btn.tooltip_text = "用新的块定义替换当前选中的块（保留子块）"
	ev_replace_btn.add_theme_font_size_override("font_size", 12)
	ev_replace_btn.pressed.connect(_on_event_replace_block)
	_event_toolbar.add_child(ev_replace_btn)

	var ev_undo_btn = Button.new()
	ev_undo_btn.text = "↩撤回"
	ev_undo_btn.tooltip_text = "撤销 (Ctrl+Z)"
	ev_undo_btn.add_theme_font_size_override("font_size", 12)
	ev_undo_btn.pressed.connect(_undo)
	_event_toolbar.add_child(ev_undo_btn)
	_event_undo_btn = ev_undo_btn

	var ev_redo_btn = Button.new()
	ev_redo_btn.text = "↪重做"
	ev_redo_btn.tooltip_text = "重做 (Ctrl+Y)"
	ev_redo_btn.add_theme_font_size_override("font_size", 12)
	ev_redo_btn.pressed.connect(_redo)
	_event_toolbar.add_child(ev_redo_btn)
	_event_redo_btn = ev_redo_btn

	# ---- 事件表搜索 ----
	_event_toolbar.add_child(VSeparator.new())
	var search_hb = HBoxContainer.new()
	search_hb.add_theme_constant_override("separation", 3)
	search_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_hb.custom_minimum_size = Vector2(200, 0)

	_event_search_input = LineEdit.new()
	_event_search_input.placeholder_text = "搜索事件..."
	_event_search_input.clear_button_enabled = true
	_event_search_input.custom_minimum_size = Vector2(120, 0)
	_event_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_search_input.text_changed.connect(_on_event_search_text_changed)
	search_hb.add_child(_event_search_input)

	_event_search_prev_btn = Button.new()
	_event_search_prev_btn.text = "▲"
	_event_search_prev_btn.tooltip_text = "上一个匹配"
	_event_search_prev_btn.add_theme_font_size_override("font_size", 11)
	_event_search_prev_btn.custom_minimum_size = Vector2(24, 0)
	_event_search_prev_btn.pressed.connect(_event_search_prev)
	search_hb.add_child(_event_search_prev_btn)

	_event_search_next_btn = Button.new()
	_event_search_next_btn.text = "▼"
	_event_search_next_btn.tooltip_text = "下一个匹配"
	_event_search_next_btn.add_theme_font_size_override("font_size", 11)
	_event_search_next_btn.custom_minimum_size = Vector2(24, 0)
	_event_search_next_btn.pressed.connect(_event_search_next)
	search_hb.add_child(_event_search_next_btn)

	_event_search_label = Label.new()
	_event_search_label.add_theme_font_size_override("font_size", 11)
	_event_search_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_event_search_label.custom_minimum_size = Vector2(50, 0)
	search_hb.add_child(_event_search_label)

	_event_toolbar.add_child(search_hb)

	# 初始禁用搜索按钮
	_event_search_prev_btn.disabled = true
	_event_search_next_btn.disabled = true

	_event_tree = Tree.new()
	_event_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_event_tree.columns = 1
	_event_tree.set_column_titles_visible(false)
	_event_tree.hide_root = true
	_event_tree.select_mode = Tree.SELECT_ROW
	_event_tree.item_selected.connect(_on_event_tree_selected)
	_event_tree.item_activated.connect(_on_event_tree_activated)
	_event_tree.item_edited.connect(_on_event_tree_item_edited)
	_event_tree.gui_input.connect(_on_event_tree_gui_input)
	_event_tree.mouse_exited.connect(_on_event_tree_mouse_exited)
	_event_tree.draw.connect(_on_event_tree_draw)
	_event_tree.item_collapsed.connect(_on_event_tree_item_collapsed)
	_event_tree.create_item()  # 根节点

	# 拖拽预览标签（浮动在 Tree 上方）
	_drag_preview = Label.new()
	_drag_preview.visible = false
	_drag_preview.add_theme_color_override("font_color", Color(0.3, 0.5, 1.0))
	_event_tree.add_child(_drag_preview)

	_event_container.add_child(_event_tree)

	# 事件树右键菜单
	_event_context_menu = PopupMenu.new()
	_event_context_menu.name = "EventContextMenu"
	_event_context_menu.id_pressed.connect(_on_event_context_menu_pressed)
	add_child(_event_context_menu)

	# 防抖保存定时器（延迟 500ms 执行保存，防止快速操作崩溃）
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(_on_save_timer_timeout)
	add_child(_save_timer)

	# 进度条覆盖层（加载/保存/转化时显示）
	_progress_overlay = Panel.new()
	_progress_overlay.size_flags_horizontal = Control.SIZE_FILL
	_progress_overlay.size_flags_vertical = Control.SIZE_FILL
	_progress_overlay.visible = false
	_progress_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.5)
	_progress_overlay.add_theme_stylebox_override("panel", overlay_style)
	var pvbox = VBoxContainer.new()
	pvbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pvbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pvbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pvbox.anchor_left = 0.5
	pvbox.anchor_right = 0.5
	pvbox.anchor_top = 0.5
	pvbox.anchor_bottom = 0.5
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(300, 24)
	_progress_bar.show_percentage = true
	pvbox.add_child(_progress_bar)
	_progress_label = Label.new()
	_progress_label.text = "处理中..."
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 14)
	pvbox.add_child(_progress_label)
	_progress_overlay.add_child(pvbox)
	add_child(_progress_overlay)

	_context_menu = PopupMenu.new()
	_context_menu.name = "ContextMenu"
	_context_menu.add_item("复制（仅当前块及内部依赖）", 0)
	_context_menu.add_item("刷新", 1)
	_context_menu.id_pressed.connect(_on_context_menu_pressed)
	add_child(_context_menu)

	_right_panel = PanelContainer.new()
	_right_panel.custom_minimum_size = Vector2(220, 0)
	main_hbox.add_child(_right_panel)

	_right_scroll = ScrollContainer.new()
	_right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_panel.add_child(_right_scroll)

	_prop_panel = VBoxContainer.new()
	_prop_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prop_panel.add_theme_constant_override("separation", 6)
	_right_scroll.add_child(_prop_panel)

	_update_prop_panel()

func _setup_categories():
	_sync_categories_from_defs()
	var default_cat_colors = {
		"事件": Color(0.96, 0.75, 0.15),
		"动作": Color(0.25, 0.58, 0.85),
		"条件": Color(0.58, 0.25, 0.82),
		"值": Color(0.35, 0.78, 0.38),
	}
	for cat in _categories:
		if not _category_colors.has(cat):
			_category_colors[cat] = default_cat_colors.get(cat, Color.GRAY)
	_category_list.clear()
	for cat in _categories:
		_category_list.add_item(cat)
	if _categories.size() > 0:
		_category_list.select(0)
		_current_category = _categories[0]
		_refresh_block_list()

func _refresh_block_list():
	_block_list.clear()
	_filtered_block_defs.clear()
	var search_text = _search_input.text.strip_edges().to_lower() if _search_input else ""
	var in_event_mode = (_current_mode == EditorMode.EVENT)
	for i in range(_block_defs.size()):
		var def = _block_defs[i]
		# ---- 按模式过滤 ----
		if in_event_mode:
			# 事件表模式：隐藏 VALUE 块、隐藏 hide_in_event 标记的块（如 if_else）
			if def.type == BlockType.VALUE:
				continue
			if def.get("hide_in_event", false):
				continue
		else:
			# 画布模式：隐藏 event_only 标记的块（如 else_if / else_block）
			if def.get("event_only", false):
				continue
		if search_text == "":
			if def.category != _current_category:
				continue
		else:
			var def_name = def.name.to_lower()
			var def_label = def.label.to_lower()
			var def_cat = def.category.to_lower()
			if search_text not in def_name and search_text not in def_label and search_text not in def_cat:
				continue
		var type_name = BlockType.keys()[def.type]
		_block_list.add_item("[%s] %s" % [type_name, def.label])
		_filtered_block_defs.append(def)

# ----------------------------------- 事件处理 ------------------------------------
func _on_search_changed(_new_text: String):
	var has_text = _search_input.text.strip_edges() != ""
	if _cat_label: _cat_label.visible = not has_text
	if _category_list: _category_list.visible = not has_text
	_refresh_block_list()

func _on_category_selected(index: int):
	if index < 0 or index >= _categories.size(): return
	_current_category = _categories[index]
	_refresh_block_list()

func _on_block_selected(index: int): pass
func _on_block_activated(index: int):
	if _current_mode == EditorMode.EVENT:
		_add_selected_block_to_events()
	else:
		_add_selected_block_to_canvas()
func _on_add_block_pressed():
	if _current_mode == EditorMode.EVENT:
		_add_selected_block_to_events()
	else:
		_add_selected_block_to_canvas()

func _add_selected_block_to_events():
	var selected = _block_list.get_selected_items()
	if selected.size() == 0: return
	var idx = selected[0]
	if idx >= 0 and idx < _filtered_block_defs.size():
		_add_block_to_events(_filtered_block_defs[idx])

func _add_selected_block_to_canvas():
	var selected = _block_list.get_selected_items()
	if selected.size() == 0: return
	var idx = selected[0]
	if idx >= 0 and idx < _filtered_block_defs.size():
		_save_undo_state()
		_create_block_instance(_filtered_block_defs[idx])

func _create_block_instance(def: Dictionary, pos: Vector2 = Vector2.ZERO):
	if pos == Vector2.ZERO:
		pos = _screen_to_logical(_canvas.size / 2.0)
	var params = {}
	for p in def.params:
		if p.default is Dictionary:
			params[p.name] = p.default.duplicate()
		else:
			params[p.name] = p.default
	var block = {
		"def": def,
		"pos": pos,
		"params": params,
		"id": _block_id_counter,
		"value_slots": {},
		"inner_block_ids": [],
		"inner_else_ids": [],
		"output_refs": {},
		"is_var_ref": false,
		"source_block_id": -1,
		"output_name": "",
		"output_type": "",
		"output_label": "",
		"stack_below_id": -1,
	}
	_block_id_counter += 1
	_blocks.append(block)
	_blocks_by_id[block.id] = block
	var old_selected = _selected_block_id
	_selected_block_id = block.id
	_create_block_node(block)
	_z_group_counter += 1
	if _block_nodes.has(block.id):
		_block_nodes[block.id].z_index = _z_group_counter * 1000
	if old_selected >= 0 and old_selected != block.id:
		_refresh_block_node(old_selected)
	_update_prop_panel()
	_update_canvas_transform()

func _create_var_ref_block(source_block_id: int, output_name: String) -> Dictionary:
	var source_block = _get_block_by_id(source_block_id)
	if source_block.is_empty(): return {}
	var output_def = {}
	for out in _ensure_outputs(source_block.def):
		if out.name == output_name:
			output_def = out
			break
	if output_def.is_empty(): return {}
	var ref_def = {
		"type": BlockType.VALUE,
		"name": "_var_ref_%s" % output_name,
		"label": "◆ %s" % output_def.label,
		"category": source_block.def.category,
		"params": [],
		"outputs": [],
	}
	var ref_block_id = _block_id_counter
	var ref_block = {
		"def": ref_def,
		"pos": source_block.pos + Vector2(_get_block_width(source_block) + 20, 0),
		"params": {},
		"id": ref_block_id,
		"value_slots": {},
		"inner_block_ids": [],
		"inner_else_ids": [],
		"output_refs": {},
		"is_var_ref": true,
		"source_block_id": source_block_id,
		"output_name": output_name,
		"output_type": output_def.type,
		"output_label": output_def.label,
		"stack_below_id": -1,
	}
	_block_id_counter += 1
	_blocks.append(ref_block)
	_blocks_by_id[ref_block.id] = ref_block
	if not source_block.output_refs.has(output_name):
		source_block.output_refs[output_name] = []
	source_block.output_refs[output_name].append(ref_block_id)
	_create_block_node(ref_block)
	_bring_stack_to_front(ref_block_id)
	return ref_block

# ============================================
# 坐标转换
# ============================================
func _screen_to_logical(screen_pos: Vector2) -> Vector2:
	return (screen_pos - _canvas.size / 2.0) / _canvas_zoom + _canvas_offset

func _logical_to_screen(logical_pos: Vector2) -> Vector2:
	return (logical_pos - _canvas_offset) * _canvas_zoom + _canvas.size / 2.0

func _is_block_in_viewport(block: Dictionary) -> bool:
	var screen_pos = _logical_to_screen(block.pos)
	var screen_w = _get_block_width(block) * _canvas_zoom
	var screen_h = _get_block_height(block) * _canvas_zoom
	var margin = 300.0
	return screen_pos.x + screen_w > -margin and screen_pos.x < _canvas.size.x + margin and screen_pos.y + screen_h > -margin and screen_pos.y < _canvas.size.y + margin

func _zoom_at(screen_pos: Vector2, factor: float):
	var old_zoom = _canvas_zoom
	_target_zoom = clampf(_target_zoom * factor, 0.1, 10.0)
	var before_logical = (screen_pos - _canvas.size / 2.0) / old_zoom + _canvas_offset
	_target_offset = before_logical - (screen_pos - _canvas.size / 2.0) / _target_zoom
	_canvas_zoom = _target_zoom
	_canvas_offset = _target_offset
	_update_canvas_transform()
	if _grid_bg: _grid_bg.queue_redraw()

func _update_canvas_transform():
	if not _block_container: return
	_block_container.position = Vector2.ZERO
	_block_container.scale = Vector2.ONE
	_refresh_all_block_nodes()

func _update_canvas_transform_light():
	if not _block_container or _is_editing_block_defs: return
	_block_container.position = Vector2.ZERO
	_block_container.scale = Vector2.ONE
	for block in _blocks:
		if not _is_block_in_slot(block.id) and _block_nodes.has(block.id):
			_block_nodes[block.id].position = _logical_to_screen(block.pos)
			_block_nodes[block.id].size = Vector2(
				_get_block_width(block) * _canvas_zoom,
				_get_block_height(block) * _canvas_zoom
			)

func _update_block_node_position(block: Dictionary):
	if not _block_nodes.has(block.id): return
	var node = _block_nodes[block.id]
	node.position = _logical_to_screen(block.pos)

# ============================================
# 积木块操作
# ============================================
func _get_block_by_id(id: int) -> Dictionary:
	return _blocks_by_id.get(id, {})

func _bring_stack_to_front(block_id: int):
	_z_group_counter += 1
	var base_z = min(_z_group_counter, 4095)
	var chain = _get_full_chain(block_id)
	if _is_inner_block(block_id):
		var chain_set2 = {}
		for cid in chain: chain_set2[cid] = true
		var ancestor_id = block_id
		var p = _find_parent_condition(ancestor_id)
		while not p.is_empty():
			ancestor_id = p.id
			p = _find_parent_condition(ancestor_id)
		if ancestor_id != block_id:
			var parent_chain = _get_full_chain(ancestor_id)
			for cid in parent_chain:
				if not chain_set2.has(cid): chain.append(cid); chain_set2[cid] = true
	var chain_set = {}
	for cid in chain: chain_set[cid] = true
	var non_chain = []
	var chain_blocks = []
	for b in _blocks:
		if chain_set.has(b.id): chain_blocks.append(b)
		else: non_chain.append(b)
	_blocks = non_chain + chain_blocks
	var main_chain = []
	for cid in chain:
		if not _is_block_in_slot(cid) and not _is_inner_block(cid):
			main_chain.append(cid)
	var z = base_z + main_chain.size() * 5
	for i in range(main_chain.size()):
		var cid = main_chain[i]
		if _block_nodes.has(cid):
			_block_nodes[cid].z_index = min(z, 4095)
			z -= 1
	for cid in chain:
		if _is_inner_block(cid):
			var parent = _find_parent_condition(cid)
			if not parent.is_empty() and _block_nodes.has(cid) and _block_nodes.has(parent.id):
				_block_nodes[cid].z_index = min(_block_nodes[parent.id].z_index + 5, 4095)
			elif _block_nodes.has(cid):
				_block_nodes[cid].z_index = min(base_z, 4095)

func _get_full_chain(block_id: int) -> Array:
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return [block_id]
	var top = block
	while true:
		var above = _find_block_above(top.id)
		if above.is_empty(): break
		top = above
	var chain = []
	var current = top
	while not current.is_empty():
		chain.append(current.id)
		_collect_dependent_ids(current.id, chain)
		var below = _find_block_below(current.id)
		current = below
	return chain

func _collect_dependent_ids(block_id: int, result: Array):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	for param_name in block.value_slots:
		var vid = block.value_slots[param_name]
		if vid >= 0 and vid not in result:
			result.append(vid)
			_collect_dependent_ids(vid, result)
	if block.def.type == BlockType.CONDITION:
		for iid in block.inner_block_ids + block.inner_else_ids:
			if iid not in result:
				result.append(iid)
				_collect_dependent_ids(iid, result)

func _get_block_at_pos(logical_pos: Vector2) -> int:
	for i in range(_blocks.size() - 1, -1, -1):
		var b = _blocks[i]
		var hit = _hit_test_block(b, logical_pos)
		if hit >= 0: return hit
	return -1

func _hit_test_block(block: Dictionary, logical_pos: Vector2) -> int:
	var def = block.def
	if def.type == BlockType.CONDITION:
		var all_inner = block.inner_else_ids.duplicate()
		all_inner.append_array(block.inner_block_ids)
		for idx in range(all_inner.size() - 1, -1, -1):
			var iid = all_inner[idx]
			var iblock = _get_block_by_id(iid)
			if not iblock.is_empty():
				var hit = _hit_test_block(iblock, logical_pos)
				if hit >= 0: return hit
	for param_name in block.value_slots:
		var vid = block.value_slots[param_name]
		if vid >= 0:
			var vrect = _get_value_block_rect_in_slot(block, param_name)
			if vrect.has_point(logical_pos):
				var vblock = _get_block_by_id(vid)
				if not vblock.is_empty():
					var nested_hit = _hit_test_embedded_value(vblock, vrect, logical_pos)
					if nested_hit >= 0: return nested_hit
				return vid
	var hit_margin = 4.0
	var full_rect = _get_block_rect(block)
	if def.type == BlockType.CONDITION:
		full_rect = Rect2(block.pos.x, block.pos.y, _get_block_width(block), BLOCK_HEIGHT)
	var rect = Rect2(full_rect.position.x + hit_margin, full_rect.position.y, full_rect.size.x - hit_margin * 2, full_rect.size.y)
	if rect.has_point(logical_pos): return block.id
	return -1

func _hit_test_embedded_value(value_block: Dictionary, slot_rect: Rect2, logical_pos: Vector2) -> int:
	for param_name in value_block.value_slots:
		var vid = value_block.value_slots[param_name]
		if vid >= 0:
			var nested_rect = _get_embedded_value_slot_rect(value_block, param_name, slot_rect)
			if nested_rect.has_point(logical_pos):
				var nested_block = _get_block_by_id(vid)
				if not nested_block.is_empty():
					var deeper_hit = _hit_test_embedded_value(nested_block, nested_rect, logical_pos)
					if deeper_hit >= 0: return deeper_hit
				return vid
	return -1

func _get_embedded_value_slot_rect(value_block: Dictionary, param_name: String, parent_slot_rect: Rect2) -> Rect2:
	var segments = _parse_label_template(value_block.def.label)
	var vextra = _count_extra_label_lines(value_block.def.label)
	var vline_h = BLOCK_LINE_HEIGHT * 0.8
	var vtotal_h = (vextra + 1) * vline_h
	var vbase_y = parent_slot_rect.position.y + (parent_slot_rect.size.y - vtotal_h) / 2.0
	var inner_h = vline_h - 4.0
	var x = parent_slot_rect.position.x + 6
	var y = vbase_y + (vline_h - inner_h) / 2.0
	var current_line = 0
	for seg in segments:
		if seg.type == "newline":
			current_line += 1
			x = parent_slot_rect.position.x + 6
			y = vbase_y + current_line * vline_h + (vline_h - inner_h) / 2.0
		elif seg.type == "text":
			x += _estimate_text_width(seg.content)
		elif seg.type == "param":
			var param_def = _find_param_def(value_block.def, seg.name)
			if not param_def.is_empty():
				var slot_w = _get_slot_width(value_block, param_def)
				if seg.name == param_name:
					return Rect2(x, y, slot_w, inner_h)
				x += slot_w + 3
	return Rect2()

func _hit_test_output_port(block: Dictionary, logical_pos: Vector2) -> Dictionary:
	var outputs = _ensure_outputs(block.def)
	if outputs.size() == 0: return {}
	var content_height: float
	if block.def.type == BlockType.CONDITION:
		content_height = _get_block_height(block) - _get_output_area_height(block)
	elif block.def.type == BlockType.EVENT:
		content_height = BLOCK_HEIGHT + HAT_HEIGHT
	else:
		content_height = BLOCK_HEIGHT
	var out_y = block.pos.y + content_height
	for out_def in outputs:
		var out_x = block.pos.x + BLOCK_PADDING_H
		var out_w = _estimate_text_width(out_def.label) + 24
		var out_rect = Rect2(out_x, out_y, out_w, SLOT_HEIGHT)
		if out_rect.has_point(logical_pos):
			return {"block_id": block.id, "output_name": out_def.name}
		out_y += SLOT_HEIGHT + 4
	return {}

func _hit_test_all_output_ports(logical_pos: Vector2) -> Dictionary:
	for i in range(_blocks.size() - 1, -1, -1):
		var b = _blocks[i]
		if _is_block_in_slot(b.id): continue
		var hit = _hit_test_output_port(b, logical_pos)
		if not hit.is_empty(): return hit
	return {}

func _get_block_rect(block: Dictionary) -> Rect2:
	return Rect2(block.pos.x, block.pos.y, _get_block_width(block), _get_block_height(block))

# ---- 标签模板解析 ----
func _parse_label_template(label: String) -> Array:
	var result = []
	var remaining = label
	while remaining.length() > 0:
		var start = remaining.find("{")
		if start < 0:
			if remaining.length() > 0: _split_text_with_newlines(result, remaining)
			break
		if start > 0: _split_text_with_newlines(result, remaining.substr(0, start))
		var end = remaining.find("}", start)
		if end < 0:
			_split_text_with_newlines(result, remaining)
			break
		var param_name = remaining.substr(start + 1, end - start - 1)
		result.append({"type": "param", "name": param_name})
		remaining = remaining.substr(end + 1)
	return result

func _split_text_with_newlines(result: Array, text: String):
	var parts = text.split(";")
	for i in range(parts.size()):
		if i > 0: result.append({"type": "newline"})
		if parts[i].length() > 0: result.append({"type": "text", "content": parts[i]})

func _find_param_def(def: Dictionary, param_name: String) -> Dictionary:
	for p in def.params:
		if p.name == param_name: return p
	return {}

# ---- 参数槽位布局 ----
func _get_param_layout(block: Dictionary, base_pos: Variant = null) -> Array:
	var result = []
	var def = block.def
	var hat_offset = HAT_HEIGHT if def.type == BlockType.EVENT else 0.0
	var segments = _parse_label_template(def.label)
	var pos = base_pos if base_pos != null else block.pos
	var extra_lines = _count_extra_label_lines(def.label)
	var line_h = BLOCK_LINE_HEIGHT
	var content_h = BLOCK_HEIGHT + extra_lines * line_h
	var total_label_h = (extra_lines + 1) * line_h
	var base_y = pos.y + hat_offset + (content_h - total_label_h) / 2.0
	var x = pos.x + BLOCK_PADDING_H
	var y = base_y + (line_h - SLOT_HEIGHT) / 2.0
	var current_line = 0
	for seg in segments:
		if seg.type == "newline":
			current_line += 1
			x = pos.x + BLOCK_PADDING_H
			y = base_y + current_line * line_h + (line_h - SLOT_HEIGHT) / 2.0
		elif seg.type == "text":
			x += _estimate_text_width(seg.content)
		elif seg.type == "param":
			var param_def = _find_param_def(def, seg.name)
			if not param_def.is_empty():
				var slot_w = _get_slot_width(block, param_def)
				result.append({
					"name": seg.name,
					"type": param_def.type,
					"rect": Rect2(x, y, slot_w, SLOT_HEIGHT),
				})
				x += slot_w + SLOT_SPACING
	return result

func _get_slot_width(block: Dictionary, param_def: Dictionary) -> float:
	var param_name = param_def.name
	if _is_slot_type(param_def.type) and block.value_slots.has(param_name) and block.value_slots[param_name] >= 0:
		var vblock = _get_block_by_id(block.value_slots[param_name])
		if not vblock.is_empty():
			return max(SLOT_MIN_WIDTH, _get_block_width(vblock) + 4)
	var val = str(block.params.get(param_name, param_def.default))
	if param_def.type == "vector2":
		var v = block.params.get(param_name, param_def.default)
		if v is Dictionary:
			val = "(%.3f, %.3f)" % [v.get("x", 0.0), v.get("y", 0.0)]
		else:
			val = "(0, 0)"
	elif param_def.type == "vector3":
		var v = block.params.get(param_name, param_def.default)
		if v is Dictionary:
			val = "(%.3f, %.3f, %.3f)" % [v.get("x", 0.0), v.get("y", 0.0), v.get("z", 0.0)]
		else:
			val = "(0, 0, 0)"
	if val == "":
		return SLOT_MIN_WIDTH
	return max(SLOT_MIN_WIDTH, _estimate_text_width(val) + 20)

func _get_value_block_rect_in_slot(block: Dictionary, param_name: String) -> Rect2:
	var layout = _get_param_layout(block)
	for slot in layout:
		if slot.name == param_name:
			return slot.rect
	return Rect2()

# ---- 块尺寸 ----
func _get_block_width(block: Dictionary) -> float:
	var def = block.def
	var segments = _parse_label_template(def.label)
	var line_width = 0.0
	var max_width = 0.0
	for seg in segments:
		if seg.type == "newline":
			max_width = max(max_width, line_width)
			line_width = 0.0
		elif seg.type == "text":
			line_width += _estimate_text_width(seg.content)
		elif seg.type == "param":
			var param_def = _find_param_def(def, seg.name)
			if not param_def.is_empty():
				line_width += _get_slot_width(block, param_def) + SLOT_SPACING
	max_width = max(max_width, line_width)
	var outputs = _ensure_outputs(def)
	for out in outputs:
		var out_label_w = _estimate_text_width("◆ %s" % out.label) + 24
		if out_label_w > max_width:
			max_width = out_label_w
	return max(BLOCK_MIN_WIDTH, max_width + BLOCK_PADDING_H * 2)

func _get_output_area_height(block: Dictionary) -> float:
	var outputs = _ensure_outputs(block.def)
	if outputs.size() == 0: return 0.0
	return outputs.size() * (SLOT_HEIGHT + 4) + 4

func _get_block_height(block: Dictionary) -> float:
	var def = block.def
	if def.type == BlockType.CONDITION:
		var then_h = _get_inner_area_height(block.inner_block_ids)
		if def.name == "if_else":
			var else_h = _get_inner_area_height(block.inner_else_ids)
			return BLOCK_HEIGHT + INNER_PADDING + (INNER_PADDING + then_h) + INNER_PADDING + ELSE_HEADER_HEIGHT + INNER_PADDING + (INNER_PADDING + else_h) + INNER_PADDING + _get_output_area_height(block)
		else:
			return BLOCK_HEIGHT + INNER_PADDING + (INNER_PADDING + then_h) + INNER_PADDING + _get_output_area_height(block)
	if def.type == BlockType.EVENT:
		return BLOCK_HEIGHT + HAT_HEIGHT + _get_output_area_height(block)
	var extra_lines = _count_extra_label_lines(def.label)
	return BLOCK_HEIGHT + extra_lines * BLOCK_LINE_HEIGHT + _get_output_area_height(block)

func _count_extra_label_lines(label: String) -> int:
	var count = label.split(";").size() - 1
	return max(0, count)

func _get_inner_area_height(inner_ids: Array) -> float:
	if inner_ids.is_empty(): return MIN_INNER_HEIGHT
	var total = 0.0
	for iid in inner_ids:
		var iblock = _get_block_by_id(iid)
		if not iblock.is_empty():
			total += _get_block_height(iblock)
	return max(MIN_INNER_HEIGHT, total)

func _is_slot_type(param_type: String) -> bool:
	return param_type in ["number", "bool", "dropdown", "node", "vector2", "vector3", "color", "string", "expr"]

func _ensure_outputs(def: Dictionary) -> Array:
	return def.get("outputs", [])

func _get_output_color(type: String) -> Color:
	match type:
		"number": return Color(0.35, 0.78, 0.38)
		"string": return Color(0.7, 0.5, 0.3)
		"bool": return Color(0.8, 0.3, 0.3)
		"node": return Color(0.6, 0.5, 1.0)
		"vector2": return Color(0.95, 0.55, 0.4)
		"vector3": return Color(0.9, 0.4, 0.7)
		"color": return Color(1.0, 0.4, 0.7)
		_: return Color.GRAY

func _estimate_text_width(text: String) -> float:
	var lines = text.split("\n")
	var max_w = 0.0
	for line in lines:
		var w = 0.0
		for ch in line:
			var code = ch.unicode_at(0)
			if code >= 0x4E00 and code <= 0x9FFF:  # CJK
				w += 13.0
			elif code >= 0x3000 and code <= 0x303F:  # CJK标点
				w += 13.0
			elif code >= 0xFF00 and code <= 0xFFEF:  # 全角
				w += 13.0
			else:
				w += 8.5
		max_w = max(max_w, w)
	return max_w

# ---- 关系查询 ----
func _is_block_in_slot(block_id: int) -> bool:
	return _slot_block_ids.has(block_id)

func _is_inner_block(block_id: int) -> bool:
	return _inner_block_ids_set.has(block_id)

func _find_parent_condition(block_id: int) -> Dictionary:
	for b in _blocks:
		var result = _find_parent_condition_recursive(b, block_id)
		if not result.is_empty(): return result
	return {}

func _find_parent_condition_recursive(cond_block: Dictionary, target_id: int) -> Dictionary:
	if cond_block.def.type != BlockType.CONDITION: return {}
	if target_id in cond_block.inner_block_ids or target_id in cond_block.inner_else_ids:
		return cond_block
	for iid in cond_block.inner_block_ids + cond_block.inner_else_ids:
		var inner_b = _get_block_by_id(iid)
		if not inner_b.is_empty() and inner_b.def.type == BlockType.CONDITION:
			var result = _find_parent_condition_recursive(inner_b, target_id)
			if not result.is_empty(): return result
	return {}

func _find_inner_slot(condition_block: Dictionary, block_id: int) -> String:
	if block_id in condition_block.inner_block_ids: return "then"
	if block_id in condition_block.inner_else_ids: return "else"
	return ""

func _find_slot_parent(block_id: int) -> Dictionary:
	for b in _blocks:
		for param_name in b.value_slots:
			if b.value_slots[param_name] == block_id:
				return b
	return {}

func _find_top_level_parent(block_id: int) -> Dictionary:
	if not _is_block_in_slot(block_id):
		return _get_block_by_id(block_id)
	var parent = _find_slot_parent(block_id)
	if parent.is_empty():
		return _get_block_by_id(block_id)
	return _find_top_level_parent(parent.id)

func _remove_block_from_slot(block_id: int):
	for b in _blocks:
		for param_name in b.value_slots:
			if b.value_slots[param_name] == block_id:
				b.value_slots[param_name] = -1
				_slot_block_ids.erase(block_id)
				return

func _rebuild_indexes():
	_blocks_by_id.clear()
	_slot_block_ids.clear()
	_inner_block_ids_set.clear()
	for b in _blocks:
		_blocks_by_id[b.id] = b
		for param_name in b.value_slots:
			var vid = b.value_slots[param_name]
			if vid >= 0:
				_slot_block_ids[vid] = true
		if b.def.type == BlockType.CONDITION:
			_rebuild_inner_indexes_recursive(b)

func _rebuild_inner_indexes_recursive(cond_block: Dictionary):
	for iid in cond_block.inner_block_ids:
		_inner_block_ids_set[iid] = true
		var inner_b = _get_block_by_id(iid)
		if not inner_b.is_empty() and inner_b.def.type == BlockType.CONDITION:
			_rebuild_inner_indexes_recursive(inner_b)
	for iid in cond_block.inner_else_ids:
		_inner_block_ids_set[iid] = true
		var inner_b = _get_block_by_id(iid)
		if not inner_b.is_empty() and inner_b.def.type == BlockType.CONDITION:
			_rebuild_inner_indexes_recursive(inner_b)

# ---- 删除 ----
func _delete_block(id: int):
	var ids_to_delete = _collect_all_dependent_ids(id)
	ids_to_delete.append(id)
	for did in ids_to_delete:
		var del_block = _get_block_by_id(did)
		if not del_block.is_empty() and del_block.get("is_var_ref", false):
			var source_id = del_block.get("source_block_id", -1)
			var out_name = del_block.get("output_name", "")
			if source_id >= 0:
				var source_block = _get_block_by_id(source_id)
				if not source_block.is_empty() and source_block.has("output_refs") and source_block.output_refs.has(out_name):
					source_block.output_refs[out_name].erase(did)
	for did in ids_to_delete:
		var del_block = _get_block_by_id(did)
		if del_block.is_empty(): continue
		for b in _blocks:
			if b.get("stack_below_id", -1) == did:
				b.stack_below_id = del_block.get("stack_below_id", -1)
				break
	for b in _blocks:
		if b.def.type == BlockType.CONDITION:
			for did in ids_to_delete:
				b.inner_block_ids.erase(did)
				b.inner_else_ids.erase(did)
			_erase_inner_ids_recursive(b, ids_to_delete)
	for did in ids_to_delete:
		for b in _blocks:
			for pname in b.value_slots:
				if b.value_slots[pname] == did:
					b.value_slots[pname] = -1
	for did in ids_to_delete:
		_remove_block_node(did)
	_blocks = _blocks.filter(func(b): return b.id not in ids_to_delete)
	_rebuild_indexes()
	_relayout_all_conditions()
	_refresh_all_block_nodes()
	if _selected_block_id in ids_to_delete:
		_selected_block_id = -1
		_update_prop_panel()

func _erase_inner_ids_recursive(cond_block: Dictionary, ids_to_delete: Array):
	for iid in cond_block.inner_block_ids + cond_block.inner_else_ids:
		var inner_b = _get_block_by_id(iid)
		if not inner_b.is_empty() and inner_b.def.type == BlockType.CONDITION:
			for did in ids_to_delete:
				inner_b.inner_block_ids.erase(did)
				inner_b.inner_else_ids.erase(did)
			_erase_inner_ids_recursive(inner_b, ids_to_delete)

func _collect_all_dependent_ids(block_id: int) -> Array:
	var result = []
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return result
	var stack_ids = _get_stack_below(block_id)
	for i in range(1, stack_ids.size()):
		result.append(stack_ids[i])
		result += _collect_all_dependent_ids(stack_ids[i])
	for param_name in block.value_slots:
		var vid = block.value_slots[param_name]
		if vid >= 0:
			result.append(vid)
			result += _collect_all_dependent_ids(vid)
	if block.def.type == BlockType.CONDITION:
		for iid in block.inner_block_ids + block.inner_else_ids:
			result.append(iid)
			result += _collect_all_dependent_ids(iid)
	if block.has("output_refs"):
		for out_name in block.output_refs:
			for ref_id in block.output_refs[out_name]:
				if ref_id not in result:
					result.append(ref_id)
					result += _collect_all_dependent_ids(ref_id)
	for b in _blocks:
		if b.has("output_refs"):
			for out_name in b.output_refs:
				for ref_id in b.output_refs[out_name]:
					if ref_id == block_id and b.id not in result:
						pass
	return result

# ---- 堆叠检测 ----
func _find_block_above(block_id: int) -> Dictionary:
	for b in _blocks:
		if b.get("stack_below_id", -1) == block_id:
			return b
	return {}

func _find_block_below(block_id: int) -> Dictionary:
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return {}
	var below_id = block.get("stack_below_id", -1)
	if below_id >= 0:
		return _get_block_by_id(below_id)
	return {}

func _get_stack_below(block_id: int) -> Array:
	var result = [block_id]
	var current = _get_block_by_id(block_id)
	while not current.is_empty():
		var below_id = current.get("stack_below_id", -1)
		if below_id < 0: break
		var below_block = _get_block_by_id(below_id)
		if below_block.is_empty(): break
		result.append(below_id)
		current = below_block
	return result

func _blocks_overlap_x(x1: float, w1: float, x2: float, w2: float) -> bool:
	var overlap = min(x1 + w1, x2 + w2) - max(x1, x2)
	return overlap > w1 * 0.3 or overlap > w2 * 0.3

func _collect_attached_blocks(block_id: int) -> Array:
	var stack = _get_stack_below(block_id)
	var result = stack.duplicate()
	var i = 0
	while i < result.size():
		var bid = result[i]
		var b = _get_block_by_id(bid)
		if b.is_empty():
			i += 1
			continue
		for param_name in b.value_slots:
			var vid = b.value_slots[param_name]
			if vid >= 0 and vid not in result:
				result.append(vid)
		if b.def.type == BlockType.CONDITION:
			for iid in b.inner_block_ids + b.inner_else_ids:
				if iid not in result:
					result.append(iid)
		i += 1
	return result

# ============================================
# 拖拽与吸附
# ============================================

func _on_canvas_input(event: InputEvent):
	if event is InputEventKey:
		pass  # Ctrl+S/Z/Y 已在 _input() 全局处理
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var logical = _screen_to_logical(event.position)
				_mouse_logical = logical
				var port_hit = _hit_test_all_output_ports(logical)
				if not port_hit.is_empty():
					_potential_output_drag = port_hit
					_drag_start_pos = event.position
					_drag_started = false
					return
				var clicked_id = _get_block_at_pos(logical)
				if clicked_id >= 0:
					var old_selected = _selected_block_id
					_selected_block_id = clicked_id
					var front_id = clicked_id
					if _is_block_in_slot(clicked_id):
						var top_parent = _find_top_level_parent(clicked_id)
						if not top_parent.is_empty(): front_id = top_parent.id
					elif _is_inner_block(clicked_id):
						var parent = _find_parent_condition(clicked_id)
						if not parent.is_empty(): front_id = parent.id
					if old_selected >= 0 and old_selected != clicked_id:
						_refresh_block_node(old_selected)
					_refresh_block_node(clicked_id)
					_bring_stack_to_front(front_id)
					_potential_drag_id = clicked_id
					_drag_start_pos = event.position
					_drag_started = false
					_dragging_block_ids.clear()
					_drag_offsets.clear()
					_update_prop_panel()
				else:
					var old_selected = _selected_block_id
					_selected_block_id = -1
					if old_selected >= 0:
						_refresh_block_node(old_selected)
					_potential_drag_id = -1
					_dragging_block_ids.clear()
					_drag_offsets.clear()
					_update_prop_panel()
			else:
				var was_drag = false
				if _drag_started and _dragging_block_ids.size() > 0:
					was_drag = true
					if _is_over_trash(event.position):
						_save_undo_state()
						_delete_block(_dragging_block_ids[0])
					else:
						_save_undo_state()
						_snap_touched_inner = false
						_snap_touched_slot = false
						_snap_touched_stack = false
						var snapped = _try_snap_to_inner(_mouse_logical)
						if not snapped and _dragging_block_ids.size() == 1:
							var drag_block = _get_block_by_id(_dragging_block_ids[0])
							if not drag_block.is_empty() and drag_block.def.type == BlockType.VALUE:
								snapped = _try_snap_to_slot(_dragging_block_ids[0])
								_snap_touched_slot = snapped
						if not snapped:
							_try_snap_stack(_dragging_block_ids[0])
						if _snap_touched_inner or _snap_touched_slot or _snap_touched_stack:
							_rebuild_indexes()
							_deferred_post_snap_refresh()
						else:
							_reposition_all_chains()
							for block in _blocks:
								if not _is_block_in_slot(block.id) and _block_nodes.has(block.id):
									var new_pos = _logical_to_screen(block.pos)
									if _block_nodes[block.id].position != new_pos:
										_block_nodes[block.id].position = new_pos
				if not was_drag and _selected_block_id >= 0:
					_try_start_inline_edit(event.position)
				var snap_occurred = _snap_touched_inner or _snap_touched_slot or _snap_touched_stack
				_hover_slot_info = {}
				_output_port_info = {}
				_snap_line.visible = false
				_set_dragging_modulate(false)
				if _selected_block_id >= 0 and not snap_occurred:
					_bring_stack_to_front(_selected_block_id)
				_dragging_block_ids.clear()
				_drag_offsets.clear()
				_potential_drag_id = -1
				_potential_output_drag = {}
				_drag_started = false
				_update_trash_highlight(false)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_is_panning = true
				_pan_start = event.position
				_pan_offset_start = _canvas_offset
			else:
				_is_panning = false
				_refresh_all_block_nodes()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				var logical = _screen_to_logical(event.position)
				var clicked_id = _get_block_at_pos(logical)
				if clicked_id >= 0:
					var old_selected = _selected_block_id
					_selected_block_id = clicked_id
					if old_selected >= 0 and old_selected != clicked_id:
						_refresh_block_node(old_selected)
					_refresh_block_node(clicked_id)
					_update_prop_panel()
					_context_menu_rclick_id = clicked_id
				else:
					_context_menu_rclick_id = -1
				_context_menu.set_item_disabled(0, clicked_id < 0)
				_context_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i(1, 1)))
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.1)
	elif event is InputEventMouseMotion:
		# 左键已松开但拖拽状态残留（如模态框关闭后），清理
		if _potential_drag_id >= 0 and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_potential_drag_id = -1
			_dragging_block_ids.clear()
			_drag_offsets.clear()
			_drag_started = false
		var logical = _screen_to_logical(event.position)
		_mouse_logical = logical
		# 悬停高亮追踪
		if not _drag_started and _potential_drag_id < 0:
			var under_id = _get_block_at_pos(logical)
			if under_id != _hovered_block_id:
				var old_hover = _hovered_block_id
				_hovered_block_id = under_id
				if old_hover >= 0 and _block_nodes.has(old_hover):
					_queue_block_redraw(old_hover)
				if _hovered_block_id >= 0 and _block_nodes.has(_hovered_block_id):
					_queue_block_redraw(_hovered_block_id)
		_output_port_info = _hit_test_all_output_ports(logical)
		if not _potential_output_drag.is_empty() and not _drag_started:
			if event.position.distance_to(_drag_start_pos) > DRAG_THRESHOLD:
				_drag_started = true
				_save_undo_state()
				var port_hit = _potential_output_drag
				var ref_block = _create_var_ref_block(port_hit.block_id, port_hit.output_name)
				if not ref_block.is_empty():
					_selected_block_id = ref_block.id
					_potential_drag_id = ref_block.id
					_dragging_block_ids = [ref_block.id]
					_drag_offsets[ref_block.id] = Vector2.ZERO
					_bring_stack_to_front(ref_block.id)
					_update_prop_panel()
				_potential_output_drag = {}
		if _potential_drag_id >= 0 and not _drag_started:
			if event.position.distance_to(_drag_start_pos) > DRAG_THRESHOLD:
				_drag_started = true
				_save_undo_state()
				_start_drag(_potential_drag_id, _mouse_logical)
		if _drag_started and _dragging_block_ids.size() > 0:
			for bid in _dragging_block_ids:
				var b = _get_block_by_id(bid)
				if b:
					b.pos = _mouse_logical + _drag_offsets[bid]
			var old_hover_slot = _hover_slot_info.duplicate()
			if _dragging_block_ids.size() == 1:
				var drag_block = _get_block_by_id(_dragging_block_ids[0])
				if not drag_block.is_empty() and drag_block.def.type == BlockType.VALUE:
					_hover_slot_info = _find_nearest_slot(drag_block, _mouse_logical)
				else:
					_hover_slot_info = {}
			else:
				_hover_slot_info = {}
			if _hover_slot_info != old_hover_slot:
				_update_slot_hover_style(old_hover_slot, false)
				_update_slot_hover_style(_hover_slot_info, true)
			_update_snap_line()
			_update_dragging_positions()
			_update_trash_highlight(_is_over_trash(event.position))
		elif _is_panning:
			var delta = event.position - _pan_start
			_canvas_offset = _pan_offset_start - delta / _canvas_zoom
			_update_canvas_transform_light()

func _set_drag_top_z():
	_z_group_counter += 1
	var top_z = _z_group_counter * 1000
	for bid in _dragging_block_ids:
		if _block_nodes.has(bid):
			_block_nodes[bid].z_index = top_z

func _start_drag(block_id: int, logical_pos: Vector2):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return

	if _is_block_in_slot(block_id):
		var parent_block = _find_slot_parent(block_id)
		_remove_block_from_slot(block_id)
		if not parent_block.is_empty():
			var top_parent = _find_top_level_parent(parent_block.id)
			if not top_parent.is_empty():
				_refresh_block_node(top_parent.id)
			else:
				_refresh_block_node(parent_block.id)
		block.pos = logical_pos
		_dragging_block_ids = [block_id]
		_drag_offsets[block_id] = Vector2.ZERO
		_ensure_block_node(block_id)
		_set_drag_top_z()
		_set_dragging_modulate(true)
		return

	var parent_cond = _find_parent_condition(block_id)
	if not parent_cond.is_empty():
		var slot = _find_inner_slot(parent_cond, block_id)
		var ids = parent_cond.inner_block_ids if slot == "then" else parent_cond.inner_else_ids
		var idx = ids.find(block_id)
		if idx >= 0:
			var drag_ids = ids.slice(idx)
			if slot == "then":
				parent_cond.inner_block_ids = parent_cond.inner_block_ids.slice(0, idx)
				_rebuild_inner_stack_chain(parent_cond.inner_block_ids)
			else:
				parent_cond.inner_else_ids = parent_cond.inner_else_ids.slice(0, idx)
				_rebuild_inner_stack_chain(parent_cond.inner_else_ids)
			for did in drag_ids:
				_inner_block_ids_set.erase(did)
			_layout_inner_blocks(parent_cond)
			_relayout_all_conditions()
			_sync_condition_visual_positions(parent_cond)
			_dragging_block_ids = drag_ids.duplicate()
			_drag_offsets.clear()
			for bid in _dragging_block_ids:
				var b = _get_block_by_id(bid)
				if not b.is_empty():
					_drag_offsets[bid] = b.pos - logical_pos
				_ensure_block_node(bid)
		else:
			_dragging_block_ids = [block_id]
			_drag_offsets[block_id] = block.pos - logical_pos
			_refresh_block_node(parent_cond.id)
		_set_drag_top_z()
		_set_dragging_modulate(true)
		return

	if block.def.type == BlockType.VALUE:
		_dragging_block_ids = [block_id]
		_drag_offsets[block_id] = block.pos - logical_pos
		var above_block = _find_block_above(block_id)
		if not above_block.is_empty():
			above_block.stack_below_id = -1
		_ensure_block_node(block_id)
		_set_drag_top_z()
		_set_dragging_modulate(true)
		return

	_dragging_block_ids = _collect_attached_blocks(block_id)
	_drag_offsets.clear()
	var above_block = _find_block_above(block_id)
	if not above_block.is_empty():
		above_block.stack_below_id = -1
	for bid in _dragging_block_ids:
		var b = _get_block_by_id(bid)
		if not b.is_empty():
			_drag_offsets[bid] = b.pos - logical_pos
		_ensure_block_node(bid)
	_set_drag_top_z()
	_set_dragging_modulate(true)

# ---- 吸附核心（基于鼠标位置） ----
func _try_snap_stack(top_block_id: int):
	var snap_info = _find_snap_stack_target(top_block_id)
	if snap_info.is_empty(): return
	_snap_touched_stack = true
	var top_block = _get_block_by_id(top_block_id)
	var target = _get_block_by_id(snap_info.target_id)
	var mode = snap_info.get("mode", "below")
	if snap_info.has("parent_cond_id"):
		_snap_into_inner(top_block_id, snap_info)
		return
	if mode == "insert":
		var dx = target.pos.x - top_block.pos.x
		var dy = snap_info.snap_y - top_block.pos.y
		var drag_stack = _get_stack_below(top_block_id)
		var drag_chain_height = 0.0
		for bid in drag_stack:
			var b = _get_block_by_id(bid)
			if not b.is_empty(): drag_chain_height += _get_block_height(b)
		for bid in _dragging_block_ids:
			var b = _get_block_by_id(bid)
			if not b.is_empty():
				b.pos.x += dx
				b.pos.y += dy
		var target_stack = _get_stack_below(target.id)
		var pushed_ids: Dictionary = {}
		for bid in target_stack:
			var below_b = _get_block_by_id(bid)
			if not below_b.is_empty():
				below_b.pos.y += drag_chain_height
				pushed_ids[bid] = true
		for bid in pushed_ids:
			_move_inner_blocks_with_parent(bid, 0.0, drag_chain_height)
		var above_target = _find_block_above(target.id)
		if not above_target.is_empty():
			above_target.stack_below_id = top_block_id
		if drag_stack.size() > 0:
			var last_stack_id = drag_stack[-1]
			var last_stack_block = _get_block_by_id(last_stack_id)
			if not last_stack_block.is_empty():
				last_stack_block.stack_below_id = target.id
		return
	var dx = target.pos.x - top_block.pos.x
	var dy = snap_info.snap_y - top_block.pos.y
	var drag_stack = _get_stack_below(top_block_id)
	var drag_chain_height = 0.0
	for bid in drag_stack:
		var b = _get_block_by_id(bid)
		if not b.is_empty(): drag_chain_height += _get_block_height(b)
	for bid in _dragging_block_ids:
		var b = _get_block_by_id(bid)
		if not b.is_empty():
			b.pos.x += dx
			b.pos.y += dy
	var stack_below = _get_stack_below(snap_info.target_id)
	if stack_below.size() > 1:
		for i in range(1, stack_below.size()):
			var below_b = _get_block_by_id(stack_below[i])
			if not below_b.is_empty():
				below_b.pos.y += drag_chain_height
		for i in range(1, stack_below.size()):
			_move_inner_blocks_with_parent(stack_below[i], 0.0, drag_chain_height)
	var original_below_id = target.get("stack_below_id", -1)
	target.stack_below_id = top_block_id
	if drag_stack.size() > 0:
		var last_stack_id = drag_stack[-1]
		var last_stack_block = _get_block_by_id(last_stack_id)
		if not last_stack_block.is_empty():
			last_stack_block.stack_below_id = original_below_id

func _snap_into_inner(top_block_id: int, snap_info: Dictionary):
	_snap_touched_inner = true
	var parent_cond = _get_block_by_id(snap_info.parent_cond_id)
	if parent_cond.is_empty(): return
	var slot = snap_info.slot
	var target_id = snap_info.target_id
	var mode = snap_info.get("mode", "below")
	var inner_list: Array = parent_cond.inner_block_ids if slot == "then" else parent_cond.inner_else_ids
	var target_index = inner_list.find(target_id)
	if target_index < 0: return
	var drag_stack = _get_stack_below(top_block_id)
	_remove_blocks_from_previous_context(drag_stack)
	for bid in drag_stack:
		inner_list.erase(bid)
	target_index = inner_list.find(target_id)
	if target_index < 0: return
	var insert_index = target_index if mode == "insert" else target_index + 1
	for i in range(drag_stack.size()):
		inner_list.insert(insert_index + i, drag_stack[i])
	for i in range(inner_list.size()):
		var cur_b = _get_block_by_id(inner_list[i])
		if cur_b.is_empty(): continue
		if i + 1 < inner_list.size():
			cur_b.stack_below_id = inner_list[i + 1]
		else:
			cur_b.stack_below_id = -1
	for bid in drag_stack:
		_inner_block_ids_set[bid] = true
	_layout_inner_blocks(parent_cond)
	_relayout_all_conditions()

func _remove_blocks_from_previous_context(block_ids: Array):
	if block_ids.is_empty(): return
	var top_id = block_ids[0]
	var bottom_id = block_ids[-1]
	var above_block = _find_block_above(top_id)
	if not above_block.is_empty():
		var bottom_block = _get_block_by_id(bottom_id)
		var old_below = -1
		if not bottom_block.is_empty(): old_below = bottom_block.get("stack_below_id", -1)
		above_block.stack_below_id = old_below
	for b in _blocks:
		if b.def.type == BlockType.CONDITION:
			for bid in block_ids:
				b.inner_block_ids.erase(bid)
				b.inner_else_ids.erase(bid)
			_remove_from_inner_recursive(b, block_ids)
	for bid in block_ids:
		_inner_block_ids_set.erase(bid)

func _remove_from_inner_recursive(cond_block: Dictionary, block_ids: Array):
	for iid in cond_block.inner_block_ids + cond_block.inner_else_ids:
		var inner_b = _get_block_by_id(iid)
		if not inner_b.is_empty() and inner_b.def.type == BlockType.CONDITION:
			for bid in block_ids:
				inner_b.inner_block_ids.erase(bid)
				inner_b.inner_else_ids.erase(bid)
			_remove_from_inner_recursive(inner_b, block_ids)

# ---- 查找堆叠吸附目标（基于鼠标位置） ----
func _find_snap_stack_target(top_block_id: int) -> Dictionary:
	var top_block = _get_block_by_id(top_block_id)
	if top_block.is_empty(): return {}
	if top_block.def.type == BlockType.VALUE: return {}
	if top_block.def.type == BlockType.EVENT: return {}
	var drag_stack = _get_stack_below(top_block_id)
	var drag_ids_set = {}
	for bid in drag_stack: drag_ids_set[bid] = true
	for bid in _dragging_block_ids: drag_ids_set[bid] = true
	var best_target_id = -1
	var best_dist = BLOCK_SNAP_DISTANCE
	var best_snap_y: float = 0.0
	var best_mode: String = "below"
	var candidates: Array = []
	for other in _blocks:
		if _is_block_in_slot(other.id): continue
		if other.def.type == BlockType.VALUE: continue
		candidates.append(other)
	for other in candidates:
		if other.id in drag_ids_set: continue
		if top_block.def.type == BlockType.EVENT and _is_inner_block(other.id): continue
		var x_overlap = _blocks_overlap_x(other.pos.x, _get_block_width(other), top_block.pos.x, _get_block_width(top_block))
		if not x_overlap: continue
		var mouse_y = _mouse_logical.y
		var other_bottom = other.pos.y + _get_block_height(other)
		var below_dist = abs(mouse_y - other_bottom)
		if below_dist < best_dist:
			best_dist = below_dist
			best_target_id = other.id
			best_snap_y = other_bottom
			best_mode = "below"
		if other.def.type != BlockType.EVENT:
			var insert_y = other.pos.y
			var insert_dist = abs(mouse_y - insert_y)
			if insert_dist < best_dist:
				best_dist = insert_dist
				best_target_id = other.id
				best_snap_y = insert_y
				best_mode = "insert"
	if best_target_id >= 0:
		var result = {"target_id": best_target_id, "snap_y": best_snap_y, "mode": best_mode}
		if _is_inner_block(best_target_id):
			var parent_cond = _find_parent_condition(best_target_id)
			if not parent_cond.is_empty():
				result["parent_cond_id"] = parent_cond.id
				result["slot"] = _find_inner_slot(parent_cond, best_target_id)
		return result
	return {}

func _try_snap_to_slot(block_id: int) -> bool:
	var block = _get_block_by_id(block_id)
	if block.is_empty() or block.def.type != BlockType.VALUE: return false
	if _hover_slot_info.is_empty(): return false
	var parent_id = _hover_slot_info.block_id
	var param_name = _hover_slot_info.param_name
	var parent = _get_block_by_id(parent_id)
	if parent.is_empty(): return false
	if parent.value_slots.has(param_name) and parent.value_slots[param_name] >= 0:
		var existing_id = parent.value_slots[param_name]
		var existing_block = _get_block_by_id(existing_id)
		if not existing_block.is_empty():
			var top_parent = _find_top_level_parent(parent_id)
			if not top_parent.is_empty():
				existing_block.pos = top_parent.pos + Vector2(0, _get_block_height(top_parent) + 10)
			else:
				existing_block.pos = parent.pos + Vector2(0, _get_block_height(parent) + 10)
	var above = _find_block_above(block_id)
	var below_id = block.get("stack_below_id", -1)
	if not above.is_empty():
		above.stack_below_id = below_id
	parent.value_slots[param_name] = block_id
	_slot_block_ids[block_id] = true
	block.stack_below_id = -1
	_layout_inner_blocks(parent)
	_remove_block_node(block_id)
	var top_parent = _find_top_level_parent(parent_id)
	if not top_parent.is_empty():
		_refresh_block_node(top_parent.id)
	else:
		_refresh_block_node(parent.id)
	return true

func _find_nearest_slot(drag_block: Dictionary, mouse_logical: Vector2) -> Dictionary:
	var best = {}
	var best_dist = SLOT_SNAP_DIST
	var all_slots = _collect_all_accessible_slots(mouse_logical, best_dist)
	if not all_slots.is_empty():
		best = all_slots
	return best

func _collect_all_accessible_slots(mouse_logical: Vector2, best_dist: float) -> Dictionary:
	var best = {}
	for b in _blocks:
		if b.id in _dragging_block_ids: continue
		if _is_block_in_slot(b.id): continue
		var result = _collect_slots_recursive(b, b.pos, mouse_logical, best_dist)
		if not result.is_empty():
			best = result
			best_dist = result._dist
	return best

func _collect_slots_recursive(block: Dictionary, base_pos: Vector2, mouse_logical: Vector2, best_dist: float, is_embedded: bool = false) -> Dictionary:
	var best = {}
	if is_embedded:
		best = _collect_embedded_slots_recursive(block, base_pos, mouse_logical, best_dist)
	else:
		var layout = _get_param_layout(block, base_pos)
		for slot in layout:
			if not _is_slot_type(slot.type): continue
			var has_embedded = block.value_slots.has(slot.name) and block.value_slots[slot.name] >= 0
			if has_embedded:
				var embedded_id = block.value_slots[slot.name]
				if embedded_id in _dragging_block_ids: continue
				var embedded_block = _get_block_by_id(embedded_id)
				if not embedded_block.is_empty():
					var embedded_base = Vector2(
						slot.rect.position.x + 6 - BLOCK_PADDING_H,
						slot.rect.position.y + 3 - (BLOCK_HEIGHT - SLOT_HEIGHT) / 2.0
					)
					var sub_result = _collect_slots_recursive(embedded_block, embedded_base, mouse_logical, best_dist, true)
					if not sub_result.is_empty():
						best = sub_result
						best_dist = sub_result._dist
			else:
				var slot_center = slot.rect.position + slot.rect.size / 2
				var dist = mouse_logical.distance_to(slot_center)
				if dist < best_dist:
					best_dist = dist
					best = {"block_id": block.id, "param_name": slot.name, "_dist": dist}
	return best

func _collect_embedded_slots_recursive(value_block: Dictionary, base_pos: Vector2, mouse_logical: Vector2, best_dist: float) -> Dictionary:
	var best = {}
	var segments = _parse_label_template(value_block.def.label)
	var vextra = _count_extra_label_lines(value_block.def.label)
	var vline_h = BLOCK_LINE_HEIGHT * 0.8
	var vtotal_h = (vextra + 1) * vline_h
	var vbase_y = base_pos.y + (BLOCK_HEIGHT - vtotal_h) / 2.0
	var inner_h = vline_h - 4.0
	var x = base_pos.x + BLOCK_PADDING_H
	var y = vbase_y + (vline_h - inner_h) / 2.0
	var current_line = 0
	for seg in segments:
		if seg.type == "newline":
			current_line += 1
			x = base_pos.x + BLOCK_PADDING_H
			y = vbase_y + current_line * vline_h + (vline_h - inner_h) / 2.0
		elif seg.type == "text":
			x += _estimate_text_width(seg.content)
		elif seg.type == "param":
			var param_def = _find_param_def(value_block.def, seg.name)
			if not param_def.is_empty():
				var slot_w = _get_slot_width(value_block, param_def)
				if _is_slot_type(param_def.type):
					var has_embedded = value_block.value_slots.has(seg.name) and value_block.value_slots[seg.name] >= 0
					if has_embedded:
						var embedded_id = value_block.value_slots[seg.name]
						if embedded_id not in _dragging_block_ids:
							var embedded_block = _get_block_by_id(embedded_id)
							if not embedded_block.is_empty():
								var embedded_base = Vector2(
									x + 6 - BLOCK_PADDING_H,
									y + 2 - (BLOCK_HEIGHT - vtotal_h) / 2.0
								)
								var sub_result = _collect_embedded_slots_recursive(embedded_block, embedded_base, mouse_logical, best_dist)
								if not sub_result.is_empty():
									best = sub_result
									best_dist = sub_result._dist
					else:
						var slot_center = Vector2(x + slot_w / 2, y + inner_h / 2)
						var dist = mouse_logical.distance_to(slot_center)
						if dist < best_dist:
							best_dist = dist
							best = {"block_id": value_block.id, "param_name": seg.name, "_dist": dist}
				x += slot_w + 3
	return best

func _try_snap_to_inner(mouse_logical: Vector2) -> bool:
	if _dragging_block_ids.is_empty(): return false
	var top_block = _get_block_by_id(_dragging_block_ids[0])
	if top_block.is_empty(): return false
	if top_block.def.type == BlockType.VALUE: return false
	var all_conditions: Array = _collect_all_condition_blocks()
	all_conditions.sort_custom(func(a, b): return _get_condition_depth(a.id) > _get_condition_depth(b.id))
	for b in all_conditions:
		if b.id in _dragging_block_ids: continue
		var layout = _get_condition_layout(b)
		var expanded_then = layout.then_rect.grow(BLOCK_SNAP_DISTANCE)
		if expanded_then.has_point(mouse_logical):
			var insert_idx = _find_insert_index_in_region(b.inner_block_ids, mouse_logical)
			_snap_touched_inner = true
			var drag_stack = _get_stack_below(_dragging_block_ids[0])
			_remove_blocks_from_previous_context(drag_stack)
			for bid in _dragging_block_ids:
				if bid not in b.inner_block_ids:
					b.inner_block_ids.insert(insert_idx, bid)
					_inner_block_ids_set[bid] = true
			_rebuild_inner_stack_chain(b.inner_block_ids)
			_layout_inner_blocks(b)
			_relayout_all_conditions()
			return true
		if b.def.name == "if_else" and layout.has("else_rect"):
			var expanded_else = layout.else_rect.grow(BLOCK_SNAP_DISTANCE)
			if expanded_else.has_point(mouse_logical):
				var insert_idx = _find_insert_index_in_region(b.inner_else_ids, mouse_logical)
				_snap_touched_inner = true
				var drag_stack = _get_stack_below(_dragging_block_ids[0])
				_remove_blocks_from_previous_context(drag_stack)
				for bid in _dragging_block_ids:
					if bid not in b.inner_else_ids:
						b.inner_else_ids.insert(insert_idx, bid)
						_inner_block_ids_set[bid] = true
				_rebuild_inner_stack_chain(b.inner_else_ids)
				_layout_inner_blocks(b)
				_relayout_all_conditions()
				return true
	return false

func _find_insert_index_in_region(inner_list: Array, mouse_pos: Vector2) -> int:
	if inner_list.is_empty(): return 0
	var min_dist = INF
	var insert_idx = inner_list.size()
	for i in range(inner_list.size()):
		var bid = inner_list[i]
		var b = _get_block_by_id(bid)
		if b.is_empty(): continue
		var center_y = b.pos.y + _get_block_height(b) / 2
		var dist = abs(mouse_pos.y - center_y)
		if dist < min_dist:
			min_dist = dist
			if mouse_pos.y < center_y:
				insert_idx = i
			else:
				insert_idx = i + 1
	return clamp(insert_idx, 0, inner_list.size())

func _rebuild_inner_stack_chain(inner_list: Array):
	for i in range(inner_list.size()):
		var cur_b = _get_block_by_id(inner_list[i])
		if cur_b.is_empty(): continue
		if i + 1 < inner_list.size():
			cur_b.stack_below_id = inner_list[i + 1]
		else:
			cur_b.stack_below_id = -1

func _collect_all_condition_blocks() -> Array:
	var result: Array = []
	for b in _blocks:
		_collect_conditions_recursive(b, result)
	return result

func _collect_conditions_recursive(block: Dictionary, result: Array):
	if block.def.type == BlockType.CONDITION:
		result.append(block)
		for iid in block.inner_block_ids + block.inner_else_ids:
			var inner_b = _get_block_by_id(iid)
			if not inner_b.is_empty():
				_collect_conditions_recursive(inner_b, result)

func _get_condition_depth(cond_id: int) -> int:
	var depth = 0
	var parent = _find_parent_condition(cond_id)
	while not parent.is_empty():
		depth += 1
		parent = _find_parent_condition(parent.id)
	return depth

# ---- 条件块布局 ----
func _get_condition_layout(block: Dictionary) -> Dictionary:
	var def = block.def
	if def.type != BlockType.CONDITION: return {}
	var x = block.pos.x
	var y = block.pos.y
	var width = _get_block_width(block)
	var result = {}
	var then_y = y + BLOCK_HEIGHT + INNER_PADDING
	var then_h = _get_inner_area_height(block.inner_block_ids)
	result["then_rect"] = Rect2(x + INNER_INDENT / 2, then_y, width - INNER_INDENT, INNER_PADDING + then_h)
	if def.name == "if_else":
		var else_y = then_y + (INNER_PADDING + then_h) + INNER_PADDING + ELSE_HEADER_HEIGHT + INNER_PADDING
		var else_h = _get_inner_area_height(block.inner_else_ids)
		result["else_rect"] = Rect2(x + INNER_INDENT / 2, else_y, width - INNER_INDENT, INNER_PADDING + else_h)
	return result

func _layout_inner_blocks(block: Dictionary):
	if block.def.type != BlockType.CONDITION: return
	var layout = _get_condition_layout(block)
	var cy = layout.then_rect.position.y + INNER_PADDING
	for iid in block.inner_block_ids:
		var iblock = _get_block_by_id(iid)
		if not iblock.is_empty():
			iblock.pos.x = block.pos.x + INNER_INDENT
			iblock.pos.y = cy
			cy += _get_block_height(iblock)
			_layout_inner_blocks(iblock)
	if block.def.name == "if_else" and layout.has("else_rect"):
		cy = layout.else_rect.position.y + INNER_PADDING
		for iid in block.inner_else_ids:
			var iblock = _get_block_by_id(iid)
			if not iblock.is_empty():
				iblock.pos.x = block.pos.x + INNER_INDENT
				iblock.pos.y = cy
				cy += _get_block_height(iblock)
				_layout_inner_blocks(iblock)

func _relayout_all_conditions():
	for b in _blocks:
		if b.def.type == BlockType.CONDITION:
			_layout_inner_blocks(b)

func _move_inner_blocks_with_parent(block_id: int, dx: float, dy: float):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	if block.def.type != BlockType.CONDITION: return
	for iid in block.inner_block_ids + block.inner_else_ids:
		if iid in _dragging_block_ids: continue
		var inner_b = _get_block_by_id(iid)
		if not inner_b.is_empty():
			inner_b.pos.x += dx
			inner_b.pos.y += dy
			_move_inner_blocks_with_parent(iid, dx, dy)

func _is_over_trash(screen_pos: Vector2) -> bool:
	if not _trash_area: return false
	var trash_rect = Rect2(_trash_area.position, _trash_area.size)
	return trash_rect.has_point(screen_pos)

func _update_trash_highlight(is_over: bool):
	if not _trash_area: return
	var style = _trash_area.get_theme_stylebox("panel") as StyleBoxFlat
	if not style: return
	if is_over:
		style.bg_color = Color(0.4, 0.15, 0.15, 0.9)
		style.border_color = Color(1.0, 0.3, 0.3)
		style.set_border_width_all(3)
	else:
		style.bg_color = Color(0.2, 0.2, 0.2, 0.7)
		style.border_color = Color(0.8, 0.3, 0.3)
		style.set_border_width_all(2)

func _on_canvas_resized():
	if _interaction_layer:
		_interaction_layer.size = _canvas.size
	if _trash_area:
		_trash_area.size = Vector2(180, 60)
		_trash_area.position = _canvas.size - Vector2(190, 70)
	if _grid_bg:
		_grid_bg.queue_redraw()
	_update_canvas_transform()

func _on_grid_draw():
	if not _grid_bg: return
	var size = _grid_bg.size
	var spacing = GRID_SPACING * _canvas_zoom
	var offset = Vector2(
		fmod(_canvas_offset.x * _canvas_zoom, spacing),
		fmod(_canvas_offset.y * _canvas_zoom, spacing)
	)
	var center = size / 2.0
	var x = fmod(offset.x - center.x, spacing)
	while x < size.x:
		var y = fmod(offset.y - center.y, spacing)
		while y < size.y:
			_grid_bg.draw_circle(Vector2(x, y), GRID_DOT_SIZE, GRID_DOT_COLOR)
			y += spacing
		x += spacing

func _process(_delta: float):
	# 平滑缩放
	if abs(_canvas_zoom - _target_zoom) > 0.001:
		_canvas_zoom = lerpf(_canvas_zoom, _target_zoom, ZOOM_SMOOTH)
		_update_canvas_transform()
		if _grid_bg: _grid_bg.queue_redraw()

# ============================================
# Control节点渲染系统
# ============================================

func _create_block_node(block: Dictionary):
	if _is_block_in_slot(block.id): return
	if not _block_container: return  # 防御
	var node = Control.new()
	node.name = "Block_%d" % block.id
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width = _get_block_width(block) * _canvas_zoom
	var height = _get_block_height(block) * _canvas_zoom
	node.size = Vector2(width, height)
	node.position = _logical_to_screen(block.pos)
	_block_container.add_child(node)
	_block_nodes[block.id] = node
	_rebuild_block_visual(block, node)

func _ensure_block_node(block_id: int):
	if _block_nodes.has(block_id): return
	var block = _get_block_by_id(block_id)
	if not block.is_empty():
		_create_block_node(block)

func _remove_block_node(block_id: int):
	if _block_nodes.has(block_id):
		var node = _block_nodes[block_id]
		if is_instance_valid(node) and node.get_parent() == _block_container:
			_block_container.remove_child(node)
		node.queue_free()
		_block_nodes.erase(block_id)

func _deferred_post_snap_refresh():
	_refresh_all_block_nodes(true)
	_reposition_all_chains()
	if _selected_block_id >= 0:
		_bring_stack_to_front(_selected_block_id)

func _refresh_all_block_nodes(skip_z_index: bool = false):
	if _is_editing_block_defs: return
	if not _block_container: return
	for child in _block_container.get_children():
		_block_container.remove_child(child)
		child.queue_free()
	_block_nodes.clear()
	for block in _blocks:
		if not _is_block_in_slot(block.id) and _is_block_in_viewport(block):
			_create_block_node(block)
	if not skip_z_index:
		_update_all_z_indices()

func _update_all_z_indices():
	if _selected_block_id >= 0:
		_bring_stack_to_front(_selected_block_id)
	else:
		for b in _blocks:
			if _block_nodes.has(b.id):
				_block_nodes[b.id].z_index = 0

func _update_slot_hover_style(slot_info: Dictionary, is_hover: bool):
	if slot_info.is_empty() or not slot_info.has("block_id"): return
	var top_parent_id: int
	var tp = _find_top_level_parent(slot_info.block_id)
	if not tp.is_empty(): top_parent_id = tp.id
	else: top_parent_id = slot_info.block_id
	if not _block_nodes.has(top_parent_id): return
	var node = _block_nodes[top_parent_id]
	var slot_name = "Slot_" + slot_info.param_name
	var slot_panel = node.get_node_or_null(slot_name)
	if slot_panel == null: return
	var style = slot_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null: return
	var new_style = style.duplicate()
	if is_hover:
		new_style.border_color = Color.WHITE
		new_style.set_border_width_all(int(2 * _canvas_zoom))
	else:
		var block = _get_block_by_id(slot_info.block_id)
		if block.is_empty(): return
		var param_def = _find_param_def(block.def, slot_info.param_name)
		if param_def.is_empty(): return
		var default_colors = {
			"node": Color(0.6, 0.5, 1.0, 0.6),
			"vector2": Color(0.95, 0.55, 0.4, 0.6),
			"vector3": Color(0.9, 0.4, 0.7, 0.6),
			"string": Color(0.5, 0.8, 0.4, 0.6),
			"expr": Color(0.5, 0.7, 0.9, 0.6),
			"dropdown": Color(0.7, 0.65, 0.5, 0.6),
			"number": Color(0.35, 0.78, 0.38, 0.6),
			"bool": Color(0.8, 0.3, 0.3, 0.6),
		}
		if default_colors.has(param_def.type):
			new_style.border_color = default_colors[param_def.type]
		else:
			new_style.border_color = Color(1, 1, 1, 0.5)
		new_style.set_border_width_all(int(1 * _canvas_zoom))
	slot_panel.add_theme_stylebox_override("panel", new_style)

func _update_snap_line():
	if not _snap_line: return
	_snap_line.visible = false
	if _dragging_block_ids.size() > 0:
		var top_block = _get_block_by_id(_dragging_block_ids[0])
		if top_block.is_empty(): return
		var stack_info = {}
		var inner_info = {}
		if top_block.def.type != BlockType.VALUE and top_block.def.type != BlockType.EVENT:
			stack_info = _find_snap_stack_target(_dragging_block_ids[0])
		if top_block.def.type != BlockType.VALUE:
			inner_info = _find_snap_inner_preview(_dragging_block_ids[0], _mouse_logical)
		var show_inner = not inner_info.is_empty()
		var show_stack = not stack_info.is_empty() and not show_inner
		if show_inner:
			var insert_x = inner_info.insert_x
			var insert_y = inner_info.insert_y
			var depth = inner_info.get("depth", 0)
			var depth_colors = [Color(0.95, 0.95, 1.0), Color(0.55, 1.0, 0.55), Color(0.5, 0.7, 1.0), Color(1.0, 0.6, 1.0)]
			var line_color = depth_colors[depth % depth_colors.size()]
			_snap_line.default_color = line_color
			_snap_line.width = (4.0 + depth * 1.5) * _canvas_zoom
			var line_width = _get_block_width(top_block) * _canvas_zoom
			var line_x = _logical_to_screen(Vector2(insert_x, insert_y)).x
			var line_y = _logical_to_screen(Vector2(insert_x, insert_y)).y
			_snap_line.points = PackedVector2Array([Vector2(line_x, line_y), Vector2(line_x + line_width, line_y)])
			_snap_line.visible = true
			return
		elif show_stack:
			var target = _get_block_by_id(stack_info.target_id)
			var snap_y = stack_info.snap_y
			var line_width = _get_block_width(target) * _canvas_zoom
			var line_x = _logical_to_screen(Vector2(target.pos.x, snap_y)).x
			var line_y = _logical_to_screen(Vector2(target.pos.x, snap_y)).y
			var is_insert = stack_info.get("mode", "below") == "insert"
			_snap_line.default_color = Color(1.0, 0.85, 0.2) if is_insert else Color(0.4, 0.9, 1.0)
			_snap_line.width = 4.0 * _canvas_zoom
			_snap_line.points = PackedVector2Array([Vector2(line_x, line_y), Vector2(line_x + line_width, line_y)])
			_snap_line.visible = true

func _find_snap_inner_preview(drag_block_id: int, mouse_logical: Vector2) -> Dictionary:
	var drag_block = _get_block_by_id(drag_block_id)
	if drag_block.is_empty(): return {}
	var all_conditions: Array = _collect_all_condition_blocks()
	all_conditions.sort_custom(func(a, b): return _get_condition_depth(a.id) > _get_condition_depth(b.id))
	for b in all_conditions:
		if b.id in _dragging_block_ids: continue
		var layout = _get_condition_layout(b)
		var expanded_then = layout.then_rect.grow(BLOCK_SNAP_DISTANCE)
		if expanded_then.has_point(mouse_logical):
			var insert_y = layout.then_rect.position.y + layout.then_rect.size.y
			var insert_x = b.pos.x + INNER_INDENT
			var depth = _get_condition_depth(b.id)
			return {"cond_id": b.id, "slot": "then_rect", "insert_x": insert_x, "insert_y": insert_y, "depth": depth}
		if b.def.name == "if_else" and layout.has("else_rect"):
			var expanded_else = layout.else_rect.grow(BLOCK_SNAP_DISTANCE)
			if expanded_else.has_point(mouse_logical):
				var insert_y = layout.else_rect.position.y + layout.else_rect.size.y
				var insert_x = b.pos.x + INNER_INDENT
				var depth = _get_condition_depth(b.id)
				return {"cond_id": b.id, "slot": "else_rect", "insert_x": insert_x, "insert_y": insert_y, "depth": depth}
	return {}

func _queue_block_redraw(block_id: int):
	if not _block_nodes.has(block_id): return
	var node = _block_nodes[block_id]
	var body = node.get_node_or_null("Body")
	if body and is_instance_valid(body):
		body.queue_redraw()

func _refresh_block_node(block_id: int):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	if _is_block_in_slot(block.id):
		var top_parent = _find_top_level_parent(block.id)
		if not top_parent.is_empty() and _block_nodes.has(top_parent.id):
			_remove_block_node(top_parent.id)
			_create_block_node(top_parent)
	else:
		if block.def.type == BlockType.CONDITION:
			_layout_inner_blocks(block)
		_remove_block_node(block_id)
		_create_block_node(block)

func _update_dragging_positions():
	for bid in _dragging_block_ids:
		var b = _get_block_by_id(bid)
		if b and _block_nodes.has(bid):
			_block_nodes[bid].position = _logical_to_screen(b.pos)

func _sync_condition_visual_positions(cond_block: Dictionary):
	if cond_block.is_empty() or cond_block.def.type != BlockType.CONDITION: return
	if not _block_nodes.has(cond_block.id): return
	var saved_z = _block_nodes[cond_block.id].z_index
	_refresh_block_node(cond_block.id)
	if _block_nodes.has(cond_block.id):
		_block_nodes[cond_block.id].z_index = saved_z
		_adjust_inner_blocks_z(cond_block.id, saved_z + 5)
	for iid in cond_block.inner_block_ids + cond_block.inner_else_ids:
		var iblock = _get_block_by_id(iid)
		if not iblock.is_empty():
			_sync_condition_visual_positions(iblock)

func _adjust_inner_blocks_z(parent_id: int, base_z: int):
	var parent = _get_block_by_id(parent_id)
	if parent.is_empty(): return
	for iid in parent.inner_block_ids + parent.inner_else_ids:
		if _block_nodes.has(iid):
			_block_nodes[iid].z_index = base_z
		var inner = _get_block_by_id(iid)
		if not inner.is_empty() and inner.def.type == BlockType.CONDITION:
			_adjust_inner_blocks_z(iid, base_z + 5)

# ---- 统一位置计算 ----
func _reposition_all_chains():
	for block in _blocks:
		if _is_block_in_slot(block.id) or _is_inner_block(block.id): continue
		var above = _find_block_above(block.id)
		if above.is_empty():
			_reposition_chain_from_top(block)

func _reposition_chain_from_top(top_block: Dictionary):
	if top_block.is_empty(): return
	var x = top_block.pos.x
	var y = top_block.pos.y
	var current: Dictionary = top_block
	while not current.is_empty():
		var moved = (current.pos.x != x or current.pos.y != y)
		current.pos.x = x
		current.pos.y = y
		if current.def.type == BlockType.CONDITION:
			_layout_inner_blocks(current)
		if moved and _block_nodes.has(current.id):
			_block_nodes[current.id].position = _logical_to_screen(current.pos)
		if current.def.type == BlockType.CONDITION:
			_sync_condition_visual_positions(current)
		y += _get_block_height(current)
		var below_id = current.get("stack_below_id", -1)
		if below_id < 0: break
		current = _get_block_by_id(below_id)

func _set_dragging_modulate(is_dragging: bool):
	for bid in _dragging_block_ids:
		if _block_nodes.has(bid):
			_block_nodes[bid].modulate.a = 0.7 if is_dragging else 1.0

# ---- 构建积木块视觉 ----
func _rebuild_block_visual(block: Dictionary, node: Control):
	if not node or not is_instance_valid(node): return
	for child in node.get_children():
		child.queue_free()
	var def = block.def
	var block_type = def.type
	var width = _get_block_width(block) * _canvas_zoom
	var height = _get_block_height(block) * _canvas_zoom
	var color = _get_block_color(block)
	var dark_color = _get_block_dark_color(block)
	var is_hovered = (block.id == _hovered_block_id)
	var is_selected = (block.id == _selected_block_id)
	var has_below = (block.get("stack_below_id", -1) >= 0)
	var has_above = not _find_block_above(block.id).is_empty() and not _is_inner_block(block.id)
	node.size = Vector2(width, height)

	# 主体 - 自定义绘制（含阴影、凹槽、边框）
	var body = Control.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.position = Vector2.ZERO
	body.size = Vector2(width, height)
	body.draw.connect(_make_block_body_draw(block, body, color, dark_color, is_selected, is_hovered, has_above, has_below, block_type))
	node.add_child(body)
	var hat_offset = HAT_HEIGHT * _canvas_zoom if block_type == BlockType.EVENT else 0.0
	var segments = _parse_label_template(def.label)
	var extra_lines = _count_extra_label_lines(def.label)
	var line_h = BLOCK_LINE_HEIGHT * _canvas_zoom
	var total_label_h = (extra_lines + 1) * line_h
	var content_h = BLOCK_HEIGHT * _canvas_zoom + extra_lines * line_h
	var base_y = hat_offset + (content_h - total_label_h) / 2.0
	var seg_x = BLOCK_PADDING_H * _canvas_zoom
	var seg_y = base_y
	var current_line = 0
	for seg in segments:
		if seg.type == "newline":
			current_line += 1
			seg_x = BLOCK_PADDING_H * _canvas_zoom
			seg_y = base_y + current_line * line_h
		elif seg.type == "text":
			var seg_label = Label.new()
			seg_label.text = seg.content
			seg_label.add_theme_color_override("font_color", Color.WHITE)
			seg_label.add_theme_font_size_override("font_size", int(14 * _canvas_zoom))
			seg_label.position = Vector2(seg_x, seg_y + (line_h - 14 * _canvas_zoom) / 2.0)
			seg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.add_child(seg_label)
			seg_x += _estimate_text_width(seg.content) * _canvas_zoom
		elif seg.type == "param":
			var param_def = _find_param_def(def, seg.name)
			if not param_def.is_empty():
				var slot_local_rect = Rect2(
					seg_x,
					seg_y + (line_h - SLOT_HEIGHT * _canvas_zoom) / 2.0,
					_get_slot_width(block, param_def) * _canvas_zoom,
					SLOT_HEIGHT * _canvas_zoom
				)
				if _is_slot_type(param_def.type):
					var vid = block.value_slots.get(seg.name, -1)
					if vid >= 0:
						_create_embedded_value_visual(block, vid, slot_local_rect, node)
					else:
						_create_slot_visual(block, seg.name, param_def, slot_local_rect, node)
				else:
					_create_slot_visual(block, seg.name, param_def, slot_local_rect, node)
				seg_x += _get_slot_width(block, param_def) * _canvas_zoom + SLOT_SPACING * _canvas_zoom
	if block_type == BlockType.CONDITION:
		_create_condition_inner_visual(block, node)
	var outputs = _ensure_outputs(def)
	if outputs.size() > 0:
		var content_height: float
		if block_type == BlockType.CONDITION:
			content_height = _get_block_height(block) - _get_output_area_height(block)
		elif block_type == BlockType.EVENT:
			content_height = BLOCK_HEIGHT + HAT_HEIGHT
		else:
			content_height = BLOCK_HEIGHT
		var out_y = content_height * _canvas_zoom
		for out_def in outputs:
			_create_output_port_visual(node, out_def, out_y, width)
			out_y += (SLOT_HEIGHT + 4) * _canvas_zoom

func _create_embedded_value_visual(parent_block: Dictionary, value_block_id: int, slot_rect: Rect2, parent_node: Control):
	if not parent_node or not is_instance_valid(parent_node): return
	var vblock = _get_block_by_id(value_block_id)
	if vblock.is_empty(): return
	var vcolor = _get_block_color(vblock)
	var is_vselected = (value_block_id == _selected_block_id)
	var is_var_ref = vblock.get("is_var_ref", false)
	var source_block_id = vblock.get("source_block_id", -1) if is_var_ref else -1
	var ref_bg_color = vcolor
	if is_var_ref and source_block_id >= 0:
		var source_block = _get_block_by_id(source_block_id)
		if not source_block.is_empty():
			ref_bg_color = _get_block_color(source_block)
	var vpanel = Panel.new()
	vpanel.name = "ValueBlock_" + str(value_block_id)
	vpanel.position = slot_rect.position
	vpanel.size = slot_rect.size
	vpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vstyle = StyleBoxFlat.new()
	if is_var_ref:
		vstyle.bg_color = ref_bg_color
		vstyle.border_color = Color.WHITE if is_vselected else _get_output_color(vblock.get("output_type", ""))
	else:
		vstyle.bg_color = vcolor
		vstyle.border_color = Color.WHITE if is_vselected else _get_block_dark_color(vblock)
	vstyle.set_border_width_all(int(2 * _canvas_zoom) if is_vselected else int(1 * _canvas_zoom))
	vstyle.set_corner_radius_all(int(4 * _canvas_zoom))
	vpanel.add_theme_stylebox_override("panel", vstyle)
	parent_node.add_child(vpanel)
	var vsegments = _parse_label_template(vblock.def.label)
	var vextra = _count_extra_label_lines(vblock.def.label)
	var vline_h = BLOCK_LINE_HEIGHT * _canvas_zoom * 0.8
	var vtotal_h = (vextra + 1) * vline_h
	var vbase_y = slot_rect.position.y + (slot_rect.size.y - vtotal_h) / 2.0
	var vseg_x = slot_rect.position.x + 6 * _canvas_zoom
	var vseg_y = vbase_y
	var vcurrent_line = 0
	for vseg in vsegments:
		if vseg.type == "newline":
			vcurrent_line += 1
			vseg_x = slot_rect.position.x + 6 * _canvas_zoom
			vseg_y = vbase_y + vcurrent_line * vline_h
		elif vseg.type == "text":
			var vseg_label = Label.new()
			vseg_label.text = vseg.content
			vseg_label.add_theme_color_override("font_color", Color.WHITE)
			vseg_label.add_theme_font_size_override("font_size", int(11 * _canvas_zoom))
			vseg_label.position = Vector2(vseg_x, vseg_y + (vline_h - 11 * _canvas_zoom) / 2.0)
			vseg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent_node.add_child(vseg_label)
			vseg_x += _estimate_text_width(vseg.content) * _canvas_zoom
		elif vseg.type == "param":
			var param_def = _find_param_def(vblock.def, vseg.name)
			if not param_def.is_empty() and _is_slot_type(param_def.type):
				var vid = vblock.value_slots.get(vseg.name, -1)
				var pw = _get_slot_width(vblock, param_def) * _canvas_zoom
				var inner_h = vline_h - 4 * _canvas_zoom
				var pr = Rect2(vseg_x, vseg_y + (vline_h - inner_h) / 2.0, pw, inner_h)
				if vid >= 0:
					_create_embedded_value_visual(vblock, vid, pr, parent_node)
				else:
					var ppanel = Panel.new()
					ppanel.name = "Slot_" + vseg.name
					ppanel.position = pr.position
					ppanel.size = pr.size
					ppanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
					var pstyle = StyleBoxFlat.new()
					var is_hover = (_hover_slot_info.get("block_id") == value_block_id and _hover_slot_info.get("param_name") == vseg.name)
					if param_def.type == "node":
						pstyle.bg_color = Color(0.8, 0.6, 1.0, 0.4) if is_hover else Color(0.8, 0.6, 1.0, 0.25)
						pstyle.border_color = Color.WHITE if is_hover else Color(0.6, 0.5, 1.0, 0.6)
					elif param_def.type == "vector2":
						pstyle.bg_color = Color(0.95, 0.55, 0.4, 0.4) if is_hover else Color(0.95, 0.55, 0.4, 0.25)
						pstyle.border_color = Color.WHITE if is_hover else Color(0.95, 0.55, 0.4, 0.6)
					elif param_def.type == "vector3":
						pstyle.bg_color = Color(0.9, 0.4, 0.7, 0.4) if is_hover else Color(0.9, 0.4, 0.7, 0.25)
						pstyle.border_color = Color.WHITE if is_hover else Color(0.9, 0.4, 0.7, 0.6)
					elif param_def.type == "string":
						pstyle.bg_color = Color(0.6, 0.9, 0.5, 0.4) if is_hover else Color(0.6, 0.9, 0.5, 0.25)
						pstyle.border_color = Color.WHITE if is_hover else Color(0.5, 0.8, 0.4, 0.6)
					else:
						pstyle.bg_color = Color(1, 1, 1, 0.3) if is_hover else Color(1, 1, 1, 0.2)
						pstyle.border_color = Color.WHITE if is_hover else Color(1, 1, 1, 0.5)
					pstyle.set_border_width_all(int(2 * _canvas_zoom) if is_hover else int(1 * _canvas_zoom))
					pstyle.set_corner_radius_all(int(2 * _canvas_zoom))
					ppanel.add_theme_stylebox_override("panel", pstyle)
					parent_node.add_child(ppanel)
					var slot_val = str(vblock.params.get(vseg.name, "true" if param_def.type == "bool" else "0"))
					if param_def.type == "node": slot_val = str(vblock.params.get(vseg.name, ""))
					if param_def.type == "string": slot_val = str(vblock.params.get(vseg.name, ""))
					if param_def.type == "dropdown" and param_def.has("options"):
						slot_val = str(vblock.params.get(vseg.name, param_def.default))
					if param_def.type == "vector2":
						var v = vblock.params.get(vseg.name, param_def.default)
						if v is Dictionary:
							slot_val = "(%.3f, %.3f)" % [v.get("x", 0.0), v.get("y", 0.0)]
						else: slot_val = "(0, 0)"
					if param_def.type == "vector3":
						var v = vblock.params.get(vseg.name, param_def.default)
						if v is Dictionary:
							slot_val = "(%.3f, %.3f, %.3f)" % [v.get("x", 0.0), v.get("y", 0.0), v.get("z", 0.0)]
						else: slot_val = "(0, 0, 0)"
					var plabel = Label.new()
					plabel.text = slot_val
					plabel.add_theme_color_override("font_color", Color.WHITE)
					plabel.add_theme_font_size_override("font_size", int(10 * _canvas_zoom))
					plabel.position = pr.position + Vector2(4 * _canvas_zoom, pr.size.y / 2 - 5 * _canvas_zoom)
					plabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
					parent_node.add_child(plabel)
				vseg_x += pw + 3 * _canvas_zoom
			else:
				var val = str(vblock.params.get(vseg.name, ""))
				var pw = _estimate_text_width(val) * _canvas_zoom + 8 * _canvas_zoom
				var inner_h = vline_h - 4 * _canvas_zoom
				var pr = Rect2(vseg_x, vseg_y + (vline_h - inner_h) / 2.0, pw, inner_h)
				var ppanel = Panel.new()
				ppanel.position = pr.position
				ppanel.size = pr.size
				ppanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var pstyle = StyleBoxFlat.new()
				pstyle.bg_color = Color(1, 1, 1, 0.25)
				pstyle.set_corner_radius_all(int(2 * _canvas_zoom))
				ppanel.add_theme_stylebox_override("panel", pstyle)
				parent_node.add_child(ppanel)
				var plabel = Label.new()
				plabel.text = val
				plabel.add_theme_color_override("font_color", Color.WHITE)
				plabel.add_theme_font_size_override("font_size", int(10 * _canvas_zoom))
				plabel.position = pr.position + Vector2(4 * _canvas_zoom, pr.size.y / 2 - 5 * _canvas_zoom)
				plabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				parent_node.add_child(plabel)
				vseg_x += pw + 3 * _canvas_zoom

# ---- 积木主体绘制回调 ----
func _make_block_body_draw(block: Dictionary, body: Control, color: Color, dark_color: Color, is_selected: bool, _is_hovered: bool, _has_above: bool, _has_below: bool, block_type: int) -> Callable:
	var _block = block
	var _body = body
	var _color = color
	var _dark = dark_color
	var _sel = is_selected
	var _type = block_type
	return func():
		var w = _body.size.x
		var h = _body.size.y
		var r = clamp(6 * _canvas_zoom, 2.0, min(w, h) * 0.3)
		var hat_h = HAT_HEIGHT * _canvas_zoom if _type == BlockType.EVENT else 0.0

		# 主体
		if _type == BlockType.VALUE:
			_draw_rounded_rect(_body, Rect2(0, 0, w, h), r, _color)
		elif _type == BlockType.EVENT:
			_body.draw_colored_polygon(_make_hat_points(w, hat_h), _color)
			_body.draw_rect(Rect2(0, hat_h, w, h - hat_h), _color, true)
		else:
			_draw_rounded_rect(_body, Rect2(0, 0, w, h), r, _color)

		# 描边
		var bw = 2 * _canvas_zoom if _sel else 1.5 * _canvas_zoom
		var bc = Color.WHITE if _sel else _dark
		if _type == BlockType.EVENT:
			_draw_event_border(_body, w, h, hat_h, r, bc, bw)
		else:
			_draw_rounded_rect_border(_body, Rect2(0, 0, w, h), r, bc, bw)

# ---- 圆角矩形填充 ----
func _draw_rounded_rect(ctrl: Control, rect: Rect2, r: float, color: Color):
	var path = _make_rounded_rect_path(rect, r)
	ctrl.draw_colored_polygon(path, color)

# ---- 圆角矩形路径 ----
func _make_rounded_rect_path(rect: Rect2, r: float) -> PackedVector2Array:
	var pts = PackedVector2Array()
	var x = rect.position.x; var y = rect.position.y
	var w = rect.size.x; var h = rect.size.y
	var rr = min(r, min(w, h) / 2.0)
	var seg = max(int(rr / 2.0), 4)
	# 上边
	pts.append(Vector2(x + rr, y))
	# 右上角
	for i in range(seg + 1):
		var a = -PI / 2.0 + i * (PI / 2.0) / seg
		pts.append(Vector2(x + w - rr + cos(a) * rr, y + rr + sin(a) * rr))
	# 右边
	pts.append(Vector2(x + w, y + h - rr))
	# 右下角
	for i in range(seg + 1):
		var a = i * (PI / 2.0) / seg
		pts.append(Vector2(x + w - rr + cos(a) * rr, y + h - rr + sin(a) * rr))
	# 下边
	pts.append(Vector2(x + rr, y + h))
	# 左下角
	for i in range(seg + 1):
		var a = PI / 2.0 + i * (PI / 2.0) / seg
		pts.append(Vector2(x + rr + cos(a) * rr, y + h - rr + sin(a) * rr))
	# 左边
	pts.append(Vector2(x, y + rr))
	# 左上角
	for i in range(seg + 1):
		var a = PI + i * (PI / 2.0) / seg
		pts.append(Vector2(x + rr + cos(a) * rr, y + rr + sin(a) * rr))
	return pts

# ---- 帽子形状 ----
func _make_hat_points(w: float, hat_h: float) -> PackedVector2Array:
	var pts = PackedVector2Array()
	pts.append(Vector2(0, hat_h))
	for i in range(11):
		var t = i / 10.0
		pts.append(Vector2(t * w, hat_h - sin(t * PI) * hat_h))
	pts.append(Vector2(w, hat_h))
	return pts

# ---- 圆角矩形边框 ----
func _draw_rounded_rect_border(ctrl: Control, rect: Rect2, r: float, color: Color, width: float):
	var x = rect.position.x; var y = rect.position.y
	var w = rect.size.x; var h = rect.size.y
	var rr = min(r, min(w, h) / 2.0)
	var half = width / 2.0
	var inner = Rect2(x + half, y + half, w - width, h - width)
	var path = _make_rounded_rect_path(inner, rr - half)
	path.append(path[0])  # 闭合
	ctrl.draw_polyline(path, color, width, true)

# ---- 事件块描边 ----
func _draw_event_border(ctrl: Control, w: float, h: float, hat_h: float, r: float, color: Color, width: float):
	var rr = min(r, min(w, h) / 2.0)
	var pts = PackedVector2Array()
	# 帽子曲线（从左到右）
	pts.append(Vector2(0, hat_h))
	for i in range(11):
		var t = i / 10.0
		var x = t * w
		var y = hat_h - sin(t * PI) * hat_h
		pts.append(Vector2(x, y))
	pts.append(Vector2(w, hat_h))
	# 右边
	pts.append(Vector2(w, h - rr))
	# 右下角
	for i in range(6):
		var a = 0.0 + i * (PI / 2.0) / 5
		pts.append(Vector2(w - rr + cos(a) * rr, h - rr + sin(a) * rr))
	# 下边
	pts.append(Vector2(rr, h))
	# 左下角
	for i in range(6):
		var a = PI / 2.0 + i * (PI / 2.0) / 5
		pts.append(Vector2(rr + cos(a) * rr, h - rr + sin(a) * rr))
	# 左边
	pts.append(Vector2(0, h - rr))
	pts.append(Vector2(0, hat_h))
	pts.append(pts[0])
	ctrl.draw_polyline(pts, color, width, true)

# ---- 槽位渲染 ----
func _create_slot_visual(block: Dictionary, param_name: String, param_def: Dictionary, rect: Rect2, parent_node: Control):
	var slot_panel = Panel.new()
	slot_panel.name = "Slot_" + param_name
	slot_panel.position = rect.position
	slot_panel.size = rect.size
	slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot_style = StyleBoxFlat.new()
	var is_hover = (_hover_slot_info.get("block_id") == block.id and _hover_slot_info.get("param_name") == param_name)
	var is_empty = _is_slot_empty(block, param_def, param_name)
	var type_colors = {
		"node": Color(0.8, 0.6, 1.0),
		"vector2": Color(0.95, 0.55, 0.4),
		"vector3": Color(0.9, 0.4, 0.7),
		"string": Color(0.6, 0.9, 0.5),
		"expr": Color(0.5, 0.7, 0.9),
		"dropdown": Color(0.7, 0.65, 0.5),
	}
	var tc = type_colors.get(param_def.type, Color.WHITE)
	slot_style.bg_color = Color(tc.r, tc.g, tc.b, 0.4 if is_hover else 0.22)
	slot_style.border_color = Color.WHITE if is_hover else Color(tc.r, tc.g, tc.b, 0.55)
	slot_style.set_border_width_all(int(2 * _canvas_zoom) if is_hover else int(1 * _canvas_zoom))
	slot_style.set_corner_radius_all(int(3 * _canvas_zoom))
	slot_panel.add_theme_stylebox_override("panel", slot_style)
	parent_node.add_child(slot_panel)
	var slot_val = _format_slot_value(block, param_def, param_name)
	var slot_label = Label.new()
	slot_label.text = slot_val
	# 空槽位用灰色斜体显示 placeholder
	if is_empty:
		slot_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.7))
	else:
		slot_label.add_theme_color_override("font_color", Color.WHITE)
	slot_label.add_theme_font_size_override("font_size", int(12 * _canvas_zoom))
	slot_label.position = rect.position + Vector2(6 * _canvas_zoom, rect.size.y / 2 - 7 * _canvas_zoom)
	slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent_node.add_child(slot_label)

# ---- 槽位内联编辑 ----
func _try_start_inline_edit(screen_pos: Vector2):
	_cancel_inline_edit()
	var block = _get_block_by_id(_selected_block_id)
	if block.is_empty(): return
	var node = _block_nodes.get(_selected_block_id)
	if not node: return
	var logical = _screen_to_logical(screen_pos)
	var layout = _get_param_layout(block)
	for slot in layout:
		if not _is_slot_type(slot.type): continue
		if block.value_slots.has(slot.name) and block.value_slots[slot.name] >= 0: continue
		if slot.rect.has_point(logical - block.pos):
			var slot_rect = Rect2(
				(slot.rect.position.x - block.pos.x) * _canvas_zoom,
				(slot.rect.position.y - block.pos.y) * _canvas_zoom,
				slot.rect.size.x * _canvas_zoom,
				slot.rect.size.y * _canvas_zoom
			)
			# dropdown 槽位：弹出菜单
			var param_def = _find_param_def(block.def, slot.name)
			if param_def.type == "dropdown" and param_def.has("options"):
				_show_dropdown_popup(block, slot.name, param_def, slot_rect, node)
				return
			_show_inline_edit(block, slot.name, slot_rect, node)
			return

func _show_dropdown_popup(block: Dictionary, param_name: String, param_def: Dictionary, slot_rect: Rect2, parent_node: Control):
	var popup = PopupMenu.new()
	popup.name = "DropdownPopup"
	var options = param_def.options
	var current_val = str(block.params.get(param_name, param_def.default))
	for i in range(options.size()):
		popup.add_item(str(options[i]))
		if str(options[i]) == current_val:
			popup.set_item_checked(i, true)
	popup.id_pressed.connect(func(idx: int):
		if idx >= 0 and idx < options.size():
			block.params[param_name] = options[idx]
			_refresh_block_node(block.id)
			_update_prop_panel()
		popup.queue_free()
	)
	popup.popup_hide.connect(popup.queue_free)
	_canvas.add_child(popup)
	var screen_pos = parent_node.global_position + slot_rect.position + Vector2(0, slot_rect.size.y)
	popup.position = screen_pos
	popup.reset_size()
	popup.popup()

func _show_inline_edit(block: Dictionary, param_name: String, slot_rect: Rect2, parent_node: Control):
	var param_def = _find_param_def(block.def, param_name)
	if param_def.is_empty(): return
	_editing_slot = {"block_id": block.id, "param_name": param_name}
	_inline_edit = LineEdit.new()
	_inline_edit.name = "InlineEdit"
	_inline_edit.position = slot_rect.position
	_inline_edit.size = slot_rect.size
	_inline_edit.text = str(block.params.get(param_name, param_def.default))
	_inline_edit.add_theme_font_size_override("font_size", int(12 * _canvas_zoom))
	_inline_edit.add_theme_color_override("font_color", Color.BLACK)
	_inline_edit.add_theme_stylebox_override("normal", _make_inline_edit_style())
	_inline_edit.add_theme_stylebox_override("focus", _make_inline_edit_style())
	_inline_edit.text_submitted.connect(_commit_inline_edit)
	_inline_edit.focus_exited.connect(_commit_inline_edit)
	parent_node.add_child(_inline_edit)
	_inline_edit.grab_focus()
	_inline_edit.select_all()

func _make_inline_edit_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = Color(0.3, 0.5, 0.9)
	style.set_border_width_all(int(2 * _canvas_zoom))
	style.set_corner_radius_all(int(3 * _canvas_zoom))
	style.content_margin_left = 4 * _canvas_zoom
	style.content_margin_right = 4 * _canvas_zoom
	return style

func _commit_inline_edit(_text: String = ""):
	if not _inline_edit or not is_instance_valid(_inline_edit): return
	var info = _editing_slot.duplicate()
	_cancel_inline_edit()
	var block = _get_block_by_id(info.block_id)
	if block.is_empty(): return
	var new_val = _text.strip_edges()
	var param_def = _find_param_def(block.def, info.param_name)
	if param_def.is_empty(): return
	if param_def.type == "number":
		if new_val.is_valid_float(): block.params[info.param_name] = float(new_val)
		else: block.params[info.param_name] = new_val
	elif param_def.type == "bool":
		block.params[info.param_name] = new_val.to_lower() in ["true", "1", "yes"]
	elif param_def.type == "vector2":
		var parts = new_val.replace("(", "").replace(")", "").split(",")
		if parts.size() >= 2:
			block.params[info.param_name] = {"x": float(parts[0].strip_edges()), "y": float(parts[1].strip_edges())}
		else:
			block.params[info.param_name] = new_val
	elif param_def.type == "vector3":
		var parts = new_val.replace("(", "").replace(")", "").split(",")
		if parts.size() >= 3:
			block.params[info.param_name] = {"x": float(parts[0].strip_edges()), "y": float(parts[1].strip_edges()), "z": float(parts[2].strip_edges())}
		else:
			block.params[info.param_name] = new_val
	elif param_def.type == "dropdown" and param_def.has("options"):
		for opt in param_def.options:
			if str(opt) == new_val:
				block.params[info.param_name] = opt
				break
	else:
		block.params[info.param_name] = new_val
	_refresh_block_node(info.block_id)
	_update_prop_panel()

func _cancel_inline_edit():
	if _inline_edit and is_instance_valid(_inline_edit):
		_inline_edit.queue_free()
	_inline_edit = null
	_editing_slot = {}

# ---- 槽位值格式化 ----
func _format_slot_value(block: Dictionary, param_def: Dictionary, param_name: String) -> String:
	if param_def.type == "vector2":
		var v = block.params.get(param_name, param_def.default)
		if v is Dictionary: return "(%.3f, %.3f)" % [v.get("x", 0.0), v.get("y", 0.0)]
		return "(0, 0)"
	if param_def.type == "vector3":
		var v = block.params.get(param_name, param_def.default)
		if v is Dictionary: return "(%.3f, %.3f, %.3f)" % [v.get("x", 0.0), v.get("y", 0.0), v.get("z", 0.0)]
		return "(0, 0, 0)"
	if param_def.type == "dropdown" and param_def.has("options"):
		return str(block.params.get(param_name, param_def.default))
	if param_def.type == "bool":
		return str(block.params.get(param_name, true))
	if param_def.type in ["node", "string"]:
		var v = block.params.get(param_name, "")
		return str(v) if str(v) != "" else param_def.label
	if param_def.type == "expr":
		var v = block.params.get(param_name, "")
		return str(v) if str(v) != "" else param_def.label
	return str(block.params.get(param_name, param_def.default))

func _is_slot_empty(block: Dictionary, param_def: Dictionary, param_name: String) -> bool:
	var val = block.params.get(param_name, param_def.default)
	if param_def.type == "expr":
		return str(val) == ""
	if param_def.type in ["node", "string"]:
		return str(val) == ""
	return false

# ---- 输出端口渲染 ----
func _create_output_port_visual(parent_node: Control, out_def: Dictionary, out_y: float, width: float):
	var out_circle = Panel.new()
	out_circle.name = "Output_" + out_def.name
	var out_x = BLOCK_PADDING_H * _canvas_zoom
	out_circle.position = Vector2(out_x, out_y)
	out_circle.size = Vector2((_estimate_text_width(out_def.label) + 24) * _canvas_zoom, SLOT_HEIGHT * _canvas_zoom)
	out_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var out_style = StyleBoxFlat.new()
	var out_color = _get_output_color(out_def.type)
	out_style.bg_color = Color(out_color.r, out_color.g, out_color.b, 0.18)
	out_style.border_color = out_color
	out_style.set_border_width_all(int(1 * _canvas_zoom))
	out_style.set_corner_radius_all(int(10 * _canvas_zoom))
	out_circle.add_theme_stylebox_override("panel", out_style)
	parent_node.add_child(out_circle)
	var out_label = Label.new()
	out_label.text = "◆ %s" % out_def.label
	out_label.add_theme_color_override("font_color", out_color)
	out_label.add_theme_font_size_override("font_size", int(11 * _canvas_zoom))
	out_label.position = Vector2(out_x + 6 * _canvas_zoom, out_y + SLOT_HEIGHT * _canvas_zoom / 2 - 6 * _canvas_zoom)
	out_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent_node.add_child(out_label)

func _create_condition_inner_visual(block: Dictionary, parent_node: Control):
	if not parent_node or not is_instance_valid(parent_node): return
	var layout = _get_condition_layout(block)
	var color = _get_block_color(block)
	var dark_color = _get_block_dark_color(block)
	var def = block.def

	# 计算内部区域在父节点坐标系中的位置
	var then_local = Rect2(
		(layout.then_rect.position.x - block.pos.x) * _canvas_zoom,
		(layout.then_rect.position.y - block.pos.y) * _canvas_zoom,
		layout.then_rect.size.x * _canvas_zoom,
		layout.then_rect.size.y * _canvas_zoom
	)

	# 左侧 C 形臂
	var arm_w = 4 * _canvas_zoom
	var arm = Panel.new()
	arm.name = "CArm"
	arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arm.position = Vector2(then_local.position.x - arm_w, then_local.position.y)
	arm.size = Vector2(arm_w, then_local.size.y)
	var arm_style = StyleBoxFlat.new()
	arm_style.bg_color = dark_color
	arm_style.set_corner_radius_all(int(2 * _canvas_zoom))
	arm.add_theme_stylebox_override("panel", arm_style)
	parent_node.add_child(arm)

	# then 区域
	var then_panel = Panel.new()
	then_panel.name = "ThenArea"
	then_panel.position = then_local.position
	then_panel.size = then_local.size
	then_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var then_style = StyleBoxFlat.new()
	then_style.bg_color = Color(color.r, color.g, color.b, 0.10)
	then_style.border_color = Color(dark_color.r, dark_color.g, dark_color.b, 0.45)
	then_style.set_border_width_all(int(1.5 * _canvas_zoom))
	then_style.set_corner_radius_all(int(4 * _canvas_zoom))
	then_panel.add_theme_stylebox_override("panel", then_style)
	parent_node.add_child(then_panel)

	if def.name == "if_else" and layout.has("else_rect"):
		var else_local = Rect2(
			(layout.else_rect.position.x - block.pos.x) * _canvas_zoom,
			(layout.else_rect.position.y - block.pos.y) * _canvas_zoom,
			layout.else_rect.size.x * _canvas_zoom,
			layout.else_rect.size.y * _canvas_zoom
		)
		# else 标签
		var else_label_y = (layout.then_rect.position.y + layout.then_rect.size.y + INNER_PADDING - block.pos.y) * _canvas_zoom
		var else_label = Label.new()
		else_label.text = "否则"
		else_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
		else_label.add_theme_font_size_override("font_size", int(13 * _canvas_zoom))
		else_label.position = Vector2(then_local.position.x + 6 * _canvas_zoom, else_label_y + ELSE_HEADER_HEIGHT * _canvas_zoom / 2 - 7 * _canvas_zoom)
		else_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent_node.add_child(else_label)

		# else 左侧 C 形臂
		var else_arm = Panel.new()
		else_arm.name = "CArmElse"
		else_arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else_arm.position = Vector2(else_local.position.x - arm_w, else_local.position.y)
		else_arm.size = Vector2(arm_w, else_local.size.y)
		else_arm.add_theme_stylebox_override("panel", arm_style)
		parent_node.add_child(else_arm)

		# else 区域
		var else_panel = Panel.new()
		else_panel.name = "ElseArea"
		else_panel.position = else_local.position
		else_panel.size = else_local.size
		else_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var else_style = StyleBoxFlat.new()
		else_style.bg_color = Color(color.r, color.g, color.b, 0.06)
		else_style.border_color = Color(dark_color.r, dark_color.g, dark_color.b, 0.35)
		else_style.set_border_width_all(int(1.5 * _canvas_zoom))
		else_style.set_corner_radius_all(int(4 * _canvas_zoom))
		else_panel.add_theme_stylebox_override("panel", else_style)
		parent_node.add_child(else_panel)

# ============================================
# 属性面板（保持原样，略作防御）
# ============================================
func _update_prop_panel():
	if _prop_panel == null:
		return
	if _selected_block_id >= 0 and _get_block_by_id(_selected_block_id).is_empty():
		_selected_block_id = -1
	if not _right_panel_visible:
		_right_panel_visible = true
		_right_panel.visible = true
	for child in _prop_panel.get_children():
		child.queue_free()
	var title = Label.new()
	title.text = "属性面板"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	_prop_panel.add_child(title)
	_prop_panel.add_child(HSeparator.new())
	if _selected_block_id < 0:
		var hint = Label.new()
		hint.text = "选中画布上的积木块\n以编辑其属性"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 13)
		_prop_panel.add_child(hint)
		return
	var block = _get_block_by_id(_selected_block_id)
	if block.is_empty():
		print("[visual_script_editor] 错误: 选中块ID=%d 但在_blocks中找不到" % _selected_block_id)
		return
	var def = block.def
	var type_label = Label.new()
	type_label.text = "类型: " + BlockType.keys()[def.type]
	type_label.add_theme_color_override("font_color", _get_block_color(block))
	type_label.add_theme_font_size_override("font_size", 14)
	_prop_panel.add_child(type_label)
	var name_label = Label.new()
	name_label.text = "名称: " + def.name
	name_label.add_theme_font_size_override("font_size", 12)
	_prop_panel.add_child(name_label)
	if _is_block_in_slot(block.id):
		var slot_hint = Label.new()
		slot_hint.text = "(嵌入在数值槽中)"
		slot_hint.add_theme_color_override("font_color", Color.CYAN)
		slot_hint.add_theme_font_size_override("font_size", 11)
		_prop_panel.add_child(slot_hint)
	if block.get("is_var_ref", false):
		var ref_hint = Label.new()
		var source_block = _get_block_by_id(block.get("source_block_id", -1))
		var source_label = source_block.def.label if not source_block.is_empty() else "???"
		var out_label = block.get("output_label", block.get("output_name", ""))
		ref_hint.text = "◆ 变量引用: %s . %s" % [source_label, out_label]
		ref_hint.add_theme_color_override("font_color", _get_output_color(block.get("output_type", "")))
		ref_hint.add_theme_font_size_override("font_size", 12)
		_prop_panel.add_child(ref_hint)
	var parent_cond = _find_parent_condition(block.id)
	if not parent_cond.is_empty():
		var inner_hint = Label.new()
		var slot_name = _find_inner_slot(parent_cond, block.id)
		inner_hint.text = "(在条件块的\"%s\"区域中)" % ("则" if slot_name == "then" else "否则")
		inner_hint.add_theme_color_override("font_color", Color.CYAN)
		inner_hint.add_theme_font_size_override("font_size", 11)
		_prop_panel.add_child(inner_hint)
	_prop_panel.add_child(HSeparator.new())
	if def.params.size() > 0:
		var param_title = Label.new()
		param_title.text = "参数"
		param_title.add_theme_color_override("font_color", Color.YELLOW)
		param_title.add_theme_font_size_override("font_size", 14)
		_prop_panel.add_child(param_title)
		for p in def.params:
			var hbox = HBoxContainer.new()
			var p_label = Label.new()
			p_label.text = p.label + ":"
			p_label.custom_minimum_size = Vector2(70, 0)
			p_label.add_theme_font_size_override("font_size", 12)
			hbox.add_child(p_label)
			if _is_slot_type(p.type):
				var vid = block.value_slots.get(p.name, -1)
				if vid >= 0:
					var vblock = _get_block_by_id(vid)
					if not vblock.is_empty():
						var info = Label.new()
						info.text = "[%s] %s" % [BlockType.keys()[BlockType.VALUE], vblock.def.label]
						info.add_theme_color_override("font_color", _get_block_color(vblock))
						info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						info.add_theme_font_size_override("font_size", 12)
						hbox.add_child(info)
						var remove_btn = Button.new()
						remove_btn.text = "移除"
						remove_btn.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
						remove_btn.pressed.connect(_on_remove_value_from_slot.bind(block.id, p.name))
						hbox.add_child(remove_btn)
					else:
						_add_param_editor(hbox, block, p)
				else:
					_add_param_editor(hbox, block, p)
			_prop_panel.add_child(hbox)
	_prop_panel.add_child(HSeparator.new())
	var pos_label = Label.new()
	pos_label.text = "位置: (%.0f, %.0f)" % [block.pos.x, block.pos.y]
	pos_label.add_theme_font_size_override("font_size", 12)
	_prop_panel.add_child(pos_label)
	_prop_panel.add_child(HSeparator.new())
	var delete_btn = Button.new()
	delete_btn.text = "删除此积木块"
	delete_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	delete_btn.pressed.connect(_on_delete_block_btn.bind(block.id))
	_prop_panel.add_child(delete_btn)
	_prop_panel.add_child(HSeparator.new())
	var export_btn = Button.new()
	export_btn.text = "导出JSON"
	export_btn.add_theme_color_override("font_color", Color.CYAN)
	export_btn.pressed.connect(_on_export_json)
	_prop_panel.add_child(export_btn)
	var clear_btn = Button.new()
	clear_btn.text = "清空画布"
	clear_btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
	clear_btn.pressed.connect(_on_clear_canvas)
	_prop_panel.add_child(clear_btn)

func _on_close_prop_panel():
	if _prop_panel: _prop_panel.release_focus()
	_right_panel_visible = false
	_right_panel.visible = false

func _add_param_editor(container: HBoxContainer, block: Dictionary, p: Dictionary):
	if p.type == "number":
		var spinbox = SpinBox.new()
		spinbox.min_value = -INT_MAX
		spinbox.max_value = INT_MAX
		spinbox.step = 0.001
		spinbox.value = block.params.get(p.name, p.default)
		spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spinbox.value_changed.connect(_on_param_changed.bind(block.id, p.name))
		container.add_child(spinbox)
	elif p.type == "bool":
		var checkbox = CheckBox.new()
		checkbox.button_pressed = block.params.get(p.name, p.default)
		checkbox.toggled.connect(_on_param_bool_changed.bind(block.id, p.name))
		container.add_child(checkbox)
	elif p.type == "dropdown":
		var opt_btn = OptionButton.new()
		opt_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var options = p.get("options", [])
		var current_val = str(block.params.get(p.name, p.default))
		for i in range(options.size()):
			opt_btn.add_item(str(options[i]))
			if str(options[i]) == current_val:
				opt_btn.select(i)
		opt_btn.item_selected.connect(_on_param_dropdown_changed.bind(block.id, p.name, p))
		container.add_child(opt_btn)
	elif p.type == "node":
		var line_edit = LineEdit.new()
		line_edit.text = str(block.params.get(p.name, p.default))
		line_edit.placeholder_text = "节点路径"
		line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_edit.text_changed.connect(_on_param_string_changed.bind(block.id, p.name))
		container.add_child(line_edit)
	elif p.type == "string":
		var line_edit = LineEdit.new()
		line_edit.text = str(block.params.get(p.name, p.default))
		line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_edit.text_changed.connect(_on_param_string_changed.bind(block.id, p.name))
		container.add_child(line_edit)
	elif p.type == "vector2":
		var default_val = p.default if p.default is Dictionary else {"x": 0.0, "y": 0.0}
		var current_val = block.params.get(p.name, default_val)
		if not current_val is Dictionary:
			current_val = {"x": 0.0, "y": 0.0}
		var x_label = Label.new()
		x_label.text = "X:"
		container.add_child(x_label)
		var x_spin = SpinBox.new()
		x_spin.min_value = -INT_MAX
		x_spin.max_value = INT_MAX
		x_spin.step = 0.001
		x_spin.value = current_val.get("x", 0.0)
		x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		x_spin.value_changed.connect(_on_param_vector2_changed.bind(block.id, p.name, "x"))
		container.add_child(x_spin)
		var y_label = Label.new()
		y_label.text = "Y:"
		container.add_child(y_label)
		var y_spin = SpinBox.new()
		y_spin.min_value = -INT_MAX
		y_spin.max_value = INT_MAX
		y_spin.step = 0.001
		y_spin.value = current_val.get("y", 0.0)
		y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		y_spin.value_changed.connect(_on_param_vector2_changed.bind(block.id, p.name, "y"))
		container.add_child(y_spin)
	elif p.type == "vector3":
		var default_val = p.default if p.default is Dictionary else {"x": 0.0, "y": 0.0, "z": 0.0}
		var current_val = block.params.get(p.name, default_val)
		if not current_val is Dictionary:
			current_val = {"x": 0.0, "y": 0.0, "z": 0.0}
		var x_label = Label.new()
		x_label.text = "X:"
		container.add_child(x_label)
		var x_spin = SpinBox.new()
		x_spin.min_value = -INT_MAX
		x_spin.max_value = INT_MAX
		x_spin.step = 0.001
		x_spin.value = current_val.get("x", 0.0)
		x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		x_spin.value_changed.connect(_on_param_vector3_changed.bind(block.id, p.name, "x"))
		container.add_child(x_spin)
		var y_label = Label.new()
		y_label.text = "Y:"
		container.add_child(y_label)
		var y_spin = SpinBox.new()
		y_spin.min_value = -INT_MAX
		y_spin.max_value = INT_MAX
		y_spin.step = 0.001
		y_spin.value = current_val.get("y", 0.0)
		y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		y_spin.value_changed.connect(_on_param_vector3_changed.bind(block.id, p.name, "y"))
		container.add_child(y_spin)
		var z_label = Label.new()
		z_label.text = "Z:"
		container.add_child(z_label)
		var z_spin = SpinBox.new()
		z_spin.min_value = -INT_MAX
		z_spin.max_value = INT_MAX
		z_spin.step = 0.001
		z_spin.value = current_val.get("z", 0.0)
		z_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		z_spin.value_changed.connect(_on_param_vector3_changed.bind(block.id, p.name, "z"))
		container.add_child(z_spin)
	elif p.type == "color":
		var default_color = {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}
		var cur_dict = block.params.get(p.name, p.default)
		if not cur_dict is Dictionary:
			cur_dict = default_color
		var cp = ColorPickerButton.new()
		cp.color = Color(cur_dict.get("r", 1.0), cur_dict.get("g", 1.0), cur_dict.get("b", 1.0), cur_dict.get("a", 1.0))
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp.custom_minimum_size = Vector2(60, 0)
		cp.get_popup().exclusive = true
		cp.color_changed.connect(_on_param_color_changed.bind(block.id, p.name))
		container.add_child(cp)

func _on_param_changed(value: float, block_id: int, param_name: String):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	_save_undo_state()
	block.params[param_name] = value
	_refresh_block_node_deferred(block_id)
	_update_prop_panel.call_deferred()
	_update_all_z_indices.call_deferred()
	if _is_block_in_slot(block_id):
		_reposition_all_chains.call_deferred()

func _on_param_bool_changed(pressed: bool, block_id: int, param_name: String):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	_save_undo_state()
	block.params[param_name] = pressed
	_refresh_block_node_deferred(block_id)
	_update_all_z_indices.call_deferred()
	if _is_block_in_slot(block_id):
		_reposition_all_chains.call_deferred()

func _on_param_string_changed(text: String, block_id: int, param_name: String):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	_save_undo_state()
	block.params[param_name] = text
	_refresh_block_node_deferred(block_id)
	_update_all_z_indices.call_deferred()
	if _is_block_in_slot(block_id):
		_reposition_all_chains.call_deferred()

func _on_param_vector2_changed(value: float, block_id: int, param_name: String, component: String):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	_save_undo_state()
	if not block.params.get(param_name) is Dictionary:
		block.params[param_name] = {"x": 0.0, "y": 0.0}
	block.params[param_name][component] = value
	_refresh_block_node_deferred(block_id)
	_update_prop_panel.call_deferred()
	_update_all_z_indices.call_deferred()
	if _is_block_in_slot(block_id):
		_reposition_all_chains.call_deferred()

func _on_param_vector3_changed(value: float, block_id: int, param_name: String, component: String):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	_save_undo_state()
	if not block.params.get(param_name) is Dictionary:
		block.params[param_name] = {"x": 0.0, "y": 0.0, "z": 0.0}
	block.params[param_name][component] = value
	_refresh_block_node_deferred(block_id)
	_update_prop_panel.call_deferred()
	_update_all_z_indices.call_deferred()
	if _is_block_in_slot(block_id):
		_reposition_all_chains.call_deferred()

func _on_param_dropdown_changed(index: int, block_id: int, param_name: String, p: Dictionary):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	var options = p.get("options", [])
	if index >= 0 and index < options.size():
		_save_undo_state()
		block.params[param_name] = options[index]
		_refresh_block_node_deferred(block_id)
		_update_all_z_indices.call_deferred()
		if _is_block_in_slot(block_id):
			_reposition_all_chains.call_deferred()

func _on_param_color_changed(color: Color, block_id: int, param_name: String):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	_save_undo_state()
	block.params[param_name] = {"r": color.r, "g": color.g, "b": color.b, "a": color.a}
	_refresh_block_node_deferred(block_id)
	_update_prop_panel.call_deferred()
	_update_all_z_indices.call_deferred()
	if _is_block_in_slot(block_id):
		_reposition_all_chains.call_deferred()

func _refresh_block_node_deferred(block_id: int):
	_refresh_block_node(block_id)

func _on_remove_value_from_slot(block_id: int, param_name: String):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	_save_undo_state()
	var vid = block.value_slots.get(param_name, -1)
	if vid >= 0:
		var vblock = _get_block_by_id(vid)
		if not vblock.is_empty():
			var top_parent = _find_top_level_parent(block_id)
			if not top_parent.is_empty():
				vblock.pos = top_parent.pos + Vector2(0, _get_block_height(top_parent) + 10)
			else:
				vblock.pos = block.pos + Vector2(0, _get_block_height(block) + 10)
		block.value_slots[param_name] = -1
		_slot_block_ids.erase(vid)
		_ensure_block_node(vid)
		var top_parent = _find_top_level_parent(block_id)
		if not top_parent.is_empty():
			_refresh_block_node(top_parent.id)
		else:
			_refresh_block_node(block_id)
		_reposition_all_chains()
		_update_prop_panel()

func _on_delete_block_btn(block_id: int):
	_save_undo_state()
	_delete_block(block_id)
	_update_prop_panel()

func _on_context_menu_pressed(id: int):
	if id == 0 and _context_menu_rclick_id >= 0:
		_save_undo_state()
		_duplicate_block_chain(_context_menu_rclick_id, false)
		_refresh_all_block_nodes()
		_rebuild_indexes()
		_relayout_all_conditions()
	elif id == 1:
		_refresh_all_block_nodes()
	_context_menu_rclick_id = -1

func _duplicate_block_chain(block_id: int, copy_stack: bool = false):
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	var ids_to_copy: Array = []
	_collect_chain_for_copy(block_id, ids_to_copy, copy_stack)
	if ids_to_copy.is_empty(): return
	var id_map: Dictionary = {}
	for old_id in ids_to_copy:
		var new_id = _block_id_counter
		_block_id_counter += 1
		id_map[old_id] = new_id
	var new_blocks: Array = []
	for old_id in ids_to_copy:
		var old = _get_block_by_id(old_id)
		if old.is_empty(): continue
		var new_b = {
			"def": old.def,
			"pos": old.pos,
			"params": _deep_copy_params(old.params, old.def),
			"id": id_map[old_id],
			"value_slots": {},
			"inner_block_ids": [],
			"inner_else_ids": [],
			"output_refs": {},
			"is_var_ref": old.get("is_var_ref", false),
			"source_block_id": -1,
			"output_name": old.get("output_name", ""),
			"output_type": old.get("output_type", ""),
			"output_label": old.get("output_label", ""),
			"stack_below_id": -1,
		}
		for pname in old.value_slots:
			var vsid = old.value_slots[pname]
			if vsid >= 0 and id_map.has(vsid):
				new_b.value_slots[pname] = id_map[vsid]
			else:
				new_b.value_slots[pname] = vsid
		if old.def.type == BlockType.CONDITION:
			for iid in old.inner_block_ids:
				if id_map.has(iid): new_b.inner_block_ids.append(id_map[iid])
			for iid in old.inner_else_ids:
				if id_map.has(iid): new_b.inner_else_ids.append(id_map[iid])
		if new_b.is_var_ref:
			var old_src = old.get("source_block_id", -1)
			if old_src >= 0 and id_map.has(old_src):
				new_b.source_block_id = id_map[old_src]
		if old.has("output_refs"):
			for out_name in old.output_refs:
				var refs: Array = []
				for rid in old.output_refs[out_name]:
					if id_map.has(rid):
						refs.append(id_map[rid])
				if refs.size() > 0:
					new_b.output_refs[out_name] = refs
		new_blocks.append(new_b)
	var offset_x = _get_block_width(block) + 60.0
	var offset_y = _get_block_height(block) + 40.0
	var top_new = _get_block_by_id(id_map[block_id])
	if not top_new.is_empty():
		top_new.pos.x += offset_x
		top_new.pos.y += offset_y
	for nb in new_blocks:
		_blocks.append(nb)
		_blocks_by_id[nb.id] = nb
	for nb in new_blocks:
		for iid in nb.inner_block_ids:
			_inner_block_ids_set[iid] = true
		for iid in nb.inner_else_ids:
			_inner_block_ids_set[iid] = true
	_relayout_all_conditions()
	var new_top_id = id_map[block_id]
	_selected_block_id = new_top_id
	_update_prop_panel()

func _collect_chain_for_copy(block_id: int, result: Array, copy_stack: bool):
	if block_id in result: return
	result.append(block_id)
	var block = _get_block_by_id(block_id)
	if block.is_empty(): return
	if copy_stack:
		var below_id = block.get("stack_below_id", -1)
		if below_id >= 0:
			_collect_chain_for_copy(below_id, result, copy_stack)
	for pname in block.value_slots:
		var vsid = block.value_slots[pname]
		if vsid >= 0:
			_collect_chain_for_copy(vsid, result, copy_stack)
	if block.def.type == BlockType.CONDITION:
		for iid in block.inner_block_ids + block.inner_else_ids:
			_collect_chain_for_copy(iid, result, copy_stack)
	if block.get("is_var_ref", false):
		var src_id = block.get("source_block_id", -1)
		if src_id >= 0:
			_collect_chain_for_copy(src_id, result, copy_stack)
	if block.has("output_refs"):
		for out_name in block.output_refs:
			for rid in block.output_refs[out_name]:
				_collect_chain_for_copy(rid, result, copy_stack)

func _deep_copy_params(src_params: Dictionary, def: Dictionary) -> Dictionary:
	var result = {}
	for p in def.params:
		var val = src_params.get(p.name, p.default)
		if val is Dictionary:
			result[p.name] = val.duplicate()
		else:
			result[p.name] = val
	return result

# ============================================
# 导出与清空
# ============================================
func _update_title():
	var base_title = "图形化脚本编辑器"
	if _entity_scene_path != "":
		var trimmed = _entity_scene_path.trim_prefix("res://assets/entities/")
		var last_slash = trimmed.rfind("/")
		var project_name = trimmed.substr(0, last_slash) if last_slash >= 0 else trimmed
		base_title += " - " + project_name
	if _dirty:
		title = "*" + base_title
	else:
		title = base_title

func _get_script_path() -> String:
	if _entity_scene_path == "": return ""
	return _entity_scene_path.get_base_dir() + "/" + SAVE_FILE_NAME

func _save_script():
	if _save_timer:
		_save_timer.stop()
	_do_save_with_progress()

func _do_save_with_progress():
	await _show_progress("正在保存脚本...")
	if _entity_scene_path == "": 
		_hide_progress()
		return
	if _save_pending:
		_hide_progress()
		return
	_save_pending = true
	await _update_progress(0.3, "序列化数据...")
	var data = _serialize_all()
	await _update_progress(0.6, "写入文件...")
	var json_str = JSON.stringify(data, "\t")
	var file_path = _get_script_path()
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		_last_saved_json = json_str
		_dirty = false
		_update_title()
		await _update_progress(1.0, "保存完成")
		print("[visual_script_editor] 脚本已保存到: ", file_path)
	else:
		push_error("[visual_script_editor] 无法写入文件: " + file_path)
	_save_pending = false
	_hide_progress()

func _on_export_json():
	_save_script()

# 统一保存所有数据（内部调用，无进度条）
func _save_all_data(data: Dictionary = {}):
	if _entity_scene_path == "": return
	if _save_pending: return
	if data.is_empty():
		data = _serialize_all()
	_save_pending = true
	var json_str = JSON.stringify(data, "\t")
	var file_path = _get_script_path()
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		_last_saved_json = json_str
		_dirty = false
		_update_title()
		print("[visual_script_editor] 脚本已保存到: ", file_path)
	else:
		push_error("[visual_script_editor] 无法写入文件: " + file_path)
	_save_pending = false

# 旧接口保留兼容：返回完整数据的 JSON 字符串
func _serialize_blocks_json() -> String:
	return _serialize_all_json()

# 仅序列化画布积木数据（数组）
func _serialize_blocks_data() -> Array:
	var blocks_data = []
	for block in _blocks:
		var vs = {}
		for k in block.value_slots:
			vs[k] = block.value_slots[k]
		var is_root = not _is_block_in_slot(block.id) and not _is_inner_block(block.id) and _find_block_above(block.id).is_empty()
		var pos_data = {"x": block.pos.x, "y": block.pos.y} if is_root else {}
		var entry = {
			"id": block.id,
			"name": block.def.name,
			"type": BlockType.keys()[block.def.type],
			"position": pos_data,
			"params": block.params,
			"value_slots": vs,
			"inner_block_ids": block.inner_block_ids.duplicate(),
			"inner_else_ids": block.inner_else_ids.duplicate(),
			"is_var_ref": block.get("is_var_ref", false),
			"source_block_id": block.get("source_block_id", -1),
			"output_name": block.get("output_name", ""),
			"output_type": block.get("output_type", ""),
			"output_label": block.get("output_label", ""),
			"stack_below_id": block.get("stack_below_id", -1),
		}
		blocks_data.append(entry)
	return blocks_data

# 序列化事件表数据（字典，含 rows 数组）
func _serialize_events_data() -> Dictionary:
	var rows_out = []
	for row in _events_data.get("rows", []):
		var copy = row.duplicate(true)
		_strip_collapsed_recursive(copy)
		rows_out.append(copy)
	return {"rows": rows_out}

## 递归移除所有节点的 collapsed（存入 ui_state）
func _strip_collapsed_recursive(node: Dictionary):
	node.erase("collapsed")
	for child in node.get("children", []):
		_strip_collapsed_recursive(child)
	for child in node.get("rows", []):
		_strip_collapsed_recursive(child)

## 递归移除所有节点的 _uid（粘贴时使用）
func _strip_uid_recursive(node: Dictionary):
	node.erase("_uid")
	for child in node.get("children", []):
		_strip_uid_recursive(child)
	for child in node.get("rows", []):
		_strip_uid_recursive(child)

## 提取 UI 状态（折叠、颜色等）
func _serialize_ui_state() -> Dictionary:
	var collapsed = {}
	var colors = {}
	_collect_ui_state(_events_data.get("rows", []), collapsed, colors)
	var state = {"col_collapsed": collapsed}
	if not colors.is_empty():
		state["group_colors"] = colors
	return state

func _collect_ui_state(rows: Array, collapsed: Dictionary, colors: Dictionary):
	for row in rows:
		var uid = row.get("_uid", "")
		if uid != "" and row.has("collapsed"):
			collapsed[uid] = row.get("collapsed", false)
		if row.get("type") == "group" and row.has("color"):
			var c = row["color"]
			if c is Color:
				colors[row.get("name", "")] = [c.r, c.g, c.b, c.a]
		_collect_ui_state(row.get("children", []), collapsed, colors)
		_collect_ui_state(row.get("rows", []), collapsed, colors)

# 序化全部数据（version + blocks + events + ui_state）
func _serialize_all() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"blocks": _serialize_blocks_data(),
		"events": _serialize_events_data(),
		"ui_state": _serialize_ui_state(),
		"run_mode": _run_mode,
		"editor_mode": _current_mode,
	}

func _serialize_all_json() -> String:
	return JSON.stringify(_serialize_all(), "\t")

func _mark_dirty():
	if not _dirty:
		_dirty = true
		_update_title()

# ---- 进度条系统 ----
func _show_progress(title: String = "处理中..."):
	if not _progress_overlay:
		return
	_progress_overlay.visible = true
	_progress_overlay.z_index = 10000
	_progress_bar.value = 0.0
	_progress_label.text = title
	await get_tree().process_frame

func _update_progress(ratio: float, text: String = ""):
	if not _progress_overlay or not _progress_overlay.visible:
		return
	_progress_bar.value = clamp(ratio, 0.0, 1.0) * 100.0
	if text != "":
		_progress_label.text = text
	await get_tree().process_frame

func _hide_progress():
	if not _progress_overlay:
		return
	_progress_overlay.visible = false

# 防抖保存超时回调
func _on_save_timer_timeout():
	if _dirty and not _is_editing_block_defs:
		_do_save_with_progress()
	# 恢复默认等待时间
	if _save_timer:
		_save_timer.wait_time = 0.5

func _on_clear_canvas():
	_save_undo_state()
	_blocks.clear()
	_blocks_by_id.clear()
	_slot_block_ids.clear()
	_inner_block_ids_set.clear()
	for bid in _block_nodes.keys():
		_remove_block_node(bid)
	_selected_block_id = -1
	_block_id_counter = 0
	_update_prop_panel()

# ============================================
# 加载脚本数据（支持版本检测 / 备份 / 迁移）
# ============================================
func _load_json_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
	var json_str = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_str) != OK:
		print("[visual_script_editor] 解析 JSON 失败 (%s): %s" % [file_path, json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		return {}
	return json.data

func _backup_file(file_path: String) -> String:
	var dir = file_path.get_base_dir()
	var stamp = Time.get_datetime_string_from_system().replace(":", "-")
	var backup_name = file_path.get_file() + ".backup_" + stamp
	var backup_path = dir + "/" + backup_name
	var old = FileAccess.open(file_path, FileAccess.READ)
	if old:
		var content = old.get_as_text()
		old.close()
		var nf = FileAccess.open(backup_path, FileAccess.WRITE)
		if nf:
			nf.store_string(content)
			nf.close()
			print("[visual_script_editor] 备份已保存至：", backup_path)
	return backup_path

# 将 v1 数据迁移到 v2 结构。v1 顶层为 {"blocks":[...]}（无 version 字段）。
func _migrate_to_v2(old_data: Dictionary) -> Dictionary:
	var blocks = old_data.get("blocks", [])
	return {
		"version": SAVE_VERSION,
		"blocks": blocks,
		"events": {"rows": []},
	}

# 弹出升级提示对话框
func _show_upgrade_notice(old_version: int):
	var dialog = AcceptDialog.new()
	dialog.title = "数据已自动升级"
	dialog.dialog_text = "检测到旧版本数据(v%d)，已自动备份并升级到版本 %d。" % [old_version, SAVE_VERSION]
	dialog.ok_button_text = "确定"
	dialog.min_size = Vector2(420, 140)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)

# 清空事件表内存数据（不影响已保存文件）
func _clear_events_data():
	_events_data = {"rows": []}
	_event_row_id_counter = 1000
	_row_uid_counter = 1
	_selected_event_row_id = -1

func _next_uid() -> String:
	var uid = _row_uid_counter
	_row_uid_counter += 1
	return "_%d" % uid

# 从字典加载事件表数据到内存（兼容旧 conditions/actions 结构）
func _load_events_data(events_dict: Dictionary, ui_state: Dictionary = {}):
	_clear_events_data()
	_ui_state = ui_state
	var rows = events_dict.get("rows", [])
	var colors_map = ui_state.get("group_colors", {})
	var max_id = 999
	for row in rows:
		var r = row.duplicate(true)
		if r.get("type") == "group":
			# 分组行：递归加载内部事件
			if not r.has("name"):
				r["name"] = "新分组"
			if not r.has("_uid"):
				r["_uid"] = _next_uid()
			if not r.has("color") and colors_map.has(r.get("name", "")):
				var c_arr = colors_map[r["name"]]
				r["color"] = Color(c_arr[0], c_arr[1], c_arr[2], c_arr[3])
			if not r.has("rows"):
				r["rows"] = []
			var group_rows = _load_rows_recursive(r.get("rows", []), max_id)
			r["rows"] = group_rows[0]
			max_id = group_rows[1]
		elif r.get("type") == "comment":
			# 注释行：只需确保 _uid 和 enabled
			if not r.has("_uid"):
				r["_uid"] = _next_uid()
			if not r.has("enabled"):
				r["enabled"] = true
			if not r.has("text"):
				r["text"] = ""
		else:
			var processed = _normalize_event_row(r, max_id)
			r = processed[0]
			max_id = processed[1]
		_events_data.rows.append(r)
	_event_row_id_counter = max_id + 1
	# 从 ui_state 恢复所有节点的折叠状态
	_apply_ui_collapsed(_events_data.rows)

## 递归加载分组内的事件行
func _load_rows_recursive(rows: Array, current_max_id: int, colors_map: Dictionary = {}) -> Array:
	var max_id = current_max_id
	var out = []
	for row in rows:
		var r = row.duplicate(true)
		if r.get("type") == "group":
			if not r.has("_uid"):
				r["_uid"] = _next_uid()
			if not r.has("color") and colors_map.has(r.get("name", "")):
				var c_arr = colors_map[r["name"]]
				r["color"] = Color(c_arr[0], c_arr[1], c_arr[2], c_arr[3])
			var loaded = _load_rows_recursive(r.get("rows", []), max_id, colors_map)
			r["rows"] = loaded[0]
			max_id = loaded[1]
		elif r.get("type") == "comment":
			if not r.has("_uid"):
				r["_uid"] = _next_uid()
			if not r.has("text"):
				r["text"] = ""
		else:
			var processed = _normalize_event_row(r, max_id)
			r = processed[0]
			max_id = processed[1]
		out.append(r)
	return [out, max_id]

## 从 ui_state 恢复所有节点的折叠状态（递归）
func _apply_ui_collapsed(rows: Array):
	var col_map = _ui_state.get("col_collapsed", _ui_state.get("group_collapsed", {}))
	for row in rows:
		var uid = row.get("_uid", "")
		if uid != "" and col_map.has(uid):
			row["collapsed"] = col_map[uid]
		elif uid != "" and col_map.has(str(uid)):
			row["collapsed"] = col_map[str(uid)]
		_apply_ui_collapsed(row.get("children", []))
		_apply_ui_collapsed(row.get("rows", []))

## 规范化单条事件行
func _normalize_event_row(r: Dictionary, current_max_id: int) -> Array:
	var max_id = current_max_id
	if not r.has("id"):
		r["id"] = _event_row_id_counter
	if not r.has("_uid"):
		r["_uid"] = _next_uid()
	if not r.has("enabled"):
		r["enabled"] = true
	if not r.has("exprs"):
		r["exprs"] = {}
	r.erase("value_slots")
	r.erase("value_blocks")
	if not r.has("children"):
		var children = []
		for c in r.get("conditions", []):
			children.append(_normalize_event_node(c))
		for a in r.get("actions", []):
			children.append(_normalize_event_node(a))
		r["children"] = children
		r.erase("conditions")
		r.erase("actions")
	else:
		var normalized = []
		for c in r.children:
			normalized.append(_normalize_event_node(c))
		r["children"] = normalized
	if int(r.id) > max_id:
		max_id = int(r.id)
	return [r, max_id]

# 规范化事件节点：确保有 block_name/params/exprs/children
func _normalize_event_node(node: Dictionary) -> Dictionary:
	var n = node.duplicate(true)
	if not n.has("_uid"):
		n["_uid"] = _next_uid()
	if not n.has("block_name"):
		n["block_name"] = n.get("name", "?")
	if not n.has("params"):
		n["params"] = {}
	# 事件表使用 exprs 字段存储参数表达式字符串
	if not n.has("exprs"):
		n["exprs"] = {}
	# 旧数据可能携带 value_slots/value_blocks，事件表不再使用，移除
	n.erase("value_slots")
	n.erase("value_blocks")
	if not n.has("children"):
		var children = []
		# 兼容旧的 conditions/actions
		for c in n.get("conditions", []):
			children.append(_normalize_event_node(c))
		for a in n.get("actions", []):
			children.append(_normalize_event_node(a))
		n["children"] = children
	else:
		var normalized = []
		for c in n.children:
			normalized.append(_normalize_event_node(c))
		n["children"] = normalized
	n.erase("conditions")
	n.erase("actions")
	return n

func _load_script_data():
	if _entity_scene_path == "":
		print("[visual_script_editor] 实体场景路径为空，跳过加载")
		return
	var file_path = _get_script_path()
	if not FileAccess.file_exists(file_path):
		print("[visual_script_editor] 未找到脚本文件: ", file_path)
		return
	# Step 1: 显示进度条
	await _show_progress("正在加载脚本...")
	# Step 2: 读取文件
	await _update_progress(0.05, "读取文件...")
	var data = _load_json_file(file_path)
	if data.is_empty():
		print("[visual_script_editor] JSON 数据无效或为空: ", file_path)
		_hide_progress()
		return

	# 版本检测与升级
	var version = int(data.get("version", 1))
	if version < SAVE_VERSION:
		await _update_progress(0.1, "数据迁移中...")
		_backup_file(file_path)
		data = _migrate_to_v2(data)
		_save_all_data(data)
		print("[visual_script_editor] 数据已从 v%d 迁移到 v%d" % [version, SAVE_VERSION])
		_show_upgrade_notice(version)

	if not data.has("blocks"):
		print("[visual_script_editor] 数据缺少 blocks 字段")
		_hide_progress()
		return

	await _update_progress(0.15, "清空旧数据...")
	# 清空当前数据
	_blocks.clear()
	_block_id_counter = 0
	_selected_block_id = -1
	for bid in _block_nodes.keys():
		_remove_block_node(bid)
	_blocks_by_id.clear()
	_slot_block_ids.clear()
	_inner_block_ids_set.clear()

	var loaded_count = 0
	var missing_def_count = 0
	var total_blocks = data.blocks.size()
	var chunk_size = max(1, total_blocks / 20)  # 分 ~20 步

	await _update_progress(0.2, "加载积木块...")
	for entry in data.blocks:
		var def = _find_block_def(entry.name)
		# 找不到定义时，构造一个基本定义
		if def.is_empty():
			missing_def_count += 1
			print("[visual_script_editor] 警告: 块 '%s' (ID:%d) 没有定义，将创建临时定义" % [entry.name, entry.id])
			# 根据 entry 构造默认定义
			var type_str = entry.get("type", "ACTION")
			var type_enum = BlockType.keys().find(type_str)
			if type_enum == -1:
				type_enum = BlockType.ACTION
			# 构造参数列表
			var params = []
			for pname in entry.params.keys():
				var pdefault = entry.params[pname]
				var ptype = "string"
				if pdefault is bool:
					ptype = "bool"
				elif pdefault is float or pdefault is int:
					ptype = "number"
				elif pdefault is Dictionary:
					if pdefault.has("x") and pdefault.has("y") and pdefault.has("z"):
						ptype = "vector3"
					elif pdefault.has("x") and pdefault.has("y"):
						ptype = "vector2"
					else:
						ptype = "string"
				params.append({
					"name": pname,
					"type": ptype,
					"default": pdefault,
					"label": pname,
				})
			def = {
				"type": type_enum,
				"name": entry.name,
				"label": entry.name,  # 临时标签，可后续编辑
				"category": "未分类",
				"params": params,
				"outputs": entry.get("outputs", []),
			}
			# 添加到 _block_defs 以便后续保存
			_block_defs.append(def)
			print("[visual_script_editor] 为块 '%s' 创建了临时定义，请之后在块定义编辑器中完善" % entry.name)

		# 构建参数
		var params = {}
		for p in def.params:
			var val = entry.params.get(p.name, null)
			if val != null:
				params[p.name] = val
			else:
				if p.default is Dictionary:
					params[p.name] = p.default.duplicate()
				else:
					params[p.name] = p.default

		# 构建 value_slots
		var value_slots = {}
		if entry.has("value_slots"):
			for k in entry.value_slots:
				value_slots[k] = int(entry.value_slots[k])

		var inner_block_ids = []
		if entry.has("inner_block_ids"):
			for iid in entry.inner_block_ids:
				inner_block_ids.append(int(iid))
		var inner_else_ids = []
		if entry.has("inner_else_ids"):
			for iid in entry.inner_else_ids:
				inner_else_ids.append(int(iid))

		var block_id = int(entry.id)
		var pos_x = entry.position.get("x", 0.0) if entry.has("position") else 0.0
		var pos_y = entry.position.get("y", 0.0) if entry.has("position") else 0.0

		var block = {
			"def": def,
			"pos": Vector2(pos_x, pos_y),
			"params": params,
			"id": block_id,
			"value_slots": value_slots,
			"inner_block_ids": inner_block_ids,
			"inner_else_ids": inner_else_ids,
			"output_refs": {},
			"is_var_ref": entry.get("is_var_ref", false),
			"source_block_id": int(entry.get("source_block_id", -1)),
			"output_name": entry.get("output_name", ""),
			"output_type": entry.get("output_type", ""),
			"output_label": entry.get("output_label", ""),
			"stack_below_id": int(entry.get("stack_below_id", -1)),
		}

		_blocks.append(block)
		if block_id >= _block_id_counter:
			_block_id_counter = block_id + 1
		loaded_count += 1
		# 进度条更新（每 chunk 更新一次）
		if loaded_count % chunk_size == 0:
			var ratio = 0.2 + (float(loaded_count) / float(total_blocks)) * 0.5
			await _update_progress(ratio, "加载积木块 %d/%d..." % [loaded_count, total_blocks])

	print("[visual_script_editor] 加载统计: 总块数=%d, 缺失定义=%d, 成功加载=%d" % [len(data.blocks), missing_def_count, loaded_count])

	await _update_progress(0.75, "重建索引...")
	_rebuild_indexes()

	await _update_progress(0.78, "修复引用...")
	# 修复变量引用块的标签
	for block in _blocks:
		if block.get("is_var_ref", false):
			var src_id = block.get("source_block_id", -1)
			var out_name = block.get("output_name", "")
			if src_id >= 0 and _blocks_by_id.has(src_id):
				var src_block = _blocks_by_id[src_id]
				for out_def in _ensure_outputs(src_block.def):
					if out_def.name == out_name:
						var new_label = "◆ %s" % out_def.label
						if block.def.label != new_label:
							block.def.label = new_label
						if block.def.category != src_block.def.category:
							block.def.category = src_block.def.category
						break

	await _update_progress(0.82, "重排链条...")
	_reposition_all_chains()

	# 重建变量引用关系（output_refs）
	for block in _blocks:
		if block.get("is_var_ref", false):
			var src_id = block.get("source_block_id", -1)
			var out_name = block.get("output_name", "")
			if src_id >= 0:
				var src_block = _get_block_by_id(src_id)
				if not src_block.is_empty():
					if not src_block.has("output_refs"):
						src_block["output_refs"] = {}
					if not src_block.output_refs.has(out_name):
						src_block.output_refs[out_name] = []
					if block.id not in src_block.output_refs[out_name]:
						src_block.output_refs[out_name].append(block.id)

	await _update_progress(0.88, "创建视觉节点...")
	# 创建视觉节点（仅创建视口内的）
	for block in _blocks:
		if not _is_block_in_slot(block.id):
			_create_block_node(block)

	await _update_progress(0.92, "更新UI...")
	# 更新画布变换
	_update_canvas_transform()
	if _blocks.size() > 0:
		_selected_block_id = _blocks[0].id
	else:
		_selected_block_id = -1
	_update_prop_panel()
	_update_all_z_indices()
	_selected_block_id = -1
	if _blocks.size() > 0:
		_selected_block_id = _blocks[0].id
	_update_prop_panel()
	print("[visual_script_editor] 加载完成，当前共有 %d 个积木块" % _blocks.size())
	# 加载事件表数据
	if data.has("events"):
		_load_events_data(data.events, data.get("ui_state", {}))
	else:
		_clear_events_data()
	# 加载运行模式
	_run_mode = data.get("run_mode", "both")
	if _run_mode_opt:
		match _run_mode:
			"blocks_only": _run_mode_opt.select(1)
			"events_only": _run_mode_opt.select(2)
			_: _run_mode_opt.select(0)
	_last_saved_json = _serialize_blocks_json()
	_dirty = false
	_update_title()
	# 加载编辑器模式
	var saved_mode = data.get("editor_mode", EditorMode.EVENT)
	if saved_mode == EditorMode.BLOCK or saved_mode == EditorMode.EVENT:
		_current_mode = saved_mode
	_update_mode_buttons()
	# 根据当前模式渲染
	_switch_editor_mode(_current_mode)
	await _update_progress(1.0, "加载完成")
	_hide_progress()

func _find_block_def(name: String) -> Dictionary:
	for def in _block_defs:
		if def.name == name: return def
	return {}

# ============================================
# 编辑器模式切换
# ============================================
func _on_mode_switch(mode: int):
	if _current_mode == mode:
		_update_mode_buttons()
		return
	_current_mode = mode
	_update_mode_buttons()
	_switch_editor_mode(mode)

func _update_mode_buttons():
	if _mode_block_btn:
		_mode_block_btn.button_pressed = (_current_mode == EditorMode.BLOCK)
	if _mode_event_btn:
		_mode_event_btn.button_pressed = (_current_mode == EditorMode.EVENT)

func _on_run_mode_changed(idx: int):
	match idx:
		0: _run_mode = "both"
		1: _run_mode = "blocks_only"
		2: _run_mode = "events_only"
		_: _run_mode = "both"

func _show_help_dialog():
	var d = AcceptDialog.new()
	d.title = "操作说明"
	d.min_size = Vector2(500, 250)
	d.dialog_text = ""
	add_child(d)
	d.get_ok_button().visible = false
	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.add_child(vbox)
	var lines = [
		"--- 积木模式 ---",
		"• 左键拖拽积木块到画布",
		"• 中键平移画布",
		"• 滚轮缩放画布",
		"• 右键打开积木块菜单",
		"",
		"--- 事件表模式 ---",
		"• 双击左侧积木块添加到事件表",
		"• 选中条件块后添加 → 加到条件块下",
		"• 双击代码行编辑参数",
		"• 双击目标块执行「移动到块下」",
		"",
		"提示: 在标签中使用 {参数名} 可将参数槽位内联显示",
	]
	for l in lines:
		var lb = Label.new()
		lb.text = l
		lb.add_theme_font_size_override("font_size", 12)
		if l.begins_with("---"):
			lb.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		vbox.add_child(lb)
	var btn_hbox = HBoxContainer.new()
	vbox.add_child(btn_hbox)
	var close_btn = Button.new()
	close_btn.text = "关闭"
	btn_hbox.add_child(close_btn)
	close_btn.pressed.connect(func(): d.queue_free())
	d.popup_centered()

func _switch_editor_mode(mode: int):
	# 清除当前所有渲染
	_clear_block_rendering()
	_clear_event_rendering()
	if mode == EditorMode.BLOCK:
		if _event_container:
			_event_container.visible = false
		if _canvas:
			_canvas.visible = true
		_render_blocks()
		_update_prop_panel()
	else:
		if _canvas:
			_canvas.visible = false
		if _event_container:
			_event_container.visible = true
		_render_events()
		_update_event_prop_panel()
	# 刷新左侧块列表（按模式过滤）
	_refresh_block_list()

func _clear_block_rendering():
	if _canvas:
		_canvas.visible = false

func _render_blocks():
	if _canvas:
		_canvas.visible = true

# ============================================
# 事件表渲染
# ============================================
func _clear_event_rendering():
	if _event_tree:
		_event_tree.clear()

# 通用消息弹窗
func _show_message_dialog(msg: String):
	var dialog = AcceptDialog.new()
	dialog.title = "提示"
	dialog.dialog_text = msg
	dialog.ok_button_text = "确定"
	dialog.min_size = Vector2(300, 100)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)

# 获取块定义的显示标签（带参数填充）
func _format_event_node_text(node: Dictionary) -> String:
	var def = _find_block_def(node.get("block_name", ""))
	var label = node.get("block_name", "?")
	if not def.is_empty() and def.has("label"):
		label = def.label
	var params = node.get("params", {})
	var exprs = node.get("exprs", {})
	for k in params:
		var display_val = str(params[k])
		# 有表达式时用括号包裹显示
		if exprs.has(k):
			display_val = "(%s)" % exprs[k]
		label = label.replace("{%s}" % k, display_val)
	# 分号换行（类似积木块分段显示）
	label = label.replace(";", "\n")
	return label

# 递归渲染事件节点到 Tree
# inherited_disabled: 父节点被禁用时，子节点链全部继承灰色显示
func _render_event_node(parent_item: TreeItem, node: Dictionary, is_root: bool, inherited_disabled: bool = false):
	if node.get("type") == "comment":
		_render_comment_node(parent_item, node)
		return
	var item = _event_tree.create_item(parent_item)
	var text = _format_event_node_text(node)
	# 显示文本 + 状态前缀（不启用复选框编辑）
	var status_text = "[%s] " % ("启用" if node.get("enabled", true) else "禁用")
	var display = status_text + text
	item.set_text(0, display)
	item.set_editable(0, false)
	var line_count = display.count("\n") + 1
	if line_count > 1:
		item.set_custom_minimum_height(line_count * 22)
	# metadata(0) 只存整数 ID，通过 _event_node_map 查找节点
	var nid = _event_node_id_counter
	_event_node_id_counter += 1
	_event_node_map[nid] = node
	item.set_metadata(0, nid)
	# 父块被禁用时，子块链全部变灰
	var self_disabled = not bool(node.get("enabled", true))
	if self_disabled or inherited_disabled:
		item.set_custom_color(0, Color(0.45, 0.45, 0.45))
	# 恢复折叠状态
	var children_list = node.get("children", [])
	if not children_list.is_empty():
		item.set_collapsed(node.get("collapsed", false))
	# 递归子节点：若当前节点禁用，子节点继承灰色
	var child_inherited = inherited_disabled or self_disabled
	for child in children_list:
		_render_event_node(item, child, false, child_inherited)

func _render_events():
	if not _event_tree:
		return
	_event_node_map.clear()
	_event_node_id_counter = 0
	_event_tree.clear()
	var root = _event_tree.create_item()
	for row in _events_data.get("rows", []):
		if row.get("type") == "group":
			_render_group_node(root, row)
		elif row.get("type") == "comment":
			_render_comment_node(root, row)
		else:
			_render_event_node(root, row, true)
	_event_apply_search()

## 渲染分组节点（可折叠，支持启用/禁用）
func _render_group_node(parent_item: TreeItem, group: Dictionary, inherited_disabled: bool = false):
	var item = _event_tree.create_item(parent_item)
	var name = group.get("name", "新分组")
	var status_text = "[%s] " % ("启用" if group.get("enabled", true) else "禁用")
	item.set_text(0, status_text + name)
	item.set_editable(0, false)
	item.set_selectable(0, true)
	# 分组颜色：自定义颜色（默认黄色），禁用时灰色
	var base_color = Color(0.9, 0.85, 0.6)
	if group.has("color") and group["color"] is Color:
		base_color = group["color"]
	item.set_custom_color(0, base_color)
	var self_disabled = not bool(group.get("enabled", true))
	if self_disabled or inherited_disabled:
		item.set_custom_color(0, Color(0.45, 0.45, 0.45))
	# metadata 存特殊标记
	var nid = _event_node_id_counter
	_event_node_id_counter += 1
	_event_node_map[nid] = group
	item.set_metadata(0, nid)
	# 分组可折叠
	item.set_collapsed(group.get("collapsed", false))
	# 递归渲染分组内的事件（分组禁用则子元素继承灰色）
	var child_inherited = inherited_disabled or self_disabled
	for row in group.get("rows", []):
		if row.get("type") == "group":
			_render_group_node(item, row, child_inherited)
		elif row.get("type") == "comment":
			_render_comment_node(item, row)
		else:
			_render_event_node(item, row, true, child_inherited)

## 渲染注释节点（灰色斜体，只读）
func _render_comment_node(parent_item: TreeItem, comment: Dictionary):
	var item = _event_tree.create_item(parent_item)
	item.set_text(0, "// " + comment.get("text", "注释文字"))
	item.set_editable(0, false)
	item.set_selectable(0, true)
	item.set_custom_color(0, Color(0.5, 0.5, 0.5))
	# metadata
	var nid = _event_node_id_counter
	_event_node_id_counter += 1
	_event_node_map[nid] = comment
	item.set_metadata(0, nid)
	# 注释可折叠 false（无子节点）

# 通过 metadata 中的整数 ID 查 map
func _get_node_from_item(item: TreeItem) -> Dictionary:
	if item == null:
		return {}
	var nid = item.get_metadata(0)
	# nid 可能是 int 或其它类型，统一用 int() 转换
	var key = int(nid) if nid != null else -1
	if _event_node_map.has(key):
		return _event_node_map[key]
	return {}

# 判断 TreeItem 是否为根事件行（顶层事件，不含分组内的）
func _is_root_event_item(item: TreeItem) -> bool:
	if item == null or not _event_tree:
		return false
	return item.get_parent() == _event_tree.get_root()

# 判断是否为分组内的事件（其父节点是分组）
func _is_event_in_group(item: TreeItem) -> bool:
	if item == null or not _event_tree:
		return false
	var parent = item.get_parent()
	if not parent:
		return false
	var parent_node = _get_node_from_item(parent)
	return not parent_node.is_empty() and parent_node.get("type") == "group"

# 判断是否为可粘贴为根级事件（在根 rows 或分组 rows 中）
func _is_event_like_root(item: TreeItem) -> bool:
	if item == null or not _event_tree:
		return false
	return _is_root_event_item(item) or _is_event_in_group(item)

# 判断 TreeItem 是否为分组节点
func _is_group_item(item: TreeItem) -> bool:
	if item == null:
		return false
	var node = _get_node_from_item(item)
	return node.get("type") == "group"

# 向上查找所属根事件 TreeItem（跳过分组节点，找到最外层的 TreeItem）
func _get_root_item_of(item: TreeItem) -> TreeItem:
	if item == null or not _event_tree:
		return null
	var root = _event_tree.get_root()
	var cur = item
	while cur.get_parent() != root and cur.get_parent() != null:
		cur = cur.get_parent()
	if cur == root:
		return null
	return cur

# 在 rows 中查找指定 id 的根事件，返回 {row, index}（递归搜索分组内）
func _find_event_root(id: int) -> Dictionary:
	var rows = _events_data.get("rows", [])
	for i in range(rows.size()):
		var row = rows[i]
		if row.get("type") == "group":
			var found = _find_event_root_in_group(row, id)
			if not found.is_empty():
				return found
		elif int(row.get("id", -1)) == id:
			return {"row": row, "index": i}
	return {}

func _find_event_root_in_group(group: Dictionary, id: int) -> Dictionary:
	for i in range(group.get("rows", []).size()):
		var row = group["rows"][i]
		if row.get("type") == "group":
			var found = _find_event_root_in_group(row, id)
			if not found.is_empty():
				return found
		elif int(row.get("id", -1)) == id:
			return {"row": row, "index": i, "group": group}
	return {}

func _find_event_root_index(id: int) -> int:
	var rows = _events_data.get("rows", [])
	for i in range(rows.size()):
		var row = rows[i]
		if row.get("type") == "group":
			var found = _find_event_root_in_group(row, id)
			if not found.is_empty():
				return i
		elif int(row.get("id", -1)) == id:
			return i
	return -1

# 通过 block_name + params 比较事件节点
func _event_node_equals(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if a.get("block_name", "") != b.get("block_name", ""):
		return false
	var a_params = a.get("params", {})
	var b_params = b.get("params", {})
	if a_params.keys().size() != b_params.keys().size():
		return false
	for key in a_params:
		if not b_params.has(key):
			return false
		if a_params[key] != b_params[key]:
			return false
	return true

func _select_event_row(id: int):
	if not _event_tree:
		return
	var root = _event_tree.get_root()
	if root == null:
		return
	# 递归搜索：根节点下的所有子节点（包括分组内的）
	var _find_by_id = func(item: TreeItem, _fn) -> bool:
		var node = _get_node_from_item(item)
		if not node.is_empty() and int(node.get("id", -1)) == id:
			item.select(0)
			return true
		for child in item.get_children():
			if _fn.call(child, _fn):
				return true
		return false
	for item in root.get_children():
		if _find_by_id.call(item, _find_by_id):
			return

# 通过内容在树中查找并选中（支持子节点），返回是否找到
func _select_event_node_by_content(target_node: Dictionary) -> bool:
	if not _event_tree or target_node.is_empty():
		return false
	var root = _event_tree.get_root()
	if root == null:
		return false
	# 递归搜索
	var _find_and_select = func(item: TreeItem, _fn) -> bool:
		var node = _get_node_from_item(item)
		if not node.is_empty() and _event_node_equals(node, target_node):
			item.select(0)
			return true
		for child in item.get_children():
			if _fn.call(child, _fn):
				return true
		return false
	for item in root.get_children():
		if _find_and_select.call(item, _find_and_select):
			return true
	return false

# 生成唯一节点 ID
func _create_event_root(def: Dictionary) -> Dictionary:
	var id = _event_row_id_counter
	_event_row_id_counter += 1
	var params = {}
	for p in def.params:
		if p.default is Dictionary:
			params[p.name] = p.default.duplicate()
		else:
			params[p.name] = p.default
	return {"id": id, "_uid": _next_uid(), "enabled": true, "block_name": def.name, "params": params, "exprs": {}, "children": []}

func _create_event_child(def: Dictionary) -> Dictionary:
	var params = {}
	for p in def.params:
		if p.default is Dictionary:
			params[p.name] = p.default.duplicate()
		else:
			params[p.name] = p.default
	return {"block_name": def.name, "_uid": _next_uid(), "params": params, "exprs": {}, "children": []}

# 在事件表模式下：双击左侧积木块 → 添加到事件表
func _add_block_to_events(def: Dictionary):
	_save_undo_state()
	var item = _event_tree.get_selected() if _event_tree else null
	if def.type == BlockType.EVENT:
		# EVENT 块 → 新建事件行
		var row = _create_event_root(def)
		if item and _is_group_item(item):
			# 选中分组 → 加入分组
			var group_node = _get_node_from_item(item)
			group_node["rows"].append(row)
		else:
			_events_data.rows.append(row)
		_selected_event_row_id = row.id
	else:
		# 非事件块 → 根据选中项决定插入位置
		if item == null or _is_group_item(item):
			_show_message_dialog("请先选中一个事件行，再添加子块")
			return
		# ---- else_if / else_block 添加规则校验 ----
		if not _vs_validate_else_add(def, item):
			return
		var child = _create_event_child(def)
		var def_name = def.get("name", "")
		var is_else_type = (def_name == "else_if" or def_name == "else_block")
		if _is_root_event_item(item) or _is_event_in_group(item):
			# 选中根事件行（或分组内事件行）→ 追加到其 children 末尾
			var target = _get_node_from_item(item)
			if target.is_empty():
				return
			target.children.append(child)
		else:
			var sel_node = _get_node_from_item(item)
			var sel_def = _find_block_def(sel_node.get("block_name", ""))
			# ---- 选中条件块且非 else 类型 → 加到其 children（作为子块）----
			# else_if / else_block 始终作为同级插入（不作为条件块子块）
			if sel_def.type == BlockType.CONDITION and not is_else_type:
				sel_node.children.append(child)
			else:
				# 选中普通子块 / else 类型 → 插入到该块的下一行（同级，附属于同一父节点）
				var parent_item = item.get_parent()
				if parent_item == null or parent_item == _event_tree.get_root():
					return
				var parent_node = _get_node_from_item(parent_item)
				if parent_node.is_empty():
					return
				var parent_children = parent_node.get("children", [])
				# 在选中节点后插入
				var insert_idx = -1
				for i in range(parent_children.size()):
					if _event_node_equals(parent_children[i], sel_node):
						insert_idx = i + 1
						break
				if insert_idx >= 0 and insert_idx <= parent_children.size():
					parent_children.insert(insert_idx, child)
				else:
					parent_children.append(child)
	_mark_dirty()
	# 记住选中节点（渲染后树重建，需要重新选中）
	var selected_node = _get_node_from_item(item) if item != null else {}
	_render_events()
	# 恢复选中（按内容匹配，否则按根ID）
	if not selected_node.is_empty() and _select_event_node_by_content(selected_node):
		pass
	elif _selected_event_row_id >= 0:
		_select_event_row(_selected_event_row_id)

## 校验 else_if / else_block 的添加规则
## else_if 只能跟在 if_condition 后，else_block 只能跟在 if_condition 或 else_if 后
func _vs_validate_else_add(def: Dictionary, item: TreeItem) -> bool:
	var def_name = def.get("name", "")
	if def_name != "else_if" and def_name != "else_block":
		return true
	# 找到将插入位置的上一条同级块（else 类型始终作为同级插入）
	var prev_name = ""
	if _is_event_like_root(item):
		# 选中根事件行 → 新块追加到其 children 末尾，上一条 = 最后一个子块
		var root_node = _get_node_from_item(item)
		var root_children = root_node.get("children", [])
		if root_children.size() > 0:
			prev_name = root_children[root_children.size() - 1].get("block_name", "")
		else:
			prev_name = ""  # 没有子块，无法跟在如果之后
	else:
		# 选中子块 → 上一条就是选中块本身（else 作为同级插入到其后）
		var sel_node = _get_node_from_item(item)
		prev_name = sel_node.get("block_name", "")
	# 校验规则
	if def_name == "else_if":
		if prev_name != "if_condition":
			_show_message_dialog("否则如果 只能跟在 如果 之后")
			return false
	elif def_name == "else_block":
		if prev_name != "if_condition" and prev_name != "else_if":
			_show_message_dialog("否则 只能跟在 如果 或 否则如果 之后")
			return false
	return true

# 获取当前选中项对应的数据节点
func _get_selected_event_target() -> Dictionary:
	if not _event_tree:
		return {}
	var item = _event_tree.get_selected()
	if item == null:
		# 没有选中项，尝试用 _selected_event_row_id 找根事件
		if _selected_event_row_id >= 0:
			var info = _find_event_root(_selected_event_row_id)
			if not info.is_empty():
				return info.row
		return {}
	var node = _get_node_from_item(item)
	if node.is_empty():
		# metadata 查找失败，尝试用根事件 ID 兜底
		if _selected_event_row_id >= 0:
			var info = _find_event_root(_selected_event_row_id)
			if not info.is_empty():
				return info.row
	return node

func _on_event_add_row():
	# 新建一个空事件行
	var event_def = {}
	for def in _block_defs:
		if def.type == BlockType.EVENT:
			event_def = def
			break
	if event_def.is_empty():
		print("[visual_script_editor] 没有可用的 EVENT 类型块定义")
		return
	var item = _event_tree.get_selected() if _event_tree else null
	if item and _is_group_item(item):
		# 选中了分组 → 在分组内添加事件
		var group_node = _get_node_from_item(item)
		var row = _create_event_root(event_def)
		group_node["rows"].append(row)
		_selected_event_row_id = row.id
		_mark_dirty()
		_render_events()
		var selected_node = row.duplicate(true)
		if not _select_event_node_by_content(selected_node):
			_select_event_row(_selected_event_row_id)
		return
	_add_block_to_events(event_def)

func _on_event_add_group():
	_save_undo_state()
	var group = {
		"type": "group",
		"name": "新分组",
		"_uid": _next_uid(),
		"collapsed": false,
		"rows": []
	}
	# 如果选中了分组，作为子分组添加到内部
	var item = _event_tree.get_selected() if _event_tree else null
	if item and _is_group_item(item):
		var parent_group = _get_node_from_item(item)
		parent_group["rows"].append(group)
	else:
		_events_data.rows.append(group)
	_mark_dirty()
	_render_events()

func _on_event_add_comment():
	_save_undo_state()
	var comment = {
		"type": "comment",
		"text": "注释文字",
		"_uid": _next_uid(),
	}
	var item = _event_tree.get_selected() if _event_tree else null
	if item and _is_group_item(item):
		var parent_group = _get_node_from_item(item)
		parent_group["rows"].append(comment)
	else:
		_events_data.rows.append(comment)
	_mark_dirty()
	_render_events()

func _on_event_delete_row():
	if not _event_tree:
		return
	_save_undo_state()
	var item = _event_tree.get_selected()
	if item == null:
		return
	var root = _event_tree.get_root()
	var node = _get_node_from_item(item)
	if node.is_empty():
		return
	# 判断是否为分组节点
	if node.get("type") == "group":
		# 删除分组：从父容器中移除
		var parent = item.get_parent()
		if parent == root:
			for i in range(_events_data.rows.size()):
				if _events_data.rows[i].get("type") == "group" and is_same(_events_data.rows[i], node):
					_events_data.rows.remove_at(i)
					break
		else:
			# 分组在另一个分组内部
			var parent_node = _get_node_from_item(parent)
			if not parent_node.is_empty():
				var rows_arr = parent_node.get("rows", [])
				for i in range(rows_arr.size()):
					if is_same(rows_arr[i], node):
						rows_arr.remove_at(i)
						break
		_selected_event_row_id = -1
		_mark_dirty()
		_render_events()
		return
	# 注释节点：和分组类似，用 type 和 is_same 识别
	if node.get("type") == "comment":
		var parent = item.get_parent()
		var rows_arr
		if parent == root:
			rows_arr = _events_data.rows
		else:
			var parent_node = _get_node_from_item(parent)
			if not parent_node.is_empty():
				rows_arr = parent_node.get("rows", [])
		if rows_arr != null:
			for i in range(rows_arr.size()):
				if is_same(rows_arr[i], node):
					rows_arr.remove_at(i)
					break
		_selected_event_row_id = -1
		_mark_dirty()
		_render_events()
		return
	# 判断是否为根事件行（顶层事件或分组内的事件）
	if item.get_parent() == root:
		var idx = _find_event_root_index(int(node.get("id", -1)))
		if idx >= 0:
			_events_data.rows.remove_at(idx)
			_selected_event_row_id = -1
	else:
		var parent_item = item.get_parent()
		if parent_item == null:
			return
		# 如果父节点是分组，移除事件行
		var parent_node = _get_node_from_item(parent_item)
		if not parent_node.is_empty() and parent_node.get("type") == "group":
			var rows_arr = parent_node.get("rows", [])
			for i in range(rows_arr.size()):
				if int(rows_arr[i].get("id", -1)) == int(node.get("id", -1)):
					rows_arr.remove_at(i)
					break
			_selected_event_row_id = -1
			_mark_dirty()
			_render_events()
			return
		# 子节点（action blocks）：从父节点的 children 中移除
		var node_meta = _get_node_from_item(item)
		var children = parent_node.get("children", [])
		for i in range(children.size()):
			if _event_node_equals(children[i], node_meta):
				children.remove_at(i)
				break
	_mark_dirty()
	_render_events()

# ============================================
# 剪切 / 复制 / 粘贴
# ============================================

func _on_event_copy():
	if not _event_tree:
		return
	var item = _event_tree.get_selected()
	if item == null:
		return
	var node = _get_node_from_item(item)
	if node.is_empty():
		return
	_event_clipboard = {"node": node.duplicate(true), "is_root": _is_event_like_root(item)}
	_event_clipboard_cut = false

func _on_event_cut():
	if not _event_tree:
		return
	var item = _event_tree.get_selected()
	if item == null:
		return
	var node = _get_node_from_item(item)
	if node.is_empty():
		return
	_event_clipboard = {"node": node.duplicate(true), "is_root": _is_event_like_root(item)}
	_event_clipboard_cut = true
	# 删除原节点（复用删除逻辑）
	_on_event_delete_row()

func _on_event_paste():
	if not _event_tree or _event_clipboard.is_empty():
		return
	var src_node = _event_clipboard["node"]
	var was_root = _event_clipboard["is_root"]
	var pasted = src_node.duplicate(true)
	_strip_uid_recursive(pasted)
	var item = _event_tree.get_selected() if _event_tree else null
	if was_root:
		_save_undo_state()
		# 粘贴根级事件/分组
		if pasted.get("type") == "group":
			# 分组：直接添加到根 rows 或选中分组内
			if item and _is_group_item(item):
				var group_node = _get_node_from_item(item)
				group_node["rows"].append(pasted)
			else:
				_events_data.rows.append(pasted)
		else:
			var new_id = _event_row_id_counter
			_event_row_id_counter += 1
			pasted["id"] = new_id
			if item and _is_group_item(item):
				var group_node = _get_node_from_item(item)
				group_node["rows"].append(pasted)
			else:
				_events_data.rows.append(pasted)
			_selected_event_row_id = new_id
	else:
		# 粘贴子节点 → 插入到选中项之后（与 _add_block_to_events 同级插入逻辑一致）
		if item == null:
			_show_message_dialog("请先选中一个事件行，再粘贴子块")
			return
		if _is_root_event_item(item):
			# 选中根事件行 → 追加到其 children 末尾
			var target = _get_node_from_item(item)
			if target.is_empty():
				return
			_save_undo_state()
			target.children.append(pasted)
		elif _is_event_in_group(item):
			# 事件在分组内 → 插入到该事件在分组 rows 中的下一行（同级）
			var sel_node = _get_node_from_item(item)
			var parent_item = item.get_parent()
			var parent_node = _get_node_from_item(parent_item)
			if parent_node.is_empty():
				return
			_save_undo_state()
			var rows_arr = parent_node.get("rows", [])
			var insert_idx = -1
			for i in range(rows_arr.size()):
				if _event_node_equals(rows_arr[i], sel_node):
					insert_idx = i + 1
					break
			if insert_idx >= 0 and insert_idx <= rows_arr.size():
				rows_arr.insert(insert_idx, pasted)
			else:
				rows_arr.append(pasted)
		else:
			# 选中子节点 → 插入到该块的下一行（同级）
			var sel_node = _get_node_from_item(item)
			var parent_item = item.get_parent()
			if parent_item == null or parent_item == _event_tree.get_root():
				return
			var parent_node = _get_node_from_item(parent_item)
			if parent_node.is_empty():
				return
			_save_undo_state()
			var parent_children = parent_node.get("children", [])
			var insert_idx = -1
			for i in range(parent_children.size()):
				if _event_node_equals(parent_children[i], sel_node):
					insert_idx = i + 1
					break
			if insert_idx >= 0 and insert_idx <= parent_children.size():
				parent_children.insert(insert_idx, pasted)
			else:
				parent_children.append(pasted)
	_mark_dirty()
	# 恢复选中到粘贴的节点
	var selected_node = pasted.duplicate(true)
	var root_id = _selected_event_row_id
	_render_events()
	if not _select_event_node_by_content(selected_node):
		if root_id >= 0:
			_select_event_row(root_id)
	# 剪切模式：粘贴后清空剪贴板
	if _event_clipboard_cut:
		_event_clipboard = {}
		_event_clipboard_cut = false

func _on_event_toggle_enabled():
	if not _event_tree:
		return
	_save_undo_state()
	var item = _event_tree.get_selected()
	if item == null:
		_show_message_dialog("请先选中一个事件行或子块")
		return
	var node = _get_node_from_item(item)
	if node.is_empty():
		return

	var current = bool(node.get("enabled", true))
	node["enabled"] = not current
	_mark_dirty()
	# 保存节点数据用于恢复选中
	var selected_node = node.duplicate(true)
	var root_id = _selected_event_row_id
	_render_events()
	_update_event_prop_panel()
	# 恢复选中（按内容匹配，否则按根ID）
	if not _select_event_node_by_content(selected_node):
		if root_id >= 0:
			_select_event_row(root_id)

func _on_event_move_row(dir: int):
	if not _event_tree:
		return
	_save_undo_state()
	var item = _event_tree.get_selected()
	if item == null:
		return
	var root = _event_tree.get_root()
	var moved_node: Dictionary = {}
	var parent_item = item.get_parent()
	var node = _get_node_from_item(item)
	if node.is_empty():
		return
	if parent_item != root:
		var parent_node = _get_node_from_item(parent_item)
		if parent_node.is_empty():
			return
		# 判断父节点类型：分组 → 在 rows 中移动；否则 → 在 children 中移动
		if parent_node.get("type") == "group":
			# 在分组内部移动事件行
			var rows_arr = parent_node.get("rows", [])
			moved_node = node
			var cur_idx = -1
			for i in range(rows_arr.size()):
				if is_same(rows_arr[i], moved_node):
					cur_idx = i
					break
			if cur_idx < 0:
				return
			var new_idx = cur_idx + dir
			if new_idx < 0 or new_idx >= rows_arr.size():
				return
			var tmp = rows_arr[cur_idx]
			rows_arr[cur_idx] = rows_arr[new_idx]
			rows_arr[new_idx] = tmp
			if node.get("type") != "group":
				_selected_event_row_id = int(node.get("id", -1))
		else:
			# 子节点移动：在父的 children 中移动
			var children = parent_node.get("children", [])
			moved_node = node
			var cur_idx = -1
			for i in range(children.size()):
				if is_same(children[i], moved_node):
					cur_idx = i
					break
			if cur_idx < 0:
				return
			var new_idx = cur_idx + dir
			if new_idx < 0 or new_idx >= children.size():
				return
			var tmp = children[cur_idx]
			children[cur_idx] = children[new_idx]
			children[new_idx] = tmp
	else:
		# 根级别元素移动（事件行、分组或注释）
		if node.get("type") == "group":
			# 分组移动
			var idx = -1
			for i in range(_events_data.rows.size()):
				if _events_data.rows[i].get("type") == "group" and is_same(_events_data.rows[i], node):
					idx = i
					break
			if idx < 0:
				return
			var new_idx = idx + dir
			if new_idx < 0 or new_idx >= _events_data.rows.size():
				return
			var tmp = _events_data.rows[idx]
			_events_data.rows[idx] = _events_data.rows[new_idx]
			_events_data.rows[new_idx] = tmp
		elif node.get("type") == "comment":
			# 注释移动
			var idx = -1
			for i in range(_events_data.rows.size()):
				if is_same(_events_data.rows[i], node):
					idx = i
					break
			if idx < 0:
				return
			var new_idx = idx + dir
			if new_idx < 0 or new_idx >= _events_data.rows.size():
				return
			var tmp = _events_data.rows[idx]
			_events_data.rows[idx] = _events_data.rows[new_idx]
			_events_data.rows[new_idx] = tmp
		else:
			# 事件行移动
			var id = int(node.get("id", -1))
			var idx = _find_event_root_index(id)
			if idx < 0:
				return
			var new_idx = idx + dir
			if new_idx < 0 or new_idx >= _events_data.rows.size():
				return
			var tmp = _events_data.rows[idx]
			_events_data.rows[idx] = _events_data.rows[new_idx]
			_events_data.rows[new_idx] = tmp
			_selected_event_row_id = id
	_mark_dirty()
	var root_id = _selected_event_row_id
	_render_events()
	# 恢复选中（按内容匹配，否则按根ID）
	if not moved_node.is_empty() and _select_event_node_by_content(moved_node):
		pass
	elif root_id >= 0:
		_select_event_row(root_id)

# ============================================
# 移动到块下 / 替换块
# ============================================

## 查找 node 在事件表数据中的位置，返回 {parent_children, index, parent_node}
## 搜索范围：根 rows、分组 rows、事件 children
func _vs_find_node_location(target_node: Dictionary) -> Dictionary:
	# 搜索根 rows
	for i in range(_events_data.rows.size()):
		if is_same(_events_data.rows[i], target_node):
			return {"parent_children": _events_data.rows, "index": i, "parent_node": null}
		# 搜索事件内的 children
		var result = _vs_find_node_in_children(_events_data.rows[i].get("children", []), target_node)
		if not result.is_empty():
			return result
		# 搜索分组内的 rows
		if _events_data.rows[i].get("type") == "group":
			result = _vs_find_node_in_group_rows(_events_data.rows[i], target_node)
			if not result.is_empty():
				return result
	return {}

## 递归搜索分组内的 rows（包括嵌套分组）
func _vs_find_node_in_group_rows(group: Dictionary, target_node: Dictionary) -> Dictionary:
	var rows_arr = group.get("rows", [])
	for i in range(rows_arr.size()):
		if is_same(rows_arr[i], target_node):
			return {"parent_children": rows_arr, "index": i, "parent_node": group}
		# 搜索事件内的 children
		var result = _vs_find_node_in_children(rows_arr[i].get("children", []), target_node)
		if not result.is_empty():
			return result
		# 搜索嵌套分组
		if rows_arr[i].get("type") == "group":
			result = _vs_find_node_in_group_rows(rows_arr[i], target_node)
			if not result.is_empty():
				return result
	return {}

func _vs_find_node_in_children(children: Array, target_node: Dictionary) -> Dictionary:
	for i in range(children.size()):
		if is_same(children[i], target_node):
			return {"parent_children": children, "index": i, "parent_node": null}
		var sub = _vs_find_node_in_children(children[i].get("children", []), target_node)
		if not sub.is_empty():
			# 补上 parent_node（直接父节点）
			if sub.get("parent_node", null) == null:
				sub["parent_node"] = children[i]
			return sub
	return {}

## 检查 candidate 是否是 ancestor 的后代
func _vs_is_descendant_of(ancestor: Dictionary, candidate: Dictionary) -> bool:
	# 搜索 children 数组（事件子块）
	for child in ancestor.get("children", []):
		if is_same(child, candidate):
			return true
		if _vs_is_descendant_of(child, candidate):
			return true
	# 搜索 rows 数组（分组内事件）
	for child in ancestor.get("rows", []):
		if is_same(child, candidate):
			return true
		if _vs_is_descendant_of(child, candidate):
			return true
	return false

## 移动到块下：打开对话框选择目标块，将选中块移到目标块的 children 末尾
func _on_event_move_under():
	if not _event_tree:
		return
	var item = _event_tree.get_selected()
	if item == null:
		_show_message_dialog("请先选中要移动的块")
		return
	var src_node = _get_node_from_item(item)
	if src_node.is_empty():
		_show_message_dialog("无法获取选中块的数据")
		return
	if _is_root_event_item(item) or src_node.get("type") == "comment":
		_show_message_dialog("事件行不能移动到其他块下")
		return
	_show_move_under_dialog(src_node)

func _show_move_under_dialog(src_node: Dictionary):
	var dialog = AcceptDialog.new()
	dialog.title = "移动到块下"
	dialog.min_size = Vector2(500, 420)
	dialog.dialog_text = "双击目标块即可移动"
	add_child(dialog)
	# 隐藏默认的确定按钮，改用双击操作
	dialog.get_ok_button().visible = false

	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(vbox)

	var hint = Label.new()
	hint.text = ""
	vbox.add_child(hint)

	var tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	vbox.add_child(tree)
	tree.create_item()  # root

	# 递归构建目标树（排除源节点自身及其后代，用 metadata 存节点引用）
	var _add_to_tree = func(parent_item: TreeItem, node: Dictionary, _fn):
		if is_same(node, src_node):
			return  # 跳过源节点
		if _vs_is_descendant_of(src_node, node):
			return  # 跳过源节点的后代
		# 分组节点不直接作为目标，展开其内部事件
		if node.get("type") == "group":
			for sub_row in node.get("rows", []):
				_fn.call(parent_item, sub_row, _fn)
			return
		var t_item = tree.create_item(parent_item)
		var label = _format_event_node_text(node)
		t_item.set_text(0, label)
		t_item.set_metadata(0, node)
		var line_count = label.count("\n") + 1
		if line_count > 1:
			t_item.set_custom_minimum_height(line_count * 22)
		for child in node.get("children", []):
			_fn.call(t_item, child, _fn)

	for row in _events_data.get("rows", []):
		_add_to_tree.call(tree.get_root(), row, _add_to_tree)

	# 双击目标块直接执行移动
	tree.item_activated.connect(func():
		var item = tree.get_selected()
		if item == null:
			return
		var target = item.get_metadata(0)
		if typeof(target) != TYPE_DICTIONARY:
			return
		dialog.queue_free()
		_save_undo_state()
		# 从原位置移除
		var loc = _vs_find_node_location(src_node)
		if loc.is_empty():
			_show_message_dialog("无法在原位置找到该块，操作失败")
			return
		loc.parent_children.remove_at(loc.index)
		# 添加到目标块的 children
		target.children.append(src_node)
		_mark_dirty()
		var root_id = _selected_event_row_id
		_render_events()
		if not _select_event_node_by_content(src_node):
			if root_id >= 0:
				_select_event_row(root_id)
	)
	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()

## 替换当前选中的块（保留子块）
func _on_event_replace_block():
	if not _event_tree:
		return
	var item = _event_tree.get_selected()
	if item == null:
		_show_message_dialog("请先选中要替换的块")
		return
	var src_node = _get_node_from_item(item)
	if src_node.is_empty():
		return
	if src_node.get("type") == "group":
		_show_message_dialog("分组不能替换")
		return
	_show_replace_block_dialog(src_node, _is_root_event_item(item) or _is_event_in_group(item))

func _show_replace_block_dialog(src_node: Dictionary, is_root: bool):
	var dialog = AcceptDialog.new()
	dialog.title = "替换块"
	dialog.min_size = Vector2(720, 460)
	dialog.dialog_text = ""
	add_child(dialog)

	var main_hbox = HBoxContainer.new()
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 8)
	dialog.add_child(main_hbox)

	# 左侧：分类
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(160, 0)
	main_hbox.add_child(left_vbox)
	var cat_title = Label.new()
	cat_title.text = "分类"
	cat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cat_title.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(cat_title)
	var cat_list = ItemList.new()
	cat_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cat_list.select_mode = ItemList.SELECT_SINGLE
	left_vbox.add_child(cat_list)

	# 右侧：块列表
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(right_vbox)
	var blk_title = Label.new()
	blk_title.text = "块（双击替换）"
	blk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blk_title.add_theme_font_size_override("font_size", 14)
	right_vbox.add_child(blk_title)
	var block_list = ItemList.new()
	block_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	block_list.select_mode = ItemList.SELECT_SINGLE
	right_vbox.add_child(block_list)

	# 按是否替换根事件过滤可用块
	var available_defs_by_cat: Dictionary = {}
	for def in _block_defs:
		# 事件表模式下隐藏 VALUE 块
		if def.type == BlockType.VALUE:
			continue
		if def.get("event_only", false) == false and def.get("hide_in_event", false):
			continue
		# 根事件只能替换为 EVENT 块；子块只能替换为非 EVENT 块
		if is_root:
			if def.type != BlockType.EVENT:
				continue
		else:
			if def.type == BlockType.EVENT:
				continue
		var cat = def.get("category", "未分类")
		if not available_defs_by_cat.has(cat):
			available_defs_by_cat[cat] = []
		available_defs_by_cat[cat].append(def)

	var cats = available_defs_by_cat.keys()
	for cat in cats:
		cat_list.add_item(cat)
	var current_defs: Array = []

	var _select_cat = func(idx: int):
		if idx < 0 or idx >= cats.size():
			return
		var cat = cats[idx]
		block_list.clear()
		current_defs.clear()
		for def in available_defs_by_cat[cat]:
			var type_name = BlockType.keys()[def.type]
			block_list.add_item("[%s] %s" % [type_name, def.get("label", def.name)])
			current_defs.append(def)
	cat_list.item_selected.connect(_select_cat)

	# 双击 → 替换
	block_list.item_activated.connect(func(idx: int):
		if idx < 0 or idx >= current_defs.size():
			return
		var new_def = current_defs[idx]
		_vs_perform_replace(src_node, new_def, is_root)
		dialog.queue_free()
	)

	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()
	if cat_list.item_count > 0:
		cat_list.select(0)
		_select_cat.call(0)

## 执行替换：用 new_def 创建新节点，保留原 children，替换原位置
func _vs_perform_replace(src_node: Dictionary, new_def: Dictionary, is_root: bool):
	_save_undo_state()
	var old_children = src_node.get("children", [])
	var old_enabled = src_node.get("enabled", true)
	var new_node: Dictionary
	if is_root:
		new_node = _create_event_root(new_def)
		new_node.children = old_children
		new_node.enabled = old_enabled
		# 用 _vs_find_node_location 查找并替换（支持根 rows 和分组 rows）
		var loc = _vs_find_node_location(src_node)
		if not loc.is_empty():
			loc.parent_children[loc.index] = new_node
			_selected_event_row_id = new_node.id
	else:
		new_node = _create_event_child(new_def)
		new_node.children = old_children
		new_node.enabled = old_enabled
		# 在父的 children 中替换
		var loc = _vs_find_node_location(src_node)
		if not loc.is_empty():
			loc.parent_children[loc.index] = new_node
	_mark_dirty()
	# 保存节点数据用于恢复选中
	var selected_node = new_node.duplicate(true)
	var root_id = new_node.get("id", _selected_event_row_id) if is_root else _selected_event_row_id
	_render_events()
	# 恢复选中（按内容匹配，否则按根ID）
	if not _select_event_node_by_content(selected_node):
		if root_id >= 0:
			_select_event_row(root_id)

func _on_event_tree_gui_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_on_event_delete_row()
		elif event.keycode == KEY_X and event.ctrl_pressed:
			_on_event_cut()
		elif event.keycode == KEY_C and event.ctrl_pressed:
			_on_event_copy()
		elif event.keycode == KEY_V and event.ctrl_pressed:
			_on_event_paste()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _drag_in_progress:
				var item = _event_tree.get_item_at_position(event.position)
				if item:
					if _prevent_drag_after_dialog:
						_prevent_drag_after_dialog = false
						_drag_source_item = null
					else:
						_drag_source_item = item
						_drag_start_pos = event.position
		else:
			# 鼠标释放：执行 drop
			if _drag_in_progress:
				_finish_event_drag(event.position)
			_drag_source_item = null
	elif event is InputEventMouseMotion and _drag_source_item and not _drag_in_progress:
		# 对话框关闭后禁止触发拖拽
		if _prevent_drag_after_dialog:
			_prevent_drag_after_dialog = false
			_drag_source_item = null
		elif _drag_start_pos.distance_to(event.position) > 10:
			_start_event_drag(event.position)
	elif event is InputEventMouseMotion and _drag_in_progress:
		# 拖拽中：更新指示线和预览标签位置
		_update_event_drag_indicator(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# 右键：选中鼠标下方的项并弹出菜单
		var pos = event.position
		var item = _event_tree.get_item_at_position(pos)
		if item != null:
			item.select(0)
			_on_event_tree_rmb(pos)

func _on_event_tree_selected():
	if not _event_tree:
		return
	var item = _event_tree.get_selected()
	if item == null:
		_selected_event_row_id = -1
		return
	var node = _get_node_from_item(item)
	if node.get("type") == "group":
		_selected_event_row_id = -1
	elif _is_event_in_group(item):
		# 事件在分组内：记录事件本身的 ID
		_selected_event_row_id = int(node.get("id", -1))
	else:
		# 记录所属根事件 ID
		var root_item = _get_root_item_of(item)
		if root_item != null:
			var root_node = _get_node_from_item(root_item)
			_selected_event_row_id = int(root_node.get("id", -1))
	_update_event_prop_panel()

func _on_event_tree_rmb(pos: Vector2):
	if not _event_context_menu:
		return
	_event_context_menu.clear()
	var item = _event_tree.get_selected() if _event_tree else null
	_event_context_menu.add_item("剪切", 0)
	_event_context_menu.add_item("复制", 1)
	# 粘贴
	_event_context_menu.add_item("粘贴", 2)
	_event_context_menu.set_item_disabled(2, _event_clipboard.is_empty())
	var screen_pos = _event_tree.get_screen_position() + pos
	_event_context_menu.position = screen_pos
	_event_context_menu.popup()

# ---- 事件表拖拽（自定义实现，不用原生 DnD） ----
func _start_event_drag(pos: Vector2):
	var node = _get_node_from_item(_drag_source_item)
	if node.is_empty():
		_drag_source_item = null
		return
	_drag_in_progress = true
	_drag_source_node = node
	# 保存原始颜色（无条件保存，含默认白色）
	if _drag_source_item and is_instance_valid(_drag_source_item):
		_drag_source_item.set_custom_bg_color(0, Color(0.3, 0.5, 1.0, 0.3))
	# 预览标签
	if node.get("type") == "comment":
		_drag_preview.text = "// " + node.get("text", "注释")
	else:
		_drag_preview.text = node.get("block_name", "?")
	_drag_preview.visible = true
	_update_event_drag_indicator(pos)

func _update_event_drag_indicator(pos: Vector2):
	if not _event_tree:
		return
	_drag_preview.position = Vector2(pos.x + 10, pos.y - 10)

	var item = _event_tree.get_item_at_position(pos)
	if item and item != _drag_source_item:
		var node = _get_node_from_item(item)
		if not node.is_empty() and not _vs_is_descendant_of(_drag_source_node, node):
			# 切换目标时清除旧目标的颜色
			if _drag_target_item and is_instance_valid(_drag_target_item) and _drag_target_item != item:
				_drag_target_item.clear_custom_bg_color(0)

			_drag_target_item = item

			# 探测 ±10px 判断是「悬停在块上」还是「缝隙」
			var above = _event_tree.get_item_at_position(Vector2(pos.x, pos.y - DRAG_EDGE_THRESHOLD))
			var below = _event_tree.get_item_at_position(Vector2(pos.x, pos.y + DRAG_EDGE_THRESHOLD))
			var on_block = (above == item or above == null) and (below == item or below == null)

			# 目标有子块时：向下探测到子块也视为悬停（附加到子块末尾）
			if not on_block and item:
				var child_items = item.get_children()
				if child_items.size() > 0 and below in child_items:
					on_block = (above == item or above == null)

			# 分组节点允许附加（将拖拽项加入分组）
			var is_group = node.get("type") == "group"

			# 不允许附加到 ACTION 块
			if on_block and not is_group:
				var def = _find_block_def(node.get("block_name", ""))
				if not def.is_empty() and def.type == BlockType.ACTION:
					on_block = false

			if on_block:
				_drag_attach_hover = true
				_drag_hover_y = -1.0
				item.set_custom_bg_color(0, Color(1, 1, 0, 0.3))
			else:
				_drag_attach_hover = false
				_drag_hover_y = pos.y + 2
				item.clear_custom_bg_color(0)
			_event_tree.queue_redraw()
			return

	# 无效目标，隐藏指示线/颜色
	_clear_target_bg_color()
	_drag_target_item = null
	_drag_hover_y = -1.0
	_drag_attach_hover = false
	_event_tree.queue_redraw()

func _finish_event_drag(pos: Vector2):
	_drag_preview.visible = false
	var target_item = _event_tree.get_item_at_position(pos) if _event_tree else null
	if not target_item or _drag_source_node.is_empty():
		_cleanup_drag()
		return
	if target_item == _drag_source_item:
		_cleanup_drag()
		return
	var target_node = _get_node_from_item(target_item)
	if target_node.is_empty() or _vs_is_descendant_of(_drag_source_node, target_node):
		_cleanup_drag()
		return
	_save_undo_state()
	var src_loc = _vs_find_node_location(_drag_source_node)
	if src_loc.is_empty():
		_cleanup_drag()
		return
	var src_children: Array = src_loc["parent_children"]
	var src_idx: int = src_loc["index"]
	src_children.remove_at(src_idx)

	# 分组节点允许附加子元素
	var can_attach = _drag_attach_hover
	if can_attach:
		var is_group = target_node.get("type") == "group"
		if not is_group:
			var def = _find_block_def(target_node.get("block_name", ""))
			if not def.is_empty() and def.type == BlockType.ACTION:
				can_attach = false

	if can_attach:
		if target_node.get("type") == "group":
			# 附加到分组：添加到分组的 rows 数组
			var tgt_rows: Array = target_node.get("rows", [])
			tgt_rows.append(_drag_source_node)
		else:
			# 附加为子节点
			var tgt_children: Array = target_node.get("children", [])
			tgt_children.append(_drag_source_node)
	else:
		# 插入到目标块之后（同级）
		var tgt_loc = _vs_find_node_location(target_node)
		if tgt_loc.is_empty():
			_cleanup_drag()
			return
		var tgt_children: Array = tgt_loc["parent_children"]
		var tgt_idx: int = tgt_loc["index"]
		var insert_idx = tgt_idx + 1
		if src_children == tgt_children:
			if src_idx < tgt_idx:
				insert_idx -= 1
			elif src_idx == tgt_idx:
				_cleanup_drag()
				return
		tgt_children.insert(insert_idx, _drag_source_node)

	# 保存引用，在 _render_events() 后用于选择新节点
	var src_node = _drag_source_node
	# 先恢复颜色再重建树，避免 TreeItem 失效后颜色丢失
	_cleanup_drag()

	_mark_dirty()
	_render_events()
	if not _select_event_node_by_content(src_node):
		_select_event_row(_selected_event_row_id)

func _on_event_tree_mouse_exited():
	if _drag_in_progress:
		_drag_hover_y = -1.0
		_drag_attach_hover = false
		_clear_target_bg_color()
		_drag_target_item = null
		_event_tree.queue_redraw()

func _on_event_tree_draw():
	if _drag_hover_y > 0 and not _drag_attach_hover:
		_event_tree.draw_line(
			Vector2(2, _drag_hover_y),
			Vector2(_event_tree.size.x - 2, _drag_hover_y),
			Color(1, 1, 1, 0.9),
			2
		)

# ---- 事件表搜索 ----

func _on_event_search_text_changed(new_text: String):
	_event_search_text = new_text.strip_edges()
	_event_apply_search()

func _event_apply_search():
	# 先恢复展开，再清除上一次搜索的绿色（仅之前标记过的项）
	_restore_search_expanded()
	_event_search_expanded.clear()
	var old_matches = _event_search_matches.duplicate()
	_event_search_matches.clear()
	_clear_search_colors(old_matches)
	_event_search_current_index = -1
	_event_search_prev_btn.disabled = true
	_event_search_next_btn.disabled = true
	_event_search_label.text = ""
	if not _event_tree or _event_search_text == "":
		return
	# 递归收集所有 TreeItem，匹配文本
	var root = _event_tree.get_root()
	if root:
		_event_search_collect_items(root)
	# 更新 UI
	var total = _event_search_matches.size()
	if total > 0:
		_event_search_prev_btn.disabled = false
		_event_search_next_btn.disabled = false
		_jump_to_search_match(0)
	else:
		_event_search_label.text = "0/%d" % total

func _event_search_collect_items(parent_item: TreeItem):
	var item = parent_item.get_first_child()
	while item:
		var txt = item.get_text(0)
		if txt.findn(_event_search_text) >= 0:
			# 保存原始颜色，设绿色
			var orig = item.get_custom_color(0)
			_event_search_matches.append({"item": item, "orig_color": orig})
			item.set_custom_color(0, Color(0.2, 1.0, 0.2))  # 绿色
		# 递归子节点
		if item.get_first_child():
			_event_search_collect_items(item)
		item = item.get_next()

## 还原之前搜索标记过的项的原始颜色
func _clear_search_colors(old_matches: Array):
	for entry in old_matches:
		var item = entry.get("item")
		if item is TreeItem and is_instance_valid(item):
			item.clear_custom_bg_color(0)
			var orig = entry.get("orig_color", Color())
			# get_custom_color 未设色时返回 Color(0,0,0,0)
			if orig == Color() or orig.a < 0.001:
				item.clear_custom_color(0)
			else:
				item.set_custom_color(0, orig)

func _jump_to_search_match(idx: int):
	var total = _event_search_matches.size()
	if total == 0:
		return
	idx = idx % total
	if idx < 0:
		idx += total
	# 清除之前的背景高亮
	if _event_search_current_index >= 0 and _event_search_current_index < total:
		var prev_entry = _event_search_matches[_event_search_current_index]
		var prev = prev_entry.get("item")
		if is_instance_valid(prev):
			prev.clear_custom_bg_color(0)
	# 恢复上一次展开的祖先折叠状态
	_restore_search_expanded()
	_event_search_current_index = idx
	var entry = _event_search_matches[idx]
	var item = entry.get("item")
	if not is_instance_valid(item):
		return
	# 展开祖先折叠，让目标可见
	_expand_ancestors_for_search(item)
	# 高亮当前匹配项
	item.set_custom_bg_color(0, Color(0.3, 0.8, 0.3, 0.4))
	# 选中并滚动到可见
	item.select(0)
	_event_tree.scroll_to_item(item)
	# 更新标签
	_event_search_label.text = "%d/%d" % [idx + 1, total]

## 展开 item 的所有折叠祖先，记录展开过的项
func _expand_ancestors_for_search(item: TreeItem):
	_event_search_expanded.clear()
	var p = item.get_parent()
	while p and p != _event_tree.get_root():
		if p.collapsed:
			_event_search_expanded.append({"item": p, "was_collapsed": true})
			p.collapsed = false
		p = p.get_parent()

## 恢复之前展开过的祖先的折叠状态
func _restore_search_expanded():
	for entry in _event_search_expanded:
		var it = entry.item
		if is_instance_valid(it) and entry.was_collapsed:
			it.collapsed = true
	_event_search_expanded.clear()

func _event_search_prev():
	_jump_to_search_match(_event_search_current_index - 1)

func _event_search_next():
	_jump_to_search_match(_event_search_current_index + 1)

func _clear_target_bg_color():
	if _drag_target_item and is_instance_valid(_drag_target_item):
		_drag_target_item.clear_custom_bg_color(0)

func _cleanup_drag():
	if _drag_source_item and is_instance_valid(_drag_source_item):
		_drag_source_item.clear_custom_bg_color(0)
	if _drag_preview:
		_drag_preview.visible = false
	_clear_target_bg_color()
	_drag_source_item = null
	_drag_source_node = {}
	_drag_target_item = null
	_drag_start_pos = Vector2.ZERO
	_drag_hover_y = -1.0
	_drag_attach_hover = false
	_drag_in_progress = false
	_event_tree.queue_redraw()

func _on_event_tree_item_collapsed(item: TreeItem):
	var node = _get_node_from_item(item)
	if not node.is_empty():
		var old_val = node.get("collapsed", false)
		node["collapsed"] = item.collapsed
		if old_val != item.collapsed:
			_mark_dirty()

func _on_event_context_menu_pressed(id: int):
	match id:
		0: _on_event_cut()
		1: _on_event_copy()
		2: _on_event_paste()

# 事件表模式下的属性面板：显示选中节点信息
func _update_event_prop_panel():
	if not _prop_panel:
		return
	for child in _prop_panel.get_children():
		child.queue_free()
	var title = Label.new()
	title.text = "事件表 - 属性"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	_prop_panel.add_child(title)
	_prop_panel.add_child(HSeparator.new())
	var item = null
	if _event_tree:
		item = _event_tree.get_selected()
	if item == null:
		var hint = Label.new()
		hint.text = "选中事件表中的行\n以查看其属性"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 13)
		_prop_panel.add_child(hint)
		return
	var node = _get_node_from_item(item)
	if node.is_empty():
		return
	# 分组节点的属性面板
	if node.get("type") == "group":
		var group_title = Label.new()
		group_title.text = "分组编辑"
		group_title.add_theme_font_size_override("font_size", 14)
		_prop_panel.add_child(group_title)
		_prop_panel.add_child(HSeparator.new())

		# 名称
		var name_hbox = HBoxContainer.new()
		var name_lbl = Label.new()
		name_lbl.text = "名称:"
		name_lbl.custom_minimum_size.x = 50
		name_hbox.add_child(name_lbl)
		var name_le = LineEdit.new()
		name_le.text = node.get("name", "新分组")
		name_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_le.text_changed.connect(func(new_text):
			_save_undo_state()
			node["name"] = new_text
			_mark_dirty()
			_render_events()
			name_le.text = new_text  # 保留焦点
		)
		name_hbox.add_child(name_le)
		_prop_panel.add_child(name_hbox)

		# 颜色
		var color_hbox = HBoxContainer.new()
		var color_lbl = Label.new()
		color_lbl.text = "颜色:"
		color_lbl.custom_minimum_size.x = 50
		color_hbox.add_child(color_lbl)
		var cp = ColorPickerButton.new()
		cp.color = node.get("color", Color(0.9, 0.85, 0.6))
		cp.edit_alpha = true
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp.color_changed.connect(func(new_color):
			_save_undo_state()
			node["color"] = new_color
			_mark_dirty()
			_render_events()
		)
		color_hbox.add_child(cp)
		var reset_color_btn = Button.new()
		reset_color_btn.text = "默认"
		reset_color_btn.pressed.connect(func():
			_save_undo_state()
			node.erase("color")
			_mark_dirty()
			_render_events()
		)
		color_hbox.add_child(reset_color_btn)
		_prop_panel.add_child(color_hbox)
		return
	if node.get("type") == "comment":
		var comment_title = Label.new()
		comment_title.text = "注释"
		comment_title.add_theme_font_size_override("font_size", 14)
		_prop_panel.add_child(comment_title)
		_prop_panel.add_child(HSeparator.new())
		var text_edit = TextEdit.new()
		text_edit.text = node.get("text", "")
		text_edit.custom_minimum_size.y = 100
		text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_edit.text_changed.connect(func():
			_save_undo_state()
			node["text"] = text_edit.text
			_mark_dirty()
			var sel = _event_tree.get_selected() if _event_tree else null
			if sel:
				_refresh_event_item_text(sel)
		)
		_prop_panel.add_child(text_edit)
		return
	var def = _find_block_def(node.get("block_name", ""))
	var name_label = Label.new()
	name_label.text = "块: " + node.get("block_name", "?")
	name_label.add_theme_font_size_override("font_size", 13)
	_prop_panel.add_child(name_label)
	if not def.is_empty():
		var type_label = Label.new()
		type_label.text = "类型: " + BlockType.keys()[def.type]
		type_label.add_theme_color_override("font_color", _category_colors.get(def.get("category", ""), Color.GRAY))
		type_label.add_theme_font_size_override("font_size", 12)
		_prop_panel.add_child(type_label)
	# 所有块都显示启用状态（复选框在 gui_input 中精确处理）
	var en_label = Label.new()
	en_label.text = "启用: " + str(bool(node.get("enabled", true)))
	en_label.add_theme_font_size_override("font_size", 12)
	_prop_panel.add_child(en_label)
	_prop_panel.add_child(HSeparator.new())
	# 用和积木模式相同的分类型控件编辑参数
	var exprs = node.get("exprs", {})
	for p in def.get("params", []):
		var hbox = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = p.get("label", p.name) + ": "
		lbl.add_theme_font_size_override("font_size", 12)
		hbox.add_child(lbl)
		# 参数值编辑控件（字面值）
		_add_event_param_widget(hbox, node, p, false)
		# 表达式按钮：为参数设置表达式（运算/函数）
		var expr_btn = Button.new()
		expr_btn.text = "Expr"
		expr_btn.tooltip_text = "为参数设置表达式（运算/函数）"
		expr_btn.custom_minimum_size = Vector2(40, 24)
		var captured_p = p
		expr_btn.pressed.connect(func():
			_show_expr_editor_dialog(node, captured_p)
		)
		hbox.add_child(expr_btn)
		# 显示当前表达式（如果有）
		if exprs.has(p.name):
			var expr_label = Label.new()
			expr_label.text = " [表达式: %s]" % exprs[p.name]
			expr_label.add_theme_color_override("font_color", Color.YELLOW)
			expr_label.add_theme_font_size_override("font_size", 11)
			hbox.add_child(expr_label)
		_prop_panel.add_child(hbox)

# 事件表参数控件工厂（和积木模式 _add_param_editor 保持一致的控件类型）
func _add_event_param_widget(container: HBoxContainer, node: Dictionary, p: Dictionary, is_dialog: bool):
	var pname = p.name
	var current_val = node.params.get(pname, p.default)
	if p.type == "number":
		var spin = SpinBox.new()
		spin.min_value = -INT_MAX
		spin.max_value = INT_MAX
		spin.step = 0.001
		spin.value = float(current_val) if current_val != null else 0.0
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(func(v: float):
			node.params[pname] = v
			_mark_dirty()
			_refresh_current_event_item()
		)
		container.add_child(spin)
	elif p.type == "bool":
		var cb = CheckBox.new()
		cb.text = "已启用" if is_dialog else ""
		cb.button_pressed = bool(current_val)
		cb.toggled.connect(func(pressed: bool):
			_save_undo_state()
			node.params[pname] = pressed
			_mark_dirty()
			_refresh_current_event_item()
		)
		container.add_child(cb)
	elif p.type == "dropdown":
		var opt = OptionButton.new()
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var options = p.get("options", [])
		for i in range(options.size()):
			opt.add_item(str(options[i]))
			if str(options[i]) == str(current_val):
				opt.select(i)
		opt.item_selected.connect(func(idx: int):
			_save_undo_state()
			node.params[pname] = str(options[idx])
			_mark_dirty()
			_refresh_current_event_item()
		)
		container.add_child(opt)
	elif p.type == "node":
		var le = LineEdit.new()
		le.text = str(current_val)
		le.placeholder_text = "节点路径"
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_changed.connect(func(t: String):
			node.params[pname] = t
			_mark_dirty()
			_refresh_current_event_item()
		)
		container.add_child(le)
	elif p.type == "string":
		var le = LineEdit.new()
		le.text = str(current_val)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_changed.connect(func(t: String):
			node.params[pname] = t
			_mark_dirty()
			_refresh_current_event_item()
		)
		container.add_child(le)
	elif p.type == "vector2":
		var default_vec = p.default if p.default is Dictionary else {"x": 0.0, "y": 0.0}
		var vec = current_val if current_val is Dictionary else default_vec
		var xl = Label.new(); xl.text = "X:"; container.add_child(xl)
		var xs = SpinBox.new(); xs.min_value = -INT_MAX; xs.max_value = INT_MAX; xs.step = 0.001
		xs.value = float(vec.get("x", 0.0)); xs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xs.value_changed.connect(func(v: float):
			var cur = node.params.get(pname, {"x": 0.0, "y": 0.0})
			if not cur is Dictionary: cur = {"x": 0.0, "y": 0.0}
			cur.x = v; node.params[pname] = cur
			_mark_dirty(); _refresh_current_event_item()
		)
		container.add_child(xs)
		var yl = Label.new(); yl.text = "Y:"; container.add_child(yl)
		var ys = SpinBox.new(); ys.min_value = -INT_MAX; ys.max_value = INT_MAX; ys.step = 0.001
		ys.value = float(vec.get("y", 0.0)); ys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ys.value_changed.connect(func(v: float):
			var cur = node.params.get(pname, {"x": 0.0, "y": 0.0})
			if not cur is Dictionary: cur = {"x": 0.0, "y": 0.0}
			cur.y = v; node.params[pname] = cur
			_mark_dirty(); _refresh_current_event_item()
		)
		container.add_child(ys)
	elif p.type == "vector3":
		var default_vec = p.default if p.default is Dictionary else {"x": 0.0, "y": 0.0, "z": 0.0}
		var vec = current_val if current_val is Dictionary else default_vec
		var xl = Label.new(); xl.text = "X:"; container.add_child(xl)
		var xs = SpinBox.new(); xs.min_value = -INT_MAX; xs.max_value = INT_MAX; xs.step = 0.001
		xs.value = float(vec.get("x", 0.0)); xs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xs.value_changed.connect(func(v: float):
			var cur = node.params.get(pname, {"x": 0.0, "y": 0.0, "z": 0.0})
			if not cur is Dictionary: cur = {"x": 0.0, "y": 0.0, "z": 0.0}
			cur.x = v; node.params[pname] = cur
			_mark_dirty(); _refresh_current_event_item()
		)
		container.add_child(xs)
		var yl = Label.new(); yl.text = "Y:"; container.add_child(yl)
		var ys = SpinBox.new(); ys.min_value = -INT_MAX; ys.max_value = INT_MAX; ys.step = 0.001
		ys.value = float(vec.get("y", 0.0)); ys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ys.value_changed.connect(func(v: float):
			var cur = node.params.get(pname, {"x": 0.0, "y": 0.0, "z": 0.0})
			if not cur is Dictionary: cur = {"x": 0.0, "y": 0.0, "z": 0.0}
			cur.y = v; node.params[pname] = cur
			_mark_dirty(); _refresh_current_event_item()
		)
		container.add_child(ys)
		var zl = Label.new(); zl.text = "Z:"; container.add_child(zl)
		var zs = SpinBox.new(); zs.min_value = -INT_MAX; zs.max_value = INT_MAX; zs.step = 0.001
		zs.value = float(vec.get("z", 0.0)); zs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zs.value_changed.connect(func(v: float):
			var cur = node.params.get(pname, {"x": 0.0, "y": 0.0, "z": 0.0})
			if not cur is Dictionary: cur = {"x": 0.0, "y": 0.0, "z": 0.0}
			cur.z = v; node.params[pname] = cur
			_mark_dirty(); _refresh_current_event_item()
		)
		container.add_child(zs)
	elif p.type == "color":
		var default_color = {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}
		var cur_dict = current_val if current_val is Dictionary else default_color
		var cp = ColorPickerButton.new()
		cp.color = Color(cur_dict.get("r", 1.0), cur_dict.get("g", 1.0), cur_dict.get("b", 1.0), cur_dict.get("a", 1.0))
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp.custom_minimum_size = Vector2(60, 0)
		cp.get_popup().exclusive = true
		cp.color_changed.connect(func(c: Color):
			_save_undo_state()
			node.params[pname] = {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
			_mark_dirty()
			_refresh_current_event_item()
		)
		container.add_child(cp)
	else:
		# 未知类型：回退到 LineEdit 字符串输入
		var le = LineEdit.new()
		le.text = str(current_val)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_changed.connect(func(t: String):
			node.params[pname] = t
			_mark_dirty()
			_refresh_current_event_item()
		)
		container.add_child(le)

# 刷新当前选中项的 Tree 显示（快捷方法）
func _refresh_current_event_item():
	if _event_tree:
		var sel = _event_tree.get_selected()
		if sel:
			_refresh_event_item_text(sel)

# 刷新单个 TreeItem 的显示文本（不重建整棵树）
func _refresh_event_item_text(item: TreeItem):
	if item == null:
		return
	var node = _get_node_from_item(item)
	if node.is_empty():
		return
	# 分组节点特殊处理
	if node.get("type") == "group":
		var name = node.get("name", "新分组")
		var status_text = "[%s] " % ("启用" if node.get("enabled", true) else "禁用")
		item.set_text(0, status_text + name)
		return
	if node.get("type") == "comment":
		item.set_text(0, "// " + node.get("text", "注释文字"))
		return
	var text = _format_event_node_text(node)
	var status_text = "[%s] " % ("启用" if node.get("enabled", true) else "禁用")
	item.set_text(0, status_text + text)

func _on_event_tree_item_edited():
	# 已改为通过"启用/禁用"按钮控制，此处不再处理
	pass

func _on_event_tree_activated():
	if not _event_tree:
		return
	var item = _event_tree.get_selected()
	if item == null:
		return
	var node = _get_node_from_item(item)
	if node.is_empty():
		return
	# 分组节点：双击编辑
	if node.get("type") == "group":
		_show_group_edit_dialog(node)
		return
	if node.get("type") == "comment":
		_show_comment_edit_dialog(node)
		return
	# 双击任何行 → 编辑参数
	_show_event_node_edit_dialog(node)

## 分组综合编辑对话框（双击或属性面板编辑）
func _show_group_edit_dialog(group: Dictionary):
	var dialog = AcceptDialog.new()
	dialog.title = "编辑分组: " + group.get("name", "")
	dialog.min_size = Vector2(360, 260)
	add_child(dialog)
	dialog.get_ok_button().visible = false
	dialog.canceled.connect(func():
		_cleanup_drag()
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(vbox)

	# 名称
	var name_hbox = HBoxContainer.new()
	var name_lbl = Label.new()
	name_lbl.text = "名称:"
	name_lbl.custom_minimum_size.x = 60
	name_hbox.add_child(name_lbl)
	var name_le = LineEdit.new()
	name_le.text = group.get("name", "新分组")
	name_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(name_le)
	vbox.add_child(name_hbox)

	# 颜色
	var color_hbox = HBoxContainer.new()
	var color_lbl = Label.new()
	color_lbl.text = "颜色:"
	color_lbl.custom_minimum_size.x = 60
	color_hbox.add_child(color_lbl)
	var cp = ColorPickerButton.new()
	cp.color = group.get("color", Color(0.9, 0.85, 0.6))
	cp.edit_alpha = true
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_hbox.add_child(cp)
	var reset_color_btn = Button.new()
	reset_color_btn.text = "默认"
	reset_color_btn.tooltip_text = "恢复默认颜色"
	color_hbox.add_child(reset_color_btn)
	vbox.add_child(color_hbox)

	# 按钮（左对齐）
	var btns = HBoxContainer.new()
	var ok_btn = Button.new()
	ok_btn.text = "确定"
	btns.add_child(ok_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	btns.add_child(cancel_btn)
	vbox.add_child(btns)

	ok_btn.pressed.connect(func():
		_cleanup_drag()
		_save_undo_state()
		var new_name = name_le.text.strip_edges()
		if new_name != "":
			group["name"] = new_name
		group["color"] = cp.color
		_mark_dirty()
		_render_events()
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)
	cancel_btn.pressed.connect(func():
		_cleanup_drag()
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)
	reset_color_btn.pressed.connect(func():
		cp.color = Color(0.9, 0.85, 0.6)
	)
	dialog.popup_centered()

## 注释编辑对话框（双击或属性面板编辑）
func _show_comment_edit_dialog(comment: Dictionary):
	var dialog = AcceptDialog.new()
	dialog.title = "编辑注释"
	dialog.min_size = Vector2(400, 260)
	add_child(dialog)
	dialog.get_ok_button().visible = false
	dialog.canceled.connect(func():
		_cleanup_drag()
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(vbox)
	var text_edit = TextEdit.new()
	text_edit.text = comment.get("text", "")
	text_edit.custom_minimum_size.y = 160
	vbox.add_child(text_edit)
	var btns = HBoxContainer.new()
	vbox.add_child(btns)
	var ok_btn = Button.new()
	ok_btn.text = "确定"
	btns.add_child(ok_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	btns.add_child(cancel_btn)
	ok_btn.pressed.connect(func():
		_cleanup_drag()
		_save_undo_state()
		comment["text"] = text_edit.text
		_mark_dirty()
		var sel = _event_tree.get_selected() if _event_tree else null
		if sel:
			_refresh_event_item_text(sel)
		else:
			_render_events()
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)
	cancel_btn.pressed.connect(func():
		_cleanup_drag()
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)
	dialog.popup_centered()

func _on_event_tree_button_clicked(_item: TreeItem, _column: int, _id: int, _mbi: int):
	pass

# 双击树行：弹出参数编辑对话框（和积木模式保持一致的控件类型）
# suppress_save: 为 true 时不自动标记脏和重新渲染（用于值块编辑器内部调用）
func _show_event_node_edit_dialog(node: Dictionary, suppress_save: bool = false):
	var def = _find_block_def(node.get("block_name", ""))
	var dialog = AcceptDialog.new()
	dialog.title = "编辑参数: " + node.get("block_name", "?")
	dialog.min_size = Vector2(420, 320)
	dialog.dialog_text = ""
	add_child(dialog)
	# 隐藏自带确定按钮
	dialog.get_ok_button().visible = false
	dialog.canceled.connect(func():
		_cleanup_drag()
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)
	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(vbox)
	for p in def.get("params", []):
		var hbox = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = p.get("label", p.name) + ": "
		lbl.add_theme_font_size_override("font_size", 12)
		hbox.add_child(lbl)
		_add_event_param_widget(hbox, node, p, true)
		# Expr 按钮：打开表达式编辑器
		var expr_btn = Button.new()
		expr_btn.text = "Expr"
		expr_btn.tooltip_text = "为参数设置表达式（运算/函数）"
		expr_btn.custom_minimum_size = Vector2(40, 24)
		var captured_p = p
		expr_btn.pressed.connect(func():
			_show_expr_editor_dialog(node, captured_p)
		)
		hbox.add_child(expr_btn)
		vbox.add_child(hbox)
	var btns = HBoxContainer.new()
	vbox.add_child(btns)
	var ok_btn = Button.new()
	ok_btn.text = "确定"
	btns.add_child(ok_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	btns.add_child(cancel_btn)
	ok_btn.pressed.connect(func():
		_cleanup_drag()
		if not suppress_save:
			_mark_dirty()
			var selected_node = node.duplicate(true)
			var root_id = _selected_event_row_id
			_render_events()
			if not _select_event_node_by_content(selected_node):
				if root_id >= 0:
					_select_event_row(root_id)
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)
	cancel_btn.pressed.connect(func():
		_cleanup_drag()
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)
	dialog.popup_centered()

# ============================================
# 表达式编辑器对话框（替代迷你画布值块编辑器）
# ============================================
func _show_expr_editor_dialog(node: Dictionary, param_def: Dictionary):
	var param_name = param_def.name
	var current_expr = node.get("exprs", {}).get(param_name, "")
	var dialog = AcceptDialog.new()
	dialog.title = "编辑表达式: %s" % param_def.get("label", param_name)
	dialog.min_size = Vector2(500, 200)
	dialog.dialog_text = ""
	add_child(dialog)
	# 隐藏 AcceptDialog 自带的"确定"按钮（使用自定义"应用"/"取消"替代）
	dialog.get_ok_button().visible = false
	dialog.canceled.connect(func():
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)

	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(vbox)

	var hint_label = Label.new()
	hint_label.text = "支持运算符: + - * /  ( )  逻辑: not, !, and, or  函数: sqrt, abs, sin, cos, tan, max, min, ..."
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint_label)

	var line_edit = LineEdit.new()
	line_edit.text = current_expr
	line_edit.placeholder_text = "输入表达式，例如: (1+2)*3"
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(line_edit)

	# 常用函数快速插入按钮
	var func_hbox = HBoxContainer.new()
	func_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(func_hbox)
	for fname in ["abs", "sqrt", "sin", "cos", "tan", "max", "min"]:
		var btn = Button.new()
		btn.text = fname
		btn.add_theme_font_size_override("font_size", 10)
		btn.custom_minimum_size = Vector2(40, 22)
		btn.pressed.connect(func():
			line_edit.insert_text_at_caret(fname + "()")
		)
		func_hbox.add_child(btn)

	# 打开函数块选择器（仅显示 VALUE 类型块，双击插入为函数调用）
	var pick_btn = Button.new()
	pick_btn.text = "插入函数块..."
	pick_btn.tooltip_text = "从 VALUE 类型积木块中选择并插入为函数调用（自动填充默认参数）"
	pick_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick_btn.pressed.connect(func():
		_show_expr_block_picker(line_edit, node)
	)
	vbox.add_child(pick_btn)

	var btns = HBoxContainer.new()
	vbox.add_child(btns)
	var apply_btn = Button.new()
	apply_btn.text = "应用"
	btns.add_child(apply_btn)
	var clear_btn = Button.new()
	clear_btn.text = "清除"
	btns.add_child(clear_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	btns.add_child(cancel_btn)

	apply_btn.pressed.connect(func():
		_save_undo_state()
		var expr = line_edit.text.strip_edges()
		if expr == "":
			# 清除表达式
			var e = node.get("exprs", {})
			e.erase(param_name)
			node["exprs"] = e
		else:
			if not node.has("exprs"):
				node["exprs"] = {}
			node["exprs"][param_name] = expr
		_mark_dirty()
		_render_events()
		_update_event_prop_panel()
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)

	clear_btn.pressed.connect(func():
		line_edit.text = ""
	)

	cancel_btn.pressed.connect(func():
		_prevent_drag_after_dialog = true
		dialog.queue_free()
	)

	dialog.popup_centered()
	line_edit.grab_focus.call_deferred()
	line_edit.select_all()

# ============================================
# 表达式函数块选择器（仅 VALUE 类型块，双击插入为函数调用）
# ============================================
# 将一个 VALUE 块格式化为函数调用字符串：name(default1, default2, ...)
func _format_value_block_as_func(def: Dictionary, param_overrides: Dictionary = {}) -> String:
	var args = []
	for p in def.get("params", []):
		var pname = p.get("name", "")
		var raw_val = param_overrides.get(pname, p.get("default", ""))
		# 从 LineEdit 读取的值是字符串，需要根据类型判断是否加引号
		var arg_str = ""
		if p.type == "string" or p.type == "node":
			# 字符串/节点路径用双引号包裹（如果还没包裹的话）
			var sv = str(raw_val).strip_edges()
			if sv.begins_with("\"") and sv.ends_with("\""):
				arg_str = sv
			else:
				arg_str = "\"%s\"" % sv
		elif p.type == "bool":
			arg_str = "true" if bool(raw_val) else "false"
		elif p.type == "color":
			var d = raw_val if raw_val is Dictionary else {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}
			arg_str = "Color(%s, %s, %s, %s)" % [str(d.get("r", 1.0)), str(d.get("g", 1.0)), str(d.get("b", 1.0)), str(d.get("a", 1.0))]
		else:
			# number / dropdown / 其它：直接使用字面值
			arg_str = str(raw_val)
		args.append(arg_str)
	return "%s(%s)" % [def.name, ", ".join(args)]

## 从不同类型的参数控件中读取当前值的字符串表示
func _get_widget_value(widget: Control, ptype: String) -> String:
	if widget is SpinBox:
		var v = widget.value
		# 整数不显示小数点，否则保留最多 6 位小数（去除尾部零）
		if v == floor(v):
			return str(int(v))
		var s = "%.6f" % v
		# 去除尾部多余的零
		while s.ends_with("0") and not s.ends_with(".0"):
			s = s.substr(0, s.length() - 1)
		return s
	elif widget is CheckBox or widget is CheckButton:
		return "true" if widget.button_pressed else "false"
	elif widget is OptionButton:
		var idx = widget.selected
		if idx >= 0 and idx < widget.item_count:
			return widget.get_item_text(idx)
		return ""
	elif widget is ColorPickerButton:
		var c = widget.color
		return "Color(%s, %s, %s, %s)" % [str(c.r), str(c.g), str(c.b), str(c.a)]
	else: # LineEdit 或其它
		if widget.has_method("get_text"):
			return widget.text
		return ""

## 收集事件表中某节点之前所有可用输出（上文输出）
## 返回数组: [{"name": "frame_idx", "label": "当前帧", "type": "node", "source": "when_animation_playing"}, ...]
func _vs_collect_context_outputs(context_node: Dictionary) -> Array:
	var outputs: Array = []
	if context_node.is_empty():
		return outputs
	# 找到包含该节点的事件行
	var target_row: Dictionary = {}
	for row in _events_data.get("rows", []):
		if is_same(row, context_node):
			target_row = row
			break
		if _vs_node_contains_child(row, context_node):
			target_row = row
			break
	if target_row.is_empty():
		return outputs
	# 事件根本身的输出
	var row_def = _find_block_def(target_row.get("block_name", ""))
	for out in row_def.get("outputs", []):
		outputs.append({
			"name": out.get("name", ""),
			"label": out.get("label", out.get("name", "")),
			"type": out.get("type", ""),
			"source": target_row.get("block_name", "")
		})
	# 前序遍历 children，收集当前节点之前所有块的输出
	# found_flag 用单元素数组作为引用 (GDScript 中 bool 按值传递)
	var found_flag: Array = [false]
	_vs_collect_preceding_outputs(target_row.get("children", []), context_node, outputs, found_flag)
	return outputs

## 递归检查 node 是否是 parent 的后代
func _vs_node_contains_child(parent: Dictionary, target: Dictionary) -> bool:
	for child in parent.get("children", []):
		if is_same(child, target):
			return true
		if _vs_node_contains_child(child, target):
			return true
	return false

## 前序遍历收集 preceding 节点的输出，遇到 target 停止
## found_flag 为单元素数组 [bool]，作为引用传递以便递归向上传播
func _vs_collect_preceding_outputs(children: Array, target: Dictionary, outputs: Array, found_flag: Array):
	for child in children:
		if found_flag[0]:
			return
		if is_same(child, target):
			found_flag[0] = true
			return
		# 收集此子块的输出
		var child_def = _find_block_def(child.get("block_name", ""))
		for out in child_def.get("outputs", []):
			outputs.append({
				"name": out.get("name", ""),
				"label": out.get("label", out.get("name", "")),
				"type": out.get("type", ""),
				"source": child.get("block_name", "")
			})
		# 递归子节点
		_vs_collect_preceding_outputs(child.get("children", []), target, outputs, found_flag)
		if found_flag[0]:
			return

func _show_expr_block_picker(line_edit: LineEdit, context_node: Dictionary = {}):
	# 收集所有 VALUE 类型块定义，按分类组织
	var value_defs_by_cat: Dictionary = {}
	for def in _block_defs:
		if def.type == BlockType.VALUE:
			var cat = def.get("category", "未分类")
			if not value_defs_by_cat.has(cat):
				value_defs_by_cat[cat] = []
			value_defs_by_cat[cat].append(def)
	# 上文输出项（仅代码虚拟分类，不创建真实块定义）
	var context_outputs: Array = _vs_collect_context_outputs(context_node)
	var has_context_outputs = not context_outputs.is_empty()
	if value_defs_by_cat.is_empty() and not has_context_outputs:
		var msg = AcceptDialog.new()
		msg.title = "提示"
		msg.dialog_text = "没有可用的 VALUE 类型积木块定义，也没有上文输出。"
		add_child(msg)
		msg.confirmed.connect(func(): msg.queue_free())
		msg.canceled.connect(func(): msg.queue_free())
		msg.popup_centered()
		return

	var picker = AcceptDialog.new()
	picker.title = "插入函数块 / 上文输出"
	picker.min_size = Vector2(720, 460)
	picker.dialog_text = ""
	add_child(picker)
	# 隐藏 AcceptDialog 自带的"确定"按钮（双击项目即可插入，无需确认按钮）
	picker.get_ok_button().visible = false

	var main_hbox = HBoxContainer.new()
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 8)
	picker.add_child(main_hbox)

	# 左侧：分类列表
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(160, 0)
	left_vbox.add_theme_constant_override("separation", 4)
	main_hbox.add_child(left_vbox)
	var cat_title = Label.new()
	cat_title.text = "分类"
	cat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cat_title.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(cat_title)
	var cat_list = ItemList.new()
	cat_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cat_list.select_mode = ItemList.SELECT_SINGLE
	left_vbox.add_child(cat_list)

	# 中间：块列表
	var mid_vbox = VBoxContainer.new()
	mid_vbox.custom_minimum_size = Vector2(220, 0)
	mid_vbox.add_theme_constant_override("separation", 4)
	main_hbox.add_child(mid_vbox)
	var blk_title = Label.new()
	blk_title.text = "项目"
	blk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blk_title.add_theme_font_size_override("font_size", 14)
	mid_vbox.add_child(blk_title)
	var block_list = ItemList.new()
	block_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	block_list.select_mode = ItemList.SELECT_SINGLE
	mid_vbox.add_child(block_list)

	# 右侧：参数详情（显示可输入的类型）
	var right_scroll = ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_hbox.add_child(right_scroll)
	var detail_vbox = VBoxContainer.new()
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.add_theme_constant_override("separation", 6)
	right_scroll.add_child(detail_vbox)

	# 填充分类列表：上文输出置顶，其后跟随 VALUE 块分类
	var cats: Array = []
	if has_context_outputs:
		cats.append("上文输出")
	for cat in value_defs_by_cat.keys():
		cats.append(cat)
	for cat in cats:
		cat_list.add_item(cat)
	# 当前分类下的项目数组（与 block_list 索引对应）
	# 每项: {"kind": "value"|"context", "data": def_dict | output_dict}
	var current_items: Array = []
	# 存储当前 VALUE 块的可编辑参数控件引用
	# (param_name → {"widget": Control, "type": String, "options": Array})
	var _current_picker_params_edits: Dictionary = {}

	# 刷新右侧详情 — 处理两种项目类型
	var _refresh_detail = func(item: Dictionary):
		for child in detail_vbox.get_children():
			child.queue_free()
		if item.is_empty():
			var hint = Label.new()
			hint.text = "选择一个项目以查看详情"
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			detail_vbox.add_child(hint)
			return
		var kind = item.get("kind", "")
		var data = item.get("data", {})
		if kind == "context":
			# 上文输出项：显示变量名、类型、来源
			var name_lbl = Label.new()
			name_lbl.text = "上文输出: %s" % data.get("label", data.get("name", ""))
			name_lbl.add_theme_font_size_override("font_size", 14)
			name_lbl.add_theme_color_override("font_color", Color.YELLOW)
			detail_vbox.add_child(name_lbl)
			var preview = Label.new()
			preview.text = "插入: " + data.get("name", "")
			preview.add_theme_color_override("font_color", Color.CYAN)
			preview.add_theme_font_size_override("font_size", 12)
			detail_vbox.add_child(preview)
			detail_vbox.add_child(HSeparator.new())
			var info_title = Label.new()
			info_title.text = "变量信息"
			info_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			info_title.add_theme_font_size_override("font_size", 13)
			detail_vbox.add_child(info_title)
			var row1 = HBoxContainer.new()
			row1.add_theme_constant_override("separation", 6)
			var nm1 = Label.new()
			nm1.text = "变量名"
			nm1.custom_minimum_size = Vector2(80, 0)
			nm1.add_theme_font_size_override("font_size", 12)
			row1.add_child(nm1)
			var val1 = Label.new()
			val1.text = data.get("name", "")
			val1.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
			val1.add_theme_font_size_override("font_size", 12)
			val1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row1.add_child(val1)
			detail_vbox.add_child(row1)
			var row2 = HBoxContainer.new()
			row2.add_theme_constant_override("separation", 6)
			var nm2 = Label.new()
			nm2.text = "类型"
			nm2.custom_minimum_size = Vector2(80, 0)
			nm2.add_theme_font_size_override("font_size", 12)
			row2.add_child(nm2)
			var val2 = Label.new()
			val2.text = "[%s]" % data.get("type", "")
			val2.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
			val2.add_theme_font_size_override("font_size", 12)
			val2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(val2)
			detail_vbox.add_child(row2)
			var row3 = HBoxContainer.new()
			row3.add_theme_constant_override("separation", 6)
			var nm3 = Label.new()
			nm3.text = "来源块"
			nm3.custom_minimum_size = Vector2(80, 0)
			nm3.add_theme_font_size_override("font_size", 12)
			row3.add_child(nm3)
			var val3 = Label.new()
			val3.text = data.get("source", "")
			val3.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			val3.add_theme_font_size_override("font_size", 12)
			val3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row3.add_child(val3)
			detail_vbox.add_child(row3)
			var hint = Label.new()
			hint.text = "双击可直接插入变量名"
			hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			hint.add_theme_font_size_override("font_size", 11)
			detail_vbox.add_child(hint)
			return
		# kind == "value" — VALUE 块定义
		var def = data
		var name_lbl = Label.new()
		name_lbl.text = "块: %s" % def.get("label", def.name)
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color.YELLOW)
		detail_vbox.add_child(name_lbl)
		var func_preview = Label.new()
		func_preview.text = "预览: " + _format_value_block_as_func(def)
		func_preview.add_theme_color_override("font_color", Color.CYAN)
		func_preview.add_theme_font_size_override("font_size", 12)
		detail_vbox.add_child(func_preview)
		detail_vbox.add_child(HSeparator.new())
		# 用于刷新预览的辅助函数
		var _refresh_preview = func():
			var ov: Dictionary = {}
			for pn in _current_picker_params_edits:
				var entry = _current_picker_params_edits[pn]
				if entry is Dictionary:
					var w = entry.get("widget")
					var pt = entry.get("type", "string")
					if is_instance_valid(w):
						ov[pn] = _get_widget_value(w, pt)
			func_preview.text = "预览: " + _format_value_block_as_func(def, ov)
		var pt_title = Label.new()
		pt_title.text = "参数 (可输入的类型)"
		pt_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		pt_title.add_theme_font_size_override("font_size", 13)
		detail_vbox.add_child(pt_title)
		var params = def.get("params", [])
		if params.is_empty():
			var empty = Label.new()
			empty.text = "（无参数）"
			empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			detail_vbox.add_child(empty)
		else:
			# 存储当前 VALUE 块的可编辑参数控件引用，供双击插入时读取
			# 每项: { "widget": Control, "type": String, "options": Array }
			_current_picker_params_edits.clear()
			for p in params:
				var pname = p.get("name", "")
				var ptype = str(p.get("type", "string"))
				var poptions = p.get("options", [])
				var row = HBoxContainer.new()
				row.add_theme_constant_override("separation", 6)
				var nm = Label.new()
				nm.text = p.get("label", pname)
				nm.custom_minimum_size = Vector2(80, 0)
				nm.add_theme_font_size_override("font_size", 12)
				row.add_child(nm)
				var ty = Label.new()
				ty.text = "[%s]" % ptype
				ty.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
				ty.custom_minimum_size = Vector2(70, 0)
				ty.add_theme_font_size_override("font_size", 12)
				row.add_child(ty)
				var widget: Control = null
				# 根据参数类型创建对应的编辑控件
				if ptype == "bool":
					var cb = CheckBox.new()
					cb.text = "已启用"
					widget = cb
				elif ptype == "dropdown":
					var ob = OptionButton.new()
					for opt in poptions:
						ob.add_item(str(opt))
					widget = ob
				elif ptype == "number":
					var sb = SpinBox.new()
					sb.min_value = -2147483647
					sb.max_value = 2147483647
					sb.step = 0.001
					sb.allow_greater = true
					sb.allow_lesser = true
					widget = sb
				elif ptype == "color":
					var cp = ColorPickerButton.new()
					cp.custom_minimum_size = Vector2(80, 0)
					cp.get_popup().exclusive = true
					widget = cp
				else:
					# string / node / 其它类型：使用 LineEdit
					var le = LineEdit.new()
					le.placeholder_text = "默认值"
					widget = le
				widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				widget.add_theme_font_size_override("font_size", 12)
				row.add_child(widget)
				# ★ 必须在设置初始值之前存入字典，否则初始值触发的信号中 _refresh_preview 会找不到控件
				_current_picker_params_edits[pname] = {"widget": widget, "type": ptype, "options": poptions}
				# 设置初始值并连接信号（放在字典写入之后）
				if ptype == "bool":
					var cb = widget as CheckBox
					cb.button_pressed = bool(p.get("default", false))
					cb.toggled.connect(func(_toggled: bool): _refresh_preview.call())
				elif ptype == "dropdown":
					var ob = widget as OptionButton
					var def_val = str(p.get("default", ""))
					for i in range(ob.item_count):
						if ob.get_item_text(i) == def_val:
							ob.select(i)
							break
					ob.item_selected.connect(func(_idx: int): _refresh_preview.call())
				elif ptype == "number":
					var sb = widget as SpinBox
					sb.value = float(p.get("default", 0))
					sb.value_changed.connect(func(_v: float): _refresh_preview.call())
				elif ptype == "color":
					var cp = widget as ColorPickerButton
					var d = p.get("default", {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0})
					cp.color = Color(d.get("r", 1.0), d.get("g", 1.0), d.get("b", 1.0), d.get("a", 1.0))
					cp.color_changed.connect(func(_c: Color): _refresh_preview.call())
				else:
					var le = widget as LineEdit
					le.text = str(p.get("default", ""))
					le.text_changed.connect(func(_t): _refresh_preview.call())
				detail_vbox.add_child(row)
			var edit_hint = Label.new()
			edit_hint.text = "修改上方参数值后，双击项目即可插入自定义参数"
			edit_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.7))
			edit_hint.add_theme_font_size_override("font_size", 10)
			detail_vbox.add_child(edit_hint)

	# 选中分类 → 刷新项目列表
	var _select_cat = func(idx: int):
		if idx < 0 or idx >= cats.size():
			return
		var cat = cats[idx]
		block_list.clear()
		current_items.clear()
		if cat == "上文输出":
			# 上文输出项：显示 label，附带来源块名提示
			for out in context_outputs:
				var display_text = "%s  (来自: %s)" % [out.get("label", out.get("name", "")), out.get("source", "")]
				block_list.add_item(display_text)
				current_items.append({"kind": "context", "data": out})
		else:
			for def in value_defs_by_cat[cat]:
				block_list.add_item(def.get("label", def.name))
				current_items.append({"kind": "value", "data": def})
		_refresh_detail.call({})
	cat_list.item_selected.connect(_select_cat)

	# 选中项目 → 刷新详情
	block_list.item_selected.connect(func(idx: int):
		if idx < 0 or idx >= current_items.size():
			return
		_refresh_detail.call(current_items[idx])
	)

	# 双击项目 → 插入并关闭
	# 上文输出：插入变量名 (如 frame_idx)
	# VALUE 块：插入函数调用 (如 calculate(0, "+", 0))
	block_list.item_activated.connect(func(idx: int):
		if idx < 0 or idx >= current_items.size():
			return
		var item = current_items[idx]
		var kind = item.get("kind", "")
		var data = item.get("data", {})
		if kind == "context":
			line_edit.insert_text_at_caret(str(data.get("name", "")))
		else:
			# 从可编辑参数控件读取用户当前修改的值
			var override_vals: Dictionary = {}
			for pname in _current_picker_params_edits:
				var entry = _current_picker_params_edits[pname]
				if entry is Dictionary:
					var w = entry.get("widget")
					var pt = entry.get("type", "string")
					if is_instance_valid(w):
						override_vals[pname] = _get_widget_value(w, pt)
			line_edit.insert_text_at_caret(_format_value_block_as_func(data, override_vals))
		line_edit.grab_focus()
		picker.queue_free()
	)

	picker.confirmed.connect(func(): picker.queue_free())
	picker.canceled.connect(func(): picker.queue_free())
	picker.popup_centered()
	# 默认选中第一个分类
	if cat_list.item_count > 0:
		cat_list.select(0)
		_select_cat.call(0)

# ============================================
# 积木 → 事件表 转换（树形结构）
# ============================================
func _create_event_node_from_block(block: Dictionary) -> Dictionary:
	var node = _create_event_child(block.def)
	node.params = block.params.duplicate(true)
	# 事件表不再使用 value_blocks/value_slots，积木中嵌入的值块在转换时忽略
	# 递归收集内部块作为 children
	var inner_ids = block.get("inner_block_ids", [])
	for iid in inner_ids:
		var inner = _get_block_by_id(int(iid))
		if not inner.is_empty():
			node.children.append(_create_event_node_from_block(inner))
	# 沿 stack_below_id 链收集同级动作块作为 children
	var cur_id = block.get("stack_below_id", -1)
	var guard = 0
	while cur_id >= 0 and guard < 1000:
		guard += 1
		var b = _get_block_by_id(cur_id)
		if b.is_empty():
			break
		node.children.append(_create_event_node_from_block(b))
		cur_id = b.get("stack_below_id", -1)
	return node

func _on_convert_blocks_to_events():
	if _save_timer:
		_save_timer.stop()
	await _show_progress("正在转化积木为事件表...")
	await _update_progress(0.1, "收集事件块...")
	var event_rows = []
	var total_blocks = _blocks.size()
	var processed = 0
	for block in _blocks:
		processed += 1
		if block.def.type != BlockType.EVENT:
			continue
		if _is_block_in_slot(block.id) or _is_inner_block(block.id):
			continue
		var row = _create_event_root(block.def)
		row.params = block.params.duplicate(true)
		# 收集事件块下的动作链作为 children
		var cur_id = block.get("stack_below_id", -1)
		var guard = 0
		while cur_id >= 0 and guard < 1000:
			guard += 1
			var b = _get_block_by_id(cur_id)
			if b.is_empty():
				break
			row.children.append(_create_event_node_from_block(b))
			cur_id = b.get("stack_below_id", -1)
		event_rows.append(row)
		# 每 5 个块更新一次进度
		if processed % 5 == 0:
			var ratio = 0.1 + (float(processed) / float(total_blocks)) * 0.5
			await _update_progress(ratio, "处理积木块 %d/%d..." % [processed, total_blocks])
	if event_rows.is_empty():
		print("[visual_script_editor] 未找到可转换的事件积木块（需要顶层 EVENT 类型块）")
		_hide_progress()
		return
	await _update_progress(0.75, "渲染事件表...")
	_events_data.rows = event_rows
	_selected_event_row_id = -1
	_mark_dirty()
	_render_events()
	await _update_progress(0.9, "保存文件...")
	# 直接写入，不用定时器
	_save_all_data()
	await _update_progress(1.0, "转化完成")
	_hide_progress()
	print("[visual_script_editor] 已从积木转换生成 %d 条事件" % event_rows.size())

# ============================================
# CSV 导入 / 导出
# ============================================
func _serialize_event_tree(node: Dictionary, depth: int) -> String:
	var prefix = "  ".repeat(depth)
	var line = prefix + _format_event_node_text(node)
	var lines = [line]
	for child in node.get("children", []):
		lines.append(_serialize_event_tree(child, depth + 1))
	return "\n".join(lines)



# ============================================
# 块定义编辑器（原样保留，无改动）
# ============================================
var _editor_dialog: AcceptDialog = null
var _is_editing_block_defs: bool = false
var _editor_cat_list: ItemList = null
var _editor_block_list: ItemList = null
var _editor_block_detail: VBoxContainer = null
var _editor_selected_cat: String = ""
var _editor_selected_block_idx: int = -1
var _editor_params_container: VBoxContainer = null
var _editor_outputs_container: VBoxContainer = null

func _show_block_editor():
	_is_editing_block_defs = true
	if _editor_dialog and is_instance_valid(_editor_dialog):
		_editor_dialog.popup_centered()
		_refresh_editor_cat_list()
		return
	_editor_dialog = AcceptDialog.new()
	_editor_dialog.title = "块定义编辑器"
	_editor_dialog.min_size = Vector2(900, 600)
	add_child(_editor_dialog)
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 8)
	_editor_dialog.add_child(main_hbox)
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(180, 0)
	left_vbox.add_theme_constant_override("separation", 4)
	main_hbox.add_child(left_vbox)
	var cat_title = Label.new()
	cat_title.text = "分类"
	cat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cat_title.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(cat_title)
	_editor_cat_list = ItemList.new()
	_editor_cat_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_cat_list.select_mode = ItemList.SELECT_SINGLE
	_editor_cat_list.item_selected.connect(_on_editor_cat_selected)
	left_vbox.add_child(_editor_cat_list)
	var cat_btn_hbox = HBoxContainer.new()
	left_vbox.add_child(cat_btn_hbox)
	var add_cat_btn = Button.new()
	add_cat_btn.text = "添加分类"
	add_cat_btn.pressed.connect(_on_editor_add_category)
	cat_btn_hbox.add_child(add_cat_btn)
	var del_cat_btn = Button.new()
	del_cat_btn.text = "删除分类"
	del_cat_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	del_cat_btn.pressed.connect(_on_editor_del_category)
	cat_btn_hbox.add_child(del_cat_btn)
	var cat_color_hbox = HBoxContainer.new()
	left_vbox.add_child(cat_color_hbox)
	var cat_color_label = Label.new()
	cat_color_label.text = "颜色:"
	cat_color_label.custom_minimum_size = Vector2(40, 0)
	cat_color_hbox.add_child(cat_color_label)
	var cat_color_picker = ColorPickerButton.new()
	cat_color_picker.name = "CatColorPicker"
	cat_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_color_picker.color_changed.connect(_on_editor_cat_color_changed)
	cat_color_hbox.add_child(cat_color_picker)
	var mid_vbox = VBoxContainer.new()
	mid_vbox.custom_minimum_size = Vector2(200, 0)
	mid_vbox.add_theme_constant_override("separation", 4)
	main_hbox.add_child(mid_vbox)
	var blk_title = Label.new()
	blk_title.text = "积木块"
	blk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blk_title.add_theme_font_size_override("font_size", 14)
	mid_vbox.add_child(blk_title)
	_editor_block_list = ItemList.new()
	_editor_block_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_block_list.select_mode = ItemList.SELECT_SINGLE
	_editor_block_list.item_selected.connect(_on_editor_block_selected)
	mid_vbox.add_child(_editor_block_list)
	var blk_btn_hbox = HBoxContainer.new()
	mid_vbox.add_child(blk_btn_hbox)
	var add_blk_btn = Button.new()
	add_blk_btn.text = "添加块"
	add_blk_btn.pressed.connect(_on_editor_add_block)
	blk_btn_hbox.add_child(add_blk_btn)
	var del_blk_btn = Button.new()
	del_blk_btn.text = "删除块"
	del_blk_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	del_blk_btn.pressed.connect(_on_editor_del_block)
	blk_btn_hbox.add_child(del_blk_btn)
	var up_blk_btn = Button.new()
	up_blk_btn.text = "▲"
	up_blk_btn.pressed.connect(_on_editor_move_block_up)
	blk_btn_hbox.add_child(up_blk_btn)
	var down_blk_btn = Button.new()
	down_blk_btn.text = "▼"
	down_blk_btn.pressed.connect(_on_editor_move_block_down)
	blk_btn_hbox.add_child(down_blk_btn)
	var copy_blk_btn = Button.new()
	copy_blk_btn.text = "复制"
	copy_blk_btn.pressed.connect(_on_editor_copy_block)
	blk_btn_hbox.add_child(copy_blk_btn)
	var right_scroll = ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_hbox.add_child(right_scroll)
	_editor_block_detail = VBoxContainer.new()
	_editor_block_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_block_detail.add_theme_constant_override("separation", 6)
	right_scroll.add_child(_editor_block_detail)
	_refresh_editor_cat_list()
	_editor_dialog.popup_centered()
	_editor_dialog.add_button("保存块定义", true, "save_defs")
	_editor_dialog.custom_action.connect(_on_editor_custom_action)
	_editor_dialog.confirmed.connect(_on_editor_dialog_closed)
	_editor_dialog.canceled.connect(_on_editor_dialog_closed)

func _refresh_editor_cat_list():
	if not _editor_cat_list: return
	_editor_cat_list.clear()
	for cat in _categories:
		_editor_cat_list.add_item(cat)
	if _categories.size() > 0:
		_editor_cat_list.select(0)
		_editor_selected_cat = _categories[0]
		_refresh_editor_block_list()
		_update_editor_cat_color_picker()
	else:
		_editor_selected_cat = ""
		_refresh_editor_block_list()

func _sync_categories_from_defs():
	_categories.clear()
	for def in _block_defs:
		if def.category not in _categories:
			_categories.append(def.category)
	var to_remove = []
	for cat in _category_colors.keys():
		if cat not in _categories:
			to_remove.append(cat)
	for cat in to_remove:
		_category_colors.erase(cat)

func _rebuild_categories_from_defs():
	_sync_categories_from_defs()

func _refresh_editor_block_list():
	if not _editor_block_list: return
	var selected_def_name = ""
	if _editor_selected_block_idx >= 0:
		var def = _get_editor_selected_def()
		if not def.is_empty(): selected_def_name = def.name
	_editor_block_list.clear()
	if _editor_selected_cat == "":
		_editor_selected_block_idx = -1
		_refresh_editor_block_detail()
		return
	var new_selected_idx = -1
	var idx = 0
	for i in range(_block_defs.size()):
		if _block_defs[i].category == _editor_selected_cat:
			var def = _block_defs[i]
			var type_name = BlockType.keys()[def.type]
			_editor_block_list.add_item("[%s] %s" % [type_name, def.label])
			if def.name == selected_def_name:
				new_selected_idx = idx
			idx += 1
	if new_selected_idx >= 0:
		_editor_block_list.select(new_selected_idx)
		_editor_selected_block_idx = new_selected_idx
	else:
		_editor_selected_block_idx = -1
	_refresh_editor_block_detail()

func _on_editor_cat_selected(index: int):
	if index < 0 or index >= _categories.size(): return
	_editor_selected_cat = _categories[index]
	_refresh_editor_block_list()
	_update_editor_cat_color_picker()

func _update_editor_cat_color_picker():
	if not _editor_dialog or not is_instance_valid(_editor_dialog): return
	var picker = _editor_dialog.find_child("CatColorPicker", true, false)
	if picker and picker is ColorPickerButton:
		if _category_colors.has(_editor_selected_cat):
			picker.color = _category_colors[_editor_selected_cat]
		else:
			picker.color = Color.GRAY

func _on_editor_cat_color_changed(color: Color):
	if _editor_selected_cat == "": return
	_category_colors[_editor_selected_cat] = color
	_refresh_all_block_nodes()

func _on_editor_add_category():
	var dialog = ConfirmationDialog.new()
	dialog.title = "添加分类"
	dialog.min_size = Vector2(300, 120)
	dialog.ok_button_text = "添加"
	dialog.cancel_button_text = "取消"
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "输入分类名称"
	vbox.add_child(line_edit)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var cat_name = line_edit.text.strip_edges()
		if cat_name != "" and cat_name not in _categories:
			_categories.append(cat_name)
			_category_colors[cat_name] = Color.GRAY
			_refresh_editor_cat_list()
			var idx = _categories.find(cat_name)
			if idx >= 0:
				_editor_cat_list.select(idx)
				_editor_selected_cat = cat_name
				_refresh_editor_block_list()
				_update_editor_cat_color_picker()
	)
	dialog.close_requested.connect(func(): dialog.queue_free())
	line_edit.grab_focus.call_deferred()
	dialog.popup_centered()

func _on_editor_del_category():
	if _editor_selected_cat == "": return
	var blocks_in_cat = _block_defs.filter(func(d): return d.category == _editor_selected_cat)
	if blocks_in_cat.size() > 0:
		var dialog = ConfirmationDialog.new()
		dialog.title = "确认删除分类"
		dialog.dialog_text = "删除分类「%s」将同时删除其下所有积木块定义，确定吗？" % _editor_selected_cat
		dialog.ok_button_text = "删除"
		dialog.cancel_button_text = "取消"
		dialog.confirmed.connect(func():
			_do_delete_category()
			dialog.queue_free()
		)
		dialog.close_requested.connect(func(): dialog.queue_free())
		add_child(dialog)
		dialog.popup_centered()
	else:
		_do_delete_category()

func _do_delete_category():
	_block_defs = _block_defs.filter(func(d): return d.category != _editor_selected_cat)
	_categories.erase(_editor_selected_cat)
	_category_colors.erase(_editor_selected_cat)
	_editor_selected_cat = ""
	_refresh_editor_cat_list()
	_sync_main_panel()

func _on_editor_block_selected(index: int):
	_editor_selected_block_idx = index
	_refresh_editor_block_detail()

func _on_editor_add_block():
	if _editor_selected_cat == "": return
	var new_def = {
		"type": BlockType.ACTION,
		"name": "new_block_%d" % (_block_defs.size() + 1),
		"label": "新块",
		"category": _editor_selected_cat,
		"params": [],
		"outputs": [],
	}
	_block_defs.append(new_def)
	_refresh_editor_block_list()
	_sync_main_panel()

func _on_editor_copy_block():
	if _editor_selected_cat == "" or _editor_selected_block_idx < 0: return
	var src_def = _get_editor_selected_def()
	if src_def.is_empty(): return
	var copy_def = src_def.duplicate(true)
	copy_def.name = copy_def.name + "_copy"
	copy_def.label = copy_def.label + " (副本)"
	_block_defs.append(copy_def)
	_editor_selected_block_idx = _get_editor_block_indices().size() - 1
	_refresh_editor_block_list()
	_sync_main_panel()

func _on_editor_del_block():
	if _editor_selected_cat == "" or _editor_selected_block_idx < 0: return
	var count = 0
	var real_idx = -1
	var block_label = ""
	for i in range(_block_defs.size()):
		if _block_defs[i].category == _editor_selected_cat:
			if count == _editor_selected_block_idx:
				real_idx = i
				block_label = _block_defs[i].label
				break
			count += 1
	if real_idx < 0: return
	var dialog = ConfirmationDialog.new()
	dialog.title = "确认删除"
	dialog.dialog_text = "确定删除积木块「%s」吗？" % block_label
	dialog.ok_button_text = "删除"
	dialog.cancel_button_text = "取消"
	add_child(dialog)
	dialog.confirmed.connect(func():
		_block_defs.remove_at(real_idx)
		_refresh_editor_block_list()
		_sync_main_panel()
	)
	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _get_editor_block_indices() -> Array:
	var indices = []
	for i in range(_block_defs.size()):
		if _block_defs[i].category == _editor_selected_cat:
			indices.append(i)
	return indices

func _on_editor_move_block_up():
	if _editor_selected_cat == "" or _editor_selected_block_idx <= 0: return
	var indices = _get_editor_block_indices()
	if _editor_selected_block_idx >= indices.size(): return
	var idx_a = indices[_editor_selected_block_idx]
	var idx_b = indices[_editor_selected_block_idx - 1]
	var tmp = _block_defs[idx_a]
	_block_defs[idx_a] = _block_defs[idx_b]
	_block_defs[idx_b] = tmp
	_editor_selected_block_idx -= 1
	_refresh_editor_block_list()
	_sync_main_panel()

func _on_editor_move_block_down():
	if _editor_selected_cat == "": return
	var indices = _get_editor_block_indices()
	if _editor_selected_block_idx < 0 or _editor_selected_block_idx >= indices.size() - 1: return
	var idx_a = indices[_editor_selected_block_idx]
	var idx_b = indices[_editor_selected_block_idx + 1]
	var tmp = _block_defs[idx_a]
	_block_defs[idx_a] = _block_defs[idx_b]
	_block_defs[idx_b] = tmp
	_editor_selected_block_idx += 1
	_refresh_editor_block_list()
	_sync_main_panel()

func _get_editor_selected_def() -> Dictionary:
	if _editor_selected_cat == "" or _editor_selected_block_idx < 0: return {}
	var count = 0
	for i in range(_block_defs.size()):
		if _block_defs[i].category == _editor_selected_cat:
			if count == _editor_selected_block_idx:
				return _block_defs[i]
			count += 1
	return {}

func _refresh_editor_block_detail():
	if not _editor_block_detail: return
	for child in _editor_block_detail.get_children():
		child.queue_free()
	var def = _get_editor_selected_def()
	if def.is_empty():
		var hint = Label.new()
		hint.text = "选择一个积木块以编辑"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_editor_block_detail.add_child(hint)
		return
	var type_hbox = HBoxContainer.new()
	var type_label = Label.new()
	type_label.text = "类型:"
	type_label.custom_minimum_size = Vector2(60, 0)
	type_hbox.add_child(type_label)
	var type_opt = OptionButton.new()
	for i in range(BlockType.size()):
		type_opt.add_item(BlockType.keys()[i])
	type_opt.select(def.type)
	type_opt.item_selected.connect(func(idx): def.type = idx; _refresh_editor_block_list(); _sync_main_panel())
	type_hbox.add_child(type_opt)
	_editor_block_detail.add_child(type_hbox)
	var name_hbox = HBoxContainer.new()
	var name_label = Label.new()
	name_label.text = "名称:"
	name_label.custom_minimum_size = Vector2(60, 0)
	name_hbox.add_child(name_label)
	var name_edit = LineEdit.new()
	name_edit.text = def.name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t): def.name = t.strip_edges(); _sync_main_panel())
	name_hbox.add_child(name_edit)
	_editor_block_detail.add_child(name_hbox)
	var lbl_hbox = HBoxContainer.new()
	var lbl_label = Label.new()
	lbl_label.text = "标签:"
	lbl_label.custom_minimum_size = Vector2(60, 0)
	lbl_hbox.add_child(lbl_label)
	var lbl_edit = LineEdit.new()
	lbl_edit.text = def.label
	lbl_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_edit.placeholder_text = "用 {参数名} 插入内联槽位"
	lbl_edit.text_changed.connect(func(t):
		def.label = t
		if _editor_selected_block_idx >= 0 and _editor_selected_block_idx < _editor_block_list.item_count:
			var type_name = BlockType.keys()[def.type]
			_editor_block_list.set_item_text(_editor_selected_block_idx, "[%s] %s" % [type_name, def.label])
		_sync_main_panel()
	)
	lbl_hbox.add_child(lbl_edit)
	_editor_block_detail.add_child(lbl_hbox)
	var lbl_hint = Label.new()
	lbl_hint.text = "提示: 在标签中使用 {参数名} 可将参数槽位内联显示"
	lbl_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	lbl_hint.add_theme_font_size_override("font_size", 11)
	_editor_block_detail.add_child(lbl_hint)
	var cat_hbox = HBoxContainer.new()
	var cat_label = Label.new()
	cat_label.text = "分类:"
	cat_label.custom_minimum_size = Vector2(60, 0)
	cat_hbox.add_child(cat_label)
	var cat_opt = OptionButton.new()
	for i in range(_categories.size()):
		cat_opt.add_item(_categories[i])
		if _categories[i] == def.category:
			cat_opt.select(i)
	cat_opt.item_selected.connect(func(idx):
		if idx >= 0 and idx < _categories.size():
			def.category = _categories[idx]
			_refresh_editor_cat_list()
			_sync_main_panel()
	)
	cat_hbox.add_child(cat_opt)
	_editor_block_detail.add_child(cat_hbox)
	_editor_block_detail.add_child(HSeparator.new())
	var param_title_hbox = HBoxContainer.new()
	var param_title = Label.new()
	param_title.text = "参数列表"
	param_title.add_theme_color_override("font_color", Color.YELLOW)
	param_title.add_theme_font_size_override("font_size", 14)
	param_title_hbox.add_child(param_title)
	var add_param_btn = Button.new()
	add_param_btn.text = "+ 添加参数"
	add_param_btn.pressed.connect(_on_editor_add_param)
	param_title_hbox.add_child(add_param_btn)
	_editor_block_detail.add_child(param_title_hbox)
	_editor_params_container = VBoxContainer.new()
	_editor_params_container.add_theme_constant_override("separation", 4)
	_editor_block_detail.add_child(_editor_params_container)
	_refresh_editor_params()
	_editor_block_detail.add_child(HSeparator.new())
	var output_title_hbox = HBoxContainer.new()
	var output_title = Label.new()
	output_title.text = "输出变量"
	output_title.add_theme_color_override("font_color", Color.CYAN)
	output_title.add_theme_font_size_override("font_size", 14)
	output_title_hbox.add_child(output_title)
	var add_output_btn = Button.new()
	add_output_btn.text = "+ 添加输出"
	add_output_btn.pressed.connect(_on_editor_add_output)
	output_title_hbox.add_child(add_output_btn)
	_editor_block_detail.add_child(output_title_hbox)
	_editor_outputs_container = VBoxContainer.new()
	_editor_outputs_container.add_theme_constant_override("separation", 4)
	_editor_block_detail.add_child(_editor_outputs_container)
	_refresh_editor_outputs()

func _refresh_editor_params():
	if not _editor_params_container: return
	for child in _editor_params_container.get_children():
		child.queue_free()
	var def = _get_editor_selected_def()
	if def.is_empty(): return
	for pi in range(def.params.size()):
		var p = def.params[pi]
		var param_frame = PanelContainer.new()
		_editor_params_container.add_child(param_frame)
		var param_vbox = VBoxContainer.new()
		param_vbox.add_theme_constant_override("separation", 2)
		param_frame.add_child(param_vbox)
		var row1 = HBoxContainer.new()
		param_vbox.add_child(row1)
		var p_name_label = Label.new()
		p_name_label.text = "名称:"
		p_name_label.custom_minimum_size = Vector2(40, 0)
		row1.add_child(p_name_label)
		var p_name_edit = LineEdit.new()
		p_name_edit.text = p.name
		p_name_edit.custom_minimum_size = Vector2(80, 0)
		p_name_edit.text_changed.connect(func(t): p.name = t.strip_edges(); _sync_main_panel())
		row1.add_child(p_name_edit)
		var p_type_label = Label.new()
		p_type_label.text = "类型:"
		p_type_label.custom_minimum_size = Vector2(40, 0)
		row1.add_child(p_type_label)
		var p_type_opt = OptionButton.new()
		var param_types = ["number", "string", "bool", "dropdown", "node", "vector2", "vector3", "color"]
		for pt in param_types:
			p_type_opt.add_item(pt)
		for pt_idx in range(param_types.size()):
			if param_types[pt_idx] == p.type:
				p_type_opt.select(pt_idx)
				break
		p_type_opt.item_selected.connect(func(idx):
			p.type = param_types[idx]
			if p.type == "dropdown" and not p.has("options"):
				p["options"] = []
			if p.type == "number": p.default = 0.0
			elif p.type == "bool": p.default = true
			elif p.type == "string": p.default = ""
			elif p.type == "node": p.default = ""
			elif p.type == "dropdown": p.default = "" if p.get("options", []).size() == 0 else str(p.options[0])
			elif p.type == "vector2": p.default = {"x": 0.0, "y": 0.0}
			elif p.type == "vector3": p.default = {"x": 0.0, "y": 0.0, "z": 0.0}
			elif p.type == "color": p.default = {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}
			_refresh_editor_params()
			_sync_main_panel()
		)
		row1.add_child(p_type_opt)
		var del_param_btn = Button.new()
		del_param_btn.text = "删除"
		del_param_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		del_param_btn.pressed.connect(_on_editor_del_param.bind(pi))
		row1.add_child(del_param_btn)
		var row2 = HBoxContainer.new()
		param_vbox.add_child(row2)
		var p_lbl_label = Label.new()
		p_lbl_label.text = "标签:"
		p_lbl_label.custom_minimum_size = Vector2(40, 0)
		row2.add_child(p_lbl_label)
		var p_lbl_edit = LineEdit.new()
		p_lbl_edit.text = p.label
		p_lbl_edit.custom_minimum_size = Vector2(80, 0)
		p_lbl_edit.text_changed.connect(func(t): p.label = t; _sync_main_panel())
		row2.add_child(p_lbl_edit)
		var p_def_label = Label.new()
		p_def_label.text = "默认:"
		p_def_label.custom_minimum_size = Vector2(40, 0)
		row2.add_child(p_def_label)
		if p.type == "number":
			var p_def_spin = SpinBox.new()
			p_def_spin.min_value = -INT_MAX
			p_def_spin.max_value = INT_MAX
			p_def_spin.step = 0.001
			p_def_spin.value = p.default
			p_def_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p_def_spin.value_changed.connect(func(v): p.default = v; _sync_main_panel())
			row2.add_child(p_def_spin)
		elif p.type == "bool":
			var p_def_check = CheckBox.new()
			p_def_check.button_pressed = p.default
			p_def_check.toggled.connect(func(v): p.default = v; _sync_main_panel())
			row2.add_child(p_def_check)
		elif p.type == "vector2":
			if not p.default is Dictionary: p.default = {"x": 0.0, "y": 0.0}
			var x_label = Label.new()
			x_label.text = "X:"
			row2.add_child(x_label)
			var x_spin = SpinBox.new()
			x_spin.min_value = -INT_MAX
			x_spin.max_value = INT_MAX
			x_spin.step = 0.001
			x_spin.value = p.default.get("x", 0.0)
			x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			x_spin.value_changed.connect(func(v): p.default["x"] = v; _sync_main_panel())
			row2.add_child(x_spin)
			var y_label = Label.new()
			y_label.text = "Y:"
			row2.add_child(y_label)
			var y_spin = SpinBox.new()
			y_spin.min_value = -INT_MAX
			y_spin.max_value = INT_MAX
			y_spin.step = 0.001
			y_spin.value = p.default.get("y", 0.0)
			y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			y_spin.value_changed.connect(func(v): p.default["y"] = v; _sync_main_panel())
			row2.add_child(y_spin)
		elif p.type == "vector3":
			if not p.default is Dictionary: p.default = {"x": 0.0, "y": 0.0, "z": 0.0}
			var x_label = Label.new()
			x_label.text = "X:"
			row2.add_child(x_label)
			var x_spin = SpinBox.new()
			x_spin.min_value = -INT_MAX
			x_spin.max_value = INT_MAX
			x_spin.step = 0.001
			x_spin.value = p.default.get("x", 0.0)
			x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			x_spin.value_changed.connect(func(v): p.default["x"] = v; _sync_main_panel())
			row2.add_child(x_spin)
			var y_label = Label.new()
			y_label.text = "Y:"
			row2.add_child(y_label)
			var y_spin = SpinBox.new()
			y_spin.min_value = -INT_MAX
			y_spin.max_value = INT_MAX
			y_spin.step = 0.001
			y_spin.value = p.default.get("y", 0.0)
			y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			y_spin.value_changed.connect(func(v): p.default["y"] = v; _sync_main_panel())
			row2.add_child(y_spin)
			var z_label = Label.new()
			z_label.text = "Z:"
			row2.add_child(z_label)
			var z_spin = SpinBox.new()
			z_spin.min_value = -INT_MAX
			z_spin.max_value = INT_MAX
			z_spin.step = 0.001
			z_spin.value = p.default.get("z", 0.0)
			z_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			z_spin.value_changed.connect(func(v): p.default["z"] = v; _sync_main_panel())
			row2.add_child(z_spin)
		elif p.type == "color":
			if not p.default is Dictionary:
				p.default = {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}
			var cp = ColorPickerButton.new()
			cp.color = Color(p.default.get("r", 1.0), p.default.get("g", 1.0), p.default.get("b", 1.0), p.default.get("a", 1.0))
			cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cp.custom_minimum_size = Vector2(80, 0)
			cp.get_popup().exclusive = true
			cp.color_changed.connect(func(c: Color):
				p.default = {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
				_sync_main_panel()
			)
			row2.add_child(cp)
		else:
			var p_def_edit = LineEdit.new()
			p_def_edit.text = str(p.default)
			p_def_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p_def_edit.text_changed.connect(func(t):
				if p.type == "number": p.default = t.to_float()
				else: p.default = t
				_sync_main_panel()
			)
			row2.add_child(p_def_edit)
		if p.type == "dropdown":
			var row3 = HBoxContainer.new()
			param_vbox.add_child(row3)
			var p_opt_label = Label.new()
			p_opt_label.text = "选项:"
			p_opt_label.custom_minimum_size = Vector2(40, 0)
			row3.add_child(p_opt_label)
			var p_opt_edit = LineEdit.new()
			var options = p.get("options", [])
			p_opt_edit.text = ",".join(options)
			p_opt_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p_opt_edit.placeholder_text = "用逗号分隔选项，如: linear,ease_in,ease_out"
			p_opt_edit.text_changed.connect(func(t):
				var new_options = []
				for opt in t.split(",", false):
					new_options.append(opt.strip_edges())
				p["options"] = new_options
				if new_options.size() > 0 and str(p.default) not in new_options:
					p.default = new_options[0]
				_sync_main_panel()
			)
			row3.add_child(p_opt_edit)

func _on_editor_add_param():
	var def = _get_editor_selected_def()
	if def.is_empty(): return
	def.params.append({"name": "param_%d" % (def.params.size() + 1), "type": "number", "default": 0, "label": "参数"})
	_refresh_editor_params()
	_sync_main_panel()

func _on_editor_del_param(param_idx: int):
	var def = _get_editor_selected_def()
	if def.is_empty(): return
	if param_idx >= 0 and param_idx < def.params.size():
		def.params.remove_at(param_idx)
	_refresh_editor_params()
	_sync_main_panel()

func _refresh_editor_outputs():
	if not _editor_outputs_container: return
	for child in _editor_outputs_container.get_children():
		child.queue_free()
	var def = _get_editor_selected_def()
	if def.is_empty(): return
	var outputs = _ensure_outputs(def)
	for oi in range(outputs.size()):
		var o = outputs[oi]
		var output_frame = PanelContainer.new()
		_editor_outputs_container.add_child(output_frame)
		var output_vbox = VBoxContainer.new()
		output_vbox.add_theme_constant_override("separation", 2)
		output_frame.add_child(output_vbox)
		var row1 = HBoxContainer.new()
		output_vbox.add_child(row1)
		var o_name_label = Label.new()
		o_name_label.text = "名称:"
		o_name_label.custom_minimum_size = Vector2(40, 0)
		row1.add_child(o_name_label)
		var o_name_edit = LineEdit.new()
		o_name_edit.text = o.name
		o_name_edit.custom_minimum_size = Vector2(80, 0)
		o_name_edit.text_changed.connect(func(t): o.name = t.strip_edges(); _sync_main_panel())
		row1.add_child(o_name_edit)
		var o_type_label = Label.new()
		o_type_label.text = "类型:"
		o_type_label.custom_minimum_size = Vector2(40, 0)
		row1.add_child(o_type_label)
		var o_type_opt = OptionButton.new()
		var output_types = ["number", "string", "bool", "node", "vector2", "vector3"]
		for ot in output_types:
			o_type_opt.add_item(ot)
		for ot_idx in range(output_types.size()):
			if output_types[ot_idx] == o.type:
				o_type_opt.select(ot_idx)
				break
		o_type_opt.item_selected.connect(func(idx):
			o.type = output_types[idx]
			_refresh_editor_outputs()
			_sync_main_panel()
		)
		row1.add_child(o_type_opt)
		var del_output_btn = Button.new()
		del_output_btn.text = "删除"
		del_output_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		del_output_btn.pressed.connect(_on_editor_del_output.bind(oi))
		row1.add_child(del_output_btn)
		var row2 = HBoxContainer.new()
		output_vbox.add_child(row2)
		var o_lbl_label = Label.new()
		o_lbl_label.text = "标签:"
		o_lbl_label.custom_minimum_size = Vector2(40, 0)
		row2.add_child(o_lbl_label)
		var o_lbl_edit = LineEdit.new()
		o_lbl_edit.text = o.label
		o_lbl_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		o_lbl_edit.text_changed.connect(func(t): o.label = t; _sync_main_panel())
		row2.add_child(o_lbl_edit)

func _on_editor_add_output():
	var def = _get_editor_selected_def()
	if def.is_empty(): return
	if not def.has("outputs"):
		def["outputs"] = []
	def.outputs.append({"name": "output_%d" % (def.outputs.size() + 1), "type": "node", "label": "输出"})
	_refresh_editor_outputs()
	_sync_main_panel()

func _on_editor_del_output(output_idx: int):
	var def = _get_editor_selected_def()
	if def.is_empty(): return
	var outputs = _ensure_outputs(def)
	if output_idx >= 0 and output_idx < outputs.size():
		outputs.remove_at(output_idx)
	_refresh_editor_outputs()
	_sync_main_panel()

func _on_editor_dialog_closed():
	_is_editing_block_defs = false
	_refresh_all_block_nodes()

func _on_editor_custom_action(action: StringName):
	if action == "save_defs":
		_on_editor_save_defs()
	elif action == "reset_defs":
		_on_editor_reset_defs()

func _on_editor_save_defs():
	_save_block_defs()

func _on_editor_reset_defs():
	_block_defs = _get_default_block_defs()
	_category_colors = {
		"事件": Color(0.96, 0.75, 0.15),
		"动作": Color(0.25, 0.58, 0.85),
		"条件": Color(0.58, 0.25, 0.82),
		"值": Color(0.35, 0.78, 0.38),
	}
	_rebuild_categories_from_defs()
	_refresh_editor_cat_list()
	_sync_main_panel()

func _sync_main_panel():
	_rebuild_categories_from_defs()
	_category_list.clear()
	for cat in _categories:
		_category_list.add_item(cat)
	if _current_category not in _categories:
		if _categories.size() > 0:
			_current_category = _categories[0]
			_category_list.select(0)
		else:
			_current_category = ""
	else:
		for i in range(_categories.size()):
			if _categories[i] == _current_category:
				_category_list.select(i)
				break
	_refresh_block_list()
	_refresh_all_block_nodes()

func setup(entity_instance: Node, scene_path: String):
	_entity_instance = entity_instance
	_entity_scene_path = scene_path
	# 分步加载（带进度条），避免瞬间操作崩溃
	_load_script_data()

func _on_close_requested():
	if _dirty:
		_show_save_on_close_dialog()
	else:
		hide()

func _show_save_on_close_dialog():
	var dialog = ConfirmationDialog.new()
	dialog.title = "未保存的更改"
	dialog.dialog_text = "是否保存对脚本的更改？\n如果不保存，更改将丢失。"
	dialog.ok_button_text = "保存"
	dialog.cancel_button_text = "取消"
	dialog.add_button("不保存", false, "discard")
	dialog.min_size = Vector2(400, 150)
	add_child(dialog)

	dialog.confirmed.connect(func():
		_save_script()
		dialog.queue_free()
		hide()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	dialog.custom_action.connect(func(action: String):
		if action == "discard":
			dialog.queue_free()
			hide()
	)
	dialog.popup_centered()

# ============================================
# 分类颜色
# ============================================
func _get_block_color(block: Dictionary) -> Color:
	if block.get("is_var_ref", false):
		var source_block = _get_block_by_id(block.get("source_block_id", -1))
		if not source_block.is_empty():
			var cat = source_block.def.category
			if _category_colors.has(cat): return _category_colors[cat]
		return _get_output_color(block.get("output_type", ""))
	var cat = block.def.category
	if _category_colors.has(cat): return _category_colors[cat]
	return Color.GRAY

func _get_block_dark_color(block: Dictionary) -> Color:
	var c = _get_block_color(block)
	return Color(c.r * 0.85, c.g * 0.85, c.b * 0.85)

# ============================================
# 撤销/重做系统
# ============================================
func _save_undo_state():
	var state = _serialize_block_state()
	if _undo_index < _undo_stack.size() - 1:
		_undo_stack = _undo_stack.slice(0, _undo_index + 1)
	_undo_stack.append(state)
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()
	else:
		_undo_index += 1
	_mark_dirty()
	_update_undo_redo_buttons()

func _undo():
	if _undo_index < 0: return
	_restore_block_state(_undo_stack[_undo_index])
	_undo_index -= 1
	_mark_dirty()
	_update_undo_redo_buttons()

func _redo():
	if _undo_index >= _undo_stack.size() - 1: return
	_undo_index += 1
	_restore_block_state(_undo_stack[_undo_index])
	_mark_dirty()
	_update_undo_redo_buttons()

func _update_undo_redo_buttons():
	if _undo_btn:
		_undo_btn.disabled = (_undo_index < 0)
	if _redo_btn:
		_redo_btn.disabled = (_undo_index >= _undo_stack.size() - 1)
	if _event_undo_btn:
		_event_undo_btn.disabled = (_undo_index < 0)
	if _event_redo_btn:
		_event_redo_btn.disabled = (_undo_index >= _undo_stack.size() - 1)

func _serialize_block_state() -> Dictionary:
	var blocks_arr = []
	for b in _blocks:
		blocks_arr.append({
			"id": b.id,
			"def_name": b.def.name,
			"pos": {"x": b.pos.x, "y": b.pos.y},
			"params": b.params.duplicate(true),
			"value_slots": b.value_slots.duplicate(true),
			"inner_block_ids": b.inner_block_ids.duplicate(true),
			"inner_else_ids": b.inner_else_ids.duplicate(true),
			"output_refs": b.output_refs.duplicate(true),
			"is_var_ref": b.get("is_var_ref", false),
			"source_block_id": b.get("source_block_id", -1),
			"output_name": b.get("output_name", ""),
			"output_type": b.get("output_type", ""),
			"output_label": b.get("output_label", ""),
			"stack_below_id": b.get("stack_below_id", -1),
		})
	return {
		"blocks": blocks_arr,
		"events": _events_data.duplicate(true),
	}

func _restore_block_state(state: Dictionary):
	# ---- 恢复积木画布 ----
	var blocks_arr = state.get("blocks", [])
	for bid in _block_nodes.keys():
		_remove_block_node(bid)
	_blocks.clear()
	_blocks_by_id.clear()
	_slot_block_ids.clear()
	_inner_block_ids_set.clear()
	_selected_block_id = -1
	for s in blocks_arr:
		var def = _find_block_def(s.def_name)
		#if def.is_empty():
			#if s.get("is_var_ref", false):
				#var out_label = s.get("output_label", s.get("output_name", ""))
				#def = {
					#"type": BlockType.VALUE,
					#"name": "_var_ref_%s" % s.get("output_name", ""),
					#"label": "◆ %s" % out_label,
					#"category": "值",
					#"params": [],
					#"outputs": [],
				#}
			#else:
				#continue
		var block = {
			"id": s.id,
			"def": def,
			"pos": Vector2(s.pos.x, s.pos.y),
			"params": s.params.duplicate(true),
			"value_slots": s.value_slots.duplicate(true),
			"inner_block_ids": s.inner_block_ids.duplicate(true),
			"inner_else_ids": s.inner_else_ids.duplicate(true),
			"output_refs": s.get("output_refs", {}).duplicate(true),
			"is_var_ref": s.get("is_var_ref", false),
			"source_block_id": s.get("source_block_id", -1),
			"output_name": s.get("output_name", ""),
			"output_type": s.get("output_type", ""),
			"output_label": s.get("output_label", ""),
			"stack_below_id": s.get("stack_below_id", -1),
		}
		_blocks.append(block)
		_blocks_by_id[block.id] = block
		for pname in block.value_slots:
			var vid = block.value_slots[pname]
			if vid >= 0: _slot_block_ids[vid] = true
		for iid in block.inner_block_ids + block.inner_else_ids:
			_inner_block_ids_set[iid] = true
	var max_id = 0
	for b in _blocks:
		if b.id > max_id: max_id = b.id
	_block_id_counter = max_id + 1
	_relayout_all_conditions()
	for block in _blocks:
		if not _is_block_in_slot(block.id):
			_create_block_node(block)
	_update_all_z_indices()
	# ---- 恢复事件表 ----
	if state.has("events"):
		_events_data = state["events"].duplicate(true)
		_selected_event_row_id = -1
		if _current_mode == EditorMode.EVENT:
			_render_events()
			_update_event_prop_panel()
	_update_prop_panel()

# ============================================
# 保存/加载块定义
# ============================================
func _get_default_block_defs() -> Array:
	return [
		{"type": BlockType.EVENT, "name": "on_game_start", "label": "当游戏开始", "category": "事件", "params": []},
		{"type": BlockType.EVENT, "name": "on_animation_playing", "label": "当动画播放 {anim_name}", "category": "事件", "params": [{"name": "anim_name", "type": "string", "default": "idle", "label": "动画名"}]},
		{"type": BlockType.EVENT, "name": "on_hit", "label": "当被攻击命中", "category": "事件", "params": [], "outputs": [{"name": "attacker", "type": "node", "label": "攻击者"}]},
		{"type": BlockType.EVENT, "name": "when_modifier_start", "label": "当自定义效果 {mod_type} 启动时", "category": "事件", "params": [{"name": "mod_type", "type": "string", "default": "", "label": "效果类型"}], "outputs": [{"name": "target", "type": "node", "label": "目标"}, {"name": "mod_type", "type": "node", "label": "效果类型"}, {"name": "mod_power", "type": "node", "label": "强度"}]},
		{"type": BlockType.EVENT, "name": "when_modifier_update", "label": "当自定义效果 {mod_type} 持续中", "category": "事件", "params": [{"name": "mod_type", "type": "string", "default": "", "label": "效果类型"}, {"name": "interval", "type": "number", "default": 0.0, "label": "间隔(秒)"}], "outputs": [{"name": "target", "type": "node", "label": "目标"}, {"name": "mod_type", "type": "node", "label": "效果类型"}, {"name": "mod_power", "type": "node", "label": "强度"}]},
		{"type": BlockType.EVENT, "name": "when_modifier_end", "label": "当自定义效果 {mod_type} 结束时", "category": "事件", "params": [{"name": "mod_type", "type": "string", "default": "", "label": "效果类型"}], "outputs": [{"name": "target", "type": "node", "label": "目标"}, {"name": "mod_type", "type": "node", "label": "效果类型"}, {"name": "mod_power", "type": "node", "label": "强度"}]},
		{"type": BlockType.ACTION, "name": "play_animation", "label": "播放动画 {anim_name}", "category": "动作", "params": [{"name": "anim_name", "type": "string", "default": "idle", "label": "动画名"}]},
		{"type": BlockType.ACTION, "name": "move_by", "label": "移动 X:{dx} Y:{dy}", "category": "动作", "params": [{"name": "dx", "type": "number", "default": 0, "label": "X偏移"}, {"name": "dy", "type": "number", "default": 0, "label": "Y偏移"}]},
		{"type": BlockType.ACTION, "name": "set_velocity", "label": "设置速度 VX:{vx} VY:{vy}", "category": "动作", "params": [{"name": "vx", "type": "number", "default": 0, "label": "X速度"}, {"name": "vy", "type": "number", "default": 0, "label": "Y速度"}]},
		{"type": BlockType.ACTION, "name": "wait", "label": "等待 {duration} 秒", "category": "动作", "params": [{"name": "duration", "type": "number", "default": 1.0, "label": "秒数"}]},
		{"type": BlockType.ACTION, "name": "set_variable", "label": "设置 {var_name} = {value}", "category": "动作", "params": [{"name": "var_name", "type": "string", "default": "my_var", "label": "变量名"}, {"name": "value", "type": "number", "default": 0, "label": "值"}]},
		{"type": BlockType.CONDITION, "name": "if_condition", "label": "如果 {condition}", "category": "条件", "params": [{"name": "condition", "type": "bool", "default": true, "label": "条件"}]},
		{"type": BlockType.CONDITION, "name": "if_else", "label": "如果 {condition}", "category": "条件", "hide_in_event": true, "params": [{"name": "condition", "type": "bool", "default": true, "label": "条件"}]},
		{"type": BlockType.CONDITION, "name": "else_if", "label": "否则如果 {condition}", "category": "条件", "event_only": true, "params": [{"name": "condition", "type": "bool", "default": true, "label": "条件"}]},
		{"type": BlockType.CONDITION, "name": "else_block", "label": "否则", "category": "条件", "event_only": true, "params": []},
		{"type": BlockType.VALUE, "name": "number_value", "label": "{value}", "category": "值", "params": [{"name": "value", "type": "number", "default": 0, "label": "数值"}]},
		{"type": BlockType.VALUE, "name": "compare", "label": "{left} {op} {right}", "category": "值", "params": [{"name": "left", "type": "number", "default": "0", "label": "左"}, {"name": "op", "type": "dropdown", "default": ">", "label": "运算", "options": ["<", "=", ">"]}, {"name": "right", "type": "number", "default": "0", "label": "右"}]},
	]

func _save_block_defs():
	var data = {
		"categories": _categories,
		"category_colors": {},
		"block_defs": [],
	}
	for cat in _category_colors:
		data.category_colors[cat] = _category_colors[cat].to_html()
	for def in _block_defs:
		var d = def.duplicate(true)
		data.block_defs.append(d)
	var file = FileAccess.open(BLOCK_DEFS_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func _load_block_defs() -> bool:
	if not FileAccess.file_exists(BLOCK_DEFS_SAVE_PATH): return false
	var file = FileAccess.open(BLOCK_DEFS_SAVE_PATH, FileAccess.READ)
	if not file: return false
	var json_str = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_str) != OK: return false
	var data = json.data
	if not data is Dictionary: return false
	_categories = data.get("categories", [])
	_category_colors = {}
	var colors = data.get("category_colors", {})
	for cat in colors:
		_category_colors[cat] = Color.from_string(colors[cat], Color.GRAY)
	_block_defs = data.get("block_defs", [])
	# 迁移：确保 else_if / else_block / if_else 标记存在
	_vs_migrate_block_defs()
	return true

## 补全 else_if / else_block，给 if_else 加 hide_in_event
func _vs_migrate_block_defs():
	var has_else_if = false
	var has_else_block = false
	for def in _block_defs:
		if def.name == "if_else" and not def.has("hide_in_event"):
			def["hide_in_event"] = true
		if def.name == "else_if":
			has_else_if = true
		if def.name == "else_block":
			has_else_block = true
	if not has_else_if:
		_block_defs.append({
			"type": BlockType.CONDITION, "name": "else_if",
			"label": "否则如果 {condition}", "category": "控制",
			"event_only": true,
			"params": [{"name": "condition", "type": "bool", "default": true, "label": "条件"}]
		})
	if not has_else_block:
		_block_defs.append({
			"type": BlockType.CONDITION, "name": "else_block",
			"label": "否则", "category": "控制",
			"event_only": true,
			"params": []
		})
