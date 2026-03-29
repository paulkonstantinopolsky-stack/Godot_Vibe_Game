extends VBoxContainer

# Проверь, чтобы путь к сцене карточки в кавычках был верным!
@export var card_scene: PackedScene = preload("res://Scenes/item_card_widget.tscn")

func build_widget():
	# Очистка
	for child in get_children():
		child.queue_free()
	
	# Раскладываем карточки
	for i in range(ItemManager.current_order.size()):
		var order_entry = ItemManager.current_order[i]
		var card = card_scene.instantiate()
		add_child(card)
		
		# Теперь вызываем set_item
		card.set_item(order_entry["id"]) 
		card.animate_arrival(i * 0.15)

func try_reveal_item(item_id: int):
	for card in get_children():
		if card.my_item_id == item_id and not card.is_revealed:
			card.reveal()
			return true
	return false