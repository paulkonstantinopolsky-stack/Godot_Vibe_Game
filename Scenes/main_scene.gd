extends Node3D

# --- ССЫЛКИ НА УЗЛЫ ---
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
var fly_tween: Tween 
const DRAG_THRESHOLD: float = 15.0 

func _ready():
	if start_button: start_button.pressed.connect(_on_start_pressed)
	if ready_button: ready_button.pressed.connect(_on_ready_pressed)
	
	if autofill_button:
		autofill_button.pressed.connect(_on_autofill_pressed)
		autofill_button.hide()
	
	ready_button.modulate.a = 0.0
	ready_button.hide()
	env_back.modulate.a = 0.0
	env_front.modulate.a = 0.0
	letter.modulate.a = 0.0
	
	if side_widget: side_widget.hide()
	if backpack_widget: backpack_widget.hide()
	if drag_preview: drag_preview.hide()
	if cabinet: cabinet.hide()
		
	ItemManager.item_pressed.connect(_on_item_pressed)

func _process(delta):
	if is_timer_active and time_left > 0:
		time_left -= delta
		if timer_label:
			timer_label.text = str(ceil(time_left)) + "s"
		if time_left <= 0:
			_on_timer_timeout()

# ==========================================================
# --- ЛОГИКА АВТО-СБОРКИ И АНИМАЦИЙ ПОЛЕТА ---
# ==========================================================

# Умный поиск 3D предмета в шкафу по его ID
func _find_cabinet_item_node(parent_node: Node, target_id: int) -> Node3D:
	if parent_node == null: return null
	
	if "id" in parent_node and parent_node.get("id") == target_id: return parent_node as Node3D
	if "item_id" in parent_node and parent_node.get("item_id") == target_id: return parent_node as Node3D
	
	for child in parent_node.get_children():
		var found = _find_cabinet_item_node(child, target_id)
		if found: return found
		
	return null

func _on_autofill_pressed():
	if not is_game_started or not backpack_widget: return
	if ItemManager.is_dragging_item or backpack_widget.is_dragging_internal: return

	var required_ids = []
	for task in ItemManager.current_order:
		if not task["found"]:
			required_ids.append(task["id"])

	if required_ids.size() == 0: return

	# Теперь рюкзак возвращает массив словарей с данными о том, куда встали предметы
	var placements = backpack_widget.auto_fill_and_optimize(required_ids)

	# Запускаем каскадную анимацию полета для каждого предмета
	for i in range(placements.size()):
		var place_data = placements[i]
		var id = place_data["id"]
		var target_cell = place_data["cell"]
		
		ItemManager.mark_item_as_found(id)
		
		# Создаем летящую 2D-иконку
		var tex_path = ItemManager.items_db[id]["texture"]
		var fly_icon = TextureRect.new()
		fly_icon.texture = load(tex_path)
		fly_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fly_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fly_icon.size = target_cell.size
		fly_icon.pivot_offset = fly_icon.size / 2.0 # Для вращения в воздухе
		fly_icon.z_index = 100
		
		# 1. Ищем этот предмет в 3D-шкафу
		var cab_node = _find_cabinet_item_node(cabinet, id)
		var start_pos = get_viewport().get_visible_rect().size / 2.0 # Запасная точка (центр экрана)
		
		if cab_node:
			# Прячем предмет в шкафу!
			if cab_node.has_method("hide_item"): cab_node.hide_item()
			else: cab_node.hide()
			
			# Магия перевода 3D координат в 2D координаты экрана
			var cam = get_viewport().get_camera_3d()
			if cam:
				start_pos = cam.unproject_position(cab_node.global_position)
		
		# Ставим иконку в начальную точку
		fly_icon.global_position = start_pos - (fly_icon.size / 2.0)
		$UILayer.add_child(fly_icon)
		
		# 2. Летим в рюкзак с задержкой (каскадный эффект)
		var target_pos = target_cell.global_position
		var target_rot = target_cell.get_meta("rot_deg", 0)
		
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_interval(i * 0.15) # Каждые 0.15 сек вылетает новый предмет
		tw.chain().tween_property(fly_icon, "global_position", target_pos, 0.4)
		tw.parallel().tween_property(fly_icon, "rotation_degrees", target_rot, 0.4) # Поворот в воздухе!
		
		# 3. В конце полета удаляем фейковую иконку и показываем настоящую в рюкзаке
		tw.chain().tween_callback(func():
			fly_icon.queue_free()
			if is_instance_valid(target_cell) and target_cell.has_node("ItemIcon"):
				target_cell.get_node("ItemIcon").show()
		)

	# Плавно прячем кнопку Авто-сборки
	if autofill_button:
		var tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(autofill_button, "modulate:a", 0.0, 0.3)
		tw.tween_callback(autofill_button.hide)

# ==========================================================
# --- ОСТАЛЬНОЙ КОД ---
# ==========================================================

func _on_item_pressed(id: int, tex: String, node: Node3D):
	potential_drag_id = id
	potential_drag_tex = tex
	potential_drag_node = node
	drag_start_pos = get_viewport().get_mouse_position()

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if potential_drag_id != -1:
			if ItemManager.is_dragging_item:
				_perform_drop()
			else:
				_reset_drag_instant() 

	if event is InputEventMouseMotion and potential_drag_id != -1:
		if not ItemManager.is_dragging_item:
			var diff = event.position - drag_start_pos
			if diff.length() > DRAG_THRESHOLD:
				if abs(diff.y) > abs(diff.x):
					_start_drag() 
				else:
					_reset_drag_instant() 
		else:
			if backpack_widget and backpack_widget.has_method("update_external_drag_preview"):
				backpack_widget.update_external_drag_preview(event.position)

func _start_drag():
	if fly_tween and fly_tween.is_running(): fly_tween.kill()
	ItemManager.is_dragging_item = true
	current_drag_node = potential_drag_node
	if current_drag_node and current_drag_node.has_method("hide_item"): current_drag_node.hide_item()
	if drag_preview: drag_preview.hide() 
	if backpack_widget and backpack_widget.has_method("show_external_drag_preview"):
		backpack_widget.show_external_drag_preview(potential_drag_id, get_viewport().get_mouse_position())

func _perform_drop():
	var mouse_pos = get_viewport().get_mouse_position()
	var dropped_successfully = false
	if backpack_widget and backpack_widget.get_global_rect().has_point(mouse_pos):
		if backpack_widget.has_method("try_add_item"):
			dropped_successfully = backpack_widget.try_add_item(potential_drag_id, mouse_pos, potential_drag_node)
			
	if dropped_successfully: current_drag_node = null; _reset_drag_instant() 
	else: _fly_back_and_cancel() 

func _fly_back_and_cancel():
	if backpack_widget and backpack_widget.has_method("hide_external_drag_preview"): backpack_widget.hide_external_drag_preview()
	if drag_preview:
		drag_preview.texture = load(potential_drag_tex)
		drag_preview.custom_minimum_size = Vector2.ZERO
		drag_preview.size = drag_preview.texture.get_size() if drag_preview.texture else Vector2.ZERO
		drag_preview.global_position = get_viewport().get_mouse_position() - (drag_preview.size / 2.0)
		drag_preview.show()
		
		fly_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var target_pos = drag_start_pos - (drag_preview.size / 2.0)
		fly_tween.tween_property(drag_preview, "global_position", target_pos, 0.3)
		fly_tween.tween_callback(_hide_preview_only)
	else: _hide_preview_only()
	potential_drag_id = -1; potential_drag_node = null; ItemManager.is_dragging_item = false

func _reset_drag_instant():
	potential_drag_id = -1; potential_drag_node = null; ItemManager.is_dragging_item = false
	_hide_preview_only()

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
	var tween = create_tween().set_parallel(true)
	tween.tween_property(order_popup, "position:y", env_intro_end_y, env_intro_duration).set_trans(env_intro_trans).set_ease(env_intro_ease)
	tween.tween_property(env_back, "modulate:a", 1.0, env_intro_fade); tween.tween_property(env_front, "modulate:a", 1.0, env_intro_fade)
	tween.tween_property(letter, "position:y", let_intro_end_y, let_intro_duration).set_trans(let_intro_trans).set_ease(let_intro_ease).set_delay(let_intro_delay)
	tween.tween_property(letter, "scale:y", let_intro_end_scale_y, let_intro_duration).set_trans(let_intro_trans).set_ease(let_outro_ease).set_delay(let_intro_delay)
	tween.tween_property(letter, "modulate:a", 1.0, let_intro_fade).set_delay(let_intro_delay)
	
	await get_tree().create_timer(let_intro_delay + let_intro_duration).timeout
	if !is_game_started: ready_button.show(); create_tween().tween_property(ready_button, "modulate:a", 1.0, 0.2); is_timer_active = true

func _on_ready_pressed():
	if is_game_started: return
	is_timer_active = false; start_game_flow()

func _on_timer_timeout():
	if is_game_started: return
	is_timer_active = false; start_game_flow()

func start_game_flow():
	is_game_started = true; ready_button.disabled = true
	if cabinet: cabinet.build_cabinet_tornado()
	var outro = create_tween().set_parallel(true)
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
		if autofill_button:
			autofill_button.modulate.a = 1.0
			autofill_button.show()
	)

func fly_back_to_cabinet(item_id: int, start_pos: Vector2, drag_node: Node3D):
	if item_id == -1: ItemManager.is_dragging_item = false; return
	ItemManager.is_dragging_item = false
	if drag_preview:
		var tex_path = ItemManager.items_db[item_id]["texture"]
		drag_preview.texture = load(tex_path); drag_preview.custom_minimum_size = Vector2.ZERO
		drag_preview.size = drag_preview.texture.get_size() if drag_preview.texture else Vector2.ZERO
		drag_preview.global_position = start_pos - (drag_preview.size / 2.0); drag_preview.show()
		if fly_tween and fly_tween.is_running(): fly_tween.kill()
		fly_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var target_pos = drag_start_pos - (drag_preview.size / 2.0)
		fly_tween.tween_property(drag_preview, "global_position", target_pos, 0.3)
		fly_tween.tween_callback(func():
			drag_preview.hide(); drag_preview.texture = null
			if drag_node:
				if drag_node.has_method("show_item"): drag_node.show_item()
				else: drag_node.show()
		)
	else:
		if drag_node:
			if drag_node.has_method("show_item"): drag_node.show_item()
			else: drag_node.show()