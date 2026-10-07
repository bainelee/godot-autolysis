class_name AutolysisQuestBoard
extends StaticBody3D
## 任务板拥有显式聚焦登记；各槽独立拥有文件来源与局部取放入口。

@export var focus_target: AutolysisFocusTarget
@export var reference_camera: Camera3D
@export var root_interaction: AutolysisInteractionComponent
@export var slots: Array[AutolysisQuestBoardSlot] = []

var _configured: bool = false
var _registered_slots: Array = []


func _ready() -> void:
	if _live(root_interaction) and root_interaction.get_parent() == self:
		root_interaction.is_enabled = false
	var error: String = get_configuration_error()
	if not error.is_empty():
		push_warning("任务板配置无效：%s" % error)
		return
	_registered_slots.assign(slots)
	for slot: Variant in _registered_slots:
		if not _live(slot):
			push_warning("任务板槽引用失效；仅停止对应槽入口")
			continue
		if not slot.configure(self, focus_target):
			push_warning("任务板槽入口配置无效：%s" % slot.get_configuration_error())
	if not focus_target.configure_quest_board(self, reference_camera, root_interaction, slots):
		push_warning("任务板聚焦登记失败")
		return
	root_interaction.set_availability_check(_can_enter)
	root_interaction.set_execution_handler(_on_entry_requested)
	_configured = true
	root_interaction.is_enabled = true


## 核心登记保护设备、相机和唯一根入口；槽入口配置按槽分别核查。
func get_configuration_error() -> String:
	if not _live(self) or not _live(focus_target) or focus_target.get_parent() != self:
		return "任务板缺少直属聚焦描述"
	if not _live(reference_camera) or not is_ancestor_of(reference_camera):
		return "任务板缺少本板聚焦相机"
	if not _live(root_interaction) or root_interaction.get_parent() != self or root_interaction.interaction_mode != AutolysisInteractionComponent.InteractionMode.FOCUS:
		return "任务板缺少直属聚焦交互入口"
	var interaction_count: int = 0
	var target_count: int = 0
	for child: Node in get_children():
		if child is AutolysisInteractionComponent:
			interaction_count += 1
		if child is AutolysisFocusTarget:
			target_count += 1
	if interaction_count != 1 or target_count != 1:
		return "任务板必须配置唯一直属根交互组件与聚焦描述"
	if slots.is_empty():
		return "任务板缺少显式槽登记"
	var seen: Array = []
	for slot: Variant in slots:
		# 已释放的单槽不影响其余槽的核心聚焦登记。
		if not _live(slot):
			continue
		if not is_ancestor_of(slot) or seen.has(slot):
			return "任务板槽引用必须互异且属于本板"
		seen.append(slot)
	if _configured and not root_interaction.has_execution_handler(_on_entry_requested):
		return "任务板根业务执行绑定失效"
	return ""


func is_configured() -> bool:
	return _configured and get_configuration_error().is_empty() and focus_target.is_valid_target()


## 不递归查询聚焦有效性，供描述器核对本次配置来源是否被替换。
func matches_focus_registration(target: AutolysisFocusTarget, camera: Camera3D, interaction: AutolysisInteractionComponent, registered_slots: Array) -> bool:
	return focus_target == target and reference_camera == camera and root_interaction == interaction and _registered_slots == registered_slots and slots == registered_slots


func owns_slot(slot: Variant) -> bool:
	return _live(self) and _live(slot) and slot is AutolysisQuestBoardSlot and _registered_slots.has(slot) and is_ancestor_of(slot) and slot.get_board() == self and slot.get_focus_target() == focus_target


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


func _exit_tree() -> void:
	_configured = false
	if is_instance_valid(root_interaction) and root_interaction.get_parent() == self:
		root_interaction.is_enabled = false
		root_interaction.clear_execution_handler()
		root_interaction.clear_availability_check()
	if is_instance_valid(focus_target):
		focus_target.clear_quest_board_registration(self)
	_registered_slots.clear()


func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()
