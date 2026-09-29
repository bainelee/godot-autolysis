class_name AutolysisRawMaterial
extends StaticBody3D
## 可独立拾取的世界原药；道具转移由玩家控制器提交。

@export var item_definition: AutolysisItemDefinition

var shelf: AutolysisRawMaterialShelf
var slot_index: int = -1
var device_stored: bool = false
var blend_slot: AutolysisBlendSlot
var _pickup_finished: bool = false

@onready var _interaction: AutolysisInteractionComponent = $InteractionComponent


func _ready() -> void:
	if device_stored:
		_disable_world_pickup()
	_interaction.set_availability_check(_can_interact)
	if not _interaction.interaction_requested.is_connected(_on_interaction_requested):
		_interaction.interaction_requested.connect(_on_interaction_requested)


func is_available_for_pickup() -> bool:
	return not device_stored and not _pickup_finished and is_inside_tree() and not is_queued_for_deletion()


## 必须先关闭世界拾取再入树；设备失效后此标记仍然保留。
func prepare_device_storage(slot: AutolysisBlendSlot) -> bool:
	if not is_instance_valid(slot) or slot.is_queued_for_deletion() or _pickup_finished:
		return false
	if is_inside_tree() or get_parent() != null or device_stored or is_instance_valid(blend_slot):
		return false
	if is_instance_valid(shelf) or slot_index != -1:
		return false
	device_stored = true
	blend_slot = slot
	_disable_world_pickup()
	return true


func _disable_world_pickup() -> void:
	var component: AutolysisInteractionComponent = get_node_or_null("InteractionComponent") as AutolysisInteractionComponent
	if component != null:
		component.is_enabled = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group(&"interactable")


## 成功转移后立即从画面和射线中移除，延迟释放不能导致重复拾取。
func finish_pickup() -> void:
	if _pickup_finished:
		return
	_pickup_finished = true
	if is_instance_valid(_interaction):
		_interaction.is_enabled = false
	hide()
	collision_layer = 0
	collision_mask = 0
	remove_from_group(&"interactable")
	queue_free()


func _can_interact(actor: Node3D) -> bool:
	if not is_instance_valid(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and inventory.can_take_world_item(self)


func _on_interaction_requested(actor: Node3D) -> void:
	if not is_instance_valid(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if is_instance_valid(inventory):
		inventory.try_take_world_item(self)
