class_name AutolysisFocusTarget
extends Node3D
## 描述一个设备的合法聚焦入口与明确登记的内部配对，不推断节点归属。

var device_root: PhysicsBody3D
var reference_camera: Camera3D
var root_interaction: AutolysisInteractionComponent

var _registered_targets: Dictionary = {}
var _slots: Array[AutolysisBlendSlot] = []
var _registered_handles: Dictionary = {}
var _tank_place: AutolysisBlendTankPlace
var _has_tank_place: bool = false
var _packing_configured: bool = false
var _packing_tank_place: AutolysisPackingTankPlace
var _packing_capsule_place: AutolysisPackingCapsulePlace
var _packing_door: AutolysisPackingDoor
var _packing_type_switches: Array[AutolysisPackingTypeSwitch] = []
var _packing_start_button: AutolysisPackingStartButton
var _packing_targets: Dictionary = {}


func configure(root: PhysicsBody3D, camera: Camera3D, interaction: AutolysisInteractionComponent, slots: Array[AutolysisBlendSlot], handles: Array[AutolysisBlendHandle] = [], tank_place: AutolysisBlendTankPlace = null) -> bool:
	device_root = root
	reference_camera = camera
	root_interaction = interaction
	_registered_targets.clear()
	_slots.clear()
	_registered_handles.clear()
	_tank_place = null
	_has_tank_place = false
	_clear_packing_registration()
	for slot: AutolysisBlendSlot in slots:
		if not _blend_slot_registration_valid(slot, root):
			return false
		var inner_body: PhysicsBody3D = slot.raw_material_anchor as PhysicsBody3D
		if not _node_is_live(inner_body) or _registered_targets.has(slot) or _registered_targets.has(inner_body):
			return false
		_registered_targets[slot] = slot
		_registered_targets[inner_body] = slot
		_slots.append(slot)
	for handle: AutolysisBlendHandle in handles:
		if not _node_is_live(handle) or handle.device_root != root or handle.focus_target != self:
			return false
		if not root.is_ancestor_of(handle) or _registered_handles.has(handle) or _registered_targets.has(handle):
			return false
		_registered_handles[handle] = handle
	if tank_place != null:
		if not _node_is_live(tank_place) or tank_place.machine != root or tank_place.focus_target != self:
			return false
		if not root.is_ancestor_of(tank_place) or _registered_targets.has(tank_place) or _registered_handles.has(tank_place):
			return false
		_tank_place = tank_place
		_has_tank_place = true
	return is_valid_target()


func configure_packing(root: PhysicsBody3D, camera: Camera3D, interaction: AutolysisInteractionComponent, tank_place: AutolysisPackingTankPlace, capsule_place: AutolysisPackingCapsulePlace, door: AutolysisPackingDoor, type_switches: Array[AutolysisPackingTypeSwitch], start_button: AutolysisPackingStartButton) -> bool:
	device_root = root
	reference_camera = camera
	root_interaction = interaction
	_registered_targets.clear()
	_slots.clear()
	_registered_handles.clear()
	_tank_place = null
	_has_tank_place = false
	_clear_packing_registration()
	if not root is AutolysisPackingMachine or type_switches.size() != 3:
		return false
	var controls: Array[Node3D] = [tank_place, capsule_place, door, start_button]
	for type_switch: AutolysisPackingTypeSwitch in type_switches:
		controls.append(type_switch)
	for control: Node3D in controls:
		if not _packing_control_valid(control) or _packing_targets.has(control):
			return false
		_packing_targets[control] = control
	_packing_tank_place = tank_place
	_packing_capsule_place = capsule_place
	_packing_door = door
	_packing_type_switches.assign(type_switches)
	_packing_start_button = start_button
	_packing_configured = true
	return is_valid_target()


func is_valid_target() -> bool:
	if not _node_is_live(self) or not _node_is_live(device_root) or get_parent() != device_root:
		return false
	if not _node_is_live(reference_camera) or not device_root.is_ancestor_of(reference_camera):
		return false
	if not _node_is_live(root_interaction) or root_interaction.get_parent() != device_root:
		return false
	if root_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.FOCUS:
		return false
	if _packing_configured:
		return _packing_registration_valid()
	if _slots.is_empty():
		return false
	for slot: Variant in _slots:
		if not _blend_slot_registration_valid(slot, device_root):
			return false
		if _registered_targets.get(slot) != slot or _registered_targets.get(slot.raw_material_anchor) != slot:
			return false
	for handle: Variant in _registered_handles:
		if not _node_is_live(handle) or not handle is AutolysisBlendHandle:
			return false
		if handle.focus_target != self or handle.device_root != device_root or not device_root.is_ancestor_of(handle) or _registered_handles[handle] != handle:
			return false
	if _has_tank_place:
		if not _node_is_live(_tank_place) or _tank_place.machine != device_root or _tank_place.focus_target != self or not device_root.is_ancestor_of(_tank_place):
			return false
	return true


func owns_target(body: Variant) -> bool:
	return _node_is_live(body) and is_valid_target() and (_registered_targets.has(body) or _registered_handles.has(body) or body == _tank_place or _packing_targets.has(body))


func get_inner_target(body: Variant) -> Node3D:
	return body as Node3D if owns_target(body) else null


func get_slot_for_target(body: Variant) -> AutolysisBlendSlot:
	if not owns_target(body) or not _registered_targets.has(body):
		return null
	return _registered_targets[body] as AutolysisBlendSlot


func get_handle_for_target(body: Variant) -> AutolysisBlendHandle:
	if not owns_target(body) or not _registered_handles.has(body):
		return null
	return _registered_handles[body] as AutolysisBlendHandle


func get_tank_place_for_target(body: Variant) -> AutolysisBlendTankPlace:
	return _tank_place if owns_target(body) and body == _tank_place else null


func get_packing_tank_place_for_target(body: Variant) -> AutolysisPackingTankPlace:
	return _packing_tank_place if owns_target(body) and body == _packing_tank_place else null


func get_packing_target_for_target(body: Variant) -> Node3D:
	return body as Node3D if _packing_targets.has(body) and owns_target(body) else null


func get_packing_capsule_place_for_target(body: Variant) -> AutolysisPackingCapsulePlace:
	return _packing_capsule_place if owns_target(body) and body == _packing_capsule_place else null


func get_packing_door_for_target(body: Variant) -> AutolysisPackingDoor:
	return _packing_door if owns_target(body) and body == _packing_door else null


func get_packing_type_switch_for_target(body: Variant) -> AutolysisPackingTypeSwitch:
	return body as AutolysisPackingTypeSwitch if owns_target(body) and _packing_type_switches.has(body) else null


func get_packing_start_button_for_target(body: Variant) -> AutolysisPackingStartButton:
	return _packing_start_button if owns_target(body) and body == _packing_start_button else null


func _clear_packing_registration() -> void:
	_packing_configured = false
	_packing_tank_place = null
	_packing_capsule_place = null
	_packing_door = null
	_packing_type_switches.clear()
	_packing_start_button = null
	_packing_targets.clear()


## 登记只保护命中归属和来源配对；某入口运动配置失效由该入口自行拒绝。
func _blend_slot_registration_valid(slot: Variant, root: PhysicsBody3D) -> bool:
	if not _node_is_live(slot) or not slot is AutolysisBlendSlot or not _node_is_live(root):
		return false
	if slot.machine != root or slot.focus_target != self or not root.is_ancestor_of(slot):
		return false
	var anchor: Variant = slot.raw_material_anchor
	return _node_is_live(anchor) and anchor is PhysicsBody3D and slot.is_ancestor_of(anchor)


func _packing_control_valid(control: Variant) -> bool:
	if not _node_is_live(control) or not control is Node3D or not _node_is_live(device_root):
		return false
	if not device_root.is_ancestor_of(control):
		return false
	return control.machine == device_root and control.focus_target == self


func _packing_registration_valid() -> bool:
	if not device_root is AutolysisPackingMachine or _packing_targets.size() != 7 or _packing_type_switches.size() != 3:
		return false
	# 登记对象可能已经释放；先按未限定类型的引用检查，避免无效对象被写入类型数组。
	var controls: Array = [_packing_tank_place, _packing_capsule_place, _packing_door, _packing_start_button]
	for type_switch: Variant in _packing_type_switches:
		controls.append(type_switch)
	for control: Variant in controls:
		if not _packing_control_valid(control) or _packing_targets.get(control) != control:
			return false
	return true


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
