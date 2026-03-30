extends Control

# Обрати внимание, теперь мы ищем GridContainer!
@onready var backpack_bg = $BackpackBG
@onready var grid = $BackpackBG/CenterContainer/GridContainer 
@onready var edit_menu = get_node_or_null("EditMenu") 

var hide_pos_offset = 600 

var active_cell: Control = null
var active_item_id: int = -1
var active_drag_node: Node3D = null
var active_shape: Array = []

var is_dragging_internal: bool = false
var drag_preview_container: Control

func _ready():
	hide()
	modulate.a = 0.0
	
	if edit_menu:
		edit_menu.hide()
		if edit_menu.has_node("BtnRotate"): edit_menu.get_node("BtnRotate").pressed.connect(_on_btn_rotate)
		if edit_menu.has_node("BtnConfirm"): edit_menu.get_node("BtnConfirm").pressed.connect(_on_btn_confirm)
		if edit_menu.has_node("BtnCancel"): edit_menu.get_node("BtnCancel").pressed.connect(_on_btn_cancel)
	
	_setup_drag_preview()
	_set_all_borders(0)

# --- ГЕНЕРАТОР ПРЬЕВЮ ПАЗЗЛА ---
func _setup_drag_preview():
	drag_preview_container = Control.new()
	drag_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview_container.z_index = 50
	add_child(drag_preview_container)
	drag_preview_container.hide()

func build_drag_preview(item_id: int, shape: Array):
	for c in drag_preview_container.get_children():
		c.queue_free()

	var sample_cell = null
	for c in grid.get_children():
		if c.has_node("ItemIcon"):
			sample_cell = c
			break
	if not sample_cell: return

	var c_size = sample_cell.size
	# Читаем реальные отступы сетки, чтобы превью 1 в 1 совпадало с рюкзаком
	var h_sep = grid.get_theme_constant("h_separation")
	var v_sep = grid.get_theme_constant("v_separation")
	var spacing = Vector2(h_sep if h_sep > 0 else 0, v_sep if v_sep > 0 else 0)

	for offset in shape:
		var cell_bg = ColorRect.new()
		cell_bg.color = Color(0.25, 0.15, 0.1, 0.85)
		cell_bg.size = c_size
		cell_bg.position = Vector2(offset.x, offset.y) * (c_size + spacing)
		
		var outline = ReferenceRect.new()
		outline.border_color = Color(0.8, 0.6, 0.4, 0.8)
		outline.border_width = 2.0
		outline.editor_only = false
		cell_bg.add_child(outline)
		drag_preview_container.add_child(cell_bg)

	var icon = TextureRect.new()
	icon.texture = load(ItemManager.items_db[item_id]["texture"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = c_size
	drag_preview_container.add_child(icon)

func show_external_drag_preview(item_id: int, mouse_pos: Vector2):
	var shape = ItemManager.items_db[item_id]["shape"]
	build_drag_preview(item_id, shape)
	update_external_drag_preview(mouse_pos)
	drag_preview_container.show()

func update_external_drag_preview(mouse_pos: Vector2):
	for c in grid.get_children():
		if c.has_node("ItemIcon"):
			drag_preview_container.global_position = mouse_pos - (c.size / 2.0)
			break

func hide_external_drag_preview():
	drag_preview_container.hide()

# --- ЛОГИКА УПРАВЛЕНИЯ КЛИКАМИ ---
func _input(event):
	var mouse_pos = get_global_mouse_position()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var clicked_cell = _get_cell_at_pos(mouse_pos)
			if clicked_cell:
				var occupant_id = clicked_cell.get_meta("occupied_by_id", -1)

				if occupant_id != -1:
					var target_root = clicked_cell.get_meta("root_cell")
					var target_shape = target_root.get_meta("current_shape")

					if occupant_id == active_item_id and ItemManager.is_edit_mode:
						is_dragging_internal = true
						_hide_icons_for_shape(active_cell, active_shape)
						build_drag_preview(active_item_id, active_shape)
						update_external_drag_preview(mouse_pos)
						drag_preview_container.show()
						get_viewport().set_input_as_handled()
						
					else:
						# ПЕРЕХВАТ: Если кликнули на другой предмет, меню НЕ закрываем, просто переносим рамку!
						_set_all_borders(0)
						_start_edit_mode(target_root, occupant_id, null, target_shape)
						get_viewport().set_input_as_handled()
				else:
					if ItemManager.is_edit_mode and edit_menu and not edit_menu.get_global_rect().has_point(mouse_pos):
						_close_edit_mode()
						
		else:
			if is_dragging_internal:
				is_dragging_internal = false
				hide_external_drag_preview()
				
				var target_root = _get_cell_at_pos(mouse_pos)
				var success = false
				
				if target_root and _can_place_shape(target_root, active_shape, true):
					var old_rot = active_cell.get_node("ItemIcon").rotation_degrees
					_clear_item_from_grid(active_cell, active_shape)
					active_cell = target_root
					_place_item_in_grid(active_cell, active_item_id, active_shape)
					active_cell.get_node("ItemIcon").rotation_degrees = old_rot
					success = true
					
				if not success:
					_show_icons_for_shape(active_cell, active_shape)
					
				_refresh_edit_borders()
				get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and is_dragging_internal:
		update_external_drag_preview(mouse_pos)
		get_viewport().set_input_as_handled()

# --- ЛОГИКА ТЕТРИСА (GRID CONTAINER) ---
func try_add_item(item_id: int, mouse_pos: Vector2, drag_node: Node3D = null) -> bool:
	var item_data = ItemManager.items_db.get(item_id)
	if not item_data: return false
	
	var shape = item_data["shape"]
	var target_root = _get_cell_at_pos(mouse_pos)
	
	if not target_root:
		target_root = _find_first_free_slot(shape)

	if target_root and _can_place_shape(target_root, shape):
		_place_item_in_grid(target_root, item_id, shape)
		_start_edit_mode(target_root, item_id, drag_node, shape)
		return true
	return false

func _can_place_shape(root_cell: Control, shape: Array, ignore_active: bool = false) -> bool:
	var root_coords = _get_cell_coords(root_cell)
	for offset in shape:
		var target_coords = root_coords + Vector2i(offset.x, offset.y)
		var cell = _get_cell_by_coords(target_coords)
		# Если вышли за край или попали в пустую зону (затычку)
		if cell == null: return false 
		var occupant_id = cell.get_meta("occupied_by_id", -1)
		if occupant_id != -1 and not (ignore_active and occupant_id == active_item_id):
			return false
	return true

func _place_item_in_grid(root_cell: Control, item_id: int, shape: Array):
	var tex_path = ItemManager.items_db[item_id]["texture"]
	var icon = root_cell.get_node("ItemIcon")
	icon.texture = load(tex_path)
	icon.show()
	icon.pivot_offset = icon.size / 2.0
	
	root_cell.set_meta("current_shape", shape)
	
	var root_coords = _get_cell_coords(root_cell)
	for offset in shape:
		var cell = _get_cell_by_coords(root_coords + Vector2i(offset.x, offset.y))
		if cell:
			cell.set_meta("occupied_by_id", item_id)
			cell.set_meta("root_cell", root_cell)

func _clear_item_from_grid(root_cell: Control, shape: Array):
	var root_coords = _get_cell_coords(root_cell)
	for offset in shape:
		var cell = _get_cell_by_coords(root_coords + Vector2i(offset.x, offset.y))
		if cell:
			cell.remove_meta("occupied_by_id")
			cell.remove_meta("root_cell")
	root_cell.remove_meta("current_shape")
	root_cell.get_node("ItemIcon").texture = null
	root_cell.get_node("ItemIcon").hide()

# --- ПОВОРОТ И МЕНЮ ---
func _on_btn_rotate():
	if not active_cell: return
	var new_shape = []
	for p in active_shape:
		new_shape.append(Vector2(-p.y, p.x))
	
	if _can_place_shape(active_cell, new_shape, true):
		var old_rot = active_cell.get_node("ItemIcon").rotation_degrees
		_clear_item_from_grid(active_cell, active_shape)
		active_shape = new_shape
		_place_item_in_grid(active_cell, active_item_id, active_shape)
		active_cell.get_node("ItemIcon").rotation_degrees = old_rot + 90
		_refresh_edit_borders()

func _on_btn_confirm():
	_close_edit_mode()
	ItemManager.mark_item_as_found(active_item_id)

func _on_btn_cancel():
	var fly_pos = active_cell.global_position + (active_cell.size / 2.0)
	var shape_to_clear = active_shape.duplicate()
	var cell_to_clear = active_cell
	var item_to_return = active_item_id
	var drag_node_to_return = active_drag_node
	
	_close_edit_mode()
	_clear_item_from_grid(cell_to_clear, shape_to_clear)
	
	if get_tree().current_scene.has_method("fly_back_to_cabinet"):
		get_tree().current_scene.fly_back_to_cabinet(item_to_return, fly_pos, drag_node_to_return)

func _start_edit_mode(cell: Control, item_id: int, drag_node: Node3D, shape: Array = []):
	var was_edit_mode = ItemManager.is_edit_mode
	active_cell = cell
	active_item_id = item_id
	active_drag_node = drag_node
	active_shape = shape if shape.size() > 0 else ItemManager.items_db[item_id]["shape"]
	ItemManager.is_edit_mode = true
	
	if edit_menu and not was_edit_mode:
		edit_menu.modulate.a = 1.0
		edit_menu.show()
		edit_menu.scale = Vector2(0.5, 0.5)
		edit_menu.pivot_offset = edit_menu.size / 2.0
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(edit_menu, "scale", Vector2.ONE, 0.2)
		
	_refresh_edit_borders()

func _close_edit_mode():
	ItemManager.is_edit_mode = false
	_set_all_borders(0)
	active_cell = null
	active_item_id = -1
	if edit_menu:
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(edit_menu, "scale", Vector2(0.5, 0.5), 0.15)
		tw.tween_property(edit_menu, "modulate:a", 0.0, 0.15)
		tw.chain().tween_callback(edit_menu.hide)

# --- УПРАВЛЕНИЕ РАМКАМИ ---
func _set_all_borders(state_id: int):
	for cell in grid.get_children():
		if cell.has_node("ItemIcon"):
			_set_single_border(cell, state_id)

func _set_single_border(cell: Control, state_id: int):
	var border = cell.get_node_or_null("CellBorder")
	if border and border.has_method("set_state"):
		border.set_state(state_id)

func _refresh_edit_borders():
	_set_all_borders(1)
	if not active_cell: return
	var rc = _get_cell_coords(active_cell)
	for offset in active_shape:
		var cell = _get_cell_by_coords(rc + Vector2i(offset.x, offset.y))
		if cell: _set_single_border(cell, 2)

# --- НОВАЯ МАТЕМАТИКА КООРДИНАТ ДЛЯ GRID CONTAINER ---
func _get_cell_coords(cell: Control) -> Vector2i:
	var idx = cell.get_index()
	return Vector2i(idx % grid.columns, idx / grid.columns)

func _get_cell_by_coords(coords: Vector2i) -> Control:
	if coords.x < 0 or coords.x >= grid.columns: return null
	
	var max_y = ceil(float(grid.get_child_count()) / grid.columns)
	if coords.y < 0 or coords.y >= max_y: return null
	
	var idx = coords.y * grid.columns + coords.x
	if idx < 0 or idx >= grid.get_child_count(): return null
	
	var cell = grid.get_child(idx)
	# Защита: если это пустой Control (затычка), считаем, что ячейки нет
	if not cell.has_node("ItemIcon"): return null 
	return cell

func _get_cell_at_pos(pos: Vector2) -> Control:
	for cell in grid.get_children():
		if cell.has_node("ItemIcon") and cell.get_global_rect().has_point(pos):
			return cell
	return null

func _find_first_free_slot(shape: Array) -> Control:
	for cell in grid.get_children():
		if cell.has_node("ItemIcon") and _can_place_shape(cell, shape): 
			return cell
	return null

func _hide_icons_for_shape(root: Control, _shape: Array):
	root.get_node("ItemIcon").hide()

func _show_icons_for_shape(root: Control, _shape: Array):
	root.get_node("ItemIcon").show()

func start_appear_animation():
	show()
	modulate.a = 0.0
	var final_y = backpack_bg.position.y
	backpack_bg.position.y += hide_pos_offset
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.5)
	tw.tween_property(backpack_bg, "position:y", final_y, 0.7)
	backpack_bg.pivot_offset = backpack_bg.size / 2.0
	backpack_bg.scale = Vector2(0.7, 0.7)
	tw.tween_property(backpack_bg, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK)