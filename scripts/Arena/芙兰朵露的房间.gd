extends Sprite2D

var bgm: AudioStream

func _ready() -> void:
	bgm = preload("res://assets/audio/Music/U.N.OWEN就是她吗？交响摇滚版.ogg")
	AudioManager.play_music(bgm)
