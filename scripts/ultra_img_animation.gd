extends Node2D

@export var voice: AudioStream

func play():
	$AnimationPlayer.play("Normal")
	if voice:
		AudioManager.play_sound(voice, "Voice")
