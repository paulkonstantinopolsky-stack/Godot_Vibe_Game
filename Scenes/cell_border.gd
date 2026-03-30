extends Control

# Наши 3 состояния
enum State { DEFAULT, DASHED, FOCUSED }
var current_state: State = State.DEFAULT

# --- ТЕКСТУРЫ ФОНА ---
@export var default_bg_texture: Texture2D
@export var focused_bg_texture: Texture2D

# --- НАСТРОЙКИ ДИЗАЙНА ---
var corner_radius = 12.0
var focused_width = 6.0
var focused_color = Color("#ffffff") 

var dashed_width = 3.0
var dashed_color = Color("#5C3621")
var dash = 18.0
var gap = 18.0
var dash_speed = 20.0 
var dash_offset = 0.0

var focused_style: StyleBoxFlat

@onready var default_png = $DefaultBorderPNG
@onready var focus_triangles_png = $FocusTrianglesPNG
@onready var root_cell = $".."

func _ready():
	focused_style = StyleBoxFlat.new()
	focused_style.bg_color = Color.TRANSPARENT
	focused_style.border_color = focused_color
	focused_style.set_border_width_all(int(focused_width))
	focused_style.set_corner_radius_all(int(corner_radius))
	focused_style.anti_aliasing = true
	
	if default_png: default_png.hide()
	
	if focus_triangles_png:
		focus_triangles_png.hide()
		# Автоматически раздвигаем стрелки наружу на 24px
		focus_triangles_png.set_anchors_preset(Control.PRESET_FULL_RECT)
		var offset_val = 24.0 
		focus_triangles_png.offset_left = -offset_val
		focus_triangles_png.offset_top = -offset_val
		focus_triangles_png.offset_right = offset_val
		focus_triangles_png.offset_bottom = offset_val

func _process(delta):
	if current_state == State.DASHED:
		dash_offset += dash_speed * delta
		queue_redraw() 

func set_state(new_state: int):
	current_state = new_state as State
	
	if root_cell:
		root_cell.clip_contents = false
	
	if current_state == State.DEFAULT:
		if root_cell: root_cell.z_index = 0
		if default_png: default_png.show()
		if focus_triangles_png: focus_triangles_png.hide()
		
	elif current_state == State.DASHED:
		if root_cell: root_cell.z_index = 0
		if default_png: default_png.hide()
		if focus_triangles_png: focus_triangles_png.hide()
		
	elif current_state == State.FOCUSED:
		if root_cell: root_cell.z_index = 1
		if default_png: default_png.hide()
		if focus_triangles_png: focus_triangles_png.show()
		
	queue_redraw()

func _draw():
	var rect = Rect2(Vector2.ZERO, size)
	
	# 1. РИСУЕМ ФОН (Автоматически растягивается на 100% ячейки)
	if current_state == State.DEFAULT or current_state == State.DASHED:
		if default_bg_texture:
			draw_texture_rect(default_bg_texture, rect, false)
	elif current_state == State.FOCUSED:
		if focused_bg_texture:
			draw_texture_rect(focused_bg_texture, rect, false)
	
	# 2. РИСУЕМ РАМКИ ПОВЕРХ ФОНА
	if current_state == State.FOCUSED:
		draw_style_box(focused_style, rect)
	elif current_state == State.DASHED:
		var inset = dashed_width / 2.0
		var path_rect = Rect2(Vector2(inset, inset), size - Vector2(inset * 2, inset * 2))
		var path_radius = corner_radius - inset
		_draw_animated_dashed_rounded_rect(path_rect, path_radius)

# --- ЛОГИКА ОТРИСОВКИ ПУНКТИРА ---
func _draw_animated_dashed_rounded_rect(rect: Rect2, r: float):
	var pts = _get_rounded_rect_points(rect, r, 10)
	var total_length = 0.0
	var lengths = []
	for i in range(pts.size() - 1):
		var d = pts[i].distance_to(pts[i+1])
		lengths.append(d)
		total_length += d

	var cycle = dash + gap
	var offset = fmod(dash_offset, cycle)
	if offset < 0: offset += cycle

	var current_dist = -offset
	while current_dist < total_length:
		var start_d = max(0.0, current_dist)
		var end_d = min(total_length, current_dist + dash)
		if end_d > start_d:
			_draw_polyline_segment(pts, lengths, start_d, end_d)
		current_dist += cycle

func _draw_polyline_segment(pts: PackedVector2Array, lengths: Array, start_d: float, end_d: float):
	var segment_pts = PackedVector2Array()
	var accumulated = 0.0
	for i in range(pts.size() - 1):
		var seg_start = accumulated
		var seg_end = accumulated + lengths[i]
		if end_d <= seg_start: break
		if start_d >= seg_end:
			accumulated = seg_end
			continue
		var t_start = clamp((start_d - seg_start) / lengths[i], 0.0, 1.0)
		var t_end = clamp((end_d - seg_start) / lengths[i], 0.0, 1.0)
		var p1 = pts[i].lerp(pts[i+1], t_start)
		var p2 = pts[i].lerp(pts[i+1], t_end)
		if segment_pts.is_empty(): 
			segment_pts.append(p1)
		elif segment_pts[segment_pts.size() - 1].distance_to(p1) > 0.1: 
			segment_pts.append(p1)
		segment_pts.append(p2)
		accumulated = seg_end
		
	if segment_pts.size() >= 2:
		draw_polyline(segment_pts, dashed_color, dashed_width, true)

func _get_rounded_rect_points(rect: Rect2, r: float, points_per_arc: int) -> PackedVector2Array:
	var pts = PackedVector2Array()
	var w = rect.size.x
	var h = rect.size.y
	for i in range(points_per_arc + 1):
		var angle = -PI/2 + (PI/2) * (float(i) / points_per_arc)
		pts.append(Vector2(w - r, r) + Vector2(cos(angle), sin(angle)) * r + rect.position)
	for i in range(points_per_arc + 1):
		var angle = 0 + (PI/2) * (float(i) / points_per_arc)
		pts.append(Vector2(w - r, h - r) + Vector2(cos(angle), sin(angle)) * r + rect.position)
	for i in range(points_per_arc + 1):
		var angle = PI/2 + (PI/2) * (float(i) / points_per_arc)
		pts.append(Vector2(r, h - r) + Vector2(cos(angle), sin(angle)) * r + rect.position)
	for i in range(points_per_arc + 1):
		var angle = PI + (PI/2) * (float(i) / points_per_arc)
		pts.append(Vector2(r, r) + Vector2(cos(angle), sin(angle)) * r + rect.position)
	pts.append(pts[0])
	return pts
