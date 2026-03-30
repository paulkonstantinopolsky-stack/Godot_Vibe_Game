extends Control

@onready var backpack_bg = $BackpackBG
var hide_pos_offset = 600 

func _ready():
	hide()
	modulate.a = 0.0

func start_appear_animation():
	show()
	modulate.a = 0.0
	var final_y = backpack_bg.position.y
	backpack_bg.position.y += hide_pos_offset
	
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.5)
	tw.tween_property(backpack_bg, "position:y", final_y, 0.7)
	
	backpack_bg.pivot_offset = backpack_bg.size / 2
	backpack_bg.scale = Vector2(0.7, 0.7)
	tw.tween_property(backpack_bg, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK)

# --- ЛОГИКА ДОБАВЛЕНИЯ ПРЕДМЕТА ---
func try_add_item(item_id: int, mouse_pos: Vector2) -> bool:
	# 1. Пытаемся положить предмет в сетку
	var placed_successfully = _place_item_smartly(item_id, mouse_pos)
	
	if not placed_successfully:
		return false # Главная сцена поймет, что места нет, и отбросит предмет назад
		
	# 2. Если положили - проверяем, правильный ли это предмет
	var is_correct = false
	for task in ItemManager.current_order:
		if task["id"] == item_id and not task["found"]:
			is_correct = true
			break
	
	if is_correct:
		ItemManager.mark_item_as_found(item_id)
		print("Угадал! Карточка слева перевернута.")
	else:
		print("Предмет добавлен в рюкзак, но его нет в списке.")
		
	return true

# Умная функция вставки
func _place_item_smartly(item_id: int, mouse_pos: Vector2) -> bool:
	var tex_path = ItemManager.items_db[item_id]["texture"]
	var grid = $BackpackBG/CenterContainer/VBoxContainer
	var target_icon_node = null
	
	# ШАГ 1: Проверяем, отпустили ли мышку прямо над конкретной ПУСТОЙ ячейкой
	for row in grid.get_children():
		for cell in row.get_children():
			# Если курсор находится внутри границ этой конкретной ячейки
			if cell.get_global_rect().has_point(mouse_pos):
				var icon = cell.get_node("ItemIcon")
				if icon.texture == null or icon.texture.resource_path == "":
					target_icon_node = icon
				break # Нашли ячейку под мышкой, дальше эту строку не проверяем
		if target_icon_node: 
			break
			
	# ШАГ 2: Если отпустили просто над рюкзаком (не над пустой ячейкой) - ищем ПЕРВУЮ пустую
	if target_icon_node == null:
		for row in grid.get_children():
			for cell in row.get_children():
				var icon = cell.get_node("ItemIcon")
				if icon.texture == null or icon.texture.resource_path == "":
					target_icon_node = icon
					break
			if target_icon_node: 
				break

	# ШАГ 3: Если всё ещё null, значит рюкзак полностью забит
	if target_icon_node == null:
		return false 

	# ШАГ 4: Вставляем картинку в найденную ячейку
	target_icon_node.texture = load(tex_path)
	
	# Масштабируем, чтобы иконка не вылезала за рамки
	if target_icon_node is TextureRect:
		target_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		target_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
	target_icon_node.show() 
	
	# Анимация "бульк"
	target_icon_node.pivot_offset = target_icon_node.size / 2
	target_icon_node.scale = Vector2(0.2, 0.2)
	var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(target_icon_node, "scale", Vector2.ONE, 0.4)
	
	return true