extends "res://main-autolysis/player/tests/telephone_dependency_audit.gd"
## 正式异步取下预处理中释放聚焦控制器，检查必要引用与取消恢复。


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	await fixture()
	var actor: AutolysisPlayer = player as AutolysisPlayer
	var requested: bool = telephone.request_handset_transfer(actor)
	actor.focus_controller.free()
	await frames(6)
	var record: Dictionary = {"用途": "正式取下已请求且物理预处理未完成时立即释放聚焦控制器", "请求被接受": requested, "聚焦控制器有效": is_instance_valid(actor.focus_controller), "电话事务等待": telephone.is_transfer_pending(), "库存事务等待": actor.inventory_controller.get_handset_transfer_pending(), "玩家独占持筒": actor.inventory_controller.has_exclusive_handset(), "挂机展示": telephone.handset_visual.visible}
	check(requested and not telephone.is_transfer_pending() and not actor.inventory_controller.get_handset_transfer_pending() and not actor.inventory_controller.has_exclusive_handset() and telephone.handset_visual.visible, "聚焦依赖释放后取下取消并成对恢复及解除事务互斥")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file: FileAccess = FileAccess.open(directory.path_join("异步聚焦依赖复核.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	print(JSON.stringify(record))
	world.queue_free()
	await frames(3)
	quit(1 if failures > 0 else 0)
