class_name AutolysisPackingStartButton
extends StaticBody3D
## 开始入口只依赖业务引用；按压是与加工并行的可选表现。

@export var start_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D
@export var animation_name: StringName = &"button_start_make_press"

var machine: AutolysisPackingMachine
var focus_target: AutolysisFocusTarget
var _runtime_player: AnimationPlayer
var _configured: bool = false
var _press_enabled: bool = false
var _press_error: String = ""
var _press_active: bool = false
var _press_animation: Animation
var _applying_press: bool = false
var _queued_rebind: bool = false
var _queued_player: AnimationPlayer


func _ready() -> void:
	if is_instance_valid(start_interaction):
		start_interaction.is_enabled = false


func configure(owner_machine: AutolysisPackingMachine, target: AutolysisFocusTarget, runtime_player: AnimationPlayer) -> bool:
	if _configured:
		return false
	machine = owner_machine
	focus_target = target
	if not get_configuration_error().is_empty():
		return false
	start_interaction.set_availability_check(can_start)
	start_interaction.set_execution_handler(_on_start_requested)
	_configured = true
	rebind_press_animation(runtime_player)
	return true


func get_configuration_error() -> String:
	if not _node_is_live(self) or not _node_is_live(machine) or not machine.is_ancestor_of(self) or not _node_is_live(focus_target) or not machine.is_ancestor_of(focus_target):
		return "开始按钮与聚焦描述必须归属于同一有效封装器"
	if not _node_is_live(collision_shape) or collision_shape.get_parent() != self or collision_shape.shape == null or collision_shape.disabled:
		return "开始按钮直属碰撞无效"
	if not _node_is_live(start_interaction) or start_interaction.get_parent() != self or start_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "开始按钮直属直接交互组件无效"
	var count: int = 0
	for child: Node in get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	if count != 1:
		return "开始按钮必须恰好配置一个交互组件"
	if _configured and not start_interaction.has_execution_handler(_on_start_requested):
		return "开始按钮缺少自身业务执行绑定"
	return ""


func get_press_error() -> String:
	if not _press_enabled and not _press_error.is_empty():
		return _press_error
	if not _node_is_live(_runtime_player) or not _runtime_player.has_animation(animation_name):
		return "开始按钮缺少可选按压播放器或指定动画"
	if not _node_is_live(machine) or not machine.is_ancestor_of(_runtime_player):
		return "开始按钮按压播放器不属于本机"
	var animation_root: Node = _runtime_player.get_node_or_null(_runtime_player.root_node)
	if not _node_is_live(animation_root) or (animation_root != machine and not machine.is_ancestor_of(animation_root)):
		return "开始按钮按压播放器根引用不属于本机"
	if not _runtime_player.active or _runtime_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL or _runtime_player.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return "开始按钮按压播放器必须由可暂停物理处理推进"
	if not is_finite(_runtime_player.speed_scale) or _runtime_player.speed_scale <= 0.0:
		return "开始按钮按压速度必须为有限正数"
	var animation: Animation = _runtime_player.get_animation(animation_name)
	if animation.loop_mode != Animation.LOOP_NONE or not is_finite(animation.length) or animation.length <= 0.0:
		return "开始按钮按压必须为有限非循环动作"
	return ""


func rebind_press_animation(runtime_player: AnimationPlayer) -> bool:
	if _applying_press:
		_press_active = false
		_press_enabled = false
		_queued_rebind = true
		_queued_player = runtime_player
		return true
	if is_instance_valid(_runtime_player) and _runtime_player.animation_finished.is_connected(_on_press_finished):
		_runtime_player.animation_finished.disconnect(_on_press_finished)
	_runtime_player = runtime_player
	_press_error = ""
	_press_active = false
	_press_animation = null
	_press_error = get_press_error()
	_press_enabled = _press_error.is_empty()
	if _press_enabled:
		_runtime_player.animation_finished.connect(_on_press_finished)
		_runtime_player.stop(true)
		_restore_press_pose()
	else:
		push_warning("封装开始按钮按压停止更新：%s" % _press_error)
	return _press_enabled


func _restore_press_pose() -> void:
	var pose_animation: Animation = _runtime_player.get_animation(animation_name).duplicate() as Animation
	for track: int in pose_animation.get_track_count():
		if pose_animation.track_get_type(track) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION]:
			pose_animation.track_set_enabled(track, false)
	var pose_library: AnimationLibrary = AnimationLibrary.new()
	pose_library.add_animation(&"pose", pose_animation)
	var pose_library_name: StringName = &"_packing_button_restore"
	var suffix: int = 0
	while _runtime_player.has_animation_library(pose_library_name):
		suffix += 1
		pose_library_name = StringName("_packing_button_restore_%d" % suffix)
	_runtime_player.add_animation_library(pose_library_name, pose_library)
	_runtime_player.assigned_animation = StringName(String(pose_library_name) + "/pose")
	_runtime_player.seek(0.0, true, true)
	_runtime_player.assigned_animation = animation_name
	_runtime_player.seek(0.0, true, true)
	_runtime_player.pause()
	_runtime_player.remove_animation_library(pose_library_name)


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func can_start(actor: Node3D) -> bool:
	return is_configured() and machine.is_actor_focused(actor) and machine.can_start_processing()


func play_press() -> void:
	if not _press_enabled:
		return
	_press_error = get_press_error()
	if not _press_error.is_empty():
		_press_enabled = false
		push_warning("封装开始按钮按压停止更新：%s" % _press_error)
		return
	_runtime_player.stop(true)
	_press_active = true
	_press_animation = _runtime_player.get_animation(animation_name)
	_runtime_player.play(animation_name, 0.0)
	_applying_press = true
	_runtime_player.seek(0.0, true, true)
	if _node_is_live(self):
		_applying_press = false
		_apply_queued_rebind()


func _on_start_requested(actor: Node3D) -> void:
	machine.try_start_processing(actor)


func _physics_process(delta: float) -> void:
	if not _press_enabled or not _press_active:
		return
	var error: String = get_press_error()
	if error.is_empty() and (_runtime_player.current_animation != animation_name or not _runtime_player.is_playing() or _runtime_player.get_animation(animation_name) != _press_animation or _runtime_player.get_playing_speed() <= 0.0):
		error = "按压被外部停止、替换播放或替换资源"
	if not error.is_empty():
		_press_error = error
		_press_enabled = false
		_press_active = false
		push_warning("封装开始按钮按压停止更新：%s" % error)
		return
	_applying_press = true
	_runtime_player.advance(delta)
	if _node_is_live(self):
		_applying_press = false
		_apply_queued_rebind()


func _apply_queued_rebind() -> void:
	if not _queued_rebind:
		return
	var replacement: AnimationPlayer = _queued_player
	_queued_rebind = false
	_queued_player = null
	rebind_press_animation(replacement)


func _on_press_finished(finished_animation: StringName) -> void:
	if finished_animation == animation_name:
		_press_active = false
		_press_animation = null


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
