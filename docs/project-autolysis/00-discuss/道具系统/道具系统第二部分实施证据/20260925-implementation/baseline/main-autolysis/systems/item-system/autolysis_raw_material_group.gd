class_name AutolysisRawMaterialGroup
extends StaticBody3D
## 原药组无限提供对应原药；内部陈列始终保持不变。

@export var item_definition: AutolysisItemDefinition

@onready var _interaction: AutolysisInteractionComponent = $InteractionComponent


func _ready() -> void:
	_interaction.set_availability_check(_can_interact)
	if not _interaction.interaction_requested.is_connected(_on_interaction_requested):
		_interaction.interaction_requested.connect(_on_interaction_requested)


func _can_interact(actor: Node3D) -> bool:
	if not is_instance_valid(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and inventory.can_receive_item(item_definition)


func _on_interaction_requested(actor: Node3D) -> void:
	if not is_instance_valid(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if is_instance_valid(inventory):
		inventory.try_receive_item(item_definition)
