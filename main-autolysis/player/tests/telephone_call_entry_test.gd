extends SceneTree
## 主场景显式入口与运行机会；无图形引擎输入，不操作原生指针。

const EVIDENCE = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd")
const MAIN_SCENE: String = "res://main-autolysis/scenes/01-autolysis-test.tscn"

var failures: int = 0
var checks: Array[Dictionary] = []
var audio_sources: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
	checks.append({"说明": description, "通过": condition})
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1


func frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame


func _capture_audio_references(scene: Node) -> Array[WeakRef]:
	var result: Array[WeakRef] = []
	for node: Node in scene.find_children("*", "", true, false):
		if (node is AudioStreamPlayer or node is AudioStreamPlayer3D) and node.has_stream_playback():
			result.append(weakref(node.get_stream_playback()))
			audio_sources.append({"来源": str(node.get_path()), "播放身份": node.get_stream_playback().get_instance_id()})
	return result


func _audio_references_alive(references: Array[WeakRef]) -> bool:
	for reference: WeakRef in references:
		if reference.get_ref() != null:
			return true
	return false


func run_checks() -> void:
	var session: Node = root.get_node_or_null("AutolysisRuntimeSession")
	check(session != null, "主工程登记运行级会话自动加载")
	if session == null:
		quit(1)
		return
	check(not session.is_telephone_test_consumed(), "新游戏进程具有一次测试机会")
	var scene: Node = load(MAIN_SCENE).instantiate()
	root.add_child(scene)
	await frames(8)
	var trigger: AutolysisTelephoneCallTestTrigger = scene.get_node("TelephoneCallTestTrigger")
	var telephone: AutolysisTelephone = scene.get_node("interaction_prefabs/machines/MachineTelephone0/StaticBody3D")
	var player: AutolysisPlayer = scene.get_node("autolysis_player")
	check(trigger.telephone == telephone and trigger.player == player, "主场景入口显式引用电话物理业务对象及当前玩家")
	check(player.dialogue_player != null and player.dialogue_player.is_inside_tree(), "正式玩家挂载通用对话播放器")
	check(trigger.dialogue_definition.dialogue_id == &"chat_0", "入口配置首段独立对话资源")
	var action_events: Array[InputEvent] = InputMap.action_get_events(&"telephone_call_test")
	check(action_events.size() == 1 and action_events[0] is InputEventKey and action_events[0].physical_keycode == KEY_O, "测试动作明确绑定指定物理字母键")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_O
	key.pressed = true
	Input.parse_input_event(key)
	await frames(3)
	key.pressed = false
	Input.parse_input_event(key)
	await frames(2)
	check(session.is_telephone_test_consumed(), "引擎内部真实测试键输入消耗运行机会")
	var call_snapshot: Dictionary = telephone.call_controller.get_call_snapshot()
	check(call_snapshot["stage"] == AutolysisTelephoneCallController.Stage.ACTIVE and call_snapshot["call_serial"] == 1, "挂机测试键请求立即激活指定电话且只建立一次来电")
	check(not trigger.request_test_call(), "同一运行再次直接请求不能取得机会")
	var audio_references: Array[WeakRef] = _capture_audio_references(scene)
	scene.queue_free()
	await frames(4)
	check(session.is_inside_tree() and session.is_telephone_test_consumed(), "场景释放不移除运行会话及已消费事实")
	var reloaded_scene: Node = load(MAIN_SCENE).instantiate()
	root.add_child(reloaded_scene)
	await frames(8)
	var reloaded_trigger: AutolysisTelephoneCallTestTrigger = reloaded_scene.get_node("TelephoneCallTestTrigger")
	check(not reloaded_trigger.request_test_call(), "重新创建主场景及电话不恢复测试机会")
	var reloaded_call: Dictionary = reloaded_trigger.telephone.call_controller.get_call_snapshot()
	check(reloaded_call["stage"] == AutolysisTelephoneCallController.Stage.IDLE and reloaded_call["call_serial"] == 0, "重载后的电话保持未请求且不重响")
	check(session.is_telephone_test_consumed(), "重载失败请求仍保持机会已消费")
	audio_references.append_array(_capture_audio_references(reloaded_scene))
	reloaded_scene.queue_free()
	await frames(4)
	var pending_after_frames: bool = _audio_references_alive(audio_references)
	var deadline: int = Time.get_ticks_usec() + 2000000
	while _audio_references_alive(audio_references) and Time.get_ticks_usec() < deadline:
		OS.delay_msec(1)
		await process_frame
	check(not _audio_references_alive(audio_references), "电话入口专项退出前原场景与重载场景实际声音播放均已退役")
	var directory: String = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/电话来电与对话系统实施证据/20261006/主场景入口")
	DirAccess.make_dir_recursive_absolute(directory)
	var report := FileAccess.open(directory.path_join("主场景入口报告.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"验证方式": "无图形引擎内部键盘事件；无原生输入", "引擎版本": Engine.get_version_info(), "断言": checks, "退出音频采样": {"播放来源": audio_sources, "原四帧后仍存活": pending_after_frames, "实际退役完成": not _audio_references_alive(audio_references)}, "失败数": failures}, "\t"))
	report.close()
	quit(1 if failures > 0 else 0)
