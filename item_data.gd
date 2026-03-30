extends Resource
class_name ItemData

# Выпадающий список с готовыми и протестированными формами
enum ShapeType {
	SINGLE,      # 1 клетка
	DOUBLE_V,    # 2 клетки (вертикально)
	CORNER_L,    # 3 клетки (уголок)
	SQUARE,      # 4 клетки (квадрат)
	ZIGZAG       # 4 клетки (зигзаг)
}

@export var id: int = 0
@export var texture: Texture2D
@export var shape_type: ShapeType = ShapeType.SINGLE

# Эта функция генерирует 100% правильные координаты без диагоналей
func get_shape() -> Array:
	match shape_type:
		ShapeType.SINGLE:
			return [Vector2(0, 0)]
		ShapeType.DOUBLE_V:
			return [Vector2(0, 0), Vector2(0, 1)]
		ShapeType.CORNER_L:
			return [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]
		ShapeType.SQUARE:
			return [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
		ShapeType.ZIGZAG:
			return [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(2, 1)]
	return [Vector2(0, 0)]