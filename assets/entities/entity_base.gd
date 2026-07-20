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
var skill_slot: Array[SkillSlot]
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
#   - play_animation(anim_name: String, custom_speed: float = -1.0)
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

func play_animation(anim_name: String, custom_speed: float = 1.0):
	"""播放指定动画"""
	if _immobilize_active: return
	current_animation = anim_name
	if anim_name == "idle":
		var wall_pos = main.point_walls(Vector2(position_3d.x, position_3d.y))
		if wall_pos:
			position_3d.x = wall_pos.x
			position_3d.y = wall_pos.y
			_last_valid_wall_pos = wall_pos
		else:
			_last_valid_wall_pos = Vector2(position_3d.x, position_3d.y)

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
var slide_resistance: float = 8.0
var slide_sequences: Dictionary = {}
var current_slide_sequence: Array = []
var current_slide_index: int = -1
var slide_locked_facing: int = 1
var processed_frames: Dictionary = {}
var frame_events_enabled: bool = true
var _current_slide_gravity: float = -1.0
var _slide_gravity_active: bool = false

# ============================================
# 击退系统
# ============================================

var _knockback_velocity: Vector2 = Vector2.ZERO      # 当前击退速度
var _knockback_resistance: float = 10.0              # 击退阻力
var _knockback_active: bool = false                  # 是否正在击退
var _knockback_timer: float = 0.0                    # 击退计时器

# ============================================
# 击飞系统
# ============================================

var _launch_velocity_z: float = 0.0
var _launch_active: bool = false
var _launch_gravity: float = 7000.0

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
var _immobilize_launch_gravity: float = 800

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
var scroll_entity_path: String = "res://assets/entities/禁术_阴愈伤灭/entity.tscn"
var summon_entity_path = ["res://assets/entities/大运重卡/entity.tscn", "res://assets/entities/鲨鱼/entity.tscn", "res://assets/entities/三方封印/entity.tscn"]
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
@export var buffer_valid_frames: int = 12   # 60fps ≈ 0.2秒
var _input_buffer: Array[Dictionary] = []
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

# ============================================
# 初始化
# ============================================

var enable_keyboard_input: bool = false
func _ready():
	enable_keyboard_input = OS.has_feature("windows") or OS.has_feature("editor")
	
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
		skill_slot.resize(9)
		inputs.resize(9)
		for i in range(9):
			cool_down_time.append({"time": 0.0, "slot_id": 0})
			skill_timer.append({"time": 0.0, "max_time": 0, "slot_id": 0, "sub_slots": []})
		skill_slot[0] = skill_slots.get_node("Attack")
		skill_slot[1] = skill_slots.get_node("Skill1")
		skill_slot[2] = skill_slots.get_node("Skill2")
		skill_slot[3] = skill_slots.get_node("Skill3")
		skill_slot[4] = skill_slots.get_node("Substitution")
		skill_slot[5] = skill_slots.get_node("Scroll")
		skill_slot[6] = skill_slots.get_node("Summon")
		skill_slot[7] = skill_slots.get_node("SubSkill1")
		skill_slot[8] = skill_slots.get_node("SubSkill2")
		
		skill_slot[7].visible = false
		skill_slot[8].visible = false
		
		virtual_joystick = skill_panel.get_node("VirtualJoystick")
	
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
	if entry_action == EntryAction.DEFAULT:
		if can_play_animation("entry"):
			play_animation("entry")
	
			_entry_target_x = position_3d.x
			
			position_3d.x -= 580 * facing_direction
			position_3d.z = 600 
			
			_entry_fall_speed_x = 600.0 * facing_direction
			
			apply_z_impulse(0)
			set_slide_gravity(700)
		else:
			play_animation("idle")
			entry_action = EntryAction.NONE
			_on_entry_end()
	elif entry_action == EntryAction.CUSTOM:
		entry_pos3d = position_3d
		teleport_to_position(position_3d + custom_entry_extra_pos3d)
		play_animation(custom_entry_anim_name)

func die():
	# 1. 停止所有物理运动
	velocity_3d = Vector3.ZERO
	velocity = Vector2.ZERO
	slide_velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_launch_velocity_z = 0.0
	is_sliding = false
	_launch_active = false

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
	file.close()

func setup_player_config():
	setup_icon()

func _on_controller_changed(new_name: String):
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
	# 仅在开启了任意调试开关时才创建调试节点
	if debug_show_hitboxes or debug_show_attack_boxes or debug_show_info_points:
		_ensure_debug_system()

func _on_draw_all_debug():
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
	
	var active_boxes = attack_box_manager._active_boxes
	for box_id in active_boxes.keys():
		var data = active_boxes[box_id]
		var node = data.node as Area2D
		var config = data.config as AttackBoxData.FrameConfig
		
		if not is_instance_valid(node): continue
		
		# --- 1. 获取逻辑坐标 (已经剥离了深度) ---
		var logic_global_pos = node.global_position
		
		# --- 2. 计算视觉坐标 (加回深度 position_3d.y) ---
		var visual_global_pos = Vector2(logic_global_pos.x, logic_global_pos.y + position_3d.y)
		
		# --- 3. 转换为屏幕视口坐标 ---
		var viewport_pos = get_viewport().canvas_transform * visual_global_pos
		
		# --- 4. 获取形状尺寸 ---
		var shape_node = node.get_child(0) as CollisionShape2D
		if not shape_node or not shape_node.shape: continue
		
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
		var trigger_mark = "✓" if data.box_data.has_triggered_instance(data.instance_key) else "○"
		var z_text = ""
		if debug_show_z_depth:
			z_text = "\nZ:%.0f(±%.0f) | D:%.0f" % [config.position.z, config.size.z/2, config.size.y]
		var text = "%s [%s]%s" % [data.box_data.box_name, trigger_mark, z_text]
		
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
	# 按需创建调试节点
	if debug_show_hitboxes or debug_show_attack_boxes or debug_show_info_points:
		_ensure_debug_system()
	# 逻辑简化：只要开启了任意调试，就启用 Process 来驱动 queue_redraw
	set_process(debug_show_hitboxes or debug_show_attack_boxes or debug_show_info_points)
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
# 处理循环
# ============================================

func _process(delta):
	_consume_local_buffer()
	_ensure_frame_sync()
	
	if debug_show_hitboxes or debug_show_attack_boxes or debug_show_info_points:
		_ensure_debug_system()
		if _debug_draw_node:
			_debug_draw_node.queue_redraw()

func _physics_process(delta):
	if is_player:
		hp_red.value = hp
	_process_magnetism(delta) # 优先级这一块/.
	_process_global_magnetisms(delta) # 全局吸附（多吸附共存）
	_record_inputs()
	
	# 卡肉状态：冻结所有更新，不调用 move_and_slide
	if _hit_stop_active:
		_apply_facing()
		_process_hit_stop(delta)
	
	if _immobilize_active:
		_process_immobilize(delta)
	
	if _hit_stop_active:
		out_of_wall()
		return
	
	_process_cd(delta)
	_process_timer(delta)
	_process_modifiers(delta)
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
			var c = mat.get_shader_parameter("self_modulate")
			if c != null:
				c.a = 1.0
				mat.set_shader_parameter("self_modulate", c)
		return
	
	if mat:
		# 半透明闪烁
		var c = mat.get_shader_parameter("self_modulate")
		if c != null:
			c.a = 0.8
			mat.set_shader_parameter("self_modulate", c)
	
	_substitution_timer -= delta
	
	if _substitution_timer <= 0:
		_substitution_invincible = false
		_substitution_timer = 0.0
		_update_hitbox_collision_state()
		substitution_invincibility_ended.emit()
		
		if debug_team:
			print("[替身无敌] %s 时间到，自动结束" % name)

func set_cd(slot_id: int, cd_id: int, cd: float):
	match entity_type:
		EntityType.PLAYER:
			skill_slot[slot_id].set_cd(cd)
	for i in cool_down_time.size():
		if cool_down_time[i]["slot_id"] == slot_id:
			cool_down_time[i]["slot_id"] = -114514
	cool_down_time[cd_id] = {"time": cd, "slot_id": slot_id}

func set_timer(slot_id: int, cd_id: int, cd: float, cd_max: float):
	_remove_sub_slot_from_all(slot_id)
	match entity_type:
		EntityType.PLAYER:
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
					if sid >= 0:
						skill_slot[sid].timer_progress = 0

func set_modifiers(type: String, pow: int, time: float = -2,
		on_start: String = "", on_update: String = "", on_end: String = ""):
	for i in modifiers.size():
		if modifiers[i]["type"] == type:
			modifiers[i]["power"] = pow
			modifiers[i]["time"] = time
			modifiers[i]["on_start"] = on_start
			modifiers[i]["on_update"] = on_update
			modifiers[i]["on_end"] = on_end
			modifiers[i]["_started"] = false
			return
	modifiers.append({
		"time": time, "type": type, "power": pow,
		"on_start": on_start, "on_update": on_update, "on_end": on_end,
		"_started": false
	})

func _process_cd(delta):
	for i in cool_down_time.size():
		if cool_down_time[i]["time"] > 0:
			cool_down_time[i]["time"] -= delta
			if cool_down_time[i]["time"] < 0:
				cool_down_time[i]["time"] = 0
			if cool_down_time[i]["slot_id"] >= 0:
				match entity_type:
					EntityType.PLAYER:
						skill_slot[cool_down_time[i]["slot_id"]].cool_down_time_now = cool_down_time[i]["time"]

func _process_timer(delta):
	for i in skill_timer.size():
		if skill_timer[i]["time"] > 0:
			skill_timer[i]["time"] -= delta
			if skill_timer[i]["time"] < 0:
				skill_timer[i]["time"] = 0
				on_timer_out(i)
			if skill_timer[i]["slot_id"] >= 0 or skill_timer[i].get("sub_slots", []).size() > 0:
				match entity_type:
					EntityType.PLAYER:
						var p = skill_timer[i]["time"] / skill_timer[i]["max_time"]
						if skill_timer[i]["slot_id"] >= 0:
							skill_slot[skill_timer[i]["slot_id"]].timer_progress = p
						for sid in skill_timer[i].get("sub_slots", []):
							if sid >= 0:
								skill_slot[sid].timer_progress = p

func on_timer_out(cd_id: int):
	pass
	#print("timerout",cd_id)

func _process_modifiers(delta):
	for i in modifiers.size():
		if modifiers[i]["time"] > 0 or modifiers[i]["time"] == -2:
			# 效果启动（仅首次）
			if not modifiers[i].get("_started", false):
				modifiers[i]["_started"] = true
				var cb = modifiers[i].get("on_start", "")
				if cb and has_method(cb):
					call(cb, self)
				_on_modifier_start(modifiers[i]["type"], modifiers[i]["power"], modifiers[i]["time"])
			# 效果运行（每帧）
			handle_modifiers_solo(i)
			var cb = modifiers[i].get("on_update", "")
			if cb and has_method(cb):
				call(cb, self)
			_on_modifier_update(modifiers[i]["type"], modifiers[i]["power"], modifiers[i]["time"])
			# 计时
			if modifiers[i]["time"] > 0:
				modifiers[i]["time"] -= delta
				if modifiers[i]["time"] < 0:
					modifiers[i]["time"] = 0
		else:
			if modifiers[i]["time"] == 0:
				handle_modifiers_reverse_solo(i)
				# 效果结束
				var cb = modifiers[i].get("on_end", "")
				if cb and has_method(cb):
					call(cb, self)
				_on_modifier_end(modifiers[i]["type"], modifiers[i]["power"], modifiers[i]["time"])
				modifiers[i]["time"] = -1

func _on_modifier_start(type: String, power: int, time_left: float = -2.0):
	pass

func _on_modifier_update(type: String, power: int, time_left: float = -2.0):
	pass

func _on_modifier_end(type: String, power: int, time_left: float = -2.0):
	pass

func bind_cd(slot_id: int, cd_id: int):
	match entity_type:
		EntityType.PLAYER:
			skill_slot[slot_id].set_cd(cool_down_time[cd_id]["time"])
	for i in cool_down_time.size():
		if cool_down_time[i]["slot_id"] == slot_id:
			cool_down_time[i]["slot_id"] = -1
	cool_down_time[cd_id]["slot_id"] = slot_id

func set_slot_aura(slot_id: int, show: bool):
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
	_remove_sub_slot_from_all(slot_id)
	if not skill_timer[cd_id].has("sub_slots"):
		skill_timer[cd_id]["sub_slots"] = []
	if slot_id not in skill_timer[cd_id]["sub_slots"]:
		skill_timer[cd_id]["sub_slots"].append(slot_id)
	match entity_type:
		EntityType.PLAYER:
			var p = skill_timer[cd_id]["time"] / skill_timer[cd_id]["max_time"] if skill_timer[cd_id]["max_time"] > 0 else 0
			skill_slot[slot_id].timer_progress = p

## 取消计时的某槽位附属
func remove_timer_sub_slot(cd_id: int, slot_id: int):
	if skill_timer[cd_id].has("sub_slots"):
		skill_timer[cd_id]["sub_slots"].erase(slot_id)

## 清除某计时的所有槽位附属
func clear_timer_sub_slots(cd_id: int):
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

func change_hp(d: int, show_number: bool = false, kv: float = 0.0, can_variation: bool = false, is_critical: bool = false):
	if d < 0:
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
	
	var old_hp = hp
	# 奥义期间无视保护值
	var _ignore_protection = _last_attacker and _last_attacker.ultimate_active
	hp += d if _ignore_protection else d * (1-calculate_protection_value(float(cumulative_launch_damage) / hp_max))
	if hp < 0:
		hp = 0
		if _last_attacker and _last_attacker.ultimate_active and not is_dead:
			_trigger_ultimate_kill_effect()
		hit(HitStateType.LAUNCH, Vector2(-300 * facing_direction, 0), 0.5, 280, true, true)
	elif hp > hp_max:
		hp = hp_max
	
	var epos = position_3d
	epos.z -= 150
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

func _reset_attack_state():
	clear_temporary_status()
	clear_attack_state()

func clear_attack_state():
	is_attacking = false
	current_attack = ""
	_waiting_for_land = false

func hit(hit_type: HitStateType,
		 kv: Vector2, hit_stun_time: float,
		 zv: float, can_OTG: bool,
		 is_heavy: bool, state: BodyState = BodyState.NORMAL,
		 hurt: float = 0.0,
		 kr: float = 10.0):
	
	if state < body_state:
		return
	if have_modifiers("customBodyState"):
		set_modifiers("customBodyState", BodyState.NORMAL, 0)
	body_state = BodyState.NORMAL
	clear_attack_state()
	
	# 根据轻重击随机选择眩晕动画
	var stun_ani: String = "stun" + str(randi() % 2 + (1 if is_heavy else 3))
	
	var is_launched = _launch_active and !get_is_low_floating()
	var is_downed = (_launch_active and get_is_low_floating()) or _is_downed
	
	# 处理平推
	if hit_type == HitStateType.PUSH:
		set_knockback(kv, hit_stun_time, kr)
		
		if is_launched:
			set_hit_stun(hit_stun_time, stun_ani)
			set_launch(zv, "launch2")
		elif is_downed:
			if can_OTG:
				set_hit_stun(hit_stun_time, stun_ani)
				set_launch(zv * 1.5, "launch1")
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
	elif hit_type == HitStateType.LAUNCH:
		if is_downed and can_OTG:
			launched_flag = true
			set_knockback(kv, hit_stun_time, kr)
			set_launch(zv * 1.2, "launch1")
		elif !is_downed or (get_is_low_floating() and !_is_downed):
			launched_flag = true
			set_knockback(kv, hit_stun_time, kr)
			# 高度 <= 10: 1.2倍速, launch1; 高度 > 10: 1.0倍速, launch2
			# set_launch(zv * (1 + 0.2 * int(position_3d.z <= 10)), "launch" + str(2 - int(position_3d.z <= 10)), g)
			set_launch(zv, "launch2")
	
	_immobilize_release_active = false
	
	change_hp_float(-hurt, kv.x)

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
	if _immobilize_active:  # 新增：被抓取时直接清除并中断吸附
		_magnetism_time = 0
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
	if _immobilize_time == -1:
		return
	
	_immobilize_time -= delta
	
	if _immobilize_time <= 0:
		stop_immobilize()

func set_immobilize(pos: Vector3, time: float = -1, rpos: Vector3 = pos,
					ani: String = "",
					kv: Vector2 = Vector2.ZERO, knockback_time: float = 0,
					launch: float = 0, launch_g: float = 700,
					state: BodyState = BodyState.SUPER_ARMOR):
	
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
	
	save_hit_stop()

func stop_immobilize():
	if have_modifiers("customBodyState"):
		set_modifiers("customBodyState", BodyState.NORMAL, 0)
	position_3d = _immobilize_release_position
	if position_3d.z <= ground_level:
		position_3d.z = ground_level
	_last_valid_wall_pos = Vector2(position_3d.x, position_3d.y)
	_immobilize_active = false
	_immobilize_release_active = true
	var is_downed = (_launch_active and get_is_low_floating()) or _is_downed
	var ani: String = "launch2"
	if is_downed:
		ani = "launch1"
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

func set_hit_stop(duration: float, freeze_frame: bool = true, prevent_physics: bool = true):
	"""设置卡肉时间 - 冻结所有运动，结束后继续"""
	_hit_stop_active = true
	_hit_stop_timer = duration
	_hit_stop_freeze_frame = freeze_frame
	_hit_stop_prevent_physics = prevent_physics
	
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

func replay_buffered_input(action: String, pressed: bool):
	if _can_perform_action(action):
		_execute_action(action)

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

func _end_hit_stop():
	"""结束卡肉 - 恢复所有运动状态"""
	_hit_stop_active = false
	_consume_buffer()
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
		_launch_velocity_z -= _launch_gravity * delta * 1+0.38*calculate_protection_value(float(cumulative_launch_damage) / hp_max)
	
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
	if have_modifiers("customBodyState"):
		set_modifiers("customBodyState", BodyState.NORMAL, 0)

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
	
	# 强制设置重力，确保生效
	_launch_gravity = 700.0  # 默认值
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
		if Input.is_action_pressed(action_name):
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
func _add_to_local_buffer(slot_id: int, action_name: String, priority: int) -> void:
	# 复用全局缓冲队列（_input_buffer）
	_add_to_buffer(action_name, priority)   # 你已有的 _add_to_buffer 只存 action，需要拓展
	# 但 _add_to_buffer 只存 action 和 priority，丢掉了 slot_id
	# 建议改造 _add_to_buffer 支持 slot_id，或者新建一个方法
	# 简单处理：直接复用但记录 slot_id
	# 为避免修改太多，重新实现一个 _add_to_local_buffer 方法：
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
		"frame": Engine.get_frames_drawn(),
		"slot_id": slot_id   # 新增 slot_id
	})

# 消费本地缓冲（每帧或适当时机调用）
func _consume_local_buffer() -> void:
	var now = Engine.get_frames_drawn()
	_input_buffer = _input_buffer.filter(func(cmd): return now - cmd.frame <= buffer_valid_frames)
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
		_execute_action_by_slot(best.get("slot_id", -1), best.action)
		# 清除刚执行的指令
		_input_buffer = _input_buffer.filter(func(c): return c.priority > best.priority)

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
		"frame": Engine.get_frames_drawn()
	})

# 消费缓冲
func _consume_buffer():
	var now = Engine.get_frames_drawn()
	_input_buffer = _input_buffer.filter(func(cmd): return now - cmd.frame <= buffer_valid_frames)
	
	if _input_buffer.is_empty():
		return
	
	# 选出最高优先级的指令（同优先级取最早）
	var best_cmd = _input_buffer.reduce(func(best, current):
		if current.priority > best.priority:
			return current
		elif current.priority == best.priority:
			return current if current.frame < best.frame else best
		return best
	)
	
	if not _can_perform_action(best_cmd.action):
		return
	
	# 优先级高于当前动作 ⇒ 中断当前动作
	if _is_executing_action and best_cmd.priority > _current_action_priority:
		_interrupt_current_action()
	
	_execute_action(best_cmd.action)
	_input_buffer = _input_buffer.filter(func(cmd): return cmd.action != best_cmd.action)

func _can_perform_action(action: String) -> bool:
	if hp <= 0 or _immobilize_active:
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

func _execute_action(action: String):
	_is_executing_action = true
	_current_action_priority = _get_action_priority(action)
	
	if is_player:
		match action:
			"attack":
				inputs[0] = true
			"skill1":
				inputs[1] = true
			"skill2":
				inputs[2] = true
			"skill3":
				inputs[3] = true
			"substitution":
				inputs[4] = true
			"scroll":
				inputs[5] = true
			"summon":
				inputs[6] = true
	_entity_input()

func _on_action_finished():
	_is_executing_action = false
	_current_action_priority = ActionPriority.NORMAL_ATTACK
	_consume_buffer()

func button_can_press(slot_id):
	if entity_type == EntityType.PLAYER:
		return skill_slot[slot_id]._can_press()
	else:
		var can_press = true
		if cool_down_time[get_slot_cd(slot_id)]["time"] > 0:
			can_press = false
		if skill_slot[slot_id].is_charging and skill_slot[slot_id].dot <= 0:
			can_press = false
		return can_press

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
	inputs[slot_id] = compare_input_solo(handle_input_key_solo(Input.is_action_pressed(action), slot_id), use_touch and skill_slot[slot_id]._button_pressed and skill_slot[slot_id].is_finger_inside())

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
	
	# 根据是否在地面决定阻力倍率（地面阻力是空中的三倍）
	var current_resistance = _knockback_resistance
	if is_grounded:
		current_resistance = _knockback_resistance * 1.3
	
	# 应用阻力（使用动态计算出的阻力值）
	_knockback_velocity = _knockback_velocity.lerp(Vector2.ZERO, current_resistance * delta)
	
	# 减少击退时间
	_knockback_timer -= delta
	
	# 检查是否结束击退
	if _knockback_velocity.length() < 5.0:
		_stop_knockback()

# 开始击退
func set_knockback(velocity: Vector2, duration: float, resistance: float = -1.0):
	if _immobilize_active: return
	
	"""开始击退，不影响控制状态
	
	参数:
		velocity: 初始击退速度
		duration: 击退持续时间（秒）
		resistance: 阻力系数（默认10.0，越大停得越快）
	"""
	_knockback_velocity = velocity
	_knockback_timer = duration
	
	if resistance > 0:
		_knockback_resistance = resistance
	
	_knockback_active = true
	
	if debug_slide:
		print("[击退] 开始 | 速度:%s | 时长:%.2f | 阻力:%.1f" % [
			str(velocity), duration, _knockback_resistance
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

func _on_death():
	"""虚方法，死亡时调用。由子类/VisualScriptComponent重写"""
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
		z_velocity_override = move_toward(z_velocity_override, 0, z_slide_resistance * delta * 100)
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
	
	slide_velocity = direction.normalized() * slide_speed
	
	if resistance >= 0:
		slide_resistance = resistance

func stop_slide():
	is_sliding = false
	slide_velocity = Vector2.ZERO
	velocity_3d.x = 0
	velocity_3d.y = 0
	velocity_smoothed = Vector2.ZERO

func modify_slide_velocity(delta_velocity: Vector2):
	slide_velocity += delta_velocity

func set_slide_resistance(resistance: float):
	slide_resistance = max(0.1, resistance)

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
	
	# 先应用帧数据（这会计算实际帧）
	_apply_frame_data()
	_process_frame_event()
	_process_effect_bindings(current_animation, get_current_frame())

func _on_animation_finished():
	if entry_action != EntryAction.NONE:
		pass
	
	if slide_sequences.has(current_animation):
		_clear_slide_sequence()
	
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

func _process_frame_event():
	if not frame_events_enabled:
		return
	
	var frame_key = "%s_%d" % [current_animation, get_current_frame()]
	
	if processed_frames.has(frame_key):
		return
	
	processed_frames[frame_key] = true
	
	_process_slide_sequence(current_animation, get_current_frame())
	_on_frame_trigger(current_animation, get_current_frame())
	_handle_frame_spe(current_animation, get_current_frame())

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
				var scene = load(scene_path)
				if scene:
					# 注册后走标准 spawn 方法，保证与 effect_name 路径行为一致
					var reg_name = "_efb_" + binding.get("id", "tmp")
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
	if _immobilize_active:
		return
	
	if can_cast_aux:
		if inputs[5]:
			play_animation("scroll")
		elif inputs[6]:
			if summon_entity_path.size() > 0:
				play_animation("summon")
	
	# 受击释放效果
	if is_under_control:
		if inputs[4] and !current_animation == "substitution":
			# 必须能扣豆才行
			if ultimate_point <= 0:
				return
			change_ultimate_point(-1)
			set_cd(4, 4, 15)
			
			_end_launch_sequence(false)
			set_knockback(Vector2(0, 0), 0)
			
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
	
	var prev_speed = slide_velocity.length()
	slide_velocity = slide_velocity.lerp(Vector2.ZERO, slide_resistance * delta)
	var new_speed = slide_velocity.length()
	
	if new_speed < 5.0:
		stop_slide()
		return
	
	velocity_3d.x = slide_velocity.x
	velocity_3d.y = slide_velocity.y

func _apply_facing():
	if visuals_node:
		visuals_node.scale.x = facing_direction

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
	
	var base_speed_x = entity_data.move_speed_x if entity_data else 300.0
	var base_speed_y = entity_data.move_speed_y if entity_data else 300.0
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
		_sync_frame_data(current_anim, visual_frame)

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
	"""获取当前实际显示的精灵帧索引（处理多帧动画）"""
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
	var safe_frame = clamp(get_current_frame(), 0, frame_count - 1)
	
	var current_tex = frames.get_frame_texture(current_animation, safe_frame)
	
	# 查找这个纹理对应的第一个帧索引
	for i in range(frame_count):
		if frames.get_frame_texture(current_animation, i) == current_tex:
			return i
	
	return safe_frame

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
	
	visuals_node.position = Vector2(
		-adjusted_offset.x * get_anim_sprite_scale().x,
		-adjusted_offset.y * get_anim_sprite_scale().y
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
		visuals_node.scale.x = dir
	
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
	
	# 3. 安全获取形状尺寸
	var atk_size = _get_rect_size_safe(atk_node)
	var def_size = _get_rect_size_safe(def_node)
	
	# 【兜底触发点 2】：如果形状获取失败或不是矩形
	if atk_size == Vector2.ZERO or def_size == Vector2.ZERO:
		return _get_random_point_on_area(def_node)
		
	# 4. 构建矩形并计算相交区域
	var atk_rect = Rect2(atk_node.global_position - atk_size * 0.5, atk_size)
	var def_rect = Rect2(def_node.global_position - def_size * 0.5, def_size)
	
	var inter_rect = atk_rect.intersection(def_rect)
	
	# 【兜底触发点 3】：如果两者没有实际重叠区域（比如刚好擦边没碰到）
	if inter_rect.size.x <= 0 or inter_rect.size.y <= 0:
		return _get_random_point_on_area(def_node)
		
	# 5. 正常逻辑：在相交区域内随机取点
	inter_rect = inter_rect.grow_individual(
		-inter_rect.size.x * 0.1, -inter_rect.size.y * 0.1, 
		-inter_rect.size.x * 0.1, -inter_rect.size.y * 0.1
	)
	
	return Vector2(
		randf_range(inter_rect.position.x, inter_rect.end.x),
		randf_range(inter_rect.position.y, inter_rect.end.y)
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
	
	# 计算目标速度（基于传入的参数）
	var target_vel = Vector2(
		input_dir.x * _free_move_speed.x,
		input_dir.y * _free_move_speed.y
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

func get_out_of_wall(pos_3d: Vector3):
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

func show_info_text(text: String):
	if info_animation_player.is_playing(): return
	info_label.text = text
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
