class_name AutolysisQuestPrintDefinition
extends Resource
## 每个数组元素对应原始换行数据行；排版分组不插入机械数据行。

@export var task_id: String = ""
@export var data_lines: PackedStringArray = []
@export var group_gap_before_lines: PackedInt32Array = []


static func split_data_lines(text: String) -> PackedStringArray:
	return text.replace("\r\n", "\n").replace("\r", "\n").split("\n", true)


func get_configuration_error() -> String:
	return AutolysisQuestPaperContents.get_data_error(task_id, data_lines)


func is_valid_definition() -> bool:
	return get_configuration_error().is_empty()


func create_contents() -> AutolysisQuestPaperContents:
	return AutolysisQuestPaperContents.create_result(task_id, data_lines, group_gap_before_lines)
