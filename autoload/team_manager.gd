extends Node

# ============================================
# 阵营定义
# ============================================

enum TeamID {
	NONE = 0,       # 无阵营（环境物体）
	PLAYER_1 = 1,   # 1P
	PLAYER_2 = 2,   # 2P
	PLAYER_3 = 3,   # 3P（扩展）
	PLAYER_4 = 4,   # 4P（扩展）
	ENEMY = 10,     # 通用敌人
	NEUTRAL = 99    # 中立（可攻击所有人）
}

# 阵营关系类型
enum Relation {
	HOSTILE,        # 敌对（可互相伤害）
	FRIENDLY,       # 友好（不可伤害）
	NEUTRAL_REL,    # 中立（可伤害但无仇恨）
	SAME_TEAM       # 同阵营
}

# 阵营配置数据
var _team_data: Dictionary = {
	TeamID.NONE: {
		"name": "无阵营",
		"color": Color.GRAY,
		"can_damage_self": false
	},
	TeamID.PLAYER_1: {
		"name": "1P",
		"color": Color.BLUE,
		"can_damage_self": false
	},
	TeamID.PLAYER_2: {
		"name": "2P",
		"color": Color.RED,
		"can_damage_self": false
	},
	TeamID.PLAYER_3: {
		"name": "3P",
		"color": Color.GREEN,
		"can_damage_self": false
	},
	TeamID.PLAYER_4: {
		"name": "4P",
		"color": Color.YELLOW,
		"can_damage_self": false
	},
	TeamID.ENEMY: {
		"name": "敌人",
		"color": Color.ORANGE,
		"can_damage_self": false
	},
	TeamID.NEUTRAL: {
		"name": "中立",
		"color": Color.PURPLE,
		"can_damage_self": true
	}
}

# 阵营关系矩阵（可动态修改）
var _relation_matrix: Dictionary = {}

# 所有注册的单位
var _entities_by_team: Dictionary = {}

# 友军伤害开关（全局）
var friendly_fire_enabled: bool = false

# ============================================
# 初始化
# ============================================

func _ready():
	_init_default_relations()
	_init_entity_storage()

func _init_default_relations():
	"""初始化默认阵营关系"""
	# 玩家之间：敌对（PvP）
	_set_relation(TeamID.PLAYER_1, TeamID.PLAYER_2, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_2, TeamID.PLAYER_1, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_1, TeamID.PLAYER_3, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_3, TeamID.PLAYER_1, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_1, TeamID.PLAYER_4, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_4, TeamID.PLAYER_1, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_2, TeamID.PLAYER_3, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_3, TeamID.PLAYER_2, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_2, TeamID.PLAYER_4, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_4, TeamID.PLAYER_2, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_3, TeamID.PLAYER_4, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_4, TeamID.PLAYER_3, Relation.HOSTILE)
	
	# 玩家与敌人：敌对
	_set_relation(TeamID.PLAYER_1, TeamID.ENEMY, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_2, TeamID.ENEMY, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_3, TeamID.ENEMY, Relation.HOSTILE)
	_set_relation(TeamID.PLAYER_4, TeamID.ENEMY, Relation.HOSTILE)
	_set_relation(TeamID.ENEMY, TeamID.PLAYER_1, Relation.HOSTILE)
	_set_relation(TeamID.ENEMY, TeamID.PLAYER_2, Relation.HOSTILE)
	_set_relation(TeamID.ENEMY, TeamID.PLAYER_3, Relation.HOSTILE)
	_set_relation(TeamID.ENEMY, TeamID.PLAYER_4, Relation.HOSTILE)
	
	# 敌人之间：友好（不互相攻击，或改为HOSTILE让它们内斗）
	_set_relation(TeamID.ENEMY, TeamID.ENEMY, Relation.FRIENDLY)
	
	# 中立与所有人：中立（可攻击但无阵营仇恨）
	for team in TeamID.values():
		_set_relation(TeamID.NEUTRAL, team, Relation.NEUTRAL_REL)
		_set_relation(team, TeamID.NEUTRAL, Relation.NEUTRAL_REL)

func _init_entity_storage():
	"""初始化实体存储字典"""
	for team_id in TeamID.values():
		_entities_by_team[team_id] = []

# ============================================
# 关系管理
# ============================================

func _set_relation(team_a: int, team_b: int, relation: int):
	"""设置两个阵营之间的关系"""
	var key = _get_relation_key(team_a, team_b)
	_relation_matrix[key] = relation

func get_relation(team_a: int, team_b: int) -> int:
	"""获取两个阵营之间的关系"""
	if team_a == team_b:
		return Relation.SAME_TEAM
	
	var key = _get_relation_key(team_a, team_b)
	return _relation_matrix.get(key, Relation.HOSTILE)  # 默认敌对

func _get_relation_key(a: int, b: int) -> String:
	"""生成关系字典的key"""
	return "%d_%d" % [a, b]

func set_friendly_fire(enabled: bool):
	"""设置友军伤害开关"""
	friendly_fire_enabled = enabled

func set_relation(team_a: int, team_b: int, relation: int):
	"""动态设置阵营关系（运行时修改）"""
	_set_relation(team_a, team_b, relation)

# ============================================
# 实体注册管理
# ============================================

func register_entity(entity: Node, team_id: int):
	"""注册实体到阵营"""
	if not _entities_by_team.has(team_id):
		_entities_by_team[team_id] = []
	
	if not entity in _entities_by_team[team_id]:
		_entities_by_team[team_id].append(entity)
		# 连接删除信号，自动清理
		if not entity.tree_exiting.is_connected(_on_entity_removed):
			entity.tree_exiting.connect(_on_entity_removed.bind(entity, team_id))

func unregister_entity(entity: Node, team_id: int):
	"""从阵营移除实体"""
	if _entities_by_team.has(team_id):
		_entities_by_team[team_id].erase(entity)

func _on_entity_removed(entity: Node, team_id: int):
	"""实体被删除时的回调"""
	unregister_entity(entity, team_id)

func get_entities_by_team(team_id: int) -> Array:
	"""获取某阵营的所有实体"""
	return _entities_by_team.get(team_id, []).duplicate()

func get_all_enemies_of(team_id: int) -> Array:
	"""获取某阵营的所有敌对实体"""
	var enemies = []
	for other_team in _entities_by_team.keys():
		if get_relation(team_id, other_team) == Relation.HOSTILE:
			enemies.append_array(_entities_by_team[other_team])
	return enemies

func get_all_allies_of(team_id: int) -> Array:
	"""获取某阵营的所有友方实体（不包括自己）"""
	var allies = []
	for other_team in _entities_by_team.keys():
		var relation = get_relation(team_id, other_team)
		if relation == Relation.FRIENDLY or relation == Relation.SAME_TEAM:
			allies.append_array(_entities_by_team[other_team])
	return allies

func get_entity_count(team_id: int) -> int:
	"""获取某阵营的实体数量"""
	return _entities_by_team.get(team_id, []).size()

# ============================================
# 伤害判定
# ============================================

func can_damage(attacker_team: int, target_team: int) -> bool:
	"""判定攻击者是否可以伤害目标"""
	var relation = get_relation(attacker_team, target_team)
	
	match relation:
		Relation.SAME_TEAM:
			return friendly_fire_enabled
		Relation.FRIENDLY:
			return friendly_fire_enabled
		Relation.HOSTILE:
			return true
		Relation.NEUTRAL_REL:
			return true  # 中立可以被任何人伤害，也可以伤害任何人
	
	return false

func is_hostile_to(team_a: int, team_b: int) -> bool:
	"""判断是否为敌对关系"""
	return get_relation(team_a, team_b) == Relation.HOSTILE

func is_friendly_to(team_a: int, team_b: int) -> bool:
	"""判断是否为友好关系"""
	var relation = get_relation(team_a, team_b)
	return relation == Relation.SAME_TEAM or relation == Relation.FRIENDLY

# ============================================
# 工具函数
# ============================================

func get_team_name(team_id: int) -> String:
	var data = _team_data.get(team_id, {})
	return data.get("name", "未知")

func get_team_color(team_id: int) -> Color:
	var data = _team_data.get(team_id, {})
	return data.get("color", Color.WHITE)

func get_team_display_info(team_id: int) -> Dictionary:
	return _team_data.get(team_id, {
		"name": "未知",
		"color": Color.WHITE
	})

func is_valid_team(team_id: int) -> bool:
	return team_id in TeamID.values()
