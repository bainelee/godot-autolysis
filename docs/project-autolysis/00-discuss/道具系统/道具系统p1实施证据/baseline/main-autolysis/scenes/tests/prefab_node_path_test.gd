extends SceneTree

# 加载真实预制场景及其嵌套实例，复查编辑器更新路径时使用的节点查找条件。
const PREFAB_DIRECTORY := "res://main-autolysis/scenes/prefabs"
const MAIN_SCENE := "res://main-autolysis/scenes/01-autolysis-test.tscn"

var failures: Array[Dictionary] = []
var scene_count := 0
var mesh_count := 0


func _initialize() -> void:
	var scene_paths: Array[String] = []
	collect_scenes(PREFAB_DIRECTORY, scene_paths)
	scene_paths.append(MAIN_SCENE)
	for scene_path in scene_paths:
		inspect_scene(scene_path)
	print("检查场景数：", scene_count)
	print("检查网格实例数：", mesh_count)
	print("失效骨架路径数：", failures.size())
	for failure in failures:
		print(JSON.stringify(failure))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var report := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			if report == null:
				push_error("无法写入验证报告")
				quit(2)
				return
			report.store_string(JSON.stringify({
				"场景数": scene_count,
				"网格实例数": mesh_count,
				"失效引用": failures,
			}, "\t"))
	quit(0 if failures.is_empty() else 1)


func collect_scenes(directory_path: String, scene_paths: Array[String]) -> void:
	for file_name in DirAccess.get_files_at(directory_path):
		if file_name.ends_with(".tscn"):
			scene_paths.append(directory_path.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(directory_path):
		collect_scenes(directory_path.path_join(directory_name), scene_paths)


func inspect_scene(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append({"场景": scene_path, "原因": "场景加载失败"})
		return
	var scene := packed.instantiate()
	if scene == null:
		failures.append({"场景": scene_path, "原因": "场景实例化失败"})
		return
	scene_count += 1
	inspect_node(scene, scene, scene_path)
	scene.free()


func inspect_node(node: Node, scene: Node, scene_path: String) -> void:
	if node is MeshInstance3D:
		mesh_count += 1
		var skeleton_path: NodePath = node.skeleton
		if not skeleton_path.is_empty() and node.get_node_or_null(skeleton_path) == null:
			failures.append({
				"场景": scene_path,
				"节点": str(scene.get_path_to(node)),
				"骨架路径": str(skeleton_path),
				"存在蒙皮": node.skin != null,
				"网格类型": node.mesh.get_class() if node.mesh != null else "",
			})
	for child in node.get_children():
		inspect_node(child, scene, scene_path)
