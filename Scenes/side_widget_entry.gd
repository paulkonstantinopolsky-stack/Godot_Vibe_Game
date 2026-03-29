extends Control

@onready var back = $Back
@onready var front = $Front

var item_id: int = -1

func setup(id: int, texture_path: String):
	item_id = id
	front.texture = load(texture_path)
	front.scale.x = 0 # Убеждаемся, что лицо скрыто
	back.scale.x = 1
	back.show()

# Функция красивого переворота карточки
func flip_to_front():
	var tw = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	
	# 1. Схлопываем спинку (вопросик) до нуля
	tw.tween_property(back, "scale:x", 0.0, 0.15)
	
	# 2. Прячем спинку, показываем лицо (в момент, когда ширина = 0)
	tw.tween_callback(back.hide)
	tw.tween_callback(front.show)
	
	# 3. Разворачиваем лицо до нормального размера
	tw.tween_property(front, "scale:x", 1.0, 0.15)