extends Node

enum Bus {
	MASTER,
	MUSIC,
	SFX,
	VOICE
}

const MUSIC_BUS = "Music"
const SFX_BUS = "SFX"
const VOICE_BUS = "Voice"

# 音乐播放器数量
var music_audio_player_count: int = 3
var current_music_player_index: int = 0
var music_players: Array[AudioStreamPlayer] = []

# 音效播放器数量
var sfx_player_count: int = 10
var sfx_players: Array[AudioStreamPlayer] = []

# 语音播放器数量
var voice_player_count: int = 5
var voice_players: Array[AudioStreamPlayer] = []

# 渐变时长
var fade_duration: float = 1.0

func _ready() -> void:
	init_music_audio_manager()
	init_sfx_audio_manager()
	init_voice_audio_manager()

func init_music_audio_manager() -> void:
	for i in range(music_audio_player_count):
		var player = AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		music_players.append(player)

func init_sfx_audio_manager() -> void:
	for i in range(sfx_player_count):
		var player = AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		sfx_players.append(player)

func init_voice_audio_manager() -> void:
	for i in range(voice_player_count):
		var player = AudioStreamPlayer.new()
		player.bus = VOICE_BUS
		add_child(player)
		voice_players.append(player)

# 播放背景音乐（交替播放，支持渐入渐出）
func play_music(stream: AudioStream) -> void:
	if music_players[current_music_player_index].stream == stream and music_players[current_music_player_index].playing:
		return
	
	var next_index = (current_music_player_index + 1) % music_audio_player_count
	
	fade_out(music_players[current_music_player_index])
	
	var next_player = music_players[next_index]
	next_player.stream = stream
	fade_in(next_player)
	
	current_music_player_index = next_index

# 标记 → AudioStreamPlayer 映射（用于按标记停止）
var _tagged_players: Dictionary = {}

# 通用播放音效/语音
# bus_name: "SFX" 或 "Voice"
# random_pitch: 是否随机音调 (0.9~1.1)
# tag: 播放标记，可用于停止特定音效/语音
# volume: 音量 (0.0~1.0)
func play_sound(stream: AudioStream, bus_name: String = "SFX", random_pitch: bool = false, tag: String = "", volume: float = 1.0) -> void:
	var players: Array[AudioStreamPlayer]
	
	match bus_name:
		"SFX":
			players = sfx_players
		"Voice":
			players = voice_players
		_:
			push_error("[AudioManager] Invalid bus name: " + bus_name)
			return
	
	# 如果已有相同标记的播放器，先用它（避免重复开新通道）
	if tag != "" and _tagged_players.has(tag):
		var old = _tagged_players[tag]
		if old and is_instance_valid(old) and old in players:
			old.stop()
			old.stream = stream
			old.pitch_scale = randf_range(0.9, 1.1) if random_pitch else 1.0
			old.volume_db = linear_to_db(clampf(volume, 0.0, 1.0))
			old.play()
			return
	
	for player in players:
		if not player.playing:
			player.stream = stream
			player.pitch_scale = randf_range(0.9, 1.1) if random_pitch else 1.0
			player.volume_db = linear_to_db(clampf(volume, 0.0, 1.0))
			player.play()
			if tag != "":
				_tagged_players[tag] = player
			return

# 便捷方法 - 播放音效
func play_sfx(stream: AudioStream, random_pitch: bool = false, tag: String = "", volume: float = 1.0) -> void:
	play_sound(stream, "SFX", random_pitch, tag, volume)

# 便捷方法 - 播放语音
func play_voice(stream: AudioStream, random_pitch: bool = false, tag: String = "", volume: float = 1.0) -> void:
	play_sound(stream, "Voice", random_pitch, tag, volume)

# 按标记停止音效
func stop_sfx_by_tag(tag: String) -> void:
	_stop_tagged(tag, sfx_players)

# 按标记停止语音
func stop_voice_by_tag(tag: String) -> void:
	_stop_tagged(tag, voice_players)

func _stop_tagged(tag: String, players: Array) -> void:
	if not _tagged_players.has(tag):
		return
	var player = _tagged_players[tag]
	if player and is_instance_valid(player) and player in players:
		player.stop()
		player.stream = null
	_tagged_players.erase(tag)

# 停止所有音效
func stop_all_sfx() -> void:
	_stop_all(sfx_players)

# 停止所有语音
func stop_all_voices() -> void:
	_stop_all(voice_players)

func _stop_all(players: Array) -> void:
	for player in players:
		player.stop()
		player.stream = null
	# 清理相关标记
	var to_remove = []
	for tag in _tagged_players:
		if _tagged_players[tag] in players:
			to_remove.append(tag)
	for tag in to_remove:
		_tagged_players.erase(tag)

# 设置总线音量 (value: 0.0 ~ 1.0)
func set_bus_volume(bus_index: Bus, value: float) -> void:
	var bus_name: String
	match bus_index:
		Bus.MASTER:
			bus_name = "Master"
		Bus.MUSIC:
			bus_name = MUSIC_BUS
		Bus.SFX:
			bus_name = SFX_BUS
		Bus.VOICE:
			bus_name = VOICE_BUS
	
	var db = linear_to_db(value)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus_name), db)

# 渐入效果
func fade_in(player: AudioStreamPlayer, duration: float = -1.0) -> void:
	if duration < 0.0:
		duration = fade_duration
	player.volume_db = -40.0
	player.play()
	var tween = create_tween()
	tween.tween_property(player, "volume_db", 0.0, duration)

# 渐出效果（结束后停止并清空音频）
func fade_out(player: AudioStreamPlayer, duration: float = -1.0) -> void:
	if duration < 0.0:
		duration = fade_duration
	var tween = create_tween()
	tween.tween_property(player, "volume_db", -40.0, duration)
	tween.tween_callback(func():
		player.stop()
		player.stream = null
	)

# ==================== 语音播报系统 ====================
var voice_descriptions: Dictionary = {}
var current_voice_pack: String = "SenjuHashirama"  # 当前语音包名称
var is_playing_sequence: bool = false

func _init():
	load_voice_descriptions()

# 获取当前语音包路径
func get_voice_pack_path() -> String:
	return "res://assets/audio/VoiceAnnouncement/" + current_voice_pack + "/"

# 切换语音包
func set_voice_pack(pack_name: String) -> void:
	current_voice_pack = pack_name
	load_voice_descriptions()
	print("[AudioManager] 切换语音包: " + pack_name)

# 加载语音描述文件
func load_voice_descriptions() -> void:
	var file_path = get_voice_pack_path() + "voice_descriptions.json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			var json = JSON.new()
			var parse_result = json.parse(json_text)
			if parse_result == OK:
				voice_descriptions = json.data.get("voice_library", {})
				print("[AudioManager] 语音描述文件加载成功: " + current_voice_pack)
			else:
				push_error("[AudioManager] 语音描述文件解析失败: " + json.get_error_message())
	else:
		push_warning("[AudioManager] 语音描述文件不存在: " + file_path)

# 根据语音ID播放语音
func play_voice_by_id(voice_id: String) -> void:
	if not voice_descriptions.has(voice_id):
		push_error("[AudioManager] 未找到语音ID: " + voice_id)
		return

	var voice_data = voice_descriptions[voice_id]
	var audio = voice_data.get("audio")
	var mode = voice_data.get("mode", "single")

	if audio is Array:
		match mode:
			"random":
				play_voice_random(audio, get_voice_pack_path())
			"sequence", _:
				play_voice_sequence(audio, get_voice_pack_path())
	else:
		var audio_path = get_voice_pack_path() + audio
		var stream = load(audio_path)
		if stream:
			play_voice(stream)

# 播放语音表达式（支持 + 和 random）
# 示例:
#   "round_2" - 播放单个语音
#   "round_final + battle_start" - 先后播放两个语音
#   "random(winner_decided)" - 随机播放winner_decided中的音频
#   "round_1 + random(winner_decided)" - 组合使用
func play_voice_expression(expression: String) -> void:
	if expression.strip_edges() == "":
		return

	# 解析表达式
	var sequence = parse_expression(expression)

	# 播放序列
	if sequence.size() > 0:
		await play_expression_sequence(sequence)

# 解析表达式，返回语音ID数组
func parse_expression(expression: String) -> Array:
	var result = []
	var tokens = expression.split("+")

	for token in tokens:
		token = token.strip_edges()

		# 检查是否是random表达式
		if token.begins_with("random(") and token.ends_with(")"):
			var voice_id = token.substr(7, token.length() - 8).strip_edges()
			result.append({"type": "random", "id": voice_id})
		else:
			result.append({"type": "single", "id": token})

	return result

# 播放表达式序列
func play_expression_sequence(sequence: Array) -> void:
	is_playing_sequence = true

	for item in sequence:
		if item.type == "random":
			play_voice_by_id(item.id)
		else:
			play_voice_by_id(item.id)

		# 等待语音播放完成（假设每个语音最长3秒）
		await get_tree().create_timer(0.5).timeout
		while is_voice_playing():
			await get_tree().process_frame

	is_playing_sequence = false

# 检查是否有语音正在播放
func is_voice_playing() -> bool:
	for player in voice_players:
		if player.playing:
			return true
	return false

# 播放音频序列（先后播放）
func play_voice_sequence(audio_files: Array, base_path: String) -> void:
	for audio_file in audio_files:
		var audio_path = base_path + audio_file
		var stream = load(audio_path)
		if stream:
			play_voice(stream)
			# 等待播放完成
			await get_tree().create_timer(0.5).timeout
			while is_voice_playing():
				await get_tree().process_frame

# 随机播放音频
func play_voice_random(audio_files: Array, base_path: String) -> void:
	var random_index = randi() % audio_files.size()
	var audio_path = base_path + audio_files[random_index]
	var stream = load(audio_path)
	if stream:
		play_voice(stream)

# 获取当前语音包的所有音频文件路径
func get_voice_pack_audio_paths() -> Array:
	var paths = []
	var base_path = get_voice_pack_path()

	for voice_id in voice_descriptions.keys():
		var voice_data = voice_descriptions[voice_id]
		var audio = voice_data.get("audio")

		if audio is Array:
			for audio_file in audio:
				paths.append(base_path + audio_file)
		else:
			paths.append(base_path + audio)

	return paths
