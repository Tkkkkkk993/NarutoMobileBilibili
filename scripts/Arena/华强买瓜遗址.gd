extends Sprite2D

var bgm: AudioStream

func _ready() -> void:
	bgm = preload("res://assets/audio/Music/征服十字路.ogg")
	AudioManager.play_music(bgm)
