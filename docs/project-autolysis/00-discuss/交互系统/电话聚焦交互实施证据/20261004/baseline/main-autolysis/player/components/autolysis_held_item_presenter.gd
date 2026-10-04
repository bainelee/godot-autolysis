class_name AutolysisHeldItemPresenter
extends Node3D
## 固定手持姿态应用到子模型，父容器继续负责原有鼠标摆动。

var _display: Node3D
var _following_camera: Camera3D
var _saved_transform: Transform3D
var _saved_top_level: bool = false
var _camera_relative: Transform3D
var _instance: AutolysisItemInstance


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


func prepare_instance(instance: AutolysisItemInstance) -> Node3D:
	if instance == null or not instance.is_valid_instance():
		return null
	var visual: Node3D = prepare_item(instance.definition)
	if visual == null:
		return null
	if instance.definition.item_id == &"liquid_tank" and not AutolysisLiquidTankVisual.apply_instance(visual, instance):
		visual.free()
		return null
	if instance.is_pneumatic_capsule() and not AutolysisPneumaticCapsuleVisual.apply_instance(visual, instance):
		visual.free()
		return null
	return visual


func commit_prepared(visual: Node3D) -> void:
	watch_instance(null)
	if is_instance_valid(_display):
		_display.hide()
		remove_child(_display)
		_display.queue_free()
	_display = visual
	if _display != null:
		add_child(_display)
		_display.show()


func watch_instance(instance: AutolysisItemInstance) -> void:
	if _instance != instance:
		if _instance != null and _instance.changed.is_connected(_refresh_instance_material):
			_instance.changed.disconnect(_refresh_instance_material)
		_instance = instance
		if _instance != null:
			_instance.changed.connect(_refresh_instance_material)
	_refresh_instance_material()


func _refresh_instance_material() -> void:
	if _instance == null or _instance.definition == null or not is_instance_valid(_display):
		return
	if _instance.is_liquid_tank():
		if not AutolysisLiquidTankVisual.apply_instance(_display, _instance):
			push_error("当前手持液体罐显示依赖或内容无效。")
	elif _instance.is_pneumatic_capsule():
		if not AutolysisPneumaticCapsuleVisual.apply_instance(_display, _instance):
			push_error("当前手持气动胶囊显示依赖或内容无效。")


func _exit_tree() -> void:
	watch_instance(null)


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
