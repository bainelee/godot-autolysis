extends SceneTree
## 胶囊逐件数据、真实场景显示、无限领取及拾取失败保留来源的定向验收。

const CAPSULE_DEFINITION: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/pneumatic_capsule.tres")
const TANK_DEFINITION: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/liquid_tank.tres")
const CAFFEINE: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/caffeine.tres")
const CAPSULE_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/pneumatic_capsules_0.tscn")
const SHELF_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/shelf_penumatic_capsules.tscn")

class TestActor extends Node3D:
	var inventory: AutolysisInventoryController
	var presenter: AutolysisHeldItemPresenter
	var notifications: int = 0

	func input_allowed() -> bool:
		return true


	func on_inventory_changed() -> void:
		notifications += 1

var world: Node3D
var assertion_count: int = 0
var failures: int = 0
var checks: Array[Dictionary] = []
var ray_records: Array[Dictionary] = []
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/封装器与气动胶囊实施证据/20261003/data")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	world = Node3D.new()
	root.add_child(world)
	_test_contents()
	_test_instance_isolation()
	await _test_visuals()
	await _test_shelf_supply()
	await _test_world_pickup()
	await _test_candidate_failures()
	_save_report()
	world.queue_free()
	await _frames()
	print("胶囊数据行为断言数：", assertion_count, "；失败总数：", failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	assertion_count += 1
	checks.append({"检查": description, "通过": condition})
	if not condition:
		failures += 1
	print(("通过：" if condition else "失败：") + description)


func _frames(count: int = 2) -> void:
	for _frame_index: int in range(count):
		await physics_frame
		await process_frame


func _source_contents() -> AutolysisLiquidContents:
	var ids: Array[String] = ["caffeine", "sodium_benzoate", "caffeine", "sodium_benzoate"]
	var source: AutolysisLiquidContents = AutolysisLiquidContents.create_result(ids)
	source.set_phase_rgb(Vector3(2.5, -3, 8))
	source.set_wave(true, false, true, true, 6)
	return source


func _test_contents() -> void:
	var original: AutolysisLiquidContents = _source_contents()
	var ids: Array[String] = original.get_raw_material_ids()
	for type: int in range(3):
		var source: AutolysisLiquidContents = original.copy_contents()
		var contents: AutolysisPackingContents = AutolysisPackingContents.create_result(source, type)
		_check(contents != null and contents.is_valid_contents(), "三类各自创建合法产物：%d" % type)
		_check(contents.get_raw_material_ids() == ids and contents.get_phase_rgb() == Vector3(2.5, -3, 8) and contents.get_wave_coordinates() == [1, 0, 1, 1, 6] and contents.get_packing_type() == type, "完整复制四条重复原药、非零相位与波形上界：%d" % type)
		_check(contents.get_raw_material_display() == "咖啡因*2、苯甲酸钠*2" and contents.get_packing_type_display() == ["针剂", "酊剂", "粉剂"][type], "原药合并显示及中文封装类型：%d" % type)
		source.set_phase_rgb(Vector3(10, 20, 30))
		source.set_wave(false, true, false, false, 0)
		_check(contents.get_phase_rgb() == original.get_phase_rgb() and contents.get_wave_coordinates() == original.get_wave_coordinates(), "源内容之后重构不改变既有封装产物：%d" % type)
		var read_source: AutolysisLiquidContents = contents.get_source_contents()
		read_source.set_phase_rgb(Vector3(-1, -2, -3))
		read_source.set_wave(false, false, false, false, 0)
		var read_ids: Array[String] = contents.get_raw_material_ids()
		read_ids.clear()
		var read_wave: Array[int] = contents.get_wave_coordinates()
		read_wave[4] = 0
		_check(contents.get_raw_material_ids() == ids and contents.get_phase_rgb() == original.get_phase_rgb() and contents.get_wave_coordinates() == original.get_wave_coordinates(), "源内容、原药数组及波形数组读取全部隔离：%d" % type)
		var copied: AutolysisPackingContents = contents.copy_contents()
		copied._source_contents.set_phase_rgb(Vector3.ZERO)
		copied._packing_type = (type + 1) % 3
		_check(contents.get_phase_rgb() == original.get_phase_rgb() and contents.get_packing_type() == type, "复制产物保留完整数据且后续写入相互隔离：%d" % type)
	for count: int in range(1, 5):
		var source_ids: Array[String] = []
		for _index: int in range(count):
			source_ids.append("caffeine")
		var source: AutolysisLiquidContents = AutolysisLiquidContents.create_result(source_ids)
		var contents: AutolysisPackingContents = AutolysisPackingContents.create_result(source, AutolysisPackingContents.PackingType.POWDER)
		_check(contents != null and contents.get_raw_material_ids() == source_ids and contents.get_wave_coordinates() == [0, 0, 0, 0, 0], "一至四条及零波形完整保留：%d" % count)
	_check(AutolysisPackingContents.create_result(original, -1) == null and AutolysisPackingContents.create_result(original, 3) == null, "未选择及越界类型禁止写入产物")
	_check(AutolysisPackingContents.create_result(null, 0) == null and AutolysisPackingContents.create_result(AutolysisLiquidContents.new(), 0) == null, "空引用及无原药来源拒绝")
	var invalid: AutolysisPackingContents = AutolysisPackingContents.new()
	_check(not invalid.is_valid_contents() and invalid.copy_contents() == null and invalid.get_source_contents() == null and invalid.get_packing_type() == -1, "无效封装资源不能复制为合法产物")


func _test_instance_isolation() -> void:
	var source: AutolysisLiquidContents = _source_contents()
	var packed: AutolysisPackingContents = AutolysisPackingContents.create_result(source, AutolysisPackingContents.PackingType.TINCTURE)
	var first: AutolysisItemInstance = AutolysisItemInstance.create(CAPSULE_DEFINITION)
	var second: AutolysisItemInstance = AutolysisItemInstance.create(CAPSULE_DEFINITION)
	var tank: AutolysisItemInstance = AutolysisItemInstance.create(TANK_DEFINITION)
	var raw: AutolysisItemInstance = AutolysisItemInstance.create(CAFFEINE)
	_check(CAPSULE_DEFINITION.is_valid_definition() and not CAPSULE_DEFINITION.is_raw_material and CAPSULE_DEFINITION.icon != null, "胶囊为非原药共享定义并具有可读模型图标")
	_check(first != second and first.definition == second.definition and first.is_empty_pneumatic_capsule() and second.is_empty_pneumatic_capsule(), "共享胶囊定义创建两个独立空实例")
	_check(not first.set_liquid_contents(source) and not tank.set_packing_contents(packed) and not raw.set_packing_contents(packed) and not raw.set_liquid_contents(source), "液体罐、胶囊与原药严格禁止内容跨种类写入")
	var changes: Array[int] = [0]
	first.changed.connect(func() -> void: changes[0] += 1)
	_check(first.set_packing_contents(packed, false) and changes[0] == 0 and not first.is_empty_pneumatic_capsule(), "静默提交产物不提前通知")
	_check(second.set_packing_contents(packed) and not second.is_empty_pneumatic_capsule(), "另一胶囊可保存相同源数据的独立产物")
	packed._source_contents.set_phase_rgb(Vector3.ZERO)
	packed._packing_type = AutolysisPackingContents.PackingType.INJECTION
	_check(first.get_phase_rgb() == Vector3(2.5, -3, 8) and second.get_phase_rgb() == Vector3(2.5, -3, 8) and first.packing_contents.get_packing_type() == AutolysisPackingContents.PackingType.TINCTURE, "赋值形成独立副本，修改调用方资源不改变两胶囊")
	var read: AutolysisPackingContents = first.packing_contents
	read._source_contents.set_phase_rgb(Vector3(1, 1, 1))
	read._packing_type = AutolysisPackingContents.PackingType.POWDER
	_check(first.packing_contents != first.packing_contents and first.get_phase_rgb() == Vector3(2.5, -3, 8) and first.packing_contents.get_packing_type() == AutolysisPackingContents.PackingType.TINCTURE, "实例封装内容读取每次返回完整副本")
	_check(tank.set_liquid_contents(source), "准备来源罐")
	var owned_source: AutolysisLiquidContents = tank.liquid_contents
	_check(tank.liquid_contents == owned_source and tank.set_liquid_contents(null), "液体罐既有内容引用读取契约保留且可以清空")
	_check(first.get_phase_rgb() == Vector3(2.5, -3, 8) and first.get_wave_coordinates() == [1, 0, 1, 1, 6], "清空来源罐不影响已封装胶囊")
	_check(first.set_packing_contents(null) and first.is_empty_pneumatic_capsule() and changes[0] == 1 and not second.is_empty_pneumatic_capsule(), "清除一件胶囊只通知本件且不改变另一产物")
	var invalid: AutolysisPackingContents = AutolysisPackingContents.new()
	_check(not second.set_packing_contents(invalid) and second.is_valid_instance() and not second.is_empty_pneumatic_capsule(), "无效产物赋值失败保留既有内容")


func _test_visuals() -> void:
	var empty: AutolysisItemInstance = AutolysisItemInstance.create(CAPSULE_DEFINITION)
	var packed: AutolysisItemInstance = AutolysisItemInstance.create(CAPSULE_DEFINITION)
	packed.set_packing_contents(AutolysisPackingContents.create_result(_source_contents(), 0))
	var first: AutolysisPneumaticCapsule = CAPSULE_SCENE.instantiate() as AutolysisPneumaticCapsule
	var second: AutolysisPneumaticCapsule = CAPSULE_SCENE.instantiate() as AutolysisPneumaticCapsule
	_check(first.bind_item_instance(empty) and second.bind_item_instance(packed), "世界胶囊入树前绑定原实例")
	world.add_child(first)
	world.add_child(second)
	first.position.x = -4
	second.position.x = -2
	var untouched: MeshInstance3D = first.get_node("mesh/MeshInstance3D9") as MeshInstance3D
	var original_cap_material: Material = untouched.material_override
	_check(AutolysisPneumaticCapsuleVisual.get_contents_mesh(first).material_override == AutolysisPneumaticCapsuleVisual.EMPTY_MATERIAL and AutolysisPneumaticCapsuleVisual.get_contents_mesh(second).material_override == AutolysisPneumaticCapsuleVisual.PACKED_MATERIAL, "世界空胶囊灰色、封装胶囊使用指定绿色发光引用")
	_check(first.apply_contents(packed.packing_contents) and untouched.material_override == original_cap_material, "装填只改变标识网格，不改胶囊端盖材质")
	var presenter: AutolysisHeldItemPresenter = AutolysisHeldItemPresenter.new()
	world.add_child(presenter)
	var display: Node3D = presenter.prepare_instance(empty)
	_check(display != null and _is_pure_visual(display) and display.find_children("", "MeshInstance3D", true, false).size() == 6, "手持场景保留六个原网格且无脚本、碰撞与交互")
	presenter.commit_prepared(display)
	presenter.watch_instance(empty)
	_check(AutolysisPneumaticCapsuleVisual.get_contents_mesh(display).material_override == AutolysisPneumaticCapsuleVisual.PACKED_MATERIAL, "手持展示当前封装材质")
	empty.set_packing_contents(null)
	_check(AutolysisPneumaticCapsuleVisual.get_contents_mesh(first).material_override == AutolysisPneumaticCapsuleVisual.EMPTY_MATERIAL and AutolysisPneumaticCapsuleVisual.get_contents_mesh(display).material_override == AutolysisPneumaticCapsuleVisual.EMPTY_MATERIAL, "逐件变化同步刷新世界与当前手持材质")
	var missing: Node3D = Node3D.new()
	_check(not AutolysisPneumaticCapsuleVisual.can_apply(missing) and not AutolysisPneumaticCapsuleVisual.apply_instance(missing, packed), "缺少标识网格的候选无法应用显示")
	missing.free()
	presenter.queue_free()
	first.queue_free()
	second.queue_free()
	await _frames()


func _new_actor() -> TestActor:
	var actor: TestActor = TestActor.new()
	actor.inventory = AutolysisInventoryController.new()
	actor.inventory.name = "InventoryController"
	actor.presenter = AutolysisHeldItemPresenter.new()
	actor.add_child(actor.inventory)
	actor.add_child(actor.presenter)
	world.add_child(actor)
	actor.inventory.configure(actor.presenter, actor.input_allowed)
	actor.inventory.inventory_changed.connect(actor.on_inventory_changed)
	return actor


func _test_shelf_supply() -> void:
	var actor: TestActor = _new_actor()
	var shelf: AutolysisPneumaticCapsuleShelf = SHELF_SCENE.instantiate() as AutolysisPneumaticCapsuleShelf
	world.add_child(shelf)
	var component: AutolysisInteractionComponent = shelf.get_node("InteractionComponent") as AutolysisInteractionComponent
	var first_display: Node3D = shelf.get_node("pneumatic_capsules_0") as Node3D
	var second_display: Node3D = shelf.get_node("pneumatic_capsules_1") as Node3D
	var first_transform: Transform3D = first_display.transform
	var second_transform: Transform3D = second_display.transform
	_check(_is_pure_visual(first_display) and _is_pure_visual(second_display), "架子两只陈列胶囊不再有物理碰撞或拾取")
	_check(component.can_interact(actor) and component.try_interact(actor), "选中空格通过真实交互组件领取")
	var first: AutolysisItemInstance = actor.inventory.get_focused_instance()
	_check(first != null and first.is_empty_pneumatic_capsule() and actor.notifications == 1, "领取生成一个独立空胶囊并在成功后通知")
	_check(not component.can_interact(actor) and not component.try_interact(actor) and actor.inventory.get_focused_instance() == first and actor.notifications == 1, "手持胶囊时不能重复领取或覆盖")
	_check(actor.inventory.cycle_focus(1) and component.try_interact(actor), "其他格占用不影响选中空格领取")
	var second: AutolysisItemInstance = actor.inventory.get_focused_instance()
	_check(second != first and second.definition == first.definition and second.is_empty_pneumatic_capsule(), "第二次领取仍产生独立逐件实例")
	_check(first_display.transform == first_transform and second_display.transform == second_transform and first_display.visible and second_display.visible, "重复领取不改变陈列数量、位置及可见性")
	await _frames()
	for location: Vector3 in [Vector3(0.32, 0.43, 0.15), Vector3(0, 0.23999988, 0.14999999), Vector3(0, 0.61999977, 0.14999996), Vector3(0, 0.73, 0.15)]:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(shelf.to_global(location + Vector3(0, 0, 1)), shelf.to_global(location - Vector3(0, 0, 1)), 3)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		var hits_shelf: bool = not hit.is_empty() and hit.get("collider") == shelf
		_check(hits_shelf, "实际射线点击架体或上下陈列范围命中架子：%s" % str(location))
		ray_records.append({"本地位置": str(location), "命中架子": hits_shelf, "实际物理体": str(hit.get("collider"))})
	actor.queue_free()
	shelf.queue_free()
	await _frames()


func _test_world_pickup() -> void:
	var actor: TestActor = _new_actor()
	var capsule: AutolysisPneumaticCapsule = CAPSULE_SCENE.instantiate() as AutolysisPneumaticCapsule
	world.add_child(capsule)
	_check(capsule.is_available_for_pickup() and actor.inventory.can_take_pneumatic_capsule(actor, capsule), "独立世界空胶囊可拾取")
	var original: AutolysisItemInstance = capsule.item_instance
	_check(actor.inventory.try_take_pneumatic_capsule(actor, capsule) and actor.inventory.get_focused_instance() == original and actor.notifications == 1, "世界拾取提交保留原实例并只通知一次")
	_check(not capsule.is_available_for_pickup() and not actor.inventory.try_take_pneumatic_capsule(actor, capsule), "已提交且待释放的世界胶囊不能重复拾取")
	await _frames()
	_check(not is_instance_valid(capsule), "成功拾取的世界胶囊实际释放")
	actor.inventory.cycle_focus(1)
	var packed: AutolysisItemInstance = AutolysisItemInstance.create(CAPSULE_DEFINITION)
	packed.set_packing_contents(AutolysisPackingContents.create_result(_source_contents(), 2))
	var full: AutolysisPneumaticCapsule = CAPSULE_SCENE.instantiate() as AutolysisPneumaticCapsule
	full.bind_item_instance(packed)
	world.add_child(full)
	_check(actor.inventory.try_take_pneumatic_capsule(actor, full) and actor.inventory.get_focused_instance() == packed and packed.get_phase_rgb() == Vector3(2.5, -3, 8) and packed.packing_contents.get_packing_type() == 2, "封装世界胶囊拾取保留身份及完整产物")
	_check(AutolysisPneumaticCapsuleVisual.get_contents_mesh(actor.presenter.get_display()).material_override == AutolysisPneumaticCapsuleVisual.PACKED_MATERIAL, "世界产物拾取后手持标识保持绿色")
	actor.queue_free()
	await _frames()


func _test_candidate_failures() -> void:
	var actor: TestActor = _new_actor()
	var broken_definition: AutolysisItemDefinition = CAPSULE_DEFINITION.duplicate() as AutolysisItemDefinition
	var visual_root: Node3D = Node3D.new()
	var broken_visual: PackedScene = PackedScene.new()
	_check(broken_visual.pack(visual_root) == OK, "构建缺少标识网格但符合纯显示结构的候选夹具")
	visual_root.free()
	broken_definition.visual_scene = broken_visual
	var shelf: AutolysisPneumaticCapsuleShelf = SHELF_SCENE.instantiate() as AutolysisPneumaticCapsuleShelf
	shelf.item_definition = broken_definition
	world.add_child(shelf)
	var component: AutolysisInteractionComponent = shelf.get_node("InteractionComponent") as AutolysisInteractionComponent
	_check(component.can_interact(actor) and component.try_interact(actor), "定义结构有效的领取请求进入候选准备")
	_check(actor.inventory.get_focused_instance() == null and actor.presenter.get_display() == null and actor.notifications == 0 and shelf.has_node("pneumatic_capsules_0") and shelf.has_node("pneumatic_capsules_1"), "领取候选显示失败不产生库存物品或通知、不改变陈列")
	var original: AutolysisItemInstance = AutolysisItemInstance.create(broken_definition)
	original.set_packing_contents(AutolysisPackingContents.create_result(_source_contents(), 1))
	var capsule: AutolysisPneumaticCapsule = CAPSULE_SCENE.instantiate() as AutolysisPneumaticCapsule
	capsule.item_definition = broken_definition
	_check(capsule.bind_item_instance(original), "世界故障夹具保留原实例及合法世界标识网格")
	world.add_child(capsule)
	_check(actor.inventory.can_take_pneumatic_capsule(actor, capsule) and not actor.inventory.try_take_pneumatic_capsule(actor, capsule), "世界胶囊拾取候选手持准备失败")
	_check(capsule.is_available_for_pickup() and capsule.item_instance == original and original.packing_contents.get_packing_type() == 1 and actor.inventory.get_focused_instance() == null and actor.notifications == 0, "拾取失败保留来源胶囊、完整数据、空库存及通知数")
	broken_definition.visual_scene = CAPSULE_DEFINITION.visual_scene
	_check(actor.inventory.try_take_pneumatic_capsule(actor, capsule) and actor.inventory.get_focused_instance() == original, "修复显示依赖后同一来源可成功拾取")
	actor.queue_free()
	shelf.queue_free()
	await _frames()


func _is_pure_visual(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node.get_script() != null or node.is_in_group(&"interactable"):
		return false
	for child: Node in node.get_children():
		if not _is_pure_visual(child):
			return false
	return true


func _save_report() -> void:
	var report: Dictionary = {"引擎版本": Engine.get_version_info()["string"], "显示后端": DisplayServer.get_name(), "断言总数": assertion_count, "失败总数": failures, "检查": checks, "实际射线": ray_records, "通过": failures == 0}
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("胶囊数据行为结果.json"), FileAccess.WRITE)
	if file == null:
		failures += 1
		push_error("胶囊数据行为证据无法写入。")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
