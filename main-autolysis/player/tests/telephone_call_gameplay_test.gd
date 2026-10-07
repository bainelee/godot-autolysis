extends "res://main-autolysis/player/tests/telephone_call_test.gd"
## 来电容量忙碌与通话中正式玩家物理移动，不以普通持筒回归替代。

var movement_samples: Array[Dictionary] = []


func _busy_finished(_token: int, _id: StringName, _source: Node) -> void:
	check(false, "只准备的忙碌会话不能自然完成")


func _busy_aborted(_token: int, _id: StringName, _source: Node, reason: String) -> void:
	check(not reason.is_empty(), "匹配容量准备取消保留具体原因")


func _test_busy_prepared_dialogue() -> void:
	await _new_scene()
	await _enter()
	var other_source := Node.new()
	world.add_child(other_source)
	var prepared: Dictionary = _dialogue().prepare_dialogue(single_definition, other_source, _busy_finished, _busy_aborted)
	check(prepared.ok, "其他来源准备会话独占通用播放容量")
	check(phone.request_call(single_definition, player), "播放器已有准备会话时电话仍接受明确来电请求")
	await _wait_realtime(func() -> bool: return _call().ring_player.get_playback_position() > 0.1, "忙碌电话铃声实际开始")
	var revision: int = inventory.get_holding_revision()
	check(not phone.request_handset_transfer(player), "播放器容量忙碌时接听取下请求拒绝")
	check(_call_stage() == CallController.Stage.ACTIVE and _call().ring_player.playing, "容量忙碌不终止已激活来电或循环铃声")
	check(_dialogue().get_session_snapshot().token == prepared.token and _dialogue().get_session_snapshot().stage == &"prepared", "忙碌取筒不覆盖原准备令牌或阶段")
	check(not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and not phone.is_transfer_pending() and phone.handset_visual.visible and phone.move_limit_shape.disabled and inventory.get_holding_revision() == revision, "容量忙碌拒绝没有半提交、库存修订或物理限位变化")
	_dialogue().cancel_dialogue(prepared.token, "容量占用准备专项清理")
	await _take()
	check(_call_stage() == CallController.Stage.TALKING, "容量释放后同一仍激活来电允许正常成对接听")
	_record_call("准备容量忙碌与重试")
	_call().cancel_call("忙碌接听用例清理")
	await _return()


func _actor_penetrates_current_limit() -> bool:
	var actor: AutolysisPlayer = player as AutolysisPlayer
	for collision: CollisionShape3D in [actor.standing_collision_shape, actor.crouching_collision_shape]:
		if collision.disabled:
			continue
		var query_shape := BoxShape3D.new()
		# 仅排除接触面的实际几何测量容差，参照既有正式移动专项；不修改生产形状。
		query_shape.size = (collision.shape as BoxShape3D).size - Vector3.ONE * 0.01
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = query_shape
		query.transform = collision.global_transform
		query.collision_mask = phone.move_limit_body.collision_layer
		for hit: Dictionary in actor.get_world_3d().direct_space_state.intersect_shape(query, 64):
			if hit.get("collider") == phone.move_limit_body:
				return true
	return false


func _test_actual_movement_during_voice() -> void:
	await _new_scene()
	await _enter()
	check(phone.request_call(CALL_DEFINITION, player), "正式九句来电为真实通话移动提供当前语音")
	await _take()
	var session: int = inventory.get_handset_session_id()
	await _exit_focus()
	var actor: AutolysisPlayer = player as AutolysisPlayer
	actor.set_physics_process(true)
	await _wait_realtime(func() -> bool: return _dialogue().get_session_snapshot().audio_position > 0.2, "通话语音实际开始后采样移动")
	var before: Dictionary = _dialogue().get_session_snapshot()
	var start: Vector3 = actor.global_position
	var action: StringName = &""
	for candidate: Array in [[&"left", Vector3.LEFT], [&"right", Vector3.RIGHT], [&"forward", Vector3.FORWARD], [&"back", Vector3.BACK]]:
		var motion: Vector3 = actor.body.global_basis * Vector3(candidate[1]) * 0.5
		if not actor.test_move(actor.global_transform, motion):
			action = candidate[0]
			break
	check(not action.is_empty(), "当前真实物理世界可取得限位不阻挡的半米移动方向")
	var no_penetration: bool = true
	if not action.is_empty():
		Input.action_press(action)
		for index: int in 20:
			await frames(1)
			no_penetration = no_penetration and not _actor_penetrates_current_limit()
			var snapshot: Dictionary = _dialogue().get_session_snapshot()
			movement_samples.append({"物理帧": Engine.get_physics_frames(), "位置": str(actor.global_position), "限位局部位置": str(phone.move_limit_shape.to_local(actor.global_position)), "无深穿透": no_penetration, "语音位置": snapshot.audio_position, "句索引": snapshot.index, "播放令牌": snapshot.token, "持有会话": inventory.get_handset_session_id(), "输入动作": action})
		Input.action_release(action)
	await frames(2)
	var after: Dictionary = _dialogue().get_session_snapshot()
	check(actor.global_position.distance_to(start) > 0.05, "正式玩家物理处理在通话中由引擎动作状态实际移动")
	check(no_penetration and not phone.move_limit_shape.disabled and phone._shape_is_active_in_world(phone.move_limit_shape), "通话实际移动保持当前真实限位有效且未深穿透")
	check(after.token == before.token and after.index == before.index and after.stage == &"voice" and after.audio_position > before.audio_position, "通话中实际移动保持同一语音流进度持续且不重启句索引")
	check(inventory.get_handset_session_id() == session and phone.is_handset_return_blocked(player, session) and _call_stage() == CallController.Stage.TALKING, "通话实际移动仍匹配原听筒归还锁与来电归属")
	actor.set_physics_process(false)
	_record_call("通话中正式物理移动")
	_call().cancel_call("真实通话移动专项清理")
	await _enter()
	await _return()


func run_checks() -> void:
	check(DisplayServer.get_name() == "headless", "通话移动与容量专项实际使用无图形后端")
	_prepare_single_definition()
	await _test_busy_prepared_dialogue()
	await _test_actual_movement_during_voice()
	var audio_references: Array[Dictionary] = _capture_audio_exit_refs()
	paused = false
	world.queue_free()
	await frames(3)
	await _await_audio_exit_release(audio_references)
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var output := FileAccess.open(evidence_directory.path_join("通话真实移动与容量忙碌.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "断言": records, "来电采样": call_records, "实际移动采样": movement_samples, "退出音频采样": audio_exit_samples, "失败数": failures, "输入方式": "无图形引擎动作状态，正式玩家物理处理，未调用系统输入"}, "\t"))
	output.close()
	quit(1 if failures > 0 else 0)
