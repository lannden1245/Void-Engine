@tool
extends AudioStreamPlayer3D

enum TickRate { 
	Ticks_10HZ = 10, Ticks_20HZ = 20, Ticks_30HZ = 30, 
	Ticks_40HZ = 40, Ticks_50HZ = 50, Ticks_60HZ = 60, Ticks_120HZ = 120 
}

@export_group("Network & Performance")
@export var sync_tick_rate: TickRate = TickRate.Ticks_30HZ
@export var anti_drift: bool = true

@export_group("Occlusion Settings")
@export var occlusion_mask: int = 1
@export var ray_count: int = 5
@export var ray_spread: float = 1.0
## How fast the audio adapts to changes. Lower is more natural/delayed. (0.05 - 0.15)
@export_range(0.01, 0.5) var smooth_speed: float = 0.1

@export_group("Realism Customization")
## Lowest frequency when fully occluded (Hz)
@export var min_cutoff: float = 400.0 
## How much turning your head away muffles the sound (0.0 to 1.0)
@export_range(0.0, 1.0) var head_muffle_strength: float = 0.4
## Max volume drop (dB) when sound is behind/beside you
@export_range(0.0, 15.0) var max_volume_dip: float = 6.0
## 1.0 is Linear. 0.5 makes muffling feel "thicker" and more organic.
@export_range(0.1, 2.0) var occlusion_curve: float = 0.6

var filter: AudioEffectLowPassFilter
var bus_idx: int
var _tick_timer: float = 0.0
var _drift_timer: float = 0.0

# Interpolation Targets
var _target_cutoff: float = 20500.0
var _target_db: float = 0.0

func _ready():
	_create_custom_audio_stack()
	if Engine.is_editor_hint(): return
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		multiplayer.peer_connected.connect(_on_peer_connected)

func _physics_process(delta):
	if Engine.is_editor_hint(): return
	
	# Smoothly interpolate values every frame for "Natural" feel
	filter.cutoff_hz = lerp(filter.cutoff_hz, _target_cutoff, smooth_speed)
	self.volume_db = lerp(self.volume_db, _target_db, smooth_speed)
	
	if not multiplayer.has_multiplayer_peer(): return
	
	_tick_timer += delta
	if _tick_timer >= (1.0 / float(sync_tick_rate)):
		_update_audio_logic()
		_tick_timer = 0.0
		
		if anti_drift and is_multiplayer_authority() and playing:
			_drift_timer += (1.0 / float(sync_tick_rate))
			if _drift_timer >= 5.0:
				rpc("sync_timestamp", get_playback_position())
				_drift_timer = 0.0

func _create_custom_audio_stack():
	var bus_name = "VoidBus_" + str(get_instance_id())
	bus_idx = AudioServer.bus_count
	AudioServer.add_bus(bus_idx)
	AudioServer.set_bus_name(bus_idx, bus_name)
	AudioServer.set_bus_send(bus_idx, "Master") 
	filter = AudioEffectLowPassFilter.new()
	AudioServer.add_bus_effect(bus_idx, filter)
	self.bus = bus_name

func _update_audio_logic():
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	var space_state = get_world_3d().direct_space_state
	
	# 1. POSITIONAL MATH
	var to_source = (global_position - camera.global_position).normalized()
	var side_dot = camera.global_transform.basis.x.dot(to_source)
	var forward_dot = (-camera.global_transform.basis.z).dot(to_source)

	# 2. RAYCAST OCCLUSION
	var hits: float = 0.0
	for i in range(ray_count):
		var offset = camera.global_transform.basis.x * (i - (ray_count/2.0)) * ray_spread
		var query = PhysicsRayQueryParameters3D.create(global_position, camera.global_position + offset)
		query.collision_mask = occlusion_mask
		if space_state.intersect_ray(query): hits += 1.0
	var env_occlusion = hits / float(ray_count)

	# 3. CALCULATE NATURAL BIAS
	# Muffle based on environment + head orientation (if sound is behind)
	var back_bias = clamp(1.0 - forward_dot, 0.0, 1.0) * 0.5
	var side_bias = abs(side_dot) * head_muffle_strength
	
	var combined_factor = clamp(env_occlusion + back_bias + side_bias, 0.0, 1.0)
	
	# Apply Curve for organic falloff
	combined_factor = pow(combined_factor, occlusion_curve)

	# Set Targets (Interpolated in _physics_process)
	_target_cutoff = lerp(20500.0, min_cutoff, combined_factor)
	_target_db = lerp(0.0, -max_volume_dip, combined_factor * 0.8 + abs(side_dot) * 0.2)
	
	# Panning remains snappy but follows dot
	self.panning_strength = lerp(1.0, 2.5, abs(side_dot))

# --- NETWORKING ---

func _on_peer_connected(id: int):
	if playing: rpc_id(id, "sync_full_start", stream.resource_path, get_playback_position())

@rpc("authority", "call_remote", "reliable")
func sync_full_start(path: String, pos: float):
	if self.stream == null or self.stream.resource_path != path: self.stream = load(path)
	self.play(pos)

@rpc("any_peer", "unreliable")
func sync_timestamp(pos: float):
	if abs(get_playback_position() - pos) > 0.15: seek(pos)

func play_synced(from_pos: float = 0.0):
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("sync_full_start", stream.resource_path, from_pos)
	self.play(from_pos)

func _exit_tree():
	if bus_idx > 0: AudioServer.remove_bus(bus_idx)
