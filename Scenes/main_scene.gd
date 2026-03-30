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

@export_group("Ссылки на объекты")
@export var cabinet: Node3D

@export_group("Настройки Времени")
@export var total_time: float = 10.0

# --- НАСТРОЙКИ АНИМАЦИИ ---
@export_group("Конверт (Envelope)")
@export_subgroup("Intro")
@export var env_intro_fade: float = 0.2
@export var env_intro_start_y: float = 2300.0
@export var env_intro_end_y: float = 1800.0
@export var env_intro_duration: float = 1.0
@export var env_intro_trans: Tween.TransitionType = Tween.TRANS_CIRC
@export var env_intro_ease: Tween.EaseType = Tween.EASE_OUT

@export_subgroup("Outro")
@export var env_outro_fade: float = 0.3
@export var env_outro_end_y: float = 2300.0
@export var env_outro_duration: float = 0.8
@export var env_outro_trans: Tween.TransitionType = Tween.TRANS_CIRC
@export var env_outro_ease: Tween.EaseType = Tween.EASE_IN

@export_group("Письмо (Letter)")
@export_subgroup("Intro")
@export var let_intro_delay: float = 0.3
@export var let_intro_fade: float = 0.2
@export var let_intro_start_y: float = -2000.0
@export var let_intro_end_y: float = 500.0 
@export var let_intro_start_scale_y: float = 0.1
@export var let_intro_end_scale_y: float = 1.0
@export var let_intro_duration: float = 0.5
@export var let_intro_trans: Tween.TransitionType = Tween.TRANS_CIRC
@export var let_intro_ease: Tween.EaseType = Tween.EASE_OUT

@export_subgroup("Outro")
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

# Переменные для Drag-and-Drop
var potential_drag_id: int = -1
var potential_drag_tex: String = ""
var potential_drag_node: Node3D = null 
var current_drag_node: Node3D = null   
var drag_start_pos: Vector2 = Vector2.ZERO
var fly_tween: Tween 
const DRAG_THRESHOLD: float = 15.0 # Мертвая зона

func _ready():
	if start_button: start_button.pressed.connect(_on_start_pressed)
	if ready_button: ready_button.pressed.connect(_on_ready_pressed)
	
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

# --- ЛОГИКА DRAG AND DROP ---
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
			# Ждем выхода из мертвой зоны (15px)
			if diff.length() > DRAG_THRESHOLD:
				if abs(diff.y) > abs(diff.x):
					_start_drag() # Потянули вниз - берем предмет
				else:
					_reset_drag_instant() # Потянули вбок - отдаем управление шкафу
		else:
			if drag_preview:
				drag_preview.global_position = event.position - (drag_preview.size / 2)

func _start_drag():
	if fly_tween and fly_tween.is_running():
		fly_tween.kill()
		
	ItemManager.is_dragging_item = true
	
	current_drag_node = potential_drag_node
	if current_drag_node and current_drag_node.has_method("hide_item"):
		current_drag_node.hide_item()
	
	if drag_preview:
		drag_preview.texture = load(potential_drag_tex)
		drag_preview.custom_minimum_size = Vector2.ZERO
		drag_preview.size = drag_preview.texture.get_size() if drag_preview.texture else Vector2.ZERO
		drag_preview.show()
		drag_preview.global_position = get_viewport().get_mouse_position() - (drag_preview.size / 2)

func _perform_drop():
	var mouse_pos = get_viewport().get_mouse_position()
	var dropped_successfully = false
	
	if backpack_widget and backpack_widget.get_global_rect().has_point(mouse_pos):
		if backpack_widget.has_method("try_add_item"):
			dropped_successfully = backpack_widget.try_add_item(potential_drag_id, mouse_pos)
			
	if dropped_successfully:
		current_drag_node = null 
		_reset_drag_instant() 
	else:
		_fly_back_and_cancel() 

func _fly_back_and_cancel():
	potential_drag_id = -1
	potential_drag_node = null
	ItemManager.is_dragging_item = false
		
	if drag_preview:
		fly_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var target_pos = drag_start_pos - (drag_preview.size / 2)
		fly_tween.tween_property(drag_preview, "global_position", target_pos, 0.3)
		fly_tween.tween_callback(_hide_preview_only)

func _reset_drag_instant():
	potential_drag_id = -1
	potential_drag_node = null
	ItemManager.is_dragging_item = false
	_hide_preview_only()

func _hide_preview_only():
	if drag_preview:
		drag_preview.hide()
		drag_preview.texture = null
		
	if current_drag_node and current_drag_node.has_method("show_item"):
		current_drag_node.show_item()
	current_drag_node = null
# ------------------------------

func _on_start_pressed():
	start_button.hide()
	ItemManager.generate_new_order()
	if order_popup.has_method("fill_order_icons"):
		order_popup.fill_order_icons()
	
	is_game_started = false
	time_left = total_time
	
	order_popup.position.y = env_intro_start_y
	letter.position.y = let_intro_start_y
	letter.scale.y = let_intro_start_scale_y
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(order_popup, "position:y", env_intro_end_y, env_intro_duration).set_trans(env_intro_trans).set_ease(env_intro_ease)
	tween.tween_property(env_back, "modulate:a", 1.0, env_intro_fade)
	tween.tween_property(env_front, "modulate:a", 1.0, env_intro_fade)
	
	tween.tween_property(letter, "position:y", let_intro_end_y, let_intro_duration).set_trans(let_intro_trans).set_ease(let_intro_ease).set_delay(let_intro_delay)
	tween.tween_property(letter, "scale:y", let_intro_end_scale_y, let_intro_duration).set_trans(let_intro_trans).set_ease(let_intro_ease).set_delay(let_intro_delay)
	tween.tween_property(letter, "modulate:a", 1.0, let_intro_fade).set_delay(let_intro_delay)
	
	await get_tree().create_timer(let_intro_delay + let_intro_duration).timeout
	
	if !is_game_started:
		ready_button.show()
		create_tween().tween_property(ready_button, "modulate:a", 1.0, 0.2)
		is_timer_active = true

func _on_ready_pressed():
	if is_game_started: return
	is_timer_active = false
	start_game_flow()

func _on_timer_timeout():
	if is_game_started: return
	is_timer_active = false
	start_game_flow()

func start_game_flow():
	is_game_started = true
	ready_button.disabled = true
	if cabinet: cabinet.build_cabinet_tornado()
	
	var outro = create_tween().set_parallel(true)
	outro.tween_property(order_popup, "position:y", env_outro_end_y, env_outro_duration).set_trans(env_outro_trans).set_ease(env_outro_ease)
	outro.tween_property(env_back, "modulate:a", 0.0, env_outro_fade)
	outro.tween_property(env_front, "modulate:a", 0.0, env_outro_fade)
	
	outro.tween_property(letter, "position:y", let_outro_end_y, let_outro_duration).set_trans(let_outro_trans).set_ease(let_outro_ease).set_delay(let_outro_delay)
	outro.tween_property(letter, "scale:y", let_outro_end_scale_y, let_outro_duration).set_trans(let_outro_trans).set_ease(let_outro_ease).set_delay(let_outro_delay)
	outro.tween_property(letter, "modulate:a", 0.0, let_outro_fade).set_delay(let_outro_delay)
	
	outro.tween_property(ready_button, "modulate:a", 0.0, let_outro_fade)
	
	outro.chain().tween_callback(ready_button.hide)
	outro.chain().tween_callback(func(): 
		if side_widget: 
			side_widget.start_appear_animation()
		if backpack_widget: 
			backpack_widget.start_appear_animation() 
	)
