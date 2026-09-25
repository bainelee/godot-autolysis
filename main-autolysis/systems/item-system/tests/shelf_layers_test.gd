extends "res://main-autolysis/systems/item-system/tests/item_system_test.gd"
## 第二部分：真实控制器首命中、共享架体不变性及主场景边界验证。

const RAY_SCENE: PackedScene = preload("res://main-autolysis/player/components/interaction_raycast.tscn")
const WAREHOUSE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_furnitures/store_shelf_warehouse_0.tscn")
var records: Array[Dictionary] = []


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	await _controller_checks()
	await _warehouse_checks()
	await _main_geometry_checks()
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("shelf-layer-details.json"), FileAccess.WRITE)
	_check(report != null, "创建分层集成证据")
	if report != null:
		report.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "记录": records}, "\t"))
		report.close()
	await _clear_world()
	world.queue_free()
	await _frames()
	print("分层集成断言数：", assertion_count, "；失败数：", failures)
	quit(1 if failures else 0)


func _controller(actor: TestActor, ray: InteractionRayCast) -> AutolysisInteractionController:
	var controller: AutolysisInteractionController = AutolysisInteractionController.new()
	actor.add_child(controller)
	controller.configure(actor, ray, func() -> bool: return true, actor.inventory)
	actor.inventory.inventory_changed.connect(controller.refresh_state)
	return controller


func _ray(origin: Vector3, target: Vector3) -> InteractionRayCast:
	var ray: InteractionRayCast = RAY_SCENE.instantiate() as InteractionRayCast
	world.add_child(ray)
	_aim(ray, origin, target)
	return ray


func _aim(ray: InteractionRayCast, origin: Vector3, target: Vector3) -> void:
	ray.global_position = origin
	ray.look_at(target, Vector3.UP)


func _click_controller(controller: AutolysisInteractionController) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"interact_direct"
	event.pressed = true
	controller._unhandled_input(event)


func _record(ray: InteractionRayCast, label: String) -> void:
	var hit: Node = ray.get_collider() as Node
	records.append({"场景": label, "掩码": ray.collision_mask, "手持状态": "原药" if ray.collision_mask == 19 else "空手或非原药", "起点": _vector_values(ray.global_position), "命中对象": str(hit.get_path()) if hit else "无命中", "命中坐标": _vector_values(ray.get_collision_point()) if hit else [], "命中距离": ray.global_position.distance_to(ray.get_collision_point()) if hit else -1.0})


func _controller_checks() -> void:
	var shelf: AutolysisRawMaterialShelf = _new_shelf()
	var actor: TestActor = _new_actor()
	actor.inventory.try_receive_item(CAFFEINE)
	actor.inventory.try_place_on_shelf(shelf)
	var item: AutolysisRawMaterial = shelf.get_item_at_slot(0)
	var target: Vector3 = (item.get_node("CollisionShape3D") as Node3D).global_position
	var local: Vector3 = shelf.to_local(target)
	var origin: Vector3 = shelf.to_global(Vector3(local.x, local.y, -1.4))
	var ray: InteractionRayCast = _ray(origin, target)
	var controller: AutolysisInteractionController = _controller(actor, ray)
	await _frames()
	controller.refresh_state()
	_check(ray.get_collider() == item and controller.is_direct_available(), "真实控制器空手命中瓶体且允许拾取")
	_record(ray, "单瓶空手")
	actor.inventory.try_receive_item(SODIUM_BENZOATE)
	_check(ray.get_collider() == shelf and ray.collision_mask == 19 and controller.is_direct_available(), "接收原药通知立即切换到架体")
	_record(ray, "相同方向手持")
	_click_controller(controller)
	_check(_shelf_count(shelf) == 2 and actor.inventory.get_focused_item() == null, "一次输入仅放置一件至最小空槽，刷新不再次拾取")
	_check(shelf.get_item_at_slot(1).item_definition == SODIUM_BENZOATE, "新原药进入编号一空槽")
	await _frames()
	_click_controller(controller)
	_check(_shelf_count(shelf) == 1 and actor.inventory.get_focused_item() == CAFFEINE, "下一次输入仅取回瞄准的一瓶")
	actor.inventory.cycle_focus(1)
	_check(ray.collision_mask == 3 and actor.inventory.get_slot_item(0) == CAFFEINE, "其他格有药时当前空格使用空手查询")
	actor.inventory.cycle_focus(-1)
	_check(ray.collision_mask == 19, "切回有药格立即恢复架体查询")
	actor.inventory.try_place_on_shelf(shelf)
	await _frames()
	item = shelf.get_item_at_slot(0)
	target = (item.get_node("CollisionShape3D") as Node3D).global_position
	_aim(ray, origin, target)
	var second_actor: TestActor = _new_actor()
	second_actor.inventory.try_receive_item(CAFFEINE)
	var second_ray: InteractionRayCast = _ray(origin, target)
	var second_controller: AutolysisInteractionController = _controller(second_actor, second_ray)
	controller.refresh_state()
	second_controller.refresh_state()
	_check(ray.get_collider() == item and second_ray.get_collider() == shelf and shelf.collision_layer == 24, "两个查询者状态独立且架体层值固定")
	var inside: Vector3 = shelf.to_global(Vector3(local.x, local.y, -0.39))
	_aim(second_ray, inside, target)
	second_controller.refresh_state()
	_check(second_ray.get_collider() == shelf and second_ray.get_collision_point().is_equal_approx(inside), "盒内起点手持命中架体且碰撞点为起点")
	_record(second_ray, "盒内手持")
	_aim(ray, inside, target)
	controller.refresh_state()
	_check(ray.get_collider() == item, "相同盒内起点空手仍命中瓶体")
	_record(ray, "盒内空手")
	_aim(ray, shelf.to_global(Vector3(0.59, 0.28, -1.4)), shelf.to_global(Vector3(0.59, 0.28, -0.2)))
	controller.refresh_state()
	_click_controller(controller)
	_check(not controller.is_direct_available() and actor.inventory.get_focused_item() == null, "架体空白处不会补选原药")
	_aim(ray, shelf.to_global(Vector3(local.x, local.y, -3.0)), target)
	controller.refresh_state()
	_check(not ray.is_colliding() and not controller.is_direct_available(), "超出两米不命中原药")
	_aim(ray, origin, target)
	var component: AutolysisInteractionComponent = item.get_node("InteractionComponent")
	component.set_availability_check(func(_actor: Node3D) -> bool: return false)
	controller.refresh_state()
	_click_controller(controller)
	_check(ray.get_collider() == item and not controller.is_direct_available() and actor.inventory.get_focused_item() == null, "不可用首命中不被跳过且点击不转移")
	var behind: AutolysisRawMaterial = _new_world_item(CAFFEINE_WORLD, item.global_position + shelf.global_basis.z * 0.6)
	await _frames()
	controller.refresh_state()
	_check(ray.get_collider() == item, "后方增加可用瓶体后仍不跳过不可用首命中")
	shelf.release_item(item)
	item.queue_free()
	await _frames()
	controller.refresh_state()
	_check(ray.get_collider() == behind and controller.is_direct_available(), "删除前方碰撞后查询更新到后方瓶体")
	behind.position.x += 10
	await _frames()
	controller.refresh_state()
	_check(not controller.is_direct_available(), "移走真实碰撞后提示清空")
	for index: int in range(36):
		if shelf.get_item_at_slot(index) == null:
			actor.inventory.try_receive_item(CAFFEINE if index % 2 == 0 else SODIUM_BENZOATE)
			actor.inventory.try_place_on_shelf(shelf)
	await _frames()
	_aim(second_ray, origin, target)
	second_controller.refresh_state()
	_click_controller(second_controller)
	_check(second_ray.get_collider() == shelf and not second_controller.is_direct_available() and _shelf_count(shelf) == 36 and second_actor.inventory.get_focused_item() == CAFFEINE, "满架仍为首命中，拒绝点击且数量守恒")
	_record(second_ray, "混放满架手持")
	controller.refresh_state()
	_check(ray.get_collider() is AutolysisRawMaterial and controller.is_direct_available(), "混放满架空手仍按真实首瓶命中")
	_record(ray, "混放满架空手")
	# 排队释放和立即释放分别使用独立查询者，避免把失效依赖当作空手。
	actor.inventory.queue_free()
	controller.refresh_state()
	_click_controller(controller)
	_check(not controller.is_direct_available() and controller._target == null and _shelf_count(shelf) == 36, "道具栏排队释放立即清空提示并拒绝输入")
	await _frames()
	second_actor.inventory.cycle_focus(1)
	second_controller.refresh_state()
	_check(second_controller.is_direct_available(), "立即释放用例先建立可用提示")
	second_actor.inventory.free()
	second_controller.refresh_state()
	_click_controller(second_controller)
	_check(not second_controller.is_direct_available() and _shelf_count(shelf) == 36, "道具栏立即失效后安全拒绝输入")
	await _clear_world()
	# 无效世界资源仍有合法手持显示，检测类别不得依据放置许可改变。
	actor = _new_actor()
	shelf = _new_shelf()
	var invalid: AutolysisItemDefinition = CAFFEINE.duplicate() as AutolysisItemDefinition
	invalid.world_scene_path = "res://不存在的原药.tscn"
	actor.inventory.try_receive_item(invalid)
	ray = _ray(origin, target)
	controller = _controller(actor, ray)
	await _frames()
	controller.refresh_state()
	_click_controller(controller)
	_check(ray.get_collider() == shelf and not controller.is_direct_available() and actor.inventory.get_focused_item() == invalid and _shelf_count(shelf) == 0, "无效放置资源不穿透架体且保留道具")
	invalid.is_raw_material = false
	controller.refresh_state()
	_check(ray.collision_mask == 3 and not controller.is_direct_available(), "非原药手持采用基础查询且不获得放置能力")
	await _clear_world()


func _warehouse_checks() -> void:
	var warehouse: StaticBody3D = WAREHOUSE.instantiate() as StaticBody3D
	world.add_child(warehouse)
	var shape: CollisionShape3D = warehouse.get_node("CollisionShape3D")
	var box: BoxShape3D = shape.shape as BoxShape3D
	var bounds: AABB = shape.transform * AABB(-box.size / 2, box.size)
	for mesh: Node in warehouse.get_node("mesh").get_children():
		if mesh is MeshInstance3D:
			var mesh_bounds: AABB = (warehouse.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			_check(bounds.grow(0.000001).encloses(mesh_bounds), "仓库整体盒覆盖实际立柱及层板模型")
			records.append({"检查": "仓库模型覆盖", "节点": str(mesh.name), "最小": _vector_values(mesh_bounds.position), "最大": _vector_values(mesh_bounds.end)})
	for scene: PackedScene in [CAFFEINE_GROUP, SODIUM_GROUP]:
		var group: AutolysisRawMaterialGroup = scene.instantiate() as AutolysisRawMaterialGroup
		world.add_child(group)
		group.position = Vector3(0, 0.9, 0.3)
		var actor: TestActor = _new_actor()
		var target: Vector3 = (group.get_node("CollisionShape3D") as Node3D).global_position
		var ray: InteractionRayCast = _ray(Vector3(target.x, target.y, -1), target)
		var controller: AutolysisInteractionController = _controller(actor, ray)
		await _frames()
		controller.refresh_state()
		_check(ray.get_collider() == group and controller.is_direct_available(), "空手从仓库整体盒外命中原药组")
		_click_controller(controller)
		_check(actor.inventory.get_focused_item() == group.item_definition and ray.get_collider() == group and not controller.is_direct_available() and warehouse.collision_layer == 8, "仓库组可领取，手持后仓库架不会成为放置目标")
		_record(ray, "仓库原药组")
		group.queue_free()
		actor.queue_free()
		ray.queue_free()
		await _frames()
	await _clear_world()


func _main_geometry_checks() -> void:
	var main: Node3D = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate() as Node3D
	world.add_child(main)
	var upper: AutolysisRawMaterialShelf = main.get_node("interaction_prefabs/item_groups/place_shelf_workroom_rm_0")
	var lower: AutolysisRawMaterialShelf = main.get_node("interaction_prefabs/item_groups/place_shelf_workroom_rm_1")
	var ray: InteractionRayCast = _ray(Vector3.ZERO, Vector3.FORWARD)
	await _frames()
	var bounds: Array[AABB] = []
	for shelf: AutolysisRawMaterialShelf in [upper, lower]:
		var shape: CollisionShape3D = shelf.get_node("CollisionShape3D")
		var box: BoxShape3D = shape.shape as BoxShape3D
		var local_bounds: AABB = shape.transform * AABB(-box.size / 2, box.size)
		var world_bounds: AABB = shelf.global_transform * local_bounds
		bounds.append(world_bounds)
		var union: AABB
		var initialized: bool = false
		for scene: PackedScene in [CAFFEINE_WORLD, SODIUM_WORLD]:
			var item: Node3D = scene.instantiate() as Node3D
			var collision: CollisionShape3D = item.get_node("CollisionShape3D")
			var item_box: BoxShape3D = collision.shape as BoxShape3D
			for index: int in range(shelf.get_slot_count()):
				var slot: Node3D = shelf.get_slot_node(index)
				var item_bounds: AABB = (shelf.global_transform.affine_inverse() * slot.global_transform * collision.transform) * AABB(-item_box.size / 2, item_box.size)
				_check(local_bounds.grow(0.000001).encloses(item_bounds), "实际药品碰撞被整体盒包围：槽位%d" % index)
				union = union.merge(item_bounds) if initialized else item_bounds
				initialized = true
			item.free()
		var mesh_records: Array[Dictionary] = []
		for mesh: Node in shelf.get_node("mesh").get_children():
			if mesh is MeshInstance3D:
				var mesh_bounds: AABB = (shelf.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
				_check(local_bounds.grow(0.000001).encloses(mesh_bounds), "整体盒覆盖实际架体网格")
				mesh_records.append({"节点": str(mesh.name), "最小": _vector_values(mesh_bounds.position), "最大": _vector_values(mesh_bounds.end)})
		records.append({"架子": str(shelf.get_path()), "整体盒最小": _vector_values(world_bounds.position), "整体盒最大": _vector_values(world_bounds.end), "药品局部联合最小": _vector_values(union.position), "药品局部联合最大": _vector_values(union.end), "模型": mesh_records})
	_check(is_equal_approx(bounds[0].position.y - bounds[1].end.y, 0.01), "主场景两整体盒实际间隙为一厘米")
	for height: float in [1.285, 1.295, 1.305, 1.31]:
		var origin: Vector3 = upper.to_global(Vector3(0, height - upper.global_position.y, -1.0))
		var target: Vector3 = upper.to_global(Vector3(0, height - upper.global_position.y, -0.2))
		_aim(ray, origin, target)
		ray.refresh_target(true)
		print("边界高度：", height, "；首命中：", ray.get_collider())
		# 实测间隙后方一米处为主场景墙体；间隙不误选架体，仍遵守墙体首命中。
		var expected: Node = lower if height < 1.29 else (upper if height > 1.3 else main.get_node("Environment/wall/wall_room0_18"))
		_check(ray.get_collider() == expected, "主场景边界水平射线高度%.3f命中预期架体或间隙后方墙体" % height)
		_record(ray, "主场景边界%.3f" % height)
	for shelf: AutolysisRawMaterialShelf in [upper, lower]:
		var inside: Vector3 = shelf.to_global(Vector3(0, 0.28, -0.2))
		_aim(ray, inside, shelf.to_global(Vector3(0, 0.28, -0.4)))
		ray.refresh_target(true)
		_check(ray.get_collider() == shelf, "实际主场景单盒内部起点命中所属架体")
		_record(ray, "主场景盒内")
