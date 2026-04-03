extends Resource
class_name GamePalette

@export_group("Puzzle Colors")
@export var puz_normal_bg: Color = Color("#401E0D")
@export var puz_normal_border: Color = Color("#5C3621")

@export var puz_edit_unfocused_bg: Color = Color("#401E0D")
@export var puz_edit_unfocused_border: Color = Color("#FFAE3C")

@export var puz_edit_focused_bg: Color = Color("#5C3621")
@export var puz_edit_focused_border: Color = Color("#ffffff")

@export var puz_drag_valid_bg: Color = Color("#401E0D")
@export var puz_drag_valid_border: Color = Color("#ffffff")

@export_group("Cell Colors")
@export var cell_default_bg: Color = Color(0, 0, 0, 0.2)
@export var cell_default_border: Color = Color(0, 0, 0, 0)

@export var cell_dashed_bg: Color = Color(0, 0, 0, 0.3)
@export var cell_dashed_border: Color = Color("#5C3621")

@export var cell_focused_bg: Color = Color(1, 1, 1, 0.2)
@export var cell_focused_border: Color = Color("#ffffff")
