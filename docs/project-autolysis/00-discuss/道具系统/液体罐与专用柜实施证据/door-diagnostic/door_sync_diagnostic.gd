extends SceneTree
## 三阶段比较，明确物理帧信号在节点物理回调之前发出。

const CABINET: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/cabinet_workroom_0.tscn")
const DIRECTORY: String = "res://docs/project-autolysis/00-discuss/道具系统/液体罐与专用柜实施证据/door-diagnostic"

class LatePhysicsProbe:
	extends Node
	var diagnostic: SceneTree
	func _physics_process(_delta: float) -> void:
		diagnostic.capture("较晚物理回调")
	func _process(_delta: float) -> void:
		diagnostic.capture("较晚普通回调")

var records: Array[Dictionary] = []
var door: AnimatableBody3D
var shape: CollisionShape3D
var mesh: MeshInstance3D
var world: Node3D
var animation: AnimationPlayer
var sample_frame: int = -1
var direction: String = ""
var sample_enabled: bool = false
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var cabinet: Node3D = CABINET.instantiate()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() > 1 and arguments[1] == "disable-sync":
		(cabinet.get_node("cabinet_door_left_root") as AnimatableBody3D).sync_to_physics = false
	world.add_child(cabinet)
	door = cabinet.get_node("cabinet_door_left_root") as AnimatableBody3D
	shape = door.get_node("CollisionShape3D") as CollisionShape3D
	mesh = door.get_node("mesh_cabinet_door_left") as MeshInstance3D
	animation = cabinet.get_node("AnimationPlayer") as AnimationPlayer
	var probe: LatePhysicsProbe = LatePhysicsProbe.new()
	probe.diagnostic = self
	probe.process_physics_priority = 10000
	probe.process_priority = 10000
	world.add_child(probe)
	for _index: int in 3:
		await physics_frame
		await process_frame
	for motion: String in ["打开", "关闭"]:
		direction = motion
		if motion == "打开":
			animation.play(&"open", 0.0)
		else:
			animation.play_backwards(&"open", 0.0)
		sample_enabled = true
		for frame: int in 18:
			sample_frame = frame
			await physics_frame
			capture("物理帧信号恢复点")
			await process_frame
			capture("随后普通帧信号恢复点")
		sample_enabled = false
	var stable_max_error: float = 0.0
	var early_max_error: float = 0.0
	var late_max_error: float = 0.0
	var mismatched_points: int = 0
	var physics_mismatched_points: int = 0
	for record: Dictionary in records:
		match record["阶段"]:
			"物理帧信号恢复点":
				early_max_error = maxf(early_max_error, record["节点与物理误差"])
			"较晚物理回调":
				late_max_error = maxf(late_max_error, record["节点与物理误差"])
				physics_mismatched_points += record["点查询不符数"]
			"随后普通帧信号恢复点":
				stable_max_error = maxf(stable_max_error, record["节点与物理误差"])
				mismatched_points += record["点查询不符数"]
	var physics_verdict: bool = "physics-check" in arguments
	if physics_verdict:
		if late_max_error >= 0.0001 or physics_mismatched_points > 0:
			failures += 1
	elif stable_max_error >= 0.0001 or mismatched_points > 0:
		failures += 1
	var label: String = "baseline"
	if not arguments.is_empty():
		label = arguments[0].validate_filename()
	var result: Dictionary = {"引擎版本": Engine.get_version_info()["string"], "动画时长": animation.get_animation(&"open").length, "物理同步设置": door.sync_to_physics, "动画处理模式": animation.callback_mode_process, "物理帧信号最大误差": early_max_error, "较晚物理回调最大误差": late_max_error, "随后普通帧最大误差": stable_max_error, "随后普通帧点查询不符数": mismatched_points, "较晚物理回调点查询不符数": physics_mismatched_points, "判据": "实际物理回调" if physics_verdict else "原普通帧同步判据", "失败数": failures, "误差定义": "取原点差与三个基向量差长度的最大值，并非全部表示米", "采样": records}
	var file: FileAccess = FileAccess.open(DIRECTORY.path_join(label + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("门同步诊断：失败数=%d；前置信号误差=%f；较晚物理误差=%f；随后普通帧误差=%f；点查询不符=%d" % [failures, early_max_error, late_max_error, stable_max_error, mismatched_points])
	world.free()
	quit(1 if failures else 0)


func capture(stage: String) -> void:
	if not sample_enabled:
		return
	var server_body: Transform3D = PhysicsServer3D.body_get_state(door.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var expected_shape: Transform3D = door.global_transform * shape.transform
	var server_shape: Transform3D = server_body * PhysicsServer3D.body_get_shape_transform(door.get_rid(), 0)
	var missing: int = _missing_points(expected_shape)
	var server_missing: int = _missing_points(server_shape)
	records.append({"方向": direction, "帧": sample_frame, "阶段": stage, "角度": str(door.rotation_degrees), "节点与物理误差": _error(door.global_transform, server_body), "碰撞节点与预期误差": _error(shape.global_transform, expected_shape), "碰撞物理与预期误差": _error(server_shape, expected_shape), "点查询不符数": missing, "物理服务器姿态点查询不符数": server_missing, "门节点姿态": str(door.global_transform), "门物理姿态": str(server_body), "模型姿态": str(mesh.global_transform), "碰撞节点姿态": str(shape.global_transform), "碰撞物理姿态": str(server_shape)})


func _missing_points(expected: Transform3D) -> int:
	var box: BoxShape3D = shape.shape as BoxShape3D
	var query: PhysicsPointQueryParameters3D = PhysicsPointQueryParameters3D.new()
	query.collision_mask = door.collision_layer
	var missing: int = 0
	for y: float in [-0.4, 0.0, 0.4]:
		for z: float in [-0.4, 0.0, 0.4]:
			query.position = expected * (box.size * Vector3(0.0, y, z))
			var found: bool = false
			for hit: Dictionary in world.get_world_3d().direct_space_state.intersect_point(query):
				found = found or hit["collider"] == door
			if not found:
				missing += 1
	return missing


func _error(left: Transform3D, right: Transform3D) -> float:
	return maxf(left.origin.distance_to(right.origin), maxf(left.basis.x.distance_to(right.basis.x), maxf(left.basis.y.distance_to(right.basis.y), left.basis.z.distance_to(right.basis.z))))
