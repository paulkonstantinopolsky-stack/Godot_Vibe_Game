extends Node

signal item_unfound(id: int)

var items_db = {}
var current_order = []

@warning_ignore("unused_signal")
signal item_found(id)
@warning_ignore("unused_signal")
signal item_pressed(id: int, tex_path: String, node: Node3D)
signal level_completed()
signal perfect_clear_achieved()
signal combo_broken()
signal attempts_updated(attempts_left: int, is_correct: bool)
signal out_of_attempts()

var is_dragging_item: bool = false 
var is_edit_mode: bool = false

var combo_score: int = 0
var combo_failed: bool = false
var max_attempts: int = 8
var current_attempts: int = 8

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

# Все доступные формы паззла (порядок совпадает с ShapeType в item_data.gd)
const _ALL_SHAPES: Array = [
	[Vector2(0, 0)],
	[Vector2(0, 0), Vector2(0, 1)],
	[Vector2(0, 0), Vector2(0, 1), Vector2(0, 2)],
	[
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(0, 1),
		Vector2(1, 1),
	],
]

# Пул форм для спавна: по item_id — очередь фигур для заказа (по одной на слот заказа)
var _spawn_shape_pool: Dictionary = {}

# =================================================================

func _ready():
	load_items_from_data()

func load_items_from_data():
	var path = "res://Items/Data/"
	var dir = DirAccess.open(path)
	if dir == null:
		printerr("ItemManager: не удалось открыть папку данных предметов: ", path)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# В экспортированных сборках Godot может отдавать имена как *.tres.remap
			# (особенно в APK). Убираем суффикс перед проверкой расширения.
			var clean_name = file_name.trim_suffix(".remap")
			if clean_name.ends_with(".tres"):
				# Загружаем по "чистому" пути: Godot сам разрулит remap внутри экспорта.
				var res = load(path + clean_name) as ItemData
				if res:
					var shape_data = res.get_shape() if res.has_method("get_shape") else res.shape.duplicate()
					items_db[res.id] = {
						"name": clean_name.get_basename(),
						"texture": res.texture.resource_path if res.texture else "",
						"shape": shape_data
					}
		file_name = dir.get_next()
	print("БАЗА ПРЕДМЕТОВ ЗАГРУЖЕНА: ", items_db.size(), " объектов")

	# Кэшируем текстуры при старте игры, чтобы избежать фризов от load() во время геймплея
	for item_id in items_db.keys():
		if items_db[item_id].has("texture"):
			var tp: String = items_db[item_id]["texture"]
			if tp != "":
				items_db[item_id]["texture_res"] = load(tp)
			else:
				items_db[item_id]["texture_res"] = null

func reset_level_state() -> void:
	is_dragging_item = false
	is_edit_mode = false
	combo_score = 0
	combo_failed = false
	current_attempts = max_attempts
	attempts_updated.emit(current_attempts, false)

func mark_item_as_found(id: int) -> bool:
	var is_correct = false
	var target_item = null

	# 1. Заранее проверяем, правильный ли это предмет
	for item in current_order:
		if item["id"] == id and not item["found"]:
			is_correct = true
			target_item = item
			break

	# 2. Списываем попытку ЗНАЯ статус предмета
	if current_attempts > 0:
		current_attempts -= 1
		attempts_updated.emit(current_attempts, is_correct)
		if current_attempts == 0:
			out_of_attempts.emit()

	# 3. Применяем логику успеха
	if is_correct:
		target_item["found"] = true
		if not combo_failed:
			combo_score += 1
		item_found.emit(id)
		_check_order_completion()
		return true

	# 4. Логика провала (Игрок положил мусор)
	if not is_correct and not combo_failed:
		combo_failed = true
		combo_score = 0
		combo_broken.emit()

	return false

func unmark_item_as_found(id: int) -> void:
	for item in current_order:
		if item["id"] == id:
			if item["found"]:
				item["found"] = false

				# Откатываем счетчик только если комбо еще живо
				if not combo_failed:
					combo_score = maxi(0, combo_score - 1)

				item_unfound.emit(id)
			return

func _check_order_completion() -> void:
	var all_found := true
	for item in current_order:
		if not item["found"]:
			all_found = false
			break
	if all_found:
		level_completed.emit()
		if not combo_failed:
			perfect_clear_achieved.emit()

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
	const MAX_ATTEMPTS := 400
	for _attempt in range(MAX_ATTEMPTS):
		_spawn_shape_pool.clear()
		var shapes_to_pack: Array = []

		for item in current_order:
			var id: int = item["id"]
			var rs: Array = _rotate_shape_norm(_ALL_SHAPES[randi() % _ALL_SHAPES.size()], randi() % 4)
			shapes_to_pack.append(rs)
			if not _spawn_shape_pool.has(id):
				_spawn_shape_pool[id] = []
			_spawn_shape_pool[id].append(rs)

		shapes_to_pack.sort_custom(func(a, b): return a.size() > b.size())
		if _can_pack_greedy(shapes_to_pack):
			return

	print("ItemManager: не удалось найти вмещающуюся комбинацию, используем SINGLE/DOUBLE")
	_spawn_shape_pool.clear()
	for item in current_order:
		var id: int = item["id"]
		var rs: Array = _rotate_shape_norm(_ALL_SHAPES[randi() % 2], randi() % 4)
		if not _spawn_shape_pool.has(id):
			_spawn_shape_pool[id] = []
		_spawn_shape_pool[id].append(rs)

func get_shape_for_instance(item_id: int) -> Array:
	if _spawn_shape_pool.has(item_id) and _spawn_shape_pool[item_id].size() > 0:
		var s: Array = _spawn_shape_pool[item_id].pop_front()
		return s.duplicate()
	return _rotate_shape_norm(_ALL_SHAPES[randi() % _ALL_SHAPES.size()], randi() % 4).duplicate()

# Жадная проверка: пробуем разместить все формы по очереди в первый свободный слот.
# Дополнительно гарантируем минимальную суммарную площадь фигур заказа (чтобы «лёгкие»
# комбинации не проходили слишком часто — иначе мусор легко заполнит остаток).
func _can_pack_greedy(shapes: Array) -> bool:
	var total_cells: int = 0
	for s in shapes:
		total_cells += s.size()
	if total_cells < 7:
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
