extends Control

@onready var icon = $ComboIcon
@onready var plate = $ComboPlate
@onready var label = $ComboPlate/ComboText
@onready var envelope = get_node_or_null("../SmallEnvelope")

var anim_tw: Tween
var is_active: bool = false
var plate_final_x: float = 0.0

var tex_plate_purple: Texture2D = load("res://Assets/2D/plate_purple.png")
var tex_plate_red: Texture2D = load("res://Assets/2D/plate_red.png")

func _ready() -> void:
	plate_final_x = plate.position.x

	hide()
	plate.modulate.a = 0.0
	icon.scale = Vector2.ZERO

func show_success(current: int, total: int) -> void:
	label.text = str(current) + "/" + str(total)
	plate.texture = tex_plate_purple
	_play_animation()

func show_fail() -> void:
	label.text = "COMBO FAILED"
	plate.texture = tex_plate_red
	_play_animation()

func _play_animation() -> void:
	show()
	is_active = true

	if anim_tw and anim_tw.is_valid():
		anim_tw.kill()

	if envelope:
		envelope.hide()
		envelope.modulate.a = 0.0

	icon.scale = Vector2.ZERO
	plate.position.x = icon.position.x
	plate.modulate.a = 0.0

	anim_tw = create_tween()

	anim_tw.tween_property(icon, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 2. Выезд плашки (возвращаем на сохранённую позицию из редактора)
	anim_tw.parallel().tween_property(plate, "position:x", plate_final_x, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	anim_tw.parallel().tween_property(plate, "modulate:a", 1.0, 0.2).set_delay(0.15)

	anim_tw.chain().tween_interval(3.0)

	anim_tw.chain().tween_property(plate, "position:x", icon.position.x, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	anim_tw.parallel().tween_property(plate, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	anim_tw.chain().tween_property(icon, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	anim_tw.chain().tween_callback(func():
		hide()
		is_active = false
		if envelope:
			envelope.show()
			var env_tw = create_tween()
			env_tw.tween_property(envelope, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_SINE)
	)
