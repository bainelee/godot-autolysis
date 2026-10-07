extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 正式取筒路径与实际网格视锥复现；只允许无图形，不替换呈现器层级。

const MAIN_SCENE: PackedScene = preload("res://main-autolysis/scenes/01-autolysis-test.tscn")
const USER_POSITION: Vector3 = Vector3(0.33, -0.12, -0.27)
const USER_ROTATION: Vector3 = Vector3(16, 125, 12)
const PLANE_LABELS: PackedStringArray = ["近", "远", "左", "上", "右", "下"]
const PROJECTION_PIXEL_TOLERANCE: float = 0.02

var actor: AutolysisPlayer
var telephone: AutolysisTelephone
var records: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var _pre_focus_projection: Dictionary
var _pre_focus_camera_transform: Transform3D
var _pre_focus_presenter_transform: Transform3D
var _pre_focus_top_level: bool
var _empty_focused_relative: Transform3D
var _user_scale: Vector3
var projection_comparisons: Array[Dictionary] = []
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/手持姿态不可见修正/视野回归")


func check(condition: bool, description: String) -> void:
	super.check(condition, description)
	records.append({"说明": description, "通过": condition})


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		print("失败：本专项只允许无图形运行")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	world = MAIN_SCENE.instantiate()
	player = world.get_node("autolysis_player")
	actor = player as AutolysisPlayer
	telephone = world.get_node("interaction_prefabs/machines/MachineTelephone0/StaticBody3D") as AutolysisTelephone
	root.add_child(world)
	actor.set_physics_process(false)
	# 沿用正式设备专项已验证的合法取筒身体位置，只定位本次玩家实例。
	actor.global_position = Vector3(-9.35, 0.8005, 11)
	actor.is_movement_paused = false
	actor.is_showing_ui = false
	actor._clear_landing_stun()
	# 无图形后端不提供鼠标捕获，替换的仅是原有入聚焦输入后端许可。
	actor.focus_controller.configure(actor, actor.camera, actor.held_item_presenter, _headless_entry_allowed)
	actor.inventory_controller.configure(actor.held_item_presenter, actor._base_input_allowed)
	await frames(3)
	_pre_focus_projection = _capture_projection(actor.camera)
	_pre_focus_camera_transform = actor.camera.global_transform
	_pre_focus_presenter_transform = actor.held_item_presenter.transform
	_pre_focus_top_level = actor.held_item_presenter.top_level
	_user_scale = telephone.handset_held_scale
	check(telephone.handset_held_position.is_equal_approx(USER_POSITION) and telephone.handset_held_rotation_degrees.is_equal_approx(USER_ROTATION), "正式电话保存用户回填的位置与角度")
	check(telephone.root_interaction.try_interact(actor, AutolysisInteractionComponent.InteractionMode.FOCUS), "通过正式电话根交互组件请求进入聚焦")
	if not await _wait_focus(true):
		await _finish()
		return
	_empty_focused_relative = _presenter_relative_transform()
	check(telephone.handset_interaction.try_interact(actor), "通过正式听筒交互组件请求正常取下")
	if not await _wait_transfer():
		await _finish()
		return
	check(actor.inventory_controller.has_exclusive_handset() and telephone.get_holder_session_id() == actor.inventory_controller.get_handset_session_id(), "取下完成后正式电话与库存持有同一会话")
	var display: Node3D = actor.inventory_controller.get_handset_display()
	check(display != null and display.get_parent() == actor.held_item_presenter, "正常取下保留纯模型作为真实呈现器子节点")
	if display == null:
		await _finish()
		return
	check(display.position.is_equal_approx(USER_POSITION) and display.rotation_degrees.is_equal_approx(USER_ROTATION), "实际手持纯模型使用用户回填的局部姿态")
	actor.handset_pose_debug_enabled = false
	actor._sync_handset_pose_panel()
	await frames(2)
	_measure_and_check("聚焦稳定态，工具关闭")
	actor.handset_pose_debug_enabled = true
	actor.handset_pose_debug.test_enabled = true
	actor._sync_handset_pose_panel()
	await frames(2)
	_measure_and_check("聚焦稳定态，工具开启")
	actor.focus_controller.request_exit()
	if not await _wait_focus(false):
		await _finish()
		return
	actor.handset_pose_debug_enabled = false
	actor._sync_handset_pose_panel()
	await frames(2)
	_measure_and_check("退出聚焦后，工具关闭")
	actor.handset_pose_debug_enabled = true
	actor._sync_handset_pose_panel()
	check(actor.set_handset_adjusting(true), "普通持筒状态可通过正式入口启用姿态工具")
	await frames(2)
	_measure_and_check("普通姿态调节，工具开启")
	actor.set_handset_adjusting(false)
	await frames(2)
	_measure_and_check("退出姿态调节后仍持筒")
	_compare_projection(measurements[0], measurements[2], "电话聚焦与退出后普通持筒投影一致")
	_compare_projection(measurements[1], measurements[3], "工具启用时电话聚焦与普通持筒投影一致")
	await _verify_return_and_retake()
	await _finish()


func _headless_entry_allowed() -> bool:
	return actor._base_input_allowed() and not actor.focus_controller.has_control()


func _wait_focus(focused: bool) -> bool:
	for iteration: int in range(120):
		var completed: bool = (actor.focus_controller.state == AutolysisFocusController.FocusState.FOCUSED) if focused else not actor.focus_controller.has_control()
		if completed:
			check(true, "正式聚焦转换完成：" + ("进入" if focused else "退出"))
			return true
		await frames(1)
	check(false, "正式聚焦转换超过专项等待上限")
	return false


func _wait_transfer() -> bool:
	for iteration: int in range(120):
		if not telephone.is_transfer_pending():
			return true
		await frames(1)
	check(false, "正常取筒事务超过专项等待上限")
	return false


func _measure_and_check(stage: String) -> void:
	var measured: Dictionary = _measure(stage)
	measurements.append(measured)
	check(measured["当前相机是玩家相机"], stage + "实际当前相机保持为玩家相机")
	var display: Node3D = actor.inventory_controller.get_handset_display()
	check(display.position.is_equal_approx(USER_POSITION) and display.rotation_degrees.is_equal_approx(USER_ROTATION), stage + "启用或关闭工具没有改变用户局部姿态")
	check(display.scale.is_equal_approx(_user_scale), stage + "保持正式来源配置的纯模型局部缩放")
	if actor.focus_controller.has_control():
		check(_capture_projection(actor.camera) == _capture_projection(telephone.reference_camera), stage + "聚焦实际使用电话参照相机完整投影参数")
	else:
		check(_capture_projection(actor.camera) == _pre_focus_projection and actor.camera.global_transform.is_equal_approx(_pre_focus_camera_transform), stage + "普通玩家相机投影与变换恢复进入聚焦前实际值")
	if measurements.size() == 2:
		check(_presenter_relative_transform().is_equal_approx(_presenter_relative_snapshot), "聚焦时启用工具没有改变呈现器相对相机变换")
	if measurements.size() == 1 or measurements.size() == 3:
		_presenter_relative_snapshot = _presenter_relative_transform()
	if measurements.size() == 4:
		check(_presenter_relative_transform().is_equal_approx(_presenter_relative_snapshot), "普通持筒时启用工具没有改变呈现器相对相机变换")
	check(measured["至少一片实际三角面在完整视锥内"], stage + "正常持筒应至少存在一片落在近远裁剪和侧面视锥内的实际网格三角面")
	print("手持视野测量：", JSON.stringify({"阶段": stage, "网格数": measured["网格数"], "顶点数": measured["顶点数"], "完整视锥内顶点数": measured["完整视锥内顶点数"], "裁剪后有面积三角面数": measured["裁剪后有面积三角面数"], "相机坐标最小": measured["相机坐标最小"], "相机坐标最大": measured["相机坐标最大"], "屏幕投影最小": measured["屏幕投影最小"], "屏幕投影最大": measured["屏幕投影最大"]}))


var _presenter_relative_snapshot: Transform3D


func _presenter_relative_transform() -> Transform3D:
	return actor.camera.get_camera_transform().affine_inverse() * actor.held_item_presenter.global_transform


func _capture_projection(camera: Camera3D) -> Dictionary:
	return {"fov": camera.fov, "size": camera.size, "near": camera.near, "far": camera.far, "projection": camera.projection, "keep_aspect": camera.keep_aspect, "h_offset": camera.h_offset, "v_offset": camera.v_offset, "frustum_offset": camera.frustum_offset}


func _compare_projection(first: Dictionary, second: Dictionary, description: String) -> void:
	var first_meshes: Array = first["网格"]
	var second_meshes: Array = second["网格"]
	var same_shape: bool = first_meshes.size() == second_meshes.size()
	var maximum_error: float = 0
	var count: int = 0
	if same_shape:
		for mesh_index: int in first_meshes.size():
			var first_vertices: Array = first_meshes[mesh_index]["全部实际面顶点"]
			var second_vertices: Array = second_meshes[mesh_index]["全部实际面顶点"]
			if first_vertices.size() != second_vertices.size():
				same_shape = false
				break
			for vertex_index: int in first_vertices.size():
				var first_projected: Array = first_vertices[vertex_index]["屏幕投影"]
				var second_projected: Array = second_vertices[vertex_index]["屏幕投影"]
				var distance: float = Vector2(first_projected[0], first_projected[1]).distance_to(Vector2(second_projected[0], second_projected[1]))
				maximum_error = maxf(maximum_error, distance)
				count += 1
	projection_comparisons.append({"说明": description, "首阶段": first["阶段"], "第二阶段": second["阶段"], "实际面顶点比较数": count, "最大像素误差": maximum_error, "容差像素": PROJECTION_PIXEL_TOLERANCE, "对应网格面结构一致": same_shape})
	check(same_shape and count == first["顶点数"] and maximum_error <= PROJECTION_PIXEL_TOLERANCE, description + "，全部实际面顶点最大屏幕误差不超过0.02像素")
	print("手持投影对照：", JSON.stringify(projection_comparisons.back()))


func _verify_return_and_retake() -> void:
	check(telephone.root_interaction.try_interact(actor, AutolysisInteractionComponent.InteractionMode.FOCUS), "仍持筒时通过正式根入口再次进入同电话聚焦")
	if not await _wait_focus(true):
		return
	await frames(2)
	_measure_and_check("同一持筒会话再次聚焦")
	_compare_projection(measurements[2], measurements.back(), "普通持筒与再次聚焦投影一致")
	check(telephone.handset_interaction.try_interact(actor), "通过正式听筒组件请求归还")
	if not await _wait_transfer():
		return
	await frames(2)
	check(not actor.inventory_controller.has_exclusive_handset() and telephone.get_holder_session_id() == 0 and actor.held_item_presenter.get_display() == null, "正式归还完成清除独占会话和手持纯模型")
	check(actor.held_item_presenter.top_level and _presenter_relative_transform().is_equal_approx(_empty_focused_relative), "聚焦中正式归还后恢复无听筒时相机跟随关系")
	check(telephone.handset_interaction.try_interact(actor), "同电话通过正式听筒组件再次取下")
	if not await _wait_transfer():
		return
	if not actor.inventory_controller.has_exclusive_handset():
		check(false, "再次取下后保持正式独占听筒会话")
		return
	await frames(2)
	_measure_and_check("同电话归还后再次取下")
	_compare_projection(measurements[2], measurements.back(), "首次普通持筒与再次取下聚焦投影一致")
	actor.focus_controller.request_exit()
	if not await _wait_focus(false):
		return
	await frames(2)
	_measure_and_check("再次取下后退出聚焦")
	check(actor.held_item_presenter.transform.is_equal_approx(_pre_focus_presenter_transform) and actor.held_item_presenter.top_level == _pre_focus_top_level, "退出聚焦恢复入焦前呈现器局部变换和独立标记")
	_compare_projection(measurements[2], measurements.back(), "两次取下的普通持筒投影一致")


func _measure(stage: String) -> Dictionary:
	var camera: Camera3D = actor.camera
	var display: Node3D = actor.inventory_controller.get_handset_display()
	var planes: Array[Plane] = camera.get_frustum()
	var camera_inverse: Transform3D = camera.get_camera_transform().affine_inverse()
	var meshes: Array[Dictionary] = []
	var total_vertices: int = 0
	var inside_vertices: int = 0
	var clipped_triangles: int = 0
	var minimum: Vector3 = Vector3(INF, INF, INF)
	var maximum: Vector3 = Vector3(-INF, -INF, -INF)
	var projected_minimum: Vector2 = Vector2(INF, INF)
	var projected_maximum: Vector2 = Vector2(-INF, -INF)
	for node: Node in display.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		var vertices: Array[Dictionary] = []
		var mesh_minimum: Vector3 = Vector3(INF, INF, INF)
		var mesh_maximum: Vector3 = Vector3(-INF, -INF, -INF)
		var mesh_inside: int = 0
		var mesh_clipped: int = 0
		var mesh_near_far: int = 0
		var mesh_forward: int = 0
		var mesh_side_inside: int = 0
		for vertex: Vector3 in faces:
			var global: Vector3 = mesh.to_global(vertex)
			var local: Vector3 = camera_inverse * global
			var depth: float = -local.z
			var inside: bool = camera.is_position_in_frustum(global)
			var near_far: bool = depth >= camera.near and depth <= camera.far
			var side_inside: bool = true
			var distances: Array[float] = []
			for index: int in planes.size():
				distances.append(planes[index].distance_to(global))
				if index >= 2 and planes[index].is_point_over(global):
					side_inside = false
			var projected: Vector2 = camera.unproject_position(global)
			projected_minimum = projected_minimum.min(projected)
			projected_maximum = projected_maximum.max(projected)
			vertices.append({"网格局部": _vector3(vertex), "全局": _vector3(global), "相机局部": _vector3(local), "前向": depth > 0, "通过近远裁剪": near_far, "通过四侧面": side_inside, "完整视锥内": inside, "引擎判定在相机后或近裁剪前": camera.is_position_behind(global), "屏幕投影": [projected.x, projected.y], "六平面有符号距离": distances})
			mesh_minimum = mesh_minimum.min(local)
			mesh_maximum = mesh_maximum.max(local)
			mesh_inside += int(inside)
			mesh_near_far += int(near_far)
			mesh_forward += int(depth > 0)
			mesh_side_inside += int(side_inside)
		for offset: int in range(0, faces.size(), 3):
			var polygon: PackedVector3Array = PackedVector3Array([mesh.to_global(faces[offset]), mesh.to_global(faces[offset + 1]), mesh.to_global(faces[offset + 2])])
			for plane: Plane in planes:
				polygon = _clip_polygon(polygon, plane)
				if polygon.is_empty():
					break
			if polygon.size() >= 3 and _projected_area(polygon, camera) > 0:
				mesh_clipped += 1
		var layer_visible: bool = (mesh.layers & camera.cull_mask) != 0
		meshes.append({"路径": str(mesh.get_path()), "可见属性": mesh.visible, "场景树可见": mesh.is_visible_in_tree(), "相机层可见": layer_visible, "网格类型": mesh.mesh.get_class(), "网格局部包围盒": _aabb(mesh.get_aabb()), "全局变换": _transform(mesh.global_transform), "相机坐标包围范围最小": _vector3(mesh_minimum), "相机坐标包围范围最大": _vector3(mesh_maximum), "面顶点数": faces.size(), "前向顶点数": mesh_forward, "近远裁剪内顶点数": mesh_near_far, "四侧面内顶点数": mesh_side_inside, "完整视锥内顶点数": mesh_inside, "裁剪后有面积三角面数": mesh_clipped, "全部实际面顶点": vertices})
		total_vertices += faces.size()
		inside_vertices += mesh_inside
		if mesh.is_visible_in_tree() and layer_visible:
			clipped_triangles += mesh_clipped
		minimum = minimum.min(mesh_minimum)
		maximum = maximum.max(mesh_maximum)
	var frustum: Array[Dictionary] = []
	for index: int in planes.size():
		frustum.append({"边界": PLANE_LABELS[index], "法向": _vector3(planes[index].normal), "常数": planes[index].d})
	return {"阶段": stage, "持有序号": actor.inventory_controller.get_handset_session_id(), "工具配置开启": actor.handset_pose_debug_enabled, "普通调节模式": actor.is_handset_adjusting(), "聚焦状态": actor.focus_controller.state, "当前相机是玩家相机": camera.get_viewport().get_camera_3d() == camera, "实际当前相机路径": str(camera.get_viewport().get_camera_3d().get_path()), "玩家相机": _camera(camera), "设备参照相机": _camera(telephone.reference_camera), "玩家根全局变换": _transform(actor.global_transform), "呈现器路径": str(actor.held_item_presenter.get_path()), "呈现器父路径": str(actor.held_item_presenter.get_parent().get_path()), "呈现器局部变换": _transform(actor.held_item_presenter.transform), "呈现器全局变换": _transform(actor.held_item_presenter.global_transform), "呈现器相对相机变换": _transform(_presenter_relative_transform()), "纯模型路径": str(display.get_path()), "纯模型可见属性": display.visible, "纯模型场景树可见": display.is_visible_in_tree(), "纯模型局部位置": _vector3(display.position), "纯模型局部角度": _vector3(display.rotation_degrees), "纯模型局部缩放": _vector3(display.scale), "纯模型全局变换": _transform(display.global_transform), "网格数": meshes.size(), "顶点数": total_vertices, "完整视锥内顶点数": inside_vertices, "裁剪后有面积三角面数": clipped_triangles, "至少一片实际三角面在完整视锥内": clipped_triangles > 0, "相机坐标最小": _vector3(minimum), "相机坐标最大": _vector3(maximum), "屏幕投影最小": [projected_minimum.x, projected_minimum.y], "屏幕投影最大": [projected_maximum.x, projected_maximum.y], "世界坐标视锥": frustum, "网格": meshes}


func _clip_polygon(polygon: PackedVector3Array, plane: Plane) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if polygon.is_empty():
		return result
	var previous: Vector3 = polygon[polygon.size() - 1]
	var previous_distance: float = plane.distance_to(previous)
	for current: Vector3 in polygon:
		var current_distance: float = plane.distance_to(current)
		var previous_inside: bool = previous_distance <= 0
		var current_inside: bool = current_distance <= 0
		if previous_inside != current_inside:
			result.append(previous.lerp(current, previous_distance / (previous_distance - current_distance)))
		if current_inside:
			result.append(current)
		previous = current
		previous_distance = current_distance
	return result


func _projected_area(polygon: PackedVector3Array, camera: Camera3D) -> float:
	var area: float = 0
	for index: int in polygon.size():
		var a: Vector2 = camera.unproject_position(polygon[index])
		var b: Vector2 = camera.unproject_position(polygon[(index + 1) % polygon.size()])
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5


func _camera(camera: Camera3D) -> Dictionary:
	return {"路径": str(camera.get_path()), "当前": camera.current, "近裁剪": camera.near, "远裁剪": camera.far, "视场角": camera.fov, "投影类型": camera.projection, "保持轴": camera.keep_aspect, "视口尺寸": [camera.get_viewport().get_visible_rect().size.x, camera.get_viewport().get_visible_rect().size.y], "全局变换": _transform(camera.global_transform), "实际相机变换": _transform(camera.get_camera_transform()), "投影矩阵": str(camera.get_camera_projection())}


func _vector3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _transform(value: Transform3D) -> Dictionary:
	return {"位置": _vector3(value.origin), "基向量横": _vector3(value.basis.x), "基向量纵": _vector3(value.basis.y), "基向量深": _vector3(value.basis.z)}


func _aabb(value: AABB) -> Dictionary:
	return {"位置": _vector3(value.position), "尺寸": _vector3(value.size)}


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("手持实际视野复现.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"规则读取": ["项目规则", "故障诊断技能", "交互领域上下文", "实际原项目装备与摆动"], "输入方式": "无图形；正式根和听筒交互组件；未定位或注入系统指针", "测量用途": "真实网格面顶点及六平面几何判定，仅用于不可见症状验收，不作为生产业务许可", "局限": "无图形几何复现不验证材质照明、遮挡或实际像素输出", "聚焦前实际玩家视场角": _pre_focus_projection.get("fov"), "逐面顶点投影对照": projection_comparisons, "断言": records, "失败": failures, "测量": measurements}, "\t"))
	file.close()
	var playback_references: Array[WeakRef] = []
	for node: Node in world.find_children("*", "AudioStreamPlayer3D", true, false):
		var audio: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		if audio.has_stream_playback():
			playback_references.append(weakref(audio.get_stream_playback()))
		audio.stop()
	world.queue_free()
	actor = null
	telephone = null
	await frames(3)
	var started: int = Time.get_ticks_msec()
	while _audio_alive(playback_references) and Time.get_ticks_msec() - started < 2000:
		await process_frame
	print("手持视野断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)


func _audio_alive(references: Array[WeakRef]) -> bool:
	for reference: WeakRef in references:
		if reference.get_ref() != null:
			return true
	return false
