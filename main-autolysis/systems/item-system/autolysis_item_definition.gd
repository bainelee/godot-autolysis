class_name AutolysisItemDefinition
extends Resource
## 道具类型的共享定义；携带和架子占用保存在各自运行实例中。

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var is_raw_material: bool = true
@export var icon: Texture2D
@export var visual_scene: PackedScene
@export_file("*.tscn") var world_scene_path: String = ""
@export var held_position: Vector3 = Vector3(0.24, -0.23, -0.48)
@export var held_rotation_degrees: Vector3 = Vector3(-8, -18, 12)
@export var held_scale: Vector3 = Vector3.ONE


func is_valid_definition() -> bool:
	return not item_id.is_empty() and not display_name.is_empty() and visual_scene != null and visual_scene.can_instantiate() and _is_visual_state(visual_scene.get_state())


## 直接读取场景描述，查询期间不创建节点或执行任何场景脚本。
func _is_visual_state(state: SceneState) -> bool:
	if state == null or state.get_node_count() == 0:
		return false
	var base: SceneState = state.get_base_scene_state()
	if base != null and not _is_visual_state(base):
		return false
	for index: int in state.get_node_count():
		var type: StringName = state.get_node_type(index)
		var nested: PackedScene = state.get_node_instance(index)
		if state.is_node_instance_placeholder(index):
			return false
		if nested != null and not _is_visual_state(nested.get_state()):
			return false
		if not type.is_empty():
			if index == 0 and not ClassDB.is_parent_class(type, &"Node3D"):
				return false
			if ClassDB.is_parent_class(type, &"CollisionObject3D") or ClassDB.is_parent_class(type, &"CollisionShape3D"):
				return false
		if &"interactable" in state.get_node_groups(index):
			return false
		for property_index: int in state.get_node_property_count(index):
			if state.get_node_property_name(index, property_index) == &"script" and state.get_node_property_value(index, property_index) != null:
				return false
	return true
