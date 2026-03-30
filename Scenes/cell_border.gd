extends Control

# Наши 3 состояния
enum State { DEFAULT, DASHED, FOCUSED }
var current_state: State = State.DEFAULT

# --- ТЕКСТУРЫ ФОНА ---
@export var default_bg_texture: Texture2D
@export var focused_bg_texture: Texture2D

# --- НАСТРОЙКИ ДИЗАЙНА (ТВОИ) ---
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
# Безопасный вызов, так как узла больше нет в сцене
@onready var focus_triangles_png = get_node_or_null("FocusTrianglesPNG")
@onready var root_cell = $".."

# --- ПЕРЕМЕННЫЕ ДЛЯ ПЛАВНЫХ АНИМАЦИЙ ---
var alpha_default: float = 1.0
var alpha_dashed: float = 0.0
var alpha_focused: float = 0.0
var fade_tween: Tween

func _ready():
	focused_style = StyleBoxFlat.new()
	focused_style.bg_color = Color.TRANSPARENT
	focused_style.border_color = focused_color
	focused_style.set_border_width_all(int(focused_width))
	focused_style.set_corner_radius_all(int(corner_radius))
	focused_style.anti_aliasing = true
	
	if default_png: 
		default_png.hide()
		default_png.modulate.a = 1.0

func _process(delta):
	var needs_redraw = false
	
	# Двигаем пунктир, только если он хоть немного виден
	if alpha_dashed > 0.0:
		dash_offset += dash_speed * delta
		needs_redraw = true
		
	# Заставляем перерисовываться кадры во время анимации смешивания цветов
	if fade_tween and fade_tween.is_running():
		needs_redraw = true
		
	if needs_redraw:
		queue_redraw()

func set_state(new_state: int):
	current_state = new_state as State
	
	if root_cell:
		root_cell.clip_contents = false
		if current_state == State.FOCUSED:
			root_cell.z_index = 1
		else:
			root_cell.z_index = 0
			
	# Убиваем старую анимацию, если она не закончилась
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()
		
	# Запускаем новую плавную анимацию прозрачности (0.2 сек)
	fade_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	var target_def = 1.0 if current_state == State.DEFAULT else 0.0
	var target_dash = 1.0 if current_state == State.DASHED else 0.0
	var target_foc = 1.0 if current_state == State.FOCUSED else 0.0
	
	fade_tween.tween_property(self, "alpha_default", target_def, 0.2)
	fade_tween.tween_property(self, "alpha_dashed", target_dash, 0.2)
	fade_tween.tween_property(self, "alpha_focused", target_foc, 0.2)
	
	# Плавно скрываем/показываем статичные PNG картинки
	if default_png:
		default_png.show()
		fade_tween.tween_property(default_png, "modulate:a", target_def, 0.2)
	
	# В конце анимации выключаем видимость полностью прозрачных PNG, чтобы экономить ресурсы
	fade_tween.chain().tween_callback(func():
		if current_state != State.DEFAULT and default_png: default_png.hide()
	)

func _draw():
	var rect = Rect2(Vector2.ZERO, size)
	
	# 1. ПЛАВНЫЕ ФОНЫ (смешивание цветов)
	var def_bg_alpha = max(alpha_default, alpha_dashed)
	if def_bg_alpha > 0.0 and default_bg_texture:
		draw_texture_rect(default_bg_texture, rect, false, Color(1, 1, 1, def_bg_alpha))
		
	if alpha_focused > 0.0 and focused_bg_texture:
		draw_texture_rect(focused_bg_texture, rect, false, Color(1, 1, 1, alpha_focused))
	
	# 2. ПЛАВНАЯ ФОКУСНАЯ РАМКА
	if alpha_focused > 0.0:
		var mod_style = focused_style.duplicate()
		mod_style.border_color.a = alpha_focused
		draw_style_box(mod_style, rect)
		
	# 3. ПЛАВНЫЙ АНИМИРОВАННЫЙ ПУНКТИР
	if alpha_dashed > 0.0:
		var current_dash_color = dashed_color
		current_dash_color.a = alpha_dashed
		var inset = dashed_width / 2.0
		var path_rect = Rect2(Vector2(inset, inset), size - Vector2(inset * 2, inset * 2))
		var path_radius = corner_radius - inset
		_draw_animated_dashed_rounded_rect(path_rect, path_radius, current_dash_color)

# --- ЛОГИКА ОТРИСОВКИ ПУНКТИРА ---
func _draw_animated_dashed_rounded_rect(rect: Rect2, r: float, color: Color):
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
			_draw_polyline_segment(pts, lengths, start_d, end_d, color)
		current_dist += cycle

func _draw_polyline_segment(pts: PackedVector2Array, lengths: Array, start_d: float, end_d: float, color: Color):
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
		draw_polyline(segment_pts, color, dashed_width, true)

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