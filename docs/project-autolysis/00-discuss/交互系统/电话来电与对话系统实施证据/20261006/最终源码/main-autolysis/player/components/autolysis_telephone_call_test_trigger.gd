class_name AutolysisTelephoneCallTestTrigger
extends Node

@export var telephone: AutolysisTelephone
@export var player: AutolysisPlayer
@export var dialogue_definition: AutolysisDialogueDefinition
@export var test_action: StringName = &"telephone_call_test"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func request_test_call() -> bool:
	if not _node_is_live(player) or player.is_dialogue_timing_paused():
		return false
	var runtime_session: Node = get_node_or_null("/root/AutolysisRuntimeSession")
	if runtime_session == null or not runtime_session.consume_telephone_test_once():
		return false
	# 领取后即消耗运行机会；受理失败、场景重载和异常均不退还。
	if not _node_is_live(telephone) or not _node_is_live(player.dialogue_player):
		return false
	return telephone.request_call(dialogue_definition, player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(test_action):
		return
	if not _node_is_live(player) or player.is_dialogue_timing_paused() or player.is_handset_text_editing():
		return
	request_test_call()
	get_viewport().set_input_as_handled()


static func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
