class_name AutolysisPackingCapsulePlace
extends StaticBody3D
## 胶囊位接受空胶囊及已封装胶囊；完整打开舱门后才能取放。

@export var capsule_anchor: Node3D
@export var transfer_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D

var machine: AutolysisPackingMachine
var focus_target: AutolysisFocusTarget
var _configured: bool = false
var _transfer_busy: bool = false
var _stored_item: AutolysisPneumaticCapsule


func _ready() -> void:
	if is_instance_valid(transfer_interaction):
		transfer_interaction.is_enabled = false


func configure(owner_machine: AutolysisPackingMachine, target: AutolysisFocusTarget) -> bool:
	if _configured:
		return false
	machine = owner_machine
	focus_target = target
	if not get_configuration_error().is_empty():
		return false
	transfer_interaction.set_availability_check(_can_transfer_interact)
	transfer_interaction.set_execution_handler(_on_transfer_requested)
	_configured = true
	return true


func get_configuration_error() -> String:
	if not _node_is_live(self) or not _node_is_live(machine) or not machine.is_ancestor_of(self):
		return "胶囊位必须归属于有效封装器"
	if not _node_is_live(focus_target) or not machine.is_ancestor_of(focus_target):
		return "胶囊位与聚焦描述必须属于同一封装器"
	if not _node_is_live(capsule_anchor) or not is_ancestor_of(capsule_anchor):
		return "胶囊锚点必须归属于本胶囊位"
	if not _node_is_live(collision_shape) or collision_shape.get_parent() != self or collision_shape.shape == null or collision_shape.disabled:
		return "胶囊位直属碰撞无效"
	if not _node_is_live(transfer_interaction) or transfer_interaction.get_parent() != self or transfer_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "胶囊位直属直接交互组件无效"
	var count: int = 0
	for child: Node in get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	if count != 1:
		return "胶囊位必须恰好配置一个交互组件"
	if _configured and not transfer_interaction.has_execution_handler(_on_transfer_requested):
		return "胶囊位缺少自身业务执行绑定"
	for child: Node in capsule_anchor.get_children():
		if child is AutolysisPneumaticCapsule and not child.is_queued_for_deletion() and child != _stored_item:
			return "胶囊锚点存在未登记胶囊"
	if is_instance_valid(_stored_item) and not owns_item(_stored_item):
		return "已登记胶囊归属失效"
	return ""


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func is_transfer_busy() -> bool:
	return _transfer_busy


func can_transfer(actor: Node3D, allow_busy: bool = false) -> bool:
	return is_configured() and not machine.is_interaction_locked() and machine.door.is_open() and (allow_busy or not _transfer_busy) and machine.is_actor_focused(actor) and focus_target.get_packing_capsule_place_for_target(self) == self


func try_begin_transfer(actor: Node3D) -> bool:
	if not can_transfer(actor):
		return false
	_transfer_busy = true
	return true


func end_transfer() -> void:
	_transfer_busy = false


func get_stored_item() -> AutolysisPneumaticCapsule:
	return _stored_item if _node_is_live(_stored_item) else null


func owns_item(item: AutolysisPneumaticCapsule) -> bool:
	return _node_is_live(item) and _node_is_live(capsule_anchor) and _stored_item == item and item.packing_stored and item.packing_place == self and item.get_parent() == capsule_anchor


func try_attach_prepared_item(item: AutolysisPneumaticCapsule) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or not machine.door.is_open() or get_stored_item() != null:
		return false
	if not is_instance_valid(item) or item.is_queued_for_deletion() or item.get_parent() != null or not item.packing_stored or item.packing_place != self or not _has_valid_instance(item):
		return false
	var anchor: Node3D = capsule_anchor
	anchor.add_child(item)
	if not _node_is_live(self) or not _node_is_live(machine) or machine.is_interaction_locked() or not _transfer_busy or not machine.door.is_open() or get_stored_item() != null:
		return false
	if not _node_is_live(item) or not _node_is_live(anchor) or capsule_anchor != anchor or item.get_parent() != anchor or not item.packing_stored or item.packing_place != self or not _has_valid_instance(item):
		return false
	item.transform = Transform3D.IDENTITY
	_stored_item = item
	if not is_configured():
		_stored_item = null
		return false
	return true


func release_item(item: AutolysisPneumaticCapsule) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or not machine.door.is_open() or not owns_item(item):
		return false
	_stored_item = null
	item.packing_place = null
	return true


func rollback_prepared_item(item: Variant) -> void:
	if is_instance_valid(machine) and machine.is_batch_running() and _stored_item == item:
		return
	if _stored_item == item:
		_stored_item = null
	if is_instance_valid(item) and item is AutolysisPneumaticCapsule and item.packing_place == self:
		item.packing_place = null


func _has_valid_instance(item: AutolysisPneumaticCapsule) -> bool:
	return is_instance_valid(item.item_instance) and item.item_instance.is_valid_instance() and item.item_instance.is_pneumatic_capsule() and item.item_definition == item.item_instance.definition


func _can_transfer_interact(actor: Node3D) -> bool:
	if not _node_is_live(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return _node_is_live(inventory) and (inventory.can_place_in_packing_capsule_place(actor, self) or inventory.can_take_from_packing_capsule_place(actor, self))


func _on_transfer_requested(actor: Node3D) -> void:
	if not _node_is_live(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if not _node_is_live(inventory):
		return
	if inventory.can_place_in_packing_capsule_place(actor, self):
		inventory.try_place_in_packing_capsule_place(actor, self)
	elif inventory.can_take_from_packing_capsule_place(actor, self):
		inventory.try_take_from_packing_capsule_place(actor, self)


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
