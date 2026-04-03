extends CharacterBody3D

@export var patrol_speed: float = 2.0
@export var chase_speed: float = 4.5
@export var vision_angle_degrees: float = 45.0 
@export var vision_range: float = 15.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var vision_ray: RayCast3D = $VisionRay

enum State { PATROL, INVESTIGATE, CHASE }
var current_state: State = State.PATROL

var player: CharacterBody3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var patrol_timer: float = 0.0
var stuck_timer: float = 0.0
var last_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	
	# FIX: Wait one frame for the NavMesh to initialize before moving!
	await get_tree().physics_frame
	pick_next_patrol_point()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if is_instance_valid(player) and GameManager.is_game_active:
		if check_if_can_see_player():
			current_state = State.CHASE
			nav_agent.target_position = player.global_position

	match current_state:
		State.PATROL:
			handle_patrol(delta)
		State.INVESTIGATE:
			move_towards_target()
			if nav_agent.is_navigation_finished():
				current_state = State.PATROL
		State.CHASE:
			move_towards_target()
			check_if_caught_player()

	move_and_slide()

# --- Vision Logic ---
func check_if_can_see_player() -> bool:
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player > vision_range: return false
		
	var direction_to_player = global_position.direction_to(player.global_position)
	var forward_direction = -global_transform.basis.z
	var angle_to_player = rad_to_deg(forward_direction.angle_to(direction_to_player))
	
	if angle_to_player < vision_angle_degrees:
		vision_ray.target_position = to_local(player.global_position)
		vision_ray.force_raycast_update() 
		
		if vision_ray.is_colliding():
			var collider = vision_ray.get_collider()
			if collider.is_in_group("player"):
				if player.is_sneaking and distance_to_player > (vision_range * 0.5):
					return false 
				return true 
	return false

# --- Smarter Patrol Logic ---
func handle_patrol(delta: float) -> void:
	patrol_timer -= delta
	
	# Anti-stuck check for the teacher
	if global_position.distance_to(last_pos) < (patrol_speed * delta * 0.1):
		stuck_timer += delta
	else:
		stuck_timer = 0.0
	last_pos = global_position
	
	# If reached destination, timer ran out, or stuck against a wall
	if nav_agent.is_navigation_finished() or patrol_timer <= 0 or stuck_timer > 1.0:
		stuck_timer = 0.0
		pick_next_patrol_point()
		
	move_towards_target()

func pick_next_patrol_point() -> void:
	var zones = get_tree().get_nodes_in_group("build_zones")
	if zones.size() > 0:
		var target_zone = zones.pick_random()
		nav_agent.target_position = target_zone.global_position
		patrol_timer = randf_range(5.0, 10.0) 

func move_towards_target() -> void:
	var speed = chase_speed if current_state == State.CHASE else patrol_speed
	
	if nav_agent.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	
	if direction.length() > 0.1:
		var look_dir = Vector2(-velocity.z, -velocity.x).angle()
		rotation.y = lerp_angle(rotation.y, look_dir, 0.1)

func investigate_crying(location: Vector3) -> void:
	if current_state != State.CHASE:
		current_state = State.INVESTIGATE
		nav_agent.target_position = location

func check_if_caught_player() -> void:
	if global_position.distance_to(player.global_position) < 2.5:
		print("YOU GOT CAUGHT!")
		GameManager.end_game()
		look_at(player.global_position, Vector3.UP)
		rotation.x = 0 
		velocity = Vector3.ZERO
