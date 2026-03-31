extends Control

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
	grid.draw.connect(_on_grid_draw)
	_update_grid_visuals()

# ==========================================================
# --- АЛГОРИТМ АВТО-СБОРКИ (BIN PACKING) ---
# ==========================================================
func auto_fill_and_optimize(required_ids: Array) -> Array:
	_close_edit_mode()

	var existing_items = []
	var processed_roots = []
	for cell in grid.get_children():
		if not cell.has_node("ItemIcon"): continue
		var item_id = cell.get_meta("occupied_by_id", -1)
		if item_id != -1:
			var root = cell.get_meta("root_cell")
			if not processed_roots.has(root):
				processed_roots.append(root)
				existing_items.append({
					"id": item_id,
					"old_root": root,
					"old_shape": root.get_meta("current_shape"),
					"old_rot": root.get_meta("rot_deg", 0)
				})

	var to_pack = []
	for item in existing_items: to_pack.append({"id": item.id, "is_new": false})
	for id in required_ids: to_pack.append({"id": id, "is_new": true})

	to_pack.sort_custom(func(a, b):
		return ItemManager.items_db[a.id]["shape"].size() > ItemManager.items_db[b.id]["shape"].size()
	)

	_clear_entire_grid()

	var successfully_added_new = []
	var packing_failed = false

	for pack_item in to_pack:
		var placed = false
		var item_id = pack_item.id
		var base_shape = ItemManager.items_db[item_id]["shape"]

		for r in range(4):
			if placed: break
			var test_shape = _rotate_shape_normalized(base_shape, r * 90)

			for cell in grid.get_children():
				if not cell.has_node("ItemIcon"): continue
				if _can_place_shape(cell, test_shape):
					_place_item_in_grid(cell, item_id, test_shape, r * 90)
					placed = true
					
					if pack_item.is_new: 
						successfully_added_new.append({"id": item_id, "cell": cell})
						# ВАЖНО: Прячем иконку! Она включится, когда долетит анимация из MainScene
						cell.get_node("ItemIcon").hide()
					break

		if not placed:
			if not pack_item.is_new: 
				packing_failed = true 
				break 
			else:
				continue 

	if packing_failed:
		_clear_entire_grid()
		for item in existing_items:
			_place_item_in_grid(item.old_root, item.id, item.old_shape, item.old_rot)
		print("Авто-сборка: Не хватает места для перетасовки!")
		return []

	if successfully_added_new.size() > 0 or existing_items.size() > 0:
		backpack_bg.pivot_offset = backpack_bg.size / 2.0
		var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		backpack_bg.scale = Vector2(0.95, 0.95)
		tw.tween_property(backpack_bg, "scale", Vector2.ONE, 0.3)

	return successfully_added_new

func _clear_entire_grid():
	var roots = []
	for cell in grid.get_children():
		if cell.has_node("ItemIcon"):
			var r = cell.get_meta("root_cell", null)
			if r and not roots.has(r): roots.append(r)
	for r in roots:
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
func _align_icon_in_bbox(icon: TextureRect, item_id: int, current_shape: Array, rot_deg: int):
	if grid.get_child_count() == 0: return
	var c_size = grid.get_child(0).size
	var h_sep = grid.get_theme_constant("h_separation")
	var v_sep = grid.get_theme_constant("v_separation")
	var spacing = Vector2(max(0, h_sep), max(0, v_sep))

	var orig_shape = ItemManager.items_db[item_id]["shape"]
	var o_max_x = 0; var o_max_y = 0
	for p in orig_shape:
		if p.x > o_max_x: o_max_x = p.x
		if p.y > o_max_y: o_max_y = p.y
		
	var orig_w = (o_max_x + 1) * c_size.x + o_max_x * spacing.x
	var orig_h = (o_max_y + 1) * c_size.y + o_max_y * spacing.y

	icon.size = Vector2(orig_w, orig_h)
	icon.pivot_offset = icon.size / 2.0
	icon.rotation_degrees = rot_deg

	var c_max_x = 0; var c_max_y = 0
	for p in current_shape:
		if p.x > c_max_x: c_max_x = p.x
		if p.y > c_max_y: c_max_y = p.y

	var cur_w = (c_max_x + 1) * c_size.x + c_max_x * spacing.x
	var cur_h = (c_max_y + 1) * c_size.y + c_max_y * spacing.y

	var target_center = Vector2(cur_w, cur_h) / 2.0
	icon.position = target_center - icon.pivot_offset

# ==========================================================
# --- МОНОЛИТНАЯ ОТРИСОВКА ---
# ==========================================================
func _get_merged_stylebox(shape: Array, offset: Vector2, is_focused: bool, is_preview: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#401E0D") 
	if is_preview: style.border_color = Color("#FFAE3C") 
	else: style.border_color = Color("#ffffff") if is_focused else Color("#FFAE3C")
	style.set_border_width_all(6)
	style.set_corner_radius_all(12) 
	style.anti_aliasing = true

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
	var h_sep = grid.get_theme_constant("h_separation")
	var v_sep = grid.get_theme_constant("v_separation")
	var spacing = Vector2(max(0, h_sep), max(0, v_sep))

	for offset in shape:
		var target_coords = _get_cell_coords(start_cell) + Vector2i(offset.x, offset.y)
		var target_cell = _get_cell_by_coords(target_coords)
		if not target_cell: continue

		var rect = Rect2(target_cell.position, target_cell.size)
		var expand = 3.0 
		if shape.has(offset + Vector2(1, 0)): rect.size.x += spacing.x + expand
		if shape.has(offset + Vector2(0, 1)): rect.size.y += spacing.y + expand
		if shape.has(offset + Vector2(-1, 0)): rect.position.x -= expand; rect.size.x += expand
		if shape.has(offset + Vector2(0, -1)): rect.position.y -= expand; rect.size.y += expand

		var style = _get_merged_stylebox(shape, offset, is_focused, false)
		style.draw(grid.get_canvas_item(), rect)

func _on_grid_draw():
	var processed_roots = []
	for cell in grid.get_children():
		if not cell.has_node("ItemIcon"): continue
		var item_id = cell.get_meta("occupied_by_id", -1)
		if item_id != -1:
			var root_cell = cell.get_meta("root_cell")
			if not processed_roots.has(root_cell):
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
		if is_occupied and is_dragging_internal and cell.get_meta("root_cell") == active_cell:
			is_occupied = false

		if is_occupied: border.hide() 
		else: border.show(); border.set_state(1 if ItemManager.is_edit_mode else 0)
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
	for c in drag_preview_container.get_children(): c.queue_free()
	var sample_cell = null
	for c in grid.get_children():
		if c.has_node("ItemIcon"): sample_cell = c; break
	if not sample_cell: return

	var c_size = sample_cell.size
	var h_sep = grid.get_theme_constant("h_separation")
	var v_sep = grid.get_theme_constant("v_separation")
	var spacing = Vector2(max(0, h_sep), max(0, v_sep))
	
	for offset in shape:
		var panel = Panel.new()
		var style = _get_merged_stylebox(shape, offset, false, true) 
		panel.add_theme_stylebox_override("panel", style)
		var p_pos = Vector2(offset.x * (c_size.x + spacing.x), offset.y * (c_size.y + spacing.y))
		var p_size = c_size
		var expand = 3.0
		if shape.has(offset + Vector2(1, 0)): p_size.x += spacing.x + expand
		if shape.has(offset + Vector2(0, 1)): p_size.y += spacing.y + expand
		if shape.has(offset + Vector2(-1, 0)): p_pos.x -= expand; p_size.x += expand
		if shape.has(offset + Vector2(0, -1)): p_pos.y -= expand; p_size.y += expand

		panel.position = p_pos; panel.size = p_size
		drag_preview_container.add_child(panel)

	var icon = TextureRect.new()
	icon.texture = load(ItemManager.items_db[item_id]["texture"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_preview_container.add_child(icon)
	_align_icon_in_bbox(icon, item_id, shape, rot_deg)

func show_external_drag_preview(item_id: int, mouse_pos: Vector2):
	var shape = ItemManager.items_db[item_id]["shape"]
	build_drag_preview(item_id, shape, 0)
	update_external_drag_preview(mouse_pos)
	drag_preview_container.show()

func update_external_drag_preview(mouse_pos: Vector2):
	for c in grid.get_children():
		if c.has_node("ItemIcon"): drag_preview_container.global_position = mouse_pos - (c.size / 2.0); break

func hide_external_drag_preview():
	drag_preview_container.hide()

# ==========================================================
# --- ОСТАЛЬНАЯ ЛОГИКА ---
# ==========================================================
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
					var target_rot = target_root.get_meta("rot_deg", 0)
					if target_root == active_cell and ItemManager.is_edit_mode:
						is_dragging_internal = true
						_hide_icons_for_shape(active_cell, active_shape)
						build_drag_preview(active_item_id, active_shape, target_rot)
						update_external_drag_preview(mouse_pos)
						drag_preview_container.show()
						_update_grid_visuals()
						get_viewport().set_input_as_handled()
					else:
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
					var old_rot = active_cell.get_meta("rot_deg", 0)
					_clear_item_from_grid(active_cell, active_shape)
					active_cell = target_root
					_place_item_in_grid(active_cell, active_item_id, active_shape, old_rot)
					success = true
				if not success: _show_icons_for_shape(active_cell, active_shape)
				_update_grid_visuals()
				get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and is_dragging_internal:
		update_external_drag_preview(mouse_pos)
		get_viewport().set_input_as_handled()

func try_add_item(item_id: int, mouse_pos: Vector2, drag_node: Node3D = null) -> bool:
	var item_data = ItemManager.items_db.get(item_id)
	if not item_data: return false
	var shape = item_data["shape"]
	var target_root = _get_cell_at_pos(mouse_pos)
	if not target_root: target_root = _find_first_free_slot(shape)
	if target_root and _can_place_shape(target_root, shape):
		_place_item_in_grid(target_root, item_id, shape, 0)
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
		if occupant_id != -1 and not (ignore_active and cell.get_meta("root_cell") == active_cell): 
			return false
	return true

func _place_item_in_grid(root_cell: Control, item_id: int, shape: Array, rot_deg: int):
	var tex_path = ItemManager.items_db[item_id]["texture"]
	var icon = root_cell.get_node("ItemIcon")
	icon.texture = load(tex_path)
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
	root_cell.get_node("ItemIcon").texture = null
	root_cell.get_node("ItemIcon").hide()
	_update_grid_visuals()

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
	if active_item_id == -1: return # Жесткий блок от двойных кликов
	
	var confirmed_id = active_item_id 
	_close_edit_mode()                
	ItemManager.mark_item_as_found(confirmed_id)

func _on_btn_cancel():
	var fly_pos = active_cell.global_position + (active_cell.size / 2.0)
	var shape_to_clear = active_shape.duplicate()
	var cell_to_clear = active_cell
	var item_to_return = active_item_id
	var drag_node_to_return = active_drag_node
	_close_edit_mode(); _clear_item_from_grid(cell_to_clear, shape_to_clear)
	if get_tree().current_scene.has_method("fly_back_to_cabinet"): get_tree().current_scene.fly_back_to_cabinet(item_to_return, fly_pos, drag_node_to_return)

func _start_edit_mode(cell: Control, item_id: int, drag_node: Node3D, shape: Array = []):
	var was_edit_mode = ItemManager.is_edit_mode
	active_cell = cell; active_item_id = item_id; active_drag_node = drag_node
	active_shape = shape if shape.size() > 0 else ItemManager.items_db[item_id]["shape"]
	ItemManager.is_edit_mode = true
	if edit_menu and not was_edit_mode:
		edit_menu.modulate.a = 1.0; edit_menu.show(); edit_menu.scale = Vector2(0.5, 0.5)
		edit_menu.pivot_offset = edit_menu.size / 2.0
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(edit_menu, "scale", Vector2.ONE, 0.2)
	_update_grid_visuals()

func _close_edit_mode():
	ItemManager.is_edit_mode = false; active_cell = null; active_item_id = -1
	_update_grid_visuals()
	if edit_menu:
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(edit_menu, "scale", Vector2(0.5, 0.5), 0.15)
		tw.tween_property(edit_menu, "modulate:a", 0.0, 0.15)
		tw.chain().tween_callback(edit_menu.hide)

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
	show(); modulate.a = 0.0; var final_y = backpack_bg.position.y
	backpack_bg.position.y += hide_pos_offset
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.5); tw.tween_property(backpack_bg, "position:y", final_y, 0.7)
	backpack_bg.pivot_offset = backpack_bg.size / 2.0; backpack_bg.scale = Vector2(0.7, 0.7)
	tw.tween_property(backpack_bg, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK)