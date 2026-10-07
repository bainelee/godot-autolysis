extends "res://main-autolysis/player/tests/blend_handle_drag_test.gd"
## 正式输入链与本机图形后端的程序原生移动验收。
## 按钮经输入解析；移动由测试驱动定位系统指针，实际相对事件由视窗系统后端产生。
## 测试驱动的位移属于刻意输入，生产控制器自身的循环位移必须补偿为零。
## 此脚本不声称真人操作体验验收通过。

const NATIVE_RATIO: float = 0.00001
const NATIVE_EPSILON: float = 0.00002

class NativeObserver extends Node:
	var runner: Object

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_physics_priority = 1100

	func _input(event: InputEvent) -> void:
		runner._record_native_event(event)

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			runner._release_after_native_echo()

	func _physics_process(_delta: float) -> void:
		runner._record_native_sample()

var native_events: Array[Dictionary] = []
var native_commands: Array[Dictionary] = []
var native_samples: Array[Dictionary] = []
var native_observer: NativeObserver
var driving_native: bool = false
var native_phase: String = "初始化"
var native_expected_y: float = TOP
var native_down_loops: int = 0
var native_up_loops: int = 0
var native_driver_motions: int = 0
var native_loop_frame: int = -1
var native_tracking: bool = false
var native_initial_camera: Transform3D
var release_on_next_echo: bool = false
var echo_release_queued: bool = false
var echo_release_frame: int = -1
var echo_release_y: float = TOP


func _run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	original_physics_ticks = Engine.physics_ticks_per_second
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	_check(graphical and DisplayServer.get_name() == "Windows", "原生循环检查使用指定视窗系统图形后端")
	if not graphical:
		_save_native_report()
		quit(1)
		return
	root.title = "原药混合器拉杆程序原生循环验收"
	root.size = Vector2i(1280, 720)
	probe = TickProbe.new()
	root.add_child(probe)
	await _test_native_layout(false)
	await _test_native_layout(true)
	if is_instance_valid(player):
		_native_button(false, root.get_mouse_position())
		player.interaction_controller.cancel_focus_drag()
	if is_instance_valid(world):
		world.queue_free()
	await _frames(2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	Engine.physics_ticks_per_second = original_physics_ticks
	_save_native_report()
	print("原生循环验收断言数：", assertion_count, "；失败总数：", failures, "；实际鼠标移动事件数：", native_driver_motions)
	quit(1 if failures > 0 else 0)


func _test_native_layout(scaled: bool) -> void:
	native_tracking = false
	if is_instance_valid(native_observer):
		native_observer.queue_free()
		await _frames(1)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080) if scaled else Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if scaled else Window.CONTENT_SCALE_MODE_DISABLED
	await _frames(2)
	await _new_scene("原生循环内容缩放" if scaled else "原生循环窗口坐标")
	handle.mouse_to_handle_ratio = NATIVE_RATIO
	_check(root.has_focus(), "可见图形窗口实际取得焦点")
	_check(root.size == Vector2i(1280, 720), "原生检查记录规定窗口尺寸一千二百八十乘七百二十")
	native_phase = "建立系统指针基准"
	native_observer = NativeObserver.new()
	native_observer.runner = self
	root.add_child(native_observer)
	var pixel: Vector2 = _native_handle_pixel()
	await _drive_native_to(pixel, false)
	_native_button(true, pixel)
	await _frames(1)
	_check(handle.is_dragging_for(player) and player.interaction_controller.is_drag_active(), "真实碰撞像素的解析左键经正式链路建立拖动")
	_check(not Input.use_accumulated_input, "开始前及绑定阶段关闭引擎输入累积")
	native_expected_y = handle.position.y
	native_initial_camera = player.camera.global_transform
	native_down_loops = 0
	native_up_loops = 0
	echo_release_frame = -1
	native_tracking = true
	await _capture("native-scaled-start.png" if scaled else "native-window-start.png")
	await _downward_round("第一轮下边缘循环")
	await _downward_round("第二轮下边缘循环")
	_check(native_down_loops >= 2, "连续两轮下边缘实际回声已进入正式控制器并被补偿")
	await _capture("native-scaled-two-loops.png" if scaled else "native-window-two-loops.png")

	# 以下三个实际原生事件在同一物理帧之前发送，保留快速反向顺序。
	native_phase = "定位后快速反向"
	var current: Vector2 = root.get_mouse_position()
	var frame_before: int = Engine.get_physics_frames()
	var horizontal: float = current.x
	await _drive_native_to(Vector2(horizontal, current.y + 24.0), false)
	await _drive_native_to(Vector2(horizontal, current.y + 8.0), false)
	await _drive_native_to(Vector2(horizontal, current.y + 16.0), false)
	_check(Engine.get_physics_frames() == frame_before, "快速下推上推下推的三个原生事件保持同一物理帧前的顺序")
	await _frames(1)
	_assert_native_position("快速反向真实位移按事件保留")
	var transform: Transform2D = root.get_screen_transform()
	var view: Rect2 = root.get_visible_rect()
	var physical_scale: float = transform.y.length()
	native_phase = "上边缘循环"
	await _drive_native_to(Vector2(horizontal, view.position.y + 1.0 / physical_scale), true)
	_check(native_up_loops >= 1, "上边缘实际原生定位回声已补偿且拉杆无整屏跳变")
	_assert_native_position("上边缘循环后位置正确")

	native_phase = "定位后同帧松开"
	release_on_next_echo = true
	await _drive_native_to(Vector2(horizontal, view.end.y - 1.0 / physical_scale), true)
	_check(echo_release_frame >= 0 and native_loop_frame == echo_release_frame, "生产定位回声与随后左键松开记录在同一物理帧编号")
	var released_y: float = echo_release_y
	if echo_release_frame < 0:
		_native_button(false, root.get_mouse_position())
	await _frames(1)
	_check(not player.interaction_controller.is_drag_active() and not player.interaction_controller.get("_warp_pending"), "定位后松开结束唯一绑定及定位标记")
	_check(completion_count == 0, "多轮定位及快速反向均不误发完成信号")
	await _await_top("原生循环提前松开", released_y)
	_check(player.camera.global_transform.is_equal_approx(native_initial_camera), "原生循环全程固定聚焦镜头")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "原生循环及回弹全程保持可见指针")
	native_tracking = false
	await _capture("native-scaled-release.png" if scaled else "native-window-release.png")
	if scaled:
		await _drive_native_to(_native_handle_pixel(), false)
		_native_button(true, root.get_mouse_position())
		await _frames(1)
		_check(player.interaction_controller.is_drag_active(), "内容缩放场景新的左键能够重新开始")
		root.size = Vector2i(960, 540)
		await _frames(2)
		_check(not player.interaction_controller.is_drag_active() and not player.interaction_controller.get("_warp_pending"), "主动拖动中改变窗口尺寸取消旧边界及定位绑定")
		_check(completion_count == 0, "窗口变更取消不会发出完成信号")
		_native_button(false, root.get_mouse_position())
		root.size = Vector2i(1280, 720)
		await _frames(2)


func _native_handle_pixel() -> Vector2:
	var shape: CollisionShape3D = handle.get_node("collision_handle_interaction") as CollisionShape3D
	var box_shape: BoxShape3D = shape.shape as BoxShape3D
	for vertical: float in [0.0, -0.4, 0.4]:
		for horizontal: float in [0.0, -0.4, 0.4]:
			for depth: float in [0.0, 0.4, -0.4]:
				var point: Vector2 = player.camera.unproject_position(shape.to_global(box_shape.size * Vector3(horizontal, vertical, depth)))
				if root.get_visible_rect().has_point(point) and _query(point) == handle:
					return point
	_check(false, "正式聚焦射线存在可命中的拉杆像素")
	return INVALID_PIXEL


func _downward_round(label: String) -> void:
	native_phase = label
	var prior_loops: int = native_down_loops
	var view: Rect2 = root.get_visible_rect()
	var scale_y: float = root.get_screen_transform().y.length()
	var bottom: float = view.end.y - 1.0 / scale_y
	for _index: int in range(30):
		if native_down_loops > prior_loops:
			break
		var current: Vector2 = root.get_mouse_position()
		await _drive_native_to(Vector2(current.x, minf(current.y + 96.0 / scale_y, bottom)), true)
	_check(native_down_loops == prior_loops + 1, label + "触发恰好一次生产指针定位")
	_assert_native_position(label + "定位自身不改变拉杆进度")
	_check(completion_count == 0, label + "无定位触发完成")
	_check(root.get_mouse_position().y < view.position.y + 8.0 / scale_y, label + "指针已从底边到顶边内侧")


func _drive_native_to(point: Vector2, advance_frame: bool) -> void:
	DisplayServer.process_events()
	_wait_for_production_echo()
	var before: Vector2 = root.get_mouse_position()
	var raw_count: int = native_events.size()
	var driver_count: int = native_driver_motions
	var previous_y: float = handle.position.y
	driving_native = true
	Input.warp_mouse((root.get_screen_transform() * point).round())
	var after: Vector2 = root.get_mouse_position()
	var actual_motion: Vector2 = after - before
	DisplayServer.process_events()
	# 系统定位后消息可稍后才可读取；等待实际消息，不能把下一主循环当同步保证。
	var wait_started: int = Time.get_ticks_msec()
	while not actual_motion.is_zero_approx() and native_driver_motions == driver_count and Time.get_ticks_msec() - wait_started < 1000:
		OS.delay_msec(1)
		DisplayServer.process_events()
	driving_native = false
	if native_tracking:
		native_expected_y = clampf(native_expected_y - actual_motion.y * NATIVE_RATIO, BOTTOM, TOP)
	native_commands.append({
		"分段": sequence, "阶段": native_phase,
		"来源": "测试驱动程序定位产生的视窗系统实际输入",
		"物理帧": Engine.get_physics_frames(), "微秒": Time.get_ticks_usec(),
		"定位前": str(before), "视口目标": str(point), "定位后": str(after),
		"刻意真实位移": str(actual_motion), "之前杆位置": previous_y,
		"预期杆位置": native_expected_y, "实际事件新增数": native_events.size() - raw_count,
		"视口变换": str(root.get_screen_transform()), "窗口尺寸": str(root.size),
	})
	if native_tracking and not actual_motion.is_zero_approx():
		_check(native_driver_motions > driver_count, native_phase + "测试定位产生可观察的实际原生事件")
	if advance_frame:
		await _frames(1)
		_wait_for_production_echo()
		if native_tracking and echo_release_frame < 0:
			_assert_native_position(native_phase + "逐步位移及补偿正确")


func _native_button(pressed: bool, point: Vector2) -> void:
	# 输入解析入口接收窗口客户区像素；进入视口时引擎再反算内容缩放。
	_button(MOUSE_BUTTON_LEFT, pressed, root.get_screen_transform() * point)


func _release_after_native_echo() -> void:
	if not echo_release_queued:
		return
	echo_release_queued = false
	release_on_next_echo = false
	echo_release_frame = Engine.get_physics_frames()
	echo_release_y = handle.position.y
	_check(absf(echo_release_y - native_expected_y) <= NATIVE_EPSILON, "同帧松开前原生循环定位不改变真实累计进度")
	_native_button(false, root.get_mouse_position())


func _wait_for_production_echo() -> void:
	if not is_instance_valid(player):
		return
	var wait_started: int = Time.get_ticks_msec()
	while player.interaction_controller.get("_warp_pending") and Time.get_ticks_msec() - wait_started < 1000:
		OS.delay_msec(1)
		DisplayServer.process_events()


func _assert_native_position(label: String) -> void:
	_check(absf(handle.position.y - native_expected_y) <= NATIVE_EPSILON, label)
	_check(handle.position.x == 0.0 and handle.position.z == 0.0, label + "保持横向及深度零坐标")


func _record_native_event(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	var controller: AutolysisInteractionController = player.interaction_controller
	var entry: Dictionary = {
		"分段": sequence, "阶段": native_phase,
		"物理帧": Engine.get_physics_frames(), "微秒": Time.get_ticks_usec(),
		"位置": str(event.position), "系统实际位置": str(root.get_mouse_position()),
		"杆位置": handle.position.y, "状态": handle.state,
		"控制器绑定": controller.is_drag_active(),
		"控制器待补偿": controller.get("_warp_pending"),
		"控制器定位量": str(controller.get("_warp_delta")),
		"控制器旧基准": str(controller.get("_warp_origin")),
		"控制器定位目标": str(controller.get("_warp_destination")),
	}
	if event is InputEventMouseMotion:
		entry["种类"] = "实际原生移动"
		entry["相对位移"] = str(event.relative)
		entry["屏幕相对位移"] = str(event.screen_relative)
		entry["推导旧基准"] = str(event.position - event.relative)
		entry["按钮掩码"] = event.button_mask
		if controller.get("_warp_pending"):
			entry["来源"] = "生产控制器循环定位回声"
			var delta: Vector2 = controller.get("_warp_delta")
			if delta.y < 0.0:
				native_down_loops += 1
			elif delta.y > 0.0:
				native_up_loops += 1
			native_loop_frame = Engine.get_physics_frames()
			if release_on_next_echo:
				echo_release_queued = true
		else:
			entry["来源"] = "测试驱动程序原生输入" if driving_native else "其他实际原生移动"
			if driving_native:
				native_driver_motions += 1
	else:
		entry["种类"] = "解析按钮"
		entry["来源"] = "输入解析按钮进入正式玩家链路"
		entry["按钮"] = event.button_index
		entry["按下"] = event.pressed
	native_events.append(entry)


func _record_native_sample() -> void:
	if not is_instance_valid(handle) or not is_instance_valid(player):
		return
	native_samples.append({
		"分段": sequence, "阶段": native_phase, "物理帧": Engine.get_physics_frames(),
		"微秒": Time.get_ticks_usec(), "指针实际位置": str(root.get_mouse_position()),
		"拉杆位置": str(handle.position), "预期纵向位置": native_expected_y,
		"状态": handle.state, "完成次数": completion_count,
		"控制器绑定": player.interaction_controller.is_drag_active(),
		"控制器待补偿": player.interaction_controller.get("_warp_pending"),
		"指针可见": Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"引擎累积输入": Input.use_accumulated_input,
	})


func _save_native_report() -> void:
	var report: Dictionary = {
		"证据范围": "程序原生鼠标移动验收；移动事件由本机视窗系统图形后端产生，按钮由输入解析建立正式玩家链路；不含真人体验调校",
		"引擎版本": Engine.get_version_info(), "后端": DisplayServer.get_name(),
		"物理迭代数": Engine.physics_ticks_per_second,
		"测试比例": NATIVE_RATIO, "断言数": assertion_count, "失败数": failures,
		"断言": records, "原生事件完整序列": native_events,
		"测试驱动定位调用": native_commands, "物理帧采样": native_samples,
		"截图": screenshots, "未覆盖": ["真人操作比例体验验收", "编辑器嵌入运行", "物理输入硬件未发送到系统的采样路径"],
	}
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("native-loop-report.json"), FileAccess.WRITE)
	if file == null:
		push_error("原生循环验收报告无法写入证据目录。")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
