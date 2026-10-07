extends "res://main-autolysis/player/tests/telephone_dependency_audit.gd"
## 有效草稿通过正式世界点击提交后，同步姿态观察者释放必要输入依赖。

var release_target: String = "库存"
var injected: bool = false


func run_checks() -> void:
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	var reports: Array[Dictionary] = []
	for target_name: String in ["库存", "聚焦控制器"]:
		await fixture()
		var actor: AutolysisPlayer = player as AutolysisPlayer
		# 本专项只验证保留工具的观察边界；不依赖正式默认启用。
		actor.handset_pose_debug_enabled = true
		telephone.request_handset_transfer(actor)
		await frames(12)
		check(actor.inventory_controller.has_exclusive_handset(), "观察者释放探针先建立正式持筒聚焦")
		var panel: AutolysisHandsetPoseDebug = actor.handset_pose_debug
		var interaction: AutolysisInteractionController = actor.interaction_controller
		var field: LineEdit = panel.get_field(0).get_line_edit()
		field.grab_focus()
		await frames(2)
		field.text = "-0.125"
		field.text_changed.emit(field.text)
		release_target = target_name
		injected = false
		panel.pose_applied.connect(_pose_applied)
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = Vector2(400, 350)
		check(actor.is_handset_text_editing() and not panel.get_panel_rect().has_point(click.position), "正式有效字段草稿与面板外左键建立提交边界")
		# 只同步调用正式未处理输入入口，避免另一个物理帧掩盖当前边界。
		interaction._unhandled_input(click)
		var record: Dictionary = {"用途": "正式世界点击提交草稿的同步姿态通知释放输入依赖", "释放对象": target_name, "已注入": injected, "库存仍有效": is_instance_valid(actor.inventory_controller), "聚焦控制器仍有效": is_instance_valid(actor.focus_controller), "旧交互队列长度": interaction._pending_clicks.size()}
		check(injected and interaction._pending_clicks.is_empty(), "草稿同步观察者释放%s后旧世界点击不入队" % target_name)
		reports.append(record)
		print(JSON.stringify(record))
		world.queue_free()
		await frames(3)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file: FileAccess = FileAccess.open(directory.path_join("姿态观察输入边界复核.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	file.close()
	quit(1 if failures > 0 else 0)


func _pose_applied(_position: Vector3, _rotation: Vector3) -> void:
	if injected:
		return
	injected = true
	var actor: AutolysisPlayer = player as AutolysisPlayer
	if release_target == "库存":
		actor.inventory_controller.free()
	else:
		actor.focus_controller.free()
