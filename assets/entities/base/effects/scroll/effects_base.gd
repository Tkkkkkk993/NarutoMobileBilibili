extends EffectBase

@onready var anim_sprite = $AnimatedSprite2D

func _ready():
	visible = true
	set_meta("sort_by_depth", true)
	
	play()

func play():
	anim_sprite.play()
	
	# 动画结束后自动销毁
	anim_sprite.animation_finished.connect(_on_animation_finished)
