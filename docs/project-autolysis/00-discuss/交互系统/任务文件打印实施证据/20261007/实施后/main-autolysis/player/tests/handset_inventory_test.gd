extends SceneTree
## 库存与呈现器专项；只替换聚焦许可，使用正式玩家、设备和全部库存入口。

const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const CAPSULE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/pneumatic_capsule.tres")

class FixtureInventory extends AutolysisInventoryController:
	var focused_source: Node3D
	var accept_actor: bool = true
	var source_dependencies_valid: bool = true

	func _handset_actor_valid(actor: Variant, source: Variant) -> bool:
		return accept_actor and _dependencies_valid() and _node_is_live(actor) and actor is AutolysisPlayer and actor.get_node_or_null("InventoryController") == self and _node_is_live(source) and focused_source == source

	func _committed_handset_source_valid(actor: Node3D, source: Node3D, session: int) -> bool:
		return source_dependencies_valid and source.get("holder") == actor and source.get("session") == session

class FixturePresenter extends AutolysisHeldItemPresenter:
	var fail_preparation: bool = false

	func prepare_handset(scene: PackedScene, position_value: Vector3, rotation_value: Vector3, scale_value: Vector3) -> Node3D:
		return null if fail_preparation else super.prepare_handset(scene, position_value, rotation_value, scale_value)

class FixtureTelephone extends Node3D:
	signal finished()
	signal committing_take()
	signal committing_return()
	var holder: Node3D
	var session: int = 0
	var dock_visible: bool = true
	var completions: int = 0
	var aborts: int = 0
	var release_actor_on_commit: bool = false
	var release_source_on_commit: bool = false
	var free_actor_on_commit: bool = false
	var refuse_commit: bool = false

	func prepare_handset_business_transfer(_actor: Node3D, returning: bool, held_session: int, transaction: int) -> bool:
		return transaction > 0 and (not returning or held_session == session)

	func commit_handset_business_completion(returning: bool, actor: Node3D, held_session: int, transaction: int) -> bool:
		return transaction > 0 and held_session > 0 and ((holder == null and session == 0) if returning else (holder == actor and session == held_session))

	func is_handset_return_blocked(_actor: Node3D, _session: int) -> bool:
		return false

	func commit_take(actor: Node3D, token: int) -> bool:
		if refuse_commit:
			return false
		holder = actor
		session = token
		dock_visible = false
		committing_take.emit()
		if release_actor_on_commit:
			actor.queue_free()
		if release_source_on_commit:
			queue_free()
		if free_actor_on_commit:
			actor.free()
		return true

	func rollback_take() -> void:
		holder = null
		session = 0
		dock_visible = true

	func commit_return() -> bool:
		if refuse_commit:
			return false
		holder = null
		session = 0
		dock_visible = true
		committing_return.emit()
		return true

	func rollback_return(actor: Node3D, held_session: int) -> void:
		holder = actor
		session = held_session
		dock_visible = false

	func notify() -> void:
		completions += 1
		finished.emit()

	func abort_handset_holder(_actor: Node3D, _session: int, _reason: String) -> void:
		aborts += 1
		rollback_take()

var world: Node3D
var player: AutolysisPlayer
var inventory: FixtureInventory
var phone: FixtureTelephone
var other_phone: FixtureTelephone
var visual_scene: PackedScene
var failures: int = 0
var records: Array[Dictionary] = []
var notifications: int = 0
var ordinary_notifications: int = 0
var reentry_blocked: bool = false
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/inventory")


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
	check(DisplayServer.get_name() == "headless", "专项仅运行无图形后端")
	visual_scene = _pure_model()
	await _fixture()
	await _basic_and_bypasses()
	await _pose_cache_and_restore()
	await _failure_and_lifetime()
	await _commit_cancellation_and_new_session()
	await _display_entry_source_failure()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("听筒库存断言.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"失败数": failures, "断言数": records.size(), "记录": records}, "\t"))
	report.close()
	if is_instance_valid(world):
		world.queue_free()
	await frames(3)
	print("听筒库存专项断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)


func _fixture() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	world = Node3D.new()
	root.add_child(world)
	player = PLAYER_SCENE.instantiate() as AutolysisPlayer
	player.get_node("%HeldItemPresenter").set_script(FixturePresenter)
	var old_inventory: Node = player.get_node("InventoryController")
	player.remove_child(old_inventory)
	old_inventory.free()
	inventory = FixtureInventory.new()
	inventory.name = "InventoryController"
	player.add_child(inventory)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	phone = FixtureTelephone.new()
	other_phone = FixtureTelephone.new()
	world.add_child(phone)
	world.add_child(other_phone)
	inventory.focused_source = phone
	inventory.held_item_changed.connect(_on_held_changed)
	inventory.inventory_changed.connect(_on_inventory_changed)
	notifications = 0
	ordinary_notifications = 0
	await frames(2)


func _pure_model(with_collision: bool = false) -> PackedScene:
	var model: Node3D = Node3D.new()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	model.add_child(mesh)
	mesh.owner = model
	if with_collision:
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		model.add_child(collision)
		collision.owner = model
	var packed: PackedScene = PackedScene.new()
	packed.pack(model)
	model.free()
	return packed


func _take(source: FixtureTelephone, position_value: Vector3 = Vector3(0.24, -0.23, -0.48), rotation_value: Vector3 = Vector3(-8, -18, 12)) -> int:
	inventory.focused_source = source
	var token: int = inventory.begin_handset_take(player, source, visual_scene, position_value, rotation_value, Vector3.ONE)
	if token <= 0:
		return 0
	if not inventory.commit_handset_take(player, source, token, source.commit_take.bind(player, token), source.rollback_take, source.notify):
		inventory.cancel_handset_transfer(source, token)
		return 0
	return token


func _return(source: FixtureTelephone) -> bool:
	inventory.focused_source = source
	var session: int = inventory.get_handset_session_id()
	var token: int = inventory.begin_handset_return(player, source)
	if token <= 0:
		return false
	var result: bool = inventory.commit_handset_return(player, source, token, source.commit_return, source.rollback_return.bind(player, session), source.notify)
	if not result:
		inventory.cancel_handset_transfer(source, token)
	return result


func _on_held_changed() -> void:
	notifications += 1


func _on_inventory_changed() -> void:
	ordinary_notifications += 1


func _try_reentry() -> void:
	reentry_blocked = not inventory.cycle_focus(1) and not inventory.try_receive_item(CAFFEINE) and inventory.begin_handset_return(player, phone) == 0


func _basic_and_bypasses() -> void:
	check(inventory.try_receive_item(CAFFEINE), "普通道具先进入第零格")
	check(not inventory.can_take_handset(player, phone), "当前格有物时拒绝取筒")
	var stored: AutolysisItemInstance = inventory.get_focused_instance()
	check(inventory.cycle_focus(1) and inventory.is_actually_empty_handed(), "其他格持物而当前格为空时实际空手")
	var before_revision: int = inventory.get_holding_revision()
	var before_index: int = inventory.get_focused_index()
	var ordinary_before: int = ordinary_notifications
	var notify_before: int = notifications
	var pending: int = inventory.begin_handset_take(player, phone, visual_scene, Vector3(0.24, -0.23, -0.48), Vector3(-8, -18, 12), Vector3.ONE)
	check(pending > 0 and inventory.get_handset_transfer_pending() and not inventory.has_exclusive_handset() and phone.dock_visible, "取下预处理保护移动并保留来源展示")
	check(not inventory.cycle_focus(1) and not inventory.try_receive_item(CAFFEINE), "取下等待期间选格和普通写入拒绝")
	check(inventory.cancel_handset_transfer(phone, pending) and not inventory.get_handset_transfer_pending() and inventory.get_holding_revision() == before_revision, "取消预处理不修改持物事实")
	var session: int = _take(phone)
	check(session > 0 and inventory.has_exclusive_handset() and not phone.dock_visible and inventory.get_handset_display().visible, "同步取下完成来源与手持成对展示")
	check(inventory.get_slot_instance(0) == stored and inventory.get_focused_instance() == null and inventory.get_focused_index() == before_index, "取筒完整保留四格身份和索引")
	check(inventory.get_holding_revision() == before_revision + 1 and notifications == notify_before + 1 and ordinary_notifications == ordinary_before and phone.completions == 1, "持物通知一次且不伪造库存内容通知")
	check(not inventory.cycle_focus(1) and not inventory.cycle_focus(-1), "直接选格两方向均受独占锁保护")
	var scene_node: Node3D = _pure_model().instantiate() as Node3D
	player.held_item_presenter.commit_prepared(scene_node)
	check(player.held_item_presenter.get_display() == inventory.get_handset_display() and scene_node.get_parent() == null, "呈现器普通写入入口不能覆盖独占显示")
	scene_node.free()
	inventory.focused_source = other_phone
	check(not inventory.can_take_handset(player, other_phone) and not inventory.can_return_handset(player, other_phone), "另一电话不能取筒或解除原来源锁")
	inventory.focused_source = phone
	await _check_all_bypasses()
	phone.finished.connect(_try_reentry)
	check(_return(phone) and reentry_blocked, "归还来源通知期间继续拒绝观察重入")
	check(not inventory.has_exclusive_handset() and phone.dock_visible and inventory.get_handset_display() == null and inventory.get_slot_instance(0) == stored and inventory.get_focused_index() == before_index, "同步归还清独占显示且保留原库存")
	check(inventory.cycle_focus(1) and inventory.cycle_focus(-1), "归还后两方向选格恢复")
	check(not inventory.cancel_handset_transfer(phone, pending) and not inventory.abort_handset_session(phone, session, "旧会话"), "旧取消与旧异常回调不修改新事实")


func _add_asset(path: String) -> Node:
	var node: Node = load(path).instantiate()
	world.add_child(node)
	return node


func _find_script_class(node: Node, script_class: StringName) -> Node:
	var script: Script = node.get_script() as Script
	if script != null and script.get_global_name() == script_class:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_script_class(child, script_class)
		if found != null:
			return found
	return null


func _check_all_bypasses() -> void:
	var raw: AutolysisRawMaterial = _add_asset("res://main-autolysis/scenes/prefabs/prefab_raw_materials/rm_caffeine_0.tscn") as AutolysisRawMaterial
	var shelf: AutolysisRawMaterialShelf = _find_script_class(_add_asset("res://main-autolysis/scenes/prefabs/prefab_place_shelf/place_shelf_workroom_rm_0.tscn"), &"AutolysisRawMaterialShelf") as AutolysisRawMaterialShelf
	var blend: Node = _add_asset("res://main-autolysis/scenes/prefabs/prefab_machines/machine_blend_0.tscn")
	var slot: AutolysisBlendSlot = _find_script_class(blend, &"AutolysisBlendSlot") as AutolysisBlendSlot
	var blend_place: AutolysisBlendTankPlace = _find_script_class(blend, &"AutolysisBlendTankPlace") as AutolysisBlendTankPlace
	var tank: AutolysisLiquidTank = _find_script_class(_add_asset("res://main-autolysis/scenes/prefabs/prefab_machines/liquid_tank_0.tscn"), &"AutolysisLiquidTank") as AutolysisLiquidTank
	var cabinet: AutolysisLiquidTankCabinet = _find_script_class(_add_asset("res://main-autolysis/scenes/prefabs/prefab_place_shelf/cabinet_workroom_0.tscn"), &"AutolysisLiquidTankCabinet") as AutolysisLiquidTankCabinet
	var packing: Node = _add_asset("res://main-autolysis/scenes/prefabs/prefab_machines/machine_packing_0.tscn")
	var packing_tank: AutolysisPackingTankPlace = _find_script_class(packing, &"AutolysisPackingTankPlace") as AutolysisPackingTankPlace
	var packing_capsule: AutolysisPackingCapsulePlace = _find_script_class(packing, &"AutolysisPackingCapsulePlace") as AutolysisPackingCapsulePlace
	var capsule: AutolysisPneumaticCapsule = _find_script_class(_add_asset(CAPSULE.world_scene_path), &"AutolysisPneumaticCapsule") as AutolysisPneumaticCapsule
	var waste: AutolysisWasteLiquidStorageTank = _find_script_class(_add_asset("res://main-autolysis/scenes/prefabs/prefab_machines/waste_liquid_storage_tank_0.tscn"), &"AutolysisWasteLiquidStorageTank") as AutolysisWasteLiquidStorageTank
	await frames(2)
	check(raw != null and shelf != null and slot != null and blend_place != null and tank != null and cabinet != null and packing_tank != null and packing_capsule != null and capsule != null and waste != null, "全部旁路使用实际已实例化设备")
	var source_instance: AutolysisItemInstance = raw.item_instance
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(CAFFEINE)
	var calls: Array[Dictionary] = [
		{"名": "普通定义许可", "调用": inventory.can_receive_item.bind(CAFFEINE)},
		{"名": "普通定义接收", "调用": inventory.try_receive_item.bind(CAFFEINE)},
		{"名": "普通实例许可", "调用": inventory.can_receive_instance.bind(instance)},
		{"名": "普通实例接收", "调用": inventory.try_receive_instance.bind(instance)},
		{"名": "世界原药许可", "调用": inventory.can_take_world_item.bind(raw)},
		{"名": "世界原药获取", "调用": inventory.try_take_world_item.bind(raw)},
		{"名": "原药架许可", "调用": inventory.can_place_on_shelf.bind(shelf)},
		{"名": "原药架放置", "调用": inventory.try_place_on_shelf.bind(shelf)},
		{"名": "配药槽放置许可", "调用": inventory.can_place_in_blend_slot.bind(player, slot)},
		{"名": "配药槽放置", "调用": inventory.try_place_in_blend_slot.bind(player, slot)},
		{"名": "配药槽获取许可", "调用": inventory.can_take_from_blend_slot.bind(player, slot)},
		{"名": "配药槽获取", "调用": inventory.try_take_from_blend_slot.bind(player, slot)},
		{"名": "液体罐获取许可", "调用": inventory.can_take_liquid_tank.bind(player, tank)},
		{"名": "液体罐获取", "调用": inventory.try_take_liquid_tank.bind(player, tank)},
		{"名": "专用柜放置许可", "调用": inventory.can_place_in_liquid_tank_cabinet.bind(player, cabinet)},
		{"名": "专用柜放置", "调用": inventory.try_place_in_liquid_tank_cabinet.bind(player, cabinet)},
		{"名": "配药罐位放置许可", "调用": inventory.can_place_in_blend_tank_place.bind(player, blend_place)},
		{"名": "配药罐位放置", "调用": inventory.try_place_in_blend_tank_place.bind(player, blend_place)},
		{"名": "配药罐位获取许可", "调用": inventory.can_take_from_blend_tank_place.bind(player, blend_place)},
		{"名": "配药罐位获取", "调用": inventory.try_take_from_blend_tank_place.bind(player, blend_place)},
		{"名": "配药罐别名放置许可", "调用": inventory.can_place_in_blend_tank.bind(player, blend_place)},
		{"名": "配药罐别名放置", "调用": inventory.try_place_in_blend_tank.bind(player, blend_place)},
		{"名": "配药罐别名获取许可", "调用": inventory.can_take_from_blend_tank.bind(player, blend_place)},
		{"名": "配药罐别名获取", "调用": inventory.try_take_from_blend_tank.bind(player, blend_place)},
		{"名": "封装罐位放置许可", "调用": inventory.can_place_in_packing_tank_place.bind(player, packing_tank)},
		{"名": "封装罐位放置", "调用": inventory.try_place_in_packing_tank_place.bind(player, packing_tank)},
		{"名": "封装罐位选格存放", "调用": inventory.try_store_selected_in_packing_tank_place.bind(player, packing_tank)},
		{"名": "封装罐位获取许可", "调用": inventory.can_take_from_packing_tank_place.bind(player, packing_tank)},
		{"名": "封装罐位获取", "调用": inventory.try_take_from_packing_tank_place.bind(player, packing_tank)},
		{"名": "封装胶囊放置许可", "调用": inventory.can_place_in_packing_capsule_place.bind(player, packing_capsule)},
		{"名": "封装胶囊放置", "调用": inventory.try_place_in_packing_capsule_place.bind(player, packing_capsule)},
		{"名": "封装胶囊选格存放", "调用": inventory.try_store_selected_in_packing_capsule_place.bind(player, packing_capsule)},
		{"名": "封装胶囊获取许可", "调用": inventory.can_take_from_packing_capsule_place.bind(player, packing_capsule)},
		{"名": "封装胶囊获取", "调用": inventory.try_take_from_packing_capsule_place.bind(player, packing_capsule)},
		{"名": "世界胶囊许可", "调用": inventory.can_take_pneumatic_capsule.bind(player, capsule)},
		{"名": "世界胶囊获取", "调用": inventory.try_take_pneumatic_capsule.bind(player, capsule)},
		{"名": "废液处置许可", "调用": inventory.can_dispose_in_waste_tank.bind(player, waste)},
		{"名": "废液处置", "调用": inventory.try_dispose_in_waste_tank.bind(player, waste)}]
	var display: Node3D = inventory.get_handset_display()
	var revision: int = inventory.get_holding_revision()
	for entry: Dictionary in calls:
		check(entry["调用"].call() == false, "独占持筒拒绝" + entry["名"])
	check(raw.item_instance == source_instance and raw.is_available_for_pickup() and inventory.get_handset_display() == display and inventory.get_holding_revision() == revision, "全部普通旁路不改变来源或听筒表现")


func _pose_cache_and_restore() -> void:
	var session: int = _take(phone)
	var display: Node3D = inventory.get_handset_display()
	var parent_transform: Transform3D = player.held_item_presenter.transform
	var position_value: Vector3 = Vector3(-0.1234567, 0.3456789, -0.9012345)
	var rotation_value: Vector3 = Vector3(-48.25, 117.75, -24.125)
	check(inventory.apply_handset_pose(phone, display, session, position_value, rotation_value), "六轴正负小数可应用到当前听筒")
	check(display.position.is_equal_approx(position_value) and display.rotation_degrees.is_equal_approx(rotation_value) and player.held_item_presenter.transform == parent_transform, "六轴只改变听筒子模型局部变换")
	check(not inventory.apply_handset_pose(other_phone, display, session, Vector3.ZERO, Vector3.ZERO) and not inventory.apply_handset_pose(phone, display, session - 1, Vector3.ZERO, Vector3.ZERO), "来源与旧序号姿态回调拒绝")
	check(not inventory.apply_handset_pose(phone, display, session, Vector3(INF, 0, 0), Vector3.ZERO), "非有限数值不形成姿态")
	display.queue_free()
	await frames(3)
	var restored: Node3D = inventory.get_handset_display()
	check(is_instance_valid(restored) and restored != display and restored.position.is_equal_approx(position_value) and inventory.get_handset_session_id() == session and not phone.dock_visible, "显示异常释放按当前运行姿态恢复并保留来源会话")
	check(_return(phone), "恢复显示后原来源可归还")
	var second_session: int = _take(phone, Vector3(9, 8, 7), Vector3(6, 5, 4))
	check(second_session != session and inventory.get_handset_display().position.is_equal_approx(position_value) and inventory.get_handset_pose_snapshot()["position"].is_equal_approx(position_value), "本次运行同电话再取沿用缓存且起始快照来自缓存")
	check(not inventory.abort_handset_session(phone, session, "过时会话") and inventory.get_handset_session_id() == second_session, "旧异常回调不清新占用")
	check(_return(phone), "缓存会话正常归还")
	var alternate: Vector3 = Vector3(-2, 3, -4)
	check(_take(other_phone, alternate, Vector3(1, 2, 3)) > 0 and inventory.get_handset_display().position == alternate, "另一电话使用自己的配置而非原电话缓存")
	check(_return(other_phone), "另一电话可归还自身听筒")
	check(_take(phone) > 0 and inventory.get_handset_display().position.is_equal_approx(position_value), "另一电话调节不会覆盖原电话缓存")
	check(_return(phone), "缓存隔离后原电话仍可归还")


func _abort_from_observer() -> void:
	if inventory.has_exclusive_handset():
		inventory.abort_handset_session(phone, inventory.get_handset_session_id(), "观察者故障注入")


func _observe_nested_cleanup_lock() -> void:
	reentry_blocked = not inventory.try_receive_item(CAFFEINE) and not inventory.cycle_focus(1)


func _commit_and_free_source(source: FixtureTelephone, actor: Node3D, token: int) -> bool:
	source.commit_take(actor, token)
	# 外部回调释放来源；不能在对象自身执行调用时释放它，引擎禁止该操作。
	source.free()
	return true


func _free_source_from_observer() -> void:
	if inventory.has_exclusive_handset() and is_instance_valid(phone):
		phone.free()


func _queue_display_during_entry(display: Node) -> void:
	(display as Node3D).visibility_changed.connect(_queue_visible_display.bind(display))


func _queue_visible_display(display: Node3D) -> void:
	if display.visible:
		display.queue_free()


func _free_source_during_display_entry(_display: Node) -> void:
	phone.free()


func _free_source_during_display_exit() -> void:
	phone.free()


func _queue_player_during_display_exit() -> void:
	# 子节点正在移除时不能立即释放其祖先；采用引擎支持的排队释放。
	player.queue_free()


func _invalidate_source_during_display_entry(_display: Node) -> void:
	inventory.source_dependencies_valid = false


func _display_entry_source_failure() -> void:
	await _fixture()
	player.held_item_presenter.child_entered_tree.connect(_invalidate_source_during_display_entry)
	var before_notifications: int = notifications
	var revision: int = inventory.get_holding_revision()
	check(_take(phone) == 0, "模型入树后必要来源复核失败不完成取下")
	check(not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and phone.dock_visible and phone.holder == null and phone.completions == 0 and phone.aborts == 1, "模型入树来源失败成对回滚占用与显示")
	check(notifications == before_notifications and inventory.get_holding_revision() == revision, "未完成取下的临时占用失败不发布持物变化或增加持物修订")
	player.held_item_presenter.child_entered_tree.disconnect(_invalidate_source_during_display_entry)
	inventory.source_dependencies_valid = true
	await frames(3)
	check(_take(phone) > 0 and _return(phone), "模型入树来源失败修复后可建立并归还下一会话")


func _abort_during_source_commit() -> void:
	var session: int = inventory.get_handset_session_id()
	if session <= 0:
		session = phone.session
	inventory.abort_handset_session(phone, session, "来源提交同步观察取消")


func _abort_and_start_new_take() -> void:
	phone.committing_take.disconnect(_abort_and_start_new_take)
	_abort_during_source_commit()
	_take(phone, Vector3(-0.5, 0.4, -0.7), Vector3(14, 28, 42))


func _commit_cancellation_and_new_session() -> void:
	await _fixture()
	phone.committing_take.connect(_abort_during_source_commit)
	var token: int = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	check(not inventory.commit_handset_take(player, phone, token, phone.commit_take.bind(player, token), phone.rollback_take, phone.notify), "取下来源同步观察取消后不继续读取旧姿态或提交")
	check(not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and phone.dock_visible and phone.completions == 0 and phone.aborts == 1, "取下来源同步取消只异常清理且不发布正常完成")
	await _fixture()
	check(_take(phone) > 0, "归还来源同步取消夹具取下")
	phone.committing_return.connect(_abort_during_source_commit)
	var held_session: int = inventory.get_handset_session_id()
	var revision: int = inventory.get_holding_revision()
	token = inventory.begin_handset_return(player, phone)
	check(not inventory.commit_handset_return(player, phone, token, phone.commit_return, phone.rollback_return.bind(player, held_session), phone.notify), "归还来源同步观察取消后不继续提交或回滚旧来源")
	check(not inventory.has_exclusive_handset() and phone.dock_visible and phone.holder == null and phone.completions == 1 and phone.aborts == 1 and inventory.get_holding_revision() == revision + 1, "归还来源同步取消不误报完成或重复增加持物修订")
	await _fixture()
	phone.committing_take.connect(_abort_and_start_new_take)
	token = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	check(not inventory.commit_handset_take(player, phone, token, phone.commit_take.bind(player, token), phone.rollback_take, phone.notify), "来源同步观察取消并重入新会话后旧提交拒绝")
	var new_session: int = inventory.get_handset_session_id()
	check(new_session > token and phone.session == new_session and phone.holder == player and not phone.dock_visible and inventory.get_handset_display().position.is_equal_approx(Vector3(-0.5, 0.4, -0.7)) and phone.completions == 1, "旧取下回调不回滚或清除后来建立的占用与显示")
	check(_return(phone), "来源回调新会话仍可正常归还")


func _failure_and_lifetime() -> void:
	await _fixture()
	check(inventory.begin_handset_take(player, phone, _pure_model(true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE) == 0 and phone.dock_visible and not inventory.get_handset_transfer_pending(), "碰撞模型准备失败保留来源且不留互斥")
	var token: int = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	player.focus_controller.session_id += 1
	check(not inventory.is_handset_transfer_current(player, phone, token) and not inventory.commit_handset_take(player, phone, token, phone.commit_take.bind(player, token), phone.rollback_take, phone.notify), "等待后聚焦会话变化拒绝成对提交")
	check(inventory.cancel_handset_transfer(phone, token) and phone.dock_visible, "失败预处理由来源物理恢复后显式取消")
	phone.refuse_commit = true
	token = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	check(not inventory.commit_handset_take(player, phone, token, phone.commit_take.bind(player, token), phone.rollback_take, phone.notify) and inventory.get_handset_transfer_pending(), "来源提交失败不提前解除移动保护")
	check(inventory.cancel_handset_transfer(phone, token) and not inventory.has_exclusive_handset(), "失败来源恢复后取消可释放互斥")
	phone.refuse_commit = false
	inventory.held_item_changed.connect(_abort_from_observer)
	inventory.held_item_changed.connect(_observe_nested_cleanup_lock)
	var before: int = phone.completions
	_take(phone)
	check(not inventory.has_exclusive_handset() and phone.dock_visible and phone.completions == before and phone.aborts == 1, "持物观察者异常终止抑制过时取下完成通知")
	check(reentry_blocked, "嵌套异常清理通知返回后外层观察仍保持写入互斥")
	inventory.held_item_changed.disconnect(_abort_from_observer)
	inventory.held_item_changed.disconnect(_observe_nested_cleanup_lock)
	check(_take(phone) > 0, "异常观察后可建立新会话")
	check(inventory.get_handset_display().position.is_equal_approx(Vector3(0.24, -0.23, -0.48)), "场景重启后的新库存不沿用上一运行调节缓存")
	phone.refuse_commit = true
	var held_session: int = inventory.get_handset_session_id()
	token = inventory.begin_handset_return(player, phone)
	check(not inventory.commit_handset_return(player, phone, token, phone.commit_return, phone.rollback_return.bind(player, held_session), phone.notify) and inventory.has_exclusive_handset() and not phone.dock_visible, "放回提交失败保留持有和来源状态")
	check(inventory.cancel_handset_transfer(phone, token) and inventory.has_exclusive_handset(), "放回失败恢复后取消只解事务互斥")
	phone.refuse_commit = false
	check(_return(phone), "放回失败恢复后可再次正常归还")
	check(_take(phone) > 0, "必要呈现器释放夹具取下")
	player.held_item_presenter.queue_free()
	await frames(3)
	check(not inventory.has_exclusive_handset() and phone.dock_visible and phone.aborts >= 2, "必要呈现器失效按匹配会话异常终止")
	await _fixture()
	check(_take(phone) > 0, "来源释放夹具取下")
	phone.queue_free()
	await frames(3)
	check(not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and player.held_item_presenter.get_display() == null, "来源卸载解除存活玩家显示和占用")
	await _fixture()
	check(_take(phone) > 0, "玩家释放夹具取下")
	player.queue_free()
	await frames(3)
	check(phone.dock_visible and phone.holder == null and phone.aborts == 1, "玩家卸载成对恢复仍存活来源且清理一次")
	await _fixture()
	phone.release_actor_on_commit = true
	token = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	check(not inventory.commit_handset_take(player, phone, token, phone.commit_take.bind(player, token), phone.rollback_take, phone.notify), "来源提交边界排队释放玩家不会完成取下")
	await frames(3)
	check(phone.dock_visible and phone.holder == null and phone.completions == 0, "提交边界玩家释放不留下半提交来源")
	await _fixture()
	phone.release_source_on_commit = true
	token = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	check(not inventory.commit_handset_take(player, phone, token, phone.commit_take.bind(player, token), phone.rollback_take, phone.notify), "来源提交边界排队释放自身不会完成取下")
	await frames(3)
	check(not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and player.held_item_presenter.get_display() == null, "提交边界来源释放不留下永久锁或显示")
	await _fixture()
	token = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	check(not inventory.commit_handset_take(player, phone, token, _commit_and_free_source.bind(phone, player, token), phone.rollback_take, phone.notify), "来源提交边界立即释放来源不完成取下")
	await frames(3)
	check(not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and player.held_item_presenter.get_display() == null, "已释放来源引用可安全幂等清理")
	await _fixture()
	phone.free_actor_on_commit = true
	token = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	var local_inventory: FixtureInventory = inventory
	var commit_callback: Callable = phone.commit_take.bind(player, token)
	var rollback_callback: Callable = phone.rollback_take
	var notify_callback: Callable = phone.notify
	check(not local_inventory.commit_handset_take(player, phone, token, commit_callback, rollback_callback, notify_callback), "来源提交边界立即释放玩家不完成取下")
	await frames(3)
	check(phone.dock_visible and phone.holder == null and phone.completions == 0, "已释放玩家与库存调用返回后来源安全回滚")
	await _fixture()
	check(_take(phone) > 0, "显示恢复失败夹具取下")
	(player.held_item_presenter as FixturePresenter).fail_preparation = true
	inventory.get_handset_display().queue_free()
	await frames(3)
	check(not inventory.has_exclusive_handset() and phone.dock_visible and phone.aborts == 1 and inventory.last_handset_abort_reason.contains("无法按当前配置恢复"), "显示恢复确实失败才异常终止并保存原因")
	await _fixture()
	inventory.held_item_changed.connect(_free_source_from_observer)
	token = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	check(inventory.commit_handset_take(player, phone, token, phone.commit_take.bind(player, token), phone.rollback_take, phone.notify), "持物提交完成后观察者允许立即释放来源")
	await frames(3)
	check(not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and player.held_item_presenter.get_display() == null, "持物通知来源立即释放成对清理且无旧完成调用")
	await _fixture()
	player.held_item_presenter.child_entered_tree.connect(_queue_display_during_entry)
	token = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	check(not inventory.commit_handset_take(player, phone, token, phone.commit_take.bind(player, token), phone.rollback_take, phone.notify), "显示入树观察者接入可见性释放候选时回滚成对来源")
	player.held_item_presenter.child_entered_tree.disconnect(_queue_display_during_entry)
	check(inventory.cancel_handset_transfer(phone, token) and phone.dock_visible and not inventory.has_exclusive_handset(), "候选入树释放失败后来源恢复且互斥可取消")
	await frames(3)
	check(inventory.try_receive_item(CAFFEINE) and player.held_item_presenter.get_display() != null, "候选失败回滚同时清除呈现器独占锁")
	await _fixture()
	player.held_item_presenter.child_entered_tree.connect(_free_source_during_display_entry)
	token = inventory.begin_handset_take(player, phone, visual_scene, Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	check(not inventory.commit_handset_take(player, phone, token, phone.commit_take.bind(player, token), phone.rollback_take, phone.notify), "显示入树观察者立即释放来源时不发布完成")
	player.held_item_presenter.child_entered_tree.disconnect(_free_source_during_display_entry)
	await frames(3)
	check(not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and player.held_item_presenter.get_display() == null and inventory.cycle_focus(1), "显示入树来源释放可安全清理双方独占并恢复下一输入")
	await _fixture()
	check(_take(phone) > 0, "归还移除显示释放来源夹具取下")
	inventory.get_handset_display().tree_exiting.connect(_free_source_during_display_exit)
	check(_return(phone), "归还已成对提交后显示离树观察可立即释放来源")
	await frames(3)
	check(not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and player.held_item_presenter.get_display() == null and inventory.cycle_focus(1), "归还显示释放来源不留下半提交或永久锁")
	await _fixture()
	check(_take(phone) > 0, "归还移除显示释放玩家夹具取下")
	inventory.get_handset_display().tree_exiting.connect(_queue_player_during_display_exit)
	check(_return(phone), "归还已成对提交后显示离树观察可排队释放玩家")
	await frames(3)
	check(phone.dock_visible and phone.holder == null and phone.completions == 1, "归还玩家释放来源保持已归还且不补发过时完成")
