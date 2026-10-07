class_name AutolysisQuestPaperView
extends Control
## 完整全文预先占位；显示进度只改变行文字绘制，不改变布局。

@export var paper_font: Font
@export var body_font_size: int = 24
@export var data_line_minimum_height: float = 40.0
@export var group_gap_height: float = 16.0
@export var text_color: Color = Color(0.055, 0.045, 0.035, 1.0)
@export var lines_container: VBoxContainer
@export var clip_area: Control

var _contents: AutolysisQuestPaperContents
var _line_labels: Array[Label] = []
var _revealed: PackedByteArray = []


func _ready() -> void:
	if _contents != null and _line_labels.is_empty():
		_build_layout()


func get_configuration_error() -> String:
	if not is_instance_valid(lines_container) or not is_instance_valid(clip_area):
		return "纸面缺少全文排版容器或裁剪区域。"
	if not is_instance_valid(paper_font) or body_font_size <= 0:
		return "纸面缺少有效字体或字号。"
	if not is_finite(data_line_minimum_height) or data_line_minimum_height < 0.0 or not is_finite(group_gap_height) or group_gap_height < 0.0:
		return "纸面排版高度必须为有限非负值。"
	return ""


func configure_contents(contents: AutolysisQuestPaperContents) -> bool:
	if not get_configuration_error().is_empty() or not is_instance_valid(contents) or not contents.is_valid_contents():
		return false
	_contents = contents.copy_contents()
	_build_layout()
	return true


func _build_layout() -> void:
	for child: Node in lines_container.get_children():
		lines_container.remove_child(child)
		child.queue_free()
	_line_labels.clear()
	_revealed.resize(_contents.get_line_count())
	_revealed.fill(0)
	var group_indices: PackedInt32Array = _contents.get_group_gap_before_lines()
	for index: int in _contents.get_line_count():
		if group_indices.has(index):
			var gap: Control = Control.new()
			gap.custom_minimum_size.y = group_gap_height
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lines_container.add_child(gap)
		var label: Label = Label.new()
		label.name = "DataLine%d" % index
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.language = "zh_CN"
		label.text = _contents.get_data_line(index)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.autowrap_trim_flags = 0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size.y = data_line_minimum_height
		label.add_theme_font_override(&"font", paper_font)
		label.add_theme_font_size_override(&"font_size", body_font_size)
		label.add_theme_color_override(&"font_color", text_color)
		label.self_modulate.a = 0.0
		lines_container.add_child(label)
		_line_labels.append(label)
	_request_viewport_update()


func reveal_data_line(index: int) -> bool:
	if index < 0 or index >= _line_labels.size() or not is_instance_valid(_line_labels[index]):
		return false
	if _revealed[index] == 1:
		return true
	_revealed[index] = 1
	_line_labels[index].self_modulate.a = 1.0
	_request_viewport_update()
	return true


func reveal_all_data_lines() -> void:
	for index: int in _line_labels.size():
		reveal_data_line(index)


func get_contents() -> AutolysisQuestPaperContents:
	return null if _contents == null else _contents.copy_contents()


func get_visible_data_line_indices() -> PackedInt32Array:
	var indices: PackedInt32Array = []
	for index: int in _revealed.size():
		if _revealed[index] == 1:
			indices.append(index)
	return indices


func get_layout_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	for index: int in _line_labels.size():
		var label: Label = _line_labels[index]
		var missing: String = ""
		for character_index: int in label.text.length():
			if not paper_font.has_char(label.text.unicode_at(character_index)):
				missing += label.text.substr(character_index, 1)
		var natural_size: Vector2 = paper_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, body_font_size)
		report.append({
			"data_line_index": index, "text": label.text, "font_size": body_font_size,
			"font_name": paper_font.get_font_name(), "missing_characters": missing,
			"natural_width": natural_size.x, "font_height": paper_font.get_height(body_font_size),
			"visual_line_count": label.get_line_count(), "visual_line_height": label.get_line_height(),
			"position": label.position, "size": label.size, "minimum_size": label.get_combined_minimum_size(),
			"revealed": _revealed[index] == 1,
		})
	return report


func _request_viewport_update() -> void:
	if not is_inside_tree():
		return
	var viewport: Viewport = get_viewport()
	if viewport is SubViewport:
		(viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
