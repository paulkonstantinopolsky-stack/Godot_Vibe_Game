extends Resource
class_name ItemData

enum ShapeType {
	SINGLE,    # 1 клетка
	DOUBLE_V,  # 2 клетки вертикально
	TRIPLE_V,  # 3 клетки вертикально (линия)
	SQUARE,    # 2×2
}

@export var id: int = 0
@export var texture: Texture2D
@export var shape_type: ShapeType = ShapeType.SINGLE

# Скрываем старый массив, чтобы не сломать кэш Godot, но убираем его с глаз долой
var shape: Array[Vector2] = []

func get_shape() -> Array:
	match shape_type:
		ShapeType.SINGLE:
			return [Vector2(0, 0)]
		ShapeType.DOUBLE_V:
			return [Vector2(0, 0), Vector2(0, 1)]
		ShapeType.TRIPLE_V:
			return [Vector2(0, 0), Vector2(0, 1), Vector2(0, 2)]
		ShapeType.SQUARE:
			return [
				Vector2(0, 0),
				Vector2(1, 0),
				Vector2(0, 1),
				Vector2(1, 1),
			]
	return [Vector2(0, 0)]
