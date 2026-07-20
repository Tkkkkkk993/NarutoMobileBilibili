extends EffectBase

@onready var anim_sprite = $AnimatedSprite2D

func _ready():
	visible = true
	set_meta("sort_by_depth", true)
	
	# 将此特效置于顶层显示
	DepthManager.bring_to_top(self)
	
	play()

func play():
	anim_sprite.play()
	# 动画结束后自动销毁
	anim_sprite.animation_finished.connect(_on_animation_finished)
