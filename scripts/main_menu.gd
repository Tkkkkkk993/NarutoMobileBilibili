extends Control

@onready var animation_player = $AnimationPlayer
var bgm: AudioStream

@onready var start_btn = $Main/MenuButton/Start

@onready var char_select_x = $CharSelect/XControl/X

func _ready():
	var test_file = "user://test_mode.json"
	if FileAccess.file_exists(test_file):
		var file = FileAccess.open(test_file, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		DirAccess.remove_absolute(test_file)  # 读取后删除
		
		var json = JSON.new()
		if json.parse(content) == OK:
			var data = json.data
			print("从测试模式接收数据: ", data)
			
			animation_player.play("in")
			await get_tree().create_timer(1.5).timeout
			animation_player.play("TestMode")
			await get_tree().create_timer(1).timeout
			
			MatchConfig.reset_match()
			MatchConfig.p1_current_char = data.get("entity_id", "")
			MatchConfig.current_mode = MatchConfig.GameMode.TEST
			MatchConfig.start_battle()
			
			return
	
	bgm = preload("res://assets/audio/Music/圣德传说.ogg")
	
	start_btn.button_pressed.connect(_on_start_clicked)
	char_select_x.pressed.connect(_on_char_select_x_clicked)
	
	call_deferred("_play_in_animation")

func _on_start_clicked():
	animation_player.play("CharSelect")

func _on_char_select_x_clicked():
	animation_player.play_backwards("CharSelect")
	await get_tree().create_timer(1.2).timeout
	$AnimationPlayer.play("RESET")

func _play_in_animation():
	AudioManager.play_music(bgm)
	animation_player.play("in")
