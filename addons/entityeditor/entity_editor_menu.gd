@tool
extends Control

const API_BASE = "http://api.udbbs.top/api/project/"

const MANIFEST_PATH = "res://addons/entityeditor/manifest.json"

var manifest: Dictionary
var http_requests: Array = []
var updates_available: Dictionary = {}  # { project_key: { latest_version, download_url } }
var check_results: Dictionary = {}      # { project_key: "updatable" | "uptodate" | "failed" }
var error_messages: Dictionary = {}     # 错误信息，用于展示

# 下载相关（简化）
var download_queue: Array = []          # 待下载的项目键列表
var download_index: int = 0             # 当前下载索引
var progress_dialog: Window = null      # 进度提示窗口

var window_scene = preload("res://addons/entityeditor/entity_editor.tscn")
var current_window = null

# 自动检查模式标志
var auto_check_mode: bool = false


func _ready() -> void:
	print("实体编辑器菜单加载成功！")
	load_manifest()
	# 延迟一帧执行自动检查，避免阻塞 UI
	call_deferred("_auto_check_updates")


# ---------- 加载 Manifest ----------
func load_manifest() -> void:
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		manifest = JSON.parse_string(content)
		file.close()
		if manifest == null or not manifest.has("projects"):
			push_error("manifest.json 格式错误或缺少 'projects' 字段")
	else:
		push_error("无法加载 manifest.json，请确保文件存在")


# ---------- 打开实体编辑器 ----------
func _on_open_editor_button_pressed() -> void:
	if current_window != null and is_instance_valid(current_window) and current_window.get_parent() != null:
		current_window.show()
		current_window.grab_focus()
		return
	
	var window_instance = window_scene.instantiate()
	window_instance.title = "实体编辑器"
	window_instance.size = Vector2i(400, 300)
	window_instance.min_size = Vector2i(300, 200)
	window_instance.close_requested.connect(_on_window_closed.bind(window_instance))
	add_child(window_instance)
	window_instance.popup_centered()
	current_window = window_instance


func _on_window_closed(window_instance) -> void:
	if window_instance:
		window_instance.queue_free()
		current_window = null


# ---------- 自动检查更新 ----------
func _auto_check_updates() -> void:
	auto_check_mode = true
	_on_check_update_button_pressed()


# ---------- 检查更新 ----------
func _on_check_update_button_pressed() -> void:
	if manifest == null or not manifest.has("projects"):
		push_error("manifest 未加载或缺少 projects 字段")
		return
	
	updates_available.clear()
	check_results.clear()
	error_messages.clear()
	
	for project_key in manifest.projects.keys():
		var project = manifest.projects[project_key]
		var project_id = project.get("project_id", "")
		var current_version = project.get("version", "")
		
		print("项目 %s：project_id='%s', version='%s'" % [project_key, project_id, current_version])
		
		if project_id != "" and current_version != "":
			_check_project_update(project_key, project_id, current_version)
		else:
			push_warning("项目 %s 的 project_id 或 version 为空，跳过检查" % project_key)
			check_results[project_key] = "failed"
			error_messages[project_key] = "project_id 或 version 未配置"


func _check_project_update(project_key: String, project_id: String, current_version: String) -> void:
	var url = "%s?action=check_update&project_id=%s&version=%s" % [API_BASE, project_id, current_version]
	print("请求URL: ", url)
	
	var http = HTTPRequest.new()
	add_child(http)
	
	if API_BASE.begins_with("https://"):
		http.set_tls_options(TLSOptions.client_unsafe())
	
	http_requests.append(http)
	http.request_completed.connect(_on_check_completed.bind(http, project_key))
	var err = http.request(url)
	if err != OK:
		push_error("请求失败：", err)
		http.queue_free()
		http_requests.erase(http)
		check_results[project_key] = "failed"
		error_messages[project_key] = "网络请求失败"


func _on_check_completed(result, response_code, headers, body, http, project_key) -> void:
	http.queue_free()
	http_requests.erase(http)
	
	var status = "failed"
	
	if response_code == 200:
		var body_str = body.get_string_from_utf8()
		print("API 返回原始数据（%s）：%s" % [project_key, body_str])
		
		var json = JSON.parse_string(body_str)
		if json != null:
			if json.has("status") and json.status == "error":
				var err_msg = json.get("message", "未知错误")
				push_error("项目 %s API 返回错误：%s" % [project_key, err_msg])
				error_messages[project_key] = err_msg
				status = "failed"
			elif json.has("status") and json.status == "success":
				var data = json.get("data", {})
				var has_update = data.get("has_update", false)
				if has_update:
					status = "updatable"
					updates_available[project_key] = {
						"latest_version": data.get("latest_version", ""),
						"download_url": data.get("download_url", "")
					}
				else:
					status = "uptodate"
			else:
				var has_update = json.get("has_update", false)
				if has_update:
					status = "updatable"
					updates_available[project_key] = {
						"latest_version": json.get("latest_version", json.get("version", "")),
						"download_url": json.get("download_url", json.get("url", ""))
					}
				else:
					status = "uptodate"
				if status == "failed":
					push_warning("未知的 JSON 结构，无法解析：%s" % json)
					error_messages[project_key] = "未知的响应格式"
		else:
			push_error("JSON 解析失败，原始内容：%s" % body_str)
			error_messages[project_key] = "JSON 解析失败"
	else:
		push_warning("项目 %s 检查更新失败，HTTP状态码：%d" % [project_key, response_code])
		error_messages[project_key] = "HTTP 状态码 %d" % response_code
	
	check_results[project_key] = status
	
	if http_requests.is_empty():
		_on_all_checks_done()


func _on_all_checks_done() -> void:
	var total = check_results.size()
	var updatable = updates_available.size()
	var uptodate = 0
	var failed = 0
	var failed_list = []
	for key in check_results.keys():
		match check_results[key]:
			"uptodate":
				uptodate += 1
			"failed":
				failed += 1
				if error_messages.has(key):
					failed_list.append("%s（%s）" % [key, error_messages[key]])
				else:
					failed_list.append(key)
	
	# 自动检查模式
	if auto_check_mode:
		auto_check_mode = false  # 重置，避免影响后续手动检查
		if updatable > 0:
			# 显示一个轻量提示，不阻断用户操作
			_show_auto_update_notification()
		else:
			# 静默，无更新或失败不打扰
			print("自动检查完成：无更新")
		return
	
	# 手动模式
	var msg = "检查完成：共 %d 个项目" % total
	if total > 0:
		msg += "，%d 个需要更新，%d 个已是最新" % [updatable, uptodate]
		if failed > 0:
			msg += "，%d 个检查失败" % failed
	
	if updatable == 0 and failed == 0:
		_show_message(msg)
		return
	
	if failed > 0:
		msg += "\n\n检查失败的项目：\n"
		for item in failed_list:
			msg += "- %s\n" % item
	
	if updatable > 0:
		msg += "\n需要更新的项目：\n"
		for key in updates_available.keys():
			var project = manifest.projects[key]
			var info = updates_available[key]
			msg += "- %s：当前 %s → 最新 %s\n" % [key, project.version, info.latest_version]
		msg += "\n是否立即下载并更新？"
		
		var dialog = ConfirmationDialog.new()
		dialog.title = "发现更新"
		dialog.dialog_text = msg
		dialog.ok_button_text = "更新"
		dialog.cancel_button_text = "稍后"
		add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(_on_update_confirmed)
		dialog.close_requested.connect(dialog.queue_free)
	else:
		_show_message(msg)


# ---------- 自动更新通知 ----------
func _show_auto_update_notification() -> void:
	var msg = "检测到插件有可用更新，是否立即更新？\n\n"
	for key in updates_available.keys():
		var project = manifest.projects[key]
		var info = updates_available[key]
		msg += "- %s：当前 %s → 最新 %s\n" % [key, project.version, info.latest_version]
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "自动检查：发现更新"
	dialog.dialog_text = msg
	dialog.ok_button_text = "立即更新"
	dialog.cancel_button_text = "忽略"
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(_on_update_confirmed)
	dialog.close_requested.connect(dialog.queue_free)


# ---------- 下载流程 ----------
func _on_update_confirmed() -> void:
	# 构建下载队列（只包含有更新的项目）
	download_queue.clear()
	for key in updates_available.keys():
		download_queue.append(key)
	download_index = 0
	
	if download_queue.is_empty():
		return
	
	# 开始第一个下载
	_download_next()


func _download_next() -> void:
	if download_index >= download_queue.size():
		# 所有下载完成
		_save_manifest_and_ask_reload()
		return
	
	var project_key = download_queue[download_index]
	var info = updates_available[project_key]
	var total = download_queue.size()
	var current = download_index + 1
	
	# 显示进度提示
	_show_progress("正在下载 %.2f%% (%d/%d)：%s" % [current / total * 100, current, total, project_key])
	
	_download_project_update(project_key, info.download_url, info.latest_version)


func _show_progress(text: String) -> void:
	# 已有进度窗口则更新文本，否则创建
	if progress_dialog == null or not is_instance_valid(progress_dialog):
		progress_dialog = Window.new()
		progress_dialog.title = "下载进度"
		progress_dialog.size = Vector2i(400, 80)
		progress_dialog.exclusive = false
		progress_dialog.visible = true
		
		var label = Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.anchor_right = 1.0
		label.anchor_bottom = 1.0
		progress_dialog.add_child(label)
		progress_dialog.set_meta("label", label)
		
		add_child(progress_dialog)
	else:
		var label = progress_dialog.get_meta("label")
		if label:
			label.text = text
		progress_dialog.visible = true


func _close_progress() -> void:
	if progress_dialog != null and is_instance_valid(progress_dialog):
		progress_dialog.visible = false
		# 不立即释放，以免冲突，稍后会在最终清理时释放


# ---------- 下载并安装更新（单个文件） ----------
func _download_project_update(project_key: String, download_url: String, latest_version: String) -> void:
	var http = HTTPRequest.new()
	add_child(http)
	
	if download_url.begins_with("https://"):
		http.set_tls_options(TLSOptions.client_unsafe())
	
	# 存储上下文，用于回调
	http.set_meta("project_key", project_key)
	http.set_meta("latest_version", latest_version)
	
	http.request_completed.connect(_on_download_completed.bind(http))
	var err = http.request(download_url)
	if err != OK:
		push_error("下载项目 %s 失败：%d" % [project_key, err])
		http.queue_free()
		# 出错时，跳过该项目，继续下一个
		download_index += 1
		_close_progress()
		_download_next()


# ---------- 下载完成回调：增加对 manifest 的合并处理 ----------
func _on_download_completed(result, response_code, headers, body, http) -> void:
	http.queue_free()
	
	var project_key = http.get_meta("project_key", "")
	var latest_version = http.get_meta("latest_version", "")
	
	if response_code != 200:
		push_error("下载项目 %s 失败，HTTP状态码：%d" % [project_key, response_code])
		_close_progress()
		download_index += 1
		_download_next()
		return
	
	# 特殊处理：更新的是 manifest.json 本身
	if project_key == "更新清单":
		_merge_manifest_update(body, latest_version)
	else:
		# 普通项目：覆盖文件并更新 manifest 版本
		var target_file_path = manifest.projects[project_key].get("path")
		if not target_file_path or target_file_path.is_empty():
			push_error("项目 %s 未配置 path，无法保存" % project_key)
			_close_progress()
			download_index += 1
			_download_next()
			return
		
		var file = FileAccess.open(target_file_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			print("文件已更新：%s" % target_file_path)
			# 更新 manifest 中的版本号
			manifest.projects[project_key].version = latest_version
		else:
			push_error("无法写入文件：%s" % target_file_path)
	
	_close_progress()
	download_index += 1
	_download_next()


# ---------- 合并 manifest 更新 ----------
func _merge_manifest_update(new_manifest_body: PackedByteArray, new_version: String) -> void:
	var new_manifest_str = new_manifest_body.get_string_from_utf8()
	var new_manifest = JSON.parse_string(new_manifest_str)
	if new_manifest == null or not new_manifest.has("projects"):
		push_error("新 manifest 格式无效，跳过更新")
		return

	var remote_projects = new_manifest.projects
	var local_projects = manifest.projects

	var merged_projects = local_projects.duplicate(true)

	# 合并远程项目（保留本地 path）
	for key in remote_projects.keys():
		var remote_project = remote_projects[key].duplicate(true)
		if local_projects.has(key):
			var local_version = local_projects[key].get("version", "")
			var remote_version = remote_project.get("version", "")
			# 注意：如果该 key 是 “更新清单”，远程版本可能不可靠，我们后面单独处理
			if _is_version_greater(remote_version, local_version):
				var local_path = local_projects[key].get("path", "")
				merged_projects[key] = remote_project
				if local_path != "":
					merged_projects[key]["path"] = local_path
				print("项目 %s 已更新：%s → %s" % [key, local_version, remote_version])
		else:
			merged_projects[key] = remote_project
			print("新增项目 %s" % key)

	# 确定清单的新版本号：优先使用 API 传入的 new_version
	var new_manifest_version = new_version
	if new_manifest_version == "":
		# 若 API 未提供，则使用清单内的 version
		new_manifest_version = new_manifest.get("version", "")
		print("使用清单内部版本：%s" % new_manifest_version)
	else:
		print("使用 API 返回版本：%s" % new_manifest_version)

	# 更新顶层版本（如果存在）
	if new_manifest_version != "" and manifest.get("version", "") != new_manifest_version:
		var old_top = manifest.get("version", "")
		manifest["version"] = new_manifest_version
		print("manifest 顶层版本已更新：%s → %s" % [old_top, new_manifest_version])

	# 更新“更新清单”项目自身的版本（如果存在）
	if merged_projects.has("更新清单") and new_manifest_version != "":
		var self_project = merged_projects["更新清单"]
		var current_self_version = self_project.get("version", "")
		if _is_version_greater(new_manifest_version, current_self_version):
			self_project["version"] = new_manifest_version
			print("“更新清单”项目版本已更新：%s → %s" % [current_self_version, new_manifest_version])

	# 应用合并结果
	manifest.projects = merged_projects

	# 保存文件
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()
		print("manifest 合并并保存完成")
	else:
		push_error("无法保存 manifest.json")


# ---------- 简单语义化版本比较（支持数字分段，如 1.2.3） ----------
func _is_version_greater(v1: String, v2: String) -> bool:
	# 分割为数字数组，逐级比较
	var parts1 = v1.split(".")
	var parts2 = v2.split(".")
	var max_len = max(parts1.size(), parts2.size())
	for i in range(max_len):
		# 尝试转换为整数，失败则按字符串比较
		var n1 = int(parts1[i]) if i < parts1.size() and parts1[i].is_valid_int() else -1
		var n2 = int(parts2[i]) if i < parts2.size() and parts2[i].is_valid_int() else -1
		# 如果都是有效数字则比较数字，否则按字符串比较
		if n1 != -1 and n2 != -1:
			if n1 > n2: return true
			if n1 < n2: return false
		else:
			# 字符串比较（如 "alpha" > "beta" 可能不是语义，但作为回退）
			var s1 = parts1[i] if i < parts1.size() else ""
			var s2 = parts2[i] if i < parts2.size() else ""
			if s1 > s2: return true
			if s1 < s2: return false
	return false  # 相等


# ---------- 保存 manifest 并询问用户如何重新加载 ----------
func _save_manifest_and_ask_reload() -> void:
	# 先关闭可能残留的进度窗口
	if progress_dialog != null and is_instance_valid(progress_dialog):
		progress_dialog.queue_free()
		progress_dialog = null
	
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()
		print("manifest 已更新")
	else:
		push_error("无法保存 manifest.json")
	
	reset_plugin()
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "更新完成"
	dialog.dialog_text = "更新已安装。\n\n- 如果只更新了资源文件（如 JSON、图片），当前插件已刷新。\n- 如果更新了脚本（.gd）或场景（.tscn），必须重启编辑器才能生效（等同于在项目设置里禁用再启用插件）。\n\n是否立即重启编辑器？"
	dialog.ok_button_text = "重启编辑器"
	dialog.cancel_button_text = "确定"
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(_restart_editor)
	dialog.close_requested.connect(dialog.queue_free)


# ---------- 快速刷新（只重置 UI 和状态，不重启编辑器） ----------
func _on_restart_button_pressed() -> void:
	reset_plugin()


func reset_plugin() -> void:
	print("正在快速刷新插件配置...")
	
	if current_window != null and current_window.get_parent() != null:
		current_window.queue_free()
		current_window = null
	
	updates_available.clear()
	check_results.clear()
	error_messages.clear()
	for req in http_requests:
		if req and is_instance_valid(req):
			req.queue_free()
	http_requests.clear()
	
	# 清理进度窗口
	if progress_dialog != null and is_instance_valid(progress_dialog):
		progress_dialog.queue_free()
		progress_dialog = null
	
	download_queue.clear()
	download_index = 0
	
	load_manifest()
	
	_show_message("配置已重载")
	print("快速刷新完成")


# ---------- 重启编辑器（完全重载插件） ----------
func _on_restart_editor_button_pressed() -> void:
	_restart_editor()

func _restart_editor() -> void:
	print("正在重启编辑器...")
	EditorInterface.restart_editor()


# ---------- 辅助 UI ----------
func _show_message(text: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "提示"
	dialog.dialog_text = text
	add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(dialog.queue_free)


func _on_explanation_button_pressed() -> void:
	var content = """[b]操作说明[/b]
[url=https://v.udbbs.top/Docs/#/9]教程[/url]

[color=gray]————————————————[/color]
[b]制作名单[/b]
程序：-225-
美术：火影忍者手游、-225-
音乐：-225-、ZUN、网络

[b]特别感谢[/b]
佐助本助、哈基米大侠、蔡是徐我坤

[b]联系方式[/b]
[url=https://qm.qq.com/q/tr07SZu40g]QQ群[/url]

[color=gray]————————————————[/color]
[color=gray]实体编辑器 V3[/color]"""

	var dialog = AcceptDialog.new()
	dialog.title = "说明"
	dialog.min_size = Vector2i(520, 420)
	dialog.get_ok_button().text = "关闭"

	var rich_label = RichTextLabel.new()
	rich_label.bbcode_enabled = true
	rich_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rich_label.text = content
	rich_label.meta_clicked.connect(_on_rich_label_meta_clicked)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(rich_label)

	dialog.add_child(scroll)
	add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(dialog.queue_free)


func _on_rich_label_meta_clicked(meta: Variant) -> void:
	OS.shell_open(meta)
