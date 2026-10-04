extends "res://main-autolysis/systems/item-system/tests/liquid_contents_blend_test.gd"
## 指示灯专项验收：实际库存事务、门动画、批次计时、材质隔离和真实渲染。

var waveform_samples: Array[Dictionary] = []
var render_samples: Array[Dictionary] = []
var waveform_max_error: float = 0.0
var sampled_frames: int = 0
var saved_time_scale: float = 1.0


func run_checks() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	saved_time_scale = Engine.time_scale
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/配药器状态指示灯实施证据/20261004/indicator")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	batch_clock = BatchClock.new()
	root.add_child(batch_clock)
	await _test_start_conditions_and_transactions()
	await _test_waveform_and_isolation()
	await _test_completed_credential_and_two_batches()
	await _test_external_fill_and_credential_invalidation()
	await _test_tank_exit()
	await _test_machine_exit()
	await _test_indicator_loss()
	_save_indicator_report()
	_release_controls()
	paused = false
	Engine.time_scale = saved_time_scale
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	if is_instance_valid(world):
		world.queue_free()
	await frames(2)
	print("配药器指示灯验收断言数：", assertion_count, "；失败总数：", failures, "；波形最大误差：", waveform_max_error)
	quit(1 if failures > 0 else 0)


func _fresh_indicator_case() -> void:
	Engine.time_scale = 1.0
	await _new_scene()
	await _enter()
	_check_indicator(INDICATOR_DEFAULT, "正式设备初始红色且没有补间")


func _focus_device(device: AutolysisBlendMachine) -> void:
	await _exit()
	check(focus.try_enter(device.focus_target), "正式公开入口进入目标设备聚焦")
	await frames(20)
	check(focus.is_focused_on(device.focus_target), "目标设备聚焦稳定完成")


func _place_indicator_tank(device: AutolysisBlendMachine, definition: AutolysisItemDefinition = TANK_DEFINITION) -> void:
	check(inventory.try_receive_item(definition), "库存接收合法独立空罐")
	check(inventory.try_place_in_blend_tank_place(player, device.tank_place), "正式库存事务将空罐放入目标设备")
	await frames(2)


func _place_indicator_raw(device: AutolysisBlendMachine, index: int = 0) -> void:
	var slot: AutolysisBlendSlot = device.slots[index]
	check(slot.try_toggle(player), "正式槽门入口开始打开原药槽")
	await frames(15)
	check(slot.is_open(), "真实门动画完成到打开状态")
	check(inventory.try_receive_item(CAFFEINE) and inventory.try_place_in_blend_slot(player, slot), "正式库存事务将原药放入已打开槽")
	check(slot.try_toggle(player), "正式槽门入口开始关闭原药槽")
	await frames(15)
	check(slot.is_closed(), "真实门动画完成到关闭状态")


func _prepare_indicator_ready(definition: AutolysisItemDefinition = TANK_DEFINITION) -> void:
	await _fresh_indicator_case()
	await _place_indicator_tank(machine as AutolysisBlendMachine, definition)
	await _place_indicator_raw(machine as AutolysisBlendMachine)
	_check_indicator(INDICATOR_READY, "一份合法原药、合法空罐、四门关闭且事务结束后橙色就绪")


func _test_start_conditions_and_transactions() -> void:
	await _fresh_indicator_case()
	await _capture_indicator("01-default-red.png")
	await _place_indicator_raw(machine as AutolysisBlendMachine)
	_check_indicator(INDICATOR_DEFAULT, "只有合法原药没有罐时红色")
	await _place_indicator_tank(machine as AutolysisBlendMachine)
	_check_indicator(INDICATOR_READY, "最后一项空罐事务结束触发橙色就绪")
	await _capture_indicator("02-ready-orange.png")
	var device: AutolysisBlendMachine = machine as AutolysisBlendMachine
	var reference: Camera3D = device.reference_camera
	device.reference_camera = null
	await frames(2)
	_check_indicator(INDICATOR_DEFAULT, "非运行阶段机体配置失效时使用红色")
	device.reference_camera = reference
	await frames(20)
	_check_indicator(INDICATOR_READY, "配置恢复后重新按完整启动条件显示橙色")
	if not focus.is_focused_on(device.focus_target):
		await _focus_device(device)
	var slot: AutolysisBlendSlot = machine.slots[1]
	check(slot.try_toggle(player), "就绪后公开入口打开空槽门")
	await frames(1)
	_check_indicator(INDICATOR_DEFAULT, "空槽门打开动画开始后红色")
	await frames(15)
	_check_indicator(INDICATOR_DEFAULT, "空槽门完全打开后仍为红色")
	check(slot.try_toggle(player), "公开入口关闭空槽门")
	await frames(1)
	_check_indicator(INDICATOR_DEFAULT, "空槽门关闭动画期间仍为红色")
	await frames(15)
	_check_indicator(INDICATOR_READY, "最后槽门关闭动画结束触发橙色就绪")
	check(machine.tank_place.try_begin_transfer(player), "合法罐位事务开始")
	await frames(2)
	_check_indicator(INDICATOR_DEFAULT, "罐位事务忙碌时红色")
	machine.tank_place.end_transfer()
	await frames(2)
	_check_indicator(INDICATOR_READY, "罐位失败回滚保留空罐且事务结束恢复橙色")
	check(inventory.try_take_from_blend_tank_place(player, machine.tank_place), "正式库存事务移走最后空罐")
	await frames(2)
	_check_indicator(INDICATOR_DEFAULT, "取走空罐事务结束后红色")
	check(inventory.try_place_in_blend_tank_place(player, machine.tank_place), "同一个空罐可经正式事务重新放入")
	await frames(2)
	_check_indicator(INDICATOR_READY, "重新放罐事务结束后恢复橙色")
	slot = machine.slots[0]
	check(slot.try_toggle(player), "正式入口打开最后原药所在槽")
	await frames(15)
	check(inventory.try_take_from_blend_slot(player, slot), "正式库存事务移走最后原药")
	check(slot.try_toggle(player), "取药后关闭空槽")
	await frames(15)
	_check_indicator(INDICATOR_DEFAULT, "移走最后原药并关门后红色")
	await _fresh_indicator_case()
	await _place_indicator_tank(machine as AutolysisBlendMachine)
	_check_indicator(INDICATOR_DEFAULT, "只有合法空罐没有原药时红色")
	check(not machine.try_start_processing(player), "未满足完整条件时拒绝启动")
	_check_indicator(INDICATOR_DEFAULT, "启动拒绝不建立运行补间")


func _expected_energy(elapsed: float) -> float:
	var phase: float = fposmod(elapsed, 1.0)
	return 2.0 - phase * 4.0 if phase <= 0.5 else (phase - 0.5) * 4.0


func _test_waveform_and_isolation() -> void:
	await _prepare_indicator_ready()
	await _focus_device(other_machine as AutolysisBlendMachine)
	await _place_indicator_tank(other_machine as AutolysisBlendMachine)
	await _place_indicator_raw(other_machine as AutolysisBlendMachine)
	_check_indicator(INDICATOR_READY, "第二台设备独立处于橙色就绪", other_machine)
	await _focus_device(machine as AutolysisBlendMachine)
	var orange: StandardMaterial3D = machine.get("_indicator_orange_material") as StandardMaterial3D
	var other_orange: StandardMaterial3D = other_machine.get("_indicator_orange_material") as StandardMaterial3D
	check(orange != other_orange and orange != INDICATOR_ORANGE and other_orange != INDICATOR_ORANGE, "两台设备各自复制橙色材质且均不修改原始资源")
	check(orange.albedo_texture == INDICATOR_ORANGE.albedo_texture and other_orange.albedo_texture == INDICATOR_ORANGE.albedo_texture and INDICATOR_ORANGE.albedo_texture != null, "设备橙色副本独立持有数值但共享原始纹理引用")
	check(machine.try_start_processing(player), "公开批次入口实际成功启动")
	_check_indicator(INDICATOR_RUNNING, "实际成功启动同步创建唯一运行补间")
	var tween: Tween = machine.get("_indicator_tween") as Tween
	var origin: float = batch_clock.effective_seconds
	var high_luminance: float = await _capture_indicator("03-running-high-orange.png")
	var low_luminance: float = -1.0
	var tested_pause: bool = false
	var tested_scale: bool = false
	var tested_refresh: bool = false
	var tested_exit: bool = false
	var captured_low: bool = false
	var one_frame_energy_tolerance: float = 4.0 / float(Engine.physics_ticks_per_second) + 0.001
	for _index: int in 450:
		if not machine.is_batch_running():
			break
		var elapsed: float = batch_clock.effective_seconds - origin
		var expected: float = _expected_energy(elapsed)
		var actual: float = orange.emission_energy_multiplier
		var error: float = absf(actual - expected)
		waveform_max_error = maxf(waveform_max_error, error)
		sampled_frames += 1
		waveform_samples.append({"有效秒数": elapsed, "预期倍率": expected, "实际倍率": actual, "误差": error, "时间缩放": Engine.time_scale, "计时器剩余秒数": machine.processing_timer.time_left, "补间实例": tween.get_instance_id(), "物理帧": Engine.get_physics_frames()})
		check(error <= one_frame_energy_tolerance, "实际补间倍率符合每半秒单向线性插值，误差不超过一物理帧")
		check(machine.get("_indicator_tween") == tween and tween.is_valid(), "运行期间始终复用同一个有效补间")
		check(is_equal_approx(other_orange.emission_energy_multiplier, 2.0) and is_equal_approx(INDICATOR_ORANGE.emission_energy_multiplier, 2.0), "本机闪烁不改变第二台就绪倍率与原始资源倍率")
		if elapsed >= 0.1 and not tested_refresh:
			tested_refresh = true
			for _refresh: int in 10:
				machine.call("_queue_indicator_refresh")
		if elapsed >= 0.2 and not tested_pause:
			tested_pause = true
			var remaining: float = machine.processing_timer.time_left
			var frozen_energy: float = orange.emission_energy_multiplier
			var frozen_clock: float = batch_clock.effective_seconds
			paused = true
			await frames(20)
			check(is_equal_approx(remaining, machine.processing_timer.time_left) and is_equal_approx(frozen_energy, orange.emission_energy_multiplier) and is_equal_approx(frozen_clock, batch_clock.effective_seconds), "暂停同时冻结真实批次计时、有效时间与指示灯波形")
			paused = false
		if elapsed >= 0.3 and not tested_scale:
			tested_scale = true
			Engine.time_scale = 0.5
		if elapsed >= 0.5 and not captured_low:
			captured_low = true
			low_luminance = await _capture_indicator("04-running-low-orange.png")
		if elapsed >= 0.8 and Engine.time_scale != 1.0:
			Engine.time_scale = 1.0
		if elapsed >= 1.05 and not tested_exit:
			tested_exit = true
			await _exit()
			_check_indicator(INDICATOR_RUNNING, "退出聚焦不会停止运行闪烁")
		await frames(1)
	check(sampled_frames >= 100 and tested_pause and tested_scale and tested_refresh and tested_exit, "波形覆盖完整两秒批次、重复刷新、暂停、时间缩放与退出聚焦")
	_check_indicator(INDICATOR_COMPLETED, "有效游戏时间两秒后真实提交切为绿色并清除运行补间")
	check(absf(batch_clock.effective_seconds - origin - 2.0) <= 1.0 / float(Engine.physics_ticks_per_second) + 0.00001, "时间缩放与暂停后仍由两秒有效游戏计时完成")
	_check_indicator(INDICATOR_READY, "本机完成后第二台仍橙色常亮", other_machine)
	if graphical:
		check(high_luminance > low_luminance + 0.01, "真实渲染高倍率画面比低倍率画面更亮")
	await _capture_indicator("05-completed-green.png")
	await _focus_device(machine as AutolysisBlendMachine)
	check(inventory.try_take_from_blend_tank_place(player, machine.tank_place), "真实库存事务成功取回完成罐")
	await frames(2)
	_check_indicator(INDICATOR_DEFAULT, "取走完成罐后恢复红色")
	await _capture_indicator("06-taken-red.png")


func _test_completed_credential_and_two_batches() -> void:
	var definition: AutolysisItemDefinition = TANK_DEFINITION.duplicate() as AutolysisItemDefinition
	await _prepare_indicator_ready(definition)
	var first_tween: Tween
	var last_batch_id: int = machine.get_processing_batch_id()
	for batch_index: int in 2:
		check(machine.try_start_processing(player), "连续批次公开入口实际成功启动")
		var current_tween: Tween = machine.get("_indicator_tween") as Tween
		check(current_tween != null and current_tween != first_tween and machine.get_processing_batch_id() == last_batch_id + 1, "每批建立一个新补间和新批次编号")
		first_tween = current_tween
		last_batch_id = machine.get_processing_batch_id()
		await frames(125)
		_check_indicator(INDICATOR_COMPLETED, "连续批次真实完成后绿色且无循环")
		check(not current_tween.is_valid(), "成功离开运行态终止本批补间")
		var tank: AutolysisLiquidTank = machine.tank_place.get_stored_item()
		var instance: AutolysisItemInstance = tank.item_instance
		check(machine.get("_completed_tank_instance") == instance, "绿色凭据保存真实成功批次罐的逐件实例身份")
		var slot: AutolysisBlendSlot = machine.slots[2]
		check(slot.try_toggle(player), "完成后允许打开空槽门")
		await frames(15)
		_check_indicator(INDICATOR_COMPLETED, "完成罐仍在时空槽门打开持续绿色")
		check(slot.try_toggle(player), "完成后允许关闭空槽门")
		await frames(15)
		await _focus_device(machine as AutolysisBlendMachine)
		_check_indicator(INDICATOR_COMPLETED, "完成后退出并重新聚焦仍保持绿色")
		if batch_index == 0:
			var broken_visual: PackedScene = PackedScene.new()
			var visual_root: Node3D = Node3D.new()
			check(broken_visual.pack(visual_root) == OK, "打包缺少满罐内容网格的真实候选故障夹具")
			visual_root.free()
			definition.visual_scene = broken_visual
			check(inventory.can_take_from_blend_tank_place(player, machine.tank_place) and not inventory.try_take_from_blend_tank_place(player, machine.tank_place), "完成罐取回候选准备失败，业务拒绝提交")
			await frames(2)
			_check_indicator(INDICATOR_COMPLETED, "取回候选失败后原完成罐归属未变且保持绿色")
			check(machine.get("_completed_tank_instance") == instance and machine.tank_place.owns_item(tank), "失败回滚保留原完成实例凭据及罐位归属")
			definition.visual_scene = TANK_DEFINITION.visual_scene
		check(inventory.try_take_from_blend_tank_place(player, machine.tank_place), "正式库存事务取回当前完成罐")
		await frames(2)
		_check_indicator(INDICATOR_DEFAULT, "每批成功取走完成罐后恢复红色")
		check(machine.get("_completed_tank_instance") == null and _machine_signal_count(instance.changed, machine) == 0 and machine.get("_observed_tank") == null and machine.get("_observed_tank_instance") == null, "取罐后清除完成凭据并断开旧罐实例和退出监听")
		if batch_index == 0:
			check(inventory.cycle_focus(1), "连续第二批切到空道具格")
			await _place_indicator_tank(machine as AutolysisBlendMachine, definition)
			await _place_indicator_raw(machine as AutolysisBlendMachine)
			_check_indicator(INDICATOR_READY, "连续第二批再次满足完整条件后橙色常亮")


func _machine_signal_count(observed: Signal, device: Node) -> int:
	var count: int = 0
	for connection: Dictionary in observed.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_object() == device:
			count += 1
	return count


func _test_external_fill_and_credential_invalidation() -> void:
	await _prepare_indicator_ready()
	var tank: AutolysisLiquidTank = machine.tank_place.get_stored_item()
	var ids: Array[String] = ["caffeine"]
	check(tank.apply_contents(AutolysisLiquidContents.create_result(ids)), "外部接口直接向就绪设备空罐装填合法内容")
	await frames(2)
	_check_indicator(INDICATOR_DEFAULT, "外部直接装填不能伪造本机完成态")
	check(machine.get("_completed_tank_instance") == null, "外部装填不会建立成功批次实例凭据")
	await _prepare_indicator_ready()
	check(machine.try_start_processing(player), "完成凭据内容失效场景启动真实批次")
	await frames(125)
	tank = machine.tank_place.get_stored_item()
	_check_indicator(INDICATOR_COMPLETED, "内容失效前真实成功批次绿色")
	check(tank.item_instance.set_liquid_contents(null), "实际逐件资源接口清除已完成罐内容")
	await frames(2)
	_check_indicator(INDICATOR_DEFAULT, "完成罐不再为合法满罐时清除绿色")
	check(machine.get("_completed_tank_instance") == null, "内容失效清除完成凭据")


func _test_tank_exit() -> void:
	for mode: String in ["释放", "移出场景"]:
		await _prepare_indicator_ready()
		check(machine.try_start_processing(player), "当前罐退出场景验收启动真实批次")
		await frames(125)
		var tank: AutolysisLiquidTank = machine.tank_place.get_stored_item()
		var instance: AutolysisItemInstance = tank.item_instance
		if mode == "释放":
			tank.queue_free()
		else:
			tank.get_parent().remove_child(tank)
		await frames(2)
		_check_indicator(INDICATOR_DEFAULT, "完成罐" + mode + "后不能保留绿色或补间")
		check(machine.get("_completed_tank_instance") == null and _machine_signal_count(instance.changed, machine) == 0, "完成罐" + mode + "后清除凭据并解除实例监听")
		if mode == "移出场景":
			tank.free()


func _test_machine_exit() -> void:
	for mode: String in ["释放", "移出场景"]:
		await _prepare_indicator_ready()
		check(machine.try_start_processing(player), "设备退出场景验收启动真实批次")
		var tween: Tween = machine.get("_indicator_tween") as Tween
		await frames(5)
		var target: Node3D = machine
		if mode == "释放":
			target.queue_free()
		else:
			target.get_parent().remove_child(target)
		await frames(2)
		check(not tween.is_valid(), "运行设备" + mode + "后终止补间，没有残留循环")
		if mode == "移出场景":
			check(target.get("_indicator_tween") == null, "设备移出场景后清除补间引用")
			target.free()


func _test_indicator_loss() -> void:
	await _prepare_indicator_ready()
	check(machine.try_start_processing(player), "指示灯失效验收启动真实批次")
	var tween: Tween = machine.get("_indicator_tween") as Tween
	var lamp: MeshInstance3D = machine.get("status_indicator") as MeshInstance3D
	lamp.queue_free()
	await frames(2)
	check(not tween.is_valid() and machine.get("_indicator_tween") == null, "指示灯节点释放后终止补间并清空引用")
	check(machine.is_batch_running() and machine.get_processing_fault().is_empty(), "显示依赖失效不改变已有业务运行或制造业务故障")
	await frames(125)
	check(not machine.is_batch_running() and not machine.tank_place.get_stored_item().is_empty(), "指示灯失效后原有业务仍完成完整批次")


func _capture_indicator(filename: String) -> float:
	if not graphical:
		return -1.0
	var lamp: MeshInstance3D = machine.get("status_indicator") as MeshInstance3D
	var previously_paused: bool = paused
	paused = true
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	viewport.world_3d = world.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.22
	camera.near = 0.01
	camera.far = 5.0
	viewport.add_child(camera)
	camera.global_position = lamp.global_position + Vector3(0, 0, 0.5)
	camera.look_at(lamp.global_position)
	camera.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var actual_image: Image = viewport.get_texture().get_image()
	var output: String = evidence_directory.path_join(filename)
	var saved: Error = actual_image.save_png(output)
	check(saved == OK, "保存正式场景指示灯真实近景渲染画面")
	var luminance: float = 0.0
	for x: int in range(280, 360):
		for y: int in range(172, 188):
			var pixel: Color = actual_image.get_pixel(x, y)
			luminance += pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
	luminance /= 80.0 * 16.0
	if saved == OK:
		screenshots.append(output)
	var orange: StandardMaterial3D = machine.get("_indicator_orange_material") as StandardMaterial3D
	render_samples.append({"画面": output, "状态": machine.get("_indicator_state"), "橙色倍率": orange.emission_energy_multiplier, "灯中心平均亮度": luminance, "采样区域": "横向280至359、纵向172至187", "说明": "真实引擎渲染；截图期间暂停有效游戏时间保持采样状态"})
	viewport.queue_free()
	await process_frame
	paused = previously_paused
	return luminance


func _save_indicator_report() -> void:
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("blend-indicator-report.json"), FileAccess.WRITE)
	if file == null:
		check(false, "指示灯专项证据报告目录可写入")
		return
	file.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "断言": records, "状态采样": indicator_records, "波形逐帧采样": waveform_samples, "最大波形误差": waveform_max_error, "单物理帧倍率容差": 4.0 / float(Engine.physics_ticks_per_second) + 0.001, "渲染采样": render_samples, "截图": screenshots, "图形后端": graphical, "输入范围": "正式公开业务入口与真实库存事务；不声称人工鼠标验收"}, "\t"))
	file.close()
