extends Node

# =================================================================
# GLOBAL MODE MANAGER (Autoload Singleton)
# Holds every game mode as a true/false variable you can flip.
# Access from anywhere: ModeManager.is_active("Team Deathmatch")
# =================================================================

# Fired whenever any mode flag changes (UI can listen to this)
signal mode_changed(mode_name: String, is_active: bool)

var Classic = false
var Free_For_All = true

var modes: Dictionary = {
	"Classic": false,
	"Free For All": false,
	"TeamDeathmatch": false,
	"Hide&Seek": false,
	"Casual": false,
}

# The currently SELECTED mode (what host will launch)
var selected_mode: String = "Classic"

# ============================================================
# CORE API — call these from anywhere
# ============================================================

# Turn a specific mode TRUE
func activate(mode_name: String) -> void:
	if modes.has(mode_name):
		modes[mode_name] = true
		emit_signal("mode_changed", mode_name, true)
		print("[ModeManager] '%s' = TRUE" % mode_name)

# Turn a specific mode FALSE
func deactivate(mode_name: String) -> void:
	if modes.has(mode_name):
		modes[mode_name] = false
		emit_signal("mode_changed", mode_name, false)
		print("[ModeManager] '%s' = FALSE" % mode_name)

# Toggle a mode
func toggle(mode_name: String) -> void:
	if modes.has(mode_name):
		set_mode(mode_name, not modes[mode_name])

# Directly set a mode true/false
func set_mode(mode_name: String, value: bool) -> void:
	if modes.has(mode_name):
		modes[mode_name] = value
		emit_signal("mode_changed", mode_name, value)
		print("[ModeManager] '%s' = %s" % [mode_name, str(value)])

# Check if a mode is active (TRUE)
func is_active(mode_name: String) -> bool:
	return modes.get(mode_name, false)

# Turn EVERYTHING off
func reset_all() -> void:
	for m in modes.keys():
		modes[m] = false
		emit_signal("mode_changed", m, false)
	print("[ModeManager] All modes reset to FALSE")

# Activate ONLY one mode (turns others off) — useful for "switch mode"
func set_only(mode_name: String) -> void:
	reset_all()
	activate(mode_name)
	selected_mode = mode_name

# Get a list of all mode names
func get_mode_names() -> Array:
	return modes.keys()

# Get the single currently active mode (or "" if none)
func get_active_mode() -> String:
	for m in modes.keys():
		if modes[m]: return m
	return ""

# Replace the whole dictionary (used by network sync)
func apply_synced(flags: Dictionary) -> void:
	modes = flags.duplicate()
	for m in modes.keys():
		emit_signal("mode_changed", m, modes[m])
