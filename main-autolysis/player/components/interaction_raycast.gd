class_name InteractionRayCast
extends RayCast3D

signal interactable_seen(interactable: Node3D)
signal interactable_unseen()

const BASE_COLLISION_MASK: int = 3
const PLACE_SHELF_LAYER: int = 5

var _target_id: int = 0


## 只接受中心射线的首个碰撞，普通墙体不会被排除后穿透查询。
func refresh_target(include_place_shelves: bool = false) -> Node3D:
	collision_mask = BASE_COLLISION_MASK
	set_collision_mask_value(PLACE_SHELF_LAYER, include_place_shelves)
	var target: Node3D = null
	if is_inside_tree() and not is_queued_for_deletion():
		force_raycast_update()
		var collider: Object = get_collider()
		if is_colliding() and is_instance_valid(collider) and collider is Node3D:
			var spatial: Node3D = collider as Node3D
			if spatial.is_inside_tree() and not spatial.is_queued_for_deletion() and spatial.is_in_group(&"interactable"):
				target = spatial
	var next_id: int = target.get_instance_id() if is_instance_valid(target) else 0
	if next_id != _target_id:
		_target_id = next_id
		if target == null:
			interactable_unseen.emit()
		else:
			interactable_seen.emit(target)
	return target
