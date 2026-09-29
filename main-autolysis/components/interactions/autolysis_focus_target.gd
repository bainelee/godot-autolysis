class_name AutolysisFocusTarget
extends Node3D
## 描述一个设备的合法聚焦入口与明确登记的内部配对，不推断节点归属。

var device_root: PhysicsBody3D
var reference_camera: Camera3D
var root_interaction: AutolysisInteractionComponent

var _registered_targets: Dictionary = {}
var _slots: Array[AutolysisBlendSlot] = []


func configure(root: PhysicsBody3D, camera: Camera3D, interaction: AutolysisInteractionComponent, slots: Array[AutolysisBlendSlot]) -> bool:
	device_root = root
	reference_camera = camera
	root_interaction = interaction
	_registered_targets.clear()
	_slots.clear()
	for slot: AutolysisBlendSlot in slots:
		if not _node_is_live(slot) or not slot.is_configured() or slot.get_parent() != root:
			return false
		var inner_body: PhysicsBody3D = slot.raw_material_anchor as PhysicsBody3D
		if not _node_is_live(inner_body) or _registered_targets.has(slot) or _registered_targets.has(inner_body):
			return false
		_registered_targets[slot] = slot
		_registered_targets[inner_body] = slot
		_slots.append(slot)
	return is_valid_target()


func is_valid_target() -> bool:
	if not _node_is_live(self) or not _node_is_live(device_root) or get_parent() != device_root:
		return false
	if not _node_is_live(reference_camera) or not device_root.is_ancestor_of(reference_camera):
		return false
	if not _node_is_live(root_interaction) or root_interaction.get_parent() != device_root:
		return false
	if root_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.FOCUS or _slots.is_empty():
		return false
	for slot: Variant in _slots:
		if not _node_is_live(slot) or not slot is AutolysisBlendSlot or not slot.is_configured() or slot.focus_target != self or slot.get_parent() != device_root:
			return false
		if _registered_targets.get(slot) != slot or _registered_targets.get(slot.raw_material_anchor) != slot:
			return false
	return true


func owns_target(body: Variant) -> bool:
	return _node_is_live(body) and is_valid_target() and _registered_targets.has(body)


func get_inner_target(body: Variant) -> Node3D:
	return body as Node3D if owns_target(body) else null


func get_slot_for_target(body: Variant) -> AutolysisBlendSlot:
	if not owns_target(body):
		return null
	return _registered_targets[body] as AutolysisBlendSlot


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
