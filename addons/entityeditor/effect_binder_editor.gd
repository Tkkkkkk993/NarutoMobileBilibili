# effect_binder_editor.gd
# 特效绑定器 — 选中动画后添加特效，带时间轴与预览播放
@tool
extends Window

const ANIM_FPS := 60.0

# ==========================================
# 数据
# ==========================================
var _bindings: Array = []
var _selected_anim: String = ""        # 当前选中的动画
var _selected_binding_id: String = ""  # 当前选中的特效绑定
var _entity_scene_path: String = ""
var _has_unsaved_changes: bool = false
var _entity_instance: Node = null
var _anim_entity: EntityBase = null
var _is_anim_player_entity: bool = false
var _available_effects: Array = []

# 预览播放
var _is_playing: bool = false
var _play_frame: int = 0
var _play_timer: float = 0.0
var _preview_effects: Array = []   # 预览时生成的特效实例
var _main_hbox: HBoxContainer       # 上部分左中右容器
var _effect_popup_btn: Button       # 特效选择按钮
var _save_btn: Button               # 保存按钮

# 存储原始 AnimatedSprite2D 的 scale（在 setup 时获取，用于编辑器预览时补偿缩放差异）
var _sprite_scale: Vector2 = Vector2.ONE

# ==========================================
# 画布
# ==========================================
var preview_root_position: Vector2 = Vector2(300, 300)
var _canvas_zoom: float = 1.0
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _pan_start_mouse_pos: Vector2 = Vector2.ZERO
var _pan_start_offset: Vector2 = Vector2.ZERO

# ==========================================
# UI 引用
# ==========================================
var _anim_select: OptionButton
var _effect_list: ItemList
var _canvas: Control
var _draw_node: Node2D
var _interaction_layer: Control
var _preview_sprite: AnimatedSprite2D
var _timeline: Control

var _effect_name_input: LineEdit
var _scene_path_input: LineEdit
var _frame_spin: SpinBox       # 当前预览帧（左侧，只读预览）
var _bind_frame_spin: SpinBox  # 选中特效的绑定帧（右侧，可编辑）
var _pos_x_spin: SpinBox
var _pos_y_spin: SpinBox
var _z_offset_spin: SpinBox  # 相对深度偏移
var _scale_x_spin: SpinBox
var _scale_y_spin: SpinBox
var _rotation_spin: SpinBox
var _follow_entity_check: CheckBox
var _follow_facing_check: CheckBox
var _flip_h_check: CheckBox
var _auto_flip_facing_check: CheckBox

var _play_btn: Button
var _stop_btn: Button
var _frame_label: Label

var _ui_built: bool = false
var _panel_updating: bool = false  # 防抖：面板更新期间屏蔽信号回调

# ==========================================
# 初始化
# ==========================================
func _ready():
	size = Vector2(1200, 850)
	min_size = Vector2(900, 700)
	_update_title()


func _update_title():
	var base = "特效绑定器"
	if _entity_scene_path != "":
		var trimmed = _entity_scene_path.trim_prefix("res://assets/entities/")
		var last_slash = trimmed.rfind("/")
		var name = trimmed.substr(0, last_slash) if last_slash >= 0 else trimmed
		base += " - " + name
	title = base


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
	
	# AnimatedSprite2DEntity: visual_node 是 AnimatedSprite2D
	if visual_node is AnimatedSprite2D:
		_sprite_scale = (visual_node as AnimatedSprite2D).scale
	
	if not _ui_built:
		_build_ui()
		_ui_built = true
	
	close_requested.connect(_on_close_requested, CONNECT_ONE_SHOT)
	
	_scan_available_effects()
	_load_existing_data()
	_setup_entity_preview()
	_populate_anim_list()
	
	if _anim_select.item_count > 0:
		_anim_select.select(0)
		_on_anim_selected(0)
	
	popup_centered()

func _process(delta):
	if _is_playing:
		if _is_anim_player_entity:
			_play_timer += delta
			var total_frames = _get_anim_frame_count(_selected_anim)
			if total_frames <= 0:
				_stop_preview()
				return
			var fd = 1.0 / 15.0  # 默认帧率
			if _play_timer >= fd:
				_play_timer = 0
				_play_frame += 1
				if _play_frame >= total_frames:
					_stop_preview()
					return
				_set_preview_frame(_selected_anim, _play_frame)
				_frame_spin.value = _play_frame
				_update_frame_label()
				_timeline.queue_redraw()
				_show_preview_effects_at_frame(_play_frame)
		elif _preview_sprite and _preview_sprite.sprite_frames:
			_play_timer += delta
			var total_frames = _preview_sprite.sprite_frames.get_frame_count(_selected_anim)
			var fd = _preview_sprite.sprite_frames.get_frame_duration(_selected_anim, _play_frame)
			var anim_fps = _preview_sprite.sprite_frames.get_animation_speed(_selected_anim)
			if anim_fps <= 0: anim_fps = 5.0
			fd /= anim_fps
			if fd <= 0:
				fd = 1.0 / 15.0
			if _play_timer >= fd:
				_play_timer = 0
				_play_frame += 1
				if _play_frame >= total_frames:
					_stop_preview()
					return
				_preview_sprite.frame = _play_frame
				_frame_spin.value = _play_frame
				_update_frame_label()
				_timeline.queue_redraw()
				_show_preview_effects_at_frame(_play_frame)

# ==========================================
# 动画抽象接口（兼容 AnimatedSprite2D 和 AnimationPlayer）
# ==========================================
func _get_anim_names() -> PackedStringArray:
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap:
			var names = ap.get_animation_list()
			print("[effect_binder] _get_anim_names: AnimationPlayer, anims=%s" % [str(names)])
			return names
	if _preview_sprite and _preview_sprite.sprite_frames:
		var names = _preview_sprite.sprite_frames.get_animation_names()
		print("[effect_binder] _get_anim_names: AnimatedSprite2D, anims=%s" % [str(names)])
		return names
	print("[effect_binder] _get_anim_names: empty")
	return PackedStringArray()

func _get_anim_frame_count(anim_name: String) -> int:
	var preview = _canvas.get_node_or_null("EntityPreview")
	if preview:
		var ap = _find_animation_player(preview)
		if ap and ap.has_animation(anim_name):
			var anim = ap.get_animation(anim_name)
			var count = int(anim.length * ANIM_FPS)
			print("[effect_binder] _get_anim_frame_count(%s) = %d" % [anim_name, count])
			return count
	if _preview_sprite and _preview_sprite.sprite_frames:
		var count = _preview_sprite.sprite_frames.get_frame_count(anim_name)
		print("[effect_binder] _get_anim_frame_count(%s) = %d (sprite)" % [anim_name, count])
		return count
	print("[effect_binder] _get_anim_frame_count(%s) = 0 (fallback)" % anim_name)
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
				print("[effect_binder] _set_preview_frame(%s, %d): seek OK" % [anim_name, frame_idx])
			else:
				print("[effect_binder] _set_preview_frame(%s, %d): anim not found" % [anim_name, frame_idx])
			return
		print("[effect_binder] _set_preview_frame(%s, %d): no AnimationPlayer, fallback sprite" % [anim_name, frame_idx])
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
# UI 构建
# ==========================================
func _build_ui():
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 4)
	main_vbox.offset_left = 8
	main_vbox.offset_top = 8
	main_vbox.offset_right = -8
	main_vbox.offset_bottom = -8
	add_child(main_vbox)

	# ---- 上部分：左-中-右 ----
	var top_hbox = HBoxContainer.new()
	top_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_hbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(top_hbox)

	# 左侧：动画列表 + 播放按钮 + 当前动画特效列表
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size.x = 200
	top_hbox.add_child(left_vbox)

	left_vbox.add_child(_mk_label("选择动画", 14))
	_anim_select = OptionButton.new()
	_anim_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_select.item_selected.connect(_on_anim_selected)
	left_vbox.add_child(_anim_select)

	# 当前帧（仅预览时显示）
	_frame_spin = SpinBox.new()
	_frame_spin.min_value = 0
	_frame_spin.max_value = 0
	_frame_spin.step = 1
	_frame_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_spin.value_changed.connect(_on_frame_spin_changed)
	_frame_spin.visible = false
	left_vbox.add_child(_frame_spin)

	var play_hbox = HBoxContainer.new()
	left_vbox.add_child(play_hbox)
	_play_btn = Button.new()
	_play_btn.text = "▶ 播放预览"
	_play_btn.pressed.connect(_on_play_pressed)
	play_hbox.add_child(_play_btn)
	_stop_btn = Button.new()
	_stop_btn.text = "■ 停止"
	_stop_btn.pressed.connect(_on_stop_pressed)
	play_hbox.add_child(_stop_btn)

	left_vbox.add_child(_mk_label("当前动画的特效绑定", 12))
	_effect_list = ItemList.new()
	_effect_list.size_flags_vertical = 3
	_effect_list.item_selected.connect(_on_effect_selected)
	left_vbox.add_child(_effect_list)

	var effect_btn_hbox = HBoxContainer.new()
	left_vbox.add_child(effect_btn_hbox)
	var add_btn = Button.new()
	add_btn.text = "添加特效到当前帧"
	add_btn.pressed.connect(_on_add_binding)
	effect_btn_hbox.add_child(add_btn)
	var del_btn = Button.new()
	del_btn.text = "删除"
	del_btn.pressed.connect(_on_del_binding)
	effect_btn_hbox.add_child(del_btn)

	# 中间画布
	var center_vbox = VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(center_vbox)

	center_vbox.add_child(_mk_label("画布 (左键拖拽 | 中键平移 | 滚轮缩放)", 11))
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	center_vbox.add_child(_canvas)

	_draw_node = Node2D.new()
	_draw_node.z_index = 100
	_draw_node.z_as_relative = false
	_draw_node.draw.connect(_on_canvas_draw)
	_canvas.add_child(_draw_node)

	_interaction_layer = ColorRect.new()
	_interaction_layer.color = Color(0, 0, 0, 0)
	_interaction_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_interaction_layer.z_index = 101
	_interaction_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_interaction_layer.gui_input.connect(_on_interaction_input)
	_canvas.add_child(_interaction_layer)

	# 右侧属性面板
	var right_vbox = VBoxContainer.new()
	right_vbox.custom_minimum_size.x = 220
	top_hbox.add_child(right_vbox)

	right_vbox.add_child(_mk_label("特效属性", 15))
	
	right_vbox.add_child(_mk_label("特效名称:", 11))
	_effect_name_input = LineEdit.new()
	_effect_name_input.placeholder_text = "注册名..."
	_effect_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effect_name_input.text_changed.connect(_on_prop_changed)
	right_vbox.add_child(_effect_name_input)

	right_vbox.add_child(_mk_label("场景路径:", 11))
	_scene_path_input = LineEdit.new()
	_scene_path_input.placeholder_text = "或 .tscn 路径..."
	_scene_path_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_path_input.text_changed.connect(_on_prop_changed)
	right_vbox.add_child(_scene_path_input)

	var popup_btn = Button.new()
	popup_btn.text = "从扫描选择特效"
	popup_btn.pressed.connect(_on_show_effect_popup.bind(popup_btn))
	right_vbox.add_child(popup_btn)

	right_vbox.add_child(_mk_hsep())
	right_vbox.add_child(_mk_label("特效绑定的帧", 11))
	_bind_frame_spin = SpinBox.new()
	_bind_frame_spin.min_value = 0
	_bind_frame_spin.max_value = 0
	_bind_frame_spin.step = 1
	_bind_frame_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bind_frame_spin.value_changed.connect(_on_bind_frame_changed)
	right_vbox.add_child(_bind_frame_spin)

	right_vbox.add_child(_mk_hsep())
	right_vbox.add_child(_mk_label("位置 (相对实体中心)", 11))
	_pos_x_spin = _mk_spinbox("X:", -999999, 999999, 1.0, right_vbox)
	_pos_y_spin = _mk_spinbox("Y:", -999999, 999999, 1.0, right_vbox)
	_pos_x_spin.value_changed.connect(_on_prop_changed)
	_pos_y_spin.value_changed.connect(_on_prop_changed)

	right_vbox.add_child(_mk_hsep())
	right_vbox.add_child(_mk_label("相对深度（Z偏移）", 11))
	_z_offset_spin = _mk_spinbox("Z:", -999999, 999999, 1.0, right_vbox)
	_z_offset_spin.value_changed.connect(_on_prop_changed)

	right_vbox.add_child(_mk_hsep())
	right_vbox.add_child(_mk_label("大小（缩放）", 11))
	_scale_x_spin = _mk_spinbox("W:", 0.001, 999999, 0.1, right_vbox)
	_scale_y_spin = _mk_spinbox("H:", 0.001, 999999, 0.1, right_vbox)
	_scale_x_spin.value = 1.0
	_scale_y_spin.value = 1.0
	_scale_x_spin.value_changed.connect(_on_prop_changed)
	_scale_y_spin.value_changed.connect(_on_prop_changed)

	right_vbox.add_child(_mk_hsep())
	right_vbox.add_child(_mk_label("旋转（度）", 11))
	_rotation_spin = _mk_spinbox("R:", -999999, 999999, 1.0, right_vbox)
	_rotation_spin.value_changed.connect(_on_prop_changed)

	right_vbox.add_child(_mk_hsep())
	_follow_entity_check = CheckBox.new()
	_follow_entity_check.text = "跟随实体移动"
	_follow_entity_check.toggled.connect(_on_prop_changed)
	right_vbox.add_child(_follow_entity_check)

	_follow_facing_check = CheckBox.new()
	_follow_facing_check.text = "跟随实体朝向"
	_follow_facing_check.toggled.connect(_on_prop_changed)
	right_vbox.add_child(_follow_facing_check)

	_flip_h_check = CheckBox.new()
	_flip_h_check.text = "初始水平翻转"
	_flip_h_check.toggled.connect(_on_prop_changed)
	right_vbox.add_child(_flip_h_check)

	_auto_flip_facing_check = CheckBox.new()
	_auto_flip_facing_check.text = "根据朝向翻转特效"
	_auto_flip_facing_check.toggled.connect(_on_prop_changed)
	right_vbox.add_child(_auto_flip_facing_check)

	right_vbox.add_child(_mk_hsep())
	var save_btn = Button.new()
	save_btn.text = "保存数据 (Ctrl+S)"
	save_btn.pressed.connect(_on_save_data)
	save_btn.add_theme_color_override("font_color", Color.CYAN)
	right_vbox.add_child(save_btn)

	# ---- 下部分：时间轴 ----
	_timeline = Control.new()
	_timeline.custom_minimum_size.y = 50
	_timeline.draw.connect(_on_timeline_draw)
	_timeline.gui_input.connect(_on_timeline_input)
	main_vbox.add_child(_timeline)

	_frame_label = Label.new()
	_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_frame_label.add_theme_font_size_override("font_size", 11)
	main_vbox.add_child(_frame_label)

# ==========================================
# 动画列表
# ==========================================
func _populate_anim_list():
	if not _anim_select: return
	_anim_select.clear()
	var anims = _get_anim_names()
	if anims.is_empty(): return
	for a in anims:
		_anim_select.add_item(a)

func _on_anim_selected(index: int):
	if index < 0: return
	_selected_anim = _anim_select.get_item_text(index)
	var total = _get_anim_frame_count(_selected_anim)
	print("[effect_binder] _on_anim_selected: anim=%s, total_frames=%d" % [_selected_anim, total])
	_selected_binding_id = ""
	_stop_preview()
	_clear_preview_effects()  # 切换动画时清除旧特效
	
	# 更新预览
	if _is_anim_player_entity:
		_set_preview_frame(_selected_anim, 0)
		var max_f = max(0, total - 1)
		_frame_spin.max_value = max_f
		_frame_spin.value = 0
		_bind_frame_spin.max_value = max_f
		_play_frame = 0
	elif _preview_sprite and _preview_sprite.sprite_frames.has_animation(_selected_anim):
		var max_f = max(0, _preview_sprite.sprite_frames.get_frame_count(_selected_anim) - 1)
		_frame_spin.max_value = max_f
		_frame_spin.value = 0
		_bind_frame_spin.max_value = max_f
		_preview_sprite.stop()
		_preview_sprite.animation = _selected_anim
		_preview_sprite.frame = 0
		_play_frame = 0
	
	_refresh_effect_list()
	_update_frame_label()
	_update_panel({})
	_timeline.queue_redraw()
	_draw_node.queue_redraw()

# ==========================================
# 特效列表（当前动画的绑定）
# ==========================================
func _get_bindings_for_anim(anim_name: String) -> Array:
	var result = []
	for b in _bindings:
		if b.get("anim", "") == anim_name:
			result.append(b)
	# 按帧排序
	result.sort_custom(func(a, b): return a.get("frame", 0) < b.get("frame", 0))
	return result

func _refresh_effect_list_keep_selection():
	if not _effect_list: return
	var sel_id = _selected_binding_id
	_refresh_effect_list()
	if sel_id != "":
		for i in range(_effect_list.item_count):
			if _effect_list.get_item_metadata(i) == sel_id:
				_effect_list.select(i)
				break

func _refresh_effect_list():
	if not _effect_list: return
	_effect_list.clear()
	for b in _get_bindings_for_anim(_selected_anim):
		var label = "[F" + str(b.get("frame", 0)) + "] " + str(b.get("effect_name", "?"))
		if b.get("scene_path", "") != "": label += " (path)"
		_effect_list.add_item(label)
		_effect_list.set_item_metadata(_effect_list.item_count - 1, b["id"])

func _on_effect_selected(index: int):
	if index < 0: return
	_selected_binding_id = _effect_list.get_item_metadata(index)
	var b = _get_binding_by_id(_selected_binding_id)
	if b.is_empty(): return
	
	_update_panel(b)
	_timeline.queue_redraw()
	_draw_node.queue_redraw()

func _get_binding_by_id(id: String) -> Dictionary:
	for b in _bindings:
		if b["id"] == id:
			return b
	return {}

# ==========================================
# 添加/删除特效绑定
# ==========================================
func _on_add_binding():
	if _selected_anim == "": return
	var frame_idx = int(_frame_spin.value) if _frame_spin else 0
	var new_b = {
		"id": "eb_" + str(Time.get_unix_time_from_system()),
		"effect_name": "",
		"scene_path": "",
		"anim": _selected_anim,
		"frame": frame_idx,
		"x": 0.0,
		"y": 0.0,
		"z_offset": 0.0,
		"scale_x": 1.0,
		"scale_y": 1.0,
		"rotation": 0.0,
		"follow_entity": false,
		"follow_facing": false,
		"flip_h": false,
		"auto_flip_by_facing": false
	}
	_bindings.append(new_b)
	_selected_binding_id = new_b["id"]
	_refresh_effect_list()
	# 选中刚添加的
	for i in range(_effect_list.item_count):
		if _effect_list.get_item_metadata(i) == new_b["id"]:
			_effect_list.select(i)
			break
	_update_panel(new_b)
	_timeline.queue_redraw()
	_draw_node.queue_redraw()
	_has_unsaved_changes = true

func _on_del_binding():
	if _selected_binding_id == "": return
	var new_array = []
	for b in _bindings:
		if b["id"] != _selected_binding_id:
			new_array.append(b)
	_bindings = new_array
	_selected_binding_id = ""
	_refresh_effect_list()
	_update_panel({})
	_timeline.queue_redraw()
	_draw_node.queue_redraw()
	_has_unsaved_changes = true

# ==========================================
# 属性面板
# ==========================================
func _update_panel(b: Dictionary):
	_panel_updating = true
	if b.is_empty():
		if _effect_name_input: _effect_name_input.text = ""
		if _scene_path_input: _scene_path_input.text = ""
		if _bind_frame_spin: _bind_frame_spin.value = 0
		if _pos_x_spin: _pos_x_spin.value = 0
		if _pos_y_spin: _pos_y_spin.value = 0
		if _z_offset_spin: _z_offset_spin.value = 0
		if _scale_x_spin: _scale_x_spin.value = 1.0
		if _scale_y_spin: _scale_y_spin.value = 1.0
		if _rotation_spin: _rotation_spin.value = 0.0
		if _follow_entity_check: _follow_entity_check.button_pressed = false
		if _follow_facing_check: _follow_facing_check.button_pressed = false
		if _flip_h_check: _flip_h_check.button_pressed = false
		if _auto_flip_facing_check: _auto_flip_facing_check.button_pressed = false
	else:
		if _effect_name_input: _effect_name_input.text = b.get("effect_name", "")
		if _scene_path_input: _scene_path_input.text = b.get("scene_path", "")
		if _bind_frame_spin: _bind_frame_spin.value = b.get("frame", 0)
		if _pos_x_spin: _pos_x_spin.value = b.get("x", 0)
		if _pos_y_spin: _pos_y_spin.value = b.get("y", 0)
		if _z_offset_spin: _z_offset_spin.value = b.get("z_offset", 0)
		if _scale_x_spin: _scale_x_spin.value = b.get("scale_x", 1.0)
		if _scale_y_spin: _scale_y_spin.value = b.get("scale_y", 1.0)
		if _rotation_spin: _rotation_spin.value = b.get("rotation", 0.0)
		if _follow_entity_check: _follow_entity_check.button_pressed = b.get("follow_entity", false)
		if _follow_facing_check: _follow_facing_check.button_pressed = b.get("follow_facing", false)
		if _flip_h_check: _flip_h_check.button_pressed = b.get("flip_h", false)
		if _auto_flip_facing_check: _auto_flip_facing_check.button_pressed = b.get("auto_flip_by_facing", false)
	_panel_updating = false

# 统一属性变更回调
func _on_prop_changed(_v = null):
	if _panel_updating: return
	var b = _get_binding_by_id(_selected_binding_id)
	if b.is_empty(): return
	b["effect_name"] = _effect_name_input.text if _effect_name_input else ""
	b["scene_path"] = _scene_path_input.text if _scene_path_input else ""
	b["x"] = _pos_x_spin.value if _pos_x_spin else 0
	b["y"] = _pos_y_spin.value if _pos_y_spin else 0
	b["z_offset"] = _z_offset_spin.value if _z_offset_spin else 0
	b["scale_x"] = _scale_x_spin.value if _scale_x_spin else 1.0
	b["scale_y"] = _scale_y_spin.value if _scale_y_spin else 1.0
	b["rotation"] = _rotation_spin.value if _rotation_spin else 0.0
	b["follow_entity"] = _follow_entity_check.button_pressed if _follow_entity_check else false
	b["follow_facing"] = _follow_facing_check.button_pressed if _follow_facing_check else false
	b["flip_h"] = _flip_h_check.button_pressed if _flip_h_check else false
	b["auto_flip_by_facing"] = _auto_flip_facing_check.button_pressed if _auto_flip_facing_check else false
	_refresh_effect_list_keep_selection()
	_timeline.queue_redraw()
	_draw_node.queue_redraw()
	_has_unsaved_changes = true

func _on_frame_spin_changed(value: float):
	var frame_idx = int(value)
	print("[effect_binder] _on_frame_spin_changed: frame=%d" % frame_idx)
	# 仅更新预览帧，绝不同步到特效绑定
	if _is_anim_player_entity:
		if not _is_playing:
			_set_preview_frame(_selected_anim, frame_idx)
			_play_frame = frame_idx
	elif _preview_sprite and not _is_playing:
		_preview_sprite.frame = frame_idx
		_play_frame = frame_idx
	_update_frame_label()
	_timeline.queue_redraw()
	_draw_node.queue_redraw()

# 右侧面板：编辑选中特效的绑定帧（仅此一处可改绑定帧）
func _on_bind_frame_changed(value: float):
	if _panel_updating: return
	var b = _get_binding_by_id(_selected_binding_id)
	if b.is_empty(): return
	b["frame"] = int(value)
	_refresh_effect_list_keep_selection()
	_timeline.queue_redraw()
	_draw_node.queue_redraw()
	_has_unsaved_changes = true

func _update_frame_label():
	if _frame_label:
		_frame_label.text = "帧: " + str(_play_frame)

# ==========================================
# 预览播放
# ==========================================
func _on_play_pressed():
	if _selected_anim == "": return
	if _is_anim_player_entity:
		# 每次预览强制重建特效
		_clear_preview_effects()
		_precreate_all_effects()
		
		# 隐藏绘制层和 UI 面板
		_set_preview_ui_visible(false)
		
		_is_playing = true
		_play_frame = 0
		_play_timer = 0.0
		_set_preview_frame(_selected_anim, 0)
		_frame_spin.value = 0
		_update_frame_label()
		_timeline.queue_redraw()
		# 显示第0帧的特效
		_show_preview_effects_at_frame(0)
		return
	
	if not _preview_sprite: return
	if not _preview_sprite.sprite_frames.has_animation(_selected_anim): return
	
	# 每次预览强制重建特效
	_clear_preview_effects()
	_precreate_all_effects()
	
	# 隐藏绘制层和 UI 面板
	_set_preview_ui_visible(false)
	
	_is_playing = true
	_play_frame = 0
	_play_timer = 0.0
	_preview_sprite.stop()
	_preview_sprite.animation = _selected_anim
	_preview_sprite.frame = 0
	_frame_spin.value = 0
	_update_frame_label()
	_timeline.queue_redraw()
	# 显示第0帧的特效
	_show_preview_effects_at_frame(0)

func _on_stop_pressed():
	_stop_preview()

func _stop_preview():
	if not _is_playing:
		return
	_is_playing = false
	_clear_preview_effects()
	_set_preview_ui_visible(true)
	if _is_anim_player_entity:
		_set_preview_frame(_selected_anim, _play_frame)
	elif _preview_sprite:
		_preview_sprite.stop()
		_preview_sprite.frame = _play_frame
	if _draw_node:
		_draw_node.queue_redraw()
	if _timeline:
		_timeline.queue_redraw()

func _set_preview_ui_visible(vis: bool):
	# 绘制层 + 时间轴：预览时隐藏
	if _draw_node:
		_draw_node.visible = vis
	if _interaction_layer:
		_interaction_layer.visible = vis
	if _timeline:
		_timeline.visible = vis
	# 帧框：预览时显示
	if _frame_spin:
		_frame_spin.visible = not vis

func _clear_preview_effects():
	for eff in _preview_effects:
		if is_instance_valid(eff):
			eff.queue_free()
	_preview_effects.clear()

# ==========================================
# 预览特效生成
# ==========================================
# 预创建当前动画所有绑定帧的特效（隐藏，等待播放时显示）
func _precreate_all_effects():
	_clear_preview_effects()
	var anim_bindings = _get_bindings_for_anim(_selected_anim)
	var preview_root = _canvas.get_node_or_null("EntityPreview")
	var base_pos = Vector2.ZERO
	if preview_root:
		base_pos = preview_root.position
	
	for b in anim_bindings:
		var scene = null
		var scene_path = b.get("scene_path", "")
		var effect_name = b.get("effect_name", "")
		
		if scene_path != "" and ResourceLoader.exists(scene_path):
			scene = load(scene_path)
		if scene == null and effect_name != "":
			scene = _find_effect_scene_by_name(effect_name)
		if scene == null:
			continue
		
		var effect = scene.instantiate()
		if effect == null:
			continue
		
		var offset_x = b.get("x", 0.0)
		var offset_y = b.get("y", 0.0)
		var z_off = b.get("z_offset", 0.0)
		# Z偏移在运行时影响屏幕Y（depth + height → screen_y），且 z_off 不乘 sprite_scale
		# 除以原始 sprite_scale 使编辑器预览与运行时显示对齐
		var spawn_2d = base_pos + Vector2(offset_x / _sprite_scale.x * _canvas_zoom, (offset_y / _sprite_scale.y + z_off) * _canvas_zoom)
		effect.position = spawn_2d
		effect.scale = Vector2(b.get("scale_x", 1.0) / _sprite_scale.x * _canvas_zoom, b.get("scale_y", 1.0) / _sprite_scale.y * _canvas_zoom)
		effect.rotation = deg_to_rad(b.get("rotation", 0.0))
		if b.get("flip_h", false):
			effect.scale.x = -abs(effect.scale.x)
		
		# 标记所属绑定，隐藏
		effect.set_meta("_bind_id", b["id"])
		effect.visible = false
		
		_canvas.add_child(effect)
		_preview_effects.append(effect)
		
		# 延迟：等 _ready() 执行后，停止动画并断开自动销毁信号
		call_deferred("_freeze_effect", effect)

func _freeze_effect(effect: Node):
	if not is_instance_valid(effect): return
	var anim_sprite = _find_animated_sprite(effect)
	if not anim_sprite: return
	# 断开 animation_finished 所有连接（阻止 EffectBase 自毁）
	for conn in anim_sprite.animation_finished.get_connections():
		anim_sprite.animation_finished.disconnect(conn["callable"])
	# 如果特效已被预览激活（visible），不要停止其动画（避免中断第0帧特效播放）
	if effect.visible:
		return
	anim_sprite.stop()

# 播放时：显示当前帧的特效并播放其动画
func _show_preview_effects_at_frame(frame_idx: int):
	var anim_bindings = _get_bindings_for_anim(_selected_anim)
	var target_ids = {}
	for b in anim_bindings:
		if b.get("frame", 0) == frame_idx:
			target_ids[b["id"]] = true
	
	for eff in _preview_effects:
		if not is_instance_valid(eff):
			continue
		var bid = eff.get_meta("_bind_id", "")
		if target_ids.has(bid) and not eff.visible:
			eff.visible = true
			var anim_sprite = _find_animated_sprite(eff)
			if anim_sprite:
				anim_sprite.stop()
				anim_sprite.frame = 0
				anim_sprite.play()

func _find_effect_scene_by_name(effect_name: String):
	var entity_dir = _entity_scene_path.get_base_dir()
	
	# 搜索实体 _effects 目录
	var effects_dir = entity_dir + "/_effects"
	if DirAccess.dir_exists_absolute(effects_dir):
		var dir = DirAccess.open(effects_dir)
		if dir:
			dir.list_dir_begin()
			var item = dir.get_next()
			while item != "":
				if dir.current_is_dir() and item == effect_name:
					var sub = DirAccess.open(effects_dir + "/" + item)
					if sub:
						sub.list_dir_begin()
						var f = sub.get_next()
						while f != "":
							if f.ends_with(".tscn"):
								return load(effects_dir + "/" + item + "/" + f)
							f = sub.get_next()
						sub.list_dir_end()
				item = dir.get_next()
			dir.list_dir_end()
	
	# 搜索通用 effects 目录
	var common_dir = "res://assets/entities/base/effects"
	if DirAccess.dir_exists_absolute(common_dir):
		var dir = DirAccess.open(common_dir)
		if dir:
			dir.list_dir_begin()
			var item = dir.get_next()
			while item != "":
				if dir.current_is_dir() and item == effect_name:
					var sub = DirAccess.open(common_dir + "/" + item)
					if sub:
						sub.list_dir_begin()
						var f = sub.get_next()
						while f != "":
							if f.ends_with(".tscn"):
								return load(common_dir + "/" + item + "/" + f)
							f = sub.get_next()
						sub.list_dir_end()
				item = dir.get_next()
			dir.list_dir_end()
	
	return null

# ==========================================
# 时间轴绘制
# ==========================================
func _on_timeline_draw():
	if _selected_anim == "" or not _timeline: return
	var total = _get_anim_frame_count(_selected_anim)
	if total <= 0: return
	
	var w = _timeline.size.x
	var h = _timeline.size.y
	var margin = 8.0
	var cell_w = (w - margin * 2) / total
	var bar_y = h * 0.25
	var bar_h = h * 0.45
	
	# 背景
	_timeline.draw_rect(Rect2(Vector2.ZERO, _timeline.size), Color(0.15, 0.15, 0.15, 1))
	
	# 播放头
	var play_x = margin + _play_frame * cell_w + cell_w / 2
	_timeline.draw_line(Vector2(play_x, 0), Vector2(play_x, h), Color(1, 1, 1, 0.6), 2.0)
	
	# 帧刻度线
	for i in range(total + 1):
		var x = margin + i * cell_w
		_timeline.draw_line(Vector2(x, bar_y), Vector2(x, bar_y + bar_h), Color(0.5, 0.5, 0.5, 0.4), 1.0)
		if i < total:
			var lbl = ThemeDB.fallback_font
			var tw = lbl.get_string_size(str(i), HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
			_timeline.draw_string(lbl, Vector2(x + cell_w / 2 - tw.x / 2, 2), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.6))

	# 特效绑定标记（菱形）
	var bindings_for_anim = _get_bindings_for_anim(_selected_anim)
	for b in bindings_for_anim:
		var f = b.get("frame", 0)
		if f < 0 or f >= total: continue
		var cx = margin + f * cell_w + cell_w / 2
		var cy = bar_y + bar_h / 2
		var size = 6.0
		
		var is_sel = (b["id"] == _selected_binding_id)
		var color = Color.YELLOW if is_sel else Color(0.3, 1.0, 0.7, 0.9)
		
		var pts = PackedVector2Array([
			Vector2(cx, cy - size),
			Vector2(cx + size, cy),
			Vector2(cx, cy + size),
			Vector2(cx - size, cy)
		])
		_timeline.draw_colored_polygon(pts, color)
		if is_sel:
			pts.append(pts[0])
			_timeline.draw_polyline(pts, Color.WHITE, 2.0)

func _on_timeline_input(event: InputEvent):
	if _selected_anim == "" or not _timeline: return
	var total = _get_anim_frame_count(_selected_anim)
	if total <= 0: return
	
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_stop_preview()
			var w = _timeline.size.x
			var margin = 8.0
			var cell_w = (w - margin * 2) / total
			var frame_idx = int((mb.position.x - margin) / cell_w)
			frame_idx = clampi(frame_idx, 0, total - 1)
			_play_frame = frame_idx
			_frame_spin.value = frame_idx
			if _is_anim_player_entity:
				_set_preview_frame(_selected_anim, frame_idx)
			elif _preview_sprite:
				_preview_sprite.frame = frame_idx
			_update_frame_label()
			_timeline.queue_redraw()
			if _draw_node:
				_draw_node.queue_redraw()

# ==========================================
# 特效选择弹窗
# ==========================================
func _on_show_effect_popup(btn: Button):
	var popup = PopupMenu.new()
	if _available_effects.size() == 0:
		popup.add_item("(无可用特效)")
		popup.set_item_disabled(0, true)
	else:
		for ef in _available_effects:
			popup.add_item(ef)
			popup.set_item_metadata(popup.item_count - 1, ef)
	popup.id_pressed.connect(_on_effect_popup_selected.bind(popup))
	popup.popup_hide.connect(popup.queue_free)
	add_child(popup)
	popup.position = btn.get_screen_position() + Vector2(0, btn.size.y)
	popup.reset_size()
	popup.popup()

func _on_effect_popup_selected(id: int, popup: PopupMenu):
	var effect_name = popup.get_item_metadata(id)
	if effect_name and effect_name is String:
		_effect_name_input.text = effect_name
		_on_prop_changed()

# ==========================================
# 工具函数
# ==========================================
func _mk_label(text: String, size: int = 14, min_w: int = 0) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		lbl.custom_minimum_size.x = min_w
	return lbl

func _mk_spinbox(label_text: String, min_v: float, max_v: float, step: float, parent: Control) -> SpinBox:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)
	hbox.add_child(_mk_label(label_text, 12, 30))
	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spin)
	return spin

func _mk_hsep() -> HSeparator:
	return HSeparator.new()

# ==========================================
# 扫描可用特效
# ==========================================
func _scan_available_effects():
	_available_effects.clear()
	var entity_dir = _entity_scene_path.get_base_dir()
	var effects_dir = entity_dir + "/_effects"
	if DirAccess.dir_exists_absolute(effects_dir):
		var dir = DirAccess.open(effects_dir)
		if dir:
			dir.list_dir_begin()
			var item_name = dir.get_next()
			while item_name != "":
				if dir.current_is_dir() and not item_name.begins_with("."):
					var sub_dir = effects_dir + "/" + item_name
					var sub = DirAccess.open(sub_dir)
					if sub:
						sub.list_dir_begin()
						var f = sub.get_next()
						while f != "":
							if f.ends_with(".tscn") and not f.begins_with("."):
								_available_effects.append(item_name)
								break
							f = sub.get_next()
						sub.list_dir_end()
				item_name = dir.get_next()
			dir.list_dir_end()
	var common_effects = "res://assets/entities/base/effects"
	if DirAccess.dir_exists_absolute(common_effects):
		var dir = DirAccess.open(common_effects)
		if dir:
			dir.list_dir_begin()
			var item_name = dir.get_next()
			while item_name != "":
				if dir.current_is_dir() and not item_name.begins_with("."):
					if not _available_effects.has(item_name):
						_available_effects.append(item_name)
				item_name = dir.get_next()
			dir.list_dir_end()
	print("[特效绑定器] 发现特效: ", _available_effects)

# ==========================================
# 数据加载与保存
# ==========================================
func _load_existing_data():
	_bindings.clear()
	var data_path = _entity_scene_path.get_base_dir() + "/effect_bindings.json"
	if not FileAccess.file_exists(data_path): return
	var file = FileAccess.open(data_path, FileAccess.READ)
	if not file: return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data = json.data
	if data is Dictionary and data.has("bindings"):
		var raw = data["bindings"]
		for b in raw:
			# 归一化：确保所有字段存在
			var nb = {
				"id": b.get("id", "eb_" + str(Time.get_unix_time_from_system())),
				"effect_name": b.get("effect_name", ""),
				"scene_path": b.get("scene_path", ""),
				"anim": b.get("anim", ""),
				"frame": b.get("frame", 0),
				"x": b.get("x", 0.0),
				"y": b.get("y", 0.0),
				"z_offset": b.get("z_offset", 0.0),
				"scale_x": b.get("scale_x", 1.0),
				"scale_y": b.get("scale_y", 1.0),
				"rotation": b.get("rotation", 0.0),
				"follow_entity": b.get("follow_entity", false),
				"follow_facing": b.get("follow_facing", false),
				"flip_h": b.get("flip_h", false),
				"auto_flip_by_facing": b.get("auto_flip_by_facing", false)
			}
			_bindings.append(nb)
		print("[特效绑定器] 已加载 %d 个特效绑定" % _bindings.size())

func _on_save_data():
	var data = {"bindings": _bindings}
	var data_path = _entity_scene_path.get_base_dir() + "/effect_bindings.json"
	var file = FileAccess.open(data_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		_has_unsaved_changes = false
		print("[特效绑定器] 已保存 %d 个绑定到: %s" % [_bindings.size(), data_path])
	else:
		print("[特效绑定器] 保存失败: ", data_path)

# ==========================================
# 预览与动画
# ==========================================
func _setup_entity_preview():
	if not _canvas: return
	for child in _canvas.get_children():
		if child.name == "EntityPreview":
			child.queue_free()
	if not _entity_instance: return
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
	if node is AnimatedSprite2D: return node
	if node.has_node("Visuals/AnimatedSprite2D"):
		return node.get_node("Visuals/AnimatedSprite2D")
	for child in node.get_children():
		var found = _find_animated_sprite(child)
		if found: return found
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
	if not _canvas: return
	var preview_root = _canvas.get_node_or_null("EntityPreview")
	if not preview_root: return
	preview_root.position = preview_root_position * _canvas_zoom
	preview_root.scale = Vector2(_canvas_zoom, _canvas_zoom)
	if _draw_node:
		_draw_node.position = preview_root_position * _canvas_zoom
		_draw_node.scale = Vector2(1, 1)
		_draw_node.queue_redraw()

# ==========================================
# 画布绘制
# ==========================================
func _on_canvas_draw():
	if _is_playing: return  # 播放时关闭绘制
	if _is_anim_player_entity:
		if not _canvas.get_node_or_null("EntityPreview") or not _draw_node:
			return
	elif not _preview_sprite or not _draw_node:
		return

	var axis_len = 50 * _canvas_zoom
	_draw_node.draw_line(Vector2(0, 0), Vector2(axis_len, 0), Color.RED, 1.0)
	_draw_node.draw_line(Vector2(0, 0), Vector2(0, axis_len), Color.GREEN, 1.0)
	_draw_node.draw_circle(Vector2.ZERO, 5, Color(1, 1, 1, 0.5))

	if _selected_anim == "": return
	var cur_frame = _play_frame

	for b in _get_bindings_for_anim(_selected_anim):
		# 显示坐标：x / sprite_scale.x, y / sprite_scale.y + z_offset（z_off 运行时不被 sprite_scale 影响）
		var draw_pos = Vector2(b["x"] / _sprite_scale.x, b["y"] / _sprite_scale.y + b.get("z_offset", 0.0)) * _canvas_zoom
		var is_sel = (b["id"] == _selected_binding_id)
		var is_cur = (b.get("frame", 0) == cur_frame and _is_playing)

		var color: Color
		if is_sel:
			color = Color(1, 1, 0, 1)
		elif is_cur:
			color = Color(1, 0.3, 0.3, 1)  # 播放中触发 = 红色
		else:
			color = Color(0.5, 0.5, 0.5, 0.5)

		var ms: float = 12.0
		_draw_node.draw_circle(draw_pos, ms, color)
		_draw_node.draw_arc(draw_pos, ms + 2, 0, TAU, 32, Color.WHITE if is_sel else Color(color, 0.5), 1.5 if is_sel else 1.0)

		if is_cur:
			# 播放触发脉冲效果
			var pulse = ms + 4 + sin(Time.get_unix_time_from_system() * 10) * 2
			_draw_node.draw_arc(draw_pos, pulse, 0, TAU, 16, Color(1, 0.3, 0.3, 0.4), 2.0)

		var rot = deg_to_rad(b.get("rotation", 0.0))
		var al = 20.0
		var ae = draw_pos + Vector2(cos(rot), sin(rot)) * al
		var ac = Color.YELLOW if is_sel else Color(0.8, 0.8, 0.3, 0.6)
		_draw_node.draw_line(draw_pos, ae, ac, 2.0)
		var tip_l = ae + Vector2(cos(rot + PI * 0.8), sin(rot + PI * 0.8)) * 6
		var tip_r = ae + Vector2(cos(rot - PI * 0.8), sin(rot - PI * 0.8)) * 6
		_draw_node.draw_line(ae, tip_l, ac, 1.5)
		_draw_node.draw_line(ae, tip_r, ac, 1.5)

		var sx = b.get("scale_x", 1.0) * 10.0
		var sy = b.get("scale_y", 1.0) * 10.0
		_draw_node.draw_rect(Rect2(draw_pos + Vector2(ms + 4, -sy/2), Vector2(sx, sy)), Color(color, 0.4), false, 1.0)

		var info_text = ""
		if b.get("follow_entity", false): info_text += "F"
		if b.get("follow_facing", false): info_text += "D"
		var label_text = b.get("effect_name", "?")
		if info_text != "": label_text += " " + info_text
		_draw_node.draw_string(ThemeDB.fallback_font, draw_pos + Vector2(ms + 20 + sx + 4, -8), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

# ==========================================
# 画布交互
# ==========================================
func _on_interaction_input(event: InputEvent):
	if not _canvas or not _canvas.get_node_or_null("EntityPreview"): return
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var zoom_factor = 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9
			var old_zoom = _canvas_zoom
			_canvas_zoom = clamp(_canvas_zoom * zoom_factor, 0.1, 10.0)
			var mouse_pos = mb.position
			var logical_mouse_before = (mouse_pos / old_zoom) - preview_root_position
			preview_root_position = (mouse_pos / _canvas_zoom) - logical_mouse_before
			_apply_canvas_transform()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_panning = true
				_pan_start_mouse_pos = mb.position
				_pan_start_offset = preview_root_position
			else:
				_is_panning = false
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _is_panning: return
				var logical_mouse = (mb.position / _canvas_zoom) - preview_root_position
				var anim_bindings = _get_bindings_for_anim(_selected_anim)
				for b in anim_bindings:
					# 计算显示坐标（与 _on_canvas_draw 一致，z_off 不除 sprite_scale）
					var pt_pos = Vector2(b["x"] / _sprite_scale.x, b["y"] / _sprite_scale.y + b.get("z_offset", 0.0))
					var threshold = 20.0 / _canvas_zoom
					if logical_mouse.distance_to(pt_pos) < threshold:
						_is_dragging = true
						_drag_offset = pt_pos - logical_mouse
						_selected_binding_id = b["id"]
						_update_panel(b)
						for i in range(_effect_list.item_count):
							if _effect_list.get_item_metadata(i) == b["id"]:
								_effect_list.select(i)
								break
						_timeline.queue_redraw()
						return
			else:
				if _is_dragging: _is_dragging = false
	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		if _is_panning:
			var drag_delta = (mm.position - _pan_start_mouse_pos) / _canvas_zoom
			preview_root_position = _pan_start_offset + drag_delta
			_apply_canvas_transform()
		elif _is_dragging:
			var logical_mouse = (mm.position / _canvas_zoom) - preview_root_position
			var new_pos = logical_mouse + _drag_offset
			var b = _get_binding_by_id(_selected_binding_id)
			if b.is_empty(): return
			# 显示坐标转回绑定坐标（乘以 sprite_scale，与绘制时的除法对称，z_off 不参与 sprite_scale 转换）
			b["x"] = new_pos.x * _sprite_scale.x
			b["y"] = (new_pos.y - b.get("z_offset", 0.0)) * _sprite_scale.y
			if _pos_x_spin: _pos_x_spin.value = b["x"]
			if _pos_y_spin: _pos_y_spin.value = b["y"]
			if _draw_node: _draw_node.queue_redraw()
			_has_unsaved_changes = true

# ==========================================
# 关闭处理
# ==========================================
func _on_close_requested():
	_stop_preview()
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
	dialog.confirmed.connect(_on_save_and_close.bind(dialog))
	dialog.canceled.connect(_on_discard_and_close.bind(dialog))
	dialog.custom_action.connect(_on_cancel_dialog.bind(dialog))
	add_child(dialog)
	dialog.popup_centered()

func _on_cancel_dialog(action: String, dialog: ConfirmationDialog):
	if action == "cancel": dialog.queue_free()

func _on_save_and_close(dialog: ConfirmationDialog):
	dialog.queue_free()
	_clear_preview_effects()
	_on_save_data()
	queue_free()

func _on_discard_and_close(dialog: ConfirmationDialog):
	dialog.queue_free()
	_clear_preview_effects()
	queue_free()

func _input(event: InputEvent):
	if not visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S and event.ctrl_pressed:
			_on_save_data()
			get_viewport().set_input_as_handled()

func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if _is_anim_player_entity:
			if _canvas and _canvas.get_node_or_null("EntityPreview"):
				_apply_canvas_transform()
		elif _preview_sprite and _canvas:
			_apply_canvas_transform()
		if _timeline:
			_timeline.queue_redraw()
