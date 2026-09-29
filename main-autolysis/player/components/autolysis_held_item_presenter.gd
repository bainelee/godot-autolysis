class_name AutolysisHeldItemPresenter
extends Node3D
## 固定手持姿态应用到子模型，父容器继续负责原有鼠标摆动。

var _display: Node3D
var _following_camera: Camera3D
var _saved_transform: Transform3D
var _saved_top_level: bool = false
var _camera_relative: Transform3D


func begin_camera_follow(camera: Camera3D) -> bool:
	if not is_instance_valid(camera) or not camera.is_inside_tree() or is_instance_valid(_following_camera):
		return false
	_saved_transform = transform
	_saved_top_level = top_level
	_camera_relative = camera.global_transform.affine_inverse() * global_transform
	_following_camera = camera
	top_level = true
	sync_camera_follow()
	return true


func sync_camera_follow() -> void:
	if is_instance_valid(_following_camera) and _following_camera.is_inside_tree() and is_inside_tree():
		global_transform = _following_camera.global_transform * _camera_relative


func end_camera_follow() -> void:
	_following_camera = null
	top_level = _saved_top_level
	transform = _saved_transform


func prepare_item(item: AutolysisItemDefinition) -> Node3D:
	if item == null or not item.is_valid_definition():
		return null
	var candidate: Node = item.visual_scene.instantiate()
	if not candidate is Node3D or not _is_display_only(candidate):
		candidate.free()
		return null
	var visual: Node3D = candidate as Node3D
	visual.position = item.held_position
	visual.rotation_degrees = item.held_rotation_degrees
	visual.scale = item.held_scale
	return visual


func commit_prepared(visual: Node3D) -> void:
	if is_instance_valid(_display):
		_display.hide()
		remove_child(_display)
		_display.queue_free()
	_display = visual
	if _display != null:
		add_child(_display)
		_display.show()


func get_display() -> Node3D:
	return _display if is_instance_valid(_display) else null


func _is_display_only(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is AutolysisInteractionComponent:
		return false
	if node.is_in_group(&"interactable") or node.get_script() != null:
		return false
	for child: Node in node.get_children():
		if not _is_display_only(child):
			return false
	return true
