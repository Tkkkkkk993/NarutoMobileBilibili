class_name AIPlaystyleAggressive extends AIPlaystyleBase

@export var attack_range_y: float = 50.0   # 进入此距离开始攻击
@export var attack_range_x: float = 200.0   # 进入此距离开始攻击
@export var skill_chance: float = 0.3    # 每次思考使用技能的概率

func _decide_action(entity: EntityBase, target: EntityBase) -> void:
	if not target or not is_instance_valid(target): return
	
	# 计算伪3D距离 (结合 X轴 和 Z轴高度差)
	var dx = abs(entity.position_3d.x - target.position_3d.x)
	var dy = abs(entity.position_3d.y - target.position_3d.y)
	
	# 面向目标
	if entity.position_3d.x < target.position_3d.x:
		entity.set_virtual_input("move_right", true)
	elif entity.position_3d.x > target.position_3d.x:
		entity.set_virtual_input("move_left", true)
		
	# 距离判断
	if dy > attack_range_y or dx > attack_range_x:
		# 走近
		if target.position_3d.y < entity.position_3d.y:
			entity.set_virtual_input("move_up", true)
		else:
			entity.set_virtual_input("move_down", true)
		if target.position_3d.y < entity.position_3d.y:
			entity.set_virtual_input("move_up", true)
		else:
			entity.set_virtual_input("move_down", true)
	else:
		# 在攻击范围内：随机攻击
		if randf() < 0.6:
			entity.set_virtual_input("button_0", true) # 普攻
		elif randf() < skill_chance:
			var skill_idx = randi() % 3 + 1
			entity.set_virtual_input("button_" + str(skill_idx), true)
			
		# 激进型特有：秒替按住
		if entity.is_under_control and entity.ultimate_point > 0:
			entity.set_virtual_input("button_4", true)
