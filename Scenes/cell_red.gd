extends Node3D

@export var door_left: Node3D
@export var door_right: Node3D

func open_doors():
	if door_left and door_right:
		var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(door_left, "rotation_degrees:y", -100.0, 1.2)
		tw.tween_property(door_right, "rotation_degrees:y", 100.0, 1.2)
		tw.chain().tween_callback(_unlock_coin)

func _unlock_coin():
	for child in get_children():
		if child.has_method("unlock"):
			child.unlock()