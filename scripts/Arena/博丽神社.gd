extends Sprite2D

var bgm: AudioStream

func _ready() -> void:
	bgm = preload("res://assets/audio/Music/世界如此可爱.ogg")
	AudioManager.play_music(bgm)
