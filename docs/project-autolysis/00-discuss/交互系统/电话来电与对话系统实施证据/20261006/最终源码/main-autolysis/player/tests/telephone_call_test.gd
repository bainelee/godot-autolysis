extends "res://main-autolysis/player/tests/telephone_device_test.gd"
## 来电与真实听筒成对事务专项。完成信号不作人工推进；旧身份回调仅明确注入。

const CALL_DEFINITION = preload("res://main-autolysis/systems/dialogue-system/chat_0.tres")
const CallController = preload("res://main-autolysis/scenes/prefabs/prefab_machines/scripts/autolysis_telephone_call_controller.gd")

var call_records: Array[Dictionary] = []
var pause_records: Array[Dictionary] = []
var single_definition: AutolysisDialogueDefinition
var earliest_lock_seen: bool = false
var reentrant_return_refused: bool = false
var business_normal_completions: int = 0


func _call() -> AutolysisTelephoneCallController:
	return phone.call_controller as AutolysisTelephoneCallController


func _dialogue() -> AutolysisDialoguePlayer:
	return (player as AutolysisPlayer).dialogue_player


func _call_stage() -> int:
	return int(_call().get_call_snapshot().stage)


func _record_call(label: String) -> void:
	var snapshot: Dictionary = _call().get_call_snapshot()
	snapshot["说明"] = label
	snapshot["墙钟微秒"] = Time.get_ticks_usec()
	snapshot["库存持有会话"] = inventory.get_handset_session_id()
	snapshot["电话持有会话"] = phone.get_holder_session_id()
	snapshot["铃声播放"] = _call().ring_player.playing if is_instance_valid(_call().ring_player) else false
	snapshot["对话"] = _dialogue().get_session_snapshot()
	call_records.append(snapshot)


func _prepare_single_definition() -> void:
	single_definition = CALL_DEFINITION.duplicate()
	single_definition.dialogue_id = &"telephone_single_test"
	single_definition.line_ids = PackedStringArray(["chat_0_8"])
	single_definition.voice_streams = [CALL_DEFINITION.voice_streams[8]]


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true).timeout


func _wait_realtime(condition: Callable, label: String, maximum: float = 12.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(maximum * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	check(false, "真实时钟等待上限仅用于验收失败：" + label)
	return false


func _menu() -> void:
	var event := InputEventAction.new()
	event.action = &"menu"
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = &"menu"
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()


func _pause_snapshot(label: String) -> Dictionary:
	var value: Dictionary = {
		"说明": label, "墙钟微秒": Time.get_ticks_usec(),
		"菜单暂停": player.is_movement_paused, "场景树暂停": paused,
		"来电": _call().get_call_snapshot(), "播放": _dialogue().get_session_snapshot(),
		"铃声位置": _call().ring_player.get_playback_position() if is_instance_valid(_call().ring_player) else 0.0,
		"铃声暂停": _call().ring_player.stream_paused if is_instance_valid(_call().ring_player) else false,
	}
	pause_records.append(value)
	return value


func _menu_freeze(label: String, kind: String) -> void:
	_menu()
	await frames(1)
	var before: Dictionary = _pause_snapshot(label + "暂停后")
	await _wait_seconds(0.35)
	var after: Dictionary = _pause_snapshot(label + "保持")
	check(player.is_movement_paused and (player as AutolysisPlayer).is_dialogue_timing_paused(), label + "真实菜单输入同步统一暂停事实")
	match kind:
		"delay": check(is_equal_approx(before.来电.delay_remaining, after.来电.delay_remaining), label + "保留原延后剩余时间")
		"ring": check(before.铃声暂停 and after.铃声暂停 and absf(before.铃声位置 - after.铃声位置) < 0.08, label + "保留循环铃声音频位置")
		"voice": check(absf(before.播放.audio_position - after.播放.audio_position) < 0.08 and before.播放.index == after.播放.index and before.播放.stage == after.播放.stage, label + "保留当前真实语音位置及句身份")
		"hold": check(is_equal_approx(before.播放.hold_remaining, after.播放.hold_remaining), label + "保留句后剩余时间")
		"fade": check(is_equal_approx(before.播放.subtitle_alpha, after.播放.subtitle_alpha) and after.播放.stage == &"fade", label + "保留本次渐隐透明度")
	_menu()
	await frames(1)
	check(not player.is_movement_paused, label + "第二次真实菜单输入恢复")


func _test_delay_reset_and_cancel() -> void:
	await _new_scene(true)
	await _enter()
	await _take()
	check(phone.request_call(single_definition, player), "持筒时公开请求受理一次来电")
	check(_call_stage() == CallController.Stage.WAIT_RETURN and not _call().ring_player.playing, "真实已提交持筒请求保存等待且不响铃")
	check(focus.is_focused_on(phone.focus_target), "持筒等待期间持续保持电话聚焦")
	check(phone.request_handset_transfer(player), "等待阶段开始归还取消用例")
	phone.cancel_handset_transfer()
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "取消归还实际限位恢复")
	check(_call_stage() == CallController.Stage.WAIT_RETURN and _call().deferred_timer.is_stopped(), "归还取消不当作正常归还且不创建延后计时")
	await _return()
	check(_call_stage() == CallController.Stage.DELAYED and _call().deferred_timer.time_left > 1.8, "成对成功归还后才开始完整两秒")
	await _wait_seconds(0.45)
	await _menu_freeze("来电延后菜单暂停", "delay")
	await _take()
	check(_call_stage() == CallController.Stage.WAIT_RETURN and not _call().ring_player.playing, "延后成功重取废弃旧计时且不算接听")
	var old_wait: int = _call().get_call_snapshot().wait_serial
	await _wait_seconds(0.4)
	await _return()
	check(_call_stage() == CallController.Stage.DELAYED and _call().deferred_timer.time_left > 1.8 and _call().get_call_snapshot().wait_serial != old_wait, "再次成对归还建立新序号并重新等待完整两秒")
	await _wait_seconds(0.7)
	check(_call_stage() == CallController.Stage.DELAYED, "新的延后未累计此前已耗时间")
	paused = true
	await frames(2)
	var tree_before: Dictionary = _pause_snapshot("延后场景树暂停")
	await _wait_seconds(0.25)
	var tree_after: Dictionary = _pause_snapshot("延后场景树暂停保持")
	check(is_equal_approx(tree_before.来电.delay_remaining, tree_after.来电.delay_remaining), "外部场景树暂停保留原延后进度")
	player.is_movement_paused = true
	paused = false
	await frames(2)
	var overlap_before: Dictionary = _pause_snapshot("只恢复场景树")
	await _wait_seconds(0.25)
	var overlap_after: Dictionary = _pause_snapshot("菜单仍暂停")
	check(is_equal_approx(overlap_before.来电.delay_remaining, overlap_after.来电.delay_remaining), "恢复场景树但菜单仍暂停时计时不推进")
	player.is_movement_paused = false
	await _wait_realtime(func() -> bool: return _call_stage() == CallController.Stage.ACTIVE, "延后自然到期激活")
	check(focus.is_focused_on(phone.focus_target) and _call().ring_player.playing, "完整两秒自然到期在持续聚焦下激活空间铃声")
	_record_call("延后与成功重取重置")
	await _wait_realtime(func() -> bool: return _call().ring_player.get_playback_position() > 0.2, "铃声实际推进后才采样中途暂停")
	await _menu_freeze("循环铃声菜单暂停", "ring")
	_call().cancel_call("延后用例清理")


func _test_take_business_rollback_and_locks() -> void:
	await _new_scene(true)
	await _enter()
	check(phone.request_call(single_definition, player), "稳定挂机立即请求来电")
	check(_call_stage() == CallController.Stage.ACTIVE and _call().ring_player.playing and _call().deferred_timer.is_stopped(), "稳定挂机直接激活铃声没有两秒延后")
	var fixture: FixtureTelephone = phone as FixtureTelephone
	fixture.refuse_business_take = true
	check(phone.request_handset_transfer(player), "开始双方暂时提交后业务取下拒绝用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "业务取下拒绝成对回滚")
	check(not inventory.has_exclusive_handset() and phone.get_holder_session_id() == 0 and phone.handset_visual.visible and phone.move_limit_shape.disabled, "业务取下拒绝后来源与库存展示占用及限位成对恢复")
	check(_call_stage() == CallController.Stage.ACTIVE and _dialogue().get_session_snapshot().token == 0 and _call().ring_player.playing, "取下业务失败不接听不开始对话并释放仅本次准备令牌")
	fixture.refuse_business_take = false
	earliest_lock_seen = false
	reentrant_return_refused = false
	inventory.held_item_changed.connect(_first_held_observer)
	await _take()
	check(earliest_lock_seen and reentrant_return_refused, "最早持物观察已经读取归还限制且重入归还被拒绝")
	var held_session: int = inventory.get_handset_session_id()
	check(_call_stage() == CallController.Stage.TALKING and not _call().ring_player.playing, "成对接听成功才停止铃声并建立通话归属")
	check(focus.is_focused_on(phone.focus_target), "接听成功不自动退出原电话聚焦")
	check(not phone.can_return_handset(player) and not phone.request_handset_transfer(player), "电话归还许可与公开请求均拒绝通话期间归还")
	check(not inventory.can_return_handset(player, phone) and inventory.begin_handset_return(player, phone) == 0, "库存归还许可与独立准备均不能绕过限制")
	check(phone.is_handset_return_blocked(player, held_session) and not phone.is_handset_return_blocked(player, held_session + 999), "限制仅匹配原持有会话而不使用新归还事务令牌")
	check(not other_phone.is_handset_return_blocked(player, held_session), "另一电话不能读取或解除当前电话通话限制")
	check(not inventory.cycle_focus(1), "通话时保留听筒道具切换锁")
	# 显式旧完成回调注入；不冒充正常语音自然完成。
	_call().call("_on_dialogue_finished", -1, single_definition.dialogue_id, phone, _call().get_call_snapshot().call_serial)
	check(phone.is_handset_return_blocked(player, held_session), "旧播放令牌完成回调注入不解锁当前持有")
	await _menu_freeze("真实语音菜单暂停", "voice")
	paused = true
	player.is_showing_ui = true
	await frames(2)
	var voice_before: Dictionary = _pause_snapshot("语音树与界面叠加暂停")
	await _wait_seconds(0.25)
	player.is_showing_ui = false
	await frames(2)
	var voice_after: Dictionary = _pause_snapshot("只恢复界面仍树暂停")
	check(absf(voice_before.播放.audio_position - voice_after.播放.audio_position) < 0.08 and voice_after.播放.paused, "树与界面叠加仅恢复界面时原语音仍冻结")
	paused = false
	await _exit_focus()
	check(inventory.get_handset_session_id() == held_session and phone.is_handset_return_blocked(player, held_session) and not phone.move_limit_shape.disabled, "主动退出聚焦保留通话听筒锁及真实限位")
	await _enter()
	await _wait_realtime(func() -> bool: return _dialogue().get_session_snapshot().stage == &"hold", "真实语音自然结束进入保留")
	await _menu_freeze("句后保留菜单暂停", "hold")
	await _wait_realtime(func() -> bool: return _dialogue().get_session_snapshot().stage == &"fade", "原句后计时自然到期")
	await _menu_freeze("字幕渐隐菜单暂停", "fade")
	check(phone.is_handset_return_blocked(player, held_session), "最后渐隐暂停期间仍保持原通话限制")
	await _wait_realtime(func() -> bool: return _call_stage() == CallController.Stage.COMPLETED, "最后渐隐自然结束提交正常完成")
	check(not _dialogue().get_subtitle().get_layout_snapshot().visible and not phone.is_handset_return_blocked(player, held_session), "末句字幕全部隐藏后才解除匹配归还限制")
	check(inventory.get_handset_session_id() == held_session and phone.get_holder_session_id() == held_session, "正常对话完成仍持筒而不自动挂机")
	_record_call("成对接听归还封锁与五阶段菜单暂停")
	fixture.refuse_business_return = true
	check(phone.request_handset_transfer(player), "普通归还双方暂时提交后业务拒绝用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "归还业务拒绝恢复")
	check(inventory.get_handset_session_id() == held_session and phone.get_holder_session_id() == held_session and not phone.move_limit_shape.disabled and not phone.handset_visual.visible, "归还业务拒绝恢复原持有展示与实际限位")
	fixture.refuse_business_return = false
	await _return()


func _first_held_observer() -> void:
	if not inventory.has_exclusive_handset() or _call_stage() != CallController.Stage.TALKING:
		return
	earliest_lock_seen = phone.is_handset_return_blocked(player, inventory.get_handset_session_id())
	reentrant_return_refused = not phone.request_handset_transfer(player)


func _test_completion_pending_and_cancel() -> void:
	await _new_scene()
	await _enter()
	var voice: AudioStreamPlayer = _dialogue().get_node("Timing/Voice")
	# 先注册观察，在原生音频自然完成当帧经真实菜单输入暂停。
	voice.finished.connect(_menu, CONNECT_ONE_SHOT)
	phone.request_call(single_definition, player)
	await _take()
	var held_session: int = inventory.get_handset_session_id()
	await _wait_realtime(func() -> bool: return _dialogue().get_session_snapshot().completion_pending == &"voice", "自然音频完成当帧暂停记录待同步")
	check(player.is_movement_paused and _dialogue().get_session_snapshot().stage == &"voice" and phone.is_handset_return_blocked(player, held_session), "自然语音完成当帧暂停只保存待同步而不推进或解锁")
	await _wait_seconds(0.25)
	check(_dialogue().get_session_snapshot().completion_pending == &"voice", "暂停中待同步自然完成保留原令牌")
	_menu()
	await _wait_realtime(func() -> bool: return _dialogue().get_session_snapshot().stage == &"hold", "自然完成待同步恢复只推进保留一次")
	check(_dialogue().get_session_snapshot().index == 0 and not voice.playing, "恢复自然结束的语音不重播")
	_call().cancel_call("专项显式取消仍有效听筒")
	check(_call_stage() == CallController.Stage.ABORTED and not phone.is_handset_return_blocked(player, held_session), "显式取消结束本次来电并清除匹配对话归还限制")
	check(inventory.get_handset_session_id() == held_session and not phone.move_limit_shape.disabled, "显式取消仅对话后仍保持有效听筒持有与限位")
	await _return()
	check(not phone.request_call(single_definition, player), "取消本次来电不自动重新等待或重播")
	_record_call("自然完成当帧暂停与普通取消")


func _test_optional_ring_and_source_failure() -> void:
	await _new_scene()
	await _enter()
	_call().ring_stream = null
	check(phone.request_call(single_definition, player) and _call_stage() == CallController.Stage.ACTIVE, "铃声资源失效仍激活来电业务")
	await _take()
	var session: int = inventory.get_handset_session_id()
	check(phone.is_handset_return_blocked(player, session), "可选铃声失效不影响有效接听与通话锁")
	phone.reference_camera.queue_free()
	await frames(4)
	check(inventory.get_handset_session_id() == session and phone.is_handset_return_blocked(player, session) and _dialogue().get_session_snapshot().token > 0, "聚焦参照相机释放保留仍有效通话及听筒限位")
	_call().cancel_call("相机隔离用例清理")
	await _new_scene()
	await _enter()
	phone.request_call(single_definition, player)
	await _take()
	var original: int = inventory.get_handset_session_id()
	_dialogue().get_node("Timing/Voice").queue_free()
	await frames(4)
	check(_call_stage() == CallController.Stage.ABORTED and inventory.get_handset_session_id() == original and not phone.move_limit_shape.disabled, "必要语音播放器释放异常结束来电且有效听筒继续持有")
	check(not _call().last_abort_record.is_empty() and not phone.is_handset_return_blocked(player, original), "播放依赖失效记录真实异常原因且只清匹配通话锁")
	await _return()
	_record_call("可选铃声与必要播放依赖隔离")


func run_checks() -> void:
	check(DisplayServer.get_name() == "headless", "专项实际使用无图形后端")
	_prepare_single_definition()
	await _test_delay_reset_and_cancel()
	await _test_take_business_rollback_and_locks()
	await _test_completion_pending_and_cancel()
	await _test_optional_ring_and_source_failure()
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var output := FileAccess.open(evidence_directory.path_join("电话来电成对事务暂停与异常.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "断言": records, "来电采样": call_records, "暂停采样": pause_records, "失败数": failures}, "\t"))
	paused = false
	world.queue_free()
	await frames(3)
	quit(1 if failures > 0 else 0)
