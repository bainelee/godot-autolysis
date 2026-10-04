extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 正式主场景真实玩家物理处理的走、跑、蹲与斜向轨迹；无原生输入。

var telephone: AutolysisTelephone
var records: Array[Dictionary] = []
var trajectories: Array[Dictionary] = []
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/movement")
var actor: AutolysisPlayer
var origin: Vector3 = Vector3(-9.35, 0.8005, 11)


func check(condition: bool, description: String) -> void:
	super.check(condition, description)
	records.append({"说明": description, "通过": condition})


func run_checks() -> void:
	world = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate()
	root.add_child(world)
	player = world.get_node("autolysis_player")
	actor = player as AutolysisPlayer
	telephone = world.get_node("interaction_prefabs/machines/MachineTelephone0/StaticBody3D") as AutolysisTelephone
	actor.focus_controller.configure(actor, actor.camera, actor.held_item_presenter, _headless_entry_allowed)
	await reset_player(origin)
	check(actor.focus_controller.try_enter(telephone.focus_target), "主场景合法口袋位置可进入原电话聚焦")
	await frames(20)
	check(telephone.request_handset_transfer(actor), "主场景合法身体可请求取筒")
	await _settle_transfer()
	check(actor.inventory_controller.has_exclusive_handset() and not telephone.move_limit_shape.disabled, "主场景取筒后限位真实启用")
	actor.focus_controller.request_exit()
	await frames(20)
	check(not actor._handset_movement_guarded(), "稳定持筒退出聚焦后短暂移动保护已经解除")
	var directions: Array[PackedStringArray] = [
		PackedStringArray(["right"]), PackedStringArray(["left"]),
		PackedStringArray(["forward"]), PackedStringArray(["back"]),
		PackedStringArray(["right", "forward"]), PackedStringArray(["right", "back"]),
		PackedStringArray(["left", "forward"]), PackedStringArray(["left", "back"]),
	]
	for mode: String in ["行走", "奔跑", "蹲行"]:
		for actions: PackedStringArray in directions:
			await reset_player(origin)
			if mode == "蹲行":
				await tap("crouch")
			if mode == "奔跑":
				Input.action_press("sprint")
			var start: Vector3 = actor.global_position
			for action: String in actions:
				Input.action_press(action)
			var trace: Array[Dictionary] = []
			var contacts: Dictionary = {}
			var stayed_inside: bool = true
			for sample_index: int in range(120):
				await frames(1)
				var local: Vector3 = telephone.to_local(actor.global_position)
				# 仅用于当前正式资产测量；不参与生产取放或普通动作完成。
				stayed_inside = stayed_inside and local.x > -0.43 and local.x < 1.85 and local.z > 0 and local.z < 2
				for collision_index: int in actor.get_slide_collision_count():
					var collider: Node = actor.get_slide_collision(collision_index).get_collider() as Node
					if is_instance_valid(collider):
						contacts[str(collider.get_path())] = true
				if sample_index % 5 == 0:
					trace.append({"物理帧": Engine.get_physics_frames(), "全局位置": [actor.global_position.x, actor.global_position.y, actor.global_position.z], "电话局部位置": [local.x, local.y, local.z], "速度": [actor.velocity.x, actor.velocity.y, actor.velocity.z], "蹲伏": actor.is_crouching})
			for action: String in actions:
				Input.action_release(action)
			Input.action_release("sprint")
			var distance: float = Vector2(actor.global_position.x - start.x, actor.global_position.z - start.z).length()
			trajectories.append({"模式": mode, "引擎内部动作": actions, "位移": distance, "保持内部": stayed_inside, "碰撞来源": contacts.keys(), "采样": trace})
			check(stayed_inside, "%s模式%s实际移动轨迹未越过电话活动边界" % [mode, "、".join(actions)])
			check(distance > 0.05, "%s模式%s在边界内部存在实际移动" % [mode, "、".join(actions)])
			check(actor.inventory_controller.has_exclusive_handset() and not telephone.move_limit_shape.disabled, "%s模式运动后持物和限位仍属于同一会话" % mode)
	# 验证沿临时墙贴边走动，台阶逻辑不能将薄墙当作可跨台阶。
	# 主场景出生根本身旋转80度；定向诊断只将本次实例转为世界轴，避免把按键名当作世界方向。
	actor.rotation = Vector3.ZERO
	await reset_player(origin)
	Input.action_press("right")
	await frames(50)
	Input.action_press("forward")
	var before_edge: Vector3 = actor.global_position
	await frames(50)
	Input.action_release("right")
	Input.action_release("forward")
	check(actor.global_position.z < before_edge.z - 0.05 and telephone.to_local(actor.global_position).x > -0.43, "贴临时墙沿边移动仍可进行且台阶路径没有跨越活动墙")
	await reset_player(origin)
	var held_session: int = telephone.get_holder_session_id()
	paused = true
	await process_frame
	await process_frame
	check(actor.inventory_controller.has_exclusive_handset() and telephone.get_holder_session_id() == held_session and not telephone.move_limit_shape.disabled, "主场景暂停保持持有及活动墙")
	paused = false
	await frames(2)
	check(actor.focus_controller.try_enter(telephone.focus_target), "主场景移动后原电话可重新聚焦")
	await frames(20)
	check(telephone.request_handset_transfer(actor), "主场景原会话可请求归还")
	await _settle_transfer()
	check(telephone.move_limit_shape.disabled and not actor.inventory_controller.has_exclusive_handset(), "归还同步完成后只停用临时限位")
	actor.focus_controller.request_exit()
	await frames(20)
	await reset_player(origin)
	var east_probe: KinematicCollision3D = KinematicCollision3D.new()
	var east_blocked: bool = actor.test_move(actor.global_transform, Vector3(0.8, 0, 0), east_probe)
	check(not east_blocked or east_probe.get_collider() != telephone.move_limit_body, "归还后原临时墙物理身份不再阻挡运动")
	var south_probe: KinematicCollision3D = KinematicCollision3D.new()
	var south_blocked: bool = actor.test_move(actor.global_transform, Vector3(0, 0, -1.5), south_probe)
	check(south_blocked and south_probe.get_collider() != telephone.move_limit_body, "归还后固定房间墙仍存在并以实际身份区分")
	east_probe = null
	south_probe = null
	Input.action_press("right")
	await frames(45)
	Input.action_release("right")
	check(actor.global_position.x > -8.8, "归还后真实玩家可以通过原临时限位位置")
	actor.set_physics_process(false)
	var audio_playbacks: Array[WeakRef] = _stop_audio_and_capture_playbacks(world)
	world.queue_free()
	actor = null
	telephone = null
	await frames(3)
	var audio_cleanup_started: int = Time.get_ticks_msec()
	while _audio_playbacks_alive(audio_playbacks) and Time.get_ticks_msec() - audio_cleanup_started < 2000:
		await process_frame
	check(not _audio_playbacks_alive(audio_playbacks), "场景退出前实际音频播放实例已释放")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("电话移动轨迹.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"断言": records, "失败": failures, "运动轨迹": trajectories, "音频清理": {"播放实例数": audio_playbacks.size(), "耗时毫秒": Time.get_ticks_msec() - audio_cleanup_started, "实例均已释放": not _audio_playbacks_alive(audio_playbacks)}, "输入方式": "无图形引擎动作状态；正式玩家物理处理；无系统输入"}, "\t"))
	file.close()
	quit(1 if failures > 0 else 0)


func _stop_audio_and_capture_playbacks(scene: Node) -> Array[WeakRef]:
	var references: Array[WeakRef] = []
	for node: Node in scene.find_children("*", "AudioStreamPlayer3D", true, false):
		var audio: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		if audio.has_stream_playback():
			references.append(weakref(audio.get_stream_playback()))
		audio.stop()
	return references


func _audio_playbacks_alive(references: Array[WeakRef]) -> bool:
	# 同步助手释放临时强引用后再等待，避免等待条件自身保持播放实例。
	for reference: WeakRef in references:
		if reference.get_ref() != null:
			return true
	return false


func _headless_entry_allowed() -> bool:
	return actor._base_input_allowed() and not actor.focus_controller.has_control()


func _settle_transfer() -> void:
	for iteration: int in range(90):
		await frames(1)
		if not telephone.is_transfer_pending():
			return
	check(false, "主场景事务超出测试等待上限")
