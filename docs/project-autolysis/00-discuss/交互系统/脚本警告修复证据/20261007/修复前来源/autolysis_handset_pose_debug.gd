class_name AutolysisHandsetPoseDebug
extends CanvasLayer
## 六轴局部姿态工具。只向匹配来源、展示实例与持物序号提交；不拥有持物业务。

signal pose_applied(position: Vector3, rotation_degrees: Vector3)
signal copy_text_ready(text: String)

@export var test_enabled: bool = true
@export var position_arrow_increment: float = 0.01
@export var rotation_arrow_increment: float = 1.0

var _source: WeakRef
var _display: WeakRef
var _serial: int = -1
var _source_id: int = 0
var _display_id: int = 0
var _initial_position: Vector3
var _initial_rotation_degrees: Vector3
var _apply_pose: Callable
var _validate_session: Callable
var _clipboard_writer: Callable
var _editing_enabled: bool = false
var _refreshing: bool = false
var _committing: bool = false
var _drafts: Dictionary = {}
var _fields: Array[SpinBox] = []

@onready var _layout: Control = $Layout
@onready var _panel: PanelContainer = $Layout/Panel
@onready var _grid: GridContainer = $Layout/Panel/Margin/Rows/Axes
@onready var _shortcut: Label = $Layout/Panel/Margin/Rows/Shortcut
@onready var _status: Label = $Layout/Panel/Margin/Rows/Status
@onready var _values_text: TextEdit = $Layout/Panel/Margin/Rows/Values
@onready var _copy_button: Button = $Layout/Panel/Margin/Rows/Buttons/Copy
@onready var _reset_button: Button = $Layout/Panel/Margin/Rows/Buttons/Reset


func _ready() -> void:
	for index: int in range(6):
		var field: SpinBox = _grid.get_node("Value%d" % index)
		field.step = 0.0
		field.allow_lesser = true
		field.allow_greater = true
		field.rounded = false
		field.custom_arrow_round = false
		field.custom_arrow_step = position_arrow_increment if index < 3 else rotation_arrow_increment
		field.update_on_text_changed = false
		field.localize_numeral_system = false
		field.mouse_force_pass_scroll_events = false
		field.gui_input.connect(_on_spin_gui_input.bind(index))
		field.value_changed.connect(_on_value_changed.bind(index))
		var edit: LineEdit = field.get_line_edit()
		edit.context_menu_enabled = false
		edit.mouse_force_pass_scroll_events = false
		edit.text_changed.connect(_on_text_changed.bind(index))
		edit.gui_input.connect(_on_field_gui_input.bind(index))
		edit.focus_exited.connect(_on_field_focus_exited.bind(index))
		_fields.append(field)
	_panel.gui_input.connect(_on_panel_gui_input)
	_copy_button.pressed.connect(request_copy)
	_reset_button.pressed.connect(reset_initial_pose)
	_update_visibility()


func bind_session(source: Node, display: Node3D, serial: int, initial_position: Vector3, initial_rotation_degrees: Vector3, apply_pose: Callable, validate_session: Callable) -> bool:
	if not is_node_ready() or not _node_is_live(source) or not _node_is_live(display):
		return false
	if not apply_pose.is_valid() or not validate_session.is_valid() or serial < 0:
		return false
	if not initial_position.is_finite() or not initial_rotation_degrees.is_finite():
		return false
	if not display.position.is_finite() or not display.rotation_degrees.is_finite():
		return false
	if not bool(validate_session.call(source, display, serial)) or not _node_is_live(source) or not _node_is_live(display):
		return false
	var same_occupancy: bool = _source_id == source.get_instance_id() and _serial == serial
	if same_occupancy and _display_id == display.get_instance_id():
		return true
	_discard_editing()
	_source = weakref(source)
	_display = weakref(display)
	_source_id = source.get_instance_id()
	_display_id = display.get_instance_id()
	_serial = serial
	_apply_pose = apply_pose
	_validate_session = validate_session
	if not same_occupancy:
		_initial_position = initial_position
		_initial_rotation_degrees = initial_rotation_degrees
	_refresh_from_display()
	_update_visibility()
	return true


func clear_session() -> void:
	_editing_enabled = false
	_discard_editing()
	_source = null
	_display = null
	_serial = -1
	_source_id = 0
	_display_id = 0
	_apply_pose = Callable()
	_validate_session = Callable()
	if is_node_ready():
		_values_text.text = ""
		_status.text = ""
		_update_visibility()


func set_editing_enabled(enabled: bool) -> void:
	if _editing_enabled == enabled:
		_update_visibility()
		return
	_editing_enabled = enabled
	if not enabled:
		_discard_editing()
		_refresh_from_display()
	_update_visibility()


func set_shortcut_text(text: String) -> void:
	if is_node_ready():
		_shortcut.text = text


func set_clipboard_writer(writer: Callable) -> void:
	_clipboard_writer = writer


func has_text_focus() -> bool:
	if not is_node_ready() or not _panel.visible or not _editing_enabled:
		return false
	for field: SpinBox in _fields:
		if field.get_line_edit().has_focus():
			return true
	return _values_text.has_focus()


func finish_editing() -> bool:
	if not commit_pending_fields():
		return false
	_discard_editing()
	_refresh_from_display()
	return true


func get_panel_rect() -> Rect2:
	return _panel.get_global_rect() if is_node_ready() and _panel.visible else Rect2()


func is_showing_pose() -> bool:
	return is_node_ready() and _panel.visible


func get_field(index: int) -> SpinBox:
	return _fields[index] if index >= 0 and index < _fields.size() else null


func get_values_text() -> String:
	return _values_text.text if is_node_ready() else ""


func commit_pending_fields() -> bool:
	if _committing or not _editing_enabled or not test_enabled or not _session_is_valid():
		return false
	if _drafts.is_empty():
		return true
	var values: Array[float] = []
	for index: int in range(6):
		if _drafts.has(index):
			var parsed: Dictionary = _parse_number(str(_drafts[index]))
			if not parsed.get("valid", false):
				_status.text = "第%d项输入无效：须为有限数值或有效数值表达式；未提交、未复制。" % (index + 1)
				return false
			values.append(float(parsed.value))
		else:
			values.append(_fields[index].value)
	var position: Vector3 = Vector3(values[0], values[1], values[2])
	var rotation_degrees: Vector3 = Vector3(values[3], values[4], values[5])
	if not position.is_finite() or not rotation_degrees.is_finite():
		_status.text = "输入超出有效变换数值；未提交、未复制。"
		return false
	return _submit_pose(position, rotation_degrees)


func request_copy() -> String:
	if not commit_pending_fields() or not _session_is_valid():
		return ""
	var display: Node3D = _display.get_ref() as Node3D
	var text: String = _format_pose(display.position, display.rotation_degrees)
	_values_text.text = text
	_status.text = "已生成当前六项数值。" if DisplayServer.get_name() == "headless" else "已复制当前六项数值。"
	if _clipboard_writer.is_valid():
		_clipboard_writer.call(text)
	elif DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(text)
	if is_instance_valid(self) and not is_queued_for_deletion():
		copy_text_ready.emit(text)
	return text


func reset_initial_pose() -> bool:
	if not _editing_enabled or not test_enabled or not _session_is_valid():
		return false
	_drafts.clear()
	return _submit_pose(_initial_position, _initial_rotation_degrees)


func _process(_delta: float) -> void:
	if _serial < 0:
		_update_visibility()
		return
	if not _session_is_valid():
		clear_session()
		return
	_update_visibility()
	if _drafts.is_empty() and not has_text_focus():
		_refresh_from_display()


func _unhandled_key_input(_event: InputEvent) -> void:
	if has_text_focus():
		get_viewport().set_input_as_handled()


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_panel.accept_event()


func _on_spin_gui_input(event: InputEvent, index: int) -> void:
	var field: SpinBox = _fields[index]
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		# 原生数值框拖动会捕获鼠标并定位指针；此工具只保留箭头及文本操作。
		field.accept_event()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		field.accept_event()


func _on_field_gui_input(event: InputEvent, index: int) -> void:
	var edit: LineEdit = _fields[index].get_line_edit()
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		# 在原生表达式提交前验证，避免无效表达式被旧值替换后冒充本次输入。
		commit_pending_fields()
		edit.accept_event()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		edit.accept_event()


func _on_text_changed(text: String, index: int) -> void:
	if not _refreshing and not _committing and _editing_enabled:
		_drafts[index] = text
		_status.text = "正在编辑；确认、失去焦点或复制时提交。"


func _on_field_focus_exited(index: int) -> void:
	if _refreshing or _committing or not _editing_enabled or not _drafts.has(index):
		return
	if not commit_pending_fields():
		# 原生编辑结束处理为延后执行。先供其安全数值，随后恢复保留的无效草稿。
		_fields[index].get_line_edit().text = str(_fields[index].value)
		_restore_draft.call_deferred(index, _serial, _display_id)


func _restore_draft(index: int, serial: int, display_id: int) -> void:
	if _serial == serial and _display_id == display_id and _drafts.has(index) and _editing_enabled:
		_fields[index].get_line_edit().text = str(_drafts[index])


func _on_value_changed(_value: float, index: int) -> void:
	if _refreshing or _committing or not _editing_enabled or not _drafts.is_empty():
		return
	var position: Vector3 = Vector3(_fields[0].value, _fields[1].value, _fields[2].value)
	var rotation_degrees: Vector3 = Vector3(_fields[3].value, _fields[4].value, _fields[5].value)
	if not position.is_finite() or not rotation_degrees.is_finite():
		_status.text = "第%d项数值无效；保持原姿态。" % (index + 1)
		_refresh_from_display()
		return
	_submit_pose(position, rotation_degrees)


func _submit_pose(position: Vector3, rotation_degrees: Vector3) -> bool:
	if _committing or not _session_is_valid():
		return false
	var source: Node = _source.get_ref() as Node
	var display: Node3D = _display.get_ref() as Node3D
	var serial: int = _serial
	var display_id: int = _display_id
	_committing = true
	var accepted: bool = bool(_apply_pose.call(source, display, serial, position, rotation_degrees))
	if not is_instance_valid(self) or is_queued_for_deletion():
		return false
	_committing = false
	if not accepted or _serial != serial or _display_id != display_id or not _session_is_valid():
		_status.text = "当前听筒会话已变化；未提交姿态。"
		return false
	_drafts.clear()
	_refresh_from_display()
	_status.text = "姿态已应用，仅修改听筒局部模型。"
	pose_applied.emit(position, rotation_degrees)
	return true


func _session_is_valid() -> bool:
	if _source == null or _display == null or not _validate_session.is_valid() or not _apply_pose.is_valid():
		return false
	var source: Node = _source.get_ref() as Node
	var display: Node3D = _display.get_ref() as Node3D
	if not _node_is_live(source) or not _node_is_live(display):
		return false
	var serial: int = _serial
	var source_id: int = _source_id
	var display_id: int = _display_id
	var valid: bool = bool(_validate_session.call(source, display, serial))
	return valid and _node_is_live(source) and _node_is_live(display) and _serial == serial and _source_id == source_id and _display_id == display_id


func _refresh_from_display() -> void:
	if not is_node_ready() or _display == null:
		return
	var display: Node3D = _display.get_ref() as Node3D
	if not _node_is_live(display):
		return
	var position: Vector3 = display.position
	var rotation_degrees: Vector3 = display.rotation_degrees
	var values: Array[float] = [position.x, position.y, position.z, rotation_degrees.x, rotation_degrees.y, rotation_degrees.z]
	_refreshing = true
	for index: int in range(6):
		_fields[index].set_value_no_signal(values[index])
		_fields[index].get_line_edit().text = str(values[index])
	_refreshing = false
	_values_text.text = _format_pose(position, rotation_degrees)


func _discard_editing() -> void:
	_drafts.clear()
	if not is_node_ready():
		return
	_refreshing = true
	for field: SpinBox in _fields:
		field.get_line_edit().text = str(field.value)
	var viewport: Viewport = get_viewport() if is_inside_tree() else null
	var owner: Control = viewport.gui_get_focus_owner() if is_instance_valid(viewport) else null
	if is_instance_valid(owner) and _panel.is_ancestor_of(owner):
		owner.release_focus()
	_refreshing = false


func _update_visibility() -> void:
	if not is_node_ready():
		return
	_panel.visible = test_enabled and _serial >= 0
	if not test_enabled:
		_discard_editing()
	for field: SpinBox in _fields:
		field.editable = _editing_enabled and test_enabled
		field.get_line_edit().focus_mode = Control.FOCUS_ALL if field.editable else Control.FOCUS_NONE
	_copy_button.disabled = not _editing_enabled or not test_enabled
	_reset_button.disabled = not _editing_enabled or not test_enabled
	_values_text.focus_mode = Control.FOCUS_ALL if _editing_enabled and test_enabled else Control.FOCUS_NONE
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_force_pass_scroll_events = false


func _parse_number(text: String) -> Dictionary:
	var expression: Expression = Expression.new()
	if expression.parse(text.strip_edges()) != OK:
		return {"valid": false}
	var value: Variant = expression.execute([], null, false, true)
	if expression.has_execute_failed() or not (value is float or value is int):
		return {"valid": false}
	return {"valid": is_finite(float(value)), "value": float(value)}


func _format_pose(position: Vector3, rotation_degrees: Vector3) -> String:
	return "局部参照：听筒模型相对手持呈现器；位置为局部坐标，旋转单位为度。\nhandset_held_position（听筒手持位置）＝Vector3（三维向量）(%s, %s, %s)\nhandset_held_rotation_degrees（听筒手持角度制旋转）＝Vector3（三维向量）(%s, %s, %s)" % [
		str(position.x), str(position.y), str(position.z),
		str(rotation_degrees.x), str(rotation_degrees.y), str(rotation_degrees.z),
	]


func _node_is_live(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()


func _exit_tree() -> void:
	clear_session()
