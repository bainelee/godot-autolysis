extends "res://main-autolysis/systems/item-system/tests/blend_slot_transfer_test.gd"
## 四槽资产变体、自然完成、取消恢复、局部失效和可编辑拉杆的真实引擎验收。

const TANK: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/liquid_tank.tres")

class EventProbe extends Node:
	var events: int = 0
	var action: Callable

	func record_event() -> void:
		events += 1
		if action.is_valid():
			action.call()

class MotionClock extends Node:
	signal sampled(seconds: float, delta: float, frame: int)

	var seconds: float = 0.0

	func _init() -> void:
		process_physics_priority = 1000

	func _physics_process(delta: float) -> void:
		seconds += delta
		sampled.emit(seconds, delta, Engine.get_physics_frames())

var device: AutolysisBlendMachine
var actor: AutolysisPlayer
var event_probe: EventProbe
var samples: Array[Dictionary] = []
var completions: int = 0
var denials: int = 0
var clock_probe: MotionClock


func _run() -> void:
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/容器开闭动画控制实施证据/20261004/blend-checks")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	world = Node3D.new()
	root.add_child(world)
	await _test_asset_variants()
	await _test_motion_lifecycle()
	await _test_immediate_method_controls()
	await _test_immediate_disposal()
	await _test_restore_library_collision()
	await _test_terminal_method_suspend()
	await _test_handle_configuration()
	_save_evidence()
	var output: FileAccess = FileAccess.open(evidence_directory.path_join("blend-animation-samples.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(samples, "\t"))
	world.queue_free()
	await _frames(2)
	print("配药资产变体验收断言数：", assertion_count, "；失败总数：", failures)
	quit(1 if failures > 0 else 0)


func _make_fixture(variant: bool = false, edited_handle: bool = false, animation_library_name: StringName = &"edited_bank") -> void:
	await _clear_world()
	actor = _new_player()
	clock_probe = MotionClock.new()
	world.add_child(clock_probe)
	device = MACHINE_SCENE.instantiate() as AutolysisBlendMachine
	device.rotation = Vector3(0.0, 0.73, 0.0)
	event_probe = EventProbe.new()
	event_probe.name = "AnimationEventProbe"
	device.add_child(event_probe)
	if variant:
		var cloned_library: AnimationLibrary = device.animation_source.get_animation_library(&"").duplicate(true) as AnimationLibrary
		device.animation_source.remove_animation_library(&"")
		device.animation_source.add_animation_library(&"", cloned_library)
		device.animation_source.add_animation_library(animation_library_name, AnimationLibrary.new())
		var group: Node3D = Node3D.new()
		group.name = "EditedSlotGroup"
		device.add_child(group)
		device.animation_source.root_node = NodePath("../EditedSlotGroup")
		device.animation_source.speed_scale = 1.7
		for index: int in device.slots.size():
			var slot: AutolysisBlendSlot = device.slots[index]
			slot.owner = null
			slot.reparent(group, false)
			slot.owner = device
			slot.name = "EditedDoor_%d" % index
			var animation: Animation = device.animation_source.get_animation(slot.animation_name).duplicate() as Animation
			animation.length = [0.08, 0.65, 1.2, 0.31][index]
			animation.track_set_path(0, NodePath("%s:rotation" % slot.name))
			while animation.track_get_key_count(0) > 0:
				animation.track_remove_key(0, 0)
			animation.track_insert_key(0, 0.0, Vector3(0.0, 0.0, 0.23))
			animation.track_insert_key(0, animation.length, Vector3(0.0, 0.0, 0.23 if index == 3 else -0.92))
			if index == 3:
				animation.track_insert_key(0, animation.length * 0.5, Vector3(0.0, 0.0, -0.62))
			var track: int = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track, NodePath("%s:position" % slot.name))
			animation.track_insert_key(track, 0.0, slot.position)
			animation.track_insert_key(track, animation.length, slot.position + Vector3(0.0, 0.07, 0.05))
			track = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track, NodePath("%s:scale" % slot.name))
			animation.track_insert_key(track, 0.0, Vector3.ONE)
			animation.track_insert_key(track, animation.length, Vector3(1.08, 0.97, 1.02))
			track = animation.add_track(Animation.TYPE_METHOD)
			animation.track_set_path(track, NodePath("../AnimationEventProbe"))
			animation.track_insert_key(track, 0.0, {"method": &"record_event", "args": []})
			animation.track_insert_key(track, animation.length * 0.5, {"method": &"record_event", "args": []})
			device.animation_source.get_animation_library(&"").remove_animation(slot.animation_name)
			var action_name: StringName = StringName("door_%d" % index)
			device.animation_source.get_animation_library(animation_library_name).add_animation(action_name, animation)
			slot.animation_name = StringName("%s/%s" % [animation_library_name, action_name])
			var asset_directory: String = evidence_directory.path_join("variant-assets")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(asset_directory))
			_check(ResourceSaver.save(animation, asset_directory.path_join("slot-%d-animation.tres" % index)) == OK, "保存第%d槽实际变体动画资源" % index)
	if edited_handle:
		device.handle.top_reference.position = Vector3(0.043, 0.39, -0.058)
		device.handle.position = device.handle.top_reference.position
		device.handle.full_travel = 0.35
		device.handle.restricted_travel = 0.09
		device.handle.hold_seconds = 0.07
		device.handle.return_seconds = 0.41
	world.add_child(device)
	_check(actor.focus_controller.try_enter(device.focus_target), "资产编辑后正式聚焦登记接受设备")
	await _wait_condition(func() -> bool: return actor.focus_controller.is_focused_on(device.focus_target), "真实聚焦过渡完成")
	await _wait_all_slots()


func _wait_condition(condition: Callable, label: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _frames(1)
	_check(condition.call(), label)


func _wait_all_slots() -> void:
	await _wait_condition(func() -> bool:
		for slot: AutolysisBlendSlot in device.slots:
			if slot.is_animating():
				return false
		return true,
		"全部槽门完成当前动作或初态同步")


func _test_asset_variants() -> void:
	await _make_fixture(true)
	_check(event_probe.events == 0, "属性专用初始化不触发方法事件")
	for index: int in device.slots.size():
		var slot: AutolysisBlendSlot = device.slots[index]
		var before: Array[Transform3D] = []
		for other: AutolysisBlendSlot in device.slots:
			before.append(other.transform)
		_check(slot.is_closed() and slot.is_configured(), "第%d槽非零关闭姿态及多轨资产可用" % index)
		var observer: Node = Node.new()
		world.add_child(observer)
		slot.toggle_interaction.interaction_requested.connect(func(_actor: Node3D) -> void: samples.append({"观察通知": index}))
		slot.toggle_interaction.interaction_requested.connect(observer.queue_free.unbind(1), CONNECT_DEFERRED)
		_check(slot.toggle_interaction.try_interact(actor), "第%d槽多个观察者下只执行一次打开请求" % index)
		_check(not slot.try_toggle(actor), "第%d槽运动中拒绝重复输入" % index)
		await _wait_condition(slot.is_open, "第%d槽目标自然完成后进入打开态" % index)
		var open_result: Transform3D = slot.transform
		_check(not open_result.origin.is_equal_approx(before[index].origin) and not open_result.basis.is_equal_approx(before[index].basis), "第%d槽物理同步保留位移旋转缩放完整结果" % index)
		await _frames(8)
		_check(slot.transform.is_equal_approx(open_result), "第%d槽自然结束结果稳定保留" % index)
		for other_index: int in device.slots.size():
			if other_index != index:
				_check(device.slots[other_index].transform.is_equal_approx(before[other_index]), "第%d槽独立播放器不驱动第%d槽" % [index, other_index])
		if index > 0:
			_check(actor.inventory_controller.cycle_focus(1), "第%d槽事务选择新的空库存格" % index)
		_check(actor.inventory_controller.try_receive_item(CAFFEINE) and actor.inventory_controller.try_place_in_blend_slot(actor, slot), "第%d槽变化资产仍允许真实原药存入" % index)
		_check(actor.inventory_controller.try_take_from_blend_slot(actor, slot), "第%d槽变化资产仍允许真实原药取回" % index)
		_check(slot.try_toggle(actor), "第%d槽接受反向关闭" % index)
		await _wait_condition(slot.is_closed, "第%d槽反向目标自然完成" % index)
		var closed_error: float = maxf(slot.transform.origin.distance_to(before[index].origin), maxf(slot.transform.basis.x.distance_to(before[index].basis.x), maxf(slot.transform.basis.y.distance_to(before[index].basis.y), slot.transform.basis.z.distance_to(before[index].basis.z))))
		var closed_result: Transform3D = slot.transform
		await _frames(8)
		_check(slot.transform.is_equal_approx(closed_result) and not closed_result.origin.is_equal_approx(open_result.origin), "第%d槽反向自然完成后保留本次实际关闭结果" % index)
		samples.append({"槽索引": index, "动画时长": device.animation_source.get_animation(slot.animation_name).length, "初始化关闭完整变换": str(before[index]), "打开完整变换": str(open_result), "关闭完整变换": str(slot.transform), "关闭表现误差": closed_error, "方法事件累计": event_probe.events})
	_check(event_probe.events == 16, "四槽正反播放各触发零秒与中段事件且稳定阶段不重放")


func _test_motion_lifecycle() -> void:
	await _make_fixture(true)
	var slot: AutolysisBlendSlot = device.slots[2]
	var immediate_events: int = event_probe.events
	_check(slot.try_toggle(actor) and slot.cancel_motion("同帧取消"), "请求打开与显式取消在同帧执行")
	await _wait_condition(slot.is_closed, "同帧取消恢复关闭稳定态")
	_check(event_probe.events == immediate_events, "同帧取消不触发零秒方法事件")
	var immediate_runtime: AnimationPlayer = slot.get("_runtime_player") as AnimationPlayer
	_check(slot.try_toggle(actor) and slot.rebind_animation_player(immediate_runtime), "请求打开与显式重绑定在同帧执行")
	await _wait_condition(slot.is_closed, "同帧重绑定恢复关闭稳定态")
	_check(event_probe.events == immediate_events, "同帧重绑定不触发零秒方法事件")
	immediate_runtime.play(slot.animation_name, 0.0)
	_check(slot.rebind_animation_player(immediate_runtime), "外部尚未推进的播放可由明确重绑定恢复")
	await _wait_condition(slot.is_closed, "外部未推进播放重绑定建立关闭态")
	_check(event_probe.events == immediate_events, "外部未推进播放恢复不触发零秒方法事件")
	var source_animation: Animation = device.animation_source.get_animation(slot.animation_name)
	_check(source_animation.track_is_enabled(source_animation.get_track_count() - 1), "初始化与取消不修改原动画事件轨道的启用状态")
	_check(slot.rebind_animation_player(immediate_runtime), "待同步恢复窗口外部接管试验建立恢复")
	immediate_runtime.play(slot.animation_name, 0.0)
	await _frames(2)
	_check(not slot.is_configured() and not slot.is_open() and not slot.is_closed() and not slot.is_animating(), "恢复待同步期间外部同名播放不得建立稳定许可")
	_check(slot.rebind_animation_player(immediate_runtime), "外部接管后明确重绑定恢复")
	await _wait_condition(slot.is_closed, "外部接管后关闭态同步完成")
	_check(slot.rebind_animation_player(immediate_runtime), "待同步资源替换试验建立恢复")
	var replacement_resource: Animation = immediate_runtime.get_animation(slot.animation_name).duplicate() as Animation
	var action_name: StringName = StringName(String(slot.animation_name).get_slice("/", 1))
	immediate_runtime.get_animation_library(&"edited_bank").remove_animation(action_name)
	immediate_runtime.get_animation_library(&"edited_bank").add_animation(action_name, replacement_resource)
	await _frames(2)
	_check(not slot.is_configured() and not slot.is_animating() and not slot.is_closed(), "恢复待同步期间同名资源替换不得建立稳定许可")
	_check(slot.rebind_animation_player(immediate_runtime), "同名资源替换后明确重绑定")
	await _wait_condition(slot.is_closed, "同名资源替换后使用新配置建立关闭态")
	var foreign_animation: Animation = replacement_resource.duplicate() as Animation
	for track: int in foreign_animation.get_track_count():
		if foreign_animation.track_get_type(track) == Animation.TYPE_METHOD:
			foreign_animation.track_set_enabled(track, false)
	immediate_runtime.get_animation_library(&"edited_bank").add_animation(&"foreign_pose", foreign_animation)
	_check(slot.rebind_animation_player(immediate_runtime), "待同步指定动作替换试验建立恢复")
	immediate_runtime.assigned_animation = &"edited_bank/foreign_pose"
	immediate_runtime.seek(foreign_animation.length * 0.5, true, true)
	await _frames(2)
	_check(not slot.is_configured() and not slot.is_closed() and not slot.is_open() and not slot.is_animating(), "恢复待同步期间外部指定其他动作并定位不得授予旧完成许可")
	_check(slot.rebind_animation_player(immediate_runtime), "指定其他动作后明确重绑定恢复")
	await _wait_condition(slot.is_closed, "指定动作归属恢复后重新建立关闭态")
	_check(slot.rebind_animation_player(immediate_runtime), "待同步外部其他动作播放暂停试验建立恢复")
	immediate_runtime.play(&"edited_bank/foreign_pose", 0.0)
	immediate_runtime.pause()
	await _frames(2)
	_check(not slot.is_configured() and not slot.is_closed() and not slot.is_open() and not slot.is_animating(), "恢复待同步期间外部其他动作播放后暂停不得伪报稳定许可")
	_check(slot.rebind_animation_player(immediate_runtime), "外部其他动作播放暂停后可明确重绑定")
	await _wait_condition(slot.is_closed, "外部其他动作播放暂停后恢复关闭态")
	_check(slot.try_toggle(actor), "长槽动作开始用于暂停回归")
	await _frames(3)
	paused = true
	var frozen: Transform3D = slot.transform
	await _frames(6)
	_check(slot.is_animating() and slot.transform.is_equal_approx(frozen), "全局暂停冻结动作且不伪报完成")
	paused = false
	_check(slot.suspend_motion(), "显式挂起保留同一槽门动作")
	await _frames(1)
	frozen = slot.transform
	await _frames(6)
	_check(slot.is_animating() and slot.transform.is_equal_approx(frozen), "显式挂起不变成永久故障")
	_check(slot.resume_motion(), "显式恢复继续同一槽门动作")
	await _wait_condition(slot.is_open, "恢复后正常自然完成打开")
	_check(slot.try_toggle(actor), "已打开槽门开始关闭")
	await _frames(4)
	var events_before: int = event_probe.events
	_check(slot.cancel_motion(), "关闭中显式取消恢复此前完成过的打开态")
	await _wait_condition(slot.is_open, "取消后打开稳定态同步完成")
	_check(event_probe.events == events_before, "取消恢复仅定位属性不重放方法事件")
	_check(slot.try_toggle(actor), "取消恢复后接受下一次关闭")
	await _wait_condition(slot.is_closed, "下一次关闭自然完成")
	_check(slot.try_toggle(actor), "关闭稳定态开始打开用于取消")
	await _frames(3)
	_check(slot.cancel_motion(), "打开中取消回到已关闭")
	await _wait_condition(slot.is_closed, "打开取消后的关闭稳定态完成")
	_check(slot.try_toggle(actor), "外部停止试验开始打开")
	await _frames(2)
	var runtime: AnimationPlayer = slot.get("_runtime_player") as AnimationPlayer
	runtime.stop(true)
	await _frames(2)
	_check(not slot.is_animating() and not slot.get_motion_error().is_empty() and not slot.is_open(), "外部停止终结等待且不伪报打开成功")
	_check(device.is_configured() and actor.focus_controller.is_focused_on(device.focus_target) and device.slots[0].can_toggle(actor), "局部门中断保留设备聚焦与其他槽门入口")
	_check(slot.cancel_motion(), "明确恢复操作解除外部停止")
	await _wait_condition(slot.is_closed, "明确恢复建立关闭态")
	_check(slot.try_toggle(actor), "同名反向接管试验开始打开")
	await _frames(3)
	runtime.play_backwards(slot.animation_name, 0.0)
	await _frames(2)
	_check(not slot.is_animating() and not slot.is_open() and not slot.get_motion_error().is_empty(), "外部同名反向接管终结等待且不授予打开许可")
	_check(slot.cancel_motion(), "同名反向接管后明确恢复")
	await _wait_condition(slot.is_closed, "同名反向接管后回到关闭稳定态")
	_check(slot.try_toggle(actor), "目标释放前开始打开")
	await _frames(2)
	runtime.queue_free()
	await _frames(2)
	_check(not slot.is_animating() and not slot.is_configured(), "播放器释放终结当前动作")
	var replacement: AnimationPlayer = AnimationPlayer.new()
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(action_name, device.animation_source.get_animation(slot.animation_name))
	replacement.add_animation_library(&"edited_bank", library)
	device.add_child(replacement)
	replacement.root_node = replacement.get_path_to(device.get_node("EditedSlotGroup"))
	_check(slot.rebind_animation_player(replacement), "依赖重新绑定接受有效播放器")
	await _wait_condition(slot.is_closed, "依赖重绑定统一建立关闭稳定态")
	var foreign: AutolysisBlendMachine = MACHINE_SCENE.instantiate() as AutolysisBlendMachine
	world.add_child(foreign)
	var rightful_root: NodePath = replacement.root_node
	replacement.root_node = replacement.get_path_to(foreign)
	_check(not slot.rebind_animation_player(replacement) and "所属设备" in slot.get_motion_error(), "明确拒绝独立播放器跨设备根引用")
	replacement.root_node = rightful_root
	_check(slot.rebind_animation_player(replacement), "恢复本机动画根后可重绑定")
	await _wait_condition(slot.is_closed, "恢复本机动画根后重新建立关闭态")
	_check(slot.try_toggle(actor), "外部排队试验开始打开")
	await _frames(1)
	replacement.queue(slot.animation_name)
	await _frames(2)
	_check(not slot.is_animating() and "排队" in slot.get_motion_error(), "外部队列接管不伪报打开完成")
	replacement.clear_queue()
	_check(slot.rebind_animation_player(replacement), "清除外部队列后可重绑定")
	await _wait_condition(slot.is_closed, "队列取消后建立关闭态")
	replacement.animation_set_next(slot.animation_name, slot.animation_name)
	_check(not slot.can_toggle(actor) and "后续动作" in slot.get_configuration_error(), "外部自动后续动作不会绕过独立播放器归属")
	replacement.animation_set_next(slot.animation_name, &"")
	_check(slot.rebind_animation_player(replacement), "清除自动后续动作后可恢复")
	await _wait_condition(slot.is_closed, "后续动作恢复后关闭态完成")
	var animation: Animation = replacement.get_animation(slot.animation_name)
	animation.loop_mode = Animation.LOOP_LINEAR
	_check(not slot.can_toggle(actor) and "非循环" in slot.get_configuration_error(), "循环动画明确给出无法自然完成的理由")
	animation.loop_mode = Animation.LOOP_NONE
	_check(slot.rebind_animation_player(replacement), "循环配置恢复后允许显式重绑定")
	await _wait_condition(slot.is_closed, "循环配置恢复后关闭态完成")
	_check(slot.try_toggle(actor), "重绑定后下一次打开可启动")
	await _wait_condition(slot.is_open, "重绑定后打开必须自然完成")
	event_probe.queue_free()
	await _frames(2)
	_check(slot.is_configured() and actor.focus_controller.is_focused_on(device.focus_target), "可选方法轨道目标释放不反向否决门体与聚焦业务")
	_check(slot.try_toggle(actor), "可选轨道目标释放后必要门体仍可关闭")
	await _wait_condition(slot.is_closed, "可选轨道目标释放后门体目标仍自然完成")


func _test_handle_configuration() -> void:
	await _make_fixture(false, true)
	var handle: AutolysisBlendHandle = device.handle
	var top: Vector3 = handle.position
	handle.interaction_completed.connect(func(_actor: Node3D) -> void: completions += 1)
	handle.handle_pull_denied.connect(func(_actor: Node3D, _reason: StringName) -> void: denials += 1)
	for _query: int in 5:
		_check(handle.can_begin_drag(actor), "编辑配置下只读许可查询可用")
	_check(denials == 0 and top.is_equal_approx(Vector3(0.043, 0.39, -0.058)), "顶部参照使用场景位置且只读查询不发送禁止消息")
	_check(handle.try_begin_drag(actor), "缺少来源时接受一次受限拖动")
	handle.apply_vertical_motion(actor, 100000.0)
	_check(handle.is_restricted_drag() and is_equal_approx(handle.position.y, top.y - 0.09) and handle.position.x == top.x and handle.position.z == top.z and completions == 0 and denials == 1, "受限行程保持横深偏移，不加工且仅发送一次禁止消息")
	handle.release_drag(actor)
	await _wait_condition(func() -> bool: return handle.state == AutolysisBlendHandle.HandleState.IDLE, "受限松开按配置回弹归顶")
	_check(handle.position.is_equal_approx(top) and denials == 1, "受限归顶不追加禁止消息")
	var slot: AutolysisBlendSlot = device.slots[0]
	_check(slot.try_toggle(actor), "完整行程回归打开原药槽")
	await _wait_condition(slot.is_open, "完整行程准备槽门已打开")
	_check(actor.inventory_controller.try_receive_item(CAFFEINE) and actor.inventory_controller.try_place_in_blend_slot(actor, slot), "完整行程准备真实原药来源")
	_check(slot.try_toggle(actor), "完整行程回归关闭原药槽")
	await _wait_condition(slot.is_closed, "完整行程准备槽门已关闭")
	_check(actor.inventory_controller.try_receive_item(TANK) and actor.inventory_controller.try_place_in_blend_tank_place(actor, device.tank_place), "完整行程准备真实空罐来源")
	_check(handle.try_begin_drag(actor) and not handle.is_restricted_drag(), "来源齐备后按配置接受完整行程")
	handle.apply_vertical_motion(actor, 0.175 / handle.mouse_to_handle_ratio)
	var start_y: float = handle.position.y
	handle.cancel_drag(actor)
	var started: float = clock_probe.seconds
	await _wait_condition(func() -> bool: return handle.state == AutolysisBlendHandle.HandleState.IDLE, "提前取消按剩余距离回弹")
	var elapsed: float = clock_probe.seconds - started
	_check(absf(elapsed - 0.205) < 0.08 and completions == 0 and handle.position.is_equal_approx(top), "半程取消用完整回弹时长一半且不触发最低业务")
	samples.append({"顶部位置": str(top), "提前取消位置": start_y, "半程回弹实测秒数": elapsed, "配置完整行程": handle.full_travel, "配置完整回弹秒数": handle.return_seconds})
	_check(handle.try_begin_drag(actor), "编辑配置允许下一次拖动")
	handle.apply_vertical_motion(actor, 100000.0)
	_check(completions == 1 and is_equal_approx(handle.position.y, top.y - 0.35), "编辑完整行程触底严格发送一次业务完成")
	handle.apply_vertical_motion(actor, 100000.0)
	await _measure_configured_handle_cycle(handle, top)
	_check(completions == 1 and handle.position.is_equal_approx(top), "完整周期归位保持偏移且不会重复完成")
	_check(device.is_batch_running() and device.is_interaction_locked() and not handle.try_begin_drag(actor), "完整回弹先于真实两秒加工结束，批次锁仍拒绝下一拖动")
	await _wait_condition(func() -> bool: return not device.is_batch_running(), "完整配置周期等待真实批次正式结束")
	var filled_tank: AutolysisLiquidTank = device.tank_place.get_stored_item()
	_check(device.get_processing_fault().is_empty() and filled_tank != null and not filled_tank.is_empty() and slot.get_stored_item() == null, "配置周期不改变真实加工提交与来源消费")
	_check(actor.inventory_controller.try_take_from_blend_tank_place(actor, device.tank_place), "完整配置周期通过正式入口取走加工结果")
	_check(actor.focus_controller.request_exit(), "完整配置周期归位与加工结束后允许退出聚焦")
	await _wait_condition(func() -> bool: return not actor.focus_controller.has_control(), "完整配置周期退出聚焦过渡完成")
	_check(not handle.can_begin_drag(actor) and completions == 1 and handle.position.is_equal_approx(top), "退出后拉杆保持顶部偏移且旧会话不能继续拖动")
	_check(actor.focus_controller.try_enter(device.focus_target), "完整配置周期退出后正式重入聚焦")
	await _wait_condition(func() -> bool: return actor.focus_controller.is_focused_on(device.focus_target), "完整配置周期重入聚焦过渡完成")
	_check(actor.inventory_controller.cycle_focus(1) and actor.inventory_controller.try_receive_item(CAFFEINE), "完整配置周期保留结果并在新空格准备下一次原药")
	_check(slot.try_toggle(actor), "完整配置周期下一轮打开空原药槽")
	await _wait_condition(slot.is_open, "完整配置周期下一轮槽门自然打开")
	_check(actor.inventory_controller.try_place_in_blend_slot(actor, slot), "完整配置周期下一轮通过正式入口存入新原药")
	_check(slot.try_toggle(actor), "完整配置周期下一轮关闭原药槽")
	await _wait_condition(slot.is_closed, "完整配置周期下一轮槽门自然关闭")
	_check(actor.inventory_controller.try_receive_item(TANK) and actor.inventory_controller.try_place_in_blend_tank_place(actor, device.tank_place), "完整配置周期下一轮通过正式入口放入新空罐")
	_check(device.can_start_processing() and handle.try_begin_drag(actor) and not handle.is_restricted_drag(), "完整配置周期重入后下一次完整拖动有效")
	handle.apply_vertical_motion(actor, 0.05 / handle.mouse_to_handle_ratio)
	_check(is_equal_approx(handle.position.y, top.y - 0.05) and handle.position.x == top.x and handle.position.z == top.z and completions == 1, "下一次拖动真实移动并保持横深偏移，不提前完成")
	handle.cancel_drag(actor)
	await _wait_condition(func() -> bool: return handle.state == AutolysisBlendHandle.HandleState.IDLE, "下一次拖动取消后按配置回弹归顶")
	_check(actor.focus_controller.request_exit(), "下一次拖动归位后仍允许正式退出聚焦")
	await _wait_condition(func() -> bool: return not actor.focus_controller.has_control(), "下一次拖动后的退出聚焦完成")
	_check(completions == 1 and not device.is_batch_running() and handle.position.is_equal_approx(top), "下一次取消与退出不重复完成或启动加工")


## 在拉杆物理处理之后采集公开位置；时长误差只取实际物理采样间隔。
func _measure_configured_handle_cycle(handle: AutolysisBlendHandle, top: Vector3) -> void:
	var started: float = clock_probe.seconds
	var bottom: Vector3 = handle.position
	var start_frame: int = Engine.get_physics_frames()
	var trajectory: Array[Dictionary] = [{"经过物理秒": 0.0, "物理间隔秒": 0.0, "物理帧": start_frame, "横": bottom.x, "高": bottom.y, "深": bottom.z, "完成累计": completions}]
	var result: Dictionary = {"已归顶": false}
	var sampler: Callable = func(seconds: float, delta: float, frame: int) -> void:
		if result["已归顶"]:
			return
		var current: Vector3 = handle.position
		trajectory.append({"经过物理秒": seconds - started, "物理间隔秒": delta, "物理帧": frame, "横": current.x, "高": current.y, "深": current.z, "完成累计": completions})
		result["已归顶"] = current.y == top.y
	clock_probe.sampled.connect(sampler)
	await _wait_condition(func() -> bool: return handle.state == AutolysisBlendHandle.HandleState.IDLE, "编辑保持与回弹时长后完整周期归位")
	clock_probe.sampled.disconnect(sampler)
	var expected_speed: float = handle.full_travel / handle.return_seconds
	var maximum_delta: float = 0.0
	var maximum_position_error: float = 0.0
	var maximum_speed_error: float = 0.0
	var maximum_offset_error: float = 0.0
	var first_move: Dictionary = {}
	var returned: Dictionary = {}
	var last_bottom_time: float = 0.0
	var holding_samples: int = 0
	var speed_samples: int = 0
	var completion_unique: bool = true
	var consecutive_frames: bool = true
	var monotonic: bool = true
	for index: int in trajectory.size():
		var point: Dictionary = trajectory[index]
		var elapsed: float = point["经过物理秒"]
		var height: float = point["高"]
		maximum_delta = maxf(maximum_delta, point["物理间隔秒"])
		maximum_offset_error = maxf(maximum_offset_error, maxf(absf(point["横"] - top.x), absf(point["深"] - top.z)))
		completion_unique = completion_unique and point["完成累计"] == 1
		var expected_height: float = bottom.y + handle.full_travel * clampf((elapsed - handle.hold_seconds) / handle.return_seconds, 0.0, 1.0)
		maximum_position_error = maxf(maximum_position_error, absf(height - expected_height))
		if height == bottom.y:
			last_bottom_time = elapsed
			holding_samples += 1
		elif first_move.is_empty():
			first_move = point
		if height == top.y and returned.is_empty():
			returned = point
		if index == 0:
			continue
		var previous: Dictionary = trajectory[index - 1]
		consecutive_frames = consecutive_frames and point["物理帧"] == previous["物理帧"] + 1
		monotonic = monotonic and height >= previous["高"] and height >= bottom.y and height <= top.y
		if previous["高"] > bottom.y and height < top.y:
			var observed_speed: float = (height - previous["高"]) / (elapsed - previous["经过物理秒"])
			maximum_speed_error = maxf(maximum_speed_error, absf(observed_speed - expected_speed))
			speed_samples += 1
	_check(consecutive_frames and holding_samples >= 3 and speed_samples >= 20 and maximum_delta > 0.0, "完整配置周期从触底逐物理帧连续采集保持和回弹公开位置")
	_check(not first_move.is_empty() and not returned.is_empty(), "完整配置周期实际采集离底与首次归顶时刻")
	if first_move.is_empty() or returned.is_empty():
		samples.append({"可调拉杆完整周期": trajectory, "离底或归顶样本缺失": true})
		return
	# 首个离底高度按配置匀速回推保持终点，不读取控制件内部剩余时钟。
	var inferred_hold: float = first_move["经过物理秒"] - (first_move["高"] - bottom.y) / expected_speed
	var total_seconds: float = returned["经过物理秒"]
	var return_seconds: float = total_seconds - inferred_hold
	var time_tolerance: float = maximum_delta + 0.00001
	_check(last_bottom_time <= handle.hold_seconds + 0.00001 and first_move["经过物理秒"] >= handle.hold_seconds - 0.00001 and absf(inferred_hold - handle.hold_seconds) <= time_tolerance, "配置0.07秒保持在实测物理采样误差内，期间不提前回弹")
	_check(absf(return_seconds - handle.return_seconds) <= time_tolerance, "配置0.41秒完整回弹在一个实际物理采样间隔内完成")
	_check(absf(total_seconds - (handle.hold_seconds + handle.return_seconds)) <= time_tolerance, "配置完整周期0.48秒在一个实际物理采样间隔内完成")
	_check(maximum_speed_error <= 0.0001 and maximum_position_error <= expected_speed * maximum_delta + 0.00001 and monotonic, "完整回弹逐帧保持配置匀速并沿实际全行程单调归顶")
	_check(maximum_offset_error <= 0.00001 and completion_unique, "完整周期每个物理样本保留横深偏移且完成通知严格唯一")
	samples.append({"可调拉杆完整周期": trajectory, "配置保持秒数": handle.hold_seconds, "配置完整回弹秒数": handle.return_seconds, "配置总秒数": handle.hold_seconds + handle.return_seconds, "配置完整行程": handle.full_travel, "配置匀速": expected_speed, "最后底部样本秒数": last_bottom_time, "首个离底样本秒数": first_move["经过物理秒"], "位置回推保持秒数": inferred_hold, "完整回弹实测秒数": return_seconds, "完整周期实测秒数": total_seconds, "实际最大物理间隔秒数": maximum_delta, "时长允许误差秒数": time_tolerance, "最大位置误差": maximum_position_error, "最大匀速误差": maximum_speed_error, "最大横深误差": maximum_offset_error, "保持样本数": holding_samples, "匀速样本数": speed_samples, "完成通知唯一": completion_unique})


func _test_immediate_method_controls() -> void:
	await _make_fixture(true)
	var slot: AutolysisBlendSlot = device.slots[2]
	var runtime: AnimationPlayer = slot.get("_runtime_player") as AnimationPlayer
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	event_probe.action = func() -> void: slot.cancel_motion("立即方法取消")
	_check(slot.try_toggle(actor), "立即方法轨道取消试验接受打开请求")
	await _wait_condition(slot.is_closed, "立即方法取消在推进返回后安全恢复关闭态")
	_check(event_probe.events == 1 and slot.is_configured(), "立即方法取消仅有实际零秒事件一次，无缓存重入错误")
	event_probe.action = func() -> void: slot.rebind_animation_player(runtime)
	var prior_events: int = event_probe.events
	_check(slot.try_toggle(actor), "立即方法轨道重绑定试验接受打开请求")
	await _wait_condition(slot.is_closed, "立即方法重绑定在推进返回后安全恢复关闭态")
	_check(event_probe.events == prior_events + 1 and slot.is_configured(), "立即方法重绑定仅有实际零秒事件一次，不重放恢复事件")
	event_probe.action = func() -> void: slot.suspend_motion()
	prior_events = event_probe.events
	_check(slot.try_toggle(actor), "立即方法挂起试验接受打开请求")
	await _wait_condition(func() -> bool: return slot.get("_motion_suspended"), "立即方法挂起在推进返回后实际暂停")
	await _frames(1)
	var frozen: Transform3D = slot.transform
	await _frames(6)
	_check(slot.is_animating() and slot.transform.is_equal_approx(frozen) and runtime.is_playing() and event_probe.events == prior_events + 1, "立即方法挂起冻结控制器推进并保留原播放，不重入原生缓存")
	event_probe.action = Callable()
	_check(slot.resume_motion(), "立即方法挂起后允许明确续播")
	await _wait_condition(slot.is_open, "立即方法挂起续播后自然完成打开")
	_check(event_probe.events == prior_events + 2, "立即方法挂起续播仅执行剩余实际方法事件")
	_check(slot.try_toggle(actor), "立即方法失效取消前正常关闭")
	await _wait_condition(slot.is_closed, "立即方法失效取消前关闭自然完成")
	var dependency_result: Dictionary = {"取消返回": true}
	var anchor: AnimatableBody3D = slot.raw_material_anchor as AnimatableBody3D
	event_probe.action = func() -> void:
		anchor.sync_to_physics = true
		dependency_result["取消返回"] = slot.cancel_motion("立即方法局部依赖失效取消")
	prior_events = event_probe.events
	_check(slot.try_toggle(actor), "立即方法局部运动依赖失效取消接受打开请求")
	await _wait_condition(func() -> bool: return not slot.is_animating(), "局部运动依赖失效后安全终结当前动作")
	_check(not dependency_result["取消返回"] and not slot.is_configured() and not slot.is_open() and not slot.is_closed() and event_probe.events == prior_events + 1, "立即方法内局部运动依赖失效不得虚构恢复完成")
	_check(device.is_configured() and actor.focus_controller.is_focused_on(device.focus_target) and device.slots[0].can_toggle(actor), "立即方法内局部运动依赖失效保留聚焦与其他槽入口")
	anchor.sync_to_physics = false
	_check(slot.rebind_animation_player(runtime), "修复局部运动依赖后明确重绑定")
	await _wait_condition(slot.is_closed, "修复局部运动依赖后建立关闭态")
	event_probe.action = func() -> void:
		slot.raw_material_anchor.queue_free()
		dependency_result["取消返回"] = slot.cancel_motion("立即方法失效取消")
	prior_events = event_probe.events
	_check(slot.try_toggle(actor), "立即方法失效取消试验接受打开请求")
	await _wait_condition(func() -> bool: return not slot.is_animating(), "必要依赖失效后终结动作等待且无原生崩溃")
	_check(not dependency_result["取消返回"] and not slot.is_configured() and not slot.is_open() and not slot.is_closed() and event_probe.events == prior_events + 1, "立即方法内依赖失效取消明确拒绝恢复与稳定许可")
	await _wait_condition(func() -> bool: return not actor.focus_controller.is_focused_on(device.focus_target), "核心来源锚点释放后聚焦会话安全结束")
	_check(not device.is_configured() and not slot.can_toggle(actor), "核心来源配对失效不保留设备登记许可")


func _test_restore_library_collision() -> void:
	await _make_fixture(true, false, &"__blend_restore_1")
	var slot: AutolysisBlendSlot = device.slots[2]
	var runtime: AnimationPlayer = slot.get("_runtime_player") as AnimationPlayer
	var original: Animation = device.animation_source.get_animation(slot.animation_name)
	var source_library: AnimationLibrary = device.animation_source.get_animation_library(&"__blend_restore_1")
	var runtime_library: AnimationLibrary = runtime.get_animation_library(&"__blend_restore_1")
	_check(slot.is_closed() and runtime.get_animation(slot.animation_name) == original and event_probe.events == 0, "源动画库名称与初始化恢复临时库同名仍建立关闭态且跳过事件")
	var collision_library: AnimationLibrary = AnimationLibrary.new()
	collision_library.add_animation(&"saved", original)
	runtime.add_animation_library(&"__blend_restore_3", collision_library)
	_check(slot.try_toggle(actor) and slot.cancel_motion("已有库名避让"), "同帧取消接受与当前恢复序号相同的合法库名")
	await _wait_condition(slot.is_closed, "已有库名避让后关闭同步完成")
	_check(runtime.get_animation_library(&"__blend_restore_1") == runtime_library and runtime.get_animation(slot.animation_name) == original and device.animation_source.get_animation_library(&"__blend_restore_1") == source_library, "恢复保留源动画库与独立运行库及原资源身份")
	_check(runtime.get_animation_library(&"__blend_restore_3") == collision_library and runtime.get_animation(&"__blend_restore_3/saved") == original and event_probe.events == 0, "恢复不删除占用同名的额外有效库且不执行方法事件")
	_check(runtime.get_animation_library_list().size() == 2, "恢复临时库完成后只移除自身创建的避让库")
	_check(slot.try_toggle(actor), "已有库名避让后下一次打开接受请求")
	await _wait_condition(slot.is_open, "已有库名避让后下一次打开自然完成")
	_check(event_probe.events == 2, "已有库名避让后原动画实际方法事件仍保持启用")
	samples.append({"同名恢复源库": String(slot.animation_name), "源库保持": device.animation_source.get_animation_library(&"__blend_restore_1") == source_library, "运行库保持": runtime.get_animation_library(&"__blend_restore_1") == runtime_library, "额外库保持": runtime.get_animation_library(&"__blend_restore_3") == collision_library})


func _test_immediate_disposal() -> void:
	await _make_fixture(true)
	var slot: AutolysisBlendSlot = device.slots[2]
	var runtime: AnimationPlayer = slot.get("_runtime_player") as AnimationPlayer
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	var result: Dictionary = {"取消接受": false}
	event_probe.action = func() -> void:
		result["取消接受"] = slot.cancel_motion("推进中取消后释放播放器")
		runtime.queue_free()
	_check(slot.try_toggle(actor), "立即取消后释放播放器试验接受打开请求")
	await _wait_condition(func() -> bool: return not slot.is_animating(), "取消后播放器排队释放不会继续恢复旧动作")
	_check(result["取消接受"] and event_probe.events == 1 and not slot.is_configured() and not slot.is_open() and not slot.is_closed(), "播放器释放撤销待恢复并拒绝稳定许可")
	_check(device.is_configured() and actor.focus_controller.is_focused_on(device.focus_target) and device.slots[0].can_toggle(actor), "取消后播放器释放仍保留其他槽与聚焦")
	await _make_fixture(true)
	slot = device.slots[2]
	runtime = slot.get("_runtime_player") as AnimationPlayer
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	result = {"取消接受": false}
	event_probe.action = func() -> void:
		result["取消接受"] = slot.cancel_motion("推进中取消后释放锚点")
		slot.raw_material_anchor.queue_free()
	_check(slot.try_toggle(actor), "立即取消后释放锚点试验接受打开请求")
	await _wait_condition(func() -> bool: return not slot.is_animating(), "取消后锚点排队释放不会继续恢复旧动作")
	_check(result["取消接受"] and event_probe.events == 1 and not slot.is_configured() and not slot.is_open() and not slot.is_closed(), "必要锚点释放撤销待恢复且不建立稳定许可")
	await _wait_condition(func() -> bool: return not actor.focus_controller.is_focused_on(device.focus_target), "取消后核心锚点释放安全退出聚焦")
	await _make_fixture(true)
	slot = device.slots[2]
	runtime = slot.get("_runtime_player") as AnimationPlayer
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	result = {"取消接受": false}
	event_probe.action = func() -> void:
		result["取消接受"] = slot.cancel_motion("推进中取消后释放槽自身")
		slot.queue_free()
	_check(slot.try_toggle(actor), "立即取消后释放槽自身试验接受打开请求")
	await _frames(3)
	_check(result["取消接受"] and event_probe.events == 1 and not is_instance_valid(slot), "槽自身排队释放后推进返回不提交旧恢复结果")
	await _wait_condition(func() -> bool: return not actor.focus_controller.is_focused_on(device.focus_target), "槽自身释放后核心登记失效安全退出聚焦")
	_check(not device.is_configured(), "槽自身释放后设备许可安全失效且无无效类型赋值")


func _test_terminal_method_suspend() -> void:
	await _make_fixture(true)
	var slot: AutolysisBlendSlot = device.slots[2]
	var runtime: AnimationPlayer = slot.get("_runtime_player") as AnimationPlayer
	runtime.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	_check(slot.try_toggle(actor), "关闭终点零秒方法挂起前正常打开")
	await _wait_condition(slot.is_open, "关闭终点零秒方法挂起前打开自然完成")
	event_probe.action = func() -> void:
		if slot.state == AutolysisBlendSlot.SlotState.CLOSING and runtime.current_animation_position == 0.0:
			slot.suspend_motion()
	_check(slot.try_toggle(actor), "关闭终点零秒方法挂起接受关闭请求")
	await _wait_condition(func() -> bool: return slot.get("_motion_suspended"), "反播到零秒方法处显式挂起同一动作")
	var events_before_resume: int = event_probe.events
	_check(runtime.current_animation_position == 0.0 and slot.is_animating(), "反播零秒挂起保持实际零秒位置与未完成逻辑态")
	_check(slot.resume_motion(), "反播零秒挂起后明确续播")
	await _wait_condition(slot.is_closed, "反播零秒挂起续播后自然完成关闭")
	_check(event_probe.events == events_before_resume, "反播零秒续播不重放已完成的零秒方法事件")
