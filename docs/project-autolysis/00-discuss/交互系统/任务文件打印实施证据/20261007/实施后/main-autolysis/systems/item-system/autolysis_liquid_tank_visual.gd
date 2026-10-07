class_name AutolysisLiquidTankVisual
extends RefCounted
## 世界罐与纯显示罐共用材质引用；仅修改网格实例的材质覆盖。

const EMPTY_MATERIAL: Material = preload("res://main-autolysis/assets/materials/liquid_tank/liquid_tank_empty.tres")
const FILLED_MATERIAL: Material = preload("res://main-autolysis/assets/materials/liquid_tank/liquid_tank_filled.tres")


static func get_contents_mesh(root: Node3D) -> MeshInstance3D:
	if not is_instance_valid(root) or root.is_queued_for_deletion():
		return null
	var mesh: MeshInstance3D = root.get_node_or_null("liquid_tank_liquid") as MeshInstance3D
	if mesh == null:
		mesh = root.get_node_or_null("mesh/liquid_tank_liquid") as MeshInstance3D
	return mesh if is_instance_valid(mesh) and not mesh.is_queued_for_deletion() else null


static func can_apply(root: Node3D) -> bool:
	var mesh: MeshInstance3D = get_contents_mesh(root)
	return mesh != null and mesh.mesh != null and EMPTY_MATERIAL != null and FILLED_MATERIAL != null


static func apply_instance(root: Node3D, instance: AutolysisItemInstance) -> bool:
	if instance == null or not instance.is_valid_instance() or not instance.is_liquid_tank():
		return false
	if not can_apply(root):
		return false
	var mesh: MeshInstance3D = get_contents_mesh(root)
	mesh.material_override = EMPTY_MATERIAL if instance.is_empty_liquid_tank() else FILLED_MATERIAL
	return true
