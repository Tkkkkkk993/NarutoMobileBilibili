extends Sprite2D

var bgm: AudioStream

func _ready() -> void:
	bgm = preload("res://assets/audio/Music/终极战斗序曲.ogg")
	AudioManager.play_music(bgm)
