extends SceneTree
## 单独复验纯展示入树观察立即释放候选的原生边界，不依赖设备或纸张场景。

const PRESENTER: Script = preload("res://main-autolysis/player/components/autolysis_held_item_presenter.gd")

var candidate: Node3D
var presenter: Node3D


func _initialize() -> void:
	call_deferred("run_probe")


func _free_candidate(display: Node) -> void:
	print("候选入树观察：立即释放")
	display.free()


func run_probe() -> void:
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	presenter = Node3D.new()
	presenter.set_script(PRESENTER)
	root.add_child(presenter)
	presenter.child_entered_tree.connect(_free_candidate)
	candidate = Node3D.new()
	presenter.commit_prepared(candidate)
	var released: bool = not is_instance_valid(candidate)
	print(("通过：" if released else "失败：") + "候选立即释放由实际入树观察触发")
	print(("通过：" if presenter.get_display() == null else "失败：") + "释放后的候选不作为有效持物显示")
	presenter.queue_free()
	await process_frame
	quit(0 if released else 1)
