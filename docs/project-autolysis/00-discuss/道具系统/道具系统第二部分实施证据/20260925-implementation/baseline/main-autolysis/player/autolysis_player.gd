class_name AutolysisPlayer
extends CharacterBody3D

signal mouse_movement(relative_mouse_movement: Vector2)
@export var item_drop_shapecast: ShapeCast3D

@export_group("移动参数")
@export var enable_jump : bool = false
@export var enable_slide : bool = false
@export var JUMP_VELOCITY : float= 4.5
@export var CROUCH_JUMP_VELOCITY : float = 3.0
@export var WALKING_SPEED : float = 5.0
@export var SPRINTING_SPEED : float = 8.0
@export var CROUCHING_SPEED : float = 3.0
@export var CROUCHING_DEPTH : float = -0.9
@export var CAN_CROUCH_JUMP = true
@export var MOUSE_SENS : float = 0.25
@export var LERP_SPEED : float = 10.0
@export var AIR_LERP_SPEED : float = 6.0
@export var FREE_LOOK_TILT_AMOUNT : float = 5.0
@export var SLIDING_SPEED : float = 5.0
@export var SLIDE_JUMP_MOD : float = 1.5
@export var disable_roll_anim : bool = false
@export var CAN_BUNNYHOP : bool = true
@export var BUNNY_HOP_ACCELERATION : float = 0.1
@export var INVERT_Y_AXIS : bool = true
@export var TOGGLE_CROUCH : bool = false
@export var PLAYER_PUSH_FORCE : float = 1.3
@export var fall_stun_light_velocity : float = -5.0
@export var fall_stun_heavy_velocity : float = -7.5
@export var fall_stun_light_duration : float = 1.0
@export var fall_stun_heavy_duration : float = 1.5
@export var fall_stun_light_pitch_deg : float = -35.0
@export var fall_stun_heavy_pitch_deg : float = -75.0

@export_group("镜头摆动")
@export_enum("轻微:0", "中等:1", "完整:2") var HEADBOBBLE : int
@export var WIGGLE_ON_WALKING_INTENSITY : float = 0.03
@export var WIGGLE_ON_WALKING_SPEED : float = 12.0
@export var WIGGLE_ON_SPRINTING_INTENSITY : float = 0.05
@export var WIGGLE_ON_SPRINTING_SPEED : float = 16.0
@export var WIGGLE_ON_CROUCHING_INTENSITY : float = 0.08
@export var WIGGLE_ON_CROUCHING_SPEED : float = 8.0

@export_group("台阶处理")
@export var step_height_camera_lerp : float = 2.5
@export var STEP_HEIGHT_DEFAULT : Vector3 = Vector3(0, 0.5, 0)
@export var STEP_MAX_SLOPE_DEGREE : float = 0.0

@export_group("梯子移动")
var on_ladder : bool = false
@export var CAN_SPRINT_ON_LADDER : bool = false
@export var LADDER_SPEED : float = 2.0
@export var LADDER_SPRINT_SPEED : float = 3.3
@export var LADDER_COOLDOWN : float = 0.5
const LADDER_JUMP_SCALE : float = 0.5
var ladder_on_cooldown : bool = false

@export_group("手柄操作")
@export var JOY_DEADZONE : float = 0.25
@export var JOY_V_SENS : float = 2
@export var JOY_H_SENS : float = 2


const WALL_MARGIN: float = 0.001
const STEP_DOWN_MARGIN: float = 0.01
const STEP_CHECK_COUNT: int = 2
const SPEED_CLAMP_AFTER_JUMP_COEFFICIENT: float = 0.3
@onready var STEP_HEIGHT_IN_AIR_DEFAULT: Vector3 = STEP_HEIGHT_DEFAULT
var is_enabled_stair_stepping_in_air: bool = true
var gravity_vec: Vector3 = Vector3.ZERO
var head_offset: Vector3 = Vector3.ZERO
var is_jumping: bool = false
var is_in_air: bool = false
var joystick_h_event: InputEventJoypadMotion
var joystick_v_event: InputEventJoypadMotion
var current_speed: float = 2.5
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var gravity_vector: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector")
var main_velocity: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO
var is_walking: bool = false
var is_sprinting: bool = false
var is_crouching: bool = false
var is_free_looking: bool = false
var try_crouch: bool = false
var slide_vector: Vector2 = Vector2.ZERO
var wiggle_vector: Vector2 = Vector2.ZERO
var wiggle_index: float = 0.0
var wiggle_current_intensity: float = 0.0
@onready var bunny_hop_speed: float = SPRINTING_SPEED
var last_velocity: Vector3 = Vector3.ZERO
var is_landing_stunned: bool = false
var stun_time_total: float = 0.0
var stun_time_left: float = 0.0
var stun_pitch_target: float = 0.0
var fall_stun_head_duck: bool = false
var is_movement_paused: bool = false
var is_showing_ui: bool = false
var jumped_from_slide: bool = false
var was_in_air: bool = false
@export var landing_threshold: float = -2.0
@export var stand_still_speed_threshold: float = 0.2
@onready var footstep_player: FootstepSurfaceDetector = $FootstepPlayer
@onready var body: Node3D = $Body
@onready var neck: Node3D = $Body/Neck
@onready var head: Node3D = $Body/Neck/Head
@onready var eyes: Node3D = $Body/Neck/Head/Eyes
@onready var camera: Camera3D = $Body/Neck/Head/Eyes/Camera
@onready var animationPlayer: AnimationPlayer = $Body/Neck/Head/Eyes/AnimationPlayer
@onready var standing_collision_shape: CollisionShape3D = $StandingCollisionShape
@onready var crouching_collision_shape: CollisionShape3D = $CrouchingCollisionShape
@onready var crouch_raycast: RayCast3D = $CrouchRayCast
@onready var sliding_timer: Timer = $SlidingTimer
@onready var jump_timer: Timer = $JumpCooldownTimer
@onready var _found_area: StaticBody3D = $DegaussPlayerFoundArea
@onready var _found_collision_standing: CollisionShape3D = $DegaussPlayerFoundArea/found_collision_standing
@onready var _found_collision_walking: CollisionShape3D = $DegaussPlayerFoundArea/found_collision_walking
@onready var _found_collision_crouching: CollisionShape3D = $DegaussPlayerFoundArea/found_collision_crouching
@onready var _found_collision_running: CollisionShape3D = $DegaussPlayerFoundArea/found_collision_running
var _active_found_shape: StringName = &""

@onready var interaction_raycast: InteractionRayCast = $Body/Neck/Head/Eyes/Camera/InteractionRaycast
@onready var interaction_controller: AutolysisInteractionController = $InteractionController
@onready var interaction_crosshair: AutolysisCrosshair = $InteractionHUD/Crosshair
@onready var wieldables: Node3D = %Wieldables
@onready var inventory_controller: AutolysisInventoryController = $InventoryController
@onready var held_item_presenter: AutolysisHeldItemPresenter = %HeldItemPresenter
@onready var inventory_bar: AutolysisInventoryBar = $InventoryBar
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.make_current()
	_apply_found_shape(&"found_collision_standing")
	crouch_raycast.add_exception(_found_area)
	$StaircheckRayCast3D.add_exception(_found_area)
	_found_area.add_to_group("Player")
	interaction_raycast.add_exception_rid(get_rid())
	interaction_raycast.add_exception_rid(_found_area.get_rid())
	item_drop_shapecast.add_exception_rid(get_rid())
	item_drop_shapecast.add_exception_rid(_found_area.get_rid())
	interaction_controller.direct_availability_changed.connect(interaction_crosshair.set_direct_available)
	interaction_controller.configure(self, interaction_raycast, is_interaction_input_allowed)
	inventory_controller.configure(held_item_presenter, is_interaction_input_allowed)
	inventory_bar.configure(inventory_controller)
	inventory_controller.inventory_changed.connect(interaction_controller.refresh_state)

func is_interaction_input_allowed() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and not get_tree().paused and not is_movement_paused and not is_showing_ui and not is_landing_stunned and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		is_movement_paused = not is_movement_paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_movement_paused else Input.MOUSE_MODE_CAPTURED
	if is_movement_paused or is_landing_stunned:
		return
	if event is InputEventMouseMotion:
		var look_movement: Vector2 = Vector2.ZERO
		if is_free_looking:
			neck.rotate_y(deg_to_rad(-event.relative.x * MOUSE_SENS))
			neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120), deg_to_rad(120))
		else:
			body.rotate_y(deg_to_rad(-event.relative.x * MOUSE_SENS))
			look_movement.x = -event.relative.x
		var vertical_sign: float = 1.0 if INVERT_Y_AXIS else -1.0
		look_movement.y = -event.relative.y if INVERT_Y_AXIS else event.relative.y
		head.rotate_x(deg_to_rad(event.relative.y * MOUSE_SENS * vertical_sign))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))
		mouse_movement.emit(look_movement)
	if event is InputEventJoypadMotion:
		if event.axis == 2:
			joystick_v_event = event
		if event.axis == 3:
			joystick_h_event = event

func ladder_buffer_finished():
	ladder_on_cooldown = false


func enter_ladder(ladder: CollisionShape3D, ladderDir: Vector3):
	var look_vector = camera.get_camera_transform().basis
	var looking_away = look_vector.z.dot(ladderDir) < 0.33
	var looking_down = look_vector.z.dot(Vector3.UP) > 0.5
	if looking_down or not looking_away:
		var offset = (global_position - ladder.global_position)
		if offset.dot(ladderDir) < -0.1:
			global_translate(ladderDir*offset.length()/4.0)
		var ladder_timer = get_tree().create_timer(LADDER_COOLDOWN)
		ladder_timer.timeout.connect(ladder_buffer_finished)
		ladder_on_cooldown = true
		on_ladder = true
		return
func _process_on_ladder(_delta):
	var input_dir
	if !is_movement_paused:
		input_dir = Input.get_vector("left", "right", "forward", "back")
	else:
		input_dir = Vector2.ZERO
	
	var ladder_speed = LADDER_SPEED
	
	if CAN_SPRINT_ON_LADDER and Input.is_action_pressed("sprint") and input_dir.length_squared() > 0.1:
		is_sprinting = true
		ladder_speed = LADDER_SPRINT_SPEED
	else:
		is_sprinting = false
		
	var jump = enable_jump and Input.is_action_pressed("jump")
	if joystick_h_event:
			if abs(joystick_h_event.get_axis_value()) > JOY_DEADZONE:
				if INVERT_Y_AXIS:
					head.rotate_x(deg_to_rad(joystick_h_event.get_axis_value() * JOY_H_SENS))
				else:
					head.rotate_x(-deg_to_rad(joystick_h_event.get_axis_value() * JOY_H_SENS))
				head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))
				
	if joystick_v_event:
		if abs(joystick_v_event.get_axis_value()) > JOY_DEADZONE:
			neck.rotate_y(deg_to_rad(-joystick_v_event.get_axis_value() * JOY_V_SENS))
			neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120), deg_to_rad(120))

	var look_vector = camera.get_camera_transform().basis
	var looking_down = look_vector.z.dot(Vector3.UP) > 0.5
	var y_dir = 1 if looking_down else -1
	direction = (body.global_transform.basis * Vector3(input_dir.x,input_dir.y * y_dir,0)).normalized()
	main_velocity = direction * ladder_speed
	
	if jump and enable_jump:
		main_velocity += look_vector * Vector3(JUMP_VELOCITY * LADDER_JUMP_SCALE, JUMP_VELOCITY * LADDER_JUMP_SCALE, JUMP_VELOCITY * LADDER_JUMP_SCALE)
	
	velocity = main_velocity
	move_and_slide()
	if is_on_floor() and not ladder_on_cooldown:
		on_ladder = false


func _physics_process(delta: float) -> void:
	var grounded_before_move: bool = is_on_floor()
	last_velocity = main_velocity
	if is_on_floor():
		if was_in_air and last_velocity.y < landing_threshold:
			if last_velocity.y <= fall_stun_heavy_velocity:
				_start_fall_stun(fall_stun_heavy_duration, fall_stun_heavy_pitch_deg, true)
			elif last_velocity.y <= fall_stun_light_velocity:
				_start_fall_stun(fall_stun_light_duration, fall_stun_light_pitch_deg, false)
		was_in_air = false
	else:
		was_in_air = true
	
	if on_ladder:
		_process_on_ladder(delta)
		return
	var input_dir
	if !is_movement_paused and !is_landing_stunned:
		input_dir = Input.get_vector("left", "right", "forward", "back")
	else:
		input_dir = Vector2.ZERO
	if joystick_h_event and !is_movement_paused and !is_landing_stunned:
			if abs(joystick_h_event.get_axis_value()) > JOY_DEADZONE:
				if INVERT_Y_AXIS:
					head.rotate_x(deg_to_rad(joystick_h_event.get_axis_value() * JOY_H_SENS))
				else:
					head.rotate_x(-deg_to_rad(joystick_h_event.get_axis_value() * JOY_H_SENS))
				head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))
				
	if joystick_v_event and !is_movement_paused and !is_landing_stunned:
		if abs(joystick_v_event.get_axis_value()) > JOY_DEADZONE:
			neck.rotate_y(deg_to_rad(-joystick_v_event.get_axis_value() * JOY_V_SENS))
			neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120), deg_to_rad(120))
	
	var crouched_jump = false
	if is_on_floor():
		jumped_from_slide = false
	else:
		crouched_jump = is_crouching and not jumped_from_slide
	if !is_movement_paused and !is_landing_stunned:
		if TOGGLE_CROUCH and Input.is_action_just_pressed("crouch"):
			try_crouch = !try_crouch
		elif !TOGGLE_CROUCH:
			try_crouch = Input.is_action_pressed("crouch")
	
	
	if crouched_jump or (not jumped_from_slide and is_on_floor() and try_crouch or crouch_raycast.is_colliding()):
		if enable_slide and is_sprinting and input_dir != Vector2.ZERO and is_on_floor():
			sliding_timer.start()
			slide_vector = input_dir
		elif !Input.is_action_pressed("sprint"):
			sliding_timer.stop()
		if not jumped_from_slide and sliding_timer.is_stopped():
			current_speed = lerp(current_speed, CROUCHING_SPEED, delta * LERP_SPEED)
		
		head.position.y = lerp(head.position.y, CROUCHING_DEPTH, delta * LERP_SPEED)
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = false
		wiggle_current_intensity = WIGGLE_ON_CROUCHING_INTENSITY
		wiggle_index += WIGGLE_ON_CROUCHING_SPEED * delta
		is_walking = false
		is_sprinting = false
		is_crouching = true
	else:
		if !is_showing_ui or !is_movement_paused:
			head.position.y = lerp(head.position.y, 0.0, delta * LERP_SPEED)
			if head.position.y < CROUCHING_DEPTH/4:
				crouching_collision_shape.disabled = false
				standing_collision_shape.disabled = true
			else:
				standing_collision_shape.disabled = false
				crouching_collision_shape.disabled = true
			sliding_timer.stop()
		if !is_movement_paused and !is_landing_stunned and Input.is_action_pressed("sprint"):	
			if !Input.is_action_pressed("jump") and CAN_BUNNYHOP:
				bunny_hop_speed = SPRINTING_SPEED
				current_speed = lerp(current_speed, bunny_hop_speed, delta * LERP_SPEED)
			elif !Input.is_action_pressed("jump") and !CAN_BUNNYHOP:
				current_speed = lerp(current_speed, SPRINTING_SPEED, delta * LERP_SPEED)
			wiggle_current_intensity = WIGGLE_ON_SPRINTING_INTENSITY * HEADBOBBLE
			wiggle_index += WIGGLE_ON_SPRINTING_SPEED * delta
			is_walking = false
			is_sprinting = true
			if is_crouching:
				is_crouching = false
				try_crouch = false
		else:
			if !is_showing_ui or !is_movement_paused:
				current_speed = lerp(current_speed, WALKING_SPEED, delta * LERP_SPEED)
				wiggle_current_intensity = WIGGLE_ON_WALKING_INTENSITY * HEADBOBBLE
				wiggle_index += WIGGLE_ON_WALKING_SPEED * delta
				is_walking = true
				is_sprinting = false
				if is_crouching:
					is_crouching = false
					try_crouch = false

	if Input.is_action_pressed("free_look") or !sliding_timer.is_stopped() and !is_movement_paused:
		is_free_looking = true
		if sliding_timer.is_stopped():
			eyes.rotation.z = -deg_to_rad(
				neck.rotation.y * FREE_LOOK_TILT_AMOUNT
			)
		else:
			eyes.rotation.z = lerp(
				eyes.rotation.z,
				deg_to_rad(4.0), 
				delta * LERP_SPEED
			)
	else:
		is_free_looking = false
		body.rotation.y += neck.rotation.y
		neck.rotation.y = 0
		eyes.rotation.z = lerp(
			eyes.rotation.z,
			0.0,
			delta*LERP_SPEED
		)
	if is_on_floor():
		is_jumping = false
		is_in_air = false
		main_velocity.y = 0
		gravity_vec = Vector3.ZERO
	else:
		is_in_air = true
		gravity_vec = gravity_vector * gravity * delta
	
	
	if not is_on_floor():
		pass
	elif sliding_timer.is_stopped() and input_dir != Vector2.ZERO:
		wiggle_vector.y = sin(wiggle_index)
		wiggle_vector.x = sin(wiggle_index / 2) + 0.5
		eyes.position.y = lerp(
			eyes.position.y,
			wiggle_vector.y * (wiggle_current_intensity / 2.0), 
			delta * LERP_SPEED
		)
		eyes.position.x = lerp(
			eyes.position.x,
			wiggle_vector.x * wiggle_current_intensity, 
			delta * LERP_SPEED
		)
	else:
		if !is_movement_paused or !is_showing_ui:
			eyes.position.y = lerp(eyes.position.y, 0.0, delta * LERP_SPEED)
			eyes.position.x = lerp(eyes.position.x, 0.0, delta * LERP_SPEED)
		
	if enable_jump and Input.is_action_pressed("jump") and !is_movement_paused and is_on_floor() and jump_timer.is_stopped():
		jump_timer.start()
		is_jumping = true
		is_in_air = false
		var crouch_jump = not is_crouching or CAN_CROUCH_JUMP
		
		var jump_vel = CROUCH_JUMP_VELOCITY if is_crouching else JUMP_VELOCITY
		
		if crouch_jump:
			animationPlayer.play("jump")
			if !sliding_timer.is_stopped():
				main_velocity.y = JUMP_VELOCITY * SLIDE_JUMP_MOD
				jumped_from_slide = true
				sliding_timer.stop()
			else:
				main_velocity.y = jump_vel
			
			if platform_on_leave != PLATFORM_ON_LEAVE_DO_NOTHING:
				var platform_velocity = get_platform_velocity()
				if PLATFORM_ON_LEAVE_ADD_UPWARD_VELOCITY:
					platform_velocity.x = 0
					platform_velocity.z = 0
				main_velocity += platform_velocity
			
			if is_sprinting and CAN_BUNNYHOP:
				bunny_hop_speed += BUNNY_HOP_ACCELERATION
			
			if is_crouching:
				standing_collision_shape.disabled = false
				crouching_collision_shape.disabled = true
	if sliding_timer.is_stopped():
		if is_on_floor():
			direction = lerp(
				direction,
				(body.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(),
				delta * LERP_SPEED
			)
		elif input_dir != Vector2.ZERO:
			direction = lerp(
				direction,
				(body.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(),
				delta * AIR_LERP_SPEED
			)
	else:
		direction = (body.global_transform.basis * Vector3(slide_vector.x, 0.0, slide_vector.y)).normalized()
		current_speed = (sliding_timer.time_left / sliding_timer.wait_time + 0.5) * SLIDING_SPEED
	
	current_speed = clamp(current_speed, 0.5, 12.0)
	
	if direction:
		main_velocity.x = direction.x * current_speed
		main_velocity.z = direction.z * current_speed
	else:
		main_velocity.x = move_toward(main_velocity.x, 0, current_speed)
		main_velocity.z = move_toward(main_velocity.z, 0, current_speed)
	
	last_velocity = main_velocity
	var step_result : StepResult = StepResult.new()
	
	var is_step : bool = step_check(delta, is_jumping, step_result)
	
	if is_step:
		var is_enabled_stair_stepping: bool = true
		if step_result.is_step_up and is_in_air and not is_enabled_stair_stepping_in_air:
			is_enabled_stair_stepping = false

		if is_enabled_stair_stepping:
			global_transform.origin += step_result.diff_position
			head_offset = step_result.diff_position
			head.position -= head_offset
			head.position.y = lerp(head.position.y, 0.0, delta * step_height_camera_lerp)
	else:
		head_offset = head_offset.lerp(Vector3.ZERO, delta * LERP_SPEED)
		head.position.y = lerp(head.position.y, 0.0, delta * step_height_camera_lerp)
	
	main_velocity += gravity_vec

	var impact_velocity: float = main_velocity.y
	velocity = main_velocity
	move_and_slide()
	var horizontal_speed: float = (get_real_velocity() * Vector3(1, 0, 1)).length()
	footstep_player.update_motion(is_on_floor(), grounded_before_move, impact_velocity,
		horizontal_speed, input_dir != Vector2.ZERO, sin(wiggle_index), is_crouching,
		is_sprinting, is_movement_paused or is_landing_stunned or not sliding_timer.is_stopped())

	if is_step and step_result.is_step_up and is_enabled_stair_stepping_in_air:
		if is_in_air or direction.dot(step_result.normal) > 0:
			main_velocity *= SPEED_CLAMP_AFTER_JUMP_COEFFICIENT
			gravity_vec *= SPEED_CLAMP_AFTER_JUMP_COEFFICIENT

	if is_jumping:
		is_jumping = false
		is_in_air = true
	for col_idx in get_slide_collision_count():
		var col := get_slide_collision(col_idx)
		if col.get_collider() is RigidBody3D:
			col.get_collider().apply_central_impulse(-col.get_normal() * PLAYER_PUSH_FORCE)

	_process_landing_stun(delta)

	var next_found_shape: StringName = _pick_found_shape_name()
	if next_found_shape != _active_found_shape:
		_apply_found_shape(next_found_shape)



func _get_horizontal_speed() -> float:
	return (velocity * Vector3(1.0, 0.0, 1.0)).length()


func _pick_found_shape_name() -> StringName:
	if is_crouching:
		return &"found_collision_crouching"
	if is_sprinting:
		return &"found_collision_running"
	if _get_horizontal_speed() < stand_still_speed_threshold:
		return &"found_collision_standing"
	return &"found_collision_walking"


func _apply_found_shape(shape_name: StringName) -> void:
	_found_collision_standing.disabled = shape_name != &"found_collision_standing"
	_found_collision_walking.disabled = shape_name != &"found_collision_walking"
	_found_collision_crouching.disabled = shape_name != &"found_collision_crouching"
	_found_collision_running.disabled = shape_name != &"found_collision_running"
	_active_found_shape = shape_name


func step_check(delta: float, is_jumping_: bool, step_result: StepResult):
	var is_step: bool = false
	
	var step_height_main: Vector3 = STEP_HEIGHT_DEFAULT
	var step_incremental_check_height: Vector3 = STEP_HEIGHT_DEFAULT / STEP_CHECK_COUNT
	
	if is_in_air and is_enabled_stair_stepping_in_air:
		step_height_main = STEP_HEIGHT_IN_AIR_DEFAULT
		step_incremental_check_height = STEP_HEIGHT_IN_AIR_DEFAULT / STEP_CHECK_COUNT
		
	if main_velocity.y >= 0:
		for i in range(STEP_CHECK_COUNT):
			var test_motion_result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
			
			var step_height: Vector3 = step_height_main - i * step_incremental_check_height
			var transform3d: Transform3D = global_transform
			var motion: Vector3 = step_height
			var test_motion_params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
			test_motion_params.from = transform3d
			test_motion_params.motion = motion
			
			var is_player_collided: bool = PhysicsServer3D.body_test_motion(self.get_rid(), test_motion_params, test_motion_result)

			if is_player_collided and test_motion_result.get_collision_normal().y < 0:
				continue

			transform3d.origin += step_height
			motion = main_velocity * delta
			test_motion_params.from = transform3d
			test_motion_params.motion = motion
			
			is_player_collided = PhysicsServer3D.body_test_motion(self.get_rid(), test_motion_params, test_motion_result)
			
			if not is_player_collided:
				transform3d.origin += motion
				motion = -step_height
				test_motion_params.from = transform3d
				test_motion_params.motion = motion
				
				is_player_collided = PhysicsServer3D.body_test_motion(self.get_rid(), test_motion_params, test_motion_result)
				
				if is_player_collided:
					if test_motion_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(STEP_MAX_SLOPE_DEGREE):
						is_step = true
						step_result.is_step_up = true
						step_result.diff_position.y = -test_motion_result.get_remainder().y
						step_result.normal = test_motion_result.get_collision_normal()
						break
			else:
				var wall_collision_normal: Vector3 = test_motion_result.get_collision_normal()
				transform3d.origin += wall_collision_normal * WALL_MARGIN
				motion = (main_velocity * delta).slide(wall_collision_normal)
				test_motion_params.from = transform3d
				test_motion_params.motion = motion
				
				is_player_collided = PhysicsServer3D.body_test_motion(self.get_rid(), test_motion_params, test_motion_result)
				
				if not is_player_collided:
					transform3d.origin += motion
					motion = -step_height
					test_motion_params.from = transform3d
					test_motion_params.motion = motion
					
					is_player_collided = PhysicsServer3D.body_test_motion(self.get_rid(), test_motion_params, test_motion_result)
					
					if is_player_collided:
						if test_motion_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(STEP_MAX_SLOPE_DEGREE):
							is_step = true
							step_result.is_step_up = true
							step_result.diff_position.y = -test_motion_result.get_remainder().y
							step_result.normal = test_motion_result.get_collision_normal()
							break

	if not is_jumping_ and not is_step and is_on_floor():
		step_result.is_step_up = false
		var test_motion_result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
		var transform3d: Transform3D = global_transform
		var motion: Vector3 = main_velocity * delta
		var test_motion_params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
		test_motion_params.from = transform3d
		test_motion_params.motion = motion
		test_motion_params.recovery_as_collision = true

		var is_player_collided: bool = PhysicsServer3D.body_test_motion(self.get_rid(), test_motion_params, test_motion_result)
			
		if not is_player_collided:
			transform3d.origin += motion
			motion = -step_height_main
			test_motion_params.from = transform3d
			test_motion_params.motion = motion
			
			is_player_collided = PhysicsServer3D.body_test_motion(self.get_rid(), test_motion_params, test_motion_result)
			
			if is_player_collided and test_motion_result.get_travel().y < -STEP_DOWN_MARGIN:
				if test_motion_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(STEP_MAX_SLOPE_DEGREE):
					is_step = true
					step_result.diff_position.y = test_motion_result.get_travel().y
					step_result.normal = test_motion_result.get_collision_normal()
		elif is_zero_approx(test_motion_result.get_collision_normal().y):
			var wall_collision_normal: Vector3 = test_motion_result.get_collision_normal()
			transform3d.origin += wall_collision_normal * WALL_MARGIN
			motion = (main_velocity * delta).slide(wall_collision_normal)
			test_motion_params.from = transform3d
			test_motion_params.motion = motion
			
			is_player_collided = PhysicsServer3D.body_test_motion(self.get_rid(), test_motion_params, test_motion_result)
			
			if not is_player_collided:
				transform3d.origin += motion
				motion = -step_height_main
				test_motion_params.from = transform3d
				test_motion_params.motion = motion
				
				is_player_collided = PhysicsServer3D.body_test_motion(self.get_rid(), test_motion_params, test_motion_result)
				
				if is_player_collided and test_motion_result.get_travel().y < -STEP_DOWN_MARGIN:
					if test_motion_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(STEP_MAX_SLOPE_DEGREE):
						is_step = true
						step_result.diff_position.y = test_motion_result.get_travel().y
						step_result.normal = test_motion_result.get_collision_normal()

	return is_step
	
	
func _on_sliding_timer_timeout():
	is_free_looking = false


func _on_animation_player_animation_finished(_anim_name):
	pass


func _start_fall_stun(duration: float, pitch_deg: float, head_duck: bool) -> void:
	is_landing_stunned = true
	stun_time_total = duration
	stun_time_left = duration
	stun_pitch_target = deg_to_rad(pitch_deg)
	fall_stun_head_duck = head_duck
	animationPlayer.stop()
	camera.rotation = Vector3.ZERO
	head.rotation.x = 0.0
	eyes.rotation = Vector3.ZERO
	if head_duck:
		standing_collision_shape.disabled = false
		crouching_collision_shape.disabled = true


func _process_landing_stun(delta: float) -> void:
	if not is_landing_stunned:
		return
	
	stun_time_left -= delta
	var progress : float = 1.0
	if stun_time_total > 0.0:
		progress = clamp(1.0 - stun_time_left / stun_time_total, 0.0, 1.0)
	var pitch: float
	if progress < 0.5:
		pitch = stun_pitch_target * (progress / 0.5)
	else:
		pitch = stun_pitch_target * (1.0 - (progress - 0.5) / 0.5)
	camera.rotation.x = pitch
	
	if fall_stun_head_duck:
		head.position.y = lerp(head.position.y, CROUCHING_DEPTH, delta * LERP_SPEED)
	elif stun_time_left <= 0.0:
		head.position.y = lerp(head.position.y, 0.0, delta * LERP_SPEED)
	if stun_time_left <= 0.0:
		_clear_landing_stun()
func _clear_landing_stun() -> void:
	is_landing_stunned = false
	stun_time_left = 0.0
	stun_time_total = 0.0
	fall_stun_head_duck = false
	camera.rotation = Vector3.ZERO
	head.rotation.x = 0.0
	eyes.rotation = Vector3.ZERO



class StepResult:
	var diff_position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.ZERO
	var is_step_up: bool = false
