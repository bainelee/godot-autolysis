extends SceneTree
## 正式主场景与引擎内部输入；无图形，不定位系统指针。

const MAIN_SCENE: PackedScene = preload("res://main-autolysis/scenes/01-autolysis-test.tscn")
const EVIDENCE = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd")

var failures: int = 0
var checks: Array[Dictionary] = []
var events: Array[Dictionary] = []
var world: Node3D
var player: AutolysisPlayer
var machine: AutolysisQuestMachine
var started_count: int = 0
var completed_count: int = 0
var taken_count: int = 0


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


func _entry_allowed() -> bool:
	return player._base_input_allowed() and not player.focus_controller.has_control()


func _wait(condition: Callable, description: String, maximum: int = 180) -> bool:
	for index: int in maximum:
		if condition.call() == true:
			return true
		await frames(1)
	check(false, "达到验收等待上限：" + description)
	return false


func _key(pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_I
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(2)


func _click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(2)


func _target_pixel(body: Node3D) -> Vector2:
	var ray := AutolysisFocusRayQuery.new()
	var projected: Vector2 = player.camera.unproject_position(body.global_position)
	var exclusions: Array[RID] = [player.get_rid(), player._found_area.get_rid()]
	for radius: int in [0, 2, 6, 12, 24, 48]:
		for x: int in range(-radius, radius + 1, 2):
			for y: int in range(-radius, radius + 1, 2):
				var point: Vector2 = projected + Vector2(x, y)
				if ray.query_target(player.camera, point, machine.focus_target, exclusions) == body:
					events.append({"事件": "实际射线命中", "物体": str(body.get_path()), "像素": str(point)})
					return point
	return Vector2(-10000, -10000)


func _on_started(serial: int) -> void:
	started_count += 1
	events.append({"事件": "打印开始", "序号": serial, "帧": Engine.get_process_frames()})


func _on_completed(serial: int) -> void:
	completed_count += 1
	events.append({"事件": "打印完成", "序号": serial, "帧": Engine.get_process_frames()})


func _on_revealed(serial: int, index: int) -> void:
	events.append({"事件": "行显示", "序号": serial, "行索引": index, "帧": Engine.get_process_frames()})


func _on_taken(serial: int, instance: AutolysisItemInstance) -> void:
	taken_count += 1
	events.append({"事件": "纸张取走", "序号": serial, "逐件身份": instance.get_instance_id(), "帧": Engine.get_process_frames()})
	check(player.inventory_controller.get_focused_instance() == instance and machine.get_current_paper() == null, "最早取纸观察者读取库存与设备一致的提交结果")


func _print_wait_limit(line_count: int) -> int:
	# 仅为验收等待上限；全部完成仍以正式设备自然通知判定。
	var duration: float = machine.first_descent_seconds + machine.first_wait_seconds + machine.first_left_seconds + machine.center_seconds + machine.reset_seconds
	duration += line_count * machine.print_line_seconds + maxi(line_count - 1, 0) * (machine.return_left_seconds + machine.next_line_seconds)
	return maxi(180, int(ceil(duration * 60.0)) + line_count * 4 + 120)


func _check_held_text(instance: AutolysisItemInstance, original: AutolysisQuestPaperContents, label: String) -> void:
	var presenter: AutolysisHeldItemPresenter = player.held_item_presenter
	var queries_present: bool = presenter.has_method("get_quest_paper_view") and presenter.has_method("get_quest_paper_viewport") and presenter.has_method("get_quest_paper_front") and presenter.has_method("get_quest_paper_instance")
	check(queries_present, label + "：正式呈现器提供手持纸面只读查询")
	if not queries_present:
		return
	var view: AutolysisQuestPaperView = presenter.call("get_quest_paper_view")
	var viewport: SubViewport = presenter.call("get_quest_paper_viewport")
	var front: MeshInstance3D = presenter.call("get_quest_paper_front")
	var display: Node3D = presenter.get_display()
	check(presenter.call("get_quest_paper_instance") == instance and player.inventory_controller.get_focused_instance() == instance, label + "：文字与携带栏绑定同一逐件身份")
	check(is_instance_valid(display) and is_instance_valid(view) and is_instance_valid(viewport) and is_instance_valid(front) and display.is_ancestor_of(viewport) and viewport.is_ancestor_of(view) and display.is_ancestor_of(front), label + "：全文视图、视口与正面属于当前手持展示")
	if not is_instance_valid(view) or not is_instance_valid(viewport) or not is_instance_valid(front):
		return
	var material: StandardMaterial3D = front.material_override as StandardMaterial3D
	var texture: ViewportTexture = viewport.get_texture()
	check(is_instance_valid(material) and is_instance_valid(texture) and texture.get_rid().is_valid() and material.albedo_texture == texture, label + "：手持纸张正面使用有效的当前视口纹理")
	var shown: AutolysisQuestPaperContents = view.get_contents()
	check(shown != null and shown.get_task_id() == original.get_task_id() and shown.get_data_lines() == original.get_data_lines() and shown.get_group_gap_before_lines() == original.get_group_gap_before_lines(), label + "：保留原任务标识、全文与分组")
	var visible_indices: PackedInt32Array = view.get_visible_data_line_indices()
	var layout: Array[Dictionary] = view.get_layout_report()
	var full_text_matches: bool = layout.size() == original.get_line_count() and visible_indices.size() == original.get_line_count()
	var group_layout_matches: bool = layout.size() == original.get_line_count()
	for index: int in mini(layout.size(), original.get_line_count()):
		full_text_matches = full_text_matches and layout[index]["text"] == original.get_data_line(index) and layout[index]["revealed"] and visible_indices.has(index)
		if index > 0:
			var actual_gap: float = layout[index]["position"].y - layout[index - 1]["position"].y - layout[index - 1]["size"].y
			var expected_gap: float = view.group_gap_height if original.get_group_gap_before_lines().has(index) else 0.0
			group_layout_matches = group_layout_matches and is_equal_approx(actual_gap, expected_gap)
	check(full_text_matches, label + "：全部自然行实际文字与可见状态匹配")
	check(group_layout_matches, label + "：实际排版保持各组空白")


func run_checks() -> void:
	check(DisplayServer.get_name() == "headless", "主场景专项使用无图形后端")
	root.size = Vector2i(1280, 720)
	world = MAIN_SCENE.instantiate()
	root.add_child(world)
	player = world.get_node("autolysis_player")
	machine = world.get_node("interaction_prefabs/machines/quest_machine_0")
	player.set_physics_process(false)
	player._clear_landing_stun()
	var trigger: AutolysisQuestPrintTestTrigger = world.get_node("QuestPrintTestTrigger")
	check(trigger.machine == machine and trigger.player == player, "主场景测试入口显式绑定当前通知中心与玩家")
	check(trigger.task_definition.task_id == "quest_test_0", "首份资源采用用户指定的独立字符串标识")
	check(is_equal_approx(machine.print_line_seconds, 2.5), "正式主场景采用新修订的每行两秒半默认打印时长")
	var original_lines: PackedStringArray = trigger.task_definition.data_lines.duplicate()
	check(original_lines.size() == 13 and original_lines[4] == "委托编号：07003141", "首份十三行全文及委托编号前导零准确")
	var bindings: Array[InputEvent] = InputMap.action_get_events(&"quest_print_test")
	check(bindings.size() == 1 and bindings[0] is InputEventKey and bindings[0].physical_keycode == KEY_I, "通知测试动作只绑定指定物理字母键")
	machine.print_started.connect(_on_started)
	machine.print_completed.connect(_on_completed)
	machine.data_line_revealed.connect(_on_revealed)
	machine.paper_taken.connect(_on_taken)
	# 只替换无图形后端不提供的捕获鼠标进入许可；聚焦内输入使用正式玩家许可。
	player.focus_controller.configure(player, player.camera, player.held_item_presenter, _entry_allowed)
	await frames(4)
	check(player.focus_controller.try_enter(machine.focus_target), "空闲通知中心通过正式聚焦入口建立会话")
	await _wait(func() -> bool: return player.focus_controller.is_focused_on(machine.focus_target), "稳定聚焦")
	await _key(true, true)
	await _key(false)
	check(not machine.can_start_print(player), "键盘重复事件不建立待打印任务")
	await _key(true)
	await _key(false)
	check(machine.can_start_print(player) and started_count == 0 and machine.get_current_paper() == null, "引擎内部通知键只建立待打印且没有自动创建纸张")
	check(not trigger.request_test_print(), "已有待打印任务拒绝再次请求且不排队")
	player.is_showing_ui = true
	check(not trigger.request_test_print() and not machine.can_start_print(player), "真实界面暂停拒绝通知和打印入口")
	player.is_showing_ui = false
	var button_pixel: Vector2 = _target_pixel(machine.print_button)
	check(button_pixel.x >= 0, "主场景相机正式射线能够命中打印按钮")
	if button_pixel.x >= 0:
		await _click(button_pixel)
	check(started_count == 1 and machine.get_current_paper() != null, "真实聚焦点击建立唯一空白纸张并开始一轮打印")
	if machine.get_current_paper() == null:
		await _finish()
		return
	var paper: AutolysisQuestPaper = machine.get_current_paper()
	var instance: AutolysisItemInstance = paper.get_item_instance()
	var serial: int = machine.get_print_serial()
	check(paper.get_visible_data_line_indices().is_empty(), "本次纸面初始全部原始数据行隐藏")
	check(not player.inventory_controller.can_take_quest_paper(player, paper), "打印刚开始的纸张不可获取")
	await _key(true)
	await _key(false)
	check(machine.get_print_serial() == serial and started_count == 1, "打印中的重复通知不覆盖本次身份")
	var paper_pixel: Vector2 = _target_pixel(paper)
	check(paper_pixel.x >= 0, "主场景动态纸张在正式相机射线中可达")
	if paper_pixel.x >= 0:
		await _click(paper_pixel)
	check(player.inventory_controller.get_focused_instance() == null and machine.get_current_paper() == paper, "打印期间真实纸张点击保持来源和库存不变")
	await _wait(func() -> bool: return completed_count == 1, "首份默认十三行完整打印与复位", _print_wait_limit(original_lines.size()))
	check(completed_count == 1 and paper.get_visible_data_line_indices().size() == 13, "默认首份打印全部十三行后自然完成一次")
	check(not machine.can_start_print(player) and not trigger.request_test_print(), "完成未取纸时拒绝新打印和通知替换")
	check(player.inventory_controller.can_take_quest_paper(player, paper), "全部复位完成后正式库存查询开放聚焦取纸")
	if paper_pixel.x >= 0:
		await _click(paper_pixel)
	check(taken_count == 1 and machine.get_current_paper() == null and player.inventory_controller.get_focused_instance() == instance, "真实纸张点击只转移一次且保留同一逐件资源身份")
	var contents: AutolysisQuestPaperContents = instance.quest_paper_contents
	check(contents != null and contents.task_id == "quest_test_0" and contents.data_lines == original_lines, "取得文件继续保存独立任务标识和全部原始数据")
	await frames(3)
	check(not is_instance_valid(paper), "首件世界纸张自然清理后实际释放")
	_check_held_text(instance, contents, "主场景首件来源释放后")
	check(player.inventory_controller.cycle_focus(1) and player.inventory_controller.get_focused_instance() == null, "主场景正式切入另一空格")
	await frames(2)
	check(player.held_item_presenter.get_display() == null and player.held_item_presenter.call("get_quest_paper_view") == null and player.held_item_presenter.call("get_quest_paper_instance") == null, "主场景空格没有残留首件文字或绑定")
	check(player.inventory_controller.cycle_focus(-1), "主场景正式切回首件")
	await frames(2)
	_check_held_text(instance, contents, "主场景首次切回首件")
	if paper_pixel.x >= 0:
		await _click(paper_pixel)
	check(taken_count == 1, "旧纸张像素再次点击不重复取得文件")
	check(trigger.request_test_print() and machine.can_start_print(player), "取纸完成后再次受理测试事件")
	check(machine.cancel_print(machine.get_print_serial(), "专项更换下一份有效任务"), "待打印重复测试通过正式取消入口清理")
	await _wait(func() -> bool: return machine.state == AutolysisQuestMachine.PrintState.IDLE, "待打印取消自然恢复空闲")
	check(player.inventory_controller.cycle_focus(1), "主场景第二件选择不同空格")
	var second_definition := AutolysisQuestPrintDefinition.new()
	second_definition.task_id = "main_held_text_second_task"
	second_definition.data_lines = PackedStringArray(["主场景第二份任务", "委托编号：00109382", "第二份分组标题", "第二份独立末行"])
	second_definition.group_gap_before_lines = PackedInt32Array([2])
	check(machine.request_task_print(second_definition, player), "主场景实际受理不同全文的第二份任务")
	if button_pixel.x >= 0:
		await _click(button_pixel)
	check(started_count == 2 and machine.get_current_paper() != null, "主场景第二次真实打印按钮点击启动第二件")
	if machine.get_current_paper() == null:
		await _finish()
		return
	var second_source: AutolysisQuestPaper = machine.get_current_paper()
	var second_instance: AutolysisItemInstance = second_source.get_item_instance()
	var second_contents: AutolysisQuestPaperContents = second_instance.quest_paper_contents
	await _wait(func() -> bool: return completed_count == 2, "第二份默认打印自然完成", _print_wait_limit(second_definition.data_lines.size()))
	var second_pixel: Vector2 = _target_pixel(second_source)
	check(second_pixel.x >= 0, "第二件动态来源仍由正式相机射线命中")
	if second_pixel.x >= 0:
		await _click(second_pixel)
	check(taken_count == 2 and player.inventory_controller.get_slot_instance(0) == instance and player.inventory_controller.get_slot_instance(1) == second_instance and second_instance != instance, "第二次真实取纸将独立身份转移到另一携带格")
	await frames(3)
	check(not is_instance_valid(second_source), "主场景两件世界来源均完成实际释放")
	_check_held_text(second_instance, second_contents, "主场景第二件来源释放后")
	check(player.inventory_controller.cycle_focus(-1), "主场景两件之间切回首件")
	await frames(2)
	_check_held_text(instance, contents, "主场景两件之间切回首件")
	check(player.inventory_controller.cycle_focus(1), "主场景两件之间再切回第二件")
	await frames(2)
	_check_held_text(second_instance, second_contents, "主场景两件之间再切回第二件")
	await _finish()


func _finish() -> void:
	var directory: String = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/任务文件打印实施证据/20261007/主场景输入")
	DirAccess.make_dir_recursive_absolute(directory)
	var report := FileAccess.open(directory.path_join("主场景输入报告.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"方式": "无图形主场景；引擎内部键盘及鼠标按钮事件；无原生输入", "引擎": Engine.get_version_info(), "断言": checks, "事件": events, "打印轨迹": machine.get_print_snapshot(), "失败数": failures}, "\t"))
	world.queue_free()
	await frames(3)
	quit(1 if failures > 0 else 0)
