extends Node3D

# --- ССЫЛКИ НА УЗЛЫ (Переменные) ---
@onready var order_popup = $CanvasLayer/Order_PopUp
@onready var env_back = $CanvasLayer/Order_PopUp/EnvelopeBack
@onready var env_front = $CanvasLayer/Order_PopUp/EnvelopeFront
@onready var letter = $CanvasLayer/Order_PopUp/LetterContainer
@onready var start_button = $CanvasLayer/Start_Button
@onready var ready_button = $CanvasLayer/Ready_Button
@onready var timer_label = $CanvasLayer/Order_PopUp/LetterContainer/LetterPaper/Timer

@export_group("Ссылки на объекты")
@export var cabinet: Node3D

@export_group("Настройки Времени")
@export var total_time: float = 10.0

# --- НАСТРОЙКИ АНИМАЦИИ (Твои оригинальные значения) ---
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

# --- СОСТОЯНИЕ ИГРЫ ---
var time_left: float
var is_timer_active: bool = false
var is_game_started: bool = false

# --- ОСНОВНЫЕ ФУНКЦИИ ---

func _ready():
	if start_button: start_button.pressed.connect(_on_start_pressed)
	if ready_button: ready_button.pressed.connect(_on_ready_pressed)
   
	ready_button.modulate.a = 0.0
	ready_button.hide()
	env_back.modulate.a = 0.0
	env_front.modulate.a = 0.0
	letter.modulate.a = 0.0
   
	if cabinet: cabinet.hide()

func _process(delta):
	if is_timer_active and time_left > 0:
		time_left -= delta
		if timer_label:
			timer_label.text = str(ceil(time_left)) + "s"
		if time_left <= 0:
			_on_timer_timeout()

func _on_start_pressed():
	start_button.hide()
	if has_node("/root/ItemManager"):
		ItemManager.generate_new_order()
	if order_popup.has_method("fill_order_icons"):
		order_popup.fill_order_icons()
   
	is_game_started = false
	time_left = total_time
   
	order_popup.position.y = env_intro_start_y
	letter.position.y = let_intro_start_y
	letter.scale.y = let_intro_start_scale_y
   
	var tween = create_tween().set_parallel(true)
	tween.tween_property(order_popup, "position:y", env_intro_end_y, env_intro_duration)\
		.set_trans(env_intro_trans).set_ease(env_intro_ease)
	tween.tween_property(env_back, "modulate:a", 1.0, env_intro_fade)
	tween.tween_property(env_front, "modulate:a", 1.0, env_intro_fade)
   
	tween.tween_property(letter, "position:y", let_intro_end_y, let_intro_duration)\
		.set_trans(let_intro_trans).set_ease(let_intro_ease).set_delay(let_intro_delay)
	tween.tween_property(letter, "scale:y", let_intro_end_scale_y, let_intro_duration)\
		.set_trans(let_intro_trans).set_ease(let_intro_ease).set_delay(let_intro_delay)
	tween.tween_property(letter, "modulate:a", 1.0, let_intro_fade).set_delay(let_intro_delay)
   
	await get_tree().create_timer(let_intro_delay + let_intro_duration).timeout
   
	if !is_game_started:
		ready_button.show()
		var btn_tween = create_tween()
		btn_tween.tween_property(ready_button, "modulate:a", 1.0, 0.2)
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
	if cabinet and cabinet.has_method("build_cabinet_tornado"):
		cabinet.build_cabinet_tornado()
   
	var outro = create_tween().set_parallel(true)
	outro.tween_property(order_popup, "position:y", env_outro_end_y, env_outro_duration)\
		.set_trans(env_outro_trans).set_ease(env_outro_ease)
	outro.tween_property(env_back, "modulate:a", 0.0, env_outro_fade)
	outro.tween_property(env_front, "modulate:a", 0.0, env_outro_fade)
   
	outro.tween_property(letter, "position:y", let_outro_end_y, let_outro_duration)\
		.set_trans(let_outro_trans).set_ease(let_outro_ease).set_delay(let_outro_delay)
	outro.tween_property(letter, "scale:y", let_outro_end_scale_y, let_outro_duration)\
		.set_trans(let_outro_trans).set_ease(let_outro_ease).set_delay(let_outro_delay)
	outro.tween_property(letter, "modulate:a", 0.0, let_outro_fade).set_delay(let_outro_delay)
   
	outro.tween_property(ready_button, "modulate:a", 0.0, let_outro_fade)
	outro.chain().tween_callback(ready_button.hide)
