extends Control

var char_select_data: Array[Dictionary] = []
var scroll_select_data: Array[Dictionary] = []
var summon_select_data: Array[Dictionary] = []
@onready var portraits: Array[TextureRect] = [
	$Portrait1,
	$Portrait2,
	$Portrait3
]
@onready var portraits_touch: Array[TouchScreenButton] = [
	$Portrait1Touch,
	$Portrait2Touch,
	$Portrait3Touch
]
@onready var char_icon_manager: Control = $CharIconManager
@onready var scrolls: Array[Control] = [
	$Scrolls/Item1,
	$Scrolls/Item2,
	$Scrolls/Item3
]
@onready var summons: Array[Control] = [
	$Summons/Item1,
	$Summons/Item2,
	$Summons/Item3
]
@onready var scroll_icon_manager: ScrollIconManager = $ScrollIconManager
@onready var summon_icon_manager: SummonIconManager = $SummonIconManager
@export var base_entities_path: String = "res://assets/entities/"
@export var portrait_sub_path: String = "portraits/idle.png"
@export var icon_sub_path: String = "portraits/icon_idle.png"

func _ready() -> void:
	char_select_data.resize(3)
	scroll_select_data.resize(3)
	summon_select_data.resize(3)
	
	for btn in portraits_touch:
		btn.pressed.connect(_on_any_button_pressed.bind(btn.name))
	
	$StartButton.pressed.connect(_on_start_button_pressed)
	
	for i in range(char_select_data.size()):
		if not char_select_data[i]: # 如果当前位置为空 (null / false)
			char_select_data[i] = {}
			portraits[i].texture = load(base_entities_path.path_join("base").path_join(portrait_sub_path))

func _process(_delta):
	_check_button_states()

func _check_button_states():
	visible = true
	for i in scrolls.size():
		var item = scrolls[i]
		if item is ScrollIconSlot:
			var child = item.touch
			if child.consume_press():
				_handle_scroll_icon_clicked(i)
	for i in summons.size():
		var item = summons[i]
		if item is ScrollIconSlot:
			var child = item.touch
			if child.consume_press():
				_handle_summon_icon_clicked(i)

func _handle_scroll_icon_clicked(index: int):
	if scroll_select_data[index]:
		delete_scroll(index)

func _handle_summon_icon_clicked(index: int):
	if summon_select_data[index]:
		delete_summon(index)

func _on_start_button_pressed():
	if char_select_data[0] and char_select_data[1] and char_select_data[2]:
		# 存入全局单例
		MatchConfig.reset_match()
		
		MatchConfig.p1_team = [char_select_data[0], char_select_data[1], char_select_data[2]]
		MatchConfig.p2_team = [char_select_data[0], char_select_data[1], char_select_data[2]]
		MatchConfig.p1_team_scroll = [scroll_select_data[0], scroll_select_data[1], scroll_select_data[2]]
		MatchConfig.p2_team_scroll = [scroll_select_data[0], scroll_select_data[1], scroll_select_data[2]]
		MatchConfig.p1_team_summon = [summon_select_data[0], summon_select_data[1], summon_select_data[2]]
		MatchConfig.p2_team_summon = [summon_select_data[0], summon_select_data[1], summon_select_data[2]]
		
		MatchConfig.start_battle()

func _on_any_button_pressed(button_name: String):
	var num_str = button_name.trim_prefix("Portrait").trim_suffix("Touch")
	
	if num_str.is_valid_int():
		delete_char(int(num_str) - 1)

func add_char(data: Dictionary) -> int:
	for i in char_select_data.size():
		if not char_select_data[i]:
			char_select_data[i] = data
			portraits[i].texture = load(base_entities_path.path_join(data.get("id", "")).path_join(portrait_sub_path))
			return i
	return -1

func delete_char(index: int):
	char_select_data[index] = {}
	portraits[index].texture = load("res://assets/entities/base/portraits/idle.png")
	char_icon_manager.deselect_by_id(index + 1)

func add_scroll(data: Dictionary) -> int:
	for i in scroll_select_data.size():
		if not scroll_select_data[i]:
			scroll_select_data[i] = data
			scrolls[i].set_texture(load(base_entities_path.path_join(data.get("id", "")).path_join(icon_sub_path)))
			return i
	return -1

func delete_scroll(index: int):
	scroll_select_data[index] = {}
	scrolls[index].set_texture(null)
	scroll_icon_manager.deselect_by_id(index + 1)

func add_summon(data: Dictionary) -> int:
	for i in summon_select_data.size():
		if not summon_select_data[i]:
			summon_select_data[i] = data
			summons[i].set_texture(load(base_entities_path.path_join(data.get("id", "")).path_join(icon_sub_path)))
			return i
	return -1

func delete_summon(index: int):
	summon_select_data[index] = {}
	summons[index].set_texture(null)
	summon_icon_manager.deselect_by_id(index + 1)
