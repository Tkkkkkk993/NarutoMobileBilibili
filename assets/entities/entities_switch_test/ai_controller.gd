extends Node
class_name 多实体切换测试实体控制器

@export var default_playstyle: AIPlaystyleBase

var entity: EntityBase
var current_playstyle: AIPlaystyleBase
var current_target: Node2D = null

# 是否被玩家接管
var is_player_controlled: bool = false

func _ready() -> void:
	entity = get_parent() as EntityBase
	
	if not entity:
		queue_free()
		return
	
	entity.is_ai_controlled = true
	entity._ai_controller = self
	
	if not default_playstyle:
		default_playstyle = AIPlaystyleBase.new()
		default_playstyle.style_name = "基础打法"
	
	switch_playstyle(default_playstyle)

func _physics_process(delta: float) -> void:
	if not entity or not is_instance_valid(entity): return
	if entity.is_hit_stopped(): return
	
	if is_player_controlled:
		return
		
	current_target = entity.get_nearest_enemy()
	
	if current_playstyle and current_target:
		current_playstyle.evaluate(entity, current_target, delta)

# 主实体调用此方法注入真实玩家输入
func inject_player_input(left: bool, right: bool, up: bool, down: bool, btns: Array[bool]) -> void:
	if not entity or not is_instance_valid(entity): return
	
	is_player_controlled = true
	
	entity.input_left = left
	entity.input_right = right
	entity.input_up = up
	entity.input_down = down
	
	# 注入移动意图，否则速度会被乘以 0 导致原地踏步
	entity.move_intent = Vector2.ONE
	
	for i in range(btns.size()):
		if i < entity.inputs.size():
			entity.inputs[i] = btns[i]
			
	entity.set_virtual_input("move_left", left)
	entity.set_virtual_input("move_right", right)
	entity.set_virtual_input("move_up", up)
	entity.set_virtual_input("move_down", down)
	for i in range(btns.size()):
		entity.set_virtual_input("button_" + str(i), btns[i])

func switch_playstyle(new_style: AIPlaystyleBase) -> void:
	if not new_style: return
	current_playstyle = new_style
	print("[AI] %s 切换打法为: %s" % [entity.name, new_style.style_name])
	entity.clear_virtual_inputs()
