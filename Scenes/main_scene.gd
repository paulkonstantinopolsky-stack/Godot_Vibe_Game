extends Node3D

signal autofill_finished

@onready var order_popup = $UILayer/Order_PopUp
@onready var env_back = $UILayer/Order_PopUp/EnvelopeBack
@onready var env_front = $UILayer/Order_PopUp/EnvelopeFront
@onready var letter = $UILayer/Order_PopUp/LetterContainer
@onready var start_button = $UILayer/Start_Button
@onready var ready_button = $UILayer/Ready_Button
@onready var timer_label = $UILayer/Order_PopUp/LetterContainer/LetterPaper/Timer
@onready var side_widget = $UILayer/SideWidget
@onready var backpack_widget = $UILayer/BackpackWidget
@onready var drag_preview = $UILayer/DragPreview
@onready var autofill_button = get_node_or_null("UILayer/AutofillButton")
@onready var attempts_widget = get_node_or_null("UILayer/AttemptsWidget")

@export_group("Ссылки на объекты")
@export var cabinet: Node3D

@export_group("Настройки Времени")
@export var total_time: float = 10.0

@export_group("Конверт (Envelope)")
@export var env_intro_fade: float = 0.2
@export var env_intro_start_y: float = 2300.0
@export var env_intro_end_y: float = 1800.0
@export var env_intro_duration: float = 1.0
@export var env_intro_trans: Tween.TransitionType = Tween.TRANS_CIRC
@export var env_intro_ease: Tween.EaseType = Tween.EASE_OUT
@export var env_outro_fade: float = 0.3
@export var env_outro_end_y: float = 2300.0
@export var env_outro_duration: float = 0.8
@export var env_outro_trans: Tween.TransitionType = Tween.TRANS_CIRC
@export var env_outro_ease: Tween.EaseType = Tween.EASE_IN

@export_group("Письмо (Letter)")
@export var let_intro_delay: float = 0.3
@export var let_intro_fade: float = 0.2
@export var let_intro_start_y: float = -2000.0
@export var let_intro_end_y: float = 500.0 
@export var let_intro_start_scale_y: float = 0.1
@export var let_intro_end_scale_y: float = 1.0
@export var let_intro_duration: float = 0.5
@export var let_intro_trans: Tween.TransitionType = Tween.TRANS_CIRC
@export var let_intro_ease: Tween.EaseType = Tween.EASE_OUT
@export var let_outro_delay: float = 0.0
@export var let_outro_fade: float = 0.3
@export var let_outro_end_y: float = -2000.0
@export var let_outro_start_scale_y: float = 1.0
@export var let_outro_end_scale_y: float = 0.5
@export var let_outro_duration: float = 0.5
@export var let_outro_trans: Tween.TransitionType = Tween.TRANS_CIRC
@export var let_outro_ease: Tween.EaseType = Tween.EASE_IN

var time_left: float
var is_timer_active: bool = false
var is_game_started: bool = false

var potential_drag_id: int = -1
var potential_drag_tex: String = ""
var potential_drag_node: Node3D = null 
var current_drag_node: Node3D = null   
var drag_start_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD: float = 15.0 

var cinematic_queue: int = 0
var is_cinematic_playing: bool = false
var is_autofill_animating: bool = false
var fast_cinematic_count: int = 0
var autofill_cab_tween: Tween

func _ready():
	ItemManager.reset_level_state()

	if start_button: start_button.pressed.connect(_on_start_pressed)
	if ready_button: ready_button.pressed.connect(_on_ready_pressed)
	if autofill_button:
		autofill_button.pressed.connect(_on_autofill_pressed)
		autofill_button.hide()
	
	ready_button.modulate.a = 0.0; ready_button.hide()
	env_back.modulate.a = 0.0; env_front.modulate.a = 0.0; letter.modulate.a = 0.0
	
	if side_widget: side_widget.hide()
	if backpack_widget: backpack_widget.hide()
	if drag_preview: drag_preview.hide()
	if cabinet: cabinet.hide()
	if attempts_widget: attempts_widget.hide()

	if cabinet:
		cabinet.all_rewards_collected_visually.connect(_on_all_rewards_collected_visually)

	ItemManager.item_pressed.connect(_on_item_pressed)

	ItemManager.perfect_clear_achieved.connect(_on_perfect_clear)
	ItemManager.level_completed.connect(_on_level_completed_normal)
	ItemManager.combo_broken.connect(_on_combo_broken)
	ItemManager.item_unfound.connect(_on_item_unfound)
	ItemManager.out_of_attempts.connect(_on_out_of_attempts)

func _on_item_unfound(id: int):
	if not side_widget:
		return
	var items_container = side_widget.items_container
	var flipped_entries = []
	for entry in items_container.get_children():
		if int(entry.item_id) == int(id) and entry.get_meta("is_flipped", false):
			flipped_entries.append(entry)

	if flipped_entries.size() > 0:
		var entry = flipped_entries.back()
		entry.flip_to_back()
		entry.set_meta("is_flipped", false)

func _trigger_backpack_jump() -> void:
	# Прячем UI перед финальным прыжком
	if side_widget: side_widget.hide()
	if attempts_widget: attempts_widget.hide()
	if autofill_button: autofill_button.hide()

	# Запускаем сам прыжок
	if backpack_widget and backpack_widget.has_method("start_order_completed_sequence"):
		backpack_widget.start_order_completed_sequence()

func _on_all_rewards_collected_visually() -> void:
	_trigger_backpack_jump()

func _on_combo_broken() -> void:
	if side_widget and side_widget.has_node("ComboWidget"):
		var cw = side_widget.get_node("ComboWidget")
		if cw.has_method("show_fail"):
			cw.show_fail()

func _on_perfect_clear() -> void:
	if is_autofill_animating:
		await autofill_finished

	var popup: Control = load("res://Scenes/perfect_popup.gd").new() as Control
	popup.z_index = 400
	$UILayer.add_child(popup)
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.play_animation(func():
		cinematic_queue = 3
		_play_next_cinematic()
	)

	# Нет шкафа — сигнала all_rewards_collected_visually не будет; взлёт через 1с после появления Perfect
	if cabinet == null:
		get_tree().create_timer(1.0).timeout.connect(_on_all_rewards_collected_visually)

func _on_level_completed_normal() -> void:
	if ItemManager.combo_failed:
		# Если шкаф еще крутится от автосбора - ждем!
		if is_autofill_animating:
			await autofill_finished

		_trigger_backpack_jump()

func _on_out_of_attempts() -> void:
	var popup_scene = load("res://Scenes/OutOfAttemptsPopup.tscn")
	if not popup_scene:
		printerr("Не удалось загрузить OutOfAttemptsPopup.tscn!")
		return

	var popup_instance = popup_scene.instantiate()
	$UILayer.add_child(popup_instance)

	if popup_instance.has_signal("popup_closed"):
		popup_instance.connect("popup_closed", func(action: String):
			if action == "continue":
				_trigger_backpack_jump()
			elif action == "autofill":
				_play_ad_autofill_sequence()
		)
	else:
		printerr("ОШИБКА: Сигнал 'popup_closed' не найден в out_of_attempts_popup.gd.")

	popup_instance.open_popup(attempts_widget)

func _play_ad_autofill_sequence() -> void:
	await get_tree().create_timer(0.3).timeout
	_on_autofill_pressed()
	# Прыжок здесь больше не вызываем! Он вызовется автоматически
	# через _on_level_completed_normal, когда _on_autofill_pressed закончит анимацию шкафа.

func _process(delta):
	if is_timer_active and time_left > 0:
		time_left -= delta
		if timer_label: timer_label.text = str(ceil(time_left)) + "s"
		if time_left <= 0: _on_timer_timeout()
			
	if cinematic_queue > 0 and not is_cinematic_playing and not ItemManager.is_dragging_item and not is_autofill_animating:
		_play_next_cinematic()

func _play_next_cinematic():
	is_cinematic_playing = true
	cinematic_queue -= 1
	if cabinet and cabinet.has_method("reveal_next_bonus_cell"):
		var use_fast = fast_cinematic_count > 0
		if use_fast:
			fast_cinematic_count -= 1
		if cabinet.has_method("set_bonus_reveal_speed_multiplier"):
			cabinet.set_bonus_reveal_speed_multiplier(2.0 if use_fast else 1.0)
		if cabinet.has_method("set_bonus_post_open_delay_multiplier"):
			cabinet.set_bonus_post_open_delay_multiplier(2.0 if use_fast else 1.0)
		if cabinet.has_method("set_bonus_fixed_post_open_delay"):
			cabinet.set_bonus_fixed_post_open_delay(0.25 if use_fast else -1.0)
		cabinet.reveal_next_bonus_cell(func(): is_cinematic_playing = false)
	else:
		is_cinematic_playing = false

func _find_cabinet_item_node(parent_node: Node, target_id: int, ignore_list: Array = []) -> Node3D:
	if parent_node == null:
		return null
	if not parent_node in ignore_list:
		if "id" in parent_node and parent_node.get("id") == target_id: return parent_node as Node3D
		if "item_id" in parent_node and parent_node.get("item_id") == target_id: return parent_node as Node3D
	for child in parent_node.get_children():
		var found = _find_cabinet_item_node(child, target_id, ignore_list)
		if found: return found
	return null

func _on_autofill_pressed():
	if not is_game_started or not backpack_widget or is_cinematic_playing or is_autofill_animating: return
	if ItemManager.is_dragging_item or backpack_widget.is_dragging_internal: return

	# СОБИРАЕМ РЕАЛЬНЫЕ ДАННЫЕ ИЗ ШКАФА
	var required_data = []
	var used_cab_nodes = []
	for task in ItemManager.current_order:
		if not task["found"]:
			var id = task["id"]
			var cab_node = _find_cabinet_item_node(cabinet, id, used_cab_nodes)
			var actual_shape = []

			# Берем сгенерированную форму прямо из 3D-предмета
			if cab_node and cab_node.has_meta("puzzle_shape"):
				actual_shape = cab_node.get_meta("puzzle_shape")
				used_cab_nodes.append(cab_node)
			else:
				actual_shape = ItemManager.items_db[id].get("shape", [Vector2.ZERO])

			required_data.append({
				"id": id,
				"shape": actual_shape,
				"cab_node": cab_node
			})

	if required_data.size() == 0: return

	# ПЕРЕДАЕМ РЕАЛЬНЫЕ ДАННЫЕ В РЮКЗАК
	var placements = backpack_widget.auto_fill_and_optimize(required_data)
	if placements.size() == 0: return

	is_autofill_animating = true

	var fly_data_array = []
	for place_data in placements:
		var cab_node = place_data["cab_node"]
		fly_data_array.append({
			"id": place_data["id"],
			"cell": place_data["cell"],
			"cab_node": cab_node,
			"start_y": cab_node.global_position.y if cab_node else -9999.0
		})
		if cab_node and is_instance_valid(cab_node) and is_instance_valid(place_data["cell"]):
			place_data["cell"].set_meta("source_drag_node", cab_node)

	fly_data_array.sort_custom(func(a, b): return a["start_y"] > b["start_y"])

	var total_anim_time = 1.0 + (fly_data_array.size() * 0.15)
	if cabinet:
		if autofill_cab_tween and autofill_cab_tween.is_running():
			autofill_cab_tween.kill()
		autofill_cab_tween = create_tween().bind_node(self).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		autofill_cab_tween.tween_property(cabinet, "rotation_degrees:y", cabinet.rotation_degrees.y + 720.0, total_anim_time)

	var cam = get_viewport().get_camera_3d()
	var queue_before = cinematic_queue
	for i in range(fly_data_array.size()):
		var data = fly_data_array[i]
		var id = data["id"]; var target_cell = data["cell"]; var cab_node = data["cab_node"]

		ItemManager.mark_item_as_found(id)

		var target_pos = target_cell.global_position
		var target_rot = target_cell.get_meta("rot_deg", 0)
		var target_shape = target_cell.get_meta("current_shape")

		# Генерируем полноценный паззл через рюкзак
		var fly_icon = backpack_widget.create_standalone_puzzle_visual(id, target_shape, target_rot)
		fly_icon.z_index = 100
		fly_icon.modulate.a = 0.0
		$UILayer.add_child(fly_icon)

		var start_tw = create_tween().bind_node(self)
		start_tw.tween_interval(i * 0.15)
		start_tw.tween_callback(func():
			var start_pos = get_viewport().get_visible_rect().size / 2.0
			if cab_node:
				if cab_node.has_method("hide_item"): cab_node.hide_item()
				else: cab_node.hide()
				if cam: start_pos = cam.unproject_position(cab_node.global_position)

			fly_icon.global_position = start_pos - (fly_icon.size / 2.0)
			fly_icon.scale = Vector2(0.2, 0.2) # Вылетает маленьким из шкафа
			fly_icon.modulate.a = 1.0

			var anim_tw = create_tween().bind_node(self).set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			anim_tw.tween_property(fly_icon, "global_position", target_pos, 0.4)
			anim_tw.tween_property(fly_icon, "scale", Vector2.ONE, 0.4)
			# Вращение не нужно, так как форма паззла уже повернута правильно внутри контейнера

			anim_tw.chain().tween_callback(func():
				fly_icon.queue_free()
				if is_instance_valid(target_cell):
					# Снимаем флаг ожидания
					target_cell.set_meta("hide_bg_until_land", false)

					if target_cell.has_node("ItemIcon"):
						target_cell.get_node("ItemIcon").show()

					# ВАЖНО: Вызываем обновление визуала рюкзака, чтобы вернуть фон
					if backpack_widget and backpack_widget.has_method("_update_grid_visuals"):
						backpack_widget._update_grid_visuals()
			)
		)
	var added_cinematics = cinematic_queue - queue_before
	if added_cinematics > 0:
		fast_cinematic_count += added_cinematics

	if autofill_button:
		var tw = create_tween().bind_node(self).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(autofill_button, "modulate:a", 0.0, 0.3)
		tw.tween_callback(autofill_button.hide)
		
	get_tree().create_timer(total_anim_time).timeout.connect(func():
		is_autofill_animating = false
		autofill_finished.emit()
	)

func _on_item_pressed(id: int, tex: String, node: Node3D):
	if is_cinematic_playing: return
	potential_drag_id = id; potential_drag_tex = tex; potential_drag_node = node
	drag_start_pos = get_viewport().get_mouse_position()

func _input(event):
	if is_cinematic_playing: return 
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if potential_drag_id != -1:
			if ItemManager.is_dragging_item: _perform_drop()
			else: _reset_drag_instant() 

	if event is InputEventMouseMotion and potential_drag_id != -1:
		if not ItemManager.is_dragging_item:
			var diff = event.position - drag_start_pos
			if diff.length() > DRAG_THRESHOLD:
				if abs(diff.y) > abs(diff.x): _start_drag() 
				else: _reset_drag_instant() 
		else:
			if backpack_widget and backpack_widget.has_method("update_external_drag_preview"):
				backpack_widget.update_external_drag_preview(event.position)

func _start_drag():
	ItemManager.is_dragging_item = true
	current_drag_node = potential_drag_node
	if cabinet and cabinet.has_method("focus_item_face_to_camera") and current_drag_node and not is_cinematic_playing:
		cabinet.focus_item_face_to_camera(current_drag_node, 0.35)
	if current_drag_node and current_drag_node.has_method("hide_item"): current_drag_node.hide_item()
	if drag_preview: drag_preview.hide()
	if backpack_widget and backpack_widget.has_method("show_external_drag_preview"):
		var shape_to_draw: Array
		if current_drag_node and current_drag_node.has_meta("puzzle_shape"):
			shape_to_draw = current_drag_node.get_meta("puzzle_shape")
		else:
			shape_to_draw = ItemManager.items_db[potential_drag_id].get("shape", [Vector2.ZERO])
		backpack_widget.show_external_drag_preview(
			potential_drag_id,
			get_viewport().get_mouse_position(),
			shape_to_draw
		)

func _perform_drop():
	var mouse_pos = get_viewport().get_mouse_position()
	var dropped_successfully = false

	if backpack_widget:
		var forgiving_drop_zone = backpack_widget.get_global_rect().grow(200.0)
		if forgiving_drop_zone.has_point(mouse_pos):
			if backpack_widget.has_method("try_add_item"):
				dropped_successfully = backpack_widget.try_add_item(potential_drag_id, mouse_pos, potential_drag_node)

	if dropped_successfully:
		current_drag_node = null
		_reset_drag_instant()
	else:
		_fly_back_and_cancel()

func _fly_back_and_cancel():
	if autofill_cab_tween and autofill_cab_tween.is_running(): autofill_cab_tween.kill()
	if backpack_widget and backpack_widget.has_method("hide_external_drag_preview"): backpack_widget.hide_external_drag_preview()
	var node_to_return = current_drag_node
	if node_to_return and is_instance_valid(node_to_return):
		var tex_path = potential_drag_tex
		var fly_icon = TextureRect.new()
		if potential_drag_id != -1 and ItemManager.items_db.has(potential_drag_id):
			fly_icon.texture = ItemManager.items_db[potential_drag_id].get("texture_res")
		if fly_icon.texture == null:
			fly_icon.texture = load(tex_path)
		fly_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fly_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fly_icon.size = fly_icon.texture.get_size() if fly_icon.texture else Vector2(100, 100)
		fly_icon.pivot_offset = fly_icon.size / 2.0
		fly_icon.global_position = get_viewport().get_mouse_position() - fly_icon.pivot_offset
		fly_icon.z_index = 100
		$UILayer.add_child(fly_icon)

		if drag_preview: drag_preview.hide()

		const FOCUS_DURATION := 0.2
		if cabinet and cabinet.has_method("focus_item_face_to_camera") and node_to_return and not is_cinematic_playing:
			cabinet.focus_item_face_to_camera(node_to_return, FOCUS_DURATION, true)

		var local_fly_tween = create_tween().bind_node(self).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		local_fly_tween.tween_interval(FOCUS_DURATION)
		local_fly_tween.tween_callback(_run_fly_icon_return_after_focus.bind(fly_icon, node_to_return))
	current_drag_node = null
	potential_drag_id = -1; potential_drag_node = null; ItemManager.is_dragging_item = false

func _reset_drag_instant():
	potential_drag_id = -1; potential_drag_node = null; ItemManager.is_dragging_item = false; _hide_preview_only()

func _hide_preview_only():
	if backpack_widget and backpack_widget.has_method("hide_external_drag_preview"): backpack_widget.hide_external_drag_preview()
	if drag_preview: drag_preview.hide(); drag_preview.texture = null
	if current_drag_node and current_drag_node.has_method("show_item"): current_drag_node.show_item()
	current_drag_node = null

func _on_start_pressed():
	start_button.hide()
	ItemManager.generate_new_order()
	if order_popup.has_method("fill_order_icons"): order_popup.fill_order_icons()
	is_game_started = false; time_left = total_time
	
	order_popup.position.y = env_intro_start_y; letter.position.y = let_intro_start_y; letter.scale.y = let_intro_start_scale_y
	var tween = create_tween().bind_node(self).set_parallel(true)
	tween.tween_property(order_popup, "position:y", env_intro_end_y, env_intro_duration).set_trans(env_intro_trans).set_ease(env_intro_ease)
	tween.tween_property(env_back, "modulate:a", 1.0, env_intro_fade); tween.tween_property(env_front, "modulate:a", 1.0, env_intro_fade)
	tween.tween_property(letter, "position:y", let_intro_end_y, let_intro_duration).set_trans(let_intro_trans).set_ease(let_intro_ease).set_delay(let_intro_delay)
	tween.tween_property(letter, "scale:y", let_intro_end_scale_y, let_intro_duration).set_trans(let_intro_trans).set_ease(let_outro_ease).set_delay(let_intro_delay)
	tween.tween_property(letter, "modulate:a", 1.0, let_intro_fade).set_delay(let_intro_delay)
	
	await get_tree().create_timer(let_intro_delay + let_intro_duration).timeout
	if !is_game_started: ready_button.show(); create_tween().bind_node(self).tween_property(ready_button, "modulate:a", 1.0, 0.2); is_timer_active = true

func _on_ready_pressed():
	if is_game_started: return
	is_timer_active = false; start_game_flow()

func _on_timer_timeout():
	if is_game_started: return
	is_timer_active = false; start_game_flow()

func start_game_flow():
	is_game_started = true; ready_button.disabled = true
	if cabinet: cabinet.build_cabinet_tornado()
	var outro = create_tween().bind_node(self).set_parallel(true)
	outro.tween_property(order_popup, "position:y", env_outro_end_y, env_outro_duration).set_trans(env_outro_trans).set_ease(env_outro_ease)
	outro.tween_property(env_back, "modulate:a", 0.0, env_outro_fade); outro.tween_property(env_front, "modulate:a", 0.0, env_outro_fade)
	outro.tween_property(letter, "position:y", let_outro_end_y, let_outro_duration).set_trans(let_outro_trans).set_ease(let_outro_ease).set_delay(let_outro_delay)
	outro.tween_property(letter, "scale:y", let_outro_end_scale_y, let_outro_duration).set_trans(let_outro_trans).set_ease(let_outro_ease).set_delay(let_outro_delay)
	outro.tween_property(letter, "modulate:a", 0.0, let_outro_fade).set_delay(let_outro_delay)
	outro.tween_property(ready_button, "modulate:a", 0.0, let_outro_fade)
	
	outro.chain().tween_callback(ready_button.hide)
	outro.chain().tween_callback(func():
		if side_widget: side_widget.start_appear_animation()
		if backpack_widget: backpack_widget.start_appear_animation()
		if attempts_widget: attempts_widget.start_appear_animation()
		if autofill_button: autofill_button.modulate.a = 1.0; autofill_button.show()
	)

func _run_fly_icon_return_after_focus(fly_icon: TextureRect, drag_node: Node3D) -> void:
	var cam = get_viewport().get_camera_3d()
	var target_pos = drag_start_pos - fly_icon.pivot_offset

	if cam and drag_node and is_instance_valid(drag_node):
		# ПРОВЕРКА НА ПОЗИЦИЮ ЗА КАМЕРОЙ
		if cam.is_position_behind(drag_node.global_position):
			fly_icon.queue_free()
			if drag_node.has_method("show_item"): drag_node.show_item()
			else: drag_node.show()
			return

		target_pos = cam.unproject_position(drag_node.global_position) - fly_icon.pivot_offset

	var local_inner_tween = create_tween().bind_node(self).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	local_inner_tween.tween_property(fly_icon, "global_position", target_pos, 0.3)
	local_inner_tween.tween_callback(func():
		fly_icon.queue_free()
		if drag_node and is_instance_valid(drag_node):
			if drag_node.has_method("show_item"): drag_node.show_item()
			else: drag_node.show()
	)

func fly_back_to_cabinet(item_id: int, start_pos: Vector2, drag_node: Node3D, skip_unmark: bool = false):
	const FOCUS_DURATION := 0.2
	if item_id == -1: ItemManager.is_dragging_item = false; return

	# Пропускаем снятие флага, если это делает Autofill (очистка мусора)
	if not skip_unmark:
		ItemManager.unmark_item_as_found(item_id)

	if autofill_cab_tween and autofill_cab_tween.is_running(): autofill_cab_tween.kill()
	ItemManager.is_dragging_item = false
	if not ItemManager.items_db.has(item_id):
		if drag_node and is_instance_valid(drag_node):
			if drag_node.has_method("show_item"): drag_node.show_item()
			else: drag_node.show()
		return
	var db_entry = ItemManager.items_db[item_id]
	var fly_icon = TextureRect.new()
	fly_icon.texture = db_entry.get("texture_res")
	if fly_icon.texture == null and db_entry.get("texture", "") != "":
		fly_icon.texture = load(db_entry["texture"])
	fly_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fly_icon.size = fly_icon.texture.get_size() if fly_icon.texture else Vector2(100, 100)
	fly_icon.pivot_offset = fly_icon.size / 2.0
	fly_icon.global_position = start_pos - fly_icon.pivot_offset
	fly_icon.z_index = 100
	$UILayer.add_child(fly_icon)

	if drag_preview: drag_preview.hide()

	if cabinet and cabinet.has_method("focus_item_face_to_camera") and drag_node and not is_cinematic_playing:
		cabinet.focus_item_face_to_camera(drag_node, FOCUS_DURATION, true)

	var local_fly_tween = create_tween().bind_node(self).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	local_fly_tween.tween_interval(FOCUS_DURATION)
	local_fly_tween.tween_callback(_run_fly_icon_return_after_focus.bind(fly_icon, drag_node))
