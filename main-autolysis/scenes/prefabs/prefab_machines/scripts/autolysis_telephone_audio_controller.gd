class_name AutolysisTelephoneAudioController
extends Node
## 听筒音频是可选表现，不参与成对提交或归还许可。

enum ReceiverStage { IDLE, DEFAULT, DIALOGUE, REMOTE_HANG_UP, BUSY }

@export var telephone: AutolysisTelephone
@export var timing_root: Node
## 此定位父节点跟随实际听筒；各三维音源子节点的局部偏移由编辑器配置。
@export var sound_origin: Node3D
@export var action_player: AudioStreamPlayer3D
@export var receiver_player: AudioStreamPlayer3D
@export var pickup_stream: AudioStreamWAV
@export var hangup_stream: AudioStreamWAV
@export var default_stream: AudioStreamWAV
@export var remote_hangup_stream: AudioStreamWAV
@export var busy_stream: AudioStreamWAV

var last_audio_error: String = ""
var _actor: Node3D
var _session: int = 0
var _receiver_stage: ReceiverStage = ReceiverStage.IDLE
var _receiver_serial: int = 0
var _action_serial: int = 0
var _receiver_finished_pending: bool = false
var _receiver_callback: Callable
var _action_callback: Callable
var _receiver_owner: AudioStreamPlayer3D
var _receiver_stream: AudioStreamWAV
var _action_owner: AudioStreamPlayer3D
var _last_taken_actor_id: int = 0
var _last_taken_session: int = 0
var _last_completion_transaction: int = 0
var _last_completion_returning: bool = false
var _last_completion_actor_id: int = 0
var _stream_copies: Dictionary = {}
var _reported_errors: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _live(timing_root):
		timing_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	_sync_sound_origin()


func activate_handset_completion_effects(returning: bool, actor: Node3D, session: int, transaction: int) -> void:
	if not _live(self) or not _live(telephone) or not _live(actor) or session <= 0 or transaction <= 0:
		return
	var actor_id: int = actor.get_instance_id()
	if _last_completion_transaction == transaction and _last_completion_returning == returning and _last_completion_actor_id == actor_id:
		return
	if returning:
		# 来源已归还；按此前成功取下身份拒绝旧归还覆盖后来持有声音。
		if _last_taken_actor_id != actor_id or _last_taken_session != session or telephone.get_holder_session_id() != 0 or telephone.get_holder() != null:
			return
		if _session > 0 and (_actor != actor or _session != session):
			return
	else:
		if not _held_session_valid(actor, session):
			return
		_last_taken_actor_id = actor_id
		_last_taken_session = session
	_last_completion_transaction = transaction
	_last_completion_returning = returning
	_last_completion_actor_id = actor_id
	_stop_receiver()
	_stop_action()
	_bind_actor(actor, session)
	if returning:
		_play_action(hangup_stream, "本人放回听筒声音")
		return
	_play_action(pickup_stream, "本人取下听筒声音")
	var owner_guard: WeakRef = weakref(self)
	var has_call: bool = _live(telephone.call_controller) and telephone.call_controller.has_method("has_pending_call_event") and bool(telephone.call_controller.has_pending_call_event())
	if owner_guard.get_ref() == null or not _live(self) or not _held_session_valid(actor, session):
		return
	if has_call:
		_receiver_stage = ReceiverStage.DIALOGUE
	else:
		_receiver_stage = ReceiverStage.DEFAULT
		_play_receiver(default_stream, true, "无来电默认循环声音")


func begin_dialogue_answer(actor: Node3D, session: int) -> void:
	if _actor != actor or _session != session or not _held_session_valid(actor, session):
		return
	_stop_receiver()
	_receiver_stage = ReceiverStage.DIALOGUE


func play_remote_hang_up(actor: Node3D, session: int) -> void:
	if _actor != actor or _session != session or not _held_session_valid(actor, session) or _receiver_stage != ReceiverStage.DIALOGUE:
		return
	_stop_receiver()
	_receiver_stage = ReceiverStage.REMOTE_HANG_UP
	if not _play_receiver(remote_hangup_stream, false, "对方挂机声音"):
		# 对方挂机表现失效不伪造自然完成，也不决定听筒归还许可。
		_receiver_stage = ReceiverStage.IDLE
		return
	_receiver_callback = _on_remote_hangup_finished.bind(_receiver_serial, actor.get_instance_id(), session)
	receiver_player.finished.connect(_receiver_callback)


func stop_handset_audio(_reason: String) -> void:
	_stop_receiver()
	_stop_action()
	_disconnect_actor()
	_actor = null
	_session = 0
	_sync_sound_origin()


func _process(_delta: float) -> void:
	if _session <= 0:
		return
	if not _live(telephone) or not _live(_actor) or not _timing_valid():
		stop_handset_audio("听筒声音来源、玩家或时序依赖失效")
		return
	_sync_pause()
	_sync_sound_origin()
	if _receiver_stage != ReceiverStage.IDLE and not _held_session_valid(_actor, _session):
		stop_handset_audio("听筒声音原持有会话或必要显示失效")
		return
	if _receiver_stage != ReceiverStage.IDLE and _receiver_stage != ReceiverStage.DIALOGUE and not _receiver_playback_valid():
		_stop_receiver()
		_audio_error("听筒接收声音播放器、资源或时序归属失效")
		return
	if _receiver_finished_pending and not _paused():
		_receiver_finished_pending = false
		_begin_busy(_receiver_serial, _actor.get_instance_id(), _session)


func _held_session_valid(actor: Node3D, session: int) -> bool:
	# 归还预处理暂时停用限位，原成对持有事实直到成功归还才清除。
	if not _live(telephone) or not _live(actor) or session <= 0 or not telephone.owns_handset(actor, session) or not telephone.is_telephone_call_source_valid():
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return _live(inventory) and inventory.is_handset_session_committed(telephone, actor, session) and inventory.is_handset_display_session(telephone, inventory.get_handset_display(), session)


func _bind_actor(actor: Node3D, session: int) -> void:
	_disconnect_actor()
	_actor = actor
	_session = session
	if actor.has_signal("dialogue_pause_changed"):
		actor.connect("dialogue_pause_changed", _on_pause_changed)
	_sync_sound_origin()
	_sync_pause()


func _sync_sound_origin() -> void:
	if not _live(telephone) or not _live(sound_origin) or not is_ancestor_of(sound_origin):
		return
	var anchor: Node3D = telephone.handset_anchor
	if _session > 0 and _live(_actor) and telephone.owns_handset(_actor, _session):
		var inventory: AutolysisInventoryController = _actor.get_node_or_null("InventoryController") as AutolysisInventoryController
		var display: Node3D = inventory.get_handset_display() if _live(inventory) else null
		if _live(display) and inventory.is_handset_display_session(telephone, display, _session):
			anchor = display
	if _live(anchor):
		# 只定位输送父节点；音源自身的可编辑局部变换与空间参数保持不变。
		sound_origin.global_transform = anchor.global_transform


func _disconnect_actor() -> void:
	if is_instance_valid(_actor) and _actor.has_signal("dialogue_pause_changed") and _actor.is_connected("dialogue_pause_changed", _on_pause_changed):
		_actor.disconnect("dialogue_pause_changed", _on_pause_changed)


func _play_action(stream: AudioStreamWAV, description: String) -> void:
	if not _player_valid(action_player):
		_audio_error("听筒单次声音播放器或时序归属失效")
		return
	var copy: AudioStreamWAV = _configured_stream(stream, false, description)
	if copy == null:
		return
	action_player.stream = copy
	_action_owner = action_player
	_action_callback = _on_action_finished.bind(_action_serial, _actor.get_instance_id(), _session)
	action_player.finished.connect(_action_callback)
	action_player.play()


func _play_receiver(stream: AudioStreamWAV, looping: bool, description: String) -> bool:
	if not _player_valid(receiver_player):
		_audio_error("听筒接收声音播放器或时序归属失效")
		return false
	var copy: AudioStreamWAV = _configured_stream(stream, looping, description)
	if copy == null:
		return false
	receiver_player.stream = copy
	_receiver_owner = receiver_player
	_receiver_stream = copy
	receiver_player.play()
	return true


func _configured_stream(stream: AudioStreamWAV, looping: bool, description: String) -> AudioStreamWAV:
	if not is_instance_valid(stream):
		_audio_error("%s资源失效" % description)
		return null
	var key: String = "%s:%s" % [stream.get_instance_id(), looping]
	if _stream_copies.has(key):
		return _stream_copies[key] as AudioStreamWAV
	var copy: AudioStreamWAV = stream.duplicate() as AudioStreamWAV
	if copy == null:
		_audio_error("%s无法建立本机独立资源" % description)
		return null
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
	if looping:
		# 实际长度和采样率只用于完整音频循环端点，不用于业务完成许可。
		if not is_finite(copy.get_length()) or copy.get_length() <= 0.0 or copy.mix_rate <= 0:
			_audio_error("%s没有有效循环采样帧" % description)
			return null
		copy.loop_begin = 0
		copy.loop_end = int(round(copy.get_length() * copy.mix_rate))
		if copy.loop_end <= 0:
			_audio_error("%s没有完整循环采样帧" % description)
			return null
	_stream_copies[key] = copy
	return copy


func _on_remote_hangup_finished(serial: int, actor_id: int, session: int) -> void:
	if serial != _receiver_serial or _receiver_stage != ReceiverStage.REMOTE_HANG_UP or not _live(_actor) or _actor.get_instance_id() != actor_id or _session != session:
		return
	if not _receiver_playback_valid():
		_stop_receiver()
		_audio_error("对方挂机自然完成时声音播放归属或时序依赖失效")
		return
	if not _held_session_valid(_actor, session):
		stop_handset_audio("对方挂机自然完成时原听筒会话失效")
		return
	if _paused():
		_receiver_finished_pending = true
		return
	_begin_busy(serial, actor_id, session)


func _begin_busy(serial: int, actor_id: int, session: int) -> void:
	if serial != _receiver_serial or _receiver_stage != ReceiverStage.REMOTE_HANG_UP or not _live(_actor) or _actor.get_instance_id() != actor_id or _session != session or not _held_session_valid(_actor, session):
		return
	if not _receiver_playback_valid():
		_stop_receiver()
		_audio_error("忙音开始前原挂机声音归属或时序依赖失效")
		return
	_stop_receiver()
	_receiver_stage = ReceiverStage.BUSY
	_play_receiver(busy_stream, true, "对方挂机后的忙音循环")


func _on_action_finished(serial: int, actor_id: int, session: int) -> void:
	if serial != _action_serial or not _live(_actor) or _actor.get_instance_id() != actor_id or _session != session:
		return
	if _receiver_stage == ReceiverStage.IDLE:
		_stop_action()
		_disconnect_actor()
		_actor = null
		_session = 0


func _stop_receiver() -> void:
	_receiver_serial += 1
	_receiver_finished_pending = false
	_receiver_stage = ReceiverStage.IDLE
	if is_instance_valid(_receiver_owner):
		if _receiver_callback.is_valid() and _receiver_owner.finished.is_connected(_receiver_callback):
			_receiver_owner.finished.disconnect(_receiver_callback)
		_receiver_owner.stop()
	_receiver_callback = Callable()
	_receiver_owner = null
	_receiver_stream = null


func _stop_action() -> void:
	_action_serial += 1
	if is_instance_valid(_action_owner):
		if _action_callback.is_valid() and _action_owner.finished.is_connected(_action_callback):
			_action_owner.finished.disconnect(_action_callback)
		_action_owner.stop()
	_action_callback = Callable()
	_action_owner = null


func _timing_valid() -> bool:
	return _live(timing_root) and is_ancestor_of(timing_root)


func _player_valid(player: Variant) -> bool:
	return _timing_valid() and _live(player) and player is AudioStreamPlayer3D and timing_root.is_ancestor_of(player)


func _receiver_playback_valid() -> bool:
	return _player_valid(_receiver_owner) and _receiver_owner == receiver_player and is_instance_valid(_receiver_stream) and _receiver_owner.stream == _receiver_stream


func _paused() -> bool:
	return get_tree().paused or (_live(_actor) and _actor.has_method("is_dialogue_timing_paused") and bool(_actor.call("is_dialogue_timing_paused")))


func _sync_pause() -> void:
	if _live(timing_root):
		var local_pause: bool = _live(_actor) and _actor.has_method("is_dialogue_local_timing_paused") and bool(_actor.call("is_dialogue_local_timing_paused"))
		# 外部场景树暂停与玩家本地菜单暂停叠加，不重新播放当前声音。
		timing_root.process_mode = Node.PROCESS_MODE_DISABLED if local_pause else Node.PROCESS_MODE_PAUSABLE


func _on_pause_changed(_paused_value: bool) -> void:
	_sync_pause()


func _audio_error(reason: String) -> void:
	last_audio_error = reason
	if not _reported_errors.has(reason):
		_reported_errors[reason] = true
		push_warning(reason)


func _exit_tree() -> void:
	stop_handset_audio("听筒音频组件离开场景树")


func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
