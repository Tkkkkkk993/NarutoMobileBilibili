extends Node

# ============================================
# 真实输入（触屏 / UI 按钮）的唯一入口
# ============================================
# 职责：把 UI 触发的按钮按下事件转发给它所属的玩家实体。
#
# 历史说明：本节点曾自带一套「时间停止期间缓冲输入」的逻辑
# （is_time_stopped / _buffered_events / start_time_stop / _end_time_stop /
#   _buffer_event / _flush_buffered）。但唯一能把它打开的 start_time_stop()
# 在全仓库从未被调用过，因此那套缓冲一次都没有真正运行过，已整体移除。
#
# 输入缓冲现在由 EntityBase 的 _input_buffer + _consume_local_buffer() 统一承担；
# 真实输入与 AI 输入共用同一个门控 handle_button_press()
# （优先级判定 _can_execute_immediately + 入队 _add_to_local_buffer）。

enum Priority {
	SUBSTITUTION = 0,
	ATTACK = 2,
	SKILL = 2,
	ULTIMATE = 3,
	SCROLL = 4,
	SUMMON = 4,
}

## UI 按钮按下 → 转发给玩家实体（与 AI 输入共用 handle_button_press 门控）
func on_button_pressed(slot_id: int, action_name: String, priority: int) -> void:
	var player = _get_player()
	if not player:
		return
	if player.has_method("handle_button_press"):
		player.handle_button_press(slot_id, action_name, priority)

## 取被控玩家实体
## TODO(联机 / 本地 2P)：目前硬编码 players[0]。
## P2 目前只用键盘所以未暴露；将来若 P2 要走触屏，
## 需要让 SkillSlot 携带其所属实体引用，改为按来源实体路由。
func _get_player() -> Node:
	var players = get_tree().get_nodes_in_group("player_entities")
	return players[0] if players.size() > 0 else null
