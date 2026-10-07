class_name AutolysisQuestPaperVisual
extends RefCounted
## 呈现器拥有的纸面适配；纯展示场景资源不携带脚本或交互。

const VIEW_SCENE: PackedScene = preload("res://main-autolysis/ui/quest-paper/autolysis_quest_paper_view.tscn")
const TEXT_MATERIAL: StandardMaterial3D = preload("res://main-autolysis/assets/materials/paper/mat_quest_paper_text.tres")
const INSTANCE_META: StringName = &"quest_paper_display_instance"


static func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and not node.is_queued_for_deletion()


static func get_viewport(visual: Node3D) -> SubViewport:
	if not _live(visual):
		return null
	var viewport: SubViewport = visual.get_node_or_null("PaperViewport") as SubViewport
	return viewport if _live(viewport) else null


static func get_front(visual: Node3D) -> MeshInstance3D:
	if not _live(visual):
		return null
	var front: MeshInstance3D = visual.get_node_or_null("PaperFront") as MeshInstance3D
	return front if _live(front) else null


static func get_view(visual: Node3D) -> AutolysisQuestPaperView:
	var viewport: SubViewport = get_viewport(visual)
	if viewport == null:
		return null
	var view: AutolysisQuestPaperView = viewport.get_node_or_null("QuestPaperView") as AutolysisQuestPaperView
	return view if _live(view) else null


static func get_instance(visual: Node3D) -> AutolysisItemInstance:
	if not _live(visual) or not visual.has_meta(INSTANCE_META):
		return null
	return visual.get_meta(INSTANCE_META, null) as AutolysisItemInstance


static func _same_contents(first: AutolysisQuestPaperContents, second: AutolysisQuestPaperContents) -> bool:
	if first == null or second == null:
		return first == second
	return first.get_task_id() == second.get_task_id() and first.get_data_lines() == second.get_data_lines() and first.get_group_gap_before_lines() == second.get_group_gap_before_lines()


static func apply_instance(visual: Node3D, instance: AutolysisItemInstance) -> bool:
	if not _live(visual) or not is_instance_valid(instance) or not instance.is_valid_instance() or not instance.is_quest_paper():
		return false
	var viewport: SubViewport = get_viewport(visual)
	var front: MeshInstance3D = get_front(visual)
	if viewport == null or front == null or front.mesh == null:
		return false
	var contents: AutolysisQuestPaperContents = instance.quest_paper_contents
	var previous: AutolysisQuestPaperView = get_view(visual)
	if previous == null and contents == null and get_instance(visual) != null:
		visual.set_meta(INSTANCE_META, instance)
		return true
	if previous != null and _same_contents(previous.get_contents(), contents):
		visual.set_meta(INSTANCE_META, instance)
		return true
	var view: AutolysisQuestPaperView
	if contents != null:
		view = VIEW_SCENE.instantiate() as AutolysisQuestPaperView
		if view == null or not view.configure_contents(contents):
			if is_instance_valid(view):
				view.free()
			return false
		view.reveal_all_data_lines()
	if previous != null:
		previous.hide()
		if not _live(visual) or not _live(viewport):
			if is_instance_valid(view):
				view.free()
			return false
		if _live(previous) and previous.get_parent() == viewport:
			viewport.remove_child(previous)
		if is_instance_valid(previous):
			previous.queue_free()
	if not _live(visual) or not _live(viewport) or not _live(front):
		if is_instance_valid(view):
			view.free()
		return false
	if view != null:
		viewport.add_child(view)
		if not _live(visual) or not _live(viewport) or not _live(front) or not _live(view) or view.get_parent() != viewport:
			return false
	# 每个模型独立持有文字叠加材质，基础纸面材质由场景配置。
	# 同件内容更新仅更换排版，保持视口、纹理和文字材质身份。
	if get_instance(visual) == null:
		front.material_overlay = TEXT_MATERIAL.duplicate() as StandardMaterial3D
		if not _live(visual) or not _live(front):
			return false
	var material: StandardMaterial3D = front.material_overlay as StandardMaterial3D
	if material == null:
		return false
	material.albedo_color = Color.WHITE if view != null else Color(1.0, 1.0, 1.0, 0.0)
	material.albedo_texture = viewport.get_texture() if view != null else null
	if not _live(visual) or not _live(viewport) or not _live(front) or (view != null and not _live(view)):
		return false
	visual.set_meta(INSTANCE_META, instance)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return true
