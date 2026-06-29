@tool
extends PathFollow3D

## This script ensures late-joiners see the monster at the correct position.

func _ready() -> void:
	if Engine.is_editor_hint(): return
	
	# THE FIX: Only connect signals if the network is actually started
	if multiplayer.has_multiplayer_peer():
		if is_multiplayer_authority():
			multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(id: int) -> void:
	# If a player joins while the monster is moving/visible, catch them up
	if is_visible_in_tree() and progress_ratio > 0.01:
		# Send current progress and visibility state only to the new player
		rpc_id(id, "_sync_late_joiner", progress, visible)

@rpc("authority", "call_remote", "reliable")
func _sync_late_joiner(_current_progress: float, _is_visible: bool) -> void:
	# New player receives the exact state of the monster
	progress = _current_progress
	visible = _is_visible
