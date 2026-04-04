extends Control

@onready var back = $Back
@onready var front = $Front

var current_tw: Tween
var item_id: int = -1

func setup(id: int, texture_path: String):
	item_id = id
	front.texture = load(texture_path)
	front.scale.x = 0 # Убеждаемся, что лицо скрыто
	back.scale.x = 1
	back.show()

# Функция красивого переворота карточки
func flip_to_front():
	if current_tw and current_tw.is_running():
		current_tw.kill()

	current_tw = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

	current_tw.tween_property(back, "scale:x", 0.0, 0.15)
	current_tw.tween_callback(back.hide)
	current_tw.tween_callback(front.show)
	current_tw.tween_property(front, "scale:x", 1.0, 0.15)