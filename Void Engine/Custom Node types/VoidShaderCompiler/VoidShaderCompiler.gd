@tool
extends Node3D


signal compilation_finished

enum TransitionMode { AUTO, MANUAL, SIGNAL_ONLY }

@export_group("Settings")
@export var warmup_version: String = "1.0"
@export var transition_mode: TransitionMode = TransitionMode.AUTO
@export var target_scene: PackedScene 

@export_group("Assets to Compile")
@export var scenes_to_compile: Array[PackedScene] = []
@export var materials_to_compile: Array[Material] = []

var current_scene_index = 0
var current_material_index = 0
var temp_camera: Camera3D
var is_finished: bool = false
const SAVE_PATH = "user://shader_warmup_status.cfg"

func _ready():
	var total_items = scenes_to_compile.size() + materials_to_compile.size()
	print("--- SHADER WARMUP STARTED ---")
	print("Version: ", warmup_version)
	print("Total Items Found: ", total_items)
	
	if is_already_cached():
		print("Status: [SKIP] Shaders already cached for this version.")
		finish_warmup()
		return
		
	temp_camera = Camera3D.new()
	add_child(temp_camera)
	temp_camera.make_current()
	
	process_next_material()

func _input(event):
	if is_finished and transition_mode == TransitionMode.MANUAL:
		if event is InputEventMouseButton or event.is_action_pressed("ui_accept"):
			execute_scene_switch()


func process_next_material():
	var total_mats = materials_to_compile.size()
	if current_material_index < total_mats:
		var mat = materials_to_compile[current_material_index]
		if mat:
			print("[%d/%d] COMPILING MATERIAL: %s" % [current_material_index + 1, total_mats, mat.resource_path.get_file()])
			warmup_material(mat)
		else:
			current_material_index += 1
			process_next_material()
	else:
		process_next_scene()

func warmup_material(mat: Material):
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = SphereMesh.new()
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	mesh_instance.global_position = temp_camera.global_position - temp_camera.global_transform.basis.z * 2.0
	await get_tree().process_frame
	await get_tree().process_frame
	mesh_instance.queue_free()
	print("      -> Material freed.")
	current_material_index += 1
	process_next_material()

func process_next_scene():
	var total_scenes = scenes_to_compile.size()
	if current_scene_index < total_scenes:
		var packed_scene = scenes_to_compile[current_scene_index]
		if packed_scene:
			print("[%d/%d] COMPILING SCENE: %s" % [current_scene_index + 1, total_scenes, packed_scene.resource_path.get_file()])
			warmup_scene(packed_scene)
		else:
			current_scene_index += 1
			process_next_scene()
	else:
		save_cache_status()
		finish_warmup()

func warmup_scene(packed_scene: PackedScene):
	var instance = packed_scene.instantiate()
	add_child(instance)
	instance.global_position = temp_camera.global_position - temp_camera.global_transform.basis.z * 2.0
	await get_tree().process_frame
	await get_tree().process_frame
	instance.queue_free()
	print("      -> Scene freed.")
	current_scene_index += 1
	process_next_scene()


func is_already_cached() -> bool:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		return config.get_value("status", "version", "") == warmup_version
	return false

func save_cache_status():
	var config = ConfigFile.new()
	config.set_value("status", "version", warmup_version)
	config.save(SAVE_PATH)
	print("Status: [SAVED] Version ", warmup_version, " recorded.")

func finish_warmup():
	if temp_camera: temp_camera.queue_free()
	is_finished = true
	compilation_finished.emit()
	print("--- SHADER WARMUP COMPLETE ---")
	
	match transition_mode:
		TransitionMode.AUTO:
			execute_scene_switch()
		TransitionMode.MANUAL:
			print("WAITING: Press any key or click to continue...")
		TransitionMode.SIGNAL_ONLY:
			print("WAITING: External script will handle transition.")

func execute_scene_switch():
	if target_scene:
		print("Switching to Target: ", target_scene.resource_path.get_file())
		get_tree().change_scene_to_packed(target_scene)
	else:
		push_warning("No target scene set.")
