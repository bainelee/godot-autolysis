extends "res://main-autolysis/systems/item-system/tests/packing_machine_behavior_test.gd"
## 正式玩家重复拨动三类开关，记录端帧与物理同步状态。

var repeat_samples: Array[Dictionary] = []


func run_checks() -> void:
	graphical = DisplayServer.get_name() != "headless"
	original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	evidence_directory = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/封装器与气动胶囊实施证据/20261003/switch-fault/input")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	await _new_scene()
	await _enter()
	await _put_tank(_source_contents())
	await _put_capsule()
	for cycle: int in range(6):
		for type_index: int in range(3):
			var control: AutolysisPackingTypeSwitch = machine.type_switches[type_index]
			await _click(_body_pixel(control))
			await _observe_motion(control, cycle, "开启")
			check(control.get_configuration_error().is_empty() and control.is_open() and machine.get_selected_type() == type_index, "第%d轮类型%d第一次拨动稳定开启且无运动故障" % [cycle, type_index])
			if not control.get_configuration_error().is_empty():
				break
			await _click(_body_pixel(control))
			await _observe_motion(control, cycle, "关闭")
			check(control.get_configuration_error().is_empty() and control.is_closed() and machine.get_selected_type() == -1, "第%d轮类型%d第二次拨动稳定关闭且无运动故障" % [cycle, type_index])
			if not control.get_configuration_error().is_empty():
				break
		if not machine.is_configured():
			break
	var report_file: FileAccess = FileAccess.open(evidence_directory.path_join("重复拨动输入报告.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify({"断言数": assertion_count, "失败数": failures, "图形运行": graphical, "命令参数": OS.get_cmdline_args(), "实际射线": ray_records, "断言": records, "运动采样": repeat_samples}, "\t"))
	report_file.close()
	_release_controls()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = original_accumulation
	world.queue_free()
	await frames(2)
	print("重复拨动验收断言数：", assertion_count, "；失败总数：", failures)
	quit(1 if failures > 0 else 0)


func _observe_motion(control: AutolysisPackingTypeSwitch, cycle: int, direction: String) -> void:
	for sample_index: int in range(30):
		var runtime: AnimationPlayer = control.get("_runtime_player")
		repeat_samples.append({"轮次": cycle, "方向": direction, "类型": control.packing_type, "物理帧": Engine.get_physics_frames(), "状态": control.state, "动画进度": runtime.current_animation_position, "角度": str(control.rotation), "物理角度": str(control.global_transform.basis.get_euler()), "播放中": runtime.is_playing(), "待完成": control.get("_completion_pending"), "配置错误": control.get_configuration_error()})
		if not control.get_configuration_error().is_empty() or not control.is_animating():
			return
		await frames(1)
