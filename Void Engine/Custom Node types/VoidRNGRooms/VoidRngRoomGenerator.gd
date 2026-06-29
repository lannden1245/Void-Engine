extends Node3D

@export var Door_number: String = "door"

@export_group("Room Setup (3D)")
## Drag your Door's Label3D here
@export var door_label_3d: Label3D

@export_group("Room Lists")
@export var good_rooms : Array[Node]
@export var bad_rooms : Array[Node]

@export_group("Speed Settings")
@export var initial_delay: float = 1.0 
@export var pre_load_delay: float = 2.0 
@export_range(0, 60) var frames_between_reveal: int = 1

var load_thread : Thread

func room_gen() -> void:
	if door_label_3d:
		door_label_3d.text = Door_number
	
	if is_multiplayer_authority():
		_host_selection_logic()

func _host_selection_logic():
	if initial_delay > 0:
		await get_tree().create_timer(initial_delay).timeout
	
	var roll = randf()
	var target_list = good_rooms if roll < 0.7 else bad_rooms
	
	if target_list.size() > 0:
		var picked_room = target_list.pick_random()
		rpc("_sync_spawn_room", picked_room.get_path())

@rpc("authority", "call_local", "reliable")
func _sync_spawn_room(room_path: NodePath):
	var room_node = get_node_or_null(room_path)
	if room_node and room_node.has_method("instantiate_node"):
		room_node.call_deferred("instantiate_node")
	
	await get_tree().create_timer(pre_load_delay).timeout
	_start_load_thread()

func _start_load_thread():
	if load_thread and load_thread.is_alive(): return 
	load_thread = Thread.new()
	load_thread.start(_thread_worker)

func _thread_worker():
	OS.delay_msec(10)
	_finish_on_main.call_deferred()

func _finish_on_main():
	if load_thread:
		load_thread.wait_to_finish()
	_reveal_everything_smoothly()

func _reveal_everything_smoothly():
	# 1. Automatic Cleanup
	if has_node("OccluderInstance3D"): $OccluderInstance3D.queue_free()
	if has_node("OccluderInstance3D2"): $OccluderInstance3D2.queue_free()

	# 2. AUTOMATIC DISCOVERY
	# This finds every node inside THIS room that you put in the "RoomVisuals" group
	var visual_parts = get_tree().get_nodes_in_group("RoomVisuals")
	
	for node in visual_parts:
		# Check if the node is actually inside this specific room instance
		if is_instance_valid(node) and is_ancestor_of(node):
			if node.has_method("show"):
				node.show()
				if frames_between_reveal > 0:
					for i in range(frames_between_reveal):
						await get_tree().process_frame 
	
	print("Automated 3D Room Load complete!")

func _exit_tree():
	if load_thread and load_thread.is_alive():
		load_thread.wait_to_finish()
