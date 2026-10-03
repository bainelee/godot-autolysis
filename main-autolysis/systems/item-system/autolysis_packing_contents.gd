class_name AutolysisPackingContents
extends Resource
## 胶囊保存完整液体来源副本与封装类型，所有可变内容读取均返回副本。

enum PackingType { INJECTION, TINCTURE, POWDER }

var _source_contents: AutolysisLiquidContents
var _packing_type: int = -1


static func create_result(source: AutolysisLiquidContents, packing_type: int) -> AutolysisPackingContents:
	if not is_instance_valid(source) or not source.is_valid_contents() or not is_valid_packing_type(packing_type):
		return null
	var copied_source: AutolysisLiquidContents = source.copy_contents()
	if copied_source == null:
		return null
	var contents: AutolysisPackingContents = AutolysisPackingContents.new()
	contents._source_contents = copied_source
	contents._packing_type = packing_type
	return contents


static func is_valid_packing_type(packing_type: int) -> bool:
	return packing_type == PackingType.INJECTION or packing_type == PackingType.TINCTURE or packing_type == PackingType.POWDER


func is_valid_contents() -> bool:
	return is_instance_valid(_source_contents) and _source_contents.is_valid_contents() and is_valid_packing_type(_packing_type)


func copy_contents() -> AutolysisPackingContents:
	return create_result(_source_contents, _packing_type) if is_valid_contents() else null


func get_source_contents() -> AutolysisLiquidContents:
	return _source_contents.copy_contents() if is_valid_contents() else null


func get_raw_material_ids() -> Array[String]:
	var empty_ids: Array[String] = []
	return _source_contents.get_raw_material_ids() if is_valid_contents() else empty_ids


func get_phase_rgb() -> Vector3:
	return _source_contents.get_phase_rgb() if is_valid_contents() else Vector3.ZERO


func get_wave_coordinates() -> Array[int]:
	var empty_coordinates: Array[int] = [0, 0, 0, 0, 0]
	return _source_contents.get_wave_coordinates() if is_valid_contents() else empty_coordinates


func get_packing_type() -> int:
	return _packing_type if is_valid_contents() else -1


func get_packing_type_display() -> String:
	match get_packing_type():
		PackingType.INJECTION:
			return "针剂"
		PackingType.TINCTURE:
			return "酊剂"
		PackingType.POWDER:
			return "粉剂"
	return ""


func get_raw_material_display() -> String:
	return _source_contents.get_raw_material_display() if is_valid_contents() else ""
