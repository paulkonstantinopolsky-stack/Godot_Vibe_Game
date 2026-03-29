extends Node3D

var item_id: int

func setup(id: int):
    item_id = id
    if !has_node("/root/ItemManager"): return
    
    var item_data = ItemManager.items_db.get(id)
    if !item_data: return
    
    var sprite = $Sprite3D
    if sprite:
        sprite.texture = load(item_data["texture"])
        
    rotation_degrees = Vector3.ZERO