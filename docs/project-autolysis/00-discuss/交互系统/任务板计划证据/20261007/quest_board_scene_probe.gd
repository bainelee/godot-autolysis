extends SceneTree
## 任务板独立场景、真实物理射线与屏幕投影探针。只在内存移除示意纸。

const BOARD_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/quest_board_0.tscn")
const OUTPUT_PATH: String = "res://docs/project-autolysis/00-discuss/交互系统/任务板计划证据/20261007/场景探针结果.json"
const FOCUS_MASK: int = 35

var measurements: Dictionary = {}
var failures: Array[String] = []
var probe_viewport: SubViewport
var board: StaticBody3D
var focus_camera: Camera3D


func _initialize() -> void:
	call_deferred("run_probe")


func _check(condition: bool, description: String) -> void:
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures.append(description)


func _v3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _v2(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _ray(target_position: Vector3, exclude_board: bool) -> Dictionary:
	var screen_position: Vector2 = focus_camera.unproject_position(target_position)
	var ray_origin: Vector3 = focus_camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + focus_camera.project_ray_normal(screen_position) * 2.0
	var exclusions: Array[RID] = []
	if exclude_board:
		exclusions.append(board.get_rid())
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, FOCUS_MASK, exclusions)
	query.hit_from_inside = true
	query.collide_with_areas = false
	var hit: Dictionary = board.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: CollisionObject3D = hit.get("collider") as CollisionObject3D
	var measurement: Dictionary = {
		"屏幕坐标": _v2(screen_position),
		"射线起点": _v3(ray_origin),
		"射线终点": _v3(ray_end),
		"查询掩码": FOCUS_MASK,
		"排除任务板根体": exclude_board,
		"命中": not hit.is_empty(),
	}
	if collider != null:
		var shape_index: int = hit.get("shape", -1)
		var owner_id: int = collider.shape_find_owner(shape_index)
		var shape_owner: Node = collider.shape_owner_get_owner(owner_id) as Node
		measurement["碰撞体路径"] = str(collider.get_path())
		measurement["碰撞体名称"] = str(collider.name)
		measurement["碰撞形状索引"] = shape_index
		measurement["形状所有者路径"] = str(shape_owner.get_path()) if shape_owner != null else ""
		measurement["形状所有者名称"] = str(shape_owner.name) if shape_owner != null else ""
		measurement["命中点"] = _v3(hit.get("position", Vector3.ZERO))
		measurement["命中法线"] = _v3(hit.get("normal", Vector3.ZERO))
		measurement["碰撞层"] = collider.collision_layer
		measurement["碰撞掩码"] = collider.collision_mask
	return measurement


func _slot_measurement(index: int) -> Dictionary:
	var anchor: Node3D = board.get_node("quest_paper_slot_%d" % index) as Node3D
	var collision: CollisionShape3D = board.get_node("collision_quest_paper_slot_%d" % index) as CollisionShape3D
	var paper: StaticBody3D = anchor.get_child(0) as StaticBody3D
	var screen_position: Vector2 = focus_camera.unproject_position(anchor.global_position)
	var paper_corners: Array[Dictionary] = []
	for x_offset: float in [-0.18, 0.18]:
		for y_offset: float in [-0.24, 0.24]:
			var corner_world: Vector3 = anchor.to_global(Vector3(x_offset, y_offset, 0.01))
			var corner_screen: Vector2 = focus_camera.unproject_position(corner_world)
			paper_corners.append({
				"世界位置": _v3(corner_world),
				"屏幕位置": _v2(corner_screen),
				"视口内": Rect2(Vector2.ZERO, Vector2(probe_viewport.size)).has_point(corner_screen),
			})
	return {
		"序号": index,
		"锚点路径": str(anchor.get_path()),
		"锚点世界位置": _v3(anchor.global_position),
		"碰撞路径": str(collision.get_path()),
		"碰撞世界位置": _v3(collision.global_position),
		"碰撞父节点为根体": collision.get_parent() == board,
		"碰撞形状尺寸": _v3((collision.shape as BoxShape3D).size),
		"示意纸世界位置": _v3(paper.global_position),
		"示意纸碰撞层": paper.collision_layer,
		"示意纸碰撞掩码": paper.collision_mask,
		"锚点屏幕投影": _v2(screen_position),
		"锚点位于相机后方": focus_camera.is_position_behind(anchor.global_position),
		"锚点位于视口内": Rect2(Vector2.ZERO, Vector2(probe_viewport.size)).has_point(screen_position),
		"示意纸四角屏幕投影": paper_corners,
		"原场景射线": _ray(collision.global_position, false),
		"原场景排除根体射线": _ray(collision.global_position, true),
	}


func run_probe() -> void:
	_check(DisplayServer.get_name() == "headless", "显示后端为无图形；未建立图形窗口")
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	probe_viewport = SubViewport.new()
	probe_viewport.name = "任务板证据视口"
	probe_viewport.size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	probe_viewport.own_world_3d = true
	root.add_child(probe_viewport)
	board = BOARD_SCENE.instantiate() as StaticBody3D
	probe_viewport.add_child(board)
	focus_camera = board.get_node("focus_camera") as Camera3D
	focus_camera.make_current()
	await physics_frame
	await physics_frame
	measurements = {
		"说明": "原始预制体在独立三维世界实例化；未载入主场景；未保存或修改生产场景。示意纸只在本次内存实例移除。",
		"引擎版本": Engine.get_version_info(),
		"显示后端": DisplayServer.get_name(),
		"项目物理引擎配置": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"物理射线实现参考": "res://main-autolysis/player/components/autolysis_focus_ray_query.gd",
		"视口尺寸来源": "project.godot（项目配置）第27至28行",
		"视口尺寸": [probe_viewport.size.x, probe_viewport.size.y],
		"任务板根体类型": board.get_class(),
		"任务板根体碰撞层": board.collision_layer,
		"任务板根体碰撞掩码": board.collision_mask,
		"相机世界位置": _v3(focus_camera.global_position),
		"相机视场角": focus_camera.fov,
		"相机保持轴": focus_camera.keep_aspect,
		"槽位": [],
	}
	_check(probe_viewport.size == Vector2i(1920, 1080), "投影视口采用项目配置1920×1080")
	for index: int in range(3):
		var slot_measurement: Dictionary = _slot_measurement(index)
		measurements["槽位"].append(slot_measurement)
		_check(slot_measurement["碰撞父节点为根体"], "第%d个槽位形状归属任务板根物理体" % index)
		_check(slot_measurement["原场景射线"].get("碰撞体名称", "") == "quest_board_0", "第%d个槽位原始射线命中任务板根物理体" % index)
		_check(slot_measurement["原场景射线"].get("形状所有者名称", "") == "collision_quest_paper_slot_%d" % index, "第%d个槽位原始射线实际命中对应槽位形状" % index)
		_check(slot_measurement["原场景排除根体射线"].get("碰撞体名称", "") == "quest_paper_%d" % index, "第%d个槽位排除根体后实际命中示意纸" % index)
		_check(slot_measurement["锚点位于视口内"] and not slot_measurement["锚点位于相机后方"], "第%d个槽位锚点在聚焦相机可见投影范围内" % index)
	measurements["板面独立区域原始射线"] = _ray(Vector3(0.0, 0.645, 0.065), false)
	_check(measurements["板面独立区域原始射线"].get("形状所有者名称", "") == "collision_board", "板面独立区域射线命中板面形状")
	for index: int in range(3):
		var anchor: Node3D = board.get_node("quest_paper_slot_%d" % index) as Node3D
		anchor.get_child(0).free()
	await physics_frame
	await physics_frame
	for index: int in range(3):
		var collision: CollisionShape3D = board.get_node("collision_quest_paper_slot_%d" % index) as CollisionShape3D
		var slot_measurement: Dictionary = measurements["槽位"][index]
		slot_measurement["空槽原始射线"] = _ray(collision.global_position, false)
		slot_measurement["空槽排除根体射线"] = _ray(collision.global_position, true)
		_check(slot_measurement["空槽原始射线"].get("形状所有者名称", "") == "collision_quest_paper_slot_%d" % index, "第%d个空槽仍命中根体所属槽位形状" % index)
		_check(not slot_measurement["空槽排除根体射线"]["命中"], "第%d个空槽在排除根物理体后没有可命中的独立槽体" % index)
	measurements["失败项"] = failures
	measurements["退出码"] = 0 if failures.is_empty() else 1
	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法保存场景探针结果。")
		quit(2)
		return
	file.store_string(JSON.stringify(measurements, "\t"))
	file.close()
	print("结果已保存至任务板计划证据目录；失败项数量：%d" % failures.size())
	probe_viewport.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
