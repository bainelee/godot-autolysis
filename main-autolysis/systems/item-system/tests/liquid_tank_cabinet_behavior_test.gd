extends SceneTree
## 真实柜场景及真实门动画的行为检查，不写入柜门状态。

const TANK: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/liquid_tank.tres")
const CABINET_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/cabinet_workroom_0.tscn")

class TestActor extends Node3D:
	var inventory: AutolysisInventoryController
	var presenter: AutolysisHeldItemPresenter
	var notifications: int = 0
	var extra_requests: int = 0

	func input_allowed() -> bool:
		return true

	func on_inventory_changed() -> void:
		notifications += 1

	func on_extra_request(_actor: Node3D) -> void:
		extra_requests += 1

class LatePhysicsPoseProbe extends Node:
	var door: AnimatableBody3D
	var remaining_samples: int = 0
	var node_poses: Array[Transform3D] = []
	var server_poses: Array[Transform3D] = []

	func _physics_process(_delta: float) -> void:
		if remaining_samples <= 0 or not is_instance_valid(door):
			return
		node_poses.append(door.global_transform)
		server_poses.append(PhysicsServer3D.body_get_state(door.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM))
		remaining_samples -= 1

var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/液体罐与专用柜实施证据/checks/behavior")
var world: Node3D
var failures: int = 0
var assertion_count: int = 0
var records: Array[Dictionary] = []
var motion_records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	await _test_initial_configuration([])
	await _test_initial_configuration([0])
	await _test_initial_configuration([1])
	await _test_initial_configuration([0, 1])
	await _test_motion_and_component_contract()
	await _test_stopped_animation(false)
	await _test_stopped_animation(true)
	await _test_released_animation_player(false)
	await _test_released_animation_player(true)
	_save_evidence()
	await _clear_world()
	world.queue_free()
	await _frames(2)
	print("液体罐柜行为断言数：", assertion_count, "；失败总数：", failures)
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


func _new_actor(with_tank: bool = false) -> TestActor:
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
	if with_tank:
		_check(actor.inventory.try_receive_item(TANK), "放置演员持有液体罐，避免空格导致门禁假通过")
	return actor


func _fixture(occupied_slots: Array[int]) -> Dictionary:
	var actor: TestActor = _new_actor()
	var cabinet: AutolysisLiquidTankCabinet = CABINET_SCENE.instantiate() as AutolysisLiquidTankCabinet
	_check(cabinet != null, "正式柜场景根节点使用液体罐柜脚本")
	if cabinet == null:
		return {}
	var expected_items: Array[AutolysisLiquidTank] = []
	expected_items.resize(2)
	for index: int in range(2):
		var anchor: Node3D = cabinet.get_node_or_null("liquid_tank_slot_%d" % index) as Node3D
		_check(anchor != null and anchor.get_parent() == cabinet, "编号%d锚点为柜的直接子级" % index)
		if anchor == null:
			cabinet.free()
			return {}
		if not occupied_slots.has(index):
			for child: Node in anchor.get_children():
				child.free()
		elif anchor.get_child_count() == 1:
			expected_items[index] = anchor.get_child(0) as AutolysisLiquidTank
		else:
			_check(false, "保留的初始槽恰有一个液体罐")
			cabinet.free()
			return {}
	world.add_child(cabinet)
	_check(cabinet.is_configured(), "真实柜初始配置有效")
	if not cabinet.is_configured():
		return {}
	return {"actor": actor, "cabinet": cabinet, "expected_items": expected_items}


func _test_initial_configuration(occupied_slots: Array[int]) -> void:
	var fixture: Dictionary = _fixture(occupied_slots)
	if fixture.is_empty():
		await _clear_world()
		return
	var actor: TestActor = fixture["actor"]
	var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
	var expected: Array[AutolysisLiquidTank] = fixture["expected_items"]
	var label: String = "初始占用" + str(occupied_slots)
	_check(cabinet.get_slot_count() == 2 and _cabinet_count(cabinet) == occupied_slots.size(), label + "只登记现有来源，数量不增加")
	_check(not cabinet.is_open() and not cabinet.is_animating() and not cabinet.animation_player.is_playing(), label + "初始化关闭且没有自行启动动画")
	_check(cabinet.door_body.rotation.is_zero_approx() and cabinet.can_toggle(actor), label + "实际关门姿态为零度且允许门交互")
	for index: int in range(2):
		var anchor: Node3D = cabinet.get_slot_node(index)
		var item: AutolysisLiquidTank = cabinet.get_item_at_slot(index)
		_check(item == expected[index] and anchor.get_child_count() == (1 if occupied_slots.has(index) else 0), label + "编号%d保持原对象身份和子级数量" % index)
		if item != null:
			_check(cabinet.owns_item(item) and item.cabinet == cabinet and item.slot_index == index and item.cabinet_stored and item.get_parent() == anchor, label + "编号%d归属、编号、父级双向一致" % index)
			_check(not item.is_available_for_pickup() and not actor.inventory.can_take_liquid_tank(actor, item), label + "关闭门保持空格演员不可取回编号%d" % index)
	_check_component_contract(cabinet.door_body, cabinet.toggle_interaction, cabinet, label + "门组件")
	_check_component_contract(cabinet.placement_body, cabinet.placement_interaction, cabinet, label + "放置组件")
	for index: int in range(2):
		var item: AutolysisLiquidTank = cabinet.get_item_at_slot(index)
		if item != null:
			_check_component_contract(item, item.get_node_or_null("InteractionComponent") as AutolysisInteractionComponent, item, label + "编号%d罐组件" % index)
	_record_motion(cabinet, label)
	await _clear_world()


func _check_component_contract(body: PhysicsBody3D, component: AutolysisInteractionComponent, receiver: Node, label: String) -> void:
	_check(component != null and component.get_parent() == body, label + "为物理体直接子级")
	if component == null:
		return
	var count: int = 0
	for child: Node in body.get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	_check(count == 1 and component.interaction_mode == AutolysisInteractionComponent.InteractionMode.DIRECT, label + "恰有一个直接交互入口")
	var connections: Array[Dictionary] = []
	connections.assign(component.interaction_requested.get_connections())
	_check(connections.size() == 1, label + "恰有一个接收者")
	if connections.size() != 1:
		return
	var callback: Callable = connections[0]["callable"]
	var flags: int = connections[0]["flags"]
	_check(callback.is_valid() and callback.get_object() == receiver and callback.get_argument_count() == 1 and (flags & (Object.CONNECT_DEFERRED | Object.CONNECT_APPEND_SOURCE_OBJECT)) == 0, label + "接收者为所属业务节点且同步接收一个演员参数")


func _test_motion_and_component_contract() -> void:
	var fixture: Dictionary = _fixture([0])
	if fixture.is_empty():
		await _clear_world()
		return
	var picker: TestActor = fixture["actor"]
	var placer: TestActor = _new_actor(true)
	var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
	_assert_transfer_denied(cabinet, picker, placer, "关闭")
	_check(cabinet.toggle_interaction.try_interact(picker), "门组件同步分发一次请求并开始真实开门")
	_check(cabinet.is_animating() and cabinet.animation_player.is_playing() and not cabinet.is_open(), "开门请求立即进入运动并维持门禁")
	_assert_transfer_denied(cabinet, picker, placer, "正在打开")
	_assert_repeated_toggle_denied(cabinet, picker, "正在打开")
	_record_motion(cabinet, "开始打开")
	await _frames(20)
	_check(cabinet.is_open() and not cabinet.is_animating() and not cabinet.animation_player.is_playing(), "真实开门动画自然结束后才建立完全打开许可")
	_check(cabinet.door_body.rotation.is_equal_approx(_animation_end_rotation(cabinet)), "完全打开时实际门姿态等于动画末帧")
	_assert_transfer_allowed(cabinet, picker, placer)
	_check_additional_receiver_denied(cabinet.toggle_interaction, picker, "开门组件")
	_check_additional_receiver_denied(cabinet.placement_interaction, placer, "放置组件")
	var stored: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	if stored != null:
		_check_additional_receiver_denied(stored.get_node("InteractionComponent") as AutolysisInteractionComponent, picker, "罐拾取组件")
	_record_motion(cabinet, "自然打开完成")
	_check(cabinet.toggle_interaction.try_interact(picker), "已打开的门组件开始真实倒放关闭")
	_check(cabinet.is_animating() and cabinet.animation_player.is_playing() and not cabinet.is_open(), "关闭请求立即收回取放许可")
	_assert_transfer_denied(cabinet, picker, placer, "正在关闭")
	_assert_repeated_toggle_denied(cabinet, picker, "正在关闭")
	await _frames(20)
	_check(not cabinet.is_open() and not cabinet.is_animating() and not cabinet.animation_player.is_playing() and cabinet.door_body.rotation.is_zero_approx(), "真实倒放自然结束回到关闭零度")
	_assert_transfer_denied(cabinet, picker, placer, "关闭完成")
	_check(cabinet.owns_item(stored) and _cabinet_count(cabinet) == 1 and picker.inventory.get_focused_item() == null and placer.inventory.get_focused_item() == TANK, "完整开闭及组件拒绝过程保持所有来源不变")
	_record_motion(cabinet, "自然关闭完成")
	await _clear_world()


func _assert_transfer_denied(cabinet: AutolysisLiquidTankCabinet, picker: TestActor, placer: TestActor, label: String) -> void:
	var stored: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	_check(stored != null and cabinet.get_item_at_slot(1) == null and picker.inventory.get_focused_item() == null and placer.inventory.get_focused_item() == TANK, label + "检查夹具为一罐、一空槽、拾取空格及放置持罐")
	if stored == null:
		return
	var picker_notifications: int = picker.notifications
	var placer_notifications: int = placer.notifications
	var display: Node3D = placer.presenter.get_display()
	_check(not cabinet.is_open() and not cabinet.can_transfer(picker) and not cabinet.can_transfer(placer), label + "柜级取放许可均关闭")
	_check(not stored.is_available_for_pickup() and not picker.inventory.can_take_liquid_tank(picker, stored) and not picker.inventory.try_take_liquid_tank(picker, stored), label + "指定罐的查询及取回执行均拒绝")
	_check(not placer.inventory.can_place_in_liquid_tank_cabinet(placer, cabinet) and not placer.inventory.try_place_in_liquid_tank_cabinet(placer, cabinet), label + "空槽存在时放置查询及执行仍拒绝")
	var pickup_component: AutolysisInteractionComponent = stored.get_node("InteractionComponent") as AutolysisInteractionComponent
	_check(not pickup_component.can_interact(picker) and not pickup_component.try_interact(picker) and not cabinet.placement_interaction.can_interact(placer) and not cabinet.placement_interaction.try_interact(placer), label + "罐与放置组件不分发请求")
	_check(cabinet.owns_item(stored) and cabinet.get_item_at_slot(1) == null and picker.inventory.get_focused_item() == null and placer.inventory.get_focused_item() == TANK and placer.presenter.get_display() == display and picker.notifications == picker_notifications and placer.notifications == placer_notifications, label + "拒绝不改变来源、手持及通知次数")


func _assert_transfer_allowed(cabinet: AutolysisLiquidTankCabinet, picker: TestActor, placer: TestActor) -> void:
	var stored: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	_check(stored != null, "打开完成时原初始罐仍存在")
	if stored == null:
		return
	_check(cabinet.can_transfer(picker) and cabinet.can_transfer(placer) and stored.is_available_for_pickup(), "完全打开允许空格取回及持罐向空槽放置")
	_check(picker.inventory.can_take_liquid_tank(picker, stored) and placer.inventory.can_place_in_liquid_tank_cabinet(placer, cabinet), "完全打开的两类库存查询返回许可")
	_check(cabinet.toggle_interaction.can_interact(picker) and cabinet.placement_interaction.can_interact(placer) and (stored.get_node("InteractionComponent") as AutolysisInteractionComponent).can_interact(picker), "完全打开时三个真实组件均满足各自业务条件")


func _assert_repeated_toggle_denied(cabinet: AutolysisLiquidTankCabinet, actor: TestActor, label: String) -> void:
	var position_before: float = cabinet.animation_player.current_animation_position
	var direction_before: float = cabinet.animation_player.get_playing_speed()
	var rotation_before: Vector3 = cabinet.door_body.rotation
	for index: int in range(4):
		_check(not cabinet.can_toggle(actor) and not cabinet.try_toggle(actor) and not cabinet.toggle_interaction.can_interact(actor) and not cabinet.toggle_interaction.try_interact(actor), label + "连续请求%d同时被业务入口与门组件拒绝" % index)
	_check(cabinet.animation_player.is_playing() and is_equal_approx(cabinet.animation_player.current_animation_position, position_before) and is_equal_approx(cabinet.animation_player.get_playing_speed(), direction_before) and cabinet.door_body.rotation.is_equal_approx(rotation_before), label + "连续请求不重启、不倒转、不跳动当前动画")


func _check_additional_receiver_denied(component: AutolysisInteractionComponent, actor: TestActor, label: String) -> void:
	_check(component != null and component.can_interact(actor), label + "单接收者夹具原本允许交互")
	if component == null:
		return
	var requests_before: int = actor.extra_requests
	component.interaction_requested.connect(actor.on_extra_request)
	_check(not component.can_interact(actor) and not component.try_interact(actor) and actor.extra_requests == requests_before, label + "追加第二接收者后查询和分发同时拒绝")
	component.interaction_requested.disconnect(actor.on_extra_request)
	_check(component.can_interact(actor), label + "恢复唯一接收者后许可恢复")


func _start_fault_motion(cabinet: AutolysisLiquidTankCabinet, actor: TestActor, closing: bool) -> bool:
	if closing:
		_check(cabinet.try_toggle(actor), "关闭故障夹具通过正式入口先打开")
		await _frames(20)
		_check(cabinet.is_open(), "关闭故障夹具确已自然打开")
		if not cabinet.is_open():
			return false
	_check(cabinet.try_toggle(actor), "故障夹具通过正式入口开始目标动作")
	await _frames(1)
	_check(cabinet.is_animating() and cabinet.animation_player.is_playing(), "故障注入前真实门动画仍在进行")
	return cabinet.is_animating() and cabinet.animation_player.is_playing()


func _test_stopped_animation(closing: bool) -> void:
	var fixture: Dictionary = _fixture([0])
	if fixture.is_empty():
		await _clear_world()
		return
	var picker: TestActor = fixture["actor"]
	var placer: TestActor = _new_actor(true)
	var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
	var label: String = "关闭途中停止" if closing else "打开途中停止"
	var motion_started: bool = await _start_fault_motion(cabinet, picker, closing)
	if not motion_started:
		await _clear_world()
		return
	# 同步门节点在普通帧可保持上一物理姿态；停止基准取已提交的服务器目标。
	var target_before: Transform3D = PhysicsServer3D.body_get_state(cabinet.door_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	_record_motion(cabinet, label + "之前的普通帧")
	var probe: LatePhysicsPoseProbe = LatePhysicsPoseProbe.new()
	probe.door = cabinet.door_body
	probe.process_physics_priority = 10000
	probe.remaining_samples = 3
	world.add_child(probe)
	cabinet.animation_player.stop(true)
	_record_motion(cabinet, label + "的同步停止返回点")
	await _frames(4)
	_check(probe.node_poses.size() == 3 and probe.server_poses.size() == 3, label + "实际采集三次后续物理回调")
	for index: int in range(probe.node_poses.size()):
		var node_error: float = _transform_error(probe.node_poses[index], target_before)
		var server_error: float = _transform_error(probe.server_poses[index], target_before)
		_check(node_error < 0.0001 and server_error < 0.0001, label + "后续物理回调%d的节点与物理姿态保持停止前服务器目标" % index)
		motion_records.append({"阶段": label + "后续物理回调%d" % index, "停止前服务器目标": str(target_before), "门节点姿态": str(probe.node_poses[index]), "门物理姿态": str(probe.server_poses[index]), "节点与停止目标误差": node_error, "服务器与停止目标误差": server_error})
	await _frames(20)
	var stable_server: Transform3D = PhysicsServer3D.body_get_state(cabinet.door_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	_check(not cabinet.animation_player.is_playing() and _transform_error(cabinet.door_body.global_transform, target_before) < 0.0001 and _transform_error(stable_server, target_before) < 0.0001, label + "等待后仍保持最后提交的中途物理目标")
	_assert_transfer_denied(cabinet, picker, placer, label)
	_check(not cabinet.can_toggle(picker) and not cabinet.try_toggle(picker) and not cabinet.toggle_interaction.try_interact(picker), label + "不能通过后续门请求恢复许可")
	_record_motion(cabinet, label)
	await _clear_world()


func _test_released_animation_player(closing: bool) -> void:
	var fixture: Dictionary = _fixture([0])
	if fixture.is_empty():
		await _clear_world()
		return
	var picker: TestActor = fixture["actor"]
	var placer: TestActor = _new_actor(true)
	var cabinet: AutolysisLiquidTankCabinet = fixture["cabinet"]
	var label: String = "关闭途中释放播放器" if closing else "打开途中释放播放器"
	var motion_started: bool = await _start_fault_motion(cabinet, picker, closing)
	if not motion_started:
		await _clear_world()
		return
	var released_player: AnimationPlayer = cabinet.animation_player
	released_player.queue_free()
	await _frames(20)
	_check(not is_instance_valid(released_player) and not cabinet.is_configured(), label + "实际播放器释放使配置失效")
	_assert_transfer_denied(cabinet, picker, placer, label)
	_check(not cabinet.can_toggle(picker) and not cabinet.try_toggle(picker) and not cabinet.toggle_interaction.try_interact(picker), label + "失效引用不分发后续门动作")
	_record_motion(cabinet, label)
	await _clear_world()


func _animation_end_rotation(cabinet: AutolysisLiquidTankCabinet) -> Vector3:
	var animation: Animation = cabinet.animation_player.get_animation(cabinet.animation_name)
	return animation.track_get_key_value(0, animation.track_get_key_count(0) - 1)


func _cabinet_count(cabinet: AutolysisLiquidTankCabinet) -> int:
	var count: int = 0
	for index: int in range(2):
		if cabinet.get_item_at_slot(index) != null:
			count += 1
	return count


func _record_motion(cabinet: AutolysisLiquidTankCabinet, label: String) -> void:
	var player_is_live: bool = is_instance_valid(cabinet.animation_player) and not cabinet.animation_player.is_queued_for_deletion()
	var animation_is_active: bool = player_is_live and cabinet.animation_player.is_animation_active()
	var server_pose: Transform3D = PhysicsServer3D.body_get_state(cabinet.door_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	motion_records.append({
		"阶段": label,
		"柜状态编号": cabinet.state,
		"配置有效": cabinet.is_configured(),
		"完全打开": cabinet.is_open(),
		"运动中": cabinet.is_animating(),
		"实际门旋转": str(cabinet.door_body.rotation),
		"播放器有效": player_is_live,
		"当前动画有效": animation_is_active,
		"正在播放": cabinet.animation_player.is_playing() if player_is_live else false,
		"播放位置": cabinet.animation_player.current_animation_position if animation_is_active else -1.0,
		"门节点姿态": str(cabinet.door_body.global_transform),
		"门物理姿态": str(server_pose),
		"节点与物理姿态误差": _transform_error(cabinet.door_body.global_transform, server_pose),
		"柜内罐数": _cabinet_count(cabinet),
	})


func _transform_error(left: Transform3D, right: Transform3D) -> float:
	return maxf(left.origin.distance_to(right.origin), maxf(left.basis.x.distance_to(right.basis.x), maxf(left.basis.y.distance_to(right.basis.y), left.basis.z.distance_to(right.basis.z))))


func _save_evidence() -> void:
	var directory: String = ProjectSettings.globalize_path(evidence_directory)
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_check(error == OK, "创建柜行为证据目录")
	if error != OK:
		return
	var report: FileAccess = FileAccess.open(directory.path_join("liquid-tank-cabinet-behavior.json"), FileAccess.WRITE)
	if report == null:
		_check(false, "柜行为报告文件可写")
		return
	report.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "物理帧率": Engine.physics_ticks_per_second, "断言数": assertion_count, "失败数": failures, "记录": records, "真实动画记录": motion_records, "姿态误差定义": "取原点差与三个基向量差长度的最大值，并非全部表示米", "官方方法证据": ["https://docs.godotengine.org/en/4.6/classes/class_animationplayer.html#class-animationplayer-method-get-playing-speed", "https://docs.godotengine.org/en/4.6/classes/class_animationplayer.html#class-animationplayer-method-stop", "https://docs.godotengine.org/en/4.6/classes/class_animationplayer.html#class-animationplayer-method-is-animation-active", "https://docs.godotengine.org/en/4.6/classes/class_physicsserver3d.html#class-physicsserver3d-method-body-get-state", "https://raw.githubusercontent.com/godotengine/godot/4.6.1-stable/scene/3d/physics/animatable_body_3d.cpp", "https://raw.githubusercontent.com/godotengine/godot/4.6.1-stable/scene/animation/animation_player.cpp"]}, "\t"))
	report.close()
