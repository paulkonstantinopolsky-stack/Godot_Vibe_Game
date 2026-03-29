extends Node3D

func setup(id: int):
    var item_data = ItemManager.items_db.get(id)
    if item_data and has_node("Sprite3D"):
        $Sprite3D.texture = load(item_data["texture"])