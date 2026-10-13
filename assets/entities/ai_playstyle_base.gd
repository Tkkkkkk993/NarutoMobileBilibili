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

# ============================================
# 招式识别查询（让 AI 能"看招"，而不只是"看判定框"）
# ============================================
# 配合 EntityBase 的招式识别只读层使用：
#   - 旧 API 只能回答"对手在不在攻击 / 判定框开没开"
#   - 新 API 可回答"对手在放哪个招 / 处于前摇还是收招"
# 典型用法：前摇抢招、收招惩罚。

## 目标当前正在放的招式身份（"attack"/"skill1"/"skill2"/"ultimate"，无则 ""）
func get_target_move_id(target: EntityBase) -> String:
	if not is_instance_valid(target):
		return ""
	return target.get_move_id()

## 目标当前所处阶段（EntityBase.MovePhase）
func get_target_move_phase(target: EntityBase) -> int:
	if not is_instance_valid(target):
		return EntityBase.MovePhase.NONE
	return target.get_move_phase()

## 目标是否处于前摇（判定框尚未出现）—— 可抢招 / 可打断的窗口
func is_target_in_startup(target: EntityBase) -> bool:
	return get_target_move_phase(target) == EntityBase.MovePhase.STARTUP

## 目标是否处于收招（判定已结束）—— 可惩罚的硬直窗口
func is_target_in_recovery(target: EntityBase) -> bool:
	return get_target_move_phase(target) == EntityBase.MovePhase.RECOVERY

## 目标当前的完整招式信息（见 EntityBase.get_move_info）
func get_target_move_info(target: EntityBase) -> Dictionary:
	if not is_instance_valid(target):
		return {}
	return target.get_move_info()

## 目标是否正在放某个具体招式（如 "skill2"）
func is_target_using_move(target: EntityBase, move_id: String) -> bool:
	return get_target_move_id(target) == move_id

# ============================================
# 实体状态查询（配合 EntityBase 的状态栈，见 base/entity_state_stack.gd）
# ============================================
# 与上面的招式识别互补，两者不重叠：
#   - 招式识别回答「在放哪个招、处于第几阶段」
#   - 状态栈回答「这个实体整体处于什么处境」（倒地 / 浮空 / 卡肉 / 被定身…）
# 状态是位掩码，允许同时成立多个（如浮空 + 受击）。
# 典型用法：对手倒地就压起身，对手卡肉就抢招，对手前摇就闪避。

## 目标当前的状态掩码。传 EntityStateStack.State.* 时可用按位或拼多个。
func get_target_state_mask(target: EntityBase) -> int:
	if not is_instance_valid(target):
		return 0
	return target.get_entity_state_mask()

## 目标是否处于指定状态（任一命中即为真）
func has_target_state(target: EntityBase, state_mask: int) -> bool:
	if not is_instance_valid(target):
		return false
	return (target.get_entity_state_mask() & state_mask) != 0

## 目标是否已倒地（可压起身的窗口）
func is_target_downed(target: EntityBase) -> bool:
	return has_target_state(target, EntityStateStack.State.DOWNED)

## 目标是否在空中（未落地）
func is_target_airborne(target: EntityBase) -> bool:
	return has_target_state(target, EntityStateStack.State.AIRBORNE)

## 目标是否处于击飞中
func is_target_launched(target: EntityBase) -> bool:
	return has_target_state(target, EntityStateStack.State.LAUNCHED)

## 目标是否处于受击硬直（击退中或受击僵直计时未走完）
func is_target_in_hurt(target: EntityBase) -> bool:
	return has_target_state(target, EntityStateStack.State.HURT)

## 目标是否被卡肉冻结。卡肉中无法行动，是抢招窗口。
func is_target_in_hit_stop(target: EntityBase) -> bool:
	return has_target_state(target, EntityStateStack.State.HIT_STOP)

## 目标是否被定身
func is_target_immobilized(target: EntityBase) -> bool:
	return has_target_state(target, EntityStateStack.State.IMMOBILIZED)

## 目标状态的可读描述，调试用，如 "HURT|LAUNCHED|AIRBORNE"
func describe_target_states(target: EntityBase) -> String:
	if not is_instance_valid(target):
		return "NONE"
	return target.describe_entity_states()
