extends "res://main-autolysis/systems/item-system/tests/packing_machine_behavior_test.gd"
## 封装提示灯专项验收：真实许可、库存事务、有效游戏时间与真实近景渲染。

const LAMP_DEFAULT: int = 0
const LAMP_READY: int = 1
const LAMP_RUNNING: int = 2
const LAMP_COMPLETED: int = 3
const LAMP_RED: Material = preload("res://main-autolysis/assets/materials/base_color/mat_base_red_2.tres")
const LAMP_GREY: Material = preload("res://main-autolysis/assets/materials/base_color/mat_base_grey_4.tres")
const LAMP_BLUE_ZERO: StandardMaterial3D = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_blue_0.tres")
const LAMP_BLUE_ONE: StandardMaterial3D = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_blue_1.tres")

class PackingBatchClock extends Node:
	var effective_seconds: float = 0.0

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_physics_priority = 1000

	func _physics_process(delta: float) -> void:
		if not get_tree().paused:
			effective_seconds += delta

class RefusingSilentClearTank extends AutolysisItemInstance:
	var rejected_silent_clears: int = 0
	var restored_silent_writes: int = 0
	var capsule_for_probe: AutolysisItemInstance
	var saw_capsule_written_before_rejection: bool = false

	func set_liquid_contents(contents: AutolysisLiquidContents, notify: bool = true) -> bool:
		if contents == null and not notify:
			rejected_silent_clears += 1
			saw_capsule_written_before_rejection = is_instance_valid(capsule_for_probe) and not capsule_for_probe.is_empty_pneumatic_capsule()
			return false
		if contents != null and not notify:
			restored_silent_writes += 1
		return super.set_liquid_contents(contents, notify)

class SourceReplacingPresenter extends AutolysisHeldItemPresenter:
	var source_capsule: AutolysisPneumaticCapsule
	var replacement_instance: AutolysisItemInstance
	var prepared_candidate: Node3D
	var candidate_was_generated: bool = false

	func prepare_instance(instance: AutolysisItemInstance) -> Node3D:
		var visual: Node3D = super.prepare_instance(instance)
		prepared_candidate = visual
		if visual != null and is_instance_valid(source_capsule):
			candidate_was_generated = true
			source_capsule.item_instance = replacement_instance
		return visual

var lamp_records: Array[Dictionary] = []
var waveform_samples: Array[Dictionary] = []
var render_samples: Array[Dictionary] = []
var boundary_records: Array[Dictionary] = []
var waveform_max_error: float = 0.0
var sampled_frames: int = 0
var saved_time_scale: float = 1.0
var indicator_clock: PackingBatchClock
var rollback_notifications: int = 0
var failed_take_inventory_changes: int = 0


func run_checks() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	saved_time_scale = Engine.time_scale
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/封装机提示灯实施证据/20261004/indicator")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	indicator_clock = PackingBatchClock.new()
	root.add_child(indicator_clock)
	await _test_lamp_permissions()
	await _test_lamp_waveform_and_isolation()
	await _test_lamp_consecutive_batches()
	await _test_lamp_commit_rollback()
	await _test_lamp_take_source_recheck()
	await _test_lamp_machine_exit()
	await _test_lamp_dependency_ownership()
	await _test_lamp_deletion()
	_save_lamp_report()
	_release_controls()
	paused = false
	Engine.time_scale = saved_time_scale
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	if is_instance_valid(world):
		world.queue_free()
	indicator_clock.queue_free()
	await frames(2)
	print("封装提示灯专项验收断言数：", assertion_count, "；失败总数：", failures, "；波形最大误差：", waveform_max_error)
	quit(1 if failures > 0 else 0)


func _fresh_lamp_case() -> void:
	Engine.time_scale = 1.0
	await _new_scene()
	await _enter()
	_assert_lamps(LAMP_DEFAULT, "初始按钮红色、双完成灯灰色且没有补间")


func _focus_lamp_device(device: AutolysisPackingMachine) -> void:
	await _exit()
	check(focus.try_enter(device.focus_target), "正式公开入口进入目标封装机聚焦")
	await frames(20)
	check(focus.is_focused_on(device.focus_target), "目标封装机聚焦稳定完成")


func _place_lamp_tank(device: AutolysisPackingMachine) -> void:
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(TANK_DEFINITION)
	check(instance.set_liquid_contents(_source_contents()), "准备含合法源内容的独立满罐实例")
	check(inventory.try_receive_instance(instance), "正式库存入口接收独立满罐实例")
	check(inventory.try_place_in_packing_tank_place(player, device.tank_place), "正式库存事务将满罐放入目标封装机")
	await frames(2)


func _place_lamp_capsule(device: AutolysisPackingMachine) -> void:
	if not device.door.is_open():
		check(device.door.try_toggle(player), "正式门入口打开目标封装机舱门")
		await frames(18)
	check(device.door.is_open(), "胶囊放入前真实舱门完全打开")
	check(inventory.try_receive_item(CAPSULE_DEFINITION), "正式库存入口接收独立空胶囊")
	check(inventory.try_place_in_packing_capsule_place(player, device.capsule_place), "正式库存事务将空胶囊放入目标封装机")
	await frames(2)


func _select_lamp_type(device: AutolysisPackingMachine, index: int = 0) -> void:
	check(device.try_select_type(player, index), "正式类型选择入口接受合法类型")
	await frames(18)
	check(device.get_selected_type() == index and not device.are_switches_animating(), "真实类型动画结束并保留合法选择")


func _prepare_lamp_ready() -> void:
	await _fresh_lamp_case()
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
	await _place_lamp_tank(device)
	await _place_lamp_capsule(device)
	await _select_lamp_type(device)
	_assert_lamps(LAMP_READY, "完整合法输入、有效类型、玩家聚焦和交互许可使按钮蓝色常亮")


func _assert_lamps(expected: int, description: String, target: AutolysisPackingMachine = null) -> void:
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine if target == null else target
	var button: MeshInstance3D = device.get("start_indicator") as MeshInstance3D
	var blue: StandardMaterial3D = device.get("_indicator_blue_material") as StandardMaterial3D
	var tween: Tween = device.get("_indicator_tween") as Tween
	var actual_state: int = int(device.get("_indicator_state"))
	var expected_material: Material = LAMP_RED
	if expected in [LAMP_READY, LAMP_COMPLETED]:
		expected_material = LAMP_BLUE_ONE
	elif expected == LAMP_RUNNING:
		expected_material = blue
	var material_valid: bool = is_instance_valid(button) and button.material_override == expected_material
	var tween_valid: bool = tween != null and tween.is_valid()
	var fixed_energy_valid: bool = is_equal_approx(LAMP_BLUE_ONE.emission_energy_multiplier, 1.0) and is_equal_approx(LAMP_BLUE_ZERO.emission_energy_multiplier, 2.0)
	var completion_valid: bool = true
	var lamps: Array[MeshInstance3D] = device.completion_indicators
	completion_valid = lamps.size() == 2
	for lamp: MeshInstance3D in lamps:
		completion_valid = completion_valid and is_instance_valid(lamp) and lamp.material_override == (LAMP_BLUE_ZERO if expected == LAMP_COMPLETED else LAMP_GREY)
	check(actual_state == expected and material_valid and tween_valid == (expected == LAMP_RUNNING) and completion_valid and fixed_energy_valid, description)
	lamp_records.append({"说明": description, "设备": str(device.get_path()), "状态": actual_state, "预期状态": expected, "物理帧": Engine.get_physics_frames(), "按钮材质符合": material_valid, "双完成灯符合": completion_valid, "独立运行倍率": blue.emission_energy_multiplier if blue != null else -1.0, "补间有效": tween_valid, "补间实例": tween.get_instance_id() if tween != null else 0})


func _test_lamp_permissions() -> void:
	await _fresh_lamp_case()
	await _capture_lamps("01-初始红色.png")
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
	await _place_lamp_tank(device)
	_assert_lamps(LAMP_DEFAULT, "仅装入合法满罐不能显示就绪")
	await _place_lamp_capsule(device)
	_assert_lamps(LAMP_DEFAULT, "满罐与空胶囊齐全但尚未选类型仍为红色")
	check(not device.start_button.start_interaction.try_interact(player), "实际交互组件拒绝缺少类型的按钮点击")
	_assert_lamps(LAMP_DEFAULT, "被拒绝的真实请求没有新补间")
	check(device.try_select_type(player, 0), "正式选择入口启动类型开关动画")
	await frames(1)
	_assert_lamps(LAMP_DEFAULT, "合法类型开关尚在运动时按钮红色")
	await frames(18)
	_assert_lamps(LAMP_READY, "完全开门且类型动画完成后就绪蓝色常亮")
	await _capture_lamps("02-就绪蓝色.png")
	check(device.door.try_toggle(player), "正式门入口接受从就绪状态关门")
	await frames(1)
	_assert_lamps(LAMP_DEFAULT, "舱门关门运动期间按钮红色")
	await frames(18)
	_assert_lamps(LAMP_READY, "完全关门后按既有许可重新显示就绪")
	check(device.door.try_toggle(player), "正式门入口接受从就绪状态开门")
	await frames(1)
	_assert_lamps(LAMP_DEFAULT, "舱门开门运动期间按钮红色")
	await frames(18)
	_assert_lamps(LAMP_READY, "完全开门后按既有许可重新显示就绪")
	check(device.tank_place.try_begin_transfer(player), "正式罐位入口取得取放事务锁")
	await frames(2)
	_assert_lamps(LAMP_DEFAULT, "取放事务锁未释放时按钮红色")
	device.tank_place.end_transfer()
	await frames(2)
	_assert_lamps(LAMP_READY, "取放事务结束后每帧许可刷新恢复就绪")
	device.start_button.start_interaction.is_enabled = false
	await frames(2)
	_assert_lamps(LAMP_DEFAULT, "真实交互入口禁用使普通阶段按钮红色")
	device.start_button.start_interaction.is_enabled = true
	await frames(2)
	_assert_lamps(LAMP_READY, "真实交互入口重新启用恢复就绪")
	device.start_button.start_interaction.interaction_mode = AutolysisInteractionComponent.InteractionMode.FOCUS
	await frames(2)
	_assert_lamps(LAMP_DEFAULT, "实际交互模式不匹配时按钮红色")
	check(focus.state == INACTIVE, "交互模式失效使真实聚焦控制器取消无效设备会话")
	device.start_button.start_interaction.interaction_mode = AutolysisInteractionComponent.InteractionMode.DIRECT
	await frames(2)
	_assert_lamps(LAMP_DEFAULT, "实际交互模式恢复但尚未重新聚焦时按钮继续红色")
	await _focus_lamp_device(device)
	_assert_lamps(LAMP_READY, "实际交互模式恢复并重新稳定聚焦后按钮就绪")
	_action(&"menu", true)
	_action(&"menu", false)
	await frames(2)
	check(player.is_movement_paused, "真实菜单输入切换正式玩家菜单暂停标记")
	_assert_lamps(LAMP_DEFAULT, "菜单暂停移除普通阶段玩家许可并显示红色")
	_action(&"menu", true)
	_action(&"menu", false)
	await frames(2)
	check(not player.is_movement_paused, "再次真实菜单输入解除正式玩家菜单暂停标记")
	_assert_lamps(LAMP_READY, "菜单恢复后完整玩家许可使按钮显示就绪")
	# 沿用正式直接交互验收的界面标记夹具，检查真实玩家的独立界面许可分支。
	player.is_showing_ui = true
	player.update_mouse_mode()
	await frames(2)
	check(not player.is_focus_business_allowed(), "正式玩家界面显示标记启用时真实业务许可关闭")
	_assert_lamps(LAMP_DEFAULT, "界面显示标记启用后普通阶段按钮红色")
	player.is_showing_ui = false
	player.update_mouse_mode()
	await frames(2)
	_assert_lamps(LAMP_READY, "界面显示标记关闭后完整玩家许可恢复就绪")
	await _exit()
	_assert_lamps(LAMP_DEFAULT, "退出普通阶段聚焦后完整交互许可失效而显示红色")
	check(focus.try_enter(device.focus_target), "正式聚焦入口接受重新进入本机")
	await frames(20)
	_assert_lamps(LAMP_READY, "重新稳定聚焦后显示就绪蓝色常亮")
	check(device.try_select_type(player, 0), "正式选择入口取消当前类型")
	await frames(18)
	_assert_lamps(LAMP_DEFAULT, "取消当前类型后恢复红色且双完成灯始终保持灰色")
	await _fresh_lamp_case()
	device = machine as AutolysisPackingMachine
	await _place_lamp_capsule(device)
	_assert_lamps(LAMP_DEFAULT, "仅放入空胶囊不能显示就绪")


func _expected_lamp_energy(elapsed: float) -> float:
	var phase: float = fposmod(elapsed, 1.0)
	return 2.0 - phase * 4.0 if phase <= 0.5 else (phase - 0.5) * 4.0


func _test_lamp_waveform_and_isolation() -> void:
	await _prepare_lamp_ready()
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
	var second: AutolysisPackingMachine = other_machine as AutolysisPackingMachine
	await _focus_lamp_device(second)
	await _place_lamp_tank(second)
	await _place_lamp_capsule(second)
	await _select_lamp_type(second)
	_assert_lamps(LAMP_READY, "第二台封装机独立满足许可并就绪", second)
	check(second.start_button.start_interaction.try_interact(player), "第二台正式按钮交互实际接受第一轮启动")
	await frames(125)
	_assert_lamps(LAMP_COMPLETED, "第二台先完成以验证双完成灯不会受另一台闪烁影响", second)
	await _focus_lamp_device(device)
	var blue: StandardMaterial3D = device.get("_indicator_blue_material") as StandardMaterial3D
	var other_blue: StandardMaterial3D = second.get("_indicator_blue_material") as StandardMaterial3D
	check(blue != null and other_blue != null and blue != other_blue and blue != LAMP_BLUE_ZERO and other_blue != LAMP_BLUE_ZERO, "两台按钮运行材质均为不同的独立副本且原始资源未被直接使用")
	check(blue.albedo_texture == LAMP_BLUE_ZERO.albedo_texture and other_blue.albedo_texture == LAMP_BLUE_ZERO.albedo_texture and LAMP_BLUE_ZERO.albedo_texture != null, "独立运行副本保持共享原始纹理引用")
	var origin: float = indicator_clock.effective_seconds
	check(device.start_button.start_interaction.try_interact(player), "正式按钮交互同步接受真实启动")
	_assert_lamps(LAMP_RUNNING, "真实点击被接受后立即闪烁，不等待按钮按压完成")
	check(is_equal_approx(blue.emission_energy_multiplier, 2.0), "真实启动瞬间从倍率二开始向零线性插值")
	var tween: Tween = device.get("_indicator_tween") as Tween
	var high_luminance: float = await _capture_lamps("03-运行明亮.png")
	var low_luminance: float = -1.0
	var tested_pause: bool = false
	var tested_scale: bool = false
	var tested_refresh: bool = false
	var tested_exit: bool = false
	var captured_low: bool = false
	var one_frame_tolerance: float = 4.0 / float(Engine.physics_ticks_per_second) + 0.001
	for _index: int in 450:
		if not device.is_batch_running():
			break
		var elapsed: float = indicator_clock.effective_seconds - origin
		var expected: float = _expected_lamp_energy(elapsed)
		var actual: float = blue.emission_energy_multiplier
		var error: float = absf(actual - expected)
		waveform_max_error = maxf(waveform_max_error, error)
		sampled_frames += 1
		waveform_samples.append({"有效秒数": elapsed, "预期倍率": expected, "实际倍率": actual, "误差": error, "时间缩放": Engine.time_scale, "计时器剩余秒数": device.processing_timer.time_left, "补间实例": tween.get_instance_id(), "物理帧": Engine.get_physics_frames()})
		check(error <= one_frame_tolerance and actual >= -0.001 and actual <= 2.001, "实际运行倍率在零至二之间且每半秒线性单向插值，误差不超过一物理帧")
		check(device.get("_indicator_tween") == tween and tween.is_valid(), "本轮运行期间只有同一个有效补间")
		check(is_equal_approx(other_blue.emission_energy_multiplier, 2.0) and is_equal_approx(LAMP_BLUE_ZERO.emission_energy_multiplier, 2.0) and is_equal_approx(LAMP_BLUE_ONE.emission_energy_multiplier, 1.0), "本机闪烁不修改另一台运行副本或两份共享蓝色材质倍率")
		for lamp: MeshInstance3D in second.completion_indicators:
			check(lamp.material_override == LAMP_BLUE_ZERO and is_equal_approx((lamp.material_override as StandardMaterial3D).emission_energy_multiplier, 2.0), "另一台完成灯始终使用倍率二的共享零号蓝色常亮材质")
		if elapsed >= 0.1 and not tested_refresh:
			tested_refresh = true
			var before_refresh: float = blue.emission_energy_multiplier
			for _refresh: int in 10:
				device.call("_refresh_indicator")
			check(device.get("_indicator_tween") == tween and is_equal_approx(before_refresh, blue.emission_energy_multiplier), "运行期间重复同步刷新保持补间实例与相位不变")
		if elapsed >= 0.2 and not tested_pause:
			tested_pause = true
			var remaining: float = device.processing_timer.time_left
			var frozen_energy: float = blue.emission_energy_multiplier
			var frozen_clock: float = indicator_clock.effective_seconds
			paused = true
			await frames(20)
			check(is_equal_approx(remaining, device.processing_timer.time_left) and is_equal_approx(frozen_energy, blue.emission_energy_multiplier) and is_equal_approx(frozen_clock, indicator_clock.effective_seconds), "暂停同时冻结真实批次计时、有效时间和按钮闪烁倍率")
			paused = false
		if elapsed >= 0.3 and not tested_scale:
			tested_scale = true
			Engine.time_scale = 0.5
		if elapsed >= 0.5 and not captured_low:
			captured_low = true
			low_luminance = await _capture_lamps("04-运行暗淡.png")
		if elapsed >= 0.8 and Engine.time_scale != 1.0:
			Engine.time_scale = 1.0
		if elapsed >= 1.05 and not tested_exit:
			tested_exit = true
			await _exit()
			_assert_lamps(LAMP_RUNNING, "运行中退出聚焦不会终止封装和按钮闪烁")
		await frames(1)
	check(sampled_frames >= 80 and tested_pause and tested_scale and tested_refresh and tested_exit and captured_low, "波形覆盖两秒批次、暂停恢复、时间缩放、重复刷新、明暗采样与退出聚焦")
	_assert_lamps(LAMP_COMPLETED, "两秒有效游戏时间后真实提交完成三灯常亮并清除运行补间")
	check(not tween.is_valid(), "成功完成后本轮运行补间已终止")
	check(absf(indicator_clock.effective_seconds - origin - 2.0) <= 1.0 / float(Engine.physics_ticks_per_second) + 0.00001, "时间缩放和暂停后仍由两秒有效游戏时间决定完成")
	_assert_lamps(LAMP_COMPLETED, "另一台完成待取显示在本机整个批次期间保持", second)
	if graphical:
		check(high_luminance > low_luminance + 0.01, "真实渲染的按钮高倍率画面比低倍率画面更亮")
	await _capture_lamps("05-完成三灯常亮.png")
	await _focus_lamp_device(device)
	check(inventory.try_take_from_packing_capsule_place(player, device.capsule_place), "正式库存事务成功取走本轮完成胶囊")
	await frames(2)
	_assert_lamps(LAMP_DEFAULT, "本轮胶囊成功取走同步恢复红色按钮与灰色双完成灯")
	await _capture_lamps("06-取走重置.png")


func _test_lamp_consecutive_batches() -> void:
	await _prepare_lamp_ready()
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
	var previous_tween: Tween
	var previous_id: int = device.get_processing_batch_id()
	for batch_index: int in 2:
		check(device.start_button.start_interaction.try_interact(player), "连续批次正式开始按钮入口实际接受请求")
		_assert_lamps(LAMP_RUNNING, "连续批次启动后按钮闪烁且双完成灯仍为灰色")
		var current_tween: Tween = device.get("_indicator_tween") as Tween
		check(current_tween != null and current_tween != previous_tween and device.get_processing_batch_id() == previous_id + 1, "连续批次建立新编号和唯一新补间")
		previous_tween = current_tween
		previous_id = device.get_processing_batch_id()
		await frames(125)
		_assert_lamps(LAMP_COMPLETED, "连续批次成功完成后停闪并显示三灯常亮")
		check(current_tween != null and not current_tween.is_valid(), "连续批次完成后旧循环不残留")
		check(device.door.try_toggle(player), "完成待取阶段允许正式门入口关闭舱门")
		await frames(18)
		_assert_lamps(LAMP_COMPLETED, "完成待取关门不会改变三个灯")
		check(device.door.try_toggle(player), "完成待取阶段允许正式门入口重新开门")
		await frames(18)
		_assert_lamps(LAMP_COMPLETED, "完成待取开门不会改变三个灯")
		await _focus_lamp_device(device)
		_assert_lamps(LAMP_COMPLETED, "完成后退出再进入聚焦仍保持三个灯")
		check(inventory.try_take_from_packing_tank_place(player, device.tank_place), "完成后正式库存事务先取空罐")
		await frames(2)
		_assert_lamps(LAMP_COMPLETED, "先取空罐不会提前重置完成显示")
		check(inventory.cycle_focus(1), "成功取空罐后切换到空道具格")
		check(inventory.try_take_from_packing_capsule_place(player, device.capsule_place), "正式库存事务再成功取走本轮完成胶囊")
		await frames(2)
		_assert_lamps(LAMP_DEFAULT, "连续批次每次成功取走本轮胶囊均重置三个灯")
		check(device.get_completed_capsule_instance() == null and device.get_selected_type() == -1, "成功取走清除本机完成记录及类型选择")
		if batch_index == 0:
			await frames(18)
			check(not device.are_switches_animating(), "胶囊成功取走后的真实类型复位动画结束再准备下一轮")
			check(inventory.cycle_focus(1), "第二轮准备使用另一个空道具格")
			await _place_lamp_tank(device)
			await _place_lamp_capsule(device)
			await _select_lamp_type(device, 1)
			_assert_lamps(LAMP_READY, "连续第二轮再次满足正式完整许可而就绪")


func _test_lamp_machine_exit() -> void:
	for mode: String in ["释放", "移出场景"]:
		await _prepare_lamp_ready()
		var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
		check(device.start_button.start_interaction.try_interact(player), "整机退出验收先通过真实入口启动批次")
		var tween: Tween = device.get("_indicator_tween") as Tween
		await frames(10)
		if mode == "释放":
			device.queue_free()
		else:
			device.get_parent().remove_child(device)
		await frames(2)
		check(not tween.is_valid(), "运行整机" + mode + "后终止补间并无残留循环")
		if mode == "移出场景":
			check(device.get("_indicator_tween") == null, "整机移出场景后清空补间引用")
			device.free()


func _lamp_source_matches_snapshot(source: AutolysisItemInstance, snapshot: AutolysisLiquidContents) -> bool:
	var actual: AutolysisLiquidContents = source.liquid_contents
	return actual != null and actual.is_valid_contents() and actual.get_raw_material_ids() == snapshot.get_raw_material_ids() and actual.get_phase_rgb() == snapshot.get_phase_rgb() and actual.get_wave_coordinates() == snapshot.get_wave_coordinates()


func _observe_lamp_commit_rollback(_batch_id: int, reason: String, device: AutolysisPackingMachine, source: RefusingSilentClearTank, capsule: AutolysisItemInstance, snapshot: AutolysisLiquidContents, tween: Tween) -> void:
	rollback_notifications += 1
	check(reason == "已预检两件物品拒绝静默共同提交，保留输入", "同步失败通知证明正式共同提交拒绝分支实际执行")
	check(source.rejected_silent_clears == 1 and source.restored_silent_writes == 1 and source.saw_capsule_written_before_rejection, "同步失败通知前胶囊曾实际写入，静默清罐被拒绝且源内容写回成功")
	check(capsule.is_empty_pneumatic_capsule() and _lamp_source_matches_snapshot(source, snapshot) and device.get_completed_capsule_instance() == null, "同步失败通知已经观察到完整回滚、原满罐源保留和空完成记录")
	_assert_lamps(LAMP_DEFAULT, "共同提交回滚的同步失败通知观察到红色按钮、灰色双完成灯且没有补间", device)
	check(not tween.is_valid() and not device.is_batch_running() and device.is_interaction_locked(), "同步失败通知已停止本轮补间及运行，并保留原有故障锁")


func _test_lamp_commit_rollback() -> void:
	await _fresh_lamp_case()
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
	var source: RefusingSilentClearTank = RefusingSilentClearTank.new()
	source.definition = TANK_DEFINITION
	check(source.set_liquid_contents(_source_contents(1)) and source.is_valid_instance(), "故障注入满罐仅拒绝静默清空，允许正常装填且逐件实例合法")
	var snapshot: AutolysisLiquidContents = source.liquid_contents.copy_contents()
	check(inventory.try_receive_instance(source), "正式库存入口接收故障注入的合法满罐实例")
	check(inventory.try_place_in_packing_tank_place(player, device.tank_place), "正式库存事务保持故障注入满罐来源身份")
	await frames(2)
	await _place_lamp_capsule(device)
	await _select_lamp_type(device, 1)
	var tank_node: AutolysisLiquidTank = device.tank_place.get_stored_item()
	var capsule_node: AutolysisPneumaticCapsule = device.capsule_place.get_stored_item()
	var capsule: AutolysisItemInstance = capsule_node.item_instance
	source.capsule_for_probe = capsule
	_assert_lamps(LAMP_READY, "共同提交回滚注入前真实预检许可与就绪灯态成立")
	rollback_notifications = 0
	check(device.start_button.start_interaction.try_interact(player), "共同提交回滚故障注入通过正式按钮入口实际启动")
	var tween: Tween = device.get("_indicator_tween") as Tween
	_assert_lamps(LAMP_RUNNING, "共同提交回滚注入运行阶段仍按正常规则闪烁")
	device.processing_failed.connect(_observe_lamp_commit_rollback.bind(device, source, capsule, snapshot, tween))
	await frames(125)
	check(rollback_notifications == 1 and source.rejected_silent_clears == 1 and source.restored_silent_writes == 1, "真实批次恰好一次进入共同提交拒绝分支、恢复源内容并通知故障")
	check(source.saw_capsule_written_before_rejection and capsule.is_empty_pneumatic_capsule() and _lamp_source_matches_snapshot(source, snapshot), "正式共同提交先写胶囊后拒绝清罐，最终两件内容成对恢复")
	check(device.tank_place.owns_item(tank_node) and device.capsule_place.owns_item(capsule_node) and tank_node.item_instance == source and capsule_node.item_instance == capsule, "共同提交回滚保留正式两槽占用与两件原来源身份")
	check(AutolysisLiquidTankVisual.get_contents_mesh(tank_node).material_override == AutolysisLiquidTankVisual.FILLED_MATERIAL and AutolysisPneumaticCapsuleVisual.get_contents_mesh(capsule_node).material_override == AutolysisPneumaticCapsuleVisual.EMPTY_MATERIAL, "共同提交回滚保留满罐与空胶囊的实际原外观")
	check(device.get_completed_capsule_instance() == null and not device.get_processing_fault().is_empty() and not device.can_start_processing(), "共同提交回滚没有完成记录且保留既有故障锁")
	_assert_lamps(LAMP_DEFAULT, "共同提交回滚结束后按钮红色、双完成灯灰色且无残留补间")
	boundary_records.append({"边界": "预检通过后的静默共同提交拒绝与回滚", "拒绝清空次数": source.rejected_silent_clears, "源写回次数": source.restored_silent_writes, "胶囊曾写入": source.saw_capsule_written_before_rejection, "失败通知数": rollback_notifications, "胶囊恢复为空": capsule.is_empty_pneumatic_capsule(), "源内容完整保留": _lamp_source_matches_snapshot(source, snapshot), "完成记录为空": device.get_completed_capsule_instance() == null})


func _observe_failed_lamp_take_inventory_change() -> void:
	failed_take_inventory_changes += 1


func _test_lamp_take_source_recheck() -> void:
	await _prepare_lamp_ready()
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
	check(device.start_button.start_interaction.try_interact(player), "取回来源复核验收先正式完成一个真实封装批次")
	await frames(125)
	_assert_lamps(LAMP_COMPLETED, "取回来源复核注入前本轮胶囊完成且三灯常亮")
	var capsule: AutolysisPneumaticCapsule = device.capsule_place.get_stored_item()
	var original_instance: AutolysisItemInstance = capsule.item_instance
	var original_presenter: AutolysisHeldItemPresenter = inventory.get("_presenter") as AutolysisHeldItemPresenter
	var input_allowed: Callable = inventory.get("_input_allowed")
	var presenter: SourceReplacingPresenter = SourceReplacingPresenter.new()
	presenter.source_capsule = capsule
	presenter.replacement_instance = AutolysisItemInstance.create(CAPSULE_DEFINITION)
	check(presenter.replacement_instance.set_packing_contents(original_instance.packing_contents), "故障注入替换来源也是同定义的合法完成胶囊实例")
	root.add_child(presenter)
	inventory.configure(presenter, input_allowed)
	failed_take_inventory_changes = 0
	inventory.inventory_changed.connect(_observe_failed_lamp_take_inventory_change)
	check(inventory.can_take_from_packing_capsule_place(player, device.capsule_place), "候选准备前真实完成胶囊满足正式取回许可")
	var accepted: bool = inventory.try_take_from_packing_capsule_place(player, device.capsule_place)
	var candidate_generated: bool = presenter.candidate_was_generated
	var candidate_released: bool = not is_instance_valid(presenter.prepared_candidate)
	check(candidate_generated and capsule.item_instance == presenter.replacement_instance, "正式显示器父类已生成真实合法候选之后同步改变来源实例身份")
	check(not accepted and candidate_released, "正式取回来源身份复核拒绝请求并释放已经生成的合法候选")
	check(device.capsule_place.owns_item(capsule) and device.capsule_place.get_stored_item() == capsule and inventory.get_focused_instance() == null and not device.capsule_place.is_transfer_busy(), "来源复核失败保留原胶囊槽占用、库存空格并结束取放事务")
	check(device.get_completed_capsule_instance() == original_instance and failed_take_inventory_changes == 0, "来源复核失败保留本机原完成记录且没有库存变化通知")
	_assert_lamps(LAMP_COMPLETED, "合法候选生成后的来源复核失败保持三个灯完成常亮且无运行补间")
	capsule.item_instance = original_instance
	inventory.configure(original_presenter, input_allowed)
	inventory.inventory_changed.disconnect(_observe_failed_lamp_take_inventory_change)
	presenter.queue_free()
	await frames(2)
	_assert_lamps(LAMP_COMPLETED, "来源实例与正式显示器恢复后仍保持本轮完成显示")
	boundary_records.append({"边界": "完成胶囊取回合法候选生成后的来源身份复核", "真实合法候选已生成": candidate_generated, "取回请求被拒绝": not accepted, "候选已释放": candidate_released, "原槽占用保留": device.capsule_place.owns_item(capsule), "完成记录保留": device.get_completed_capsule_instance() == original_instance, "库存变化通知数": failed_take_inventory_changes})
	check(inventory.try_take_from_packing_capsule_place(player, device.capsule_place), "恢复原来源与正式显示器后真实库存事务可成功取走本轮胶囊")
	await frames(2)
	_assert_lamps(LAMP_DEFAULT, "来源复核故障恢复后的成功取走才触发三灯重置")


func _test_lamp_dependency_ownership() -> void:
	await _prepare_lamp_ready()
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
	var second: AutolysisPackingMachine = other_machine as AutolysisPackingMachine
	var owned_button: AutolysisPackingStartButton = device.start_button
	var owned_indicator: MeshInstance3D = device.start_indicator
	device.start_button = second.start_button
	check(not device.call("_indicator_dependencies_are_valid"), "显示依赖校验拒绝属于另一台机器的开始按钮")
	device.start_indicator = second.start_indicator
	check(not device.call("_indicator_dependencies_are_valid"), "开始按钮和按钮网格同时属于另一台机器时仍由本机父级校验拒绝")
	device.start_button = owned_button
	device.start_indicator = owned_indicator
	var owned_lamps: Array[MeshInstance3D] = device.completion_indicators.duplicate()
	device.completion_indicators = [second.completion_indicators[0], owned_lamps[1]]
	check(not device.call("_indicator_dependencies_are_valid"), "显示依赖校验拒绝混入另一台机器的完成灯网格")
	device.completion_indicators = owned_lamps
	_assert_lamps(LAMP_READY, "只读显示依赖校验没有改变合法机器或另一台材质")
	check(device.start_button.start_interaction.try_interact(player), "运行中显示引用失效验收通过真实入口启动批次")
	var tween: Tween = device.get("_indicator_tween") as Tween
	await frames(10)
	var other_material: Material = second.start_indicator.material_override
	device.start_indicator = second.start_indicator
	device.call("_refresh_indicator")
	check(not tween.is_valid() and device.get("_indicator_tween") == null and not device.get("_indicator_enabled"), "运行按钮网格误绑定另一台机器时停显并清理补间")
	check(second.start_indicator.material_override == other_material, "非法按钮网格归属不会污染另一台机器的材质")
	check(device.is_batch_running() and device.get_processing_fault().is_empty(), "显示引用归属失效不改变原业务运行或制造故障")
	await frames(125)
	check(not device.is_batch_running() and device.get_completed_capsule_instance() != null, "显示引用归属失效后正式业务仍完成封装批次")


func _test_lamp_deletion() -> void:
	await _prepare_lamp_ready()
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
	check(device.start_button.start_interaction.try_interact(player), "按钮灯删除验收先通过真实入口启动批次")
	var tween: Tween = device.get("_indicator_tween") as Tween
	await frames(10)
	var lamp: MeshInstance3D = device.get("start_indicator") as MeshInstance3D
	lamp.queue_free()
	await frames(2)
	check(not tween.is_valid() and device.get("_indicator_tween") == null, "按钮灯网格释放后终止运行补间并清空引用")
	check(device.is_batch_running() and device.get_processing_fault().is_empty(), "按钮显示依赖失效不改变原有业务运行和故障规则")
	await frames(125)
	check(not device.is_batch_running() and device.get_completed_capsule_instance() != null and device.capsule_place.get_stored_item().item_instance.packing_contents != null, "按钮灯释放后业务仍成功共同提交本轮封装")


func _capture_lamps(filename: String) -> float:
	if not graphical:
		return -1.0
	var device: AutolysisPackingMachine = machine as AutolysisPackingMachine
	var lamp: MeshInstance3D = device.get("start_indicator") as MeshInstance3D
	var completion: MeshInstance3D = device.completion_indicators[0]
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
	camera.size = 0.24
	camera.near = 0.01
	camera.far = 5.0
	viewport.add_child(camera)
	var target: Vector3 = (lamp.global_position + completion.global_position) * 0.5
	camera.global_position = target + Vector3(0, 0, 0.5)
	camera.look_at(target)
	camera.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var actual_image: Image = viewport.get_texture().get_image()
	var output: String = evidence_directory.path_join(filename)
	var saved: Error = actual_image.save_png(output)
	check(saved == OK, "保存正式封装机按钮及双完成灯真实近景渲染画面")
	var center: Vector2i = Vector2i(camera.unproject_position(lamp.global_position))
	var luminance: float = 0.0
	for x: int in range(center.x - 8, center.x + 8):
		for y: int in range(center.y - 8, center.y + 8):
			var pixel: Color = actual_image.get_pixel(x, y)
			luminance += pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
	luminance /= 16.0 * 16.0
	if saved == OK:
		screenshots.append(output)
	var blue: StandardMaterial3D = device.get("_indicator_blue_material") as StandardMaterial3D
	render_samples.append({"画面": output, "状态": device.get("_indicator_state"), "独立运行倍率": blue.emission_energy_multiplier, "按钮中心平均亮度": luminance, "采样中心像素": str(center), "采样区域": "中心前后八像素，共十六乘十六像素", "说明": "真实引擎渲染；截图期间暂停有效游戏时间保持采样状态"})
	viewport.queue_free()
	await process_frame
	paused = previously_paused
	return luminance


func _save_lamp_report() -> void:
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("packing-indicator-report.json"), FileAccess.WRITE)
	if file == null:
		check(false, "专项证据报告目录可写入")
		return
	file.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "断言": records, "状态采样": lamp_records, "波形逐帧采样": waveform_samples, "最大波形误差": waveform_max_error, "单物理帧倍率容差": 4.0 / float(Engine.physics_ticks_per_second) + 0.001, "渲染采样": render_samples, "事务失败边界": boundary_records, "截图": screenshots, "图形后端": graphical, "输入范围": "正式交互许可入口、真实库存事务和真实聚焦控制；不声称人工鼠标验收"}, "\t"))
	file.close()
