extends Control

func set_item(tex_path: String):
	if has_node("Icon"):
		$Icon.texture = load(tex_path)
