@tool
extends EditorPlugin

const plugin_data_filename = "/plugin_data.cfg"
const Void_WhiteVoid_anticheat = "Void_WhiteVoidAntiCheat"
var main_panel_instance

func _enter_tree() -> void:
	main_panel_instance = preload("res://addons/Void Engine/Custom Node types/VoidForge/VoidForge.gd").new()
	EditorInterface.get_editor_main_screen().add_child(main_panel_instance)
	_make_visible(false)
	
	add_autoload_singleton("VoidEngine", "res://addons/Void Engine/VoidEngine.gd")
	add_autoload_singleton("WhiteVoid_AntiCheat", "res://addons/Void Engine/WhiteVoid AntiCheat/WhiteVoid AntiCheat.gd")
	add_autoload_singleton("ModeManager", "res://addons/Void Engine/Custom Node types/VoidNetworking/VoidWebRTC/ModeManager.gd")
	add_custom_type("VoidAnimationPlayer", "AnimationPlayer", preload("res://addons/Void Engine/Custom Node types/VoidAnimationPlayer/VoidAnimationPlayer.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidLoading", "Control", preload("res://addons/Void Engine/Custom Node types/VoidLoading/VoidLoading.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidRigidBody", "RigidBody3D", preload("res://addons/Void Engine/Custom Node types/VoidRigidBody/VoidRigidBody.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidPlayerSynchronizer", "Node", preload("res://addons/Void Engine/Custom Node types/VoidPlayerSynchronizer/VoidPlayerSynchronizer.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidTrigger", "Area3D", preload("res://addons/Void Engine/Custom Node types/VoidTrigger/VoidTrigger.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidTextureStreaming", "MeshInstance3D", preload("res://addons/Void Engine/Custom Node types/VoidTextureStreaming/VoidTextureStreaming.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidSpotlight", "SpotLight3D", preload("res://addons/Void Engine/Custom Node types/VoidSpotlight/VoidSpotlight.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidShaderCompiler", "Node3D", preload("res://addons/Void Engine/Custom Node types/VoidShaderCompiler/VoidShaderCompiler.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidRngRoomGenerator", "Node3D", preload("res://addons/Void Engine/Custom Node types/VoidRNGRooms/VoidRngRoomGenerator.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidRNGRoomsStarter", "Node3D", preload("res://addons/Void Engine/Custom Node types/VoidRNGRooms/VoidRNGRoomsStarter.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidNet", "Node3D", preload("res://addons/Void Engine/Custom Node types/VoidNetworking/VoidWebRTC/VoidNet.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidAudioPlayer3D", "AudioStreamPlayer3D", preload("res://addons/Void Engine/Custom Node types/VoidAudioPlayer3D/VoidAudioPlayer3D.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidDynamicResolution", "Node", preload("res://addons/Void Engine/Custom Node types/VoidDynamicResolution/VoidDynamicResolution.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidOmniDirectionalSystem", "Node", preload("res://addons/Void Engine/Custom Node types/VoidOmniDirectionalSystem/VoidOmniDirectionalSystem.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidPathFollow", "PathFollow3D", preload("res://addons/Void Engine/Custom Node types/VoidPathFollow/VoidPathFollow.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidRandomNodeInstantiator", "Node3D", preload("res://addons/Void Engine/Custom Node types/VoidRandomNodeInstantiator/VoidRandomNodeInstantiator.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidOmniLight", "OmniLight3D", preload("res://addons/Void Engine/Custom Node types/VoidOmniLight/VoidOmniLight.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))
	add_custom_type("VoidNodeInstantiator", "Node3D", preload("res://addons/Void Engine/Custom Node types/VoidNodeInstantiator/VoidNodeInstantiator.gd"), preload("res://addons/Void Engine/assets/Void icon.png"))


func _exit_tree() -> void:
	if main_panel_instance:
		main_panel_instance.queue_free()
	
	remove_autoload_singleton("VoidEngine")
	remove_autoload_singleton("WhiteVoid_AntiCheat")
	remove_autoload_singleton("ModeManager")
	remove_custom_type("VoidAnimationPlayer")
	remove_custom_type("VoidLoading")
	remove_custom_type("VoidRigidBody")
	remove_custom_type("VoidTrigger")
	remove_custom_type("VoidPlayerSynchronizer")
	remove_custom_type("VoidAnimationPlayer")
	remove_custom_type("VoidTextureStreaming")
	remove_custom_type("VoidSpotlight")
	remove_custom_type("VoidShaderCompiler")
	remove_custom_type("VoidRngRoomGenerator")
	remove_custom_type("VoidRNGRoomsStarter")
	remove_custom_type("VoidNet")
	remove_custom_type("VoidAudioPlayer3D")
	remove_custom_type("VoidDynamicResolution")
	remove_custom_type("VoidOmniDirectionalSystem")
	remove_custom_type("VoidPathFollow")
	remove_custom_type("VoidRandomNodeInstantiator")
	remove_custom_type("VoidOmniLight")
	remove_custom_type("VoidNodeInstantiator")



func _has_main_screen(): return true
func _make_visible(visible): if main_panel_instance: main_panel_instance.visible = visible
func _get_plugin_name(): return "VoidForge"
