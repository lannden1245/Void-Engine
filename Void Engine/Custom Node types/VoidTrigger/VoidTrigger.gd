@tool
extends Area3D

@export var player_group_name = "player"

@export_group("Room Generation Trigger")
@export var room_manager: RNG_Rooms_test
@export var room_trigger: bool = false

@export_group("AI Path Following")
@export var path_follow_node: PathFollow3D
@export var move_speed: float = 20.0
@export var movement_delay: float = 2.0
@export var path_trigger: bool = false
@export var hide_on_finish: bool = true

# --- ADDED ---
@export var ai_ping_pong: bool = false
@export_range(1, 100, 1) var ai_back_and_forth_times: int = 1
# -------------

@export_group("Animation trigger")
@export var animation_name = ""
@export var Animation_player: AnimationPlayer
@export var animation_delay: float = 0.0
@export var animation_trigger: bool = false

@export_group("AudioPlayer trigger")
@export var audio_player: AudioStreamPlayer3D
@export var audio_delay: float = 0.5
@export var audioplayer_trigger: bool = false

@export_group("Teleport trigger")
@export var connect_portal: Node3D
@export var NodeTeleporter: bool = false

# Internal state for sync
var _is_active: bool = false

# --- ADDED ---
var _ai_direction: float = 1.0
var _ai_completed_round_trips: int = 0
# -------------

func _ready():
	if Engine.is_editor_hint():
		set_process(false)
		return

	set_process(false)
	if path_trigger and path_follow_node:
		path_follow_node.hide()

	# --- SYNC HANDSHAKE ---
	if multiplayer.has_multiplayer_peer():
		if is_multiplayer_authority():
			multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(id: int):
	# If a player joins late and the AI monster is currently running
	if _is_active and path_follow_node:
		# Send current progress and visibility to the new player only
		rpc_id(id, "_sync_late_joiner", path_follow_node.progress, path_follow_node.visible, _ai_direction, _ai_completed_round_trips, _is_active)

@rpc("authority", "call_remote", "reliable")
func _sync_late_joiner(current_progress: float, is_visible: bool, current_direction: float, completed_round_trips: int, is_running: bool):
	if path_follow_node:
		path_follow_node.progress = current_progress
		path_follow_node.visible = is_visible
	_ai_direction = current_direction
	_ai_completed_round_trips = completed_round_trips
	_is_active = is_running
	if is_visible and is_running:
		set_process(true)

func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if is_multiplayer_authority() and body.is_in_group(player_group_name):
		if room_trigger and room_manager:
			room_manager.room_gen()

		if path_trigger and path_follow_node:
			rpc("_start_ai_sequence")

		if animation_trigger:
			rpc("_delayed_animation")

		if audioplayer_trigger:
			rpc("_delayed_audio")

		if NodeTeleporter and connect_portal:
			rpc("_sync_teleport", body.get_path())

# --- AI PATH LOGIC ---

func _process(delta):
	if not multiplayer.has_multiplayer_peer() or not path_follow_node:
		return

	if is_multiplayer_authority():
		path_follow_node.progress += move_speed * delta * _ai_direction
		rpc("_sync_path_position", path_follow_node.progress)

		if not ai_ping_pong:
			if path_follow_node.progress_ratio >= 0.99:
				rpc("_finish_ai_sequence")
		else:
			if _ai_direction > 0.0 and path_follow_node.progress_ratio >= 0.99:
				path_follow_node.progress_ratio = 1.0
				_ai_direction = -1.0
				rpc("_sync_ai_direction_state", _ai_direction, _ai_completed_round_trips)

			elif _ai_direction < 0.0 and path_follow_node.progress_ratio <= 0.01:
				path_follow_node.progress_ratio = 0.0
				_ai_completed_round_trips += 1

				if _ai_completed_round_trips >= ai_back_and_forth_times:
					rpc("_finish_ai_sequence")
				else:
					_ai_direction = 1.0
					rpc("_sync_ai_direction_state", _ai_direction, _ai_completed_round_trips)

@rpc("any_peer", "unreliable")
func _sync_path_position(current_progress: float):
	if path_follow_node and not is_multiplayer_authority():
		path_follow_node.progress = current_progress

# --- ADDED ---
@rpc("authority", "call_remote", "reliable")
func _sync_ai_direction_state(direction: float, completed_round_trips: int):
	_ai_direction = direction
	_ai_completed_round_trips = completed_round_trips
# -------------

@rpc("authority", "call_local", "reliable")
func _finish_ai_sequence():
	set_process(false)
	_is_active = false
	_ai_direction = 1.0
	_ai_completed_round_trips = 0
	if hide_on_finish and path_follow_node:
		path_follow_node.hide()

@rpc("authority", "call_local", "reliable")
func _start_ai_sequence():
	if _is_active:
		return
	_is_active = true
	_ai_direction = 1.0
	_ai_completed_round_trips = 0
	if path_follow_node:
		path_follow_node.progress_ratio = 0
	await get_tree().create_timer(movement_delay).timeout
	if path_follow_node:
		path_follow_node.show()
	set_process(true)

# --- TELEPORT LOGIC ---

@rpc("authority", "call_local", "reliable")
func _sync_teleport(target_body_path: NodePath):
	var body = get_node_or_null(target_body_path)
	if body and connect_portal:
		body.global_transform = connect_portal.global_transform

# --- ANIMATION & AUDIO ---

@rpc("authority", "call_local", "reliable")
func _delayed_animation():
	if Animation_player:
		await get_tree().create_timer(animation_delay).timeout
		Animation_player.play(animation_name)

@rpc("authority", "call_local", "reliable")
func _delayed_audio():
	if audio_player:
		await get_tree().create_timer(audio_delay).timeout
		audio_player.play()
