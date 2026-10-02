class_name AutolysisInteractionController
extends Node

signal direct_availability_changed(available: bool)

const DIRECT_ACTION: StringName = &"interact_direct"
const EXIT_ACTION: StringName = &"focus_exit"

var _actor: Node3D
var _detector: InteractionRayCast
var _inventory: AutolysisInventoryController
var _input_allowed: Callable
var _target: Node3D
var _component: AutolysisInteractionComponent
var _direct_available: bool = false
var _has_published: bool = false
var _reported_target_id: int = 0
var _reported_component_ids: Array[int] = []
var _focus: AutolysisFocusController
var _focus_query: AutolysisFocusRayQuery = AutolysisFocusRayQuery.new()
var _pending_clicks: Array[Dictionary] = []
var _drag_events: Array[Dictionary] = []
var _next_sequence: int = 0
var _capture_sequence: int = 0
var _drag_sequence: int = 0
var _drag_session: int = -1
var _drag_target: AutolysisBlendHandle
var _drag_viewport_rect: Rect2
var _drag_screen_transform: Transform2D
var _drag_window_position: Vector2i
var _accumulation_saved: bool = false
var _original_accumulation: bool = true
var _focus_accumulation_saved: bool = false
var _focus_original_accumulation: bool = true
var _last_drag_motion: Vector2 = Vector2.ZERO
var _last_drag_position: Vector2 = Vector2.ZERO
var _warp_pending: bool = false
var _warp_delta: Vector2 = Vector2.ZERO
var _warp_origin: Vector2 = Vector2.ZERO
var _warp_destination: Vector2 = Vector2.ZERO
var _request_mode: AutolysisInteractionComponent.InteractionMode = AutolysisInteractionComponent.InteractionMode.DIRECT


func _init() -> void:
	# 暂停时也要清除准星的可用状态；执行许可仍由玩家统一判断。
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(actor: Node3D, detector: InteractionRayCast, input_allowed: Callable, inventory: AutolysisInventoryController, focus: AutolysisFocusController = null) -> void:
	_actor = actor
	_detector = detector
	_input_allowed = input_allowed
	_inventory = inventory
	cancel_focus_drag()
	_restore_focus_accumulation()
	if is_instance_valid(_focus) and _focus.state_changed.is_connected(_on_focus_state_changed):
		_focus.state_changed.disconnect(_on_focus_state_changed)
	_focus = focus
	if is_instance_valid(_focus):
		_focus.state_changed.connect(_on_focus_state_changed)
	_has_published = false
	refresh_state()


func is_direct_available() -> bool:
	return _direct_available


func _process(_delta: float) -> void:
	if _drag_sequence != 0 and not _drag_context_valid():
		cancel_focus_drag()
	_sync_focus_accumulation()
	refresh_state()


func refresh_state() -> void:
	_target = null
	_component = null
	_request_mode = AutolysisInteractionComponent.InteractionMode.DIRECT
	if is_instance_valid(_focus) and _focus.has_control():
		_publish_availability(false)
		return
	if not _dependencies_valid():
		_publish_availability(false)
		return
	var held_item: AutolysisItemDefinition = _inventory.get_focused_item()
	var holds_liquid_tank: bool = held_item != null and not held_item.is_raw_material and held_item.item_id == &"liquid_tank"
	_target = _detector.refresh_target(held_item != null and held_item.is_raw_material, holds_liquid_tank)
	if not _node_is_live(_target):
		_reported_target_id = 0
		_reported_component_ids.clear()
		_publish_availability(false)
		return

	var components: Array[AutolysisInteractionComponent] = []
	var component_ids: Array[int] = []
	for child: Node in _target.get_children():
		if child is AutolysisInteractionComponent:
			components.append(child)
			component_ids.append(child.get_instance_id())
	if components.size() != 1:
		if components.size() > 1:
			var target_id: int = _target.get_instance_id()
			if target_id != _reported_target_id or component_ids != _reported_component_ids:
				push_warning("交互目标必须恰好配置一个直接子交互组件：%s" % _target.get_path())
				_reported_target_id = target_id
				_reported_component_ids = component_ids
		_publish_availability(false)
		return
	_reported_target_id = 0
	_reported_component_ids.clear()
	_component = components[0]
	if _component.interaction_mode == AutolysisInteractionComponent.InteractionMode.FOCUS:
		if not _has_matching_focus_target():
			_publish_availability(false)
			return
		_request_mode = AutolysisInteractionComponent.InteractionMode.FOCUS
	var allowed: Variant = _input_allowed.call()
	_publish_availability(allowed is bool and allowed and _component.can_interact(_actor, _request_mode))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or (event is InputEventMouseButton and event.canceled):
		return
	if is_instance_valid(_focus) and _focus.has_control():
		_handle_focus_input(event)
		return
	if not event.is_action_pressed(DIRECT_ACTION):
		return
	# 点击前重新核对首个碰撞和当前业务状态，永不缓存请求。
	refresh_state()
	if not _direct_available:
		return
	var viewport: Viewport = get_viewport()
	var dispatched: bool = _component.try_interact(_actor, _request_mode)
	if dispatched and is_instance_valid(viewport):
		viewport.set_input_as_handled()
	# 效果可以禁用、移动或删除目标；此处不再使用旧组件引用。
	if is_instance_valid(self) and not is_queued_for_deletion():
		refresh_state()


func _has_matching_focus_target() -> bool:
	if not _node_is_live(_focus):
		return false
	var descriptors: Array[AutolysisFocusTarget] = []
	for child: Node in _target.get_children():
		if child is AutolysisFocusTarget:
			descriptors.append(child)
	return descriptors.size() == 1 and descriptors[0].is_valid_target() and descriptors[0].device_root == _target and descriptors[0].root_interaction == _component


func clear_pending_clicks() -> void:
	_pending_clicks.clear()
	# 切格只作废开始请求，已经绑定的持续事件仍按顺序处理。
	if _capture_sequence != _drag_sequence:
		_capture_sequence = 0
	_restore_accumulation_if_unused()


func is_drag_active() -> bool:
	return _node_is_live(_drag_target) and _drag_target.is_dragging_for(_actor)


func get_drag_target() -> AutolysisBlendHandle:
	return _drag_target if is_drag_active() else null


func cancel_focus_drag() -> void:
	var handle: AutolysisBlendHandle = _drag_target
	_clear_drag_binding()
	_pending_clicks.clear()
	_drag_events.clear()
	_capture_sequence = 0
	_restore_accumulation_if_unused()
	if _node_is_live(handle):
		handle.cancel_drag(_actor)


## 玩家前置输入只观察持续事件；开始仍须经过未处理输入和物理射线。
func observe_focus_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.canceled:
		cancel_focus_drag()
		return
	if _capture_sequence == 0:
		return
	if not _focus_input_valid():
		cancel_focus_drag()
		return
	if event is InputEventMouseMotion:
		var relative: Vector2 = event.relative
		if _warp_pending:
			# 原生消息已在定位前排空；只扣程序定位分量，保留同消息中的真实移动。
			var inferred_origin: Vector2 = event.position - event.relative
			if inferred_origin.distance_to(_warp_origin) <= 0.01:
				relative -= _warp_delta
			elif inferred_origin.distance_to(_warp_destination) > 0.01 and not event.relative.is_zero_approx():
				# 后端基准与实际取证不符时停止本次拖动，禁止推测一个整屏补偿量。
				push_warning("拉杆鼠标定位基准不符，取消拖动：旧基准=%s；定位前=%s；定位后=%s" % [inferred_origin, _warp_origin, _warp_destination])
				cancel_focus_drag()
				return
			_warp_pending = false
			_warp_delta = Vector2.ZERO
		_drag_events.append({"kind": &"motion", "sequence": _capture_sequence,
			"session": _focus.session_id, "position": event.position, "relative": relative})
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_events.append({"kind": &"release", "sequence": _capture_sequence, "session": _focus.session_id})
		_capture_sequence = 0


func _handle_focus_input(event: InputEvent) -> void:
	if not _node_is_live(_actor) or not _actor is AutolysisPlayer:
		return
	var player: AutolysisPlayer = _actor as AutolysisPlayer
	if event.is_action_pressed(EXIT_ACTION):
		if player.is_focus_exit_allowed():
			if _focus.state == AutolysisFocusController.FocusState.FOCUSED and (is_drag_active() or not _pending_clicks.is_empty()):
				_drag_events.append({"kind": &"exit", "session": _focus.session_id})
				_capture_sequence = 0
			else:
				cancel_focus_drag()
				_focus.request_exit()
			get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(DIRECT_ACTION) or not player.is_focus_input_allowed():
		return
	var left_mouse: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	# 释放已入队后可接收新的按下；是否已归位由物理队列中的真实拉杆状态决定。
	if (left_mouse and _capture_sequence != 0) or (not left_mouse and is_drag_active()):
		get_viewport().set_input_as_handled()
		return
	var mouse: Vector2 = event.position if event is InputEventMouseButton else get_viewport().get_mouse_position()
	_next_sequence += 1
	var click: Dictionary = {
		"kind": &"begin", "sequence": _next_sequence,
		"left_mouse": left_mouse,
		"mouse": mouse, "session": _focus.session_id,
		"index": _inventory.get_focused_index(), "item": _inventory.get_focused_item(),
	}
	_pending_clicks.append(click)
	_drag_events.append(click)
	if left_mouse:
		_capture_sequence = _next_sequence
		_save_accumulation()
	get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	_sync_focus_accumulation()
	if not _focus_input_valid():
		cancel_focus_drag()
		return
	if _drag_sequence != 0 and not _drag_context_valid():
		cancel_focus_drag()
		return
	if is_drag_active() or not _pending_clicks.is_empty():
		# 排空窗口消息和引擎缓冲，避免对物理帧前的旧边缘事件定位。
		DisplayServer.process_events()
		if not is_instance_valid(self):
			return
	_drain_drag_events()
	if not is_instance_valid(self):
		return
	# 按钮状态仅作有序队列处理后的兜底，保留同帧按下、到最低、松开。
	if is_drag_active() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var handle: AutolysisBlendHandle = _drag_target
		_clear_drag_binding()
		handle.release_drag(_actor)
	if is_drag_active() and _drag_context_valid():
		_wrap_drag_cursor()
		if not is_instance_valid(self):
			return
		_drain_drag_events()
		if not is_instance_valid(self):
			return
	if _pending_clicks.is_empty() and not is_drag_active():
		_capture_sequence = 0
	_restore_accumulation_if_unused()


func _drain_drag_events() -> void:
	var events: Array[Dictionary] = _drag_events
	_drag_events = []
	for entry: Dictionary in events:
		if not _focus_input_valid() or entry["session"] != _focus.session_id:
			cancel_focus_drag()
			break
		if entry["kind"] == &"exit":
			cancel_focus_drag()
			_focus.request_exit()
			break
		if entry["kind"] == &"begin":
			if _pending_clicks.has(entry):
				_pending_clicks.erase(entry)
				_dispatch_focus_click(entry)
			continue
		if entry["sequence"] != _drag_sequence or not _drag_context_valid():
			continue
		if entry["kind"] == &"release":
			var handle: AutolysisBlendHandle = _drag_target
			_clear_drag_binding()
			handle.release_drag(_actor)
		elif entry["kind"] == &"motion":
			_last_drag_motion = entry["relative"]
			_last_drag_position = entry["position"]
			_drag_target.apply_vertical_motion(_actor, entry["relative"].y)
			if not is_instance_valid(self):
				return
			if not is_drag_active():
				_clear_drag_binding()


func _dispatch_focus_click(click: Dictionary) -> void:
	if is_drag_active() or click["index"] != _inventory.get_focused_index() or click["item"] != _inventory.get_focused_item():
		return
	var player: AutolysisPlayer = _actor as AutolysisPlayer
	var descriptor: AutolysisFocusTarget = _focus.get_focus_target()
	var exclusions: Array[RID] = [player.get_rid(), player._found_area.get_rid()]
	var target: Node3D = _focus_query.query_target(player.camera, click["mouse"], descriptor, exclusions)
	if not _node_is_live(target) or not descriptor.owns_target(target):
		return
	var components: Array[AutolysisInteractionComponent] = []
	for child: Node in target.get_children():
		if child is AutolysisInteractionComponent:
			components.append(child)
	if components.size() != 1:
		return
	var handle: AutolysisBlendHandle = descriptor.get_handle_for_target(target)
	if handle != null and not click["left_mouse"]:
		return
	components[0].try_interact(_actor)
	if not is_instance_valid(self):
		return
	if _node_is_live(handle) and handle.is_dragging_for(_actor) and _focus_input_valid() and click["session"] == _focus.session_id:
		_drag_target = handle
		_drag_sequence = click["sequence"]
		_drag_session = click["session"]
		_drag_viewport_rect = get_viewport().get_visible_rect()
		_drag_screen_transform = get_viewport().get_screen_transform()
		_drag_window_position = get_window().position


func _focus_input_valid() -> bool:
	return _node_is_live(_focus) and _dependencies_valid() and _actor is AutolysisPlayer and _actor.is_focus_input_allowed()


func _drag_context_valid() -> bool:
	if not _focus_input_valid() or not is_drag_active() or _drag_session != _focus.session_id:
		return false
	var descriptor: AutolysisFocusTarget = _focus.get_focus_target()
	if descriptor == null or not descriptor.owns_target(_drag_target):
		return false
	return _drag_viewport_rect == get_viewport().get_visible_rect() and _drag_screen_transform == get_viewport().get_screen_transform() and _drag_window_position == get_window().position


func _clear_drag_binding() -> void:
	if _capture_sequence == _drag_sequence:
		_capture_sequence = 0
	_drag_target = null
	_drag_sequence = 0
	_drag_session = -1
	_last_drag_motion = Vector2.ZERO
	_last_drag_position = Vector2.ZERO
	_warp_pending = false
	_warp_delta = Vector2.ZERO


func _save_accumulation() -> void:
	if _accumulation_saved:
		return
	_original_accumulation = Input.use_accumulated_input
	_accumulation_saved = true
	Input.use_accumulated_input = false


func _restore_accumulation_if_unused() -> void:
	if _accumulation_saved and _pending_clicks.is_empty() and _drag_events.is_empty() and not is_drag_active():
		Input.use_accumulated_input = _original_accumulation
		_accumulation_saved = false


func _on_focus_state_changed() -> void:
	cancel_focus_drag()
	_sync_focus_accumulation()


func _sync_focus_accumulation() -> void:
	if _focus_input_valid():
		if not _focus_accumulation_saved:
			_focus_original_accumulation = Input.use_accumulated_input
			_focus_accumulation_saved = true
		# 在新按下到来前关闭累积，避免同一原生消息批内的下拉与反推已被合并。
		Input.use_accumulated_input = false
	elif not _accumulation_saved:
		_restore_focus_accumulation()


func _restore_focus_accumulation() -> void:
	if _focus_accumulation_saved:
		Input.use_accumulated_input = _focus_original_accumulation
		_focus_accumulation_saved = false


func _wrap_drag_cursor() -> void:
	if _warp_pending or DisplayServer.get_name() == "headless" or not get_window().has_focus():
		return
	var viewport: Viewport = get_viewport()
	var before: Vector2 = viewport.get_mouse_position()
	var scale_y: float = _drag_screen_transform.y.length()
	if scale_y <= 0.0:
		cancel_focus_drag()
		return
	var edge_margin: float = 2.0 / scale_y
	var landing_margin: float = 4.0 / scale_y
	var destination: Vector2 = before
	if _last_drag_motion.y > 0.0 and before.y >= _drag_viewport_rect.end.y - edge_margin:
		destination.y = _drag_viewport_rect.position.y + landing_margin
	elif _last_drag_motion.y < 0.0 and before.y <= _drag_viewport_rect.position.y + edge_margin:
		destination.y = _drag_viewport_rect.end.y - landing_margin
	else:
		return
	# 此变换与引擎视口定位接口相同：顶层得到客户区坐标，嵌入窗口包含父变换。
	_warp_origin = _last_drag_position
	Input.warp_mouse((_drag_screen_transform * destination).round())
	_warp_destination = viewport.get_mouse_position()
	_warp_delta = _warp_destination - before
	_warp_pending = not _warp_delta.is_zero_approx()
	# 同步读取定位回声，避免下一次定位与尚未解析的定位量叠加。
	DisplayServer.process_events()


func _exit_tree() -> void:
	cancel_focus_drag()
	_restore_focus_accumulation()


func _dependencies_valid() -> bool:
	if not _node_is_live(_actor) or not _node_is_live(_detector) or not _node_is_live(_inventory):
		return false
	if not _input_allowed.is_valid():
		return false
	var receiver: Object = _input_allowed.get_object()
	if receiver is Node and not _node_is_live(receiver):
		return false
	return true


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()


func _publish_availability(available: bool) -> void:
	if _has_published and available == _direct_available:
		return
	_direct_available = available
	_has_published = true
	direct_availability_changed.emit(available)
