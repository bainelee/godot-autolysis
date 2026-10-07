class_name AutolysisInventoryBar
extends CanvasLayer

const SLOT_COUNT: int = 4

var _controller: AutolysisInventoryController
var _last_focused_index: int = -1

@onready var _bar: HBoxContainer = $Bar
@onready var _focus_sound: AudioStreamPlayer = $FocusSound


func _ready() -> void:
	_refresh()


func configure(controller: AutolysisInventoryController) -> void:
	if is_instance_valid(_controller):
		if _controller.inventory_changed.is_connected(_refresh):
			_controller.inventory_changed.disconnect(_refresh)
	_controller = controller
	_last_focused_index = -1
	if is_instance_valid(_controller):
		_controller.inventory_changed.connect(_refresh)
	if is_node_ready():
		_refresh()


func get_slot_rect(index: int) -> Rect2:
	if not is_node_ready() or index < 0 or index >= SLOT_COUNT:
		return Rect2()
	var slot: Control = _bar.get_child(index) as Control
	return slot.get_global_rect()


func get_bar_rect() -> Rect2:
	if not is_node_ready():
		return Rect2()
	return _bar.get_global_rect()


func is_slot_highlighted(index: int) -> bool:
	if not is_node_ready() or index < 0 or index >= SLOT_COUNT:
		return false
	var highlight: Panel = _bar.get_child(index).get_node("Highlight") as Panel
	return highlight.visible


func _refresh() -> void:
	if not is_node_ready():
		return
	var focused_index: int = 0
	if is_instance_valid(_controller):
		focused_index = _controller.get_focused_index()
	for index: int in range(SLOT_COUNT):
		var slot: Control = _bar.get_child(index) as Control
		var icon: TextureRect = slot.get_node("Icon") as TextureRect
		var highlight: Panel = slot.get_node("Highlight") as Panel
		var item: AutolysisItemDefinition = null
		if is_instance_valid(_controller):
			item = _controller.get_slot_item(index)
		icon.texture = item.icon if item != null else null
		slot.tooltip_text = item.display_name if item != null else ""
		highlight.visible = index == focused_index
	if _last_focused_index >= 0 and _last_focused_index != focused_index:
		_focus_sound.play()
	_last_focused_index = focused_index
