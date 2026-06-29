extends Node3D

# This signal is emitted when EVERY room has finished generating
signal all_rooms_ready
@export var generate_on_spawn = true

@export_group("UI Elements")
@export var loading_screen : Control 
@export var progress_bar : ProgressBar
@export var status_label : Label

@export_group("Room Selection")
@export var rooms_to_trigger : Array[Node]

@export_group("Performance Settings")
@export var start_delay : float = 10.0
@export var seconds_between_starts : float = 0.5

var load_thread : Thread
var rooms_completed : int = 0

func GenerateRooms():
	if loading_screen: loading_screen.hide()
	
	await get_tree().create_timer(start_delay).timeout
	
	if loading_screen: loading_screen.show()
	
	if progress_bar:
		progress_bar.min_value = 0
		progress_bar.max_value = rooms_to_trigger.size()
		progress_bar.value = 0
	
	# 1. Connect to signals from individual rooms
	for room in rooms_to_trigger:
		if room.has_signal("generation_finished"):
			room.generation_finished.connect(_on_room_finished)
		
		load_thread = Thread.new()
		load_thread.start(_threaded_scheduler)

func _ready() -> void:
	if generate_on_spawn == true:
		if loading_screen: loading_screen.hide()
		
		await get_tree().create_timer(start_delay).timeout
		
		if loading_screen: loading_screen.show()
		
		if progress_bar:
			progress_bar.min_value = 0
			progress_bar.max_value = rooms_to_trigger.size()
			progress_bar.value = 0
		
		# 1. Connect to signals from individual rooms
		for room in rooms_to_trigger:
			if room.has_signal("generation_finished"):
				room.generation_finished.connect(_on_room_finished)
		
		load_thread = Thread.new()
		load_thread.start(_threaded_scheduler)

func _threaded_scheduler() -> void:
	for i in range(rooms_to_trigger.size()):
		var room_node = rooms_to_trigger[i]
		if is_instance_valid(room_node):
			_update_status_text.call_deferred(i + 1, rooms_to_trigger.size())
			if room_node.has_method("room_gen"):
				room_node.call_deferred("room_gen")
			
			OS.delay_msec(int(seconds_between_starts * 1000.0))
	
	_finish_scheduler.call_deferred()

func _update_status_text(current: int, total: int):
	if status_label:
		status_label.text = "Generating Rooms: " + str(current) + " / " + str(total)

func _on_room_finished():
	rooms_completed += 1
	if progress_bar:
		progress_bar.value = rooms_completed
	
	# 2. CHECK IF EVERYTHING IS DONE
	if rooms_completed >= rooms_to_trigger.size():
		_finalize_generation()

func _finalize_generation():
	if status_label:
		status_label.text = "Rooms Ready!"
	
	# Give a small buffer for the final frame to render
	await get_tree().create_timer(1.0).timeout
	
	# 3. EMIT THE MAIN SIGNAL (This starts your elevator/animations)
	all_rooms_ready.emit()
	
	# Hide UI
	if loading_screen:
		var tween = create_tween()
		tween.tween_property(loading_screen, "modulate:a", 0.0, 0.5)
		tween.tween_callback(loading_screen.hide)

func _finish_scheduler():
	if load_thread:
		load_thread.wait_to_finish()

func _exit_tree():
	if load_thread and load_thread.is_alive():
		load_thread.wait_to_finish()
