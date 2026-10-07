extends "res://main-autolysis/player/tests/telephone_dependency_audit.gd"
## 正式呈现器模型入树观察者排队释放必要限位；仅运行无图形。

var injected: bool = false
var held_notifications: int = 0
var taken_notifications: int = 0


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	await fixture()
	var actor: AutolysisPlayer = player as AutolysisPlayer
	actor.inventory_controller.held_item_changed.connect(_held_changed)
	actor.held_item_presenter.child_entered_tree.connect(_display_entered)
	telephone.handset_taken.connect(_taken)
	var requested: bool = telephone.request_handset_transfer(actor)
	await frames(12)
	var record: Dictionary = {"用途": "正式手持显示模型入树同步回调排队释放必要限位形状", "请求被接受": requested, "已注入": injected, "持物变化通知": held_notifications, "取下正常完成通知": taken_notifications, "最终独占持筒": actor.inventory_controller.has_exclusive_handset(), "最终电话持有序号": telephone.get_holder_session_id(), "最终库存事务等待": actor.inventory_controller.get_handset_transfer_pending(), "最终电话事务等待": telephone.is_transfer_pending(), "最终手持显示": actor.held_item_presenter.get_display() != null, "最终挂机展示": telephone.handset_visual.visible}
	check(injected and taken_notifications == 0 and held_notifications == 0, "模型入树边界必要限位失效不发布正常取下或持物变化")
	check(not actor.inventory_controller.has_exclusive_handset() and telephone.get_holder_session_id() == 0 and actor.held_item_presenter.get_display() == null and telephone.handset_visual.visible, "模型入树边界必要限位失效后成对恢复")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file: FileAccess = FileAccess.open(directory.path_join("模型入树观察复核.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	print(JSON.stringify(record))
	world.queue_free()
	await frames(3)
	quit(1 if failures > 0 else 0)


func _display_entered(_display: Node) -> void:
	if injected:
		return
	injected = true
	telephone.move_limit_shape.queue_free()


func _held_changed() -> void:
	held_notifications += 1


func _taken(_actor: Node3D, _serial: int) -> void:
	taken_notifications += 1
