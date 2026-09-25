extends SceneTree
## 实例仅用于读取实际模型和变换，不加入场景树，不触发玩家初始化。

const MAIN_SCENE_PATH: String = "res://main-autolysis/scenes/01-autolysis-test.tscn"
const UPPER_SHELF_PATH: NodePath = ^"interaction_prefabs/item_groups/place_shelf_workroom_rm_0"
const LOWER_SHELF_PATH: NodePath = ^"interaction_prefabs/item_groups/place_shelf_workroom_rm_1"
const REPORT_PATH: String = "res://docs/project-autolysis/00-discuss/道具系统/道具系统p1实施证据/checks/shelf-clearance.json"
const VISUAL_PATHS: Array[String] = [
	"res://main-autolysis/scenes/prefabs/prefab_raw_materials/visuals/rm_caffeine_visual.tscn",
	"res://main-autolysis/scenes/prefabs/prefab_raw_materials/visuals/rm_sodium_benzoate_visual.tscn",
]
const MATERIAL_NAMES: Array[String] = ["咖啡因", "苯甲酸钠"]
const BOARD_PATHS: Array[NodePath] = [^"mesh/MeshInstance3D10", ^"mesh/MeshInstance3D8"]
const GEOMETRY_EPSILON: float = 0.000001

var _checks: int = 0
var _failures: Array[String] = []
var _report: Dictionary = {
	"说明": "实际主场景实例未加入场景树；通过父子局部变换计算世界轴对齐包围盒。",
	"判定": "各轴交叠深度均大于百万分之一单位时视为相交；接触边界及浮点舍入不计为穿插。",
	"模型测量": [],
}


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if not _check(packed != null, "实际主场景资源可加载"):
		_finish()
		return
	var main: Node = packed.instantiate()
	if not _check(main != null, "实际主场景可实例化"):
		_finish()
		return
	_check(not main.is_inside_tree(), "几何验证不触发场景初始化")
	var upper: Node3D = main.get_node_or_null(UPPER_SHELF_PATH) as Node3D
	var lower: Node3D = main.get_node_or_null(LOWER_SHELF_PATH) as Node3D
	if not _check(upper != null and lower != null, "实际主场景包含指定上下原药架"):
		main.free()
		_finish()
		return
	_report["主场景"] = MAIN_SCENE_PATH
	_report["上架路径"] = str(UPPER_SHELF_PATH)
	_report["下架路径"] = str(LOWER_SHELF_PATH)
	_report["上架局部变换"] = _transform_record(upper.transform)
	_report["下架局部变换"] = _transform_record(lower.transform)
	_report["上架世界变换"] = _transform_record(_world_transform(upper))
	_report["下架世界变换"] = _transform_record(_world_transform(lower))
	_report["架子原点世界高度差"] = _world_transform(upper).origin.y - _world_transform(lower).origin.y
	var boards: Array[MeshInstance3D] = []
	var board_records: Array[Dictionary] = []
	for board_path: NodePath in BOARD_PATHS:
		var board: MeshInstance3D = upper.get_node_or_null(board_path) as MeshInstance3D
		if not _check(board != null and board.mesh != null, "上架层板具有实际网格：%s" % board_path):
			continue
		boards.append(board)
		board_records.append({
			"节点": str(upper.get_path_to(board)),
			"世界变换": _transform_record(_world_transform(board)),
			"世界包围盒": _aabb_record(_world_transform(board) * board.get_aabb()),
		})
	_report["上架层板"] = board_records
	var slots: Array[Node3D] = _get_upper_row_slots(lower)
	_check(slots.size() == 18, "下架实际最高一层包含18个原药槽位")
	_report["验证槽位数"] = slots.size()
	for material_index: int in VISUAL_PATHS.size():
		var visual_packed: PackedScene = load(VISUAL_PATHS[material_index]) as PackedScene
		if not _check(visual_packed != null, "%s纯显示资源可加载" % MATERIAL_NAMES[material_index]):
			continue
		var instance: Node = visual_packed.instantiate()
		var visual: Node3D = instance as Node3D
		if not _check(visual != null, "%s纯显示资源具有三维根节点" % MATERIAL_NAMES[material_index]):
			if instance != null:
				instance.free()
			continue
		var meshes: Array[MeshInstance3D] = []
		_collect_visible_meshes(visual, true, meshes)
		_check(meshes.size() == 4, "%s实际显示包含4个网格" % MATERIAL_NAMES[material_index])
		for slot: Node3D in slots:
			_measure_material(MATERIAL_NAMES[material_index], lower, slot, visual, meshes, upper, boards)
		visual.free()
	main.free()
	_finish()


func _measure_material(
	material_name: String,
	lower: Node3D,
	slot: Node3D,
	visual: Node3D,
	meshes: Array[MeshInstance3D],
	upper: Node3D,
	boards: Array[MeshInstance3D]
) -> void:
	var slot_world: Transform3D = _world_transform(slot)
	var mesh_records: Array[Dictionary] = []
	var material_bounds: AABB
	var has_bounds: bool = false
	for mesh: MeshInstance3D in meshes:
		# 架上实例采用单位局部变换，纯显示场景保留自身原始节点变换。
		var mesh_world: Transform3D = slot_world * _world_transform(mesh)
		var bounds: AABB = mesh_world * mesh.get_aabb()
		material_bounds = material_bounds.merge(bounds) if has_bounds else bounds
		has_bounds = true
		var board_comparisons: Array[Dictionary] = []
		for board: MeshInstance3D in boards:
			var board_bounds: AABB = _world_transform(board) * board.get_aabb()
			var overlap: Vector3 = _overlap_depth(bounds, board_bounds)
			var intersects: bool = overlap.x > GEOMETRY_EPSILON and overlap.y > GEOMETRY_EPSILON and overlap.z > GEOMETRY_EPSILON
			var condition: String = "%s，槽位%s，网格%s不与上架层板%s相交" % [
				material_name, slot.name, visual.get_path_to(mesh), upper.get_path_to(board),
			]
			_check(not intersects, condition)
			board_comparisons.append({
				"层板节点": str(upper.get_path_to(board)),
				"各轴交叠深度": _vector_record(overlap),
				"发生穿插": intersects,
				"层板下表面减网格最高点": board_bounds.position.y - bounds.end.y,
			})
		mesh_records.append({
			"节点": str(visual.get_path_to(mesh)),
			"网格局部包围盒": _aabb_record(mesh.get_aabb()),
			"世界变换": _transform_record(mesh_world),
			"世界包围盒": _aabb_record(bounds),
			"层板比较": board_comparisons,
		})
	var vertical_gaps: Array[Dictionary] = []
	for board: MeshInstance3D in boards:
		var board_bounds: AABB = _world_transform(board) * board.get_aabb()
		vertical_gaps.append({
			"层板节点": str(upper.get_path_to(board)),
			"层板下表面减原药最高点": board_bounds.position.y - material_bounds.end.y,
		})
	_report["模型测量"].append({
		"原药": material_name,
		"下架槽位路径": str(lower.get_path_to(slot)),
		"槽位世界变换": _transform_record(slot_world),
		"原药整体世界包围盒": _aabb_record(material_bounds),
		"垂直间距": vertical_gaps,
		"逐网格测量": mesh_records,
	})


func _get_upper_row_slots(shelf: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var container: Node3D = shelf.get_node_or_null("rm_place_shelf_slots") as Node3D
	if not _check(container != null, "下架存在实际槽位容器"):
		return result
	var highest: float = -INF
	for child: Node in container.get_children():
		if child is Node3D:
			highest = maxf(highest, (child as Node3D).position.y)
	for child: Node in container.get_children():
		if child is Node3D and absf((child as Node3D).position.y - highest) <= GEOMETRY_EPSILON:
			result.append(child as Node3D)
	result.sort_custom(func(first: Node3D, second: Node3D) -> bool:
		return str(first.name).get_slice("_", 4).to_int() < str(second.name).get_slice("_", 4).to_int()
	)
	return result


func _collect_visible_meshes(node: Node, ancestors_visible: bool, result: Array[MeshInstance3D]) -> void:
	var node_visible: bool = ancestors_visible
	if node is Node3D:
		node_visible = node_visible and (node as Node3D).visible
	if not node_visible:
		return
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_visible_meshes(child, node_visible, result)


func _world_transform(node: Node3D) -> Transform3D:
	var result: Transform3D = node.transform
	var ancestor: Node = node.get_parent()
	while ancestor != null:
		if ancestor is Node3D:
			result = (ancestor as Node3D).transform * result
		ancestor = ancestor.get_parent()
	return result


func _overlap_depth(first: AABB, second: AABB) -> Vector3:
	return Vector3(
		minf(first.end.x, second.end.x) - maxf(first.position.x, second.position.x),
		minf(first.end.y, second.end.y) - maxf(first.position.y, second.position.y),
		minf(first.end.z, second.end.z) - maxf(first.position.z, second.position.z)
	)


func _aabb_record(bounds: AABB) -> Dictionary:
	return {"最小坐标": _vector_record(bounds.position), "最大坐标": _vector_record(bounds.end), "尺寸": _vector_record(bounds.size)}


func _transform_record(value: Transform3D) -> Dictionary:
	return {
		"位置": _vector_record(value.origin),
		"基向量": [_vector_record(value.basis.x), _vector_record(value.basis.y), _vector_record(value.basis.z)],
	}


func _vector_record(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(description)
		printerr("失败：", description)
	return condition


func _finish() -> void:
	_report["检查数"] = _checks
	_report["失败数"] = _failures.size()
	_report["失败列表"] = _failures
	_report["通过"] = _failures.is_empty()
	_report["引擎版本"] = Engine.get_version_info()["string"]
	_report["时间"] = Time.get_datetime_string_from_system()
	var absolute_path: String = ProjectSettings.globalize_path(REPORT_PATH)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		printerr("无法创建原药架净空证据目录：", error_string(directory_error))
		quit(1)
		return
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		printerr("无法保存原药架净空证据：", error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string(JSON.stringify(_report, "\t") + "\n")
	file.close()
	print("原药架净空检查：", _checks, "项；失败：", _failures.size(), "项；证据：", absolute_path)
	quit(0 if _failures.is_empty() else 1)
