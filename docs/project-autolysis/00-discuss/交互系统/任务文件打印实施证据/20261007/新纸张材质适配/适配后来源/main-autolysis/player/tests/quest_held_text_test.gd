extends SceneTree
## 真实玩家库存接收和手持呈现的全文显示专项。

const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
const PAPER: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/quest_paper.tres")
const FIRST_TASK: AutolysisQuestPrintDefinition = preload("res://main-autolysis/systems/quest-print-system/quests/quest_test_0.tres")
const VISUAL_ADAPTER: Script = preload("res://main-autolysis/systems/item-system/autolysis_quest_paper_visual.gd")
const MACHINE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/quest_machine_0.tscn")

class ReleaseObserver extends Node:
	var target: Node
	var calls: int = 0
	var release_queued: bool = false

	func release_target() -> void:
		calls += 1
		if is_instance_valid(target):
			target.queue_free()
			release_queued = target.is_queued_for_deletion()

var failures: int = 0
var records: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/任务文件打印实施证据/20261007/持有文字与空间音效修订/手持全文")


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
	records.append({"说明": description, "通过": condition})
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1


func _visible_text(node: Node) -> PackedStringArray:
	var lines: PackedStringArray = []
	if node is Label and node.visible and node.self_modulate.a > 0.0:
		lines.append(node.text)
	for child: Node in node.get_children():
		lines.append_array(_visible_text(child))
	return lines


func _presenter_connection_count(instance: AutolysisItemInstance, presenter: AutolysisHeldItemPresenter) -> int:
	var count: int = 0
	for connection: Dictionary in instance.changed.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_object() == presenter:
			count += 1
	return count


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("手持文字专项禁止启动图形后端。")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var release_case_index: int = arguments.find("--held-update-release-case")
	if release_case_index >= 0 and release_case_index + 1 < arguments.size():
		await _test_update_release_boundary(StringName(arguments[release_case_index + 1]))
		_write_report(PackedStringArray())
		quit(1 if failures > 0 else 0)
		return
	var actor: AutolysisPlayer = PLAYER_SCENE.instantiate() as AutolysisPlayer
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process_input(false)
	actor.set_process_unhandled_input(false)
	actor._clear_landing_stun()
	await process_frame
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(PAPER)
	check(instance.set_quest_paper_contents(FIRST_TASK.create_contents()), "真实任务逐件资源保存用户指定任务全文")
	check(actor.inventory_controller.try_receive_instance(instance), "正式库存接收逐件任务文件并提交手持展示")
	check(actor.inventory_controller.get_focused_instance() == instance and instance.quest_paper_contents.get_data_lines() == FIRST_TASK.data_lines, "正式接收保留同一逐件身份和全文")
	await process_frame
	var display: Node3D = actor.held_item_presenter.get_display()
	var actual_lines: PackedStringArray = _visible_text(display) if display != null else PackedStringArray()
	check(actual_lines == FIRST_TASK.data_lines, "正式手持展示可见本件全部自然行而不是白纸")
	await process_frame
	await _test_display_contents(actor, instance)
	await _test_focus_projection(actor)
	await _test_take_after_focus_projection()
	actor.camera.make_current()
	await _test_resource_lifecycle(actor, instance)
	for release_case: StringName in [&"hide_display", &"hide_actor", &"exit_display", &"exit_actor"]:
		await _test_update_release_boundary(release_case)
	_write_report(actual_lines)
	if is_instance_valid(actor):
		actor.queue_free()
	await process_frame
	await process_frame
	print("手持全文专项断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)


func _write_report(actual_lines: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("手持全文断言.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"失败数": failures, "断言数": records.size(), "记录": records, "测量": measurements, "期望全文": FIRST_TASK.data_lines, "实际显示全文": actual_lines}, "\t"))
	report.close()


func _test_update_release_boundary(release_case: StringName) -> void:
	var before_orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var actor: AutolysisPlayer = PLAYER_SCENE.instantiate() as AutolysisPlayer
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process_input(false)
	actor.set_process_unhandled_input(false)
	actor._clear_landing_stun()
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(PAPER)
	instance.set_quest_paper_contents(FIRST_TASK.create_contents())
	check(actor.inventory_controller.try_receive_instance(instance), "内容释放边界通过正式库存建立手持文件")
	await process_frame
	var presenter: AutolysisHeldItemPresenter = actor.held_item_presenter
	var display: Node3D = presenter.get_display()
	var previous_view: AutolysisQuestPaperView = presenter.get_quest_paper_view()
	var viewport: SubViewport = presenter.get_quest_paper_viewport()
	var observer: ReleaseObserver = ReleaseObserver.new()
	root.add_child(observer)
	var release_actor: bool = release_case in [&"hide_actor", &"exit_actor"]
	observer.target = actor if release_actor else display
	if release_case in [&"hide_display", &"hide_actor"]:
		previous_view.visibility_changed.connect(observer.release_target, CONNECT_ONE_SHOT)
	else:
		previous_view.tree_exiting.connect(observer.release_target, CONNECT_ONE_SHOT)
	check(instance.set_quest_paper_contents(_new_contents("release_update", PackedStringArray(["内容更新中的同步释放"]))), "内容更新正式通知触发旧排版观察边界")
	check(observer.calls == 1 and observer.release_queued, "旧纸面同步观察实际排队释放指定对象")
	var observer_calls: int = observer.calls
	await process_frame
	await process_frame
	check(not is_instance_valid(display) and not is_instance_valid(viewport) and not is_instance_valid(previous_view), "排队释放完成后旧显示纸面视口和排版均已退役")
	if not release_actor:
		check(is_instance_valid(presenter) and presenter.get_display() == null and actor.inventory_controller.get_focused_instance() == instance and _presenter_connection_count(instance, presenter) == 1, "显示退役后仅保留当前库存选择的单一合法监听")
		instance.emit_changed()
		check(actor.inventory_controller.cycle_focus(1) and presenter.get_display() == null and instance.changed.get_connections().is_empty(), "退役后通知无无效访问且正式切格断开逐件监听")
	else:
		check(not is_instance_valid(actor) and not is_instance_valid(presenter) and instance.changed.get_connections().is_empty(), "玩家排队释放完成后逐件监听全部断开")
	world.queue_free()
	observer.queue_free()
	await process_frame
	await process_frame
	await process_frame
	var after_orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(instance.changed.get_connections().is_empty() and after_orphans == before_orphans, "同步释放后没有逐件监听或未提交排版候选残留")
	measurements.append({"名称": "已持有内容更新的同步排队释放", "边界": release_case, "观察调用": observer_calls, "释放前孤立节点": before_orphans, "清理后孤立节点": after_orphans})


func _test_focus_projection(actor: AutolysisPlayer) -> void:
	var machine: AutolysisQuestMachine = MACHINE_SCENE.instantiate() as AutolysisQuestMachine
	root.add_child(machine)
	# 无图形驱动不模拟原生捕获指针；仅替换入口输入许可，业务检查和过渡仍用正式入口。
	actor.focus_controller.configure(actor, actor.camera, actor.held_item_presenter, _focus_entry_allowed.bind(actor))
	var entered: bool = actor.focus_controller.try_enter(machine.focus_target)
	check(entered, "持有文件可正式进入通知中心聚焦")
	if not entered:
		machine.queue_free()
		return
	for index: int in 30:
		await physics_frame
		await process_frame
	check(actor.focus_controller.is_focused_on(machine.focus_target) and actor.camera.fov == machine.reference_camera.fov, "真实玩家完成通知中心实际相机过渡")
	var presenter: AutolysisHeldItemPresenter = actor.held_item_presenter
	var view: AutolysisQuestPaperView = presenter.get_quest_paper_view()
	var viewport: SubViewport = presenter.get_quest_paper_viewport()
	var front: MeshInstance3D = presenter.get_quest_paper_front()
	var all_inside: bool = true
	var point_records: Array[Dictionary] = []
	var rectangle: Rect2 = Rect2(Vector2.ZERO, Vector2(root.size))
	for entry: Dictionary in view.get_layout_report():
		var text_position: Vector2 = view.clip_area.position + view.lines_container.position + Vector2(entry["position"])
		var row_size: Vector2 = entry["size"]
		var projected: Array[Vector2] = []
		for corner: Vector2 in [text_position, text_position + Vector2(row_size.x, 0.0), text_position + row_size, text_position + Vector2(0.0, row_size.y)]:
			var point: Vector3 = front.global_transform * Vector3((corner.x / float(viewport.size.x) - 0.5) * 0.36, (0.5 - corner.y / float(viewport.size.y)) * 0.48, 0.0)
			var projection: Vector2 = actor.camera.unproject_position(point)
			projected.append(projection)
			all_inside = all_inside and not actor.camera.is_position_behind(point) and rectangle.has_point(projection)
		point_records.append({"自然行": entry["data_line_index"], "投影角点": projected})
	check(all_inside, "通知中心真实聚焦视角下十三行完整文字区域仍全部可见")
	measurements.append({"名称": "真实通知中心聚焦投影", "玩家视角": actor.camera.fov, "目标视角": machine.reference_camera.fov, "全文区域完整可见": all_inside, "行投影": point_records})
	check(actor.focus_controller.request_exit(), "几何量测后通过正式退出入口恢复视角")
	for index: int in 30:
		await physics_frame
		await process_frame
	machine.queue_free()
	await process_frame


func _focus_entry_allowed(actor: AutolysisPlayer) -> bool:
	return actor._base_input_allowed() and not actor.focus_controller.has_control()


func _projected_paper(actor: AutolysisPlayer) -> Dictionary:
	var presenter: AutolysisHeldItemPresenter = actor.held_item_presenter
	var view: AutolysisQuestPaperView = presenter.get_quest_paper_view()
	var viewport: SubViewport = presenter.get_quest_paper_viewport()
	var front: MeshInstance3D = presenter.get_quest_paper_front()
	if view == null or viewport == null or front == null:
		return {"完整可见": false}
	var rectangle: Rect2 = Rect2(Vector2.ZERO, Vector2(root.size))
	var all_inside: bool = true
	var points: Array[Vector2] = []
	for entry: Dictionary in view.get_layout_report():
		var text_position: Vector2 = view.clip_area.position + view.lines_container.position + Vector2(entry["position"])
		var row_size: Vector2 = entry["size"]
		for corner: Vector2 in [text_position, text_position + Vector2(row_size.x, 0.0), text_position + row_size, text_position + Vector2(0.0, row_size.y)]:
			var point: Vector3 = front.global_transform * Vector3((corner.x / float(viewport.size.x) - 0.5) * 0.36, (0.5 - corner.y / float(viewport.size.y)) * 0.48, 0.0)
			var projected: Vector2 = actor.camera.unproject_position(point)
			points.append(projected)
			all_inside = all_inside and not actor.camera.is_position_behind(point) and rectangle.has_point(projected)
	var normal: Vector3 = front.global_basis.z.normalized()
	var facing: float = normal.dot((actor.camera.global_position - front.global_position).normalized())
	return {"完整可见": all_inside, "朝向点积": facing, "视角": actor.camera.fov, "投影点": points}


func _test_take_after_focus_projection() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var actor: AutolysisPlayer = PLAYER_SCENE.instantiate() as AutolysisPlayer
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process_input(false)
	actor.set_process_unhandled_input(false)
	actor._clear_landing_stun()
	actor.focus_controller.configure(actor, actor.camera, actor.held_item_presenter, _focus_entry_allowed.bind(actor))
	var machine: AutolysisQuestMachine = MACHINE_SCENE.instantiate() as AutolysisQuestMachine
	# 几何专项缩短显式动作配置，仍等待正式有限动作自然完成；不替换打印或获取链。
	for field: StringName in [&"first_descent_seconds", &"first_wait_seconds", &"first_left_seconds", &"print_line_seconds", &"return_left_seconds", &"next_line_seconds", &"center_seconds", &"reset_seconds"]:
		machine.set(field, 0.002)
	world.add_child(machine)
	var entered: bool = actor.focus_controller.try_enter(machine.focus_target)
	check(entered, "空手玩家通过正式入口进入通知中心准备打印与获取")
	if not entered:
		world.queue_free()
		return
	for index: int in 30:
		await physics_frame
		await process_frame
	check(actor.focus_controller.is_focused_on(machine.focus_target) and actor.held_item_presenter.get_display() == null, "打印前真实聚焦相机和空手状态成立")
	check(machine.request_task_print(FIRST_TASK, actor) and machine.try_start_print(actor), "正式受理并启动首份十三行打印")
	for index: int in 150:
		if machine.state == AutolysisQuestMachine.PrintState.COMPLETE:
			break
		await physics_frame
		await process_frame
	check(machine.state == AutolysisQuestMachine.PrintState.COMPLETE, "正式自然动作完成后进入可获取阶段")
	if machine.state != AutolysisQuestMachine.PrintState.COMPLETE:
		world.queue_free()
		return
	var paper: AutolysisQuestPaper = machine.get_current_paper()
	var instance: AutolysisItemInstance = paper.item_instance
	check(actor.inventory_controller.try_take_quest_paper(actor, paper), "实际聚焦取纸入口成功提交首份手持文件")
	await process_frame
	await process_frame
	check(not is_instance_valid(paper) and actor.held_item_presenter.get_quest_paper_instance() == instance, "世界来源实际释放后手持文字仍绑定原逐件身份")
	check(_visible_text(actor.held_item_presenter.get_display()) == FIRST_TASK.data_lines, "真实取纸后的手持子树继续显示十三行全部原文")
	var taken: Dictionary = _projected_paper(actor)
	check(taken["完整可见"] and taken["朝向点积"] > 0.0 and actor.camera.fov == machine.reference_camera.fov, "完成聚焦后才取到的文件全文区域完整位于实际画面内")
	measurements.append({"名称": "正式聚焦取纸后的全文投影", "测量": taken})
	check(actor.inventory_controller.cycle_focus(1) and actor.held_item_presenter.get_display() == null and actor.held_item_presenter.get_quest_paper_viewport() == null, "真实聚焦中切换空格清空纸面和文字资源")
	check(actor.inventory_controller.cycle_focus(-1) and actor.held_item_presenter.get_quest_paper_instance() == instance, "真实聚焦中切回文件恢复对应逐件显示")
	await process_frame
	var returned: Dictionary = _projected_paper(actor)
	check(returned["完整可见"] and _visible_text(actor.held_item_presenter.get_display()) == FIRST_TASK.data_lines, "聚焦中重新选中文件仍显示全部原文且没有屏外裁剪")
	check(actor.focus_controller.request_exit(), "实际取纸后通过正式退出入口恢复普通玩家视角")
	for index: int in 30:
		await physics_frame
		await process_frame
	var exited: Dictionary = _projected_paper(actor)
	check(not actor.focus_controller.has_control() and exited["完整可见"] and exited["朝向点积"] > 0.0, "真实聚焦退出后全文投影恢复并继续完整可见")
	measurements.append({"名称": "正式聚焦取纸后退出投影", "测量": exited})
	world.queue_free()
	await process_frame
	await process_frame
	# 声音停止的底层释放由实际混音提交，退出前等待两次已完成的虚拟驱动混音。
	var previous_mix: float = AudioServer.get_time_since_last_mix()
	var mixes: int = 0
	var deadline: int = Time.get_ticks_msec() + 2000
	while mixes < 2 and Time.get_ticks_msec() < deadline:
		OS.delay_msec(2)
		await process_frame
		var current_mix: float = AudioServer.get_time_since_last_mix()
		if current_mix < previous_mix:
			mixes += 1
		previous_mix = current_mix
	check(mixes == 2, "打印音源退出清理经过两次实际混音边界")


func _test_display_contents(actor: AutolysisPlayer, instance: AutolysisItemInstance) -> void:
	var presenter: AutolysisHeldItemPresenter = actor.held_item_presenter
	var view: AutolysisQuestPaperView = presenter.get_quest_paper_view()
	var viewport: SubViewport = presenter.get_quest_paper_viewport()
	var front: MeshInstance3D = presenter.get_quest_paper_front()
	check(view != null and viewport != null and front != null, "呈现器公开查询实际全文纸面及独立视口与正面")
	if view == null or viewport == null or front == null:
		return
	check(presenter.get_quest_paper_instance() == instance, "手持文字绑定同一逐件资源身份")
	check(view.get_contents().get_task_id() == FIRST_TASK.task_id and view.get_contents().get_data_lines() == FIRST_TASK.data_lines and view.get_contents().get_group_gap_before_lines() == FIRST_TASK.group_gap_before_lines, "手持纸面保留完整任务标识原文与分组")
	check(view.get_visible_data_line_indices().size() == FIRST_TASK.data_lines.size(), "拿起后的所有自然行立即显示")
	check(front.material_overlay is StandardMaterial3D and front.material_overlay.albedo_texture == viewport.get_texture(), "正面文字叠加材质实际绑定当前独立纸面纹理")
	check(PAPER.is_valid_definition() and presenter._is_display_scene_state(PAPER.visual_scene.get_state()), "纯展示源仍无脚本碰撞或交互组")
	var copy: PackedStringArray = view.get_contents().get_data_lines()
	copy[0] = "读取副本被改写"
	check(view.get_contents().get_data_lines() == FIRST_TASK.data_lines and instance.quest_paper_contents.get_data_lines() == FIRST_TASK.data_lines, "手持视图读取副本不能改写逐件原文")
	var layout: Array[Dictionary] = view.get_layout_report()
	var missing: String = ""
	var projected_points: PackedVector2Array = []
	var all_inside: bool = true
	var camera: Camera3D = actor.camera
	var rectangle: Rect2 = Rect2(Vector2.ZERO, Vector2(root.size))
	for entry: Dictionary in layout:
		missing += String(entry["missing_characters"])
		var text_position: Vector2 = view.clip_area.position + view.lines_container.position + Vector2(entry["position"])
		var row_size: Vector2 = entry["size"]
		for corner: Vector2 in [text_position, text_position + Vector2(row_size.x, 0.0), text_position + row_size, text_position + Vector2(0.0, row_size.y)]:
			var point: Vector3 = front.global_transform * Vector3((corner.x / float(viewport.size.x) - 0.5) * 0.36, (0.5 - corner.y / float(viewport.size.y)) * 0.48, 0.0)
			var projection: Vector2 = camera.unproject_position(point)
			projected_points.append(projection)
			all_inside = all_inside and not camera.is_position_behind(point) and rectangle.has_point(projection)
	var direction: Vector3 = (camera.global_position - front.global_position).normalized()
	var normal: Vector3 = front.global_basis.z.normalized()
	var facing: float = normal.dot(direction)
	check(missing.is_empty(), "真实手持字号所用字体支持首份所有中文字符")
	check(facing > 0.0, "文字正面法线在真实玩家相机一侧")
	check(all_inside, "首份十三行完整文字区域实际投影均位于玩家画面内")
	measurements.append({"名称": "真实手持相机纸面测量", "正面法线": normal, "相机方向": direction, "朝向点积": facing, "画面尺寸": root.size, "投影点": projected_points, "布局": layout})
	var view_id: int = view.get_instance_id()
	for index: int in 20:
		presenter.watch_instance(instance)
		instance.emit_changed()
	check(presenter.get_quest_paper_view().get_instance_id() == view_id and viewport.get_child_count() == 1, "重复监听与同内容通知不重建纸面或重复子节点")
	check(_presenter_connection_count(instance, presenter) == 1, "同件重复绑定仍只保留一个呈现监听")
	measurements.append({"名称": "重复绑定后的监听数量", "全部观察者": instance.changed.get_connections().size(), "手持呈现器": _presenter_connection_count(instance, presenter)})
	var candidate: Node3D = presenter.prepare_instance(instance)
	check(candidate != null, "同件可以独立准备第二个纯展示候选")
	if candidate != null:
		check(VISUAL_ADAPTER.get_viewport(candidate) != viewport and VISUAL_ADAPTER.get_front(candidate).material_overlay != front.material_overlay and VISUAL_ADAPTER.get_viewport(candidate).get_texture() != viewport.get_texture(), "并列候选的视口、文字叠加材质与纹理均不共享")
		candidate.free()
	check(presenter.get_quest_paper_view().get_instance_id() == view_id, "未提交候选释放不影响当前手持全文")


func _new_contents(task_id: String, lines: PackedStringArray, gaps: PackedInt32Array = PackedInt32Array()) -> AutolysisQuestPaperContents:
	var definition: AutolysisQuestPrintDefinition = AutolysisQuestPrintDefinition.new()
	definition.task_id = task_id
	definition.data_lines = lines
	definition.group_gap_before_lines = gaps
	return definition.create_contents()


func _test_resource_lifecycle(actor: AutolysisPlayer, first: AutolysisItemInstance) -> void:
	var inventory: AutolysisInventoryController = actor.inventory_controller
	var presenter: AutolysisHeldItemPresenter = actor.held_item_presenter
	var first_view: AutolysisQuestPaperView = presenter.get_quest_paper_view()
	var first_viewport: SubViewport = presenter.get_quest_paper_viewport()
	check(inventory.cycle_focus(1), "正式切换至空格解除任务文件手持")
	check(presenter.get_quest_paper_view() == null and presenter.get_quest_paper_instance() == null and first.changed.get_connections().is_empty(), "空手时清理全文绑定与逐件监听")
	await process_frame
	check(not is_instance_valid(first_view) and not is_instance_valid(first_viewport), "换格实际释放上一文件的视图和视口")
	var second: AutolysisItemInstance = AutolysisItemInstance.create(PAPER)
	var second_lines: PackedStringArray = PackedStringArray(["另一份任务原文", "", "结尾", ""])
	second.set_quest_paper_contents(_new_contents("other_task", second_lines, PackedInt32Array([2])))
	check(inventory.try_receive_instance(second), "另一个格正式接收第二份不同任务文件")
	check(presenter.get_quest_paper_instance() == second and presenter.get_quest_paper_view().get_contents().get_data_lines() == second_lines, "第二份文字只绑定第二件全文和末尾空行")
	check(inventory.cycle_focus(-1), "正式切回第一份任务文件")
	check(presenter.get_quest_paper_instance() == first and presenter.get_quest_paper_view().get_contents().get_data_lines() == FIRST_TASK.data_lines and second.changed.get_connections().is_empty(), "切回原文正确且解绑第二件监听")
	var view: AutolysisQuestPaperView = presenter.get_quest_paper_view()
	var viewport: SubViewport = presenter.get_quest_paper_viewport()
	var material: StandardMaterial3D = presenter.get_quest_paper_front().material_overlay as StandardMaterial3D
	var texture: Texture2D = viewport.get_texture()
	second.set_quest_paper_contents(_new_contents("other_changed", PackedStringArray(["未选中文件变化"])))
	check(presenter.get_quest_paper_view() == view and view.get_contents().get_data_lines() == FIRST_TASK.data_lines, "未选中另一件更新不串改当前文字")
	var updated_lines: PackedStringArray = PackedStringArray(["本件更新全文", "", "分组新行", " ", "\t", ""])
	check(first.set_quest_paper_contents(_new_contents("updated_task", updated_lines, PackedInt32Array([2]))), "当前逐件任务内容更新可形成有效全文")
	var updated: AutolysisQuestPaperView = presenter.get_quest_paper_view()
	check(updated != view and updated.get_contents().get_task_id() == "updated_task" and _visible_text(updated) == updated_lines and updated.get_visible_data_line_indices().size() == updated_lines.size(), "当前逐件更新同步显示新标识全文空行和末尾换行")
	check(presenter.get_quest_paper_viewport() == viewport and presenter.get_quest_paper_front().material_overlay == material and material.albedo_texture == texture, "真正内容更新保持本模型视口、纹理和文字叠加材质身份")
	await process_frame
	check(not is_instance_valid(view) and viewport.get_child_count() == 1, "更新后的旧排版释放且没有积累视图")
	check(_presenter_connection_count(first, presenter) == 1, "全文更新没有增加呈现器资源监听")
	var updated_id: int = updated.get_instance_id()
	first.set_quest_paper_contents(_new_contents("updated_task", updated_lines, PackedInt32Array([2])))
	check(presenter.get_quest_paper_view().get_instance_id() == updated_id, "等值内容副本通知不重新排版")
	first.set_quest_paper_contents(null)
	check(presenter.get_quest_paper_view() == null and presenter.get_quest_paper_front().material_overlay == material and material.albedo_texture == null and material.albedo_color.a == 0.0, "清空本件内容保持同一文字叠加材质完全透明且不遗留已失效的旧任务文字")
	first.set_quest_paper_contents(FIRST_TASK.create_contents())
	check(presenter.get_quest_paper_view().get_contents().get_data_lines() == FIRST_TASK.data_lines, "恢复逐件内容重新建立完整文字")
	check(inventory.cycle_focus(1), "正式换格显示第二件更新后的内容")
	check(presenter.get_quest_paper_instance() == second and presenter.get_quest_paper_view().get_contents().get_task_id() == "other_changed", "换格后读取第二件独立最新快照")
	check(inventory.cycle_focus(1), "正式切至后续空格清空手持展示")
	check(presenter.get_display() == null and presenter.get_quest_paper_viewport() == null and first.changed.get_connections().is_empty() and second.changed.get_connections().is_empty(), "空格和弃用显示清理所有本轮监听")
	check(inventory.cycle_focus(-1), "重新显示一份任务文件供玩家释放边界检查")
	var retiring_view: AutolysisQuestPaperView = presenter.get_quest_paper_view()
	var retiring_viewport: SubViewport = presenter.get_quest_paper_viewport()
	actor.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(retiring_view) and not is_instance_valid(retiring_viewport) and first.changed.get_connections().is_empty() and second.changed.get_connections().is_empty(), "玩家释放销毁持有文字子树并断开全部逐件监听")
