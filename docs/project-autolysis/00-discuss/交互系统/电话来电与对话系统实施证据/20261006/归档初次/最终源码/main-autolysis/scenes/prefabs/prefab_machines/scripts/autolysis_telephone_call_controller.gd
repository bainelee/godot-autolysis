class_name AutolysisTelephoneCallController
extends Node3D
## 来电业务只由成对提交推进。时序子树冻结进度，拥有者继续清理来源。

enum Stage { IDLE, RESOLVING, WAIT_RETURN, DELAYED, ACTIVE, TALKING, COMPLETED, ABORTED }

@export var telephone: AutolysisTelephone
@export var timing_root: Node
@export var deferred_timer: Timer
@export var ring_player: AudioStreamPlayer3D
@export var ring_stream: AudioStreamWAV
@export var deferred_ring_delay: float = 2.0

var last_abort_record: Dictionary = {}
var last_ring_error: String = ""
var _stage: Stage = Stage.IDLE
var _call_serial: int = 0
var _wait_serial: int = 0
var _timer_serial: int = 0
var _delay_expired: bool = false
var _definition: Resource
var _context: Node
var _player: Node
var _playback_token: int = 0
var _prepared_actor: Node3D
var _prepared_transaction: int = 0
var _holder: Node3D
var _holder_session: int = 0
var _pending_effects: bool = false
var _successful_hold_seen: bool = false
var _ring_copy: AudioStreamWAV
var _delay_callback: Callable
var _handset_display: Node3D
var _source_id: int = 0
var _source_path: String = ""
var _business_snapshot: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _live(timing_root):
		timing_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	if _live(deferred_timer):
		deferred_timer.one_shot = true


func request_call(definition: Resource, context: Node) -> bool:
	if _stage != Stage.IDLE or not _live(telephone) or not telephone.is_telephone_call_source_valid() or not is_instance_valid(definition) or not _live(context):
		return false
	var playback: Variant = context.get("dialogue_player")
	if not _live(playback) or not context.has_method("is_dialogue_timing_paused") or not context.has_method("is_dialogue_local_timing_paused") or not context.has_signal("dialogue_pause_changed"):
		return false
	if not _live(timing_root) or not _live(deferred_timer) or not timing_root.is_ancestor_of(deferred_timer) or not is_finite(deferred_ring_delay) or deferred_ring_delay < 0.0:
		return false
	_call_serial += 1
	_source_id = telephone.get_instance_id()
	_source_path = str(telephone.get_path())
	_definition = definition
	_context = context
	_player = playback
	context.dialogue_pause_changed.connect(_on_pause_changed)
	_sync_pause()
	_successful_hold_seen = telephone.has_committed_handset_hold()
	_stage = Stage.WAIT_RETURN if _successful_hold_seen else Stage.RESOLVING
	_resolve_request()
	return true


func is_handset_return_blocked(actor: Node3D, session: int) -> bool:
	return _stage == Stage.TALKING and session > 0 and _holder == actor and _holder_session == session and _playback_token > 0


func prepare_handset_business_transfer(actor: Node3D, returning: bool, session: int, transaction: int) -> bool:
	if returning:
		return not is_handset_return_blocked(actor, session)
	if _stage != Stage.ACTIVE:
		return true
	if not _definition is AutolysisDialogueDefinition:
		cancel_call("接听准备时对话定义资源类型无效")
		return false
	if _playback_token > 0 or not _live(_player) or not _live(_context):
		if not _live(_player) or not _live(_context):
			cancel_call("接听准备时播放上下文失效")
		return false
	var serial: int = _call_serial
	var prepared: Dictionary = _player.prepare_dialogue(_definition, telephone, _on_dialogue_finished.bind(serial), _on_dialogue_aborted.bind(serial))
	if not _live(self) or _call_serial != serial or _stage != Stage.ACTIVE:
		if _live(_player) and prepared.get("ok", false):
			_player.cancel_dialogue(int(prepared.get("token", 0)), "来电接听准备期间来源失效")
		return false
	if not prepared.get("ok", false):
		if not prepared.get("busy", false):
			cancel_call("接听准备失败：%s" % str(prepared.get("reason", "缺少失败原因")))
		return false
	_playback_token = int(prepared["token"])
	_prepared_actor = actor
	_prepared_transaction = transaction
	return _playback_token > 0


func cancel_handset_business_preparation(actor: Node3D, transaction: int) -> void:
	if _stage != Stage.ACTIVE or _prepared_actor != actor or _prepared_transaction != transaction or transaction <= 0:
		return
	var playback: int = _playback_token
	_playback_token = 0
	_prepared_actor = null
	_prepared_transaction = 0
	if _live(_player) and playback > 0:
		_player.cancel_dialogue(playback, "听筒取下事务取消或回滚")


func commit_handset_business_completion(returning: bool, actor: Node3D, session: int, transaction: int) -> bool:
	# 此处不发观察、不启动声音；先完整验证，再一次改变业务事实。
	if not _live(telephone) or not _live(actor) or session <= 0 or transaction <= 0:
		return false
	if returning:
		if is_handset_return_blocked(actor, session):
			return false
		_remember_business_completion(actor, transaction)
		if _stage == Stage.WAIT_RETURN or (_stage == Stage.RESOLVING and _successful_hold_seen):
			_wait_serial += 1
			_delay_expired = false
			_stage = Stage.DELAYED
			_pending_effects = true
		return true
	if _stage == Stage.ACTIVE:
		if _prepared_actor != actor or _prepared_transaction != transaction or not _live(_player) or not _player.has_prepared_dialogue(_playback_token, telephone):
			return false
		_remember_business_completion(actor, transaction)
		_holder = actor
		_holder_session = session
		_stage = Stage.TALKING
		_pending_effects = true
		return true
	_remember_business_completion(actor, transaction)
	if _stage == Stage.DELAYED or _stage == Stage.RESOLVING:
		_wait_serial += 1
		_delay_expired = false
		_successful_hold_seen = true
		_stage = Stage.WAIT_RETURN
		_pending_effects = false
	return true


func rollback_handset_business_completion(actor: Node3D, transaction: int) -> void:
	if _business_snapshot.is_empty() or _business_snapshot["actor"] != actor or _business_snapshot["transaction"] != transaction:
		return
	_stage = _business_snapshot["stage"]
	_wait_serial = _business_snapshot["wait_serial"]
	_delay_expired = _business_snapshot["delay_expired"]
	_successful_hold_seen = _business_snapshot["successful_hold_seen"]
	_pending_effects = _business_snapshot["pending_effects"]
	_holder = _business_snapshot["holder"]
	_holder_session = _business_snapshot["holder_session"]
	_business_snapshot.clear()


func _remember_business_completion(actor: Node3D, transaction: int) -> void:
	_business_snapshot = {"actor": actor, "transaction": transaction, "stage": _stage, "wait_serial": _wait_serial, "delay_expired": _delay_expired, "successful_hold_seen": _successful_hold_seen, "pending_effects": _pending_effects, "holder": _holder, "holder_session": _holder_session}


func activate_handset_completion_effects(returning: bool, actor: Node3D, session: int, transaction: int) -> void:
	if _business_snapshot.get("actor") == actor and int(_business_snapshot.get("transaction", 0)) == transaction:
		_business_snapshot.clear()
	if returning:
		if _stage == Stage.DELAYED and _pending_effects:
			_start_pending_effects()
		return
	if _stage == Stage.WAIT_RETURN and _live(deferred_timer):
		_stop_deferred_timer()
	if _stage == Stage.TALKING and _holder == actor and _holder_session == session and _prepared_transaction == transaction:
		_stop_ring()
		if not _watch_handset_display():
			return
		_start_pending_effects()


func cancel_call(reason: String) -> void:
	if _stage == Stage.IDLE or _stage == Stage.COMPLETED or _stage == Stage.ABORTED:
		return
	var playback: int = _playback_token
	var playback_snapshot: Dictionary = _player.get_session_snapshot() if _live(_player) and playback > 0 else {}
	var current_line: int = int(playback_snapshot.get("index", -1)) if _stage == Stage.TALKING and not _pending_effects and int(playback_snapshot.get("token", 0)) == playback else -1
	last_abort_record = {"来电序号": _call_serial, "播放令牌": playback, "对话编号": str(_definition.get("dialogue_id")) if _definition is AutolysisDialogueDefinition else "", "当前句索引": current_line, "来源": _source_path, "来源实例身份": _source_id, "原持有会话": _holder_session, "原因": reason}
	_stage = Stage.ABORTED
	_business_snapshot.clear()
	_disconnect_handset_display()
	_wait_serial += 1
	_playback_token = 0
	_holder = null
	_holder_session = 0
	_prepared_actor = null
	_prepared_transaction = 0
	_pending_effects = false
	_delay_expired = false
	_stop_deferred_timer()
	_stop_ring()
	if _live(_player) and playback > 0:
		_player.cancel_dialogue(playback, reason)
	print("电话来电异常终止：", JSON.stringify(last_abort_record))


func get_call_snapshot() -> Dictionary:
	return {"stage": _stage, "call_serial": _call_serial, "wait_serial": _wait_serial, "delay_expired": _delay_expired, "delay_remaining": deferred_timer.time_left if _live(deferred_timer) else 0.0, "playback_token": _playback_token, "holder_session": _holder_session, "pending_effects": _pending_effects}


func _process(_delta: float) -> void:
	if _stage == Stage.IDLE or _stage == Stage.COMPLETED or _stage == Stage.ABORTED:
		return
	if not _live(telephone) or not telephone.is_telephone_call_source_valid() or not _live(_context) or not _live(_player) or not _live(timing_root) or not _live(deferred_timer):
		cancel_call("来电来源或必要播放时序依赖失效")
		return
	if telephone.get_holder_session_id() > 0 and not _live(telephone.get_holder()):
		cancel_call("来电期间持有玩家失效")
		return
	_sync_pause()
	if _stage == Stage.TALKING:
		if not _live(_holder) or not telephone.owns_handset(_holder, _holder_session):
			cancel_call("通话持有玩家或原听筒会话失效")
			return
		_start_pending_effects()
	elif _stage == Stage.DELAYED:
		_start_pending_effects()
		if _delay_expired and not _paused() and telephone.is_handset_stably_docked():
			_activate_call()
	elif _stage == Stage.RESOLVING:
		_resolve_request()
	elif _stage == Stage.WAIT_RETURN and not telephone.is_transfer_pending() and telephone.get_holder_session_id() == 0:
		cancel_call("等待正常归还期间原持有会话异常清除")
	elif _stage == Stage.ACTIVE and not _paused():
		_start_ring()


func _resolve_request() -> void:
	if not _live(telephone):
		return
	if telephone.has_committed_handset_hold():
		_successful_hold_seen = true
		_stage = Stage.WAIT_RETURN
	elif telephone.is_handset_stably_docked() and not _successful_hold_seen:
		_activate_call()


func _activate_call() -> void:
	_stage = Stage.ACTIVE
	_pending_effects = false
	_delay_expired = false
	if not _paused():
		_start_ring()


func _start_pending_effects() -> void:
	if not _pending_effects or _paused():
		return
	if _stage == Stage.DELAYED:
		_pending_effects = false
		_timer_serial = _wait_serial
		_stop_deferred_timer()
		if deferred_ring_delay == 0.0:
			_delay_expired = true
		else:
			_delay_callback = _on_delay_timeout.bind(_wait_serial)
			deferred_timer.timeout.connect(_delay_callback)
			deferred_timer.start(deferred_ring_delay)
	elif _stage == Stage.TALKING:
		if not _live(_player) or not _player.has_prepared_dialogue(_playback_token, telephone):
			cancel_call("成对接听观察后已准备播放会话失效")
			return
		_pending_effects = false
		if not _player.start_prepared_dialogue(_playback_token):
			cancel_call("成对接听完成后无法启动已准备对话")


func _on_delay_timeout(serial: int) -> void:
	if _stage != Stage.DELAYED or serial != _wait_serial or serial != _timer_serial:
		return
	_delay_expired = true
	if not _paused() and _live(telephone) and telephone.is_handset_stably_docked():
		_activate_call()


func _on_dialogue_finished(token: int, _dialogue_id: StringName, source: Node, serial: int) -> void:
	if _stage != Stage.TALKING or serial != _call_serial or source != telephone or token != _playback_token:
		return
	if not _live(telephone) or not _live(_holder) or not telephone.owns_handset(_holder, _holder_session):
		cancel_call("正常对话收尾时听筒会话失效")
		return
	_stage = Stage.COMPLETED
	_disconnect_handset_display()
	_playback_token = 0
	_holder = null
	_holder_session = 0
	_prepared_actor = null
	_prepared_transaction = 0
	_pending_effects = false


func _on_dialogue_aborted(token: int, _dialogue_id: StringName, source: Node, reason: String, serial: int) -> void:
	if serial == _call_serial and source == telephone and token == _playback_token and token > 0:
		cancel_call(reason)


func _start_ring() -> void:
	if not last_ring_error.is_empty() or (_live(ring_player) and ring_player.playing):
		return
	if not _live(ring_player) or not _live(timing_root) or not timing_root.is_ancestor_of(ring_player) or ring_stream == null:
		last_ring_error = "铃声播放器或指定资源失效"
		push_warning(last_ring_error)
		return
	if _ring_copy == null:
		_ring_copy = ring_stream.duplicate() as AudioStreamWAV
		_ring_copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_ring_copy.loop_begin = 0
		# 长度与采样率只用于铃声资产完整循环端点，不用于来电或对话完成许可。
		_ring_copy.loop_end = int(round(_ring_copy.get_length() * _ring_copy.mix_rate))
		if _ring_copy.loop_end <= 0:
			last_ring_error = "铃声资源没有可循环的实际采样帧"
			push_warning(last_ring_error)
			return
		ring_player.stream = _ring_copy
	ring_player.play()


func _stop_ring() -> void:
	if _live(ring_player):
		ring_player.stop()


func _paused() -> bool:
	return get_tree().paused or (_live(_context) and bool(_context.is_dialogue_timing_paused()))


func _sync_pause() -> void:
	if _live(timing_root):
		var local_pause: bool = _live(_context) and bool(_context.is_dialogue_local_timing_paused())
		# 场景树暂停仍由可暂停模式处理；本地菜单冻结使用禁用模式。
		timing_root.process_mode = Node.PROCESS_MODE_DISABLED if local_pause else Node.PROCESS_MODE_PAUSABLE


func _on_pause_changed(_paused_value: bool) -> void:
	_sync_pause()


func _stop_deferred_timer() -> void:
	if is_instance_valid(deferred_timer):
		deferred_timer.stop()
		if _delay_callback.is_valid() and deferred_timer.timeout.is_connected(_delay_callback):
			deferred_timer.timeout.disconnect(_delay_callback)
	_delay_callback = Callable()


func _watch_handset_display() -> bool:
	var inventory: AutolysisInventoryController = _holder.get_node_or_null("InventoryController") as AutolysisInventoryController if _live(_holder) else null
	var display: Node3D = inventory.get_handset_display() if _live(inventory) else null
	if not _live(display) or not inventory.is_handset_display_session(telephone, display, _holder_session):
		if _live(inventory):
			inventory.abort_handset_session(telephone, _holder_session, "接听观察后必要听筒显示失效")
		else:
			cancel_call("接听观察后必要听筒库存失效")
		return false
	_handset_display = display
	var callback: Callable = _on_handset_display_exiting.bind(_call_serial, _holder_session)
	if not display.tree_exiting.is_connected(callback):
		display.tree_exiting.connect(callback)
	return true


func _disconnect_handset_display() -> void:
	var callback: Callable = _on_handset_display_exiting.bind(_call_serial, _holder_session)
	if is_instance_valid(_handset_display) and _handset_display.tree_exiting.is_connected(callback):
		_handset_display.tree_exiting.disconnect(callback)
	_handset_display = null


func _on_handset_display_exiting(serial: int, session: int) -> void:
	if _stage != Stage.TALKING or serial != _call_serial or session != _holder_session:
		return
	var inventory: AutolysisInventoryController = _holder.get_node_or_null("InventoryController") as AutolysisInventoryController if _live(_holder) else null
	if _live(inventory):
		inventory.abort_handset_session(telephone, session, "通话必要听筒显示离开场景树")
	else:
		cancel_call("通话必要听筒库存失效")


func _exit_tree() -> void:
	cancel_call("电话来电控制器离开场景树")
	if is_instance_valid(_context) and _context.dialogue_pause_changed.is_connected(_on_pause_changed):
		_context.dialogue_pause_changed.disconnect(_on_pause_changed)


func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
