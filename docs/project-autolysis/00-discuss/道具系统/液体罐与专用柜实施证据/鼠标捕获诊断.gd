extends SceneTree
## 记录指定后端实际能否保留捕获鼠标模式。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor: AutolysisPlayer = load("res://main-autolysis/player/autolysis_player.tscn").instantiate() as AutolysisPlayer
	root.add_child(actor)
	actor.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await process_frame
	var result: Dictionary = {"图形后端": DisplayServer.get_name(), "要求捕获模式": Input.MOUSE_MODE_CAPTURED, "实际模式": Input.mouse_mode, "玩家基础许可": actor._base_input_allowed(), "玩家交互许可": actor.is_interaction_input_allowed()}
	var directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/液体罐与专用柜实施证据/checks/mouse-capability")
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(directory.path_join("捕获能力.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print(JSON.stringify(result))
	actor.queue_free()
	await process_frame
	quit(0)
