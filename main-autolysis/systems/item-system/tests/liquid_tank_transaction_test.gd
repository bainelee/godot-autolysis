extends SceneTree
## 正式罐、柜和库存入口的同步事务验证；通过真实入树信号注入故障。

const TANK: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/liquid_tank.tres")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const WORLD_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/luquid_tank_0.tscn")
const CABINET_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/cabinet_workroom_0.tscn")
const SHELF_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/place_shelf_workroom_rm_0.tscn")
const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
const BLEND_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/machine_blend_0.tscn")

class TestActor extends Node3D:
	var inventory: AutolysisInventoryController
	var presenter: AutolysisHeldItemPresenter
	var input_enabled: bool = true
	var notifications: int = 0

	func input_allowed() -> bool:
		return input_enabled

	func on_inventory_changed() -> void:
		notifications += 1

var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/液体罐与专用柜实施证据/checks/transactions")
var world: Node3D
var failures: int = 0
var assertion_count: int = 0
var records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	await _test_world_and_input()
	await _test_focused_player()
	await _test_round_trips_and_selection()
	await _test_resource_failures()
	await _test_attachment_failures()
	await _test_observer_reentry()
	await _test_two_actor_reentry()
	await _test_orphaned_storage()
	_save_evidence()
	await _clear_world()
	world.queue_free()
	await _frames(2)
	print("液体罐事务断言数：", assertion_count, "；失败总数：", failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	assertion_count += 1
	records.append({"序号": assertion_count, "说明": description, "通过": condition})
	if condition:
		print("通过：", description)
	else:
		failures += 1
		print("失败：", description)


func _frames(count: int = 2) -> void:
	for _index: int in range(count):
		await physics_frame
		await process_frame


func _clear_world() -> void:
	paused = false
	for child: Node in world.get_children():
		child.queue_free()
	await _frames(2)


func _new_actor() -> TestActor:
	var actor: TestActor = TestActor.new()
	actor.inventory = AutolysisInventoryController.new()
	actor.inventory.name = "InventoryController"
	actor.presenter = AutolysisHeldItemPresenter.new()
	actor.presenter.name = "HeldItemPresenter"
	actor.add_child(actor.inventory)
	actor.add_child(actor.presenter)
	world.add_child(actor)
	actor.inventory.configure(actor.presenter, actor.input_allowed)
	actor.inventory.inventory_changed.connect(actor.on_inventory_changed)
	return actor


func _fixture(initial_count: int = 0, open_cabinet: bool = true) -> Dictionary:
	var actor: TestActor = _new_actor()
	var cabinet: AutolysisLiquidTankCabinet = CABINET_SCENE.instantiate() as AutolysisLiquidTankCabinet
	for index: int in range(2):
		if index < initial_count:
			continue
		var anchor: Node3D = cabinet.get_node("luquid_tank_slot_%d" % index) as Node3D
		for child: Node in anchor.get_children():
			child.free()
	world.add_child(cabinet)
	_check(cabinet.get_slot_count() == 2 and _cabinet_count(cabinet) == initial_count, "真实柜初始化登记%d罐且不额外生成" % initial_count)
	if open_cabinet:
		_check(cabinet.try_toggle(actor), "正式开闭入口开始打开真实柜门")
		await _frames(20)
		_check(cabinet.is_open(), "真实柜门动画完成后才建立完全打开状态")
	return {"actor": actor, "cabinet": cabinet}


func _new_world_tank(definition: AutolysisItemDefinition = TANK) -> AutolysisLiquidTank:
	var item: AutolysisLiquidTank = WORLD_SCENE.instantiate() as AutolysisLiquidTank
	item.item_definition = definition
	world.add_child(item)
	return item


func _inventory_count(inventory: AutolysisInventoryController) -> int:
	var count: int = 0
	for index: int in range(4):
		var definition: AutolysisItemDefinition = inventory.get_slot_item(index)
		if definition != null and definition.item_id == &"liquid_tank":
			count += 1
	return count


func _cabinet_count(cabinet: AutolysisLiquidTankCabinet) -> int:
	var count: int = 0
	for index: int in range(cabinet.get_slot_count()):
		if cabinet.get_item_at_slot(index) != null:
			count += 1
	return count


func _test_world_and_input() -> void:
	var actor: TestActor = _new_actor()
	var other: TestActor = _new_actor()
	var item: AutolysisLiquidTank = _new_world_tank()
	actor.input_enabled = false
	_check(not actor.inventory.can_take_liquid_tank(actor, item) and not actor.inventory.try_take_liquid_tank(actor, item), "输入禁止时查询及世界拾取同时拒绝")
	actor.input_enabled = true
	paused = true
	_check(not actor.inventory.can_take_liquid_tank(actor, item) and not actor.inventory.try_take_liquid_tank(actor, item), "直接调用世界拾取不能绕过场景暂停")
	paused = false
	_check(not actor.inventory.try_take_liquid_tank(other, item), "不能借用另一角色写入本库存控制器")
	var old_notifications: int = actor.notifications
	for _index: int in range(8):
		_check(actor.inventory.can_take_liquid_tank(actor, item), "重复许可查询只读且允许合法世界来源")
	_check(actor.notifications == old_notifications and actor.presenter.get_display() == null and item.is_available_for_pickup(), "查询不生成显示、不删除来源、不通知")
	_check(actor.inventory.try_take_liquid_tank(actor, item), "世界独立罐进入当前选中空格")
	_check(actor.inventory.get_focused_item() == TANK and actor.notifications == old_notifications + 1 and item.is_queued_for_deletion() and not item.visible and item.collision_layer == 0, "成功拾取一次通知并立即隐藏关闭世界碰撞")
	_check(not actor.inventory.try_take_liquid_tank(actor, item), "同帧重复世界拾取不生成额外罐")
	var fixed_item: AutolysisLiquidTank = WORLD_SCENE.instantiate() as AutolysisLiquidTank
	fixed_item.fixed_installation = true
	world.add_child(fixed_item)
	_check(not other.inventory.can_take_liquid_tank(other, fixed_item) and not other.inventory.try_take_liquid_tank(other, fixed_item) and fixed_item.collision_layer != 0, "固定装配罐保留物理碰撞且不能拾取")
	await _clear_world()


func _test_round_trips_and_selection() -> void:
	var fixture: Dictionary = await _fixture(2)
	var actor: TestActor = fixture["actor"]
	var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
	var original_zero: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	var original_one: AutolysisLiquidTank = cabinet.get_item_at_slot(1)
	_check(actor.inventory.try_take_liquid_tank(actor, original_one) and cabinet.get_item_at_slot(0) == original_zero and cabinet.get_item_at_slot(1) == null, "指定取回一号罐只释放一号槽")
	var display: Node3D = actor.presenter.get_display()
	_check(not actor.inventory.try_take_liquid_tank(actor, original_zero) and actor.inventory.get_slot_item(1) == null and actor.presenter.get_display() == display, "当前格已占用时不交换且不寻找其他空格")
	_check(actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet) and cabinet.get_item_at_slot(0) == original_zero and cabinet.get_item_at_slot(1) != null, "零号仍占用时放回一号空槽")
	for _index: int in range(5):
		var item: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
		_check(actor.inventory.try_take_liquid_tank(actor, item) and actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet), "指定零号罐反复取放成功")
		_check(_cabinet_count(cabinet) + _inventory_count(actor.inventory) == 2, "往返完成保持两罐总数")
	_check(actor.inventory.try_receive_item(TANK), "满柜第三罐进入当前格")
	display = actor.presenter.get_display()
	var old_notifications: int = actor.notifications
	_check(not actor.inventory.can_place_in_liquid_tank_cabinet(actor, cabinet) and not actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet), "满柜拒绝第三罐")
	_check(actor.inventory.get_focused_item() == TANK and actor.presenter.get_display() == display and actor.notifications == old_notifications and _cabinet_count(cabinet) == 2, "满柜拒绝保留库存、手持和既有两槽")
	var shelf: AutolysisRawMaterialShelf = SHELF_SCENE.instantiate() as AutolysisRawMaterialShelf
	world.add_child(shelf)
	_check(not actor.inventory.can_place_on_shelf(shelf) and not actor.inventory.try_place_on_shelf(shelf), "液体罐不能通过原药放置接口进入原药架")
	await _clear_world()


func _test_focused_player() -> void:
	var player: AutolysisPlayer = PLAYER_SCENE.instantiate() as AutolysisPlayer
	world.add_child(player)
	player.set_physics_process(false)
	player.inventory_controller.configure(player.held_item_presenter, func() -> bool: return true)
	player.focus_controller.configure(player, player.camera, player.held_item_presenter, func() -> bool: return true)
	var machine: Node3D = BLEND_SCENE.instantiate() as Node3D
	world.add_child(machine)
	var target: AutolysisFocusTarget = machine.get_node("FocusTarget") as AutolysisFocusTarget
	_check(player.focus_controller.try_enter(target), "正式玩家通过真实设备进入聚焦")
	await _frames(18)
	_check(player.focus_controller.is_focused_on(target), "正式玩家聚焦会话已完成相机过渡")
	var item: AutolysisLiquidTank = _new_world_tank()
	_check(not player.inventory_controller.can_take_liquid_tank(player, item) and not player.inventory_controller.try_take_liquid_tank(player, item) and item.is_available_for_pickup(), "柜外拾取业务接口也不能绕过正式玩家聚焦门禁")
	await _clear_world()


func _fault_scene_path(mode: int) -> String:
	var item: AutolysisLiquidTank = WORLD_SCENE.instantiate() as AutolysisLiquidTank
	if mode == 0:
		item.item_definition = CAFFEINE
	else:
		item.fixed_installation = true
	var packed: PackedScene = PackedScene.new()
	_check(packed.pack(item) == OK, "打包资源故障测试场景")
	item.free()
	var directory: String = ProjectSettings.globalize_path(evidence_directory)
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "创建事务故障证据目录")
	var scene_path: String = evidence_directory.path_join("fault_world_%d.tscn" % mode)
	_check(ResourceSaver.save(packed, scene_path) == OK, "保存可复跑资源故障场景")
	return scene_path


func _test_resource_failures() -> void:
	var invalid_paths: Array[String] = ["res://missing_liquid_tank_scene.tscn", "res://main-autolysis/scenes/prefabs/prefab_raw_materials/rm_caffeine_0.tscn", _fault_scene_path(0), _fault_scene_path(1)]
	for path: String in invalid_paths:
		var fixture: Dictionary = await _fixture()
		var actor: TestActor = fixture["actor"]
		var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
		var definition: AutolysisItemDefinition = TANK.duplicate() as AutolysisItemDefinition
		definition.world_scene_path = path
		_check(actor.inventory.try_receive_item(definition), "世界资源故障用例先建立合法手持显示")
		var display: Node3D = actor.presenter.get_display()
		var old_notifications: int = actor.notifications
		_check(not actor.inventory.can_place_in_liquid_tank_cabinet(actor, cabinet) and not actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet), "缺失、原药根、定义不符或固定装配世界场景被只读查询与执行拒绝")
		_check(actor.inventory.get_focused_item() == definition and actor.presenter.get_display() == display and actor.notifications == old_notifications and _cabinet_count(cabinet) == 0, "资源失败保留当前格、模型和通知次数且不占槽")
		await _clear_world()
	var fixture: Dictionary = await _fixture()
	var actor: TestActor = fixture["actor"]
	var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
	_check(actor.inventory.try_receive_item(CAFFEINE) and not actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet), "原药不能进入液体罐专用柜")
	await _clear_world()
	fixture = await _fixture()
	actor = fixture["actor"]
	cabinet = fixture["cabinet"]
	var definition: AutolysisItemDefinition = TANK.duplicate() as AutolysisItemDefinition
	_check(actor.inventory.try_receive_item(definition) and actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet), "损坏手持资源用例先正常存放")
	var stored: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	definition.visual_scene = null
	var old_notifications: int = actor.notifications
	_check(not actor.inventory.can_take_liquid_tank(actor, stored) and not actor.inventory.try_take_liquid_tank(actor, stored), "取回时损坏纯显示资源拒绝查询和执行")
	_check(cabinet.owns_item(stored) and actor.inventory.get_focused_item() == null and actor.presenter.get_display() == null and actor.notifications == old_notifications, "手持准备失败不释放柜内来源且不通知")
	await _clear_world()


func _test_attachment_failures() -> void:
	for mode: int in range(7):
		var fixture: Dictionary = await _fixture()
		var actor: TestActor = fixture["actor"]
		var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
		var anchor: Node3D = cabinet.get_slot_node(0)
		var definition: AutolysisItemDefinition = TANK.duplicate() as AutolysisItemDefinition
		_check(actor.inventory.try_receive_item(definition), "候选入树故障用例建立当前罐")
		var display: Node3D = actor.presenter.get_display()
		var old_notifications: int = actor.notifications
		var attempt: Dictionary = {"called": false, "toggle": true, "cycle": true}
		anchor.child_entered_tree.connect(func(node: Node) -> void:
			attempt["called"] = true
			attempt["toggle"] = cabinet.try_toggle(actor)
			attempt["cycle"] = actor.inventory.cycle_focus(1)
			match mode:
				0: cabinet.queue_free()
				1: anchor.queue_free()
				2: node.queue_free()
				3: node.set("slot_index", 1)
				4: node.set("item_definition", CAFFEINE)
				5: actor.input_enabled = false
				6: definition.is_raw_material = true
		, CONNECT_ONE_SHOT)
		_check(not actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet) and attempt["called"], "候选入树故障%d拒绝提交并回滚" % mode)
		_check(not attempt["toggle"] and not attempt["cycle"], "候选入树期间关门和切格均由事务锁拒绝")
		_check(actor.inventory.get_slot_item(0) == definition and actor.presenter.get_display() == display and actor.notifications == old_notifications, "入树失败保留来源格、原手持和通知次数")
		if is_instance_valid(cabinet) and not cabinet.is_queued_for_deletion():
			_check(cabinet.get_item_at_slot(0) == null, "失败候选未遗留槽位登记")
		if is_instance_valid(anchor) and not anchor.is_queued_for_deletion():
			_check(anchor.get_child_count() == 0, "失败候选已从场景树移除")
		await _clear_world()


func _test_observer_reentry() -> void:
	var fixture: Dictionary = await _fixture()
	var actor: TestActor = fixture["actor"]
	var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
	_check(actor.inventory.try_receive_item(TANK), "通知重入用例建立当前罐")
	var snapshots: Array[Dictionary] = []
	var callback: Callable = func() -> void:
		var stored: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
		snapshots.append({
			"总数": _inventory_count(actor.inventory) + _cabinet_count(cabinet),
			"空手": actor.inventory.get_focused_item() == null,
			"允许放入": actor.inventory.can_place_in_liquid_tank_cabinet(actor, cabinet),
			"允许取回": actor.inventory.can_take_liquid_tank(actor, stored) if stored != null else false,
			"放入": actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet),
			"取回": actor.inventory.try_take_liquid_tank(actor, stored) if stored != null else false,
			"接收": actor.inventory.try_receive_item(TANK),
			"切格": actor.inventory.cycle_focus(1),
			"关门": cabinet.try_toggle(actor),
		})
	actor.inventory.inventory_changed.connect(callback)
	var old_notifications: int = actor.notifications
	_check(actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet) and snapshots.size() == 1 and actor.notifications == old_notifications + 1, "放入完成只发布一次同步通知")
	var first: Dictionary = snapshots[0]
	_check(first["总数"] == 1 and first["空手"] and first["允许取回"] and not first["允许放入"], "通知只读许可反映已提交空格与柜内占用")
	_check(not first["放入"] and not first["取回"] and not first["接收"] and not first["切格"] and not first["关门"], "放入通知期间所有重入写入和柜门操作被拒绝")
	_check(actor.inventory.try_take_liquid_tank(actor, cabinet.get_item_at_slot(0)) and snapshots.size() == 2, "事务锁释放后指定取回成功且只追加一次通知")
	var second: Dictionary = snapshots[1]
	_check(second["总数"] == 1 and not second["空手"] and second["允许放入"] and not second["允许取回"], "取回通知读取已提交手持与空柜状态")
	_check(not second["放入"] and not second["取回"] and not second["接收"] and not second["切格"] and not second["关门"], "取回通知期间保持库存和柜级事务锁")
	actor.inventory.inventory_changed.disconnect(callback)
	_check(actor.inventory.cycle_focus(1) and cabinet.try_toggle(actor), "通知返回后切格与柜门锁均已释放")
	await _clear_world()


func _test_two_actor_reentry() -> void:
	var fixture: Dictionary = await _fixture()
	var first: TestActor = fixture["actor"]
	var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
	var second: TestActor = _new_actor()
	_check(first.inventory.try_receive_item(TANK) and second.inventory.try_receive_item(TANK), "同槽竞争建立两个独立库存来源")
	var attempt: Dictionary = {"called": false, "result": true}
	cabinet.get_slot_node(0).child_entered_tree.connect(func(_node: Node) -> void:
		attempt["called"] = true
		attempt["result"] = second.inventory.try_place_in_liquid_tank_cabinet(second, cabinet)
	, CONNECT_ONE_SHOT)
	_check(first.inventory.try_place_in_liquid_tank_cabinet(first, cabinet) and attempt["called"] and not attempt["result"], "候选入树时第二角色同柜重入被柜级锁拒绝")
	var placed: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	_check(placed != null and cabinet.owns_item(placed) and cabinet.get_slot_node(0).get_child_count() == 1 and first.inventory.get_focused_item() == null and second.inventory.get_focused_item() == TANK, "竞争保留甲提交及乙来源且零号仅一罐")
	_check(second.inventory.try_place_in_liquid_tank_cabinet(second, cabinet) and cabinet.get_item_at_slot(0) == placed and cabinet.get_item_at_slot(1) != null, "竞争结束后第二角色进入下一空槽且不覆盖首罐")
	_check(_inventory_count(first.inventory) + _inventory_count(second.inventory) + _cabinet_count(cabinet) == 2, "竞争前后两罐总数守恒")
	var unrelated: AutolysisLiquidTank = _new_world_tank()
	cabinet.rollback_prepared_item(unrelated)
	_check(cabinet.get_item_at_slot(0) == placed and _cabinet_count(cabinet) == 2, "回滚无关候选不能清除已提交占用")
	await _clear_world()


func _test_orphaned_storage() -> void:
	var fixture: Dictionary = await _fixture()
	var actor: TestActor = fixture["actor"]
	var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
	_check(actor.inventory.try_receive_item(TANK) and actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet), "失效归属用例先成功存放")
	var stored: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	stored.reparent(world, true)
	_check(not actor.inventory.try_take_liquid_tank(actor, stored), "被移出指定槽的罐不能绕过双向归属取回")
	cabinet.queue_free()
	await _frames(2)
	_check(stored.cabinet_stored and not actor.inventory.can_take_liquid_tank(actor, stored) and not actor.inventory.try_take_liquid_tank(actor, stored), "所属柜失效仍保留曾存柜标记且不能退回无主世界拾取")
	await _clear_world()


func _save_evidence() -> void:
	var directory: String = ProjectSettings.globalize_path(evidence_directory)
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_check(error == OK, "创建事务结果目录")
	if error != OK:
		return
	var report: FileAccess = FileAccess.open(directory.path_join("liquid-tank-transactions.json"), FileAccess.WRITE)
	if report == null:
		_check(false, "事务结果文件可写")
		return
	report.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "记录": records}, "\t"))
	report.close()
