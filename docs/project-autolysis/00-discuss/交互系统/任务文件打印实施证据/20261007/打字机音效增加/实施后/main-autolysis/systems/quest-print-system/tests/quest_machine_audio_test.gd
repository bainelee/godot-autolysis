extends "res://main-autolysis/systems/quest-print-system/tests/quest_machine_behavior_test.gd"
## 使用真实场景、真实随机源、真实音频自然完成和物理补间；不注入完成信号。


func run_checks() -> void:
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/任务文件打印实施证据/20261007/逐行打印音效")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	check(DisplayServer.get_name() == "headless", "打印音效专项只使用无图形后端")
	await _test_six_actual_choices()
	await _test_silence_pause()
	await _test_typing_pause()
	await _test_audio_lifecycle()
	await _test_cancel_audio()
	await _test_optional_audio_release()
	await _test_audio_instances_and_settings()
	await _test_audio_assignment_reentry()
	await _wait_actual_audio_mixes(null, 2)
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("打印音效专项报告.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "参数": OS.get_cmdline_args(), "断言数": assertion_count, "失败数": failures, "断言": records, "场景": scenarios, "官方机制来源": ["https://docs.godotengine.org/en/4.6/classes/class_audiostreamplayer3d.html", "https://docs.godotengine.org/en/4.6/classes/class_randomnumbergenerator.html", "https://docs.godotengine.org/en/4.6/classes/class_tween.html"], "输入方式": "无图形正式场景及直接音效接口；不启动图形窗口，不注入系统指针，不伪造完成信号"}, "\t"))
	report.close()
	print("打印音效专项断言数：", assertion_count, "；失败数：", failures)
	quit(0 if failures == 0 else 1)


func _audio() -> AutolysisQuestPrintAudio:
	return machine.print_audio


func _prepare_pending_audio() -> void:
	await _prepare()
	check(is_instance_valid(_audio()), "真实通知中心场景配置独立打印音效控制器")
	check(machine.request_task_print(_definition(PackedStringArray(["音效输入"])), player), "正式待打印事件绑定真实玩家暂停来源")


func _seed_choice(audio: AutolysisQuestPrintAudio, desired: int) -> int:
	var probe: RandomNumberGenerator = RandomNumberGenerator.new()
	for candidate: int in 1000:
		probe.seed = candidate
		if probe.randi_range(0, 5) == desired:
			var source: RandomNumberGenerator = audio.get("_random") as RandomNumberGenerator
			source.seed = candidate
			return candidate
	check(false, "实际随机数生成器未找到指定六选项的可重现种子")
	return -1


func _typing_events(audio: AutolysisQuestPrintAudio) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in audio.get_audio_snapshot()["events"]:
		if entry["event"] == &"typing_choice":
			result.append(entry)
	return result


func _wait_audio_condition(predicate: Callable, description: String, timeout_us: int = 3000000) -> void:
	var deadline: int = Time.get_ticks_usec() + timeout_us
	while Time.get_ticks_usec() < deadline:
		if predicate.call():
			return
		# 给实际混音线程调度机会；条件取自真实完成或底层播放，而不是此一毫秒。
		OS.delay_msec(1)
		await process_frame
	check(false, description)


func _test_six_actual_choices() -> void:
	for desired: int in 6:
		await _prepare_pending_audio()
		var audio: AutolysisQuestPrintAudio = _audio()
		var seed_value: int = _seed_choice(audio, desired)
		var completed: Array[int] = [0]
		audio.typing_player.finished.connect(func() -> void: completed[0] += 1)
		audio.begin_action(&"print_line")
		var choices: Array[Dictionary] = _typing_events(audio)
		check(choices.size() == 1 and int(choices[0]["choice"]) == desired, "实际随机源种子覆盖六选项中的第%d项" % desired)
		if desired < 4:
			var source: AudioStreamWAV = audio.typing_streams[desired]
			var stream: AudioStreamWAV = audio.typing_player.stream as AudioStreamWAV
			check(stream != source and stream.data == source.data and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "敲击%d播放实际指定资源的独立非循环副本" % desired)
			check(audio.typing_player.playing and source.loop_mode == AudioStreamWAV.LOOP_DISABLED, "敲击%d发起真实三维播放且不修改共享资源" % desired)
			await _wait_audio_condition(func() -> bool: return _typing_events(audio).size() >= 2, "敲击资源自然完成后未继续六选项随机轮转")
			check(completed[0] == 1, "敲击%d只在真实音源自然完成一次之后选择下一项" % desired)
		else:
			var expected: float = 0.25 if desired == 4 else 0.4
			check(not audio.typing_player.playing and float(choices[0]["seconds"]) == expected, "静音%d不请求声音并采用明确停顿时长" % desired)
			await _wait_audio_condition(func() -> bool: return _typing_events(audio).size() >= 2, "静音物理补间自然完成后未继续随机轮转")
			check(completed[0] == 0, "静音停顿通过真实有限补间继续且不伪造音频完成")
			choices = _typing_events(audio)
			var measured: float = float(int(choices[1]["physics_frame"]) - int(choices[0]["physics_frame"])) / FPS
			check(absf(measured - expected) <= 2.1 / FPS, "静音%d实际物理帧停顿符合配置" % desired)
		scenarios.append({"名称": "六项真实随机选择", "指定选择": desired, "实际种子": seed_value, "实际音频完成数": completed[0], "选择事件": _typing_events(audio), "底层驱动": AudioServer.get_driver_name(), "音频采样率": AudioServer.get_mix_rate()})
		audio.stop_all()
		var stopped_count: int = _typing_events(audio).size()
		await _wait_actual_audio_mixes(null, 2)
		check(not audio.get_audio_snapshot()["typing_active"] and not audio.typing_player.playing and _typing_events(audio).size() == stopped_count, "停止敲击后真实音频或静音旧完成不能继续选择")
		await _dispose()


func _test_silence_pause() -> void:
	for tree_pause: bool in [false, true]:
		for desired: int in [4, 5]:
			await _prepare_pending_audio()
			var audio: AutolysisQuestPrintAudio = _audio()
			_seed_choice(audio, desired)
			audio.begin_action(&"print_line")
			await frames(3)
			_set_audio_test_pause(tree_pause, true)
			await frames(1)
			var before: Dictionary = audio.get_audio_snapshot()
			var pause_start: int = Engine.get_physics_frames()
			await frames(20)
			var after: Dictionary = audio.get_audio_snapshot()
			check(before["paused"] and after["paused"] and float(before["gap_remaining"]) > 0.0, "静音停顿收到真实界面或场景树暂停")
			check(after["gap_remaining"] == before["gap_remaining"] and _typing_events(audio).size() == 1, "静音暂停保持准确剩余时长且不抽取新项")
			_set_audio_test_pause(tree_pause, false)
			var paused_frames: int = Engine.get_physics_frames() - pause_start
			await _wait_audio_condition(func() -> bool: return _typing_events(audio).size() >= 2, "静音恢复后未自然续接剩余停顿")
			var choices: Array[Dictionary] = _typing_events(audio)
			var measured: float = float(int(choices[1]["physics_frame"]) - int(choices[0]["physics_frame"]) - paused_frames) / FPS
			var expected: float = 0.25 if desired == 4 else 0.4
			check(absf(measured - expected) <= 2.1 / FPS, "静音恢复只完成剩余停顿且不重新开始完整时长")
			scenarios.append({"名称": "静音真实暂停恢复", "场景树暂停": tree_pause, "选择": desired, "暂停前": before, "暂停后": after, "扣除暂停物理帧": paused_frames, "有效停顿实测秒": measured, "选择事件": choices})
			audio.stop_all()
			await _dispose()


func _set_audio_test_pause(tree_pause: bool, enabled: bool) -> void:
	if tree_pause:
		paused = enabled
	else:
		player.is_showing_ui = enabled
		player.dialogue_pause_changed.emit(enabled)


func _test_typing_pause() -> void:
	await _prepare_pending_audio()
	var audio: AutolysisQuestPrintAudio = _audio()
	# 实际可编辑音高降低播放速度，只给异步混音采样提供足够自然长度。
	audio.typing_player.pitch_scale = 0.2
	_seed_choice(audio, 0)
	audio.begin_action(&"print_line")
	await _wait_audio_condition(func() -> bool: return audio.typing_player.has_stream_playback() and audio.typing_player.get_stream_playback().is_playing(), "敲击声音未实际登记到底层音频服务器")
	var stream: AudioStream = audio.typing_player.stream
	var playback: AudioStreamPlayback = audio.typing_player.get_stream_playback()
	_set_audio_test_pause(false, true)
	await frames(1)
	await _wait_actual_audio_mixes(null, 2)
	var stable_position: float = audio.typing_player.get_playback_position()
	await _wait_actual_audio_mixes(null, 1)
	check(audio.typing_player.stream_paused and audio.typing_player.get_playback_position() == stable_position and audio.typing_player.stream == stream and audio.typing_player.get_stream_playback() == playback, "真实界面暂停跨实际混音提交后冻结同一敲击资源与播放对象")
	check(_typing_events(audio).size() == 1, "敲击声音暂停不提前进入下一次随机选择")
	_set_audio_test_pause(false, false)
	await _wait_actual_audio_mixes(null, 1)
	check(not audio.typing_player.stream_paused and audio.typing_player.get_stream_playback() == playback and audio.typing_player.get_playback_position() != stable_position, "敲击恢复续接原播放对象及进度")
	scenarios.append({"名称": "敲击真实混音暂停", "稳定暂停位置": stable_position, "恢复位置": audio.typing_player.get_playback_position(), "可编辑音高": audio.typing_player.pitch_scale, "音效快照": audio.get_audio_snapshot()})
	audio.stop_all()
	await _dispose()


func _test_audio_lifecycle() -> void:
	for data: PackedStringArray in [PackedStringArray(["a"]), PackedStringArray(["", "a", "", "b", ""]), PackedStringArray(["", "", ""]), PackedStringArray([" ", "\t", ""]), _lines(25)]:
		await _prepare()
		_start(data)
		await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
		var audio: AutolysisQuestPrintAudio = _audio()
		var events: Array = audio.get_audio_snapshot()["events"]
		var mechanical: Array = machine.get_print_snapshot()["events"]
		var printed: int = _event_count(mechanical, &"action_started", &"print_line")
		check(_event_count(events, &"ding") == printed and _event_count(events, &"typing_stopped") == printed, "仅每个真实非空机械行自然完成鸣铃一次并停止该行敲击")
		check(_event_count(events, &"head_return") == _event_count(mechanical, &"action_started", &"first_left") + _event_count(mechanical, &"action_started", &"return_left") + _event_count(mechanical, &"action_started", &"center"), "首次左移、逐行回左及最终回中均播放一次打印头复位声")
		check(_event_count(events, &"axis_return_started") == 1 and _event_count(events, &"axis_return_stopped") == 1 and not audio.axis_return_player.playing, "最终横轴真实复位开始播放且自然复位完成立即停止")
		check(not audio.get_audio_snapshot()["typing_active"] and not audio.typing_player.playing, "完成待取阶段不继续逐行敲击")
		if printed == 0:
			check(_typing_events(audio).is_empty() and _event_count(events, &"ding") == 0, "全空行只推进机械位置且不敲击或鸣铃")
		scenarios.append({"名称": "正式打印音效生命周期", "实际数据": data, "机械非空行数": printed, "机械快照": machine.get_print_snapshot(), "音效快照": audio.get_audio_snapshot()})
		await _dispose()
	await _prepare()
	machine.reset_seconds = 2.0
	_start(PackedStringArray(["a"]))
	await _wait_phase(&"axis_reset")
	var audio: AutolysisQuestPrintAudio = _audio()
	var original: AudioStreamWAV = audio.axis_return_stream
	var loop: AudioStreamWAV = audio.axis_return_player.stream as AudioStreamWAV
	check(loop != original and loop.data == original.data and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.loop_begin == 0 and loop.loop_end == int(round(loop.get_length() * loop.mix_rate)), "横轴复位采用独立完整采样循环以覆盖可编辑复位时长")
	check(original.loop_mode == AudioStreamWAV.LOOP_DISABLED, "横轴循环不修改共享导入音频资源")
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	check(not audio.axis_return_player.playing, "延长实际横轴复位后仍由自然完成停止音效")
	await _dispose()


func _test_cancel_audio() -> void:
	for phase: StringName in [&"first_descent", &"first_wait", &"first_left", &"print_line", &"return_left", &"next_line", &"center", &"axis_reset"]:
		await _prepare()
		_start(PackedStringArray(["a", "b"]))
		await _wait_phase(phase)
		var audio: AutolysisQuestPrintAudio = _audio()
		check(machine.cancel_print(machine.get_print_serial(), "打印音效专项取消"), "指定实际动作阶段受理取消")
		check(not audio.get_audio_snapshot()["typing_active"] and not audio.typing_player.playing and not audio.ding_player.playing and not audio.axis_return_player.playing, "取消立即撤销敲击、行铃与横轴旧声音")
		await _wait_state(AutolysisQuestMachine.PrintState.IDLE)
		var events: Array = audio.get_audio_snapshot()["events"]
		check(_event_count(events, &"head_return", &"cancel_center") == 1, "取消恢复真实回中动作播放一次打印头复位声音")
		check(_event_count(events, &"axis_return_started") == (1 if phase == &"axis_reset" else 0), "取消轴恢复不冒充正常完成后的横轴复位音效")
		audio.stop_all()
		var choice_count: int = _typing_events(audio).size()
		await _wait_actual_audio_mixes(null, 2)
		check(_typing_events(audio).size() == choice_count and _players_stopped(audio), "取消清理后旧自然音频与静音回调不能重启任何声音")
		var before_rebind: int = audio.get_audio_snapshot()["events"].size()
		check(machine.rebind_print_targets(machine.horizontal_axis, machine.print_head), "空闲显式目标重新绑定成功")
		check(audio.get_audio_snapshot()["events"].size() == before_rebind, "显式位置恢复不重放敲击、行铃或机械回位声音")
		_start(PackedStringArray(["下一行"]))
		await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
		check(_event_count(audio.get_audio_snapshot()["events"], &"ding") == 1, "取消后下一份真实打印只保留本次一行铃声")
		await _dispose()


func _players_stopped(audio: AutolysisQuestPrintAudio) -> bool:
	for candidate: Variant in [audio.typing_player, audio.ding_player, audio.head_return_player, audio.axis_return_player]:
		if is_instance_valid(candidate) and candidate.playing:
			return false
	return true


func _test_optional_audio_release() -> void:
	for property: StringName in [&"typing_player", &"ding_player", &"head_return_player", &"axis_return_player", &"print_audio"]:
		await _prepare()
		var candidate: Node = machine.print_audio if property == &"print_audio" else _audio().get(property) as Node
		candidate.free()
		_start(PackedStringArray(["a", "", "b"]))
		await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
		check(machine.get_current_paper().is_print_complete() and machine.can_release_completed_paper(player, machine.get_current_paper(), machine.get_print_serial(), machine.get_current_paper().item_instance), "可选打印声音立即释放仍自然完成且允许获取原纸张：" + str(property) + "（被释放音效引用）")
		await _dispose()
	await _prepare()
	_start(PackedStringArray(["a", "b"]))
	await _wait_phase(&"print_line")
	_audio().typing_player.free()
	await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
	check(machine.get_current_paper().is_print_complete(), "敲击进行中音源立即释放只停止对应表现")
	await _dispose()


func _settings(audio: AudioStreamPlayer3D) -> Dictionary:
	return {"音量": audio.volume_db, "音高": audio.pitch_scale, "总线": audio.bus, "局部变换": audio.transform, "单位距离": audio.unit_size, "最大距离": audio.max_distance, "最大音量": audio.max_db, "衰减方式": audio.attenuation_model, "声像强度": audio.panning_strength, "方向开关": audio.emission_angle_enabled, "方向角度": audio.emission_angle_degrees, "滤波频率": audio.attenuation_filter_cutoff_hz}


func _test_audio_instances_and_settings() -> void:
	await _prepare_pending_audio()
	var audio: AutolysisQuestPrintAudio = _audio()
	var other: AutolysisQuestMachine = MACHINE_SCENE.instantiate() as AutolysisQuestMachine
	world.add_child(other)
	var second: AutolysisQuestPrintAudio = other.print_audio
	check(audio != second and audio.get("_random") != second.get("_random"), "两个真实设备分别拥有音效控制器与随机源")
	var settings: Dictionary = {}
	var index: int = 0
	for sound: AudioStreamPlayer3D in [audio.typing_player, audio.ding_player, audio.head_return_player, audio.axis_return_player]:
		sound.volume_db = -17.0 - index
		sound.unit_size = 2.0 + index
		sound.max_distance = 12.0 + index
		sound.max_db = -3.0
		sound.panning_strength = 0.4
		sound.position = Vector3(0.03 * index, 0.02, 0.01)
		settings[sound.get_instance_id()] = _settings(sound)
		index += 1
	audio.begin_action(&"axis_reset")
	second.begin_action(&"axis_reset")
	check(audio.axis_return_player.stream != second.axis_return_player.stream, "两实例横轴循环使用各自音流副本")
	audio.stop_all()
	check(second.axis_return_player.playing and _event_count(second.get_audio_snapshot()["events"], &"axis_return_stopped") == 0, "停止一台设备不停止另一台真实横轴声音")
	_seed_choice(audio, 0)
	_seed_choice(second, 4)
	audio.begin_action(&"print_line")
	second.begin_action(&"print_line")
	check(audio.typing_player.playing and not second.typing_player.playing and int(second.get_audio_snapshot()["choice"]) == 4, "两实例六项抽取及敲击或静音状态互不覆盖")
	audio.finish_action(&"print_line")
	audio.begin_action(&"center")
	audio.begin_action(&"axis_reset")
	for sound: AudioStreamPlayer3D in [audio.typing_player, audio.ding_player, audio.head_return_player, audio.axis_return_player]:
		check(_settings(sound) == settings[sound.get_instance_id()], "真实播放保留三维音源可编辑音量、空间属性和局部偏移：" + str(sound.name) + "（声音节点）")
	check(audio.ding_player.stream != audio.ding_stream and (audio.ding_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED and (audio.head_return_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "行铃与打印头复位采用独立单次音流")
	scenarios.append({"名称": "两设备声音隔离与可编辑配置保持", "第一台": audio.get_audio_snapshot(), "第二台": second.get_audio_snapshot(), "实际可编辑配置": settings})
	audio.stop_all()
	second.stop_all()
	await _dispose()


func _test_audio_assignment_reentry() -> void:
	for property: StringName in [&"typing_player", &"head_return_player", &"ding_player", &"axis_return_player"]:
		await _check_audio_assignment_reentry(property)


func _check_audio_assignment_reentry(property: StringName) -> void:
	for release_controller: bool in [false, true]:
		await _prepare()
		var audio: AutolysisQuestPrintAudio = _audio()
		_seed_choice(audio, 0)
		var called: Array[bool] = [false]
		var source: AudioStreamPlayer3D = audio.get(property) as AudioStreamPlayer3D
		source.property_list_changed.connect(func() -> void:
			if called[0]:
				return
			called[0] = true
			if release_controller:
				audio.queue_free()
			else:
				machine.cancel_print(machine.get_print_serial(), "真实音流属性变更观察者取消")
		)
		_start(PackedStringArray(["a", "b"]))
		if release_controller:
			await _wait_state(AutolysisQuestMachine.PrintState.COMPLETE)
			check(called[0] and not is_instance_valid(audio) and machine.get_current_paper().is_print_complete(), "实际音流赋值通知同步请求释放控制器，帧末实际释放后打印仍自然完成")
			check(machine.can_release_completed_paper(player, machine.get_current_paper(), machine.get_print_serial(), machine.get_current_paper().item_instance), "观察请求释放可选音效控制器后保留当前完成纸张获取许可")
		else:
			await _wait_state(AutolysisQuestMachine.PrintState.IDLE)
			check(called[0] and machine.get_current_paper() == null and _event_count(machine.get_print_snapshot()["events"], &"print_completed") == 0, "实际音流赋值通知同步取消后清理旧来源且不伪报完成")
			check(machine.horizontal_axis.position == machine.axis_reset_position and machine.print_head.position == machine.head_center_position, "同步声音观察取消保留真实取消回中及横轴恢复动作")
			if property in [&"typing_player", &"head_return_player"]:
				check(_event_count(machine.get_print_snapshot()["events"], &"action_started", &"print_line") == 0, "同步音流赋值取消后不再发布旧打印行开始通知")
		scenarios.append({"名称": "真实音流赋值观察重入", "音源引用": str(property) + "（被测播放器引用）", "同步请求释放控制器": release_controller, "观察已调用": called[0], "机械快照": machine.get_print_snapshot()})
		await _dispose()
