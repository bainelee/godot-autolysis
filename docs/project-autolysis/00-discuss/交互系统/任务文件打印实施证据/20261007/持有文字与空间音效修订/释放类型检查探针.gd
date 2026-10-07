extends SceneTree

func _initialize() -> void:
	var released_audio: Variant = AudioStreamPlayer3D.new()
	released_audio.free()
	call_deferred("quit")
	print("已释放三维节点类型检查：", released_audio is AudioStreamPlayer3D)
