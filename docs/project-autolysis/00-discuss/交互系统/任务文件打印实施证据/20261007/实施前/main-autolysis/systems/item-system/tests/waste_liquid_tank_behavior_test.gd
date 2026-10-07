extends SceneTree
## 废液罐真实动画、逐件处置与通知事务验收；图形模式补充主场景射线和输入。

const WASTE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/waste_liquid_storage_tank_0.tscn")
const CABINET_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/cabinet_workroom_0.tscn")
const MAIN_SCENE: PackedScene = preload("res://main-autolysis/scenes/01-autolysis-test.tscn")
const TANK: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/liquid_tank.tres")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const SODIUM: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/sodium_benzoate.tres")

class TestActor extends Node3D:
	var inventory: AutolysisInventoryController
	var presenter: AutolysisHeldItemPresenter
	var input_enabled: bool = true
	var notifications: int = 0

	func input_allowed() -> bool:
		return input_enabled

	func on_inventory_changed() -> void:
		notifications += 1

var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/废液罐交互实施证据/checks/behavior")
var world: Node3D
var failures: int = 0
var assertion_count: int = 0
var records: Array[Dictionary] = []
var motion_records: Array[Dictionary] = []
var ray_records: Array[Dictionary] = []
var screenshots: Array[String] = []
var graphical: bool = false
var player: AutolysisPlayer
var main_tank: AutolysisWasteLiquidStorageTank


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	world = Node3D.new()
	root.add_child(world)
	if "--pose-regression-only" in OS.get_cmdline_user_args():
		await _test_rotated_parent_motion()
		_save_evidence()
		world.queue_free()
		await _frames(2)
		print("废液罐主场景旋转回归断言数：", assertion_count, "；失败总数：", failures)
		quit(1 if failures > 0 else 0)
		return
	await _test_matrix_and_selection()
	await _test_raw_material_destruction()
	await _test_notifications_and_reentry()
	await _test_prior_resource_observer()
	await _test_invalid_sources_and_display()
	await _test_motion_faults()
	await _test_rotated_parent_motion()
	await _test_empty_cabinet_round_trip()
	if graphical:
		await _test_main_scene_inputs_and_refill()
	_save_evidence()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(world):
		world.queue_free()
	await _frames(2)
	print("废液罐行为与事务断言数：", assertion_count, "；失败总数：", failures, "；实际图形验收：", graphical)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	assertion_count += 1
	records.append({"序号": assertion_count, "说明": description, "通过": condition})
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1


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


func _new_tank() -> AutolysisWasteLiquidStorageTank:
	var tank: AutolysisWasteLiquidStorageTank = WASTE_SCENE.instantiate() as AutolysisWasteLiquidStorageTank
	_check(tank != null, "真实废液罐预制体根节点挂载处置控制器")
	if tank != null:
		world.add_child(tank)
		await _frames(2)
		_check(tank.is_configured(), "真实废液罐初始化配置有效")
	return tank


func _filled_instance() -> AutolysisItemInstance:
	var contents: AutolysisLiquidContents = AutolysisLiquidContents.create_result(["caffeine", "sodium_benzoate", "caffeine"])
	contents.set_phase_rgb(Vector3(2.5, -3.0, 8.0))
	contents.set_wave(true, false, true, true, 6)
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(TANK)
	_check(instance.set_liquid_contents(contents, false), "夹具创建含三份原药及非零重构数据的逐件满罐")
	return instance


func _open(tank: AutolysisWasteLiquidStorageTank, actor: Node3D) -> bool:
	_check(tank.try_toggle(actor), "正式开闭入口开始真实开盖动画")
	await _wait_motion(tank)
	_check(tank.is_open() and not tank.is_animating() and not tank.animation_player.is_playing(), "自然动画结束后废液罐才完全打开")
	return tank.is_open()


func _component_contract(body: PhysicsBody3D, component: AutolysisInteractionComponent, receiver: Node, label: String) -> void:
	_check(component != null and component.get_parent() == body and body.is_in_group(&"interactable"), label + "为可交互物理体直接子级")
	if component == null:
		return
	var count: int = 0
	for child: Node in body.get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	_check(count == 1 and component.has_execution_handler(), label + "具有唯一直接入口和明确业务执行绑定")

func _assert_denied(actor: TestActor, tank: AutolysisWasteLiquidStorageTank, label: String) -> void:
	var source: AutolysisItemInstance = actor.inventory.get_focused_instance()
	var contents: AutolysisLiquidContents = source.liquid_contents if source != null else null
	var display: Node3D = actor.presenter.get_display()
	var index: int = actor.inventory.get_focused_index()
	var count: int = actor.notifications
	_check(not actor.inventory.can_dispose_in_waste_tank(actor, tank) and not actor.inventory.try_dispose_in_waste_tank(actor, tank), label + "库存处置查询与执行同时拒绝")
	_check(not tank.disposal_interaction.can_interact(actor) and not tank.disposal_interaction.try_interact(actor), label + "真实罐体入口不分发处置请求")
	_check(actor.inventory.get_focused_instance() == source and actor.inventory.get_focused_index() == index and actor.presenter.get_display() == display and actor.notifications == count and (source == null or source.liquid_contents == contents), label + "拒绝保留实例、内容、选中格、显示和通知次数")


func _test_matrix_and_selection() -> void:
	var actor: TestActor = _new_actor()
	var other: TestActor = _new_actor()
	var tank: AutolysisWasteLiquidStorageTank = await _new_tank()
	if tank == null:
		await _clear_world()
		return
	var first: AutolysisItemInstance = _filled_instance()
	var second: AutolysisItemInstance = _filled_instance()
	_check(actor.inventory.try_receive_instance(first) and actor.inventory.cycle_focus(1) and actor.inventory.try_receive_instance(second), "两只同定义满罐进入相邻格且独立保存实例")
	_component_contract(tank, tank.disposal_interaction, tank, "罐体组件")
	_component_contract(tank.lid_body, tank.lid_interaction, tank, "盖子组件")
	_check(not tank.is_open() and not tank.is_animating() and tank.lid_body.rotation.is_zero_approx(), "初始化盖子明确位于实际关闭端帧")
	_check(tank.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL and tank.lid_body.sync_to_physics, "真实盖子由物理回调手动推进并保留物理同步")
	_assert_denied(actor, tank, "关闭持满罐")
	var notifications_before: int = actor.notifications
	_check(tank.lid_interaction.try_interact(actor), "持满罐点击盖子仅开始打开")
	_check(tank.is_animating() and not tank.is_open() and actor.inventory.get_focused_instance() == second and actor.notifications == notifications_before, "开始打开维持未打开许可且不处理手持满罐")
	_assert_denied(actor, tank, "打开中持满罐")
	var position_before: float = tank.animation_player.current_animation_position
	_check(not tank.try_toggle(actor) and not tank.lid_interaction.try_interact(actor) and is_equal_approx(tank.animation_player.current_animation_position, position_before), "打开中重复开闭不重启动画")
	await _wait_motion(tank)
	_check(tank.is_open(), "真实打开动画完成建立许可")
	var animation: Animation = tank.animation_player.get_animation(&"lid_open")
	var expected_rotation: Vector3 = animation.track_get_key_value(0, animation.track_get_key_count(0) - 1)
	_check(_basis_error(tank.lid_body.basis, Basis.from_euler(expected_rotation)) < 0.0003, "完全打开的盖子姿态等于真实动画末帧")
	actor.input_enabled = false
	_assert_denied(actor, tank, "输入禁止")
	actor.input_enabled = true
	paused = true
	_assert_denied(actor, tank, "场景暂停")
	_check(not tank.try_toggle(actor), "场景暂停同时拒绝盖子开闭")
	paused = false
	_check(not actor.inventory.can_dispose_in_waste_tank(other, tank) and not actor.inventory.try_dispose_in_waste_tank(other, tank), "另一角色不能借用当前库存控制器处置")
	for _index: int in range(6):
		_check(actor.inventory.can_dispose_in_waste_tank(actor, tank), "重复满罐许可查询保持只读")
	_check(actor.notifications == notifications_before and actor.inventory.get_focused_instance() == second and second.liquid_contents != null, "许可查询未通知、未倒空、未切格")
	var display: Node3D = actor.presenter.get_display()
	_check(tank.disposal_interaction.try_interact(actor), "真实罐体组件同步倒空当前满罐")
	_check(actor.inventory.get_focused_instance() == second and second.definition == TANK and second.is_empty_liquid_tank() and actor.inventory.get_focused_index() == 1 and actor.presenter.get_display() == display, "倒空保留同一实例、定义、选中格和手持模型")
	_check(second.get_phase_rgb() == Vector3.ZERO and second.get_wave_coordinates() == [0, 0, 0, 0, 0], "倒空后内容引用移除且相位与波形读取全部归零")
	_check(actor.inventory.get_slot_instance(0) == first and first.liquid_contents != null and first.get_phase_rgb() == Vector3(2.5, -3.0, 8.0), "其他格同定义满罐及其完整内容保持不变")
	_check(AutolysisLiquidTankVisual.get_contents_mesh(display).material_override == AutolysisLiquidTankVisual.EMPTY_MATERIAL, "手持满罐在同步通知后切换既有空罐材质")
	_assert_denied(actor, tank, "打开持空罐再次交互")
	_check(tank.lid_interaction.try_interact(actor), "持空罐点击盖子开始反向关闭")
	_check(tank.is_animating() and not tank.is_open() and tank.animation_player.get_playing_speed() < 0.0, "关闭请求收回处置许可并实际倒放")
	_assert_denied(actor, tank, "关闭中持空罐")
	_check(not tank.try_toggle(actor), "关闭中不追加开闭动作")
	await _wait_motion(tank)
	_check(not tank.is_open() and not tank.is_animating() and tank.lid_body.rotation.is_zero_approx(), "反播自然结束回到关闭零度")
	for _index: int in range(3):
		await _open(tank, actor)
		_check(tank.try_toggle(actor), "连续循环正式入口开始关闭")
		await _wait_motion(tank)
		_check(tank.lid_body.rotation.is_zero_approx() and not tank.is_open(), "连续开闭循环恢复实际关闭端帧")
	await _clear_world()


func _test_raw_material_destruction() -> void:
	var actor: TestActor = _new_actor()
	var tank: AutolysisWasteLiquidStorageTank = await _new_tank()
	if tank == null:
		await _clear_world()
		return
	_check(actor.inventory.try_receive_item(CAFFEINE) and actor.inventory.cycle_focus(1) and actor.inventory.try_receive_item(CAFFEINE), "两个同类原药分别进入独立道具格")
	var retained: AutolysisItemInstance = actor.inventory.get_slot_instance(0)
	var removed: AutolysisItemInstance = actor.inventory.get_focused_instance()
	_assert_denied(actor, tank, "关闭持原药")
	await _open(tank, actor)
	var old_notifications: int = actor.notifications
	_check(tank.disposal_interaction.try_interact(actor), "打开罐体的一次交互销毁当前原药")
	_check(actor.inventory.get_focused_instance() == null and actor.inventory.get_focused_index() == 1 and actor.presenter.get_display() == null and actor.notifications == old_notifications + 1, "销毁只清空当前格与显示且不自动切格，只通知一次")
	_check(actor.inventory.get_slot_instance(0) == retained and is_instance_valid(removed) and removed.definition == CAFFEINE, "其他格原药不变，资源销毁按移除持有引用实施")
	_assert_denied(actor, tank, "打开空手")
	var definition: AutolysisItemDefinition = CAFFEINE.duplicate() as AutolysisItemDefinition
	definition.item_id = &"waste_test_raw"
	definition.display_name = "处置标记测试原药"
	_check(actor.inventory.try_receive_item(definition) and actor.inventory.try_dispose_in_waste_tank(actor, tank), "具有原药类型标记的合法新定义同样可销毁")
	definition = CAFFEINE.duplicate() as AutolysisItemDefinition
	definition.item_id = &"waste_test_other"
	definition.display_name = "处置类型排斥测试道具"
	definition.is_raw_material = false
	_check(actor.inventory.try_receive_item(definition), "类型排斥用例建立既非原药也非液体罐的合法实例")
	_assert_denied(actor, tank, "打开持其他类别")
	await _clear_world()


func _test_notifications_and_reentry() -> void:
	for destroy_raw: bool in [false, true]:
		var actor: TestActor = _new_actor()
		var other: TestActor = _new_actor()
		var tank: AutolysisWasteLiquidStorageTank = await _new_tank()
		if tank == null:
			await _clear_world()
			return
		var source: AutolysisItemInstance = AutolysisItemInstance.create(CAFFEINE) if destroy_raw else _filled_instance()
		_check(actor.inventory.try_receive_instance(source) and other.inventory.try_receive_item(SODIUM), "通知重入用例建立甲来源与乙原药")
		await _open(tank, actor)
		var snapshots: Array[Dictionary] = []
		var resource_changes: Dictionary = {"次数": 0}
		var observe: Callable = func(channel: String) -> void:
			snapshots.append({
				"通道": channel,
				"最终空手": actor.inventory.get_focused_instance() == null,
				"最终空罐": source.is_empty_liquid_tank(),
				"当前处置许可": actor.inventory.can_dispose_in_waste_tank(actor, tank),
				"接收许可": actor.inventory.can_receive_item(CAFFEINE),
				"重复处置": actor.inventory.try_dispose_in_waste_tank(actor, tank),
				"切格": actor.inventory.cycle_focus(1),
				"接收": actor.inventory.try_receive_item(TANK),
				"关盖": tank.try_toggle(actor),
				"第二角色处置": other.inventory.try_dispose_in_waste_tank(other, tank),
			})
		var changed_callback: Callable = func() -> void:
			resource_changes["次数"] += 1
			observe.call("实例变化")
		var inventory_callback: Callable = func() -> void: observe.call("库存变化")
		source.changed.connect(changed_callback)
		actor.inventory.inventory_changed.connect(inventory_callback)
		var count: int = actor.notifications
		_check(actor.inventory.try_dispose_in_waste_tank(actor, tank), "通知重入用例通过正式处置入口提交")
		_check(actor.notifications == count + 1 and resource_changes["次数"] == (0 if destroy_raw else 1) and snapshots.size() == (1 if destroy_raw else 2), "原药只发库存一次，倒空仅发实例一次及库存一次")
		for snapshot: Dictionary in snapshots:
			_check(snapshot["最终空手"] == destroy_raw and snapshot["最终空罐"] == (not destroy_raw) and not snapshot["当前处置许可"] and snapshot["接收许可"] == destroy_raw, "同步通知只读查询反映已经提交的最终状态")
			_check(not snapshot["重复处置"] and not snapshot["切格"] and not snapshot["接收"] and not snapshot["关盖"] and not snapshot["第二角色处置"], "实例与库存通知期间拒绝重复处置、切格、接收、关盖及另一角色设备重入")
		source.changed.disconnect(changed_callback)
		actor.inventory.inventory_changed.disconnect(inventory_callback)
		_check(other.inventory.try_dispose_in_waste_tank(other, tank) and actor.inventory.cycle_focus(1) and tank.try_toggle(actor), "通知返回后库存锁和设备处置锁均已释放")
		await _clear_world()


func _test_invalid_sources_and_display() -> void:
	for invalid_contents: bool in [false, true]:
		var actor: TestActor = _new_actor()
		var tank: AutolysisWasteLiquidStorageTank = await _new_tank()
		if tank == null:
			await _clear_world()
			return
		var source: AutolysisItemInstance = _filled_instance()
		_check(actor.inventory.try_receive_instance(source), "故障用例先建立合法满罐显示")
		await _open(tank, actor)
		var contents: AutolysisLiquidContents = source.liquid_contents
		if invalid_contents:
			contents.set("_wave_level", 7)
			_check(not contents.is_valid_contents(), "实际越界波形数据使液体内容失效")
		else:
			AutolysisLiquidTankVisual.get_contents_mesh(actor.presenter.get_display()).mesh = null
			_check(not AutolysisLiquidTankVisual.can_apply(actor.presenter.get_display()), "实际网格依赖失效但未触发实例变化通知")
		if invalid_contents:
			_assert_denied(actor, tank, "无效内容")
		else:
			var old_notifications: int = actor.notifications
			var display: Node3D = actor.presenter.get_display()
			_check(not actor.inventory.try_dispose_in_waste_tank(actor, tank), "手持显示依赖故障在修改内容前拒绝处置")
			_check(actor.inventory.get_focused_instance() == source and actor.presenter.get_display() == display and actor.notifications == old_notifications and source.liquid_contents == contents, "显示故障保留原实例、内容、显示和通知次数")
		_check(source.liquid_contents == contents and contents.get_raw_material_ids() == ["caffeine", "sodium_benzoate", "caffeine"], "故障拒绝保留原内容引用与原药数据")
		await _clear_world()


func _test_prior_resource_observer() -> void:
	var actor: TestActor = _new_actor()
	var tank: AutolysisWasteLiquidStorageTank = await _new_tank()
	if tank == null:
		await _clear_world()
		return
	var source: AutolysisItemInstance = _filled_instance()
	var snapshots: Array[Dictionary] = []
	# 提前订阅确保此观察者先于手持呈现器收到实例变化。
	var callback: Callable = func() -> void:
		var display: Node3D = actor.presenter.get_display()
		var mesh: MeshInstance3D = AutolysisLiquidTankVisual.get_contents_mesh(display)
		snapshots.append({"同一实例": actor.inventory.get_focused_instance() == source, "空内容": source.is_empty_liquid_tank(), "空材质": mesh != null and mesh.material_override == AutolysisLiquidTankVisual.EMPTY_MATERIAL, "重复倒空": actor.inventory.try_dispose_in_waste_tank(actor, tank), "切格": actor.inventory.cycle_focus(1), "关盖": tank.try_toggle(actor)})
	source.changed.connect(callback)
	_check(actor.inventory.try_receive_instance(source), "先于呈现器订阅实例的观察者建立有效满罐")
	await _open(tank, actor)
	_check(actor.inventory.try_dispose_in_waste_tank(actor, tank) and snapshots.size() == 1, "提前订阅观察者在倒空时恰收到一次实例通知")
	if snapshots.size() == 1:
		var snapshot: Dictionary = snapshots[0]
		_check(snapshot["同一实例"] and snapshot["空内容"] and snapshot["空材质"], "先于呈现器执行的实例观察者也读取空内容和空材质一致终态")
		_check(not snapshot["重复倒空"] and not snapshot["切格"] and not snapshot["关盖"], "提前订阅观察者期间仍保持库存与设备锁")
	source.changed.disconnect(callback)
	await _clear_world()


func _test_motion_faults() -> void:
	for mode: int in range(4):
		var actor: TestActor = _new_actor()
		var tank: AutolysisWasteLiquidStorageTank = await _new_tank()
		_check(actor.inventory.try_receive_instance(_filled_instance()), "运动中断用例持有效满罐")
		if mode > 0:
			await _open(tank, actor)
		if mode == 2:
			# 姿态只用于测量；合法运动已完成后不以几何偏差撤销业务许可。
			tank.lid_body.transform = Transform3D.IDENTITY
			await _frames(2)
			_check(tank.is_open() and tank.can_toggle(actor), "完成态不因外部姿态偏移增加业务门禁")
		else:
			_check(tank.try_toggle(actor), "中断用例由正式入口开始目标动作")
			await _frames(1)
			if mode == 3:
				tank.animation_player.queue_free()
			else:
				tank.animation_player.stop(true)
			await _frames(4)
			_assert_denied(actor, tank, "动画中断或必要播放器释放")
			_check(not tank.is_animating() and not tank.can_toggle(actor), "中断终结等待且不伪报自然完成")
			if mode < 3:
				_check(tank.cancel_motion(), "明确取消可以恢复此前稳定状态")
				await _wait_motion(tank)
				_check(tank.is_open() == (mode == 1), "恢复与请求前稳定状态一致且不重复处置")
		motion_records.append({"中断类型": mode, "配置有效": tank.is_configured(), "完全打开": tank.is_open(), "配置错误": tank.get_configuration_error()})
		await _clear_world()

func _test_empty_cabinet_round_trip() -> void:
	var actor: TestActor = _new_actor()
	var tank: AutolysisWasteLiquidStorageTank = await _new_tank()
	if tank == null:
		await _clear_world()
		return
	var cabinet: AutolysisLiquidTankCabinet = CABINET_SCENE.instantiate() as AutolysisLiquidTankCabinet
	for index: int in range(2):
		for child: Node in cabinet.get_node("liquid_tank_slot_%d" % index).get_children():
			child.free()
	world.add_child(cabinet)
	var source: AutolysisItemInstance = _filled_instance()
	_check(actor.inventory.try_receive_instance(source), "柜子往返建立当前满罐")
	await _open(tank, actor)
	_check(actor.inventory.try_dispose_in_waste_tank(actor, tank), "柜子往返先通过废液罐倒空")
	_check(cabinet.try_toggle(actor), "柜子往返通过既有正式入口开门")
	await _wait_motion(cabinet)
	_check(actor.inventory.try_place_in_liquid_tank_cabinet(actor, cabinet), "倒空原罐可继续放入真实专用柜")
	var stored: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	_check(stored != null and stored.item_instance == source and stored.is_empty(), "柜内保持原实例与空罐内容")
	_check(stored != null and actor.inventory.try_take_liquid_tank(actor, stored) and actor.inventory.get_focused_instance() == source and source.is_empty_liquid_tank(), "通过专用柜正式取回后仍为同一空罐")
	await _clear_world()


func _test_rotated_parent_motion() -> void:
	# 直接读取当前主场景的实际实例变换，不用手写角度替代主场景证据。
	var reference_scene: Node3D = MAIN_SCENE.instantiate() as Node3D
	var reference_tank: Node3D = reference_scene.get_node("interaction_prefabs/machines/waste_liquid_storage_tank_0") as Node3D
	var source_transform: Transform3D = reference_tank.transform
	reference_scene.free()
	for pause_motion: bool in [false, true]:
		var actor: TestActor = _new_actor()
		var tank: AutolysisWasteLiquidStorageTank = WASTE_SCENE.instantiate() as AutolysisWasteLiquidStorageTank
		tank.name = "主场景旋转回归暂停" if pause_motion else "主场景旋转回归自然"
		tank.transform = source_transform
		world.add_child(tank)
		await _frames(2)
		_check(tank.is_configured() and tank.can_toggle(actor), "主场景实际变换下初始化配置与关闭许可有效")
		var animation: Animation = tank.animation_player.get_animation(&"lid_open")
		var expected_rotation: Vector3 = animation.track_get_key_value(0, animation.track_get_key_count(0) - 1)
		_check(tank.try_toggle(actor), "主场景实际变换下正式入口开始开盖")
		if pause_motion:
			await _frames(3)
			var paused_basis: Basis = tank.lid_body.basis
			paused = true
			await _frames(5)
			_check(_basis_error(tank.lid_body.basis, paused_basis) < 0.00001, "主场景旋转下开盖中暂停保持实际姿态")
			paused = false
		await _wait_motion(tank)
		var open_error: float = _basis_error(tank.lid_body.basis, Basis.from_euler(expected_rotation))
		motion_records.append({"阶段": "主场景旋转暂停恢复开盖" if pause_motion else "主场景旋转自然开盖", "主场景原始变换": str(source_transform), "动画末帧角度": str(expected_rotation), "实际盖子角度": str(tank.lid_body.rotation), "期望局部矩阵": str(Basis.from_euler(expected_rotation)), "实际局部矩阵": str(tank.lid_body.basis), "矩阵最大轴差值": open_error, "完全打开": tank.is_open(), "运动中": tank.is_animating(), "配置错误": tank.get_configuration_error()})
		_check(open_error < 0.0003, "主场景旋转后实际盖子矩阵与动画打开端帧一致")
		_check(tank.is_open() and not tank.is_animating() and tank.can_dispose(actor) and tank.can_toggle(actor), "主场景旋转后自然完成开放处置与关闭许可")
		if tank.is_open():
			_check(tank.try_toggle(actor), "主场景实际变换下正式入口反播关闭")
			await _wait_motion(tank)
			var close_error: float = _basis_error(tank.lid_body.basis, Basis.IDENTITY)
			motion_records.append({"阶段": "主场景旋转反播关闭", "实际盖子角度": str(tank.lid_body.rotation), "实际局部矩阵": str(tank.lid_body.basis), "矩阵最大轴差值": close_error, "完全打开": tank.is_open(), "运动中": tank.is_animating()})
			_check(close_error < 0.00001 and not tank.is_open() and not tank.is_animating() and tank.can_toggle(actor) and not tank.can_dispose(actor), "主场景旋转后反播回到真实关闭端帧并恢复开盖许可")
		await _clear_world()


func _basis_error(actual: Basis, expected: Basis) -> float:
	return maxf(actual.x.distance_to(expected.x), maxf(actual.y.distance_to(expected.y), actual.z.distance_to(expected.z)))


func _test_main_scene_inputs_and_refill() -> void:
	await _clear_world()
	world.queue_free()
	await _frames(2)
	world = MAIN_SCENE.instantiate() as Node3D
	root.add_child(world)
	root.size = Vector2i(1280, 720)
	Input.use_accumulated_input = false
	await _frames(8)
	player = world.get_node("autolysis_player") as AutolysisPlayer
	main_tank = world.get_node("interaction_prefabs/machines/waste_liquid_storage_tank_0") as AutolysisWasteLiquidStorageTank
	player.set_physics_process(false)
	player._clear_landing_stun()
	player.is_movement_paused = false
	player.is_showing_ui = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var inventory: AutolysisInventoryController = player.inventory_controller
	var source: AutolysisItemInstance = _filled_instance()
	_check(inventory.try_receive_instance(source) and player.liquid_contents_panel.is_showing_contents(), "真实主场景手持满罐且内容面板可见")
	_check(main_tank.is_configured() and not main_tank.is_open(), "真实主场景继承废液罐关闭初始化")
	player.is_movement_paused = true
	_check(not main_tank.try_toggle(player) and not inventory.try_dispose_in_waste_tank(player, main_tank), "正式玩家输入禁止同时拒绝盖子开闭与库存处置")
	player.is_movement_paused = false
	if not await _aim_reachable(main_tank.lid_body, "主场景关闭盖子"):
		return
	await _capture("01-主场景关闭持满罐.png")
	await _click()
	_check(main_tank.is_animating() and not main_tank.is_open() and source.liquid_contents != null, "主场景真实左键只开始开盖且满罐不变")
	paused = true
	await _click()
	_check(source.liquid_contents != null and not main_tank.is_open(), "主场景动画中暂停点击不倒空")
	paused = false
	await _wait_motion(main_tank)
	_check(main_tank.is_open(), "主场景真实开盖动画自然完成")
	if not await _aim_reachable(main_tank, "主场景打开罐体"):
		return
	await _capture("02-主场景打开持满罐.png")
	# 在真实射线上插入普通碰撞体，验证首命中不会穿透处置。
	var blocker: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.12, 0.12, 0.12)
	collision.shape = shape
	blocker.add_child(collision)
	world.add_child(blocker)
	blocker.global_position = player.interaction_raycast.global_position.lerp(player.interaction_raycast.get_collision_point(), 0.6)
	await _frames(3)
	player.interaction_controller.refresh_state()
	_check(player.interaction_raycast.get_collider() == blocker and not player.interaction_controller.is_direct_available(), "主场景普通遮挡物是首命中且无直接交互许可")
	await _click()
	_check(source.liquid_contents != null, "真实点击遮挡物不向其后废液罐执行倒空")
	blocker.queue_free()
	await _frames(3)
	player.interaction_controller.refresh_state()
	await _click()
	_check(inventory.get_focused_instance() == source and source.is_empty_liquid_tank() and not player.liquid_contents_panel.is_showing_contents(), "主场景罐体真实左键立即倒空原罐并隐藏内容面板")
	_check(AutolysisLiquidTankVisual.get_contents_mesh(player.held_item_presenter.get_display()).material_override == AutolysisLiquidTankVisual.EMPTY_MATERIAL, "主场景空罐材质同步更新")
	await _capture("03-主场景倒空原罐.png")
	var count: Dictionary = {"次数": 0}
	var count_callback: Callable = func() -> void: count["次数"] += 1
	inventory.inventory_changed.connect(count_callback)
	await _click()
	_check(count["次数"] == 0 and inventory.get_focused_instance() == source, "主场景再次点击空罐不产生成功通知")
	inventory.inventory_changed.disconnect(count_callback)
	if not await _aim_reachable(main_tank.lid_body, "主场景已打开盖子仍可关闭"):
		return
	await _click()
	await _wait_motion(main_tank)
	_check(not main_tank.is_open() and main_tank.lid_body.rotation.is_zero_approx(), "真实主场景打开后的盖子仍能首命中并通过左键关闭")
	if not await _aim_reachable(main_tank.lid_body, "主场景再次开盖"):
		return
	await _click()
	await _wait_motion(main_tank)
	_check(inventory.cycle_focus(1) and inventory.try_receive_item(CAFFEINE), "主场景切换空格建立当前原药，原空罐留在其他格")
	if not await _aim_reachable(main_tank, "主场景原药罐体"):
		return
	await _click()
	_check(inventory.get_focused_instance() == null and inventory.get_focused_index() == 1 and player.held_item_presenter.get_display() == null and inventory.get_slot_instance(0) == source, "主场景真实左键销毁当前原药且保留其他格原空罐")
	await _capture("04-主场景销毁原药.png")
	_check(inventory.cycle_focus(-1) and inventory.get_focused_instance() == source, "主场景返回原空罐所在格")
	await _test_actual_blend_refill(source)


func _aim_reachable(wanted: PhysicsBody3D, stage: String) -> bool:
	var collision: CollisionShape3D
	for child: Node in wanted.get_children():
		if child is CollisionShape3D:
			collision = child as CollisionShape3D
			break
	_check(collision != null and collision.shape is BoxShape3D, stage + "使用真实碰撞盒采样")
	if collision == null or not collision.shape is BoxShape3D:
		return false
	var size: Vector3 = (collision.shape as BoxShape3D).size
	var origins: Array[Vector3] = [Vector3(0, 0.9, 0.9), Vector3(-0.8, 0.9, 0.8), Vector3(0.8, 0.9, 0.8), Vector3(0, 0.9, -0.8), Vector3(-0.8, 0.9, -0.8), Vector3(0.8, 0.9, -0.8)]
	for origin: Vector3 in origins:
		player.global_position = main_tank.to_global(origin)
		player.velocity = Vector3.ZERO
		player.main_velocity = Vector3.ZERO
		# 候选高度只是落地起点；以正式角色运动求得实际站立位置。
		player.set_physics_process(true)
		await _frames(25)
		player.set_physics_process(false)
		player._clear_landing_stun()
		if not player.is_on_floor() or not _player_volume_free():
			continue
		for x: float in [-0.35, 0.0, 0.35]:
			for y: float in [0.35, 0.0, -0.35]:
				for z: float in [0.35, 0.0, -0.35]:
					var point: Vector3 = collision.to_global(Vector3(x, y, z) * size)
					player.body.rotation = Vector3.ZERO
					player.neck.rotation = Vector3.ZERO
					player.camera.rotation = Vector3.ZERO
					player.head.look_at(point, Vector3.UP)
					player.interaction_controller.refresh_state()
					if player.interaction_raycast.get_collider() != wanted:
						continue
					await _frames(3)
					player.interaction_controller.refresh_state()
					if player.interaction_raycast.get_collider() == wanted:
						ray_records.append({"阶段": stage, "玩家位置": str(player.global_position), "玩家实际着地": player.is_on_floor(), "玩家碰撞内部无占用": true, "目标点": str(point), "实际命中": str(wanted.get_path()), "起点": str(player.interaction_raycast.global_position), "碰撞点": str(player.interaction_raycast.get_collision_point()), "射线长度": player.interaction_raycast.target_position.length(), "交互许可": player.interaction_controller.is_direct_available(), "盖子旋转": str(main_tank.lid_body.rotation)})
						_check(player.interaction_controller.is_direct_available(), stage + "实际两米中心射线首命中且输入许可有效")
						return true
	_check(false, stage + "在玩家体积无占用位置找到真实首命中")
	return false


func _player_volume_free() -> bool:
	var parameters: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	# 仅剔除接触容差，避免将真实着地的地面接触误记为站立体积被占用。
	var shape: BoxShape3D = player.standing_collision_shape.shape.duplicate() as BoxShape3D
	shape.size -= Vector3(0.002, 0.004, 0.002)
	parameters.shape = shape
	parameters.transform = player.standing_collision_shape.global_transform
	parameters.collision_mask = player.collision_mask
	parameters.exclude = [player.get_rid(), player._found_area.get_rid()]
	parameters.margin = 0.0
	return world.get_world_3d().direct_space_state.intersect_shape(parameters, 1).is_empty()


func _click() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = Vector2(root.size) * 0.5
		event.global_position = event.position
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(2)


func _test_actual_blend_refill(source: AutolysisItemInstance) -> void:
	var machine: AutolysisBlendMachine = world.get_node("interaction_prefabs/machines/machine_blend_0") as AutolysisBlendMachine
	var inventory: AutolysisInventoryController = player.inventory_controller
	_check(machine != null and machine.is_configured(), "真实主场景配药器配置有效")
	if machine == null:
		return
	_check(player.focus_controller.try_enter(machine.focus_target), "倒空后通过真实聚焦会话进入现有配药器")
	await _frames(20)
	_check(player.focus_controller.is_focused_on(machine.focus_target), "配药器相机过渡完成后建立真实聚焦会话")
	_check(inventory.try_place_in_blend_tank_place(player, machine.tank_place), "废液罐倒空后的原实例可通过正式入口重新放入配药器")
	var placed: AutolysisLiquidTank = machine.tank_place.get_stored_item()
	_check(placed != null and placed.item_instance == source and placed.is_empty(), "配药器罐位保留倒空原实例身份与空内容")
	var slot: AutolysisBlendSlot = machine.slots[0]
	_check(slot.try_toggle(player), "正式槽门入口打开零号原药槽")
	await _wait_motion(slot)
	_check(inventory.try_receive_item(SODIUM) and inventory.try_place_in_blend_slot(player, slot), "重新装填通过既有库存接口装入一份苯甲酸钠")
	_check(slot.try_toggle(player), "正式槽门入口关闭装药槽")
	await _wait_motion(slot)
	_check(machine.try_start_processing(player), "空罐和有效原药通过正式入口开始真实两秒配药")
	await _frames(125)
	_check(not machine.is_batch_running() and placed != null and not placed.is_empty() and placed.item_instance == source and source.liquid_contents.get_raw_material_ids() == ["sodium_benzoate"], "真实计时完成后倒空原罐重新获得新药液且原实例保持")
	_check(source.get_phase_rgb() == Vector3.ZERO and source.get_wave_coordinates() == [0, 0, 0, 0, 0], "重新装填结果使用新的零值重构数据，不恢复已废弃旧内容")
	_check(inventory.try_take_from_blend_tank_place(player, machine.tank_place) and inventory.get_focused_instance() == source and player.liquid_contents_panel.is_showing_contents(), "重新装填的同一罐可正式取回且内容面板重新显示")
	await _capture("05-主场景原罐重新装填.png")


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(evidence_directory.path_join(filename)) == OK, "保存实际图形画面：" + filename)
	screenshots.append(filename)


func _save_evidence() -> void:
	var directory: String = ProjectSettings.globalize_path(evidence_directory)
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "废液罐验收证据目录可创建")
	var file: FileAccess = FileAccess.open(directory.path_join("废液罐行为与事务报告.json"), FileAccess.WRITE)
	if file == null:
		_check(false, "废液罐验收报告可写")
		return
	file.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "实际图形后端": graphical, "断言数": assertion_count, "失败数": failures, "断言": records, "运动故障": motion_records, "真实射线": ray_records, "画面": screenshots, "输入范围": "自动注入真实鼠标事件；未声明人工鼠标验收", "参考代码": ["D:/cogito/addons/cogito/CogitoObjects/cogito_door.gd:344", "D:/cogito/addons/cogito/InventoryPD/cogito_inventory.gd:46", "D:/cogito/addons/cogito/InventoryPD/cogito_inventory.gd:120", "res://main-autolysis/systems/item-system/tests/liquid_tank_transaction_test.gd", "res://main-autolysis/systems/item-system/tests/liquid_tank_cabinet_behavior_test.gd", "res://main-autolysis/systems/item-system/tests/liquid_contents_blend_test.gd"]}, "\t"))
	file.close()

func _wait_motion(container: Node) -> void:
	for frame: int in 240:
		if not container.is_animating():
			return
		await _frames(1)
	_check(false, "容器动作等待超过测试上限；配置原因：" + container.get_configuration_error())
