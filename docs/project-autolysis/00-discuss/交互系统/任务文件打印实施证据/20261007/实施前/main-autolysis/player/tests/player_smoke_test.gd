extends SceneTree

var failures: int = 0
var player: CharacterBody3D
var world: Node3D

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func box(size: Vector3, location: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = location
	return body

func reset_player(location: Vector3 = Vector3(0, 0.9, 0)) -> void:
	for action in ["forward", "back", "left", "right", "sprint", "crouch", "jump", "free_look", "interact_direct"]:
		Input.action_release(action)
	paused = false
	player.is_movement_paused = false
	player.is_showing_ui = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.position = location
	player.velocity = Vector3.ZERO
	player.main_velocity = Vector3.ZERO
	player.direction = Vector3.ZERO
	player.body.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.try_crouch = false
	player._clear_landing_stun()
	await frames(45)

func tap(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(30)

func run_checks() -> void:
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(100, 1, 100), Vector3(0, -0.5, 0))
	player = load("res://main-autolysis/player/autolysis_player.tscn").instantiate()
	world.add_child(player)
	await reset_player()
	check(player.is_on_floor(), "角色稳定着地")
	check(player.camera.current, "摄像机为当前视角")
	check(player.standing_collision_shape.shape.size == Vector3(0.6, 1.7, 0.6), "站立碰撞尺寸与原角色一致")
	check(player.crouching_collision_shape.shape.size == Vector3(0.6, 0.7, 0.6), "蹲伏碰撞尺寸与原角色一致")
	Input.action_press("forward")
	await frames(90)
	check(abs(player.velocity.z + 2.5) < 0.05, "行走速度为每秒二点五米")
	Input.action_press("sprint")
	await frames(90)
	check(abs(player.velocity.z + 4.0) < 0.05, "无体力组件时冲刺速度为每秒四米")
	await reset_player()
	await tap("crouch")
	Input.action_press("forward")
	await frames(60)
	check(player.is_crouching and not player.crouching_collision_shape.disabled and player.standing_collision_shape.disabled, "切换蹲伏并启用矮碰撞体")
	check(abs(player.velocity.z + 2.0) < 0.05, "蹲行速度为每秒两米")
	await tap("crouch")
	check(not player.is_crouching and not player.standing_collision_shape.disabled, "再次按蹲伏键恢复站立")
	await reset_player()
	var start_y: float = player.position.y
	await tap("jump")
	check(not player.enable_jump and not player.enable_slide and abs(player.position.y - start_y) < 0.05, "沿用原场景默认关闭跳跃和滑铲")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(40, 20)
	player._input(mouse)
	check(abs(player.body.rotation.y - deg_to_rad(-10)) < 0.001 and abs(player.head.rotation.x - deg_to_rad(-5)) < 0.001, "鼠标视角灵敏度及方向与原测试场景一致")
	Input.action_press("free_look")
	await frames(2)
	var yaw: float = player.body.rotation.y
	player._input(mouse)
	check(is_equal_approx(player.body.rotation.y, yaw) and abs(player.neck.rotation.y) > 0.01, "自由观察只旋转颈部")
	Input.action_release("free_look")
	await frames(2)
	check(is_zero_approx(player.neck.rotation.y), "退出自由观察时朝向合并回身体")
	await reset_player()
	var wall := box(Vector3(5, 3, 0.5), Vector3(0, 1.5, -2))
	Input.action_press("forward")
	await frames(120)
	check(player.position.z > -1.6, "行走遇墙停止且不穿透")
	wall.queue_free()
	await reset_player()
	var step := box(Vector3(5, 0.2, 4), Vector3(0, 0.1, -3))
	Input.action_press("forward")
	await frames(90)
	check(player.position.z < -1.5 and player.position.y > 0.95, "自动跨上二十厘米台阶")
	step.queue_free()
	await reset_player()
	await tap("crouch")
	var ceiling := box(Vector3(4, 0.2, 4), Vector3(0, 1.25, 0))
	await frames(3)
	await tap("crouch")
	check(player.is_crouching and player.standing_collision_shape.disabled, "低顶阻止站立")
	ceiling.queue_free()
	await frames(40)
	check(not player.is_crouching, "离开低顶后恢复站立")
	await check_shelf_physics()
	world.queue_free()
	await frames(3)
	var scene: Node = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate()
	root.add_child(scene)
	await frames(120)
	var integrated = scene.get_node("autolysis_player")
	check(integrated.is_on_floor(), "默认场景出生点可以稳定着地")
	check(integrated.camera.current, "默认场景使用新玩家摄像机")
	check(scene.get_script() == null, "默认场景不再挂载原框架场景脚本")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var evidence: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://.godot")
		root.get_texture().get_image().save_png(evidence.path_join("player-scene-verification.png"))
	scene.queue_free()
	await frames(2)
	print("失败总数：", failures)
	quit(1 if failures else 0)


func check_shelf_physics() -> void:
	var records: Array[Dictionary] = []
	for scene_path: String in ["res://main-autolysis/scenes/prefabs/prefab_place_shelf/place_shelf_workroom_rm_0.tscn", "res://main-autolysis/scenes/prefabs/prefab_furnitures/store_shelf_warehouse_0.tscn"]:
		await reset_player()
		var shelf: StaticBody3D = load(scene_path).instantiate() as StaticBody3D
		world.add_child(shelf)
		shelf.position = Vector3(0, 0, -2)
		# 原药架半米高度高于可跨台阶，实际玩家持续运动检测应停在架外。
		var start: Vector3 = player.position
		var touched: bool = false
		Input.action_press("forward")
		for frame: int in range(120):
			await frames(1)
			for index: int in range(player.get_slide_collision_count()):
				if player.get_slide_collision(index).get_collider() == shelf:
					touched = true
		Input.action_release("forward")
		check(player.position.z > -1.6 and player.position.z < start.z - 0.3 and touched, "实际物理处理持续行走被整体架体阻挡并记录接触")
		records.append({"架子": scene_path, "起点": str(start), "终点": str(player.position), "接触架体": touched, "物理处理启用": player.is_physics_processing()})
		shelf.queue_free()
		await frames(3)
	await reset_player()
	var step: StaticBody3D = box(Vector3(5, 0.2, 4), Vector3(0, 0.1, -3))
	step.collision_layer = 8
	Input.action_press("forward")
	await frames(60)
	Input.action_release("forward")
	var stair: RayCast3D = player.get_node("StaircheckRayCast3D")
	stair.force_raycast_update()
	check(player.position.z < -1.5 and player.position.y > 0.95 and stair.get_collider() == step, "实际运动跨上第四层台阶且台阶射线命中")
	records.append({"检查": "第四层台阶", "终点": str(player.position), "台阶命中": stair.get_collider() == step})
	step.queue_free()
	await reset_player()
	await tap("crouch")
	var ceiling: StaticBody3D = box(Vector3(4, 0.2, 4), Vector3(0, 1.25, 0))
	ceiling.collision_layer = 8
	await frames(3)
	await tap("crouch")
	check(player.is_crouching and player.crouch_raycast.get_collider() == ceiling, "第四层头顶实体阻止实际玩家起身")
	records.append({"检查": "第四层头顶", "蹲伏": player.is_crouching, "头顶命中": player.crouch_raycast.get_collider() == ceiling})
	ceiling.queue_free()
	await frames(40)
	check(not player.is_crouching, "移除第四层头顶实体后恢复站立")
	await reset_player()
	var target: StaticBody3D = box(Vector3(0.4, 0.4, 0.2), player.camera.global_position + Vector3(0, 0, -1))
	target.collision_layer = 8
	await frames(3)
	player.item_drop_shapecast.force_shapecast_update()
	check(player.item_drop_shapecast.is_colliding() and player.item_drop_shapecast.get_collider(0) == target, "投放形状实际命中第四层实体")
	target.queue_free()
	await frames(3)
	var evidence: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://.godot")
	var file: FileAccess = FileAccess.open(evidence.path_join("shelf-physics.json"), FileAccess.WRITE)
	check(file != null, "保存实际移动与接触记录")
	if file != null:
		file.store_string(JSON.stringify(records, "\t"))
		file.close()
