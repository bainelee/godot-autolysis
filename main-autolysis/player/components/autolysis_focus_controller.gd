class_name AutolysisFocusController
extends Node
## 会话拥有相机写入权；设备只提供只读目标姿态。

signal state_changed()

enum FocusState { INACTIVE, ENTERING, FOCUSED, EXITING }

const TRANSITION_SECONDS: float = 0.2
const NUMERIC_PROPERTIES: Array[StringName] = [&"fov", &"size", &"near", &"far", &"h_offset", &"v_offset", &"frustum_offset"]

var state: FocusState = FocusState.INACTIVE
var session_id: int = 0
var _actor: AutolysisPlayer
var _camera: Camera3D
var _presenter: AutolysisHeldItemPresenter
var _entry_allowed: Callable
var _target: AutolysisFocusTarget
var _tween: Tween
var _saved_world: Transform3D
var _saved_local: Transform3D
var _saved_projection: Dictionary
var _from_transform: Transform3D
var _to_transform: Transform3D
var _from_projection: Dictionary
var _to_projection: Dictionary
var _menu_paused: bool = false
var _watched_nodes: Array[Node] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(actor: AutolysisPlayer, camera: Camera3D, presenter: AutolysisHeldItemPresenter, entry_allowed: Callable) -> void:
	_actor = actor
	_camera = camera
	_presenter = presenter
	_entry_allowed = entry_allowed


func has_control() -> bool:
	return state != FocusState.INACTIVE


func get_focus_target() -> AutolysisFocusTarget:
	return _target if _live(_target) else null


func is_focused_on(target: AutolysisFocusTarget) -> bool:
	return state == FocusState.FOCUSED and _target == target and _live(target) and target.is_valid_target()


func can_enter(target: AutolysisFocusTarget) -> bool:
	if has_control() or not _live(_actor) or not _live(_camera) or not _live(_presenter):
		return false
	if not _actor.can_begin_focus_control():
		return false
	if not _live(target) or not target.is_valid_target() or target.reference_camera == _camera:
		return false
	if not _entry_allowed.is_valid():
		return false
	return _entry_allowed.call() == true


func try_enter(target: AutolysisFocusTarget) -> bool:
	if not can_enter(target):
		return false
	_saved_world = _camera.global_transform
	_saved_local = _camera.transform
	_saved_projection = _projection_of(_camera)
	if not _presenter.begin_camera_follow(_camera):
		return false
	_target = target
	session_id += 1
	state = FocusState.ENTERING
	_actor.begin_focus_control()
	for node: Node in [target, target.device_root, target.reference_camera, _camera]:
		if not _watched_nodes.has(node):
			_watched_nodes.append(node)
			node.tree_exiting.connect(_on_dependency_exiting)
	_actor.update_mouse_mode()
	_start_transition(target.reference_camera.global_transform, _projection_of(target.reference_camera))
	state_changed.emit()
	return true


func request_exit() -> bool:
	if state != FocusState.ENTERING and state != FocusState.FOCUSED:
		return false
	if not _live(_camera):
		abort_session()
		return false
	session_id += 1
	state = FocusState.EXITING
	_start_transition(_saved_world, _saved_projection)
	state_changed.emit()
	return true


func sync_pause_state() -> void:
	if not has_control() or not _live(_actor):
		return
	var pause_for_menu: bool = _actor.is_movement_paused or _actor.is_showing_ui
	if pause_for_menu == _menu_paused:
		return
	_menu_paused = pause_for_menu
	if _tween != null and _tween.is_valid():
		if _menu_paused:
			_tween.pause()
		else:
			_tween.play()


func _process(_delta: float) -> void:
	if not has_control():
		return
	if not _live(_actor) or not _live(_camera) or not _live(_presenter) or not _live(_target) or not _target.is_valid_target():
		abort_session()
		return
	sync_pause_state()


func _start_transition(destination: Transform3D, projection_values: Dictionary) -> void:
	_kill_tween()
	_from_transform = _camera.global_transform
	_to_transform = destination
	_from_projection = _projection_of(_camera)
	_to_projection = projection_values
	_camera.projection = projection_values[&"projection"]
	_camera.keep_aspect = projection_values[&"keep_aspect"]
	var serial: int = session_id
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_method(_apply_progress.bind(serial), 0.0, 1.0, TRANSITION_SECONDS)
	_tween.tween_callback(_finish_transition.bind(serial))
	_menu_paused = false
	sync_pause_state()


func _apply_progress(progress: float, serial: int) -> void:
	if serial != session_id or not has_control() or not _live(_camera):
		return
	var rotation_from: Quaternion = _from_transform.basis.get_rotation_quaternion()
	var rotation_to: Quaternion = _to_transform.basis.get_rotation_quaternion()
	var basis: Basis = Basis(rotation_from.slerp(rotation_to, progress))
	basis = basis.scaled(_from_transform.basis.get_scale().lerp(_to_transform.basis.get_scale(), progress))
	_camera.global_transform = Transform3D(basis, _from_transform.origin.lerp(_to_transform.origin, progress))
	for property: StringName in NUMERIC_PROPERTIES:
		_camera.set(property, lerp(_from_projection[property], _to_projection[property], progress))
	if progress >= 1.0:
		_camera.global_transform = _to_transform
		_restore_projection(_to_projection)
	if _live(_presenter):
		_presenter.sync_camera_follow()


func _finish_transition(serial: int) -> void:
	if serial != session_id or not has_control():
		return
	if state == FocusState.EXITING:
		abort_session()
	else:
		state = FocusState.FOCUSED
		state_changed.emit()


## 先作废会话再恢复；可重复调用，释放中的玩家不再触碰子节点。
func abort_session(restore_player: bool = true) -> void:
	if not has_control():
		return
	session_id += 1
	_kill_tween()
	for node: Node in _watched_nodes:
		if is_instance_valid(node) and node.tree_exiting.is_connected(_on_dependency_exiting):
			node.tree_exiting.disconnect(_on_dependency_exiting)
	_watched_nodes.clear()
	_target = null
	if restore_player and _live(_actor):
		if _live(_camera):
			_camera.transform = _saved_local
			_restore_projection(_saved_projection)
		if _live(_presenter):
			_presenter.end_camera_follow()
		_actor.end_focus_control()
	state = FocusState.INACTIVE
	_menu_paused = false
	if restore_player and _live(_actor):
		_actor.update_mouse_mode()
	state_changed.emit()


func _on_dependency_exiting() -> void:
	abort_session()


func _exit_tree() -> void:
	abort_session(false)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _projection_of(source: Camera3D) -> Dictionary:
	var result: Dictionary = {&"projection": source.projection, &"keep_aspect": source.keep_aspect}
	for property: StringName in NUMERIC_PROPERTIES:
		result[property] = source.get(property)
	return result


func _restore_projection(values: Dictionary) -> void:
	for property: StringName in values:
		_camera.set(property, values[property])


func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
