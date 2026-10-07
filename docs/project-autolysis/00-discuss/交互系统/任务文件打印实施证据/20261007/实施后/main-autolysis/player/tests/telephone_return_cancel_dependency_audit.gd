extends "res://main-autolysis/player/tests/telephone_device_test.gd"
## 归还取消恢复启用时释放必要限位，不能永久保留预处理与移动保护。


func run_checks() -> void:
	await _new_scene()
	await _enter()
	await _take()
	check(phone.request_handset_transfer(player), "建立归还预处理")
	phone.cancel_handset_transfer()
	phone.move_limit_shape.free()
	await frames(8)
	check(not phone.is_transfer_pending() and not inventory.get_handset_transfer_pending(), "归还取消恢复期间限位失效解除双方预处理")
	check(phone.get_holder() == null and not inventory.has_exclusive_handset(), "无法恢复必要限位时匹配异常终止原持有")
	check(not player._handset_movement_guarded(), "失效限位实际移除后解除移动保护")
	snapshots.append({"来源事务等待": phone.is_transfer_pending(), "库存事务等待": inventory.get_handset_transfer_pending(), "来源会话": phone.get_holder_session_id(), "库存持筒": inventory.has_exclusive_handset(), "移动保护": player._handset_movement_guarded()})
	_save_report()
	if is_instance_valid(world):
		world.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)
