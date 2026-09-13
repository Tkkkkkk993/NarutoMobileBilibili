# composite_renderer_entity.gd
# ============================================
# 基于 UFE 碎片拼合的实体渲染器
# 继承 EntityBase，从 UFEDataCache 读取 sprites/animations 数据
# 通过多个 Sprite2D 子节点拼合出完整角色姿态
# ============================================

class_name CompositeRendererEntity
extends EntityBase

# ============================================
# 部件节点池
# ============================================

var _part_nodes: Dictionary = {}  # {sprite_id: Sprite2D}

# ============================================
# 帧引擎状态
# ============================================

var _current_anim: String = ""
var _current_frame: int = 0
var _frame_timer: float = 0.0
var _speed_scale: float = 1.0
var _paused: bool = false
var _loop: bool = true

# VisualScriptComponent
var _vs_component: VisualScriptComponent
var _vs_has_script: bool = false

# ============================================
# EntityBase 抽象接口实现
# ============================================

func get_animator_node() -> Node:
	return self

func has_animation(anim_name: String) -> bool:
	return UFEDataCache.animations.has(anim_name)

func play_animation(anim_name: String, custom_speed: float = 1.0):
	if _immobilize_active:
		return
	if not has_animation(anim_name):
		return
	current_animation = anim_name
	_current_anim = anim_name
	_current_frame = 0
	_frame_timer = 0.0
	_speed_scale = custom_speed if custom_speed > 0 else 1.0
	_paused = false
	# 读取循环设置（默认循环）
	var anim_data: Dictionary = UFEDataCache.animations[anim_name]
	_loop = anim_data.get("loop", true)
	# 通知 EntityBase 动画已变更（触发锚点/滑步/入场等）
	_on_animation_changed()
	_apply_current_frame()

func get_current_frame() -> int:
	return _current_frame

func get_current_animation() -> String:
	return _current_anim

func get_animation_frame_count(anim_name: String) -> int:
	if not UFEDataCache.animations.has(anim_name):
		return 0
	return UFEDataCache.animations[anim_name].get("frames", {}).size()

func get_animation_list() -> PackedStringArray:
	return PackedStringArray(UFEDataCache.animations.keys())

func pause_animation():
	_paused = true

func resume_animation():
	_paused = false

func set_animation_frame(frame_idx: int):
	_current_frame = frame_idx
	_frame_timer = 0.0
	_apply_current_frame()

func set_animation_speed_scale(speed: float):
	_speed_scale = speed

func get_animation_speed_scale() -> float:
	return _speed_scale

func stop_animation():
	_paused = true
	_current_anim = ""
	for sp in _part_nodes.values():
		sp.visible = false

func get_current_frame_texture() -> Texture2D:
	# TODO: SubViewport 缓存方案（残影合成纹理）
	return null

func get_anim_sprite_scale() -> Vector2:
	if visuals_node:
		return visuals_node.scale
	return Vector2.ONE

func get_anim_global_scale() -> Vector2:
	if visuals_node:
		return visuals_node.global_scale
	return Vector2.ONE

func get_anim_global_position() -> Vector2:
	if visuals_node:
		return visuals_node.global_position
	return Vector2.ZERO

func get_anim_material() -> Material:
	if visuals_node:
		return visuals_node.material
	return null

func set_anim_material(mat: Material):
	if visuals_node:
		visuals_node.material = mat

func set_anim_self_modulate(color: Color):
	if visuals_node:
		visuals_node.self_modulate = color

# ============================================
# 初始化
# ============================================

func _ready():
	super._ready()

func _deferred_heavy_init():
	super._deferred_heavy_init()
	# 此时 visuals_node 已由 _setup_components() 设置
	if UFEDataCache.is_loaded():
		_create_part_nodes()
		if UFEDataCache.animations.has("idle"):
			play_animation("idle")
	else:
		push_warning("CompositeRendererEntity: UFEDataCache 未加载数据")

func _deferred_heavy_init_phase4():
	super._deferred_heavy_init_phase4()
	# 挂载 VisualScriptComponent
	if res_path != "":
		var script_path = res_path.get_base_dir() + "/visual_script.json"
		if FileAccess.file_exists(script_path):
			_vs_component = VisualScriptComponent.new()
			_vs_component._entity = self
			_vs_component.name = "VisualScriptComponent"
			add_child(_vs_component)
			_vs_has_script = true
		call_deferred("_vs_init_component")

func _vs_init_component():
	if _vs_component:
		_vs_component._vs_init()

# 不需要 AnimatedSprite2D 子节点收集
func _setup_hitboxes():
	pass

# 无 AnimatedSprite2D 信号可连
func _connect_signals():
	pass

# ============================================
# 创建部件节点（按 sprite_id 字母序）
# ============================================

func _create_part_nodes():
	if not visuals_node:
		return
	var sorted_ids := UFEDataCache.sprites.keys()
	sorted_ids.sort()
	for spr_id in sorted_ids:
		var sp := Sprite2D.new()
		sp.name = spr_id
		sp.centered = true
		sp.texture = UFEDataCache.get_texture(spr_id)
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.visible = false
		visuals_node.add_child(sp)
		_part_nodes[spr_id] = sp

# ============================================
# 帧引擎（_process 驱动）
# ============================================

func _process(delta: float):
	super._process(delta)
	if _paused or _current_anim.is_empty():
		return
	if not UFEDataCache.animations.has(_current_anim):
		return

	var anim_data: Dictionary = UFEDataCache.animations[_current_anim]
	var fps: float = anim_data.get("fps", 30.0)
	var frame_dur: float = 1.0 / fps
	var overrides: Dictionary = anim_data.get("frame_overrides", {})

	_frame_timer += delta * _speed_scale

	var extra: float = overrides.get(str(_current_frame), 0.0)
	if _frame_timer >= frame_dur + extra:
		_frame_timer -= frame_dur + extra
		_advance_frame()

func _advance_frame():
	var total = get_animation_frame_count(_current_anim)
	if total <= 0:
		return
	var next = _current_frame + 1
	if next >= total:
		if _loop:
			next = 0
		else:
			_paused = true
			_on_animation_finished()
			return
	_current_frame = next
	_apply_current_frame()

# ============================================
# 帧数据覆盖（锚点从 UFE 数据读取）
# ============================================

func _apply_frame_data_forced(anim_name: String, frame_idx: int):
	if not UFEDataCache.animations.has(anim_name):
		current_anchor_offset = Vector2.ZERO
		current_frame_data = null
		_apply_anchor_constraint()
		return
	var frames: Dictionary = UFEDataCache.animations[anim_name].get("frames", {})
	var fd: Dictionary = frames.get(str(frame_idx), {})
	var arr: Array = fd.get("anchor", [0.0, 0.0])
	current_anchor_offset = Vector2(arr[0], arr[1])
	_apply_anchor_constraint()

func _apply_frame_data():
	if _current_anim.is_empty():
		return
	if not UFEDataCache.animations.has(_current_anim):
		current_anchor_offset = Vector2.ZERO
		return
	var frames: Dictionary = UFEDataCache.animations[_current_anim].get("frames", {})
	var fd: Dictionary = frames.get(str(_current_frame), {})
	var arr: Array = fd.get("anchor", [0.0, 0.0])
	current_anchor_offset = Vector2(arr[0], arr[1])
	_apply_anchor_constraint()

# ============================================
# 核心：应用当前帧的部件姿态
# ============================================

func _apply_current_frame():
	if _current_anim.is_empty():
		return
	if not UFEDataCache.animations.has(_current_anim):
		return

	var frames: Dictionary = UFEDataCache.animations[_current_anim].get("frames", {})
	var fd: Dictionary = frames.get(str(_current_frame), {})
	var parts: Dictionary = fd.get("parts", {})
	var visible_set := {}

	for spr_name in parts:
		var p: Dictionary = parts[spr_name]
		var sp: Sprite2D = _part_nodes.get(spr_name)
		if not sp:
			continue
		if not UFEDataCache.sprites.has(spr_name):
			continue
		var s: Dictionary = UFEDataCache.sprites[spr_name]

		# 基础位置（cx/cy 已在 UFE 侧完成 Y 翻转）
		var pos := Vector2(s.get("cx", 0.0), s.get("cy", 0.0))
		# @scale 还原: PNG 已预缩放 at_scale 倍(名字 @N), 节点乘 1/at_scale 还原完整尺寸
		var at_scale: float = s.get("at_scale", 1.0)
		var inv_at: float = 1.0 / at_scale if at_scale > 0.0 else 1.0
		var sx: float = p.get("sx", 1.0) * inv_at
		var sy: float = p.get("sy", 1.0) * inv_at
		if sx != 1.0 or sy != 1.0:
			# pivot 修正用还原后完整尺寸, 缩放基准为动画原始缩放(sx/inv_at)
			var pw: float = s.get("w", 0.0) * inv_at
			var ph: float = s.get("h", 0.0) * inv_at
			var pivot_x: float = s.get("px", 0.5)
			var pivot_y: float = s.get("py", 0.5)
			pos.x -= (pivot_x - 0.5) * pw * (sx / inv_at - 1.0)
			pos.y -= (pivot_y - 0.5) * ph * (sy / inv_at - 1.0)

		sp.position = pos
		sp.scale = Vector2(sx, sy)
		sp.visible = true

		# z_index 覆盖（用于临时层级调整，如武器挥到身体前面）
		if p.has("z"):
			var new_z: int = int(p["z"])
			if sp.z_index != new_z:
				sp.z_index = new_z

		visible_set[spr_name] = true

	# 隐藏未出现的部件
	for spr_name in _part_nodes:
		if not visible_set.has(spr_name):
			_part_nodes[spr_name].visible = false

	# 通知 EntityBase 帧变化（驱动受击框、信息点、特效绑定）
	_on_frame_changed()

# ============================================
# EntityBase 帧事件回调
# ============================================

func _on_animation_changed():
	super._on_animation_changed()

func _on_frame_changed():
	super._on_frame_changed()
	_on_frame_trigger(get_current_animation(), get_current_frame())

func _on_attack_hit(hit_result):
	super._on_attack_hit(hit_result)
	if _vs_component:
		_vs_component._on_attack_hit(hit_result)

func setup_icon():
	super.setup_icon()
	if _vs_component:
		_vs_component.setup_icon()
