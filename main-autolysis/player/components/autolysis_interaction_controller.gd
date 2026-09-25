class_name AutolysisInteractionController
extends Node

signal direct_availability_changed(available: bool)

const DIRECT_ACTION: StringName = &"interact_direct"

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


func _init() -> void:
	# 暂停时也要清除准星的可用状态；执行许可仍由玩家统一判断。
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(actor: Node3D, detector: InteractionRayCast, input_allowed: Callable, inventory: AutolysisInventoryController) -> void:
	_actor = actor
	_detector = detector
	_input_allowed = input_allowed
	_inventory = inventory
	_has_published = false
	refresh_state()


func is_direct_available() -> bool:
	return _direct_available


func _process(_delta: float) -> void:
	refresh_state()


func refresh_state() -> void:
	_target = null
	_component = null
	if not _dependencies_valid():
		_publish_availability(false)
		return
	var held_item: AutolysisItemDefinition = _inventory.get_focused_item()
	_target = _detector.refresh_target(held_item != null and held_item.is_raw_material)
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
	var allowed: Variant = _input_allowed.call()
	_publish_availability(allowed is bool and allowed and _component.can_interact(_actor))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(DIRECT_ACTION):
		return
	# 点击前重新核对首个碰撞和当前业务状态，永不缓存请求。
	refresh_state()
	if not _direct_available:
		return
	var viewport: Viewport = get_viewport()
	var dispatched: bool = _component.try_interact(_actor)
	if dispatched and is_instance_valid(viewport):
		viewport.set_input_as_handled()
	# 效果可以禁用、移动或删除目标；此处不再使用旧组件引用。
	if is_instance_valid(self) and not is_queued_for_deletion():
		refresh_state()


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
