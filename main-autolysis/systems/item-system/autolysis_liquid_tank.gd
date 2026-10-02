class_name AutolysisLiquidTank
extends StaticBody3D
## 世界罐保留来源标记；所属柜失效不能退回无主拾取。

@export var item_definition: AutolysisItemDefinition
@export var fixed_installation: bool = false

var item_instance: AutolysisItemInstance
var cabinet: AutolysisLiquidTankCabinet
var slot_index: int = -1
var cabinet_stored: bool = false
var blend_place: AutolysisBlendTankPlace
var blend_stored: bool = false
var _pickup_finished: bool = false

@onready var _interaction: AutolysisInteractionComponent = get_node_or_null("InteractionComponent") as AutolysisInteractionComponent


func _ready() -> void:
	if item_instance == null:
		item_instance = AutolysisItemInstance.create(item_definition)
	if not _has_valid_instance() or not AutolysisLiquidTankVisual.apply_instance(self, item_instance):
		_disable_world_pickup()
		push_error("液体罐实例或显示依赖无效：%s" % get_path())
		return
	if not item_instance.changed.is_connected(_on_instance_changed):
		item_instance.changed.connect(_on_instance_changed)
	if not is_instance_valid(_interaction):
		push_error("液体罐缺少直接子交互组件：%s" % get_path())
		return
	_interaction.set_availability_check(_can_interact)
	_interaction.interaction_requested.connect(_on_interaction_requested)
	if fixed_installation or blend_stored:
		_disable_world_pickup()


func bind_item_instance(instance: AutolysisItemInstance) -> bool:
	if is_inside_tree() or _pickup_finished or not is_instance_valid(instance) or not instance.is_valid_instance() or not instance.is_liquid_tank():
		return false
	if not is_instance_valid(item_definition) or item_definition.item_id != instance.definition.item_id:
		return false
	item_definition = instance.definition
	item_instance = instance
	return AutolysisLiquidTankVisual.apply_instance(self, item_instance)


func is_empty() -> bool:
	return _has_valid_instance() and item_instance.is_empty_liquid_tank()


func can_apply_contents(contents: AutolysisLiquidContents) -> bool:
	return not _pickup_finished and _has_valid_instance() and is_empty() and is_instance_valid(contents) and contents.is_valid_contents() and AutolysisLiquidTankVisual.can_apply(self)


func apply_contents(contents: AutolysisLiquidContents, notify: bool = true) -> bool:
	if not can_apply_contents(contents):
		return false
	if not item_instance.set_liquid_contents(contents, false):
		return false
	AutolysisLiquidTankVisual.apply_instance(self, item_instance)
	if notify:
		notify_contents_changed()
	return true


func notify_contents_changed() -> void:
	if _has_valid_instance():
		item_instance.emit_changed()


func _has_valid_instance() -> bool:
	return is_instance_valid(item_instance) and item_instance.is_valid_instance() and item_instance.definition == item_definition and item_instance.is_liquid_tank()


func _on_instance_changed() -> void:
	if not _pickup_finished and _has_valid_instance():
		AutolysisLiquidTankVisual.apply_instance(self, item_instance)


func _disable_world_pickup() -> void:
	var component: AutolysisInteractionComponent = get_node_or_null("InteractionComponent") as AutolysisInteractionComponent
	if is_instance_valid(component):
		component.is_enabled = false
	remove_from_group(&"interactable")
	if blend_stored:
		# 只保留玩家阻挡层，罐位碰撞继续承担聚焦命中。
		collision_layer = 8
		collision_mask = 0


func is_available_for_pickup() -> bool:
	if fixed_installation or blend_stored or is_instance_valid(blend_place) or _pickup_finished or not is_inside_tree() or is_queued_for_deletion():
		return false
	if not is_instance_valid(_interaction) or not _interaction.is_enabled or not is_in_group(&"interactable"):
		return false
	if not _has_valid_instance():
		return false
	if cabinet_stored:
		return is_instance_valid(cabinet) and cabinet.is_open() and cabinet.owns_item(self)
	return not is_instance_valid(cabinet) and slot_index == -1


## 候选必须在入树前绑定柜来源，防止初始化回调绕过门禁。
func prepare_cabinet_storage(owner_cabinet: AutolysisLiquidTankCabinet, index: int) -> bool:
	if not is_instance_valid(owner_cabinet) or owner_cabinet.is_queued_for_deletion() or index < 0 or index >= 2:
		return false
	if is_inside_tree() or get_parent() != null or fixed_installation or _pickup_finished or cabinet_stored or blend_stored or is_instance_valid(blend_place):
		return false
	if is_instance_valid(cabinet) or slot_index != -1:
		return false
	cabinet = owner_cabinet
	slot_index = index
	cabinet_stored = true
	return true


func prepare_blend_storage(place: AutolysisBlendTankPlace) -> bool:
	if not is_instance_valid(place) or place.is_queued_for_deletion() or not is_empty():
		return false
	if is_inside_tree() or get_parent() != null or fixed_installation or _pickup_finished or cabinet_stored or blend_stored:
		return false
	if is_instance_valid(cabinet) or is_instance_valid(blend_place) or slot_index != -1:
		return false
	blend_place = place
	blend_stored = true
	_disable_world_pickup()
	return true


## 提交后立即隐藏并移出检测，延迟释放不得产生第二次拾取。
func finish_pickup() -> void:
	if _pickup_finished:
		return
	_pickup_finished = true
	if is_instance_valid(_interaction):
		_interaction.is_enabled = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group(&"interactable")
	hide()
	# 可见性通知可能同步释放来源，后续禁止访问失效节点。
	if is_instance_valid(self) and not is_queued_for_deletion():
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
