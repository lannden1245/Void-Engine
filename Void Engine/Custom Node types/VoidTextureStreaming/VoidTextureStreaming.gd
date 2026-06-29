extends MeshInstance3D

# --- Global Script Check ---
@export_group("Global Check Settings")
## The name of your autoload singleton (Project Settings -> Autoload).
@export var global_script_name: String = "WhitevoidAntiCheat"

## Boolean variable names inside the global script, checked in order.
## Element 0 -> texture index 0, Element 1 -> texture index 1, etc.
@export var mode_flags: Array[String] = ["classic", "free_for_all"]

## ON  = automatically checks the mode flags.
## OFF = mode is locked. Uses manual_mode_index instead.
@export var auto_mode_checking: bool = true

## Only used when auto_mode_checking is OFF.
@export var manual_mode_index: int = 0

# --- Level Groups ---
@export_group("Ultra-Res (Level 3)")
@export var albedo_ultra: Array[Texture2D] = []
@export var normal_ultra: Array[Texture2D] = []
@export var roughness_ultra: Array[Texture2D] = []
@export var metallic_ultra: Array[Texture2D] = []
@export var ao_ultra: Array[Texture2D] = []

@export_group("High-Res (Level 2)")
@export var albedo_hi: Array[Texture2D] = []
@export var normal_hi: Array[Texture2D] = []
@export var roughness_hi: Array[Texture2D] = []
@export var metallic_hi: Array[Texture2D] = []
@export var ao_hi: Array[Texture2D] = []

@export_group("Mid-Res (Level 1 / Mobile 1K)")
@export var albedo_mid: Array[Texture2D] = []
@export var normal_mid: Array[Texture2D] = []
@export var roughness_mid: Array[Texture2D] = []
@export var metallic_mid: Array[Texture2D] = []
@export var ao_mid: Array[Texture2D] = []

@export_group("Low-Res (Level 0 / Far Away)")
@export var albedo_low: Array[Texture2D] = []
@export var normal_low: Array[Texture2D] = []
@export var roughness_low: Array[Texture2D] = []
@export var metallic_low: Array[Texture2D] = []
@export var ao_low: Array[Texture2D] = []

# --- Distance Settings ---
@export_group("Distances (Albedo)")
@export var ultra_dist: float = 4.0
@export var high_dist: float = 12.0
@export var mid_dist: float = 35.0

@export_group("Distances (Normal)")
@export var normal_ultra_dist: float = 4.0
@export var normal_high_dist: float = 12.0
@export var normal_mid_dist: float = 35.0

@export_group("Distances (Roughness)")
@export var rough_ultra_dist: float = 4.0
@export var rough_high_dist: float = 12.0
@export var rough_mid_dist: float = 35.0

@export_group("Distances (Metallic)")
@export var metal_ultra_dist: float = 4.0
@export var metal_high_dist: float = 12.0
@export var metal_mid_dist: float = 35.0

@export_group("Distances (AO)")
@export var ao_ultra_dist: float = 4.0
@export var ao_high_dist: float = 12.0
@export var ao_mid_dist: float = 35.0

# --- Startup Visibility ---
@export_group("Startup Visibility")
## ON = the object is completely hidden the moment the game starts.
@export var hide_on_start: bool = true

## Seconds to wait after the game starts before the object is shown.
@export var show_delay: float = 0.0

# --- Progressive Loading ---
@export_group("Progressive Loading")
## ON = when the object first appears, textures start at the LOWEST level
##      you have assigned and climb up one level at a time.
@export var progressive_loading: bool = true

## Seconds between each resolution step-up.
@export var progressive_step_time: float = 1.0

## ON  = climbs through EVERY level that has textures assigned, ignoring
##       camera distance, so the climb is always visible.
## OFF = stops climbing at the level the camera distance needs.
@export var climb_all_levels: bool = true

# --- Optimization ---
@export_group("Optimization")
@export var streaming_delay: float = 0.5
@export var check_interval: float = 1.0

## ON  = automatically checks textures every check_interval seconds.
## OFF = call force_texture_check() manually.
@export var auto_texture_checking: bool = true

## ON = texture selection logic runs on a background thread.
@export var use_threading: bool = true

@export var surface_index: int = 0
@export var force_mobile_resolution: bool = false
@export var debug_prints: bool = true

@export_group("Transparency")
@export_enum("Opaque", "Alpha", "Alpha Scissor", "Alpha Hash") var transparency_mode: int = 0
@export_range(0, 1) var alpha_cutoff: float = 0.5
@export var albedo_color: Color = Color.WHITE

@export_group("UV Mapping")
@export var uv_scale: Vector3 = Vector3(1, 1, 1)
@export var uv_offset: Vector3 = Vector3(0, 0, 0)
@export var triplanar: bool = false
@export_range(0, 150) var triplanar_sharpness: float = 1.0

@export_group("UV2 Mapping")
@export var uv2_scale: Vector3 = Vector3(1, 1, 1)
@export var uv2_offset: Vector3 = Vector3(0, 0, 0)
@export var triplanar_uv2: bool = false

@export_group("Material PBR Settings")
@export_range(0, 1) var mat_roughness: float = 1.0
@export_range(0, 1) var mat_metallic: float = 0.0
@export_range(-16, 16) var mat_normal_scale: float = 1.0
@export_range(0, 1) var mat_ao_light_affect: float = 0.0


signal object_shown
signal loading_finished

var original_textures: Dictionary = {}
var swap_timers: Dictionary = {}
var pending_tex: Dictionary = {}
var streaming_material: StandardMaterial3D = null
var is_mobile: bool = false
var last_active_index: int = -1

var thread_busy: bool = false
var check_timer_node: Timer = null
var initial_loading: bool = false


func _ready():
	is_mobile = OS.get_name() in ["Android", "iOS"]

	if hide_on_start:
		visible = false

	var base_mat: Material = get_surface_override_material(surface_index)

	if base_mat == null and mesh != null and surface_index < mesh.get_surface_count():
		base_mat = mesh.surface_get_material(surface_index)

	if base_mat != null and base_mat is StandardMaterial3D:
		streaming_material = (base_mat as StandardMaterial3D).duplicate()
		if debug_prints:
			print("[TextureStreaming] Duplicated existing StandardMaterial3D on: ", name)
	else:
		streaming_material = StandardMaterial3D.new()
		if debug_prints:
			print("[TextureStreaming] No StandardMaterial3D found. Created a new one on: ", name)

	set_surface_override_material(surface_index, streaming_material)

	streaming_material.albedo_color = albedo_color
	streaming_material.roughness = mat_roughness
	streaming_material.metallic = mat_metallic
	streaming_material.normal_scale = mat_normal_scale
	streaming_material.ao_enabled = true
	streaming_material.ao_light_affect = mat_ao_light_affect
	streaming_material.alpha_scissor_threshold = alpha_cutoff

	streaming_material.uv1_scale = uv_scale
	streaming_material.uv1_offset = uv_offset
	streaming_material.uv1_triplanar = triplanar
	streaming_material.uv1_triplanar_sharpness = triplanar_sharpness

	streaming_material.uv2_scale = uv2_scale
	streaming_material.uv2_offset = uv2_offset
	streaming_material.uv2_triplanar = triplanar_uv2

	match transparency_mode:
		0: streaming_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		1: streaming_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		2: streaming_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		3: streaming_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH

	original_textures = {
		"albedo": streaming_material.albedo_texture,
		"normal": streaming_material.normal_texture,
		"roughness": streaming_material.roughness_texture,
		"metallic": streaming_material.metallic_texture,
		"ao": streaming_material.ao_texture
	}

	if auto_texture_checking:
		check_timer_node = Timer.new()
		check_timer_node.wait_time = max(check_interval, 0.05)
		check_timer_node.autostart = true
		check_timer_node.one_shot = false
		check_timer_node.timeout.connect(_do_check)
		add_child(check_timer_node)

	initial_loading = true
	call_deferred("_startup_sequence")


# =========================================================
#  STARTUP SEQUENCE (FIXED)
#  Climbs through the levels you ACTUALLY assigned textures
#  to, lowest first, so the climb is always visible.
# =========================================================
func _startup_sequence() -> void:
	if streaming_material == null:
		initial_loading = false
		return

	# --- Step 1: wait the show_delay timer while fully hidden ---
	if show_delay > 0.0:
		if debug_prints:
			print("[TextureStreaming] ", name, " hidden for ", show_delay, "s before showing...")
		await get_tree().create_timer(show_delay).timeout
		if not is_inside_tree() or streaming_material == null:
			return

	# --- Step 2: mode index ---
	var active_index: int
	if auto_mode_checking:
		active_index = _get_active_index()
	else:
		active_index = max(manual_mode_index, 0)
	last_active_index = active_index

	# --- Step 3: build the climb list from levels that actually have textures ---
	var climb_levels: Array[String] = []
	for lvl in ["low", "mid", "hi", "ultra"]:
		if _level_has_textures(lvl):
			climb_levels.append(lvl)

	# Mobile never goes above mid.
	if is_mobile or force_mobile_resolution:
		climb_levels = climb_levels.filter(func(l): return _level_rank(l) <= 1)

	# Optionally cap at what the camera distance needs.
	if not climb_all_levels and progressive_loading:
		var target_rank := _level_rank(_get_target_level_for_distance())
		climb_levels = climb_levels.filter(func(l): return _level_rank(l) <= target_rank)

	if debug_prints:
		print("[TextureStreaming] ", name, " climb path: ", climb_levels)

	# --- Step 4: apply the LOWEST assigned level while still hidden ---
	if climb_levels.size() > 0:
		_apply_level_exact(climb_levels[0], active_index)
		if debug_prints:
			print("[TextureStreaming] First load: starting at ", climb_levels[0].to_upper(), " on ", name)

	await get_tree().process_frame
	if not is_inside_tree():
		return

	# --- Step 5: show the object ---
	if hide_on_start:
		visible = true
		if debug_prints:
			print("[TextureStreaming] ", name, " is now visible.")
	object_shown.emit()

	# --- Step 6: climb the remaining levels one at a time ---
	if progressive_loading:
		for i in range(1, climb_levels.size()):
			await get_tree().create_timer(max(progressive_step_time, 0.05)).timeout
			if not is_inside_tree() or streaming_material == null:
				return

			_apply_level_exact(climb_levels[i], active_index)

			if debug_prints:
				print("[TextureStreaming] First load: climbed to ", climb_levels[i].to_upper(), " on ", name)
	elif climb_levels.size() > 0:
		# No progressive climb -> jump straight to the best level in the list.
		_apply_level_exact(climb_levels[climb_levels.size() - 1], active_index)

	# --- Step 7: done, hand over to normal streaming ---
	initial_loading = false
	loading_finished.emit()

	if debug_prints:
		print("[TextureStreaming] First load complete on ", name, ". Normal streaming active.")

	_do_check()


## Does this level have ANY textures assigned at all?
func _level_has_textures(level: String) -> bool:
	match level:
		"low":
			return albedo_low.size() > 0 or normal_low.size() > 0 or roughness_low.size() > 0 or metallic_low.size() > 0 or ao_low.size() > 0
		"mid":
			return albedo_mid.size() > 0 or normal_mid.size() > 0 or roughness_mid.size() > 0 or metallic_mid.size() > 0 or ao_mid.size() > 0
		"hi":
			return albedo_hi.size() > 0 or normal_hi.size() > 0 or roughness_hi.size() > 0 or metallic_hi.size() > 0 or ao_hi.size() > 0
		"ultra":
			return albedo_ultra.size() > 0 or normal_ultra.size() > 0 or roughness_ultra.size() > 0 or metallic_ultra.size() > 0 or ao_ultra.size() > 0
	return false


## Applies EXACTLY this level's textures (per-map: falls down only if that map's slot is empty).
func _apply_level_exact(level: String, index: int) -> void:
	_apply_map("albedo", _pick_for_level(level, albedo_ultra, albedo_hi, albedo_mid, albedo_low, index))
	_apply_map("normal", _pick_for_level(level, normal_ultra, normal_hi, normal_mid, normal_low, index))
	_apply_map("roughness", _pick_for_level(level, roughness_ultra, roughness_hi, roughness_mid, roughness_low, index))
	_apply_map("metallic", _pick_for_level(level, metallic_ultra, metallic_hi, metallic_mid, metallic_low, index))
	_apply_map("ao", _pick_for_level(level, ao_ultra, ao_hi, ao_mid, ao_low, index))


func _pick_for_level(level: String, ultra_arr: Array[Texture2D], hi_arr: Array[Texture2D], mid_arr: Array[Texture2D], low_arr: Array[Texture2D], index: int) -> Texture2D:
	var chosen: Texture2D = null

	match level:
		"ultra":
			chosen = _pick(ultra_arr, index)
			if chosen == null: chosen = _pick(hi_arr, index)
			if chosen == null: chosen = _pick(mid_arr, index)
			if chosen == null: chosen = _pick(low_arr, index)
		"hi":
			chosen = _pick(hi_arr, index)
			if chosen == null: chosen = _pick(mid_arr, index)
			if chosen == null: chosen = _pick(low_arr, index)
		"mid":
			chosen = _pick(mid_arr, index)
			if chosen == null: chosen = _pick(low_arr, index)
		"low":
			chosen = _pick(low_arr, index)

	return chosen


func _get_target_level_for_distance() -> String:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return "ultra"   # no camera yet -> don't accidentally cap the climb

	var dist := global_position.distance_to(cam.global_position)

	if is_mobile or force_mobile_resolution:
		if dist < mid_dist:
			return "mid"
		return "low"

	if dist < ultra_dist:
		return "ultra"
	elif dist < high_dist:
		return "hi"
	elif dist < mid_dist:
		return "mid"
	return "low"


func _level_rank(level: String) -> int:
	match level:
		"low": return 0
		"mid": return 1
		"hi": return 2
		"ultra": return 3
	return 0


## --- PUBLIC ---

func force_texture_check():
	_do_check()

func force_mode_check():
	last_active_index = -1
	_do_check()

func set_auto_checking(enabled: bool):
	auto_texture_checking = enabled
	if check_timer_node != null:
		check_timer_node.paused = not enabled
	elif enabled:
		check_timer_node = Timer.new()
		check_timer_node.wait_time = max(check_interval, 0.05)
		check_timer_node.autostart = true
		check_timer_node.one_shot = false
		check_timer_node.timeout.connect(_do_check)
		add_child(check_timer_node)


## --- MAIN CHECK ---
func _do_check():
	if streaming_material == null:
		return

	if initial_loading:
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var dist := global_position.distance_to(cam.global_position)

	var active_index: int
	if auto_mode_checking:
		active_index = _get_active_index()
	else:
		active_index = max(manual_mode_index, 0)

	var force_instant: bool = active_index != last_active_index

	if force_instant:
		if debug_prints:
			print("[TextureStreaming] Mode changed -> texture index ", active_index)
		last_active_index = active_index

	if use_threading:
		if thread_busy:
			return
		thread_busy = true
		WorkerThreadPool.add_task(_threaded_evaluate.bind(dist, active_index, force_instant))
	else:
		var results := _evaluate_all(dist, active_index, force_instant)
		_apply_results(results)


func _threaded_evaluate(dist: float, active_index: int, force_instant: bool):
	var results := _evaluate_all(dist, active_index, force_instant)
	call_deferred("_finish_threaded", results)


func _finish_threaded(results: Dictionary):
	thread_busy = false
	_apply_results(results)


func _evaluate_all(dist: float, active_index: int, force_instant: bool) -> Dictionary:
	var results: Dictionary = {}

	results["albedo"] = _evaluate_one("albedo", albedo_ultra, albedo_hi, albedo_mid, albedo_low, active_index, dist, ultra_dist, high_dist, mid_dist, force_instant)
	results["normal"] = _evaluate_one("normal", normal_ultra, normal_hi, normal_mid, normal_low, active_index, dist, normal_ultra_dist, normal_high_dist, normal_mid_dist, force_instant)
	results["roughness"] = _evaluate_one("roughness", roughness_ultra, roughness_hi, roughness_mid, roughness_low, active_index, dist, rough_ultra_dist, rough_high_dist, rough_mid_dist, force_instant)
	results["metallic"] = _evaluate_one("metallic", metallic_ultra, metallic_hi, metallic_mid, metallic_low, active_index, dist, metal_ultra_dist, metal_high_dist, metal_mid_dist, force_instant)
	results["ao"] = _evaluate_one("ao", ao_ultra, ao_hi, ao_mid, ao_low, active_index, dist, ao_ultra_dist, ao_high_dist, ao_mid_dist, force_instant)

	return results


func _evaluate_one(type: String, ultra_arr: Array[Texture2D], hi_arr: Array[Texture2D], mid_arr: Array[Texture2D], low_arr: Array[Texture2D], index: int, dist: float, u_d: float, h_d: float, m_d: float, force_instant: bool) -> Dictionary:
	var ultra_tex := _pick(ultra_arr, index)
	var hi_tex := _pick(hi_arr, index)
	var mid_tex := _pick(mid_arr, index)
	var low_tex := _pick(low_arr, index)

	var chosen: Texture2D = null

	if is_mobile or force_mobile_resolution:
		if dist < m_d:
			chosen = mid_tex
			if chosen == null: chosen = low_tex
			if chosen == null: chosen = hi_tex
			if chosen == null: chosen = ultra_tex
		else:
			chosen = low_tex
			if chosen == null: chosen = mid_tex
	else:
		if dist < u_d:
			chosen = ultra_tex
			if chosen == null: chosen = hi_tex
			if chosen == null: chosen = mid_tex
			if chosen == null: chosen = low_tex
		elif dist < h_d:
			chosen = hi_tex
			if chosen == null: chosen = mid_tex
			if chosen == null: chosen = ultra_tex
			if chosen == null: chosen = low_tex
		elif dist < m_d:
			chosen = mid_tex
			if chosen == null: chosen = hi_tex
			if chosen == null: chosen = low_tex
			if chosen == null: chosen = ultra_tex
		else:
			chosen = low_tex
			if chosen == null: chosen = mid_tex

	if chosen == null:
		chosen = original_textures.get(type, null)

	if force_instant:
		swap_timers[type] = 0.0
		pending_tex[type] = null
		return {"tex": chosen, "apply": true}

	if pending_tex.get(type, null) != chosen:
		pending_tex[type] = chosen
		swap_timers[type] = 0.0

	swap_timers[type] = swap_timers.get(type, 0.0) + max(check_interval, 0.05)

	if swap_timers[type] >= streaming_delay:
		swap_timers[type] = 0.0
		pending_tex[type] = null
		return {"tex": chosen, "apply": true}

	return {"tex": null, "apply": false}


func _apply_results(results: Dictionary):
	if streaming_material == null:
		return

	for type in results.keys():
		var r: Dictionary = results[type]
		if r.get("apply", false):
			_apply_map(type, r.get("tex", null))


func _get_active_index() -> int:
	var global_script := get_node_or_null("/root/" + global_script_name)

	if global_script == null:
		return 0

	for i in mode_flags.size():
		var flag_name := mode_flags[i].strip_edges()

		if flag_name == "":
			continue

		if flag_name in global_script:
			if global_script.get(flag_name) == true:
				return i

	return 0


func _pick(arr: Array[Texture2D], index: int) -> Texture2D:
	if arr.size() == 0:
		return null
	if index < arr.size():
		return arr[index]
	return arr[0]


func _apply_map(type: String, tex: Texture2D):
	if tex == null:
		tex = original_textures.get(type, null)

	match type:
		"albedo":
			if streaming_material.albedo_texture != tex:
				streaming_material.albedo_texture = tex
		"normal":
			if streaming_material.normal_texture != tex:
				streaming_material.normal_texture = tex
				streaming_material.normal_enabled = tex != null
		"roughness":
			if streaming_material.roughness_texture != tex:
				streaming_material.roughness_texture = tex
		"metallic":
			if streaming_material.metallic_texture != tex:
				streaming_material.metallic_texture = tex
		"ao":
			if streaming_material.ao_texture != tex:
				streaming_material.ao_texture = tex
