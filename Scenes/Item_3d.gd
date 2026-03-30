extends Node3D

var item_id: int
var texture_path: String

func setup(id: int):
	item_id = id
	var item_data = ItemManager.items_db.get(id)
	if item_data:
		texture_path = item_data["texture"]
		if has_node("Sprite3D"):
			$Sprite3D.texture = load(texture_path)

func _ready():
	if has_node("Area3D"):
		$Area3D.input_event.connect(_on_area_3d_input_event)

func _on_area_3d_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Передаем ссылку на себя (self)
			ItemManager.item_pressed.emit(item_id, texture_path, self)

# --- НОВЫЕ ФУНКЦИИ ДЛЯ ПРЯТАНЬЯ ПРЕДМЕТА ---
func hide_item():
	if has_node("Sprite3D"):
		$Sprite3D.hide()

func show_item():
	if has_node("Sprite3D"):
		$Sprite3D.show()