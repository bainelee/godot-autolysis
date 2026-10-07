extends "res://main-autolysis/player/tests/quest_paper_inventory_test.gd"


func run_checks() -> void:
	await _fixture()
	var references: Array[WeakRef] = []
	var source_ids: Array[Dictionary] = []
	for node: Node in world.find_children("*", "AudioStreamPlayer3D", true, false):
		var output: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		if output.has_stream_playback():
			var playback: AudioStreamPlayback = output.get_stream_playback()
			references.append(weakref(playback))
			source_ids.append({"音源路径": str(output.get_path()), "播放身份": playback.get_instance_id()})
	var count_before: int = _count_alive(references)
	_capture_retiring_audio()
	world.queue_free()
	await frames(3)
	var count_after_three: int = _count_alive(references)
	var world_released: bool = not is_instance_valid(world)
	if "--corrected-read" in OS.get_cmdline_user_args():
		await _wait_for_audio_retirement()
		check(_count_alive(references) == 0, "修正后的同一实际音频对象退出读取点没有残留")
	else:
		check(count_after_three == 0, "原取纸专项三帧退出读取点没有残留实际音频播放对象")
	var started: int = Time.get_ticks_usec()
	while _count_alive(references) > 0 and Time.get_ticks_usec() - started < 2000000:
		OS.delay_msec(1)
		await process_frame
	var count_after_retirement: int = _count_alive(references)
	check(count_after_retirement == 0, "原实际音频播放对象在自然服务器清理后全部退役")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	var report: FileAccess = FileAccess.open(evidence_directory.path_join("取纸退出实际播放对象.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"来源": source_ids, "释放前实际播放数": count_before, "三帧后场景已释放": world_released, "三帧后实际播放残留": count_after_three, "实际退役后残留": count_after_retirement, "实际退役观察微秒": Time.get_ticks_usec() - started, "参数": OS.get_cmdline_args()}, "\t"))
	report.close()
	quit(1 if failures > 0 else 0)


func _count_alive(references: Array[WeakRef]) -> int:
	var count: int = 0
	for reference: WeakRef in references:
		if reference.get_ref() != null:
			count += 1
	return count
