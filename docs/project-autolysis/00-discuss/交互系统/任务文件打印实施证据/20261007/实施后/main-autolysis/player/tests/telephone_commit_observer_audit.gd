extends "res://main-autolysis/player/tests/telephone_dependency_audit.gd"
## 独立观察回调故障探针：电话展示隐藏同步回调取消尚未完成的同一会话。

var taken_count: int = 0
var returned_count: int = 0
var aborted_count: int = 0
var injected: bool = false
var audit_stage: String = "取下"
var held_serial: int = 0


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	await fixture()
	telephone.handset_taken.connect(_taken)
	telephone.handset_returned.connect(_returned)
	telephone.handset_aborted.connect(_aborted)
	telephone.handset_visual.visibility_changed.connect(_dock_visibility_changed)
	var requested: bool = telephone.request_handset_transfer(player)
	await frames(12)
	var actor: AutolysisPlayer = player as AutolysisPlayer
	var record: Dictionary = {"用途": "电话挂机展示隐藏的同步观察回调异常终止当前预处理", "请求被接受": requested, "已注入": injected, "取下完成通知": taken_count, "归还完成通知": returned_count, "异常终止通知": aborted_count, "玩家会话序号": actor.inventory_controller.get_handset_session_id(), "电话持有序号": telephone.get_holder_session_id(), "玩家独占持筒": actor.inventory_controller.has_exclusive_handset(), "电话持有者匹配": telephone.get_holder() == actor, "电话事务仍等待": telephone.is_transfer_pending(), "玩家库存事务仍等待": actor.inventory_controller.get_handset_transfer_pending(), "电话听筒可见": telephone.handset_visual.visible, "玩家手中显示": actor.held_item_presenter.get_display() != null}
	check(injected and aborted_count == 1 and taken_count == 0 and returned_count == 0, "取下展示同步回调取消只发布一次异常终止，不发布正常完成")
	check(not actor.inventory_controller.has_exclusive_handset() and telephone.get_holder_session_id() == 0 and telephone.handset_visual.visible and actor.held_item_presenter.get_display() == null, "取下同步取消后玩家及来源成对恢复")
	check(not telephone.is_transfer_pending() and not actor.inventory_controller.get_handset_transfer_pending(), "取下同步取消完成物理恢复后解除事务互斥")
	world.queue_free()
	await frames(3)
	await fixture()
	telephone.handset_taken.connect(_taken)
	telephone.handset_returned.connect(_returned)
	telephone.handset_aborted.connect(_aborted)
	telephone.handset_visual.visibility_changed.connect(_dock_visibility_changed)
	audit_stage = "准备归还"
	injected = false
	telephone.request_handset_transfer(player)
	await frames(10)
	actor = player as AutolysisPlayer
	held_serial = actor.inventory_controller.get_handset_session_id()
	taken_count = 0
	returned_count = 0
	aborted_count = 0
	audit_stage = "归还"
	var revision_before_return: int = actor.inventory_controller.get_holding_revision()
	var return_requested: bool = telephone.request_handset_transfer(player)
	await frames(12)
	var return_record: Dictionary = {"用途": "电话挂机展示恢复的同步观察回调异常终止当前归还", "原持有序号": held_serial, "请求被接受": return_requested, "已注入": injected, "取下完成通知": taken_count, "归还完成通知": returned_count, "异常终止通知": aborted_count, "玩家会话序号": actor.inventory_controller.get_handset_session_id(), "电话持有序号": telephone.get_holder_session_id(), "玩家独占持筒": actor.inventory_controller.has_exclusive_handset(), "电话事务仍等待": telephone.is_transfer_pending(), "玩家库存事务仍等待": actor.inventory_controller.get_handset_transfer_pending(), "电话听筒可见": telephone.handset_visual.visible, "玩家手中显示": actor.held_item_presenter.get_display() != null, "归还前持物修订": revision_before_return, "取消后持物修订": actor.inventory_controller.get_holding_revision()}
	check(held_serial > 0 and injected and aborted_count == 1 and returned_count == 0 and taken_count == 0, "归还展示同步回调取消只发布异常终止，不重复正常归还完成")
	check(actor.inventory_controller.get_holding_revision() == revision_before_return + 1, "归还同步取消只增加一次持物变化修订")
	check(not actor.inventory_controller.has_exclusive_handset() and telephone.get_holder_session_id() == 0 and telephone.handset_visual.visible and actor.held_item_presenter.get_display() == null, "归还同步取消成对清理且原展示恢复")
	world.queue_free()
	await frames(3)
	await fixture()
	telephone.handset_taken.connect(_taken)
	telephone.handset_returned.connect(_returned)
	telephone.handset_aborted.connect(_aborted)
	audit_stage = "必要依赖释放"
	injected = false
	taken_count = 0
	returned_count = 0
	aborted_count = 0
	telephone.handset_visual.visibility_changed.connect(_dock_visibility_changed)
	var dependency_requested: bool = telephone.request_handset_transfer(player)
	await frames(12)
	actor = player as AutolysisPlayer
	var dependency_record: Dictionary = {"用途": "电话挂机展示隐藏的同步观察回调立即释放必要限位形状", "请求被接受": dependency_requested, "已注入": injected, "取下完成通知": taken_count, "归还完成通知": returned_count, "异常终止通知": aborted_count, "玩家独占持筒": actor.inventory_controller.has_exclusive_handset(), "电话持有序号": telephone.get_holder_session_id(), "电话听筒可见": telephone.handset_visual.visible, "玩家手中显示": actor.held_item_presenter.get_display() != null}
	check(injected and taken_count == 0 and returned_count == 0 and aborted_count <= 1, "取下同步表现回调释放必要限位不发布正常取下完成")
	check(not actor.inventory_controller.has_exclusive_handset() and telephone.get_holder_session_id() == 0 and telephone.handset_visual.visible, "提交边界必要限位释放后成对恢复")
	world.queue_free()
	await frames(3)
	await fixture()
	telephone.handset_taken.connect(_taken)
	telephone.handset_returned.connect(_returned)
	telephone.handset_aborted.connect(_aborted)
	audit_stage = "准备归还"
	injected = false
	telephone.handset_visual.visibility_changed.connect(_dock_visibility_changed)
	telephone.request_handset_transfer(player)
	await frames(10)
	taken_count = 0
	returned_count = 0
	aborted_count = 0
	audit_stage = "归还展示释放"
	var visual_return_requested: bool = telephone.request_handset_transfer(player)
	await frames(12)
	actor = player as AutolysisPlayer
	var visual_return_record: Dictionary = {"用途": "电话挂机展示恢复的同步观察回调排队释放必要挂机展示", "请求被接受": visual_return_requested, "已注入": injected, "取下完成通知": taken_count, "归还完成通知": returned_count, "异常终止通知": aborted_count, "挂机展示仍有效": is_instance_valid(telephone.handset_visual), "玩家独占持筒": actor.inventory_controller.has_exclusive_handset(), "电话持有序号": telephone.get_holder_session_id(), "玩家手中显示": actor.held_item_presenter.get_display() != null}
	check(injected and returned_count == 0 and taken_count == 0, "归还同步表现回调排队释放必要挂机展示不发布正常归还完成")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file: FileAccess = FileAccess.open(directory.path_join("提交观察回调复核.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify([record, return_record, dependency_record, visual_return_record], "\t"))
	file.close()
	print(JSON.stringify(record))
	print(JSON.stringify(return_record))
	print(JSON.stringify(dependency_record))
	print(JSON.stringify(visual_return_record))
	world.queue_free()
	await frames(3)
	quit(1 if failures > 0 else 0)


func _dock_visibility_changed() -> void:
	if injected or audit_stage == "准备归还":
		return
	if audit_stage == "取下" and telephone.handset_visual.visible:
		return
	if audit_stage == "归还" and not telephone.handset_visual.visible:
		return
	if audit_stage == "必要依赖释放" and telephone.handset_visual.visible:
		return
	if audit_stage == "归还展示释放" and not telephone.handset_visual.visible:
		return
	injected = true
	if audit_stage == "必要依赖释放":
		telephone.move_limit_shape.free()
		return
	if audit_stage == "归还展示释放":
		telephone.handset_visual.queue_free()
		return
	var actor: AutolysisPlayer = player as AutolysisPlayer
	actor.inventory_controller.abort_handset_session(telephone, telephone.get_holder_session_id() if audit_stage == "取下" else held_serial, "挂机可视变更观察回调异常终止")


func _taken(_actor: Node3D, _serial: int) -> void:
	taken_count += 1


func _returned(_actor: Node3D, _serial: int) -> void:
	returned_count += 1


func _aborted(_actor: Node3D, _serial: int, _reason: String) -> void:
	aborted_count += 1
