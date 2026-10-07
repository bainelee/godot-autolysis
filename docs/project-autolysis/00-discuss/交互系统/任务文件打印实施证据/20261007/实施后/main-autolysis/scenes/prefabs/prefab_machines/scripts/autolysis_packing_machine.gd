class_name AutolysisPackingMachine
extends StaticBody3D
## 封装器保存唯一选择、运行来源和待取产物；两件状态在静默段共同提交。

signal processing_started(batch_id: int)
signal processing_completed(batch_id: int, contents: AutolysisPackingContents)
signal processing_failed(batch_id: int, reason: String)

const PROCESSING_SECONDS: float = 2.0
const NO_TYPE: int = -1

enum IndicatorState { DEFAULT, READY, RUNNING, COMPLETED }

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
@export var start_indicator: MeshInstance3D
@export var completion_indicators: Array[MeshInstance3D] = []
@export_group("提示灯表现")
@export var indicator_default_material: StandardMaterial3D = preload("res://main-autolysis/assets/materials/base_color/mat_base_red_2.tres")
@export var indicator_ready_material: StandardMaterial3D = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_blue_1.tres")
@export var indicator_running_material: StandardMaterial3D = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_blue_0.tres")
@export var indicator_incomplete_material: StandardMaterial3D = preload("res://main-autolysis/assets/materials/base_color/mat_base_grey_4.tres")
@export var indicator_half_cycle_seconds: float = 0.5
@export var indicator_emission_minimum: float = 0.0
@export var indicator_emission_maximum: float = 2.0

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
var _indicator_enabled: bool = false
var _completion_indicator_enabled: bool = false
var _indicator_state: int = -1
var _indicator_blue_material: StandardMaterial3D
var _indicator_tween: Tween


func _ready() -> void:
	if is_instance_valid(root_interaction):
		root_interaction.is_enabled = false
	_initialize_indicator()
	if not _validate_configuration():
		push_error("封装器配置无效：%s" % get_path())
		return
	if _node_is_live(animation_source):
		animation_source.stop(true)
		animation_source.active = false
	if not tank_place.configure(self, focus_target) or not capsule_place.configure(self, focus_target):
		push_error("封装器槽位配置失败：%s；%s" % [tank_place.get_configuration_error(), capsule_place.get_configuration_error()])
		return
	if not door.configure(self, focus_target, _create_player(door.animation_name, "PackingDoorAnimation")):
		push_warning("封装器舱门停止更新：%s" % door.get_configuration_error())
	for index: int in type_switches.size():
		var control: AutolysisPackingTypeSwitch = type_switches[index]
		if not control.configure(self, focus_target, _create_player(control.animation_name, "PackingTypeAnimation_%d" % index)):
			push_warning("封装器类型开关停止更新：%s" % control.get_configuration_error())
		control.motion_cancelled.connect(_on_type_motion_cancelled.bind(control))
	if not start_button.configure(self, focus_target, _create_player(start_button.animation_name, "PackingStartAnimation")):
		push_error("封装器开始按钮配置失败：%s" % start_button.get_configuration_error())
		return
	if not focus_target.configure_packing(self, reference_camera, root_interaction, tank_place, capsule_place, door, type_switches, start_button):
		push_error("封装器聚焦描述登记失败：%s" % get_path())
		return
	root_interaction.set_availability_check(_can_enter)
	root_interaction.set_execution_handler(_on_entry_requested)
	processing_timer.timeout.connect(_on_processing_timeout)
	_configured = true
	tank_place.transfer_interaction.is_enabled = true
	capsule_place.transfer_interaction.is_enabled = true
	door.toggle_interaction.is_enabled = true
	for control: AutolysisPackingTypeSwitch in type_switches:
		control.toggle_interaction.is_enabled = true
	start_button.start_interaction.is_enabled = true
	root_interaction.is_enabled = true
	_refresh_indicator()


## 显示依赖独立校验；失效时只停灯，不改变封装业务许可或故障锁。
func _initialize_indicator() -> void:
	if is_instance_valid(indicator_running_material):
		_indicator_blue_material = indicator_running_material.duplicate() as StandardMaterial3D
	_indicator_enabled = _start_indicator_dependencies_are_valid()
	_completion_indicator_enabled = _completion_indicator_dependencies_are_valid()
	if _indicator_enabled:
		start_indicator.tree_exiting.connect(_on_indicator_exiting)
		_set_indicator_state(IndicatorState.DEFAULT)
	else:
		_disable_indicator("开始提示灯引用、材质或闪烁参数无效")
	if _completion_indicator_enabled:
		for indicator: MeshInstance3D in completion_indicators:
			indicator.tree_exiting.connect(_on_completion_indicator_exiting)
		_set_completion_indicators(false)
	else:
		push_warning("封装完成灯停止更新：显示引用或材质无效")


func rebind_indicators() -> void:
	_on_indicator_exiting()
	for indicator: MeshInstance3D in completion_indicators:
		if _node_is_live(indicator) and indicator.tree_exiting.is_connected(_on_completion_indicator_exiting):
			indicator.tree_exiting.disconnect(_on_completion_indicator_exiting)
	if _node_is_live(start_indicator) and start_indicator.tree_exiting.is_connected(_on_indicator_exiting):
		start_indicator.tree_exiting.disconnect(_on_indicator_exiting)
	_indicator_state = -1
	_initialize_indicator()
	_refresh_indicator()
	_set_completion_indicators(_completed_capsule_instance != null)


func _indicator_dependencies_are_valid() -> bool:
	return _start_indicator_dependencies_are_valid() and _completion_indicator_dependencies_are_valid()


func _start_indicator_dependencies_are_valid() -> bool:
	if not _node_is_live(start_button) or not is_ancestor_of(start_button) or not _node_is_live(start_indicator) or not is_ancestor_of(start_indicator) or start_indicator.mesh == null:
		return false
	if not is_instance_valid(indicator_default_material) or not is_instance_valid(indicator_ready_material) or not is_instance_valid(_indicator_blue_material):
		return false
	return is_finite(indicator_half_cycle_seconds) and indicator_half_cycle_seconds > 0.0 and is_finite(indicator_emission_minimum) and is_finite(indicator_emission_maximum) and indicator_emission_minimum >= 0.0 and indicator_emission_maximum >= indicator_emission_minimum


func _completion_indicator_dependencies_are_valid() -> bool:
	if completion_indicators.size() != 2 or completion_indicators[0] == completion_indicators[1] or not is_instance_valid(indicator_running_material) or not is_instance_valid(indicator_incomplete_material):
		return false
	for indicator: MeshInstance3D in completion_indicators:
		if not _node_is_live(indicator) or not is_ancestor_of(indicator) or indicator.mesh == null:
			return false
	return true


func _refresh_indicator() -> void:
	if not _indicator_enabled or not _node_is_live(self):
		return
	if not _start_indicator_dependencies_are_valid():
		_disable_indicator("提示灯引用、归属、网格或运行材质已失效")
		return
	_set_indicator_state(_get_indicator_state())


func _get_indicator_state() -> IndicatorState:
	if not _fault.is_empty():
		return IndicatorState.DEFAULT
	if _processing:
		return IndicatorState.RUNNING
	if _completed_capsule_instance != null:
		return IndicatorState.COMPLETED
	if _node_is_live(start_button) and _node_is_live(start_button.start_interaction):
		# 玩家组还包含发现区域；只向实际玩家查询完整交互许可。
		for candidate: Node in get_tree().get_nodes_in_group(&"Player"):
			if _node_is_live(candidate) and candidate is AutolysisPlayer and start_button.start_interaction.can_interact(candidate as AutolysisPlayer):
				return IndicatorState.READY
	return IndicatorState.DEFAULT


func _set_indicator_state(next_state: IndicatorState) -> void:
	if _indicator_state == next_state:
		return
	_stop_indicator_blink()
	_indicator_state = next_state
	match next_state:
		IndicatorState.DEFAULT:
			start_indicator.material_override = indicator_default_material
		IndicatorState.READY, IndicatorState.COMPLETED:
			start_indicator.material_override = indicator_ready_material
		IndicatorState.RUNNING:
			_indicator_blue_material.emission_energy_multiplier = indicator_emission_maximum
			start_indicator.material_override = _indicator_blue_material
			_indicator_tween = create_tween()
			_indicator_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			_indicator_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
			_indicator_tween.set_ignore_time_scale(false)
			_indicator_tween.set_trans(Tween.TRANS_LINEAR)
			_indicator_tween.set_loops()
			_indicator_tween.tween_property(_indicator_blue_material, "emission_energy_multiplier", indicator_emission_minimum, indicator_half_cycle_seconds)
			_indicator_tween.tween_property(_indicator_blue_material, "emission_energy_multiplier", indicator_emission_maximum, indicator_half_cycle_seconds)


## 完成双灯只在初始化、成功完成与成功取走本轮胶囊的边界切换。
func _set_completion_indicators(completed: bool) -> void:
	if not _completion_indicator_enabled:
		return
	if not _completion_indicator_dependencies_are_valid():
		_on_completion_indicator_exiting()
		push_warning("封装完成灯停止更新：显示依赖已失效")
		return
	for indicator: MeshInstance3D in completion_indicators:
		indicator.material_override = indicator_running_material if completed else indicator_incomplete_material


func _stop_indicator_blink() -> void:
	if is_instance_valid(_indicator_tween):
		_indicator_tween.kill()
	_indicator_tween = null


func _on_indicator_exiting() -> void:
	_stop_indicator_blink()
	_indicator_enabled = false


func _disable_indicator(reason: String) -> void:
	_on_indicator_exiting()
	push_warning("封装机提示灯停止更新：%s；%s" % [reason, get_path()])


func _on_completion_indicator_exiting() -> void:
	_completion_indicator_enabled = false


func _create_player(animation_name: StringName, player_name: String) -> AnimationPlayer:
	if not _node_is_live(animation_source) or not animation_source.has_animation(animation_name):
		return null
	var animation_root: Node = animation_source.get_node_or_null(animation_source.root_node)
	if not _node_is_live(animation_root) or (animation_root != self and not is_ancestor_of(animation_root)):
		return null
	var library: AnimationLibrary = AnimationLibrary.new()
	var library_name: StringName = &""
	var local_animation_name: StringName = animation_name
	var name_parts: PackedStringArray = String(animation_name).split("/", false, 1)
	if name_parts.size() == 2:
		library_name = StringName(name_parts[0])
		local_animation_name = StringName(name_parts[1])
	library.add_animation(local_animation_name, animation_source.get_animation(animation_name))
	var runtime_player: AnimationPlayer = AnimationPlayer.new()
	runtime_player.name = player_name
	runtime_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	runtime_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	runtime_player.playback_auto_capture = false
	runtime_player.add_animation_library(library_name, library)
	add_child(runtime_player)
	runtime_player.root_node = runtime_player.get_path_to(animation_root)
	runtime_player.speed_scale = animation_source.speed_scale
	return runtime_player


func _validate_configuration() -> bool:
	if not _node_is_live(self) or not _node_is_live(focus_target) or not is_ancestor_of(focus_target):
		return false
	if not _node_is_live(reference_camera) or not is_ancestor_of(reference_camera):
		return false
	if not _node_is_live(root_interaction) or root_interaction.get_parent() != self or root_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.FOCUS:
		return false
	if not _node_is_live(tank_place) or not is_ancestor_of(tank_place) or not _node_is_live(capsule_place) or not is_ancestor_of(capsule_place):
		return false
	if not _node_is_live(door) or not is_ancestor_of(door) or not _node_is_live(start_button) or not is_ancestor_of(start_button) or type_switches.size() != 3:
		return false
	if not _node_is_live(processing_timer) or not is_ancestor_of(processing_timer) or not processing_timer.one_shot or processing_timer.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return false
	if processing_timer.ignore_time_scale or processing_timer.process_callback != Timer.TIMER_PROCESS_PHYSICS:
		return false
	if _configured and not root_interaction.has_execution_handler(_on_entry_requested):
		return false
	var seen: Array[AutolysisPackingTypeSwitch] = []
	for index: int in type_switches.size():
		var candidate: Variant = type_switches[index]
		if not _node_is_live(candidate):
			return false
		var control: AutolysisPackingTypeSwitch = candidate as AutolysisPackingTypeSwitch
		if not is_ancestor_of(control) or seen.has(control) or control.packing_type != index:
			return false
		seen.append(control)
	return true


func is_configured() -> bool:
	return _configured and _validate_configuration() and focus_target.is_valid_target()


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
	for candidate: Variant in type_switches:
		if _node_is_live(candidate) and (candidate as AutolysisPackingTypeSwitch).is_animating():
			return true
	return false


func can_select_type(actor: Node3D, packing_type: int) -> bool:
	return packing_type >= 0 and packing_type < 3 and is_configured() and _switch_dependencies_are_valid() and not is_interaction_locked() and _completed_capsule_instance == null and not are_transfers_busy() and has_valid_inputs() and not are_switches_animating() and is_actor_focused(actor)


func _switch_dependencies_are_valid() -> bool:
	for candidate: Variant in type_switches:
		if not _node_is_live(candidate) or not (candidate as AutolysisPackingTypeSwitch).is_configured():
			return false
	return true


func _on_type_motion_cancelled(_reason: String, _control: AutolysisPackingTypeSwitch) -> void:
	_selected_type = NO_TYPE
	for candidate: Variant in type_switches:
		if _node_is_live(candidate):
			(candidate as AutolysisPackingTypeSwitch).clear_selection_for_recovery()
	_refresh_indicator()


func try_select_type(actor: Node3D, packing_type: int) -> bool:
	if not can_select_type(actor, packing_type):
		return false
	_selected_type = NO_TYPE if _selected_type == packing_type else packing_type
	_apply_selection()
	return true


func _apply_selection() -> void:
	# 先恢复旧灯，再亮新灯，使改选过程中也最多一盏发光灯。
	for candidate: Variant in type_switches:
		if not _node_is_live(candidate):
			continue
		var control: AutolysisPackingTypeSwitch = candidate as AutolysisPackingTypeSwitch
		if control.packing_type != _selected_type:
			control.set_selected(false)
	if _selected_type >= 0:
		type_switches[_selected_type].set_selected(true)


## 只在库存已成功提交取物后调用；这里不发布设备通知或再次查询库存。
func on_packing_item_taken(place: Node3D, instance: AutolysisItemInstance) -> void:
	if is_interaction_locked() or (place != tank_place and place != capsule_place):
		return
	var reset_completed: bool = _completed_capsule_instance != null
	if _completed_capsule_instance != null:
		if place != capsule_place or instance != _completed_capsule_instance:
			return
		_completed_capsule_instance = null
	_selected_type = NO_TYPE
	_apply_selection()
	_refresh_indicator()
	if reset_completed:
		_set_completion_indicators(false)


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
	if not door.is_configured() or door.is_animating() or (not door.is_open() and not door.is_closed()):
		return &"door_moving"
	if not _switch_dependencies_are_valid() or are_switches_animating():
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
	_refresh_indicator()
	start_button.play_press()
	processing_started.emit(_batch_id)
	return true


func _physics_process(delta: float) -> void:
	_refresh_indicator()
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
	_refresh_indicator()
	_set_completion_indicators(true)
	processing_completed.emit(completed_batch_id, contents)


func _get_batch_commit_error(contents: AutolysisPackingContents) -> String:
	if not is_configured() or not _timeout_received or _batch_elapsed < PROCESSING_SECONDS or _batch_type != _selected_type:
		return "运行批次、计时或设备配置失效"
	if not is_instance_valid(contents) or not contents.is_valid_contents():
		return "不能建立合法封装产物"
	if are_transfers_busy():
		return "本轮取放事务仍在运行"
	if not _node_is_live(_batch_tank) or not tank_place.owns_item(_batch_tank):
		return "本轮液体罐节点或槽位归属失效"
	if not _node_is_live(_batch_capsule) or not capsule_place.owns_item(_batch_capsule):
		return "本轮胶囊节点或槽位归属失效"
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
	_refresh_indicator()
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
	_on_indicator_exiting()
	if is_instance_valid(processing_timer):
		processing_timer.stop()
	_batch_id += 1
	_processing = false
	_committing = false
	_clear_batch()


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
