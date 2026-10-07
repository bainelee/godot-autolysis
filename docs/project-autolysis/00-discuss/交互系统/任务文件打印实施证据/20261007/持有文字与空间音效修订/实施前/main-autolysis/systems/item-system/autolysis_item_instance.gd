class_name AutolysisItemInstance
extends Resource
## 逐件状态独立于共享定义；转移时保留此资源身份。

var definition: AutolysisItemDefinition
var liquid_contents: AutolysisLiquidContents:
	get:
		return _liquid_contents
	set(value):
		set_liquid_contents(value)
var packing_contents: AutolysisPackingContents:
	get:
		return null if _packing_contents == null else _packing_contents.copy_contents()
	set(value):
		set_packing_contents(value)
var quest_paper_contents: AutolysisQuestPaperContents:
	get:
		return null if _quest_paper_contents == null else _quest_paper_contents.copy_contents()
	set(value):
		set_quest_paper_contents(value)

var _liquid_contents: AutolysisLiquidContents
var _packing_contents: AutolysisPackingContents
var _quest_paper_contents: AutolysisQuestPaperContents


static func create(item_definition: AutolysisItemDefinition) -> AutolysisItemInstance:
	if not is_instance_valid(item_definition) or not item_definition.is_valid_definition():
		return null
	var instance: AutolysisItemInstance = AutolysisItemInstance.new()
	instance.definition = item_definition
	return instance


func is_valid_instance() -> bool:
	if not is_instance_valid(definition) or not definition.is_valid_definition():
		return false
	if _liquid_contents != null and (not is_liquid_tank() or not _liquid_contents.is_valid_contents()):
		return false
	if _packing_contents != null and (not is_pneumatic_capsule() or not _packing_contents.is_valid_contents()):
		return false
	if _quest_paper_contents != null and (not is_quest_paper() or not _quest_paper_contents.is_valid_contents()):
		return false
	return true


func is_liquid_tank() -> bool:
	return is_instance_valid(definition) and definition.item_id == &"liquid_tank" and not definition.is_raw_material


func is_empty_liquid_tank() -> bool:
	return is_valid_instance() and is_liquid_tank() and _liquid_contents == null


func is_pneumatic_capsule() -> bool:
	return is_instance_valid(definition) and definition.item_id == &"pneumatic_capsule" and not definition.is_raw_material


func is_empty_pneumatic_capsule() -> bool:
	return is_valid_instance() and is_pneumatic_capsule() and _packing_contents == null


func is_quest_paper() -> bool:
	return is_instance_valid(definition) and definition.item_id == &"quest_paper" and not definition.is_raw_material


func get_phase_rgb() -> Vector3:
	if _packing_contents != null:
		return _packing_contents.get_phase_rgb()
	return Vector3.ZERO if _liquid_contents == null else _liquid_contents.get_phase_rgb()


func get_wave_coordinates() -> Array[int]:
	if _packing_contents != null:
		return _packing_contents.get_wave_coordinates()
	if _liquid_contents == null:
		var empty_coordinates: Array[int] = [0, 0, 0, 0, 0]
		return empty_coordinates
	return _liquid_contents.get_wave_coordinates()


func set_liquid_contents(contents: AutolysisLiquidContents, notify: bool = true) -> bool:
	if contents != null and (not is_liquid_tank() or _packing_contents != null or _quest_paper_contents != null or not contents.is_valid_contents()):
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


func set_packing_contents(contents: AutolysisPackingContents, notify: bool = true) -> bool:
	if contents != null and (not is_pneumatic_capsule() or _liquid_contents != null or _quest_paper_contents != null or not contents.is_valid_contents()):
		return false
	if _packing_contents == null and contents == null:
		return true
	# 本件保存完整副本；读取也复制，调用方不能改写已经完成的产物。
	var owned_contents: AutolysisPackingContents = null if contents == null else contents.copy_contents()
	if contents != null and owned_contents == null:
		return false
	_packing_contents = owned_contents
	if notify:
		emit_changed()
	return true


func set_quest_paper_contents(contents: AutolysisQuestPaperContents, notify: bool = true) -> bool:
	if contents != null and (not is_quest_paper() or _liquid_contents != null or _packing_contents != null or not contents.is_valid_contents()):
		return false
	if _quest_paper_contents == null and contents == null:
		return true
	var owned_contents: AutolysisQuestPaperContents = null if contents == null else contents.copy_contents()
	if contents != null and owned_contents == null:
		return false
	_quest_paper_contents = owned_contents
	if notify:
		emit_changed()
	return true


func _on_contents_changed() -> void:
	emit_changed()
