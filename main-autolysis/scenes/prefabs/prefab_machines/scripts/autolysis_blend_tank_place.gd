class_name AutolysisBlendTankPlace
extends StaticBody3D
## 单罐位负责归属与事务；道具栏提交仍由玩家库存控制器执行。

signal state_changed

@export var liquid_tank_anchor: Node3D
@export var transfer_interaction: AutolysisInteractionComponent
@export var collision_shape: CollisionShape3D

var machine: AutolysisBlendMachine
var focus_target: AutolysisFocusTarget

var _configured: bool = false
var _transfer_busy: bool = false
var _stored_item: AutolysisLiquidTank


func _ready() -> void:
	if is_instance_valid(transfer_interaction):
		transfer_interaction.is_enabled = false


func configure(owner_machine: AutolysisBlendMachine, target: AutolysisFocusTarget) -> bool:
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


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


func get_configuration_error() -> String:
	if not _node_is_live(self) or not _node_is_live(machine) or not machine.is_ancestor_of(self):
		return "液体罐放置位必须属于有效配药器"
	if not _node_is_live(focus_target) or not machine.is_ancestor_of(focus_target):
		return "液体罐放置位与聚焦描述必须属于同一配药器"
	if not _node_is_live(liquid_tank_anchor) or not is_ancestor_of(liquid_tank_anchor):
		return "liquid_tank_anchor（罐锚点）必须属于本放置位子树"
	if not _node_is_live(collision_shape) or collision_shape.get_parent() != self or collision_shape.shape == null or collision_shape.disabled:
		return "collision_shape（碰撞形状）必须属于本放置位直接子级且有效"
	if not _node_is_live(transfer_interaction) or transfer_interaction.get_parent() != self:
		return "transfer_interaction（取放交互组件）必须属于本放置位直接子级"
	if transfer_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "液体罐取放组件必须使用直接动作模式"
	var component_count: int = 0
	for child: Node in get_children():
		if child is AutolysisInteractionComponent:
			component_count += 1
	if component_count != 1:
		return "液体罐放置位必须恰好配置一个交互组件"
	if _configured and not transfer_interaction.has_execution_handler(_on_transfer_requested):
		return "液体罐取放组件的业务执行绑定失效"
	for child: Node in liquid_tank_anchor.get_children():
		if child is AutolysisLiquidTank and not child.is_queued_for_deletion() and child != _stored_item:
			return "液体罐锚点存在未登记罐，保留来源并关闭入口"
	if is_instance_valid(_stored_item) and not owns_item(_stored_item):
		return "已登记液体罐的来源或锚点归属失效"
	return ""


func is_transfer_busy() -> bool:
	return _transfer_busy


func can_transfer(actor: Node3D, allow_busy: bool = false) -> bool:
	return is_configured() and not machine.is_interaction_locked() and (allow_busy or not _transfer_busy) and _actor_is_focused(actor)


func try_begin_transfer(actor: Node3D) -> bool:
	if not can_transfer(actor):
		return false
	_transfer_busy = true
	_emit_state_changed.call_deferred()
	return true


func end_transfer() -> void:
	if not _transfer_busy:
		return
	_transfer_busy = false
	_emit_state_changed.call_deferred()


func get_stored_item() -> AutolysisLiquidTank:
	return _stored_item if _node_is_live(_stored_item) else null


func owns_item(item: AutolysisLiquidTank) -> bool:
	return _node_is_live(item) and _node_is_live(liquid_tank_anchor) and _stored_item == item and item.blend_stored and item.blend_place == self and not item.cabinet_stored and not is_instance_valid(item.cabinet) and item.slot_index == -1 and item.get_parent() == liquid_tank_anchor


func try_attach_prepared_item(item: AutolysisLiquidTank) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or get_stored_item() != null:
		return false
	if not is_instance_valid(item) or item.is_queued_for_deletion() or item.get_parent() != null or not item.is_empty():
		return false
	if not item.blend_stored or item.blend_place != self or item.cabinet_stored or is_instance_valid(item.cabinet) or item.slot_index != -1:
		return false
	var anchor: Node3D = liquid_tank_anchor
	anchor.add_child(item)
	# 入树回调后重新核验；此时候选未登记，不能调用包含占用检查的完整配置查询。
	if not _node_is_live(self) or not _node_is_live(machine) or machine.is_interaction_locked() or not _transfer_busy or get_stored_item() != null:
		return false
	if not _node_is_live(item) or not _node_is_live(anchor) or liquid_tank_anchor != anchor or item.get_parent() != anchor or not item.is_empty():
		return false
	if not item.blend_stored or item.blend_place != self or item.cabinet_stored or is_instance_valid(item.cabinet) or item.slot_index != -1:
		return false
	item.transform = Transform3D.IDENTITY
	_stored_item = item
	if not is_configured():
		_stored_item = null
		return false
	_emit_state_changed.call_deferred()
	return true


func release_item(item: AutolysisLiquidTank) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or not owns_item(item):
		return false
	_stored_item = null
	item.blend_place = null
	_emit_state_changed.call_deferred()
	return true


func rollback_prepared_item(item: Variant) -> void:
	if is_instance_valid(machine) and (machine.is_batch_running() or not machine.get_processing_fault().is_empty()) and _stored_item == item:
		return
	var occupancy_changed: bool = false
	if _stored_item == item:
		_stored_item = null
		occupancy_changed = true
	if is_instance_valid(item) and item is AutolysisLiquidTank and item.blend_place == self:
		item.blend_place = null
		occupancy_changed = true
	if occupancy_changed:
		_emit_state_changed.call_deferred()


## 延后外部通知，库存取放调用栈完成前不新增同步回调。
func _emit_state_changed() -> void:
	if not _node_is_live(self):
		return
	state_changed.emit()


func _actor_is_focused(actor: Node3D) -> bool:
	if not _node_is_live(actor) or not actor is AutolysisPlayer or not focus_target.is_valid_target():
		return false
	if focus_target.get_tank_place_for_target(self) != self:
		return false
	var player: AutolysisPlayer = actor as AutolysisPlayer
	return player.is_focus_business_allowed() and _node_is_live(player.focus_controller) and player.focus_controller.is_focused_on(focus_target)


func _can_transfer_interact(actor: Node3D) -> bool:
	if not _node_is_live(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and (inventory.can_place_in_blend_tank_place(actor, self) or inventory.can_take_from_blend_tank_place(actor, self))


func _on_transfer_requested(actor: Node3D) -> void:
	if not _node_is_live(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if not is_instance_valid(inventory):
		return
	if inventory.can_place_in_blend_tank_place(actor, self):
		inventory.try_place_in_blend_tank_place(actor, self)
	elif inventory.can_take_from_blend_tank_place(actor, self):
		inventory.try_take_from_blend_tank_place(actor, self)


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
