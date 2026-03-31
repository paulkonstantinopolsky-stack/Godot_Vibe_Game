extends Node3D

const COLUMNS: int = 8
const STEP_ANGLE: float = deg_to_rad(45.0)
const ROWS: int = 5
const CELL_HEIGHT: float = 1.25
const VERTICAL_SPACING: float = 1.6
const BLENDER_RADIUS: float = 1.88
const CAP_FIT_RADIUS: float = 1.9
const CAP_BOTTOM_Y: float = -1.3
const CAP_TOP_Y_MARGIN: float = 0.0

@export_group("Параметры анимации")
@export var cell_fly_duration: float = 1.2
@export var spawn_distance_min: float = 15.0
@export var spawn_distance_max: float = 30.0
@export var total_rotation_degrees: float = 360.0

@export_group("Поэтапная сборка")
@export var delay_between_rows: float = 0.2
@export var delay_between_cells_in_row: float = 0.05

@export_group("ГЕОМЕТРИЯ (Стыковка)")
@export var width_scale: float = 1.01
@export var geometric_radial_offset: float = 0.0
@export var manual_mesh_width: float = 2.0

@export_group("Интерполяция")
@export var trans_type: Tween.TransitionType = Tween.TRANS_CUBIC
@export var ease_type: Tween.EaseType = Tween.EASE_OUT

@export_group("Интерактив (iOS Style)")
@export var sensitivity: float = 0.2
@export var throw_momentum_factor: float = 1.5
@export var friction: float = 0.94
@export var snap_velocity_limit: float = 0.08

@export_group("Хаптик (Сейф)")
@export var haptics_enabled: bool = true
@export var haptic_click_ms: int = 10

var can_rotate: bool = false
var is_dragging: bool = false
var is_swipe_confirmed: bool = false 
var drag_start_pos_v: Vector2 = Vector2.ZERO
var angular_velocity: float = 0.0
var last_frame_x: float = 0.0
var snap_tween: Tween
var last_haptic_index: int = 0

var red_cell_scene = preload("res://Scenes/Cell_Red.tscn")
var green_cell_scene = preload("res://Scenes/Cell_Green.tscn")
var cap_scene = preload("res://Scenes/Top_Down.tscn")
var item_3d_scene = preload("res://Scenes/Item_3d.tscn")

var active_red_cells = []
var bonus_reveal_speed_multiplier: float = 1.0
var bonus_post_open_delay_multiplier: float = 1.0
var bonus_fixed_post_open_delay: float = -1.0

func set_bonus_reveal_speed_multiplier(mult: float) -> void:
	bonus_reveal_speed_multiplier = max(mult, 0.01)

func set_bonus_post_open_delay_multiplier(mult: float) -> void:
	bonus_post_open_delay_multiplier = max(mult, 0.01)

func set_bonus_fixed_post_open_delay(seconds: float) -> void:
	bonus_fixed_post_open_delay = seconds

func _ready() -> void:
	hide()

func _process(delta: float) -> void:
	if not can_rotate: return
	if not is_dragging:
		if abs(angular_velocity) > 0.001:
			rotate_y(angular_velocity * delta)
			angular_velocity *= friction
			_check_haptic_click()
			if abs(angular_velocity) < snap_velocity_limit:
				if snap_tween == null or not snap_tween.is_running():
					_start_snap()

func _input(event: InputEvent) -> void:
	if not can_rotate: return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		is_dragging = false
		if is_swipe_confirmed:
			var total_drag = event.position.x - drag_start_pos_v.x
			angular_velocity += (total_drag * throw_momentum_factor) * 0.01
		is_swipe_confirmed = false
		return
		
	if ItemManager.is_dragging_item:
		is_dragging = false
		is_swipe_confirmed = false
		return 
	
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch:
		if event.pressed:
			is_dragging = false 
			is_swipe_confirmed = false
			drag_start_pos_v = event.position
			last_frame_x = event.position.x
			angular_velocity = 0.0
			_stop_snap()
				
	if (event is InputEventMouseMotion or event is InputEventScreenDrag):
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_dragging = true
			if not is_swipe_confirmed:
				var diff = event.position - drag_start_pos_v
				if diff.length() > 15.0: 
					if abs(diff.x) > abs(diff.y):
						is_swipe_confirmed = true 
						last_frame_x = event.position.x 
					else:
						is_dragging = false 
						return
						
			if is_swipe_confirmed:
				var delta_x = event.position.x - last_frame_x
				rotate_y(deg_to_rad(delta_x * sensitivity))
				angular_velocity = deg_to_rad(delta_x / (1.0/60.0)) * 2.0
				last_frame_x = event.position.x
				_check_haptic_click()

func _check_haptic_click() -> void:
	if not haptics_enabled: return
	var current_index = int(round(rotation.y / STEP_ANGLE))
	if current_index != last_haptic_index:
		Input.vibrate_handheld(haptic_click_ms)
		last_haptic_index = current_index

func _start_snap() -> void:
	var target_rot = round(rotation.y / STEP_ANGLE) * STEP_ANGLE
	if abs(rotation.y - target_rot) < 0.001: return
	_stop_snap()
	snap_tween = create_tween()
	snap_tween.tween_property(self, "rotation:y", target_rot, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	snap_tween.finished.connect(func(): _check_haptic_click())
	angular_velocity = 0.0

func _stop_snap() -> void:
	if snap_tween: snap_tween.kill()

func build_cabinet_tornado() -> void:
	for child in get_children():
		child.queue_free()
		
	show()
	can_rotate = false
	active_red_cells.clear()
	
	var spawn_list = []
	for order_item in ItemManager.current_order:
		spawn_list.append(order_item["id"])
	var all_ids = ItemManager.items_db.keys()
	while spawn_list.size() < (ROWS * COLUMNS):
		spawn_list.append(all_ids[randi() % all_ids.size()])
	spawn_list.shuffle()
	
	var all_indices = []
	for i in range(ROWS * COLUMNS): all_indices.append(i)
	all_indices.shuffle()
	var bonus_indices = all_indices.slice(0, 3)
	
	var tangential_max_width = 2.0 * BLENDER_RADIUS * tan(STEP_ANGLE / 2.0)
	var target_scale_x = (tangential_max_width / manual_mesh_width) * width_scale
	var final_radial_position = BLENDER_RADIUS + geometric_radial_offset
	var total_assembly_time = (ROWS * delay_between_rows) + (COLUMNS * delay_between_cells_in_row) + cell_fly_duration
	
	rotation.y = 0
	last_haptic_index = 0
	
	var cabinet_tween = create_tween()
	cabinet_tween.tween_property(self, "rotation:y", deg_to_rad(total_rotation_degrees), total_assembly_time)\
		.set_trans(trans_type).set_ease(ease_type)
	cabinet_tween.finished.connect(func(): can_rotate = true)
	
	for row in range(ROWS):
		var current_row_delay = row * delay_between_rows
		var row_y = float(row) * CELL_HEIGHT * VERTICAL_SPACING
		
		for i in range(COLUMNS):
			var current_index = row * COLUMNS + i
			var is_red = current_index in bonus_indices
			
			var angle: float = float(i) * STEP_ANGLE
			var target_pos := Vector3(cos(angle) * final_radial_position, row_y, sin(angle) * final_radial_position)

			var cell
			if is_red:
				cell = red_cell_scene.instantiate()
				active_red_cells.append({"cell": cell, "col": i})
				# В красную ячейку предмет НЕ добавляем! Монетка там уже есть по умолчанию.
			else:
				cell = green_cell_scene.instantiate()
				# В зелёную ячейку добавляем предмет
				var item_node = item_3d_scene.instantiate()
				cell.add_child(item_node)
				item_node.setup(spawn_list[current_index])
				item_node.position = Vector3(0, 0, 0.1)
				
			add_child(cell)
			
			cell.scale = Vector3(0.001, 0.001, 0.001)
			
			var random_spawn_dist = randf_range(spawn_distance_min, spawn_distance_max)
			var spawn_radius = final_radial_position + random_spawn_dist
			cell.position = Vector3(cos(angle) * spawn_radius, row_y, sin(angle) * spawn_radius)
			cell.rotation = Vector3(0, -angle, 0)
			
			var individual_delay = current_row_delay + (i * delay_between_cells_in_row)
			var t = create_tween().set_parallel(true)
			t.tween_property(cell, "position", target_pos, cell_fly_duration)\
				.set_trans(trans_type).set_ease(ease_type).set_delay(individual_delay)
			t.tween_property(cell, "scale", Vector3(target_scale_x, 1.0, 1.0), cell_fly_duration)\
				.set_trans(trans_type).set_ease(ease_type).set_delay(individual_delay)

	_place_caps_sync(total_assembly_time)

func reveal_next_bonus_cell(callback: Callable):
	if active_red_cells.size() == 0:
		callback.call()
		return
		
	var data = active_red_cells.pop_front()
	var cell = data["cell"]
	var col: int = data["col"]
	
	_stop_snap()
	can_rotate = false
	is_dragging = false
	angular_velocity = 0.0
	
	# Угол камеры относительно центра шкафа в XZ-плоскости.
	var cam = get_viewport().get_camera_3d()
	var cam_angle = PI / 2.0
	if cam:
		var to_cam = cam.global_position - global_position
		to_cam.y = 0.0
		if to_cam.length_squared() > 0.0001:
			cam_angle = atan2(to_cam.z, to_cam.x)
	
	# Ячейка col стоит на цилиндре под локальным углом col * STEP_ANGLE.
	# При rotation.y = R мировой угол ячейки = col_angle - R (из матрицы поворота Godot).
	# Приравниваем к cam_angle: col_angle - R = cam_angle => R = col_angle - cam_angle.
	var target_rot = float(col) * STEP_ANGLE - cam_angle
	var diff = angle_difference(rotation.y, target_rot)
	
	if abs(diff) < deg_to_rad(5.0):
		diff += TAU
	
	var final_angle = rotation.y + diff
	
	var reveal_duration = 1.2 / bonus_reveal_speed_multiplier
	var post_open_delay = 1.3 / (bonus_reveal_speed_multiplier * bonus_post_open_delay_multiplier)
	if bonus_fixed_post_open_delay >= 0.0:
		post_open_delay = bonus_fixed_post_open_delay
	var tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation:y", final_angle, reveal_duration) 
	tw.tween_callback(func():
		if is_instance_valid(cell) and cell.has_method("open_doors"):
			cell.open_doors()
		
		get_tree().create_timer(post_open_delay).timeout.connect(func():
			can_rotate = true
			angular_velocity = 0.0
			callback.call()
		)
	)

func _place_caps_sync(duration: float) -> void:
	if cap_scene == null: return
	var s_xz = BLENDER_RADIUS / CAP_FIT_RADIUS
	var cap_scale = Vector3(s_xz, 1.0, s_xz)
	var t = create_tween().set_parallel(true)

	var bottom = cap_scene.instantiate() as Node3D
	add_child(bottom)
	bottom.scale = Vector3(0.001, 0.001, 0.001)
	bottom.position = Vector3(0.0, CAP_BOTTOM_Y - 15.0, 0.0)
	t.tween_property(bottom, "position", Vector3(0.0, CAP_BOTTOM_Y, 0.0), duration).set_trans(trans_type).set_ease(ease_type)
	t.tween_property(bottom, "scale", cap_scale, duration).set_trans(trans_type).set_ease(ease_type)

	var top = cap_scene.instantiate() as Node3D
	add_child(top)
	top.scale = Vector3(0.001, 0.001, 0.001)
	var top_y = (float(ROWS - 1) * CELL_HEIGHT * VERTICAL_SPACING) + CELL_HEIGHT + CAP_TOP_Y_MARGIN
	top.position = Vector3(0.0, top_y + 15.0, 0.0)
	t.tween_property(top, "position", Vector3(0.0, top_y, 0.0), duration).set_trans(trans_type).set_ease(ease_type)
	t.tween_property(top, "scale", cap_scale, duration).set_trans(trans_type).set_ease(ease_type)