extends Node

signal progress_updated(value)
signal load_finished

var _load_queue: Array = []
var _current_load_index: int = 0
var _loaded_resources: Dictionary = {}
# 新增：记录失败的资源，便于调试
var _failed_resources: Array = []

func _ready():
	set_process(false)

func start_loading(resources_to_load: Array):
	_load_queue = resources_to_load
	_current_load_index = 0
	_loaded_resources.clear()
	_failed_resources.clear() # 重置失败列表
	
	if _load_queue.is_empty():
		return
		
	var err = ResourceLoader.load_threaded_request(_load_queue[0])
	if err == OK:
		set_process(true)
	else:
		push_error("加载请求失败: " + _load_queue[0])
		# 【改动】请求失败也尝试移动到下一个
		_move_to_next()

func _process(_delta):
	var path = _load_queue[_current_load_index]
	var status = ResourceLoader.load_threaded_get_status(path)
	
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# 加载中，等待
			pass
			
		ResourceLoader.THREAD_LOAD_LOADED:
			_loaded_resources[path] = ResourceLoader.load_threaded_get(path)
			_move_to_next()
				
		ResourceLoader.THREAD_LOAD_FAILED:
			# 【核心改动】记录失败，但继续加载下一个
			push_warning("资源加载失败，已跳过: " + path)
			_failed_resources.append(path)
			_move_to_next()
			
		_:
			# 【新增】处理未知状态，防止逻辑挂起
			push_warning("未知的加载状态: " + str(status) + " for " + path)
			# 可以稍等一帧再试，或者直接跳过防止卡死
			_move_to_next()

# 【新增】提取公共的“移动到下一项”逻辑
func _move_to_next():
	_current_load_index += 1
	
	# 计算进度（基于已处理的数量，包括失败的）
	var total_progress = float(_current_load_index) / float(_load_queue.size())
	progress_updated.emit(total_progress)
	
	if _current_load_index >= _load_queue.size():
		set_process(false)
		progress_updated.emit(1.0)
		# 如果有失败的，可以在这里发出一个额外信号或记录日志
		if not _failed_resources.is_empty():
			push_warning("加载完成，但有 %d 个资源加载失败" % _failed_resources.size())
		load_finished.emit()
	else:
		# 请求加载下一个
		var err = ResourceLoader.load_threaded_request(_load_queue[_current_load_index])
		if err != OK:
			push_error("请求下一个资源失败: " + _load_queue[_current_load_index])
			# 递归调用自己，跳过这个有问题的资源
			_move_to_next()

func get_resource(path: String) -> Resource:
	if _loaded_resources.has(path):
		return _loaded_resources[path]
	push_error("尝试获取未加载或不存在的资源: " + path)
	return null

func is_loaded(path: String) -> bool:
	return _loaded_resources.has(path)

func get_failed_resources() -> Array:
	return _failed_resources
