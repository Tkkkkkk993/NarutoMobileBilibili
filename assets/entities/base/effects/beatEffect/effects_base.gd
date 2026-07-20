extends EffectBase

@onready var player = $AnimationPlayer

func _ready():
	visible = true
	set_meta("sort_by_depth", true)
	
	# 将此特效置于底层显示
	DepthManager.send_to_bottom(self)
	
	play()

func play():
	player.play("B2")
	
	# 动画结束后自动销毁
	player.animation_finished.connect(_on_animation_finished, CONNECT_ONE_SHOT)
