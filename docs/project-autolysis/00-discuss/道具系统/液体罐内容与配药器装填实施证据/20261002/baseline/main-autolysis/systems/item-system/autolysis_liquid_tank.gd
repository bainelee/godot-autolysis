class_name AutolysisLiquidTank
extends StaticBody3D
## 世界罐保留来源标记；所属柜失效不能退回无主拾取。

@export var item_definition: AutolysisItemDefinition
@export var fixed_installation: bool = false

var cabinet: AutolysisLiquidTankCabinet
var slot_index: int = -1
var cabinet_stored: bool = false
var _pickup_finished: bool = false

@onready var _interaction: AutolysisInteractionComponent = get_node_or_null("InteractionComponent") as AutolysisInteractionComponent


func _ready() -> void:
	if not is_instance_valid(_interaction):
		push_error("液体罐缺少直接子交互组件：%s" % get_path())
		return
	_interaction.set_availability_check(_can_interact)
	_interaction.interaction_requested.connect(_on_interaction_requested)
	if fixed_installation:
		_interaction.is_enabled = false
		remove_from_group(&"interactable")


func is_available_for_pickup() -> bool:
	if fixed_installation or _pickup_finished or not is_inside_tree() or is_queued_for_deletion():
		return false
	if not is_instance_valid(_interaction) or not _interaction.is_enabled or not is_in_group(&"interactable"):
		return false
	if not is_instance_valid(item_definition) or not item_definition.is_valid_definition() or item_definition.is_raw_material or item_definition.item_id != &"liquid_tank":
		return false
	if cabinet_stored:
		return is_instance_valid(cabinet) and cabinet.is_open() and cabinet.owns_item(self)
	return not is_instance_valid(cabinet) and slot_index == -1


## 候选必须在入树前绑定柜来源，防止初始化回调绕过门禁。
func prepare_cabinet_storage(owner_cabinet: AutolysisLiquidTankCabinet, index: int) -> bool:
	if not is_instance_valid(owner_cabinet) or owner_cabinet.is_queued_for_deletion() or index < 0 or index >= 2:
		return false
	if is_inside_tree() or get_parent() != null or fixed_installation or _pickup_finished or cabinet_stored:
		return false
	if is_instance_valid(cabinet) or slot_index != -1:
		return false
	cabinet = owner_cabinet
	slot_index = index
	cabinet_stored = true
	return true


## 提交后立即隐藏并移出检测，延迟释放不得产生第二次拾取。
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
	return is_instance_valid(inventory) and inventory.can_take_liquid_tank(actor, self)


func _on_interaction_requested(actor: Node3D) -> void:
	if not is_instance_valid(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if is_instance_valid(inventory):
		inventory.try_take_liquid_tank(actor, self)
