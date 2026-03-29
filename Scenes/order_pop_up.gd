extends Control

@export var item_card_scene: PackedScene
@onready var items_grid = $LetterContainer/LetterPaper/Items

func fill_order_icons():
	# Очистка
	for child in items_grid.get_children():
		child.queue_free()
	
	# Создание иконок на основе ItemManager
	for order_data in ItemManager.current_order:
		if item_card_scene:
			var card = item_card_scene.instantiate()
			items_grid.add_child(card)
			# Достаем путь к текстуре из базы по ID
			var tex = ItemManager.items_db[order_data["id"]]["texture"]
			card.set_item(tex) # Передаем СТРОКУ (путь к файлу)
