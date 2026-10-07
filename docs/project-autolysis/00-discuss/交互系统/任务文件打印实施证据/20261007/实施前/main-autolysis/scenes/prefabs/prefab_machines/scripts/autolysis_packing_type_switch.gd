class_name AutolysisPackingTypeSwitch
extends AutolysisPackingMotion
## 选择和灯材质由本机同步提交；动画完成只能更新自身运动状态。

@export_range(0, 2) var packing_type: int = 0
@export var indicator: MeshInstance3D
@export var selected_material: Material

var _selected: bool = false
var _original_material: Material
var _indicator_enabled: bool = false


func configure(owner_machine: AutolysisPackingMachine, target: AutolysisFocusTarget, runtime_player: AnimationPlayer) -> bool:
	var configured: bool = super.configure(owner_machine, target, runtime_player)
	_initialize_indicator()
	return configured


func get_configuration_error() -> String:
	var error: String = super.get_configuration_error()
	if not error.is_empty():
		return error
	if packing_type < 0 or packing_type > 2:
		return "类型编号无效"
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
	if not is_configured() and selected:
		return
	_update_indicator(selected)
	if _selected == selected:
		return
	_selected = selected
	if is_configured():
		_start_motion(selected)


func clear_selection_for_recovery() -> void:
	_selected = false
	_update_indicator(false)
	restore_closed()


func _initialize_indicator() -> void:
	_indicator_enabled = _indicator_dependencies_are_valid()
	if _indicator_enabled:
		_original_material = indicator.material_override
		_update_indicator(_selected)
	else:
		push_warning("封装类型灯停止更新：显示引用、归属、网格或材质无效")


func rebind_indicator() -> void:
	_initialize_indicator()


func _indicator_dependencies_are_valid() -> bool:
	return _node_is_live(machine) and _node_is_live(indicator) and machine.is_ancestor_of(indicator) and indicator.mesh != null and is_instance_valid(selected_material)


func _update_indicator(selected: bool) -> void:
	if not _indicator_enabled:
		return
	if not _indicator_dependencies_are_valid():
		_indicator_enabled = false
		push_warning("封装类型灯停止更新：显示依赖已失效")
		return
	indicator.material_override = selected_material if selected else _original_material
