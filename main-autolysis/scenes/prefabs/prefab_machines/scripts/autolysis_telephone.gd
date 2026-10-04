class_name AutolysisTelephone
extends StaticBody3D
## 电话拥有来源与限位；库存拥有独占显示。同步提交前逐项查询真实物理形状。

signal handset_taken(actor: Node3D, session: int)
signal handset_returned(actor: Node3D, session: int)
signal handset_aborted(actor: Node3D, session: int, reason: String)
signal limit_sync_observed(event: Dictionary)
signal state_changed()

@export var reference_camera: Camera3D
@export var root_interaction: AutolysisInteractionComponent
@export var focus_target: AutolysisFocusTarget
@export var handset_body: StaticBody3D
@export var handset_interaction: AutolysisInteractionComponent
@export var handset_anchor: Node3D
@export var handset_visual: Node3D
@export var handset_visual_scene: PackedScene
@export var move_limit_body: StaticBody3D
@export var move_limit_shape: CollisionShape3D
@export var additional_move_limit_shapes: Array[CollisionShape3D] = []
## 临时起值来自现有普通道具定义，最终值由用户调节记录确定。
@export var handset_held_position: Vector3 = Vector3(0.24, -0.23, -0.48)
@export var handset_held_rotation_degrees: Vector3 = Vector3(-8, -18, 12)
@export var handset_held_scale: Vector3 = Vector3.ONE

var _configured: bool = false
var _holder: Node3D
var _holder_session: int = 0
var _transfer_actor: AutolysisPlayer
var _transfer_inventory: AutolysisInventoryController
var _transfer_token: int = 0
var _transfer_focus_session: int = 0
var _transfer_is_return: bool = false
var _transfer_restoring: bool = false
var _return_holder_session: int = 0
var _limit_revision: int = 0
var _limit_target_enabled: bool = false
var _limit_write_applied: int = -1
var _limit_cleanup_pending: bool = false
var _guard_actor: AutolysisPlayer
var _guard_serial: int = 0
var last_limit_recovery_reason: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(root_interaction):
		root_interaction.is_enabled = false
	if is_instance_valid(handset_interaction):
		handset_interaction.is_enabled = false
	if not get_configuration_error().is_empty():
		push_error("电话核心登记无效：%s；%s" % [get_path(), get_configuration_error()])
		return
	root_interaction.set_availability_check(_can_enter)
	root_interaction.set_execution_handler(_on_entry_requested)
	handset_interaction.set_availability_check(_can_transfer_interact)
	handset_interaction.set_execution_handler(_on_handset_requested)
	if not focus_target.configure_telephone(self, reference_camera, root_interaction, handset_body, handset_interaction):
		push_error("电话聚焦登记失败：%s" % get_path())
		return
	_configured = true
	root_interaction.is_enabled = true
	handset_interaction.is_enabled = true
	_request_limit(false)


func get_configuration_error() -> String:
	if not _live(self):
		return "电话物理根无效"
	if not _live(reference_camera) or not is_ancestor_of(reference_camera):
		return "参照相机必须属于电话"
	if not _live(root_interaction) or root_interaction.get_parent() != self or root_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.FOCUS:
		return "根聚焦组件必须直属电话物理根"
	if not _live(focus_target) or focus_target.get_parent() != self:
		return "聚焦描述必须直属电话物理根"
	if not _live(handset_body) or not is_ancestor_of(handset_body) or handset_body.collision_layer != 32:
		return "听筒物理入口必须归属本电话并使用聚焦内部层"
	if not _live(handset_interaction) or handset_interaction.get_parent() != handset_body or handset_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT:
		return "听筒直接组件必须直属登记物理入口"
	if _configured and (not root_interaction.has_execution_handler(_on_entry_requested) or not handset_interaction.has_execution_handler(_on_handset_requested)):
		return "电话缺少本设备唯一业务执行绑定"
	return ""


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty() and focus_target.is_valid_target()


func is_actor_focused(actor: Node3D) -> bool:
	return _live(actor) and actor is AutolysisPlayer and _live(actor.focus_controller) and actor.is_focus_business_allowed() and actor.focus_controller.is_focused_on(focus_target)


func is_transfer_pending() -> bool:
	return _transfer_token > 0 or _limit_cleanup_pending


func get_holder() -> Node3D:
	return _holder if _live(_holder) else null


func get_holder_session_id() -> int:
	return _holder_session


func owns_handset(actor: Node3D, session: int) -> bool:
	return _live(self) and _live(actor) and _holder == actor and session > 0 and _holder_session == session


func is_committed_handset_valid(actor: Node3D, session: int) -> bool:
	return owns_handset(actor, session) and _visual_dependencies_valid() and _limit_dependencies_valid() and _actor_limit_mask_valid(actor) and _limit_matches(true)


func get_move_limit_shapes() -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	if is_instance_valid(move_limit_shape):
		shapes.append(move_limit_shape)
	for shape: Variant in additional_move_limit_shapes:
		if is_instance_valid(shape):
			shapes.append(shape)
	return shapes


func can_take_handset(actor: Node3D) -> bool:
	if not is_configured() or is_transfer_pending() or is_instance_valid(_holder) or not is_actor_focused(actor):
		return false
	if not _visual_dependencies_valid() or not _limit_dependencies_valid() or not _actor_limit_mask_valid(actor):
		return false
	var inventory: AutolysisInventoryController = _inventory_of(actor)
	return _live(inventory) and inventory.can_take_handset(actor, self)


func can_return_handset(actor: Node3D) -> bool:
	if not is_configured() or is_transfer_pending() or not is_actor_focused(actor) or not owns_handset(actor, _holder_session):
		return false
	# 已失效的限位不阻止仍可安全完成的原来源归还。
	var inventory: AutolysisInventoryController = _inventory_of(actor)
	return _visual_dependencies_valid() and _live(inventory) and inventory.can_return_handset(actor, self)


func request_handset_transfer(actor: Node3D) -> bool:
	var returning: bool = can_return_handset(actor)
	if not returning and not can_take_handset(actor):
		return false
	var inventory: AutolysisInventoryController = _inventory_of(actor)
	var token: int = inventory.begin_handset_return(actor, self) if returning else inventory.begin_handset_take(actor, self, handset_visual_scene, handset_held_position, handset_held_rotation_degrees, handset_held_scale)
	if not _live(self):
		return false
	if token <= 0 or not _live(actor) or not _live(inventory):
		return false
	if not _live(actor.focus_controller):
		# 库存准备期间失去聚焦时，物理目标尚未改变，可立即撤销本次预处理。
		inventory.cancel_handset_transfer(self, token)
		return false
	_transfer_actor = actor as AutolysisPlayer
	_transfer_inventory = inventory
	_transfer_token = token
	_transfer_focus_session = _transfer_actor.focus_controller.session_id
	_transfer_is_return = returning
	_return_holder_session = _holder_session
	_transfer_restoring = false
	last_limit_recovery_reason = "" if not returning or _limit_dependencies_valid() else "归还预处理已失效限位；逐项停用残存形状并确认实际物理移除"
	_request_limit(not returning, _transfer_actor)
	return true


func cancel_handset_transfer() -> void:
	if _transfer_token <= 0 or _transfer_restoring:
		return
	# 库存已完成成对提交后，观察通知中的取消不能撤销成功状态或重新启用归还边界。
	if _live(_transfer_inventory) and not _transfer_inventory.get_handset_transfer_pending():
		if not _transfer_is_return and _transfer_inventory.get_handset_source() == self and _transfer_inventory.get_handset_session_id() == _transfer_token:
			return
		if _transfer_is_return and _holder_session == 0 and _transfer_inventory.get_handset_session_id() == 0:
			return
	_transfer_restoring = true
	_request_limit(_transfer_is_return and _return_holder_session > 0, _transfer_actor)


func _physics_process(_delta: float) -> void:
	if _transfer_token > 0:
		_poll_transfer()
	elif _limit_cleanup_pending:
		if _limit_write_applied == _limit_revision and _limit_matches(false):
			_limit_cleanup_pending = false
			_clear_movement_guard()
	elif _holder_session > 0:
		var inventory: AutolysisInventoryController = _inventory_of(_holder)
		if not _live(_holder) or not _live(inventory) or not _visual_dependencies_valid() or not _limit_dependencies_valid() or not _actor_limit_mask_valid(_holder) or not _limit_matches(true):
			if _live(inventory):
				inventory.abort_handset_session(self, _holder_session, "电话持筒必要依赖失效")
			else:
				abort_handset_holder(_holder, _holder_session, "电话持有玩家或库存离树")


func _poll_transfer() -> void:
	if not _live(_transfer_actor) or not _live(_transfer_inventory):
		abort_handset_holder(_transfer_actor, _return_holder_session if _transfer_is_return else _transfer_token, "电话预处理玩家或库存失效")
		return
	if _transfer_restoring and _transfer_is_return and _return_holder_session > 0 and (not _visual_dependencies_valid() or not _limit_dependencies_valid() or not _actor_limit_mask_valid(_transfer_actor)):
		# 取消归还要恢复原持有；必要边界已无法恢复时，不能永久等待一个无效启用目标。
		_transfer_inventory.abort_handset_session(self, _return_holder_session, "归还取消恢复期间必要持有依赖失效")
		return
	if not _transfer_restoring:
		var paused_input: bool = get_tree().paused or _transfer_actor.is_movement_paused or _transfer_actor.is_showing_ui
		if not _live(_transfer_actor.focus_controller) or _transfer_actor.focus_controller.session_id != _transfer_focus_session or not _transfer_actor.focus_controller.is_focused_on(focus_target):
			cancel_handset_transfer()
		elif not paused_input and not _transfer_inventory.is_handset_transfer_current(_transfer_actor, self, _transfer_token):
			cancel_handset_transfer()
		elif not _visual_dependencies_valid() or (not _transfer_is_return and (not _limit_dependencies_valid() or not _actor_limit_mask_valid(_transfer_actor))):
			cancel_handset_transfer()
	if _limit_write_applied != _limit_revision or not _limit_matches(_limit_target_enabled):
		return
	var observed_token: int = _transfer_token
	var observed_revision: int = _limit_revision
	var observed_actor: AutolysisPlayer = _transfer_actor
	var observed_inventory: AutolysisInventoryController = _transfer_inventory
	_emit_sync("真实物理目标已确认")
	if not _live(self) or _transfer_token != observed_token or _limit_revision != observed_revision or _transfer_actor != observed_actor or _transfer_inventory != observed_inventory or not _live(observed_actor) or not _live(observed_inventory):
		return
	if _transfer_restoring:
		_transfer_inventory.cancel_handset_transfer(self, _transfer_token)
		if _live(self) and _transfer_token == observed_token:
			_finish_transfer()
		return
	# 暂停只保留预处理；恢复后再复核正常业务许可。
	if get_tree().paused or _transfer_actor.is_movement_paused or _transfer_actor.is_showing_ui:
		return
	if not is_actor_focused(_transfer_actor):
		cancel_handset_transfer()
		return
	var actor: AutolysisPlayer = _transfer_actor
	var token: int = _transfer_token
	var success: bool
	if _transfer_is_return:
		success = _transfer_inventory.commit_handset_return(actor, self, token, _commit_returned.bind(actor, token), _rollback_returned.bind(actor, token), _notify_returned.bind(actor, _return_holder_session))
	else:
		success = _transfer_inventory.commit_handset_take(actor, self, token, _commit_taken.bind(actor, token), _rollback_taken.bind(actor, token), _notify_taken.bind(actor, token))
	if not _live(self) or token != _transfer_token:
		return
	if success:
		_finish_transfer()
	else:
		cancel_handset_transfer()


func _commit_taken(actor: Variant, token: int) -> bool:
	if token != _transfer_token or _transfer_is_return or _transfer_restoring or not _live(actor) or not _visual_dependencies_valid() or _holder_session != 0 or not _limit_matches(true) or not _actor_limit_mask_valid(actor):
		return false
	var revision: int = _limit_revision
	_holder = actor
	_holder_session = token
	handset_visual.visible = false
	# 可见性通知也是同步可调用边界；取消、异常清理或释放不能伪报来源提交成功。
	return _live(self) and _live(actor) and token == _transfer_token and revision == _limit_revision and not _transfer_restoring and _limit_target_enabled and _holder == actor and _holder_session == token and _visual_dependencies_valid() and _limit_dependencies_valid() and _actor_limit_mask_valid(actor) and _limit_matches(true)


func _rollback_taken(actor: Variant, token: int) -> void:
	if token != _transfer_token or _transfer_is_return:
		return
	if _holder == actor and _holder_session == token:
		_holder = null
		_holder_session = 0
	if _live(handset_visual) and _holder_session == 0:
		handset_visual.visible = true


func _commit_returned(actor: Variant, token: int) -> bool:
	if token != _transfer_token or not _transfer_is_return or _transfer_restoring or not _live(actor) or not owns_handset(actor, _return_holder_session) or not _visual_dependencies_valid() or not _limit_matches(false):
		return false
	var revision: int = _limit_revision
	_holder = null
	_holder_session = 0
	handset_visual.visible = true
	return _live(self) and _live(actor) and token == _transfer_token and revision == _limit_revision and not _transfer_restoring and not _limit_target_enabled and _holder == null and _holder_session == 0 and _visual_dependencies_valid() and _limit_matches(false)


func _rollback_returned(actor: Variant, token: int) -> void:
	if token != _transfer_token or not _transfer_is_return:
		return
	if not _live(actor):
		abort_handset_holder(actor, _return_holder_session, "归还回滚玩家已经失效")
		return
	_holder = actor
	_holder_session = _return_holder_session
	if _live(handset_visual):
		handset_visual.visible = false


func _notify_taken(actor: Variant, session: int) -> void:
	if not _live(actor) or not owns_handset(actor, session):
		return
	if not is_committed_handset_valid(actor, session):
		var inventory: AutolysisInventoryController = _inventory_of(actor)
		if _live(inventory):
			inventory.abort_handset_session(self, session, "取下完成观察前电话必要依赖已经失效")
		return
	handset_taken.emit(actor, session)
	if _live(self):
		state_changed.emit()


func _notify_returned(actor: Variant, session: int) -> void:
	if not _live(actor):
		return
	if not _limit_matches(false):
		_limit_cleanup_pending = true
		last_limit_recovery_reason = "归还完成观察前限位被重新启用，继续安全停用残存形状"
		_request_limit(false, actor as AutolysisPlayer)
		return
	handset_returned.emit(actor, session)
	if _live(self):
		state_changed.emit()


func abort_handset_holder(actor: Variant, session: int, reason: String) -> void:
	var matches_holder: bool = _holder == actor and _holder_session == session and session > 0
	var matches_take: bool = not _transfer_is_return and _transfer_actor == actor and _transfer_token == session and session > 0
	var matches_return: bool = _transfer_is_return and _transfer_actor == actor and _return_holder_session == session and session > 0
	if not matches_holder and not matches_take and not matches_return:
		return
	_holder = null
	_holder_session = 0
	_transfer_token = 0
	_transfer_actor = null
	_transfer_inventory = null
	_transfer_restoring = false
	if _live(handset_visual):
		handset_visual.visible = true
	if is_inside_tree() and not is_queued_for_deletion():
		_limit_cleanup_pending = true
		_request_limit(false, actor as AutolysisPlayer if _live(actor) else null)
	else:
		# 来源离树的物理移除由引擎完成，玩家保护租约也在来源真正离树后解除。
		_limit_revision += 1
	if _live(self):
		handset_aborted.emit(actor if _live(actor) else null, session, reason)
		if _live(self):
			state_changed.emit()


func _finish_transfer() -> void:
	_transfer_token = 0
	_transfer_actor = null
	_transfer_inventory = null
	_transfer_restoring = false
	if not _limit_cleanup_pending:
		_clear_movement_guard()


func _request_limit(enabled: bool, actor: AutolysisPlayer = null) -> void:
	_limit_revision += 1
	_limit_target_enabled = enabled
	_limit_write_applied = -1
	if _live(actor):
		_guard_actor = actor
		_guard_serial = _limit_revision
		actor.set_handset_collision_guard(self, _guard_serial, true)
	_apply_limit_target.call_deferred(_limit_revision, enabled)


func _apply_limit_target(revision: int, enabled: bool) -> void:
	if not _live(self) or revision != _limit_revision:
		return
	for shape: CollisionShape3D in _owned_limit_shapes():
		shape.set_deferred("disabled", not enabled)
	_limit_property_written.call_deferred(revision)
	_emit_sync("延后属性写入已请求")


func _limit_property_written(revision: int) -> void:
	if not _live(self) or revision != _limit_revision:
		return
	_limit_write_applied = revision
	_emit_sync("延后属性写入已执行")


func _clear_movement_guard() -> void:
	if _live(_guard_actor):
		_guard_actor.set_handset_collision_guard(self, _guard_serial, false)
	_guard_actor = null
	_guard_serial = 0


## 逐项使用来源物理身份与形状拥有者确认真实世界；固定帧数不参与许可。
func _limit_matches(enabled: bool) -> bool:
	if enabled and not _limit_dependencies_valid():
		return false
	if not _live(move_limit_body):
		return not enabled
	for shape: CollisionShape3D in _owned_limit_shapes():
		if shape.disabled == enabled or _shape_is_active_in_world(shape) != enabled:
			return false
	return true


func _shape_is_active_in_world(shape: CollisionShape3D) -> bool:
	if not _live(shape) or shape.shape == null or not _live(move_limit_body):
		return false
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = move_limit_body.collision_layer
	return _shape_query_hits_body(query, move_limit_body, shape)


func _owned_limit_shapes() -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	if _live(move_limit_body):
		for child: Node in move_limit_body.get_children():
			if _live(child) and child is CollisionShape3D and child.shape != null:
				shapes.append(child)
	return shapes


func _limit_dependencies_valid() -> bool:
	if not _live(move_limit_body) or not is_ancestor_of(move_limit_body) or move_limit_body.collision_layer != 8:
		return false
	if not _live(move_limit_shape) or additional_move_limit_shapes.size() + 1 != _owned_limit_shapes().size():
		return false
	var registered: Array[CollisionShape3D] = get_move_limit_shapes()
	var seen: Dictionary = {}
	for shape: CollisionShape3D in registered:
		if not _live(shape) or shape.get_parent() != move_limit_body or shape.shape == null or seen.has(shape):
			return false
		seen[shape] = true
	return registered.size() == additional_move_limit_shapes.size() + 1


func _visual_dependencies_valid() -> bool:
	return _live(handset_anchor) and is_ancestor_of(handset_anchor) and _live(handset_visual) and handset_anchor.is_ancestor_of(handset_visual) and is_instance_valid(handset_visual_scene) and handset_visual_scene.can_instantiate()


## 排除已检查的其他物理体再查，避免默认返回容量截断来源物理身份。
func _shape_query_hits_body(query: PhysicsShapeQueryParameters3D, body: PhysicsBody3D, shape_owner: Node) -> bool:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	while true:
		var hits: Array[Dictionary] = space.intersect_shape(query)
		var exclusions: Array[RID] = query.exclude
		var added_exclusion: bool = false
		for hit: Dictionary in hits:
			var body_rid: RID = hit.get("rid", RID())
			if body_rid == body.get_rid():
				var owner_id: int = body.shape_find_owner(int(hit.get("shape", -1)))
				if body.shape_owner_get_owner(owner_id) == shape_owner:
					return true
			elif not exclusions.has(body_rid):
				exclusions.append(body_rid)
				added_exclusion = true
		if not added_exclusion:
			return false
		query.exclude = exclusions
	return false


func _actor_limit_mask_valid(actor: Node3D) -> bool:
	return _live(actor) and actor is PhysicsBody3D and _live(move_limit_body) and (actor.collision_mask & move_limit_body.collision_layer) != 0


func _can_enter(actor: Node3D) -> bool:
	return is_configured() and not is_transfer_pending() and _live(actor) and actor is AutolysisPlayer and _live(actor.focus_controller) and actor.focus_controller.can_enter(focus_target)


func _on_entry_requested(actor: Node3D) -> void:
	if _can_enter(actor):
		actor.focus_controller.try_enter(focus_target)


func _can_transfer_interact(actor: Node3D) -> bool:
	return can_take_handset(actor) or can_return_handset(actor)


func _on_handset_requested(actor: Node3D) -> void:
	request_handset_transfer(actor)


func _inventory_of(actor: Variant) -> AutolysisInventoryController:
	return actor.get_node_or_null("InventoryController") as AutolysisInventoryController if _live(actor) else null


func _emit_sync(event: String) -> void:
	var shapes: Array[Dictionary] = []
	for shape: CollisionShape3D in _owned_limit_shapes():
		shapes.append({"形状": str(shape.get_path()), "停用": shape.disabled, "真实物理启用": _shape_is_active_in_world(shape)})
	limit_sync_observed.emit({"事件": event, "物理帧": Engine.get_physics_frames(), "普通帧": Engine.get_process_frames(), "限位序号": _limit_revision, "事务序号": _transfer_token, "目标启用": _limit_target_enabled, "形状": shapes})


func _exit_tree() -> void:
	_limit_revision += 1
	var inventory: AutolysisInventoryController = _transfer_inventory if is_instance_valid(_transfer_inventory) else _inventory_of(_holder)
	if _live(inventory):
		inventory.abort_handset_session(self, _holder_session if _holder_session > 0 else _transfer_token, "电话来源离树")


func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
