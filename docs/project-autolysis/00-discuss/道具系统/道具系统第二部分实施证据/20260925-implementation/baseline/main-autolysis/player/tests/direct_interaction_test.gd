extends "res://main-autolysis/player/tests/player_smoke_test.gd"

# 本测试以真实鼠标事件经过玩家、射线、控制器与物体效果。
# 无图形运行只覆盖行为；像素验证仅在真实渲染器下执行。
const COMPONENT_SCENE: PackedScene = preload("res://main-autolysis/components/interactions/autolysis_interaction_component.tscn")
const ARTIFACT_DIR: String = "res://.godot/interaction-verification"

class ProbeBody extends StaticBody3D:
	var request_count: int = 0
	var state: bool = false
	var recurse: bool = false
	var recursive_result: bool = true
	var component: AutolysisInteractionComponent

	func receive(actor: Node3D) -> void:
		request_count += 1
		state = not state
		if recurse:
			recursive_result = component.try_interact(actor)

	func receive_alternative(_actor: Node3D) -> void:
		request_count += 100

class EffectReceiver extends Node3D:
	var count: int = 0
	var release_target: Node = null

	func receive(_actor: Node3D) -> void:
		count += 1
		if is_instance_valid(release_target):
			release_target.queue_free()

	func receive_zero() -> void:
		count += 1

class ClickConsumer extends Control:
	var consumed: int = 0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				consumed += 1
			accept_event()

class AvailabilityReceiver extends Node3D:
	var allowed: bool = true
	var query_count: int = 0
	var received_actor: Node3D = null
	var component: AutolysisInteractionComponent = null
	var recurse: bool = false
	var recursive_query_result: bool = true
	var recursive_dispatch_result: bool = true
	var release_target: Node = null

	func permits(actor: Node3D) -> bool:
		query_count += 1
		received_actor = actor
		if recurse:
			recursive_query_result = component.can_interact(actor)
			recursive_dispatch_result = component.try_interact(actor)
		# 定向故障注入：正常业务查询不得释放节点。
		if is_instance_valid(release_target):
			release_target.queue_free()
		return allowed

	func permits_zero() -> bool:
		query_count += 1
		return true

	func permits_two(_actor: Node3D, _other: Node3D) -> bool:
		query_count += 1
		return true

	func permits_wrong_result(_actor: Node3D) -> String:
		return "允许"

class NonNodeAvailabilityReceiver extends RefCounted:
	func permits(_actor: Node3D) -> bool:
		return true

var available: bool = false
var availability_notifications: int = 0
var controller: Node
var detector: InteractionRayCast
var _original_accumulation: bool = true

func _on_availability_changed(value: bool) -> void:
	available = value
	availability_notifications += 1

func new_probe(location: Vector3, with_receiver: bool = true) -> ProbeBody:
	var probe: ProbeBody = ProbeBody.new()
	probe.collision_layer = 2
	probe.collision_mask = 0
	probe.add_to_group("interactable")
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.1, 0.1, 0.1)
	collision.shape = shape
	probe.add_child(collision)
	probe.component = COMPONENT_SCENE.instantiate()
	probe.add_child(probe.component)
	if with_receiver:
		probe.component.interaction_requested.connect(probe.receive)
	world.add_child(probe)
	probe.global_position = location
	return probe

func mouse_button(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = Vector2(root.size) / 2.0
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func click() -> void:
	mouse_button(true)
	await frames(2)
	mouse_button(false)
	await frames(2)

func menu_event(pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func attach_player() -> void:
	controller = player.get_node("InteractionController")
	detector = player.interaction_raycast
	controller.direct_availability_changed.connect(_on_availability_changed)
	available = controller.is_direct_available()

func run_component_contracts() -> void:
	var actor: Node3D = Node3D.new()
	world.add_child(actor)
	var probe: ProbeBody = new_probe(Vector3(20, 20, 20))
	var component: AutolysisInteractionComponent = probe.component
	check(component.can_interact(actor) and probe.request_count == 0, "组件可用性查询无效果副作用")
	check(component.try_interact(actor) and probe.request_count == 1 and probe.state, "独立组件请求恰好分发一次并执行效果")
	component.is_enabled = false
	check(not component.can_interact(actor) and not component.try_interact(actor) and probe.request_count == 1, "独立组件禁用时拒绝请求")
	component.is_enabled = true
	component.interaction_mode = AutolysisInteractionComponent.InteractionMode.FOCUS
	check(not component.can_interact(actor) and not component.try_interact(actor), "独立组件预留聚焦模式不执行直接交互")
	component.interaction_mode = AutolysisInteractionComponent.InteractionMode.DIRECT
	component.interaction_requested.disconnect(probe.receive)
	check(not component.can_interact(actor) and not component.try_interact(actor), "没有效果接收者时不可用且不分发")
	component.interaction_requested.connect(probe.receive)
	component.interaction_requested.connect(probe.receive_alternative)
	check(not component.can_interact(actor) and not component.try_interact(actor), "多个效果接收者时不可用且不分发")
	component.interaction_requested.disconnect(probe.receive_alternative)
	component.interaction_requested.disconnect(probe.receive)
	component.interaction_requested.connect(probe.receive, CONNECT_DEFERRED)
	check(not component.can_interact(actor), "延迟效果连接不符合本期同步契约")
	component.interaction_requested.disconnect(probe.receive)
	component.interaction_requested.connect(probe.receive)
	probe.recurse = true
	check(component.try_interact(actor) and not probe.recursive_result and probe.request_count == 2, "效果回调递归交互被拒绝且外层仅分发一次")
	probe.recurse = false
	var detached_actor: Node3D = Node3D.new()
	check(not component.can_interact(detached_actor) and not component.can_interact(null), "未入树或空执行者不可用")
	detached_actor.free()
	component.interaction_requested.disconnect(probe.receive)
	var receiver: EffectReceiver = EffectReceiver.new()
	world.add_child(receiver)
	component.interaction_requested.connect(receiver.receive_zero)
	check(not component.can_interact(actor), "零参数接收者不符合单参数效果契约")
	component.interaction_requested.disconnect(receiver.receive_zero)
	component.interaction_requested.connect(receiver.receive, CONNECT_APPEND_SOURCE_OBJECT)
	check(not component.can_interact(actor), "追加信号来源参数的连接不符合单参数效果契约")
	component.interaction_requested.disconnect(receiver.receive)
	component.interaction_requested.connect(receiver.receive)
	receiver.queue_free()
	check(not component.can_interact(actor) and not component.try_interact(actor), "效果接收者排队释放后立即拒绝请求")
	await frames(2)
	component.interaction_requested.connect(probe.receive)
	component.queue_free()
	check(not component.can_interact(actor) and not component.try_interact(actor), "组件排队释放后立即拒绝请求")
	probe.queue_free()
	await frames(2)
	probe = new_probe(Vector3(20, 20, 20))
	probe.queue_free()
	check(not probe.component.can_interact(actor), "物理父节点排队释放后立即拒绝请求")
	await frames(2)
	probe = new_probe(Vector3(20, 20, 20))
	actor.queue_free()
	check(not probe.component.can_interact(actor), "执行者排队释放后立即拒绝请求")
	probe.queue_free()
	await frames(2)

func run_availability_contracts() -> void:
	var actor: Node3D = Node3D.new()
	world.add_child(actor)
	var probe: ProbeBody = new_probe(Vector3(20, 20, 20))
	var component: AutolysisInteractionComponent = probe.component
	var receiver: AvailabilityReceiver = AvailabilityReceiver.new()
	world.add_child(receiver)
	receiver.component = component
	check(component.can_interact(actor), "未配置业务查询时保留原组件可用行为")
	component.set_availability_check(receiver.permits)
	var child_count: int = world.get_child_count()
	for query_index: int in range(3):
		check(component.can_interact(actor), "业务查询允许时第%d次仍可用" % (query_index + 1))
	check(receiver.query_count == 3 and receiver.received_actor == actor, "业务查询每次接收当前发起者")
	check(probe.request_count == 0 and not probe.state and world.get_child_count() == child_count, "重复业务查询不分发效果、不改变物体状态、不创建节点")
	component.is_enabled = false
	check(not component.can_interact(actor) and receiver.query_count == 3, "基础许可拒绝时不调用业务查询")
	component.is_enabled = true
	receiver.allowed = false
	check(not component.can_interact(actor) and not component.try_interact(actor) and probe.request_count == 0, "业务拒绝同时阻止可用显示和请求分发")
	receiver.allowed = true
	check(component.can_interact(actor), "业务状态恢复后原地恢复可用")
	receiver.allowed = false
	check(not component.try_interact(actor) and probe.request_count == 0, "显示查询之后业务状态改变时分发前重新拒绝")
	receiver.allowed = true
	check(component.try_interact(actor) and probe.request_count == 1 and probe.state, "业务允许时仍只分发一次效果请求")
	component.set_availability_check(receiver.permits_wrong_result)
	check(not component.can_interact(actor) and not component.try_interact(actor), "业务查询返回非布尔值时拒绝而不隐式转换")
	var query_count: int = receiver.query_count
	component.set_availability_check(receiver.permits_zero)
	check(not component.can_interact(actor) and receiver.query_count == query_count, "零参数业务查询在执行前被拒绝")
	component.set_availability_check(receiver.permits_two)
	check(not component.can_interact(actor) and receiver.query_count == query_count, "双参数业务查询在执行前被拒绝")
	var non_node: NonNodeAvailabilityReceiver = NonNodeAvailabilityReceiver.new()
	component.set_availability_check(non_node.permits)
	check(not component.can_interact(actor), "非节点业务查询接收者被拒绝")
	component.set_availability_check(Callable())
	check(not component.can_interact(actor) and not component.try_interact(actor), "已经配置的空查询不可伪装为从未配置")
	component.clear_availability_check()
	check(component.can_interact(actor), "明确清除业务查询后恢复兼容行为")
	component.set_availability_check(receiver.permits)
	receiver.recurse = true
	check(component.can_interact(actor) and not receiver.recursive_query_result and not receiver.recursive_dispatch_result, "业务查询再次查询或请求自身时拒绝重入且外层正常返回")
	check(probe.request_count == 1, "业务查询重入不产生额外效果")
	receiver.recurse = false
	world.remove_child(receiver)
	check(not component.can_interact(actor), "离树的业务查询接收者不可用")
	world.add_child(receiver)
	receiver.queue_free()
	check(not component.can_interact(actor) and not component.try_interact(actor), "业务查询接收者排队释放时立即拒绝")
	await frames(2)
	check(not component.can_interact(actor) and not component.try_interact(actor), "业务查询接收者释放后保持配置失效并拒绝请求")
	component.clear_availability_check()
	check(component.can_interact(actor), "失效配置只在明确清除后恢复原契约")
	probe.queue_free()
	actor.queue_free()
	await frames(2)
	await run_availability_lifetime_contracts()

func run_availability_lifetime_contracts() -> void:
	# 查询故障不得造成随后向失效依赖发射请求。
	for target_kind: int in range(5):
		var actor: Node3D = Node3D.new()
		world.add_child(actor)
		var probe: ProbeBody = new_probe(Vector3(20, 20, 20), false)
		var effect_receiver: EffectReceiver = EffectReceiver.new()
		world.add_child(effect_receiver)
		probe.component.interaction_requested.connect(effect_receiver.receive)
		var receiver: AvailabilityReceiver = AvailabilityReceiver.new()
		world.add_child(receiver)
		probe.component.set_availability_check(receiver.permits)
		var targets: Array[Node] = [actor, probe, probe.component, receiver, effect_receiver]
		receiver.release_target = targets[target_kind]
		check(not probe.component.try_interact(actor) and effect_receiver.count == 0, "查询期间第%d类依赖排队释放时取消分发" % target_kind)
		probe.queue_free()
		actor.queue_free()
		receiver.queue_free()
		effect_receiver.queue_free()
		await frames(2)

func run_geometry_and_input() -> void:
	var origin: Vector3 = player.camera.global_position
	var probe: ProbeBody = new_probe(origin + Vector3(0, 0, -1.2))
	await frames(4)
	check(available and detector.refresh_target() == probe, "边长零点一的目标在中心前方一点二米时可交互")
	var notification_count: int = availability_notifications
	await frames(5)
	check(availability_notifications == notification_count, "目标与可用性不变时不重复发状态通知")
	mouse_button(true)
	await frames(2)
	check(probe.request_count == 1 and probe.state, "真实鼠标按下经过输入分发并执行一次效果")
	await frames(12)
	check(probe.request_count == 1, "持续按住鼠标不重复分发")
	mouse_button(false)
	await frames(3)
	check(probe.request_count == 1, "鼠标松开不追加效果")
	await click()
	check(probe.request_count == 2 and not probe.state, "第二次独立按下恰好产生第二次效果")
	probe.position = origin + Vector3(0.11, 0, -1.2)
	await frames(3)
	await click()
	check(not available and detector.refresh_target() == null and probe.request_count == 2, "横向偏移零点一一后不能补选也不能点击")
	probe.position = origin + Vector3(0, 0, -1.2)
	var wall: StaticBody3D = box(Vector3(0.3, 0.3, 0.1), origin + Vector3(0, 0, -0.7))
	await frames(3)
	await click()
	check(not available and detector.get_collider() == wall and probe.request_count == 2, "普通墙体首个命中阻挡后方交互")
	wall.queue_free()
	await frames(3)
	check(available, "移除墙体后恢复直接交互")
	probe.position = origin + Vector3(0, 0, -2.2)
	await frames(3)
	await click()
	check(not available and probe.request_count == 2, "移出两米射线终点后不能点击")
	probe.position = origin + Vector3(0, 0, -1.2)
	await frames(3)
	probe.component.is_enabled = false
	await frames(3)
	await click()
	check(not available and probe.request_count == 2, "同一目标原地禁用时准星状态和点击同时拒绝")
	probe.component.is_enabled = true
	await frames(3)
	check(available, "同一目标不转镜头重新启用时自动恢复")
	probe.component.interaction_mode = AutolysisInteractionComponent.InteractionMode.FOCUS
	await frames(3)
	await click()
	check(not available and probe.request_count == 2, "同一目标切换聚焦模式时不执行直接交互")
	probe.component.interaction_mode = AutolysisInteractionComponent.InteractionMode.DIRECT
	await frames(3)
	probe.component.is_enabled = false
	mouse_button(true)
	mouse_button(false)
	check(probe.request_count == 2, "按下前刚禁用且尚未走显示帧时仍重新核查")
	probe.component.is_enabled = true
	await frames(3)
	player.body.rotation.y = PI / 2.0
	mouse_button(true)
	mouse_button(false)
	check(probe.request_count == 2, "按下前刚转离目标时刷新中心射线而不使用缓存")
	player.body.rotation = Vector3.ZERO
	await frames(3)
	probe.queue_free()
	mouse_button(true)
	mouse_button(false)
	check(probe.request_count == 2, "当前目标刚排队释放时拒绝过期点击")
	await frames(3)
	check(not available, "目标释放后清除可用状态")

func run_configuration_cases() -> void:
	var origin: Vector3 = player.camera.global_position
	var probe: ProbeBody = new_probe(origin + Vector3(0, 0, -1.2), false)
	await frames(3)
	await click()
	check(not available and probe.request_count == 0, "命中无效果连接的组件不能伪装成可执行目标")
	probe.component.interaction_requested.connect(probe.receive)
	var extra: AutolysisInteractionComponent = COMPONENT_SCENE.instantiate()
	extra.interaction_requested.connect(probe.receive_alternative)
	probe.add_child(extra)
	await frames(3)
	await click()
	check(not available and probe.request_count == 0, "物体拥有两个直接子组件时拒绝任意选择")
	extra.queue_free()
	probe.component.queue_free()
	await frames(3)
	await click()
	check(not available and probe.request_count == 0, "命中无组件物体时不分发")
	var child: ProbeBody = new_probe(Vector3(20, 20, 20))
	child.reparent(probe)
	await frames(3)
	await click()
	check(not available and child.request_count == 0, "父物体不递归借用子孙物体的组件")
	probe.queue_free()
	await frames(3)

func run_player_gates() -> void:
	var probe: ProbeBody = new_probe(player.camera.global_position + Vector3(0, 0, -1.2))
	await frames(3)
	menu_event(true)
	menu_event(false)
	await frames(3)
	await click()
	check(player.is_movement_paused and not available and probe.request_count == 0, "菜单输入开启暂停后隐藏可执行状态且拒绝点击")
	menu_event(true)
	menu_event(false)
	await frames(3)
	check(available and probe.request_count == 0, "菜单恢复不补发暂停期间的点击")
	player.is_showing_ui = true
	await frames(3)
	await click()
	check(not available and probe.request_count == 0, "界面显示标记阻止交互")
	player.is_showing_ui = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(3)
	await click()
	check(not available and probe.request_count == 0, "鼠标释放时阻止交互")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 保持眩晕标记以隔离本用例；不修改正常游戏的眩晕逻辑。
	player.set_physics_process(false)
	player.is_landing_stunned = true
	await frames(3)
	await click()
	check(not available and probe.request_count == 0, "落地眩晕时阻止交互")
	player.is_landing_stunned = false
	player.set_physics_process(true)
	paused = true
	await frames(3)
	await click()
	check(not available and probe.request_count == 0, "场景树暂停时玩家仍能刷新不可执行状态")
	paused = false
	await frames(3)
	check(available and probe.request_count == 0, "所有门控解除后不补发旧点击")
	await click()
	check(probe.request_count == 1, "门控恢复只接受新的鼠标按下")
	probe.queue_free()
	await frames(3)

func run_gui_priority() -> void:
	var probe: ProbeBody = new_probe(player.camera.global_position + Vector3(0, 0, -1.2))
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 100
	world.add_child(canvas)
	var consumer: ClickConsumer = ClickConsumer.new()
	consumer.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(consumer)
	consumer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(3)
	await click()
	check(consumer.consumed == 1 and probe.request_count == 0, "真实控件消费左键后游戏交互入口不执行")
	canvas.queue_free()
	await frames(3)
	await click()
	check(probe.request_count == 1, "消费控件移除后准星自身不拦截鼠标")
	probe.queue_free()
	await frames(3)

func run_effect_release_cases() -> void:
	var probe: ProbeBody = new_probe(player.camera.global_position + Vector3(0, 0, -1.2), false)
	var receiver: EffectReceiver = EffectReceiver.new()
	receiver.release_target = probe
	world.add_child(receiver)
	probe.component.interaction_requested.connect(receiver.receive)
	await frames(3)
	check(available, "释放效果执行前目标有效且可用")
	await click()
	check(receiver.count == 1 and not is_instance_valid(probe) and not available, "效果回调排队释放目标后清空可用状态且无重复请求")
	receiver.queue_free()
	await frames(2)
	probe = new_probe(player.camera.global_position + Vector3(0, 0, -1.2), false)
	receiver = EffectReceiver.new()
	world.add_child(receiver)
	probe.component.interaction_requested.connect(receiver.receive)
	await frames(3)
	check(available, "点击前立即释放用例初始目标已选中")
	# 信号发射中的源对象必须排队释放；这里在发射前销毁，验证过期选择。
	probe.free()
	await click()
	check(receiver.count == 0 and not available, "目标在点击前立即释放后不访问过期选择也不分发")
	receiver.queue_free()
	await frames(2)
func run_dependency_release() -> void:
	var probe: ProbeBody = new_probe(player.camera.global_position + Vector3(0, 0, -1.2))
	await frames(3)
	check(available, "检测器释放用例初始拥有可用目标")
	detector.queue_free()
	await frames(3)
	await click()
	check(not available and not controller.is_direct_available() and probe.request_count == 0, "检测器依赖释放后清除可用状态且拒绝点击")
	probe.queue_free()
	await frames(3)
func aim_at(point: Vector3) -> void:
	player.body.rotation = Vector3.ZERO
	player.neck.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.camera.look_at(point, Vector3.UP)
	await frames(3)

func run_actual_demo() -> void:
	world.queue_free()
	await frames(3)
	var scene: PackedScene = load("res://main-autolysis/player/tests/direct_interaction_demo.tscn")
	var demo: AutolysisDirectInteractionDemo = scene.instantiate()
	world = demo
	root.add_child(world)
	player = demo.get_node("Player")
	await reset_player(Vector3(0, 0.8, 0))
	attach_player()
	await frames(3)
	check(available and detector.refresh_target() == demo.switch_a, "验证场景出生后中心直接看见可操作开关甲")
	await click()
	check(demo.switch_a_on and demo.switch_a_indicator.visible and demo.switch_a_requests == 1 and demo.switch_b_requests == 0, "点击开关甲只改变甲的真实网格可见状态")
	await aim_at(demo.switch_b.global_position)
	await click()
	check(demo.switch_b_on and demo.switch_b_indicator.visible and demo.switch_b_requests == 1 and demo.switch_a_requests == 1, "点击相邻开关乙不串联开关甲")
	await aim_at(demo.door.global_position + Vector3(0.5, 1.5, 0))
	var mesh: MeshInstance3D = demo.door.get_node("Mesh")
	var collision: CollisionShape3D = demo.door.get_node("CollisionShape3D")
	var closed_position: Vector3 = collision.global_position
	check(detector.refresh_target() == demo.door, "真实门的关闭碰撞形状被中心射线命中")
	mouse_button(true)
	check(not demo.door_component.is_enabled, "门请求立即置忙避免等待物理帧期间重复请求")
	mouse_button(false)
	await frames(5)
	check(demo.door_is_open and demo.door_requests == 1 and is_equal_approx(demo.door.rotation.y, -PI / 2.0), "鼠标请求后物理门自身实际转动九十度")
	check(mesh.global_transform.is_equal_approx(collision.global_transform) and collision.global_position.distance_to(closed_position) > 0.5, "门模型与碰撞共同随门轴变换")
	await aim_at(collision.global_position)
	check(detector.refresh_target() == demo.door, "旋转后的门碰撞形状仍能被新的中心射线命中")
	await click()
	check(not demo.door_is_open and demo.door_requests == 2 and collision.global_position.is_equal_approx(closed_position), "第二次点击真实门关闭且碰撞恢复")
	if DisplayServer.get_name() != "headless":
		await run_rendered_checks(demo)
	else:
		print("未执行图像验收：当前为无图形运行，不能证明准星像素和实际渲染外观。")

func run_rendered_checks(demo: AutolysisDirectInteractionDemo) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR))
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1279, 719)]:
		root.size = viewport_size
		await frames(5)
		await aim_at(demo.switch_a.global_position)
		check(available, "图像验收前真实目标可直接交互")
		await capture_and_measure(viewport_size, true)
		await aim_at(player.camera.global_position + Vector3(0, 2, 0.1))
		check(not available, "图像验收空处只有基础准星状态")
		await capture_and_measure(viewport_size, false)
	await aim_at(demo.switch_a.global_position)
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	check(rendered.save_png(ARTIFACT_DIR + "/demo-effects.png") == OK, "保存门和两开关完成效果后的场景截图")

func capture_and_measure(expected_size: Vector2i, expanded: bool, subdirectory: String = "") -> void:
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	check(rendered.get_size() == expected_size, "实际渲染视口尺寸为 %d×%d" % [expected_size.x, expected_size.y])
	var file_name: String = "%s/%dx%d-%s.png" % [ARTIFACT_DIR + subdirectory, expected_size.x, expected_size.y, "available" if expanded else "base"]
	check(rendered.save_png(file_name) == OK, "保存实际渲染准星图像：" + file_name)
	# 验证依据直接写成独立像素区域，不读取生产准星的内部尺寸字段。
	var center: Vector2i = Vector2i(floori(rendered.get_width() / 2.0), floori(rendered.get_height() / 2.0))
	var wrong: int = 0
	var white_count: int = 0
	for offset_y: int in range(-31, 31):
		for offset_x: int in range(-31, 31):
			var central: bool = offset_x >= -1 and offset_x < 1 and offset_y >= -1 and offset_y < 1
			var vertical: bool = offset_x >= -1 and offset_x < 1 and ((offset_y >= -29 and offset_y < -9) or (offset_y >= 9 and offset_y < 29))
			var horizontal: bool = offset_y >= -1 and offset_y < 1 and ((offset_x >= -29 and offset_x < -9) or (offset_x >= 9 and offset_x < 29))
			var expected_white: bool = central or (expanded and (vertical or horizontal))
			var pixel: Color = rendered.get_pixel(center.x + offset_x, center.y + offset_y)
			var actual_white: bool = pixel.r > 0.97 and pixel.g > 0.97 and pixel.b > 0.97
			if actual_white:
				white_count += 1
			if actual_white != expected_white:
				wrong += 1
	var expected_count: int = 164 if expanded else 4
	check(wrong == 0 and white_count == expected_count, "%d×%d准星实测：错位像素%d，白色像素%d，应为%d；中心二乘二、四线二十乘二、边缘间隔八像素" % [expected_size.x, expected_size.y, wrong, white_count, expected_count])

func run_crosshair_only() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "独立准星像素验收必须使用有图形渲染器")
		return
	RenderingServer.set_default_clear_color(Color.BLACK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR + "/crosshair-only"))
	var crosshair_scene: PackedScene = load("res://main-autolysis/ui/autolysis_crosshair.tscn")
	var canvas: CanvasLayer = crosshair_scene.instantiate()
	root.add_child(canvas)
	var crosshair: Control = canvas.get_node("Crosshair")
	check(crosshair.mouse_filter == Control.MOUSE_FILTER_IGNORE and crosshair.focus_mode == Control.FOCUS_NONE, "独立准星忽略鼠标并且不抢键盘焦点")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1279, 719)]:
		root.size = viewport_size
		await frames(5)
		for expanded: bool in [false, true]:
			crosshair.set_direct_available(expanded)
			await frames(3)
			await capture_and_measure(viewport_size, expanded, "/crosshair-only")
	canvas.queue_free()
	await frames(2)

func run_checks() -> void:
	_original_accumulation = Input.use_accumulated_input
	Input.use_accumulated_input = false
	if "--crosshair-only" in OS.get_cmdline_user_args():
		await run_crosshair_only()
		Input.use_accumulated_input = _original_accumulation
		print("独立准星失败总数：", failures)
		quit(1 if failures else 0)
		return
	world = Node3D.new()
	root.add_child(world)
	await run_component_contracts()
	await run_availability_contracts()
	if "--component-only" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		world.queue_free()
		await frames(2)
		Input.use_accumulated_input = _original_accumulation
		if DisplayServer.get_name() == "headless":
			print("无图形后端不提供捕获鼠标状态；本次仅验证独立组件。完整玩家输入、五项门控、界面优先、生命周期、实际门与开关、准星像素须由有图形运行验收。严格射线另由组件迁移检查覆盖。")
		print("独立组件失败总数：", failures)
		quit(1 if failures else 0)
		return
	box(Vector3(100, 1, 100), Vector3(0, -0.5, 0))
	player = load("res://main-autolysis/player/autolysis_player.tscn").instantiate()
	world.add_child(player)
	await reset_player()
	attach_player()
	await frames(3)
	check(not available, "面向空处初始不显示直接交互状态")
	await run_geometry_and_input()
	await run_configuration_cases()
	await run_player_gates()
	await run_gui_priority()
	await run_effect_release_cases()
	await run_dependency_release()
	await run_actual_demo()
	mouse_button(false)
	Input.action_release("interact_direct")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.use_accumulated_input = _original_accumulation
	world.queue_free()
	await frames(3)
	print("直接交互失败总数：", failures)
	quit(1 if failures else 0)







