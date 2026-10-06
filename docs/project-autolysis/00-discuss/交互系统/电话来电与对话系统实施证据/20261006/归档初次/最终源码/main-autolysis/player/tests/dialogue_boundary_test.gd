extends "res://main-autolysis/player/tests/dialogue_system_test.gd"
## 可调用边界与自然完成当帧暂停。改变观察接线次序有明确记录，不人工发完成信号。

var boundary_samples: Array[Dictionary] = []
var end_order: Array[Dictionary] = []
var intercept_fade: bool = false
var timing_measurements: Array[Dictionary] = []
var phase_meter: TimingMeter
var phase_starts: Dictionary = {}

class TimingMeter extends Node:
	var elapsed: float = 0.0
	var maximum_step: float = 0.0

	func _process(delta: float) -> void:
		elapsed += delta
		maximum_step = maxf(maximum_step, delta)


func _business_finished(token: int, dialogue_id: StringName, origin: Node) -> void:
	if is_instance_valid(phase_meter) and phase_starts.has("fade"):
		var measured: float = phase_meter.elapsed - float(phase_starts.fade)
		timing_measurements.append({"阶段": "最后渐隐", "实际处理秒": measured, "配置秒": 0.2, "最大单次处理秒": phase_meter.maximum_step, "墙钟微秒": Time.get_ticks_usec()})
		check(absf(measured - 0.2) <= phase_meter.maximum_step * 2.0, "最后渐隐实际处理时长符合零点二秒且误差限来自本次最大处理步长")
		phase_starts.clear()
	super._business_finished(token, dialogue_id, origin)


func _on_measured_stage(_token: int, stage: StringName, _index: int) -> void:
	if not is_instance_valid(phase_meter):
		return
	if stage == &"hold":
		phase_starts["hold"] = phase_meter.elapsed
	elif stage == &"fade":
		var measured: float = phase_meter.elapsed - float(phase_starts.hold)
		var expected: float = float(phase_starts.expected_hold)
		timing_measurements.append({"阶段": "句后等待", "实际处理秒": measured, "配置秒": expected, "最大单次处理秒": phase_meter.maximum_step, "墙钟微秒": Time.get_ticks_usec()})
		check(absf(measured - expected) <= phase_meter.maximum_step * 2.0, "句后等待实际处理时长符合本次配置快照且误差限来自本次最大处理步长")
		phase_starts["fade"] = phase_meter.elapsed


func _test_actual_phase_durations() -> void:
	phase_meter = TimingMeter.new()
	dialogue.get_node("Timing").add_child(phase_meter)
	dialogue.stage_changed.connect(_on_measured_stage)
	for seconds: float in [1.5, 0.27]:
		single.post_voice_hold_seconds = seconds
		phase_meter.maximum_step = 0.0
		phase_starts["expected_hold"] = seconds
		var prepared: Dictionary = _prepare(single)
		# 准备后改变配置，必须保留本次快照，并在下一会话采用新配置。
		single.post_voice_hold_seconds = 0.44
		var normal_before: int = normal_count
		check(prepared.ok and dialogue.start_prepared_dialogue(prepared.token), "可配置等待及快照时长测量开始真实语音")
		await wait_until(func() -> bool: return normal_count > normal_before, "等待与渐隐处理时长自然完成")
	single.post_voice_hold_seconds = 1.5
	dialogue.stage_changed.disconnect(_on_measured_stage)
	phase_meter.queue_free()
	phase_meter = null


func _menu() -> void:
	var event := InputEventAction.new()
	event.action = &"menu"
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = &"menu"
	Input.parse_input_event(release)
	Input.flush_buffered_events()


func _test_configuration_and_tiny_viewport() -> void:
	var subtitle: AutolysisDialogueSubtitle = dialogue.get_subtitle()
	for change: Array in [
		["subtitle_font_size", 0],
		["subtitle_max_width", NAN],
		["subtitle_single_line_height", INF],
		["subtitle_horizontal_padding", -1.0],
		["subtitle_inventory_gap", -1.0],
		["subtitle_screen_margin", -1.0],
	]:
		var original: Variant = subtitle.get(change[0])
		subtitle.set(change[0], change[1])
		var rejected: Dictionary = _prepare(single)
		check(not rejected.ok and not rejected.busy and not rejected.reason.is_empty(), "实际非法排版字段明确拒绝准备并有具体原因：" + String(change[0]) + "（测试字段）")
		subtitle.set(change[0], original)
	root.size = Vector2i(10, 70)
	await frames(3)
	var zero: AutolysisDialogueDefinition = single.duplicate()
	zero.post_voice_hold_seconds = 0.0
	var prepared: Dictionary = _prepare(zero)
	check(prepared.ok and dialogue.start_prepared_dialogue(prepared.token), "极窄实际视口仍允许有效配置播放而不以尺寸终止会话")
	boundary_samples.append(dialogue.get_session_snapshot())
	var normal_before: int = normal_count
	await wait_until(func() -> bool: return normal_count > normal_before, "极窄零等待真实语音与渐隐自然完成")
	check(normal_count == normal_before + 1, "极窄视口零等待也由真实语音和自然渐隐完成一次")
	root.size = Vector2i(1280, 720)
	await frames(3)


func _test_hold_and_fade_completion_pause() -> void:
	var hold: Timer = dialogue.get_node("Timing/Hold")
	# 先添加菜单观察，再由生产为当前句连接完成处理。
	hold.timeout.connect(_menu, CONNECT_ONE_SHOT)
	var prepared: Dictionary = _prepare(single)
	check(prepared.ok and dialogue.start_prepared_dialogue(prepared.token), "句后计时器自然到期当帧暂停用例开始真实播放")
	var normal_before: int = normal_count
	await wait_until(func() -> bool: return dialogue.get_session_snapshot().completion_pending == &"hold", "真实句后计时器自然到期保存待同步")
	var before: Dictionary = dialogue.get_session_snapshot()
	boundary_samples.append(before)
	check(player.is_movement_paused and before.stage == &"hold" and before.token == prepared.token and normal_count == normal_before, "真实句后到期当帧暂停保留原会话不提前渐隐或完成")
	await wait_seconds(0.25)
	check(dialogue.get_session_snapshot().completion_pending == &"hold", "暂停中句后自然到期待同步保留")
	_menu()
	await wait_until(func() -> bool: return normal_count > normal_before, "句后待同步恢复后原渐隐完成")
	check(normal_count == normal_before + 1, "句后自然到期待同步恢复后仅完成一次")
	intercept_fade = true
	dialogue.stage_changed.connect(_on_boundary_stage)
	var last: Dictionary = _prepare(single)
	check(last.ok and dialogue.start_prepared_dialogue(last.token), "最后渐隐自然完成当帧暂停用例开始真实播放")
	normal_before = normal_count
	await wait_until(func() -> bool: return dialogue.get_session_snapshot().completion_pending == &"fade", "最后渐隐原生自然完成保存待同步")
	var final: Dictionary = dialogue.get_session_snapshot()
	boundary_samples.append(final)
	check(player.is_movement_paused and final.stage == &"fade" and final.token == last.token and normal_count == normal_before, "最后渐隐自然完成当帧暂停不提交正常完成")
	check(final.subtitle.visible and is_zero_approx(final.subtitle_alpha), "已完成最后渐隐的字幕保留零透明度待同步而不重播")
	await wait_seconds(0.25)
	check(dialogue.get_session_snapshot().completion_pending == &"fade" and normal_count == normal_before, "最后自然渐隐完成待同步在暂停中不发布业务")
	_menu()
	await wait_until(func() -> bool: return normal_count > normal_before, "最后渐隐待同步恢复唯一完成")
	check(normal_count == normal_before + 1 and not dialogue.get_subtitle().get_layout_snapshot().visible, "恢复后只提交一次原正常完成并隐藏全部字幕")
	dialogue.stage_changed.disconnect(_on_boundary_stage)


func _on_boundary_stage(_token: int, stage: StringName, _index: int) -> void:
	if not intercept_fade or stage != &"fade":
		return
	intercept_fade = false
	var tween: Tween = dialogue.get("_fade_tween")
	var connections: Array = tween.finished.get_connections()
	for connection: Dictionary in connections:
		var callback: Callable = connection.callable
		tween.finished.disconnect(callback)
	# 原生补间仍自行推进并发自然完成。仅将菜单观察移到完成处理之前。
	tween.finished.connect(_menu, CONNECT_ONE_SHOT)
	for connection: Dictionary in connections:
		tween.finished.connect(connection.callable, connection.flags)
	end_order.append({"用途": "原生最后补间完成当帧前置菜单观察", "原连接数量": connections.size(), "人工完成信号": false, "播放令牌": dialogue.get_session_snapshot().token})


func _test_dependency_lifecycle() -> void:
	for dependency: String in ["source", "subtitle", "voice"]:
		if dependency != "source":
			world.queue_free()
			await frames(3)
			await setup_fixture()
		var prepared: Dictionary = _prepare(single)
		check(prepared.ok and dialogue.start_prepared_dialogue(prepared.token), dependency + "（依赖变体）开始真实会话")
		var normal_before: int = normal_count
		var abort_before: int = abort_count
		match dependency:
			"source": source.queue_free()
			"subtitle": dialogue.get_subtitle().queue_free()
			"voice": dialogue.get_node("Timing/Voice").queue_free()
		await frames(4)
		var snapshot: Dictionary = dialogue.get_session_snapshot()
		boundary_samples.append(snapshot)
		check(snapshot.token == 0 and abort_count == abort_before + 1 and normal_count == normal_before, dependency + "（依赖变体）释放只终止原会话一次并不发正常完成")
		check(not snapshot.last_result.reason.is_empty(), dependency + "（依赖变体）异常记录保留实际原因")
	world.queue_free()
	await frames(3)
	await setup_fixture()
	var display: Panel = dialogue.get_subtitle().get_node("Display")
	display.visibility_changed.connect(_cancel_on_visibility)
	var visibility_prepared: Dictionary = _prepare(single)
	var abort_before: int = abort_count
	check(visibility_prepared.ok, "字幕同步可见观察取消边界准备成功")
	dialogue.start_prepared_dialogue(visibility_prepared.token)
	await frames(3)
	check(dialogue.get_session_snapshot().token == 0 and abort_count == abort_before + 1, "字幕同步显示观察中取消不会启动旧语音且异常唯一")
	check(not dialogue.get_node("Timing/Voice").playing and not dialogue.get_subtitle().get_layout_snapshot().visible, "同步显示观察取消完成音频与字幕成对清理")


func _cancel_on_visibility() -> void:
	var subtitle: AutolysisDialogueSubtitle = dialogue.get_subtitle()
	if is_instance_valid(subtitle) and subtitle.get_node("Display").visible:
		dialogue.cancel_dialogue(dialogue.get_session_snapshot().token, "字幕显示观察同步取消")


func run_checks() -> void:
	check(DisplayServer.get_name() == "headless", "边界专项实际使用无图形后端")
	await setup_fixture()
	await _test_configuration_and_tiny_viewport()
	await _test_actual_phase_durations()
	await _test_hold_and_fade_completion_pause()
	await _test_dependency_lifecycle()
	var evidence_dir: String = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/电话来电与对话系统实施证据/20261006/专项验收/对话边界")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	var output := FileAccess.open(evidence_dir.path_join("对话依赖与自然完成当帧暂停.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "断言": checks, "边界采样": boundary_samples, "自然完成观察次序": end_order, "实际处理时长": timing_measurements, "失败数": failures}, "\t"))
	paused = false
	world.queue_free()
	await frames(3)
	quit(1 if failures > 0 else 0)
