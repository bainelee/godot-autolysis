extends SceneTree

# 记录指定引擎图形后端产生的实际定位事件；不把定位事件冒充人工鼠标操作。
class MotionRecorder extends Node:
	var owner_tree: SceneTree
	var records: Array[Dictionary] = []
	var phase: String = "启动"
	var serial: int = 0

	func _ready() -> void:
		set_process_input(true)
		print("探针记录节点已进入场景树，输入监听启用=", is_processing_input())

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
			print("探针收到实际空格按键。")
			owner_tree.call("_start_sequence")
		elif event is InputEventMouseButton:
			print("探针收到实际鼠标按钮：按钮=", event.button_index, "；按下=", event.pressed)
		if event is InputEventMouseMotion:
			serial += 1
			var row: Dictionary = {
				"序号": serial,
				"阶段": phase,
				"微秒": Time.get_ticks_usec(),
				"位置": [event.position.x, event.position.y],
				"相对位移": [event.relative.x, event.relative.y],
				"屏幕相对位移": [event.screen_relative.x, event.screen_relative.y],
				"窗口编号": event.window_id,
				"按钮掩码": event.button_mask,
			}
			records.append(row)
			print("鼠标事件：", JSON.stringify(row))

var _recorder: MotionRecorder
var _original_accumulation: bool
var _evidence_dir: String = "res://docs/project-autolysis/00-discuss/交互系统/原药混合器拉杆交互实施证据/鼠标定位探针"
var _manual: bool = false
var _pump_native: bool = false
var _wait_for_key: bool = false
var _setup_finished: bool = false
var _started_usec: int
var _next_phase: int = 0
var _commands: Array[Dictionary] = []
var _focus_started: bool = false
var _label: Label


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			_evidence_dir = argument.trim_prefix("--evidence-dir=")
		elif argument == "--manual":
			_manual = true
		elif argument == "--pump-native":
			_pump_native = true
		elif argument == "--wait-for-key":
			_wait_for_key = true
	_setup.call_deferred()


func _setup() -> void:
	_original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	root.title = "鼠标定位事件探针"
	root.size = Vector2i(800, 600)
	root.content_scale_size = Vector2i(1600, 1200)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.visible = true
	_recorder = MotionRecorder.new()
	_recorder.owner_tree = self
	root.add_child(_recorder)
	_label = Label.new()
	_label.text = "鼠标定位事件探针\n按空格开始程序定位序列" if _wait_for_key else "鼠标定位事件探针\n等待窗口获得焦点后启动"
	_label.text += "\n窗口：800×600；内容：1600×1200\n程序会记录上下边缘循环产生的实际事件"
	_label.position = Vector2(60, 60)
	_label.add_theme_font_size_override("font_size", 38)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_label)
	_started_usec = Time.get_ticks_usec()
	print("探针设置：", JSON.stringify({
		"引擎版本": Engine.get_version_info(),
		"后端": DisplayServer.get_name(),
		"原累积设置": _original_accumulation,
		"累积设置": Input.use_accumulated_input,
		"敏捷刷新": ProjectSettings.get_setting("input_devices/buffering/agile_event_flushing"),
		"窗口尺寸": [root.size.x, root.size.y],
		"内容尺寸": [root.content_scale_size.x, root.content_scale_size.y],
		"模式": "人工观察" if _manual else "程序定位观察",
		"同步原生消息": _pump_native,
		"等待空格启动": _wait_for_key,
	}))
	_setup_finished = true
	print("探针延迟初始化完成：记录节点在树中=", _recorder.is_inside_tree(), "；窗口可见=", root.visible)


func _start_sequence() -> void:
	if not _setup_finished or _focus_started:
		return
	_focus_started = true
	_started_usec = Time.get_ticks_usec()
	print("窗口已获得焦点，启动程序定位序列。")
	_label.text = "鼠标定位事件探针\n程序定位序列运行中\n窗口：800×600；内容：1600×1200"


func _process(_delta: float) -> bool:
	if not _setup_finished:
		return false
	if not _focus_started:
		if _wait_for_key or not root.has_focus():
			return false
		_start_sequence()
	var elapsed: float = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	if _manual:
		if elapsed >= 60.0:
			_finish()
		return false
	var phase_times: Array[float] = [1.0, 1.7, 2.4, 3.1, 3.8, 4.5]
	if _next_phase < phase_times.size() and elapsed >= phase_times[_next_phase]:
		match _next_phase:
			0:
				_warp("建立中央基准", Vector2(800, 600))
			1:
				_warp("定位到底边内侧", Vector2(800, 1192))
			2:
				_warp("从底边循环到顶边", Vector2(800, 8))
			3:
				_warp("从顶边循环到底边", Vector2(800, 1192))
			4:
				_warp("同帧连续定位第一次", Vector2(800, 8))
				_warp("同帧连续定位第二次", Vector2(800, 100))
			5:
				_finish()
		_next_phase += 1
	return false


func _warp(label: String, target: Vector2) -> void:
	if _pump_native:
		DisplayServer.process_events()
	Input.flush_buffered_events()
	_recorder.phase = label
	var before: Vector2 = root.get_mouse_position()
	var transform: Transform2D = root.get_screen_transform()
	var window_target: Vector2 = (transform * target).round()
	Input.warp_mouse(window_target)
	var after: Vector2 = root.get_mouse_position()
	var command: Dictionary = {
		"阶段": label,
		"微秒": Time.get_ticks_usec(),
		"视口定位前": [before.x, before.y],
		"视口目标": [target.x, target.y],
		"窗口目标": [window_target.x, window_target.y],
		"视口定位后": [after.x, after.y],
		"真实定位分量": [after.x - before.x, after.y - before.y],
		"变换": str(transform),
	}
	_commands.append(command)
	print("定位调用：", JSON.stringify(command))
	if _pump_native:
		DisplayServer.process_events()
		print("定位同步消息完成：阶段=", label, "；当前实际事件数=", _recorder.records.size())


func _finish() -> void:
	Input.use_accumulated_input = _original_accumulation
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_evidence_dir))
	var output: FileAccess = FileAccess.open(_evidence_dir.path_join("实际事件.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({
			"定位调用": _commands,
			"鼠标事件": _recorder.records,
			"恢复累积设置": Input.use_accumulated_input,
			"证据范围": "指定图形后端实际程序定位事件，不含人工鼠标体验或真实按钮拖动验收",
		}, "\t"))
		output.close()
	print("探针完成：实际鼠标事件数=", _recorder.records.size())
	if _recorder.records.is_empty():
		push_error("探针没有收到实际鼠标移动事件，不能视为有效后端证据。")
		quit(1)
	else:
		quit(0)
