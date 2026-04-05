extends DirectionalLight3D

@export_category("Lighting States")
@export var normal_color: Color = Color.WHITE
@export var normal_energy: float = 1.0

@export var chase_color: Color = Color.DARK_RED 
@export var chase_energy: float = 0.4 # Dim the lights to make it tense

var target_color: Color
var target_energy: float

func _ready() -> void:
	# Initialize starting values
	target_color = normal_color
	target_energy = normal_energy
	
	# Connect to the global signal
	GameManager.chase_state_changed.connect(_on_chase_state_changed)

func _on_chase_state_changed(is_chasing: bool) -> void:
	if is_chasing:
		target_color = chase_color
		target_energy = chase_energy
	else:
		target_color = normal_color
		target_energy = normal_energy

func _process(delta: float) -> void:
	# Smoothly transition the light color and energy over time using lerp
	light_color = light_color.lerp(target_color, delta * 3.0)
	light_energy = lerpf(light_energy, target_energy, delta * 3.0)
