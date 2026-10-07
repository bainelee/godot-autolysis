extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 正式玩家、电话及面板的输入集成；只注入引擎内部事件。

const TELEPHONE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/machine_telephone_0.tscn")
const PLAYER: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")

var telephone: AutolysisTelephone
var records: Array[Dictionary] = []
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/input")


func check(condition: bool, description: String) -> void:
	super.check(condition, description)
	records.append({"说明": description, "通过": condition})


func run_checks() -> void:
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	var phone_scene: Node3D = TELEPHONE.instantiate()
	phone_scene.position = Vector3(0, 1.2, 0)
	world.add_child(phone_scene)
	telephone = phone_scene.get_node("StaticBody3D") as AutolysisTelephone
	player = PLAYER.instantiate()
	world.add_child(player)
	await reset_player(Vector3(0, 0.9, 1))
	var actor: AutolysisPlayer = player as AutolysisPlayer
	# 正式默认已关闭工具并取消键位；本专项显式启用保留的调节功能。
	actor.handset_pose_debug_enabled = true
	var original_pose_bindings: Array[InputEvent] = InputMap.action_get_events(actor.handset_pose_debug_action)
	var pose_key: InputEventKey = InputEventKey.new()
	pose_key.physical_keycode = KEY_P
	InputMap.action_add_event(actor.handset_pose_debug_action, pose_key)
	var inventory: AutolysisInventoryController = actor.inventory_controller
	var panel: AutolysisHandsetPoseDebug = actor.handset_pose_debug
	if DisplayServer.get_name() == "headless":
		# 与既有聚焦夹具一致，只替换无图形后端不存在的鼠标捕获状态。
		actor.focus_controller.configure(actor, actor.camera, actor.held_item_presenter, _headless_entry_allowed)
	print("电话输入进入前实际状态：", JSON.stringify({"聚焦状态": actor.focus_controller.state, "聚焦可进入": actor.focus_controller.can_enter(telephone.focus_target), "聚焦描述有效": telephone.focus_target.is_valid_target(), "玩家基础许可": actor._base_input_allowed(), "玩家交互许可": actor.is_interaction_input_allowed(), "鼠标模式": Input.mouse_mode, "玩家位置": str(actor.global_position), "电话配置错误": telephone.get_configuration_error(), "着地": actor.is_on_floor(), "落地眩晕": actor.is_landing_stunned}))
	check(actor.focus_controller.try_enter(telephone.focus_target), "真实电话可进入聚焦")
	await frames(20)
	check(telephone.can_take_handset(actor), "稳定聚焦实际空手可取筒")
	telephone.request_handset_transfer(actor)
	await _settle_transfer()
	check(inventory.has_exclusive_handset() and telephone.get_holder() == actor, "取筒同步完成后来源与玩家成对持有")
	await frames(3)
	check(panel.is_showing_pose() and panel.get_panel_rect().size.x > 0, "持有后正式右侧面板显示并布局")
	var revision: int = inventory.get_holding_revision()
	var holder_session: int = telephone.get_holder_session_id()
	var index: int = inventory.get_focused_index()
	var panel_point: Vector2 = panel.get_panel_rect().position + Vector2(12, 12)
	for button: int in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
		await _click(panel_point, button)
	check(inventory.get_holding_revision() == revision and telephone.get_holder_session_id() == holder_session and actor.focus_controller.is_focused_on(telephone.focus_target), "面板左右键与滚轮不穿透取放或聚焦退出")
	check(inventory.get_focused_index() == index, "面板滚轮不切换库存")
	var editors: Array[Node] = panel.find_children("*", "SpinBox", true, false)
	check(editors.size() == 6, "实际面板具有六项数值编辑")
	if editors.size() == 6:
		var field: SpinBox = editors[0] as SpinBox
		field.get_line_edit().grab_focus()
		await frames(2)
		check(actor.is_handset_text_editing() and not actor.is_focus_input_allowed(), "字段焦点阻断世界交互入队")
		var before_pending: int = actor.interaction_controller._pending_clicks.size()
		var interact_event: InputEventAction = InputEventAction.new()
		interact_event.action = &"interact_direct"
		interact_event.pressed = true
		actor.interaction_controller._unhandled_input(interact_event)
		check(actor.interaction_controller._pending_clicks.size() == before_pending and inventory.get_holding_revision() == revision, "文本占用时交互快捷请求不入队")
		field.get_line_edit().release_focus()
		await frames(2)
	var old_click: Dictionary = {
		"session": actor.focus_controller.session_id,
		"focus_target": telephone.focus_target,
		"index": index, "item": inventory.get_focused_item(),
		"instance": inventory.get_focused_instance(),
		"holding_revision": revision - 1,
		"mouse": actor.camera.unproject_position(telephone.handset_body.global_position),
		"left_mouse": true, "sequence": 999,
	}
	actor.interaction_controller._dispatch_focus_click(old_click)
	await frames(3)
	check(inventory.get_holding_revision() == revision and not telephone.is_transfer_pending(), "旧持物序号点击不得发起归还")
	check(actor.focus_controller.request_exit(), "持筒可正常退出聚焦")
	await frames(20)
	check(inventory.has_exclusive_handset() and not telephone.move_limit_shape.disabled and not actor.focus_controller.has_control(), "退出聚焦保留听筒及活动限位")
	_key(KEY_P)
	await frames(3)
	check(actor.is_handset_adjusting() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "实际快捷动作开放鼠标调节")
	var original_position: Vector3 = actor.global_position
	var original_rotation: Vector3 = actor.body.rotation
	Input.action_press("forward")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(30, 20)
	Input.parse_input_event(motion)
	await frames(12)
	Input.action_release("forward")
	check(actor.global_position.is_equal_approx(original_position) and actor.body.rotation.is_equal_approx(original_rotation), "普通调节态暂停移动及视角")
	check(inventory.has_exclusive_handset() and inventory.get_focused_index() == index and not telephone.move_limit_shape.disabled, "普通调节态保留独占与限位")
	panel.get_field(0).get_line_edit().grab_focus()
	await frames(1)
	_key(KEY_P)
	await frames(3)
	check(not actor.is_handset_adjusting() and not panel.has_text_focus() and actor._base_input_allowed(), "文本焦点期间再次快捷动作仍恢复普通输入许可")
	panel.test_enabled = false
	check(not actor.set_handset_adjusting(true), "关闭面板自身测试开关后不可进入隐藏调节态")
	panel.test_enabled = true
	actor.set_handset_adjusting(true)
	actor.is_showing_ui = true
	await frames(3)
	check(not actor.is_handset_adjusting() and inventory.has_exclusive_handset(), "菜单状态结束编辑并保留持筒")
	actor.is_showing_ui = false
	actor.update_mouse_mode()
	actor.set_handset_adjusting(true)
	paused = true
	await process_frame
	await process_frame
	check(not actor.is_handset_adjusting() and inventory.has_exclusive_handset() and not telephone.move_limit_shape.disabled, "场景暂停结束编辑但不解除持有")
	paused = false
	await frames(2)
	check(not actor.is_handset_adjusting(), "暂停恢复须再次显式开启编辑")
	actor.set_handset_adjusting(true)
	actor._on_handset_window_focus_exited()
	check(not actor.is_handset_adjusting() and inventory.has_exclusive_handset(), "窗口失焦结束编辑保留持有")
	actor._on_handset_window_focus_entered()
	check(not actor.is_handset_adjusting(), "窗口恢复不自动继续编辑")
	check(actor.focus_controller.try_enter(telephone.focus_target), "同一持有会话可重新聚焦原电话")
	await frames(20)
	check(telephone.can_return_handset(actor), "重入后原玩家可以归还")
	var position_field: SpinBox = panel.get_field(0)
	position_field.get_line_edit().grab_focus()
	position_field.get_line_edit().text = "-0.125"
	position_field.get_line_edit().text_changed.emit("-0.125")
	var handset_shape: CollisionShape3D = null
	for child: Node in telephone.handset_body.get_children():
		if child is CollisionShape3D:
			handset_shape = child as CollisionShape3D
	var world_point: Vector2 = actor.camera.unproject_position(handset_shape.global_position)
	check(not panel.get_panel_rect().has_point(world_point), "实际听筒点击像素位于面板矩形外")
	await _click(world_point, MOUSE_BUTTON_LEFT)
	await _settle_transfer()
	check(not actor.is_handset_text_editing(), "面板外业务点击先提交草稿并释放字段焦点")
	check(not inventory.has_exclusive_handset() and not panel.is_showing_pose() and telephone.move_limit_shape.disabled, "归还后面板隐藏并释放独占及限位")
	check(inventory.get_focused_index() == index, "整个持筒过程选中索引保持")
	panel.queue_free()
	await frames(2)
	telephone.request_handset_transfer(actor)
	await _settle_transfer()
	check(inventory.has_exclusive_handset(), "调节面板移除后仍可取筒")
	telephone.request_handset_transfer(actor)
	await _settle_transfer()
	check(not inventory.has_exclusive_handset(), "调节面板移除后仍可归还")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("电话输入结果.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"断言": records, "失败": failures, "输入方式": "无图形引擎内部事件及明确故障调用；没有系统指针操作"}, "\t"))
	report.close()
	InputMap.action_erase_events(actor.handset_pose_debug_action)
	for binding: InputEvent in original_pose_bindings:
		InputMap.action_add_event(actor.handset_pose_debug_action, binding)
	var playback_refs: Array[WeakRef] = []
	for node: Node in world.find_children("*", "AudioStreamPlayer3D", true, false):
		var audio: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		if audio.has_stream_playback():
			playback_refs.append(weakref(audio.get_stream_playback()))
	world.queue_free()
	await frames(3)
	var pending: int = 0
	for reference: WeakRef in playback_refs:
		if reference.get_ref() != null:
			pending += 1
	check(pending == 0, "原三帧读点被测实际播放实例已经全部退役")
	var retirement_report := FileAccess.open(evidence_directory.path_join("输入退出实际退役探针.json"), FileAccess.WRITE)
	retirement_report.store_string(JSON.stringify({"播放实例数": playback_refs.size(), "原三帧后存活数": pending, "断言": records, "失败数": failures}, "\t"))
	retirement_report.close()
	var deadline: int = Time.get_ticks_msec() + 2000
	while pending > 0 and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		await process_frame
		pending = 0
		for reference: WeakRef in playback_refs:
			if reference.get_ref() != null:
				pending += 1
	quit(1 if failures > 0 else 0)


func _settle_transfer() -> void:
	for iteration: int in range(90):
		await frames(1)
		if not telephone.is_transfer_pending():
			return
	check(false, "听筒事务必须在测试等待上限内结束")


func _headless_entry_allowed() -> bool:
	return player._base_input_allowed() and not player.focus_controller.has_control()


func _key(key: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.physical_keycode = key
	event.pressed = false
	Input.parse_input_event(event)


func _click(point: Vector2, button: MouseButton) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
	await frames(3)
