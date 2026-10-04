extends SceneTree
class EventProbe extends Node:
	var calls: int = 0
	func record() -> void:
		calls += 1
func _initialize() -> void:
	_run.call_deferred()
func restore(player: AnimationPlayer) -> void:
	player.stop(true)
	player.assigned_animation = &"move"
	player.seek(0.0, true, true)
	player.pause()
func _run() -> void:
	var world := Node3D.new()
	var receiver := EventProbe.new()
	receiver.name = "Event"
	world.add_child(receiver)
	var player := AnimationPlayer.new()
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.playback_auto_capture = false
	var animation := Animation.new()
	animation.length = 0.2
	var event_track := animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(event_track, NodePath("Event"))
	animation.track_insert_key(event_track, 0.0, {"method": &"record", "args": []})
	var library := AnimationLibrary.new()
	library.add_animation(&"move", animation)
	player.add_animation_library(&"", library)
	world.add_child(player)
	root.add_child(world)
	player.root_node = NodePath("..")
	restore(player)
	await process_frame
	print("初次属性初始化事件数：", receiver.calls)
	player.play(&"move", 0.0)
	restore(player)
	await process_frame
	print("接受请求同帧取消后的事件数：", receiver.calls)
	player.play(&"move", 0.0)
	player.advance(0.0)
	restore(player)
	await process_frame
	print("主动消费合法请求再取消后的累计事件数：", receiver.calls)
	player.play(&"move", 0.0)
	player.stop(true)
	var isolated: Animation = animation.duplicate()
	isolated.track_set_enabled(event_track, false)
	library.remove_animation(&"move")
	library.add_animation(&"move", isolated)
	restore(player)
	library.remove_animation(&"move")
	library.add_animation(&"move", animation)
	player.assigned_animation = &"move"
	player.seek(0.0, true, true)
	player.pause()
	await process_frame
	print("外部播放后用隔离属性副本恢复的累计事件数：", receiver.calls)
	print("原资源事件轨道仍启用：", animation.track_is_enabled(event_track))
	world.queue_free()
	await process_frame
	quit()