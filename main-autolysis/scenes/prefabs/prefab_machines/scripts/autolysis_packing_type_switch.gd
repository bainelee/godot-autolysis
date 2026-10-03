class_name AutolysisPackingTypeSwitch
extends AutolysisPackingMotion
## 选择和灯材质由本机同步提交；动画完成只能更新自身运动状态。

@export_range(0, 2) var packing_type: int = 0
@export var indicator: MeshInstance3D
@export var selected_material: Material

var _selected: bool = false
var _original_material: Material


func configure(owner_machine: AutolysisPackingMachine, target: AutolysisFocusTarget, runtime_player: AnimationPlayer) -> bool:
	if not _node_is_live(indicator) or indicator.get_parent() != owner_machine or not is_instance_valid(selected_material):
		return false
	_original_material = indicator.material_override
	return super.configure(owner_machine, target, runtime_player)


func get_configuration_error() -> String:
	var error: String = super.get_configuration_error()
	if not error.is_empty():
		return error
	if packing_type < 0 or packing_type > 2 or not _node_is_live(indicator) or indicator.get_parent() != machine or not is_instance_valid(selected_material):
		return "类型、指示灯或亮起材质无效"
	return ""


func is_selected() -> bool:
	return _selected


func get_original_material() -> Material:
	return _original_material


func can_toggle(actor: Node3D) -> bool:
	return is_configured() and machine.can_select_type(actor, packing_type)


func _on_toggle_requested(actor: Node3D) -> void:
	machine.try_select_type(actor, packing_type)


func set_selected(selected: bool) -> void:
	if not is_configured():
		return
	indicator.material_override = selected_material if selected else _original_material
	if _selected == selected:
		return
	_selected = selected
	_start_motion(selected)
