class_name AutolysisPackingStartButton
extends StaticBody3D
## 合法点击接受即启动计时；按钮按压与加工计时并行运行。

@export var start_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D
@export var animation_name: StringName = &"button_start_make_press"

var machine: AutolysisPackingMachine
var focus_target: AutolysisFocusTarget
var _runtime_player: AnimationPlayer
var _configured: bool = false


func _ready() -> void:
	if is_instance_valid(start_interaction):
		start_interaction.is_enabled = false


func configure(owner_machine: AutolysisPackingMachine, target: AutolysisFocusTarget, runtime_player: AnimationPlayer) -> bool:
	if _configured:
		return false
	machine = owner_machine
	focus_target = target
	_runtime_player = runtime_player
	if not get_configuration_error().is_empty():
		return false
	_runtime_player.play(animation_name, 0.0)
	_runtime_player.seek(0.0, true)
	_runtime_player.pause()
	start_interaction.set_availability_check(can_start)
	start_interaction.interaction_requested.connect(_on_start_requested)
	_configured = true
	return true


func get_configuration_error() -> String:
	if not _node_is_live(self) or not _node_is_live(machine) or get_parent() != machine or not _node_is_live(focus_target) or focus_target.get_parent() != machine:
		return "开始按钮与聚焦描述必须属于同一有效封装器"
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
	var receivers: Array[Dictionary] = []
	receivers.assign(start_interaction.interaction_requested.get_connections())
	if not _configured and not receivers.is_empty():
		return "开始按钮初始化前不得连接其他接收者"
	if _configured and (receivers.size() != 1 or receivers[0]["callable"] != _on_start_requested or receivers[0]["flags"] != 0):
		return "开始按钮必须只同步连接自身请求方法"
	if not _node_is_live(_runtime_player) or _runtime_player.get_parent() != machine or not _runtime_player.has_animation(animation_name) or _runtime_player.get_node_or_null(_runtime_player.root_node) != machine:
		return "开始按钮独立动画配置无效"
	if not _runtime_player.active or _runtime_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS or _runtime_player.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return "开始按钮动画必须使用可暂停物理帧"
	var animation: Animation = _runtime_player.get_animation(animation_name)
	if animation.loop_mode != Animation.LOOP_NONE or not is_equal_approx(animation.length, 0.12) or animation.get_track_count() != 1 or animation.track_get_path(0) != NodePath("button_start_packing/button_press:position"):
		return "开始按钮必须绑定既有零点一二秒按压动作"
	return ""


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func can_start(actor: Node3D) -> bool:
	return is_configured() and machine.is_actor_focused(actor) and machine.can_start_processing()


func play_press() -> void:
	_runtime_player.play(animation_name, 0.0)
	_runtime_player.seek(0.0, true)


func _on_start_requested(actor: Node3D) -> void:
	machine.try_start_processing(actor)


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
