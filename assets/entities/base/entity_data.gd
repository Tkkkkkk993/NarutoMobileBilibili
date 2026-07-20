# entity_data.gd
extends Resource
class_name EntityData

@export var entity_name: String = "Name[Title]"
@export var max_health: int = 3105960

# 横纵独立速度控制
@export var move_speed_x: float = 350  # 水平移动速度
@export var move_speed_y: float = 175  # 垂直移动速度

@export var substitution_distance: float = 500

@export var floder_path: String = "res://assets/entities/.../"

@export var custom_entry: String = ""
@export var custom_entry_extra_pos3d: Vector3 = Vector3.ZERO

# 在这些动画播放时也视为待机状态（结算时可跳过等待）
@export var extra_idle_anims: Array[String] = []

# 该资源保存在floder_path下的main.tres
# FrameData数据保存在floder_path下的entity_frame_data.json
