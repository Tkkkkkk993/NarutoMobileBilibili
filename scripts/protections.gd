extends Control

# 定义保护状态的枚举
enum ProtectionState {
	NONE,    # 无保护
	YELLOW,  # 黄保护
	RED      # 红保护
}

@onready var texture_rect = $TextureRect

@export var yellow_protection_img: Texture2D = preload("res://assets/UI/protection_yellow.png")
@export var red_protection_img: Texture2D = preload("res://assets/UI/protection_red.png")

# 保护值变量 (由外部修改)
var protection_value: float = 0.0

# 使用枚举类型来记录状态
var current_state: ProtectionState = ProtectionState.NONE
var prev_state: ProtectionState = ProtectionState.NONE

var fade_tween: Tween

# 渐显时间（秒）
const FADE_DURATION: float = 0.6

func _ready():
	# 初始时隐藏并确保透明度为0
	texture_rect.modulate.a = 0.0
	texture_rect.visible = false

func update_protection(value: float):
	protection_value = clampf(value, 0.0, 1.0)
	
	# 判断当前应该处于什么枚举状态
	if protection_value > 0.6:
		current_state = ProtectionState.RED
	elif protection_value > 0.15:
		current_state = ProtectionState.YELLOW
	else:
		current_state = ProtectionState.NONE
		
	# 只有在状态发生改变时，才触发动画
	if current_state != prev_state:
		_handle_state_change(current_state)
		prev_state = current_state

# 处理状态改变
func _handle_state_change(new_state: ProtectionState):
	# 如果上一次的渐变动画还没播完，强制终止它，防止动画冲突
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()
		
	# 使用 match 匹配枚举，比 if 更清晰
	match new_state:
		ProtectionState.NONE:
			texture_rect.visible = false
			texture_rect.modulate.a = 0.0
			
		ProtectionState.YELLOW:
			_start_fade_effect(yellow_protection_img)
			
		ProtectionState.RED:
			_start_fade_effect(red_protection_img)

# 核心动画逻辑：换图 -> 归零 -> 持续闪烁循环
func _start_fade_effect(target_texture: Texture2D):
	# 容错：如果图片没拖进去就跳过
	if not target_texture:
		return
		
	# 1. 替换为对应的黄/红图片
	texture_rect.texture = target_texture
	
	# 2. 显示节点
	texture_rect.visible = true
	
	# 3. 瞬间将透明度强制设为 0
	texture_rect.modulate.a = 0.0
	
	# 4. 创建循环闪烁的 Tween 动画
	fade_tween = create_tween().set_loops() # .set_loops() 不传参数默认无限循环
	
	# 第一段：从 0 渐显到 1
	fade_tween.tween_property(texture_rect, "modulate:a", 1.0, FADE_DURATION)
	
	# 第二段：从 1 渐隐到 0
	# Tween 会自动把这两段连起来，形成 0->1->0 的完美循环
	fade_tween.tween_property(texture_rect, "modulate:a", 0.0, FADE_DURATION)
