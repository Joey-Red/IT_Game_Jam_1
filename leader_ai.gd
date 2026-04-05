extends CharacterBody3D

@export_category("Dynamic AI Stats")
@export var base_patrol_speed: float = 2.0
@export var base_chase_speed: float = 3.5
@export var max_chase_speed: float = 6.0
@export var base_vision_range: float = 10.0
@export var vision_angle_degrees: float = 45.0 

@export_category("Patrol Settings")
@export var wander_radius: float = 10.0
@export var initial_wait_time: float = 5.0
@export var idle_wait_range: Vector2 = Vector2(3.0, 6.0)

@export_category("Suspicion Mechanics")
@export var max_suspicion: float = 100.0
@export var suspicion_build_rate: float = 20.0
@export var suspicion_decay_rate: float = 15.0
@export var active_steal_penalty: float = 40.0
@export_category("Audio Settings")
@export var audio_folder: String = "res://assets/" # Change to match your project structure
@onready var voice_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer
var footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL: float = 0.4 # Adjust based on animation/speed


var voice_timer: float = 0.0
const VOICE_INTERVAL: float = 5.0
var _last_state: State = State.PATROL
# State tracking for stealth mechanics
var current_suspicion: float = 0.0
var previous_player_blocks: int = 0
var patrol_speed: float = base_patrol_speed
var chase_speed: float = base_chase_speed
var vision_range: float = base_vision_range
@export var debug_mode: bool = false 

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var vision_ray: RayCast3D = $VisionRay

enum State { IDLE, PATROL, INVESTIGATE, CHASE }
var current_state: State = State.IDLE
var previous_state: State = State.IDLE 

var player: CharacterBody3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var state_timer: float = 0.0
var stuck_timer: float = 0.0
var last_pos: Vector3 = Vector3.ZERO

# Debug Visuals
var debug_laser: MeshInstance3D

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	
	if debug_mode:
		print("[LeaderAI] Ready. Player found: ", player != null)
		setup_debug_laser()
	
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	
	# Start by idling at the spawn point for a bit
	state_timer = initial_wait_time
	change_state(State.IDLE)

func setup_debug_laser() -> void:
	debug_laser = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.05
	cylinder.height = 1.0 
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color.RED
	cylinder.material = mat
	
	debug_laser.mesh = cylinder
	vision_ray.add_child(debug_laser)

func handle_footsteps(delta: float) -> void:
	# Only play footsteps if grounded and moving
	if is_on_floor() and velocity.length() > 0.2:
		footstep_timer -= delta
		if footstep_timer <= 0.0:
			footstep_player.pitch_scale = randf_range(0.9, 1.1)
			footstep_player.play()
			
			# Speed up footsteps if chasing (For leader)
			var current_interval = FOOTSTEP_INTERVAL
			if "chase_speed" in self and velocity.length() > (patrol_speed + 0.5):
				current_interval = FOOTSTEP_INTERVAL * 0.6
				
			footstep_timer = current_interval
	else:
		footstep_timer = 0.0

func _physics_process(delta: float) -> void:
	if not GameManager.is_game_active:
		if not is_on_floor():
			velocity.y -= gravity * delta
			move_and_slide()
		return
	if not is_on_floor():
		velocity.y -= gravity * delta

	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(player):
			move_and_slide() 
			return

	if not GameManager.is_game_active:
		change_state(State.IDLE)

	if is_instance_valid(player) and GameManager.is_game_active:
		handle_suspicion_logic(delta)
		
		# --- MECHANIC: Dynamic Difficulty Scaling ---
		chase_speed = clamp(base_chase_speed + (float(GameManager.score) / 500.0), base_chase_speed, max_chase_speed)
		vision_range = base_vision_range + (float(GameManager.score) / 200.0)

	#if current_state != _last_state:
		#_last_state = current_state
		#play_state_voice(current_state)
		#voice_timer = VOICE_INTERVAL
	#else:
		#voice_timer -= delta
		#if voice_timer <= 0.0:
			#play_state_voice(current_state)
			#voice_timer = VOICE_INTERVAL
	# --- Audio State Management ---
	if current_state != _last_state:
		_last_state = current_state
		play_state_voice(current_state)
		voice_timer = VOICE_INTERVAL
		
		# --- NEW: Tell GameManager if we started or stopped chasing ---
		if current_state == State.CHASE:
			GameManager.set_chase_state(true)
		else:
			# If transitioning back to PATROL or INVESTIGATE, stop chase music
			GameManager.set_chase_state(false)
			
	else:
		voice_timer -= delta
		if voice_timer <= 0.0:
			play_state_voice(current_state)
			voice_timer = VOICE_INTERVAL

	match current_state:
		State.PATROL:
			handle_patrol(delta)
		State.INVESTIGATE:
			move_towards_target(delta)
			if nav_agent.is_navigation_finished():
				current_state = State.PATROL
		State.CHASE:
			move_towards_target(delta)
			check_if_caught_player()
	match current_state:
		State.IDLE:
			handle_idle(delta)
		State.PATROL:
			handle_patrol(delta)
		State.INVESTIGATE:
			handle_investigate(delta)
		State.CHASE:
			nav_agent.target_position = player.global_position 
			move_towards_target(delta)
			check_if_caught_player()

	#move_and_slide()
	handle_footsteps(delta)
	
	# Kids use _on_safe_velocity_computed for actual movement, but handle_footsteps 
	# uses the velocity vector which is tracked accurately in both setups.
	if not "nav_agent" in self or not nav_agent.avoidance_enabled:
		move_and_slide()


func play_state_voice(state: State) -> void:
	# NEW: Abort if audio is already playing to prevent overlap
	if voice_player.is_playing():
		return
		
	# Convert enum integer to string (e.g., 0 -> "patrol")
	var state_name: String = State.keys()[state].to_lower()
	
	# Possible file suffixes
	var suffixes: Array[String] = ["", "2", "3"]
	var chosen_suffix: String = suffixes.pick_random()
	
	var audio_path: String = audio_folder + state_name + chosen_suffix + ".mp3"
	
	if ResourceLoader.exists(audio_path):
		var stream: AudioStream = load(audio_path)
		voice_player.stream = stream
		voice_player.play()
	else:
		push_warning("LeaderAI: Audio file not found at path: " + audio_path)

# --- Suspicion Logic ---
func handle_suspicion_logic(delta: float) -> void:
	var sees_player = check_if_can_see_player()
	var is_stealing_right_now = player.blocks_in_hands > previous_player_blocks
	
	if sees_player:
		if is_stealing_right_now:
			current_suspicion += active_steal_penalty
			if debug_mode: print("[LeaderAI] Caught stealing! Suspicion spiked to: ", current_suspicion)
			
		if player.blocks_in_hands > 0:
			var multiplier = float(player.blocks_in_hands) + (float(GameManager.score) / 500.0)
			current_suspicion += suspicion_build_rate * multiplier * delta
			
			if current_state == State.PATROL or current_state == State.IDLE:
				change_state(State.INVESTIGATE)
		else:
			current_suspicion -= suspicion_decay_rate * delta
	else:
		current_suspicion -= suspicion_decay_rate * delta

	current_suspicion = clamp(current_suspicion, 0.0, max_suspicion)
	
	if current_suspicion >= max_suspicion and current_state != State.CHASE:
		change_state(State.CHASE)
	elif current_suspicion <= 0.0 and current_state == State.INVESTIGATE:
		# Return to the previous wandering logic when suspicion drops
		change_state(State.IDLE)
		state_timer = randf_range(idle_wait_range.x, idle_wait_range.y)

	previous_player_blocks = player.blocks_in_hands

func change_state(new_state: State) -> void:
	if current_state != new_state:
		previous_state = current_state
		current_state = new_state
		if debug_mode:
			var state_names = ["IDLE", "PATROL", "INVESTIGATE", "CHASE"]
			print("[LeaderAI] State changed to: ", state_names[current_state])

# --- Vision Logic ---
func check_if_can_see_player() -> bool:
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player > vision_range: 
		update_debug_laser(Vector3.ZERO, false)
		return false
		
	var dir_to_player = global_position.direction_to(player.global_position)
	var forward_dir = -global_transform.basis.z.normalized()
	var angle_to_player = rad_to_deg(Vector2(forward_dir.x, forward_dir.z).angle_to(Vector2(dir_to_player.x, dir_to_player.z)))
	
	if abs(angle_to_player) < vision_angle_degrees:
		var target_global_pos = player.global_position + Vector3(0, 1.0, 0) 
		var local_target = vision_ray.to_local(target_global_pos)
		
		vision_ray.target_position = local_target
		vision_ray.force_raycast_update() 
		
		var sees = vision_ray.is_colliding() and vision_ray.get_collider().is_in_group("player")
		update_debug_laser(local_target, sees)
		
		if sees:
			if player.is_sneaking and distance_to_player > (vision_range * 0.5):
				return false 
			return true 
	else:
		update_debug_laser(Vector3.ZERO, false)
		
	return false

func update_debug_laser(local_target: Vector3, sees_player: bool) -> void:
	if not debug_mode or not is_instance_valid(debug_laser): return
	
	if local_target == Vector3.ZERO:
		debug_laser.visible = false
		return
		
	debug_laser.visible = true
	var distance = local_target.length()
	
	debug_laser.position = local_target / 2.0
	debug_laser.scale.y = distance
	
	if local_target.normalized() != Vector3.UP and local_target.normalized() != Vector3.DOWN:
		debug_laser.look_at(debug_laser.global_position + vision_ray.to_global(local_target) - vision_ray.global_position, Vector3.UP)
		debug_laser.rotation_degrees.x += 90

	var mat = debug_laser.mesh.surface_get_material(0)
	if mat:
		mat.albedo_color = Color(0, 1, 0, 0.5) if sees_player else Color(1, 0, 0, 0.5)
		mat.emission = Color.GREEN if sees_player else Color.RED

# --- State Behaviours ---
func handle_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, patrol_speed)
	velocity.z = move_toward(velocity.z, 0, patrol_speed)
	
	if GameManager.is_game_active:
		state_timer -= delta
		if state_timer <= 0:
			pick_next_patrol_point()
			change_state(State.PATROL)

func handle_patrol(delta: float) -> void:
	if global_position.distance_to(last_pos) < (patrol_speed * delta * 0.1):
		stuck_timer += delta
	else:
		stuck_timer = 0.0
	last_pos = global_position
	
	# If we arrived at the target, or got stuck on geometry
	if nav_agent.is_navigation_finished() or stuck_timer > 1.0:
		if debug_mode and stuck_timer > 1.0:
			print("[LeaderAI] Stuck! Abandoning path.")
			
		stuck_timer = 0.0
		state_timer = randf_range(idle_wait_range.x, idle_wait_range.y)
		change_state(State.IDLE)
		
	move_towards_target(delta)

func handle_investigate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, patrol_speed)
	velocity.z = move_toward(velocity.z, 0, patrol_speed)
	
	var target_pos = player.global_position
	target_pos.y = global_position.y
	
	var direction = global_position.direction_to(target_pos)
	var target_y_rot = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_y_rot, 5.0 * delta)

func pick_next_patrol_point() -> void:
	# Generate a random offset to wander to
	var random_offset = Vector3(
		randf_range(-wander_radius, wander_radius), 
		0.0, 
		randf_range(-wander_radius, wander_radius)
	)
	var target_pos = global_position + random_offset
	
	# Query the NavigationServer for the closest valid point on the NavMesh
	var map = get_world_3d().navigation_map
	var safe_pos = NavigationServer3D.map_get_closest_point(map, target_pos)
	
	nav_agent.target_position = safe_pos
	
	if debug_mode:
		print("[LeaderAI] Wandering to new random point: ", safe_pos)
		
# --- External Triggers ---
func investigate_crying(_location: Vector3) -> void:
	if current_state != State.CHASE:
		if debug_mode:
			print("[LeaderAI] Heard crying! Cover blown, chasing player!")
		
		# Instantly max out suspicion to bypass the investigate phase
		current_suspicion = max_suspicion
		change_state(State.CHASE)

func move_towards_target(delta: float) -> void:
	var speed = chase_speed if current_state == State.CHASE else patrol_speed
	
	if nav_agent.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	direction.y = 0
	direction = direction.normalized()
	
	var flat_pos = Vector2(global_position.x, global_position.z)
	var flat_target = Vector2(next_path_pos.x, next_path_pos.z)
	var distance = flat_pos.distance_to(flat_target)
	
	if distance > 0.1:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	
	var horizontal_velocity = Vector2(velocity.x, velocity.z)
	if horizontal_velocity.length_squared() > 0.1:
		var target_y_rot = atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, target_y_rot, 10.0 * delta)

func check_if_caught_player() -> void:
	if global_position.distance_to(player.global_position) < 2.8:
		change_state(State.IDLE)
		GameManager.end_game()
		
		var target_pos = player.global_position
		target_pos.y = global_position.y
		look_at(target_pos, Vector3.UP)
		
		velocity = Vector3.ZERO
