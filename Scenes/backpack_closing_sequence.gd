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

func _ready():
	current_frame_index = 0

	if affordance_ui:
		affordance_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in affordance_ui.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Запоминаем оригинальные позиции, чтобы не ломать якоря родителя
	if stars: stars_base_pos = stars.position
	if hand: hand_base_pos = hand.position

	_start_stars_rotation()
	_start_idle_animation()

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
	stars_tw.tween_property(stars, "rotation_degrees", 360.0, 4.0).as_relative()

func _start_idle_animation():
	if not hand: return
	if idle_tw and idle_tw.is_valid():
		idle_tw.kill()

	hand.show()
	# Восстанавливаем оригинальную позицию из редактора (вместо жесткого 0)
	hand.position = hand_base_pos
	hand.modulate.a = 0.0

	idle_tw = create_tween().bind_node(self).set_loops()

	var drop_y = hand_base_pos.y + 60.0

	# Свайп 1
	idle_tw.tween_property(hand, "modulate:a", 1.0, 0.2)
	idle_tw.parallel().tween_property(hand, "position:y", drop_y, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	idle_tw.tween_property(hand, "modulate:a", 0.0, 0.2)
	idle_tw.tween_property(hand, "position:y", hand_base_pos.y, 0.0)

	# Свайп 2
	idle_tw.tween_property(hand, "modulate:a", 1.0, 0.2)
	idle_tw.parallel().tween_property(hand, "position:y", drop_y, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	idle_tw.tween_property(hand, "modulate:a", 0.0, 0.2)
	idle_tw.tween_property(hand, "position:y", hand_base_pos.y, 0.0)

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
		if affordance_ui:
			create_tween().bind_node(self).tween_property(affordance_ui, "modulate:a", 0.0, 0.2)
		emit_signal("packing_completed")
	else:
		if not is_dragging:
			_start_idle_animation()
