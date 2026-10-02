class_name AutolysisLiquidTankCabinet
extends StaticBody3D
## 两槽共用门禁和转移锁，初始化只登记场景已有罐。

enum DoorState { CLOSED, OPENING, OPEN, CLOSING }

@export var slot_0: Node3D
@export var slot_1: Node3D
@export var door_body: AnimatableBody3D
@export var toggle_interaction: AutolysisInteractionComponent
@export var placement_body: StaticBody3D
@export var placement_interaction: AutolysisInteractionComponent
@export var animation_player: AnimationPlayer
@export var animation_name: StringName = &"open"

var state: DoorState = DoorState.CLOSED
var _items: Array[AutolysisLiquidTank] = []
var _configured: bool = false
var _transfer_busy: bool = false
var _motion_fault: bool = false
var _closed_rotation: Vector3 = Vector3.ZERO
var _open_rotation: Vector3 = Vector3.ZERO


func _ready() -> void:
	_items.resize(2)
	_protect_initial_sources()
	var error: String = get_configuration_error()
	if not error.is_empty():
		push_error("液体罐柜配置失败：%s；%s" % [get_path(), error])
		return
	var source: Animation = animation_player.get_animation(animation_name)
	_closed_rotation = source.track_get_key_value(0, 0)
	_open_rotation = source.track_get_key_value(0, source.track_get_key_count(0) - 1)
	animation_player.playback_auto_capture = false
	animation_player.stop(true)
	if not door_body.rotation.is_equal_approx(_closed_rotation):
		push_error("液体罐柜必须以关闭门姿态初始化：%s" % get_path())
		return
	if not _register_initial_items():
		return
	toggle_interaction.set_availability_check(can_toggle)
	toggle_interaction.interaction_requested.connect(_on_toggle_requested)
	placement_interaction.set_availability_check(_can_place_interact)
	placement_interaction.interaction_requested.connect(_on_place_requested)
	animation_player.animation_finished.connect(_on_animation_finished)
	_configured = true


func get_configuration_error() -> String:
	if not _node_is_live(self):
		return "柜子未进入有效场景树"
	if not _node_is_live(slot_0) or not _node_is_live(slot_1) or slot_0 == slot_1:
		return "两个槽锚点必须有效且互不重复"
	if slot_0.get_parent() != self or slot_1.get_parent() != self or slot_0.name != &"liquid_tank_slot_0" or slot_1.name != &"liquid_tank_slot_1":
		return "两个槽锚点必须绑定本柜编号零和一的直接子节点"
	if not _node_is_live(door_body) or door_body.get_parent() != self:
		return "活动门体必须为本柜直接子节点"
	if not _node_is_live(placement_body) or placement_body.get_parent() != self:
		return "放置物理体必须为本柜直接子节点"
	if not _valid_component(door_body, toggle_interaction) or not _valid_component(placement_body, placement_interaction):
		return "门体和放置体必须各有一个直接子级直接交互组件"
	if not _node_is_live(animation_player) or animation_player.get_parent() != self or not animation_player.has_animation(animation_name):
		return "动画播放器或指定开门动画无效"
	if not animation_player.active or animation_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS:
		return "门动画必须启用并使用物理帧回调"
	var source: Animation = animation_player.get_animation(animation_name)
	if source.loop_mode != Animation.LOOP_NONE or not is_equal_approx(source.length, 0.2):
		return "门动画必须为现有零点二秒非循环动作"
	if source.get_track_count() != 1 or source.track_get_path(0) != NodePath("cabinet_door_left_root:rotation") or source.track_get_key_count(0) < 2:
		return "门动画必须控制现有活动门旋转轨道"
	return ""


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty() and _storage_is_consistent()


func get_slot_count() -> int:
	return 2


func get_slot_node(index: int) -> Node3D:
	var slot: Node3D = slot_0 if index == 0 else slot_1 if index == 1 else null
	return slot if _node_is_live(slot) and slot.get_parent() == self else null


func get_item_at_slot(index: int) -> AutolysisLiquidTank:
	if index < 0 or index >= _items.size():
		return null
	var item: AutolysisLiquidTank = _items[index]
	return item if _node_is_live(item) else null


func find_first_empty_slot() -> int:
	if not is_configured():
		return -1
	for index: int in 2:
		if get_slot_node(index) != null and _items[index] == null:
			return index
	return -1


func owns_item(item: AutolysisLiquidTank) -> bool:
	if not _node_is_live(item) or not item.cabinet_stored or item.fixed_installation or item.cabinet != self or item.blend_stored or is_instance_valid(item.blend_place):
		return false
	var slot: Node3D = get_slot_node(item.slot_index)
	return slot != null and get_item_at_slot(item.slot_index) == item and item.get_parent() == slot


func can_accept_item(definition: AutolysisItemDefinition) -> bool:
	return _valid_definition(definition) and is_open() and find_first_empty_slot() >= 0


func is_open() -> bool:
	return state == DoorState.OPEN and not _motion_fault and is_configured() and not animation_player.is_playing() and door_body.rotation.is_equal_approx(_open_rotation)


func is_animating() -> bool:
	return state == DoorState.OPENING or state == DoorState.CLOSING


func can_toggle(actor: Node3D) -> bool:
	if not _actor_is_valid(actor) or not is_configured() or _transfer_busy or _motion_fault or is_animating() or animation_player.is_playing():
		return false
	return door_body.rotation.is_equal_approx(_closed_rotation if state == DoorState.CLOSED else _open_rotation)


func try_toggle(actor: Node3D) -> bool:
	if not can_toggle(actor):
		return false
	if state == DoorState.CLOSED:
		state = DoorState.OPENING
		animation_player.play(animation_name, 0.0)
	else:
		state = DoorState.CLOSING
		animation_player.play_backwards(animation_name, 0.0)
	return true


func can_transfer(actor: Node3D, allow_busy: bool = false) -> bool:
	return _actor_is_valid(actor) and is_open() and (allow_busy or not _transfer_busy)


func try_begin_transfer(actor: Node3D) -> bool:
	if not can_transfer(actor):
		return false
	_transfer_busy = true
	return true


func end_transfer() -> void:
	_transfer_busy = false


func try_attach_prepared_item(index: int, item: AutolysisLiquidTank) -> bool:
	if not _transfer_busy or not is_open() or index < 0 or index >= 2 or _items[index] != null:
		return false
	if not is_instance_valid(item) or item.is_queued_for_deletion() or item.get_parent() != null or item.is_inside_tree():
		return false
	if not item.cabinet_stored or item.cabinet != self or item.slot_index != index or item.fixed_installation or not _valid_item_instance(item) or item.blend_stored or is_instance_valid(item.blend_place):
		return false
	var slot: Node3D = get_slot_node(index)
	if slot == null or not _live_slot_children(slot).is_empty():
		return false
	slot.add_child(item)
	# 候选初始化可改变配置；提交占用前重新核对身份和唯一子节点。
	if not is_instance_valid(self) or not _node_is_live(self) or not _configured or not get_configuration_error().is_empty() or not _transfer_busy or state != DoorState.OPEN or _items[index] != null:
		return false
	if not _node_is_live(item) or not _node_is_live(slot) or get_slot_node(index) != slot or item.get_parent() != slot or _live_slot_children(slot).size() != 1:
		return false
	if not item.cabinet_stored or item.cabinet != self or item.slot_index != index or item.fixed_installation or not _valid_item_instance(item) or item.blend_stored or is_instance_valid(item.blend_place):
		return false
	item.transform = Transform3D.IDENTITY
	_items[index] = item
	return true


func release_item(item: AutolysisLiquidTank) -> bool:
	if not _transfer_busy or not owns_item(item):
		return false
	_items[item.slot_index] = null
	item.cabinet = null
	item.slot_index = -1
	return true


func rollback_prepared_item(item: Variant) -> void:
	for index: int in _items.size():
		if _items[index] == item:
			_items[index] = null
	if is_instance_valid(item) and item is AutolysisLiquidTank and item.cabinet == self:
		item.cabinet = null
		item.slot_index = -1


func _register_initial_items() -> bool:
	var initial: Array[AutolysisLiquidTank] = []
	initial.resize(2)
	for index: int in 2:
		var slot: Node3D = get_slot_node(index)
		if slot.get_child_count() > 1:
			push_error("液体罐柜槽内存在多个对象，禁止覆盖：%s" % slot.get_path())
			return false
		if slot.get_child_count() == 0:
			continue
		var item: AutolysisLiquidTank = slot.get_child(0) as AutolysisLiquidTank
		if not _node_is_live(item) or item.fixed_installation or not item.cabinet_stored or item.cabinet != self or item.slot_index != index or not _valid_item_instance(item) or item.blend_stored or is_instance_valid(item.blend_place):
			push_error("液体罐柜初始槽内容或来源无效：%s" % slot.get_path())
			return false
		if initial.has(item):
			push_error("液体罐柜不能重复登记同一物体：%s" % slot.get_path())
			return false
		initial[index] = item
	for index: int in 2:
		var item: AutolysisLiquidTank = initial[index]
		if item != null:
			item.cabinet = self
			item.slot_index = index
			item.cabinet_stored = true
			_items[index] = item
	return true


## 配置失败也不能让柜内初始罐退回无主拾取；登记仍由完整校验决定。
func _protect_initial_sources() -> void:
	for index: int in 2:
		var slot: Node = get_node_or_null("liquid_tank_slot_%d" % index)
		if not is_instance_valid(slot):
			continue
		for child: Node in slot.get_children():
			var item: AutolysisLiquidTank = child as AutolysisLiquidTank
			if not is_instance_valid(item) or item.cabinet_stored or is_instance_valid(item.cabinet) or item.slot_index != -1:
				continue
			item.cabinet = self
			item.slot_index = index
			item.cabinet_stored = true


func _storage_is_consistent() -> bool:
	if _items.size() != 2:
		return false
	for index: int in 2:
		var slot: Node3D = get_slot_node(index)
		if slot == null:
			return false
		var item: AutolysisLiquidTank = _items[index]
		if item == null:
			if not _live_slot_children(slot).is_empty():
				return false
		elif not owns_item(item) or _live_slot_children(slot).size() != 1 or not _valid_definition(item.item_definition):
			return false
	return true


## 已提交拾取的排队来源不再占槽，允许同帧取回和再次放入。
func _live_slot_children(slot: Node3D) -> Array[Node]:
	var children: Array[Node] = []
	for child: Node in slot.get_children():
		if _node_is_live(child):
			children.append(child)
	return children


func _valid_definition(definition: AutolysisItemDefinition) -> bool:
	return is_instance_valid(definition) and definition.is_valid_definition() and not definition.is_raw_material and definition.item_id == &"liquid_tank"


func _valid_item_instance(item: AutolysisLiquidTank) -> bool:
	return is_instance_valid(item) and is_instance_valid(item.item_instance) and item.item_instance.is_valid_instance() and item.item_instance.definition == item.item_definition and _valid_definition(item.item_definition)


func _valid_component(body: PhysicsBody3D, component: AutolysisInteractionComponent) -> bool:
	if not _node_is_live(component) or component.get_parent() != body or component.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return false
	var count: int = 0
	for child: Node in body.get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	return count == 1


func _actor_is_valid(actor: Node3D) -> bool:
	if not _node_is_live(actor) or get_tree().paused:
		return false
	return not actor is AutolysisPlayer or (actor as AutolysisPlayer).is_interaction_input_allowed()


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()


func _process(_delta: float) -> void:
	if is_animating() and (not _node_is_live(animation_player) or not animation_player.is_playing()):
		_motion_fault = true


func _on_animation_finished(finished_animation: StringName) -> void:
	if finished_animation != animation_name or not _configured or _motion_fault:
		return
	if state == DoorState.OPENING:
		state = DoorState.OPEN
	elif state == DoorState.CLOSING:
		state = DoorState.CLOSED


func _on_toggle_requested(actor: Node3D) -> void:
	try_toggle(actor)


func _can_place_interact(actor: Node3D) -> bool:
	if not _node_is_live(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and inventory.can_place_in_liquid_tank_cabinet(actor, self)


func _on_place_requested(actor: Node3D) -> void:
	if not _node_is_live(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if is_instance_valid(inventory):
		inventory.try_place_in_liquid_tank_cabinet(actor, self)
