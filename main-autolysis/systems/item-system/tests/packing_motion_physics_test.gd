extends SceneTree
## 正式封装器控制件连续正反播放，逐物理帧保存真实姿态和状态。

const MACHINE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/machine_packing_0.tscn")
const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")

var world: Node3D
var machine: AutolysisPackingMachine
var actor: AutolysisPlayer
var controls: Array[AutolysisPackingMotion] = []
var records: Array[Dictionary] = []
var failures: int = 0
var assertion_count: int = 0
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/封装器与气动胶囊实施证据/20261003/switch-fault/default")
var frame_limit: int = 60
var cycles: int = 20
var physics_before: int = 0
var render_before: int = 0
var endpoint_fault_injected: bool = false


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
	world = Node3D.new()
	root.add_child(world)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 1.0, 3.0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	machine = MACHINE_SCENE.instantiate() as AutolysisPackingMachine
	world.add_child(machine)
	await physics_frame
	await physics_frame
	_check(machine.is_configured(), "正式机器初始化成功")
	if arguments.has("--all-controls"):
		controls.assign(machine.type_switches)
		controls.append(machine.door)
		actor = PLAYER_SCENE.instantiate() as AutolysisPlayer
		world.add_child(actor)
		actor.set_physics_process(false)
		if DisplayServer.get_name() == "headless":
			# 无图形后端缺少鼠标捕获状态，其余聚焦门控使用正式玩家。
			actor.focus_controller.configure(actor, actor.camera, actor.held_item_presenter, _headless_entry_allowed)
		_check(actor.focus_controller.try_enter(machine.focus_target), "正式玩家进入舱门测试聚焦会话")
		for _frame: int in range(18):
			await physics_frame
		_check(machine.is_actor_focused(actor), "正式玩家完成舱门测试聚焦过渡")
	else:
		controls.append(machine.type_switches[0])
	physics_before = Engine.get_physics_frames()
	render_before = Engine.get_process_frames()
	if arguments.has("--inject-endpoint-offset"):
		var runtime_player: AnimationPlayer = controls[0].get("_runtime_player") as AnimationPlayer
		runtime_player.animation_finished.connect(_inject_endpoint_offset.bind(controls[0]), CONNECT_ONE_SHOT)
		_command_motion(controls[0], true)
		await _observe_motion(0, "开启")
		_check(endpoint_fault_injected, "动画实际完成信号已注入明显端帧偏移")
		_check(not controls[0].get_configuration_error().is_empty() and not controls[0].is_open(), "真实动画结束后明显端帧偏移仍被拒绝并留下故障")
		_save_report()
		world.queue_free()
		await physics_frame
		print("开关故障保护断言数：", assertion_count, "；失败总数：", failures)
		quit(0 if failures == 0 else 1)
		return
	for cycle: int in range(cycles):
		for control: AutolysisPackingMotion in controls:
			_command_motion(control, true)
		await _observe_motion(cycle, "开启")
		for control: AutolysisPackingMotion in controls:
			_check(control.is_open(), "第%d轮控制件%s抵达开启端帧" % [cycle, control.name])
		for control: AutolysisPackingMotion in controls:
			_command_motion(control, false)
		await _observe_motion(cycle, "关闭")
		for control: AutolysisPackingMotion in controls:
			_check(control.is_closed(), "第%d轮控制件%s抵达关闭端帧" % [cycle, control.name])
		if failures > 0:
			break
	_save_report()
	world.queue_free()
	await physics_frame
	print("开关连续运动断言数：", assertion_count, "；失败总数：", failures)
	quit(0 if failures == 0 else 1)


func _inject_endpoint_offset(_animation_name: StringName, control: AutolysisPackingMotion) -> void:
	endpoint_fault_injected = true
	var endpoint: Vector3 = control.get("_open_rotation")
	control.rotation = endpoint + Vector3(0.02, 0.0, 0.0)


func _headless_entry_allowed() -> bool:
	return actor._base_input_allowed() and not actor.focus_controller.has_control()


func _command_motion(control: AutolysisPackingMotion, opening: bool) -> void:
	if control is AutolysisPackingTypeSwitch:
		(control as AutolysisPackingTypeSwitch).set_selected(opening)
	elif control is AutolysisPackingDoor:
		_check((control as AutolysisPackingDoor).try_toggle(actor), "正式舱门接受运动请求")


func _observe_motion(cycle: int, direction: String) -> void:
	var fault_step: int = -1
	for step: int in range(20):
		await physics_frame
		var all_stopped: bool = true
		for control: AutolysisPackingMotion in controls:
			_record_motion(control, cycle, direction, step)
			all_stopped = all_stopped and not control.is_animating()
			if not control.get_configuration_error().is_empty() and fault_step < 0:
				fault_step = step
		if fault_step >= 0 and step - fault_step >= 6:
			return
		if fault_step < 0 and all_stopped:
			return


func _record_motion(control: AutolysisPackingMotion, cycle: int, direction: String, step: int) -> void:
	var runtime_player: AnimationPlayer = control.get("_runtime_player") as AnimationPlayer
	var animation: Animation = runtime_player.get_animation(control.animation_name)
	var last_key: int = animation.track_get_key_count(0) - 1
	var expected: Vector3 = animation.track_get_key_value(0, last_key if direction == "开启" else 0)
	var last_rotation: Vector3 = animation.track_get_key_value(0, last_key)
	var configured_rotation: Vector3 = control.get("_open_rotation") if direction == "开启" else control.get("_closed_rotation")
	var quaternion_delta: Quaternion = control.basis.get_rotation_quaternion().inverse() * Quaternion.from_euler(expected)
	var stable_quaternion_angle: float = 2.0 * atan2(Vector3(quaternion_delta.x, quaternion_delta.y, quaternion_delta.z).length(), absf(quaternion_delta.w))
	records.append({
		"控制件": str(control.name),
		"轮次": cycle,
		"方向": direction,
		"采样": step,
		"物理帧": Engine.get_physics_frames(),
		"处理帧": Engine.get_process_frames(),
		"状态": int(control.state),
		"待完成": control.get("_completion_pending"),
		"动画正在播放": runtime_player.is_playing(),
		"动画进度": runtime_player.current_animation_position,
		"角度": [control.rotation.x, control.rotation.y, control.rotation.z],
		"目标角度": [expected.x, expected.y, expected.z],
		"角度差": [control.rotation.x - expected.x, control.rotation.y - expected.y, control.rotation.z - expected.z],
		"默认旋转近似通过": control.rotation.is_equal_approx(expected),
		"四元数角距离": control.basis.get_rotation_quaternion().angle_to(Quaternion.from_euler(expected)),
		"四元数稳定角距离": stable_quaternion_angle,
		"末关键帧角度": [last_rotation.x, last_rotation.y, last_rotation.z],
		"配置目标角度": [configured_rotation.x, configured_rotation.y, configured_rotation.z],
		"全局角度": [control.global_rotation.x, control.global_rotation.y, control.global_rotation.z],
		"错误": control.get_configuration_error()
	})


func _check(condition: bool, description: String) -> void:
	assertion_count += 1
	if not condition:
		failures += 1
	print(("通过：" if condition else "失败：") + description)


func _save_report() -> void:
	var report: Dictionary = {
		"渲染后端": DisplayServer.get_name(),
		"渲染帧率上限": frame_limit,
		"请求循环数": cycles,
		"控制件数": controls.size(),
		"明显端帧偏移已注入": endpoint_fault_injected,
		"物理帧率": Engine.physics_ticks_per_second,
		"物理帧数": Engine.get_physics_frames() - physics_before,
		"处理帧数": Engine.get_process_frames() - render_before,
		"断言数": assertion_count,
		"失败数": failures,
		"记录": records
	}
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("连续拨动报告.json"), FileAccess.WRITE)
	if file == null:
		push_error("连续拨动报告无法创建")
		failures += 1
		return
	file.store_string(JSON.stringify(report, "\t"))
