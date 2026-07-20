class_name AIPlaystyleBase extends Resource

# 打法名称 (如："纯度打法", "撕咬打法")
@export var style_name: String = "基础打法"

# 决策频率 (AI 每隔多少秒思考一次，防止每帧计算太耗性能)
@export var think_interval: float = 0.1

# 内部计时器
var _think_timer: float = 0.0

# 核心：由 AI 控制器每帧调用
func evaluate(entity: EntityBase, target: EntityBase, delta: float) -> void:
	_think_timer += delta
	if _think_timer < think_interval:
		return
	_think_timer = 0.0
	# 每次思考前清空上一次的输入
	entity.clear_virtual_inputs()
	# 调用具体打法的决策逻辑 (子类重写)
	_decide_action(entity, target)

# 子类必须重写这个方法来决定按什么键
func _decide_action(entity: EntityBase, target: EntityBase) -> void:
	push_error("AI打法文件未实现 _decide_action 方法!")

# ============================================
# 攻击框检测辅助方法
# ============================================

## 基础检测：目标当前是否处于攻击状态（基于状态机，延迟较高）
func is_target_attacking(target: EntityBase) -> bool:
	return target.is_attacking if is_instance_valid(target) else false

## 精确检测：目标当前是否激活了攻击框（能抓到出招前摇瞬间）
func has_active_attack_box(target: EntityBase) -> bool:
	if not is_instance_valid(target) or not target.attack_box_manager:
		return false
	return target.attack_box_manager._active_boxes.size() > 0

## 获取目标当前激活的攻击框数量
func get_active_attack_box_count(target: EntityBase) -> int:
	if not is_instance_valid(target) or not target.attack_box_manager:
		return 0
	return target.attack_box_manager._active_boxes.size()

## 获取目标当前所有激活攻击框的世界坐标数组
func get_active_attack_box_positions(target: EntityBase) -> Array:
	var positions = []
	if not is_instance_valid(target) or not target.attack_box_manager:
		return positions
		
	for box_data in target.attack_box_manager._active_boxes.values():
		var node = box_data.get("node")
		if is_instance_valid(node):
			positions.append(node.global_position)
			
	return positions

## 高级预判：敌人的攻击框是否正在逼近自己
## entity: 自己, target: 敌人, safe_distance: 触发防御/闪避的安全距离阈值
func is_attack_box_approaching(entity: EntityBase, target: EntityBase, safe_distance: float = 150.0) -> bool:
	if not has_active_attack_box(target):
		return false
		
	var positions = get_active_attack_box_positions(target)
	for pos in positions:
		var dist_x = abs(pos.x - entity.global_position.x)
		# 如果攻击框在安全距离内
		if dist_x < safe_distance:
			# 判断攻击框是否朝向自己
			var atk_facing = target.facing_direction
			var dir_to_me = sign(entity.global_position.x - pos.x)
			if dir_to_me == atk_facing:
				return true
	return false
