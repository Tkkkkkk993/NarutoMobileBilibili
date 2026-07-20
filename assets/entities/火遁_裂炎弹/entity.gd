extends AnimatedSprite2DEntity

func _ready():
	res_path = "res://assets/entities/火遁_裂炎弹/main.tres"
	enable_wall_collision = false
	aux_cd_value = 18
	super._ready()
	is_invincible = true

func _post_init():
	await get_tree().create_timer(0.3).timeout
	
	for i in range(8): # 八连火，暂时没有升级机制
		await get_tree().create_timer(0.15).timeout
		var target = get_nearest_valid_enemy_in_range(Vector2(700, 100))
		var cfg = EntityManager.EntityConfig.new(
			name + "_子实体" + str(i),
			"res://assets/entities/火遁_裂炎弹/子实体/entity.tscn",
			get_2d_pos(),
			team_id,
			facing_direction
		)
		var ee = entity_manager.spawn_entity_runtime(cfg)
		ee.parent_entity = self
		ee.et = target
	
	die()
