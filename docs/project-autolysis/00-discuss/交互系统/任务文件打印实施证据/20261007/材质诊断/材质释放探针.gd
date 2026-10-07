extends SceneTree
## 最小材质故障探针；只在无图形运行中改变一项材质配置。


func _initialize() -> void:
	call_deferred("run_probe")


func run_probe() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = arguments[0] if not arguments.is_empty() else "scene"
	print("材质探针输入：", mode)
	if mode == "scene":
		var scene: PackedScene = load("res://main-autolysis/scenes/prefabs/prefab_paper/quest_paper.tscn") as PackedScene
		var paper: Node = scene.instantiate()
		print("纸张仅实例化完成，未入树或绑定。")
		paper.free()
	else:
		var mesh: PrimitiveMesh = BoxMesh.new() if mode.begins_with("box") else QuadMesh.new()
		if mode.ends_with("base") or mode.ends_with("both"):
			mesh.material = StandardMaterial3D.new()
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.mesh = mesh
		if mode.ends_with("override") or mode.ends_with("both"):
			visual.set_surface_override_material(0, StandardMaterial3D.new())
		elif mode.ends_with("global"):
			visual.material_override = StandardMaterial3D.new()
		root.add_child(visual)
		await process_frame
		visual.free()
	print("材质探针完成。")
	quit()
