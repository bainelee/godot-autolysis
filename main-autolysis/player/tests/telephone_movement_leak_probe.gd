extends "res://main-autolysis/player/tests/telephone_movement_test.gd"
## 资源退出诊断：关闭运行期输出以复现原执行时序，退出前恢复详细输出。


func run_checks() -> void:
	if "--load-only" in OS.get_cmdline_user_args():
		world = load("res://main-autolysis/scenes/01-autolysis-test.tscn").instantiate()
		root.add_child(world)
		await frames(3)
		world.queue_free()
		await frames(3)
		quit()
		return
	Engine.print_to_stdout = false
	await super.run_checks()
	Engine.print_to_stdout = true
