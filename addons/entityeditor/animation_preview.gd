# animation_preview.gd
# 动画预览窗口 — 支持缩放、拖拽、三种渲染器
@tool
extends Window

var _entity: Node = null
var _scene_path: String = ""
var _render_mode: int = -1  # 当前动画的渲染模式: 0=Sprite, 1=AnimPlayer, 2=CRE
var _primary_mode: int = -1  # 实体的主要渲染模式

# 预览
var _preview_root: Node2D = null
var _preview_node: Node = null
var _cre_sprite_nodes: Array = []  # CRE 专用 Sprite2D 节点
var _cre_part_nodes: Dictionary = {}  # {sprite_id: Sprite2D}

# CRE 数据
var _cre_sprites: Dictionary = {}
var _cre_animations: Dictionary = {}
var _has_ufe_data: bool = false

# 画布
var _canvas: Control = null
var _canvas_zoom: float = 1.0
var _root_pos: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_offset: Vector2 = Vector2.ZERO
var _needs_focus: bool = false

# 播放状态
var _current_anim: String = ""
var _current_frame: int = 0
var _frame_keys: Array = []
var _frame_timer: float = 0.0
var _is_playing: bool = false
var _play_dir: int = 1  # 1=正放 -1=倒放
var _loop: bool = true
var _speed: float = 1.0
var _total_frames: int = 0
var _fps: float = 30.0
var _overrides: Dictionary = {}

# UI
var _anim_select: OptionButton
var _loop_btn: CheckButton
var _speed_slider: HSlider
var _speed_label: Label
var _frame_slider: HSlider
var _frame_label: Label
var _debug_btn: CheckButton

func setup(entity: Node, scene_path: String = ""):
	_entity = entity
	_scene_path = scene_path
	_detect_source()
	_build_ui()
	_create_preview()
	_populate_anims()

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_cleanup()

func _cleanup():
	_is_playing = false
	set_process(false)
	if _preview_root and is_instance_valid(_preview_root):
		_preview_root.queue_free()
		_preview_root = null

# ============================================
# 检测
# ============================================

func _detect_source():
	# 始终检查 UFE 数据
	var ufe_dir = _find_ufe_dir()
	if not ufe_dir.is_empty():
		_load_cre_data(ufe_dir)
		_has_ufe_data = _cre_animations.size() > 0

	# UFE 数据优先（CompositeRendererEntity 可能场景树里也有 AnimPlayer）
	if _has_ufe_data:
		_primary_mode = 2
		_render_mode = 2
		return

	# 检测主要渲染模式
	var sp = _find_anim_sprite(_entity)
	if sp:
		_primary_mode = 0
		_render_mode = 0
		return
	var ap = _find_anim_player(_entity)
	if ap:
		_primary_mode = 1
		_render_mode = 1

func _find_anim_sprite(node: Node) -> Node:
	for child in node.get_children():
		if child.name == "Aura": continue
		if child is AnimatedSprite2D: return child
		var r = _find_anim_sprite(child)
		if r: return r
	return null

func _find_anim_player(node: Node) -> Node:
	for child in node.get_children():
		if child.name == "Aura": continue
		if child is AnimationPlayer: return child
		var r = _find_anim_player(child)
		if r: return r
	return null

func _find_ufe_dir() -> String:
	if not _scene_path.is_empty():
		var dir = _scene_path.get_base_dir() + "/ufe/"
		if FileAccess.file_exists(dir + "sprites.json"):
			return dir
	return ""

func _load_cre_data(ufe_dir: String):
	if FileAccess.file_exists(ufe_dir + "sprites.json"):
		var f = FileAccess.open(ufe_dir + "sprites.json", FileAccess.READ)
		var j = JSON.new()
		j.parse(f.get_as_text())
		f.close()
		if j.data and j.data.has("sprites"):
			_cre_sprites = j.data["sprites"]
	if FileAccess.file_exists(ufe_dir + "animations.json"):
		var f = FileAccess.open(ufe_dir + "animations.json", FileAccess.READ)
		var j = JSON.new()
		j.parse(f.get_as_text())
		f.close()
		if j.data and j.data.has("animations"):
			_cre_animations = j.data["animations"]

# ============================================
# UI
# ============================================

func _lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _build_ui():
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 2)

	# 控制栏
	var toolbar := HBoxContainer.new()
	toolbar.add_child(_lbl("动画:"))
	_anim_select = OptionButton.new()
	_anim_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_select.item_selected.connect(_on_anim_selected)
	toolbar.add_child(_anim_select)
	_loop_btn = CheckButton.new()
	_loop_btn.text = "循环"
	_loop_btn.button_pressed = true
	_loop_btn.toggled.connect(func(v: bool): _loop = v)
	toolbar.add_child(_loop_btn)
	_debug_btn = CheckButton.new()
	_debug_btn.text = "调试"
	_debug_btn.button_pressed = false
	_debug_btn.toggled.connect(_on_debug_toggled)
	toolbar.add_child(_debug_btn)
	var focus_btn := Button.new()
	focus_btn.text = "定位"
	focus_btn.pressed.connect(_focus_first_sprite)
	toolbar.add_child(focus_btn)
	root.add_child(toolbar)

	# 播放按钮栏
	var playbar := HBoxContainer.new()
	playbar.alignment = BoxContainer.ALIGNMENT_CENTER
	playbar.add_theme_constant_override("separation", 4)
	var btn_names: Array = ["|◄", "◄", "■", "►", "►|"]
	var btn_cbs: Array = [
		func(): _play_from_end_reverse(),
		func(): _play_reverse(),
		func(): _stop(); _set_frame(_current_frame),
		func(): _play_forward(),
		func(): _play_from_start(),
	]
	for i in range(5):
		var btn := Button.new()
		btn.text = btn_names[i]
		btn.custom_minimum_size = Vector2(40, 0)
		btn.pressed.connect(btn_cbs[i])
		playbar.add_child(btn)
	root.add_child(playbar)

	# 画布
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.gui_input.connect(_on_canvas_input)
	_canvas.draw.connect(_on_canvas_draw)
	root.add_child(_canvas)

	# 底栏
	var bottom := HBoxContainer.new()
	bottom.add_child(_lbl("速度:"))
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.1
	_speed_slider.max_value = 3.0
	_speed_slider.step = 0.1
	_speed_slider.value = 1.0
	_speed_slider.custom_minimum_size.x = 100
	_speed_slider.value_changed.connect(_on_speed_changed)
	bottom.add_child(_speed_slider)
	_speed_label = Label.new()
	_speed_label.text = "1.0x"
	_speed_label.custom_minimum_size.x = 35
	bottom.add_child(_speed_label)
	bottom.add_spacer(false)
	var sb := Button.new()
	sb.text = "<"
	sb.pressed.connect(_on_step_back)
	bottom.add_child(sb)
	_frame_slider = HSlider.new()
	_frame_slider.min_value = 0
	_frame_slider.max_value = 1
	_frame_slider.step = 1
	_frame_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_slider.value_changed.connect(_on_frame_scrub)
	bottom.add_child(_frame_slider)
	var sfwd := Button.new()
	sfwd.text = ">"
	sfwd.pressed.connect(_on_step_forward)
	bottom.add_child(sfwd)
	_frame_label = Label.new()
	_frame_label.text = "0/0"
	_frame_label.custom_minimum_size.x = 50
	bottom.add_child(_frame_label)
	root.add_child(bottom)

	add_child(root)

# ============================================
# 画布交互（缩放 + 拖拽）
# ============================================

func _on_canvas_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor = 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9
			var old_zoom = _canvas_zoom
			_canvas_zoom = clampf(_canvas_zoom * factor, 0.1, 5.0)
			# 以鼠标为中心缩放
			var mouse_pos = mb.position
			var logical_before = (mouse_pos / old_zoom) - _root_pos
			_root_pos = (mouse_pos / _canvas_zoom) - logical_before
			_apply_transform()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_panning = true
				_pan_start_mouse = mb.position
				_pan_start_offset = _root_pos
			else:
				_is_panning = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# 右键拖拽也可以平移
			if mb.pressed:
				_is_panning = true
				_pan_start_mouse = mb.position
				_pan_start_offset = _root_pos
			else:
				_is_panning = false
	elif event is InputEventMouseMotion and _is_panning:
		var delta = event.position - _pan_start_mouse
		_root_pos = _pan_start_offset + delta / _canvas_zoom
		_apply_transform()

func _apply_transform():
	if not _preview_root:
		return
	_preview_root.position = _root_pos * _canvas_zoom
	_preview_root.scale = Vector2.ONE * _canvas_zoom

# ============================================
# 创建预览
# ============================================

func _create_preview():
	_preview_root = Node2D.new()
	_preview_root.name = "PreviewRoot"
	_canvas.add_child(_preview_root)

	# 主要预览（Sprite / AnimPlayer）
	match _primary_mode:
		0:
			var src: AnimatedSprite2D = _find_anim_sprite(_entity)
			if src and src.sprite_frames:
				var copy := AnimatedSprite2D.new()
				copy.sprite_frames = src.sprite_frames.duplicate()
				copy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				copy.centered = true
				_preview_root.add_child(copy)
				_preview_node = copy
		1:
			if not _scene_path.is_empty():
				var scene = load(_scene_path)
				if scene:
					var inst = scene.instantiate()
					if inst is CollisionObject2D:
						inst.input_pickable = false
					_preview_root.add_child(inst)
					_preview_node = inst
					if inst is EntityBase:
						var scr = inst.get_script()
						if scr and scr.is_tool():
							inst.set_physics_process(false)
							inst.set_process(false)

	# CRE 碎片节点（UFE 数据存在时始终创建）
	if _has_ufe_data:
		var ufe_dir = _find_ufe_dir()
		var tex_dir = ufe_dir + "sprites/"
		var sorted_ids: Array = _cre_sprites.keys()
		sorted_ids.sort()
		_cre_part_nodes.clear()
		for spr_id in sorted_ids:
			var info: Dictionary = _cre_sprites[spr_id]
			var sp := Sprite2D.new()
			sp.name = spr_id
			sp.centered = true
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var fn: String = str(info.get("file", spr_id + ".png"))
			if ResourceLoader.exists(tex_dir + fn):
				sp.texture = load(tex_dir + fn)
			sp.visible = false
			_preview_root.add_child(sp)
			_cre_sprite_nodes.append(sp)
			_cre_part_nodes[spr_id] = sp
	_apply_transform()

func _show_cre_nodes(show: bool):
	for sp in _cre_sprite_nodes:
		if is_instance_valid(sp):
			sp.visible = false  # 始终先隐藏，由 _apply_cre 控制显示
	# 隐藏/显示主要预览节点
	if _preview_node and is_instance_valid(_preview_node):
		if _preview_node is AnimatedSprite2D:
			_preview_node.visible = !show
		elif _preview_node is Node2D:
			# AnimPlayer 实体：隐藏其 Visuals 子节点
			var vis = _preview_node.get_node_or_null("Visuals")
			if vis:
				vis.visible = !show

# ============================================
# 动画列表
# ============================================

func _populate_anims():
	_anim_select.clear()
	var anim_set := {}

	# 主要源
	match _primary_mode:
		0:
			if _preview_node and _preview_node is AnimatedSprite2D:
				var sp: AnimatedSprite2D = _preview_node as AnimatedSprite2D
				if sp.sprite_frames:
					for n in sp.sprite_frames.get_animation_names():
						anim_set[n] = true
		1:
			var ap = _find_ap()
			if ap:
				for n in ap.get_animation_list():
					anim_set[n] = true

	# UFE 动画（补充）
	if _has_ufe_data:
		for n in _cre_animations.keys():
			anim_set[n] = true

	if anim_set.is_empty():
		_frame_label.text = "无动画"
		return

	var anims: Array = anim_set.keys()
	anims.sort()
	for i in range(anims.size()):
		_anim_select.add_item(anims[i])
	_select_anim(anims[0])

func _find_ap() -> AnimationPlayer:
	if not _preview_node:
		return null
	if _preview_node is AnimationPlayer:
		return _preview_node as AnimationPlayer
	return _find_ap_r(_preview_node)

func _find_ap_r(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var r = _find_ap_r(child)
		if r: return r
	return null

func _select_anim(anim_name: String):
	_stop()
	_current_anim = anim_name
	_current_frame = 0
	_frame_timer = 0.0
	_total_frames = 0
	_overrides.clear()
	_fps = 30.0
	_loop = true
	_frame_keys.clear()

	# 判断该动画用哪种模式
	if _has_ufe_data and _cre_animations.has(anim_name):
		_render_mode = 2
	else:
		_render_mode = _primary_mode

	# 显示/隐藏 CRE 节点
	if _render_mode == 2:
		_show_cre_nodes(true)
	else:
		_show_cre_nodes(false)

	match _render_mode:
		0:
			if _preview_node and _preview_node is AnimatedSprite2D:
				var sp: AnimatedSprite2D = _preview_node as AnimatedSprite2D
				if sp.sprite_frames and sp.sprite_frames.has_animation(anim_name):
					_total_frames = sp.sprite_frames.get_frame_count(anim_name)
					_loop = sp.sprite_frames.get_animation_loop(anim_name)
		1:
			var ap = _find_ap()
			if ap and ap.has_animation(anim_name):
				var anim: Animation = ap.get_animation(anim_name)
				_total_frames = int(anim.length * 60.0)
				_loop = anim.loop_mode != Animation.LOOP_NONE
		2:
			var ad: Dictionary = _cre_animations.get(anim_name, {})
			_loop = ad.get("loop", true)
			_fps = float(ad.get("fps", 30))
			_overrides = ad.get("frame_overrides", {})
			var frames: Dictionary = ad.get("frames", {})
			# 构建排序后的帧键列表
			_frame_keys.clear()
			for k in frames.keys():
				_frame_keys.append(int(k))
			_frame_keys.sort()
			_total_frames = _frame_keys.size()

	_frame_slider.max_value = max(_total_frames - 1, 0)
	_loop_btn.button_pressed = _loop
	_set_frame(0)
	# CRE 模式标记需要定位
	if _render_mode == 2:
		_needs_focus = true
		set_process(true)

# ============================================
# 播放控制
# ============================================

func _play_forward():
	_play_dir = 1
	_start_playback()

func _play_reverse():
	_play_dir = -1
	_start_playback()

func _play_from_start():
	_play_dir = 1
	_set_frame(0)
	_start_playback()

func _play_from_end_reverse():
	_play_dir = -1
	_set_frame(maxi(_total_frames - 1, 0))
	_start_playback()

func _start_playback():
	_stop()
	_is_playing = true
	set_process(true)
	match _render_mode:
		0:
			if _preview_node and _preview_node is AnimatedSprite2D:
				var sp: AnimatedSprite2D = _preview_node as AnimatedSprite2D
				sp.play(_current_anim, _speed * _play_dir)
		1:
			var ap = _find_ap()
			if ap:
				ap.play(_current_anim)
				ap.speed_scale = _speed * _play_dir
		2:
			_apply_cre()

func _stop():
	_is_playing = false
	if not _needs_focus:
		set_process(false)
	match _render_mode:
		0:
			if _preview_node and _preview_node is AnimatedSprite2D:
				(_preview_node as AnimatedSprite2D).stop()
		1:
			var ap = _find_ap()
			if ap: ap.stop()

func _on_speed_changed(v: float):
	_speed = v
	_speed_label.text = "%.1fx" % v
	if _is_playing:
		match _render_mode:
			0:
				if _preview_node and _preview_node is AnimatedSprite2D:
					(_preview_node as AnimatedSprite2D).speed_scale = _speed * _play_dir
			1:
				var ap = _find_ap()
				if ap: ap.speed_scale = _speed * _play_dir

func _on_anim_selected(idx: int):
	var name: String = _anim_select.get_item_text(idx)
	if name != _current_anim:
		_select_anim(name)

# ============================================
# 帧控制
# ============================================

func _on_step_back():
	if _is_playing: return
	_set_frame(maxi(_current_frame - 1, 0))

func _on_step_forward():
	if _is_playing: return
	_set_frame(mini(_current_frame + 1, maxi(_total_frames - 1, 0)))

func _on_frame_scrub(v: float):
	_set_frame(int(v))

func _set_frame(f: int):
	_current_frame = f
	_frame_slider.set_value_no_signal(f)
	_frame_label.text = "%d/%d" % [f + 1, _total_frames]
	match _render_mode:
		0:
			if _preview_node and _preview_node is AnimatedSprite2D:
				(_preview_node as AnimatedSprite2D).frame = f
		1:
			var ap = _find_ap()
			if ap:
				if ap.current_animation != _current_anim:
					ap.play(_current_anim)
				ap.seek(float(f) / 60.0, true)
				ap.pause()
		2:
			_apply_cre()

# ============================================
# CRE 帧应用
# ============================================

func _hide_cre():
	if not _preview_root: return
	for c in _preview_root.get_children():
		if c is Sprite2D: c.visible = false

func _apply_cre():
	if _current_anim.is_empty() or not _preview_root: return
	if _current_frame < 0 or _current_frame >= _frame_keys.size(): return
	var ad: Dictionary = _cre_animations.get(_current_anim, {})
	var frames: Dictionary = ad.get("frames", {})
	var actual_key: int = _frame_keys[_current_frame]
	var fd: Dictionary = frames.get(str(actual_key), {})
	var parts: Dictionary = fd.get("parts", {})
	var vis := {}  # {sp_node: true}
	var visible_count := 0
	for spr_name in parts:
		var p: Dictionary = parts[spr_name]
		var sp_node = _cre_part_nodes.get(spr_name)
		if not is_instance_valid(sp_node): continue
		if not _cre_sprites.has(spr_name): continue
		var s: Dictionary = _cre_sprites[spr_name]
		# 基础位置（cx/cy 已在 UFE 侧完成 Y 翻转）
		var pos := Vector2(s.get("cx", 0.0), s.get("cy", 0.0))
		# @scale 还原: PNG 已预缩放 at_scale 倍(名字 @N), 节点乘 1/at_scale 还原完整尺寸
		var at_scale: float = s.get("at_scale", 1.0)
		var inv_at: float = 1.0 / at_scale if at_scale > 0.0 else 1.0
		var sx: float = p.get("sx", 1.0) * inv_at
		var sy: float = p.get("sy", 1.0) * inv_at
		if sx != 1.0 or sy != 1.0:
			# pivot 修正用还原后完整尺寸, 缩放基准为动画原始缩放(sx/inv_at)
			var pw: float = s.get("w", 0.0) * inv_at
			var ph: float = s.get("h", 0.0) * inv_at
			var pivot_x: float = s.get("px", 0.5)
			var pivot_y: float = s.get("py", 0.5)
			pos.x -= (pivot_x - 0.5) * pw * (sx / inv_at - 1.0)
			pos.y -= (pivot_y - 0.5) * ph * (sy / inv_at - 1.0)
		sp_node.position = pos
		sp_node.scale = Vector2(sx, sy)
		sp_node.visible = true
		vis[sp_node] = true
		visible_count += 1
	# 隐藏未出现的碎片
	for sp in _cre_sprite_nodes:
		if not vis.has(sp):
			sp.visible = false
	_frame_label.text = "%d/%d [%d碎片]" % [_current_frame + 1, _total_frames, visible_count]
	_canvas.queue_redraw()

# ============================================
# _process
# ============================================

func _process(delta: float):
	# CRE 模式：等画布大小准备好后定位到第一个碎片
	if _needs_focus and _canvas.size.x > 10 and _canvas.size.y > 10:
		_needs_focus = false
		_focus_first_sprite()
		if not _is_playing:
			set_process(false)
			return
	if not _is_playing or _current_anim.is_empty(): return
	match _render_mode:
		0:
			if _preview_node and _preview_node is AnimatedSprite2D:
				var f: int = (_preview_node as AnimatedSprite2D).frame
				if f != _current_frame:
					_current_frame = f
					_frame_slider.set_value_no_signal(f)
					_frame_label.text = "%d/%d" % [f + 1, _total_frames]
		1:
			var ap = _find_ap()
			if ap:
				if not ap.is_playing():
					if _loop: ap.play(_current_anim)
					else: _stop(); return
				var f: int = int(ap.current_animation_position * 60.0)
				if f != _current_frame:
					_current_frame = f
					_frame_slider.set_value_no_signal(f)
					_frame_label.text = "%d/%d" % [f + 1, _total_frames]
		2:
			var dur: float = 1.0 / _fps
			_frame_timer += delta * _speed
			var actual_key: int = _frame_keys[_current_frame] if _current_frame < _frame_keys.size() else _current_frame
			var extra: float = float(_overrides.get(str(actual_key), 0.0))
			if _frame_timer >= dur + extra:
				_frame_timer -= dur + extra
				var next: int = _current_frame + _play_dir
				if next >= _total_frames:
					if _loop: next = 0
					else: _set_frame(_total_frames - 1); _stop(); return
				elif next < 0:
					if _loop: next = _total_frames - 1
					else: _set_frame(0); _stop(); return
				_set_frame(next)

# ============================================
# 调试 + 定位
# ============================================

func _on_debug_toggled(v: bool):
	_canvas.queue_redraw()

func _on_canvas_draw():
	if not _debug_btn or not _debug_btn.button_pressed: return
	if not _preview_root or not is_instance_valid(_preview_root): return
	var color := Color(0.2, 0.8, 1.0, 0.8)
	var root_pos: Vector2 = _preview_root.position
	var root_scale: float = _preview_root.scale.x
	# 原点十字
	var ox := 12.0
	_canvas.draw_line(root_pos - Vector2(ox, 0), root_pos + Vector2(ox, 0), Color(1, 0.5, 0.2), 2.0)
	_canvas.draw_line(root_pos - Vector2(0, ox), root_pos + Vector2(0, ox), Color(1, 0.5, 0.2), 2.0)
	for c in _preview_root.get_children():
		if c is Sprite2D and c.visible and c.texture:
			var tex_sz: Vector2 = c.texture.get_size()
			var sz: Vector2 = tex_sz * c.scale
			var center: Vector2 = root_pos + c.position * root_scale
			var tl: Vector2 = center - sz * 0.5 * root_scale
			var draw_sz: Vector2 = sz * root_scale
			_canvas.draw_rect(Rect2(tl, draw_sz), color, false, 2.0)
			# 碎片名称标签
			_canvas.draw_string(ThemeDB.fallback_font, tl + Vector2(0, -4), c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
		elif c is Sprite2D and not c.texture:
			# 纹理缺失的碎片用红色标记
			var center: Vector2 = root_pos + c.position * root_scale
			_canvas.draw_circle(center, 5.0, Color(1, 0, 0))

func _focus_first_sprite():
	if not _preview_root or not is_instance_valid(_preview_root): return
	# 先触发一次 CRE 渲染，确保碎片位置已设置
	if _render_mode == 2 and _has_ufe_data:
		_apply_cre()
	var canvas_sz: Vector2 = _canvas.size
	if canvas_sz.x < 10 or canvas_sz.y < 10:
		return
	for c in _preview_root.get_children():
		if c is Sprite2D and c.visible:
			_root_pos = canvas_sz * 0.5 / _canvas_zoom - c.position
			_apply_transform()
			return
