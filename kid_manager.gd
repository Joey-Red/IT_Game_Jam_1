extends Node

func _ready() -> void:
	# Await one frame to guarantee all Kid _ready() functions have completed
	await get_tree().process_frame
	assign_unique_traits()

func assign_unique_traits() -> void:
	var kids: Array[Node] = get_tree().get_nodes_in_group("kids")
	var zones: Array[Node] = get_tree().get_nodes_in_group("build_zones")
	
	if kids.is_empty():
		push_warning("KidManager: No kids found.")
		return
		
	if zones.is_empty():
		push_warning("KidManager: No build zones found.")
		return

	# Represents the enum indices: 0 = TOWER, 1 = PYRAMID, 2 = WALL
	var available_styles: Array[int] = [0, 1, 2]
	
	# Shuffle to ensure variety on each playthrough
	available_styles.shuffle()
	zones.shuffle()

	for i in range(kids.size()):
		var kid: Node = kids[i]
		
		# Assign unique style
		if "build_style" in kid:
			kid.build_style = available_styles[i % available_styles.size()]
			
		# Assign unique build zone
		if "claimed_zone" in kid:
			kid.claimed_zone = zones[i % zones.size()]
