extends AnimatedSprite2DEntity

func _ready():
	res_path = "res://assets/entities/大运重卡/main.tres"
	enable_wall_collision = false
	aux_cd_value = 20
	super._ready()
	is_invincible = true
	position_3d.x = -2000
	_update_visual_position()
	effects_container.register_effects({
		"blunt": preload("res://assets/entities/base/effects/blunt/effects_base.tscn"),
	})

func _post_init():
	position_3d.x = -1300 * facing_direction
	play_animation("attack")
	
	start_slide(3000, Vector2(facing_direction, 0), 0.0)
	
	await get_tree().create_timer(3).timeout
	die()

func _on_attack_hit(hit_result: AttackBoxManager.HitResult):
	var target: EntityBase = hit_result.target
	var target_config = hit_result.hitbox_data
	var box_id = hit_result.attack_box_id
	var box_name = hit_result.attack_box_name
	var box_config = hit_result.attack_config
	
	var hit_eff_pos = calculate_intersection(hit_result, box_config.to_dict())
	
	if box_name == "attack":
		target.hit(HitStateType.LAUNCH, Vector2(0, 0), 0.5, 350, true, true, BodyState.HARD)
		target.set_hit_stop(0.2)
		
		effects_container.spawn_effect(
			"blunt",
			Vector3(hit_eff_pos.x, position_3d.y, hit_eff_pos.y),
			facing_direction < 0
		)
		
		target.change_hp(-300000)
