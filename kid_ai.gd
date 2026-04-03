extends CharacterBody3D

@export var move_speed: float = 3.0
@export var block_scene: PackedScene 

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

enum State { FINDING_BLOCK, MOVING_TO_BLOCK, MOVING_TO_ZONE, BUILDING, CELEBRATING, UPSET, CRYING }
var current_state: State = State.FINDING_BLOCK

var target_block: RigidBody3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- NEW: Permanent Station & Avoidance Setup ---
var claimed_zone: Node3D = null
var max_tower_size: int = 0
var state_timer: float = 0.0

func _ready() -> void:
	# 1. Activate Godot's built-in Crowd Avoidance
	nav_agent.velocity_computed.connect(_on_safe_velocity_computed)
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 0.6 # The "personal space" bubble around the kid
	
	# 2. Claim a station immediately
	var zones = get_tree().get_nodes_in_group("build_zones")
	if zones.size() > 0:
		claimed_zone = zones.pick_random()

func _physics_process(delta: float) -> void:
	# Calculate desired velocity
	if not is_on_floor():
		velocity.y -= gravity * delta

	match current_state:
		State.FINDING_BLOCK:
			find_nearest_block()
		State.MOVING_TO_BLOCK:
			calculate_movement(delta)
			check_if_block_reached()
		State.MOVING_TO_ZONE:
			calculate_movement(delta)
			check_if_zone_reached()
		State.BUILDING:
			build_tower()
		State.CELEBRATING:
			celebrate_behavior(delta)
			monitor_tower()
		State.UPSET:
			upset_behavior(delta)
		State.CRYING:
			crying_behavior(delta)

	# --- NEW: Send desired velocity to the Avoidance AI instead of moving directly ---
	if nav_agent.avoidance_enabled and (current_state == State.MOVING_TO_BLOCK or current_state == State.MOVING_TO_ZONE or current_state == State.CELEBRATING):
		nav_agent.set_velocity(velocity)
	else:
		_on_safe_velocity_computed(velocity)

# --- NEW: Avoidance Movement Execution ---
func _on_safe_velocity_computed(safe_velocity: Vector3) -> void:
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()

# --- Logic Functions ---
func find_nearest_block() -> void:
	var blocks = get_tree().get_nodes_in_group("BLOCKS")
	if blocks.is_empty():
		check_if_all_blocks_placed()
		return 
		
	var nearest_distance = INF
	target_block = null
	var found_loose_block = false
	
	for block in blocks:
		if is_block_in_build_zone(block):
			continue
			
		found_loose_block = true
		var dist = global_position.distance_to(block.global_position) + randf_range(0.0, 3.0)
		
		if dist < nearest_distance:
			nearest_distance = dist
			target_block = block
			
	if target_block:
		nav_agent.target_position = target_block.global_position
		current_state = State.MOVING_TO_BLOCK
	else:
		if not found_loose_block:
			check_if_all_blocks_placed()
		else:
			velocity.x = 0
			velocity.z = 0

func check_if_all_blocks_placed() -> void:
	if current_state != State.CELEBRATING and current_state != State.CRYING:
		start_celebrating()

func is_block_in_build_zone(block: Node3D) -> bool:
	var zones = get_tree().get_nodes_in_group("build_zones")
	for zone in zones:
		if block.global_position.distance_to(zone.global_position) < 2.5:
			return true
	return false

# --- FIX: Only walk to THEIR claimed zone ---
func find_nearest_zone() -> void:
	if claimed_zone:
		nav_agent.target_position = claimed_zone.global_position
		current_state = State.MOVING_TO_ZONE

func calculate_movement(delta: float) -> void:
	if current_state == State.MOVING_TO_BLOCK:
		if not is_instance_valid(target_block):
			current_state = State.FINDING_BLOCK
			velocity.x = 0
			velocity.z = 0
			return
		else:
			nav_agent.target_position = target_block.global_position

	if nav_agent.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	
	if direction.length() > 0.1:
		var look_dir = Vector2(-velocity.z, -velocity.x).angle()
		rotation.y = lerp_angle(rotation.y, look_dir, 0.1)

func check_if_block_reached() -> void:
	if is_instance_valid(target_block):
		if global_position.distance_to(target_block.global_position) < 1.8:
			var all_blocks = get_tree().get_nodes_in_group("BLOCKS")
			for b in all_blocks:
				if is_instance_valid(b) and b != target_block:
					if target_block.global_position.distance_to(b.global_position) < 1.5:
						b.sleeping = false 
						var random_nudge = Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1))
						b.apply_central_impulse(random_nudge)
			
			target_block.queue_free()
			find_nearest_zone()

func check_if_zone_reached() -> void:
	if claimed_zone:
		if global_position.distance_to(claimed_zone.global_position) < 1.8:
			current_state = State.BUILDING

func build_tower() -> void:
	# FIX: Immediately change state so this only runs ONCE per drop!
	current_state = State.FINDING_BLOCK
	
	if block_scene and claimed_zone:
		var new_block = block_scene.instantiate()
		get_parent().add_child(new_block)
		var random_offset = Vector3(randf_range(-0.2, 0.2), 2.0, randf_range(-0.2, 0.2))
		new_block.global_position = claimed_zone.global_position + random_offset
		
	await get_tree().create_timer(0.5).timeout
	if current_state == State.BUILDING: 
		current_state = State.FINDING_BLOCK

# --- Post-Building Mechanics ---

func start_celebrating() -> void:
	current_state = State.CELEBRATING
	max_tower_size = count_blocks_in_zone(claimed_zone)

func count_blocks_in_zone(zone: Node3D) -> int:
	var count = 0
	if not zone: return 0
	for b in get_tree().get_nodes_in_group("BLOCKS"):
		if is_instance_valid(b):
			if b.global_position.distance_to(zone.global_position) < 2.5:
				count += 1
	return count

# --- FIX: Walk back to their zone and stay there! ---
func celebrate_behavior(delta: float) -> void:
	if claimed_zone and global_position.distance_to(claimed_zone.global_position) > 2.5:
		# Walk back home!
		nav_agent.target_position = claimed_zone.global_position
		calculate_movement(delta)
	else:
		# Arrived home, stop walking and hop
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		if is_on_floor() and randf() < 0.015:
			velocity.y = 3.5

func monitor_tower() -> void:
	if not claimed_zone: return
	var current_size = count_blocks_in_zone(claimed_zone)
	
	if current_size < max_tower_size:
		var blocks_lost = max_tower_size - current_size
		var percent_lost = float(blocks_lost) / float(max_tower_size) if max_tower_size > 0 else 1.0
		
		if percent_lost >= 0.3:
			start_crying()
		else:
			if randf() < 0.5:
				current_state = State.UPSET
				state_timer = 2.0 
			else:
				max_tower_size = current_size 

func upset_behavior(delta: float) -> void:
	state_timer -= delta
	velocity.x = 0
	velocity.z = 0
	rotation.y += 12.0 * delta 
	
	if state_timer <= 0:
		current_state = State.CELEBRATING
		max_tower_size = count_blocks_in_zone(claimed_zone)

func start_crying() -> void:
	current_state = State.CRYING
	velocity.x = 0
	velocity.z = 0
	get_tree().call_group("teacher", "investigate_crying", global_position)

func crying_behavior(delta: float) -> void:
	rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.2
