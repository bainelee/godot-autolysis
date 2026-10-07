extends SceneTree
## 专属最小音频退出探针：仅播放与释放正式石材脚步音频。

var _directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://.godot")
var _samples: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for iteration: int in range(count):
		await physics_frame
		await process_frame


func _run() -> void:
	var container: Node3D = Node3D.new()
	root.add_child(container)
	var audio: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	container.add_child(audio)
	var profile: AudioStreamRandomizer = load("res://main-autolysis/systems/dynamic-footstep-system/footstep-profiles/stone_footstep_profile.tres")
	var profile_reference: WeakRef = weakref(profile)
	_samples.append({"阶段": "正式音频资源组", "资源": _audio_resource_graph(profile)})
	audio.stream = profile
	profile = null
	await _frames(3)
	if not "--no-playback" in OS.get_cmdline_user_args():
		audio.play()
	await _frames(45)
	var playback_reference: WeakRef = weakref(audio.get_stream_playback()) if audio.has_stream_playback() else null
	_samples.append(_snapshot("播放后", profile_reference, playback_reference))
	if "--stop-audio" in OS.get_cmdline_user_args():
		audio.stop()
	container.queue_free()
	audio = null
	container = null
	await _frames(3)
	_samples.append(_snapshot("场景释放三帧后", profile_reference, playback_reference))
	if "--extra-cleanup" in OS.get_cmdline_user_args():
		await _frames(30)
		_samples.append(_snapshot("额外三十帧后", profile_reference, playback_reference))
	if "--await-audio-release" in OS.get_cmdline_user_args():
		var start_msec: int = Time.get_ticks_msec()
		var process_frames: int = 0
		while _weak_alive(playback_reference) and Time.get_ticks_msec() - start_msec < 2000:
			await process_frame
			process_frames += 1
		_samples.append({"阶段": "等待实际音频播放实例释放", "耗时毫秒": Time.get_ticks_msec() - start_msec, "处理帧数": process_frames, "结果": _snapshot("必要播放实例消失条件", profile_reference, playback_reference)})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var file: FileAccess = FileAccess.open(_directory.path_join("最小音频退出复核.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_samples, "\t"))
	file.close()
	if "--await-audio-release" in OS.get_cmdline_user_args() and _weak_alive(playback_reference):
		print("失败：两秒上限内音频播放实例未释放")
		quit(1)
		return
	print("通过：最小音频探针执行结束，退出错误单独判定")
	quit()


func _snapshot(stage: String, profile: WeakRef, playback: WeakRef) -> Dictionary:
	return {"阶段": stage, "物理帧": Engine.get_physics_frames(), "音频资源": _info(profile), "音频播放实例": _info(playback), "资源数": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "孤立节点": Node.get_orphan_node_ids()}


func _info(reference: WeakRef) -> Dictionary:
	var object: RefCounted = reference.get_ref() if reference != null else null
	if object == null:
		return {"有效": false}
	return {"有效": true, "实例": object.get_instance_id(), "类型": object.get_class(), "临时查询引用在内的引用数": object.get_reference_count()}


func _weak_alive(reference: WeakRef) -> bool:
	# 把弱引用查询限制在同步函数内，避免临时强引用跨等待保留播放实例。
	return reference != null and is_instance_valid(reference.get_ref())


func _audio_resource_graph(profile: AudioStreamRandomizer) -> Array[Dictionary]:
	var resources: Array[Dictionary] = [_resource_identity(profile)]
	for index: int in profile.streams_count:
		var stream: AudioStreamOggVorbis = profile.get_stream(index) as AudioStreamOggVorbis
		resources.append(_resource_identity(stream))
		resources.append(_resource_identity(stream.packet_sequence))
	return resources


func _resource_identity(resource: Resource) -> Dictionary:
	return {"实例": resource.get_instance_id(), "类型": resource.get_class(), "来源": resource.resource_path}
