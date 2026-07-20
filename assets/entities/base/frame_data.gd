@tool
extends Resource
class_name FrameData

# 每帧的数据
@export var frame_index: int = 0
@export var anchor_point: Vector2 = Vector2.ZERO  # 锚点位置
@export var hitboxes_data: Array = []  # 存储每个HitboxArea的数据，使用通用Array类型

# 序列化方法
func serialize() -> Dictionary:
	return {
		"frame_index": frame_index,
		"anchor_point": {"x": anchor_point.x, "y": anchor_point.y},
		"hitboxes_data": hitboxes_data.duplicate(true)
	}

func deserialize(data: Dictionary) -> void:
	frame_index = data.get("frame_index", 0)
	
	var anchor_data = data.get("anchor_point", {})
	if anchor_data:
		anchor_point = Vector2(anchor_data.get("x", 0), anchor_data.get("y", 0))
	
	hitboxes_data = data.get("hitboxes_data", [])
