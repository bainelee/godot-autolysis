extends SceneTree
## 两类正式容器的资产变化、取消恢复与来源守恒。

const SCENES: Array[PackedScene] = [preload("res://main-autolysis/scenes/prefabs/prefab_machines/waste_liquid_storage_tank_0.tscn"), preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/cabinet_workroom_0.tscn")]
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/容器开闭动画控制实施证据/20261004/container-checks/assets")

class EventProbe extends Node:
	var events: int = 0
	var action: Callable
	func on_event() -> void:
		events += 1
		if action.is_valid():
			action.call()

var failures: int = 0
var records: Array[Dictionary] = []
var world: Node3D
var actor: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	actor = Node3D.new()
	world.add_child(actor)
	for scene: PackedScene in SCENES:
		for variant: int in 8:
			await _test_variant(scene, variant)
		for boundary: String in ["取消", "重新绑定", "节点释放", "挂起", "零秒挂起", "零秒关闭挂起", "失效取消"]:
			await _test_immediate_boundary(scene, boundary)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("容器资产矩阵.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"断言": records, "失败数": failures}, "\t"))
	world.queue_free()
	await process_frame
	print("容器资产矩阵断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures else 0)


func _test_variant(scene: PackedScene, variant: int) -> void:
	var container: Node3D = scene.instantiate()
	var waste: bool = container is AutolysisWasteLiquidStorageTank
	var body: AnimatableBody3D = container.lid_body if waste else container.door_body
	var player: AnimationPlayer = container.animation_player
	var name: StringName = container.animation_name
	var source: Animation = player.get_animation(name).duplicate(true)
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(name, source)
	player.remove_animation_library(&"")
	player.add_animation_library(&"动作库" if variant == 7 else &"", library)
	if variant == 7:
		name = StringName("动作库/" + str(name))
		container.animation_name = name
	var duration: float = [0.08, 0.65, 1.2, 0.31, 0.47, 0.29, 0.33, 0.37][variant]
	var old_duration: float = source.length
	for track: int in source.get_track_count():
		var keys: Array[Dictionary] = []
		for key: int in source.track_get_key_count(track):
			keys.append({"时间": source.track_get_key_time(track, key) * duration / old_duration, "值": source.track_get_key_value(track, key), "过渡": source.track_get_key_transition(track, key)})
		while source.track_get_key_count(track) > 0:
			source.track_remove_key(track, 0)
		for key: Dictionary in keys:
			source.track_insert_key(track, key["时间"], key["值"], key["过渡"])
	source.length = duration
	var closed_angle: Vector3 = Vector3(0.12, 0.06, -0.04)
	var opened_angle: Vector3 = closed_angle if variant == 4 else Vector3(0.51, 0.17, -0.09)
	source.track_set_key_value(0, 0, closed_angle)
	source.track_set_key_value(0, source.track_get_key_count(0) - 1, opened_angle)
	if variant == 4:
		source.track_insert_key(0, duration * 0.5, Vector3(0.68, 0.2, -0.1))
	var close_position: Vector3 = body.position
	var open_position: Vector3 = close_position + Vector3(0.03, 0.04, -0.02)
	var position_track: int = source.add_track(Animation.TYPE_VALUE)
	source.track_set_path(position_track, NodePath(str(container.get_path_to(body)) + ":position"))
	source.track_insert_key(position_track, 0.0, close_position)
	source.track_insert_key(position_track, duration, open_position)
	var scale_track: int = source.add_track(Animation.TYPE_VALUE)
	source.track_set_path(scale_track, NodePath(str(container.get_path_to(body)) + ":scale"))
	source.track_insert_key(scale_track, 0.0, Vector3.ONE)
	source.track_insert_key(scale_track, duration, Vector3(1.03, 1.03, 1.03))
	var probe: EventProbe = EventProbe.new()
	probe.name = "事件计数"
	container.add_child(probe)
	var event_track: int = source.add_track(Animation.TYPE_METHOD)
	source.track_set_path(event_track, container.get_path_to(probe))
	source.track_insert_key(event_track, 0.0, {"method": &"on_event", "args": []})
	source.track_insert_key(event_track, duration * 0.5, {"method": &"on_event", "args": []})
	if variant == 5:
		var group: Node3D = Node3D.new()
		group.name = "新分组"
		container.add_child(group)
		_move_before_tree(body, group)
		body.name = "新活动体"
		for track: int in [0, position_track, scale_track]:
			var property: String = source.track_get_path(track).get_concatenated_subnames()
			source.track_set_path(track, NodePath(str(container.get_path_to(body)) + ":" + property))
		_move_before_tree(player, group)
		player.root_node = player.get_path_to(container)
		if not waste:
			_move_before_tree(container.slot_0, group)
			container.slot_0.name = "左槽"
			_move_before_tree(container.slot_1, group)
			container.slot_1.name = "右槽"
	player.speed_scale = 1.35
	container.rotation.y = PI
	world.add_child(container)
	await _frames(3)
	var label: String = ("废液罐" if waste else "专用柜") + "变体%d" % variant
	_check(container.is_configured() and container.can_toggle(actor), label + "初始化不受长度、端点和层级形状限制")
	_check(probe.events == 0, label + "属性初始化跳过事件轨道")
	var source_item: Node = null if waste else container.get_item_at_slot(0)
	var counts: Dictionary = {"完成": 0, "观察": 0}
	container.motion_completed.connect(func(_opened: bool) -> void: counts["完成"] += 1)
	var component: AutolysisInteractionComponent = container.lid_interaction if waste else container.toggle_interaction
	component.interaction_requested.connect(func(_actor: Node3D) -> void: counts["观察"] += 1)
	_check(component.try_interact(actor), label + "权威入口分发后通知观察者")
	if variant == 6:
		var initial_events: int = probe.events
		container.cancel_motion()
		await _wait(container)
		_check(probe.events == initial_events and not container.is_open(), label + "同帧取消不触发残留开始事件")
		player.play(name)
		container.rebind_animation_player(player)
		await _wait(container)
		_check(probe.events == initial_events and source.track_is_enabled(event_track), label + "外部未推进播放立即重绑定不触发事件且源轨道保留")
		container.try_toggle(actor)
		await _frames(2)
		_check(container.suspend_motion(), label + "控制器显式挂起保留本次动作")
		await _frames(2)
		var position_before: float = player.current_animation_position
		await _frames(4)
		_check(is_equal_approx(position_before, player.current_animation_position) and container.is_animating() and not container.is_open(), label + "挂起不伪报完成")
		_check(container.resume_motion(), label + "明确续播同一动作")
	await _wait(container)
	_check(container.is_open() and counts["完成"] == 1 and counts["观察"] == 1, label + "自然完成推进一次且观察不重复执行业务")
	records.append({"测量": label, "位置误差": body.position.distance_to(open_position), "矩阵误差": _basis_error(body.basis, Basis.from_euler(opened_angle).scaled(Vector3(1.03, 1.03, 1.03))), "实际变换": var_to_str(body.transform)})
	_check(body.position.distance_to(open_position) < 0.0003 and _basis_error(body.basis, Basis.from_euler(opened_angle).scaled(Vector3(1.03, 1.03, 1.03))) < 0.0003, label + "本次结束结果同时保留位移旋转缩放")
	var stable: Transform3D = body.transform
	var events_after: int = probe.events
	await _frames(6)
	_check(body.transform.is_equal_approx(stable) and probe.events == events_after, label + "稳定阶段保留实际结果且不重放事件")
	_check(container.try_toggle(actor), label + "下一请求允许动画重新驱动")
	await _frames(1)
	if variant == 6:
		_check(container.cancel_motion(), label + "关闭中取消恢复此前已完成打开态")
		await _wait(container)
		_check(container.is_open() and counts["完成"] == 1, label + "取消恢复不发布自然完成")
		_check(container.try_toggle(actor), label + "恢复后可以再次关闭")
	await _wait(container)
	_check(not container.is_open() and container.can_toggle(actor), label + "反播完成建立关闭许可")
	_check(body.position.distance_to(close_position) < 0.0003 and _basis_error(body.basis, Basis.from_euler(closed_angle)) < 0.0003, label + "关闭使用本次反播结束结果")
	if variant == 6:
		_check(container.try_toggle(actor), label + "打开中取消夹具开始")
		await _frames(1)
		container.cancel_motion()
		await _wait(container)
		_check(not container.is_open(), label + "打开中取消回到已关闭")
		container.try_toggle(actor)
		await _frames(1)
		player.stop(true)
		await _frames(2)
		_check(not container.is_animating() and not container.can_toggle(actor), label + "外部停止终结等待并要求明确恢复")
		container.cancel_motion()
		await _wait(container)
		var replacement: AnimationPlayer = player.duplicate()
		container.add_child(replacement)
		replacement.root_node = replacement.get_path_to(container)
		player.queue_free()
		await _frames(2)
		_check(not container.is_animating() and not container.is_open(), label + "必要依赖释放关闭打开许可")
		_check(container.rebind_animation_player(replacement), label + "明确重新绑定有效依赖")
		await _wait(container)
		_check(not container.is_open() and container.can_toggle(actor), label + "重绑定建立关闭态后恢复请求")
		container.try_toggle(actor)
		await _wait(container)
		_check(container.is_open(), label + "重绑定后再次自然完成打开")
		container.try_toggle(actor)
		await _wait(container)
		container.try_toggle(actor)
		await _frames(1)
		replacement.play_backwards(name)
		await _frames(2)
		_check(not container.is_open() and not container.is_animating(), label + "同名反向接管不授予错误打开许可")
		container.cancel_motion()
		await _wait(container)
		container.try_toggle(actor)
		var replaced_source: Animation = replacement.get_animation(name).duplicate()
		replacement.get_animation_library(&"").remove_animation(name)
		replacement.get_animation_library(&"").add_animation(name, replaced_source)
		await _frames(2)
		_check(not container.is_open() and not container.is_animating(), label + "本次同名资源替换终结动作")
		container.rebind_animation_player(replacement)
		await _wait(container)
		container.try_toggle(actor)
		await replacement.animation_finished
		replacement.play(name)
		await _frames(2)
		_check(not container.is_open() and not container.is_animating(), label + "完成待同步窗口被接管不发布稳定打开许可")
		container.rebind_animation_player(replacement)
		await _wait(container)
		replaced_source.loop_mode = Animation.LOOP_LINEAR
		_check(not container.rebind_animation_player(replacement) and not container.is_open(), label + "循环配置给出不可自然完成原因")
		replaced_source.loop_mode = Animation.LOOP_NONE
		container.rebind_animation_player(replacement)
		await _wait(container)
		_check(container.can_toggle(actor), label + "有限非循环配置重新绑定后恢复")
	_check(waste or (container.get_item_at_slot(0) == source_item and container.owns_item(source_item)), label + "动画变化与恢复保留柜内来源身份")
	container.queue_free()
	await _frames(2)


func _test_immediate_boundary(scene: PackedScene, boundary: String) -> void:
	var container: Node3D = scene.instantiate()
	var waste: bool = container is AutolysisWasteLiquidStorageTank
	var body: AnimatableBody3D = container.lid_body if waste else container.door_body
	var player: AnimationPlayer = container.animation_player
	player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	var source: Animation = player.get_animation(container.animation_name).duplicate()
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(container.animation_name, source)
	player.remove_animation_library(&"")
	player.add_animation_library(&"", library)
	var probe: EventProbe = EventProbe.new()
	probe.name = "立即事件"
	container.add_child(probe)
	var method_track: int = source.add_track(Animation.TYPE_METHOD)
	source.track_set_path(method_track, container.get_path_to(probe))
	source.track_insert_key(method_track, 0.0 if boundary in ["零秒挂起", "零秒关闭挂起"] else source.length * 0.375, {"method": &"on_event", "args": []})
	var position_track: int = source.add_track(Animation.TYPE_VALUE)
	source.track_set_path(position_track, NodePath(str(container.get_path_to(body)) + ":position"))
	source.track_insert_key(position_track, 0.0, body.position)
	source.track_insert_key(position_track, source.length, body.position + Vector3(0.0, 0.2, 0.0))
	world.add_child(container)
	await _frames(3)
	var closed: Transform3D = body.transform
	var initial_item: Node = null if waste else container.get_item_at_slot(0)
	var counts: Dictionary = {"事件": 0, "完成": 0, "立即撤销": false}
	container.motion_completed.connect(func(_opened: bool) -> void: counts["完成"] += 1)
	if boundary == "零秒关闭挂起":
		container.try_toggle(actor)
		await _wait(container)
		_check(container.is_open(), "关闭终点挂起前已自然完成打开")
		counts["完成"] = 0
	probe.action = func() -> void:
		counts["事件"] += 1
		if boundary == "节点释放":
			container.queue_free()
		else:
			if boundary == "取消":
				container.cancel_motion("立即方法取消")
			elif boundary in ["挂起", "零秒挂起", "零秒关闭挂起"]:
				container.suspend_motion()
			elif boundary == "失效取消":
				if waste:
					container.lid_collision.disabled = true
				else:
					container.toggle_interaction.is_enabled = false
				container.cancel_motion("立即方法依赖失效取消")
			else:
				container.rebind_animation_player(player)
			counts["立即撤销"] = not container.can_toggle(actor) and not container.is_open()
	var label: String = ("废液罐" if waste else "专用柜") + "立即方法" + boundary
	_check(container.try_toggle(actor), label + "接受原动作")
	await _frames(30)
	_check(counts["事件"] == 1 and counts["完成"] == 0, label + "仅执行一次事件且不伪报自然完成")
	if boundary == "节点释放":
		_check(not is_instance_valid(container), label + "释放后不继续访问旧控制件")
		return
	if boundary in ["挂起", "零秒挂起", "零秒关闭挂起"]:
		var suspended_time: float = player.current_animation_position
		var suspended_transform: Transform3D = body.transform
		await _frames(3)
		_check(counts["立即撤销"] and container.is_animating() and is_equal_approx(player.current_animation_position, suspended_time) and body.transform.is_equal_approx(suspended_transform), label + "挂起保留同次等待且实际时间与完整变换不继续推进")
		_check(container.resume_motion(), label + "同次动作允许续播")
		await _wait(container)
		var target_reached: bool = not container.is_open() and container.can_toggle(actor) if boundary == "零秒关闭挂起" else container.is_open()
		_check(target_reached and counts["完成"] == 1 and counts["事件"] == 1, label + "续播只自然完成一次且不重放开始事件")
		container.queue_free()
		await _frames(2)
		return
	if boundary == "失效取消":
		_check(counts["立即撤销"] and not container.is_animating() and not container.is_open(), label + "失效终结等待且不伪报完成")
		if waste:
			container.lid_collision.disabled = false
		else:
			container.toggle_interaction.is_enabled = true
		_check(container.rebind_animation_player(player), label + "必要依赖修复后明确重新绑定")
		await _wait(container)
	_check(counts["立即撤销"] and not container.is_open() and not container.is_animating() and container.can_toggle(actor), label + "立即撤销旧许可并在推进返回后恢复稳定关闭")
	records.append({"边界": label, "关闭预期": var_to_str(closed), "恢复实际": var_to_str(body.transform), "位置差": body.position.distance_to(closed.origin), "基差": _basis_error(body.basis, closed.basis)})
	_check(body.transform.origin.distance_to(closed.origin) < 0.0003 and _basis_error(body.basis, closed.basis) < 0.0003, label + "完整关闭表现恢复且没有旧帧覆盖")
	_check(waste or container.get_item_at_slot(0) == initial_item, label + "保留原有柜内来源")
	probe.action = Callable()
	_check(container.try_toggle(actor), label + "恢复后可接受下一动作")
	await _wait(container)
	_check(container.is_open() and counts["完成"] == 1, label + "下一动作正常自然完成")
	container.queue_free()
	await _frames(2)


func _wait(container: Node) -> void:
	for frame: int in 360:
		if not container.is_animating():
			return
		await _frames(1)
	_check(false, "动作超过测试等待上限")


func _frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame


func _basis_error(left: Basis, right: Basis) -> float:
	return maxf(left.x.distance_to(right.x), maxf(left.y.distance_to(right.y), left.z.distance_to(right.z)))


func _move_before_tree(node: Node, parent: Node) -> void:
	var original: Transform3D = node.transform if node is Node3D else Transform3D.IDENTITY
	_clear_owner(node)
	node.get_parent().remove_child(node)
	parent.add_child(node)
	if node is Node3D:
		node.transform = original


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child: Node in node.get_children():
		_clear_owner(child)


func _check(condition: bool, description: String) -> void:
	records.append({"说明": description, "通过": condition})
	if not condition:
		failures += 1
	print(("通过：" if condition else "失败：") + description)

