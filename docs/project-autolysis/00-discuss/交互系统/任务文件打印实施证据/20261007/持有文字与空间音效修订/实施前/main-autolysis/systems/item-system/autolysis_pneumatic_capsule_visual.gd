class_name AutolysisPneumaticCapsuleVisual
extends RefCounted
## 世界、槽内及手持胶囊只替换标识网格的覆盖材质，不修改共享材质。

const EMPTY_MATERIAL: Material = preload("res://main-autolysis/assets/materials/base_color/mat_base_grey_1.tres")
const PACKED_MATERIAL: Material = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_green_0.tres")


static func get_contents_mesh(root: Node3D) -> MeshInstance3D:
	if not is_instance_valid(root) or root.is_queued_for_deletion():
		return null
	var mesh: MeshInstance3D = root.get_node_or_null("mesh_packing_info") as MeshInstance3D
	if mesh == null:
		mesh = root.get_node_or_null("mesh/mesh_packing_info") as MeshInstance3D
	return mesh if is_instance_valid(mesh) and not mesh.is_queued_for_deletion() else null


static func can_apply(root: Node3D) -> bool:
	var mesh: MeshInstance3D = get_contents_mesh(root)
	return mesh != null and mesh.mesh != null and EMPTY_MATERIAL != null and PACKED_MATERIAL != null


static func apply_instance(root: Node3D, instance: AutolysisItemInstance) -> bool:
	if not is_instance_valid(instance) or not instance.is_valid_instance() or not instance.is_pneumatic_capsule() or not can_apply(root):
		return false
	get_contents_mesh(root).material_override = EMPTY_MATERIAL if instance.is_empty_pneumatic_capsule() else PACKED_MATERIAL
	return true
