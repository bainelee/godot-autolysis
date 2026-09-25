class_name AutolysisRawMaterialShelf
extends StaticBody3D
## 槽位按数字编号排列；每个架子独立维护运行时占用。

const SLOT_PREFIX: String = "rm_place_shelf_slot_"

var _slots: Array[Node3D] = []
var _items: Array[AutolysisRawMaterial] = []

@onready var _interaction: AutolysisInteractionComponent = $InteractionComponent


func _ready() -> void:
	_collect_slots()
	_interaction.set_availability_check(_can_interact)
	if not _interaction.interaction_requested.is_connected(_on_interaction_requested):
		_interaction.interaction_requested.connect(_on_interaction_requested)


func get_slot_count() -> int:
	return _slots.size()


func find_first_empty_slot() -> int:
	if not is_inside_tree() or is_queued_for_deletion():
		return -1
	for index: int in _slots.size():
		if get_slot_node(index) != null and get_item_at_slot(index) == null:
			return index
	return -1


func get_slot_node(index: int) -> Node3D:
	if index < 0 or index >= _slots.size():
		return null
	var slot: Node3D = _slots[index]
	if not is_instance_valid(slot) or not slot.is_inside_tree() or slot.is_queued_for_deletion():
		return null
	return slot


func get_item_at_slot(index: int) -> AutolysisRawMaterial:
	if index < 0 or index >= _items.size():
		return null
	var item: AutolysisRawMaterial = _items[index]
	if not is_instance_valid(item) or item.is_queued_for_deletion():
		return null
	return item


func owns_item(item: AutolysisRawMaterial) -> bool:
	if not is_instance_valid(item) or item.is_queued_for_deletion():
		return false
	if not is_instance_valid(item.shelf) or item.shelf != self:
		return false
	var slot: Node3D = get_slot_node(item.slot_index)
	return slot != null and get_item_at_slot(item.slot_index) == item and item.get_parent() == slot


func can_accept_item(definition: AutolysisItemDefinition) -> bool:
	return is_instance_valid(definition) and definition.is_raw_material and find_first_empty_slot() >= 0


## 只接受未归属其他架子的准备实例；玩家控制器负责事务与格子提交。
func try_attach_item(index: int, item: AutolysisRawMaterial) -> bool:
	if not is_inside_tree() or is_queued_for_deletion():
		return false
	if not is_instance_valid(item) or item.is_queued_for_deletion():
		return false
	if is_instance_valid(item.shelf) or item.slot_index != -1:
		return false
	if not is_instance_valid(item.item_definition) or not item.item_definition.is_raw_material:
		return false
	var slot: Node3D = get_slot_node(index)
	if slot == null or get_item_at_slot(index) != null:
		return false
	if item.get_parent() == null:
		slot.add_child(item)
	else:
		item.reparent(slot, false)
	# 加入场景树时会执行初始化；初始化失败不得记录占用。
	if not is_instance_valid(self) or not is_inside_tree() or is_queued_for_deletion():
		return false
	if not is_instance_valid(item) or item.is_queued_for_deletion():
		return false
	if not is_instance_valid(slot) or slot.is_queued_for_deletion() or item.get_parent() != slot:
		return false
	# 入树回调可能让另一名玩家先完成放置，不得覆盖其占用。
	if get_item_at_slot(index) != null:
		return false
	item.transform = Transform3D.IDENTITY
	item.shelf = self
	item.slot_index = index
	_items[index] = item
	return true


## 解除归属但不删除节点；同一同步事务随后完成世界物体拾取。
func release_item(item: AutolysisRawMaterial) -> bool:
	if not owns_item(item):
		return false
	_items[item.slot_index] = null
	item.shelf = null
	item.slot_index = -1
	return true


func _collect_slots() -> void:
	_slots.clear()
	_items.clear()
	var container: Node3D = get_node_or_null("rm_place_shelf_slots") as Node3D
	if container == null:
		push_error("原药架缺少槽位容器：%s" % get_path())
		return
	var numbered_slots: Dictionary = {}
	for child: Node in container.get_children():
		var node_name: String = str(child.name)
		var number_text: String = node_name.trim_prefix(SLOT_PREFIX)
		if not child is Node3D or not node_name.begins_with(SLOT_PREFIX) or not number_text.is_valid_int():
			push_error("原药架槽位名称或节点类型错误：%s" % child.get_path())
			return
		var number: int = number_text.to_int()
		if number < 0 or str(number) != number_text or numbered_slots.has(number):
			push_error("原药架槽位编号无效或重复：%s" % child.get_path())
			return
		numbered_slots[number] = child
	var numbers: Array[int] = []
	numbers.assign(numbered_slots.keys())
	numbers.sort()
	for number: int in numbers:
		_slots.append(numbered_slots[number] as Node3D)
	_items.resize(_slots.size())


func _can_interact(actor: Node3D) -> bool:
	if not is_instance_valid(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and inventory.can_place_on_shelf(self)


func _on_interaction_requested(actor: Node3D) -> void:
	if not is_instance_valid(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if is_instance_valid(inventory):
		inventory.try_place_on_shelf(self)
