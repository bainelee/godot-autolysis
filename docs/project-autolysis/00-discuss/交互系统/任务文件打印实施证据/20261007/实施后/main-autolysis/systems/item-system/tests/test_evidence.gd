extends RefCounted
## 各测试共享用户参数解析；未指定时保留历史入口的默认目录。


static func directory(default_directory: String) -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = arguments.find("--evidence-dir")
	if index >= 0 and index + 1 < arguments.size():
		return arguments[index + 1].trim_suffix("/")
	return default_directory
