extends SceneTree
## 从胶囊纯显示模型实际渲染透明图标；保留独立相机参数及可复跑证据。

const ICON_SIZE: Vector2i = Vector2i(256, 256)
const VISUAL_PATH: String = "res://main-autolysis/scenes/prefabs/prefab_machines/visuals/pneumatic_capsule_visual.tscn"
const ICON_PATH: String = "res://main-autolysis/assets/ui/item-icons/pneumatic_capsule.png"
const CAMERA_POSITION: Vector3 = Vector3(0.75, 0.48, 0.95)
const CAMERA_TARGET: Vector3 = Vector3.ZERO
const CAMERA_SIZE: float = 1.12

var _evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/封装器与气动胶囊实施证据/20261003/data")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("气动胶囊图标需要真实图形渲染，不能使用无图形空渲染模式。")
		quit(1)
		return
	for directory: String in [ICON_PATH.get_base_dir(), _evidence_directory]:
		var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		if directory_error != OK:
			push_error("图标或证据输出目录创建失败，错误码：%d" % directory_error)
			quit(1)
			return
	var visual_scene: PackedScene = load(VISUAL_PATH) as PackedScene
	if visual_scene == null or not visual_scene.can_instantiate():
		push_error("气动胶囊纯显示资源无法实例化。")
		quit(1)
		return
	var visual_node: Node = visual_scene.instantiate()
	if not visual_node is Node3D or not _is_display_only(visual_node):
		visual_node.free()
		push_error("气动胶囊纯显示场景含脚本、碰撞或交互对象。")
		quit(1)
		return
	var viewport: SubViewport = SubViewport.new()
	viewport.size = ICON_SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var scene_root: Node3D = Node3D.new()
	viewport.add_child(scene_root)
	scene_root.add_child(visual_node)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = environment
	scene_root.add_child(environment_node)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	key_light.light_energy = 1.4
	scene_root.add_child(key_light)
	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-25.0, 140.0, 0.0)
	fill_light.light_energy = 0.5
	scene_root.add_child(fill_light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_SIZE
	camera.near = 0.01
	camera.far = 10.0
	scene_root.add_child(camera)
	camera.position = CAMERA_POSITION
	camera.look_at(CAMERA_TARGET)
	camera.current = true
	for _frame_index: int in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var rendered_image: Image = viewport.get_texture().get_image()
	var report: Dictionary = _inspect_pixels(rendered_image)
	report["引擎版本"] = Engine.get_version_info()["string"]
	report["渲染后端"] = RenderingServer.get_current_rendering_method()
	report["图形驱动"] = RenderingServer.get_current_rendering_driver_name()
	report["纯显示资源"] = VISUAL_PATH
	report["模型网格数"] = visual_node.find_children("", "MeshInstance3D", true, false).size()
	report["相机位置"] = str(CAMERA_POSITION)
	report["观察目标"] = str(CAMERA_TARGET)
	report["正交相机尺寸"] = CAMERA_SIZE
	report["输出图标"] = ICON_PATH
	if report["通过"]:
		var save_error: Error = rendered_image.save_png(ProjectSettings.globalize_path(ICON_PATH))
		report["保存成功"] = save_error == OK
		report["通过"] = save_error == OK
		if save_error == OK:
			report["图标散列摘要"] = FileAccess.get_sha256(ICON_PATH)
	var report_file: FileAccess = FileAccess.open(_evidence_directory.path_join("气动胶囊图标渲染结果.json"), FileAccess.WRITE)
	if report_file == null:
		push_error("气动胶囊图标渲染证据无法写入。")
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	viewport.queue_free()
	print("气动胶囊图标真实渲染结果：", JSON.stringify(report))
	quit(0 if report["通过"] else 1)


func _is_display_only(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node.get_script() != null or node.is_in_group(&"interactable"):
		return false
	for child: Node in node.get_children():
		if not _is_display_only(child):
			return false
	return true


func _inspect_pixels(rendered_image: Image) -> Dictionary:
	if rendered_image == null or rendered_image.is_empty() or rendered_image.get_size() != ICON_SIZE:
		return {"通过": false, "原因": "渲染图像为空或尺寸错误"}
	var opaque_pixels: int = 0
	var transparent_pixels: int = 0
	var brightness_min: float = INF
	var brightness_max: float = -INF
	var minimum: Vector2i = ICON_SIZE
	var maximum: Vector2i = Vector2i(-1, -1)
	for y: int in range(ICON_SIZE.y):
		for x: int in range(ICON_SIZE.x):
			var pixel: Color = rendered_image.get_pixel(x, y)
			if pixel.a < 0.01:
				transparent_pixels += 1
			elif pixel.a > 0.9:
				opaque_pixels += 1
				var brightness: float = (pixel.r + pixel.g + pixel.b) / 3.0
				brightness_min = minf(brightness_min, brightness)
				brightness_max = maxf(brightness_max, brightness)
			if pixel.a > 0.01:
				minimum.x = mini(minimum.x, x)
				minimum.y = mini(minimum.y, y)
				maximum.x = maxi(maximum.x, x)
				maximum.y = maxi(maximum.y, y)
	var enough_margin: bool = minimum.x >= 8 and minimum.y >= 8 and maximum.x < ICON_SIZE.x - 8 and maximum.y < ICON_SIZE.y - 8
	return {
		"通过": opaque_pixels > 1024 and transparent_pixels > 1024 and brightness_max - brightness_min > 0.05 and enough_margin,
		"图标尺寸": str(ICON_SIZE),
		"不透明像素": opaque_pixels,
		"透明像素": transparent_pixels,
		"亮度最小值": brightness_min,
		"亮度最大值": brightness_max,
		"可见像素左上": str(minimum),
		"可见像素右下": str(maximum),
		"至少八像素留白": enough_margin,
	}
