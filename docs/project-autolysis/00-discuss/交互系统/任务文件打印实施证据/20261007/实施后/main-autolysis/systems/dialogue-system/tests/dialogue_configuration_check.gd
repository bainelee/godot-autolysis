extends SceneTree
## 静态配置与引擎导入资源的真实关联检查；不推进人工完成事件。

const DEFINITION: AutolysisDialogueDefinition = preload("res://main-autolysis/systems/dialogue-system/chat_0.tres")
var _failures: int = 0
var _records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source: ConfigFile = ConfigFile.new()
	_check(source.load("res://main-autolysis/systems/dialogue-system/dialogue_source.cfg") == OK, "原文配置实际可读取")
	var csv: FileAccess = FileAccess.open("res://main-autolysis/systems/dialogue-system/dialogue_zh.csv", FileAccess.READ)
	_check(csv != null, "中文表格实际可读取")
	var translations: Dictionary = {}
	if csv != null:
		_check(csv.get_csv_line() == PackedStringArray(["keys", "zh"]), "中文表头列配置正确")
		while not csv.eof_reached():
			var row: PackedStringArray = csv.get_csv_line()
			if row.size() == 1 and row[0].is_empty():
				continue
			_check(row.size() == 2, "中文每行恰有两列")
			if row.size() != 2:
				continue
			_check(not translations.has(row[0]), "中文没有重复句编号")
			translations[row[0]] = row[1]
	var snapshot: Dictionary = DEFINITION.make_snapshot()
	_check(snapshot.get("ok", false), "首段全部译文和语音准备成功")
	_check(DEFINITION.line_ids.size() == 9 and translations.size() == 9, "首次首段恰有九句")
	for index: int in DEFINITION.line_ids.size():
		var line_id: String = DEFINITION.line_ids[index]
		_check(line_id == "chat_0_%d" % index, "有序句编号保持零至八")
		var original: String = source.get_value("chat_0", line_id, "")
		_check(original == translations.get(line_id, ""), "原文和独立中文表格逐字一致")
		_check(original == String(DEFINITION.chinese_translation.get_message(StringName(line_id))), "运行明确中文资源与表格一致")
		_check(DEFINITION.voice_streams[index].resource_path.ends_with("/%s.wav" % line_id), "语音与句编号显式对应")
	_check(String(source.get_value("chat_0", "chat_0_3", "")) == "与你之前的临床医疗任务不同", "第四句没有新增末尾标点")
	var changed: AutolysisDialogueDefinition = DEFINITION.duplicate() as AutolysisDialogueDefinition
	changed.post_voice_hold_seconds = 0.0
	_check(changed.make_snapshot().get("ok", false), "句后零等待可配置")
	changed.post_voice_hold_seconds = -1.0
	_check(not changed.make_snapshot().get("ok", false), "负等待拒绝准备")
	changed = DEFINITION.duplicate() as AutolysisDialogueDefinition
	changed.line_ids = PackedStringArray(["chat_0_0", "chat_0_0"])
	changed.voice_streams = [DEFINITION.voice_streams[0], DEFINITION.voice_streams[1]]
	_check(not changed.make_snapshot().get("ok", false), "重复句编号拒绝准备")
	changed.line_ids = PackedStringArray(["missing"])
	changed.voice_streams = [DEFINITION.voice_streams[0]]
	_check(not changed.make_snapshot().get("ok", false), "中文缺失不回退原文")
	var looping: AudioStreamWAV = DEFINITION.voice_streams[0].duplicate() as AudioStreamWAV
	looping.loop_mode = AudioStreamWAV.LOOP_FORWARD
	changed.line_ids = PackedStringArray(["chat_0_0"])
	changed.voice_streams = [looping]
	_check(not changed.make_snapshot().get("ok", false), "循环语音拒绝准备")
	_check((DEFINITION.voice_streams[0] as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "共享原语音没有被循环副本改写")
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var argument_index: int = arguments.find("--evidence-dir")
	if argument_index >= 0 and argument_index + 1 < arguments.size():
		var evidence_path: String = arguments[argument_index + 1]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_path))
		var result: FileAccess = FileAccess.open(evidence_path.path_join("配置核验.json"), FileAccess.WRITE)
		result.store_string(JSON.stringify({"记录": _records, "失败数": _failures, "引擎": Engine.get_version_info()}, "\t"))
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	_records.append({"检查": description, "通过": condition})
	if condition:
		print("通过：", description)
	else:
		_failures += 1
		push_error("失败：" + description)
