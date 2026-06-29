@tool
extends Marker3D


@export var room_scenes : Array[PackedScene] = []
@export var instantiate_on_ready : bool = false
var synchronized_instantiate : bool = false

var rng = RandomNumberGenerator.new()
var already_instantiated = false
var shared_seed : int = 0

func _ready() -> void:
	if Engine.is_editor_hint(): return
	
	if multiplayer.is_server():
		rng.randomize()
		shared_seed = rng.seed
		multiplayer.peer_connected.connect(_on_peer_connected)
	
	if instantiate_on_ready:
		instantiate_node()

func _on_peer_connected(id: int):
	if already_instantiated:
		rpc_id(id, "spawn_on_all_clients", shared_seed, synchronized_instantiate)

func instantiate_node():
	if already_instantiated: return
	
	if is_multiplayer_authority():
		rpc("spawn_on_all_clients", shared_seed, synchronized_instantiate)

@rpc("authority", "call_local", "reliable")
func spawn_on_all_clients(seed_to_use: int, should_sync: bool):
	if already_instantiated: return
	
	rng.seed = seed_to_use
	
	for i in range(room_scenes.size()):
		if not room_scenes[i]: continue
		
		var room_index = rng.randi() % room_scenes.size()
		var instance = room_scenes[room_index].instantiate()
		
		if should_sync:
			instance.name = "Room_" + str(i) + "_" + str(get_instance_id())
		else:
			instance.name = "LocalRoom_" + str(i) + "_" + str(multiplayer.get_unique_id())
			for sync in instance.find_children("*", "MultiplayerSynchronizer"):
				sync.queue_free()
				
		add_child(instance)
	
	already_instantiated = true
