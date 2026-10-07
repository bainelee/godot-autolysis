class_name AutolysisInteractionComponent
extends Node3D
## 附加在物理体上的交互入口；明确绑定的拥有者执行业务，信号仅发布分发观察。

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
var _execution_handler: Callable = Callable()


## 同步业务入口接收发起者；观察者连接数量不参与业务许可。
func set_execution_handler(handler: Callable) -> void:
	_execution_handler = handler


func clear_execution_handler() -> void:
	_execution_handler = Callable()


## 可按期望回调核对登记，避免其他入口错误借用本组件。
func has_execution_handler(expected: Callable = Callable()) -> bool:
	return _has_live_execution_handler() and (expected.is_null() or _execution_handler == expected)


## 查询必须同步、只读，接收发起者并返回布尔值；无效配置不会退回无限制状态。
func set_availability_check(check: Callable) -> void:
	_availability_check = check
	_availability_check_configured = true


## 只有明确清除配置才恢复原有的不附加业务条件行为。
func clear_availability_check() -> void:
	_availability_check = Callable()
	_availability_check_configured = false


## 仅查询当前请求能否分发，不产生物体效果。
func can_interact(actor: Node3D, requested_mode: InteractionMode = InteractionMode.DIRECT) -> bool:
	if _is_querying_availability or not _has_base_permission(actor, requested_mode):
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
	return _has_base_permission(actor, requested_mode) and _has_live_availability_check()


func _has_base_permission(actor: Node3D, requested_mode: InteractionMode) -> bool:
	if _is_dispatching or not is_enabled or interaction_mode != requested_mode:
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
	return _has_live_execution_handler()


## 返回真仅表示请求已分发，不表示动画或其他延迟效果已完成。
func try_interact(actor: Node3D, requested_mode: InteractionMode = InteractionMode.DIRECT) -> bool:
	if not can_interact(actor, requested_mode):
		return false
	_is_dispatching = true
	var handler: Callable = _execution_handler
	handler.call(actor)
	# 业务可能释放组件、命中体或发起者；仅向仍有效的观察上下文通知。
	if not is_instance_valid(self):
		return true
	if _dispatch_context_is_live(actor):
		interaction_requested.emit(actor)
	# 观察期间仍保持互斥；观察者释放源对象后不继续访问成员。
	if is_instance_valid(self):
		_is_dispatching = false
	return true


func _dispatch_context_is_live(actor: Variant) -> bool:
	if not is_inside_tree() or is_queued_for_deletion():
		return false
	var physical_parent: Node = get_parent()
	if not is_instance_valid(physical_parent) or not physical_parent.is_inside_tree() or physical_parent.is_queued_for_deletion():
		return false
	return is_instance_valid(actor) and actor is Node3D and actor.is_inside_tree() and not actor.is_queued_for_deletion()


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


func _has_live_execution_handler() -> bool:
	if not _execution_handler.is_valid() or _execution_handler.get_argument_count() != 1:
		return false
	var receiver_object: Object = _execution_handler.get_object()
	if not is_instance_valid(receiver_object) or not receiver_object is Node:
		return false
	var receiver_node: Node = receiver_object as Node
	return receiver_node.is_inside_tree() and not receiver_node.is_queued_for_deletion()
