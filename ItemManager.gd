extends Node

var items_db = {
	1: {"name": "Красное зелье", "texture": "res://Assets/Items/potion_red.png"},
	2: {"name": "Зеленое зелье", "texture": "res://Assets/Items/potion_green.png"},
	3: {"name": "Синее зелье",   "texture": "res://Assets/Items/potion_blue.png"},
	4: {"name": "Розовое зелье", "texture": "res://Assets/Items/potion_pink.png"},
	5: {"name": "Красное перо",  "texture": "res://Assets/Items/feather_red.png"},
	6: {"name": "Синее перо",    "texture": "res://Assets/Items/feather_blue.png"},
	7: {"name": "Книги",         "texture": "res://Assets/Items/books.png"}
}

var current_order = []
# --- СИГНАЛЫ ---
signal item_found(id)

# --- ФУНКЦИЯ ДЛЯ ВЫЗОВА ПРИ КЛИКЕ ---
func mark_item_as_found(item_id: int):
	for item in current_order:
		if item["id"] == item_id and not item["found"]:
			item["found"] = true
			item_found.emit(item_id) # Сигнал виджету: "Переворачивай!"
			print("ПРЕДМЕТ НАЙДЕН: ID ", item_id)
			break

func _ready():
	check_resources()

func check_resources():
	print("--- ПРОВЕРКА РЕСУРСОВ ---")
	for id in items_db:
		var path = items_db[id]["texture"]
		if not FileAccess.file_exists(path):
			print("!!! ОШИБКА: Файл НЕ найден: ", path)
		else:
			print("OK: ", path)

func generate_new_order():
	current_order.clear()
	var all_ids = items_db.keys()
	all_ids.shuffle()
	
	for i in range(5):
		current_order.append({"id": all_ids[i], "found": false})
	print("НОВЫЙ ЗАКАЗ СГЕНЕРИРОВАН")