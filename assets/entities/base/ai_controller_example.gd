extends Node
class_name AIController

# 可以配置多个打法资源，并设置切换条件
@export var default_playstyle: AIPlaystyleBase
@export var low_health_playstyle: AIPlaystyleBase # 残血打法
@export var switch_health_threshold: float = 0.2   # 血量低于 20% 切换

var entity: EntityBase
var current_playstyle: AIPlaystyleBase
var current_target: Node2D = null

func _ready() -> void:
	# 等待父节点 准备好
	await get_parent().ready
	entity = get_parent() as EntityBase
	
	if not entity:
		queue_free()
		return
	
	default_playstyle = AIPlaystyleAggressive.new()
	low_health_playstyle = AIPlaystyleAggressive.new()
	
	entity.is_ai_controlled = true
	entity._ai_controller = self
	switch_playstyle(default_playstyle)

func _physics_process(delta: float) -> void:
	if not entity or not is_instance_valid(entity): return
	# 尊重原有的卡肉和冻结状态，不进行思考
	if entity.is_hit_stopped(): return
	
	# 寻找目标
	current_target = entity.get_nearest_enemy()
	
	# 动态切换打法逻辑 (例如残血换防守型)
	if low_health_playstyle and entity.hp < entity.hp_max * switch_health_threshold:
		if current_playstyle != low_health_playstyle:
			switch_playstyle(low_health_playstyle)
			
	# 执行当前打法
	if current_playstyle and current_target:
		current_playstyle.evaluate(entity, current_target, delta)

func switch_playstyle(new_style: AIPlaystyleBase) -> void:
	if not new_style: return
	current_playstyle = new_style
	print("[AI] %s 切换打法为: %s" % [entity.name, new_style.style_name])
	entity.clear_virtual_inputs()
