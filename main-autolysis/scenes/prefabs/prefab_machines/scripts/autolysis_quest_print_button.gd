class_name AutolysisQuestPrintButton
extends StaticBody3D
## 唯一业务执行绑定调用本机；按压动作独立且不等待完成。

@export var print_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D
@export var animation_name: StringName = &"button_print_quest_press"

var machine: AutolysisQuestMachine
var focus_target: AutolysisFocusTarget
var last_press_error: String = ""
var _configured: bool = false
var _runtime_player: AnimationPlayer
var _press_animation: Animation
var _press_active: bool = false
var _press_enabled: bool = false
var _press_paused: bool = false
var _applying_press: bool = false
var _queued_rebind: bool = false
var _queued_player: AnimationPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if _live(print_interaction):
		print_interaction.is_enabled = false


func configure(owner_machine: AutolysisQuestMachine, target: AutolysisFocusTarget, player: AnimationPlayer) -> bool:
	if _configured:
		return false
	machine = owner_machine
	focus_target = target
	if not get_configuration_error().is_empty():
		return false
	print_interaction.set_availability_check(can_start)
	print_interaction.set_execution_handler(_on_print_requested)
	_configured = true
	rebind_press_animation(player)
	return true


func get_configuration_error() -> String:
	if not _live(self) or not _live(machine) or not machine.is_ancestor_of(self) or not _live(focus_target) or not machine.is_ancestor_of(focus_target):
		return "打印按钮与聚焦描述必须属于同一通知中心"
	if not _live(collision_shape) or collision_shape.get_parent() != self or collision_shape.shape == null or collision_shape.disabled:
		return "打印按钮直属碰撞失效"
	if not _live(print_interaction) or print_interaction.get_parent() != self or print_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "打印按钮直属直接交互组件失效"
	var count: int = 0
	for child: Node in get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	if count != 1:
		return "打印按钮必须配置唯一直属交互组件"
	if _configured and not print_interaction.has_execution_handler(_on_print_requested):
		return "打印按钮业务执行绑定失效"
	return ""


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func can_start(actor: Node3D) -> bool:
	return is_configured() and machine.can_start_print(actor)


func _on_print_requested(actor: Node3D) -> void:
	if is_configured():
		machine.try_start_print(actor)


func get_press_error() -> String:
	if not _live(_runtime_player) or not _live(machine) or not machine.is_ancestor_of(_runtime_player) or not _runtime_player.has_animation(animation_name):
		return "打印按钮可选按压播放器或动画失效"
	var root: Node = _runtime_player.get_node_or_null(_runtime_player.root_node)
	if not _live(root) or (root != machine and not machine.is_ancestor_of(root)):
		return "按压播放器根引用不属于通知中心"
	if not _runtime_player.active or _runtime_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
		return "按压播放器必须由拥有者推进"
	if not is_finite(_runtime_player.speed_scale) or _runtime_player.speed_scale <= 0.0:
		return "按压播放速度必须为有限正数"
	var animation: Animation = _runtime_player.get_animation(animation_name)
	if animation.loop_mode != Animation.LOOP_NONE or not is_finite(animation.length) or animation.length <= 0.0:
		return "按压动画必须为有限非循环动作"
	return ""


func rebind_press_animation(player: AnimationPlayer) -> bool:
	if _applying_press:
		_press_active = false
		_press_enabled = false
		_queued_rebind = true
		_queued_player = player
		return true
	if is_instance_valid(_runtime_player) and _runtime_player.animation_finished.is_connected(_on_press_finished):
		_runtime_player.animation_finished.disconnect(_on_press_finished)
	_runtime_player = player
	_press_active = false
	_press_animation = null
	last_press_error = get_press_error()
	_press_enabled = last_press_error.is_empty()
	if _press_enabled:
		_runtime_player.stop(true)
		_restore_press_pose()
		_runtime_player.animation_finished.connect(_on_press_finished)
	else:
		push_warning("通知中心按压停止更新：%s" % last_press_error)
	return _press_enabled


func _restore_press_pose() -> void:
	var pose: Animation = _runtime_player.get_animation(animation_name).duplicate() as Animation
	for track: int in pose.get_track_count():
		if pose.track_get_type(track) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION]:
			pose.track_set_enabled(track, false)
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(&"pose", pose)
	var library_name: StringName = &"_quest_button_restore"
	var suffix: int = 0
	while _runtime_player.has_animation_library(library_name):
		suffix += 1
		library_name = StringName("_quest_button_restore_%d" % suffix)
	_runtime_player.add_animation_library(library_name, library)
	_runtime_player.assigned_animation = StringName(String(library_name) + "/pose")
	_runtime_player.seek(0.0, true, true)
	_runtime_player.pause()
	_runtime_player.assigned_animation = animation_name
	_runtime_player.remove_animation_library(library_name)


func play_press() -> void:
	if not _press_enabled:
		return
	last_press_error = get_press_error()
	if not last_press_error.is_empty():
		_disable_press(last_press_error)
		return
	_runtime_player.stop(true)
	_press_active = true
	_press_animation = _runtime_player.get_animation(animation_name)
	_runtime_player.play(animation_name, 0.0)
	_applying_press = true
	_runtime_player.seek(0.0, true, true)
	if _live(self):
		_applying_press = false
		_apply_queued_rebind()


func set_press_paused(value: bool) -> void:
	_press_paused = value


func _physics_process(delta: float) -> void:
	if not _press_enabled or not _press_active or _press_paused:
		return
	var error: String = get_press_error()
	if error.is_empty() and (_runtime_player.current_animation != animation_name or not _runtime_player.is_playing() or _runtime_player.get_animation(animation_name) != _press_animation or _runtime_player.get_playing_speed() <= 0.0):
		error = "按压被外部停止或替换"
	if not error.is_empty():
		_disable_press(error)
		return
	_applying_press = true
	_runtime_player.advance(delta)
	if _live(self):
		_applying_press = false
		_apply_queued_rebind()


func _disable_press(reason: String) -> void:
	last_press_error = reason
	_press_active = false
	_press_enabled = false
	push_warning("通知中心按压停止更新：%s" % reason)


func _apply_queued_rebind() -> void:
	if not _queued_rebind:
		return
	var replacement: AnimationPlayer = _queued_player
	_queued_rebind = false
	_queued_player = null
	rebind_press_animation(replacement)


func _on_press_finished(finished: StringName) -> void:
	if finished == animation_name:
		_press_active = false
		_press_animation = null


func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
