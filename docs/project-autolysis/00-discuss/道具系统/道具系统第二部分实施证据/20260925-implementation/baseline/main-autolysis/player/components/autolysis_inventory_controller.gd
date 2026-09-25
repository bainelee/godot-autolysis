class_name AutolysisInventoryController
extends Node
## 四格状态与原药转移的唯一写入入口；通知发出前各处占用已经一致。

signal inventory_changed()

const SLOT_COUNT: int = 4
const NEXT_ACTION: StringName = &"inventory_next"
const PREVIOUS_ACTION: StringName = &"inventory_previous"

var _slots: Array[AutolysisItemDefinition] = []
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
	if index < 0 or index >= SLOT_COUNT:
		return null
	return _slots[index]


func get_focused_index() -> int:
	return _focused_index


func get_focused_item() -> AutolysisItemDefinition:
	return _slots[_focused_index]


func cycle_focus(direction: int) -> bool:
	if _busy or not _dependencies_valid() or (direction != -1 and direction != 1):
		return false
	_busy = true
	var next_index: int = posmod(_focused_index + direction, SLOT_COUNT)
	var item: AutolysisItemDefinition = _slots[next_index]
	var visual: Node3D = _prepare_visual(item)
	if item != null and visual == null:
		_busy = false
		return false
	_focused_index = next_index
	_presenter.commit_prepared(visual)
	_publish_change()
	return true


func can_receive_item(item: AutolysisItemDefinition) -> bool:
	return (not _busy or _publishing) and _dependencies_valid() and get_focused_item() == null and item != null and item.is_valid_definition()


func try_receive_item(item: AutolysisItemDefinition) -> bool:
	if _busy or not can_receive_item(item):
		return false
	_busy = true
	var visual: Node3D = _prepare_visual(item)
	if visual == null:
		_busy = false
		return false
	_slots[_focused_index] = item
	_presenter.commit_prepared(visual)
	_publish_change()
	return true


func can_take_world_item(item: AutolysisRawMaterial) -> bool:
	if not _node_is_live(item) or not item.is_available_for_pickup():
		return false
	if not can_receive_item(item.item_definition):
		return false
	if item.shelf != null:
		return _node_is_live(item.shelf) and item.shelf.owns_item(item)
	return item.slot_index == -1


func try_take_world_item(item: AutolysisRawMaterial) -> bool:
	if _busy or not can_take_world_item(item):
		return false
	_busy = true
	var definition: AutolysisItemDefinition = item.item_definition
	var visual: Node3D = _prepare_visual(definition)
	if visual == null:
		_busy = false
		return false
	# 模型准备期间不提交任何占用；准备完成后再次核对来源。
	if not _node_is_live(item) or not item.is_available_for_pickup():
		visual.free()
		_busy = false
		return false
	if item.shelf != null:
		if not _node_is_live(item.shelf) or not item.shelf.release_item(item):
			visual.free()
			_busy = false
			return false
	_slots[_focused_index] = definition
	item.finish_pickup()
	_presenter.commit_prepared(visual)
	_publish_change()
	return true


func can_place_on_shelf(shelf: AutolysisRawMaterialShelf) -> bool:
	if (_busy and not _publishing) or not _dependencies_valid() or not _node_is_live(shelf):
		return false
	var item: AutolysisItemDefinition = get_focused_item()
	return item != null and item.is_raw_material and shelf.can_accept_item(item) and _get_world_scene(item) != null


func try_place_on_shelf(shelf: AutolysisRawMaterialShelf) -> bool:
	if _busy or not can_place_on_shelf(shelf):
		return false
	_busy = true
	var original_index: int = _focused_index
	var definition: AutolysisItemDefinition = get_focused_item()
	var slot: int = shelf.find_first_empty_slot()
	var candidate: AutolysisRawMaterial = _prepare_world_item(definition)
	if candidate == null:
		_busy = false
		return false
	if not _node_is_live(shelf) or _focused_index != original_index or get_focused_item() != definition:
		candidate.free()
		_busy = false
		return false
	if not shelf.try_attach_item(slot, candidate):
		if is_instance_valid(candidate):
			candidate.free()
		_busy = false
		return false
	_slots[original_index] = null
	_presenter.commit_prepared(null)
	_publish_change()
	return true


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


func _prepare_visual(item: AutolysisItemDefinition) -> Node3D:
	return null if item == null else _presenter.prepare_item(item)


func _prepare_world_item(definition: AutolysisItemDefinition) -> AutolysisRawMaterial:
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
	item.item_definition = definition
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


func _node_is_live(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()


func _publish_change() -> void:
	# 保持重入保护直到观察者完成读取，避免一个请求嵌套提交第二次转移。
	# 提交已经完成，因此通知中的只读许可查询应反映最终状态。
	_publishing = true
	inventory_changed.emit()
	if is_instance_valid(self):
		_publishing = false
		_busy = false
