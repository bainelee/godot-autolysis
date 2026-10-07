class_name AutolysisLiquidContentsPanel
extends CanvasLayer
## 临时内容界面观察当前满罐或封装胶囊，不处理鼠标输入。

@export var top_left_margin: Vector2 = Vector2(24, 24)
@export var panel_width: float = 570.0

var _controller: AutolysisInventoryController
var _instance: AutolysisItemInstance
var _contents: AutolysisLiquidContents
var _packing_contents: AutolysisPackingContents

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Text


func _ready() -> void:
	_panel.position = top_left_margin
	_panel.custom_minimum_size.x = panel_width
	_refresh()


func configure(controller: AutolysisInventoryController) -> void:
	if is_instance_valid(_controller) and _controller.inventory_changed.is_connected(_refresh):
		_controller.inventory_changed.disconnect(_refresh)
	_controller = controller
	if is_instance_valid(_controller):
		_controller.inventory_changed.connect(_refresh)
	_refresh()


func get_contents_text() -> String:
	return _label.text if is_node_ready() else ""


func is_showing_contents() -> bool:
	return is_node_ready() and _panel.visible


func _refresh() -> void:
	if not is_node_ready():
		return
	var instance: AutolysisItemInstance = _controller.get_focused_instance() if is_instance_valid(_controller) else null
	_watch_instance(instance)
	if _instance == null or not _instance.is_valid_instance() or (_contents == null and _packing_contents == null):
		_label.text = ""
		_panel.hide()
		return
	var phase: Vector3 = _instance.get_phase_rgb()
	var wave: Array[int] = _instance.get_wave_coordinates()
	var heading: String = "液体罐：有液体" if _contents != null else "气动胶囊：已封装"
	var raw_material_display: String = _contents.get_raw_material_display() if _contents != null else _packing_contents.get_raw_material_display()
	_label.text = "%s\n原药：%s\n相位重构：r（红）＝%s，g（绿）＝%s，b（蓝）＝%s\n波形重构：（%d，%d，%d，%d，%d）" % [
		heading, raw_material_display,
		_format_number(phase.x), _format_number(phase.y), _format_number(phase.z),
		wave[0], wave[1], wave[2], wave[3], wave[4],
	]
	if _packing_contents != null:
		_label.text += "\n封装类型：%s" % _packing_contents.get_packing_type_display()
	_panel.show()


func _watch_instance(instance: AutolysisItemInstance) -> void:
	if _instance != instance:
		if _instance != null and _instance.changed.is_connected(_refresh):
			_instance.changed.disconnect(_refresh)
		_instance = instance
		if _instance != null:
			_instance.changed.connect(_refresh)
	_contents = _instance.liquid_contents if _instance != null else null
	_packing_contents = _instance.packing_contents if _instance != null else null


func _format_number(value: float) -> String:
	return "0" if value == 0.0 else str(value)


func _exit_tree() -> void:
	if is_instance_valid(_controller) and _controller.inventory_changed.is_connected(_refresh):
		_controller.inventory_changed.disconnect(_refresh)
	_controller = null
	_watch_instance(null)
