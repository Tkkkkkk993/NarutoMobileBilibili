# animated_sprite_2d_entity.gd
# ============================================
# 基于 AnimatedSprite2D 的实体实现
# 继承 EntityBase，提供 2D 精灵帧动画支持
# ============================================
# 未来可扩展 SpineAnimator、SkeletonAnimator 等不同动画实现

class_name AnimatedSprite2DEntity
extends EntityBase

# ============================================
# 节点引用 (AnimatedSprite2D 专用)
# ============================================

var animated_sprite: AnimatedSprite2D

# ============================================
# VisualScriptComponent 引用
# ============================================

var _vs_component: VisualScriptComponent
var _vs_has_script: bool = false

# ============================================
# 公共抽象方法实现
# ============================================

func get_animator_node() -> Node:
	return animated_sprite

func has_animation(anim_name: String) -> bool:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return false
	return animated_sprite.sprite_frames.has_animation(anim_name)

func play_animation(anim_name: String, custom_speed: float = -1.0):
	super.play_animation(anim_name, custom_speed)
	if not animated_sprite or not is_instance_valid(animated_sprite):
		return
	if has_animation(anim_name):
		if custom_speed > 0:
			animated_sprite.play(anim_name, custom_speed)
		else:
			animated_sprite.play(anim_name)

func get_current_frame() -> int:
	return animated_sprite.frame if animated_sprite and is_instance_valid(animated_sprite) else 0

func get_current_animation() -> String:
	if animated_sprite and is_instance_valid(animated_sprite):
		return animated_sprite.animation
	return ""

func get_current_frame_texture() -> Texture2D:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return null
	var anim = animated_sprite.animation
	var frame = animated_sprite.frame
	if not anim or not animated_sprite.sprite_frames.has_animation(anim):
		return null
	if frame < 0 or frame >= animated_sprite.sprite_frames.get_frame_count(anim):
		return null
	return animated_sprite.sprite_frames.get_frame_texture(anim, frame)

func pause_animation():
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.pause()

func resume_animation():
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.play()

func set_animation_frame(frame_idx: int):
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.frame = frame_idx

func get_animation_frame_count(anim_name: String) -> int:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return 0
	return animated_sprite.sprite_frames.get_frame_count(anim_name)

func get_animation_speed_scale() -> float:
	if animated_sprite and is_instance_valid(animated_sprite):
		return animated_sprite.speed_scale
	return 1.0

func set_animation_speed_scale(speed: float):
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.speed_scale = speed

func get_anim_sprite_scale() -> Vector2:
	if animated_sprite and is_instance_valid(animated_sprite):
		return animated_sprite.scale
	return Vector2.ONE

func get_anim_global_scale() -> Vector2:
	if animated_sprite and is_instance_valid(animated_sprite):
		return animated_sprite.global_scale
	return Vector2.ONE

func get_anim_global_position() -> Vector2:
	if animated_sprite and is_instance_valid(animated_sprite):
		return animated_sprite.global_position
	return Vector2.ZERO

func get_anim_material() -> Material:
	if animated_sprite and is_instance_valid(animated_sprite):
		return animated_sprite.material
	return null

func set_anim_material(mat: Material):
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.material = mat

func set_anim_self_modulate(color: Color):
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.self_modulate = color

func stop_animation():
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.stop()

func get_animation_list() -> PackedStringArray:
	if animated_sprite and animated_sprite.sprite_frames:
		return animated_sprite.sprite_frames.get_animation_names()
	return PackedStringArray()

# ============================================
# 初始化
# ============================================

func _ready():
	# 先让父类初始化（_setup_components 会设置 visuals_node）
	super._ready()
	
	# 寻找 AnimatedSprite2D（此时 visuals_node 已可用，与原始代码逻辑一致）
	if visuals_node:
		animated_sprite = visuals_node.get_node_or_null("AnimatedSprite2D")
	if not animated_sprite:
		animated_sprite = get_node_or_null("AnimatedSprite2D")
	if not animated_sprite:
		# 递归搜索作为兜底
		for child in get_children():
			if child is AnimatedSprite2D:
				animated_sprite = child
				break
			for subchild in child.get_children():
				if subchild is AnimatedSprite2D:
					animated_sprite = subchild
					break
			if animated_sprite:
				break
	
	if animated_sprite:
		# 连接信号（不停止动画，保持原有播放状态）
		if not animated_sprite.frame_changed.is_connected(_on_frame_changed):
			animated_sprite.frame_changed.connect(_on_frame_changed)
		if not animated_sprite.animation_changed.is_connected(_on_animation_changed):
			animated_sprite.animation_changed.connect(_on_animation_changed)
		if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
			animated_sprite.animation_finished.connect(_on_animation_finished)
	
	# 设置 shader 材质（闪烁效果）
	if animated_sprite:
		var shader_material = ShaderMaterial.new()
		shader_material.shader = preload("res://shader/entity_animated_sprite_shader.gdshader")
		animated_sprite.material = shader_material
		animated_sprite.self_modulate = Color(1, 1, 1, 1)
	
	# 自动挂载 VisualScriptComponent（如果存在 visual_script.json）
	if res_path != "":
		var script_path = res_path.get_base_dir() + "/visual_script.json"
		if FileAccess.file_exists(script_path):
			_vs_component = VisualScriptComponent.new()
			_vs_component._entity = self
			_vs_component.name = "VisualScriptComponent"
			add_child(_vs_component)
			_vs_has_script = true

func _setup_hitboxes():
	"""收集 AnimatedSprite2D 下的受击框 Area2D 子节点"""
	if not animated_sprite:
		return
	hitbox_areas.clear()
	for child in animated_sprite.get_children():
		if child is Area2D:
			hitbox_areas.append(child)
			# 复制碰撞形状，避免共享 SubResource 影响其他实体
			var shape_node = child.get_child(0) as CollisionShape2D
			if shape_node and shape_node.shape:
				shape_node.shape = shape_node.shape.duplicate()

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

func _on_frame_changed():
	# 先执行父类逻辑：帧数据应用、帧事件处理、特效绑定
	super._on_frame_changed()
	_on_frame_trigger(get_current_animation(), get_current_frame())

func _on_animation_changed():
	# 父类处理：current_animation更新、帧数据强制应用、锚点约束、滑步序列、动画进入回调
	super._on_animation_changed()
