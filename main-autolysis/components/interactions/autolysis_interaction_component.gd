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


## 仅查询当前请求能否分发，不产生物体效果。
func can_interact(actor: Node3D) -> bool:
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
