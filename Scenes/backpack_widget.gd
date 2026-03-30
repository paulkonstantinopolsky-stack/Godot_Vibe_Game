extends Control

# Ссылка на фон рюкзака, который будем двигать
@onready var backpack_bg = $BackpackBG

# На сколько пикселей рюкзак будет уходить вниз перед появлением
var hide_pos_offset = 600 

func _ready():
	# Скрываем при старте, чтобы не мешал читать письмо
	hide()
	modulate.a = 0.0

# ТА САМАЯ ФУНКЦИЯ, КОТОРУЮ НЕ ВИДИТ ДВИЖОК
func start_appear_animation():
	print("--- ЗАПУСК АНИМАЦИИ РЮКЗАКА ---")
	
	show()
	# Убеждаемся, что модуляция на нуле
	modulate.a = 0.0
	
	# Запоминаем, где рюкзак должен стоять в итоге
	var final_y = backpack_bg.position.y
	# Временно опускаем его вниз (локально)
	backpack_bg.position.y += hide_pos_offset
	
	# Создаем Tween для плавного появления
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 1. Проявление прозрачности
	tw.tween_property(self, "modulate:a", 1.0, 0.5)
	
	# 2. Движение вверх к исходной точке
	tw.tween_property(backpack_bg, "position:y", final_y, 0.7)
	
	# 3. Легкий эффект "увеличения" для сочности
	backpack_bg.scale = Vector2(0.7, 0.7)
	# Ставим пивот в центр, чтобы увеличивался из середины (если забыли в редакторе)
	backpack_bg.pivot_offset = backpack_bg.size / 2
	tw.tween_property(backpack_bg, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK)

func try_add_item(item_id: int):
	# Логика добавления предмета (напишем на этапе Drag-and-Drop)
	print("Попытка добавить предмет: ", item_id)