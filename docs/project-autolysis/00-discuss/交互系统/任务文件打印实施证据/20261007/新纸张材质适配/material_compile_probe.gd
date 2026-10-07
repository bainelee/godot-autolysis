extends SceneTree
## 当前进程严格编译实际生产脚本与回归脚本，不保存项目设置。

const TARGET_PATHS: Array[String] = [
	"res://main-autolysis/systems/quest-print-system/tests/quest_paper_material_test.gd",
	"res://main-autolysis/scenes/prefabs/prefab_paper/autolysis_quest_paper.gd",
	"res://main-autolysis/systems/item-system/autolysis_quest_paper_visual.gd",
	"res://main-autolysis/player/tests/quest_held_text_test.gd",
	"res://main-autolysis/player/tests/quest_paper_inventory_test.gd",
	"res://main-autolysis/player/tests/quest_print_main_test.gd",
]
const WARNING_KEYS: Array[String] = [
	"debug/gdscript/warnings/shadowed_variable_base_class",
	"debug/gdscript/warnings/incompatible_ternary",
	"debug/gdscript/warnings/unused_variable",
]


func _initialize() -> void:
	var scripts: Array[GDScript] = []
	for target_path: String in TARGET_PATHS:
		var target_script: GDScript = load(target_path) as GDScript
		if target_script == null:
			push_error("无法加载待检查脚本：" + target_path)
			quit(2)
			return
		scripts.append(target_script)
	ProjectSettings.set_setting("debug/gdscript/warnings/enable", true)
	for warning_key: String in WARNING_KEYS:
		if not ProjectSettings.has_setting(warning_key):
			push_error("引擎不存在指定警告设置：" + warning_key)
			quit(2)
			return
		ProjectSettings.set_setting(warning_key, 2)
	ProjectSettings.settings_changed.emit()
	var failures: int = 0
	for index: int in TARGET_PATHS.size():
		var reload_error: Error = scripts[index].reload()
		if reload_error != OK:
			failures += 1
			print("失败：", TARGET_PATHS[index], "；重新编译结果：", reload_error)
		else:
			print("通过：", TARGET_PATHS[index], "；重新编译结果：", reload_error)
	print("编译检查完成；脚本数：", scripts.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)
