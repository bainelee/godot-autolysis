class_name AutolysisBlendMachine
extends StaticBody3D
## 根入口只负责开始玩家聚焦；每槽运行播放器独立使用原制作动画。

@export var focus_target: AutolysisFocusTarget
@export var reference_camera: Camera3D
@export var root_interaction: AutolysisInteractionComponent
@export var animation_source: AnimationPlayer
@export var slots: Array[AutolysisBlendSlot] = []
@export var handle: AutolysisBlendHandle

var _configured: bool = false


func _ready() -> void:
	if is_instance_valid(root_interaction):
		root_interaction.is_enabled = false
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
	if not focus_target.configure(self, reference_camera, root_interaction, slots, [handle]):
		push_error("原药混合器聚焦描述登记失败：%s" % get_path())
		return
	root_interaction.set_availability_check(_can_enter)
	root_interaction.interaction_requested.connect(_on_entry_requested)
	_configured = true
	handle.drag_interaction.is_enabled = true
	root_interaction.is_enabled = true


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
	var seen: Array[AutolysisBlendSlot] = []
	for slot: AutolysisBlendSlot in slots:
		if not is_instance_valid(slot) or slot.get_parent() != self or seen.has(slot):
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


func _can_enter(actor: Node3D) -> bool:
	if not _configured or not is_instance_valid(focus_target) or not focus_target.is_valid_target() or not is_instance_valid(actor):
		return false
	var controller: Node = actor.get("focus_controller") as Node
	return is_instance_valid(controller) and controller.has_method("can_enter") and controller.can_enter(focus_target)


func _on_entry_requested(actor: Node3D) -> void:
	if not _can_enter(actor):
		return
	var controller: Node = actor.get("focus_controller") as Node
	controller.try_enter(focus_target)
