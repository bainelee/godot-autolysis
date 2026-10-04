extends "res://main-autolysis/systems/item-system/tests/blend_animation_variants_test.gd"
func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	await _make_fixture()
	var slot: AutolysisBlendSlot = device.slots[0]
	var runtime: AnimationPlayer = slot.get("_runtime_player")
	var source_root: Node = runtime.get_node(runtime.root_node)
	var external_animation: Animation = Animation.new()
	external_animation.length = 0.65
	var track: int = external_animation.add_track(Animation.TYPE_VALUE)
	external_animation.track_set_path(track, NodePath(str(source_root.get_path_to(slot)) + ":rotation"))
	external_animation.track_insert_key(track, 0.0, Vector3(0.0, 0.0, 0.37))
	external_animation.track_insert_key(track, 0.65, Vector3(0.0, 0.0, 0.37))
	runtime.get_animation_library(&"").add_animation(&"external", external_animation)
	runtime.animation_finished.connect(func(completed: StringName) -> void:
		if completed == slot.animation_name:
			print("自然完成回调待同步：", slot.get("_motion_pending"))
			runtime.play(&"external", 0.0)
			runtime.seek(0.1, true, true)
			runtime.pause()
	)
	print("请求接受：", slot.try_toggle(actor))
	await _frames(40)
	print("外部不同目标暂停后；指定名称：", runtime.assigned_animation, "；旧打开许可：", slot.is_open(), "；中断原因：", slot.get_motion_error(), "；实际旋转：", slot.rotation)
	world.queue_free()
	await _frames(2)
	quit()