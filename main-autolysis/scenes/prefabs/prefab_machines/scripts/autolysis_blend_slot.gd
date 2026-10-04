class_name AutolysisBlendSlot
extends AnimatableBody3D
## 每槽独立保存开闭与占用；道具栏提交由玩家的道具控制器负责。

signal state_changed

enum SlotState { CLOSED, OPENING, OPEN, CLOSING }

@export var raw_material_anchor: Node3D
@export var toggle_interaction: AutolysisInteractionComponent
@export var transfer_interaction: AutolysisInteractionComponent
@export var animation_name: StringName

var focus_target: AutolysisFocusTarget
var machine: AutolysisBlendMachine
var state: SlotState = SlotState.CLOSED

var _runtime_player: AnimationPlayer
var _stored_item: AutolysisRawMaterial
var _configured: bool = false
var _transfer_busy: bool = false


func configure(target: AutolysisFocusTarget, runtime_player: AnimationPlayer) -> bool:
	if _configured:
		return false
	focus_target = target
	machine = get_parent() as AutolysisBlendMachine
	_runtime_player = runtime_player
	_configured = true
	if not is_configured():
		_configured = false
		return false
	toggle_interaction.set_availability_check(can_toggle)
	toggle_interaction.interaction_requested.connect(_on_toggle_requested)
	transfer_interaction.set_availability_check(_can_transfer_interact)
	transfer_interaction.interaction_requested.connect(_on_transfer_requested)
	_runtime_player.animation_finished.connect(_on_animation_finished)
	return true


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty()


## 配置失败给出实际失效字段，避免移动节点或清空引用后只能得到笼统错误。
func get_configuration_error() -> String:
	if not _node_is_live(self) or not _node_is_live(focus_target):
		return "槽位或聚焦目标描述不在有效场景树中"
	if not _node_is_live(machine) or get_parent() != machine or focus_target.get_parent() != machine:
		return "槽位与聚焦目标描述必须属于同一配药器"
	if not _node_is_live(raw_material_anchor):
		return "raw_material_anchor（原药锚点）未绑定或已失效"
	if not raw_material_anchor is PhysicsBody3D or raw_material_anchor.get_parent() != self:
		return "raw_material_anchor（原药锚点）必须指向本槽直接子级的取放物理体"
	# 本槽由物理帧动画驱动，内部取放体只继承父变换，不能独立回写物理姿态。
	if raw_material_anchor is AnimatableBody3D and raw_material_anchor.sync_to_physics:
		return "随父槽运动的原药取放体必须关闭 sync_to_physics（物理同步）"
	if not _node_is_live(_runtime_player) or not _runtime_player.has_animation(animation_name):
		return "独立运行播放器或指定槽位动画无效"
	if not _node_is_live(toggle_interaction) or toggle_interaction.get_parent() != self:
		return "toggle_interaction（开闭交互组件）必须位于本槽直接子级"
	if not _node_is_live(transfer_interaction) or transfer_interaction.get_parent() != raw_material_anchor:
		return "transfer_interaction（取放交互组件）必须位于原药取放体直接子级"
	if toggle_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT or transfer_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "槽位开闭和取放组件必须使用直接动作模式"
	return ""


func is_open() -> bool:
	return state == SlotState.OPEN


func is_closed() -> bool:
	return state == SlotState.CLOSED


func is_transfer_busy() -> bool:
	return _transfer_busy


func is_animating() -> bool:
	return state == SlotState.OPENING or state == SlotState.CLOSING


func can_toggle(actor: Node3D) -> bool:
	return is_configured() and not machine.is_interaction_locked() and not _transfer_busy and not is_animating() and _actor_is_focused(actor)


func try_toggle(actor: Node3D) -> bool:
	if not can_toggle(actor):
		return false
	if state == SlotState.CLOSED:
		state = SlotState.OPENING
		_runtime_player.play(animation_name, 0.0)
	else:
		state = SlotState.CLOSING
		_runtime_player.play_backwards(animation_name, 0.0)
	_emit_state_changed.call_deferred()
	return true


func can_transfer(actor: Node3D, allow_busy: bool = false) -> bool:
	return is_configured() and not machine.is_interaction_locked() and is_open() and (allow_busy or not _transfer_busy) and _actor_is_focused(actor)


func try_begin_transfer(actor: Node3D) -> bool:
	if _transfer_busy or not can_transfer(actor):
		return false
	_transfer_busy = true
	_emit_state_changed.call_deferred()
	return true


func end_transfer() -> void:
	if not _transfer_busy:
		return
	_transfer_busy = false
	_emit_state_changed.call_deferred()


func get_stored_item() -> AutolysisRawMaterial:
	if not is_instance_valid(_stored_item) or _stored_item.is_queued_for_deletion():
		return null
	return _stored_item


func owns_item(item: AutolysisRawMaterial) -> bool:
	return _node_is_live(item) and _node_is_live(raw_material_anchor) and get_stored_item() == item and item.device_stored and item.blend_slot == self and not is_instance_valid(item.shelf) and item.slot_index == -1 and item.get_parent() == raw_material_anchor


func try_attach_prepared_item(item: AutolysisRawMaterial) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or not is_open() or get_stored_item() != null:
		return false
	if not is_instance_valid(item) or item.is_queued_for_deletion() or not item.device_stored or item.blend_slot != self:
		return false
	if is_instance_valid(item.shelf) or item.slot_index != -1 or item.get_parent() != null:
		return false
	if not is_instance_valid(item.item_definition) or not item.item_definition.is_valid_definition() or not item.item_definition.is_raw_material:
		return false
	var anchor: Node3D = raw_material_anchor
	anchor.add_child(item)
	# 入树回调可释放设备或改变配置，提交占用前必须重新核验。
	if not is_instance_valid(self) or not is_configured() or machine.is_interaction_locked() or not is_open() or get_stored_item() != null:
		return false
	if not _node_is_live(item) or not _node_is_live(anchor) or raw_material_anchor != anchor or item.get_parent() != anchor:
		return false
	if not item.device_stored or item.blend_slot != self or is_instance_valid(item.shelf) or item.slot_index != -1:
		return false
	item.transform = Transform3D.IDENTITY
	_stored_item = item
	_emit_state_changed.call_deferred()
	return true


func release_item(item: AutolysisRawMaterial) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or not owns_item(item):
		return false
	_stored_item = null
	item.blend_slot = null
	_emit_state_changed.call_deferred()
	return true


## 关门加工来源只接受所属设备当前批次；查询不修改槽位或来源。
func can_consume_processing_item(owner_machine: AutolysisBlendMachine, batch_id: int, item: AutolysisRawMaterial, expected_instance: AutolysisItemInstance, expected_id: String) -> bool:
	if owner_machine != machine or not is_configured() or not is_closed() or _transfer_busy or not owns_item(item):
		return false
	if not machine.owns_processing_source(self, item, batch_id):
		return false
	return is_instance_valid(expected_instance) and item.item_instance == expected_instance and expected_instance.is_valid_instance() and item.item_definition == expected_instance.definition and item.item_definition.is_raw_material and String(item.item_definition.item_id) == expected_id


## 设备先核验全部来源，再在无外部通知的同步提交段调用。
func consume_processing_item(owner_machine: AutolysisBlendMachine, batch_id: int, item: AutolysisRawMaterial, expected_instance: AutolysisItemInstance, expected_id: String) -> bool:
	if not _node_is_live(machine) or not machine.is_committing_processing_batch(batch_id) or not can_consume_processing_item(owner_machine, batch_id, item, expected_instance, expected_id):
		return false
	_stored_item = null
	item.blend_slot = null
	return true


## 失败只撤销本次候选；设备失效或槽位状态改变后也不能清除其他占用。
func rollback_prepared_item(item: Variant) -> void:
	if is_instance_valid(machine) and (machine.is_batch_running() or not machine.get_processing_fault().is_empty()) and _stored_item == item:
		return
	var occupancy_changed: bool = false
	if _stored_item == item:
		_stored_item = null
		occupancy_changed = true
	if is_instance_valid(item) and item is AutolysisRawMaterial and item.blend_slot == self:
		item.blend_slot = null
		occupancy_changed = true
	if occupancy_changed:
		_emit_state_changed.call_deferred()


func _actor_is_focused(actor: Node3D) -> bool:
	if not _node_is_live(actor) or not actor is AutolysisPlayer or not focus_target.is_valid_target():
		return false
	var player: AutolysisPlayer = actor as AutolysisPlayer
	return player.is_focus_business_allowed() and _node_is_live(player.focus_controller) and player.focus_controller.is_focused_on(focus_target)


func _can_transfer_interact(actor: Node3D) -> bool:
	if not _node_is_live(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and (inventory.can_place_in_blend_slot(actor, self) or inventory.can_take_from_blend_slot(actor, self))


func _on_toggle_requested(actor: Node3D) -> void:
	try_toggle(actor)


func _on_transfer_requested(actor: Node3D) -> void:
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if not is_instance_valid(inventory):
		return
	if inventory.can_place_in_blend_slot(actor, self):
		inventory.try_place_in_blend_slot(actor, self)
	elif inventory.can_take_from_blend_slot(actor, self):
		inventory.try_take_from_blend_slot(actor, self)


func _on_animation_finished(finished_animation: StringName) -> void:
	if finished_animation != animation_name:
		return
	if state == SlotState.OPENING:
		state = SlotState.OPEN
	elif state == SlotState.CLOSING:
		state = SlotState.CLOSED
	else:
		return
	_emit_state_changed.call_deferred()


## 延后外部通知，库存取放调用栈完成前不新增同步回调。
func _emit_state_changed() -> void:
	if not _node_is_live(self):
		return
	state_changed.emit()


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
