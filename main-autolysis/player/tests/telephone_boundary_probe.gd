extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 原场景单墙诊断：保留正式玩家碰撞与房间固定体，以实际运动记录绕行路径。

var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/boundary-map")
var records: Array[Dictionary] = []
var maps: Array[Dictionary] = []


func run_checks() -> void:
	world = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate()
	root.add_child(world)
	player = world.get_node("autolysis_player")
	player.set_physics_process(false)
	var phone: AutolysisTelephone = world.get_node("interaction_prefabs/machines/MachineTelephone0/StaticBody3D")
	await frames(3)
	check(phone.move_limit_shape.shape is BoxShape3D and phone.move_limit_shape.shape.size.is_equal_approx(Vector3(0.12, 1.7, 2)), "诊断来源为修改前实际单墙资产")
	phone.move_limit_shape.set_deferred("disabled", false)
	await frames(2)
	player.global_position = Vector3(-9.35, 0.8005, 11)
	player.velocity = Vector3.ZERO
	var start: Vector3 = player.global_position
	for motion: Vector3 in [Vector3(0, 0, -0.1), Vector3(0.1, 0, 0)]:
		for index: int in 20:
			var collision: KinematicCollision3D = player.move_and_collide(motion)
			records.append({"位置": [player.global_position.x, player.global_position.y, player.global_position.z], "局部位置": [phone.to_local(player.global_position).x, phone.to_local(player.global_position).y, phone.to_local(player.global_position).z], "运动": [motion.x, motion.y, motion.z], "碰撞来源": str(collision.get_collider().get_path()) if collision != null else ""})
			await frames(1)
	check(player.global_position.z > 10.0 and player.global_position.x < -8.9, "正式玩家预设绕南端路径受到实际固定墙和限位阻挡")
	for crouched: bool in [false, true]:
		player.standing_collision_shape.set_deferred("disabled", crouched)
		player.crouching_collision_shape.set_deferred("disabled", not crouched)
		await frames(2)
		for yaw_degrees: float in [0.0, 45.0, 80.0, 90.0]:
			var active_basis: Basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees))
			var origin: Vector3 = Vector3(-9.35, 0.8005, 11)
			var queue: Array[Vector2i] = [Vector2i.ZERO]
			var seen: Dictionary = {Vector2i.ZERO: true}
			var blocked_sources: Dictionary = {}
			var escaped: bool = false
			var extent_min: Vector2 = Vector2(origin.x, origin.z)
			var extent_max: Vector2 = extent_min
			var cursor: int = 0
			while cursor < queue.size():
				var cell: Vector2i = queue[cursor]
				cursor += 1
				var position_value: Vector3 = origin + Vector3(cell.x * 0.1, 0, cell.y * 0.1)
				extent_min = extent_min.min(Vector2(position_value.x, position_value.z))
				extent_max = extent_max.max(Vector2(position_value.x, position_value.z))
				if absf(cell.x) > 40 or absf(cell.y) > 40:
					escaped = true
					break
				for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
					var next: Vector2i = cell + direction
					if seen.has(next):
						continue
					var motion_query: KinematicCollision3D = KinematicCollision3D.new()
					if player.test_move(Transform3D(active_basis, position_value), Vector3(direction.x * 0.1, 0, direction.y * 0.1), motion_query):
						var blocker: Node = motion_query.get_collider() as Node
						if is_instance_valid(blocker):
							blocked_sources[str(blocker.get_path())] = true
						continue
					seen[next] = true
					queue.append(next)
			maps.append({"蹲伏": crouched, "身体朝向度": yaw_degrees, "可到达点数": queue.size(), "最小水平坐标": [extent_min.x, extent_min.y], "最大水平坐标": [extent_max.x, extent_max.y], "阻挡来源": blocked_sources.keys(), "存在离开通道": escaped})
			check(not escaped and queue.size() > 10, "实际主场景%s姿态%s度的八向运动连通搜索无离开通道且保留内部移动" % ["蹲伏" if crouched else "站立", yaw_degrees])
	var directory: String = ProjectSettings.globalize_path(evidence_directory)
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(directory.path_join("原单墙绕行.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"起始位置": [start.x, start.y, start.z], "终止位置": [player.global_position.x, player.global_position.y, player.global_position.z], "墙位置": [phone.move_limit_shape.global_position.x, phone.move_limit_shape.global_position.y, phone.move_limit_shape.global_position.z], "墙尺寸": [phone.move_limit_shape.shape.size.x, phone.move_limit_shape.shape.size.y, phone.move_limit_shape.shape.size.z], "预设路径轨迹": records, "连通搜索": maps, "失败数": failures}, "\t"))
	world.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
