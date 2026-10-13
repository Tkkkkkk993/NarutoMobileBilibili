# entity_base.gd
class_name EntityBase
extends CharacterBody2D

# ============================================
# 导出变量
# ============================================

var entity_data: EntityData
@export var res_path: String
var frame_data_path: String = ""

## 阵营设置
@export_group("阵营")
@export var team_id: int = TeamManager.TeamID.NONE:
	set(value):
		var old_team = team_id
		team_id = value
		if is_inside_tree():
			_update_team_registration(old_team)

## 移动设置
@export var use_inertia: bool = false
@export var inertia_speed: float = 12.0

## Z轴物理设置
@export_group("Z轴物理")
@export var gravity: float = 2000.0
@export var max_fall_speed: float = 1500.0
@export var ground_level: float = 0.0

## 调试设置
@export_group("调试")
@export var debug_anchor: bool = false
@export var debug_slide: bool = true
@export var debug_z_axis: bool = true
@export var debug_team: bool = true
## 打印逐帧链路的跳帧补偿情况（帧事件 / 位移序列 / 攻击框）。
## 打开后若出现"跳帧补偿 N 帧"，说明那一 tick 发生了卡顿 —— 用于核对补偿是否生效。
@export var debug_frame_pipeline: bool = false

## 碰撞框调试
@export_group("碰撞框调试")
@export var debug_show_hitboxes: bool = true:
	set(value):
		debug_show_hitboxes = value
		_update_debug_visuals()
@export var debug_show_attack_boxes: bool = true:
	set(value):
		debug_show_attack_boxes = value
		_update_debug_visuals()
@export var debug_box_line_width: float = 2.0
@export var debug_hitbox_color: Color = Color.BLUE
@export var debug_attack_box_color: Color = Color.RED
@export var debug_box_fill_alpha: float = 0.2
@export var debug_show_z_depth: bool = true

## 信息点调试
@export_group("信息点调试")
@export var debug_show_info_points: bool = true: 
	set(value): 
		debug_show_info_points = value 
		_update_debug_visuals()
@export var debug_info_point_color: Color = Color(0.0, 1.0, 0.5, 0.9) # 亮青绿色
@export var debug_info_point_size: float = 6.0

## 深度排序
@export_group("深度排序")
@export var enable_depth_sort: bool = true
@export var depth_sort_priority: int = 0

# ============================================
# 节点引用
# ============================================

var visuals_node: Node2D
var shadow_node: Node2D
var hitbox_areas: Array[Area2D] = []
var main
var camera: DuelCamera
var effects_container
var fight_ui
var info_bar: Control
var hp_bar: Control
var hp_red: TextureProgressBar
var energy_bar: TextureProgressBar
var ultimate_panel: Control
var title_label: Label
var skill_panel: CanvasLayer
var skill_slot = []  # 当前绑定的槽位 (NullSlot 或真实 SkillSlot)
var _real_skill_slots: Array[SkillSlot] = []  # 真实 SkillPanel 节点引用
var button_pressed: Array[bool]
var protections: Control
var entity_manager: EntityManager
var virtual_joystick: VirtualJoystick
var arena
var info_label
var info_animation_player
@onready var aura_node = $Shadow/Aura

# ============================================
# 动画抽象接口 (子类实现)
# ============================================
# 子类必须实现以下方法:
#   - get_animator_node() -> Node
#   - has_animation(anim_name: String) -> bool
#   - can_play_animation(anim_name: String) -> bool
#   - play_animation(anim_name: String, custom_speed: float = -1.0, start_frame: int = 0)
#   - get_current_frame() -> int
#   - get_current_animation() -> String
#   - pause_animation()
#   - resume_animation()
#   - set_animation_frame(frame_idx: int)
#   - get_animation_frame_count(anim_name: String) -> int
#   - get_animation_speed_scale() -> float
#   - set_animation_speed_scale(speed: float)

func get_animator_node() -> Node:
	"""获取动画播放器节点，用于坐标计算等"""
	return null

func has_animation(anim_name: String) -> bool:
	"""检查动画是否存在"""
	return false

func can_play_animation(anim_name: String) -> bool:
	"""判断当前是否能够播放指定动画（动画存在 且 未被定身）"""
	return has_animation(anim_name) and not _immobilize_active

func play_animation(anim_name: String, custom_speed: float = 1.0, start_frame: int = 0):
	"""播放指定动画。
	start_frame 为从第几帧开始播，默认 0。
	大于 0 时，起始帧之前那几帧视为没播过：挂在它们上面的帧事件、滑步序列、
	特效绑定与攻击框都不会补出来。"""
	if _immobilize_active: return
	# 动画不存在时必须整体拒绝，不能先写 current_animation 再让子类跳过。
	# 否则产生幽灵动画：精灵还在播旧动画，逻辑层却以为在播新动画，
	# 状态机的退出回调（animation_finished）永远等不到，标志位永久挂死。
	if not has_animation(anim_name):
		push_warning("[play_animation] %s 没有动画 %s，忽略" % [name, anim_name])
		return
	current_animation = anim_name
	if anim_name == "idle":
		var wall_pos = main.point_walls(Vector2(position_3d.x, position_3d.y))
		if wall_pos:
			position_3d.x = wall_pos.x
			position_3d.y = wall_pos.y
			_last_valid_wall_pos = wall_pos
		else:
			_last_valid_wall_pos = Vector2(position_3d.x, position_3d.y)
	_on_animation_play_started(anim_name, start_frame)

# ============================================
# 播放起点（起始帧）
# ============================================

## 本次播放的起始帧，0 表示从第 0 帧播。
var play_start_frame: int = 0
## 播放序号，每真正开始播放一次动画自增一次。
## 图形化脚本靠它判断「这是一次新的播放」，从而把帧事件游标对齐到起始帧。
## play_animation 里被拒掉的调用（定身中、动画不存在）不增。
var play_seq: int = 0

## 动画真正开始播放时由各动画实现调用：记录本次播放起点，并把三处帧游标对齐到起始帧。
##
## 三处游标都要对齐，缺一处起始帧之前那几帧就会被当成「播过了」补出来：
##   _last_processed_visual_frame / processed_frames 管帧事件、滑步序列与特效绑定，
##   attack_box_manager 的 _last_box_anim / _last_box_frame 管攻击框开合。
## 起始帧为 0 时不碰这些游标，行为与加起始帧之前完全一致。
func _on_animation_play_started(anim_name: String, start_frame: int) -> void:
	play_start_frame = maxi(start_frame, 0)
	play_seq += 1
	if attack_box_manager:
		attack_box_manager.on_animation_play(anim_name, play_start_frame)
	if play_start_frame > 0:
		_last_processed_animation = anim_name
		_last_processed_visual_frame = play_start_frame - 1
		processed_frames.clear()

## 把播放位置挪到起始帧。不大于 0 时不动，越界夹到末帧。
## 各动画实现必须在真正 play 之后再调它，顺序反了会被 play 重置回第 0 帧。
func _apply_play_start_frame(anim_name: String, start_frame: int) -> void:
	if start_frame <= 0:
		return
	var total := get_animation_frame_count(anim_name)
	var f := start_frame
	if total > 0:
		f = mini(f, total - 1)
	if f > 0:
		set_animation_frame(f)

func get_current_frame() -> int:
	"""获取当前动画帧索引"""
	return 0

func get_current_animation() -> String:
	"""获取当前动画名称"""
	return current_animation

func pause_animation():
	"""暂停当前动画"""
	pass

func resume_animation():
	"""恢复动画播放"""
	pass

func set_animation_frame(frame_idx: int):
	"""设置当前动画帧索引"""
	pass

func get_animation_frame_count(anim_name: String) -> int:
	"""获取指定动画总帧数"""
	return 0

func get_animation_list() -> PackedStringArray:
	"""获取所有动画名称列表"""
	return PackedStringArray()

func get_animation_speed_scale() -> float:
	"""获取动画播放速度缩放"""
	return 1.0

func set_animation_speed_scale(speed: float):
	"""设置动画播放速度缩放"""
	pass

func get_current_frame_texture() -> Texture2D:
	"""返回当前帧的纹理，供残影/特效等子系统使用。
	   子类按自身实现覆盖。"""
	return null

func get_anim_sprite_scale() -> Vector2:
	"""获取动画节点的本地缩放"""
	return Vector2.ONE

func get_visuals_extra_scale() -> Vector2:
	"""锚点补偿里额外要乘的 Visuals 缩放大小。
	两种动画实现的口径不同：AnimatedSprite2DEntity 的 get_anim_sprite_scale()
	返回动画节点自身的缩放，Visuals 的缩放不在其中，必须在这里补上；
	AnimationPlayerEntity 与 CompositeRendererEntity 返回的就是 Visuals.scale，
	已经算过一次，各自覆盖成 ONE 避免重复相乘。
	Visuals.scale 为 ±1 时本项恒为 ONE，锚点补偿与加这一项之前完全一致。"""
	if visuals_node:
		return visuals_node.scale.abs()
	return Vector2.ONE

func get_anim_global_scale() -> Vector2:
	"""获取动画节点的全局缩放"""
	return Vector2.ONE

func get_anim_global_position() -> Vector2:
	"""获取动画节点的全局位置"""
	return Vector2.ZERO

func get_anim_material() -> Material:
	"""获取动画节点的材质"""
	return null

func set_anim_material(mat: Material):
	"""设置动画节点的材质"""
	pass

func set_anim_self_modulate(color: Color):
	"""设置动画节点的自调制颜色"""
	pass

func stop_animation():
	"""停止动画播放"""
	pass

# ============================================
# 3D状态数据
# ============================================

var position_3d: Vector3 = Vector3.ZERO
var velocity_3d: Vector3 = Vector3.ZERO

var current_frame_data: FrameData = null
var animation_frame_data: Dictionary = {}
var velocity_smoothed: Vector2 = Vector2.ZERO
var facing_direction: int = 1
var is_running: bool = false
var current_animation: String = "idle"

var current_anchor_offset: Vector2 = Vector2.ZERO
var last_logged_frame: int = -1
var last_logged_animation: String = ""

# ============================================
# 阵营系统
# ============================================

var _current_team: int = TeamManager.TeamID.NONE
signal team_changed(new_team: int)
signal broadcast_received(msg: String, data: Dictionary, is_global: bool)
## 受到附带力的攻击时发射: kv=击退速度, zv=击飞速度
signal receive_force(kv: Vector2, zv: float)
## 血量变化时发射: old_hp=变化前血量, new_hp=变化后血量
signal hp_changed(old_hp: float, new_hp: float)
## 被攻击命中时发射
signal deal_hit(attacker: Node2D)
## 死亡时发射
signal death()
## 自定义效果相关
signal modifier_start(type: String, power: int, time_left: float, target: Node2D)
signal modifier_update(type: String, power: int, time_left: float, target: Node2D)
signal modifier_end(type: String, power: int, time_left: float, target: Node2D)
## 冷却计时器到期时发射
signal timer_out(cd_id: int)
## 状态栈：某状态进入时发射（观察层，只报事实不驱动行为，见 assets/entities/base/entity_state_stack.gd）
signal entity_state_entered(state: int, frame: int)
## 状态栈：某状态退出时发射
signal entity_state_exited(state: int, frame: int)

# ============================================
# 控制系统
# ============================================

var is_under_control: bool = false
var knockback_active: bool = false
var hit_stun: float = 0

# ============================================
# Z轴状态
# ============================================

var is_grounded: bool = true
var z_velocity_override: float = 0.0
var z_slide_resistance: float = 5.0

# ============================================
# 滑动系统
# ============================================

var is_sliding: bool = false
var slide_velocity: Vector2 = Vector2.ZERO
var slide_resistance: Vector2 = Vector2(8.0, 8.0)
## 滑行期 Z 轴阻力覆盖 (-1 表示使用默认 z_slide_resistance)
var _slide_z_resistance: float = -1.0
var slide_sequences: Dictionary = {}
var current_slide_sequence: Array = []
var current_slide_index: int = -1
var slide_locked_facing: int = 1
var processed_frames: Dictionary = {}
var _last_processed_frame: int = -1  # 上一帧索引，用于检测跳帧
var frame_events_enabled: bool = true
var _current_slide_gravity: float = -1.0
var _slide_gravity_active: bool = false

# ============================================
# 击退系统
# ============================================

@export_group("击退")
## 落地进入倒地时是否清零水平击退速度（"倒地即停"手感）。
## 只在**本次击飞真的离过地**时才生效：否则"零上抛的扫地"会在写入击退的同一帧
## 就满足落地判定，把刚给出去的水平速度当场抹掉（扫地打不动人）。
## false = 保留残余水平速度，倒地的身体会继续滑一小段（旧行为）。
@export var clear_knockback_on_downed: bool = true
@export_group("")

var _knockback_velocity: Vector2 = Vector2.ZERO      # 当前击退速度
var _knockback_resistance: float = 10.0              # 地面阻力
var _knockback_air_resistance: float = 0.0           # 空中阻力（0=无阻力）
var _knockback_active: bool = false                  # 是否正在击退
var _knockback_timer: float = 0.0                    # 击退计时器

# 击退模型（由 hit() 每次按招式传入，见 KnockbackModel）
# EXPONENTIAL = 指数衰减（旧公式，默认行为，数据缺键时即此）
# LINEAR      = 线性匀减速（新公式）：地面用 kr、空中用 ar，皆为恒定减速度且
#               总滑行距离与旧公式一致。
#               （想要"空中一路推着走"，把 ar 填 0 即可 —— 两种模型下 ar=0 都表示不衰减。）
# 注意：模型只决定"衰减曲线形状"，不决定"给多少初速"。空中/地面的初速差异
#       由 hit() 的高度分支（z<=10 用 v、z>10 用 va）决定，没有额外的乘算惩罚。
var _knockback_linear: bool = false
var _knockback_initial_speed: float = 0.0            # 本次击退的初速大小（线性模型算减速度用）

enum KnockbackModel {
	EXPONENTIAL,  # 指数衰减（旧）
	LINEAR,       # 线性匀减速（新）
}

# ============================================
# 击飞系统
# ============================================

var _launch_velocity_z: float = 0.0
var _launch_active: bool = false
var _launch_gravity: float = 7000.0
## 本次击飞序列是否真的离过地（z 超过地面 1 单位）。
## 用作"倒地清零击退"的判据：零上抛的扫地从未离地，不能被当成落地。
var _launch_left_ground: bool = false

# 回弹相关
var _has_bounced: bool = false
var _bounce_dampening: float = 0.4

# 倒地相关
var _is_downed: bool = false
var _downed_timer: float = 0.0
var _downed_duration: float = 0.5  # 倒地持续时间

# 动画相关
var _launch_anim_timer: float = 0.0
var _current_launch_phase: String = ""

# 结束条件
var _launch_min_velocity: float = 50.0  # 速度小于此值结束

# ============================================
# 卡肉系统（Hit Stop）
# ============================================

var _hit_stop_active: bool = false      
var _hit_stop_timer: float = 0.0        
var _hit_stop_freeze_frame: bool = true 
var _hit_stop_prevent_physics: bool = true 
## 减帧是否为「延迟减帧」触发的。clear_temporary_status 只结束这一类减帧，
## 直接调 set_hit_stop 进来的减帧不归它管。
var _hit_stop_from_delay: bool = false
## 待触发的延迟减帧队列，每项 {duration, freeze_frame, prevent_physics, delay}。
## delay 走完就按登记时的参数进卡肉；clear_temporary_status 会整体清掉。
var _hit_stop_pending: Array = []

# 冻结前保存的速度状态
var _saved_velocity_3d: Vector3 = Vector3.ZERO
var _saved_slide_velocity: Vector2 = Vector2.ZERO
var _saved_knockback_velocity: Vector2 = Vector2.ZERO
var _saved_launch_velocity_z: float = 0.0
var _saved_z_velocity_override: float = 0.0
var _saved_animation_speed: float = 1.0

# ============================================
# 抓取系统
# ============================================

var _immobilize_active: bool = false
var _immobilize_release_active: bool = false
var _immobilize_release_position: Vector3 = Vector3.ZERO
var _immobilize_time: float = -1
var _immobilize_knockback: Vector2 = Vector2.ZERO
var _immobilize_knockback_time: float = 0
var _immobilize_launch: float = 0
var _immobilize_launch_gravity: float = 730
var _immobilize_can_substitute: bool = false  # 定身期间能否替身
var _immobilize_visuals_rotation: float = 0.0  # 定身时 visuals 旋转角度
var _saved_visuals_rotation: float = 0.0        # 定身前保存的 visuals 旋转
var _immobilize_release_ani: String = ""        # 释放时播放的动画；空 = 按原来的 launch1/launch2

# ---- 抓取跟随模式（抓取模式为「跟随位置」时才有值） ----
# 固定位置模式：pos / rpos / 速度都是调用瞬间算好的世界坐标，抓取期间不再变。
# 跟随位置模式：把它们换算成「相对施术者」的偏移，每帧按施术者实时位置与朝向重算。
var _immobilize_follow_caster: EntityBase = null   # 参照实体；null 表示固定位置模式
var _immobilize_follow_pos: Vector3 = Vector3.ZERO     # 相对施术者的偏移，z 正数向上
var _immobilize_follow_rpos: Vector3 = Vector3.ZERO    # 相对施术者的释放点
var _immobilize_follow_kv: Vector2 = Vector2.ZERO      # 面向相对口径的击退速度

# ============================================
# 吸附系统
# ============================================

var _magnetism_time: float = 0
var _magnetism_pos: Vector2 = Vector2.ZERO
var _magnetism_speed: Vector2 = Vector2.ZERO
var _magnetism_state: BodyState = BodyState.SUPER_ARMOR

# 全局吸附追踪（记录当前受哪些全局吸附影响，按名称去重）
var _active_global_mag_names: Array[String] = []

# ============================================
# 自由移动系统
# ============================================

var is_free_moving: bool = false
var _free_move_speed: Vector2 = Vector2.ZERO

# ============================================
# 保护系统
# ============================================

## 保护值作用模式（一个变量即可切换）
enum ProtectionEffect { LAUNCH_SPEED, FALL_SPEED }
## LAUNCH_SPEED(默认)：保护值越高，受击时的击飞初速(zv)越弱，连段中后续击飞越来越矮
## FALL_SPEED(旧行为)：保护值越高，被击飞后下落越快（通过加快落地来断连）
@export_group("保护系统")
@export var protection_effect: ProtectionEffect = ProtectionEffect.LAUNCH_SPEED
@export_group("")
## 击飞初速衰减系数：击飞初速 *= 1 - 该系数 * 保护值（LAUNCH_SPEED 模式下生效）
var launch_protection_decay: float = 0.38

# 公用
var launched_combo_cnt: int = 0
# 保护值
var launched_flag: bool = false
var cumulative_launch_damage: int = 0
# 扫地保护
var OTGp_downed_flag: int = 0
var OTGp_fLaunch_hp: int = 114514
var OTGp_cLaunch_hp: int = 0
var OTGp_threshold_value = 0.2

# 奥义系统
var ultimate_active: bool = false
var ultimate_img_scene: PackedScene = preload("res://scenes/ultra_img_animation.tscn")
# 上次攻击者（用于奥义击杀判定和伤害保护值跳过）
var _last_attacker: EntityBase = null
# 本局累计造成的伤害（用于下一局血量继承）
var total_damage_dealt: int = 0
# 本局是否奥义击杀（用于下一局奥义点+1）
var _ultimate_kill_this_round: bool = false

# ============================================
# 信息点系统
# ============================================
var info_points_data: Array = [] # 存储加载的信息点数据

# ============================================
# 特效绑定系统
# ============================================
var _effect_bindings: Array = [] # 存储加载的特效绑定数据
var _processed_effect_frames: Dictionary = {} # 已处理的特效帧，用于去重（独立于 processed_frames）

# ============================================
# 实体数据
# ============================================

# 定义实体类型枚举
enum EntityType {
	PLAYER,
	ENEMY,
	OBJECT,
	SCROLL,
	SUMMON
}
enum HitStateType {
	PUSH,
	LAUNCH
}
@export var entity_type: EntityType = EntityType.ENEMY
# 攻击服务
var is_attacking: bool = false
var _waiting_for_land: bool = false
var current_attack: String = ""
var attack_configs
# X体管理
enum BodyState {
	NORMAL,       # 什么体都没有
	HARD,         # 硬体
	SUPER_ARMOR,  # 霸体
	KONGO         # 金刚体
}
var body_state := BodyState.NORMAL        # 引擎内部状态
var custom_body_state := BodyState.NORMAL # 自定义状态
var add_body_state := BodyState.NORMAL    # 附加状态
# 无敌
var is_invincible: bool = false :
	set(value):
		is_invincible = value
		_update_hitbox_collision_state()
var custom_invincible: bool = false :
	set(value):
		custom_invincible = value
		_update_hitbox_collision_state()
func _update_hitbox_collision_state():
	if hitbox_areas.is_empty(): return
	var should_disable = get_is_invincible()
	for hitbox in hitbox_areas:
		if not is_instance_valid(hitbox): continue
		if should_disable:
			# 进入无敌状态
			if not hitbox.has_meta("original_state_saved"):
				hitbox.set_meta("original_collision_layer", hitbox.collision_layer)
				hitbox.set_meta("original_collision_mask", hitbox.collision_mask)
				hitbox.set_meta("original_monitoring", hitbox.monitoring)
				hitbox.set_meta("original_monitorable", hitbox.monitorable)
				hitbox.set_meta("original_state_saved", true)
			hitbox.collision_layer = 0
			hitbox.collision_mask = 0
			hitbox.monitoring = false
			hitbox.monitorable = false
			for child in hitbox.get_children():
				if child is CollisionShape2D or child is CollisionPolygon2D:
					child.set_deferred("disabled", true)
		else:
			# 解除无敌状态
			if hitbox.has_meta("original_state_saved"):
				hitbox.collision_layer = hitbox.get_meta("original_collision_layer")
				hitbox.collision_mask = hitbox.get_meta("original_collision_mask")
				hitbox.monitoring = hitbox.get_meta("original_monitoring")
				hitbox.monitorable = hitbox.get_meta("original_monitorable")
				hitbox.remove_meta("original_collision_layer")
				hitbox.remove_meta("original_collision_mask")
				hitbox.remove_meta("original_monitoring")
				hitbox.remove_meta("original_monitorable")
				hitbox.remove_meta("original_state_saved")
			else:
				_configure_hitbox_collision(hitbox)
				hitbox.monitoring = true
				hitbox.monitorable = true
			for child in hitbox.get_children():
				if child is CollisionShape2D or child is CollisionPolygon2D:
					child.set_deferred("disabled", false)
func get_is_invincible():
	return is_invincible or _substitution_invincible or custom_invincible
# 通灵密卷
var can_cast_aux: bool = false
var aux_cd_value: float = 0
var scroll_addon_entity_path: String = ""
## 默认什么都不携带：谁携带由队伍数据决定，EntityManager 生成时按定义填进来。
## 此前这里硬编码着一个密卷与三个通灵，没配过的实体也会凭空带上，训练场那份名单已挪去 MatchConfig。
var scroll_entity_path: String = ""
var summon_entity_path: Array = []
## 密卷与通灵槽位图标取的那张图，目录规则与角色图标一致，见 _refresh_scroll_summon_icons
const PORTRAIT_ICON_FILE := "portraits/icon_idle.png"
## 密卷槽位与通灵槽位在 skill_slot 里的下标，与 _real_skill_slots 的装配一致
const SLOT_SCROLL := 5
const SLOT_SUMMON := 6
# 杂项
var substitution_distance: float = 0
var enable_wall_collision: bool = true
var _last_valid_wall_pos: Vector2 = Vector2.ZERO
var move_intent: Vector2 = Vector2.ZERO
var is_dead: bool = false
var out_wall_mode = OutWallMode.RETURN
enum OutWallMode {
	CALCULATE,
	RETURN
}
var load_done: bool = false
# 预输入
enum ActionPriority {  # 按钮优先级
	SUBSTITUTION=0,   # 替身
	NORMAL_ATTACK=1,  # 普攻
	SKILL=2,          # 技能
	ULTIMATE=3,        # 奥义
	SCROLL=4,         # 秘卷
	SUMMON=4         # 通灵
}
@export var buffer_max_size: int = 3
## 预输入窗口长度，单位【秒】。用秒而不是物理帧数：物理帧率可配（30/60），
## 按帧数计的窗口在 30Hz 下会翻倍成 400 毫秒，预输入会变得过分宽容。
@export var buffer_valid_seconds: float = 0.2
var _input_buffer: Array[Dictionary] = []
## 预输入缓冲的两把尺子，都只在"实体能动的帧"里走，所以停帧与卡肉期间缓冲不流逝：
##   停帧：场景树暂停（get_tree().paused）。被暂停的实体连 _physics_process 都不跑，
##         能跑的实体靠这行判断，避免"停帧把别人攒下的预输入烧掉"。
##   卡肉：_hit_stop_active。卡肉期间 _physics_process 照跑，必须显式不加。
## _buffer_time 是超时判据（秒，物理帧率改了窗口也不变），_buffer_clock 只在同一帧内排序用。
var _buffer_clock: int = 0
var _buffer_time: float = 0.0
var _current_action_priority: int = ActionPriority.NORMAL_ATTACK
var _is_executing_action: bool = false
func _get_action_priority(action: String) -> int:
	match action:
		"substitution":
			return ActionPriority.SUBSTITUTION
		"attack":
			return ActionPriority.NORMAL_ATTACK
		"skill1", "skill2", "sub_skill1", "sub_skill2":
			return ActionPriority.SKILL
		"scroll":
			return ActionPriority.SCROLL
		"summon":
			return ActionPriority.SUMMON
		"skill3":
			return ActionPriority.ULTIMATE
		_:
			return ActionPriority.NORMAL_ATTACK

# ============================================
# 替身无敌系统（独立计时）也可以叫起身无敌
# ============================================

var _substitution_invincible: bool = false      # 替身无敌状态（独立）
var _substitution_timer: float = 0.0            # 替身无敌计时器
var _substitution_duration: float = 1.0         # 替身无敌持续时间（可配置）

signal substitution_invincibility_started(duration: float)
signal substitution_invincibility_ended

# 设置替身无敌时间（单位：秒）
func set_substitution_invincibility(duration: float = -1.0):
	"""触发替身无敌，-1表示使用默认值"""
	if duration < 0:
		duration = _substitution_duration
	
	_substitution_invincible = true
	_substitution_timer = duration
	
	_update_hitbox_collision_state()  # 立即更新碰撞状态
	
	substitution_invincibility_started.emit(duration)
	
	if debug_team:
		print("[替身无敌] %s 开启，持续 %.2f 秒" % [name, duration])

func stop_substitution_invincibility():
	"""提前结束替身无敌"""
	if _substitution_invincible:
		_substitution_invincible = false
		_substitution_timer = 0.0
		_update_hitbox_collision_state()
		substitution_invincibility_ended.emit()
		
		if debug_team:
			print("[替身无敌] %s 提前结束" % name)

func is_substitution_invincible() -> bool:
	return _substitution_invincible

# ============================================
# 输入系统
# ============================================

var input_left: bool = false
var input_right: bool = false
var input_up: bool = false
var input_down: bool = false
var inputs: Array[bool] = []

# ============================================
# 攻击框系统
# ============================================

var attack_box_manager: AttackBoxManager = null

# ============================================
# 调试可视化系统
# ============================================

var _debug_canvas_layer: CanvasLayer = null
var _debug_draw_node: Control = null
var _debug_attack_box_visuals: Dictionary = {}  # box_id -> Control
var _debug_hitbox_visuals: Dictionary = {}  # area -> Control

# ============================================
# 实体信息
# ============================================

var title: String = "名称加载失败"
var hp_max: int = 1919810
var hp: int = 114514
var custom_entry_anim_name: String = ""
var custom_entry_extra_pos3d: Vector3 = Vector3.ZERO
var entry_pos3d: Vector3 = Vector3.ZERO
var ultimate_point: int = 2
var ultimate_point_max: int = 4
var cool_down_time: Array[Dictionary] = []
var skill_timer: Array[Dictionary] = []
var modifiers: Array[Dictionary] = []

# 加成池：可堆叠数值加成（atk/speed/def），每帧重算最终加成
var bonus_pool: Array[Dictionary] = []
var final_atk: float = 1.0
var final_speed: float = 1.0
var final_def: float = 1.0
var _bonus_next_id: int = 1
# 状态池：自定义状态标记，可堆叠，供图形化脚本查询
var state_pool: Array[Dictionary] = []
var _state_next_id: int = 1
enum EntryAction {
	NONE,
	DEFAULT,
	CUSTOM
}
var entry_action: EntryAction = EntryAction.NONE
var _entry_target_x: float = 0.0    # 记录预设的落地 X 坐标
var _entry_fall_speed_x: float = 0.0 # 掉落时的水平初速度
var is_player: bool = false
var parent_entity: EntityBase = null

# ============================================
# AI系统
# ============================================
var is_ai_controlled: bool = false
var _ai_controller: Node = null # 挂载的 AI 控制器节点

# 虚拟输入字典 (模拟手柄按键)
var _virtual_inputs: Dictionary = {
	"move_left": false,
	"move_right": false,
	"move_up": false,
	"move_down": false,
	"buttons": [false, false, false, false, false, false, false, false, false] # 对应9个技能槽
}

# AI 按键上一帧的电平，用于检测上升沿（按下瞬间）
# 目的：让 AI 的每一次「按键」都走与真实输入相同的门控 handle_button_press()，
#       而不是仅靠电平注入绕过优先级判定与输入缓冲。
var _ai_prev_buttons: Array = [false, false, false, false, false, false, false, false, false]

# 供 AI 控制器调用的公开接口
func set_virtual_input(action: String, pressed: bool) -> void:
	if action in _virtual_inputs:
		_virtual_inputs[action] = pressed
	elif action.begins_with("button_"):
		var idx = int(action.split("_")[1])
		if idx >= 0 and idx < 9:
			_virtual_inputs.buttons[idx] = pressed

func clear_virtual_inputs() -> void:
	for key in _virtual_inputs:
		if key == "buttons":
			for i in range(9):
				_virtual_inputs.buttons[i] = false
		else:
			_virtual_inputs[key] = false
	# 同步重置上升沿基线。
	# 原因：AI 每次决策前都会先 clear 再 _decide_action()，两步在同一次调用内完成，
	# 而 _entity_input() 每物理帧只采样一次，永远观察不到中间那个 false 状态。
	# 不在这里清基线，按键的上升沿就几乎永远检不出来（统一门控形同虚设）。
	for i in range(_ai_prev_buttons.size()):
		_ai_prev_buttons[i] = false

# ============================================
# 初始化
# ============================================

var enable_keyboard_input: bool = false
func _ready():
	# 调试总开关：print 类开关按总开关压一次，绘制类在每次绘制时现查，见 _apply_debug_master_switch
	_apply_debug_master_switch()
	if not MatchConfig.debug_enabled_changed.is_connected(_on_match_debug_enabled_changed):
		MatchConfig.debug_enabled_changed.connect(_on_match_debug_enabled_changed)
	
	enable_keyboard_input = OS.has_feature("windows") or OS.has_feature("editor")
	# 键盘上升沿靠 _input 截获，见 KEYBOARD_ACTIONS 上方的注释
	set_process_input(enable_keyboard_input)
	
	camera = _get_duel_camera()
	
	if ResourceLoader.exists(res_path):
		var forced = load(res_path)
		if forced:
			entity_data = forced
	
	is_player = is_player_with_number(name)
	title = entity_data.entity_name
	hp_max = entity_data.max_health
	hp = hp_max
	# 继承上一局血量
	if name == "Player1" and MatchConfig.p1_carry_hp >= 0:
		hp = MatchConfig.p1_carry_hp
		hp_max = MatchConfig.p1_carry_hp_max
	elif name == "Player2" and MatchConfig.p2_carry_hp >= 0:
		hp = MatchConfig.p2_carry_hp
		hp_max = MatchConfig.p2_carry_hp_max
	# 继承上一局奥义点
	if name == "Player1" and MatchConfig.p1_carry_ultimate >= 0:
		ultimate_point = MatchConfig.p1_carry_ultimate
	elif name == "Player2" and MatchConfig.p2_carry_ultimate >= 0:
		ultimate_point = MatchConfig.p2_carry_ultimate
	# 血量不能超过上限
	if hp > hp_max:
		hp = hp_max
	substitution_distance = entity_data.substitution_distance
	custom_entry_anim_name = entity_data.custom_entry
	if custom_entry_anim_name:
		custom_entry_extra_pos3d = entity_data.custom_entry_extra_pos3d
		custom_entry_extra_pos3d.x *= facing_direction
		entry_action = EntryAction.CUSTOM
	
	var entities_container = get_parent()
	if entities_container: main = entities_container.get_parent()
	if main: effects_container = main.get_node("Effects")
	
	_init_3d_position()
	_setup_slide_sequences()
	_setup_components()

	if is_player:
		if name == "Player1":
			aura_node.play("own")
		elif name == "Player2":
			aura_node.play("ene")
	shadow_node.visible = true

	effects_container.register_effects({
		"scroll": preload("res://assets/entities/base/effects/scroll/effects_base.tscn"),
		"summon": preload("res://assets/entities/base/effects/summon/effects_base.tscn"),
		"Afterimage": preload("res://assets/entities/base/effects/afterimage/effects_base.tscn"),
		"CancelWhite": preload("res://assets/entities/base/effects/cancel_white/effects_base.tscn"),
		"hurt_num_sw": preload("res://assets/entities/base/effects/hurt/own/w.tscn"),
		"hurt_num_sg": preload("res://assets/entities/base/effects/hurt/own/g.tscn"),
		"hurt_num_sw_ene": preload("res://assets/entities/base/effects/hurt/ene/w.tscn"),
		"hurt_num_sg_ene": preload("res://assets/entities/base/effects/hurt/ene/g.tscn")
	})
	
	# 预热伤害数字图集缓存，避免首次生成时卡顿
	DigitDisplay.prewarm(preload("res://assets/UI/number/hurtsw.png"), "0123456789  ", 6, 2)
	DigitDisplay.prewarm(preload("res://assets/UI/number/hurtsg.png"), "0123456789  ", 6, 2)
	DigitDisplay.prewarm(preload("res://assets/UI/number/hurtew.png"), "0123456789  ", 6, 2)
	DigitDisplay.prewarm(preload("res://assets/UI/number/hurteg.png"), "0123456789  ", 6, 2)

	MatchConfig.controller_changed.connect(_on_controller_changed)
	call_deferred("_deferred_heavy_init")

func _deferred_heavy_init():
	# 第1帧：UI 设置 + 帧数据 + 受击框 + 信号
	fight_ui = get_parent().get_parent().get_parent().get_node_or_null("FightUI")
	info_animation_player = fight_ui.get_node_or_null("Info/AnimationPlayer")
	info_label = fight_ui.get_node_or_null("Info/Label")
	if is_player:
		info_bar = fight_ui.get_node_or_null("P"+str(name)[6]+"_Info")
		hp_bar = info_bar.get_node_or_null("HpBar")
		hp_red = hp_bar.get_node_or_null("HpRed")
		energy_bar = hp_bar.get_node_or_null("EnergyBar")
		ultimate_panel = info_bar.get_node_or_null("UltimatePanel")
		title_label = info_bar.get_node_or_null("Title")
		protections = info_bar.get_node_or_null("Protections")
		
		hp_red.max_value = hp_max
		hp_red.value = hp
		title_label.text = title
		
		skill_panel = main.get_parent().get_node("SkillPanel")
		var skill_slots = skill_panel.get_node("PanelContainer").get_node("TextureRect")
		_real_skill_slots.resize(9)
		_real_skill_slots[0] = skill_slots.get_node("Attack")
		_real_skill_slots[1] = skill_slots.get_node("Skill1")
		_real_skill_slots[2] = skill_slots.get_node("Skill2")
		_real_skill_slots[3] = skill_slots.get_node("Skill3")
		_real_skill_slots[4] = skill_slots.get_node("Substitution")
		_real_skill_slots[5] = skill_slots.get_node("Scroll")
		_real_skill_slots[6] = skill_slots.get_node("Summon")
		_real_skill_slots[7] = skill_slots.get_node("SubSkill1")
		_real_skill_slots[8] = skill_slots.get_node("SubSkill2")
		
		_real_skill_slots[7].visible = false
		_real_skill_slots[8].visible = false
		
		virtual_joystick = skill_panel.get_node("VirtualJoystick")
	
	# 输入、冷却与计时三张表按 9 个槽位建立，与有没有面板无关。
	# 这段此前在 if is_player 里面，而子实体的名字不是 PlayerN，三张表全是空的：
	# set_timer 与 set_cd 会写越界并被静默丢弃，计时结束事件永远不触发。
	# 负数 slot_id 的计时恰恰是子实体在用的那种（它没有面板可显示），
	# 所以这个缺陷表现为「负数槽位计时不能触发计时结束事件」。
	inputs.resize(9)
	for i in range(9):
		cool_down_time.append({"time": 0.0, "slot_id": 0})
		skill_timer.append({"time": 0.0, "max_time": 0, "slot_id": 0, "sub_slots": []})
	
	_sync_skill_slot_binding()
	_update_summon_dot()
	
	if entity_type == EntityType.PLAYER:
		setup_player_config()
		
	_ready_ultimate_point()
	
	if not get_animator_node():
		push_error("EntityBase: 初始化失败，缺少AnimatedSprite2D")
		return
		
	_load_frame_data() 
	_setup_hitboxes()
	_connect_signals()
	
	_deferred_team_setup()
	
	if enable_depth_sort:
		_register_depth_sort()
		_update_initial_depth()
		
	attack_box_manager = AttackBoxManager.new(self)
	add_child(attack_box_manager)
	
	# 第2帧：加载攻击框 + 信息点数据
	call_deferred("_deferred_heavy_init_phase2")

func _deferred_heavy_init_phase2():
	_load_attack_box_data()
	_load_info_points()
	
	# 第3帧：加载特效绑定 + 其余初始化
	call_deferred("_deferred_heavy_init_phase3")

func _deferred_heavy_init_phase3():
	_load_effect_bindings()
	
	_setup_debug_system()
	load_done = true
	_post_init()
	
	# 处理 CD 和附属物生成
	if entity_type == EntityType.SCROLL:
		parent_entity.set_cd(5, 5, aux_cd_value)
	elif entity_type == EntityType.SUMMON:
		parent_entity.set_cd(6, 6, aux_cd_value)
	
	call_deferred("_deferred_heavy_init_phase4")

func _deferred_heavy_init_phase4():
	if info_bar:
		set_energy_bar_visible(false)
	
	if scroll_addon_entity_path == "": return
	var cfg = EntityManager.EntityConfig.new(
		name + "_密卷附加" + str(Engine.get_frames_drawn()),
		scroll_addon_entity_path,
		get_2d_pos(),
		team_id,
		facing_direction,
		EntityType.SCROLL,
		self
	)
	var ee = entity_manager.spawn_entity_runtime(cfg)
	if ee:
		ee.parent_entity = self

func load_on_not_empty(path: String):
	if path != "":
		return load(path)
	return null

func is_player_with_number(text: String) -> bool:
	if not text.begins_with("Player"):
		return false
	
	var suffix = text.substr(6)
	
	if suffix.is_valid_int():
		return true
	
	return false

func _post_init():
	_begin_entry()

# ============================================
# 入场状态（进场 / entry）
# ============================================

## 结算当前 entry_action 对应的入场流程。_post_init 与图形化脚本的动作块共用这一条路径。
## 注意：DEFAULT 分支会把实体挪到场外高处，落点记在 _entry_target_x；
## CUSTOM 分支把原位记在 entry_pos3d，两者都是退出入场时归位的依据。
func _begin_entry():
	if entry_action == EntryAction.DEFAULT:
		if can_play_animation("entry"):
			play_animation("entry")
	
			_entry_target_x = position_3d.x
			
			position_3d.x -= 580 * facing_direction
			position_3d.z = 600 
			
			_entry_fall_speed_x = 600.0 * facing_direction
			
			apply_z_impulse(0)
			set_slide_gravity(730)
		else:
			play_animation("idle")
			entry_action = EntryAction.NONE
			_on_entry_end()
	elif entry_action == EntryAction.CUSTOM:
		entry_pos3d = position_3d
		teleport_to_position(position_3d + custom_entry_extra_pos3d)
		play_animation(custom_entry_anim_name)

## 设置入场状态。图形化脚本与角色脚本的统一入口。
## mode = NONE 时等价于 cancel_entry()。
## mode = DEFAULT / CUSTOM 时会先结束当前入场再按新方式重新入场，
## 这样落点不会在半空中被重算（entry_action 已经是所选模式时也是重新入场）。
## anim_name 与 extra_pos3d 只在 CUSTOM 下生效，留空与零向量时沿用 EntityData 的配置。
## extra_pos3d 与 EntityData.custom_entry_extra_pos3d 同口径，按朝向镜像。
func set_entry_state(mode: EntryAction, anim_name: String = "", extra_pos3d: Vector3 = Vector3.ZERO) -> void:
	if mode == EntryAction.NONE:
		cancel_entry()
		return
	if mode == EntryAction.CUSTOM:
		if anim_name != "":
			custom_entry_anim_name = anim_name
		if custom_entry_anim_name == "":
			push_warning("set_entry_state: CUSTOM 入场缺少动画名，本次忽略（%s）" % name)
			return
		if extra_pos3d != Vector3.ZERO:
			custom_entry_extra_pos3d = extra_pos3d
			custom_entry_extra_pos3d.x *= facing_direction
	# 已在入场中：先归位，避免在半空中重算落点
	if entry_action != EntryAction.NONE:
		_settle_entry(false)
	entry_action = mode
	_begin_entry()

## 取消入场：归位到落点并转入 idle，等价于"入场正常结束"的收尾流程。
## 入场已结束时不做事，可安全重复调用。
## 注意：本方法是"事后归位"，DEFAULT 入场在 _post_init 里已经先把实体挪到场外高处，
## 所以若调用发生在入场开始后的某一帧，那一帧仍可能在场外画出实体。
## 图形化脚本的 when_entity_create 与 _post_init 同帧触发，正常用法下不会看到这一帧。
func cancel_entry() -> void:
	if entry_action == EntryAction.NONE:
		return
	_settle_entry(true)

## 把入场中的实体归位到落点并清掉入场状态。
## play_idle 为 true 时接 idle 并回调 _on_entry_end，即入场正常结束；
## 为 false 时只归位，供紧接着重新入场用（此时不回调 _on_entry_end）。
func _settle_entry(play_idle: bool) -> void:
	match entry_action:
		EntryAction.DEFAULT:
			# 默认入场是"从场外高处坠入"，落点 X 记在 _entry_target_x
			position_3d.x = _entry_target_x
			_entry_fall_speed_x = 0.0
			stop_slide()
			stop_z_motion(true, true)
		EntryAction.CUSTOM:
			# 自定义入场是"按偏移瞬移出去"，原位记在 entry_pos3d
			position_3d = entry_pos3d
			stop_slide()
			stop_z_motion(true, true)
	entry_action = EntryAction.NONE
	position_3d.z = ground_level
	is_grounded = true
	_update_visual_position()
	if play_idle:
		clear_temporary_status()
		play_animation("idle")
		_on_entry_end()

func die():
	# 1. 停止所有物理运动
	velocity_3d = Vector3.ZERO
	velocity = Vector2.ZERO
	slide_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_launch_velocity_z = 0.0
	is_sliding = false
	_launch_active = false
	_slide_z_resistance = -1.0

	# 2. 禁用碰撞 【修改点】使用 set_deferred 避免在物理帧中报错
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	
	# 禁用受击框
	for hitbox in hitbox_areas:
		if is_instance_valid(hitbox):
			hitbox.set_deferred("monitorable", false)
			hitbox.set_deferred("monitoring", false)

	# 3. 通知管理器移除
	if entity_manager and is_instance_valid(entity_manager):
		entity_manager.remove_entity(name)
	else:
		if debug_team: print("[死亡] %s (无管理器) 直接移除" % name)
		queue_free()

func _trigger_ultimate_kill_effect():
	"""奥义击杀时：时停3s + 居中播放奥义图，3s后移除并恢复"""
	if _last_attacker:
		_last_attacker._ultimate_kill_this_round = true
	var arena = get_tree().current_scene
	if not arena or not arena.has_node("UltraImage"):
		return
	if not _last_attacker or not _last_attacker.ultimate_img_scene:
		return

	var ultra = arena.get_node("UltraImage")
	var img = _last_attacker.ultimate_img_scene.instantiate()
	ultra.add_child(img)

	# 居中 + 启动奥义图
	var viewport_size = get_viewport().get_visible_rect().size
	img.position = viewport_size / 2
	if img.has_method("play"):
		img.play()

	# 静音音乐通道
	var music_bus_idx = AudioServer.get_bus_index("Music")
	var saved_music_vol = AudioServer.get_bus_volume_db(music_bus_idx)
	AudioServer.set_bus_volume_db(music_bus_idx, -80.0)

	# 时停
	Engine.time_scale = 0.0

	# 用单个 Tween（忽略时间缩放）同时处理动画推进 + 3s后清理
	var t = create_tween().set_ignore_time_scale(true)
	t.set_parallel(true)

	# 手动推进奥义动画
	var ap = img.get_node("AnimationPlayer")
	if ap:
		var anim = ap.get_animation("Normal")
		if anim:
			t.tween_method(func(pos): ap.seek(pos, true), 0.0, anim.length, minf(anim.length, 3.0))

	# 3s后移除并恢复
	t.tween_callback(func():
		if is_instance_valid(img):
			img.queue_free()
		if not arena.is_queued_for_deletion():
			AudioServer.set_bus_volume_db(music_bus_idx, saved_music_vol)
			Engine.time_scale = 1.0
	).set_delay(3.0)

func _load_info_points():
	"""从 JSON 读取信息点编辑器生成的数据"""
	if res_path == "": return
	var data_path = res_path.get_base_dir() + "/info_points.json"
	if not FileAccess.file_exists(data_path): return
	
	var file = FileAccess.open(data_path, FileAccess.READ)
	if not file: return
	
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		if data is Dictionary and data.has("points"):
			info_points_data = data["points"]
			print("[信息点] 已加载 %d 个信息点" % info_points_data.size())
	file.close()

func _load_effect_bindings():
	"""从 JSON 读取特效绑定编辑器生成的数据"""
	if res_path == "": return
	var data_path = res_path.get_base_dir() + "/effect_bindings.json"
	if not FileAccess.file_exists(data_path): return
	
	var file = FileAccess.open(data_path, FileAccess.READ)
	if not file: return
	
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		if data is Dictionary and data.has("bindings"):
			_effect_bindings = data["bindings"]
			print("[特效绑定] 已加载 %d 个特效绑定" % _effect_bindings.size())
			_register_pooled_bindings()
	file.close()

func _register_pooled_bindings():
	"""预注册池化特效绑定，开场由 init_pooled_effects() 实例化"""
	if not effects_container:
		return
	for binding in _effect_bindings:
		if not binding.get("pooled", false):
			continue
		var scene_path = binding.get("scene_path", "")
		var effect_name = binding.get("effect_name", "")
		var pool_size = binding.get("pool_size", 1)
		if scene_path != "":
			var scene = load(scene_path)
			if scene:
				var reg_name = "_efb_" + binding.get("id", "tmp")
				effects_container.register_pooled_effect(reg_name, scene, pool_size)
		elif effect_name != "":
			# 已通过 entity.gd register_effects 注册，需升级为池化
			var scene = effects_container._effect_scenes.get(effect_name)
			if scene and not effects_container._pooled_scenes.has(effect_name):
				effects_container.register_pooled_effect(effect_name, scene, pool_size)

func _sync_skill_slot_binding():
	"""根据当前操控者切换 skill_slot 绑定：操控者用真实 SkillPanel，其它用 NullSlot"""
	skill_slot.resize(_real_skill_slots.size())
	skill_slot.fill(NullSlot.new())
	if _real_skill_slots.size() > 0 and name == MatchConfig.current_controller_name:
		for i in _real_skill_slots.size():
			skill_slot[i] = _real_skill_slots[i]
		_push_slot_state_to_panel()

func _push_slot_state_to_panel():
	"""接管真实面板时，把实体自己的 CD、计时与点数推回面板。
	面板在非操控期间收不到 set_cd 与 _process_cd 的写入，会停在交接瞬间的旧值。
	若某个 CD 在离开期间走完，面板就永久停在正数上，该槽位再也按不动 —— 交接回来即死锁。"""
	for i in cool_down_time.size():
		var cd_sid: int = int(cool_down_time[i]["slot_id"])
		if cd_sid >= 0 and cd_sid < skill_slot.size():
			skill_slot[cd_sid].cool_down_time_now = cool_down_time[i]["time"]
	for i in skill_timer.size():
		var t_sid: int = int(skill_timer[i]["slot_id"])
		var t_max: float = float(skill_timer[i]["max_time"])
		var progress: float = (float(skill_timer[i]["time"]) / t_max) if t_max > 0.0 else 0.0
		if t_sid >= 0 and t_sid < skill_slot.size():
			skill_slot[t_sid].timer_progress = progress
		for sub in skill_timer[i].get("sub_slots", []):
			var sub_sid: int = int(sub)
			if sub_sid >= 0 and sub_sid < skill_slot.size():
				skill_slot[sub_sid].timer_progress = progress
	_process_ultimate_point()
	_update_summon_dot()
	_refresh_scroll_summon_icons()

func setup_player_config():
	setup_icon()
	# 图标与角色技能图标同一个入口。面板绑定可能晚于 _ready（操控者名字是生成后才写的），
	# 那条路由 _on_controller_changed 再进来一次，两边都调一次才不漏。
	_refresh_scroll_summon_icons()

func _on_controller_changed(new_name: String):
	if is_player:
		_sync_skill_slot_binding()
	if name == new_name:
		setup_player_config()

func setup_icon():
	pass

func _ready_ultimate_point():
	match entity_type:
		EntityType.PLAYER:
			skill_slot[4].dot = ultimate_point
			skill_slot[4].dot_max = 4
	
	_process_ultimate_point()

func _get_duel_camera() -> DuelCamera:
	"""获取相机引用：实体 -> 父节点(Entities) -> 父节点(Main) -> 父节点(Arena) -> Camera2D"""
	
	arena = get_parent().get_parent().get_parent()  # Arena
	if not arena:
		return null
	
	# 假设相机直接在Arena下，或在某个子节点中
	for child in arena.get_children():
		if child is DuelCamera:
			return child
		# 递归查找
		var found = _find_camera_recursive(child)
		if found:
			return found
	
	return null

func _find_camera_recursive(node: Node) -> DuelCamera:
	if node is DuelCamera:
		return node
	for child in node.get_children():
		var found = _find_camera_recursive(child)
		if found:
			return found
	return null

func _ensure_debug_system():
	"""按需创建调试系统，避免不必要的节点开销"""
	if not MatchConfig.debug_enabled:
		return
	if _debug_canvas_layer:
		return
	_debug_canvas_layer = CanvasLayer.new()
	_debug_canvas_layer.name = "DebugCanvasLayer"
	_debug_canvas_layer.layer = 100
	add_child(_debug_canvas_layer)
	
	_debug_draw_node = Control.new()
	_debug_draw_node.name = "DebugDrawNode"
	_debug_draw_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_canvas_layer.add_child(_debug_draw_node)
	
	if not _debug_draw_node.draw.is_connected(_on_draw_all_debug):
		_debug_draw_node.draw.connect(_on_draw_all_debug)
	
	set_process(true)

func _setup_debug_system():
	# 仅在总开关开启且开启了任意调试开关时才创建调试节点
	if not MatchConfig.debug_enabled:
		return
	if debug_show_hitboxes or debug_show_attack_boxes or debug_show_info_points:
		_ensure_debug_system()

# ============================================
# 调试总开关（MatchConfig.debug_enabled）
# ============================================

## 总开关关闭时被压掉的 print 类开关的原值，重新打开时原样恢复。
var _debug_print_flags_saved: Dictionary = {}
var _debug_print_flags_muted: bool = false

## 总开关关闭时压掉 print 类开关，避免发布包刷日志；重新打开时把原值放回去。
## 绘制类开关不在这里压：它们每次绘制都现查总开关，所以运行中开关总开关都立刻生效。
func _apply_debug_master_switch():
	if MatchConfig.debug_enabled:
		if not _debug_print_flags_muted:
			return
		_debug_print_flags_muted = false
		debug_anchor = _debug_print_flags_saved.get("debug_anchor", debug_anchor)
		debug_slide = _debug_print_flags_saved.get("debug_slide", debug_slide)
		debug_z_axis = _debug_print_flags_saved.get("debug_z_axis", debug_z_axis)
		debug_team = _debug_print_flags_saved.get("debug_team", debug_team)
		debug_frame_pipeline = _debug_print_flags_saved.get("debug_frame_pipeline", debug_frame_pipeline)
		debug_state_stack = _debug_print_flags_saved.get("debug_state_stack", debug_state_stack)
		_debug_print_flags_saved.clear()
		return
	
	if _debug_print_flags_muted:
		return
	_debug_print_flags_muted = true
	_debug_print_flags_saved = {
		"debug_anchor": debug_anchor,
		"debug_slide": debug_slide,
		"debug_z_axis": debug_z_axis,
		"debug_team": debug_team,
		"debug_frame_pipeline": debug_frame_pipeline,
		"debug_state_stack": debug_state_stack,
	}
	debug_anchor = false
	debug_slide = false
	debug_z_axis = false
	debug_team = false
	debug_frame_pipeline = false
	debug_state_stack = false

func _on_match_debug_enabled_changed(_enabled: bool) -> void:
	_apply_debug_master_switch()
	_update_debug_visuals()

func _on_draw_all_debug():
	# 总开关关闭时整帧都不画，绘制内容自然被清空
	if not MatchConfig.debug_enabled:
		return
	
	# 1. 绘制信息点 (保持原有逻辑)
	if debug_show_info_points:
		_on_debug_draw_info_points()
	
	# 2. 绘制碰撞箱
	if debug_show_hitboxes:
		_draw_hitboxes_batch()
	
	# 3. 绘制攻击框
	if debug_show_attack_boxes:
		_draw_attack_boxes_batch()

func _draw_attack_boxes_batch():
	if not is_instance_valid(_debug_draw_node) or not attack_box_manager: return
	
	# 动画帧驱动的攻击框
	for box_id in attack_box_manager._active_boxes.keys():
		_draw_attack_box_entry(attack_box_manager._active_boxes[box_id], "")
	
	# 图形化脚本创建的动态攻击框。它们存在另一张表里（_dynamic_boxes），
	# 不受动画帧驱动，此前只遍历 _active_boxes 导致这批量完全不绘制。
	for box_id in attack_box_manager._dynamic_boxes.keys():
		_draw_attack_box_entry(attack_box_manager._dynamic_boxes[box_id], "动态:")

## 绘制单个攻击框。_active_boxes 与 _dynamic_boxes 的条目结构一致
## （node / instance_key / config / box_data），所以两者共用本函数。
## label_prefix 用于区分来源，动态框传 "动态:"。
func _draw_attack_box_entry(data: Dictionary, label_prefix: String = ""):
	var node = data.get("node") as Area2D
	if not is_instance_valid(node): return
	var config = data.get("config") as AttackBoxData.FrameConfig
	if not config: return
	var box_data = data.get("box_data") as AttackBoxData
	if not box_data: return
	
	# --- 1. 获取逻辑坐标 (已经剥离了深度) ---
	var logic_global_pos = node.global_position
	
	# --- 2. 计算视觉坐标 (加回深度 position_3d.y) ---
	# 2D 判定平面不含深度，显示时要加回深度才落进视觉平面。
	# 脱手框有自己冻结的深度，必须用它的：用绘制者当前的深度会让框在画面上跟着人走。
	var box_depth: float = float(data.get("detached_y", NAN))
	if is_nan(box_depth):
		box_depth = position_3d.y
	var visual_global_pos = Vector2(logic_global_pos.x, logic_global_pos.y + box_depth)
	
	# --- 3. 转换为屏幕视口坐标 ---
	var viewport_pos = get_viewport().canvas_transform * visual_global_pos
	
	# --- 4. 获取形状尺寸 ---
	var shape_node = node.get_child(0) as CollisionShape2D
	if not shape_node or not shape_node.shape: return
	
	var shape_size = Vector2.ZERO
	if shape_node.shape is RectangleShape2D:
		shape_size = shape_node.shape.size * node.global_scale.abs()
	
	# --- 5. 绘制形状与文字 ---
	var rect = Rect2(viewport_pos - shape_size / 2.0, shape_size)
	
	# 填充
	_debug_draw_node.draw_rect(rect, Color(debug_attack_box_color, debug_box_fill_alpha))
	
	# 边框
	_draw_rect_border(rect, debug_attack_box_color, debug_box_line_width)
	
	# 文字
	var trigger_mark = "✓" if box_data.has_triggered_instance(data.get("instance_key", "")) else "○"
	var z_text = ""
	if debug_show_z_depth:
		z_text = "\nZ:%.0f(±%.0f) | D:%.0f" % [config.position.z, config.size.z/2, config.size.y]
		# 脱手框：深度是创建瞬间冻结的绝对值，跟实体当前位置无关，画出来方便核对
		var detached_y: float = float(data.get("detached_y", NAN))
		if not is_nan(detached_y):
			z_text += " | 脱手Y:%.0f" % detached_y
	var text = "%s%s [%s]%s" % [label_prefix, box_data.box_name, trigger_mark, z_text]
	
	var font = ThemeDB.fallback_font
	var text_pos = viewport_pos + Vector2(0, -50 if debug_show_z_depth else -20)
	
	# 文字背景
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	_debug_draw_node.draw_rect(Rect2(text_pos - Vector2(2, 12), text_size + Vector2(4, 4)), Color(0, 0, 0, 0.5))
	
	_debug_draw_node.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, debug_attack_box_color)
	
	# Z轴深度指示器
	if debug_show_z_depth:
		var z_ratio = clamp(config.size.z / 200.0, 0.1, 1.0)
		var ind_h = shape_size.y * z_ratio
		var ind_w = 4.0
		# 注意：指示器位置也要基于 viewport_pos
		var ind_pos = Vector2(rect.position.x + rect.size.x + 2, rect.position.y + (shape_size.y - ind_h) / 2.0)
		_debug_draw_node.draw_rect(Rect2(ind_pos, Vector2(ind_w, ind_h)), Color.CYAN)

func _draw_rect_border(rect: Rect2, color: Color, width: float):
	var tl = rect.position
	var tr = rect.position + Vector2(rect.size.x, 0)
	var br = rect.position + rect.size
	var bl = rect.position + Vector2(0, rect.size.y)
	
	# 绘制四条线
	_debug_draw_node.draw_line(tl, tr, color, width)
	_debug_draw_node.draw_line(tr, br, color, width)
	_debug_draw_node.draw_line(br, bl, color, width)
	_debug_draw_node.draw_line(bl, tl, color, width)

func _draw_hitboxes_batch():
	if not is_instance_valid(_debug_draw_node): return
	
	for i in range(hitbox_areas.size()):
		var area = hitbox_areas[i]
		if not is_instance_valid(area): continue
		
		# 检查帧数据可见性，隐藏的碰撞箱不绘制debug渲染
		if current_frame_data and i < current_frame_data.hitboxes_data.size():
			var is_visible = current_frame_data.hitboxes_data[i].get("visible", true)
			if not is_visible:
				continue
		
		# --- 1. 获取逻辑坐标 (已经剥离了深度) ---
		var logic_global_pos = area.global_position
		
		# --- 2. 计算视觉坐标 (加回深度 position_3d.y) ---
		# position_3d.y 是角色的前后深度，加回它，碰撞框就会跟随角色上下移动
		var visual_global_pos = Vector2(logic_global_pos.x, logic_global_pos.y + position_3d.y)
		
		# --- 3. 转换为屏幕视口坐标 ---
		var viewport_pos = get_viewport().canvas_transform * visual_global_pos
		
		# --- 4. 获取形状尺寸 ---
		var shape_node = area.get_child(0) as CollisionShape2D
		if not shape_node or not shape_node.shape: continue
		
		var shape_size = Vector2.ZERO
		if shape_node.shape is RectangleShape2D:
			shape_size = shape_node.shape.size * area.global_scale.abs()
		elif shape_node.shape is CircleShape2D:
			var r = shape_node.shape.radius * abs(area.global_scale.x)
			shape_size = Vector2(r * 2, r * 2)
		
		# --- 5. 绘制形状与文字 ---
		var rect = Rect2(viewport_pos - shape_size / 2.0, shape_size)
		
		# 填充
		_debug_draw_node.draw_rect(rect, Color(debug_hitbox_color, debug_box_fill_alpha))
		
		# 边框
		_draw_rect_border(rect, debug_hitbox_color, debug_box_line_width)
		
		# 文字
		var z_info = ""
		if current_frame_data and i < current_frame_data.hitboxes_data.size():
			var h_data = current_frame_data.hitboxes_data[i]
			var z_off = h_data.get("z_offset", 0.0)
			var z_h = h_data.get("z_height", 50.0)
			var act_z = position_3d.z + z_off
			var y_d = h_data.get("y_depth", h_data.get("z_height", 50.0))
			z_info = "\nZ:%.0f(±%.0f) | D:%.0f" % [act_z, z_h/2, y_d]
		
		var text = "受击%d%s" % [i, z_info]
		var font = ThemeDB.fallback_font
		var text_pos = viewport_pos + Vector2(0, -35)
		
		# 文字背景
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		_debug_draw_node.draw_rect(Rect2(text_pos - Vector2(2, 12), text_size + Vector2(4, 4)), Color(0, 0, 0, 0.5))
		
		_debug_draw_node.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, debug_hitbox_color)

func _on_frame_changed_debug():
	pass

func _update_debug_visuals():
	# 总开关关闭时既不建也不画，已存在的调试层一并隐藏
	if not MatchConfig.debug_enabled:
		if _debug_canvas_layer:
			_debug_canvas_layer.visible = false
		return
	# 按需创建调试节点
	if debug_show_hitboxes or debug_show_attack_boxes or debug_show_info_points:
		_ensure_debug_system()
	if _debug_canvas_layer:
		_debug_canvas_layer.visible = true
	# 如果需要立即刷新，手动请求重绘
	if _debug_draw_node:
		_debug_draw_node.queue_redraw()

# ============================================
# 受击框调试可视化
# ============================================

func _create_hitbox_visual(area: Area2D, index: int) -> Control:
	var container = Control.new()
	container.name = "HitboxDebug_" + str(index)
	
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(debug_hitbox_color, debug_box_fill_alpha)
	container.add_child(bg)
	
	var border = ReferenceRect.new()
	border.name = "Border"
	border.editor_only = false
	border.border_color = debug_hitbox_color
	border.border_width = debug_box_line_width
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(border)
	
	var label = Label.new()
	label.name = "Label"
	label.add_theme_font_size_override("font_size", 10)
	label.modulate = debug_hitbox_color
	container.add_child(label)
	
	return container

func _update_hitbox_visual_transform(visual: Control, area: Area2D, index: int):
	if not get_animator_node():
		return
		
	# 1. 纯粹获取位置，不掺杂任何尺寸/缩放因素
	var global_pos = area.global_position
	var viewport_pos = get_viewport().canvas_transform * global_pos
	
	var collision_shape = area.get_child(0) as CollisionShape2D
	if not collision_shape or not collision_shape.shape:
		return
		
	# 2. 纯粹获取实际物理大小，必须包含全局缩放
	var shape_size = Vector2.ZERO
	if collision_shape.shape is RectangleShape2D:
		# abs() 是防止面朝左时 scale.x 为 -1 导致尺寸变负数
		shape_size = collision_shape.shape.size * area.global_scale.abs()
	elif collision_shape.shape is CircleShape2D:
		var radius = collision_shape.shape.radius * abs(area.global_scale.x)
		shape_size = Vector2(radius * 2, radius * 2)
		
	# 3. 用位置和大小独立计算绘制区域
	visual.position = viewport_pos - shape_size / 2.0
	visual.size = shape_size
	
	var bg = visual.get_node("Background")
	if bg:
		bg.size = shape_size
		
	var label = visual.get_node("Label")
	if label:
		var z_info = ""
		if current_frame_data and index < current_frame_data.hitboxes_data.size():
			var hitbox_data = current_frame_data.hitboxes_data[index]
			var z_offset = hitbox_data.get("z_offset", 0.0)
			var z_height = hitbox_data.get("z_height", 50.0)
			var actual_z = position_3d.z + z_offset
			var y_depth = hitbox_data.get("y_depth", hitbox_data.get("z_height", 50.0))
			z_info = "\nZ:%.0f(±%.0f) | D:%.0f" % [actual_z, z_height/2, y_depth]
		label.text = "受击%d%s" % [index, z_info]
		label.position = Vector2(0, -35)

# ============================================
# 攻击框调试可视化
# ============================================
func _create_attack_box_visual(box_id: String, box_data: AttackBoxData) -> Control:
	var container = Control.new()
	container.name = "AttackBoxDebug_" + box_id
	
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(debug_attack_box_color, debug_box_fill_alpha)
	container.add_child(bg)
	
	var border = ReferenceRect.new()
	border.name = "Border"
	border.editor_only = false
	border.border_color = debug_attack_box_color
	border.border_width = debug_box_line_width
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(border)
	
	var label = Label.new()
	label.name = "Label"
	label.add_theme_font_size_override("font_size", 10)
	label.modulate = debug_attack_box_color
	container.add_child(label)
	
	if debug_show_z_depth:
		var z_indicator = ColorRect.new()
		z_indicator.name = "ZIndicator"
		z_indicator.color = Color.CYAN
		container.add_child(z_indicator)
	
	return container

func _update_attack_box_visual_transform(visual: Control, box_node: Area2D, box_data: AttackBoxData, config: AttackBoxData.FrameConfig, active_data: Dictionary):
	if not box_node or not config:
		return
		
	# 同样，位置与尺寸完全解耦
	var global_pos = box_node.global_position
	var viewport_pos = get_viewport().canvas_transform * global_pos
	
	var collision_shape = box_node.get_child(0) as CollisionShape2D
	if not collision_shape or not collision_shape.shape:
		return
		
	var shape_size = Vector2.ZERO
	if collision_shape.shape is RectangleShape2D:
		shape_size = collision_shape.shape.size * box_node.global_scale.abs()
		
	visual.position = viewport_pos - shape_size / 2.0
	visual.size = shape_size
	
	var bg = visual.get_node("Background")
	if bg:
		bg.size = shape_size
		
	var label = visual.get_node("Label")
	if label:
		var instance_key = active_data.get("instance_key", "")
		var trigger_status = "✓" if box_data.has_triggered_instance(instance_key) else "○"
		var z_info = ""
		if debug_show_z_depth:
			z_info = "\nZ:%.0f(±%.0f) | D:%.0f" % [config.position.z, config.size.z/2, config.size.y]
		label.text = "%s [%s]%s" % [box_data.box_name, trigger_status, z_info]
		label.position = Vector2(0, -50 if debug_show_z_depth else -20)
		
	if debug_show_z_depth:
		var z_indicator = visual.get_node("ZIndicator")
		if z_indicator:
			var z_ratio = clamp(config.size.z / 200.0, 0.1, 1.0)
			z_indicator.size = Vector2(4, shape_size.y * z_ratio)
			z_indicator.position = Vector2(shape_size.x + 2, (shape_size.y - z_indicator.size.y) / 2)

func _clear_attack_box_debug_visuals():
	for visual in _debug_attack_box_visuals.values():
		if is_instance_valid(visual):
			visual.queue_free()
	_debug_attack_box_visuals.clear()

# ============================================
# 状态栈（观察层，纯附加）
# ============================================
# 把散落的状态布尔量汇总成一处可枚举的位掩码，实现在
# assets/entities/base/entity_state_stack.gd。本层不改写任何字段、
# 不驱动任何行为，进入与退出只发信号。
#
# 接入方式是纯附加的：
#   - 每次读字段重新推导，不新增任何状态真值来源
#   - 只在 _physics_process 开头观测一次，故观测延迟最多一个物理帧
#   - 状态真值仍是原来的布尔量，删掉本层不影响任何现有行为

@export var debug_state_stack: bool = false
var state_stack: EntityStateStack = null

func _init_state_stack() -> void:
	state_stack = EntityStateStack.new()
	state_stack.state_entered.connect(_on_entity_state_entered)
	state_stack.state_exited.connect(_on_entity_state_exited)

func _update_state_stack() -> void:
	if state_stack == null:
		_init_state_stack()
	state_stack.update(self, Engine.get_physics_frames())

func _on_entity_state_entered(state: int, frame: int) -> void:
	entity_state_entered.emit(state, frame)
	if debug_state_stack:
		print("[状态栈] +%s @f%d | %s" % [state_stack.get_state_name(state), frame, state_stack.describe()])

func _on_entity_state_exited(state: int, frame: int) -> void:
	entity_state_exited.emit(state, frame)
	if debug_state_stack:
		print("[状态栈] -%s @f%d | %s" % [state_stack.get_state_name(state), frame, state_stack.describe()])

## 当前是否处于某状态（传 EntityStateStack.State.*）
func has_entity_state(state: int) -> bool:
	return state_stack != null and state_stack.has(state)

## 当前激活状态的位掩码。int，可直接进快照/同步。
func get_entity_state_mask() -> int:
	return state_stack.get_mask() if state_stack else 0

## 优先级最高的激活状态
func get_entity_state_top() -> int:
	return state_stack.get_top() if state_stack else EntityStateStack.State.NONE

## 调试用单行描述
func describe_entity_states() -> String:
	return state_stack.describe() if state_stack else "NONE"

# ============================================
# 处理循环
# ============================================

func _process(delta):
	_ensure_frame_sync()
	
	if MatchConfig.debug_enabled and (debug_show_hitboxes or debug_show_attack_boxes or debug_show_info_points):
		_ensure_debug_system()
		if _debug_draw_node:
			_debug_draw_node.queue_redraw()

func _physics_process(delta):
	# 换上新收到的键盘上升沿，供本帧两条输入路径消费，见 _input 上方的注释。
	# 放在函数最开头：无论下面走哪条早退分支，上一帧的快照都不会留到下一帧。
	_key_edges_tick = _key_edges
	_key_edges = {}
	# 预输入缓冲的时钟：停帧与卡肉这两类帧不走，缓冲窗口就只在实体能动的帧里流逝
	if not _hit_stop_active and not get_tree().paused:
		_buffer_clock += 1
		_buffer_time += delta
	_update_state_stack()
	if is_player:
		hp_red.value = hp
	_process_magnetism(delta) # 优先级这一块/.
	_process_global_magnetisms(delta) # 全局吸附（多吸附共存）
	_record_inputs()
	# 预输入消费必须与"记录"同挂物理帧：
	# 计时用 _buffer_time（只在实体能动的帧里累加，见该字段注释），
	# 窗口恒为 buffer_valid_seconds（0.2 秒），不会因为停帧或卡肉而白烧。
	# 若挂在 _process（渲染帧）而 VSync 又是关的，帧率越高缓冲窗口越短
	# （144fps→83ms、300fps→40ms），预输入手感会随机器变化。
	_consume_local_buffer()
	
	# 卡肉状态：冻结所有更新，不调用 move_and_slide
	if _hit_stop_active:
		_apply_facing()
		_process_hit_stop(delta)
	
	if _immobilize_active:
		_process_immobilize(delta)
	
	# 效果的处理挪到卡肉早退之前：勾了「不受减帧影响」的效果在卡肉停帧期间照常走计时与回调。
	# 没勾的那部分由 _process_modifiers 自己按卡肉状态跳过，与挪动之前同口径。
	# 注意只挪到这一处，下面那个 _process_modifiers 调用点已经删除，免得勾了的效果一帧走两次。
	_process_modifiers(delta)
	
	if _hit_stop_active:
		out_of_wall()
		_update_visual_position()  # 卡肉中若被墙回推，视觉立即同步，避免墙体穿模残影
		return
	
	# 延迟减帧的计时放在卡肉早退之后：卡肉期间不流逝，与停帧同口径
	_process_pending_hit_stops(delta)
	
	_process_cd(delta)
	_process_timer(delta)
	_process_bonus(delta)
	_process_states(delta)
	_process_substitution_invincibility(delta)
	_handle_body_state()
	
	# 物理处理
	_process_knockback(delta)
	_process_launch(delta)
	_control_system(delta)
	_entity_input()
	_handle_input()
	_handle_movement(delta)
	_process_z_physics(delta)
	_apply_frame_data()
	_apply_anchor_constraint()
	_apply_facing()
	_process_slide_physics(delta)
	_handle_free_move_physics(delta)
	velocity.x = velocity_3d.x
	velocity.y = velocity_3d.y
	
	move_and_slide()
	
	position_3d.x = position.x
	position_3d.y = position.y + position_3d.z
	out_of_wall()
	
	if entry_action == EntryAction.DEFAULT:
		if not is_grounded:
			# 空中：只处理 X 轴的水平位移
			position_3d.x += _entry_fall_speed_x * delta
		else:
			# 落地瞬间：精准吸附到预设 X，并切换收尾动画
			position_3d.x = _entry_target_x
			_entry_fall_speed_x = 0.0
			stop_slide()
			# 只播一次：本分支每帧都会进入，而 play_animation 对同动画会重置重播，
			# 若不守卫会把 entry_e 永远卡在第一帧
			if current_animation != "entry_e":
				play_animation("entry_e")
	
	_update_visual_position()
	
	if enable_depth_sort and DepthManager.update_frequency == DepthManager.UpdateFrequency.EVERY_FRAME:
		_update_depth()

func out_of_wall():
	if entry_action == EntryAction.DEFAULT: return
	
	if main and main.has_method("point_walls") and enable_wall_collision:
		if out_wall_mode == OutWallMode.CALCULATE:
			# 独立检测 X/Y，防止一个轴卡墙导致另一个轴无法移动
			var wx = main.point_walls(Vector2(position_3d.x, _last_valid_wall_pos.y))
			if wx:
				position_3d.x = wx.x
			var wy = main.point_walls(Vector2(position_3d.x, position_3d.y))
			if wy:
				position_3d.y = wy.y
			_last_valid_wall_pos = Vector2(position_3d.x, position_3d.y)
		elif out_wall_mode == OutWallMode.RETURN:
			var wx = main.point_walls(Vector2(position_3d.x, _last_valid_wall_pos.y))
			if wx:
				position_3d.x = _last_valid_wall_pos.x
			var wy = main.point_walls(Vector2(position_3d.x, position_3d.y))
			if wy:
				position_3d.y = _last_valid_wall_pos.y
			_last_valid_wall_pos = Vector2(position_3d.x, position_3d.y)

func _process_ultimate_point():
	if is_player:
		ultimate_panel.point = ultimate_point
		ultimate_panel.max_point = ultimate_point_max
		match entity_type:
			EntityType.PLAYER:
				skill_slot[4].dot = ultimate_point

func _update_summon_dot():
	if is_player:
		match entity_type:
			EntityType.PLAYER:
				skill_slot[6].dot = summon_entity_path.size()

## 密卷与通灵槽位的图标按「携带的那个东西自己的 icon_idle」取，目录规则与角色图标一致。
## 密卷可重复使用，所以整局不变；通灵是队列，用掉一个就换成队列里的下一个。
## 三个调用点：角色配置就绪（setup_player_config）、面板交接手（_push_slot_state_to_panel）、
## 消耗通灵（handle_summon），后两处都紧跟点数刷新。
func _refresh_scroll_summon_icons():
	if not is_player or entity_type != EntityType.PLAYER:
		return
	_apply_slot_icon_from_entity_path(SLOT_SCROLL, scroll_entity_path)
	# 队列空时什么都不做：图标留在最后一个通灵上，剩余数量由点数显示，与手游玩法一致
	if summon_entity_path.size() > 0:
		_apply_slot_icon_from_entity_path(SLOT_SUMMON, str(summon_entity_path[0]))

## entity_scene_path 形如 res://assets/entities/大运重卡/entity.tscn，取同级目录的 portraits/icon_idle.png。
## 找不到就保留槽位原图并告警：槽位图标同时被角色脚本的 setup_icon 用着，
## 塞一张占位图会把图标缩放基准带偏（112 除以贴图尺寸），什么都不做比放错图安全。
func _apply_slot_icon_from_entity_path(slot_id: int, entity_scene_path: String):
	if slot_id < 0 or slot_id >= skill_slot.size() or entity_scene_path == "":
		return
	var icon_path := entity_scene_path.get_base_dir().path_join(PORTRAIT_ICON_FILE)
	if not ResourceLoader.exists(icon_path):
		push_warning("[图标] %s 下没有 %s，槽位 %d 保留原图" % [
			entity_scene_path.get_base_dir().get_file(), PORTRAIT_ICON_FILE, slot_id])
		return
	skill_slot[slot_id].set_texture(load(icon_path))

func _handle_body_state():
	var dc_body_state: BodyState = BodyState.NORMAL
	if current_animation in ["scroll", "summon"]:
		dc_body_state = BodyState.KONGO
	var lbs = body_state
	body_state = max(custom_body_state, add_body_state, dc_body_state)
	if body_state == BodyState.KONGO and lbs != BodyState.KONGO:
		if have_modifiers("addBodyState"):
			set_modifiers("addBodyState", BodyState.NORMAL, 0)

func _process_substitution_invincibility(delta: float):
	"""处理替身无敌倒计时"""
	var mat = get_anim_material() as ShaderMaterial
	
	if not _substitution_invincible:
		if mat:
			# 恢复完全不透明
			mat.set_shader_parameter("self_modulate", Color(1, 1, 1, 1.0))
		return
	
	if mat:
		# 半透明闪烁
			mat.set_shader_parameter("self_modulate", Color(1, 1, 1, 0.8))
	
	_substitution_timer -= delta
	
	if _substitution_timer <= 0:
		_substitution_invincible = false
		_substitution_timer = 0.0
		_update_hitbox_collision_state()
		substitution_invincibility_ended.emit()
		
		if debug_team:
			print("[替身无敌] %s 时间到，自动结束" % name)

## cd_id 是否有对应的冷却 / 计时项。两张表固定 9 项且与面板无关，
## 每个实体都建，所以这里只可能是作者填了越界序号。
func _has_cd_slot(cd_id: int) -> bool:
	return cd_id >= 0 and cd_id < skill_timer.size()

## slot_id 是否有真实的面板槽位可写。负数表示不绑面板（子实体、只有事件没有进度条的计时），
## 越界表示该实体根本没绑面板。两种都为假，调用方据此跳过界面写入。
func _has_panel_slot(slot_id: int) -> bool:
	return slot_id >= 0 and slot_id < skill_slot.size()

func set_cd(slot_id: int, cd_id: int, cd: float):
	if not _has_cd_slot(cd_id):
		push_warning("[冷却] cd_id %d 越界，%s 上本次设置被忽略" % [cd_id, name])
		return
	match entity_type:
		EntityType.PLAYER:
			if _has_panel_slot(slot_id):
				skill_slot[slot_id].set_cd(cd)
	for i in cool_down_time.size():
		if cool_down_time[i]["slot_id"] == slot_id:
			cool_down_time[i]["slot_id"] = -114514
	cool_down_time[cd_id] = {"time": cd, "slot_id": slot_id}

func set_timer(slot_id: int, cd_id: int, cd: float, cd_max: float):
	if not _has_cd_slot(cd_id):
		push_warning("[计时] cd_id %d 越界，%s 上本次设置被忽略" % [cd_id, name])
		return
	_remove_sub_slot_from_all(slot_id)
	match entity_type:
		EntityType.PLAYER:
			if _has_panel_slot(slot_id):
				skill_slot[slot_id].timer_progress = cd / cd_max
	for i in skill_timer.size():
		if skill_timer[i]["slot_id"] == slot_id:
			skill_timer[i]["slot_id"] = -114514
	skill_timer[cd_id] = {"time": cd, "max_time": cd_max, "slot_id": slot_id, "sub_slots": skill_timer[cd_id].get("sub_slots", [])}
	if cd <= 0:
		skill_timer[cd_id]["time"] = 0
		on_timer_out(cd_id)
		match entity_type:
			EntityType.PLAYER:
				for sid in skill_timer[cd_id].get("sub_slots", []) + [slot_id]:
					if _has_panel_slot(sid):
						skill_slot[sid].timer_progress = 0

## 设置一个效果。同类型已存在时是覆盖式重设，并把启动回调重新走一遍。
##
## 两个开关都挂在这条效果自己身上，同一个实体上不同类型的效果可以各勾各的：
##   clearable   可被清除。clear_temporary_status 会把勾了的效果按收尾流程结束掉，
##               没勾的照旧不受影响，默认不勾，老数据的口径不变。
##   hit_stop_inv 不受减帧影响。默认勾上，卡肉停帧期间照常走计时与每帧回调；
##               不勾的整条跳过，与加这个开关之前的口径一致。
func set_modifiers(type: String, pow: int, time: float = -2,
		on_start: String = "", on_update: String = "", on_end: String = "",
		caster: Node2D = null, clearable: bool = false, hit_stop_inv: bool = true):
	for i in modifiers.size():
		if modifiers[i]["type"] == type:
			modifiers[i]["power"] = pow
			modifiers[i]["time"] = time
			modifiers[i]["on_start"] = on_start
			modifiers[i]["on_update"] = on_update
			modifiers[i]["on_end"] = on_end
			modifiers[i]["_started"] = false
			modifiers[i]["caster"] = caster
			modifiers[i]["clearable"] = clearable
			modifiers[i]["hit_stop_inv"] = hit_stop_inv
			return
	modifiers.append({
		"time": time, "type": type, "power": pow,
		"on_start": on_start, "on_update": on_update, "on_end": on_end,
		"_started": false, "caster": caster,
		"clearable": clearable, "hit_stop_inv": hit_stop_inv
	})

func _process_cd(delta):
	for i in cool_down_time.size():
		if cool_down_time[i]["time"] > 0:
			cool_down_time[i]["time"] -= delta
			if cool_down_time[i]["time"] < 0:
				cool_down_time[i]["time"] = 0
			if _has_panel_slot(cool_down_time[i]["slot_id"]):
				match entity_type:
					EntityType.PLAYER:
						skill_slot[cool_down_time[i]["slot_id"]].cool_down_time_now = cool_down_time[i]["time"]

func _process_timer(delta):
	for i in skill_timer.size():
		if skill_timer[i]["time"] > 0:
			skill_timer[i]["time"] -= delta
			# 判据必须是 <=0：卡顿或大 delta 会让 time 一次减到正好 0，
			# 用 <0 就漏掉这一帧，而下一帧 time>0 已经不成立，事件永久丢失。
			if skill_timer[i]["time"] <= 0:
				skill_timer[i]["time"] = 0
				# slot_id 只决定要不要画进度，不影响事件。负数（子实体没有面板时用的那种）
				# 同样必须触发。
				on_timer_out(i)
			if skill_timer[i]["slot_id"] >= 0 or skill_timer[i].get("sub_slots", []).size() > 0:
				match entity_type:
					EntityType.PLAYER:
						var p = skill_timer[i]["time"] / skill_timer[i]["max_time"]
						if _has_panel_slot(skill_timer[i]["slot_id"]):
							skill_slot[skill_timer[i]["slot_id"]].timer_progress = p
						for sid in skill_timer[i].get("sub_slots", []):
							if _has_panel_slot(sid):
								skill_slot[sid].timer_progress = p

func on_timer_out(cd_id: int):
	timer_out.emit(cd_id)
	pass
	#print("timerout",cd_id)

func _process_modifiers(delta):
	for i in modifiers.size():
		# 卡肉停帧期间只放过勾了「不受减帧影响」的效果。没勾的整条跳过：
		# 计时不走、每帧回调不调、when_modifier_update 也不触发，与加这个开关之前同口径。
		if _hit_stop_active and not modifiers[i].get("hit_stop_inv", true):
			continue
		if modifiers[i]["time"] > 0 or modifiers[i]["time"] == -2:
			var type = modifiers[i]["type"]
			var power = modifiers[i]["power"]
			var time_left = modifiers[i]["time"]
			var caster = modifiers[i].get("caster", null)
			# 效果启动（仅首次）
			if not modifiers[i].get("_started", false):
				modifiers[i]["_started"] = true
				var cb = modifiers[i].get("on_start", "")
				if cb and has_method(cb):
					call(cb, self)
				_on_modifier_start(type, power, time_left)
				if caster and caster != self:
					caster._on_modifier_start(type, power, time_left, self)
			# 效果运行（每帧）
			handle_modifiers_solo(i)
			var cb = modifiers[i].get("on_update", "")
			if cb and has_method(cb):
				call(cb, self)
			_on_modifier_update(type, power, time_left)
			if caster and caster != self:
				caster._on_modifier_update(type, power, time_left, self)
			# 计时
			if modifiers[i]["time"] > 0:
				modifiers[i]["time"] -= delta
				if modifiers[i]["time"] < 0:
					modifiers[i]["time"] = 0
		else:
			if modifiers[i]["time"] == 0:
				handle_modifiers_reverse_solo(i)
				var type = modifiers[i]["type"]
				var power = modifiers[i]["power"]
				var time_left = modifiers[i]["time"]
				var caster = modifiers[i].get("caster", null)
				# 效果结束
				var cb = modifiers[i].get("on_end", "")
				if cb and has_method(cb):
					call(cb, self)
				_on_modifier_end(type, power, time_left)
				if caster and caster != self:
					caster._on_modifier_end(type, power, time_left, self)
				modifiers[i]["time"] = -1

## 结束所有勾了「可被清除」的效果。走与自然到期同一条收尾：
## 反向处理 + on_end 回调 + modifier_end 信号，最后把 time 标成 -1，
## 所以 when_modifier_end 照常触发，作者写在结束分支里的善后不会漏。
##
## time_left 传的是这条效果还剩下的时间。自然到期那条路走出来必然是 0，
## 被清除的可能是正数，也可能是 -2 表示本来就是永久效果，读这个值能分辨两者。
##
## 一次都没跑过启动的只标掉、不发结束事件：那次效果根本没生效过，
## 发出去只会让作者收到一次没有对应开始的结束。
func _clear_clearable_modifiers():
	for i in modifiers.size():
		if not modifiers[i].get("clearable", false):
			continue
		if modifiers[i]["time"] == -1:
			continue  # 已经结束过，不能重复收尾
		if modifiers[i].get("_started", false):
			handle_modifiers_reverse_solo(i)
			var type = modifiers[i]["type"]
			var power = modifiers[i]["power"]
			var time_left = modifiers[i]["time"]
			var caster = modifiers[i].get("caster", null)
			var cb = modifiers[i].get("on_end", "")
			if cb and has_method(cb):
				call(cb, self)
			_on_modifier_end(type, power, time_left)
			if caster and caster != self:
				caster._on_modifier_end(type, power, time_left, self)
		modifiers[i]["time"] = -1

func _on_modifier_start(type: String, power: int, time_left: float = -2.0, target: Node2D = null):
	modifier_start.emit(type, power, time_left, target)
	pass

func _on_modifier_update(type: String, power: int, time_left: float = -2.0, target: Node2D = null):
	modifier_update.emit(type, power, time_left, target)
	pass

func _on_modifier_end(type: String, power: int, time_left: float = -2.0, target: Node2D = null):
	modifier_end.emit(type, power, time_left, target)
	pass

func bind_cd(slot_id: int, cd_id: int):
	if not _has_cd_slot(cd_id):
		push_warning("[冷却] 绑定: cd_id %d 越界，%s 上本次绑定被忽略" % [cd_id, name])
		return
	match entity_type:
		EntityType.PLAYER:
			if _has_panel_slot(slot_id):
				skill_slot[slot_id].set_cd(cool_down_time[cd_id]["time"])
	for i in cool_down_time.size():
		if cool_down_time[i]["slot_id"] == slot_id:
			cool_down_time[i]["slot_id"] = -1
	cool_down_time[cd_id]["slot_id"] = slot_id

func set_slot_aura(slot_id: int, show: bool):
	if _has_panel_slot(slot_id):
		skill_slot[slot_id].show_aura = show

# ========== 附属槽位管理 ==========

## 从所有计时中移除指定 slot_id 的附属关系
func _remove_sub_slot_from_all(slot_id: int):
	for i in skill_timer.size():
		var subs = skill_timer[i].get("sub_slots", [])
		if slot_id in subs:
			subs.erase(slot_id)

## 给计时添加附属槽位
func add_timer_sub_slot(cd_id: int, slot_id: int):
	if not _has_cd_slot(cd_id):
		push_warning("[计时] 附属槽位: cd_id %d 越界，%s 上本次设置被忽略" % [cd_id, name])
		return
	_remove_sub_slot_from_all(slot_id)
	if not skill_timer[cd_id].has("sub_slots"):
		skill_timer[cd_id]["sub_slots"] = []
	if slot_id not in skill_timer[cd_id]["sub_slots"]:
		skill_timer[cd_id]["sub_slots"].append(slot_id)
	match entity_type:
		EntityType.PLAYER:
			if _has_panel_slot(slot_id):
				var p = skill_timer[cd_id]["time"] / skill_timer[cd_id]["max_time"] if skill_timer[cd_id]["max_time"] > 0 else 0
				skill_slot[slot_id].timer_progress = p

## 取消计时的某槽位附属
func remove_timer_sub_slot(cd_id: int, slot_id: int):
	if not _has_cd_slot(cd_id):
		push_warning("[计时] 取消附属: cd_id %d 越界，%s 上本次操作被忽略" % [cd_id, name])
		return
	if skill_timer[cd_id].has("sub_slots"):
		skill_timer[cd_id]["sub_slots"].erase(slot_id)

## 清除某计时的所有槽位附属
func clear_timer_sub_slots(cd_id: int):
	if not _has_cd_slot(cd_id):
		push_warning("[计时] 清空附属: cd_id %d 越界，%s 上本次操作被忽略" % [cd_id, name])
		return
	skill_timer[cd_id]["sub_slots"] = []

func handle_modifiers_solo(id: int):
	match modifiers[id]["type"]:
		"customBodyState":
			custom_body_state = modifiers[id]["power"]
			if custom_body_state > add_body_state:
				set_modifiers("addBodyState", BodyState.NORMAL, 0)
		"addBodyState":
			add_body_state = modifiers[id]["power"]

func handle_modifiers_reverse_solo(id: int):
	match modifiers[id]["type"]:
		"customBodyState":
			custom_body_state = BodyState.NORMAL
		"addBodyState":
			add_body_state = BodyState.NORMAL

func have_modifiers(type: String) -> bool:
	for i in modifiers.size():
		if modifiers[i]["type"] == type and (modifiers[i]["time"] > 0 or modifiers[i]["time"] == -2):
			return true
	return false

# ========== 加成池（可堆叠数值加成） ==========

## 添加加成：type=atk/speed/def，mode=multiply(乘算)/add(加算)，duration=-2 永久，group 用于精确移除，返回实例 id
func add_bonus(e_type: String, value: float, duration: float = -2.0, mode: String = "multiply", source: Node2D = null, group: String = "") -> int:
	var id = _bonus_next_id
	_bonus_next_id += 1
	bonus_pool.append({
		"id": id, "type": e_type, "value": value,
		"duration": duration, "time_left": duration,
		"mode": mode, "source": source, "group": group
	})
	_recalc_bonus()
	return id

func remove_bonus(id: int):
	for i in range(bonus_pool.size() - 1, -1, -1):
		if bonus_pool[i]["id"] == id:
			bonus_pool.remove_at(i)
			_recalc_bonus()
			return true
	return false

## 移除指定类型最早添加的一层；e_group 非空时仅匹配该分组，成功返回 true
func remove_bonus_layer(e_type: String, e_group: String = "") -> bool:
	for i in bonus_pool.size():
		if bonus_pool[i]["type"] == e_type and (e_group == "" or bonus_pool[i].get("group", "") == e_group):
			bonus_pool.remove_at(i)
			_recalc_bonus()
			return true
	return false

## 按类型清空，type 为空则清空全部
func clear_bonus(e_type: String = ""):
	if e_type == "":
		bonus_pool.clear()
	else:
		for i in range(bonus_pool.size() - 1, -1, -1):
			if bonus_pool[i]["type"] == e_type:
				bonus_pool.remove_at(i)
	_recalc_bonus()

func get_bonus_value(e_type: String) -> float:
	match e_type:
		"atk": return final_atk
		"speed": return final_speed
		"def": return final_def
	return 1.0

## 遍历池子重算最终加成（乘算：直接乘 value，value=倍率 1=不变；加算：累加 value）
func _recalc_bonus():
	final_atk = 1.0
	final_speed = 1.0
	final_def = 1.0
	for e in bonus_pool:
		var v = e["value"]
		var is_mult = e["mode"] == "multiply"
		match e["type"]:
			"atk":
				final_atk = final_atk * v if is_mult else final_atk + v
			"speed":
				final_speed = final_speed * v if is_mult else final_speed + v
			"def":
				final_def = final_def * v if is_mult else final_def + v

func _process_bonus(delta):
	var changed = false
	for i in range(bonus_pool.size() - 1, -1, -1):
		var t: float = bonus_pool[i]["time_left"]
		if t > 0:
			bonus_pool[i]["time_left"] = t - delta
			if bonus_pool[i]["time_left"] <= 0:
				bonus_pool.remove_at(i)
				changed = true
	if changed:
		_recalc_bonus()

# ========== 状态池（自定义状态标记，可堆叠） ==========

## 添加状态：state 为任意自定义名，duration=-2 永久，返回实例 id
func add_state(state: String, duration: float = -2.0, source: Node2D = null) -> int:
	var id = _state_next_id
	_state_next_id += 1
	state_pool.append({"id": id, "state": state, "duration": duration, "time_left": duration, "source": source})
	return id

func remove_state(id: int):
	for i in range(state_pool.size() - 1, -1, -1):
		if state_pool[i]["id"] == id:
			state_pool.remove_at(i)
			return true
	return false

## 按名称移除 count 层（count=-1 移除全部同名）
func remove_state_by_name(state: String, count: int = -1):
	var removed = 0
	for i in range(state_pool.size() - 1, -1, -1):
		if state_pool[i]["state"] == state:
			state_pool.remove_at(i)
			removed += 1
			if count >= 0 and removed >= count:
				break

## 按名称清空，state 为空则清空全部
func clear_state(state: String = ""):
	if state == "":
		state_pool.clear()
	else:
		for i in range(state_pool.size() - 1, -1, -1):
			if state_pool[i]["state"] == state:
				state_pool.remove_at(i)

func has_state(state: String) -> bool:
	return get_state_count(state) > 0

func get_state_count(state: String) -> int:
	var n = 0
	for s in state_pool:
		if s["state"] == state:
			n += 1
	return n

func _process_states(delta):
	for i in range(state_pool.size() - 1, -1, -1):
		var t: float = state_pool[i]["time_left"]
		if t > 0:
			state_pool[i]["time_left"] = t - delta
			if state_pool[i]["time_left"] <= 0:
				state_pool.remove_at(i)

func change_hp(d: int, show_number: bool = false, kv: float = 0.0, can_variation: bool = false, is_critical: bool = false):
	if d < 0:
		# 加成池：攻击者加成放大伤害，自身防御加成直接乘（>1 减伤，<1 易伤）
		if _last_attacker and _last_attacker is EntityBase:
			d = int(d * _last_attacker.final_atk)
		d = int(d * final_def)
		# 累计攻击者造成的伤害（用于局间继承）
		if _last_attacker:
			_last_attacker.total_damage_dealt += abs(d)
		# 扫地保护处理
		if OTGp_downed_flag == 2:
			if _immobilize_release_active:
				_immobilize_release_active = false
			else:
				OTGp_cLaunch_hp += abs(d)
		# 保护值处理
		if launched_flag and position_3d.z > 0:
			if _immobilize_active and position_3d.z == 0:
				pass
			else:
				cumulative_launch_damage += abs(d)
	
	kv *=  randf_range(0.9, 1.1)
	print("[更变血量] kv: ", kv)
	
	var old_hp = hp
	# 攻击者处于奥义期间 → 这一击不吃被打者(自己)的保护值减伤。
	# 注意是"攻击者的 ultimate_active"，不是本实体自己的；其他来源的伤害照常吃保护值。
	var _ignore_protection = _last_attacker and _last_attacker.ultimate_active
	hp += d if _ignore_protection else d * (1-calculate_protection_value(float(cumulative_launch_damage) / hp_max))
	if hp < 0:
		hp = 0
		if _last_attacker and _last_attacker.ultimate_active and not is_dead:
			_trigger_ultimate_kill_effect()
		hit(HitStateType.LAUNCH, Vector2(-300 * facing_direction, 0), 0.5, 280, true, true)
	elif hp > hp_max:
		hp = hp_max
	
	if old_hp != hp:
		hp_changed.emit(old_hp, hp)
	
	var epos = position_3d
	epos.z *= -1
	epos.z -= 150
	epos.x += randf_range(-20.0, 20.0)
	epos.z += randf_range(-15.0, 15.0)
	if show_number and d < 0 and effects_container:
		var dmg = int(old_hp - hp)
		if dmg > 0:
			var is_controlled = self.name == MatchConfig.current_controller_name
			if is_controlled:
				if is_critical:
					effects_container.spawn_effect("hurt_num_sg_ene", epos, false, {"damage": dmg, "kv": kv})
				else:
					effects_container.spawn_effect("hurt_num_sw_ene", epos, false, {"damage": dmg, "kv": kv})
			else:
				if is_critical:
					effects_container.spawn_effect("hurt_num_sg", epos, false, {"damage": dmg, "kv": kv})
				else:
					effects_container.spawn_effect("hurt_num_sw", epos, false, {"damage": dmg, "kv": kv})

func change_ultimate_point(d: int):
	ultimate_point += d
	if ultimate_point < 0:
		ultimate_point = 0
	elif ultimate_point > ultimate_point_max:
		ultimate_point = ultimate_point_max
	
	_process_ultimate_point()

func get_is_low_floating():
	# 这里「3」是「触地保护」是否触发的「阈值」
	return position_3d.z <= 3

func calculate_protection_value(x: float) -> float:
	if protections:
		protections.update_protection(x)
	if x <= 0.6:
		# ---- 前半段：完美抛物线 ----
		# 精确经过 (0,0), (0.15, 0.15), (0.6, 0.4)
		var a: float = -20.0 / 27.0
		var b: float = 10.0 / 9.0
		return a * (x * x) + b * x
		
	else:
		# ---- 后半段：指数缓和趋近 ----
		# 从 (0.6, 0.4) 开始，极限无限趋近于 0.95
		var limit_y: float = 0.95   # 你可以修改这个值，比如改成 0.99，但永远不要写 1.0
		var decay_speed: float = 0.404 # 衰减速度，值越小越缓和
		
		var offset_x: float = x - 0.6
		# 公式：y = 极限 - 差值 * e^(-速度 * 距离)
		return limit_y - 0.55 * exp(-decay_speed * offset_x)

## 保护值作用到击飞初速(zv)：FALL_SPEED 模式原样返回；LAUNCH_SPEED 模式按当前保护值削弱
func _apply_launch_protection(velocity_z: float) -> float:
	if protection_effect == ProtectionEffect.FALL_SPEED:
		return velocity_z
	var pv: float = calculate_protection_value(float(cumulative_launch_damage) / hp_max)
	return velocity_z * (1.0 - launch_protection_decay * pv)

func _reset_attack_state():
	clear_temporary_status()
	clear_attack_state()

func clear_attack_state():
	is_attacking = false
	current_attack = ""
	_waiting_for_land = false

# ============================================
# 招式识别（只读观察层）
# ============================================
# 目的：让 AI / UI / 调试 能回答"现在在放哪个招式、处于哪个阶段"。
# 设计原则：纯附加、只读、不改动任何现有行为；角色脚本与 JSON 均无需改动。
#   ① 招式身份：沿 attack_configs 的 next_attack / end_anim 反向走到链起点，再按前缀归类
#      （可选增强：给某个节点加 "move_id": "xxx" 可覆盖前缀推断）
#   ② 三阶段：由 attack_boxes.json 已有的 bind_frames 推导（前摇 / 判定 / 收招）
# 已知边界：attack_configs 里不含奥义/秘卷/通灵的节点，故奥义靠既有 ultimate_active
#   标志判断，秘卷/通灵返回空串（它们走独立子实体，不占本实体的招式链）。

enum MovePhase { NONE, STARTUP, ACTIVE, RECOVERY }

const MOVE_ID_ATTACK: String = "attack"
const MOVE_ID_SKILL1: String = "skill1"
const MOVE_ID_SKILL2: String = "skill2"
const MOVE_ID_ULTIMATE: String = "ultimate"

## 反向走到链起点（如 a3 -> a2 -> a1）
func get_chain_root() -> String:
	if current_attack == "":
		return ""
	return _resolve_chain_root(current_attack)

func _resolve_chain_root(node: String) -> String:
	if not (attack_configs is Dictionary) or attack_configs.is_empty():
		return node
	var cur: String = node
	var guard: int = 0
	while guard < 32:
		guard += 1
		var prev: String = ""
		for key in attack_configs.keys():
			var cfg = attack_configs[key]
			if not (cfg is Dictionary):
				continue
			if String(cfg.get("next_attack", "")) == cur or String(cfg.get("end_anim", "")) == cur:
				prev = String(key)
				break
		if prev == "" or prev == cur:
			break
		cur = prev
	return cur

func _move_id_from_root(root: String) -> String:
	if root == "":
		return ""
	if attack_configs is Dictionary and attack_configs.has(root):
		var cfg = attack_configs[root]
		if cfg is Dictionary:
			var explicit: String = String(cfg.get("move_id", ""))
			if explicit != "":
				return explicit
	if root.begins_with("s1"):
		return MOVE_ID_SKILL1
	if root.begins_with("s2"):
		return MOVE_ID_SKILL2
	if root.begins_with("s3"):
		return MOVE_ID_ULTIMATE
	if root.begins_with("a"):
		return MOVE_ID_ATTACK
	return root

## 当前招式身份；无招式时返回 ""
func get_move_id() -> String:
	if ultimate_active:
		return MOVE_ID_ULTIMATE
	if not is_attacking or current_attack == "":
		return ""
	return _move_id_from_root(get_chain_root())

## 取某动画的判定帧区间（来自 attack_boxes.json 的 bind_frames）
func _get_anim_active_span(anim: String) -> Dictionary:
	if anim == "" or not attack_box_manager:
		return {}
	var first: int = -1
	var last: int = -1
	for box in attack_box_manager.get_all_attack_boxes():
		if box == null or box.bind_animation != anim:
			continue
		for fr in box.bind_frames:
			var fi: int = int(fr)
			if first < 0 or fi < first:
				first = fi
			if fi > last:
				last = fi
	if last < 0:
		return {}
	return {"first": first, "last": last}

## 当前阶段（前摇 / 判定 / 收招）；无判定框的动画返回 NONE
func get_move_phase() -> int:
	if not is_attacking:
		return MovePhase.NONE
	var span: Dictionary = _get_anim_active_span(current_animation)
	if span.is_empty():
		return MovePhase.NONE
	var f: int = get_current_frame()
	if f < int(span["first"]):
		return MovePhase.STARTUP
	if f <= int(span["last"]):
		return MovePhase.ACTIVE
	return MovePhase.RECOVERY

## 打包当前招式信息（供 AI / UI / 调试消费）
func get_move_info() -> Dictionary:
	var mid: String = get_move_id()
	if mid == "":
		return {}
	var anim: String = current_animation
	var span: Dictionary = _get_anim_active_span(anim)
	var frame: int = get_current_frame()
	var total: int = get_animation_frame_count(anim)
	var cancel_win: Array = []
	var next_node: String = ""
	if attack_configs is Dictionary and attack_configs.has(current_attack):
		var cfg = attack_configs[current_attack]
		if cfg is Dictionary:
			cancel_win = cfg.get("cancel_window", [])
			next_node = String(cfg.get("next_attack", ""))
	return {
		"move_id": mid,
		"chain_root": get_chain_root(),
		"node": current_attack,
		"next_node": next_node,
		"anim": anim,
		"phase": get_move_phase(),
		"frame": frame,
		"total_frames": total,
		"frames_left": max(0, total - 1 - frame),
		"active_first": span.get("first", -1),
		"active_last": span.get("last", -1),
		"cancel_window": cancel_win,
		"action_priority": _current_action_priority,
	}

func hit(hit_type: HitStateType,
		 kv: Vector2, hit_stun_time: float,
		 zv: float, can_OTG: bool,
		 is_heavy: bool, state: BodyState = BodyState.NORMAL,
		 hurt: float = 0.0,
		 kr: float = 10.0,
		 ar: float = 0.0,
		 kv_air: Vector2 = Vector2.ZERO,
		 zv_air: float = 0.0,
		 kb_linear: bool = false):
	
	if state < body_state:
		return
	if have_modifiers("customBodyState"):
		set_modifiers("customBodyState", BodyState.NORMAL, 0)
	body_state = BodyState.NORMAL
	clear_attack_state()
	stop_slide()
	
	# 本次击退使用的模型（只影响减速曲线形状，见 _process_knockback）
	_knockback_linear = kb_linear
	
	# 根据轻重击随机选择眩晕动画
	var stun_ani: String = "stun" + str(randi() % 2 + (1 if is_heavy else 3))
	
	var is_launched = _launch_active and !get_is_low_floating()
	var is_downed = (_launch_active and get_is_low_floating()) or _is_downed
	
	# 空中命中**不再降速**：低浮空（z <= 10）与地面拿同一个水平速度（= v.x），
	# 所以"被挑起来再打"和"站地上被打"的横推距离一致。
	# （曾经这里有一条 `if not is_grounded: kv *= 1/3` 的隐式规则，会造成
	#   同一招在 0 < z <= 10 与 z > 10 之间横向击退差 3 倍，已删除。）
	var in_air: bool = false
	
	# 处理平推
	if hit_type == HitStateType.PUSH:
		set_knockback(kv, hit_stun_time, kr, ar, kb_linear)
		
		if is_launched or position_3d.z > 0:
			in_air = true
		elif is_downed:
			if can_OTG:
				set_hit_stun(hit_stun_time, stun_ani)
				set_launch(_apply_launch_protection(zv * 1.5), "launch1")
			elif _immobilize_release_active:
				clear_temporary_status()
				set_hit_stun(hit_stun_time, stun_ani)
			else: # 触地保护(￣▽￣)
				_launch_velocity_z = 0
				position_3d.z = 0
				set_knockback(Vector2.ZERO, 0)
		else:
			set_hit_stun(hit_stun_time, stun_ani)
	
	# 处理击飞
	if hit_type == HitStateType.LAUNCH or in_air:
		if is_downed and can_OTG:
			launched_flag = true
			set_knockback(kv, hit_stun_time, kr, ar, kb_linear)
			set_launch(_apply_launch_protection(zv), "launch1")
		elif !is_downed or (get_is_low_floating() and !_is_downed):
			launched_flag = true
			if position_3d.z <= 10:
				set_knockback(kv, hit_stun_time, kr, ar, kb_linear)
				set_launch(_apply_launch_protection(zv), "launch1")
			else:
				var air_kv: Vector2 = kv_air if kv_air != Vector2.ZERO else kv
				var air_zv: float = zv_air if zv_air != 0.0 else zv
				set_knockback(air_kv, hit_stun_time, kr, ar, kb_linear)
				set_launch(_apply_launch_protection(air_zv), "launch2")
	
	_immobilize_release_active = false
	
	# 立即更新受控状态，避免当帧内后续逻辑读取到错误的值
	is_under_control = knockback_active or _launch_active
	
	change_hp_float(-hurt, kv.x)
	
	# 通知子类/VS组件本次攻击附带了力（击退/击飞）
	if kv.length() > 0 or abs(zv) > 0:
		receive_force.emit(kv, zv)

func change_hp_float(hurt: float, kv: float):
	"""暴击&伤害浮动"""
	var is_c: bool = false
	if randf() <= 0.1:
		hurt *= 1.5
		is_c = true
	hurt *= randf_range(0.9, 1.1)
	change_hp(hurt, true, kv, true, is_c)

func _process_magnetism(delta):
	if _magnetism_time <= 0:
		_magnetism_time = 0
		return
	if _immobilize_active:
		return
	_magnetism_time -= delta

	if _magnetism_state < body_state:
		return

	
	# 计算到目标点的距离
	var dx = _magnetism_pos.x - position_3d.x
	var dy = _magnetism_pos.y - position_3d.y

	# 按各轴速度移动，但不超过剩余距离
	var move_x = min(abs(dx), _magnetism_speed.x * delta) * sign(dx)
	var move_y = min(abs(dy), _magnetism_speed.y * delta) * sign(dy)

	position_3d.x += move_x
	position_3d.y += move_y
	_update_visual_position()

func set_magnetism(pos: Vector2, spe: Vector2, time: float, state: BodyState = BodyState.SUPER_ARMOR):
	_magnetism_pos = pos
	_magnetism_speed = spe
	_magnetism_time = time
	_magnetism_state = state

# ============================================
# 全局吸附处理（多吸附共存）
# ============================================

## 每帧处理所有全局吸附：检测范围内吸附并施加吸力
## 吸附到期后自动从追踪中清理
func _process_global_magnetisms(delta: float):
	if not main or not "global_magnetisms" in main:
		return
	
	var g_mags: Array = main.global_magnetisms
	if g_mags.is_empty():
		# 列表为空时清空所有追踪
		if not _active_global_mag_names.is_empty():
			_active_global_mag_names.clear()
		return
	
	var pos2d = Vector2(position_3d.x, position_3d.y)
	var active_this_frame: Array[String] = []
	
	for mag in g_mags:
		var mag_name: String = mag.name
		# 检查实体是否在吸附范围内
		if not main.is_pos_in_magnetism_range(pos2d, mag):
			continue
		# 检查阵营是否允许被吸入
		if not main.is_team_affected_by_magnetism(team_id, mag):
			continue
		# 检查吸附强度：低于实体当前 body_state 则吸附无效
		var mag_state: int = int(mag.get("state", -1))
		if mag_state >= 0 and mag_state < body_state:
			continue
		# 检查无敌：默认吸附无敌实体（替身无敌除外），false=不吸无敌
		if not mag.get("mag_inv", true) and (is_invincible or custom_invincible):
			continue
		
		active_this_frame.append(mag_name)
		
		var center: Vector2 = mag.center
		var force: Vector2 = mag.force
		
		# 计算到中心点的距离
		var dx = center.x - position_3d.x
		var dy = center.y - position_3d.y
		
		# 按吸力移动，但不超过剩余距离
		var move_x = min(abs(dx), force.x * delta) * sign(dx)
		var move_y = min(abs(dy), force.y * delta) * sign(dy)
		
		position_3d.x += move_x
		position_3d.y += move_y
	
	# 更新全局吸附追踪（防止已被移除的吸附残留）
	_active_global_mag_names = active_this_frame
	_update_visual_position()

## 清除指定名称的全局吸附追踪（吸附被外部移除时调用）
func _clean_global_magnetism(mag_name: String):
	var idx = _active_global_mag_names.find(mag_name)
	if idx != -1:
		_active_global_mag_names.remove_at(idx)

func _process_immobilize(delta):
	# 跟随模式必须在时间判空之前更新：time == -1 表示常驻，同样要跟着施术者移动
	_update_immobilize_follow()
	if _immobilize_time == -1:
		return
	
	_immobilize_time -= delta
	
	if _immobilize_time <= 0:
		stop_immobilize()

## 跟随位置模式：每帧按施术者的实时位置与朝向重算被抓者的位置与释放点。
## 固定位置模式（参照实体为空）什么都不做，保持既有行为。
##
## 这里刻意不动被抓者的朝向。朝向是作者的事 —— madara_jie 这类抓取会用 turn_entity
## 每帧把被抓者转向施术者，而 when_modifier_update 比 _process_immobilize 晚跑，
## 本函数若也写朝向就会在"抓取结束的那一帧"抢到最后一次写入：那时施术者的
## turn_entity 已经不再触发，被抓者就会带着施术者的朝向落地，看起来像"朝向变回去了"。
func _update_immobilize_follow():
	var caster := _immobilize_follow_caster
	if not is_instance_valid(caster):
		return
	var f := caster.facing_direction
	var c := caster.position_3d
	set_position_3d(_immobilize_wall_fix(Vector3(
		c.x + _immobilize_follow_pos.x * f,
		c.y + _immobilize_follow_pos.y,
		c.z + _immobilize_follow_pos.z)))
	# 释放点跟着走：释放时按施术者当时的位置与朝向落地，而不是抓取瞬间那个点
	_immobilize_release_position = _immobilize_wall_fix(Vector3(
		c.x + _immobilize_follow_rpos.x * f,
		c.y + _immobilize_follow_rpos.y,
		c.z + _immobilize_follow_rpos.z))
	# 释放速度的横向分量随朝向翻，竖直分量与朝向无关
	_immobilize_knockback = Vector2(_immobilize_follow_kv.x * f, _immobilize_follow_kv.y)

## 抓取点位的出墙修正。跟随模式下「被举的位置」与「释放点」都是拿施术者当前坐标加偏移算出来的，
## 施术者贴墙时这两个点会落进墙体：被抓者当场被画进墙里，释放瞬间又会直接落在墙内，而且
## _last_valid_wall_pos 会跟着被标成墙内坐标，连 out_wall() 的 RETURN 回退都失效（回退目标就是墙内那个点）。
## 固定位置模式也可能因为作者给的坐标本身就贴墙，所以在赋值处再兜一次。
## enable_wall_collision 为假的实体本就无视墙，原样返回。
func _immobilize_wall_fix(pos: Vector3) -> Vector3:
	return get_out_of_wall(pos) if enable_wall_collision else pos

func set_immobilize(pos: Vector3, time: float = -1, rpos: Vector3 = pos,
					ani: String = "",
					kv: Vector2 = Vector2.ZERO, knockback_time: float = 0,
					launch: float = 0, launch_g: float = 730,
					state: BodyState = BodyState.SUPER_ARMOR,
					can_substitute: bool = false,
					visuals_rotation: float = 0.0,
					release_ani: String = "",
					follow_caster: EntityBase = null):
	
	if _immobilize_active: return
	
	if state < body_state:
		return
	
	_stop_knockback()       # 停止并清空击退速度（解决Y轴漂移）
	_magnetism_time = 0     # 清除吸附状态（解决Y轴被拉扯）
	stop_slide()            # 停止滑动
	is_attacking = false    # 清除攻击状态，防止后续朝向/移动逻辑错乱
	current_attack = ""
	
	play_animation(ani)
	
	_immobilize_active = true
	
	_stop_launch()
	set_position_3d(pos)
	_immobilize_release_position = rpos
	_immobilize_time = time
	_immobilize_launch = launch
	_immobilize_launch_gravity = launch_g
	_immobilize_knockback = kv
	_immobilize_knockback_time = knockback_time
	_immobilize_can_substitute = can_substitute
	_immobilize_release_ani = release_ani
	
	# ---- 抓取模式 ----
	# 传了参照实体就是「跟随位置」：把世界坐标换算成相对施术者的偏移。
	# 图形化脚本给的 pos 形如 now_pos3d()+Vector3(dx*now_dir(), dy, dz)，横向已经带了朝向符号，
	# 这里乘一次朝向把符号消掉，之后每帧按施术者当前朝向乘回来 —— 施术者转身时被抓者跟着翻面。
	_immobilize_follow_caster = follow_caster
	if is_instance_valid(follow_caster):
		var f: int = follow_caster.facing_direction
		var c: Vector3 = follow_caster.position_3d
		_immobilize_follow_pos = Vector3((pos.x - c.x) * f, pos.y - c.y, pos.z - c.z)
		_immobilize_follow_rpos = Vector3((rpos.x - c.x) * f, rpos.y - c.y, rpos.z - c.z)
		# 击退速度的 x 本来就是「面向前方为正」的口径，释放时再乘朝向
		_immobilize_follow_kv = kv
		_update_immobilize_follow()
	
	# visuals 旋转（弧度）
	if visuals_node:
		_saved_visuals_rotation = visuals_node.rotation
		_immobilize_visuals_rotation = visuals_rotation
		visuals_node.rotation = visuals_rotation
	
	save_hit_stop()

func stop_immobilize():
	if have_modifiers("customBodyState"):
		set_modifiers("customBodyState", BodyState.NORMAL, 0)
	position_3d = _immobilize_wall_fix(_immobilize_release_position)
	if position_3d.z <= ground_level:
		position_3d.z = ground_level
	_last_valid_wall_pos = Vector2(position_3d.x, position_3d.y)
	_immobilize_active = false
	_immobilize_release_active = true
	_immobilize_follow_caster = null   # 释放后不再跟随，免得残留引用被下一帧读到
	
	# 恢复 visuals 旋转
	if visuals_node:
		visuals_node.rotation = _saved_visuals_rotation
	
	var is_downed = (_launch_active and get_is_low_floating()) or _is_downed
	# 释放动画：作者填了就用作者的，空则沿用原来的 launch1/launch2
	var ani: String = _immobilize_release_ani
	if ani == "":
		ani = "launch1" if is_downed else "launch2"
	set_launch(_immobilize_launch, ani, _immobilize_launch_gravity)
	set_knockback(_immobilize_knockback, _immobilize_knockback_time)

func get_launch_velocity_z():
	if _hit_stop_active:
		return _saved_launch_velocity_z
	return _launch_velocity_z

func save_hit_stop():
	# 保存所有速度状态
	_saved_velocity_3d = velocity_3d
	_saved_slide_velocity = slide_velocity
	_saved_knockback_velocity = _knockback_velocity
	_saved_launch_velocity_z = _launch_velocity_z
	_saved_z_velocity_override = z_velocity_override

func set_hit_stop(duration: float, freeze_frame: bool = true, prevent_physics: bool = true, delay: float = 0.0):
	"""设置卡肉时间 - 冻结所有运动，结束后继续
	delay 大于 0 时不当场进卡肉，先登记一条待触发记录，等 delay 秒后再按同一套流程进。
	待触发记录（以及已经触发的那一次延迟减帧）由 clear_temporary_status 清除。"""
	if delay > 0.0:
		_hit_stop_pending.append({
			"duration": duration,
			"freeze_frame": freeze_frame,
			"prevent_physics": prevent_physics,
			"delay": delay,
		})
		return
	_begin_hit_stop(duration, freeze_frame, prevent_physics, false)

## 真正进入卡肉。direct 路径与延迟减帧到期后都走这里，参数口径完全一致。
func _begin_hit_stop(duration: float, freeze_frame: bool, prevent_physics: bool, from_delay: bool):
	_hit_stop_active = true
	_hit_stop_timer = duration
	_hit_stop_freeze_frame = freeze_frame
	_hit_stop_prevent_physics = prevent_physics
	_hit_stop_from_delay = from_delay
	
	save_hit_stop()
	
	if not get_animator_node() or get_animation_speed_scale() > 0.01:
		_saved_animation_speed = get_animation_speed_scale() if get_animator_node() else 1.0
	
	# 冻结动画（降速到接近0，视觉上冻结但逻辑继续）
	if freeze_frame and get_animator_node():
		set_animation_speed_scale(0.001)
	
	if debug_slide:
		print("[卡肉] 冻结 | 保存速度: xy=%s, z=%.1f, slide=%s, launch_z=%.1f" % [
			str(_saved_velocity_3d), 
			_saved_velocity_3d.z,
			str(_saved_slide_velocity),
			_saved_launch_velocity_z
		])

func _process_hit_stop(delta: float):
	"""处理卡肉状态 - 完全冻结，不更新任何物理"""
	# 卡肉期间：所有速度归零（位置不变）
	velocity_3d = Vector3.ZERO
	velocity = Vector2.ZERO
	slide_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_launch_velocity_z = 0.0
	z_velocity_override = 0.0
	
	if _hit_stop_timer > 0:
		_hit_stop_timer -= delta
		if _hit_stop_timer <= 0:
			_end_hit_stop()
	
	# 不调用 move_and_slide，位置完全冻结

## 推进延迟减帧。每条记录各自计时，delay 走完就按登记时的参数进卡肉。
##
## 调用点在 _physics_process 的卡肉早退分支之后，所以卡肉期间延迟不流逝：
## 被别的攻击减帧冻住的这段时间里，本实体的延迟减帧也跟着一起停。
## 多条记录到期时按登记顺序依次触发，后触发的那条覆盖前一条的参数（与连续调用 set_hit_stop 同义）。
func _process_pending_hit_stops(delta: float) -> void:
	if _hit_stop_pending.is_empty():
		return
	var fired: Array = []
	var remaining: Array = []
	for rec in _hit_stop_pending:
		rec["delay"] = float(rec["delay"]) - delta
		if rec["delay"] > 0.0:
			remaining.append(rec)
		else:
			fired.append(rec)
	# 先换掉队列再触发：触发路径本身不会再往队列里塞东西，但先把状态摆正更稳
	_hit_stop_pending = remaining
	for rec in fired:
		_begin_hit_stop(rec["duration"], rec["freeze_frame"], rec["prevent_physics"], true)

func _end_hit_stop():
	"""结束卡肉 - 恢复所有运动状态"""
	_hit_stop_active = false
	_hit_stop_from_delay = false
	_consume_local_buffer()
	_hit_stop_timer = 0.0
	
	# 恢复动画速度
	if get_animator_node() and _hit_stop_freeze_frame:
		set_animation_speed_scale(_saved_animation_speed)
	
	# 恢复所有速度状态
	velocity_3d = _saved_velocity_3d
	slide_velocity = _saved_slide_velocity
	_knockback_velocity = _saved_knockback_velocity
	_launch_velocity_z = _saved_launch_velocity_z
	z_velocity_override = _saved_z_velocity_override
	
	# 恢复各系统激活状态（如果之前有速度）
	if slide_velocity.length() > 0:
		is_sliding = true
	if _knockback_velocity.length() > 0:
		_knockback_active = true
	if abs(_launch_velocity_z) > 0:
		_launch_active = true
	
	if debug_slide:
		print("[卡肉] 解冻 | 恢复速度: xy=%s, z=%.1f, slide=%s, launch_z=%.1f" % [
			str(velocity_3d),
			velocity_3d.z,
			str(slide_velocity),
			_launch_velocity_z
		])

func is_hit_stopped() -> bool:
	"""检查是否正在卡肉"""
	return _hit_stop_active

func get_hit_stop_time_left() -> float:
	"""获取剩余卡肉时间"""
	return _hit_stop_timer if _hit_stop_active else 0.0

func force_end_hit_stop():
	"""强制结束卡肉"""
	if _hit_stop_active:
		_end_hit_stop()

func _process_launch(delta):
	if not _launch_active: return
	if _hit_stop_active: return
	if _immobilize_active: return
	
	# 倒地状态：只处理计时器，不处理物理
	if _is_downed:
		_process_downed_state(delta)
		return
	
	# 物理阶段：更新位置和速度
	if _current_launch_phase != "getup":
		position_3d.z += 2 * _launch_velocity_z * delta
		# 记录"真的离过地"（倒地清零击退的判据，见 _start_downed）
		if position_3d.z > ground_level + 1.0:
			_launch_left_ground = true
		if protection_effect == ProtectionEffect.FALL_SPEED:
			# 旧模式：保护值加快下落（等效于原式 `重力*delta*1 + 0.38*保护值`）
			_launch_velocity_z -= _launch_gravity * delta + 0.38 * calculate_protection_value(float(cumulative_launch_damage) / hp_max)
		else:
			# 新模式：下落速度不受保护值影响
			_launch_velocity_z -= _launch_gravity * delta
	
	# 动画计时器（所有阶段）
	if _launch_anim_timer > 0:
		_launch_anim_timer -= delta
		if _launch_anim_timer <= 0:
			_on_launch_anim_finished()
	
	# 落地检测（只在非起身阶段）
	if _current_launch_phase != "getup":
		if position_3d.z <= ground_level and _launch_velocity_z <= 0:
			OTGp_downed_flag = 1
			if not _has_bounced and abs(_launch_velocity_z) > 100.0 and calculate_protection_value(float(cumulative_launch_damage) / hp_max) < 0.15:
				_trigger_bounce()
			elif _has_bounced:
				# 第二次落地，进入倒地状态
				_start_downed()
			else:
				# 第一次落地但速度不够弹起，直接倒地
				_start_downed()
	
	if _current_launch_phase == "getup":
		_check_getup_animation_finished()

func _start_downed():
	"""开始倒地状态"""
	# 倒地清零水平击退（"倒地即停"，对齐唤境 躺 + 停止移动）。
	# 只在本次击飞真的离过地时才清：零上抛的扫地（zv≈0）会在写入击退的同一帧
	# 就走到这里，若在此清零就等于"扫地打不动人"。
	if clear_knockback_on_downed and _launch_left_ground:
		_stop_knockback()
		knockback_active = false
	
	_is_downed = true
	_downed_timer = _downed_duration
	position_3d.z = ground_level
	_launch_velocity_z = 0.0
	is_grounded = true
	
	# 播放倒地动画
	_play_launch_anim("downed", -1)
	_current_launch_phase = "downed"
	
	if OTGp_cLaunch_hp > OTGp_fLaunch_hp * OTGp_threshold_value:
		_process_downed_state(114514)
		return
	
	if debug_z_axis:
		print("[击飞] 开始倒地，持续 %.2f 秒" % _downed_duration)

func _process_downed_state(delta):
	"""处理倒地状态"""
	if _downed_timer > 0:
		_downed_timer -= delta
	if _downed_timer <= 0:
		# 倒地时间结束，开始起身
		_start_getup_from_downed()

func _start_getup_from_downed():
	"""从倒地状态起身"""
	if hp <= 0:
		if not is_dead:
			is_dead = true
			_on_death()
			var mat = get_anim_material()
			var tween = create_tween()
			# 0 -> 1 变白
			tween.tween_method(func(val): mat.set_shader_parameter("whitening", val), 0.0, 1.0, 0.0)
			tween.tween_interval(0.3)
			# 1 -> 0 恢复
			tween.tween_method(func(val): mat.set_shader_parameter("whitening", val), 1.0, 0.0, 0.0)
	else:
		_is_downed = false
		_downed_timer = 0.0
		_start_getup()

func _check_getup_animation_finished():
	"""检测起身动画是否播放完毕"""
	if not get_animator_node():
		return
	
	# 检测是否还在播放 getup
	if get_current_animation() != "getup":
		_on_launch_anim_finished()
		return
	
	# 检测是否播放到最后一帧
	var frame_count = get_animation_frame_count("getup")
	if get_current_frame() >= frame_count - 1:
		_on_launch_anim_finished()

func _trigger_bounce():
	_has_bounced = true
	var bounce_speed = abs(_launch_velocity_z) * _bounce_dampening
	_launch_velocity_z = bounce_speed
	position_3d.z = ground_level + 5.0
	
	_play_launch_anim("launch2", 0.1)
	_current_launch_phase = "bounce"
	
	if debug_z_axis:
		print("[击飞] 第一次弹地，速度: %.1f" % bounce_speed)

func _on_launch_anim_finished():
	"""动画阶段切换"""
	match _current_launch_phase:
		"launch1":
			_play_launch_anim("launch_e", 0.1)
			_current_launch_phase = "launch_e"
		
		"launch_e":
			_play_launch_anim("launched", 0.1)
			_current_launch_phase = "launched"
		
		"bounce":
			_play_launch_anim("launch_e", 0.1)
			_current_launch_phase = "launched"
		
		"getup":
			# 起身完成，真正结束
			is_invincible = false
			set_substitution_invincibility(1.5)
			_end_launch_sequence()  # 现在才结束
			clear_temporary_status()

func clear_temporary_status():
	stop_free_move()
	is_attacking = false
	current_attack = ""
	launched_flag = false
	cumulative_launch_damage = 0
	OTGp_downed_flag = 0
	OTGp_fLaunch_hp = 1145141919810
	OTGp_cLaunch_hp = 0
	launched_combo_cnt = 0
	_immobilize_release_active = false
	calculate_protection_value(0)
	_force_land_and_reset()
	# 延迟减帧：还没到期的记录整体丢掉；已经触发的那一次也一并结束，
	# 免得清完临时状态之后还残留一段延迟减帧把实体冻着。
	# 直接调 set_hit_stop 进来的减帧不归这里管，_hit_stop_from_delay 为假时不碰。
	_hit_stop_pending.clear()
	if _hit_stop_active and _hit_stop_from_delay:
		force_end_hit_stop()
	if have_modifiers("customBodyState"):
		set_modifiers("customBodyState", BodyState.NORMAL, 0)
	# 可被清除的效果放最后结束：上面那行把 customBodyState 重置成待收尾状态，
	# 若它自己也勾了可被清除，在这里一次收干净，不会先收尾、再被复活成第二次结束。
	_clear_clearable_modifiers()

func _force_land_and_reset():
	# 位置重置
	position_3d.z = ground_level
	
	# 所有速度清零
	velocity_3d = Vector3.ZERO
	velocity = Vector2.ZERO
	velocity_smoothed = Vector2.ZERO
	
	# 状态重置
	_launch_active = false
	_launch_velocity_z = 0.0
	_has_bounced = false
	_launch_left_ground = false
	_current_launch_phase = ""
	_is_downed = false
	_downed_timer = 0.0
	_waiting_for_land = false
	apply_z_impulse(0)
	_update_visual_position()
	is_grounded = true

func _end_launch_sequence(b: bool = true):
	"""真正结束击飞系统"""
	_launch_active = false
	_launch_velocity_z = 0.0
	_launch_anim_timer = 0.0
	_has_bounced = false
	_current_launch_phase = ""
	_is_downed = false  # 确保倒地状态被清除
	_downed_timer = 0.0
	
	if b:
		play_animation("idle")
	
	if hit_stun <= 0:
		knockback_active = false
	
	_stop_launch()
	
	if debug_z_axis:
		print("[击飞] 完全结束，恢复idle")

func _play_launch_anim(anim_name: String, duration: float):
	"""播放击飞动画
	duration: >0 表示固定时间，-1 表示不自动切换（等物理或动画结束）
	"""
	if _immobilize_active: return
	
	if not get_animator_node():
		return
	
	if has_animation(anim_name):
		play_animation(anim_name)
		_launch_anim_timer = duration
	else:
		# 动画不存在，直接跳过
		push_warning("动画不存在: " + anim_name)
		_launch_anim_timer = 0.01  # 立即触发下一帧切换

func _start_getup():
	"""开始起身"""
	_launch_velocity_z = 0.0
	position_3d.z = ground_level
	is_grounded = true
	_is_downed = false  # 确保倒地状态被清除
	# 起身清除效果：清掉上一次击退残留的水平速度/计时，
	# 否则起身动画期间（以及起身结束后）角色仍会被旧击退推着滑动
	_stop_knockback()
	knockback_active = false
	
	_play_launch_anim("getup", -1)
	_current_launch_phase = "getup"
	is_invincible = true
	_launch_anim_timer = 0
	
	if debug_z_axis:
		print("[击飞] 开始起身")

# 设置击飞
func set_launch(velocity_z: float, launch_anim: String = "launch1", custom_gravity: float = -1.0, launch_pause = "launch1"):
	if _immobilize_active: return
	
	# 扫地保户计算
	if launched_combo_cnt == 0:
		OTGp_fLaunch_hp = hp
		OTGp_cLaunch_hp = 0
	launched_combo_cnt += 1
	if OTGp_downed_flag > 0:OTGp_downed_flag += 1
	
	_launch_velocity_z = velocity_z
	_has_bounced = false
	# 每次击飞序列开始时重判"是否离过地"：从空中被打（z 已经很高）算离地，
	# 地面上零上抛的扫地则不算 —— 见 _start_downed 的倒地清零判据。
	_launch_left_ground = position_3d.z > ground_level + 1.0
	
	# 强制设置重力，确保生效
	_launch_gravity = 730.0  # 默认值
	if custom_gravity > 0:
		_launch_gravity = custom_gravity
	
	_launch_active = true
	is_grounded = false
	knockback_active = true
	
	# 重置倒地状态，确保能再次被击飞
	_is_downed = false
	_downed_timer = 0.0
	
	var initial_anim = launch_anim if launch_anim != "" else "launch1"
	_play_launch_anim(initial_anim, 0.1)
	_current_launch_phase = launch_pause
	
	save_hit_stop()
	
	# 调试确认重力值
	if debug_z_axis:
		var peak_height = (velocity_z * velocity_z) / (2 * _launch_gravity)
		print("[击飞] 开始 | 初速:%.1f | 重力:%.1f | 预估高度:%.1f" % [
			velocity_z, _launch_gravity, peak_height
		])

# 停止击飞（强制结束）
func _stop_launch():
	"""强制停止"""
	_launch_active = false
	_launch_velocity_z = 0.0
	_launch_anim_timer = 0.0
	_has_bounced = false
	_current_launch_phase = ""
	_is_downed = false  # 清除倒地状态
	_downed_timer = 0.0
	_launch_left_ground = false
	position_3d.z = ground_level
	is_grounded = true
	
	if debug_z_axis:
		print("[击飞] 强制停止")

# 修改控制系统
func _control_system(delta):
	# 卡肉期间：不处理硬直计时，保持冻结前的状态
	if _hit_stop_active:
		return
	
	# 击飞期间
	if _launch_active:
		if hit_stun > 0:
			hit_stun -= delta
			if hit_stun < 0:
				hit_stun = 0
		return
	
	# 正常硬直
	if knockback_active and hit_stun <= 0 and current_animation != "substitution":
		if not _immobilize_active:
			play_animation("idle")
	
	knockback_active = false
	
	if hit_stun > 0:
		hit_stun -= delta
		knockback_active = true
	
	if hit_stun < 0:
		hit_stun = 0

# 输入处理
func _entity_input():
	if not is_player: return
	# 卡肉期间：不处理输入
	if _hit_stop_active: return
	if entry_action != EntryAction.NONE: return
	if not arena.battle_started:
		input_left = false
		input_right = false
		input_up = false
		input_down = false
		for i in range(9):
			inputs[i] = false
		return
	
	is_under_control = knockback_active or _launch_active
	
	if is_ai_controlled:
		# --- AI 虚拟输入注入 ---
		if _hit_stop_active: return
		if entry_action != EntryAction.NONE: return
		is_under_control = knockback_active or _launch_active
		
		# AI 按键上升沿 → 走与真实输入完全相同的门控（优先级判定 + 入队缓冲）
		# 分两步：先整体采样本帧上升沿并同步 prev，再统一派发。
		# 必须先同步 prev：handle_button_press 内部会回调 _entity_input() 造成重入，
		# 若边采样边派发，重入会把本帧后续按键的上升沿提前吃掉（丢按键）。
		var rising_slots: Array[int] = []
		for i in range(9):
			var want: bool = _virtual_inputs.buttons[i]
			if want and not _ai_prev_buttons[i]:
				rising_slots.append(i)
			_ai_prev_buttons[i] = want
		for i in rising_slots:
			var act: String = _action_for_slot(i)
			if act != "":
				handle_button_press(i, act, _get_action_priority(act))
		
		# 模拟技能槽按键 (直接注入 inputs 数组)
		for i in range(9):
			inputs[i] = handle_input_key_solo(_virtual_inputs.buttons[i], i)
	else:
		match entity_type:
			EntityType.PLAYER:
				handle_input_solo(0, "attack")
				handle_input_solo(1, "skill1")
				handle_input_solo(2, "skill2")
				handle_input_solo(3, "skill3")
				handle_input_solo(4, "substitution")
				handle_input_solo(5, "scroll")
				handle_input_solo(6, "summon")
				handle_input_solo(7, "subs1")
				handle_input_solo(8, "subs2")
			EntityType.ENEMY:
				handle_input_solo(0, "p2_a")
				handle_input_solo(1, "p2_s1")
				handle_input_solo(2, "p2_s2")
				handle_input_solo(3, "p2_s3")
				handle_input_solo(4, "p2_substitution")
				handle_input_solo(5, "p2_scroll")
				handle_input_solo(6, "p2_summon")
				handle_input_solo(7, "p2_subs1")
				handle_input_solo(8, "p2_subs2")
	
	_handle_input_spe()
	
	if is_under_control:
		return
	
	if is_ai_controlled:
		input_left = _virtual_inputs.move_left
		input_right = _virtual_inputs.move_right
		input_up = _virtual_inputs.move_up
		input_down = _virtual_inputs.move_down
	else:
		match entity_type:
			EntityType.PLAYER:
				if virtual_joystick and virtual_joystick.is_pressed:
					var joy_out = virtual_joystick.output
					input_left = joy_out.x < -0.03
					input_right = joy_out.x > 0.03
					input_up = joy_out.y < -0.03
					input_down = joy_out.y > 0.03
					move_intent = abs(joy_out)
					if move_intent.x > 0.3: move_intent.x = 1
					else: move_intent.x = 0.5
					if move_intent.y > 0.3: move_intent.y = 1
					else: move_intent.y = 0.5
				else:
					input_left = Input.is_action_pressed("move_left")
					input_right = Input.is_action_pressed("move_right")
					input_up = Input.is_action_pressed("move_up")
					input_down = Input.is_action_pressed("move_down")
					move_intent = Vector2.ONE
			EntityType.ENEMY:
				input_left = Input.is_action_pressed("p2_mL")
				input_right = Input.is_action_pressed("p2_mR")
				input_up = Input.is_action_pressed("p2_mU")
				input_down = Input.is_action_pressed("p2_mD")
				move_intent = Vector2.ONE

# 预输入处理

## 键盘上升沿的截获表。_input 只认这一张表，表外的键一概不管。
## 收全部动作名而不按 entity_type 分家：哪个消费者读哪个名字保持不变，
## 这次只补"点按不丢"，不改"哪个键归哪个实体"的既有映射。
const KEYBOARD_ACTIONS = [
	"attack", "skill1", "skill2", "skill3", "substitution", "scroll", "summon", "subs1", "subs2",
	"p2_a", "p2_s1", "p2_s2", "p2_s3", "p2_substitution", "p2_scroll", "p2_summon", "p2_subs1", "p2_subs2",
]

## 本帧收到的键盘上升沿（动作名 → true），由 _input 写入
var _key_edges: Dictionary = {}
## 本物理帧消费用的快照。在 _physics_process 开头换一次，
## 保证同一帧里 _record_inputs 与 inputs[] 两条路径看到的是同一个点按，且不会被提前清掉。
var _key_edges_tick: Dictionary = {}

## 键盘上升沿在事件到达的当下截获，不靠物理帧轮询。
## 为什么必须这样：_record_inputs 与 handle_input_solo 都在 _physics_process 里读
## Input.is_action_pressed。30Hz 下一次轮询相隔 33 毫秒，短于一个间隔的点按整帧都看不见。
## 触屏不受影响，它走 Control 的按下信号，本来就是事件驱动。
func _input(event):
	if not enable_keyboard_input:
		return
	if not (event is InputEventKey):
		return
	for action_name in KEYBOARD_ACTIONS:
		# is_action_pressed 默认不认长按的系统重复，正是要的上升沿
		if event.is_action_pressed(action_name):
			_key_edges[action_name] = true

func _record_inputs():
	if not enable_keyboard_input:
		return
	
	if not is_instance_valid(get_animator_node()) or hp <= 0:
		return
	
	var actions_to_check = {
		"attack": ActionPriority.NORMAL_ATTACK,
		"skill1": ActionPriority.SKILL,
		"skill2": ActionPriority.SKILL,
		"skill3": ActionPriority.ULTIMATE,
		"substitution": ActionPriority.SUBSTITUTION,
		"scroll": ActionPriority.SCROLL,
		"summon": ActionPriority.SUMMON
	}
	
	for action_name in actions_to_check:
		# 轮询负责「按住」，本帧快照负责「短点按」，两者取或
		if not Input.is_action_pressed(action_name) and not _key_edges_tick.has(action_name):
			continue
		# 键盘有两条路径，这里是第二条：直接入队，不经过 inputs[]。
		# 此前它一个闸门都不查，于是槽位在冷却、充能不足或被禁用时触屏按不了、
		# 键盘却能把它塞进缓冲并触发。这里与 _entity_input() 查同一个槽位判据。
		var slot_id := _slot_for_action(action_name)
		if slot_id >= 0 and not button_can_press(slot_id):
			continue
		_add_to_buffer(action_name, actions_to_check[action_name])

func handle_button_press(slot_id: int, action_name: String, priority: int) -> void:
	if slot_id >= 0 and slot_id < inputs.size():
		inputs[slot_id] = true
	
	if _can_execute_immediately(action_name, priority):
		_execute_action_by_slot(slot_id, action_name)
	else:
		_add_to_local_buffer(slot_id, action_name, priority)

# 判断能否立即执行动作（由 handle_button_press 调用）
func _can_execute_immediately(action_name: String, priority: int) -> bool:
	if hp <= 0 or _immobilize_active:
		return false
	if _hit_stop_active or _launch_active or _is_downed:
		return false
	if _is_executing_action and priority <= _current_action_priority:
		return false
	return true

# 通过槽位执行动作（由 handle_button_press 直接调用）
func _execute_action_by_slot(slot_id: int, action_name: String) -> void:
	_is_executing_action = true
	_current_action_priority = _get_action_priority(action_name)
	if slot_id >= 0 and slot_id < inputs.size():
		inputs[slot_id] = true
	_entity_input()

# 添加到本地缓冲（带优先级覆盖）
# 唯一入队入口：真实输入（触屏/键盘）与 AI 输入都走这里，共用同一套优先级/缓冲策略。
func _add_to_local_buffer(slot_id: int, action_name: String, priority: int) -> void:
	var highest = -1
	for cmd in _input_buffer:
		if cmd.priority > highest:
			highest = cmd.priority
	if priority > highest:
		_input_buffer = _input_buffer.filter(func(c): return c.priority >= priority)
	elif priority < highest:
		return
	# 移除相同动作的旧记录
	_input_buffer = _input_buffer.filter(func(c): return not (c.action == action_name))
	if _input_buffer.size() >= buffer_max_size:
		_input_buffer.pop_front()
	_input_buffer.append({
		"action": action_name,
		"priority": priority,
		"frame": _buffer_clock,
		"time": _buffer_time,
		"logic_frame": MatchConfig.logic_frame,
		"slot_id": slot_id
	})

# 消费本地缓冲（每帧 / 卡肉结束 / 动作结束时调用）
# 唯一消费者：真实输入与 AI 输入共用同一个缓冲队列与同一套消费策略。
func _consume_local_buffer() -> void:
	var now := _buffer_time
	# 时间戳是 _buffer_time（停帧与卡肉期间不流逝），不是引擎物理帧号，也不是墙钟
	_input_buffer = _input_buffer.filter(func(cmd): return now - float(cmd.get("time", now)) <= buffer_valid_seconds)
	if _input_buffer.is_empty():
		return
	# 槽位闸门。入队路径不止一条（触屏、键盘轮询、键盘直连入队、AI），
	# 可用性判据收在槽位自己的 _can_press() 上，消费端是最后一道，任何路径都绕不过。
	# 按不了的指令直接丢掉而不是留着：留着它会一直占住最高优先级，把后面能用的指令饿死。
	_input_buffer = _input_buffer.filter(func(cmd): return _command_slot_usable(cmd))
	if _input_buffer.is_empty():
		return
	# 找最高优先级
	var best = _input_buffer[0]
	for cmd in _input_buffer:
		if cmd.priority > best.priority or (cmd.priority == best.priority and cmd.frame < best.frame):
			best = cmd
	if _can_perform_action(best.action):
		# 中断当前动作
		if _is_executing_action and best.priority > _current_action_priority:
			_interrupt_current_action()
		# 槽位解析：入队时带了 slot_id 就直接用；
		# 键盘路径入队时没带 slot_id，这里按动作名补出槽位。
		var slot: int = int(best.get("slot_id", -1))
		if slot < 0:
			slot = _slot_for_action(best.action)
		_execute_action_by_slot(slot, best.action)
		# 清除刚执行的指令
		_input_buffer = _input_buffer.filter(func(c): return c.priority > best.priority)

## 动作名 → 技能槽位（与 _entity_input() 里 PLAYER 的槽位映射保持一致）
func _slot_for_action(action: String) -> int:
	match action:
		"attack": return 0
		"skill1": return 1
		"skill2": return 2
		"skill3": return 3
		"substitution": return 4
		"scroll": return 5
		"summon": return 6
		"subs1": return 7
		"subs2": return 8
	return -1

## 技能槽位 → 动作名（_slot_for_action 的逆映射，供 AI 按键接入统一门控时使用）
func _action_for_slot(slot_id: int) -> String:
	match slot_id:
		0: return "attack"
		1: return "skill1"
		2: return "skill2"
		3: return "skill3"
		4: return "substitution"
		5: return "scroll"
		6: return "summon"
		7: return "subs1"
		8: return "subs2"
	return ""

## 队列里的这条指令，它对应的槽位现在是否允许按下。判不出槽位的按放行处理。
func _command_slot_usable(cmd: Dictionary) -> bool:
	var slot: int = int(cmd.get("slot_id", -1))
	if slot < 0:
		slot = _slot_for_action(cmd.action)
	if slot < 0 or slot >= skill_slot.size():
		return true
	return button_can_press(slot)

func _add_to_buffer(action: String, priority: int):
	# 计算缓冲区中最高优先级
	var highest_priority = -1
	for cmd in _input_buffer:
		if cmd.priority > highest_priority:
			highest_priority = cmd.priority
	
	# 新指令优先级更高 ⇒ 清除所有比它低的指令
	if priority > highest_priority:
		_input_buffer = _input_buffer.filter(func(cmd): return cmd.priority >= priority)
	# 新指令优先级低于已有最高 ⇒ 不添加
	elif priority < highest_priority:
		return
	
	# 同优先级：移除旧同名记录
	_input_buffer = _input_buffer.filter(func(cmd): return cmd.action != action)
	
	if _input_buffer.size() >= buffer_max_size:
		_input_buffer.pop_front()
	
	_input_buffer.append({
		"action": action,
		"priority": priority,
		"frame": _buffer_clock,
		"time": _buffer_time,
		"logic_frame": MatchConfig.logic_frame
	})

func _can_perform_action(action: String) -> bool:
	if hp <= 0: 
		return false
	
	# 定身时允许替身的特殊处理
	if _immobilize_active:
		if action == "substitution":
			return _immobilize_can_substitute and has_substitution() and not _hit_stop_active
		return false
	
	if action == "substitution":
		return is_under_control and has_substitution() and not _hit_stop_active
	
	if _hit_stop_active or _launch_active or _is_downed:
		return false
	
	if _is_executing_action:
		var new_prio = _get_action_priority(action)
		return new_prio >= _current_action_priority
	
	return true

func _interrupt_current_action():
	clear_attack_state()
	stop_slide()
	_stop_knockback()
	_stop_launch()
	_is_executing_action = false
	_current_action_priority = ActionPriority.NORMAL_ATTACK
	if debug_slide:
		print("[预输入] 中断当前动作")

func _on_action_finished():
	_is_executing_action = false
	_current_action_priority = ActionPriority.NORMAL_ATTACK
	_consume_local_buffer()

func button_can_press(slot_id):
	# 没有对应槽位的实体（子实体等）没有可用性可言，按可按下处理，顺带避免越界
	if slot_id < 0 or slot_id >= skill_slot.size():
		return true
	# 只有真正绑定了 SkillPanel 的实体才拿面板当闸门。
	# 非操控者的 skill_slot 是 NullSlot 存根，_can_press() 恒为 false，
	# 一旦用它当闸门，该实体的 inputs[] 就再也置不起来，按键、连招与派生窗口全部失效。
	# 判据用「绑定是不是真实面板」而不是「是不是当前操控者」，
	# 这样 current_controller_name 与 skill_slot 绑定不会各说各话。
	if entity_type == EntityType.PLAYER and _binds_real_skill_panel(slot_id):
		return skill_slot[slot_id]._can_press()
	else:
		# 非真实面板的实体判不了面板状态，按同一套规则查实体自己的冷却表与槽位字段
		var can_press = true
		if skill_slot[slot_id].disabled:
			can_press = false
		var cd_id = get_slot_cd(slot_id)
		if cd_id >= 0 and cool_down_time[cd_id]["time"] > 0:
			can_press = false
		if skill_slot[slot_id].is_charging and skill_slot[slot_id].dot <= 0:
			can_press = false
		return can_press

func _binds_real_skill_panel(slot_id) -> bool:
	"""当前 skill_slot[slot_id] 是否就是真实 SkillPanel 槽位，而非 NullSlot 存根"""
	if slot_id < 0: return false
	if slot_id >= skill_slot.size() or slot_id >= _real_skill_slots.size(): return false
	return skill_slot[slot_id] == _real_skill_slots[slot_id]

func get_slot_cd(slot_id):
	for i in cool_down_time.size():
		if cool_down_time[i]["slot_id"] == slot_id:
			return i
	return -1

func handle_input_key_solo(pressed: bool, slot_id: int):
	if is_player:
		if inputs[slot_id]:
			return pressed
		else:
			if button_can_press(slot_id):
				return pressed
		return false

func handle_input_solo(slot_id: int, action: String):
	if not is_player:
		return
	var use_touch = self.name == MatchConfig.current_controller_name
	# 本帧的键盘上升沿等同「按住一次」：短点按在两次轮询之间松开时 inputs[] 也要置起来，
	# 否则图形化脚本的 when_press_input 看不到这次按键
	var key_pressed: bool = Input.is_action_pressed(action) or _key_edges_tick.has(action)
	inputs[slot_id] = compare_input_solo(handle_input_key_solo(key_pressed, slot_id), use_touch and skill_slot[slot_id]._button_pressed and skill_slot[slot_id].is_finger_inside())

func compare_input_solo(k: bool, b: bool) -> bool:
	if self.name == MatchConfig.current_controller_name:
		return k or b
	match entity_type:
		EntityType.PLAYER:
			return k or b
	return k

# 击退处理
func _process_knockback(delta):
	if not _knockback_active: return
	if _immobilize_active: return
	if _hit_stop_active: return
	
	# 应用击退速度
	position_3d.x += _knockback_velocity.x * delta
	position_3d.y += _knockback_velocity.y * delta
	
	# 新版逻辑：地面使用击退阻力，空中使用独立的空中阻力（默认0=无阻力，速度不衰减）
	var current_resistance = _knockback_resistance
	if not is_grounded:
		current_resistance = _knockback_air_resistance
	
	if _knockback_linear:
		# 线性模型（新公式）：地面吃 kr、空中吃 ar，都是恒定减速度 a = v0·r/2。
		#   停下用时 2/r、总滑行距离 v0²/(2a) = v0/r，与旧公式的指数衰减总距离完全一致
		#   —— 只改减速曲线的形状，不改距离。
		#   ar = 0 时空中不衰减（全程匀速滑到落地），用作"被一路推着走"的表达。
		var decel: float = _knockback_initial_speed * current_resistance * 0.5
		if decel > 0.0:
			_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, decel * delta)
	else:
		# 旧版逻辑（指数衰减）
		_knockback_velocity = _knockback_velocity.lerp(Vector2.ZERO, current_resistance * delta)
	
	# 减少击退时间
	_knockback_timer -= delta
	
	# 检查是否结束击退
	if _knockback_velocity.length() < 5.0:
		_stop_knockback()

# 开始击退
func set_knockback(velocity: Vector2, duration: float, resistance: float = -1.0, air_resistance: float = 0.0, linear: bool = false):
	if _immobilize_active: return
	
	"""开始击退，不影响控制状态
	
	参数:
		velocity: 初始击退速度
		duration: 击退持续时间（秒）
		resistance: 地面阻力系数（默认10.0，越大停得越快）
		air_resistance: 空中阻力系数（默认0，越大停得越快）
		linear: true=线性匀减速模型（新，地面 kr / 空中 ar 都生效），false=指数衰减（旧，默认）
	"""
	_knockback_velocity = velocity
	_knockback_timer = duration
	_knockback_linear = linear
	_knockback_initial_speed = velocity.length()
	
	if resistance > 0:
		_knockback_resistance = resistance
	_knockback_air_resistance = air_resistance
	
	_knockback_active = true
	
	if debug_slide:
		print("[击退] 开始 | 速度:%s | 时长:%.2f | 阻力:%.1f | 空中阻力:%.1f" % [
			str(velocity), duration, _knockback_resistance, _knockback_air_resistance
		])

# 停止击退
func _stop_knockback():
	_knockback_active = false
	_knockback_velocity = Vector2.ZERO
	_knockback_timer = 0.0
	
	if debug_slide:
		print("[击退] 结束")

# 获取击退状态
func is_knockback_active() -> bool:
	return _knockback_active

func get_knockback_velocity() -> Vector2:
	return _knockback_velocity

func set_hit_stun(stun_time: float, stun_ani: String):
	if _immobilize_active: return
	
	play_animation(stun_ani)
	knockback_active = true
	hit_stun = stun_time

func _register_depth_sort():
	set_meta("sort_by_depth", true)
	set_meta("depth_priority", depth_sort_priority)
	DepthManager.register_entity(self)

func _update_initial_depth():
	if not enable_depth_sort:
		return
	var base_z = int(position.y * 0.1)
	z_index = base_z + depth_sort_priority

func _update_depth():
	var depth_value = position.y
	if position_3d.z > 0:
		depth_value -= position_3d.z * 0.5
	var target_z = int(depth_value * 0.1) + depth_sort_priority
	if z_index != target_z:
		z_index = target_z

func set_depth_priority(priority: int):
	depth_sort_priority = priority
	set_meta("depth_priority", priority)
	_update_depth()

func _exit_tree():
	_is_quitting = true
	
	if enable_depth_sort:
		DepthManager.unregister_entity(self)
	# 清理动态攻击框（不绑定的挂在父节点上，需手动释放）
	if is_instance_valid(attack_box_manager):
		attack_box_manager.clear_dynamic_boxes()

func _deferred_team_setup():
	_update_team_registration(TeamManager.TeamID.NONE)
	if debug_team:
		print("[阵营] %s (节点名:%s) 加入阵营: %s" % [name, str(name), get_team_name()])

func _init_3d_position():
	position_3d.x = position.x
	position_3d.y = position.y
	position_3d.z = ground_level
	_last_valid_wall_pos = Vector2(position_3d.x, position_3d.y) # 新增这一行
	_update_visual_position()

func _setup_components():
	visuals_node = get_node_or_null("Visuals")
	shadow_node = get_node_or_null("Shadow")

func _load_frame_data():
	frame_data_path = entity_data.floder_path + "entity_frame_data.json" if entity_data else ""
	if frame_data_path == "" or not FileAccess.file_exists(frame_data_path):
		debug_show_hitboxes = false
		return
	
	var file = FileAccess.open(frame_data_path, FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	file.close()
	
	var data = json.data
	if data.has("animation_data"):
		for anim_name in data["animation_data"]:
			animation_frame_data[anim_name] = {}
			var anim_data = data["animation_data"][anim_name]
			for frame_str in anim_data:
				var frame_idx = int(frame_str)
				var frame_data = FrameData.new()
				frame_data.deserialize(anim_data[frame_str])
				animation_frame_data[anim_name][frame_idx] = frame_data
	else:
		debug_show_hitboxes = false

func _setup_hitboxes():
	pass

func _connect_signals():
	pass

# ============================================
# 攻击框系统
# ============================================

func _load_attack_box_data():
	if res_path == "":
		return
	
	var data_path = res_path.get_base_dir() + "/attack_boxes.json"
	if not FileAccess.file_exists(data_path):
		return
	
	var file = FileAccess.open(data_path, FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	file.close()
	
	var data = json.data
	if data.has("attack_boxes"):
		for box_dict in data["attack_boxes"]:
			var box = AttackBoxData.new()
			box.from_dict(box_dict)
			attack_box_manager.add_attack_box(box)
		print("[攻击框] 已加载 %d 个攻击框" % data["attack_boxes"].size())

func _on_attack_hit(hit_result: AttackBoxManager.HitResult):
	"""基础攻击命中回调（向后兼容）"""
	pass

func _on_attack_hit_detailed(hit_result: AttackBoxManager.HitResult):
	"""详细的攻击命中回调"""
	print("[攻击详细] %s 的 %s 命中 %s 的 %s[%d]" % [
		name,
		hit_result.attack_box_name,
		hit_result.target.name,
		hit_result.hitbox_name,
		hit_result.hitbox_index
	])
	
	# 打印受击框数据
	var shape_info = hit_result.get_hitbox_shape_info()
	print("  -> 受击框形状: %s | 位置: (%d, %d)" % [
		shape_info.shape_type,
		shape_info.position.get("x", 0),
		shape_info.position.get("y", 0)
	])
	
	# 调用旧版回调保持兼容
	await _on_attack_hit(hit_result)
	hit_result.target._on_deal_hit(self)

func get_attack_box_manager() -> AttackBoxManager:
	return attack_box_manager

# ---- 动态攻击框（脚本创建，不受动画帧驱动） ----

## 创建动态攻击框，pos/size 为相对实体根的 3D 偏移与大小；bind=是否跟随实体；duration<=0 表示常驻直到手动移除
## pos 口径：x 横向、y 前后深度、z 高度且正数向上，与图形化脚本其它 3D 坐标一致。
## size 口径：x 宽、y 深度、z 高。
## anims 非空时框的存活期绑在这些动画上：实体当前动画不在列表里时框立刻移除。
## 两条判据同时给出时都要满足，谁先到谁先移除；anims 为空则只看 duration。
func create_attack_box(box_name: String, pos: Vector3, size: Vector3, bind: bool = true, duration: float = 0.0,
		anims: PackedStringArray = PackedStringArray()) -> String:
	if not attack_box_manager:
		return ""
	return attack_box_manager.create_dynamic_box(box_name, pos, size, bind, duration, false, anims)

## 按框名再现已存在的攻击框（取首个匹配框的首帧配置）
## anims 与 create_attack_box 同一口径：非空时框只在这些动画播放期间存在。
func replay_attack_box(box_name: String, bind: bool = true, duration: float = 0.0,
		anims: PackedStringArray = PackedStringArray()) -> String:
	if not attack_box_manager:
		return ""
	return attack_box_manager.replay_dynamic_box(box_name, bind, duration, anims)

## 按框名移除所有匹配的动态攻击框
func remove_attack_box(box_name: String):
	if attack_box_manager:
		attack_box_manager.remove_dynamic_box_by_name(box_name)

func get_attack_box(box_id: String) -> AttackBoxData:
	if attack_box_manager:
		return attack_box_manager.get_attack_box(box_id)
	return null

func get_all_attack_boxes() -> Array[AttackBoxData]:
	if attack_box_manager:
		return attack_box_manager.get_all_attack_boxes()
	return []

# ============================================
# 阵营系统
# ============================================

func _update_team_registration(old_team: int):
	if old_team != TeamManager.TeamID.NONE:
		TeamManager.unregister_entity(self, old_team)
	
	_current_team = team_id
	if team_id != TeamManager.TeamID.NONE:
		TeamManager.register_entity(self, team_id)
		_update_hitbox_teams()
		team_changed.emit(team_id)

func _configure_hitbox_collision(hitbox: Area2D):
	hitbox.set_deferred("collision_layer", 0)
	hitbox.set_deferred("collision_mask", 0)
	hitbox.set_deferred("collision_layer", (1 << 12))
	match team_id:
		TeamManager.TeamID.PLAYER_1: hitbox.set_deferred("collision_mask", (1 << 11))
		TeamManager.TeamID.PLAYER_2: hitbox.set_deferred("collision_mask", (1 << 11))
		TeamManager.TeamID.PLAYER_3: hitbox.set_deferred("collision_mask", (1 << 11))
		TeamManager.TeamID.PLAYER_4: hitbox.set_deferred("collision_mask", (1 << 11))
		TeamManager.TeamID.ENEMY: hitbox.set_deferred("collision_mask", (1 << 11))
		TeamManager.TeamID.NEUTRAL: hitbox.set_deferred("collision_mask", (1 << 11))
		_: hitbox.set_deferred("collision_mask", (1 << 11))

func _update_hitbox_teams():
	for hitbox in hitbox_areas:
		_configure_hitbox_collision(hitbox)

func _on_hitbox_body_entered(body: Node2D):
	if body == self:
		return
	if not body.has_method("get_team_id"):
		return
	
	# 检查目标是否无敌
	if body.get_is_invincible():
		return  # 目标无敌，无视此次碰撞
	
	var target_team = body.get_team_id()
	
	if debug_team:
		print("[阵营] %s(%s) 击中 %s(%s)" % [name, get_team_name(), body.name, body.get_team_name()])
	
	#if TeamManager.can_damage(team_id, target_team):
		#_on_deal_hit(body)
	#else:
		#if debug_team:
			#print("[阵营] 伤害被阻止（同阵营或友好关系）")

func _on_hitbox_area_entered(area: Area2D):
	var parent = area.get_parent()
	if parent == self:
		return
	
	#if area.name.begins_with("AttackBox"):
		#if parent.has_method("get_team_id"):
			#var target_team = parent.get_team_id()
			#if TeamManager.can_damage(team_id, target_team):
				#_on_deal_hit(parent)

func _on_deal_hit(attacker: Node2D):
	if attacker is EntityBase:
		_last_attacker = attacker
	if debug_team:
		print("[战斗] %s 对 %s 造成伤害" % [attacker.name, name])
	deal_hit.emit(attacker)

func _on_death():
	"""虚方法，死亡时调用。由子类/VisualScriptComponent重写"""
	death.emit()
	pass

func get_team_id() -> int:
	return team_id

func get_team_name() -> String:
	return TeamManager.get_team_name(team_id)

func is_hostile_to(other: Node2D) -> bool:
	if other.has_method("get_team_id"):
		return TeamManager.is_hostile_to(team_id, other.get_team_id())
	return false

func is_friendly_to(other: Node2D) -> bool:
	if other.has_method("get_team_id"):
		return TeamManager.is_friendly_to(team_id, other.get_team_id())
	return false

func set_team(new_team: int):
	var old_team = team_id
	team_id = new_team
	_update_team_registration(old_team)
	
	if debug_team:
		print("[阵营] %s 切换阵营: %s -> %s" % [
			name, 
			TeamManager.get_team_name(old_team), 
			get_team_name()
		])

# ============================================
# Z轴系统
# ============================================

func _process_z_physics(delta):
	if _immobilize_active: return
	# 如果正在击飞，跳过正常的Z轴物理（除了落地检测）
	if _launch_active:
		# 只处理落地检测
		if position_3d.z <= ground_level:
			pass
			# _stop_launch()
			# 落地后继续正常物理
		else:
			# 击飞中，完全由_process_launch控制
			_update_visual_position()
			return
	
	# 原有的Z轴物理代码（击飞不激活时执行）
	if z_velocity_override != 0:
		velocity_3d.z = z_velocity_override
		# 滑行期间使用自定义 Z 阻力，否则使用默认值
		var z_res = _slide_z_resistance if _slide_z_resistance >= 0 else z_slide_resistance
		z_velocity_override = move_toward(z_velocity_override, 0, z_res * delta * 100)
		if abs(z_velocity_override) < 10:
			z_velocity_override = 0
	
	var current_gravity = gravity
	if _slide_gravity_active and _current_slide_gravity >= 0:
		current_gravity = _current_slide_gravity
	
	if not is_grounded:
		velocity_3d.z -= current_gravity * delta
		velocity_3d.z = max(velocity_3d.z, -max_fall_speed)
	
	var was_grounded = is_grounded
	position_3d.z += 2 * velocity_3d.z * delta
	
	if position_3d.z <= ground_level:
		position_3d.z = ground_level
		velocity_3d.z = 0
		z_velocity_override = 0.0  # 落地时清除残留的Z轴冲量
		is_grounded = true

		if _slide_gravity_active:
			_slide_gravity_active = false
			_current_slide_gravity = -1.0
			if debug_z_axis:
				print("[Z轴] 落地，重力恢复默认: %.2f" % gravity)
		
		if not was_grounded:
			_on_landed()
		
		if debug_z_axis and not was_grounded:
			print("[Z轴] 落地 | 位置: %.2f" % position_3d.z)
	else:
		# 位置高于地面 → 非地面状态，确保重力等正常生效
		# （修复 z_velocity_override 在 grounded 状态下推高实体但重力不生效的 bug）
		is_grounded = false
	
	_update_visual_position()

func set_slide_gravity(custom_gravity: float):
	if custom_gravity >= 0:
		_current_slide_gravity = custom_gravity
		_slide_gravity_active = true
		if debug_z_axis:
			print("[Z轴] 自定义重力启用: %.2f (默认: %.2f)" % [custom_gravity, gravity])
	else:
		_slide_gravity_active = false
		_current_slide_gravity = -1.0
		if debug_z_axis:
			print("[Z轴] 重力恢复默认: %.2f" % gravity)

func reset_slide_gravity():
	_slide_gravity_active = false
	_current_slide_gravity = -1.0
	z_velocity_override = 0

func get_current_gravity() -> float:
	if _slide_gravity_active and _current_slide_gravity > 0:
		return _current_slide_gravity
	return gravity

func _update_visual_position():
	"""将3D位置转换为2D世界坐标"""
	# 防止浮点漂移累积
	position_3d.y = snapped(position_3d.y, 0.001)
	position.x = position_3d.x
	# 关键：这里完成Y和Z的合并，子节点不再处理Z
	position.y = position_3d.y - position_3d.z
	
	if shadow_node:
		# 阴影在脚底，所以加回Z高度（相对于视觉节点的本地坐标）
		shadow_node.position = Vector2(0, position_3d.z)

func _on_landed():
	pass

func force_set_z_height(height: float):
	position_3d.z = height
	if height > ground_level:
		is_grounded = false
	_update_visual_position()

func apply_z_impulse(impulse: float):
	z_velocity_override = impulse
	is_grounded = false

func start_z_slide(speed: float, resistance: float = -1.0):
	"""Z 轴滑动：speed 沿高度方向滑动，resistance 为衰减阻力(-1 用默认)"""
	z_velocity_override = speed
	is_grounded = false
	if resistance >= 0:
		_slide_z_resistance = resistance

func stop_z_motion(slide: bool = true, fall: bool = true):
	"""停止 Z 轴运动：slide 停 Z 滑动，fall 停普通重力掉落"""
	if slide:
		z_velocity_override = 0.0
		_slide_z_resistance = -1.0
	if fall:
		velocity_3d.z = 0.0
		is_grounded = true

func get_z_height() -> float:
	return position_3d.z

func is_in_air() -> bool:
	return not is_grounded

# ============================================
# 滑动系统
# ============================================

func _setup_slide_sequences():
	pass

func _clear_slide_sequence():
	current_slide_sequence = []
	current_slide_index = -1

func _start_slide_sequence(anim_name: String):
	if slide_sequences.has(anim_name):
		current_slide_sequence = slide_sequences[anim_name]
		current_slide_index = -1
		slide_locked_facing = facing_direction

func _process_slide_sequence(anim_name: String, frame_idx: int):
	if current_slide_sequence.is_empty():
		return
	
	for i in range(current_slide_sequence.size()):
		var slide_cfg = current_slide_sequence[i]
		
		if slide_cfg.frame == frame_idx:
			var slide_dir: Vector2
			var dir_mode = slide_cfg.get("direction_mode", "facing")
			
			match dir_mode:
				"facing":
					slide_dir = Vector2(slide_locked_facing, 0)
				"-facing":
					slide_dir = Vector2(-slide_locked_facing, 0)
				"input":
					var input_x = Input.get_axis("move_left", "move_right")
					var input_y = Input.get_axis("move_up", "move_down")
					if input_x != 0 or input_y != 0:
						slide_dir = Vector2(input_x, input_y).normalized()
					else:
						slide_dir = Vector2(slide_locked_facing, 0)
				"locked":
					slide_dir = Vector2(slide_locked_facing, 0)
				_:
					slide_dir = Vector2(slide_locked_facing, 0)
			
			var z_speed = slide_cfg.get("z_speed", 0.0)
			var custom_gravity = slide_cfg.get("gravity", -1.0)
			
			if z_speed != 0:
				apply_z_impulse(z_speed)
			
			set_slide_gravity(custom_gravity)
			
			if slide_cfg.get("force_stop", false):
				stop_slide()
				if debug_slide:
					print("[%s] 第%d帧：强制停止滑动" % [anim_name, frame_idx])
				return
			
			current_slide_index = i
			start_slide(slide_cfg.speed, slide_dir, slide_cfg.resistance)
			
			if debug_slide:
				var gravity_display = custom_gravity if custom_gravity > 0 else gravity
				print("[%s] 第%d帧触发第%d段滑动 | XY速度:%.0f | Z速度:%.0f | 重力:%.0f | 方向:%s" % [
					anim_name, frame_idx, i + 1,
					slide_cfg.speed, z_speed, 
					gravity_display,
					dir_mode
				])

func start_slide(slide_speed: float, direction: Vector2 = Vector2.ZERO, resistance: float = -1):
	is_sliding = true
	
	if direction == Vector2.ZERO:
		direction = Vector2(facing_direction, 0)
	
	slide_velocity = direction.normalized() * slide_speed * final_speed
	
	if resistance >= 0:
		slide_resistance = Vector2(resistance, resistance)

func stop_slide():
	is_sliding = false
	slide_velocity = Vector2.ZERO
	velocity_3d.x = 0
	velocity_3d.y = 0
	velocity_smoothed = Vector2.ZERO
	z_velocity_override = 0.0  # 停止 Z 轴滑动
	_slide_z_resistance = -1.0

func modify_slide_velocity(delta_velocity: Vector2):
	slide_velocity += delta_velocity

func set_slide_resistance(resistance: float):
	slide_resistance = Vector2(max(0.1, resistance), max(0.1, resistance))

func is_currently_sliding() -> bool:
	return is_sliding

func get_slide_velocity() -> Vector2:
	return slide_velocity

func get_current_slide_info() -> Dictionary:
	if current_slide_index < 0 or current_slide_index >= current_slide_sequence.size():
		return {}
	return current_slide_sequence[current_slide_index]

# ============================================
# 帧事件系统
# ============================================

func _on_animation_changed():
	current_animation = get_current_animation()
	processed_frames.clear()
	_processed_effect_frames.clear()
	_last_processed_frame = -1  # 重置上一帧索引
	
	# 【修复卡帧】：强制使用新动画的第 0 帧进行同步，而不是等待引擎更新 frame 索引
	_apply_frame_data_forced(current_animation, 0)
	_apply_anchor_constraint()
	
	if slide_sequences.has(current_animation):
		_start_slide_sequence(current_animation)
	else:
		_clear_slide_sequence()
	_on_animation_enter(current_animation)
	
	# 注意：这里不再调用 _apply_frame_data()，因为上面已经强制应用了
	
	if attack_box_manager:
		attack_box_manager.reset_all_triggers()

func _on_frame_changed():
	# 卡肉期间：不处理帧变化事件
	if _hit_stop_active:
		return

	# 先应用帧数据
	_apply_frame_data()

	# 处理当前帧的帧事件（跳帧补偿由 _ensure_frame_sync 统一负责）
	_process_frame_event()

	# 处理当前帧的特效绑定（dedup 靠 _processed_effect_frames）
	_process_effect_bindings(current_animation, get_current_frame())

func _on_animation_finished():
	if entry_action != EntryAction.NONE:
		pass
	
	if slide_sequences.has(current_animation):
		_clear_slide_sequence()
	
	# 动画自然播完：把卡顿可能跨过的尾巴几帧上的攻击框补开一次（见 queue_tail_boxes）
	if attack_box_manager:
		attack_box_manager.queue_tail_boxes(current_animation)
	
	_on_animation_exit(current_animation)
	
	_on_action_finished()

func _on_animation_enter(anim_name: String):
	pass

func _on_animation_exit(anim_name: String):
	match anim_name:
		"substitution":
			knockback_active = false
			_launch_active = false
			is_under_control = false
			is_invincible = false
			set_substitution_invincibility(1.5)
			clear_temporary_status()
			play_animation("idle")
		"entry_e":
			clear_temporary_status()
			play_animation("idle")
			entry_action = EntryAction.NONE
			_on_entry_end()
		"scroll":
			clear_temporary_status()
			play_animation("idle")
		"summon":
			clear_temporary_status()
			play_animation("idle")
	if entry_action == EntryAction.CUSTOM:
		if anim_name == custom_entry_anim_name:
			position_3d = entry_pos3d
			play_animation("idle")
			entry_action = EntryAction.NONE

func _on_entry_end():
	pass

## 计算"自 last_frame 之后、到 current_frame 为止"经过的所有帧（含动画循环回绕）。
##
## 为什么要这个：卡顿（生成特效等）会让动画在**一个 tick 内跨过好几帧**。
## 所有逐帧逻辑（帧事件 / 位移序列 slide / 攻击框）都必须遍历这个区间，
## 否则被跨过的那几帧就永久丢失 —— 表现为"滑动不生效""攻击框不生效"。
## 三条链路共用本函数，保证判定口径一致。
##
## 边界：last_frame < 0 / 无可靠上一帧 / 拿不到总帧数 → 只返回当前帧（不猜）。
## 已知限制：一个 tick 内动画循环**多圈**时无法还原（只有首尾两个帧号可用），
## 单圈（last > current）已正确处理。
func get_frames_passed(last_frame: int, current_frame: int, total_frames: int) -> Array[int]:
	var out: Array[int] = []
	if total_frames <= 0 or last_frame < 0 or last_frame >= total_frames:
		out.append(current_frame)
		return out
	if current_frame >= last_frame:
		for f in range(last_frame + 1, current_frame + 1):
			out.append(f)
	else:
		# 回绕：last+1 .. total-1，再 0 .. current
		for f in range(last_frame + 1, total_frames):
			out.append(f)
		for f in range(0, current_frame + 1):
			out.append(f)
	return out

func _process_frame_event():
	# 只处理当前帧。跳帧补偿由 _ensure_frame_sync 统一负责。
	# 原实现在这里也做 get_frames_passed 跳帧补偿，但 frame_changed 信号
	# 在卡顿恢复时会被 Godot 对每个中间帧逐一触发，导致：
	#   第一次信号处理 [4,5,6,7] 并设 _last_processed_frame=7，
	#   第二次信号（frame 5）看到 last=7, current=5 → 走回绕分支 → 生成错误帧。
	# 修复方式：本函数只处理当前帧（dedup 靠 processed_frames），
	# _ensure_frame_sync 在下一渲染帧补偿所有跳过的帧。
	if not frame_events_enabled:
		return

	var current_frame = get_current_frame()
	if current_frame == _last_processed_frame:
		return
	_last_processed_frame = current_frame

	var frame_key = "%s_%d" % [current_animation, current_frame]
	if processed_frames.has(frame_key):
		return
	processed_frames[frame_key] = true

	_process_slide_sequence(current_animation, current_frame)
	_on_frame_trigger(current_animation, current_frame)
	_handle_frame_spe(current_animation, current_frame)

func _on_frame_trigger(anim_name: String, frame_idx: int):
	pass

# ============================================
# 特效绑定系统
# ============================================
func _process_effect_bindings(anim_name: String, frame_idx: int):
	if _effect_bindings.is_empty():
		return
	if not effects_container:
		return
	
	var frame_key = "%s_%d" % [anim_name, frame_idx]
	if _processed_effect_frames.has(frame_key):
		return
	_processed_effect_frames[frame_key] = true
	
	for binding in _effect_bindings:
		if binding.get("anim", "") == anim_name and binding.get("frame", 0) == frame_idx:
			var effect_name = binding.get("effect_name", "")
			var scene_path = binding.get("scene_path", "")
			if effect_name == "" and scene_path == "":
				continue
			
			# 计算偏移位置
			var offset_x = binding.get("x", 0.0) * get_anim_sprite_scale().x - current_anchor_offset.x
			var offset_y = binding.get("y", 0.0) * get_anim_sprite_scale().y - current_anchor_offset.y
			var scale_x = binding.get("scale_x", 1.0) * get_anim_sprite_scale().x
			var scale_y = binding.get("scale_y", 1.0) * get_anim_sprite_scale().y
			var rot_deg = binding.get("rotation", 0.0)
			var follow_entity = binding.get("follow_entity", false)
			var follow_facing = binding.get("follow_facing", false)
			var flip_h = binding.get("flip_h", false)
			
			# 若跟随朝向，则 flips offset_x
			var actual_flip = flip_h
			if follow_facing and facing_direction < 0:
				offset_x = -offset_x
				actual_flip = not actual_flip
			
			var z_off = binding.get("z_offset", 0.0)
			var spawn_pos = position_3d + Vector3(offset_x, offset_y, z_off)
			
			var effect: Node2D = null
			
			# 优先使用场景路径直接加载
			if scene_path != "":
				var reg_name = "_efb_" + binding.get("id", "tmp")
				if binding.get("pooled", false) and effects_container._pooled_scenes.has(reg_name):
					# 池化绑定：已预注册，直接走 spawn（会从池中取）
					if follow_entity:
						effect = effects_container.spawn_follow_effect(
							reg_name, self, Vector3(offset_x, offset_y, z_off), true, actual_flip
						)
					else:
						effect = effects_container.spawn_effect(
							reg_name, spawn_pos, actual_flip
						)
				else:
					var scene = load(scene_path)
					if scene:
						effects_container.register_effect(reg_name, scene, true)
						if follow_entity:
							effect = effects_container.spawn_follow_effect(
								reg_name, self, Vector3(offset_x, offset_y, z_off), true, actual_flip
							)
						else:
							effect = effects_container.spawn_effect(
								reg_name, spawn_pos, actual_flip
							)
					elif effect_name != "":
						scene_path = ""
			
			if not effect and effect_name != "":
				if follow_entity:
					effect = effects_container.spawn_follow_effect(
						effect_name, self, Vector3(offset_x, offset_y, z_off), true, actual_flip
					)
				else:
					effect = effects_container.spawn_effect(
						effect_name, spawn_pos, actual_flip
					)
			
			if effect:
				# 设置缩放
				effect.scale = Vector2(scale_x, scale_y)
				# 设置旋转（度转弧度）
				effect.rotation = deg_to_rad(rot_deg)
				# 记录生成者实体引用（用于深度排序）
				effect.set_meta("_spawn_entity", self)
				# 逻辑特效名：绑定里写的 effect_name 才是作者认得的名字。
				# 带 scene_path 的绑定运行期是用内部名 _efb_<绑定 id> 注册与生成的，
				# 图形化脚本的「移除特效」按逻辑名匹配，所以要在这里单独记一份。
				# 绑定没写 effect_name 时退回内部名，这样按内部名也还有办法定位。
				var logical_name: String = str(effect_name)
				if logical_name == "":
					logical_name = "_efb_" + str(binding.get("id", "tmp"))
				effect.set_meta("effect_name", logical_name)
				# 如果跟随朝向且不跟随实体，需要翻转位置
				if follow_facing and not follow_entity:
					if facing_direction < 0:
						effect.scale.x = -abs(effect.scale.x)
				# 根据朝向自动翻转特效
				var auto_flip = binding.get("auto_flip_by_facing", false)
				if auto_flip:
					if facing_direction < 0:
						effect.scale.x = -abs(effect.scale.x)
					else:
						effect.scale.x = abs(effect.scale.x)

# ============================================
# 移动系统
# ============================================

func _can_move() -> bool:
	return current_animation in ["idle", "run"] or is_sliding and !is_attacking

func _handle_input():
	if entry_action != EntryAction.NONE: return
	if not arena.battle_started:
		is_running = false
		return
	var input_dir = Vector2.ZERO
	
	if _can_move():
		if input_left:
			input_dir.x -= 1
			if not is_sliding:
				facing_direction = -1
		
		if input_right:
			input_dir.x += 1
			if not is_sliding:
				facing_direction = 1
		
		if input_up:
			input_dir.y -= 1
		
		if input_down:
			input_dir.y += 1
	
	is_running = input_dir != Vector2.ZERO

func _handle_input_spe():
	if not is_player: return
	if _immobilize_active and not _immobilize_can_substitute:
		return
	
	if can_cast_aux and not _immobilize_active:
		if inputs[5]:
			play_animation("scroll")
		elif inputs[6]:
			if summon_entity_path.size() > 0:
				play_animation("summon")
	
	# 受击释放效果
	var can_substitute = is_under_control or (_immobilize_active and _immobilize_can_substitute)
	if can_substitute:
		if inputs[4] and !(current_animation == "substitution"):
			# 替身有 15 秒 CD（set_cd(4,4,15)），缓冲路径的 _can_perform_action
			# 已经用 has_substitution() 把关，直通路径此前漏了，导致按住键可以
			# 绕过 CD 连续触发、重复扣奥义点。
			if not has_substitution():
				return
			# 缺 substitution 动画的角色直接不生效。此前动画缺失时
			# play_animation 会写出一个幽灵 current_animation，替身无敌
			# 等不到退出回调永久挂死，VS 还会误触发旧动画的结束事件。
			if not has_animation("substitution"):
				push_warning("[替身] %s 缺少 substitution 动画，替身未生效" % name)
				return
			# 必须能扣豆才行
			if ultimate_point <= 0:
				return
			change_ultimate_point(-1)
			set_cd(4, 4, 15)
			
			_end_launch_sequence(false)
			set_knockback(Vector2(0, 0), 0)
			
			# 定身中替身：清除定身状态并恢复旋转
			if _immobilize_active:
				_immobilize_active = false
				if visuals_node:
					visuals_node.rotation = _saved_visuals_rotation
			
			# 替身到敌人身后逻辑
			var target_enemy = get_nearest_valid_enemy_for_substitution(substitution_distance)
			
			if target_enemy:
				# 1. 计算目标身后的位置
				# 假设向身后偏移 80 个单位（可根据实际手感微调此数值）
				var behind_offset_x = -target_enemy.facing_direction * 80.0 
				
				var target_pos_3d = Vector3(
					target_enemy.position_3d.x + behind_offset_x, # X轴：目标位置 + 身后偏移
					target_enemy.position_3d.y,                   # Y轴：保持一致
					target_enemy.position_3d.z                    # Z轴(高度)：保持一致，防止穿模或浮空异常
				)
				
				# 2. 执行瞬移
				set_position_3d(target_pos_3d)
				
				# 3. 面向目标敌人
				var face_dir = sign(target_enemy.position_3d.x - position_3d.x)
				if face_dir != 0:
					set_facing(face_dir)
			# --------------------------------
			
			play_animation("substitution")
			is_invincible = true
			clear_temporary_status()

func _handle_frame_spe(anim_name: String, frame_idx: int):
	match anim_name:
		"scroll":
			if frame_idx == 1:
				handle_scroll()
		"summon":
			if frame_idx == 1:
				handle_summon()

func handle_scroll():
	if scroll_entity_path != "":
		if is_sliding: stop_slide()
		if not is_grounded: _force_land_and_reset()
		stop_free_move()
		
		var cfg = EntityManager.EntityConfig.new(
			name + "_密卷" + str(Engine.get_frames_drawn()),
			scroll_entity_path,
			get_2d_pos(),
			team_id,
			facing_direction,
			EntityType.SCROLL,
			self
		)
		var ee = entity_manager.spawn_entity_runtime(cfg)
		ee.parent_entity = self
		
		var eff_pos = position_3d
		eff_pos.z = -eff_pos.z
		effects_container.spawn_effect(
			"scroll",
			eff_pos + Vector3(0, 1, 0),
			facing_direction < 0
		)

func handle_summon():
	if summon_entity_path.size() > 0:
		var sep = summon_entity_path[0]
		summon_entity_path.pop_front()
		_update_summon_dot()
		_refresh_scroll_summon_icons()
		if is_sliding: stop_slide()
		if not is_grounded: _force_land_and_reset()
		stop_free_move()
		
		var cfg = EntityManager.EntityConfig.new(
			name + "_通灵" + str(Engine.get_frames_drawn()),
			sep,
			get_2d_pos(),
			team_id,
			facing_direction,
			EntityType.SUMMON,
			self
		)
		var ee = entity_manager.spawn_entity_runtime(cfg)
		ee.parent_entity = self
		
		var eff_pos = position_3d
		eff_pos.z = -eff_pos.z
		effects_container.spawn_effect(
			"summon",
			eff_pos + Vector3(0, 1, 0),
			facing_direction < 0
		)

func _process_slide_physics(delta):
	if not is_sliding:
		return
	
	# 指数衰减：帧率无关，慢速/快速下单位时间总衰减量一致
	slide_velocity.x *= exp(-slide_resistance.x * delta)
	slide_velocity.y *= exp(-slide_resistance.y * delta)
	
	if slide_velocity.length() < 5.0:
		stop_slide()
		return
	
	velocity_3d.x = slide_velocity.x
	velocity_3d.y = slide_velocity.y

func _apply_facing():
	if visuals_node:
		# 只改符号、保留横向缩放的大小：图形化脚本的补间会把 Visuals 缩放到非 1 的值，
		# 而本函数每物理帧都会跑一次，直接写 ±1 会把补间抹掉。
		visuals_node.scale.x = absf(visuals_node.scale.x) * facing_direction

func _handle_movement(delta):
	if is_sliding:
		return
	
	# 卡肉期间：不处理移动
	if _hit_stop_active:
		return
	
	if not _can_move():
		velocity_3d.x = 0
		velocity_3d.y = 0
		velocity_smoothed = Vector2.ZERO
		is_running = false
		if current_animation not in ["idle", "run"]:
			_update_animation_state()
		return
	
	var base_speed_x = (entity_data.move_speed_x if entity_data else 300.0) * final_speed
	var base_speed_y = (entity_data.move_speed_y if entity_data else 300.0) * final_speed
	var run_multiplier = 1.5 if is_running else 1.0
	
	var input_dir = Vector2.ZERO
	if input_left:
		input_dir.x -= 1
	if input_right:
		input_dir.x += 1
	if input_up:
		input_dir.y -= 1
	if input_down:
		input_dir.y += 1
	
	var target_velocity = Vector2(
		input_dir.x * base_speed_x * run_multiplier,
		input_dir.y * base_speed_y * run_multiplier
	)
	
	if use_inertia:
		velocity_smoothed = velocity_smoothed.lerp(target_velocity, inertia_speed * delta)
		velocity_3d.x = velocity_smoothed.x
		velocity_3d.y = velocity_smoothed.y
	else:
		velocity_3d.x = target_velocity.x
		velocity_3d.y = target_velocity.y
		velocity_smoothed = target_velocity
	
	velocity_3d.x *= move_intent.x
	velocity_3d.y *= move_intent.y
	
	_update_animation_state()

func _update_animation_state():
	if not _can_move() or is_sliding:
		return
	
	var target_anim = "run" if is_running else "idle"
	
	if target_anim != current_animation:
		if not has_animation(target_anim):
			return
		
		current_animation = target_anim
		play_animation(target_anim)
		
		var frame_count = get_animation_frame_count(current_animation)
		if get_current_frame() >= frame_count:
			set_animation_frame(0)

# ============================================
# 锚点与受击框系统
# ============================================
var _last_processed_visual_frame: int = -1
var _last_processed_animation: String = ""

# 帧同步核心函数
func _ensure_frame_sync():
	"""确保帧数据与视觉同步 - 每帧检查"""
	if not get_animator_node():
		return

	var current_anim = get_current_animation()
	var visual_frame = _get_visual_frame_index()

	# 检测变化
	var anim_changed = current_anim != _last_processed_animation
	var frame_changed = visual_frame != _last_processed_visual_frame
	
	# 【新增逻辑】检测动画循环
	# 如果动画名没变，但帧数比上一帧小（例如从 5 -> 0），说明动画循环了
	var is_looping = (not anim_changed) and (visual_frame < _last_processed_visual_frame)

	if anim_changed or frame_changed:
		# 【修改】动画变化 或 循环重置 时，清空已处理帧记录
		if anim_changed or is_looping:
			processed_frames.clear()
			if debug_anchor:
				if is_looping:
					print("[帧同步] 动画循环重置，清空帧记录: ", current_anim)
				else:
					print("[帧同步] 动画变化: ", _last_processed_animation, " -> ", current_anim)

		# 执行同步
		# 关键：必须遍历"经过的每一帧"，不能只同步当前帧。
		# 卡顿会让动画一个 tick 跨过好几帧；而卡肉期间信号链路 _on_frame_changed() 会被
		# 直接 return 掉（卡肉与特效同帧发生），此时这里是唯一的兜底 ——
		# 只喂当前帧就会把中间帧的 slide 序列 / 帧触发永久丢掉。
		var last_visual: int = -1 if anim_changed else _last_processed_visual_frame
		var passed: Array[int] = get_frames_passed(
			last_visual, visual_frame, get_animation_frame_count(current_anim))
		if debug_frame_pipeline and passed.size() > 1:
			print("[帧管线] 帧同步跳帧补偿: %s 跨 %d 帧 %s" % [current_anim, passed.size(), str(passed)])
		for f in passed:
			_sync_frame_data(current_anim, f)

		# 更新记录
		_last_processed_animation = current_anim
		_last_processed_visual_frame = visual_frame

func _sync_frame_data(anim_name: String, frame_idx: int):
	"""同步帧数据"""
	# 更新当前动画
	current_animation = anim_name
	
	# 应用帧数据（复用原有逻辑）
	_apply_frame_data_forced(anim_name, frame_idx)
	
	# 触发帧事件（如果没处理过）
	var frame_key = "%s_%d" % [anim_name, frame_idx]
	if not processed_frames.has(frame_key):
		processed_frames[frame_key] = true
		_process_slide_sequence(anim_name, frame_idx)
		_on_frame_trigger(anim_name, frame_idx)
		_handle_frame_spe(anim_name, frame_idx)
		_process_effect_bindings(anim_name, frame_idx)

		if debug_anchor:
			print("[帧同步] 触发事件: ", frame_key)

# 强制应用帧数据（不依赖 _apply_frame_data 的内部判断）
func _apply_frame_data_forced(anim_name: String, frame_idx: int):
	"""强制应用指定动画帧的数据"""
	if not animation_frame_data.has(anim_name):
		# 无数据时重置锚点
		var old_anchor = current_anchor_offset
		current_anchor_offset = Vector2.ZERO
		current_frame_data = null
		
		if debug_anchor and old_anchor != Vector2.ZERO:
			print("[锚点强制重置] 动画 ", anim_name, " 无帧数据")
		
		_apply_anchor_constraint()
		return
	
	var frame_dict = animation_frame_data[anim_name]
	
	# 查找帧数据
	var target_frame = frame_idx
	if not frame_dict.has(target_frame):
		target_frame = _find_closest_frame(frame_dict, target_frame)
		if target_frame < 0 and frame_dict.has(0):
			target_frame = 0
	
	if target_frame < 0 or not frame_dict.has(target_frame):
		return
	
	# 应用数据
	current_frame_data = frame_dict[target_frame]
	var old_anchor = current_anchor_offset
	current_anchor_offset = current_frame_data.anchor_point
	
	_apply_hitbox_transforms()
	_apply_anchor_constraint()
	
	if debug_anchor:
		var change_text = ""
		if old_anchor != current_anchor_offset:
			change_text = " [变化: (%.2f, %.2f)]" % [
				current_anchor_offset.x - old_anchor.x,
				current_anchor_offset.y - old_anchor.y
			]
		print("[锚点同步] %s[%d] -> (%.2f, %.2f)%s" % [
			anim_name, frame_idx,
			current_anchor_offset.x, current_anchor_offset.y,
			change_text
		])

func _apply_frame_data():
	if not get_animator_node(): return
	var current_frame_idx = get_current_frame()
	
	if not animation_frame_data.has(current_animation):
		var old_anchor2 = current_anchor_offset
		current_anchor_offset = Vector2.ZERO
		
		if debug_anchor and (current_animation != last_logged_animation or current_frame_idx != last_logged_frame):
			_log_anchor_info(current_animation, current_frame_idx, old_anchor2, current_anchor_offset, "无帧数据")
			last_logged_animation = current_animation
			last_logged_frame = current_frame_idx
		
		return
	
	var frame_dict = animation_frame_data[current_animation]
	
	# 使用实际帧查找数据
	if not frame_dict.has(current_frame_idx):
		# 如果没有精确匹配，尝试查找最接近的
		var closest_frame = _find_closest_frame(frame_dict, current_frame_idx)
		if closest_frame >= 0:
			current_frame_idx = closest_frame
		elif frame_dict.has(0):
			current_frame_idx = 0
		else:
			var old_anchor2 = current_anchor_offset
			current_anchor_offset = Vector2.ZERO
			
			if debug_anchor and (current_animation != last_logged_animation or current_frame_idx != last_logged_frame):
				_log_anchor_info(current_animation, current_frame_idx, old_anchor2, current_anchor_offset, "帧无数据")
				last_logged_animation = current_animation
			last_logged_frame = current_frame_idx
			return
	
	current_frame_data = frame_dict[current_frame_idx]
	var old_anchor = current_anchor_offset
	current_anchor_offset = current_frame_data.anchor_point
	
	_apply_hitbox_transforms()
	_apply_anchor_constraint()
	
	if debug_anchor and (current_animation != last_logged_animation or current_frame_idx != last_logged_frame):
		_log_anchor_info(current_animation, current_frame_idx, old_anchor, current_anchor_offset, "帧变化")
		last_logged_animation = current_animation
		last_logged_frame = current_frame_idx

# 添加辅助函数：查找最接近的帧
func _find_closest_frame(frame_dict: Dictionary, target_frame: int) -> int:
	var closest = -1
	var min_diff = INF
	
	for frame_idx in frame_dict.keys():
		var diff = abs(int(frame_idx) - target_frame)
		if diff < min_diff:
			min_diff = diff
			closest = int(frame_idx)
	
	# 只接受距离较近的帧（2帧以内）
	return closest if min_diff <= 2 else -1

func _get_visual_frame_index() -> int:
	"""获取当前实际显示的精灵帧索引（真实帧号）
	
	注意：**不要**改成"纹理相同即同一帧"的去重版本。动画里存在重复纹理（停顿帧很常见）
	时，去重会把这些帧判成"帧没变"，从而：
	  ① 把该帧的 slide 序列 / 帧触发稳定吞掉（与卡顿无关的独立丢帧途径）；
	  ② 把**第一个**同纹理帧的锚点与帧数据套到当前帧上（帧数据用错）。
	"""
	if not get_animator_node() or not get_animator_node().sprite_frames:
		return 0
	
	var frames = get_animator_node().sprite_frames
	
	# 检查当前动画是否存在
	if not has_animation(current_animation):
		# 如果没有这个动画，尝试使用第一个可用动画
		var anim_names = frames.get_animation_names()
		if anim_names.is_empty():
			return 0  # 没有任何动画，直接返回0
		current_animation = anim_names[0]  # 注意：这可能会影响其他逻辑，视情况可只临时替换
	
	# 确保 frame 索引不越界
	var frame_count = get_animation_frame_count(current_animation)
	return clamp(get_current_frame(), 0, max(frame_count - 1, 0))

func _log_anchor_info(anim_name: String, frame_idx: int, old_anchor: Vector2, new_anchor: Vector2, reason: String):
	var change_text = ""
	if old_anchor != new_anchor:
		var delta = new_anchor - old_anchor
		change_text = " [变化: (%.2f, %.2f)]" % [delta.x, delta.y]
	
	print("[锚点调试] %s | 动画: %s | 帧: %d | 锚点: (%.2f, %.2f)%s | 朝向: %s | Z:%.2f" % [
		reason, anim_name, frame_idx, new_anchor.x, new_anchor.y, change_text,
		"左" if facing_direction == -1 else "右", position_3d.z
	])

func _apply_anchor_constraint():
	if not visuals_node:
		return
	
	var adjusted_offset = current_anchor_offset
	if facing_direction == -1:
		adjusted_offset.x = -adjusted_offset.x
	
	# Visuals 自身的缩放要一起算进锚点补偿：补间把 Visuals 放大后，
	# 偏移量不跟着放大的话锚点就不再落在实体原点，角色会整体漂移。
	# get_visuals_extra_scale 返回 ±1 时结果与原来完全一致。
	var visuals_extra = get_visuals_extra_scale()
	visuals_node.position = Vector2(
		-adjusted_offset.x * get_anim_sprite_scale().x * visuals_extra.x,
		-adjusted_offset.y * get_anim_sprite_scale().y * visuals_extra.y
	)

func _apply_hitbox_transforms():
	if current_frame_data == null or current_frame_data.hitboxes_data.is_empty():
		# 无帧数据时隐藏所有受击框，避免继承上一帧位置
		for area in hitbox_areas:
			if not is_instance_valid(area): continue
			area.visible = false
			var shape_node = area.get_child(0) as CollisionShape2D
			if shape_node:
				shape_node.disabled = true
		return
		
	if not get_animator_node(): return
	
	var apply_count = mini(current_frame_data.hitboxes_data.size(), hitbox_areas.size())
	
	# 获取全局缩放，用于确定拉伸比例
	var sprite_scale = get_anim_global_scale()
	var sprite_global_pos = get_anim_global_position()
	
	for i in range(apply_count):
		var area = hitbox_areas[i]
		var data = current_frame_data.hitboxes_data[i]
		
		# --- 1. 读取帧数据偏移 ---
		var base_offset = Vector2.ZERO
		if data.has("position"):
			base_offset = Vector2(
				data["position"].get("x", 0.0),
				data["position"].get("y", 0.0)
			)
		
		# --- 2. 读取 Z轴 (高度) 偏移 ---
		var z_offset = data.get("z_offset", 0.0)
		
		# --- 3. 计算像素偏移量 ---
		var pixel_offset = Vector2(
			base_offset.x,
			base_offset.y - z_offset
		)
		
		# --- 4. 转换为世界坐标偏移 (手动控制翻转) ---
		# 【核心修正】X轴：使用 facing_direction 控制左右方向，使用 abs(scale) 控制拉伸大小
		var world_offset_x = pixel_offset.x * facing_direction * abs(sprite_scale.x)
		
		# Y轴：只应用拉伸大小，强制取绝对值防止上下翻转
		var world_offset_y = pixel_offset.y * abs(sprite_scale.y)
		
		var world_offset = Vector2(world_offset_x, world_offset_y)
		
		# --- 5. 计算最终全局坐标 ---
		var target_x = sprite_global_pos.x + world_offset.x
		# Y坐标：逻辑位置 - 深度
		var target_y = sprite_global_pos.y + world_offset.y - position_3d.y
		
		area.global_position = Vector2(target_x, target_y)
		
		# --- 6. 缩放设置 ---
		# 设为 ONE，让形状自然继承父节点的拉伸
		area.scale = Vector2.ONE
		
		# 如果有额外自定义缩放
		if data.has("scale"):
			area.scale = Vector2(
				abs(data["scale"].get("x", 1.0)),
				abs(data["scale"].get("y", 1.0))
			)
		
		# --- 7. 其他属性 ---
		if data.has("rotation"):
			area.rotation = data["rotation"]
		
		# 应用可见性（帧数据编辑器中设置的 visible 字段）
		var is_visible = data.get("visible", true)
		area.visible = is_visible
		
		# 隐藏时额外禁用碰撞检测（Area2D.visible 只影响渲染，不影响碰撞）
		var shape_node = area.get_child(0) as CollisionShape2D
		if shape_node:
			shape_node.disabled = not is_visible
			
		_apply_hitbox_shape(area, data)

func _apply_hitbox_shape(area: Area2D, data: Dictionary):
	var shape_node = area.get_child(0) as CollisionShape2D
	
	# 安全检查
	if not shape_node or not shape_node.shape or not shape_node.shape is RectangleShape2D:
		return
		
	var target_size = Vector2(50.0, 50.0) # 默认兜底大小
	
	# 提取尺寸数据
	if data.has("size"):
		target_size = Vector2(
			data["size"].get("width", 50.0),
			data["size"].get("height", 50.0)
		)
	elif data.has("radius"):
		# 兼容圆形数据：把半径转成等大小的正方形
		var r = data["radius"]
		target_size = Vector2(r * 2.0, r * 2.0)

	# 绝对安全：只修改现有对象的属性，不替换指针，不需要 deferred
	shape_node.shape.size = target_size

# ============================================
# 公共API
# ============================================

func get_hitbox_area(index: int) -> Area2D:
	if index >= 0 and index < hitbox_areas.size():
		return hitbox_areas[index]
	return null

func set_facing(dir: int):
	facing_direction = dir
	if visuals_node:
		# 与 _apply_facing 同一口径：只改朝向符号，保留补间出来的横向缩放大小
		visuals_node.scale.x = absf(visuals_node.scale.x) * dir
	
	# 强制应用当前帧数据，使锚点和受击框与新朝向同步
	if get_animator_node():
		var anim = get_current_animation()
		var frame = get_current_frame()
		_apply_frame_data_forced(anim, frame)

func get_facing() -> int:
	return facing_direction

func set_inertia_enabled(enabled: bool):
	use_inertia = enabled
	if not enabled:
		velocity_smoothed = Vector2(velocity_3d.x, velocity_3d.y)

func is_inertia_enabled() -> bool:
	return use_inertia

func set_debug_anchor(enabled: bool):
	debug_anchor = enabled

func set_debug_slide(enabled: bool):
	debug_slide = enabled

func set_debug_z_axis(enabled: bool):
	debug_z_axis = enabled

func set_debug_team(enabled: bool):
	debug_team = enabled

func set_debug_hitboxes(enabled: bool):
	debug_show_hitboxes = enabled

func set_debug_attack_boxes(enabled: bool):
	debug_show_attack_boxes = enabled

func set_debug_all(enabled: bool):
	# 总开关关闭时，任何途径都不允许打开调试输出
	if not MatchConfig.debug_enabled:
		enabled = false
	debug_show_hitboxes = enabled
	debug_show_attack_boxes = enabled
	debug_show_info_points = enabled # 新增
	debug_anchor = enabled
	debug_slide = enabled
	debug_z_axis = enabled
	debug_team = enabled

func get_debug_info() -> Dictionary:
	return {
		"hitboxes_visible": debug_show_hitboxes,
		"attack_boxes_visible": debug_show_attack_boxes,
		"info_points_visible": debug_show_info_points, # 新增
		"info_points_count": info_points_data.size(),   # 新增
		"active_attack_boxes": attack_box_manager._active_boxes.size() if attack_box_manager else 0,
		"hitbox_count": hitbox_areas.size(),
		"current_animation": current_animation,
		"current_frame": get_current_frame(),
		"position_3d": position_3d
	}

func is_moving() -> bool:
	return Vector2(velocity_3d.x, velocity_3d.y).length() > 10.0

func get_entity_data() -> EntityData:
	return entity_data

func get_current_anchor_info() -> Dictionary:
	return {
		"animation": current_animation,
		"frame": get_current_frame(),
		"anchor_offset": current_anchor_offset,
		"visuals_position": visuals_node.position if visuals_node else Vector2.ZERO,
		"facing": facing_direction,
		"position_3d": position_3d,
		"is_grounded": is_grounded
	}

func get_position_3d() -> Vector3:
	return position_3d

func get_depth_pos() -> Vector3:
	return position_3d

func get_effect_pos() -> Vector3:
	var real_pos := position_3d
	real_pos.y = position_3d.z
	real_pos.z = position_3d.y
	return real_pos

func calculate_intersection(hit_result: AttackBoxManager.HitResult, _box_config: Dictionary = {}) -> Vector2:
	"""
	计算攻击框与受击框的相交区域，并返回一个随机点。
	攻击框可能同时盖住多个受击框（手/脚/躯干），而 hit_result 记录的不一定是最合理的那个，
	这里遍历目标所有受击框，取与攻击框重叠面积最大者作为命中点基准，避免被远端受击框带偏。
	如果计算失败，则回退到在受击框（def_node）上随机取一个点。
	"""
	# 安全获取受击节点（兜底方案的基础）
	var def_node: Area2D = _get_def_node_safe(hit_result)
	if not def_node:
		return Vector2.ZERO # 如果连受击节点都没有，彻底无解，返回 ZERO
		
	# 2. 安全获取攻击节点
	var atk_node: Area2D = _get_atk_node_safe(hit_result)
	
	# 【兜底触发点 1】：如果没有攻击节点
	if not atk_node:
		return _get_random_point_on_area(def_node)
	
	# 3. 安全获取攻击框尺寸
	var atk_size = _get_rect_size_safe(atk_node)
	if atk_size == Vector2.ZERO:
		return _get_random_point_on_area(def_node)
	
	var atk_rect = Rect2(atk_node.global_position - atk_size * 0.5, atk_size)
	
	# 4. 遍历目标所有受击框，选与攻击框重叠面积最大的那个作为命中点基准
	var target_entity = hit_result.target_entity
	var best_def: Area2D = null
	var best_inter = Rect2()
	var best_area = -1.0
	if target_entity:
		for area in target_entity.hitbox_areas:
			if not is_instance_valid(area): continue
			var d_size = _get_rect_size_safe(area)
			if d_size == Vector2.ZERO: continue
			var d_rect = Rect2(area.global_position - d_size * 0.5, d_size)
			var inter = atk_rect.intersection(d_rect)
			if inter.size.x <= 0 or inter.size.y <= 0: continue
			var area_val = inter.size.x * inter.size.y
			if area_val > best_area:
				best_area = area_val
				best_def = area
				best_inter = inter
	
	# 没找到可用的重叠受击框，回退到 hit_result 记录的受击框
	if best_def == null:
		best_def = def_node
		var d_size = _get_rect_size_safe(def_node)
		if d_size == Vector2.ZERO:
			return _get_random_point_on_area(def_node)
		best_inter = atk_rect.intersection(Rect2(def_node.global_position - d_size * 0.5, d_size))
		# 【兜底触发点 2】：如果没有实际重叠区域（比如刚好擦边没碰到）
		if best_inter.size.x <= 0 or best_inter.size.y <= 0:
			return _get_random_point_on_area(def_node)
		
	# 5. 正常逻辑：在相交区域内随机取点
	best_inter = best_inter.grow_individual(
		-best_inter.size.x * 0.1, -best_inter.size.y * 0.1, 
		-best_inter.size.x * 0.1, -best_inter.size.y * 0.1
	)
	
	return Vector2(
		randf_range(best_inter.position.x, best_inter.end.x),
		randf_range(best_inter.position.y, best_inter.end.y)
	)


# ==========================================
# 辅助函数
# ==========================================

func _get_random_point_on_area(area_node: Area2D) -> Vector2:
	var base_pos = area_node.global_position
	var scale = area_node.global_scale.abs()
	
	for child in area_node.get_children():
		if child is CollisionShape2D and child.shape and not child.disabled:
			var shape = child.shape
			
			if shape is RectangleShape2D:
				var size = shape.size * scale
				return base_pos + Vector2(
					randf_range(-size.x / 2, size.x / 2),
					randf_range(-size.y / 2, size.y / 2)
				)
				
			elif shape is CircleShape2D:
				var r = shape.radius * scale.x
				# sqrt 保证面积上的均匀分布，避免中心点过于密集
				var dist = sqrt(randf()) * r 
				var angle = randf() * TAU
				return base_pos + Vector2(cos(angle), sin(angle)) * dist
				
			elif shape is CapsuleShape2D:
				# 简易处理：把胶囊体近似当作矩形来随机
				var w = shape.radius * 2 * scale.x
				var h = shape.height * scale.y
				return base_pos + Vector2(
					randf_range(-w / 2, w / 2),
					randf_range(-h / 2, h / 2)
				)
			break # 找到第一个有效形状就处理
			
	return base_pos # 极端情况兜底：连 Shape 都没有，直接返回节点中心

func _get_rect_size_safe(area_node: Area2D) -> Vector2:
	for child in area_node.get_children():
		if child is CollisionShape2D and child.shape and not child.disabled:
			if child.shape is RectangleShape2D:
				return child.shape.size * area_node.global_scale.abs()
			break
	return Vector2.ZERO

func _get_atk_node_safe(hit_result: AttackBoxManager.HitResult) -> Area2D:
	if attack_box_manager and hit_result.attack_box_id in attack_box_manager._active_boxes:
		return attack_box_manager._active_boxes[hit_result.attack_box_id].get("node", null)
	return null

func _get_def_node_safe(hit_result: AttackBoxManager.HitResult) -> Area2D:
	var target_entity = hit_result.target_entity
	if target_entity and hit_result.hitbox_index >= 0 and hit_result.hitbox_index < target_entity.hitbox_areas.size():
		return target_entity.hitbox_areas[hit_result.hitbox_index]
	return null

func set_position_3d(pos: Vector3):
	position_3d = pos
	_last_valid_wall_pos = Vector2(position_3d.x, position_3d.y)
	_update_visual_position()

func get_velocity_3d() -> Vector3:
	return velocity_3d

func set_velocity_3d(vel: Vector3):
	velocity_3d = vel

func get_nearest_enemy() -> Node2D:
	var enemies = TeamManager.get_all_enemies_of(team_id)
	var nearest: Node2D = null
	var min_dist = INF
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy
	
	return nearest

func get_nearest_ally() -> Node2D:
	var allies = TeamManager.get_all_allies_of(team_id)
	var nearest: Node2D = null
	var min_dist = INF
	
	for ally in allies:
		if ally == self or not is_instance_valid(ally):
			continue
		var dist = global_position.distance_to(ally.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = ally
	
	return nearest

func get_enemies_in_range(range_distance: float) -> Array[Node2D]:
	"""获取范围内的所有敌人"""
	var enemies = TeamManager.get_all_enemies_of(team_id)
	var in_range: Array[Node2D] = []
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= range_distance:
			in_range.append(enemy)
	
	return in_range

func face_nearest_enemy():
	"""面向最近的敌人"""
	var nearest = get_nearest_enemy()
	if nearest:
		var dir = sign(nearest.global_position.x - global_position.x)
		if dir != 0:
			set_facing(dir)

func get_nearest_valid_enemy_for_substitution(range_distance: float) -> Node2D:
	"""获取替身范围内最近且合法的敌人（非同阵营且为玩家或敌人类型）"""
	var enemies = get_enemies_in_range(range_distance)
	var nearest: Node2D = null
	var min_dist = INF
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		# 条件过滤：必须是 ENEMY 或 PLAYER 类型
		if enemy.entity_type != EntityType.ENEMY and enemy.entity_type != EntityType.PLAYER:
			continue
			
		var dist = global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy
			
	return nearest

func get_nearest_valid_enemy_in_range(range: Vector2) -> Node2D:
	"""获取替身范围内最近且合法的敌人（非同阵营且为玩家或敌人类型）"""
	var nearest: Node2D = get_nearest_valid_enemy_for_substitution(INF)
	
	var dist: Vector2
	dist.x = abs(position_3d.x-nearest.position_3d.x)
	dist.y = abs(position_3d.y-nearest.position_3d.y)
	
	if dist < range:
		return nearest
	else:
		return null

func get_info_point_position(point_name: String) -> Vector2:
	"""获取指定名称信息点的世界 2D 坐标（自动处理朝向与精灵缩放）"""
	if info_points_data.is_empty():
		return Vector2.ZERO
	for pt in info_points_data:
		if pt.get("name", "") == point_name:
			var offset = Vector2(pt.get("x", 0.0), pt.get("y", 0.0))

			# 使用信息点所属动画帧的锚点，而非当前播放帧的锚点
			var anchor = Vector2.ZERO
			var pt_anim = pt.get("anim", "")
			var pt_frame = pt.get("frame", 0)

			if animation_frame_data.has(pt_anim):
				var frame_dict = animation_frame_data[pt_anim]
				var target_frame = pt_frame
				if not frame_dict.has(target_frame):
					target_frame = _find_closest_frame(frame_dict, target_frame)
					if target_frame < 0 and frame_dict.has(0):
						target_frame = 0
				if target_frame >= 0 and frame_dict.has(target_frame):
					anchor = frame_dict[target_frame].anchor_point

			offset.x -= anchor.x
			offset.y -= anchor.y
			offset.x *= get_anim_sprite_scale().x * facing_direction
			offset.y *= get_anim_sprite_scale().y

			return offset
	push_warning("EntityBase: 未找到名为 '%s' 的信息点，返回角色中心坐标" % point_name)
	return Vector2.ZERO

func translate_pos2d_to_pos3d(pos_2d: Vector2):
	var pos_3d: Vector3 = Vector3.ZERO
	pos_3d.x = pos_2d.x
	pos_3d.z = pos_2d.y
	return pos_3d

func calculate_immobilize_position_3d(target: Node2D, attacker_point_name: String, target_point_name: String) -> Vector3:
	""" 
	计算目标被抓取/吸附时应该在的 3D 世界坐标。
	确保攻击者的指定点(如手)与目标的指定点(如脖子)在视觉画面上完全重合。
	
	参数:
	target: 被抓取的目标节点 (必须是 EntityBase)
	attacker_point_name: 攻击者身上的信息点名 (如 "hand")
	target_point_name: 目标身上的信息点名 (如 "neck")
		
	返回: 目标需要被设置的 position_3d 坐标
	"""
	if not target or not target.has_method("get_info_point_position"):
		push_error("calculate_immobilize_position_3d: 目标无效或缺少 get_info_point_position 方法")
		return Vector3.ZERO
		
	# 1. 获取攻击者信息点的屏幕世界 2D 坐标
	var attacker_offset = get_info_point_position(attacker_point_name)
	var attacker_world_2d = global_position + attacker_offset
	
	# 2. 获取目标信息点的本地 2D 偏移 (注意：这里读取的是目标当前朝向的偏移，调用前通常需要先设定好目标的朝向)
	var target_offset = target.get_info_point_position(target_point_name)
	
	# 3. 计算目标需要的全局 2D 坐标 (使两个信息点在画面上重合)
	var target_needed_world_2d = attacker_offset - target_offset
	
	# 4. 反推目标的 position_3d
	var result_pos = Vector3.ZERO
	result_pos.x = position_3d.x + target_needed_world_2d.x
	result_pos.y = position_3d.y
	result_pos.z = position_3d.z - target_needed_world_2d.y
	
	return result_pos

# ============================================
# 自由移动系统
# ============================================

## 开始自由移动
## 在攻击动画的开始帧调用，启用输入控制移动
## x_speed: X轴（横向）最大移动速度
## y_speed: Y轴（纵向）最大移动速度
func start_free_move(x_speed: float, y_speed: float):
	is_free_moving = true
	_free_move_speed = Vector2(abs(x_speed), abs(y_speed))
	
	if debug_slide:
		print("[自由移动] 开始 | X速度:%.0f | Y速度:%.0f" % [x_speed, y_speed])

## 停止自由移动
## 在攻击动画的结束帧调用，禁用并重置移动状态
func stop_free_move():
	if is_free_moving:
		is_free_moving = false
		_free_move_speed = Vector2.ZERO
		
		# 清零速度，防止惯性滑行
		velocity_3d.x = 0
		velocity_3d.y = 0
		velocity_smoothed = Vector2.ZERO
		
		if debug_slide:
			print("[自由移动] 停止")

## 自由移动物理处理
func _handle_free_move_physics(delta):
	if !is_free_moving:
		return
	
	var input_dir = Vector2.ZERO
	
	# 读取输入方向
	if input_left:
		input_dir.x -= 1
	if input_right:
		input_dir.x += 1
	if input_up:
		input_dir.y -= 1
	if input_down:
		input_dir.y += 1
	
	# 计算目标速度（基于传入的参数，乘移速加成）
	var target_vel = Vector2(
		input_dir.x * _free_move_speed.x * final_speed,
		input_dir.y * _free_move_speed.y * final_speed
	)
	
	# 应用惯性或直接设置速度
	if use_inertia:
		velocity_smoothed = velocity_smoothed.lerp(target_vel, inertia_speed * delta)
		velocity_3d.x += velocity_smoothed.x
		velocity_3d.y += velocity_smoothed.y
	else:
		velocity_3d.x += target_vel.x
		velocity_3d.y += target_vel.y
		velocity_smoothed = target_vel


func set_facing_dir(fd: int, state: BodyState = BodyState.HARD):
	if state < body_state:
		return
	set_facing(fd)

# ============================================ 
# 信息点调试可视化 
# ============================================
func _on_debug_draw_info_points():
	if not debug_show_info_points or info_points_data.is_empty(): return
	
	for pt in info_points_data:
		var point_name = pt.get("name", "")
		if point_name == "": continue
		
		# 获取信息点的本地偏移（已自动处理朝向和缩放）
		var offset = get_info_point_position(point_name)
		# 计算屏幕视口坐标
		var viewport_pos = get_viewport().get_canvas_transform() * (global_position + offset)
		
		var size = debug_info_point_size
		var color = debug_info_point_color
		
		# 1. 画实心小圆点
		_debug_draw_node.draw_circle(viewport_pos, size * 0.6, Color(color, 0.5))
		
		# 2. 画十字准星
		var cross_size = size * 1.5
		_debug_draw_node.draw_line(viewport_pos + Vector2(-cross_size, 0), viewport_pos + Vector2(cross_size, 0), color, 1.5)
		_debug_draw_node.draw_line(viewport_pos + Vector2(0, -cross_size), viewport_pos + Vector2(0, cross_size), color, 1.5)
		
		# 3. 画名称标签（稍微偏移防止遮挡准星）
		_debug_draw_node.draw_string(
			ThemeDB.fallback_font, 
			viewport_pos + Vector2(12, -8), 
			point_name, 
			HORIZONTAL_ALIGNMENT_LEFT, 
			-1, 12, color
		)

func get_2d_pos():
	return Vector2(position_3d.x, position_3d.y)

## 把一个点推出墙体。抓取的释放点用它兜底，鲨鱼与三方封印的脚本也拿它算 set_immobilize 的落点。
func get_out_of_wall(pos_3d: Vector3) -> Vector3:
	if main == null or not main.has_method("point_walls"):
		return pos_3d
	var wall_pos = main.point_walls(Vector2(pos_3d.x, pos_3d.y))
	var will_pos = pos_3d
	if wall_pos:
		will_pos.x = wall_pos.x
		will_pos.y = wall_pos.y
	return will_pos

func is_using_ultimate():
	return false

func has_substitution():
	if cool_down_time[4].time > 0: return false
	return true

var _is_quitting := false

## 安全等待一帧：节点离开场景树时会直接跳过，避免 process_frame 空对象错误
func wait_frame():
	var tree = get_tree()
	if tree == null:
		return
	await tree.process_frame
	if _is_quitting:
		return

## 安全等待一段时间
func wait_time(sec: float):
	var tree = get_tree()
	if tree == null:
		return
	await tree.create_timer(sec).timeout
	if _is_quitting:
		return

func teleport_to_position(target_pos: Vector3, adjust_for_wall: bool = true, clamp_to_ground: bool = true) -> void:
	var new_pos = target_pos
	
	# 1. 墙壁修正：如果目标点超出战斗区域，使用 point_walls 返回的最近合法点
	#if adjust_for_wall and main and main.has_method("point_walls"):
		#var wall_pos = main.point_walls(Vector2(new_pos.x, new_pos.y))
		#if wall_pos != null:
			#new_pos.x = wall_pos.x
			#new_pos.y = wall_pos.y
	
	# 2. 地面高度修正：防止瞬移到地底
	if clamp_to_ground and new_pos.z < ground_level:
		new_pos.z = ground_level
	
	# 3. 应用新位置（内部自动更新 _last_valid_wall_pos 和视觉位置）
	set_position_3d(new_pos)
	
	print("[瞬移] %s 移动到 (%.1f, %.1f, %.1f)" % [name, new_pos.x, new_pos.y, new_pos.z])

func show_info_text(text: String, color: Color = Color.WHITE):
	if info_animation_player.is_playing(): return
	info_label.text = text
	info_label.add_theme_color_override("font_color", color)
	info_animation_player.play("Jump")

func set_aura_visible(b: bool):
	aura_node.visible = b

func set_energy_bar_visible(b: bool):
	energy_bar.visible = b
	if b: ultimate_panel.position.y = 83.945
	else: ultimate_panel.position.y = 72.0

func set_energy_bar_value(v: float):
	energy_bar.value = v

func set_energy_bar_value_max(v: float):
	energy_bar.max_value = v

func set_energy_bar_modulate(c: Color):
	energy_bar.modulate = c

func set_energy_bar_split(c: int):
	energy_bar.split_count = c

func get_root_parent_entity() -> EntityBase:
	var target: EntityBase = self
	while target.parent_entity:
		target = target.parent_entity
	return target

# ============================================
# 广播系统
# ============================================

func send_private_broadcast(msg: String, data: Dictionary = {}):
	if not entity_manager:
		return
	var my_root = get_root_parent_entity()
	for e in entity_manager.get_all_entities():
		if e.get_root_parent_entity() == my_root:
			e._receive_broadcast(msg, data, false)

func send_global_broadcast(msg: String, data: Dictionary = {}):
	if not entity_manager:
		return
	for e in entity_manager.get_all_entities():
		e._receive_broadcast(msg, data, true)
	if main and main.has_method("broadcast_global"):
		main.broadcast_global(msg, data)

func _receive_broadcast(msg: String, data: Dictionary, is_global: bool):
	broadcast_received.emit(msg, data, is_global)

# ============================================
# NullSlot — 非操控者实体的存根槽位
# 接收所有属性赋值和方法调用但不做任何事，
# 避免多个实体争抢同一组 SkillPanel 节点。
# ============================================
class NullSlot:
	var disabled = false
	var dot = -1
	var dot_max = 4
	var timer_progress = 0.0
	var show_aura = false
	var is_charging = false
	var cool_down_time_now = 0.0
	var cool_down_time_max = 0.0
	var _button_pressed = false
	var visible = true
	var charging_progress: _NullProgress

	func _init():
		charging_progress = _NullProgress.new()

	func set_texture(_t): pass
	func set_cd(_cd): pass
	func _can_press(): return false
	func is_finger_inside(): return false

class _NullProgress:
	var rotation: float = 0.0
	var visible: bool = false
