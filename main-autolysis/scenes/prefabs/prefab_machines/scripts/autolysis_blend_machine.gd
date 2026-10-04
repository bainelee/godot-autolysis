class_name AutolysisBlendMachine
extends StaticBody3D
## 统一保存配药批次与运行锁；槽门、罐位、拉杆继续独立处理外观动作。

signal processing_started(batch_id: int)
signal processing_completed(batch_id: int, contents: AutolysisLiquidContents)
signal processing_failed(batch_id: int, reason: String)
signal handle_pull_denied(actor: Node3D, reason: StringName)

const PROCESSING_SECONDS: float = 2.0
const INDICATOR_HALF_CYCLE_SECONDS: float = 0.5
const INDICATOR_RED_MATERIAL = preload("res://main-autolysis/assets/materials/base_color/mat_base_red_2.tres")
const INDICATOR_ORANGE_MATERIAL = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_orange_0.tres")
const INDICATOR_GREEN_MATERIAL = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_green_0.tres")

enum IndicatorState { DEFAULT, READY, RUNNING, COMPLETED }

@export var focus_target: AutolysisFocusTarget
@export var reference_camera: Camera3D
@export var root_interaction: AutolysisInteractionComponent
@export var animation_source: AnimationPlayer
@export var slots: Array[AutolysisBlendSlot] = []
@export var handle: AutolysisBlendHandle
@export var tank_place: AutolysisBlendTankPlace
@export var processing_timer: Timer
@export var status_indicator: MeshInstance3D

var _configured: bool = false
var _processing: bool = false
var _committing: bool = false
var _fault: String = ""
var _batch_id: int = 0
var _batch_slots: Array[AutolysisBlendSlot] = []
var _batch_items: Array[AutolysisRawMaterial] = []
var _batch_instances: Array[AutolysisItemInstance] = []
var _batch_ids: Array[String] = []
var _batch_raw_material_ids: Array[String] = []
var _batch_tank: AutolysisLiquidTank
var _batch_tank_instance: AutolysisItemInstance
var _indicator_enabled: bool = false
var _indicator_state: int = -1
var _indicator_orange_material: StandardMaterial3D
var _indicator_tween: Tween
var _indicator_refresh_queued: bool = false
var _completed_tank_instance: AutolysisItemInstance
var _observed_tank: AutolysisLiquidTank
var _observed_tank_instance: AutolysisItemInstance


func _ready() -> void:
	if is_instance_valid(root_interaction):
		root_interaction.is_enabled = false
	_initialize_indicator()
	if not _validate_configuration():
		push_error("原药混合器配置无效：%s" % get_path())
		return
	animation_source.stop(true)
	animation_source.active = false
	for index: int in slots.size():
		var slot: AutolysisBlendSlot = slots[index]
		var library: AnimationLibrary = AnimationLibrary.new()
		library.add_animation(slot.animation_name, animation_source.get_animation(slot.animation_name))
		var runtime_player: AnimationPlayer = AnimationPlayer.new()
		runtime_player.name = "BlendSlotAnimation_%d" % index
		runtime_player.root_node = NodePath("..")
		runtime_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		runtime_player.process_mode = Node.PROCESS_MODE_PAUSABLE
		runtime_player.playback_auto_capture = false
		runtime_player.add_animation_library(&"", library)
		add_child(runtime_player)
		if not slot.configure(focus_target, runtime_player):
			push_error("原药混合器槽位配置失败：%s；%s" % [slot.get_path(), slot.get_configuration_error()])
			return
	if not handle.configure(focus_target):
		push_error("原药混合器拉杆配置失败：%s；%s" % [handle.get_path(), handle.get_configuration_error()])
		return
	if not tank_place.configure(self, focus_target):
		push_error("配药器液体罐位配置失败：%s；%s" % [tank_place.get_path(), tank_place.get_configuration_error()])
		return
	if not focus_target.configure(self, reference_camera, root_interaction, slots, [handle], tank_place):
		push_error("原药混合器聚焦描述登记失败：%s" % get_path())
		return
	root_interaction.set_availability_check(_can_enter)
	root_interaction.interaction_requested.connect(_on_entry_requested)
	handle.interaction_completed.connect(_on_handle_completed)
	handle.handle_pull_denied.connect(_on_handle_pull_denied)
	processing_timer.timeout.connect(_on_processing_timeout)
	_configured = true
	handle.drag_interaction.is_enabled = true
	tank_place.transfer_interaction.is_enabled = true
	root_interaction.is_enabled = true
	for slot: AutolysisBlendSlot in slots:
		slot.state_changed.connect(_queue_indicator_refresh)
	tank_place.state_changed.connect(_queue_indicator_refresh)
	_refresh_indicator()


## 通知负责常规刷新；物理帧只在显示或监听发生偏差时合并刷新，覆盖外部释放及配置改动。
func _physics_process(_delta: float) -> void:
	if not _indicator_enabled:
		return
	if not _indicator_dependencies_are_valid():
		_disable_indicator("指示灯引用、网格或材质已失效")
		return
	var current_tank: AutolysisLiquidTank = tank_place.get_stored_item() if _node_is_live(tank_place) else null
	var current_instance: AutolysisItemInstance = current_tank.item_instance if current_tank != null else null
	if _get_indicator_state() != _indicator_state or current_tank != _observed_tank or current_instance != _observed_tank_instance:
		_queue_indicator_refresh()


func _initialize_indicator() -> void:
	if not _node_is_live(status_indicator) or status_indicator.get_parent() != self or status_indicator.mesh == null:
		_disable_indicator("status_indicator（状态指示灯）必须绑定本机直接子级的有效网格")
		return
	if not INDICATOR_RED_MATERIAL is StandardMaterial3D or not INDICATOR_ORANGE_MATERIAL is StandardMaterial3D or not INDICATOR_GREEN_MATERIAL is StandardMaterial3D:
		_disable_indicator("三份指定指示灯材质必须为 StandardMaterial3D（标准三维材质）")
		return
	_indicator_orange_material = INDICATOR_ORANGE_MATERIAL.duplicate() as StandardMaterial3D
	if not is_instance_valid(_indicator_orange_material):
		_disable_indicator("橙色材质独立副本创建失败")
		return
	_indicator_enabled = true
	status_indicator.tree_exiting.connect(_on_indicator_exiting)
	_set_indicator_state(IndicatorState.DEFAULT)


func _indicator_dependencies_are_valid() -> bool:
	return _node_is_live(status_indicator) and status_indicator.get_parent() == self and status_indicator.mesh != null and is_instance_valid(_indicator_orange_material)


func _queue_indicator_refresh() -> void:
	if not _indicator_enabled or _indicator_refresh_queued or not _node_is_live(self):
		return
	_indicator_refresh_queued = true
	_refresh_indicator.call_deferred()


func _refresh_indicator() -> void:
	_indicator_refresh_queued = false
	if not _indicator_enabled or not _node_is_live(self):
		return
	if not _indicator_dependencies_are_valid():
		_disable_indicator("指示灯引用、网格或材质已失效")
		return
	_update_observed_tank()
	if not _fault.is_empty() or not _has_completed_tank():
		_completed_tank_instance = null
	_set_indicator_state(_get_indicator_state())


func _get_indicator_state() -> IndicatorState:
	if not _fault.is_empty():
		return IndicatorState.DEFAULT
	if _processing:
		return IndicatorState.RUNNING
	if not is_configured():
		return IndicatorState.DEFAULT
	if _has_completed_tank():
		return IndicatorState.COMPLETED
	return IndicatorState.READY if can_start_processing() else IndicatorState.DEFAULT


## 凭据只由本机成功提交建立；外部填罐或候选取回失败不得制造或提前清除凭据。
func _has_completed_tank() -> bool:
	if not is_instance_valid(_completed_tank_instance) or not _completed_tank_instance.is_valid_instance() or not _node_is_live(tank_place):
		return false
	var tank: AutolysisLiquidTank = tank_place.get_stored_item()
	return _node_is_live(tank) and tank_place.owns_item(tank) and tank.item_instance == _completed_tank_instance and tank.item_definition == _completed_tank_instance.definition and not _completed_tank_instance.is_empty_liquid_tank()


func _set_indicator_state(next_state: IndicatorState) -> void:
	if _indicator_state == next_state:
		return
	_stop_indicator_blink()
	_indicator_state = next_state
	match next_state:
		IndicatorState.DEFAULT:
			status_indicator.material_override = INDICATOR_RED_MATERIAL
		IndicatorState.READY:
			_indicator_orange_material.emission_energy_multiplier = (INDICATOR_ORANGE_MATERIAL as StandardMaterial3D).emission_energy_multiplier
			status_indicator.material_override = _indicator_orange_material
		IndicatorState.RUNNING:
			_indicator_orange_material.emission_energy_multiplier = 2.0
			status_indicator.material_override = _indicator_orange_material
			_indicator_tween = create_tween()
			_indicator_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			_indicator_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
			_indicator_tween.set_ignore_time_scale(false)
			_indicator_tween.set_trans(Tween.TRANS_LINEAR)
			_indicator_tween.set_loops()
			_indicator_tween.tween_property(_indicator_orange_material, "emission_energy_multiplier", 0.0, INDICATOR_HALF_CYCLE_SECONDS)
			_indicator_tween.tween_property(_indicator_orange_material, "emission_energy_multiplier", 2.0, INDICATOR_HALF_CYCLE_SECONDS)
		IndicatorState.COMPLETED:
			status_indicator.material_override = INDICATOR_GREEN_MATERIAL


func _stop_indicator_blink() -> void:
	if is_instance_valid(_indicator_tween):
		_indicator_tween.kill()
	_indicator_tween = null


func _update_observed_tank() -> void:
	var current_tank: AutolysisLiquidTank = tank_place.get_stored_item() if _node_is_live(tank_place) else null
	var current_instance: AutolysisItemInstance = current_tank.item_instance if current_tank != null else null
	if current_tank == _observed_tank and current_instance == _observed_tank_instance:
		return
	_disconnect_observed_tank()
	_observed_tank = current_tank
	_observed_tank_instance = current_instance
	if is_instance_valid(_observed_tank):
		_observed_tank.tree_exiting.connect(_queue_indicator_refresh)
	if is_instance_valid(_observed_tank_instance):
		_observed_tank_instance.changed.connect(_queue_indicator_refresh)


func _disconnect_observed_tank() -> void:
	if is_instance_valid(_observed_tank) and _observed_tank.tree_exiting.is_connected(_queue_indicator_refresh):
		_observed_tank.tree_exiting.disconnect(_queue_indicator_refresh)
	if is_instance_valid(_observed_tank_instance) and _observed_tank_instance.changed.is_connected(_queue_indicator_refresh):
		_observed_tank_instance.changed.disconnect(_queue_indicator_refresh)
	_observed_tank = null
	_observed_tank_instance = null


func _on_indicator_exiting() -> void:
	_stop_indicator_blink()
	_indicator_enabled = false
	_indicator_refresh_queued = false
	_disconnect_observed_tank()
	_completed_tank_instance = null


func _disable_indicator(reason: String) -> void:
	_on_indicator_exiting()
	push_error("配药器状态指示灯停止更新：%s；%s" % [reason, get_path()])


func _validate_configuration() -> bool:
	if not is_instance_valid(focus_target) or focus_target.get_parent() != self:
		return false
	if not is_instance_valid(reference_camera) or not is_ancestor_of(reference_camera):
		return false
	if not is_instance_valid(root_interaction) or root_interaction.get_parent() != self:
		return false
	if root_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.FOCUS:
		return false
	if not is_instance_valid(animation_source) or slots.size() != 4:
		return false
	if not is_instance_valid(handle) or not is_ancestor_of(handle) or handle.device_root != self:
		return false
	if not _node_is_live(tank_place) or tank_place.get_parent() != self:
		return false
	if not _node_is_live(processing_timer) or processing_timer.get_parent() != self:
		return false
	if not processing_timer.one_shot or processing_timer.process_mode != Node.PROCESS_MODE_PAUSABLE or processing_timer.ignore_time_scale or processing_timer.process_callback != Timer.TIMER_PROCESS_PHYSICS or not is_equal_approx(processing_timer.wait_time, PROCESSING_SECONDS):
		return false
	var seen: Array[AutolysisBlendSlot] = []
	for index: int in slots.size():
		var slot: AutolysisBlendSlot = slots[index]
		if not is_instance_valid(slot) or slot.get_parent() != self or seen.has(slot):
			return false
		if slot.name != StringName("blend_slot_%d" % index):
			return false
		if not animation_source.has_animation(slot.animation_name):
			return false
		var animation: Animation = animation_source.get_animation(slot.animation_name)
		if animation.loop_mode != Animation.LOOP_NONE or not is_equal_approx(animation.length, 0.2):
			return false
		if animation.get_track_count() != 1 or animation.track_get_path(0) != NodePath("%s:rotation" % slot.name):
			return false
		seen.append(slot)
	return true


func is_configured() -> bool:
	if not _configured or not _validate_configuration() or not focus_target.is_valid_target():
		return false
	return handle.is_configured() and tank_place.is_configured()


func is_batch_running() -> bool:
	return _processing


func is_interaction_locked() -> bool:
	return not _configured or _processing or not _fault.is_empty() or not _validate_configuration()


func get_processing_batch_id() -> int:
	return _batch_id


func get_processing_fault() -> String:
	return _fault


func can_start_processing() -> bool:
	return get_start_denial_reason().is_empty()


## 所有启动前提集中在只读查询；拉杆据此选择完整或受限行程。
func get_start_denial_reason() -> StringName:
	if not _fault.is_empty():
		return &"processing_fault"
	if not is_configured():
		return &"invalid_configuration"
	if _processing:
		return &"processing"
	if tank_place.is_transfer_busy():
		return &"transfer_busy"
	var tank: AutolysisLiquidTank = tank_place.get_stored_item()
	if not is_instance_valid(tank):
		return &"missing_tank"
	if not tank_place.owns_item(tank) or not is_instance_valid(tank.item_instance) or not tank.item_instance.is_valid_instance():
		return &"invalid_tank"
	if not tank.is_empty():
		return &"filled_tank"
	var material_count: int = 0
	for slot: AutolysisBlendSlot in slots:
		if not slot.is_configured():
			return &"invalid_slot"
		if slot.is_transfer_busy():
			return &"transfer_busy"
		if not slot.is_closed():
			return &"door_not_closed"
		var item: AutolysisRawMaterial = slot.get_stored_item()
		if item == null:
			continue
		if not slot.owns_item(item) or not is_instance_valid(item.item_instance) or not item.item_instance.is_valid_instance():
			return &"invalid_raw_material"
		if item.item_definition != item.item_instance.definition or not item.item_definition.is_raw_material:
			return &"invalid_raw_material"
		if AutolysisLiquidContents.resolve_raw_material_definition(String(item.item_definition.item_id)) != item.item_definition:
			return &"invalid_raw_material"
		material_count += 1
	return &"missing_raw_material" if material_count == 0 else &""


func try_start_processing(actor: Node3D) -> bool:
	if not can_start_processing() or not _actor_is_focused(actor):
		return false
	# 先锁运行再保存来源；随后启动计时，通知期间不得重入另一批次。
	_processing = true
	_batch_id += 1
	_batch_slots.assign(slots)
	_batch_items.clear()
	_batch_instances.clear()
	_batch_ids.clear()
	_batch_raw_material_ids.clear()
	_batch_tank = tank_place.get_stored_item()
	_batch_tank_instance = _batch_tank.item_instance
	for slot: AutolysisBlendSlot in _batch_slots:
		var item: AutolysisRawMaterial = slot.get_stored_item()
		_batch_items.append(item)
		_batch_instances.append(item.item_instance if item != null else null)
		var raw_id: String = String(item.item_definition.item_id) if item != null else ""
		_batch_ids.append(raw_id)
		if item != null:
			_batch_raw_material_ids.append(raw_id)
	processing_timer.start(PROCESSING_SECONDS)
	_refresh_indicator()
	processing_started.emit(_batch_id)
	return true


func owns_processing_source(slot: AutolysisBlendSlot, item: AutolysisRawMaterial, batch_id: int) -> bool:
	if not _processing or batch_id != _batch_id or not _fault.is_empty():
		return false
	var index: int = _batch_slots.find(slot)
	return index >= 0 and _batch_items[index] == item and item != null


func is_committing_processing_batch(batch_id: int) -> bool:
	return _committing and _processing and batch_id == _batch_id and _fault.is_empty()


func _on_processing_timeout() -> void:
	if not _processing or _committing or not _fault.is_empty():
		return
	# 提前外部发送或重复计时回调不能越过真实计时。
	if not _node_is_live(processing_timer) or not processing_timer.is_stopped():
		return
	var completed_batch_id: int = _batch_id
	var contents: AutolysisLiquidContents = AutolysisLiquidContents.create_result(_batch_raw_material_ids)
	var error: String = _get_batch_commit_error(contents)
	if not error.is_empty():
		_fail_batch(error)
		return
	_committing = true
	# 先静默清除全部槽记录；任何显示变化回调都只能观察完整提交后的占用。
	var consumed_items: Array[AutolysisRawMaterial] = []
	for index: int in _batch_slots.size():
		var item: AutolysisRawMaterial = _batch_items[index]
		if item == null:
			continue
		if not _batch_slots[index].consume_processing_item(self, completed_batch_id, item, _batch_instances[index], _batch_ids[index]):
			_committing = false
			_fail_batch("已预检原药在同步提交中拒绝消费：槽号%d" % index)
			return
		consumed_items.append(item)
	if not _batch_tank.apply_contents(contents, false):
		_committing = false
		_fail_batch("已预检液体罐拒绝静默装填")
		return
	var completed_tank: AutolysisLiquidTank = _batch_tank
	var completed_tank_instance: AutolysisItemInstance = _batch_tank_instance
	_clear_batch()
	_committing = false
	# 隐藏会同步发送可见性通知；保持运行锁，并在每个回调边界核验存活。
	for item: AutolysisRawMaterial in consumed_items:
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			item.finish_pickup()
		if not is_instance_valid(self) or not is_inside_tree() or is_queued_for_deletion():
			return
	if _node_is_live(completed_tank):
		completed_tank.notify_contents_changed()
	# 内容通知可释放设备，不继续访问已释放实例。
	if is_instance_valid(self) and is_inside_tree() and not is_queued_for_deletion():
		_processing = false
		_completed_tank_instance = completed_tank_instance if _node_is_live(completed_tank) and _node_is_live(tank_place) and tank_place.owns_item(completed_tank) and completed_tank.item_instance == completed_tank_instance else null
		_refresh_indicator()
		processing_completed.emit(completed_batch_id, contents)


func _get_batch_commit_error(contents: AutolysisLiquidContents) -> String:
	if not is_configured() or _batch_slots.size() != 4 or _batch_items.size() != 4 or _batch_instances.size() != 4 or _batch_ids.size() != 4:
		return "运行批次或设备配置失效"
	if not is_instance_valid(contents) or not contents.is_valid_contents():
		return "运行批次不能创建合法液体内容"
	if tank_place.is_transfer_busy() or not tank_place.owns_item(_batch_tank) or _batch_tank.item_instance != _batch_tank_instance:
		return "目标液体罐来源、实例或罐位事务失效"
	if not _batch_tank.is_empty() or not _batch_tank.can_apply_contents(contents):
		return "目标液体罐内容或显示依赖失效"
	for index: int in 4:
		var slot: AutolysisBlendSlot = _batch_slots[index]
		if not _node_is_live(slot) or slots[index] != slot or not slot.is_configured() or not slot.is_closed() or slot.is_transfer_busy():
			return "运行槽位配置或关闭状态失效：槽号%d" % index
		var item: AutolysisRawMaterial = _batch_items[index]
		if _batch_ids[index].is_empty():
			if slot.get_stored_item() != null:
				return "本轮空槽出现非批次来源：槽号%d" % index
		elif not _node_is_live(item) or not slot.can_consume_processing_item(self, _batch_id, item, _batch_instances[index], _batch_ids[index]):
			return "本轮原药来源或实例失效：槽号%d" % index
	return ""


func _fail_batch(reason: String) -> void:
	_fault = reason
	_processing = false
	_committing = false
	if is_instance_valid(processing_timer):
		processing_timer.stop()
	_completed_tank_instance = null
	_refresh_indicator()
	push_error("配药器批次%d故障，保持交互关闭：%s；%s" % [_batch_id, reason, get_path()])
	processing_failed.emit(_batch_id, reason)


func _clear_batch() -> void:
	_batch_slots.clear()
	_batch_items.clear()
	_batch_instances.clear()
	_batch_ids.clear()
	_batch_raw_material_ids.clear()
	_batch_tank = null
	_batch_tank_instance = null


func _exit_tree() -> void:
	_on_indicator_exiting()
	if is_instance_valid(processing_timer):
		processing_timer.stop()
	_batch_id += 1
	_processing = false
	_committing = false
	_clear_batch()


func _actor_is_focused(actor: Node3D) -> bool:
	if not _node_is_live(actor) or not actor is AutolysisPlayer:
		return false
	var player: AutolysisPlayer = actor as AutolysisPlayer
	return player.is_focus_business_allowed() and _node_is_live(player.focus_controller) and player.focus_controller.is_focused_on(focus_target)


func _on_handle_completed(actor: Node3D) -> void:
	try_start_processing(actor)


func _on_handle_pull_denied(actor: Node3D, reason: StringName) -> void:
	handle_pull_denied.emit(actor, reason)


func _can_enter(actor: Node3D) -> bool:
	if is_interaction_locked() or not is_configured() or not is_instance_valid(actor):
		return false
	var controller: Node = actor.get("focus_controller") as Node
	return is_instance_valid(controller) and controller.has_method("can_enter") and controller.can_enter(focus_target)


func _on_entry_requested(actor: Node3D) -> void:
	if not _can_enter(actor):
		return
	var controller: Node = actor.get("focus_controller") as Node
	controller.try_enter(focus_target)


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
