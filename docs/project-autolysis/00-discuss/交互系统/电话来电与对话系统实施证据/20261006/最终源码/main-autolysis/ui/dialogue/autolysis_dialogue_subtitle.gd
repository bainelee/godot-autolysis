class_name AutolysisDialogueSubtitle
extends CanvasLayer
## 字幕只管理表现；所有位置均换算到本画布坐标。

@export var subtitle_font: Font
@export var subtitle_font_size: int = 24
@export var subtitle_max_width: float = 1000.0
@export var subtitle_single_line_height: float = 40.0
@export var subtitle_horizontal_padding: float = 16.0
@export var subtitle_inventory_gap: float = 8.0
@export var subtitle_screen_margin: float = 16.0

var _inventory_bar: CanvasLayer
var _token: int = 0
var _line_index: int = -1
var _text: String = ""
var _last_inventory_rect: Rect2
var _last_viewport_rect: Rect2
var _last_canvas_transform: Transform2D
var _last_configuration: Array = []
var _layout: Dictionary = {}

@onready var _display: Panel = $Display
@onready var _label: Label = $Display/Text


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if subtitle_font != null:
		_label.add_theme_font_override("font", subtitle_font)
	_label.add_theme_font_size_override("font_size", subtitle_font_size)
	_label.theme_changed.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	_display.hide()


func setup(inventory_bar: CanvasLayer) -> void:
	_inventory_bar = inventory_bar
	_queue_layout()


func is_available() -> bool:
	return is_inside_tree() and is_node_ready() and is_instance_valid(_display) \
		and is_instance_valid(_label) and is_instance_valid(_inventory_bar) \
		and not is_queued_for_deletion() and _display.is_inside_tree() and not _display.is_queued_for_deletion() \
		and _label.is_inside_tree() and not _label.is_queued_for_deletion() \
		and _inventory_bar.is_inside_tree() and not _inventory_bar.is_queued_for_deletion() \
		and _inventory_bar.has_method("get_bar_rect")


func get_configuration_error() -> String:
	if subtitle_font_size <= 0:
		return "字幕字号必须为正整数"
	for entry: Array in [
		["字幕最大宽度", subtitle_max_width, true],
		["字幕单行背景高度", subtitle_single_line_height, true],
		["字幕水平内边距", subtitle_horizontal_padding, false],
		["字幕道具栏间距", subtitle_inventory_gap, false],
		["字幕屏幕留白", subtitle_screen_margin, false],
	]:
		var value: float = entry[1]
		if not is_finite(value) or value < 0.0 or (bool(entry[2]) and value == 0.0):
			return "%s必须为有限%s值" % [entry[0], "正" if bool(entry[2]) else "非负"]
	return ""


func prepare_line(token: int, line_index: int, text: String) -> bool:
	if not is_available() or not get_configuration_error().is_empty():
		return false
	_token = token
	_line_index = line_index
	_text = text
	_label.text = text
	_refresh_layout(token, line_index)
	return true


func show_prepared_line(token: int, line_index: int) -> bool:
	if not is_available() or _token != token or _line_index != line_index:
		return false
	_refresh_layout(token, line_index)
	_display.modulate = Color.WHITE
	_display.show()
	return true


func hide_line(token: int) -> void:
	if _token != token:
		return
	_token = 0
	_line_index = -1
	_text = ""
	if is_instance_valid(_display):
		_display.modulate = Color.WHITE
		_display.hide()


func get_fade_target() -> Control:
	return _display if is_available() else null


func get_layout_snapshot() -> Dictionary:
	var snapshot: Dictionary = _layout.duplicate(true)
	snapshot["token"] = _token
	snapshot["index"] = _line_index
	snapshot["text"] = _text
	snapshot["visible"] = is_instance_valid(_display) and _display.visible
	snapshot["alpha"] = _display.modulate.a if is_instance_valid(_display) else 0.0
	return snapshot


func _process(_delta: float) -> void:
	if _token == 0 or not is_available():
		return
	var inventory_rect: Rect2 = _inventory_rect_in_canvas()
	var viewport_rect: Rect2 = _viewport_rect_in_canvas()
	if inventory_rect != _last_inventory_rect or viewport_rect != _last_viewport_rect \
			or get_final_transform() != _last_canvas_transform or _configuration() != _last_configuration:
		_refresh_layout(_token, _line_index)


func _queue_layout() -> void:
	if _token != 0:
		_refresh_layout.call_deferred(_token, _line_index)


func _inventory_rect_in_canvas() -> Rect2:
	var rect: Rect2 = _inventory_bar.call("get_bar_rect")
	return get_final_transform().affine_inverse() * (_inventory_bar.get_final_transform() * rect)


func _viewport_rect_in_canvas() -> Rect2:
	return get_final_transform().affine_inverse() * get_viewport().get_visible_rect()


func _refresh_layout(token: int, line_index: int) -> void:
	if token != _token or line_index != _line_index or not is_available() \
			or not get_configuration_error().is_empty():
		return
	if subtitle_font != null and _label.get_theme_font("font") != subtitle_font:
		_label.add_theme_font_override("font", subtitle_font)
	elif subtitle_font == null and _label.has_theme_font_override("font"):
		_label.remove_theme_font_override("font")
	if _label.get_theme_font_size("font_size") != subtitle_font_size:
		_label.add_theme_font_size_override("font_size", subtitle_font_size)
	var font: Font = _label.get_theme_font("font")
	var font_size: int = _label.get_theme_font_size("font_size")
	var natural_size: Vector2 = font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var viewport_rect: Rect2 = _viewport_rect_in_canvas()
	var inventory_rect: Rect2 = _inventory_rect_in_canvas()
	var available_width: float = maxf(1.0, viewport_rect.size.x - subtitle_screen_margin * 2.0)
	var width: float = minf(natural_size.x + subtitle_horizontal_padding * 2.0,
		minf(subtitle_max_width, available_width))
	width = maxf(1.0, width)
	var horizontal_padding: float = minf(subtitle_horizontal_padding, maxf(0.0, (width - 1.0) * 0.5))
	var text_width: float = maxf(1.0, width - horizontal_padding * 2.0)
	_label.position = Vector2(horizontal_padding, 0.0)
	_label.size = Vector2(text_width, 0.0)
	# 请求标签真实最小尺寸会立即完成引擎排版，不估算字符宽度或行高。
	var text_height: float = _label.get_minimum_size().y
	var line_count: int = _label.get_line_count()
	var single_height: float = font.get_height(font_size)
	var vertical_padding: float = maxf(0.0, (subtitle_single_line_height - single_height) * 0.5)
	var height: float = subtitle_single_line_height if line_count <= 1 \
		else maxf(subtitle_single_line_height, text_height + vertical_padding * 2.0)
	_display.size = Vector2(width, height)
	_display.position = Vector2(viewport_rect.position.x + (viewport_rect.size.x - width) * 0.5,
		inventory_rect.position.y - subtitle_inventory_gap - height)
	_label.position.y = (height - text_height) * 0.5
	_label.size = Vector2(text_width, text_height)
	_last_inventory_rect = inventory_rect
	_last_viewport_rect = viewport_rect
	_last_canvas_transform = get_final_transform()
	_last_configuration = _configuration()
	_layout = {
		"background_rect": _display.get_global_rect(),
		"text_rect": _label.get_global_rect(),
		"inventory_rect": inventory_rect,
		"viewport_rect": viewport_rect,
		"natural_size": natural_size,
		"text_height": text_height,
		"font_height": single_height,
		"font_name": font.get_font_name(),
		"font_resource": font.resource_path,
		"font_size": font_size,
		"line_count": line_count,
		"horizontal_padding": horizontal_padding,
		"vertical_padding": vertical_padding,
	}


func _configuration() -> Array:
	return [subtitle_font, subtitle_font_size, subtitle_max_width, subtitle_single_line_height,
		subtitle_horizontal_padding, subtitle_inventory_gap, subtitle_screen_margin]
