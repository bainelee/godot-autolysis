extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 独立故障复核；仅运行无图形，使用正式电话与玩家，在实例上改变必要物理配置。

const TELEPHONE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/machine_telephone_0.tscn")
const PLAYER: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")

var telephone: AutolysisTelephone
var observations: Array[Dictionary] = []
var directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/dependency-audit")


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	await fixture()
	var actor: AutolysisPlayer = player as AutolysisPlayer
	actor.collision_mask = 1
	var mask_allowed: bool = telephone.can_take_handset(actor)
	var mask_requested: bool = telephone.handset_interaction.try_interact(actor)
	for index: int in range(90):
		await frames(1)
		if not telephone.is_transfer_pending():
			break
	var query_mask_one: KinematicCollision3D = KinematicCollision3D.new()
	var blocked_mask_one: bool = actor.test_move(actor.global_transform, Vector3(-1, 0, 0), query_mask_one)
	actor.collision_mask = 9
	var query_mask_nine: KinematicCollision3D = KinematicCollision3D.new()
	var blocked_mask_nine: bool = actor.test_move(actor.global_transform, Vector3(-1, 0, 0), query_mask_nine)
	observations.append({"用途": "玩家掩码不再包含必要限位层时的配置依赖复核", "试验玩家掩码": 1, "限位层": telephone.move_limit_body.collision_layer, "取筒许可": mask_allowed, "请求被接受": mask_requested, "实际玩家持筒": actor.inventory_controller.has_exclusive_handset(), "掩码一运动受阻": blocked_mask_one, "掩码九运动受阻": blocked_mask_nine, "掩码九碰撞来源": str(query_mask_nine.get_collider().get_path()) if blocked_mask_nine else ""})
	check(not mask_allowed and not mask_requested and not actor.inventory_controller.has_exclusive_handset(), "缺少有效移动限位掩码时拒绝取筒")
	if actor.inventory_controller.has_exclusive_handset():
		actor.inventory_controller.abort_handset_session(telephone, actor.inventory_controller.get_handset_session_id(), "独立复核完成后清理试验会话")
	await frames(4)
	actor.collision_mask = 9
	telephone.move_limit_shape.position = telephone.move_limit_body.to_local(actor.global_position)
	await frames(2)
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = telephone.move_limit_shape.shape
	query.transform = telephone.move_limit_shape.global_transform
	query.collision_mask = actor.collision_layer
	var intersects_actor: bool = false
	for hit: Dictionary in actor.get_world_3d().direct_space_state.intersect_shape(query):
		if hit.get("rid") == actor.get_rid():
			intersects_actor = true
	var overlap_allowed: bool = telephone.can_take_handset(actor)
	var requested: bool = telephone.handset_interaction.try_interact(actor)
	for index: int in range(90):
		await frames(1)
		if not telephone.is_transfer_pending():
			break
	observations.append({"用途": "必要限位形状移至真实玩家身体内，重叠只作测量而不作为取下许可", "形状几何实际与玩家重叠": intersects_actor, "取筒许可": overlap_allowed, "请求被接受": requested, "事务仍等待": telephone.is_transfer_pending(), "玩家独占持筒": actor.inventory_controller.has_exclusive_handset(), "电话持有者匹配": telephone.get_holder() == actor, "玩家位置": str(actor.global_position), "限位位置": str(telephone.move_limit_shape.global_position)})
	check(intersects_actor and overlap_allowed and requested and actor.inventory_controller.has_exclusive_handset() and telephone.get_holder() == actor and telephone._shape_is_active_in_world(telephone.move_limit_shape), "实际限位重叠不拒绝正式取下且真实边界完成启用")
	await _normal_return(actor, "实际限位重叠")
	actor.collision_layer = 0
	var zero_layer_allowed: bool = telephone.can_take_handset(actor)
	var zero_layer_requested: bool = telephone.handset_interaction.try_interact(actor)
	for index: int in range(90):
		await frames(1)
		if not telephone.is_transfer_pending():
			break
	var recovery: KinematicCollision3D = KinematicCollision3D.new()
	var physically_overlapped: bool = actor.test_move(actor.global_transform, Vector3.ZERO, recovery, 0.001, true)
	observations.append({"用途": "玩家物理层为零但必要移动掩码有效，原重叠证明要求已经删除", "玩家物理层": actor.collision_layer, "玩家掩码": actor.collision_mask, "取筒许可": zero_layer_allowed, "请求被接受": zero_layer_requested, "实际玩家持筒": actor.inventory_controller.has_exclusive_handset(), "零运动实际恢复碰撞": physically_overlapped, "碰撞来源": str(recovery.get_collider().get_path()) if physically_overlapped else ""})
	check(zero_layer_allowed and zero_layer_requested and actor.inventory_controller.has_exclusive_handset() and telephone.get_holder() == actor and telephone._shape_is_active_in_world(telephone.move_limit_shape), "删除玩家重叠证明门禁后零实体层仍可正式取下且必要移动掩码保持")
	await _normal_return(actor, "零实体层重叠")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file: FileAccess = FileAccess.open(directory.path_join("必要物理依赖复核.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(observations, "\t"))
	file.close()
	for record: Dictionary in observations:
		print(JSON.stringify(record))
	world.queue_free()
	await frames(3)
	quit(1 if failures > 0 else 0)


func _normal_return(actor: AutolysisPlayer, label: String) -> void:
	check(telephone.handset_interaction.try_interact(actor), label + "通过正式听筒组件请求归还")
	for index: int in range(90):
		if not telephone.is_transfer_pending():
			break
		await frames(1)
	var returned: bool = not actor.inventory_controller.has_exclusive_handset() and telephone.get_holder() == null and telephone.move_limit_shape.disabled and not telephone._shape_is_active_in_world(telephone.move_limit_shape)
	check(returned, label + "正式归还成对完成且实际边界已停用")
	observations.append({"用途": label + "正式归还", "成对归还完成": returned, "事务仍等待": telephone.is_transfer_pending(), "限位已停用": telephone.move_limit_shape.disabled, "实际物理限位仍启用": telephone._shape_is_active_in_world(telephone.move_limit_shape)})


func fixture() -> void:
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	var phone_scene: Node3D = TELEPHONE.instantiate()
	phone_scene.position = Vector3(0, 1.2, 0)
	world.add_child(phone_scene)
	telephone = phone_scene.get_node("StaticBody3D") as AutolysisTelephone
	player = PLAYER.instantiate()
	world.add_child(player)
	await reset_player(Vector3(0, 0.9, 1))
	var actor: AutolysisPlayer = player as AutolysisPlayer
	actor.focus_controller.configure(actor, actor.camera, actor.held_item_presenter, headless_entry)
	check(actor.focus_controller.try_enter(telephone.focus_target), "必要依赖复核使用正式电话进入聚焦")
	await frames(20)
	actor.set_physics_process(false)
	check(telephone.can_take_handset(actor), "正式默认非几何依赖建立稳定聚焦取筒起点")


func headless_entry() -> bool:
	return player._base_input_allowed() and not player.focus_controller.has_control()
