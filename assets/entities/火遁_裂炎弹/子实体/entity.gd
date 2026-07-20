extends AnimatedSprite2DEntity

var et: EntityBase

func _ready():
	res_path = "res://assets/entities/火遁_裂炎弹/子实体/main.tres"
	enable_wall_collision = false
	aux_cd_value = 20
	super._ready()
	is_invincible = true
	effects_container.register_effects({
		"blunt": preload("res://assets/entities/base/effects/blunt/effects_base.tscn"),
	})

func _post_init():
	play_animation("attack")
	
	if !et:
		die()
		return
	
	var mpos: Vector2
	mpos.x = et.position_3d.x
	mpos.y = et.position_3d.y
	set_magnetism(mpos, Vector2(1500, 1500), 2)
	
	while abs(mpos.x-position_3d.x) > 1 or abs(mpos.y-position_3d.y) > 1:
		await get_tree().process_frame # 等待下一帧
		mpos.x = et.position_3d.x
		mpos.y = et.position_3d.y
		set_magnetism(mpos, Vector2(1500, 1500), 2)
	
	await get_tree().create_timer(0.2).timeout
	
	die()

func _on_attack_hit(hit_result: AttackBoxManager.HitResult):
	var target: EntityBase = hit_result.target
	var target_config = hit_result.hitbox_data
	var box_id = hit_result.attack_box_id
	var box_name = hit_result.attack_box_name
	var box_config = hit_result.attack_config
	
	var hit_eff_pos = calculate_intersection(hit_result, box_config.to_dict())
	
	if box_name == "attack":
		var dxv = 500
		if target.position_3d.x < position_3d.x:
			dxv = -500
		target.hit(HitStateType.PUSH, Vector2(dxv, 0), 0.5, 140, false, false, BodyState.HARD)
		
		effects_container.spawn_effect(
			"blunt",
			Vector3(hit_eff_pos.x, position_3d.y, hit_eff_pos.y),
			facing_direction < 0
		)
		
		target.change_hp(-15000)
		
		die()
