# debug_manager.gd（全局自动加载）
extends Node

var debug_entities: Array[EntityBase] = []

func register_entity(entity: EntityBase):
	if not entity in debug_entities:
		debug_entities.append(entity)

func unregister_entity(entity: EntityBase):
	debug_entities.erase(entity)

func set_all_hitboxes(enabled: bool):
	for entity in debug_entities:
		if is_instance_valid(entity):
			entity.set_debug_hitboxes(enabled)

func set_all_attack_boxes(enabled: bool):
	for entity in debug_entities:
		if is_instance_valid(entity):
			entity.set_debug_attack_boxes(enabled)

func _input(event):
	# 快捷键控制
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				set_all_hitboxes(not _any_hitboxes_visible())
				print("受击框调试: ", "开启" if _any_hitboxes_visible() else "关闭")
			KEY_F2:
				set_all_attack_boxes(not _any_attack_boxes_visible())
				print("攻击框调试: ", "开启" if _any_attack_boxes_visible() else "关闭")
			KEY_F3:
				set_all_hitboxes(true)
				set_all_attack_boxes(true)
				print("全部调试显示开启")
			KEY_QUOTELEFT:
				var next = "Player2" if MatchConfig.current_controller_name == "Player1" else "Player1"
				MatchConfig.current_controller_name = next
				print("操控切换: ", next)

func _any_hitboxes_visible() -> bool:
	for entity in debug_entities:
		if is_instance_valid(entity) and entity.debug_show_hitboxes:
			return true
	return false

func _any_attack_boxes_visible() -> bool:
	for entity in debug_entities:
		if is_instance_valid(entity) and entity.debug_show_attack_boxes:
			return true
	return false
