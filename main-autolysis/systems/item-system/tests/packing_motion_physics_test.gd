extends SceneTree
## 真实封装资产变体及中断；姿态只作表现测量，不参与运行许可。

const MACHINE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/machine_packing_0.tscn")
const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")

class AnimationEvents extends Node:
	var calls: int = 0
	func record() -> void:
		calls += 1

var world: Node3D
var machine: AutolysisPackingMachine
var actor: AutolysisPlayer
var controls: Array[AutolysisPackingMotion] = []
var records: Array[Dictionary] = []
var failures: int = 0
var assertion_count: int = 0
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/容器开闭动画控制实施证据/20261004/packing-checks/motion")
var frame_limit: int = 60
var cycles: int = 3
var completion_count: int = 0
var event_probe: AnimationEvents
var expected_closed: Dictionary = {}
var expected_open: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = arguments.find("--frame-limit")
	if index >= 0 and index + 1 < arguments.size():
		frame_limit = int(arguments[index + 1])
	index = arguments.find("--cycles")
	if index >= 0 and index + 1 < arguments.size():
		cycles = int(arguments[index + 1])
	Engine.max_fps = frame_limit
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(640, 360)
	await _create_case()
	for cycle: int in range(cycles):
		await _cycle_all(cycle, false)
	for duration: float in [0.08, 0.65, 1.2]:
		await _create_case(duration, false, duration == 0.65)
		await _cycle_all(0, true)
	await _create_case(0.65, true)
	await _cycle_all(0, true)
	await _create_case(0.65, false, false, true)
	await _cycle_all(0, true)
	await _create_case(0.65)
	await _test_interruptions()
	await _create_case(0.08)
	await _test_pending_takeover()
	await _create_case(0.08)
	await _test_pending_resource_replacement()
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("运动资产与中断报告.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"后端": DisplayServer.get_name(), "命令参数": OS.get_cmdline_args(), "断言数": assertion_count, "失败数": failures, "记录": records}, "\t"))
	world.queue_free()
	await physics_frame
	print("封装运动资产与中断断言数：", assertion_count, "；失败总数：", failures)
	quit(0 if failures == 0 else 1)


func _create_case(duration: float = 0.0, equal_ends: bool = false, reparented: bool = false, named_library: bool = false) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await physics_frame
	world = Node3D.new()
	root.add_child(world)
	machine = MACHINE_SCENE.instantiate() as AutolysisPackingMachine
	machine.rotation.y = 0.41
	controls.assign(machine.type_switches)
	controls.append(machine.door)
	expected_closed.clear()
	expected_open.clear()
	event_probe = AnimationEvents.new()
	event_probe.name = "AnimationEvents"
	machine.add_child(event_probe)
	if reparented:
		var grouping: Node3D = Node3D.new()
		grouping.name = "Controls"
		machine.add_child(grouping)
		for control: AutolysisPackingMotion in controls:
			control.owner = null
			control.reparent(grouping, false)
			control.owner = machine
	if duration > 0.0:
		for control: AutolysisPackingMotion in controls:
			_variant_animation(control, duration, equal_ends)
		machine.animation_source.speed_scale = 1.75
	if named_library:
		var original_library: AnimationLibrary = machine.animation_source.get_animation_library(&"")
		var qualified_library: AnimationLibrary = AnimationLibrary.new()
		for control: AutolysisPackingMotion in controls:
			var local_name: StringName = control.animation_name
			qualified_library.add_animation(local_name, original_library.get_animation(local_name))
			original_library.remove_animation(local_name)
			control.animation_name = StringName("_packing_restore/" + String(local_name))
		machine.animation_source.add_animation_library(&"_packing_restore", qualified_library)
	world.add_child(machine)
	actor = PLAYER_SCENE.instantiate() as AutolysisPlayer
	world.add_child(actor)
	actor.set_physics_process(false)
	if DisplayServer.get_name() == "headless":
		actor.focus_controller.configure(actor, actor.camera, actor.held_item_presenter, _headless_entry_allowed)
	await physics_frame
	await physics_frame
	_check(machine.is_configured(), "封装机器核心登记有效")
	_check(actor.focus_controller.try_enter(machine.focus_target), "真实玩家进入封装聚焦")
	var deadline: int = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 5
	while not machine.is_actor_focused(actor) and Engine.get_physics_frames() < deadline:
		await physics_frame
	_check(machine.is_actor_focused(actor), "真实玩家聚焦稳定")
	for control: AutolysisPackingMotion in controls:
		(control.get("_runtime_player") as AnimationPlayer).callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
		control.motion_completed.connect(_on_completed)
		_check(control.is_closed(), "控制件初始化由当前动画建立关闭态：%s" % control.name)
		if named_library:
			_check((control.get("_runtime_player") as AnimationPlayer).has_animation_library(&"_packing_restore"), "临时库默认名称与业务源库相同时保留原业务动画库：%s" % control.name)
	_check(event_probe.calls == 0, "属性专用初始化未执行方法轨道")
	completion_count = 0
	records.append({"变体": duration, "首尾相同": equal_ends, "调整层级": reparented, "命名动画库": named_library, "速度倍率": machine.animation_source.speed_scale, "父级旋转": str(machine.rotation)})


func _variant_animation(control: AutolysisPackingMotion, duration: float, equal_ends: bool) -> void:
	var animation: Animation = Animation.new()
	animation.length = duration
	var path: String = str(machine.get_path_to(control))
	var closed_position: Vector3 = control.position
	var opened_position: Vector3 = closed_position + Vector3(0.015, 0.025, -0.01)
	var closed_rotation: Vector3 = Vector3(0.04, 0.08, -0.03)
	var opened_rotation: Vector3 = Vector3(0.29, 0.37, 0.12)
	var closed_scale: Vector3 = Vector3.ONE * 0.93
	var opened_scale: Vector3 = Vector3.ONE * 1.04
	for property: String in ["rotation", "position", "scale"]:
		var closed_value: Vector3 = closed_rotation if property == "rotation" else (closed_position if property == "position" else closed_scale)
		var opened_value: Vector3 = opened_rotation if property == "rotation" else (opened_position if property == "position" else opened_scale)
		var track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath(path + ":" + property))
		animation.track_insert_key(track, 0.0, closed_value)
		animation.track_insert_key(track, duration * 0.5, opened_value)
		animation.track_insert_key(track, duration, closed_value if equal_ends else opened_value)
	var event_track: int = animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(event_track, NodePath("AnimationEvents"))
	animation.track_insert_key(event_track, 0.0, {"method": &"record", "args": []})
	animation.track_insert_key(event_track, duration * 0.5, {"method": &"record", "args": []})
	var library: AnimationLibrary = machine.animation_source.get_animation_library(&"")
	# 每个夹具持有独立库，避免变体改变其他机器或原始资产。
	var isolated: AnimationLibrary = library.duplicate() as AnimationLibrary
	machine.animation_source.remove_animation_library(&"")
	machine.animation_source.add_animation_library(&"", isolated)
	isolated.remove_animation(control.animation_name)
	isolated.add_animation(control.animation_name, animation)
	expected_closed[control] = Transform3D(Basis.from_euler(closed_rotation).scaled(closed_scale), closed_position)
	expected_open[control] = expected_closed[control] if equal_ends else Transform3D(Basis.from_euler(opened_rotation).scaled(opened_scale), opened_position)


func _headless_entry_allowed() -> bool:
	return actor._base_input_allowed() and not actor.focus_controller.has_control()


func _on_completed(_opened: bool) -> void:
	completion_count += 1


func _command_motion(control: AutolysisPackingMotion, opening: bool) -> void:
	if control is AutolysisPackingTypeSwitch:
		(control as AutolysisPackingTypeSwitch).set_selected(opening)
	else:
		_check((control as AutolysisPackingDoor).try_toggle(actor), "正式舱门接受目标动作")


func _cycle_all(cycle: int, measure: bool) -> void:
	for opening: bool in [true, false]:
		var previous_completions: int = completion_count
		for control: AutolysisPackingMotion in controls:
			_command_motion(control, opening)
		await _observe_motion()
		_check(completion_count == previous_completions + controls.size(), "每个目标自然完成只发布一次：轮次%d、打开%s" % [cycle, opening])
		var stable: Dictionary = {}
		for control: AutolysisPackingMotion in controls:
			_check(control.is_open() if opening else control.is_closed(), "目标完成后稳定业务态：%s" % control.name)
			stable[control] = control.transform
			if measure:
				var expected: Transform3D = expected_open[control] if opening else expected_closed[control]
				_check(_transform_near(control.transform, expected), "多属性表现保留本次旋转、位移与缩放：%s" % control.name)
		var events_after_finish: int = event_probe.calls
		for _sample: int in range(6):
			await physics_frame
			for control: AutolysisPackingMotion in controls:
				_check(_transform_near(control.transform, stable[control]), "自然结果在稳定阶段保留：%s" % control.name)
		_check(event_probe.calls == events_after_finish, "稳定阶段未重放方法事件轨道")


func _transform_near(actual: Transform3D, expected: Transform3D) -> bool:
	return actual.origin.distance_to(expected.origin) < 0.001 and actual.basis.x.distance_to(expected.basis.x) < 0.001 and actual.basis.y.distance_to(expected.basis.y) < 0.001 and actual.basis.z.distance_to(expected.basis.z) < 0.001


func _observe_motion() -> void:
	var deadline: int = Engine.get_physics_frames() + Engine.physics_ticks_per_second * 5
	while Engine.get_physics_frames() < deadline:
		await physics_frame
		var moving: bool = false
		for control: AutolysisPackingMotion in controls:
			moving = moving or control.is_animating()
			var runtime: AnimationPlayer = control.get("_runtime_player") as AnimationPlayer
			records.append({"控制件": str(control.name), "物理帧": Engine.get_physics_frames(), "状态": control.state, "完成待处理": control.get("_completion_pending"), "动作序号": control.get("_motion_serial"), "实际变换": str(control.transform), "全局变换": str(control.global_transform), "进度": runtime.current_animation_position if is_instance_valid(runtime) and not runtime.current_animation.is_empty() else -1.0, "错误": control.get_configuration_error()})
		if not moving:
			return
	_check(false, "目标动作未在测试上限内终结")


func _test_interruptions() -> void:
	var door: AutolysisPackingDoor = machine.door
	_check(door.try_toggle(actor), "暂停用例打开请求已接受")
	await physics_frame
	await physics_frame
	_check(door.pause_motion(), "控制器显式暂停动作")
	var paused_transform: Transform3D = door.transform
	var paused_position: float = (door.get("_runtime_player") as AnimationPlayer).current_animation_position
	for _frame: int in range(5):
		await physics_frame
	_check(door.is_animating() and completion_count == 0 and _transform_near(door.transform, paused_transform), "暂停保留动作且未发布完成")
	_check(is_equal_approx((door.get("_runtime_player") as AnimationPlayer).current_animation_position, paused_position), "暂停保留当前动画进度")
	_check(door.resume_motion(), "同一动作显式续播")
	await _observe_motion()
	_check(door.is_open() and completion_count == 1, "续播只自然完成一次")
	_check(door.try_toggle(actor), "关闭取消用例接受请求")
	await physics_frame
	await physics_frame
	var events_before_cancel: int = event_probe.calls
	door.cancel_motion()
	await _observe_motion()
	_check(door.is_open() and completion_count == 1, "关闭中取消恢复此前确实完成的打开态且不发布完成")
	_check(event_probe.calls == events_before_cancel, "取消恢复未执行零秒或其他方法事件")
	_check(door.try_toggle(actor), "再次关闭接受请求")
	await _observe_motion()
	_check(door.is_closed(), "取消恢复后可自然关闭")
	_check(door.try_toggle(actor), "同帧取消用例接受打开")
	var events_before_immediate: int = event_probe.calls
	door.cancel_motion()
	await _observe_motion()
	_check(door.is_closed() and event_probe.calls == events_before_immediate, "合法请求零秒事件之后同帧取消不追加方法事件")
	var immediate_player: AnimationPlayer = door.get("_runtime_player") as AnimationPlayer
	immediate_player.play(door.animation_name)
	_check(door.rebind_animation_player(immediate_player), "未推进外部播放后立即重新绑定")
	await _observe_motion()
	_check(door.is_closed() and event_probe.calls == events_before_immediate, "外部播放后立即重绑恢复不执行残留启动事件")
	var before_cancel: int = completion_count
	_check(door.try_toggle(actor), "打开取消用例接受请求")
	await physics_frame
	door.cancel_motion()
	await _observe_motion()
	_check(door.is_closed() and completion_count == before_cancel, "打开中取消恢复关闭态且不虚报完成")
	_check(door.try_toggle(actor), "外部停止用例接受请求")
	await physics_frame
	(door.get("_runtime_player") as AnimationPlayer).stop(true)
	await physics_frame
	await physics_frame
	_check(not door.is_animating() and not door.get_configuration_error().is_empty(), "外部停止终结动作并记录原因")
	_check(machine.is_configured() and actor.focus_controller.is_focused_on(machine.focus_target), "局部门中断不使机器登记或聚焦失效")
	_check(door.restore_closed(), "显式恢复建立配置关闭态")
	await _observe_motion()
	for takeover: int in range(3):
		var paused_completion_count: int = completion_count
		_check(door.try_toggle(actor), "挂起期间外部接管用例接受打开")
		await physics_frame
		await physics_frame
		_check(door.pause_motion(), "外部接管之前挂起手动推进")
		var paused_player: AnimationPlayer = door.get("_runtime_player") as AnimationPlayer
		if takeover == 0:
			paused_player.stop(true)
		elif takeover == 1:
			paused_player.play_backwards(door.animation_name)
		else:
			paused_player.get_animation_library(&"").add_animation(&"external_takeover", paused_player.get_animation(door.animation_name))
			paused_player.play(&"external_takeover")
		await physics_frame
		await physics_frame
		_check(not door.is_animating() and not door.get_configuration_error().is_empty() and completion_count == paused_completion_count, "挂起期间外部停止、反向或名称替换立即终结旧动作且无完成许可")
		_check(door.restore_closed(), "挂起期间接管之后显式恢复关闭")
		await _observe_motion()
	var before_replacement: int = completion_count
	_check(door.try_toggle(actor), "同名反向接管用例接受打开请求")
	await physics_frame
	await physics_frame
	(door.get("_runtime_player") as AnimationPlayer).play_backwards(door.animation_name)
	await physics_frame
	await physics_frame
	_check(not door.is_animating() and not door.is_open() and completion_count == before_replacement and not door.get_configuration_error().is_empty(), "同名反播接管终结旧动作且不误授予打开许可")
	_check(door.restore_closed(), "同名反播接管之后显式恢复关闭")
	await _observe_motion()
	_check(door.try_toggle(actor), "播放器释放用例接受请求")
	await physics_frame
	var old_player: AnimationPlayer = door.get("_runtime_player") as AnimationPlayer
	old_player.queue_free()
	await physics_frame
	await physics_frame
	_check(not door.is_animating() and not door.is_open(), "播放器释放未伪造自然完成且已清理等待")
	var replacement: AnimationPlayer = machine.call("_create_player", door.animation_name, "ReplacementDoorAnimation") as AnimationPlayer
	_check(door.rebind_animation_player(replacement), "必要播放器重新绑定")
	await _observe_motion()
	_check(door.is_closed(), "重新绑定建立关闭态而不恢复被取消打开态")
	_check(door.try_toggle(actor), "重新绑定后接受新打开")
	await _observe_motion()
	_check(door.is_open(), "重新绑定后新动作按自然完成开放")
	var active_player: AnimationPlayer = door.get("_runtime_player") as AnimationPlayer
	var looping: Animation = active_player.get_animation(door.animation_name).duplicate() as Animation
	looping.loop_mode = Animation.LOOP_LINEAR
	var loop_library: AnimationLibrary = active_player.get_animation_library(&"")
	loop_library.remove_animation(door.animation_name)
	loop_library.add_animation(door.animation_name, looping)
	_check(not door.rebind_animation_player(active_player) and door.get_configuration_error().contains("非循环"), "循环动作不能完成时给出实际配置理由")
	_check(machine.is_configured() and actor.focus_controller.is_focused_on(machine.focus_target), "循环门动作只限制门相关入口而保留机器聚焦")


func _check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failures += 1
	print(("通过：" if condition else "失败：") + description)


func _test_pending_takeover() -> void:
	var runtime: AnimationPlayer = machine.door.get("_runtime_player") as AnimationPlayer
	runtime.animation_finished.connect(_takeover_finished.bind(runtime), CONNECT_ONE_SHOT)
	_check(machine.door.try_toggle(actor), "完成同步窗口接管用例接受打开")
	await _observe_motion()
	_check(completion_count == 0 and not machine.door.is_open() and not machine.door.is_animating() and not machine.door.get_configuration_error().is_empty(), "目标完成后同步窗口外部同名重播不获得打开许可")


func _takeover_finished(_animation_name: StringName, runtime: AnimationPlayer) -> void:
	runtime.play(machine.door.animation_name)


func _test_pending_resource_replacement() -> void:
	var runtime: AnimationPlayer = machine.door.get("_runtime_player") as AnimationPlayer
	runtime.animation_finished.connect(_replace_finished_resource.bind(runtime), CONNECT_ONE_SHOT)
	_check(machine.door.try_toggle(actor), "完成同步窗口资源替换用例接受打开")
	await _observe_motion()
	_check(completion_count == 0 and not machine.door.is_open() and not machine.door.is_animating() and not machine.door.get_configuration_error().is_empty(), "完成同步窗口同名资源替换终结旧动作且不误授予打开")


func _replace_finished_resource(_animation_name: StringName, runtime: AnimationPlayer) -> void:
	var replacement: Animation = runtime.get_animation(machine.door.animation_name).duplicate() as Animation
	var library: AnimationLibrary = runtime.get_animation_library(&"")
	library.remove_animation(machine.door.animation_name)
	library.add_animation(machine.door.animation_name, replacement)
