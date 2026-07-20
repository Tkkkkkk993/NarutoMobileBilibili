extends Control
class_name TabSlotManager

@onready var tabs: Array[TabSlot] = [
	$Tab1,
	$Tab2,
	$Tab3
]

var selected_tab_id = 0

func _ready() -> void:
	for i in tabs.size():
		tabs[i].vis_node.texture = load("res://assets/UI/charSelect/tab_0.png")
		tabs[i].z_index = 2 - i
	
	tabs[selected_tab_id].vis_node.texture = load("res://assets/UI/charSelect/tab_1.png")
	tabs[selected_tab_id].z_index = 3

func _process(_delta):
	_check_button_states()

func _check_button_states():
	# 遍历所有的子节点
	for i in tabs.size():
		if tabs[i].touch.consume_press():
			_handle_icon_clicked(i)

# 具体的处理逻辑
func _handle_icon_clicked(index: int):
	tabs[selected_tab_id].vis_node.texture = load("res://assets/UI/charSelect/tab_0.png")
	tabs[selected_tab_id].z_index = 2 - selected_tab_id
	selected_tab_id = index
	tabs[selected_tab_id].vis_node.texture = load("res://assets/UI/charSelect/tab_1.png")
	tabs[selected_tab_id].z_index = 3
