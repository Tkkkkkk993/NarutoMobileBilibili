extends Node2D

@onready var fight_ui = $FightUI
var timer: DigitDisplay
var rest_time: float = 60
var battle_started: bool = false
var round_animation
@onready var entitys = $Main/Entities
var player1: EntityBase
var player2: EntityBase
enum STATUS {
	IDLE,
	START,
	RESULT
}
var status
var p1_avatars: Array
var p2_avatars: Array
@onready var effects_container = $Main/Effects
@onready var camera = $Camera2D

func _ready() -> void:
	timer = fight_ui.get_node("RoundsNumber/Timer")
	var background = LoadingManager.get_resource(
		"res://scenes/Arena/%s.tscn"
		% MatchConfig.current_map
	)
	var background_instance = background.instantiate()
	$Main/Background.add_child(background_instance)
	
	if MatchConfig.current_mode == MatchConfig.GameMode.TEST:
		fight_ui.get_node("RoundsNumber").visible = false
		timer.visible = false
		fight_ui.get_node("P1_Info/Avatar2").visible = false
		fight_ui.get_node("P1_Info/Avatar3").visible = false
		fight_ui.get_node("P2_Info/Avatar2").visible = false
		fight_ui.get_node("P2_Info/Avatar3").visible = false
		
		var path = get_battle_icon_list_solo(MatchConfig.p1_current_char)
		fight_ui.get_node("P1_Info/Protections/Avatar2").texture = LoadingManager.get_resource(path)
		fight_ui.get_node("P1_Info/Protections/X").visible = false
		path = get_battle_icon_list_solo(MatchConfig.p2_current_char)
		fight_ui.get_node("P2_Info/Protections/Avatar2").texture = LoadingManager.get_resource(path)
		fight_ui.get_node("P2_Info/Protections/X").visible = false
		
		while not (player1 and player2):
			for e in entitys.get_children():
				if e is EntityBase:
					if e.name == "Player1" and e.load_done:
						player1 = e
					elif e.name == "Player2" and e.load_done:
						player2 = e
			await get_tree().process_frame
		$CanvasLayer/AnimationPlayer.play("Start")
		
		await get_tree().process_frame
		var entry_ended: bool = false
		while not entry_ended:
			entry_ended = true
			for e in entitys.get_children():
				if e is EntityBase:
					if e.entry_action != EntityBase.EntryAction.NONE:
						entry_ended = false
						break
			await get_tree().process_frame # 等待下一帧
		
		status = STATUS.START
	else:
		effects_container.register_effects({
			"Beat": preload("res://assets/entities/base/effects/beatEffect/effects_base.tscn"),
		})
		
		fight_ui.get_node("RoundsNumber/TextureRect").texture = load(
			"res://assets/UI/roundsNum/".path_join("roundNum-"+str(MatchConfig.current_round)+"-000.png")
		)
		
		rest_time = 60
		timer.set_text("60")
		
		p1_avatars = [
			fight_ui.get_node("P1_Info/Protections"),
			fight_ui.get_node("P1_Info/Avatar2"),
			fight_ui.get_node("P1_Info/Avatar3")
		]
		p2_avatars = [
			fight_ui.get_node("P2_Info/Protections"),
			fight_ui.get_node("P2_Info/Avatar2"),
			fight_ui.get_node("P2_Info/Avatar3")
		]
		var paths = get_battle_icon_list(MatchConfig.get_char_id(1))
		for i in p1_avatars.size():
			p1_avatars[i].get_node("Avatar2").texture = LoadingManager.get_resource(paths[i])
			if 3 - i <= MatchConfig.p1_current_index:
				p1_avatars[i].get_node("X").visible = true
			else:
				p1_avatars[i].get_node("X").visible = false
		paths = get_battle_icon_list(MatchConfig.get_char_id(2))
		for i in p2_avatars.size():
			p2_avatars[i].get_node("Avatar2").texture = LoadingManager.get_resource(paths[i])
			if 3 - i <= MatchConfig.p2_current_index:
				p2_avatars[i].get_node("X").visible = true
			else:
				p2_avatars[i].get_node("X").visible = false
		
		round_animation = fight_ui.get_node("RoundAnimationControl").get_node("RoundAnimation")
		round_animation.visible = false
		await get_tree().process_frame
		var entry_ended: bool = false
		
		while not (player1 and player2):
			for e in entitys.get_children():
				if e is EntityBase:
					if e.name == "Player1" and e.load_done:
						player1 = e
					elif e.name == "Player2" and e.load_done:
						player2 = e
			await get_tree().process_frame
		$CanvasLayer/AnimationPlayer.play("Start")
		
		while not entry_ended:
			entry_ended = true
			for e in entitys.get_children():
				if e is EntityBase:
					if e.entry_action != EntityBase.EntryAction.NONE:
						entry_ended = false
						break
			await get_tree().process_frame # 等待下一帧
		
		round_animation.visible = true
		var round_texture_path
		var voice_expression: String
		if MatchConfig.p1_current_index < 2 or MatchConfig.p2_current_index < 2:
			round_texture_path = "res://assets/UI/roundsNum/".path_join("roundNumBig-"+str(MatchConfig.current_round)+"-000.png")
			voice_expression = "round_" + str(MatchConfig.current_round)
		else:
			round_texture_path = "res://assets/UI/roundsNum/roundNumBig-final-000.png"
			round_animation.get_node("DiXHui/Di").texture = load("res://assets/UI/roundsNum/prefix-last-000.png")
			voice_expression = "round_final"
		round_animation.get_node("DiXHui/RoundNum").texture = load(
			round_texture_path
		)
		AudioManager.play_voice_by_id(voice_expression)
		round_animation.play("DiXHui")
		await get_tree().create_timer(1.5).timeout
		AudioManager.play_voice_by_id("battle_start")
		round_animation.play("Start")
		await get_tree().create_timer(1.5).timeout
		
		# 开场动画结束, 进入战斗状态
		status = STATUS.START

func get_battle_icon_list(a: Array):
	var b: Array
	for item in a:
		b.append(
			get_battle_icon_list_solo(item)
		)
	return b

func get_battle_icon_list_solo(s: String):
	return "res://assets/entities/%s/portraits/icon_battle.png" % s

func _process(delta: float) -> void:
	match status:
		STATUS.IDLE:
			# 空闲
			battle_started = false
		STATUS.START:
			battle_started = true
			if not MatchConfig.current_mode == MatchConfig.GameMode.TEST and not GlobalTimeManager.time_stop_active:
				rest_time -= delta
			if rest_time <= 0:
				status = STATUS.IDLE
				timer.set_text("0")
				rest_time = 0
				round_animation.play("TimeUp")
				await get_tree().create_timer(1.5).timeout
				await decide_winner()
			elif not MatchConfig.current_mode == MatchConfig.GameMode.TEST:
				timer.set_text(str(int(rest_time)))
				if player1.hp <= 0 or player2.hp <= 0:
					status = STATUS.IDLE
					await get_tree().create_timer(0.1).timeout
					GlobalTimeManager.set_time_scale_animated(0.5, 0.5, 0.0, 0.0, -1)
					var is_dead: bool = false
					var pos = Vector3.ZERO
					pos.x = camera.global_position.x
					effects_container.spawn_effect(
						"Beat",
						pos,
						true
					)
					while not is_dead:
						var total_die: int = 0
						var dead: int = 0
						if player1.hp <= 0:
							total_die += 1
							dead += int(player1.is_dead)
							p1_avatars[0].get_node("X").visible = true
						if player2.hp <= 0:
							total_die += 1
							dead += int(player2.is_dead)
							p2_avatars[0].get_node("X").visible = true
						is_dead = dead >= total_die
						await get_tree().process_frame # 等待下一帧
					await decide_winner()
		STATUS.RESULT:
			battle_started = false

func _input(event: InputEvent):
	match status:
		STATUS.RESULT:
			if event is InputEventMouseButton and event.pressed or event is InputEventKey and event.pressed:
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func decide_winner():
	status = STATUS.IDLE
	var winner: int = 0
	if player1.hp > player2.hp:
		winner = 1
	elif player1.hp < player2.hp:
		winner = 2

	# 等待所有实体进入 idle/run、extra_idle_anims 或已死亡（最多等 10 秒）
	var wait_start = Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var all_settled = true
		for e in [player1, player2]:
			if not is_instance_valid(e):
				continue
			if e.is_dead:
				continue
			var extra = e.entity_data.extra_idle_anims if e.entity_data else []
			if e.current_animation not in ["idle", "run"] + extra:
				all_settled = false
				break
		if all_settled:
			break
		if Time.get_ticks_msec() - wait_start >= 10000:
			break

	# 胜者继承血量到下一局（附加伤害10%加成）和奥义点
	if winner > 0:
		if winner == 1:
			if is_instance_valid(player1):
				var bonus = int(player1.total_damage_dealt * 0.1)
				var base_max = player1.entity_data.max_health if player1.entity_data else player1.hp_max
				MatchConfig.p1_carry_hp = min(player1.hp + bonus, base_max)
				MatchConfig.p1_carry_hp_max = base_max
				MatchConfig.p1_carry_ultimate = player1.ultimate_point + (1 if player1._ultimate_kill_this_round else 0)
			else:
				MatchConfig.p1_carry_hp = -1
				MatchConfig.p1_carry_hp_max = -1
				MatchConfig.p1_carry_ultimate = -1
			MatchConfig.p2_carry_hp = -1
			MatchConfig.p2_carry_hp_max = -1
			MatchConfig.p2_carry_ultimate = -1
		else:
			if is_instance_valid(player2):
				var bonus = int(player2.total_damage_dealt * 0.1)
				var base_max = player2.entity_data.max_health if player2.entity_data else player2.hp_max
				MatchConfig.p2_carry_hp = min(player2.hp + bonus, base_max)
				MatchConfig.p2_carry_hp_max = base_max
				MatchConfig.p2_carry_ultimate = player2.ultimate_point + (1 if player2._ultimate_kill_this_round else 0)
			else:
				MatchConfig.p2_carry_hp = -1
				MatchConfig.p2_carry_hp_max = -1
				MatchConfig.p2_carry_ultimate = -1
			MatchConfig.p1_carry_hp = -1
			MatchConfig.p1_carry_hp_max = -1
			MatchConfig.p1_carry_ultimate = -1
	else:
		MatchConfig.p1_carry_hp = -1
		MatchConfig.p1_carry_hp_max = -1
		MatchConfig.p1_carry_ultimate = -1
		MatchConfig.p2_carry_hp = -1
		MatchConfig.p2_carry_hp_max = -1
		MatchConfig.p2_carry_ultimate = -1

	if winner > 0:
		MatchConfig.switch_next_char(3 - winner)
		var winner_name: String
		var winner_node: EntityBase
		if winner == 1:
			winner_name = MatchConfig.p1_current_char
			winner_node = player1
		else:
			winner_name = MatchConfig.p2_current_char
			winner_node = player2
		round_animation.get_node("WinnerDecided/WinnerDecideBg/IconSlot/IconIdle").texture = load(
			# res://assets/entities/llx/portraits/icon_idle.png
			"res://assets/entities/".path_join(winner_name).path_join("/portraits/icon_idle.png")
		)
		round_animation.get_node("WinnerDecided/WinnerDecideBg/CharName").text = winner_node.title
		AudioManager.play_voice_by_id("winner_decided")
		round_animation.play("WinnerDecided")
		await get_tree().create_timer(2).timeout
	else:
		MatchConfig.switch_next_char(1)
		MatchConfig.switch_next_char(2)
		round_animation.play("Draw")
		await get_tree().create_timer(1).timeout
	
	if MatchConfig.p1_current_index >= 3:
		status = STATUS.RESULT
		var team_id = MatchConfig.get_char_id(1)
		for i in team_id.size():
			round_animation.get_node("Result/Portraits/Portrait"+str(i+1)).texture = load(
				"res://assets/entities/".path_join(team_id[i]).path_join("/portraits/idle.png")
			)
		if MatchConfig.p2_current_index >= 3:
			# 平局
			round_animation.get_node("Result/Bg").texture = load("res://assets/UI/winnerDecided/r-lose-bg.png")
			round_animation.get_node("Result/Font").texture = load("res://assets/UI/winnerDecided/r-draw.png")
			round_animation.play("Result")
		else:
			# P2获胜
			round_animation.get_node("Result/Bg").texture = load("res://assets/UI/winnerDecided/r-lose-bg.png")
			round_animation.get_node("Result/Font").texture = load("res://assets/UI/winnerDecided/r-lose.png")
			AudioManager.play_voice_by_id("victory")
			round_animation.play("Result")
	elif MatchConfig.p2_current_index >= 3:
		status = STATUS.RESULT
		var team_id = MatchConfig.get_char_id(2)
		for i in team_id.size():
			round_animation.get_node("Result/Portraits/Portrait"+str(i+1)).texture = load(
				"res://assets/entities/".path_join(team_id[i]).path_join("/portraits/idle.png")
			)
		# P1获胜
		if MatchConfig.p1_current_index == 0:
			# P1完胜
			round_animation.get_node("Result/Font").texture = load("res://assets/UI/winnerDecided/r-winPerfect.png")
			AudioManager.play_voice_by_id("victory_perfect")
		else:
			AudioManager.play_voice_by_id("victory")
		round_animation.play("Result")
	else:
		MatchConfig.current_round += 1
		MatchConfig.start_battle()
