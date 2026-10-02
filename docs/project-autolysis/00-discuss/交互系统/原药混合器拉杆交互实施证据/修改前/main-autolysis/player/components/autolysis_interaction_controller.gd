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
var _request_mode: AutolysisInteractionComponent.InteractionMode = AutolysisInteractionComponent.InteractionMode.DIRECT


func _init() -> void:
	# 暂停时也要清除准星的可用状态；执行许可仍由玩家统一判断。
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(actor: Node3D, detector: InteractionRayCast, input_allowed: Callable, inventory: AutolysisInventoryController, focus: AutolysisFocusController = null) -> void:
	_actor = actor
	_detector = detector
	_input_allowed = input_allowed
	_inventory = inventory
	if is_instance_valid(_focus) and _focus.state_changed.is_connected(clear_pending_clicks):
		_focus.state_changed.disconnect(clear_pending_clicks)
	_focus = focus
	if is_instance_valid(_focus):
		_focus.state_changed.connect(clear_pending_clicks)
	_has_published = false
	refresh_state()


func is_direct_available() -> bool:
	return _direct_available


func _process(_delta: float) -> void:
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


func _handle_focus_input(event: InputEvent) -> void:
	if not _node_is_live(_actor) or not _actor is AutolysisPlayer:
		return
	var player: AutolysisPlayer = _actor as AutolysisPlayer
	if event.is_action_pressed(EXIT_ACTION):
		if player.is_focus_exit_allowed():
			_focus.request_exit()
			clear_pending_clicks()
			get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(DIRECT_ACTION) or not player.is_focus_input_allowed():
		return
	var mouse: Vector2 = event.position if event is InputEventMouseButton else get_viewport().get_mouse_position()
	_pending_clicks.append({
		"mouse": mouse, "session": _focus.session_id,
		"index": _inventory.get_focused_index(), "item": _inventory.get_focused_item(),
	})
	get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _pending_clicks.is_empty():
		return
	var clicks: Array[Dictionary] = _pending_clicks.duplicate()
	clear_pending_clicks()
	for click: Dictionary in clicks:
		if not _node_is_live(_focus) or not _dependencies_valid() or not _actor is AutolysisPlayer:
			return
		var player: AutolysisPlayer = _actor as AutolysisPlayer
		if not player.is_focus_input_allowed() or click["session"] != _focus.session_id:
			continue
		if click["index"] != _inventory.get_focused_index() or click["item"] != _inventory.get_focused_item():
			continue
		var descriptor: AutolysisFocusTarget = _focus.get_focus_target()
		var exclusions: Array[RID] = [player.get_rid(), player._found_area.get_rid()]
		var target: Node3D = _focus_query.query_target(player.camera, click["mouse"], descriptor, exclusions)
		if not _node_is_live(target) or not descriptor.owns_target(target):
			continue
		var components: Array[AutolysisInteractionComponent] = []
		for child: Node in target.get_children():
			if child is AutolysisInteractionComponent:
				components.append(child)
		if components.size() == 1:
			components[0].try_interact(_actor)


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
