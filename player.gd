extends CharacterBody3D

@export_category("Movement Settings")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var sneak_speed: float = 2.0
@export var jump_velocity: float = 4.5

@export_category("Mouse Settings")
@export var mouse_sensitivity: float = 0.002

# Inventory
var blocks_in_hands: int = 0
@export var max_blocks_in_hands: int = 3

# UI References
@onready var score_label = $HUD/ScoreLabel
@onready var timer_label = $HUD/TimerLabel
@onready var inventory_label = $HUD/InventoryLabel

# State variables
var current_speed: float = walk_speed
var is_sneaking: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- NEW: A dedicated variable to track vertical camera rotation ---
var camera_pitch: float = 0.0

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var interaction_ray = $Head/Camera3D/RayCast3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	update_inventory_ui()
	
	# Connect to the GameManager signals to update our UI
	GameManager.score_updated.connect(_on_score_updated)
	GameManager.time_updated.connect(_on_time_updated)
	GameManager.game_over.connect(_on_game_over)
	
	# Set initial UI text
	_on_score_updated(GameManager.score)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Horizontal rotation (Player Body)
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Vertical rotation (Head Node) - Bulletproof method
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch = clamp(camera_pitch, deg_to_rad(-85), deg_to_rad(85))
		head.rotation.x = camera_pitch
		
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_pressed("interact"):
		if interaction_ray.is_colliding():
			var target = interaction_ray.get_collider()
			
			# If looking at a BLOCK (Layer 2)
			if target.get_collision_layer_value(2):
				if blocks_in_hands < max_blocks_in_hands:
					target.queue_free()
					blocks_in_hands += 1
					update_inventory_ui()
					
			# If looking at the CUBBY (Layer 3)
			elif target.get_collision_layer_value(3):
				if blocks_in_hands > 0:
					# Calculate points
					var points_earned = blocks_in_hands * 100
					GameManager.add_score(points_earned)
					blocks_in_hands = 0
					update_inventory_ui()

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Handle Sneaking and Sprinting states
	if Input.is_action_pressed("sneak"):
		is_sneaking = true
		current_speed = sneak_speed
		head.position.y = lerp(head.position.y, 0.2, delta * 10) # Lower camera to crouch
	else:
		is_sneaking = false
		head.position.y = lerp(head.position.y, 0.6, delta * 10) # Stand back up
		
		if Input.is_action_pressed("sprint") and is_on_floor():
			current_speed = sprint_speed
		else:
			current_speed = walk_speed

	# Get input direction and handle movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	# --- Kick blocks over ---
# --- Kick blocks over ---
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		# FIX 1: EXACT MATCH for "BLOCKS" in all caps
		if collider is RigidBody3D and collider.is_in_group("BLOCKS"):
			
			# FIX 2: Force the engine to wake the block up
			collider.sleeping = false
			
			# FIX 3: A sane multiplier. (Assuming your Block mass is 0.1)
			var push_impulse_multiplier = 0.05
			
			# FIX 4: Improved Push Physics
			# We take the collision angle, but add a slight upward tilt (0.2) 
			# so the blocks actually tumble and roll instead of just sliding flat.
			var push_dir = -collision.get_normal()
			push_dir.y = 0.2 
			
			var push_force = push_dir.normalized() * current_speed * push_impulse_multiplier
			collider.apply_central_impulse(push_force)


# --- UI Helper Functions ---
func update_inventory_ui() -> void:
	if inventory_label:
		inventory_label.text = "Backpack: " + str(blocks_in_hands) + " / " + str(max_blocks_in_hands)

func _on_score_updated(new_score: int) -> void:
	if score_label:
		score_label.text = "Score: " + str(new_score)

func _on_time_updated(time_left: float) -> void:
	if timer_label:
		var minutes = int(time_left / 60.0)
		var seconds = int(time_left) % 60
		timer_label.text = "%d:%02d" % [minutes, seconds]

func _on_game_over() -> void:
	if timer_label and inventory_label:
		timer_label.text = "0:00"
		inventory_label.text = "TIME'S UP!"
	walk_speed = 0
	sprint_speed = 0
	sneak_speed = 0
