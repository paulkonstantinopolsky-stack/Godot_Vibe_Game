extends Node

# База данных теперь заполняется автоматически
var items_db = {}
var current_order = []

signal item_found(id)
signal item_pressed(id: int, tex_path: String, node: Node3D) 

var is_dragging_item: bool = false 
var is_edit_mode: bool = false

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
					items_db[res.id] = {
						"name": file_name.get_basename(),
						"texture": res.texture.resource_path if res.texture else "",
						# ИЗМЕНЕНО: теперь мы вызываем функцию-генератор идеальных форм!
						"shape": res.get_shape() 
					}
			file_name = dir.get_next()
	print("БАЗА ПРЕДМЕТОВ ЗАГРУЖЕНА: ", items_db.size(), " объектов")

func mark_item_as_found(item_id: int):
	for item in current_order:
		if item["id"] == item_id and not item["found"]:
			item["found"] = true
			item_found.emit(item_id)
			break

func generate_new_order():
	current_order.clear()
	var all_ids = items_db.keys()
	if all_ids.size() < 5: 
		print("Внимание: предметов в базе меньше 5!")
	all_ids.shuffle()
	for i in range(min(5, all_ids.size())):
		current_order.append({"id": all_ids[i], "found": false})