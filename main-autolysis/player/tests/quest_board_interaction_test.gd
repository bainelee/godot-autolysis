extends SceneTree
## 正式任务板、正式玩家与主场景的无图形交互验收；不定位系统指针。

const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
const BOARD_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/quest_board_0.tscn")
const MAIN_SCENE: PackedScene = preload("res://main-autolysis/scenes/01-autolysis-test.tscn")
const PAPER: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/quest_paper.tres")
const FIRST_TASK: AutolysisQuestPrintDefinition = preload("res://main-autolysis/systems/quest-print-system/quests/quest_test_0.tres")
const INVALID_PIXEL: Vector2 = Vector2(-10000.0, -10000.0)

var world: Node3D
var player: AutolysisPlayer
var board: AutolysisQuestBoard
var inventory: AutolysisInventoryController
var query: AutolysisFocusRayQuery = AutolysisFocusRayQuery.new()
var failures: int = 0
var records: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var original_accumulation: bool = true
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/任务板实施证据/20261007/checks/interaction")


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
	records.append({"说明": description, "通过": condition})
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1


func frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("任务板交互专项禁止启动图形后端。")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	await _fixture()
	await _entry_and_session()
	await _ray_and_display()
	await _queued_clicks()
	await _local_dependencies()
	await _main_scene()
	paused = false
	Input.use_accumulated_input = original_accumulation
	if is_instance_valid(world):
		world.queue_free()
	await frames(3)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("任务板交互断言.json"), FileAccess.WRITE)
	if report == null:
		check(false, "任务板交互报告可写入本轮证据目录")
	else:
		report.store_string(JSON.stringify({"失败数": failures, "断言数": records.size(), "记录": records, "测量": measurements, "输入方式": "无图形后端引擎内部输入；普通入口仅替换捕获鼠标许可；未执行图形或原生指针"}, "\t"))
		report.close()
	print("任务板交互专项断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)


func _ordinary_input_allowed() -> bool:
	# 无图形后端不实现捕获鼠标；其余正式玩家门控保持原样。
	return player._base_input_allowed() and not player.focus_controller.has_control()


func _fixture(main_scene: bool = false) -> void:
	paused = false
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	if main_scene:
		world = MAIN_SCENE.instantiate()
		root.add_child(world)
		player = world.get_node("autolysis_player") as AutolysisPlayer
		board = world.get_node("interaction_prefabs/machines/quest_board_0") as AutolysisQuestBoard
	else:
		world = Node3D.new()
		root.add_child(world)
		player = PLAYER_SCENE.instantiate() as AutolysisPlayer
		world.add_child(player)
		board = BOARD_SCENE.instantiate() as AutolysisQuestBoard
		board.position = Vector3(2.0, 0.5, -1.0)
		board.rotation.y = 0.23
		world.add_child(board)
	player.set_physics_process(false)
	player._clear_landing_stun()
	inventory = player.inventory_controller
	player.focus_controller.configure(player, player.camera, player.held_item_presenter, _ordinary_input_allowed)
	player.interaction_controller.configure(player, player.interaction_raycast, _ordinary_input_allowed, inventory, player.focus_controller)
	await frames(3)
	check(board.is_configured() and board.focus_target.is_valid_target(), "正式任务板核心引用与明确槽登记有效")
	check(board.slots.size() == 3, "当前任务板配置三个独立槽入口")


func _button(button: MouseButton, pressed: bool, point: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT and pressed else 0
	event.pressed = pressed
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(button, true, point)
	await frames(1)
	_button(button, false, point)
	await frames(1)


func _aim_board() -> void:
	var collision: CollisionShape3D = board.get_node("collision_board") as CollisionShape3D
	player.global_position = board.to_global(Vector3(0.0, -1.0, 1.2))
	player.camera.global_transform = board.reference_camera.global_transform
	player.camera.look_at(collision.global_position, Vector3.UP)
	await frames(2)
	check(player.interaction_raycast.refresh_target() == board, "普通中心射线首命中实际板面根体")


func _enter() -> void:
	await _aim_board()
	await _click(Vector2(root.size) * 0.5)
	check(player.focus_controller.state == AutolysisFocusController.FocusState.ENTERING, "板面鼠标输入经正式分发建立进入过渡")
	await frames(25)
	check(player.focus_controller.is_focused_on(board.focus_target), "任务板正式聚焦过渡完成")


func _pixel(slot: AutolysisQuestBoardSlot) -> Vector2:
	var center: Vector2 = player.camera.unproject_position(slot.global_position)
	var exclusions: Array[RID] = [player.get_rid(), player._found_area.get_rid()]
	for radius: int in [0, 2, 6, 12, 24]:
		for x: int in range(-radius, radius + 1, 2):
			for y: int in range(-radius, radius + 1, 2):
				var point: Vector2 = center + Vector2(x, y)
				if query.query_target(player.camera, point, board.focus_target, exclusions) == slot:
					measurements.append({"类型": "正式槽射线", "槽路径": str(slot.get_path()), "像素": point, "相机变换": player.camera.global_transform, "槽变换": slot.global_transform})
					return point
	return INVALID_PIXEL


func _instance() -> AutolysisItemInstance:
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(PAPER)
	instance.set_quest_paper_contents(FIRST_TASK.create_contents())
	return instance


func _entry_and_session() -> void:
	var instance: AutolysisItemInstance = _instance()
	# 普通状态接收夹具不需要捕获鼠标；取放许可仍由正式聚焦状态决定。
	inventory.configure(player.held_item_presenter, player._base_input_allowed)
	check(inventory.try_receive_instance(instance), "正式库存接收测试任务文件")
	check(not inventory.can_place_in_quest_board_slot(player, board.slots[0]), "未聚焦本板时拒绝直接放置")
	await _aim_board()
	_button(MOUSE_BUTTON_LEFT, true, Vector2(root.size) * 0.5)
	await frames(1)
	_button(MOUSE_BUTTON_LEFT, false, Vector2(root.size) * 0.5)
	check(player.focus_controller.state == AutolysisFocusController.FocusState.ENTERING, "普通板面入口进入本板会话")
	check(not inventory.can_place_in_quest_board_slot(player, board.slots[0]) and not inventory.try_place_in_quest_board_slot(player, board.slots[0]), "进入过渡拒绝槽取放且保留原来源")
	await frames(25)
	check(player.focus_controller.is_focused_on(board.focus_target), "正式会话完成后开放本板槽入口")
	check(player.camera.global_transform.is_equal_approx(board.reference_camera.global_transform) and is_equal_approx(player.camera.fov, board.reference_camera.fov), "玩家相机到达作者参照相机完整变换与视场")
	player.is_movement_paused = true
	check(not inventory.can_place_in_quest_board_slot(player, board.slots[0]) and not inventory.try_place_in_quest_board_slot(player, board.slots[0]), "菜单暂停拒绝槽取放")
	player.is_movement_paused = false
	paused = true
	check(not inventory.can_place_in_quest_board_slot(player, board.slots[0]), "场景树暂停拒绝槽取放")
	paused = false
	var point: Vector2 = _pixel(board.slots[0])
	check(point != INVALID_PIXEL, "聚焦相机实际射线可达零号空槽")
	if point != INVALID_PIXEL:
		await _click(point)
	check(board.slots[0].get_stored_instance() == instance and inventory.get_focused_instance() == null, "正式左键将原实例仅放入命中零号槽")
	await _click(point, MOUSE_BUTTON_RIGHT)
	await frames(25)
	check(not player.focus_controller.has_control() and board.slots[0].get_stored_instance() == instance, "正式右键退出保留板上原文件")
	await _enter()
	player.is_movement_paused = true
	await frames(2)
	player.is_movement_paused = false
	await frames(2)
	check(player.focus_controller.is_focused_on(board.focus_target) and board.slots[0].get_stored_instance() == instance, "暂停与恢复保持本板稳定聚焦和占用")
	await _click(_pixel(board.slots[0]))
	check(inventory.get_focused_instance() == instance and board.slots[0].get_stored_instance() == null, "重新聚焦后正式入口取回同一实例")


func _raw_ray(point: Vector2, mask: int, excluded: Array[RID]) -> Dictionary:
	var origin: Vector3 = player.camera.project_ray_origin(point)
	var parameters: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + player.camera.project_ray_normal(point) * 2.0, mask, excluded)
	parameters.hit_from_inside = true
	parameters.collide_with_areas = false
	return world.get_world_3d().direct_space_state.intersect_ray(parameters)


func _blocker(point: Vector2, layer: int = 1) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.08, 0.08, 0.025)
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	var origin: Vector3 = player.camera.project_ray_origin(point)
	body.global_position = origin + player.camera.project_ray_normal(point) * 0.35
	return body


func _ray_and_display() -> void:
	for index: int in board.slots.size():
		var slot: AutolysisQuestBoardSlot = board.slots[index]
		check(slot.collision_layer == 32 and slot.collision_mask == 0, "第%d槽使用聚焦层32与零碰撞掩码" % index)
		check(slot.get_node_or_null("quest_paper_%d" % index) == null, "第%d槽已删除示意纸节点" % index)
		var point: Vector2 = _pixel(slot)
		check(point != INVALID_PIXEL, "第%d空槽正式聚焦射线可达" % index)
		if point == INVALID_PIXEL:
			continue
		var excluded: Array[RID] = [board.get_rid(), player.get_rid(), player._found_area.get_rid()]
		check(_raw_ray(point, 3, excluded).get("collider") != slot, "第%d槽不参与普通掩码3射线" % index)
		if inventory.get_focused_instance() == null:
			check(inventory.try_receive_instance(_instance()), "为第%d槽准备正式手持文件" % index)
		await _click(point)
		var display: Node3D = slot.get_display()
		check(slot.get_stored_instance() != null and is_instance_valid(display) and display.get_parent() == slot, "第%d槽正式文件显示归属实际命中锚点" % index)
		if is_instance_valid(display):
			check(_display_only(display), "第%d槽纸面无拾取碰撞或独立交互入口" % index)
			_measure_projection(slot, display, "独立预制体")
		check(query.query_target(player.camera, point, board.focus_target, [player.get_rid(), player._found_area.get_rid()]) == slot, "第%d槽占用后射线仍命中原槽入口" % index)
		var blocker: StaticBody3D = _blocker(point)
		await frames(2)
		check(query.query_target(player.camera, point, board.focus_target, [player.get_rid(), player._found_area.get_rid()]) == null, "第%d槽外部墙体首命中阻挡正式聚焦查询" % index)
		await _click(point)
		check(slot.get_stored_instance() != null and inventory.get_focused_instance() == null, "第%d槽遮挡点击不穿透取回" % index)
		blocker.queue_free()
		await frames(2)
		await _click(point)
		check(slot.get_stored_instance() == null and inventory.get_focused_instance() != null, "第%d槽解除遮挡后正式点击取回" % index)


func _display_only(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is AutolysisInteractionComponent:
		return false
	for child: Node in node.get_children():
		if not _display_only(child):
			return false
	return true


func _measure_projection(slot: AutolysisQuestBoardSlot, display: Node3D, source: String) -> void:
	var front: MeshInstance3D = AutolysisQuestPaperVisual.get_front(display)
	var view: AutolysisQuestPaperView = AutolysisQuestPaperVisual.get_view(display)
	check(front != null and view != null, source + "纸面存在正面与全文视图")
	if front == null or view == null:
		return
	var bounds: AABB = front.get_aabb()
	var points: Array[Vector2] = []
	var inside: bool = true
	var rectangle: Rect2 = Rect2(Vector2.ZERO, Vector2(root.size))
	for local: Vector3 in [bounds.position, bounds.position + Vector3(bounds.size.x, 0.0, 0.0), bounds.position + Vector3(bounds.size.x, bounds.size.y, 0.0), bounds.position + Vector3(0.0, bounds.size.y, 0.0)]:
		var position: Vector3 = front.to_global(local)
		var projected: Vector2 = player.camera.unproject_position(position)
		points.append(projected)
		inside = inside and not player.camera.is_position_behind(position) and rectangle.has_point(projected)
	var facing: float = front.global_basis.z.normalized().dot((player.camera.global_position - front.global_position).normalized())
	check(inside and facing > 0.0, source + "纸面几何投影在视口内且正面朝向配置相机")
	check(view.get_visible_data_line_indices().size() == slot.get_stored_instance().quest_paper_contents.get_line_count(), source + "纸面直接显示完整正文而不重播打印")
	measurements.append({"类型": "无图形纸面几何投影", "来源": source, "槽": str(slot.get_path()), "视口": root.size, "纸面四角": points, "正面朝向点积": facing, "全部在视口内": inside, "视觉可读性": "未验证；需要图形许可"})


func _queued_clicks() -> void:
	await _fixture()
	await _enter()
	var instance: AutolysisItemInstance = _instance()
	check(inventory.try_receive_instance(instance), "旧点击测试接收正式文件")
	var point: Vector2 = _pixel(board.slots[1])
	player.interaction_controller.set_physics_process(false)
	_button(MOUSE_BUTTON_LEFT, true, point)
	_button(MOUSE_BUTTON_LEFT, false, point)
	inventory._holding_revision += 1
	player.interaction_controller.set_physics_process(true)
	await frames(2)
	check(board.slots[1].get_stored_instance() == null and inventory.get_focused_instance() == instance, "排队点击持有修订变化后拒绝旧请求")
	player.interaction_controller.set_physics_process(false)
	_button(MOUSE_BUTTON_LEFT, true, point)
	_button(MOUSE_BUTTON_LEFT, false, point)
	check(player.focus_controller.request_exit(), "排队点击期间正式退出作废旧会话")
	await frames(25)
	player.interaction_controller.set_physics_process(true)
	await _enter()
	check(board.slots[1].get_stored_instance() == null and inventory.get_focused_instance() == instance, "旧会话点击不会在重入后提交")
	player.interaction_controller.set_physics_process(false)
	for index: int in range(2):
		_button(MOUSE_BUTTON_LEFT, true, point)
		_button(MOUSE_BUTTON_LEFT, false, point)
	player.interaction_controller.set_physics_process(true)
	await frames(2)
	check(board.slots[1].get_stored_instance() == instance and inventory.get_focused_instance() == null, "同批两次点击仅转移一次，不反向取回")


func _local_dependencies() -> void:
	await _fixture()
	await _enter()
	var failed_slot: AutolysisQuestBoardSlot = board.slots[0]
	var collision: CollisionShape3D = failed_slot.get_node("collision_quest_paper_slot_0") as CollisionShape3D
	collision.disabled = true
	await frames(2)
	check(player.focus_controller.is_focused_on(board.focus_target) and _pixel(board.slots[1]) != INVALID_PIXEL, "单槽碰撞禁用不关闭其他槽或整板聚焦")
	check(inventory.try_receive_instance(_instance()) and inventory.try_place_in_quest_board_slot(player, board.slots[1]), "单槽失效时其他槽仍能正式放置")
	var instance: AutolysisItemInstance = board.slots[1].get_stored_instance()
	var display: Node3D = board.slots[1].get_display()
	display.queue_free()
	await frames(3)
	check(board.slots[1].get_stored_instance() == instance and player.focus_controller.is_focused_on(board.focus_target), "实际删除槽纸面仍保留原资源占用与聚焦")
	await _click(_pixel(board.slots[1]))
	check(inventory.get_focused_instance() == instance and board.slots[1].get_stored_instance() == null, "纸面实际释放后正式槽入口取回同一实例")
	board.slots[1].transfer_interaction.queue_free()
	await frames(3)
	check(player.focus_controller.is_focused_on(board.focus_target) and _pixel(board.slots[2]) != INVALID_PIXEL, "单槽交互组件实际释放不关闭其他槽或整板聚焦")
	board.slots[0].queue_free()
	await frames(3)
	check(player.focus_controller.is_focused_on(board.focus_target) and _pixel(board.slots[2]) != INVALID_PIXEL, "单槽物理体实际释放不关闭其他槽或整板聚焦")
	check(inventory.try_place_in_quest_board_slot(player, board.slots[2]), "单槽组件及物理体释放后剩余有效槽仍能正式放置")
	board.reference_camera.queue_free()
	await frames(3)
	check(not player.focus_controller.has_control(), "核心参照相机释放安全结束本板聚焦")
	await _fixture()
	await _enter()
	board.queue_free()
	await frames(3)
	check(not player.focus_controller.has_control(), "板根释放安全归还玩家聚焦控制")
	await _fixture()
	await _enter()
	board.root_interaction.clear_execution_handler()
	await frames(3)
	check(not player.focus_controller.has_control() and not board.is_configured(), "根唯一执行绑定清除使核心登记失效并结束聚焦")
	await _fixture()
	await _enter()
	board.focus_target.clear_quest_board_registration(board)
	await frames(3)
	check(not player.focus_controller.has_control() and not board.focus_target.is_valid_target(), "显式任务板登记清除使核心描述失效并结束聚焦")


func _main_scene() -> void:
	await _fixture(true)
	check(board.global_position.is_equal_approx(Vector3(-2.2, 1.5, 7.6)), "主场景实际任务板保持作者已保存世界位置")
	await _enter()
	for index: int in board.slots.size():
		var slot: AutolysisQuestBoardSlot = board.slots[index]
		var point: Vector2 = _pixel(slot)
		check(point != INVALID_PIXEL, "主场景保留全部周边物理体时第%d槽可达" % index)
		if point == INVALID_PIXEL:
			continue
		var instance: AutolysisItemInstance = _instance()
		check(inventory.try_receive_instance(instance), "主场景第%d槽准备正式手持文件" % index)
		await _click(point)
		check(slot.get_stored_instance() == instance, "主场景正式点击第%d槽仅放入命中槽" % index)
		if is_instance_valid(slot.get_display()):
			_measure_projection(slot, slot.get_display(), "主场景")
		var blocker: StaticBody3D = _blocker(point)
		await frames(2)
		var raw: Dictionary = _raw_ray(point, 35, [board.get_rid(), player.get_rid(), player._found_area.get_rid()])
		check(raw.get("collider") == blocker and query.query_target(player.camera, point, board.focus_target, [player.get_rid(), player._found_area.get_rid()]) == null, "主场景第%d槽实际外部首命中遮挡不被穿透" % index)
		blocker.queue_free()
		await frames(2)
		await _click(point)
		check(slot.get_stored_instance() == null and inventory.get_focused_instance() == instance, "主场景第%d槽正式入口取回同件文件" % index)
		check(inventory.cycle_focus(1), "主场景主动切换到下一空道具格")
