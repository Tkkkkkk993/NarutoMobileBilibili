extends Node2D

func play(name: String):
	$AnimationPlayer.play("RESET")
	await $AnimationPlayer.animation_finished  # 等待这一帧播完
	$AnimationPlayer.play(name)
