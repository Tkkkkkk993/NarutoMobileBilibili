extends Control

@onready var progress_bar = $TextureProgressBar
@onready var black_screen = $BlackScreen
@onready var portraits: Array[TextureRect] = [
	$Portrait1,
	$Portrait2
]

func _ready():
	portraits[0].texture = load(
		"res://assets/entities/%s/portraits/idle.png"
		% MatchConfig.p1_current_char
	)
	portraits[1].texture = load(
		"res://assets/entities/%s/portraits/idle.png"
		% MatchConfig.p2_current_char
	)
	
	progress_bar.value = 0
	LoadingManager.progress_updated.connect(_on_progress_updated)
	LoadingManager.load_finished.connect(_on_load_finished)
	
	var load_list = _build_load_list()
	LoadingManager.start_loading(load_list)

func _build_load_list() -> Array:
	var list = []

	list.append("res://scenes/arena.tscn")
	list.append(
		"res://assets/entities/%s/entity.tscn"
		% MatchConfig.p1_current_char
	)
	list.append(
		"res://assets/entities/%s/entity.tscn"
		% MatchConfig.p2_current_char
	)
	list.append(
		"res://assets/entities/%s/entity.tscn"
		% MatchConfig.p1_current_scroll
	)
	list.append(
		"res://assets/entities/%s/entity.tscn"
		% MatchConfig.p2_current_scroll
	)
	list += MatchConfig.p1_current_summon
	list += MatchConfig.p2_current_summon

	# 预加载实体的资源文件
	list += get_entity_preload_resources(MatchConfig.p1_current_char)
	list += get_entity_preload_resources(MatchConfig.p2_current_char)
	list += get_entity_preload_resources(MatchConfig.p1_current_scroll)
	list += get_entity_preload_resources(MatchConfig.p2_current_scroll)
	for summon_path in MatchConfig.p1_current_summon:
		var entity_folder = summon_path.get_base_dir().get_file()
		list += get_entity_preload_resources(entity_folder)
	for summon_path in MatchConfig.p2_current_summon:
		var entity_folder = summon_path.get_base_dir().get_file()
		list += get_entity_preload_resources(entity_folder)

	if MatchConfig.current_mode == MatchConfig.GameMode.TEST:
		list.append(get_battle_icon_list_solo(MatchConfig.p1_current_char))
		list.append(get_battle_icon_list_solo(MatchConfig.p2_current_char))
	else:
		list += get_battle_icon_list(MatchConfig.get_char_id(1))
		list += get_battle_icon_list(MatchConfig.get_char_id(2))

	list.append(
		"res://scenes/Arena/%s.tscn"
		% MatchConfig.current_map
	)

	# 预加载语音包音频文件
	list += AudioManager.get_voice_pack_audio_paths()

	return list

func get_battle_icon_list(a: Array):
	var b: Array
	for item in a:
		b.append(
			get_battle_icon_list_solo(item)
		)
	return b

func get_battle_icon_list_solo(s: String):
	return "res://assets/entities/%s/portraits/icon_battle.png" % s

func get_entity_preload_resources(entity_name: String) -> Array:
	var preload_list = []
	var config_path = "res://assets/entities/%s/preload_resources.json" % entity_name

	# 检查配置文件是否存在
	if not FileAccess.file_exists(config_path):
		return preload_list

	# 读取配置文件
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_warning("无法打开预加载配置文件: " + config_path)
		return preload_list

	var json_text = file.get_as_text()
	file.close()

	# 解析JSON
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_warning("预加载配置文件JSON解析失败: " + config_path)
		return preload_list

	var data = json.get_data()
	if not data.has("preload"):
		push_warning("预加载配置文件缺少preload字段: " + config_path)
		return preload_list

	# 转换相对路径为完整res://路径
	for relative_path in data["preload"]:
		var full_path = "res://assets/entities/%s/%s" % [entity_name, relative_path]
		preload_list.append(full_path)

	return preload_list

func _on_progress_updated(value: float):
	var target_value = value * 100
	var tween = get_tree().create_tween()
	tween.tween_property(progress_bar, "value", target_value, 0.3)
	
	if value >= 1.0:
		progress_bar.value = 100

func _on_load_finished():
	# 播放加载完成语音
	AudioManager.play_voice_by_id("load_complete")

	# 先让玩家看到满进度条
	await get_tree().create_timer(0.3).timeout

	black_screen.visible = true

	$AnimationPlayer.play("End")

	# 等待黑屏完全盖住画面
	await get_tree().create_timer(1.0).timeout

	# 不让你看到我其实卡爆了哈哈哈哈哈（已修复）
	var battle_scene = LoadingManager.get_resource("res://scenes/arena.tscn")
	get_tree().change_scene_to_packed(battle_scene)

func _exit_tree():
	if LoadingManager.progress_updated.is_connected(_on_progress_updated):
		LoadingManager.progress_updated.disconnect(_on_progress_updated)
	if LoadingManager.load_finished.is_connected(_on_load_finished):
		LoadingManager.load_finished.disconnect(_on_load_finished)
