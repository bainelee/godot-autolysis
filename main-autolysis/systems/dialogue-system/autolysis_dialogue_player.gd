class_name AutolysisDialoguePlayer
extends Node
## 会话所有者始终处理；音频、计时和补间只在同一可暂停时序树推进。

signal dialogue_finished(token: int, dialogue_id: StringName, source: Node)
signal dialogue_aborted(token: int, dialogue_id: StringName, source: Node, reason: String)
signal line_started(token: int, dialogue_id: StringName, index: int, text: String)
signal stage_changed(token: int, stage: StringName, index: int)

const IDLE: StringName = &"idle"
const PREPARED: StringName = &"prepared"
const START_PENDING: StringName = &"start_pending"
const VOICE: StringName = &"voice"
const HOLD: StringName = &"hold"
const FADE: StringName = &"fade"
const FINISHING: StringName = &"finishing"
const ABORTING: StringName = &"aborting"

var _player: Node
var _inventory_bar: CanvasLayer
var _next_token: int = 0
var _token: int = 0
var _stage: StringName = IDLE
var _index: int = -1
var _source: Node
var _source_id: int = 0
var _snapshot: Dictionary = {}
var _finished_callback: Callable
var _aborted_callback: Callable
var _voice_callback: Callable
var _hold_callback: Callable
var _source_exit_callback: Callable
var _fade_tween: Tween
var _completion_pending: StringName
var _last_result: Dictionary = {}

@onready var _timing: Node = $Timing
@onready var _voice: AudioStreamPlayer = $Timing/Voice
@onready var _hold: Timer = $Timing/Hold
@onready var _subtitle: AutolysisDialogueSubtitle = $Subtitle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(_inventory_bar):
		_subtitle.setup(_inventory_bar)
	_sync_pause()


func setup(player: Node, inventory_bar: CanvasLayer) -> void:
	if is_instance_valid(_player) and _player.has_signal("dialogue_pause_changed") \
			and _player.is_connected("dialogue_pause_changed", _on_pause_changed):
		_player.disconnect("dialogue_pause_changed", _on_pause_changed)
	if _token != 0:
		cancel_dialogue(_token, "播放上下文重新设置")
	_player = player
	_inventory_bar = inventory_bar
	if is_instance_valid(_player) and _player.has_signal("dialogue_pause_changed"):
		_player.connect("dialogue_pause_changed", _on_pause_changed)
	if is_node_ready() and is_instance_valid(_subtitle):
		_subtitle.setup(inventory_bar)
	_sync_pause()


func prepare_dialogue(definition: AutolysisDialogueDefinition, source: Node,
		finished_callback: Callable, aborted_callback: Callable) -> Dictionary:
	if _token != 0:
		return {"ok": false, "token": 0, "reason": "播放器忙碌", "busy": true}
	var dependency_reason: String = _dependency_reason()
	if not dependency_reason.is_empty():
		return _prepare_failure(dependency_reason)
	if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
		return _prepare_failure("对话来源失效")
	if not _receiver_available(finished_callback) or not _receiver_available(aborted_callback):
		return _prepare_failure("唯一业务完成或异常接收者失效")
	if definition == null:
		return _prepare_failure("对话定义缺失")
	var snapshot: Dictionary = definition.make_snapshot()
	if not snapshot.get("ok", false):
		return _prepare_failure(snapshot.get("reason", "对话配置失败"))
	_next_token += 1
	_token = _next_token
	_source = source
	_source_id = source.get_instance_id()
	_snapshot = snapshot
	_finished_callback = finished_callback
	_aborted_callback = aborted_callback
	_index = 0
	_stage = PREPARED
	_completion_pending = &""
	_source_exit_callback = _on_source_exiting.bind(_token)
	_source.tree_exiting.connect(_source_exit_callback)
	var prepared_token: int = _token
	var owner_guard: WeakRef = weakref(self)
	if not _subtitle.prepare_line(prepared_token, _index, _snapshot["lines"][_index]):
		if owner_guard.get_ref() == null:
			return {"ok": false, "token": 0, "reason": "字幕准备期间播放器被释放", "busy": false}
		cancel_dialogue(prepared_token, "字幕准备依赖失效")
		return _prepare_failure("字幕准备依赖失效")
	if owner_guard.get_ref() == null:
		return {"ok": false, "token": 0, "reason": "字幕准备期间播放器被释放", "busy": false}
	if _token != prepared_token or not _check_session_dependencies():
		return {"ok": false, "token": 0, "reason": "字幕准备期间会话失效", "busy": false}
	return {"ok": true, "token": prepared_token, "reason": "", "busy": false}


func has_prepared_dialogue(token: int, source: Node) -> bool:
	return token > 0 and token == _token and is_instance_valid(source) and source == _source \
		and _stage != IDLE and _stage != FINISHING and _stage != ABORTING \
		and _dependency_reason().is_empty() and source.is_inside_tree() and not source.is_queued_for_deletion() \
		and _receiver_available(_finished_callback) and _receiver_available(_aborted_callback)


func start_prepared_dialogue(token: int) -> bool:
	if token <= 0 or token != _token or (_stage != PREPARED and _stage != START_PENDING):
		return false
	if not _check_session_dependencies():
		return false
	_stage = START_PENDING
	_sync_pause()
	var owner_guard: WeakRef = weakref(self)
	if not _is_paused():
		_begin_line(token, _index)
	if owner_guard.get_ref() == null:
		return false
	return token == _token and _stage != ABORTING


func cancel_dialogue(token: int, reason: String) -> bool:
	if token <= 0 or token != _token or _stage == FINISHING or _stage == ABORTING:
		return false
	_abort(token, reason if not reason.is_empty() else "显式取消")
	return true


func get_session_snapshot() -> Dictionary:
	var subtitle: Dictionary = _subtitle.get_layout_snapshot() if is_instance_valid(_subtitle) else {}
	return {
		"token": _token,
		"dialogue_id": _snapshot.get("dialogue_id", &""),
		"source_id": _source_id,
		"index": _index,
		"stage": _stage,
		"paused": _is_paused(),
		"completion_pending": _completion_pending,
		"audio_position": _voice.get_playback_position() if is_instance_valid(_voice) else 0.0,
		"audio_playing": is_instance_valid(_voice) and _voice.playing,
		"hold_remaining": _hold.time_left if is_instance_valid(_hold) else 0.0,
		"subtitle_alpha": subtitle.get("alpha", 0.0),
		"subtitle": subtitle,
		"last_result": _last_result.duplicate(true),
	}


func get_subtitle() -> AutolysisDialogueSubtitle:
	return _subtitle if is_instance_valid(_subtitle) else null


func _process(_delta: float) -> void:
	_sync_pause()
	if _token == 0 or _stage == FINISHING or _stage == ABORTING:
		return
	if not _check_session_dependencies() or _is_paused():
		return
	if _stage == START_PENDING:
		_begin_line(_token, _index)
	elif not _completion_pending.is_empty():
		var completed_stage: StringName = _completion_pending
		_completion_pending = &""
		_advance_completed_stage(completed_stage, _token, _index)


func _exit_tree() -> void:
	if _token != 0 and _stage != FINISHING and _stage != ABORTING:
		_abort(_token, "对话播放器离开场景树")
	if is_instance_valid(_player) and _player.has_signal("dialogue_pause_changed") \
			and _player.is_connected("dialogue_pause_changed", _on_pause_changed):
		_player.disconnect("dialogue_pause_changed", _on_pause_changed)


func _dependency_reason() -> String:
	if not is_inside_tree() or not is_node_ready() or is_queued_for_deletion():
		return "对话播放器未就绪"
	if not is_instance_valid(_player) or not _player.is_inside_tree() \
			or _player.is_queued_for_deletion() or not _player.has_method("is_dialogue_timing_paused"):
		return "玩家播放上下文失效"
	if not is_instance_valid(_timing) or not _timing.is_inside_tree() or _timing.is_queued_for_deletion():
		return "播放时序依赖失效"
	if not is_instance_valid(_voice) or not _voice.is_inside_tree() or _voice.is_queued_for_deletion():
		return "语音播放器失效"
	if not is_instance_valid(_hold) or not _hold.is_inside_tree() or _hold.is_queued_for_deletion():
		return "句后计时器失效"
	if not is_instance_valid(_subtitle) or _subtitle.is_queued_for_deletion() or not _subtitle.is_available():
		return "字幕必要依赖失效"
	var subtitle_error: String = _subtitle.get_configuration_error()
	if not subtitle_error.is_empty():
		return subtitle_error
	return ""


func _check_session_dependencies() -> bool:
	var reason: String = _dependency_reason()
	if reason.is_empty() and (not is_instance_valid(_source) or not _source.is_inside_tree() \
			or _source.is_queued_for_deletion()):
		reason = "对话来源失效"
	if reason.is_empty() and (not _receiver_available(_finished_callback) or not _receiver_available(_aborted_callback)):
		reason = "业务接收者失效"
	if not reason.is_empty():
		_abort(_token, reason)
		return false
	return true


func _is_paused() -> bool:
	if is_inside_tree() and get_tree().paused:
		return true
	return is_instance_valid(_player) and _player.has_method("is_dialogue_timing_paused") \
		and bool(_player.call("is_dialogue_timing_paused"))


func _sync_pause() -> void:
	var local_paused: bool = false
	if is_instance_valid(_player):
		if _player.has_method("is_dialogue_local_timing_paused"):
			local_paused = bool(_player.call("is_dialogue_local_timing_paused"))
		elif _player.has_method("is_dialogue_timing_paused"):
			local_paused = bool(_player.call("is_dialogue_timing_paused"))
	if is_instance_valid(_timing):
		# 场景树暂停由可暂停模式承担；菜单标记也禁用整棵时序子树。
		_timing.process_mode = Node.PROCESS_MODE_DISABLED if local_paused else Node.PROCESS_MODE_PAUSABLE


func _on_pause_changed(_paused: bool) -> void:
	_sync_pause()


func _begin_line(token: int, index: int) -> void:
	if token != _token or index != _index or _is_paused() or not _check_session_dependencies():
		return
	var text: String = _snapshot["lines"][index]
	var owner_guard: WeakRef = weakref(self)
	var prepared: bool = _subtitle.prepare_line(token, index, text)
	if owner_guard.get_ref() == null:
		return
	if token != _token or index != _index:
		return
	if not _check_session_dependencies():
		return
	var shown: bool = prepared and _subtitle.show_prepared_line(token, index)
	if owner_guard.get_ref() == null:
		return
	if token != _token or index != _index:
		return
	if not shown:
		_abort(token, "字幕条目开始依赖失效")
		return
	if not _check_session_dependencies():
		return
	_disconnect_voice()
	_voice.stream = _snapshot["voices"][index]
	_voice_callback = _on_voice_finished.bind(token, index)
	_voice.finished.connect(_voice_callback, CONNECT_ONE_SHOT)
	_stage = VOICE
	_voice.play()
	# 外部观察发生在字幕和语音都已经开始之后。
	line_started.emit(token, _snapshot["dialogue_id"], index, text)
	if owner_guard.get_ref() == null:
		return
	if not _matches(token, index, VOICE) or not _check_session_dependencies():
		return
	if _matches(token, index, VOICE):
		stage_changed.emit(token, VOICE, index)


func _on_voice_finished(token: int, index: int) -> void:
	_on_natural_completion(VOICE, token, index)


func _on_hold_finished(token: int, index: int) -> void:
	_on_natural_completion(HOLD, token, index)


func _on_fade_finished(token: int, index: int) -> void:
	_on_natural_completion(FADE, token, index)


func _on_natural_completion(stage: StringName, token: int, index: int) -> void:
	if not _matches(token, index, stage) or not _completion_pending.is_empty():
		return
	if not _check_session_dependencies():
		return
	if _is_paused():
		_completion_pending = stage
		return
	_advance_completed_stage(stage, token, index)


func _advance_completed_stage(stage: StringName, token: int, index: int) -> void:
	if not _matches(token, index, stage) or _is_paused() or not _check_session_dependencies():
		return
	match stage:
		VOICE:
			_stage = HOLD
			var seconds: float = _snapshot["post_voice_hold_seconds"]
			if seconds == 0.0:
				_begin_fade(token, index)
			else:
				_disconnect_hold()
				_hold_callback = _on_hold_finished.bind(token, index)
				_hold.timeout.connect(_hold_callback, CONNECT_ONE_SHOT)
				_hold.start(seconds)
				stage_changed.emit(token, HOLD, index)
		HOLD:
			_begin_fade(token, index)
		FADE:
			var owner_guard: WeakRef = weakref(self)
			_subtitle.hide_line(token)
			if owner_guard.get_ref() == null or not _matches(token, index, FADE):
				return
			_fade_tween = null
			if index + 1 >= _snapshot["lines"].size():
				_finish(token)
			else:
				_index += 1
				_stage = START_PENDING
				_begin_line(token, _index)


func _begin_fade(token: int, index: int) -> void:
	if not _matches(token, index, HOLD) or _is_paused():
		return
	var target: Control = _subtitle.get_fade_target()
	if target == null:
		_abort(token, "字幕渐隐目标失效")
		return
	_stage = FADE
	_fade_tween = _timing.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_fade_tween.tween_property(target, "modulate:a", 0.0, _snapshot["subtitle_fade_seconds"])
	_fade_tween.finished.connect(_on_fade_finished.bind(token, index), CONNECT_ONE_SHOT)
	stage_changed.emit(token, FADE, index)


func _finish(token: int) -> void:
	if token != _token or _stage != FADE:
		return
	_stage = FINISHING
	_completion_pending = &""
	var dialogue_id: StringName = _snapshot["dialogue_id"]
	var source: Node = _source
	var callback: Callable = _finished_callback
	_last_result = _result("正常完成", "")
	_disconnect_source()
	var owner_guard: WeakRef = weakref(self)
	if callback.is_valid():
		callback.call(token, dialogue_id, source if is_instance_valid(source) else null)
	if owner_guard.get_ref() == null:
		return
	# 终态已固定；回调内取消和新准备均不得覆盖本次结果。
	dialogue_finished.emit(token, dialogue_id, source if is_instance_valid(source) else null)
	if owner_guard.get_ref() != null:
		_release_session(token)


func _abort(token: int, reason: String) -> void:
	if token <= 0 or token != _token or _stage == FINISHING or _stage == ABORTING:
		return
	_stage = ABORTING
	_completion_pending = &""
	var dialogue_id: StringName = _snapshot.get("dialogue_id", &"")
	var source: Node = _source if is_instance_valid(_source) else null
	var callback: Callable = _aborted_callback
	var owner_guard: WeakRef = weakref(self)
	_last_result = _result("异常终止", reason)
	_disconnect_voice()
	_disconnect_hold()
	_disconnect_source()
	if is_instance_valid(_voice):
		_voice.stop()
		_voice.stream = null
	if is_instance_valid(_hold):
		_hold.stop()
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if is_instance_valid(_subtitle):
		_subtitle.hide_line(token)
	if owner_guard.get_ref() == null:
		if callback.is_valid():
			callback.call(token, dialogue_id, source if is_instance_valid(source) else null, reason)
		return
	if callback.is_valid():
		callback.call(token, dialogue_id, source if is_instance_valid(source) else null, reason)
	if owner_guard.get_ref() == null:
		return
	dialogue_aborted.emit(token, dialogue_id, source if is_instance_valid(source) else null, reason)
	if owner_guard.get_ref() != null:
		_release_session(token)


func _result(outcome: String, reason: String) -> Dictionary:
	return {"token": _token, "dialogue_id": _snapshot.get("dialogue_id", &""),
		"source_id": _source_id, "index": _index, "outcome": outcome, "reason": reason}


func _release_session(token: int) -> void:
	if token != _token:
		return
	_disconnect_voice()
	_disconnect_hold()
	_disconnect_source()
	if is_instance_valid(_voice):
		_voice.stream = null
	_token = 0
	_stage = IDLE
	_index = -1
	_source = null
	_source_id = 0
	_snapshot = {}
	_finished_callback = Callable()
	_aborted_callback = Callable()


func _disconnect_voice() -> void:
	if is_instance_valid(_voice) and _voice_callback.is_valid() and _voice.finished.is_connected(_voice_callback):
		_voice.finished.disconnect(_voice_callback)
	_voice_callback = Callable()


func _disconnect_hold() -> void:
	if is_instance_valid(_hold) and _hold_callback.is_valid() and _hold.timeout.is_connected(_hold_callback):
		_hold.timeout.disconnect(_hold_callback)
	_hold_callback = Callable()


func _disconnect_source() -> void:
	if is_instance_valid(_source) and _source_exit_callback.is_valid() \
			and _source.tree_exiting.is_connected(_source_exit_callback):
		_source.tree_exiting.disconnect(_source_exit_callback)
	_source_exit_callback = Callable()


func _matches(token: int, index: int, stage: StringName) -> bool:
	return token > 0 and token == _token and index == _index and stage == _stage


func _on_source_exiting(token: int) -> void:
	_abort(token, "对话来源离开场景树")


func _prepare_failure(reason: String) -> Dictionary:
	return {"ok": false, "token": 0, "reason": reason, "busy": false}


static func _receiver_available(callback: Callable) -> bool:
	if not callback.is_valid():
		return false
	var receiver: Object = callback.get_object()
	if receiver is Node:
		var node: Node = receiver as Node
		return node.is_inside_tree() and not node.is_queued_for_deletion()
	return is_instance_valid(receiver)
