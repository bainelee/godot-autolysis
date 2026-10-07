class_name AutolysisCrosshair
extends Control
## 仅显示直接交互可用状态，不检测物体、不读取输入。

const CENTER_SIZE: float = 2.0
const LINE_LENGTH: float = 20.0
const LINE_WIDTH: float = 2.0
const EDGE_GAP: float = 8.0

@export var direct_color: Color = Color.WHITE:
	set(value):
		if direct_color == value:
			return
		direct_color = value
		queue_redraw()

var _direct_available: bool = false
var _center_rectangle: Rect2 = Rect2()
var _direct_rectangles: Array[Rect2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	resized.connect(_update_geometry)
	_update_geometry()


func set_direct_available(available: bool) -> void:
	if _direct_available == available:
		return
	_direct_available = available
	queue_redraw()


func _update_geometry() -> void:
	# 奇数视口向下取整半尺寸，保持所有矩形边缘落在整数像素。
	var center: Vector2 = (size * 0.5).floor()
	var half_center: float = CENTER_SIZE * 0.5
	var half_width: float = LINE_WIDTH * 0.5
	var inner_edge: float = half_center + EDGE_GAP
	var outer_edge: float = inner_edge + LINE_LENGTH
	_center_rectangle = Rect2(center - Vector2.ONE * half_center, Vector2.ONE * CENTER_SIZE)
	_direct_rectangles = [
		Rect2(center + Vector2(-half_width, -outer_edge), Vector2(LINE_WIDTH, LINE_LENGTH)),
		Rect2(center + Vector2(-half_width, inner_edge), Vector2(LINE_WIDTH, LINE_LENGTH)),
		Rect2(center + Vector2(-outer_edge, -half_width), Vector2(LINE_LENGTH, LINE_WIDTH)),
		Rect2(center + Vector2(inner_edge, -half_width), Vector2(LINE_LENGTH, LINE_WIDTH)),
	]
	queue_redraw()


func _draw() -> void:
	draw_rect(_center_rectangle, Color.WHITE, true, -1.0, false)
	if _direct_available:
		for rectangle: Rect2 in _direct_rectangles:
			draw_rect(rectangle, direct_color, true, -1.0, false)
