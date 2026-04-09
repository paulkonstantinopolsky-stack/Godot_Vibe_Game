extends Control

signal packing_completed

@onready var frame_display = $FrameDisplay
@onready var drag_handle = $DragHandle

# --- УЗЛЫ UI (НОВЫЕ) ---
@onready var affordance_ui = get_node_or_null("AffordanceUI")
@onready var stars = get_node_or_null("AffordanceUI/Stars")
@onready var hand = get_node_or_null("AffordanceUI/Hand")

var frames = [
	preload("res://Assets/Backpack_animation/B1.png"),
	preload("res://Assets/Backpack_animation/B2.png"),
	preload("res://Assets/Backpack_animation/B3.png"),
	preload("res://Assets/Backpack_animation/B4.png"),
	preload("res://Assets/Backpack_animation/B5.png"),
	preload("res://Assets/Backpack_animation/B6.png"),
	preload("res://Assets/Backpack_animation/B7.png"),
	preload("res://Assets/Backpack_animation/B8.png")
]

var total_frames = 8
var current_frame_index = 0

var is_dragging = false
var drag_start_y = 0.0
var frame_start_index = 0
@export var drag_sensitivity = 400.0

# --- ПЕРЕМЕННЫЕ ВИРТУАЛЬНОГО ДЖОЙСТИКА ---
var stars_base_pos: Vector2 = Vector2.ZERO
var hand_base_pos: Vector2 = Vector2.ZERO
var drag_start_local_pos: Vector2 = Vector2.ZERO
var idle_tw: Tween
var stars_tw: Tween

@export var joystick_radius: float = 100.0
@export var ui_follow_speed: float = 25.0
@export var strap_visual_distance: float = 350.0 # НОВАЯ: На сколько пикселей реально опускается ручка к 8 кадру

# --- ПЕРЕМЕННЫЕ ФИНАЛА (VICTORY) ---
var is_sealed: bool = false
var glint_mat: ShaderMaterial
var float_tw: Tween
var frame_base_pos: Vector2

func _ready():
	current_frame_index = 0

	if affordance_ui:
		affordance_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in affordance_ui.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if stars: stars_base_pos = stars.position
		if hand: hand_base_pos = hand.position
		
		# --- ЗАДЕРЖКА ПЕРЕД ПОЯВЛЕНИЕМ ПОДСКАЗКИ ---
		affordance_ui.modulate.a = 0.0
		var delay_tw = create_tween().bind_node(self)
		delay_tw.tween_interval(0.9) # Ждем пока рюкзак приземлится
		delay_tw.tween_callback(func():
			_start_stars_rotation()
			_start_idle_animation()
		)
		delay_tw.tween_property(affordance_ui, "modulate:a", 1.0, 0.4)

	# --- ИНИЦИАЛИЗАЦИЯ ШЕЙДЕРА И КЛИКА ПОБЕДЫ ---
	glint_mat = ShaderMaterial.new()
	glint_mat.shader = load("res://Shaders/glint.gdshader")
	glint_mat.set_shader_parameter("progress", -0.1)
	if frame_display:
		frame_display.material = glint_mat

	gui_input.connect(_on_victory_click)
	# --------------------------------------------

	_update_frame()
	drag_handle.gui_input.connect(_on_handle_input)

# --- БЕСКОНЕЧНО ПЛАВНЫЙ ПОДВИЖНЫЙ UI (60 FPS) ---
func _process(delta: float) -> void:
	if not stars: return

	var target_offset = Vector2.ZERO

	if is_dragging:
		var finger_offset = get_local_mouse_position() - drag_start_local_pos

		# По X: классическое ограничение джойстика
		var clamped_x = clamp(finger_offset.x, -joystick_radius, joystick_radius)

		var clamped_y = 0.0
		if finger_offset.y > 0:
			# Вычисляем прогресс свайпа (от 0.0 до 1.0)
			var pull_progress = clamp(finger_offset.y / drag_sensitivity, 0.0, 1.0)
			# Мапим прогресс на РЕАЛЬНОЕ визуальное расстояние ручки
			clamped_y = pull_progress * strap_visual_distance

			# Эффект натяжения: если тянем дальше 100%, даем оттянуться еще на 40px
			if finger_offset.y > drag_sensitivity:
				clamped_y += min(finger_offset.y - drag_sensitivity, 40.0)
		else:
			# Если тянем вверх от стартовой точки
			clamped_y = clamp(finger_offset.y, -50.0, 0.0)

		target_offset = Vector2(clamped_x, clamped_y)

	# Двигаем ТОЛЬКО звезды, сохраняя их изначальный центр
	stars.position = stars.position.lerp(stars_base_pos + target_offset, ui_follow_speed * delta)

func _start_stars_rotation():
	if not stars: return
	stars_tw = create_tween().bind_node(self).set_loops()
	stars_tw.tween_property(stars, "rotation_degrees", 360.0, 20.0).as_relative()

func _start_idle_animation():
	if not hand: return
	if idle_tw and idle_tw.is_valid():
		idle_tw.kill()

	hand.show()
	# Восстанавливаем оригинальную позицию из редактора
	hand.position = hand_base_pos
	hand.modulate.a = 0.0

	idle_tw = create_tween().bind_node(self).set_loops()

	var drop_y = hand_base_pos.y + 60.0

	# Единственный свайп
	idle_tw.tween_property(hand, "modulate:a", 1.0, 0.2)
	idle_tw.parallel().tween_property(hand, "position:y", drop_y, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	idle_tw.tween_property(hand, "modulate:a", 0.0, 0.2)
	idle_tw.tween_property(hand, "position:y", hand_base_pos.y, 0.0)

	# Пауза перед следующим циклом
	idle_tw.tween_interval(2.0)

func _update_frame():
	if frames.size() > 0 and current_frame_index < frames.size():
		frame_display.texture = frames[current_frame_index]

func _on_handle_input(event):
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			is_dragging = true
			drag_start_y = event.position.y
			frame_start_index = current_frame_index

			# Чистая локальная координата клика
			drag_start_local_pos = get_local_mouse_position()

			if idle_tw and idle_tw.is_valid(): idle_tw.kill()
			if hand:
				var hide_tw = create_tween().bind_node(self)
				hide_tw.tween_property(hand, "modulate:a", 0.0, 0.1)
				hide_tw.tween_callback(hand.hide)

		else:
			is_dragging = false
			
			# МГНОВЕННО прячем UI при отпускании, если ремешок дотянут до конца
			if current_frame_index == total_frames - 1 and affordance_ui:
				affordance_ui.hide()
				
			_check_snap()

	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and is_dragging):
		if is_dragging:
			# Физика переключения кадров рюкзака (остается на локальных координатах)
			var delta_y = event.position.y - drag_start_y
			var frame_delta = int((delta_y / drag_sensitivity) * total_frames)
			var new_index = clamp(frame_start_index + frame_delta, 0, total_frames - 1)

			if new_index != current_frame_index:
				current_frame_index = new_index
				_update_frame()

func _check_snap():
	var target_frame = 0
	if current_frame_index * 2 > total_frames:
		target_frame = total_frames - 1

	var tween = create_tween()
	tween.tween_method(_animate_frame_snap, current_frame_index, target_frame, 0.3)
	tween.finished.connect(_on_snap_finished)

func _animate_frame_snap(frame_val):
	current_frame_index = int(frame_val)
	_update_frame()

func _on_snap_finished():
	if current_frame_index == total_frames - 1:
		_enter_victory_state()
	else:
		if not is_dragging:
			_start_idle_animation()


# ==========================================================
# --- ЛОГИКА ПОБЕДЫ И ЗАВЕРШЕНИЯ ---
# ==========================================================
func _enter_victory_state():
	if is_sealed: return
	is_sealed = true

	if drag_handle: drag_handle.hide()

	if frame_display:
		# Устанавливаем пивот в центр для правильного сжатия
		frame_display.pivot_offset = frame_display.size / 2.0
		frame_base_pos = frame_display.position

		var tw = create_tween().bind_node(self).set_parallel(true)

		# Уменьшаем рюкзак в 2 раза
		tw.tween_property(frame_display, "scale", Vector2(0.5, 0.5), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		# Пускаем красивый блик
		glint_mat.set_shader_parameter("progress", 0.0)
		tw.tween_method(
			func(v: float): glint_mat.set_shader_parameter("progress", v),
			0.0, 1.0, 0.6
		).set_trans(Tween.TRANS_SINE).set_delay(0.1)

		tw.chain().tween_callback(_start_victory_float)


func _start_victory_float():
	if not frame_display: return
	float_tw = create_tween().bind_node(self).set_loops()
	var amp = 60.0 # Амплитуда левитации (т.к. масштаб 0.5, визуально это будет летать очень приятно)

	float_tw.tween_property(frame_display, "position:y", frame_base_pos.y - amp, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tw.tween_property(frame_display, "position:y", frame_base_pos.y + amp, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tw.tween_property(frame_display, "position:y", frame_base_pos.y, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_victory_click(event):
	if is_sealed:
		# not event.pressed означает, что игрок отпустил ЛКМ или убрал палец с экрана
		var is_mouse_release = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
		var is_touch_release = event is InputEventScreenTouch and not event.pressed

		if is_mouse_release or is_touch_release:
			if float_tw and float_tw.is_valid(): float_tw.kill()
			emit_signal("packing_completed")
