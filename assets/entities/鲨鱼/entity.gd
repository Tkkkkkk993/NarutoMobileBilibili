extends AnimatedSprite2DEntity

var posx
var et: EntityBase = null

func _ready():
	res_path = "res://assets/entities/鲨鱼/main.tres"
	enable_wall_collision = false
	aux_cd_value = 20
	super._ready()
	is_invincible = true
	effects_container.register_effects({
		"blunt": preload("res://assets/entities/base/effects/blunt/effects_base.tscn"),
	})

func _process(delta):
	animated_sprite.rotation += deg_to_rad(112.5)*delta

func _post_init():
	posx = position_3d.x
	_update_visual_position()
	play_animation("attack")
	start_slide(1170, Vector2(facing_direction, 0), 0.0)
	apply_z_impulse(0)
	set_slide_gravity(1100)
	velocity_3d.z = 750
	animated_sprite.rotation = deg_to_rad(-60)
	camera.start_pulse_zoom(0.05, 6.0, DuelCamera.PulseWaveform.SQUARE, 0.5)
	
	while animated_sprite.rotation < deg_to_rad(60):
		await get_tree().process_frame # 等待下一帧
	camera.start_pulse_zoom(0.05, 6.0, DuelCamera.PulseWaveform.SQUARE, 0.2)
	
	if et:
		et.stop_immobilize()
		
		die()
		return
	
	play_animation("idle")
	await get_tree().create_timer(0.5).timeout
	
	position_3d.x = posx + 400 * facing_direction
	facing_direction = -facing_direction
	play_animation("attack")
	start_slide(1170, Vector2(facing_direction, 0), 0.0)
	apply_z_impulse(0)
	set_slide_gravity(1100)
	velocity_3d.z = 750
	animated_sprite.rotation = deg_to_rad(-60)
	camera.start_pulse_zoom(0.05, 6.0, DuelCamera.PulseWaveform.SQUARE, 0.5)
	
	while animated_sprite.rotation < deg_to_rad(60):
		await get_tree().process_frame # 等待下一帧
	camera.start_pulse_zoom(0.05, 6.0, DuelCamera.PulseWaveform.SQUARE, 0.2)
	
	if et:
		et.stop_immobilize()
	
	die()

func _on_attack_hit(hit_result: AttackBoxManager.HitResult):
	var target: EntityBase = hit_result.target
	var target_config = hit_result.hitbox_data
	var box_id = hit_result.attack_box_id
	var box_name = hit_result.attack_box_name
	var box_config = hit_result.attack_config
	
	var hit_eff_pos = calculate_intersection(hit_result, box_config.to_dict())
	
	if box_name == "a1":
		target.hit(HitStateType.LAUNCH, Vector2(2000 * facing_direction, 0), 0.5, 200, false, false, BodyState.HARD)
		
		effects_container.spawn_effect(
			"blunt",
			Vector3(hit_eff_pos.x, position_3d.y, hit_eff_pos.y),
			facing_direction < 0
		)
		
		target.change_hp(-10000)
	elif box_name == "a2":
		var ipos: Vector3 = Vector3.ZERO
		ipos.x = position_3d.x + 400 * facing_direction
		ipos.y = position_3d.y
		target.set_immobilize(Vector3(0, 114514, 0), -1, get_out_of_wall(ipos), "stun1", Vector2.ZERO, 0, 300)
		if target._immobilize_active:
			et = target
		target.change_hp(-10000)
