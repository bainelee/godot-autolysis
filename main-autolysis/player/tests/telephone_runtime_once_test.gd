extends "res://main-autolysis/player/tests/telephone_device_test.gd"
## 各模式独立进程验证等待或受理失败也消耗运行机会；无图形内部业务调用。

const CallController = preload("res://main-autolysis/scenes/prefabs/prefab_machines/scripts/autolysis_telephone_call_controller.gd")


func run_checks() -> void:
	check(DisplayServer.get_name() == "headless", "运行机会专项实际使用无图形后端")
	var runtime: Node = root.get_node("AutolysisRuntimeSession")
	check(not runtime.is_telephone_test_consumed(), "本独立游戏进程重新获得初次运行机会")
	await _new_scene()
	var trigger: AutolysisTelephoneCallTestTrigger = world.get_node("TelephoneCallTestTrigger")
	var rejected: bool = OS.get_cmdline_user_args().has("--reject-request")
	if rejected:
		trigger.dialogue_definition = null
		check(not trigger.request_test_call(), "缺失对话定义使具体电话受理失败")
	else:
		await _enter()
		await _take()
		check(trigger.request_test_call(), "真实成对持筒时测试入口请求来电")
		check(phone.call_controller.get_call_snapshot().stage == CallController.Stage.WAIT_RETURN and not phone.call_controller.ring_player.playing, "测试入口持筒请求进入等待放回且不响铃")
	check(runtime.is_telephone_test_consumed(), "请求进入等待或受理失败均已消耗本进程机会")
	phone.call_controller.cancel_call("运行机会专项取消")
	check(runtime.is_telephone_test_consumed() and not trigger.request_test_call(), "取消或具体受理失败不退还运行机会")
	var audio_references: Array[Dictionary] = _capture_audio_exit_refs()
	await _new_scene()
	trigger = world.get_node("TelephoneCallTestTrigger")
	check(runtime.is_telephone_test_consumed() and not trigger.request_test_call(), "重新创建电话及主场景仍不能重复测试请求")
	check(phone.call_controller.get_call_snapshot().stage == CallController.Stage.IDLE, "重建电话保持未请求且不自动恢复旧来电")
	audio_references.append_array(_capture_audio_exit_refs())
	world.queue_free()
	await frames(3)
	await _await_audio_exit_release(audio_references)
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var output := FileAccess.open(evidence_directory.path_join("运行机会等待或失败报告.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "模式": "受理失败" if rejected else "持筒等待", "断言": records, "退出音频采样": audio_exit_samples, "失败数": failures}, "\t"))
	output.close()
	quit(1 if failures > 0 else 0)
