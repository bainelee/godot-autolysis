extends SceneTree
## 库存主导任务板取放事务验收；故障注入只使用正式同步回调边界。

const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
const BOARD_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/quest_board_0.tscn")
const MACHINE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/quest_machine_0.tscn")
const PAPER: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/quest_paper.tres")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const FIRST_TASK: AutolysisQuestPrintDefinition = preload("res://main-autolysis/systems/quest-print-system/quests/quest_test_0.tres")

class FaultInventory extends AutolysisInventoryController:
	var fail_preparation: bool = false
	var preparation_hook: Callable

	func _prepare_visual(instance: AutolysisItemInstance) -> Node3D:
		if fail_preparation:
			return null
		var candidate: Node3D = super._prepare_visual(instance)
		var hook: Callable = preparation_hook
		if hook.is_valid():
			hook.call()
		return candidate

class FaultSlot extends AutolysisQuestBoardSlot:
	var fail_preparation: bool = false
	var preparation_hook: Callable

	func prepare_visual(instance: AutolysisItemInstance) -> Node3D:
		if fail_preparation:
			return null
		var candidate: Node3D = super.prepare_visual(instance)
		var hook: Callable = preparation_hook
		if hook.is_valid():
			hook.call()
		return candidate

var world: Node3D
var player: AutolysisPlayer
var inventory: FaultInventory
var board: AutolysisQuestBoard
var slot: FaultSlot
var expected_instance: AutolysisItemInstance
var failures: int = 0
var records: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var observation_count: int = 0
var observation_consistent: bool = true
var reentry_blocked: bool = true
var placing: bool = true
var mutation_mode: StringName = &"task_id"
var callback_case: StringName
var callback_calls: int = 0
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/任务板实施证据/20261007/checks/transfer")


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
		push_error("任务板转移专项禁止启动图形后端。")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	await _three_slots_and_identity()
	await _gates_and_queries()
	await _preparation_failures()
	await _contents_boundaries()
	await _reversible_display_boundaries()
	await _candidate_dependency_boundaries()
	await _release_boundaries()
	await _immediate_release_boundaries()
	await _observation_boundaries()
	await _completed_cleanup_boundaries()
	await _renamed_nested_references()
	await _released_printer()
	paused = false
	if is_instance_valid(world):
		world.queue_free()
	await frames(3)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("任务板转移断言.json"), FileAccess.WRITE)
	if report == null:
		check(false, "任务板转移报告可写入本轮证据目录")
	else:
		report.store_string(JSON.stringify({"失败数": failures, "断言数": records.size(), "记录": records, "测量": measurements, "方式": "无图形正式库存入口与同步回调故障注入；未执行图形或原生指针"}, "\t"))
		report.close()
	print("任务板转移专项断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)


func _entry_allowed() -> bool:
	return player._base_input_allowed() and not player.focus_controller.has_control()


func _fixture(occupied: bool = false, nested: bool = false) -> void:
	paused = false
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
	board = BOARD_SCENE.instantiate() as AutolysisQuestBoard
	# 本夹具不保存场景；移植前解除原保存归属，防止合法重挂触发所有者警告。
	for child: Node in board.find_children("*", "", true, false):
		child.owner = null
	var original: AutolysisQuestBoardSlot = board.slots[0]
	slot = FaultSlot.new()
	slot.name = original.name
	slot.transform = original.transform
	slot.collision_layer = original.collision_layer
	slot.collision_mask = original.collision_mask
	slot.collision_shape = original.collision_shape
	slot.transfer_interaction = original.transfer_interaction
	slot.paper_position = original.paper_position
	slot.paper_rotation_degrees = original.paper_rotation_degrees
	slot.paper_scale = original.paper_scale
	for child: Node in original.get_children():
		original.remove_child(child)
		slot.add_child(child)
	board.remove_child(original)
	board.add_child(slot)
	board.slots[0] = slot
	original.free()
	if nested:
		var holder: Node3D = Node3D.new()
		holder.name = "显式槽引用容器"
		board.add_child(holder)
		for index: int in board.slots.size():
			var target: AutolysisQuestBoardSlot = board.slots[index]
			board.remove_child(target)
			holder.add_child(target)
			target.name = "已重命名槽%d" % index
	board.position = Vector3(2.0, 0.5, -1.0)
	board.rotation.y = 0.23
	world.add_child(board)
	await frames(3)
	check(board.is_configured() and slot.is_configured(), "真实任务板与故障夹具槽保持生产引用合同")
	check(player.focus_controller.try_enter(board.focus_target), "正式玩家通过任务板聚焦入口建立事务夹具")
	await frames(25)
	check(player.focus_controller.is_focused_on(board.focus_target), "事务夹具等待真实聚焦过渡完成")
	expected_instance = _paper("任务板事务原件")
	check(inventory.try_receive_instance(expected_instance), "正式库存接收原逐件任务文件")
	if occupied:
		check(inventory.try_place_in_quest_board_slot(player, slot), "正式入口建立待取原件占用")
	callback_calls = 0
	observation_count = 0
	observation_consistent = true
	reentry_blocked = true


func _paper(task_id: String, blank: bool = false) -> AutolysisItemInstance:
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(PAPER)
	if not blank:
		instance.set_quest_paper_contents(AutolysisQuestPaperContents.create_result(task_id, PackedStringArray(["委托编号：07003141", "目标原文第二行", "排版分组第三行"]), PackedInt32Array([2])))
	return instance


func _same_contents(first: AutolysisQuestPaperContents, second: AutolysisQuestPaperContents) -> bool:
	if first == null or second == null:
		return first == second
	return first.get_task_id() == second.get_task_id() and first.get_data_lines() == second.get_data_lines() and first.get_group_gap_before_lines() == second.get_group_gap_before_lines()


func _select(index: int) -> void:
	for count: int in AutolysisInventoryController.SLOT_COUNT:
		if inventory.get_focused_index() == index:
			return
		check(inventory.cycle_focus(1), "正式库存主动切格成功")
	check(inventory.get_focused_index() == index, "正式选中指定库存格")


func _identity_count(instance: AutolysisItemInstance) -> int:
	var count: int = 0
	if is_instance_valid(inventory) and not inventory.is_queued_for_deletion():
		for index: int in AutolysisInventoryController.SLOT_COUNT:
			if inventory.get_slot_instance(index) == instance:
				count += 1
	if is_instance_valid(board) and not board.is_queued_for_deletion():
		for target: AutolysisQuestBoardSlot in board.slots:
			if is_instance_valid(target) and not target.is_queued_for_deletion() and target.get_stored_instance() == instance:
				count += 1
	return count


func _subscription_count(instance: AutolysisItemInstance, observer: Object) -> int:
	var count: int = 0
	for connection: Dictionary in instance.changed.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_object() == observer:
			count += 1
	return count


func _held_matches(instance: AutolysisItemInstance) -> bool:
	var presenter: AutolysisHeldItemPresenter = player.held_item_presenter
	var display: Node3D = presenter.get_display()
	return is_instance_valid(display) and not display.is_queued_for_deletion() and display.get_parent() == presenter and display.visible and presenter._instance == instance and AutolysisQuestPaperVisual.get_instance(display) == instance and _subscription_count(instance, presenter) == 1


func _locks_released() -> bool:
	return not inventory._busy and slot._transfer_token == 0 and player.held_item_presenter._replacement_token == 0


func _three_slots_and_identity() -> void:
	await _fixture()
	var originals: Array[AutolysisItemInstance] = [expected_instance, _paper("任务板事务原件"), _paper("合法空白文件", true)]
	var snapshots: Array[AutolysisQuestPaperContents] = []
	check(originals[0] != originals[1] and _same_contents(originals[0].quest_paper_contents, originals[1].quest_paper_contents), "相同任务标识与正文的两件资源保持不同逐件身份")
	await _select(3)
	check(inventory.try_receive_item(CAFFEINE), "未参与转移的其他道具格保存原料")
	var untouched: AutolysisItemInstance = inventory.get_slot_instance(3)
	await _select(0)
	for index: int in board.slots.size():
		var instance: AutolysisItemInstance = originals[index]
		snapshots.append(instance.quest_paper_contents)
		if index > 0:
			check(inventory.try_receive_instance(instance), "第%d槽准备另一正式逐件任务文件" % index)
		var focused: int = inventory.get_focused_index()
		check(_identity_count(instance) == 1, "第%d槽放置前存活来源数量为一" % index)
		check(inventory.can_place_in_quest_board_slot(player, board.slots[index]) and inventory.try_place_in_quest_board_slot(player, board.slots[index]), "第%d槽正式放置原件成功" % index)
		check(inventory.get_focused_index() == focused and inventory.get_focused_instance() == null and board.slots[index].get_stored_instance() == instance, "第%d槽放置只清空当前格与占用命中槽，格号不变" % index)
		check(_identity_count(instance) == 1 and _same_contents(instance.quest_paper_contents, snapshots[index]) and inventory.get_slot_instance(3) == untouched, "第%d槽放置保持逐件身份、完整内容与未参与库存格守恒" % index)
		check(_subscription_count(instance, player.held_item_presenter) == 0 and _subscription_count(instance, board.slots[index]) == 1, "第%d槽成功放置后资源订阅从手持移至本槽" % index)
	var first_display: Node3D = board.slots[0].get_display()
	var second_display: Node3D = board.slots[1].get_display()
	check(AutolysisQuestPaperVisual.get_front(first_display).material_overlay != AutolysisQuestPaperVisual.get_front(second_display).material_overlay, "相同任务两张纸面持有独立文字材质")
	var blank_display: Node3D = board.slots[2].get_display()
	check(originals[2].is_valid_instance() and AutolysisQuestPaperVisual.get_instance(blank_display) == originals[2] and AutolysisQuestPaperVisual.get_view(blank_display) == null, "合法空白任务纸按既有定义保存同件空正文")
	for index: int in [2, 0, 1]:
		var instance: AutolysisItemInstance = originals[index]
		var focused: int = inventory.get_focused_index()
		check(inventory.try_take_from_quest_board_slot(player, board.slots[index]), "按不同顺序取回第%d槽原件" % index)
		check(board.slots[index].get_stored_instance() == null and inventory.get_focused_instance() == instance and inventory.get_focused_index() == focused and _held_matches(instance), "第%d槽取回清空本槽、恢复原件手持与原选格号" % index)
		check(_identity_count(instance) == 1 and _same_contents(instance.quest_paper_contents, snapshots[index]) and inventory.get_slot_instance(3) == untouched, "第%d槽取回后身份、空白或完整正文及其他格守恒" % index)
		check(_subscription_count(instance, board.slots[index]) == 0 and not inventory.try_take_from_quest_board_slot(player, board.slots[index]), "第%d槽取回解除槽订阅且重复取回不复制文件" % index)
		await _select(posmod(focused + 1, 3))
	for instance: AutolysisItemInstance in originals:
		check(_identity_count(instance) == 1, "三槽往返后每件原资源在存活库存和任务板内恰好一份")


func _gates_and_queries() -> void:
	await _fixture()
	var children_before: int = slot.get_child_count()
	var slot_revision: int = slot.get_revision()
	var held_revision: int = inventory.get_holding_revision()
	var display: Node3D = player.held_item_presenter.get_display()
	for count: int in range(5):
		check(inventory.can_place_in_quest_board_slot(player, slot) and not inventory.can_take_from_quest_board_slot(player, slot), "只读查询返回实际空槽与任务手持许可")
	check(children_before == slot.get_child_count() and slot_revision == slot.get_revision() and held_revision == inventory.get_holding_revision() and player.held_item_presenter.get_display() == display and slot._transfer_token == 0, "重复许可查询不创建显示、不占槽、不修改修订或手持")
	check(inventory.try_place_in_quest_board_slot(player, slot), "拒绝矩阵建立占用槽")
	check(not inventory.try_place_in_quest_board_slot(player, board.slots[1]), "空手点击空槽不转移资源")
	check(inventory.try_receive_item(CAFFEINE), "正式手持非任务类型输入")
	var blocker: AutolysisItemInstance = inventory.get_focused_instance()
	check(not inventory.can_place_in_quest_board_slot(player, board.slots[1]) and not inventory.try_place_in_quest_board_slot(player, board.slots[1]), "非任务类型拒绝空槽放置")
	check(not inventory.can_take_from_quest_board_slot(player, slot) and not inventory.try_take_from_quest_board_slot(player, slot) and inventory.get_focused_instance() == blocker and slot.get_stored_instance() == expected_instance, "任意手持占用拒绝取回和替换，双方来源保持")
	await _select(1)
	check(inventory.can_take_from_quest_board_slot(player, slot), "主动切到空格后允许取回，其他格有物不影响空手")
	inventory._handset_transfer_token = 1
	check(not inventory.can_take_from_quest_board_slot(player, slot) and not inventory.try_take_from_quest_board_slot(player, slot), "听筒交接互斥拒绝任务板取回")
	inventory._handset_transfer_token = 0
	inventory._handset_session = 1
	check(not inventory.can_take_from_quest_board_slot(player, slot), "听筒独占持有拒绝任务板取回")
	inventory._handset_session = 0
	var token: int = slot.begin_transfer(player, inventory)
	check(token > 0 and not inventory.can_take_from_quest_board_slot(player, slot) and not inventory.try_take_from_quest_board_slot(player, slot), "同槽已持转移令牌拒绝第二次竞争请求")
	var other_actor: AutolysisPlayer = PLAYER_SCENE.instantiate() as AutolysisPlayer
	world.add_child(other_actor)
	other_actor.set_physics_process(false)
	check(not slot.is_transfer_current(other_actor, inventory, token) and not slot.is_transfer_current(player, other_actor.inventory_controller, token), "其他玩家及库存不能借用原转移令牌")
	slot.end_transfer(other_actor, inventory, token)
	check(slot.is_transfer_current(player, inventory, token), "错误发起者不能结束本次槽转移")
	slot.end_transfer(player, inventory, token)
	other_actor.queue_free()
	player.is_showing_ui = true
	check(not inventory.can_take_from_quest_board_slot(player, slot), "玩家界面输入关闭拒绝任务板取回")
	player.is_showing_ui = false
	check(player.focus_controller.request_exit(), "正式退出本板用于错误设备许可核查")
	await frames(25)
	var other_board: AutolysisQuestBoard = BOARD_SCENE.instantiate() as AutolysisQuestBoard
	other_board.position = Vector3(5.0, 0.0, -1.0)
	world.add_child(other_board)
	check(player.focus_controller.try_enter(other_board.focus_target), "正式聚焦另一任务板")
	await frames(25)
	check(not inventory.can_take_from_quest_board_slot(player, slot) and not inventory.try_take_from_quest_board_slot(player, slot) and slot.get_stored_instance() == expected_instance, "错误任务板会话拒绝原板取回且保留原资源")


func _execute() -> bool:
	return inventory.try_place_in_quest_board_slot(player, slot) if placing else inventory.try_take_from_quest_board_slot(player, slot)


func _preparation_failures() -> void:
	for direction: bool in [true, false]:
		placing = direction
		await _fixture(not placing)
		var previous: Node3D = player.held_item_presenter.get_display() if placing else slot.get_display()
		slot.fail_preparation = placing
		inventory.fail_preparation = not placing
		check(not _execute(), "显示准备失败拒绝" + ("放置" if placing else "取回"))
		check(_identity_count(expected_instance) == 1 and _locks_released() and (player.held_item_presenter.get_display() == previous if placing else slot.get_display() == previous), "准备失败保留来源、原显示及双方互斥清理")
		slot.fail_preparation = false
		inventory.fail_preparation = false
		for fault: StringName in [&"revision", &"selection", &"exit"]:
			await _fixture(not placing)
			callback_case = fault
			if placing:
				slot.preparation_hook = _preparation_callback
			else:
				inventory.preparation_hook = _preparation_callback
			check(not _execute() and callback_calls == 1, "准备回调改变" + ("持有修订" if fault == &"revision" else "选格" if fault == &"selection" else "聚焦会话") + "拒绝旧事务")
			check(_identity_count(expected_instance) == 1 and _locks_released(), "准备上下文失效保持同件来源且释放事务锁")
			if placing:
				check(inventory.get_slot_instance(0) == expected_instance and _held_matches(expected_instance), "放置准备失效保持原库存格与有效手持显示")
			else:
				check(slot.get_stored_instance() == expected_instance and slot.get_display() != null and inventory.get_slot_instance(0) == null, "取回准备失效保持槽来源和当前空格")
			inventory._focused_index = 0
	# 有效显示场景缺少纸面适配依赖，绑定失败不应被误报为成功。
	await _fixture()
	var definition: AutolysisItemDefinition = PAPER.duplicate() as AutolysisItemDefinition
	var empty_root: Node3D = Node3D.new()
	var empty_scene: PackedScene = PackedScene.new()
	empty_scene.pack(empty_root)
	empty_root.free()
	definition.visual_scene = empty_scene
	expected_instance.definition = definition
	check(expected_instance.is_valid_instance() and not inventory.try_place_in_quest_board_slot(player, slot), "合法纯显示资产缺少纸面绑定依赖时拒绝放置")
	check(inventory.get_focused_instance() == expected_instance and slot.get_stored_instance() == null and _locks_released(), "纸面绑定失败保持原资源且不发布槽占用")


func _preparation_callback() -> void:
	callback_calls += 1
	match callback_case:
		&"revision":
			inventory._holding_revision += 1
		&"selection":
			check(not inventory.cycle_focus(1), "准备期间正式切格入口拒绝重入")
			inventory._focused_index = 1
		&"exit":
			player.focus_controller.request_exit()


func _changed_contents(original: AutolysisQuestPaperContents) -> AutolysisQuestPaperContents:
	if mutation_mode == &"blank":
		return null
	if original == null:
		return FIRST_TASK.create_contents()
	var task_id: String = original.get_task_id()
	var lines: PackedStringArray = original.get_data_lines()
	var gaps: PackedInt32Array = original.get_group_gap_before_lines()
	match mutation_mode:
		&"task_id":
			task_id = "回调中改变任务标识"
		&"data_lines":
			lines[0] = "回调中改变有效正文：07003141"
		&"group_gaps":
			gaps = PackedInt32Array([1])
	return AutolysisQuestPaperContents.create_result(task_id, lines, gaps)


func _mutate_contents(_candidate: Node) -> void:
	callback_calls += 1
	expected_instance.set_quest_paper_contents(_changed_contents(expected_instance.quest_paper_contents), false)


func _contents_boundaries() -> void:
	for direction: bool in [true, false]:
		placing = direction
		for mode: StringName in [&"task_id", &"data_lines", &"group_gaps", &"blank"]:
			await _fixture(not placing)
			mutation_mode = mode
			var original: AutolysisQuestPaperContents = expected_instance.quest_paper_contents
			var expected_change: AutolysisQuestPaperContents = _changed_contents(original)
			var source_display: Node3D = player.held_item_presenter.get_display() if placing else slot.get_display()
			var source: Node = slot if placing else player.held_item_presenter
			source.child_entered_tree.connect(_mutate_contents)
			check(not _execute() and callback_calls == 1, "显示入树改变" + ("任务标识" if mode == &"task_id" else "正文" if mode == &"data_lines" else "分组" if mode == &"group_gaps" else "正文为空状态") + "撤回" + ("放置" if placing else "取回"))
			source.child_entered_tree.disconnect(_mutate_contents)
			check(_identity_count(expected_instance) == 1 and _same_contents(expected_instance.quest_paper_contents, expected_change) and _locks_released(), "内容故障仅撤回本次转移，实际内容变更和原件身份保留")
			if placing:
				check(inventory.get_focused_instance() == expected_instance and slot.get_stored_instance() == null and player.held_item_presenter.get_display() == source_display and _held_matches(expected_instance), "内容变化回滚恢复原手持节点、实例绑定与唯一订阅")
			else:
				check(slot.get_stored_instance() == expected_instance and slot.get_display() == source_display and source_display.visible and inventory.get_focused_instance() == null and player.held_item_presenter.get_display() == null, "内容变化回滚恢复原槽来源与显示，手持无候选残留")
			check(_execute(), "故障解除后同件有效新内容可以正式转移")
			check(_identity_count(expected_instance) == 1 and _same_contents(expected_instance.quest_paper_contents, expected_change), "新请求采用当前真实内容而不恢复过期正文")
		await _fixture()
		check(expected_instance.set_quest_paper_contents(null), "合法任务原件可以形成空正文输入")
		if not placing:
			check(inventory.try_place_in_quest_board_slot(player, slot), "正式槽保存合法空白原件")
		mutation_mode = &"task_id"
		var blank_source: Node = slot if placing else player.held_item_presenter
		blank_source.child_entered_tree.connect(_mutate_contents)
		check(not _execute() and expected_instance.quest_paper_contents != null, "显示入树将空白原件改变为有效全文时拒绝过期空快照")
		blank_source.child_entered_tree.disconnect(_mutate_contents)
		check(_identity_count(expected_instance) == 1 and _locks_released() and (_held_matches(expected_instance) if placing else slot.get_stored_instance() == expected_instance), "单方为空的内容故障保持原件与有效来源显示")
		check(_execute(), "空白改为全文后新事务可以正式接收当前内容")


func _visibility_fault(display: Node3D) -> void:
	callback_calls += 1
	match callback_case:
		&"exit":
			if not display.visible:
				player.focus_controller.request_exit()
		&"pause":
			if not display.visible:
				player.is_movement_paused = true
		&"candidate":
			if display.visible:
				display.queue_free()


func _candidate_entry(candidate: Node) -> void:
	callback_calls += 1
	if callback_case == &"candidate":
		candidate.queue_free()
	elif callback_case == &"visibility":
		(candidate as Node3D).hide()
		(candidate as Node3D).visibility_changed.connect(_candidate_visibility.bind(candidate))


func _candidate_visibility(candidate: Node3D) -> void:
	if candidate.visible:
		candidate.queue_free()


func _reversible_display_boundaries() -> void:
	for direction: bool in [true, false]:
		placing = direction
		for fault: StringName in [&"exit", &"pause"]:
			await _fixture(not placing)
			callback_case = fault
			var previous: Node3D = player.held_item_presenter.get_display() if placing else slot.get_display()
			previous.visibility_changed.connect(_visibility_fault.bind(previous))
			check(not _execute(), "旧显示隐藏回调" + ("退出聚焦" if fault == &"exit" else "暂停") + "撤回未完成事务")
			check(callback_calls >= 1 and _identity_count(expected_instance) == 1 and previous.visible and not previous.is_queued_for_deletion() and _locks_released(), "暂存隐藏失败恢复同一旧显示可见性、唯一原件及锁")
			if placing:
				check(_held_matches(expected_instance), "可撤回放置恢复原手持绑定与唯一资源监听")
			else:
				check(slot.get_stored_instance() == expected_instance and slot.get_display() == previous and player.held_item_presenter.get_display() == null, "可撤回取回恢复原槽显示且无手持候选残留")
		for fault: StringName in [&"candidate", &"visibility"]:
			await _fixture(not placing)
			callback_case = fault
			var source: Node = slot if placing else player.held_item_presenter
			var previous: Node3D = player.held_item_presenter.get_display() if placing else slot.get_display()
			source.child_entered_tree.connect(_candidate_entry)
			check(not _execute() and callback_calls >= 1, "候选" + ("入树释放" if fault == &"candidate" else "显示回调释放") + "拒绝未完成事务")
			source.child_entered_tree.disconnect(_candidate_entry)
			check(_identity_count(expected_instance) == 1 and previous.visible and not previous.is_queued_for_deletion() and _locks_released(), "候选生命周期故障保持原件、原显示并清理双方锁")
			check(_held_matches(expected_instance) if placing else slot.get_stored_instance() == expected_instance and slot.get_display() == previous and player.held_item_presenter.get_display() == null, "候选故障回滚保留有效显示与原来源绑定")
			check(_execute(), "候选故障解除后正式入口可继续转移")


func _dependency_entry(candidate: Node) -> void:
	(candidate as Node3D).hide()
	(candidate as Node3D).visibility_changed.connect(_dependency_visibility.bind(candidate))


func _dependency_visibility(candidate: Node3D) -> void:
	if not candidate.visible:
		return
	callback_calls += 1
	var dependency: Node
	match callback_case:
		&"front":
			dependency = AutolysisQuestPaperVisual.get_front(candidate)
		&"viewport":
			dependency = AutolysisQuestPaperVisual.get_viewport(candidate)
		&"view":
			dependency = AutolysisQuestPaperVisual.get_view(candidate)
	if is_instance_valid(dependency):
		dependency.queue_free()


func _candidate_dependency_boundaries() -> void:
	for direction: bool in [true, false]:
		placing = direction
		for target: StringName in [&"front", &"viewport", &"view"]:
			await _fixture(not placing)
			callback_case = target
			var source: Node = slot if placing else player.held_item_presenter
			var previous: Node3D = player.held_item_presenter.get_display() if placing else slot.get_display()
			source.child_entered_tree.connect(_dependency_entry)
			check(not _execute() and callback_calls >= 1, "候选显示回调仅释放" + ("纸面正面" if target == &"front" else "纸面视口" if target == &"viewport" else "全文视图") + "时拒绝统一提交")
			source.child_entered_tree.disconnect(_dependency_entry)
			check(_identity_count(expected_instance) == 1 and _locks_released() and previous.visible and not previous.is_queued_for_deletion(), "候选展示局部依赖失效保持原件来源、原显示与互斥清理")
			check(_held_matches(expected_instance) if placing else slot.get_stored_instance() == expected_instance and slot.get_display() == previous and player.held_item_presenter.get_display() == null, "仅候选纸面依赖失效不误清稳定来源显示和订阅")
			check(_execute(), "候选纸面依赖故障解除后正式入口可继续转移")


func _release_callback(_candidate: Node) -> void:
	callback_calls += 1
	match callback_case:
		&"slot":
			slot.queue_free()
		&"board":
			board.queue_free()
		&"player":
			player.queue_free()
		&"presenter":
			player.held_item_presenter.queue_free()


func _release_boundaries() -> void:
	for direction: bool in [true, false]:
		placing = direction
		for fault: StringName in [&"slot", &"board", &"player", &"presenter"]:
			await _fixture(not placing)
			callback_case = fault
			var source: Node = slot if placing else player.held_item_presenter
			source.child_entered_tree.connect(_release_callback)
			check(not _execute() and callback_calls == 1, "候选入树排队释放" + ("槽" if fault == &"slot" else "板根" if fault == &"board" else "玩家" if fault == &"player" else "呈现器") + "时不伪报转移成功")
			if placing:
				check(inventory.get_focused_instance() == expected_instance, "放置生命周期失效保留原库存来源")
				if fault == &"slot" or fault == &"board":
					check(_held_matches(expected_instance) and not inventory._busy, "世界来源排队释放后原库存手持仍有效且解锁")
			else:
				check(inventory.get_focused_instance() == null and not inventory._busy, "取回生命周期失效不提交库存候选且清理库存锁")
				if fault == &"player" or fault == &"presenter":
					check(slot.get_stored_instance() == expected_instance and slot.get_display() != null and slot._transfer_token == 0, "玩家侧失效匹配恢复仍存活槽来源、显示与槽锁")
			await frames(3)


func _immediate_release_callback() -> void:
	callback_calls += 1
	match callback_case:
		&"slot":
			_retire_active_node(slot)
		&"board":
			board.free()
		&"player":
			player.free()
		&"presenter":
			player.held_item_presenter.free()
		&"inventory":
			_retire_active_node(inventory)


func _retire_active_node(target: Node) -> void:
	# 正在执行方法的对象拒绝直接释放；实际父生命周期释放仍能销毁其子节点。
	# 临时父级离树，避免入树锁；本段结束后目标必须已经实际失效。
	var parent: Node = target.get_parent()
	if parent != null:
		parent.remove_child(target)
	var retiring_parent: Node = Node.new()
	retiring_parent.add_child(target)
	retiring_parent.free()
	check(not is_instance_valid(target), "离树临时父生命周期变体实际销毁目标对象，不直接调用执行中对象释放")


func _surviving_locks_clear() -> bool:
	if is_instance_valid(inventory) and inventory._busy:
		return false
	if is_instance_valid(slot) and slot._transfer_token != 0:
		return false
	if is_instance_valid(player) and is_instance_valid(player.held_item_presenter) and player.held_item_presenter._replacement_token != 0:
		return false
	return true


func _immediate_release_boundaries() -> void:
	for direction: bool in [true, false]:
		placing = direction
		for target: StringName in [&"slot", &"board", &"player", &"presenter", &"inventory"]:
			await _fixture(not placing)
			callback_case = target
			var original_slot_display: Node3D = slot.get_display()
			if placing:
				slot.preparation_hook = _immediate_release_callback
			else:
				inventory.preparation_hook = _immediate_release_callback
			check(not _execute() and callback_calls == 1, "离树候选准备回调立即释放" + ("槽" if target == &"slot" else "板根" if target == &"board" else "玩家" if target == &"player" else "呈现器" if target == &"presenter" else "库存") + "拒绝旧事务")
			var dependency_alive: bool = is_instance_valid(slot) if target == &"slot" else is_instance_valid(board) if target == &"board" else is_instance_valid(player) if target == &"player" else is_instance_valid(inventory) if target == &"inventory" else is_instance_valid(player.held_item_presenter)
			check(not dependency_alive, "准备阶段生命周期操作完成后指定对象实际不存在")
			measurements.append({"类型": "准备回调立即生命周期终止", "方向": "放置" if placing else "取回", "目标": "槽" if target == &"slot" else "板根" if target == &"board" else "玩家" if target == &"player" else "呈现器" if target == &"presenter" else "库存", "实际不存在": not dependency_alive, "操作": "离树临时父生命周期销毁变体" if target == &"slot" or target == &"inventory" else "释放实际生产父级或呈现器"})
			check(_surviving_locks_clear(), "立即释放依赖后只清理仍存活对象的本次事务锁")
			if placing:
				if is_instance_valid(inventory):
					check(inventory.get_focused_instance() == expected_instance, "放置立即失效保留仍存活库存原件来源")
				if is_instance_valid(slot):
					check(slot.get_stored_instance() == null and slot.get_display() == null, "放置立即失效不建立未成功的槽资源或显示")
				if target == &"slot" or target == &"board" or target == &"inventory":
					check(is_instance_valid(player) and _held_matches(expected_instance), "立即释放世界来源或库存后原手持显示仍绑定原件")
			else:
				if is_instance_valid(inventory):
					check(inventory.get_focused_instance() == null, "取回立即失效不提交候选库存原件")
				if is_instance_valid(slot):
					check(slot.get_stored_instance() == expected_instance and slot.get_display() == original_slot_display and original_slot_display.visible, "取回立即失效匹配恢复仍存活槽原资源与原显示")
				if target == &"slot" or target == &"board" or target == &"inventory":
					check(is_instance_valid(player) and player.held_item_presenter.get_display() == null, "立即释放来源或库存后不伪报取回显示恢复")
			await frames(3)


func _observe_final() -> void:
	observation_count += 1
	var inventory_expected: AutolysisItemInstance = null if placing else expected_instance
	var slot_expected: AutolysisItemInstance = expected_instance if placing else null
	observation_consistent = observation_consistent and inventory.get_focused_instance() == inventory_expected and slot.get_stored_instance() == slot_expected and _identity_count(expected_instance) == 1
	if placing:
		observation_consistent = observation_consistent and player.held_item_presenter.get_display() == null and slot.get_display() != null and slot.get_display().visible
		observation_consistent = observation_consistent and inventory.can_take_from_quest_board_slot(player, slot) and not inventory.can_place_in_quest_board_slot(player, slot)
	else:
		observation_consistent = observation_consistent and _held_matches(expected_instance) and slot.get_display() == null
		observation_consistent = observation_consistent and inventory.can_place_in_quest_board_slot(player, slot) and not inventory.can_take_from_quest_board_slot(player, slot)
	reentry_blocked = reentry_blocked and not inventory.try_place_in_quest_board_slot(player, slot) and not inventory.try_take_from_quest_board_slot(player, slot) and not inventory.try_receive_item(CAFFEINE) and not inventory.cycle_focus(1)


func _observe_final_second() -> void:
	_observe_final()


func _observation_boundaries() -> void:
	for direction: bool in [true, false]:
		placing = direction
		await _fixture(not placing)
		inventory.held_item_changed.connect(_observe_final)
		inventory.held_item_changed.connect(_observe_final_second)
		slot.state_changed.connect(_observe_final)
		check(_execute(), "多个库存与槽观察者下正式事务只提交一次")
		check(observation_count == 3 and observation_consistent, "三个最早观察通知均读取库存、槽、显示与身份一致终态")
		check(reentry_blocked and _locks_released(), "成功通知期间取放、普通接收与切格重入拒绝，通知后锁释放")
		measurements.append({"方向": "放置" if placing else "取回", "逐件身份": expected_instance.get_instance_id(), "观察通知数": observation_count, "终态一致": observation_consistent, "重入拒绝": reentry_blocked})


func _cleanup_callback() -> void:
	callback_calls += 1
	if callback_case == &"board":
		board.queue_free()
	elif callback_case == &"player":
		player.queue_free()


func _completed_cleanup_boundaries() -> void:
	for direction: bool in [true, false]:
		placing = direction
		for target: StringName in [&"board", &"player"]:
			await _fixture(not placing)
			callback_case = target
			var previous: Node3D = player.held_item_presenter.get_display() if placing else slot.get_display()
			previous.tree_exiting.connect(_cleanup_callback)
			check(_execute() and callback_calls == 1, "最终成功清理旧显示期间排队释放" + ("板根" if target == &"board" else "玩家") + "仍返回成功")
			check(inventory.get_focused_instance() == (null if placing else expected_instance) and slot.get_stored_instance() == (expected_instance if placing else null), "成功后的生命周期清理不撤销已提交库存与槽终态")
			await frames(3)
			if placing and target == &"player":
				check(not is_instance_valid(player) and slot.get_stored_instance() == expected_instance, "玩家实际释放后已放入文件继续归属存活槽")
			elif not placing and target == &"board":
				check(not is_instance_valid(board) and inventory.get_focused_instance() == expected_instance and _held_matches(expected_instance), "板根实际释放后已取回文件继续归属存活库存与有效手持")
	await _fixture(true)
	placing = false
	callback_case = &"board"
	slot.state_changed.connect(_cleanup_callback)
	check(_execute() and callback_calls == 1 and inventory.get_focused_instance() == expected_instance, "最终槽观察者释放板根不撤销已经成功取回的文件")
	await frames(3)
	check(not is_instance_valid(board) and inventory.get_focused_instance() == expected_instance and _held_matches(expected_instance), "成功通知后板根实际释放保持已取得原件与手持全文")


func _renamed_nested_references() -> void:
	await _fixture(false, true)
	check(slot.get_parent() != board and slot.name == "已重命名槽0" and board.owns_slot(slot), "重命名与嵌套后显式归属引用保持有效")
	check(inventory.try_place_in_quest_board_slot(player, slot) and inventory.try_take_from_quest_board_slot(player, slot), "更新显式引用的重命名嵌套槽仍可原件往返")
	check(inventory.get_focused_instance() == expected_instance and _held_matches(expected_instance) and _identity_count(expected_instance) == 1, "嵌套变体取放保持身份与手持绑定")


func _released_printer() -> void:
	await _fixture()
	check(inventory.try_place_in_quest_board_slot(player, board.slots[2]), "临时将夹具原件移至独立槽以腾空当前格")
	check(player.focus_controller.request_exit(), "退出任务板准备真实打印来源")
	await frames(25)
	var machine: AutolysisQuestMachine = MACHINE_SCENE.instantiate() as AutolysisQuestMachine
	for field: StringName in [&"first_descent_seconds", &"first_wait_seconds", &"first_left_seconds", &"print_line_seconds", &"return_left_seconds", &"next_line_seconds", &"center_seconds", &"reset_seconds"]:
		machine.set(field, 0.002)
	world.add_child(machine)
	check(player.focus_controller.try_enter(machine.focus_target), "正式聚焦原打印设备")
	await frames(25)
	check(machine.request_task_print(FIRST_TASK, player) and machine.try_start_print(player), "原设备正式受理并启动本份任务打印")
	for count: int in range(240):
		if machine.state == AutolysisQuestMachine.PrintState.COMPLETE:
			break
		await frames(1)
	check(machine.state == AutolysisQuestMachine.PrintState.COMPLETE, "原设备真实有限动作完成本份任务")
	var paper: AutolysisQuestPaper = machine.get_current_paper()
	if paper == null:
		return
	var printed: AutolysisItemInstance = paper.get_item_instance()
	check(inventory.try_take_quest_paper(player, paper), "正式库存从原打印设备取得本份原件")
	check(player.focus_controller.request_exit(), "正式退出原打印设备")
	await frames(25)
	check(player.focus_controller.try_enter(board.focus_target), "重新聚焦任务板承接真实打印原件")
	await frames(25)
	check(inventory.try_place_in_quest_board_slot(player, slot), "真实打印原件通过任务板正式接口放置")
	machine.queue_free()
	await frames(4)
	check(not is_instance_valid(machine) and slot.get_stored_instance() == printed, "原打印设备实际释放后任务板占用仍保存原件")
	check(inventory.try_take_from_quest_board_slot(player, slot) and inventory.get_focused_instance() == printed and _held_matches(printed), "打印来源已释放仍可正式取回同件全文文件")
