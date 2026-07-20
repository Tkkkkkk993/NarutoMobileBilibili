extends AnimatedSprite2DEntity
class_name 多实体切换测试

var is_ready: bool = false
var char_entities: Array[EntityBase]
var current_entity_id = 0

func _ready():
	res_path = "res://assets/entities/entities_switch_test/main.tres"
	super._ready()
	# 防止主实体自身 inputs 数组越界
	inputs.resize(9)

func _post_init():
	play_animation("control")
	
	var cfg = EntityManager.EntityConfig.new(
		name + "_chuangliban",
		"res://assets/entities/KonohaFounding_UchihaMadara/entity.tscn",
		get_2d_pos(), team_id, facing_direction
	)
	var ee = entity_manager.spawn_entity_runtime(cfg)
	ee.parent_entity = self
	ee.inputs.resize(9)
	ee.is_player = is_player # 继承玩家身份，用于UI和光圈
	ee.entity_type = entity_type
	
	var cfg2 = EntityManager.EntityConfig.new(
		name + "_huituban",
		"res://assets/entities/EdoTensei_UchihaMadara/entity.tscn",
		get_2d_pos(), team_id, facing_direction
	)
	var ee2 = entity_manager.spawn_entity_runtime(cfg2)
	ee2.parent_entity = self
	ee2.inputs.resize(9)
	ee2.is_player = is_player
	ee2.entity_type = entity_type
	
	char_entities.append(ee)
	char_entities.append(ee2)
	
	teleport_to_position(char_entities[current_entity_id].position_3d)
	char_entities[1-current_entity_id].position_3d = Vector3(0,114514,0)
	
	entry_action = EntryAction.NONE
	
	# 挂载独立控制器
	var script_path = "res://assets/entities/entities_switch_test/ai_controller.gd"
	var script = load(script_path)
	
	var ai_node1 = Node.new()
	ai_node1.name = "AIController"
	ai_node1.set_script(script)
	ee.add_child(ai_node1)
	
	var ai_node2 = Node.new()
	ai_node2.name = "AIController"
	ai_node2.set_script(script)
	ee2.add_child(ai_node2)
	
	ee.is_ai_controlled = true
	ee2.is_ai_controlled = true
	
	# 强制播放 idle 解除状态机锁死
	ee.play_animation("idle")
	ee2.play_animation("idle")
	
	# 手动播放光圈动画
	if ee.aura_node: ee.aura_node.play("own" if is_player else "ene")
	if ee2.aura_node: ee2.aura_node.play("own" if is_player else "ene")
	
	aura_node.visible = false
	
	is_ready = true

func _physics_process(delta: float) -> void:
	if !is_ready: return
	
	# 主实体自身读取真实玩家输入 (根据 entity_type 自动区分 1P 或 2P)
	super._physics_process(delta)
	
	# 将输入转发给当前操控的子实体
	var active_entity = char_entities[current_entity_id]
	if inputs[3]:
		try_3_input()
		inputs[3] = false
	if is_instance_valid(active_entity):
		var ai_ctrl = active_entity.get_node_or_null("AIController")
		if ai_ctrl and ai_ctrl.has_method("inject_player_input"):
			# 调用控制器的方法注入输入
			ai_ctrl.inject_player_input(input_left, input_right, input_up, input_down, inputs)
	if not active_entity.position_3d.y == 114514:
		teleport_to_position(active_entity.position_3d)
		set_facing(active_entity.facing_direction)
	
	# 清空未操控实体的输入，防止卡键
	var inactive_entity = char_entities[1 - current_entity_id]
	if is_instance_valid(inactive_entity):
		inactive_entity.clear_virtual_inputs()

func try_3_input():
	if cool_down_time[3].time > 0:
		return
	
	set_cd(3, 3, 1)
	
	if char_entities[current_entity_id].current_animation == "run":
		char_entities[1-current_entity_id].play_animation("run")
	char_entities[1-current_entity_id].position_3d = char_entities[current_entity_id].position_3d
	char_entities[1-current_entity_id].set_facing(char_entities[current_entity_id].facing_direction)
	char_entities[current_entity_id].position_3d = Vector3(0,114514,0)
	
	current_entity_id = 1-current_entity_id
