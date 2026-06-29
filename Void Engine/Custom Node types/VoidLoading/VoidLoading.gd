@tool
extends Control


@export var Loading : bool = false
@export var loading_scene: String = ""
@export var scene_change: String = ""
@export var loading_bar : ProgressBar

var progress : Array
var update : float = 0.0

func _ready():
	if Loading:
		ResourceLoader.load_threaded_request(loading_scene)
	else:
		var tween = create_tween()
		tween.tween_property(loading_bar, "value", 1, 1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(1.1).timeout
		get_tree().change_scene_to_file(scene_change)

func _process(delta):
	if Loading:
		ResourceLoader.load_threaded_get_status(loading_scene, progress)
		
		if progress[0] > update:
			update = progress[0]
		
		if loading_bar.value >= 1.0:
			if update >= 1.0:
				get_tree().change_scene_to_packed(
					ResourceLoader.load_threaded_get(loading_scene)
				)
				
		if loading_bar.value < update:
			loading_bar.value = lerp(loading_bar.value, update, delta)
		
		loading_bar.value += delta * 0.2 * \
			(3.0 if update >= 1.0 else clamp(0.9 - loading_bar.value, 0.0, 1.0))
