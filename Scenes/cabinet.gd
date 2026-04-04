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

@export_group("Inertia Physics")
@export var swipe_sensitivity: float = 0.5
@export var max_angular_velocity: float = 25.0
@export var friction: float = 3.0
@export var snap_threshold: float = 2.0
@export var snap_duration: float = 0.25
@export var face_angle_step: float = 45.0

@export_group("Хаптик (Сейф)")
@export var haptics_enabled: bool = true
@export var haptic_click_ms: int = 10

const SNAP_ANGLE_EPS: float = 0.01

var can_rotate: bool = false
var is_dragging: bool = false
## Скорость в градусах за кадр (_physics-like для инерции)
var angular_velocity: float = 0.0
## Текущий yaw в градусах (синхрон с rotation_degrees.y)
var current_rotation_y: float = 0.0
var snap_tween: Tween
var last_haptic_index: int = 0

var red_cell_scene = preload("res://Scenes/Cell_Red.tscn")
var green_cell_scene = preload("res://Scenes/Cell_Green.tscn")
var cap_scene = preload("res://Scenes/Top_Down.tscn")
var item_3d_scene = preload("res://Scenes/Item_3d.tscn")

var active_red_cells = []
var focus_tween: Tween
var bonus_reveal_speed_multiplier: float = 1.0

# --- Последовательность сбора монет ---
var unlocked_coin_cols: Array = []  # Отсортированный список колонок с открытыми монетами
var coin_seq_tween: Tween
var bonus_post_open_delay_multiplier: float = 1.0
var bonus_fixed_post_open_delay: float = -1.0

var _is_first_bonus_reveal: bool = true

func set_bonus_reveal_speed_multiplier(mult: float) -> void:
	bonus_reveal_speed_multiplier = max(mult, 0.01)

func set_bonus_post_open_delay_multiplier(mult: float) -> void:
	bonus_post_open_delay_multiplier = max(mult, 0.01)

func set_bonus_fixed_post_open_delay(seconds: float) -> void:
	bonus_fixed_post_open_delay = seconds

func _ready() -> void:
	hide()

func _process(delta: float) -> void:
	if not can_rotate:
		return

	if snap_tween and snap_tween.is_running():
		current_rotation_y = rotation_degrees.y
		_check_haptic_click()
		return

	if is_dragging:
		return

	if abs(angular_velocity) > snap_threshold:
		current_rotation_y += angular_velocity * (delta * 60.0) # Компенсация под 60 FPS
		rotation_degrees.y = current_rotation_y
		angular_velocity = lerpf(angular_velocity, 0.0, friction * delta)
		_check_haptic_click()
	else:
		angular_velocity = 0.0
		var target_y: float = round(current_rotation_y / face_angle_step) * face_angle_step
		if abs(target_y - current_rotation_y) > SNAP_ANGLE_EPS:
			_begin_snap_to_face(target_y)

func _input(event: InputEvent) -> void:
	if not can_rotate:
		return

	if ItemManager.is_dragging_item:
		if event is InputEventMouseButton or event is InputEventScreenTouch:
			if not event.pressed:
				is_dragging = false
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_rotate_grab()
		else:
			is_dragging = false
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_on_rotate_grab()
		else:
			is_dragging = false
		return

	if not is_dragging:
		return

	if event is InputEventMouseMotion:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return
		_apply_direct_rotation(event.relative.x)
	elif event is InputEventScreenDrag:
		_apply_direct_rotation(event.relative.x)

func _on_rotate_grab() -> void:
	is_dragging = true
	angular_velocity = 0.0
	_stop_snap()
	current_rotation_y = rotation_degrees.y

func _apply_direct_rotation(rel_x: float) -> void:
	var delta_rot: float = rel_x * swipe_sensitivity
	current_rotation_y += delta_rot
	rotation_degrees.y = current_rotation_y
	angular_velocity = rel_x * swipe_sensitivity
	angular_velocity = clampf(angular_velocity, -max_angular_velocity, max_angular_velocity)
	# Щелчки только через хаптики, без визуального притяжения к грани во время драга
	_check_haptic_click()

func _begin_snap_to_face(target_y: float) -> void:
	_stop_snap()
	snap_tween = create_tween()
	snap_tween.set_parallel(true)
	snap_tween.tween_property(self, "current_rotation_y", target_y, snap_duration)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	snap_tween.tween_property(self, "rotation_degrees:y", target_y, snap_duration)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	snap_tween.finished.connect(func():
		current_rotation_y = rotation_degrees.y
		_check_haptic_click()
	)

func _check_haptic_click() -> void:
	if not haptics_enabled:
		return
	var step: float = maxf(face_angle_step, 0.001)
	var current_index: int = int(round(rotation_degrees.y / step))
	if current_index != last_haptic_index:
		Input.vibrate_handheld(haptic_click_ms)
		last_haptic_index = current_index

func _stop_snap() -> void:
	if snap_tween != null:
		snap_tween.kill()
	snap_tween = null

func _get_camera_angle_xz(default_angle: float = PI / 2.0) -> float:
	var cam = get_viewport().get_camera_3d()
	var cam_angle = default_angle
	if cam:
		var to_cam = cam.global_position - global_position
		to_cam.y = 0.0
		if to_cam.length_squared() > 0.0001:
			cam_angle = atan2(to_cam.z, to_cam.x)
	return cam_angle

func focus_item_face_to_camera(item_node: Node3D, duration: float = 0.35, force: bool = false) -> void:
	if item_node == null or not is_instance_valid(item_node):
		return
	var cell = item_node.get_parent()
	if cell == null or not is_instance_valid(cell):
		return
	
	var cell_pos = cell.global_position - global_position
	cell_pos.y = 0.0
	if cell_pos.length_squared() <= 0.0001:
		return
	
	var col_world_angle = atan2(cell_pos.z, cell_pos.x)
	var cam_angle = _get_camera_angle_xz()
	var diff = wrapf(col_world_angle - cam_angle, -PI, PI)
	
	if not force and abs(diff) < deg_to_rad(8.0):
		return
	# При force=true всё равно не трогаем шкаф если он уже точно смотрит в камеру
	if abs(diff) < deg_to_rad(0.5):
		return

	_stop_snap()
	if focus_tween and focus_tween.is_running():
		focus_tween.kill()
	angular_velocity = 0.0
	var target_deg: float = rad_to_deg(rotation.y + diff)
	focus_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	focus_tween.tween_property(self, "rotation_degrees:y", target_deg, duration)
	focus_tween.finished.connect(func(): current_rotation_y = rotation_degrees.y)

func build_cabinet_tornado() -> void:
	for child in get_children():
		child.hide() # Спрятать перед удалением
		child.queue_free()
		
	show()
	can_rotate = false
	active_red_cells.clear()
	unlocked_coin_cols.clear()
	_is_first_bonus_reveal = true

	var spawn_list = []
	for order_item in ItemManager.current_order:
		spawn_list.append(order_item["id"])
	if spawn_list == null or spawn_list.is_empty():
		printerr("build_cabinet_tornado: spawn_list пуст. Проверь генерацию заказа и загрузку items_db.")
		return

	var all_ids = ItemManager.items_db.keys()
	if all_ids == null or all_ids.is_empty():
		printerr("build_cabinet_tornado: items_db пуст (all_ids пуст). Проверь пути/регистр в Items/Data и ресурсы .tres.")
		return
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
	
	current_rotation_y = 0.0
	rotation_degrees.y = 0.0
	last_haptic_index = 0

	var cabinet_tween = create_tween()
	cabinet_tween.tween_property(self, "rotation_degrees:y", total_rotation_degrees, total_assembly_time)\
		.set_trans(trans_type).set_ease(ease_type)
	cabinet_tween.finished.connect(func():
		can_rotate = true
		current_rotation_y = rotation_degrees.y
	)
	
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
				var sid: int = spawn_list[current_index]
				item_node.setup(sid)
				item_node.set_meta("puzzle_shape", ItemManager.get_shape_for_instance(sid))
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
	# Убиваем focus tween — иначе он будет конфликтовать с поворотом кинематики
	if focus_tween and focus_tween.is_running():
		focus_tween.kill()
	can_rotate = false
	is_dragging = false
	angular_velocity = 0.0
	
	# Угол камеры относительно центра шкафа в XZ-плоскости.
	var cam_angle = _get_camera_angle_xz()
	
	# Ячейка col стоит на цилиндре под локальным углом col * STEP_ANGLE.
	# При rotation.y = R мировой угол ячейки = col_angle - R (из матрицы поворота Godot).
	# Приравниваем к cam_angle: col_angle - R = cam_angle => R = col_angle - cam_angle.
	var target_rot = float(col) * STEP_ANGLE - cam_angle
	var diff = angle_difference(rotation.y, target_rot)
	
	if abs(diff) < deg_to_rad(5.0):
		diff += TAU
	
	var final_angle_rad: float = rotation.y + diff
	var final_deg: float = rad_to_deg(final_angle_rad)

	var extra_spin: float = 0.0
	if _is_first_bonus_reveal:
		extra_spin = 360.0 if diff >= 0 else -360.0
		_is_first_bonus_reveal = false

	var juicy_final_deg: float = final_deg + extra_spin

	var reveal_duration: float = 1.0 / bonus_reveal_speed_multiplier
	var post_open_delay: float = 0.6 / (bonus_reveal_speed_multiplier * bonus_post_open_delay_multiplier)
	if bonus_fixed_post_open_delay >= 0.0:
		post_open_delay = bonus_fixed_post_open_delay

	var tw := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation_degrees:y", juicy_final_deg, reveal_duration)
	tw.tween_callback(func():
		current_rotation_y = rotation_degrees.y
		rotation_degrees.y = fmod(rotation_degrees.y, 360.0)
		current_rotation_y = rotation_degrees.y

		if is_instance_valid(cell):
			cell.set_meta("cabinet_col", col)
			_register_coin_col(col)
			if cell.has_method("open_doors"):
				cell.open_doors()

		get_tree().create_timer(post_open_delay).timeout.connect(func():
			can_rotate = true
			angular_velocity = 0.0
			current_rotation_y = rotation_degrees.y
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

# =============================================================
# ПОСЛЕДОВАТЕЛЬНОСТЬ СБОРА МОНЕТ (всегда слева направо)
# =============================================================

# Регистрируем открытую ячейку с монетой в порядке колонок
func _register_coin_col(col: int) -> void:
	if not col in unlocked_coin_cols:
		unlocked_coin_cols.append(col)
		unlocked_coin_cols.sort()  # Сортируем по возрастанию → слева направо

# Вызывается из coin_3d.gd после завершения анимации сбора монеты.
# Следующей всегда становится ячейка ПРАВЕЕ собранной (по возрастанию колонки),
# а если правее ничего нет — переходим к крайней левой из оставшихся.
func on_coin_collected(col: int) -> void:
	var idx := unlocked_coin_cols.find(col)
	if idx < 0:
		return  # Монетка уже не в списке — ничего не делаем
	unlocked_coin_cols.remove_at(idx)

	if unlocked_coin_cols.is_empty():
		# Все монеты собраны — отпускаем управление шкафом
		can_rotate = true
		angular_velocity = 0.0
		return

	# После удаления idx указывает ровно на следующую правую ячейку.
	# Если были в конце списка — % оборачивает к крайней левой.
	var next_col: int = unlocked_coin_cols[idx % unlocked_coin_cols.size()]
	_rotate_to_coin_col(next_col)

# Поворот к грани с монетой — всегда в положительном направлении (слева направо)
func _rotate_to_coin_col(next_col: int) -> void:
	can_rotate = false
	_stop_snap()
	if focus_tween and focus_tween.is_running(): focus_tween.kill()
	if coin_seq_tween and coin_seq_tween.is_running(): coin_seq_tween.kill()
	angular_velocity = 0.0

	var cam_angle := _get_camera_angle_xz()
	var target_rot := float(next_col) * STEP_ANGLE - cam_angle

	# Положительный поворот (слева направо): используем wrapf в [0, TAU).
	var diff := wrapf(target_rot - rotation.y, 0.0, TAU)
	# Если уже смотрим на эту монетку — не крутим, игрок сразу видит её.
	if diff < deg_to_rad(3.0):
		return

	var target_coin_deg: float = rad_to_deg(rotation.y + diff)
	coin_seq_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	coin_seq_tween.tween_property(self, "rotation_degrees:y", target_coin_deg, 0.7)
	coin_seq_tween.finished.connect(func(): current_rotation_y = rotation_degrees.y)
