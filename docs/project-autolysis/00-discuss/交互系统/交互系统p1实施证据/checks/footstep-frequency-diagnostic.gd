extends "res://main-autolysis/player/tests/player_smoke_test.gd"

var records: Array[Dictionary] = []
var diagnostic_load: Node = null

class DisplayStall extends Node:
	var count: int = 0
	func _process(_delta: float) -> void:
		count += 1
		if count % 12 == 0:
			OS.delay_msec(45)

func heard(_profile: AudioStreamRandomizer, landing: bool) -> void:
	if not landing:
		records.append({"frame": Engine.get_physics_frames(), "phase": player.wiggle_index, "speed": player.get_real_velocity().length(), "grounded": player.is_on_floor()})

func measure(sprinting: bool, use_display_stall: bool = false) -> Dictionary:
	records.clear()
	var start_frame: int = Engine.get_physics_frames()
	var start_phase: float = player.wiggle_index
	var start_ticks: int = Time.get_ticks_msec()
	Input.action_press("forward")
	if sprinting:
		Input.action_press("sprint")
	if use_display_stall:
		diagnostic_load = DisplayStall.new()
		world.add_child(diagnostic_load)
	await frames(120)
	var result: Dictionary = {"sprinting": sprinting, "controlled_display_stall": use_display_stall, "physics_frames": Engine.get_physics_frames() - start_frame, "elapsed_ms": Time.get_ticks_msec() - start_ticks, "phase_start": start_phase, "phase_end": player.wiggle_index, "count": records.size(), "samples": records.duplicate(true), "speed_end": player.current_speed, "grounded_end": player.is_on_floor()}
	if diagnostic_load != null:
		diagnostic_load.queue_free()
		diagnostic_load = null
	Input.action_release("forward")
	Input.action_release("sprint")
	print("步态诊断：", JSON.stringify(result))
	return result

func run_checks() -> void:
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(100, 1, 100), Vector3(0, -0.5, 0))
	player = load("res://main-autolysis/player/autolysis_player.tscn").instantiate()
	world.add_child(player)
	player.footstep_player.sound_played.connect(heard)
	for iteration: int in range(3):
		await reset_player()
		await frames(120)
		var walk: Dictionary = await measure(false)
		await frames(120)
		await reset_player()
		var sprint: Dictionary = await measure(true)
		print("正常重复结果：", iteration, "，行走", walk.count, "，冲刺", sprint.count, "，原断言", sprint.count > walk.count)
	await reset_player()
	var delayed_walk: Dictionary = await measure(false, true)
	await reset_player()
	var ordinary_sprint: Dictionary = await measure(true)
	print("显示停顿复现：行走", delayed_walk.count, "，冲刺", ordinary_sprint.count, "，原断言", ordinary_sprint.count > delayed_walk.count)
	world.queue_free()
	await frames(3)
	quit()
