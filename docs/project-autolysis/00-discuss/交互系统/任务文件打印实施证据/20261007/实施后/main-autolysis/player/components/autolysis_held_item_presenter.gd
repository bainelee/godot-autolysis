class_name AutolysisHeldItemPresenter
extends Node3D
## 固定手持姿态应用到子模型，父容器继续负责原有鼠标摆动。

var _display: Node3D
var _following_camera: Camera3D
var _saved_transform: Transform3D
var _saved_top_level: bool = false
var _camera_relative: Transform3D
var _camera_follow_projection: Projection
var _camera_follow_perspective: bool = false
var _instance: AutolysisItemInstance
var _handset_source: Node3D
var _handset_session: int = 0


func begin_camera_follow(camera: Camera3D) -> bool:
	if not is_instance_valid(camera) or not camera.is_inside_tree() or is_instance_valid(_following_camera):
		return false
	_saved_transform = transform
	_saved_top_level = top_level
	_camera_relative = camera.global_transform.affine_inverse() * global_transform
	_camera_follow_projection = camera.get_camera_projection()
	_camera_follow_perspective = camera.projection == Camera3D.PROJECTION_PERSPECTIVE
	_following_camera = camera
	top_level = true
	sync_camera_follow()
	return true


func sync_camera_follow() -> void:
	if is_instance_valid(_following_camera) and _following_camera.is_inside_tree() and is_inside_tree():
		var relative: Transform3D = _camera_relative
		if _handset_session > 0:
			relative = _handset_projection_transform() * relative
		global_transform = _following_camera.global_transform * relative


func _handset_projection_transform() -> Transform3D:
	# 聚焦镜头收窄时保持听筒的普通视角投影；子模型六轴配置不参与补偿。
	if not _camera_follow_perspective or _following_camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return Transform3D.IDENTITY
	var projection: Projection = _following_camera.get_camera_projection()
	if projection.x.x == 0.0 or projection.y.y == 0.0:
		return Transform3D.IDENTITY
	var projection_scale: Vector3 = Vector3(_camera_follow_projection.x.x / projection.x.x, _camera_follow_projection.y.y / projection.y.y, 1.0)
	if not projection_scale.is_finite():
		return Transform3D.IDENTITY
	return Transform3D(Basis.from_scale(projection_scale), Vector3.ZERO)


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
	# 普通装备入口不能覆盖设备绑定的独占显示。
	if _handset_session != 0:
		return
	watch_instance(null)
	var previous: Node3D = _display
	if is_instance_valid(previous):
		previous.hide()
		if not is_instance_valid(self):
			return
		if is_instance_valid(previous) and previous.get_parent() == self:
			remove_child(previous)
		if not is_instance_valid(self):
			return
		if is_instance_valid(previous):
			previous.queue_free()
	_display = visual
	if _display != null:
		if not is_instance_valid(visual) or visual.is_queued_for_deletion():
			_display = null
			return
		add_child(visual)
		if not is_instance_valid(self):
			return
		if not is_instance_valid(visual) or visual.is_queued_for_deletion() or visual.get_parent() != self:
			_display = null
			return
		visual.show()
		if not is_instance_valid(self):
			return
		if not is_instance_valid(visual) or visual.is_queued_for_deletion():
			_display = null


func watch_instance(instance: AutolysisItemInstance) -> void:
	if _handset_session != 0 and instance != null:
		return
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


func can_prepare_handset(scene: PackedScene, position_value: Vector3, rotation_value: Vector3, scale_value: Vector3) -> bool:
	return scene != null and scene.can_instantiate() and position_value.is_finite() and rotation_value.is_finite() and scale_value.is_finite() and _is_display_scene_state(scene.get_state())


func prepare_handset(scene: PackedScene, position_value: Vector3, rotation_value: Vector3, scale_value: Vector3) -> Node3D:
	if not can_prepare_handset(scene, position_value, rotation_value, scale_value):
		return null
	var candidate: Node = scene.instantiate()
	if not candidate is Node3D or not _is_display_only(candidate):
		candidate.free()
		return null
	var visual: Node3D = candidate as Node3D
	visual.position = position_value
	visual.rotation_degrees = rotation_value
	visual.scale = scale_value
	return visual


func commit_handset_prepared(visual: Node3D, source: Node3D, session: int) -> bool:
	if not is_instance_valid(source) or session <= 0 or not is_instance_valid(visual) or visual.is_queued_for_deletion() or visual.get_parent() != null:
		return false
	if _handset_session != 0 and (_handset_source != source or _handset_session != session):
		return false
	watch_instance(null)
	_handset_source = source
	_handset_session = session
	var previous: Node3D = _display
	_display = visual
	sync_camera_follow()
	if not is_instance_valid(self) or not is_instance_valid(visual) or visual.is_queued_for_deletion():
		return false
	visual.hide()
	add_child(visual)
	# 入树观察者允许释放对象；释放后不继续访问显示或来源。
	if not is_instance_valid(self):
		return false
	if not is_instance_valid(visual) or visual.is_queued_for_deletion() or not visual.is_inside_tree() or visual.get_parent() != self:
		_display = null
		_handset_source = null
		_handset_session = 0
		sync_camera_follow()
		return false
	visual.show()
	if not is_instance_valid(self) or not is_instance_valid(visual) or visual.is_queued_for_deletion():
		return false
	if is_instance_valid(previous) and previous != visual:
		previous.hide()
		if not is_instance_valid(self) or not is_instance_valid(previous):
			return false
		if previous.get_parent() == self:
			remove_child(previous)
		if is_instance_valid(previous):
			previous.queue_free()
	return true


func clear_handset(source: Variant, session: int) -> bool:
	if _handset_source != source or _handset_session != session or session <= 0:
		return false
	var previous: Node3D = _display
	_display = null
	_handset_source = null
	_handset_session = 0
	sync_camera_follow()
	if not is_instance_valid(self):
		return true
	if is_instance_valid(previous):
		previous.hide()
		if not is_instance_valid(self) or not is_instance_valid(previous):
			return true
		if previous.get_parent() == self:
			remove_child(previous)
		if is_instance_valid(previous):
			previous.queue_free()
	return true


func is_handset_display(source: Node3D, display: Node3D, session: int) -> bool:
	return _handset_source == source and _handset_session == session and session > 0 and is_instance_valid(display) and not display.is_queued_for_deletion() and display.is_inside_tree() and _display == display and display.get_parent() == self


func apply_handset_pose(source: Node3D, display: Node3D, session: int, position_value: Vector3, rotation_value: Vector3) -> bool:
	if not is_handset_display(source, display, session) or not position_value.is_finite() or not rotation_value.is_finite():
		return false
	display.position = position_value
	display.rotation_degrees = rotation_value
	return true


func _is_display_scene_state(state: SceneState) -> bool:
	if state == null or state.get_node_count() == 0:
		return false
	var base: SceneState = state.get_base_scene_state()
	if base != null and not _is_display_scene_state(base):
		return false
	for index: int in state.get_node_count():
		var type: StringName = state.get_node_type(index)
		var nested: PackedScene = state.get_node_instance(index)
		if state.is_node_instance_placeholder(index):
			return false
		if nested != null and not _is_display_scene_state(nested.get_state()):
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


func _is_display_only(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is AutolysisInteractionComponent:
		return false
	if node.is_in_group(&"interactable") or node.get_script() != null:
		return false
	for child: Node in node.get_children():
		if not _is_display_only(child):
			return false
	return true
