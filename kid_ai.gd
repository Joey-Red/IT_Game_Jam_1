extends CharacterBody3D
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer
var footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL: float = 0.4 # Adjust based on animation/speed
@export var move_speed: float = 3.0
@export var block_scene: PackedScene 

@export_category("Building Logic")
enum BuildStyle { TOWER, PYRAMID, WALL }
@export var build_style: BuildStyle = BuildStyle.TOWER
@export var block_size: float = 1.0 # Adjust this to match your actual block mesh size (e.g., 0.5 or 1.0)
@export_category("Audio Settings")
@export var audio_folder: String = "res://assets/" # Change to match your project structure
@onready var voice_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
# Defines local positional offsets for blocks based on their placement order.
# Assuming the block's origin is at its center, Y offsets start at 0.5.
var blueprints: Dictionary = {
	BuildStyle.TOWER: [
		Vector3(0, 0.5, 0),     # 1st block (Bottom)
		Vector3(0, 1.5, 0),     # 2nd block
		Vector3(0, 2.5, 0),     # 3rd block
		Vector3(0, 3.5, 0),     # 4th block
		Vector3(0, 4.5, 0)      # 5th block (Top)
	],
	BuildStyle.PYRAMID: [
		Vector3(-1.05, 0.5, 0), # Base Left (Slightly spread to avoid collision jitter)
		Vector3(0, 0.5, 0),     # Base Center
		Vector3(1.05, 0.5, 0),  # Base Right
		Vector3(-0.525, 1.5, 0),# Mid Left
		Vector3(0.525, 1.5, 0), # Mid Right
		Vector3(0, 2.5, 0)      # Top
	],
	BuildStyle.WALL: [
		Vector3(-1.05, 0.5, 0), Vector3(0, 0.5, 0), Vector3(1.05, 0.5, 0), # Bottom Row
		Vector3(-1.05, 1.5, 0), Vector3(0, 1.5, 0), Vector3(1.05, 1.5, 0)  # Top Row
	]
}

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
	nav_agent.radius = 0.6 
	
	# 2. Wait for the KidManager to finish assigning styles
	await get_tree().process_frame
	await get_tree().process_frame
	
	# --- NEW: Wait in a loop until the player actually hits PLAY ---
	while not GameManager.is_game_active:
		await get_tree().process_frame
	
	# 3. Wait a random amount of time and announce
	var random_delay: float = randf_range(1.0, 3.0)
	await get_tree().create_timer(random_delay).timeout
	announce_build()

func handle_footsteps(delta: float) -> void:
	# Only play footsteps if grounded and moving
	if is_on_floor() and velocity.length() > 0.2:
		footstep_timer -= delta
		if footstep_timer <= 0.0:
			footstep_player.pitch_scale = randf_range(0.9, 1.1)
			footstep_player.play()
			
			# Speed up footsteps if chasing (For leader)
			var current_interval = FOOTSTEP_INTERVAL
			#if "chase_speed" in self and velocity.length() > (patrol_speed + 0.5):
			#	current_interval = FOOTSTEP_INTERVAL * 0.6
				
			footstep_timer = current_interval
	else:
		footstep_timer = 0.0

func _physics_process(delta: float) -> void:
	if not GameManager.is_game_active:
		if not is_on_floor():
			velocity.y -= gravity * delta
			move_and_slide()
		return
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
	handle_footsteps(delta)
	
	# Kids use _on_safe_velocity_computed for actual movement, but handle_footsteps 
	# uses the velocity vector which is tracked accurately in both setups.
	#if not "nav_agent" in self or not nav_agent.avoidance_enabled:
		#move_and_slide()
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
	var block_pos_2d = Vector2(block.global_position.x, block.global_position.z)
	
	for zone in zones:
		var zone_pos_2d = Vector2(zone.global_position.x, zone.global_position.z)
		# 2D distance check ignores how high the tower gets
		if block_pos_2d.distance_to(zone_pos_2d) < 2.5:
			return true
	return false

# --- FIX: Only walk to THEIR claimed zone ---
func find_nearest_zone() -> void:
	if claimed_zone:
		nav_agent.target_position = claimed_zone.global_position
		current_state = State.MOVING_TO_ZONE

func calculate_movement(_delta: float) -> void:
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
		# Increased stopping distance from 1.8 to 2.2
		if global_position.distance_to(claimed_zone.global_position) < 2.2:
			current_state = State.BUILDING

#func build_tower() -> void:
	## FIX: Immediately change state so this only runs ONCE per drop!
	#current_state = State.FINDING_BLOCK
	#
	#if block_scene and claimed_zone:
		#var new_block = block_scene.instantiate()
		#get_parent().add_child(new_block)
		#var random_offset = Vector3(randf_range(-0.2, 0.2), 2.0, randf_range(-0.2, 0.2))
		#new_block.global_position = claimed_zone.global_position + random_offset
		#
	#await get_tree().create_timer(0.5).timeout
	#if current_state == State.BUILDING: 
		#current_state = State.FINDING_BLOCK
func build_tower() -> void:
	current_state = State.FINDING_BLOCK
	
	if block_scene and claimed_zone:
		var current_block_count = count_blocks_in_zone(claimed_zone)
		var blueprint = blueprints[build_style]
		
		var placement_index = min(current_block_count, blueprint.size() - 1)
		var target_offset = blueprint[placement_index]
		
		var new_block = block_scene.instantiate()
		get_parent().add_child(new_block)
		
		var final_offset = target_offset * block_size
		var drop_height_fudge = Vector3(0, 0.25, 0)
		new_block.global_position = claimed_zone.global_position + final_offset + drop_height_fudge
		
		if new_block is RigidBody3D:
			new_block.rotation = Vector3.ZERO
			new_block.linear_velocity = Vector3.ZERO
			new_block.angular_velocity = Vector3.ZERO
			
			# NEW: Ignore collision between this specific kid and this specific block
			add_collision_exception_with(new_block)
		
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
	
	var zone_pos_2d = Vector2(zone.global_position.x, zone.global_position.z)
	
	for b in get_tree().get_nodes_in_group("BLOCKS"):
		if is_instance_valid(b):
			var block_pos_2d = Vector2(b.global_position.x, b.global_position.z)
			if block_pos_2d.distance_to(zone_pos_2d) < 2.5:
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
	play_audio("cry", true)

func crying_behavior(_delta: float) -> void:
	rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.2
	
func announce_build() -> void:
	# Converts the enum (e.g., TOWER) to the string "build_tower"
	var style_name: String = BuildStyle.keys()[build_style].to_lower()
	play_audio("build_" + style_name, false)

func play_audio(file_name: String, loop: bool = false) -> void:
	# Abort if audio is playing, UNLESS we are trying to play the cry sound
	if voice_player.is_playing() and file_name != "cry":
		return
		
	var audio_path: String = audio_folder + file_name + ".mp3"
	
	if ResourceLoader.exists(audio_path):
		var stream: AudioStream = load(audio_path)
		
		# Godot 4 explicitly allows enabling MP3 loops via code
		if stream is AudioStreamMP3:
			stream.loop = loop
			
		voice_player.stream = stream
		voice_player.play()
	else:
		push_warning("KidAI: Audio file not found at path: " + audio_path)
