#extends CharacterBody3D
#
#@export_category("Movement Settings")
#@export var walk_speed: float = 4.0
#@export var sprint_speed: float = 7.0
#@export var sneak_speed: float = 2.0
#@export var jump_velocity: float = 4.5
#
#@export_category("Mouse Settings")
#@export var mouse_sensitivity: float = 0.002
#
## Inventory
#var blocks_in_hands: int = 0
#@export var max_blocks_in_hands: int = 3
#
## UI References
#@onready var score_label = $HUD/ScoreLabel
#@onready var timer_label = $HUD/TimerLabel
#@onready var inventory_label = $HUD/InventoryLabel
#
## State variables
#var current_speed: float = walk_speed
#var is_sneaking: bool = false
#var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
#
## --- Camera Rotation ---
#var camera_pitch: float = 0.0
#
#@onready var head = $Head
#@onready var camera = $Head/Camera3D
#@onready var interaction_ray = $Head/Camera3D/RayCast3D
#
#@export_category("Audio Files")
#@export var sfx_pickup: AudioStream
#@export var sfx_deposit: AudioStream
#@export var sfx_jump: AudioStream
#@export var sfx_land: AudioStream
#@export var sfx_footstep: AudioStream
#
#@onready var sfx_player: AudioStreamPlayer = $SFXPlayer
#@onready var movement_player: AudioStreamPlayer = $MovementPlayer
#@onready var footstep_player: AudioStreamPlayer = $FootstepPlayer
#
#var footstep_timer: float = 0.0
#var footstep_interval: float = 0.4
#var was_on_floor: bool = true
#
#func _ready() -> void:
	#Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	#update_inventory_ui()
	#
	## Connect to the GameManager signals to update our UI
	#GameManager.score_updated.connect(_on_score_updated)
	#GameManager.time_updated.connect(_on_time_updated)
	#GameManager.game_over.connect(_on_game_over)
	#
	## Set initial UI text
	#_on_score_updated(GameManager.score)
#
#func _unhandled_input(event: InputEvent) -> void:
	#if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		## Horizontal rotation (Player Body)
		#rotate_y(-event.relative.x * mouse_sensitivity)
		#
		## Vertical rotation (Head Node)
		#camera_pitch -= event.relative.y * mouse_sensitivity
		#camera_pitch = clamp(camera_pitch, deg_to_rad(-85), deg_to_rad(85))
		#head.rotation.x = camera_pitch
		#
	#if event.is_action_pressed("ui_cancel"):
		#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
#
	#if event.is_action_pressed("interact"):
		#if interaction_ray.is_colliding():
			#var target = interaction_ray.get_collider()
			#
			## If looking at a BLOCK
			#if target.get_collision_layer_value(2):
				#if blocks_in_hands < max_blocks_in_hands:
					#target.queue_free()
					#blocks_in_hands += 1
					#update_inventory_ui()
					#if sfx_pickup:
						#sfx_player.stream = sfx_pickup
						#sfx_player.play()
					#
			## If looking at the CUBBY
			#elif target.get_collision_layer_value(3):
				#if blocks_in_hands > 0:
					#var points_earned = blocks_in_hands * 100
					#GameManager.add_score(points_earned)
					#blocks_in_hands = 0
					#update_inventory_ui()
					#if sfx_deposit:
						#sfx_player.stream = sfx_deposit
						#sfx_player.play()
#
#func _physics_process(delta: float) -> void:
	#var currently_on_floor = is_on_floor()
	#
	## Landing Audio Logic
	#if currently_on_floor and not was_on_floor:
		#if sfx_land:
			#movement_player.stream = sfx_land
			#movement_player.play()
	#was_on_floor = currently_on_floor
#
	## Add gravity
	#if not currently_on_floor:
		#velocity.y -= gravity * delta
#
	## Handle Jump
	#if Input.is_action_just_pressed("jump") and currently_on_floor:
		#velocity.y = jump_velocity
		## Jump Audio Logic
		#if sfx_jump:
			#movement_player.stream = sfx_jump
			#movement_player.play()
#
	## Handle Sneaking and Sprinting states
	#if Input.is_action_pressed("sneak"):
		#is_sneaking = true
		#current_speed = sneak_speed
		#head.position.y = lerp(head.position.y, 0.2, delta * 10) 
	#else:
		#is_sneaking = false
		#head.position.y = lerp(head.position.y, 0.6, delta * 10) 
		#
		#if Input.is_action_pressed("sprint") and currently_on_floor:
			#current_speed = sprint_speed
		#else:
			#current_speed = walk_speed
#
	## Get input direction and handle movement
	#var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	#var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	#
	#if direction:
		#velocity.x = direction.x * current_speed
		#velocity.z = direction.z * current_speed
	#else:
		#velocity.x = move_toward(velocity.x, 0, current_speed)
		#velocity.z = move_toward(velocity.z, 0, current_speed)
		#
	## Footstep logic
	#if currently_on_floor and velocity.length() > 0.5:
		#footstep_interval = 0.3 if current_speed == sprint_speed else 0.5
		#footstep_interval = 0.7 if is_sneaking else footstep_interval
		#
		#footstep_timer -= delta
		#if footstep_timer <= 0:
			#if sfx_footstep:
				#footstep_player.stream = sfx_footstep
				#footstep_player.pitch_scale = randf_range(0.9, 1.1)
				#footstep_player.play()
			#footstep_timer = footstep_interval
	#else:
		#footstep_timer = 0.0
		#
	#move_and_slide()
#
	## --- Kick blocks over ---
	#for i in get_slide_collision_count():
		#var collision = get_slide_collision(i)
		#var collider = collision.get_collider()
		#
		#if collider is RigidBody3D and collider.is_in_group("BLOCKS"):
			#collider.sleeping = false
			#var push_impulse_multiplier = 0.05
			#
			#var push_dir = -collision.get_normal()
			#push_dir.y = 0.2 
			#
			#var push_force = push_dir.normalized() * current_speed * push_impulse_multiplier
			#collider.apply_central_impulse(push_force)
#
## --- UI Helper Functions ---
#func update_inventory_ui() -> void:
	#if inventory_label:
		#inventory_label.text = "Holding blocks: " + str(blocks_in_hands) + " / " + str(max_blocks_in_hands)
#
#func _on_score_updated(new_score: int) -> void:
	#if score_label:
		#score_label.text = "Score: " + str(new_score)
#
#func _on_time_updated(time_left: float) -> void:
	#if timer_label:
		#var minutes = int(time_left / 60.0)
		#var seconds = int(time_left) % 60
		#timer_label.text = "%d:%02d" % [minutes, seconds]
#
#func _on_game_over() -> void:
	#if timer_label and inventory_label:
		#timer_label.text = "0:00"
		#inventory_label.text = "TIME'S UP!"
	#walk_speed = 0
	#sprint_speed = 0
	#sneak_speed = 0
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

# --- NEW: Menu UI References ---
@onready var start_screen = $HUD/StartScreen
@onready var play_button = $HUD/StartScreen/PlayButton

@onready var game_over_screen = $HUD/GameOverScreen
@onready var final_score_label = $HUD/GameOverScreen/FinalScoreLabel
@onready var play_again_button = $HUD/GameOverScreen/PlayAgainButton

# State variables
var current_speed: float = walk_speed
var is_sneaking: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var camera_pitch: float = 0.0

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var interaction_ray = $Head/Camera3D/RayCast3D

@export_category("Audio Files")
@export var sfx_pickup: AudioStream
@export var sfx_deposit: AudioStream
@export var sfx_jump: AudioStream
@export var sfx_land: AudioStream
@export var sfx_footstep: AudioStream

@onready var sfx_player: AudioStreamPlayer = $SFXPlayer
@onready var movement_player: AudioStreamPlayer = $MovementPlayer
@onready var footstep_player: AudioStreamPlayer = $FootstepPlayer

var footstep_timer: float = 0.0
var footstep_interval: float = 0.4
var was_on_floor: bool = true

func _ready() -> void:
	update_inventory_ui()
	
	GameManager.score_updated.connect(_on_score_updated)
	GameManager.time_updated.connect(_on_time_updated)
	GameManager.game_over.connect(_on_game_over)
	
	play_button.pressed.connect(_on_play_pressed)
	play_again_button.pressed.connect(_on_play_again_pressed)
	
	# Determine if we show the Start Menu or jump right in (if restarting)
	game_over_screen.hide()
	if not GameManager.has_started_once:
		start_screen.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		start_screen.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		GameManager.start_game()
		
	_on_score_updated(GameManager.score)

func _on_play_pressed() -> void:
	start_screen.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameManager.start_game()

func _on_play_again_pressed() -> void:
	# Reloading the scene resets the physical world, GameManager persists the state
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if not GameManager.is_game_active: return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch = clamp(camera_pitch, deg_to_rad(-85), deg_to_rad(85))
		head.rotation.x = camera_pitch
		
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_pressed("interact"):
			if interaction_ray.is_colliding():
				var target = interaction_ray.get_collider()
				
				# --- FIX: Ensure the target actually exists before checking layers ---
				# This prevents crashes if the AI deletes the block right as you click it,
				# or if the raycast hits a non-physics node.
				if not is_instance_valid(target) or not target.has_method("get_collision_layer_value"):
					return
				
				if target.get_collision_layer_value(2):
					if blocks_in_hands < max_blocks_in_hands:
						target.queue_free()
						blocks_in_hands += 1
						update_inventory_ui()
						if sfx_pickup:
							sfx_player.stream = sfx_pickup
							sfx_player.play()
						
				elif target.get_collision_layer_value(3):
					if blocks_in_hands > 0:
						var points_earned = blocks_in_hands * 100
						GameManager.add_score(points_earned)
						blocks_in_hands = 0
						update_inventory_ui()
						if sfx_deposit:
							sfx_player.stream = sfx_deposit
							sfx_player.play()
						
						# --- WIN CONDITION ---
						if GameManager.score >= 1000:
							GameManager.end_game(true)

func _physics_process(delta: float) -> void:
	if not GameManager.is_game_active: 
		return # Stop player movement if menu is open
		
	var currently_on_floor = is_on_floor()
	
	if currently_on_floor and not was_on_floor:
		if sfx_land:
			movement_player.stream = sfx_land
			movement_player.play()
	was_on_floor = currently_on_floor

	if not currently_on_floor:
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and currently_on_floor:
		velocity.y = jump_velocity
		if sfx_jump:
			movement_player.stream = sfx_jump
			movement_player.play()

	if Input.is_action_pressed("sneak"):
		is_sneaking = true
		current_speed = sneak_speed
		head.position.y = lerp(head.position.y, 0.2, delta * 10) 
	else:
		is_sneaking = false
		head.position.y = lerp(head.position.y, 0.6, delta * 10) 
		
		if Input.is_action_pressed("sprint") and currently_on_floor:
			current_speed = sprint_speed
		else:
			current_speed = walk_speed

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
		
	if currently_on_floor and velocity.length() > 0.5:
		footstep_interval = 0.3 if current_speed == sprint_speed else 0.5
		footstep_interval = 0.7 if is_sneaking else footstep_interval
		
		footstep_timer -= delta
		if footstep_timer <= 0:
			if sfx_footstep:
				footstep_player.stream = sfx_footstep
				footstep_player.pitch_scale = randf_range(0.9, 1.1)
				footstep_player.play()
			footstep_timer = footstep_interval
	else:
		footstep_timer = 0.0
		
	move_and_slide()

	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		if collider is RigidBody3D and collider.is_in_group("BLOCKS"):
			collider.sleeping = false
			var push_impulse_multiplier = 0.05
			var push_dir = -collision.get_normal()
			push_dir.y = 0.2 
			var push_force = push_dir.normalized() * current_speed * push_impulse_multiplier
			collider.apply_central_impulse(push_force)

# --- UI Helper Functions ---
func update_inventory_ui() -> void:
	if inventory_label:
		inventory_label.text = "Holding blocks: " + str(blocks_in_hands) + " / " + str(max_blocks_in_hands)

func _on_score_updated(new_score: int) -> void:
	if score_label:
		score_label.text = "Score: " + str(new_score)

func _on_time_updated(time_left: float) -> void:
	if timer_label:
		var minutes = int(time_left / 60.0)
		var seconds = int(time_left) % 60
		timer_label.text = "%d:%02d" % [minutes, seconds]

func _on_game_over(won: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game_over_screen.show()
	
	if won:
		final_score_label.text = "YOU WIN!\nTime Bonus Applied!\nFinal Score: " + str(GameManager.score)
	else:
		final_score_label.text = "GAME OVER\nFinal Score: " + str(GameManager.score)
		if timer_label and inventory_label:
			timer_label.text = "0:00"
			inventory_label.text = "TIME'S UP!"
			
	# Halt movement
	walk_speed = 0
	sprint_speed = 0
	sneak_speed = 0
