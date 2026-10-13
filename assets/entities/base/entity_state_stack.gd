class_name EntityStateStack extends RefCounted

# ============================================
# 实体状态栈（观察层）
# ============================================
# 把散落在 EntityBase 里的十几个状态布尔量，汇总成一处可枚举、可查询、可序列化的
# 「当前激活状态集合」。
#
# 定位（第一阶段，动这个文件前务必先读这一段）
#   本层是**镜像层**：某个状态是否激活，完全由 EntityBase 里既有的布尔量推导，
#   本层不写回任何字段、不驱动任何行为、不改任何时序。
#   所以接入它是零行为改动的。将来逐项把行为搬进状态时，才逐个改成「由状态拥有字段」。
#
# 为什么值得先做镜像
#   1. 状态变成 int 位掩码，可以进快照、可以同步；字符串与一堆 bool 的排列组合不行。
#   2. 进入与退出有了统一出口，事件系统、特效、音效、AI 都能只挂一个地方。
#   3. 「谁在什么状态下」第一次有了单一事实来源，后面拆状态才有依据。
#
# 状态允许叠加：浮空 + 霸体这种组合，就是掩码里同时亮两个位。
# 互斥不在这里决定 —— 互斥是行为层的事，本层只如实反映既有字段。
#
# 为什么参数不写 EntityBase 类型
#   本文件要被 entity_base.gd 引用；若这里反向引用 EntityBase，就构成 class_name
#   循环引用，Godot 4 会直接报错。故这里一律按鸭子类型读取字段。

enum State {
	NONE = 0,
	DEAD = 1,
	HIT_STOP = 2,
	IMMOBILIZED = 4,
	DOWNED = 8,
	LAUNCHED = 16,
	AIRBORNE = 32,
	HURT = 64,
	INVINCIBLE = 128,
	SUBSTITUTION_INVINCIBLE = 256,
	ATTACKING = 512,
	ULTIMATE = 1024,
	SLIDING = 2048,
	FREE_MOVE = 4096,
	MAGNETIZED = 8192,
	GROUNDED = 16384,
	WAITING_FOR_LAND = 32768,
}

const STATE_NAMES: Dictionary = {
	State.DEAD: "DEAD",
	State.HIT_STOP: "HIT_STOP",
	State.IMMOBILIZED: "IMMOBILIZED",
	State.DOWNED: "DOWNED",
	State.LAUNCHED: "LAUNCHED",
	State.AIRBORNE: "AIRBORNE",
	State.HURT: "HURT",
	State.INVINCIBLE: "INVINCIBLE",
	State.SUBSTITUTION_INVINCIBLE: "SUBSTITUTION_INVINCIBLE",
	State.ATTACKING: "ATTACKING",
	State.ULTIMATE: "ULTIMATE",
	State.SLIDING: "SLIDING",
	State.FREE_MOVE: "FREE_MOVE",
	State.MAGNETIZED: "MAGNETIZED",
	State.GROUNDED: "GROUNDED",
	State.WAITING_FOR_LAND: "WAITING_FOR_LAND",
}

## 展示与信号发射顺序，从高到低。只影响顺序，不影响掩码内容。
const PRIORITY: Array = [
	State.DEAD,
	State.HIT_STOP,
	State.IMMOBILIZED,
	State.DOWNED,
	State.LAUNCHED,
	State.AIRBORNE,
	State.HURT,
	State.SUBSTITUTION_INVINCIBLE,
	State.INVINCIBLE,
	State.ULTIMATE,
	State.ATTACKING,
	State.SLIDING,
	State.FREE_MOVE,
	State.MAGNETIZED,
	State.GROUNDED,
	State.WAITING_FOR_LAND,
]

signal state_entered(state: int, frame: int)
signal state_exited(state: int, frame: int)
signal active_changed(mask: int, frame: int)

var _mask: int = 0
var _entry_frame: Dictionary = {}
var _last_frame: int = -1

# ============================================
# 更新
# ============================================

## 由 EntityBase 每物理帧调用。同一帧内多次调用是安全的：
## 每次都按当前字段重新推导，只对变化的差集发信号。
func update(entity, frame: int) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	_last_frame = frame

	var next_mask: int = _derive(entity)
	if next_mask == _mask:
		return

	var entered: int = next_mask & ~_mask
	var exited: int = _mask & ~next_mask
	_mask = next_mask

	# 先退出、后进入。这样「进入某状态」的回调可以假定旧状态已经退干净了。
	# 两个循环都按 PRIORITY 走，保证同一帧内的信号顺序可复现。
	for raw in PRIORITY:
		var s: int = int(raw)
		if exited & s:
			_entry_frame.erase(s)
			state_exited.emit(s, frame)

	for raw in PRIORITY:
		var s: int = int(raw)
		if entered & s:
			_entry_frame[s] = frame
			state_entered.emit(s, frame)

	active_changed.emit(_mask, frame)

## 从既有字段推导当前应激活的状态集合。
## 这张表是本层唯一的事实来源，改它等于改「状态的定义」。
func _derive(entity) -> int:
	var mask: int = 0

	# 终局与硬控制
	if bool(entity.is_dead):
		mask |= State.DEAD
	if bool(entity._hit_stop_active):
		mask |= State.HIT_STOP
	if bool(entity._immobilize_active):
		mask |= State.IMMOBILIZED

	# 受击链
	if bool(entity._is_downed):
		mask |= State.DOWNED
	if bool(entity._launch_active):
		mask |= State.LAUNCHED
	if bool(entity.knockback_active) or float(entity.hit_stun) > 0.0:
		mask |= State.HURT

	# 位置
	if not bool(entity.is_grounded) or bool(entity._launch_active):
		mask |= State.AIRBORNE
	if bool(entity.is_grounded) and not bool(entity._launch_active) and not bool(entity._is_downed):
		mask |= State.GROUNDED

	# 无敌
	if bool(entity.is_invincible) or bool(entity.custom_invincible):
		mask |= State.INVINCIBLE
	if bool(entity._substitution_invincible):
		mask |= State.SUBSTITUTION_INVINCIBLE

	# 主动作
	if bool(entity.is_attacking):
		mask |= State.ATTACKING
	if bool(entity.ultimate_active):
		mask |= State.ULTIMATE
	if bool(entity.is_sliding):
		mask |= State.SLIDING
	if bool(entity.is_free_moving):
		mask |= State.FREE_MOVE

	# 外部位移
	if float(entity._magnetism_time) > 0.0:
		mask |= State.MAGNETIZED

	# 出招后等落地
	if bool(entity._waiting_for_land):
		mask |= State.WAITING_FOR_LAND

	return mask

# ============================================
# 查询
# ============================================

func has(state: int) -> bool:
	return (_mask & state) != 0

func has_any(states: Array) -> bool:
	for raw in states:
		if (_mask & int(raw)) != 0:
			return true
	return false

func has_all(states: Array) -> bool:
	for raw in states:
		if (_mask & int(raw)) == 0:
			return false
	return true

func get_mask() -> int:
	return _mask

func is_empty() -> bool:
	return _mask == 0

## 当前激活状态，按 PRIORITY 从高到低
func get_active_states() -> Array:
	var out: Array = []
	for raw in PRIORITY:
		var s: int = int(raw)
		if _mask & s:
			out.append(s)
	return out

## 优先级最高的那个激活状态；没有则 NONE
func get_top() -> int:
	for raw in PRIORITY:
		var s: int = int(raw)
		if _mask & s:
			return s
	return State.NONE

## 某状态已经持续了几个物理帧
func get_frames_in(state: int, frame: int = -1) -> int:
	if not has(state):
		return 0
	var now: int = frame if frame >= 0 else _last_frame
	return max(0, now - int(_entry_frame.get(state, now)))

func get_state_name(state: int) -> String:
	return str(STATE_NAMES.get(state, "STATE_%d" % state))

func get_active_names() -> Array:
	var out: Array = []
	for raw in get_active_states():
		out.append(get_state_name(int(raw)))
	return out

## 调试用单行描述，如 "HURT|LAUNCHED|AIRBORNE"
func describe() -> String:
	if _mask == 0:
		return "NONE"
	var text: String = ""
	for raw in get_active_states():
		if text != "":
			text += "|"
		text += get_state_name(int(raw))
	return text

## 为将来的快照/同步准备。掩码是 int，可以直接进网络包。
func to_dict() -> Dictionary:
	return {
		"mask": _mask,
		"names": get_active_names(),
		"top": get_top(),
		"frame": _last_frame,
	}

func reset() -> void:
	_mask = 0
	_entry_frame.clear()
