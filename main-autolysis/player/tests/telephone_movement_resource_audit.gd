extends "res://main-autolysis/player/tests/telephone_movement_test.gd"
## 专属诊断：只读记录资源引用及孤立节点；不修改正式移动专项。

var _resource_audit_paths: PackedStringArray = []
var _resource_audit_samples: Array[Dictionary] = []
var _resource_audit_started: bool = false
var _resource_audit_finished: bool = false
var _resource_audit_last_profile: WeakRef
var _resource_audit_last_playback: WeakRef


func run_checks() -> void:
	_collect_audit_paths("res://main-autolysis")
	_resource_audit_samples.append(_resource_audit_snapshot("移动开始前"))
	await super.run_checks()


func check(condition: bool, description: String) -> void:
	super.check(condition, description)
	if description == "归还后真实玩家可以通过原临时限位位置":
		var footstep: AudioStreamPlayer3D = actor.footstep_player
		if footstep.stream != null:
			_resource_audit_last_profile = weakref(footstep.stream)
		if footstep.has_stream_playback():
			_resource_audit_last_playback = weakref(footstep.get_stream_playback())
		_resource_audit_samples.append(_resource_audit_snapshot("最终运动完成但场景未释放"))
		if "--stop-final-audio" in OS.get_cmdline_user_args():
			actor.set_physics_process(false)
			footstep.stop()
			(footstep.get_node("LandingPlayer") as AudioStreamPlayer3D).stop()
			_resource_audit_samples.append(_resource_audit_snapshot("最终运动停止音频后"))


func frames(count: int) -> void:
	await super.frames(count)
	if is_instance_valid(world) and not _resource_audit_started:
		_resource_audit_started = true
		_resource_audit_samples.append(_resource_audit_snapshot("主场景入树后"))
	if not is_instance_valid(world) and _resource_audit_started and not _resource_audit_finished:
		_resource_audit_finished = true
		_resource_audit_samples.append(_resource_audit_snapshot("主场景释放三帧后"))
		if "--extra-cleanup" in OS.get_cmdline_user_args():
			await super.frames(30)
			_resource_audit_samples.append(_resource_audit_snapshot("额外三十帧后"))
		if "--await-audio-release" in OS.get_cmdline_user_args():
			var start_msec: int = Time.get_ticks_msec()
			var process_frames: int = 0
			while (_resource_audit_weak_alive(_resource_audit_last_profile) or _resource_audit_weak_alive(_resource_audit_last_playback)) and Time.get_ticks_msec() - start_msec < 2000:
				await process_frame
				process_frames += 1
			_resource_audit_samples.append({"阶段": "正式运动等待实际音频清理", "耗时毫秒": Time.get_ticks_msec() - start_msec, "处理帧数": process_frames, "结果": _resource_audit_snapshot("音频实例与来源真正消失条件")})
			if _resource_audit_weak_alive(_resource_audit_last_profile) or _resource_audit_weak_alive(_resource_audit_last_playback):
				check(false, "正式运动两秒上限内音频实例与来源未清理")
		var file: FileAccess = FileAccess.open(evidence_directory.path_join("移动资源引用复核.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(_resource_audit_samples, "\t"))
		file.close()


func _collect_audit_paths(directory_path: String) -> void:
	for child: String in DirAccess.get_directories_at(directory_path):
		_collect_audit_paths(directory_path.path_join(child))
	for file_name: String in DirAccess.get_files_at(directory_path):
		if file_name.get_extension() in ["gd", "tscn", "tres", "ogg", "wav"]:
			_resource_audit_paths.append(directory_path.path_join(file_name))


func _resource_audit_snapshot(stage: String) -> Dictionary:
	var cached: Array[Dictionary] = []
	for path: String in _resource_audit_paths:
		var resource: Resource = ResourceLoader.get_cached_ref(path)
		if is_instance_valid(resource):
			cached.append({"路径": path, "实例": resource.get_instance_id(), "类型": resource.get_class(), "临时查询引用在内的引用数": resource.get_reference_count()})
	var orphans: Array[Dictionary] = []
	for object_id: int in Node.get_orphan_node_ids():
		var node: Node = instance_from_id(object_id) as Node
		if is_instance_valid(node):
			orphans.append({"实例": object_id, "类型": node.get_class(), "名称": str(node.name), "脚本": str(node.get_script().resource_path) if node.get_script() != null else ""})
	return {"阶段": stage, "物理帧": Engine.get_physics_frames(), "资源数": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "缓存资源": cached, "孤立节点": orphans,
		"最后音频资源": _resource_audit_weak_info(_resource_audit_last_profile), "最后音频播放实例": _resource_audit_weak_info(_resource_audit_last_playback)}


func _resource_audit_weak_info(reference: WeakRef) -> Dictionary:
	var object: RefCounted = reference.get_ref() if reference != null else null
	if object == null:
		return {"有效": false}
	return {"有效": true, "实例": object.get_instance_id(), "类型": object.get_class(), "临时查询引用在内的引用数": object.get_reference_count()}


func _resource_audit_weak_alive(reference: WeakRef) -> bool:
	return reference != null and is_instance_valid(reference.get_ref())
