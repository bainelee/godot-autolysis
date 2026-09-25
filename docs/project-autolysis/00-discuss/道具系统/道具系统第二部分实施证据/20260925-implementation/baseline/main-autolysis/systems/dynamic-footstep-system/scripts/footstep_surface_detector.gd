class_name FootstepSurfaceDetector
extends AudioStreamPlayer3D

signal sound_played(profile: AudioStreamRandomizer, landing: bool)

@export var generic_fallback_footstep_profile: AudioStreamRandomizer
@export var footstep_material_library: FootstepMaterialLibrary
@export var generic_fallback_landing_profile: AudioStreamRandomizer
@export var landing_material_library: FootstepMaterialLibrary
@export_flags_3d_physics var ground_collision_mask: int = 3
@export var ground_probe_length: float = 1.0
@export_group("脚步音量")
@export var walk_volume_db: float = -25.0
@export var sprint_volume_db: float = -20.0
@export var crouch_volume_db: float = -38.0
@export_group("落地音效")
@export var landing_threshold: float = -2.0
@export var max_landing_velocity: float = -8.0
@export var min_landing_velocity: float = -2.0
@export var min_landing_volume_db: float = -40.0
@export var max_landing_volume_db: float = 0.0
@export var min_landing_pitch: float = 0.7
@export var max_landing_pitch: float = 0.8

var _excluded_bodies: Array[RID] = []
var _step_armed: bool = true
@onready var _landing_player: AudioStreamPlayer3D = $LandingPlayer

func _ready() -> void:
	var body := get_parent() as CollisionObject3D
	if body != null:
		_excluded_bodies.append(body.get_rid())
	for child in get_parent().find_children("*", "CollisionObject3D", true, false):
		_excluded_bodies.append(child.get_rid())

# 由角色完成本帧移动后调用；仅接收移动结果，不读取角色私有状态。
func update_motion(grounded: bool, was_grounded: bool, impact_velocity: float,
		horizontal_speed: float, moving: bool, phase: float, crouching: bool,
		sprinting: bool, blocked: bool) -> void:
	if not grounded or blocked:
		_step_armed = true
		return
	if not was_grounded and impact_velocity < landing_threshold:
		play_landing(impact_velocity)
		_step_armed = false
		return
	if not moving or horizontal_speed < 0.2:
		_step_armed = true
		return
	if phase < 0.9:
		_step_armed = true
	elif _step_armed:
		volume_db = crouch_volume_db if crouching else (sprint_volume_db if sprinting else walk_volume_db)
		play_footstep()
		_step_armed = false

func play_footstep() -> void:
	var profile := _ground_profile(footstep_material_library, generic_fallback_footstep_profile)
	if profile == null or profile.streams_count == 0:
		return
	stream = profile
	play()
	sound_played.emit(profile, false)

func play_landing(impact_velocity: float = -2.0) -> void:
	var profile := _ground_profile(landing_material_library, generic_fallback_landing_profile)
	if profile == null or profile.streams_count == 0:
		return
	var span: float = max_landing_velocity - min_landing_velocity
	var intensity: float = clampf((impact_velocity - min_landing_velocity) / span, 0.0, 1.0) if not is_zero_approx(span) else 1.0
	_landing_player.stream = profile
	_landing_player.volume_db = lerpf(min_landing_volume_db, max_landing_volume_db, intensity)
	_landing_player.pitch_scale = lerpf(max_landing_pitch, min_landing_pitch, intensity)
	_landing_player.play()
	sound_played.emit(profile, true)

func _ground_profile(library: FootstepMaterialLibrary, fallback: AudioStreamRandomizer) -> AudioStreamRandomizer:
	var query := PhysicsRayQueryParameters3D.create(global_position,
		global_position + Vector3.DOWN * ground_probe_length, ground_collision_mask, _excluded_bodies)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit["collider"] as Node3D
	for child in collider.find_children("*", "FootstepSurface", true, false):
		if child.footstep_profile != null:
			return child.footstep_profile
	if collider is FootstepSurface and collider.footstep_profile != null:
		return collider.footstep_profile
	if library != null:
		var material := _surface_material(collider, hit["position"])
		if material != null:
			var profile := library.get_footstep_profile_by_material(material)
			if profile != null:
				return profile
	return fallback

func _surface_material(collider: Node3D, hit_position: Vector3) -> Material:
	if collider is CSGShape3D:
		if collider.material_override != null:
			return collider.material_override
		if not collider is CSGCombiner3D:
			return collider.material
	var meshes: Array[Node] = collider.find_children("*", "MeshInstance3D", true, false)
	if collider.get_parent() is MeshInstance3D:
		meshes.push_front(collider.get_parent())
	var nearest: float = INF
	var selected: Material = null
	# 查找射线命中的最近三角面，兼容节点覆盖材质、表面覆盖材质和网格材质。
	for node in meshes:
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in range(instance.mesh.get_surface_count()):
			if instance.mesh is ArrayMesh and instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for offset in range(0, count - 2, 3):
				var a: int = indices[offset] if not indices.is_empty() else offset
				var b: int = indices[offset + 1] if not indices.is_empty() else offset + 1
				var c: int = indices[offset + 2] if not indices.is_empty() else offset + 2
				var intersection: Variant = Geometry3D.ray_intersects_triangle(global_position, Vector3.DOWN,
					instance.to_global(vertices[a]), instance.to_global(vertices[b]), instance.to_global(vertices[c]))
				if intersection != null:
					var distance: float = intersection.distance_squared_to(hit_position)
					if distance < nearest:
						nearest = distance
						selected = instance.get_active_material(surface)
	return selected