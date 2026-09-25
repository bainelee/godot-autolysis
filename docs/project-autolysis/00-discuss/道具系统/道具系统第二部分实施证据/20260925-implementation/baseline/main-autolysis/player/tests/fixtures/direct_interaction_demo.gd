class_name AutolysisDirectInteractionDemo
extends Node3D

# 仅用于交互验收：两个开关分别改变可见状态，门在物理帧内转动自身。
var switch_a_on: bool = false
var switch_b_on: bool = false
var switch_a_requests: int = 0
var switch_b_requests: int = 0
var door_requests: int = 0
var door_is_open: bool = false
var _door_change_pending: bool = false

@onready var switch_a: StaticBody3D = $SwitchA
@onready var switch_b: StaticBody3D = $SwitchB
@onready var door: AnimatableBody3D = $Door
@onready var switch_a_indicator: MeshInstance3D = $SwitchA/Indicator
@onready var switch_b_indicator: MeshInstance3D = $SwitchB/Indicator
@onready var door_component: AutolysisInteractionComponent = $Door/Interaction
@onready var status: Label = $Instructions/Status

func _ready() -> void:
	set_physics_process(false)
	_update_status()

func _on_switch_a_requested(_actor: Node3D) -> void:
	switch_a_requests += 1
	switch_a_on = not switch_a_on
	switch_a_indicator.visible = switch_a_on
	_update_status()
	print("开关甲：", switch_a_on, "，请求次数：", switch_a_requests)

func _on_switch_b_requested(_actor: Node3D) -> void:
	switch_b_requests += 1
	switch_b_on = not switch_b_on
	switch_b_indicator.visible = switch_b_on
	_update_status()
	print("开关乙：", switch_b_on, "，请求次数：", switch_b_requests)

func _on_door_requested(_actor: Node3D) -> void:
	door_requests += 1
	_door_change_pending = true
	door_component.is_enabled = false
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if not _door_change_pending:
		return
	door_is_open = not door_is_open
	door.reset_physics_interpolation()
	door.rotation.y = -PI / 2.0 if door_is_open else 0.0
	door.reset_physics_interpolation()
	_door_change_pending = false
	door_component.is_enabled = true
	set_physics_process(false)
	_update_status()
	print("门已", "打开" if door_is_open else "关闭", "，请求次数：", door_requests)

func _update_status() -> void:
	status.text = "开关甲：%s（%d次）　开关乙：%s（%d次）　门：%s（%d次）" % [
		"开启" if switch_a_on else "关闭", switch_a_requests,
		"开启" if switch_b_on else "关闭", switch_b_requests,
		"打开" if door_is_open else "关闭", door_requests]
