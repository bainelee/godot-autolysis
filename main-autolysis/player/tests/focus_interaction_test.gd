extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 正式玩家与正式设备的集成验收。所有业务点击通过输入系统进入唯一入口。
## 只读射线用于选择真实可命中像素，不通过直接开关槽位或动画构造通过结果。

const DEMO: PackedScene = preload("res://main-autolysis/player/tests/focus_interaction_demo.tscn")
const RAY_SCRIPT: Script = preload("res://main-autolysis/player/components/autolysis_focus_ray_query.gd")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const SODIUM: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/sodium_benzoate.tres")
const INACTIVE: int = 0
const ENTERING: int = 1
const FOCUSED: int = 2
const EXITING: int = 3
const INVALID_PIXEL: Vector2 = Vector2(-10000, -10000)

class ClickConsumer extends Control:
	var consumed: int = 0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				consumed += 1
			accept_event()

var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/聚焦交互与原药混合器p1实施证据/自动检查/聚焦行为")
var machine: Node3D
var other_machine: Node3D
var focus: Node
var inventory: AutolysisInventoryController
var ray_query: RefCounted = RAY_SCRIPT.new()
var records: Array[Dictionary] = []
var assertion_count: int = 0
var camera_samples: Array[Dictionary] = []
var ray_records: Array[Dictionary] = []
var screenshots: Array[String] = []
var graphical: bool = false
var original_accumulation: bool = true
var camera_start: Transform3D
var camera_local_start: Transform3D
var presenter_start: Transform3D
var presenter_top_level_start: bool
var camera_fov_start: float
var camera_projection_start: Dictionary = {}
var camera_id: int
var camera_relative_presenter: Transform3D
var cursor: Vector2 = Vector2.ZERO
var animation_restore_observation: Dictionary = {}
var animation_records: Array[Dictionary] = []


func check(condition: bool, description: String) -> void:
	assertion_count += 1
	super.check(condition, description)
	records.append({"说明": description, "通过": condition})


func run_checks() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	await _new_scene()
	if OS.get_cmdline_user_args().has("--animation-only"):
		await _test_camera_animation_resume()
	elif OS.get_cmdline_user_args().has("--queued-only"):
		await _test_queued_inputs()
	elif OS.get_cmdline_user_args().has("--main-only"):
		await _test_main_scene()
	elif OS.get_cmdline_user_args().has("--local-only"):
		await _test_local_dependency_isolation()
	else:
		await _test_normal_entry_gates()
		await _obtain_source_items()
		await _test_camera_and_control()
		await _test_slots_and_transfer()
		await _test_obstructions()
		await _test_gui_consumption()
		await _test_queued_inputs()
		await _test_cancellation()
		await _test_alternate_camera_snapshots()
		await _test_camera_animation_resume()
		await _test_menu_and_pause()
		await _test_dependency_release()
		await _test_local_dependency_isolation()
		await _test_main_scene()
	_save_report()
	_release_controls()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	if is_instance_valid(world):
		world.queue_free()
	await frames(2)
	print("聚焦验收断言数：", assertion_count, "；记录数：", records.size(), "；失败总数：", failures, "；图形后端：", graphical)
	quit(1 if failures > 0 else 0)


func _new_scene() -> void:
	_release_controls()
	paused = false
	if is_instance_valid(world):
		world.queue_free()
		await frames(2)
	world = DEMO.instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	machine = world.get_node("MachineA")
	other_machine = world.get_node("MachineB")
	focus = player.get_node("FocusController")
	inventory = player.inventory_controller
	if not graphical:
		# 夹具只替换无图形后端缺失的捕获状态，保留正式玩家其余全部输入门控。
		focus.configure(player, player.camera, player.held_item_presenter, _headless_entry_allowed)
	await frames(25)
	await _aim_root()


func _headless_entry_allowed() -> bool:
	return player._base_input_allowed() and not focus.has_control()


func _button(button: MouseButton, pressed: bool, point: Vector2) -> void:
	cursor = point
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_move_cursor(point)
	_button(button, true, point)
	await frames(1)
	_button(button, false, point)
	await frames(1)


func _move_cursor(point: Vector2, movement: Vector2 = Vector2.ZERO) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = movement
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	cursor = point


func _action(action: StringName, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _joy(axis: JoyAxis, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release_controls() -> void:
	for action: StringName in [&"forward", &"back", &"left", &"right", &"jump", &"crouch", &"sprint", &"free_look", &"interact_direct", &"focus_exit"]:
		Input.action_release(action)
	_joy(JOY_AXIS_RIGHT_X, 0.0)
	_joy(JOY_AXIS_RIGHT_Y, 0.0)


func _wheel() -> void:
	_button(MOUSE_BUTTON_WHEEL_DOWN, true, cursor)
	_button(MOUSE_BUTTON_WHEEL_DOWN, false, cursor)
	await frames(1)


func _select(index: int) -> void:
	for attempt: int in range(4):
		if inventory.get_focused_index() == index:
			return
		await _wheel()
	check(inventory.get_focused_index() == index, "真实滚轮到达指定道具格")


func _aim_root() -> void:
	player.body.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.eyes.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.head.look_at(machine.to_global(Vector3(0, 0.3, 0.075)), Vector3.UP)
	await frames(3)


func _snapshot() -> void:
	camera_start = player.camera.global_transform
	camera_local_start = player.camera.transform
	camera_fov_start = player.camera.fov
	camera_projection_start.clear()
	for property: StringName in [&"projection", &"keep_aspect", &"size", &"near", &"far", &"h_offset", &"v_offset", &"frustum_offset"]:
		camera_projection_start[property] = player.camera.get(property)
	camera_id = player.camera.get_instance_id()
	presenter_start = player.held_item_presenter.transform
	presenter_top_level_start = player.held_item_presenter.is_set_as_top_level()
	camera_relative_presenter = player.camera.global_transform.affine_inverse() * player.held_item_presenter.global_transform


func _start_entry() -> void:
	await _aim_root()
	_snapshot()
	if graphical:
		_button(MOUSE_BUTTON_LEFT, true, Vector2(root.size) * 0.5)
	else:
		# 无图形后端不实现鼠标捕获。此入口只建立夹具，不声称覆盖普通鼠标入口。
		check(focus.try_enter(machine.focus_target), "无图形夹具通过正式会话入口建立聚焦")
	await frames(1)
	_button(MOUSE_BUTTON_LEFT, false, Vector2(root.size) * 0.5)


func _enter() -> void:
	await _start_entry()
	await frames(15)
	check(focus.state == FOCUSED, "正式设备进入稳定聚焦")


func _exit() -> void:
	if focus.state != INACTIVE:
		await _click(cursor, MOUSE_BUTTON_RIGHT)
		await frames(15)
	check(focus.state == INACTIVE, "真实右键归还普通控制")


func _test_normal_entry_gates() -> void:
	check(machine.slots.size() == 4 and other_machine.slots.size() == 4, "验证场景包含两台完整正式混合器")
	check(player.is_on_floor() and player.camera.current, "真实玩家着地且保持角色相机当前身份")
	if not graphical:
		records.append({"说明": "无图形后端无法保持捕获鼠标，普通入口及普通原药组点击由图形运行覆盖", "未覆盖": true})
		return
	check(player.interaction_raycast.get_collider() == machine, "普通中心射线首先命中设备根")
	var saved_position: Vector3 = player.position
	player.position.z += 3.0
	await _aim_root()
	await _click(Vector2(root.size) * 0.5)
	check(focus.state == INACTIVE, "超出两单位普通交互距离不能进入")
	player.position = saved_position
	await _aim_root()
	player.head.rotation.y = PI * 0.5
	await frames(3)
	await _click(Vector2(root.size) * 0.5)
	check(focus.state == INACTIVE, "普通视线偏离设备不能进入")
	await _aim_root()
	var blocker: StaticBody3D = box(Vector3(0.8, 0.8, 0.05), player.camera.global_position + -player.camera.global_basis.z * 0.35)
	await frames(3)
	await _click(Vector2(root.size) * 0.5)
	check(focus.state == INACTIVE, "设备根前墙体阻止普通聚焦入口")
	blocker.queue_free()
	await frames(3)


func _obtain_source_items() -> void:
	if not graphical:
		check(inventory.try_receive_item(CAFFEINE), "无图形夹具准备第一种正式原药")
		check(inventory.cycle_focus(1) and inventory.try_receive_item(SODIUM), "无图形夹具准备第二种正式原药")
		check(inventory.cycle_focus(1), "无图形夹具使用空的第三格")
		return
	for source_name: String in ["CaffeineSource", "SodiumSource"]:
		var source: Node3D = world.get_node(source_name)
		player.head.look_at(source.global_position + Vector3(0, 0.1, 0), Vector3.UP)
		await frames(3)
		check(player.interaction_raycast.get_collider() == source, "普通射线实际命中验证场景原药来源")
		await _click(Vector2(root.size) * 0.5)
		check(inventory.get_focused_item() == source.item_definition, "真实左键从正式原药组取得对应定义")
		await _wheel()
	await _aim_root()


func _test_camera_and_control() -> void:
	player.camera.fov = 71.0
	await _aim_root()
	_snapshot()
	await _capture("01-before-enter.png")
	var start_frame: int = Engine.get_physics_frames()
	if graphical:
		_button(MOUSE_BUTTON_LEFT, true, Vector2(root.size) * 0.5)
	else:
		focus.try_enter(machine.focus_target)
	var first_session: int = focus.session_id
	var middle_seen: bool = false
	var completion_frame: int = -1
	var first_motion_frame: int = -1
	var arrival_frame: int = -1
	var held_synchronous: bool = true
	for frame_index: int in range(15):
		await frames(1)
		var error: float = player.camera.global_position.distance_to(machine.get_node("focus_camera").global_position)
		camera_samples.append({"方向": "进入", "采样帧": Engine.get_physics_frames() - start_frame, "状态": focus.state, "位置": str(player.camera.global_position), "视野": player.camera.fov, "目标位置误差": error})
		middle_seen = middle_seen or (focus.state == ENTERING and error > 0.001 and player.camera.global_position.distance_to(camera_start.origin) > 0.001)
		if first_motion_frame < 0 and player.camera.global_position.distance_to(camera_start.origin) > 0.001:
			first_motion_frame = Engine.get_physics_frames() - start_frame
		if arrival_frame < 0 and error < 0.0001:
			arrival_frame = Engine.get_physics_frames() - start_frame
		held_synchronous = held_synchronous and _presenter_follows_camera()
		if frame_index == 2:
			var old_index: int = inventory.get_focused_index()
			_button(MOUSE_BUTTON_WHEEL_DOWN, true, cursor)
			_button(MOUSE_BUTTON_WHEEL_DOWN, false, cursor)
			check(inventory.get_focused_index() == posmod(old_index + 1, 4), "进入阶段真实滚轮有效")
		if focus.state == FOCUSED and completion_frame < 0:
			completion_frame = Engine.get_physics_frames() - start_frame
	_button(MOUSE_BUTTON_LEFT, false, cursor)
	check(focus.state == FOCUSED and middle_seen, "相机进入存在中间帧并完成过渡")
	# 绘制后开始输入时，第一个处理信号可能先于补间首次推进；保留原始采样并单列这段输入调度延迟。
	var transition_start_frame: int = first_motion_frame - 1
	camera_samples.append({"方向": "进入时序核对", "首次运动原始帧": first_motion_frame, "目标到达原始帧": arrival_frame, "状态完成原始帧": completion_frame, "运动前采样帧数": transition_start_frame, "实际运动帧数": arrival_frame - transition_start_frame})
	check(arrival_frame - transition_start_frame == 12 and completion_frame - transition_start_frame <= 13, "固定六十帧下进入运动恰好零点二秒且完成观察偏差最多一帧")
	check(focus.session_id == first_session and _all_closed(), "进入左键保持按住只建立一个会话且不开槽")
	check(player.camera.get_instance_id() == camera_id and player.camera.current, "聚焦始终使用同一个玩家相机")
	check(_transform_error(player.camera.global_transform, machine.get_node("focus_camera").global_transform) < 0.0001 and is_equal_approx(player.camera.fov, 55.0), "角色相机精确匹配正式设备目标世界变换与视野")
	check(held_synchronous, "进入每个采样帧手持展示器与相机同步")
	check(not player.interaction_controller.is_direct_available() and player.inventory_bar.visible, "聚焦停止普通四线交互提示并保留道具栏")
	var prior_index: int = inventory.get_focused_index()
	await _wheel()
	check(inventory.get_focused_index() == posmod(prior_index + 1, 4), "稳定聚焦阶段真实滚轮有效")
	await _select(0)
	check(player.held_item_presenter.get_display() != null, "稳定聚焦切到有药格时手持模型存在")
	await _capture("02-focused-held.png")
	var root_pose: Transform3D = player.global_transform
	var body_pose: Transform3D = player.body.transform
	var neck_pose: Transform3D = player.neck.transform
	var head_pose: Transform3D = player.head.transform
	var eyes_pose: Transform3D = player.eyes.transform
	var camera_pose: Transform3D = player.camera.global_transform
	for action: StringName in [&"forward", &"right", &"jump", &"crouch", &"sprint", &"free_look"]:
		_action(action, true)
	_joy(JOY_AXIS_RIGHT_X, 0.9)
	_joy(JOY_AXIS_RIGHT_Y, -0.8)
	_move_cursor(Vector2(450, 350), Vector2(100, -50))
	await frames(8)
	check(_transform_error(player.global_transform, root_pose) < 0.0001 and _transform_error(player.body.transform, body_pose) < 0.0001 and _transform_error(player.neck.transform, neck_pose) < 0.0001 and _transform_error(player.head.transform, head_pose) < 0.0001 and _transform_error(player.eyes.transform, eyes_pose) < 0.0001, "移动跳跃蹲伏冲刺自由观察及摇杆均不改变冻结姿态")
	check(_transform_error(player.camera.global_transform, camera_pose) < 0.0001 and player.velocity.is_zero_approx() and player.main_velocity.is_zero_approx(), "聚焦镜头不被普通流程争写且无残余运动速度")
	_release_controls()
	await frames(2)


func _presenter_follows_camera() -> bool:
	return _transform_error(player.held_item_presenter.global_transform, player.camera.global_transform * camera_relative_presenter) < 0.0001


func _all_closed() -> bool:
	for slot: Node3D in machine.slots:
		if slot.state != 0:
			return false
	return true


func _exclusions() -> Array[RID]:
	return [player.get_rid(), player.get_node("DegaussPlayerFoundArea").get_rid()]


func _query(point: Vector2) -> Node3D:
	return ray_query.query_target(player.camera, point, machine.focus_target, _exclusions())


func _pixel(slot_index: int, transfer: bool = false) -> Vector2:
	var slot: Node3D = machine.slots[slot_index]
	var wanted: Node3D = slot.raw_material_anchor if transfer else slot
	var held_rectangle: Rect2 = _held_projection_rectangle()
	# 将原有盒体内部规则网格投影到屏幕，逐点读取正式查询的实际结果。
	for height: float in [0.2, 0.12, 0.32, 0.05, 0.38]:
		for depth: float in [-0.16, -0.32, 0.05, 0.12, -0.39]:
			for horizontal: float in [0.0, -0.06, 0.06, -0.13, 0.13]:
				var point: Vector2 = player.camera.unproject_position(slot.to_global(Vector3(horizontal, height, depth)))
				if not Rect2(Vector2.ZERO, Vector2(root.size)).has_point(point):
					continue
				# 从手持全部网格的投影包围矩形之外选择，保守证明必要点击像素确实可见。
				if held_rectangle.has_area() and held_rectangle.has_point(point):
					continue
				if _query(point) == wanted:
					ray_records.append({"槽位": slot_index, "取放": transfer, "像素": str(point), "目标": str(wanted.get_path()), "相机距离": player.camera.global_position.distance_to(wanted.global_position), "手持投影包围矩形": str(held_rectangle), "点击位于手持投影外": true})
					return point
	check(false, "正式有限射线找到可操作像素：槽位%d，取放%s" % [slot_index, str(transfer)])
	return INVALID_PIXEL


func _held_projection_rectangle() -> Rect2:
	var display: Node3D = player.held_item_presenter.get_display()
	if display == null:
		return Rect2()
	var meshes: Array[Node] = display.find_children("*", "MeshInstance3D", true, false)
	if display is MeshInstance3D:
		meshes.append(display)
	var result: Rect2 = Rect2()
	var initialized: bool = false
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var bounds: AABB = mesh.get_aabb()
		for index: int in range(8):
			var projected: Vector2 = player.camera.unproject_position(mesh.to_global(bounds.get_endpoint(index)))
			if not initialized:
				result = Rect2(projected, Vector2.ZERO)
				initialized = true
			else:
				result = result.expand(projected)
	return result




func _test_slots_and_transfer() -> void:
	var zero: Node3D = machine.slots[0]
	var one: Node3D = machine.slots[1]
	var zero_anchor: Transform3D = zero.raw_material_anchor.transform
	var one_anchor: Transform3D = one.raw_material_anchor.transform
	var pixel_zero: Vector2 = _pixel(0)
	await _click(pixel_zero)
	check(zero.is_animating(), "真实鼠标点击零号槽立即进入打开运动")
	await _click(_pixel(1))
	check(zero.is_animating() and one.is_animating(), "零号尚未完成时一号可接受真实鼠标点击")
	var zero_physics: Transform3D = PhysicsServer3D.body_get_state(zero.raw_material_anchor.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var one_physics: Transform3D = PhysicsServer3D.body_get_state(one.raw_material_anchor.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	check(_transform_error(zero_physics, zero.global_transform * zero_anchor) < 0.0001 and _transform_error(one_physics, one.global_transform * one_anchor) < 0.0001, "两槽动画中物理服务器的嵌套取放体保持动画前局部姿态同步随动")
	await _capture("03-two-slots-moving.png")
	await _click(pixel_zero)
	check(zero.state == 1, "同槽运动中重复点击不反向或排队")
	await frames(15)
	check(zero.is_open() and one.is_open(), "两段独立打开动画均完成且零号不被打断")
	for index: int in [2, 3]:
		await _click(_pixel(index))
	await frames(15)
	var all_open: bool = true
	for slot: Node3D in machine.slots:
		all_open = all_open and slot.is_open()
	check(all_open, "四个屏幕位置均可操作并同时保持打开")
	await _select(2)
	await _click(_pixel(0, true))
	check(zero.is_open() and zero.get_stored_item() == null, "空手点击空取放区域不回退为关槽")
	var count_before: int = _item_count()
	await _select(0)
	await _capture("04a-open-held.png")
	await _click(_pixel(2, true))
	var stored: Node3D = machine.slots[2].get_stored_item()
	check(stored != null and inventory.get_focused_item() == null and zero.get_stored_item() == null, "第一种原药只放入鼠标指定二号槽")
	check(_item_count() == count_before, "指定槽放入前后原药数量守恒")
	if stored != null:
		check(stored.get_parent() == machine.slots[2].raw_material_anchor and stored.transform.is_equal_approx(Transform3D.IDENTITY), "设备原药使用原锚点单位局部变换")
		check(stored.collision_layer == 0 and stored.collision_mask == 0 and not inventory.try_take_world_item(stored), "设备中原药无碰撞且普通拾取入口不能绕过槽位")
	await _capture("04-material-in-slot.png")
	await _select(1)
	await _click(_pixel(3, true))
	check(machine.slots[3].get_stored_item() != null and inventory.get_focused_item() == null and _item_count() == count_before, "第二种原药通过真实鼠标放入三号槽且数量守恒")
	await _select(2)
	await _click(_pixel(2, true))
	check(inventory.get_focused_index() == 2 and inventory.get_focused_item() == CAFFEINE and machine.slots[2].get_stored_item() == null, "指定取回写入当前第三格而不自动填前方空格")
	await _click(_pixel(3, true))
	check(inventory.get_focused_item() == CAFFEINE and machine.slots[3].get_stored_item() != null, "当前有药时拒绝取回或覆盖已有槽药品")
	await _click(_pixel(2, true))
	stored = machine.slots[2].get_stored_item()
	var before_motion: Vector3 = stored.global_position if stored != null else Vector3.ZERO
	await _click(_pixel(2))
	await frames(5)
	check(stored != null and stored.global_position.distance_to(before_motion) > 0.0001 and stored.transform.is_equal_approx(Transform3D.IDENTITY), "含药槽动画中原药跟随锚点且不改变局部姿态")
	await frames(15)
	check(machine.slots[2].state == 0 and zero.is_open() and one.is_open() and machine.slots[3].is_open(), "关闭二号槽不重置其他三个槽位")
	var start_frame: int = Engine.get_physics_frames()
	_button(MOUSE_BUTTON_RIGHT, true, cursor)
	_button(MOUSE_BUTTON_RIGHT, false, cursor)
	var completion: int = -1
	var follow_valid: bool = true
	for index: int in range(15):
		await frames(1)
		if focus.has_control():
			follow_valid = follow_valid and _presenter_follows_camera()
		camera_samples.append({"方向": "退出", "采样帧": Engine.get_physics_frames() - start_frame, "状态": focus.state, "位置": str(player.camera.global_position), "恢复位置误差": player.camera.global_position.distance_to(camera_start.origin), "视野": player.camera.fov})
		if index == 2:
			var old: int = inventory.get_focused_index()
			_button(MOUSE_BUTTON_WHEEL_DOWN, true, cursor)
			_button(MOUSE_BUTTON_WHEEL_DOWN, false, cursor)
			check(inventory.get_focused_index() == posmod(old + 1, 4), "退出阶段真实滚轮有效")
		if focus.state == INACTIVE and completion < 0:
			completion = Engine.get_physics_frames() - start_frame
	check(completion >= 11 and completion <= 13, "固定六十帧下退出为零点二秒且观察偏差最多一帧")
	check(follow_valid, "退出中手持展示器每帧同步跟随相机")
	_assert_restored("正常退出")
	await _capture("05-restored.png")
	await _enter()
	check(machine.slots[2].state == 0 and machine.slots[2].get_stored_item() == stored and zero.is_open() and machine.slots[3].is_open(), "重新进入保留开闭状态与指定原药占用")
	await _click(_pixel(2))
	await frames(15)
	check(machine.slots[2].is_open() and machine.slots[2].get_stored_item() == stored, "含药槽再次打开保留原药")


func _item_count() -> int:
	var total: int = 0
	for index: int in range(4):
		if inventory.get_slot_item(index) != null:
			total += 1
	for slot: Node3D in machine.slots:
		if slot.get_stored_item() != null:
			total += 1
	return total


func _assert_restored(label: String) -> void:
	check(focus.state == INACTIVE and not focus.has_control(), label + "归还会话控制权")
	check(_transform_error(player.camera.global_transform, camera_start) < 0.0001 and _transform_error(player.camera.transform, camera_local_start) < 0.0001 and abs(player.camera.fov - camera_fov_start) < 0.0001, label + "恢复原相机世界与局部快照及视野")
	check(player.camera.get_instance_id() == camera_id and player.camera.current, label + "保持玩家相机身份")
	var projection_restored: bool = true
	for property: StringName in camera_projection_start:
		projection_restored = projection_restored and player.camera.get(property) == camera_projection_start[property]
	check(projection_restored, label + "恢复投影模式、裁剪面、尺寸、偏移及长宽适配参数")
	check(player.held_item_presenter.is_set_as_top_level() == presenter_top_level_start and _transform_error(player.held_item_presenter.transform, presenter_start) < 0.0001, label + "恢复手持展示器局部变换和独立标记")


func _test_obstructions() -> void:
	await _select(0)
	var slot: Node3D = machine.slots[2]
	var camera_before: Transform3D = player.camera.global_transform
	var presenter_before: Transform3D = player.held_item_presenter.global_transform
	var reference_before: Transform3D = machine.focus_target.reference_camera.global_transform
	var outer_collision: CollisionShape3D = slot.get_node("CollisionShape3D") as CollisionShape3D
	var inner_collision: CollisionShape3D = slot.raw_material_anchor.get_node("collision_rm_place_slot_2") as CollisionShape3D
	var outer_shape: BoxShape3D = outer_collision.shape as BoxShape3D
	# 正式参考视角只能命中两盒共有上边界。仅此独立墙夹具临时从槽侧面观察，
	# 相机位于原外盒侧面外两厘米，仍处于相邻槽体之间；原盒体和参考相机不变。
	player.camera.global_position = inner_collision.global_position + outer_collision.global_basis.x * (outer_shape.size.x * 0.5 + 0.02)
	player.camera.look_at(inner_collision.global_position, slot.global_basis.y.normalized())
	player.held_item_presenter.sync_camera_follow()
	var camera_observation: Dictionary = {"用途": "内部墙夹具临时相机", "临时相机世界变换": str(player.camera.global_transform), "临时相机位置": str(player.camera.global_position), "临时相机方向": str(-player.camera.global_basis.z), "原玩家相机世界变换": str(camera_before), "正式参考相机世界变换": str(reference_before), "槽外盒尺寸": str(outer_shape.size), "侧面外偏移": 0.02}
	ray_records.append(camera_observation)
	print("内部墙夹具相机观测：", JSON.stringify(camera_observation))
	await _test_internal_wall_obstruction(2)
	player.camera.global_transform = camera_before
	player.held_item_presenter.sync_camera_follow()
	check(_transform_error(player.camera.global_transform, camera_before) < 0.0001 and _transform_error(player.held_item_presenter.global_transform, presenter_before) < 0.0001 and _transform_error(machine.focus_target.reference_camera.global_transform, reference_before) < 0.0001, "内部墙夹具恢复玩家相机与手持姿态且正式参考相机保持原值")
	if not slot.is_open():
		await _click(_pixel(2))
		await frames(15)
	var point: Vector2 = _pixel(2, true)
	var origin: Vector3 = player.camera.project_ray_origin(point)
	var direction: Vector3 = player.camera.project_ray_normal(point)
	var outer: StaticBody3D = box(Vector3(0.22, 0.22, 0.04), origin + direction * 0.35)
	outer.look_at(outer.global_position + direction)
	await frames(3)
	check(_query(point) == null, "聚焦射线不能穿透设备外独立墙")
	var count_before: int = _item_count()
	await _click(point)
	check(_item_count() == count_before and slot.get_stored_item() != null, "被墙遮挡的真实点击不转移药品")
	outer.queue_free()
	await frames(3)
	var other_transform: Transform3D = other_machine.global_transform
	# 将另一台正式设备根放在当前指针前方，保留其真实外盒与内部对象。
	other_machine.global_position = origin + direction * 0.5 - Vector3(0, 0.3, 0.075)
	await frames(3)
	check(_query(point) == null, "其他设备根仍然遮挡当前设备射线")
	await _click(point)
	var other_unchanged: bool = true
	for other_slot: Node3D in other_machine.slots:
		other_unchanged = other_unchanged and other_slot.state == 0
	check(other_unchanged and _item_count() == count_before, "点击其他设备覆盖区域不跨设备开槽或转移")
	other_machine.global_transform = other_transform
	await frames(3)
	var saved_slot: Transform3D = machine.slots[0].global_transform
	machine.slots[0].global_position = origin + direction * 0.7
	await frames(3)
	check(_query(point) != slot.raw_material_anchor, "另一槽体挡在前方时不继续穿透寻找后方取放区")
	machine.slots[0].global_transform = saved_slot
	await frames(3)


func _test_internal_wall_obstruction(slot_index: int) -> void:
	var slot: Node3D = machine.slots[slot_index]
	var point: Vector2 = Vector2(root.size) * 0.5
	var held_rectangle: Rect2 = _held_projection_rectangle()
	check(not held_rectangle.has_point(point), "内部墙夹具中央像素位于手持投影之外")
	var origin: Vector3 = player.camera.project_ray_origin(point)
	var direction: Vector3 = player.camera.project_ray_normal(point)
	var exclusions: Array[RID] = _exclusions()
	exclusions.append(machine.get_rid())
	var first_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * RAY_SCRIPT.MAX_DISTANCE, RAY_SCRIPT.COLLISION_MASK, exclusions)
	first_query.hit_from_inside = true
	var first: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(first_query)
	check(first.get("collider") == slot, "实际物理首命中为包含取放区域的槽大盒")
	exclusions.append(slot.get_rid())
	var second_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * RAY_SCRIPT.MAX_DISTANCE, RAY_SCRIPT.COLLISION_MASK, exclusions)
	second_query.hit_from_inside = true
	var second: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(second_query)
	check(second.get("collider") == slot.raw_material_anchor and _query(point) == slot.raw_material_anchor, "只排除本槽后第二次首命中正确解析取放区域")
	if first.has("position") and second.has("position"):
		var gap: float = (second.position - first.position).dot(direction)
		var observation: Dictionary = {"用途": "槽大盒内部独立墙临时侧视夹具", "槽位": slot_index, "像素": str(point), "首命中位置": str(first.position), "第二次命中位置": str(second.position), "正向间距": gap, "射线长度": RAY_SCRIPT.MAX_DISTANCE, "手持投影包围矩形": str(held_rectangle), "点击位于手持投影外": not held_rectangle.has_point(point)}
		ray_records.append(observation)
		print("内部遮挡射线观测：", JSON.stringify(observation))
		check(gap > 0.002, "两层盒体实际命中之间存在可插入独立墙的空间")
		if gap <= 0.002:
			return
		var blocker: StaticBody3D = box(Vector3(0.16, 0.16, minf(0.005, gap * 0.2)), first.position.lerp(second.position, 0.5))
		blocker.look_at(blocker.global_position + direction)
		await frames(3)
		var existing: Node3D = slot.get_stored_item()
		check(_query(point) == slot, "槽大盒内独立墙阻断第二次查询并返回开闭区")
		await _click(point)
		check(inventory.get_focused_item() == null and slot.get_stored_item() == existing, "真实点击不能取到槽大盒内独立墙后的原药")
		blocker.queue_free()
		await frames(16)


func _test_gui_consumption() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 100
	world.add_child(canvas)
	var consumer: ClickConsumer = ClickConsumer.new()
	consumer.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(consumer)
	consumer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(3)
	var slot: Node3D = machine.slots[0]
	var before: int = slot.state
	await _click(_pixel(0))
	await _click(cursor, MOUSE_BUTTON_RIGHT)
	check(consumer.consumed == 2 and focus.state == FOCUSED and slot.state == before, "界面消费左右键后世界开闭与退出入口均不执行")
	canvas.queue_free()
	await frames(3)
	await _exit()


func _test_cancellation() -> void:
	for iteration: int in range(3):
		await _start_entry()
		await frames(3)
		var cancellation_start: Transform3D = player.camera.global_transform
		await _click(cursor, MOUSE_BUTTON_RIGHT)
		check(focus.state == EXITING and player.camera.global_position.distance_to(camera_start.origin) > 0.0001, "进入中右键从当前相机姿态开始返回")
		var session: int = focus.session_id
		await _click(cursor, MOUSE_BUTTON_RIGHT)
		check(focus.state == EXITING and focus.session_id == session, "退出中重复右键不重建会话或重启返回")
		check(cancellation_start.origin.distance_to(camera_start.origin) > 0.0001, "取消测试真实经历进入中间姿态")
		await frames(15)
		_assert_restored("连续进出第%d次" % iteration)


func _test_queued_inputs() -> void:
	await _new_scene()
	await _enter()
	var point: Vector2 = _pixel(0)
	var slot: Node3D = machine.slots[0]
	var selected: int = inventory.get_focused_index()
	var frame_before: int = Engine.get_physics_frames()
	_move_cursor(point)
	_button(MOUSE_BUTTON_LEFT, true, point)
	_button(MOUSE_BUTTON_LEFT, false, point)
	_button(MOUSE_BUTTON_WHEEL_DOWN, true, point)
	_button(MOUSE_BUTTON_WHEEL_DOWN, false, point)
	_button(MOUSE_BUTTON_WHEEL_UP, true, point)
	_button(MOUSE_BUTTON_WHEEL_UP, false, point)
	check(Engine.get_physics_frames() == frame_before and inventory.get_focused_index() == selected, "同一物理帧先排队左键再滚轮离开并回到原格")
	await frames(3)
	check(slot.state == 0, "同帧切格往返作废先前待处理点击而不误开槽")
	frame_before = Engine.get_physics_frames()
	_button(MOUSE_BUTTON_LEFT, true, point)
	_button(MOUSE_BUTTON_LEFT, false, point)
	_action(&"menu", true)
	_action(&"menu", false)
	_action(&"menu", true)
	_action(&"menu", false)
	check(Engine.get_physics_frames() == frame_before and not player.is_movement_paused, "同一物理帧先排队左键再打开并关闭菜单")
	await frames(3)
	check(slot.state == 0 and focus.state == FOCUSED, "同帧菜单往返清空待处理点击并保留原会话")
	await _click(point)
	await frames(15)
	check(slot.is_open(), "待处理点击作废后仍能接受新的真实左键")
	await _exit()


func _prepare_stage(stage: int) -> void:
	await _start_entry()
	if stage == FOCUSED or stage == EXITING:
		await frames(15)
	if stage == EXITING:
		await _click(cursor, MOUSE_BUTTON_RIGHT)
	check(focus.state == stage, "异常检查到达指定聚焦阶段%d" % stage)


func _test_alternate_camera_snapshots() -> void:
	for offset: float in [-0.15, 0.2]:
		player.position.x = offset
		player.camera.position = Vector3(0.025, 0.015, 0.02)
		player.camera.fov = 63.0 + offset * 10.0
		player.camera.near = 0.08
		player.camera.far = 850.0
		player.camera.size = 1.7
		player.camera.h_offset = 0.01
		player.camera.v_offset = -0.01
		await _enter()
		var camera: Camera3D = machine.get_node("focus_camera")
		var matched: bool = true
		for property: StringName in [&"projection", &"keep_aspect", &"fov", &"size", &"near", &"far", &"h_offset", &"v_offset", &"frustum_offset"]:
			matched = matched and player.camera.get(property) == camera.get(property)
		check(matched, "不同初始视角进入后全部投影参数匹配参考相机")
		await _exit()
		_assert_restored("不同初始视角")


func _test_camera_animation_resume() -> void:
	for speed: float in [0.4, -0.4]:
		await _new_scene()
		await _aim_root()
		var animation: AnimationPlayer = player.animationPlayer
		animation.play(&"jump", -1.0, speed, speed < 0.0)
		animation.seek(0.15, true)
		check(animation.is_playing() and abs(animation.get_playing_speed() - speed) < 0.0001, "镜头动画夹具进入前确实沿指定正倒放方向播放")
		_snapshot()
		var saved_progress: float = animation.current_animation_position
		var observation: Dictionary = {"请求播放速度": speed, "进入前进度": saved_progress, "进入前速度": animation.get_playing_speed(), "进入前相机旋转": str(player.camera.rotation)}
		if graphical:
			_button(MOUSE_BUTTON_LEFT, true, Vector2(root.size) * 0.5)
		else:
			focus.try_enter(machine.focus_target)
		_button(MOUSE_BUTTON_LEFT, false, Vector2(root.size) * 0.5)
		await frames(15)
		observation["聚焦状态"] = focus.state
		observation["聚焦中动画进度"] = animation.current_animation_position
		observation["聚焦中动画激活"] = animation.active
		check(focus.state == FOCUSED and not animation.active and abs(animation.current_animation_position - saved_progress) < 0.0001, "聚焦暂停原镜头动画并保留正放或倒放进度")
		animation_restore_observation.clear()
		focus.state_changed.connect(_observe_animation_restore)
		await _exit()
		focus.state_changed.disconnect(_observe_animation_restore)
		observation["归还控制瞬间"] = animation_restore_observation.duplicate()
		check(not animation_restore_observation.is_empty() and animation_restore_observation.get("播放中", false) and animation_restore_observation.get("激活", false) and abs(float(animation_restore_observation.get("进度", -1.0)) - saved_progress) < 0.0001 and abs(float(animation_restore_observation.get("速度", 0.0)) - speed) < 0.0001, "归还控制瞬间镜头动画恢复原进度、播放状态与正倒放速度")
		var resumed: float = animation.current_animation_position
		observation["退出等待后进度"] = resumed
		observation["退出等待后速度"] = animation.get_playing_speed()
		await frames(2)
		observation["随后两帧进度"] = animation.current_animation_position
		observation["随后两帧速度"] = animation.get_playing_speed()
		animation_records.append(observation)
		print("镜头动画恢复观测：", JSON.stringify(observation))
		check((animation.current_animation_position - resumed) * speed > 0.0, "恢复后原镜头动画沿原播放方向继续推进")
	await _new_scene()


func _observe_animation_restore() -> void:
	if focus.state == INACTIVE:
		animation_restore_observation = {"播放中": player.animationPlayer.is_playing(), "激活": player.animationPlayer.active, "进度": player.animationPlayer.current_animation_position, "速度": player.animationPlayer.get_playing_speed()}


func _test_menu_and_pause() -> void:
	for menu: bool in [true, false]:
		for stage: int in [ENTERING, FOCUSED, EXITING]:
			await _prepare_stage(stage)
			var animated_slot: Node3D = machine.slots[0]
			if stage == FOCUSED:
				await _click(_pixel(0))
				check(animated_slot.is_animating(), "暂停检查前通过真实点击启动槽位动画")
			if menu:
				_action(&"menu", true)
				_action(&"menu", false)
			else:
				paused = true
			await frames(1)
			var pose: Transform3D = player.camera.global_transform
			var slot_pose: Transform3D = animated_slot.transform
			var state_before: int = focus.state
			var selected: int = inventory.get_focused_index()
			await _click(cursor)
			await _click(cursor, MOUSE_BUTTON_RIGHT)
			await _wheel()
			await frames(5)
			check(_transform_error(player.camera.global_transform, pose) < 0.0001 and focus.state == state_before and inventory.get_focused_index() == selected, "菜单或全局暂停在阶段%d冻结相机并拦截左右键及滚轮：%s" % [stage, "菜单" if menu else "全局暂停"])
			if stage == FOCUSED:
				check(_transform_error(animated_slot.transform, slot_pose) > 0.0001 if menu else _transform_error(animated_slot.transform, slot_pose) < 0.0001, "菜单允许既有槽位动画继续而全局暂停冻结槽位动画")
			if menu:
				_action(&"menu", true)
				_action(&"menu", false)
			else:
				paused = false
			await frames(16)
			check(focus.state == (INACTIVE if stage == EXITING else FOCUSED) and inventory.get_focused_index() == selected, "恢复后继续原会话且不补播暂停期间点击")
			if focus.state == FOCUSED:
				check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "菜单或暂停恢复稳定聚焦时鼠标保持可见")
				await _exit()


func _test_dependency_release() -> void:
	for released: String in ["设备", "参考相机", "玩家"]:
		for stage: int in [ENTERING, FOCUSED, EXITING]:
			await _new_scene()
			await _prepare_stage(stage)
			if released == "设备":
				machine.queue_free()
			elif released == "参考相机":
				machine.get_node("focus_camera").queue_free()
			else:
				player.queue_free()
			await frames(3)
			if released == "玩家":
				check(not is_instance_valid(player), "阶段%d释放玩家完成且不访问已释放子节点" % stage)
			else:
				_assert_restored("阶段%d释放%s" % [stage, released])


func _test_local_dependency_isolation() -> void:
	await _new_scene()
	await _obtain_source_items()
	await _enter()
	var session: int = focus.session_id
	var before_count: int = _item_count()
	var unavailable: AutolysisBlendSlot = machine.slots[0]
	var available_slot: AutolysisBlendSlot = machine.slots[1]
	var local_player: AnimationPlayer = unavailable._runtime_player
	local_player.queue_free()
	await frames(3)
	check(machine.focus_target.is_valid_target() and focus.state == FOCUSED and focus.session_id == session, "一个槽门的必要播放器失效不撤销设备核心登记或聚焦会话")
	check(not unavailable.toggle_interaction.can_interact(player) and not unavailable.transfer_interaction.can_interact(player), "局部播放器失效只拒绝依赖该门的开闭和取放")
	await _click(_pixel(0))
	await _click(_pixel(1))
	for wait_index: int in range(180):
		if available_slot.is_open():
			break
		await frames(1)
	check(available_slot.is_open() and not unavailable.is_open() and focus.state == FOCUSED, "局部门失效后真实鼠标仍能打开另一个登记槽门")
	check(_item_count() == before_count, "局部运动依赖失效与邻门操作保持原药来源数量")
	await _exit()
	_assert_restored("局部门依赖失效后退出")


func _test_main_scene() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(2)
	world = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate()
	root.add_child(world)
	await frames(45)
	var machines: Array[Node] = world.find_children("machine_blend*", "", true, false)
	check(machines.size() > 0, "正式主场景继续实例化真实混合器")
	player = world.get_node("autolysis_player")
	check(player.camera.current and player.is_on_floor(), "正式主场景玩家着地并保持正常相机")
	await _capture("06-main-scene.png")
	if machines.is_empty():
		return
	machine = machines[0]
	focus = player.focus_controller
	inventory = player.inventory_controller
	if not graphical:
		focus.configure(player, player.camera, player.held_item_presenter, _headless_entry_allowed)
	player.global_position = machine.to_global(Vector3(0, -0.1, 1.65))
	player.velocity = Vector3.ZERO
	player.main_velocity = Vector3.ZERO
	await frames(25)
	await _enter()
	await _capture("07-main-focused.png")
	for slot_index: int in range(4):
		await _click(_pixel(slot_index))
	await frames(15)
	var all_open: bool = true
	for slot: Node3D in machine.slots:
		all_open = all_open and slot.is_open()
	check(all_open, "正式主场景实际聚焦后四槽分别响应鼠标指针点击")
	await _capture("08-main-four-open.png")
	await _exit()
	_assert_restored("正式主场景退出")
	await _capture("09-main-restored.png")


func _capture(filename: String) -> void:
	if not graphical:
		return
	await RenderingServer.frame_post_draw
	var output: String = evidence_directory.path_join(filename)
	var result: Error = root.get_texture().get_image().save_png(output)
	check(result == OK, "保存实际图形画面")
	if result == OK:
		screenshots.append(output)


func _transform_error(left: Transform3D, right: Transform3D) -> float:
	return maxf(left.origin.distance_to(right.origin), maxf(left.basis.x.distance_to(right.basis.x), maxf(left.basis.y.distance_to(right.basis.y), left.basis.z.distance_to(right.basis.z))))


func _save_report() -> void:
	var report: Dictionary = {"图形运行": graphical, "断言数": assertion_count, "断言": records, "失败数": failures, "相机逐帧采样": camera_samples, "镜头动画恢复观测": animation_records, "实际射线像素": ray_records, "截图": screenshots}
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("focus-interaction-report.json"), FileAccess.WRITE)
	if file == null:
		check(false, "聚焦验收报告可以写入指定本轮目录")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
