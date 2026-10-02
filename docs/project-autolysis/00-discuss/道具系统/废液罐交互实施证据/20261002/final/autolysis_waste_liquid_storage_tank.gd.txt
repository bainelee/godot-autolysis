class_name AutolysisWasteLiquidStorageTank
extends StaticBody3D
## 盖子和罐体使用独立入口；设备只管理运动与处置锁，库存负责道具提交。

enum LidState { CLOSED, OPENING, OPEN, CLOSING }

@export var lid_body: AnimatableBody3D
@export var lid_interaction: AutolysisInteractionComponent
@export var disposal_interaction: AutolysisInteractionComponent
@export var animation_player: AnimationPlayer
@export var animation_name: StringName = &"lid_open"

var state: LidState = LidState.CLOSED

var _configured: bool = false
var _disposal_busy: bool = false
var _motion_fault: bool = false
var _completion_pending: bool = false
var _expected_direction: int = 0
var _closed_rotation: Vector3 = Vector3.ZERO
var _open_rotation: Vector3 = Vector3.ZERO
var _source_animation: Animation


func _ready() -> void:
	var error: String = get_configuration_error()
	if not error.is_empty():
		push_error("废液罐配置失败：%s；%s" % [get_path(), error])
		return
	_source_animation = animation_player.get_animation(animation_name)
	_closed_rotation = _source_animation.track_get_key_value(0, 0)
	_open_rotation = _source_animation.track_get_key_value(0, _source_animation.track_get_key_count(0) - 1)
	# 显式使用关闭端帧，不依赖编辑器上一次预览停留的位置。
	animation_player.playback_auto_capture = false
	animation_player.play(animation_name, 0.0)
	animation_player.seek(0.0, true)
	animation_player.pause()
	lid_interaction.set_availability_check(can_toggle)
	lid_interaction.interaction_requested.connect(_on_lid_requested)
	disposal_interaction.set_availability_check(_can_dispose_interact)
	disposal_interaction.interaction_requested.connect(_on_disposal_requested)
	animation_player.animation_finished.connect(_on_animation_finished)
	_configured = true


func get_configuration_error() -> String:
	if not _node_is_live(self):
		return "废液罐未进入有效场景树"
	if not is_in_group(&"interactable"):
		return "罐体必须属于可交互分组"
	if not _node_is_live(lid_body) or lid_body.get_parent() != self or lid_body.name != &"waste_liquid_storage_tank_lid":
		return "活动盖子必须为本罐既有直接子节点"
	if not lid_body.is_in_group(&"interactable") or not lid_body.sync_to_physics:
		return "盖子必须属于可交互分组并保留物理同步"
	var body_collision: CollisionShape3D = get_node_or_null("collision_waste_liquid_storage_tank") as CollisionShape3D
	var lid_collision: CollisionShape3D = lid_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not _valid_collision(self, body_collision) or not _valid_collision(lid_body, lid_collision):
		return "罐体和盖子必须保留各自有效的直属碰撞"
	if not _valid_component(lid_body, lid_interaction, _on_lid_requested) or not _valid_component(self, disposal_interaction, _on_disposal_requested):
		return "盖子和罐体必须各有唯一直属直接交互组件，并仅同步连接本罐"
	if not _node_is_live(animation_player) or animation_player.get_parent() != self or not animation_player.has_animation(animation_name):
		return "动画播放器或指定开盖动画无效"
	if animation_player.get_node_or_null(animation_player.root_node) != self:
		return "盖子动画的轨道根节点必须为本罐"
	if not animation_player.active or animation_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS:
		return "盖子动画必须启用并使用物理帧回调"
	if not is_finite(animation_player.speed_scale) or animation_player.speed_scale <= 0.0:
		return "盖子动画速度倍率必须为有效正数"
	if not animation_player.autoplay.is_empty() or not animation_player.animation_get_next(animation_name).is_empty() or not animation_player.get_queue().is_empty():
		return "盖子动画不得自动播放或排队切换其他动作"
	var source: Animation = animation_player.get_animation(animation_name)
	if source.loop_mode != Animation.LOOP_NONE or not is_equal_approx(source.length, 0.2):
		return "开盖动画必须为现有零点二秒非循环动作"
	if source.get_track_count() != 1 or source.track_get_type(0) != Animation.TYPE_VALUE or not source.track_is_enabled(0):
		return "开盖动画必须只有一个启用的旋转属性轨道"
	if source.track_get_path(0) != NodePath("waste_liquid_storage_tank_lid:rotation") or source.track_get_key_count(0) < 2:
		return "开盖动画必须控制既有盖子旋转并包含两端关键帧"
	var last_key: int = source.track_get_key_count(0) - 1
	if not is_zero_approx(source.track_get_key_time(0, 0)) or not is_equal_approx(source.track_get_key_time(0, last_key), source.length):
		return "盖子旋转关键帧必须覆盖动画首尾"
	var first_value: Variant = source.track_get_key_value(0, 0)
	var last_value: Variant = source.track_get_key_value(0, last_key)
	if not first_value is Vector3 or not last_value is Vector3 or not first_value.is_finite() or not last_value.is_finite() or first_value.is_equal_approx(last_value):
		return "盖子旋转端帧必须为不同的有效三维角度"
	if _source_animation != null and (source != _source_animation or not first_value.is_equal_approx(_closed_rotation) or not last_value.is_equal_approx(_open_rotation)):
		return "盖子动画或旋转端帧在初始化后被修改"
	return ""


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func is_open() -> bool:
	return not _motion_fault and state == LidState.OPEN and is_configured() and not animation_player.is_playing() and not _completion_pending and _lid_matches_rotation(_open_rotation)


func is_animating() -> bool:
	return state == LidState.OPENING or state == LidState.CLOSING


func can_toggle(actor: Node3D) -> bool:
	if not _actor_is_valid(actor) or not is_configured() or _disposal_busy or _motion_fault or is_animating() or animation_player.is_playing():
		return false
	if state != LidState.CLOSED and state != LidState.OPEN:
		return false
	return _lid_matches_rotation(_closed_rotation if state == LidState.CLOSED else _open_rotation)


func try_toggle(actor: Node3D) -> bool:
	if not can_toggle(actor):
		return false
	_completion_pending = false
	if state == LidState.CLOSED:
		state = LidState.OPENING
		_expected_direction = 1
		animation_player.play(animation_name, 0.0)
	else:
		state = LidState.CLOSING
		_expected_direction = -1
		animation_player.play_backwards(animation_name, 0.0)
	if not _playback_matches_motion():
		_set_motion_fault("盖子动画启动后的名称或方向不符合请求")
		return false
	return true


func can_dispose(actor: Node3D, allow_busy_query: bool = false) -> bool:
	return _actor_is_valid(actor) and is_open() and (allow_busy_query or not _disposal_busy)


func try_begin_disposal(actor: Node3D) -> bool:
	if not can_dispose(actor):
		return false
	_disposal_busy = true
	return true


func end_disposal() -> void:
	_disposal_busy = false


func _physics_process(_delta: float) -> void:
	if not _configured or _motion_fault:
		return
	var error: String = get_configuration_error()
	if not error.is_empty():
		_set_motion_fault(error)
		return
	if _completion_pending:
		# 物理同步会先恢复上一有效变换；完成信号后的下一物理帧才核对真实盖子端帧。
		var target_rotation: Vector3 = _open_rotation if state == LidState.OPENING else _closed_rotation
		if not is_animating() or animation_player.is_playing() or not _lid_matches_rotation(target_rotation):
			_set_motion_fault("盖子动画完成后实际物理端帧不符合请求")
			return
		state = LidState.OPEN if state == LidState.OPENING else LidState.CLOSED
		_completion_pending = false
		_expected_direction = 0
	elif is_animating() and not _playback_matches_motion():
		_set_motion_fault("盖子动画被中断、替换或改变了播放方向")
	elif not is_animating() and (animation_player.is_playing() or not _lid_matches_rotation(_closed_rotation if state == LidState.CLOSED else _open_rotation)):
		_set_motion_fault("盖子稳定状态与实际旋转或播放状态不一致")


func _lid_matches_rotation(expected_rotation: Vector3) -> bool:
	# 物理同步重新分解变换后，同一姿态可能具有不同欧拉角；比较实际局部旋转矩阵。
	return _node_is_live(lid_body) and lid_body.basis.orthonormalized().is_equal_approx(Basis.from_euler(expected_rotation, lid_body.rotation_order))


func _on_animation_finished(finished_animation: StringName) -> void:
	if not _configured or _motion_fault:
		return
	if finished_animation != animation_name or not is_animating() or _completion_pending or not is_configured():
		_set_motion_fault("盖子动画完成信号与当前运动不一致")
		return
	var expected_direction: int = 1 if state == LidState.OPENING else -1
	var target_time: float = _source_animation.length if state == LidState.OPENING else 0.0
	# 引擎在完成信号之前停止播放器，方向由本次运动记录与实际动画端点共同验证。
	if _expected_direction != expected_direction or animation_player.assigned_animation != animation_name or animation_player.is_playing() or not is_equal_approx(animation_player.current_animation_position, target_time):
		_set_motion_fault("盖子动画完成的方向、名称或时间端点不符合请求")
		return
	_completion_pending = true


func _playback_matches_motion() -> bool:
	if not _node_is_live(animation_player) or not animation_player.is_playing() or animation_player.assigned_animation != animation_name:
		return false
	var speed: float = animation_player.get_playing_speed()
	return is_finite(speed) and ((_expected_direction == 1 and speed > 0.0) or (_expected_direction == -1 and speed < 0.0))


func _set_motion_fault(reason: String) -> void:
	if _motion_fault:
		return
	_motion_fault = true
	_completion_pending = false
	if _node_is_live(animation_player):
		animation_player.pause()
	push_error("废液罐盖子故障，交互已锁闭：%s；%s" % [get_path(), reason])


func _valid_collision(body: PhysicsBody3D, collision: CollisionShape3D) -> bool:
	return _node_is_live(collision) and collision.get_parent() == body and is_instance_valid(collision.shape) and not collision.disabled


func _valid_component(body: PhysicsBody3D, component: AutolysisInteractionComponent, receiver: Callable) -> bool:
	if not _node_is_live(component) or component.get_parent() != body or not component.is_enabled or component.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return false
	var count: int = 0
	for child: Node in body.get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	if count != 1:
		return false
	var receivers: Array[Dictionary] = []
	receivers.assign(component.interaction_requested.get_connections())
	if not _configured:
		return receivers.is_empty()
	return receivers.size() == 1 and receivers[0]["callable"] == receiver and receivers[0]["flags"] == 0


func _actor_is_valid(actor: Node3D) -> bool:
	if not _node_is_live(actor) or get_tree().paused:
		return false
	return not actor is AutolysisPlayer or (actor as AutolysisPlayer).is_interaction_input_allowed()


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()


func _on_lid_requested(actor: Node3D) -> void:
	try_toggle(actor)


func _can_dispose_interact(actor: Node3D) -> bool:
	if not _node_is_live(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return _node_is_live(inventory) and inventory.can_dispose_in_waste_tank(actor, self)


func _on_disposal_requested(actor: Node3D) -> void:
	if not _node_is_live(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if _node_is_live(inventory):
		inventory.try_dispose_in_waste_tank(actor, self)
