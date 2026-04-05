extends Control

signal cascade_finished

const GamePaletteResource = preload("res://game_palette.gd")
var palette: GamePaletteResource

@export_group("Drag Preview")
@export var drag_smooth_speed: float = 25.0
@export var drag_pointer_offset: Vector2 = Vector2(0, -120)

@export_group("Backpack Magnetism")
@export var magnet_enabled: bool = true
@export var magnet_max_offset: float = 120.0 # Выдвигаем рюкзак дальше (было 60)
@export var magnet_smoothness: float = 12.0
@export var magnet_scale_bump: float = 1.08 # Увеличиваем сильнее (было 1.02)
@export var magnet_max_rotation: float = 2.0

@export_group("Grid Magnetism")
@export var grid_catch_radius: float = 120.0 # Дистанция захвата снаружи
@export var grid_release_radius: float = 220.0 # Сила удержания (натяжение резинки)
@export var fast_snap_multiplier: float = 3.5 # Сила рывка при первом попадании в сетку

const BACKPACK_CLOSING_SCENE = preload("res://Scenes/backpack_closing_sequence.tscn")

@export var seq_visual_offset: Vector2 = Vector2(10.0, -270.0)
@export var seq_visual_scale_multiplier: float = 0.99
# НОВАЯ ПЕРЕМЕННАЯ:
@export var final_flight_y_offset: float = 600.0 # Стартуем с бОльшего значения

var is_order_completed = false
var closing_sequence_node = null
var is_cascading: bool = false

## Целевой центр рюкзака (глобальные координаты) и масштаб для lerp
var target_bg_pos: Vector2 = Vector2.ZERO
var target_bg_scale: Vector2 = Vector2.ONE
## Сохранённый центр покоя (глобально)
var original_bg_pos: Vector2 = Vector2.ZERO
var original_bg_scale: Vector2 = Vector2.ONE

var _current_snap_speed_mult: float = 1.0

@onready var backpack_bg = $BackpackBG
@onready var grid = $BackpackBG/CenterContainer/GridContainer 
@onready var edit_menu = get_node_or_null("EditMenu") 

var default_edit_menu_pos: Vector2 = Vector2.ZERO
var hide_pos_offset = 600 

var active_cell: Control = null
var active_item_id: int = -1
var active_drag_node: Node3D = null
var active_shape: Array = []

var is_dragging_internal: bool = false
var drag_preview_container: Control

var target_preview_pos: Vector2 = Vector2.ZERO
var bg_base_pos: Vector2 = Vector2.ZERO
var bg_base_scale: Vector2 = Vector2.ONE
var bg_base_rot: float = 0.0
var is_magnet_ready: bool = false # Блокирует магнит во время анимации появления
var is_preview_snapped: bool = false
var _snapped_root_cell: Control = null
var mag_frozen_pos: Vector2 = Vector2.ZERO
var mag_frozen_scale: Vector2 = Vector2.ONE
var mag_frozen_rot: float = 0.0
var is_backpack_frozen: bool = false
## Форма текущего превью (для магнита и проверки ячейки)
var _drag_preview_shape: Array = []

func _ready():
	if ResourceLoader.exists("res://game_palette.tres"):
		palette = load("res://game_palette.tres")
	else:
		palette = GamePaletteResource.new()

	hide()
	modulate.a = 0.0
	
	if edit_menu:
		default_edit_menu_pos = edit_menu.position
		edit_menu.hide()
		if edit_menu.has_node("BtnRotate"): edit_menu.get_node("BtnRotate").pressed.connect(_on_btn_rotate)
		if edit_menu.has_node("BtnConfirm"): edit_menu.get_node("BtnConfirm").pressed.connect(_on_btn_confirm)
		if edit_menu.has_node("BtnCancel"): edit_menu.get_node("BtnCancel").pressed.connect(_on_btn_cancel)
	
	_setup_drag_preview()
	grid.draw.connect(_on_grid_draw)
	_update_grid_visuals()

func _backpack_global_center_from_local_top_left(local_tl: Vector2, scale_vec: Vector2) -> Vector2:
	var p = backpack_bg.get_parent()
	var tl_global = p.global_position + local_tl
	return tl_global + backpack_bg.size * scale_vec / 2.0

func _update_edit_mode_targets() -> void:
	if grid.get_child_count() == 0:
		return
	var view_size = get_viewport_rect().size

	if is_order_completed:
		target_bg_pos = (view_size / 2.0) + Vector2(0, final_flight_y_offset)
		target_bg_scale = Vector2(1.1, 1.1)
	elif ItemManager.is_edit_mode:
		target_bg_pos = view_size / 2.0
		target_bg_scale = Vector2(1.1, 1.1)
	else:
		target_bg_pos = original_bg_pos
		target_bg_scale = original_bg_scale

func _process(delta: float) -> void:
	# 1. Логика превью
	if drag_preview_container and drag_preview_container.visible:
		_current_snap_speed_mult = lerpf(_current_snap_speed_mult, 1.0, 15.0 * delta)
		var weight: float = clampf(drag_smooth_speed * _current_snap_speed_mult * delta, 0.0, 1.0)

		# СИНХРОНИЗАЦИЯ МАСШТАБА: Паззл растет пропорционально рюкзаку
		if bg_base_scale != Vector2.ZERO:
			var relative_bg_scale = backpack_bg.scale / bg_base_scale
			drag_preview_container.scale = drag_preview_container.scale.lerp(relative_bg_scale, weight)

		drag_preview_container.global_position = drag_preview_container.global_position.lerp(
			target_preview_pos, weight)

	# 2. Логика магнетизма рюкзака
	if not magnet_enabled or not is_magnet_ready:
		return

	_update_edit_mode_targets()

	var tgt_center_global = target_bg_pos
	var tgt_scale = target_bg_scale
	var tgt_rot = bg_base_rot

	if not is_order_completed and ItemManager.is_dragging_item and not is_dragging_internal and drag_preview_container.visible:
		var bg_rect = backpack_bg.get_global_rect().grow(20.0)

		var real_mouse_pos = get_global_mouse_position()
		var is_over_bg = bg_rect.has_point(real_mouse_pos)

		if is_over_bg:
			if not is_backpack_frozen:
				is_backpack_frozen = true
				var targets = _calculate_current_magnet_targets()
				mag_frozen_pos = targets.pos
				mag_frozen_scale = targets.scale
				mag_frozen_rot = targets.rot

			tgt_center_global = _backpack_global_center_from_local_top_left(mag_frozen_pos, mag_frozen_scale)
			tgt_scale = mag_frozen_scale
			tgt_rot = mag_frozen_rot
		else:
			if is_backpack_frozen:
				is_backpack_frozen = false

			var targets = _calculate_current_magnet_targets()
			tgt_center_global = _backpack_global_center_from_local_top_left(targets.pos, targets.scale)
			tgt_scale = targets.scale
			tgt_rot = targets.rot

	elif ItemManager.is_edit_mode:
		is_preview_snapped = false
		_snapped_root_cell = null
		is_backpack_frozen = false

	else:
		is_preview_snapped = false
		_snapped_root_cell = null
		is_backpack_frozen = false

	if not is_order_completed:
		var move_speed = 10.0
		backpack_bg.global_position = backpack_bg.global_position.lerp(
			tgt_center_global - (backpack_bg.size * backpack_bg.scale / 2.0), delta * move_speed)
		backpack_bg.scale = backpack_bg.scale.lerp(tgt_scale, delta * move_speed)
	var m_weight = clampf(magnet_smoothness * delta, 0.0, 1.0)
	backpack_bg.rotation_degrees = lerpf(backpack_bg.rotation_degrees, tgt_rot, m_weight)

	if drag_preview_container.visible:
		drag_preview_container.rotation_degrees = backpack_bg.rotation_degrees

	# СИНХРОНИЗАЦИЯ НОВОГО УЗЛА (Центр к Центру)
	if closing_sequence_node and is_instance_valid(closing_sequence_node):
		closing_sequence_node.size = backpack_bg.size
		closing_sequence_node.scale = backpack_bg.scale * seq_visual_scale_multiplier

		var bg_center = backpack_bg.global_position + (backpack_bg.size * backpack_bg.scale / 2.0)
		var seq_offset = (closing_sequence_node.size * closing_sequence_node.scale) / 2.0
		closing_sequence_node.global_position = bg_center - seq_offset + seq_visual_offset

	if edit_menu and edit_menu.visible:
		var current_bg_offset: Vector2 = backpack_bg.position - bg_base_pos
		edit_menu.position = default_edit_menu_pos + current_bg_offset

# ==========================================================
# --- АЛГОРИТМ АВТО-СБОРКИ (BIN PACKING) ---
# ==========================================================
func auto_fill_and_optimize(new_items_data: Array) -> Array:
	_close_edit_mode()

	var existing_items = []
	var wrong_items_to_return = []
	var processed_roots = []

	# 1. Считаем лимиты: сколько ПРАВИЛЬНЫХ предметов уже лежит в рюкзаке
	var valid_counts = {}
	for task in ItemManager.current_order:
		if task["found"]:
			valid_counts[task["id"]] = valid_counts.get(task["id"], 0) + 1

	# 2. Ревизия рюкзака: отделяем правильные предметы от мусора
	for cell in grid.get_children():
		if not cell.has_node("ItemIcon"): continue
		var item_id = cell.get_meta("occupied_by_id", -1)
		if item_id != -1:
			var root = cell.get_meta("root_cell")
			if not processed_roots.has(root):
				processed_roots.append(root)

				var is_correct = false
				if valid_counts.get(item_id, 0) > 0:
					is_correct = true
					valid_counts[item_id] -= 1 # Списываем со счета легальных

				if is_correct:
					existing_items.append({
						"id": item_id,
						"old_root": root,
						"old_shape": root.get_meta("current_shape"),
						"old_rot": root.get_meta("rot_deg", 0)
					})
				else:
					# Этот предмет лишний или вообще не из заказа!
					wrong_items_to_return.append({
						"id": item_id,
						"pos": root.global_position + (root.size / 2.0),
						"drag_node": root.get_meta("source_drag_node") if root.has_meta("source_drag_node") else null
					})

	var saved_drag_nodes: Dictionary = {}
	for item in existing_items:
		if item["old_root"].has_meta("source_drag_node"):
			saved_drag_nodes[item["id"]] = item["old_root"].get_meta("source_drag_node")

	var to_pack = []
	for item in existing_items:
		to_pack.append({"id": item["id"], "is_new": false, "shape": item["old_shape"]})
	for data in new_items_data:
		to_pack.append({"id": data["id"], "is_new": true, "shape": data["shape"], "cab_node": data["cab_node"]})

	to_pack.sort_custom(func(a, b):
		return a["shape"].size() > b["shape"].size()
	)

	_clear_entire_grid()

	# 3. АНИМАЦИЯ ВОЗВРАТА: Вышвыриваем мусор обратно в шкаф
	for wrong_item in wrong_items_to_return:
		if get_tree().current_scene.has_method("fly_back_to_cabinet"):
			# Передаем skip_unmark = true, чтобы не сломать учет легальных предметов!
			get_tree().current_scene.fly_back_to_cabinet(wrong_item["id"], wrong_item["pos"], wrong_item["drag_node"], true)

	var successfully_added_new = []
	var packing_failed = false

	for pack_item in to_pack:
		var placed = false
		var item_id = pack_item["id"]
		var base_shape = pack_item["shape"]

		for r in range(4):
			if placed: break
			var test_shape = _rotate_shape_normalized(base_shape, r * 90)

			for cell in grid.get_children():
				if not cell.has_node("ItemIcon"): continue
				if _can_place_shape(cell, test_shape):
					_place_item_in_grid(cell, item_id, test_shape, r * 90)
					placed = true

					if pack_item["is_new"]:
						successfully_added_new.append({
							"id": item_id,
							"cell": cell,
							"cab_node": pack_item.get("cab_node")
						})
						cell.get_node("ItemIcon").hide()
						cell.set_meta("hide_bg_until_land", true)
					else:
						if saved_drag_nodes.has(item_id):
							cell.set_meta("source_drag_node", saved_drag_nodes[item_id])
					break

		if not placed:
			# ФОЛЛБЭК: Жадный алгоритм не смог упаковать сложную форму.
			# Ужимаем предмет до 1 клетки (1x1), чтобы он гарантированно влез в рюкзак!
			var fallback_shape = [Vector2(0, 0)]
			for cell in grid.get_children():
				if not cell.has_node("ItemIcon"): continue
				if _can_place_shape(cell, fallback_shape):
					_place_item_in_grid(cell, item_id, fallback_shape, 0)
					placed = true

					if pack_item["is_new"]:
						successfully_added_new.append({
							"id": item_id,
							"cell": cell,
							"cab_node": pack_item.get("cab_node")
						})
						cell.get_node("ItemIcon").hide()
						cell.set_meta("hide_bg_until_land", true)
					else:
						if saved_drag_nodes.has(item_id):
							cell.set_meta("source_drag_node", saved_drag_nodes[item_id])
					break

			# Если даже 1х1 не влезло (что невозможно при правильных лимитах)
			if not placed:
				if not pack_item["is_new"]:
					packing_failed = true
					break
				else:
					continue

	if packing_failed:
		_clear_entire_grid()
		for item in existing_items:
			_place_item_in_grid(item["old_root"], item["id"], item["old_shape"], item["old_rot"])
		print("Авто-сборка: Не хватает места для перетасовки!")
		return []

	if successfully_added_new.size() > 0 or existing_items.size() > 0:
		_update_grid_visuals()
		# Закрытие рюкзака вызывается из main_scene после сбора всех монет.
		_play_autofill_cascade_animation()

	return successfully_added_new


func _play_autofill_cascade_animation() -> void:
	is_cascading = true
	var cell_tween: Tween = create_tween()
	cell_tween.set_parallel(true)

	var delay: float = 0.0
	const DURATION: float = 0.3
	const DELAY_STEP: float = 0.05
	var any_animated = false

	for cell in grid.get_children():
		var icon = cell.get_node_or_null("ItemIcon")

		# Анимируем только те иконки, которые сейчас ВИДИМЫ (старые предметы, которые перемешались).
		# Новые предметы были скрыты (hide) в auto_fill_and_optimize, их покажет main_scene когда они долетят.
		if icon and icon.visible and cell.get_meta("occupied_by_id", -1) != -1:
			any_animated = true
			# Убеждаемся, что пивот по центру
			icon.pivot_offset = icon.size / 2.0
			icon.scale = Vector2.ZERO

			cell_tween.tween_property(icon, "scale", Vector2.ONE, DURATION)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)\
				.set_delay(delay)

			delay += DELAY_STEP

	if not any_animated:
		is_cascading = false
		cascade_finished.emit()
		return

	cell_tween.finished.connect(_on_autofill_cascade_finished)


func _apply_ideal_flight_step(
	v: float,
	start_center: Vector2,
	target_center: Vector2,
	start_scale: Vector2,
	target_scale: Vector2
) -> void:
	var cur_scale = start_scale.lerp(target_scale, v)
	var cur_center = start_center.lerp(target_center, v)
	backpack_bg.scale = cur_scale
	backpack_bg.global_position = cur_center - (backpack_bg.size * cur_scale / 2.0)
	if is_instance_valid(closing_sequence_node):
		closing_sequence_node.scale = cur_scale * seq_visual_scale_multiplier
		var seq_offset = (closing_sequence_node.size * closing_sequence_node.scale) / 2.0
		closing_sequence_node.global_position = cur_center - seq_offset + seq_visual_offset


func _on_autofill_cascade_finished() -> void:
	is_cascading = false
	cascade_finished.emit()

func _clear_entire_grid():
	var roots = []
	for cell in grid.get_children():
		if cell.has_node("ItemIcon"):
			if not cell.has_meta("root_cell"):
				continue
			var r = cell.get_meta("root_cell")
			if r and not roots.has(r):
				roots.append(r)
	for r in roots:
		if r and r.has_meta("current_shape"):
			_clear_item_from_grid(r, r.get_meta("current_shape"))

func _rotate_shape_normalized(shape: Array, rot_deg: int) -> Array:
	if rot_deg == 0: return shape.duplicate()
	var steps = (rot_deg / 90) % 4
	var current_shape = shape.duplicate()
	for i in range(steps):
		var next_shape = []
		for p in current_shape: next_shape.append(Vector2(-p.y, p.x))
		current_shape = next_shape

	var min_x = 999; var min_y = 999
	for p in current_shape:
		if p.x < min_x: min_x = p.x
		if p.y < min_y: min_y = p.y
	for i in range(current_shape.size()):
		current_shape[i] = Vector2(current_shape[i].x - min_x, current_shape[i].y - min_y)
	return current_shape

# ==========================================================
# --- ИНДУСТРИАЛЬНЫЙ СТАНДАРТ ЦЕНТРОВКИ ИКОНОК ---
# ==========================================================
func _align_icon_in_bbox(icon: TextureRect, _item_id: int, current_shape: Array, rot_deg: int):
	if grid.get_child_count() == 0:
		return
	var c_size = grid.get_child(0).size
	var h_sep = grid.get_theme_constant("h_separation")
	var v_sep = grid.get_theme_constant("v_separation")
	var spacing = Vector2(max(0, h_sep), max(0, v_sep))

	var max_x := 0.0
	var max_y := 0.0
	for p in current_shape:
		if p.x > max_x:
			max_x = p.x
		if p.y > max_y:
			max_y = p.y

	var bbox_w: float = (max_x + 1.0) * c_size.x + max_x * spacing.x
	var bbox_h: float = (max_y + 1.0) * c_size.y + max_y * spacing.y

	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Инвертируем контейнер перед поворотом, если предмет стоит боком
	if int(rot_deg) % 180 != 0:
		icon.size = Vector2(bbox_h, bbox_w)
	else:
		icon.size = Vector2(bbox_w, bbox_h)

	icon.pivot_offset = icon.size / 2.0
	icon.rotation_degrees = rot_deg

	var bbox_center := Vector2(bbox_w, bbox_h) / 2.0
	icon.position = bbox_center - icon.pivot_offset

func _shake_item(root_cell: Control) -> void:
	if not root_cell:
		return
	var icon = root_cell.get_node_or_null("ItemIcon")
	if not icon:
		return
	var orig_rot = root_cell.get_meta("rot_deg", 0)
	if root_cell.has_meta("shake_tween"):
		var old_tw = root_cell.get_meta("shake_tween")
		if old_tw and old_tw.is_valid():
			old_tw.kill()
	var tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	root_cell.set_meta("shake_tween", tw)
	tw.tween_property(icon, "rotation_degrees", orig_rot + 15, 0.05)
	tw.tween_property(icon, "rotation_degrees", orig_rot - 15, 0.1)
	tw.tween_property(icon, "rotation_degrees", orig_rot, 0.05)

# ==========================================================
# --- МОНОЛИТНАЯ ОТРИСОВКА ---
# ==========================================================
func _get_merged_stylebox(shape: Array, offset: Vector2, is_focused: bool, is_preview: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.set_border_width_all(6)
	style.set_corner_radius_all(12)
	style.anti_aliasing = true

	if is_preview:
		style.bg_color = palette.puz_drag_valid_bg
		style.border_color = palette.puz_drag_valid_border
	elif ItemManager.is_edit_mode:
		style.bg_color = palette.puz_edit_focused_bg if is_focused else palette.puz_edit_unfocused_bg
		style.border_color = palette.puz_edit_focused_border if is_focused else palette.puz_edit_unfocused_border
	else:
		style.bg_color = palette.puz_normal_bg
		style.border_color = palette.puz_normal_border

	if shape.has(offset + Vector2(1, 0)):
		style.border_width_right = 0; style.corner_radius_top_right = 0; style.corner_radius_bottom_right = 0
	if shape.has(offset + Vector2(0, 1)):
		style.border_width_bottom = 0; style.corner_radius_bottom_right = 0; style.corner_radius_bottom_left = 0
	if shape.has(offset + Vector2(-1, 0)):
		style.border_width_left = 0; style.corner_radius_top_left = 0; style.corner_radius_bottom_left = 0
	if shape.has(offset + Vector2(0, -1)):
		style.border_width_top = 0; style.corner_radius_top_left = 0; style.corner_radius_top_right = 0
	return style

func _draw_merged_item(_item_id: int, start_cell: Control, shape: Array, is_focused: bool):
	if start_cell.get_meta("hide_bg_until_land", false):
		return

	for offset in shape:
		var target_coords = _get_cell_coords(start_cell) + Vector2i(offset.x, offset.y)
		var target_cell = _get_cell_by_coords(target_coords)
		if not target_cell: continue

		# Округляем базовые координаты
		var r_pos = target_cell.position.round()
		var r_size = target_cell.size.round()
		var rect = Rect2(r_pos, r_size)

		var overlap = 2.0 # Идеальный нахлест для непрозрачных цветов

		if shape.has(offset + Vector2(1, 0)):
			var next_cell = _get_cell_by_coords(target_coords + Vector2i(1, 0))
			if next_cell:
				var next_pos = next_cell.position.round()
				rect.size.x = (next_pos.x - rect.position.x) + overlap

		if shape.has(offset + Vector2(0, 1)):
			var next_cell = _get_cell_by_coords(target_coords + Vector2i(0, 1))
			if next_cell:
				var next_pos = next_cell.position.round()
				rect.size.y = (next_pos.y - rect.position.y) + overlap

		var style = _get_merged_stylebox(shape, offset, is_focused, false)
		style.draw(grid.get_canvas_item(), rect)

func _on_grid_draw():
	var processed_roots = []
	for cell in grid.get_children():
		if not cell.has_node("ItemIcon"): continue
		var item_id = cell.get_meta("occupied_by_id", -1)
		if item_id != -1:
			var root_cell = cell.get_meta("root_cell")
			if root_cell and not processed_roots.has(root_cell):
				if is_dragging_internal and root_cell == active_cell: continue
				processed_roots.append(root_cell)

				var shape = root_cell.get_meta("current_shape")
				var is_focused = (root_cell == active_cell and ItemManager.is_edit_mode)
				_draw_merged_item(item_id, root_cell, shape, is_focused)

func _update_grid_visuals():
	for cell in grid.get_children():
		if not cell.has_node("ItemIcon"): continue
		var border = cell.get_node_or_null("CellBorder")
		if not border: continue

		var is_occupied = cell.get_meta("occupied_by_id", -1) != -1

		# БЕЗОПАСНОЕ ПОЛУЧЕНИЕ META: достаем корень только если он существует
		var root_cell = null
		if cell.has_meta("root_cell"):
			root_cell = cell.get_meta("root_cell")

		# Если предмет летит, ячейка считает себя визуально "пустой" для рамки
		var is_waiting = is_occupied and root_cell and root_cell.get_meta("hide_bg_until_land", false)

		var show_border_as_empty = is_waiting
		if is_occupied and is_dragging_internal and root_cell == active_cell:
			show_border_as_empty = true

		if is_occupied and not show_border_as_empty:
			border.hide()
		else:
			border.show()
			border.set_state(1 if ItemManager.is_edit_mode else 0)
			border.alpha_default = 1.0

	grid.queue_redraw()

# ==========================================================
# --- ПРЕВЬЮ ПАЗЗЛА ---
# ==========================================================
func _setup_drag_preview():
	drag_preview_container = Control.new()
	drag_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview_container.z_index = 50
	add_child(drag_preview_container)
	drag_preview_container.hide()

func build_drag_preview(item_id: int, shape: Array, rot_deg: int = 0):
	for c in drag_preview_container.get_children():
		c.queue_free()
	_drag_preview_shape.clear()
	var sample_cell = null
	for c in grid.get_children():
		if c.has_node("ItemIcon"): sample_cell = c; break
	if not sample_cell:
		return
	_drag_preview_shape = shape.duplicate()

	var c_size = sample_cell.size
	var h_sep = grid.get_theme_constant("h_separation")
	var v_sep = grid.get_theme_constant("v_separation")
	var spacing = Vector2(max(0, h_sep), max(0, v_sep))

	for offset in shape:
		var panel = Panel.new()
		var style = _get_merged_stylebox(shape, offset, false, true)
		panel.add_theme_stylebox_override("panel", style)

		# Математически вычисляем позицию в сетке превью и округляем
		var raw_pos = Vector2(offset.x * (c_size.x + spacing.x), offset.y * (c_size.y + spacing.y))
		var p_pos = raw_pos.round()
		var p_size = c_size.round()

		var overlap = 2.0 # Идеальный нахлест для непрозрачных цветов

		# Тянем край до следующей ячейки + нахлест
		if shape.has(offset + Vector2(1, 0)):
			var next_raw_pos = Vector2((offset.x + 1) * (c_size.x + spacing.x), offset.y * (c_size.y + spacing.y))
			p_size.x = (next_raw_pos.round().x - p_pos.x) + overlap

		if shape.has(offset + Vector2(0, 1)):
			var next_raw_pos = Vector2(offset.x * (c_size.x + spacing.x), (offset.y + 1) * (c_size.y + spacing.y))
			p_size.y = (next_raw_pos.round().y - p_pos.y) + overlap

		panel.position = p_pos
		panel.size = p_size
		drag_preview_container.add_child(panel)

	var icon = TextureRect.new()
	icon.texture = load(ItemManager.items_db[item_id]["texture"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_preview_container.add_child(icon)
	_align_icon_in_bbox(icon, item_id, shape, rot_deg)

func show_external_drag_preview(item_id: int, mouse_pos: Vector2, shape_override: Array = []):
	var shape: Array
	if shape_override.size() > 0:
		shape = shape_override
	else:
		shape = ItemManager.items_db[item_id]["shape"]
	build_drag_preview(item_id, shape, 0)
	_update_drag_preview_pos(mouse_pos)
	drag_preview_container.global_position = target_preview_pos
	drag_preview_container.show()

func update_external_drag_preview(mouse_pos: Vector2) -> void:
	_update_drag_preview_pos(mouse_pos)

func _get_preview_pixel_size(shape: Array) -> Vector2:
	if grid.get_child_count() == 0:
		return Vector2.ZERO
	var cell_size: Vector2 = grid.get_child(0).size
	var max_x: float = 0.0
	var max_y: float = 0.0
	for p in shape:
		if p.x > max_x:
			max_x = p.x
		if p.y > max_y:
			max_y = p.y
	return Vector2((max_x + 1.0) * cell_size.x, (max_y + 1.0) * cell_size.y)

func _find_closest_cell_in_radius(hotspot: Vector2, radius: float) -> Control:
	var closest_cell: Control = null
	var min_dist: float = INF
	for cell in grid.get_children():
		if cell is Control: # Убеждаемся, что это нода ячейки
			var cell_center = cell.global_position + (cell.size / 2.0)
			var dist = hotspot.distance_to(cell_center)
			if dist < min_dist and dist <= radius:
				min_dist = dist
				closest_cell = cell
	return closest_cell

func _calculate_current_magnet_targets() -> Dictionary:
	var hotspot = get_global_mouse_position() + drag_pointer_offset

	var current_local_offset = backpack_bg.position - bg_base_pos
	var base_global_center = (backpack_bg.global_position - current_local_offset) + (backpack_bg.size / 2.0)

	var dist = hotspot.distance_to(base_global_center)
	var dir = base_global_center.direction_to(hotspot)

	# МАТЕМАТИКА "СОБАКИ НА ПОВОДКЕ":
	# Как только палец отдаляется от центра дальше чем на 150 пикселей, тяга становится 100%
	# Рюкзак всегда "дотянут" до лимита навстречу пальцу и не отступает при сближении
	var pull_strength = clampf(dist / 150.0, 0.0, 1.0)

	var offset_vector = dir * (magnet_max_offset * pull_strength)

	return {
		"pos": bg_base_pos + offset_vector,
		"scale": bg_base_scale * lerpf(1.0, magnet_scale_bump, pull_strength),
		"rot": bg_base_rot + (dir.x * magnet_max_rotation * pull_strength)
	}

func _update_drag_preview_pos(mouse_pos: Vector2) -> void:
	var hotspot: Vector2 = mouse_pos + drag_pointer_offset
	var current_preview_scale = drag_preview_container.scale if drag_preview_container else Vector2.ONE
	var half_size: Vector2 = (_get_preview_pixel_size(_drag_preview_shape) * current_preview_scale) / 2.0

	# 1. Поиск ячейки (Только строго под пальцем или захват снаружи)
	var current_cell = _get_cell_at_pos(hotspot)
	if not current_cell and not is_preview_snapped:
		current_cell = _find_closest_cell_in_radius(hotspot, grid_catch_radius)

	# 2. Проверка валидности
	var is_valid = false
	if current_cell and not _drag_preview_shape.is_empty():
		is_valid = _can_place_shape(current_cell, _drag_preview_shape, is_dragging_internal)
		if not is_valid:
			var obstacles = _get_obstacle_roots(current_cell, _drag_preview_shape)
			if obstacles.size() > 0 and _calculate_multi_swap(current_cell, _drag_preview_shape, obstacles).size() > 0:
				is_valid = true

	# 3. ГИСТЕРЕЗИС ПО ВИДЖЕТУ РЮКЗАКА
	if not is_valid and is_preview_snapped and _snapped_root_cell:
		# Берем глобальные границы рюкзака и расширяем их на "резинку" (grid_release_radius)
		var bg_rect = backpack_bg.get_global_rect().grow(grid_release_radius)

		if bg_rect.has_point(hotspot):
			# Палец все еще над рюкзаком (даже в пустом углу или над занятой ячейкой)!
			# Принудительно оставляем предмет на последней удачной ячейке.
			current_cell = _snapped_root_cell
			is_valid = true

	# 4. Применение состояния
	if is_valid:
		if not is_preview_snapped:
			# ВХОД В СЕТКУ (Первый щелчок предмета)
			is_preview_snapped = true
			_current_snap_speed_mult = fast_snap_multiplier

		_snapped_root_cell = current_cell
		target_preview_pos = current_cell.global_position
	else:
		# СВОБОДНЫЙ ПОЛЕТ
		is_preview_snapped = false
		_snapped_root_cell = null
		target_preview_pos = hotspot - half_size

func hide_external_drag_preview() -> void:
	if drag_preview_container:
		drag_preview_container.hide()
		drag_preview_container.scale = Vector2.ONE
	_update_grid_visuals()
	is_preview_snapped = false
	_snapped_root_cell = null
	is_backpack_frozen = false
	mag_frozen_pos = bg_base_pos
	mag_frozen_scale = bg_base_scale
	mag_frozen_rot = bg_base_rot

# ==========================================================
# --- ОСТАЛЬНАЯ ЛОГИКА ---
# ==========================================================
func _input(event):
	var mouse_pos = get_global_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if edit_menu and edit_menu.visible and edit_menu.get_global_rect().has_point(mouse_pos):
				return

			var clicked_cell = _get_cell_at_pos(mouse_pos)
			if clicked_cell:
				var occupant_id = clicked_cell.get_meta("occupied_by_id", -1)
				if occupant_id != -1:
					var target_root = clicked_cell.get_meta("root_cell")
					var target_shape = target_root.get_meta("current_shape")
					var target_rot = target_root.get_meta("rot_deg", 0)
					if target_root == active_cell and ItemManager.is_edit_mode:
						is_dragging_internal = true
						_hide_icons_for_shape(active_cell, active_shape)
						build_drag_preview(active_item_id, active_shape, target_rot)
						_update_drag_preview_pos(mouse_pos)
						drag_preview_container.global_position = target_preview_pos
						drag_preview_container.show()
						_update_grid_visuals()
						get_viewport().set_input_as_handled()
					else:
						var saved_drag_node = target_root.get_meta("source_drag_node") if target_root.has_meta("source_drag_node") else null
						_start_edit_mode(target_root, occupant_id, saved_drag_node, target_shape)
						get_viewport().set_input_as_handled()
			else:
				if (
					ItemManager.is_edit_mode
					and edit_menu
					and not edit_menu.get_global_rect().has_point(mouse_pos)
				):
					_close_edit_mode()
		else:
			if is_dragging_internal:
				hide_external_drag_preview()
				var hotspot: Vector2 = mouse_pos + drag_pointer_offset
				var target_root = _get_cell_at_pos(hotspot)
				var old_rot = active_cell.get_meta("rot_deg", 0)
				var success = false

				if target_root:
					if _can_place_shape(target_root, active_shape, true):
						_clear_item_from_grid(active_cell, active_shape)
						active_cell = target_root
						_place_item_in_grid(active_cell, active_item_id, active_shape, old_rot)
						success = true
					else:
						var obstacles = _get_obstacle_roots(target_root, active_shape)
						if obstacles.size() > 0:
							var multi_swap = _calculate_multi_swap(target_root, active_shape, obstacles)
							if multi_swap.size() > 0:
								var saved_obs = []
								for swap_entry in multi_swap:
									var o_root = swap_entry["obs_root"]
									var old_shape_to_clear = o_root.get_meta("current_shape")
									saved_obs.append({
										"id": swap_entry["id"],
										"shape": swap_entry["shape"],
										"new_root": swap_entry["new_root"],
										"rot": swap_entry["new_rot"],
										"old_rot": swap_entry["old_rot"],
										"drag": o_root.get_meta("source_drag_node") if o_root.has_meta("source_drag_node") else null,
										"pos": o_root.global_position + (o_root.size / 2.0)
									})
									_clear_item_from_grid(o_root, old_shape_to_clear)

								_clear_item_from_grid(active_cell, active_shape)
								active_cell = target_root
								_place_item_in_grid(active_cell, active_item_id, active_shape, old_rot)

								for obs in saved_obs:
									_place_item_in_grid(obs["new_root"], obs["id"], obs["shape"], obs["rot"])
									if obs["drag"]: obs["new_root"].set_meta("source_drag_node", obs["drag"])
									_animate_swap_fly(obs["new_root"], obs["pos"], obs["old_rot"])
								success = true

				is_dragging_internal = false

				if success:
					_show_icons_for_shape(active_cell, active_shape)
				else:
					_show_icons_for_shape(active_cell, active_shape)
					_shake_item(active_cell)
				_update_grid_visuals()
				get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and is_dragging_internal:
		update_external_drag_preview(mouse_pos)
		get_viewport().set_input_as_handled()

func try_add_item(item_id: int, _mouse_pos: Vector2, drag_node: Node3D = null) -> bool:
	var item_data = ItemManager.items_db.get(item_id)
	if not item_data:
		return false

	var shape: Array
	if drag_node and drag_node.has_meta("puzzle_shape"):
		shape = drag_node.get_meta("puzzle_shape")
	else:
		shape = item_data.get("shape", [Vector2.ZERO])

	var preview_root_pos = drag_preview_container.global_position + Vector2(10, 10)
	var target_root = _get_cell_at_pos(preview_root_pos)
	if not target_root:
		target_root = _find_first_free_slot(shape)

	if target_root and _can_place_shape(target_root, shape):
		_place_item_in_grid(target_root, item_id, shape, 0)
		if drag_node: target_root.set_meta("source_drag_node", drag_node)
		_close_edit_mode()
		ItemManager.mark_item_as_found(item_id)
		return true

	# 2. Попытка вытеснить предмет(ы) (Multi-Swap)
	if target_root:
		var obstacles = _get_obstacle_roots(target_root, shape)
		if obstacles.size() > 0:
			var multi_swap = _calculate_multi_swap(target_root, shape, obstacles)
			if multi_swap.size() > 0:
				var saved_obs = []
				for swap_entry in multi_swap:
					var o_root = swap_entry["obs_root"]
					var old_shape_to_clear = o_root.get_meta("current_shape")
					saved_obs.append({
						"id": swap_entry["id"],
						"shape": swap_entry["shape"],
						"new_root": swap_entry["new_root"],
						"rot": swap_entry["new_rot"],
						"old_rot": swap_entry["old_rot"],
						"drag": o_root.get_meta("source_drag_node") if o_root.has_meta("source_drag_node") else null,
						"pos": o_root.global_position + (o_root.size / 2.0)
					})
					_clear_item_from_grid(o_root, old_shape_to_clear)

				_place_item_in_grid(target_root, item_id, shape, 0)
				if drag_node: target_root.set_meta("source_drag_node", drag_node)

				for obs in saved_obs:
					_place_item_in_grid(obs["new_root"], obs["id"], obs["shape"], obs["rot"])
					if obs["drag"]: obs["new_root"].set_meta("source_drag_node", obs["drag"])
					_animate_swap_fly(obs["new_root"], obs["pos"], obs["old_rot"])

				_close_edit_mode()
				ItemManager.mark_item_as_found(item_id)
				return true

	# 3. АВТО-УСТАНОВКА (План Б)
	var auto_slot = _find_first_free_slot(shape)
	if auto_slot:
		_place_item_in_grid(auto_slot, item_id, shape, 0)
		if drag_node: auto_slot.set_meta("source_drag_node", drag_node)
		_close_edit_mode()
		ItemManager.mark_item_as_found(item_id)
		return true

	return false

func _can_place_shape(root_cell: Control, shape: Array, ignore_active: bool = false) -> bool:
	var root_coords = _get_cell_coords(root_cell)
	for offset in shape:
		var target_coords = root_coords + Vector2i(offset.x, offset.y)
		var cell = _get_cell_by_coords(target_coords)
		if cell == null: return false 
		var occupant_id = cell.get_meta("occupied_by_id", -1)
		if occupant_id != -1 and not (ignore_active and cell.get_meta("root_cell") == active_cell): 
			return false
	return true

func _place_item_in_grid(root_cell: Control, item_id: int, shape: Array, rot_deg: int):
	var tex_path = ItemManager.items_db[item_id]["texture"]
	var icon = root_cell.get_node("ItemIcon")
	icon.texture = load(tex_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.show()
	_align_icon_in_bbox(icon, item_id, shape, rot_deg)
	root_cell.set_meta("current_shape", shape)
	root_cell.set_meta("rot_deg", rot_deg)
	var root_coords = _get_cell_coords(root_cell)
	for offset in shape:
		var cell = _get_cell_by_coords(root_coords + Vector2i(offset.x, offset.y))
		if cell: cell.set_meta("occupied_by_id", item_id); cell.set_meta("root_cell", root_cell)
	_update_grid_visuals()

func _clear_item_from_grid(root_cell: Control, shape: Array):
	var root_coords = _get_cell_coords(root_cell)
	for offset in shape:
		var cell = _get_cell_by_coords(root_coords + Vector2i(offset.x, offset.y))
		if cell: cell.remove_meta("occupied_by_id"); cell.remove_meta("root_cell")
	root_cell.remove_meta("current_shape")
	root_cell.remove_meta("rot_deg")
	if root_cell.has_meta("source_drag_node"): root_cell.remove_meta("source_drag_node")
	root_cell.get_node("ItemIcon").texture = null
	root_cell.get_node("ItemIcon").hide()
	_update_grid_visuals()

func _get_obstacle_roots(root_cell: Control, shape: Array) -> Array:
	var roots: Array = []
	var root_coords = _get_cell_coords(root_cell)
	for offset in shape:
		var cell = _get_cell_by_coords(root_coords + Vector2i(offset.x, offset.y))
		if cell == null: continue
		var occ = cell.get_meta("occupied_by_id", -1)
		if occ != -1:
			var r = cell.get_meta("root_cell")
			if r != active_cell and not roots.has(r):
				roots.append(r)
	return roots

func _calculate_multi_swap(target_root: Control, drag_shape: Array, obstacles: Array) -> Array:
	var result: Array = []
	var saved_data: Array = []

	var active_saved_id = -1
	var active_saved_root: Control = null
	if is_dragging_internal and active_cell:
		active_saved_root = active_cell
		var a_coords = _get_cell_coords(active_cell)
		var a_c = _get_cell_by_coords(a_coords)
		if a_c and a_c.has_meta("occupied_by_id"):
			active_saved_id = a_c.get_meta("occupied_by_id")
		for offset in active_shape:
			var t_c = _get_cell_by_coords(a_coords + Vector2i(offset.x, offset.y))
			if t_c:
				if t_c.has_meta("occupied_by_id"):
					t_c.remove_meta("occupied_by_id")
				if t_c.has_meta("root_cell"):
					t_c.remove_meta("root_cell")

	for obs in obstacles:
		var o_shape = obs.get_meta("current_shape")
		var root_coords = _get_cell_coords(obs)
		var oid = -1
		var first_cell = _get_cell_by_coords(root_coords)
		if first_cell and first_cell.has_meta("occupied_by_id"):
			oid = first_cell.get_meta("occupied_by_id")
		saved_data.append({"root": obs, "shape": o_shape, "id": oid, "coords": root_coords})
		for offset in o_shape:
			var t_c = _get_cell_by_coords(root_coords + Vector2i(offset.x, offset.y))
			if t_c:
				if t_c.has_meta("occupied_by_id"):
					t_c.remove_meta("occupied_by_id")
				if t_c.has_meta("root_cell"):
					t_c.remove_meta("root_cell")

	var is_valid = false
	if _can_place_shape(target_root, drag_shape):
		is_valid = true
		var target_coords = _get_cell_coords(target_root)
		for offset in drag_shape:
			var t_c = _get_cell_by_coords(target_coords + Vector2i(offset.x, offset.y))
			if t_c:
				t_c.set_meta("occupied_by_id", -999)
				t_c.set_meta("root_cell", target_root)

		for obs_data in saved_data:
			var found_root: Control = null
			var best_shape: Array = []
			var best_rot = 0
			var obs_root_ctrl: Control = obs_data["root"]
			var old_rot_meta: float = obs_root_ctrl.get_meta("rot_deg", 0)

			for rot_offset in [0, 90, 180, 270]:
				var test_shape = _rotate_shape_normalized(obs_data["shape"], rot_offset)
				for cell in grid.get_children():
					if cell.has_node("ItemIcon") and _can_place_shape(cell, test_shape):
						found_root = cell
						best_shape = test_shape
						best_rot = int(old_rot_meta + rot_offset) % 360
						break
				if found_root:
					break

			if found_root:
				result.append({
					"obs_root": obs_data["root"],
					"new_root": found_root,
					"shape": best_shape,
					"id": obs_data["id"],
					"new_rot": best_rot,
					"old_rot": old_rot_meta
				})
				var fr_coords = _get_cell_coords(found_root)
				for offset in best_shape:
					var t_c2 = _get_cell_by_coords(fr_coords + Vector2i(offset.x, offset.y))
					if t_c2:
						t_c2.set_meta("occupied_by_id", -998)
						t_c2.set_meta("root_cell", found_root)
			else:
				is_valid = false
				break

		for offset in drag_shape:
			var t_c = _get_cell_by_coords(target_coords + Vector2i(offset.x, offset.y))
			if t_c:
				if t_c.has_meta("occupied_by_id"):
					t_c.remove_meta("occupied_by_id")
				if t_c.has_meta("root_cell"):
					t_c.remove_meta("root_cell")
		for res_entry in result:
			var fr_coords = _get_cell_coords(res_entry["new_root"])
			for offset in res_entry["shape"]:
				var t_c = _get_cell_by_coords(fr_coords + Vector2i(offset.x, offset.y))
				if t_c:
					if t_c.has_meta("occupied_by_id"):
						t_c.remove_meta("occupied_by_id")
					if t_c.has_meta("root_cell"):
						t_c.remove_meta("root_cell")

	if not is_valid:
		result.clear()

	for obs_data in saved_data:
		for offset in obs_data["shape"]:
			var t_c = _get_cell_by_coords(obs_data["coords"] + Vector2i(offset.x, offset.y))
			if t_c:
				t_c.set_meta("occupied_by_id", obs_data["id"])
				t_c.set_meta("root_cell", obs_data["root"])

	if is_dragging_internal and active_cell and active_saved_id != -1:
		var a_coords = _get_cell_coords(active_cell)
		for offset in active_shape:
			var t_c = _get_cell_by_coords(a_coords + Vector2i(offset.x, offset.y))
			if t_c:
				t_c.set_meta("occupied_by_id", active_saved_id)
				t_c.set_meta("root_cell", active_saved_root)

	return result

func _animate_swap_fly(new_root: Control, old_global_pos: Vector2, old_rot: float) -> void:
	var icon = new_root.get_node_or_null("ItemIcon")
	if not icon or not icon.visible:
		return
	var final_pos = icon.position
	var final_rot = icon.rotation_degrees
	var offset = old_global_pos - new_root.global_position - (new_root.size / 2.0)
	icon.position = offset
	icon.rotation_degrees = old_rot
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(icon, "position", final_pos, 0.25)
	var diff = wrapf(final_rot - old_rot, -180.0, 180.0)
	tw.tween_property(icon, "rotation_degrees", old_rot + diff, 0.25)

func _on_btn_rotate():
	if not active_cell: return
	var new_shape = []
	for p in active_shape: new_shape.append(Vector2(-p.y, p.x))
	var min_x = 999; var min_y = 999; var max_x = -999; var max_y = -999
	for p in new_shape:
		if p.x < min_x: min_x = p.x
		if p.y < min_y: min_y = p.y
		if p.x > max_x: max_x = p.x
		if p.y > max_y: max_y = p.y
	for i in range(new_shape.size()): new_shape[i] = Vector2(new_shape[i].x - min_x, new_shape[i].y - min_y)

	var new_max_x = max_x - min_x; var new_max_y = max_y - min_y
	var old_max_x = 0; var old_max_y = 0
	for p in active_shape:
		if p.x > old_max_x: old_max_x = p.x
		if p.y > old_max_y: old_max_y = p.y

	var root_coords = _get_cell_coords(active_cell)
	var new_root_x = round(root_coords.x + (old_max_x / 2.0) - (new_max_x / 2.0))
	var new_root_y = round(root_coords.y + (old_max_y / 2.0) - (new_max_y / 2.0))
	var new_root_coords = Vector2i(new_root_x, new_root_y)

	var valid_root = null
	var test_offsets = [
		Vector2i(0,0), Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1), 
		Vector2i(1,1), Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1),
		Vector2i(2,0), Vector2i(-2,0), Vector2i(0,2), Vector2i(0,-2)
	]
	for offset in test_offsets:
		var test_coords = new_root_coords + offset
		var test_cell = _get_cell_by_coords(test_coords)
		if test_cell and _can_place_shape(test_cell, new_shape, true):
			valid_root = test_cell; break

	if valid_root:
		var old_rot = active_cell.get_meta("rot_deg", 0)
		_clear_item_from_grid(active_cell, active_shape)
		active_shape = new_shape; active_cell = valid_root
		_place_item_in_grid(active_cell, active_item_id, active_shape, old_rot + 90)
		
		var icon = active_cell.get_node("ItemIcon")
		icon.rotation_degrees = old_rot 
		var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(icon, "rotation_degrees", old_rot + 90, 0.25)
		active_cell.set_meta("rot_deg", int(old_rot + 90) % 360)
		_update_grid_visuals()

func _on_btn_confirm():
	if active_item_id == -1:
		return
	var confirmed_id = active_item_id
	_close_edit_mode()
	ItemManager.mark_item_as_found(confirmed_id)

func _on_btn_cancel():
	if not active_cell:
		_close_edit_mode()
		return

	var fly_pos = active_cell.global_position + (active_cell.size / 2.0)
	var shape_to_clear = active_shape.duplicate()
	var cell_to_clear = active_cell
	var item_to_return = active_item_id
	var drag_node_to_return = active_drag_node

	_clear_item_from_grid(cell_to_clear, shape_to_clear)
	if get_tree().current_scene.has_method("fly_back_to_cabinet"):
		get_tree().current_scene.fly_back_to_cabinet(item_to_return, fly_pos, drag_node_to_return)

	active_cell = null
	active_item_id = -1
	active_drag_node = null
	active_shape = []

	ItemManager.is_edit_mode = false
	_tween_hide_edit_menu()
	_update_grid_visuals()

func _start_edit_mode(cell: Control, item_id: int, drag_node: Node3D, shape: Array = []):
	active_cell = cell
	active_item_id = item_id
	active_drag_node = drag_node
	if shape.size() > 0:
		active_shape = shape
	elif drag_node and drag_node.has_meta("puzzle_shape"):
		active_shape = drag_node.get_meta("puzzle_shape").duplicate()
	else:
		active_shape = ItemManager.items_db[item_id].get("shape", [Vector2.ZERO])
	ItemManager.is_edit_mode = true

	if edit_menu:
		edit_menu.top_level = false
		edit_menu.z_index = 0
		edit_menu.position = default_edit_menu_pos
		if edit_menu.has_node("BtnRotate"):
			edit_menu.get_node("BtnRotate").show()
		if edit_menu.has_node("BtnConfirm"):
			edit_menu.get_node("BtnConfirm").show()
		edit_menu.modulate.a = 1.0
		edit_menu.show()
		edit_menu.scale = Vector2(0.5, 0.5)
		edit_menu.pivot_offset = edit_menu.size / 2.0
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(
			edit_menu, "scale", Vector2.ONE, 0.2)
	_update_grid_visuals()

func _tween_hide_edit_menu() -> void:
	if not edit_menu:
		return
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(edit_menu, "scale", Vector2(0.5, 0.5), 0.15)
	tw.tween_property(edit_menu, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(edit_menu.hide)

func _close_edit_mode(hide_menu: bool = true):
	ItemManager.is_edit_mode = false
	active_cell = null
	active_item_id = -1
	active_drag_node = null
	active_shape = []
	_update_grid_visuals()
	if hide_menu:
		_tween_hide_edit_menu()

func _get_cell_coords(cell: Control) -> Vector2i:
	var idx = cell.get_index(); return Vector2i(idx % grid.columns, idx / grid.columns)

func _get_cell_by_coords(coords: Vector2i) -> Control:
	if coords.x < 0 or coords.x >= grid.columns: return null
	var max_y = ceil(float(grid.get_child_count()) / grid.columns)
	if coords.y < 0 or coords.y >= max_y: return null
	var idx = coords.y * grid.columns + coords.x
	if idx < 0 or idx >= grid.get_child_count(): return null
	var cell = grid.get_child(idx)
	if not cell.has_node("ItemIcon"): return null 
	return cell

func _get_cell_at_pos(pos: Vector2) -> Control:
	for cell in grid.get_children():
		if cell.has_node("ItemIcon") and cell.get_global_rect().has_point(pos): return cell
	return null

func _find_first_free_slot(shape: Array) -> Control:
	for cell in grid.get_children():
		if cell.has_node("ItemIcon") and _can_place_shape(cell, shape): return cell
	return null

func _hide_icons_for_shape(root: Control, _shape: Array): root.get_node("ItemIcon").hide()
func _show_icons_for_shape(root: Control, _shape: Array): root.get_node("ItemIcon").show()

func start_appear_animation():
	is_magnet_ready = false
	show(); modulate.a = 0.0; var final_y = backpack_bg.position.y
	backpack_bg.position.y += hide_pos_offset
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.5); tw.tween_property(backpack_bg, "position:y", final_y, 0.7)
	backpack_bg.pivot_offset = backpack_bg.size / 2.0; backpack_bg.scale = Vector2(0.7, 0.7)
	tw.tween_property(backpack_bg, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_callback(func():
		bg_base_pos = backpack_bg.position
		bg_base_scale = backpack_bg.scale
		bg_base_rot = backpack_bg.rotation_degrees
		original_bg_pos = backpack_bg.global_position + backpack_bg.size * backpack_bg.scale / 2.0
		original_bg_scale = backpack_bg.scale
		is_magnet_ready = true # Включаем магнит только когда рюкзак встал на место
	)

# ==========================================================
# --- ФАБРИКА ОДИНОЧНОГО ПАЗЗЛА (ДЛЯ АНИМАЦИИ ПОЛЕТА) ---
# ==========================================================
func create_standalone_puzzle_visual(item_id: int, shape: Array, rot_deg: int) -> Control:
	var container = Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if grid.get_child_count() == 0: return container
	var c_size = grid.get_child(0).size
	var spacing = Vector2(max(0, grid.get_theme_constant("h_separation")), max(0, grid.get_theme_constant("v_separation")))

	# 1. Строим подложку из Panel
	for offset in shape:
		var panel = Panel.new()
		# Используем стандартный стиль (false), чтобы летел обычный коричневый паззл
		var style = _get_merged_stylebox(shape, offset, false, false)
		panel.add_theme_stylebox_override("panel", style)

		var raw_pos = Vector2(offset.x * (c_size.x + spacing.x), offset.y * (c_size.y + spacing.y))
		var p_pos = raw_pos.round()
		var p_size = c_size.round()
		var overlap = 2.0

		if shape.has(offset + Vector2(1, 0)):
			var next_raw_pos = Vector2((offset.x + 1) * (c_size.x + spacing.x), offset.y * (c_size.y + spacing.y))
			p_size.x = (next_raw_pos.round().x - p_pos.x) + overlap
		if shape.has(offset + Vector2(0, 1)):
			var next_raw_pos = Vector2(offset.x * (c_size.x + spacing.x), (offset.y + 1) * (c_size.y + spacing.y))
			p_size.y = (next_raw_pos.round().y - p_pos.y) + overlap

		panel.position = p_pos
		panel.size = p_size
		container.add_child(panel)

	# 2. Добавляем иконку
	var icon = TextureRect.new()
	icon.texture = load(ItemManager.items_db[item_id]["texture"])
	container.add_child(icon)
	_align_icon_in_bbox(icon, item_id, shape, rot_deg)

	# 3. Вычисляем общий размер контейнера для правильного pivot_offset
	var max_x = 0.0
	var max_y = 0.0
	for p in shape:
		if p.x > max_x: max_x = p.x
		if p.y > max_y: max_y = p.y
	container.size = Vector2((max_x + 1.0) * c_size.x + max_x * spacing.x, (max_y + 1.0) * c_size.y + max_y * spacing.y)
	container.pivot_offset = container.size / 2.0

	return container

func start_order_completed_sequence() -> void:
	if closing_sequence_node != null:
		return

	if is_cascading:
		await cascade_finished

	# «Вдох» перед прыжком: короткая пауза, чтобы сцена «успокоилась»
	await get_tree().create_timer(0.15).timeout

	is_order_completed = true
	_close_edit_mode()

	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for cell in grid.get_children():
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

	closing_sequence_node = BACKPACK_CLOSING_SCENE.instantiate()
	closing_sequence_node.modulate.a = 0.0
	closing_sequence_node.set_meta("MOUSE_FILTER_IGNORE", true)
	get_parent().add_child(closing_sequence_node)

	closing_sequence_node.size = backpack_bg.size
	closing_sequence_node.scale = backpack_bg.scale * seq_visual_scale_multiplier
	var bg_center = backpack_bg.global_position + (backpack_bg.size * backpack_bg.scale / 2.0)
	var seq_offset = (closing_sequence_node.size * closing_sequence_node.scale) / 2.0
	closing_sequence_node.global_position = bg_center - seq_offset + seq_visual_offset

	var start_center = backpack_bg.global_position + (backpack_bg.size * backpack_bg.scale / 2.0)
	var target_center = (get_viewport_rect().size / 2.0) + Vector2(0, final_flight_y_offset)
	var start_scale = backpack_bg.scale
	var target_scale = Vector2(1.1, 1.1)

	var fade_tw = create_tween().set_parallel(true)

	# TRANS_BACK + EASE_IN_OUT: лёгкий замах, затем мягкое торможение и overshoot (~0.95 с)
	fade_tw.tween_method(
		_apply_ideal_flight_step.bind(start_center, target_center, start_scale, target_scale),
		0.0,
		1.0,
		0.95
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)

	fade_tw.tween_property(grid, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_tw.tween_property(closing_sequence_node, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_tw.tween_property(backpack_bg, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.1)

	fade_tw.chain().tween_callback(func():
		if closing_sequence_node:
			closing_sequence_node.set_meta("MOUSE_FILTER_IGNORE", false)
			closing_sequence_node.mouse_filter = Control.MOUSE_FILTER_STOP
			closing_sequence_node.packing_completed.connect(_on_packing_final_completed)
	)

func _on_packing_final_completed() -> void:
	is_order_completed = false
	if closing_sequence_node:
		closing_sequence_node.queue_free()
		closing_sequence_node = null

	_clear_entire_grid()

	if get_tree().current_scene.has_method("_on_level_completed"):
		get_tree().current_scene._on_level_completed()
