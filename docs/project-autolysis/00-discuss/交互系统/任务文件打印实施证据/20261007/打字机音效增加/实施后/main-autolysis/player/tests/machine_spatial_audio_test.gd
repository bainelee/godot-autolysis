extends "res://main-autolysis/player/tests/telephone_call_test.gd"
## 正式设备空间音效、可编辑参数与实际听筒来源专项，仅无图形。

const QUEST_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/quest_machine_0.tscn")
const BEFORE_PHONE: PackedScene = preload("res://docs/project-autolysis/00-discuss/交互系统/任务文件打印实施证据/20261007/持有文字与空间音效修订/实施前/main-autolysis/scenes/prefabs/prefab_machines/machine_telephone_0.tscn")
const EDITABLE_PROPERTIES: Array[StringName] = [&"volume_db", &"pitch_scale", &"bus", &"unit_size", &"max_distance", &"max_db", &"panning_strength", &"attenuation_model", &"attenuation_filter_cutoff_hz", &"attenuation_filter_db", &"emission_angle_enabled", &"emission_angle_degrees", &"emission_angle_filter_attenuation_db", &"area_mask", &"transform"]
const TEST_BUS: StringName = &"空间音效验收"

var spatial_samples: Array[Dictionary] = []
var expected_settings: Dictionary = {}


func _handset_audio() -> AutolysisTelephoneAudioController:
	return phone.handset_audio as AutolysisTelephoneAudioController


func _all_phone_players() -> Array[AudioStreamPlayer3D]:
	return [_call().ring_player, _handset_audio().action_player, _handset_audio().receiver_player, _call().voice_player]


func _audit_scene_types(scene: PackedScene, expected_count: int) -> void:
	var count: int = 0
	var state: SceneState = scene.get_state()
	for index: int in state.get_node_count():
		var type_name: StringName = state.get_node_type(index)
		if type_name in [&"AudioStreamPlayer", &"AudioStreamPlayer2D", &"AudioStreamPlayer3D"]:
			count += 1
			check(type_name == &"AudioStreamPlayer3D", "机器场景实际音源均为三维：" + str(state.get_node_path(index)) + "（节点路径）")
	check(count == expected_count, "机器场景实际空间输出数量完整：" + str(expected_count))


func _settings(audio: AudioStreamPlayer3D) -> Dictionary:
	var result: Dictionary = {}
	for property: StringName in EDITABLE_PROPERTIES:
		result[property] = audio.get(property)
	return result


func _configure_variants() -> void:
	expected_settings.clear()
	_configure_audio_variants(_all_phone_players())


func _configure_audio_variants(players: Array[AudioStreamPlayer3D]) -> void:
	var index: int = 0
	for audio: AudioStreamPlayer3D in players:
		var editor_names: Array[StringName] = []
		for info: Dictionary in audio.get_property_list():
			if int(info.usage) & PROPERTY_USAGE_EDITOR:
				editor_names.append(info.name)
		for property: StringName in EDITABLE_PROPERTIES:
			var editor_available: bool = property in editor_names
			if property == &"transform":
				editor_available = &"position" in editor_names and &"rotation" in editor_names and &"scale" in editor_names
			check(editor_available, "空间参数确有编辑器入口：" + str(property) + "（原生音源属性）")
		audio.volume_db = -11.0 - index
		audio.pitch_scale = 1.2
		audio.bus = TEST_BUS
		audio.unit_size = 2.7
		audio.max_distance = 23.5
		audio.max_db = 1.0
		audio.panning_strength = 0.4
		audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		audio.attenuation_filter_cutoff_hz = 4200.0
		audio.attenuation_filter_db = -18.0
		audio.emission_angle_enabled = true
		audio.emission_angle_degrees = 67.0
		audio.emission_angle_filter_attenuation_db = -15.0
		audio.area_mask = 3
		audio.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)), Vector3(0.03 * (index + 1), 0.02, 0.01))
		expected_settings[audio.get_instance_id()] = _settings(audio)
		index += 1


func _assert_settings(label: String) -> void:
	for audio: AudioStreamPlayer3D in _all_phone_players():
		check(_settings(audio) == expected_settings[audio.get_instance_id()], label + "保留音源全部可编辑参数及局部偏移：" + str(audio.name) + "（音源节点）")


func _assert_source(label: String, held: bool) -> void:
	var anchor: Node3D = inventory.get_handset_display() if held else phone.handset_anchor
	check(_handset_audio().sound_origin.global_transform.is_equal_approx(anchor.global_transform), label + "声源定位父节点匹配当前真实听筒来源")
	for audio: AudioStreamPlayer3D in [_handset_audio().action_player, _handset_audio().receiver_player, _call().voice_player]:
		var expected: Transform3D = anchor.global_transform * audio.transform
		# 指定引擎的三维音源构造时禁用缩放，只正交化全局基，原点保留。
		if audio.is_scale_disabled():
			expected.basis = expected.basis.orthonormalized()
		check(audio.global_transform.is_equal_approx(expected), label + "空间音源在当前来源上保留自己的编辑器偏移：" + str(audio.name) + "（音源节点）")
	spatial_samples.append({"阶段": label, "持筒": held, "来源变换": str(anchor.global_transform), "声源父变换": str(_handset_audio().sound_origin.global_transform), "接收音源变换": str(_handset_audio().receiver_player.global_transform), "语音变换": str(_call().voice_player.global_transform)})


func _mixes(count: int) -> void:
	var observed: int = 0
	var previous: float = AudioServer.get_time_since_last_mix()
	var deadline: int = Time.get_ticks_usec() + 2000000
	while observed < count and Time.get_ticks_usec() < deadline:
		OS.delay_msec(1)
		await process_frame
		var current: float = AudioServer.get_time_since_last_mix()
		if current < previous:
			observed += 1
		previous = current
	check(observed == count, "探针观察指定数量的实际混音完成边界")


func _pause_output(audio: AudioStreamPlayer3D, label: String) -> void:
	await _mixes(1)
	var stream: AudioStream = audio.stream
	var playback: AudioStreamPlayback = audio.get_stream_playback()
	_menu()
	await frames(1)
	await _mixes(2)
	var position_value: float = audio.get_playback_position()
	await _mixes(1)
	check(audio.stream_paused and audio.get_playback_position() == position_value and audio.stream == stream and audio.get_stream_playback() == playback, label + "实际淡出提交后冻结同一播放对象和精确位置")
	_assert_settings(label + "暂停")
	_menu()
	await _mixes(1)
	check(not audio.stream_paused and audio.stream == stream and audio.get_stream_playback() == playback and audio.get_playback_position() != position_value, label + "恢复续接原空间播放对象")
	_assert_settings(label + "恢复")


func _test_receiver_and_actions() -> void:
	await _new_scene()
	await _enter()
	_configure_variants()
	_assert_source("挂机初态", false)
	await _take()
	if OS.get_cmdline_user_args().has("--audio-control-overwrite"):
		_handset_audio().receiver_player.volume_db = 0.0
	_assert_settings("取下与默认循环")
	_assert_source("取下完成", true)
	var receiver: AudioStreamPlayer3D = _handset_audio().receiver_player
	var copy: AudioStreamWAV = receiver.stream as AudioStreamWAV
	check(receiver.playing and copy.loop_mode == AudioStreamWAV.LOOP_FORWARD and copy.loop_begin == 0 and copy.loop_end == int(round(copy.get_length() * copy.mix_rate)), "默认接收声音保留独立完整正向循环")
	await _pause_output(receiver, "默认接收声音")
	await _exit_focus()
	var before_move: Vector3 = _handset_audio().sound_origin.global_position
	player.global_position += Vector3(0.15, 0.0, 0.12)
	await frames(2)
	check(_handset_audio().sound_origin.global_position != before_move, "普通持筒时玩家实际移动带动空间声音来源")
	_assert_source("持筒移动", true)
	_assert_settings("持筒移动")
	var session: int = inventory.get_handset_session_id()
	_handset_audio().begin_dialogue_answer(player, session)
	_handset_audio().play_remote_hang_up(player, session)
	_assert_settings("对方挂机单次声音")
	check((receiver.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "对方挂机声音仍为单次自然完成")
	await _wait_realtime(func() -> bool: return _handset_audio().get("_receiver_stage") == AutolysisTelephoneAudioController.ReceiverStage.BUSY, "对方挂机自然结束后空间忙音")
	_assert_settings("自然结束后的忙音")
	check((receiver.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "忙音仍为独立完整正向循环")
	await _pause_output(receiver, "忙音")
	await _enter()
	await _return()
	_assert_source("归还完成", false)
	_assert_settings("归还声音")
	check(not receiver.playing and _handset_audio().action_player.playing and (_handset_audio().action_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "归还停止接收循环并在挂机来源播放单次声音")


func _test_voice_binding() -> void:
	await _new_scene()
	await _enter()
	_configure_variants()
	var default_voice: AudioStreamPlayer = _dialogue().get_node("Timing/Voice")
	check(phone.request_call(single_definition, player), "正式来电受理空间语音任务")
	_assert_settings("来电铃声")
	await _pause_output(_call().ring_player, "机座铃声")
	await _take()
	await _wait_realtime(func() -> bool: return _dialogue().get_session_snapshot().stage == &"voice", "实际电话空间语音开始")
	check(_dialogue().get_voice_output() == _call().voice_player and _dialogue().get_session_snapshot().audio_spatial and _call().voice_player.playing and not default_voice.playing, "电话语音实际路由本电话三维输出且默认共享输出未播放")
	_assert_settings("电话语音开始")
	_assert_source("电话语音来源", true)
	await _pause_output(_call().voice_player, "电话语音")
	await _exit_focus()
	var before_move: Vector3 = _handset_audio().sound_origin.global_position
	player.global_position += Vector3(0.1, 0.0, 0.08)
	await frames(2)
	check(_handset_audio().sound_origin.global_position != before_move, "通话中普通持筒移动带动语音空间来源")
	_assert_source("通话持筒移动", true)
	_assert_settings("通话移动")
	_call().cancel_call("空间输出专项取消")
	check(not _call().voice_player.playing and _call().voice_player.stream == null and _dialogue().get_voice_output() == default_voice, "取消停止并清理原空间输出，会话释放后恢复共享默认输出")
	_assert_settings("取消清理")
	await _enter()
	await _return()
	var prepared: Dictionary = _dialogue().prepare_dialogue(single_definition, other_phone, _idle_finished, _idle_aborted)
	check(prepared.get("ok", false) and _dialogue().get_voice_output() == default_voice, "普通共享对白仍使用原默认输出")
	if prepared.get("ok", false):
		_dialogue().start_prepared_dialogue(prepared.token)
		check(default_voice.playing and not _call().voice_player.playing, "普通对白实际播放默认音源")
		_dialogue().cancel_dialogue(prepared.token, "默认输出对照清理")
	var foreign: Dictionary = _dialogue().prepare_dialogue(single_definition, phone, _idle_finished, _idle_aborted, other_phone.call_controller.voice_player)
	check(not foreign.get("ok", false) and _dialogue().get_voice_output() == default_voice, "另一电话的空间输出不能冒充当前来源")


func _idle_finished(_token: int, _id: StringName, _source: Node) -> void:
	pass


func _idle_aborted(_token: int, _id: StringName, _source: Node, _reason: String) -> void:
	pass


func _test_immediate_voice_release() -> void:
	await _new_scene()
	await _enter()
	check(phone.request_call(single_definition, player), "立即释放用例受理真实来电")
	await _take()
	await _wait_realtime(func() -> bool: return _dialogue().get_session_snapshot().stage == &"voice", "立即释放用例开始真实空间语音")
	var session: int = inventory.get_handset_session_id()
	_call().voice_player.free()
	var after_free: Dictionary = _dialogue().get_session_snapshot()
	check(not after_free.audio_spatial and after_free.audio_output_id == 0 and not after_free.audio_playing, "空间语音立即释放后同一同步调用可安全读取实际输出快照")
	await frames(3)
	check(_call_stage() == CallController.Stage.ABORTED and inventory.get_handset_session_id() == session and not phone.is_handset_return_blocked(player, session), "必要空间语音释放终止原通话，仍持有原听筒且解除匹配通话锁")
	await _return()


func _test_quest_configuration() -> void:
	await _new_scene()
	var machine: AutolysisQuestMachine = world.get_node("interaction_prefabs/machines/quest_machine_0") as AutolysisQuestMachine
	var players: Array[AudioStreamPlayer3D] = [machine.notice_player, machine.scanning_player]
	expected_settings.clear()
	_configure_audio_variants(players)
	var task: AutolysisQuestPrintDefinition = load("res://main-autolysis/systems/quest-print-system/quests/quest_test_0.tres")
	check(machine.request_task_print(task, player), "通知中心通过正式事件受理待打印任务")
	check(machine.notice_player.playing, "待打印提示实际请求三维播放")
	for audio: AudioStreamPlayer3D in players:
		check(_settings(audio) == expected_settings[audio.get_instance_id()], "通知中心待打印保留三维音源可编辑参数")
	check(machine.root_interaction.try_interact(player, AutolysisInteractionComponent.InteractionMode.FOCUS), "通过正式根入口进入通知中心聚焦")
	await _wait(func() -> bool: return focus.state == AutolysisFocusController.FocusState.FOCUSED, "通知中心稳定聚焦")
	check(machine.print_button.print_interaction.try_interact(player), "通过正式打印按钮开始通知中心任务")
	for index: int in 6000:
		if machine.state == AutolysisQuestMachine.PrintState.COMPLETE:
			break
		await frames(1)
	check(machine.state == AutolysisQuestMachine.PrintState.COMPLETE and machine.scanning_player.playing and not machine.notice_player.playing, "通知中心按正式自然完成链切换三维完成提示")
	for audio: AudioStreamPlayer3D in players:
		check(_settings(audio) == expected_settings[audio.get_instance_id()], "通知中心完成提示保留全部音源可编辑参数及局部偏移")
	var stream: AudioStream = machine.scanning_player.stream
	await _mixes(1)
	var playback: AudioStreamPlayback = machine.scanning_player.get_stream_playback()
	_menu()
	await frames(1)
	await _mixes(2)
	var stable_position: float = machine.scanning_player.get_playback_position()
	await _mixes(1)
	check(machine.scanning_player.stream_paused and machine.scanning_player.get_playback_position() == stable_position and machine.scanning_player.stream == stream and machine.scanning_player.get_stream_playback() == playback, "通知中心空间完成提示在实际混音提交后精确暂停同一播放对象")
	_menu()
	await _mixes(1)
	check(machine.scanning_player.get_playback_position() != stable_position and machine.scanning_player.get_stream_playback() == playback, "通知中心空间完成提示恢复续接")
	for audio: AudioStreamPlayer3D in players:
		check(_settings(audio) == expected_settings[audio.get_instance_id()], "通知中心暂停恢复不覆盖编辑器空间参数")
	machine.cancel_print(machine.get_print_serial(), "空间音效参数专项清理")
	for audio: AudioStreamPlayer3D in players:
		check(not audio.playing and _settings(audio) == expected_settings[audio.get_instance_id()], "通知中心清理停止声音并保留编辑器空间参数")


func _finish_spatial() -> void:
	paused = false
	if is_instance_valid(world):
		world.queue_free()
	await frames(3)
	await _mixes(2)
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var output: FileAccess = FileAccess.open(evidence_directory.path_join("机器空间音效专项报告.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "断言": records, "来源采样": spatial_samples, "失败数": failures, "输入方式": "无图形引擎内部输入，未调用系统指针"}, "\t"))
	output.close()
	print("机器空间音效断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)


func run_checks() -> void:
	check(DisplayServer.get_name() == "headless", "机器空间音效专项使用无图形后端")
	if OS.get_cmdline_user_args().has("--audio-baseline-audit"):
		_audit_scene_types(BEFORE_PHONE, 4)
		await _finish_spatial()
		return
	_audit_scene_types(PHONE_SCENE, 4)
	_audit_scene_types(QUEST_SCENE, 6)
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, TEST_BUS)
	_prepare_single_definition()
	# 本用例保留实际首句资源，给真实混音暂停与恢复足够的自然播放长度。
	single_definition.line_ids = PackedStringArray(["chat_0_0"])
	single_definition.voice_streams = [CALL_DEFINITION.voice_streams[0]]
	await _test_receiver_and_actions()
	await _test_voice_binding()
	await _test_immediate_voice_release()
	await _test_quest_configuration()
	await _finish_spatial()
