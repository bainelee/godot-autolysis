class_name AutolysisPackingDoor
extends AutolysisPackingMotion
## 舱门运动不改变本机类型；胶囊取放依赖打开动作自然完成。


func can_toggle(actor: Node3D) -> bool:
	return is_configured() and not machine.is_interaction_locked() and not machine.are_transfers_busy() and not is_animating() and (is_open() or is_closed()) and machine.is_actor_focused(actor)


func try_toggle(actor: Node3D) -> bool:
	if not can_toggle(actor):
		return false
	_start_motion(state == MotionState.CLOSED)
	return true


func _on_toggle_requested(actor: Node3D) -> void:
	try_toggle(actor)
