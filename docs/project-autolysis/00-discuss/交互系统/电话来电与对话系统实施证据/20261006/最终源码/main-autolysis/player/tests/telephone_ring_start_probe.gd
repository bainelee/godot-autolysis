extends SceneTree
## 原生空间音频首次待启动与节点暂停探针；位置只用于采样，不影响任何生产许可。

const RING = preload("res://main-autolysis/assets/audio/sound_fx/phone/sfx_phone_default_0.wav")
const EVIDENCE = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd")

var failures: int = 0
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
	checks.append({"说明": description, "通过": condition})
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1


func sample(label: String, audio: AudioStreamPlayer3D) -> Dictionary:
	var value: Dictionary = {"说明": label, "普通帧": Engine.get_process_frames(), "物理帧": Engine.get_physics_frames(), "位置": audio.get_playback_position(), "播放": audio.playing, "流暂停": audio.stream_paused, "处理模式": audio.get_parent().process_mode, "墙钟微秒": Time.get_ticks_usec()}
	samples.append(value)
	return value


func run_checks() -> void:
	var owner := Node3D.new()
	owner.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(owner)
	var temporal := Node3D.new()
	temporal.process_mode = Node.PROCESS_MODE_PAUSABLE
	owner.add_child(temporal)
	var camera := Camera3D.new()
	owner.add_child(camera)
	camera.current = true
	var audio := AudioStreamPlayer3D.new()
	var copy: AudioStreamWAV = RING.duplicate()
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	copy.loop_end = roundi(copy.get_length() * copy.mix_rate)
	audio.stream = copy
	temporal.add_child(audio)
	audio.play()
	sample("调用播放后尚无物理处理", audio)
	temporal.process_mode = Node.PROCESS_MODE_DISABLED
	sample("首次物理处理前禁用", audio)
	await create_timer(0.3, true).timeout
	var pending: Dictionary = sample("禁用保持待首次启动", audio)
	check(pending.播放 and is_zero_approx(pending.位置), "首次物理启动前禁用保留待启动请求且音频位置未推进")
	temporal.process_mode = Node.PROCESS_MODE_PAUSABLE
	var deadline: int = Time.get_ticks_msec() + 5000
	while audio.get_playback_position() < 0.2 and Time.get_ticks_msec() < deadline:
		await process_frame
	var started: Dictionary = sample("恢复后真实物理启动与推进", audio)
	check(started.播放 and started.位置 >= 0.2, "恢复后同一待启动空间音频开始并实际推进")
	temporal.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	var before: Dictionary = sample("实际中途禁用", audio)
	await create_timer(0.3, true).timeout
	var after: Dictionary = sample("实际中途禁用保持", audio)
	check(before.流暂停 and after.流暂停 and absf(before.位置 - after.位置) < 0.07, "实际中途禁用空间音频流暂停并保留位置")
	temporal.process_mode = Node.PROCESS_MODE_PAUSABLE
	await create_timer(0.2, true).timeout
	var resumed: Dictionary = sample("实际中途恢复", audio)
	check(resumed.位置 > after.位置 and not resumed.流暂停, "实际中途恢复继续原空间声音进度")
	var directory: String = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/电话来电与对话系统实施证据/20261006/时序探针/首次空间播放")
	DirAccess.make_dir_recursive_absolute(directory)
	var output := FileAccess.open(directory.path_join("空间铃声首次启动与暂停.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "断言": checks, "采样": samples, "失败数": failures}, "\t"))
	audio.stop()
	owner.free()
	quit(1 if failures > 0 else 0)
