extends Node

signal controller_changed(new_name: String)

enum GameMode { PLAYER_VS_CPU, PLAYER_VS_PLAYER, TRAINING, TEST }

var current_controller_name: String = "Player1":
	set(value):
		if current_controller_name != value:
			current_controller_name = value
			controller_changed.emit(value)

var current_mode: GameMode = GameMode.PLAYER_VS_CPU

## 调试总开关。
## 关闭后实体不再绘制受击框、攻击框、信息点与 Z 深度标签，也不再输出任何调试 print，
## 无论实体自己的调试开关是什么状态。编辑器与调试构建默认开启，导出发布默认关闭。
## 运行中改这个值会广播 debug_enabled_changed，实体收到后立刻重算。
signal debug_enabled_changed(enabled: bool)

var debug_enabled: bool = OS.has_feature("editor") or OS.is_debug_build():
	set(value):
		if debug_enabled == value:
			return
		debug_enabled = value
		debug_enabled_changed.emit(value)

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

## 全局逻辑帧号：每个物理帧 +1。
## 停帧（场景树暂停）与 Engine.time_scale 为 0 时物理帧不推进，它也不推进。
## 与实体各自的 _buffer_clock 不同，它是全局唯一、跨实体可比的，
## 供联机输入包与将来的动画时钟使用。
var logic_frame: int = 0

func _physics_process(_delta):
	logic_frame += 1

func start_battle():
	logic_frame = 0
	AudioManager.set_voice_pack("KirisameMarisa")
	
	if current_mode == GameMode.TEST:
		print("测试模式")
		
		p2_current_char = "神秘面具男"
		
		p1_current_scroll = "解术_散"
		p2_current_scroll = "解术_散"
		
		# 训练场给满三个通灵。这份名单原来硬编码在 EntityBase 的字段初值里，
		# 那边现在默认什么都不携带，想测通灵就得在这里显式给。
		var test_summon_ids := ["大运重卡", "鲨鱼", "三方封印"]
		p1_current_summon = []
		p2_current_summon = []
		for summon_id in test_summon_ids:
			p1_current_summon.append("res://assets/entities/%s/entity.tscn" % summon_id)
			p2_current_summon.append("res://assets/entities/%s/entity.tscn" % summon_id)
		
		current_map = "normal"
		current_round = 1
		
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
	logic_frame = 0
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

func _input(event):
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			# 主键盘数字 1 切换调试总开关。小键盘 1 是 P2 的攻击键，不要混用。
			debug_enabled = not debug_enabled
			print("调试总开关: ", "开启" if debug_enabled else "关闭")
		KEY_QUOTELEFT:
			# 引号键切换操控方。原挂在 DebugManager 上，该自动加载因没有任何注册者已删除。
			var next = "Player2" if current_controller_name == "Player1" else "Player1"
			current_controller_name = next
			print("操控切换: ", next)
