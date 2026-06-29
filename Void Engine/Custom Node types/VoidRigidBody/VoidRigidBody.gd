extends RigidBody3D

@export_group("Network Settings")
## Choose the frequency of updates. Higher = Better quality, more internet usage.
@export_enum("10 Ticks", "20 Ticks", "30 Ticks", "40 Ticks", "50 Ticks","120 Ticks") var tick_rate: int = 1

## Higher = Snappier/Faster, Lower = Smoother/Delayed
@export_range(0.05, 1.0) var smoothness : float = 0.3

# --- Internal Variables ---
var _sync_timer : float = 0.0
var _target_pos : Vector3
var _target_rot : Vector3
var _last_sent_pos : Vector3

# Mapping the Enum selection to actual Hertz values
var _tick_map = {
	0: 10.0,
	1: 20.0,
	2: 30.0,
	3: 40.0,
	4: 50.0,
	5: 60.0,
	6: 120.0
}

func _ready() -> void:
	_target_pos = global_position
	_target_rot = global_rotation
	
	# Only run authority logic if the network is active
	if multiplayer.has_multiplayer_peer():
		if not is_multiplayer_authority():
			freeze = true 

func _physics_process(delta: float) -> void:
	# --- THE FIX ---
	# If the game is just starting or offline, don't run network checks
	if not multiplayer.has_multiplayer_peer():
		return
	# ----------------
	
	if is_multiplayer_authority():
		_handle_authority_send(delta)
	else:
		_handle_client_interpolation()

func _handle_authority_send(delta: float) -> void:
	_sync_timer += delta
	var target_hertz = _tick_map.get(tick_rate, 20.0)
	
	if _sync_timer >= (1.0 / target_hertz):
		# OPTIMIZATION: Only send if it moved or is awake
		if global_position.distance_to(_last_sent_pos) > 0.001 or not sleeping:
			rpc("_receive_sync_data", global_position, global_rotation)
			_last_sent_pos = global_position
		
		_sync_timer = 0.0

func _handle_client_interpolation() -> void:
	# Smoothly slide the object to the last known network position
	global_position = global_position.lerp(_target_pos, smoothness)
	
	# Smoothly rotate all axes using lerp_angle to handle 360-degree wrapping
	global_rotation.x = lerp_angle(global_rotation.x, _target_rot.x, smoothness)
	global_rotation.y = lerp_angle(global_rotation.y, _target_rot.y, smoothness)
	global_rotation.z = lerp_angle(global_rotation.z, _target_rot.z, smoothness)

@rpc("any_peer", "unreliable")
func _receive_sync_data(pos: Vector3, rot: Vector3) -> void:
	_target_pos = pos
	_target_rot = rot
