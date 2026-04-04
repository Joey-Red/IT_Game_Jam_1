extends CharacterBody3D

@export_category("Dynamic AI Stats")
@export var base_patrol_speed: float = 2.0
@export var base_chase_speed: float = 3.5
@export var max_chase_speed: float = 6.0
@export var base_vision_range: float = 10.0
@export var vision_angle_degrees: float = 45.0 

# State tracking for stealth mechanics
var previous_player_blocks: int = 0
var patrol_speed: float = base_patrol_speed
var chase_speed: float = base_chase_speed
var vision_range: float = base_vision_range
#@export var patrol_speed: float = 2.0
#@export var chase_speed: float = 4.5
#@export var vision_angle_degrees: float = 45.0 
#@export var vision_range: float = 15.0
@export var debug_mode: bool = true # Toggle logging and visuals

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var vision_ray: RayCast3D = $VisionRay

enum State { IDLE, PATROL, INVESTIGATE, CHASE }
var current_state: State = State.PATROL
var previous_state: State = State.IDLE # For logging state changes

var player: CharacterBody3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var patrol_timer: float = 0.0
var stuck_timer: float = 0.0
var last_pos: Vector3 = Vector3.ZERO

# Debug Visuals
var debug_laser: MeshInstance3D

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	
	if debug_mode:
		print("[LeaderAI] Ready. Player found: ", player != null)
		print("[LeaderAI] Game Active status: ", GameManager.is_game_active)
		setup_debug_laser()
	
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	
	call_deferred("pick_next_patrol_point")

func setup_debug_laser() -> void:
	debug_laser = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.05
	cylinder.height = 1.0 # Base height, scaled later
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color.RED
	cylinder.material = mat
	
	debug_laser.mesh = cylinder
	vision_ray.add_child(debug_laser)
	
	# Rotate to point along -Z (forward for RayCast3D usually, depending on your setup)
	# RayCast3D target_position determines the actual direction in code later.

#func _physics_process(delta: float) -> void:
	#if not is_on_floor():
		#velocity.y -= gravity * delta
#
	## FIX 1: Robust Player Fetching. Keep checking if the player is missing.
	#if not is_instance_valid(player):
		#player = get_tree().get_first_node_in_group("player")
		#if not is_instance_valid(player):
			#move_and_slide() # Allow gravity to apply, but don't run AI logic yet
			#return
		#elif debug_mode:
			#print("[LeaderAI] Player successfully found at runtime!")
#
	#if not GameManager.is_game_active:
		#change_state(State.IDLE)
#
	#if current_state != State.IDLE and is_instance_valid(player):
		#if check_if_can_see_player() and current_state != State.CHASE:
			#change_state(State.CHASE)
#
	#match current_state:
		#State.IDLE:
			#velocity.x = move_toward(velocity.x, 0, patrol_speed)
			#velocity.z = move_toward(velocity.z, 0, patrol_speed)
		#State.PATROL:
			#handle_patrol(delta)
		#State.INVESTIGATE:
			#move_towards_target(delta)
			#if nav_agent.is_navigation_finished():
				#change_state(State.PATROL)
		#State.CHASE:
			#nav_agent.target_position = player.global_position 
			#move_towards_target(delta)
			#check_if_caught_player()
#
	#move_and_slide()
	
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Ensure player exists
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(player):
			move_and_slide() 
			return

	if not GameManager.is_game_active:
		change_state(State.IDLE)

	if current_state != State.IDLE and is_instance_valid(player):
		var sees_player = check_if_can_see_player()
		var is_stealing_right_now = player.blocks_in_hands > previous_player_blocks
		
		# --- MECHANIC 1: Caught in the Act ---
		if sees_player and is_stealing_right_now:
			change_state(State.CHASE)
			if debug_mode: print("[LeaderAI] Caught player actively stealing!")
			
		# --- MECHANIC 2: Escalating Suspicion ---
		# If the teacher sees you, and you are carrying blocks, she has a chance to notice.
		if sees_player and current_state != State.CHASE and player.blocks_in_hands > 0:
			# Base 5% chance per second, escalating by 10% for every 500 points
			var notice_chance_per_sec = 0.05 + (float(GameManager.score) / 500.0) * 0.10
			if randf() < (notice_chance_per_sec * delta):
				change_state(State.CHASE)
				if debug_mode: print("[LeaderAI] Teacher noticed the stolen blocks!")

		previous_player_blocks = player.blocks_in_hands

		# --- MECHANIC 3: Dynamic Difficulty Scaling ---
		# The teacher gets faster and sees further as the player scores more points
		chase_speed = clamp(base_chase_speed + (float(GameManager.score) / 500.0), base_chase_speed, max_chase_speed)
		vision_range = base_vision_range + (float(GameManager.score) / 200.0)

	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, patrol_speed)
			velocity.z = move_toward(velocity.z, 0, patrol_speed)
		State.PATROL:
			handle_patrol(delta)
		State.INVESTIGATE:
			move_towards_target(delta)
			if nav_agent.is_navigation_finished():
				change_state(State.PATROL)
		State.CHASE:
			nav_agent.target_position = player.global_position 
			move_towards_target(delta)
			check_if_caught_player()

	move_and_slide()
	
	
	
	
	
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
		
		update_debug_laser(local_target, vision_ray.is_colliding() and vision_ray.get_collider().is_in_group("player"))
		
		if vision_ray.is_colliding():
			var collider = vision_ray.get_collider()
			if collider and collider.is_in_group("player"):
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
	
	# Point laser exactly at the local target position
	debug_laser.position = local_target / 2.0
	debug_laser.scale.y = distance
	
	# Orient laser correctly along the vector
	if local_target.normalized() != Vector3.UP and local_target.normalized() != Vector3.DOWN:
		debug_laser.look_at(debug_laser.global_position + vision_ray.to_global(local_target) - vision_ray.global_position, Vector3.UP)
		debug_laser.rotation_degrees.x += 90 # Cylinder meshes generate upright (Y-axis)

	var mat = debug_laser.mesh.surface_get_material(0)
	if mat:
		mat.albedo_color = Color(0, 1, 0, 0.5) if sees_player else Color(1, 0, 0, 0.5)
		mat.emission = Color.GREEN if sees_player else Color.RED

# --- Patrol Logic ---
func handle_patrol(delta: float) -> void:
	patrol_timer -= delta
	
	if global_position.distance_to(last_pos) < (patrol_speed * delta * 0.1):
		stuck_timer += delta
	else:
		stuck_timer = 0.0
	last_pos = global_position
	
	if nav_agent.is_navigation_finished() or patrol_timer <= 0 or stuck_timer > 1.0:
		if debug_mode and stuck_timer > 1.0:
			print("[LeaderAI] Stuck! Forcing new patrol point.")
		stuck_timer = 0.0
		pick_next_patrol_point()
		
	move_towards_target(delta)

func pick_next_patrol_point() -> void:
	var zones = get_tree().get_nodes_in_group("build_zones")
	if zones.size() > 0:
		var target_zone = zones.pick_random()
		nav_agent.target_position = target_zone.global_position
		patrol_timer = randf_range(5.0, 10.0)
		
		if debug_mode:
			print("[LeaderAI] New patrol target: ", target_zone.name, " | Reachable: ", nav_agent.is_target_reachable())
	elif debug_mode:
		print("[LeaderAI] ERROR: No 'build_zones' found in scene tree!")

func move_towards_target(delta: float) -> void:
	var speed = chase_speed if current_state == State.CHASE else patrol_speed
	
	if nav_agent.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		return

	var next_path_pos = nav_agent.get_next_path_position()
	
	# Isolate the direction to the XZ plane only
	var direction = global_position.direction_to(next_path_pos)
	direction.y = 0
	direction = direction.normalized()
	
	# Calculate flat distance to prevent overshooting jitter
	var flat_pos = Vector2(global_position.x, global_position.z)
	var flat_target = Vector2(next_path_pos.x, next_path_pos.z)
	var distance = flat_pos.distance_to(flat_target)
	
	# Only apply velocity if we aren't microscopically close to the node
	if distance > 0.1:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	
	# Smooth rotation: Only rotate if moving significantly
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
