extends Node

var items_db = {}
var current_order = []

@warning_ignore("unused_signal")
signal item_found(id)
@warning_ignore("unused_signal")
signal item_pressed(id: int, tex_path: String, node: Node3D) 
signal bonus_cell_unlocked()

var is_dragging_item: bool = false 
var is_edit_mode: bool = false

var combo_score: int = 0
var combo_failed: bool = false

func _ready():
	load_items_from_data()

func load_items_from_data():
	var path = "res://Items/Data/"
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var res = load(path + file_name) as ItemData
				if res:
					var shape_data = res.get_shape() if res.has_method("get_shape") else res.shape.duplicate()
					items_db[res.id] = {
						"name": file_name.get_basename(),
						"texture": res.texture.resource_path if res.texture else "",
						"shape": shape_data 
					}
			file_name = dir.get_next()
	print("БАЗА ПРЕДМЕТОВ ЗАГРУЖЕНА: ", items_db.size(), " объектов")

func mark_item_as_found(item_id: int):
	if item_id == -1: return 
	
	var is_part_of_order = false
	var was_just_found = false
	
	for item in current_order:
		# Ищем предмет, который совпадает по ID и ЕЩЕ НЕ найден
		if item["id"] == item_id and not item["found"]:
			is_part_of_order = true
			item["found"] = true
			was_just_found = true
			item_found.emit(item_id)
			break # Важно! Прерываем цикл, чтобы за один раз отметить только ОДИН дубликат
	
	# Если мы не нашли нетронутый слот, значит либо это мусор, либо мы уже собрали все такие зелья
	if not is_part_of_order:
		# Проверяем, может игрок перетащил уже найденный предмет внутри рюкзака
		var is_already_packed = false
		for item in current_order:
			if item["id"] == item_id and item["found"]:
				is_already_packed = true
				break
				
		# Если это вообще левый предмет или лишний дубликат - срываем комбо
		if not is_already_packed:
			combo_failed = true
	else:
		# Если мы успешно нашли новый предмет заказа - растим комбо!
		if was_just_found and not combo_failed:
			combo_score += 1
			if combo_score == 2 or combo_score == 4 or combo_score == 5:
				bonus_cell_unlocked.emit()

func generate_new_order():
	current_order.clear()
	combo_score = 0
	combo_failed = false
	
	var all_ids = items_db.keys()
	if all_ids.size() == 0: 
		print("Внимание: база предметов пуста!")
		return
		
	# Генерируем 5 случайных предметов (они теперь могут повторяться!)
	for i in range(5):
		var random_id = all_ids[randi() % all_ids.size()]
		current_order.append({"id": random_id, "found": false})