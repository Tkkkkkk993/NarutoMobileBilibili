extends Node

signal controller_changed(new_name: String)

enum GameMode { PLAYER_VS_CPU, PLAYER_VS_PLAYER, TRAINING, TEST }

var current_controller_name: String = "Player1":
	set(value):
		if current_controller_name != value:
			current_controller_name = value
			controller_changed.emit(value)

var current_mode: GameMode = GameMode.PLAYER_VS_CPU

var p1_team: Array = []
var p1_team_scroll: Array = []
var p1_team_summon: Array = []
var p2_team: Array = []
var p2_team_scroll: Array = []
var p2_team_summon: Array = []

# 记录当前场上是队伍里的第几个人
var p1_current_index: int = 0
var p2_current_index: int = 0

var p1_current_char: String = ""
var p2_current_char: String = ""

var p1_current_scroll: String = ""
var p2_current_scroll: String = ""

var p1_current_summon: Array = []
var p2_current_summon: Array = []

var selected_stage: String = ""
var current_round: int = 1

# 血量继承（-1 表示不继承，使用满血）
var p1_carry_hp: int = -1
var p1_carry_hp_max: int = -1
var p2_carry_hp: int = -1
var p2_carry_hp_max: int = -1

# 奥义点继承（-1 表示不继承）
var p1_carry_ultimate: int = -1
var p2_carry_ultimate: int = -1

# 长时变量（在图形化脚本中用 set_long_var/get_long_var 读写，赢了传到下一把）
var p1_long_vars: Dictionary = {}
var p2_long_vars: Dictionary = {}

const maps = [
	"normal",
	"雾之湖",
	"华强买瓜遗址",
	"偶像练习生舞台",
	"芙兰朵露的房间",
	"博丽神社"
]

var current_map: String = "normal"

func start_battle():
	if current_mode == GameMode.TEST:
		print("测试模式")
		
		p2_current_char = "Daliwang"
		
		p1_current_scroll = "解术_散"
		p2_current_scroll = "解术_散"
		
		current_map = "normal"
		current_round = 1
		
		AudioManager.set_voice_pack("SenjuHashirama")
		
		get_tree().change_scene_to_file("res://scenes/arena_loading_screen.tscn")
		
		return
	
	# 校验必须选满3个
	if p1_team.size() != 3 or p2_team.size() != 3:
		push_error("队伍必须选满3个角色！")
		return
	
	p1_current_char = p1_team[p1_current_index].get("id", "")
	p2_current_char = p2_team[p2_current_index].get("id", "")
	
	p1_current_scroll = p1_team_scroll[p1_current_index].get("id", "")
	p2_current_scroll = p2_team_scroll[p2_current_index].get("id", "")
	
	p1_current_summon = []
	for i in p1_team_summon.size():
		p1_current_summon.append("res://assets/entities/%s/entity.tscn" % p1_team_summon[i]["id"])
	p2_current_summon = []
	for i in p2_team_summon.size():
		p2_current_summon.append("res://assets/entities/%s/entity.tscn" % p2_team_summon[i]["id"])
	
	current_map = maps.pick_random()
	
	get_tree().change_scene_to_file("res://scenes/arena_loading_screen.tscn")

func reset_match():
	current_mode = GameMode.PLAYER_VS_CPU
	p1_team.clear()
	p2_team.clear()
	p1_current_index = 0
	p2_current_index = 0
	selected_stage = ""
	current_round = 1
	current_map = maps.pick_random()
	p1_carry_hp = -1
	p1_carry_hp_max = -1
	p2_carry_hp = -1
	p2_carry_hp_max = -1
	p1_carry_ultimate = -1
	p2_carry_ultimate = -1
	p1_long_vars.clear()
	p2_long_vars.clear()

func switch_next_char(player: int):
	if player == 1:
		p1_current_index += 1
	elif player == 2:
		p2_current_index += 1

func get_char_id(player: int):
	var index: int
	var team: Array
	var result: Array
	if player == 1:
		team = p1_team
		index = p1_current_index
	else:
		team = p2_team
		index = p2_current_index
	for i in team.size():
		result.append(team[(index + i) % team.size()]["id"])
	return result
