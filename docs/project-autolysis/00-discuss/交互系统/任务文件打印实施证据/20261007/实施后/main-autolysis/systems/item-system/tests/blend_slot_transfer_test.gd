extends SceneTree
## 正式玩家、正式设备与正式入口的同步转移验证；故障通过信号边界注入。

const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
const MACHINE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/machine_blend_0.tscn")
const SHELF_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/place_shelf_workroom_rm_0.tscn")
const WORLD_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_raw_materials/rm_caffeine_0.tscn")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const SODIUM: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/sodium_benzoate.tres")

var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/聚焦交互与原药混合器p1实施证据/自动检查/槽位事务")
var world: Node3D
var failures: int = 0
var assertion_count: int = 0
var records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	if "--immediate-free-probe" in OS.get_cmdline_user_args():
		await _test_immediate_free_probe()
		_save_evidence()
		world.queue_free()
		await _frames(2)
		print("立即释放边界探测断言数：", assertion_count, "；失败总数：", failures)
		quit(1 if failures > 0 else 0)
		return
	await _test_round_trips()
	await _test_busy_and_selected_slot()
	await _test_invalid_resources()
	await _test_attachment_failures()
	await _test_observer_reentry()
	await _test_two_actor_reentry()
	await _test_device_pickup_exclusion()
	_save_evidence()
	world.queue_free()
	await _frames(2)
	print("混合槽位事务断言数：", assertion_count, "；失败总数：", failures)
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


func _wait_slot_state(slot: AutolysisBlendSlot, opened: bool) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while slot.is_animating() and Time.get_ticks_msec() < deadline:
		await _frames(1)
	_check(slot.is_open() if opened else slot.is_closed(), "对应槽门在失败上限内完成目标动作；%s" % slot.get_motion_error())


func _clear_world() -> void:
	for child: Node in world.get_children():
		child.queue_free()
	await _frames(2)


func _new_player() -> AutolysisPlayer:
	var player: AutolysisPlayer = PLAYER_SCENE.instantiate() as AutolysisPlayer
	world.add_child(player)
	player.position = Vector3(10, 0, 10)
	player.set_physics_process(false)
	# 事务测试使用真实会话，入口许可独立于无图形后端的鼠标模式。
	player.focus_controller.configure(player, player.camera, player.held_item_presenter, func() -> bool: return true)
	return player


func _fixture(open_slots: bool = true) -> Dictionary:
	var player: AutolysisPlayer = _new_player()
	var machine: Node3D = MACHINE_SCENE.instantiate() as Node3D
	world.add_child(machine)
	var target: AutolysisFocusTarget = machine.get_node("FocusTarget") as AutolysisFocusTarget
	_check(player.focus_controller.try_enter(target), "正式聚焦控制器接受合法设备")
	await _frames(18)
	_check(player.focus_controller.is_focused_on(target), "真实相机过渡完成后建立稳定会话")
	var slots: Array[AutolysisBlendSlot] = []
	for index: int in range(4):
		var slot: AutolysisBlendSlot = machine.get_node("blend_slot_%d" % index) as AutolysisBlendSlot
		slots.append(slot)
		if open_slots:
			var component: AutolysisInteractionComponent = slot.get_node("InteractionComponent") as AutolysisInteractionComponent
			_check(component.try_interact(player), "通过正式开闭组件打开第%d槽" % index)
	if open_slots:
		for slot: AutolysisBlendSlot in slots:
			await _wait_slot_state(slot, true)
	return {"player": player, "machine": machine, "target": target, "slots": slots}


func _inventory_count(inventory: AutolysisInventoryController) -> int:
	var count: int = 0
	for index: int in range(4):
		if inventory.get_slot_item(index) != null:
			count += 1
	return count


func _stored_count(slots: Array[AutolysisBlendSlot]) -> int:
	var count: int = 0
	for slot: AutolysisBlendSlot in slots:
		if is_instance_valid(slot) and slot.get_stored_item() != null:
			count += 1
	return count


func _observe(inventory: AutolysisInventoryController) -> Dictionary:
	var result: Dictionary = {"notifications": 0}
	inventory.inventory_changed.connect(func() -> void: result["notifications"] += 1)
	return result


func _test_round_trips() -> void:
	var fixture: Dictionary = await _fixture()
	var player: AutolysisPlayer = fixture["player"]
	var inventory: AutolysisInventoryController = player.inventory_controller
	var slots: Array[AutolysisBlendSlot] = fixture["slots"]
	var observation: Dictionary = _observe(inventory)
	for definition: AutolysisItemDefinition in [CAFFEINE, SODIUM]:
		for slot_index: int in [3, 1, 0, 2]:
			var slot: AutolysisBlendSlot = slots[slot_index]
			_check(inventory.try_receive_item(definition), "当前道具格接收%s" % definition.display_name)
			var focused_index: int = inventory.get_focused_index()
			var old_notifications: int = observation["notifications"]
			var transfer: AutolysisInteractionComponent = slot.raw_material_anchor.get_node("InteractionComponent") as AutolysisInteractionComponent
			_check(transfer.can_interact(player) and transfer.try_interact(player), "正式取放入口将%s放入指定第%d槽" % [definition.display_name, slot_index])
			var item: AutolysisRawMaterial = slot.get_stored_item()
			_check(item != null and item.item_definition == definition and slot.owns_item(item), "指定槽位、定义和双向归属一致")
			_check(item != null and item.get_parent() == slot.raw_material_anchor and item.transform.is_equal_approx(Transform3D.IDENTITY), "世界原药使用原锚点及单位局部姿态")
			_check(item != null and item.device_stored and item.blend_slot == slot and item.collision_layer == 0 and item.collision_mask == 0 and not item.is_in_group(&"interactable"), "存放原药关闭自身碰撞与交互分组")
			_check(inventory.get_focused_index() == focused_index and inventory.get_focused_item() == null and player.held_item_presenter.get_display() == null, "放入清空当前格及手持并保持选中格")
			_check(_inventory_count(inventory) + _stored_count(slots) == 1 and observation["notifications"] == old_notifications + 1, "放入总数守恒且只通知一次")
			_check(not inventory.can_take_world_item(item) and not inventory.try_take_world_item(item), "普通世界拾取不能绕过设备取放入口")
			_check(transfer.can_interact(player) and transfer.try_interact(player), "正式取放入口取回指定第%d槽" % slot_index)
			_check(slot.get_stored_item() == null and inventory.get_focused_item() == definition and inventory.get_focused_index() == focused_index, "取回写入原当前格且清空指定槽位")
			_check(item.is_queued_for_deletion() and not item.visible and player.held_item_presenter.get_display() != null, "取回立即隐藏世界实例并提交手持显示")
			_check(_inventory_count(inventory) + _stored_count(slots) == 1 and observation["notifications"] == old_notifications + 2, "取回总数守恒且只追加一次通知")
			# 再存入架子释放当前格，下一组合继续独立验证。
			var shelf: AutolysisRawMaterialShelf = SHELF_SCENE.instantiate() as AutolysisRawMaterialShelf
			world.add_child(shelf)
			_check(inventory.try_place_on_shelf(shelf), "设备取回后仍能使用既有原药架")
			shelf.queue_free()
			await _frames(2)
	await _clear_world()


func _test_busy_and_selected_slot() -> void:
	var fixture: Dictionary = await _fixture(false)
	var player: AutolysisPlayer = fixture["player"]
	var inventory: AutolysisInventoryController = player.inventory_controller
	var slots: Array[AutolysisBlendSlot] = fixture["slots"]
	var slot: AutolysisBlendSlot = slots[2]
	var component: AutolysisInteractionComponent = slot.get_node("InteractionComponent") as AutolysisInteractionComponent
	_check(inventory.try_receive_item(CAFFEINE), "关闭和运动拒绝用例建立手持原药")
	_check(not inventory.can_place_in_blend_slot(player, slot) and not inventory.try_place_in_blend_slot(player, slot), "关闭槽位拒绝放入")
	_check(component.try_interact(player), "通过组件开始打开指定槽位")
	_check(not inventory.try_place_in_blend_slot(player, slot), "槽位打开动画期间拒绝放入")
	await _wait_slot_state(slot, true)
	_check(inventory.try_place_in_blend_slot(player, slot), "完全打开后允许放入")
	_check(inventory.try_receive_item(SODIUM), "原当前格重新持有另一原药")
	var item: AutolysisRawMaterial = slot.get_stored_item()
	var display: Node3D = player.held_item_presenter.get_display()
	var observation: Dictionary = _observe(inventory)
	_check(not inventory.can_place_in_blend_slot(player, slot) and not inventory.try_place_in_blend_slot(player, slot), "槽内有药且手持有药时不替换不交换")
	_check(not inventory.can_take_from_blend_slot(player, slot) and not inventory.try_take_from_blend_slot(player, slot), "当前格有药时不向其他空格取回")
	_check(inventory.get_slot_item(1) == null and inventory.get_focused_item() == SODIUM and slot.get_stored_item() == item and display == player.held_item_presenter.get_display() and observation["notifications"] == 0, "拒绝后其他格、占用、显示及通知保持原状")
	_check(inventory.cycle_focus(1) and inventory.try_take_from_blend_slot(player, slot), "切换到当前空格后取回成功")
	_check(inventory.get_focused_index() == 1 and inventory.get_slot_item(0) == SODIUM and inventory.get_slot_item(1) == CAFFEINE, "取回只写当前第二格，第一格原药不变")
	_check(inventory.try_place_in_blend_slot(player, slot), "将第二格原药放回原指定槽位")
	var old_item_transform: Transform3D = slot.get_stored_item().global_transform
	_check(component.try_interact(player), "含药槽位允许关闭")
	_check(not inventory.try_take_from_blend_slot(player, slot), "含药槽关闭运动期间拒绝取回")
	await _wait_slot_state(slot, false)
	_check(slot.get_stored_item() == item or slot.owns_item(slot.get_stored_item()), "含药关闭保留唯一占用")
	_check(not slot.get_stored_item().global_transform.is_equal_approx(old_item_transform) and slot.get_stored_item().transform.is_equal_approx(Transform3D.IDENTITY), "原药真实世界姿态随槽位动画变化且局部姿态保持单位变换")
	_check(_inventory_count(inventory) + _stored_count(slots) == 2, "切格、拒绝和含药动画均保持总数")
	_check(player.focus_controller.request_exit(), "含药设备正常退出聚焦")
	await _frames(18)
	_check(not inventory.try_take_from_blend_slot(player, slot) and slot.get_stored_item() != null, "退出不清槽且不能在普通状态取回")
	_check(player.focus_controller.try_enter(fixture["target"]), "再次进入同一设备")
	await _frames(18)
	_check(slot.get_stored_item() != null and not inventory.can_take_from_blend_slot(player, slot), "重新进入保留含药关闭状态")
	await _clear_world()


func _test_invalid_resources() -> void:
	for bad_path: String in ["res://missing_blend_world.tscn", SODIUM.world_scene_path, "res://main-autolysis/scenes/prefabs/prefab_raw_materials/rm_caffeine_group_0.tscn"]:
		var fixture: Dictionary = await _fixture()
		var player: AutolysisPlayer = fixture["player"]
		var slot: AutolysisBlendSlot = fixture["slots"][0]
		var definition: AutolysisItemDefinition = CAFFEINE.duplicate() as AutolysisItemDefinition
		definition.world_scene_path = bad_path
		_check(player.inventory_controller.try_receive_item(definition), "无效世界资源用例建立合法手持")
		var display: Node3D = player.held_item_presenter.get_display()
		var observation: Dictionary = _observe(player.inventory_controller)
		_check(not player.inventory_controller.can_place_in_blend_slot(player, slot) and not player.inventory_controller.try_place_in_blend_slot(player, slot), "世界场景缺失、定义不符或根类型不符时拒绝放入")
		_check(slot.get_stored_item() == null and player.inventory_controller.get_focused_item() == definition and player.held_item_presenter.get_display() == display and observation["notifications"] == 0, "世界资源失败不改变道具、显示、槽位或通知")
		await _clear_world()
	var fixture: Dictionary = await _fixture()
	var player: AutolysisPlayer = fixture["player"]
	var slot: AutolysisBlendSlot = fixture["slots"][0]
	var definition: AutolysisItemDefinition = CAFFEINE.duplicate() as AutolysisItemDefinition
	definition.is_raw_material = false
	_check(player.inventory_controller.try_receive_item(definition), "合法非原药可以进入普通道具格")
	_check(not player.inventory_controller.try_place_in_blend_slot(player, slot), "非原药不能进入混合槽")
	await _clear_world()
	fixture = await _fixture()
	player = fixture["player"]
	slot = fixture["slots"][0]
	definition = CAFFEINE.duplicate() as AutolysisItemDefinition
	_check(player.inventory_controller.try_receive_item(definition) and player.inventory_controller.try_place_in_blend_slot(player, slot), "损坏展示资源用例先完成存放")
	var stored: AutolysisRawMaterial = slot.get_stored_item()
	definition.visual_scene = WORLD_SCENE
	var observation: Dictionary = _observe(player.inventory_controller)
	_check(not player.inventory_controller.can_take_from_blend_slot(player, slot) and not player.inventory_controller.try_take_from_blend_slot(player, slot), "取回时损坏展示资源被查询与执行同时拒绝")
	_check(slot.owns_item(stored) and player.inventory_controller.get_focused_item() == null and player.held_item_presenter.get_display() == null and observation["notifications"] == 0, "展示准备失败保留来源原药且无通知")
	await _clear_world()


func _test_attachment_failures() -> void:
	for failure_mode: int in range(5):
		var fixture: Dictionary = await _fixture()
		var player: AutolysisPlayer = fixture["player"]
		var machine: Node3D = fixture["machine"]
		var focus_target: AutolysisFocusTarget = fixture["target"]
		var slot: AutolysisBlendSlot = fixture["slots"][0]
		var anchor: Node3D = slot.raw_material_anchor
		_check(player.inventory_controller.try_receive_item(CAFFEINE), "入树故障用例%d建立原药" % failure_mode)
		var display: Node3D = player.held_item_presenter.get_display()
		var observation: Dictionary = _observe(player.inventory_controller)
		var sabotage: Callable = func(_candidate: Node) -> void:
			match failure_mode:
				0:
					machine.queue_free()
				1:
					anchor.queue_free()
				2:
					player.focus_controller.request_exit()
				3:
					_candidate.queue_free()
				4:
					focus_target.reference_camera.free()
		anchor.child_entered_tree.connect(sabotage, CONNECT_ONE_SHOT)
		_check(not player.inventory_controller.try_place_in_blend_slot(player, slot), "候选入树故障%d回滚事务" % failure_mode)
		_check(player.inventory_controller.get_focused_item() == CAFFEINE and player.inventory_controller.get_focused_index() == 0 and player.held_item_presenter.get_display() == display and observation["notifications"] == 0, "入树失败%d保留来源格、显示及通知次数" % failure_mode)
		_check(slot.get_stored_item() == null, "入树失败%d清理本次临时占用" % failure_mode)
		await _clear_world()


func _test_observer_reentry() -> void:
	var fixture: Dictionary = await _fixture()
	var player: AutolysisPlayer = fixture["player"]
	var inventory: AutolysisInventoryController = player.inventory_controller
	var slots: Array[AutolysisBlendSlot] = fixture["slots"]
	var slot: AutolysisBlendSlot = slots[1]
	_check(inventory.try_receive_item(CAFFEINE), "通知重入用例建立原药")
	var snapshots: Array[Dictionary] = []
	var callback: Callable = func() -> void:
		var stored: AutolysisRawMaterial = slot.get_stored_item()
		snapshots.append({
			"empty": inventory.get_focused_item() == null,
			"stored": stored != null,
			"total": _inventory_count(inventory) + _stored_count(slots),
			"can_take": inventory.can_take_from_blend_slot(player, slot),
			"can_place": inventory.can_place_in_blend_slot(player, slot),
			"take": inventory.try_take_from_blend_slot(player, slot),
			"place": inventory.try_place_in_blend_slot(player, slot),
			"cycle": inventory.cycle_focus(1),
			"receive": inventory.try_receive_item(SODIUM),
		})
	inventory.inventory_changed.connect(callback)
	_check(inventory.try_place_in_blend_slot(player, slot) and snapshots.size() == 1, "放入只发布一次同步通知")
	if snapshots.size() == 1:
		var snapshot: Dictionary = snapshots[0]
		_check(snapshot["empty"] and snapshot["stored"] and snapshot["total"] == 1 and snapshot["can_take"] and not snapshot["can_place"], "放入通知看到已提交单占用且只读许可可取不可放")
		_check(not snapshot["take"] and not snapshot["place"] and not snapshot["cycle"] and not snapshot["receive"], "放入通知内再次取放、切格和接收均拒绝")
	_check(inventory.try_take_from_blend_slot(player, slot) and snapshots.size() == 2, "锁释放后取回只追加一次通知")
	if snapshots.size() == 2:
		var snapshot: Dictionary = snapshots[1]
		_check(not snapshot["empty"] and not snapshot["stored"] and snapshot["total"] == 1 and not snapshot["can_take"] and snapshot["can_place"], "取回通知看到已提交单占用且只读许可可放不可取")
		_check(not snapshot["take"] and not snapshot["place"] and not snapshot["cycle"] and not snapshot["receive"], "取回通知内再次取放、切格和接收均拒绝")
	inventory.inventory_changed.disconnect(callback)
	_check(inventory.cycle_focus(1), "通知返回后道具事务保护已释放")
	await _clear_world()


## 单独运行：同步释放入树中节点可能被引擎拒绝，保留真实错误而不伪装通过。
func _test_immediate_free_probe() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var probe_argument: int = arguments.find("--immediate-free-probe")
	var probe_mode: String = arguments[probe_argument + 1] if probe_argument + 1 < arguments.size() else "candidate"
	var fixture: Dictionary = await _fixture()
	var player: AutolysisPlayer = fixture["player"]
	var machine: Node3D = fixture["machine"]
	var slot: AutolysisBlendSlot = fixture["slots"][0]
	var anchor: Node3D = slot.raw_material_anchor
	_check(player.inventory_controller.try_receive_item(CAFFEINE), "立即释放探测建立真实原药来源")
	var display: Node3D = player.held_item_presenter.get_display()
	var observation: Dictionary = _observe(player.inventory_controller)
	var probe: Dictionary = {"模式": "设备" if probe_mode == "device" else "候选", "回调执行": false, "立即释放生效": false}
	anchor.child_entered_tree.connect(func(candidate: Node) -> void:
		probe["回调执行"] = true
		var victim: Node = machine if probe_mode == "device" else candidate
		victim.free()
		probe["立即释放生效"] = not is_instance_valid(victim), CONNECT_ONE_SHOT)
	var accepted: bool = player.inventory_controller.try_place_in_blend_slot(player, slot)
	probe["事务返回"] = accepted
	probe["通知次数"] = observation["notifications"]
	probe["来源仍在"] = player.inventory_controller.get_focused_item() == CAFFEINE
	print("立即释放探测：", JSON.stringify(probe))
	records.append(probe)
	_check(probe["回调执行"], "真实候选入树信号执行立即释放请求")
	if probe["立即释放生效"]:
		_check(not accepted and probe["来源仍在"] and observation["notifications"] == 0 and player.held_item_presenter.get_display() == display, "引擎允许立即释放时事务失败且来源与通知保持不变")
		_check(not is_instance_valid(slot) or slot.get_stored_item() == null, "立即释放后不遗留临时占用")
	else:
		_check(accepted and not probe["来源仍在"] and observation["notifications"] == 1 and slot.owns_item(slot.get_stored_item()), "引擎拒绝立即释放时仍按实际存活对象完成单次一致提交")
	await _clear_world()


func _test_two_actor_reentry() -> void:
	var fixture: Dictionary = await _fixture()
	var first: AutolysisPlayer = fixture["player"]
	var second: AutolysisPlayer = _new_player()
	_check(second.focus_controller.try_enter(fixture["target"]), "第二玩家通过正式会话进入同一设备")
	await _frames(18)
	var slot: AutolysisBlendSlot = fixture["slots"][0]
	_check(first.inventory_controller.try_receive_item(CAFFEINE) and second.inventory_controller.try_receive_item(SODIUM), "同槽竞争用例建立两个独立来源")
	var attempt: Dictionary = {"called": false, "result": true}
	slot.raw_material_anchor.child_entered_tree.connect(func(_node: Node) -> void:
		attempt["called"] = true
		attempt["result"] = second.inventory_controller.try_place_in_blend_slot(second, slot), CONNECT_ONE_SHOT)
	_check(first.inventory_controller.try_place_in_blend_slot(first, slot) and attempt["called"] and not attempt["result"], "候选入树时第二玩家同槽重入被槽位事务锁拒绝")
	_check(slot.get_stored_item().item_definition == CAFFEINE and first.inventory_controller.get_focused_item() == null and second.inventory_controller.get_focused_item() == SODIUM, "竞争后保留第一玩家存放与第二玩家手持")
	var unrelated: AutolysisRawMaterial = WORLD_SCENE.instantiate() as AutolysisRawMaterial
	slot.rollback_prepared_item(unrelated)
	unrelated.free()
	_check(slot.get_stored_item() != null and slot.owns_item(slot.get_stored_item()), "按候选身份回滚不能清除其他已提交药品")
	_check(not first.inventory_controller.try_take_from_blend_slot(second, slot), "不能借用另一角色向本控制器转移")
	await _clear_world()


func _test_device_pickup_exclusion() -> void:
	var fixture: Dictionary = await _fixture()
	var player: AutolysisPlayer = fixture["player"]
	var slot: AutolysisBlendSlot = fixture["slots"][0]
	var candidate: AutolysisRawMaterial = WORLD_SCENE.instantiate() as AutolysisRawMaterial
	_check(candidate.prepare_device_storage(slot), "未入树候选成功标记设备存放")
	var component: AutolysisInteractionComponent = candidate.get_node("InteractionComponent") as AutolysisInteractionComponent
	_check(not component.is_enabled and candidate.collision_layer == 0 and candidate.collision_mask == 0 and not candidate.is_in_group(&"interactable"), "入树前已关闭普通拾取、分组及碰撞")
	var shelf: AutolysisRawMaterialShelf = SHELF_SCENE.instantiate() as AutolysisRawMaterialShelf
	world.add_child(shelf)
	_check(not shelf.try_attach_item(0, candidate), "原药架拒绝具有设备标记的候选")
	world.add_child(candidate)
	_check(not component.is_enabled and not candidate.is_available_for_pickup() and not component.try_interact(player), "初始化不会重新开放设备原药普通入口")
	candidate.blend_slot = null
	_check(not player.inventory_controller.can_take_world_item(candidate) and not player.inventory_controller.try_take_world_item(candidate) and not shelf.try_attach_item(0, candidate), "设备归属引用失效也不能恢复普通拾取或转入架子")
	candidate.queue_free()
	await _clear_world()


func _save_evidence() -> void:
	var path: String = ProjectSettings.globalize_path(evidence_directory.path_join("blend-slot-transfers.json"))
	var result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(result == OK, "创建槽位事务证据目录")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "打开槽位事务证据文件")
	if file != null:
		file.store_string(JSON.stringify({"引擎版本": Engine.get_version_info().get("string", ""), "断言数": assertion_count, "失败数": failures, "记录": records}, "\t"))
		file.close()
