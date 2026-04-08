extends Control

@onready var heart_icon = $HeartIcon
@onready var count_label = $HeartIcon/CountLabel

var pulse_tween: Tween
var _shader_mat: ShaderMaterial

func _ready() -> void:
	hide()

	if not ItemManager.attempts_updated.is_connected(_on_attempts_updated):
		ItemManager.attempts_updated.connect(_on_attempts_updated)

	count_label.text = str(ItemManager.current_attempts)

	# Создаем уникальный материал с шейдером блика
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = load("res://Shaders/glint.gdshader")
	_shader_mat.set_shader_parameter("progress", -0.1) # Прячем блик за пределы
	heart_icon.material = _shader_mat

func start_appear_animation() -> void:
	show()
	modulate.a = 0.0
	var tw = create_tween().bind_node(self).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.4)

func _on_attempts_updated(new_val: int, is_correct: bool) -> void:
	# Защита от анимации при рестарте уровня
	if new_val == ItemManager.max_attempts:
		count_label.text = str(new_val)
		return

	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()

	pulse_tween = create_tween().bind_node(self)

	# Если предмет верный - ждем 0.35с, пока перевернется карточка в SideWidget
	if is_correct:
		pulse_tween.tween_interval(0.35)

	# Подготовка перед пульсом
	pulse_tween.tween_callback(func():
		_shader_mat.set_shader_parameter("progress", 0.0)
	)

	# ФАЗА 1: "Вздох" (наполнение сердца) + Проход блика
	var phase1 = pulse_tween.parallel()
	phase1.tween_property(heart_icon, "scale", Vector2(1.35, 1.35), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	phase1.tween_method(
		func(v: float): _shader_mat.set_shader_parameter("progress", v),
		0.0, 1.0, 0.25
	).set_trans(Tween.TRANS_LINEAR)

	# ФАЗА 2: Пик пульса (микро-зависание и изменение цифры)
	pulse_tween.chain().tween_callback(func():
		count_label.text = str(new_val)
	)
	pulse_tween.tween_property(heart_icon, "scale", Vector2(1.45, 1.45), 0.05).set_trans(Tween.TRANS_LINEAR)

	# ФАЗА 3: Упругий возврат (Elastic snap)
	pulse_tween.chain().tween_property(heart_icon, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# Прячем блик в конце, чтобы не оставлять артефактов
	pulse_tween.parallel().tween_callback(func():
		_shader_mat.set_shader_parameter("progress", -0.1)
	).set_delay(0.1)
