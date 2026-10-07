extends SceneTree
## 使用正式玩家相机及全部原模型网格投影校正姿态；复跑默认只验证，不改资源。

const DEFINITION_PATH: String = "res://main-autolysis/systems/item-system/items/pneumatic_capsule.tres"
const DEMO_SCENE: PackedScene = preload("res://main-autolysis/systems/item-system/tests/packing_machine_demo.tscn")
const VIEW_SIZE: Vector2i = Vector2i(1280, 720)
const EDGE_MARGIN: float = 16.0
const NUMERIC_MARGIN: float = 1.0

var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/封装器与气动胶囊实施证据/20261003/hand-pose")
var world: Node3D
var player: AutolysisPlayer
var machine: AutolysisPackingMachine
var definition: AutolysisItemDefinition
var display: Node3D
var samples: Array[Dictionary] = []
var failures: int = 0
var calibrating: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("手持姿态检查必须使用实际图形后端。")
		quit(1)
		return
	calibrating = OS.get_cmdline_user_args().has("--calibrate")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = VIEW_SIZE
	world = DEMO_SCENE.instantiate() as Node3D
	world.get_node("MachineA").free()
	world.get_node("MachineB").free()
	root.add_child(world)
	player = world.get_node("Player") as AutolysisPlayer
	machine = world.get_node("PackingA") as AutolysisPackingMachine
	await _frames(30)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.body.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.eyes.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.head.look_at(machine.to_global(Vector3(-0.24, 0.5, 0.32)), Vector3.UP)
	await _frames(3)
	definition = load(DEFINITION_PATH) as AutolysisItemDefinition
	var ids: Array[String] = ["caffeine", "sodium_benzoate", "caffeine", "sodium_benzoate"]
	var source: AutolysisLiquidContents = AutolysisLiquidContents.create_result(ids)
	source.set_phase_rgb(Vector3(3.5, -3, 8))
	source.set_wave(true, false, true, true, 6)
	var capsule: AutolysisItemInstance = AutolysisItemInstance.create(definition)
	if capsule == null or not capsule.set_packing_contents(AutolysisPackingContents.create_result(source, 1)) or not player.inventory_controller.try_receive_instance(capsule):
		push_error("正式玩家无法准备封装胶囊。")
		quit(1)
		return
	display = player.held_item_presenter.get_display()
	if not player.focus_controller.try_enter(machine.focus_target):
		push_error("正式玩家无法进入封装器聚焦。")
		quit(1)
		return
	await _frames(30)
	if not player.focus_controller.is_focused_on(machine.focus_target):
		push_error("正式玩家聚焦过渡未完成。")
		quit(1)
		return
	var before: Dictionary = _measure("校正前聚焦")
	await _capture("校正前聚焦.png")
	var original_position: Vector3 = definition.held_position
	var original_scale: Vector3 = definition.held_scale
	if calibrating and not _calibrate():
		failures += 1
		push_error("实际投影校正未取得符合边距的完整姿态。")
	var focused: Dictionary = _measure("最终聚焦")
	_check_pose(focused)
	await _capture("最终聚焦胶囊.png")
	if calibrating and failures == 0:
		definition.held_position = display.position
		definition.held_scale = display.scale
		if ResourceSaver.save(definition, DEFINITION_PATH) != OK:
			failures += 1
			push_error("已经校正的胶囊手持姿态无法保存。")
	player.focus_controller.request_exit()
	await _frames(30)
	var normal: Dictionary = _measure("最终普通视角")
	_check_pose(normal)
	await _capture("最终普通视角胶囊.png")
	var label: AutolysisLiquidContentsPanel = player.get_node("LiquidContentsPanel") as AutolysisLiquidContentsPanel
	if not label.is_showing_contents() or not label.get_contents_text().contains("封装类型：酊剂") or AutolysisPneumaticCapsuleVisual.get_contents_mesh(display).material_override != AutolysisPneumaticCapsuleVisual.PACKED_MATERIAL:
		failures += 1
		push_error("姿态校正后内容面板或绿色标识失效。")
	var report: Dictionary = {"引擎版本": Engine.get_version_info()["string"], "实际图形驱动": RenderingServer.get_current_rendering_driver_name(), "画面尺寸": str(VIEW_SIZE), "要求边距像素": EDGE_MARGIN, "校正模式": calibrating, "原手持位置": str(original_position), "原手持缩放": str(original_scale), "最终手持位置": str(display.position), "最终手持缩放": str(display.scale), "校正前": before, "最终聚焦": focused, "最终普通视角": normal, "投影求解采样": samples, "失败数": failures, "通过": failures == 0}
	var report_file: FileAccess = FileAccess.open(evidence_directory.path_join("手持姿态投影结果.json"), FileAccess.WRITE)
	if report_file == null:
		failures += 1
	else:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print("手持姿态实际投影结果：", JSON.stringify({"校正前": before, "最终聚焦": focused, "最终普通视角": normal, "最终手持位置": str(display.position), "最终手持缩放": str(display.scale), "失败数": failures}))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.queue_free()
	await _frames()
	quit(0 if failures == 0 else 1)


func _calibrate() -> bool:
	var safe_height: float = float(VIEW_SIZE.y) - 2.0 * (EDGE_MARGIN + NUMERIC_MARGIN)
	var initial: Dictionary = _measure("求解初始")
	var rectangle: Rect2 = initial["rectangle"]
	# 先按实测投影高度决定是否缩小，能完整容纳时保留既有缩放。
	if rectangle.size.y > safe_height:
		display.scale *= safe_height / rectangle.size.y
	var target_bottom: float = float(VIEW_SIZE.y) - EDGE_MARGIN - NUMERIC_MARGIN
	var current_y: float = display.position.y
	var step: float = _local_model_height() * display.scale.y
	var lower: float = current_y - step
	var upper: float = current_y + step
	# 通过实际投影建立单调区间，区间不足时才按原模型尺寸倍增。
	for _index: int in range(12):
		display.position.y = lower
		var low_rectangle: Rect2 = _measure("求解下界")["rectangle"]
		display.position.y = upper
		var high_rectangle: Rect2 = _measure("求解上界")["rectangle"]
		if low_rectangle.end.y >= target_bottom and high_rectangle.end.y <= target_bottom:
			break
		step *= 2.0
		lower = current_y - step
		upper = current_y + step
	for _index: int in range(32):
		display.position.y = (lower + upper) / 2.0
		var measured: Dictionary = _measure("求解二分")
		var projected: Rect2 = measured["rectangle"]
		samples.append({"本地纵坐标": display.position.y, "投影底边": projected.end.y})
		if projected.end.y > target_bottom:
			lower = display.position.y
		else:
			upper = display.position.y
	display.position.y = upper
	var result: Dictionary = _measure("求解完成")
	return _is_safe_pose(result)


func _local_model_height() -> float:
	var minimum: float = INF
	var maximum: float = -INF
	for mesh: MeshInstance3D in display.find_children("", "MeshInstance3D", true, false):
		var bounds: AABB = mesh.get_aabb()
		for corner_index: int in range(8):
			var point: Vector3 = display.to_local(mesh.to_global(bounds.get_endpoint(corner_index)))
			minimum = minf(minimum, point.y)
			maximum = maxf(maximum, point.y)
	return maximum - minimum


func _measure(description: String) -> Dictionary:
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	var all_in_front: bool = true
	var mesh_count: int = 0
	for mesh: MeshInstance3D in display.find_children("", "MeshInstance3D", true, false):
		mesh_count += 1
		var bounds: AABB = mesh.get_aabb()
		for corner_index: int in range(8):
			var point: Vector3 = mesh.to_global(bounds.get_endpoint(corner_index))
			all_in_front = all_in_front and not player.camera.is_position_behind(point)
			var pixel: Vector2 = player.camera.unproject_position(point)
			minimum = minimum.min(pixel)
			maximum = maximum.max(pixel)
	var rectangle: Rect2 = Rect2(minimum, maximum - minimum)
	var safe_rectangle: Rect2 = Rect2(Vector2.ONE * EDGE_MARGIN, Vector2(VIEW_SIZE) - Vector2.ONE * EDGE_MARGIN * 2.0)
	return {"说明": description, "rectangle": rectangle, "投影左上": str(minimum), "投影右下": str(maximum), "投影尺寸": str(rectangle.size), "所有端点在相机前": all_in_front, "全部网格数": mesh_count, "相机视野": player.camera.fov, "至少十六像素边距": safe_rectangle.encloses(rectangle), "位于画面右下": rectangle.get_center().x > float(VIEW_SIZE.x) / 2.0 and rectangle.get_center().y > float(VIEW_SIZE.y) / 2.0}


func _is_safe_pose(measured: Dictionary) -> bool:
	return measured["所有端点在相机前"] and measured["全部网格数"] == 6 and measured["至少十六像素边距"] and measured["位于画面右下"]


func _check_pose(measured: Dictionary) -> void:
	if not _is_safe_pose(measured):
		failures += 1
		push_error("手持姿态实际投影不符合全部网格与右下边距要求：%s" % str(measured))


func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(ProjectSettings.globalize_path(evidence_directory.path_join(filename))) != OK:
		failures += 1
		push_error("手持姿态实际截图保存失败。")


func _frames(count: int = 2) -> void:
	for _index: int in range(count):
		await physics_frame
		await process_frame
