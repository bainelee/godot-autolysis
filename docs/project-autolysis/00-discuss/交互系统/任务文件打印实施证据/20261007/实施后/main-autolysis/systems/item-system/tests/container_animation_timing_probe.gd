extends SceneTree
## 仅测量正式资产的动画应用与物理同步；不判定业务许可。

const MAIN_SCENE: PackedScene = preload("res://main-autolysis/scenes/01-autolysis-test.tscn")
var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/容器开闭动画控制实施证据/20261004/timing")

var records: Array[Dictionary] = []
var action: int = 0
var finished: bool = false
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = MAIN_SCENE.instantiate()
	var paths: Array[NodePath] = [
		NodePath("interaction_prefabs/machines/waste_liquid_storage_tank_0"),
		NodePath("interaction_prefabs/place_shelf_and_cabinet/cabinet_workroom_0"),
		NodePath("interaction_prefabs/machines/machine_packing_0"),
	]
	for path: NodePath in paths:
		var device: Node3D = main.get_node(path)
		var player: AnimationPlayer = device.get_node("AnimationPlayer")
		var names: Array[StringName] = []
		if str(path).contains("waste"):
			names.append(&"lid_open")
		elif str(path).contains("cabinet"):
			names.append(&"open")
		else:
			names.assign([&"door_capsules_input_bay_open", &"type_switch_0_open", &"type_switch_1_open", &"type_switch_2_open"])
		var original_transform: Transform3D = device.transform
		device.get_parent().remove_child(device)
		_remove_scripts(device)
		root.add_child(device)
		device.transform = original_transform
		player.playback_auto_capture = false
		for animation_name: StringName in names:
			var original: Animation = player.get_animation(animation_name)
			var body_path: NodePath = NodePath(original.track_get_path(0).get_concatenated_names())
			var body: AnimatableBody3D = device.get_node(body_path)
			for variant: int in 3:
				var source: Animation = original.duplicate(true)
				if variant > 0:
					var track: int = source.add_track(Animation.TYPE_VALUE)
					source.track_set_path(track, NodePath(str(body_path) + ":position"))
					source.track_insert_key(track, 0.0, body.position)
					source.track_insert_key(track, source.length, body.position + Vector3(0.07, 0.03, -0.02))
				var library: AnimationLibrary = AnimationLibrary.new()
				library.add_animation(&"probe", source)
				if player.has_animation_library(&"probe"):
					player.remove_animation_library(&"probe")
				player.add_animation_library(&"probe", library)
				player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if variant == 2 else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
				var applied_callback: Callable = _sample.bind("应用后", device, body, player, animation_name, variant)
				var finished_callback: Callable = _finished.bind(device, body, player, animation_name, variant)
				player.mixer_applied.connect(applied_callback)
				player.animation_finished.connect(finished_callback)
				player.play(&"probe/probe", 0.0)
				if variant == 2:
					body.set_notify_local_transform(false)
				player.seek(0.0, true, true)
				if variant == 2:
					_submit_transform(body)
				player.pause()
				await _frames(3)
				_sample("初始化同步后", device, body, player, animation_name, variant)
				for opening: bool in [true, false]:
					action += 1
					finished = false
					player.play(&"probe/probe", 0.0, 1.0 if opening else -1.0, not opening)
					for step: int in 120:
						await physics_frame
						_sample("物理帧前", device, body, player, animation_name, variant)
						if variant == 2 and player.is_playing():
							body.set_notify_local_transform(false)
							player.advance(1.0 / float(Engine.physics_ticks_per_second))
							_submit_transform(body)
						await process_frame
						_sample("普通帧前", device, body, player, animation_name, variant)
						if variant > 0 and opening and step == 2:
							player.pause()
							_sample("显式暂停", device, body, player, animation_name, variant)
							await _frames(3)
							player.play(&"probe/probe", 0.0)
						if finished:
							break
					if not finished:
						failures += 1
					for sample: int in 6:
						await _frames(1)
						_sample("稳定采样%d" % sample, device, body, player, animation_name, variant)
				player.mixer_applied.disconnect(applied_callback)
				player.animation_finished.disconnect(finished_callback)
		device.queue_free()
		await _frames(2)
	main.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("时序采样.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"记录": records, "失败数": failures, "引擎": Engine.get_version_info()}, "\t"))
	print("通过：六个物理对象原始与位移变体正反播时序采样；动作数：", action, "；失败数：", failures)
	quit(1 if failures else 0)


func _remove_scripts(node: Node) -> void:
	for child: Node in node.get_children():
		_remove_scripts(child)
	node.set_script(null)


func _frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame


func _submit_transform(body: AnimatableBody3D) -> void:
	var applied: Transform3D = body.transform
	body.set_notify_local_transform(true)
	body.transform = applied


func _finished(_name: StringName, device: Node3D, body: AnimatableBody3D, player: AnimationPlayer, name: StringName, variant: int) -> void:
	_sample("完成信号", device, body, player, name, variant)
	finished = true


func _sample(event: String, device: Node3D, body: AnimatableBody3D, player: AnimationPlayer, name: StringName, variant: int) -> void:
	records.append({"事件": event, "动作": action, "设备": str(device.name), "动画": str(name), "变体": variant, "物理帧": Engine.get_physics_frames(), "普通帧": Engine.get_process_frames(), "播放": player.is_playing(), "时间": player.current_animation_position, "局部变换": var_to_str(body.transform), "全局变换": var_to_str(body.global_transform), "父级变换": var_to_str(device.global_transform)})
