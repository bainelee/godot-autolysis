extends SceneTree
## 正式玩家、通知中心和纸张的无图形取纸事务专项；故障只注入实际可调用边界。

const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
const MACHINE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/quest_machine_0.tscn")
const FIRST_TASK: AutolysisQuestPrintDefinition = preload("res://main-autolysis/systems/quest-print-system/quests/quest_test_0.tres")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const RAW_SHELF: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/place_shelf_workroom_rm_0.tscn")

class FaultInventory extends AutolysisInventoryController:
	var fail_preparation: bool = false
	var empty_display_variant: bool = false
	var preparation_hook: Callable

	func _prepare_visual(instance: AutolysisItemInstance) -> Node3D:
		if fail_preparation:
			return null
		var visual: Node3D = super._prepare_visual(instance)
		if empty_display_variant and is_instance_valid(visual):
			visual.free()
			visual = Node3D.new()
		var hook: Callable = preparation_hook
		if hook.is_valid():
			hook.call()
		return visual

var world: Node3D
var player: AutolysisPlayer
var inventory: FaultInventory
var machine: AutolysisQuestMachine
var paper: AutolysisQuestPaper
var query: AutolysisFocusRayQuery = AutolysisFocusRayQuery.new()
var failures: int = 0
var records: Array[Dictionary] = []
var ray_records: Array[Dictionary] = []
var held_notifications: int = 0
var source_notifications: int = 0
var observation_consistent: bool = true
var reentry_blocked: bool = true
var expected_instance: AutolysisItemInstance
var released_actor: bool = false
var contents_mutation_mode: StringName = &"task_id"
var contents_mutation_written: bool = false
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/任务文件打印实施证据/20261007/inventory")


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
		push_error("任务纸张库存专项禁止启动图形后端。")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	await _gates_and_source_identity()
	await _preparation_failures()
	await _contents_integrity()
	await _display_boundaries()
	await _observations_and_transfer()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("任务纸张库存断言.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"失败数": failures, "断言数": records.size(), "记录": records, "射线": ray_records}, "\t"))
	report.close()
	if is_instance_valid(world):
		world.queue_free()
	await frames(3)
	print("任务纸张库存专项断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)


func _entry_allowed() -> bool:
	return player._base_input_allowed() and not player.focus_controller.has_control()


func _fixture(use_first_task: bool = false) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	world = Node3D.new()
	root.add_child(world)
	player = PLAYER_SCENE.instantiate() as AutolysisPlayer
	var old_inventory: Node = player.get_node("InventoryController")
	player.remove_child(old_inventory)
	old_inventory.free()
	inventory = FaultInventory.new()
	inventory.name = "InventoryController"
	player.add_child(inventory)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player._clear_landing_stun()
	player.focus_controller.configure(player, player.camera, player.held_item_presenter, _entry_allowed)
	machine = MACHINE_SCENE.instantiate() as AutolysisQuestMachine
	# 缩短的是显式表现配置；完成许可仍由正式有限动作自然完成推进。
	for field: StringName in [&"first_descent_seconds", &"first_wait_seconds", &"first_left_seconds", &"print_line_seconds", &"return_left_seconds", &"next_line_seconds", &"center_seconds", &"reset_seconds"]:
		machine.set(field, 0.002)
	machine.position = Vector3(2.0, 0.4, -1.0)
	machine.rotation = Vector3(0.0, 0.23, 0.0)
	world.add_child(machine)
	held_notifications = 0
	source_notifications = 0
	observation_consistent = true
	reentry_blocked = true
	released_actor = false
	paper = null
	await frames(2)
	check(machine.is_configured() and machine.focus_target.is_valid_target(), "真实通知中心空闲无纸仍为合法聚焦目标")
	check(player.focus_controller.try_enter(machine.focus_target), "真实玩家可通过明确登记进入通知中心聚焦")
	await frames(25)
	check(player.focus_controller.is_focused_on(machine.focus_target), "正式聚焦过渡自然完成")
	var definition: AutolysisQuestPrintDefinition = FIRST_TASK if use_first_task else AutolysisQuestPrintDefinition.new()
	if not use_first_task:
		definition.task_id = "inventory_boundary_task"
		definition.data_lines = PackedStringArray(["库存边界测试：07003141"])
	check(machine.request_task_print(definition, player), "任务事件仅建立待打印")
	check(machine.get_current_paper() == null, "待打印阶段没有世界纸张")
	check(machine.try_start_print(player), "正式入口接受一次打印")
	paper = machine.get_current_paper()
	check(is_instance_valid(paper) and machine.focus_target.owns_target(paper), "本次动态纸张已显式登记")
	check(not inventory.can_take_quest_paper(player, paper) and not inventory.try_take_quest_paper(player, paper), "打印未完成时查询与执行均拒绝获取")
	for count: int in 240:
		if machine.state == AutolysisQuestMachine.PrintState.COMPLETE:
			break
		await frames(1)
	check(machine.state == AutolysisQuestMachine.PrintState.COMPLETE and paper.is_print_complete(), "真实两杆自然复位后完成待取")
	expected_instance = paper.get_item_instance()
	check(inventory.can_take_quest_paper(player, paper), "对应聚焦与当前空格允许取纸")


func _ray_pixel(body: Node3D) -> Vector2:
	var center: Vector2 = player.camera.unproject_position(body.global_position)
	var exclusions: Array[RID] = [player.get_rid(), player._found_area.get_rid()]
	for offset_y: int in range(-30, 31, 3):
		for offset_x: int in range(-30, 31, 3):
			var pixel: Vector2 = center + Vector2(offset_x, offset_y)
			if query.query_target(player.camera, pixel, machine.focus_target, exclusions) == body:
				ray_records.append({"入口": body.name, "像素": pixel, "相机": player.camera.global_transform, "目标": body.global_transform})
				return pixel
	return Vector2(-10000.0, -10000.0)


func _gates_and_source_identity() -> void:
	await _fixture()
	var paper_pixel: Vector2 = _ray_pixel(paper)
	var button_pixel: Vector2 = _ray_pixel(machine.print_button)
	check(paper_pixel.x >= 0.0 and button_pixel.x >= 0.0, "真实聚焦相机射线可达动态纸张和打印按钮")
	if paper_pixel.x >= 0.0:
		var obstruction: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(0.2, 0.2, 0.05)
		collision.shape = shape
		obstruction.add_child(collision)
		world.add_child(obstruction)
		var ray_origin: Vector3 = player.camera.project_ray_origin(paper_pixel)
		var distance: float = ray_origin.distance_to(paper.global_position) * 0.5
		obstruction.global_position = ray_origin + player.camera.project_ray_normal(paper_pixel) * distance
		await frames(2)
		var exclusions: Array[RID] = [player.get_rid(), player._found_area.get_rid()]
		check(query.query_target(player.camera, paper_pixel, machine.focus_target, exclusions) == null, "外部首命中阻挡通知中心纸张，不穿透遮挡")
		obstruction.queue_free()
		await frames(2)
	check(not machine.focus_target.unregister_quest_paper(paper, paper.print_serial - 1) and machine.focus_target.owns_target(paper), "旧纸张序号不能解除本次登记")
	check(inventory.try_receive_item(CAFFEINE), "当前格可先接收原料作为占格输入")
	check(not inventory.can_take_quest_paper(player, paper) and not inventory.try_take_quest_paper(player, paper), "当前格占用拒绝取纸，不自动寻找其他空格")
	check(machine.get_current_paper() == paper and machine.state == AutolysisQuestMachine.PrintState.COMPLETE, "占格失败保留原纸张及完成待取状态")
	check(inventory.cycle_focus(1) and inventory.can_take_quest_paper(player, paper), "玩家主动选中空格后允许获取")
	inventory._handset_transfer_token = 1
	check(not inventory.can_take_quest_paper(player, paper) and not inventory.try_take_quest_paper(player, paper), "听筒交接互斥拒绝任务文件获取")
	inventory._handset_transfer_token = 0
	inventory._handset_session = 1
	check(not inventory.can_take_quest_paper(player, paper), "已持听筒互斥拒绝任务文件获取")
	inventory._handset_session = 0
	check(player.focus_controller.request_exit(), "玩家正常退出设备聚焦")
	check(not inventory.can_take_quest_paper(player, paper) and not inventory.try_take_quest_paper(player, paper), "退出聚焦拒绝纸张直接调用")
	await frames(25)
	check(machine.get_current_paper() == paper and machine.state == AutolysisQuestMachine.PrintState.COMPLETE, "退出聚焦保留已完成纸张")
	check(player.focus_controller.try_enter(machine.focus_target), "重新进入同一通知中心聚焦")
	await frames(25)
	player.is_movement_paused = true
	check(not inventory.can_take_quest_paper(player, paper) and not inventory.try_take_quest_paper(player, paper), "真实菜单暂停拒绝取纸")
	player.is_movement_paused = false
	paused = true
	check(not inventory.can_take_quest_paper(player, paper), "场景树暂停拒绝取纸")
	paused = false
	var original_descriptor: AutolysisFocusTarget = player.focus_controller._target
	player.focus_controller._target = null
	check(not inventory.can_take_quest_paper(player, paper), "聚焦来源不匹配时拒绝获取")
	player.focus_controller._target = original_descriptor
	var other_machine: AutolysisQuestMachine = MACHINE_SCENE.instantiate() as AutolysisQuestMachine
	other_machine.position = Vector3(5.0, 0.0, -1.0)
	world.add_child(other_machine)
	check(player.focus_controller.request_exit(), "开始切换到另一有效通知中心")
	await frames(25)
	check(player.focus_controller.try_enter(other_machine.focus_target), "正式聚焦入口可选择另一设备")
	await frames(25)
	check(not inventory.can_take_quest_paper(player, paper) and not inventory.try_take_quest_paper(player, paper), "聚焦另一有效设备拒绝原设备纸张")
	check(machine.get_current_paper() == paper and machine.state == AutolysisQuestMachine.PrintState.COMPLETE, "错误设备聚焦不消耗已完成来源")


func _force_other_slot() -> void:
	check(not inventory.cycle_focus(1), "准备期间正式切格入口受库存互斥阻挡")
	inventory._focused_index = 1


func _exit_during_preparation() -> void:
	player.focus_controller.request_exit()


func _replace_instance_during_preparation() -> void:
	var replacement: AutolysisItemInstance = AutolysisItemInstance.create(expected_instance.definition)
	replacement.set_quest_paper_contents(expected_instance.quest_paper_contents, false)
	paper.item_instance = replacement


func _queue_paper_during_preparation() -> void:
	paper.queue_free()


func _change_revision_during_preparation() -> void:
	inventory._holding_revision += 1


func _changed_contents(original: AutolysisQuestPaperContents) -> AutolysisQuestPaperContents:
	var task_id: String = original.get_task_id()
	var lines: PackedStringArray = original.get_data_lines()
	var gaps: PackedInt32Array = original.get_group_gap_before_lines()
	match contents_mutation_mode:
		&"task_id":
			task_id = "changed_valid_task_id"
		&"data_lines":
			lines[0] = "另一份有效任务原文：07003141"
		&"group_gaps":
			gaps = PackedInt32Array([0])
	return AutolysisQuestPaperContents.create_result(task_id, lines, gaps)


func _replace_contents_during_preparation() -> void:
	contents_mutation_written = expected_instance.set_quest_paper_contents(_changed_contents(expected_instance.quest_paper_contents), false)


func _replace_contents_during_display_entry(_display: Node) -> void:
	_replace_contents_during_preparation()


func _contents_integrity() -> void:
	await _fixture()
	var original: AutolysisQuestPaperContents = expected_instance.quest_paper_contents
	var variants: Array[Dictionary] = [
		{"mode": &"task_id", "label": "任务标识"},
		{"mode": &"data_lines", "label": "完整原文"},
		{"mode": &"group_gaps", "label": "排版分组"},
	]
	for variant: Dictionary in variants:
		contents_mutation_mode = variant["mode"]
		contents_mutation_written = false
		var revision: int = inventory.get_holding_revision()
		inventory.preparation_hook = _replace_contents_during_preparation
		check(not inventory.try_take_quest_paper(player, paper) and contents_mutation_written, "准备期间同一逐件资源有效" + variant["label"] + "变化拒绝旧请求")
		check(paper.get_item_instance() == expected_instance and expected_instance.is_valid_instance() and inventory.get_focused_instance() == null and machine.get_current_paper() == paper and machine.state == AutolysisQuestMachine.PrintState.COMPLETE and machine.get_print_snapshot()["take_token"] == 0 and not inventory._busy and inventory.get_holding_revision() == revision, "准备期间" + variant["label"] + "变化保留来源身份、当前格、修订和双方锁守恒")
		inventory.preparation_hook = Callable()
		check(expected_instance.set_quest_paper_contents(original, false) and inventory.can_take_quest_paper(player, paper), "恢复本次绑定" + variant["label"] + "快照后许可恢复")
		check(expected_instance.set_quest_paper_contents(_changed_contents(original), false), "完成来源同件" + variant["label"] + "可以形成有效变更故障输入")
		check(not inventory.can_take_quest_paper(player, paper) and not inventory.try_take_quest_paper(player, paper), "完成后同件" + variant["label"] + "变化立即拒绝查询和正式入口")
		check(machine.get_current_paper() == paper and paper.get_item_instance() == expected_instance and inventory.get_focused_instance() == null and inventory.get_holding_revision() == revision, "完成后" + variant["label"] + "变化不冒充转移或清理来源")
		expected_instance.set_quest_paper_contents(original, false)
		player.held_item_presenter.child_entered_tree.connect(_replace_contents_during_display_entry)
		contents_mutation_written = false
		check(not inventory.try_take_quest_paper(player, paper) and contents_mutation_written, "来源暂存撤销后的显示入树同件" + variant["label"] + "变化拒绝提交")
		check(machine.get_current_paper() == paper and paper.get_item_instance() == expected_instance and machine.focus_target.owns_target(paper) and machine.state == AutolysisQuestMachine.PrintState.COMPLETE and inventory.get_focused_instance() == null and player.held_item_presenter.get_display() == null and player.held_item_presenter._instance == null and machine.get_print_snapshot()["take_token"] == 0 and not inventory._busy and inventory.get_holding_revision() == revision, "显示边界" + variant["label"] + "变化匹配回滚来源、登记、当前格、候选及资源监听")
		player.held_item_presenter.child_entered_tree.disconnect(_replace_contents_during_display_entry)
		check(expected_instance.set_quest_paper_contents(original, false) and inventory.can_take_quest_paper(player, paper), "显示边界失败恢复绑定" + variant["label"] + "后仍可正常获取")
	check(inventory.try_take_quest_paper(player, paper) and inventory.get_focused_instance() == expected_instance and expected_instance.quest_paper_contents.get_task_id() == original.get_task_id() and expected_instance.quest_paper_contents.get_data_lines() == original.get_data_lines() and expected_instance.quest_paper_contents.get_group_gap_before_lines() == original.get_group_gap_before_lines(), "全部内容变更故障恢复后唯一获取仍转移原绑定快照与同一逐件身份")


func _preparation_failures() -> void:
	await _fixture()
	inventory.fail_preparation = true
	check(not inventory.try_take_quest_paper(player, paper), "纯展示模型准备失败拒绝取纸")
	check(inventory.get_focused_instance() == null and machine.get_current_paper() == paper and machine.state == AutolysisQuestMachine.PrintState.COMPLETE and machine.get_print_snapshot()["take_token"] == 0, "准备失败保持来源、当前空格及待取状态，并释放双方锁")
	inventory.fail_preparation = false
	inventory.preparation_hook = _force_other_slot
	check(not inventory.try_take_quest_paper(player, paper), "准备期间选格上下文变化拒绝旧请求")
	check(inventory.get_slot_instance(0) == null and inventory.get_slot_instance(1) == null and machine.get_current_paper() == paper, "选格变化不转移旧格或新格，不消耗纸张")
	inventory._focused_index = 0
	inventory.preparation_hook = _replace_instance_during_preparation
	check(not inventory.try_take_quest_paper(player, paper), "准备期间同一纸张逐件身份替换拒绝获取")
	check(inventory.get_focused_instance() == null and machine.get_current_paper() == paper, "身份替换失败没有库存提交或来源撤销")
	paper.item_instance = expected_instance
	inventory.preparation_hook = _change_revision_during_preparation
	check(not inventory.try_take_quest_paper(player, paper) and inventory.get_focused_instance() == null and machine.get_current_paper() == paper, "准备期间持物修订变化拒绝旧请求并保留来源")
	inventory.preparation_hook = _exit_during_preparation
	check(not inventory.try_take_quest_paper(player, paper), "准备期间真实退出聚焦拒绝旧请求")
	check(inventory.get_focused_instance() == null and machine.get_current_paper() == paper and machine.state == AutolysisQuestMachine.PrintState.COMPLETE, "退出期间准备失败保留已完成来源")
	await _fixture()
	inventory.preparation_hook = _queue_paper_during_preparation
	check(not inventory.try_take_quest_paper(player, paper), "准备期间纸张排队释放拒绝旧请求")
	check(inventory.get_focused_instance() == null, "丢失来源不会进入携带栏")


func _reenter_during_display_entry(_display: Node) -> void:
	reentry_blocked = reentry_blocked and not inventory.try_take_quest_paper(player, paper) and not inventory.try_receive_item(CAFFEINE) and not inventory.cycle_focus(1)


func _exit_during_display_entry(_display: Node) -> void:
	player.focus_controller.request_exit()


func _queue_actor_during_display_entry(_display: Node) -> void:
	# 子节点入树期间不能立即释放祖先；使用引擎支持的排队释放。
	player.queue_free()
	released_actor = true


func _free_source_during_display_entry(_display: Node) -> void:
	machine.free()


func _free_candidate_during_display_entry(display: Node) -> void:
	display.free()


func _queue_display_on_visibility(display: Node3D) -> void:
	if display.visible:
		display.queue_free()


func _watch_display_visibility(display: Node) -> void:
	(display as Node3D).hide()
	(display as Node3D).visibility_changed.connect(_queue_display_on_visibility.bind(display))


func _display_boundaries() -> void:
	await _fixture()
	player.held_item_presenter.child_entered_tree.connect(_exit_during_display_entry)
	check(not inventory.try_take_quest_paper(player, paper), "显示入树时退出聚焦回滚获取")
	check(inventory.get_focused_instance() == null and machine.get_current_paper() == paper and machine.focus_target.owns_target(paper) and machine.state == AutolysisQuestMachine.PrintState.COMPLETE, "显示提交后失败成对恢复来源、登记和当前格")
	check(player.held_item_presenter.get_display() == null and machine.get_print_snapshot()["take_token"] == 0, "显示边界失败清理候选并释放双方锁")
	await _fixture()
	player.held_item_presenter.child_entered_tree.connect(_queue_actor_during_display_entry)
	check(not inventory.try_take_quest_paper(player, paper) and released_actor, "显示入树观察排队释放玩家时不完成获取")
	check(machine.get_current_paper() == paper and machine.state == AutolysisQuestMachine.PrintState.COMPLETE and machine.get_print_snapshot()["take_token"] == 0, "玩家失效后来源与设备锁回滚")
	await _fixture()
	player.held_item_presenter.child_entered_tree.connect(_free_source_during_display_entry)
	check(not inventory.try_take_quest_paper(player, paper), "显示入树观察立即释放设备时不完成获取")
	check(inventory.get_focused_instance() == null and player.held_item_presenter.get_display() == null, "设备释放后库存不保留来源或候选展示")
	await _fixture()
	# 实际进入整棵网格子树尚未结束时释放其祖先会触发原生错误；
	# 无子节点的纯展示变体用于合法的立即释放边界，完整模型另测排队释放。
	inventory.empty_display_variant = true
	player.held_item_presenter.child_entered_tree.connect(_free_candidate_during_display_entry)
	check(not inventory.try_take_quest_paper(player, paper), "无子节点展示入树观察立即释放候选时拒绝获取")
	check(inventory.get_focused_instance() == null and machine.get_current_paper() == paper and machine.focus_target.owns_target(paper) and player.held_item_presenter.get_display() == null, "立即释放候选后成对回滚库存、世界来源和显示")
	await _fixture()
	player.held_item_presenter.child_entered_tree.connect(_watch_display_visibility)
	check(not inventory.try_take_quest_paper(player, paper), "显示可见性回调释放候选时拒绝获取")
	check(inventory.get_focused_instance() == null and machine.get_current_paper() == paper and machine.focus_target.owns_target(paper), "可见性失败成对回滚库存与来源登记")


func _observe_held() -> void:
	held_notifications += 1
	observation_consistent = observation_consistent and inventory.get_focused_instance() == expected_instance and machine.get_current_paper() == null and machine.state == AutolysisQuestMachine.PrintState.IDLE and player.held_item_presenter.get_display() != null
	reentry_blocked = reentry_blocked and not inventory.try_receive_item(CAFFEINE) and not inventory.cycle_focus(1)


func _observe_held_second() -> void:
	_observe_held()


func _observe_source(_serial: int, instance: AutolysisItemInstance) -> void:
	source_notifications += 1
	observation_consistent = observation_consistent and instance == expected_instance and inventory.get_focused_instance() == expected_instance and machine.get_current_paper() == null and machine.state == AutolysisQuestMachine.PrintState.IDLE and player.held_item_presenter.get_display() != null
	reentry_blocked = reentry_blocked and not inventory.try_receive_item(CAFFEINE) and not machine.request_task_print(FIRST_TASK, player)


func _release_source_observer(_serial: int, _instance: AutolysisItemInstance) -> void:
	machine.queue_free()


func _release_machine_when_world_hidden() -> void:
	if not paper.visible:
		# 设备正在执行取纸完成，立即释放被引擎对象锁拒绝；采用合法排队释放。
		machine.queue_free()


func _release_actor_when_world_hidden() -> void:
	if not paper.visible:
		player.free()


func _observations_and_transfer() -> void:
	await _fixture(true)
	var contents: AutolysisQuestPaperContents = expected_instance.quest_paper_contents
	player.held_item_presenter.child_entered_tree.connect(_reenter_during_display_entry)
	inventory.held_item_changed.connect(_observe_held)
	inventory.held_item_changed.connect(_observe_held_second)
	machine.paper_taken.connect(_observe_source)
	check(inventory.try_take_quest_paper(player, paper), "正式专用入口成功取得首份任务文件")
	check(inventory.get_focused_instance() == expected_instance and expected_instance.quest_paper_contents.task_id == "quest_test_0" and expected_instance.quest_paper_contents.data_lines == contents.data_lines and contents.data_lines.size() == 13, "成功转移保留同一逐件身份、独立任务标识及全部十三行原文")
	check(observation_consistent and held_notifications == 2 and source_notifications == 1, "最早来源及两个持物观察者均看见双方一致终态")
	check(reentry_blocked, "模型入树及全部业务观察期间拒绝重入和重复获取")
	check(not machine.focus_target.owns_target(paper) and paper.is_queued_for_deletion(), "成功清理仅移除本次纸张登记和世界来源")
	check(not inventory.try_take_quest_paper(player, paper), "同一任务纸张只能转移一次")
	var shelf: AutolysisRawMaterialShelf = RAW_SHELF.instantiate() as AutolysisRawMaterialShelf
	world.add_child(shelf)
	check(shelf.find_first_empty_slot() >= 0 and not inventory.can_place_on_shelf(shelf) and not inventory.try_place_on_shelf(shelf), "任务文件拒绝有效空原料架的放置查询与执行")
	check(machine.request_task_print(FIRST_TASK, player), "成功取走并结束观察后可接收下一份任务事件")
	await _fixture()
	machine.paper_taken.connect(_release_source_observer)
	check(inventory.try_take_quest_paper(player, paper), "正常双方提交后来源观察释放设备仍保持成功")
	check(inventory.get_focused_instance() == expected_instance, "成功观察后的设备释放不会撤销已取得资源")
	await _fixture()
	paper.visibility_changed.connect(_release_machine_when_world_hidden)
	check(inventory.try_take_quest_paper(player, paper), "双方成功提交后隐藏世界纸张的观察排队释放设备仍返回成功")
	check(machine.is_queued_for_deletion() and inventory.get_focused_instance() == expected_instance, "世界纸张隐藏期间设备排队释放不撤销已取得资源")
	await frames(2)
	check(not is_instance_valid(machine) and inventory.get_focused_instance() == expected_instance, "设备完成实际释放后携带栏保留已取得资源")
	await _fixture()
	paper.visibility_changed.connect(_release_actor_when_world_hidden)
	check(inventory.try_take_quest_paper(player, paper), "双方成功提交后隐藏世界纸张的观察立即释放玩家仍返回成功")
	check(not is_instance_valid(player) and machine.get_current_paper() == null and machine.state == AutolysisQuestMachine.PrintState.IDLE and expected_instance.quest_paper_contents != null, "世界纸张隐藏期间玩家释放不恢复已提交来源或丢失局部内容快照")
