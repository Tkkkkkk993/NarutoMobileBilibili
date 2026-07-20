extends Node


#func _input(event: InputEvent) -> void:
	#if event.is_action_pressed("move_left"):
		#$HpRed.value -= randf_range(1.0, 20.0)
	#elif event.is_action_pressed("move_right"):
		#$HpRed.value += randf_range(1.0, 20.0)
