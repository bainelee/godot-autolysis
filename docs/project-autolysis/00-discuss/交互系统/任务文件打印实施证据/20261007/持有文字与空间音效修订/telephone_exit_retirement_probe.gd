extends "res://main-autolysis/player/tests/telephone_call_test.gd"
## 退出诊断夹具：保留正式全链，弱引用仅测量释放边界，不留住播放实例。

var retirement_samples: Array[Dictionary] = []

func _audio_refs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in world.find_children("*", "", true, false):
		if (node is AudioStreamPlayer or node is AudioStreamPlayer3D) and node.has_stream_playback():
			var playback: AudioStreamPlayback = node.get_stream_playback()
			result.append({"来源": str(node.get_path()), "播放身份": playback.get_instance_id(), "播放类型": playback.get_class(), "资源路径": node.stream.resource_path if node.stream != null else "", "弱引用": weakref(playback)})
	return result

func _retirement_state(references: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for info: Dictionary in references:
		var object: RefCounted = (info["弱引用"] as WeakRef).get_ref()
		result.append({"来源": info["来源"], "播放身份": info["播放身份"], "播放类型": info["播放类型"], "资源路径": info["资源路径"], "残留": is_instance_valid(object), "临时查询在内的引用数": object.get_reference_count() if is_instance_valid(object) else 0})
	return result

func _has_pending(references: Array[Dictionary]) -> bool:
	for info: Dictionary in references:
		if is_instance_valid((info["弱引用"] as WeakRef).get_ref()):
			return true
	return false

func run_checks() -> void:
	_prepare_single_definition()
	if OS.get_cmdline_user_args().has("--minimal-retirement"):
		await _new_scene()
		await _enter()
		await _take()
		await _return()
	else:
		await _test_delay_reset_and_cancel()
		await _test_take_business_rollback_and_locks()
		await _test_completion_pending_and_cancel()
		await _test_optional_ring_and_source_failure()
	var references: Array[Dictionary] = _audio_refs()
	retirement_samples.append({"阶段": "整链结束且场景仍存活", "墙钟微秒": Time.get_ticks_usec(), "混音时钟": AudioServer.get_time_since_last_mix(), "播放": _retirement_state(references)})
	paused = false
	world.queue_free()
	await frames(3)
	if OS.get_cmdline_user_args().has("--correct-retirement"):
		var translated: Array[Dictionary] = []
		for info: Dictionary in references:
			translated.append({"source": info["来源"], "id": info["播放身份"], "class": info["播放类型"], "reference": info["弱引用"]})
		await _await_audio_exit_release(translated)
	retirement_samples.append({"阶段": "原三帧收尾后", "墙钟微秒": Time.get_ticks_usec(), "混音时钟": AudioServer.get_time_since_last_mix(), "播放": _retirement_state(references)})
	check(not _has_pending(references), "原收尾必须真正释放实际服务器播放实例")
	if OS.get_cmdline_user_args().has("--await-retirement"):
		var deadline: int = Time.get_ticks_usec() + 2000000
		while _has_pending(references) and Time.get_ticks_usec() < deadline:
			await process_frame
		retirement_samples.append({"阶段": "等待实际引用解除", "墙钟微秒": Time.get_ticks_usec(), "混音时钟": AudioServer.get_time_since_last_mix(), "播放": _retirement_state(references), "场景树暂停": paused})
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var output: FileAccess = FileAccess.open(evidence_directory.path_join("实际播放退役诊断.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"断言": records, "退役采样": retirement_samples, "失败数": failures}, "\t"))
	output.close()
	quit(1 if failures > 0 else 0)
