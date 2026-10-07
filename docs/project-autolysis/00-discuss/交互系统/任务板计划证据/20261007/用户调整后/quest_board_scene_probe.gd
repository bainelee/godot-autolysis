extends SceneTree
## 复测用户保存的独立槽物理体；所有示意纸与层号调整均限于内存实例。

const BOARD_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/quest_board_0.tscn")
const OUTPUT_PATH: String = "res://docs/project-autolysis/00-discuss/交互系统/任务板计划证据/20261007/用户调整后/场景探针结果.json"
const FOCUS_MASK: int = 35
const ORDINARY_MASK: int = 3

var failures: Array[String] = []
var measurements: Dictionary = {}
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


func _ray(target_position: Vector3, mask: int, exclude_board: bool) -> Dictionary:
	var screen_position: Vector2 = focus_camera.unproject_position(target_position)
	var ray_origin: Vector3 = focus_camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + focus_camera.project_ray_normal(screen_position) * 2.0
	var exclusions: Array[RID] = []
	if exclude_board:
		exclusions.append(board.get_rid())
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, mask, exclusions)
	query.hit_from_inside = true
	query.collide_with_areas = false
	var hit: Dictionary = board.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: CollisionObject3D = hit.get("collider") as CollisionObject3D
	var data: Dictionary = {
		"射线起点": _v3(ray_origin), "射线终点": _v3(ray_end),
		"查询掩码": mask, "排除任务板根体": exclude_board, "命中": not hit.is_empty(),
	}
	if collider != null:
		var shape_index: int = hit.get("shape", -1)
		var owner_id: int = collider.shape_find_owner(shape_index)
		var shape_owner: Node = collider.shape_owner_get_owner(owner_id) as Node
		data["碰撞体路径"] = str(collider.get_path())
		data["碰撞体名称"] = str(collider.name)
		data["形状所有者路径"] = str(shape_owner.get_path()) if shape_owner != null else ""
		data["形状所有者名称"] = str(shape_owner.name) if shape_owner != null else ""
		data["命中点"] = _v3(hit.get("position", Vector3.ZERO))
		data["碰撞层"] = collider.collision_layer
		data["碰撞掩码"] = collider.collision_mask
	return data


func _measure_slot(index: int) -> Dictionary:
	var slot: StaticBody3D = board.get_node("quest_paper_slot_%d" % index) as StaticBody3D
	var collision: CollisionShape3D = slot.get_node("collision_quest_paper_slot_%d" % index) as CollisionShape3D
	var screen_position: Vector2 = focus_camera.unproject_position(slot.global_position)
	return {
		"序号": index, "槽体路径": str(slot.get_path()),
		"槽体类型": slot.get_class(), "槽体碰撞层": slot.collision_layer, "槽体碰撞掩码": slot.collision_mask,
		"槽锚点世界位置": _v3(slot.global_position),
		"碰撞形状世界位置": _v3(collision.global_position),
		"碰撞父节点为各自槽体": collision.get_parent() == slot,
		"槽锚点屏幕位置": [screen_position.x, screen_position.y],
		"原场景聚焦掩码不排除根体": _ray(collision.global_position, FOCUS_MASK, false),
		"原场景聚焦掩码排除根体": _ray(collision.global_position, FOCUS_MASK, true),
		"原场景普通掩码不排除根体": _ray(collision.global_position, ORDINARY_MASK, false),
	}


func run_probe() -> void:
	_check(DisplayServer.get_name() == "headless", "显示后端为无图形")
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	probe_viewport = SubViewport.new()
	probe_viewport.name = "任务板用户调整证据视口"
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
	_check(probe_viewport.size == Vector2i(1920, 1080), "采用项目配置1920×1080视口")
	measurements = {
		"说明": "用户调整后独立槽物理体；示意纸删除和层32设置只作用于内存实例；生产场景未修改。",
		"引擎版本": Engine.get_version_info(), "显示后端": DisplayServer.get_name(),
		"物理引擎配置": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"视口尺寸": [probe_viewport.size.x, probe_viewport.size.y],
		"任务板根体碰撞层": board.collision_layer, "任务板根体碰撞掩码": board.collision_mask,
		"聚焦查询掩码": FOCUS_MASK, "普通查询掩码": ORDINARY_MASK,
		"槽位": [],
	}
	for index: int in range(3):
		var data: Dictionary = _measure_slot(index)
		measurements["槽位"].append(data)
		var slot_name: String = "quest_paper_slot_%d" % index
		_check(data["槽体类型"] == "StaticBody3D", "第%d个槽为独立静态物理体" % index)
		_check(data["碰撞父节点为各自槽体"], "第%d个碰撞形状归属各自槽体" % index)
		_check(data["槽体碰撞层"] == 1 and data["槽体碰撞掩码"] == 1, "第%d个槽当前层与掩码均为默认1" % index)
		_check(data["原场景聚焦掩码不排除根体"].get("碰撞体名称", "") == slot_name, "第%d个槽原场景聚焦掩码实际命中槽体" % index)
		_check(data["原场景聚焦掩码排除根体"].get("碰撞体名称", "") == slot_name, "第%d个槽原场景排除板根后仍实际命中槽体" % index)
		_check(data["原场景普通掩码不排除根体"].get("碰撞体名称", "") == slot_name, "第%d个槽当前默认层也被普通掩码3实际命中" % index)
	for index: int in range(3):
		var slot: StaticBody3D = board.get_node("quest_paper_slot_%d" % index) as StaticBody3D
		slot.get_node("quest_paper_%d" % index).free()
	await physics_frame
	await physics_frame
	for index: int in range(3):
		var slot: StaticBody3D = board.get_node("quest_paper_slot_%d" % index) as StaticBody3D
		var collision: CollisionShape3D = slot.get_node("collision_quest_paper_slot_%d" % index) as CollisionShape3D
		var data: Dictionary = measurements["槽位"][index]
		data["空槽聚焦掩码排除根体"] = _ray(collision.global_position, FOCUS_MASK, true)
		data["空槽普通掩码不排除根体"] = _ray(collision.global_position, ORDINARY_MASK, false)
		_check(data["空槽聚焦掩码排除根体"].get("碰撞体名称", "") == str(slot.name), "第%d个空槽排除板根后聚焦掩码35仍命中槽体" % index)
		_check(data["空槽普通掩码不排除根体"].get("碰撞体名称", "") == str(slot.name), "第%d个空槽默认层被普通掩码3实际命中" % index)
		slot.collision_layer = 32
	await physics_frame
	await physics_frame
	for index: int in range(3):
		var slot: StaticBody3D = board.get_node("quest_paper_slot_%d" % index) as StaticBody3D
		var collision: CollisionShape3D = slot.get_node("collision_quest_paper_slot_%d" % index) as CollisionShape3D
		var data: Dictionary = measurements["槽位"][index]
		data["内存层32槽体碰撞层"] = slot.collision_layer
		data["内存层32槽体碰撞掩码"] = slot.collision_mask
		data["内存层32聚焦掩码排除根体"] = _ray(collision.global_position, FOCUS_MASK, true)
		data["内存层32普通掩码不排除根体"] = _ray(collision.global_position, ORDINARY_MASK, false)
		data["内存层32普通掩码排除根体"] = _ray(collision.global_position, ORDINARY_MASK, true)
		_check(data["内存层32聚焦掩码排除根体"].get("碰撞体名称", "") == str(slot.name), "第%d个层32空槽仍被聚焦掩码35命中" % index)
		_check(data["内存层32普通掩码不排除根体"].get("碰撞体名称", "") != str(slot.name), "第%d个层32空槽不被普通掩码3命中" % index)
		_check(not data["内存层32普通掩码排除根体"]["命中"], "第%d个层32空槽排除板根后普通掩码3无命中" % index)
	measurements["失败项"] = failures
	measurements["退出码"] = 0 if failures.is_empty() else 1
	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法保存调整后场景探针结果。")
		quit(2)
		return
	file.store_string(JSON.stringify(measurements, "\t"))
	file.close()
	print("调整后探针结果已保存；失败项数量：%d" % failures.size())
	probe_viewport.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
