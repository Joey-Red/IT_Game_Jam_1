#extends Node
#
#var score: int = 0
#var time_left: float = 600.0 # 10 minutes in seconds
#var is_game_active: bool = true
#
## UI Signals
#signal score_updated(new_score)
#signal time_updated(new_time)
#signal game_over
#
## --- Global Chase & Music State ---
#signal chase_state_changed(is_chasing)
#
#var is_currently_chasing: bool = false
#var bgm_player: AudioStreamPlayer
#var chase_music_player: AudioStreamPlayer
#
## Ensure these match your exact file paths
#var bgm_path: String = "res://assets/bgm.wav"
#var chase_music_path: String = "res://assets/chase_music.mp3"
#
#func _ready() -> void:
	## Initialize audio players dynamically
	#bgm_player = AudioStreamPlayer.new()
	#chase_music_player = AudioStreamPlayer.new()
	#
	#bgm_player.volume_db = -10.0
	#chase_music_player.volume_db = -10.0
	#
	#add_child(bgm_player)
	#add_child(chase_music_player)
	#
	## Load and start background music
	#if ResourceLoader.exists(bgm_path):
		#var stream = load(bgm_path)
		#if stream is AudioStreamMP3: 
			#stream.loop = true
		#bgm_player.stream = stream
		#bgm_player.play()
	#
	## Load chase music
	#if ResourceLoader.exists(chase_music_path):
		#var stream = load(chase_music_path)
		#if stream is AudioStreamMP3: 
			#stream.loop = true
		#chase_music_player.stream = stream
#
#func _process(delta: float) -> void:
	#if is_game_active:
		#time_left -= delta
		#time_updated.emit(time_left)
		#
		#if time_left <= 0:
			#end_game()
#
#func set_chase_state(chasing: bool) -> void:
	#if is_currently_chasing == chasing: 
		#return
	#
	#is_currently_chasing = chasing
	#chase_state_changed.emit(is_currently_chasing)
	#
	## Switch audio tracks based on state
	#if is_currently_chasing:
		#bgm_player.stop()
		#chase_music_player.play()
	#else:
		#chase_music_player.stop()
		#bgm_player.play()
#
#func add_score(points: int) -> void:
	#score += points
	#score_updated.emit(score)
	#print("Score is now: ", score)
#
#func end_game() -> void:
	#is_game_active = false
	#time_left = 0
	#game_over.emit()
	#print("Game Over! Final Score: ", score)
	#
	## Optional: Stop all music on game over
	#bgm_player.stop()
	#chase_music_player.stop()
#
##extends Node
##
##var score: int = 0
##var time_left: float = 600.0 # 10 minutes in seconds
##var is_game_active: bool = true
##
### We will use these signals to tell the Player's HUD to update
##signal score_updated(new_score)
##signal time_updated(new_time)
##signal game_over
##
##func _process(delta: float) -> void:
	##if is_game_active:
		##time_left -= delta
		##time_updated.emit(time_left)
		##
		##if time_left <= 0:
			##end_game()
##
##func add_score(points: int) -> void:
	##score += points
	##score_updated.emit(score)
	##print("Score is now: ", score)
##
##func end_game() -> void:
	##is_game_active = false
	##time_left = 0
	##game_over.emit()
	##print("Game Over! Final Score: ", score)
	### You can later add code here to show a game over UI screen
extends Node

var score: int = 0
var time_left: float = 90.0 # Changed to 90 seconds
var is_game_active: bool = false
var has_started_once: bool = false # Tracks if we should skip the menu on restart

# UI Signals
signal score_updated(new_score)
signal time_updated(new_time)
signal game_over(won: bool)

# Global Chase & Music State
signal chase_state_changed(is_chasing)
var is_currently_chasing: bool = false

var bgm_player: AudioStreamPlayer
var chase_music_player: AudioStreamPlayer

var bgm_path: String = "res://assets/bgm.wav"
var chase_music_path: String = "res://assets/chase_music.mp3"

func _ready() -> void:
	bgm_player = AudioStreamPlayer.new()
	chase_music_player = AudioStreamPlayer.new()
	
	bgm_player.volume_db = -10.0
	chase_music_player.volume_db = -10.0
	
	add_child(bgm_player)
	add_child(chase_music_player)
	
	if ResourceLoader.exists(bgm_path):
		var stream = load(bgm_path)
		if stream is AudioStreamMP3: stream.loop = true
		bgm_player.stream = stream
		bgm_player.play() # Plays immediately on Start Screen
	
	if ResourceLoader.exists(chase_music_path):
		var stream = load(chase_music_path)
		if stream is AudioStreamMP3: stream.loop = true
		chase_music_player.stream = stream

func _process(delta: float) -> void:
	if is_game_active:
		time_left -= delta
		time_updated.emit(time_left)
		
		if time_left <= 0:
			end_game(false)

func start_game() -> void:
	has_started_once = true
	is_game_active = true
	score = 0
	time_left = 90.0
	is_currently_chasing = false
	chase_state_changed.emit(false)
	
	# Restore Master Bus Volume to normal (0 dB)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), 0.0)
	
	score_updated.emit(score)
	if not bgm_player.playing: bgm_player.play()
	chase_music_player.stop()

func set_chase_state(chasing: bool) -> void:
	if is_currently_chasing == chasing: return
	
	is_currently_chasing = chasing
	chase_state_changed.emit(is_currently_chasing)
	
	if is_currently_chasing and is_game_active:
		bgm_player.stop()
		chase_music_player.play()
	else:
		chase_music_player.stop()
		if not bgm_player.playing: bgm_player.play()

func add_score(points: int) -> void:
	if not is_game_active: return
	score += points
	score_updated.emit(score)

func end_game(won: bool = false) -> void:
	if not is_game_active: return
	is_game_active = false
	
	if won:
		# Calculate 10 points per remaining second
		var time_bonus = int(time_left) * 10
		score += time_bonus
		
	time_left = 0
	game_over.emit(won)
	
	# Reduce ALL game audio by 90% (-20 Decibels is roughly a 90% perceived volume drop)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), -20.0)
