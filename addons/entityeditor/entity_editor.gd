@tool
extends Control

var _current_entity_instance: Node = null
var _entity_container: Control = null
var _current_entity_scene_path: String = ""
var _frame_editor_instance: Window = null
var _attack_box_editor_instance: Window = null
var _info_point_editor_instance: Window = null
var _effect_binder_editor_instance: Window = null
var _visual_script_editor_instance: Window = null

func _ready():
	_create_entity_container()
	_add_editor_buttons()
	_update_window_title()

func _create_entity_container():
	if _entity_container == null or not is_instance_valid(_entity_container):
		_entity_container = Control.new()
		_entity_container.name = "EntityContainer"
		_entity_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_entity_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_entity_container.z_index = -1
		
		add_child(_entity_container)
		move_child(_entity_container, 0)
		print("创建实体容器: ", _entity_container.name)

func _add_editor_buttons():
	var button_container = $ToolContainer
	
	# 加载实体按钮
	var load_btn = Button.new()
	load_btn.text = "加载实体"
	load_btn.custom_minimum_size = Vector2(120, 40)
	load_btn.pressed.connect(_on_load_entity_pressed)
	button_container.add_child(load_btn)
	
	# 帧编辑器按钮
	var frame_btn = Button.new()
	frame_btn.text = "编辑帧数据"
	frame_btn.custom_minimum_size = Vector2(120, 40)
	frame_btn.pressed.connect(_on_frame_edit_pressed)
	button_container.add_child(frame_btn)
	
	# 攻击框编辑器按钮
	var attack_btn = Button.new()
	attack_btn.text = "编辑攻击框"
	attack_btn.custom_minimum_size = Vector2(120, 40)
	attack_btn.pressed.connect(_on_attack_box_edit_pressed)
	button_container.add_child(attack_btn)
	
	# 信息点编辑器按钮
	var info_btn = Button.new()
	info_btn.text = "编辑信息点"
	info_btn.custom_minimum_size = Vector2(120, 40)
	info_btn.pressed.connect(_on_info_point_edit_pressed)
	button_container.add_child(info_btn)
	
	# 特效绑定器按钮
	var effect_binder_btn = Button.new()
	effect_binder_btn.text = "绑定特效"
	effect_binder_btn.custom_minimum_size = Vector2(120, 40)
	effect_binder_btn.pressed.connect(_on_effect_binder_edit_pressed)
	button_container.add_child(effect_binder_btn)
	
	# 图形化脚本编辑器按钮
	var vs_btn = Button.new()
	vs_btn.text = "图形化脚本"
	vs_btn.custom_minimum_size = Vector2(120, 40)
	vs_btn.pressed.connect(_on_visual_script_edit_pressed)
	button_container.add_child(vs_btn)

	# 测试运行按钮（调用 EditorInterface.play_main_scene）
	var test_btn = Button.new()
	test_btn.text = "测试"
	test_btn.custom_minimum_size = Vector2(120, 40)
	test_btn.pressed.connect(_on_test_run_pressed)
	button_container.add_child(test_btn)

func _on_test_run_pressed():
	# 1. 检查是否已加载实体
	if _current_entity_scene_path.is_empty():
		print("未加载实体场景")
		return
	else:
		var dir = DirAccess.open("user://")
		if dir == null:
			DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
		var test_info = {
			"entity_path": _current_entity_scene_path,
			"entity_id": _current_entity_scene_path.get_base_dir().get_file()
		}
		# 打开文件（检查返回值）
		var file = FileAccess.open("user://test_mode.json", FileAccess.WRITE)
		if file == null:
			print("无法打开文件 user://test_mode.json，错误代码: ", FileAccess.get_open_error())
			return
		file.store_string(JSON.stringify(test_info))
		file.close()
		print("测试数据已写入 user://test_mode.json")
	
	# 3. 运行主场景
	EditorInterface.play_main_scene()

func _on_load_entity_pressed():
	var window = Window.new()
	window.title = "输入实体场景路径"
	window.size = Vector2(400, 150)
	window.min_size = Vector2(300, 120)
	window.max_size = Vector2(600, 200)
	window.exclusive = true
	window.unresizable = false
	window.transient = true
	window.wrap_controls = true
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	
	var label = Label.new()
	label.text = "实体场景路径:"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var line_edit = LineEdit.new()
	line_edit.custom_minimum_size = Vector2(300, 40)
	line_edit.placeholder_text = "res://assets/entities/.../entity.tscn"
	
	var button_hbox = HBoxContainer.new()
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var confirm_button = Button.new()
	confirm_button.text = "确认"
	confirm_button.custom_minimum_size = Vector2(80, 30)
	
	var cancel_button = Button.new()
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(80, 30)
	
	button_hbox.add_child(confirm_button)
	button_hbox.add_child(cancel_button)
	
	vbox.add_child(label)
	vbox.add_spacer(false)
	vbox.add_child(line_edit)
	vbox.add_spacer(false)
	vbox.add_child(button_hbox)
	
	window.add_child(vbox)
	add_child(window)
	window.popup_centered()
	
	await get_tree().process_frame
	line_edit.grab_focus()
	
	confirm_button.pressed.connect(_on_confirm_pressed.bind(line_edit, window))
	cancel_button.pressed.connect(_on_cancel_pressed.bind(window))
	line_edit.text_submitted.connect(_on_text_submitted.bind(line_edit, window))
	window.close_requested.connect(_on_window_closed.bind(window))

func _on_confirm_pressed(line_edit: LineEdit, window: Window):
	var input_text = line_edit.text.strip_edges()
	if input_text != "":
		_load_and_instantiate_scene(input_text)
		window.queue_free()
	else:
		line_edit.placeholder_text = "请输入有效的路径！"
		line_edit.text = ""
		line_edit.grab_focus()

func _load_and_instantiate_scene(scene_path: String):
	if not FileAccess.file_exists(scene_path):
		print("错误：文件不存在 - ", scene_path)
		return
	
	var scene = load(scene_path)
	if scene == null:
		print("错误：无法加载场景 - ", scene_path)
		return
	
	var instance = scene.instantiate()
	if instance == null:
		print("错误：无法实例化场景")
		return
	
	if instance.name != "Entity":
		print("根节点名称不是 'Entity'")
		instance.queue_free()
		return
	
	_clear_previous_instance()
	_create_entity_container()
	
	instance.name = "EntityInstance"
	instance.position = _entity_container.size / 2
	
	_entity_container.add_child(instance)
	_current_entity_instance = instance
	_current_entity_scene_path = scene_path
	_update_window_title()
	
	print("场景已成功实例化: ", scene_path)


func _update_window_title():
	var win = get_window()
	if not win:
		return
	var base = "实体编辑器"
	if _current_entity_scene_path != "":
		var trimmed = _current_entity_scene_path.trim_prefix("res://assets/entities/")
		var last_slash = trimmed.rfind("/")
		var name = trimmed.substr(0, last_slash) if last_slash >= 0 else trimmed
		base += " - " + name
	win.title = base


func _clear_previous_instance():
	if _current_entity_instance != null and is_instance_valid(_current_entity_instance):
		_current_entity_instance.queue_free()
		_current_entity_instance = null
	
	if _entity_container != null and is_instance_valid(_entity_container):
		for child in _entity_container.get_children():
			if child.name == "EntityInstance":
				child.queue_free()

func _on_cancel_pressed(window: Window):
	window.queue_free()

func _on_text_submitted(_text: String, line_edit: LineEdit, window: Window):
	_on_confirm_pressed(line_edit, window)

func _on_window_closed(window: Window):
	window.queue_free()

func _on_frame_edit_pressed():
	if _current_entity_instance == null:
		print("请先加载实体场景")
		return
	
	var visual_node = _get_visual_node(_current_entity_instance)
	if visual_node == null:
		print("未找到视觉节点（AnimatedSprite2D 或 Visuals）")
		return
	
	var frame_editor_scene = load("res://addons/entityeditor/frame_editor.tscn")
	if frame_editor_scene:
		var frame_editor = frame_editor_scene.instantiate()
		add_child(frame_editor)
		frame_editor.setup_entity(_current_entity_instance, visual_node, _current_entity_scene_path)
		_frame_editor_instance = frame_editor
		print("帧编辑器已打开")
	else:
		print("错误：无法加载帧编辑器场景")

func _on_attack_box_edit_pressed():
	if _current_entity_instance == null:
		print("请先加载实体场景")
		return
	
	var visual_node = _get_visual_node(_current_entity_instance)
	if visual_node == null:
		print("未找到视觉节点（AnimatedSprite2D 或 Visuals）")
		return
	
	# 关闭之前的编辑器
	if _attack_box_editor_instance and is_instance_valid(_attack_box_editor_instance):
		_attack_box_editor_instance.queue_free()
	
	var editor_scene = load("res://addons/entityeditor/attack_box_editor.tscn")
	if editor_scene:
		var editor = editor_scene.instantiate()
		add_child(editor)
		editor.setup(_current_entity_instance, visual_node, _current_entity_scene_path)
		_attack_box_editor_instance = editor
		print("攻击框编辑器已打开")
	else:
		print("错误：无法加载攻击框编辑器场景")

func _find_animated_sprite(node: Node) -> AnimatedSprite2D:
	# 1. 优先按固定路径查找
	if node.has_node("Visuals/AnimatedSprite2D"):
		return node.get_node("Visuals/AnimatedSprite2D") as AnimatedSprite2D
	if node is AnimatedSprite2D:
		return node as AnimatedSprite2D

	# 2. 尝试通过 EntityBase API 获取（仅当脚本为工具且非占位符）
	if node is EntityBase and node.has_method("get_animator_node"):
		var script = node.get_script()
		# 检查脚本是否有效且标记为 @tool
		if script != null and script.is_tool():
			var anim_node = (node as EntityBase).get_animator_node()
			if anim_node is AnimatedSprite2D:
				return anim_node
		# 若非工具脚本，则跳过方法调用，继续遍历

	# 3. 递归遍历子节点（兜底方案）
	for child in node.get_children():
		var found = _find_animated_sprite(child)
		if found:
			return found

	return null

## 获取实体的视觉参考节点（兼容 AnimatedSprite2DEntity 和 AnimationPlayerEntity）
## 返回用于编辑器预览的 Node2D 节点
func _get_visual_node(entity: Node) -> Node2D:
	# AnimatedSprite2DEntity: 直接返回 AnimatedSprite2D
	var sprite = _find_animated_sprite(entity)
	if sprite:
		return sprite
	
	# AnimationPlayerEntity: 返回 visuals_node（包含 3D 模型/骨骼的容器）
	if entity is EntityBase and is_instance_valid((entity as EntityBase).visuals_node):
		return (entity as EntityBase).visuals_node
	
	# 兜底：递归查找 Visuals 节点
	if entity.has_node("Visuals"):
		var visuals = entity.get_node("Visuals")
		if visuals is Node2D:
			return visuals
	
	# 最终兜底
	if entity is Node2D:
		return entity
	return null

## 获取实体的动画控制器（EntityBase 实例，提供统一的动画 API）
func _get_animation_entity(entity: Node) -> EntityBase:
	if entity is EntityBase:
		return entity
	return null

## 获取实体的精灵缩放（用于编辑器中的锚点补偿计算）
func _get_sprite_scale_for_editor(entity: Node) -> Vector2:
	var sprite = _find_animated_sprite(entity)
	if sprite:
		return sprite.scale
	# AnimationPlayerEntity: 使用实体自身的 get_anim_sprite_scale()
	if entity is EntityBase and entity.has_method("get_anim_sprite_scale"):
		return (entity as EntityBase).get_anim_sprite_scale()
	return Vector2.ONE

## 获取当前实体的视觉参考节点（兼容）
func _get_entity_visuals_ref() -> Node:
	"""返回可用于编辑器预览的视觉节点"""
	if _current_entity_instance is EntityBase and _current_entity_instance.has_method("get_animator_node"):
		var e = _current_entity_instance as EntityBase
		return e.visuals_node if e.visuals_node else _current_entity_instance
	return _current_entity_instance

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		if _current_entity_instance != null and is_instance_valid(_current_entity_instance):
			await get_tree().process_frame
			_current_entity_instance.position = _entity_container.size / 2

func _exit_tree():
	if _frame_editor_instance and is_instance_valid(_frame_editor_instance):
		_frame_editor_instance.queue_free()
	if _attack_box_editor_instance and is_instance_valid(_attack_box_editor_instance):
		_attack_box_editor_instance.queue_free()
	if _info_point_editor_instance and is_instance_valid(_info_point_editor_instance):
		_info_point_editor_instance.queue_free()
	if _effect_binder_editor_instance and is_instance_valid(_effect_binder_editor_instance):
		_effect_binder_editor_instance.queue_free()
	if _visual_script_editor_instance and is_instance_valid(_visual_script_editor_instance):
		_visual_script_editor_instance.queue_free()
	if _current_entity_instance != null and is_instance_valid(_current_entity_instance):
		_current_entity_instance.queue_free()
	if _entity_container != null and is_instance_valid(_entity_container):
		_entity_container.queue_free()

func _on_info_point_edit_pressed():
	if _current_entity_instance == null:
		print("请先加载实体场景")
		return
	var visual_node = _get_visual_node(_current_entity_instance)
	if visual_node == null:
		print("未找到视觉节点（AnimatedSprite2D 或 Visuals）")
		return
		
	# 关闭之前的编辑器
	if _info_point_editor_instance and is_instance_valid(_info_point_editor_instance):
		_info_point_editor_instance.queue_free()
		
	# 稳健的纯代码实例化方式
	var editor_script = load("res://addons/entityeditor/info_point_editor.gd")
	if editor_script:
		var editor = Window.new()
		editor.script = editor_script
		add_child(editor)
		
		# 等待一帧，确保脚本已完全附加并编译生效
		await get_tree().process_frame
		
		editor.setup(_current_entity_instance, visual_node, _current_entity_scene_path)
		_info_point_editor_instance = editor
		print("信息点编辑器已打开")
	else:
		print("错误：无法加载信息点编辑器脚本")

func _on_effect_binder_edit_pressed():
	if _current_entity_instance == null:
		print("请先加载实体场景")
		return
	var visual_node = _get_visual_node(_current_entity_instance)
	if visual_node == null:
		print("未找到视觉节点（AnimatedSprite2D 或 Visuals）")
		return
	
	# 关闭之前的编辑器
	if _effect_binder_editor_instance and is_instance_valid(_effect_binder_editor_instance):
		_effect_binder_editor_instance.queue_free()
	
	var editor_script = load("res://addons/entityeditor/effect_binder_editor.gd")
	if editor_script:
		var editor = Window.new()
		editor.script = editor_script
		add_child(editor)
		await get_tree().process_frame
		editor.setup(_current_entity_instance, visual_node, _current_entity_scene_path)
		_effect_binder_editor_instance = editor
		print("特效绑定器已打开")
	else:
		print("错误：无法加载特效绑定器脚本")

func _on_visual_script_edit_pressed():
	if _current_entity_instance == null:
		print("请先加载实体场景")
		return

	if _visual_script_editor_instance and is_instance_valid(_visual_script_editor_instance):
		_visual_script_editor_instance.queue_free()

	var editor_script = load("res://addons/entityeditor/visual_script_editor.gd")
	if editor_script:
		var editor = Window.new()
		editor.script = editor_script
		add_child(editor)
		# 等一帧让 @tool 脚本的 _ready 执行完成，再调用 setup
		await get_tree().process_frame
		editor.setup(_current_entity_instance, _current_entity_scene_path)
		_visual_script_editor_instance = editor
		print("图形化脚本编辑器已打开")
	else:
		print("错误：无法加载图形化脚本编辑器场景")
