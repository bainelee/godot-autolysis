extends "res://main-autolysis/player/tests/player_smoke_test.gd"
## 正式主场景合法内容图形夹具；不声称人工配药或人工鼠标验收。

const MAIN_SCENE: PackedScene = preload("res://main-autolysis/scenes/01-autolysis-test.tscn")

var evidence_directory: String = preload("res://main-autolysis/systems/item-system/tests/test_evidence.gd").directory("res://docs/project-autolysis/00-discuss/道具系统/液体罐内容与配药器装填实施证据/20261002/main-rendered")
var assertions: Array[Dictionary] = []
var screenshots: Array[String] = []
var avatar: AutolysisPlayer
var cabinet: AutolysisLiquidTankCabinet
var machine: AutolysisBlendMachine
var inventory: AutolysisInventoryController
var held_text: String = ""
var panel_rect: Rect2


func check(condition: bool, description: String) -> void:
	super.check(condition, description)
	assertions.append({"说明": description, "通过": condition})


func run_checks() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("正式主场景液体内容画面检查需要实际图形后端。")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_directory))
	root.size = Vector2i(1280, 720)
	world = MAIN_SCENE.instantiate() as Node3D
	root.add_child(world)
	await frames(12)
	avatar = world.get_node("autolysis_player") as AutolysisPlayer
	player = avatar
	inventory = avatar.inventory_controller
	cabinet = world.get_node("interaction_prefabs/place_shelf_and_cabinet/cabinet_workroom_0") as AutolysisLiquidTankCabinet
	machine = world.get_node("interaction_prefabs/machines/machine_blend_0") as AutolysisBlendMachine
	check(cabinet.is_configured() and machine.is_configured(), "正式主场景现有柜子与配药器配置有效")
	avatar.set_physics_process(false)
	avatar.is_movement_paused = false
	avatar.is_showing_ui = false
	avatar._clear_landing_stun()
	avatar.global_position = cabinet.to_global(Vector3(-0.58, 0.9, 1.8))
	avatar.velocity = Vector3.ZERO
	avatar.main_velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var filled: AutolysisLiquidTank = cabinet.get_item_at_slot(0)
	var empty: AutolysisLiquidTank = cabinet.get_item_at_slot(1)
	check(filled != null and empty != null and filled.item_instance != empty.item_instance, "正式柜内两只同定义罐具有独立实例")
	var ids: Array[String] = ["caffeine", "sodium_benzoate", "caffeine", "sodium_benzoate"]
	var fixture: AutolysisLiquidContents = AutolysisLiquidContents.create_result(ids)
	check(fixture != null and fixture.set_phase_rgb(Vector3(2.5, -3, 8)) and fixture.set_wave(true, false, true, true, 6), "图形夹具使用合法重复原药和非零重构数据")
	check(filled.apply_contents(fixture), "仅给柜内零号罐写入合法图形夹具内容")
	var original_instance: AutolysisItemInstance = filled.item_instance
	var original_contents: AutolysisLiquidContents = original_instance.liquid_contents
	check(original_contents.get_raw_material_ids() == ids and original_contents.get_raw_material_display() == "咖啡因*2、苯甲酸钠*2", "显示按首次顺序合并且内部保留四条原药")
	check(empty.is_empty() and empty.item_instance.liquid_contents == null, "同定义一号罐继续为空且无内容资源")
	check(AutolysisLiquidTankVisual.get_contents_mesh(filled).material_override == AutolysisLiquidTankVisual.FILLED_MATERIAL and AutolysisLiquidTankVisual.get_contents_mesh(empty).material_override == AutolysisLiquidTankVisual.EMPTY_MATERIAL, "正式柜内空满罐使用独立材质覆盖引用")
	check(cabinet.try_toggle(avatar), "正式柜门业务打开现有柜门")
	await frames(22)
	check(cabinet.is_open(), "柜门完全打开可观察两只罐")
	# 使用正式蹲下动作降低观察高度，保留主场景柜与上方机器原布局。
	avatar.set_physics_process(true)
	Input.action_press("crouch")
	await frames(45)
	Input.action_release("crouch")
	avatar.set_physics_process(false)
	avatar.body.rotation = Vector3.ZERO
	avatar.neck.rotation = Vector3.ZERO
	avatar.eyes.rotation = Vector3.ZERO
	avatar.camera.rotation = Vector3.ZERO
	avatar.head.look_at((filled.global_position + empty.global_position) * 0.5, Vector3.UP)
	await frames(4)
	check(not avatar.liquid_contents_panel.is_showing_contents(), "空手观察柜内空满罐时内容界面隐藏")
	await _capture("01-正式柜内空满并列.png")
	check(inventory.try_take_liquid_tank(avatar, filled) and inventory.get_focused_instance() == original_instance, "正式库存取回满罐保留原实例")
	check(inventory.get_focused_instance().liquid_contents == original_contents, "满罐转移保持原独立内容引用")
	check(avatar.focus_controller.try_enter(machine.focus_target), "现有正式配药器接管观察视角")
	await frames(16)
	check(avatar.focus_controller.is_focused_on(machine.focus_target), "正式配药器稳定聚焦")
	check(avatar.liquid_contents_panel.is_showing_contents(), "正式玩家手持满罐时显示内容界面")
	held_text = avatar.liquid_contents_panel.get_contents_text()
	check(held_text.contains("原药：咖啡因*2、苯甲酸钠*2") and held_text.contains("r（红）＝2.5") and held_text.contains("g（绿）＝-3") and held_text.contains("b（蓝）＝8") and held_text.contains("（1，0，1，1，6）"), "正式玩家内容文本完整显示重复合并与非零相位波形")
	var panel: PanelContainer = avatar.liquid_contents_panel.get_node("Panel") as PanelContainer
	var label: Label = avatar.liquid_contents_panel.get_node("Panel/Margin/Text") as Label
	panel_rect = panel.get_global_rect()
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(panel_rect) and label.size.x >= label.get_minimum_size().x, "内容面板在实际窗口范围内且文本宽度未裁切")
	check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "满罐内容文本与背景忽略鼠标")
	check(AutolysisLiquidTankVisual.get_contents_mesh(avatar.held_item_presenter.get_display()).material_override == AutolysisLiquidTankVisual.FILLED_MATERIAL and AutolysisLiquidTankVisual.get_contents_mesh(empty).material_override == AutolysisLiquidTankVisual.EMPTY_MATERIAL, "手持满材质与原柜中空材质保持独立")
	await _capture("02-正式配药器手持内容界面.png")
	_save_report()
	Input.action_release("crouch")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.queue_free()
	await frames(2)
	print("正式主场景液体内容图形断言数：", assertions.size(), "；失败：", failures)
	quit(1 if failures > 0 else 0)


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var saved: bool = root.get_texture().get_image().save_png(evidence_directory.path_join(filename)) == OK
	check(saved, "保存实际正式主场景画面：" + filename)
	if saved:
		screenshots.append(filename)


func _save_report() -> void:
	var file: FileAccess = FileAccess.open(evidence_directory.path_join("正式主场景液体内容画面报告.json"), FileAccess.WRITE)
	if file == null:
		check(false, "图形证据报告可写")
		return
	file.store_string(JSON.stringify({"引擎": Engine.get_version_info(), "图形后端": DisplayServer.get_name(), "窗口大小": str(root.size), "断言数": assertions.size(), "失败数": failures, "断言": assertions, "手持文本": held_text, "面板范围": str(panel_rect), "画面": screenshots, "夹具范围": "正式主场景内仅构造合法内容供图形检查；不声称人工配药或人工鼠标验收；不修改主场景布局"}, "\t"))
	file.close()
