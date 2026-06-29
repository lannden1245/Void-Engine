extends Node3D

enum TickRate { 
	Ticks_10HZ = 10, 
	Ticks_20HZ = 20, 
	Ticks_30HZ = 30, 
	Ticks_40HZ = 40,
	Ticks_50HZ = 50,
	Ticks_60HZ = 60, 
	Ticks_120HZ = 120 
}

@export_group("Network & Performance")
## Choose how often movement/rotation is calculated and synced.
@export var sync_tick_rate: TickRate = TickRate.Ticks_60HZ

@export_group("References")
@export var anim_player: AnimationPlayer

@export_group("Animation Names")
@export var idle_anim: StringName = &"idle"
@export var forward_anim: StringName = &"move_forward"
@export var backward_anim: StringName = &"move_backward"

@export_group("Animation Control")
@export_range(0.0, 0.5, 0.01) var input_deadzone: float = 0.1
@export_range(0.0, 20.0, 0.1) var anim_speed: float = 1.0
@export var restart_on_state_change: bool = true

@export_group("Strafe Logic")
@export var strafe_plays_last_fb_direction: bool = true
@export var default_strafe_is_forward: bool = true

@export_group("Options")
@export var full_omnidirectional_movement: bool = true
@export var use_lean_angle_for_strafe: bool = false
@export var enable_side_rotation: bool = false

@export_group("Smoothness & Snappiness")
@export_range(1.0, 50.0) var snappiness_weight: float = 12.0

@export_group("Rotation Angles")
@export var lean_angle: float = 45.0
@export var side_angle: float = 90.0

var _last_anim_key: StringName = &""
var _last_fb_sign: int = -1 
var _tick_timer: float = 0.0

# --- NETWORK SYNC STATE ---
var _last_sent_anim: StringName = &""
var _net_target_y_rot: float = 0.0   # remote-applied rotation target
var _grace_timer: float = 0.5        # wait for scene tree to settle before sending

# ============================================================
# SAFE AUTHORITY + CHANNEL GUARDS
# ============================================================
func _is_safe_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return is_multiplayer_authority()

func _has_ready_peers() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return not multiplayer.get_peers().is_empty()

# ============================================================
# PHYSICS
# ============================================================
func _physics_process(delta: float) -> void:
	if _is_safe_authority():
		# ---- LOCAL OWNER: drive animation + rotation, then sync ----
		if _grace_timer > 0.0:
			_grace_timer -= delta

		var interval := 1.0 / float(sync_tick_rate)
		_tick_timer += delta
		if _tick_timer >= interval:
			_update_animation()
			_handle_local_rotation(_tick_timer)
			# Sync rotation to peers every tick (guarded)
			if _grace_timer <= 0.0 and _has_ready_peers():
				_safe_send_rotation(rotation.y)
			_tick_timer = 0.0
	else:
		# ---- REMOTE PROXY: smoothly lerp toward last received rotation ----
		rotation.y = lerp_angle(rotation.y, _net_target_y_rot, snappiness_weight * delta)

# ============================================================
# ANIMATION (local decides, syncs on change)
# ============================================================
func _update_animation() -> void:
	if anim_player == null: return

	var v: Vector2 = Input.get_vector("l", "r", "f", "b")
	var x: float = v.x
	var y: float = v.y 

	var has_lr: bool = abs(x) > input_deadzone
	var has_fb: bool = abs(y) > input_deadzone

	var desired: StringName = idle_anim

	if has_fb:
		_last_fb_sign = (-1 if y < 0.0 else 1)
		desired = (forward_anim if _last_fb_sign == -1 else backward_anim)
	elif has_lr:
		if strafe_plays_last_fb_direction:
			desired = (forward_anim if _last_fb_sign == -1 else backward_anim)
		else:
			desired = (forward_anim if default_strafe_is_forward else backward_anim)
	else:
		desired = idle_anim

	anim_player.speed_scale = anim_speed
	_play_if_needed(desired)

func _play_if_needed(anim_name: StringName) -> void:
	if anim_name == _last_anim_key: return

	if (not restart_on_state_change) and anim_player.current_animation == String(anim_name):
		_last_anim_key = anim_name
		return

	# Play locally
	if anim_player.has_method("play_synced"):
		anim_player.play_synced(anim_name)
	else:
		anim_player.play(anim_name)

	_last_anim_key = anim_name

	# Sync animation change to all peers (only when changed + channel ready)
	if anim_name != _last_sent_anim and _grace_timer <= 0.0 and _has_ready_peers():
		_last_sent_anim = anim_name
		_safe_send_anim(anim_name)

# ============================================================
# LOCAL ROTATION (owner only)
# ============================================================
func _handle_local_rotation(accumulated_delta: float) -> void:
	if not full_omnidirectional_movement: return

	var input_dir: Vector2 = Input.get_vector("l", "r", "f", "b")
	var target_y_rot: float = 0.0

	if input_dir.x != 0.0:
		var moving_vertical: bool = abs(input_dir.y) > input_deadzone
		if moving_vertical:
			var is_moving_backwards: bool = input_dir.y > 0.0
			target_y_rot = (input_dir.x if is_moving_backwards else -input_dir.x) * deg_to_rad(lean_angle)
		elif use_lean_angle_for_strafe:
			target_y_rot = -input_dir.x * deg_to_rad(lean_angle)
		elif enable_side_rotation:
			target_y_rot = -input_dir.x * deg_to_rad(side_angle)

	rotation.y = lerp_angle(rotation.y, target_y_rot, snappiness_weight * accumulated_delta)

# ============================================================
# SAFE RPC SENDERS (guard against closed WebRTC channels)
# ============================================================
func _safe_send_rotation(y_rot: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_receive_rotation.rpc(y_rot)

func _safe_send_anim(anim_name: StringName) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_receive_anim.rpc(String(anim_name))

# ============================================================
# RPC RECEIVERS (remote proxies only)
# ============================================================
@rpc("any_peer", "unreliable")
func _receive_rotation(y_rot: float) -> void:
	if not is_inside_tree() or is_multiplayer_authority():
		return
	# Store target; _physics_process lerps toward it smoothly
	_net_target_y_rot = y_rot

@rpc("any_peer", "call_remote", "reliable")
func _receive_anim(anim_name: String) -> void:
	if not is_inside_tree() or is_multiplayer_authority():
		return
	# GUARD: anim_player might not be ready/valid on this peer yet
	if anim_player == null or not is_instance_valid(anim_player):
		return
	var sname := StringName(anim_name)
	if _last_anim_key == sname:
		return
	anim_player.speed_scale = anim_speed
	anim_player.play(sname)
	_last_anim_key = sname
