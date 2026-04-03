extends Control

const GamePaletteResource = preload("res://game_palette.gd")

# Наши 3 состояния
enum State { DEFAULT, DASHED, FOCUSED }
var current_state: State = State.DEFAULT

var palette: GamePaletteResource

# --- НАСТРОЙКИ ДИЗАЙНА ---
var corner_radius = 12.0
var focused_width = 6.0

var dashed_width = 3.0
var dash = 18.0
var gap = 18.0
var dash_speed = 20.0
var dash_offset = 0.0

@onready var root_cell = $".."

# --- ПЕРЕМЕННЫЕ ДЛЯ ПЛАВНЫХ АНИМАЦИЙ ---
var alpha_default: float = 1.0
var alpha_dashed: float = 0.0
var alpha_focused: float = 0.0
var fade_tween: Tween

func _ready():
	if ResourceLoader.exists("res://game_palette.tres"):
		palette = load("res://game_palette.tres")
	else:
		palette = GamePaletteResource.new()

	var default_png = get_node_or_null("DefaultBorderPNG")
	if default_png:
		default_png.hide()

func _process(delta):
	var needs_redraw = false

	if alpha_dashed > 0.0:
		dash_offset += dash_speed * delta
		needs_redraw = true

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

	if fade_tween and fade_tween.is_running():
		fade_tween.kill()

	fade_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var target_def = 1.0 if current_state == State.DEFAULT else 0.0
	var target_dash = 1.0 if current_state == State.DASHED else 0.0
	var target_foc = 1.0 if current_state == State.FOCUSED else 0.0

	fade_tween.tween_property(self, "alpha_default", target_def, 0.2)
	fade_tween.tween_property(self, "alpha_dashed", target_dash, 0.2)
	fade_tween.tween_property(self, "alpha_focused", target_foc, 0.2)

func _draw():
	var rect = Rect2(Vector2.ZERO, size)

	var draw_bg = func(bg_color: Color, border_color: Color, alpha: float):
		if alpha <= 0.0:
			return
		var style = StyleBoxFlat.new()
		var c_bg = bg_color
		c_bg.a *= alpha
		var c_border = border_color
		c_border.a *= alpha
		style.bg_color = c_bg
		style.border_color = c_border
		if border_color == Color.TRANSPARENT:
			style.set_border_width_all(0)
		else:
			style.set_border_width_all(int(focused_width))
		style.set_corner_radius_all(int(corner_radius))
		style.anti_aliasing = true
		draw_style_box(style, rect)

	if alpha_default > 0.0:
		draw_bg.call(palette.cell_default_bg, palette.cell_default_border, alpha_default)

	if alpha_dashed > 0.0:
		draw_bg.call(palette.cell_dashed_bg, Color.TRANSPARENT, alpha_dashed)

	if alpha_focused > 0.0:
		draw_bg.call(palette.cell_focused_bg, palette.cell_focused_border, alpha_focused)

	if alpha_dashed > 0.0:
		var current_dash_color = palette.cell_dashed_border
		current_dash_color.a *= alpha_dashed
		var inset = dashed_width / 2.0
		var path_rect = Rect2(Vector2(inset, inset), size - Vector2(inset * 2, inset * 2))
		var path_radius = corner_radius - inset
		_draw_animated_dashed_rounded_rect(path_rect, path_radius, current_dash_color)

func _draw_animated_dashed_rounded_rect(rect: Rect2, r: float, color: Color):
	var pts = _get_rounded_rect_points(rect, r, 10)
	var total_length = 0.0
	var lengths = []
	for i in range(pts.size() - 1):
		var d = pts[i].distance_to(pts[i + 1])
		lengths.append(d)
		total_length += d

	var cycle = dash + gap
	var offset = fmod(dash_offset, cycle)
	if offset < 0:
		offset += cycle

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
		if end_d <= seg_start:
			break
		if start_d >= seg_end:
			accumulated = seg_end
			continue
		var t_start = clampf((start_d - seg_start) / lengths[i], 0.0, 1.0)
		var t_end = clampf((end_d - seg_start) / lengths[i], 0.0, 1.0)
		var p1 = pts[i].lerp(pts[i + 1], t_start)
		var p2 = pts[i].lerp(pts[i + 1], t_end)
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
		var angle = -PI / 2 + (PI / 2) * (float(i) / points_per_arc)
		pts.append(Vector2(w - r, r) + Vector2(cos(angle), sin(angle)) * r + rect.position)
	for i in range(points_per_arc + 1):
		var angle = 0 + (PI / 2) * (float(i) / points_per_arc)
		pts.append(Vector2(w - r, h - r) + Vector2(cos(angle), sin(angle)) * r + rect.position)
	for i in range(points_per_arc + 1):
		var angle = PI / 2 + (PI / 2) * (float(i) / points_per_arc)
		pts.append(Vector2(r, h - r) + Vector2(cos(angle), sin(angle)) * r + rect.position)
	for i in range(points_per_arc + 1):
		var angle = PI + (PI / 2) * (float(i) / points_per_arc)
		pts.append(Vector2(r, r) + Vector2(cos(angle), sin(angle)) * r + rect.position)
	pts.append(pts[0])
	return pts
