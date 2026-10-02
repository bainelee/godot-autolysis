class_name AutolysisBlendHandle
extends StaticBody3D
## 拉杆独占物理位置写入；输入控制器只提交已绑定角色的真实纵向位移。

signal interaction_completed(actor: Node3D)

enum HandleState { IDLE, DRAGGING, HOLDING, RETURNING }

const TOP_Y: float = 0.12
const BOTTOM_Y: float = -0.12
const HOLD_SECONDS: float = 0.1
const RETURN_SECONDS: float = 0.2
const RETURN_SPEED: float = (TOP_Y - BOTTOM_Y) / RETURN_SECONDS

@export var device_root: PhysicsBody3D
@export var drag_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D
## 临时初始配置，单位为局部坐标单位／鼠标视口纵向输入单位；最终比例须真实操作调校。
@export_range(0.000001, 0.01, 0.000001, "or_greater") var mouse_to_handle_ratio: float = 0.0005

var focus_target: AutolysisFocusTarget
var state: HandleState = HandleState.IDLE

var _configured: bool = false
var _drag_actor: Node3D
var _hold_remaining: float = 0.0
var _automatic_started_frame: int = -1


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# 控制器优先处理本帧有序输入；自动流程随后处理，进入自动状态的当帧为计时零点。
	process_physics_priority = 100


func _ready() -> void:
	if is_instance_valid(drag_interaction):
		drag_interaction.is_enabled = false


func configure(target: AutolysisFocusTarget) -> bool:
	if _configured:
		return false
	focus_target = target
	if not get_configuration_error().is_empty():
		return false
	drag_interaction.set_availability_check(can_begin_drag)
	drag_interaction.interaction_requested.connect(_on_drag_requested)
	state = HandleState.IDLE
	_set_y(TOP_Y)
	_configured = true
	return true


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func get_configuration_error() -> String:
	if not _node_is_live(self) or not _node_is_live(device_root) or not device_root.is_ancestor_of(self):
		return "拉杆必须位于已绑定设备的子树中"
	if not _node_is_live(focus_target) or focus_target.get_parent() != device_root:
		return "拉杆的聚焦目标描述必须属于已绑定设备"
	if not _node_is_live(drag_interaction) or drag_interaction.get_parent() != self:
		return "drag_interaction（拖动交互组件）必须位于拉杆直接子级"
	if drag_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "拉杆组件必须使用直接动作模式"
	var component_count: int = 0
	for child: Node in get_children():
		if child is AutolysisInteractionComponent:
			component_count += 1
	if component_count != 1:
		return "拉杆必须恰好配置一个直接子交互组件"
	var receivers: Array[Dictionary] = []
	receivers.assign(drag_interaction.interaction_requested.get_connections())
	if not _configured and not receivers.is_empty():
		return "拉杆交互组件在初始化前已连接其他请求接收者"
	if _configured:
		if receivers.size() != 1 or receivers[0]["callable"] != _on_drag_requested or receivers[0]["flags"] != 0:
			return "拉杆交互组件必须只同步连接本拉杆的请求接收方法"
	if not _node_is_live(collision_shape) or collision_shape.get_parent() != self or collision_shape.shape == null or collision_shape.disabled:
		return "collision_shape（碰撞形状）必须指向拉杆直接子级的有效碰撞形状"
	if not is_finite(mouse_to_handle_ratio) or mouse_to_handle_ratio <= 0.0:
		return "mouse_to_handle_ratio（鼠标位移到拉杆位移比例）必须是大于零的有限数值"
	return ""


## 许可查询只读；设备登记与稳定聚焦均满足后才能接受一次新按下。
func can_begin_drag(actor: Node3D) -> bool:
	return is_configured() and state == HandleState.IDLE and _actor_is_focused(actor)


func try_begin_drag(actor: Node3D) -> bool:
	if not can_begin_drag(actor):
		return false
	_drag_actor = actor
	state = HandleState.DRAGGING
	return true


func is_dragging_for(actor: Node3D) -> bool:
	return _node_is_live(self) and _node_is_live(actor) and state == HandleState.DRAGGING and _drag_actor == actor


func apply_vertical_motion(actor: Node3D, vertical_motion: float) -> void:
	if not is_dragging_for(actor):
		return
	if not is_configured() or not _actor_is_focused(actor):
		cancel_drag(actor)
		return
	if not is_finite(vertical_motion) or vertical_motion == 0.0:
		return
	var next_y: float = clampf(position.y - vertical_motion * mouse_to_handle_ratio, BOTTOM_Y, TOP_Y)
	_set_y(next_y)
	if position != Vector3(0.0, BOTTOM_Y, 0.0):
		return
	# 先锁定和解除角色归属，再同步通知；回调重入不能重新开始本周期。
	state = HandleState.HOLDING
	_drag_actor = null
	_hold_remaining = HOLD_SECONDS
	_automatic_started_frame = Engine.get_physics_frames()
	interaction_completed.emit(actor)
	# 完成回调可能立即释放设备或拉杆，此处不再访问实例成员。


func release_drag(actor: Node3D) -> void:
	if state != HandleState.DRAGGING or _drag_actor != actor:
		return
	_start_return()


func cancel_drag(actor: Node3D) -> void:
	release_drag(actor)


func _physics_process(delta: float) -> void:
	if not _configured:
		return
	if state == HandleState.DRAGGING:
		if not is_configured() or not _actor_is_focused(_drag_actor):
			_start_return()
		return
	if state != HandleState.HOLDING and state != HandleState.RETURNING:
		return
	if Engine.get_physics_frames() == _automatic_started_frame:
		return
	var available_time: float = delta
	if state == HandleState.HOLDING:
		var consumed_time: float = minf(_hold_remaining, available_time)
		_hold_remaining = maxf(0.0, _hold_remaining - consumed_time)
		available_time -= consumed_time
		# 时间累计的浮点尾差不增加一整帧保持；最低完成判定仍严格使用下限。
		if _hold_remaining > 0.000000001:
			return
		_hold_remaining = 0.0
		state = HandleState.RETURNING
	if available_time <= 0.0:
		return
	var next_y: float = move_toward(position.y, TOP_Y, RETURN_SPEED * available_time)
	_set_y(next_y)
	if position == Vector3(0.0, TOP_Y, 0.0):
		state = HandleState.IDLE


func _start_return() -> void:
	_drag_actor = null
	_hold_remaining = 0.0
	_automatic_started_frame = Engine.get_physics_frames()
	state = HandleState.IDLE if position == Vector3(0.0, TOP_Y, 0.0) else HandleState.RETURNING


func _actor_is_focused(actor: Node3D) -> bool:
	if not _node_is_live(actor) or not actor is AutolysisPlayer or not _node_is_live(focus_target):
		return false
	if focus_target.get_handle_for_target(self) != self:
		return false
	var player: AutolysisPlayer = actor as AutolysisPlayer
	return player.is_focus_business_allowed() and _node_is_live(player.focus_controller) and player.focus_controller.is_focused_on(focus_target)


func _on_drag_requested(actor: Node3D) -> void:
	try_begin_drag(actor)


func _set_y(value: float) -> void:
	position = Vector3(0.0, value, 0.0)


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
