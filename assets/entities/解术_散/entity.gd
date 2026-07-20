extends AnimatedSprite2DEntity

func _ready():
	res_path = "res://assets/entities/解术_散/main.tres"
	enable_wall_collision = false
	aux_cd_value = 25
	super._ready()
	is_invincible = true

func _post_init():
	var cfg = EntityManager.EntityConfig.new(
		name + "_子实体1",
		"res://assets/entities/解术_散/子实体/entity.tscn",
		get_2d_pos(),
		team_id,
		facing_direction
	)
	var ee = entity_manager.spawn_entity_runtime(cfg)
	ee.parent_entity = self
	
	await get_tree().create_timer(0.1).timeout
	
	var cfg2 = EntityManager.EntityConfig.new(
		name + "_子实体2",
		"res://assets/entities/解术_散/子实体/entity.tscn",
		get_2d_pos(),
		team_id,
		facing_direction
	)
	var ee2 = entity_manager.spawn_entity_runtime(cfg2)
	ee2.parent_entity = self
	
	die()
