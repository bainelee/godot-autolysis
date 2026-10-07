extends SceneTree

const ICON_SIZE: Vector2i = Vector2i(256, 256)
const OUTPUT_DIRECTORY: String = "res://main-autolysis/assets/ui/item-icons"
const VISUAL_DIRECTORY: String = "res://main-autolysis/scenes/prefabs/prefab_raw_materials/visuals"
const MATERIAL_NAMES: Array[String] = ["caffeine", "sodium_benzoate"]
const CAMERA_POSITION: Vector3 = Vector3(0.30, 0.22, 0.42)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.09, 0.0)
const CAMERA_SIZE: float = 0.26


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("图标生成需要实际渲染器，不能在无图形空渲染模式中运行。")
		quit(1)
		return
	var output_path: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_path)
	if directory_error != OK:
		push_error("无法创建图标输出目录，错误码：%d" % directory_error)
		quit(1)
		return
	for material_name: String in MATERIAL_NAMES:
		if not await _render_icon(material_name):
			quit(1)
			return
	print("两种原药图标实际渲染完成。尺寸：256×256，透明背景，正交相机尺寸：", CAMERA_SIZE)
	print("相机位置：", CAMERA_POSITION, "；观察目标：", CAMERA_TARGET)
	quit(0)


func _render_icon(material_name: String) -> bool:
	var scene_path: String = "%s/rm_%s_visual.tscn" % [VISUAL_DIRECTORY, material_name]
	var visual_scene: PackedScene = load(scene_path) as PackedScene
	if visual_scene == null:
		push_error("无法加载纯显示场景：%s" % scene_path)
		return false
	var visual_node: Node = visual_scene.instantiate()
	if not visual_node is Node3D:
		visual_node.free()
		push_error("纯显示场景根节点必须为三维节点：%s" % scene_path)
		return false
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
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	scene_root.add_child(world_environment)
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
	if not _has_visible_model(rendered_image):
		viewport.queue_free()
		push_error("渲染图像缺少可见模型或透明背景：%s" % scene_path)
		return false
	var target_path: String = "%s/%s.png" % [OUTPUT_DIRECTORY, material_name]
	var save_error: Error = rendered_image.save_png(ProjectSettings.globalize_path(target_path))
	viewport.queue_free()
	await process_frame
	if save_error != OK:
		push_error("保存图标失败，错误码：%d；输出：%s" % [save_error, target_path])
		return false
	print("图标已保存：", target_path, "；内容校验值：", FileAccess.get_sha256(target_path))
	return true


func _has_visible_model(rendered_image: Image) -> bool:
	if rendered_image == null or rendered_image.is_empty() or rendered_image.get_size() != ICON_SIZE:
		return false
	var opaque_pixels: int = 0
	var transparent_pixels: int = 0
	var brightness_min: float = INF
	var brightness_max: float = -INF
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
	print("图标像素检查：不透明像素=", opaque_pixels, "，透明像素=", transparent_pixels,
		"，亮度范围=", brightness_min, " 至 ", brightness_max)
	return opaque_pixels > 1024 and transparent_pixels > 1024 and brightness_max - brightness_min > 0.05
