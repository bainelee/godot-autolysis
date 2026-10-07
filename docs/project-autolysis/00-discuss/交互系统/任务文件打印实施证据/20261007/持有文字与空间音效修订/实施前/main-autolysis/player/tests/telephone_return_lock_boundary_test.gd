extends "res://main-autolysis/player/tests/telephone_call_test.gd"
## 合法归还准备后改变匹配来源只读限制，逐个验证持续与最终提交边界。
## 注入真实可查询的限制事实，不伪造成功完成，不使用错误事务令牌代替测试。

class ReturnLockTelephone extends AutolysisTelephone:
	var boundary: String = ""
	var constraint_active: bool = false
	var constrained_actor: Node3D
	var constrained_session: int = 0
	var source_commit_called: bool = false
	var source_commit_result: bool = false
	var business_commit_called: bool = false
	var dock_observer_injected: bool = false

	func _ready() -> void:
		super._ready()
		handset_visual.visibility_changed.connect(_on_dock_visibility)

	func is_handset_return_blocked(actor: Node3D, session: int) -> bool:
		return (constraint_active and actor == constrained_actor and session == constrained_session and session > 0) or super.is_handset_return_blocked(actor, session)

	func _commit_returned(actor: Variant, token: int) -> bool:
		source_commit_called = true
		if boundary == "来源提交前":
			constraint_active = true
		var result: bool = super._commit_returned(actor, token)
		source_commit_result = result
		if boundary == "库存提交复核" and result:
			constraint_active = true
		return result

	func commit_handset_business_completion(returning: bool, actor: Node3D, session: int, transaction: int) -> bool:
		if returning:
			business_commit_called = true
			if boundary == "唯一业务最终提交":
				constraint_active = true
		return super.commit_handset_business_completion(returning, actor, session, transaction)

	func _on_dock_visibility() -> void:
		if boundary == "来源提交后" and handset_visual.visible and constrained_session > 0:
			constraint_active = true
			dock_observer_injected = true


var lock_samples: Array[Dictionary] = []
var lock_return_notifications: int = 0


func _lock_fixture() -> void:
	paused = false
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	world = MAIN_SCENE.instantiate()
	player = world.get_node("autolysis_player")
	phone = world.get_node("interaction_prefabs/machines/MachineTelephone0/StaticBody3D")
	var exported: Dictionary = {}
	for property: StringName in PHONE_EXPORTS:
		exported[property] = phone.get(property)
	phone.set_script(ReturnLockTelephone)
	for property: StringName in PHONE_EXPORTS:
		phone.set(property, exported[property])
	root.add_child(world)
	player.set_physics_process(false)
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(-9.35, 0.8005, 11))
	player.body.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.is_movement_paused = false
	player.is_showing_ui = false
	player._clear_landing_stun()
	inventory = player.inventory_controller
	focus = player.focus_controller
	focus.configure(player, player.camera, player.held_item_presenter, _headless_entry)
	inventory.configure(player.held_item_presenter, _headless_inventory_input)
	lock_return_notifications = 0
	phone.handset_returned.connect(func(_actor: Node3D, _session: int) -> void: lock_return_notifications += 1)
	await frames(3)
	await _enter()
	await _take()
	var fixture: ReturnLockTelephone = phone as ReturnLockTelephone
	fixture.constrained_actor = player
	fixture.constrained_session = inventory.get_handset_session_id()


func _test_return_boundary(boundary: String) -> void:
	await _lock_fixture()
	var fixture: ReturnLockTelephone = phone as ReturnLockTelephone
	fixture.boundary = boundary
	var held_session: int = inventory.get_handset_session_id()
	var revision: int = inventory.get_holding_revision()
	var display: Node3D = inventory.get_handset_display()
	check(phone.can_return_handset(player) and inventory.can_return_handset(player, phone), boundary + "注入前普通匹配持有可正常准备归还")
	if boundary == "持续复核":
		phone.set_physics_process(false)
	check(phone.request_handset_transfer(player), boundary + "建立真实合法归还事务")
	var transaction: int = int(phone.get("_transfer_token"))
	check(transaction > 0 and transaction != held_session and inventory.is_handset_transfer_current(player, phone, transaction), boundary + "使用真实新归还令牌且注入前双方当前事务匹配")
	if boundary == "持续复核":
		fixture.constraint_active = true
		check(not inventory.is_handset_transfer_current(player, phone, transaction), "准备后来源限制生效使库存持续复核拒绝原有效事务")
		phone.set_physics_process(true)
	await _wait(func() -> bool: return not phone.is_transfer_pending(), boundary + "拒绝后等待真实限位恢复")
	check(fixture.constraint_active and inventory.get_handset_session_id() == held_session and phone.get_holder_session_id() == held_session and phone.get_holder() == player, boundary + "限制生效后拒绝归还并成对保留原匹配持有")
	check(inventory.get_handset_display() == display and is_instance_valid(display) and display.visible and not phone.handset_visual.visible and not phone.move_limit_shape.disabled and phone._shape_is_active_in_world(phone.move_limit_shape), boundary + "拒绝后原显示与真实启用限位恢复")
	check(lock_return_notifications == 0 and inventory.get_holding_revision() == revision and not inventory.get_handset_transfer_pending(), boundary + "不发布成功归还、不增加持物修订且解除本次事务互斥")
	match boundary:
		"持续复核": check(not fixture.source_commit_called, "持续复核受限在来源提交前取消事务")
		"来源提交前": check(fixture.source_commit_called and not fixture.source_commit_result, "电话最终来源提交直接查询同一原持有会话限制并拒绝")
		"来源提交后": check(fixture.dock_observer_injected and fixture.source_commit_called and not fixture.source_commit_result, "来源临时清空后同步展示观察产生限制，电话提交后复核仍拒绝")
		"库存提交复核": check(fixture.source_commit_called and fixture.source_commit_result and not fixture.business_commit_called, "来源提交先成功返回后限制生效，库存最终复核阻止业务完成与公开收尾")
		"唯一业务最终提交": check(fixture.source_commit_result and fixture.business_commit_called, "库存最后唯一业务入口前仍合法，来源业务完成中的同一限制拒绝并成对回滚")
	lock_samples.append({"边界": boundary, "原持有会话": held_session, "真实归还事务": transaction, "来源提交被调用": fixture.source_commit_called, "来源暂时提交返回": fixture.source_commit_result, "唯一业务完成被调用": fixture.business_commit_called, "同步展示限制注入": fixture.dock_observer_injected, "库存持有": inventory.get_handset_session_id(), "来源持有": phone.get_holder_session_id(), "归还成功通知": lock_return_notifications, "真实限位启用": phone._shape_is_active_in_world(phone.move_limit_shape), "来电阶段": _call().get_call_snapshot().stage, "注入性质": "合法归还准备后匹配来源只读限制事实生效；没有人工完成信号"})
	fixture.constraint_active = false
	fixture.boundary = ""
	await _return()
	check(lock_return_notifications == 1, boundary + "移除测试限制后同一听筒可以随后正常归还一次")


func run_checks() -> void:
	check(DisplayServer.get_name() == "headless", "归还限制边界专项实际使用无图形后端")
	for boundary: String in ["持续复核", "来源提交前", "来源提交后", "库存提交复核", "唯一业务最终提交"]:
		await _test_return_boundary(boundary)
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var output := FileAccess.open(evidence_directory.path_join("全部归还提交边界限制.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "断言": records, "匹配限制边界": lock_samples, "失败数": failures}, "\t"))
	world.queue_free()
	await frames(3)
	quit(1 if failures > 0 else 0)
