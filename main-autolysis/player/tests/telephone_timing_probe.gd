extends SceneTree
## 原生时序与实际字体探针。全程无图形，不伪造自然完成信号。

const EVIDENCE = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd")
const VOICE = preload("res://main-autolysis/assets/audio/speech/chat_0/chat_0_8.wav")
const RING = preload("res://main-autolysis/assets/audio/sound_fx/phone/sfx_phone_default_0.wav")
const LINES: Array[String] = [
	"早上好，马蒂亚斯中士。很高兴你平安抵达了。",
	"前线的情况不容乐观。",
	"你这次的任务依然艰巨，但我们相信你的能力和忠诚。",
	"与你之前的临床医疗任务不同",
	"海尔塔十四号研究所是一个配备先进设备的药物配给站。",
	"为了你的安全，你将在设施内完成为期十五天的封闭式任务。",
	"现在开始你的第一天吧。具体任务信息可以在“通知中心”查看。",
	"如果对设备操作有任何疑问，请查阅手册。",
	"你很快会习惯的。",
]

var failures: int = 0
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var font_measurements: Array[Dictionary] = []
var voice_finished: int = 0
var timer_finished: int = 0
var tween_finished: int = 0
var started_usec: int = 0


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
	checks.append({"说明": description, "通过": condition})
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1


func wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true).timeout


func sample(label: String, audio: AudioStreamPlayer, timer: Timer, visual: CanvasItem) -> Dictionary:
	var result: Dictionary = {
		"阶段": label, "墙钟秒": (Time.get_ticks_usec() - started_usec) / 1000000.0,
		"普通帧": Engine.get_process_frames(), "物理帧": Engine.get_physics_frames(),
		"场景树暂停": paused, "时序处理模式": audio.get_parent().process_mode,
		"音频位置": audio.get_playback_position(), "音频暂停": audio.stream_paused,
		"剩余计时": timer.time_left, "透明度": visual.modulate.a,
		"音频自然完成次数": voice_finished, "计时自然完成次数": timer_finished,
		"补间自然完成次数": tween_finished,
	}
	samples.append(result)
	return result


func _measure_font() -> void:
	for family: String in ["", "Noto Sans SC", "Microsoft YaHei"]:
		_measure_font_family(family)


func _measure_font_family(family: String) -> void:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 24)
	if not family.is_empty():
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray([family])
		label.add_theme_font_override("font", system_font)
	root.add_child(label)
	var font: Font = label.get_theme_font("font")
	var missing: String = ""
	for line: String in LINES:
		var absent: String = ""
		for index: int in line.length():
			if not font.has_char(line.unicode_at(index)):
				absent += line.substr(index, 1)
				missing += line.substr(index, 1)
		var size_value: Vector2 = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
		font_measurements.append({"字体家族": family, "文字": line, "字号": 24, "宽": size_value.x, "高": size_value.y, "缺字": absent})
	print("字体资源：", font.resource_path, "；家族：", family, "；单行高度：", font.get_height(24), "；缺字：", missing)
	# 字体探针记录事实；缺字由生产字幕明确配置回退字体解决，不把字体作为电话许可。
	label.free()


func run_checks() -> void:
	started_usec = Time.get_ticks_usec()
	_measure_font()
	if OS.get_cmdline_user_args().has("--font-only"):
		var font_dir: String = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/电话来电与对话系统实施证据/20261006/时序探针/字体")
		DirAccess.make_dir_recursive_absolute(font_dir)
		var font_output := FileAccess.open(font_dir.path_join("字体测量.json"), FileAccess.WRITE)
		font_output.store_string(JSON.stringify(font_measurements, "\t"))
		quit()
		return
	var owner := Node3D.new()
	owner.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(owner)
	var temporal := Node.new()
	temporal.process_mode = Node.PROCESS_MODE_PAUSABLE
	owner.add_child(temporal)
	var audio := AudioStreamPlayer.new()
	audio.stream = VOICE
	temporal.add_child(audio)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 1.0
	temporal.add_child(timer)
	var visual := Control.new()
	temporal.add_child(visual)
	audio.finished.connect(func() -> void: voice_finished += 1)
	timer.timeout.connect(func() -> void: timer_finished += 1)
	var tween: Tween = temporal.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	tween.tween_property(visual, "modulate:a", 0.0, 1.0)
	tween.finished.connect(func() -> void: tween_finished += 1)
	audio.play()
	timer.start()
	await wait_seconds(0.25)
	var before: Dictionary = sample("显式禁用前", audio, timer, visual)
	temporal.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_seconds(0.35)
	var disabled: Dictionary = sample("显式禁用保持", audio, timer, visual)
	check(is_equal_approx(before.剩余计时, disabled.剩余计时), "显式禁用冻结计时器原剩余进度")
	check(is_equal_approx(before.透明度, disabled.透明度), "显式禁用冻结绑定补间透明度")
	check(absf(before.音频位置 - disabled.音频位置) < 0.07 and audio.stream_paused, "显式禁用冻结原生音频位置并暂停音频流")
	temporal.process_mode = Node.PROCESS_MODE_PAUSABLE
	await wait_seconds(0.15)
	var resumed: Dictionary = sample("显式禁用恢复", audio, timer, visual)
	check(resumed.剩余计时 < disabled.剩余计时 and resumed.透明度 < disabled.透明度, "恢复后计时器与同一补间继续原进度")
	check(resumed.音频位置 > disabled.音频位置 and not audio.stream_paused, "恢复后同一语音继续原进度")
	paused = true
	var tree_before: Dictionary = sample("场景树暂停前", audio, timer, visual)
	await wait_seconds(0.35)
	var tree_after: Dictionary = sample("场景树暂停保持", audio, timer, visual)
	check(is_equal_approx(tree_before.剩余计时, tree_after.剩余计时), "场景树暂停冻结可暂停时序计时器")
	check(is_equal_approx(tree_before.透明度, tree_after.透明度), "场景树暂停冻结绑定补间")
	check(absf(tree_before.音频位置 - tree_after.音频位置) < 0.07 and audio.stream_paused, "场景树暂停冻结原生语音位置")
	temporal.process_mode = Node.PROCESS_MODE_DISABLED
	paused = false
	await wait_seconds(0.25)
	var overlap: Dictionary = sample("只恢复场景树后仍显式禁用", audio, timer, visual)
	check(is_equal_approx(tree_after.剩余计时, overlap.剩余计时) and is_equal_approx(tree_after.透明度, overlap.透明度) and audio.stream_paused, "只恢复场景树时显式禁用仍冻结全部时序")
	temporal.process_mode = Node.PROCESS_MODE_PAUSABLE
	var deadline: int = Time.get_ticks_msec() + 15000
	while (voice_finished == 0 or timer_finished == 0 or tween_finished == 0) and Time.get_ticks_msec() < deadline:
		await process_frame
	sample("三项原生自然完成", audio, timer, visual)
	check(voice_finished == 1, "真实语音恢复后自然完成恰好一次")
	check(timer_finished == 1, "原计时器恢复后自然到期恰好一次")
	check(tween_finished == 1, "原绑定补间恢复后自然完成恰好一次")
	var ring: AudioStreamWAV = RING.duplicate()
	var samples_count: int = roundi(ring.get_length() * ring.mix_rate)
	ring.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ring.loop_begin = 0
	ring.loop_end = samples_count
	var ring_player := AudioStreamPlayer3D.new()
	ring_player.stream = ring
	temporal.add_child(ring_player)
	var ring_events: Array[bool] = []
	ring_player.finished.connect(func() -> void: ring_events.append(true))
	ring_player.play()
	var ring_samples: Array[Dictionary] = []
	for index: int in 4:
		await wait_seconds(ring.get_length() * 0.8)
		ring_samples.append({"观测序号": index, "播放": ring_player.playing, "位置": ring_player.get_playback_position(), "墙钟秒": (Time.get_ticks_usec() - started_usec) / 1000000.0})
	check(ring_player.playing and ring_events.is_empty(), "指定铃声副本跨过三次完整时长仍循环且没有自然结束")
	check(RING.loop_mode == AudioStreamWAV.LOOP_DISABLED and VOICE.loop_mode == AudioStreamWAV.LOOP_DISABLED, "铃声副本未改写共享原铃声或语音的非循环模式")
	check(samples_count > 0 and ring.loop_end == samples_count, "铃声循环端点取引擎时长乘采样率还原的整数样本数")
	var report: Dictionary = {
		"引擎": Engine.get_version_info(), "后端": DisplayServer.get_name(), "采样": samples,
		"字体度量": font_measurements, "断言": checks, "失败数": failures,
		"铃声": {"时长": ring.get_length(), "采样率": ring.mix_rate, "压缩格式": ring.format, "资源数据字节": ring.data.size(), "循环端点": ring.loop_end, "观测": ring_samples},
		"语音资源": VOICE.resource_path, "语音时长": VOICE.get_length(),
	}
	var evidence_dir: String = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/电话来电与对话系统实施证据/20261006/时序探针")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	var output := FileAccess.open(evidence_dir.path_join("时序与字体测量.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	ring_player.stop()
	owner.free()
	quit(1 if failures > 0 else 0)
