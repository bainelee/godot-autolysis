extends SceneTree
## 真实玩家库存接收和手持呈现的全文显示专项。

const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/player/autolysis_player.tscn")
const PAPER: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/quest_paper.tres")
const FIRST_TASK: AutolysisQuestPrintDefinition = preload("res://main-autolysis/systems/quest-print-system/quests/quest_test_0.tres")

var failures: int = 0
var records: Array[Dictionary] = []
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/交互系统/任务文件打印实施证据/20261007/持有文字与空间音效修订/手持全文")


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
	records.append({"说明": description, "通过": condition})
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1


func _visible_text(node: Node) -> PackedStringArray:
	var lines: PackedStringArray = []
	if node is Label and node.visible and node.self_modulate.a > 0.0:
		lines.append(node.text)
	for child: Node in node.get_children():
		lines.append_array(_visible_text(child))
	return lines


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("手持文字专项禁止启动图形后端。")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var actor: AutolysisPlayer = PLAYER_SCENE.instantiate() as AutolysisPlayer
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process_input(false)
	actor.set_process_unhandled_input(false)
	actor._clear_landing_stun()
	await process_frame
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(PAPER)
	check(instance.set_quest_paper_contents(FIRST_TASK.create_contents()), "真实任务逐件资源保存用户指定任务全文")
	check(actor.inventory_controller.try_receive_instance(instance), "正式库存接收逐件任务文件并提交手持展示")
	check(actor.inventory_controller.get_focused_instance() == instance and instance.quest_paper_contents.get_data_lines() == FIRST_TASK.data_lines, "正式接收保留同一逐件身份和全文")
	await process_frame
	var display: Node3D = actor.held_item_presenter.get_display()
	var actual_lines: PackedStringArray = _visible_text(display) if display != null else PackedStringArray()
	check(actual_lines == FIRST_TASK.data_lines, "正式手持展示可见本件全部自然行而不是白纸")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("手持全文断言.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"失败数": failures, "断言数": records.size(), "记录": records, "期望全文": FIRST_TASK.data_lines, "实际显示全文": actual_lines}, "\t"))
	report.close()
	actor.queue_free()
	await process_frame
	await process_frame
	print("手持全文专项断言数：", records.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)
