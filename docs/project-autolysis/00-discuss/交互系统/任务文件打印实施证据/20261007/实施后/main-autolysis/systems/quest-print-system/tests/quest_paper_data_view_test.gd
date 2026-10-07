extends SceneTree
## 数据副本和真实文字布局专项；不创建图形窗口，不注入输入。

const EVIDENCE = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd")
const FIRST_TASK = preload("res://main-autolysis/systems/quest-print-system/quests/quest_test_0.tres")
const ITEM_DEFINITION = preload("res://main-autolysis/systems/item-system/items/quest_paper.tres")
const VIEW_SCENE = preload("res://main-autolysis/ui/quest-paper/autolysis_quest_paper_view.tscn")
const PAPER_SCENE = preload("res://main-autolysis/scenes/prefabs/prefab_paper/quest_paper.tscn")

class PaperSource extends Node3D:
	var current_paper: Node3D
	var current_serial: int = 1
	var current_instance: AutolysisItemInstance

	func is_current_paper(paper: Node3D, serial: int, instance: AutolysisItemInstance = null) -> bool:
		return current_paper == paper and current_serial == serial and (instance == null or instance == current_instance)

var failures: int = 0
var checks: Array[Dictionary] = []
var layout_measurements: Array[Dictionary] = []


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


func make_view(contents: AutolysisQuestPaperContents) -> AutolysisQuestPaperView:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(720, 960)
	root.add_child(viewport)
	var view: AutolysisQuestPaperView = VIEW_SCENE.instantiate() as AutolysisQuestPaperView
	viewport.add_child(view)
	check(view.configure_contents(contents), "完整快照建立纸面布局")
	return view


func run_checks() -> void:
	var definition: AutolysisQuestPrintDefinition = FIRST_TASK.duplicate(true) as AutolysisQuestPrintDefinition
	check(definition.is_valid_definition() and definition.task_id == "quest_test_0", "首份任务使用用户指定独立字符串标识")
	check(definition.data_lines.size() == 13, "首份任务严格包含十三个原始数据行")
	check(definition.data_lines[4] == "委托编号：07003141", "委托编号保留前导零且独立于任务标识")
	var contents: AutolysisQuestPaperContents = definition.create_contents()
	definition.data_lines[0] = "修改共享任务"
	definition.task_id = "changed_task"
	definition.group_gap_before_lines[0] = 0
	check(contents.get_task_id() == "quest_test_0" and contents.get_data_line(0) == "日期：1944年9月12日" and contents.get_group_gap_before_lines() == PackedInt32Array([6, 8]), "受理快照不随共享任务、全文和分组编辑改变")
	var copied: AutolysisQuestPaperContents = contents.copy_contents()
	var returned_lines: PackedStringArray = copied.get_data_lines()
	returned_lines[0] = "修改读取副本"
	var returned_groups: PackedInt32Array = copied.get_group_gap_before_lines()
	returned_groups[0] = 0
	check(copied != contents and contents.get_data_line(0) == "日期：1944年9月12日" and copied.get_data_line(0) == "日期：1944年9月12日" and copied.get_group_gap_before_lines() == PackedInt32Array([6, 8]), "复制和数组读取均隔离可变内容")
	check(AutolysisQuestPrintDefinition.split_data_lines("首\r\n\r\n末\r\n") == PackedStringArray(["首", "", "末", ""]), "统一换行时保留中间空行与末尾空行")
	check(AutolysisQuestPrintDefinition.split_data_lines(" \t\r末") == PackedStringArray([" \t", "末"]), "空格与制表符不被修剪且独立回车被规范化")
	check(AutolysisQuestPaperContents.create_result("", PackedStringArray([""])) == null, "拒绝空任务标识")
	check(AutolysisQuestPaperContents.create_result("test", PackedStringArray()) == null, "拒绝零元素数据")
	check(AutolysisQuestPaperContents.create_result("test", PackedStringArray(["首\n末"])) == null, "数组元素必须是单个原始换行数据行")
	var blanks: PackedStringArray = []
	for index: int in 21:
		blanks.append("")
	var blank_contents: AutolysisQuestPaperContents = AutolysisQuestPaperContents.create_result("blank_task", blanks)
	check(blank_contents != null and blank_contents.get_line_count() == 21, "二十一个全空数据行有效且保留完整容量")
	check(ITEM_DEFINITION.is_valid_definition() and not ITEM_DEFINITION.is_raw_material, "任务文件定义为非原料且手持展示无脚本无碰撞")
	var first_instance: AutolysisItemInstance = AutolysisItemInstance.create(ITEM_DEFINITION)
	var second_instance: AutolysisItemInstance = AutolysisItemInstance.create(ITEM_DEFINITION)
	check(first_instance.set_quest_paper_contents(contents, false) and second_instance.set_quest_paper_contents(contents, false), "两个逐件实例分别接收完整任务副本")
	var item_read: AutolysisQuestPaperContents = first_instance.quest_paper_contents
	var item_read_lines: PackedStringArray = item_read.data_lines
	item_read_lines[0] = "修改物品读取结果"
	check(first_instance != second_instance and first_instance.quest_paper_contents.get_data_lines() == contents.get_data_lines() and second_instance.quest_paper_contents.get_data_lines() == contents.get_data_lines(), "逐件身份不同且读取修改不污染任一任务原文")
	var raw_definition: AutolysisItemDefinition = load("res://main-autolysis/systems/item-system/items/caffeine.tres") as AutolysisItemDefinition
	var raw_instance: AutolysisItemInstance = AutolysisItemInstance.create(raw_definition)
	check(not raw_instance.set_quest_paper_contents(contents, false), "原料不能接收任务纸张内容")

	var first_view: AutolysisQuestPaperView = make_view(contents)
	await settle_layout()
	var initial_report: Array[Dictionary] = first_view.get_layout_report()
	layout_measurements.append({"样例": "首份十三行", "行测量": initial_report})
	check(first_view.size == Vector2(720, 960) and first_view.clip_area.size == Vector2(648, 888), "真实画布七百二十乘九百六十且四边三十六像素留白")
	check(first_view.clip_area.clip_contents and first_view.get_visible_data_line_indices().is_empty(), "单页裁剪启用且初始文字全部隐藏")
	var missing_characters: String = ""
	for row: Dictionary in initial_report:
		missing_characters += row.missing_characters
		check(row.font_size == 24 and row.size.x == 648 and row.size.y >= 40 and row.visual_line_count >= 1, "第%d自然行由真实字体排版且保持基础占位" % row.data_line_index)
	check(missing_characters.is_empty(), "当前实际系统字体支持首份全部字符")
	check(first_view.reveal_data_line(6) and first_view.reveal_data_line(6) and first_view.get_visible_data_line_indices() == PackedInt32Array([6]), "指定自然行一次完整显示且重复显示幂等")
	await settle_layout()
	var revealed_report: Array[Dictionary] = first_view.get_layout_report()
	var positions_match: bool = true
	for index: int in initial_report.size():
		positions_match = positions_match and initial_report[index].position == revealed_report[index].position and initial_report[index].size == revealed_report[index].size
	check(positions_match, "隐藏与显示只改变绘制而不改变布局位置和尺寸")
	check(not first_view.reveal_data_line(-1) and not first_view.reveal_data_line(13), "越界自然行显示被拒绝")
	first_view.reveal_all_data_lines()
	check(first_view.get_visible_data_line_indices().size() == 13, "完成补全所有原始数据行")

	var overflow_lines: PackedStringArray = []
	for index: int in 25:
		overflow_lines.append("长行正文用于核实真实中文自动折行，保留完整原文并且不增加机械行数。长行正文用于核实真实中文自动折行，保留完整原文并且不增加机械行数。")
	var overflow_contents: AutolysisQuestPaperContents = AutolysisQuestPaperContents.create_result("overflow_task", overflow_lines, PackedInt32Array([1]))
	var overflow_view: AutolysisQuestPaperView = make_view(overflow_contents)
	await settle_layout()
	var overflow_report: Array[Dictionary] = overflow_view.get_layout_report()
	layout_measurements.append({"样例": "二十五个长数据行", "行测量": overflow_report})
	check(overflow_report[0].visual_line_count > 1 and overflow_report[0].size.y > 40, "真实长行自动折行且增加对应视觉行高度")
	check(overflow_report[24].position.y >= overflow_view.clip_area.size.y, "超出单页的末行位于实际裁剪区域外")
	overflow_view.reveal_all_data_lines()
	check(overflow_view.get_contents().get_data_lines() == overflow_lines and overflow_view.get_visible_data_line_indices().size() == 25, "裁剪后仍保存和补全全部二十五个原始数据行")
	var blank_view: AutolysisQuestPaperView = make_view(blank_contents)
	await settle_layout()
	check(blank_view.get_layout_report().size() == 21 and blank_view.lines_container.size.y >= 840, "全空数据行保留二十一个排版位置")
	blank_view.reveal_all_data_lines()
	check(blank_view.get_visible_data_line_indices().size() == 21, "全空数据行可以正常完成显示")

	var source: PaperSource = PaperSource.new()
	root.add_child(source)
	var paper: AutolysisQuestPaper = PAPER_SCENE.instantiate() as AutolysisQuestPaper
	source.current_paper = paper
	source.current_instance = first_instance
	check(paper.configure(source, 1, first_instance), "世界纸张入树前绑定设备、序号和同一逐件实例")
	source.add_child(paper)
	await settle_layout()
	check(paper.get_item_instance() == first_instance and paper.get_paper_viewport().size == Vector2i(720, 960), "世界纸张保留逐件身份并绑定实际纸面子视口")
	check(not paper.reveal_data_line(2, 0) and paper.reveal_data_line(1, 0), "纸张拒绝旧序号且本次序号可显示原始行")
	check(paper.complete_print(1) and paper.get_visible_data_line_indices().size() == 13, "来源匹配时世界纸张可补全全文")
	var changed_contents: AutolysisQuestPaperContents = AutolysisQuestPaperContents.create_result("replacement_task", PackedStringArray(["另一个完整任务"]), PackedInt32Array())
	check(first_instance.set_quest_paper_contents(changed_contents, false), "同一逐件实例可以注入不同有效任务来源变体")
	check(not paper.matches_source(source, 1, first_instance) and not paper.reveal_data_line(1, 1) and not paper.complete_print(1), "同一逐件身份中的任务标识或全文替换不能冒用本次纸面来源")
	check(first_instance.set_quest_paper_contents(contents, false) and paper.matches_source(source, 1, first_instance), "恢复原始任务全文后纸张来源再次匹配")
	var changed_layout_contents: AutolysisQuestPaperContents = AutolysisQuestPaperContents.create_result(contents.get_task_id(), contents.get_data_lines(), PackedInt32Array([1]))
	check(first_instance.set_quest_paper_contents(changed_layout_contents, false) and not paper.matches_source(source, 1, first_instance), "同一逐件身份替换为不同完整排版快照不能冒用当前来源")
	check(first_instance.set_quest_paper_contents(contents, false) and paper.matches_source(source, 1, first_instance), "原始标识全文和分组快照复原后来源完整匹配")
	source.current_paper = null
	check(not paper.reveal_data_line(1, 1) and not paper.complete_print(1), "设备已撤销来源后旧纸张无法继续推进")
	source.current_paper = paper
	paper.finish_pickup()
	check(not paper.matches_source(source, 1, first_instance) and first_instance.quest_paper_contents.get_data_lines() == contents.get_data_lines(), "清理世界表现立即撤销纸张自身来源且完整逐件内容不丢失")
	await settle_layout()
	check(not is_instance_valid(paper), "世界纸张排队释放完成")
	source.free()
	first_view.get_parent().free()
	overflow_view.get_parent().free()
	blank_view.get_parent().free()

	var evidence_dir: String = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/任务文件打印实施证据/20261007/数据纸面专项")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	var report_file: FileAccess = FileAccess.open(evidence_dir.path_join("数据纸面结果.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify({"通过": failures == 0, "失败数": failures, "断言": checks, "实际字体排版": layout_measurements}, "\t"))
	report_file.close()
	quit(0 if failures == 0 else 1)
