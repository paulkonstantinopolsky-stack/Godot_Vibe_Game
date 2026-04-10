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

func _is_cabinet_locked() -> bool:
	var node: Node = self
	while node != null:
		if node.has_method("disable_interaction") and node.has_method("enable_interaction"):
			return not bool(node.get("is_interactable"))
		node = node.get_parent()
	return false

func _on_area_3d_input_event(_camera, event, _position, _normal, _shape_idx):
	if _is_cabinet_locked():
		return
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

func fade_out_magic() -> void:
	if has_node("Sprite3D"):
		var sprite = $Sprite3D
		# Прозрачность Sprite3D в Godot 4 — через modulate.a (1 = видим, 0 = невидим)
		var tw = create_tween().bind_node(self).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(sprite, "modulate:a", 0.0, 0.4)