extends TextureProgressBar

@onready var HpRed: TextureProgressBar = $"../HpRed"

# 记录红条上一次的值，用于判断变化方向
var _last_red_value: float = 0.0

# ---------- 延迟减少模式相关 ----------
var _last_damage_time: float = 0.0
@export var damage_delay: float = 0.2

# ---------- 渐隐同步模式相关 ----------
enum DisplayMode { DELAY_REDUCE, FADE_SYNC }
@export var display_mode: DisplayMode = DisplayMode.FADE_SYNC :
	set(value):
		display_mode = value
		_reset_to_red()
		modulate.a = 1.0
		if _tween:
			_tween.kill()
		set_process(display_mode == DisplayMode.DELAY_REDUCE && value > HpRed.value)

@export var fade_duration: float = 0.23
@export var fade_target_alpha: float = 0.5
@export var fade_restore_duration: float = 0.23

var _tween: Tween

func _ready() -> void:
	HpRed.value_changed.connect(_on_hp_red_value_changed)
	_reset_to_red()
	_last_red_value = HpRed.value
	set_process(display_mode == DisplayMode.DELAY_REDUCE && value > HpRed.value)

func _reset_to_red() -> void:
	value = HpRed.value
	max_value = HpRed.max_value
	modulate.a = 1.0
	if _tween:
		_tween.kill()

func _on_hp_red_changed() -> void:
	max_value = HpRed.max_value

func _process(delta: float) -> void:
	if display_mode == DisplayMode.DELAY_REDUCE:
		if value > HpRed.value:
			var now = Time.get_ticks_msec() / 1000.0
			if now - _last_damage_time >= damage_delay:
				value -= max_value * 0.5 * delta
		else:
			value = HpRed.value
			set_process(false)
	else:
		set_process(false)

func _on_hp_red_value_changed(new_value: float) -> void:
	if new_value > _last_red_value:
		# 治疗：立即同步，恢复透明度，停止动画
		_reset_to_red()
		set_process(false)
	else:
		# 伤害
		if display_mode == DisplayMode.DELAY_REDUCE:
			if self.value > new_value:
				_last_damage_time = Time.get_ticks_msec() / 1000.0
				set_process(true)
		else: # FADE_SYNC 模式
			# 停止之前的渐变动画
			if _tween:
				_tween.kill()
			# 如果白条已经完全和红条对齐（空闲状态），从红条当前位置开始
			# 否则白条还在前方，保持原位不动
			if value <= HpRed.value:
				value = HpRed.value
			# 每次伤害重置透明度为1.0，确保视觉反馈从清晰开始
			modulate.a = 1.0
			# 开始渐隐到目标阈值，到达后执行同步并渐显
			_tween = create_tween()
			_tween.tween_property(self, "modulate:a", fade_target_alpha, fade_duration)
			_tween.tween_callback(_sync_and_fade_in)
	
	_last_red_value = new_value

func _sync_and_fade_in() -> void:
	value = HpRed.value
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, fade_restore_duration)
