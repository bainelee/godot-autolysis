extends SceneTree
## 正式玩家和正式混合器的输入链集成验收。
## 注入事件属于自动检查；真实指针循环和操作体验须另保留图形运行证据。

const DEMO: PackedScene = preload("res://main-autolysis/player/tests/focus_interaction_demo.tscn")
const RAY_SCRIPT: Script = preload("res://main-autolysis/player/components/autolysis_focus_ray_query.gd")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const TOP: float = 0.12
const BOTTOM: float = -0.12
const SPEED: float = 1.2
const HOLD_SECONDS: float = 0.1
const EPSILON: float = 0.00005
const INVALID_PIXEL: Vector2 = Vector2(-10000, -10000)

class TickProbe extends Node:
	var effective_seconds: float = 0.0
	var last_delta: float = 0.0

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_physics_priority = 1000

	func _physics_process(delta: float) -> void:
		last_delta = delta
		if not get_tree().paused:
			effective_seconds += delta

class EventConsumer extends Control:
	var consume_presses: bool = true
	var presses: int = 0
	var releases: int = 0
	var motions: int = 0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				presses += 1
				if not consume_presses:
					return
			else:
				releases += 1
			accept_event()
		elif event is InputEventMouseMotion:
			motions += 1
			accept_event()

class ManualObserver extends Node:
	var runner: Object
	var label: Label

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_physics_priority = 1100

	func _input(event: InputEvent) -> void:
		runner._record_manual_input(event)

	func _process(_delta: float) -> void:
		runner._update_manual_label(label)

	func _physics_process(_delta: float) -> void:
		runner._record_manual_physics()

var failures: int = 0
var assertion_count: int = 0
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/原药混合器拉杆交互实施证据/自动作业/拉杆60")
var world: Node3D
var player: AutolysisPlayer
var machine: AutolysisBlendMachine
var other_machine: AutolysisBlendMachine
var handle: Node3D
var focus: AutolysisFocusController
var probe: TickProbe
var ray_query: RefCounted = RAY_SCRIPT.new()
var cursor: Vector2 = Vector2.ZERO
var left_pressed: bool = false
var graphical: bool = false
var original_accumulation: bool = true
var original_physics_ticks: int = 60
var completion_count: int = 0
var completion_actors: Array[int] = []
var records: Array[Dictionary] = []
var inputs: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var collision_records: Array[Dictionary] = []
var screenshots: Array[String] = []
var sequence: String = ""
var completion_action: String = ""
var reentry_result: bool = true
var graphical_entry_count: int = 0
var configured_ratio: float = 0.0
var manual_started_ms: int = 0
var manual_duration: float = 150.0
var manual_done: bool = false
var manual_relative_y: float = 0.0
var manual_relative_x: float = 0.0
var manual_input_count: int = 0
var manual_capture_count: int = 0
var manual_prior_height: float = TOP
var manual_maximum_physics_error: float = 0.0
var manual_point_misses: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	assertion_count += 1
	print(("通过：" if condition else "失败：") + description)
	records.append({"分段": sequence, "说明": description, "通过": condition})
	if not condition:
		failures += 1


func _frames(count: int) -> void:
	for _index: int in range(count):
		await physics_frame
		await process_frame


func _run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	original_physics_ticks = Engine.physics_ticks_per_second
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var tick_index: int = arguments.find("--physics-ticks")
	if tick_index >= 0 and tick_index + 1 < arguments.size():
		Engine.physics_ticks_per_second = int(arguments[tick_index + 1])
	Input.use_accumulated_input = false
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	probe = TickProbe.new()
	root.add_child(probe)
	if arguments.has("--manual"):
		await _run_manual()
	elif arguments.has("--core-only"):
		await _test_motion_and_binding()
		await _test_ordered_inputs()
		await _test_release_and_repress()
		await _test_right_click_during_drag()
		await _test_return_times()
		await _test_completion()
		await _test_accumulation_restore()
	elif arguments.has("--cancel-only"):
		await _test_right_click_during_drag()
		await _test_interruptions()
		await _test_gui_consumption()
	elif arguments.has("--safety-only"):
		await _test_sessions_and_dependencies()
		await _test_completion_reentry()
	elif arguments.has("--collision-only"):
		await _test_collision_follow()
	else:
		await _test_motion_and_binding()
		await _test_ordered_inputs()
		await _test_release_and_repress()
		await _test_right_click_during_drag()
		await _test_return_times()
		await _test_completion()
		await _test_accumulation_restore()
		await _test_interruptions()
		await _test_gui_consumption()
		await _test_sessions_and_dependencies()
		await _test_completion_reentry()
		await _test_collision_follow()
	paused = false
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	_save_report()
	if is_instance_valid(world):
		world.queue_free()
	await _frames(2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	Engine.physics_ticks_per_second = original_physics_ticks
	print("拉杆输入验收断言数：", assertion_count, "；失败总数：", failures, "；图形运行：", graphical)
	quit(1 if failures > 0 else 0)


func _new_scene(label: String, initial_accumulation: bool = false) -> void:
	sequence = label
	paused = false
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	Input.action_release(&"menu")
	Input.action_release(&"focus_exit")
	if is_instance_valid(world):
		world.queue_free()
		await _frames(2)
	world = DEMO.instantiate()
	root.add_child(world)
	Input.use_accumulated_input = initial_accumulation
	player = world.get_node("Player") as AutolysisPlayer
	machine = world.get_node("MachineA") as AutolysisBlendMachine
	other_machine = world.get_node("MachineB") as AutolysisBlendMachine
	focus = player.focus_controller
	handle = machine.handle
	completion_count = 0
	completion_actors.clear()
	completion_action = ""
	reentry_result = true
	handle.interaction_completed.connect(_on_completed)
	configured_ratio = float(handle.mouse_to_handle_ratio)
	if not graphical:
		# 无图形后端仅替换捕获鼠标的入口许可，保留聚焦内部正式输入链。
		focus.configure(player, player.camera, player.held_item_presenter, _headless_entry_allowed)
	await _frames(25)
	player.body.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.eyes.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.head.look_at(machine.to_global(Vector3(0, 0.3, 0.075)), Vector3.UP)
	await _frames(3)
	_check(machine.focus_target.is_valid_target(), "正式设备含合法槽位及拉杆登记")
	_check(handle.position.is_equal_approx(Vector3(0, TOP, 0)), "拉杆精确初始化为规定顶部局部位置")
	_check(configured_ratio > 0.0, "正式场景提供正数鼠标换算比例")
	if graphical:
		_button(MOUSE_BUTTON_LEFT, true, Vector2(root.size) * 0.5)
		await _frames(1)
		_button(MOUSE_BUTTON_LEFT, false, Vector2(root.size) * 0.5)
		graphical_entry_count += 1
	else:
		_check(focus.try_enter(machine.focus_target), "无图形夹具经正式入口建立聚焦会话")
	await _frames(int(ceil(0.3 * Engine.physics_ticks_per_second)) + 2)
	_check(focus.is_focused_on(machine.focus_target), "正式玩家稳定聚焦当前正式混合器")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "聚焦拖动入口保持可见指针")
	_check(not Input.use_accumulated_input, "稳定聚焦在首次新按下来临前禁用输入累积")


func _headless_entry_allowed() -> bool:
	return player._base_input_allowed() and not focus.has_control()


func _on_completed(actor: Node3D) -> void:
	completion_count += 1
	completion_actors.append(actor.get_instance_id())
	samples.append({"分段": sequence, "事件": "完成信号", "物理帧": Engine.get_physics_frames(), "纵向位置": handle.position.y, "状态": handle.state, "角色编号": actor.get_instance_id()})
	if completion_action == "重新请求":
		reentry_result = handle.drag_interaction.try_interact(actor, AutolysisInteractionComponent.InteractionMode.DIRECT)
	elif completion_action == "删除设备":
		machine.queue_free()
	elif completion_action == "立即释放设备":
		machine.free()


func _button(button: MouseButton, pressed: bool, point: Vector2, canceled: bool = false) -> void:
	if button == MOUSE_BUTTON_LEFT:
		left_pressed = pressed and not canceled
	cursor = point
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.canceled = canceled
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if left_pressed else 0
	event.position = point
	event.global_position = point
	inputs.append({"分段": sequence, "物理帧": Engine.get_physics_frames(), "种类": "按钮", "按钮编号": button, "按下": pressed, "取消标记": canceled, "坐标": str(point)})
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _motion(vertical: float, horizontal: float = 0.0, point: Vector2 = INVALID_PIXEL) -> void:
	# 位移字段为注入的有序输入数据；测试坐标保持在画面内部，边缘循环另由图形取证覆盖。
	var target_point: Vector2 = point
	if target_point == INVALID_PIXEL:
		target_point = Vector2(clampf(cursor.x + horizontal, 16.0, float(root.size.x) - 16.0), clampf(cursor.y + vertical, 16.0, float(root.size.y) - 16.0))
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = target_point
	event.global_position = target_point
	event.relative = Vector2(horizontal, vertical)
	event.screen_relative = event.relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if left_pressed else 0
	inputs.append({"分段": sequence, "物理帧": Engine.get_physics_frames(), "种类": "移动", "坐标": str(target_point), "相对位移": str(event.relative), "左键按住": left_pressed})
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	cursor = target_point


func _action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _key(key: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.pressed = pressed
	inputs.append({"分段": sequence, "物理帧": Engine.get_physics_frames(), "种类": "键盘", "键码": key, "按下": pressed})
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _exclusions() -> Array[RID]:
	return [player.get_rid(), player._found_area.get_rid()]


func _query(point: Vector2, descriptor: AutolysisFocusTarget = null) -> Node3D:
	return ray_query.query_target(player.camera, point, machine.focus_target if descriptor == null else descriptor, _exclusions())


func _pixel() -> Vector2:
	var shape: CollisionShape3D = handle.get_node("collision_handle_interaction") as CollisionShape3D
	var box_shape: BoxShape3D = shape.shape as BoxShape3D
	for vertical: float in [0.0, -0.4, 0.4]:
		for horizontal: float in [0.0, -0.4, 0.4]:
			for depth: float in [0.0, 0.4, -0.4]:
				var point: Vector2 = player.camera.unproject_position(shape.to_global(box_shape.size * Vector3(horizontal, vertical, depth)))
				if Rect2(Vector2.ZERO, Vector2(root.size)).has_point(point) and _query(point) == handle:
					samples.append({"分段": sequence, "事件": "真实射线选择", "像素": str(point), "目标": str(handle.get_path()), "纵向位置": handle.position.y, "比例": handle.mouse_to_handle_ratio})
					return point
	_check(false, "正式聚焦射线能命中移动拉杆的实际碰撞")
	return INVALID_PIXEL


func _begin() -> void:
	var point: Vector2 = _pixel()
	_motion(0.0, 0.0, point)
	_button(MOUSE_BUTTON_LEFT, true, point)
	await _frames(1)
	_check(handle.is_dragging_for(player) and player.interaction_controller.is_drag_active(), "真实左键命中后建立唯一拖动绑定")
	_check(player.interaction_controller.get_drag_target() == handle, "控制器绑定当前登记拉杆")


func _to_height(height: float) -> void:
	_motion((handle.position.y - height) / float(handle.mouse_to_handle_ratio))
	await _frames(1)


func _sample(label: String) -> void:
	samples.append({"分段": sequence, "事件": label, "物理帧": Engine.get_physics_frames(), "有效秒数": probe.effective_seconds, "物理间隔": probe.last_delta, "纵向位置": handle.position.y, "状态": handle.state, "已绑定": player.interaction_controller.is_drag_active(), "完成数": completion_count, "暂停": paused})


func _await_top(label: String, from_height: float, has_hold: bool = false) -> void:
	var start: float = probe.effective_seconds
	var actual: float = 0.0
	var maximum_error: float = 0.0
	var prior_height: float = handle.position.y
	var prior_time: float = start
	var interior_speed_error: float = 0.0
	for _index: int in range(180):
		if handle.can_begin_drag(player):
			break
		await _frames(1)
		actual = probe.effective_seconds - start
		var movement_seconds: float = maxf(0.0, actual - (HOLD_SECONDS if has_hold else 0.0))
		var expected: float = minf(TOP, from_height + SPEED * movement_seconds)
		maximum_error = maxf(maximum_error, absf(handle.position.y - expected))
		var delta: float = probe.effective_seconds - prior_time
		if prior_height > BOTTOM + EPSILON and handle.position.y < TOP - EPSILON and delta > 0.0:
			interior_speed_error = maxf(interior_speed_error, absf((handle.position.y - prior_height) / delta - SPEED))
		prior_height = handle.position.y
		prior_time = probe.effective_seconds
		_sample(label)
		if handle.position.is_equal_approx(Vector3(0, TOP, 0)):
			break
	var expected_seconds: float = (TOP - from_height) / SPEED + (HOLD_SECONDS if has_hold else 0.0)
	_check(handle.position.is_equal_approx(Vector3(0, TOP, 0)), label + "最终精确恢复顶部位置")
	_check(absf(actual - expected_seconds) <= probe.last_delta + EPSILON, label + "实测时间按剩余距离换算，偏差不超过一物理帧")
	_check(maximum_error <= SPEED * probe.last_delta + EPSILON, label + "逐帧位置满足保持及匀速推进，偏差不超过一物理帧行程")
	_check(interior_speed_error < EPSILON, label + "回弹内部采样速度恒为每秒一点二局部坐标单位")
	samples.append({"分段": sequence, "事件": label + "时间核验", "起始纵向位置": from_height, "理论秒数": expected_seconds, "实测有效秒数": actual, "最大位置误差": maximum_error, "最大内部速度误差": interior_speed_error, "物理间隔": probe.last_delta})


func _test_motion_and_binding() -> void:
	await _new_scene("范围及绑定")
	var camera_pose: Transform3D = player.camera.global_transform
	await _begin()
	await _to_height(0.06)
	_check(absf(handle.position.y - 0.06) < EPSILON, "下拉按配置比例换算且不乘帧间秒数")
	var before: Vector3 = handle.position
	_motion(0.0, 120.0)
	await _frames(1)
	await _frames(4)
	_check(handle.position.is_equal_approx(before), "横向移动与静止均不改变拉杆")
	_motion(-0.03 / float(handle.mouse_to_handle_ratio))
	await _frames(1)
	_check(absf(handle.position.y - 0.09) < EPSILON, "相同比例向上移动回推拉杆")
	_motion(-0.6 / float(handle.mouse_to_handle_ratio))
	await _frames(1)
	_check(handle.position.is_equal_approx(Vector3(0, TOP, 0)), "超量上推精确限位且横向及深度不变")
	_motion(0.03 / float(handle.mouse_to_handle_ratio), 0.0, Vector2(60, 60))
	await _frames(1)
	_check(_query(cursor) != handle and handle.is_dragging_for(player), "指针离开碰撞后仍持续操作原拉杆")
	_check(absf(handle.position.y - 0.09) < EPSILON, "顶部超量上推不会积存反向死区")
	var old_index: int = player.inventory_controller.get_focused_index()
	_button(MOUSE_BUTTON_WHEEL_DOWN, true, cursor)
	_button(MOUSE_BUTTON_WHEEL_DOWN, false, cursor)
	_motion(0.03 / float(handle.mouse_to_handle_ratio))
	await _frames(1)
	_check(player.inventory_controller.get_focused_index() == posmod(old_index + 1, 4), "绑定中真实滚轮仍可切换道具格")
	_check(handle.is_dragging_for(player) and absf(handle.position.y - 0.06) < EPSILON, "切格不清除已经绑定的持续移动")
	_check(player.camera.global_transform.is_equal_approx(camera_pose), "拖动及切格期间聚焦相机不随鼠标旋转")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "拖动期间指针持续可见")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	_check(not player.interaction_controller.is_drag_active(), "提前松开释放控制器绑定")
	await _await_top("范围检查提前松开", 0.06)
	_check(completion_count == 0, "范围检查及提前松开不发完成信号")


func _test_ordered_inputs() -> void:
	await _new_scene("同帧输入顺序")
	var point: Vector2 = _pixel()
	var frame_before: int = Engine.get_physics_frames()
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.12 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	_check(Engine.get_physics_frames() == frame_before, "按下、下拉和松开全部进入同一物理帧前的有序输入队列")
	await _frames(1)
	_check(absf(handle.position.y) < EPSILON and completion_count == 0, "同帧按下下拉松开保留中途位移且提前取消")
	await _await_top("同帧提前松开", 0.0)
	var keyboard_binding: InputEventKey = InputEventKey.new()
	keyboard_binding.keycode = KEY_E
	InputMap.action_add_event(&"interact_direct", keyboard_binding)
	point = _pixel()
	_motion(0.0, 0.0, point)
	_button(MOUSE_BUTTON_LEFT, true, point)
	_key(KEY_E, true)
	_key(KEY_E, false)
	_motion(0.12 / float(handle.mouse_to_handle_ratio))
	await _frames(1)
	_check(handle.is_dragging_for(player) and absf(handle.position.y) < EPSILON, "同帧左键按下后键盘直接动作不污染左键捕获及后续移动")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	_check(not player.interaction_controller.is_drag_active() and completion_count == 0, "混合键盘输入后左键释放仍正确结束原拖动")
	await _await_top("键盘穿插的提前松开", 0.0)
	point = _pixel()
	_motion(0.0, 0.0, point)
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(1)
	_check(not handle.is_dragging_for(player) and handle.position.is_equal_approx(Vector3(0, TOP, 0)), "键盘直接动作单独命中拉杆不会冒充新的左键开始")
	InputMap.action_erase_event(&"interact_direct", keyboard_binding)
	point = _pixel()
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.24 / float(handle.mouse_to_handle_ratio))
	_motion(-0.12 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	_check(completion_count == 1 and absf(handle.position.y - BOTTOM) < EPSILON, "同帧到最低后上推松开仍立即完成一次，不以位移净和代替路径")
	await _await_top("同帧完成", BOTTOM, true)
	point = _pixel()
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.12 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_WHEEL_DOWN, true, cursor)
	_button(MOUSE_BUTTON_WHEEL_DOWN, false, cursor)
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(2)
	_check(handle.position.is_equal_approx(Vector3(0, TOP, 0)) and not player.interaction_controller.is_drag_active(), "切格作废尚未解析的开始及后续输入序列")
	_button(MOUSE_BUTTON_LEFT, true, Vector2(60, 60))
	_motion(0.12 / float(handle.mouse_to_handle_ratio), 0.0, _pixel())
	await _frames(1)
	_check(not handle.is_dragging_for(player), "其他对象上按住再移入拉杆不会启动拖动")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)


func _test_release_and_repress() -> void:
	await _new_scene("顶部同帧松开并重新按下")
	await _begin()
	var point: Vector2 = _pixel()
	var frame_before: int = Engine.get_physics_frames()
	_button(MOUSE_BUTTON_LEFT, false, point)
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.06 / float(handle.mouse_to_handle_ratio))
	_check(Engine.get_physics_frames() == frame_before, "顶部释放、重新按下和下拉全部在下一物理帧前依次入队")
	await _frames(1)
	_check(handle.is_dragging_for(player) and absf(handle.position.y - 0.06) < EPSILON, "顶部释放无剩余回弹，同帧新按下可立即开始且后续移动有效")
	_sample("顶部同帧新按下已绑定")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	await _await_top("顶部重新开始后的提前松开", 0.06)
	await _begin()
	await _to_height(0.0)
	point = _pixel()
	_button(MOUSE_BUTTON_LEFT, false, point)
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.18 / float(handle.mouse_to_handle_ratio))
	await _frames(1)
	_check(not player.interaction_controller.is_drag_active() and absf(handle.position.y) < EPSILON, "部分下拉释放进入回弹，同帧新按下由实际回弹状态拒绝")
	_sample("部分下拉新按下被锁定拒绝")
	await _await_top("部分下拉重按后的回弹", 0.0)
	_motion(0.06 / float(handle.mouse_to_handle_ratio))
	await _frames(1)
	_check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not handle.is_dragging_for(player) and handle.position.is_equal_approx(Vector3(0, TOP, 0)), "回弹期间被拒绝的新按下一直保持到归位也不会自动启动")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	await _begin()
	var bound_sequence: int = int(player.interaction_controller.get("_drag_sequence"))
	point = _pixel()
	_button(MOUSE_BUTTON_LEFT, true, point)
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.06 / float(handle.mouse_to_handle_ratio))
	await _frames(1)
	_check(int(player.interaction_controller.get("_drag_sequence")) == bound_sequence and handle.is_dragging_for(player) and absf(handle.position.y - 0.06) < EPSILON, "原左键未释放的重复按下被拒绝且保留原绑定和移动顺序")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	await _await_top("重复按下后正常释放", 0.06)
	_check(completion_count == 0, "顶部重按、回弹锁定和重复按下均不误发完成信号")


func _test_right_click_during_drag() -> void:
	await _new_scene("拖动期间右键无效")
	await _begin()
	await _to_height(0.06)
	var session_before: int = focus.session_id
	var pose_before: Vector3 = handle.position
	_button(MOUSE_BUTTON_RIGHT, true, cursor)
	_button(MOUSE_BUTTON_RIGHT, false, cursor)
	await _frames(1)
	_check(focus.session_id == session_before and focus.is_focused_on(machine.focus_target), "主动拖动期间右键不改变聚焦会话")
	_check(handle.is_dragging_for(player) and player.interaction_controller.get_drag_target() == handle and handle.position.is_equal_approx(pose_before), "主动拖动期间右键不改变绑定或拉杆位置")
	_sample("主动拖动右键被忽略")
	await _to_height(0.09)
	_check(absf(handle.position.y - 0.09) < EPSILON and handle.is_dragging_for(player), "右键无效后仍可通过真实移动事件向上回推")
	await _to_height(0.0)
	_check(absf(handle.position.y) < EPSILON and handle.is_dragging_for(player), "右键无效后仍可通过真实移动事件向下拖动")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	_check(not player.interaction_controller.is_drag_active() and focus.session_id == session_before and focus.is_focused_on(machine.focus_target), "右键无效后左键松开正常解绑并保留聚焦")
	await _await_top("右键无效后的提前松开", 0.0)
	_button(MOUSE_BUTTON_RIGHT, true, cursor)
	_button(MOUSE_BUTTON_RIGHT, false, cursor)
	_check(focus.state == AutolysisFocusController.FocusState.EXITING and focus.session_id != session_before, "未拖动时右键仍立即启动正常退出")
	await _frames(int(ceil(0.3 * Engine.physics_ticks_per_second)))
	_check(focus.state == AutolysisFocusController.FocusState.INACTIVE, "未拖动时右键正常退出完成")
	await _new_scene("同帧拖动序列穿插右键")
	var point: Vector2 = _pixel()
	session_before = focus.session_id
	var frame_before: int = Engine.get_physics_frames()
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.06 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_RIGHT, true, cursor)
	_button(MOUSE_BUTTON_RIGHT, false, cursor)
	_motion(0.06 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	_check(Engine.get_physics_frames() == frame_before, "开始下拉右键再下拉松开全部按顺序注入同一物理帧前")
	await _frames(1)
	_check(focus.session_id == session_before and focus.is_focused_on(machine.focus_target) and absf(handle.position.y) < EPSILON and not player.interaction_controller.is_drag_active() and completion_count == 0, "待解析鼠标开始期间右键无效，不清理前后移动及松开序列")
	_sample("同帧右键未清理有序序列")
	await _await_top("同帧右键无效后的松开", 0.0)
	await _new_scene("完成后最低保持允许右键退出")
	await _begin()
	await _to_height(BOTTOM)
	session_before = focus.session_id
	_button(MOUSE_BUTTON_RIGHT, true, cursor)
	_button(MOUSE_BUTTON_RIGHT, false, cursor)
	_check(focus.state == AutolysisFocusController.FocusState.EXITING and focus.session_id != session_before and completion_count == 1, "物理处理已完成后右键立即退出且保留完成一次")
	await _frames(int(ceil(0.4 * Engine.physics_ticks_per_second)))
	_check(focus.state == AutolysisFocusController.FocusState.INACTIVE and handle.position.is_equal_approx(Vector3(0, TOP, 0)) and completion_count == 1, "完成后退出不影响设备最低保持及回弹")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _new_scene("自动回弹期间允许右键退出")
	await _begin()
	await _to_height(0.0)
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	_button(MOUSE_BUTTON_RIGHT, true, cursor)
	_button(MOUSE_BUTTON_RIGHT, false, cursor)
	_check(focus.state == AutolysisFocusController.FocusState.EXITING, "已经解绑的自动回弹期间右键仍立即退出")
	await _frames(int(ceil(0.3 * Engine.physics_ticks_per_second)))
	_check(focus.state == AutolysisFocusController.FocusState.INACTIVE and handle.position.is_equal_approx(Vector3(0, TOP, 0)) and completion_count == 0, "自动回弹期间退出正常归位且不误完成")


func _test_return_times() -> void:
	for height: float in [0.09, 0.06, 0.0, -0.06]:
		await _new_scene("提前松开位置%0.2f" % height)
		await _begin()
		await _to_height(height)
		_check(absf(handle.position.y - height) < EPSILON, "输入链实际到达所测提前松开位置")
		_button(MOUSE_BUTTON_LEFT, false, cursor)
		await _frames(1)
		_check(absf(handle.position.y - height) < EPSILON, "松开帧以当前位置作为自动回弹计时零点")
		await _await_top("剩余距离回弹", height)
		_check(completion_count == 0, "未到最低的提前松开完成次数为零")


func _test_completion() -> void:
	await _new_scene("完整周期及锁定")
	_check(player.inventory_controller.try_receive_item(CAFFEINE), "夹具准备正式手持原药定义")
	await _frames(1)
	var item_before: AutolysisItemDefinition = player.inventory_controller.get_focused_item()
	await _capture("01-focused.png")
	await _begin()
	await _to_height(0.0)
	await _capture("02-middle.png")
	_motion(0.6 / float(handle.mouse_to_handle_ratio))
	await _frames(1)
	_check(completion_count == 1 and completion_actors == [player.get_instance_id()], "超量下拉立即携带实际角色发出唯一完成信号")
	_check(handle.position.is_equal_approx(Vector3(0, BOTTOM, 0)) and not player.interaction_controller.is_drag_active(), "到达最低先锁定位置并释放玩家绑定")
	_check(not handle.can_begin_drag(player), "最低保持阶段拒绝新拉杆请求")
	await _capture("03-bottom.png")
	var start: float = probe.effective_seconds
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	_button(MOUSE_BUTTON_LEFT, true, _pixel())
	_motion(-0.2 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	_check(absf(handle.position.y - BOTTOM) < EPSILON and completion_count == 1, "保持中松开及新点击不缩短最低保持也不重复完成")
	for _index: int in range(60):
		if probe.effective_seconds - start >= HOLD_SECONDS - probe.last_delta * 0.5:
			break
		await _frames(1)
		_sample("最低保持")
		_check(absf(handle.position.y - BOTTOM) <= SPEED * probe.last_delta + EPSILON, "最低保持累计零点一秒前无提前大幅回弹")
	var reference_y: float = handle.position.y
	var remaining_hold: float = maxf(0.0, HOLD_SECONDS - (probe.effective_seconds - start))
	var timing_start: float = probe.effective_seconds
	var speed_error: float = 0.0
	var last_y: float = handle.position.y
	var last_time: float = timing_start
	for _index: int in range(60):
		if handle.position.y >= TOP - EPSILON:
			break
		await _frames(1)
		var elapsed: float = probe.effective_seconds - timing_start
		var expected: float = minf(TOP, reference_y + SPEED * maxf(0.0, elapsed - remaining_hold))
		_check(absf(handle.position.y - expected) <= SPEED * probe.last_delta + EPSILON, "完成后自动阶段逐帧符合剩余保持及匀速回弹")
		var delta: float = probe.effective_seconds - last_time
		if last_y > BOTTOM + EPSILON and handle.position.y < TOP - EPSILON:
			speed_error = maxf(speed_error, absf((handle.position.y - last_y) / delta - SPEED))
		last_y = handle.position.y
		last_time = probe.effective_seconds
		_sample("完成后回弹")
	var completed_duration: float = probe.effective_seconds - start
	_check(absf(completed_duration - 0.3) <= probe.last_delta + EPSILON and speed_error < EPSILON, "最低保持零点一秒加全程零点二秒回弹且内部速度恒定")
	_check(player.inventory_controller.get_focused_item() == item_before, "拉杆交互保留手持道具且不消耗原药")
	_check(handle.position.is_equal_approx(Vector3(0, TOP, 0)) and completion_count == 1, "完整周期精确归位且完成数维持一次")
	await _capture("04-returned.png")
	await _begin()
	await _to_height(BOTTOM)
	await _await_top("持续按住的完整周期", BOTTOM, true)
	_motion(0.24 / float(handle.mouse_to_handle_ratio))
	await _frames(2)
	_check(completion_count == 2 and not handle.is_dragging_for(player) and handle.position.is_equal_approx(Vector3(0, TOP, 0)), "完成后持续按住和移动不会自动开始新一轮")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	await _begin()
	_check(handle.is_dragging_for(player), "归位后新的左键按下可以开始下一轮")
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)


func _test_accumulation_restore() -> void:
	for initial_value: bool in [true, false]:
		await _new_scene("进入前输入累积为" + ("真" if initial_value else "假"), initial_value)
		_check(not Input.use_accumulated_input, "首次左键之前稳定聚焦已禁用输入累积")
		await _begin()
		_check(not Input.use_accumulated_input, "拖动延续稳定聚焦的禁用累积状态")
		await _to_height(0.0)
		_button(MOUSE_BUTTON_LEFT, false, cursor)
		await _frames(1)
		_check(not Input.use_accumulated_input, "提前松开只恢复拖动前的聚焦累积值并保持禁用")
		await _frames(int(ceil(0.15 * Engine.physics_ticks_per_second)))
		await _begin()
		await _to_height(BOTTOM)
		_check(not Input.use_accumulated_input, "完成解绑后稳定聚焦继续禁用输入累积")
		_button(MOUSE_BUTTON_LEFT, false, cursor)
		await _frames(int(ceil(0.35 * Engine.physics_ticks_per_second)))
		await _begin()
		_action(&"menu")
		await _frames(1)
		_check(Input.use_accumulated_input == initial_value and not player.interaction_controller.is_drag_active(), "菜单取消精确恢复进入聚焦前输入累积原值")
		samples.append({"分段": sequence, "事件": "菜单累积恢复", "进入前原值": initial_value, "实际值": Input.use_accumulated_input})
		_action(&"menu")
		_button(MOUSE_BUTTON_LEFT, false, cursor)
		await _frames(1)
		_check(not Input.use_accumulated_input, "关闭菜单重新进入稳定聚焦时再次禁用累积")
		paused = true
		await _frames(1)
		_check(Input.use_accumulated_input == initial_value, "场景树暂停精确恢复进入聚焦前输入累积原值")
		paused = false
		await _frames(1)
		_check(not Input.use_accumulated_input, "恢复场景树后稳定聚焦重新禁用累积")
		_button(MOUSE_BUTTON_RIGHT, true, cursor)
		_button(MOUSE_BUTTON_RIGHT, false, cursor)
		await _frames(1)
		_check(Input.use_accumulated_input == initial_value, "右键退出开始即精确恢复进入聚焦前输入累积原值")
		await _frames(int(ceil(0.3 * Engine.physics_ticks_per_second)))
		_check(focus.state == AutolysisFocusController.FocusState.INACTIVE and Input.use_accumulated_input == initial_value, "聚焦完全退出后保留进入前输入累积原值")
		samples.append({"分段": sequence, "事件": "退出累积恢复", "进入前原值": initial_value, "实际值": Input.use_accumulated_input})
	Input.use_accumulated_input = false


func _test_interruptions() -> void:
	for reason: String in ["菜单", "暂停", "失焦", "取消标记", "尺寸变更"]:
		await _new_scene("主动拖动中断：" + reason)
		await _begin()
		await _to_height(0.0)
		if reason == "菜单":
			_action(&"menu")
		elif reason == "暂停":
			paused = true
		elif reason == "失焦":
			root.focus_exited.emit()
		elif reason == "尺寸变更":
			root.size += Vector2i(20, 10)
		else:
			_button(MOUSE_BUTTON_LEFT, false, cursor, true)
		await _frames(1)
		_check(not player.interaction_controller.is_drag_active() and not handle.is_dragging_for(player), reason + "释放尚未完成的拖动绑定")
		_check(completion_count == 0, reason + "中断不发完成信号")
		if reason == "暂停":
			var frozen: Vector3 = handle.position
			await _frames(8)
			_check(handle.position.is_equal_approx(frozen), "场景树暂停取消主动拖动并冻结回弹推进")
			paused = false
		elif reason == "菜单":
			await _frames(int(ceil(0.15 * Engine.physics_ticks_per_second)))
			_check(handle.position.y >= TOP - EPSILON, "不暂停场景树的菜单允许取消后回弹继续")
			_action(&"menu")
		elif reason == "尺寸变更":
			root.size = Vector2i(1280, 720)
		await _frames(25)
		_check(handle.position.is_equal_approx(Vector3(0, TOP, 0)), reason + "结束后拉杆可恢复顶部且没有永久绑定")
		_button(MOUSE_BUTTON_LEFT, false, cursor)
	for phase: String in ["最低保持", "回弹"]:
		await _new_scene("自动阶段暂停：" + phase)
		await _begin()
		await _to_height(BOTTOM)
		if phase == "回弹":
			await _frames(int(ceil(0.15 * Engine.physics_ticks_per_second)))
		paused = true
		await _frames(1)
		var frozen: Vector3 = handle.position
		await _frames(10)
		_check(handle.position.is_equal_approx(frozen) and completion_count == 1, phase + "期间暂停只冻结自动时间而不重复完成")
		paused = false
		await _frames(int(ceil(0.35 * Engine.physics_ticks_per_second)))
		_check(handle.position.is_equal_approx(Vector3(0, TOP, 0)), phase + "恢复后续接自动回弹")
		_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _new_scene("完成后退出")
	await _begin()
	await _to_height(BOTTOM)
	_button(MOUSE_BUTTON_RIGHT, true, cursor)
	_button(MOUSE_BUTTON_RIGHT, false, cursor)
	_check(focus.state == AutolysisFocusController.FocusState.EXITING, "完成后右键立即离开聚焦")
	await _frames(int(ceil(0.4 * Engine.physics_ticks_per_second)))
	_check(completion_count == 1 and handle.position.is_equal_approx(Vector3(0, TOP, 0)), "完成后右键离开不撤销完成且设备自动流程继续")
	_button(MOUSE_BUTTON_LEFT, false, cursor)


func _consumer(consume_presses: bool = true) -> EventConsumer:
	var consumer: EventConsumer = EventConsumer.new()
	consumer.consume_presses = consume_presses
	consumer.mouse_filter = Control.MOUSE_FILTER_PASS
	consumer.position = Vector2.ZERO
	consumer.size = Vector2(root.size)
	root.add_child(consumer)
	return consumer


func _test_gui_consumption() -> void:
	await _new_scene("界面消费输入")
	var point: Vector2 = _pixel()
	var consumer: EventConsumer = _consumer()
	await _frames(1)
	_motion(0.0, 0.0, point)
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.12 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	_check(consumer.presses == 1 and not handle.is_dragging_for(player), "界面消费开始左键后不会进入世界拖动")
	consumer.queue_free()
	await _frames(2)
	consumer = _consumer(false)
	await _begin()
	await _to_height(0.0)
	_motion(-0.06 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	_check(consumer.motions > 0 and consumer.releases == 1, "界面实际消费已经绑定拖动的移动及释放事件")
	_check(not player.interaction_controller.is_drag_active() and absf(handle.position.y - 0.06) < EPSILON, "前置输入观察保留界面消费后的移动并可靠释放")
	consumer.queue_free()
	await _await_top("界面消费释放", 0.06)
	_check(completion_count == 0, "界面消费释放的提前回弹不完成")
	await _new_scene("待解析开始的界面释放")
	point = _pixel()
	consumer = _consumer(false)
	await _frames(1)
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.12 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(1)
	_check(consumer.releases == 1 and not player.interaction_controller.is_drag_active() and absf(handle.position.y) < EPSILON, "开始尚未解析时界面消费后续释放仍保持按下移动松开顺序")
	consumer.queue_free()
	await _await_top("待解析开始可靠释放", 0.0)


func _test_sessions_and_dependencies() -> void:
	await _new_scene("旧会话及跨设备")
	var point: Vector2 = _pixel()
	_check(_query(point, other_machine.focus_target) != handle, "另一台设备的聚焦描述不能解析当前拉杆")
	_check(not other_machine.handle.can_begin_drag(player), "未聚焦设备的拉杆拒绝当前玩家")
	var old_session: int = focus.session_id
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.24 / float(handle.mouse_to_handle_ratio))
	_button(MOUSE_BUTTON_RIGHT, true, cursor)
	_button(MOUSE_BUTTON_RIGHT, false, cursor)
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(2)
	samples.append({"分段": sequence, "事件": "解析前右键忽略核验", "旧会话": old_session, "当前会话": focus.session_id, "聚焦状态": focus.state, "完成数": completion_count, "纵向位置": handle.position.y, "绑定": player.interaction_controller.is_drag_active()})
	_check(focus.session_id == old_session and focus.is_focused_on(machine.focus_target) and completion_count == 1 and absf(handle.position.y - BOTTOM) < EPSILON, "到最低的鼠标序列尚未解析时右键被忽略，完成一次且保持聚焦")
	_button(MOUSE_BUTTON_RIGHT, true, cursor)
	_button(MOUSE_BUTTON_RIGHT, false, cursor)
	_check(focus.session_id != old_session and focus.state == AutolysisFocusController.FocusState.EXITING and completion_count == 1, "已经完成后的新右键立即退出并保留完成一次")
	await _new_scene("解析前正式终止会话")
	point = _pixel()
	old_session = focus.session_id
	_button(MOUSE_BUTTON_LEFT, true, point)
	_motion(0.24 / float(handle.mouse_to_handle_ratio))
	focus.abort_session()
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	await _frames(2)
	samples.append({"分段": sequence, "事件": "正式终止后的旧序列", "旧会话": old_session, "当前会话": focus.session_id, "完成数": completion_count, "纵向位置": handle.position.y, "绑定": player.interaction_controller.is_drag_active()})
	_check(focus.session_id != old_session and completion_count == 0 and handle.position.is_equal_approx(Vector3(0, TOP, 0)), "正式终止递增会话编号并作废解析前的旧输入序列")
	for dependency: String in ["拉杆", "设备", "参考相机", "玩家"]:
		await _new_scene("拖动依赖释放：" + dependency)
		await _begin()
		await _to_height(0.0)
		if dependency == "拉杆":
			handle.queue_free()
		elif dependency == "设备":
			machine.queue_free()
		elif dependency == "参考相机":
			machine.focus_target.reference_camera.queue_free()
		else:
			player.queue_free()
		await _frames(3)
		if dependency == "玩家":
			_check(not is_instance_valid(player), "玩家释放完成且不访问已释放子节点")
		else:
			_check(not player.interaction_controller.is_drag_active(), dependency + "释放后控制器无残余绑定")
			_check(focus.state == AutolysisFocusController.FocusState.INACTIVE, dependency + "失效终止正式聚焦会话")
		_check(completion_count == 0, dependency + "释放不发完成信号")
		_button(MOUSE_BUTTON_LEFT, false, cursor)


func _test_completion_reentry() -> void:
	var actions: Array[String] = ["重新请求", "删除设备"]
	if OS.get_cmdline_user_args().has("--immediate-source-free"):
		actions.append("立即释放设备")
	for action: String in actions:
		await _new_scene("完成回调：" + action)
		completion_action = action
		await _begin()
		_motion(0.24 / float(handle.mouse_to_handle_ratio))
		_motion(-0.24 / float(handle.mouse_to_handle_ratio))
		_button(MOUSE_BUTTON_LEFT, false, cursor)
		await _frames(3)
		_check(completion_count == 1, action + "同步回调只完成一次")
		if action == "重新请求":
			_check(not reentry_result and not handle.is_dragging_for(player), "完成前先改变状态，正式组件拒绝同步重入请求")
			await _frames(int(ceil(0.35 * Engine.physics_ticks_per_second)))
			_check(handle.position.is_equal_approx(Vector3(0, TOP, 0)), "重入拒绝后原自动回弹流程正常归位")
		else:
			_check(not is_instance_valid(machine) and not player.interaction_controller.is_drag_active(), "完成回调释放设备后不遗留绑定或访问失效对象")


func _collision_sample(label: String, previous_point: Vector3 = Vector3.INF) -> Vector3:
	var shape: CollisionShape3D = handle.get_node("collision_handle_interaction") as CollisionShape3D
	var node_pose: Transform3D = handle.global_transform
	var server_pose: Transform3D = PhysicsServer3D.body_get_state(handle.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var error: float = maxf(node_pose.origin.distance_to(server_pose.origin), maxf(node_pose.basis.x.distance_to(server_pose.basis.x), maxf(node_pose.basis.y.distance_to(server_pose.basis.y), node_pose.basis.z.distance_to(server_pose.basis.z))))
	var point: Vector3 = shape.global_position
	var query: PhysicsPointQueryParameters3D = PhysicsPointQueryParameters3D.new()
	query.collision_mask = 32
	query.exclude = _exclusions()
	query.position = point
	var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_point(query)
	var found_new: bool = false
	for hit: Dictionary in hits:
		found_new = found_new or hit.get("collider") == handle
	var found_old: bool = false
	if previous_point != Vector3.INF:
		query.position = previous_point
		var old_hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_point(query)
		for hit: Dictionary in old_hits:
			found_old = found_old or hit.get("collider") == handle
	var pixel: Vector2 = _pixel()
	collision_records.append({"阶段": label, "物理帧": Engine.get_physics_frames(), "局部位置": str(handle.position), "节点姿态": str(node_pose), "物理服务器姿态": str(server_pose), "姿态误差": error, "新位置点": str(point), "新位置命中": found_new, "旧位置点": str(previous_point), "旧位置仍命中": found_old, "正式射线像素": str(pixel)})
	_check(error < EPSILON and found_new, label + "节点及物理服务器姿态一致且新位置真实点查询命中")
	if previous_point != Vector3.INF:
		_check(not found_old, label + "旧位置点查询无拉杆幽灵碰撞")
	return point


func _test_collision_follow() -> void:
	await _new_scene("实际碰撞跟随")
	var old_point: Vector3 = _collision_sample("初始")
	await _begin()
	await _to_height(0.0)
	old_point = _collision_sample("中途", old_point)
	await _to_height(BOTTOM)
	old_point = _collision_sample("最低", old_point)
	await _frames(int(ceil(0.2 * Engine.physics_ticks_per_second)))
	old_point = _collision_sample("回弹", old_point)
	await _frames(int(ceil(0.2 * Engine.physics_ticks_per_second)))
	_collision_sample("归位", old_point)
	_check(handle.position.is_equal_approx(Vector3(0, TOP, 0)), "碰撞跟随完整周期保留规定初始结构和位置")
	_button(MOUSE_BUTTON_LEFT, false, cursor)


func _capture(filename: String) -> void:
	if not graphical:
		return
	await RenderingServer.frame_post_draw
	var output: String = evidence_directory.path_join(filename)
	var result: Error = root.get_texture().get_image().save_png(output)
	_check(result == OK, "保存正式聚焦视角的实际图形画面")
	if result == OK:
		screenshots.append(output)


func _run_manual() -> void:
	await _new_scene("本机实际鼠标取证", original_accumulation)
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var seconds_index: int = arguments.find("--manual-seconds")
	if seconds_index >= 0 and seconds_index + 1 < arguments.size():
		manual_duration = clampf(float(arguments[seconds_index + 1]), 60.0, 180.0)
	root.title = "原药混合器拉杆实际输入取证"
	var layer: CanvasLayer = CanvasLayer.new()
	root.add_child(layer)
	var label: Label = Label.new()
	label.position = Vector2(16, 16)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 5)
	layer.add_child(label)
	var observer: ManualObserver = ManualObserver.new()
	observer.runner = self
	observer.label = label
	root.add_child(observer)
	manual_started_ms = Time.get_ticks_msec()
	print("本机实际操作窗口已就绪；截图导出键为第八功能键，提前结束键为第九功能键。")
	await _capture("manual-start.png")
	while not manual_done and float(Time.get_ticks_msec() - manual_started_ms) / 1000.0 < manual_duration:
		await _frames(1)
	observer.queue_free()
	layer.queue_free()
	_check(manual_input_count > 0, "图形操作阶段收到实际鼠标输入事件")
	_check(manual_maximum_physics_error < EPSILON and manual_point_misses == 0, "图形操作中移动拉杆的物理服务器姿态及新位置点查询跟随")
	samples.append({"事件": "实际操作结束", "实际鼠标事件数": manual_input_count, "原始纵向累计": manual_relative_y, "原始横向累计": manual_relative_x, "完成数": completion_count, "实际墙钟秒数": float(Time.get_ticks_msec() - manual_started_ms) / 1000.0, "配置比例": handle.mouse_to_handle_ratio, "物理服务器最大姿态误差": manual_maximum_physics_error, "新位置点查询遗漏数": manual_point_misses})
	await _capture("manual-end.png")


func _record_manual_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8:
			manual_capture_count += 1
			_export_manual_capture.call_deferred(manual_capture_count)
		elif event.keycode == KEY_F9:
			manual_done = true
	if not event is InputEventMouse:
		return
	manual_input_count += 1
	var entry: Dictionary = {"分段": sequence, "来源": "本机实际鼠标", "物理帧": Engine.get_physics_frames(), "墙钟毫秒": Time.get_ticks_msec() - manual_started_ms, "视口位置": str(event.position), "输入系统鼠标位置": str(root.get_mouse_position()), "纵向位置": handle.position.y, "状态": handle.state, "完成数": completion_count, "控制器绑定": player.interaction_controller.is_drag_active()}
	if event is InputEventMouseMotion:
		manual_relative_y += event.relative.y
		manual_relative_x += event.relative.x
		entry["种类"] = "实际移动"
		entry["视口相对位移"] = str(event.relative)
		entry["未缩放相对位移"] = str(event.screen_relative)
		entry["按钮掩码"] = event.button_mask
	else:
		entry["种类"] = "实际按钮"
		entry["按钮编号"] = event.button_index
		entry["按下"] = event.pressed
		entry["取消标记"] = event.canceled
	inputs.append(entry)


func _update_manual_label(label: Label) -> void:
	if not is_instance_valid(handle) or not is_instance_valid(player):
		manual_done = true
		return
	var statuses: Array[String] = ["待机", "拖动", "最低保持", "回弹"]
	var remaining: float = maxf(0.0, manual_duration - float(Time.get_ticks_msec() - manual_started_ms) / 1000.0)
	label.text = "原药混合器拉杆实际操作取证\n换算比例：%.6f　局部纵向位置：%.5f\n状态：%s　完成次数：%d　已绑定：%s\n原始鼠标纵向累计：%.1f　输入事件：%d\n鼠标位置：%s　剩余秒数：%.0f\n第八功能键：保存画面和记录　第九功能键：结束" % [handle.mouse_to_handle_ratio, handle.position.y, statuses[int(handle.state)], completion_count, "是" if player.interaction_controller.is_drag_active() else "否", manual_relative_y, manual_input_count, str(root.get_mouse_position()), remaining]


func _record_manual_physics() -> void:
	if not is_instance_valid(handle) or not is_instance_valid(player):
		return
	if absf(handle.position.y - manual_prior_height) < EPSILON and Engine.get_physics_frames() % 5 != 0:
		return
	var server_pose: Transform3D = PhysicsServer3D.body_get_state(handle.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var error: float = server_pose.origin.distance_to(handle.global_position)
	manual_maximum_physics_error = maxf(manual_maximum_physics_error, error)
	var shape: CollisionShape3D = handle.get_node("collision_handle_interaction") as CollisionShape3D
	var query: PhysicsPointQueryParameters3D = PhysicsPointQueryParameters3D.new()
	query.position = shape.global_position
	query.collision_mask = 32
	query.exclude = _exclusions()
	var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_point(query)
	var found: bool = false
	for hit: Dictionary in hits:
		found = found or hit.get("collider") == handle
	if not found:
		manual_point_misses += 1
	manual_prior_height = handle.position.y
	samples.append({"分段": sequence, "事件": "实际操作物理采样", "物理帧": Engine.get_physics_frames(), "有效秒数": probe.effective_seconds, "墙钟毫秒": Time.get_ticks_msec() - manual_started_ms, "位置": str(handle.position), "状态": handle.state, "完成数": completion_count, "绑定": player.interaction_controller.is_drag_active(), "服务器姿态误差": error, "新位置点命中": found, "鼠标可见": Input.mouse_mode == Input.MOUSE_MODE_VISIBLE})


func _export_manual_capture(index: int) -> void:
	await _capture("manual-capture-%02d.png" % index)
	_save_report()
	print("本机实际操作取证已导出，画面编号：", index)


func _save_report() -> void:
	var report: Dictionary = {"图形运行": graphical, "自动注入入口": "Input.parse_input_event（输入系统解析输入事件）", "物理迭代数": Engine.physics_ticks_per_second, "窗口尺寸": str(root.size), "内容缩放模式": root.content_scale_mode, "内容缩放尺寸": str(root.content_scale_size), "内容缩放因子": root.content_scale_factor, "正式场景读取比例": configured_ratio, "图形普通输入进入次数": graphical_entry_count, "断言数": assertion_count, "失败数": failures, "断言": records, "注入输入顺序": inputs, "物理有效时间采样": samples, "碰撞实际查询": collision_records, "截图": screenshots, "另需图形取证": ["本机鼠标定位事件序列及补偿", "上下边缘多次循环与快速反向", "循环定位同帧松开", "嵌入及内容缩放坐标转换", "正常实时拉动比例体验调校及用户体验验收"]}
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("blend-handle-drag-report.json"), FileAccess.WRITE)
	if file == null:
		_check(false, "拉杆验收报告可写入独立证据目录")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
