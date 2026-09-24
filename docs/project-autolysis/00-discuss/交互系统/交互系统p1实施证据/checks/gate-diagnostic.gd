extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed: PackedScene = load("res://main-autolysis/player/tests/direct_interaction_demo.tscn")
	var demo: Node3D = packed.instantiate()
	root.add_child(demo)
	await process_frame
	var actor: AutolysisPlayer = demo.get_node("Player")
	var component: AutolysisInteractionComponent = demo.get_node("SwitchA/Interaction")
	print("诊断：后端=", DisplayServer.get_name(), "，鼠标模式=", Input.mouse_mode, "，捕获值=", Input.MOUSE_MODE_CAPTURED)
	print("诊断：暂停=", paused, "，移动暂停=", actor.is_movement_paused, "，界面=", actor.is_showing_ui, "，眩晕=", actor.is_landing_stunned, "，玩家许可=", actor.is_interaction_input_allowed())
	print("诊断：组件可用=", component.can_interact(actor), "，射线命中=", actor.interaction_raycast.refresh_target() == demo.get_node("SwitchA"), "，控制器可用=", actor.interaction_controller.is_direct_available())
	demo.queue_free()
	await process_frame
	quit()