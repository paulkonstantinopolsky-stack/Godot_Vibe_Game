extends Control

# Ссылка на сцену карточки (должна быть назначена в Инспекторе Godot!)
@export var item_card_scene: PackedScene

# Ссылка на узел, куда будут складываться иконки
@onready var items_grid = $LetterContainer/LetterPaper/Items

func fill_order_icons():
	# 1. Сначала полностью очищаем список от старых иконок
	for child in items_grid.get_children():
		child.queue_free()
	
	# 2. Создаем новые карточки на основе текущего заказа в ItemManager
	for order_data in ItemManager.current_order:
		# Проверяем, что сцена карточки привязана, чтобы не было вылета
		if item_card_scene:
			var card = item_card_scene.instantiate()
			items_grid.add_child(card)
			
			# Берем путь к текстуре из базы данных по ID предмета
			var tex_path = ItemManager.items_db[order_data["id"]]["texture"]
			
			# Вызываем функцию внутри карточки, чтобы поставить иконку
			card.set_item(tex_path)
