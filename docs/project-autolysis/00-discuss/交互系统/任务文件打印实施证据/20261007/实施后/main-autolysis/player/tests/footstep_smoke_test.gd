extends "res://main-autolysis/player/tests/player_smoke_test.gd"

var events: Array[Dictionary] = []

func heard(profile: AudioStreamRandomizer, landing: bool) -> void:
	events.append({"profile": profile, "landing": landing, "volume": player.footstep_player.volume_db})

func step_count() -> int:
	var total: int = 0
	for event in events:
		if not event.landing:
			total += 1
	return total

func run_checks() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_body := box(Vector3(100, 1, 100), Vector3(0, -0.5, 0))
	player = load("res://main-autolysis/player/autolysis_player.tscn").instantiate()
	world.add_child(player)
	player.footstep_player.sound_played.connect(heard)
	await reset_player()
	events.clear()
	await frames(120)
	check(events.is_empty(), "站立不播放脚步")
	Input.action_press("forward")
	await frames(120)
	var walking_count: int = step_count()
	check(walking_count >= 3 and walking_count <= 5, "行走节奏与原步态周期一致")
	check(events.back().volume == -25.0, "行走音量沿用原配置")
	check(events.back().profile == player.footstep_player.generic_fallback_footstep_profile, "没有地面标记时播放默认音效")
	Input.action_release("forward")
	var count: int = events.size()
	await frames(120)
	check(events.size() == count, "停止输入后不产生额外脚步")
	await reset_player()
	events.clear()
	Input.action_press("forward")
	Input.action_press("sprint")
	await frames(120)
	check(step_count() > walking_count, "冲刺脚步频率高于行走")
	check(events.back().volume == -20.0, "冲刺音量沿用原配置")
	await reset_player()
	await tap("crouch")
	events.clear()
	Input.action_press("forward")
	await frames(120)
	check(step_count() > 0 and step_count() < walking_count, "蹲行脚步频率低于行走")
	check(events.back().volume == -38.0, "蹲行音量沿用原配置")
	await reset_player()
	var wall := box(Vector3(5, 3, 0.5), Vector3(0, 1.5, -2))
	Input.action_press("forward")
	await frames(120)
	events.clear()
	await frames(120)
	check(events.is_empty(), "持续顶墙但无实际位移时不播放脚步")
	wall.queue_free()
	await reset_player()
	Input.action_press("forward")
	player.is_movement_paused = true
	events.clear()
	await frames(90)
	check(events.is_empty(), "移动暂停时不播放脚步")
	player.is_movement_paused = false
	Input.action_release("forward")
	await reset_player()
	player.position = Vector3(0, 8, 0)
	player.main_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	events.clear()
	await frames(30)
	check(events.is_empty(), "空中不播放脚步或落地音效")
	await frames(180)
	check(events.size() == 1 and events[0].landing, "一次下落只触发一次落地声音")
	check(player.footstep_player.get_node("LandingPlayer").volume_db == 0.0, "重落地音量达到上限")
	check(is_equal_approx(player.footstep_player.get_node("LandingPlayer").pitch_scale, 0.7), "重落地音调沿用原配置")
	await reset_player()
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(100, 1, 100)
	mesh.material = load("res://main-autolysis/systems/dynamic-footstep-system/assets/materials/example_dirt.tres")
	mesh_node.mesh = mesh
	mesh_node.material_override = load("res://main-autolysis/systems/dynamic-footstep-system/assets/materials/example_wood.tres")
	floor_body.add_child(mesh_node)
	await frames(2)
	events.clear()
	player.footstep_player.play_footstep()
	check(events.size() == 1 and events[0].profile == load("res://main-autolysis/systems/dynamic-footstep-system/footstep-profiles/wood_footstep_profile.tres"), "节点覆盖材质正确映射木质音效")
	mesh_node.material_override = null
	mesh_node.set_surface_override_material(0, load("res://main-autolysis/systems/dynamic-footstep-system/assets/materials/example_stone.tres"))
	events.clear()
	player.footstep_player.play_footstep()
	check(events.size() == 1 and events[0].profile == load("res://main-autolysis/systems/dynamic-footstep-system/footstep-profiles/stone_footstep_profile.tres"), "表面覆盖材质正确映射石质音效")
	mesh_node.set_surface_override_material(0, null)
	events.clear()
	player.footstep_player.play_footstep()
	check(events.size() == 1 and events[0].profile == load("res://main-autolysis/systems/dynamic-footstep-system/footstep-profiles/dirt_footstep_profile.tres"), "网格基础材质正确映射泥土音效")
	var surface = floor_body.get_child(0)
	surface.set_script(load("res://main-autolysis/systems/dynamic-footstep-system/scripts/footstep_surface.gd"))
	surface.footstep_profile = load("res://main-autolysis/systems/dynamic-footstep-system/footstep-profiles/grass_footstep_profile.tres")
	events.clear()
	player.footstep_player.play_footstep()
	check(events.size() == 1 and events[0].profile == surface.footstep_profile, "碰撞形状上的脚步配置优先于材质映射")
	player.footstep_player.play_landing(-4.0)
	check(events.back().landing and events.back().profile == surface.footstep_profile, "落地使用同一地面配置")
	floor_body.collision_layer = 8
	await frames(3)
	events.clear()
	player.footstep_player.play_footstep()
	check(player.is_on_floor() and events.size() == 1 and events[0].profile == surface.footstep_profile, "第四层脚下实体维持着地并通过实际脚步射线读取配置")
	floor_body.collision_layer = 1
	var resource_failures: int = 0
	for file in DirAccess.get_files_at("res://main-autolysis/systems/dynamic-footstep-system/footstep-profiles"):
		if not file.ends_with(".tres"):
			continue
		var profile: AudioStreamRandomizer = load("res://main-autolysis/systems/dynamic-footstep-system/footstep-profiles/" + file)
		if profile == null or profile.streams_count == 0:
			resource_failures += 1
		else:
			for index in range(profile.streams_count):
				if profile.get_stream(index) == null:
					resource_failures += 1
	check(resource_failures == 0, "所有脚步音效配置的音频均可加载")
	if DisplayServer.get_name() != "headless":
		var bus: int = AudioServer.get_bus_index("SFX")
		var capture := AudioEffectCapture.new()
		AudioServer.add_bus_effect(bus, capture)
		var start: int = Time.get_ticks_msec()
		var next_sound: int = start
		var peak: float = 0.0
		while Time.get_ticks_msec() - start < 1800:
			if Time.get_ticks_msec() >= next_sound:
				player.footstep_player.play_footstep()
				next_sound += 300
			await process_frame
			for sample in capture.get_buffer(capture.get_frames_available()):
				peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
		check(peak > 0.000001, "真实音频总线输出非零波形")
		print("音频峰值：", peak)
	world.queue_free()
	await frames(3)
	var scene: Node = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate()
	root.add_child(scene)
	await frames(100)
	var floor_count: int = 0
	var collision_profiles: int = 0
	var extra_nodes: int = 0
	for floor_node: Node in scene.get_node("Environment/floor").get_children():
		if not floor_node.name.begins_with("floor_stone_"):
			continue
		floor_count += 1
		var collision: CollisionShape3D = floor_node.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision != null and collision.get_script() == load("res://main-autolysis/systems/dynamic-footstep-system/scripts/footstep_surface.gd"):
			var floor_profile: AudioStreamRandomizer = collision.get("footstep_profile") as AudioStreamRandomizer
			var has_audio: bool = floor_profile != null and floor_profile.streams_count > 0
			if has_audio:
				for stream_index: int in range(floor_profile.streams_count):
					if floor_profile.get_stream(stream_index) == null:
						has_audio = false
						break
			if has_audio:
				collision_profiles += 1
		if floor_node.has_node("FootstepSurface"):
			extra_nodes += 1
	print("主场景石质地面实测数量：", floor_count, "；正确脚步配置：", collision_profiles, "；额外脚步节点：", extra_nodes)
	check(floor_count > 0 and collision_profiles == floor_count and extra_nodes == 0, "%d块实际地面均在碰撞形状上配置脚步和非空音效且无额外节点" % floor_count)
	var local_profile = scene.get_node("Environment/floor/floor_stone_4/CollisionShape3D").footstep_profile
	check(local_profile.resource_path.contains("::") and local_profile.streams_count == 4, "保留原场景第四块地面的内嵌四音频配置")
	player = scene.get_node("autolysis_player")
	player.footstep_player.sound_played.connect(heard)
	events.clear()
	player.footstep_player.play_footstep()
	check(events.size() == 1 and events[0].profile == load("res://main-autolysis/systems/dynamic-footstep-system/footstep-profiles/stone_footstep_profile.tres"), "默认场景出生地面使用石质脚步音效")
	scene.queue_free()
	await frames(3)
	var demo: PackedScene = load("res://main-autolysis/systems/dynamic-footstep-system/dynamic_footstep_demo_scene.tscn")
	check(demo != null and demo.can_instantiate(), "脚步演示场景可以独立加载")
	print("失败总数：", failures)
	quit(1 if failures else 0)
