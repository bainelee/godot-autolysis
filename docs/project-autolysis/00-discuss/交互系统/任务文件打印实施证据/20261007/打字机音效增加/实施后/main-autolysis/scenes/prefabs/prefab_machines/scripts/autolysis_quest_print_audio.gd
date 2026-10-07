class_name AutolysisQuestPrintAudio
extends Node3D
## 只拥有打印声音表现；声音失效不会改变机械完成、纸张来源或取纸许可。

const SILENCE_SECONDS: Array[float] = [0.25, 0.4]

@export var typing_player: AudioStreamPlayer3D
@export var ding_player: AudioStreamPlayer3D
@export var head_return_player: AudioStreamPlayer3D
@export var axis_return_player: AudioStreamPlayer3D
@export var typing_streams: Array[AudioStreamWAV] = [
	preload("res://main-autolysis/assets/audio/sound_fx/machine/typewriter/typewriter_single_type_0.wav"),
	preload("res://main-autolysis/assets/audio/sound_fx/machine/typewriter/typewriter_single_type_1.wav"),
	preload("res://main-autolysis/assets/audio/sound_fx/machine/typewriter/typewriter_single_type_2.wav"),
	preload("res://main-autolysis/assets/audio/sound_fx/machine/typewriter/typewriter_single_type_3.wav"),
]
@export var ding_stream: AudioStreamWAV = preload("res://main-autolysis/assets/audio/sound_fx/machine/typewriter/typewriter_ding_0.wav")
@export var head_return_stream: AudioStreamWAV = preload("res://main-autolysis/assets/audio/sound_fx/machine/typewriter/typewriter_print_main_back.wav")
@export var axis_return_stream: AudioStreamWAV = preload("res://main-autolysis/assets/audio/sound_fx/machine/typewriter/typewriter_axis_back_0.wav")

var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _typing_active: bool = false
var _generation: int = 0
var _cue_generation: int = 0
var _choice: int = -1
var _gap: Tween
var _gap_seconds: float = 0.0
var _next_pending: bool = false
var _paused: bool = false
var _typing_source: AudioStreamPlayer3D
var _typing_stream: AudioStreamWAV
var _typing_finished: Callable
var _axis_source: AudioStreamPlayer3D
var _axis_stream: AudioStreamWAV
var _events: Array[Dictionary] = []
var _warnings: Dictionary = {}


func _ready() -> void:
	_random.randomize()


func begin_action(phase: StringName) -> void:
	_cue_generation += 1
	var cue: int = _cue_generation
	match phase:
		&"first_descent":
			_events.clear()
		&"print_line":
			_stop_typing()
			if not _player_valid(typing_player):
				_warn("逐行敲击播放器失效；停止敲击表现")
				return
			_typing_active = true
			_typing_source = typing_player
			_typing_finished = _on_typing_finished.bind(_generation)
			_typing_source.finished.connect(_typing_finished)
			_choose_typing_step(_generation)
		&"first_left", &"return_left", &"center", &"cancel_center":
			if _play_once(head_return_player, head_return_stream, cue):
				_record(&"head_return", -1, 0.0, phase)
		&"axis_reset":
			_stop_axis()
			if not _player_valid(axis_return_player) or not is_instance_valid(axis_return_stream):
				_warn("横轴复位声音配置失效；停止对应声音表现")
				return
			_axis_stream = axis_return_stream.duplicate() as AudioStreamWAV
			# 实际采样数仅用于完整音频循环；机械完成仍由本次动作自然完成决定。
			_axis_stream.loop_begin = 0
			_axis_stream.loop_end = int(round(_axis_stream.get_length() * _axis_stream.mix_rate))
			if _axis_stream.loop_end <= 0:
				_axis_stream = null
				_warn("横轴复位音频缺少有效采样；停止对应声音表现")
				return
			_axis_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			_axis_source = axis_return_player
			var player: AudioStreamPlayer3D = _axis_source
			var stream: AudioStreamWAV = _axis_stream
			player.stream = stream
			if not is_instance_valid(self) or is_queued_for_deletion() or cue != _cue_generation or not _player_valid(player) or player != _axis_source or player.stream != stream:
				return
			player.play()
			player.stream_paused = _paused
			_record(&"axis_return_started", -1, 0.0, phase)


func finish_action(phase: StringName) -> void:
	var cue: int = _cue_generation
	match phase:
		&"print_line":
			_stop_typing()
			if _play_once(ding_player, ding_stream, cue):
				_record(&"ding", -1, 0.0, phase)
		&"axis_reset":
			_stop_axis()


func _choose_typing_step(generation: int) -> void:
	if generation != _generation or not _typing_active:
		return
	if _paused:
		_next_pending = true
		return
	if not _player_valid(_typing_source) or _typing_source != typing_player:
		_stop_typing()
		return
	_next_pending = false
	_choice = _random.randi_range(0, 5)
	_typing_stream = null
	_gap_seconds = 0.0
	if _choice < 4:
		if _choice >= typing_streams.size() or not is_instance_valid(typing_streams[_choice]):
			_warn("敲击音频%d失效；停止敲击表现" % _choice)
			_stop_typing()
			return
		_typing_stream = typing_streams[_choice].duplicate() as AudioStreamWAV
		_typing_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		var player: AudioStreamPlayer3D = _typing_source
		var stream: AudioStreamWAV = _typing_stream
		player.stream = stream
		if not is_instance_valid(self) or is_queued_for_deletion() or generation != _generation or not _typing_active or not _player_valid(player) or player != _typing_source or player.stream != stream:
			return
		player.play()
		player.stream_paused = _paused
	else:
		_gap_seconds = SILENCE_SECONDS[_choice - 4]
		_gap = create_tween()
		_gap.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_gap.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
		_gap.tween_interval(_gap_seconds)
		_gap.finished.connect(_on_gap_finished.bind(generation))
	_record(&"typing_choice", _choice, _gap_seconds)


func _on_typing_finished(generation: int) -> void:
	_choose_typing_step(generation)


func _on_gap_finished(generation: int) -> void:
	if generation != _generation:
		return
	_gap = null
	_choose_typing_step(generation)


func _stop_typing() -> void:
	_generation += 1
	if is_instance_valid(_gap):
		_gap.kill()
	_gap = null
	if is_instance_valid(_typing_source):
		if _typing_finished.is_valid() and _typing_source.finished.is_connected(_typing_finished):
			_typing_source.finished.disconnect(_typing_finished)
		_typing_source.stop()
	if _typing_active:
		_record(&"typing_stopped")
	_typing_active = false
	_typing_source = null
	_typing_stream = null
	_typing_finished = Callable()
	_next_pending = false
	_gap_seconds = 0.0
	_choice = -1


func _stop_axis() -> void:
	if is_instance_valid(_axis_source):
		_axis_source.stop()
	if _axis_stream != null:
		_record(&"axis_return_stopped")
	_axis_source = null
	_axis_stream = null


func _play_once(player: Variant, source: AudioStreamWAV, cue: int) -> bool:
	if not _player_valid(player) or not is_instance_valid(source):
		_warn("打印单次声音播放器或资源失效；停止对应声音表现")
		return false
	var stream: AudioStreamWAV = source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	player.stop()
	player.stream = stream
	if not is_instance_valid(self) or is_queued_for_deletion() or cue != _cue_generation or not _player_valid(player) or player.stream != stream:
		return false
	player.play()
	player.stream_paused = _paused
	return true


func set_paused(value: bool) -> void:
	_paused = value
	for player: Variant in [typing_player, ding_player, head_return_player, axis_return_player]:
		if is_instance_valid(player):
			player.stream_paused = value


func stop_all() -> void:
	_cue_generation += 1
	_stop_typing()
	_stop_axis()
	for player: Variant in [typing_player, ding_player, head_return_player, axis_return_player]:
		if is_instance_valid(player):
			player.stop()


func _process(_delta: float) -> void:
	if _typing_active and (not _player_valid(_typing_source) or _typing_source != typing_player or (_typing_stream != null and _typing_source.stream != _typing_stream)):
		_stop_typing()
		_warn("运行中敲击播放来源失效；停止敲击表现")
	if _axis_stream != null and (not _player_valid(_axis_source) or _axis_source != axis_return_player or _axis_source.stream != _axis_stream):
		_stop_axis()
		_warn("运行中横轴声音来源失效；停止对应声音表现")
	if not _paused and _next_pending:
		_choose_typing_step(_generation)


func get_audio_snapshot() -> Dictionary:
	var remaining: float = maxf(0.0, _gap_seconds - _gap.get_total_elapsed_time()) if is_instance_valid(_gap) else 0.0
	return {"events": _events.duplicate(true), "typing_active": _typing_active, "choice": _choice, "gap_remaining": remaining, "paused": _paused}


func _record(event: StringName, choice: int = -1, seconds: float = 0.0, phase: StringName = &"") -> void:
	_events.append({"event": event, "choice": choice, "seconds": seconds, "phase": phase, "physics_frame": Engine.get_physics_frames(), "ticks_usec": Time.get_ticks_usec()})


func _player_valid(player: Variant) -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and not player.is_queued_for_deletion() and is_ancestor_of(player)


func _warn(reason: String) -> void:
	if not _warnings.has(reason):
		_warnings[reason] = true
		push_warning(reason)


func _exit_tree() -> void:
	stop_all()
