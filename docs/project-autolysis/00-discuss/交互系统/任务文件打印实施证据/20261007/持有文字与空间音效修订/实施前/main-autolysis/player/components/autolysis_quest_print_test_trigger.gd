class_name AutolysisQuestPrintTestTrigger
extends Node

@export var machine: AutolysisQuestMachine
@export var player: AutolysisPlayer
@export var task_definition: AutolysisQuestPrintDefinition
@export var test_action: StringName = &"quest_print_test"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func request_test_print() -> bool:
	if not _node_is_live(player) or not _node_is_live(machine):
		return false
	if player.is_dialogue_timing_paused() or not player.is_inventory_input_allowed():
		return false
	return machine.request_task_print(task_definition, player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(test_action):
		return
	if not _node_is_live(player) or not player.is_inventory_input_allowed():
		return
	request_test_print()
	get_viewport().set_input_as_handled()


static func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
