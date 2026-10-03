class_name AutolysisPackingMotion
extends AnimatableBody3D
## 门与开关共用物理帧端帧核验；每个控制件仍有自己的播放器和运动状态。

enum MotionState { CLOSED, OPENING, OPEN, CLOSING }

# 实测物理同步后的端帧误差约为0.0000176弧度，默认向量容差会误判。
# 此容差小于0.006度；动画停止、状态和实际端帧仍同时核验。
const ENDPOINT_ANGLE_TOLERANCE: float = 0.0001

@export var toggle_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D
@export var animation_name: StringName

var machine: AutolysisPackingMachine
var focus_target: AutolysisFocusTarget
var state: MotionState = MotionState.CLOSED
var _runtime_player: AnimationPlayer
var _configured: bool = false
var _source_animation: Animation
var _closed_rotation: Vector3
var _open_rotation: Vector3
var _completion_pending: bool = false
var _expected_direction: int = 0
var _motion_fault: String = ""


func _ready() -> void:
	if is_instance_valid(toggle_interaction):
		toggle_interaction.is_enabled = false


func configure(owner_machine: AutolysisPackingMachine, target: AutolysisFocusTarget, runtime_player: AnimationPlayer) -> bool:
	if _configured:
		return false
	machine = owner_machine
	focus_target = target
	_runtime_player = runtime_player
	if not get_configuration_error().is_empty():
		return false
	_source_animation = _runtime_player.get_animation(animation_name)
	_closed_rotation = _source_animation.track_get_key_value(0, 0)
	_open_rotation = _source_animation.track_get_key_value(0, _source_animation.track_get_key_count(0) - 1)
	_runtime_player.play(animation_name, 0.0)
	_runtime_player.seek(0.0, true)
	_runtime_player.pause()
	toggle_interaction.set_availability_check(can_toggle)
	toggle_interaction.interaction_requested.connect(_on_toggle_requested)
	_runtime_player.animation_finished.connect(_on_animation_finished)
	_configured = true
	return true


func get_configuration_error() -> String:
	if not _motion_fault.is_empty():
		return _motion_fault
	if not _node_is_live(self) or not _node_is_live(machine) or get_parent() != machine:
		return "控制件必须属于有效封装器直接子级"
	if not _node_is_live(focus_target) or focus_target.get_parent() != machine:
		return "控制件与聚焦描述必须属于同一封装器"
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
	var receivers: Array[Dictionary] = []
	receivers.assign(toggle_interaction.interaction_requested.get_connections())
	if not _configured and not receivers.is_empty():
		return "控制件初始化前不得连接其他接收者"
	if _configured and (receivers.size() != 1 or receivers[0]["callable"] != _on_toggle_requested or receivers[0]["flags"] != 0):
		return "控制件必须只同步连接自身请求方法"
	if not _node_is_live(_runtime_player) or _runtime_player.get_parent() != machine or not _runtime_player.has_animation(animation_name):
		return "独立运行播放器或指定动画无效"
	if _runtime_player.get_node_or_null(_runtime_player.root_node) != machine or not _runtime_player.active or _runtime_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS:
		return "动画轨道必须使用本机根节点及物理帧"
	if _runtime_player.process_mode != Node.PROCESS_MODE_PAUSABLE or not is_equal_approx(_runtime_player.speed_scale, 1.0):
		return "动画必须使用可暂停处理及原速度"
	if not _runtime_player.autoplay.is_empty() or not _runtime_player.animation_get_next(animation_name).is_empty() or not _runtime_player.get_queue().is_empty():
		return "控制件动画不得自动播放或排队"
	var source: Animation = _runtime_player.get_animation(animation_name)
	if source.loop_mode != Animation.LOOP_NONE or source.get_track_count() != 1 or source.track_get_type(0) != Animation.TYPE_VALUE or not source.track_is_enabled(0):
		return "控制件动画必须只有一个启用的非循环属性轨道"
	if source.track_get_path(0) != NodePath("%s:rotation" % name) or source.track_get_key_count(0) < 2:
		return "控制件动画必须控制自身旋转并具有两端关键帧"
	var first: Variant = source.track_get_key_value(0, 0)
	var last: Variant = source.track_get_key_value(0, source.track_get_key_count(0) - 1)
	if not first is Vector3 or not last is Vector3 or not first.is_finite() or not last.is_finite() or first.is_equal_approx(last):
		return "控制件动画端帧必须为不同的有效角度"
	if _source_animation != null and (source != _source_animation or first != _closed_rotation or last != _open_rotation):
		return "初始化后的动画资源或端帧发生变化"
	return ""


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func is_open() -> bool:
	return is_configured() and state == MotionState.OPEN and not _completion_pending and not _runtime_player.is_playing() and _rotation_matches_endpoint(_open_rotation)


func is_closed() -> bool:
	return is_configured() and state == MotionState.CLOSED and not _completion_pending and not _runtime_player.is_playing() and _rotation_matches_endpoint(_closed_rotation)


func is_animating() -> bool:
	return state == MotionState.OPENING or state == MotionState.CLOSING or _completion_pending


func can_toggle(_actor: Node3D) -> bool:
	return false


func _on_toggle_requested(_actor: Node3D) -> void:
	pass


func _start_motion(opening: bool) -> void:
	var position: float = _runtime_player.current_animation_position
	if not is_animating():
		position = _source_animation.length if state == MotionState.OPEN else 0.0
	_completion_pending = false
	_expected_direction = 1 if opening else -1
	state = MotionState.OPENING if opening else MotionState.CLOSING
	# 同名动画显式恢复当前进度，取消开启时不得先跳至末帧。
	_runtime_player.play(animation_name, 0.0, float(_expected_direction), not opening)
	_runtime_player.seek(position, true)
	if (opening and is_equal_approx(position, _source_animation.length)) or (not opening and is_zero_approx(position)):
		_runtime_player.pause()
		_completion_pending = true


func _physics_process(_delta: float) -> void:
	if not _configured or not _motion_fault.is_empty():
		return
	var error: String = get_configuration_error()
	if not error.is_empty():
		_motion_fault = error
		push_error("封装器控制件配置失效：%s；%s" % [get_path(), error])
		return
	if _completion_pending:
		var endpoint: Vector3 = _open_rotation if _expected_direction == 1 else _closed_rotation
		if _runtime_player.is_playing() or not _rotation_matches_endpoint(endpoint):
			_motion_fault = "控制件动画完成后实际物理端帧不符合请求"
			push_error("封装器控制件运动故障：%s；预期角度：%s；实际角度：%s；动画进度：%.9f" % [get_path(), endpoint, rotation, _runtime_player.current_animation_position])
			return
		state = MotionState.OPEN if _expected_direction == 1 else MotionState.CLOSED
		_completion_pending = false
		_expected_direction = 0


func _on_animation_finished(finished_animation: StringName) -> void:
	if finished_animation != animation_name or not is_animating() or _completion_pending or not _motion_fault.is_empty():
		return
	var endpoint: float = _source_animation.length if _expected_direction == 1 else 0.0
	if _runtime_player.is_playing() or not is_equal_approx(_runtime_player.current_animation_position, endpoint):
		return
	_completion_pending = true


func _rotation_matches_endpoint(endpoint: Vector3) -> bool:
	if not rotation.is_finite():
		return false
	var difference := Vector3(
		angle_difference(rotation.x, endpoint.x),
		angle_difference(rotation.y, endpoint.y),
		angle_difference(rotation.z, endpoint.z)
	)
	return difference.length_squared() <= ENDPOINT_ANGLE_TOLERANCE * ENDPOINT_ANGLE_TOLERANCE


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
