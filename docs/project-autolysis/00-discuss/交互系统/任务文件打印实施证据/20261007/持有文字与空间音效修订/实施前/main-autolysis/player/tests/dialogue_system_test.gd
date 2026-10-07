extends SceneTree
## 通用逐句播放、配置及排版专项。音频完成均来自真实资源自然播放。

const PLAYER_SCENE = preload("res://main-autolysis/player/autolysis_player.tscn")
const DEFINITION = preload("res://main-autolysis/systems/dialogue-system/chat_0.tres")
const EVIDENCE = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd")
const TIMING_PROBE = preload("res://main-autolysis/player/tests/telephone_timing_probe.gd")

var failures: int = 0
var checks: Array[Dictionary] = []
var layouts: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var world: Node3D
var player: AutolysisPlayer
var dialogue: AutolysisDialoguePlayer
var source: Node
var normal_count: int = 0
var abort_count: int = 0
var observation_count: int = 0
var finished_result: Dictionary = {}
var single: AutolysisDialogueDefinition
var real_voice_finishes: int = 0
var real_line_starts: Array[int] = []


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
	checks.append({"说明": description, "通过": condition})
	print(("通过：" if condition else "失败：") + description)
	if not condition:
		failures += 1


func frames(count: int) -> void:
	for index: int in count:
		await process_frame


func wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true).timeout


func wait_until(condition: Callable, label: String, maximum_seconds: float = 12.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(maximum_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	check(false, "等待上限仅用于验收失败：" + label)
	return false


func setup_fixture() -> void:
	paused = false
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	root.add_child(world)
	player = PLAYER_SCENE.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.is_movement_paused = false
	player.is_showing_ui = false
	dialogue = player.dialogue_player
	source = Node.new()
	world.add_child(source)
	await frames(3)
	single = DEFINITION.duplicate()
	single.dialogue_id = &"single_test"
	single.line_ids = PackedStringArray(["chat_0_8"])
	single.voice_streams = [DEFINITION.voice_streams[8]]


func _prepare(definition: AutolysisDialogueDefinition) -> Dictionary:
	return dialogue.prepare_dialogue(definition, source, _business_finished, _business_aborted)


func _record_transition(snapshot: Dictionary) -> void:
	var record: Dictionary = snapshot.duplicate(true)
	record["墙钟微秒"] = Time.get_ticks_usec()
	record["普通帧"] = Engine.get_process_frames()
	record["物理帧"] = Engine.get_physics_frames()
	transitions.append(record)


func _business_finished(_token: int, _dialogue_id: StringName, _source: Node) -> void:
	normal_count += 1
	finished_result = dialogue.get_session_snapshot().last_result
	check(not dialogue.get_subtitle().get_layout_snapshot().visible, "业务正常完成接收者已看到字幕隐藏")
	var reentrant: Dictionary = _prepare(single)
	check(not reentrant.ok and reentrant.get("busy", false), "正常业务完成发布期间新准备返回忙碌")


func _business_aborted(_token: int, _dialogue_id: StringName, _source: Node, reason: String) -> void:
	abort_count += 1
	check(not reason.is_empty(), "异常业务接收者取得真实原因")


func _observe_finished(_token: int, _dialogue_id: StringName, _source: Node) -> void:
	observation_count += 1
	var reentrant: Dictionary = _prepare(single)
	check(not reentrant.ok and reentrant.get("busy", false), "正常完成观察期间新准备仍返回忙碌")


func _on_real_line_started(_token: int, _dialogue_id: StringName, index: int, text: String) -> void:
	real_line_starts.append(index)
	var voice: AudioStreamPlayer = dialogue.get_node("Timing/Voice")
	var subtitle: Dictionary = dialogue.get_subtitle().get_layout_snapshot()
	check(text == TIMING_PROBE.LINES[index] and voice.stream == DEFINITION.voice_streams[index], "实际开始第%d句同时使用对应中文和真实语音" % index)
	check(voice.playing and subtitle.visible and is_equal_approx(subtitle.alpha, 1.0), "实际开始第%d句文字背景与语音同时存在且透明度复原" % index)


func _on_real_stage_changed(_token: int, stage: StringName, index: int) -> void:
	if stage == &"hold":
		check(real_voice_finishes == index + 1, "第%d句只有真实语音自然结束后才开始句后保留" % index)
	_record_transition(dialogue.get_session_snapshot())


func _test_configurations() -> void:
	var snapshot: Dictionary = DEFINITION.make_snapshot()
	check(snapshot.ok and snapshot.lines.size() == 9 and snapshot.voices.size() == 9, "首段明确九句有序文本与语音快照")
	var cfg := ConfigFile.new()
	check(cfg.load("res://main-autolysis/systems/dialogue-system/dialogue_source.cfg") == OK, "独立原文配置真实可读取")
	var csv := FileAccess.open("res://main-autolysis/systems/dialogue-system/dialogue_zh.csv", FileAccess.READ)
	check(csv.get_csv_line() == PackedStringArray(["keys", "zh"]), "中文表格实际表头只有稳定键及中文列")
	var seen: Dictionary = {}
	for index: int in 9:
		var row: PackedStringArray = csv.get_csv_line()
		var key: String = "chat_0_%d" % index
		check(row.size() == 2 and row[0] == key and not seen.has(key), "中文配置有序且编号唯一：第%d句" % index)
		seen[key] = true
		check(row[1] == TIMING_PROBE.LINES[index] and cfg.get_value("chat_0", key, "") == row[1], "原文与中文首次逐字一致：第%d句" % index)
		check(snapshot.lines[index] == row[1], "运行译文逐句来自明确中文翻译资源：第%d句" % index)
		check(snapshot.voices[index].resource_path.ends_with("chat_0_%d.wav" % index), "第%d句语音映射使用对应实际文件" % index)
	check(not snapshot.lines[3].ends_with("。"), "第四句没有新增末尾标点")
	cfg.set_value("chat_0", "chat_0_0", "此原文仅在独立内存配置中修改")
	check(DEFINITION.make_snapshot().lines[0] == snapshot.lines[0], "修改独立原文配置对象不改变明确中文资源快照")
	var alternative: Translation = Translation.new()
	alternative.locale = "zh"
	alternative.add_message(&"chat_0_8", &"中文明确资源变体")
	var changed: AutolysisDialogueDefinition = single.duplicate()
	changed.chinese_translation = alternative
	check(changed.make_snapshot().lines[0] == "中文明确资源变体", "显式中文资源变体决定运行译文")
	for reason: String in ["缺键", "空译文", "重复编号", "缺语音", "循环语音", "负等待"]:
		var invalid: AutolysisDialogueDefinition = single.duplicate()
		match reason:
			"缺键": invalid.line_ids = PackedStringArray(["absent"])
			"空译文": invalid.chinese_translation = Translation.new()
			"重复编号":
				invalid.line_ids = PackedStringArray(["chat_0_8", "chat_0_8"])
				invalid.voice_streams = [DEFINITION.voice_streams[8], DEFINITION.voice_streams[8]]
			"缺语音": invalid.voice_streams = [null]
			"循环语音":
				var looping: AudioStreamWAV = DEFINITION.voice_streams[8].duplicate()
				looping.loop_mode = AudioStreamWAV.LOOP_FORWARD
				invalid.voice_streams = [looping]
			"负等待": invalid.post_voice_hold_seconds = -1.0
		var rejected: Dictionary = invalid.make_snapshot()
		check(not rejected.ok and not rejected.reason.is_empty(), reason + "变体明确拒绝并报告原因")


func _check_layout(text: String, index: int, label: String) -> Dictionary:
	check(dialogue.get_subtitle().prepare_line(700, index, text), label + "准备字幕布局")
	check(dialogue.get_subtitle().show_prepared_line(700, index), label + "同步显示当前布局")
	var layout: Dictionary = dialogue.get_subtitle().get_layout_snapshot()
	layouts.append(layout)
	var background: Rect2 = layout.background_rect
	var viewport: Rect2 = layout.viewport_rect
	var inventory_rect: Rect2 = layout.inventory_rect
	check(is_equal_approx(background.get_center().x, viewport.get_center().x), label + "背景实际矩形水平居中")
	check(is_equal_approx(background.end.y, inventory_rect.position.y - 8.0), label + "背景底边在实际道具栏顶边上方八像素")
	check(background.size.x <= minf(1000.0, maxf(1.0, viewport.size.x - 32.0)) + 0.01, label + "实际宽度包含内边距且不超过上限及可用视口")
	check(layout.font_size == 24, label + "实际字体字号保持二十四")
	return layout


func _test_layouts() -> void:
	var short: Dictionary = _check_layout(TIMING_PROBE.LINES[8], 0, "短句")
	check(short.line_count == 1 and is_equal_approx(short.background_rect.size.y, 40.0), "短句单行背景实际高度四十像素")
	check(short.background_rect.size.x < 1000.0 and is_equal_approx(short.background_rect.size.x, short.natural_size.x + 32.0), "短句背景依实际字体宽度自适应而非固定最大宽")
	var longest: Dictionary = _check_layout(TIMING_PROBE.LINES[6], 1, "首段最长句")
	var font: Font = dialogue.get_subtitle().get_node("Display/Text").get_theme_font("font")
	for index: int in 9:
		var missing: String = ""
		for character: int in TIMING_PROBE.LINES[index].length():
			if not font.has_char(TIMING_PROBE.LINES[index].unicode_at(character)):
				missing += TIMING_PROBE.LINES[index].substr(character, 1)
		check(missing.is_empty(), "实际字幕字体第%d句全部字形存在" % index)
	check(longest.font_height <= 40.0, "实际字号二十四字体单行高度可完整容纳四十像素背景")
	var long_line: String = TIMING_PROBE.LINES[6].repeat(8)
	var wrapped: Dictionary = _check_layout(long_line, 2, "长中文")
	check(wrapped.line_count > 1 and wrapped.background_rect.size.y > 40.0, "长中文真实换行且背景高度依实际排版增长")
	check(is_equal_approx(wrapped.background_rect.size.y, wrapped.text_height + wrapped.vertical_padding * 2.0), "多行背景使用真实排版高度与单行上下留白")
	root.size = Vector2i(420, 720)
	await frames(3)
	var narrow: Dictionary = _check_layout(long_line, 3, "窄视口")
	check(narrow.line_count > wrapped.line_count and narrow.background_rect.size.x <= 388.01, "窄视口按真实可用宽度增加换行")
	var long_word: Dictionary = _check_layout("W".repeat(140), 4, "连续长词")
	check(long_word.line_count > 1 and long_word.text_rect.size.x <= long_word.background_rect.size.x, "连续长词按智能换行限定文本控件宽度")
	var bar: Control = player.inventory_bar.get_node("Bar")
	bar.position.y -= 30.0
	await frames(3)
	var moved: Dictionary = dialogue.get_subtitle().get_layout_snapshot()
	layouts.append(moved)
	check(is_equal_approx(moved.background_rect.end.y, moved.inventory_rect.position.y - 8.0), "道具栏真实布局移动后字幕保持八像素间距")
	dialogue.get_subtitle().prepare_line(701, 9, "新布局")
	# 这是显式旧布局回调注入，不能作为自然完成证据。
	dialogue.get_subtitle().call("_refresh_layout", 700, 4)
	check(dialogue.get_subtitle().get_layout_snapshot().token == 701 and dialogue.get_subtitle().get_layout_snapshot().text == "新布局", "旧布局回调注入不能覆盖新句")
	for control: Control in [dialogue.get_subtitle().get_node("Display"), dialogue.get_subtitle().get_node("Display/Text")]:
		check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE and control.focus_mode == Control.FOCUS_NONE, "字幕及背景忽略鼠标且不取得焦点")
	dialogue.get_subtitle().hide_line(701)
	root.size = Vector2i(1280, 720)
	await frames(3)


func _test_prepare_cancel_and_pause() -> void:
	var prepared: Dictionary = _prepare(single)
	check(prepared.ok and not dialogue.get_subtitle().get_layout_snapshot().visible, "准备独占令牌且不显示字幕")
	var busy: Dictionary = _prepare(single)
	check(not busy.ok and busy.get("busy", false), "准备未启动时其他会话被忙碌拒绝")
	player.is_movement_paused = true
	check(dialogue.start_prepared_dialogue(prepared.token), "暂停中启动请求被登记为待启动")
	await wait_seconds(0.2)
	check(not dialogue.get_subtitle().get_layout_snapshot().visible and _prepare(single).get("busy", false), "暂停待启动保留原令牌且不显示或被新准备覆盖")
	player.is_movement_paused = false
	await wait_until(func() -> bool: return dialogue.get_subtitle().get_layout_snapshot().visible, "恢复开始原准备句")
	check(dialogue.cancel_dialogue(prepared.token, "专项显式取消"), "匹配令牌显式取消成功")
	check(not dialogue.get_subtitle().get_layout_snapshot().visible and normal_count == 0 and abort_count == 1, "显式取消隐藏字幕且只异常通知一次")
	check(not dialogue.cancel_dialogue(prepared.token, "旧取消"), "已失效旧令牌不能重复取消")
	var zero: AutolysisDialogueDefinition = single.duplicate()
	zero.post_voice_hold_seconds = 0.0
	var zero_prepared: Dictionary = _prepare(zero)
	check(zero_prepared.ok, "零秒等待可以正常准备")
	dialogue.cancel_dialogue(zero_prepared.token, "零等待准备清理")
	var frozen: Dictionary = _prepare(single)
	single.post_voice_hold_seconds = 0.33
	check(is_equal_approx(dialogue.get("_snapshot").get("post_voice_hold_seconds"), 1.5), "运行中准备快照保留原句后等待")
	dialogue.cancel_dialogue(frozen.token, "快照测试清理")
	single.post_voice_hold_seconds = 1.5


func _test_nine_real_voices() -> void:
	normal_count = 0
	observation_count = 0
	dialogue.dialogue_finished.connect(_observe_finished)
	dialogue.dialogue_finished.connect(func(token: int, dialogue_id: StringName, origin: Node) -> void: _observe_finished(token, dialogue_id, origin))
	dialogue.line_started.connect(_on_real_line_started)
	dialogue.stage_changed.connect(_on_real_stage_changed)
	var voice: AudioStreamPlayer = dialogue.get_node("Timing/Voice")
	voice.finished.connect(func() -> void: real_voice_finishes += 1)
	var prepared: Dictionary = _prepare(DEFINITION)
	check(prepared.ok and dialogue.start_prepared_dialogue(prepared.token), "九句正式资源准备并启动真实逐句播放")
	var previous: String = ""
	var deadline: int = Time.get_ticks_msec() + 150000
	while normal_count == 0 and Time.get_ticks_msec() < deadline:
		var snapshot: Dictionary = dialogue.get_session_snapshot()
		var identity: String = "%s:%s" % [snapshot.get("index", -1), snapshot.get("stage", "")]
		if identity != previous:
			_record_transition(snapshot)
			previous = identity
		await process_frame
	check(normal_count == 1 and observation_count == 2, "九句自然音频与最后渐隐完成仅一次业务及两位观察通知")
	check(real_voice_finishes == 9 and real_line_starts == [0, 1, 2, 3, 4, 5, 6, 7, 8], "九句真实音频自然完成次数与开始顺序均准确")
	check(not dialogue.get_subtitle().get_layout_snapshot().visible, "九句末句收尾后文字和背景隐藏")
	var started_indices: Array[int] = []
	for record: Dictionary in transitions:
		var index: int = record.get("index", -1)
		if index >= 0 and not started_indices.has(index):
			started_indices.append(index)
	check(started_indices == [0, 1, 2, 3, 4, 5, 6, 7, 8], "真实逐句开始顺序为零至八且不跳句")
	var next: Dictionary = _prepare(single)
	check(next.ok, "正常业务和观察发布收尾后播放容量释放")
	dialogue.cancel_dialogue(next.token, "后续会话清理")


func run_checks() -> void:
	check(DisplayServer.get_name() == "headless", "专项实际使用无图形后端")
	await setup_fixture()
	_test_configurations()
	await _test_layouts()
	await _test_prepare_cancel_and_pause()
	await _test_nine_real_voices()
	var evidence_dir: String = EVIDENCE.directory("res://docs/project-autolysis/00-discuss/交互系统/电话来电与对话系统实施证据/20261006/专项验收/对话")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	var output := FileAccess.open(evidence_dir.path_join("对话配置排版与真实播放.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "断言": checks, "排版": layouts, "阶段采样": transitions, "完成结果": finished_result, "失败数": failures}, "\t"))
	world.queue_free()
	await frames(3)
	quit(1 if failures > 0 else 0)
