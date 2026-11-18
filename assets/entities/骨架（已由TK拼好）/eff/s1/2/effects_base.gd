extends EffectBase

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

func play():
	anim_sprite.animation_finished.connect(_on_animation_finished)
	anim_sprite.play("s1_attack_slash")
