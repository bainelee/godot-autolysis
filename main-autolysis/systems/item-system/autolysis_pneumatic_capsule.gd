class_name AutolysisPneumaticCapsule
extends StaticBody3D
## 胶囊在转移中保留逐件实例；机器存储来源失效时禁止退回普通拾取。

@export var item_definition: AutolysisItemDefinition

var item_instance: AutolysisItemInstance
var packing_place: AutolysisPackingCapsulePlace
var packing_stored: bool = false
var _pickup_finished: bool = false

@onready var _interaction: AutolysisInteractionComponent = get_node_or_null("InteractionComponent") as AutolysisInteractionComponent


func _ready() -> void:
	if item_instance == null:
		item_instance = AutolysisItemInstance.create(item_definition)
	if not _has_valid_instance() or not AutolysisPneumaticCapsuleVisual.apply_instance(self, item_instance):
		_disable_world_pickup()
		push_error("气动胶囊实例或显示依赖无效：%s" % get_path())
		return
	if not item_instance.changed.is_connected(_on_instance_changed):
		item_instance.changed.connect(_on_instance_changed)
	if not is_instance_valid(_interaction):
		push_error("气动胶囊缺少直接子交互组件：%s" % get_path())
		return
	_interaction.set_availability_check(_can_interact)
	_interaction.interaction_requested.connect(_on_interaction_requested)
	if packing_stored:
		_disable_world_pickup()


func bind_item_instance(instance: AutolysisItemInstance) -> bool:
	if is_inside_tree() or _pickup_finished or not is_instance_valid(instance) or not instance.is_valid_instance() or not instance.is_pneumatic_capsule():
		return false
	if not is_instance_valid(item_definition) or item_definition.item_id != instance.definition.item_id:
		return false
	item_definition = instance.definition
	item_instance = instance
	return AutolysisPneumaticCapsuleVisual.apply_instance(self, item_instance)


func is_empty() -> bool:
	return _has_valid_instance() and item_instance.is_empty_pneumatic_capsule()


func can_apply_contents(contents: AutolysisPackingContents) -> bool:
	return not _pickup_finished and _has_valid_instance() and is_empty() and is_instance_valid(contents) and contents.is_valid_contents() and AutolysisPneumaticCapsuleVisual.can_apply(self)


func apply_contents(contents: AutolysisPackingContents, notify: bool = true) -> bool:
	if not can_apply_contents(contents) or not item_instance.set_packing_contents(contents, false):
		return false
	AutolysisPneumaticCapsuleVisual.apply_instance(self, item_instance)
	if notify:
		notify_contents_changed()
	return true


func notify_contents_changed() -> void:
	if _has_valid_instance():
		item_instance.emit_changed()


func prepare_packing_storage(place: AutolysisPackingCapsulePlace) -> bool:
	if not is_instance_valid(place) or place.is_queued_for_deletion() or not _has_valid_instance():
		return false
	if is_inside_tree() or get_parent() != null or _pickup_finished or packing_stored or is_instance_valid(packing_place):
		return false
	packing_place = place
	packing_stored = true
	_disable_world_pickup()
	return true


func is_available_for_pickup() -> bool:
	if packing_stored or is_instance_valid(packing_place) or _pickup_finished or not is_inside_tree() or is_queued_for_deletion():
		return false
	return is_instance_valid(_interaction) and _interaction.is_enabled and is_in_group(&"interactable") and _has_valid_instance()


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
	if is_instance_valid(self) and not is_queued_for_deletion():
		queue_free()


func _has_valid_instance() -> bool:
	return is_instance_valid(item_instance) and item_instance.is_valid_instance() and item_instance.definition == item_definition and item_instance.is_pneumatic_capsule()


func _on_instance_changed() -> void:
	if not _pickup_finished and _has_valid_instance():
		AutolysisPneumaticCapsuleVisual.apply_instance(self, item_instance)


func _disable_world_pickup() -> void:
	var component: AutolysisInteractionComponent = get_node_or_null("InteractionComponent") as AutolysisInteractionComponent
	if is_instance_valid(component):
		component.is_enabled = false
	remove_from_group(&"interactable")
	if packing_stored:
		# 只保留玩家阻挡层，机器槽位碰撞负责聚焦命中。
		collision_layer = 8
		collision_mask = 0


func _can_interact(actor: Node3D) -> bool:
	if not is_instance_valid(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and inventory.can_take_pneumatic_capsule(actor, self)


func _on_interaction_requested(actor: Node3D) -> void:
	if not is_instance_valid(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if is_instance_valid(inventory):
		inventory.try_take_pneumatic_capsule(actor, self)
