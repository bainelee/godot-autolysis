class_name AutolysisLiquidTankCabinet
extends StaticBody3D
## 槽位登记与门动画分离；取放仍要求门完成打开并持有转移锁。

signal motion_completed(opened: bool)
signal motion_cancelled(reason: String)

enum DoorState { CLOSED, OPENING, OPEN, CLOSING, INTERRUPTED }

@export var slot_0: Node3D
@export var slot_1: Node3D
@export var door_body: AnimatableBody3D
@export var toggle_interaction: AutolysisInteractionComponent
@export var placement_body: StaticBody3D
@export var placement_interaction: AutolysisInteractionComponent
@export var animation_player: AnimationPlayer
@export var animation_name: StringName = &"open"

var state: DoorState = DoorState.CLOSED
var last_completed_transform: Transform3D = Transform3D.IDENTITY
var _items: Array[AutolysisLiquidTank] = []
var _configured: bool = false
var _transfer_busy: bool = false
var _motion_fault: String = ""
var _completion_pending: bool = false
var _motion_suspended: bool = false
var _stable_open: bool = false
var _sequence: int = 0
var _pending_sequence: int = 0
var _pending_frame: int = 0
var _pending_open: bool = false
var _pending_natural: bool = false
var _expected_direction: int = 0
var _bound_player: AnimationPlayer
var _bound_body: AnimatableBody3D
var _action_animation: Animation
var _advancing: bool = false
var _deferred_restore: bool = false
var _deferred_open: bool = false
var _deferred_rebind: bool = false
var _deferred_player: AnimationPlayer
var _deferred_pause: bool = false
var _restore_on_physics: bool = false
var _restore_requested_frame: int = 0
var _applying_restore: bool = false


func _ready() -> void:
	_items.resize(2)
	_protect_initial_sources()
	var error: String = _get_structure_error()
	if not error.is_empty():
		push_error("液体罐柜配置失败：%s；%s" % [get_path(), error])
		return
	if not _register_initial_items():
		return
	toggle_interaction.set_availability_check(can_toggle)
	toggle_interaction.set_execution_handler(_on_toggle_requested)
	placement_interaction.set_availability_check(_can_place_interact)
	placement_interaction.set_execution_handler(_on_place_requested)
	_configured = true
	rebind_animation_player(animation_player)


func _get_structure_error() -> String:
	if not _node_is_live(self):
		return "柜子未进入有效场景树"
	if not _node_is_live(slot_0) or not _node_is_live(slot_1) or slot_0 == slot_1 or not is_ancestor_of(slot_0) or not is_ancestor_of(slot_1):
		return "两个槽锚点必须有效、互异且归属于本柜"
	if not _node_is_live(door_body) or not is_ancestor_of(door_body):
		return "活动门体必须有效且归属于本柜"
	if not _node_is_live(placement_body) or not is_ancestor_of(placement_body):
		return "放置物理体必须有效且归属于本柜"
	if not _valid_component(door_body, toggle_interaction) or not _valid_component(placement_body, placement_interaction):
		return "门体和放置体必须各有一个直属直接交互组件"
	if _configured and (not toggle_interaction.has_execution_handler(_on_toggle_requested) or not placement_interaction.has_execution_handler(_on_place_requested)):
		return "柜门或放置业务执行绑定失效"
	return ""


func get_configuration_error() -> String:
	return _get_structure_error()


func get_motion_error() -> String:
	var error: String = _get_animation_error()
	return error if not error.is_empty() else _motion_fault


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty() and _storage_is_consistent()

func _get_animation_error() -> String:
	if not _node_is_live(door_body) or not door_body.sync_to_physics:
		return "盖子物理体或物理同步失效"
	if not _node_is_live(animation_player) or not is_ancestor_of(animation_player) or not animation_player.has_animation(animation_name):
		return "动画播放器或指定动画失效"
	if is_instance_valid(_bound_body) and door_body != _bound_body:
		return "活动物理体引用已更换，需要明确重新绑定"
	if is_animating() and _action_animation != null and animation_player.get_animation(animation_name) != _action_animation:
		return "本次动作动画资源已替换，需要明确重新绑定"
	if is_instance_valid(_bound_player) and animation_player != _bound_player:
		return "播放器引用已更换，需要明确重新绑定"
	if is_instance_valid(_bound_player) and animation_player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
		return "播放器已脱离拥有者的物理推进"
	if not animation_player.active or not is_finite(animation_player.speed_scale) or animation_player.speed_scale <= 0.0:
		return "动画必须启用并具有有效正速度倍率"
	if animation_player.process_mode != Node.PROCESS_MODE_INHERIT and animation_player.process_mode != Node.PROCESS_MODE_PAUSABLE:
		return "动画必须遵守场景暂停"
	if animation_player.get_animation(animation_name).loop_mode != Animation.LOOP_NONE:
		return "循环动画不能产生本次自然完成事件"
	if not animation_player.animation_get_next(animation_name).is_empty() or not animation_player.get_queue().is_empty():
		return "本次盖子动作不能被排队动作接管"
	return ""


func get_slot_count() -> int:
	return 2


func get_slot_node(index: int) -> Node3D:
	var slot: Node3D = slot_0 if index == 0 else slot_1 if index == 1 else null
	return slot if _node_is_live(slot) and is_ancestor_of(slot) else null


func get_item_at_slot(index: int) -> AutolysisLiquidTank:
	if index < 0 or index >= _items.size():
		return null
	var item: AutolysisLiquidTank = _items[index]
	return item if _node_is_live(item) else null


func find_first_empty_slot() -> int:
	if not is_configured():
		return -1
	for index: int in 2:
		if get_slot_node(index) != null and _items[index] == null:
			return index
	return -1


func owns_item(item: AutolysisLiquidTank) -> bool:
	if not _node_is_live(item) or not item.cabinet_stored or item.fixed_installation or item.cabinet != self or item.blend_stored or is_instance_valid(item.blend_place):
		return false
	var slot: Node3D = get_slot_node(item.slot_index)
	return slot != null and get_item_at_slot(item.slot_index) == item and item.get_parent() == slot


func can_accept_item(definition: AutolysisItemDefinition) -> bool:
	return _valid_definition(definition) and is_open() and find_first_empty_slot() >= 0


func is_open() -> bool:
	return is_configured() and get_motion_error().is_empty() and state == DoorState.OPEN and not _completion_pending and not animation_player.is_playing()


func is_animating() -> bool:
	return state == DoorState.OPENING or state == DoorState.CLOSING or _completion_pending


func can_toggle(actor: Node3D) -> bool:
	return _actor_is_valid(actor) and is_configured() and get_motion_error().is_empty() and not _transfer_busy and not is_animating() and not animation_player.is_playing() and (state == DoorState.CLOSED or state == DoorState.OPEN)


func try_toggle(actor: Node3D) -> bool:
	if not can_toggle(actor):
		return false
	_sequence += 1
	_action_animation = animation_player.get_animation(animation_name)
	_expected_direction = -1 if _stable_open else 1
	state = DoorState.CLOSING if _stable_open else DoorState.OPENING
	animation_player.play(animation_name, 0.0, float(_expected_direction), _stable_open)
	return true


func can_transfer(actor: Node3D, allow_busy: bool = false) -> bool:
	return _actor_is_valid(actor) and is_open() and (allow_busy or not _transfer_busy)


func try_begin_transfer(actor: Node3D) -> bool:
	if not can_transfer(actor):
		return false
	_transfer_busy = true
	return true


func end_transfer() -> void:
	_transfer_busy = false


func try_attach_prepared_item(index: int, item: AutolysisLiquidTank) -> bool:
	if not _transfer_busy or not is_open() or index < 0 or index >= 2 or _items[index] != null:
		return false
	if not is_instance_valid(item) or item.is_queued_for_deletion() or item.get_parent() != null or item.is_inside_tree():
		return false
	if not item.cabinet_stored or item.cabinet != self or item.slot_index != index or item.fixed_installation or not _valid_item_instance(item) or item.blend_stored or is_instance_valid(item.blend_place):
		return false
	var slot: Node3D = get_slot_node(index)
	if slot == null or not _live_slot_children(slot).is_empty():
		return false
	slot.add_child(item)
	# 候选初始化可改变配置；提交占用前重新核对身份和唯一子节点。
	if not is_instance_valid(self) or not _node_is_live(self) or not _configured or not get_configuration_error().is_empty() or not _transfer_busy or state != DoorState.OPEN or _items[index] != null:
		return false
	if not _node_is_live(item) or not _node_is_live(slot) or get_slot_node(index) != slot or item.get_parent() != slot or _live_slot_children(slot).size() != 1:
		return false
	if not item.cabinet_stored or item.cabinet != self or item.slot_index != index or item.fixed_installation or not _valid_item_instance(item) or item.blend_stored or is_instance_valid(item.blend_place):
		return false
	item.transform = Transform3D.IDENTITY
	_items[index] = item
	return true


func release_item(item: AutolysisLiquidTank) -> bool:
	if not _transfer_busy or not owns_item(item):
		return false
	_items[item.slot_index] = null
	item.cabinet = null
	item.slot_index = -1
	return true


func rollback_prepared_item(item: Variant) -> void:
	for index: int in _items.size():
		if _items[index] == item:
			_items[index] = null
	if is_instance_valid(item) and item is AutolysisLiquidTank and item.cabinet == self:
		item.cabinet = null
		item.slot_index = -1


func _register_initial_items() -> bool:
	var initial: Array[AutolysisLiquidTank] = []
	initial.resize(2)
	for index: int in 2:
		var slot: Node3D = get_slot_node(index)
		if slot.get_child_count() > 1:
			push_error("液体罐柜槽内存在多个对象，禁止覆盖：%s" % slot.get_path())
			return false
		if slot.get_child_count() == 0:
			continue
		var item: AutolysisLiquidTank = slot.get_child(0) as AutolysisLiquidTank
		if not _node_is_live(item) or item.fixed_installation or not item.cabinet_stored or item.cabinet != self or item.slot_index != index or not _valid_item_instance(item) or item.blend_stored or is_instance_valid(item.blend_place):
			push_error("液体罐柜初始槽内容或来源无效：%s" % slot.get_path())
			return false
		if initial.has(item):
			push_error("液体罐柜不能重复登记同一物体：%s" % slot.get_path())
			return false
		initial[index] = item
	for index: int in 2:
		var item: AutolysisLiquidTank = initial[index]
		if item != null:
			item.cabinet = self
			item.slot_index = index
			item.cabinet_stored = true
			_items[index] = item
	return true


## 配置失败也不能让柜内初始罐退回无主拾取；登记仍由完整校验决定。
func _protect_initial_sources() -> void:
	for index: int in 2:
		var slot: Node = slot_0 if index == 0 else slot_1
		if not is_instance_valid(slot):
			continue
		for child: Node in slot.get_children():
			var item: AutolysisLiquidTank = child as AutolysisLiquidTank
			if not is_instance_valid(item) or item.cabinet_stored or is_instance_valid(item.cabinet) or item.slot_index != -1:
				continue
			item.cabinet = self
			item.slot_index = index
			item.cabinet_stored = true


func _storage_is_consistent() -> bool:
	if _items.size() != 2:
		return false
	for index: int in 2:
		var slot: Node3D = get_slot_node(index)
		if slot == null:
			return false
		var item: AutolysisLiquidTank = _items[index]
		if item == null:
			if not _live_slot_children(slot).is_empty():
				return false
		elif not owns_item(item) or _live_slot_children(slot).size() != 1 or not _valid_definition(item.item_definition):
			return false
	return true


## 已提交拾取的排队来源不再占槽，允许同帧取回和再次放入。
func _live_slot_children(slot: Node3D) -> Array[Node]:
	var children: Array[Node] = []
	for child: Node in slot.get_children():
		if _node_is_live(child):
			children.append(child)
	return children


func _valid_definition(definition: AutolysisItemDefinition) -> bool:
	return is_instance_valid(definition) and definition.is_valid_definition() and not definition.is_raw_material and definition.item_id == &"liquid_tank"


func _valid_item_instance(item: AutolysisLiquidTank) -> bool:
	return is_instance_valid(item) and is_instance_valid(item.item_instance) and item.item_instance.is_valid_instance() and item.item_instance.definition == item.item_definition and _valid_definition(item.item_definition)


func suspend_motion() -> bool:
	if not is_animating() or _completion_pending or _motion_suspended or not is_configured():
		return false
	_motion_suspended = true
	# 播放器只由本拥有者手动推进，挂起无需停止原生播放或清动画缓存。
	return true


func resume_motion() -> bool:
	if not _motion_suspended or not is_configured():
		return false
	_motion_suspended = false
	return true


func cancel_motion(reason: String = "显式取消") -> bool:
	if not _configured or not _get_structure_error().is_empty() or not _get_animation_error().is_empty():
		_interrupt_motion(reason)
		return false
	_restore_stable(_stable_open)
	motion_cancelled.emit(reason)
	return true


func rebind_animation_player(player: AnimationPlayer) -> bool:
	if _advancing:
		_sequence += 1
		_completion_pending = true
		_motion_suspended = false
		_deferred_rebind = true
		_deferred_restore = false
		_deferred_player = player
		return true
	_deferred_rebind = false
	_deferred_restore = false
	_deferred_player = null
	_restore_on_physics = false
	_sequence += 1
	_completion_pending = false
	_motion_suspended = false
	if _node_is_live(_bound_player):
		if _bound_player.animation_finished.is_connected(_on_animation_finished):
			_bound_player.animation_finished.disconnect(_on_animation_finished)
		_bound_player.pause()
	animation_player = player
	_bound_player = null
	_bound_body = null
	_action_animation = null
	var error: String = _get_animation_error()
	if not error.is_empty():
		_interrupt_motion(error)
		return false
	_bound_player = player
	_bound_body = door_body
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_player.playback_auto_capture = false
	animation_player.animation_finished.connect(_on_animation_finished)
	_restore_stable(false)
	return true


func _restore_stable(opened: bool) -> void:
	_sequence += 1
	_motion_fault = ""
	_motion_suspended = false
	if _advancing:
		# 混合循环内不能更换动画库；先撤销旧许可，推进返回后再恢复。
		_completion_pending = true
		_deferred_restore = true
		_deferred_open = opened
		_deferred_rebind = false
		_deferred_player = null
		return
	_deferred_restore = false
	_action_animation = animation_player.get_animation(animation_name)
	if not _applying_restore:
		# 引用或碰撞刚修复时先经过物理同步，再由拥有者提交配置姿态。
		animation_player.pause()
		_restore_on_physics = true
		_restore_requested_frame = Engine.get_physics_frames()
		_deferred_open = opened
		_completion_pending = true
		return
	animation_player.stop(true)
	animation_player.assigned_animation = animation_name
	# 多属性完整应用后一次提交，保持物理同步；定位不重放事件轨道。
	door_body.set_notify_local_transform(false)
	_seek_properties(animation_player.get_animation(animation_name).length if opened else 0.0)
	_submit_applied_transform()
	animation_player.pause()
	_set_pending(opened, false)


func _set_pending(opened: bool, natural: bool) -> void:
	_completion_pending = true
	_pending_sequence = _sequence
	_pending_frame = Engine.get_physics_frames()
	_pending_open = opened
	_pending_natural = natural


func _physics_process(delta: float) -> void:
	if not _configured:
		return
	var error: String = _get_structure_error()
	if error.is_empty():
		error = _get_animation_error()
	if not error.is_empty():
		_interrupt_motion(error)
		return
	if not _motion_fault.is_empty():
		return
	if _restore_on_physics:
		if animation_player.is_playing():
			_interrupt_motion("恢复同步期间播放被外部接管")
		elif Engine.get_physics_frames() > _restore_requested_frame:
			_restore_on_physics = false
			_applying_restore = true
			_restore_stable(_deferred_open)
			_applying_restore = false
		return
	if _completion_pending:
		if _motion_suspended:
			return
		if animation_player.is_playing() or animation_player.assigned_animation != animation_name:
			_interrupt_motion("完成同步期间播放被外部接管")
			return
		if _pending_sequence != _sequence:
			_completion_pending = false
		elif Engine.get_physics_frames() > _pending_frame:
			last_completed_transform = door_body.transform
			_stable_open = _pending_open
			state = DoorState.OPEN if _stable_open else DoorState.CLOSED
			_completion_pending = false
			_expected_direction = 0
			_motion_suspended = false
			if _pending_natural:
				motion_completed.emit(_stable_open)
		return
	if not is_animating():
		if animation_player.is_playing():
			_interrupt_motion("稳定阶段播放被外部接管")
		return
	if not animation_player.is_playing() or animation_player.assigned_animation != animation_name or signf(animation_player.get_playing_speed()) != float(_expected_direction):
		_interrupt_motion("本次动作被外部停止、替换或改变方向")
		return
	if _motion_suspended:
		return
	var advancing_body: AnimatableBody3D = door_body
	var advancing_sequence: int = _sequence
	advancing_body.set_notify_local_transform(false)
	_advancing = true
	animation_player.advance(delta)
	if not is_instance_valid(self):
		return
	_advancing = false
	if is_instance_valid(advancing_body):
		advancing_body.set_notify_local_transform(true)
	if not _node_is_live(self):
		return
	if _deferred_pause:
		_deferred_pause = false
		if _node_is_live(_bound_player):
			_bound_player.pause()
	if _deferred_rebind:
		var requested_player: AnimationPlayer = _deferred_player
		rebind_animation_player(requested_player)
		return
	error = _get_structure_error()
	if error.is_empty():
		error = _get_animation_error()
	if not error.is_empty():
		_deferred_restore = false
		_interrupt_motion(error)
		return
	if _deferred_restore:
		_restore_stable(_deferred_open)
		return
	if advancing_sequence != _sequence:
		return
	_submit_applied_transform()


func _submit_applied_transform() -> void:
	var applied: Transform3D = door_body.transform
	door_body.set_notify_local_transform(true)
	door_body.transform = applied


func _on_animation_finished(finished_animation: StringName) -> void:
	if finished_animation != animation_name or not is_animating() or _completion_pending or (_motion_suspended and not _advancing) or not _motion_fault.is_empty():
		return
	_set_pending(state == DoorState.OPENING, true)


func _interrupt_motion(reason: String) -> void:
	if _motion_fault == reason:
		return
	_sequence += 1
	_motion_fault = reason
	_restore_on_physics = false
	_completion_pending = false
	_motion_suspended = false
	state = DoorState.INTERRUPTED
	if _node_is_live(_bound_player):
		if _advancing:
			_deferred_pause = true
		else:
			_bound_player.pause()
	motion_cancelled.emit(reason)


func _valid_component(body: PhysicsBody3D, component: AutolysisInteractionComponent) -> bool:
	if not _node_is_live(component) or component.get_parent() != body or component.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return false
	var count: int = 0
	for child: Node in body.get_children():
		if child is AutolysisInteractionComponent:
			count += 1
	return count == 1


func _actor_is_valid(actor: Node3D) -> bool:
	if not _node_is_live(actor) or get_tree().paused:
		return false
	return not actor is AutolysisPlayer or (actor as AutolysisPlayer).is_interaction_input_allowed()


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()


func _on_toggle_requested(actor: Node3D) -> void:
	try_toggle(actor)


func _can_place_interact(actor: Node3D) -> bool:
	if not _node_is_live(actor):
		return false
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	return is_instance_valid(inventory) and inventory.can_place_in_liquid_tank_cabinet(actor, self)


func _on_place_requested(actor: Node3D) -> void:
	if not _node_is_live(actor):
		return
	var inventory: AutolysisInventoryController = actor.get_node_or_null("InventoryController") as AutolysisInventoryController
	if is_instance_valid(inventory):
		inventory.try_place_in_liquid_tank_cabinet(actor, self)





## 独立属性副本消费引擎残留的开始标记；源资源的事件轨道保持原样。
func _seek_properties(time: float) -> void:
	var source: Animation = animation_player.get_animation(animation_name)
	var properties: Animation = source.duplicate()
	for track: int in properties.get_track_count():
		if properties.track_get_type(track) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION]:
			properties.track_set_enabled(track, false)
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(&"pose", properties)
	var library_name: StringName = &"__property_restore"
	while animation_player.has_animation_library(library_name):
		library_name = StringName(str(library_name) + "_")
	animation_player.add_animation_library(library_name, library)
	animation_player.assigned_animation = StringName(str(library_name) + "/pose")
	animation_player.seek(time, true, true)
	animation_player.assigned_animation = animation_name
	animation_player.seek(time, true, true)
	animation_player.remove_animation_library(library_name)
