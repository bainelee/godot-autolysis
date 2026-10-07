extends "res://main-autolysis/player/tests/focus_interaction_test.gd"
## 正式场景、真实射线与注入输入的配药验收；保存数据、计时与图形证据。

const TANK_DEFINITION: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/liquid_tank.tres")
const CABINET_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_place_shelf/cabinet_workroom_0.tscn")
const TANK_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_machines/liquid_tank_0.tscn")
const INDICATOR_DEFAULT: int = 0
const INDICATOR_READY: int = 1
const INDICATOR_RUNNING: int = 2
const INDICATOR_COMPLETED: int = 3
const INDICATOR_RED: Material = preload("res://main-autolysis/assets/materials/base_color/mat_base_red_2.tres")
const INDICATOR_ORANGE: StandardMaterial3D = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_orange_0.tres")
const INDICATOR_GREEN: Material = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_green_0.tres")

class BatchClock extends Node:
	var effective_seconds: float = 0.0

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_physics_priority = 1000

	func _physics_process(delta: float) -> void:
		if not get_tree().paused:
			effective_seconds += delta

var denied_count: int = 0
var completed_batches: int = 0
var started_batches: int = 0
var timing_samples: Array[Dictionary] = []
var batch_clock: BatchClock
var batch_start_seconds: float = 0.0
var indicator_records: Array[Dictionary] = []


func run_checks() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/液体罐内容与配药器装填实施证据/20261002/integration")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	batch_clock = BatchClock.new()
	root.add_child(batch_clock)
	_test_contents_data()
	await _new_scene()
	_check_indicator(INDICATOR_DEFAULT, "初次正式场景无罐无药保持红色")
	await _enter()
	await _test_tank_candidate_failure()
	await _new_scene()
	await _enter()
	machine.handle.handle_pull_denied.connect(func(_actor: Node3D, _reason: StringName) -> void: denied_count += 1)
	machine.processing_started.connect(_on_batch_started)
	machine.processing_completed.connect(_on_batch_completed)
	await _test_restricted_handle()
	await _test_tank_and_batch()
	await _test_full_tank_transfer()
	await _test_batch_boundaries()
	await _test_failed_batch()
	_save_liquid_report()
	_release_controls()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	if is_instance_valid(world):
		world.queue_free()
	await frames(2)
	print("液体内容与配药验收断言数：", assertion_count, "；失败总数：", failures)
	quit(1 if failures > 0 else 0)


func _test_contents_data() -> void:
	var ids: Array[String] = ["caffeine", "sodium_benzoate", "caffeine"]
	var contents: AutolysisLiquidContents = AutolysisLiquidContents.create_result(ids)
	check(contents != null and contents.is_valid_contents(), "合法一至四份原药可建立内容")
	check(contents.get_raw_material_ids() == ids and contents.get_raw_material_display() == "咖啡因*2、苯甲酸钠", "内部重复与顺序保留，界面按首次出现位置合并")
	var copy: Array[String] = contents.get_raw_material_ids()
	copy.clear()
	check(contents.get_raw_material_ids() == ids, "读取原药数组返回副本")
	check(contents.get_phase_rgb() == Vector3.ZERO and contents.get_wave_coordinates() == [0, 0, 0, 0, 0], "新配药结果重构数据全零")
	check(contents.set_phase_rgb(Vector3(2.5, -3.0, 8.0)), "相位允许范围未定义的有限数值")
	check(not contents.set_phase_rgb(Vector3(INF, 0, 0)) and contents.get_phase_rgb() == Vector3(2.5, -3.0, 8.0), "非有限相位拒绝且保留旧数据")
	check(contents.set_wave(true, false, true, true, 6), "波形上界六可写入")
	check(not contents.set_wave(false, false, false, false, 7) and not contents.set_wave(false, false, false, false, -1), "波形越界拒绝")
	check(contents.get_wave_coordinates() == [1, 0, 1, 1, 6], "波形拒绝写入保留全部旧值")
	check(contents.set_wave(false, false, false, false, 0), "波形下界零可写入")
	var empty: Array[String] = []
	var unknown: Array[String] = ["not_a_material"]
	var too_many: Array[String] = ["caffeine", "caffeine", "caffeine", "caffeine", "caffeine"]
	check(AutolysisLiquidContents.create_result(empty) == null and AutolysisLiquidContents.create_result(unknown) == null and AutolysisLiquidContents.create_result(too_many) == null, "零份、未知标识、五份拒绝")
	var first: AutolysisLiquidTank = TANK_SCENE.instantiate() as AutolysisLiquidTank
	var second: AutolysisLiquidTank = TANK_SCENE.instantiate() as AutolysisLiquidTank
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	holder.add_child(first)
	holder.add_child(second)
	check(first.item_instance != second.item_instance, "同定义两个世界罐具有独立实例")
	check(first.apply_contents(contents) and not first.is_empty() and second.is_empty(), "装填一罐不改变另一罐")
	var first_mesh: MeshInstance3D = AutolysisLiquidTankVisual.get_contents_mesh(first)
	var second_mesh: MeshInstance3D = AutolysisLiquidTankVisual.get_contents_mesh(second)
	check(first_mesh.material_override != second_mesh.material_override, "空满罐使用各自材质覆盖引用")
	check(second.apply_contents(contents) and first.item_instance.liquid_contents != second.item_instance.liquid_contents, "两罐装填同一输入内容时各自持有独立内容副本")
	check(first.item_instance.liquid_contents.set_phase_rgb(Vector3(9, 8, 7)) and second.item_instance.get_phase_rgb() == Vector3(2.5, -3, 8), "任意一罐重构不污染另一罐或调用方内容")
	holder.queue_free()


func _machine_pixel(wanted: Node3D) -> Vector2:
	var collision: CollisionShape3D
	for child: Node in wanted.get_children():
		if child is CollisionShape3D:
			collision = child as CollisionShape3D
			break
	if collision != null and collision.shape is BoxShape3D:
		var size: Vector3 = (collision.shape as BoxShape3D).size
		for x: float in [-0.4, -0.2, 0.0, 0.2, 0.4]:
			for y: float in [-0.4, -0.2, 0.0, 0.2, 0.4]:
				for z: float in [-0.4, 0.0, 0.4]:
					var pixel: Vector2 = player.camera.unproject_position(collision.to_global(Vector3(x, y, z) * size))
					if Rect2(Vector2.ZERO, Vector2(root.size)).has_point(pixel) and _query(pixel) == wanted:
						ray_records.append({"目标": str(wanted.get_path()), "像素": str(pixel)})
						return pixel
	check(false, "真实有限射线找到罐位或拉杆首命中")
	return INVALID_PIXEL


func _restricted_once(description: String) -> void:
	var point: Vector2 = _machine_pixel(machine.handle)
	var old_denied: int = denied_count
	_button(MOUSE_BUTTON_LEFT, true, point)
	await frames(1)
	_move_cursor(point + Vector2(0, 20), Vector2(0, 20))
	await frames(1)
	check(is_equal_approx(machine.handle.position.y, 0.12 - 20.0 * machine.handle.mouse_to_handle_ratio * 0.5), description + "受限拖动使用一半比例")
	_move_cursor(point + Vector2(0, 500), Vector2(0, 480))
	await frames(1)
	check(machine.handle.position.is_equal_approx(Vector3(0, 0.08, 0)) and not machine.is_batch_running(), description + "受限下限为零点零八且不加工")
	check(denied_count == old_denied + 1, description + "一次实际开始只发一次禁止消息")
	_button(MOUSE_BUTTON_LEFT, false, point)
	await frames(6)
	check(machine.handle.position.is_equal_approx(Vector3(0, 0.12, 0)) and denied_count == old_denied + 1, description + "松手归顶且不追加消息")
	_check_indicator(INDICATOR_COMPLETED if machine.get("_completed_tank_instance") != null else INDICATOR_DEFAULT, description + "受限拉杆没有产生运行闪烁且保持当前静态显示")


func _test_restricted_handle() -> void:
	var old_denied: int = denied_count
	for _index: int in range(5):
		machine.handle.drag_interaction.can_interact(player)
	check(denied_count == old_denied, "许可查询没有禁止消息副作用")
	await _restricted_once("无罐无药：")
	check(inventory.try_receive_item(TANK_DEFINITION), "准备正式空罐")
	var source: AutolysisItemInstance = inventory.get_focused_instance()
	check(not inventory.try_place_in_blend_tank_place(player, other_machine.tank_place), "跨设备罐位拒绝放入")
	check(inventory.get_focused_instance() == source, "跨设备失败保留原罐实例")
	await _click(_machine_pixel(machine.tank_place))
	check(machine.tank_place.get_stored_item() != null and machine.tank_place.get_stored_item().item_instance == source and inventory.get_focused_instance() == null, "真实点击空罐位转移原实例")
	await _restricted_once("有空罐无原药：")
	await _capture("01-empty-tank.png")


func _test_tank_candidate_failure() -> void:
	var definition: AutolysisItemDefinition = TANK_DEFINITION.duplicate() as AutolysisItemDefinition
	var broken_world: AutolysisLiquidTank = TANK_SCENE.instantiate() as AutolysisLiquidTank
	broken_world.get_node("mesh").free()
	var packed: PackedScene = PackedScene.new()
	check(packed.pack(broken_world) == OK, "打包缺少内容网格的真实世界罐故障夹具")
	broken_world.free()
	var world_path: String = evidence_directory + "/fault_tank_visual.tscn"
	check(ResourceSaver.save(packed, world_path) == OK, "保存候选准备故障夹具以便复跑")
	definition.world_scene_path = world_path
	check(inventory.try_receive_item(definition), "世界候选故障保留合法手持源罐")
	var instance: AutolysisItemInstance = inventory.get_focused_instance()
	var display: Node3D = player.held_item_presenter.get_display()
	check(inventory.can_place_in_blend_tank_place(player, machine.tank_place), "世界场景描述合法但候选显示依赖故障")
	check(not inventory.try_place_in_blend_tank_place(player, machine.tank_place) and inventory.get_focused_instance() == instance and player.held_item_presenter.get_display() == display and machine.tank_place.get_stored_item() == null, "世界候选显示准备失败保留源罐、手持与空罐位")
	definition.world_scene_path = TANK_DEFINITION.world_scene_path
	check(inventory.try_place_in_blend_tank_place(player, machine.tank_place), "故障修复后同一源罐可正常放入")
	var tank: AutolysisLiquidTank = machine.tank_place.get_stored_item()
	var ids: Array[String] = ["sodium_benzoate", "caffeine", "sodium_benzoate"]
	var contents: AutolysisLiquidContents = AutolysisLiquidContents.create_result(ids)
	contents.set_phase_rgb(Vector3(7, 8, 9))
	check(tank.apply_contents(contents), "取回候选故障夹具准备满罐")
	await frames(2)
	_check_indicator(INDICATOR_DEFAULT, "外部直接装填满罐不建立本机绿色完成态")
	var held_root: Node3D = Node3D.new()
	var broken_held: PackedScene = PackedScene.new()
	check(broken_held.pack(held_root) == OK, "打包无内容网格但符合纯显示规则的手持夹具")
	held_root.free()
	definition.visual_scene = broken_held
	check(inventory.can_take_from_blend_tank_place(player, machine.tank_place), "满罐定义可读但手持内容网格缺失")
	check(not inventory.try_take_from_blend_tank_place(player, machine.tank_place) and machine.tank_place.owns_item(tank) and inventory.get_focused_instance() == null and tank.item_instance == instance and instance.liquid_contents.get_phase_rgb() == Vector3(7, 8, 9), "手持候选准备失败保留罐位原满罐及完整内容")
	definition.visual_scene = TANK_DEFINITION.visual_scene
	check(inventory.try_take_from_blend_tank_place(player, machine.tank_place) and inventory.get_focused_instance() == instance, "修复手持依赖后可取回原满罐")


func _load_slot(index: int, definition: AutolysisItemDefinition) -> void:
	await _click(_pixel(index))
	await _wait_blend_slot(machine.slots[index], true)
	check(inventory.try_receive_item(definition), "当前选中空格接收原药")
	await _click(_pixel(index, true))
	check(machine.slots[index].get_stored_item() != null and inventory.get_focused_item() == null, "真实射线点击将原药放入指定槽")
	await _click(_pixel(index))
	await _wait_blend_slot(machine.slots[index], false)


func _wait_blend_slot(slot: AutolysisBlendSlot, opened: bool) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while slot.is_animating() and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(slot.is_open() if opened else slot.is_closed(), "对应槽门完成目标动作；%s" % slot.get_motion_error())


func _start_batch_input() -> void:
	var point: Vector2 = _machine_pixel(machine.handle)
	_button(MOUSE_BUTTON_LEFT, true, point)
	await frames(1)
	_move_cursor(point + Vector2(0, 300), Vector2(0, 300))
	await frames(1)
	_button(MOUSE_BUTTON_LEFT, false, point)
	check(machine.is_batch_running(), "正常最低点经真实输入启动配药")


func _test_tank_and_batch() -> void:
	await _load_slot(2, CAFFEINE)
	await _click(_pixel(0))
	await _wait_blend_slot(machine.slots[0], true)
	check(not machine.can_start_processing(), "空槽门完全打开仍阻止启动")
	_check_indicator(INDICATOR_DEFAULT, "空槽门打开期间红色")
	await _restricted_once("空槽门打开：")
	await _click(_pixel(0))
	check(not machine.can_start_processing(), "空槽门关闭运动中不能启动")
	_check_indicator(INDICATOR_DEFAULT, "空槽门关闭动画期间红色")
	await _wait_blend_slot(machine.slots[0], false)
	check(machine.can_start_processing(), "四门完全关闭、一份原药与空罐允许启动")
	_check_indicator(INDICATOR_READY, "关门动画结束并满足完整启动条件后橙色常亮")
	var old_denied_for_cancel: int = denied_count
	check(machine.handle.try_begin_drag(player) and not machine.handle.is_restricted_drag(), "合法前提选择正常拖动")
	machine.handle.apply_vertical_motion(player, 40)
	check(machine.slots[0].try_toggle(player), "正常拖动中实际改变空槽门前提")
	await _wait_blend_slot(machine.slots[0], true)
	check(not machine.handle.is_dragging_for(player) and not machine.is_batch_running() and denied_count == old_denied_for_cancel, "正常拖动期间启动前提失效时取消且不发禁止或完成")
	await _click(_pixel(0))
	await _wait_blend_slot(machine.slots[0], false)
	var source: AutolysisRawMaterial = machine.slots[2].get_stored_item()
	var tank: AutolysisLiquidTank = machine.tank_place.get_stored_item()
	var old_completed: int = completed_batches
	await _start_batch_input()
	_check_indicator(INDICATOR_RUNNING, "真实拉杆完成且实际启动后橙色闪烁")
	check(machine.slots[2].get_stored_item() == source and tank.is_empty(), "启动只记录快照，原药仍在且罐仍空")
	var old_started: int = started_batches
	check(not machine.try_start_processing(player) and started_batches == old_started, "同帧重入请求不建立另一批次")
	machine.processing_timer.timeout.emit()
	check(machine.is_batch_running() and tank.is_empty() and machine.slots[2].get_stored_item() == source, "提前计时回调不能越过两秒或消费来源")
	var remaining: float = machine.processing_timer.time_left
	var old_denied: int = denied_count
	for slot: AutolysisBlendSlot in machine.slots:
		check(not slot.toggle_interaction.try_interact(player) and not slot.try_toggle(player), "运行中槽门组件与业务入口拒绝")
		check(not slot.transfer_interaction.try_interact(player) and not slot.try_begin_transfer(player), "运行中原药取放组件与业务入口拒绝")
	check(not machine.tank_place.transfer_interaction.try_interact(player) and not inventory.try_take_from_blend_tank_place(player, machine.tank_place), "运行中罐位组件与库存业务拒绝")
	check(not machine.handle.drag_interaction.try_interact(player) and not machine.handle.try_begin_drag(player), "运行中拉杆组件与业务拒绝")
	check(not machine.root_interaction.try_interact(player, AutolysisInteractionComponent.InteractionMode.FOCUS), "运行中根聚焦组件拒绝")
	check(denied_count == old_denied, "运行中拉杆请求不发送禁止消息")
	paused = true
	var paused_energy: float = (machine.get("_indicator_orange_material") as StandardMaterial3D).emission_energy_multiplier
	await frames(20)
	check(is_equal_approx(machine.processing_timer.time_left, remaining) and tank.is_empty(), "暂停冻结配药游戏时间且不装填")
	check(is_equal_approx((machine.get("_indicator_orange_material") as StandardMaterial3D).emission_energy_multiplier, paused_energy), "暂停同时冻结运行指示灯倍率")
	paused = false
	await _exit()
	check(machine.is_batch_running() and not focus.can_enter(machine.focus_target) and not focus.try_enter(machine.focus_target), "运行中允许退出，公开进入接口拒绝重入")
	_check_indicator(INDICATOR_RUNNING, "退出聚焦仍保持真实加工与闪烁")
	for _index: int in range(150):
		if not machine.is_batch_running():
			break
		timing_samples.append({"剩余秒数": machine.processing_timer.time_left, "仍有原药": machine.slots[2].get_stored_item() == source, "罐为空": tank.is_empty(), "物理帧": Engine.get_physics_frames()})
		await frames(1)
	check(not machine.is_batch_running() and completed_batches == old_completed + 1, "退出聚焦后单批次只完成一次")
	machine.processing_timer.timeout.emit()
	check(completed_batches == old_completed + 1, "重复计时回调不重复消费或装填")
	check(machine.slots[2].get_stored_item() == null and not tank.is_empty(), "完成后消费原药并装填留在设备中的罐")
	_check_indicator(INDICATOR_COMPLETED, "成功提交且解除运行状态后绿色无循环")
	check(tank.item_instance.liquid_contents.get_raw_material_ids() == ["caffeine"], "一份原药加工记录正确")
	await _enter()
	await _capture("02-full-tank.png")
	var filled_instance: AutolysisItemInstance = tank.item_instance
	await _click(_machine_pixel(machine.tank_place))
	check(inventory.get_focused_instance() == filled_instance and machine.tank_place.get_stored_item() == null, "真实点击满罐位取回原实例")
	_check_indicator(INDICATOR_DEFAULT, "成功取走完成罐后恢复红色")
	check(machine.get("_completed_tank_instance") == null, "成功取罐清除完成实例凭据")
	check(player.liquid_contents_panel.is_showing_contents() and player.liquid_contents_panel.get_contents_text().contains("原药：咖啡因"), "手持满罐显示全部内容")


func _test_full_tank_transfer() -> void:
	var instance: AutolysisItemInstance = inventory.get_focused_instance()
	var contents: AutolysisLiquidContents = instance.liquid_contents
	check(contents.set_phase_rgb(Vector3(2, -4, 6)) and contents.set_wave(true, false, true, true, 4), "重构预留接口写入合法非零值")
	check(player.liquid_contents_panel.get_contents_text().contains("r（红）＝2") and player.liquid_contents_panel.get_contents_text().contains("（1，0，1，1，4）"), "内容变化通知立即刷新相位及波形文本")
	check(player.liquid_contents_panel.get_node("Panel").mouse_filter == Control.MOUSE_FILTER_IGNORE and player.liquid_contents_panel.get_node("Panel/Margin/Text").mouse_filter == Control.MOUSE_FILTER_IGNORE, "左上角面板及文本忽略鼠标")
	await _click(_machine_pixel(machine.tank_place))
	check(inventory.get_focused_instance() == instance and machine.tank_place.get_stored_item() == null, "真实点击空罐位拒绝手持满罐")
	await _capture("03-held-full-tank.png")
	check(inventory.cycle_focus(1), "切换到另一空格")
	check(not player.liquid_contents_panel.is_showing_contents(), "空手立即隐藏内容界面")
	check(inventory.try_receive_item(TANK_DEFINITION), "准备另一独立空罐")
	check(not player.liquid_contents_panel.is_showing_contents(), "空罐隐藏内容界面")
	await _click(_machine_pixel(machine.tank_place))
	check(machine.tank_place.get_stored_item().is_empty() and instance.liquid_contents == contents, "另一空罐放入不污染原满罐")
	await _click(_machine_pixel(machine.tank_place))
	var second: AutolysisItemInstance = inventory.get_focused_instance()
	check(second != instance and second.is_empty_liquid_tank(), "同定义另一罐保留独立身份")
	check(inventory.cycle_focus(-1) and inventory.get_focused_instance() == instance, "切回满罐完整恢复原实例")
	check(player.liquid_contents_panel.is_showing_contents() and player.liquid_contents_panel.get_contents_text().contains("（1，0，1，1，4）"), "切回满罐恢复对应内容界面")
	await _exit()
	if not graphical:
		records.append({"说明": "无图形后端缺少普通鼠标捕获；满罐柜库存链路由同脚本图形运行覆盖", "未覆盖": true})
		await _enter()
		return
	var cabinet: AutolysisLiquidTankCabinet = CABINET_SCENE.instantiate() as AutolysisLiquidTankCabinet
	for index: int in range(2):
		for child: Node in cabinet.get_node("liquid_tank_slot_%d" % index).get_children():
			child.free()
	world.add_child(cabinet)
	check(cabinet.try_toggle(player), "正式柜门入口打开空柜")
	await frames(20)
	for _index: int in range(3):
		check(inventory.try_place_in_liquid_tank_cabinet(player, cabinet), "满罐可经库存业务放入专用柜")
		var stored: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
		check(stored != null and stored.item_instance == instance and stored.item_instance.liquid_contents == contents, "柜中罐完整持有原实例及内容")
		check(inventory.try_take_liquid_tank(player, stored) and inventory.get_focused_instance() == instance, "专用柜取回保持原罐身份")
	check(contents.get_phase_rgb() == Vector3(2, -4, 6) and contents.get_wave_coordinates() == [1, 0, 1, 1, 4], "多轮柜库存转移完整保留非零重构")
	cabinet.queue_free()
	await frames(2)
	await _enter()


func _test_batch_boundaries() -> void:
	await _new_scene()
	await _enter()
	machine.handle.handle_pull_denied.connect(func(_actor: Node3D, _reason: StringName) -> void: denied_count += 1)
	await _load_slot(0, CAFFEINE)
	await _restricted_once("有药无罐：")
	for arrangement: Array in [[CAFFEINE, SODIUM, CAFFEINE, SODIUM], [CAFFEINE, CAFFEINE, CAFFEINE, CAFFEINE], [null, SODIUM, null, CAFFEINE]]:
		await _new_scene()
		await _enter()
		machine.processing_started.connect(_on_batch_started)
		machine.processing_completed.connect(_on_batch_completed)
		machine.handle.handle_pull_denied.connect(func(_actor: Node3D, _reason: StringName) -> void: denied_count += 1)
		check(inventory.try_receive_item(TANK_DEFINITION), "数量边界批次准备空罐")
		await _click(_machine_pixel(machine.tank_place))
		for index: int in [3, 2, 1, 0]:
			if arrangement[index] != null:
				await _load_slot(index, arrangement[index])
		var expected: Array[String] = []
		for definition: AutolysisItemDefinition in arrangement:
			if definition != null:
				expected.append(String(definition.item_id))
		await _start_batch_input()
		await frames(125)
		var tank: AutolysisLiquidTank = machine.tank_place.get_stored_item()
		check(not machine.is_batch_running() and tank.item_instance.liquid_contents.get_raw_material_ids() == expected, "倒序实际装药仍按槽号收集，四份、四同种、稀疏批次均完成")
		await _load_slot(0, CAFFEINE)
		check(not machine.can_start_processing(), "补药后满罐仍占位时不能启动下一轮")
		_check_indicator(INDICATOR_COMPLETED, "完成罐仍在时再次开关槽门与补药保持绿色")
		await _restricted_once("满罐占位：")


func _test_failed_batch() -> void:
	await _new_scene()
	await _enter()
	check(inventory.try_receive_item(TANK_DEFINITION), "故障批次准备空罐")
	await _click(_machine_pixel(machine.tank_place))
	await _load_slot(0, CAFFEINE)
	await _load_slot(3, SODIUM)
	await _start_batch_input()
	var retained: AutolysisRawMaterial = machine.slots[0].get_stored_item()
	var invalidated: AutolysisRawMaterial = machine.slots[3].get_stored_item()
	invalidated.queue_free()
	await frames(125)
	check(machine.is_interaction_locked() and machine.slots[0].get_stored_item() == retained and machine.tank_place.get_stored_item().is_empty(), "完成前来源失效时锁定设备，保留其他原药且不生成部分药液")
	_check_indicator(INDICATOR_DEFAULT, "加工失败停止闪烁并恢复红色")
	machine.tank_place.queue_free()
	await frames(2)
	check(not machine.focus_target.is_valid_target() and focus.state == INACTIVE, "已登记罐位释放后聚焦目标失效并结束会话")


func _on_batch_started(_value: Variant = null) -> void:
	started_batches += 1
	batch_start_seconds = batch_clock.effective_seconds
	_check_indicator(INDICATOR_RUNNING, "加工开始信号观察到同步进入运行显示")


func _on_batch_completed(_value: Variant = null, _contents: Variant = null) -> void:
	completed_batches += 1
	var elapsed: float = batch_clock.effective_seconds - batch_start_seconds
	timing_samples.append({"完成有效秒数": elapsed, "开始批次数": started_batches, "完成批次数": completed_batches})
	check(absf(elapsed - 2.0) <= 1.0 / float(Engine.physics_ticks_per_second) + 0.00001, "装填计时为两秒有效游戏时间，误差最多一物理帧")
	_check_indicator(INDICATOR_COMPLETED, "加工完成信号观察到同步进入绿色完成显示")


func _check_indicator(expected_state: int, description: String, target: Node3D = null) -> void:
	var device: Node3D = machine if target == null else target
	var lamp: MeshInstance3D = device.get("status_indicator") as MeshInstance3D
	var orange: StandardMaterial3D = device.get("_indicator_orange_material") as StandardMaterial3D
	var tween: Tween = device.get("_indicator_tween") as Tween
	var actual_state: int = int(device.get("_indicator_state"))
	var material: Material = lamp.material_override if is_instance_valid(lamp) else null
	var material_valid: bool = material == orange if expected_state in [INDICATOR_READY, INDICATOR_RUNNING] else material == (INDICATOR_GREEN if expected_state == INDICATOR_COMPLETED else INDICATOR_RED)
	var tween_valid: bool = tween != null and tween.is_valid()
	var expected_tween: bool = expected_state == INDICATOR_RUNNING
	var energy_valid: bool = expected_state != INDICATOR_READY or (orange != null and is_equal_approx(orange.emission_energy_multiplier, 2.0))
	check(is_instance_valid(lamp) and actual_state == expected_state and material_valid and tween_valid == expected_tween and energy_valid, description)
	indicator_records.append({"说明": description, "设备": str(device.get_path()), "状态": actual_state, "预期状态": expected_state, "物理帧": Engine.get_physics_frames(), "橙色倍率": orange.emission_energy_multiplier if orange != null else -1.0, "补间有效": tween_valid, "补间实例": tween.get_instance_id() if tween != null else 0})


func _save_liquid_report() -> void:
	var file: FileAccess = FileAccess.open(evidence_directory + "/liquid-contents-blend.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "断言": records, "禁止消息数": denied_count, "开始批次数": started_batches, "完成批次数": completed_batches, "计时采样": timing_samples, "指示灯状态": indicator_records, "射线": ray_records, "画面": screenshots, "图形后端": graphical, "输入范围": "自动注入输入；不声称本机人工鼠标验收"}, "\t"))
