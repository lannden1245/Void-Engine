@tool
extends Node

## @description Advanced DRS, MSAA/TAA, and Post-Processing (Sharp/Soft/G-Sync) manager.

@export_group("=== Target & Limits ===")
@export var target_fps: float = 60.0
@export_range(0.1, 0.9, 0.05) var min_resolution_scale: float = 0.5:
	set(value):
		min_resolution_scale = value
		if resolution_scale < min_resolution_scale: resolution_scale = min_resolution_scale

@export_range(0.5, 1.0, 0.05) var max_resolution_scale: float = 1.0:
	set(value):
		max_resolution_scale = value
		if resolution_scale > max_resolution_scale: resolution_scale = max_resolution_scale

@export_group("=== Scaling Behavior ===")
@export_range(0.1, 1.0, 0.05) var resolution_scale: float = 1.0:
	set(value):
		resolution_scale = clampf(value, min_resolution_scale, max_resolution_scale)
		_current_applied_scale = resolution_scale 
		_apply_viewport_settings()

@export var dynamic_resolution_enabled: bool = true:
	set(value):
		dynamic_resolution_enabled = value

@export_range(0.01, 0.5, 0.01) var resolution_drop_amount: float = 0.15
@export_range(0.01, 0.2, 0.01) var resolution_recover_amount: float = 0.05
@export_range(1.0, 10.0, 0.5) var resolution_transition_speed: float = 4.0

@export_group("=== Anti-Aliasing ===")
@export_enum("Disabled", "MSAA 2x", "MSAA 4x", "MSAA 8x", "TAA (Temporal)") var aa_mode: int = 0:
	set(value):
		aa_mode = value
		_apply_viewport_settings()

@export_group("=== Post-Processing: Sharpener & Softener ===")
@export_range(0.0, 2.0, 0.05) var sharpness_strength: float = 0.5:
	set(value):
		sharpness_strength = value
		_update_shader_uniforms()

@export_range(0.0, 1.0, 0.05) var softness_strength: float = 0.0:
	set(value):
		softness_strength = value
		_update_shader_uniforms()

@export_group("=== Post-Processing: G-Sync / ULMB Strobe ===")
# Customizable down to 45Hz as requested.
@export_range(45.0, 240.0, 1.0) var strobe_refresh_hz: float = 120.0:
	set(value):
		strobe_refresh_hz = value
		_update_shader_uniforms()

# How aggressively the backlight "turns off" to reduce motion blur. 0.0 = Off, 1.0 = Max Clarity (Darker).
@export_range(0.0, 1.0, 0.05) var strobe_intensity: float = 0.0:
	set(value):
		strobe_intensity = value
		_update_shader_uniforms()

# Internal variables
var _frame_count: int = 0
var _time_accumulator: float = 0.0
var _vp: Viewport = null
var _current_applied_scale: float = 1.0
var _color_rect: ColorRect = null
var _shader_mat: ShaderMaterial = null

const POST_PROCESS_SHADER: String = """
shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Godot 4.6 Requirement: Explicitly declare SCREEN_TEXTURE
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

uniform float sharpness_strength;
uniform float softness_strength;
uniform float strobe_refresh_hz;
uniform float strobe_intensity;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 col = texture(SCREEN_TEXTURE, uv).rgb;

	// 1. SOFTENER (Gaussian Blur for Anti-Aliasing smoothing)
	if (softness_strength > 0.0) {
		vec3 blur = vec3(0.0);
		float total = 0.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				float weight = exp(-float(x*x + y*y) / 2.0);
				blur += texture(SCREEN_TEXTURE, uv + vec2(float(x), float(y)) * px).rgb * weight;
				total += weight;
			}
		}
		col = mix(col, blur / total, softness_strength);
	}

	// 2. SHARPENER (Unsharp Mask)
	if (sharpness_strength > 0.0) {
		vec3 blur = vec3(0.0);
		float total = 0.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				float weight = exp(-float(x*x + y*y) / 2.0);
				blur += texture(SCREEN_TEXTURE, uv + vec2(float(x), float(y)) * px).rgb * weight;
				total += weight;
			}
		}
		// Add the difference between original and blurred back to the original
		col += (col - (blur / total)) * sharpness_strength;
	}

	// 3. G-SYNC / ULMB STROBE SIMULATION (Motion Clarity)
	// Simulates backlight strobing to reduce perceived motion blur.
	if (strobe_intensity > 0.0) {
		float pulse = fract(TIME * strobe_refresh_hz);
		// Create a sharp pulse: '1' for most of the frame, '0' for a brief moment
		float strobe_mask = smoothstep(0.0, 0.1, pulse) * smoothstep(1.0, 0.9, pulse);
		
		// Darken the 'off' phase of the strobe to mimic ULMB backlight behavior
		col = mix(col * (1.0 - strobe_intensity), col, strobe_mask);
	}

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
"""

func _ready() -> void:
	_vp = get_viewport()
	_current_applied_scale = resolution_scale
	_setup_post_processing()
	_apply_viewport_settings()

func _setup_post_processing() -> void:
	# Create a CanvasLayer to ensure this draws OVER the 3D world
	var canvas = CanvasLayer.new()
	canvas.layer = 100 
	add_child(canvas)

	# Create the ColorRect
	_color_rect = ColorRect.new()
	_color_rect.anchors_preset = Control.PRESET_FULL_RECT
	_color_rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_color_rect.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	# CRITICAL SAFETY: Set base color to transparent. 
	# If the shader fails to compile, this node becomes invisible instead of a grey box.
	_color_rect.color = Color(0, 0, 0, 0) 
	canvas.add_child(_color_rect)

	# Build Shader
	var shader = Shader.new()
	shader.code = POST_PROCESS_SHADER
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_color_rect.material = _shader_mat
	
	_update_shader_uniforms()

func _update_shader_uniforms() -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("sharpness_strength", sharpness_strength)
		_shader_mat.set_shader_parameter("softness_strength", softness_strength)
		_shader_mat.set_shader_parameter("strobe_refresh_hz", strobe_refresh_hz)
		_shader_mat.set_shader_parameter("strobe_intensity", strobe_intensity)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if not dynamic_resolution_enabled:
		return

	_frame_count += 1
	_time_accumulator += delta

	# 1-Second Consistency Check
	if _time_accumulator >= 1.0:
		var avg_fps = float(_frame_count) / _time_accumulator
		_evaluate_performance(avg_fps)
		_frame_count = 0
		_time_accumulator = 0.0

	# Smooth Resolution Transition
	if abs(_current_applied_scale - resolution_scale) > 0.0001:
		_current_applied_scale = lerp(_current_applied_scale, resolution_scale, resolution_transition_speed * delta)
		if _vp:
			_vp.scaling_3d_scale = _current_applied_scale

func _evaluate_performance(avg_fps: float) -> void:
	var changed: bool = false

	if avg_fps < target_fps:
		var deficit_ratio = (target_fps - avg_fps) / target_fps
		var drop = resolution_drop_amount * deficit_ratio
		var new_scale = resolution_scale - drop
		if new_scale < min_resolution_scale: new_scale = min_resolution_scale
		if abs(new_scale - resolution_scale) > 0.001:
			resolution_scale = new_scale
			changed = true
	elif avg_fps > target_fps * 1.05:
		var recovery = resolution_recover_amount
		var new_scale = resolution_scale + recovery
		if new_scale > max_resolution_scale: new_scale = max_resolution_scale
		if abs(new_scale - resolution_scale) > 0.001:
			resolution_scale = new_scale
			changed = true

func _apply_viewport_settings() -> void:
	if not _vp:
		_vp = get_viewport()
		if not _vp: return
	
	var target_msaa: int = Viewport.MSAA_DISABLED
	var use_taa: bool = false

	match aa_mode:
		0: target_msaa = Viewport.MSAA_DISABLED; use_taa = false
		1: target_msaa = Viewport.MSAA_2X; use_taa = false
		2: target_msaa = Viewport.MSAA_4X; use_taa = false
		3: target_msaa = Viewport.MSAA_8X; use_taa = false
		4: target_msaa = Viewport.MSAA_DISABLED; use_taa = true # TAA

	if _vp.scaling_3d_scale != _current_applied_scale:
		_vp.scaling_3d_scale = _current_applied_scale
	if _vp.msaa_3d != target_msaa:
		_vp.msaa_3d = target_msaa
	if _vp.use_taa != use_taa:
		_vp.use_taa = use_taa
