extends SceneTree

const DEFINITION: AutolysisDialogueDefinition = preload("res://chat_0.tres")

func _initialize() -> void:
    var arguments: PackedStringArray = OS.get_cmdline_user_args()
    var snapshot: Dictionary = DEFINITION.make_snapshot()
    var text: String = snapshot.get("lines", PackedStringArray([""]))[0]
    var passed: bool = snapshot.get("ok", false) and arguments.size() >= 2 and text == arguments[0]
    var record: FileAccess = FileAccess.open(arguments[1], FileAccess.WRITE)
    record.store_string(JSON.stringify({"通过": passed, "实际字幕": text, "预期字幕": arguments[0], "引擎": Engine.get_version_info()}, "\t"))
    print("通过：独立进程读取实际中文导入资源" if passed else "失败：实际中文与预期不符")
    quit(0 if passed else 1)