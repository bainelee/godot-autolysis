extends SceneTree
## 对照节点姿态与物理服务器实际碰撞，不能用父子变换恒等式替代物理验证。

const MACHINE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/machine_blend_0.tscn")
const PLAYER: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
var evidence: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/聚焦碰撞跟随修复证据")
var failures: int = 0
var records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	print(("通过：" if condition else "失败：") + message)
	if not condition:
		failures += 1


func _frames(count: int) -> void:
	for _index: int in count:
		await physics_frame
		await process_frame


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var machine: AutolysisBlendMachine = MACHINE.instantiate()
	world.add_child(machine)
	var player: AutolysisPlayer = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.focus_controller.configure(player, player.camera, player.held_item_presenter, func() -> bool: return true)
	_check(machine.focus_target.is_valid_target(), "正式设备与四槽配置有效")
	if not machine.focus_target.is_valid_target():
		world.free()
		quit(1)
		return
	_check(player.focus_controller.try_enter(machine.focus_target), "通过正式会话建立测试聚焦")
	await _frames(18)
	var locals: Array[Transform3D] = []
	for slot: AutolysisBlendSlot in machine.slots:
		locals.append(slot.raw_material_anchor.transform)
	for direction: String in ["打开", "关闭"]:
		for slot: AutolysisBlendSlot in machine.slots:
			_check(slot.toggle_interaction.try_interact(player), "通过正式组件" + direction + "槽位")
		var max_node_error: float = 0.0
		var max_physics_error: float = 0.0
		var mismatched_points: int = 0
		for frame: int in 18:
			await _frames(1)
			for index: int in 4:
				var slot: AutolysisBlendSlot = machine.slots[index]
				var inner: PhysicsBody3D = slot.raw_material_anchor as PhysicsBody3D
				var expected_body: Transform3D = slot.global_transform * locals[index]
				var server_body: Transform3D = PhysicsServer3D.body_get_state(inner.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
				var node_error: float = _error(inner.global_transform, expected_body)
				var physics_error: float = _error(server_body, expected_body)
				max_node_error = maxf(max_node_error, node_error)
				max_physics_error = maxf(max_physics_error, physics_error)
				var shape: CollisionShape3D = inner.get_node("collision_rm_place_slot_%d" % index)
				var expected_shape: Transform3D = expected_body * shape.transform
				var point_failures: int = _point_mismatches(world, machine, player, inner, expected_shape, shape.shape as BoxShape3D)
				mismatched_points += point_failures
				records.append({"方向": direction, "帧": frame, "槽位": index, "槽位旋转": str(slot.rotation), "节点误差": node_error, "物理误差": physics_error, "点查询不符数": point_failures, "节点变换": str(inner.global_transform), "物理变换": str(server_body)})
		_check(max_node_error < 0.0001, direction + "全过程取放节点姿态跟随槽位")
		_check(max_physics_error < 0.0001, direction + "全过程物理服务器实际碰撞姿态跟随槽位，最大误差=%f" % max_physics_error)
		_check(mismatched_points == 0, direction + "全过程预期碰撞盒内部采样点均命中实际取放体，不符数=%d" % mismatched_points)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence))
	var file: FileAccess = FileAccess.open(evidence.path_join("collision-follow.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"失败数": failures, "采样": records}, "\t"))
	world.free()
	quit(1 if failures else 0)


func _point_mismatches(world: Node3D, machine: AutolysisBlendMachine, player: AutolysisPlayer, inner: PhysicsBody3D, expected: Transform3D, shape: BoxShape3D) -> int:
	var excluded: Array[RID] = [machine.get_rid(), player.get_rid(), player._found_area.get_rid()]
	for slot: AutolysisBlendSlot in machine.slots:
		excluded.append(slot.get_rid())
		if slot.raw_material_anchor != inner:
			excluded.append((slot.raw_material_anchor as PhysicsBody3D).get_rid())
	var query: PhysicsPointQueryParameters3D = PhysicsPointQueryParameters3D.new()
	query.collision_mask = 32
	query.exclude = excluded
	var missing: int = 0
	for y: float in [-0.4, 0.0, 0.4]:
		for z: float in [-0.4, 0.0, 0.4]:
			query.position = expected * (shape.size * Vector3(0.0, y, z))
			var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_point(query)
			var found: bool = false
			for hit: Dictionary in hits:
				found = found or hit["collider"] == inner
			if not found:
				missing += 1
	return missing


func _error(a: Transform3D, b: Transform3D) -> float:
	return maxf(a.origin.distance_to(b.origin), maxf(a.basis.x.distance_to(b.basis.x), maxf(a.basis.y.distance_to(b.basis.y), a.basis.z.distance_to(b.basis.z))))
