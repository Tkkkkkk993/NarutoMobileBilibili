extends Sprite2D

var bgm: AudioStream

func _ready() -> void:
	if MatchConfig.current_mode == MatchConfig.GameMode.TEST:
		return  # 测试模式下不播放音乐
	bgm = preload("res://assets/audio/Music/终极战斗序曲.ogg")
	AudioManager.play_music(bgm)
