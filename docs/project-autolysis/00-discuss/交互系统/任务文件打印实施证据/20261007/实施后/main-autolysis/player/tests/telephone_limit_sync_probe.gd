extends SceneTree
## 独立诊断夹具：记录延后启停、真实形状查询和角色运动查询的同帧结果。

var wall: StaticBody3D
var collision: CollisionShape3D
var actor: CharacterBody3D
var samples: Array[Dictionary] = []
var stage: String = "初始"


func _initialize() -> void:
	run.call_deferred()


func sample(event: String) -> void:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collision_mask = 8
	var hits: Array[Dictionary] = wall.get_world_3d().direct_space_state.intersect_shape(query)
	var found: bool = false
	for hit: Dictionary in hits:
		if hit.get("rid") == wall.get_rid():
			found = true
	var result: KinematicCollision3D = KinematicCollision3D.new()
	var blocked: bool = actor.test_move(actor.global_transform, Vector3(2, 0, 0), result)
	samples.append({"阶段": stage, "事件": event, "普通帧": Engine.get_process_frames(), "物理帧": Engine.get_physics_frames(), "形状停用": collision.disabled, "形状查询命中限位": found, "角色运动受阻": blocked, "运动碰撞来源": str(result.get_collider()) if blocked else ""})


func apply(enabled: bool) -> void:
	sample("延后写入前")
	collision.set_deferred("disabled", not enabled)
	sample("延后写入已请求")
	post_write.call_deferred()


func post_write() -> void:
	sample("延后属性写入后")


func run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	wall = StaticBody3D.new()
	wall.collision_layer = 8
	wall.collision_mask = 0
	collision = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.12, 1.7, 2)
	collision.shape = box
	collision.disabled = true
	wall.add_child(collision)
	world.add_child(wall)
	actor = CharacterBody3D.new()
	actor.collision_mask = 9
	var actor_collision: CollisionShape3D = CollisionShape3D.new()
	var actor_box: BoxShape3D = BoxShape3D.new()
	actor_box.size = Vector3(0.6, 1.7, 0.6)
	actor_collision.shape = actor_box
	actor.add_child(actor_collision)
	world.add_child(actor)
	actor.position = Vector3(-1, 0, 0)
	for index: int in 3:
		await physics_frame
		await process_frame
	sample("初始稳定")
	for enabled: bool in [true, false, true, false]:
		stage = "启用" if enabled else "停用"
		sample("请求前")
		apply.call_deferred(enabled)
		sample("请求后")
		for index: int in 3:
			await physics_frame
			sample("物理帧信号")
			await process_frame
			sample("普通帧信号")
	var directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/电话聚焦交互实施证据/20261004/limit-sync")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file: FileAccess = FileAccess.open(directory.path_join("限位时序.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(samples, "\t"))
	for record: Dictionary in samples:
		print(JSON.stringify(record))
	world.queue_free()
	await process_frame
	quit()
