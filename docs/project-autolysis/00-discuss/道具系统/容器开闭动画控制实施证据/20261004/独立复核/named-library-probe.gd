extends SceneTree
func _initialize() -> void:
	var source := AnimationPlayer.new()
	var animation := Animation.new()
	var source_library := AnimationLibrary.new()
	source_library.add_animation(&"move", animation)
	source.add_animation_library(&"bank", source_library)
	print("源播放器限定名称有效：", source.has_animation(&"bank/move"))
	var runtime_library := AnimationLibrary.new()
	var result: Error = runtime_library.add_animation(&"bank/move", source.get_animation(&"bank/move"))
	print("复制限定名称到空库的返回码：", result)
	print("运行库含目标动作：", runtime_library.has_animation(&"bank/move"))
	source.free()
	quit()