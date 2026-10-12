extends RefCounted
## 显式参数覆盖输出位置；默认按本次进程统一保存到项目外历史目录。

const HISTORY_ROOT: String = "D:/autolysis_history/测试运行/脚本直跑"
const DISCUSSION_PREFIX: String = "res://docs/project-autolysis/00-discuss/"

static var _default_run_directory: String = ""


static func directory(default_directory: String) -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = arguments.find("--evidence-dir")
	if index >= 0 and index + 1 < arguments.size():
		return arguments[index + 1].trim_suffix("/")
	for argument: String in arguments:
		if argument.begins_with("--evidence-dir="):
			return argument.trim_prefix("--evidence-dir=").trim_suffix("/")
	if _default_run_directory.is_empty():
		var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
		var run_name: String = "%s-%d-%d" % [timestamp, OS.get_process_id(), Time.get_ticks_usec()]
		_default_run_directory = HISTORY_ROOT.path_join(run_name)
	var relative_directory: String = default_directory.trim_prefix(DISCUSSION_PREFIX).trim_prefix("res://")
	var output_directory: String = _default_run_directory.path_join(relative_directory)
	var error: Error = DirAccess.make_dir_recursive_absolute(output_directory)
	if error != OK:
		push_error("无法创建默认实施证据目录：%s；错误码：%d" % [output_directory, error])
	return output_directory
