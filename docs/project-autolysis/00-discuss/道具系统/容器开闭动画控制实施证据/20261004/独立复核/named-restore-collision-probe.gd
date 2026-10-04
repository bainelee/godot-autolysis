extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var machine: AutolysisPackingMachine = load("res://main-autolysis/scenes/prefabs/prefab_machines/machine_packing_0.tscn").instantiate()
	var controls: Array[AutolysisPackingMotion] = []
	controls.assign(machine.type_switches)
	controls.append(machine.door)
	var original_library: AnimationLibrary = machine.animation_source.get_animation_library(&"")
	var qualified_library: AnimationLibrary = AnimationLibrary.new()
	for control: AutolysisPackingMotion in controls:
		var local_name: StringName = control.animation_name
		qualified_library.add_animation(local_name, original_library.get_animation(local_name))
		original_library.remove_animation(local_name)
		control.animation_name = StringName("_packing_restore/" + String(local_name))
	machine.animation_source.add_animation_library(&"_packing_restore", qualified_library)
	root.add_child(machine)
	for frame: int in 3:
		await physics_frame
		await process_frame
	print("整机登记有效：", machine.is_configured())
	for control: AutolysisPackingMotion in controls:
		var runtime: AnimationPlayer = control.get("_runtime_player")
		print("动作名称：", control.animation_name, "；源动画保留：", machine.animation_source.has_animation(control.animation_name), "；独立动画保留：", runtime.has_animation(control.animation_name), "；控制件有效：", control.is_configured(), "；关闭稳定：", control.is_closed())
	machine.queue_free()
	await process_frame
	quit()