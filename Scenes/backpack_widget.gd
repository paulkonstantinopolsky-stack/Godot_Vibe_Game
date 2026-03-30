extends Control

@onready var backpack_bg = $BackpackBG
@onready var grid = $BackpackBG/CenterContainer/VBoxContainer
@onready var edit_menu = get_node_or_null("EditMenu") 

var hide_pos_offset = 600 

var active_cell: Control = null
var active_item_id: int = -1
var active_drag_node: Node3D = null

func _ready():
	hide()
	modulate.a = 0.0
	
	if edit_menu:
		edit_menu.hide()
		if edit_menu.has_node("BtnRotate"): edit_menu.get_node("BtnRotate").pressed.connect(_on_btn_rotate)
		if edit_menu.has_node("BtnConfirm"): edit_menu.get_node("BtnConfirm").pressed.connect(_on_btn_confirm)
		if edit_menu.has_node("BtnCancel"): edit_menu.get_node("BtnCancel").pressed.connect(_on_btn_cancel)
		
	_set_all_borders(0)

func start_appear_animation():
	show()
	modulate.a = 0.0
	var final_y = backpack_bg.position.y
	backpack_bg.position.y += hide_pos_offset
	
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.5)
	tw.tween_property(backpack_bg, "position:y", final_y, 0.7)
	
	backpack_bg.pivot_offset = backpack_bg.size / 2
	backpack_bg.scale = Vector2(0.7, 0.7)
	tw.tween_property(backpack_bg, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK)

# --- ЛОГИКА ДОБАВЛЕНИЯ ПРЕДМЕТА ---
func try_add_item(item_id: int, mouse_pos: Vector2, drag_node: Node3D = null) -> bool:
	var target_cell = _place_item_smartly(item_id, mouse_pos)
	if target_cell == null:
		return false 
		
	_start_edit_mode(target_cell, item_id, drag_node)
	return true

func _place_item_smartly(item_id: int, mouse_pos: Vector2) -> Control:
	var tex_path = ItemManager.items_db[item_id]["texture"]
	var target_cell = null
	
	for row in grid.get_children():
		for cell in row.get_children():
			if cell.get_global_rect().has_point(mouse_pos):
				var icon = cell.get_node("ItemIcon")
				if icon.texture == null or icon.texture.resource_path == "":
					target_cell = cell
				break 
		if target_cell: break
			
	if target_cell == null:
		for row in grid.get_children():
			for cell in row.get_children():
				var icon = cell.get_node("ItemIcon")
				if icon.texture == null or icon.texture.resource_path == "":
					target_cell = cell
					break
			if target_cell: break

	if target_cell == null:
		return null 

	var target_icon_node = target_cell.get_node("ItemIcon")
	target_icon_node.texture = load(tex_path)
	
	if target_icon_node is TextureRect:
		target_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		target_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
	target_icon_node.show() 
	
	target_icon_node.pivot_offset = target_icon_node.size / 2
	target_icon_node.scale = Vector2(0.2, 0.2)
	var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(target_icon_node, "scale", Vector2.ONE, 0.4)
	
	return target_cell

# --- УПРАВЛЕНИЕ РАМКАМИ ЯЧЕЕК ---
func _set_all_borders(state_id: int):
	for row in grid.get_children():
		for cell in row.get_children():
			var border = cell.get_node_or_null("CellBorder")
			if border and border.has_method("set_state"):
				border.set_state(state_id)

func _set_single_border(cell: Control, state_id: int):
	if cell:
		var border = cell.get_node_or_null("CellBorder")
		if border and border.has_method("set_state"):
			border.set_state(state_id)

# --- ЛОГИКА РЕЖИМА РЕДАКТИРОВАНИЯ ---
func _start_edit_mode(cell: Control, item_id: int, drag_node: Node3D):
	active_cell = cell
	active_item_id = item_id
	active_drag_node = drag_node
	ItemManager.is_edit_mode = true

	_set_all_borders(1)
	_set_single_border(active_cell, 2)

	if edit_menu:
		edit_menu.modulate.a = 1.0 # Убеждаемся, что прозрачность 100%
		edit_menu.show()
		edit_menu.scale = Vector2(0.5, 0.5)
		edit_menu.pivot_offset = edit_menu.size / 2.0
		var tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(edit_menu, "scale", Vector2.ONE, 0.2)

# --- ПЕРЕТАСКИВАНИЕ ВНУТРИ РЮКЗАКА ---
func is_mouse_over_active_cell(mouse_pos: Vector2) -> bool:
	if active_cell and active_cell.get_global_rect().has_point(mouse_pos):
		return true
	return false

func hide_active_icon_for_drag():
	if active_cell: active_cell.get_node("ItemIcon").hide()

func show_active_icon_after_drag():
	if active_cell: active_cell.get_node("ItemIcon").show()

func try_move_active_cell(mouse_pos: Vector2) -> bool:
	var target_cell = null
	
	for row in grid.get_children():
		for cell in row.get_children():
			if cell.get_global_rect().has_point(mouse_pos):
				var icon = cell.get_node("ItemIcon")
				if icon.texture == null or icon.texture.resource_path == "":
					target_cell = cell
				break
		if target_cell: break
		
	if target_cell and target_cell != active_cell:
		var icon_target = target_cell.get_node("ItemIcon")
		var icon_active = active_cell.get_node("ItemIcon")

		icon_target.texture = icon_active.texture
		icon_target.rotation_degrees = icon_active.rotation_degrees
		icon_target.show()

		icon_active.texture = null
		icon_active.hide()
		icon_active.rotation_degrees = 0

		_set_single_border(active_cell, 1)
		_set_single_border(target_cell, 2)

		active_cell = target_cell
		return true
	return false

# --- КНОПКИ МЕНЮ ---
func _on_btn_rotate():
	if active_cell:
		var icon = active_cell.get_node("ItemIcon")
		icon.pivot_offset = icon.size / 2
		var tw = create_tween()
		tw.tween_property(icon, "rotation_degrees", icon.rotation_degrees + 90, 0.15)

func _on_btn_confirm():
	_close_edit_mode()
	var is_correct = false
	for task in ItemManager.current_order:
		if task["id"] == active_item_id and not task["found"]:
			is_correct = true
			break
	if is_correct:
		ItemManager.mark_item_as_found(active_item_id)

func _on_btn_cancel():
	_close_edit_mode()
	var icon = active_cell.get_node("ItemIcon")
	
	# Вычисляем точный центр ячейки для красивого старта полета
	var fly_start_pos = active_cell.global_position + (active_cell.size / 2.0)
	
	icon.texture = null
	icon.hide()
	icon.rotation_degrees = 0
	
	if get_tree().current_scene.has_method("fly_back_to_cabinet"):
		get_tree().current_scene.fly_back_to_cabinet(active_item_id, fly_start_pos, active_drag_node)
	else:
		if active_drag_node:
			if active_drag_node.has_method("show_item"): active_drag_node.show_item()
			else: active_drag_node.show()

func _close_edit_mode():
	ItemManager.is_edit_mode = false
	_set_all_borders(0) 
	
	# Плавное исчезновение меню
	if edit_menu:
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(edit_menu, "scale", Vector2(0.5, 0.5), 0.15)
		tw.tween_property(edit_menu, "modulate:a", 0.0, 0.15)
		tw.chain().tween_callback(edit_menu.hide)
