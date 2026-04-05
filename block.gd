extends RigidBody3D
@export var clack_sound: AudioStream
@onready var clack_player: AudioStreamPlayer = $ClackPlayer

## The list of "Oldschool" solid colors
const PALETTE: Array[Color] = [
	Color.RED,
	Color.BLUE,
	Color.YELLOW,
	Color.GREEN,
	Color.ORANGE,
	Color.PURPLE
]

func _ready() -> void:
	setup_random_color()
	body_entered.connect(_on_body_entered)
	clack_player.stream = clack_sound
func setup_random_color() -> void:
	# 1. Access the MeshInstance3D (assumes it is a direct child)
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
	
	if not mesh_instance:
		push_warning("BlockColor.gd: No MeshInstance3D found as a child.")
		return

	# 2. Create a unique material so we don't change every block in the scene
	var new_material := StandardMaterial3D.new()
	
	# 3. Set properties for the "Oldschool" look
	new_material.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	new_material.albedo_color = PALETTE.pick_random()
	
	# 4. Apply to the mesh
	mesh_instance.set_surface_override_material(0, new_material)
	
	
func _on_body_entered(_body: Node) -> void:
	# Only play sound if moving fast enough (prevents audio spam while resting on ground)
	var impact_velocity = linear_velocity.length()
	if impact_velocity > 1.5:
		if not clack_player.is_playing():
			# Map velocity to volume dynamically. 1.5 min, ~10.0 max expected.
			var volume_db = linear_to_db(clamp(impact_velocity / 10.0, 0.1, 1.0))
			clack_player.volume_db = volume_db
			clack_player.pitch_scale = randf_range(0.8, 1.2)
			clack_player.play()
