class_name AutolysisQuestPaperContents
extends Resource
## 逐件全文快照；数组读出和复制均与共享任务定义分离。

var task_id: String:
	get:
		return _task_id
var data_lines: PackedStringArray:
	get:
		return _data_lines.duplicate()
var group_gap_before_lines: PackedInt32Array:
	get:
		return _group_gap_before_lines.duplicate()

var _task_id: String = ""
var _data_lines: PackedStringArray = []
var _group_gap_before_lines: PackedInt32Array = []


static func get_data_error(id: String, lines: PackedStringArray) -> String:
	if id.is_empty():
		return "任务字符串标识为空。"
	if lines.is_empty():
		return "任务没有任何原始数据行。"
	for index: int in lines.size():
		if lines[index].contains("\n") or lines[index].contains("\r"):
			return "第%d个数组元素仍包含换行符，必须先按原始换行拆行。" % index
	return ""


static func create_result(id: String, lines: PackedStringArray, gap_indices: PackedInt32Array = []) -> AutolysisQuestPaperContents:
	if not get_data_error(id, lines).is_empty():
		return null
	var contents: AutolysisQuestPaperContents = AutolysisQuestPaperContents.new()
	contents._task_id = id
	contents._data_lines = lines.duplicate()
	# 越界或重复的可选排版标记只被忽略，不改变机械行或任务受理。
	for index: int in gap_indices:
		if index >= 0 and index < lines.size() and not contents._group_gap_before_lines.has(index):
			contents._group_gap_before_lines.append(index)
	return contents


func get_configuration_error() -> String:
	return get_data_error(_task_id, _data_lines)


func is_valid_contents() -> bool:
	return get_configuration_error().is_empty()


func copy_contents() -> AutolysisQuestPaperContents:
	return create_result(_task_id, _data_lines, _group_gap_before_lines) if is_valid_contents() else null


func get_task_id() -> String:
	return _task_id


func get_data_lines() -> PackedStringArray:
	return _data_lines.duplicate()


func get_line_count() -> int:
	return _data_lines.size()


func get_data_line(index: int) -> String:
	return _data_lines[index] if index >= 0 and index < _data_lines.size() else ""


func get_group_gap_before_lines() -> PackedInt32Array:
	return _group_gap_before_lines.duplicate()
