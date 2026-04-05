extends Control

signal packing_completed

@onready var frame_display = $FrameDisplay
@onready var drag_handle = $DragHandle

# УКАЖИ ЗДЕСЬ ПУТИ К ТВОИМ 8 КАДРАМ!
var frames = [
	preload("res://Assets/Backpack_animation/B1.png"), # Замени на свои пути
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
@export var drag_sensitivity = 400.0 # В пикселях: сколько нужно потянуть для полного закрытия

func _ready():
	current_frame_index = 0
	_update_frame()
	drag_handle.gui_input.connect(_on_handle_input)

func _update_frame():
	if frames.size() > 0 and current_frame_index < frames.size():
		frame_display.texture = frames[current_frame_index]

func _on_handle_input(event):
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			is_dragging = true
			drag_start_y = event.position.y
			frame_start_index = current_frame_index
		else:
			is_dragging = false
			_check_snap()

	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and is_dragging):
		if is_dragging:
			var delta_y = event.position.y - drag_start_y
			var frame_delta = int((delta_y / drag_sensitivity) * total_frames)
			var new_index = clamp(frame_start_index + frame_delta, 0, total_frames - 1)

			if new_index != current_frame_index:
				current_frame_index = new_index
				_update_frame()

func _check_snap():
	var target_frame = 0
	if current_frame_index > total_frames / 2:
		target_frame = total_frames - 1

	var tween = create_tween()
	tween.tween_method(_animate_frame_snap, current_frame_index, target_frame, 0.3)
	tween.finished.connect(_on_snap_finished)

func _animate_frame_snap(frame_val):
	current_frame_index = int(frame_val)
	_update_frame()

func _on_snap_finished():
	if current_frame_index == total_frames - 1:
		emit_signal("packing_completed")
