# ufe_data_cache.gd
# UFE (Unity Fighter Exporter) 数据缓存全局单例
# 管理 sprites.json / animations.json 的加载和纹理缓存
extends Node

var sprites: Dictionary = {}     # {sprite_id: {w, h, cx, cy, px, py, file}}
var animations: Dictionary = {}  # {anim_name: {fps, frame_overrides, frames}}
var textures: Dictionary = {}    # {sprite_id: Texture2D}

var _loaded: bool = false
var _char_id: String = ""

func is_loaded() -> bool:
	return _loaded

func get_char_id() -> String:
	return _char_id

func get_texture(id: String) -> Texture2D:
	return textures.get(id, null)

# 加载角色 UFE 数据（sprites.json + animations.json + 纹理）
# data_dir: 角色数据目录路径，如 "res://assets/entities/<char_id>/ufe/"
func load_character_data(data_dir: String, char_id: String = "") -> bool:
	_char_id = char_id
	_loaded = false
	sprites.clear()
	animations.clear()
	textures.clear()

	var sprites_path = data_dir + "sprites.json"
	var anims_path = data_dir + "animations.json"

	if not FileAccess.file_exists(sprites_path):
		push_warning("UFEDataCache: sprites.json 不存在: " + sprites_path)
		return false
	if not FileAccess.file_exists(anims_path):
		push_warning("UFEDataCache: animations.json 不存在: " + anims_path)
		return false

	# 加载 sprites.json
	var spr_file = FileAccess.open(sprites_path, FileAccess.READ)
	var spr_json = JSON.new()
	spr_json.parse(spr_file.get_as_text())
	spr_file.close()
	var spr_data = spr_json.data
	if spr_data and spr_data.has("sprites"):
		sprites = spr_data["sprites"]

	# 加载 animations.json
	var anim_file = FileAccess.open(anims_path, FileAccess.READ)
	var anim_json = JSON.new()
	anim_json.parse(anim_file.get_as_text())
	anim_file.close()
	var anim_data = anim_json.data
	if anim_data and anim_data.has("animations"):
		animations = anim_data["animations"]

	# 加载纹理
	var tex_dir = data_dir + "sprites/"
	for spr_id in sprites:
		var spr_info: Dictionary = sprites[spr_id]
		var file_name: String = spr_info.get("file", spr_id + ".png")
		var tex_path = tex_dir + file_name
		if ResourceLoader.exists(tex_path):
			textures[spr_id] = load(tex_path)
		else:
			push_warning("UFEDataCache: 纹理缺失 [%s] -> %s" % [spr_id, tex_path])

	_loaded = true
	return true

# 清空缓存（切换角色时调用）
func clear_cache():
	sprites.clear()
	animations.clear()
	textures.clear()
	_loaded = false
	_char_id = ""
