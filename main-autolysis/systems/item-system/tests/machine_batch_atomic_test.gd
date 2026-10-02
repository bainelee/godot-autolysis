extends SceneTree
## 正式设备同步提交的可见性回调与来源／设备释放验收。

const MACHINE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/machine_blend_0.tscn")
const PLAYER: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
const TANK: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/liquid_tank.tres")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const SODIUM_BENZOATE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/sodium_benzoate.tres")

var failures: int = 0
var assertion_count: int = 0
var records: Array[Dictionary] = []
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/液体罐内容与配药器装填实施证据/20261002/checks/atomic/internal")


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	assertion_count += 1
	print(("通过：" if condition else "失败：") + description)
	records.append({"说明": description, "通过": condition})
	if not condition:
		failures += 1


func _frames(count: int) -> void:
	for _index: int in count:
		await physics_frame
		await process_frame


func _run() -> void:
	for mode: String in ["观察全部提交", "删除后续原药", "排队释放后续原药", "仅删除目标罐", "排队释放设备", "移出场景后排队释放设备"]:
		await _run_case(mode)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("machine-batch-atomic.json"), FileAccess.WRITE)
	if file == null:
		_check(false, "原子提交证据目录可写入")
	else:
		file.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "回调检查": records}, "\t"))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("加工原子提交验收断言数：", assertion_count, "；失败总数：", failures)
	quit(1 if failures > 0 else 0)


func _run_case(mode: String) -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var machine: AutolysisBlendMachine = MACHINE.instantiate() as AutolysisBlendMachine
	world.add_child(machine)
	var player: AutolysisPlayer = PLAYER.instantiate() as AutolysisPlayer
	world.add_child(player)
	player.set_physics_process(false)
	player.focus_controller.configure(player, player.camera, player.held_item_presenter, func() -> bool: return true)
	_check(machine.focus_target.is_valid_target(), mode + "正式设备配置有效")
	_check(player.focus_controller.try_enter(machine.focus_target), mode + "通过正式入口进入聚焦")
	await _frames(20)
	var inventory: AutolysisInventoryController = player.inventory_controller
	_check(inventory.try_receive_item(TANK) and inventory.try_place_in_blend_tank_place(player, machine.tank_place), mode + "正式库存事务放入空罐")
	var definitions: Array[AutolysisItemDefinition] = [CAFFEINE, SODIUM_BENZOATE]
	for index: int in 2:
		var slot: AutolysisBlendSlot = machine.slots[index]
		_check(slot.try_toggle(player), mode + "打开本轮原药槽%d" % index)
		await _frames(15)
		_check(inventory.try_receive_item(definitions[index]) and inventory.try_place_in_blend_slot(player, slot), mode + "正式事务放入本轮原药%d" % index)
		_check(slot.try_toggle(player), mode + "关闭本轮原药槽%d" % index)
		await _frames(15)
	var tank: AutolysisLiquidTank = machine.tank_place.get_stored_item()
	var tank_instance_id: int = tank.get_instance_id()
	var first: AutolysisRawMaterial = machine.slots[0].get_stored_item()
	var second: AutolysisRawMaterial = machine.slots[1].get_stored_item()
	var observed: Dictionary = {"可见性次数": 0, "内容次数": 0, "完成次数": 0}
	first.visibility_changed.connect(func() -> void:
		if not is_instance_valid(first) or first.visible or observed["可见性次数"] > 0:
			return
		observed["可见性次数"] += 1
		_observe_committed_state(machine, player, tank, mode + "首原药隐藏回调")
		if mode == "删除后续原药":
			second.free()
		elif mode == "排队释放后续原药":
			second.queue_free()
		elif mode == "仅删除目标罐":
			tank.free()
		elif mode == "排队释放设备":
			machine.queue_free()
		elif mode == "移出场景后排队释放设备":
			machine.get_parent().remove_child(machine)
			machine.queue_free()
	)
	tank.item_instance.changed.connect(func() -> void:
		observed["内容次数"] += 1
		_observe_committed_state(machine, player, tank, mode + "内容通知回调")
	)
	machine.processing_completed.connect(func(_batch_id: int, _contents: AutolysisLiquidContents) -> void:
		observed["完成次数"] += 1
		var completed_tank: AutolysisLiquidTank = instance_from_id(tank_instance_id) as AutolysisLiquidTank
		_check(not machine.is_batch_running() and not machine.is_interaction_locked() and (completed_tank == null or not completed_tank.is_empty()), mode + "完成通知时已恢复交互且完整提交没有回退")
	)
	_check(machine.try_start_processing(player), mode + "合法前提启动唯一加工批次")
	await _frames(125)
	_check(observed["可见性次数"] == 1, mode + "首来源隐藏通知只观察一次")
	if mode != "排队释放设备" and mode != "移出场景后排队释放设备":
		var expected_content_notifications: int = 0 if mode == "仅删除目标罐" else 1
		_check(observed["内容次数"] == expected_content_notifications and observed["完成次数"] == 1, mode + "完整批次只发送一次完成通知并跳过已释放罐内容通知")
		_check(not is_instance_valid(first) and not is_instance_valid(second), mode + "本轮原药节点全部释放")
		machine.processing_timer.timeout.emit()
		_check(observed["完成次数"] == 1, mode + "过期计时回调不重复完成")
	else:
		_check(not is_instance_valid(machine) and observed["内容次数"] == 0 and observed["完成次数"] == 0, mode + "设备释放后不访问实例或补发后续通知")
	world.queue_free()
	await _frames(2)


func _observe_committed_state(machine: AutolysisBlendMachine, player: AutolysisPlayer, tank: AutolysisLiquidTank, context: String) -> void:
	var all_slots_empty: bool = true
	for slot: AutolysisBlendSlot in machine.slots:
		all_slots_empty = all_slots_empty and slot.get_stored_item() == null
	_check(all_slots_empty and not tank.is_empty(), context + "全部槽为空且目标罐已满")
	_check(tank.item_instance.liquid_contents.get_raw_material_ids() == ["caffeine", "sodium_benzoate"], context + "完整槽序与内容已一致")
	_check(machine.is_batch_running() and machine.is_interaction_locked(), context + "对外回调期间保持运行锁")
	var all_entries_locked: bool = not machine.try_start_processing(player)
	for slot: AutolysisBlendSlot in machine.slots:
		all_entries_locked = all_entries_locked and not slot.try_toggle(player) and not slot.try_begin_transfer(player)
	all_entries_locked = all_entries_locked and not machine.tank_place.try_begin_transfer(player) and not machine.handle.try_begin_drag(player)
	all_entries_locked = all_entries_locked and not machine.root_interaction.try_interact(player, AutolysisInteractionComponent.InteractionMode.FOCUS)
	_check(all_entries_locked, context + "公开加工、槽、罐、拉杆与根入口均拒绝同步重入")
