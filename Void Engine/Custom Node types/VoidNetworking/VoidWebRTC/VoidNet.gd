extends Node3D
# ============================================================
# SIGNALS
# ============================================================
signal server_started(protocol: String, mode: String, port: int, ip: String, code: String)
signal server_stopped()
signal client_connected_to_server()
signal client_failed_to_connect(reason: String)
signal client_disconnected_from_server()
signal player_spawned(id: int, is_local: bool)
signal player_despawned(id: int)
signal peer_joined(id: int)
signal peer_left(id: int)
signal peer_kicked(id: int, reason: String)
signal error_occurred(message: String)

signal server_browser_updated(lobbies: Array)
signal host_migration_triggered(new_host_id: int, is_me: bool)

# --- LOBBY / MATCH SIGNALS ---
signal lobby_joined(code: String, is_host: bool)
signal lobby_left()
signal lobby_updated(code: String, peers: Dictionary, mode: String, in_match: bool)
signal match_started(mode: String)
signal match_ended(mode: String)

# ============================================================
# ENUMS
# ============================================================
enum TransportProtocol { ENET, WEBRTC }
enum HostingMode { LOCAL_ONLY, LAN, ONLINE_UPNP, ONLINE_MANUAL }
enum NetworkState { OFFLINE, HOSTING, CONNECTING, CONNECTED, MIGRATING }

# ============================================================
# EXPORTS
# ============================================================
@export_group("Protocol Switches")
@export var transport_protocol: TransportProtocol = TransportProtocol.ENET
@export var hosting_mode: HostingMode = HostingMode.LAN
@export var port: int = 9991
@export var max_clients: int = 32
@export var connection_timeout_ms: int = 5000

@export_group("Advanced Side Options")
@export var enable_server_browser: bool = true
@export var auto_refresh_interval: float = 5.0
var enable_host_migration: bool = false
@export var server_lobby_name: String = "Godot Universal Server"
@export var is_private_lobby: bool = false
@export_range(0.5, 10.0, 0.1) var shutdown_delay_seconds: float = 3.0

@export_group("Security & Encryption Engine")
@export var enable_encryption: bool = true
@export var encryption_passphrase: String = "vOid_uNivErsAl_sEcrEt_pAssphrAsE_256bit"

@export_group("Multi-Region Firebase Engine")
@export var firebase_region_urls: PackedStringArray = [
	"https://your-primary-us-rtdb.firebaseio.com",
	"https://your-backup-eu-rtdb.firebaseio.com",
	"https://your-fallback-asia-rtdb.firebaseio.com"
]
@export var firebase_region_names: PackedStringArray = [
	"US East (Primary)",
	"Europe (Backup)",
	"Asia (Fallback)"
]
@export var stun_server_url: String = "stun:stun.l.google.com:19302"
@export_range(0.2, 2.0, 0.1) var firebase_poll_rate: float = 0.5
@export var enable_auto_fallback: bool = true

@export_group("Server Limits")
@export var enable_compression: bool = true
@export var allocate_channels: int = 2

@export_group("Debug & Trace")
@export var verbose_logging: bool = true

@export_group("UI & Scene References")
@export var player_scene: PackedScene
@export var spawn_node: Node
@export var player_spawn: Node3D
@export var address_entry: LineEdit
@export var game_code_label: Label
@export var status_label: Label
@export var peer_list_label: Label
@export var lobby_info_label: Label
@export var online_count_label: Label

@export var host_button: Button
@export var join_button: Button
@export var disconnect_button: Button
@export var matchmake_button: Button
@export var server_browser_list: ItemList

@export var username_entry: LineEdit
@export var lobby_name_entry: LineEdit
@export var private_lobby_checkbox: CheckBox
@export var region_dropdown: OptionButton
@export var chat_display: RichTextLabel
@export var chat_input: LineEdit
@export var chat_send_button: Button

@export_group("Lobby System")
@export var enable_lobby_system: bool = true
@export var enable_match_timer: bool = false
@export_range(5.0, 3600.0, 1.0) var match_duration_seconds: float = 120.0
@export var main_menu_panel: Control
@export var lobby_root: Control
@export var lobby_player_list: Label
@export var lobby_player_item_list: ItemList
@export var lobby_mode_picker: OptionButton
@export var lobby_mode_label: Label
@export var lobby_code_label: Label
@export var lobby_start_button: Button
@export var lobby_leave_button: Button
@export var lobby_status_label: Label
@export var match_timer_label: Label
@export var start_match_button: Button

@export_group("Mode System")
@export var mode_dropdown: OptionButton
@export var mode_filter_dropdown: OptionButton
@export var game_modes: PackedStringArray = [
	"Classic",
	"Free For All",
	"Team Deathmatch",
	"Hide & Seek",
	"Casual"
]
@export var game_modes_enabled: Array[bool] = [true, true, true, true, true]

# ============================================================
# INTERNAL STATE
# ============================================================
var current_state: NetworkState = NetworkState.OFFLINE
var connected_peers: Dictionary = {}
var local_player_id: int = 0
var local_username: String = ""
var public_ip_cache: String = ""
var _connection_timer: SceneTreeTimer = null

var active_firebase_url: String = ""
var current_region_index: int = 0

var current_lobby_code: String = "OFFLINE"
var current_player_count: int = 0
var total_players_online: int = 0
var _online_count_acc: float = 0.0

var selected_game_mode: String = "Classic"
var browser_mode_filter: String = "All Modes"
var match_in_progress: bool = false
var _match_timer_acc: float = 0.0

var enet_peer: ENetMultiplayerPeer = null
var webrtc_peer: WebRTCMultiplayerPeer = null

var udp_broadcaster: PacketPeerUDP = null
var udp_listener: PacketPeerUDP = null
var _udp_broadcast_timer: float = 0.0

var upnp: Object = null

var webrtc_peers_map: Dictionary = {}
var webrtc_client_id: int = 0
var _remote_desc_set: Dictionary = {}
var _orphaned_candidates: Dictionary = {}

var _firebase_poll_acc: float = 0.0
var _is_polling_firebase: bool = false

var _cached_browser_lobbies: Array = []
var _is_browsing_lan: bool = false
var _auto_refresh_acc: float = 0.0
var _is_evicting: bool = false
var _is_quitting: bool = false

# ============================================================
# OUTPUT
# ============================================================
func _debug_print(msg: String) -> void:
	if verbose_logging:
		print(msg)

func safe_print(msg: String) -> void:
	_debug_print("[NET] " + msg.strip_edges())

func _log(msg: String) -> void:
	if verbose_logging:
		safe_print(msg)

# ============================================================
# HELPERS — MODE PERMISSIONS
# ============================================================
# Lobby system: WebRTC OR ENet-LAN only.
func _lobby_allowed() -> bool:
	if transport_protocol == TransportProtocol.WEBRTC:
		return true
	if transport_protocol == TransportProtocol.ENET and hosting_mode == HostingMode.LAN:
		return true
	return false

# Server browser + matchmaking: WebRTC OR ENet-LAN only.
func _browser_allowed() -> bool:
	if transport_protocol == TransportProtocol.WEBRTC:
		return true
	if transport_protocol == TransportProtocol.ENET and hosting_mode == HostingMode.LAN:
		return true
	return false

func _is_mode_enabled(index: int) -> bool:
	if index < 0 or index >= game_modes.size():
		return false
	if index >= game_modes_enabled.size():
		return true
	return game_modes_enabled[index]

func _get_enabled_modes() -> PackedStringArray:
	var result := PackedStringArray()
	for i in range(game_modes.size()):
		if _is_mode_enabled(i):
			result.append(game_modes[i])
	return result

func _passes_mode_filter(lobby_mode: String) -> bool:
	return browser_mode_filter == "All Modes" or browser_mode_filter == "" or lobby_mode == browser_mode_filter

# Stable auth context: host & client MUST compute identical HMAC.
func _get_auth_context() -> String:
	if transport_protocol == TransportProtocol.WEBRTC:
		if current_lobby_code != "" and current_lobby_code != "OFFLINE":
			return current_lobby_code
		return "WEBRTC"
	# ENet: passphrase is the shared secret; constant keeps HMAC consistent.
	return "ENET_SHARED"

func _bytes_to_string(bytes: PackedByteArray) -> String:
	var clean := PackedByteArray()
	for b in bytes:
		if b != 0:
			clean.append(b)
	return clean.get_string_from_utf8()

func _despawn_all_player_nodes() -> void:
	if spawn_node == null:
		return
	var ids_to_remove: Array[int] = []
	for child in spawn_node.get_children():
		var node_name := String(child.name)
		if node_name.is_valid_int():
			ids_to_remove.append(node_name.to_int())
	for id in ids_to_remove:
		_despawn_player(id)

func _reset_match_world_state() -> void:
	_despawn_all_player_nodes()
	if get_tree():
		for node in get_tree().get_nodes_in_group("match_resettable"):
			if is_instance_valid(node) and node.has_method("reset_match_state"):
				node.call_deferred("reset_match_state")

# ============================================================
# AES / SECURITY
# ============================================================
func _secure_seal_payload(data_dict: Dictionary) -> String:
	var json_str := JSON.stringify(data_dict)
	if not enable_encryption:
		return json_str
	var key := encryption_passphrase.sha256_buffer()
	var aes := AESContext.new()
	aes.start(AESContext.MODE_ECB_ENCRYPT, key)
	var buffer := json_str.to_utf8_buffer()
	var padding := 16 - (buffer.size() % 16)
	if padding == 0:
		padding = 16
	for _i in range(padding):
		buffer.append(padding)
	var encrypted := aes.update(buffer)
	aes.finish()
	return Marshalls.raw_to_base64(encrypted)

func _secure_unseal_payload(base64_str: String) -> Dictionary:
	if not enable_encryption or base64_str.begins_with("{"):
		var json_parser := JSON.new()
		if json_parser.parse(base64_str) == OK and json_parser.data is Dictionary:
			return json_parser.data
		return {}
	var encrypted := Marshalls.base64_to_raw(base64_str)
	if encrypted.is_empty():
		return {}
	var key := encryption_passphrase.sha256_buffer()
	var aes := AESContext.new()
	aes.start(AESContext.MODE_ECB_DECRYPT, key)
	var decrypted := aes.update(encrypted)
	aes.finish()
	if decrypted.is_empty():
		return {}
	var padding := int(decrypted[decrypted.size() - 1])
	if padding <= 0 or padding > 16 or padding > decrypted.size():
		return {}
	var clean := decrypted.slice(0, decrypted.size() - padding)
	var json_parser := JSON.new()
	if json_parser.parse(clean.get_string_from_utf8()) == OK and json_parser.data is Dictionary:
		return json_parser.data
	return {}

func _generate_auth_hmac(target_id: int) -> String:
	var raw := "%d|%s|%s" % [target_id, _get_auth_context(), encryption_passphrase]
	return raw.sha256_text()

# ============================================================
# READY / PROCESS
# ============================================================
func _ready() -> void:
	randomize()
	get_tree().set_auto_accept_quit(false)

	if OS.has_feature("web") and transport_protocol != TransportProtocol.WEBRTC:
		_debug_print("[NET ALERT] HTML5 detected. Forcing WebRTC.")
		transport_protocol = TransportProtocol.WEBRTC

	if firebase_region_urls.size() > 0:
		_set_active_firebase_region(0)
	else:
		active_firebase_url = "https://your-project-default-rtdb.firebaseio.com"

	if region_dropdown:
		region_dropdown.clear()
		for i in range(firebase_region_urls.size()):
			var r_disp := firebase_region_names[i] if i < firebase_region_names.size() else ("Region " + str(i + 1))
			region_dropdown.add_item(r_disp + "  [Pinging...]")
		if not region_dropdown.item_selected.is_connected(_on_region_selected):
			region_dropdown.item_selected.connect(_on_region_selected)
		_measure_region_pings()

	if host_button and not host_button.pressed.is_connected(start_host):
		host_button.pressed.connect(start_host)
	if join_button and not join_button.pressed.is_connected(start_client):
		join_button.pressed.connect(start_client)
	if matchmake_button and not matchmake_button.pressed.is_connected(quick_matchmake):
		matchmake_button.pressed.connect(quick_matchmake)
	if disconnect_button and not disconnect_button.pressed.is_connected(_on_disconnect_pressed):
		disconnect_button.pressed.connect(_on_disconnect_pressed)
	if server_browser_list and not server_browser_list.item_activated.is_connected(_on_browser_list_item_double_clicked):
		server_browser_list.item_activated.connect(_on_browser_list_item_double_clicked)
	if chat_send_button and not chat_send_button.pressed.is_connected(broadcast_chat_message):
		chat_send_button.pressed.connect(broadcast_chat_message)
	if chat_input and not chat_input.text_submitted.is_connected(_on_chat_submitted):
		chat_input.text_submitted.connect(_on_chat_submitted)
	if start_match_button and not start_match_button.pressed.is_connected(start_match):
		start_match_button.pressed.connect(start_match)
	if lobby_start_button and not lobby_start_button.pressed.is_connected(start_match):
		lobby_start_button.pressed.connect(start_match)
	if lobby_leave_button and not lobby_leave_button.pressed.is_connected(_on_disconnect_pressed):
		lobby_leave_button.pressed.connect(_on_disconnect_pressed)

	_setup_lobby_mode_ui()

	_set_status("Offline")
	_update_ui_displays()
	_update_ui_visibility()
	_update_match_timer_display()
	_update_live_player_count()

	_debug_print("[NET] Network Engine Initialized.")

	if enable_server_browser:
		refresh_server_browser()

func _process(delta: float) -> void:
	match transport_protocol:
		TransportProtocol.WEBRTC:
			for peer_id in webrtc_peers_map.keys():
				var pc: WebRTCPeerConnection = webrtc_peers_map[peer_id]
				if pc:
					pc.poll()
			if webrtc_peer:
				webrtc_peer.poll()
		TransportProtocol.ENET:
			pass

	if enable_server_browser and _browser_allowed() and current_state == NetworkState.OFFLINE:
		_auto_refresh_acc += delta
		if _auto_refresh_acc >= auto_refresh_interval:
			_auto_refresh_acc = 0.0
			refresh_server_browser()
			if transport_protocol == TransportProtocol.WEBRTC:
				_measure_region_pings()

	if transport_protocol == TransportProtocol.ENET:
		if udp_broadcaster and current_state == NetworkState.HOSTING and not is_private_lobby:
			_udp_broadcast_timer += delta
			if _udp_broadcast_timer >= 1.0:
				_udp_broadcast_timer = 0.0
				var beacon := "ENET_BEACON|" + current_lobby_code + "|" + server_lobby_name + "|" + str(current_player_count) + "|" + str(max_clients)
				udp_broadcaster.put_packet(beacon.to_utf8_buffer())

		if udp_listener:
			while udp_listener.get_available_packet_count() > 0:
				var pkt := _bytes_to_string(udp_listener.get_packet())
				if pkt.begins_with("ENET_BEACON|"):
					var parts := pkt.split("|")
					var discovered_code := parts[1]
					if _is_browsing_lan:
						var s_name := parts[2] if parts.size() > 2 else "LAN Server"
						var p_cnt := parts[3] if parts.size() > 3 else "1"
						var m_cnt := parts[4] if parts.size() > 4 else str(max_clients)
						var exists := false
						for entry in _cached_browser_lobbies:
							if entry["id"] == discovered_code:
								exists = true
								break
						if not exists:
							_cached_browser_lobbies.append({
								"id": discovered_code,
								"name": s_name,
								"players": p_cnt.to_int(),
								"max_players": m_cnt.to_int(),
								"ping": 1
							})
							if server_browser_list:
								server_browser_list.add_item("[LAN] %s   (Players: %s/%s)   [Ping: <1 ms]" % [s_name, p_cnt, m_cnt])
							_set_status("Found %d LAN Server(s)" % _cached_browser_lobbies.size())
							_recount_global_players()
							emit_signal("server_browser_updated", _cached_browser_lobbies)
					elif current_state == NetworkState.CONNECTING:
						_debug_print("[UDP DISCOVERY] Found LAN host beacon: " + discovered_code)
						udp_listener.close()
						udp_listener = null
						_execute_enet_connection(discovered_code)
						return

	if transport_protocol == TransportProtocol.WEBRTC:
		if current_state in [NetworkState.HOSTING, NetworkState.CONNECTING, NetworkState.CONNECTED]:
			_firebase_poll_acc += delta
			if _firebase_poll_acc >= firebase_poll_rate:
				_firebase_poll_acc = 0.0
				if not _is_polling_firebase:
					_poll_firebase_inbox()

	if _lobby_allowed() and match_in_progress and enable_match_timer:
		if _match_timer_acc > 0.0:
			_match_timer_acc = maxf(_match_timer_acc - delta, 0.0)
			_update_match_timer_display()
			if _match_timer_acc <= 0.0 and multiplayer.is_server():
				end_match()

	_online_count_acc += delta
	if _online_count_acc >= 0.5:
		_online_count_acc = 0.0
		_update_live_player_count()

# ============================================================
# WINDOW CLOSE
# ============================================================
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_debug_print("[NET EMERGENCY] Close request intercepted.")
		_is_quitting = true
		_is_browsing_lan = false
		if udp_listener:
			udp_listener.close()
			udp_listener = null
		if current_state == NetworkState.HOSTING:
			stop_host()
		elif current_state in [NetworkState.CONNECTED, NetworkState.CONNECTING]:
			disconnect_client()
		get_tree().create_timer(shutdown_delay_seconds).timeout.connect(func() -> void:
			get_tree().quit()
		)

# ============================================================
# REGION / MODE / LOBBY UI
# ============================================================
func _measure_region_pings() -> void:
	if not region_dropdown or firebase_region_urls.is_empty() or transport_protocol != TransportProtocol.WEBRTC:
		return
	for i in range(firebase_region_urls.size()):
		var idx := i
		var raw_url := firebase_region_urls[idx].strip_edges()
		if raw_url.ends_with("/"):
			raw_url = raw_url.substr(0, raw_url.length() - 1)
		var ping_http := HTTPRequest.new()
		add_child(ping_http)
		var start_time := Time.get_ticks_msec()
		var test_url := raw_url + "/.json?shallow=true"
		ping_http.request_completed.connect(func(res, code, _h, _b) -> void:
			var latency := Time.get_ticks_msec() - start_time
			var r_disp := firebase_region_names[idx] if idx < firebase_region_names.size() else ("Region " + str(idx + 1))
			if region_dropdown and idx < region_dropdown.item_count:
				if res == HTTPRequest.RESULT_SUCCESS and code == 200:
					region_dropdown.set_item_text(idx, "%s  [Ping: %d ms]" % [r_disp, latency])
				else:
					region_dropdown.set_item_text(idx, "%s  [ERR / OVERLOADED]" % r_disp)
			ping_http.queue_free()
		)
		ping_http.request(test_url)

func _set_active_firebase_region(index: int) -> void:
	if index < 0 or index >= firebase_region_urls.size():
		return
	current_region_index = index
	var raw_url := firebase_region_urls[index].strip_edges()
	if raw_url.ends_with("/"):
		raw_url = raw_url.substr(0, raw_url.length() - 1)
	active_firebase_url = raw_url
	var r_disp := firebase_region_names[index] if index < firebase_region_names.size() else ("Region " + str(index + 1))
	_debug_print("[NET DEBUG] Active Firebase Region: " + r_disp + " -> " + active_firebase_url)

func _on_region_selected(index: int) -> void:
	_set_active_firebase_region(index)
	_measure_region_pings()
	refresh_server_browser()

func _setup_lobby_mode_ui() -> void:
	var enabled := _get_enabled_modes()
	if enabled.size() > 0:
		selected_game_mode = enabled[0]
	if mode_dropdown:
		mode_dropdown.clear()
		for m in enabled:
			mode_dropdown.add_item(m)
		if enabled.size() > 0:
			mode_dropdown.select(0)
		if not mode_dropdown.item_selected.is_connected(_on_main_mode_selected):
			mode_dropdown.item_selected.connect(_on_main_mode_selected)
	if mode_filter_dropdown:
		mode_filter_dropdown.clear()
		mode_filter_dropdown.add_item("All Modes")
		for m in enabled:
			mode_filter_dropdown.add_item(m)
		mode_filter_dropdown.select(0)
		if not mode_filter_dropdown.item_selected.is_connected(_on_filter_mode_selected):
			mode_filter_dropdown.item_selected.connect(_on_filter_mode_selected)
	if lobby_mode_picker:
		lobby_mode_picker.clear()
		for m in enabled:
			lobby_mode_picker.add_item(m)
		if enabled.size() > 0:
			lobby_mode_picker.select(0)
		if not lobby_mode_picker.item_selected.is_connected(_on_lobby_mode_selected):
			lobby_mode_picker.item_selected.connect(_on_lobby_mode_selected)

func _on_main_mode_selected(index: int) -> void:
	var enabled := _get_enabled_modes()
	if index >= 0 and index < enabled.size():
		selected_game_mode = enabled[index]
		if lobby_mode_picker and index < lobby_mode_picker.item_count:
			lobby_mode_picker.select(index)
		_refresh_lobby_ui()
		_update_ui_displays()

func _on_filter_mode_selected(index: int) -> void:
	var enabled := _get_enabled_modes()
	if index == 0:
		browser_mode_filter = "All Modes"
	elif index - 1 >= 0 and index - 1 < enabled.size():
		browser_mode_filter = enabled[index - 1]
	refresh_server_browser()

func _on_lobby_mode_selected(index: int) -> void:
	var enabled := _get_enabled_modes()
	if index < 0 or index >= enabled.size():
		return
	selected_game_mode = enabled[index]
	if mode_dropdown and index < mode_dropdown.item_count:
		mode_dropdown.select(index)
	if _lobby_allowed() and multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_sync_selected_mode.rpc(selected_game_mode)
		_broadcast_lobby_state()
	_refresh_lobby_ui()
	_update_ui_displays()

func _refresh_lobby_ui() -> void:
	if lobby_mode_label:
		lobby_mode_label.text = "Mode: " + selected_game_mode
	if lobby_code_label:
		lobby_code_label.text = "Code: " + current_lobby_code
	if lobby_player_list:
		var lines: Array[String] = []
		for id_variant in connected_peers.keys():
			var peer_id := int(id_variant)
			var nm := str(connected_peers[peer_id].get("name", "Player " + str(peer_id)))
			var tag := " [HOST]" if peer_id == 1 else ""
			lines.append("• " + nm + tag)
		lobby_player_list.text = "\n".join(lines) if lines.size() > 0 else "Waiting for players..."
	if lobby_player_item_list:
		lobby_player_item_list.clear()
		for id_variant in connected_peers.keys():
			var peer_id := int(id_variant)
			var nm := str(connected_peers[peer_id].get("name", "Player " + str(peer_id)))
			var tag := " [HOST]" if peer_id == 1 else ""
			lobby_player_item_list.add_item(nm + tag)
			var item_idx := lobby_player_item_list.item_count - 1
			lobby_player_item_list.set_item_metadata(item_idx, peer_id)
	var is_host := current_state == NetworkState.HOSTING
	if lobby_start_button:
		lobby_start_button.visible = _lobby_allowed() and is_host and not match_in_progress
	if start_match_button:
		start_match_button.visible = _lobby_allowed() and is_host and not match_in_progress
	if lobby_mode_picker:
		lobby_mode_picker.disabled = not is_host or match_in_progress
	if lobby_status_label:
		if not _lobby_allowed():
			lobby_status_label.text = "Direct-connect mode."
		elif is_host:
			lobby_status_label.text = "You are the host. Pick a mode and start the match."
		else:
			lobby_status_label.text = "Waiting for host to start the match..."

func _update_ui_visibility() -> void:
	var connected := current_state in [NetworkState.HOSTING, NetworkState.CONNECTED]
	var show_lobby := _lobby_allowed() and enable_lobby_system and connected and not match_in_progress
	if main_menu_panel:
		main_menu_panel.visible = current_state == NetworkState.OFFLINE
	if lobby_root:
		lobby_root.visible = show_lobby
	if match_timer_label:
		match_timer_label.visible = _lobby_allowed() and match_in_progress and enable_match_timer
	_refresh_lobby_ui()

func _update_match_timer_display() -> void:
	if not match_timer_label:
		return
	if match_in_progress and enable_match_timer:
		var secs := int(ceil(_match_timer_acc))
		var mm := int(secs / 60.0)
		var ss := int(secs % 60)
		match_timer_label.text = "Time: %02d:%02d" % [mm, ss]
	else:
		match_timer_label.text = ""

# ============================================================
# DISPLAY
# ============================================================
func _set_status(txt: String) -> void:
	if status_label:
		status_label.text = "Status: " + txt

func _error(msg: String) -> void:
	var clean := msg.strip_edges()
	_debug_print("[NET ALERT] " + clean)
	_set_status(clean)
	emit_signal("error_occurred", clean)

func _recount_global_players() -> void:
	total_players_online = 0
	for lobby in _cached_browser_lobbies:
		total_players_online += int(lobby.get("players", 0))
	if online_count_label:
		online_count_label.text = "%d Players Online   |   %d Lobbies" % [
			total_players_online,
			_cached_browser_lobbies.size()
		]

func _update_live_player_count() -> void:
	if current_state in [NetworkState.HOSTING, NetworkState.CONNECTED]:
		total_players_online = connected_peers.size()
		if online_count_label:
			if _lobby_allowed():
				var state_label := "Players in Match" if match_in_progress else "Players in Lobby"
				online_count_label.text = "%d %s   |   Mode: %s" % [
					total_players_online,
					state_label,
					selected_game_mode
				]
			else:
				online_count_label.text = "%d Players Connected   |   Direct Mode" % [
					total_players_online
				]
	else:
		_recount_global_players()

func _update_ui_displays() -> void:
	current_player_count = connected_peers.size() if current_state != NetworkState.OFFLINE else 0
	if game_code_label:
		if current_state != NetworkState.OFFLINE:
			var mode_label := "Firebase WebRTC" if transport_protocol == TransportProtocol.WEBRTC else (("LAN Lobby" if hosting_mode == HostingMode.LAN else ("Worldwide Lobby" if hosting_mode in [HostingMode.ONLINE_UPNP, HostingMode.ONLINE_MANUAL] else "Localhost")))
			game_code_label.text = "%s: %s   (Players: %d/%d)" % [mode_label, current_lobby_code, current_player_count, max_clients]
		else:
			game_code_label.text = "Offline"
	if lobby_info_label:
		var state_text := "IN MATCH" if match_in_progress else ("IN LOBBY" if _lobby_allowed() else "DIRECT CONNECT")
		if current_state == NetworkState.OFFLINE:
			state_text = "OFFLINE"
		lobby_info_label.text = "Lobby Code: %s\nPlayers: %d / %d\nMode: %s\nState: %s" % [
			current_lobby_code,
			current_player_count,
			max_clients,
			selected_game_mode,
			state_text
		]
	if peer_list_label:
		var lines := ["  Active Links (" + str(connected_peers.size()) + "):"]
		for id in connected_peers.keys():
			var p_info: Dictionary = connected_peers[id]
			var p_name: String = p_info.get("name", "Player " + str(id))
			var tag := " [HOST]" if id == 1 else ""
			var rdy := " [OK]" if bool(p_info.get("ready", false)) else " [AUTH]"
			lines.append("  " + p_name + " (ID: " + str(id) + ")" + tag + rdy)
		peer_list_label.text = "\n".join(lines)
	_refresh_lobby_ui()
	_update_live_player_count()

func _validate_scene_references(is_host: bool) -> bool:
	if player_scene == null or spawn_node == null:
		_error("Missing structural inspector references.")
		return false
	if not is_host and address_entry == null:
		_error("Missing client address_entry reference.")
		return false
	return true

# ============================================================
# LOBBY BROADCAST
# ============================================================
func _broadcast_lobby_state() -> void:
	if not multiplayer.is_server():
		return
	_update_ui_displays()
	_refresh_lobby_ui()
	_receive_lobby_state.rpc(current_lobby_code, connected_peers)
	emit_signal("lobby_updated", current_lobby_code, connected_peers, selected_game_mode, match_in_progress)
	if transport_protocol == TransportProtocol.WEBRTC and current_lobby_code != "OFFLINE" and current_lobby_code != "":
		var update_http := HTTPRequest.new()
		add_child(update_http)
		update_http.request_completed.connect(func(_r, _c, _h, _b) -> void:
			update_http.queue_free()
		)
		var url := "%s/rooms/%s/info.json" % [active_firebase_url, current_lobby_code]
		var info_data := {
			"name": server_lobby_name,
			"players": current_player_count,
			"max": max_clients,
			"private": is_private_lobby,
			"mode": selected_game_mode
		}
		update_http.request.call_deferred(url, ["Content-Type: application/json"], HTTPClient.METHOD_PUT, JSON.stringify(info_data))

@rpc("authority", "call_remote", "reliable")
func _receive_lobby_state(synced_code: String, synced_peers: Dictionary) -> void:
	current_lobby_code = synced_code
	connected_peers = synced_peers
	_update_ui_displays()
	_refresh_lobby_ui()
	_update_ui_visibility()
	emit_signal("lobby_updated", current_lobby_code, connected_peers, selected_game_mode, match_in_progress)

# ============================================================
# CHAT
# ============================================================
func broadcast_chat_message() -> void:
	if current_state not in [NetworkState.HOSTING, NetworkState.CONNECTED]:
		return
	if not chat_input or chat_input.text.strip_edges() == "":
		return
	var clean_msg := chat_input.text.strip_edges()
	chat_input.text = ""
	var my_id := multiplayer.get_unique_id()
	var sender_label := local_username if local_username != "" else ("Host" if my_id == 1 else ("Player " + str(my_id)))
	receive_network_chat.rpc(my_id, sender_label, clean_msg)

@rpc("any_peer", "call_local", "reliable")
func receive_network_chat(sender_id: int, sender: String, message: String) -> void:
	var formatted_line := sender + ": " + message + "\n"
	if chat_display:
		chat_display.append_text(formatted_line)
	_debug_print("[IN-GAME CHAT] %s: %s" % [sender, message])
	if spawn_node:
		var avatar_node = spawn_node.get_node_or_null(str(sender_id))
		if avatar_node and avatar_node.has_method("show_chat_bubble"):
			avatar_node.show_chat_bubble(message)

func _on_chat_submitted(_new_text: String) -> void:
	broadcast_chat_message()

# ============================================================
# SERVER BROWSER / MATCHMAKING
# ============================================================
func refresh_server_browser() -> void:
	if not enable_server_browser:
		return
	if not _browser_allowed():
		if server_browser_list:
			server_browser_list.clear()
		_cached_browser_lobbies.clear()
		_recount_global_players()
		return
	_set_status("Refreshing Server List...")
	if server_browser_list:
		server_browser_list.clear()
	_cached_browser_lobbies.clear()
	_is_browsing_lan = false
	_recount_global_players()

	if transport_protocol == TransportProtocol.WEBRTC:
		var browse_start_ticks := Time.get_ticks_msec()
		var browse_http := HTTPRequest.new()
		add_child(browse_http)
		browse_http.timeout = 4.0
		browse_http.request_completed.connect(func(res, code, _h, body) -> void:
			var signaling_ping := Time.get_ticks_msec() - browse_start_ticks
			if res != HTTPRequest.RESULT_SUCCESS or code != 200:
				_debug_print("[NET FALLBACK ALERT] Firebase browser refresh failed. HTTP Code: " + str(code))
				if enable_auto_fallback and firebase_region_urls.size() > 1:
					var next_region := (current_region_index + 1) % firebase_region_urls.size()
					if region_dropdown:
						region_dropdown.select(next_region)
					_set_active_firebase_region(next_region)
				browse_http.queue_free()
				return
			var json_parser := JSON.new()
			if json_parser.parse(_bytes_to_string(body)) == OK and json_parser.data is Dictionary:
				var rooms: Dictionary = json_parser.data
				for room_code in rooms.keys():
					if str(room_code) == "OFFLINE":
						continue
					var room_obj: Dictionary = rooms[room_code]
					if room_obj.has("info") and room_obj["info"] is Dictionary:
						var info: Dictionary = room_obj["info"]
						if bool(info.get("private", false)):
							continue
						var s_name := str(info.get("name", "WebRTC Room"))
						var p_curr := int(info.get("players", 1))
						var p_max := int(info.get("max", max_clients))
						var lobby_mode := str(info.get("mode", "Classic"))
						if not _passes_mode_filter(lobby_mode):
							continue
						var exists := false
						for item in _cached_browser_lobbies:
							if item["id"] == str(room_code):
								exists = true
								break
						if not exists:
							var r_disp := firebase_region_names[current_region_index] if current_region_index < firebase_region_names.size() else ("R" + str(current_region_index + 1))
							_cached_browser_lobbies.append({
								"id": str(room_code),
								"name": s_name,
								"players": p_curr,
								"max_players": p_max,
								"ping": signaling_ping,
								"region": current_region_index,
								"mode": lobby_mode
							})
							if server_browser_list:
								server_browser_list.add_item("[%s] %s   <%s>   (Players: %d/%d)   [Ping: %d ms]" % [
									r_disp, s_name, lobby_mode, p_curr, p_max, signaling_ping
								])
			_set_status("Found %d WebRTC Room(s)" % _cached_browser_lobbies.size())
			_recount_global_players()
			emit_signal("server_browser_updated", _cached_browser_lobbies)
			browse_http.queue_free()
		)
		browse_http.request("%s/rooms.json" % active_firebase_url)
	elif transport_protocol == TransportProtocol.ENET and hosting_mode == HostingMode.LAN:
		_is_browsing_lan = true
		if udp_listener == null:
			udp_listener = PacketPeerUDP.new()
			udp_listener.bind(port + 5)
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			_is_browsing_lan = false
		)

func _on_browser_list_item_double_clicked(index: int) -> void:
	if index < 0 or index >= _cached_browser_lobbies.size():
		return
	var entry: Dictionary = _cached_browser_lobbies[index]
	if entry.has("region") and transport_protocol == TransportProtocol.WEBRTC:
		var region_idx := int(entry["region"])
		if region_dropdown:
			region_dropdown.select(region_idx)
		_set_active_firebase_region(region_idx)
	if entry.has("mode"):
		selected_game_mode = str(entry["mode"])
		var enabled := _get_enabled_modes()
		var mode_idx := enabled.find(selected_game_mode)
		if mode_dropdown and mode_idx >= 0 and mode_idx < mode_dropdown.item_count:
			mode_dropdown.select(mode_idx)
		if lobby_mode_picker and mode_idx >= 0 and mode_idx < lobby_mode_picker.item_count:
			lobby_mode_picker.select(mode_idx)
	if address_entry:
		address_entry.text = str(entry["id"])
	_is_browsing_lan = false
	if udp_listener and current_state != NetworkState.CONNECTING:
		udp_listener.close()
		udp_listener = null
	start_client()

func quick_matchmake() -> void:
	if not _browser_allowed():
		_error("Matchmaking is only available for WebRTC and ENet LAN.")
		return
	if current_state != NetworkState.OFFLINE:
		_error("Already running an active connection instance.")
		return
	var open_sessions := []
	for lobby in _cached_browser_lobbies:
		var current_p: int = lobby.get("players", 0)
		var max_p: int = lobby.get("max_players", max_clients)
		if current_p < max_p:
			open_sessions.append(lobby)
	if open_sessions.is_empty():
		_error("No available open lobbies found. Try refreshing or host a game!")
		return
	open_sessions.sort_custom(func(a, b) -> bool:
		return a.get("ping", 999999) < b.get("ping", 999999)
	)
	var perfect_match: Dictionary = open_sessions[0]
	if perfect_match.has("region") and transport_protocol == TransportProtocol.WEBRTC:
		if region_dropdown:
			region_dropdown.select(int(perfect_match["region"]))
		_set_active_firebase_region(int(perfect_match["region"]))
	if perfect_match.has("mode"):
		selected_game_mode = str(perfect_match["mode"])
	if address_entry:
		address_entry.text = str(perfect_match["id"])
	_is_browsing_lan = false
	if udp_listener and current_state != NetworkState.CONNECTING:
		udp_listener.close()
		udp_listener = null
	start_client()

# ============================================================
# HOST / CLIENT ENTRY
# ============================================================
func start_host() -> void:
	if current_state == NetworkState.HOSTING:
		_error("Already hosting session.")
		return
	if current_state != NetworkState.OFFLINE or not _validate_scene_references(true):
		return
	if username_entry and username_entry.text.strip_edges() != "":
		local_username = username_entry.text.strip_edges()
	else:
		local_username = "Host"
	if lobby_name_entry and lobby_name_entry.text.strip_edges() != "":
		server_lobby_name = lobby_name_entry.text.strip_edges()
	if private_lobby_checkbox:
		is_private_lobby = private_lobby_checkbox.button_pressed
	current_state = NetworkState.HOSTING
	local_player_id = 1
	_is_evicting = false
	match_in_progress = false
	_match_timer_acc = 0.0
	_register_peer(1, "127.0.0.1", local_username)
	connected_peers[1]["ready"] = true
	match transport_protocol:
		TransportProtocol.ENET:
			_start_enet_host()
		TransportProtocol.WEBRTC:
			_start_webrtc_host()
	_update_ui_visibility()
	_refresh_lobby_ui()
	if _lobby_allowed():
		emit_signal("lobby_joined", current_lobby_code, true)
		emit_signal("lobby_updated", current_lobby_code, connected_peers, selected_game_mode, match_in_progress)

func stop_host() -> void:
	if current_state != NetworkState.HOSTING:
		return
	_is_evicting = true
	kick_all_clients.rpc("Host intentionally closed the session.")
	if upnp and transport_protocol == TransportProtocol.ENET and hosting_mode == HostingMode.ONLINE_UPNP:
		upnp.call("delete_port_mapping", port, "UDP")
	if udp_broadcaster:
		udp_broadcaster.close()
		udp_broadcaster = null
	if _lobby_allowed():
		emit_signal("lobby_left")
	if transport_protocol == TransportProtocol.WEBRTC and current_lobby_code != "OFFLINE" and current_lobby_code != "":
		var url := "%s/rooms/%s.json" % [active_firebase_url, current_lobby_code]
		var http := HTTPRequest.new()
		add_child(http)
		var target_wipe_code := current_lobby_code
		_teardown_network()
		_set_status("Offline")
		emit_signal("server_stopped")
		http.request_completed.connect(func(_r, _c, _h, _b) -> void:
			_debug_print("[NET] Firebase room " + target_wipe_code + " deleted.")
			http.queue_free()
			if not _is_quitting:
				get_tree().reload_current_scene()
		)
		http.request(url, [], HTTPClient.METHOD_DELETE)
		return
	_teardown_network()
	_set_status("Offline")
	emit_signal("server_stopped")
	if not _is_quitting:
		get_tree().reload_current_scene()

func start_client() -> void:
	if current_state == NetworkState.HOSTING:
		_error("Already running hosting instance.")
		return
	if current_state != NetworkState.OFFLINE or not _validate_scene_references(false):
		return
	var raw_input := address_entry.text.strip_edges() if address_entry else ""
	current_state = NetworkState.CONNECTING
	_is_evicting = false
	match transport_protocol:
		TransportProtocol.ENET:
			_start_enet_client(raw_input)
		TransportProtocol.WEBRTC:
			_start_webrtc_client(raw_input)
	_connection_timer = get_tree().create_timer(connection_timeout_ms / 1000.0)
	_connection_timer.timeout.connect(_on_connection_timeout)

func disconnect_client() -> void:
	if current_state not in [NetworkState.CONNECTED, NetworkState.CONNECTING]:
		return
	if transport_protocol == TransportProtocol.WEBRTC and not _is_evicting and current_lobby_code != "" and current_lobby_code != "OFFLINE":
		_push_firebase_msg(1, { "type": "drop", "id": webrtc_client_id })
	if _lobby_allowed():
		emit_signal("lobby_left")
	_teardown_network()
	_set_status("Offline")
	emit_signal("client_disconnected_from_server")
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		if not _is_quitting:
			get_tree().reload_current_scene()
	)

func _on_disconnect_pressed() -> void:
	if current_state == NetworkState.HOSTING:
		stop_host()
	else:
		disconnect_client()

# ============================================================
# KICKS / MATCH
# ============================================================
func kick_peer(target_id: int, reason: String = "Kicked") -> void:
	if not multiplayer.is_server():
		return
	_receive_kick_alert.rpc_id(target_id, reason)
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		var mp := multiplayer.multiplayer_peer
		if mp != null and mp.has_method("disconnect_peer"):
			mp.disconnect_peer(target_id)
	)

@rpc("authority", "call_remote", "reliable")
func _receive_kick_alert(reason: String) -> void:
	_error("Disconnected: " + reason)
	emit_signal("peer_kicked", multiplayer.get_unique_id(), reason)
	_is_evicting = true
	disconnect_client()

func start_match() -> void:
	if not _lobby_allowed():
		_error("Lobby system is only used on WebRTC and ENet LAN.")
		return
	if not multiplayer.is_server():
		_error("Only the host can start the match.")
		return
	if match_in_progress:
		_error("Match already in progress.")
		return
	match_in_progress = true
	_match_timer_acc = match_duration_seconds if enable_match_timer else 0.0
	_receive_match_state.rpc(true, _match_timer_acc, selected_game_mode)
	_broadcast_lobby_state()
	for peer_id_variant in connected_peers.keys():
		var peer_id := int(peer_id_variant)
		spawn_player.rpc(peer_id)
	emit_signal("match_started", selected_game_mode)
	emit_signal("lobby_updated", current_lobby_code, connected_peers, selected_game_mode, match_in_progress)
	_update_ui_visibility()
	_update_match_timer_display()

func end_match() -> void:
	if not _lobby_allowed():
		return
	if not multiplayer.is_server():
		return
	if not match_in_progress:
		return
	match_in_progress = false
	_match_timer_acc = 0.0
	_receive_match_end.rpc()
	_broadcast_lobby_state()
	emit_signal("match_ended", selected_game_mode)
	emit_signal("lobby_updated", current_lobby_code, connected_peers, selected_game_mode, match_in_progress)
	_update_ui_visibility()
	_update_match_timer_display()

@rpc("authority", "call_remote", "reliable")
func _sync_selected_mode(mode_name: String) -> void:
	selected_game_mode = mode_name
	var enabled := _get_enabled_modes()
	var idx := enabled.find(mode_name)
	if mode_dropdown and idx >= 0 and idx < mode_dropdown.item_count:
		mode_dropdown.select(idx)
	if lobby_mode_picker and idx >= 0 and idx < lobby_mode_picker.item_count:
		lobby_mode_picker.select(idx)
	_refresh_lobby_ui()
	_update_ui_displays()

@rpc("authority", "call_local", "reliable")
func _receive_match_state(in_progress: bool, duration: float, mode_name: String) -> void:
	match_in_progress = in_progress
	selected_game_mode = mode_name
	_match_timer_acc = duration if in_progress else 0.0
	if in_progress:
		_reset_match_world_state()
	_update_ui_visibility()
	_update_match_timer_display()
	_refresh_lobby_ui()
	emit_signal("lobby_updated", current_lobby_code, connected_peers, selected_game_mode, match_in_progress)

@rpc("authority", "call_local", "reliable")
func _receive_match_end() -> void:
	match_in_progress = false
	_match_timer_acc = 0.0
	_reset_match_world_state()
	_update_ui_visibility()
	_update_match_timer_display()
	_refresh_lobby_ui()
	emit_signal("lobby_updated", current_lobby_code, connected_peers, selected_game_mode, match_in_progress)

# ============================================================
# MULTIPLAYER CALLBACKS
# ============================================================
func _bind_multiplayer_peer(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_connected_to_server() -> void:
	_connection_timer = null
	local_player_id = multiplayer.get_unique_id()
	current_state = NetworkState.CONNECTED
	if username_entry and username_entry.text.strip_edges() != "":
		local_username = username_entry.text.strip_edges()
	else:
		local_username = "Player " + str(local_player_id)
	_set_status("Connected | " + local_username)
	_update_ui_visibility()
	_refresh_lobby_ui()
	emit_signal("client_connected_to_server")
	if _lobby_allowed():
		emit_signal("lobby_joined", current_lobby_code, false)
	var secure_token := _generate_auth_hmac(local_player_id)
	rpc_id(1, "execute_client_handshake", local_player_id, local_username, secure_token)

func _on_connection_failed() -> void:
	_teardown_failed_client("Connection Refused")

func _on_server_disconnected() -> void:
	_error("Host closed session.")
	_is_evicting = true
	disconnect_client()

func _on_connection_timeout() -> void:
	if current_state == NetworkState.CONNECTING:
		_teardown_failed_client("Timed Out")

func _on_peer_connected(id: int) -> void:
	if current_state == NetworkState.HOSTING and connected_peers.size() >= max_clients:
		_log("Incoming connection rejected: Lobby is full.")
		kick_peer(id, "Lobby is full.")
		return
	var remote_ip := "WebRTC P2P Peer" if transport_protocol == TransportProtocol.WEBRTC else "Unknown"
	if transport_protocol == TransportProtocol.ENET and enet_peer:
		var pkt := enet_peer.get_peer(id)
		if pkt:
			remote_ip = pkt.get_remote_address()
	if not connected_peers.has(id):
		_register_peer(id, remote_ip)
	if multiplayer.is_server() and _lobby_allowed():
		_sync_selected_mode.rpc_id(id, selected_game_mode)
		_receive_match_state.rpc_id(id, match_in_progress, _match_timer_acc, selected_game_mode)
		_broadcast_lobby_state()
	_refresh_lobby_ui()
	_update_ui_visibility()

func _on_peer_disconnected(id: int) -> void:
	_despawn_player(id)
	connected_peers.erase(id)
	if webrtc_peers_map.has(id):
		var pc: WebRTCPeerConnection = webrtc_peers_map[id]
		if pc:
			pc.close()
		webrtc_peers_map.erase(id)
	_remote_desc_set.erase(id)
	_orphaned_candidates.erase(id)
	emit_signal("peer_left", id)
	if multiplayer.is_server():
		_broadcast_lobby_state()
	_refresh_lobby_ui()
	_update_ui_visibility()

func _teardown_network() -> void:
	current_state = NetworkState.OFFLINE
	multiplayer.multiplayer_peer = null
	enet_peer = null
	webrtc_peer = null
	if udp_listener:
		udp_listener.close()
		udp_listener = null
	if udp_broadcaster:
		udp_broadcaster.close()
		udp_broadcaster = null
	for id in webrtc_peers_map.keys():
		var pc: WebRTCPeerConnection = webrtc_peers_map[id]
		if pc:
			pc.close()
	connected_peers.clear()
	webrtc_peers_map.clear()
	_remote_desc_set.clear()
	_orphaned_candidates.clear()
	current_lobby_code = "OFFLINE"
	match_in_progress = false
	_match_timer_acc = 0.0
	local_player_id = 0
	webrtc_client_id = 0
	_update_ui_displays()
	_update_ui_visibility()
	_update_match_timer_display()
	_update_live_player_count()

func _teardown_failed_client(reason: String) -> void:
	_teardown_network()
	_set_status(reason)
	emit_signal("client_failed_to_connect", reason)

# ============================================================
# SPAWN / AUTH
# ============================================================
func _register_peer(id: int, remote_ip: String = "Unknown", peer_name: String = "") -> void:
	if not connected_peers.has(id):
		var default_name := peer_name if peer_name != "" else ("Host" if id == 1 else ("Player " + str(id)))
		connected_peers[id] = {
			"ready": false,
			"ip": remote_ip,
			"name": default_name
		}
	elif peer_name != "":
		connected_peers[id]["name"] = peer_name
	_update_ui_displays()

@rpc("any_peer", "call_local", "reliable")
func execute_client_handshake(id: int, peer_username: String = "", secure_token: String = "") -> void:
	if not multiplayer.is_server():
		return
	if enable_encryption:
		var expected_token := _generate_auth_hmac(id)
		if secure_token != expected_token:
			_debug_print("[SECURITY] Peer %d failed HMAC validation." % id)
			kick_peer(id, "Invalid security context.")
			return
	if connected_peers.size() > max_clients:
		kick_peer(id, "Lobby is full.")
		return
	if connected_peers.has(id):
		connected_peers[id]["ready"] = true
		if peer_username != "":
			connected_peers[id]["name"] = peer_username
	else:
		_register_peer(id, "Unknown", peer_username)
		connected_peers[id]["ready"] = true
	_broadcast_lobby_state()
	if _lobby_allowed():
		_sync_selected_mode.rpc_id(id, selected_game_mode)
		_receive_match_state.rpc_id(id, match_in_progress, _match_timer_acc, selected_game_mode)
	if not (_lobby_allowed() and enable_lobby_system) or match_in_progress:
		spawn_player.rpc(id)
		for existing_id in multiplayer.get_peers():
			if existing_id != id:
				spawn_player.rpc_id(id, existing_id)
		if id != 1:
			spawn_player.rpc_id(id, 1)
	emit_signal("peer_joined", id)
	_refresh_lobby_ui()
	_update_ui_visibility()

@rpc("any_peer", "call_local", "reliable")
func spawn_player(id: int) -> void:
	if spawn_node == null or player_scene == null:
		return
	if spawn_node.has_node(str(id)):
		return
	var p := player_scene.instantiate()
	p.name = str(id)
	p.set_multiplayer_authority(id, true)
	spawn_node.add_child(p)
	if p is Node3D and player_spawn:
		p.global_position = player_spawn.global_position
	var p_name := ""
	if connected_peers.has(id):
		p_name = str(connected_peers[id].get("name", ""))
	if p_name == "":
		p_name = "Host" if id == 1 else ("Player " + str(id))
	if p.has_method("set_username"):
		p.set_username(p_name)
	emit_signal("player_spawned", id, id == local_player_id)
	_update_ui_displays()

func _despawn_player(id: int) -> void:
	if spawn_node == null:
		return
	var node := spawn_node.get_node_or_null(str(id))
	if node:
		node.queue_free()
		emit_signal("player_despawned", id)
		_update_ui_displays()

@rpc("authority", "call_remote", "reliable")
func kick_all_clients(reason: String) -> void:
	enable_host_migration = false
	_error(reason)
	_is_evicting = true
	disconnect_client()

# ============================================================
# ENET
# ============================================================
func _start_enet_host() -> void:
	enet_peer = ENetMultiplayerPeer.new()
	var err := enet_peer.create_server(port, max_clients, allocate_channels)
	if err != OK:
		if err == ERR_ALREADY_IN_USE:
			_log("[TESTING FALLBACK] Port claimed. Booting Local Instance Client...")
			_teardown_network()
			get_tree().create_timer(0.3).timeout.connect(func() -> void:
				if address_entry:
					address_entry.text = "127.0.0.1"
				start_client()
			)
			return
		_error("ENet binding failed: " + str(err))
		_teardown_network()
		return
	if enable_compression:
		enet_peer.get_host().compress(ENetConnection.COMPRESS_ZLIB)
	_bind_multiplayer_peer(enet_peer)

	match hosting_mode:
		HostingMode.LOCAL_ONLY:
			current_lobby_code = "LOCAL_HOST"
			_set_status("Hosting | 127.0.0.1:" + str(port))
			emit_signal("server_started", "ENET", "LOCAL", port, "127.0.0.1", "127.0.0.1")
		HostingMode.LAN:
			var lan := _get_local_ip_and_code()
			current_lobby_code = lan.code
			_set_status("Hosting LAN | Code: " + current_lobby_code)
			udp_broadcaster = PacketPeerUDP.new()
			udp_broadcaster.set_broadcast_enabled(true)
			udp_broadcaster.set_dest_address("255.255.255.255", port + 5)
			emit_signal("server_started", "ENET", "LAN", port, lan.ip, lan.code)
		HostingMode.ONLINE_UPNP:
			_set_status("Negotiating UPnP...")
			if _execute_upnp_discovery() == OK:
				current_lobby_code = _encode_string_to_hex(public_ip_cache)
				_set_status("Hosting Worldwide | Code: " + current_lobby_code)
				emit_signal("server_started", "ENET", "UPNP", port, public_ip_cache, current_lobby_code)
			else:
				hosting_mode = HostingMode.ONLINE_MANUAL
				_fetch_http_public_ip()
		HostingMode.ONLINE_MANUAL:
			_set_status("Querying Global Internet IP...")
			_fetch_http_public_ip()

	_broadcast_lobby_state()
	# LAN (with lobby) waits for Start. LOCAL/UPNP/MANUAL = instant direct spawn.
	if not (_lobby_allowed() and enable_lobby_system):
		spawn_player(1)

func _start_enet_client(raw_input: String) -> void:
	var clean := raw_input.strip_edges()
	if clean == "":
		match hosting_mode:
			HostingMode.LOCAL_ONLY:
				_execute_enet_connection("127.0.0.1")
				return
			HostingMode.LAN:
				_set_status("Scanning UDP LAN Beacons...")
				udp_listener = PacketPeerUDP.new()
				if udp_listener.bind(port + 5) == OK:
					return
				else:
					udp_listener = null
					_teardown_failed_client("Failed to bind LAN scanner port.")
					return
			HostingMode.ONLINE_UPNP, HostingMode.ONLINE_MANUAL:
				_teardown_failed_client("Worldwide Lobby Code required to join online WAN.")
				return
	_execute_enet_connection(clean)

func _execute_enet_connection(target_hex_code: String) -> void:
	var clean_target := target_hex_code.strip_edges()
	var target_ip := _safe_decode_target(clean_target)
	if hosting_mode == HostingMode.LOCAL_ONLY:
		current_lobby_code = "LOCAL_HOST"
	elif clean_target == "" or clean_target.to_lower() == "localhost" or "." in clean_target or ":" in clean_target:
		current_lobby_code = _encode_string_to_hex(target_ip)
	else:
		current_lobby_code = clean_target
	var is_lan := false
	if target_ip == "127.0.0.1" or target_ip.begins_with("10.") or target_ip.begins_with("192.168."):
		is_lan = true
	elif target_ip.begins_with("172."):
		var parts := target_ip.split(".")
		if parts.size() >= 2:
			var second := parts[1].to_int()
			if second >= 16 and second <= 31:
				is_lan = true
	var route_type := "Local Network LAN Route" if is_lan else "Worldwide Internet Route"
	_set_status("Dialing " + route_type + "...")
	enet_peer = ENetMultiplayerPeer.new()
	if enet_peer.create_client(target_ip, port, allocate_channels) != OK:
		_teardown_failed_client("Connection Refused")
		return
	if enable_compression:
		enet_peer.get_host().compress(ENetConnection.COMPRESS_ZLIB)
	_bind_multiplayer_peer(enet_peer)

# ============================================================
# WEBRTC / FIREBASE
# ============================================================
func _start_webrtc_host() -> void:
	webrtc_peer = WebRTCMultiplayerPeer.new()
	var err := webrtc_peer.create_server()
	if err != OK:
		_teardown_failed_client("Failed to create WebRTC host.")
		return
	_bind_multiplayer_peer(webrtc_peer)
	current_lobby_code = str(randi() % 899999 + 100000)
	_set_status("Firebase Active | Code: " + current_lobby_code)
	var put_http := HTTPRequest.new()
	add_child(put_http)
	put_http.request_completed.connect(func(_r, _c, _h, _b) -> void:
		put_http.queue_free()
	)
	var url := "%s/rooms/%s/info.json" % [active_firebase_url, current_lobby_code]
	var info_data := {
		"name": server_lobby_name,
		"players": 1,
		"max": max_clients,
		"private": is_private_lobby,
		"mode": selected_game_mode
	}
	put_http.request.call_deferred(url, ["Content-Type: application/json"], HTTPClient.METHOD_PUT, JSON.stringify(info_data))
	emit_signal("server_started", "WEBRTC", "FIREBASE", port, "Firebase Relay", current_lobby_code)
	_broadcast_lobby_state()
	# Consistent gate across all protocols
	if not (_lobby_allowed() and enable_lobby_system):
		spawn_player(1)

func _start_webrtc_client(raw_input: String) -> void:
	current_lobby_code = raw_input.strip_edges()
	if current_lobby_code == "":
		_teardown_failed_client("Room code required.")
		return
	webrtc_client_id = randi() % 2147483640 + 5
	webrtc_peer = WebRTCMultiplayerPeer.new()
	var err := webrtc_peer.create_client(webrtc_client_id)
	if err != OK:
		_teardown_failed_client("Failed to create WebRTC client.")
		return
	_bind_multiplayer_peer(webrtc_peer)
	_set_status("Connecting to Firebase Room...")
	_push_firebase_msg(1, { "type": "intro", "id": webrtc_client_id })

func _push_firebase_msg(target_id: int, payload: Dictionary) -> void:
	if current_lobby_code == "OFFLINE" or current_lobby_code == "":
		return
	if active_firebase_url == "":
		return
	var http := HTTPRequest.new()
	add_child(http)
	var is_host := current_state == NetworkState.HOSTING
	payload["from"] = 1 if is_host else webrtc_client_id
	http.request_completed.connect(func(_r, _code, _h, _b) -> void:
		http.queue_free()
	)
	var url := "%s/rooms/%s/inbox/%d.json" % [active_firebase_url, current_lobby_code, target_id]
	var secure_package := _secure_seal_payload(payload)
	var http_body := JSON.stringify(secure_package)
	http.request.call_deferred(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, http_body)

func _poll_firebase_inbox() -> void:
	if current_lobby_code == "OFFLINE" or current_lobby_code == "":
		return
	if active_firebase_url == "":
		return
	_is_polling_firebase = true
	var is_host := current_state == NetworkState.HOSTING
	var my_inbox_id := 1 if is_host else webrtc_client_id
	var url := "%s/rooms/%s/inbox/%d.json" % [active_firebase_url, current_lobby_code, my_inbox_id]
	var poll_http := HTTPRequest.new()
	add_child(poll_http)
	poll_http.request_completed.connect(func(res, code, headers, body) -> void:
		_on_firebase_poll_result(res, code, headers, body)
		poll_http.queue_free()
	)
	poll_http.request.call_deferred(url, ["Cache-Control: no-cache"])

func _on_firebase_poll_result(res: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_polling_firebase = false
	if res != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var json_str := _bytes_to_string(body).strip_edges()
	if json_str == "null" or json_str == "":
		return
	var json_parser := JSON.new()
	if json_parser.parse(json_str) != OK or not (json_parser.data is Dictionary):
		return
	var inbox_data: Dictionary = json_parser.data
	var is_host := current_state == NetworkState.HOSTING
	var my_inbox_id := 1 if is_host else webrtc_client_id
	var patch_deletes := {}
	for push_key in inbox_data.keys():
		patch_deletes[push_key] = null
	var clear_url := "%s/rooms/%s/inbox/%d.json" % [active_firebase_url, current_lobby_code, my_inbox_id]
	var clear_http := HTTPRequest.new()
	add_child(clear_http)
	clear_http.request_completed.connect(func(_r, _c, _h, _b) -> void:
		clear_http.queue_free()
	)
	clear_http.request.call_deferred(clear_url, ["Content-Type: application/json"], HTTPClient.METHOD_PATCH, JSON.stringify(patch_deletes))
	var raw_messages: Array = inbox_data.values()
	var messages := []
	for pkt in raw_messages:
		if pkt is String:
			var decrypted_dict := _secure_unseal_payload(pkt)
			if not decrypted_dict.is_empty():
				messages.append(decrypted_dict)
		elif pkt is Dictionary:
			messages.append(pkt)
	messages.sort_custom(func(a, b) -> bool:
		var priority := { "intro": 0, "offer": 1, "answer": 2, "candidate": 3, "drop": 4 }
		return priority.get(a.get("type", ""), 5) < priority.get(b.get("type", ""), 5)
	)
	for msg in messages:
		if msg is Dictionary:
			_handle_webrtc_signaling_packet_dict(msg)

func _send_signaling_packet(payload: Dictionary) -> void:
	_push_firebase_msg(int(payload["to"]), payload)

func _handle_webrtc_signaling_packet_dict(data: Dictionary) -> void:
	if not data.has("type"):
		return
	var msg_type := str(data["type"])
	var from_id := int(data.get("from", 0))
	match msg_type:
		"intro":
			if current_state != NetworkState.HOSTING:
				return
			var cid := int(data.get("id", 0))
			if cid <= 0:
				return
			if webrtc_peers_map.has(cid):
				return
			var host_pc := _create_peer_connection(cid)
			if host_pc == null:
				return
			webrtc_peer.add_peer(host_pc, cid)
			host_pc.create_offer()
			_flush_orphaned_candidates(cid)
		"offer":
			var fid := int(data.get("from", 0))
			if fid <= 0:
				return
			if webrtc_peers_map.has(fid) and bool(_remote_desc_set.get(fid, false)):
				return
			var offer_pc: WebRTCPeerConnection = null
			if webrtc_peers_map.has(fid):
				offer_pc = webrtc_peers_map[fid]
			else:
				offer_pc = _create_peer_connection(fid)
				if offer_pc == null:
					return
				webrtc_peer.add_peer(offer_pc, fid)
			offer_pc.set_remote_description("offer", str(data.get("sdp", "")))
			_remote_desc_set[fid] = true
			get_tree().create_timer(0.1).timeout.connect(func() -> void:
				_flush_orphaned_candidates(fid)
			)
		"answer":
			if from_id <= 0:
				return
			if not webrtc_peers_map.has(from_id):
				return
			if bool(_remote_desc_set.get(from_id, false)):
				return
			var answer_pc: WebRTCPeerConnection = webrtc_peers_map[from_id]
			answer_pc.set_remote_description("answer", str(data.get("sdp", "")))
			_remote_desc_set[from_id] = true
			get_tree().create_timer(0.1).timeout.connect(func() -> void:
				_flush_orphaned_candidates(from_id)
			)
		"candidate":
			if from_id <= 0:
				return
			if webrtc_peers_map.has(from_id) and bool(_remote_desc_set.get(from_id, false)):
				var candidate_pc: WebRTCPeerConnection = webrtc_peers_map[from_id]
				candidate_pc.add_ice_candidate(
					str(data.get("mid", "")),
					int(data.get("index", 0)),
					str(data.get("sdp", ""))
				)
			else:
				if not _orphaned_candidates.has(from_id):
					_orphaned_candidates[from_id] = []
				_orphaned_candidates[from_id].append(data)
		"drop":
			var drop_id := int(data.get("id", from_id))
			if webrtc_peers_map.has(drop_id):
				var drop_pc: WebRTCPeerConnection = webrtc_peers_map[drop_id]
				if drop_pc:
					drop_pc.close()
				webrtc_peers_map.erase(drop_id)
			_remote_desc_set.erase(drop_id)
			_orphaned_candidates.erase(drop_id)

func _flush_orphaned_candidates(id: int) -> void:
	if not _orphaned_candidates.has(id):
		return
	if not webrtc_peers_map.has(id):
		_orphaned_candidates.erase(id)
		return
	var pc: WebRTCPeerConnection = webrtc_peers_map[id]
	var pending: Array = _orphaned_candidates[id]
	for cand in pending:
		if cand is Dictionary:
			pc.add_ice_candidate(
				str(cand.get("mid", "")),
				int(cand.get("index", 0)),
				str(cand.get("sdp", ""))
			)
	_orphaned_candidates.erase(id)

func _create_peer_connection(id: int) -> WebRTCPeerConnection:
	var pc := WebRTCPeerConnection.new()
	var init_err := pc.initialize({ "iceServers": [ { "urls": [stun_server_url] } ] })
	if init_err != OK:
		_error("Failed to initialize WebRTC peer connection.")
		return null
	pc.session_description_created.connect(_on_webrtc_sdp.bind(id))
	pc.ice_candidate_created.connect(_on_webrtc_ice.bind(id))
	webrtc_peers_map[id] = pc
	return pc

func _on_webrtc_sdp(type: String, sdp: String, target_id: int) -> void:
	if not webrtc_peers_map.has(target_id):
		return
	var pc: WebRTCPeerConnection = webrtc_peers_map[target_id]
	pc.set_local_description(type, sdp)
	_send_signaling_packet({
		"type": type,
		"to": target_id,
		"sdp": sdp
	})

func _on_webrtc_ice(media: String, index: int, sdp_name: String, target_id: int) -> void:
	_send_signaling_packet({
		"type": "candidate",
		"to": target_id,
		"mid": media,
		"index": index,
		"sdp": sdp_name
	})

# ============================================================
# UTILITIES
# ============================================================
func _execute_upnp_discovery() -> int:
	if OS.has_feature("web"):
		return ERR_CANT_CONNECT
	if upnp == null:
		upnp = ClassDB.instantiate("UPNP")
	if upnp == null:
		return ERR_CANT_CONNECT
	var discover_res: int = upnp.call("discover")
	if discover_res != 0:
		return ERR_CANT_CONNECT
	var gateway: Variant = upnp.call("get_gateway")
	if gateway == null or not gateway.call("is_valid_gateway"):
		return ERR_CANT_CONNECT
	var map_res: int = upnp.call("add_port_mapping", port, port, "Godot ENet Engine", "UDP")
	if map_res != 0:
		return ERR_CANT_CONNECT
	public_ip_cache = str(upnp.call("query_external_address"))
	return OK

func _fetch_http_public_ip() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(res, code, _headers, body) -> void:
		if res == HTTPRequest.RESULT_SUCCESS and code == 200:
			public_ip_cache = _bytes_to_string(body).strip_edges()
			current_lobby_code = _encode_string_to_hex(public_ip_cache)
			_set_status("Hosting Worldwide | Code: " + current_lobby_code)
			emit_signal("server_started", "ENET", "MANUAL", port, public_ip_cache, current_lobby_code)
			_broadcast_lobby_state()
		else:
			_set_status("Hosting | Unknown IP")
		http.queue_free()
	)
	http.request("https://api.ipify.org")

func _encode_string_to_hex(str_in: String) -> String:
	var code := ""
	for b in str_in.to_utf8_buffer():
		code += "%02X" % b
	return code

func _get_local_ip_and_code() -> Dictionary:
	var ip := "127.0.0.1"
	for a in IP.get_local_addresses():
		if "." in a and not a.begins_with("127") and not a.begins_with("169"):
			ip = a
			break
	return { "ip": ip, "code": _encode_string_to_hex(ip) }

func _safe_decode_target(input: String) -> String:
	var clean := input.strip_edges()
	if "." in clean or ":" in clean or clean.to_lower() == "localhost":
		return clean
	var bytes := PackedByteArray()
	for i in range(0, clean.length(), 2):
		if i + 2 <= clean.length():
			bytes.append(("0x" + clean.substr(i, 2)).hex_to_int())
	var decoded := _bytes_to_string(bytes)
	return decoded if decoded != "" else "127.0.0.1"
