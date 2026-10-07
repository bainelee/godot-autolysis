class_name AutolysisLiquidContents
extends Resource
## 保存原始槽序和重复条目；外部读取数组得到副本。

const MAX_RAW_MATERIALS: int = 4
const RAW_MATERIAL_PATHS: Dictionary[String, String] = {
	"caffeine": "res://main-autolysis/systems/item-system/items/caffeine.tres",
	"sodium_benzoate": "res://main-autolysis/systems/item-system/items/sodium_benzoate.tres",
}

var _raw_material_ids: Array[String] = []
var _phase_rgb: Vector3 = Vector3.ZERO
var _wave_flag_0: bool = false
var _wave_flag_1: bool = false
var _wave_flag_2: bool = false
var _wave_flag_3: bool = false
var _wave_level: int = 0


static func create_result(ids: Array[String]) -> AutolysisLiquidContents:
	if not are_valid_raw_material_ids(ids):
		return null
	var contents: AutolysisLiquidContents = AutolysisLiquidContents.new()
	contents._raw_material_ids.assign(ids)
	return contents


static func resolve_raw_material_definition(id: String) -> AutolysisItemDefinition:
	if not RAW_MATERIAL_PATHS.has(id):
		return null
	var definition: AutolysisItemDefinition = load(RAW_MATERIAL_PATHS[id]) as AutolysisItemDefinition
	if not is_instance_valid(definition) or not definition.is_raw_material or str(definition.item_id) != id or not definition.is_valid_definition():
		return null
	return definition


static func are_valid_raw_material_ids(ids: Array[String]) -> bool:
	if ids.is_empty() or ids.size() > MAX_RAW_MATERIALS:
		return false
	for id: String in ids:
		if id.is_empty() or resolve_raw_material_definition(id) == null:
			return false
	return true


func is_valid_contents() -> bool:
	return are_valid_raw_material_ids(_raw_material_ids) and _phase_rgb.is_finite() and _wave_level >= 0 and _wave_level <= 6


func get_raw_material_ids() -> Array[String]:
	return _raw_material_ids.duplicate()


func copy_contents() -> AutolysisLiquidContents:
	if not is_valid_contents():
		return null
	var copied: AutolysisLiquidContents = create_result(_raw_material_ids)
	copied._phase_rgb = _phase_rgb
	copied._wave_flag_0 = _wave_flag_0
	copied._wave_flag_1 = _wave_flag_1
	copied._wave_flag_2 = _wave_flag_2
	copied._wave_flag_3 = _wave_flag_3
	copied._wave_level = _wave_level
	return copied


func get_phase_rgb() -> Vector3:
	return _phase_rgb


func set_phase_rgb(value: Vector3) -> bool:
	if not value.is_finite():
		return false
	if _phase_rgb != value:
		_phase_rgb = value
		emit_changed()
	return true


func set_wave(flag_0: bool, flag_1: bool, flag_2: bool, flag_3: bool, level: int) -> bool:
	if level < 0 or level > 6:
		return false
	if _wave_flag_0 != flag_0 or _wave_flag_1 != flag_1 or _wave_flag_2 != flag_2 or _wave_flag_3 != flag_3 or _wave_level != level:
		_wave_flag_0 = flag_0
		_wave_flag_1 = flag_1
		_wave_flag_2 = flag_2
		_wave_flag_3 = flag_3
		_wave_level = level
		emit_changed()
	return true


func get_wave_coordinates() -> Array[int]:
	return [int(_wave_flag_0), int(_wave_flag_1), int(_wave_flag_2), int(_wave_flag_3), _wave_level]


func get_raw_material_display() -> String:
	var counts: Dictionary[String, int] = {}
	var first_seen: Array[String] = []
	for id: String in _raw_material_ids:
		if not counts.has(id):
			counts[id] = 0
			first_seen.append(id)
		counts[id] += 1
	var parts: PackedStringArray = []
	for id: String in first_seen:
		var definition: AutolysisItemDefinition = resolve_raw_material_definition(id)
		if definition == null:
			return ""
		var text: String = definition.display_name
		if counts[id] > 1:
			text += "*%d" % counts[id]
		parts.append(text)
	return "、".join(parts)
