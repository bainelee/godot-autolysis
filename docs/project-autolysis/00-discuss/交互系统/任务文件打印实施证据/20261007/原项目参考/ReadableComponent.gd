extends InteractionComponent
class_name ReadableComponent
## 可读组件（ReadableComponent）：挂在可阅读道具上的交互组件。
## 玩家按 F 交互后进入独立检视态（由 HUD 常驻 ReadableUI 驱动），
## 可旋转模型、发现阅读面、按 F 阅读文字内容。

signal has_been_read

@export_group("Readable Settings")
@export var interact_sound: AudioStream
## 检视展示用可视根节点（包含 MeshInstance3D 和 ReadingSurface 子节点的子树）。
@export var inspect_visual_root: Node3D
## 模型场景引用，收集 note 时取 resource_path 写入 NoteData.model_scene_path。
@export var model_scene: PackedScene
## 唯一标识，用于防重复收集。
@export var note_id: String = ""
## 为 true 时首次交互先收集 note 到 CogitoPlayerState。
@export var auto_get_note: bool = false
## 检视态顶部标题文字。
@export var inspect_title_text: String = "详细检查"

## 运行时：从 inspect_visual_root 子树自动扫描到的阅读面。
var reading_surfaces: Array[ReadingSurface] = []


func _ready() -> void:
	if is_instance_valid(inspect_visual_root):
		var found := inspect_visual_root.find_children("", "ReadingSurface", true, false)
		for node in found:
			reading_surfaces.append(node as ReadingSurface)


func interact(_player_interaction_component: PlayerInteractionComponent) -> void:
	if is_disabled:
		return
	was_interacted_with.emit(interaction_text, input_map_action)

	if interact_sound:
		Audio.play_sound_3d(interact_sound).global_position = self.global_position

	# auto_get_note：首次交互时先收集 note。
	if auto_get_note and note_id != "":
		_try_collect_note(_player_interaction_component)

	var hud := _get_hud(_player_interaction_component)
	if hud and hud.readable_ui and not hud.readable_ui.is_inspecting:
		hud.readable_ui.start_inspecting(self, _player_interaction_component)

	has_been_read.emit()


func _get_hud(pic: PlayerInteractionComponent) -> CogitoPlayerHudManager:
	var hud_path := NodePath(pic.player.player_hud)
	return pic.player.get_node(hud_path) as CogitoPlayerHudManager


func _try_collect_note(pic: PlayerInteractionComponent) -> void:
	var player_state: CogitoPlayerState = CogitoSceneManager._player_state
	if player_state == null:
		player_state = CogitoPlayerState.new()
		CogitoSceneManager._player_state = player_state
	for note in player_state.collected_notes:
		if note.source_id == note_id:
			return
	var note_data := build_note_data()
	player_state.collected_notes.append(note_data)


## 从当前组件数据构建 NoteData 实例。
func build_note_data() -> NoteData:
	var note_data := NoteData.new()
	note_data.source_id = note_id

	if model_scene:
		note_data.model_scene_path = model_scene.resource_path
	elif owner and owner.scene_file_path != "":
		note_data.model_scene_path = owner.scene_file_path
	else:
		note_data.model_scene_path = ""

	var parent_obj = get_parent()
	if parent_obj and "display_name" in parent_obj:
		note_data.display_name = parent_obj.display_name
	else:
		note_data.display_name = note_id

	for surface in reading_surfaces:
		var surface_dict: Dictionary = {
			"title": surface.title,
			"pages": surface.pages.duplicate()
		}
		note_data.surfaces.append(surface_dict)
	return note_data
