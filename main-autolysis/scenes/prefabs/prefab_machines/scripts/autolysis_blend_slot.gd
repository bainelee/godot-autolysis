class_name AutolysisBlendSlot
extends AnimatableBody3D
## 每槽独立保存开闭与占用；道具栏提交由玩家的道具控制器负责。

signal state_changed
signal motion_cancelled(reason: String)

enum SlotState { CLOSED, OPENING, OPEN, CLOSING }

@export var raw_material_anchor: Node3D
@export var toggle_interaction: AutolysisInteractionComponent
@export var transfer_interaction: AutolysisInteractionComponent
@export var animation_name: StringName

var focus_target: AutolysisFocusTarget
var machine: AutolysisBlendMachine
var state: SlotState = SlotState.CLOSED

var _runtime_player: AnimationPlayer
var _stored_item: AutolysisRawMaterial
var _configured: bool = false
var _transfer_busy: bool = false
var _stable_open: bool = false
var _motion_serial: int = 0
var _motion_pending: bool = false
var _result_frame: int = -1
var _result_serial: int = -1
var _motion_suspended: bool = false
var _motion_error: String = ""
var _active_animation: Animation
var _result_animation: Animation
var _last_completed_transform: Transform3D
var _advancing: bool = false
var _restore_queued: bool = false
var _restore_open: bool = false
var _rebind_queued: bool = false
var _replacement_player: AnimationPlayer
var _stop_queued: bool = false


func configure(target: AutolysisFocusTarget, runtime_player: AnimationPlayer) -> bool:
	if _configured:
		return false
	focus_target = target
	var ancestor: Node = get_parent()
	while ancestor != null and not ancestor is AutolysisBlendMachine:
		ancestor = ancestor.get_parent()
	machine = ancestor as AutolysisBlendMachine
	_runtime_player = runtime_player
	_configured = true
	if _node_is_live(toggle_interaction):
		toggle_interaction.set_availability_check(can_toggle)
		toggle_interaction.set_execution_handler(_on_toggle_requested)
	if _node_is_live(transfer_interaction):
		transfer_interaction.set_availability_check(_can_transfer_interact)
		transfer_interaction.set_execution_handler(_on_transfer_requested)
	return rebind_animation_player(runtime_player)


func is_configured() -> bool:
	return _configured and _motion_error.is_empty() and get_configuration_error().is_empty()


## 配置失败给出实际失效字段，避免移动节点或清空引用后只能得到笼统错误。
func get_configuration_error() -> String:
	if not _node_is_live(self) or not _node_is_live(focus_target):
		return "槽位或聚焦目标描述不在有效场景树中"
	if not _node_is_live(machine) or not machine.is_ancestor_of(self) or not machine.is_ancestor_of(focus_target):
		return "槽位与聚焦目标描述必须属于同一配药器"
	if not _node_is_live(raw_material_anchor):
		return "raw_material_anchor（原药锚点）未绑定或已失效"
	if not raw_material_anchor is PhysicsBody3D or not is_ancestor_of(raw_material_anchor):
		return "raw_material_anchor（原药锚点）必须指向本槽子树的取放物理体"
	# 本槽由物理帧动画驱动，内部取放体只继承父变换，不能独立回写物理姿态。
	if raw_material_anchor is AnimatableBody3D and raw_material_anchor.sync_to_physics:
		return "随父槽运动的原药取放体必须关闭 sync_to_physics（物理同步）"
	if not _node_is_live(_runtime_player) or not _runtime_player.has_animation(animation_name):
		return "独立运行播放器或指定槽位动画无效"
	if not machine.is_ancestor_of(_runtime_player):
		return "槽门运行播放器必须归属于本机"
	for other_slot: Variant in machine.slots:
		if other_slot != self and _node_is_live(other_slot) and other_slot.get("_runtime_player") == _runtime_player:
			return "每槽必须拥有互不共享的独立运行播放器"
	if not is_finite(_runtime_player.speed_scale) or _runtime_player.speed_scale <= 0.0:
		return "槽门动画播放器速度必须为有限正数"
	if _runtime_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
		return "槽门由本槽物理回调统一推进并合并变换提交"
	var animation: Animation = _runtime_player.get_animation(animation_name)
	if animation.loop_mode != Animation.LOOP_NONE or not is_finite(animation.length) or animation.length <= 0.0:
		return "槽门必须配置可自然完成的有限非循环动画"
	var animation_root: Node = _runtime_player.get_node_or_null(_runtime_player.root_node)
	if not _node_is_live(animation_root) or (animation_root != machine and not machine.is_ancestor_of(animation_root)):
		return "槽门动画根引用必须解析为所属设备或其子树"
	if not _runtime_player.get_queue().is_empty() or not _runtime_player.animation_get_next(animation_name).is_empty():
		return "槽门独立播放器被外部排队或后续动作接管"
	if not _node_is_live(toggle_interaction) or toggle_interaction.get_parent() != self:
		return "toggle_interaction（开闭交互组件）必须位于本槽直接子级"
	if not _node_is_live(transfer_interaction) or transfer_interaction.get_parent() != raw_material_anchor:
		return "transfer_interaction（取放交互组件）必须位于原药取放体直接子级"
	if toggle_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT or transfer_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "槽位开闭和取放组件必须使用直接动作模式"
	if _configured and (not toggle_interaction.has_execution_handler(_on_toggle_requested) or not transfer_interaction.has_execution_handler(_on_transfer_requested)):
		return "槽位开闭或取放业务执行绑定失效"
	return ""


func is_open() -> bool:
	return is_configured() and not _motion_pending and state == SlotState.OPEN


func is_closed() -> bool:
	return is_configured() and not _motion_pending and state == SlotState.CLOSED


func is_transfer_busy() -> bool:
	return _transfer_busy


func is_animating() -> bool:
	return state == SlotState.OPENING or state == SlotState.CLOSING


func can_toggle(actor: Node3D) -> bool:
	return is_configured() and not _advancing and not machine.is_interaction_locked() and not _transfer_busy and not is_animating() and _actor_is_focused(actor)


func try_toggle(actor: Node3D) -> bool:
	if not can_toggle(actor):
		return false
	_motion_serial += 1
	_motion_suspended = false
	_active_animation = _runtime_player.get_animation(animation_name)
	if state == SlotState.CLOSED:
		state = SlotState.OPENING
		_runtime_player.play(animation_name, 0.0)
	else:
		state = SlotState.CLOSING
		_runtime_player.play_backwards(animation_name, 0.0)
	_emit_state_changed.call_deferred()
	return true


func can_transfer(actor: Node3D, allow_busy: bool = false) -> bool:
	return is_configured() and not machine.is_interaction_locked() and is_open() and (allow_busy or not _transfer_busy) and _actor_is_focused(actor)


func try_begin_transfer(actor: Node3D) -> bool:
	if _transfer_busy or not can_transfer(actor):
		return false
	_transfer_busy = true
	_emit_state_changed.call_deferred()
	return true


func end_transfer() -> void:
	if not _transfer_busy:
		return
	_transfer_busy = false
	_emit_state_changed.call_deferred()


func get_stored_item() -> AutolysisRawMaterial:
	if not is_instance_valid(_stored_item) or _stored_item.is_queued_for_deletion():
		return null
	return _stored_item


func owns_item(item: AutolysisRawMaterial) -> bool:
	return _node_is_live(item) and _node_is_live(raw_material_anchor) and get_stored_item() == item and item.device_stored and item.blend_slot == self and not is_instance_valid(item.shelf) and item.slot_index == -1 and item.get_parent() == raw_material_anchor


func try_attach_prepared_item(item: AutolysisRawMaterial) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or not is_open() or get_stored_item() != null:
		return false
	if not is_instance_valid(item) or item.is_queued_for_deletion() or not item.device_stored or item.blend_slot != self:
		return false
	if is_instance_valid(item.shelf) or item.slot_index != -1 or item.get_parent() != null:
		return false
	if not is_instance_valid(item.item_definition) or not item.item_definition.is_valid_definition() or not item.item_definition.is_raw_material:
		return false
	var anchor: Node3D = raw_material_anchor
	anchor.add_child(item)
	# 入树回调可释放设备或改变配置，提交占用前必须重新核验。
	if not is_instance_valid(self) or not is_configured() or machine.is_interaction_locked() or not is_open() or get_stored_item() != null:
		return false
	if not _node_is_live(item) or not _node_is_live(anchor) or raw_material_anchor != anchor or item.get_parent() != anchor:
		return false
	if not item.device_stored or item.blend_slot != self or is_instance_valid(item.shelf) or item.slot_index != -1:
		return false
	item.transform = Transform3D.IDENTITY
	_stored_item = item
	_emit_state_changed.call_deferred()
	return true


func release_item(item: AutolysisRawMaterial) -> bool:
	if not _transfer_busy or not is_configured() or machine.is_interaction_locked() or not owns_item(item):
		return false
	_stored_item = null
	item.blend_slot = null
	_emit_state_changed.call_deferred()
	return true


## 关门加工来源只接受所属设备当前批次；查询不修改槽位或来源。
func can_consume_processing_item(owner_machine: AutolysisBlendMachine, batch_id: int, item: AutolysisRawMaterial, expected_instance: AutolysisItemInstance, expected_id: String) -> bool:
	if owner_machine != machine or not is_configured() or not is_closed() or _transfer_busy or not owns_item(item):
		return false
	if not machine.owns_processing_source(self, item, batch_id):
		return false
	return is_instance_valid(expected_instance) and item.item_instance == expected_instance and expected_instance.is_valid_instance() and item.item_definition == expected_instance.definition and item.item_definition.is_raw_material and String(item.item_definition.item_id) == expected_id


## 设备先核验全部来源，再在无外部通知的同步提交段调用。
func consume_processing_item(owner_machine: AutolysisBlendMachine, batch_id: int, item: AutolysisRawMaterial, expected_instance: AutolysisItemInstance, expected_id: String) -> bool:
	if not _node_is_live(machine) or not machine.is_committing_processing_batch(batch_id) or not can_consume_processing_item(owner_machine, batch_id, item, expected_instance, expected_id):
		return false
	_stored_item = null
	item.blend_slot = null
	return true


## 失败只撤销本次候选；设备失效或槽位状态改变后也不能清除其他占用。
func rollback_prepared_item(item: Variant) -> void:
	if is_instance_valid(machine) and (machine.is_batch_running() or not machine.get_processing_fault().is_empty()) and _stored_item == item:
		return
	var occupancy_changed: bool = false
	if _stored_item == item:
		_stored_item = null
		occupancy_changed = true
	if is_instance_valid(item) and item is AutolysisRawMaterial and item.blend_slot == self:
		item.blend_slot = null
		occupancy_changed = true
	if occupancy_changed:
		_emit_state_changed.call_deferred()


func _actor_is_focused(actor: Node3D) -> bool:
	if not _node_is_live(actor) or not actor is AutolysisPlayer or not focus_target.is_valid_target():
		return false
	var player: AutolysisPlayer = actor as AutolysisPlayer
	return player.is_focus_business_allowed() and _node_is_live(player.focus_controller) and player.focus_controller.is_focused_on(focus_target)


func _can_transfer_interact(actor: Node3D) -> bool:
	if not _node_is_live(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and (inventory.can_place_in_blend_slot(actor, self) or inventory.can_take_from_blend_slot(actor, self))


func _on_toggle_requested(actor: Node3D) -> void:
	try_toggle(actor)


func _on_transfer_requested(actor: Node3D) -> void:
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if not is_instance_valid(inventory):
		return
	if inventory.can_place_in_blend_slot(actor, self):
		inventory.try_place_in_blend_slot(actor, self)
	elif inventory.can_take_from_blend_slot(actor, self):
		inventory.try_take_from_blend_slot(actor, self)


func _on_animation_finished(finished_animation: StringName) -> void:
	if finished_animation != animation_name or not is_animating() or not _motion_error.is_empty() or _restore_queued or _rebind_queued:
		return
	_motion_pending = true
	_result_frame = Engine.get_physics_frames()
	_result_serial = _motion_serial
	_result_animation = _active_animation


func _finish_result(serial: int) -> void:
	if serial != _motion_serial or not _motion_pending or not _node_is_live(self):
		return
	if not get_configuration_error().is_empty():
		_interrupt_motion(get_configuration_error())
		return
	_last_completed_transform = transform
	_stable_open = state == SlotState.OPENING
	state = SlotState.OPEN if _stable_open else SlotState.CLOSED
	_motion_pending = false
	_active_animation = null
	_result_animation = null
	_emit_state_changed.call_deferred()


## 只有所属目标自然完成才发布稳定态；外部停止不会伪报完成。
func _physics_process(delta: float) -> void:
	if not _configured:
		return
	var dependency_error: String = get_configuration_error()
	if not dependency_error.is_empty():
		if _motion_error.is_empty():
			_interrupt_motion(dependency_error)
		return
	if _motion_suspended:
		return
	if _motion_pending:
		if _runtime_player.is_playing() or _runtime_player.assigned_animation != animation_name or _runtime_player.get_animation(animation_name) != _result_animation:
			_interrupt_motion("槽门完成待同步期间目标播放被替换")
			return
		if Engine.get_physics_frames() > _result_frame:
			_finish_result(_result_serial)
		return
	if is_animating() and not _motion_pending and not _motion_suspended:
		var actual_speed: float = _runtime_player.get_playing_speed()
		var direction_matches: bool = actual_speed > 0.0 if state == SlotState.OPENING else actual_speed < 0.0
		if not _runtime_player.is_playing() or _runtime_player.current_animation != animation_name or _runtime_player.get_animation(animation_name) != _active_animation or not direction_matches:
			_interrupt_motion("槽门目标播放被外部停止或替换")
			return
		# 原生物理同步逐属性写回旧变换；先应用本次全部属性，再一次性提交实际变换。
		set_notify_local_transform(false)
		_advancing = true
		_runtime_player.advance(delta)
		if not is_instance_valid(self):
			return
		_advancing = false
		var applied_transform: Transform3D = transform
		set_notify_local_transform(true)
		if not _node_is_live(self):
			_motion_pending = false
			_restore_queued = false
			_rebind_queued = false
			_replacement_player = null
			_active_animation = null
			_result_animation = null
			return
		# 方法轨道可能在推进内取消或重绑定；引擎遍历缓存返回后才变更动画库。
		if _rebind_queued:
			_rebind_queued = false
			var replacement: Variant = _replacement_player
			_replacement_player = null
			rebind_animation_player(replacement if _node_is_live(replacement) else null)
			return
		dependency_error = get_configuration_error()
		if not dependency_error.is_empty():
			_interrupt_motion(dependency_error)
			return
		if _restore_queued:
			_restore_queued = false
			_restore_stable_state(_restore_open, _motion_serial)
			return
		transform = applied_transform
		if _stop_queued:
			_stop_queued = false
			if _node_is_live(_runtime_player):
				_runtime_player.stop(true)
		return


func suspend_motion() -> bool:
	if not is_animating() or _motion_pending or _motion_suspended or not is_configured():
		return false
	_motion_suspended = true
	return true


func resume_motion() -> bool:
	if not _motion_suspended or not is_animating() or not is_configured():
		return false
	_motion_suspended = false
	return true


func cancel_motion(reason: String = "显式取消") -> bool:
	if not _configured or not get_configuration_error().is_empty():
		return false
	_motion_serial += 1
	_motion_pending = false
	_motion_suspended = false
	_motion_error = ""
	_active_animation = null
	_stop_queued = false
	if _advancing:
		_restore_queued = true
		_restore_open = _stable_open
		_rebind_queued = false
		_replacement_player = null
		_motion_pending = true
		state = SlotState.OPENING if _stable_open else SlotState.CLOSING
	else:
		_restore_stable_state(_stable_open, _motion_serial)
	motion_cancelled.emit(reason)
	return true


func rebind_animation_player(player: AnimationPlayer) -> bool:
	_stop_queued = false
	if _advancing:
		_motion_serial += 1
		_motion_pending = true
		_motion_suspended = false
		_active_animation = null
		_restore_queued = false
		_rebind_queued = true
		_replacement_player = player
		state = SlotState.CLOSING
		return true
	_motion_serial += 1
	_motion_pending = false
	_motion_suspended = false
	_active_animation = null
	if _node_is_live(_runtime_player) and _runtime_player.animation_finished.is_connected(_on_animation_finished):
		_runtime_player.animation_finished.disconnect(_on_animation_finished)
	_runtime_player = player
	if _node_is_live(_runtime_player):
		_runtime_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_motion_error = get_configuration_error()
	if not _motion_error.is_empty():
		_stable_open = false
		state = SlotState.CLOSED
		return false
	_runtime_player.animation_finished.connect(_on_animation_finished)
	_stable_open = false
	_restore_stable_state(false, _motion_serial)
	return true


func get_motion_error() -> String:
	return _motion_error


func _restore_stable_state(opened: bool, serial: int) -> void:
	_motion_pending = true
	_result_frame = Engine.get_physics_frames()
	_result_serial = serial
	state = SlotState.OPENING if opened else SlotState.CLOSING
	_runtime_player.stop(true)
	var animation: Animation = _runtime_player.get_animation(animation_name)
	_result_animation = animation
	# 停止尚未推进的播放仍会遗留开始标记；临时表现副本先消费标记且不执行事件。
	var pose_animation: Animation = animation.duplicate() as Animation
	for track: int in pose_animation.get_track_count():
		var track_type: Animation.TrackType = pose_animation.track_get_type(track)
		if track_type == Animation.TYPE_METHOD or track_type == Animation.TYPE_AUDIO or track_type == Animation.TYPE_ANIMATION:
			pose_animation.track_set_enabled(track, false)
	var pose_library: AnimationLibrary = AnimationLibrary.new()
	pose_library.add_animation(&"pose", pose_animation)
	var library_name: StringName = StringName("__blend_restore_%d" % _motion_serial)
	while _runtime_player.has_animation_library(library_name):
		library_name = StringName("%s_" % library_name)
	_runtime_player.add_animation_library(library_name, pose_library)
	set_notify_local_transform(false)
	_runtime_player.assigned_animation = StringName("%s/pose" % library_name)
	_runtime_player.seek(animation.length if opened else 0.0, true, true)
	_runtime_player.assigned_animation = animation_name
	_runtime_player.seek(animation.length if opened else 0.0, true, true)
	var applied_transform: Transform3D = transform
	set_notify_local_transform(true)
	transform = applied_transform
	_runtime_player.pause()
	_runtime_player.remove_animation_library(library_name)


func _interrupt_motion(reason: String) -> void:
	_motion_serial += 1
	_restore_queued = false
	_rebind_queued = false
	_replacement_player = null
	_motion_pending = false
	_motion_suspended = false
	_active_animation = null
	_result_animation = null
	_motion_error = reason
	state = SlotState.OPEN if _stable_open else SlotState.CLOSED
	if _node_is_live(_runtime_player):
		if _advancing:
			_stop_queued = true
		else:
			_runtime_player.stop(true)
	motion_cancelled.emit(reason)
	_emit_state_changed.call_deferred()


## 延后外部通知，库存取放调用栈完成前不新增同步回调。
func _emit_state_changed() -> void:
	if not _node_is_live(self):
		return
	state_changed.emit()


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
