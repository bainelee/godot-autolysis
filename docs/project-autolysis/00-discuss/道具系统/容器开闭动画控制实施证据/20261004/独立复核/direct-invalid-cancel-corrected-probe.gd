extends SceneTree
class ImmediateCancel extends Node:
	var container: Node3D
	var calls: int = 0
	func cancel() -> void:
		calls += 1
		var body: AnimatableBody3D = container.lid_body if container is AutolysisWasteLiquidStorageTank else container.door_body
		body.sync_to_physics = false
		container.cancel_motion("立即必要物理同步失效取消")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var world := Node3D.new()
	var actor := Node3D.new()
	world.add_child(actor)
	root.add_child(world)
	for scene_path: String in ["res://main-autolysis/scenes/prefabs/prefab_machines/waste_liquid_storage_tank_0.tscn", "res://main-autolysis/scenes/prefabs/prefab_place_shelf/cabinet_workroom_0.tscn"]:
		var container: Node3D = load(scene_path).instantiate()
		var waste: bool = container is AutolysisWasteLiquidStorageTank
		var body: AnimatableBody3D = container.lid_body if waste else container.door_body
		var player: AnimationPlayer = container.animation_player
		player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
		var source_animation: Animation = player.get_animation(container.animation_name).duplicate()
		var source_library := AnimationLibrary.new()
		source_library.add_animation(container.animation_name, source_animation)
		player.remove_animation_library(&"")
		player.add_animation_library(&"", source_library)
		var cancel_event := ImmediateCancel.new()
		cancel_event.name = "ImmediateEvent"
		cancel_event.container = container
		container.add_child(cancel_event)
		var track: int = source_animation.add_track(Animation.TYPE_METHOD)
		source_animation.track_set_path(track, NodePath("ImmediateEvent"))
		source_animation.track_insert_key(track, 0.075, {"method": &"cancel", "args": []})
		var closed_position: Vector3 = body.position
		track = source_animation.add_track(Animation.TYPE_VALUE)
		source_animation.track_set_path(track, NodePath(str(container.get_path_to(body)) + ":position"))
		source_animation.track_insert_key(track, 0.0, closed_position)
		source_animation.track_insert_key(track, source_animation.length, closed_position + Vector3(0.0, 0.2, 0.0))
		world.add_child(container)
		for frame: int in 3:
			await physics_frame
			await process_frame
		var closed_transform: Transform3D = body.transform
		print("初始化类型：", "废液罐" if waste else "专用柜", "；可切换：", container.can_toggle(actor))
		container.try_toggle(actor)
		for frame: int in 30:
			await physics_frame
			await process_frame
		print("依赖失效类型：", "废液罐" if waste else "专用柜", "；取消次数：", cancel_event.calls, "；拒绝切换：", not container.can_toggle(actor), "；动作停止：", not player.is_playing())
		body.sync_to_physics = true
		print("修复重新绑定：", container.rebind_animation_player(player))
		for frame: int in 3:
			await physics_frame
			await process_frame
		print("修复后类型：", "废液罐" if waste else "专用柜", "；切换可用：", container.can_toggle(actor), "；稳定关闭：", not container.is_open() and not container.is_animating(), "；关闭完整姿态：", body.transform.is_equal_approx(closed_transform))
		container.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	quit()