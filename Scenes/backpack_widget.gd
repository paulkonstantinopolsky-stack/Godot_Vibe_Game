extends Control

@onready var backpack_bg = $BackpackBG
@onready var grid = $BackpackBG/CenterContainer/VBoxContainer
@onready var edit_menu = get_node_or_null("EditMenu") 

var hide_pos_offset = 600 

var active_cell: Control = null
var active_item_id: int = -1
var active_drag_node: Node3D = null
var active_shape: Array = []

# --- ПЕРЕМЕННЫЕ ВНУТРЕННЕГО ПЕРЕТАСКИВАНИЯ ---
var is_dragging_internal: bool = false
var internal_drag_preview: Control
var preview_bg: TextureRect
var preview_border: TextureRect
var preview_icon: TextureRect

func _ready():
	hide()
	modulate.a = 0.0
	
	if edit_menu:
		edit_menu.hide()
		if edit_menu.has_node("BtnRotate"): edit_menu.get_node("BtnRotate").pressed.connect(_on_btn_rotate)
		if edit_menu.has_node("BtnConfirm"): edit_menu.get_node("BtnConfirm").pressed.connect(_on_btn_confirm)
		if edit_menu.has_node("BtnCancel"): edit_menu.get_node("BtnCancel").pressed.connect(_on_btn_cancel)
	
	_setup_internal_drag_preview()
	_set_all_borders(0)

func _setup_internal_drag_preview():
	internal_drag_preview = Control.new()
	internal_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	internal_drag_preview.z_index = 20
	
	preview_bg = TextureRect.new()
	preview_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	internal_drag_preview.add_child(preview_bg)
	
	preview_border = TextureRect.new()
	preview_border.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	internal_drag_preview.add_child(preview_border)
	
	preview_icon = TextureRect.new()
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	internal_drag_preview.add_child(preview_icon)
	
	add_child(internal_drag_preview)
	internal_drag_preview.hide()

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

func _input(event):
	if not ItemManager.is_edit_mode or active_cell == null:
		return

	var mouse_pos = get_global_mouse_position()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_mouse_over_active_cell(mouse_pos):
				is_dragging_internal = true
				_hide_icons_for_shape(active_cell, active_shape)
				
				internal_drag_preview.size = active_cell.size
				preview_bg.size = active_cell.size
				preview_border.size = active_cell.size
				preview_icon.size = active_cell.size
				
				var cell_border = active_cell.get_node_or_null("CellBorder")
				if cell_border:
					preview_bg.texture = cell_border.default_bg_texture
					if cell_border.default_png:
						preview_border.texture = cell_border.default_png.texture
				
				var orig_icon = active_cell.get_node("ItemIcon")
				preview_icon.texture = orig_icon.texture
				preview_icon.rotation_degrees = orig_icon.rotation_degrees
				preview_icon.pivot_offset = preview_icon.size / 2.0
				
				internal_drag_preview.global_position = mouse_pos - (internal_drag_preview.size / 2.0)
				internal_drag_preview.show()
				if edit_menu: edit_menu.hide()
				get_viewport().set_input_as_handled()
		else:
			if is_dragging_internal:
				is_dragging_internal = false
				internal_drag_preview.hide()
				if not try_move_active_cell(mouse_pos):
					_show_icons_for_shape(active_cell, active_shape)
				if edit_menu: edit_menu.show()
				get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and is_dragging_internal:
		internal_drag_preview.global_position = mouse_pos - (internal_drag_preview.size / 2.0)
		get_viewport().set_input_as_handled()

# --- ЛОГИКА ТЕТРИСА ---

func try_add_item(item_id: int, mouse_pos: Vector2, drag_node: Node3D = null) -> bool:
	var item_data = ItemManager.items_db.get(item_id)
	if not item_data: return false
	
	var shape = item_data["shape"]
	var target_root = _get_cell_at_pos(mouse_pos)
	
	# Если не попали в ячейку мышкой, ищем первую свободную для этой формы
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
	
	var root_coords = _get_cell_coords(root_cell)
	for offset in shape:
		var cell = _get_cell_by_coords(root_coords + Vector2i(offset.x, offset.y))
		cell.set_meta("occupied_by_id", item_id)
		cell.set_meta("root_cell", root_cell)

func _clear_item_from_grid(root_cell: Control, shape: Array):
	var root_coords = _get_cell_coords(root_cell)
	for offset in shape:
		var cell = _get_cell_by_coords(root_coords + Vector2i(offset.x, offset.y))
		if cell:
			cell.remove_meta("occupied_by_id")
			cell.remove_meta("root_cell")
	root_cell.get_node("ItemIcon").texture = null
	root_cell.get_node("ItemIcon").hide()

# --- ПОВОРОТ И ПЕРЕМЕЩЕНИЕ ---

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

func try_move_active_cell(mouse_pos: Vector2) -> bool:
	var target_root = _get_cell_at_pos(mouse_pos)
	if target_root and _can_place_shape(target_root, active_shape, true):
		var old_rot = active_cell.get_node("ItemIcon").rotation_degrees
		_clear_item_from_grid(active_cell, active_shape)
		active_cell = target_root
		_place_item_in_grid(active_cell, active_item_id, active_shape)
		active_cell.get_node("ItemIcon").rotation_degrees = old_rot
		_refresh_edit_borders()
		return true
	return false

# --- УПРАВЛЕНИЕ РАМКАМИ (ИСПРАВЛЕНО) ---

func _set_all_borders(state_id: int):
	for row in grid.get_children():
		for cell in row.get_children():
			_set_single_border(cell, state_id)

func _set_single_border(cell: Control, state_id: int):
	var border = cell.get_node_or_null("CellBorder")
	if border and border.has_method("set_state"):
		border.set_state(state_id)

func _refresh_edit_borders():
	_set_all_borders(1)
	var rc = _get_cell_coords(active_cell)
	for offset in active_shape:
		var cell = _get_cell_by_coords(rc + Vector2i(offset.x, offset.y))
		if cell: _set_single_border(cell, 2)

# --- ВСПОМОГАТЕЛЬНЫЕ ---

func _get_cell_coords(cell: Control) -> Vector2i:
	return Vector2i(cell.get_index(), cell.get_parent().get_index())

func _get_cell_by_coords(coords: Vector2i) -> Control:
	if coords.y < 0 or coords.y >= grid.get_child_count(): return null
	var row = grid.get_child(coords.y)
	if coords.x < 0 or coords.x >= row.get_child_count(): return null
	return row.get_child(coords.x)

func _get_cell_at_pos(pos: Vector2) -> Control:
	for row in grid.get_children():
		for cell in row.get_children():
			if cell.get_global_rect().has_point(pos): return cell
	return null

func _find_first_free_slot(shape: Array) -> Control:
	for row in grid.get_children():
		for cell in row.get_children():
			if _can_place_shape(cell, shape): return cell
	return null

func is_mouse_over_active_cell(mouse_pos: Vector2) -> bool:
	if not active_cell: return false
	var rc = _get_cell_coords(active_cell)
	for offset in active_shape:
		var cell = _get_cell_by_coords(rc + Vector2i(offset.x, offset.y))
		if cell and cell.get_global_rect().has_point(mouse_pos): return true
	return false

func _hide_icons_for_shape(root: Control, shape: Array):
	root.get_node("ItemIcon").hide()

func _show_icons_for_shape(root: Control, shape: Array):
	root.get_node("ItemIcon").show()

func _start_edit_mode(cell: Control, item_id: int, drag_node: Node3D, shape: Array = []):
	active_cell = cell
	active_item_id = item_id
	active_drag_node = drag_node
	active_shape = shape if shape.size() > 0 else ItemManager.items_db[item_id]["shape"]
	ItemManager.is_edit_mode = true
	if edit_menu:
		edit_menu.modulate.a = 1.0
		edit_menu.show()
		edit_menu.scale = Vector2(0.5, 0.5)
		edit_menu.pivot_offset = edit_menu.size / 2.0
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(edit_menu, "scale", Vector2.ONE, 0.2)
	_refresh_edit_borders()

func _on_btn_confirm():
	_close_edit_mode()
	ItemManager.mark_item_as_found(active_item_id)

func _on_btn_cancel():
	var fly_pos = active_cell.global_position + (active_cell.size / 2.0)
	var shape_to_clear = active_shape.duplicate()
	var cell_to_clear = active_cell
	_close_edit_mode()
	_clear_item_from_grid(cell_to_clear, shape_to_clear)
	if get_tree().current_scene.has_method("fly_back_to_cabinet"):
		get_tree().current_scene.fly_back_to_cabinet(active_item_id, fly_pos, active_drag_node)

func _close_edit_mode():
	ItemManager.is_edit_mode = false
	_set_all_borders(0)
	if edit_menu:
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(edit_menu, "scale", Vector2(0.5, 0.5), 0.15)
		tw.tween_property(edit_menu, "modulate:a", 0.0, 0.15)
		tw.chain().tween_callback(edit_menu.hide)
