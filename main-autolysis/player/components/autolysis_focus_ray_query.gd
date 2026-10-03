class_name AutolysisFocusRayQuery
extends RefCounted
## 当前设备之外的首命中始终阻挡；仅允许穿过本槽整体盒查询其配对取放体。

const MAX_DISTANCE: float = 2.0
const COLLISION_MASK: int = 35


func query_target(camera: Camera3D, mouse_position: Vector2, target: AutolysisFocusTarget, exclusions: Array[RID] = []) -> Node3D:
	if not is_instance_valid(camera) or not camera.is_inside_tree() or camera.is_queued_for_deletion():
		return null
	if not is_instance_valid(target) or not target.is_valid_target():
		return null
	var world: World3D = camera.get_world_3d()
	if world == null:
		return null
	var excluded: Array[RID] = exclusions.duplicate()
	var root_rid: RID = target.device_root.get_rid()
	if not excluded.has(root_rid):
		excluded.append(root_rid)
	var origin: Vector3 = camera.project_ray_origin(mouse_position)
	var endpoint: Vector3 = origin + camera.project_ray_normal(mouse_position) * MAX_DISTANCE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, endpoint, COLLISION_MASK, excluded)
	query.hit_from_inside = true
	query.collide_with_areas = false
	var first_hit: Dictionary = world.direct_space_state.intersect_ray(query)
	var first_body: Node = first_hit.get("collider") as Node
	# 封装器只解析显式登记的首命中，门和其他物体仍保留真实遮挡。
	var packing_target: Node3D = target.get_packing_target_for_target(first_body)
	if packing_target != null:
		return packing_target
	var handle: AutolysisBlendHandle = target.get_handle_for_target(first_body)
	if handle != null:
		return handle
	var tank_place: AutolysisBlendTankPlace = target.get_tank_place_for_target(first_body)
	if tank_place != null:
		return tank_place
	var slot: AutolysisBlendSlot = target.get_slot_for_target(first_body)
	if slot == null:
		return null
	# 共享边界直接命中取放体时，关闭或运动中的槽位统一解析为开闭入口。
	if first_body == slot.raw_material_anchor:
		return slot.raw_material_anchor if slot.is_open() else slot
	if not slot.is_open():
		return slot
	# 第二次沿完全相同的射线查询，只额外排除这一个已登记槽体。
	excluded.append(slot.get_rid())
	query.exclude = excluded
	var inner_hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if inner_hit.get("collider") == slot.raw_material_anchor:
		return target.get_inner_target(slot.raw_material_anchor)
	return slot
