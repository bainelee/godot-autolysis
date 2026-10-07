extends SceneTree
## 新材质适配专项：只读取真实资源、世界纸张和正式手持适配器的运行状态。

const EVIDENCE = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd")
const FIRST_TASK: AutolysisQuestPrintDefinition = preload("res://main-autolysis/systems/quest-print-system/quests/quest_test_0.tres")
const ITEM_DEFINITION: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/quest_paper.tres")
const WORLD_SCENE: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_paper/quest_paper.tscn")
const VISUAL_ADAPTER: Script = preload("res://main-autolysis/systems/item-system/autolysis_quest_paper_visual.gd")
const FRONT_MATERIAL: StandardMaterial3D = preload("res://main-autolysis/assets/materials/paper/mat_paper_test_0.tres")
const BODY_MATERIAL: StandardMaterial3D = preload("res://main-autolysis/assets/materials/paper/mat_paper_test_1.tres")

class PaperSource extends Node3D:
	var current_paper: Node3D
	var current_instance: AutolysisItemInstance

	func is_current_paper(paper: Node3D, serial: int, instance: AutolysisItemInstance = null) -> bool:
		return current_paper == paper and serial == 1 and instance == current_instance

var failures: int = 0
var checks: Array[Dictionary] = []
var measurements: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
	checks.append({"说明": description, "通过": condition})
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1


func settle_layout() -> void:
	for index: int in 4:
		await process_frame


func material_properties(material: StandardMaterial3D) -> Dictionary:
	return {
		"颜色": material.albedo_color,
		"第一纹理坐标三平面": material.uv1_triplanar,
		"第二纹理坐标三平面": material.uv2_triplanar,
		"基础纹理": material.albedo_texture,
		"粗糙度": material.roughness,
		"着色模式": material.shading_mode,
		"透明模式": material.transparency,
	}


func _has_visible_background(node: Node) -> bool:
	if node is ColorRect and node.visible and node.color.a > 0.0:
		return true
	for child: Node in node.get_children():
		if _has_visible_background(child):
			return true
	return false


func _visible_text(node: Node) -> PackedStringArray:
	var lines: PackedStringArray = []
	if node is Label and node.visible and node.self_modulate.a > 0.0:
		lines.append(node.text)
	for child: Node in node.get_children():
		lines.append_array(_visible_text(child))
	return lines


func verify_base(front: MeshInstance3D, body: MeshInstance3D, front_before: Dictionary, body_before: Dictionary, description: String) -> void:
	check(front.material_override == FRONT_MATERIAL, description + "正面继续绑定用户新正面材质资源")
	check(body.get_active_material(0) == BODY_MATERIAL, description + "纸体继续绑定用户新纸体材质资源")
	var base: StandardMaterial3D = front.material_override as StandardMaterial3D
	check(base != null and material_properties(base) == front_before, description + "基础正面颜色三平面等配置没有被文字绘制改写")
	check(material_properties(FRONT_MATERIAL) == front_before and material_properties(BODY_MATERIAL) == body_before, description + "两份共享用户材质资源属性保持原值")
	check(base != null and base.albedo_texture == front_before["基础纹理"] and not base.albedo_texture is ViewportTexture, description + "基础正面材质没有写入视口文字纹理")


func verify_ink(front: MeshInstance3D, viewport: SubViewport, description: String) -> StandardMaterial3D:
	var ink: StandardMaterial3D = front.material_overlay as StandardMaterial3D
	check(ink != null, description + "建立独立文字叠加材质")
	check(viewport.transparent_bg, description + "实际纸面视口使用透明背景")
	check(ink != null and ink.albedo_texture == viewport.get_texture(), description + "文字叠加材质绑定本模型实际视口纹理")
	check(ink != null and not ink.uv1_triplanar and not ink.uv2_triplanar, description + "文字使用网格常规纹理坐标且不使用三平面")
	check(ink != null and ink.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, description + "文字采用透明混合模式")
	check(ink != null and ink.albedo_color == Color.WHITE, description + "文字纹理保持原色和完整透明度")
	check(ink != null and ink.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and not ink.texture_repeat, description + "文字层采用无光照且关闭纹理重复")
	return ink


func verify_contents(view: AutolysisQuestPaperView, contents: AutolysisQuestPaperContents, description: String) -> void:
	check(view != null, description + "具备实际全文排版视图")
	if view == null:
		return
	var actual: AutolysisQuestPaperContents = view.get_contents()
	check(actual != null and actual.get_task_id() == contents.get_task_id() and actual.get_data_lines() == contents.get_data_lines() and actual.get_group_gap_before_lines() == contents.get_group_gap_before_lines(), description + "保留任务标识全部原文及分组数据")
	check(not _has_visible_background(view), description + "共享纸面视图没有可绘制的不透明底色")
	var report: Array[Dictionary] = view.get_layout_report()
	check(report.size() == contents.get_line_count(), description + "真实字体为每个原始数据行建立布局")
	var all_text: bool = report.size() == contents.get_line_count()
	var glyphs: String = ""
	for index: int in report.size():
		all_text = all_text and report[index]["text"] == contents.get_data_line(index) and report[index]["font_size"] == view.body_font_size and report[index]["visual_line_count"] >= 1
		# 制表符控制排版而不要求字体字形；原始内容仍逐字比较且记录全部字体报告。
		glyphs += String(report[index]["missing_characters"]).replace("\t", "")
	check(all_text and glyphs.is_empty(), description + "真实字体保留逐行原文且没有缺失字符")
	measurements.append({"样例": description, "实际字体排版": report})


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("纸张材质专项禁止启动图形后端。")
		quit(1)
		return
	var front_before: Dictionary = material_properties(FRONT_MATERIAL)
	var body_before: Dictionary = material_properties(BODY_MATERIAL)
	var orphan_count: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var first: AutolysisItemInstance = AutolysisItemInstance.create(ITEM_DEFINITION)
	var second: AutolysisItemInstance = AutolysisItemInstance.create(ITEM_DEFINITION)
	var original: AutolysisQuestPaperContents = FIRST_TASK.create_contents()
	var other: AutolysisQuestPaperContents = AutolysisQuestPaperContents.create_result("material_second", PackedStringArray(["第二件独立任务", "", "末行", ""]), PackedInt32Array([2]))
	check(first.set_quest_paper_contents(original, false) and second.set_quest_paper_contents(other, false), "真实逐件资源分别接收两份完整任务数据")
	var source: PaperSource = PaperSource.new()
	root.add_child(source)
	var world_paper: AutolysisQuestPaper = WORLD_SCENE.instantiate() as AutolysisQuestPaper
	source.current_paper = world_paper
	source.current_instance = first
	check(world_paper.configure(source, 1, first), "世界纸张通过正式配置绑定实际来源和逐件身份")
	source.add_child(world_paper)
	var held_first: Node3D = ITEM_DEFINITION.visual_scene.instantiate() as Node3D
	var held_second: Node3D = ITEM_DEFINITION.visual_scene.instantiate() as Node3D
	root.add_child(held_first)
	root.add_child(held_second)
	check(VISUAL_ADAPTER.apply_instance(held_first, first) and VISUAL_ADAPTER.apply_instance(held_second, second), "手持模型通过正式逐件适配器建立两件文字显示")
	await settle_layout()
	var world_front: MeshInstance3D = world_paper.front_mesh
	var world_body: MeshInstance3D = world_paper.get_node("mesh_quest_paper") as MeshInstance3D
	var world_viewport: SubViewport = world_paper.get_paper_viewport()
	var held_front: MeshInstance3D = VISUAL_ADAPTER.get_front(held_first)
	var held_body: MeshInstance3D = held_first.get_node("Paper") as MeshInstance3D
	var held_viewport: SubViewport = VISUAL_ADAPTER.get_viewport(held_first)
	var second_front: MeshInstance3D = VISUAL_ADAPTER.get_front(held_second)
	var second_viewport: SubViewport = VISUAL_ADAPTER.get_viewport(held_second)
	verify_base(world_front, world_body, front_before, body_before, "世界纸张：")
	verify_base(held_front, held_body, front_before, body_before, "手持纸张：")
	var world_ink: StandardMaterial3D = verify_ink(world_front, world_viewport, "世界纸张：")
	var held_ink: StandardMaterial3D = verify_ink(held_front, held_viewport, "第一件手持纸张：")
	var second_ink: StandardMaterial3D = verify_ink(second_front, second_viewport, "第二件手持纸张：")
	check(world_front.material_override == held_front.material_override and world_body.get_active_material(0) == held_body.get_active_material(0), "世界与手持正面及纸体使用相同用户新材质")
	check(world_ink != null and held_ink != null and second_ink != null and world_ink != held_ink and held_ink != second_ink and world_ink != second_ink, "世界及两件手持模型各自持有独立文字叠加材质")
	check(world_viewport != held_viewport and held_viewport != second_viewport and world_viewport.get_texture() != held_viewport.get_texture() and held_viewport.get_texture() != second_viewport.get_texture(), "世界及两件手持模型的视口和纹理身份独立")
	verify_contents(world_paper.get_paper_view(), original, "世界纸张初始：")
	verify_contents(VISUAL_ADAPTER.get_view(held_first), original, "第一件手持纸张：")
	verify_contents(VISUAL_ADAPTER.get_view(held_second), other, "第二件手持纸张：")
	check(world_paper.get_visible_data_line_indices().is_empty(), "世界纸张打印前全部原始数据行隐藏")
	var world_layout: Array[Dictionary] = world_paper.get_paper_view().get_layout_report()
	check(world_paper.reveal_data_line(1, 6) and world_paper.get_visible_data_line_indices() == PackedInt32Array([6]), "世界纸张真实来源逐行显示且只显示本次指定行")
	check(world_paper.complete_print(1) and _visible_text(world_paper.get_paper_view()) == FIRST_TASK.data_lines, "世界纸张正式完成后显示全部十三行原文")
	await settle_layout()
	var final_layout: Array[Dictionary] = world_paper.get_paper_view().get_layout_report()
	var layout_unchanged: bool = final_layout.size() == world_layout.size()
	for index: int in final_layout.size():
		layout_unchanged = layout_unchanged and final_layout[index]["position"] == world_layout[index]["position"] and final_layout[index]["size"] == world_layout[index]["size"]
	check(layout_unchanged and world_front.material_overlay == world_ink, "世界逐行打印只改变文字绘制且保持排版与文字材质身份")
	check(_visible_text(VISUAL_ADAPTER.get_view(held_first)) == FIRST_TASK.data_lines and _visible_text(VISUAL_ADAPTER.get_view(held_second)) == other.get_data_lines(), "两件手持文字显示各自全部原文并保留空行")
	await _test_held_updates(held_first, held_second, first, original, other, held_ink, held_viewport, front_before, body_before)
	check(world_front.material_overlay == world_ink and _visible_text(world_paper.get_paper_view()) == FIRST_TASK.data_lines, "手持内容更新与清空没有改写已打印的世界文字")
	source.free()
	held_first.free()
	held_second.free()
	await settle_layout()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == orphan_count, "测试释放世界纸张和手持排版后没有新增孤立节点")
	_write_report(front_before, body_before)
	print("纸张材质专项断言数：", checks.size(), "；失败数：", failures)
	quit(0 if failures == 0 else 1)


func _test_held_updates(visual: Node3D, other_visual: Node3D, instance: AutolysisItemInstance, original: AutolysisQuestPaperContents, other: AutolysisQuestPaperContents, ink: StandardMaterial3D, viewport: SubViewport, front_before: Dictionary, body_before: Dictionary) -> void:
	var front: MeshInstance3D = VISUAL_ADAPTER.get_front(visual)
	var body: MeshInstance3D = visual.get_node("Paper") as MeshInstance3D
	var texture: Texture2D = viewport.get_texture()
	var previous: AutolysisQuestPaperView = VISUAL_ADAPTER.get_view(visual)
	for index: int in 8:
		check(VISUAL_ADAPTER.apply_instance(visual, instance), "相同逐件内容第%d次重复应用成功" % index)
	check(VISUAL_ADAPTER.get_view(visual) == previous and viewport.get_child_count() == 1 and front.material_overlay == ink, "等值更新不重建排版或叠加材质且不积累子节点")
	var replacement: AutolysisQuestPaperContents = AutolysisQuestPaperContents.create_result("material_updated", PackedStringArray(["本件更新全文", "", "分组新行", " ", "\t", ""]), PackedInt32Array([2]))
	check(instance.set_quest_paper_contents(replacement, false) and VISUAL_ADAPTER.apply_instance(visual, instance), "实际逐件内容替换通过正式适配器成功应用")
	await settle_layout()
	verify_contents(VISUAL_ADAPTER.get_view(visual), replacement, "手持替换内容：")
	check(not is_instance_valid(previous) and viewport.get_child_count() == 1, "内容更新释放旧排版且仅保留当前视图")
	check(front.material_overlay == ink and ink != null and ink.albedo_texture == texture and VISUAL_ADAPTER.get_viewport(visual) == viewport, "不同内容更新保持本模型文字材质视口和纹理身份")
	check(_visible_text(VISUAL_ADAPTER.get_view(visual)) == replacement.get_data_lines() and _visible_text(VISUAL_ADAPTER.get_view(other_visual)) == other.get_data_lines(), "第一件更新全部原文且没有串改第二件文字")
	verify_base(front, body, front_before, body_before, "内容更新后：")
	var retiring_view: AutolysisQuestPaperView = VISUAL_ADAPTER.get_view(visual)
	check(instance.set_quest_paper_contents(null, false) and VISUAL_ADAPTER.apply_instance(visual, instance), "清空逐件内容通过正式适配器成功应用")
	check(VISUAL_ADAPTER.get_view(visual) == null and front.material_overlay == ink and ink != null and ink.albedo_texture == null and ink.albedo_color.a == 0.0, "内容清空移除文字纹理并关闭叠加层透明度且保留材质身份")
	await settle_layout()
	check(not is_instance_valid(retiring_view) and viewport.get_child_count() == 0, "清空后旧排版已释放且没有文字子节点")
	check(VISUAL_ADAPTER.apply_instance(visual, instance) and front.material_overlay == ink and VISUAL_ADAPTER.get_viewport(visual) == viewport, "重复清空保持原文字材质和视口身份")
	check(instance.set_quest_paper_contents(original, false) and VISUAL_ADAPTER.apply_instance(visual, instance), "恢复原任务内容通过正式适配器重新显示")
	await settle_layout()
	check(front.material_overlay == ink and ink != null and ink.albedo_texture == texture and ink.albedo_color.a == 1.0 and _visible_text(VISUAL_ADAPTER.get_view(visual)) == original.get_data_lines(), "清空后恢复继续使用原材质原视口纹理并显示完整原文")
	verify_base(front, body, front_before, body_before, "清空和恢复后：")


func _write_report(front_before: Dictionary, body_before: Dictionary) -> void:
	var directory: String = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/任务文件打印实施证据/20261007/新纸张材质适配")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var report: FileAccess = FileAccess.open(directory.path_join("材质回归结果.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"通过": failures == 0, "断言数": checks.size(), "失败数": failures, "断言": checks, "原正面材质": front_before, "原纸体材质": body_before, "实际排版测量": measurements, "验证范围": "无图形资源配置和正式业务调用；不包含图形像素效果"}, "\t"))
	report.close()
