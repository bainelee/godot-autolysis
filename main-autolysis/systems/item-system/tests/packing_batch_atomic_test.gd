extends "res://main-autolysis/systems/item-system/tests/packing_machine_behavior_test.gd"
## 使用正式物品与设备，验证变化通知同步释放来源或机器时的提交边界。

var atomic_callbacks: int = 0
var atomic_partial: bool = false
var atomic_tank: AutolysisItemInstance
var atomic_capsule: AutolysisItemInstance
var atomic_release_target: Node
var atomic_records: Array[Dictionary] = []


func run_checks() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/封装器与气动胶囊实施证据/20261003/atomic")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	for notifier: int in range(3):
		for released: int in range(3):
			await _test_notification_release(notifier, released)
	await _test_source_release(false)
	await _test_source_release(true)
	_save_atomic_report()
	_release_controls()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	if is_instance_valid(world):
		world.queue_free()
	await frames(2)
	print("封装原子提交验收断言数：", assertion_count, "；失败总数：", failures)
	quit(1 if failures > 0 else 0)


func _prepare_atomic_batch() -> void:
	await _new_scene()
	await _enter()
	atomic_tank = await _put_tank(_source_contents(1))
	atomic_capsule = await _put_capsule()
	check(machine.try_select_type(player, 1), "原子验收正式机器接受针酊粉类型选择")
	await _wait_packing_motion()
	check(machine.can_start_processing(), "原子验收批次前提成立")
	atomic_callbacks = 0
	atomic_partial = false


func _test_notification_release(notifier: int, released: int) -> void:
	await _prepare_atomic_batch()
	var current_machine: AutolysisPackingMachine = machine as AutolysisPackingMachine
	var tank_node: AutolysisLiquidTank = current_machine.tank_place.get_stored_item()
	var capsule_node: AutolysisPneumaticCapsule = current_machine.capsule_place.get_stored_item()
	atomic_release_target = current_machine if released == 0 else (tank_node if released == 1 else capsule_node)
	if notifier == 0:
		atomic_tank.changed.connect(_on_atomic_resource_change)
	elif notifier == 1:
		atomic_capsule.changed.connect(_on_atomic_resource_change)
	else:
		current_machine.processing_completed.connect(_on_atomic_machine_complete)
	check(current_machine.try_start_processing(player), "释放边界验收批次已启动")
	await frames(135)
	check(atomic_callbacks == 1 and not atomic_partial, "完成通知只触发一次且观察者没有半提交：通知%d、释放%d" % [notifier, released])
	check(atomic_tank.is_empty_liquid_tank() and not atomic_capsule.is_empty_pneumatic_capsule(), "通知同步释放节点后两件逐件资源仍保存完整加工状态")
	check(not is_instance_valid(atomic_release_target), "完成通知释放指定节点")
	atomic_records.append({"通知入口": notifier, "释放对象": released, "通知数": atomic_callbacks, "半提交": atomic_partial, "空罐": atomic_tank.is_empty_liquid_tank(), "封装胶囊": not atomic_capsule.is_empty_pneumatic_capsule()})
	if atomic_tank.changed.is_connected(_on_atomic_resource_change):
		atomic_tank.changed.disconnect(_on_atomic_resource_change)
	if atomic_capsule.changed.is_connected(_on_atomic_resource_change):
		atomic_capsule.changed.disconnect(_on_atomic_resource_change)
	if is_instance_valid(current_machine) and current_machine.processing_completed.is_connected(_on_atomic_machine_complete):
		current_machine.processing_completed.disconnect(_on_atomic_machine_complete)
	atomic_release_target = null
	atomic_tank = null
	atomic_capsule = null


func _on_atomic_resource_change() -> void:
	atomic_callbacks += 1
	atomic_partial = atomic_partial or not atomic_tank.is_empty_liquid_tank() or atomic_capsule.is_empty_pneumatic_capsule()
	if is_instance_valid(atomic_release_target):
		# 正在调用或发信号的机器受引擎锁保护，只能排队释放；物品节点可同步释放。
		if atomic_release_target is AutolysisPackingMachine:
			atomic_release_target.queue_free()
		else:
			atomic_release_target.free()


func _on_atomic_machine_complete(_batch_id: int, _contents: AutolysisPackingContents) -> void:
	_on_atomic_resource_change()


func _test_source_release(release_capsule: bool) -> void:
	await _prepare_atomic_batch()
	var current_machine: AutolysisPackingMachine = machine as AutolysisPackingMachine
	var source: Node = current_machine.capsule_place.get_stored_item() if release_capsule else current_machine.tank_place.get_stored_item()
	check(current_machine.try_start_processing(player), "来源释放边界批次真实启动")
	await frames(20)
	source.free()
	await frames(120)
	check(not current_machine.is_batch_running() and not current_machine.get_processing_fault().is_empty(), "来源节点释放后拒绝提交并记录故障")
	check(atomic_tank.liquid_contents != null and atomic_capsule.is_empty_pneumatic_capsule(), "来源节点释放未消耗逐件源内容或创建半件产物")
	atomic_records.append({"运行中释放胶囊": release_capsule, "故障": current_machine.get_processing_fault(), "液体内容保留": atomic_tank.liquid_contents != null, "胶囊仍空": atomic_capsule.is_empty_pneumatic_capsule()})
	atomic_tank = null
	atomic_capsule = null


func _save_atomic_report() -> void:
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("封装原子提交报告.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "断言": records, "释放边界": atomic_records}, "\t"))
