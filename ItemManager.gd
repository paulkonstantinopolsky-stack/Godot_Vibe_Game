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

# =================================================================
# ГЕОМЕТРИЯ РЮКЗАКА (для проверки вместимости при генерации форм)
# =================================================================
# Сетка 4×4 = 16 позиций, 4 угловые заблокированы Spacer-нодами → 12 реальных ячеек
const _BP_COLS: int = 4
const _BP_ROWS: int = 4
const _BP_BLOCKED: Array = [
	Vector2i(0, 0), Vector2i(3, 0),
	Vector2i(0, 3), Vector2i(3, 3)
]

# Все доступные формы паззла (индекс соответствует ShapeType в item_data.gd)
const _ALL_SHAPES: Array = [
	[Vector2(0, 0)],                                                           # SINGLE   (1 кл.)
	[Vector2(0, 0), Vector2(0, 1)],                                            # DOUBLE_V (2 кл.)
	[Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)],                             # CORNER_L (3 кл.)
	[Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)],              # SQUARE   (4 кл.)
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(2, 1)],              # ZIGZAG   (4 кл.)
]

# =================================================================

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
		if item["id"] == item_id and not item["found"]:
			is_part_of_order = true
			item["found"] = true
			was_just_found = true
			item_found.emit(item_id)
			break
	
	if not is_part_of_order:
		var is_already_packed = false
		for item in current_order:
			if item["id"] == item_id and item["found"]:
				is_already_packed = true
				break
		if not is_already_packed:
			combo_failed = true
	else:
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
		
	# Генерируем 5 случайных предметов (могут повторяться)
	for i in range(5):
		var random_id = all_ids[randi() % all_ids.size()]
		current_order.append({"id": random_id, "found": false})
	
	# Назначаем рандомные формы всем предметам в базе,
	# гарантируя что 5 предметов из заказа влезут в рюкзак
	_assign_random_shapes()

# =================================================================
# УМНЫЙ РАНДОМ ФОРМ
# =================================================================

func _assign_random_shapes() -> void:
	# Собираем уникальные ID предметов из заказа
	var order_ids: Array = []
	for item in current_order:
		if not item["id"] in order_ids:
			order_ids.append(item["id"])
	
	const MAX_ATTEMPTS := 400
	var assigned_shapes: Dictionary = {}  # id → shape

	for _attempt in range(MAX_ATTEMPTS):
		assigned_shapes.clear()

		# Случайно назначаем форму каждому уникальному ID заказа
		for id in order_ids:
			assigned_shapes[id] = _ALL_SHAPES[randi() % _ALL_SHAPES.size()].duplicate()

		# Строим список форм для 5 слотов заказа (учитываем повторения одного ID)
		var shapes_to_pack: Array = []
		for item in current_order:
			shapes_to_pack.append(assigned_shapes[item["id"]])

		# Сортируем largest-first — точно так же как auto_fill_and_optimize,
		# чтобы валидация и реальная расстановка использовали один и тот же порядок.
		shapes_to_pack.sort_custom(func(a, b): return a.size() > b.size())
		if _can_pack_greedy(shapes_to_pack):
			# Применяем найденные формы
			for id in assigned_shapes:
				items_db[id]["shape"] = assigned_shapes[id]
			# Рандомизируем формы для остальных предметов (не в заказе)
			for id in items_db:
				if not id in assigned_shapes:
					items_db[id]["shape"] = _ALL_SHAPES[randi() % _ALL_SHAPES.size()].duplicate()
			return

	# Fallback: если за 400 попыток не нашли — назначаем минимальные формы заказу
	print("ItemManager: не удалось найти вмещающуюся комбинацию, используем SINGLE/DOUBLE")
	for id in order_ids:
		items_db[id]["shape"] = _ALL_SHAPES[randi() % 2].duplicate()  # SINGLE или DOUBLE_V
	for id in items_db:
		if not id in order_ids:
			items_db[id]["shape"] = _ALL_SHAPES[randi() % _ALL_SHAPES.size()].duplicate()

# Жадная проверка: пробуем разместить все формы по очереди в первый свободный слот.
# Дополнительно гарантируем, что предметы заказа занимают не менее 10 из 12 ячеек
# → после правильной расстановки остаётся ≤2 клеток, и мусорные предметы туда не влезут.
func _can_pack_greedy(shapes: Array) -> bool:
	var total_cells: int = 0
	for s in shapes:
		total_cells += s.size()
	if total_cells < 10:
		return false  # Слишком мало — мусор может легко заполнить остаток

	var grid: Dictionary = {}
	for r in range(_BP_ROWS):
		for c in range(_BP_COLS):
			if not Vector2i(c, r) in _BP_BLOCKED:
				grid[Vector2i(c, r)] = true

	for shape in shapes:
		if not _greedy_place(shape, grid):
			return false
	return true

# Пробует разместить shape (с перебором ротаций и позиций).
# При успехе занимает клетки в grid и возвращает true.
func _greedy_place(shape: Array, grid: Dictionary) -> bool:
	for rot in range(4):
		var rotated: Array = _rotate_shape_norm(shape, rot)
		for r in range(_BP_ROWS):
			for c in range(_BP_COLS):
				var cells: Array = []
				var ok := true
				for offset in rotated:
					var cell := Vector2i(c + int(offset.x), r + int(offset.y))
					if not grid.has(cell):
						ok = false
						break
					cells.append(cell)
				if ok:
					for cell in cells:
						grid.erase(cell)
					return true
	return false

# Поворот формы на rot*90° с нормализацией к началу координат
func _rotate_shape_norm(shape: Array, rot: int) -> Array:
	var result: Array = shape.duplicate()
	for _i in range(rot % 4):
		var temp: Array = []
		for p in result:
			temp.append(Vector2(-p.y, p.x))
		var min_x: float = temp[0].x
		var min_y: float = temp[0].y
		for p in temp:
			if p.x < min_x: min_x = p.x
			if p.y < min_y: min_y = p.y
		result = []
		for p in temp:
			result.append(p - Vector2(min_x, min_y))
	return result