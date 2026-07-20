@tool
extends EditorPlugin

var control: Control

func _enter_tree() -> void:
	control = preload("res://addons/entityeditor/entity_editor_menu.tscn").instantiate()
	control.name = "实体编辑器菜单"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, control)


func _exit_tree() -> void:
	remove_control_from_docks(control)
	control.queue_free()
