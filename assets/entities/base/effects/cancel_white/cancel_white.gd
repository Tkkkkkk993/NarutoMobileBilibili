extends EffectBase

var _target: Node2D


func _ready():
	_target = extra_data.get("target", null) if extra_data else null
	if not _target:
		push_warning("CancelWhite: 缺少 target")
		queue_free()
		return

	visible = true
	set_meta("sort_by_depth", true)
	var dm = get_node_or_null("/root/DepthManager")
	if dm and dm.has_method("register_entity"):
		dm.register_entity(self)

	_capture_and_spawn()


# 白影要盖在角色身上。基类在没有跟随目标时拿 z 当排序深度，而生成时传进来的 z 是高度，
# 白影因此排在角色前面画，整块被角色挡掉，只在轮廓外露出一圈白边。
# 这里直接取目标的深度再往前一点，排在角色之后画，白影才真的落在角色身上。
func get_depth_pos() -> Vector3:
	if _target and is_instance_valid(_target) and _target.has_method("get_depth_pos"):
		var target_depth: Vector3 = _target.get_depth_pos()
		return Vector3(pos_3d.x, target_depth.y + 0.1, 0.0)
	return super.get_depth_pos()


func _capture_and_spawn():
	if not _target.has_method("get_current_frame_texture"):
		queue_free()
		return
	var tex = _target.get_current_frame_texture()
	if not tex:
		queue_free()
		return

	# 真正画出这一帧的节点。白影与它同贴图、同 offset 与 centered、同缩放，才会严丝合缝。
	var anim_sprite: AnimatedSprite2D = _target.get("animated_sprite") as AnimatedSprite2D
	if anim_sprite and not is_instance_valid(anim_sprite):
		anim_sprite = null

	# 当前帧锚点相对动画节点原点的偏移（贴图像素）。帧数据的锚点在角色脚下，
	# 它既是白影要对齐的点，也是缩放该绕的支点。
	var anchor_offset := Vector2.ZERO
	if _target.has_method("get_current_anchor_info"):
		var info: Dictionary = _target.get_current_anchor_info()
		var raw_anchor = info.get("anchor_offset", null)
		if raw_anchor is Vector2:
			anchor_offset = raw_anchor

	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = tex
	var base_offset := Vector2.ZERO
	if anim_sprite:
		base_offset = anim_sprite.offset
		sprite.flip_h = anim_sprite.flip_h
		sprite.flip_v = anim_sprite.flip_v
		sprite.centered = anim_sprite.centered
	else:
		sprite.centered = false
	# 贴图按「动画节点 offset 减锚点」挪一次 offset，配合下面把原点落在锚点上，
	# 画出来的白影与角色逐像素重合，而缩放的支点是锚点（脚附近）而不是贴图中心。
	# 贴图中心不在锚点上，缩放绕它发生就会往头那边跑。
	sprite.offset = base_offset - anchor_offset
	# shader 变白，保留原 alpha
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://assets/entities/base/effects/cancel_white/white.gdshader")
	sprite.material = mat

	add_child(sprite)

	# 先继承来源节点的缩放与旋转：锚点补偿、Visuals 的补间缩放、实体层的缩放、朝向镜像、
	# 以及动画节点自身的位移都一并带过来。手抄 visuals_node.position 只在特效层与实体层
	# 的父级变换完全一致、且动画节点自身没有位移时才落得准，任一条不成立白影就会偏。
	var source: Node2D = anim_sprite
	if not source:
		source = _target.get("visuals_node") as Node2D
	if source and is_instance_valid(source):
		sprite.global_transform = source.global_transform
		# 再把原点搬到锚点上。当前帧的锚点正好落在实体原点上，所以取实体原点即可。
		sprite.global_position = _target.global_position

	# 起手整体放大 1.1 倍（xy 同倍），全程收到角色本身的大小；缩放与淡出同时起跑，
	# 淡出 0.18 秒完，缩放 0.3 秒完。缩放绕锚点发生，所以白影是往脚那头缩进去的。
	var base_scale: Vector2 = sprite.scale
	sprite.scale = base_scale * 1.2
	var tw = create_tween().set_ignore_time_scale(true)
	tw.tween_property(sprite, "scale", base_scale*Vector2(1.25, 1.0), 0.3)
	tw.set_parallel(true)
	sprite.modulate.a = 1.0
	tw.tween_property(sprite, "modulate:a", 0.0, 0.21)
	tw.set_parallel(false)
	tw.tween_callback(queue_free)
