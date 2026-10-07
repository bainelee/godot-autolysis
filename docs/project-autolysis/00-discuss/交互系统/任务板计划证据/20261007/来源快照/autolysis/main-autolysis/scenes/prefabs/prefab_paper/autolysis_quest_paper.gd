class_name AutolysisQuestPaper
extends StaticBody3D
## 本次设备专用纸张来源；取纸只能经过对应聚焦库存事务。

const TEXT_MATERIAL: StandardMaterial3D = preload("res://main-autolysis/assets/materials/paper/mat_quest_paper_text.tres")

@export var item_definition: AutolysisItemDefinition
@export var interaction_component: AutolysisInteractionComponent
@export var paper_viewport: SubViewport
@export var paper_view: AutolysisQuestPaperView
@export var front_mesh: MeshInstance3D

var machine: Node3D
var print_serial: int = 0
var item_instance: AutolysisItemInstance
var _configured: bool = false
var _pickup_finished: bool = false
var _print_complete: bool = false
var _bound_contents: AutolysisQuestPaperContents


func configure(source_machine: Node3D, serial: int, instance: AutolysisItemInstance) -> bool:
	if is_inside_tree() or _configured or not is_instance_valid(source_machine) or serial <= 0:
		return false
	if not is_instance_valid(instance) or not instance.is_valid_instance() or not instance.is_quest_paper():
		return false
	var contents: AutolysisQuestPaperContents = instance.quest_paper_contents
	if contents == null or not contents.is_valid_contents() or not get_configuration_error().is_empty():
		return false
	if not paper_view.configure_contents(contents):
		return false
	machine = source_machine
	print_serial = serial
	item_definition = instance.definition
	item_instance = instance
	_bound_contents = contents
	_configured = true
	return true


func _ready() -> void:
	if not _configured or not get_configuration_error().is_empty():
		_disable_interaction()
		push_error("任务纸张必须由有效设备绑定完整逐件内容后入树。")
		return
	interaction_component.set_availability_check(_can_interact)
	interaction_component.set_execution_handler(_on_interaction_requested)
	# 文字独立叠加，保留纸面材质自身的颜色、纹理和映射方式。
	var material: StandardMaterial3D = TEXT_MATERIAL.duplicate() as StandardMaterial3D
	material.albedo_texture = paper_viewport.get_texture()
	front_mesh.material_overlay = material
	paper_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func get_configuration_error() -> String:
	if not is_instance_valid(interaction_component) or interaction_component.get_parent() != self:
		return "任务纸张缺少直属交互入口。"
	if not is_instance_valid(paper_viewport) or not is_instance_valid(paper_view) or not is_instance_valid(front_mesh):
		return "任务纸张缺少子视口、纸面界面或正面网格。"
	return paper_view.get_configuration_error()


func get_item_instance() -> AutolysisItemInstance:
	return item_instance


func get_machine() -> Node3D:
	return machine if is_instance_valid(machine) else null


func get_print_serial() -> int:
	return print_serial


func get_paper_viewport() -> SubViewport:
	return paper_viewport


func get_paper_view() -> AutolysisQuestPaperView:
	return paper_view


func get_visible_data_line_indices() -> PackedInt32Array:
	return paper_view.get_visible_data_line_indices() if is_instance_valid(paper_view) else PackedInt32Array()


func matches_source(source_machine: Node3D, serial: int, instance: AutolysisItemInstance) -> bool:
	if not _configured or _pickup_finished or is_queued_for_deletion() or not is_instance_valid(machine) or machine != source_machine or print_serial != serial or item_instance != instance or not is_instance_valid(item_instance) or not item_instance.is_valid_instance():
		return false
	var contents: AutolysisQuestPaperContents = item_instance.quest_paper_contents
	return contents != null and _bound_contents != null and contents.get_task_id() == _bound_contents.get_task_id() and contents.get_data_lines() == _bound_contents.get_data_lines() and contents.get_group_gap_before_lines() == _bound_contents.get_group_gap_before_lines()


func _is_current_source(serial: int) -> bool:
	if not matches_source(machine, serial, item_instance) or not is_instance_valid(machine) or machine.is_queued_for_deletion():
		return false
	if not machine.has_method(&"is_current_paper"):
		return false
	var result: Variant = machine.call(&"is_current_paper", self, serial, item_instance)
	return typeof(result) == TYPE_BOOL and result


func reveal_data_line(serial: int, index: int) -> bool:
	return _is_current_source(serial) and is_instance_valid(paper_view) and paper_view.reveal_data_line(index)


func complete_print(serial: int) -> bool:
	if not _is_current_source(serial) or not is_instance_valid(paper_view):
		return false
	paper_view.reveal_all_data_lines()
	_print_complete = true
	return true


func is_print_complete() -> bool:
	return _print_complete and not _pickup_finished


func finish_pickup() -> void:
	if _pickup_finished:
		return
	_pickup_finished = true
	_disable_interaction()
	collision_layer = 0
	collision_mask = 0
	hide()
	if is_instance_valid(self) and not is_queued_for_deletion():
		queue_free()


func _disable_interaction() -> void:
	if is_instance_valid(interaction_component):
		interaction_component.is_enabled = false
	remove_from_group(&"interactable")


func _can_interact(actor: Node3D) -> bool:
	if not _is_current_source(print_serial) or not is_instance_valid(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and inventory.can_take_quest_paper(actor, self)


func _on_interaction_requested(actor: Node3D) -> void:
	if not _is_current_source(print_serial) or not is_instance_valid(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if is_instance_valid(inventory):
		inventory.try_take_quest_paper(actor, self)
