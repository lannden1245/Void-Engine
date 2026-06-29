extends AnimationPlayer

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
## Choose how often to sync animation timestamps.
## 20-30Hz is great for general animations. 60Hz+ for precision logic.
@export var sync_tick_rate: TickRate = TickRate.Ticks_30HZ
## Periodically forces everyone to the same animation frame to prevent drift.
@export var anti_drift: bool = true

var _tick_timer: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint(): return
	
	if multiplayer.has_multiplayer_peer():
		if is_multiplayer_authority():
			multiplayer.peer_connected.connect(_on_peer_connected)

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if not multiplayer.has_multiplayer_peer(): return

	# --- TICK RATE LOGIC ---
	var interval = 1.0 / float(sync_tick_rate)
	_tick_timer += delta
	
	if _tick_timer >= interval:
		if anti_drift and is_multiplayer_authority() and is_playing():
			# Send timestamp to everyone
			rpc("_receive_animation_drift_sync", current_animation, active, current_animation_position)
		_tick_timer = 0.0

# --- TRIGGER FUNCTIONS ---

func play_synced(anim_name: String, custom_speed: float = 1.0, from_end: bool = false):
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("_receive_animation_play", anim_name, custom_speed, from_end)
	self.play(anim_name, -1, custom_speed, from_end)

func stop_synced(keep_state: bool = false):
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		rpc("_receive_animation_stop", keep_state)
	self.stop(keep_state)

# --- RPC RECEIVERS ---

@rpc("any_peer", "call_remote", "reliable")
func _receive_animation_play(anim_name: String, speed: float, from_end: bool):
	self.play(anim_name, -1, speed, from_end)

@rpc("any_peer", "call_remote", "reliable")
func _receive_animation_stop(keep_state: bool):
	self.stop(keep_state)

@rpc("any_peer", "call_remote", "unreliable")
func _receive_animation_drift_sync(anim_name: String, is_playing_now: bool, pos: float):
	# Safety: Ignore if node isn't ready
	if not is_inside_tree() or anim_name == "": return
	
	if anim_name != current_animation:
		self.play(anim_name)
	
	# Only seek if the difference is noticeable (> 0.1s)
	if abs(current_animation_position - pos) > 0.1:
		seek(pos, true)

# --- LATE JOINER HANDSHAKE ---

func _on_peer_connected(id: int):
	# Identify which animation to sync
	var anim_to_sync = current_animation if current_animation != "" else assigned_animation
	
	# ONLY send if we actually have an animation name (Fixes your red error)
	if anim_to_sync != "" and anim_to_sync != null:
		rpc_id(id, "_receive_animation_drift_sync", anim_to_sync, is_playing(), current_animation_position)
