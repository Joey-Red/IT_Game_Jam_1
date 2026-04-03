extends Node

var score: int = 0
var time_left: float = 600.0 # 10 minutes in seconds
var is_game_active: bool = true

# We will use these signals to tell the Player's HUD to update
signal score_updated(new_score)
signal time_updated(new_time)
signal game_over

func _process(delta: float) -> void:
	if is_game_active:
		time_left -= delta
		time_updated.emit(time_left)
		
		if time_left <= 0:
			end_game()

func add_score(points: int) -> void:
	score += points
	score_updated.emit(score)
	print("Score is now: ", score)

func end_game() -> void:
	is_game_active = false
	time_left = 0
	game_over.emit()
	print("Game Over! Final Score: ", score)
	# You can later add code here to show a game over UI screen
