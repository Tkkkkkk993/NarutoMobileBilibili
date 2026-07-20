# animation_player_entity.gd
# ============================================
# 基于 AnimationPlayer 的实体实现
# 继承 EntityBase，提供 3D 骨骼动画 / 关键帧动画支持
# 帧时间基准: 1 帧 = 1/60 秒
# ============================================

class_name AnimationPlayerEntity
extends EntityBase

const ANIM_FPS := 60.0

# ============================================
# 节点引用 (AnimationPlayer 专用)
# ============================================

var animation_player: AnimationPlayer
var _last_frame: int = -1

# ============================================
# VisualScriptComponent 引用
# ============================================

var _vs_component: VisualScriptComponent
var _vs_has_script: bool = false

# ============================================
# 公共抽象方法实现
# ============================================

func get_animator_node() -> Node:
	return animation_player

func has_animation(anim_name: String) -> bool:
	if not animation_player or not is_instance_valid(animation_player):
		return false
	return animation_player.has_animation(anim_name)

func play_animation(anim_name: String, custom_speed: float = -1.0):
	super.play_animation(anim_name, custom_speed)
	if not animation_player or not is_instance_valid(animation_player):
		return
	if has_animation(anim_name):
		var speed = custom_speed if custom_speed > 0 else 1.0
		animation_player.speed_scale = speed
		animation_player.stop(true)
		animation_player.play(anim_name)
		_last_frame = -1

func get_current_frame() -> int:
	if animation_player and is_instance_valid(animation_player) and animation_player.is_playing():
		return int(animation_player.current_animation_position * ANIM_FPS)
	return 0

func get_current_animation() -> String:
	if animation_player and is_instance_valid(animation_player):
		return animation_player.current_animation
	return ""

func pause_animation():
	if animation_player and is_instance_valid(animation_player):
		animation_player.pause()

func resume_animation():
	if animation_player and is_instance_valid(animation_player):
		animation_player.play()

func set_animation_frame(frame_idx: int):
	if animation_player and is_instance_valid(animation_player):
		animation_player.seek(frame_idx / ANIM_FPS, true)

func get_animation_frame_count(anim_name: String) -> int:
	if not animation_player or not is_instance_valid(animation_player):
		return 0
	var anim = animation_player.get_animation(anim_name)
	if not anim:
		return 0
	return int(anim.length * ANIM_FPS)

func get_current_frame_texture() -> Texture2D:
	if not visuals_node or not is_instance_valid(visuals_node):
		return null
	# 优先从 SubViewport 取渲染纹理（3D 骨骼动画）
	var svp_container = visuals_node.get_node_or_null("SubViewportContainer")
	if svp_container:
		var svp = svp_container.get_node_or_null("SubViewport") as SubViewport
		if svp:
			return svp.get_texture()
	return null

func get_animation_speed_scale() -> float:
	if animation_player and is_instance_valid(animation_player):
		return animation_player.speed_scale
	return 1.0

func set_animation_speed_scale(speed: float):
	if animation_player and is_instance_valid(animation_player):
		animation_player.speed_scale = speed

func stop_animation():
	if animation_player and is_instance_valid(animation_player):
		animation_player.stop()

func get_animation_list() -> PackedStringArray:
	if animation_player and is_instance_valid(animation_player):
		return animation_player.get_animation_list()
	return PackedStringArray()

# ============================================
# 材质 / 缩放 / 位置 (AnimationPlayer 本身不渲染，委托给 visuals_node 或根节点)
# ============================================

func get_anim_sprite_scale() -> Vector2:
	if visuals_node and is_instance_valid(visuals_node):
		return visuals_node.scale
	return Vector2.ONE

func get_anim_global_scale() -> Vector2:
	if visuals_node and is_instance_valid(visuals_node):
		return visuals_node.global_scale
	return Vector2.ONE

func get_anim_global_position() -> Vector2:
	if visuals_node and is_instance_valid(visuals_node):
		return visuals_node.global_position
	return Vector2.ZERO

func get_anim_material() -> Material:
	if visuals_node and is_instance_valid(visuals_node):
		return visuals_node.material
	return null

func set_anim_material(mat: Material):
	if visuals_node and is_instance_valid(visuals_node):
		visuals_node.material = mat

func set_anim_self_modulate(color: Color):
	if visuals_node and is_instance_valid(visuals_node):
		visuals_node.self_modulate = color

# ============================================
# _process: 帧变化检测 (AnimationPlayer 无 frame_changed 信号)
# ============================================

func _process(delta: float):
	super._process(delta)
	if not animation_player or not is_instance_valid(animation_player):
		return
	if not animation_player.is_playing():
		return
	var cur_frame = get_current_frame()
	if cur_frame != _last_frame:
		_last_frame = cur_frame
		_on_frame_changed()

# ============================================
# 初始化
# ============================================

func _ready():
	super._ready()
	
	# 寻找 AnimationPlayer（优先在 visuals_node 下查找）
	if visuals_node:
		for child in visuals_node.get_children():
			if child is AnimationPlayer:
				animation_player = child
				break
		# 也检查 SubViewport 路径下的 AnimationPlayer
		if not animation_player:
			var svp_container = visuals_node.get_node_or_null("SubViewportContainer")
			if svp_container:
				var svp = svp_container.get_node_or_null("SubViewport")
				if svp:
					for child in svp.get_children():
						animation_player = _find_animation_player_recursive(child)
						if animation_player:
							break
	
	if not animation_player:
		animation_player = _find_animation_player_recursive(self)
	
	if animation_player:
		# AnimationPlayer 无 frame_changed 信号，由 _process 轮询检测
		if not animation_player.animation_finished.is_connected(_on_animation_finished):
			animation_player.animation_finished.connect(_on_animation_finished)
		if not animation_player.animation_changed.is_connected(_on_animation_changed):
			animation_player.animation_changed.connect(_on_animation_changed)
	
	# 设置 shader 材质（闪烁效果）
	if visuals_node and is_instance_valid(visuals_node):
		var shader_material = ShaderMaterial.new()
		shader_material.shader = preload("res://shader/entity_animated_sprite_shader.gdshader")
		visuals_node.material = shader_material
		visuals_node.self_modulate = Color(1, 1, 1, 1)
	
	# 自动挂载 VisualScriptComponent（如果存在 visual_script.json）
	if res_path != "":
		var script_path = res_path.get_base_dir() + "/visual_script.json"
		if FileAccess.file_exists(script_path):
			_vs_component = VisualScriptComponent.new()
			_vs_component._entity = self
			_vs_component.name = "VisualScriptComponent"
			add_child(_vs_component)
			_vs_has_script = true

func _find_animation_player_recursive(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var result = _find_animation_player_recursive(child)
		if result:
			return result
	return null

func _setup_hitboxes():
	"""收集实体下的受击框 Area2D 子节点"""
	hitbox_areas.clear()
	if visuals_node:
		_collect_area2d_recursive(visuals_node)
	for child in get_children():
		if child != visuals_node:
			_collect_area2d_recursive(child)

func _collect_area2d_recursive(root: Node):
	for child in root.get_children():
		if child is Area2D:
			hitbox_areas.append(child)
			var shape_node = child.get_child(0) as CollisionShape2D
			if shape_node and shape_node.shape:
				shape_node.shape = shape_node.shape.duplicate()
		_collect_area2d_recursive(child)

# ============================================
# VisualScriptComponent 初始化
# ============================================

func _deferred_heavy_init():
	super._deferred_heavy_init()

func _deferred_heavy_init_phase4():
	super._deferred_heavy_init_phase4()
	if _vs_has_script and _vs_component:
		call_deferred("_vs_init_component")

func _vs_init_component():
	if _vs_component:
		_vs_component._vs_init()

# ============================================
# VS 事件委托 (将实体事件转发给组件)
# ============================================

func _on_attack_hit(hit_result):
	super._on_attack_hit(hit_result)
	if _vs_component:
		_vs_component._on_attack_hit(hit_result)

func setup_icon():
	super.setup_icon()
	if _vs_component:
		_vs_component.setup_icon()

func on_timer_out(cd_id: int):
	super.on_timer_out(cd_id)
	if _vs_component:
		_vs_component.on_timer_out(cd_id)

func _on_deal_hit(attacker: Node2D):
	super._on_deal_hit(attacker)
	if _vs_component:
		_vs_component._on_deal_hit(attacker)

func _on_death():
	super._on_death()
	if _vs_component:
		_vs_component._on_death()

func _on_modifier_start(type: String, power: int, time_left: float = -2.0):
	super._on_modifier_start(type, power, time_left)
	if _vs_component:
		_vs_component._on_modifier_start(type, power, time_left)

func _on_modifier_update(type: String, power: int, time_left: float = -2.0):
	super._on_modifier_update(type, power, time_left)
	if _vs_component:
		_vs_component._on_modifier_update(type, power, time_left)

func _on_modifier_end(type: String, power: int, time_left: float = -2.0):
	super._on_modifier_end(type, power, time_left)
	if _vs_component:
		_vs_component._on_modifier_end(type, power, time_left)
