extends Node3D

var is_collected = false
var is_unlocked = false

func unlock():
	is_unlocked = true

	# Небольшая пауза (0.4 сек), чтобы игрок успел насладиться взрывом конфетти
	# и осознать награду, прежде чем она улетит
	get_tree().create_timer(0.4).timeout.connect(func():
		if not is_collected:
			is_collected = true
			collect_coin()
	)

func collect_coin():
	if not is_inside_tree(): return

	var main_scene = get_tree().current_scene

	# Ищем шкаф, поднимаясь по родителям
	var cabinet_node = get_parent()
	while cabinet_node != null and not cabinet_node.has_method("reveal_next_bonus_cell"):
		cabinet_node = cabinet_node.get_parent()

	if cabinet_node == null:
		printerr("ОШИБКА: Шкаф не найден! Анимация отменена.")
		is_collected = false
		return

	# Запоминаем колонку ДО того как перепривяжемся к main_scene.
	# Метаданные "cabinet_col" устанавливаются шкафом в reveal_next_bonus_cell.
	var my_col: int = -1
	var parent_cell = get_parent()
	if parent_cell and parent_cell.has_meta("cabinet_col"):
		my_col = parent_cell.get_meta("cabinet_col")

	# Вычисляем направление от центра шкафа к монетке (только по XZ).
	var direction_out = global_position - cabinet_node.global_position
	direction_out.y = 0
	if direction_out.length_squared() < 0.0001:
		direction_out = -global_basis.z
		direction_out.y = 0
	direction_out = direction_out.normalized()

	var out_distance = 1.2
	var final_out_pos = global_position + (direction_out * out_distance)

	# Сообщаем шкафу СРАЗУ — поворот к следующей монете начинается параллельно с анимацией
	if my_col >= 0 and is_instance_valid(cabinet_node) and cabinet_node.has_method("on_coin_collected"):
		cabinet_node.on_coin_collected(my_col)

	var tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Отрываем от шкафа (перепривязка к main_scene для свободного полёта)
	tw.tween_callback(func():
		var old_global_transform = global_transform
		if get_parent():
			get_parent().remove_child(self)
		main_scene.add_child(self)
		global_transform = old_global_transform
	)

	# Шаг 1: Быстро выдвигаем из ячейки
	tw.tween_property(self, "global_position", final_out_pos, 0.18)
	tw.tween_interval(0.1)

	# Шаг 2: Летим вверх с вращением
	var spin_degrees = 360.0
	var up_distance = 10.0
	tw.parallel().tween_property(self, "global_position:y", final_out_pos.y + up_distance, 1.2)
	tw.parallel().tween_property(self, "rotation_degrees:y", rotation_degrees.y + spin_degrees, 1.2).set_ease(Tween.EASE_IN_OUT)

	tw.tween_callback(queue_free)
