class_name AutolysisPackingTankPlace
extends StaticBody3D
## 封装器罐位只判断液体罐种类，空满许可不与配药器共用。

@export var liquid_tank_anchor: Node3D
@export var transfer_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D

var machine: AutolysisPackingMachine
var focus_target: AutolysisFocusTarget
var _configured: bool = false
var _transfer_busy: bool = false
var _stored_item: AutolysisLiquidTank


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
	transfer_interaction.interaction_requested.connect(_on_transfer_requested)
	_configured = true
	return true


func get_configuration_error() -> String:
	if not _node_is_live(self) or not _node_is_live(machine) or get_parent() != machine:
		return "液体罐位必须属于有效封装器直接子级"
	if not _node_is_live(focus_target) or focus_target.get_parent() != machine:
		return "液体罐位与聚焦描述必须属于同一封装器"
	if not _node_is_live(liquid_tank_anchor) or liquid_tank_anchor.get_parent() != self:
		return "罐锚点必须属于本罐位直接子级"
	if not _node_is_live(collision_shape) or collision_shape.get_parent() != self or collision_shape.shape == null or collision_shape.disabled:
		return "液体罐位直属碰撞无效"
	if not _node_is_live(transfer_interaction) or transfer_interaction.get_parent() != self or transfer_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "液体罐位直属直接交互组件无效"
	var count: int = 0
	for child: Node in get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	if count != 1:
		return "液体罐位必须恰好配置一个交互组件"
	var receivers: Array[Dictionary] = []
	receivers.assign(transfer_interaction.interaction_requested.get_connections())
	if not _configured and not receivers.is_empty():
		return "液体罐位初始化前不得连接其他接收者"
	if _configured and (receivers.size() != 1 or receivers[0]["callable"] != _on_transfer_requested or receivers[0]["flags"] != 0):
		return "液体罐位必须只同步连接自身请求方法"
	for child: Node in liquid_tank_anchor.get_children():
		if child is AutolysisLiquidTank and not child.is_queued_for_deletion() and child != _stored_item:
			return "罐锚点存在未登记液体罐"
	if is_instance_valid(_stored_item) and not owns_item(_stored_item):
		return "已登记液体罐归属失效"
	return ""


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func is_transfer_busy() -> bool:
	return _transfer_busy


func can_transfer(actor: Node3D, allow_busy: bool = false) -> bool:
	return is_configured() and not machine.is_interaction_locked() and (allow_busy or not _transfer_busy) and machine.is_actor_focused(actor) and focus_target.get_packing_tank_place_for_target(self) == self


func try_begin_transfer(actor: Node3D) -> bool:
	if not can_transfer(actor):
		return false
	_transfer_busy = true
	return true


func end_transfer() -> void:
	_transfer_busy = false


func get_stored_item() -> AutolysisLiquidTank:
	return _stored_item if _node_is_live(_stored_item) else null


func owns_item(item: AutolysisLiquidTank) -> bool:
	return _node_is_live(item) and _node_is_live(liquid_tank_anchor) and _stored_item == item and item.packing_stored and item.packing_place == self and not item.blend_stored and not is_instance_valid(item.blend_place) and not item.cabinet_stored and not is_instance_valid(item.cabinet) and item.slot_index == -1 and not item.fixed_installation and item.get_parent() == liquid_tank_anchor


func try_attach_prepared_item(item: AutolysisLiquidTank) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or get_stored_item() != null:
		return false
	if not is_instance_valid(item) or item.is_queued_for_deletion() or item.get_parent() != null or not _has_valid_instance(item):
		return false
	if not item.packing_stored or item.packing_place != self or item.blend_stored or is_instance_valid(item.blend_place) or item.cabinet_stored or is_instance_valid(item.cabinet) or item.slot_index != -1 or item.fixed_installation:
		return false
	var anchor: Node3D = liquid_tank_anchor
	anchor.add_child(item)
	# 入树边界后候选尚未登记，使用独立来源检查，避免把候选误判为已有占用。
	if not _node_is_live(self) or not _node_is_live(machine) or machine.is_interaction_locked() or not _transfer_busy or get_stored_item() != null:
		return false
	if not _node_is_live(item) or not _node_is_live(anchor) or liquid_tank_anchor != anchor or item.get_parent() != anchor or not _has_valid_instance(item):
		return false
	if not item.packing_stored or item.packing_place != self or item.blend_stored or is_instance_valid(item.blend_place) or item.cabinet_stored or is_instance_valid(item.cabinet) or item.slot_index != -1 or item.fixed_installation:
		return false
	item.transform = Transform3D.IDENTITY
	_stored_item = item
	if not is_configured():
		_stored_item = null
		return false
	return true


func release_item(item: AutolysisLiquidTank) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or not owns_item(item):
		return false
	_stored_item = null
	item.packing_place = null
	return true


func rollback_prepared_item(item: Variant) -> void:
	if is_instance_valid(machine) and machine.is_batch_running() and _stored_item == item:
		return
	if _stored_item == item:
		_stored_item = null
	if is_instance_valid(item) and item is AutolysisLiquidTank and item.packing_place == self:
		item.packing_place = null


func _has_valid_instance(item: AutolysisLiquidTank) -> bool:
	return is_instance_valid(item.item_instance) and item.item_instance.is_valid_instance() and item.item_instance.is_liquid_tank() and item.item_definition == item.item_instance.definition


func _can_transfer_interact(actor: Node3D) -> bool:
	if not _node_is_live(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return _node_is_live(inventory) and (inventory.can_place_in_packing_tank_place(actor, self) or inventory.can_take_from_packing_tank_place(actor, self))


func _on_transfer_requested(actor: Node3D) -> void:
	if not _node_is_live(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if not _node_is_live(inventory):
		return
	if inventory.can_place_in_packing_tank_place(actor, self):
		inventory.try_place_in_packing_tank_place(actor, self)
	elif inventory.can_take_from_packing_tank_place(actor, self):
		inventory.try_take_from_packing_tank_place(actor, self)


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
