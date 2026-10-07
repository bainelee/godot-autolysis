extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 真实图形后端、实际输入和实际预制体的集成验收。

var EVIDENCE: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/道具系统p1实施证据/checks")
const RAW_DIR: String = "res://main-autolysis/scenes/prefabs/prefab_raw_materials/"
const SHELF_PATH: String = "res://main-autolysis/scenes/prefabs/prefab_place_shelf/place_shelf_workroom_rm_0.tscn"
var inventory: AutolysisInventoryController
var bar: AutolysisInventoryBar
var shelf: AutolysisRawMaterialShelf
var caffeine_group: AutolysisRawMaterialGroup
var sodium_group: AutolysisRawMaterialGroup
var _layout_records: Array[Dictionary] = []
var _aim_records: Array[Dictionary] = []


func run_checks() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("本检查必须使用真实图形后端。")
		quit(1)
		return
	Input.use_accumulated_input = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	root.size = Vector2i(1920, 1080)
	if OS.get_cmdline_user_args().has("--main-only"):
		await _test_main_scene()
		_save_aim_records("rendered-main-rays.json")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		quit(1 if failures else 0)
		return
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(30, 1, 30), Vector3(0, -0.5, 0))
	_add_lighting(world)
	player = load("res://main-autolysis/player/autolysis_player.tscn").instantiate()
	world.add_child(player)
	await reset_player()
	inventory = player.get_node("InventoryController") as AutolysisInventoryController
	bar = player.get_node("InventoryBar") as AutolysisInventoryBar
	check(bar.visible and not player.is_showing_ui and not player.is_movement_paused, "初始四格常显不占用游戏输入")
	_measure_layout()
	await _capture("initial-empty.png")
	await _test_wheel_and_gates()
	await check_shelf_physics()
	await reset_player()
	await _test_world_cycle()
	await _test_persistent_visibility()
	await _test_main_scene()
	var report: FileAccess = FileAccess.open(EVIDENCE + "/layout.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_layout_records, "\t"))
	report.close()
	_save_aim_records("rendered-rays.json")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("实际图形道具系统失败总数：", failures)
	quit(1 if failures else 0)


func _add_lighting(parent: Node3D) -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.13, 0.16)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	parent.add_child(holder)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	parent.add_child(light)


func _button(button: MouseButton, pressed: bool = true) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT and pressed else 0
	event.position = Vector2(root.size) / 2.0
	event.global_position = event.position
	Input.parse_input_event(event)
	await frames(2)


func _click() -> void:
	await _button(MOUSE_BUTTON_LEFT)
	await _button(MOUSE_BUTTON_LEFT, false)
	_trace_aim("点击后状态")


func _aim_at(point: Vector3) -> void:
	player.body.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.head.look_at(point, Vector3.UP)
	await frames(4)


func _test_wheel_and_gates() -> void:
	await _button(MOUSE_BUTTON_WHEEL_UP)
	check(inventory.get_focused_index() == 3 and bar.is_slot_highlighted(3), "第一格向上循环到第四格并更新高亮")
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	check(inventory.get_focused_index() == 0, "第四格向下循环到第一格")
	await _button(MOUSE_BUTTON_WHEEL_DOWN, false)
	check(inventory.get_focused_index() == 0, "滚轮释放事件不重复切换")
	for gate: String in ["is_movement_paused", "is_showing_ui", "is_landing_stunned"]:
		player.set(gate, true)
		if gate == "is_landing_stunned":
			player.stun_time_left = 10.0
			player.stun_time_total = 10.0
		await _button(MOUSE_BUTTON_WHEEL_DOWN)
		check(inventory.get_focused_index() == 0 and bar.visible, "输入限制时道具栏继续可见且不切换：" + gate)
		player.set(gate, false)
	player._clear_landing_stun()
	paused = true
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	check(inventory.get_focused_index() == 0 and bar.visible, "暂停不切格也不隐藏道具栏")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	check(inventory.get_focused_index() == 0, "鼠标未捕获时不切格")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await frames(3)
	check(inventory.get_focused_index() == 0, "恢复输入后不补执行旧滚轮事件")
	var initial_location: Vector3 = player.position
	Input.action_press("right")
	await frames(8)
	Input.action_release("right")
	check(player.position.x > initial_location.x and bar.visible, "道具栏常显期间玩家正常移动")
	await reset_player()


func _test_world_cycle() -> void:
	caffeine_group = load(RAW_DIR + "rm_caffeine_group_0.tscn").instantiate()
	world.add_child(caffeine_group)
	caffeine_group.position = Vector3(0, 1.0, -1.1)
	await _aim_at(caffeine_group.global_position + Vector3(0, 0.1, 0))
	check(player.interaction_controller.is_direct_available(), "空手瞄准实际原药组显示交互准星")
	await _click()
	check(inventory.get_focused_item() != null and inventory.get_focused_item().item_id == &"caffeine", "实际左键从组取得咖啡因")
	check(player.held_item_presenter.get_display() != null and not player.interaction_controller.is_direct_available(), "取药后手持显示与交互准星同步")
	await _click()
	check(inventory.get_slot_item(1) == null, "当前格有药时点击不会塞入其他空格")
	await _capture("held-caffeine.png")
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	check(inventory.get_focused_item() == null and player.held_item_presenter.get_display() == null, "切空格后空手且原药保留原格")
	check(player.interaction_controller.is_direct_available(), "原地切空格后准星重新可用")
	caffeine_group.position.x = -5.0
	sodium_group = load(RAW_DIR + "rm_sodium_benzoate_group_0.tscn").instantiate()
	world.add_child(sodium_group)
	sodium_group.position = Vector3(0, 1.0, -1.1)
	await _aim_at(sodium_group.global_position + Vector3(0, 0.1, 0))
	await _click()
	check(inventory.get_focused_item() != null and inventory.get_focused_item().item_id == &"sodium_benzoate", "第二格通过实际点击获得苯甲酸钠")
	await _capture("held-sodium.png")
	sodium_group.position.x = 5.0
	shelf = load(SHELF_PATH).instantiate()
	world.add_child(shelf)
	shelf.position = Vector3(0, 0.72, -1.2)
	await _aim_at(shelf.to_global(Vector3(0.55, 0.02, -0.2)))
	check(player.interaction_controller.is_direct_available(), "手持原药瞄准架体可放置")
	await _click()
	check(inventory.get_focused_item() == null and shelf.get_item_at_slot(0) != null, "实际点击放入编号最小空槽并清空当前格")
	check(player.interaction_raycast.collision_mask == 3 and shelf.get_item_at_slot(1) == null, "放置后切换空手查询且一次点击未重复转移")
	await _button(MOUSE_BUTTON_WHEEL_UP)
	await _aim_at(shelf.to_global(Vector3(0.55, 0.02, -0.2)))
	await _click()
	check(shelf.get_item_at_slot(1) != null and inventory.get_focused_item() == null, "第二种原药混放到编号一槽位")
	var selected: AutolysisRawMaterial = shelf.get_item_at_slot(1)
	if selected != null:
		await _aim_at(selected.global_position + Vector3(0, 0.09, 0))
		check(player.interaction_raycast.get_collider() == selected and player.interaction_raycast.collision_mask == 3, "空手在重叠架体内实际瞄准指定瓶体")
		await _click()
		check(inventory.get_focused_item() != null and inventory.get_focused_item().item_id == &"caffeine" and shelf.get_item_at_slot(1) == null, "瞄准指定瓶体只取回对应原药")
		check(player.interaction_raycast.collision_mask == 19 and player.interaction_raycast.get_collider() == shelf, "同一瞄准方向拾取后立即切换为架体入口")
		await _button(MOUSE_BUTTON_WHEEL_DOWN)
		check(player.interaction_raycast.collision_mask == 3, "真实滚轮切空格后立即排除架体")
		await _button(MOUSE_BUTTON_WHEEL_UP)
		check(player.interaction_raycast.collision_mask == 19 and player.interaction_controller.is_direct_available(), "真实滚轮切回有药格恢复放置准星")
	check(shelf.get_item_at_slot(0) != null, "取回另一件原药不影响原槽零的苯甲酸钠")
	await _capture("mixed-shelf.png")
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	check(inventory.get_focused_item() == null, "常显静置检查使用空手状态")


func _test_persistent_visibility() -> void:
	# 观察真实时间，不能用加速物理帧替代持续可见验收。
	var deadline: int = Time.get_ticks_msec() + 60000
	var remained_visible: bool = true
	while Time.get_ticks_msec() < deadline:
		await process_frame
		remained_visible = remained_visible and bar.visible and bar.get_node("Bar").is_visible_in_tree()
	check(remained_visible, "正常游戏静置六十秒道具栏持续可见")
	await _capture("persistent-after-60s.png")
	root.size = Vector2i(1280, 720)
	await frames(6)
	_measure_layout()
	root.size = Vector2i(1920, 1080)
	await frames(6)


func _measure_layout() -> void:
	var rectangle: Rect2 = bar.get_bar_rect()
	var expected: Rect2 = Rect2(Vector2(root.size.x * 0.5 - 175, root.size.y - 160), Vector2(350, 80))
	check(rectangle.is_equal_approx(expected), "道具栏几何、居中和底距符合当前窗口：" + str(root.size))
	for index: int in range(4):
		var slot_rect: Rect2 = bar.get_slot_rect(index)
		check(slot_rect.size.is_equal_approx(Vector2(80, 80)) and is_equal_approx(slot_rect.position.x, rectangle.position.x + index * 90), "道具格尺寸与间距：" + str(index + 1))
	_layout_records.append({"窗口": str(root.size), "实际范围": str(rectangle), "预期范围": str(expected)})


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var captured: Image = root.get_texture().get_image()
	check(captured.save_png(EVIDENCE + "/" + file_name) == OK, "保存实际渲染图像：" + file_name)


func _test_main_scene() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	world = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate()
	root.add_child(world)
	await frames(8)
	player = world.find_child("autolysis_player", true, false) as AutolysisPlayer
	if player == null:
		for node: Node in get_nodes_in_group(&"Player"):
			if node is AutolysisPlayer:
				player = node
	check(player != null, "实际主场景加载玩家")
	if player == null:
		return
	inventory = player.inventory_controller
	bar = player.inventory_bar
	# 保留真实场景、射线和输入；定点布置玩家以使检查不依赖导航路径。
	player.set_physics_process(false)
	for group_name: String in ["rm_caffeine_group_0", "rm_sodium_benzoate_group_0"]:
		var group: AutolysisRawMaterialGroup = world.get_node("interaction_prefabs/item_groups/" + group_name)
		# 从仓库架开放正面接近，玩家位于架外；不绕过实体遮挡。
		player.global_position = group.global_position + Vector3(1.0, 0, 0)
		await _aim_at(group.global_position + Vector3(0, 0.1, 0))
		_trace_aim("主场景取药：" + group_name)
		await _click()
		check(inventory.get_focused_item() == group.item_definition, "实际主场景原有原药组经左键成功取药：" + group_name)
		if group_name == "rm_caffeine_group_0":
			await _button(MOUSE_BUTTON_WHEEL_DOWN)
	await _capture("main-scene-group.png")
	for shelf_name: String in ["place_shelf_workroom_rm_0", "place_shelf_workroom_rm_1"]:
		var actual_shelf: AutolysisRawMaterialShelf = world.get_node("interaction_prefabs/item_groups/" + shelf_name)
		var expected_item: AutolysisItemDefinition = inventory.get_focused_item()
		player.global_position = actual_shelf.to_global(Vector3(0, 0, -1.0))
		await _aim_at(actual_shelf.to_global(Vector3(0.55, 0.02, -0.2)))
		await _click()
		check(actual_shelf.get_item_at_slot(0) != null and inventory.get_focused_item() == null, "实际主场景架子接受放置：" + shelf_name)
		var item: AutolysisRawMaterial = actual_shelf.get_item_at_slot(0)
		if item != null:
			check(item.item_definition == expected_item, "实际主场景放入原药种类与当前格一致")
			await _aim_at(item.global_position + Vector3(0, 0.09, 0))
			await _click()
			check(inventory.get_focused_item() == expected_item and actual_shelf.get_item_at_slot(0) == null, "实际主场景架子指定瓶体取回：" + shelf_name)
		if shelf_name == "place_shelf_workroom_rm_0":
			await _button(MOUSE_BUTTON_WHEEL_UP)
	await _capture("main-scene-cycle.png")


func _save_aim_records(file_name: String) -> void:
	var report: FileAccess = FileAccess.open(EVIDENCE.path_join(file_name), FileAccess.WRITE)
	check(report != null, "保存实际图形命中和手持状态记录")
	if report != null:
		report.store_string(JSON.stringify(_aim_records, "\t"))
		report.close()


func _trace_aim(label: String) -> void:
	var detector: InteractionRayCast = player.interaction_controller._detector
	detector.force_raycast_update()
	var hit: Object = detector.get_collider()
	var held: AutolysisItemDefinition = inventory.get_focused_item()
	_aim_records.append({"阶段": label, "当前格": inventory.get_focused_index(), "手持": held.display_name if held else "空手", "掩码": detector.collision_mask, "起点": str(detector.global_position), "命中": str(hit.get_path()) if hit is Node else "无命中", "碰撞点": str(detector.get_collision_point()) if hit else "无命中", "交互许可": player.interaction_controller.is_direct_available()})
	if hit is Node3D:
		print("命中场景=", hit.scene_file_path, "；世界变换=", hit.global_transform)
		for child: Node in hit.get_children():
			if child is CollisionShape3D:
				print("碰撞形状=", child.name, "；世界变换=", child.global_transform,
					"；局部变换=", child.transform, "；尺寸=", child.shape.size if child.shape is BoxShape3D else str(child.shape))
	print(label, "：相机位置=", player.camera.global_position,
		"；射线位置=", detector.global_position,
		"；首个碰撞=", hit.get_path() if hit is Node else str(hit),
		"；碰撞位置=", detector.get_collision_point(),
		"；交互许可=", player.interaction_controller.is_direct_available(),
		"；鼠标模式=", Input.mouse_mode,
		"；输入标记=", [player.is_movement_paused, player.is_showing_ui, player.is_landing_stunned])
