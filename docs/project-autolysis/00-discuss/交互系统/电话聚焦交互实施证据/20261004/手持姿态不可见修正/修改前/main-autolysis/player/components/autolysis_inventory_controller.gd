class_name AutolysisInventoryController
extends Node
## 四格状态与道具转移的唯一写入入口；通知发出前各处占用已经一致。

signal inventory_changed()
signal held_item_changed()

const SLOT_COUNT: int = 4
const LIQUID_TANK_ID: StringName = &"liquid_tank"
const PNEUMATIC_CAPSULE_ID: StringName = &"pneumatic_capsule"
const NEXT_ACTION: StringName = &"inventory_next"
const PREVIOUS_ACTION: StringName = &"inventory_previous"

var _slots: Array[AutolysisItemInstance] = []
var _focused_index: int = 0
var _busy: bool = false
var _publishing: bool = false
var _publication_depth: int = 0
var _presenter: AutolysisHeldItemPresenter
var _input_allowed: Callable
var _holding_revision: int = 0
var _handset_counter: int = 0
var _handset_source: Node3D
var _handset_actor: Node3D
var _handset_session: int = 0
var _handset_session_committed: bool = false
var _handset_scene: PackedScene
var _handset_position: Vector3
var _handset_rotation: Vector3
var _handset_scale: Vector3 = Vector3.ONE
var _handset_initial_pose: Dictionary = {}
var _handset_pose_cache: Dictionary = {}
var _handset_transfer_source: Node3D
var _handset_transfer_actor: Node3D
var _handset_transfer_token: int = 0
var _handset_transfer_returning: bool = false
var _handset_transfer_index: int = -1
var _handset_transfer_revision: int = 0
var _handset_transfer_focus: int = 0
var _handset_candidate: Node3D
var _handset_transfer_scene: PackedScene
var _handset_transfer_pose: Dictionary = {}
var _handset_cleaning: bool = false
var last_handset_abort_reason: String = ""


func _init() -> void:
	_slots.resize(SLOT_COUNT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(presenter: AutolysisHeldItemPresenter, input_allowed: Callable) -> void:
	_presenter = presenter
	_input_allowed = input_allowed


func get_holding_revision() -> int:
	return _holding_revision


func has_exclusive_handset() -> bool:
	return _handset_session > 0


func is_actually_empty_handed() -> bool:
	return get_focused_instance() == null and _ordinary_hands_available()


func get_handset_transfer_pending() -> bool:
	return _handset_transfer_token > 0


func get_handset_source() -> Node3D:
	return _handset_source if _node_is_live(_handset_source) else null


func get_handset_session_id() -> int:
	return _handset_session


func get_handset_display() -> Node3D:
	return _presenter.get_display() if _handset_session > 0 and _node_is_live(_presenter) else null


func get_handset_pose_snapshot() -> Dictionary:
	return _handset_initial_pose.duplicate()


func get_handset_session_snapshot() -> Dictionary:
	var display: Node3D = get_handset_display()
	if not is_handset_display_session(_handset_source, display, _handset_session):
		return {}
	return {"source": _handset_source, "display": display, "serial": _handset_session,
		"initial_position": _handset_initial_pose["position"],
		"initial_rotation_degrees": _handset_initial_pose["rotation_degrees"]}


func can_take_handset(actor: Node3D, source: Node3D) -> bool:
	return not _busy and is_actually_empty_handed() and _handset_actor_valid(actor, source)


func begin_handset_take(actor: Node3D, source: Node3D, scene: PackedScene, position_value: Vector3, rotation_value: Vector3, scale_value: Vector3) -> int:
	if not can_take_handset(actor, source):
		return 0
	var pose: Dictionary = _cached_handset_pose(source, position_value, rotation_value)
	if not _presenter.can_prepare_handset(scene, pose["position"], pose["rotation_degrees"], scale_value):
		return 0
	_start_handset_transfer(actor, source, false)
	_handset_transfer_scene = scene
	_handset_transfer_pose = pose.duplicate()
	_handset_transfer_pose["scale"] = scale_value
	_handset_candidate = _presenter.prepare_handset(scene, pose["position"], pose["rotation_degrees"], scale_value)
	if not is_instance_valid(_handset_candidate):
		_clear_handset_transfer()
		_busy = false
		return 0
	return _handset_transfer_token


func can_return_handset(actor: Node3D, source: Node3D) -> bool:
	return not _busy and _handset_session > 0 and _handset_source == source and _handset_actor == actor and _handset_actor_valid(actor, source) and is_handset_display_session(source, get_handset_display(), _handset_session)


func begin_handset_return(actor: Node3D, source: Node3D) -> int:
	if not can_return_handset(actor, source):
		return 0
	_start_handset_transfer(actor, source, true)
	return _handset_transfer_token


func is_handset_transfer_current(actor: Node3D, source: Node3D, token: int) -> bool:
	if token <= 0 or _handset_transfer_token != token or _handset_transfer_source != source or _handset_transfer_actor != actor or not _busy or _handset_cleaning:
		return false
	if _focused_index != _handset_transfer_index or _holding_revision != _handset_transfer_revision or not _handset_actor_valid(actor, source):
		return false
	if (actor as AutolysisPlayer).focus_controller.session_id != _handset_transfer_focus or get_focused_instance() != null:
		return false
	if _handset_transfer_returning:
		return _handset_actor == actor and _handset_source == source and _handset_session > 0 and is_handset_display_session(source, get_handset_display(), _handset_session)
	return _handset_session == 0 and is_instance_valid(_handset_candidate) and not _handset_candidate.is_queued_for_deletion() and _handset_candidate.get_parent() == null


func commit_handset_take(actor: Node3D, source: Node3D, token: int, commit_source: Callable, rollback_source: Callable, notify_source: Callable) -> bool:
	if not is_handset_transfer_current(actor, source, token) or _handset_transfer_returning or not _callable_is_live(commit_source) or not _callable_is_live(rollback_source) or not _callable_is_live(notify_source):
		return false
	var presenter: AutolysisHeldItemPresenter = _presenter
	var candidate: Node3D = _handset_candidate
	var scene: PackedScene = _handset_transfer_scene
	var pose: Dictionary = _handset_transfer_pose.duplicate()
	var revision: int = _holding_revision
	var index: int = _focused_index
	var focus_session: int = _handset_transfer_focus
	var committed: Variant = commit_source.call()
	if not is_instance_valid(self):
		return false
	# 可见性观察者可能已取消本次事务或建立新事务，先复核身份再读取或提交。
	if not committed is bool or not committed or not _handset_commit_identity_current(actor, source, token, false, presenter, revision, index, focus_session) or not is_handset_transfer_current(actor, source, token) or _handset_candidate != candidate or _handset_transfer_scene != scene:
		_rollback_current_handset_transfer(actor, source, token, rollback_source)
		return false
	# 来源提交不发通知；同一同步调用内完成双方占用与显示。
	_handset_source = source
	_handset_actor = actor
	_handset_session = token
	_handset_scene = scene
	_handset_position = pose["position"]
	_handset_rotation = pose["rotation_degrees"]
	_handset_scale = pose["scale"]
	_handset_initial_pose = {"position": _handset_position, "rotation_degrees": _handset_rotation}
	if not presenter.commit_handset_prepared(candidate, source, token):
		if is_instance_valid(self):
			_rollback_current_handset_transfer(actor, source, token, rollback_source)
			if is_instance_valid(presenter):
				presenter.clear_handset(source, token)
			if _handset_source == source and _handset_actor == actor and _handset_session == token:
				_reset_handset_state()
		return false
	if not is_instance_valid(self):
		return false
	if not _handset_commit_identity_current(actor, source, token, false, presenter, revision, index, focus_session) or _handset_source != source or _handset_actor != actor or _handset_session != token or not presenter.is_handset_display(source, candidate, token):
		_rollback_current_handset_transfer(actor, source, token, rollback_source)
		abort_handset_session(source, token, "取下显示提交期间必要对象失效。")
		return false
	# 模型入树通知可能释放电话必要限位；显示身份有效仍不足以发布持有。
	var source_valid: bool = _committed_handset_source_valid(actor, source, token)
	if not is_instance_valid(self):
		return false
	if not source_valid or not _handset_commit_identity_current(actor, source, token, false, presenter, revision, index, focus_session) or _handset_source != source or _handset_actor != actor or _handset_session != token or not presenter.is_handset_display(source, candidate, token):
		_rollback_current_handset_transfer(actor, source, token, rollback_source)
		abort_handset_session(source, token, "听筒模型入树后电话必要来源依赖失效。")
		return false
	_handset_candidate = null
	_store_handset_pose(source, _handset_position, _handset_rotation)
	_watch_handset_dependencies()
	_handset_session_committed = true
	_holding_revision += 1
	_clear_handset_transfer()
	_publish_handset_change(notify_source, actor, source)
	return true


func commit_handset_return(actor: Node3D, source: Node3D, token: int, commit_source: Callable, rollback_source: Callable, notify_source: Callable) -> bool:
	if not is_handset_transfer_current(actor, source, token) or not _handset_transfer_returning or not _callable_is_live(commit_source) or not _callable_is_live(rollback_source) or not _callable_is_live(notify_source):
		return false
	var presenter: AutolysisHeldItemPresenter = _presenter
	var session: int = _handset_session
	var display: Node3D = get_handset_display()
	var revision: int = _holding_revision
	var index: int = _focused_index
	var focus_session: int = _handset_transfer_focus
	var committed: Variant = commit_source.call()
	if not is_instance_valid(self):
		return false
	if not committed is bool or not committed or not _handset_commit_identity_current(actor, source, token, true, presenter, revision, index, focus_session) or _handset_session != session or not is_handset_transfer_current(actor, source, token) or get_handset_display() != display:
		_rollback_current_handset_transfer(actor, source, token, rollback_source)
		return false
	_disconnect_handset_dependencies()
	_reset_handset_state()
	_holding_revision += 1
	_clear_handset_transfer()
	presenter.clear_handset(source, session)
	if is_instance_valid(self):
		_publish_handset_change(notify_source, actor, source)
	return true


func cancel_handset_transfer(source: Node3D, token: int) -> bool:
	if token <= 0 or _handset_transfer_token != token or _handset_transfer_source != source:
		return false
	_clear_handset_transfer()
	_busy = _publication_depth > 0
	return true


func is_handset_display_session(source: Node3D, display: Node3D, serial: int) -> bool:
	return serial > 0 and _handset_session == serial and _handset_source == source and _node_is_live(source) and _node_is_live(_handset_actor) and _node_is_live(_presenter) and _presenter.is_handset_display(source, display, serial)


func apply_handset_pose(source: Node3D, display: Node3D, serial: int, position_value: Vector3, rotation_value: Vector3) -> bool:
	if _busy or not is_handset_display_session(source, display, serial) or not position_value.is_finite() or not rotation_value.is_finite():
		return false
	if not _presenter.apply_handset_pose(source, display, serial, position_value, rotation_value):
		return false
	_handset_position = position_value
	_handset_rotation = rotation_value
	_store_handset_pose(source, position_value, rotation_value)
	return true


func abort_handset_session(source: Variant, session: int, reason: String) -> bool:
	if _handset_cleaning:
		return false
	var held_match: bool = session > 0 and _handset_session == session and _handset_source == source
	var committed_match: bool = held_match and _handset_session_committed
	var pending_match: bool = session > 0 and _handset_transfer_source == source and (_handset_transfer_token == session or held_match)
	if not held_match and not pending_match:
		return false
	_handset_cleaning = true
	_busy = true
	var actor: Node3D = _handset_actor if held_match else _handset_transfer_actor
	var presenter: AutolysisHeldItemPresenter = _presenter
	last_handset_abort_reason = reason
	_disconnect_handset_dependencies()
	_reset_handset_state()
	_clear_handset_transfer()
	if is_instance_valid(presenter):
		presenter.clear_handset(source, session)
	if is_instance_valid(source) and source.has_method("abort_handset_holder"):
		source.call("abort_handset_holder", actor, session, reason)
	if not is_instance_valid(self):
		return true
	_handset_cleaning = false
	if committed_match:
		_holding_revision += 1
		_publish_handset_change(Callable())
	else:
		_busy = _publication_depth > 0
	return true


func _ordinary_hands_available() -> bool:
	return _handset_session == 0 and _handset_transfer_token == 0 and not _handset_cleaning


func _handset_actor_valid(actor: Variant, source: Variant) -> bool:
	if not _dependencies_valid() or not _node_is_live(actor) or not actor is AutolysisPlayer or not _node_is_live(source) or not source is Node3D:
		return false
	if actor.get_node_or_null("InventoryController") != self or not actor.is_focus_business_allowed() or not _node_is_live(actor.focus_controller):
		return false
	var target: AutolysisFocusTarget = actor.focus_controller.get_focus_target()
	return _node_is_live(target) and target.device_root == source and actor.focus_controller.is_focused_on(target)


func _start_handset_transfer(actor: Node3D, source: Node3D, returning: bool) -> void:
	_busy = true
	_handset_counter += 1
	_handset_transfer_token = _handset_counter
	_handset_transfer_source = source
	_handset_transfer_actor = actor
	_handset_transfer_returning = returning
	_handset_transfer_index = _focused_index
	_handset_transfer_revision = _holding_revision
	_handset_transfer_focus = (actor as AutolysisPlayer).focus_controller.session_id


func _clear_handset_transfer() -> void:
	var candidate: Node3D = _handset_candidate
	_handset_candidate = null
	_handset_transfer_source = null
	_handset_transfer_actor = null
	_handset_transfer_token = 0
	_handset_transfer_index = -1
	_handset_transfer_revision = 0
	_handset_transfer_focus = 0
	_handset_transfer_returning = false
	_handset_transfer_scene = null
	_handset_transfer_pose.clear()
	if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
		if candidate.is_inside_tree():
			candidate.queue_free()
		else:
			candidate.free()


func _reset_handset_state() -> void:
	_handset_source = null
	_handset_actor = null
	_handset_session = 0
	_handset_session_committed = false
	_handset_scene = null
	_handset_initial_pose.clear()


func _cached_handset_pose(source: Node3D, position_value: Vector3, rotation_value: Vector3) -> Dictionary:
	var cached: Dictionary = _handset_pose_cache.get(source.get_instance_id(), {})
	if not cached.is_empty() and cached["source"].get_ref() == source:
		return {"position": cached["position"], "rotation_degrees": cached["rotation_degrees"]}
	return {"position": position_value, "rotation_degrees": rotation_value}


func _store_handset_pose(source: Node3D, position_value: Vector3, rotation_value: Vector3) -> void:
	_handset_pose_cache[source.get_instance_id()] = {"source": weakref(source), "position": position_value, "rotation_degrees": rotation_value}


static func _callable_is_live(callback: Callable) -> bool:
	if not callback.is_valid():
		return false
	var receiver: Object = callback.get_object()
	return is_instance_valid(receiver) and (not receiver is Node or _node_is_live(receiver))


static func _call_handset_rollback(callback: Callable) -> void:
	if _callable_is_live(callback):
		callback.call()


func _rollback_current_handset_transfer(actor: Variant, source: Variant, token: int, callback: Callable) -> void:
	# 旧回调不能回滚已经取消或后来建立的来源会话。
	if _handset_transfer_token == token and _handset_transfer_actor == actor and _handset_transfer_source == source:
		_call_handset_rollback(callback)


func _handset_commit_identity_current(actor: Variant, source: Variant, token: int, returning: bool, presenter: Variant, revision: int, index: int, focus_session: int) -> bool:
	if token <= 0 or _handset_transfer_token != token or _handset_transfer_actor != actor or _handset_transfer_source != source or _handset_transfer_returning != returning or not _busy or _handset_cleaning:
		return false
	if _holding_revision != revision or _handset_transfer_revision != revision or _focused_index != index or _handset_transfer_index != index or _handset_transfer_focus != focus_session or _presenter != presenter or not _node_is_live(presenter):
		return false
	return _handset_actor_valid(actor, source) and (actor as AutolysisPlayer).focus_controller.session_id == focus_session


func _committed_handset_source_valid(actor: Node3D, source: Node3D, session: int) -> bool:
	return source is AutolysisTelephone and source.is_committed_handset_valid(actor, session)


func _publish_handset_change(notify_source: Callable, completed_actor: Variant = null, completed_source: Variant = null) -> void:
	_publication_depth += 1
	_publishing = true
	var revision: int = _holding_revision
	held_item_changed.emit()
	if not is_instance_valid(self):
		return
	# 观察者可释放当前来源或触发异常终止；旧完成通知不得继续发布。
	if revision == _holding_revision and _node_is_live(completed_actor) and _node_is_live(completed_source) and _callable_is_live(notify_source):
		notify_source.call()
	if is_instance_valid(self):
		_publication_depth -= 1
		_publishing = _publication_depth > 0
		_busy = _publication_depth > 0


func _watch_handset_dependencies() -> void:
	for dependency: Variant in [_handset_source, _handset_actor, _presenter]:
		var callback: Callable = _on_handset_dependency_exiting.bind(_handset_source, _handset_session)
		if _node_is_live(dependency) and not dependency.tree_exiting.is_connected(callback):
			dependency.tree_exiting.connect(callback)


func _disconnect_handset_dependencies() -> void:
	var callback: Callable = _on_handset_dependency_exiting.bind(_handset_source, _handset_session)
	for dependency: Variant in [_handset_source, _handset_actor, _presenter]:
		if is_instance_valid(dependency) and dependency.tree_exiting.is_connected(callback):
			dependency.tree_exiting.disconnect(callback)


func _on_handset_dependency_exiting(source: Variant, session: int) -> void:
	abort_handset_session(source, session, "听筒来源、玩家或必要呈现器离开场景树。")


func _process(_delta: float) -> void:
	if _handset_cleaning:
		return
	if _handset_transfer_token > 0 and (not _node_is_live(_handset_transfer_source) or not _node_is_live(_handset_transfer_actor) or not _node_is_live(_presenter)):
		var serial: int = _handset_session if _handset_session > 0 else _handset_transfer_token
		abort_handset_session(_handset_transfer_source, serial, "听筒预处理期间必要对象失效。")
		return
	if _handset_session <= 0:
		return
	if not _node_is_live(_handset_source) or not _node_is_live(_handset_actor) or not _node_is_live(_presenter):
		abort_handset_session(_handset_source, _handset_session, "持筒期间来源、玩家或必要呈现器失效。")
		return
	if _busy or _presenter.is_handset_display(_handset_source, _presenter.get_display(), _handset_session):
		return
	# 显示丢失先按本次配置和运行调节值重建，不解除持有。
	_busy = true
	var source: Node3D = _handset_source
	var session: int = _handset_session
	var replacement: Node3D = _presenter.prepare_handset(_handset_scene, _handset_position, _handset_rotation, _handset_scale)
	if replacement == null or not _presenter.commit_handset_prepared(replacement, source, session):
		if is_instance_valid(replacement):
			if replacement.is_inside_tree():
				replacement.queue_free()
			else:
				replacement.free()
		if is_instance_valid(self):
			abort_handset_session(source, session, "听筒显示丢失后无法按当前配置恢复。")
		return
	if is_instance_valid(self):
		_publish_handset_change(Callable())


func _exit_tree() -> void:
	if _handset_session > 0:
		abort_handset_session(_handset_source, _handset_session, "库存控制器离开场景树。")
	elif _handset_transfer_token > 0:
		abort_handset_session(_handset_transfer_source, _handset_transfer_token, "库存控制器在听筒预处理期间离开场景树。")


func get_slot_item(index: int) -> AutolysisItemDefinition:
	var instance: AutolysisItemInstance = get_slot_instance(index)
	return null if instance == null else instance.definition


func get_slot_instance(index: int) -> AutolysisItemInstance:
	if index < 0 or index >= SLOT_COUNT:
		return null
	return _slots[index]


func get_focused_index() -> int:
	return _focused_index


func get_focused_item() -> AutolysisItemDefinition:
	return get_slot_item(_focused_index)


func get_focused_instance() -> AutolysisItemInstance:
	return _slots[_focused_index]


func cycle_focus(direction: int) -> bool:
	if _busy or not _ordinary_hands_available() or not _dependencies_valid() or (direction != -1 and direction != 1):
		return false
	_busy = true
	var next_index: int = posmod(_focused_index + direction, SLOT_COUNT)
	var item: AutolysisItemInstance = _slots[next_index]
	var visual: Node3D = _prepare_visual(item)
	if item != null and visual == null:
		_busy = false
		return false
	_focused_index = next_index
	_commit_visual(visual)
	_publish_change()
	return true


func can_receive_item(item: AutolysisItemDefinition) -> bool:
	return (not _busy or _publishing) and _ordinary_hands_available() and _dependencies_valid() and get_focused_instance() == null and item != null and item.is_valid_definition()


func try_receive_item(item: AutolysisItemDefinition) -> bool:
	if _busy or not can_receive_item(item):
		return false
	return try_receive_instance(AutolysisItemInstance.create(item))


func can_receive_instance(instance: AutolysisItemInstance) -> bool:
	return is_instance_valid(instance) and instance.is_valid_instance() and not _slots.has(instance) and can_receive_item(instance.definition)


func try_receive_instance(instance: AutolysisItemInstance) -> bool:
	if _busy or not can_receive_instance(instance):
		return false
	_busy = true
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_busy = false
		return false
	_slots[_focused_index] = instance
	_commit_visual(visual)
	_publish_change()
	return true


func can_take_world_item(item: AutolysisRawMaterial) -> bool:
	if not _node_is_live(item) or item.device_stored or is_instance_valid(item.blend_slot) or not item.is_available_for_pickup():
		return false
	if not can_receive_instance(item.item_instance):
		return false
	if item.shelf != null:
		return _node_is_live(item.shelf) and item.shelf.owns_item(item)
	return item.slot_index == -1


func try_take_world_item(item: AutolysisRawMaterial) -> bool:
	if _busy or not can_take_world_item(item):
		return false
	_busy = true
	var instance: AutolysisItemInstance = item.item_instance
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_busy = false
		return false
	# 模型准备期间不提交任何占用；准备完成后再次核对来源。
	if not _node_is_live(item) or item.item_instance != instance or item.device_stored or is_instance_valid(item.blend_slot) or not item.is_available_for_pickup():
		visual.free()
		_busy = false
		return false
	if item.shelf != null:
		if not _node_is_live(item.shelf) or not item.shelf.release_item(item):
			visual.free()
			_busy = false
			return false
	_slots[_focused_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	_publish_change()
	return true


func can_place_on_shelf(shelf: AutolysisRawMaterialShelf) -> bool:
	if (_busy and not _publishing) or not _ordinary_hands_available() or not _dependencies_valid() or not _node_is_live(shelf):
		return false
	var item: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	return instance != null and instance.is_valid_instance() and item.is_raw_material and shelf.can_accept_item(item) and _get_world_scene(item) != null


func try_place_on_shelf(shelf: AutolysisRawMaterialShelf) -> bool:
	if _busy or not can_place_on_shelf(shelf):
		return false
	_busy = true
	var original_index: int = _focused_index
	var instance: AutolysisItemInstance = get_focused_instance()
	var slot: int = shelf.find_first_empty_slot()
	var candidate: AutolysisRawMaterial = _prepare_world_item(instance)
	if candidate == null:
		_busy = false
		return false
	if not _ordinary_hands_available() or not _node_is_live(shelf) or _focused_index != original_index or get_focused_instance() != instance:
		candidate.free()
		_busy = false
		return false
	if not shelf.try_attach_item(slot, candidate):
		if is_instance_valid(candidate):
			candidate.free()
		_busy = false
		return false
	_slots[original_index] = null
	_commit_visual(null)
	_publish_change()
	return true


func can_place_in_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if not _can_query_blend_slot(actor, slot):
		return false
	var definition: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	return slot.get_stored_item() == null and instance != null and instance.is_valid_instance() and definition.is_raw_material and _get_world_scene(definition) != null


func try_place_in_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if _busy or not can_place_in_blend_slot(actor, slot):
		return false
	var original_index: int = _focused_index
	var definition: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	var anchor: Node3D = slot.raw_material_anchor
	_busy = true
	if not slot.try_begin_transfer(actor):
		_busy = false
		return false
	var candidate: AutolysisRawMaterial = _prepare_world_item(instance)
	if candidate == null:
		_end_blend_transfer(slot)
		return false
	if not _blend_transaction_valid(actor, slot, anchor, original_index, instance) or not candidate.prepare_device_storage(slot):
		_rollback_blend_candidate(slot, candidate)
		return false
	if not slot.try_attach_prepared_item(candidate):
		_rollback_blend_candidate(slot, candidate)
		return false
	# 入树回调可能删除设备、改变会话或搬走原药，提交前重新核对全部来源。
	if not _blend_transaction_valid(actor, slot, anchor, original_index, instance) or not _node_is_live(candidate):
		_rollback_blend_candidate(slot, candidate)
		return false
	if candidate.item_instance != instance or candidate.item_definition != definition or not slot.owns_item(candidate) or candidate.get_parent() != anchor:
		_rollback_blend_candidate(slot, candidate)
		return false
	_slots[original_index] = null
	_commit_visual(null)
	_publish_change()
	_end_blend_transfer(slot)
	return true


func can_take_from_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if not _can_query_blend_slot(actor, slot) or get_focused_item() != null:
		return false
	var item: AutolysisRawMaterial = slot.get_stored_item()
	return _node_is_live(item) and slot.owns_item(item) and is_instance_valid(item.item_instance) and item.item_instance.is_valid_instance() and item.item_instance.definition == item.item_definition and item.item_definition.is_raw_material


func try_take_from_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if _busy or not can_take_from_blend_slot(actor, slot):
		return false
	var original_index: int = _focused_index
	var item: AutolysisRawMaterial = slot.get_stored_item()
	var definition: AutolysisItemDefinition = item.item_definition
	var instance: AutolysisItemInstance = item.item_instance
	var anchor: Node3D = slot.raw_material_anchor
	_busy = true
	if not slot.try_begin_transfer(actor):
		_busy = false
		return false
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_end_blend_transfer(slot)
		return false
	if not _blend_transaction_valid(actor, slot, anchor, original_index, null) or not _node_is_live(item):
		visual.free()
		_end_blend_transfer(slot)
		return false
	if item.item_instance != instance or item.item_definition != definition or not slot.owns_item(item) or not slot.release_item(item):
		visual.free()
		_end_blend_transfer(slot)
		return false
	_slots[original_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	_publish_change()
	_end_blend_transfer(slot)
	return true


func _can_query_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if (_busy and not _publishing) or not _ordinary_hands_available() or not _dependencies_valid() or not _node_is_live(actor) or not _node_is_live(slot):
		return false
	return actor.get_node_or_null("InventoryController") == self and slot.can_transfer(actor, _publishing)


func _blend_transaction_valid(actor: Variant, slot: Variant, anchor: Variant, original_index: int, original_item: AutolysisItemInstance) -> bool:
	if not _ordinary_hands_available() or not _dependencies_valid() or not _node_is_live(actor) or not _node_is_live(slot) or not _node_is_live(anchor):
		return false
	if not actor is Node3D or not slot is AutolysisBlendSlot or not anchor is Node3D:
		return false
	if actor.get_node_or_null("InventoryController") != self or _focused_index != original_index or get_focused_instance() != original_item:
		return false
	return slot.raw_material_anchor == anchor and slot.can_transfer(actor, true)


func _rollback_blend_candidate(slot: Variant, candidate: Variant) -> void:
	if is_instance_valid(slot) and slot is AutolysisBlendSlot:
		slot.rollback_prepared_item(candidate)
	if is_instance_valid(candidate) and candidate is AutolysisRawMaterial:
		candidate.free()
	_end_blend_transfer(slot)


func _end_blend_transfer(slot: Variant) -> void:
	if is_instance_valid(slot) and slot is AutolysisBlendSlot:
		slot.end_transfer()
	_busy = false


func can_take_liquid_tank(actor: Node3D, item: AutolysisLiquidTank) -> bool:
	if not _can_query_liquid_actor(actor) or not _node_is_live(item) or not item.is_available_for_pickup():
		return false
	if not _is_liquid_tank_definition(item.item_definition) or not can_receive_instance(item.item_instance):
		return false
	if item.cabinet_stored:
		return _node_is_live(item.cabinet) and item.cabinet.can_transfer(actor, _publishing) and item.cabinet.owns_item(item)
	return item.cabinet == null and item.slot_index == -1


func try_take_liquid_tank(actor: Node3D, item: AutolysisLiquidTank) -> bool:
	if _busy or not can_take_liquid_tank(actor, item):
		return false
	var original_index: int = _focused_index
	var instance: AutolysisItemInstance = item.item_instance
	var cabinet: AutolysisLiquidTankCabinet = item.cabinet
	var slot_index: int = item.slot_index
	var anchor: Node3D = cabinet.get_slot_node(slot_index) if item.cabinet_stored else null
	_busy = true
	if item.cabinet_stored and not cabinet.try_begin_transfer(actor):
		_busy = false
		return false
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_end_liquid_transfer(cabinet)
		return false
	# 准备显示不释放来源；准备完成后核对指定罐和原空格。
	if not _liquid_pickup_source_valid(actor, item, cabinet, slot_index, anchor, original_index, instance):
		visual.free()
		_end_liquid_transfer(cabinet)
		return false
	if cabinet != null and not cabinet.release_item(item):
		visual.free()
		_end_liquid_transfer(cabinet)
		return false
	_slots[original_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	_publish_change()
	_end_liquid_transfer(cabinet)
	return true


func can_place_in_liquid_tank_cabinet(actor: Node3D, cabinet: AutolysisLiquidTankCabinet) -> bool:
	if not _can_query_liquid_actor(actor) or not _node_is_live(cabinet) or not cabinet.can_transfer(actor, _publishing):
		return false
	var definition: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	return instance != null and instance.is_valid_instance() and _is_liquid_tank_definition(definition) and cabinet.can_accept_item(definition) and _get_liquid_tank_world_scene(definition) != null


func try_place_in_liquid_tank_cabinet(actor: Node3D, cabinet: AutolysisLiquidTankCabinet) -> bool:
	if _busy or not can_place_in_liquid_tank_cabinet(actor, cabinet):
		return false
	var original_index: int = _focused_index
	var definition: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	var slot_index: int = cabinet.find_first_empty_slot()
	var anchor: Node3D = cabinet.get_slot_node(slot_index)
	_busy = true
	if not cabinet.try_begin_transfer(actor):
		_busy = false
		return false
	var candidate: AutolysisLiquidTank = _prepare_liquid_tank_world_item(instance)
	if candidate == null:
		_end_liquid_transfer(cabinet)
		return false
	if not _liquid_transaction_valid(actor, cabinet, slot_index, anchor, original_index, instance) or not candidate.prepare_cabinet_storage(cabinet, slot_index):
		_rollback_liquid_candidate(cabinet, candidate)
		return false
	if not cabinet.try_attach_prepared_item(slot_index, candidate):
		_rollback_liquid_candidate(cabinet, candidate)
		return false
	# 入树回调可能释放柜子、移动候选或损坏来源，提交前再次核对。
	if not _liquid_transaction_valid(actor, cabinet, slot_index, anchor, original_index, instance) or not _node_is_live(candidate):
		_rollback_liquid_candidate(cabinet, candidate)
		return false
	if candidate.item_instance != instance or candidate.item_definition != definition or not candidate.is_available_for_pickup() or not cabinet.owns_item(candidate) or candidate.get_parent() != anchor:
		_rollback_liquid_candidate(cabinet, candidate)
		return false
	_slots[original_index] = null
	_commit_visual(null)
	_publish_change()
	_end_liquid_transfer(cabinet)
	return true


func can_place_in_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if not _can_query_blend_tank_place(actor, place):
		return false
	var instance: AutolysisItemInstance = get_focused_instance()
	return place.get_stored_item() == null and instance != null and instance.is_empty_liquid_tank() and _get_liquid_tank_world_scene(instance.definition) != null


func try_place_in_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if _busy or not can_place_in_blend_tank_place(actor, place):
		return false
	var original_index: int = _focused_index
	var instance: AutolysisItemInstance = get_focused_instance()
	var anchor: Node3D = place.liquid_tank_anchor
	_busy = true
	if not place.try_begin_transfer(actor):
		_busy = false
		return false
	var candidate: AutolysisLiquidTank = _prepare_liquid_tank_world_item(instance)
	if candidate == null:
		_end_blend_tank_transfer(place)
		return false
	if not _blend_tank_transaction_valid(actor, place, anchor, original_index, instance) or not candidate.prepare_blend_storage(place):
		_rollback_blend_tank_candidate(place, candidate)
		return false
	if not place.try_attach_prepared_item(candidate):
		_rollback_blend_tank_candidate(place, candidate)
		return false
	if not _blend_tank_transaction_valid(actor, place, anchor, original_index, instance) or not _node_is_live(candidate):
		_rollback_blend_tank_candidate(place, candidate)
		return false
	if candidate.item_instance != instance or not instance.is_empty_liquid_tank() or not place.owns_item(candidate) or candidate.get_parent() != anchor:
		_rollback_blend_tank_candidate(place, candidate)
		return false
	_slots[original_index] = null
	_commit_visual(null)
	_publish_change()
	_end_blend_tank_transfer(place)
	return true


func can_take_from_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if not _can_query_blend_tank_place(actor, place) or get_focused_instance() != null:
		return false
	var item: AutolysisLiquidTank = place.get_stored_item()
	return _node_is_live(item) and place.owns_item(item) and is_instance_valid(item.item_instance) and item.item_instance.is_valid_instance() and item.item_instance.is_liquid_tank() and item.item_instance.definition == item.item_definition


func try_take_from_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if _busy or not can_take_from_blend_tank_place(actor, place):
		return false
	var original_index: int = _focused_index
	var item: AutolysisLiquidTank = place.get_stored_item()
	var instance: AutolysisItemInstance = item.item_instance
	var anchor: Node3D = place.liquid_tank_anchor
	_busy = true
	if not place.try_begin_transfer(actor):
		_busy = false
		return false
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_end_blend_tank_transfer(place)
		return false
	if not _blend_tank_transaction_valid(actor, place, anchor, original_index, null) or not _node_is_live(item):
		visual.free()
		_end_blend_tank_transfer(place)
		return false
	if item.item_instance != instance or item.item_definition != instance.definition or not instance.is_valid_instance() or not place.owns_item(item) or not place.release_item(item):
		visual.free()
		_end_blend_tank_transfer(place)
		return false
	_slots[original_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	_publish_change()
	_end_blend_tank_transfer(place)
	return true


func can_place_in_blend_tank(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	return can_place_in_blend_tank_place(actor, place)


func try_place_in_blend_tank(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	return try_place_in_blend_tank_place(actor, place)


func can_take_from_blend_tank(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	return can_take_from_blend_tank_place(actor, place)


func try_take_from_blend_tank(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	return try_take_from_blend_tank_place(actor, place)


func _can_query_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if (_busy and not _publishing) or not _ordinary_hands_available() or not _dependencies_valid() or not _node_is_live(actor) or not _node_is_live(place):
		return false
	return actor.get_node_or_null("InventoryController") == self and place.can_transfer(actor, _publishing)


func _blend_tank_transaction_valid(actor: Variant, place: Variant, anchor: Variant, original_index: int, original_item: AutolysisItemInstance) -> bool:
	if not _ordinary_hands_available() or not _dependencies_valid() or not _node_is_live(actor) or not _node_is_live(place) or not _node_is_live(anchor):
		return false
	if not actor is Node3D or not place is AutolysisBlendTankPlace or not anchor is Node3D:
		return false
	if actor.get_node_or_null("InventoryController") != self or _focused_index != original_index or get_focused_instance() != original_item:
		return false
	if original_item != null and (not original_item.is_empty_liquid_tank() or _get_liquid_tank_world_scene(original_item.definition) == null):
		return false
	return place.liquid_tank_anchor == anchor and place.can_transfer(actor, true)


func _rollback_blend_tank_candidate(place: Variant, candidate: Variant) -> void:
	if is_instance_valid(place) and place is AutolysisBlendTankPlace:
		place.rollback_prepared_item(candidate)
	if is_instance_valid(candidate) and candidate is AutolysisLiquidTank:
		candidate.free()
	_end_blend_tank_transfer(place)


func _end_blend_tank_transfer(place: Variant) -> void:
	if is_instance_valid(place) and place is AutolysisBlendTankPlace:
		place.end_transfer()
	if is_instance_valid(self):
		_busy = false


func can_place_in_packing_tank_place(actor: Node3D, place: AutolysisPackingTankPlace) -> bool:
	return _can_place_in_packing_place(actor, place)


func try_place_in_packing_tank_place(actor: Node3D, place: AutolysisPackingTankPlace) -> bool:
	return _try_place_in_packing_place(actor, place)


func try_store_selected_in_packing_tank_place(actor: Node3D, place: AutolysisPackingTankPlace) -> bool:
	return try_place_in_packing_tank_place(actor, place)


func can_take_from_packing_tank_place(actor: Node3D, place: AutolysisPackingTankPlace) -> bool:
	return _can_take_from_packing_place(actor, place)


func try_take_from_packing_tank_place(actor: Node3D, place: AutolysisPackingTankPlace) -> bool:
	return _try_take_from_packing_place(actor, place)


func can_place_in_packing_capsule_place(actor: Node3D, place: AutolysisPackingCapsulePlace) -> bool:
	return _can_place_in_packing_place(actor, place)


func try_place_in_packing_capsule_place(actor: Node3D, place: AutolysisPackingCapsulePlace) -> bool:
	return _try_place_in_packing_place(actor, place)


func try_store_selected_in_packing_capsule_place(actor: Node3D, place: AutolysisPackingCapsulePlace) -> bool:
	return try_place_in_packing_capsule_place(actor, place)


func can_take_from_packing_capsule_place(actor: Node3D, place: AutolysisPackingCapsulePlace) -> bool:
	return _can_take_from_packing_place(actor, place)


func try_take_from_packing_capsule_place(actor: Node3D, place: AutolysisPackingCapsulePlace) -> bool:
	return _try_take_from_packing_place(actor, place)


func _can_query_packing_place(actor: Variant, place: Variant) -> bool:
	if (_busy and not _publishing) or not _ordinary_hands_available() or not _dependencies_valid() or not _node_is_live(actor) or not actor is AutolysisPlayer or not _node_is_live(place):
		return false
	if not place is AutolysisPackingTankPlace and not place is AutolysisPackingCapsulePlace:
		return false
	return actor.get_node_or_null("InventoryController") == self and place.can_transfer(actor, _publishing)


func _packing_instance_matches(place: Variant, instance: AutolysisItemInstance) -> bool:
	if not is_instance_valid(instance) or not instance.is_valid_instance():
		return false
	if place is AutolysisPackingTankPlace:
		return instance.is_liquid_tank() and _get_liquid_tank_world_scene(instance.definition) != null
	if place is AutolysisPackingCapsulePlace:
		return instance.is_pneumatic_capsule() and _get_pneumatic_capsule_world_scene(instance.definition) != null
	return false


func _packing_anchor(place: Variant) -> Node3D:
	if place is AutolysisPackingTankPlace:
		return place.liquid_tank_anchor
	if place is AutolysisPackingCapsulePlace:
		return place.capsule_anchor
	return null


func _can_place_in_packing_place(actor: Node3D, place: Variant) -> bool:
	return _can_query_packing_place(actor, place) and place.get_stored_item() == null and _packing_instance_matches(place, get_focused_instance())


func _try_place_in_packing_place(actor: Node3D, place: Variant) -> bool:
	if _busy or not _can_place_in_packing_place(actor, place):
		return false
	var original_index: int = _focused_index
	var instance: AutolysisItemInstance = get_focused_instance()
	var anchor: Node3D = _packing_anchor(place)
	var player: AutolysisPlayer = actor as AutolysisPlayer
	var session: int = player.focus_controller.session_id
	_busy = true
	if not place.try_begin_transfer(actor):
		_busy = false
		return false
	var candidate: Variant
	if place is AutolysisPackingTankPlace:
		candidate = _prepare_liquid_tank_world_item(instance)
	else:
		candidate = _prepare_pneumatic_capsule_world_item(instance)
	if candidate == null:
		_end_packing_transfer(place)
		return false
	if not _packing_transaction_valid(actor, place, anchor, original_index, instance, session) or place.get_stored_item() != null or not candidate.prepare_packing_storage(place):
		_rollback_packing_candidate(place, candidate)
		return false
	if not place.try_attach_prepared_item(candidate):
		_rollback_packing_candidate(place, candidate)
		return false
	# 入树初始化后复查同一实例、同一会话和已登记候选，失败时仍保留库存来源。
	if not _packing_transaction_valid(actor, place, anchor, original_index, instance, session) or not _node_is_live(candidate):
		_rollback_packing_candidate(place, candidate)
		return false
	if candidate.item_instance != instance or candidate.item_definition != instance.definition or not place.owns_item(candidate) or candidate.get_parent() != anchor:
		_rollback_packing_candidate(place, candidate)
		return false
	_slots[original_index] = null
	_commit_visual(null)
	_publish_change()
	_end_packing_transfer(place)
	return true


func _can_take_from_packing_place(actor: Node3D, place: Variant) -> bool:
	if not _can_query_packing_place(actor, place) or get_focused_instance() != null:
		return false
	var item: Variant = place.get_stored_item()
	return _node_is_live(item) and place.owns_item(item) and _packing_instance_matches(place, item.item_instance) and item.item_instance.definition == item.item_definition


func _try_take_from_packing_place(actor: Node3D, place: Variant) -> bool:
	if _busy or not _can_take_from_packing_place(actor, place):
		return false
	var original_index: int = _focused_index
	var item: Variant = place.get_stored_item()
	var instance: AutolysisItemInstance = item.item_instance
	var anchor: Node3D = _packing_anchor(place)
	var machine: AutolysisPackingMachine = place.machine
	var player: AutolysisPlayer = actor as AutolysisPlayer
	var session: int = player.focus_controller.session_id
	_busy = true
	if not place.try_begin_transfer(actor):
		_busy = false
		return false
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_end_packing_transfer(place)
		return false
	if not _packing_transaction_valid(actor, place, anchor, original_index, null, session) or not _node_is_live(item):
		visual.free()
		_end_packing_transfer(place)
		return false
	if item.item_instance != instance or item.item_definition != instance.definition or not _packing_instance_matches(place, instance) or not place.owns_item(item) or not place.release_item(item):
		visual.free()
		_end_packing_transfer(place)
		return false
	# 释放来源后无失败分支；先提交库存和显示，再以成功取走事件清除机器选择。
	_slots[original_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	if _node_is_live(machine):
		machine.on_packing_item_taken(place, instance)
	_publish_change()
	_end_packing_transfer(place)
	return true


func _packing_transaction_valid(actor: Variant, place: Variant, anchor: Variant, original_index: int, instance: AutolysisItemInstance, session: int) -> bool:
	if not _ordinary_hands_available() or not _dependencies_valid() or not _node_is_live(actor) or not actor is AutolysisPlayer or not _node_is_live(place) or not _node_is_live(anchor):
		return false
	if not place is AutolysisPackingTankPlace and not place is AutolysisPackingCapsulePlace:
		return false
	if actor.get_node_or_null("InventoryController") != self or _focused_index != original_index or get_focused_instance() != instance:
		return false
	if not _node_is_live(actor.focus_controller) or actor.focus_controller.session_id != session:
		return false
	if instance != null and not _packing_instance_matches(place, instance):
		return false
	return _packing_anchor(place) == anchor and place.can_transfer(actor, true)


func _rollback_packing_candidate(place: Variant, candidate: Variant) -> void:
	if is_instance_valid(place) and (place is AutolysisPackingTankPlace or place is AutolysisPackingCapsulePlace):
		place.rollback_prepared_item(candidate)
		# 槽位保留的已提交来源不得由候选回滚释放。
		if is_instance_valid(candidate) and place.owns_item(candidate):
			_end_packing_transfer(place)
			return
	if is_instance_valid(candidate) and (candidate is AutolysisLiquidTank or candidate is AutolysisPneumaticCapsule):
		candidate.free()
	_end_packing_transfer(place)


func _end_packing_transfer(place: Variant) -> void:
	if is_instance_valid(place) and (place is AutolysisPackingTankPlace or place is AutolysisPackingCapsulePlace):
		place.end_transfer()
	if is_instance_valid(self):
		_busy = false


func can_take_pneumatic_capsule(actor: Node3D, item: AutolysisPneumaticCapsule) -> bool:
	return _can_query_liquid_actor(actor) and _node_is_live(item) and item.is_available_for_pickup() and _is_pneumatic_capsule_definition(item.item_definition) and can_receive_instance(item.item_instance)


func try_take_pneumatic_capsule(actor: Node3D, item: AutolysisPneumaticCapsule) -> bool:
	if _busy or not can_take_pneumatic_capsule(actor, item):
		return false
	var original_index: int = _focused_index
	var instance: AutolysisItemInstance = item.item_instance
	_busy = true
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_busy = false
		return false
	if not _liquid_actor_valid(actor) or not _node_is_live(item) or _focused_index != original_index or get_focused_instance() != null:
		visual.free()
		_busy = false
		return false
	if item.item_instance != instance or item.item_definition != instance.definition or not instance.is_valid_instance() or not instance.is_pneumatic_capsule() or not item.is_available_for_pickup():
		visual.free()
		_busy = false
		return false
	_slots[original_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	_publish_change()
	return true


func can_dispose_in_waste_tank(actor: Node3D, tank: AutolysisWasteLiquidStorageTank) -> bool:
	if not _can_query_liquid_actor(actor) or not _node_is_live(tank) or not tank.can_dispose(actor, _publishing):
		return false
	var instance: AutolysisItemInstance = get_focused_instance()
	return _is_waste_disposable(instance)


func try_dispose_in_waste_tank(actor: Node3D, tank: AutolysisWasteLiquidStorageTank) -> bool:
	if _busy or not can_dispose_in_waste_tank(actor, tank):
		return false
	var original_index: int = _focused_index
	var instance: AutolysisItemInstance = get_focused_instance()
	var definition: AutolysisItemDefinition = instance.definition
	var contents: AutolysisLiquidContents = instance.liquid_contents
	var presenter: AutolysisHeldItemPresenter = _presenter
	var display: Node3D = presenter.get_display()
	_busy = true
	if not tank.try_begin_disposal(actor):
		_busy = false
		return false
	# 倒空前只检查既有显示依赖，不创建新罐或新手持模型。
	if contents != null and (not _node_is_live(display) or display.get_parent() != presenter or not AutolysisLiquidTankVisual.can_apply(display)):
		_end_waste_disposal(tank)
		return false
	# 许可回调与设备锁获取后，再次核对本次格、实例及内容引用。
	if not _waste_transaction_valid(actor, tank, original_index, instance, definition, contents, presenter, display):
		_end_waste_disposal(tank)
		return false
	if contents != null:
		if not instance.set_liquid_contents(null, false):
			_end_waste_disposal(tank)
			return false
		# 清空与材质提交均无回调；先更新已验证模型，保证提前订阅的观察者也读到空罐。
		AutolysisLiquidTankVisual.apply_instance(display, instance)
		# 内容提交后才通知；观察者可读最终状态，写入仍由两级锁拒绝。
		_publishing = true
		instance.emit_changed()
	else:
		_slots[original_index] = null
		_commit_visual(null)
	_publish_change()
	_end_waste_disposal(tank)
	return true


func _is_waste_disposable(instance: AutolysisItemInstance) -> bool:
	if not is_instance_valid(instance) or not instance.is_valid_instance():
		return false
	return instance.definition.is_raw_material or instance.is_pneumatic_capsule() or (instance.is_liquid_tank() and instance.liquid_contents != null and instance.liquid_contents.is_valid_contents())


func _waste_transaction_valid(actor: Variant, tank: Variant, original_index: int, instance: AutolysisItemInstance, definition: AutolysisItemDefinition, contents: AutolysisLiquidContents, presenter: AutolysisHeldItemPresenter, display: Node3D) -> bool:
	if not _liquid_actor_valid(actor) or not _node_is_live(tank) or not tank is AutolysisWasteLiquidStorageTank:
		return false
	if not tank.can_dispose(actor, true) or _focused_index != original_index or get_focused_instance() != instance:
		return false
	if not _is_waste_disposable(instance) or instance.definition != definition or instance.liquid_contents != contents:
		return false
	if _presenter != presenter or not _node_is_live(presenter) or presenter.get_display() != display:
		return false
	return contents == null or (_node_is_live(display) and display.get_parent() == presenter and AutolysisLiquidTankVisual.can_apply(display))


func _end_waste_disposal(tank: Variant) -> void:
	if is_instance_valid(tank) and tank is AutolysisWasteLiquidStorageTank:
		tank.end_disposal()
	if is_instance_valid(self):
		_publishing = false
		_busy = false


func _can_query_liquid_actor(actor: Node3D) -> bool:
	return (not _busy or _publishing) and _liquid_actor_valid(actor)


func _liquid_actor_valid(actor: Variant) -> bool:
	if not _ordinary_hands_available() or not _dependencies_valid() or not _node_is_live(actor) or not actor is Node3D or get_tree().paused:
		return false
	if actor.get_node_or_null("InventoryController") != self or not _input_allowed.is_valid():
		return false
	if actor is AutolysisPlayer and not actor.is_interaction_input_allowed():
		return false
	var receiver: Object = _input_allowed.get_object()
	if not is_instance_valid(receiver) or (receiver is Node and not _node_is_live(receiver)):
		return false
	var allowed: Variant = _input_allowed.call()
	return allowed is bool and allowed and is_instance_valid(self) and _dependencies_valid() and _node_is_live(actor) and actor.get_node_or_null("InventoryController") == self


func _liquid_transaction_valid(actor: Variant, cabinet: Variant, slot_index: int, anchor: Variant, original_index: int, original_item: AutolysisItemInstance) -> bool:
	if not _liquid_actor_valid(actor) or not _node_is_live(cabinet) or not _node_is_live(anchor):
		return false
	if not cabinet is AutolysisLiquidTankCabinet or not anchor is Node3D:
		return false
	if _focused_index != original_index or get_focused_instance() != original_item:
		return false
	if original_item != null and (not original_item.is_valid_instance() or _get_liquid_tank_world_scene(original_item.definition) == null):
		return false
	return cabinet.get_slot_node(slot_index) == anchor and cabinet.can_transfer(actor, true)


func _liquid_pickup_source_valid(actor: Variant, item: Variant, cabinet: Variant, slot_index: int, anchor: Variant, original_index: int, instance: AutolysisItemInstance) -> bool:
	if not _liquid_actor_valid(actor) or not _node_is_live(item) or not item is AutolysisLiquidTank:
		return false
	if _focused_index != original_index or get_focused_instance() != null or item.item_instance != instance or item.item_definition != instance.definition:
		return false
	if not instance.is_valid_instance() or not item.is_available_for_pickup() or not _is_liquid_tank_definition(instance.definition):
		return false
	if cabinet == null:
		return not item.cabinet_stored and item.cabinet == null and item.slot_index == -1 and slot_index == -1
	if not _liquid_transaction_valid(actor, cabinet, slot_index, anchor, original_index, null):
		return false
	return item.cabinet_stored and item.cabinet == cabinet and item.slot_index == slot_index and cabinet.owns_item(item) and item.get_parent() == anchor


func _rollback_liquid_candidate(cabinet: Variant, candidate: Variant) -> void:
	if is_instance_valid(cabinet) and cabinet is AutolysisLiquidTankCabinet:
		cabinet.rollback_prepared_item(candidate)
	if is_instance_valid(candidate) and candidate is AutolysisLiquidTank:
		candidate.free()
	_end_liquid_transfer(cabinet)


func _end_liquid_transfer(cabinet: Variant) -> void:
	if is_instance_valid(cabinet) and cabinet is AutolysisLiquidTankCabinet:
		cabinet.end_transfer()
	if is_instance_valid(self):
		_busy = false


func _is_liquid_tank_definition(definition: AutolysisItemDefinition) -> bool:
	return is_instance_valid(definition) and definition.item_id == LIQUID_TANK_ID and not definition.is_raw_material and definition.is_valid_definition()


func _prepare_liquid_tank_world_item(instance: AutolysisItemInstance) -> AutolysisLiquidTank:
	if not is_instance_valid(instance) or not instance.is_valid_instance():
		return null
	var definition: AutolysisItemDefinition = instance.definition
	var scene: PackedScene = _get_liquid_tank_world_scene(definition)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	if not node is AutolysisLiquidTank:
		node.free()
		return null
	var item: AutolysisLiquidTank = node as AutolysisLiquidTank
	if not _is_liquid_tank_definition(item.item_definition) or item.item_definition.item_id != definition.item_id or item.fixed_installation or item.cabinet_stored or item.cabinet != null or item.slot_index != -1 or item.blend_stored or item.blend_place != null or item.packing_stored or item.packing_place != null:
		item.free()
		return null
	if not item.bind_item_instance(instance):
		item.free()
		return null
	return item


func _get_liquid_tank_world_scene(definition: AutolysisItemDefinition) -> PackedScene:
	if not _is_liquid_tank_definition(definition) or definition.world_scene_path.is_empty() or not ResourceLoader.exists(definition.world_scene_path, "PackedScene"):
		return null
	var resource: Resource = load(definition.world_scene_path)
	if not resource is PackedScene or not resource.can_instantiate():
		return null
	var scene: PackedScene = resource as PackedScene
	var state: SceneState = scene.get_state()
	var script: Variant = _root_property(state, &"script")
	var item: Variant = _root_property(state, &"item_definition")
	var fixed_installation: Variant = _root_property(state, &"fixed_installation")
	# 许可查询仅读取场景描述，不实例化节点或执行初始化。
	if not script is Script or script.get_global_name() != &"AutolysisLiquidTank":
		return null
	if not item is AutolysisItemDefinition or not _is_liquid_tank_definition(item) or item.item_id != definition.item_id:
		return null
	if fixed_installation != null and (not fixed_installation is bool or fixed_installation):
		return null
	return scene


func _is_pneumatic_capsule_definition(definition: AutolysisItemDefinition) -> bool:
	return is_instance_valid(definition) and definition.item_id == PNEUMATIC_CAPSULE_ID and not definition.is_raw_material and definition.is_valid_definition()


func _prepare_pneumatic_capsule_world_item(instance: AutolysisItemInstance) -> AutolysisPneumaticCapsule:
	if not is_instance_valid(instance) or not instance.is_valid_instance() or not instance.is_pneumatic_capsule():
		return null
	var scene: PackedScene = _get_pneumatic_capsule_world_scene(instance.definition)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	if not node is AutolysisPneumaticCapsule:
		node.free()
		return null
	var item: AutolysisPneumaticCapsule = node as AutolysisPneumaticCapsule
	if not _is_pneumatic_capsule_definition(item.item_definition) or item.item_definition.item_id != instance.definition.item_id or item.packing_stored or item.packing_place != null:
		item.free()
		return null
	if not item.bind_item_instance(instance):
		item.free()
		return null
	return item


func _get_pneumatic_capsule_world_scene(definition: AutolysisItemDefinition) -> PackedScene:
	if not _is_pneumatic_capsule_definition(definition) or definition.world_scene_path.is_empty() or not ResourceLoader.exists(definition.world_scene_path, "PackedScene"):
		return null
	var resource: Resource = load(definition.world_scene_path)
	if not resource is PackedScene or not resource.can_instantiate():
		return null
	var scene: PackedScene = resource as PackedScene
	var state: SceneState = scene.get_state()
	var script: Variant = _root_property(state, &"script")
	var item: Variant = _root_property(state, &"item_definition")
	if not script is Script or script.get_global_name() != &"AutolysisPneumaticCapsule":
		return null
	if not item is AutolysisItemDefinition or not _is_pneumatic_capsule_definition(item) or item.item_id != definition.item_id:
		return null
	return scene


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.canceled or event.is_echo():
		return
	var direction: int = 0
	if event.is_action_pressed(NEXT_ACTION):
		direction = 1
	elif event.is_action_pressed(PREVIOUS_ACTION):
		direction = -1
	if direction == 0 or not _input_allowed.is_valid():
		return
	if not _ordinary_hands_available():
		get_viewport().set_input_as_handled()
		return
	var receiver: Object = _input_allowed.get_object()
	if receiver is Node and not _node_is_live(receiver):
		return
	var allowed: Variant = _input_allowed.call()
	if allowed is bool and allowed and cycle_focus(direction):
		get_viewport().set_input_as_handled()


func _prepare_visual(item: AutolysisItemInstance) -> Node3D:
	return null if item == null else _presenter.prepare_instance(item)


func _commit_visual(visual: Node3D) -> void:
	_presenter.commit_prepared(visual)
	_presenter.watch_instance(get_focused_instance())


func _prepare_world_item(instance: AutolysisItemInstance) -> AutolysisRawMaterial:
	if not is_instance_valid(instance) or not instance.is_valid_instance():
		return null
	var definition: AutolysisItemDefinition = instance.definition
	var scene: PackedScene = _get_world_scene(definition)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	if not node is AutolysisRawMaterial:
		node.free()
		return null
	var item: AutolysisRawMaterial = node as AutolysisRawMaterial
	if item.item_definition == null or item.item_definition.item_id != definition.item_id:
		item.free()
		return null
	if not item.bind_item_instance(instance):
		item.free()
		return null
	return item


func _get_world_scene(definition: AutolysisItemDefinition) -> PackedScene:
	if definition.world_scene_path.is_empty() or not ResourceLoader.exists(definition.world_scene_path, "PackedScene"):
		return null
	var resource: Resource = load(definition.world_scene_path)
	if not resource is PackedScene or not resource.can_instantiate():
		return null
	var scene: PackedScene = resource as PackedScene
	var state: SceneState = scene.get_state()
	var script: Variant = _root_property(state, &"script")
	var item: Variant = _root_property(state, &"item_definition")
	# 查询只读场景描述，不执行世界节点初始化。
	if not script is Script or script.get_global_name() != &"AutolysisRawMaterial":
		return null
	if not item is AutolysisItemDefinition or item.item_id != definition.item_id:
		return null
	return scene


func _root_property(state: SceneState, property: StringName) -> Variant:
	if state == null or state.get_node_count() == 0:
		return null
	for index: int in state.get_node_property_count(0):
		if state.get_node_property_name(0, index) == property:
			return state.get_node_property_value(0, index)
	var nested: PackedScene = state.get_node_instance(0)
	if nested != null:
		return _root_property(nested.get_state(), property)
	return _root_property(state.get_base_scene_state(), property)


func _dependencies_valid() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and _node_is_live(_presenter)


static func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()


func _publish_change() -> void:
	# 保持重入保护直到观察者完成读取，避免一个请求嵌套提交第二次转移。
	# 提交已经完成，因此通知中的只读许可查询应反映最终状态。
	_publication_depth += 1
	_publishing = true
	_holding_revision += 1
	inventory_changed.emit()
	if is_instance_valid(self):
		held_item_changed.emit()
	if is_instance_valid(self):
		_publication_depth -= 1
		_publishing = _publication_depth > 0
		_busy = _publication_depth > 0
