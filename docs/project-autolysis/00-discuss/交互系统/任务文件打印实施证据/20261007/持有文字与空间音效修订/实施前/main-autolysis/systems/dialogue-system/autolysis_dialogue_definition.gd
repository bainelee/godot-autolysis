class_name AutolysisDialogueDefinition
extends Resource
## 对话配置只生成本次快照；运行文本唯一来自显式中文翻译资源。

@export var dialogue_id: StringName
@export var line_ids: PackedStringArray = []
@export var voice_streams: Array[AudioStream] = []
@export var chinese_translation: Translation
@export var post_voice_hold_seconds: float = 0.5
@export var subtitle_fade_seconds: float = 0.2


func make_snapshot() -> Dictionary:
	if dialogue_id.is_empty():
		return _failure("对话编号为空")
	if line_ids.is_empty() or line_ids.size() != voice_streams.size():
		return _failure("有序句清单为空或语音数量不匹配")
	if chinese_translation == null:
		return _failure("中文翻译资源缺失")
	if not is_finite(post_voice_hold_seconds) or post_voice_hold_seconds < 0.0:
		return _failure("句后等待必须为有限非负值")
	if not is_finite(subtitle_fade_seconds) or subtitle_fade_seconds <= 0.0:
		return _failure("字幕渐隐必须为有限正值")
	var seen: Dictionary = {}
	var lines: PackedStringArray = []
	var voices: Array[AudioStream] = []
	for index: int in line_ids.size():
		var line_id: String = line_ids[index]
		if line_id.is_empty() or seen.has(line_id):
			return _failure("句编号为空或重复：%s；位置：%d" % [line_id, index])
		seen[line_id] = true
		var text: String = chinese_translation.get_message(StringName(line_id))
		if text.strip_edges().is_empty():
			return _failure("中文译文缺失或为空：%s" % line_id)
		var voice: AudioStream = voice_streams[index]
		if voice == null or voice.instantiate_playback() == null:
			return _failure("语音资源不可播放：%s" % line_id)
		if _is_looping(voice):
			return _failure("逐句语音不能循环：%s；资源：%s" % [line_id, voice.resource_path])
		lines.append(text)
		voices.append(voice)
	return {
		"ok": true,
		"reason": "",
		"dialogue_id": dialogue_id,
		"line_ids": line_ids.duplicate(),
		"lines": lines,
		"voices": voices,
		"post_voice_hold_seconds": post_voice_hold_seconds,
		"subtitle_fade_seconds": subtitle_fade_seconds,
	}


static func _is_looping(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).loop
	return false


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": "对话：%s；%s" % [dialogue_id, reason]}
