extends Node

enum TickRate { MODE_10HZ, MODE_20HZ, MODE_30HZ, MODE_40HZ, MODE_50HZ, MODE_60HZ, MODE_120HZ } 

@export var sync_mode: TickRate = TickRate.MODE_20HZ:
	set(value):
		sync_mode = value
		set_tick_rate(sync_mode)

@export var target: Node3D 
@export var sync_position: bool = true
@export var sync_rotation: bool = true

var TICK_RATE: float = 0.05
var tick_timer: float = 0.0
var network_grace_timer: float = 0.5 

func _ready() -> void:
	set_tick_rate(sync_mode)
	if target == null and get_parent() is Node3D:
		target = get_parent() as Node3D

func set_tick_rate(mode: TickRate) -> void:
	match mode:
		TickRate.MODE_10HZ:  TICK_RATE = 1.0 / 10.0
		TickRate.MODE_20HZ:  TICK_RATE = 1.0 / 20.0
		TickRate.MODE_30HZ:  TICK_RATE = 1.0 / 30.0
		TickRate.MODE_40HZ:  TICK_RATE = 1.0 / 40.0
		TickRate.MODE_50HZ:  TICK_RATE = 1.0 / 50.0
		TickRate.MODE_60HZ:  TICK_RATE = 1.0 / 60.0
		TickRate.MODE_120HZ: TICK_RATE = 1.0 / 120.0

# --- CRASH-PROOF AUTHORITY GUARD ---
func _is_safe_authority() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return is_multiplayer_authority()

# --- WEBRTC SAFE-SEND GUARD: only send to FULLY connected peers ---
func _has_ready_peers() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	# Must have at least one actual peer to send to
	return not multiplayer.get_peers().is_empty()

func _physics_process(delta: float) -> void:
	if target == null:
		return
	if not _is_safe_authority():
		return
	if network_grace_timer > 0.0:
		network_grace_timer -= delta
		return

	tick_timer += delta
	if tick_timer >= TICK_RATE:
		tick_timer = 0.0

		# CRITICAL: don't send if no peers are ready (prevents channel->isClosed errors)
		if not _has_ready_peers():
			return

		var sync_data := {}
		if sync_position: 
			sync_data["p"] = target.global_position
		if sync_rotation: 
			sync_data["r"] = target.global_rotation

		if not sync_data.is_empty():
			# Wrapped in a safety call to avoid crashing on a half-closed channel
			_safe_send(sync_data)

func _safe_send(sync_data: Dictionary) -> void:
	# Final guard: peer could close between the check and the send
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	receive_sync_data.rpc(sync_data)

@rpc("any_peer", "unreliable")
func receive_sync_data(data: Dictionary) -> void:
	# SAFETY GATE: stop if not in tree, or we own this entity (don't overwrite our own pos)
	if not is_inside_tree() or is_multiplayer_authority():
		return
	# Use the EXPORTED target (no shadowing). Fall back to parent if unset.
	var apply_target: Node3D = target
	if apply_target == null and get_parent() is Node3D:
		apply_target = get_parent() as Node3D
	if apply_target == null:
		return

	if data.has("p"):
		apply_target.global_position = data["p"]
	if data.has("r"):
		apply_target.global_rotation = data["r"]
