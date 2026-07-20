extends Control
class_name ScrollIconManager

# ========== 导出变量 ==========
@export_file("*.json") var json_data_path: String = ""
@export var icon_scene: PackedScene = null

@export_group("数据设置")
@export var char_ids: Array[int] = [1, 2, 3]

@export_group("路径约定")
@export var base_entities_path: String = "res://assets/entities/"
@export var icon_sub_path: String = "portraits/icon_idle.png"

@export_group("布局设置")
@export var start_pos: Vector2 = Vector2(124.5, -164.9) 
@export var gap_x: float = 81.0                   
@export var gap_y: float = 74.0                   
@export var columns: int = 4

# ========== 内部变量 ==========
var char_data_dict: Dictionary = {}
@onready var main: Control = $".."
@onready var tabs: TabSlotManager = $"../Tabs"

# ========== 生命周期 ==========
func _ready():
	_load_json_data()
	_generate_icons()

# ========== 核心逻辑 ==========
func _load_json_data():
	if json_data_path.is_empty(): return
	
	var file = FileAccess.open(json_data_path, FileAccess.READ)
	if not file: return
	
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK: return
	
	char_data_dict = json.data

func _generate_icons():
	# 清理旧节点
	for child in get_children():
		child.queue_free()
		
	var max_count = columns * 4 
	var count_to_generate = min(char_ids.size(), max_count)
	
	for i in range(count_to_generate):
		var num_id = char_ids[i]
		var str_id = str(num_id) # 转成字符串查 JSON
		
		if not char_data_dict.has(str_id):
			push_warning("CharIconManager: JSON 中找不到编号 ", num_id)
			continue
			
		var data = char_data_dict[str_id]
		var folder_id = data.get("id", "")
		
		if folder_id.is_empty():
			push_warning("CharIconManager: 编号 ", num_id, " 缺少 'id' 字段")
			continue
			
		# ========== 核心：自动拼接路径 ==========
		var full_icon_path = base_entities_path.path_join(folder_id).path_join(icon_sub_path)
		
		if not ResourceLoader.exists(full_icon_path):
			push_warning("CharIconManager: 自动拼接的路径不存在 -> ", full_icon_path)
			continue
			
		# 1. 实例化节点
		var icon_node
		if icon_scene:
			icon_node = icon_scene.instantiate()
		else:
			icon_node = TextureButton.new()
			
		# 2. 计算坐标
		var col = i % columns
		var row = i / columns 
		icon_node.position = Vector2(start_pos.x + col * gap_x, start_pos.y + row * gap_y)
		
		# 3. 设置贴图
		var texture = load(full_icon_path)
		if icon_node.has_method("set_texture"):
			icon_node.set_texture(texture)
		elif icon_node is TextureButton:
			icon_node.texture_normal = texture
			
		# 4. 将 JSON 数据挂在节点元数据上，方便以后点选时读取
		icon_node.set_meta("num_id", num_id)
		icon_node.set_meta("name", data.get("name", ""))
		icon_node.set_meta("folder_id", folder_id)
		
		icon_node.scale.x = 0.8
		icon_node.scale.y = 0.8
		
		add_child(icon_node)
		print("生成了节点：", icon_node.name, " 坐标：", icon_node.position, " 父节点：", self.name)

# ========== 公共接口 ==========
## 获取完整的显示名称
func get_full_display_name(num_id: int) -> String:
	var data = char_data_dict.get(str(num_id), {})
	if data.is_empty(): return ""
	return data.get("name", "")

## 获取该角色对应的战斗场景路径
func get_battle_scene_path(num_id: int) -> String:
	var data = char_data_dict.get(str(num_id), {})
	var folder_id = data.get("id", "")
	if folder_id.is_empty(): return ""
	return base_entities_path.path_join(folder_id).path_join("entity.tscn")

func _process(_delta):
	_check_button_states()

# ========== 基于 _pressed 变量的轮询检测 ==========
func _check_button_states():
	if tabs.selected_tab_id == 2:
		visible = true
		for item in get_children():
			if item is ScrollIconSlot:
				var child = item.touch
				if child.consume_press():
					_handle_icon_clicked(item)
	else:
		visible = false

# 具体的处理逻辑
func _handle_icon_clicked(clicked_slot: ScrollIconSlot):
	var num_id = clicked_slot.get_meta("num_id")
	
	if clicked_slot.num > 0:
		main.delete_scroll(clicked_slot.num - 1)
	else:
		var new_num = main.add_scroll(char_data_dict[str(num_id)])
		if new_num >= 0:
			clicked_slot.num = new_num + 1

func deselect(slot: ScrollIconSlot):
	slot.num = 0

func deselect_by_id(id: int):
	# 遍历所有的子节点
	for child in get_children():
		if child is ScrollIconSlot:
			if child.num == id:
				deselect(child)
