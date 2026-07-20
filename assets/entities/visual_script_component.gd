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
var _vs_last_frame_idx: Dictionary = {}
var _vs_game_started_fired: bool = false
var _vs_victory_fired: bool = false
var _vs_initialized: bool = false
## 延迟执行的图标设置标记 (因 setup_icon 在 _vs_init 之前被调用)
var _vs_pending_setup_icon: bool = false
## 自定义效果持续事件触发冷却追踪
var _vs_modifier_cooldowns: Dictionary = {}
## 奥义点标记字典
var _vs_ultimate_flags: Dictionary = {}

var blocks_rng = RandomNumberGenerator.new()

# ============================================
# 初始化
# ============================================

func _ready():
	# 由父节点的 _deferred_heavy_init 触发实际初始化
	pass

func _vs_init():
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

func _vs_check_events(delta):
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
		if exit_anim != "":
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
	if current_animation != _vs_prev_animation:
		var old_anim = _vs_prev_animation
		_vs_prev_animation = current_animation
		_vs_pending_anim = current_animation
		_vs_pending_frame_count = 0
		_vs_last_frame_idx[current_animation] = -1

		if not _vs_script_set_animation and not _entity._immobilize_active:
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
		if not _vs_script_set_animation and old_anim != _vs_exit_fired_for and old_anim != "":
			_vs_fire_event("when_any_animation_ended", {"anim_name": old_anim})
		_vs_exit_fired_for = ""
		_vs_script_set_animation = false

	# ---- when_animation_playing ----
	var frame_val = _entity.get_current_frame()
	if _vs_pending_anim != "" and _vs_pending_anim == current_animation:
		_vs_pending_frame_count += 1
		if frame_val == 0 or _vs_pending_frame_count > 2:
			_vs_pending_anim = ""

	if _vs_pending_anim == "" and current_animation != "" and frame_val != _vs_last_frame_idx.get(current_animation, -1):
		_vs_last_frame_idx[current_animation] = frame_val
		var matched_playing_ids: Array = []
		if _vs_event_chains.has("when_animation_playing"):
			for eid in _vs_event_chains["when_animation_playing"]:
				var eblock = _vs_blocks_by_id[eid]
				var target_anim = str(eblock.params.get("anim_name", ""))
				if target_anim == current_animation:
					matched_playing_ids.append(eid)
		var matched_playing_rows = _vs_collect_matching_rows("when_animation_playing", "anim_name", current_animation)
		if matched_playing_ids.size() > 0 or matched_playing_rows.size() > 0:
			_vs_fire_event("when_animation_playing", {
				"anim_name": current_animation,
				"frame_idx": frame_val
			}, matched_playing_ids, matched_playing_rows)

	# ---- when_frame_changed（每 1/60 秒无条件触发）----
	var matched_fc_ids: Array = []
	if _vs_run_mode != "events_only" and _vs_event_chains.has("when_frame_changed"):
		matched_fc_ids = _vs_event_chains["when_frame_changed"]
	var matched_fc_rows: Array = []
	if _vs_run_mode != "blocks_only" and _vs_event_table_chains.has("when_frame_changed"):
		for row in _vs_event_table_chains["when_frame_changed"]:
			if bool(row.get("enabled", true)):
				matched_fc_rows.append(row)
	if matched_fc_ids.size() > 0 or matched_fc_rows.size() > 0:
		_vs_fire_event("when_frame_changed", {}, matched_fc_ids, matched_fc_rows)

	# ---- when_any_animation_frame_changed ----
	if _vs_pending_anim == "" and current_animation != "" and frame_val != _vs_last_frame_idx.get(current_animation, -1):
		_vs_fire_event("when_any_animation_frame_changed", {
			"anim_name": current_animation,
			"frame_idx": frame_val
		})

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

# ---- 攻击命中事件 (由实体委托调用) ----

func _on_attack_hit(hit_result):
	if not _vs_initialized: return

	var target_entity = hit_result.target_entity as EntityBase
	if not target_entity: return

	var box_config = hit_result.attack_config
	var hit_eff_pos = _entity.calculate_intersection(hit_result, box_config.to_dict())
	var abox_name = hit_result.attack_box_name
	var ipoint = Vector3(hit_eff_pos.x, _entity.position_3d.y, hit_eff_pos.y)

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

func _on_death():
	if _vs_initialized:
		_vs_fire_event("when_death", {"attacker": _entity._last_attacker if _entity._last_attacker else null})

# ---- 自定义效果事件 (由实体委托调用) ----

func _on_modifier_start(type: String, power: int, time_left: float = -2.0):
	if not _vs_initialized: return
	_vs_fire_modifier_event("when_modifier_start", type, power, time_left)

func _on_modifier_update(type: String, power: int, time_left: float = -2.0):
	if not _vs_initialized: return
	_vs_fire_modifier_event("when_modifier_update", type, power, time_left)

func _on_modifier_end(type: String, power: int, time_left: float = -2.0):
	if not _vs_initialized: return
	_vs_fire_modifier_event("when_modifier_end", type, power, time_left)

func _vs_fire_modifier_event(event_name: String, type: String, power: int, time_left: float = -2.0):
	var ctx = {"mod_type": type, "mod_power": power, "mod_time": time_left, "target": _entity}
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
	_vs_deferred_exit_anim = _entity.current_animation

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
			_vs_execute_event_children.call_deferred(row.get("children", []), row, context)

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
	if _vs_debug_print:
		print("[VS-EQ] _vs_eval_expr: raw='", expr_str, "' → processed='", processed, "'")
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
		if i + 1 < s.length() and s[i] == '=' and s[i+1] == '=':
			# 提取左操作数：跳过 == 前的空格，再向左扫描
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
						paren_depth -= 1
					elif paren_depth == 0 and (s[j] == ' ' or s[j] in ['(', ')', ',']):
						break
					j -= 1
				left_start = j + 1
			var left_raw = s.substr(left_start, left_end - left_start).strip_edges()

			# 提取右操作数：跳过 == 后的空格，再向右扫描
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
					paren_depth -= 1
				elif paren_depth == 0 and (s[j] == ' ' or s[j] in ['(', ')', ',']):
					break
				j += 1
			right_end = j
			var right_raw = s.substr(right_start, right_end - right_start).strip_edges()

			# 分别求值左右操作数
			var left_val = _vs_eval_eq_side(left_raw, context)
			var right_val = _vs_eval_eq_side(right_raw, context)

			var eq = left_val == right_val
			if _vs_debug_print:
				print("[VS-EQ] '", left_raw, "' (", typeof(left_val), "=", left_val, ") == '", right_raw, "' (", typeof(right_val), "=", right_val, ") → ", eq)
			var replacement = "true" if eq else "false"

			s = s.substr(0, left_start) + replacement + s.substr(right_end)
			i = left_start + replacement.length()
			continue

		i += 1

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
				if _contains_unquoted_char(args_str, '('):
					continue
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
	var result = _vs_eval_expr(arg_str, context)
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
	return ch.is_valid_identifier() or ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")

func _is_valid_identifier(s: String) -> bool:
	if s == "": return false
	if not (_is_ident_first_char(s[0])): return false
	for i in range(1, s.length()):
		if not _is_ident_char(s[i]): return false
	return true

func _is_ident_first_char(ch: String) -> bool:
	return ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")

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
		"die":
			_action_die(params)
		"die_entity":
			_action_die_entity(params)
		"hit_entity":
			_action_hit_entity(params)
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
					print("[DEBUG] _vs_resolve_params: evaluated result=", evaluated, " type=", typeof(evaluated))
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
	_vs_script_set_animation = true
	_entity.play_animation(anim_name)

# ---- 转向 ----

func _action_turn_to(p: Dictionary):
	var dir_str = str(p.get("d", "左"))
	match dir_str:
		"左":
			_entity.set_facing(-1)
		"右":
			_entity.set_facing(1)

func _action_turn_by_input(_p: Dictionary):
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

# ---- 实体操作 ----

func _action_slide(p: Dictionary):
	var v = _vs_to_vector3(p.get("v", Vector3.ZERO))
	var r = _vs_to_vector2(p.get("r", Vector2.ZERO))
	var g = _vs_to_float(p.get("g", 0.0))
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
	_entity.set_slide_gravity(g)
	var speed = v.x
	if speed > 0:
		_entity.start_slide(speed, slide_dir, r.x)
	if v.y != 0:
		_entity.slide_velocity.y = v.y

func _action_hit_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return

	var hit_type_str = str(p.get("type", "push"))
	var v = _vs_to_vector3(p.get("v", Vector3.ZERO))
	var hst = _vs_to_float(p.get("hst", 0.0))
	var cotg = _vs_to_bool(p.get("cotg", false))
	var ish = _vs_to_bool(p.get("ish", false))
	var bs = _vs_to_float(p.get("bs", 0.0))
	var isgd = _vs_to_bool(p.get("isgd", false))
	var hurt = _vs_to_float(p.get("hurt", 0.0))
	var kr = _vs_to_float(p.get("kr", 10.0))

	var hit_type = _entity.HitStateType.PUSH if hit_type_str == "push" else _entity.HitStateType.LAUNCH
	var kv = Vector2(v.x, v.y)
	if isgd:
		kv.x = kv.x * _entity.facing_direction

	# 在 hit() 前设置攻击者，让 change_hp 能访问到
	target._last_attacker = _entity
	target.hit(hit_type, kv, hst, v.z, cotg, ish, bs, hurt, kr)
	if target.has_method("_on_deal_hit"):
		target._on_deal_hit(_entity)

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
	target.set_magnetism(mpos, spe, d)

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
	_entity.main.add_global_magnetism(_entity.name+"_"+mag_name, center, [range_x1, range_y1, range_x2, range_y2], force, duration, affected_teams)

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
	_entity.main.add_global_magnetism(_entity.name+"_"+mag_name, center, [range_x1, range_y1, range_x2, range_y2], force, duration, affected_teams)

func _action_hit_stop_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target: return
	var d = _vs_to_float(p.get("d", -1))
	target.set_hit_stop(d)

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

func _action_die(_p: Dictionary):
	_entity.die()

func _action_die_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if target:
		target.die()

func _action_outwall_entity(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if target:
		var wall_pos = target.main.point_walls(Vector2(target.position_3d.x, target.position_3d.y))
		if wall_pos:
			target.position_3d.x = wall_pos.x
			target.position_3d.y = wall_pos.y

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
	target.set_modifiers(type, pow, d)

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

	target.set_immobilize(pos, time, rpos, ani, Vector2(v.x, v.y), kt, v.z, g, bs)
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
	var data_str = str(p.get("data", ""))
	var data = {}
	if data_str != "":
		var parsed = JSON.parse_string(data_str)
		if parsed is Dictionary:
			data = parsed
	if _entity.effects_container:
		_entity.effects_container.spawn_effect(eff_name, pos, not dir, data)

func _action_create_effect_copy(p: Dictionary):
	var eff_name = str(p.get("name", ""))
	var target = _vs_to_entity(p.get("target", null))
	var pos = _vs_to_vector3(p.get("pos", Vector3.ZERO))
	var dir = _vs_to_bool(p.get("dir", true))
	var data_str = str(p.get("data", ""))
	var data = {}
	if data_str != "":
		var parsed = JSON.parse_string(data_str)
		if parsed is Dictionary:
			data = parsed
	if _entity.effects_container and target:
		_entity.effects_container.spawn_follow_effect(eff_name, target, pos, true, not dir, data)

func _action_spawn_afterimage(p: Dictionary):
	var fade = _vs_to_float(p.get("fade", 0.5))
	var hold = _vs_to_float(p.get("hold", 0.0))
	var color = _vs_to_color(p.get("color", Color.WHITE))
	if _entity.effects_container:
		var eff = _entity.effects_container.spawn_effect("Afterimage", _entity.position_3d, false, {"target": _entity})
		if eff:
			eff.fade_time = fade
			eff.hold_time = hold
			eff.custom_modulate = color

func _action_spawn_cancel_white(p: Dictionary):
	if _entity.effects_container:
		_entity.effects_container.spawn_effect("CancelWhite", _entity.position_3d, false, {"target": _entity})

func _action_print(p: Dictionary):
	var text = str(p.get("text", ""))
	print(text)

func _action_show_info_text(p: Dictionary):
	var text = str(p.get("text", ""))
	_entity.show_info_text(text)
	print("提示: ", text)
	if _vs_debug_print:
		print("[DEBUG] _action_show_info_text: raw params=", p, " text='", text, "'")

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

# ---- 摄像机 ----

func _action_make_zoom_shock(p: Dictionary):
	var intensity = _vs_to_float(p.get("i", 0.0))
	var duration = _vs_to_float(p.get("d", 0.0))
	if _entity.camera:
		_entity.camera.zoom_shock(intensity, duration)

func _action_camera_shake(p: Dictionary):
	var intensity = _vs_to_float(p.get("intensity", 10.0))
	var duration = _vs_to_float(p.get("duration", 0.3))
	if _entity.camera:
		_entity.camera.shake_random(intensity, duration)

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
	var waveform_str = str(p.get("waveform", "正弦波"))
	var duration = _vs_to_float(p.get("duration", 0.0))
	var waveform: int = 0
	match waveform_str:
		"正弦波": waveform = 0
		"三角波": waveform = 1
		"方波":   waveform = 2
	if _entity.camera:
		_entity.camera.start_pulse_zoom(amplitude, frequency, waveform, duration)

func _action_camera_stop_pulse_zoom(_p: Dictionary):
	if _entity.camera:
		_entity.camera.stop_pulse_zoom()

func _action_camera_move(p: Dictionary):
	var offset = _vs_to_vector2(p.get("offset", Vector2.ZERO))
	var zoom_val = _vs_to_float(p.get("zoom", 1.0))
	var duration = _vs_to_float(p.get("duration", 0.5))
	if _entity.camera:
		_entity.camera.camera_move(offset, zoom_val, duration)

func _action_camera_move_absolute(p: Dictionary):
	var pos = _vs_to_vector2(p.get("pos", Vector2.ZERO))
	var zoom_val = _vs_to_float(p.get("zoom", 1.0))
	var duration = _vs_to_float(p.get("duration", 0.5))
	if _entity.camera:
		_entity.camera.camera_move_to_absolute(pos, zoom_val, duration)

func _action_camera_stop_move(p: Dictionary):
	var immediate = _vs_to_bool(p.get("immediate", false))
	if _entity.camera:
		_entity.camera.stop_camera_move(immediate)

func _action_camera_rotate(p: Dictionary):
	var angle = _vs_to_float(p.get("angle", 0.0))
	var enter_duration = _vs_to_float(p.get("enter_duration", 0.2))
	var hold_duration = _vs_to_float(p.get("hold_duration", 0.5))
	var exit_duration = _vs_to_float(p.get("exit_duration", 0.3))
	if _entity.camera:
		_entity.camera.camera_rotate(angle, hold_duration, enter_duration, exit_duration)

# ---- 补间动画 ----

func _action_tween_property(p: Dictionary):
	var target = _vs_to_entity(p.get("target", null))
	if not target:
		if _vs_debug_print:
			push_warning("[VS-tween] 目标实体为空")
		return
	var prop = str(p.get("prop", "scale"))
	var to_val = _vs_to_float(p.get("to", 1.0))
	var dur = _vs_to_float(p.get("dur", 0.5))
	var ease_str = str(p.get("ease", "缓出"))
	var delay = _vs_to_float(p.get("delay", 0.0))
	var ease_type = _vs_tween_ease(ease_str)
	var trans_type = Tween.TRANS_SINE
	match ease_str:
		"线性": trans_type = Tween.TRANS_LINEAR
	match prop:
		"scale":
			var tween = target.create_tween()
			tween.tween_property(target, "scale", Vector2(to_val, to_val), dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"modulate":
			var tween = target.create_tween()
			tween.tween_property(target, "modulate", Color(to_val, to_val, to_val, 1.0), dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"modulate:a":
			var src = target.modulate
			var dst = Color(src.r, src.g, src.b, to_val)
			var tween = target.create_tween()
			tween.tween_property(target, "modulate", dst, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"rotation":
			var tween = target.create_tween()
			tween.tween_property(target, "rotation", deg_to_rad(to_val), dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"position:x":
			var tween = target.create_tween()
			tween.tween_property(target, "position:x", to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished
		"position:y":
			var tween = target.create_tween()
			tween.tween_property(target, "position:y", to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
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
			var tween = target.create_tween()
			tween.tween_property(target, prop, to_val, dur).set_delay(delay).set_trans(trans_type).set_ease(ease_type)
			await tween.finished

func _vs_tween_ease(ease_str: String) -> int:
	match ease_str:
		"缓入": return Tween.EASE_IN
		"缓出": return Tween.EASE_OUT
		"缓入缓出": return Tween.EASE_IN_OUT
		_: return Tween.EASE_IN_OUT

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
	var dir = _vs_to_int(p.get("dir", 0))
	match dir:
		0: return _entity.input_up
		1: return _entity.input_down
		2: return _entity.input_left
		3: return _entity.input_right
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
