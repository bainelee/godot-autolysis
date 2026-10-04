class_name AutolysisBlendHandle
extends StaticBody3D
## 拉杆独占物理位置写入；输入控制器只提交已绑定角色的真实纵向位移。

signal interaction_completed(actor: Node3D)
signal handle_pull_denied(actor: Node3D, reason: StringName)

enum HandleState { IDLE, DRAGGING, HOLDING, RETURNING }

@export var device_root: PhysicsBody3D
@export var drag_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D
@export var top_reference: Node3D
@export var full_travel: float = 0.24
@export var restricted_travel: float = 0.04
@export var hold_seconds: float = 0.1
@export var return_seconds: float = 0.2
## 临时初始配置，单位为局部坐标单位／鼠标视口纵向输入单位；最终比例须真实操作调校。
@export_range(0.000001, 0.01, 0.000001, "or_greater") var mouse_to_handle_ratio: float = 0.0005

var focus_target: AutolysisFocusTarget
var state: HandleState = HandleState.IDLE

var _configured: bool = false
var _drag_actor: Node3D
var _hold_remaining: float = 0.0
var _automatic_started_frame: int = -1
var _restricted_drag: bool = false
var _drag_ratio: float = 0.0
var _drag_bottom_y: float = 0.0
var _top_position: Vector3


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
	drag_interaction.set_execution_handler(_on_drag_requested)
	state = HandleState.IDLE
	_top_position = top_reference.position if top_reference.get_parent() == get_parent() else get_parent_node_3d().to_local(top_reference.global_position)
	position = _top_position
	_configured = true
	return true


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func get_configuration_error() -> String:
	if not _node_is_live(self) or not _node_is_live(device_root) or not device_root.is_ancestor_of(self):
		return "拉杆必须位于已绑定设备的子树中"
	if not device_root is AutolysisBlendMachine:
		return "拉杆必须绑定配药器根物理体"
	if not _node_is_live(focus_target) or not device_root.is_ancestor_of(focus_target):
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
	if _configured and not drag_interaction.has_execution_handler(_on_drag_requested):
		return "拉杆交互组件的业务执行绑定失效"
	if not _node_is_live(collision_shape) or collision_shape.get_parent() != self or collision_shape.shape == null or collision_shape.disabled:
		return "collision_shape（碰撞形状）必须指向拉杆直接子级的有效碰撞形状"
	if not is_finite(mouse_to_handle_ratio) or mouse_to_handle_ratio <= 0.0:
		return "mouse_to_handle_ratio（鼠标位移到拉杆位移比例）必须是大于零的有限数值"
	if not _node_is_live(top_reference) or top_reference == self or is_ancestor_of(top_reference) or not device_root.is_ancestor_of(top_reference):
		return "top_reference（顶部参照）必须为设备子树中的独立参照"
	if not is_instance_valid(get_parent_node_3d()):
		return "拉杆必须具有有效三维父节点以换算顶部参照"
	if not top_reference.global_position.is_finite():
		return "顶部参照位置必须为有限数值"
	if not is_finite(full_travel) or full_travel <= 0.0 or not is_finite(restricted_travel) or restricted_travel < 0.0 or restricted_travel > full_travel:
		return "完整行程必须为有限正数，受限行程必须位于零和完整行程之间"
	if not is_finite(hold_seconds) or hold_seconds < 0.0 or not is_finite(return_seconds) or return_seconds <= 0.0:
		return "保持时长必须为有限非负数，完整回弹时长必须为有限正数"
	return ""


## 许可查询只读；设备登记与稳定聚焦均满足后才能接受一次新按下。
func can_begin_drag(actor: Node3D) -> bool:
	return is_configured() and not (device_root as AutolysisBlendMachine).is_interaction_locked() and state == HandleState.IDLE and _actor_is_focused(actor)


func try_begin_drag(actor: Node3D) -> bool:
	if not can_begin_drag(actor):
		return false
	_drag_actor = actor
	var machine: AutolysisBlendMachine = device_root as AutolysisBlendMachine
	var reason: StringName = machine.get_start_denial_reason()
	_restricted_drag = not reason.is_empty()
	_drag_ratio = mouse_to_handle_ratio * 0.5 if _restricted_drag else mouse_to_handle_ratio
	# 限位与三维位置使用相同精度，避免场景参照和标量减法形成不可表示的触底值。
	var travel: float = restricted_travel if _restricted_drag else full_travel
	_drag_bottom_y = (_top_position - Vector3(0.0, travel, 0.0)).y
	state = HandleState.DRAGGING
	if _restricted_drag:
		handle_pull_denied.emit(actor, reason)
	return true


func is_dragging_for(actor: Node3D) -> bool:
	return _node_is_live(self) and _node_is_live(actor) and state == HandleState.DRAGGING and _drag_actor == actor


func apply_vertical_motion(actor: Node3D, vertical_motion: float) -> void:
	if not is_dragging_for(actor):
		return
	if not _can_continue_drag(actor):
		cancel_drag(actor)
		return
	if not is_finite(vertical_motion) or vertical_motion == 0.0:
		return
	var next_y: float = clampf(position.y - vertical_motion * _drag_ratio, _drag_bottom_y, _top_position.y)
	_set_y(next_y)
	if _restricted_drag or next_y != _drag_bottom_y:
		return
	# 先锁定和解除角色归属，再同步通知；回调重入不能重新开始本周期。
	state = HandleState.HOLDING
	_drag_actor = null
	_hold_remaining = hold_seconds
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
		if not _can_continue_drag(_drag_actor):
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
	var next_y: float = move_toward(position.y, _top_position.y, full_travel / return_seconds * available_time)
	_set_y(next_y)
	if next_y == _top_position.y:
		state = HandleState.IDLE


func _start_return() -> void:
	_drag_actor = null
	_hold_remaining = 0.0
	_automatic_started_frame = Engine.get_physics_frames()
	state = HandleState.IDLE if position.y == _top_position.y else HandleState.RETURNING


func is_restricted_drag() -> bool:
	return state == HandleState.DRAGGING and _restricted_drag


func get_active_mouse_ratio() -> float:
	return _drag_ratio if state == HandleState.DRAGGING else mouse_to_handle_ratio


func _can_continue_drag(actor: Node3D) -> bool:
	if not is_configured() or not _actor_is_focused(actor):
		return false
	var machine: AutolysisBlendMachine = device_root as AutolysisBlendMachine
	return not machine.is_interaction_locked() and (_restricted_drag or machine.can_start_processing())


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
	position = Vector3(_top_position.x, value, _top_position.z)


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
