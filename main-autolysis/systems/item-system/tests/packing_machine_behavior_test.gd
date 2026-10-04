extends "res://main-autolysis/player/tests/focus_interaction_test.gd"
## 正式设备、正式玩家、真实有限射线与注入输入的封装验收。

const PACKING_DEMO: PackedScene = preload("res://main-autolysis/systems/item-system/tests/packing_machine_demo.tscn")
const TANK_DEFINITION: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/liquid_tank.tres")
const CAPSULE_DEFINITION: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/pneumatic_capsule.tres")
const WASTE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/waste_liquid_storage_tank_0.tscn")
const INDICATOR_RED: StandardMaterial3D = preload("res://main-autolysis/assets/materials/base_color/mat_base_red_2.tres")
const INDICATOR_BLUE_RUNNING: StandardMaterial3D = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_blue_0.tres")
const INDICATOR_BLUE_READY: StandardMaterial3D = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_blue_1.tres")
const INDICATOR_GREY: StandardMaterial3D = preload("res://main-autolysis/assets/materials/base_color/mat_base_grey_4.tres")

var timing_records: Array[Dictionary] = []
var pose_records: Array[Dictionary] = []
var batch_start_frame: int = 0
var batch_completed_frame: int = 0
var batch_pause_frames: int = 0
var observer_saw_partial: bool = false
var original_lights: Array[Material] = []
var indicator_records: Array[Dictionary] = []
var capsule_reset_notification_seen: bool = false


func run_checks() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/封装器与气动胶囊实施证据/20261003/integration")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	await _test_input_matrix()
	await _new_scene()
	await _enter()
	await _test_transfer_and_animation()
	await _new_scene()
	await _enter()
	for type_index: int in range(3):
		if type_index == 2:
			await _new_scene()
			await _enter()
		await _test_batch(type_index)
	await _test_old_click()
	await _test_disposal()
	await _test_candidate_failures()
	await _test_source_fault()
	await _test_main_packing()
	_save_packing_report()
	_release_controls()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	if is_instance_valid(world):
		world.queue_free()
	await frames(2)
	print("封装集成验收断言数：", assertion_count, "；失败总数：", failures)
	quit(1 if failures > 0 else 0)


func _new_scene() -> void:
	_release_controls()
	paused = false
	if is_instance_valid(world):
		world.queue_free()
		await frames(2)
	world = PACKING_DEMO.instantiate()
	# 继承夹具的配药器会与封装器占用同一位置，入树前移除。
	world.get_node("MachineA").free()
	world.get_node("MachineB").free()
	_prepare_packing_scene()
	root.add_child(world)
	player = world.get_node("Player")
	machine = world.get_node("PackingA")
	other_machine = world.get_node("PackingB")
	focus = player.focus_controller
	inventory = player.inventory_controller
	if not graphical:
		focus.configure(player, player.camera, player.held_item_presenter, _headless_entry_allowed)
	await frames(25)
	check(machine.is_configured() and other_machine.is_configured(), "两台真实封装器配置有效")
	check(machine.tank_place.get_stored_item() == null and machine.capsule_place.get_stored_item() == null and machine.get_selected_type() == -1, "两槽初始为空且没有类型选择")
	_assert_packing_indicators(INDICATOR_RED, false, "设备初始化")
	original_lights.clear()
	for index: int in range(3):
		original_lights.append(machine.get_node("light_type_switch_%d" % index).material_override)
	await _aim_root()


func _prepare_packing_scene() -> void:
	pass


func _aim_root() -> void:
	player.body.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.eyes.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.head.look_at(machine.to_global(Vector3(-0.24, 0.5, 0.32)), Vector3.UP)
	await frames(3)


func _body_pixel(wanted: Node3D, require_hit: bool = true) -> Vector2:
	var held_rectangle: Rect2 = _held_projection_rectangle()
	for child: Node in wanted.get_children():
		if not child is CollisionShape3D or not child.shape is BoxShape3D:
			continue
		var shape: CollisionShape3D = child as CollisionShape3D
		var size: Vector3 = (shape.shape as BoxShape3D).size
		for x: float in [0.0, -0.4, 0.4, -0.2, 0.2]:
			for y: float in [0.0, -0.4, 0.4, -0.2, 0.2]:
				for z: float in [0.4, 0.0, -0.4]:
					var pixel: Vector2 = player.camera.unproject_position(shape.to_global(Vector3(x, y, z) * size))
					if not Rect2(Vector2.ZERO, Vector2(root.size)).has_point(pixel) or held_rectangle.has_point(pixel):
						continue
					if _query(pixel) == wanted:
						ray_records.append({"目标": str(wanted.get_path()), "像素": str(pixel), "物理帧": Engine.get_physics_frames(), "手持投影外": true})
						return pixel
	if require_hit:
		check(false, "真实有限射线找到可见交互入口：" + str(wanted.name) + "（目标节点）")
	return INVALID_PIXEL


func _source_contents(type_index: int = 0) -> AutolysisLiquidContents:
	var ids: Array[String] = ["caffeine", "sodium_benzoate", "caffeine", "sodium_benzoate"]
	if type_index == 0:
		ids = ["caffeine"]
	elif type_index == 2:
		ids = ["sodium_benzoate", "caffeine", "sodium_benzoate"]
	var contents: AutolysisLiquidContents = AutolysisLiquidContents.create_result(ids)
	contents.set_phase_rgb(Vector3(2.5 + type_index, -3.0, 8.0))
	contents.set_wave(true, false, true, true, 0 if type_index == 0 else 6)
	return contents


func _put_tank(contents: AutolysisLiquidContents) -> AutolysisItemInstance:
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(TANK_DEFINITION)
	if contents != null:
		check(instance.set_liquid_contents(contents), "准备完整内容满罐实例")
	check(inventory.try_receive_instance(instance), "选中空格接收液体罐实例")
	await _click(_body_pixel(machine.tank_place))
	var tank: AutolysisLiquidTank = machine.tank_place.get_stored_item()
	check(tank != null and tank.item_instance == instance and inventory.get_focused_instance() == null, "真实罐位点击保持原实例且移除库存来源")
	return instance


func _put_capsule(contents: AutolysisPackingContents = null) -> AutolysisItemInstance:
	if not machine.door.is_open():
		await _click(_body_pixel(machine.door))
		await _wait_packing_motion()
	check(machine.door.is_open(), "胶囊取放前舱门完全打开")
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(CAPSULE_DEFINITION)
	if contents != null:
		check(instance.set_packing_contents(contents), "准备封装胶囊实例")
	check(inventory.try_receive_instance(instance), "选中空格接收胶囊实例")
	await _click(_body_pixel(machine.capsule_place))
	var capsule: AutolysisPneumaticCapsule = machine.capsule_place.get_stored_item()
	check(capsule != null and capsule.item_instance == instance and inventory.get_focused_instance() == null, "真实胶囊位点击保持原实例且移除库存来源")
	return instance


func _test_input_matrix() -> void:
	for tank_state: int in range(3):
		for capsule_state: int in range(3):
			await _new_scene()
			await _enter()
			if tank_state > 0:
				await _put_tank(_source_contents() if tank_state == 2 else null)
			if capsule_state > 0:
				await _put_capsule(AutolysisPackingContents.create_result(_source_contents(), 1) if capsule_state == 2 else null)
			var should_select: bool = tank_state == 2 and capsule_state == 1
			check(machine.try_select_type(player, 0) == should_select, "九种输入组合仅满罐加空胶囊允许选择：%d、%d" % [tank_state, capsule_state])
			await _wait_packing_motion()
			check(machine.can_start_processing() == should_select, "九种组合启动许可与实际合法输入一致")
			_assert_packing_indicators(INDICATOR_BLUE_READY if should_select else INDICATOR_RED, false, "输入组合%d、%d" % [tank_state, capsule_state])


func _test_transfer_and_animation() -> void:
	check(not inventory.try_place_in_packing_tank_place(player, other_machine.tank_place), "跨设备聚焦不允许转移")
	check(inventory.try_receive_item(CAFFEINE), "准备错误种类原药")
	await _click(_body_pixel(machine.tank_place))
	check(inventory.get_focused_item() == CAFFEINE and machine.tank_place.get_stored_item() == null, "错误种类点击不改变来源和槽位")
	await _wheel()
	var first_tank_instance: AutolysisItemInstance = await _put_tank(null)
	var second_tank_instance: AutolysisItemInstance = AutolysisItemInstance.create(TANK_DEFINITION)
	check(inventory.try_receive_instance(second_tank_instance), "准备同种类罐检查已占用入口")
	await _click(_body_pixel(machine.tank_place))
	check(inventory.get_focused_instance() == second_tank_instance and machine.tank_place.get_stored_item().item_instance == first_tank_instance, "已占用槽对合法同种类物品不交换、不覆盖")
	await _wheel()
	var empty_capsule: AutolysisItemInstance = AutolysisItemInstance.create(CAPSULE_DEFINITION)
	check(inventory.try_receive_instance(empty_capsule), "准备空胶囊以检查关闭门禁")
	check(not inventory.try_place_in_packing_capsule_place(player, machine.capsule_place), "关闭舱门拒绝胶囊放入")
	var capsule_center: Vector2 = player.camera.unproject_position(machine.capsule_place.get_node("collision_pneumatic_capsule_slot").global_position)
	check(_query(capsule_center) == machine.door, "关闭舱门实际阻挡胶囊槽射线")
	await _click(_body_pixel(machine.door))
	check(machine.door.is_animating() and not inventory.try_place_in_packing_capsule_place(player, machine.capsule_place), "舱门运动中拒绝胶囊放入")
	await _wait_packing_motion()
	await _click(_body_pixel(machine.capsule_place))
	check(machine.capsule_place.get_stored_item().item_instance == empty_capsule, "完全开门后放入原胶囊")
	check(not machine.try_select_type(player, 0), "空罐加空胶囊不能选类型")
	var tank: AutolysisLiquidTank = machine.tank_place.get_stored_item()
	var stored_tank_instance: AutolysisItemInstance = tank.item_instance
	check(tank.apply_contents(_source_contents()), "夹具对真实罐写入合法源内容")
	await _click(_body_pixel(machine.type_switches[0]))
	await frames(2)
	check(machine.get_selected_type() == 0 and not machine.can_start_processing(), "开关开启途中已经唯一选中但不能启动")
	_assert_packing_indicators(INDICATOR_RED, false, "类型开关开启途中")
	check(not machine.try_select_type(player, 1), "开关动作途中拒绝新的类型点击")
	await _click(_body_pixel(machine.tank_place))
	check(machine.get_selected_type() == -1 and inventory.get_focused_instance() == stored_tank_instance, "开启途中成功取罐立即取消类型")
	await _wait_packing_motion()
	check(not machine.type_switches[0].is_selected() and not machine.type_switches[0].is_animating(), "中途反播自然归位且旧回调不恢复选择")
	check(machine.door.is_open(), "开关复位不改变舱门")
	await _click(_body_pixel(machine.tank_place))
	await _click(_body_pixel(machine.type_switches[0]))
	await _wait_packing_motion()
	await _click(_body_pixel(machine.type_switches[2]))
	await _wait_packing_motion()
	check(machine.get_selected_type() == 2 and not machine.type_switches[0].is_selected() and machine.type_switches[2].is_selected(), "改选时旧开关关闭、新开关开启")
	await _click(_body_pixel(machine.type_switches[2]))
	await _wait_packing_motion()
	_record_machine_state("取消类型后")
	check(machine.get_selected_type() == -1 and not machine.can_start_processing(), "再次点击当前类型取消选择")
	_assert_packing_indicators(INDICATOR_RED, false, "取消类型选择")
	_assert_original_lights()
	var blocker: StaticBody3D = box(Vector3(0.08, 0.08, 0.08), player.camera.global_position.lerp(machine.start_button.global_position, 0.5))
	var blocked_pixel: Vector2 = player.camera.unproject_position(machine.start_button.global_position)
	await frames(2)
	check(_query(blocked_pixel) == null, "未登记外部物体阻挡真实聚焦射线")
	blocker.queue_free()
	await frames(2)


func _assert_original_lights() -> void:
	for index: int in range(3):
		check(machine.get_node("light_type_switch_%d" % index).material_override == original_lights[index], "关闭后分别恢复第%d盏灯的原材质" % index)


func _assert_completion_indicators(completed: bool, label: String) -> void:
	var expected: StandardMaterial3D = INDICATOR_BLUE_RUNNING if completed else INDICATOR_GREY
	for index: int in range(2):
		var mesh: MeshInstance3D = machine.get_node("light_packing_complete_sign/light_packing_complete_sign_mesh_%d" % index) as MeshInstance3D
		check(mesh.material_override == expected, "%s：第%d盏完成灯保持指定%s材质" % [label, index, "蓝色常亮" if completed else "灰色"])
		if completed:
			check(is_equal_approx((mesh.material_override as StandardMaterial3D).emission_energy_multiplier, 2.0), "%s：第%d盏完成灯倍率保持二" % [label, index])


func _assert_packing_indicators(expected: StandardMaterial3D, completed: bool, label: String) -> void:
	var mesh: MeshInstance3D = machine.get_node("button_start_packing/button_press") as MeshInstance3D
	check(mesh.material_override == expected, "%s：开始按钮使用指定固定材质" % label)
	check(machine.get("_indicator_tween") == null, "%s：没有残留按钮闪烁补间" % label)
	if expected == INDICATOR_BLUE_READY:
		check(is_equal_approx((mesh.material_override as StandardMaterial3D).emission_energy_multiplier, INDICATOR_BLUE_READY.emission_energy_multiplier), "%s：按钮就绪或完成待取沿用一号蓝色倍率" % label)
	_assert_completion_indicators(completed, label)
	indicator_records.append({"位置": label, "按钮材质": mesh.material_override.resource_path, "完成灯亮": completed, "物理帧": Engine.get_physics_frames(), "运行补间": machine.get("_indicator_tween") != null})


func _assert_running_indicator(label: String) -> void:
	var mesh: MeshInstance3D = machine.get_node("button_start_packing/button_press") as MeshInstance3D
	var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	var blink: Tween = machine.get("_indicator_tween") as Tween
	check(material != null and material == machine.get("_indicator_blue_material") and material != INDICATOR_BLUE_RUNNING, "%s：按钮使用本机独立蓝色运行材质" % label)
	check(is_instance_valid(blink) and blink.is_valid() and blink.is_running(), "%s：只有既有运行补间持续闪烁" % label)
	if material != null:
		check(material.emission_energy_multiplier >= 0.0 and material.emission_energy_multiplier <= 2.0, "%s：运行发光倍率处于零至二" % label)
	_assert_completion_indicators(false, label)
	indicator_records.append({"位置": label, "按钮材质实例": material.get_instance_id() if material != null else 0, "倍率": material.emission_energy_multiplier if material != null else -1.0, "完成灯亮": false, "物理帧": Engine.get_physics_frames(), "运行补间": is_instance_valid(blink) and blink.is_valid()})


func _test_batch(type_index: int) -> void:
	var source: AutolysisLiquidContents = _source_contents(type_index)
	var tank_instance: AutolysisItemInstance = await _put_tank(source)
	var capsule_instance: AutolysisItemInstance = await _put_capsule()
	check(not machine.can_start_processing(), "合法输入尚未选类型不能启动")
	_assert_packing_indicators(INDICATOR_RED, false, "合法输入尚未选类型")
	await _click(_body_pixel(machine.type_switches[type_index]))
	await _wait_packing_motion()
	_record_machine_state("本轮选择后%d" % type_index)
	check(machine.get_selected_type() == type_index and machine.can_start_processing(), "类型开启保持末帧且完全开门可启动")
	_assert_packing_indicators(INDICATOR_BLUE_READY, false, "完全开门且类型稳定")
	check(machine.tank_place.try_begin_transfer(player), "启动前取得真实罐位转移锁")
	check(not machine.can_start_processing(), "转移事务未结束禁止启动")
	await frames(1)
	_assert_packing_indicators(INDICATOR_RED, false, "启动前取放事务保持锁定")
	machine.tank_place.end_transfer()
	await frames(1)
	_assert_packing_indicators(INDICATOR_BLUE_READY, false, "启动前取放事务结束")
	var glowing: int = 0
	for index: int in range(3):
		if machine.get_node("light_type_switch_%d" % index).material_override == load("res://main-autolysis/assets/materials/glow_color/mat_glow_green_0.tres"):
			glowing += 1
	check(glowing == 1, "选择提交后只有一盏灯使用指定发光材质")
	if type_index == 1:
		await _click(_body_pixel(machine.door))
		check(not machine.can_start_processing(), "关闭舱门途中禁止启动")
		_assert_packing_indicators(INDICATOR_RED, false, "舱门关闭途中")
		await _wait_packing_motion()
		check(machine.door.is_closed() and machine.can_start_processing(), "完全关门仍可启动")
		_assert_packing_indicators(INDICATOR_BLUE_READY, false, "完全关门且类型稳定")
	observer_saw_partial = false
	if not machine.processing_started.is_connected(_record_batch_start):
		machine.processing_started.connect(_record_batch_start)
		machine.processing_completed.connect(_record_batch_end)
	tank_instance.changed.connect(_observe_batch.bind(tank_instance, capsule_instance))
	capsule_instance.changed.connect(_observe_batch.bind(tank_instance, capsule_instance))
	batch_start_frame = Engine.get_physics_frames()
	batch_pause_frames = 0
	await _click(_body_pixel(machine.start_button))
	check(machine.is_batch_running() and tank_instance.liquid_contents != null and capsule_instance.is_empty_pneumatic_capsule(), "按钮接受后立即计时且完成前两件内容不变")
	_assert_running_indicator("真实按钮点击被接受")
	check(not machine.try_start_processing(player), "同帧重入不能启动第二批次")
	machine.processing_timer.timeout.emit()
	check(machine.is_batch_running() and tank_instance.liquid_contents != null and capsule_instance.is_empty_pneumatic_capsule(), "提前完成回调不能越过真实两秒计时")
	check(not machine.door.try_toggle(player) and not machine.try_select_type(player, 2), "运行中门和类型业务锁定")
	check(not inventory.try_take_from_packing_tank_place(player, machine.tank_place) and not inventory.try_take_from_packing_capsule_place(player, machine.capsule_place), "运行中两个库存转移入口锁定")
	check(not machine.root_interaction.try_interact(player, AutolysisInteractionComponent.InteractionMode.FOCUS), "运行中根设备交互锁定")
	var remaining: float = machine.processing_timer.time_left
	var frozen_material: StandardMaterial3D = machine.get("_indicator_blue_material") as StandardMaterial3D
	var frozen_energy: float = frozen_material.emission_energy_multiplier
	paused = true
	var pause_start: int = Engine.get_physics_frames()
	await frames(20)
	batch_pause_frames += Engine.get_physics_frames() - pause_start
	check(is_equal_approx(remaining, machine.processing_timer.time_left), "暂停期间计时剩余量完全不变")
	check(is_equal_approx(frozen_energy, frozen_material.emission_energy_multiplier), "暂停期间真实按钮闪烁倍率不推进")
	paused = false
	await _exit()
	check(not focus.can_enter(machine.focus_target) and not focus.try_enter(machine.focus_target), "右键退出有效且运行中拒绝重新进入")
	_assert_running_indicator("运行中退出聚焦")
	for _index: int in range(150):
		if not machine.is_batch_running():
			break
		await frames(1)
	var effective_frames: int = batch_completed_frame - batch_start_frame - batch_pause_frames
	timing_records.append({"封装类型": type_index, "有效物理帧数": effective_frames, "暂停物理帧数": batch_pause_frames, "物理帧率": Engine.physics_ticks_per_second, "计时秒数": machine.PROCESSING_SECONDS})
	check(effective_frames >= Engine.physics_ticks_per_second * 2 and effective_frames <= Engine.physics_ticks_per_second * 2 + 1, "实际接受至完成的游戏时间为两秒至一个物理采样帧误差")
	check(not machine.is_batch_running() and tank_instance.is_empty_liquid_tank() and not capsule_instance.is_empty_pneumatic_capsule(), "退出聚焦后自然完成得到空罐和封装胶囊")
	_assert_packing_indicators(INDICATOR_BLUE_READY, true, "退出聚焦后自然完成")
	check(not observer_saw_partial, "所有实例变化观察者只看到成对完成状态")
	var packed_contents: AutolysisPackingContents = capsule_instance.packing_contents
	if packed_contents == null:
		check(false, "本轮未完成产物，停止该分支避免空引用")
		return
	check(packed_contents != null and packed_contents.get_raw_material_ids() == source.get_raw_material_ids() and packed_contents.get_phase_rgb() == source.get_phase_rgb() and packed_contents.get_wave_coordinates() == source.get_wave_coordinates() and packed_contents.get_packing_type() == type_index, "产物完整保留原药顺序重复、相位、波形与本轮类型")
	machine.processing_timer.timeout.emit()
	check(capsule_instance.packing_contents.get_raw_material_ids() == source.get_raw_material_ids(), "重复完成回调不改变产物")
	await _enter()
	_assert_packing_indicators(INDICATOR_BLUE_READY, true, "完成后重新进入聚焦")
	if not machine.door.is_open():
		await _click(_body_pixel(machine.door))
		_assert_packing_indicators(INDICATOR_BLUE_READY, true, "完成后舱门运动中")
		await _wait_packing_motion()
		_assert_packing_indicators(INDICATOR_BLUE_READY, true, "完成后完全开门")
	if type_index != 1:
		await _click(_body_pixel(machine.tank_place))
		check(inventory.get_focused_instance() == tank_instance and machine.get_selected_type() == type_index, "完成后先取空罐保留选中类型")
		_assert_packing_indicators(INDICATOR_BLUE_READY, true, "完成后先取空罐")
		check(tank_instance.set_liquid_contents(_source_contents(2)), "原罐再次装填不会改动产物")
		await _click(_body_pixel(machine.tank_place))
		check(machine.get_selected_type() == type_index and not machine.can_start_processing() and not machine.try_select_type(player, 1), "完成待取时补满罐仍保留类型并拒绝再封装")
		_assert_packing_indicators(INDICATOR_BLUE_READY, true, "完成待取时补满罐")
	if type_index == 0:
		var capsule_definition: AutolysisItemDefinition = capsule_instance.definition
		var original_visual: PackedScene = capsule_definition.visual_scene
		var empty_visual: Node3D = Node3D.new()
		var broken: PackedScene = PackedScene.new()
		broken.pack(empty_visual)
		empty_visual.free()
		capsule_definition.visual_scene = broken
		check(not inventory.try_take_from_packing_capsule_place(player, machine.capsule_place) and machine.capsule_place.get_stored_item().item_instance == capsule_instance and machine.get_selected_type() == type_index, "产物取回候选失败保持胶囊占用、完成身份与类型")
		_assert_packing_indicators(INDICATOR_BLUE_READY, true, "产物取回候选失败")
		capsule_definition.visual_scene = original_visual
	capsule_reset_notification_seen = false
	var reset_observer: Callable = _observe_capsule_take.bind(capsule_instance)
	inventory.inventory_changed.connect(reset_observer)
	await _click(_body_pixel(machine.capsule_place))
	inventory.inventory_changed.disconnect(reset_observer)
	check(inventory.get_focused_instance() == capsule_instance and machine.get_selected_type() == -1, "成功取回本轮胶囊才清除完成记录和类型")
	check(capsule_reset_notification_seen, "真实成功取胶囊路径发布已复位的库存变化通知")
	_assert_packing_indicators(INDICATOR_RED, false, "成功取回本轮胶囊")
	await _wait_packing_motion()
	_assert_original_lights()
	var panel: AutolysisLiquidContentsPanel = player.get_node("LiquidContentsPanel") as AutolysisLiquidContentsPanel
	check(panel.is_showing_contents() and panel.get_contents_text().contains("气动胶囊") and panel.get_contents_text().contains(packed_contents.get_packing_type_display()) and panel.get_contents_text().contains("波形重构"), "取回封装胶囊临时面板显示全部内容和封装类型")
	check(AutolysisPneumaticCapsuleVisual.get_contents_mesh(player.held_item_presenter.get_display()).material_override == load("res://main-autolysis/assets/materials/glow_color/mat_glow_green_0.tres"), "取回手持胶囊使用指定绿色标识")
	_check_capsule_pose("封装类型%d" % type_index)
	await _capture("胶囊产物-%d.png" % type_index)
	await _click(_body_pixel(machine.capsule_place))
	check(machine.capsule_place.get_stored_item().item_instance == capsule_instance and machine.get_selected_type() == -1 and not machine.can_start_processing(), "封装胶囊放回保持数据且不能二次封装")
	await _click(_body_pixel(machine.capsule_place))
	check(capsule_instance.packing_contents.get_phase_rgb() == source.get_phase_rgb(), "再次取回封装胶囊数据独立")
	await _wheel()
	check(not panel.is_showing_contents(), "切换至空格立即隐藏内容面板")
	await _click(_body_pixel(machine.tank_place))
	check(inventory.get_focused_instance() == tank_instance and machine.tank_place.get_stored_item() == null, "产物先取或后取两种顺序都可取回罐")
	await _wheel()


func _observe_batch(tank: AutolysisItemInstance, capsule: AutolysisItemInstance) -> void:
	if machine.is_batch_running() and tank.is_empty_liquid_tank() != (not capsule.is_empty_pneumatic_capsule()):
		observer_saw_partial = true
	if machine.is_batch_running() and tank.is_empty_liquid_tank() and not capsule.is_empty_pneumatic_capsule():
		_assert_running_indicator("共同提交内容通知仍保持运行显示")


func _record_batch_start(_batch_id: int) -> void:
	batch_start_frame = Engine.get_physics_frames()
	batch_completed_frame = 0
	_assert_running_indicator("同步开始通知")
	check(is_equal_approx((machine.get("_indicator_blue_material") as StandardMaterial3D).emission_energy_multiplier, 2.0), "同步开始通知已在倍率二进入闪烁")
	var press_animation: AnimationPlayer = machine.start_button.get("_runtime_player") as AnimationPlayer
	check(press_animation.is_playing() and is_zero_approx(press_animation.current_animation_position), "按钮按压动画起点的开始通知已经进入运行灯态")


func _record_batch_end(_batch_id: int, _contents: AutolysisPackingContents) -> void:
	batch_completed_frame = Engine.get_physics_frames()
	_assert_packing_indicators(INDICATOR_BLUE_READY, true, "同步完成通知")


func _observe_capsule_take(capsule: AutolysisItemInstance) -> void:
	if inventory.get_focused_instance() != capsule:
		return
	capsule_reset_notification_seen = true
	check(machine.capsule_place.get_stored_item() == null and machine.get_completed_capsule_instance() == null and machine.get_selected_type() == -1, "库存变化通知前本轮胶囊来源、完成记录和类型已经清空")
	check(machine.capsule_place.is_transfer_busy(), "成功取胶囊库存通知仍处于原取放事务内")
	_assert_packing_indicators(INDICATOR_RED, false, "成功取胶囊的库存变化通知")


func _record_batch_failure(_batch_id: int, _reason: String) -> void:
	_assert_packing_indicators(INDICATOR_RED, false, "同步失败通知")


func _test_old_click() -> void:
	await _new_scene()
	await _enter()
	check(inventory.try_receive_item(TANK_DEFINITION), "准备旧请求来源罐")
	var source: AutolysisItemInstance = inventory.get_focused_instance()
	var point: Vector2 = _body_pixel(machine.tank_place)
	_button(MOUSE_BUTTON_LEFT, true, point)
	check(inventory.cycle_focus(1), "点击入队后真实库存切换选中格")
	await frames(1)
	_button(MOUSE_BUTTON_LEFT, false, point)
	check(machine.tank_place.get_stored_item() == null and inventory.get_slot_instance(0) == source, "旧选中格快照请求拒绝且保留来源")


func _test_disposal() -> void:
	if not graphical:
		print("无图形模式不覆盖普通鼠标捕获处置入口，图形轮次执行该项。")
		return
	await _exit()
	var waste: AutolysisWasteLiquidStorageTank = WASTE_SCENE.instantiate() as AutolysisWasteLiquidStorageTank
	world.add_child(waste)
	waste.position = Vector3(4, 0.75, 0)
	await _wait_container_open(waste, false)
	for sealed: bool in [false, true]:
		var instance: AutolysisItemInstance = AutolysisItemInstance.create(CAPSULE_DEFINITION)
		if sealed:
			instance.set_packing_contents(AutolysisPackingContents.create_result(_source_contents(), 2))
		check(inventory.try_receive_instance(instance), "准备废弃胶囊")
		check(not inventory.try_dispose_in_waste_tank(player, waste), "关闭罐盖拒绝胶囊废弃")
		check(waste.try_toggle(player), "开启正式废液罐盖")
		check(not inventory.try_dispose_in_waste_tank(player, waste), "运动罐盖拒绝胶囊废弃")
		await _wait_container_open(waste, true)
		check(inventory.try_dispose_in_waste_tank(player, waste) and inventory.get_focused_instance() == null and player.held_item_presenter.get_display() == null, "空或封装胶囊均整件销毁且不留下空壳")
		check(waste.try_toggle(player), "关闭正式废液罐盖")
		await _wait_container_open(waste, false)


func _test_candidate_failures() -> void:
	await _new_scene()
	await _enter()
	var definition: AutolysisItemDefinition = TANK_DEFINITION.duplicate() as AutolysisItemDefinition
	var source: AutolysisItemInstance = AutolysisItemInstance.create(definition)
	source.set_liquid_contents(_source_contents())
	check(inventory.try_receive_instance(source), "候选故障准备原满罐")
	check(not inventory.try_place_in_packing_tank_place(player, other_machine.tank_place) and inventory.get_focused_instance() == source and other_machine.tank_place.get_stored_item() == null, "手持合法满罐跨设备请求拒绝且保持来源")
	var original_world: String = definition.world_scene_path
	definition.world_scene_path = "res://main-autolysis/scenes/prefabs/prefab_machines/pneumatic_capsules_0.tscn"
	check(not inventory.try_place_in_packing_tank_place(player, machine.tank_place) and inventory.get_focused_instance() == source and machine.tank_place.get_stored_item() == null, "候选世界种类不匹配不丢失原满罐")
	definition.world_scene_path = original_world
	check(inventory.try_place_in_packing_tank_place(player, machine.tank_place), "修复候选后可以放入同一满罐")
	var original_visual: PackedScene = definition.visual_scene
	var empty_visual: Node3D = Node3D.new()
	var broken: PackedScene = PackedScene.new()
	broken.pack(empty_visual)
	empty_visual.free()
	definition.visual_scene = broken
	check(not inventory.try_take_from_packing_tank_place(player, machine.tank_place) and inventory.get_focused_instance() == null and machine.tank_place.get_stored_item().item_instance == source and source.liquid_contents != null, "手持候选缺少内容网格不改变罐位和源内容")
	definition.visual_scene = original_visual
	check(inventory.try_take_from_packing_tank_place(player, machine.tank_place), "候选修复后取回保持实例")


func _test_source_fault() -> void:
	await _new_scene()
	await _enter()
	var tank: AutolysisItemInstance = await _put_tank(_source_contents())
	var capsule: AutolysisItemInstance = await _put_capsule()
	await _click(_body_pixel(machine.type_switches[0]))
	await _wait_packing_motion()
	machine.processing_started.connect(_record_batch_start)
	machine.processing_failed.connect(_record_batch_failure)
	await _click(_body_pixel(machine.start_button))
	check(machine.is_batch_running(), "来源变化故障批次真实启动")
	_assert_running_indicator("来源变化故障批次启动后")
	tank.liquid_contents.set_phase_rgb(Vector3(99, 8, 7))
	await frames(130)
	check(not machine.is_batch_running() and not machine.get_processing_fault().is_empty() and tank.liquid_contents != null and capsule.is_empty_pneumatic_capsule(), "完成前源字段变化拒绝提交且没有半件产物")
	_assert_packing_indicators(INDICATOR_RED, false, "来源变化拒绝提交后")


func _test_main_packing() -> void:
	await _new_scene()
	world.queue_free()
	await frames(2)
	world = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate()
	root.add_child(world)
	player = world.get_node("autolysis_player")
	machine = world.get_node("interaction_prefabs/machines/machine_packing_0")
	focus = player.focus_controller
	inventory = player.inventory_controller
	if not graphical:
		focus.configure(player, player.camera, player.held_item_presenter, _headless_entry_allowed)
	player.global_position = machine.to_global(Vector3(-0.24, -0.1, 1.7))
	player.velocity = Vector3.ZERO
	player.main_velocity = Vector3.ZERO
	await frames(35)
	await _enter()
	check(machine.is_configured() and machine.tank_place.get_stored_item() == null and machine.capsule_place.get_stored_item() == null, "实际主场景封装器初始空槽并正常聚焦")
	_assert_packing_indicators(INDICATOR_RED, false, "实际主场景初始空槽")
	await _put_tank(_source_contents(1))
	await _put_capsule()
	await _click(_body_pixel(machine.type_switches[1]))
	await _wait_packing_motion()
	_assert_packing_indicators(INDICATOR_BLUE_READY, false, "实际主场景准备完成")
	await _capture("主场景封装器已准备.png")
	await _click(_body_pixel(machine.start_button))
	_assert_running_indicator("实际主场景按钮点击被接受")
	await frames(130)
	check(machine.tank_place.get_stored_item().is_empty() and not machine.capsule_place.get_stored_item().item_instance.is_empty_pneumatic_capsule(), "实际主场景真实射线点击完成封装")
	_assert_packing_indicators(INDICATOR_BLUE_READY, true, "实际主场景完成封装")
	await _click(_body_pixel(machine.capsule_place))
	_assert_packing_indicators(INDICATOR_RED, false, "实际主场景成功取胶囊")
	_check_capsule_pose("主场景")
	await _capture("主场景胶囊手持.png")
	await _exit()


func _save_packing_report() -> void:
	var report: Dictionary = {"图形运行": graphical, "断言数": assertion_count, "失败数": failures, "断言": records, "提示灯观察": indicator_records, "计时采样": timing_records, "实际射线": ray_records, "手持投影": pose_records, "截图": screenshots}
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("封装器验收报告.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))


func _check_capsule_pose(label: String) -> void:
	var bounds: Rect2 = _held_projection_rectangle()
	var visible_region: Rect2 = Rect2(Vector2(16, 16), Vector2(root.size) - Vector2(32, 32))
	check(bounds.has_area() and visible_region.encloses(bounds), "整件手持胶囊完整入画且至少保留十六像素边距：" + label)
	pose_records.append({"位置": label, "投影包围矩形": str(bounds), "视场角": player.camera.fov, "画面尺寸": str(root.size), "完整入画": visible_region.encloses(bounds)})


func _record_machine_state(label: String) -> void:
	var switches: Array[Dictionary] = []
	for control: Node in machine.type_switches:
		var runtime: AnimationPlayer = control.get("_runtime_player") as AnimationPlayer
		switches.append({"选中": control.is_selected(), "运动": control.is_animating(), "状态": control.state, "角度": str(control.rotation), "配置错误": control.get_configuration_error(), "播放中": runtime.is_playing(), "进度": runtime.current_animation_position, "速度": runtime.get_playing_speed(), "待完成": control.get("_completion_pending")})
	print("设备观测：", JSON.stringify({"位置": label, "类型": machine.get_selected_type(), "输入合法": machine.has_valid_inputs(), "转移锁": machine.are_transfers_busy(), "故障": machine.get_processing_fault(), "启动拒绝": machine.get_start_denial_reason(), "开关": switches}))



func _wait_packing_motion(device: AutolysisPackingMachine = null) -> void:
	var target_device: AutolysisPackingMachine = machine as AutolysisPackingMachine if device == null else device
	var deadline: int = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 5
	while is_instance_valid(target_device) and (target_device.door.is_animating() or target_device.are_switches_animating()) and Engine.get_physics_frames() < deadline:
		await frames(1)
	check(is_instance_valid(target_device) and not target_device.door.is_animating() and not target_device.are_switches_animating(), "目标门及开关在测试上限内完成；状态按自然完成确认")
	await frames(1)


func _wait_container_open(container: AutolysisWasteLiquidStorageTank, opened: bool) -> void:
	var deadline: int = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 5
	while is_instance_valid(container) and container.is_animating() and Engine.get_physics_frames() < deadline:
		await frames(1)
	check(is_instance_valid(container) and container.is_open() == opened and not container.is_animating(), "废液罐目标开闭在测试上限内完成")
