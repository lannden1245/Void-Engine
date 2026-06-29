extends Node

# ════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════
@export_group("Core")
@export var enabled: bool = true
@export var aggressive_mode: bool = true
@export var scan_speed: float = 0.4

@export_group("Features")
@export var show_popup: bool = true
@export var enable_hwid_ban: bool = true
@export var ip_ban_mode: bool = true
@export var use_fancy_ui: bool = true

@export_group("Detection Types")
@export var detect_debuggers: bool = true
@export var detect_modifiers: bool = true
@export var detect_memory_tools: bool = true

# ════════════════════════════════════════════════════════════
# STATE & DATABASES
# ════════════════════════════════════════════════════════════
var _timer: Timer
var _is_active: bool = false
var _popup_shown: bool = false
var _hwid: String = ""
var _ban_file_path: String = "user://anticheat_blacklist.dat"

var _blacklist_processes: Array[String] = [
	"cheatengine", "ce-x86_64", "ce-i386", "ceserver.exe", 
	"speedhack-i386.dll", "speedhack-x86_64.dll",
	"x64dbg", "x32dbg", "ollydbg", "ida64", "idaq64", "windbg",
	"dbgview", "sysinternals", "procmon",
	"artmoney", "bit slicer", "memory scanner", "scyllahide",
	"hxd hex editor", "winhex", "010editor", "cheat table",
	"process hacker", "process monitor", "procexp", "procmon64",
	"gameguardian", "ggmodifier", "lucky patcher", "freedom",
	"injector", "dll injector", "mimik_dump", "reclass"
]

var _blacklist_windows: Array[String] = [
	"cheat engine", "scan result", "memory view", "found list",
	"TCEForm", "CheatTable", "First Scan", "Next Scan", "New Scan",
	"artmoney", "x64_dbg", "IDA View", "Hex Editor",
	"game guardian", "lucky patcher", "process hacker"
]

var _vault: Dictionary = {}

var _honeypots: Dictionary = {
	"_ac_test_hp": 1337,
	"_ac_test_gold": 999999,
	"_ac_active": true,
	"_integrity_check": 0xDEAD
}
var _honeypot_hashes: Dictionary = {}

func _ready():
	if not enabled:
		push_warning("[AC] DISABLED - Test mode active")
		return
	
	_hwid = _generate_hwid()
	
	if enable_hwid_ban and _check_local_ban():
		_show_permanent_ban_screen()
		return
	
	for k in _honeypots.keys():
		_honeypot_hashes[k] = _fnv_hash(str(_honeypots[k]))
	
	_timer = Timer.new()
	_timer.wait_time = scan_speed
	_timer.timeout.connect(_scan_loop)
	add_child(_timer)
	_timer.start()
	
	_is_active = true
	print("[WhiteVoid AC] ✅ Online | ID: %s..." % _hwid.substr(0, 8))

# ════════════════════════════════════════════════════════════
# MAIN SCAN LOOP
# ════════════════════════════════════════════════════════════
func _scan_loop():
	if not _is_active or _popup_shown:
		return
	
	if _check_honeypots():
		_execute_security_action("MEMORY_TAMPERING")
		return
	
	if _detect_any_threat():
		_execute_security_action("UNAUTHORIZED_TOOL")
		return

# ════════════════════════════════════════════════════════════
# DETECTION ENGINE
# ════════════════════════════════════════════════════════════
func _detect_any_threat() -> bool:
	var output = []
	
	var exit_code = OS.execute("cmd", ["/c", "tasklist", "/FO", "CSV", "/NH"], output, true, false)
	if exit_code == 0 and output.size() > 0:
		var text = str(output[0]).to_lower()
		for sig in _blacklist_processes:
			if sig in text:
				push_warning("[AC] ⚠️ Process detected: %s" % sig)
				return true
	
	output.clear()
	exit_code = OS.execute("cmd", ["/c", "tasklist", "/FO", "CSV", "/NH", "/V"], output, true, false)
	if exit_code == 0 and output.size() > 0:
		var text = str(output[0]).to_lower()
		for sig in _blacklist_windows:
			if sig in text:
				push_warning("[AC] ⚠️ Window signature: %s" % sig)
				return true
	
	if detect_debuggers:
		output.clear()
		exit_code = OS.execute("wmic", ["process", "where", "name='cmd.exe'", "get", "commandline"], output, true, false)
		if exit_code == 0 and output.size() > 0:
			var txt = str(output[0]).to_lower()
			if ("debugger" in txt or "-debug" in txt or "ollydbg" in txt or "x64dbg" in txt):
				push_warning("[AC] Debugger attachment suspected")
				return true
	
	return false

# ════════════════════════════════════════════════════════════
# VARIABLE PROTECTION API
# ════════════════════════════════════════════════════════════
func protect(var_name: String, val):
	var key = randi() % 2147483647
	_vault[var_name] = {
		v = _xor_encrypt(str(val), key),
		h = _fnv_hash(str(val)) ^ key,
		t = typeof(val),
		k = key,
		ts = Time.get_ticks_msec(),
		last = val
	}

func retrieve(var_name: String):
	if !_vault.has(var_name):
		push_error("[AC] Unprotected access: %s" % var_name)
		return null
	
	var d = _vault[var_name]
	var dec = _xor_decrypt(d.v, d.k)
	var current_val
	
	if d.t == TYPE_STRING:
		current_val = dec
	else:
		current_val = str_to_var(dec)
	
	if (_fnv_hash(str(current_val)) ^ d.k) != d.h:
		_execute_security_action("TAMPER_" + var_name.to_upper())
		return null
	
	var dt = float(Time.get_ticks_msec() - d.ts) / 1000.0
	if dt < 0.2 and d.t in [TYPE_INT, TYPE_FLOAT]:
		if abs(float(current_val) - float(d.last)) > 100:
			_execute_security_action("SPEEDHACK_" + var_name.to_upper())
			return null
	
	d.ts = Time.get_ticks_msec()
	d.last = current_val
	return current_val

func set_val(var_name: String, new_val):
	if !_vault.has(var_name):
		protect(var_name, new_val)
		return
	
	var d = _vault[var_name]
	d.v = _xor_encrypt(str(new_val), d.k)
	d.h = _fnv_hash(str(new_val)) ^ d.k
	d.ts = Time.get_ticks_msec()
	d.last = new_val

func _check_honeypots() -> bool:
	for k in _honeypots.keys():
		if _fnv_hash(str(_honeypots[k])) != _honeypot_hashes[k]:
			push_warning("[AC] 💥 Honeypot triggered: %s" % k)
			return true
	return false

# ════════════════════════════════════════════════════════════
# BAN & SECURITY EXECUTION
# ════════════════════════════════════════════════════════════
func _execute_security_action(reason: String):
	if not enabled:
		push_error("\n[DEBUG-MODE] Violation blocked: %s\nEnable 'enabled' to activate." % reason)
		return
	
	_is_active = false
	_popup_shown = true
	
	if _timer and not _timer.is_stopped():
		_timer.stop()
	
	if enable_hwid_ban:
		_save_local_ban(reason)
	
	if ip_ban_mode:
		_send_ip_ban_to_server(reason)
	
	if show_popup:
		await _show_cheat_detected_dialog(reason)
	else:
		await get_tree().create_timer(0.05).timeout
	
	_crash_process()

# ════════════════════════════════════════════════════════════
# HWID BAN SYSTEM
# ════════════════════════════════════════════════════════════
func _generate_hwid() -> String:
	var id_parts = []
	
	var mac_output = []
	var exit_code = OS.execute("getmac", ["/nh", "/fo", "csv", "/v"], mac_output, true, false)
	if exit_code == 0 and mac_output.size() > 0:
		id_parts.append(str(mac_output[0]).replace("-", "").replace(":", ""))
	
	if OS.has_feature("windows"):
		var bios_output = []
		exit_code = OS.execute("wmic", ["bios", "get", "serialnumber"], bios_output, true, false)
		if exit_code == 0 and bios_output.size() > 1:
			id_parts.append(str(bios_output[1]).strip_edges())
	
	id_parts.append(str(OS.get_unique_id()))
	
	var combined = "".join(id_parts).to_upper().replace(" ", "").replace("\"", "")
	
	if combined.length() < 10:
		combined += str(randi()) + str(Time.get_ticks_usec())
	
	return combined.md5_text()

func _save_local_ban(reason: String):
	var file = FileAccess.open(_ban_file_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(_ban_file_path, FileAccess.WRITE)
	else:
		file.seek_end(file.get_length())
	
	var timestamp = Time.get_datetime_string_from_system()
	file.store_line("%s|%s|%s|%d" % [_hwid, reason, timestamp, Time.get_unix_time_from_system()])
	file = null

func _check_local_ban() -> bool:
	if !FileAccess.file_exists(_ban_file_path):
		return false
	
	var file = FileAccess.open(_ban_file_path, FileAccess.READ)
	while !file.eof_reached():
		var line = file.get_line()
		var parts = line.split("|")
		if parts.size() >= 1 and parts[0] == _hwid:
			file = null
			return true
	file = null
	return false

func _send_ip_ban_to_server(reason: String):
	pass

# ════════════════════════════════════════════════════════════
# UI SYSTEM (Auto-generated, Fancy)
# ════════════════════════════════════════════════════════════
func _show_cheat_detected_dialog(reason: String) -> void:
	# Defer so we never hit "parent busy setting up children"
	await get_tree().process_frame
	
	if use_fancy_ui:
		_build_fancy_overlay(reason, _hwid, 15.0)
		await get_tree().create_timer(15.0).timeout
		return
	
	# Fallback plain dialog
	var dialog = AcceptDialog.new()
	dialog.title = "⛔ SECURITY VIOLATION DETECTED"
	dialog.min_size = Vector2i(450, 280)
	dialog.unresizable = true
	dialog.exclusive = true
	
	var label = RichTextLabel.new()
	label.fit_content = true
	label.bbcode_enabled = true
	label.text = "[center][b][color=red]UNAUTHORIZED TOOL DETECTED[/color][/b][/center]\n\nReason: [color=yellow]%s[/color]\nDevice ID: %s...\n\nThis application will terminate immediately." % [reason, _hwid.substr(0, 12)]
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dialog.add_child(label)
	
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.grab_focus()
	
	await get_tree().create_timer(15.0).timeout

func _show_permanent_ban_screen() -> void:
	# Defer so we never hit "parent busy setting up children"
	await get_tree().process_frame
	
	if use_fancy_ui:
		_build_fancy_overlay("PERMANENTLY BANNED (HWID)", _hwid, 10.0)
		await get_tree().create_timer(10.0).timeout
		get_tree().quit(-99)
		return
	
	var dialog = AcceptDialog.new()
	dialog.title = "🔒 PERMANENTLY BANNED"
	dialog.min_size = Vector2i(400, 220)
	dialog.exclusive = true
	
	var lbl = Label.new()
	lbl.text = "YOU ARE PERMANENTLY BANNED FROM THIS APPLICATION.\n\nDevice ID: %s" % _hwid.substr(0, 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.add_child(lbl)
	
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	
	await get_tree().create_timer(10.0).timeout
	get_tree().quit(-99)

func _build_fancy_overlay(reason: String, hwid: String, auto_kill_in: float) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(layer)
	
	# Dim
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.size = vp_size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	
	# Card
	var card := Panel.new()
	var card_size := Vector2(520, 320)
	card.size = card_size
	card.position = (vp_size - card_size) / 2.0
	dim.add_child(card)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.07, 0.98)
	sb.border_color = Color(0.9, 0.2, 0.2, 1.0)
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(1, 0, 0, 0.35)
	sb.shadow_size = 24
	card.add_theme_stylebox_override("panel", sb)
	
	# VBox
	var v := VBoxContainer.new()
	v.size = Vector2(card_size.x - 56, card_size.y - 44)
	v.position = Vector2(28, 22)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	
	# Title
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_font_size_override("normal_font_size", 26)
	title.text = "[center][shake rate=6 level=8][color=#ff3333]SECURITY VIOLATION[/color][/shake][/center]"
	v.add_child(title)
	
	# Subtitle
	var sub := Label.new()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.text = "An unauthorized tool / memory tampering was detected."
	v.add_child(sub)
	
	# Reason box
	var rb := Panel.new()
	rb.custom_minimum_size = Vector2(0, 48)
	v.add_child(rb)
	
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.12, 0.02, 0.02, 0.9)
	rsb.border_color = Color(0.55, 0.1, 0.1, 1.0)
	rsb.border_width_left = 1
	rsb.border_width_right = 1
	rsb.border_width_top = 1
	rsb.border_width_bottom = 1
	rsb.corner_radius_top_left = 6
	rsb.corner_radius_top_right = 6
	rsb.corner_radius_bottom_left = 6
	rsb.corner_radius_bottom_right = 6
	rb.add_theme_stylebox_override("panel", rsb)
	
	var rc := CenterContainer.new()
	rc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rb.add_child(rc)
	
	var rl := Label.new()
	rl.text = "Reason: %s" % reason
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.add_theme_font_size_override("font_size", 15)
	rc.add_child(rl)
	
	# HWID
	var id := Label.new()
	id.text = "Device ID: %s" % hwid.substr(0, 16)
	id.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	id.modulate = Color(0.75, 0.75, 0.75)
	v.add_child(id)
	
	# Progress bar
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 18)
	bar.max_value = auto_kill_in
	bar.value = auto_kill_in
	bar.show_percentage = false
	v.add_child(bar)
	
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.18, 0, 0, 1)
	bsb.border_color = Color(0.9, 0.2, 0.2, 0.8)
	bsb.border_width_left = 1
	bsb.border_width_right = 1
	bsb.border_width_top = 1
	bsb.border_width_bottom = 1
	bsb.corner_radius_top_left = 6
	bsb.corner_radius_top_right = 6
	bsb.corner_radius_bottom_left = 6
	bsb.corner_radius_bottom_right = 6
	bar.add_theme_stylebox_override("fill", bsb)
	
	# Countdown text
	var c := Label.new()
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.text = "Application will terminate in %.1f seconds..." % auto_kill_in
	v.add_child(c)
	
	# Note
	var note := Label.new()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.modulate = Color(0.55, 0.55, 0.55)
	note.add_theme_font_size_override("font_size", 11)
	note.text = "If this is a false positive, contact support with your Device ID."
	v.add_child(note)
	
	# Pulse
	var tw := layer.create_tween().set_loops()
	tw.tween_property(sb, "shadow_color:a", 0.15, 0.45).from(0.45)
	tw.tween_property(sb, "shadow_color:a", 0.45, 0.45)
	
	# Countdown logic
	var time_left := auto_kill_in
	while time_left > 0 and is_instance_valid(layer):
		await get_tree().create_timer(0.05).timeout
		if not is_instance_valid(layer):
			return
		time_left -= 0.05
		bar.value = max(0.0, time_left)
		if time_left <= 0.25:
			c.text = "Terminating..."
		else:
			c.text = "Application will terminate in %.1f seconds..." % time_left
	
	if is_instance_valid(layer):
		layer.queue_free()

func _crash_process():
	OS.kill(OS.get_process_id())

# ════════════════════════════════════════════════════════════
# CRYPTOGRAPHY
# ════════════════════════════════════════════════════════════
func _xor_encrypt(text: String, key: int) -> PackedByteArray:
	var bytes = text.to_utf8_buffer()
	var key_bytes = var_to_bytes(key)
	var result = PackedByteArray()
	result.resize(bytes.size())
	
	for i in range(bytes.size()):
		var kb = key_bytes[i % key_bytes.size()]
		result[i] = bytes[i] ^ kb ^ ((i * 7) & 0xFF)
	
	return result

func _xor_decrypt(enc: PackedByteArray, key: int) -> String:
	var key_bytes = var_to_bytes(key)
	var result = PackedByteArray()
	result.resize(enc.size())
	
	for i in range(enc.size()):
		var kb = key_bytes[i % key_bytes.size()]
		result[i] = enc[i] ^ kb ^ ((i * 7) & 0xFF)
		
	return result.get_string_from_utf8()

func _fnv_hash(text: String) -> int:
	var h = 2166136261
	for i in range(text.length()):
		h = h ^ text.unicode_at(i)
		h = (h * 16777619) & 0xFFFFFFFF
	return h

# ════════════════════════════════════════════════════════════
# LIFECYCLE
# ════════════════════════════════════════════════════════════
func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _is_active == false and enabled:
		_crash_process()

static func clear_local_bans() -> void:
	if FileAccess.file_exists("user://anticheat_blacklist.dat"):
		DirAccess.remove_absolute("user://anticheat_blacklist.dat")

func get_device_id() -> String:
	return _hwid.substr(0, 16) + "..."

func is_device_banned() -> bool:
	return _check_local_ban()
