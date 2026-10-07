extends SceneTree
## 面板专属无图形检查：真实控件、局部变换、会话身份及引擎内部输入消费。

const PANEL_SCENE: PackedScene = preload("res://main-autolysis/ui/autolysis_handset_pose_debug.tscn")
const EVIDENCE: Script = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd")

class Authority extends Node:
	var source: Node
	var display: Node3D
	var serial: int = 1
	var calls: int = 0
	var cache: Dictionary = {}

	func validates(candidate_source: Node, candidate_display: Node3D, candidate_serial: int) -> bool:
		return candidate_source == source and candidate_display == display and candidate_serial == serial

	func applies(candidate_source: Node, candidate_display: Node3D, candidate_serial: int, position: Vector3, rotation_degrees: Vector3) -> bool:
		if not validates(candidate_source, candidate_display, candidate_serial):
			return false
		calls += 1
		candidate_display.position = position
		candidate_display.rotation_degrees = rotation_degrees
		cache[candidate_source.get_instance_id()] = {"位置": position, "角度": rotation_degrees}
		return true


class WorldInput extends Node:
	var mouse_pressed: int = 0
	var keys_pressed: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			mouse_pressed += 1
		if event is InputEventKey and event.pressed:
			keys_pressed += 1


var failures: int = 0
var records: Array[Dictionary] = []
var observations: Array[Dictionary] = []
var copied: Array[String] = []
var world: Node3D
var authority: Authority
var input_sink: WorldInput
var panel: Node
var source_a: Node
var source_b: Node
var presenter: Node3D
var model: Node3D
var initial_position: Vector3 = Vector3(-0.1234567, 0.2468135, -0.7654321)
var initial_rotation: Vector3 = Vector3(-15.4321, 24.5678, -32.1234)
var original_accumulation: bool
var evidence_directory: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	evidence_directory = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/pose-panel")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	check(DisplayServer.get_name() == "headless", "本检查强制无图形后端，不启动图形窗口")
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	root.add_child(world)
	source_a = Node.new()
	source_b = Node.new()
	world.add_child(source_a)
	world.add_child(source_b)
	presenter = Node3D.new()
	world.add_child(presenter)
	presenter.position = Vector3(3.2, -1.2, 7.5)
	presenter.rotation_degrees = Vector3(9, 18, -11)
	model = Node3D.new()
	presenter.add_child(model)
	model.position = initial_position
	model.rotation_degrees = initial_rotation
	authority = Authority.new()
	world.add_child(authority)
	authority.source = source_a
	authority.display = model
	input_sink = WorldInput.new()
	world.add_child(input_sink)
	panel = PANEL_SCENE.instantiate()
	world.add_child(panel)
	await frames(3)
	panel.set_clipboard_writer(_capture_copy)
	await _test_binding_and_values()
	await _test_submission_copy_reset()
	await _test_input_consumption()
	await _test_sessions_and_optional_tool()
	_save_report()
	panel.clear_session()
	world.queue_free()
	await frames(3)
	Input.use_accumulated_input = original_accumulation
	print("听筒姿态面板断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)


func _test_binding_and_values() -> void:
	check(panel.test_enabled, "供用户调节的测试开关默认开启")
	check(_bind(initial_position, initial_rotation), "来源、实例与会话序号有效时绑定成功")
	panel.set_editing_enabled(true)
	await frames(2)
	check(panel.is_showing_pose(), "有效持物会话显示面板")
	check(authority.calls == 0, "回填六轴不再次应用姿态")
	var values: Array[float] = [model.position.x, model.position.y, model.position.z, model.rotation_degrees.x, model.rotation_degrees.y, model.rotation_degrees.z]
	for index: int in range(6):
		var field: SpinBox = panel.get_field(index)
		check(field.step == 0.0 and field.allow_lesser and field.allow_greater and not field.rounded, "第%d轴允许正负值与超范围且不量化" % (index + 1))
		check(absf(field.value - values[index]) < 0.000001, "第%d轴回填保留模型小数" % (index + 1))
		check(field.custom_arrow_step == (0.01 if index < 3 else 1.0), "第%d轴箭头增量仅由操作配置决定" % (index + 1))
	var rectangle: Rect2 = panel.get_panel_rect()
	observations.append({"用途": "无图形控件矩形测量，不证明图形布局适合", "面板矩形": str(rectangle), "视口尺寸": str(root.size)})
	check(rectangle.position.x > 0 and rectangle.end.x <= 1280 and rectangle.end.y < 720, "实际控件矩形位于右侧且未扩展至全屏")
	check(panel.get_node("Layout").mouse_filter == Control.MOUSE_FILTER_IGNORE, "全屏定位容器忽略鼠标")
	check(panel.get_node("Layout/Panel").mouse_filter == Control.MOUSE_FILTER_STOP and not panel.get_node("Layout/Panel").mouse_force_pass_scroll_events, "实际面板停止鼠标及滚轮传播")


func _test_submission_copy_reset() -> void:
	var parent_before: Transform3D = presenter.transform
	var scale_before: Vector3 = model.scale
	var before: Vector3 = model.position
	_draft(0, "-")
	check(model.position == before and authority.calls == 0, "未完成负号草稿不反复应用")
	check(panel.request_copy().is_empty() and copied.is_empty(), "无效草稿拒绝复制，不以旧数值冒充")
	_draft(0, "-0.314159265")
	_draft(1, "1 / 8.0")
	_draft(2, "-1.987654321")
	_draft(3, "-71.123456")
	_draft(4, "12 + 0.345678")
	_draft(5, "-6.543210")
	check(model.position == before, "六项有效草稿在提交前保持现有姿态")
	var text: String = panel.request_copy()
	check(not text.is_empty() and copied.size() == 1 and copied[0] == text, "复制先提交全部字段，再发出当前快照文本")
	check(authority.calls == 1, "六项文本一次成对提交")
	check(model.position.distance_to(Vector3(-0.314159265, 0.125, -1.987654321)) < 0.000001, "正负小数及表达式提交到模型局部位置")
	check(model.rotation_degrees.distance_to(Vector3(-71.123456, 12.345678, -6.543210)) < 0.0001, "三轴旋转使用角度制")
	check(text.contains("局部参照") and text.contains("旋转单位为度") and text.contains("handset_held_position（听筒手持位置）") and text.contains(str(model.position.x)), "复制文本含六值、局部参照、中文字段说明与角度单位")
	check(presenter.transform == parent_before and model.scale == scale_before, "姿态调节不改父呈现器或模型缩放")
	_draft(1, "1e100")
	check(panel.request_copy().is_empty() and copied.size() == 1, "不能形成有限三维变换的巨大值拒绝提交及复制")
	_draft(1, "sqrt(-1)")
	check(panel.request_copy().is_empty(), "非有限表达式拒绝复制")
	_draft(1, "Vector3(1, 2, 3)")
	check(panel.request_copy().is_empty(), "非数值表达式拒绝复制")
	check(panel.reset_initial_pose(), "恢复初始值忽略未提交草稿并提交取下时快照")
	check(model.position.distance_to(initial_position) < 0.000001 and model.rotation_degrees.distance_to(initial_rotation) < 0.0001, "重置准确回到本次取下六轴起始姿态")
	check(panel.get_values_text() == panel.request_copy(), "重置后界面与复制读取同一模型快照")
	var calls_before: int = authority.calls
	panel.get_field(2).value = -0.2222222
	check(authority.calls == calls_before + 1 and absf(model.position.z + 0.2222222) < 0.000001, "控件即时数值改变直接应用且不量化")
	await frames(2)
	check(authority.calls == calls_before + 1, "后续同步回填不重复提交")


func _test_input_consumption() -> void:
	var inside: Vector2 = panel.get_panel_rect().position + Vector2(10, 10)
	var outside: Vector2 = Vector2(160, 120)
	var before: int = input_sink.mouse_pressed
	for button: int in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_mouse_button(inside, button, true)
		_mouse_button(inside, button, false)
	await frames(2)
	check(input_sink.mouse_pressed == before, "面板实际矩形消费左右键与正反滚轮")
	_mouse_button(outside, MOUSE_BUTTON_RIGHT, true)
	_mouse_button(outside, MOUSE_BUTTON_RIGHT, false)
	await frames(2)
	check(input_sink.mouse_pressed == before + 1, "面板外右键保留世界输入")
	var field: SpinBox = panel.get_field(0)
	var edit: LineEdit = field.get_line_edit()
	edit.grab_focus()
	await frames(2)
	check(panel.has_text_focus(), "六轴文本编辑真实取得焦点")
	var key_before: int = input_sink.keys_pressed
	var position_before: Vector3 = model.position
	_draft(0, "-0.3333333")
	_key(KEY_ENTER, 0, true)
	_key(KEY_ENTER, 0, false)
	await frames(2)
	check(absf(model.position.x + 0.3333333) < 0.000001 and model.position != position_before, "引擎内部确认键提交正在编辑的数值")
	check(input_sink.keys_pressed == key_before, "确认键不进入世界交互")
	edit.select_all()
	_key(KEY_E, 101, true)
	_key(KEY_E, 101, false)
	await frames(2)
	check(input_sink.keys_pressed == key_before and edit.text == "e", "文本按键由控件消费，世界交互快捷键不入队")
	edit.select_all()
	_key(KEY_P, 112, true)
	_key(KEY_P, 112, false)
	await frames(2)
	check(input_sink.keys_pressed == key_before and edit.text == "p", "单行文本框会消费普通字母姿态快捷键，玩家关闭调节态必须在前置输入处理")
	_draft(0, "-")
	panel.get_node("Layout/Panel/Margin/Rows/Buttons/Copy").grab_focus()
	await frames(3)
	check(panel.request_copy().is_empty() and edit.text == "-", "失去焦点后仍保留无效草稿且复制拒绝旧值")
	panel.reset_initial_pose()
	edit.grab_focus()
	_draft(0, "-0.54321")
	panel.get_node("Layout/Panel/Margin/Rows/Buttons/Copy").grab_focus()
	await frames(3)
	check(absf(model.position.x + 0.54321) < 0.000001, "文本失去焦点时提交有效值")
	var arrow_before: float = model.position.x
	var arrow_point: Vector2 = field.get_global_rect().position + Vector2(field.size.x - 7, field.size.y * 0.25)
	_mouse_button(arrow_point, MOUSE_BUTTON_LEFT, true)
	_mouse_button(arrow_point, MOUSE_BUTTON_LEFT, false)
	await frames(3)
	check(absf(model.position.x - arrow_before - field.custom_arrow_step) < 0.000001, "真实箭头按钮使用独立增量即时应用")
	var button_before: int = input_sink.mouse_pressed
	var pose_before: Vector3 = model.position
	_mouse_button(arrow_point, MOUSE_BUTTON_RIGHT, true)
	_mouse_button(arrow_point, MOUSE_BUTTON_RIGHT, false)
	_mouse_button(arrow_point, MOUSE_BUTTON_WHEEL_DOWN, true)
	_mouse_button(arrow_point, MOUSE_BUTTON_WHEEL_DOWN, false)
	await frames(2)
	check(input_sink.mouse_pressed == button_before and model.position == pose_before, "数值框内右键与滚轮消费且不跳到默认上下限")
	edit.grab_focus()
	_draft(0, "-4.2")
	check(_bind(Vector3(9, 9, 9), Vector3(90, 90, 90)) and edit.text == "-4.2" and panel.has_text_focus(), "逐帧重复绑定不覆盖草稿或释放焦点")
	panel.set_editing_enabled(false)
	await frames(3)
	check(not panel.has_text_focus() and not edit.has_focus() and edit.text != "-4.2", "停止编辑释放焦点并清除未提交草稿")
	check(panel.is_showing_pose() and model.position == pose_before, "停止编辑继续显示且保留现有持筒姿态")
	panel.set_editing_enabled(true)
	edit.grab_focus()
	_draft(0, "-0.6789")
	_mouse_button(outside, MOUSE_BUTTON_LEFT, true)
	_mouse_button(outside, MOUSE_BUTTON_LEFT, false)
	await frames(3)
	observations.append({"用途": "文本焦点后面板外世界点击探针", "文本仍有焦点": panel.has_text_focus(), "实际局部横轴": model.position.x, "世界鼠标累计": input_sink.mouse_pressed})
	check(panel.finish_editing() and not panel.has_text_focus() and absf(model.position.x + 0.6789) < 0.000001, "世界入口可显式结束编辑，提交有效草稿并释放文本焦点")
	edit.grab_focus()
	_draft(0, "-")
	check(not panel.finish_editing() and panel.has_text_focus() and edit.text == "-" and absf(model.position.x + 0.6789) < 0.000001, "世界入口遇到无效草稿拒绝本次点击并保留文本焦点与错误草稿")
	panel.reset_initial_pose()


func _test_sessions_and_optional_tool() -> void:
	check(panel.reset_initial_pose() and model.position.distance_to(initial_position) < 0.000001, "重复绑定没有重新定义本次初始快照")
	var old_model: Node3D = model
	model = Node3D.new()
	presenter.add_child(model)
	model.position = Vector3(-2, 1, 0.4)
	model.rotation_degrees = Vector3(4, 5, 6)
	authority.display = model
	check(_bind(Vector3(8, 8, 8), Vector3(80, 80, 80)), "同来源同序号允许重新绑定恢复的展示实例")
	old_model.queue_free()
	await frames(2)
	check(panel.reset_initial_pose() and model.position.distance_to(initial_position) < 0.000001, "恢复展示实例仍使用原取下初始快照")
	var source_a_pose: Dictionary = authority.cache[source_a.get_instance_id()].duplicate()
	authority.source = source_b
	authority.serial += 1
	var initial_b_position: Vector3 = Vector3(-0.7, 0.3, -0.2)
	var initial_b_rotation: Vector3 = Vector3(16, -9, 7)
	model.position = initial_b_position
	model.rotation_degrees = initial_b_rotation
	check(_bind(initial_b_position, initial_b_rotation), "另一电话绑定自己的初始姿态")
	_draft(2, "-0.456789")
	check(panel.commit_pending_fields() and authority.cache[source_a.get_instance_id()] == source_a_pose, "调节另一来源不修改前一来源缓存")
	check(panel.reset_initial_pose() and model.position == initial_b_position, "另一来源重置使用独立初始快照")
	var calls_before: int = authority.calls
	authority.serial += 1
	_draft(0, "-1.5")
	check(not panel.commit_pending_fields() and authority.calls == calls_before, "旧持物序号不能提交到后续会话")
	await frames(2)
	check(not panel.is_showing_pose() and not panel.has_text_focus(), "会话失效自动隐藏并解除编辑绑定")
	check(_bind(model.position, model.rotation_degrees), "新会话可以重新绑定")
	panel.set_editing_enabled(true)
	panel.test_enabled = false
	await frames(2)
	check(not panel.is_showing_pose() and not panel.commit_pending_fields() and authority.source == source_b, "关闭可选调节工具只停界面，不改来源占用事实")
	panel.test_enabled = true
	await frames(2)
	check(panel.is_showing_pose(), "重新开启测试工具恢复当前会话显示")
	source_b.queue_free()
	await frames(3)
	check(not panel.is_showing_pose() and not panel.has_text_focus(), "来源排队释放清理绑定且不调用已释放对象")
	panel.clear_session()
	panel.clear_session()
	check(not panel.is_showing_pose(), "重复清除面板会话幂等")
	world.remove_child(panel)
	panel.clear_session()
	panel.clear_session()
	check(is_instance_valid(panel) and not panel.is_inside_tree(), "面板已离树时仍可重复清理，无空视口访问")
	panel.free()
	panel = PANEL_SCENE.instantiate()
	world.add_child(panel)


func _bind(position: Vector3, rotation_degrees: Vector3) -> bool:
	return bool(panel.bind_session(authority.source, model, authority.serial, position, rotation_degrees, authority.applies, authority.validates))


func _draft(index: int, text: String) -> void:
	var edit: LineEdit = panel.get_field(index).get_line_edit()
	edit.text = text
	edit.text_changed.emit(text)


func _capture_copy(text: String) -> void:
	copied.append(text)


func _mouse_button(position: Vector2, button: int, pressed: bool) -> void:
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.position = position
	move.global_position = position
	Input.parse_input_event(move)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _key(keycode: Key, unicode: int, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.unicode = unicode
	event.pressed = pressed
	Input.parse_input_event(event)


func frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func check(condition: bool, description: String) -> void:
	records.append({"说明": description, "通过": condition})
	if condition:
		print("通过：", description)
	else:
		failures += 1
		print("失败：", description)


func _save_report() -> void:
	var report: Dictionary = {"验收方式": "无图形真实控件及引擎内部输入注入；未执行图形、原生系统输入或真实剪贴板", "断言数": records.size(), "失败数": failures, "断言": records, "矩形测量": observations, "复制快照": copied}
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("面板控件验收.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
