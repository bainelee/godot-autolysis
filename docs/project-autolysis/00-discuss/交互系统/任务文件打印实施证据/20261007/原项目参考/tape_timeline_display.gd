@tool
extends Node3D

## 3D 时间轴显示（Tape Timeline Display）：SubViewport（子视口）贴屏 Quad（需求 §4）。

const PANEL_PIXEL_SIZE := Vector2i(100, 40)
const QUAD_MATERIAL := preload("res://main-degauss/recorder/ui/tape_timeline_quad_material.tres")

@export var panel_pixel_size: Vector2i = PANEL_PIXEL_SIZE:
	set(value):
		panel_pixel_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_apply_panel_size()

@export var quad_width: float = 0.18:
	set(value):
		quad_width = maxf(value, 0.001)
		_apply_panel_size()

@onready var _viewport: SubViewport = $SubViewport
@onready var _quad: MeshInstance3D = $TimelineQuad


func _enter_tree() -> void:
	call_deferred("_apply_panel_size")
	if Engine.is_editor_hint():
		call_deferred("_bind_viewport_texture")


func _ready() -> void:
	_apply_panel_size()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	call_deferred("_bind_viewport_texture")


func _apply_panel_size() -> void:
	if not is_inside_tree():
		return
	var viewport := get_node_or_null("SubViewport") as SubViewport
	if viewport != null:
		viewport.size = panel_pixel_size
	var quad := get_node_or_null("TimelineQuad") as MeshInstance3D
	if quad != null and quad.mesh is QuadMesh:
		var mesh := quad.mesh as QuadMesh
		var aspect := float(panel_pixel_size.y) / float(panel_pixel_size.x)
		mesh.size = Vector2(quad_width, quad_width * aspect)


func _bind_viewport_texture() -> void:
	if not is_inside_tree():
		return
	var viewport := get_node_or_null("SubViewport") as SubViewport
	var quad := get_node_or_null("TimelineQuad") as MeshInstance3D
	if viewport == null or quad == null:
		return
	var mat := quad.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		mat = QUAD_MATERIAL.duplicate() as StandardMaterial3D
		quad.set_surface_override_material(0, mat)
	var vp_texture: Texture2D = viewport.get_texture()
	if mat.albedo_texture != vp_texture:
		mat.albedo_texture = vp_texture
