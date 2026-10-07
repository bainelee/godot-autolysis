extends "res://main-autolysis/player/tests/telephone_call_test.gd"
## 仅无图形；冻结电话事务轮询使真实计时到期与预处理相邻，不人工发完成信号。

var boundary_samples: Array[Dictionary] = []
var boundary_action: String = ""
var boundary_lines: int = 0
var boundary_finished: int = 0
var boundary_aborted: int = 0
var boundary_call: WeakRef
var boundary_intercept_fade: bool = false


func _sample_boundary(label: String) -> void:
	var sample: Dictionary = {"说明": label, "普通帧": Engine.get_process_frames(), "物理帧": Engine.get_physics_frames(), "墙钟微秒": Time.get_ticks_usec()}
	if is_instance_valid(phone):
		sample["来电"] = _call().get_call_snapshot()
		sample["来源持有"] = phone.get_holder_session_id()
		sample["来源待转移"] = phone.is_transfer_pending()
		sample["限位停用"] = phone.move_limit_shape.disabled if is_instance_valid(phone.move_limit_shape) else null
	if is_instance_valid(inventory):
		sample["库存持有"] = inventory.get_handset_session_id()
	if is_instance_valid(player) and is_instance_valid(_dialogue()):
		sample["对话"] = _dialogue().get_session_snapshot()
	sample["实际开始句数"] = boundary_lines
	boundary_samples.append(sample)


func _deferred_fixture() -> void:
	await _new_scene(true)
	await _enter()
	await _take()
	check(phone.request_call(single_definition, player), "边界专项持筒请求受理")
	await _return()
	check(_call_stage() == CallController.Stage.DELAYED, "边界专项以正常成对归还开始两秒等待")
	await _wait_realtime(func() -> bool: return _call().deferred_timer.time_left < 0.09, "等待真实计时接近自然到期", 3.0)


func _test_expiry_transaction_neighbors() -> void:
	for outcome: String in ["成功", "取消", "来源提交拒绝"]:
		await _deferred_fixture()
		var serial: int = int(_call().get_call_snapshot().wait_serial)
		# 唯一故障注入为停止电话物理轮询；计时器、声音和控制器继续真实处理。
		phone.set_physics_process(false)
		check(phone.request_handset_transfer(player), outcome + "用例在自然到期附近建立真实取下预处理")
		await _wait_realtime(func() -> bool: return bool(_call().get_call_snapshot().delay_expired), "真实计时到期保留事实", 2.0)
		check(_call_stage() == CallController.Stage.DELAYED and not _call().ring_player.playing and phone.is_transfer_pending(), outcome + "预处理未结束时到期事实保留且不响铃")
		_sample_boundary(outcome + "预处理期间真实自然到期")
		if outcome == "取消":
			phone.cancel_handset_transfer()
		elif outcome == "来源提交拒绝":
			(phone as FixtureTelephone).refuse_take = true
		phone.set_physics_process(true)
		await _wait(func() -> bool: return not phone.is_transfer_pending(), outcome + "用例结束真实物理事务")
		if outcome == "成功":
			check(_call_stage() == CallController.Stage.WAIT_RETURN and inventory.has_exclusive_handset() and not _call().ring_player.playing, "到期附近成功取下废弃旧等待且不算接听")
			await _return()
			check(_call_stage() == CallController.Stage.DELAYED and _call().deferred_timer.time_left > 1.8, "到期附近成功重取后正常归还重新等待完整两秒")
			_call().call("_on_delay_timeout", serial)
			check(not _call().get_call_snapshot().delay_expired and _call_stage() == CallController.Stage.DELAYED, "明确注入旧等待序号到期回调不能推进后来等待")
		else:
			await _wait_realtime(func() -> bool: return _call_stage() == CallController.Stage.ACTIVE, outcome + "稳定挂机后处理已经真实到期事实", 2.0)
			check(not inventory.has_exclusive_handset() and phone.is_handset_stably_docked() and _call().ring_player.playing and _call().get_call_snapshot().wait_serial == serial, outcome + "不伪造归还或重置等待，沿原已到期序号激活")
		_sample_boundary(outcome + "事务最终结果")
		_call().cancel_call("到期邻近事务用例清理")


func _test_expiry_frame_menu_pause() -> void:
	await _new_scene(true)
	await _enter()
	await _take()
	phone.request_call(single_definition, player)
	# 在归还启动计时并绑定本次业务回调前注册，真实到期当帧先经过正式菜单输入。
	_call().deferred_timer.timeout.connect(_menu, CONNECT_ONE_SHOT)
	await _return()
	await _wait_realtime(func() -> bool: return player.is_movement_paused and bool(_call().get_call_snapshot().delay_expired), "真实计时自然到期当帧菜单暂停", 3.0)
	check(_call_stage() == CallController.Stage.DELAYED and not _call().ring_player.playing, "到期当帧菜单暂停保存真实到期事实且不推进来电表现")
	var serial: int = int(_call().get_call_snapshot().wait_serial)
	await _wait_seconds(0.2)
	check(_call_stage() == CallController.Stage.DELAYED and _call().get_call_snapshot().wait_serial == serial and _call().get_call_snapshot().delay_expired, "暂停保留同一已到期序号不重新累计")
	_sample_boundary("真实计时到期当帧菜单暂停")
	_menu()
	await _wait_realtime(func() -> bool: return _call_stage() == CallController.Stage.ACTIVE, "恢复只提交本次到期事实", 2.0)
	check(_call().ring_player.playing and _call().get_call_snapshot().wait_serial == serial, "恢复后处理一次原自然到期并开始铃声")
	_call().cancel_call("到期当帧暂停用例清理")


func _observe_line(_token: int, _id: StringName, _index: int, _text: String) -> void:
	boundary_lines += 1


func _observe_finished(_token: int, _id: StringName, _source: Node) -> void:
	boundary_finished += 1


func _observe_aborted(token: int, _id: StringName, _source: Node, reason: String) -> void:
	boundary_aborted += 1
	var controller: Variant = boundary_call.get_ref() if boundary_call != null else null
	boundary_samples.append({"说明": "匹配异常观察", "播放令牌": token, "原因": reason, "业务开始句数": boundary_lines, "正常完成数": boundary_finished, "来电异常": controller.last_abort_record.duplicate() if is_instance_valid(controller) else {}})


func _wire_lifecycle_observers() -> void:
	boundary_lines = 0
	boundary_finished = 0
	boundary_aborted = 0
	boundary_call = weakref(_call())
	_dialogue().line_started.connect(_observe_line)
	_dialogue().dialogue_finished.connect(_observe_finished)
	_dialogue().dialogue_aborted.connect(_observe_aborted)


func _first_release_observer() -> void:
	if boundary_action.is_empty() or not inventory.has_exclusive_handset():
		return
	var action: String = boundary_action
	boundary_action = ""
	check(phone.is_handset_return_blocked(player, inventory.get_handset_session_id()), "释放观察者在最早持物观察已读到匹配归还锁")
	match action:
		"电话": phone.queue_free()
		"玩家": player.queue_free()
		"播放器": _dialogue().queue_free()
		"来源同步离树":
			phone.get_parent().remove_child(phone)
			phone.queue_free()


func _test_earliest_observer_releases() -> void:
	for dependency: String in ["电话", "玩家", "播放器", "来源同步离树"]:
		await _new_scene(true)
		await _enter()
		_wire_lifecycle_observers()
		phone.request_call(single_definition, player)
		boundary_action = dependency
		inventory.held_item_changed.connect(_first_release_observer)
		check(phone.request_handset_transfer(player), dependency + "释放用例开始成对接听")
		await frames(8)
		check(boundary_lines == 0 and boundary_finished == 0 and boundary_aborted == 1, "最早持物观察" + dependency + "释放使本次准备异常一次且无旧表现开始或正常完成")
		if dependency == "电话" or dependency == "来源同步离树":
			check(not is_instance_valid(phone) and inventory.get_handset_session_id() == 0 and inventory.get_handset_display() == null, "观察释放来源后库存与显示匹配清理")
		elif dependency == "玩家":
			check(not is_instance_valid(player) and phone.get_holder_session_id() == 0 and phone.move_limit_shape.disabled and _call_stage() == CallController.Stage.ABORTED, "观察释放玩家后电话占用与真实限位匹配清理")
		else:
			check(inventory.get_handset_session_id() > 0 and phone.get_holder_session_id() == inventory.get_handset_session_id() and not phone.is_handset_return_blocked(player, inventory.get_handset_session_id()) and not phone.move_limit_shape.disabled, "观察释放播放器仅解除对话锁并保留有效听筒成对持有")
			await _return()


func _test_necessary_handset_and_limit_release() -> void:
	for dependency: String in ["听筒显示", "限位", "玩家", "电话"]:
		await _new_scene(true)
		await _enter()
		_wire_lifecycle_observers()
		phone.request_call(single_definition, player)
		await _take()
		var session: int = inventory.get_handset_session_id()
		check(is_instance_valid(phone.handset_audio) and phone.handset_audio.telephone == phone and phone.handset_audio.sound_origin.is_ancestor_of(_call().voice_player), dependency + "脚本替换夹具保留正式听筒音频与语音输出接线")
		check(is_instance_valid(_call().voice_player) and phone.is_ancestor_of(_call().voice_player) and _dialogue().get_voice_output() == _call().voice_player, dependency + "本次准备已选择同一电话的实际空间语音输出")
		_sample_boundary(dependency + "取筒提交后真实接听等待读取点")
		await _wait_realtime(func() -> bool: return boundary_lines == 1, dependency + "等待实际接听计时自然完成与首句开始观察")
		check(session > 0 and boundary_lines == 1, dependency + "生命周期用例已经实际开始本次对话")
		check(phone.handset_audio.sound_origin.global_transform.is_equal_approx(inventory.get_handset_display().global_transform), dependency + "实际对话开始时听筒声源父节点跟随当前持筒显示")
		_sample_boundary(dependency + "接听等待自然完成后真实首句读取点")
		var other_actor: AutolysisPlayer = load("res://main-autolysis/player/autolysis_player.tscn").instantiate() as AutolysisPlayer
		other_actor.set_physics_process(false)
		other_actor.set_process_input(false)
		other_actor.set_process_unhandled_input(false)
		world.add_child(other_actor)
		check(not phone.is_handset_return_blocked(other_actor, session) and phone.is_handset_return_blocked(player, session), "另一真实玩家对象查询不能替代接听玩家身份")
		other_actor.queue_free()
		_call().call("_on_dialogue_finished", _call().get_call_snapshot().playback_token, single_definition.dialogue_id, other_phone, _call().get_call_snapshot().call_serial)
		check(phone.is_handset_return_blocked(player, session), "明确注入错误来源的当前令牌完成回调不能解锁")
		match dependency:
			"听筒显示": inventory.get_handset_display().queue_free()
			"限位": phone.move_limit_shape.queue_free()
			"玩家": player.queue_free()
			"电话": phone.queue_free()
		await frames(8)
		check(boundary_finished == 0 and boundary_aborted == 1, dependency + "失效只发布匹配异常一次且不正常完成")
		if is_instance_valid(inventory):
			check(inventory.get_handset_session_id() == 0 and inventory.get_handset_display() == null, dependency + "必要依赖失效清除匹配库存与显示")
		if is_instance_valid(phone):
			check(phone.get_holder_session_id() == 0 and _call_stage() == CallController.Stage.ABORTED and not phone.is_handset_return_blocked(player if is_instance_valid(player) else null, session), dependency + "必要依赖失效清除原来源占用与匹配通话锁")
			check(_call().last_abort_record.get("当前句索引", -1) == 0 and int(_call().last_abort_record.get("来源实例身份", 0)) > 0, "异常记录保留实际当前句及原来源实例身份")
		_sample_boundary(dependency + "异常后结果")


func _test_after_business_completion_rejection() -> void:
	await _new_scene(true)
	await _enter()
	phone.request_call(single_definition, player)
	(phone as FixtureTelephone).refuse_business_take_after_commit = true
	check(phone.request_handset_transfer(player), "故障注入上级业务完成返回后拒绝本次取下")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "业务状态已经修改后拒绝的成对回滚")
	check(_call_stage() == CallController.Stage.ACTIVE and _call().get_call_snapshot().playback_token == 0 and _dialogue().get_session_snapshot().token == 0, "尚未观察发布的业务完成拒绝还原激活来电并释放本次准备")
	check(not inventory.has_exclusive_handset() and phone.is_handset_stably_docked() and phone.handset_visual.visible and _call().ring_player.playing, "上级业务完成后拒绝仍成对恢复库存来源显示和限位")
	_call().cancel_call("取下完成后拒绝用例清理")
	await _new_scene(true)
	await _enter()
	await _take()
	phone.request_call(single_definition, player)
	var session: int = inventory.get_handset_session_id()
	(phone as FixtureTelephone).refuse_business_return_after_commit = true
	check(phone.request_handset_transfer(player), "故障注入上级业务完成返回后拒绝本次归还")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "业务归还拒绝恢复原持有")
	check(_call_stage() == CallController.Stage.WAIT_RETURN and _call().deferred_timer.is_stopped(), "尚未观察发布的归还业务拒绝撤销新延后阶段而不伪造正常归还")
	check(inventory.get_handset_session_id() == session and phone.get_holder_session_id() == session and not phone.move_limit_shape.disabled and not phone.handset_visual.visible, "归还业务完成后拒绝恢复原持有及真实限位")
	(phone as FixtureTelephone).refuse_business_return_after_commit = false
	await _return()
	check(_call_stage() == CallController.Stage.DELAYED and _call().deferred_timer.time_left > 1.8, "拒绝恢复后下一真实归还正常建立完整两秒延后")
	_call().cancel_call("归还完成后拒绝用例清理")


func _arm_last_fade_menu(_token: int, stage: StringName, _index: int) -> void:
	if not boundary_intercept_fade or stage != &"fade":
		return
	boundary_intercept_fade = false
	var tween: Tween = _dialogue().get("_fade_tween")
	var connections: Array = tween.finished.get_connections()
	for connection: Dictionary in connections:
		tween.finished.disconnect(connection.callable)
	# 补间仍真实自然完成；仅在同一自然事件的业务处理前经过正式菜单输入。
	tween.finished.connect(_menu, CONNECT_ONE_SHOT)
	for connection: Dictionary in connections:
		tween.finished.connect(connection.callable, connection.flags)
	boundary_samples.append({"说明": "最后原生补间完成当帧前置真实菜单观察", "原连接数量": connections.size(), "人工完成信号": false})


func _test_last_fade_frame_matching_lock() -> void:
	await _new_scene(true)
	await _enter()
	_wire_lifecycle_observers()
	boundary_intercept_fade = true
	_dialogue().stage_changed.connect(_arm_last_fade_menu)
	phone.request_call(single_definition, player)
	await _take()
	var session: int = inventory.get_handset_session_id()
	await _wait_realtime(func() -> bool: return _dialogue().get_session_snapshot().completion_pending == &"fade", "最后真实自然渐隐完成当帧菜单暂停保留待同步")
	check(player.is_movement_paused and _call_stage() == CallController.Stage.TALKING and phone.is_handset_return_blocked(player, session) and boundary_finished == 0, "最后原生补间完成当帧暂停保留匹配听筒归还限制而不正常完成")
	check(is_zero_approx(_dialogue().get_session_snapshot().subtitle_alpha), "最后自然渐隐已到零透明度但暂停待同步不重播")
	await _wait_seconds(0.2)
	check(phone.is_handset_return_blocked(player, session) and boundary_finished == 0 and _dialogue().get_session_snapshot().completion_pending == &"fade", "最后自然渐隐完成待同步在暂停中保持原听筒锁及终态互斥")
	_sample_boundary("最后自然渐隐完成当帧匹配通话锁")
	_menu()
	await _wait_realtime(func() -> bool: return _call_stage() == CallController.Stage.COMPLETED, "恢复后提交原最后渐隐一次正常完成")
	check(boundary_finished == 1 and not phone.is_handset_return_blocked(player, session) and inventory.get_handset_session_id() == session and not _dialogue().get_subtitle().get_layout_snapshot().visible, "恢复原最后自然渐隐后只完成一次，字幕隐藏才解锁且仍持筒")
	await _return()


func run_checks() -> void:
	check(DisplayServer.get_name() == "headless", "来电边界专项实际使用无图形后端")
	_prepare_single_definition()
	await _test_expiry_transaction_neighbors()
	await _test_expiry_frame_menu_pause()
	await _test_earliest_observer_releases()
	await _test_necessary_handset_and_limit_release()
	await _test_after_business_completion_rejection()
	await _test_last_fade_frame_matching_lock()
	var audio_references: Array[Dictionary] = _capture_audio_exit_refs()
	paused = false
	if is_instance_valid(world):
		world.queue_free()
	await frames(3)
	await _await_audio_exit_release(audio_references)
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var report := FileAccess.open(evidence_directory.path_join("来电到期提交观察与来源生命周期.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "失败数": failures, "断言": records, "边界采样": boundary_samples, "退出音频采样": audio_exit_samples, "图形验收": false, "原生输入": false, "内部输入": "真实菜单动作由引擎输入解析；真实计时自然完成，无人工完成信号"}, "\t"))
	report.close()
	quit(1 if failures > 0 else 0)
