extends Sprite2D

var bgm: AudioStream

func _ready() -> void:
	bgm = preload("res://assets/audio/Music/最强大脑之战.ogg")
	AudioManager.play_music(bgm)
