extends Control

var overlay: ColorRect
var popup_img: TextureRect
var _shader_mat: ShaderMaterial

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.size = get_viewport_rect().size
	add_child(overlay)

	popup_img = TextureRect.new()
	popup_img.texture = load("res://Assets/UI/Perfect_Memory.png")
	popup_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	popup_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	popup_img.custom_minimum_size = Vector2(988, 982)
	popup_img.size = Vector2(988, 982)
	popup_img.pivot_offset = popup_img.size / 2.0
	popup_img.scale = Vector2.ZERO
	add_child(popup_img)

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = load("res://Shaders/glint.gdshader")
	_shader_mat.set_shader_parameter("progress", 0.0)
	popup_img.material = _shader_mat

	hide()

func play_animation(on_complete: Callable) -> void:
	show()
	var screen_size: Vector2 = get_viewport_rect().size
	overlay.size = screen_size
	popup_img.position = (screen_size / 2.0) - popup_img.pivot_offset

	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "color:a", 0.7, 0.4)
	tw.tween_property(popup_img, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(
		func(v: float): _shader_mat.set_shader_parameter("progress", v),
		0.0, 1.0, 0.6
	).set_trans(Tween.TRANS_SINE).set_delay(0.35)

	var start_y: float = popup_img.position.y
	var amp: float = 15.0
	var float_tw := create_tween().set_loops()
	float_tw.tween_property(popup_img, "position:y", start_y - amp, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(0.6)
	float_tw.tween_property(popup_img, "position:y", start_y + amp, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tw.tween_property(popup_img, "position:y", start_y, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	get_tree().create_timer(2.5).timeout.connect(func():
		if float_tw.is_valid():
			float_tw.kill()
		var outro := create_tween().set_parallel(true)
		outro.tween_property(overlay, "color:a", 0.0, 0.2)
		outro.tween_property(popup_img, "scale", Vector2.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		outro.chain().tween_callback(func():
			hide()
			on_complete.call()
			queue_free()
		)
	)
