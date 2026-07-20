extends AnimatedSprite2DEntity

func _ready():
	res_path = "res://assets/entities/三方封印/main.tres"
	enable_wall_collision = false
	super._ready()
	is_invincible = true
	effects_container.register_effects({
		"blunt": preload("res://assets/entities/base/effects/blunt/effects_base.tscn"),
	})

func _post_init():
	position_3d.x += 300 * facing_direction
	position_3d.z = 300
	_update_visual_position()
	play_animation("attack2")
	apply_z_impulse(0)
	set_slide_gravity(2000)
	velocity_3d.z = -400
	
	while position_3d.z > 0:
		await get_tree().process_frame # 等待下一帧
	camera.start_pulse_zoom(0.05, 6.0, DuelCamera.PulseWaveform.SQUARE, 0.2)
	
	play_animation("attack")
	await get_tree().create_timer(2).timeout
	
	die()

func _on_attack_hit(hit_result: AttackBoxManager.HitResult):
	var target: EntityBase = hit_result.target
	var target_config = hit_result.hitbox_data
	var box_id = hit_result.attack_box_id
	var box_name = hit_result.attack_box_name
	var box_config = hit_result.attack_config
	
	var hit_eff_pos = calculate_intersection(hit_result, box_config.to_dict())
	
	if box_name == "attack":
		var ipos: Vector3 = Vector3.ZERO
		ipos.x = position_3d.x
		ipos.y = position_3d.y
		target.set_immobilize(ipos, 2, get_out_of_wall(ipos), "launched", Vector2.ZERO, 0, 300)
		target.change_hp(-20000)
