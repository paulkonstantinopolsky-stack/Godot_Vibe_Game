extends Control

@export var entry_scene: PackedScene = preload("res://Scenes/SideWidgetEntry.tscn")

@onready var items_container = $ItemsContainer
@onready var small_envelope = $SmallEnvelope

const ITEM_SIZE = 120.0
const SPACING = 30.0

func _ready():
	hide()
	if !ItemManager.item_found.is_connected(_on_item_found):
		ItemManager.item_found.connect(_on_item_found)

func start_appear_animation():
	# ПРАВИЛЬНАЯ ОЧИСТКА: отрываем от интерфейса перед удалением
	for c in items_container.get_children():
		items_container.remove_child(c)
		c.queue_free()
	
	show()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	
	for i in range(ItemManager.current_order.size()):
		var item_data = ItemManager.current_order[i]
		var entry = entry_scene.instantiate()
		items_container.add_child(entry)
		
		entry.setup(item_data["id"], ItemManager.items_db[item_data["id"]]["texture"])
		
		var is_already_found = item_data["found"]
		entry.set_meta("is_flipped", is_already_found)
		if is_already_found and entry.has_method("flip_to_front"):
			entry.flip_to_front()
		
		var target_pos = Vector2(0, i * (ITEM_SIZE + SPACING))
		var diff = small_envelope.position - items_container.position
		var start_pos = diff + Vector2((small_envelope.size.x - ITEM_SIZE)/2, (small_envelope.size.y - ITEM_SIZE)/2)
		
		entry.position = start_pos
		entry.scale = Vector2(0.1, 0.1)
		
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(entry, "position", target_pos, 0.6).set_delay(i * 0.1)
		tw.tween_property(entry, "scale", Vector2.ONE, 0.6).set_delay(i * 0.1)

func _on_item_found(id: int):
	for entry in items_container.get_children():
		if int(entry.item_id) == int(id) and not entry.get_meta("is_flipped", false):
			entry.flip_to_front()
			entry.set_meta("is_flipped", true)
			break