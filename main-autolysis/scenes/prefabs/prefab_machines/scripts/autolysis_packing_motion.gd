class_name AutolysisPackingMotion
extends AnimatableBody3D
## 控制件由物理处理推进独立播放器；目标自然完成后发布稳定结果。

signal motion_completed(opened: bool)
signal motion_cancelled(reason: String)

enum MotionState { CLOSED, OPENING, OPEN, CLOSING }

@export var toggle_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D
@export var animation_name: StringName

var machine: AutolysisPackingMachine
var focus_target: AutolysisFocusTarget
var state: MotionState = MotionState.CLOSED
var _runtime_player: AnimationPlayer
var _configured: bool = false
var _completion_pending: bool = false
var _restoration_pending: bool = false
var _expected_direction: int = 0
var _motion_fault: String = ""
var _motion_serial: int = 0
var _pending_serial: int = 0
var _pending_frame: int = 0
var _stable_open: bool = false
var _suspended: bool = false
var _action_animation: Animation
var _pending_animation: Animation
var _completed_transform: Transform3D
var _applying_animation: bool = false
var _deferred_action: int = 0
var _deferred_open: bool = false
var _deferred_player: AnimationPlayer


func _ready() -> void:
	if is_instance_valid(toggle_interaction):
		toggle_interaction.is_enabled = false


func configure(owner_machine: AutolysisPackingMachine, target: AutolysisFocusTarget, runtime_player: AnimationPlayer) -> bool:
	if _configured:
		return false
	machine = owner_machine
	focus_target = target
	if not _get_control_error().is_empty():
		return false
	toggle_interaction.set_availability_check(can_toggle)
	toggle_interaction.set_execution_handler(_on_toggle_requested)
	_configured = true
	return rebind_animation_player(runtime_player)


func _get_control_error() -> String:
	if not _node_is_live(self) or not _node_is_live(machine) or not machine.is_ancestor_of(self):
		return "控制件必须归属于有效封装器"
	if not _node_is_live(focus_target) or not machine.is_ancestor_of(focus_target):
		return "控制件与聚焦描述必须归属于同一封装器"
	if not sync_to_physics:
		return "活动控制件必须保留物理同步"
	if not _node_is_live(collision_shape) or collision_shape.get_parent() != self or collision_shape.shape == null or collision_shape.disabled:
		return "控制件必须具有有效直属碰撞"
	if not _node_is_live(toggle_interaction) or toggle_interaction.get_parent() != self or toggle_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "控制件必须具有直属直接交互组件"
	var count: int = 0
	for child: Node in get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	if count != 1:
		return "控制件必须恰好配置一个交互组件"
	if _configured and not toggle_interaction.has_execution_handler(_on_toggle_requested):
		return "控制件缺少自身业务执行绑定"
	return ""


func _get_dependency_error() -> String:
	var control_error: String = _get_control_error()
	if not control_error.is_empty():
		return control_error
	if not _node_is_live(_runtime_player) or not machine.is_ancestor_of(_runtime_player) or not _runtime_player.has_animation(animation_name):
		return "独立运行播放器或指定动画无效"
	var animation_root: Node = _runtime_player.get_node_or_null(_runtime_player.root_node)
	if not _node_is_live(animation_root) or (animation_root != machine and not machine.is_ancestor_of(animation_root)):
		return "独立运行播放器根引用不属于本机"
	if not _runtime_player.active or _runtime_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL or _runtime_player.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return "动画必须由本控制件可暂停物理处理推进"
	if not is_finite(_runtime_player.speed_scale) or _runtime_player.speed_scale <= 0.0:
		return "动画速度倍率必须为有限正数"
	if not _runtime_player.autoplay.is_empty() or not _runtime_player.animation_get_next(animation_name).is_empty() or not _runtime_player.get_queue().is_empty():
		return "独立控制件动画不得自动播放或排队"
	var animation: Animation = _runtime_player.get_animation(animation_name)
	if animation.loop_mode != Animation.LOOP_NONE or not is_finite(animation.length) or animation.length <= 0.0:
		return "目标自然完成要求有限正时长的非循环动画"
	return ""


func get_configuration_error() -> String:
	return _motion_fault if not _motion_fault.is_empty() else _get_dependency_error()


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func is_open() -> bool:
	return is_configured() and state == MotionState.OPEN and not is_animating()


func is_closed() -> bool:
	return is_configured() and state == MotionState.CLOSED and not is_animating()


func is_animating() -> bool:
	return state == MotionState.OPENING or state == MotionState.CLOSING or _completion_pending or _restoration_pending


func can_toggle(_actor: Node3D) -> bool:
	return false


func _on_toggle_requested(_actor: Node3D) -> void:
	pass


func rebind_animation_player(runtime_player: AnimationPlayer) -> bool:
	var had_active_state: bool = is_animating() or _stable_open
	if _applying_animation:
		_invalidate_motion()
		if had_active_state:
			motion_cancelled.emit("动作播放器重新绑定")
		_deferred_action = 2
		_deferred_player = runtime_player
		return true
	_disconnect_player()
	_invalidate_motion()
	_runtime_player = runtime_player
	_motion_fault = _get_dependency_error()
	if not _motion_fault.is_empty():
		if had_active_state:
			motion_cancelled.emit("动作播放器重新绑定")
		return false
	_runtime_player.animation_finished.connect(_on_animation_finished)
	_motion_fault = ""
	_restore_stable_state(false)
	if had_active_state:
		motion_cancelled.emit("动作播放器重新绑定")
	return true


func restore_closed() -> bool:
	_invalidate_motion()
	if _applying_animation:
		_deferred_action = 1
		_deferred_open = false
		return true
	var error: String = _get_dependency_error()
	if not error.is_empty():
		_motion_fault = error
		return false
	_motion_fault = ""
	_restore_stable_state(false)
	return true


func pause_motion() -> bool:
	if not is_configured() or not is_animating() or _completion_pending or _restoration_pending or _suspended:
		return false
	_suspended = true
	# 手动播放器只由本控制件推进；暂停不重启播放，避免续播重复当前事件。
	return true


func resume_motion() -> bool:
	if not is_configured() or not _suspended:
		return false
	_suspended = false
	return true


func cancel_motion(reason: String = "显式取消动作") -> void:
	var was_moving: bool = is_animating()
	var previous_open: bool = _stable_open
	_invalidate_motion()
	if _applying_animation:
		_deferred_action = 1
		_deferred_open = previous_open
		if was_moving:
			motion_cancelled.emit(reason)
		return
	var error: String = _get_dependency_error()
	if error.is_empty():
		_motion_fault = ""
		_restore_stable_state(previous_open)
	else:
		_motion_fault = error
	if was_moving:
		motion_cancelled.emit(reason)


func _start_motion(opening: bool) -> void:
	if not is_configured():
		return
	if _applying_animation:
		_deferred_action = 3
		_deferred_open = opening
		return
	var was_moving: bool = is_animating()
	var animation_time: float = _runtime_player.current_animation_position
	if not was_moving:
		animation_time = _runtime_player.get_animation(animation_name).length if _stable_open else 0.0
	_invalidate_motion()
	_expected_direction = 1 if opening else -1
	state = MotionState.OPENING if opening else MotionState.CLOSING
	_action_animation = _runtime_player.get_animation(animation_name)
	# 类型清除可以从当前进度反向；不会定位至旧的打开端点。
	_runtime_player.play(animation_name, 0.0, float(_expected_direction), not opening)
	_apply_seek(animation_time)


func _physics_process(delta: float) -> void:
	if not _configured or not _motion_fault.is_empty():
		return
	var error: String = _get_dependency_error()
	if not error.is_empty():
		_interrupt_motion(error)
		return
	if _completion_pending or _restoration_pending:
		if _runtime_player.is_playing() or _runtime_player.assigned_animation != animation_name or _runtime_player.get_animation(animation_name) != _pending_animation:
			_interrupt_motion("完成同步期间播放归属或本次资源被外部替换")
			return
		if _suspended:
			return
		if _pending_serial == _motion_serial and Engine.get_physics_frames() > _pending_frame:
			_finish_pending()
		return
	if not is_animating():
		return
	if _runtime_player.current_animation != animation_name or _runtime_player.get_animation(animation_name) != _action_animation or not _runtime_player.is_playing() or signf(_runtime_player.get_playing_speed()) != float(_expected_direction):
		_interrupt_motion("本次动作被外部停止、替换播放方向或替换资源")
		return
	if _suspended:
		return
	# 原生同步会在每次局部属性写入回退变换；暂时合并属性后只提交完整变换一次。
	var advancing_serial: int = _motion_serial
	set_notify_local_transform(false)
	_applying_animation = true
	_runtime_player.advance(delta)
	# 立即方法轨道可以释放控制件、播放器或取消本次动作。
	if not _node_is_live(self):
		return
	_applying_animation = false
	if _apply_deferred_action():
		return
	if advancing_serial != _motion_serial:
		set_notify_local_transform(true)
		return
	var applied_error: String = _get_dependency_error()
	if not applied_error.is_empty():
		set_notify_local_transform(true)
		_interrupt_motion(applied_error)
		return
	var animated_transform: Transform3D = transform
	set_notify_local_transform(true)
	transform = animated_transform


func _apply_seek(animation_time: float) -> void:
	var seeking_serial: int = _motion_serial
	set_notify_local_transform(false)
	_applying_animation = true
	_runtime_player.seek(animation_time, true, true)
	if not _node_is_live(self):
		return
	_applying_animation = false
	if _apply_deferred_action():
		return
	if seeking_serial != _motion_serial:
		set_notify_local_transform(true)
		return
	var applied_error: String = _get_dependency_error()
	if not applied_error.is_empty():
		set_notify_local_transform(true)
		_interrupt_motion(applied_error)
		return
	var animated_transform: Transform3D = transform
	set_notify_local_transform(true)
	transform = animated_transform


func _restore_stable_state(opened: bool) -> void:
	_stable_open = opened
	state = MotionState.OPEN if opened else MotionState.CLOSED
	_runtime_player.stop(true)
	_apply_restore_seek(_runtime_player.get_animation(animation_name).length if opened else 0.0)
	_restoration_pending = true
	_pending_animation = _runtime_player.get_animation(animation_name)
	_pending_serial = _motion_serial
	_pending_frame = Engine.get_physics_frames()


func _apply_restore_seek(animation_time: float) -> void:
	# 未推进播放留下的启动事件由临时属性副本消费；原动画事件启用位保持不变。
	var pose_animation: Animation = _runtime_player.get_animation(animation_name).duplicate() as Animation
	for track: int in pose_animation.get_track_count():
		if pose_animation.track_get_type(track) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION]:
			pose_animation.track_set_enabled(track, false)
	var pose_library: AnimationLibrary = AnimationLibrary.new()
	pose_library.add_animation(&"pose", pose_animation)
	var pose_library_name: StringName = &"_packing_restore"
	var suffix: int = 0
	while _runtime_player.has_animation_library(pose_library_name):
		suffix += 1
		pose_library_name = StringName("_packing_restore_%d" % suffix)
	_runtime_player.add_animation_library(pose_library_name, pose_library)
	set_notify_local_transform(false)
	_runtime_player.assigned_animation = StringName(String(pose_library_name) + "/pose")
	_runtime_player.seek(animation_time, true, true)
	_runtime_player.assigned_animation = animation_name
	_runtime_player.seek(animation_time, true, true)
	_runtime_player.pause()
	_runtime_player.remove_animation_library(pose_library_name)
	var restored_transform: Transform3D = transform
	set_notify_local_transform(true)
	transform = restored_transform


func _on_animation_finished(finished_animation: StringName) -> void:
	if finished_animation != animation_name or not is_animating() or _completion_pending or _restoration_pending or not _motion_fault.is_empty():
		return
	if _suspended and not _applying_animation:
		return
	_completion_pending = true
	_pending_animation = _action_animation
	_pending_serial = _motion_serial
	_pending_frame = Engine.get_physics_frames()


func _finish_pending() -> void:
	var natural_completion: bool = _completion_pending
	_completed_transform = transform
	if natural_completion:
		_stable_open = _expected_direction == 1
		state = MotionState.OPEN if _stable_open else MotionState.CLOSED
	_completion_pending = false
	_restoration_pending = false
	_expected_direction = 0
	_action_animation = null
	_pending_animation = null
	if natural_completion:
		motion_completed.emit(_stable_open)


func _interrupt_motion(reason: String) -> void:
	_invalidate_motion()
	_motion_fault = reason
	push_warning("封装控制件动作中断：%s；%s" % [get_path(), reason])
	motion_cancelled.emit(reason)


func _invalidate_motion() -> void:
	_motion_serial += 1
	_completion_pending = false
	_restoration_pending = false
	_expected_direction = 0
	_suspended = false
	_action_animation = null
	_pending_animation = null
	_deferred_action = 0
	_deferred_player = null
	state = MotionState.OPEN if _stable_open else MotionState.CLOSED
	if not _applying_animation and _node_is_live(_runtime_player):
		_runtime_player.stop(true)


func _apply_deferred_action() -> bool:
	if _deferred_action == 0:
		return false
	set_notify_local_transform(true)
	var requested_action: int = _deferred_action
	var requested_open: bool = _deferred_open
	var requested_player: AnimationPlayer = _deferred_player
	_deferred_action = 0
	_deferred_player = null
	if requested_action == 2:
		rebind_animation_player(requested_player)
	elif requested_action == 3:
		_start_motion(requested_open)
	else:
		var error: String = _get_dependency_error()
		if error.is_empty():
			_motion_fault = ""
			_restore_stable_state(requested_open)
		else:
			_motion_fault = error
			if _node_is_live(_runtime_player):
				_runtime_player.stop(true)
	return true


func _disconnect_player() -> void:
	if is_instance_valid(_runtime_player) and _runtime_player.animation_finished.is_connected(_on_animation_finished):
		_runtime_player.animation_finished.disconnect(_on_animation_finished)


func _exit_tree() -> void:
	_invalidate_motion()
	_disconnect_player()


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
