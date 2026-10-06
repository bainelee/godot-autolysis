extends SceneTree
## 真实可见性通知和句开始观察释放必要对象；不注入音频完成。

const PLAYER_SCENE: PackedScene = preload("res://main-autolysis/systems/dialogue-system/autolysis_dialogue_player.tscn")
const BAR_SCENE: PackedScene = preload("res://main-autolysis/ui/inventory/autolysis_inventory_bar.tscn")
const DEFINITION: AutolysisDialogueDefinition = preload("res://main-autolysis/systems/dialogue-system/chat_0.tres")

class PlaybackContext extends Node:
	signal dialogue_pause_changed(paused: bool)
	func is_dialogue_timing_paused() -> bool:
		return get_tree().paused
	func is_dialogue_local_timing_paused() -> bool:
		return false

var _failures: int = 0
var _records: Array[Dictionary] = []
var _world: Node
var _dialogue: AutolysisDialoguePlayer
var _source: Node
var _mode: String = ""
var _normal_count: int = 0
var _abort_count: int = 0
var _source_was_null: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for mode: String in ["显示释放来源", "显示释放播放器", "句开始释放播放器",
		"显示排队释放播放器", "句开始排队释放播放器", "异常隐藏释放来源"]:
		_mode = mode
		_normal_count = 0
		_abort_count = 0
		_source_was_null = false
		_world = Node.new()
		root.add_child(_world)
		var context: PlaybackContext = PlaybackContext.new()
		_world.add_child(context)
		var bar: AutolysisInventoryBar = BAR_SCENE.instantiate()
		context.add_child(bar)
		_dialogue = PLAYER_SCENE.instantiate()
		context.add_child(_dialogue)
		_dialogue.setup(context, bar)
		_source = Node.new()
		_world.add_child(_source)
		await process_frame
		var definition: AutolysisDialogueDefinition = DEFINITION.duplicate() as AutolysisDialogueDefinition
		definition.line_ids = PackedStringArray(["chat_0_8"])
		definition.voice_streams = [DEFINITION.voice_streams[8]]
		var prepared: Dictionary = _dialogue.prepare_dialogue(definition, _source, _finished, _aborted)
		_check(prepared.ok, "边界变体先成功准备：" + mode)
		var display: Control = _dialogue.get_subtitle().get_node("Display")
		display.visibility_changed.connect(_visibility_changed.bind(display))
		_dialogue.line_started.connect(_line_started)
		var started: bool = _dialogue.start_prepared_dialogue(prepared.token)
		if mode == "异常隐藏释放来源":
			_check(started, "异常隐藏变体真实语音已启动")
			_check(_dialogue.cancel_dialogue(prepared.token, "显式取消触发隐藏观察"), "显式取消成功清理匹配会话")
			_check(_source_was_null, "隐藏观察释放来源后异常接收者取得空来源")
		else:
			_check(not started, "公开启动在释放后安全返回失败：" + mode)
		_check(_normal_count == 0 and _abort_count == 1, "释放变体只异常一次且没有正常完成：" + mode)
		if is_instance_valid(_dialogue):
			_check(_dialogue.get_session_snapshot().token == 0, "仍存活播放器释放匹配播放容量：" + mode)
		await process_frame
		if mode.contains("播放器"):
			_check(not is_instance_valid(_dialogue), "引擎安全释放排队播放器：" + mode)
		_world.free()
		await process_frame
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var argument_index: int = arguments.find("--evidence-dir")
	if argument_index >= 0 and argument_index + 1 < arguments.size():
		var evidence_path: String = arguments[argument_index + 1]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_path))
		var file: FileAccess = FileAccess.open(evidence_path.path_join("可见性边界核验.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"记录": _records, "失败数": _failures, "引擎": Engine.get_version_info()}, "\t"))
	quit(1 if _failures > 0 else 0)


func _visibility_changed(display: Control) -> void:
	if display.visible:
		if _mode == "显示释放来源" and is_instance_valid(_source):
			_source.free()
		elif _mode == "显示释放播放器" and is_instance_valid(_dialogue):
			_dialogue.get_parent().remove_child(_dialogue)
			_dialogue.queue_free()
		elif _mode == "显示排队释放播放器" and is_instance_valid(_dialogue):
			_dialogue.queue_free()
	elif _mode == "异常隐藏释放来源" and is_instance_valid(_source):
		_source.free()


func _line_started(_token: int, _dialogue_id: StringName, _index: int, _text: String) -> void:
	if _mode == "句开始释放播放器" and is_instance_valid(_dialogue):
		_dialogue.get_parent().remove_child(_dialogue)
		_dialogue.queue_free()
	elif _mode == "句开始排队释放播放器" and is_instance_valid(_dialogue):
		_dialogue.queue_free()


func _finished(_token: int, _dialogue_id: StringName, _source_node: Node) -> void:
	_normal_count += 1


func _aborted(_token: int, _dialogue_id: StringName, source_node: Node, reason: String) -> void:
	_abort_count += 1
	_source_was_null = source_node == null
	_check(not reason.is_empty(), "异常接收者取得真实原因：" + _mode)


func _check(condition: bool, description: String) -> void:
	_records.append({"检查": description, "通过": condition})
	if condition:
		print("通过：", description)
	else:
		_failures += 1
		push_error("失败：" + description)
