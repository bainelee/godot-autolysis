class_name AutolysisPneumaticCapsuleShelf
extends StaticBody3D
## 空手领取新的独立空胶囊；纯显示陈列物始终保持不变。

@export var item_definition: AutolysisItemDefinition

@onready var _interaction: AutolysisInteractionComponent = $InteractionComponent


func _ready() -> void:
	_interaction.set_availability_check(_can_interact)
	_interaction.interaction_requested.connect(_on_interaction_requested)


func _can_interact(actor: Node3D) -> bool:
	if not is_instance_valid(actor) or not _is_capsule_definition():
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and inventory.can_receive_item(item_definition)


func _on_interaction_requested(actor: Node3D) -> void:
	if not _can_interact(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(item_definition)
	if instance != null and instance.is_empty_pneumatic_capsule():
		inventory.try_receive_instance(instance)


func _is_capsule_definition() -> bool:
	return is_instance_valid(item_definition) and item_definition.is_valid_definition() and item_definition.item_id == &"pneumatic_capsule" and not item_definition.is_raw_material
