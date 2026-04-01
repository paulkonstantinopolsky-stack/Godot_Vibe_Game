extends Control

# Ссылка на сцену карточки (должна быть назначена в Инспекторе Godot!)
@export var item_card_scene: PackedScene

# Ссылка на узел, куда будут складываться иконки
@onready var items_grid = $LetterContainer/LetterPaper/Items

func fill_order_icons():
	# 1. ПРАВИЛЬНАЯ ОЧИСТКА: Сначала отрываем от дерева, потом удаляем
	for child in items_grid.get_children():
		items_grid.remove_child(child)
		child.queue_free()
	
	# 2. Создаем новые карточки на основе текущего заказа
	for order_data in ItemManager.current_order:
		if item_card_scene:
			var card = item_card_scene.instantiate()
			items_grid.add_child(card)
			
			var tex_path = ItemManager.items_db[order_data["id"]]["texture"]
			card.set_item(tex_path)