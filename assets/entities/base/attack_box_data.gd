# attack_box_data.gd (修复版)

class_name AttackBoxData
extends Resource

class FrameConfig:
	var position: Vector3 = Vector3.ZERO  # 相对于实体锚点的偏移
	var size: Vector3 = Vector3(50, 50, 50)  # XYZ三轴大小
	var pivot_offset: Vector2 = Vector2.ZERO  # 视觉锚点偏移（用于编辑器居中显示）
	
	func to_dict() -> Dictionary:
		return {
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"size": {"x": size.x, "y": size.y, "z": size.z},
			"pivot_offset": {"x": pivot_offset.x, "y": pivot_offset.y}
		}
	
	func from_dict(data: Dictionary):
		if data.has("position"):
			var p = data["position"]
			position = Vector3(p.get("x", 0), p.get("y", 0), p.get("z", 0))
		if data.has("size"):
			var s = data["size"]
			size = Vector3(s.get("x", 50), s.get("y", 50), s.get("z", 50))
		if data.has("pivot_offset"):
			var o = data["pivot_offset"]
			pivot_offset = Vector2(o.get("x", 0), o.get("y", 0))
		# 兼容旧数据的offset字段
		elif data.has("offset"):
			var o = data["offset"]
			pivot_offset = Vector2(o.get("x", 0), o.get("y", 0))

@export var box_id: String = ""
@export var box_name: String = ""
@export var bind_animation: String = ""
var bind_frames: Array = []
var frame_configs: Dictionary = {}

# 实例级触发状态（修复：支持多实例同时存在）
var _instance_triggers: Dictionary = {}  # instance_key -> bool

func _init():
	if box_id == "":
		box_id = "attack_box_" + str(randi())

func get_frame_config(frame: int) -> FrameConfig:
	return frame_configs.get(frame, null)

func set_frame_config(frame: int, config: FrameConfig):
	frame_configs[frame] = config
	if not frame in bind_frames:
		bind_frames.append(frame)
		bind_frames.sort()

func remove_frame_config(frame: int):
	frame_configs.erase(frame)
	bind_frames.erase(frame)

func is_active_at_frame(frame: int) -> bool:
	return frame_configs.has(frame)

# 实例级触发检查（修复：支持同一攻击框多实例）
func has_triggered_instance(instance_key: String) -> bool:
	return _instance_triggers.get(instance_key, false)

func set_triggered_instance(instance_key: String):
	_instance_triggers[instance_key] = true

func reset_trigger():
	_instance_triggers.clear()

func to_dict() -> Dictionary:
	var frames_dict = {}
	for frame in frame_configs.keys():
		frames_dict[str(frame)] = frame_configs[frame].to_dict()
	
	var unique_frames = bind_frames.duplicate()
	unique_frames.sort()
	
	return {
		"box_id": box_id,
		"box_name": box_name,
		"bind_animation": bind_animation,
		"bind_frames": unique_frames,
		"frame_configs": frames_dict
	}

func from_dict(data: Dictionary):
	box_id = data.get("box_id", "")
	box_name = data.get("box_name", "")
	bind_animation = data.get("bind_animation", "")
	
	bind_frames.clear()
	var raw_frames = data.get("bind_frames", [])
	for f in raw_frames:
		var frame_int = int(f)
		if not frame_int in bind_frames:
			bind_frames.append(frame_int)
	bind_frames.sort()
	
	frame_configs.clear()
	var frames_dict = data.get("frame_configs", {})
	for frame_str in frames_dict.keys():
		var frame = int(frame_str)
		var config = FrameConfig.new()
		config.from_dict(frames_dict[frame_str])
		frame_configs[frame] = config
	
	# 同步确保一致性
	for frame in frame_configs.keys():
		if not frame in bind_frames:
			bind_frames.append(frame)
	bind_frames.sort()
