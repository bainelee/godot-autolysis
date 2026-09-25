class_name AutolysisInteractionComponent
extends Node3D
## 附加在物理体上的交互入口；物体负责接收请求并执行效果。

signal interaction_requested(actor: Node3D)

enum InteractionMode {
	DIRECT,
	FOCUS,
}

@export var is_enabled: bool = true
@export var interaction_mode: InteractionMode = InteractionMode.DIRECT

var _is_dispatching: bool = false
var _is_querying_availability: bool = false
var _availability_check_configured: bool = false
var _availability_check: Callable = Callable()


## 查询必须同步、只读，接收发起者并返回布尔值；无效配置不会退回无限制状态。
func set_availability_check(check: Callable) -> void:
	_availability_check = check
	_availability_check_configured = true


## 只有明确清除配置才恢复原有的不附加业务条件行为。
func clear_availability_check() -> void:
	_availability_check = Callable()
	_availability_check_configured = false


## 仅查询当前请求能否分发，不产生物体效果。
func can_interact(actor: Node3D) -> bool:
	if _is_querying_availability or not _has_base_permission(actor):
		return false
	if not _availability_check_configured:
		return true
	if not _has_live_availability_check():
		return false
	var configured_check: Callable = _availability_check
	_is_querying_availability = true
	var result: Variant = configured_check.call(actor)
	# 配置方法不应释放节点；即使错误回调释放组件，也不再访问其成员。
	if not is_instance_valid(self):
		return false
	_is_querying_availability = false
	if typeof(result) != TYPE_BOOL or not result:
		return false
	if not _availability_check_configured or _availability_check != configured_check:
		return false
	# 回调边界后复核，禁止向排队释放或刚失效的对象分发请求。
	return _has_base_permission(actor) and _has_live_availability_check()


func _has_base_permission(actor: Node3D) -> bool:
	if _is_dispatching or not is_enabled or interaction_mode != InteractionMode.DIRECT:
		return false
	if not is_inside_tree() or is_queued_for_deletion():
		return false
	if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.is_queued_for_deletion():
		return false
	var physical_parent: Node = get_parent()
	if not is_instance_valid(physical_parent) or not physical_parent is PhysicsBody3D:
		return false
	if not physical_parent.is_inside_tree() or physical_parent.is_queued_for_deletion():
		return false
	return _has_single_live_receiver()


## 返回真仅表示请求已分发，不表示动画或其他延迟效果已完成。
func try_interact(actor: Node3D) -> bool:
	if not can_interact(actor):
		return false
	_is_dispatching = true
	interaction_requested.emit(actor)
	# 接收者可能释放物体；不在已释放的组件上继续写入。
	if is_instance_valid(self):
		_is_dispatching = false
	return true


func _has_live_availability_check() -> bool:
	if not _availability_check.is_valid():
		return false
	var check_object: Object = _availability_check.get_object()
	if not is_instance_valid(check_object) or not check_object is Node:
		return false
	var check_node: Node = check_object as Node
	if not check_node.is_inside_tree() or check_node.is_queued_for_deletion():
		return false
	return _availability_check.get_argument_count() == 1


func _has_single_live_receiver() -> bool:
	var connections: Array[Dictionary] = []
	connections.assign(interaction_requested.get_connections())
	if connections.size() != 1:
		return false
	var connection: Dictionary = connections[0]
	var receiver: Callable = connection["callable"]
	var flags: int = connection["flags"]
	# 延迟连接或追加源对象会破坏同步、单参数请求契约。
	if (flags & Object.CONNECT_DEFERRED) != 0 or (flags & Object.CONNECT_APPEND_SOURCE_OBJECT) != 0:
		return false
	if not receiver.is_valid() or receiver.get_argument_count() != 1:
		return false
	var receiver_object: Object = receiver.get_object()
	if not is_instance_valid(receiver_object) or not receiver_object is Node:
		return false
	var receiver_node: Node = receiver_object as Node
	return receiver_node.is_inside_tree() and not receiver_node.is_queued_for_deletion()
