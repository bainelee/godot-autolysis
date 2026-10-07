extends "res://main-autolysis/player/tests/quest_print_main_test.gd"
## 对照探针：仅在当前进程恢复提交原始源码，磁盘生产文件不修改。


func _initialize() -> void:
	var source_directory: String = "res://docs/project-autolysis/00-discuss/交互系统/脚本警告修复证据/20261007/修复前来源/"
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var source_index: int = arguments.find("--source-directory")
	if source_index >= 0 and source_index + 1 < arguments.size():
		source_directory = arguments[source_index + 1]
	var source_paths: Array[String] = [
		"res://main-autolysis/ui/autolysis_handset_pose_debug.gd",
		"res://main-autolysis/scenes/prefabs/prefab_machines/scripts/autolysis_quest_machine.gd",
	]
	for source_path: String in source_paths:
		var original_source: String = FileAccess.get_file_as_string(source_directory.path_join(source_path.get_file()))
		var cached_script: GDScript = load(source_path) as GDScript
		if original_source.is_empty() or not is_instance_valid(cached_script):
			push_error("修复前源码恢复依赖失效：" + source_path)
			quit(1)
			return
		cached_script.source_code = original_source
		var reload_error: Error = cached_script.reload(true)
		if reload_error != OK:
			push_error("修复前源码重新编译失败：" + source_path + "；错误码：" + str(reload_error))
			quit(1)
			return
		print("当前进程已恢复提交源码：" + source_path)
	super._initialize()
