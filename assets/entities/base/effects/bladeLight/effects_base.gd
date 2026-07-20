extends EffectBase

@onready var anim_sprite = $AnimatedSprite2D
@onready var anim_sprite2 = $AnimatedSprite2D2

func _ready():
	visible = true
	set_meta("sort_by_depth", true)
	
	# 将此特效置于顶层显示
	DepthManager.bring_to_top(self)
	
	play()

func play():
	anim_sprite.play()
	
	# 设置随机旋转角度（0° 到 360°）
	anim_sprite2.rotation = randf_range(0, TAU)  # TAU = 2 * PI
	anim_sprite2.play()
	
	# 动画结束后自动销毁
	anim_sprite.animation_finished.connect(_on_animation_finished)
