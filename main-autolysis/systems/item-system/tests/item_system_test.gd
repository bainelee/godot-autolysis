extends SceneTree
## 真实道具资源、业务转移与架外物理射线验证；不依赖鼠标捕获或界面。

const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const SODIUM_BENZOATE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/sodium_benzoate.tres")
const CAFFEINE_WORLD: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_raw_materials/rm_caffeine_0.tscn")
const SODIUM_WORLD: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_raw_materials/rm_sodium_benzoate_0.tscn")
const CAFFEINE_GROUP: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_raw_materials/rm_caffeine_group_0.tscn")
const SODIUM_GROUP: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_raw_materials/rm_sodium_benzoate_group_0.tscn")
const SHELF_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/place_shelf_workroom_rm_0.tscn")
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/道具系统p1实施证据/checks")

class TestActor extends Node3D:
	var inventory: AutolysisInventoryController
	var presenter: AutolysisHeldItemPresenter
	var notifications: int = 0
	var reenter: bool = false
	var reentry_item: AutolysisItemDefinition
	var reentry_receive_result: bool = true
	var reentry_place_result: bool = true
	var reentry_focus_result: bool = true
	var observed_shelf: AutolysisRawMaterialShelf
	var observed_empty_hand: bool = false
	var observed_shelf_count: int = -1
	var observed_can_receive: bool = false
	var observed_can_place: bool = false
	var sabotage_shelf: AutolysisRawMaterialShelf
	var handling_notification: bool = false
	var competing_shelf: AutolysisRawMaterialShelf
	var competing_attempted: bool = false
	var competing_place_result: bool = false

	func on_inventory_changed() -> void:
		notifications += 1
		if not reenter or handling_notification:
			return
		handling_notification = true
		observed_empty_hand = inventory.get_focused_item() == null
		observed_shelf_count = 0
		if is_instance_valid(observed_shelf):
			for index: int in range(observed_shelf.get_slot_count()):
				if observed_shelf.get_item_at_slot(index) != null:
					observed_shelf_count += 1
		observed_can_receive = inventory.can_receive_item(reentry_item)
		observed_can_place = inventory.can_place_on_shelf(observed_shelf)
		reentry_receive_result = inventory.try_receive_item(reentry_item)
		reentry_place_result = inventory.try_place_on_shelf(observed_shelf)
		reentry_focus_result = inventory.cycle_focus(1)
		handling_notification = false

	func on_slot_child_entered(_node: Node) -> void:
		if is_instance_valid(sabotage_shelf):
			sabotage_shelf.queue_free()

	func on_competing_slot_child_entered(_node: Node) -> void:
		if competing_attempted:
			return
		competing_attempted = true
		competing_place_result = inventory.try_place_on_shelf(competing_shelf)

var world: Node3D
var failures: int = 0
var assertion_count: int = 0
var ray_records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = Node3D.new()
	world.name = "ItemSystemVerification"
	root.add_child(world)
	await _test_inventory_and_display()
	await _test_groups()
	await _test_world_pickup()
	await _test_shelves_and_conservation()
	await _test_transfer_failures()
	await _test_observer_reentry()
	await _test_two_actor_slot_reentry()
	await _test_slot_rays()
	_save_ray_evidence()
	await _clear_world()
	world.queue_free()
	await _frames(2)
	print("道具系统断言数：", assertion_count, "；失败总数：", failures, "；逐槽射线记录数：", ray_records.size())
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("通过：", message)
	else:
		failures += 1
		print("失败：", message)


func _frames(count: int = 2) -> void:
	for _frame_index: int in range(count):
		await physics_frame
		await process_frame


func _clear_world() -> void:
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
	actor.position = Vector3(20, 20, 20)
	actor.inventory.configure(actor.presenter, func() -> bool: return true)
	actor.inventory.inventory_changed.connect(actor.on_inventory_changed)
	return actor


func _new_shelf(location: Vector3 = Vector3.ZERO) -> AutolysisRawMaterialShelf:
	var shelf: AutolysisRawMaterialShelf = SHELF_SCENE.instantiate() as AutolysisRawMaterialShelf
	world.add_child(shelf)
	shelf.position = location
	return shelf


func _new_world_item(scene: PackedScene, location: Vector3) -> AutolysisRawMaterial:
	var item: AutolysisRawMaterial = scene.instantiate() as AutolysisRawMaterial
	world.add_child(item)
	item.position = location
	return item


func _inventory_count(inventory: AutolysisInventoryController) -> int:
	var count: int = 0
	for index: int in range(4):
		if inventory.get_slot_item(index) != null:
			count += 1
	return count


func _shelf_count(shelf: AutolysisRawMaterialShelf) -> int:
	var count: int = 0
	for index: int in range(shelf.get_slot_count()):
		if shelf.get_item_at_slot(index) != null:
			count += 1
	return count


func _is_pure_visual(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is AutolysisInteractionComponent:
		return false
	if node.get_script() != null or node.is_in_group(&"interactable"):
		return false
	for child: Node in node.get_children():
		if not _is_pure_visual(child):
			return false
	return true


func _test_inventory_and_display() -> void:
	var actor: TestActor = _new_actor()
	var other: TestActor = _new_actor()
	_check(actor.inventory.get_focused_index() == 0 and _inventory_count(actor.inventory) == 0 and actor.presenter.get_display() == null, "初始四格全空、第一格聚焦且无手持模型")
	_check(actor.inventory.get_slot_item(-1) == null and actor.inventory.get_slot_item(4) == null, "道具栏查询不能越过四格范围")
	for step: int in range(1, 5):
		_check(actor.inventory.cycle_focus(1) and actor.inventory.get_focused_index() == step % 4, "向下循环第%d步聚焦正确" % step)
	_check(actor.inventory.cycle_focus(-1) and actor.inventory.get_focused_index() == 3, "第一格向上循环到第四格")
	_check(not actor.inventory.cycle_focus(0) and not actor.inventory.cycle_focus(2) and actor.inventory.get_focused_index() == 3, "非单步方向不改变聚焦")
	actor.inventory.cycle_focus(1)
	_check(actor.inventory.try_receive_item(CAFFEINE), "空手时真实咖啡因进入当前第一格")
	_check(not actor.inventory.try_receive_item(CAFFEINE) and not actor.inventory.try_receive_item(SODIUM_BENZOATE) and _inventory_count(actor.inventory) == 1, "当前格已有道具时不叠加也不转存其他空格")
	actor.inventory.cycle_focus(1)
	_check(actor.inventory.try_receive_item(CAFFEINE) and _inventory_count(actor.inventory) == 2, "相同原药可以分别占用两格")
	actor.inventory.cycle_focus(1)
	_check(actor.inventory.try_receive_item(SODIUM_BENZOATE), "第三格可以持有另一种原药")
	var display: Node3D = actor.presenter.get_display()
	_check(display != null and _is_pure_visual(display) and actor.presenter.get_child_count() == 1, "真实手持模型不含脚本、碰撞或交互并且仅显示一个实例")
	actor.inventory.cycle_focus(1)
	_check(actor.inventory.get_focused_item() == null and actor.presenter.get_display() == null and actor.presenter.get_child_count() == 0, "切换空格立即进入空手并卸下显示")
	actor.inventory.cycle_focus(1)
	_check(actor.inventory.get_focused_item() == CAFFEINE and actor.presenter.get_display() != null and _inventory_count(actor.inventory) == 3, "切回第一格恢复原药显示且其他格内容保留")
	_check(other.inventory.get_focused_index() == 0 and _inventory_count(other.inventory) == 0 and other.presenter.get_display() == null, "两个玩家道具格、聚焦和显示互不共享")
	var notification_count: int = other.notifications
	var child_count: int = other.presenter.get_child_count()
	for _query_index: int in range(10):
		other.inventory.can_receive_item(CAFFEINE)
	_check(other.notifications == notification_count and other.presenter.get_child_count() == child_count and _inventory_count(other.inventory) == 0, "重复接收许可查询不改变道具、不创建显示、不发送变化通知")
	await _clear_world()


func _test_groups() -> void:
	var scenes: Array[PackedScene] = [CAFFEINE_GROUP, SODIUM_GROUP]
	var definitions: Array[AutolysisItemDefinition] = [CAFFEINE, SODIUM_BENZOATE]
	for type_index: int in range(scenes.size()):
		var actor: TestActor = _new_actor()
		var group: AutolysisRawMaterialGroup = scenes[type_index].instantiate() as AutolysisRawMaterialGroup
		world.add_child(group)
		var tray_name: String = "MeshInstance3D15" if type_index == 0 else "meshes"
		var tray: Node3D = group.get_node(tray_name) as Node3D
		var component: AutolysisInteractionComponent = group.get_node("InteractionComponent") as AutolysisInteractionComponent
		var originals: Array[Node] = tray.get_children()
		var transforms: Array[Transform3D] = []
		for child: Node in originals:
			transforms.append((child as Node3D).global_transform)
		_check(originals.size() == 4 and _is_pure_visual(tray), "%s组内四件陈列全部为纯显示" % definitions[type_index].display_name)
		for slot_index: int in range(4):
			_check(component.can_interact(actor) and component.try_interact(actor) and actor.inventory.get_focused_item() == definitions[type_index], "%s组向第%d格提供对应原药" % [definitions[type_index].display_name, slot_index + 1])
			_check(not component.can_interact(actor) and not component.try_interact(actor), "手持时原药组不可再次发放")
			actor.inventory.cycle_focus(1)
		_check(_inventory_count(actor.inventory) == 4 and tray.get_child_count() == 4, "原药组连续发放四次后陈列数保持四件")
		for index: int in range(originals.size()):
			_check(is_instance_valid(originals[index]) and originals[index].get_parent() == tray and (originals[index] as Node3D).global_transform.is_equal_approx(transforms[index]), "原药组第%d件陈列节点及位置未改变" % index)
		await _clear_world()


func _test_world_pickup() -> void:
	var actor: TestActor = _new_actor()
	var first: AutolysisRawMaterial = _new_world_item(CAFFEINE_WORLD, Vector3(0, 0, 0))
	var second: AutolysisRawMaterial = _new_world_item(SODIUM_WORLD, Vector3(1, 0, 0))
	var second_transform: Transform3D = second.global_transform
	var component: AutolysisInteractionComponent = first.get_node("InteractionComponent") as AutolysisInteractionComponent
	_check(component.try_interact(actor) and actor.inventory.get_focused_item() == CAFFEINE, "独立单体通过真实交互组件进入当前格")
	_check(first.is_queued_for_deletion() and not first.visible and first.collision_layer == 0 and not actor.inventory.try_take_world_item(first), "取走的单体立即隐藏、关闭碰撞并拒绝重复拾取")
	_check(second.is_available_for_pickup() and second.global_transform.is_equal_approx(second_transform) and not actor.inventory.try_take_world_item(second), "指定取回不影响相邻原药且手持时不交换")
	actor.inventory.cycle_focus(1)
	_check(actor.inventory.try_take_world_item(second) and actor.inventory.get_focused_item() == SODIUM_BENZOATE and _inventory_count(actor.inventory) == 2, "切换空格后只取走指定的另一件原药")
	var queued: AutolysisRawMaterial = _new_world_item(CAFFEINE_WORLD, Vector3(2, 0, 0))
	actor.inventory.cycle_focus(1)
	queued.queue_free()
	_check(not actor.inventory.can_take_world_item(queued) and not actor.inventory.try_take_world_item(queued) and actor.inventory.get_focused_item() == null, "已排队释放的世界来源不能生成道具")
	var shelf: AutolysisRawMaterialShelf = _new_shelf(Vector3(4, 0, 0))
	var unowned: AutolysisRawMaterial = _new_world_item(CAFFEINE_WORLD, Vector3(5, 0, 0))
	unowned.shelf = shelf
	unowned.slot_index = 0
	_check(not actor.inventory.can_take_world_item(unowned) and not actor.inventory.try_take_world_item(unowned) and _shelf_count(shelf) == 0 and unowned.visible, "伪造架子归属但槽位未登记时拒绝取回且不删除物体")
	await _clear_world()


func _test_shelves_and_conservation() -> void:
	var actor: TestActor = _new_actor()
	var other: TestActor = _new_actor()
	var shelf: AutolysisRawMaterialShelf = _new_shelf()
	var other_shelf: AutolysisRawMaterialShelf = _new_shelf(Vector3(5, 0, 0))
	_check(shelf.get_slot_count() == 36 and other_shelf.get_slot_count() == 36 and shelf.find_first_empty_slot() == 0, "真实原药架各自读取三十六个槽位并从编号零开始")
	for index: int in range(36):
		var definition: AutolysisItemDefinition = CAFFEINE if index % 2 == 0 else SODIUM_BENZOATE
		_check(actor.inventory.try_receive_item(definition) and actor.inventory.try_place_on_shelf(shelf), "混放第%d件原药成功" % (index + 1))
		var item: AutolysisRawMaterial = shelf.get_item_at_slot(index)
		var slot: Node3D = shelf.get_slot_node(index)
		_check(item != null and item.item_definition == definition and shelf.owns_item(item), "第%d件占据相同数字编号的槽位并登记唯一归属" % (index + 1))
		_check(item != null and slot != null and item.global_position.is_equal_approx(slot.global_position) and item.transform.is_equal_approx(Transform3D.IDENTITY), "槽位%d中原药继承旋转架体并与槽位原点重合" % index)
		_check(_inventory_count(actor.inventory) + _shelf_count(shelf) == index + 1, "第%d次放入保持原药总数" % (index + 1))
	_check(_shelf_count(other_shelf) == 0 and _inventory_count(other.inventory) == 0, "填满第一架不改变另一架或另一玩家")
	_check(actor.inventory.try_receive_item(CAFFEINE), "满架前玩家仍可以持有第三十七件原药")
	var display: Node3D = actor.presenter.get_display()
	_check(not actor.inventory.can_place_on_shelf(shelf) and not actor.inventory.try_place_on_shelf(shelf) and _shelf_count(shelf) == 36 and actor.inventory.get_focused_item() == CAFFEINE and actor.presenter.get_display() == display, "满架拒绝第三十七件并保留玩家原药及手持显示")
	var slot_two: AutolysisRawMaterial = shelf.get_item_at_slot(2)
	var slot_ten: AutolysisRawMaterial = shelf.get_item_at_slot(10)
	_check(other.inventory.try_take_world_item(slot_two), "另一玩家指定取回编号二原药")
	other.inventory.cycle_focus(1)
	_check(other.inventory.try_take_world_item(slot_ten), "另一玩家指定取回编号十原药")
	_check(shelf.get_item_at_slot(2) == null and shelf.get_item_at_slot(10) == null and shelf.find_first_empty_slot() == 2 and _shelf_count(shelf) == 34, "同时空出二和十后按数字编号优先选择二")
	_check(actor.inventory.try_place_on_shelf(shelf) and shelf.get_item_at_slot(2) != null and shelf.get_item_at_slot(10) == null, "持有的第三十七件优先补入编号二")
	_check(_inventory_count(actor.inventory) + _inventory_count(other.inventory) + _shelf_count(shelf) + _shelf_count(other_shelf) == 37, "跨玩家取回及补位后总数仍为三十七")
	_check(other.inventory.try_place_on_shelf(other_shelf) and _shelf_count(other_shelf) == 1 and _shelf_count(shelf) == 35, "第二架独立接收原药且第一架占用不变")
	other.inventory.cycle_focus(-1)
	_check(other.inventory.try_place_on_shelf(shelf) and _shelf_count(shelf) == 36 and shelf.get_item_at_slot(10) != null, "编号十空位随后补齐")
	for round_index: int in range(5):
		var item: AutolysisRawMaterial = shelf.get_item_at_slot(5)
		_check(actor.inventory.try_take_world_item(item) and shelf.get_item_at_slot(5) == null and actor.inventory.try_place_on_shelf(shelf), "第%d次指定原药往返架子成功" % (round_index + 1))
		_check(_inventory_count(actor.inventory) + _inventory_count(other.inventory) + _shelf_count(shelf) + _shelf_count(other_shelf) == 37, "第%d次往返后总数守恒" % (round_index + 1))
	await _clear_world()


func _test_transfer_failures() -> void:
	var invalid_paths: Array[String] = ["res://main-autolysis/systems/item-system/tests/不存在的世界场景.tscn", SODIUM_BENZOATE.world_scene_path, "res://main-autolysis/scenes/prefabs/prefab_raw_materials/rm_caffeine_group_0.tscn"]
	for case_index: int in range(invalid_paths.size()):
		var actor: TestActor = _new_actor()
		var shelf: AutolysisRawMaterialShelf = _new_shelf()
		var definition: AutolysisItemDefinition = CAFFEINE.duplicate() as AutolysisItemDefinition
		definition.world_scene_path = invalid_paths[case_index]
		_check(actor.inventory.try_receive_item(definition), "世界资源故障用例%d先建立合法手持显示" % case_index)
		var display: Node3D = actor.presenter.get_display()
		var notifications: int = actor.notifications
		_check(not actor.inventory.can_place_on_shelf(shelf) and not actor.inventory.try_place_on_shelf(shelf) and actor.inventory.get_focused_item() == definition and actor.presenter.get_display() == display and _shelf_count(shelf) == 0 and actor.notifications == notifications, "世界资源故障用例%d在许可查询及放入时均拒绝且道具、显示、架子和通知保持原状" % case_index)
		await _clear_world()
	var actor: TestActor = _new_actor()
	for invalid_visual: PackedScene in [CAFFEINE_WORLD, CAFFEINE_GROUP]:
		var definition: AutolysisItemDefinition = CAFFEINE.duplicate() as AutolysisItemDefinition
		definition.visual_scene = invalid_visual
		_check(not actor.inventory.can_receive_item(definition) and not actor.inventory.try_receive_item(definition) and _inventory_count(actor.inventory) == 0 and actor.presenter.get_display() == null and actor.notifications == 0, "带碰撞和业务脚本的显示场景在许可查询及接收时均拒绝且不产生显示")
	var empty_definition: AutolysisItemDefinition = AutolysisItemDefinition.new()
	_check(not actor.inventory.can_receive_item(null) and not actor.inventory.try_receive_item(empty_definition) and _inventory_count(actor.inventory) == 0, "空定义和缺失必要资源的定义不能进入道具栏")
	await _clear_world()
	actor = _new_actor()
	var interrupted_shelf: AutolysisRawMaterialShelf = _new_shelf()
	actor.sabotage_shelf = interrupted_shelf
	interrupted_shelf.get_slot_node(0).child_entered_tree.connect(actor.on_slot_child_entered)
	_check(actor.inventory.try_receive_item(CAFFEINE), "架子初始化中释放故障用例先持有原药")
	var original_display: Node3D = actor.presenter.get_display()
	var original_notifications: int = actor.notifications
	_check(not actor.inventory.try_place_on_shelf(interrupted_shelf) and interrupted_shelf.is_queued_for_deletion() and actor.inventory.get_focused_item() == CAFFEINE and actor.presenter.get_display() == original_display and actor.notifications == original_notifications, "槽位子节点入树回调使架子排队释放时放入失败且玩家原药保持完整")
	await _clear_world()


func _test_observer_reentry() -> void:
	var actor: TestActor = _new_actor()
	var shelf: AutolysisRawMaterialShelf = _new_shelf()
	_check(actor.inventory.try_receive_item(CAFFEINE), "通知重入用例先持有原药")
	actor.reenter = true
	actor.reentry_item = SODIUM_BENZOATE
	actor.observed_shelf = shelf
	var notifications: int = actor.notifications
	_check(actor.inventory.try_place_on_shelf(shelf), "放入原药时发出提交后的状态通知")
	_check(actor.observed_empty_hand and actor.observed_shelf_count == 1, "通知观察者读取时玩家已空手且架子已登记一件")
	_check(actor.observed_can_receive and not actor.observed_can_place, "放入完成通知内的许可查询反映已提交空格可以接收且不能空手放入")
	_check(not actor.reentry_receive_result and not actor.reentry_place_result and not actor.reentry_focus_result and actor.inventory.get_focused_index() == 0 and actor.inventory.get_focused_item() == null and actor.notifications == notifications + 1, "通知期间再次接收、放入及切格被拒绝且只发送一次通知")
	_check(actor.inventory.try_receive_item(SODIUM_BENZOATE), "通知返回后解除事务锁并接受新的接收请求")
	_check(not actor.observed_empty_hand and not actor.observed_can_receive and actor.observed_can_place and not actor.reentry_place_result and actor.inventory.get_focused_item() == SODIUM_BENZOATE and _shelf_count(shelf) == 1, "获得原药通知内许可查询允许放入但嵌套放入仍被拒绝")
	actor.reenter = false
	await _clear_world()


func _test_two_actor_slot_reentry() -> void:
	var first: TestActor = _new_actor()
	var second: TestActor = _new_actor()
	var shelf: AutolysisRawMaterialShelf = _new_shelf()
	_check(first.inventory.try_receive_item(CAFFEINE) and second.inventory.try_receive_item(SODIUM_BENZOATE), "同槽重入用例中甲乙分别持有不同原药")
	var first_display: Node3D = first.presenter.get_display()
	var first_notifications: int = first.notifications
	var second_notifications: int = second.notifications
	var slot_zero: Node3D = shelf.get_slot_node(0)
	second.competing_shelf = shelf
	slot_zero.child_entered_tree.connect(second.on_competing_slot_child_entered, CONNECT_ONE_SHOT)
	var first_result: bool = first.inventory.try_place_on_shelf(shelf)
	_check(second.competing_attempted and second.competing_place_result and not first_result, "甲挂入零号槽触发乙同步放入时乙成功而甲因槽位冲突失败")
	_check(first.inventory.get_focused_item() == CAFFEINE and first.presenter.get_display() == first_display and first.notifications == first_notifications, "同槽冲突失败后甲的道具、手持显示和通知数保持原状")
	_check(second.inventory.get_focused_item() == null and second.presenter.get_display() == null and second.notifications == second_notifications + 1, "乙成功后当前格清空且只发布一次变化")
	var placed: AutolysisRawMaterial = shelf.get_item_at_slot(0)
	_check(placed != null and placed.item_definition == SODIUM_BENZOATE and shelf.owns_item(placed) and slot_zero.get_child_count() == 1 and slot_zero.get_child(0) == placed, "零号槽仅保留乙的一瓶原药且实际节点与登记记录一致")
	_check(_inventory_count(first.inventory) + _inventory_count(second.inventory) + _shelf_count(shelf) == 2 and shelf.find_first_empty_slot() == 1, "同槽同步重入后总数守恒且下一个空位为一号槽")
	_check(first.inventory.try_place_on_shelf(shelf), "甲在冲突结束后可以正常放入下一空位")
	var next_item: AutolysisRawMaterial = shelf.get_item_at_slot(1)
	_check(next_item != null and next_item.item_definition == CAFFEINE and shelf.owns_item(next_item) and shelf.get_slot_node(1).get_child_count() == 1 and shelf.get_item_at_slot(0) == placed, "甲随后进入一号槽且未覆盖乙的零号槽记录")
	_check(_inventory_count(first.inventory) == 0 and _inventory_count(second.inventory) == 0 and _shelf_count(shelf) == 2 and slot_zero.get_child_count() + shelf.get_slot_node(1).get_child_count() == 2, "两次提交结束后玩家均空手且两槽仅有两瓶原药")
	await _clear_world()


func _cast_ray(origin: Vector3, target: Vector3, mask: int = 3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target)
	query.collision_mask = mask
	query.hit_from_inside = true
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return world.get_world_3d().direct_space_state.intersect_ray(query)


func _vector_values(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _test_slot_rays() -> void:
	var shelf: AutolysisRawMaterialShelf = _new_shelf()
	var scenes: Array[PackedScene] = [CAFFEINE_WORLD, SODIUM_WORLD]
	for scene: PackedScene in scenes:
		for index: int in range(shelf.get_slot_count()):
			var item: AutolysisRawMaterial = scene.instantiate() as AutolysisRawMaterial
			if not shelf.try_attach_item(index, item):
				_check(false, "逐槽射线准备失败：槽位%d" % index)
				item.free()
				continue
			await _frames(2)
			var collision: CollisionShape3D = item.get_node("CollisionShape3D") as CollisionShape3D
			var target: Vector3 = collision.global_position
			var target_local: Vector3 = shelf.to_local(target)
			var origin_local: Vector3 = Vector3(target_local.x, target_local.y, -1.4)
			var origin: Vector3 = shelf.to_global(origin_local)
			var result: Dictionary = _cast_ray(origin, target)
			var collider: Object = result.get("collider", null) as Object
			var hit_position: Vector3 = result.get("position", Vector3.ZERO)
			var hit_path: String = str((collider as Node).get_path()) if collider is Node else "无命中"
			var reachable: bool = collider == item and origin.distance_to(target) <= 2.0 and origin_local.z < -0.4
			ray_records.append({"原药": item.item_definition.display_name, "槽位编号": index, "发射点世界坐标": _vector_values(origin), "发射点架体局部坐标": _vector_values(origin_local), "目标世界坐标": _vector_values(target), "射线长度": origin.distance_to(target), "命中物体": hit_path, "命中世界坐标": _vector_values(hit_position), "命中距离": origin.distance_to(hit_position) if not result.is_empty() else -1.0, "架外两米内命中目标": reachable})
			ray_records.back()["手持状态"] = "空手"
			ray_records.back()["掩码"] = 3
			_check(reachable, "%s在槽位%d可从架外两米内直接命中瓶体" % [item.item_definition.display_name, index])
			var held_result: Dictionary = _cast_ray(origin, target, 19)
			var held_hit: Node = held_result.get("collider") as Node
			var held_position: Vector3 = held_result.get("position", Vector3.ZERO)
			ray_records.append({"原药": item.item_definition.display_name, "槽位编号": index, "手持状态": "原药", "掩码": 19, "发射点世界坐标": _vector_values(origin), "命中物体": str(held_hit.get_path()) if held_hit != null else "无命中", "命中世界坐标": _vector_values(held_position), "命中距离": origin.distance_to(held_position), "命中架体": held_hit == shelf})
			_check(held_hit == shelf, "手持原药时槽位%d方向先命中整体架体" % index)
			_check(shelf.release_item(item), "逐槽验证结束释放槽位%d占用" % index)
			item.finish_pickup()
			await _frames(2)
	_check(ray_records.size() == 144, "两种原药各三十六槽位双状态形成一百四十四条真实射线记录")
	await _test_ray_occlusion(shelf)
	await _clear_world()


func _test_ray_occlusion(shelf: AutolysisRawMaterialShelf) -> void:
	var item: AutolysisRawMaterial = CAFFEINE_WORLD.instantiate() as AutolysisRawMaterial
	var attached: bool = shelf.try_attach_item(0, item)
	_check(attached, "遮挡检查在下层编号零放置原药")
	if not attached:
		item.free()
		return
	await _frames(2)
	var collision: CollisionShape3D = item.get_node("CollisionShape3D") as CollisionShape3D
	var target: Vector3 = collision.global_position
	var local_target: Vector3 = shelf.to_local(target)
	var front: Vector3 = shelf.to_global(Vector3(local_target.x, local_target.y, -1.4))
	var back: Vector3 = shelf.to_global(Vector3(local_target.x, local_target.y, 1.0))
	var back_result: Dictionary = _cast_ray(back, target)
	_check(back_result.get("collider", null) == item, "空手从架后穿过整体盒及视觉背板命中原药")
	var wall: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.05)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_transform = shelf.global_transform * Transform3D(Basis.IDENTITY, Vector3(local_target.x, local_target.y, -0.7))
	await _frames(2)
	var wall_result: Dictionary = _cast_ray(front, target)
	_check(wall_result.get("collider", null) == wall, "普通墙体遮挡时射线首个命中墙而不能穿透取药")
	_check(_cast_ray(front, target, 19).get("collider") == wall, "手持原药也被独立普通墙阻挡")
	wall.global_transform = shelf.global_transform * Transform3D(Basis.IDENTITY, Vector3(local_target.x, local_target.y, 0.2))
	await _frames(2)
	for mask: int in [3, 19]:
		_check(_cast_ray(back, target, mask).get("collider") == wall, "独立背板在两种手持状态下均阻挡")
	wall.queue_free()
	await _frames(2)
	var clear_result: Dictionary = _cast_ray(front, target)
	_check(clear_result.get("collider", null) == item, "移除普通墙后相同射线恢复命中原药")
	var below: Vector3 = shelf.to_global(Vector3(local_target.x, -0.5, local_target.z))
	var board_result: Dictionary = _cast_ray(below, target)
	_check(board_result.get("collider", null) == item, "空手穿过视觉层板命中原药")
	_check(shelf.release_item(item), "遮挡验证结束释放原药占用")
	item.finish_pickup()
	await _frames(2)


func _save_ray_evidence() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(evidence_directory.path_join("slot-rays.json"))
	var directory_result: Error = DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	_check(directory_result == OK, "创建逐槽射线证据目录")
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_check(false, "无法保存逐槽射线证据")
		return
	var document: Dictionary = {"引擎版本": Engine.get_version_info().get("string", ""), "验证说明": "每次仅放置一个待测原药，射线从架体局部前方一点四米处发射；满架及相邻原药业务另行验证。", "生成时间": Time.get_datetime_string_from_system(), "记录数": ray_records.size(), "断言数": assertion_count, "失败数": failures, "逐槽射线": ray_records}
	file.store_string(JSON.stringify(document, "\t"))
	file.close()
	_check(FileAccess.file_exists(absolute_path), "逐槽射线坐标及命中记录已保存")
