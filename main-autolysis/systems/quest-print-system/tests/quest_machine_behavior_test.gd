extends SceneTree
## 无图形真实补间专项；夹具只替换玩家输入许可，不替换打印动作与数据来源。

const MACHINE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/quest_machine_0.tscn")
const FIRST_TASK: AutolysisQuestPrintDefinition = preload("res://main-autolysis/systems/quest-print-system/quests/quest_test_0.tres")
const FPS: float = 60.0

class TestFocus extends AutolysisFocusController:
	func _process(_delta: float) -> void:
		pass

class TestPlayer extends AutolysisPlayer:
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass
	func is_focus_business_allowed() -> bool:
		return is_inside_tree() and not is_queued_for_deletion() and not get_tree().paused and not is_movement_paused and not is_showing_ui

class EventCounter extends Node:
	var completed: int = 0
	var cancelled: int = 0
	func on_completed(_serial: int) -> void:
		completed += 1
	func on_cancelled(_serial: int, _reason: String) -> void:
		cancelled += 1

class MethodEvent extends Node:
	var calls: int = 0
	func record() -> void:
		calls += 1

var world: Node3D
var player: TestPlayer
var machine: AutolysisQuestMachine
var failures: int = 0
var assertion_count: int = 0
var records: Array[Dictionary] = []
var scenarios: Array[Dictionary] = []
var evidence_directory: String


func _initialize() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/任务文件打印实施证据/20261007/machine")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	check(DisplayServer.get_name() == "headless", "仅无图形执行，不启动窗口或操作指针")
	if "--audio-pause-probe" in OS.get_cmdline_user_args():
		await _test_audio_pause_probe()
		await _wait_actual_audio_mixes(null, 2)
		_write_report()
		quit(0 if failures == 0 else 1)
		return
	if "--audio-pause-check" in OS.get_cmdline_user_args():
		await _test_pause_matrix()
		await _wait_actual_audio_mixes(null, 2)
		_write_report()
		quit(0 if failures == 0 else 1)
		return
	await _run_case("首份当前配置十三行", FIRST_TASK.data_lines, false)
	await _run_case("当前配置二十一行", _lines(21), false)
	for count: int in [1, 20, 22, 25]:
		await _run_case("容量%d" % count, _lines(count), true)
	for data: PackedStringArray in [PackedStringArray(["", "a"]), PackedStringArray(["", "", "a", "b"]), PackedStringArray(["a", "", "b"]), PackedStringArray(["a", ""]), PackedStringArray(["a", "", ""]), PackedStringArray(["", "", ""]), PackedStringArray([" ", "\t", ""]), _blank_lines(21)]:
		await _run_case("空行矩阵", data, true)
	await _test_pending_and_snapshot()
	await _test_pause_matrix()
	await _test_audio_start_pause_boundary()
	await _test_completion_pause_boundary()
	await _test_cancel_matrix()
	await _test_dependency_release_and_rebind()
	await _test_optional_effects_and_instances()
	await _test_configured_variants()
	await _test_active_configuration_snapshot()
	await _test_start_failure_and_external_stop()
	await _test_item_contents_replacement()
	await _test_press_event_restore()
	# 已停止播放由音频线程下一次混音删除；退出前观察实际混音清理边界。
	await _wait_actual_audio_mixes(null, 2)
	_write_report()
	print("打印设备专项断言数：", assertion_count, "；失败数：", failures)
	quit(0 if failures == 0 else 1)


func _write_report() -> void:
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("打印设备专项报告.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "断言": records, "场景": scenarios, "参数": OS.get_cmdline_args(), "采样物理帧秒": 1.0 / FPS}, "\t"))


func _test_audio_pause_probe() -> void:
	for completed: bool in [false, true]:
		await _prepare()
		machine.request_task_print(_definition(PackedStringArray(["a"])), player)
		if completed:
			machine.try_start_print(player)
			await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
		await frames(3)
		var audio: AudioStreamPlayer3D = machine.scanning_player if completed else machine.notice_player
		var samples: Array[Dictionary] = []
		samples.append(_audio_sample(audio))
		player.is_showing_ui = true
		for index: int in 40:
			OS.delay_msec(2)
			await process_frame
			samples.append(_audio_sample(audio))
		player.is_showing_ui = false
		for index: int in 20:
			OS.delay_msec(2)
			await process_frame
			samples.append(_audio_sample(audio))
		scenarios.append({"名称": "异步混音暂停边界探针", "完成提示": completed, "驱动": AudioServer.get_driver_name(), "采样率": AudioServer.get_mix_rate(), "样本": samples})
		await _dispose()


func _audio_sample(audio: AudioStreamPlayer3D) -> Dictionary:
	var sample: Dictionary = {"墙钟微秒": Time.get_ticks_usec(), "物理帧": Engine.get_physics_frames(), "上次混音后秒": AudioServer.get_time_since_last_mix(), "服务器暂停请求": audio.stream_paused, "播放位置": audio.get_playback_position(), "底层播放位置": audio.get_stream_playback().get_playback_position() if audio.has_stream_playback() else null, "底层已启动": audio.get_stream_playback().is_playing() if audio.has_stream_playback() else false, "可处理": audio.can_process()}
	var index: int = 0 if audio == machine.notice_player else 1
	var material: StandardMaterial3D = (machine.get("_materials") as Array)[index]
	sample["提示发光倍率"] = material.emission_energy_multiplier
	return sample


func _wait_actual_audio_mixes(audio: AudioStreamPlayer3D, count: int) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	var previous: float = AudioServer.get_time_since_last_mix()
	var observed: int = 0
	var started: int = Time.get_ticks_usec()
	while observed < count and Time.get_ticks_usec() - started < 2000000:
		# 一毫秒只让混音线程取得调度；真正读取点由实际混音时钟复位决定。
		OS.delay_msec(1)
		await process_frame
		var current: float = AudioServer.get_time_since_last_mix()
		if current < previous:
			observed += 1
		if is_instance_valid(audio):
			samples.append(_audio_sample(audio))
		previous = current
	check(observed == count, "观测实际音频混音周期而非假定物理帧同步")
	return samples


func _prepare(short_actions: bool = true) -> void:
	world = Node3D.new()
	root.add_child(world)
	var actor_candidate: Node = preload("res://main-autolysis/player/autolysis_player.tscn").instantiate()
	actor_candidate.set_script(TestPlayer)
	player = actor_candidate as TestPlayer
	player.get_node("FocusController").set_script(TestFocus)
	world.add_child(player)
	machine = MACHINE_SCENE.instantiate() as AutolysisQuestMachine
	if short_actions:
		_shorten(machine, 0.05)
	world.add_child(machine)
	machine.reference_camera.make_current()
	player.focus_controller.state = AutolysisFocusController.FocusState.FOCUSED
	player.focus_controller.set("_target", machine.focus_target)
	player.focus_controller.session_id = 1
	await frames(2)
	check(machine.is_configured(), "真实场景聚焦配置有效")
	check(machine.state == AutolysisQuestMachine.PrintState.IDLE and machine.get_current_paper() == null, "运行初态没有预置纸张")


func _shorten(target: AutolysisQuestMachine, seconds: float) -> void:
	for property: StringName in [&"first_descent_seconds", &"first_wait_seconds", &"first_left_seconds", &"print_line_seconds", &"return_left_seconds", &"next_line_seconds", &"center_seconds", &"reset_seconds"]:
		target.set(property, seconds)


func _definition(data: PackedStringArray) -> AutolysisQuestPrintDefinition:
	var definition: AutolysisQuestPrintDefinition = AutolysisQuestPrintDefinition.new()
	definition.task_id = "quest_test_0"
	definition.data_lines = data
	return definition


func _start(data: PackedStringArray) -> bool:
	var accepted: bool = machine.request_task_print(_definition(data), player)
	check(accepted and machine.state == AutolysisQuestMachine.PrintState.PENDING and machine.get_current_paper() == null, "任务事件只建立待打印")
	check(not machine.request_task_print(_definition(PackedStringArray(["replacement"])), player), "忙碌事件不覆盖本次任务")
	var started: bool = machine.print_button.print_interaction.try_interact(player)
	check(started and machine.state == AutolysisQuestMachine.PrintState.PRINTING and machine.get_current_paper() != null, "唯一按钮入口建立一份空白纸张")
	check(not machine.try_start_print(player), "开始后重复正式入口拒绝")
	check(machine.get_current_paper().get_visible_data_line_indices().is_empty(), "打印开始全文隐藏")
	return started


func _run_case(name: String, data: PackedStringArray, short_actions: bool) -> void:
	await _prepare(short_actions)
	var counts: EventCounter = EventCounter.new()
	world.add_child(counts)
	machine.print_completed.connect(counts.on_completed)
	machine.print_completed.connect(func(_serial: int) -> void: check(machine.get_current_paper().is_print_complete(), "最早完成观察纸张已补全"))
	if _start(data):
		await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE, 11000)
		check(counts.completed == 1, "自然完成通知唯一")
		_validate_trace(name, data)
	await _dispose()


func _validate_trace(name: String, data: PackedStringArray) -> void:
	var snapshot: Dictionary = machine.get_print_snapshot()
	var events: Array = snapshot["events"]
	var config: Dictionary = snapshot["config"]
	var count: int = mini(data.size(), int(config["capacity"]))
	var nonempty: int = 0
	for index: int in count:
		if not data[index].is_empty():
			nonempty += 1
	var ordinary_returns: int = nonempty - (1 if not data[count - 1].is_empty() else 0)
	check(_event_count(events, &"action_started", &"print_line") == nonempty, "非空机械行横向次数正确")
	check(_event_count(events, &"action_started", &"first_left") == (1 if nonempty > 0 else 0), "首次移左只在首个非空行前一次")
	check(_event_count(events, &"action_started", &"return_left") == ordinary_returns, "普通回程按末个机械行决定")
	check(_event_count(events, &"action_started", &"next_line") == count - 1, "空行保留机械位置且不超容量")
	check(_event_count(events, &"line_revealed") == count, "每个机械数据行只显示一次")
	check(machine.get_current_paper().get_visible_data_line_indices().size() == data.size(), "复位完成后全文补全超容量行")
	var last_data_y: float = 0.0
	var finished_index: int = -1
	var final_event_index: int = -1
	var center_finish: int = -1
	var axis_start: int = -1
	var axis_finish: int = -1
	var start_frame: int = -1
	var end_frame: int = -1
	var stage_start: Dictionary = {}
	for index: int in events.size():
		var event: Dictionary = events[index]
		if event["event"] == &"action_started":
			stage_start = event
			if event["phase"] == &"first_descent":
				start_frame = int(event["physics_frame"])
			if event["phase"] == &"axis_reset":
				axis_start = index
		if event["event"] == &"action_finished":
			if event["phase"] == &"print_line":
				finished_index = index
			if event["phase"] == &"center":
				center_finish = index
			if event["phase"] == &"axis_reset":
				axis_finish = index
				end_frame = int(event["physics_frame"])
			if not stage_start.is_empty():
				var measured: float = float(int(event["physics_frame"]) - int(stage_start["physics_frame"])) / FPS
				check(absf(measured - _phase_seconds(StringName(event["phase"]), config)) <= 2.1 / FPS, "有限动作按配置自然结束")
		if event["event"] == &"line_revealed":
			var line: int = int(event["line"])
			var axis_position: Vector3 = event["axis_position"]
			var first: Vector3 = config["first"]
			check(absf(axis_position.y - (first.y - float(line) * float(config["spacing"]))) < 0.000001, "显示行的轴位置由整数索引计算")
			if not data[line].is_empty():
				check(finished_index == index - 1, "非空行在自然完成事件之后先显示再回程")
			last_data_y = axis_position.y
			final_event_index = index
	check(center_finish > final_event_index and axis_start > center_finish and axis_finish > axis_start, "末行处理后先归中再横轴复位")
	check((machine.horizontal_axis.position - Vector3(config["axis_reset"])).length() < 0.000001 and (machine.print_head.position - Vector3(config["center"])).length() < 0.000001, "两杆完成实际局部位置与本次配置匹配")
	var theory: float = float(config["first_descent"]) + float(config["first_wait"]) + (float(config["first_left"]) if nonempty > 0 else 0.0) + float(nonempty) * float(config["print_line"]) + float(ordinary_returns) * float(config["return_left"]) + float(count - 1) * float(config["next_line"]) + float(config["center_time"]) + float(config["reset_time"])
	var measured: float = float(end_frame - start_frame) / FPS
	check(absf(measured - theory) <= float(_event_count(events, &"action_started") + 2) / FPS, "理论动作时长与固定物理帧实测误差在逐阶段调度范围")
	if name in ["首份当前配置十三行", "当前配置二十一行"]:
		check(float(config["print_line"]) == 2.5, "本轮默认非空行横向打印时长为二点五秒")
		check(absf(theory - (41.8 if count == 13 else 66.6)) < 0.00001, "当前配置十三或二十一行理论核算正确")
	var first_event: Dictionary = events[0]
	var last_event: Dictionary = events[events.size() - 1]
	scenarios.append({"名称": name, "原始数据": data, "机械行": count, "非空机械行": nonempty, "普通回程": ordinary_returns, "最后机械行纵坐标": last_data_y, "打印单行配置秒": config["print_line"], "理论秒": theory, "固定物理帧实测秒": measured, "事件轨迹实际墙钟微秒": int(last_event["ticks_usec"]) - int(first_event["ticks_usec"]), "快照": snapshot})


func _phase_seconds(phase: StringName, config: Dictionary) -> float:
	var keys: Dictionary = {&"first_descent": "first_descent", &"first_wait": "first_wait", &"first_left": "first_left", &"print_line": "print_line", &"return_left": "return_left", &"next_line": "next_line", &"center": "center_time", &"axis_reset": "reset_time"}
	return float(config[keys[phase]])


func _test_pending_and_snapshot() -> void:
	await _prepare()
	var definition: AutolysisQuestPrintDefinition = _definition(PackedStringArray(["original", "", "tail"]))
	check(machine.request_task_print(definition, player), "待打印任务受理")
	definition.data_lines = PackedStringArray(["changed"])
	check(machine.get_current_paper() == null, "受理不创建文件")
	player.focus_controller.state = AutolysisFocusController.FocusState.INACTIVE
	check(not machine.can_start_print(player) and not machine.try_start_print(player), "未聚焦查询和直接调用均拒绝")
	player.focus_controller.state = AutolysisFocusController.FocusState.FOCUSED
	check(machine.try_start_print(player), "回到对应聚焦可打印")
	player.focus_controller.state = AutolysisFocusController.FocusState.INACTIVE
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	check(machine.get_current_paper().item_instance.quest_paper_contents.get_data_lines() == PackedStringArray(["original", "", "tail"]), "共享定义变化不修改本次快照")
	check(not machine.can_release_completed_paper(player, machine.get_current_paper(), machine.get_print_serial(), machine.get_current_paper().item_instance), "退出聚焦继续打印但不能取纸")
	check(not machine.request_task_print(definition, player), "完成未取走不接收第二份")
	await _dispose()


func _test_pause_matrix() -> void:
	for tree_pause: bool in [false, true]:
		for phase: StringName in [&"first_descent", &"first_wait", &"first_left", &"print_line", &"return_left", &"next_line", &"center", &"axis_reset"]:
			await _prepare()
			_start(PackedStringArray(["a", "b"]))
			await _wait_phase(phase)
			if tree_pause:
				paused = true
			else:
				player.is_movement_paused = true
				player.dialogue_pause_changed.emit(true)
			await frames(1)
			var before: Dictionary = machine.get_print_snapshot()
			var before_axis: Vector3 = machine.horizontal_axis.position
			var before_head: Vector3 = machine.print_head.position
			var before_lines: PackedInt32Array = machine.get_current_paper().get_visible_data_line_indices()
			await frames(10)
			check(machine.horizontal_axis.position == before_axis and machine.print_head.position == before_head and machine.get_print_snapshot()["phase"] == before["phase"], "暂停冻结指定动作及位置")
			check(machine.get_current_paper().get_visible_data_line_indices() == before_lines and machine.state != AutolysisQuestMachine.PrintState.COMPLETE, "暂停不显示新行或伪报完成")
			check(not machine.can_start_print(player) and not machine.try_start_print(player), "暂停拒绝业务操作")
			paused = false
			player.is_movement_paused = false
			player.dialogue_pause_changed.emit(false)
			await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
			check(_event_count(machine.get_print_snapshot()["events"], &"line_revealed") == 2, "恢复续接并且行显示不重复")
			await _dispose()
	for completed: bool in [false, true]:
		await _prepare()
		machine.request_task_print(_definition(PackedStringArray(["a"])), player)
		if completed:
			machine.try_start_print(player)
			await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
		await frames(3)
		var index: int = 1 if completed else 0
		var material: StandardMaterial3D = (machine.get("_materials") as Array)[index]
		var audio: AudioStreamPlayer3D = machine.scanning_player if completed else machine.notice_player
		var original_stream: AudioStream = audio.stream
		var original_playback: AudioStreamPlayback = audio.get_stream_playback()
		var before_pause: Dictionary = _audio_sample(audio)
		player.is_showing_ui = true
		player.dialogue_pause_changed.emit(true)
		await frames(1)
		var energy: float = material.emission_energy_multiplier
		var pause_transition: Array[Dictionary] = await _wait_actual_audio_mixes(audio, 2)
		var audio_position: float = audio.get_playback_position()
		var stable_pause: Array[Dictionary] = await _wait_actual_audio_mixes(audio, 1)
		check(material.emission_energy_multiplier == energy, "真实界面暂停冻结提示灯相位")
		check(audio.stream_paused and audio.get_playback_position() == audio_position and audio.stream == original_stream and audio.get_stream_playback() == original_playback, "真实界面暂停在实际混音淡出后冻结同一播放位置及资源")
		player.is_showing_ui = false
		player.dialogue_pause_changed.emit(false)
		var resume_samples: Array[Dictionary] = await _wait_actual_audio_mixes(audio, 1)
		var blink_resumed: bool = false
		for sample: Dictionary in resume_samples:
			if sample["提示发光倍率"] != energy:
				blink_resumed = true
		check(blink_resumed, "提示恢复继续闪烁")
		check(audio.has_stream_playback() and not audio.stream_paused and audio.stream == original_stream and audio.get_stream_playback() == original_playback and audio.get_playback_position() != audio_position, "提示音恢复续接同一播放来源与非零进度")
		scenarios.append({"名称": "实际混音暂停与恢复", "完成提示": completed, "驱动": AudioServer.get_driver_name(), "采样率": AudioServer.get_mix_rate(), "暂停前": before_pause, "暂停过渡样本": pause_transition, "稳定暂停基准位置": audio_position, "稳定暂停样本": stable_pause, "恢复样本": resume_samples})
		await _dispose()


func _test_audio_start_pause_boundary() -> void:
	for completed: bool in [false, true]:
		await _prepare()
		machine.request_task_print(_definition(PackedStringArray(["a"])), player)
		if completed:
			machine.try_start_print(player)
			await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
		var audio: AudioStreamPlayer3D = machine.scanning_player if completed else machine.notice_player
		var stream: AudioStream = audio.stream
		player.is_showing_ui = true
		await frames(12)
		var playback: AudioStreamPlayback = audio.get_stream_playback()
		check(not playback.is_playing() and audio.get_playback_position() == 0.0 and audio.stream == stream and not audio.can_process(), "音源请求后尚未服务器登记时暂停不启动实际播放")
		scenarios.append({"名称": "提示初始请求暂停边界", "完成提示": completed, "暂停中音源公开播放请求": audio.playing, "暂停中底层播放已开始": playback.is_playing(), "暂停中播放位置": audio.get_playback_position(), "暂停中音源可处理": audio.can_process()})
		player.is_showing_ui = false
		await frames(4)
		check(audio.playing and audio.has_stream_playback() and playback.is_playing() and audio.stream == stream, "初始请求暂停恢复后启动同一循环音流")
		await _dispose()


func _test_completion_pause_boundary() -> void:
	await _prepare()
	var paused_once: Array[bool] = [false]
	machine.action_finished.connect(func(_serial: int, phase: StringName, _line: int) -> void:
		if phase == &"print_line" and not paused_once[0]:
			paused_once[0] = true
			player.is_showing_ui = true
	)
	_start(PackedStringArray(["a"]))
	for index: int in 100:
		if paused_once[0]:
			break
		await physics_frame
	await frames(10)
	check(machine.get_current_paper().get_visible_data_line_indices().is_empty(), "自然完成观察同帧暂停暂存完成且不显示新行")
	check(machine.get_print_snapshot()["finished_pending"], "自然完成暂停保留本次完成身份")
	player.is_showing_ui = false
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	check(_event_count(machine.get_print_snapshot()["events"], &"action_finished", &"print_line") == 1 and _event_count(machine.get_print_snapshot()["events"], &"line_revealed") == 1, "恢复完成边界只发布一次自然完成与一次行显示")
	await _dispose()


func _test_cancel_matrix() -> void:
	for phase: StringName in [&"first_descent", &"first_wait", &"first_left", &"print_line", &"return_left", &"next_line", &"center", &"axis_reset"]:
		await _prepare()
		var counter: EventCounter = EventCounter.new()
		world.add_child(counter)
		machine.print_completed.connect(counter.on_completed)
		machine.print_cancelled.connect(counter.on_cancelled)
		_start(PackedStringArray(["a", "b"]))
		await _wait_phase(phase)
		var serial: int = machine.get_print_serial()
		check(machine.cancel_print(serial, "专项显式取消"), "指定阶段取消受理")
		check(machine.get_print_serial() != serial and machine.get_current_paper() == null, "取消立即失效旧序号与未完成来源")
		check(not machine.cancel_print(serial, "旧取消"), "旧序号取消拒绝")
		await _wait_state(AutolysisQuestMachine.PrintState.IDLE)
		check(counter.completed == 0 and counter.cancelled == 1, "取消恢复不发布自然完成且只取消一次")
		check(machine.horizontal_axis.position == machine.axis_reset_position and machine.print_head.position == machine.head_center_position, "取消按当前配置先归中后复位")
		_start(PackedStringArray(["next"]))
		await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
		check(counter.completed == 1, "取消后下一轮可正常自然完成")
		await _dispose()


func _test_dependency_release_and_rebind() -> void:
	await _prepare()
	_start(PackedStringArray(["a", "b"]))
	await _wait_phase(&"print_line")
	var replacement_head: Node3D = Node3D.new()
	machine.horizontal_axis.add_child(replacement_head)
	machine.print_head = replacement_head
	await _wait_state(AutolysisQuestMachine.PrintState.IDLE)
	check(_event_count(machine.get_print_snapshot()["events"], &"print_completed") == 0, "运行中有效目标引用替换不冒充原目标完成")
	await _dispose()
	for release_paper: bool in [false, true]:
		await _prepare()
		_start(PackedStringArray(["a", "b"]))
		await _wait_phase(&"print_line")
		if release_paper:
			machine.get_current_paper().queue_free()
			await _wait_state(AutolysisQuestMachine.PrintState.IDLE)
		else:
			machine.print_head.queue_free()
			await _wait_state(AutolysisQuestMachine.PrintState.WAITING_RECOVERY)
			check(not machine.request_task_print(_definition(PackedStringArray(["x"])), player), "目标失效待恢复不接受新任务")
			var replacement: Node3D = Node3D.new()
			machine.add_child(replacement)
			check(machine.rebind_print_targets(machine.horizontal_axis, replacement), "显式有效重绑恢复初态")
		check(_event_count(machine.get_print_snapshot()["events"], &"print_completed") == 0, "来源失效不冒充完成")
		_start(PackedStringArray(["next"]))
		await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
		await _dispose()
	await _prepare()
	_start(PackedStringArray(["a"]))
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	machine.get_current_paper().queue_free()
	await _wait_state(AutolysisQuestMachine.PrintState.IDLE)
	check(not machine.last_failure_reason.is_empty() and _event_count(machine.get_print_snapshot()["events"], &"paper_taken") == 0, "完成纸张外部释放记录来源丢失且不冒充取走")
	await _dispose()


func _test_optional_effects_and_instances() -> void:
	await _prepare()
	var other: AutolysisQuestMachine = MACHINE_SCENE.instantiate() as AutolysisQuestMachine
	_shorten(other, 0.05)
	world.add_child(other)
	other.request_task_print(_definition(PackedStringArray(["other"])), player)
	machine.request_task_print(_definition(PackedStringArray(["a"])), player)
	var first: StandardMaterial3D = machine.pending_indicator.material_override as StandardMaterial3D
	var second: StandardMaterial3D = other.pending_indicator.material_override as StandardMaterial3D
	check(first != second and first != machine.indicator_pending_material, "两实例发光材质各自复制")
	check(machine.notice_player.stream != other.notice_player.stream and machine.notice_player.stream != machine.notice_stream, "两实例循环音流各自复制")
	var loop_stream: AudioStreamWAV = machine.notice_player.stream as AudioStreamWAV
	check(loop_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop_stream.loop_begin == 0 and loop_stream.loop_end == int(round(loop_stream.get_length() * loop_stream.mix_rate)), "正向循环覆盖真实完整采样帧")
	check(machine.notice_stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "不修改导入共享音流循环")
	await frames(15)
	check(absf(first.emission_energy_multiplier - 1.0) < 0.15, "提示从零线性升亮半程")
	machine.pending_indicator.material_override = machine.indicator_default_material
	machine.scanning_player.queue_free()
	machine.completed_indicator.queue_free()
	machine.animation_source.stop()
	machine.animation_source.queue_free()
	await frames(2)
	check(machine.try_start_print(player), "灯音按压来源失效不阻断正式开始")
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	check(machine.get_current_paper().is_print_complete(), "可选表现缺失仍自然打印完成")
	check(machine.can_release_completed_paper(player, machine.get_current_paper(), machine.get_print_serial(), machine.get_current_paper().item_instance), "可选表现缺失不锁取纸")
	await _dispose()


func _test_configured_variants() -> void:
	await _prepare()
	machine.first_line_position = Vector3(0.01, -0.03, 0.02)
	machine.minimum_line_y = -0.19
	machine.line_spacing = 0.04
	machine.head_left_position = Vector3(-0.09, 0.02, 0.01)
	machine.head_right_position = Vector3(0.30, 0.02, 0.01)
	machine.head_center_position = Vector3(0.12, 0.02, 0.01)
	machine.axis_reset_position = Vector3(0.01, 0.01, 0.02)
	machine.scale = Vector3(1.2, 0.8, 1.3)
	machine.rotation.y = 0.6
	machine.horizontal_axis.name = "RenamedAxis"
	machine.print_head.name = "RenamedHead"
	_shorten(machine, 0.04)
	_start(_lines(25))
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	_validate_trace("合法位置时长父级变换改名容量配置", _lines(25))
	check(machine.get_print_snapshot()["mechanical_count"] == 5, "合法间距与最低位置变更重新核算容量")
	await _dispose()
	await _prepare()
	_shorten(machine, 0.0)
	_start(PackedStringArray(["a", "", "b"]))
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	_validate_trace("合法零秒有限动作仍自然完成", PackedStringArray(["a", "", "b"]))
	await _dispose()


func _test_press_event_restore() -> void:
	await _prepare()
	var event: MethodEvent = MethodEvent.new()
	event.name = "OptionalEvent"
	machine.add_child(event)
	var library: AnimationLibrary = machine.animation_source.get_animation_library(&"").duplicate() as AnimationLibrary
	machine.animation_source.remove_animation_library(&"")
	machine.animation_source.add_animation_library(&"", library)
	var animation: Animation = machine.animation_source.get_animation(machine.print_button.animation_name).duplicate() as Animation
	var method_track: int = animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(method_track, NodePath("OptionalEvent"))
	animation.track_insert_key(method_track, 0.0, {"method": &"record", "args": []})
	library.remove_animation(machine.print_button.animation_name)
	library.add_animation(machine.print_button.animation_name, animation)
	check(machine.print_button.rebind_press_animation(machine.animation_source), "按压多轨配置可绑定")
	check(event.calls == 0, "初始化定位不重放方法事件")
	_start(PackedStringArray(["a"]))
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	check(event.calls == 1, "正常按压事件执行一次并与打印并行")
	check(machine.print_button.rebind_press_animation(machine.animation_source) and event.calls == 1, "恢复初始姿态不重复提交事件")
	await _dispose()


func _test_active_configuration_snapshot() -> void:
	await _prepare()
	var data: PackedStringArray = PackedStringArray(["a", "b"])
	_start(data)
	await _wait_phase(&"print_line")
	var accepted_config: Dictionary = machine.get_print_snapshot()["config"]
	# 下一次的创建场景及合法表现配置变化，不会撤销这件现有纸张的必要依赖。
	machine.paper_scene = null
	_shorten(machine, 0.4)
	machine.first_line_position = Vector3(0.01, -0.4, 0.02)
	machine.head_left_position = Vector3(-0.12, 0.02, 0.01)
	machine.head_right_position = Vector3(0.31, 0.02, 0.01)
	machine.head_center_position = Vector3(0.14, 0.02, 0.01)
	machine.axis_reset_position = Vector3(0.01, 0.02, 0.03)
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	check(machine.get_print_snapshot()["config"] == accepted_config, "打印中后续场景及表现配置变化保持本次配置快照")
	_validate_trace("本轮快照与下一轮配置相互独立", data)
	check(machine.can_release_completed_paper(player, machine.get_current_paper(), machine.get_print_serial(), machine.get_current_paper().item_instance), "后续创建场景失效不限制当前完成实例获取")
	await _dispose()


func _test_start_failure_and_external_stop() -> void:
	await _prepare()
	var original_scene: PackedScene = machine.paper_scene
	var wrong_scene: PackedScene = PackedScene.new()
	var wrong_root: Node3D = Node3D.new()
	wrong_scene.pack(wrong_root)
	wrong_root.free()
	machine.paper_scene = wrong_scene
	check(machine.request_task_print(_definition(PackedStringArray(["a"])), player), "纸张创建故障前待打印受理")
	check(not machine.try_start_print(player) and machine.state == AutolysisQuestMachine.PrintState.PENDING and machine.get_current_paper() == null, "创建失败不消耗待打印快照")
	machine.paper_scene = original_scene
	check(machine.try_start_print(player), "修复场景来源后同一待打印可再次开始")
	await _wait_phase(&"print_line")
	var tween: Tween = machine.get("_active_tween") as Tween
	tween.kill()
	await _wait_state(AutolysisQuestMachine.PrintState.IDLE)
	check(_event_count(machine.get_print_snapshot()["events"], &"print_completed") == 0, "外部终止有限补间不视为自然完成")
	await _dispose()


func _test_item_contents_replacement() -> void:
	for completed: bool in [false, true]:
		for group_only: bool in [false, true]:
			await _prepare()
			_start(PackedStringArray(["a", "b"]))
			if completed:
				await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
			else:
				await _wait_phase(&"print_line")
			var source: AutolysisQuestPaper = machine.get_current_paper()
			var instance: AutolysisItemInstance = source.item_instance
			var serial: int = machine.get_print_serial()
			var definition: AutolysisQuestPrintDefinition = _definition(PackedStringArray(["a", "b"]) if group_only else PackedStringArray(["replacement"]))
			if group_only:
				definition.group_gap_before_lines = PackedInt32Array([1])
			check(instance.set_quest_paper_contents(definition.create_contents(), false), "故障注入同件实例上的有效全文或分组替换")
			check(not machine.is_current_paper(source, serial, instance), "同件资源身份不掩盖绑定内容来源变更")
			check(not machine.can_release_completed_paper(player, source, serial, instance) and machine.begin_paper_take(player, source, serial, instance) == 0, "有效内容替换即时拒绝查询和正式取纸锁")
			await _wait_state(AutolysisQuestMachine.PrintState.IDLE)
			check(_event_count(machine.get_print_snapshot()["events"], &"print_completed") == (1 if completed else 0), "内容替换不追加正常完成并清理匹配来源")
			check(_event_count(machine.get_print_snapshot()["events"], &"paper_taken") == 0, "内容替换不能冒充获取成功")
			await _dispose()


func _event_count(events: Array, event: StringName, phase: StringName = &"") -> int:
	var count: int = 0
	for entry: Dictionary in events:
		if entry["event"] == event and (phase.is_empty() or entry["phase"] == phase):
			count += 1
	return count


func _wait_state(expected: AutolysisQuestMachine.PrintState, limit: int = 1000) -> void:
	for index: int in limit:
		if machine.state == expected:
			return
		await physics_frame
	check(false, "等待期望设备阶段超时")


func _wait_phase(expected: StringName, limit: int = 1000) -> void:
	for index: int in limit:
		if machine.get_print_snapshot()["phase"] == expected:
			return
		await physics_frame
	check(false, "等待指定自然动作超时")


func _lines(count: int) -> PackedStringArray:
	var result: PackedStringArray = []
	for index: int in count:
		result.append("数据行%d" % index)
	return result


func _blank_lines(count: int) -> PackedStringArray:
	var result: PackedStringArray = []
	result.resize(count)
	return result


func _dispose() -> void:
	paused = false
	if is_instance_valid(world):
		world.queue_free()
	await frames(2)


func frames(count: int) -> void:
	for index: int in count:
		await physics_frame


func check(passed: bool, description: String) -> void:
	assertion_count += 1
	records.append({"通过": passed, "说明": description})
	if passed:
		print("通过：", description)
	else:
		failures += 1
		push_error("失败：" + description)
