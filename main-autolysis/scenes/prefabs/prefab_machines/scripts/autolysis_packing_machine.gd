class_name AutolysisPackingMachine
extends StaticBody3D
## 封装器保存唯一选择、运行来源和待取产物；两件状态在静默段共同提交。

signal processing_started(batch_id: int)
signal processing_completed(batch_id: int, contents: AutolysisPackingContents)
signal processing_failed(batch_id: int, reason: String)

const PROCESSING_SECONDS: float = 2.0
const NO_TYPE: int = -1

@export var focus_target: AutolysisFocusTarget
@export var reference_camera: Camera3D
@export var root_interaction: AutolysisInteractionComponent
@export var animation_source: AnimationPlayer
@export var tank_place: AutolysisPackingTankPlace
@export var capsule_place: AutolysisPackingCapsulePlace
@export var door: AutolysisPackingDoor
@export var type_switches: Array[AutolysisPackingTypeSwitch] = []
@export var start_button: AutolysisPackingStartButton
@export var processing_timer: Timer

var _configured: bool = false
var _processing: bool = false
var _committing: bool = false
var _fault: String = ""
var _selected_type: int = NO_TYPE
var _completed_capsule_instance: AutolysisItemInstance
var _batch_id: int = 0
var _batch_start_frame: int = 0
var _batch_elapsed: float = 0.0
var _timeout_received: bool = false
var _batch_tank: AutolysisLiquidTank
var _batch_capsule: AutolysisPneumaticCapsule
var _batch_tank_instance: AutolysisItemInstance
var _batch_capsule_instance: AutolysisItemInstance
var _batch_source: AutolysisLiquidContents
var _batch_type: int = NO_TYPE


func _ready() -> void:
	if is_instance_valid(root_interaction):
		root_interaction.is_enabled = false
	if not _validate_configuration():
		push_error("封装器配置无效：%s" % get_path())
		return
	animation_source.stop(true)
	animation_source.active = false
	if not tank_place.configure(self, focus_target) or not capsule_place.configure(self, focus_target):
		push_error("封装器槽位配置失败：%s；%s" % [tank_place.get_configuration_error(), capsule_place.get_configuration_error()])
		return
	if not door.configure(self, focus_target, _create_player(door.animation_name, "PackingDoorAnimation")):
		push_error("封装器舱门配置失败：%s" % door.get_configuration_error())
		return
	for index: int in type_switches.size():
		var control: AutolysisPackingTypeSwitch = type_switches[index]
		if not control.configure(self, focus_target, _create_player(control.animation_name, "PackingTypeAnimation_%d" % index)):
			push_error("封装器类型开关配置失败：%s" % control.get_configuration_error())
			return
	if not start_button.configure(self, focus_target, _create_player(start_button.animation_name, "PackingStartAnimation")):
		push_error("封装器开始按钮配置失败：%s" % start_button.get_configuration_error())
		return
	if not focus_target.configure_packing(self, reference_camera, root_interaction, tank_place, capsule_place, door, type_switches, start_button):
		push_error("封装器聚焦描述登记失败：%s" % get_path())
		return
	root_interaction.set_availability_check(_can_enter)
	root_interaction.interaction_requested.connect(_on_entry_requested)
	processing_timer.timeout.connect(_on_processing_timeout)
	_configured = true
	tank_place.transfer_interaction.is_enabled = true
	capsule_place.transfer_interaction.is_enabled = true
	door.toggle_interaction.is_enabled = true
	for control: AutolysisPackingTypeSwitch in type_switches:
		control.toggle_interaction.is_enabled = true
	start_button.start_interaction.is_enabled = true
	root_interaction.is_enabled = true


func _create_player(animation_name: StringName, player_name: String) -> AnimationPlayer:
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(animation_name, animation_source.get_animation(animation_name))
	var runtime_player: AnimationPlayer = AnimationPlayer.new()
	runtime_player.name = player_name
	runtime_player.root_node = NodePath("..")
	runtime_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	runtime_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	runtime_player.playback_auto_capture = false
	runtime_player.add_animation_library(&"", library)
	add_child(runtime_player)
	return runtime_player


func _validate_configuration() -> bool:
	if not _node_is_live(self) or not _node_is_live(focus_target) or focus_target.get_parent() != self:
		return false
	if not _node_is_live(reference_camera) or not is_ancestor_of(reference_camera):
		return false
	if not _node_is_live(root_interaction) or root_interaction.get_parent() != self or root_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.FOCUS:
		return false
	if not _node_is_live(animation_source) or animation_source.get_parent() != self or (_configured and animation_source.active):
		return false
	if not _node_is_live(tank_place) or tank_place.get_parent() != self or not _node_is_live(capsule_place) or capsule_place.get_parent() != self:
		return false
	if not _node_is_live(door) or door.get_parent() != self or not _node_is_live(start_button) or start_button.get_parent() != self or type_switches.size() != 3:
		return false
	if not _node_is_live(processing_timer) or processing_timer.get_parent() != self or not processing_timer.one_shot or processing_timer.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return false
	if processing_timer.ignore_time_scale or processing_timer.process_callback != Timer.TIMER_PROCESS_PHYSICS or not is_equal_approx(processing_timer.wait_time, PROCESSING_SECONDS):
		return false
	if not _valid_animation(door.animation_name, 0.2) or not _valid_animation(start_button.animation_name, 0.12):
		return false
	var seen: Array[AutolysisPackingTypeSwitch] = []
	for index: int in type_switches.size():
		var control: AutolysisPackingTypeSwitch = type_switches[index]
		if not _node_is_live(control) or control.get_parent() != self or seen.has(control) or control.packing_type != index or not _valid_animation(control.animation_name, 0.16):
			return false
		seen.append(control)
	return true


func _valid_animation(animation_name: StringName, seconds: float) -> bool:
	if not animation_source.has_animation(animation_name):
		return false
	var animation: Animation = animation_source.get_animation(animation_name)
	return animation.loop_mode == Animation.LOOP_NONE and is_equal_approx(animation.length, seconds)


func is_configured() -> bool:
	if not _configured or not _validate_configuration() or not focus_target.is_valid_target():
		return false
	if not tank_place.is_configured() or not capsule_place.is_configured() or not door.is_configured() or not start_button.is_configured():
		return false
	for control: AutolysisPackingTypeSwitch in type_switches:
		if not control.is_configured():
			return false
	return true


func is_interaction_locked() -> bool:
	return not _configured or _processing or _committing or not _fault.is_empty() or not _validate_configuration()


func is_batch_running() -> bool:
	return _processing


func get_processing_batch_id() -> int:
	return _batch_id


func get_processing_fault() -> String:
	return _fault


func get_selected_type() -> int:
	return _selected_type


func get_completed_capsule_instance() -> AutolysisItemInstance:
	return _completed_capsule_instance


func are_transfers_busy() -> bool:
	return tank_place.is_transfer_busy() or capsule_place.is_transfer_busy()


func has_valid_inputs() -> bool:
	if not tank_place.is_configured() or not capsule_place.is_configured():
		return false
	var tank: AutolysisLiquidTank = tank_place.get_stored_item()
	var capsule: AutolysisPneumaticCapsule = capsule_place.get_stored_item()
	if not tank_place.owns_item(tank) or not capsule_place.owns_item(capsule):
		return false
	if not is_instance_valid(tank.item_instance) or not tank.item_instance.is_valid_instance() or not tank.item_instance.is_liquid_tank() or tank.item_definition != tank.item_instance.definition:
		return false
	if not is_instance_valid(capsule.item_instance) or not capsule.item_instance.is_valid_instance() or not capsule.item_instance.is_empty_pneumatic_capsule() or capsule.item_definition != capsule.item_instance.definition:
		return false
	return tank.item_instance.liquid_contents != null and tank.item_instance.liquid_contents.is_valid_contents()


func are_switches_animating() -> bool:
	for control: AutolysisPackingTypeSwitch in type_switches:
		if control.is_animating():
			return true
	return false


func can_select_type(actor: Node3D, packing_type: int) -> bool:
	return packing_type >= 0 and packing_type < 3 and is_configured() and not is_interaction_locked() and _completed_capsule_instance == null and not are_transfers_busy() and has_valid_inputs() and not are_switches_animating() and is_actor_focused(actor)


func try_select_type(actor: Node3D, packing_type: int) -> bool:
	if not can_select_type(actor, packing_type):
		return false
	_selected_type = NO_TYPE if _selected_type == packing_type else packing_type
	_apply_selection()
	return true


func _apply_selection() -> void:
	# 先恢复旧灯，再亮新灯，使改选过程中也最多一盏发光灯。
	for control: AutolysisPackingTypeSwitch in type_switches:
		if control.packing_type != _selected_type:
			control.set_selected(false)
	if _selected_type >= 0:
		type_switches[_selected_type].set_selected(true)


## 只在库存已成功提交取物后调用；这里不发布设备通知或再次查询库存。
func on_packing_item_taken(place: Node3D, instance: AutolysisItemInstance) -> void:
	if is_interaction_locked() or (place != tank_place and place != capsule_place):
		return
	if _completed_capsule_instance != null:
		if place != capsule_place or instance != _completed_capsule_instance:
			return
		_completed_capsule_instance = null
	_selected_type = NO_TYPE
	_apply_selection()


func can_start_processing() -> bool:
	return get_start_denial_reason().is_empty()


func get_start_denial_reason() -> StringName:
	if not _fault.is_empty():
		return &"processing_fault"
	if not is_configured():
		return &"invalid_configuration"
	if _processing or _committing:
		return &"processing"
	if _completed_capsule_instance != null:
		return &"completed_capsule_waiting"
	if are_transfers_busy():
		return &"transfer_busy"
	if not has_valid_inputs():
		return &"invalid_inputs"
	if _selected_type < 0 or _selected_type >= 3:
		return &"missing_type"
	if door.is_animating() or (not door.is_open() and not door.is_closed()):
		return &"door_moving"
	if are_switches_animating():
		return &"switch_moving"
	for control: AutolysisPackingTypeSwitch in type_switches:
		if control.is_selected() != (control.packing_type == _selected_type) or (control.is_selected() and not control.is_open()) or (not control.is_selected() and not control.is_closed()):
			return &"invalid_switch_state"
	return &""


func try_start_processing(actor: Node3D) -> bool:
	if not can_start_processing() or not is_actor_focused(actor):
		return false
	_processing = true
	_batch_id += 1
	_batch_tank = tank_place.get_stored_item()
	_batch_capsule = capsule_place.get_stored_item()
	_batch_tank_instance = _batch_tank.item_instance
	_batch_capsule_instance = _batch_capsule.item_instance
	_batch_source = _batch_tank_instance.liquid_contents.copy_contents()
	_batch_type = _selected_type
	_batch_start_frame = Engine.get_physics_frames()
	_batch_elapsed = 0.0
	_timeout_received = false
	processing_timer.start(PROCESSING_SECONDS)
	start_button.play_press()
	processing_started.emit(_batch_id)
	return true


func _physics_process(delta: float) -> void:
	if not _processing or _committing or not _fault.is_empty():
		return
	if Engine.get_physics_frames() > _batch_start_frame:
		_batch_elapsed += delta
	if _timeout_received and _batch_elapsed >= PROCESSING_SECONDS:
		_complete_batch()


func _on_processing_timeout() -> void:
	if not _processing or _committing or _timeout_received or not _fault.is_empty():
		return
	# 必须同时达到真实计时终点与累计物理游戏时间，提前或重复回调均不提交。
	if not _node_is_live(processing_timer) or not processing_timer.is_stopped() or _batch_elapsed + get_physics_process_delta_time() < PROCESSING_SECONDS:
		return
	_timeout_received = true
	if _batch_elapsed >= PROCESSING_SECONDS:
		_complete_batch()


func _complete_batch() -> void:
	if not _processing or _committing or not _timeout_received or _batch_elapsed < PROCESSING_SECONDS:
		return
	var contents: AutolysisPackingContents = AutolysisPackingContents.create_result(_batch_source, _batch_type)
	var error: String = _get_batch_commit_error(contents)
	if not error.is_empty():
		_fail_batch(error)
		return
	var completed_batch_id: int = _batch_id
	var completed_tank: AutolysisLiquidTank = _batch_tank
	var completed_capsule: AutolysisPneumaticCapsule = _batch_capsule
	var tank_instance: AutolysisItemInstance = _batch_tank_instance
	var capsule_instance: AutolysisItemInstance = _batch_capsule_instance
	var old_tank_contents: AutolysisLiquidContents = tank_instance.liquid_contents.copy_contents()
	_committing = true
	var capsule_written: bool = capsule_instance.set_packing_contents(contents, false)
	var tank_cleared: bool = capsule_written and tank_instance.set_liquid_contents(null, false)
	if not capsule_written or not tank_cleared:
		capsule_instance.set_packing_contents(null, false)
		tank_instance.set_liquid_contents(old_tank_contents, false)
		_committing = false
		_fail_batch("已预检两件物品拒绝静默共同提交，保留输入")
		return
	# 显示依赖预检完成；仍检查实际应用，失败时成对恢复原业务状态和外观。
	var tank_displayed: bool = AutolysisLiquidTankVisual.apply_instance(completed_tank, tank_instance)
	var capsule_displayed: bool = AutolysisPneumaticCapsuleVisual.apply_instance(completed_capsule, capsule_instance)
	if not tank_displayed or not capsule_displayed:
		capsule_instance.set_packing_contents(null, false)
		tank_instance.set_liquid_contents(old_tank_contents, false)
		AutolysisLiquidTankVisual.apply_instance(completed_tank, tank_instance)
		AutolysisPneumaticCapsuleVisual.apply_instance(completed_capsule, capsule_instance)
		_committing = false
		_fail_batch("两件物品显示应用失败，已成对恢复输入")
		return
	_completed_capsule_instance = capsule_instance
	_clear_batch()
	_committing = false
	# 运行锁覆盖通知边界；任一观察者均只能读取空罐与已封装胶囊。
	tank_instance.emit_changed()
	if not is_instance_valid(self) or not is_inside_tree() or is_queued_for_deletion():
		return
	if is_instance_valid(capsule_instance):
		capsule_instance.emit_changed()
	if not is_instance_valid(self) or not is_inside_tree() or is_queued_for_deletion():
		return
	_processing = false
	processing_completed.emit(completed_batch_id, contents)


func _get_batch_commit_error(contents: AutolysisPackingContents) -> String:
	if not is_configured() or not _timeout_received or _batch_elapsed < PROCESSING_SECONDS or _batch_type != _selected_type:
		return "运行批次、计时或设备配置失效"
	if not is_instance_valid(contents) or not contents.is_valid_contents():
		return "不能建立合法封装产物"
	if are_transfers_busy() or not _node_is_live(_batch_tank) or not _node_is_live(_batch_capsule) or not tank_place.owns_item(_batch_tank) or not capsule_place.owns_item(_batch_capsule):
		return "本轮两槽归属或取放事务失效"
	if _batch_tank.item_instance != _batch_tank_instance or _batch_capsule.item_instance != _batch_capsule_instance:
		return "本轮物品实例身份发生变化"
	if not is_instance_valid(_batch_tank_instance) or not _batch_tank_instance.is_valid_instance() or not is_instance_valid(_batch_capsule_instance) or not _batch_capsule_instance.is_empty_pneumatic_capsule():
		return "本轮液体罐或空气动胶囊实例失效"
	if not _source_matches_snapshot(_batch_tank_instance.liquid_contents):
		return "源内容原药顺序、相位或波形与启动快照不一致"
	if not AutolysisLiquidTankVisual.can_apply(_batch_tank) or not _batch_capsule.can_apply_contents(contents):
		return "液体罐或胶囊显示依赖失效"
	return ""


func _source_matches_snapshot(source: AutolysisLiquidContents) -> bool:
	return is_instance_valid(source) and source.is_valid_contents() and is_instance_valid(_batch_source) and source.get_raw_material_ids() == _batch_source.get_raw_material_ids() and source.get_phase_rgb() == _batch_source.get_phase_rgb() and source.get_wave_coordinates() == _batch_source.get_wave_coordinates()


func _fail_batch(reason: String) -> void:
	_fault = reason
	_processing = false
	_committing = false
	if is_instance_valid(processing_timer):
		processing_timer.stop()
	push_error("封装器批次%d故障，保留来源并关闭入口：%s；%s" % [_batch_id, reason, get_path()])
	processing_failed.emit(_batch_id, reason)


func _clear_batch() -> void:
	_batch_tank = null
	_batch_capsule = null
	_batch_tank_instance = null
	_batch_capsule_instance = null
	_batch_source = null
	_batch_type = NO_TYPE
	_batch_elapsed = 0.0
	_timeout_received = false


func is_actor_focused(actor: Node3D) -> bool:
	if not _node_is_live(actor) or not actor is AutolysisPlayer or not focus_target.is_valid_target():
		return false
	var player: AutolysisPlayer = actor as AutolysisPlayer
	return player.is_focus_business_allowed() and _node_is_live(player.focus_controller) and player.focus_controller.is_focused_on(focus_target)


func _can_enter(actor: Node3D) -> bool:
	if is_interaction_locked() or not is_configured() or not _node_is_live(actor):
		return false
	var controller: Node = actor.get("focus_controller") as Node
	return _node_is_live(controller) and controller.has_method("can_enter") and controller.can_enter(focus_target)


func _on_entry_requested(actor: Node3D) -> void:
	if not _can_enter(actor):
		return
	var controller: Node = actor.get("focus_controller") as Node
	controller.try_enter(focus_target)


func _exit_tree() -> void:
	if is_instance_valid(processing_timer):
		processing_timer.stop()
	_batch_id += 1
	_processing = false
	_committing = false
	_clear_batch()


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
