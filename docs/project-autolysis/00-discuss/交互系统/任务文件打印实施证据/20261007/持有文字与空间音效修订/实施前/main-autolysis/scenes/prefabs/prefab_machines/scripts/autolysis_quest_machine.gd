class_name AutolysisQuestMachine
extends StaticBody3D
## 本机拥有任务快照、有限动作序号与取纸锁；可选表现不授予业务许可。

signal state_changed(serial: int, state: int)
signal task_accepted(serial: int)
signal print_started(serial: int)
signal action_started(serial: int, phase: StringName, line: int)
signal action_finished(serial: int, phase: StringName, line: int)
signal data_line_revealed(serial: int, line: int)
signal print_completed(serial: int)
signal print_cancelled(serial: int, reason: String)
signal paper_taken(serial: int, instance: AutolysisItemInstance)

enum PrintState { IDLE, PENDING, PRINTING, RESETTING, COMPLETE, TAKING, RECOVERING, WAITING_RECOVERY }

@export var focus_target: AutolysisFocusTarget
@export var reference_camera: Camera3D
@export var root_interaction: AutolysisInteractionComponent
@export var print_button: AutolysisQuestPrintButton
@export var animation_source: AnimationPlayer
@export var paper_anchor: Node3D
@export var horizontal_axis: Node3D
@export var print_head: Node3D
@export var timing_root: Node
@export var paper_scene: PackedScene = preload("res://main-autolysis/scenes/prefabs/prefab_paper/quest_paper.tscn")
@export var paper_definition: AutolysisItemDefinition = preload("res://main-autolysis/systems/item-system/items/quest_paper.tres")
@export_group("机械动作配置")
@export var first_line_position: Vector3 = Vector3(0.0, -0.10, 0.0)
@export var minimum_line_y: float = -0.50
@export var line_spacing: float = 0.02
@export var axis_reset_position: Vector3 = Vector3.ZERO
@export var head_left_position: Vector3 = Vector3(-0.07, 0.0, 0.0)
@export var head_right_position: Vector3 = Vector3(0.27, 0.0, 0.0)
@export var head_center_position: Vector3 = Vector3(0.10, 0.0, 0.0)
@export var first_descent_seconds: float = 0.2
@export var first_wait_seconds: float = 0.5
@export var first_left_seconds: float = 0.2
@export var print_line_seconds: float = 5.0
@export var return_left_seconds: float = 0.4
@export var next_line_seconds: float = 0.2
@export var center_seconds: float = 0.2
@export var reset_seconds: float = 1.0
@export_group("提示表现")
@export var pending_indicator: MeshInstance3D
@export var completed_indicator: MeshInstance3D
@export var indicator_default_material: StandardMaterial3D = preload("res://main-autolysis/assets/materials/base_color/mat_base_red_3.tres")
@export var indicator_pending_material: StandardMaterial3D = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_orange_0.tres")
@export var indicator_completed_material: StandardMaterial3D = preload("res://main-autolysis/assets/materials/glow_color/mat_glow_blue_0.tres")
@export var indicator_half_cycle_seconds: float = 0.5
@export var indicator_emission_minimum: float = 0.0
@export var indicator_emission_maximum: float = 2.0
@export var notice_player: AudioStreamPlayer3D
@export var scanning_player: AudioStreamPlayer3D
@export var notice_stream: AudioStreamWAV = preload("res://main-autolysis/assets/audio/sound_fx/machine/sfx_machine_notice_0.wav")
@export var scanning_stream: AudioStreamWAV = preload("res://main-autolysis/assets/audio/sound_fx/machine/sfx_machine_scanning_0.wav")

var state: PrintState = PrintState.IDLE
var last_failure_reason: String = ""
var _configured: bool = false
var _serial: int = 0
var _task_contents: AutolysisQuestPaperContents
var _paper: AutolysisQuestPaper
var _paper_instance: AutolysisItemInstance
var _actor: Node3D
var _line: int = 0
var _mechanical_count: int = 0
var _first_left_done: bool = false
var _active_tween: Tween
var _action_id: int = 0
var _phase: StringName = &""
var _finished_pending: bool = false
var _completion_observed: bool = false
var _action_config: Dictionary = {}
var _printing_axis: Node3D
var _printing_head: Node3D
var _printing_anchor: Node3D
var _printing_timing_root: Node
var _events: Array[Dictionary] = []
var _materials: Array[StandardMaterial3D] = []
var _blinks: Array[Tween] = []
var _audio_copies: Array[AudioStreamWAV] = []
var _effect_active: Array[bool] = [false, false]
var _reported_effect_errors: Dictionary = {}
var _take_counter: int = 0
var _take_token: int = 0
var _take_actor: Node3D
var _take_paper: AutolysisQuestPaper
var _take_instance: AutolysisItemInstance
var _take_serial: int = 0
var _take_committed: bool = false
var _take_finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _live(root_interaction):
		root_interaction.is_enabled = false
	if _live(timing_root):
		timing_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	_initialize_effects()
	if not get_configuration_error().is_empty():
		push_warning("通知中心配置无效：%s" % get_configuration_error())
		return
	if _live(animation_source):
		animation_source.stop(true)
		animation_source.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		animation_source.process_mode = Node.PROCESS_MODE_PAUSABLE
	if not print_button.configure(self, focus_target, animation_source):
		push_warning("通知中心打印按钮停止更新：%s" % print_button.get_configuration_error())
	if not focus_target.configure_quest(self, reference_camera, root_interaction, print_button):
		push_warning("通知中心聚焦登记失败")
		return
	root_interaction.set_availability_check(_can_enter)
	root_interaction.set_execution_handler(_on_entry_requested)
	_configured = true
	root_interaction.is_enabled = true
	if _live(print_button) and _live(print_button.print_interaction):
		print_button.print_interaction.is_enabled = true
	horizontal_axis.position = axis_reset_position
	print_head.position = head_center_position


func get_configuration_error() -> String:
	if not _live(self) or not _live(focus_target) or focus_target.get_parent() != self:
		return "通知中心缺少直属聚焦描述"
	if not _live(reference_camera) or not is_ancestor_of(reference_camera):
		return "通知中心缺少本机聚焦相机"
	if not _live(root_interaction) or root_interaction.get_parent() != self or root_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.FOCUS:
		return "通知中心缺少直属聚焦交互入口"
	if not _live(print_button) or not is_ancestor_of(print_button):
		return "通知中心缺少显式打印按钮"
	return _motion_configuration_error()


func _motion_configuration_error() -> String:
	var dependency_error: String = _print_dependency_error()
	if not dependency_error.is_empty():
		return dependency_error
	if paper_scene == null or paper_definition == null or not paper_definition.is_valid_definition():
		return "纸张场景或任务文件物品定义失效"
	if not is_finite(line_spacing) or line_spacing <= 0.0 or not is_finite(minimum_line_y) or minimum_line_y > first_line_position.y:
		return "机械行间距及最低位置配置无效"
	for value: Vector3 in [first_line_position, axis_reset_position, head_left_position, head_right_position, head_center_position]:
		if not value.is_finite():
			return "打印目标位置必须有限"
	for duration: float in [first_descent_seconds, first_wait_seconds, first_left_seconds, print_line_seconds, return_left_seconds, next_line_seconds, center_seconds, reset_seconds]:
		if not is_finite(duration) or duration < 0.0:
			return "有限机械动作时长必须为有限非负数"
	return ""


func _print_dependency_error() -> String:
	# 已开始的动作只依赖实际目标；后续创建资源及表现配置属于下一次预检。
	if not _live(timing_root) or not is_ancestor_of(timing_root):
		return "通知中心缺少可暂停时序子树"
	if not _live(horizontal_axis) or not _live(print_head) or horizontal_axis == print_head or not is_ancestor_of(horizontal_axis) or not is_ancestor_of(print_head):
		return "本机打印横轴或打印头失效"
	if not _live(paper_anchor) or not is_ancestor_of(paper_anchor):
		return "本机纸张锚点失效"
	if state in [PrintState.PRINTING, PrintState.RESETTING] and (horizontal_axis != _printing_axis or print_head != _printing_head or paper_anchor != _printing_anchor or timing_root != _printing_timing_root):
		return "本次必要打印目标或时序来源被替换"
	return ""


func is_configured() -> bool:
	return _configured and _live(focus_target) and focus_target.is_valid_target()


func request_task_print(definition: AutolysisQuestPrintDefinition, actor: Node3D = null) -> bool:
	if not _live(self) or not is_configured() or state != PrintState.IDLE or _paper != null or _take_token != 0:
		return false
	if not is_instance_valid(definition) or not definition.is_valid_definition():
		return false
	var contents: AutolysisQuestPaperContents = definition.create_contents()
	if contents == null or not contents.is_valid_contents():
		return false
	_serial += 1
	_task_contents = contents
	_events.clear()
	last_failure_reason = ""
	_bind_actor(actor)
	_set_state(PrintState.PENDING)
	if not _live(self) or state != PrintState.PENDING:
		return false
	_set_effect(0, true)
	task_accepted.emit(_serial)
	return true


func can_start_print(actor: Node3D) -> bool:
	return _live(self) and state == PrintState.PENDING and _take_token == 0 and _paper == null and _task_contents != null and _task_contents.is_valid_contents() and _motion_configuration_error().is_empty() and is_actor_focused(actor) and not _paused()


func try_start_print(actor: Node3D) -> bool:
	if not can_start_print(actor):
		return false
	var instance: AutolysisItemInstance = AutolysisItemInstance.create(paper_definition)
	if instance == null or not instance.set_quest_paper_contents(_task_contents, false):
		return false
	var candidate: Node = paper_scene.instantiate()
	if not candidate is AutolysisQuestPaper:
		if is_instance_valid(candidate):
			candidate.free()
		return false
	# 先建立互斥；入树及纸张配置的可调用边界不能接受第二次开始。
	_serial += 1
	var accepted_serial: int = _serial
	_action_config = _capture_action_configuration()
	_printing_axis = horizontal_axis
	_printing_head = print_head
	_printing_anchor = paper_anchor
	_printing_timing_root = timing_root
	_paper = candidate as AutolysisQuestPaper
	_paper_instance = instance
	_line = 0
	_first_left_done = false
	_mechanical_count = mini(_task_contents.get_line_count(), int(_action_config["capacity"]))
	_bind_actor(actor)
	_set_effect(0, false)
	state = PrintState.PRINTING
	if not _paper.configure(self, accepted_serial, instance):
		_restore_start_failure(accepted_serial, "本次纸张入树前配置失败")
		if is_instance_valid(candidate) and not candidate.is_inside_tree():
			candidate.free()
		return false
	paper_anchor.add_child(candidate)
	if not _live(self):
		return false
	if not _print_context_valid(accepted_serial) or not focus_target.register_quest_paper(_paper, accepted_serial):
		_restore_start_failure(accepted_serial, "本次纸张建立或聚焦登记失败")
		return false
	_paper.tree_exiting.connect(_on_paper_exiting.bind(_paper, accepted_serial))
	_record(&"print_started")
	print_started.emit(accepted_serial)
	if not _print_context_valid(accepted_serial):
		return true
	if _live(print_button):
		print_button.play_press()
	if _print_context_valid(accepted_serial):
		_begin_motion(&"first_descent", horizontal_axis, _action_config["first"], float(_action_config["first_descent"]), accepted_serial)
	return true


func _restore_start_failure(serial: int, reason: String) -> void:
	if _serial != serial:
		return
	_kill_action()
	_cleanup_paper()
	last_failure_reason = reason
	_set_state(PrintState.PENDING)
	if _live(self) and state == PrintState.PENDING:
		_set_effect(0, true)


func _capture_action_configuration() -> Dictionary:
	return {"first": first_line_position, "minimum": minimum_line_y, "spacing": line_spacing, "capacity": int(floor((first_line_position.y - minimum_line_y) / line_spacing + 0.000001)) + 1, "axis_reset": axis_reset_position, "left": head_left_position, "right": head_right_position, "center": head_center_position, "first_descent": first_descent_seconds, "first_wait": first_wait_seconds, "first_left": first_left_seconds, "print_line": print_line_seconds, "return_left": return_left_seconds, "next_line": next_line_seconds, "center_time": center_seconds, "reset_time": reset_seconds}


func _begin_motion(phase: StringName, target: Node3D, destination: Vector3, seconds: float, serial: int) -> void:
	if not _action_context_valid(serial) or not _live(target):
		return
	_kill_action()
	_phase = phase
	_active_tween = _new_tween()
	_active_tween.tween_property(target, "position", destination, seconds)
	_active_tween.finished.connect(_on_action_finished.bind(serial, _action_id, phase))
	_record(&"action_started", phase)
	action_started.emit(serial, phase, _line)


func _begin_wait(serial: int) -> void:
	if not _print_context_valid(serial):
		return
	_kill_action()
	_phase = &"first_wait"
	_active_tween = _new_tween()
	_active_tween.tween_interval(float(_action_config["first_wait"]))
	_active_tween.finished.connect(_on_action_finished.bind(serial, _action_id, _phase))
	_record(&"action_started", _phase)
	action_started.emit(serial, _phase, _line)


func _new_tween() -> Tween:
	var tween: Tween = get_tree().create_tween().bind_node(timing_root)
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	tween.set_ignore_time_scale(false)
	tween.set_trans(Tween.TRANS_LINEAR)
	return tween


func _on_action_finished(serial: int, action: int, phase: StringName) -> void:
	if not _action_context_valid(serial) or action != _action_id or phase != _phase:
		return
	_active_tween = null
	_finished_pending = true
	if not _paused():
		_advance_finished_action(serial, action, phase)


func _advance_finished_action(serial: int, action: int, phase: StringName) -> void:
	if not _finished_pending or not _action_context_valid(serial) or action != _action_id or phase != _phase or _paused():
		return
	if not _completion_observed:
		_completion_observed = true
		_record(&"action_finished", phase)
		action_finished.emit(serial, phase, _line)
	if not _action_context_valid(serial) or action != _action_id or phase != _phase:
		return
	if _paused():
		return
	_finished_pending = false
	match phase:
		&"first_descent":
			_begin_wait(serial)
		&"first_wait", &"next_line":
			_process_line(serial)
		&"first_left":
			_first_left_done = true
			_begin_motion(&"print_line", print_head, _action_config["right"], float(_action_config["print_line"]), serial)
		&"print_line":
			if not _reveal_line(serial):
				return
			if _line < _mechanical_count - 1:
				_begin_motion(&"return_left", print_head, _action_config["left"], float(_action_config["return_left"]), serial)
			else:
				_begin_reset(serial)
		&"return_left":
			_next_line(serial)
		&"center":
			_begin_motion(&"axis_reset", horizontal_axis, _action_config["axis_reset"], float(_action_config["reset_time"]), serial)
		&"axis_reset":
			_complete_print(serial)
		&"cancel_center":
			_begin_motion(&"cancel_axis_reset", horizontal_axis, axis_reset_position, reset_seconds, serial)
		&"cancel_axis_reset":
			_finish_recovery(serial)


func _process_line(serial: int) -> void:
	if not _print_context_valid(serial):
		return
	if _task_contents.get_data_line(_line).is_empty():
		if not _reveal_line(serial):
			return
		if _line < _mechanical_count - 1:
			_next_line(serial)
		else:
			_begin_reset(serial)
	elif not _first_left_done:
		_begin_motion(&"first_left", print_head, _action_config["left"], float(_action_config["first_left"]), serial)
	else:
		_begin_motion(&"print_line", print_head, _action_config["right"], float(_action_config["print_line"]), serial)


func _reveal_line(serial: int) -> bool:
	if not _print_context_valid(serial) or not _paper.reveal_data_line(serial, _line):
		return false
	if not _print_context_valid(serial):
		return false
	_record(&"line_revealed")
	data_line_revealed.emit(serial, _line)
	return _print_context_valid(serial)


func _next_line(serial: int) -> void:
	if not _print_context_valid(serial):
		return
	_line += 1
	var destination: Vector3 = _action_config["first"]
	destination.y -= float(_line) * float(_action_config["spacing"])
	_begin_motion(&"next_line", horizontal_axis, destination, float(_action_config["next_line"]), serial)


func _begin_reset(serial: int) -> void:
	if not _print_context_valid(serial):
		return
	_set_state(PrintState.RESETTING)
	if _print_context_valid(serial):
		_begin_motion(&"center", print_head, _action_config["center"], float(_action_config["center_time"]), serial)


func _complete_print(serial: int) -> void:
	if not _print_context_valid(serial) or state != PrintState.RESETTING or _phase != &"axis_reset":
		return
	if not _paper.complete_print(serial) or not _print_context_valid(serial):
		return
	_phase = &""
	_set_state(PrintState.COMPLETE)
	if not _live(self) or _serial != serial or state != PrintState.COMPLETE:
		return
	_set_effect(1, true)
	_record(&"print_completed")
	print_completed.emit(serial)


func cancel_print(serial: int, reason: String) -> bool:
	if not _live(self) or serial != _serial or _take_token != 0 or state in [PrintState.IDLE, PrintState.RECOVERING, PrintState.WAITING_RECOVERY]:
		return false
	var old_serial: int = _serial
	_serial += 1
	_kill_action()
	last_failure_reason = reason
	_set_effect(0, false)
	_set_effect(1, false)
	_cleanup_paper()
	_task_contents = null
	state = PrintState.RECOVERING
	_record(&"print_cancelled")
	print_cancelled.emit(old_serial, reason)
	if not _live(self) or state != PrintState.RECOVERING:
		return true
	if not _recovery_dependencies_valid():
		_set_state(PrintState.WAITING_RECOVERY)
		return true
	_begin_motion(&"cancel_center", print_head, head_center_position, center_seconds, _serial)
	return true


func rebind_print_targets(axis: Node3D, head: Node3D) -> bool:
	if not _live(self) or _take_token != 0 or state not in [PrintState.IDLE, PrintState.WAITING_RECOVERY]:
		return false
	horizontal_axis = axis
	print_head = head
	if not _recovery_dependencies_valid():
		return false
	# 显式恢复只定位配置属性；不显示文本、不发布正常打印完成。
	horizontal_axis.position = axis_reset_position
	print_head.position = head_center_position
	_phase = &""
	_set_state(PrintState.IDLE)
	return true


func _recovery_dependencies_valid() -> bool:
	return _live(timing_root) and is_ancestor_of(timing_root) and _live(horizontal_axis) and _live(print_head) and horizontal_axis != print_head and is_ancestor_of(horizontal_axis) and is_ancestor_of(print_head) and head_center_position.is_finite() and axis_reset_position.is_finite() and is_finite(center_seconds) and center_seconds >= 0.0 and is_finite(reset_seconds) and reset_seconds >= 0.0


func _finish_recovery(serial: int) -> void:
	if serial != _serial or state != PrintState.RECOVERING:
		return
	_phase = &""
	_set_state(PrintState.IDLE)
	_disconnect_actor()
	_actor = null


func is_current_paper(paper: Variant, serial: int, instance: AutolysisItemInstance = null) -> bool:
	return _live(self) and _live(paper) and paper == _paper and serial == _serial and _paper_instance != null and (instance == null or instance == _paper_instance) and paper_anchor == paper.get_parent() and paper.matches_source(self, serial, _paper_instance)


func get_current_paper() -> AutolysisQuestPaper:
	return _paper if _live(_paper) else null


func get_print_serial() -> int:
	return _serial


func can_release_completed_paper(actor: Node3D, paper: AutolysisQuestPaper, serial: int, instance: AutolysisItemInstance) -> bool:
	return is_instance_valid(instance) and _take_token == 0 and state == PrintState.COMPLETE and is_current_paper(paper, serial, instance) and instance.is_valid_instance() and instance.is_quest_paper() and is_actor_focused(actor) and not _paused()


func begin_paper_take(actor: Node3D, paper: AutolysisQuestPaper, serial: int, instance: AutolysisItemInstance) -> int:
	if not can_release_completed_paper(actor, paper, serial, instance):
		return 0
	_take_counter += 1
	_take_token = _take_counter
	_take_actor = actor
	_take_paper = paper
	_take_instance = instance
	_take_serial = serial
	_take_committed = false
	_take_finished = false
	state = PrintState.TAKING
	return _take_token


func validate_paper_take(actor: Node3D, paper: AutolysisQuestPaper, serial: int, instance: AutolysisItemInstance, token: int) -> bool:
	if token <= 0 or token != _take_token or actor != _take_actor or paper != _take_paper or instance != _take_instance or serial != _take_serial or serial != _serial or state != PrintState.TAKING or _take_finished:
		return false
	if not _live(self) or not _live(paper) or paper.get_parent() != paper_anchor or not instance.is_valid_instance() or not paper.matches_source(self, serial, instance) or not is_actor_focused(actor) or _paused():
		return false
	return (_take_committed and _paper == null and _paper_instance == null) or (not _take_committed and is_current_paper(paper, serial, instance))


func commit_paper_take(actor: Node3D, paper: AutolysisQuestPaper, serial: int, instance: AutolysisItemInstance, token: int) -> bool:
	if _take_committed or not validate_paper_take(actor, paper, serial, instance, token):
		return false
	# 此同步段不释放来源、不停止待取表现、不发布观察，可按同一身份回滚。
	focus_target.unregister_quest_paper(paper, serial)
	_paper = null
	_paper_instance = null
	_take_committed = true
	return true


func rollback_paper_take(actor: Variant, paper: Variant, serial: int, instance: AutolysisItemInstance, token: int) -> bool:
	if token != _take_token or paper != _take_paper or actor != _take_actor or serial != _take_serial or instance != _take_instance or _take_finished:
		return false
	if _take_committed:
		if not _live(self) or not _live(paper) or serial != _serial:
			return false
		_paper = paper
		_paper_instance = instance
		_take_committed = false
		if _live(focus_target):
			focus_target.register_quest_paper(paper, serial)
	state = PrintState.COMPLETE
	return true


func finish_paper_take(actor: Node3D, paper: AutolysisQuestPaper, serial: int, instance: AutolysisItemInstance, token: int) -> bool:
	if not _take_committed or not validate_paper_take(actor, paper, serial, instance, token):
		return false
	_take_finished = true
	_task_contents = null
	state = PrintState.IDLE
	_set_effect(1, false)
	if _live(paper):
		paper.finish_pickup()
	# 世界模型隐藏会发布可见性通知；双方已提交后释放设备仍是成功获取。
	if not is_instance_valid(self) or is_queued_for_deletion():
		return true
	_record(&"paper_taken")
	paper_taken.emit(serial, instance)
	return true


func abort_paper_take(token: int) -> void:
	if token != _take_token or token <= 0:
		return
	if not _take_finished and _take_committed:
		rollback_paper_take(_take_actor, _take_paper, _take_serial, _take_instance, token)
	if not _take_finished and state == PrintState.TAKING:
		state = PrintState.COMPLETE
	_take_token = 0
	_take_actor = null
	_take_paper = null
	_take_instance = null
	_take_serial = 0
	_take_committed = false
	_take_finished = false


func is_actor_focused(actor: Node3D) -> bool:
	if not _live(actor) or not actor is AutolysisPlayer or not is_configured():
		return false
	var player: AutolysisPlayer = actor as AutolysisPlayer
	return player.is_focus_business_allowed() and _live(player.focus_controller) and player.focus_controller.is_focused_on(focus_target)


func _can_enter(actor: Node3D) -> bool:
	if not is_configured() or not _live(actor) or not actor is AutolysisPlayer:
		return false
	var player: AutolysisPlayer = actor as AutolysisPlayer
	return _live(player.focus_controller) and player.focus_controller.can_enter(focus_target)


func _on_entry_requested(actor: Node3D) -> void:
	if _can_enter(actor):
		(actor as AutolysisPlayer).focus_controller.try_enter(focus_target)


func _process(_delta: float) -> void:
	_sync_pause()
	_update_effect_dependencies()
	if state in [PrintState.PRINTING, PrintState.RESETTING] and not _print_context_valid(_serial):
		cancel_print(_serial, "打印必要目标、纸张或本次数据失效")
		return
	if state == PrintState.COMPLETE and not is_current_paper(_paper, _serial, _paper_instance):
		cancel_print(_serial, "完成纸张来源失效")
		return
	if state == PrintState.RECOVERING and not _recovery_dependencies_valid():
		_kill_action()
		_set_state(PrintState.WAITING_RECOVERY)
		return
	if _finished_pending and not _paused():
		_advance_finished_action(_serial, _action_id, _phase)
	elif not _phase.is_empty() and not _finished_pending and state in [PrintState.PRINTING, PrintState.RESETTING, PrintState.RECOVERING] and not _paused():
		if not is_instance_valid(_active_tween) or not _active_tween.is_valid() or not _active_tween.is_running():
			if state == PrintState.RECOVERING:
				_kill_action()
				_set_state(PrintState.WAITING_RECOVERY)
			else:
				cancel_print(_serial, "有限动作被外部停止或失效")


func _print_context_valid(serial: int) -> bool:
	return _live(self) and serial == _serial and state in [PrintState.PRINTING, PrintState.RESETTING] and _print_dependency_error().is_empty() and _task_contents != null and _task_contents.is_valid_contents() and is_current_paper(_paper, serial, _paper_instance) and _paper_instance.is_valid_instance()


func _action_context_valid(serial: int) -> bool:
	return (_print_context_valid(serial) or (_live(self) and serial == _serial and state == PrintState.RECOVERING and _recovery_dependencies_valid()))


func _kill_action() -> void:
	_action_id += 1
	_finished_pending = false
	_completion_observed = false
	if is_instance_valid(_active_tween):
		_active_tween.kill()
	_active_tween = null


func _cleanup_paper() -> void:
	var old_paper: Variant = _paper
	var old_serial: int = old_paper.print_serial if is_instance_valid(old_paper) else _serial - 1
	_paper = null
	_paper_instance = null
	if _live(focus_target) and old_paper != null:
		focus_target.unregister_quest_paper(old_paper, old_serial)
	if _live(old_paper):
		old_paper.queue_free()


func _on_paper_exiting(paper: AutolysisQuestPaper, serial: int) -> void:
	if not _live(self) or paper != _paper or serial != _serial:
		return
	if _take_token != 0:
		# 受保护事务由库存边界拒绝；解锁后拥有者负责来源异常清理。
		return
	cancel_print(serial, "本次任务纸张被外部释放")


func _set_state(next_state: PrintState) -> void:
	state = next_state
	_record(&"state_changed")
	state_changed.emit(_serial, state)


func _record(event: StringName, phase: StringName = &"") -> void:
	_events.append({"event": event, "serial": _serial, "state": state, "phase": phase, "line": _line, "physics_frame": Engine.get_physics_frames(), "ticks_usec": Time.get_ticks_usec(), "axis_position": horizontal_axis.position if _live(horizontal_axis) else null, "head_position": print_head.position if _live(print_head) else null})


func get_print_snapshot() -> Dictionary:
	return {"state": state, "serial": _serial, "line": _line, "mechanical_count": _mechanical_count, "phase": _phase, "first_left_done": _first_left_done, "finished_pending": _finished_pending, "take_token": _take_token, "failure": last_failure_reason, "config": _action_config.duplicate(true), "events": _events.duplicate(true)}


func _bind_actor(actor: Node3D) -> void:
	_disconnect_actor()
	_actor = actor
	if _live(_actor) and _actor.has_signal("dialogue_pause_changed"):
		_actor.connect("dialogue_pause_changed", _on_pause_changed)
	_sync_pause()


func _disconnect_actor() -> void:
	if is_instance_valid(_actor) and _actor.has_signal("dialogue_pause_changed") and _actor.is_connected("dialogue_pause_changed", _on_pause_changed):
		_actor.disconnect("dialogue_pause_changed", _on_pause_changed)


func _paused() -> bool:
	return get_tree().paused or (_live(_actor) and _actor.has_method("is_dialogue_timing_paused") and bool(_actor.call("is_dialogue_timing_paused")))


func _sync_pause() -> void:
	var local_pause: bool = _live(_actor) and _actor.has_method("is_dialogue_local_timing_paused") and bool(_actor.call("is_dialogue_local_timing_paused"))
	if _live(timing_root):
		timing_root.process_mode = Node.PROCESS_MODE_DISABLED if local_pause else Node.PROCESS_MODE_PAUSABLE
	for audio: Variant in [notice_player, scanning_player]:
		if _live(audio):
			audio.stream_paused = get_tree().paused or local_pause
	if _live(print_button):
		print_button.set_press_paused(get_tree().paused or local_pause)


func _on_pause_changed(_value: bool) -> void:
	_sync_pause()


func _initialize_effects() -> void:
	_materials.resize(2)
	_blinks.resize(2)
	_audio_copies.resize(2)
	for index: int in 2:
		var source: StandardMaterial3D = indicator_pending_material if index == 0 else indicator_completed_material
		if is_instance_valid(source):
			_materials[index] = source.duplicate() as StandardMaterial3D
		_set_effect(index, false)


func _set_effect(index: int, enabled: bool) -> void:
	_effect_active[index] = enabled
	if is_instance_valid(_blinks[index]):
		_blinks[index].kill()
	_blinks[index] = null
	var indicator: MeshInstance3D = pending_indicator if index == 0 else completed_indicator
	var player: AudioStreamPlayer3D = notice_player if index == 0 else scanning_player
	if _live(player):
		player.stop()
	if _live(indicator) and is_instance_valid(indicator_default_material):
		indicator.material_override = indicator_default_material
	if not enabled:
		return
	if _indicator_valid(index):
		var material: StandardMaterial3D = _materials[index]
		material.emission_energy_multiplier = indicator_emission_minimum
		indicator.material_override = material
		_blinks[index] = _new_tween()
		_blinks[index].set_loops()
		_blinks[index].tween_property(material, "emission_energy_multiplier", indicator_emission_maximum, indicator_half_cycle_seconds)
		_blinks[index].tween_property(material, "emission_energy_multiplier", indicator_emission_minimum, indicator_half_cycle_seconds)
	else:
		_effect_warning("提示灯%d配置失效；停止对应灯表现" % index)
	if _audio_player_valid(player):
		var stream: AudioStreamWAV = _copy_loop_stream(notice_stream if index == 0 else scanning_stream)
		_audio_copies[index] = stream
		if stream != null:
			player.stream = stream
			player.play()
			_sync_pause()
	else:
		_effect_warning("提示音%d播放器失效；停止对应声音表现" % index)


func _copy_loop_stream(source: AudioStreamWAV) -> AudioStreamWAV:
	if not is_instance_valid(source):
		_effect_warning("提示音资源失效")
		return null
	var stream: AudioStreamWAV = source.duplicate() as AudioStreamWAV
	if stream == null or not is_finite(stream.get_length()) or stream.get_length() <= 0.0 or stream.mix_rate <= 0:
		_effect_warning("提示音缺少有效完整采样长度")
		return null
	# 实際采样长度只配置循环端点，不决定任务、动作或取纸许可。
	stream.loop_begin = 0
	stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	if stream.loop_end <= 0:
		return null
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


func _indicator_valid(index: int) -> bool:
	var indicator: MeshInstance3D = pending_indicator if index == 0 else completed_indicator
	return _live(indicator) and is_ancestor_of(indicator) and indicator.mesh != null and is_instance_valid(indicator_default_material) and is_instance_valid(_materials[index]) and _live(timing_root) and is_finite(indicator_half_cycle_seconds) and indicator_half_cycle_seconds > 0.0 and is_finite(indicator_emission_minimum) and is_finite(indicator_emission_maximum) and indicator_emission_minimum >= 0.0 and indicator_emission_maximum >= indicator_emission_minimum


func _audio_player_valid(player: Variant) -> bool:
	return _live(player) and _live(timing_root) and timing_root.is_ancestor_of(player)


func _update_effect_dependencies() -> void:
	for index: int in 2:
		if not _effect_active[index]:
			continue
		var indicator: MeshInstance3D = pending_indicator if index == 0 else completed_indicator
		if is_instance_valid(_blinks[index]) and (not _indicator_valid(index) or indicator.material_override != _materials[index]):
			_blinks[index].kill()
			_blinks[index] = null
			_effect_warning("提示灯%d运行引用或材质失效；停止对应灯表现" % index)
		var player: AudioStreamPlayer3D = notice_player if index == 0 else scanning_player
		if _audio_copies[index] != null and (not _audio_player_valid(player) or player.stream != _audio_copies[index]):
			if _live(player):
				player.stop()
			_audio_copies[index] = null
			_effect_warning("提示音%d播放来源失效；停止对应声音表现" % index)


func _effect_warning(reason: String) -> void:
	if _reported_effect_errors.has(reason):
		return
	_reported_effect_errors[reason] = true
	push_warning(reason)


func _exit_tree() -> void:
	_serial += 1
	_kill_action()
	_disconnect_actor()
	for tween: Tween in _blinks:
		if is_instance_valid(tween):
			tween.kill()
	for player: Variant in [notice_player, scanning_player]:
		if is_instance_valid(player):
			player.stop()


func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
