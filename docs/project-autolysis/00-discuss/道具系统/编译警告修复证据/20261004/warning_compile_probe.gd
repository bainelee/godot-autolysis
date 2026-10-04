extends SceneTree

const TARGET_PATHS: Array[String] = [
	"res://main-autolysis/player/components/item_drop_shape_cast.gd",
	"res://main-autolysis/player/components/autolysis_inventory_controller.gd",
	"res://main-autolysis/scenes/prefabs/prefab_machines/scripts/autolysis_packing_motion.gd",
]
const WARNING_KEYS: Array[String] = [
	"debug/gdscript/warnings/unused_variable",
	"debug/gdscript/warnings/incompatible_ternary",
	"debug/gdscript/warnings/shadowed_variable_base_class",
]

func _initialize() -> void:
	var scripts: Array[GDScript] = []
	for target_path in TARGET_PATHS:
		var target_script: GDScript = load(target_path) as GDScript
		if target_script == null:
			push_error("无法加载待检查脚本：" + target_path)
			quit(2)
			return
		scripts.append(target_script)
	ProjectSettings.set_setting("debug/gdscript/warnings/enable", true)
	for warning_key in WARNING_KEYS:
		if not ProjectSettings.has_setting(warning_key):
			push_error("引擎不存在指定警告设置：" + warning_key)
			quit(2)
			return
		ProjectSettings.set_setting(warning_key, 2)
		print("警告提升为编译错误：", warning_key)
	# 警告等级由解析器缓存；立即通知语言服务刷新本进程中的设置。
	ProjectSettings.settings_changed.emit()
	var failures: int = 0
	for index in TARGET_PATHS.size():
		var reload_error: Error = scripts[index].reload()
		if reload_error != OK:
			failures += 1
			print("失败：", TARGET_PATHS[index], "；重新编译结果：", reload_error)
		else:
			print("通过：", TARGET_PATHS[index], "；重新编译结果：", reload_error)
	print("编译检查完成；脚本数：", scripts.size(), "；失败数：", failures)
	quit(1 if failures > 0 else 0)
