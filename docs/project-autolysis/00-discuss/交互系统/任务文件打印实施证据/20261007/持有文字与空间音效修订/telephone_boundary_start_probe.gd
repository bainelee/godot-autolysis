extends "res://main-autolysis/player/tests/telephone_call_boundary_test.gd"

func run_checks() -> void:
	_prepare_single_definition()
	await _new_scene(true)
	await _enter()
	_wire_lifecycle_observers()
	phone.request_call(single_definition, player)
	await _take()
	var observations: Array[Dictionary] = []
	observations.append({"阶段": "原失败读取点", "墙钟微秒": Time.get_ticks_usec(), "来电": _call().get_call_snapshot(), "对白": _dialogue().get_session_snapshot(), "开始句数": boundary_lines, "语音引用存活": is_instance_valid(_call().voice_player), "语音归属": phone.is_ancestor_of(_call().voice_player), "实际语音输出相同": _dialogue().get_voice_output() == _call().voice_player, "声音控制器引用存活": is_instance_valid(phone.handset_audio)})
	check(boundary_lines == 1, "原读取点要求实际语音已开始")
	await _wait_realtime(func() -> bool: return boundary_lines == 1, "实际接听等待自然完成后语音开始")
	observations.append({"阶段": "真实等待自然完成后", "墙钟微秒": Time.get_ticks_usec(), "来电": _call().get_call_snapshot(), "对白": _dialogue().get_session_snapshot(), "开始句数": boundary_lines})
	var references: Array[Dictionary] = _capture_audio_exit_refs()
	_call().cancel_call("边界开始读取点诊断清理")
	world.queue_free()
	await frames(3)
	await _await_audio_exit_release(references)
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var output: FileAccess = FileAccess.open(evidence_directory.path_join("边界真实开始读取点.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"断言": records, "采样": observations, "失败数": failures}, "\t"))
	output.close()
	quit(1 if failures > 0 else 0)
