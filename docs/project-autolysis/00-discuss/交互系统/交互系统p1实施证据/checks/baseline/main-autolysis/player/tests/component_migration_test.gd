extends "res://main-autolysis/player/tests/player_smoke_test.gd"

var seen: Node = null
var unseen_count: int = 0

func on_seen(target: Node) -> void:
	seen = target

func on_unseen() -> void:
	seen = null
	unseen_count += 1

func run_checks() -> void:
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(100, 1, 100), Vector3(0, -0.5, 0))
	player = load("res://main-autolysis/player/autolysis_player.tscn").instantiate()
	world.add_child(player)
	await reset_player()
	var ray: RayCast3D = player.interaction_raycast
	var shape: ShapeCast3D = ray.get_node("InteractionShapecast")
	check(ray.get_parent() == player.camera, "交互射线保留原摄像机子节点层级")
	check(ray.target_position == Vector3(0, 0, -2) and ray.collision_mask == 3, "射线距离与碰撞掩码和原项目一致")
	check(shape.target_position == Vector3(0, 0, -2) and shape.collision_mask == 3, "辅助形状检测距离与碰撞掩码一致")
	check(is_equal_approx(shape.shape.radius, 0.075) and is_equal_approx(shape.shape.margin, 0.075) and is_equal_approx(shape.margin, 0.08) and shape.max_results == 16, "辅助形状半径、边距和结果数量一致")
	check(ray.get_node("ShapecastHotspot").position == Vector3(0, 0, -1.5), "检测热点位置一致")
	check(not ray.get_node("RaycastHighlighter").visible and not ray.get_node("TargetHighlighter").visible, "原调试标记节点完整且默认隐藏")
	check(player.camera.get_node("CarryablePosition").position == Vector3(0, 0, -1.8), "搬运定位位置一致")
	var drop: ShapeCast3D = player.item_drop_shapecast
	check(drop == player.camera.get_node("ItemDropShapeCast"), "投放检测节点引用正确")
	check(drop.target_position == Vector3(0, 0, -2) and drop.collision_mask == 3 and drop.shape.size == Vector3(0.1, 0.1, 0.1), "投放检测形状、距离与掩码一致")
	check(player.navigation_agent is NavigationAgent3D, "原导航代理节点已恢复")
	check(player.has_node("DegaussPlayerFoundArea"), "保留原检测体节点名称")
	check(player.mouse_movement.is_connected(player.wieldables.sway), "原鼠标移动到手持物摆动信号已恢复")
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(40, 20)
	player._input(event)
	check(is_equal_approx(player.wieldables.position.x, -40.0 / 3.0 * 0.001) and is_equal_approx(player.wieldables.position.y, 20.0 / 3.0 * 0.001), "原摆动脚本接收原鼠标参数并产生一致偏移")
	await frames(60)
	check(player.wieldables.position.length() < 0.001, "原摆动脚本自动回中")
	await reset_player()
	ray.interactable_seen.connect(on_seen)
	ray.interactable_unseen.connect(on_unseen)
	var target := box(Vector3(0.1, 0.1, 0.1), player.camera.global_position + Vector3(0, 0, -1.2))
	target.collision_layer = 2
	target.add_to_group("interactable")
	await frames(10)
	check(seen == target and ray.is_colliding(), "原射线脚本发现正前方可交互对象")
	target.position = player.camera.global_position + Vector3(0.11, 0, -1.2)
	await frames(10)
	check(seen == target and not ray.is_colliding() and shape.is_colliding(), "原辅助形状检测拾取射线旁目标")
	target.position = Vector3(20, 20, 20)
	await frames(10)
	check(seen == null and unseen_count > 0, "目标离开检测范围时发出原消失信号")
	var destination: Vector3 = drop.get_shapecast_item_drop_position(0.25, 0.2)
	var expected: Vector3 = drop.global_position - 2.25 * player.camera.global_basis.z
	check(destination.is_equal_approx(expected), "投放位置计算使用原脚本逻辑")
	world.queue_free()
	await frames(3)
	print("失败总数：", failures)
	quit(1 if failures else 0)