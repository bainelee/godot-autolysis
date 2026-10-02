extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 正式预制体、玩家、中心射线与鼠标事件的液体罐验收。

const CABINET_PATH: String = "res://main-autolysis/scenes/prefabs/prefab_place_shelf/cabinet_workroom_0.tscn"
const TANK_PATH: String = "res://main-autolysis/scenes/prefabs/prefab_machines/liquid_tank_0.tscn"
const LIQUID: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/liquid_tank.tres")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")

var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/液体罐与专用柜实施证据/checks/rendered")
var cabinet: AutolysisLiquidTankCabinet
var inventory: AutolysisInventoryController
var assertions: Array[Dictionary] = []
var rays: Array[Dictionary] = []
var _rendered: bool = false


func check(condition: bool, description: String) -> void:
	super.check(condition, description)
	assertions.append({"说明": description, "通过": condition})


func run_checks() -> void:
	_rendered = DisplayServer.get_name() != "headless"
	if not _rendered:
		push_error("真实鼠标捕获与玩家许可检查需要实际图形后端。")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	Input.use_accumulated_input = false
	await _fixture()
	await _test_cycle()
	await _test_gate_and_occlusion()
	await _test_body_collision()
	await _test_main_scene()
	_save_report()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.queue_free()
	await frames(2)
	print("液体罐真实输入检查断言数：", assertions.size(), "；失败：", failures)
	quit(1 if failures else 0)


func _fixture() -> void:
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(30, 1, 30), Vector3(0, -0.5, 0))
	_add_lighting()
	cabinet = load(CABINET_PATH).instantiate() as AutolysisLiquidTankCabinet
	world.add_child(cabinet)
	player = load("res://main-autolysis/player/autolysis_player.tscn").instantiate()
	world.add_child(player)
	await reset_player(Vector3(-0.58, 0.9, 1.8))
	player.set_physics_process(false)
	inventory = player.get_node("InventoryController") as AutolysisInventoryController
	check(cabinet.get_slot_count() == 2 and _stored_count() == 2, "正式柜初始恰有两个槽与两个罐")
	check(not cabinet.is_open() and inventory.get_focused_item() == null, "初始关门且当前道具格为空")
	check(cabinet.owns_item(cabinet.get_item_at_slot(0)) and cabinet.owns_item(cabinet.get_item_at_slot(1)), "现有两个罐登记双向归属且未重复生成")
	_record("初始输入许可")


func _add_lighting() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.13, 0.17)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -25, 0)
	key.light_energy = 1.2
	world.add_child(key)


func _button(button: MouseButton, pressed: bool = true) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT and pressed else 0
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(2)


func _click() -> void:
	await _button(MOUSE_BUTTON_LEFT)
	await _button(MOUSE_BUTTON_LEFT, false)


func _aim(point: Vector3) -> void:
	player.body.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.head.look_at(point, Vector3.UP)
	await frames(4)


func _front() -> void:
	player.global_position = cabinet.to_global(Vector3(-0.58, 0.9, 1.8))
	player.velocity = Vector3.ZERO
	player.main_velocity = Vector3.ZERO
	await frames(3)


func _door_shape() -> CollisionShape3D:
	return cabinet.get_node("cabinet_door_left_root/CollisionShape3D") as CollisionShape3D


func _aim_door() -> void:
	await _aim(_door_shape().global_position)
	_record("瞄准柜门")
	check(player.interaction_raycast.get_collider() == _door_shape().get_parent(), "中心射线实际命中柜门物理体")


func _aim_place() -> void:
	await _aim(cabinet.to_global(Vector3(-0.58, 0.30, 0.85)))
	_record("瞄准柜内放置区")


func _test_cycle() -> void:
	await _aim_door()
	await _capture("01-关闭双罐.png")
	await _click()
	check(cabinet.is_animating() and not cabinet.is_open(), "一次左键开始开门但尚未允许取放")
	var rotation_before: Vector3 = _door_shape().get_parent().rotation
	paused = true
	await frames(8)
	check(_door_shape().get_parent().rotation.is_equal_approx(rotation_before), "开门中暂停保持实际门姿态")
	await _click()
	check(not cabinet.is_open() and _stored_count() == 2, "暂停期间左键不转移液体罐")
	paused = false
	await frames(20)
	check(cabinet.is_open(), "恢复后打开动画自然结束并开放取放")
	check(absf(_door_shape().get_parent().rotation.x - deg_to_rad(75)) < 0.002, "打开终态保留现有横轴七十五度")
	await _capture("02-打开双罐.png")
	var one: AutolysisLiquidTank = cabinet.get_item_at_slot(1)
	await _aim(one.global_position)
	_record("指定一号罐")
	check(player.interaction_raycast.get_collider() == one and player.interaction_controller.is_direct_available(), "空手真实射线穿过柜体只选择一号罐")
	paused = true
	await _click()
	check(cabinet.get_item_at_slot(1) == one and inventory.get_focused_item() == null, "完全打开后暂停点击指定罐不转移来源")
	paused = false
	await frames(3)
	check(cabinet.get_item_at_slot(1) == one and inventory.get_focused_item() == null, "恢复后不补执行暂停期间的点击")
	await _click()
	check(cabinet.get_item_at_slot(1) == null and cabinet.get_item_at_slot(0) != null and inventory.get_focused_item() == LIQUID, "一号罐进入当前格且零号保留")
	check(player.interaction_raycast.collision_mask == 67 and _pure_visual(player.held_item_presenter.get_display()), "拾取后使用掩码六十七且手持仅为纯显示")
	await _capture("03-指定取回手持.png")
	await _aim_place()
	await _click()
	check(_stored_count() == 2 and inventory.get_focused_item() == null, "只空出一号时实际放回一号槽")
	check(player.interaction_raycast.collision_mask == 3, "放入成功后恢复空手掩码三")
	await _aim(cabinet.get_item_at_slot(0).global_position)
	await _click()
	check(cabinet.get_item_at_slot(0) == null and inventory.get_slot_item(0) == LIQUID, "指定零号罐进入第一格")
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	check(inventory.get_focused_index() == 1 and inventory.get_focused_item() == null, "真实滚轮切换第二空格")
	await _aim(cabinet.get_item_at_slot(1).global_position)
	await _click()
	check(_stored_count() == 0 and inventory.get_slot_item(0) == LIQUID and inventory.get_slot_item(1) == LIQUID, "两个同类罐分别占两格且柜子为空")
	await _capture("04-空柜携带两罐.png")
	await _aim_place()
	await _click()
	check(cabinet.get_item_at_slot(0) != null and cabinet.get_item_at_slot(1) == null, "两槽为空时首先补入零号")
	await _button(MOUSE_BUTTON_WHEEL_UP)
	await _aim_place()
	await _click()
	check(_stored_count() == 2 and _inventory_count() == 0, "第二次放回一号且有限两罐总数守恒")
	await _capture("05-放回双罐.png")
	var third: AutolysisLiquidTank = load(TANK_PATH).instantiate() as AutolysisLiquidTank
	world.add_child(third)
	third.position = Vector3(-2.0, 0.65, 0.65)
	player.position = Vector3(-2.0, 0.9, 1.8)
	await _aim(third.global_position)
	check(player.interaction_raycast.get_collider() == third, "额外有限世界罐通过真实射线选中")
	await _click()
	check(inventory.get_focused_item() == LIQUID and (not is_instance_valid(third) or third.is_queued_for_deletion()), "柜外独立罐通过左键进入道具栏")
	await _front()
	await _aim_place()
	check(not player.interaction_controller.is_direct_available(), "两槽满载持第三罐时提示不可放入")
	await _click()
	check(_stored_count() == 2 and _inventory_count() == 1 and inventory.get_focused_item() == LIQUID, "满载拒绝第三罐且来源保留")
	_record("满柜拒绝第三罐")
	await _capture("06-满柜拒绝第三罐.png")
	await _aim_door()
	await _click()
	check(cabinet.is_animating() and not cabinet.is_open(), "持罐点击打开的门只开始关闭")
	await frames(20)
	check(not cabinet.is_open() and not cabinet.is_animating() and _door_shape().get_parent().rotation.is_zero_approx(), "倒放结束恢复实际关门零度")
	check(_stored_count() == 2 and _inventory_count() == 1, "关门不改变三个有限罐的占用")
	await _capture("07-持罐关闭.png")


func _test_gate_and_occlusion() -> void:
	var stored: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	check(inventory.get_focused_item() == null, "切空格后仍保留其他格第三罐")
	check(not inventory.can_take_liquid_tank(player, stored) and not inventory.try_take_liquid_tank(player, stored), "当前格为空时关闭门禁仍同时拒绝查询和执行")
	check(_stored_count() == 2 and inventory.get_focused_item() == null and _inventory_count() == 1, "关门业务拒绝保持两个来源罐及其他格第三罐")
	player.global_position = cabinet.to_global(Vector3(-0.85, 0.9, -0.9))
	await _aim(stored.global_position)
	_record("关门背面瞄准")
	check(not player.interaction_controller.is_direct_available(), "从背面瞄准柜内罐仍受门禁")
	await _click()
	check(_stored_count() == 2 and inventory.get_focused_item() == null, "背面点击不能绕过关闭门取罐")
	await _front()
	await _aim_door()
	await _click()
	await frames(20)
	check(cabinet.is_open(), "空手再次通过真实柜门交互打开")
	var blocker: StaticBody3D = box(Vector3(0.4, 2, 0.04), cabinet.to_global(Vector3(-0.85, 0.8, 1.2)))
	await _aim(stored.global_position)
	_record("普通墙体遮挡")
	check(player.interaction_raycast.get_collider() == blocker and not player.interaction_controller.is_direct_available(), "普通实体首命中不向后补选罐")
	await _click()
	check(cabinet.owns_item(stored), "实体阻挡后的点击保留柜内罐")
	blocker.queue_free()
	await frames(3)
	player.global_position = cabinet.to_global(Vector3(-0.85, 0.9, 4.0))
	await _aim(stored.global_position)
	check(not player.interaction_controller.is_direct_available(), "超过两单位距离不可拾取")
	await _front()
	check(inventory.try_receive_item(CAFFEINE), "类型排斥检查准备当前格原药")
	await _aim_place()
	check(player.interaction_raycast.collision_mask == 19 and player.interaction_raycast.get_collider() != cabinet.placement_body, "手持原药保持掩码十九且不检测液体罐放置体")
	await _aim_door()
	await _click()
	await frames(20)
	check(not cabinet.is_open(), "手持原药仍可通过真实柜门交互关闭")


func _test_body_collision() -> void:
	player.set_physics_process(true)
	await reset_player(Vector3(-2.5, 0.9, 0.5))
	var touched: bool = false
	Input.action_press("right")
	for _index: int in range(65):
		await frames(1)
		for collision_index: int in range(player.get_slide_collision_count()):
			if player.get_slide_collision(collision_index).get_collider() == cabinet:
				touched = true
	Input.action_release("right")
	check(touched and player.position.x < -1.4, "正式玩家侧向行走仍被第四层柜体阻挡")
	player.set_physics_process(false)


func _test_main_scene() -> void:
	world.queue_free()
	await frames(3)
	world = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate() as Node3D
	root.add_child(world)
	await frames(8)
	player = world.get_node("autolysis_player") as AutolysisPlayer
	player.set_physics_process(false)
	inventory = player.get_node("InventoryController") as AutolysisInventoryController
	cabinet = world.get_node("interaction_prefabs/place_shelf_and_cabinet/cabinet_workroom_0") as AutolysisLiquidTankCabinet
	check(cabinet != null and _stored_count() == 2, "真实主场景继承柜子与两罐初始占用")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player._clear_landing_stun()
	player.is_movement_paused = false
	player.is_showing_ui = false
	await _front()
	await _aim_door()
	await _click()
	await frames(20)
	check(cabinet.is_open(), "实际主场景左键打开现有柜门")
	await _capture("08-主场景打开.png")
	# 混合机现有底部碰撞位于柜内罐上方；真实蹲下后瞄准可见下部。
	player.set_physics_process(true)
	Input.action_press("crouch")
	await frames(45)
	player.set_physics_process(false)
	check(player.is_crouching, "实际主场景通过现有蹲下动作接近柜内下部")
	var selected: AutolysisLiquidTank = cabinet.get_item_at_slot(1)
	await _aim(selected.to_global(Vector3(0.0, -0.10, 0.15)))
	_record("主场景指定一号罐")
	check(player.interaction_raycast.get_collider() == selected and player.interaction_controller.is_direct_available(), "实际主场景射线命中可见的一号罐下部")
	await _click()
	check(inventory.get_focused_item() == LIQUID and cabinet.get_item_at_slot(1) == null, "实际主场景指定取回一号罐")
	await _capture("09-主场景手持.png")
	await _aim(cabinet.to_global(Vector3(-0.58, 0.13, 0.85)))
	_record("主场景柜内下部放置区")
	check(player.interaction_raycast.get_collider() == cabinet.placement_body and player.interaction_controller.is_direct_available(), "实际主场景射线命中可见柜内放置区")
	await _click()
	check(_stored_count() == 2 and inventory.get_focused_item() == null, "实际主场景放回对应空槽")
	await _aim_door()
	await _click()
	await frames(20)
	check(not cabinet.is_open(), "实际主场景关闭柜门完成完整循环")
	Input.action_release("crouch")
	var fixed_count: int = 0
	for machine_name: String in ["machine_packing_0", "machine_wave_rebuilder_0", "machine_phase_separator_0"]:
		var tank: AutolysisLiquidTank = world.get_node("interaction_prefabs/machines/" + machine_name + "/liquid_tank_0") as AutolysisLiquidTank
		check(tank != null and tank.fixed_installation and not tank.is_available_for_pickup(), "机器嵌入罐固定装配且不可拾取：" + machine_name + "（机器节点）")
		if tank != null:
			check(tank.collision_layer != 0, "固定机器罐保留原物理碰撞")
			fixed_count += 1
	check(fixed_count == 3 and _stored_count() == 2, "主场景三件固定罐与两件可转移柜罐边界正确")
	await _capture("10-主场景循环完成.png")


func _stored_count() -> int:
	var total: int = 0
	for index: int in range(2):
		if cabinet.get_item_at_slot(index) != null:
			total += 1
	return total


func _inventory_count() -> int:
	var total: int = 0
	for index: int in range(4):
		if inventory.get_slot_item(index) == LIQUID:
			total += 1
	return total


func _pure_visual(node: Node) -> bool:
	if node == null or node is CollisionObject3D or node is CollisionShape3D or node.get_script() != null or node.is_in_group(&"interactable"):
		return false
	for child: Node in node.get_children():
		if not _pure_visual(child):
			return false
	return true


func _record(stage: String) -> void:
	var detector: InteractionRayCast = player.interaction_raycast
	detector.force_raycast_update()
	var hit: Object = detector.get_collider()
	rays.append({"阶段": stage, "当前格": inventory.get_focused_index(), "掩码": detector.collision_mask, "起点": str(detector.global_position), "命中": str(hit.get_path()) if hit is Node else "无命中", "碰撞点": str(detector.get_collision_point()) if hit else "无碰撞", "许可": player.interaction_controller.is_direct_available(), "柜内罐数": _stored_count(), "携带罐数": _inventory_count(), "鼠标模式": Input.mouse_mode, "玩家基础许可": player._base_input_allowed(), "玩家交互许可": player.is_interaction_input_allowed(), "聚焦接管": player.focus_controller.has_control(), "柜门可交互": cabinet.can_toggle(player), "柜门状态": cabinet.state})


func _capture(filename: String) -> void:
	if not _rendered:
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(evidence_directory.path_join(filename)) == OK, "保存实际画面：" + filename)


func _save_report() -> void:
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("真实输入与射线报告.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "实际图形后端": _rendered, "断言数": assertions.size(), "失败数": failures, "断言": assertions, "射线": rays}, "\t"))
		file.close()
	else:
		check(false, "报告文件可写")
