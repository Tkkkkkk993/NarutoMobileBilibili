# visual_script_component.gd
# ============================================
# 图形化脚本运行时引擎 V1 - 独立组件
# 作为 AnimatedSprite2DEntity 的子节点挂载
# ============================================

class_name VisualScriptComponent
extends Node

# ============================================
# 实体引用 (由父节点在 add_child 前设置)
# ============================================

var _entity: EntityBase

# ============================================
# 脚本数据
# ============================================

## 积木块数组 (从 visual_script.json 加载)
var _vs_blocks: Array = []
## 按ID索引的积木块字典
var _vs_blocks_by_id: Dictionary = {}
## 积木块定义字典 (从 block_defs.json 加载, name -> def)
var _vs_block_defs: Dictionary = {}
## 事件链索引: event_name -> Array[event_block_id]
var _vs_event_chains: Dictionary = {}
## 实体局部变量存储
var _vs_variables: Dictionary = {}
## 事件上下文: event_block_id -> {output_name: value}
var _vs_event_contexts: Dictionary = {}
## DEBUG开关
var _vs_debug_print: bool = false
## 事件表行数据 (从 visual_script.json 的 events.rows 加载)
var _vs_event_rows: Array = []
## 事件表链索引: event_name -> Array[row_dict]
var _vs_event_table_chains: Dictionary = {}
## 脚本运行模式: "both" | "blocks_only" | "events_only"
var _vs_run_mode: String = "both"

# ---- 事件状态追踪 ----
var _vs_prev_animation: String = ""
var _vs_exit_fired_for: String = ""
var _vs_script_set_animation: bool = false
var _vs_deferred_exit_anim: String = ""
var _vs_pending_anim: String = ""
var _vs_pending_frame_count: int = 0
## 动画切换守卫时长（秒）。运行时按物理 tick 率折算成 tick 数：
## 物理帧率降一半时守卫的墙钟长度不能跟着翻倍，否则 30Hz 下切换后头 100 毫秒的
## 帧事件（精确单帧的 slide/语音/震屏）会被整个吞掉。
const _VS_PENDING_GUARD_SEC: float = 0.05
var _vs_pending_guard_ticks: int = 3
var _vs_last_frame_idx: Dictionary = {}
var _vs_last_visual_frame: int = -1
## 已消费过的实体播放序号，见 _vs_sync_play_start。
var _vs_seen_play_seq: int = -1
var _vs_game_started_fired: bool = false
var _vs_victory_fired: bool = false
var _vs_initialized: bool = false
## 延迟执行的图标设置标记 (因 setup_icon 在 _vs_init 之前被调用)
var _vs_pending_setup_icon: bool = false
## 自定义效果持续事件触发冷却追踪
var _vs_modifier_cooldowns: Dictionary = {}
## 奥义点标记字典
var _vs_ultimate_flags: Dictionary = {}
## 事件分发重入深度: 0=空闲, >0=正在分发
var _vs_fire_depth: int = 0
## 重入时暂存的事件队列
var _vs_fire_queue: Array = []

## when_frame_changed 出生保护：VS 初始化时的时间戳
var _vs_birth_time_msec: int = 0
const _VS_BIRTH_PROTECT_MS: int = 300

var blocks_rng = RandomNumberGenerator.new()


# ============================================
# 初始化
# ============================================

func _ready():
	# 由父节点的 _deferred_heavy_init 触发实际初始化
	pass

func _vs_init():
	_vs_birth_time_msec = Time.get_ticks_msec()
	# 守卫时长按物理 tick 率折算：60Hz→3 tick（50ms），30Hz→2 tick（约 67ms）
	var ticks_per_second: float = float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	_vs_pending_guard_ticks = maxi(1, int(round(_VS_PENDING_GUARD_SEC * ticks_per_second)))
	_vs_load_script()
	_vs_load_block_defs()
	_vs_build_indexes()
	_vs_initialized = true

	# 连接动画结束信号 (用于 when_animation_exit)
	var anim_node = _entity.get_animator_node()
	if anim_node and anim_node.has_signal("animation_finished") and not anim_node.animation_finished.is_connected(_on_vs_anim_finished):
		anim_node.animation_finished.connect(_on_vs_anim_finished)

	# 连接实体生成信号 (用于 when_a_entity_create)
	if _entity.entity_manager and not _entity.entity_manager.entity_spawned.is_connected(_on_vs_entity_spawned):
		_entity.entity_manager.entity_spawned.connect(_on_vs_entity_spawned)

	# 连接广播信号
	if not _entity.broadcast_received.is_connected(_on_vs_broadcast_received):
		_entity.broadcast_received.connect(_on_vs_broadcast_received)

	# 连接受力/血量变化信号（替代原虚方法+子类转发链）
	if not _entity.receive_force.is_connected(_on_receive_force):
		_entity.receive_force.connect(_on_receive_force)
	if not _entity.hp_changed.is_connected(_on_hp_changed):
		_entity.hp_changed.connect(_on_hp_changed)

	# 连接旧有转发信号（统一改用 signals 替代子类转发）
	if not _entity.deal_hit.is_connected(_on_deal_hit):
		_entity.deal_hit.connect(_on_deal_hit)
	if not _entity.death.is_connected(_on_death):
		_entity.death.connect(_on_death)
	if not _entity.modifier_start.is_connected(_on_modifier_start):
		_entity.modifier_start.connect(_on_modifier_start)
	if not _entity.modifier_update.is_connected(_on_modifier_update):
		_entity.modifier_update.connect(_on_modifier_update)
	if not _entity.modifier_end.is_connected(_on_modifier_end):
		_entity.modifier_end.connect(_on_modifier_end)
	if not _entity.timer_out.is_connected(on_timer_out):
		_entity.timer_out.connect(on_timer_out)

	# 触发实体创建事件
	_vs_fire_event("when_entity_create")

	# 处理延迟的图标设置请求
	if _vs_pending_setup_icon:
		_vs_fire_event("when_setup_icon")
		_vs_pending_setup_icon = false

func setup_icon():
	if not _vs_initialized:
		_vs_pending_setup_icon = true
		return
	_vs_fire_event("when_setup_icon")

# ============================================
# 数据加载
# ============================================

func _vs_load_script():
	if _entity.res_path == "": return
	var script_path = _entity.res_path.get_base_dir() + "/visual_script.json"
	if not FileAccess.file_exists(script_path): return

	var file = FileAccess.open(script_path, FileAccess.READ)
	if not file: return

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		if data is Dictionary:
			_vs_blocks = data.get("blocks", [])
			var events = data.get("events", {})
			_vs_event_rows = events.get("rows", []) if events is Dictionary else []
			_vs_run_mode = data.get("run_mode", "both")
	file.close()

func _vs_load_block_defs():
	var defs_path = "res://addons/entityeditor/block_defs.json"
	if not FileAccess.file_exists(defs_path): return

	var file = FileAccess.open(defs_path, FileAccess.READ)
	if not file: return

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_vs_block_defs = {}
		var data = json.data
		if data is Dictionary:
			var defs = data.get("block_defs", [])
			if defs is Array:
				for def in defs:
					if def is Dictionary and def.has("name"):
						_vs_block_defs[def["name"]] = def
	file.close()

func _vs_build_indexes():
	# 按ID索引
	_vs_blocks_by_id.clear()
	_vs_event_chains.clear()
	_vs_event_table_chains.clear()

	for block in _vs_blocks:
		if block is Dictionary and block.has("id"):
			_vs_blocks_by_id[block.id] = block

	# 事件链索引
	for block in _vs_blocks:
		if block is Dictionary and block.type == "EVENT":
			var event_name = str(block.name)
			if not _vs_event_chains.has(event_name):
				_vs_event_chains[event_name] = []
			_vs_event_chains[event_name].append(block.id)

	# 事件表索引（递归遍历分组）
	for row in _vs_collect_all_event_rows(_vs_event_rows):
		var event_name = str(row.get("block_name", ""))
		if event_name == "": continue
		if not _vs_event_table_chains.has(event_name):
			_vs_event_table_chains[event_name] = []
		_vs_event_table_chains[event_name].append(row)

## 递归收集所有事件行（展开分组中的事件，跳过禁用分组）
func _vs_collect_all_event_rows(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		if row.get("type") == "group":
			if not bool(row.get("enabled", true)):
				continue
			result.append_array(_vs_collect_all_event_rows(row.get("rows", [])))
		elif row.get("type") == "comment":
			continue
		else:
			result.append(row)
	return result

# ============================================
# 事件检测 (在物理帧中检查)
# ============================================

func _physics_process(delta):
	if not _vs_initialized: return
	_vs_check_events(delta)

func _process(delta):
	if not _vs_initialized: return
	_vs_check_visual_events(delta)

## 收集事件表中某事件名下、指定参数值匹配的行
func _vs_collect_matching_rows(event_name: String, param_name: String, expected_value) -> Array:
	var matched: Array = []
	if not _vs_event_table_chains.has(event_name): return matched
	for row in _vs_event_table_chains[event_name]:
		if not bool(row.get("enabled", true)): continue
		var val = row.get("params", {}).get(param_name, null)
		if val == null: continue
		# 优先数值比较（避免 JSON 浮点 1.0 vs 整数 1 不匹配）
		if (val is int or val is float) and (expected_value is int or expected_value is float):
			if _vs_to_float(val) == _vs_to_float(expected_value):
				matched.append(row)
				continue
		if str(val) == str(expected_value):
			matched.append(row)
	return matched

## 收集事件表中 when_press_input 事件下、按键当前按下的行
func _vs_collect_pressed_input_rows() -> Array:
	var matched: Array = []
	if not _vs_event_table_chains.has("when_press_input"): return matched
	for row in _vs_event_table_chains["when_press_input"]:
		if not bool(row.get("enabled", true)): continue
		var key = _vs_to_int(row.get("params", {}).get("key", 0))
		if key >= 0 and key < _entity.inputs.size() and _entity.inputs[key]:
			matched.append(row)
	return matched

## when_frame_changed 出生保护：勾选后生成初期不触发
func _vs_birth_protect_active(params: Dictionary) -> bool:
	if not bool(params.get("birth_protect", false)): return false
	return Time.get_ticks_msec() - _vs_birth_time_msec < _VS_BIRTH_PROTECT_MS

## 为「某个动画的某一帧」派发三类帧事件。
##
## 抽成函数是为了让三处共用同一套判据：正常 tick 的当前帧走它自己那三条派发，
## 跳帧补偿与动画尾巴补偿都走这里。参数是动画名而不是直接读 current_animation，
## 尾巴补偿要对「上一个动画」派发，那时当前动画已经换了。
##
## 覆盖 动画帧 与 物理帧 两种类型，只排除 画面帧（它有自己的每画面帧路径）：
##   物理帧类型是"每物理帧轮询一次当前帧"，靠轮询去命中 frame_idx == N。
##   卡顿时动画在一个 idle 帧内连跳好几帧（AnimatedSprite2D 会为每个跨过的帧
##   逐一发 frame_changed，但物理帧轮询完全看不到它们），于是 frame_idx == N
##   永远不成立，挂在精确帧上的动作（突进位移、攻击、语音、震屏）被静默丢掉。
##   把物理帧也纳入补偿，等于让"精确帧"重新可见。
##   窗口类条件（a <= frame_idx <= b）会在同一 tick 内被多次求值，语义等价；
##   若某分支有副作用且只想跑一次，作者自行加一个"只执行一次"的条件块。
func _vs_fire_frame_events(anim_name: String, frame_idx: int) -> void:
	if anim_name == "":
		return
	# when_animation_playing（动画帧 / 物理帧）
	var playing_ids: Array = []
	if _vs_event_chains.has("when_animation_playing"):
		for eid in _vs_event_chains["when_animation_playing"]:
			var eblock = _vs_blocks_by_id[eid]
			if not bool(eblock.get("enabled", true)): continue
			var target_anim = str(eblock.params.get("anim_name", ""))
			if target_anim != anim_name: continue
			var frame_type = str(eblock.params.get("frame_type", "动画帧"))
			if frame_type == "画面帧": continue
			playing_ids.append(eid)
	var playing_rows: Array = []
	if _vs_event_table_chains.has("when_animation_playing"):
		for row in _vs_event_table_chains["when_animation_playing"]:
			if not bool(row.get("enabled", true)): continue
			var target_anim = str(row.get("params", {}).get("anim_name", ""))
			if target_anim != anim_name: continue
			var frame_type = str(row.get("params", {}).get("frame_type", "动画帧"))
			if frame_type == "画面帧": continue
			playing_rows.append(row)
	if playing_ids.size() > 0 or playing_rows.size() > 0:
		_vs_fire_event("when_animation_playing", {"anim_name": anim_name, "frame_idx": frame_idx}, playing_ids, playing_rows)
	# when_frame_changed（动画帧 / 物理帧）
	var fc_ids: Array = []
	if _vs_run_mode != "events_only" and _vs_event_chains.has("when_frame_changed"):
		for eid in _vs_event_chains["when_frame_changed"]:
			var eblock = _vs_blocks_by_id[eid]
			if not bool(eblock.get("enabled", true)): continue
			var frame_type = str(eblock.params.get("frame_type", "物理帧"))
			if frame_type == "画面帧": continue
			if _vs_birth_protect_active(eblock.params): continue
			fc_ids.append(eid)
	var fc_rows: Array = []
	if _vs_run_mode != "blocks_only" and _vs_event_table_chains.has("when_frame_changed"):
		for row in _vs_event_table_chains["when_frame_changed"]:
			if not bool(row.get("enabled", true)): continue
			var frame_type = str(row.get("params", {}).get("frame_type", "物理帧"))
			if frame_type == "画面帧": continue
			if _vs_birth_protect_active(row.get("params", {})): continue
			fc_rows.append(row)
	if fc_ids.size() > 0 or fc_rows.size() > 0:
		_vs_fire_event("when_frame_changed", {"anim_name": anim_name, "frame_idx": frame_idx}, fc_ids, fc_rows)
	# when_any_animation_frame_changed（动画帧 / 物理帧）
	var any_ids: Array = []
	if _vs_event_chains.has("when_any_animation_frame_changed"):
		for eid in _vs_event_chains["when_any_animation_frame_changed"]:
			var eblock = _vs_blocks_by_id[eid]
			if not bool(eblock.get("enabled", true)): continue
			var frame_type = str(eblock.params.get("frame_type", "动画帧"))
			if frame_type == "画面帧": continue
			any_ids.append(eid)
	var any_rows: Array = []
	if _vs_event_table_chains.has("when_any_animation_frame_changed"):
		for row in _vs_event_table_chains["when_any_animation_frame_changed"]:
			if not bool(row.get("enabled", true)): continue
			var frame_type = str(row.get("params", {}).get("frame_type", "动画帧"))
			if frame_type == "画面帧": continue
			any_rows.append(row)
	if any_ids.size() > 0 or any_rows.size() > 0:
		_vs_fire_event("when_any_animation_frame_changed", {"anim_name": anim_name, "frame_idx": frame_idx}, any_ids, any_rows)

## 播放起点对齐：实体每真正播一次动画就把 play_seq 加一，这里每个检查周期对一次表。
##
## 带起始帧播放时（起始帧大于 0），起始帧之前那几帧并没有播过，而帧事件的判据是
## 「游标为 -1 就把第 0 帧到当前帧全部补触发」，不动游标的话挂在第 0 帧上的动作会凭空触发一次。
##
## 同时要清掉动画切换守卫：守卫期间 anim_frame_changed 恒为假、游标不推进，
## 守卫结束后游标还是 -1，起始帧之前那几帧照样会被补出来。
##
## 起始帧为 0 时只记账不动游标，与该参数加入之前的行为完全一致。
## 游标按动画名分别存放，所以同名重播（从第 N 帧重播同一个动画）也走这里对齐。
func _vs_sync_play_start(current_animation: String) -> void:
	if _vs_seen_play_seq == _entity.play_seq:
		return
	_vs_seen_play_seq = _entity.play_seq
	var start_frame: int = _entity.play_start_frame
	if start_frame <= 0:
		return
	_vs_last_frame_idx[current_animation] = start_frame - 1
	_vs_pending_anim = ""

func _vs_check_events(delta):
	# ---- 消费「脚本自己切了动画」标记 ----
	# 该标记由 play_animation 动作置位，含义只有一个：下一次检查若观察到动画切换，
	# 这次切换是脚本自己造成的，不要反过来再报一次退出事件。
	# 它是**一次性**的，必须在这里消费掉：脚本重播「当前正在播放的那个动画」时
	# 动画名不变，下面唯一清标记的切换分支永远不执行，标记会永久留在 true 上，
	# 之后所有 when_animation_exit 与 when_any_animation_ended 都被静默吞掉
	# （表现为画布/事件表里的「当动画结束时」再也不触发）。
	# 本次检查内新置位的标记不受影响，它留给下一次检查用。
	var script_set_animation := _vs_script_set_animation
	_vs_script_set_animation = false
	var current_animation = _entity.current_animation
	var inputs = _entity.inputs

	# ---- 处理上一帧推迟的 animation_finished 退出 ----
	if _vs_deferred_exit_anim != "":
		var exit_anim = _vs_deferred_exit_anim
		_vs_deferred_exit_anim = ""
		if current_animation == exit_anim and exit_anim != "":
			var matched_deferred_ids: Array = []
			if _vs_event_chains.has("when_animation_exit"):
				for eid in _vs_event_chains["when_animation_exit"]:
					var eblock = _vs_blocks_by_id[eid]
					var target_anim = str(eblock.params.get("anim_name", ""))
					if target_anim == exit_anim:
						matched_deferred_ids.append(eid)
			var matched_deferred_rows = _vs_collect_matching_rows("when_animation_exit", "anim_name", exit_anim)
			if matched_deferred_ids.size() > 0 or matched_deferred_rows.size() > 0:
				_vs_exit_fired_for = exit_anim
				_vs_fire_event("when_animation_exit", {"anim_name": exit_anim}, matched_deferred_ids, matched_deferred_rows)
			# ---- when_any_animation_ended (deferred) ----
			# 这里读的是**本次检查内**被置位的标记：如果 when_animation_exit 的脚本
			# 刚刚同步换了动画名，就不再触发 when_any_animation_ended，否则
			# now_animation() 读到的是新动画名，可能导致条件误判
			# （例如 attack_1a 结束 -> 1a2，但 now_animation() 返回 "attack_1a2"）。
			# 重播同名动画（A 播完又播 A）不算换动画，此时按名不变处理，照常触发。
			if exit_anim != "" and not _vs_script_set_animation:
				_vs_fire_event("when_any_animation_ended", {"anim_name": exit_anim})

	# ---- when_game_start ----
	if not _vs_game_started_fired:
		if _entity.arena and _entity.arena.battle_started:
			_vs_game_started_fired = true
			_vs_fire_event("when_game_start", {})


	# ---- on_victory（当胜利时：敌人死亡 & 自己 idle，仅触发一次）----
	if not _vs_victory_fired:
		if _entity.current_animation == "idle":
			var enemies = TeamManager.get_all_enemies_of(_entity.team_id)
			var has_dead_enemy = false
			for enemy in enemies:
				if is_instance_valid(enemy) and enemy.is_dead:
					has_dead_enemy = true
					break
			if has_dead_enemy:
				_vs_victory_fired = true
				_vs_fire_event("on_victory", {})

	# ---- 动画切换检测 ----
	# deferred exit 处理器内部可能刚通过 play_animation 切了动画（置位了 _vs_script_set_animation），
	# 但下方切换判定用的是函数开头消费的局部快照，快照里没有这次置位，
	# 导致「A 结束 -> 脚本播 B」被当成外部切换，ended(A) 二次触发，
	# 此时 now_animation() 已是 B，条件误判（如 attack3 结束播 attack_air 后立刻回 idle）。
	# 这里把活标记合并进快照并清掉，让本检查内的切换判定能看到最新标记。
	if _vs_script_set_animation:
		script_set_animation = true
		_vs_script_set_animation = false
	# 重新读取动画名：deferred exit 处理可能通过 VS 动作切了动画，
	# 但局部变量 current_animation 仍是旧值，导致帧事件误判（如旧动画的 frame_idx==0 触发）
	current_animation = _entity.current_animation
	if current_animation != _vs_prev_animation:
		var old_anim = _vs_prev_animation
		_vs_prev_animation = current_animation
		_vs_pending_anim = current_animation
		_vs_pending_frame_count = 0
		_vs_last_frame_idx[current_animation] = -1

		if not script_set_animation and not _entity._immobilize_active:
			if old_anim != _vs_exit_fired_for:
				var matched_exit_ids: Array = []
				if _vs_event_chains.has("when_animation_exit"):
					for eid in _vs_event_chains["when_animation_exit"]:
						var eblock = _vs_blocks_by_id[eid]
						var target_anim = str(eblock.params.get("anim_name", ""))
						if target_anim == old_anim and old_anim != "":
							matched_exit_ids.append(eid)
				var matched_exit_rows = _vs_collect_matching_rows("when_animation_exit", "anim_name", old_anim) if old_anim != "" else []
				if matched_exit_ids.size() > 0 or matched_exit_rows.size() > 0:
					_vs_fire_event("when_animation_exit", {"anim_name": old_anim}, matched_exit_ids, matched_exit_rows)
		# ---- when_any_animation_ended ----
		if not script_set_animation and old_anim != _vs_exit_fired_for and old_anim != "":
			_vs_fire_event("when_any_animation_ended", {"anim_name": old_anim})
		_vs_exit_fired_for = ""
		# _vs_script_set_animation 已在函数开头被消费，此处不再清（见函数顶部注释）

	_vs_sync_play_start(current_animation)

	# ---- when_animation_playing ----
	var frame_val = _entity.get_current_frame()
	if _vs_pending_anim != "" and _vs_pending_anim == current_animation:
		_vs_pending_frame_count += 1
		if frame_val == 0 or _vs_pending_frame_count >= _vs_pending_guard_ticks:
			_vs_pending_anim = ""

	var last_frame = _vs_last_frame_idx.get(current_animation, -1)
	var anim_frame_changed = _vs_pending_anim == "" and current_animation != "" and frame_val != last_frame
	
	# 计算中间帧列表（仅用于"动画帧"类型的事件）
	var frames_to_trigger: Array[int] = []
	if anim_frame_changed:
		if last_frame == -1:
			# 首次采样到本动画：把 0..frame_val 全部纳入，交给下面的中间帧补偿逐帧补触发。
			# 旧实现只放当前帧，于是"动画切换守卫期间跨过的帧"永远补不回来
			# （30Hz 下 s1_0 第 2 帧的后退就是这么丢的）。
			for f in range(0, frame_val + 1):
				frames_to_trigger.append(f)
		else:
			var total_frames = _entity.get_animation_frame_count(current_animation)
			if total_frames > 0:
				if frame_val > last_frame:
					for f in range(last_frame + 1, frame_val + 1):
						frames_to_trigger.append(f)
				else:
					for f in range(last_frame + 1, total_frames):
						frames_to_trigger.append(f)
					for f in range(0, frame_val + 1):
						frames_to_trigger.append(f)
			else:
				frames_to_trigger.append(frame_val)
		_vs_last_frame_idx[current_animation] = frame_val

	# 本 tick 是否发生跨帧。跨帧时当前帧也交给下面的补偿循环按时间顺序派发，
	# 上面三条"当前帧"派发全部让位，避免同一帧被派发两次。
	var frame_catchup := frames_to_trigger.size() > 1

	# ---- when_animation_playing ----
	# 物理帧类型：每物理帧触发一次，用当前帧（持续轮询语义，如落地检测）
	# 动画帧类型：帧变化时为每个中间帧触发一次
	var matched_playing_ids: Array = []
	if _vs_event_chains.has("when_animation_playing"):
		for eid in _vs_event_chains["when_animation_playing"]:
			var eblock = _vs_blocks_by_id[eid]
			if not bool(eblock.get("enabled", true)): continue
			var target_anim = str(eblock.params.get("anim_name", ""))
			if target_anim != current_animation: continue
			var frame_type = str(eblock.params.get("frame_type", "动画帧"))
			if frame_type == "画面帧": continue
			var should_fire = (frame_type == "物理帧") or (frame_type == "动画帧" and anim_frame_changed)
			if not should_fire: continue
			matched_playing_ids.append(eid)
	var matched_playing_rows: Array = []
	if _vs_event_table_chains.has("when_animation_playing"):
		for row in _vs_event_table_chains["when_animation_playing"]:
			if not bool(row.get("enabled", true)): continue
			var target_anim = str(row.get("params", {}).get("anim_name", ""))
			if target_anim != current_animation: continue
			var frame_type = str(row.get("params", {}).get("frame_type", "动画帧"))
			if frame_type == "画面帧": continue
			var should_fire = (frame_type == "物理帧") or (frame_type == "动画帧" and anim_frame_changed)
			if not should_fire: continue
			matched_playing_rows.append(row)
	if not frame_catchup and (matched_playing_ids.size() > 0 or matched_playing_rows.size() > 0):
		_vs_fire_event("when_animation_playing", {
			"anim_name": current_animation,
			"frame_idx": frame_val
		}, matched_playing_ids, matched_playing_rows)

	# ---- when_frame_changed ----
	# 物理帧类型：每物理帧触发一次，用当前帧
	# 动画帧类型：帧变化时为每个中间帧触发一次
	var matched_fc_ids: Array = []
	if _vs_run_mode != "events_only" and _vs_event_chains.has("when_frame_changed"):
		for eid in _vs_event_chains["when_frame_changed"]:
			var eblock = _vs_blocks_by_id[eid]
			if not bool(eblock.get("enabled", true)): continue
			var frame_type = str(eblock.params.get("frame_type", "物理帧"))
			if frame_type == "画面帧": continue
			if _vs_birth_protect_active(eblock.params): continue
			matched_fc_ids.append(eid)
	var matched_fc_rows: Array = []
	if _vs_run_mode != "blocks_only" and _vs_event_table_chains.has("when_frame_changed"):
		for row in _vs_event_table_chains["when_frame_changed"]:
			if not bool(row.get("enabled", true)): continue
			var frame_type = str(row.get("params", {}).get("frame_type", "物理帧"))
			if frame_type == "画面帧": continue
			if _vs_birth_protect_active(row.get("params", {})): continue
			matched_fc_rows.append(row)
	if not frame_catchup and (matched_fc_ids.size() > 0 or matched_fc_rows.size() > 0):
		_vs_fire_event("when_frame_changed", {"anim_name": current_animation, "frame_idx": frame_val}, matched_fc_ids, matched_fc_rows)

	# ---- when_any_animation_frame_changed ----
	# 物理帧类型：每物理帧触发一次，用当前帧
	# 动画帧类型：帧变化时为每个中间帧触发一次
	var matched_any_fc_ids: Array = []
	if _vs_event_chains.has("when_any_animation_frame_changed"):
		for eid in _vs_event_chains["when_any_animation_frame_changed"]:
			var eblock = _vs_blocks_by_id[eid]
			if not bool(eblock.get("enabled", true)): continue
			var frame_type = str(eblock.params.get("frame_type", "动画帧"))
			if frame_type == "画面帧": continue
			var should_fire = (frame_type == "物理帧") or (frame_type == "动画帧" and anim_frame_changed)
			if not should_fire: continue
			matched_any_fc_ids.append(eid)
	var matched_any_fc_rows: Array = []
	if _vs_event_table_chains.has("when_any_animation_frame_changed"):
		for row in _vs_event_table_chains["when_any_animation_frame_changed"]:
			if not bool(row.get("enabled", true)): continue
			var frame_type = str(row.get("params", {}).get("frame_type", "动画帧"))
			if frame_type == "画面帧": continue
			var should_fire = (frame_type == "物理帧") or (frame_type == "动画帧" and anim_frame_changed)
			if not should_fire: continue
			matched_any_fc_rows.append(row)
	if not frame_catchup and (matched_any_fc_ids.size() > 0 or matched_any_fc_rows.size() > 0):
		_vs_fire_event("when_any_animation_frame_changed", {
			"anim_name": current_animation,
			"frame_idx": frame_val
		}, matched_any_fc_ids, matched_any_fc_rows)

	# ---- 帧事件的跳帧补偿 ----
	# 当帧索引跳变时（卡顿恢复、掉帧），把这一跳跨过的**每一帧**都按时间顺序补触发一次，
	# 当前帧也在其中（上面三条"当前帧"派发在跨帧时已让位，不会重复派发）。
	#
	# 覆盖 动画帧 与 物理帧 两种类型 —— 这一点很关键：
	#   物理帧类型是"每物理帧轮询一次当前帧"，靠轮询去命中 frame_idx == N。
	#   卡顿时动画在一个 idle 帧内连跳好几帧（AnimatedSprite2D 会为每个跨过的帧
	#   逐一发 frame_changed，但物理帧轮询完全看不到它们），于是 frame_idx == N
	#   永远不成立，挂在精确帧上的动作（突进位移、攻击、语音、震屏）被静默丢掉。
	#   把物理帧也纳入补偿，等于让"精确帧"重新可见。
	#   窗口类条件（a <= frame_idx <= b）会在同一 tick 内被多次求值，语义等价；
	#   若某分支有副作用且只想跑一次，作者自行加一个"只执行一次"条件块。
	# 画面帧类型不在这里处理，它有自己的每画面帧路径（_vs_check_visual_events）。
	# 跨帧时动画若直接播完，尾巴那几帧走 _vs_replay_anim_tail，不在这里补。
	# 三类派发的判据收在 _vs_fire_frame_events 一处，三处调用共用。
	if frame_catchup:
		# 按时间顺序逐帧补触发，当前帧也在其中（上面三条"当前帧"派发已让位）。
		# 顺序很关键：先发生的先做，后发生的才能覆盖它。
		# 反过来——当前帧先、被跨过的帧后——会让"滑动前允许转向、滑动后禁止"这类设计失效，
		# 也会让"突进接刹车"里的刹车被前面那几帧的突进覆盖。
		for f in frames_to_trigger:
			_vs_fire_frame_events(current_animation, f)

	# ---- when_press_input ----
	var matched_input_ids: Array = []
	if _vs_event_chains.has("when_press_input"):
		for eid in _vs_event_chains["when_press_input"]:
			var eblock = _vs_blocks_by_id[eid]
			var key = _vs_to_int(eblock.params.get("key", 0))
			if key >= 0 and key < inputs.size() and inputs[key]:
				matched_input_ids.append(eid)
	var matched_input_rows = _vs_collect_pressed_input_rows()
	if matched_input_ids.size() > 0 or matched_input_rows.size() > 0:
		_vs_fire_event("when_press_input", {"key": 0}, matched_input_ids, matched_input_rows)

# ============================================
# 画面帧事件检测 (在 _process 中调用)
# ============================================

func _vs_check_visual_events(delta):
	var current_animation = _entity.current_animation

	# ---- 画面帧模式的 when_frame_changed（每画面帧无条件触发）----
	var matched_fc_ids: Array = []
	if _vs_run_mode != "events_only" and _vs_event_chains.has("when_frame_changed"):
		for eid in _vs_event_chains["when_frame_changed"]:
			var eblock = _vs_blocks_by_id[eid]
			if not bool(eblock.get("enabled", true)): continue
			var frame_type = str(eblock.params.get("frame_type", "物理帧"))
			if frame_type != "画面帧": continue
			if _vs_birth_protect_active(eblock.params): continue
			matched_fc_ids.append(eid)
	var matched_fc_rows: Array = []
	if _vs_run_mode != "blocks_only" and _vs_event_table_chains.has("when_frame_changed"):
		for row in _vs_event_table_chains["when_frame_changed"]:
			if not bool(row.get("enabled", true)): continue
			var frame_type = str(row.get("params", {}).get("frame_type", "物理帧"))
			if frame_type != "画面帧": continue
			if _vs_birth_protect_active(row.get("params", {})): continue
			matched_fc_rows.append(row)
	if matched_fc_ids.size() > 0 or matched_fc_rows.size() > 0:
		_vs_fire_event("when_frame_changed", {"anim_name": current_animation, "frame_idx": _entity.get_current_frame()}, matched_fc_ids, matched_fc_rows)

	# 画面帧变化检测
	var anim_node = _entity.get_animator_node()
	var visual_frame_val = -1
	if anim_node and "frame" in anim_node:
		visual_frame_val = anim_node.frame
	var visual_frame_changed = visual_frame_val != _vs_last_visual_frame
	if visual_frame_changed:
		_vs_last_visual_frame = visual_frame_val

	if not visual_frame_changed:
		return

	var frame_val = _entity.get_current_frame()

	# ---- 画面帧模式的 when_animation_playing ----
	var matched_playing_ids: Array = []
	if _vs_event_chains.has("when_animation_playing"):
		for eid in _vs_event_chains["when_animation_playing"]:
			var eblock = _vs_blocks_by_id[eid]
			if not bool(eblock.get("enabled", true)): continue
			var target_anim = str(eblock.params.get("anim_name", ""))
			if target_anim != current_animation: continue
			var frame_type = str(eblock.params.get("frame_type", "动画帧"))
			if frame_type != "画面帧": continue
			matched_playing_ids.append(eid)
	var matched_playing_rows: Array = []
	if _vs_event_table_chains.has("when_animation_playing"):
		for row in _vs_event_table_chains["when_animation_playing"]:
			if not bool(row.get("enabled", true)): continue
			var target_anim = str(row.get("params", {}).get("anim_name", ""))
			if target_anim != current_animation: continue
			var frame_type = str(row.get("params", {}).get("frame_type", "动画帧"))
			if frame_type != "画面帧": continue
			matched_playing_rows.append(row)
	if matched_playing_ids.size() > 0 or matched_playing_rows.size() > 0:
		_vs_fire_event("when_animation_playing", {
			"anim_name": current_animation,
			"frame_idx": frame_val
		}, matched_playing_ids, matched_playing_rows)

	# ---- 画面帧模式的 when_any_animation_frame_changed ----
	var matched_any_ids: Array = []
	if _vs_event_chains.has("when_any_animation_frame_changed"):
		for eid in _vs_event_chains["when_any_animation_frame_changed"]:
			var eblock = _vs_blocks_by_id[eid]
			if not bool(eblock.get("enabled", true)): continue
			var frame_type = str(eblock.params.get("frame_type", "动画帧"))
			if frame_type != "画面帧": continue
			matched_any_ids.append(eid)
	var matched_any_rows: Array = []
	if _vs_event_table_chains.has("when_any_animation_frame_changed"):
		for row in _vs_event_table_chains["when_any_animation_frame_changed"]:
			if not bool(row.get("enabled", true)): continue
			var frame_type = str(row.get("params", {}).get("frame_type", "动画帧"))
			if frame_type != "画面帧": continue
			matched_any_rows.append(row)
	if matched_any_ids.size() > 0 or matched_any_rows.size() > 0:
		_vs_fire_event("when_any_animation_frame_changed", {
			"anim_name": current_animation,
			"frame_idx": frame_val
		}, matched_any_ids, matched_any_rows)

# ---- 攻击命中事件 (由实体委托调用) ----

func _on_attack_hit(hit_result):
	if not _vs_initialized: return

	var target_entity = hit_result.target_entity as EntityBase
	if not target_entity: return

	var box_config = hit_result.attack_config
	var hit_eff_pos = _entity.calculate_intersection(hit_result, box_config.to_dict())
	var abox_name = hit_result.attack_box_name
	var ipoint = Vector3(hit_eff_pos.x, target_entity.position_3d.y, hit_eff_pos.y)

	_vs_fire_event("when_attack", {
		"target": target_entity,
		"abox_name": abox_name,
		"ipoint": ipoint
	})

	# 按攻击框名过滤的专用事件
	_vs_fire_attack_box_hit_event(abox_name, target_entity, ipoint)

func _vs_fire_attack_box_hit_event(abox_name: String, target: EntityBase, ipoint: Vector3):
	var ctx = {"target": target, "ipoint": ipoint}
	var event_name = "when_attack_box_hit"

	var matched_ids: Array = []
	if _vs_run_mode != "events_only" and _vs_event_chains.has(event_name):
		for eid in _vs_event_chains[event_name]:
			var eblock = _vs_blocks_by_id.get(eid)
			if not eblock: continue
			if not bool(eblock.get("enabled", true)): continue
			var expected = str(eblock.get("params", {}).get("abox_name", ""))
			if expected != "" and expected != abox_name:
				continue
			matched_ids.append(eid)

	var matched_rows: Array = []
	if _vs_run_mode != "blocks_only" and _vs_event_table_chains.has(event_name):
		for row in _vs_event_table_chains[event_name]:
			if not bool(row.get("enabled", true)): continue
			var expected = str(row.get("params", {}).get("abox_name", ""))
			if expected != "" and expected != abox_name:
				continue
			matched_rows.append(row)

	if matched_ids.size() > 0 or matched_rows.size() > 0:
		_vs_fire_event(event_name, ctx, matched_ids, matched_rows)

# ---- 被攻击命中事件 (由实体委托调用) ----

func _on_deal_hit(attacker: Node2D):
	if _vs_initialized:
		_vs_fire_event("when_hit", {"entity": attacker})

func _on_receive_force(kv: Vector2, zv: float):
	if _vs_initialized:
		_vs_fire_event("when_receive_force", {"kv": kv, "zv": zv})

func _on_hp_changed(old_hp: float, new_hp: float):
	if _vs_initialized:
		var delta = new_hp - old_hp
		_vs_fire_event("when_hp_changed", {"delta": delta, "old_hp": old_hp, "new_hp": new_hp})

func _on_death():
	if _vs_initialized:
		_vs_fire_event("when_death", {"attacker": _entity._last_attacker if _entity._last_attacker else null})

# ---- 自定义效果事件 (由实体委托调用) ----

func _on_modifier_start(type: String, power: int, time_left: float = -2.0, target: Node2D = null):
	if not _vs_initialized: return
	_vs_fire_modifier_event("when_modifier_start", type, power, time_left, target)

func _on_modifier_update(type: String, power: int, time_left: float = -2.0, target: Node2D = null):
	if not _vs_initialized: return
	_vs_fire_modifier_event("when_modifier_update", type, power, time_left, target)

func _on_modifier_end(type: String, power: int, time_left: float = -2.0, target: Node2D = null):
	if not _vs_initialized: return
	_vs_fire_modifier_event("when_modifier_end", type, power, time_left, target)

func _vs_fire_modifier_event(event_name: String, type: String, power: int, time_left: float = -2.0, target: Node2D = null):
	if target == null:
		target = _entity
	var ctx = {"mod_type": type, "mod_power": power, "mod_time": time_left, "target": target}
	var now = Time.get_ticks_msec() / 1000.0

	# 积木模式：按 mod_type + interval 过滤
	var matched_ids: Array = []
	if _vs_run_mode != "events_only" and _vs_event_chains.has(event_name):
		for eid in _vs_event_chains[event_name]:
			var eblock = _vs_blocks_by_id.get(eid)
			if not eblock: continue
			if not bool(eblock.get("enabled", true)): continue
			var expected_type = str(eblock.get("params", {}).get("mod_type", ""))
			if expected_type != "" and expected_type != type:
				continue
			if event_name == "when_modifier_update":
				var interval = _vs_to_float(eblock.params.get("interval", 0.0))
				if interval > 0.0:
					var key = "b%d" % eid
					var last = _vs_modifier_cooldowns.get(key, -INF)
					if now - last < interval:
						continue
					_vs_modifier_cooldowns[key] = now
			matched_ids.append(eid)

	# 事件表模式：按 mod_type + interval 过滤
	var matched_rows: Array = []
	if _vs_run_mode != "blocks_only" and _vs_event_table_chains.has(event_name):
		for row in _vs_event_table_chains[event_name]:
			if not bool(row.get("enabled", true)): continue
			var expected_type = str(row.get("params", {}).get("mod_type", ""))
			if expected_type != "" and expected_type != type:
				continue
			if event_name == "when_modifier_update":
				var interval = _vs_to_float(row.get("params", {}).get("interval", 0.0))
				if interval > 0.0:
					var key = "r%s" % row.get("id", str(row.hash()))
					var last = _vs_modifier_cooldowns.get(key, -INF)
					if now - last < interval:
						continue
					_vs_modifier_cooldowns[key] = now
			matched_rows.append(row)

	if matched_ids.size() > 0 or matched_rows.size() > 0:
		_vs_fire_event(event_name, ctx, matched_ids, matched_rows)

# ---- 动画播放结束信号 ----

func _on_vs_anim_finished():
	if not _vs_initialized: return
	# 抓取/定身状态下，不让动画退出事件触发（防止 VS 脚本切回 idle）
	if _entity._immobilize_active: return
	var finished_anim := _entity.current_animation
	# 卡顿可能让一次采样直接跨到动画末帧，中间那几帧的帧事件一次都没轮到。
	# 此刻动画名与总帧数都还是这个旧动画的，正好把尾巴补上。
	_vs_replay_anim_tail(finished_anim)
	_vs_deferred_exit_anim = finished_anim

## 非循环动画**自然播完**时，把"上次采样之后到末帧"之间被卡顿吞掉的帧补触发。
##
## 挂在 animation_finished 信号上是有意的：只有自然播完才走这里，
## 被脚本或退出链打断的动画不会触发这个信号，所以补出来的一定是真播过的那几帧，
## 不会凭空造出没发生的突进或攻击。补完把游标推到末帧，避免下一 tick 再补一次。
func _vs_replay_anim_tail(anim_name: String) -> void:
	if anim_name == "":
		return
	var last_sampled: int = int(_vs_last_frame_idx.get(anim_name, -1))
	var total := _entity.get_animation_frame_count(anim_name)
	if last_sampled < 0 or total <= 0:
		return
	for f in range(last_sampled + 1, total):
		_vs_fire_frame_events(anim_name, f)
	_vs_last_frame_idx[anim_name] = total - 1

# ---- 监听其他实体创建事件 ----

func _on_vs_entity_spawned(entity: EntityBase):
	if not _vs_initialized: return
	if entity == _entity: return
	_vs_fire_event("when_a_entity_create", {"entity": entity})

# ---- 广播事件 ----

func _on_vs_broadcast_received(msg: String, data: Dictionary, is_global: bool):
	if not _vs_initialized: return
	var event_name = "when_global_broadcast" if is_global else "when_private_broadcast"
	if _vs_debug_print:
		print("[DEBUG] _on_vs_broadcast_received: event=", event_name, " msg='", msg, "' data=", data)
	var matched_ids: Array = []
	if _vs_event_chains.has(event_name):
		for eid in _vs_event_chains[event_name]:
			var eblock = _vs_blocks_by_id[eid]
			var target_msg = str(eblock.params.get("msg", ""))
			if target_msg == msg:
				matched_ids.append(eid)

	var matched_rows = _vs_collect_matching_rows(event_name, "msg", msg)
	if _vs_debug_print:
		print("[DEBUG] _on_vs_broadcast_received: matched_ids=", matched_ids, " matched_rows=", matched_rows)

	if matched_ids.size() > 0 or matched_rows.size() > 0:
		_vs_fire_event(event_name, {"msg": msg, "data": data}, matched_ids, matched_rows)

# ---- 计时结束事件 (由实体委托调用) ----

func on_timer_out(cd_id: int):
	if not _vs_initialized: return
	var matched_ids: Array = []
	if _vs_event_chains.has("when_timer_out"):
		for eid in _vs_event_chains["when_timer_out"]:
			var eblock = _vs_blocks_by_id[eid]
			var target_cd_id = _vs_to_int(eblock.params.get("cd_id", 0))
			if target_cd_id == cd_id:
				matched_ids.append(eid)
	var matched_rows = _vs_collect_matching_rows("when_timer_out", "cd_id", cd_id)

	if matched_ids.size() > 0 or matched_rows.size() > 0:
		_vs_fire_event("when_timer_out", {"cd_id": cd_id}, matched_ids, matched_rows)

# ============================================
# 事件分发
# ============================================

func _vs_fire_event(event_name: String, context: Dictionary = {}, filter_block_ids: Array = [], filter_rows: Array = []):
	if _vs_fire_depth > 0:
		_vs_fire_queue.append([event_name, context, filter_block_ids, filter_rows])
		return

	_vs_fire_depth += 1
	if _vs_run_mode != "events_only" and _vs_event_chains.has(event_name):
		var target_ids: Array = filter_block_ids if filter_block_ids.size() > 0 else _vs_event_chains[event_name]
		for event_block_id in target_ids:
			var event_block = _vs_blocks_by_id.get(event_block_id)
			if not event_block: continue
			if not bool(event_block.get("enabled", true)): continue
			_vs_event_contexts[event_block_id] = context
			var next_id = event_block.get("stack_below_id", -1)
			if next_id >= 0:
				_vs_execute_chain.call_deferred(next_id, event_block_id)

	if _vs_run_mode != "blocks_only":
		var rows_to_fire: Array = []
		if filter_rows.size() > 0:
			rows_to_fire = filter_rows
		elif filter_block_ids.size() == 0 and _vs_event_table_chains.has(event_name):
			rows_to_fire = _vs_event_table_chains[event_name]
		for row in rows_to_fire:
			if not bool(row.get("enabled", true)): continue
			_vs_execute_event_children(row.get("children", []), row, context)
	_vs_fire_depth -= 1

	# 执行完毕后处理重入队列
	if _vs_fire_depth == 0 and _vs_fire_queue.size() > 0:
		var queue = _vs_fire_queue.duplicate()
		_vs_fire_queue.clear()
		for args in queue:
			_vs_fire_event(args[0], args[1], args[2], args[3])

# ============================================
# 事件表执行引擎
# ============================================

func _vs_execute_event_children(children: Array, source_row: Dictionary, context: Dictionary):
	var i = 0
	while i < children.size():
		if _entity._is_quitting: return
		var child = children[i]
		if not bool(child.get("enabled", true)):
			var bname = str(child.get("block_name", ""))
			if bname == "if_condition":
				i = _vs_skip_if_chain(children, i)
			else:
				i += 1
			continue
		var bname = str(child.get("block_name", ""))
		if bname == "if_condition":
			i = await _vs_execute_if_chain(children, i, source_row, context)
		else:
			await _vs_execute_event_node(child, source_row, context)
			i += 1

func _vs_execute_if_chain(children: Array, start_idx: int, source_row: Dictionary, context: Dictionary) -> int:
	var i = start_idx
	var satisfied = false
	var if_node = children[i]
	var if_params = _vs_resolve_event_params(if_node, context)
	if _vs_to_bool(if_params.get("condition", false)):
		await _vs_execute_event_children(if_node.get("children", []), source_row, context)
		satisfied = true
	i += 1
	while i < children.size():
		var sibling = children[i]
		var sib_name = str(sibling.get("block_name", ""))

		if not bool(sibling.get("enabled", true)):
			i += 1
			if sib_name == "else_block":
				break
			continue
		if sib_name == "else_if":
			if not satisfied:
				var ei_params = _vs_resolve_event_params(sibling, context)
				if _vs_to_bool(ei_params.get("condition", false)):
					await _vs_execute_event_children(sibling.get("children", []), source_row, context)
					satisfied = true
			i += 1
		elif sib_name == "else_block":
			if not satisfied:
				await _vs_execute_event_children(sibling.get("children", []), source_row, context)
				satisfied = true
			i += 1
			break
		else:
			break
	return i

func _vs_skip_if_chain(children: Array, start_idx: int) -> int:
	var i = start_idx + 1
	while i < children.size():
		var sibling = children[i]
		var sib_name = str(sibling.get("block_name", ""))
		if sib_name == "else_if":
			i += 1
		elif sib_name == "else_block":
			i += 1
			break
		else:
			break
	return i

func _vs_execute_event_node(node: Dictionary, source_row: Dictionary, context: Dictionary):
	var block_name = str(node.get("block_name", ""))
	if block_name == "": return
	var def = _vs_block_defs.get(block_name, {})
	var block_type = int(def.get("type", -1))
	match block_type:
		1: # ACTION
			var params = _vs_resolve_event_params(node, context)
			await _vs_dispatch_action(block_name, params)
		2: # CONDITION
			if block_name == "else_if" or block_name == "else_block":
				return
			var params = _vs_resolve_event_params(node, context)
			await _vs_execute_event_condition(node, block_name, params, source_row, context)
		_:
			pass

func _vs_execute_event_condition(node: Dictionary, block_name: String, params: Dictionary, source_row: Dictionary, context: Dictionary):
	var children = node.get("children", [])

	match block_name:
		"if_condition":
			if _vs_to_bool(params.get("condition", false)):
				await _vs_execute_event_children(children, source_row, context)
		"if_else":
			if _vs_to_bool(params.get("condition", false)):
				await _vs_execute_event_children(children, source_row, context)
		"repeat_forever":
			while not _entity._is_quitting:
				await _vs_execute_event_children(children, source_row, context)
				await _entity.wait_frame()
		"repeat_in_range":
			var n = int(params.get("n", 0))
			for _i in range(n):
				if _entity._is_quitting: return
				await _vs_execute_event_children(children, source_row, context)
		"repeat_while":
			while _vs_to_bool(params.get("bool", false)):
				if _entity._is_quitting: return
				await _vs_execute_event_children(children, source_row, context)
				await _entity.wait_frame()
		_:
			var method_name = "_condition_" + block_name
			if has_method(method_name):
				await call(method_name, node, params, context)

# ============================================
# 事件表参数解析 + 表达式求值
# ============================================

var _vs_expr_temp_vars: Dictionary = {}
var _vs_expr_temp_counter: int = 0

func _vs_resolve_event_params(node: Dictionary, context: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var raw_params = node.get("params", {})
	var exprs = node.get("exprs", {})
	for param_name in raw_params:
		var value = raw_params[param_name]
		if exprs.has(param_name):
			var expr_str = str(exprs[param_name]).strip_edges()
			if _vs_debug_print:
				print("[DEBUG] _vs_resolve_event_params: param='", param_name, "' expr='", expr_str, "' context=", context)
			if expr_str != "":
				var evaluated = _vs_eval_expr(expr_str, context)
				if _vs_debug_print:
					print("[DEBUG] _vs_resolve_event_params: evaluated=", evaluated, " type=", typeof(evaluated))
				if evaluated != null:
					value = evaluated
				elif _vs_debug_print:
					print("[DEBUG] _vs_resolve_event_params: expr returned null")
		result[param_name] = value
	if _vs_debug_print:
		print("[DEBUG] _vs_resolve_event_params final=", result)
	return result

func _vs_eval_expr(expr_str: String, context: Dictionary) -> Variant:
	expr_str = expr_str.strip_edges()
	if expr_str == "": return null
	_vs_expr_temp_vars.clear()
	_vs_expr_temp_counter = 0
	var processed = _vs_preprocess_value_calls(expr_str, context)
	if processed == "": return null
	var input_names: Array = []
	var input_values: Array = []
	for k in _vs_variables:
		if _is_valid_identifier(str(k)):
			input_names.append(str(k))
			input_values.append(_vs_variables[k])
	for k in context:
		if _is_valid_identifier(str(k)) and not (str(k) in input_names):
			input_names.append(str(k))
			input_values.append(context[k])
	for k in _vs_expr_temp_vars:
		input_names.append(str(k))
		input_values.append(_vs_expr_temp_vars[k])

	if _vs_debug_print:
		print("[VS-EQ] raw='", expr_str, "' → processed='", processed, "'")
		print("[VS-EQ] names=", input_names, " vals=", input_values)

	var result = _vs_try_eval(processed, input_names, input_values, expr_str)
	if result != null:
		return result

	# 重试：复杂类型(Dictionary/Array)包上 str()
	var replaced = false
	for i in input_names.size():
		if input_values[i] is Dictionary or input_values[i] is Array:
			var var_name = input_names[i]
			var re = RegEx.new()
			re.compile("(?<![a-zA-Z0-9_])" + var_name + "(?!\\s*\\()")
			if re.search(processed):
				processed = re.sub(processed, "str(" + var_name + ")", true)
				replaced = true

	if replaced:
		result = _vs_try_eval(processed, input_names, input_values, expr_str)
		if result != null:
			return result

	push_warning("[VS-EXPR] 执行失败: '%s' → 尝试 str() 包裹后仍失败" % expr_str)
	return null

func _vs_try_eval(processed: String, input_names: Array, input_values: Array, raw_expr: String) -> Variant:
	var expr = Expression.new()
	var err = expr.parse(processed, input_names)
	if err != OK:
		push_warning("[VS-EXPR] 解析失败: '%s' → '%s' 错误: %s" % [raw_expr, processed, expr.get_error_text()])
		return null
	var result = expr.execute(input_values, _entity)
	if expr.has_execute_failed():
		push_warning("[VS-EXPR] 执行失败: '%s' → '%s' 错误: %s" % [raw_expr, processed, expr.get_error_text()])
		return null
	return result

func _vs_preprocess_value_calls(expr_str: String, context: Dictionary) -> String:
	var s = expr_str
	# 替换内置常量
	s = s.replace("INT_MAX", str(2147483647))
	s = s.replace("INT_MIN", str(-2147483648))
	s = s.replace("PI", str(PI))
	s = s.replace("TAU", str(TAU))
	s = s.replace("INF", str(INF))
	s = s.replace("NAN", str(NAN))
	if _vs_debug_print:
		print("[VS-EQ] _vs_preprocess_value_calls input: '", s, "' context=", context)
	var guard = 0
	while guard < 100:
		guard += 1
		var found = _find_innermost_value_call(s)
		if found == null: break
		var call_name = found["name"]
		var args_str = found["args"]
		var start = found["start"]
		var end = found["end"]
		if call_name.begins_with("_var_ref_"):
			var var_name = call_name.substr("_var_ref_".length())
			s = s.substr(0, start) + var_name + s.substr(end)
			continue
		if not _vs_block_defs.has(call_name):
			# 未知函数名，原样保留（如 str() 等 Godot 内置函数）
			s = s.substr(0, start) + call_name + "(" + args_str + ")" + s.substr(end)
			continue
		var arg_strs = _vs_split_top_level_args(args_str)
		var def = _vs_block_defs.get(call_name, {})
		var def_params = def.get("params", [])
		var params: Dictionary = {}
		for i in range(arg_strs.size()):
			var arg_val = _vs_eval_arg(arg_strs[i], context)
			if i < def_params.size():
				params[def_params[i].name] = arg_val
		var result = _vs_dispatch_value(call_name, params)
		var literal = _vs_value_to_expr_literal(result)
		s = s.substr(0, start) + literal + s.substr(end)
	# 把所有 == 替换为直接比较结果，走 _value_compare 相同的路径
	var before = s
	s = _vs_replace_eq_with_compare(s, context)
	if _vs_debug_print and before != s:
		print("[VS-EQ] after eq replace: '", before, "' -> '", s, "'")
	# 转换链式比较: a <= b <= c -> a <= b and b <= c
	var before2 = s
	s = _vs_transform_chained_comparisons(s)
	if _vs_debug_print and before2 != s:
		print("[VS-EQ] after chain transform: '", before2, "' -> '", s, "'")
	return s

# 在 == 之间插入空字符标记，避免 _find_innermost_value_call 误识
func _vs_replace_eq_with_compare(s: String, context: Dictionary) -> String:
	# 扫描字符串中的 ==，提取左右操作数，分别求值后用 GDScript 原生 == 比较
	# 这样可以绕过 Expression 对 StringName vs String 比较的限制
	var i = 0
	while i < s.length():
		if s[i] == '"':
			i += 1
			while i < s.length() and s[i] != '"':
				if s[i] == '\\': i += 1
				i += 1
			i += 1
			continue

		# 处理 == 和 !=
		var is_eq = false
		var is_neq = false
		if i + 1 < s.length() and s[i] == '=' and s[i+1] == '=':
			is_eq = true
		elif i + 1 < s.length() and s[i] == '!' and s[i+1] == '=':
			is_neq = true
		if is_eq or is_neq:
			# 提取左操作数：跳过 ==/!= 前的空格，再向左扫描
			var left_end = i
			var scan_l = left_end - 1
			while scan_l >= 0 and s[scan_l] == ' ':
				scan_l -= 1
			var left_start = 0
			if scan_l >= 0:
				var paren_depth = 0
				var j = scan_l
				while j >= 0:
					if s[j] == ')':
						paren_depth += 1
					elif s[j] == '(':
						if paren_depth <= 0:
							break  # 外层 (，不属于操作数
						paren_depth -= 1
					elif paren_depth == 0 and (s[j] == ' ' or s[j] in [',']):
						break
					elif paren_depth == 0 and s[j] in ['(', ')']:
						if s[j] == '(' and j > 0:
							var c = s[j-1]
							if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == ")":
								j -= 1
								continue
						break
					j -= 1
				left_start = j + 1
			var left_raw = s.substr(left_start, left_end - left_start).strip_edges()

			# 提取右操作数：跳过 ==/!= 后的空格，再向右扫描
			var right_start = i + 2
			while right_start < s.length() and s[right_start] == ' ':
				right_start += 1
			var right_end = right_start
			var paren_depth = 0
			var j = right_start
			while j < s.length():
				if s[j] == '(':
					paren_depth += 1
				elif s[j] == ')':
					if paren_depth <= 0:
						break  # 外层 )，不属于操作数
					paren_depth -= 1
				elif paren_depth == 0 and (s[j] == ' ' or s[j] in ['(', ')', ',']):
					break
				j += 1
			right_end = j
			var right_raw = s.substr(right_start, right_end - right_start).strip_edges()

			# 分别求值左右操作数
			var left_val = _vs_eval_eq_side(left_raw, context)
			var right_val = _vs_eval_eq_side(right_raw, context)

			# 兼容不同类型比较（如 String vs int），转成同类型再比
			var eq = false
			if typeof(left_val) == typeof(right_val):
				eq = left_val == right_val
			else:
				var lv = str(left_val) if left_val != null else ""
				var rv = str(right_val) if right_val != null else ""
				eq = lv == rv
			if is_neq:
				eq = not eq
			if _vs_debug_print:
				var op_str = "!=" if is_neq else "=="
				print("[VS-EQ] '", left_raw, "' (", typeof(left_val), "=", left_val, ") ", op_str, " '", right_raw, "' (", typeof(right_val), "=", right_val, ") → ", eq)
			var replacement = "true" if eq else "false"

			s = s.substr(0, left_start) + replacement + s.substr(right_end)
			i = left_start + replacement.length()
			continue

		i += 1

	return s

# 转换链式比较: a <= b <= c -> a <= b and b <= c
# Expression 类可能不完整支持链式比较，用 and 拆开确保兼容
func _vs_transform_chained_comparisons(s: String) -> String:
	var changed = true
	while changed:
		changed = false
		var i = 0
		while i < s.length():
			if s[i] == '"':
				i += 1
				while i < s.length() and s[i] != '"':
					if s[i] == '\\': i += 1
					i += 1
				i += 1
				continue

			var found_op = false
			var op = ""; var op_len = 0
			for cand in ["<=", ">="]:
				if i + 1 < s.length() and s[i] == cand[0] and s[i+1] == cand[1]:
					op = cand; op_len = 2; found_op = true; break
			if not found_op and s[i] in ['<', '>']:
				if not (i > 0 and s[i-1] in ['!', '=']):
					op = s[i]; op_len = 1; found_op = true
			if not found_op:
				i += 1; continue

			# 扫描中间表达式结束位置（遇到下一个 OP、and/or 即停）
			var mid_start = i + op_len
			while mid_start < s.length() and s[mid_start] == ' ':
				mid_start += 1
			var mid_end = mid_start
			var paren_depth = 0
			while mid_end < s.length():
				var c = s[mid_end]
				if c == '(': paren_depth += 1
				elif c == ')': paren_depth -= 1
				elif paren_depth == 0:
					if c in ['<', '>']: break
					if c == '=' and mid_end + 1 < s.length() and s[mid_end+1] == '=': break
					if mid_end + 3 <= s.length() and s.substr(mid_end, 3) == "and": break
					if mid_end + 2 <= s.length() and s.substr(mid_end, 2) == "or": break
				mid_end += 1
			if mid_end >= s.length():
				i += 1; continue

			# 检查后面是否紧跟另一个比较运算符
			var op2_pos = mid_end
			while op2_pos < s.length() and s[op2_pos] == ' ':
				op2_pos += 1
			var is_chain = false
			var op2 = ""; var op2_len = 0
			for cand in ["<=", ">="]:
				if op2_pos + 1 < s.length() and s[op2_pos] == cand[0] and s[op2_pos+1] == cand[1]:
					op2 = cand; op2_len = 2; is_chain = true; break
			if not is_chain and op2_pos < s.length() and s[op2_pos] in ['<', '>']:
				op2 = s[op2_pos]; op2_len = 1; is_chain = true
			if not is_chain:
				i += 1; continue

			# 提取左操作数（向左扫描）
			var left_end = i
			var scan = left_end - 1
			while scan >= 0 and s[scan] == ' ': scan -= 1
			var left_start = 0
			if scan >= 0:
				var pd = 0; var j = scan
				while j >= 0:
					if s[j] == ')': pd += 1
					elif s[j] == '(': pd -= 1
					elif pd == 0 and (s[j] == ' ' or s[j] in ['(', ')', ',']): break
					j -= 1
				left_start = j + 1

			var mid_raw = s.substr(mid_start, mid_end - mid_start).strip_edges()

			# 提取 OP2 的右操作数
			var right_start = op2_pos + op2_len
			while right_start < s.length() and s[right_start] == ' ':
				right_start += 1
			var right_end = right_start
			var pd = 0
			while right_end < s.length():
				var c = s[right_end]
				if c == '(': pd += 1
				elif c == ')': pd -= 1
				elif pd == 0:
					if c in ['<', '>']: break
					if right_end + 3 <= s.length() and s.substr(right_end, 3) == "and": break
					if right_end + 2 <= s.length() and s.substr(right_end, 2) == "or": break
				right_end += 1

			var left_raw = s.substr(left_start, left_end - left_start).strip_edges()
			var right_raw = s.substr(right_start, right_end - right_start).strip_edges()

			# 左 OP1 中 and 中 OP2 右
			var replacement = str(left_raw, " ", op, " ", mid_raw, " and ", mid_raw, " ", op2, " ", right_raw)
			s = s.substr(0, left_start) + replacement + s.substr(right_end)
			changed = true
			break  # 重新扫描，避免位置错乱
	return s

# 对 == 一侧的表达式求值（不触发 _vs_replace_eq_with_compare，避免递归）
func _vs_eval_eq_side(raw: String, context: Dictionary) -> Variant:
	raw = raw.strip_edges()
	if raw.is_empty():
		return null

	# 引号字符串
	if raw.begins_with('"') and raw.ends_with('"'):
		return raw.substr(1, raw.length() - 2)

	# 数字字面量
	if raw.is_valid_int():
		return raw.to_int()
	if raw.is_valid_float():
		return raw.to_float()

	# 布尔字面量
	if raw == "true": return true
	if raw == "false": return false

	# 上下文变量
	if context.has(raw):
		return context[raw]
	if _vs_variables.has(raw):
		return _vs_variables[raw]

	# 复杂表达式（如 str(abox_name), 数学运算等）：用 Expression 求值
	# 注意：这里不用 _vs_preprocess_value_calls，因为值块已经在外部处理完了
	var input_names: Array = []
	var input_values: Array = []
	for k in _vs_variables:
		if _is_valid_identifier(str(k)):
			input_names.append(str(k))
			input_values.append(_vs_variables[k])
	for k in context:
		if _is_valid_identifier(str(k)) and not (str(k) in input_names):
			input_names.append(str(k))
			input_values.append(context[k])
	for k in _vs_expr_temp_vars:
		if _is_valid_identifier(str(k)) and not (str(k) in input_names):
			input_names.append(str(k))
			input_values.append(_vs_expr_temp_vars[k])

	var expr = Expression.new()
	var err = expr.parse(raw, input_names)
	if err == OK:
		var result = expr.execute(input_values, _entity)
		if not expr.has_execute_failed():
			return result

	# 兜底：原样返回字符串
	if _vs_debug_print:
		print("[VS-EQ] _vs_eval_eq_side fallback: raw='", raw, "'")
	return raw

func _find_innermost_value_call(s: String) -> Variant:
	var i = 0
	while i < s.length():
		if s[i] == '"':
			i += 1
			while i < s.length() and s[i] != '"':
				if s[i] == '\\': i += 1
				i += 1
			i += 1
			continue
		if _is_ident_char(s[i]):
			var name_start = i
			while i < s.length() and _is_ident_char(s[i]):
				i += 1
			var call_name = s.substr(name_start, i - name_start)
			var j = i
			while j < s.length() and s[j] == ' ': j += 1
			if j < s.length() and s[j] == '(':
				if not _vs_block_defs.has(call_name) and not call_name.begins_with("_var_ref_"):
					continue
				var depth = 1
				var k = j + 1
				while k < s.length() and depth > 0:
					if s[k] == '"':
						k += 1
						while k < s.length() and s[k] != '"':
							if s[k] == '\\': k += 1
							k += 1
					elif s[k] == '(':
						depth += 1
					elif s[k] == ')':
						depth -= 1
					k += 1
				if depth != 0: continue
				var args_str = s.substr(j + 1, k - j - 2)
				return {
					"name": call_name,
					"args": args_str,
					"start": name_start,
					"end": k
				}
		i += 1
	return null

func _vs_eval_arg(arg_str: String, context: Dictionary) -> Variant:
	arg_str = arg_str.strip_edges()
	if arg_str == "": return ""
	# 值块嵌套时内层结果已存入临时变量，直接取回，避免 _vs_eval_expr 开头 clear() 丢失
	if _vs_expr_temp_vars.has(arg_str):
		return _vs_expr_temp_vars[arg_str]
	# 保存临时变量，防止 _vs_eval_expr 清空后内层值块结果丢失
	var saved_temp_vars = _vs_expr_temp_vars.duplicate()
	var saved_counter = _vs_expr_temp_counter
	var result = _vs_eval_expr(arg_str, context)
	# 恢复外层临时变量（合并：保留内层新产生的，恢复外层被清掉的）
	for k in saved_temp_vars:
		if not _vs_expr_temp_vars.has(k):
			_vs_expr_temp_vars[k] = saved_temp_vars[k]
	_vs_expr_temp_counter = max(_vs_expr_temp_counter, saved_counter)
	if result != null:
		return result
	return arg_str

func _vs_value_to_expr_literal(value) -> String:
	if value == null: return "null"
	if value is bool: return "true" if value else "false"
	if value is int: return str(value)
	if value is float: return str(value)
	if value is String:
		return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
	_vs_expr_temp_counter += 1
	var var_name = "_expr_tmp_%d" % _vs_expr_temp_counter
	_vs_expr_temp_vars[var_name] = value
	return var_name

func _vs_split_top_level_args(s: String) -> Array:
	var args: Array = []
	var depth = 0
	var current = ""
	var i = 0
	while i < s.length():
		var ch = s[i]
		if ch == '"':
			current += ch
			i += 1
			while i < s.length():
				current += s[i]
				if s[i] == '\\' and i + 1 < s.length():
					i += 1
					current += s[i]
				elif s[i] == '"':
					break
				i += 1
		elif ch == '(' or ch == '[' or ch == '{':
			depth += 1
			current += ch
		elif ch == ')' or ch == ']' or ch == '}':
			depth -= 1
			current += ch
		elif ch == ',' and depth == 0:
			args.append(current)
			current = ""
		else:
			current += ch
		i += 1
	if current.strip_edges() != "" or args.size() > 0:
		args.append(current)
	return args

func _vs_dispatch_value(block_name: String, params: Dictionary) -> Variant:
	match block_name:
		"compare": return _value_compare(params)
		"calculate": return _value_calculate(params)
		"json_parse": return _value_json_parse(params)
		"calculate_3d": return _value_calculate_3d(params)
		"calculate_2d": return _value_calculate_2d(params)
		"not_bool": return _value_not_bool(params)
		"val_in_a_and_b": return _value_val_in_a_and_b(params)
		"get_entity_data": return _value_get_entity_data(params)
		"get_entity_num_var": return _value_get_entity_num_var(params)
		"get_entity_string_var": return _value_get_entity_string_var(params)
		"get_entity_bool_var": return _value_get_entity_bool_var(params)
		"get_entity_2d_var": return _value_get_entity_2d_var(params)
		"get_entity_3d_var": return _value_get_entity_3d_var(params)
		"self_entity": return _entity
		"get_entity_by_id": return _value_get_entity_by_id(params)
		"find_entity_by_regex": return _value_find_entity_by_regex(params)
		"find_effect_by_regex": return _value_find_effect_by_regex(params)
		"find_effect_by_name": return _value_find_effect_by_name(params)
		"has_state": return _value_has_state(params)
		"get_state_count": return _value_get_state_count(params)
		"get_bonus_value": return _value_get_bonus_value(params)
		"player_entity": return _value_player_entity(params)
		"is_ourside_entity": return _value_is_ourside_entity(params)
		"get_parent_entity": return _value_get_parent_entity(params)
		"get_root_parent_entity": return _value_get_root_parent_entity(params)
		"get_my_team": return _value_get_my_team(params)
		"get_opponent_team": return _value_get_opponent_team(params)
		"timer_alive": return _value_timer_alive(params)
		"get_info_point": return _value_get_info_point(params)
		"add_pos3d_to_spos2d": return _value_add_pos3d_to_spos2d(params)
		"add_pos3d_to_hpos2d": return _value_add_pos3d_to_hpos2d(params)
		"latest_non_player_entity": return _value_latest_non_player_entity(params)
		"has_valid_target": return _value_has_valid_target(params)
		"distance_2d": return _value_distance_2d(params)
		"deg_to_rad": return _value_deg_to_rad(params)
		"2d_data": return _value_2d_data(params)
		"calculate_immobilize_position_3d": return _value_calculate_immobilize_position_3d(params)
		"now_animation": return _entity.current_animation
		"now_animation_frame_idx": return _entity.get_current_frame()
		"now_dir": return _value_now_dir(params)
		"now_pos2d": return _value_now_pos2d(params)
		"now_pos3d": return _value_now_pos3d(params)
		_:
			var method_name = "_value_" + block_name
			if has_method(method_name):
				return call(method_name, params)
			return null

# ---- 表达式辅助 ----

func _is_ident_char(ch: String) -> bool:
	return ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or _is_cjk_char(ch)

func _is_valid_identifier(s: String) -> bool:
	if s == "": return false
	if not (_is_ident_first_char(s[0])): return false
	for i in range(1, s.length()):
		if not _is_ident_char(s[i]): return false
	return true

func _is_ident_first_char(ch: String) -> bool:
	return ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or _is_cjk_char(ch)

func _is_cjk_char(ch: String) -> bool:
	var c = ch.unicode_at(0)
	return (c >= 0x4E00 and c <= 0x9FFF) or (c >= 0x3400 and c <= 0x4DBF) or (c >= 0xF900 and c <= 0xFAFF)

func _contains_unquoted_char(s: String, target: String) -> bool:
	var i = 0
	while i < s.length():
		if s[i] == '"':
			i += 1
			while i < s.length() and s[i] != '"':
				if s[i] == '\\': i += 1
				i += 1
			i += 1
			continue
		if s[i] == target:
			return true
		i += 1
	return false

# ============================================
# 核心执行引擎
# ============================================

func _vs_execute_chain(start_id, event_block_id):
	var event_block = _vs_blocks_by_id.get(event_block_id, {})
	var current_id = start_id
	var visited: Dictionary = {}

	while current_id >= 0 and not visited.has(current_id):
		if _entity._is_quitting: return
		visited[current_id] = true

		var block = _vs_blocks_by_id.get(current_id)
		if not block: break
		match block.type:
			"ACTION":
				await _vs_execute_action(block, event_block_id)
			"CONDITION":
				await _vs_execute_condition(block, event_block_id)

		current_id = block.get("stack_below_id", -1)

func _vs_execute_inner(inner_ids: Array, event_block_id):
	var executed: Dictionary = {}

	for block_id in inner_ids:
		if executed.has(block_id): continue
		if _entity._is_quitting: return

		var block = _vs_blocks_by_id.get(block_id)
		if not block: continue

		if block.get("is_in_slot", false): continue

		var current_id = block_id
		while current_id >= 0 and not executed.has(current_id):
			if _entity._is_quitting: return
			executed[current_id] = true

			var cur_block = _vs_blocks_by_id.get(current_id)
			if not cur_block: break

			match cur_block.type:
				"ACTION":
					await _vs_execute_action(cur_block, event_block_id)
				"CONDITION":
					await _vs_execute_condition(cur_block, event_block_id)

			current_id = cur_block.get("stack_below_id", -1)

# ============================================
# ACTION 块执行
# ============================================

func _vs_execute_action(block: Dictionary, event_block_id):
	var params = _vs_resolve_params(block, event_block_id)
	await _vs_dispatch_action(block.name, params)

func _vs_dispatch_action(block_name: String, params: Dictionary):
	match block_name:
		"play_animation":
			_action_play_animation(params)
		"wait":
			await _action_wait(params)
		"slide":
			_action_slide(params)
		"start_freemove":
			_action_start_freemove(params)
		"stop_freemove":
			_action_stop_freemove(params)
		"stop_slide":
			_action_stop_slide(params)
		"start_z_slide":
			_action_start_z_slide(params)
		"stop_z_motion":
			_action_stop_z_motion(params)
		"execute_code":
			_action_execute_code(params)
		"set_shadow_visible":
			_action_set_shadow_visible(params)
		"set_wall_collision":
			_action_set_wall_collision(params)
		"add_bonus":
			_action_add_bonus(params)
		"remove_bonus":
			_action_remove_bonus(params)
		"clear_bonus":
			_action_clear_bonus(params)
		"add_state":
			_action_add_state(params)
		"remove_state":
			_action_remove_state(params)
		"clear_state":
			_action_clear_state(params)
		"set_entry_state":
			_action_set_entry_state(params)
		"set_entity_prop":
			_action_set_entity_prop(params)
		"die":
			_action_die(params)
		"die_entity":
			_action_die_entity(params)
		"hit_entity":
			_action_hit_entity(params)
		"create_attack_box":
			_action_create_attack_box(params)
		"replay_attack_box":
			_action_replay_attack_box(params)
		"remove_attack_box":
			_action_remove_attack_box(params)
		"change_entity_hp":
			_action_change_entity_hp(params)
		"magnetism_entity":
			_action_magnetism_entity(params)
		"set_global_magnetism":
			_action_set_global_magnetism(params)
		"set_global_magnetism_by_size":
			_action_set_global_magnetism_by_size(params)
		"hit_stop_entity":
			_action_hit_stop_entity(params)
		"create_entity_by_path":
			_action_create_entity_by_path(params)
		"set_entity_modifiers":
			_action_set_entity_modifiers(params)
		"set_parent_entity":
			_action_set_parent_entity(params)
		"move_pos3d_immd":
			_action_move_pos3d_immd(params)
		"move_entity_pos3d_immd":
			_action_move_entity_pos3d_immd(params)
		"move_toward_2d_point":
			_action_move_toward_2d_point(params)
		"set_cd":
			_action_set_cd(params)
		"set_timer":
			_action_set_timer(params)
		"bind_cd":
			_action_bind_cd(params)
		"add_timer_sub_slot":
			_action_add_timer_sub_slot(params)
		"remove_timer_sub_slot":
			_action_remove_timer_sub_slot(params)
		"clear_timer_sub_slots":
			_action_clear_timer_sub_slots(params)
		"print":
			_action_print(params)
		"send_private_broadcast":
			_action_send_private_broadcast(params)
		"send_global_broadcast":
			_action_send_global_broadcast(params)
		"create_effect":
			_action_create_effect(params)
		"create_effect_copy":
			_action_create_effect_copy(params)
		"remove_effect":
			_action_remove_effect(params)
		"make_zoom_shock":
			_action_make_zoom_shock(params)
		"camera_shake":
			_action_camera_shake(params)
		"camera_shake_directional":
			_action_camera_shake_directional(params)
		"camera_shake_trauma":
			_action_camera_shake_trauma(params)
		"camera_shake_spring":
			_action_camera_shake_spring(params)
		"camera_shake_explosion":
			_action_camera_shake_explosion(params)
		"camera_shake_oscillate":
			_action_camera_shake_oscillate(params)
		"camera_stop_shake":
			_action_camera_stop_shake(params)
		"camera_zoom_shock_instant":
			_action_camera_zoom_shock_instant(params)
		"camera_zoom_shock_hold":
			_action_camera_zoom_shock_hold(params)
		"camera_pulse_zoom":
			_action_camera_pulse_zoom(params)
		"camera_stop_pulse_zoom":
			_action_camera_stop_pulse_zoom(params)
		"camera_move":
			_action_camera_move(params)
		"camera_move_absolute":
			_action_camera_move_absolute(params)
		"camera_stop_move":
			_action_camera_stop_move(params)
		"camera_rotate":
			_action_camera_rotate(params)
		"tween_property":
			await _action_tween_property(params)
		"tween_aura":
			await _action_tween_aura(params)
		"play_voice":
			_action_play_voice(params)
		"play_sound":
			_action_play_sound(params)
		_:
			var method_name = "_action_" + block_name
			if has_method(method_name):
				call(method_name, params)

# ============================================
# CONDITION 块执行
# ============================================

func _vs_execute_condition(block: Dictionary, event_block_id):
	var params = _vs_resolve_params(block, event_block_id)

	match block.name:
		"if_condition":
			var condition = _vs_to_bool(params.get("condition", false))
			if condition:
				await _vs_execute_inner(block.get("inner_block_ids", []), event_block_id)
		"if_else":
			var condition = _vs_to_bool(params.get("condition", false))
			if condition:
				await _vs_execute_inner(block.get("inner_block_ids", []), event_block_id)
			else:
				await _vs_execute_inner(block.get("inner_else_ids", []), event_block_id)
		"repeat_forever":
			while not _entity._is_quitting:
				await _vs_execute_inner(block.get("inner_block_ids", []), event_block_id)
				await _entity.wait_frame()
		"repeat_in_range":
			var n = int(params.get("n", 0))
			for _i in range(n):
				if _entity._is_quitting: return
				await _vs_execute_inner(block.get("inner_block_ids", []), event_block_id)
		"repeat_while":
			while _vs_to_bool(params.get("bool", false)):
				if _entity._is_quitting: return
				await _vs_execute_inner(block.get("inner_block_ids", []), event_block_id)
				await _entity.wait_frame()
		_:
			var method_name = "_condition_" + block.name
			if has_method(method_name):
				await call(method_name, block, params, event_block_id)

# ============================================
# VALUE 块求值
# ============================================

func _vs_evaluate_value(block: Dictionary, event_block_id) -> Variant:
	if block.get("is_var_ref", false):
		var output_name = block.get("output_name", "")
		var source_id = block.get("source_block_id", -1)
		if source_id >= 0 and _vs_event_contexts.has(source_id):
			return _vs_event_contexts[source_id].get(output_name)
		return null

	var params = _vs_resolve_params(block, event_block_id)
	return _vs_dispatch_value(block.name, params)

# ============================================
# 参数解析
# ============================================

func _vs_resolve_params(block: Dictionary, event_block_id) -> Dictionary:
	var result: Dictionary = {}
	var value_slots = block.get("value_slots", {})
	var raw_params = block.get("params", {})
	var exprs = block.get("exprs", {})

	var context: Dictionary = {}
	if event_block_id >= 0 and _vs_event_contexts.has(event_block_id):
		context = _vs_event_contexts[event_block_id]

	for param_name in raw_params:
		if value_slots.has(param_name) and value_slots[param_name] >= 0:
			var slot_id = value_slots[param_name]
			var value_block = _vs_blocks_by_id.get(slot_id)
			if value_block:
				result[param_name] = _vs_evaluate_value(value_block, event_block_id)
				if _vs_debug_print:
					print("[DEBUG] _vs_resolve_params: value_slot for '", param_name, "' = ", result[param_name])
			else:
				result[param_name] = raw_params[param_name]
		elif exprs.has(param_name):
			var expr_str = str(exprs[param_name]).strip_edges()
			if _vs_debug_print:
				print("[DEBUG] _vs_resolve_params: evaluating expr for '", param_name, "': '", expr_str, "'")
				print("[DEBUG] _vs_resolve_params: context=", context)
			if expr_str != "":
				var evaluated = _vs_eval_expr(expr_str, context)
				if _vs_debug_print:
					print("[DEBUG] _vs_resolve_params: '", param_name, "' expr='", expr_str, "' => evaluated=", evaluated, " type=", typeof(evaluated))
				if evaluated != null:
					result[param_name] = evaluated
				else:
					if _vs_debug_print:
						print("[DEBUG] _vs_resolve_params: expr returned null, falling back to raw=", raw_params[param_name])
					result[param_name] = raw_params[param_name]
			else:
				result[param_name] = raw_params[param_name]
		else:
			result[param_name] = raw_params[param_name]

	if _vs_debug_print:
		print("[DEBUG] _vs_resolve_params final result=", result)
	return result

# ============================================
# 类型转换工具
# ============================================

## 收集某块所有参数的"老数据缺省值"：优先 migrate，其次 default。
## 这是运行时侧的缺省来源，必须与编辑器 _migrate_to_v3 的补齐规则保持一致，
## 否则"被编辑器打开过的文件"和"没打开过的文件"会拿到不同的值。
func _vs_block_defaults(block_name: String) -> Dictionary:
	var out: Dictionary = {}
	var def = _vs_block_defs.get(block_name, null)
	if not (def is Dictionary):
		return out
	var params = def.get("params", [])
	if not (params is Array):
		return out
	for pd in params:
		if not (pd is Dictionary):
			continue
		var pname = str(pd.get("name", ""))
		if pname == "":
			continue
		if pd.has("migrate"):
			out[pname] = pd["migrate"]
		elif pd.has("default"):
			out[pname] = pd["default"]
	return out

func _vs_to_bool(value: Variant) -> bool:
	if value == null: return false
	if value is bool: return value
	if value is int or value is float: return value != 0
	if value is String: return value != "" and value != "false"
	return true

func _vs_to_float(value: Variant) -> float:
	if value == null: return 0.0
	if value is float: return value
	if value is int: return float(value)
	if value is String: return value.to_float()
	return 0.0

func _vs_to_int(value: Variant) -> int:
	if value == null: return 0
	if value is int: return value
	if value is float: return int(value)
	if value is String: return value.to_int()
	return 0

func _vs_to_vector2(value: Variant) -> Vector2:
	if value == null: return Vector2.ZERO
	if value is Vector2: return value
	if value is Dictionary:
		return Vector2(value.get("x", 0.0), value.get("y", 0.0))
	return Vector2.ZERO

func _vs_to_vector3(value: Variant) -> Vector3:
	if value == null: return Vector3.ZERO
	if value is Vector3: return value
	if value is Dictionary:
		return Vector3(value.get("x", 0.0), value.get("y", 0.0), value.get("z", 0.0))
	return Vector3.ZERO

## 合集参数取字符串数组。三种来源都认，作者怎么写都能跑：
##   数组 / PackedStringArray —— 编辑器里存下来的形态；
##   字符串                  —— 表达式或手写 JSON 里用逗号分隔的形态，中英文逗号都行；
##   其它                    —— 当成单项。
## 空项与纯空白项丢弃，免得空字符串被当成一个合法动画名去比对。
func _vs_to_string_array(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value == null:
		return out
	if value is PackedStringArray:
		for v in value:
			_vs_append_string_item(out, str(v))
		return out
	if value is Array:
		for v in value:
			_vs_append_string_item(out, str(v))
		return out
	if value is String:
		for part in str(value).replace("，", ",").split(",", false):
			_vs_append_string_item(out, part)
		return out
	_vs_append_string_item(out, str(value))
	return out

func _vs_append_string_item(out: PackedStringArray, raw: String) -> void:
	var s := raw.strip_edges()
	if s != "":
		out.append(s)

const _VS_TRANS_IDS := {
	"linear": 0, "sine": 1, "quint": 2, "quart": 3, "quad": 4,
	"expo": 5, "elastic": 6, "cubic": 7, "circ": 8, "bounce": 9,
	"back": 10, "credit": 11, "spring": 12,
}
const _VS_EASE_IDS := { "in": 0, "out": 1, "in_out": 2, "out_in": 3 }

# 统一曲线解析：返回 {"kind":0, trans, ease} / {"kind":1, expr} / {"kind":2, wf}
# 支持: Godot 数值(0..13 或 "7.1"), 中文旧名(线性/缓入/缓出/缓入缓出/正弦波/三角波/方波),
#       Godot 英文名(linear/sine/... 或 "back.out"), 自定义表达式(变量 t)
func _vs_to_curve(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	if value is int or value is float:
		return {"kind": 0, "trans": clampi(int(value), 0, 13), "ease": 2}
	var s = str(value).strip_edges()
	if s == "": return {"kind": 0, "trans": 7, "ease": 1}
	# 数值或 "trans.ease" 数字组合
	var num_parts = s.split(".")
	if num_parts.size() <= 2 and num_parts[0].is_valid_int():
		var trans = clampi(int(num_parts[0]), 0, 13)
		var ease = 2
		if num_parts.size() == 2 and num_parts[1].is_valid_int():
			ease = clampi(int(num_parts[1]), 0, 3)
		return {"kind": 0, "trans": trans, "ease": ease}
	match s:
		"线性": return {"kind": 0, "trans": 0, "ease": 2}
		"缓入": return {"kind": 0, "trans": 7, "ease": 0}
		"缓出": return {"kind": 0, "trans": 7, "ease": 1}
		"缓入缓出": return {"kind": 0, "trans": 7, "ease": 2}
		"正弦波": return {"kind": 2, "wf": 0}
		"三角波": return {"kind": 2, "wf": 1}
		"方波": return {"kind": 2, "wf": 2}
	# Godot 英文名或 "trans.ease" 组合
	var parts = s.to_lower().split(".")
	if _VS_TRANS_IDS.has(parts[0]):
		var ease = 2
		if parts.size() > 1 and _VS_EASE_IDS.has(parts[1]):
			ease = _VS_EASE_IDS[parts[1]]
		return {"kind": 0, "trans": _VS_TRANS_IDS[parts[0]], "ease": ease}
	# 其余视为自定义表达式（变量 t∈[0,1]，返回插值）
	return {"kind": 1, "expr": s}

func _vs_to_entity(value: Variant) -> EntityBase:
	if value == null: return null
	if value is EntityBase: return value
	if value is String and value != "":
		if _entity.entity_manager:
			return _entity.entity_manager.get_entity(value)
	return null

func _vs_to_color(value: Variant) -> Color:
	if value == null: return Color.WHITE
	if value is Color: return value
	if value is Dictionary:
		return Color(
			value.get("r", 1.0),
			value.get("g", 1.0),
			value.get("b", 1.0),
			value.get("a", 1.0)
		)
	return Color.WHITE

# ============================================
# ACTION 块实现
# ============================================

# ---- 动画 ----

func _action_play_animation(p: Dictionary):
	var anim_name = str(p.get("anim_name", ""))
	# 动画不存在时 play_animation 会整体拒绝（不写 current_animation），
	# 这里也不能置标记，否则标记会活到下一次真实切换，
	# 吞掉本该触发的 when_animation_exit 与 when_any_animation_ended。
	if not _entity.has_animation(anim_name):
		return
	# 标记的含义是「下一次检查会观察到一次动画切换，而这次切换是脚本自己造成的」。
	# 只有动画名真的会变才置位：重播当前正在播放的那个动画（A 播放中又播 A、
	# 现在会从头重播）时动画名不变，没有需要抑制的退出事件；置位反而会让标记
	# 活过一个检查周期去吞掉本该触发的 when_animation_exit 与 when_any_animation_ended。
	if anim_name != _entity.current_animation:
		_vs_script_set_animation = true
	# 起始帧之前那几帧视为没播过：游标靠 _entity.play_seq 对齐，见 _vs_sync_play_start
	# 缺省值取自 block_defs.json，与编辑器补齐的值同源，没被编辑器打开过的文件也不会跑偏
	var dft: Dictionary = _vs_block_defaults("play_animation")
	# 速度传 -1：各动画实现的默认口径不一致，负值表示"不覆盖当前播放速度"，
	# 与加起始帧参数之前调 _entity.play_animation(anim_name) 完全同义。
	_entity.play_animation(anim_name, -1.0, _vs_to_int(p.get("start_frame", dft.get("start_frame", 0))))

# ---- 转向 ----

func _action_turn_to(p: Dictionary):
	var dir_val = p.get("d", "左")
	if dir_val is int or dir_val is float:
		_entity.set_facing(1 if dir_val > 0 else -1)
	else:
		match str(dir_val):
			"左":
				_entity.set_facing(-1)
			"右":
				_entity.set_facing(1)
			_:
				pass

## 按输入转向。滑动期间不改朝向。
##
## 与 _handle_input 里写 facing 的口径一致：那边也是 not is_sliding 才写朝向。
## 滑动方向在触发那一刻就锁进 slide_locked_facing 了，滑到一半再翻面只会让画面翻，
## 方向却不变，看起来就是"滑着滑着突然转身"。
## 想无条件强制转身用 turn_to，那是显式动作，不受这条限制。
func _action_turn_by_input(_p: Dictionary):
	if _entity.is_sliding:
		return
	if _entity.input_left:
		_entity.set_facing(-1)
	elif _entity.input_right:
		_entity.set_facing(1)

# ---- 控制 ----

func _action_wait(p: Dictionary):
	var duration = _vs_to_float(p.get("duration", 1.0))
	await _entity.wait_time(duration)

# ---- 变量设置 ----

func _action_set_var_val(p: Dictionary):
	var var_name = str(p.get("var", ""))
	var val = p.get("val", 0.0)
	if val is String:
		var trimmed = val.strip_edges()
		if trimmed.is_valid_int():
			val = trimmed.to_int()
		elif trimmed.is_valid_float():
			val = trimmed.to_float()
	if var_name != "":
		_vs_variables[var_name] = val


func _action_set_long_var(p: Dictionary):
	var var_name = str(p.get("var", ""))
	var val = str(p.get("val", ""))
	if var_name != "":
		var long_vars = _get_long_vars()
		if long_vars != null:
			long_vars[var_name] = val

func _get_long_vars() -> Dictionary:
	if not _entity: return {}
	match _entity.name:
		"Player1": return MatchConfig.p1_long_vars
		"Player2": return MatchConfig.p2_long_vars
	return {}

func _action_set_entity_var_val(p: Dictionary):
	var var_name = str(p.get("var", ""))
	var val = _vs_to_entity(p.get("val", null))
	if var_name != "":
		_vs_variables[var_name] = val

## 把值写进目标实体的视觉脚本变量，值的类型跟着值本身走。
## 值块与表达式给的是原生类型，直接存；字面量文本按内容推断成整数、浮点或布尔，都不是当字符串存。
## 一块即可覆盖数值、字符串、布尔、2D、3D、实体各类型，不需要按类型分成多个块。
func _action_set_entity_var(p: Dictionary):
	var target = _vs_to_entity(p.get("entity", null))
	var var_name = str(p.get("var", ""))
	if not target or var_name == "":
		return
	if not target.has_method("_vs_set_variable"):
		return
	target._vs_set_variable(var_name, _vs_typed_value(p.get("val", null)))

## 字面量文本自动定型，非字符串原样返回
func _vs_typed_value(val: Variant) -> Variant:
	if not (val is String):
		return val
	var text := str(val).strip_edges()
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float():
		return text.to_float()
	if text == "true":
		return true
	if text == "false":
		return false
	return val

# ---- 原生变量（Godot 属性） ----

## 把值写进目标实体的原生变量，与 set_entity_var 写的图形化脚本变量区分开。
## 不需要作者选类型：先查这个属性在它所属对象上的声明类型，再把值转成该类型。
## 变量名支持用 : 写嵌套路径，例如 aura_node:visible，类型按叶子的声明类型判。
## 属性不存在时报错并跳过，不静默失败。
func _action_set_entity_prop(p: Dictionary):
	var target := _vs_to_entity(p.get("entity", null))
	var prop_name := str(p.get("var", "")).strip_edges()
	if not target:
		push_warning("[VS] set_entity_prop: 目标实体为空")
		return
	if prop_name == "":
		push_warning("[VS] set_entity_prop: 原生变量名为空")
		return
	var raw = p.get("val", null)

	var host: Object = target
	var leaf := prop_name
	if prop_name.contains(":") or prop_name.contains("/"):
		var walk := _vs_walk_prop_host(target, prop_name)
		if walk.is_empty():
			# 中间段不是对象（字典、数组、落在标量上），类型判不出来，交给引擎的 set_indexed
			target.set_indexed(NodePath(prop_name), _vs_typed_value(raw))
			return
		host = walk["host"]
		leaf = walk["leaf"]

	_vs_write_native_prop(host, leaf, raw, prop_name)

## 逐段走 a:b:c 路径，返回叶子属性所在的对象与叶子名。
## 中间段不是对象时返回 {}，不做类型判断。
func _vs_walk_prop_host(target: Object, prop_name: String) -> Dictionary:
	var parts := prop_name.replace("/", ":").split(":")
	if parts.size() < 2:
		return {}
	var host: Object = target
	for i in range(parts.size() - 1):
		var seg := parts[i].strip_edges()
		if seg == "":
			return {}
		var next = host.get(seg)
		if not (next is Object):
			return {}
		host = next
	return {"host": host, "leaf": parts[parts.size() - 1].strip_edges()}

## 按 host 上 leaf 的声明类型把 raw 写进去。label 只用于告警，显示作者填的完整变量名。
func _vs_write_native_prop(host: Object, leaf: String, raw: Variant, label: String) -> void:
	var prop := _vs_find_native_prop(host, leaf)
	if prop.is_empty():
		push_warning("[VS] set_entity_prop: %s 上没有原生变量 '%s'" % [host, label])
		return
	var prop_type := int(prop.get("type", TYPE_NIL))

	# 对象类型的属性只接受真对象，或相对所属对象解析得通的节点路径。
	# 解析不到就跳过，不能写 null：无类型提示的 var 允许被写成 null，等于把成员抹掉。
	if prop_type == TYPE_OBJECT:
		var obj := _vs_resolve_object_ref(host, raw)
		if obj == null:
			push_warning("[VS] set_entity_prop: '%s' 需要一个对象，拿到的值解析不成对象" % label)
			return
		host.set(leaf, obj)
		return

	# 无类型提示的 var 报的是 Variant。若它当前装的是节点而给的是字符串，按节点路径解析，
	# 这样 aura_node 这类没有类型标注的成员也能直接用路径写。
	if prop_type == TYPE_NIL and raw is String and host.get(leaf) is Object:
		var obj := _vs_resolve_object_ref(host, raw)
		if obj == null:
			push_warning("[VS] set_entity_prop: '%s' 是节点成员，字符串解析不成节点" % label)
			return
		host.set(leaf, obj)
		return

	host.set(leaf, _vs_coerce_to_prop_type(raw, prop_type))

## 在 host 上查原生属性定义。group / category 这类占位项跳过，查不到返回 {}。
func _vs_find_native_prop(host: Object, prop_name: String) -> Dictionary:
	for prop in host.get_property_list():
		if str(prop.get("name", "")) != prop_name:
			continue
		var usage := int(prop.get("usage", 0))
		if usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SUBGROUP):
			continue
		return prop
	return {}

## 按属性的声明类型把值转过去。这就是「自动检测变量类型」的落点：
## 值块给的原生类型能用就直接用，字面量文本先按内容定型，最后统一按属性类型收口。
func _vs_coerce_to_prop_type(value: Variant, prop_type: int) -> Variant:
	match prop_type:
		TYPE_INT:
			return _vs_to_int(value)
		TYPE_FLOAT:
			return _vs_to_float(value)
		TYPE_BOOL:
			return _vs_to_bool(value)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2:
			return _vs_to_vector2(value)
		TYPE_VECTOR2I:
			return Vector2i(_vs_to_vector2(value))
		TYPE_VECTOR3:
			return _vs_to_vector3(value)
		TYPE_VECTOR3I:
			return Vector3i(_vs_to_vector3(value))
		TYPE_COLOR:
			return _vs_to_color_literal(value)
		_:
			# Variant、数组、字典等从属性表判不出目标类型的，值本身是什么就是什么
			return _vs_typed_value(value)

## 颜色属性的放宽解析：在 _vs_to_color 之外额外认 "#rrggbb" 这类十六进制文本。
func _vs_to_color_literal(value: Variant) -> Color:
	if value is String:
		var text := str(value).strip_edges()
		if text != "" and text.is_valid_html_color():
			return Color.from_string(text, Color.WHITE)
	return _vs_to_color(value)

## 把值解析成对象引用。已经是对象就直接用，字符串按节点路径相对 host 查。
func _vs_resolve_object_ref(host: Object, value: Variant) -> Object:
	if value is Object:
		return value
	if not (value is String):
		return null
	var path := str(value).strip_edges()
	if path == "":
		return null
	if path == "self":
		return host
	if not (host is Node):
		return null
	var node := host as Node
	if path.begins_with("$"):
		path = path.substr(1)
	if node.has_node(NodePath(path)):
		return node.get_node(NodePath(path))
	return null

# ---- 实体操作 ----

func _action_slide(p: Dictionary):
	var v = _vs_to_vector3(p.get("v", Vector3.ZERO))
	var r = _vs_to_vector3(p.get("r", Vector3.ZERO))
	var g = _vs_to_float(p.get("g", -1.0))
	var m = str(p.get("m", "facing"))

	_entity.slide_locked_facing = _entity.facing_direction

	var slide_dir: Vector2
	match m:
		"facing":
			slide_dir = Vector2(_entity.slide_locked_facing, 0)
		"-facing":
			slide_dir = Vector2(-_entity.slide_locked_facing, 0)
		"input":
			var input_x := 0.0
			var input_y := 0.0
			if _entity.input_left: input_x -= 1.0
			if _entity.input_right: input_x += 1.0
			if _entity.input_up: input_y -= 1.0
			if _entity.input_down: input_y += 1.0
			if input_x != 0 or input_y != 0:
				slide_dir = Vector2(input_x, input_y).normalized()
			else:
				slide_dir = Vector2(_entity.slide_locked_facing, 0)
		"locked":
			slide_dir = Vector2(_entity.slide_locked_facing, 0)
		_:
			slide_dir = Vector2(_entity.slide_locked_facing, 0)

	if v.z != 0:
		_entity.apply_z_impulse(v.z)
	elif _entity.z_velocity_override != 0:
		_entity.z_velocity_override = 0
		_entity.velocity_3d.z = 0  # 同时清掉 velocity_3d.z（之前被 override 路径设成了旧值）
	_entity.set_slide_gravity(g)
	var speed = v.x
	if speed > 0:
		_entity.start_slide(speed, slide_dir, -1)
		# 三轴独立阻力
		_entity.slide_resistance = Vector2(r.x, r.y)
		_entity._slide_z_resistance = r.z
	if v.y != 0:
		_entity.slide_velocity.y = v.y

func _action_hit_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return

	# 让 block_defs.json 成为缺省值的唯一真值源：
	# 数据里缺键时，这里取到的和编辑器加载时补齐的值是同一个数，
	# 不会因为"文件有没有被编辑器打开过"而行为分裂。
	# 取值的优先级与编辑器 _migrate_to_v3 一致：migrate（老数据语义）→ default（新块初值）。
	var dft: Dictionary = _vs_block_defaults("hit_entity")

	var hit_type_str = str(p.get("type", dft.get("type", "push")))
	var v = _vs_to_vector3(p.get("v", dft.get("v", Vector3.ZERO)))
	var hst = _vs_to_float(p.get("hst", dft.get("hst", 0.0)))
	var cotg = _vs_to_bool(p.get("cotg", dft.get("cotg", false)))
	var ish = _vs_to_bool(p.get("ish", dft.get("ish", false)))
	var bs = _vs_to_float(p.get("bs", dft.get("bs", 0.0)))
	var isgd = _vs_to_bool(p.get("isgd", dft.get("isgd", false)))
	var hurt = _vs_to_float(p.get("hurt", dft.get("hurt", 0.0)))
	var kr = _vs_to_float(p.get("kr", dft.get("kr", 10.0)))
	var ar = _vs_to_float(p.get("ar", dft.get("ar", 0.0)))
	var va = _vs_to_vector3(p.get("va", dft.get("va", Vector3.ZERO)))
	# 击退模型：默认（缺键）= 指数阻力（老公式），显式选中"线性阻力"才走新公式
	var kb_model = str(p.get("knockback_model", dft.get("knockback_model", "指数阻力")))
	var kb_linear: bool = (kb_model == "线性阻力")

	var hit_type = _entity.HitStateType.PUSH if hit_type_str == "push" else _entity.HitStateType.LAUNCH
	var kv = Vector2(v.x, v.y)
	if isgd:
		kv.x = kv.x * _entity.facing_direction
		va.x = va.x * _entity.facing_direction

	# 在 hit() 前设置攻击者，让 change_hp 能访问到
	target._last_attacker = _entity
	target.hit(hit_type, kv, hst, v.z, cotg, ish, bs, hurt, kr, ar, Vector2(va.x, va.y), va.z, kb_linear)
	if target.has_method("_on_deal_hit"):
		target._on_deal_hit(_entity)

func _action_create_attack_box(p: Dictionary):
	var box_name = str(p.get("name", ""))
	var pos = _vs_to_vector3(p.get("pos", Vector3.ZERO))
	var size = _vs_to_vector3(p.get("size", Vector3(50, 50, 50)))
	var bind = _vs_to_bool(p.get("bind", true))
	var duration = _vs_to_float(p.get("duration", 0.0))
	# 缺省值取自 block_defs.json，与编辑器补齐的值同源
	var dft: Dictionary = _vs_block_defaults("create_attack_box")
	var anims = _vs_to_string_array(p.get("anims", dft.get("anims", [])))
	_entity.create_attack_box(box_name, pos, size, bind, duration, anims)

func _action_replay_attack_box(p: Dictionary):
	var box_name = str(p.get("name", ""))
	var bind = _vs_to_bool(p.get("bind", true))
	var duration = _vs_to_float(p.get("duration", 0.0))
	var dft: Dictionary = _vs_block_defaults("replay_attack_box")
	var anims = _vs_to_string_array(p.get("anims", dft.get("anims", [])))
	_entity.replay_attack_box(box_name, bind, duration, anims)

func _action_remove_attack_box(p: Dictionary):
	var box_name = str(p.get("name", ""))
	_entity.remove_attack_box(box_name)

func _action_change_entity_hp(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return
	var hp_change = _vs_to_int(p.get("hp", 0))
	var random_value = 1 if randi() % 2 == 0 else -1 # 随机一个方向
	target.change_hp_float(hp_change, 500 * random_value)

func _action_magnetism_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return
	var mpos = _vs_to_vector2(p.get("mpos", Vector2.ZERO))
	var d = _vs_to_float(p.get("d", 0.0))
	var spe = _vs_to_vector2(p.get("spe", Vector2(3000, 3000)))
	var st = _vs_to_int(p.get("st", 2))  # 吸附强度(BodyState)
	target.set_magnetism(mpos, spe, d, st)

func _action_set_global_magnetism(p: Dictionary):
	if not _entity.main or not "add_global_magnetism" in _entity.main:
		push_warning("[set_global_magnetism] main 不可用或无全局吸附功能")
		return
	var mag_name = str(p.get("name", ""))
	if mag_name == "": return
	var center = _vs_to_vector2(p.get("center", Vector2.ZERO))
	var range_x1 = _vs_to_float(p.get("range_x1", 0.0))
	var range_y1 = _vs_to_float(p.get("range_y1", 0.0))
	var range_x2 = _vs_to_float(p.get("range_x2", 0.0))
	var range_y2 = _vs_to_float(p.get("range_y2", 0.0))
	var force = _vs_to_vector2(p.get("force", Vector2(1000, 1000)))
	var duration = _vs_to_float(p.get("duration", 1.0))
	var affected_teams_str = str(p.get("affected_teams", ""))
	var affected_teams: Array = []
	if affected_teams_str != "" and affected_teams_str != "all":
		for part in affected_teams_str.split(",", false):
			var tid = part.strip_edges().to_int()
			if tid > 0:
				affected_teams.append(tid)
	var st = _vs_to_int(p.get("st", -1))  # 吸附强度(BodyState)，-1=不判断
	var mag_inv = _vs_to_bool(p.get("mag_inv", true))  # 吸附无敌(替身无敌除外)，false=不吸
	_entity.main.add_global_magnetism(_entity.name+"_"+mag_name, center, [range_x1, range_y1, range_x2, range_y2], force, duration, affected_teams, st, mag_inv)

func _action_set_global_magnetism_by_size(p: Dictionary):
	if not _entity.main or not "add_global_magnetism" in _entity.main:
		push_warning("[set_global_magnetism_by_size] main 不可用")
		return
	var mag_name = str(p.get("name", ""))
	if mag_name == "": return
	var center = _vs_to_vector2(p.get("center", Vector2.ZERO))
	var range_center = _vs_to_vector2(p.get("range_center", Vector2.ZERO))
	var range_size = _vs_to_vector2(p.get("range_size", Vector2.ZERO))
	var force = _vs_to_vector2(p.get("force", Vector2(1000, 1000)))
	var duration = _vs_to_float(p.get("duration", 1.0))
	var affected_teams_str = str(p.get("affected_teams", ""))
	var range_x1 = range_center.x - range_size.x / 2.0
	var range_y1 = range_center.y - range_size.y / 2.0
	var range_x2 = range_center.x + range_size.x / 2.0
	var range_y2 = range_center.y + range_size.y / 2.0
	var affected_teams: Array = []
	if affected_teams_str != "" and affected_teams_str != "all":
		for part in affected_teams_str.split(",", false):
			var tid = part.strip_edges().to_int()
			if tid > 0:
				affected_teams.append(tid)
	var st = _vs_to_int(p.get("st", -1))  # 吸附强度(BodyState)，-1=不判断
	var mag_inv = _vs_to_bool(p.get("mag_inv", true))  # 吸附无敌(替身无敌除外)，false=不吸
	_entity.main.add_global_magnetism(_entity.name+"_"+mag_name, center, [range_x1, range_y1, range_x2, range_y2], force, duration, affected_teams, st, mag_inv)

func _action_hit_stop_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return
	var d = _vs_to_float(p.get("d", -1))
	# 缺省值取自 block_defs.json，与编辑器补齐的值同源
	var dft: Dictionary = _vs_block_defaults("hit_stop_entity")
	var delay = _vs_to_float(p.get("delay", dft.get("delay", 0.0)))
	target.set_hit_stop(d, true, true, delay)

func _action_create_entity_by_path(p: Dictionary):
	var path = str(p.get("path", ""))
	var entity_name = str(p.get("name", ""))
	if path == "": return
	if not _entity.entity_manager: return

	var cfg = EntityManager.EntityConfig.new(
		_entity.name + "_" + entity_name + str(Engine.get_frames_drawn()),
		path,
		_entity.get_2d_pos(),
		_entity.team_id,
		_entity.facing_direction
	)
	var ee = _entity.entity_manager.spawn_entity_runtime(cfg)
	if ee:
		ee.parent_entity = _entity

func _action_start_freemove(p: Dictionary):
	var v = _vs_to_vector2(p.get("v", Vector2.ZERO))
	_entity.start_free_move(v.x, v.y)

func _action_stop_freemove(_p: Dictionary):
	_entity.stop_free_move()

func _action_stop_slide(_p: Dictionary):
	_entity.stop_slide()

func _action_start_z_slide(p: Dictionary):
	var speed = _vs_to_float(p.get("speed", 0.0))
	var res = _vs_to_float(p.get("r", -1.0))
	_entity.start_z_slide(speed, res)

func _action_stop_z_motion(p: Dictionary):
	var m = str(p.get("m", "all"))
	match m:
		"slide":
			_entity.stop_z_motion(true, false)
		"fall":
			_entity.stop_z_motion(false, true)
		_:
			_entity.stop_z_motion(true, true)

func _action_execute_code(p: Dictionary):
	var code = str(p.get("code", "")).strip_edges()
	if code == "": return
	_exec_code(code)

# 动态编译执行 GDScript 代码，代码内用 entity 引用当前实体，vars 读写图形化脚本变量
func _exec_code(code: String):
	var gd = GDScript.new()
	var src = "extends Object\nvar entity\nvar vars\nfunc run():\n"
	for line in code.split("\n"):
		src += "\t" + line + "\n"
	gd.source_code = src
	var err = gd.reload()
	if err != OK:
		push_error("[VS] 执行代码解析失败 行%d: %s\n%s" % [gd.get_error_line(), gd.get_error_text(), code])
		return
	var inst = gd.new()
	inst.set("entity", _entity)
	var env = _VsVarsEnv.new()
	env.data = _vs_variables
	inst.set("vars", env)
	inst.call("run")

func _action_die(_p: Dictionary):
	_entity.die()

func _action_die_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if target:
		target.die()

func _action_outwall_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target:
		print("[出墙] 未知节点")
		return
	if not target.main:
		print("[出墙] main 节点为空")
		return
	var in_pos = Vector2(target.position_3d.x, target.position_3d.y)
	var wall_pos = target.main.point_walls(in_pos)
	#print("[出墙] 输入=", in_pos, " 输出=", wall_pos, " walls数量=", target.main.walls.size() if "walls" in target.main else "无walls")
	if wall_pos != Vector2.ZERO:
		target.position_3d.x = wall_pos.x
		target.position_3d.y = wall_pos.y
		target.set_position_3d(target.position_3d)

func _action_turn_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target:
		return
	var dir = _vs_to_int(p.get("dir", 1))
	var bs = _vs_to_int(p.get("bs", 1))
	target.set_facing_dir(dir, bs)

func _action_set_cd(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var cd_id = _vs_to_int(p.get("cd_id", 0))
	var cd = _vs_to_float(p.get("cd", 0.0))
	_entity.set_cd(slot_id, cd_id, cd)

func _action_set_timer(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var cd_id = _vs_to_int(p.get("cd_id", 0))
	var cd = _vs_to_float(p.get("cd", 0.0))
	var cd_max = _vs_to_float(p.get("cd_max", 0.0))
	_entity.set_timer(slot_id, cd_id, cd, cd_max)

func _action_bind_cd(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var cd_id = _vs_to_int(p.get("cd_id", 0))
	_entity.bind_cd(slot_id, cd_id)

func _action_add_timer_sub_slot(p: Dictionary):
	var cd_id = _vs_to_int(p.get("cd_id", 0))
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	_entity.add_timer_sub_slot(cd_id, slot_id)

func _action_remove_timer_sub_slot(p: Dictionary):
	var cd_id = _vs_to_int(p.get("cd_id", 0))
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	_entity.remove_timer_sub_slot(cd_id, slot_id)

func _action_clear_timer_sub_slots(p: Dictionary):
	var cd_id = _vs_to_int(p.get("cd_id", 0))
	_entity.clear_timer_sub_slots(cd_id)

func _action_set_slot_aura(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var show = _vs_to_bool(p.get("show", false))
	_entity.set_slot_aura(slot_id, show)

func _action_set_entity_modifiers(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return
	var type = str(p.get("type", ""))
	var pow = _vs_to_int(p.get("pow", 0))
	var d = _vs_to_float(p.get("d", -2))
	var caster = _vs_to_entity(p.get("caster", null))
	if not caster:
		caster = _entity
	# 两个开关的缺省与 block_defs.json 同源，没被编辑器打开过的老数据行为一致
	var dft = _vs_block_defaults("set_entity_modifiers")
	var clearable = _vs_to_bool(p.get("clearable", dft.get("clearable", false)))
	var hit_stop_inv = _vs_to_bool(p.get("hit_stop_inv", dft.get("hit_stop_inv", true)))
	target.set_modifiers(type, pow, d, "", "", "", caster, clearable, hit_stop_inv)

func _action_set_parent_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return
	var new_parent = _vs_to_entity(p.get("parent", null))
	target.parent_entity = new_parent

func _action_move_pos3d_immd(p: Dictionary):
	var pos = _vs_to_vector3(p.get("pos", Vector3.ZERO))
	_entity.teleport_to_position(pos)

func _action_move_entity_pos3d_immd(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return
	var pos = _vs_to_vector3(p.get("pos", Vector3.ZERO))
	target.teleport_to_position(pos)

func _action_move_toward_2d_point(p: Dictionary):
	var point = _vs_to_vector2(p.get("point", Vector2.ZERO))
	var speed = _vs_to_float(p.get("speed", 500.0))
	var cur_2d = Vector2(_entity.position_3d.x, _entity.position_3d.y)
	var to_point = point - cur_2d
	if to_point.length() < 10.0:
		return
	var step = to_point.normalized() * speed * get_physics_process_delta_time()
	_entity.position_3d.x += step.x
	_entity.position_3d.y += step.y
	_entity.set_position_3d(_entity.position_3d)

func _action_set_entity_immobilize(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return
	var pos = _vs_to_vector3(p.get("pos", Vector3.ZERO))
	var time = _vs_to_float(p.get("time", -1))
	var rpos = _vs_to_vector3(p.get("rpos", Vector3.ZERO))
	var ani = str(p.get("ani", "immobilize"))
	var v = _vs_to_vector3(p.get("v", Vector3.ZERO))
	var kt = _vs_to_int(p.get("kt", 0))
	var g = _vs_to_int(p.get("g", 700))
	var bs = _vs_to_int(p.get("bs", 2))
	var var_name = str(p.get("var", ""))
	var cs = _vs_to_bool(p.get("cs", false))
	var vr = _vs_to_float(p.get("vr", 0.0))
	var rani = str(p.get("rani", ""))
	# 抓取模式。fixed = 固定位置：pos / rpos / 速度都用调用瞬间算好的世界坐标，抓取期间不再变。
	# follow = 跟随位置：把它们换算成相对自己实体的偏移，抓取期间每帧按施术者实时位置与朝向重算。
	var follow: bool = str(p.get("mode", "fixed")) == "follow"

	target.set_immobilize(pos, time, rpos, ani, Vector2(v.x, v.y), kt, v.z, g, bs, cs, vr,
		rani, _entity if follow else null)
	if target._immobilize_active:
		_vs_variables[var_name] = target

func _action_stop_entity_immobilize(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return
	target.stop_immobilize()

# ---- 特效 ----

func _action_create_effect(p: Dictionary):
	var eff_name = str(p.get("name", ""))
	var pos = _vs_to_vector3(p.get("pos", Vector3.ZERO))
	var dir = _vs_to_bool(p.get("dir", true))
	var scale_vec = _vs_to_vector2(p.get("scale", Vector2.ONE))
	var rot_deg = _vs_to_float(p.get("rotation", 0.0))
	var data_str = str(p.get("data", ""))
	var data = {}
	if data_str != "":
		var parsed = JSON.parse_string(data_str)
		if parsed is Dictionary:
			data = parsed
	if _entity.effects_container:
		var eff = _entity.effects_container.spawn_effect(eff_name, pos, not dir, data)
		if eff:
			# 逻辑特效名与生成者：前者供「选择特效」按名字找，后者供它判断归属
			eff.set_meta("effect_name", eff_name)
			eff.set_meta("_spawn_entity", _entity)
			if scale_vec != Vector2.ONE:
				eff.scale = scale_vec
			if rot_deg != 0.0:
				eff.rotation = deg_to_rad(rot_deg)

func _action_create_effect_copy(p: Dictionary):
	var eff_name = str(p.get("name", ""))
	var target = _vs_to_entity(p.get("target", null))
	var pos = _vs_to_vector3(p.get("pos", Vector3.ZERO))
	var dir = _vs_to_bool(p.get("dir", true))
	var scale_vec = _vs_to_vector2(p.get("scale", Vector2.ONE))
	var rot_deg = _vs_to_float(p.get("rotation", 0.0))
	var auto_flip = _vs_to_bool(p.get("auto_flip_by_facing", false))
	var data_str = str(p.get("data", ""))
	var data = {}
	if data_str != "":
		var parsed = JSON.parse_string(data_str)
		if parsed is Dictionary:
			data = parsed
	if _entity.effects_container and target:
		var eff = _entity.effects_container.spawn_follow_effect(eff_name, target, pos, true, not dir, data)
		if eff:
			# 逻辑特效名与生成者：前者供「选择特效」按名字找，后者供它判断归属
			eff.set_meta("effect_name", eff_name)
			eff.set_meta("_spawn_entity", _entity)
			if scale_vec != Vector2.ONE:
				eff.scale = scale_vec
			if rot_deg != 0.0:
				eff.rotation = deg_to_rad(rot_deg)
			if auto_flip and _entity.facing_direction < 0:
				eff.scale.x = -abs(eff.scale.x)

## 取特效实例：接受特效节点本身，也接受能解析到它的节点路径。
## 值块「选择特效」返回的就是节点，所以常规路径是第一种；第二种留给手写路径的兜底。
func _vs_to_effect_node(value: Variant) -> Node2D:
	if value == null:
		return null
	if value is Node2D:
		return value
	if value is Node or value is NodePath or value is String:
		var path_text := str(value).strip_edges()
		if path_text == "":
			return null
		var ec = _entity.effects_container
		if not ec:
			return null
		return ec.get_node_or_null(NodePath(path_text)) as Node2D
	return null

## 移除特效。输入是特效节点，不是特效名：
## 名字只用于「选择特效」那一步把节点找出来，找到之后这里只认节点，
## 于是同一个动作既能删本实体生成的，也能删别的实体交给它的那一份，语义只有一个「删掉这个实例」。
##
## 归属判断在选择那一步做，见 _value_find_effect_by_name 的 own 参数。
## 这里只做防呆：拿到的必须是本场特效容器下的实例，避免误传实体或别的节点把场面搞乱。
func _action_remove_effect(p: Dictionary):
	var eff := _vs_to_effect_node(p.get("target", null))
	if eff == null:
		if _vs_debug_print:
			print("[特效] 移除特效：没拿到特效节点，跳过")
		return
	if not is_instance_valid(eff) or eff.is_queued_for_deletion():
		return
	var ec = _entity.effects_container
	if ec == null or not ec.is_ancestor_of(eff):
		push_warning("[特效] 移除特效：%s 不是本场特效容器下的实例，跳过" % str(eff))
		return
	var eff_desc := str(eff.name)
	var owner_desc := "无"
	if eff.has_meta("_spawn_entity"):
		var owner = eff.get_meta("_spawn_entity")
		owner_desc = str(owner.name) if is_instance_valid(owner) else "已失效"
	if ec.has_method("finish_effect"):
		ec.finish_effect(eff)  # 池化的归还池子，非池化的 queue_free
	else:
		eff.queue_free()
	if _vs_debug_print:
		print("[特效] 移除 %s，生成者 %s" % [eff_desc, owner_desc])

## 特效选择器：按逻辑特效名找特效实例，返回节点。
##
## 归属判断在这里，不在移除那一步：特效容器是全场的，同名特效可能同时存在对手或父实体的一份，
## own 为真时只认 _spawn_entity 是自己的那些。元数据由生成侧写入：
##   帧绑定特效 —— EntityBase._process_effect_bindings
##   脚本生成特效 —— 本文件的 create_effect、create_effect_copy、spawn_afterimage、spawn_cancel_white
## 没有写生成者的实例按自己的处理，免得早期数据选不中。
func _value_find_effect_by_name(p: Dictionary) -> Node2D:
	var eff_name = str(p.get("name", "")).strip_edges()
	if eff_name == "":
		return null
	var index = _vs_to_int(p.get("index", 0))
	var own = _vs_to_bool(p.get("own", true))
	var ec = _entity.effects_container
	if not ec:
		return null
	var matched := 0
	for eff in ec.get_children():
		if not is_instance_valid(eff) or not (eff is Node2D) or eff.is_queued_for_deletion():
			continue
		var logical := str(eff.get_meta("effect_name", "")) if eff.has_meta("effect_name") else ""
		var pool_name := str(eff.get_meta("pool_name", "")) if eff.has_meta("pool_name") else ""
		if logical != eff_name and pool_name != eff_name:
			continue
		if own and eff.has_meta("_spawn_entity"):
			var owner = eff.get_meta("_spawn_entity")
			if is_instance_valid(owner) and owner != _entity:
				continue
		if matched == index:
			return eff
		matched += 1
	return null

func _action_spawn_afterimage(p: Dictionary):
	var fade = _vs_to_float(p.get("fade", 0.5))
	var hold = _vs_to_float(p.get("hold", 0.0))
	var color = _vs_to_color(p.get("color", Color.WHITE))
	if _entity.effects_container:
		var eff = _entity.effects_container.spawn_effect("Afterimage", _entity.position_3d, false, {"target": _entity})
		if eff:
			eff.set_meta("effect_name", "Afterimage")
			eff.set_meta("_spawn_entity", _entity)
			eff.fade_time = fade
			eff.hold_time = hold
			eff.custom_modulate = color

func _action_spawn_cancel_white(p: Dictionary):
	if _entity.effects_container:
		var eff = _entity.effects_container.spawn_effect("CancelWhite", _entity.position_3d, false, {"target": _entity})
		if eff:
			eff.set_meta("effect_name", "CancelWhite")
			eff.set_meta("_spawn_entity", _entity)

func _action_print(p: Dictionary):
	var text = str(p.get("text", ""))
	print(text)

func _action_show_info_text(p: Dictionary):
	var text = str(p.get("text", ""))
	var color = _vs_to_color(p.get("color", Color.WHITE))
	_entity.show_info_text(text, color)
	print("提示: ", text)
	if _vs_debug_print:
		print("[DEBUG] _action_show_info_text: raw params=", p, " text='", text, "' color=", color)

# ---- 广播 ----

func _action_send_private_broadcast(p: Dictionary):
	var msg = str(p.get("msg", ""))
	if msg == "": return
	var data_str = str(p.get("data", ""))
	var data: Dictionary = {}
	if data_str != "":
		var parsed = JSON.parse_string(data_str)
		if parsed is Dictionary:
			data = parsed
		else:
			data = {"value": data_str}
	_entity.send_private_broadcast(msg, data)

func _action_send_global_broadcast(p: Dictionary):
	var msg = str(p.get("msg", ""))
	if msg == "": return
	var data_str = str(p.get("data", ""))
	var data: Dictionary = {}
	if data_str != "":
		var parsed = JSON.parse_string(data_str)
		if parsed is Dictionary:
			data = parsed
		else:
			data = {"value": data_str}
	_entity.send_global_broadcast(msg, data)

func _action_set_aura_visible(p: Dictionary):
	var visible = _vs_to_bool(p.get("visible", false))
	_entity.set_aura_visible(visible)

func _action_set_shadow_visible(p: Dictionary):
	var visible = _vs_to_bool(p.get("visible", true))
	if _entity.shadow_node:
		_entity.shadow_node.visible = visible

func _action_set_wall_collision(p: Dictionary):
	var enabled = _vs_to_bool(p.get("enabled", true))
	_entity.enable_wall_collision = enabled

func _action_add_bonus(p: Dictionary):
	var e_type = str(p.get("type", "atk"))
	var value = _vs_to_float(p.get("value", 0.0))
	var duration = _vs_to_float(p.get("duration", -2.0))
	var mode = str(p.get("mode", "multiply"))
	var group = str(p.get("group", ""))
	_entity.add_bonus(e_type, value, duration, mode, _entity, group)

func _action_remove_bonus(p: Dictionary):
	_entity.remove_bonus_layer(str(p.get("type", "atk")), str(p.get("group", "")))

func _action_clear_bonus(p: Dictionary):
	var e_type = str(p.get("type", ""))
	if e_type == "all": e_type = ""
	_entity.clear_bonus(e_type)

func _action_add_state(p: Dictionary):
	var state = str(p.get("state", ""))
	var duration = _vs_to_float(p.get("duration", -2.0))
	_entity.add_state(state, duration, _entity)

func _action_remove_state(p: Dictionary):
	_entity.remove_state_by_name(str(p.get("state", "")), 1)

func _action_clear_state(p: Dictionary):
	_entity.clear_state(str(p.get("state", "")))

## 修改入场状态。none 取消入场并落到地面，default 重新走默认从天而降，
## custom 走自定义入场（anim 为空时沿用 EntityData.custom_entry）。
func _action_set_entry_state(p: Dictionary):
	var mode = str(p.get("mode", "none"))
	var anim = str(p.get("anim", ""))
	var offset = _vs_to_vector3(p.get("offset", Vector3.ZERO))
	match mode:
		"none":
			_entity.set_entry_state(EntityBase.EntryAction.NONE)
		"default":
			_entity.set_entry_state(EntityBase.EntryAction.DEFAULT)
		"custom":
			_entity.set_entry_state(EntityBase.EntryAction.CUSTOM, anim, offset)
		_:
			push_warning("[VS] set_entry_state: 未知入场方式 '%s'" % mode)

func _value_has_state(p: Dictionary) -> bool:
	return _entity.has_state(str(p.get("state", "")))

func _value_get_state_count(p: Dictionary) -> int:
	return _entity.get_state_count(str(p.get("state", "")))

func _value_get_bonus_value(p: Dictionary) -> float:
	return _entity.get_bonus_value(str(p.get("type", "atk")))

func _action_set_custom_invincible(p: Dictionary):
	var b = _vs_to_bool(p.get("b", false))
	_entity.custom_invincible = b

func _action_set_ultimate_active(p: Dictionary):
	var active = _vs_to_bool(p.get("active", false))
	_entity.ultimate_active = active

func _action_set_ultimate_img_scene(p: Dictionary):
	var path = str(p.get("path", ""))
	if path != "":
		_entity.ultimate_img_scene = load(path)

func _action_set_icon(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var path = str(p.get("path", ""))
	_entity.skill_slot[slot_id].set_texture(load(path))

func _action_set_energy_bar_visible(p: Dictionary):
	var visible = _vs_to_bool(p.get("visible", false))
	_entity.set_energy_bar_visible(visible)

func _action_set_energy_bar_value(p: Dictionary):
	var v = _vs_to_float(p.get("v", false))
	_entity.set_energy_bar_value(v)

func _action_set_energy_bar_value_max(p: Dictionary):
	var v = _vs_to_float(p.get("v", false))
	_entity.set_energy_bar_value_max(v)

func _action_set_energy_bar_color(p: Dictionary):
	var c = _vs_to_color(p.get("c", Color.WHITE))
	_entity.set_energy_bar_modulate(c)

func _action_set_energy_bar_split(p: Dictionary):
	var c = _vs_to_int(p.get("c", 1))
	_entity.set_energy_bar_split(c)

func _action_set_ultimate_point(p: Dictionary):
	var v = _vs_to_int(p.get("v", 4))
	_entity.ultimate_point = v

func _action_set_ultimate_point_max(p: Dictionary):
	var v = _vs_to_int(p.get("v", 4))
	_entity.ultimate_point_max = v

func _action_change_ultimate_point(p: Dictionary):
	var d = _vs_to_int(p.get("d", 0))
	_entity.change_ultimate_point(d)

func _action_change_ultimate_point_for(p: Dictionary):
	var target = p.get("entity", null)
	var d = _vs_to_int(p.get("d", 0))
	if target and target is EntityBase:
		target.change_ultimate_point(d)

func _action_change_ultimate_point_flag(p: Dictionary):
	var d = _vs_to_int(p.get("d", 0))
	var flag = str(p.get("flag", ""))
	if flag != "" and not _vs_ultimate_flags.get(flag, false):
		_entity.change_ultimate_point(d)
		_vs_ultimate_flags[flag] = true

func _action_clear_ultimate_flag(p: Dictionary):
	var flag = str(p.get("flag", ""))
	if flag != "":
		_vs_ultimate_flags[flag] = false

func _action_set_can_cast_aux(p: Dictionary):
	var b = _vs_to_bool(p.get("b", false))
	_entity.can_cast_aux = b

func _action_set_charging_progress(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var value = _vs_to_float(p.get("value", 0.0))
	_entity.skill_slot[slot_id].charging_progress.rotation = remap(value, 0.0, 1.0, 0.0, PI)

func _action_set_charging_progress_visible(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var visible = _vs_to_bool(p.get("visible", false))
	_entity.skill_slot[slot_id].charging_progress.visible = visible

func _action_set_is_charging(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var b = _vs_to_bool(p.get("b", false))
	_entity.skill_slot[slot_id].is_charging = b

func _action_set_charging(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var n = _vs_to_int(p.get("n", 0))
	_entity.skill_slot[slot_id].dot = n

func _action_set_charging_max(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var n = _vs_to_int(p.get("n", 0))
	_entity.skill_slot[slot_id].dot_max = n


func _action_set_skill_slot_disabled(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var disabled = _vs_to_bool(p.get("disabled", false))
	_entity.skill_slot[slot_id].disabled = disabled

func _action_set_slot_visible(p: Dictionary):
	var slot_id = _vs_to_int(p.get("slot_id", 0))
	var visible = _vs_to_bool(p.get("visible", true))
	_entity.skill_slot[slot_id].visible = visible

# ---- 摄像机 ----

func _action_make_zoom_shock(p: Dictionary):
	var intensity = _vs_to_float(p.get("i", 0.0))
	var duration = _vs_to_float(p.get("d", 0.0))
	if _entity.camera:
		_entity.camera.zoom_shock(intensity, duration)

func _action_camera_shake(p: Dictionary):
	var intensity = _vs_to_float(p.get("intensity", 10.0))
	var duration = _vs_to_float(p.get("duration", 0.3))
	var frequency = _vs_to_float(p.get("frequency", 20.0))
	if _entity.camera:
		_entity.camera.shake_random(intensity, duration, frequency)

func _action_camera_shake_directional(p: Dictionary):
	var intensity = _vs_to_float(p.get("intensity", 10.0))
	var duration = _vs_to_float(p.get("duration", 0.3))
	var dir = _vs_to_vector2(p.get("dir", Vector2(1, 0)))
	if _entity.camera:
		_entity.camera.shake_directional(intensity, duration, dir)

func _action_camera_shake_trauma(p: Dictionary):
	var trauma = _vs_to_float(p.get("trauma", 0.5))
	var max_trauma = _vs_to_float(p.get("max_trauma", 1.0))
	if _entity.camera:
		_entity.camera.shake_trauma(trauma, max_trauma)

func _action_camera_shake_spring(p: Dictionary):
	var impulse = _vs_to_vector2(p.get("impulse", Vector2(100, 0)))
	var stiffness = _vs_to_float(p.get("stiffness", 300.0))
	var damping = _vs_to_float(p.get("damping", 0.3))
	if _entity.camera:
		_entity.camera.shake_spring(impulse, stiffness, damping)

func _action_camera_shake_explosion(p: Dictionary):
	var intensity = _vs_to_float(p.get("intensity", 30.0))
	var duration = _vs_to_float(p.get("duration", 0.3))
	if _entity.camera:
		_entity.camera.shake_explosion(intensity, duration)

func _action_camera_shake_oscillate(p: Dictionary):
	var amplitude = _vs_to_float(p.get("amplitude", 10.0))
	var frequency = _vs_to_float(p.get("frequency", 2.0))
	var duration = _vs_to_float(p.get("duration", -1.0))
	if _entity.camera:
		_entity.camera.shake_oscillate(amplitude, frequency, duration)

func _action_camera_stop_shake(_p: Dictionary):
	if _entity.camera:
		_entity.camera.stop_shake()

func _action_camera_zoom_shock_instant(p: Dictionary):
	var intensity = _vs_to_float(p.get("intensity", 0.3))
	var duration = _vs_to_float(p.get("duration", 0.3))
	if _entity.camera:
		_entity.camera.zoom_shock_instant(intensity, duration)

func _action_camera_zoom_shock_hold(p: Dictionary):
	var intensity = _vs_to_float(p.get("intensity", 0.3))
	var hold_time = _vs_to_float(p.get("hold_time", 0.2))
	if _entity.camera:
		_entity.camera.zoom_shock_hold(intensity, hold_time)

func _action_camera_pulse_zoom(p: Dictionary):
	var amplitude = _vs_to_float(p.get("amplitude", 0.2))
	var frequency = _vs_to_float(p.get("frequency", 2.0))
	var duration = _vs_to_float(p.get("duration", 0.0))
	var curve = _vs_to_curve(p.get("waveform", "正弦波"))
	if _entity.camera:
		_entity.camera.start_pulse_zoom(amplitude, frequency, curve, duration)

func _action_camera_stop_pulse_zoom(_p: Dictionary):
	if _entity.camera:
		_entity.camera.stop_pulse_zoom()

func _action_camera_move(p: Dictionary):
	var offset = _vs_to_vector2(p.get("offset", Vector2.ZERO))
	var zoom_val = _vs_to_float(p.get("zoom", 1.0))
	var duration = _vs_to_float(p.get("duration", 0.5))
	var enter_duration = _vs_to_float(p.get("enter_duration", 0.2))
	var exit_duration = _vs_to_float(p.get("exit_duration", 0.3))
	var enter_ease = _vs_to_curve(p.get("enter_ease", "缓出"))
	var exit_ease = _vs_to_curve(p.get("exit_ease", "缓入"))
	if _entity.camera:
		_entity.camera.camera_move(offset, zoom_val, duration, enter_duration, exit_duration, enter_ease, exit_ease)

func _action_camera_move_absolute(p: Dictionary):
	var pos = _vs_to_vector2(p.get("pos", Vector2.ZERO))
	var zoom_val = _vs_to_float(p.get("zoom", 1.0))
	var duration = _vs_to_float(p.get("duration", 0.5))
	var enter_duration = _vs_to_float(p.get("enter_duration", 0.2))
	var exit_duration = _vs_to_float(p.get("exit_duration", 0.3))
	var enter_ease = _vs_to_curve(p.get("enter_ease", "缓出"))
	var exit_ease = _vs_to_curve(p.get("exit_ease", "缓入"))
	var use_limit = _vs_to_bool(p.get("use_limit", false))
	if _entity.camera:
		_entity.camera.camera_move_to_absolute(pos, zoom_val, duration, enter_duration, exit_duration, enter_ease, exit_ease, use_limit)

func _action_camera_stop_move(p: Dictionary):
	var immediate = _vs_to_bool(p.get("immediate", false))
	if _entity.camera:
		_entity.camera.stop_camera_move(immediate)

func _action_camera_rotate(p: Dictionary):
	var angle = _vs_to_float(p.get("angle", 0.0))
	var enter_duration = _vs_to_float(p.get("enter_duration", 0.2))
	var hold_duration = _vs_to_float(p.get("hold_duration", 0.5))
	var exit_duration = _vs_to_float(p.get("exit_duration", 0.3))
	var enter_ease = _vs_to_curve(p.get("enter_ease", "缓出"))
	var exit_ease = _vs_to_curve(p.get("exit_ease", "缓入"))
	if _entity.camera:
		_entity.camera.camera_rotate(angle, hold_duration, enter_duration, exit_duration, enter_ease, exit_ease)

# ---- 补间动画 ----

## 补间 scale 的写入端。
## Visuals.scale.x 同时承载朝向符号：EntityBase 每物理帧都会按朝向写一次，
## 所以这里只改缩放大小，符号跟着实体当前朝向走，避免与朝向应用互相覆盖。
func _tween_apply_visual_scale(value: float, host: Node2D, face_source):
	var face := 1.0
	if face_source != null and face_source.facing_direction < 0:
		face = -1.0
	host.scale = Vector2(value * face, value)

func _action_tween_property(p: Dictionary):
	await _tween_entity_property(_vs_to_entity(p.get("target", null)), p, false)

## 光圈补间：参数与缓动跟 tween_property 完全一致，只是宿主换成 Aura 节点。
## Aura 挂在 Shadow 下，与 Visuals 是兄弟关系，所以 tween_property 那种
## 「视觉补间一律打 Visuals」的规则覆盖不到它，必须单独给一个入口。
func _action_tween_aura(p: Dictionary):
	await _tween_entity_property(_vs_to_entity(p.get("target", null)), p, true)

## tween_property 与 tween_aura 的共用实现。use_aura 决定宿主取 Aura 还是 Visuals/实体根。
func _tween_entity_property(target, p: Dictionary, use_aura: bool):
	if not target:
		if _vs_debug_print:
			push_warning("[VS-tween] 目标实体为空")
		return
	var prop = str(p.get("prop", "scale"))
	var to_val = _vs_to_float(p.get("to", 1.0))
	var dur = _vs_to_float(p.get("dur", 0.5))
	var delay = _vs_to_float(p.get("delay", 0.0))
	var curve = _vs_to_curve(p.get("ease", "缓出"))
	var trans_type = Tween.TRANS_LINEAR
	var ease_type = Tween.EASE_IN_OUT
	if curve.get("kind", 0) == 0:
		trans_type = int(curve.get("trans", Tween.TRANS_LINEAR))
		ease_type = int(curve.get("ease", Tween.EASE_IN_OUT))
	elif _vs_debug_print:
		push_warning("[VS-tween] 自定义表达式缓动不支持 Tween，已用线性替代")
	var host: Node2D = target
	var host_is_visuals := false
	if use_aura:
		host = target.aura_node
		if not host:
			push_warning("[VS-tween] %s 没有 Aura 节点，本次光圈补间被忽略" % target.name)
			return
		if prop.begins_with("position_3d"):
			# position_3d 是逻辑坐标，光圈是纯视觉节点，没有这一说
			push_warning("[VS-tween] 光圈不支持 position_3d 补间，本次被忽略")
			return
	else:
		# 视觉补间一律打在 Visuals 节点上。Visuals 与 Shadow 是兄弟节点，Aura 挂在 Shadow 下，
		# 补间打在实体根上会把 Aura 与 Shadow 一起缩放、淡出、旋转。
		# position_3d 是逻辑坐标，碰撞、深度与受击框都读它，补间必须留在实体根上。
		if not prop.begins_with("position_3d") and target.visuals_node:
			host = target.visuals_node
			host_is_visuals = true
	match prop:
		"scale":
			# 光圈不随朝向镜像，face_src 只给 Visuals 那条路
			var face_src = target if host_is_visuals else null
			var tween = target.create_tween()
			tween.tween_method(_tween_apply_visual_scale.bind(host, face_src), host.scale.y, to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"modulate":
			var tween = target.create_tween()
			tween.tween_property(host, "modulate", Color(to_val, to_val, to_val, 1.0), dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"modulate:a":
			var src = host.modulate
			var dst = Color(src.r, src.g, src.b, to_val)
			var tween = target.create_tween()
			tween.tween_property(host, "modulate", dst, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"rotation":
			var tween = target.create_tween()
			tween.tween_property(host, "rotation", deg_to_rad(to_val), dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"position:x":
			var tween = target.create_tween()
			tween.tween_property(host, "position:x", to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"position:y":
			var tween = target.create_tween()
			tween.tween_property(host, "position:y", to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"position_3d:x":
			var tween = target.create_tween()
			tween.tween_property(target, "position_3d:x", to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"position_3d:y":
			var tween = target.create_tween()
			tween.tween_property(target, "position_3d:y", to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"position_3d:z":
			var tween = target.create_tween()
			tween.tween_property(target, "position_3d:z", to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		_:
			# 属性下拉之外的自定义属性维持原行为：打在实体根上
			var tween = target.create_tween()
			tween.tween_property(target, prop, to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished

func _action_play_voice(p: Dictionary):
	var path = str(p.get("path", ""))
	if path == "": return
	var isz = _vs_to_bool(p.get("isz", true))
	var tag = str(p.get("tag", ""))
	var volume = _vs_to_float(p.get("volume", 1.0))
	var stream = load(path)
	if stream:
		AudioManager.play_voice(stream, isz, tag, volume)

func _action_play_sound(p: Dictionary):
	var path = str(p.get("path", ""))
	if path == "": return
	var isz = _vs_to_bool(p.get("isz", true))
	var tag = str(p.get("tag", ""))
	var volume = _vs_to_float(p.get("volume", 1.0))
	var stream = load(path)
	if stream:
		AudioManager.play_sfx(stream, isz, tag, volume)
	print("[音效] ", path)

func _action_stop_sfx_by_tag(p: Dictionary):
	var tag = str(p.get("tag", ""))
	if tag == "": return
	AudioManager.stop_sfx_by_tag(tag)

func _action_stop_voice_by_tag(p: Dictionary):
	var tag = str(p.get("tag", ""))
	if tag == "": return
	AudioManager.stop_voice_by_tag(tag)

func _action_stop_all_sfx(p: Dictionary):
	AudioManager.stop_all_sfx()

func _action_stop_all_voices(p: Dictionary):
	AudioManager.stop_all_voices()

func _action_freeze_frame(p: Dictionary):
	var duration = _vs_to_float(p.get("duration", 1.0))
	GlobalTimeManager.start_freeze_frame(duration)

func _action_time_stop(p: Dictionary):
	var duration = _vs_to_float(p.get("duration", 1.0))
	GlobalTimeManager.start_time_stop(duration)

func _action_set_time_scale_animated(p: Dictionary):
	var target = _vs_to_float(p.get("target", 0.5))
	var tin = _vs_to_float(p.get("transition_in", 0.5))
	var hold = _vs_to_float(p.get("hold", 0.0))
	var tout = _vs_to_float(p.get("transition_out", 0.0))
	GlobalTimeManager.set_time_scale_animated(target, tin, hold, tout)

# ============================================
# VALUE 块实现
# ============================================

func _value_compare(p: Dictionary) -> bool:
	var left = p.get("left", "")
	var right = p.get("right", "")
	var op = str(p.get("op", "="))
	# 解析变量名→值（如果比较块参数是未加引号的变量名）
	if left is String and _vs_variables.has(left):
		left = _vs_variables[left]
	if right is String and _vs_variables.has(right):
		right = _vs_variables[right]
	var left_num = _vs_try_to_float(left)
	var right_num = _vs_try_to_float(right)
	var is_numeric = left_num != null and right_num != null

	if is_numeric:
		match op:
			"<": return left_num < right_num
			"=", "==": return left_num == right_num
			">": return left_num > right_num
			"或": return _vs_to_bool(left) or _vs_to_bool(right)
			"且": return _vs_to_bool(left) and _vs_to_bool(right)
	else:
		var left_str = str(left)
		var right_str = str(right)
		match op:
			"=", "==": return left_str == right_str
			"<": return left_str < right_str
			">": return left_str > right_str
			"或": return _vs_to_bool(left) or _vs_to_bool(right)
			"且": return _vs_to_bool(left) and _vs_to_bool(right)
	return false

func _value_calculate(p: Dictionary) -> Variant:
	var left = p.get("left", 0.0)
	var right = p.get("right", 0.0)
	var op = str(p.get("op", "+"))

	if op == "+" and (left is String or right is String):
		return str(left) + str(right)

	var lf = _vs_to_float(left)
	var rf = _vs_to_float(right)
	match op:
		"+": return lf + rf
		"-": return lf - rf
		"*": return lf * rf
		"/": return lf / rf if rf != 0 else 0.0
	return 0.0

func _value_json_parse(p: Dictionary) -> Variant:
	var json_str = str(p.get("str", "")).strip_edges()
	if json_str == "": return {}
	var result = JSON.parse_string(json_str)
	if result == null:
		push_warning("[VS] JSON解析失败: '%s'" % json_str)
		return {}
	return result

func _value_calculate_3d(p: Dictionary) -> Vector3:
	var left = _vs_to_vector3(p.get("left", 0.0))
	var right = _vs_to_vector3(p.get("right", 0.0))
	var op = str(p.get("op", "+"))
	match op:
		"+": return left + right
		"-": return left - right
		"*": return left * right
		"/": return left / right if right != 0 else 0.0
	return Vector3.ZERO

func _value_calculate_2d(p: Dictionary) -> Vector2:
	var left = _vs_to_vector2(p.get("left", Vector2.ZERO))
	var right = _vs_to_vector2(p.get("right", Vector2.ZERO))
	var op = str(p.get("op", "+"))
	match op:
		"+": return left + right
		"-": return left - right
		"*": return left * right
		"/": return left / right if right != Vector2.ZERO else Vector2.ZERO
	return Vector2.ZERO

func _value_deg_to_rad(p: Dictionary) -> float:
	return deg_to_rad(_vs_to_float(p.get("deg", 0.0)))

func _value_not_bool(p: Dictionary) -> bool:
	return not _vs_to_bool(p.get("bool", false))

func _value_val_in_a_and_b(p: Dictionary) -> bool:
	var val = _vs_to_float(p.get("val", 0.0))
	var a = _vs_to_float(p.get("a", 0.0))
	var b = _vs_to_float(p.get("b", 0.0))
	return val >= min(a, b) and val <= max(a, b)

func _value_get_var(p: Dictionary):
	var var_name = str(p.get("var", ""))
	return _vs_variables.get(var_name, 0.0)

func _value_get_long_var(p: Dictionary):
	var var_name = str(p.get("var", ""))
	var long_vars = _get_long_vars()
	return long_vars.get(var_name, "") if long_vars != null else ""

func _value_get_entity_data(p: Dictionary) -> Variant:
	var entity = _vs_to_entity(p.get("entity", null))
	var data_type = str(p.get("data_type", "title"))
	if not entity: return null
	match data_type:
		"title": return entity.title
		"hp": return entity.hp
		"name": return entity.name
		"position_3d": return Vector3(entity.position_3d.x, entity.position_3d.y, entity.position_3d.z)
		"facing_direction": return entity.facing_direction
	return null

func _value_get_entity_num_var(p: Dictionary) -> float:
	var entity = _vs_to_entity(p.get("entity", null))
	var var_name = str(p.get("var", ""))
	if not entity: return 0.0
	if entity.has_method("_vs_get_variable"):
		return _vs_to_float(entity._vs_get_variable(var_name))
	return 0.0

func _value_get_entity_string_var(p: Dictionary) -> String:
	var entity = _vs_to_entity(p.get("entity", null))
	var var_name = str(p.get("var", ""))
	if not entity: return ""
	if entity.has_method("_vs_get_variable"):
		return str(entity._vs_get_variable(var_name))
	return ""

func _value_get_entity_bool_var(p: Dictionary) -> bool:
	var entity = _vs_to_entity(p.get("entity", null))
	var var_name = str(p.get("var", ""))
	if not entity: return false
	if entity.has_method("_vs_get_variable"):
		return _vs_to_bool(entity._vs_get_variable(var_name))
	return false

func _value_get_entity_2d_var(p: Dictionary) -> Vector2:
	var entity = _vs_to_entity(p.get("entity", null))
	var var_name = str(p.get("var", ""))
	if not entity: return Vector2.ZERO
	if entity.has_method("_vs_get_variable"):
		return _vs_to_vector2(entity._vs_get_variable(var_name))
	return Vector2.ZERO

func _value_get_entity_3d_var(p: Dictionary) -> Vector3:
	var entity = _vs_to_entity(p.get("entity", null))
	var var_name = str(p.get("var", ""))
	if not entity: return Vector3.ZERO
	if entity.has_method("_vs_get_variable"):
		return _vs_to_vector3(entity._vs_get_variable(var_name))
	return Vector3.ZERO

func _value_get_entity_by_id(p: Dictionary) -> EntityBase:
	var id = _vs_to_int(p.get("id", 0))
	if not _entity.entity_manager: return null
	var all = _entity.entity_manager.get_all_entities()
	if id >= 0 and id < all.size():
		return all[id]
	return null

# 正则选择实体：props(逗号分隔的属性名) 的值用 | 拼接后正则匹配，取第 index 个匹配(注册顺序从0开始)
func _value_find_entity_by_regex(p: Dictionary) -> EntityBase:
	var regex_str = str(p.get("regex", "")).strip_edges()
	if regex_str == "": return null
	var index = _vs_to_int(p.get("index", 0))
	var props: Array = []
	for s in str(p.get("props", "name")).split(","):
		var t = s.strip_edges()
		if t != "": props.append(t)
	if props.is_empty(): props = ["name"]
	var em = _entity.entity_manager
	if not em: return null
	var reg = RegEx.new()
	if reg.compile(regex_str) != OK:
		push_warning("[VS] 正则编译失败: '%s'" % regex_str)
		return null
	var matched = 0
	for e in em.get_all_entities():
		if not is_instance_valid(e): continue
		var parts: Array = []
		for prop in props:
			parts.append(_vs_obj_prop_str(e, prop))
		if reg.search("|".join(parts)):
			if matched == index:
				return e
			matched += 1
	return null

# 正则选择特效：遍历特效容器(注册顺序)，props 值用 | 拼接后正则匹配，取第 index 个匹配(从0开始)
func _value_find_effect_by_regex(p: Dictionary) -> Node2D:
	var regex_str = str(p.get("regex", "")).strip_edges()
	if regex_str == "": return null
	var index = _vs_to_int(p.get("index", 0))
	var props: Array = []
	for s in str(p.get("props", "name")).split(","):
		var t = s.strip_edges()
		if t != "": props.append(t)
	if props.is_empty(): props = ["name"]
	var ec = _entity.effects_container
	if not ec: return null
	var reg = RegEx.new()
	if reg.compile(regex_str) != OK:
		push_warning("[VS] 正则编译失败: '%s'" % regex_str)
		return null
	var matched = 0
	for eff in ec.get_children():
		if not is_instance_valid(eff): continue
		var parts: Array = []
		for prop in props:
			parts.append(_vs_obj_prop_str(eff, prop))
		if reg.search("|".join(parts)):
			if matched == index:
				return eff
			matched += 1
	return null

func _vs_obj_prop_str(obj: Node, prop: String) -> String:
	var v = obj.get(prop)
	if v != null: return str(v)
	# 视觉脚本变量：读实体挂载的组件
	var comp = obj.get("_vs_component")
	if comp is VisualScriptComponent:
		var vv = comp._vs_get_variable(prop)
		if vv != null: return str(vv)
	return ""

func _value_latest_non_player_entity(p: Dictionary) -> EntityBase:
	var title_filter = str(p.get("title", ""))
	var em = _entity.entity_manager
	if not em: return null
	var all = em.get_all_entities()
	var latest: EntityBase = null
	for i in range(all.size() - 1, -1, -1):
		var e = all[i]
		if not is_instance_valid(e): continue
		if e == _entity: continue
		if e.entity_type == EntityBase.EntityType.PLAYER: continue
		if e.team_id != _entity.team_id: continue  # 不追踪敌方
		if latest == null:
			latest = e
		if title_filter != "" and e.title == title_filter:
			return e
	return latest

func _value_has_valid_target(p: Dictionary) -> bool:
	var t = p.get("target", null)
	return is_instance_valid(t) and t is EntityBase

func _value_distance_2d(p: Dictionary) -> float:
	var p1 = _vs_to_vector2(p.get("p1", Vector2.ZERO))
	var p2 = _vs_to_vector2(p.get("p2", Vector2.ZERO))
	return p1.distance_to(p2)

func _value_player_entity(p: Dictionary) -> EntityBase:
	var id = _vs_to_int(p.get("id", 0))
	if not _entity.entity_manager: return null
	var players: Array[EntityBase] = []
	for e in _entity.entity_manager.get_all_entities():
		if e.entity_type == EntityBase.EntityType.PLAYER:
			players.append(e)
	if id >= 0 and id < players.size():
		return players[id]
	var pe = _entity.entity_manager.get_player_entity()
	if pe: return pe
	return null

func _value_is_ourside_entity(p: Dictionary) -> bool:
	var entity = _vs_to_entity(p.get("entity", null))
	if not entity: return false
	return entity.team_id == _entity.team_id

func _value_get_parent_entity(p: Dictionary) -> EntityBase:
	var entity = _vs_to_entity(p.get("entity", null))
	if not entity: return null
	return entity.parent_entity

func _value_get_root_parent_entity(p: Dictionary) -> EntityBase:
	var target = _vs_to_entity(p.get("entity", null))
	if not target: return null
	return target.get_root_parent_entity()

func _value_get_my_team(_p: Dictionary) -> int:
	return _entity.team_id

func _value_get_opponent_team(_p: Dictionary) -> int:
	match _entity.team_id:
		TeamManager.TeamID.PLAYER_1:
			return TeamManager.TeamID.PLAYER_2
		TeamManager.TeamID.PLAYER_2:
			return TeamManager.TeamID.PLAYER_1
		_:
			return TeamManager.TeamID.NONE

func _value_now_dir(_p: Dictionary) -> int:
	return _entity.facing_direction

func _value_now_pos2d(_p: Dictionary) -> Vector2:
	return Vector2(_entity.position_3d.x, _entity.position_3d.y)

func _value_now_pos3d(_p: Dictionary) -> Vector3:
	return _entity.position_3d

func _value_now_energy_bar(_p: Dictionary) -> float:
	return _entity.energy_bar.value

func _value_timer_alive(_p: Dictionary) -> bool:
	var cd_id = _vs_to_int(_p.get("cd_id", 0))
	return _entity.skill_timer[cd_id]["time"] > 0

func _value_get_info_point(_p: Dictionary) -> Vector2:
	var name = str(_p.get("name", ""))
	return _entity.get_info_point_position(name)

func _value_add_pos3d_to_spos2d(_p: Dictionary) -> Vector3:
	var spos2d = _vs_to_vector2(_p.get("spos2d", Vector2.ZERO))
	var resu = _entity.position_3d
	resu.x = resu.x + spos2d.x
	resu.z = resu.z - spos2d.y
	return resu

func _value_add_pos3d_to_hpos2d(_p: Dictionary) -> Vector3:
	var hpos2d = _vs_to_vector2(_p.get("hpos2d", Vector2.ZERO))
	var resu = _entity.position_3d
	resu.x = resu.x + hpos2d.x
	resu.y = resu.y + hpos2d.y
	return resu

func _value_calculate_immobilize_position_3d(_p: Dictionary) -> Vector3:
	var target = _vs_to_entity(_p.get("target", null))
	if not target: return Vector3.ZERO
	var mifn = str(_p.get("mifn", ""))
	var tifn = str(_p.get("tifn", ""))
	return _entity.calculate_immobilize_position_3d(target, mifn, tifn)

func _value_c_outwall_pos_3d(_p: Dictionary) -> Vector3:
	print(_p.get("pos", Vector3.ZERO))
	var pos = _vs_to_vector3(_p.get("pos", Vector3.ZERO))
	var wall_pos = _entity.main.point_walls(Vector2(pos.x, pos.y))
	if wall_pos:
		pos.x = wall_pos.x
		pos.y = wall_pos.y
	return pos

func _value_a_have_b(p: Dictionary) -> bool:
	var a = str(p.get("a", ""))
	var b = str(p.get("b", ""))
	return b in a

func _value_a_front_b(p: Dictionary) -> bool:
	var a = str(p.get("a", ""))
	var b = str(p.get("b", ""))
	return a.begins_with(b)

func _value_get_random_in_ab(p: Dictionary):
	var a = p.get("a", "")
	var b = p.get("b", "")
	if a is float: a = _vs_to_float(a)
	else: a = _vs_to_int(a)
	if b is float: b = _vs_to_float(b)
	else: b = _vs_to_int(b)
	return blocks_rng.randi_range(a, b)

func _value_2dv_num(p: Dictionary) -> float:
	var val = _vs_to_vector2(p.get("val", Vector2.ZERO))
	var type_str = str(p.get("type", "X"))
	match type_str:
		"X": return val.x
		"Y": return val.y
	return 0.0

func _value_3dv_num(p: Dictionary) -> float:
	var val = _vs_to_vector3(p.get("val", Vector3.ZERO))
	var type_str = str(p.get("type", "X"))
	match type_str:
		"X": return val.x
		"Y": return val.y
		"Z": return val.z
	return 0.0

func _value_3d_data(p: Dictionary) -> Vector3:
	var x = _vs_to_float(p.get("x", 0.0))
	var y = _vs_to_float(p.get("y", 0.0))
	var z = _vs_to_float(p.get("z", 0.0))
	return Vector3(x, y, z)

func _value_2d_data(p: Dictionary) -> Vector2:
	var x = _vs_to_float(p.get("x", 0.0))
	var y = _vs_to_float(p.get("y", 0.0))
	return Vector2(x, y)

func _value_is_press_key(p: Dictionary) -> bool:
	var key = _vs_to_int(p.get("key", 0))
	if key >= 0 and key < _entity.inputs.size():
		return _entity.inputs[key]
	return false

func _value_is_moving(p: Dictionary) -> bool:
	return _entity.input_left or _entity.input_right or _entity.input_up or _entity.input_down

func _value_is_moving_dir(p: Dictionary) -> bool:
	var dir = str(p.get("dir", "上"))
	match dir:
		"上": return _entity.input_up
		"下": return _entity.input_down
		"左": return _entity.input_left
		"右": return _entity.input_right
	return false

# ============================================
# 变量系统公共接口
# ============================================

func _vs_set_variable(var_name: String, value: Variant):
	_vs_variables[var_name] = value

func _vs_get_variable(var_name: String) -> Variant:
	return _vs_variables.get(var_name, null)


# ============================================
# 辅助工具
# ============================================

func _vs_try_to_float(value: Variant) -> Variant:
	if value == null: return null
	if value is float: return value
	if value is int: return float(value)
	if value is String:
		if value.is_valid_float():
			return value.to_float()
		return null
	return null

# 视觉脚本变量代理：vars.xxx 动态读写 _vs_variables
class _VsVarsEnv:
	var data: Dictionary = {}
	func _get(property: StringName) -> Variant:
		return data.get(property, null)
	func _set(property: StringName, value: Variant) -> bool:
		data[property] = value
		return true
