extends Control

var overlay: ColorRect
var popup_img: TextureRect
var _shader_mat: ShaderMaterial

func _ready() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	popup_img = TextureRect.new()
	popup_img.texture = load("res://Assets/UI/Perfect_Memory.png")
	popup_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	popup_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
	var vp := get_viewport_rect().size
	popup_img.position = (vp / 2.0) - popup_img.pivot_offset
	var base_y: float = popup_img.position.y

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(overlay, "color:a", 0.7, 0.5)
	tw.tween_property(popup_img, "scale", Vector2(1.1, 1.1), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tw.chain().tween_method(
		func(v: float): _shader_mat.set_shader_parameter("progress", v),
		0.0, 1.0, 0.6
	).set_trans(Tween.TRANS_SINE)

	for _i in range(3):
		tw.chain().tween_property(popup_img, "position:y", base_y - 15.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.chain().tween_property(popup_img, "position:y", base_y + 15.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tw.chain().tween_property(popup_img, "position:y", base_y, 0.25).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_interval(2.0)

	tw.parallel().tween_property(overlay, "color:a", 0.0, 0.3)
	tw.parallel().tween_property(popup_img, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		hide()
		on_complete.call()
		queue_free()
	)
