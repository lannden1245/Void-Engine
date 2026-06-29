@tool
extends SpotLight3D

@export var PC_Shadows : bool = false
@export var Mobile_Shadows : bool = false
var Light_Shadows = VoidEngine.Light_Shadows

func _ready() -> void:
	var platform = OS.get_name()
	
	if Light_Shadows == true:
		shadow_enabled = true
	
	if Light_Shadows == false:
		match platform:
			"Windows":
				if PC_Shadows == true:
					shadow_enabled = true
					
				if PC_Shadows == false:
					shadow_enabled = false
					
			"Linux", "FreeBSD", "NetBSD":
				if PC_Shadows == true:
					shadow_enabled = true
					
				if PC_Shadows == false:
					shadow_enabled = false
					
			"macOS":
				if PC_Shadows == true:
					shadow_enabled = true
					
				if PC_Shadows == false:
					shadow_enabled = false
					
			"Android":
				if Mobile_Shadows == true:
					shadow_enabled = true
					
				if Mobile_Shadows == false:
					shadow_enabled = false
					
			"iOS":
				if Mobile_Shadows == true:
					shadow_enabled = true
					
				if Mobile_Shadows == false:
					shadow_enabled = false
					
			"Web":
				if PC_Shadows == true:
					shadow_enabled = true
					
				if PC_Shadows == false:
					shadow_enabled = false
