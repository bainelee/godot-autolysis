extends "res://main-autolysis/systems/item-system/tests/packing_machine_behavior_test.gd"
## 可选表现失效与类型协调取消使用真实业务入口验证来源及一次提交。

var missing_press_at_initialization: bool = false

class ButtonEvents extends Node:
	var calls: int = 0
	func record() -> void:
		calls += 1

class ReleasingEvent extends Node:
	var target: Node
	var calls: int = 0
	func release_control() -> void:
		calls += 1
		if is_instance_valid(target):
			target.queue_free()

class MotionCommandEvent extends Node:
	var target: AutolysisPackingMotion
	var rebind: bool = false
	var suspend: bool = false
	var release_dependency: bool = false
	var calls: int = 0
	var accepted: bool = false
	func command() -> void:
		calls += 1
		if release_dependency:
			target.collision_shape.queue_free()
		if suspend:
			accepted = target.pause_motion()
		elif rebind:
			accepted = target.rebind_animation_player(target.get("_runtime_player") as AnimationPlayer)
		else:
			target.cancel_motion("立即方法轨道取消")
			accepted = true

class ButtonRebindEvent extends Node:
	var target: AutolysisPackingStartButton
	var calls: int = 0
	var accepted: bool = false
	func command() -> void:
		calls += 1
		accepted = target.rebind_press_animation(target.get("_runtime_player") as AnimationPlayer)

class TakingEvent extends Node:
	var target: AutolysisPackingMachine
	var actor: Node3D
	var inventory: AutolysisInventoryController
	var calls: int = 0
	var accepted: bool = false
	func command() -> void:
		calls += 1
		var transferred: bool = inventory.try_take_from_packing_tank_place(actor, target.tank_place)
		accepted = accepted or transferred

var isolated_completed: int = 0
var isolated_started: int = 0
var isolation_records: Array[Dictionary] = []


func run_checks() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/容器开闭动画控制实施证据/20261004/packing-checks/isolation")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	await _test_optional_display_and_press()
	await _test_switch_coordinated_cancellation()
	await _test_button_duration_and_material_configuration()
	await _test_core_control_release(0.04)
	await _test_core_control_release(0.0)
	for event_time: float in [0.0, 0.04]:
		for rebind: bool in [false, true]:
			await _test_immediate_motion_command(event_time, rebind)
		await _test_immediate_button_rebind(event_time)
		await _test_immediate_motion_pause(event_time)
		await _test_immediate_dependency_cancel(event_time)
		await _test_immediate_item_take(event_time)
	await _test_immediate_motion_pause(-1.0)
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("显示隔离与类型中断报告.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "断言": records, "记录": isolation_records, "命令参数": OS.get_cmdline_args()}, "\t"))
	_release_controls()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	world.queue_free()
	await frames(2)
	print("封装显示隔离与类型中断断言数：", assertion_count, "；失败总数：", failures)
	quit(0 if failures == 0 else 1)


func _prepare_packing_scene() -> void:
	if not missing_press_at_initialization:
		return
	for node_name: String in ["PackingA", "PackingB"]:
		var device: AutolysisPackingMachine = world.get_node(node_name) as AutolysisPackingMachine
		var isolated: AnimationLibrary = device.animation_source.get_animation_library(&"").duplicate() as AnimationLibrary
		device.animation_source.remove_animation_library(&"")
		device.animation_source.add_animation_library(&"", isolated)
		isolated.remove_animation(device.start_button.animation_name)
		device.processing_timer.wait_time = 9.0


func _prepare_sources() -> Array[AutolysisItemInstance]:
	await _new_scene()
	await _enter()
	var source: AutolysisItemInstance = await _put_tank(_source_contents())
	var capsule: AutolysisItemInstance = await _put_capsule()
	return [source, capsule]


func _test_optional_display_and_press() -> void:
	missing_press_at_initialization = true
	var sources: Array[AutolysisItemInstance] = await _prepare_sources()
	missing_press_at_initialization = false
	check(machine.start_button.is_configured() and not machine.start_button.get_press_error().is_empty(), "缺少初始按压动画仍保留业务开始入口")
	var decoration: Node3D = Node3D.new()
	machine.add_child(decoration)
	for control: AutolysisPackingTypeSwitch in machine.type_switches:
		control.indicator.reparent(decoration)
	check(machine.try_select_type(player, 0), "类型灯重组层级后允许选择")
	await _wait_packing_motion()
	machine.type_switches[0].indicator.queue_free()
	machine.start_indicator.queue_free()
	machine.completion_indicators[0].queue_free()
	await frames(2)
	check(machine.is_configured() and focus.is_focused_on(machine.focus_target) and machine.can_start_processing(), "移除类型灯、开始灯和完成灯不退出聚焦或拒绝合法加工")
	isolated_started = 0
	isolated_completed = 0
	machine.processing_started.connect(_on_isolated_started)
	machine.processing_completed.connect(_on_isolated_completed)
	var before: int = Engine.get_physics_frames()
	check(machine.start_button.start_interaction.try_interact(player), "缺少全部相关表现时权威开始入口接受一次请求")
	check(not machine.start_button.start_interaction.try_interact(player), "接受批次后拒绝重复开始")
	await _wait_batch()
	check(isolated_started == 1 and isolated_completed == 1 and sources[0].is_empty_liquid_tank() and not sources[1].is_empty_pneumatic_capsule(), "显示失效仍只提交一次并保留两件来源身份")
	check(Engine.get_physics_frames() - before >= Engine.physics_ticks_per_second * 2, "加工仍从真实接受时计算两秒")
	isolation_records.append({"用例": "缺按压与灯删除", "开始次数": isolated_started, "完成次数": isolated_completed, "源罐为空": sources[0].is_empty_liquid_tank(), "胶囊已封装": not sources[1].is_empty_pneumatic_capsule(), "实际计时器等待值": machine.processing_timer.wait_time})


func _test_switch_coordinated_cancellation() -> void:
	var sources: Array[AutolysisItemInstance] = await _prepare_sources()
	for cancelled_index: int in [0, 1]:
		check(machine.try_select_type(player, 0), "选择取消用例接受初始类型")
		await _wait_packing_motion()
		check(machine.try_select_type(player, 1), "选择取消用例同时关闭旧开关并打开新开关")
		await frames(2)
		machine.type_switches[cancelled_index].cancel_motion("类型切换专项显式取消")
		await _wait_packing_motion()
		_assert_cancelled_selection(sources, "取消旧开关" if cancelled_index == 0 else "取消新开关")
	# 一个控制件先自然完成，另一个仍运动时统一清除整次选择。
	var slow: AutolysisPackingTypeSwitch = machine.type_switches[0]
	var runtime: AnimationPlayer = slow.get("_runtime_player") as AnimationPlayer
	runtime.speed_scale = 0.2
	check(machine.try_select_type(player, 0), "慢速开关可以使用有效正速度倍率")
	await _wait_packing_motion()
	check(machine.try_select_type(player, 1), "快慢开关类型切换已接受")
	var deadline: int = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 5
	while not machine.type_switches[1].is_open() and slow.is_animating() and Engine.get_physics_frames() < deadline:
		await frames(1)
	check(machine.type_switches[1].is_open() and slow.is_animating(), "新开关已完成而旧开关仍关闭中")
	slow.cancel_motion("类型切换部分完成取消")
	await _wait_packing_motion()
	_assert_cancelled_selection(sources, "一个已完成另一个取消")
	runtime.speed_scale = 1.0
	check(machine.try_select_type(player, 2), "重新选择用例接受目标类型")
	await frames(2)
	var interrupted: AutolysisPackingTypeSwitch = machine.type_switches[2]
	var released: AnimationPlayer = interrupted.get("_runtime_player") as AnimationPlayer
	released.queue_free()
	await frames(3)
	check(machine.get_selected_type() == -1 and not interrupted.is_animating() and not interrupted.is_selected(), "必要播放器释放立即清除整机选择和选中标记")
	var replacement: AnimationPlayer = machine.call("_create_player", interrupted.animation_name, "RecoveredTypeAnimation") as AnimationPlayer
	check(interrupted.rebind_animation_player(replacement), "类型依赖重新绑定成功")
	await _wait_packing_motion()
	_assert_cancelled_selection(sources, "依赖释放后恢复")
	check(machine.try_select_type(player, 2), "恢复依赖后再次选择")
	await _wait_packing_motion()
	check(machine.can_start_processing(), "恢复后选中状态与稳定动作一致可启动")


func _assert_cancelled_selection(sources: Array[AutolysisItemInstance], label: String) -> void:
	check(machine.get_selected_type() == -1 and not machine.can_start_processing(), label + "：整机选择已清除且不能启动")
	for control: AutolysisPackingTypeSwitch in machine.type_switches:
		check(not control.is_selected() and control.is_closed(), label + "：每个有依赖开关恢复关闭且未选中")
	check(sources[0].liquid_contents != null and sources[1].is_empty_pneumatic_capsule(), label + "：未消耗输入或创建产物")


func _test_button_duration_and_material_configuration() -> void:
	var sources: Array[AutolysisItemInstance] = await _prepare_sources()
	check(machine.try_select_type(player, 1), "可调显示用例选择类型")
	await _wait_packing_motion()
	var button: AutolysisPackingStartButton = machine.start_button
	var runtime: AnimationPlayer = button.get("_runtime_player") as AnimationPlayer
	var variant: Animation = runtime.get_animation(button.animation_name).duplicate() as Animation
	variant.length = 1.2
	var events: ButtonEvents = ButtonEvents.new()
	events.name = "ButtonEvents"
	machine.add_child(events)
	var method_track: int = variant.add_track(Animation.TYPE_METHOD)
	variant.track_set_path(method_track, NodePath("ButtonEvents"))
	variant.track_insert_key(method_track, 0.0, {"method": &"record", "args": []})
	var library: AnimationLibrary = runtime.get_animation_library(&"")
	library.remove_animation(button.animation_name)
	var local_animation_name: StringName = button.animation_name
	var protected_library: AnimationLibrary = AnimationLibrary.new()
	protected_library.add_animation(local_animation_name, variant)
	runtime.add_animation_library(&"_packing_button_restore", protected_library)
	button.animation_name = StringName("_packing_button_restore/" + String(local_animation_name))
	check(button.rebind_press_animation(runtime), "按压表现使用一点二秒有效变体重新绑定")
	check(runtime.has_animation_library(&"_packing_button_restore") and runtime.get_animation(button.animation_name) == variant, "按钮临时库默认名称与业务源库相同时保留原动画库及资源")
	await frames(2)
	check(events.calls == 0, "按钮属性专用重新绑定未执行零秒方法事件")
	runtime.play(button.animation_name)
	check(button.rebind_press_animation(runtime), "按钮外部未推进播放后立即重新绑定")
	await frames(2)
	check(events.calls == 0 and variant.track_is_enabled(method_track), "按钮恢复消费残留启动事件且原动画事件启用位未改")
	var ready_material: StandardMaterial3D = StandardMaterial3D.new()
	ready_material.albedo_color = Color(0.2, 0.7, 0.8)
	machine.indicator_ready_material = ready_material
	machine.indicator_half_cycle_seconds = 0.2
	machine.indicator_emission_minimum = 0.3
	machine.indicator_emission_maximum = 3.4
	machine.rebind_indicators()
	check(machine.start_indicator.material_override == ready_material, "有效材质替换被实际显示采用")
	check(machine.start_button.start_interaction.try_interact(player), "可调显示和长按压不阻断正式启动")
	var independent: StandardMaterial3D = machine.get("_indicator_blue_material") as StandardMaterial3D
	await frames(5)
	check(events.calls == 1, "真实启动按压只执行一次零秒方法事件")
	check(independent.emission_energy_multiplier >= 0.3 and independent.emission_energy_multiplier <= 3.4 and independent != machine.indicator_running_material, "合法闪烁周期及发光范围使用本机独立材质")
	runtime.stop(true)
	await frames(2)
	check(machine.is_batch_running() and machine.get_processing_fault().is_empty(), "按压外部停止不撤销已接受批次")
	check(not button.get_press_error().is_empty(), "按压中断记录原因并只停用相关表现")
	await _wait_batch()
	check(sources[0].is_empty_liquid_tank() and not sources[1].is_empty_pneumatic_capsule(), "按压停止后仍成对提交加工结果")


func _wait_batch() -> void:
	var deadline: int = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 5
	while machine.is_batch_running() and Engine.get_physics_frames() < deadline:
		await frames(1)
	check(not machine.is_batch_running() and machine.get_processing_fault().is_empty(), "目标批次在测试上限内自然完成且没有业务故障")


func _test_core_control_release(event_time: float) -> void:
	var sources: Array[AutolysisItemInstance] = await _prepare_sources()
	var control: AutolysisPackingTypeSwitch = machine.type_switches[0]
	var runtime: AnimationPlayer = control.get("_runtime_player") as AnimationPlayer
	var events: ReleasingEvent = ReleasingEvent.new()
	events.name = "ReleaseEvent"
	events.target = control
	machine.add_child(events)
	var releasing_animation: Animation = runtime.get_animation(control.animation_name).duplicate() as Animation
	var method_track: int = releasing_animation.add_track(Animation.TYPE_METHOD)
	releasing_animation.track_set_path(method_track, NodePath("ReleaseEvent"))
	releasing_animation.track_insert_key(method_track, event_time, {"method": &"release_control", "args": []})
	var library: AnimationLibrary = runtime.get_animation_library(&"")
	library.remove_animation(control.animation_name)
	library.add_animation(control.animation_name, releasing_animation)
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	check(control.rebind_animation_player(runtime), "控制件立即事件变体通过显式重新绑定建立关闭态")
	await _wait_packing_motion()
	check(machine.try_select_type(player, 0), "核心控制件释放用例接受选择")
	var deadline: int = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 5
	while is_instance_valid(control) and Engine.get_physics_frames() < deadline:
		await frames(1)
	await frames(2)
	check(events.calls == 1 and not is_instance_valid(control), "立即方法轨道实际释放正在推进的控制件一次")
	check(not machine.is_configured() and not focus.is_focused_on(machine.focus_target), "登记控制物理体释放按核心登记失效退出聚焦")
	check(sources[0].liquid_contents != null and sources[1].is_empty_pneumatic_capsule(), "核心控制件释放没有消耗来源或创建产物")


func _on_isolated_started(_batch_id: int) -> void:
	isolated_started += 1


func _test_immediate_motion_command(event_time: float, rebind: bool) -> void:
	var sources: Array[AutolysisItemInstance] = await _prepare_sources()
	var control: AutolysisPackingTypeSwitch = machine.type_switches[0]
	var runtime: AnimationPlayer = control.get("_runtime_player") as AnimationPlayer
	var event: MotionCommandEvent = MotionCommandEvent.new()
	event.name = "MotionCommandEvent"
	event.target = control
	event.rebind = rebind
	machine.add_child(event)
	var variant: Animation = runtime.get_animation(control.animation_name).duplicate() as Animation
	var track: int = variant.add_track(Animation.TYPE_METHOD)
	variant.track_set_path(track, NodePath("MotionCommandEvent"))
	variant.track_insert_key(track, event_time, {"method": &"command", "args": []})
	var library: AnimationLibrary = runtime.get_animation_library(&"")
	library.remove_animation(control.animation_name)
	library.add_animation(control.animation_name, variant)
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	check(control.rebind_animation_player(runtime), "立即方法取消或重绑变体从显式关闭态建立")
	await _wait_packing_motion()
	check(machine.try_select_type(player, 0), "立即方法取消或重绑用例接受真实类型选择")
	await _wait_packing_motion()
	check(event.calls == 1 and event.accepted and control.is_closed() and machine.get_selected_type() == -1, "立即方法定位或推进内取消及重绑只执行一次，返回后恢复关闭并协调清除选择")
	check(sources[0].liquid_contents != null and sources[1].is_empty_pneumatic_capsule(), "立即方法取消及重绑没有消耗两件来源")


func _test_immediate_button_rebind(event_time: float) -> void:
	var sources: Array[AutolysisItemInstance] = await _prepare_sources()
	check(machine.try_select_type(player, 0), "按钮立即重绑用例建立稳定类型选择")
	await _wait_packing_motion()
	var button: AutolysisPackingStartButton = machine.start_button
	var runtime: AnimationPlayer = button.get("_runtime_player") as AnimationPlayer
	var event: ButtonRebindEvent = ButtonRebindEvent.new()
	event.name = "ButtonRebindEvent"
	event.target = button
	machine.add_child(event)
	var variant: Animation = runtime.get_animation(button.animation_name).duplicate() as Animation
	var track: int = variant.add_track(Animation.TYPE_METHOD)
	variant.track_set_path(track, NodePath("ButtonRebindEvent"))
	variant.track_insert_key(track, event_time, {"method": &"command", "args": []})
	var library: AnimationLibrary = runtime.get_animation_library(&"")
	library.remove_animation(button.animation_name)
	library.add_animation(button.animation_name, variant)
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	check(button.rebind_press_animation(runtime), "按钮立即方法重绑变体初始化不执行事件")
	check(event.calls == 0 and button.start_interaction.try_interact(player), "按钮立即方法重绑用例通过权威入口启动真实批次")
	await _wait_batch()
	check(event.calls == 1 and event.accepted and sources[0].is_empty_liquid_tank() and not sources[1].is_empty_pneumatic_capsule(), "按钮定位或推进内部重绑返回后安全恢复表现且真实批次仍成对完成")


func _test_immediate_motion_pause(event_time: float) -> void:
	var sources: Array[AutolysisItemInstance] = await _prepare_sources()
	var control: AutolysisPackingTypeSwitch = machine.type_switches[0]
	var runtime: AnimationPlayer = control.get("_runtime_player") as AnimationPlayer
	var event: MotionCommandEvent = MotionCommandEvent.new()
	event.name = "MotionPauseEvent"
	event.target = control
	event.suspend = true
	machine.add_child(event)
	var variant: Animation = runtime.get_animation(control.animation_name).duplicate() as Animation
	var track: int = variant.add_track(Animation.TYPE_METHOD)
	variant.track_set_path(track, NodePath("MotionPauseEvent"))
	var actual_event_time: float = variant.length if event_time < 0.0 else event_time
	variant.track_insert_key(track, actual_event_time, {"method": &"command", "args": []})
	var library: AnimationLibrary = runtime.get_animation_library(&"")
	library.remove_animation(control.animation_name)
	library.add_animation(control.animation_name, variant)
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	check(control.rebind_animation_player(runtime), "立即方法暂停变体初始化不执行事件")
	await _wait_packing_motion()
	check(machine.try_select_type(player, 0), "立即方法暂停用例接受类型选择")
	var deadline: int = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 5
	while event.calls == 0 and Engine.get_physics_frames() < deadline:
		await frames(1)
	var paused_position: float = runtime.current_animation_position
	await frames(3)
	check(event.calls == 1 and event.accepted and control.is_animating() and is_equal_approx(paused_position, runtime.current_animation_position), "立即方法定位或推进内暂停返回后安全保留同一动作与进度")
	check(control.resume_motion(), "立即方法暂停后显式续播被接受")
	await _wait_packing_motion()
	check(control.is_open() and event.calls == 1 and machine.get_selected_type() == 0, "立即方法暂停续播只完成一次并保留一致类型选择")
	check(sources[0].liquid_contents != null and sources[1].is_empty_pneumatic_capsule(), "立即方法暂停及续播没有消耗两件来源")
	isolation_records.append({"用例": "立即方法暂停与续播", "事件时间": actual_event_time, "暂停进度": paused_position, "事件次数": event.calls, "最终打开": control.is_open(), "故障": control.get_configuration_error()})


func _test_immediate_dependency_cancel(event_time: float) -> void:
	var sources: Array[AutolysisItemInstance] = await _prepare_sources()
	var control: AutolysisPackingTypeSwitch = machine.type_switches[0]
	var runtime: AnimationPlayer = control.get("_runtime_player") as AnimationPlayer
	var replacement_collision: CollisionShape3D = control.collision_shape.duplicate() as CollisionShape3D
	var event: MotionCommandEvent = MotionCommandEvent.new()
	event.name = "MotionDependencyCancelEvent"
	event.target = control
	event.release_dependency = true
	machine.add_child(event)
	var variant: Animation = runtime.get_animation(control.animation_name).duplicate() as Animation
	var track: int = variant.add_track(Animation.TYPE_METHOD)
	variant.track_set_path(track, NodePath("MotionDependencyCancelEvent"))
	variant.track_insert_key(track, event_time, {"method": &"command", "args": []})
	var library: AnimationLibrary = runtime.get_animation_library(&"")
	library.remove_animation(control.animation_name)
	library.add_animation(control.animation_name, variant)
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	check(control.rebind_animation_player(runtime), "立即方法依赖失效取消变体初始化不执行事件")
	await _wait_packing_motion()
	check(machine.try_select_type(player, 0), "立即方法依赖失效取消用例接受类型选择")
	var deadline: int = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 5
	while event.calls == 0 and Engine.get_physics_frames() < deadline:
		await frames(1)
	await _wait_packing_motion()
	check(event.calls == 1 and event.accepted and not control.is_configured() and not runtime.is_playing() and machine.get_selected_type() == -1, "立即方法依赖释放后取消返回时安全停止旧动作并清除选择")
	control.add_child(replacement_collision)
	control.collision_shape = replacement_collision
	variant.track_set_enabled(track, false)
	check(control.rebind_animation_player(runtime), "立即依赖失效后修复碰撞并显式重绑")
	await _wait_packing_motion()
	check(control.is_closed() and machine.try_select_type(player, 0), "依赖修复后从稳定关闭态接受下一选择")
	await _wait_packing_motion()
	check(control.is_open() and event.calls == 1 and sources[0].liquid_contents != null and sources[1].is_empty_pneumatic_capsule(), "依赖修复后下一动作自然完成且来源保留")


func _test_immediate_item_take(event_time: float) -> void:
	var sources: Array[AutolysisItemInstance] = await _prepare_sources()
	var control: AutolysisPackingTypeSwitch = machine.type_switches[0]
	var runtime: AnimationPlayer = control.get("_runtime_player") as AnimationPlayer
	var event: TakingEvent = TakingEvent.new()
	event.name = "MotionTakingEvent"
	event.target = machine
	event.actor = player
	event.inventory = inventory
	machine.add_child(event)
	var variant: Animation = runtime.get_animation(control.animation_name).duplicate() as Animation
	var track: int = variant.add_track(Animation.TYPE_METHOD)
	variant.track_set_path(track, NodePath("MotionTakingEvent"))
	variant.track_insert_key(track, event_time, {"method": &"command", "args": []})
	var library: AnimationLibrary = runtime.get_animation_library(&"")
	library.remove_animation(control.animation_name)
	library.add_animation(control.animation_name, variant)
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	check(control.rebind_animation_player(runtime), "立即方法取物反播变体初始化不执行事件")
	await _wait_packing_motion()
	check(machine.try_select_type(player, 0), "立即方法取物反播用例接受类型选择")
	await _wait_packing_motion()
	check(event.accepted and event.calls >= 1 and machine.tank_place.get_stored_item() == null and inventory.get_focused_instance() == sources[0], "立即方法实际槽位取物保留原来源实例并移入库存")
	check(machine.get_selected_type() == -1 and not control.is_selected() and control.is_closed() and machine.door.is_open(), "立即方法取物之后返回再安全反播关闭，旧动作不恢复类型选择")
	variant.track_set_enabled(track, false)
	check(inventory.try_place_in_packing_tank_place(player, machine.tank_place), "立即取物反播后原来源可再次放回槽位")
	check(machine.try_select_type(player, 0), "立即取物反播后接受下一次正常选择")
	await _wait_packing_motion()
	check(control.is_open() and machine.can_start_processing() and sources[0].liquid_contents != null and sources[1].is_empty_pneumatic_capsule(), "立即取物反播后下一动作自然完成且两件来源未加工")


func _on_isolated_completed(_batch_id: int, _contents: AutolysisPackingContents) -> void:
	isolated_completed += 1
