class_name AutolysisQuestBoardSlot
extends StaticBody3D
## 槽位只保存逐件来源；库存控制器决定双方的最终提交点。

signal state_changed

const QUEST_PAPER_VISUAL: Script = preload("res://main-autolysis/systems/item-system/autolysis_quest_paper_visual.gd")

enum TransferStage { NONE, PLACE, TAKE }

@export var collision_shape: CollisionShape3D
@export var transfer_interaction: AutolysisInteractionComponent
@export var paper_position: Vector3 = Vector3.ZERO
@export var paper_rotation_degrees: Vector3 = Vector3.ZERO
@export var paper_scale: Vector3 = Vector3.ONE

var _board: AutolysisQuestBoard
var _focus_target: AutolysisFocusTarget
var _configured: bool = false
var _stored_instance: AutolysisItemInstance
var _display: Node3D
var _watched_instance: AutolysisItemInstance
var _revision: int = 0
var _transfer_serial: int = 0
var _transfer_token: int = 0
var _transfer_actor: Node3D
var _transfer_inventory: AutolysisInventoryController
var _transfer_stage: TransferStage = TransferStage.NONE
var _transfer_original_instance: AutolysisItemInstance
var _transfer_original_display: Node3D
var _transfer_original_visible: bool = false
var _transfer_candidate: Node3D
var _transfer_candidate_instance: AutolysisItemInstance
var _transfer_committed: bool = false


func configure(board: AutolysisQuestBoard, target: AutolysisFocusTarget) -> bool:
	if _configured:
		return _board == board and _focus_target == target and is_configured()
	_board = board
	_focus_target = target
	_configured = true
	if _node_is_live(transfer_interaction):
		transfer_interaction.set_availability_check(_can_transfer_interact)
		transfer_interaction.set_execution_handler(_on_transfer_requested)
	return is_configured()


func get_configuration_error() -> String:
	if not _configured or not _node_is_live(self):
		return "任务文件槽未配置或不在有效场景树中"
	if not _node_is_live(_board) or not _board.is_ancestor_of(self) or not _board.owns_slot(self):
		return "任务文件槽未归属于显式登记的任务板"
	if not _node_is_live(_focus_target) or _board.focus_target != _focus_target or not _board.is_ancestor_of(_focus_target):
		return "任务文件槽聚焦描述归属无效"
	if not _node_is_live(collision_shape) or collision_shape.get_parent() != self or collision_shape.shape == null or collision_shape.disabled:
		return "任务文件槽碰撞形状未绑定、失效或不直属本槽"
	if not _node_is_live(transfer_interaction) or transfer_interaction.get_parent() != self:
		return "任务文件槽取放组件未绑定或不直属本槽"
	var component_count: int = 0
	for child: Node in get_children():
		if child is AutolysisInteractionComponent:
			component_count += 1
	if component_count != 1 or transfer_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.DIRECT or not transfer_interaction.has_execution_handler(_on_transfer_requested):
		return "任务文件槽必须具有唯一直属直接交互组件及本槽执行入口"
	return ""


func is_configured() -> bool:
	return get_configuration_error().is_empty()


func get_board() -> AutolysisQuestBoard:
	return _board if _node_is_live(_board) else null


func get_focus_target() -> AutolysisFocusTarget:
	return _focus_target if _node_is_live(_focus_target) else null


func get_anchor() -> Node3D:
	return self if _node_is_live(self) else null


func get_revision() -> int:
	return _revision


func get_stored_instance() -> AutolysisItemInstance:
	return _stored_instance


func get_display() -> Node3D:
	return _display if _display_is_live(_display) else null


func is_occupied() -> bool:
	return _stored_instance != null


func can_transfer(actor: Variant, allow_busy: bool = false) -> bool:
	return _node_is_live(actor) and actor is Node3D and is_configured() and (allow_busy or _transfer_token == 0) and _board.is_actor_focused(actor)


func begin_transfer(actor: Node3D, inventory: AutolysisInventoryController) -> int:
	if not can_transfer(actor) or not _node_is_live(inventory) or not actor is AutolysisPlayer:
		return 0
	if (actor as AutolysisPlayer).inventory_controller != inventory:
		return 0
	_transfer_serial += 1
	_transfer_token = _transfer_serial
	_transfer_actor = actor
	_transfer_inventory = inventory
	_transfer_original_instance = _stored_instance
	_transfer_original_display = get_display()
	_transfer_original_visible = _transfer_original_display.visible if _transfer_original_display != null else false
	_transfer_stage = TransferStage.NONE
	_transfer_committed = false
	return _transfer_token


## 令牌只能由发起它的玩家及库存使用；查询不变更互斥或占用。
func is_transfer_current(actor: Variant, inventory: Variant, token: int) -> bool:
	return token > 0 and token == _transfer_token and actor == _transfer_actor and inventory == _transfer_inventory


func prepare_visual(instance: AutolysisItemInstance) -> Node3D:
	if not is_instance_valid(instance) or not instance.is_valid_instance() or not instance.is_quest_paper():
		return null
	if not paper_position.is_finite() or not paper_rotation_degrees.is_finite() or not paper_scale.is_finite():
		return null
	var scene: PackedScene = instance.definition.visual_scene
	if scene == null or not scene.can_instantiate():
		return null
	var candidate: Node = scene.instantiate()
	if not candidate is Node3D or not _is_display_only(candidate):
		if is_instance_valid(candidate):
			candidate.free()
		return null
	var visual: Node3D = candidate as Node3D
	visual.position = paper_position
	visual.rotation_degrees = paper_rotation_degrees
	visual.scale = paper_scale
	if not QUEST_PAPER_VISUAL.apply_instance(visual, instance):
		if is_instance_valid(visual):
			visual.free()
		return null
	return visual


func attach_prepared_visual(actor: Node3D, inventory: AutolysisInventoryController, token: int, visual: Node3D, instance: AutolysisItemInstance) -> bool:
	if not is_transfer_current(actor, inventory, token) or not can_transfer(actor, true) or _transfer_stage != TransferStage.NONE or _stored_instance != null or _transfer_candidate != null:
		return false
	if not _display_is_live(visual, false) or visual.get_parent() != null or QUEST_PAPER_VISUAL.get_instance(visual) != instance:
		return false
	_transfer_candidate = visual
	_transfer_candidate_instance = instance
	visual.hide()
	if not is_instance_valid(self) or not _display_is_live(visual, false):
		return false
	add_child(visual)
	if not is_instance_valid(self):
		return false
	return is_transfer_current(actor, inventory, token) and can_transfer(actor, true) and _candidate_matches(visual, instance)


func stage_place(actor: Node3D, inventory: AutolysisInventoryController, token: int, visual: Node3D, instance: AutolysisItemInstance) -> bool:
	if not is_transfer_current(actor, inventory, token) or not can_transfer(actor, true) or _transfer_stage != TransferStage.NONE or _stored_instance != null or not _candidate_matches(visual, instance):
		return false
	_transfer_stage = TransferStage.PLACE
	_stored_instance = instance
	_display = visual
	_watch_instance(instance)
	var applied: bool = _refresh_stored_visual()
	if not is_instance_valid(self) or not applied or not _display_is_live(visual):
		return false
	visual.show()
	if not is_instance_valid(self):
		return false
	return can_finalize_transfer(actor, inventory, token)


func stage_take(actor: Node3D, inventory: AutolysisInventoryController, token: int, instance: AutolysisItemInstance) -> bool:
	if not is_transfer_current(actor, inventory, token) or not can_transfer(actor, true) or _transfer_stage != TransferStage.NONE or _stored_instance != instance or _transfer_original_instance != instance:
		return false
	var previous: Node3D = get_display()
	if previous != null and (previous.get_parent() != self or QUEST_PAPER_VISUAL.get_instance(previous) != instance):
		return false
	_transfer_stage = TransferStage.TAKE
	_stored_instance = null
	_display = null
	if previous != null:
		previous.hide()
	if not is_instance_valid(self):
		return false
	return can_finalize_transfer(actor, inventory, token)


func can_finalize_transfer(actor: Variant, inventory: Variant, token: int) -> bool:
	if not is_transfer_current(actor, inventory, token) or _transfer_committed or not _node_is_live(actor) or not _node_is_live(inventory) or not can_transfer(actor, true):
		return false
	if _transfer_stage == TransferStage.PLACE:
		return _transfer_original_instance == null and _stored_instance == _transfer_candidate_instance and _display == _transfer_candidate and _candidate_matches(_display, _stored_instance)
	if _transfer_stage == TransferStage.TAKE:
		if _stored_instance != null or _display != null or not is_instance_valid(_transfer_original_instance):
			return false
		return not _display_is_live(_transfer_original_display) or (_transfer_original_display.get_parent() == self and QUEST_PAPER_VISUAL.get_instance(_transfer_original_display) == _transfer_original_instance)
	return false


## 调用方先核验双方；本段只修改字段与信号连接，不调用显示或观察回调。
func finalize_transfer(actor: Variant, inventory: Variant, token: int) -> bool:
	if not is_transfer_current(actor, inventory, token) or _transfer_committed or _transfer_stage == TransferStage.NONE:
		return false
	_transfer_committed = true
	_revision += 1
	if _transfer_stage == TransferStage.TAKE:
		_watch_instance(null)
	return true


func cleanup_transfer(actor: Variant, inventory: Variant, token: int) -> void:
	if not is_transfer_current(actor, inventory, token) or not _transfer_committed or _transfer_stage != TransferStage.TAKE:
		return
	var previous: Variant = _transfer_original_display
	_transfer_original_display = null
	_dispose_visual(previous)


func rollback_transfer(actor: Variant, inventory: Variant, token: int) -> void:
	if not is_transfer_current(actor, inventory, token) or _transfer_committed:
		return
	var candidate: Variant = _transfer_candidate
	if _transfer_stage == TransferStage.PLACE and _stored_instance == _transfer_candidate_instance and _display == _transfer_candidate:
		_stored_instance = _transfer_original_instance
		_display = null
		_watch_instance(_transfer_original_instance)
	elif _transfer_stage == TransferStage.TAKE and _stored_instance == null and _display == null:
		_stored_instance = _transfer_original_instance
		var previous: Variant = _transfer_original_display
		if _display_is_live(previous) and previous.get_parent() == self and QUEST_PAPER_VISUAL.get_instance(previous) == _stored_instance:
			_display = previous
			previous.visible = _transfer_original_visible
			if not is_instance_valid(self):
				return
	_transfer_candidate = null
	_transfer_candidate_instance = null
	_transfer_stage = TransferStage.NONE
	_dispose_visual(candidate)


func notify_transfer(actor: Variant, inventory: Variant, token: int) -> void:
	if is_transfer_current(actor, inventory, token) and _transfer_committed and _node_is_live(self):
		state_changed.emit()


func end_transfer(actor: Variant, inventory: Variant, token: int) -> void:
	if not is_transfer_current(actor, inventory, token):
		return
	_transfer_token = 0
	_transfer_actor = null
	_transfer_inventory = null
	_transfer_stage = TransferStage.NONE
	_transfer_original_instance = null
	_transfer_original_display = null
	_transfer_candidate = null
	_transfer_candidate_instance = null
	_transfer_committed = false


func _candidate_matches(visual: Variant, instance: AutolysisItemInstance) -> bool:
	if _transfer_candidate != visual or _transfer_candidate_instance != instance or not _display_is_live(visual) or visual.get_parent() != self or not is_instance_valid(instance) or not instance.is_valid_instance() or not instance.is_quest_paper() or QUEST_PAPER_VISUAL.get_instance(visual) != instance:
		return false
	var front: MeshInstance3D = QUEST_PAPER_VISUAL.get_front(visual)
	return front != null and front.mesh != null and QUEST_PAPER_VISUAL.get_viewport(visual) != null and (instance.quest_paper_contents == null or QUEST_PAPER_VISUAL.get_view(visual) != null)


func _watch_instance(instance: AutolysisItemInstance) -> void:
	if _watched_instance == instance:
		return
	if _watched_instance != null and _watched_instance.changed.is_connected(_refresh_stored_visual):
		_watched_instance.changed.disconnect(_refresh_stored_visual)
	_watched_instance = instance
	if instance != null:
		instance.changed.connect(_refresh_stored_visual)


func _refresh_stored_visual() -> bool:
	var visual: Node3D = get_display()
	if _transfer_stage == TransferStage.TAKE and not _transfer_committed:
		visual = _transfer_original_display if _display_is_live(_transfer_original_display) else null
	if _watched_instance == null or visual == null or visual.get_parent() != self:
		return false
	return QUEST_PAPER_VISUAL.apply_instance(visual, _watched_instance)


func _can_transfer_interact(actor: Node3D) -> bool:
	if not _node_is_live(actor) or not actor is AutolysisPlayer:
		return false
	var inventory: AutolysisInventoryController = (actor as AutolysisPlayer).inventory_controller
	return _node_is_live(inventory) and (inventory.can_place_in_quest_board_slot(actor, self) or inventory.can_take_from_quest_board_slot(actor, self))


func _on_transfer_requested(actor: Node3D) -> void:
	if not _node_is_live(actor) or not actor is AutolysisPlayer:
		return
	var inventory: AutolysisInventoryController = (actor as AutolysisPlayer).inventory_controller
	if not _node_is_live(inventory):
		return
	if is_occupied():
		inventory.try_take_from_quest_board_slot(actor, self)
	else:
		inventory.try_place_in_quest_board_slot(actor, self)


func _exit_tree() -> void:
	_watch_instance(null)


func _dispose_visual(visual: Variant) -> void:
	if not is_instance_valid(visual) or not visual is Node3D:
		return
	if visual.get_parent() == self:
		remove_child(visual)
	if is_instance_valid(visual):
		visual.queue_free()


func _node_is_live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()


func _display_is_live(node: Variant, require_tree: bool = true) -> bool:
	return is_instance_valid(node) and node is Node3D and not node.is_queued_for_deletion() and (not require_tree or node.is_inside_tree())


func _is_display_only(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is AutolysisInteractionComponent or node.is_in_group(&"interactable") or node.get_script() != null:
		return false
	for child: Node in node.get_children():
		if not _is_display_only(child):
			return false
	return true
