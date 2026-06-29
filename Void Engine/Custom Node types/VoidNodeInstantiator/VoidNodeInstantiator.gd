@tool
extends Node3D

@export_group("Spawn Settings")
## The .tscn file you want to spawn
@export var scene_to_spawn: PackedScene
## If true, spawns automatically when the node enters the tree
@export var spawn_on_ready : bool = false

@export_group("Custom Path Logic")
## Optional: Choose a specific node to spawn the scene into. 
## If left empty, it spawns as a child of THIS node.
@export var custom_parent_path : NodePath
## If true, the spawned object will match this node's Position/Rotation exactly
@export var sync_transform : bool = true

@export_group("Network & Persistence")
## If true, players who join late will automatically see the spawned node
@export var late_joiner_sync : bool = true

# --- Internal Variables ---
var spawned_instances: Array[Node] = []

func _ready() -> void:
	if Engine.is_editor_hint(): return
	
	# WAIT for the peer to be assigned
	if not multiplayer.has_multiplayer_peer():
		await get_tree().create_timer(0.1).timeout
	
	# Now check safely
	if multiplayer.has_multiplayer_peer():
		if is_multiplayer_authority():
			if late_joiner_sync:
				multiplayer.peer_connected.connect(func(id):
					for i in range(spawned_instances.size()):
						rpc_id(id, "_execute_spawn")
				)
			
			if spawn_on_ready:
				instantiate_node()

## THE MAIN CALL: Triggers the spawning logic across the network
func instantiate_node() -> void:
	if is_multiplayer_authority():
		rpc("_execute_spawn")

@rpc("authority", "call_local", "reliable")
func _execute_spawn() -> void:
	if scene_to_spawn == null:
		push_warning("VoidInstantiator [%s]: Scene is empty!" % name)
		return

	# 1. INSTANTIATE
	var instance = scene_to_spawn.instantiate()
	
	# 2. CUSTOM PATH LOGIC
	var target_parent = self
	if custom_parent_path:
		var potential_node = get_node_or_null(custom_parent_path)
		if potential_node: target_parent = potential_node
	
	# 3. TRANSFORM SYNC
	if sync_transform and instance is Node3D:
		instance.global_transform = global_transform

	# 4. UNIQUE SYNC NAME (Critical for Multiplayer)
	instance.name = "VoidSync_" + str(get_instance_id()) + "_" + str(spawned_instances.size())

	target_parent.add_child(instance)
	
	# 5. TRACKING
	spawned_instances.append(instance)

## Utility: Remove the most recently spawned object across the network
func clear_last() -> void:
	if is_multiplayer_authority():
		rpc("_execute_cleanup")

@rpc("authority", "call_local", "reliable")
func _execute_cleanup() -> void:
	if spawned_instances.size() > 0:
		var last = spawned_instances.pop_back()
		if is_instance_valid(last):
			last.queue_free()
