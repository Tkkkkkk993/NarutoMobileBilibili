@tool
extends Control

signal button_pressed

@export var text: String = "默认文本":
	set(value):
		text = value
		# 在编辑器中实时更新按钮文字
		if is_node_ready() and $Button:
			$Button.text = value

func _ready() -> void:
	# 只在游戏运行时连接信号，避免编辑器内误触发
	if Engine.is_editor_hint():
		return
	$Button.text = text
	$Button.pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	button_pressed.emit()
