extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 正式电话与正式玩家集成；无图形只替换后端无法提供的鼠标捕获许可。

const MAIN_SCENE: PackedScene = preload("res://main-autolysis/scenes/01-autolysis-test.tscn")
const PHONE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/machine_telephone_0.tscn")
const BASELINE_PHONE: PackedScene = preload("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/baseline/main-autolysis/scenes/prefabs/prefab_machines/machine_telephone_0.tscn")
const BASELINE_MAIN: PackedScene = preload("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/baseline/main-autolysis/scenes/01-autolysis-test.tscn")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const PHONE_EXPORTS: Array[StringName] = [&"reference_camera", &"root_interaction", &"focus_target", &"handset_body", &"handset_interaction", &"handset_anchor", &"handset_visual", &"handset_visual_scene", &"move_limit_body", &"move_limit_shape", &"additional_move_limit_shapes", &"handset_held_position", &"handset_held_rotation_degrees", &"handset_held_scale", &"call_controller", &"handset_audio"]
## 删除前场景明确配置的区域，仅证明样本在旧区域外，不参与任何取筒许可。
const REMOVED_TAKE_BOUNDS: AABB = AABB(Vector3(-0.43, -1.3, 0), Vector3(2.28, 3.1, 2))

class FixtureTelephone extends AutolysisTelephone:
	var refuse_take: bool = false
	var refuse_return: bool = false
	var refuse_business_take: bool = false
	var refuse_business_return: bool = false
	var refuse_business_take_after_commit: bool = false
	var refuse_business_return_after_commit: bool = false

	func commit_handset_business_completion(returning: bool, actor: Node3D, session: int, transaction: int) -> bool:
		if (returning and refuse_business_return) or (not returning and refuse_business_take):
			return false
		var accepted: bool = super.commit_handset_business_completion(returning, actor, session, transaction)
		return accepted and not ((returning and refuse_business_return_after_commit) or (not returning and refuse_business_take_after_commit))

	func _commit_taken(actor: Variant, token: int) -> bool:
		return false if refuse_take else super._commit_taken(actor, token)

	func _commit_returned(actor: Variant, token: int) -> bool:
		return false if refuse_return else super._commit_returned(actor, token)

class FixturePresenter extends AutolysisHeldItemPresenter:
	var refuse_prepare: bool = false
	var refuse_commit: bool = false

	func prepare_handset(scene: PackedScene, position_value: Vector3, rotation_value: Vector3, scale_value: Vector3) -> Node3D:
		return null if refuse_prepare else super.prepare_handset(scene, position_value, rotation_value, scale_value)

	func commit_handset_prepared(visual: Node3D, source: Node3D, session: int) -> bool:
		return false if refuse_commit else super.commit_handset_prepared(visual, source, session)

var phone: AutolysisTelephone
var other_phone: AutolysisTelephone
var inventory: AutolysisInventoryController
var focus: AutolysisFocusController
var ray: AutolysisFocusRayQuery = AutolysisFocusRayQuery.new()
var records: Array[Dictionary] = []
var audio_exit_samples: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var sync_events: Array[Dictionary] = []
var motion_records: Array[Dictionary] = []
var position_records: Array[Dictionary] = []
var take_notifications: int = 0
var return_notifications: int = 0
var abort_notifications: int = 0
var held_notifications: int = 0
var observer_action: String = ""
var visibility_action: String = ""
var display_enter_action: String = ""
var holding_observer_action: String = ""
var completion_observer_action: String = ""
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/device")


func check(condition: bool, description: String) -> void:
	super.check(condition, description)
	records.append({"说明": description, "通过": condition})


func run_checks() -> void:
	root.size = Vector2i(1280, 720)
	await _new_scene()
	if OS.get_cmdline_user_args().has("--take-position-regression-only"):
		await _test_safe_take_positions()
	else:
		_test_asset_migration()
		await _test_focus_queries()
		await _test_safe_take_positions()
		await _test_paired_holding()
		await _test_cancel_pause_and_old_callbacks()
		await _test_failure_rollback()
		await _test_visibility_callback_boundaries()
		await _test_local_dependency_lifecycle()
		await _test_asset_variants()
		await _test_observer_release()
	var audio_references: Array[Dictionary] = _capture_audio_exit_refs()
	for action: StringName in [&"forward", &"back", &"left", &"right", &"sprint", &"crouch"]:
		Input.action_release(action)
	paused = false
	if is_instance_valid(world):
		world.queue_free()
	await frames(2)
	await _await_audio_exit_release(audio_references, "原两帧清理后")
	_save_report()
	print("电话设备断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)


func _capture_audio_exit_refs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in world.find_children("*", "", true, false):
		if (node is AudioStreamPlayer or node is AudioStreamPlayer3D) and node.has_stream_playback():
			var playback: AudioStreamPlayback = node.get_stream_playback()
			result.append({"source": str(node.get_path()), "id": playback.get_instance_id(), "class": playback.get_class(), "reference": weakref(playback)})
	return result


func _audio_exit_state(references: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for info: Dictionary in references:
		# 临时强查询只在同步函数内存活，不跨等待保留播放实例。
		var playback: RefCounted = (info.reference as WeakRef).get_ref()
		result.append({"来源": info.source, "播放身份": info.id, "播放类型": info["class"], "仍存活": is_instance_valid(playback), "临时查询在内的引用数": playback.get_reference_count() if is_instance_valid(playback) else 0})
	return result


func _audio_exit_pending(references: Array[Dictionary]) -> bool:
	for info: Dictionary in references:
		if is_instance_valid((info.reference as WeakRef).get_ref()):
			return true
	return false


func _await_audio_exit_release(references: Array[Dictionary], cleanup_label: String = "原三帧清理后") -> void:
	audio_exit_samples.append({"阶段": cleanup_label, "墙钟微秒": Time.get_ticks_usec(), "混音时钟": AudioServer.get_time_since_last_mix(), "播放": _audio_exit_state(references)})
	var deadline: int = Time.get_ticks_usec() + 2000000
	while _audio_exit_pending(references) and Time.get_ticks_usec() < deadline:
		# 退出只观察实际服务器引用解除；一毫秒让线程调度，两秒仅是验收超时。
		OS.delay_msec(1)
		await process_frame
	audio_exit_samples.append({"阶段": "实际播放退役完成", "墙钟微秒": Time.get_ticks_usec(), "混音时钟": AudioServer.get_time_since_last_mix(), "播放": _audio_exit_state(references)})
	check(not _audio_exit_pending(references), "退出前实际声音播放实例已解除全部引用")


func _new_scene(fixture: bool = false) -> void:
	paused = false
	for action: StringName in [&"forward", &"back", &"left", &"right", &"sprint", &"crouch"]:
		Input.action_release(action)
	if is_instance_valid(world):
		world.queue_free()
		await frames(2)
	world = MAIN_SCENE.instantiate()
	player = world.get_node("autolysis_player")
	phone = world.get_node("interaction_prefabs/machines/MachineTelephone0/StaticBody3D")
	if fixture:
		var exported: Dictionary = {}
		for property: StringName in PHONE_EXPORTS:
			exported[property] = phone.get(property)
		phone.set_script(FixtureTelephone)
		for property: StringName in PHONE_EXPORTS:
			phone.set(property, exported[property])
		player.get_node("Body/Neck/Head/Wieldables/HeldItemPresenter").set_script(FixturePresenter)
	root.add_child(world)
	player.set_physics_process(false)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(-9.35, 0.8005, 11))
	player.body.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.is_movement_paused = false
	player.is_showing_ui = false
	player._clear_landing_stun()
	inventory = player.inventory_controller
	focus = player.focus_controller
	if DisplayServer.get_name() == "headless":
		focus.configure(player, player.camera, player.held_item_presenter, _headless_entry)
		inventory.configure(player.held_item_presenter, _headless_inventory_input)
	take_notifications = 0
	return_notifications = 0
	abort_notifications = 0
	held_notifications = 0
	observer_action = ""
	visibility_action = ""
	display_enter_action = ""
	holding_observer_action = ""
	completion_observer_action = ""
	phone.handset_taken.connect(_on_taken)
	phone.handset_returned.connect(_on_returned)
	phone.handset_aborted.connect(_on_aborted)
	phone.limit_sync_observed.connect(_on_sync)
	phone.handset_visual.visibility_changed.connect(_on_visibility_changed)
	player.held_item_presenter.child_entered_tree.connect(_on_handset_display_entered)
	inventory.held_item_changed.connect(_on_held_changed)
	var other_root: Node3D = PHONE_SCENE.instantiate()
	other_root.position = Vector3(10, 1.2, 12)
	world.add_child(other_root)
	other_phone = other_root.get_node("StaticBody3D")
	await frames(3)


func _headless_entry() -> bool:
	return player._base_input_allowed() and not focus.has_control()


func _headless_inventory_input() -> bool:
	return player._base_input_allowed()


func _wait(condition: Callable, label: String, maximum: int = 120) -> bool:
	for index: int in maximum:
		if condition.call() == true:
			return true
		await frames(1)
	check(false, "等待上限仅用于验收失败：" + label)
	return false


func _enter() -> void:
	check(phone.root_interaction.try_interact(player, AutolysisInteractionComponent.InteractionMode.FOCUS), "正式根组件分发进入电话聚焦")
	await _wait(func() -> bool: return focus.state == AutolysisFocusController.FocusState.FOCUSED, "电话稳定聚焦")


func _take() -> void:
	check(phone.handset_interaction.try_interact(player), "正式听筒组件分发取下请求")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "取筒真实限位同步与提交")
	check(inventory.has_exclusive_handset() and phone.get_holder() == player, "取筒提交完成后两侧占用一致")


func _return() -> void:
	check(phone.handset_interaction.try_interact(player), "正式听筒组件分发归还请求")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "归还真实限位同步与提交")
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null, "归还提交完成后两侧占用清除")


func _exit_focus() -> void:
	check(focus.request_exit(), "电话聚焦可以正常退出")
	await _wait(func() -> bool: return not focus.has_control(), "聚焦恢复普通相机")


func _test_asset_migration() -> void:
	var old: Node3D = BASELINE_PHONE.instantiate()
	world.add_child(old)
	old.global_transform = phone.get_parent().global_transform
	check(old.get_node("focus_camera").global_transform.is_equal_approx(phone.reference_camera.global_transform), "原电话聚焦相机迁移后的实际全局变换保持")
	check(is_equal_approx(old.get_node("focus_camera").fov, phone.reference_camera.fov), "原电话聚焦相机场角保持")
	check(old.get_node("StaticBody3D/collision_phone_hand_set_interaction").global_transform.is_equal_approx(phone.handset_body.get_node("collision_phone_hand_set_interaction").global_transform), "听筒独立物理入口迁移保持实际全局变换")
	# 限位变换由用户当前资产决定；不再用首次迁移快照固定其位置。
	var old_visual: Node3D = old.get_node("StaticBody3D/phone_hand_set")
	check(old_visual.global_transform.is_equal_approx(phone.handset_anchor.global_transform), "听筒挂机锚点原场景实际全局变换保持")
	var old_meshes: Array[Node] = old_visual.find_children("*", "MeshInstance3D", true, false)
	var new_meshes: Array[Node] = phone.handset_visual.find_children("*", "MeshInstance3D", true, false)
	check(old_meshes.size() == 5 and new_meshes.size() == old_meshes.size(), "纯模型提取保留原资产实际五个网格")
	for original: MeshInstance3D in old_meshes:
		var relative_path: NodePath = old_visual.get_path_to(original)
		var extracted: MeshInstance3D = phone.handset_visual.get_node(relative_path)
		check(original.mesh.size.is_equal_approx(extracted.mesh.size), "提取网格尺寸与来源一致：" + str(relative_path) + "（来源网格路径）")
		check(original.material_override.resource_path == extracted.material_override.resource_path, "提取网格材质与来源一致：" + str(relative_path) + "（来源网格路径）")
		check((old_visual.global_transform.affine_inverse() * original.global_transform).is_equal_approx(phone.handset_visual.global_transform.affine_inverse() * extracted.global_transform), "提取网格相对变换与来源一致：" + str(relative_path) + "（来源网格路径）")
	var definition: AutolysisItemDefinition = AutolysisItemDefinition.new()
	definition.item_id = &"telephone_handset_test"
	definition.display_name = "听筒诊断模型"
	definition.visual_scene = phone.handset_visual_scene
	check(definition.is_valid_definition(), "共享纯模型无业务脚本、碰撞或交互分组")
	var baseline_main_state: SceneState = BASELINE_MAIN.get_state()
	var found_main_transform: bool = false
	for index: int in baseline_main_state.get_node_count():
		if String(baseline_main_state.get_node_path(index)).ends_with("interaction_prefabs/machines/MachineTelephone0"):
			for property_index: int in baseline_main_state.get_node_property_count(index):
				if baseline_main_state.get_node_property_name(index, property_index) == &"transform":
					found_main_transform = true
					check(phone.get_parent().transform.is_equal_approx(baseline_main_state.get_node_property_value(index, property_index)), "正式主场景电话实例变换保持实施前基线")
	check(found_main_transform, "实际读取实施前主场景电话实例变换来源")
	old.queue_free()


func _test_focus_queries() -> void:
	check(phone.is_configured() and phone.focus_target.is_valid_target(), "电话明确聚焦登记有效")
	check(phone.move_limit_shape.disabled and other_phone.move_limit_shape.disabled, "各电话限位初始停用")
	check(not phone.can_take_handset(player), "普通模式不直接取下听筒")
	var base_shape: CollisionShape3D = phone.get_node("collision_base")
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(phone.reference_camera.global_position, base_shape.global_position, 3, [player.get_rid()])
	var first: Dictionary = phone.get_world_3d().direct_space_state.intersect_ray(query)
	check(first.get("collider") == phone, "普通掩码实际射线命中基座且不会被听筒内部层遮挡")
	check(phone.root_interaction.try_interact(player, AutolysisInteractionComponent.InteractionMode.FOCUS), "电话基座接受聚焦请求")
	check(not phone.can_take_handset(player), "聚焦过渡期间拒绝取筒")
	await _wait(func() -> bool: return focus.state == AutolysisFocusController.FocusState.FOCUSED, "首次聚焦")
	var handset_shape: CollisionShape3D = phone.handset_body.get_node("collision_phone_hand_set_interaction")
	var pixel: Vector2 = player.camera.unproject_position(handset_shape.global_position)
	check(ray.query_target(player.camera, pixel, phone.focus_target, [player.get_rid()]) == phone.handset_body, "稳定聚焦真实射线首命中解析唯一听筒入口")
	var blocker: StaticBody3D = box(Vector3(0.25, 0.5, 0.1), player.camera.global_position.lerp(handset_shape.global_position, 0.5))
	await frames(2)
	check(ray.query_target(player.camera, pixel, phone.focus_target, [player.get_rid()]) == null, "真实外部首命中遮挡不被电话分支穿透")
	blocker.collision_layer = 32
	await frames(2)
	check(ray.query_target(player.camera, pixel, phone.focus_target, [player.get_rid()]) == null, "未登记内部层物体不能借用电话入口")
	blocker.queue_free()
	await frames(2)
	check(ray.query_target(player.camera, pixel, phone.focus_target, [player.get_rid()]) == phone.handset_body, "遮挡移除后同一真实射线恢复听筒入口")
	await _exit_focus()


func _test_safe_take_positions() -> void:
	await _new_scene()
	player.global_position = Vector3(-8.4, 0.8005, 11)
	var base_shape: CollisionShape3D = phone.get_node("collision_base")
	var origin: Vector3 = player.camera.global_position
	var direction: Vector3 = (base_shape.global_position - origin).normalized()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * 2.0, 3, [player.get_rid()])
	check(phone.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == phone, "实际边界外身体位置仍可在普通两米射线范围命中电话根")
	await _enter()
	check(not REMOVED_TAKE_BOUNDS.has_point(phone.to_local(player.global_position)), "正式根射线可达的玩家样本位于已删除的旧取筒区域外")
	await _position_take_and_return("旧取筒区域外正式站位")
	for sample: String in ["贴近当前限位", "重叠当前限位", "零实体层重叠当前限位"]:
		await _new_scene()
		await _enter()
		var target: Vector3 = phone.move_limit_shape.global_position
		if sample == "贴近当前限位":
			var separation: float = phone.move_limit_shape.shape.size.x * 0.5 + player.standing_collision_shape.shape.size.x * 0.5 + 0.02
			target += phone.move_limit_shape.global_basis.x.normalized() * separation
		target.y = player.global_position.y
		player.global_position = target
		await frames(2)
		var overlapping: bool = _limit_intersects_player()
		check(not overlapping if sample == "贴近当前限位" else overlapping, sample + "样本由用户当前真实限位变换构造且几何事实经过实际查询")
		if sample == "零实体层重叠当前限位":
			player.collision_layer = 0
		await _position_take_and_return(sample)
	await _new_scene()
	await _enter()
	var requested: bool = phone.handset_interaction.try_interact(player)
	check(requested and phone.is_transfer_pending(), "位置变更样本通过正式入口建立取下预处理")
	player.global_position = phone.to_global(Vector3(-3, -0.3995, 1))
	phone.move_limit_shape.global_position = Vector3(player.global_position.x, phone.move_limit_shape.global_position.y, player.global_position.z)
	await _position_take_and_return("预处理后玩家移出旧区域且真实限位移入身体", requested)
	for boundary: String in ["同步确认", "来源提交可见性", "持物通知", "完成通知"]:
		await _new_scene()
		await _enter()
		match boundary:
			"同步确认":
				observer_action = "move-outside-on-confirm"
			"来源提交可见性":
				visibility_action = "move-overlap"
			"持物通知":
				holding_observer_action = "move-outside"
			"完成通知":
				completion_observer_action = "move-overlap"
		await _position_take_and_return(boundary + "回调只改变玩家几何站位")
	await _new_scene()
	await _enter()
	player.collision_mask = 1
	check(not phone.can_take_handset(player), "玩家实际掩码缺限位层时拒绝取筒")
	player.collision_mask = 9
	phone.move_limit_body.collision_layer = 1
	check(not phone.can_take_handset(player), "限位层失效时仅拒绝取筒")
	phone.move_limit_body.collision_layer = 8


func _position_take_and_return(label: String, already_requested: bool = false) -> void:
	var before_take: int = take_notifications
	var before_return: int = return_notifications
	var before_abort: int = abort_notifications
	var requested: bool = already_requested or phone.handset_interaction.try_interact(player)
	check(requested, label + "通过正式听筒入口接受取下")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), label + "等待真实启用或回滚完成")
	var held: bool = inventory.has_exclusive_handset() and phone.get_holder() == player and inventory.get_handset_session_id() == phone.get_holder_session_id()
	position_records.append({"阶段": label, "请求已分发": requested, "双方正常持有": held, "玩家全局位置": _vector(player.global_position), "当前真实限位位置": _vector(phone.move_limit_shape.global_position), "旧区域包含玩家原点": REMOVED_TAKE_BOUNDS.has_point(phone.to_local(player.global_position)), "玩家实体层": player.collision_layer, "来源与库存占用序号": [phone.get_holder_session_id(), inventory.get_handset_session_id()]})
	check(held, label + "不因距离、区域或重叠取消正常成对取下")
	if not held:
		return
	check(not phone.move_limit_shape.disabled and phone._shape_is_active_in_world(phone.move_limit_shape), label + "限位实际在物理世界启用")
	await frames(2)
	check(inventory.has_exclusive_handset() and phone.get_holder() == player and take_notifications == before_take + 1 and abort_notifications == before_abort, label + "提交与通知后仍持筒且正常完成只通知一次")
	await _return()
	check(phone.move_limit_shape.disabled and not phone._shape_is_active_in_world(phone.move_limit_shape) and return_notifications == before_return + 1, label + "正式归还后实际限位停用且完成一次")


func _limit_intersects_player() -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = phone.move_limit_shape.shape
	query.transform = phone.move_limit_shape.global_transform
	query.collision_mask = player.collision_layer
	while true:
		var hits: Array[Dictionary] = phone.get_world_3d().direct_space_state.intersect_shape(query)
		var exclusions: Array[RID] = query.exclude
		var added: bool = false
		for hit: Dictionary in hits:
			var hit_rid: RID = hit.get("rid", RID())
			if hit_rid == player.get_rid():
				return true
			if not exclusions.has(hit_rid):
				exclusions.append(hit_rid)
				added = true
		if not added:
			return false
		query.exclude = exclusions
	return false


func _test_paired_holding() -> void:
	var stored: AutolysisItemInstance = AutolysisItemInstance.create(CAFFEINE)
	inventory._slots[1] = stored
	var initial_index: int = inventory.get_focused_index()
	var revision: int = inventory.get_holding_revision()
	for index: int in 3:
		check(phone.can_take_handset(player), "只读取筒查询不改变空手状态")
	check(phone.handset_visual.visible and phone.move_limit_shape.disabled and not inventory.get_handset_transfer_pending() and inventory.get_holding_revision() == revision, "只读许可不创建占用、不切换限位或隐藏挂机展示")
	await _take()
	var session: int = inventory.get_handset_session_id()
	check(session == phone.get_holder_session_id() and session > 0 and inventory.get_holding_revision() == revision + 1, "双方来源会话匹配且持物序号只增加一次")
	check(not phone.handset_visual.visible and inventory.get_handset_display().visible and not phone.move_limit_shape.disabled and phone._shape_is_active_in_world(phone.move_limit_shape), "取下只显示玩家听筒并确认真实限位启用")
	check(take_notifications == 1 and held_notifications == 1, "取下完成和持物观察通知各一次")
	check(inventory.get_focused_instance() == null and not inventory.is_actually_empty_handed(), "当前格为空与实际空手明确区分")
	check(inventory.get_slot_instance(1) == stored and inventory.get_focused_index() == initial_index, "其他格原实例和选中索引保持")
	check(not inventory.cycle_focus(1) and not inventory.cycle_focus(-1), "权威选格入口两个方向拒绝持筒切换")
	await _exit_focus()
	check(inventory.get_handset_session_id() == session and not phone.move_limit_shape.disabled, "正常退出聚焦保留持筒会话和限位")
	check(not player._handset_movement_guarded(), "稳定持筒已解除短暂同步移动保护")
	check(other_phone.root_interaction.try_interact(player, AutolysisInteractionComponent.InteractionMode.FOCUS), "持筒不扩大为禁止进入另一电话聚焦")
	await _wait(func() -> bool: return focus.state == AutolysisFocusController.FocusState.FOCUSED, "另一电话聚焦")
	check(not other_phone.can_take_handset(player) and not other_phone.can_return_handset(player), "另一电话不能取第二听筒或解除原来源会话")
	await _exit_focus()
	await _enter()
	var handset_shape: CollisionShape3D = phone.handset_body.get_node("collision_phone_hand_set_interaction")
	check(ray.query_target(player.camera, player.camera.unproject_position(handset_shape.global_position), phone.focus_target, [player.get_rid()]) == phone.handset_body, "挂机模型隐藏后原交互区仍由真实射线命中")
	await _return()
	check(phone.handset_visual.visible and inventory.get_handset_display() == null and phone.move_limit_shape.disabled and not phone._shape_is_active_in_world(phone.move_limit_shape), "放回只显示挂机听筒且真实限位停用")
	check(return_notifications == 1 and take_notifications == 1 and held_notifications == 2, "取放完成和持物观察各按成功次数通知")
	check(inventory.get_slot_instance(1) == stored and inventory.get_focused_index() == initial_index and other_phone.move_limit_shape.disabled, "归还保留库存身份且不修改另一电话限位")
	check(inventory.cycle_focus(1) and inventory.cycle_focus(-1), "放回后权威选格入口两个方向恢复")
	_snapshot("正式取放完成")


func _test_cancel_pause_and_old_callbacks() -> void:
	check(phone.request_handset_transfer(player), "开始取下预处理")
	check(player._handset_movement_guarded() and inventory.get_handset_transfer_pending(), "启用待同步期间维持移动保护和库存互斥")
	phone.cancel_handset_transfer()
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "取消取下恢复真实停用")
	check(not inventory.has_exclusive_handset() and phone.move_limit_shape.disabled and not player._handset_movement_guarded(), "取下取消恢复挂机并在实际停用后解除保护")
	observer_action = "cancel-on-write"
	check(phone.request_handset_transfer(player), "开始延后写入回调取消用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "写入观察取消恢复")
	check(not inventory.has_exclusive_handset() and phone.move_limit_shape.disabled, "旧延后启用回调不覆盖取消后的停用目标")
	observer_action = "cancel-on-confirm"
	check(phone.request_handset_transfer(player), "开始同步观察重入取消用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "同步观察取消恢复")
	check(not inventory.has_exclusive_handset() and phone.move_limit_shape.disabled, "同步确认观察重入取消不会提交旧取筒请求")
	check(phone.request_handset_transfer(player), "开始取下后立即全局暂停")
	paused = true
	await frames(3)
	check(inventory.get_handset_transfer_pending() and not inventory.has_exclusive_handset() and player._handset_movement_guarded(), "全局暂停保留取下预处理和保护而不提前提交")
	paused = false
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "暂停恢复取下")
	check(inventory.has_exclusive_handset(), "恢复后同一取下事务提交成功")
	var held_session: int = inventory.get_handset_session_id()
	check(phone.request_handset_transfer(player), "开始归还后显式取消")
	phone.cancel_handset_transfer()
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "归还取消恢复启用")
	check(inventory.get_handset_session_id() == held_session and not phone.move_limit_shape.disabled and phone._shape_is_active_in_world(phone.move_limit_shape), "归还取消保持原持有和真实限位启用")
	await _return()
	await _take()
	var current_session: int = inventory.get_handset_session_id()
	phone.abort_handset_holder(player, held_session, "旧会话测试回调")
	phone._apply_limit_target(1, false)
	await frames(2)
	check(inventory.get_handset_session_id() == current_session and current_session != held_session and not phone.move_limit_shape.disabled, "旧来源会话清理和旧限位序号不清除后来持有")
	await _return()
	check(phone.request_handset_transfer(player), "开始取下后退出聚焦")
	check(focus.request_exit(), "待同步取下可请求退出聚焦")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "退出造成取下回滚")
	check(not inventory.has_exclusive_handset() and phone.move_limit_shape.disabled and not player._handset_movement_guarded(), "取下待同步退出完成限位恢复后解除保护")
	await _wait(func() -> bool: return not focus.has_control(), "退出相机恢复")


func _test_failure_rollback() -> void:
	await _new_scene(true)
	await _enter()
	var fixture: FixtureTelephone = phone as FixtureTelephone
	var presenter: FixturePresenter = player.held_item_presenter as FixturePresenter
	presenter.refuse_prepare = true
	check(not phone.request_handset_transfer(player), "候选准备失败不进入电话碰撞预处理")
	check(phone.handset_visual.visible and phone.move_limit_shape.disabled and not inventory.get_handset_transfer_pending(), "候选失败保持挂机与停用状态")
	presenter.refuse_prepare = false
	presenter.refuse_commit = true
	check(phone.request_handset_transfer(player), "开始手持呈现提交失败用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "呈现失败回滚")
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and phone.handset_visual.visible and phone.move_limit_shape.disabled and not player._handset_movement_guarded(), "呈现提交失败成对回滚并恢复真实限位停用")
	presenter.refuse_commit = false
	fixture.refuse_take = true
	check(phone.request_handset_transfer(player), "开始来源取下拒绝用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "来源拒绝取下回滚")
	check(not inventory.has_exclusive_handset() and phone.move_limit_shape.disabled, "来源拒绝取下不留下半提交")
	fixture.refuse_take = false
	await _take()
	var session: int = inventory.get_handset_session_id()
	fixture.refuse_return = true
	check(phone.request_handset_transfer(player), "开始来源归还拒绝用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "来源拒绝归还恢复")
	check(inventory.get_handset_session_id() == session and phone.get_holder_session_id() == session and not phone.handset_visual.visible and not phone.move_limit_shape.disabled and phone._shape_is_active_in_world(phone.move_limit_shape), "归还提交失败保持匹配持有、切换锁与实际边界")
	fixture.refuse_return = false
	await _return()
	check(take_notifications == 1 and return_notifications == 1, "所有失败预处理均不发布玩家成功取放通知")


func _test_local_dependency_lifecycle() -> void:
	await _new_scene()
	await _enter()
	await _take()
	var session: int = inventory.get_handset_session_id()
	var camera_transform: Transform3D = phone.reference_camera.transform
	var camera_fov: float = phone.reference_camera.fov
	phone.reference_camera.queue_free()
	await frames(3)
	check(not focus.has_control() and inventory.get_handset_session_id() == session and not phone.move_limit_shape.disabled, "仅聚焦相机释放终止聚焦而保留持筒和限位")
	var replacement: Camera3D = Camera3D.new()
	replacement.transform = camera_transform
	replacement.fov = camera_fov
	phone.add_child(replacement)
	phone.reference_camera = replacement
	check(phone.focus_target.configure_telephone(phone, replacement, phone.root_interaction, phone.handset_body, phone.handset_interaction), "替换相机后显式重新登记聚焦引用")
	await _enter()
	await _return()
	await _take()
	player.collision_mask = 1
	await frames(3)
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and phone.move_limit_shape.disabled and abort_notifications == 1 and not player._handset_movement_guarded(), "持有中实际玩家掩码失效按匹配会话异常清理并停用边界")
	player.collision_mask = 9
	await _take()
	phone.move_limit_shape.queue_free()
	check(phone.request_handset_transfer(player), "限位已排队释放仍可安全请求原来源归还")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "缺失限位安全归还")
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and not phone.last_limit_recovery_reason.is_empty(), "必要限位缺失的安全归还记录实际原因并清除占用")
	await _new_scene()
	await _enter()
	await _take()
	phone.move_limit_body.queue_free()
	await frames(4)
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and phone.handset_visual.visible and not player._handset_movement_guarded(), "持有中限位物理体释放终止匹配会话且不留下永久移动保护")
	await _new_scene()
	await _enter()
	await _take()
	var old_display: Node3D = inventory.get_handset_display()
	session = inventory.get_handset_session_id()
	old_display.queue_free()
	await frames(3)
	check(inventory.get_handset_session_id() == session and inventory.get_handset_display() != old_display and inventory.get_handset_display() != null and not phone.move_limit_shape.disabled, "仅玩家显示实例释放按当前配置恢复而保留来源会话")
	await _return()


func _test_visibility_callback_boundaries() -> void:
	await _new_scene()
	await _enter()
	visibility_action = "cancel"
	check(phone.request_handset_transfer(player), "开始取下可见性观察取消用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "可见性取消取下恢复")
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and phone.handset_visual.visible and phone.move_limit_shape.disabled and take_notifications == 0, "取下隐藏观察显式取消不伪报提交或留下半占用")
	await _take()
	var session: int = inventory.get_handset_session_id()
	visibility_action = "cancel"
	check(phone.request_handset_transfer(player), "开始归还可见性观察取消用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "可见性取消归还恢复")
	check(inventory.get_handset_session_id() == session and phone.get_holder_session_id() == session and not phone.handset_visual.visible and not phone.move_limit_shape.disabled and phone._shape_is_active_in_world(phone.move_limit_shape) and return_notifications == 0, "归还显示观察取消按提交前持有恢复真实启用边界")
	await _return()
	visibility_action = "abort"
	check(phone.request_handset_transfer(player), "开始取下可见性观察异常终止用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "可见性异常清理取下")
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and phone.handset_visual.visible and phone.move_limit_shape.disabled and not player._handset_movement_guarded(), "取下可见性观察异常终止不留下旧事务或永久保护")
	await _take()
	visibility_action = "abort"
	check(phone.request_handset_transfer(player), "开始归还可见性观察异常终止用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "可见性异常清理归还")
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and phone.handset_visual.visible and phone.move_limit_shape.disabled and not player._handset_movement_guarded(), "归还可见性观察异常终止不会回滚为失效持有")
	await _new_scene()
	await _enter()
	visibility_action = "release-limit"
	check(phone.request_handset_transfer(player), "开始取下隐藏观察立即释放必要限位用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "可见性释放限位后的预处理回滚")
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and phone.handset_visual.visible and take_notifications == 0 and not player._handset_movement_guarded(), "隐藏观察释放必要限位不发成功取下并成对恢复")
	await _new_scene()
	await _enter()
	display_enter_action = "release-limit"
	check(phone.request_handset_transfer(player), "开始手持显示入树立即释放必要限位用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "显示入树释放限位后的清理")
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and phone.handset_visual.visible and take_notifications == 0 and not player._handset_movement_guarded(), "显示入树释放必要限位在正常完成前清理匹配会话")
	await _new_scene()
	await _enter()
	holding_observer_action = "release-limit"
	check(phone.request_handset_transfer(player), "开始持物观察立即释放必要限位用例")
	await _wait(func() -> bool: return not phone.is_transfer_pending(), "持物观察释放限位后的清理")
	check(not inventory.has_exclusive_handset() and phone.get_holder() == null and phone.handset_visual.visible and take_notifications == 0 and not player._handset_movement_guarded(), "持物观察释放必要限位不继续发电话正常取下完成")
	await _new_scene()
	await _enter()
	completion_observer_action = "cancel"
	await _take()
	check(not phone.move_limit_shape.disabled and inventory.has_exclusive_handset(), "已提交取下的完成观察不能取消回未持有边界")
	completion_observer_action = "cancel"
	await _return()
	await frames(2)
	check(phone.move_limit_shape.disabled and not inventory.has_exclusive_handset(), "已提交归还的完成观察不能重启临时边界")


func _test_observer_release() -> void:
	# 引擎禁止立即释放正在发出信号的来源；来源释放使用真实允许的排队释放路径。
	for action: String in ["free-player-on-confirm", "free-inventory-on-confirm", "free-source-on-confirm", "immediate-player-on-confirm", "immediate-inventory-on-confirm"]:
		await _new_scene()
		await _enter()
		observer_action = action
		check(phone.request_handset_transfer(player), "开始同步观察释放边界：" + action + "（释放故障注入标识）")
		await frames(6)
		if action == "free-source-on-confirm":
			check(not is_instance_valid(phone) and not inventory.has_exclusive_handset() and not inventory.get_handset_transfer_pending() and not player._handset_movement_guarded(), "同步确认观察释放来源后没有库存占用或保护残留")
		else:
			check(phone.get_holder() == null and phone.move_limit_shape.disabled and not phone.is_transfer_pending(), "同步确认观察释放玩家或库存后来源恢复挂机及限位停用")
	await _new_scene()
	await _enter()
	await _take()
	phone.queue_free()
	await frames(4)
	check(not inventory.has_exclusive_handset() and inventory.get_handset_display() == null and not player._handset_movement_guarded(), "稳定持有的来源卸载清除显示与独占并释放移动保护")


func _test_asset_variants() -> void:
	await _new_scene()
	var variant_holder: Node3D = Node3D.new()
	phone.add_child(variant_holder)
	phone.handset_anchor.reparent(variant_holder, true)
	phone.handset_anchor.position += Vector3(0.08, -0.03, 0.06)
	phone.handset_anchor.rotation_degrees = Vector3(0, 12, -5)
	phone.handset_body.reparent(variant_holder, true)
	phone.handset_body.name = "RenamedHandsetBody"
	phone.rotation.y += deg_to_rad(35)
	phone.handset_held_position = Vector3(-0.31, 0.06, -0.73)
	phone.handset_held_rotation_degrees = Vector3(42, -37, 81)
	phone.handset_held_scale = Vector3(0.83, 0.83, 0.83)
	player.global_position = phone.to_global(Vector3(0, -0.3995, 1))
	player.global_basis = phone.global_basis
	await frames(2)
	check(phone.is_configured(), "电话实例旋转及听筒引用重组改名不因旧名称层级失效")
	await _enter()
	await _take()
	var display: Node3D = inventory.get_handset_display()
	check(display.position.is_equal_approx(phone.handset_held_position) and display.rotation_degrees.is_equal_approx(phone.handset_held_rotation_degrees) and display.scale.is_equal_approx(phone.handset_held_scale), "有效独立六轴及缩放配置精确应用到本次纯模型")
	var exported_position: Vector3 = phone.handset_held_position
	var exported_rotation: Vector3 = phone.handset_held_rotation_degrees
	var cached_position: Vector3 = Vector3(-0.1234567, 0.2345678, -0.7654321)
	var cached_rotation: Vector3 = Vector3(-23.4567, 34.5678, 145.6789)
	check(inventory.apply_handset_pose(phone, display, inventory.get_handset_session_id(), cached_position, cached_rotation), "变体听筒当前运行姿态可调节")
	await _return()
	await _take()
	check(inventory.get_handset_display().position.is_equal_approx(cached_position) and inventory.get_handset_display().rotation_degrees.is_equal_approx(cached_rotation), "同来源放回再取沿用本次运行缓存")
	check(phone.handset_held_position == exported_position and phone.handset_held_rotation_degrees == exported_rotation, "调节缓存不修改电话导出配置或共享模型资源")
	player.handset_pose_debug.queue_free()
	await frames(2)
	check(phone.can_return_handset(player) and inventory.has_exclusive_handset(), "仅调节面板释放不解除持有也不阻止原电话归还")
	await _return()
	check(phone.handset_visual.visible and phone.handset_anchor.rotation_degrees.is_equal_approx(Vector3(0, 12, -5)), "归还变体听筒保持用户配置的挂机锚点姿态")
	await _new_scene()
	await _enter()
	await _take()
	check(inventory.get_handset_display().position.is_equal_approx(phone.handset_held_position) and inventory.get_handset_display().rotation_degrees.is_equal_approx(phone.handset_held_rotation_degrees), "重新载入正式场景恢复电话导出起值而不沿用前场景缓存")
	await _return()


func _on_taken(_actor: Node3D, _session: int) -> void:
	take_notifications += 1
	if completion_observer_action == "cancel":
		completion_observer_action = ""
		phone.cancel_handset_transfer()
	elif completion_observer_action == "move-overlap":
		completion_observer_action = ""
		_move_player_overlapping_current_limit()


func _on_returned(_actor: Node3D, _session: int) -> void:
	return_notifications += 1
	if completion_observer_action == "cancel":
		completion_observer_action = ""
		phone.cancel_handset_transfer()


func _on_aborted(_actor: Node3D, _session: int, _reason: String) -> void:
	abort_notifications += 1


func _on_held_changed() -> void:
	held_notifications += 1
	if holding_observer_action == "release-limit" and inventory.has_exclusive_handset():
		holding_observer_action = ""
		phone.move_limit_shape.free()
	elif holding_observer_action == "move-outside" and inventory.has_exclusive_handset():
		holding_observer_action = ""
		player.global_position = phone.to_global(Vector3(-3, -0.3995, 1))


func _on_visibility_changed() -> void:
	var action: String = visibility_action
	visibility_action = ""
	if action == "cancel":
		phone.cancel_handset_transfer()
	elif action == "abort":
		var session: int = phone.get_holder_session_id() if phone.get_holder_session_id() > 0 else phone._return_holder_session
		inventory.abort_handset_session(phone, session, "来源可见性回调中的测试异常终止")
	elif action == "release-limit":
		phone.move_limit_shape.free()
	elif action == "move-overlap":
		_move_player_overlapping_current_limit()


func _move_player_overlapping_current_limit() -> void:
	player.global_position = Vector3(phone.move_limit_shape.global_position.x, player.global_position.y, phone.move_limit_shape.global_position.z)


func _on_handset_display_entered(_node: Node) -> void:
	if display_enter_action == "release-limit":
		display_enter_action = ""
		phone.move_limit_shape.free()


func _on_sync(event: Dictionary) -> void:
	sync_events.append(event.duplicate(true))
	var action: String = observer_action
	if action == "cancel-on-write" and event["事件"] == "延后属性写入已请求":
		observer_action = ""
		phone.cancel_handset_transfer()
	elif event["事件"] == "真实物理目标已确认":
		observer_action = ""
		match action:
			"cancel-on-confirm":
				phone.cancel_handset_transfer()
			"free-player-on-confirm":
				player.queue_free()
			"free-inventory-on-confirm":
				inventory.queue_free()
			"free-source-on-confirm":
				phone.queue_free()
			"immediate-player-on-confirm":
				player.free()
			"immediate-inventory-on-confirm":
				inventory.free()
			"move-outside-on-confirm":
				player.global_position = phone.to_global(Vector3(-3, -0.3995, 1))


func _snapshot(label: String) -> void:
	var slots: Array[int] = []
	for index: int in 4:
		var item: AutolysisItemInstance = inventory.get_slot_instance(index)
		slots.append(item.get_instance_id() if is_instance_valid(item) else 0)
	snapshots.append({"阶段": label, "选中索引": inventory.get_focused_index(), "四格身份": slots, "持物序号": inventory.get_holding_revision(), "持有会话": inventory.get_handset_session_id(), "来源会话": phone.get_holder_session_id(), "挂机可见": phone.handset_visual.visible, "限位停用": phone.move_limit_shape.disabled, "实际限位启用": phone._shape_is_active_in_world(phone.move_limit_shape), "玩家位置": _vector(player.global_position)})


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _save_report() -> void:
	var directory: String = ProjectSettings.globalize_path(evidence_directory)
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(directory.path_join("电话设备报告.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"断言": records, "失败数": failures, "业务快照": snapshots, "站位无门禁样本": position_records, "限位同步事件": sync_events, "正式玩家运动轨迹": motion_records, "退出音频采样": audio_exit_samples, "图形验收": false, "原生系统输入": false}, "\t"))
