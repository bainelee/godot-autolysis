class_name AutolysisItemInstance
extends Resource
## 逐件状态独立于共享定义；转移时保留此资源身份。

var definition: AutolysisItemDefinition
var liquid_contents: AutolysisLiquidContents:
	get:
		return _liquid_contents
	set(value):
		set_liquid_contents(value)

var _liquid_contents: AutolysisLiquidContents


static func create(item_definition: AutolysisItemDefinition) -> AutolysisItemInstance:
	if not is_instance_valid(item_definition) or not item_definition.is_valid_definition():
		return null
	var instance: AutolysisItemInstance = AutolysisItemInstance.new()
	instance.definition = item_definition
	return instance


func is_valid_instance() -> bool:
	if not is_instance_valid(definition) or not definition.is_valid_definition():
		return false
	if _liquid_contents == null:
		return true
	return is_liquid_tank() and _liquid_contents.is_valid_contents()


func is_liquid_tank() -> bool:
	return is_instance_valid(definition) and definition.item_id == &"liquid_tank" and not definition.is_raw_material


func is_empty_liquid_tank() -> bool:
	return is_valid_instance() and is_liquid_tank() and _liquid_contents == null


func get_phase_rgb() -> Vector3:
	return Vector3.ZERO if _liquid_contents == null else _liquid_contents.get_phase_rgb()


func get_wave_coordinates() -> Array[int]:
	return [0, 0, 0, 0, 0] if _liquid_contents == null else _liquid_contents.get_wave_coordinates()


func set_liquid_contents(contents: AutolysisLiquidContents, notify: bool = true) -> bool:
	if contents != null and (not is_liquid_tank() or not contents.is_valid_contents()):
		return false
	if _liquid_contents == contents:
		return true
	# 对新内容建立逐件副本，禁止两只罐共享可变重构数据。
	var owned_contents: AutolysisLiquidContents = null if contents == null else contents.copy_contents()
	if contents != null and owned_contents == null:
		return false
	if _liquid_contents != null and _liquid_contents.changed.is_connected(_on_contents_changed):
		_liquid_contents.changed.disconnect(_on_contents_changed)
	_liquid_contents = owned_contents
	if _liquid_contents != null:
		_liquid_contents.changed.connect(_on_contents_changed)
	if notify:
		emit_changed()
	return true


func _on_contents_changed() -> void:
	emit_changed()
