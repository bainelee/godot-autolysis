extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var player: AutolysisPlayer = load("res://main-autolysis/player/autolysis_player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var animation: AnimationPlayer = player.animationPlayer
	for speed: float in [0.4, -0.4]:
		animation.play(&"jump", -1.0, speed)
		animation.seek(0.15, true)
		print("原状态：", animation.current_animation_position, "，速度：", animation.get_playing_speed())
		player.begin_focus_control()
		print("暂停：", animation.current_animation_position, "，保存速度：", player._focus_animation_speed)
		player.end_focus_control()
		print("恢复：", animation.current_animation_position, "，速度：", animation.get_playing_speed())
		animation.advance(1.0 / 60.0)
		print("下一帧：", animation.current_animation_position, "，速度：", animation.get_playing_speed())
	player.free()
	quit()
