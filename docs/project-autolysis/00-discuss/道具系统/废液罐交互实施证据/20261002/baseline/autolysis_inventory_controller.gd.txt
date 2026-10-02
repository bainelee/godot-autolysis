class_name AutolysisInventoryController
extends Node
## 四格状态与道具转移的唯一写入入口；通知发出前各处占用已经一致。

signal inventory_changed()

const SLOT_COUNT: int = 4
const LIQUID_TANK_ID: StringName = &"liquid_tank"
const NEXT_ACTION: StringName = &"inventory_next"
const PREVIOUS_ACTION: StringName = &"inventory_previous"

var _slots: Array[AutolysisItemInstance] = []
var _focused_index: int = 0
var _busy: bool = false
var _publishing: bool = false
var _presenter: AutolysisHeldItemPresenter
var _input_allowed: Callable


func _init() -> void:
	_slots.resize(SLOT_COUNT)


func configure(presenter: AutolysisHeldItemPresenter, input_allowed: Callable) -> void:
	_presenter = presenter
	_input_allowed = input_allowed


func get_slot_item(index: int) -> AutolysisItemDefinition:
	var instance: AutolysisItemInstance = get_slot_instance(index)
	return null if instance == null else instance.definition


func get_slot_instance(index: int) -> AutolysisItemInstance:
	if index < 0 or index >= SLOT_COUNT:
		return null
	return _slots[index]


func get_focused_index() -> int:
	return _focused_index


func get_focused_item() -> AutolysisItemDefinition:
	return get_slot_item(_focused_index)


func get_focused_instance() -> AutolysisItemInstance:
	return _slots[_focused_index]


func cycle_focus(direction: int) -> bool:
	if _busy or not _dependencies_valid() or (direction != -1 and direction != 1):
		return false
	_busy = true
	var next_index: int = posmod(_focused_index + direction, SLOT_COUNT)
	var item: AutolysisItemInstance = _slots[next_index]
	var visual: Node3D = _prepare_visual(item)
	if item != null and visual == null:
		_busy = false
		return false
	_focused_index = next_index
	_commit_visual(visual)
	_publish_change()
	return true


func can_receive_item(item: AutolysisItemDefinition) -> bool:
	return (not _busy or _publishing) and _dependencies_valid() and get_focused_instance() == null and item != null and item.is_valid_definition()


func try_receive_item(item: AutolysisItemDefinition) -> bool:
	if _busy or not can_receive_item(item):
		return false
	return try_receive_instance(AutolysisItemInstance.create(item))


func can_receive_instance(instance: AutolysisItemInstance) -> bool:
	return is_instance_valid(instance) and instance.is_valid_instance() and not _slots.has(instance) and can_receive_item(instance.definition)


func try_receive_instance(instance: AutolysisItemInstance) -> bool:
	if _busy or not can_receive_instance(instance):
		return false
	_busy = true
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_busy = false
		return false
	_slots[_focused_index] = instance
	_commit_visual(visual)
	_publish_change()
	return true


func can_take_world_item(item: AutolysisRawMaterial) -> bool:
	if not _node_is_live(item) or item.device_stored or is_instance_valid(item.blend_slot) or not item.is_available_for_pickup():
		return false
	if not can_receive_instance(item.item_instance):
		return false
	if item.shelf != null:
		return _node_is_live(item.shelf) and item.shelf.owns_item(item)
	return item.slot_index == -1


func try_take_world_item(item: AutolysisRawMaterial) -> bool:
	if _busy or not can_take_world_item(item):
		return false
	_busy = true
	var instance: AutolysisItemInstance = item.item_instance
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_busy = false
		return false
	# 模型准备期间不提交任何占用；准备完成后再次核对来源。
	if not _node_is_live(item) or item.item_instance != instance or item.device_stored or is_instance_valid(item.blend_slot) or not item.is_available_for_pickup():
		visual.free()
		_busy = false
		return false
	if item.shelf != null:
		if not _node_is_live(item.shelf) or not item.shelf.release_item(item):
			visual.free()
			_busy = false
			return false
	_slots[_focused_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	_publish_change()
	return true


func can_place_on_shelf(shelf: AutolysisRawMaterialShelf) -> bool:
	if (_busy and not _publishing) or not _dependencies_valid() or not _node_is_live(shelf):
		return false
	var item: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	return instance != null and instance.is_valid_instance() and item.is_raw_material and shelf.can_accept_item(item) and _get_world_scene(item) != null


func try_place_on_shelf(shelf: AutolysisRawMaterialShelf) -> bool:
	if _busy or not can_place_on_shelf(shelf):
		return false
	_busy = true
	var original_index: int = _focused_index
	var instance: AutolysisItemInstance = get_focused_instance()
	var slot: int = shelf.find_first_empty_slot()
	var candidate: AutolysisRawMaterial = _prepare_world_item(instance)
	if candidate == null:
		_busy = false
		return false
	if not _node_is_live(shelf) or _focused_index != original_index or get_focused_instance() != instance:
		candidate.free()
		_busy = false
		return false
	if not shelf.try_attach_item(slot, candidate):
		if is_instance_valid(candidate):
			candidate.free()
		_busy = false
		return false
	_slots[original_index] = null
	_commit_visual(null)
	_publish_change()
	return true


func can_place_in_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if not _can_query_blend_slot(actor, slot):
		return false
	var definition: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	return slot.get_stored_item() == null and instance != null and instance.is_valid_instance() and definition.is_raw_material and _get_world_scene(definition) != null


func try_place_in_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if _busy or not can_place_in_blend_slot(actor, slot):
		return false
	var original_index: int = _focused_index
	var definition: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	var anchor: Node3D = slot.raw_material_anchor
	_busy = true
	if not slot.try_begin_transfer(actor):
		_busy = false
		return false
	var candidate: AutolysisRawMaterial = _prepare_world_item(instance)
	if candidate == null:
		_end_blend_transfer(slot)
		return false
	if not _blend_transaction_valid(actor, slot, anchor, original_index, instance) or not candidate.prepare_device_storage(slot):
		_rollback_blend_candidate(slot, candidate)
		return false
	if not slot.try_attach_prepared_item(candidate):
		_rollback_blend_candidate(slot, candidate)
		return false
	# 入树回调可能删除设备、改变会话或搬走原药，提交前重新核对全部来源。
	if not _blend_transaction_valid(actor, slot, anchor, original_index, instance) or not _node_is_live(candidate):
		_rollback_blend_candidate(slot, candidate)
		return false
	if candidate.item_instance != instance or candidate.item_definition != definition or not slot.owns_item(candidate) or candidate.get_parent() != anchor:
		_rollback_blend_candidate(slot, candidate)
		return false
	_slots[original_index] = null
	_commit_visual(null)
	_publish_change()
	_end_blend_transfer(slot)
	return true


func can_take_from_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if not _can_query_blend_slot(actor, slot) or get_focused_item() != null:
		return false
	var item: AutolysisRawMaterial = slot.get_stored_item()
	return _node_is_live(item) and slot.owns_item(item) and is_instance_valid(item.item_instance) and item.item_instance.is_valid_instance() and item.item_instance.definition == item.item_definition and item.item_definition.is_raw_material


func try_take_from_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if _busy or not can_take_from_blend_slot(actor, slot):
		return false
	var original_index: int = _focused_index
	var item: AutolysisRawMaterial = slot.get_stored_item()
	var definition: AutolysisItemDefinition = item.item_definition
	var instance: AutolysisItemInstance = item.item_instance
	var anchor: Node3D = slot.raw_material_anchor
	_busy = true
	if not slot.try_begin_transfer(actor):
		_busy = false
		return false
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_end_blend_transfer(slot)
		return false
	if not _blend_transaction_valid(actor, slot, anchor, original_index, null) or not _node_is_live(item):
		visual.free()
		_end_blend_transfer(slot)
		return false
	if item.item_instance != instance or item.item_definition != definition or not slot.owns_item(item) or not slot.release_item(item):
		visual.free()
		_end_blend_transfer(slot)
		return false
	_slots[original_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	_publish_change()
	_end_blend_transfer(slot)
	return true


func _can_query_blend_slot(actor: Node3D, slot: AutolysisBlendSlot) -> bool:
	if (_busy and not _publishing) or not _dependencies_valid() or not _node_is_live(actor) or not _node_is_live(slot):
		return false
	return actor.get_node_or_null("InventoryController") == self and slot.can_transfer(actor, _publishing)


func _blend_transaction_valid(actor: Variant, slot: Variant, anchor: Variant, original_index: int, original_item: AutolysisItemInstance) -> bool:
	if not _dependencies_valid() or not _node_is_live(actor) or not _node_is_live(slot) or not _node_is_live(anchor):
		return false
	if not actor is Node3D or not slot is AutolysisBlendSlot or not anchor is Node3D:
		return false
	if actor.get_node_or_null("InventoryController") != self or _focused_index != original_index or get_focused_instance() != original_item:
		return false
	return slot.raw_material_anchor == anchor and slot.can_transfer(actor, true)


func _rollback_blend_candidate(slot: Variant, candidate: Variant) -> void:
	if is_instance_valid(slot) and slot is AutolysisBlendSlot:
		slot.rollback_prepared_item(candidate)
	if is_instance_valid(candidate) and candidate is AutolysisRawMaterial:
		candidate.free()
	_end_blend_transfer(slot)


func _end_blend_transfer(slot: Variant) -> void:
	if is_instance_valid(slot) and slot is AutolysisBlendSlot:
		slot.end_transfer()
	_busy = false


func can_take_liquid_tank(actor: Node3D, item: AutolysisLiquidTank) -> bool:
	if not _can_query_liquid_actor(actor) or not _node_is_live(item) or not item.is_available_for_pickup():
		return false
	if not _is_liquid_tank_definition(item.item_definition) or not can_receive_instance(item.item_instance):
		return false
	if item.cabinet_stored:
		return _node_is_live(item.cabinet) and item.cabinet.can_transfer(actor, _publishing) and item.cabinet.owns_item(item)
	return item.cabinet == null and item.slot_index == -1


func try_take_liquid_tank(actor: Node3D, item: AutolysisLiquidTank) -> bool:
	if _busy or not can_take_liquid_tank(actor, item):
		return false
	var original_index: int = _focused_index
	var instance: AutolysisItemInstance = item.item_instance
	var cabinet: AutolysisLiquidTankCabinet = item.cabinet
	var slot_index: int = item.slot_index
	var anchor: Node3D = cabinet.get_slot_node(slot_index) if item.cabinet_stored else null
	_busy = true
	if item.cabinet_stored and not cabinet.try_begin_transfer(actor):
		_busy = false
		return false
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_end_liquid_transfer(cabinet)
		return false
	# 准备显示不释放来源；准备完成后核对指定罐和原空格。
	if not _liquid_pickup_source_valid(actor, item, cabinet, slot_index, anchor, original_index, instance):
		visual.free()
		_end_liquid_transfer(cabinet)
		return false
	if cabinet != null and not cabinet.release_item(item):
		visual.free()
		_end_liquid_transfer(cabinet)
		return false
	_slots[original_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	_publish_change()
	_end_liquid_transfer(cabinet)
	return true


func can_place_in_liquid_tank_cabinet(actor: Node3D, cabinet: AutolysisLiquidTankCabinet) -> bool:
	if not _can_query_liquid_actor(actor) or not _node_is_live(cabinet) or not cabinet.can_transfer(actor, _publishing):
		return false
	var definition: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	return instance != null and instance.is_valid_instance() and _is_liquid_tank_definition(definition) and cabinet.can_accept_item(definition) and _get_liquid_tank_world_scene(definition) != null


func try_place_in_liquid_tank_cabinet(actor: Node3D, cabinet: AutolysisLiquidTankCabinet) -> bool:
	if _busy or not can_place_in_liquid_tank_cabinet(actor, cabinet):
		return false
	var original_index: int = _focused_index
	var definition: AutolysisItemDefinition = get_focused_item()
	var instance: AutolysisItemInstance = get_focused_instance()
	var slot_index: int = cabinet.find_first_empty_slot()
	var anchor: Node3D = cabinet.get_slot_node(slot_index)
	_busy = true
	if not cabinet.try_begin_transfer(actor):
		_busy = false
		return false
	var candidate: AutolysisLiquidTank = _prepare_liquid_tank_world_item(instance)
	if candidate == null:
		_end_liquid_transfer(cabinet)
		return false
	if not _liquid_transaction_valid(actor, cabinet, slot_index, anchor, original_index, instance) or not candidate.prepare_cabinet_storage(cabinet, slot_index):
		_rollback_liquid_candidate(cabinet, candidate)
		return false
	if not cabinet.try_attach_prepared_item(slot_index, candidate):
		_rollback_liquid_candidate(cabinet, candidate)
		return false
	# 入树回调可能释放柜子、移动候选或损坏来源，提交前再次核对。
	if not _liquid_transaction_valid(actor, cabinet, slot_index, anchor, original_index, instance) or not _node_is_live(candidate):
		_rollback_liquid_candidate(cabinet, candidate)
		return false
	if candidate.item_instance != instance or candidate.item_definition != definition or not candidate.is_available_for_pickup() or not cabinet.owns_item(candidate) or candidate.get_parent() != anchor:
		_rollback_liquid_candidate(cabinet, candidate)
		return false
	_slots[original_index] = null
	_commit_visual(null)
	_publish_change()
	_end_liquid_transfer(cabinet)
	return true


func can_place_in_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if not _can_query_blend_tank_place(actor, place):
		return false
	var instance: AutolysisItemInstance = get_focused_instance()
	return place.get_stored_item() == null and instance != null and instance.is_empty_liquid_tank() and _get_liquid_tank_world_scene(instance.definition) != null


func try_place_in_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if _busy or not can_place_in_blend_tank_place(actor, place):
		return false
	var original_index: int = _focused_index
	var instance: AutolysisItemInstance = get_focused_instance()
	var anchor: Node3D = place.liquid_tank_anchor
	_busy = true
	if not place.try_begin_transfer(actor):
		_busy = false
		return false
	var candidate: AutolysisLiquidTank = _prepare_liquid_tank_world_item(instance)
	if candidate == null:
		_end_blend_tank_transfer(place)
		return false
	if not _blend_tank_transaction_valid(actor, place, anchor, original_index, instance) or not candidate.prepare_blend_storage(place):
		_rollback_blend_tank_candidate(place, candidate)
		return false
	if not place.try_attach_prepared_item(candidate):
		_rollback_blend_tank_candidate(place, candidate)
		return false
	if not _blend_tank_transaction_valid(actor, place, anchor, original_index, instance) or not _node_is_live(candidate):
		_rollback_blend_tank_candidate(place, candidate)
		return false
	if candidate.item_instance != instance or not instance.is_empty_liquid_tank() or not place.owns_item(candidate) or candidate.get_parent() != anchor:
		_rollback_blend_tank_candidate(place, candidate)
		return false
	_slots[original_index] = null
	_commit_visual(null)
	_publish_change()
	_end_blend_tank_transfer(place)
	return true


func can_take_from_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if not _can_query_blend_tank_place(actor, place) or get_focused_instance() != null:
		return false
	var item: AutolysisLiquidTank = place.get_stored_item()
	return _node_is_live(item) and place.owns_item(item) and is_instance_valid(item.item_instance) and item.item_instance.is_valid_instance() and item.item_instance.is_liquid_tank() and item.item_instance.definition == item.item_definition


func try_take_from_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if _busy or not can_take_from_blend_tank_place(actor, place):
		return false
	var original_index: int = _focused_index
	var item: AutolysisLiquidTank = place.get_stored_item()
	var instance: AutolysisItemInstance = item.item_instance
	var anchor: Node3D = place.liquid_tank_anchor
	_busy = true
	if not place.try_begin_transfer(actor):
		_busy = false
		return false
	var visual: Node3D = _prepare_visual(instance)
	if visual == null:
		_end_blend_tank_transfer(place)
		return false
	if not _blend_tank_transaction_valid(actor, place, anchor, original_index, null) or not _node_is_live(item):
		visual.free()
		_end_blend_tank_transfer(place)
		return false
	if item.item_instance != instance or item.item_definition != instance.definition or not instance.is_valid_instance() or not place.owns_item(item) or not place.release_item(item):
		visual.free()
		_end_blend_tank_transfer(place)
		return false
	_slots[original_index] = instance
	item.finish_pickup()
	_commit_visual(visual)
	_publish_change()
	_end_blend_tank_transfer(place)
	return true


func can_place_in_blend_tank(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	return can_place_in_blend_tank_place(actor, place)


func try_place_in_blend_tank(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	return try_place_in_blend_tank_place(actor, place)


func can_take_from_blend_tank(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	return can_take_from_blend_tank_place(actor, place)


func try_take_from_blend_tank(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	return try_take_from_blend_tank_place(actor, place)


func _can_query_blend_tank_place(actor: Node3D, place: AutolysisBlendTankPlace) -> bool:
	if (_busy and not _publishing) or not _dependencies_valid() or not _node_is_live(actor) or not _node_is_live(place):
		return false
	return actor.get_node_or_null("InventoryController") == self and place.can_transfer(actor, _publishing)


func _blend_tank_transaction_valid(actor: Variant, place: Variant, anchor: Variant, original_index: int, original_item: AutolysisItemInstance) -> bool:
	if not _dependencies_valid() or not _node_is_live(actor) or not _node_is_live(place) or not _node_is_live(anchor):
		return false
	if not actor is Node3D or not place is AutolysisBlendTankPlace or not anchor is Node3D:
		return false
	if actor.get_node_or_null("InventoryController") != self or _focused_index != original_index or get_focused_instance() != original_item:
		return false
	if original_item != null and (not original_item.is_empty_liquid_tank() or _get_liquid_tank_world_scene(original_item.definition) == null):
		return false
	return place.liquid_tank_anchor == anchor and place.can_transfer(actor, true)


func _rollback_blend_tank_candidate(place: Variant, candidate: Variant) -> void:
	if is_instance_valid(place) and place is AutolysisBlendTankPlace:
		place.rollback_prepared_item(candidate)
	if is_instance_valid(candidate) and candidate is AutolysisLiquidTank:
		candidate.free()
	_end_blend_tank_transfer(place)


func _end_blend_tank_transfer(place: Variant) -> void:
	if is_instance_valid(place) and place is AutolysisBlendTankPlace:
		place.end_transfer()
	if is_instance_valid(self):
		_busy = false


func _can_query_liquid_actor(actor: Node3D) -> bool:
	return (not _busy or _publishing) and _liquid_actor_valid(actor)


func _liquid_actor_valid(actor: Variant) -> bool:
	if not _dependencies_valid() or not _node_is_live(actor) or not actor is Node3D or get_tree().paused:
		return false
	if actor.get_node_or_null("InventoryController") != self or not _input_allowed.is_valid():
		return false
	if actor is AutolysisPlayer and not actor.is_interaction_input_allowed():
		return false
	var receiver: Object = _input_allowed.get_object()
	if not is_instance_valid(receiver) or (receiver is Node and not _node_is_live(receiver)):
		return false
	var allowed: Variant = _input_allowed.call()
	return allowed is bool and allowed and is_instance_valid(self) and _dependencies_valid() and _node_is_live(actor) and actor.get_node_or_null("InventoryController") == self


func _liquid_transaction_valid(actor: Variant, cabinet: Variant, slot_index: int, anchor: Variant, original_index: int, original_item: AutolysisItemInstance) -> bool:
	if not _liquid_actor_valid(actor) or not _node_is_live(cabinet) or not _node_is_live(anchor):
		return false
	if not cabinet is AutolysisLiquidTankCabinet or not anchor is Node3D:
		return false
	if _focused_index != original_index or get_focused_instance() != original_item:
		return false
	if original_item != null and (not original_item.is_valid_instance() or _get_liquid_tank_world_scene(original_item.definition) == null):
		return false
	return cabinet.get_slot_node(slot_index) == anchor and cabinet.can_transfer(actor, true)


func _liquid_pickup_source_valid(actor: Variant, item: Variant, cabinet: Variant, slot_index: int, anchor: Variant, original_index: int, instance: AutolysisItemInstance) -> bool:
	if not _liquid_actor_valid(actor) or not _node_is_live(item) or not item is AutolysisLiquidTank:
		return false
	if _focused_index != original_index or get_focused_instance() != null or item.item_instance != instance or item.item_definition != instance.definition:
		return false
	if not instance.is_valid_instance() or not item.is_available_for_pickup() or not _is_liquid_tank_definition(instance.definition):
		return false
	if cabinet == null:
		return not item.cabinet_stored and item.cabinet == null and item.slot_index == -1 and slot_index == -1
	if not _liquid_transaction_valid(actor, cabinet, slot_index, anchor, original_index, null):
		return false
	return item.cabinet_stored and item.cabinet == cabinet and item.slot_index == slot_index and cabinet.owns_item(item) and item.get_parent() == anchor


func _rollback_liquid_candidate(cabinet: Variant, candidate: Variant) -> void:
	if is_instance_valid(cabinet) and cabinet is AutolysisLiquidTankCabinet:
		cabinet.rollback_prepared_item(candidate)
	if is_instance_valid(candidate) and candidate is AutolysisLiquidTank:
		candidate.free()
	_end_liquid_transfer(cabinet)


func _end_liquid_transfer(cabinet: Variant) -> void:
	if is_instance_valid(cabinet) and cabinet is AutolysisLiquidTankCabinet:
		cabinet.end_transfer()
	if is_instance_valid(self):
		_busy = false


func _is_liquid_tank_definition(definition: AutolysisItemDefinition) -> bool:
	return is_instance_valid(definition) and definition.item_id == LIQUID_TANK_ID and not definition.is_raw_material and definition.is_valid_definition()


func _prepare_liquid_tank_world_item(instance: AutolysisItemInstance) -> AutolysisLiquidTank:
	if not is_instance_valid(instance) or not instance.is_valid_instance():
		return null
	var definition: AutolysisItemDefinition = instance.definition
	var scene: PackedScene = _get_liquid_tank_world_scene(definition)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	if not node is AutolysisLiquidTank:
		node.free()
		return null
	var item: AutolysisLiquidTank = node as AutolysisLiquidTank
	if not _is_liquid_tank_definition(item.item_definition) or item.item_definition.item_id != definition.item_id or item.fixed_installation or item.cabinet_stored or item.cabinet != null or item.slot_index != -1 or item.blend_stored or item.blend_place != null:
		item.free()
		return null
	if not item.bind_item_instance(instance):
		item.free()
		return null
	return item


func _get_liquid_tank_world_scene(definition: AutolysisItemDefinition) -> PackedScene:
	if not _is_liquid_tank_definition(definition) or definition.world_scene_path.is_empty() or not ResourceLoader.exists(definition.world_scene_path, "PackedScene"):
		return null
	var resource: Resource = load(definition.world_scene_path)
	if not resource is PackedScene or not resource.can_instantiate():
		return null
	var scene: PackedScene = resource as PackedScene
	var state: SceneState = scene.get_state()
	var script: Variant = _root_property(state, &"script")
	var item: Variant = _root_property(state, &"item_definition")
	var fixed_installation: Variant = _root_property(state, &"fixed_installation")
	# 许可查询仅读取场景描述，不实例化节点或执行初始化。
	if not script is Script or script.get_global_name() != &"AutolysisLiquidTank":
		return null
	if not item is AutolysisItemDefinition or not _is_liquid_tank_definition(item) or item.item_id != definition.item_id:
		return null
	if fixed_installation != null and (not fixed_installation is bool or fixed_installation):
		return null
	return scene


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.canceled or event.is_echo():
		return
	var direction: int = 0
	if event.is_action_pressed(NEXT_ACTION):
		direction = 1
	elif event.is_action_pressed(PREVIOUS_ACTION):
		direction = -1
	if direction == 0 or not _input_allowed.is_valid():
		return
	var receiver: Object = _input_allowed.get_object()
	if receiver is Node and not _node_is_live(receiver):
		return
	var allowed: Variant = _input_allowed.call()
	if allowed is bool and allowed and cycle_focus(direction):
		get_viewport().set_input_as_handled()


func _prepare_visual(item: AutolysisItemInstance) -> Node3D:
	return null if item == null else _presenter.prepare_instance(item)


func _commit_visual(visual: Node3D) -> void:
	_presenter.commit_prepared(visual)
	_presenter.watch_instance(get_focused_instance())


func _prepare_world_item(instance: AutolysisItemInstance) -> AutolysisRawMaterial:
	if not is_instance_valid(instance) or not instance.is_valid_instance():
		return null
	var definition: AutolysisItemDefinition = instance.definition
	var scene: PackedScene = _get_world_scene(definition)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	if not node is AutolysisRawMaterial:
		node.free()
		return null
	var item: AutolysisRawMaterial = node as AutolysisRawMaterial
	if item.item_definition == null or item.item_definition.item_id != definition.item_id:
		item.free()
		return null
	if not item.bind_item_instance(instance):
		item.free()
		return null
	return item


func _get_world_scene(definition: AutolysisItemDefinition) -> PackedScene:
	if definition.world_scene_path.is_empty() or not ResourceLoader.exists(definition.world_scene_path, "PackedScene"):
		return null
	var resource: Resource = load(definition.world_scene_path)
	if not resource is PackedScene or not resource.can_instantiate():
		return null
	var scene: PackedScene = resource as PackedScene
	var state: SceneState = scene.get_state()
	var script: Variant = _root_property(state, &"script")
	var item: Variant = _root_property(state, &"item_definition")
	# 查询只读场景描述，不执行世界节点初始化。
	if not script is Script or script.get_global_name() != &"AutolysisRawMaterial":
		return null
	if not item is AutolysisItemDefinition or item.item_id != definition.item_id:
		return null
	return scene


func _root_property(state: SceneState, property: StringName) -> Variant:
	if state == null or state.get_node_count() == 0:
		return null
	for index: int in state.get_node_property_count(0):
		if state.get_node_property_name(0, index) == property:
			return state.get_node_property_value(0, index)
	var nested: PackedScene = state.get_node_instance(0)
	if nested != null:
		return _root_property(nested.get_state(), property)
	return _root_property(state.get_base_scene_state(), property)


func _dependencies_valid() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and _node_is_live(_presenter)


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()


func _publish_change() -> void:
	# 保持重入保护直到观察者完成读取，避免一个请求嵌套提交第二次转移。
	# 提交已经完成，因此通知中的只读许可查询应反映最终状态。
	_publishing = true
	inventory_changed.emit()
	if is_instance_valid(self):
		_publishing = false
		_busy = false
