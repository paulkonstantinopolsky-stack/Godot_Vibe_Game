extends Control

signal popup_closed(action: String)

@onready var overlay = $Overlay
@onready var content_box = $ContentBox
@onready var btn_close = $ContentBox/BtnClose
@onready var btn_autofill = $ContentBox/BtnAutofill

# Ссылки на визуальные элементы для авто-загрузки
@onready var paper_bg = $ContentBox/PaperBackground
@onready var illustration = $ContentBox/Illustration
@onready var title_label = $ContentBox/TitleLabel
@onready var paragraph_label = $ContentBox/ParagraphLabel
@onready var left_deco = $ContentBox/LeftDeco
@onready var right_deco = $ContentBox/RightDeco
@onready var icon_video = get_node_or_null("ContentBox/BtnAutofill/HBoxContainer/Icon")

var _attempts_widget_ref: Control = null
var _original_attempts_z_index: int = 0

func _ready() -> void:
	hide()
	_setup_visuals()

	overlay.color.a = 0.0
	content_box.scale = Vector2(0.5, 0.0)
	btn_close.modulate.a = 0.0
	btn_autofill.modulate.a = 0.0

	if btn_close: btn_close.pressed.connect(_on_close_pressed)
	if btn_autofill: btn_autofill.pressed.connect(_on_autofill_pressed)

func _setup_visuals() -> void:
	# === НАСТРОЙКА ТЕКСТОВ ===
	if title_label:
		title_label.text = "Out of attempts"
	if paragraph_label:
		paragraph_label.text = "Watch an AD and we'll place\nall the right items. Your cats\nwill be happy!"

	# === ЗАГРУЗКА КАРТИНОК ===
	# ВНИМАНИЕ: Замени названия файлов (paper.png и т.д.) на реальные имена из твоей папки!
	var load_tex = func(node: TextureRect, file_name: String):
		if node and ResourceLoader.exists("res://Assets/2D/" + file_name):
			node.texture = load("res://Assets/2D/" + file_name)

	var load_btn = func(btn: TextureButton, file_name: String):
		if btn and ResourceLoader.exists("res://Assets/2D/" + file_name):
			btn.texture_normal = load("res://Assets/2D/" + file_name)

	load_tex.call(paper_bg, "paper_bg.png") # Фон письма
	load_tex.call(illustration, "cats_art.png") # Картинка с котами
	load_tex.call(left_deco, "deco_left.png") # Узор слева
	load_tex.call(right_deco, "deco_right.png") # Узор справа
	load_tex.call(icon_video, "icon_video.png") # Иконка видео на кнопке

	load_btn.call(btn_close, "btn_close.png") # Крестик
	load_btn.call(btn_autofill, "btn_autofill.png") # Оранжевая кнопка

func open_popup(attempts_widget: Control = null) -> void:
	show()
	z_index = 300
	if attempts_widget and is_instance_valid(attempts_widget):
		_attempts_widget_ref = attempts_widget
		_original_attempts_z_index = attempts_widget.z_index
		attempts_widget.z_index = 301

	var tw = create_tween().bind_node(self)
	tw.parallel().tween_property(overlay, "color:a", 0.85, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(content_box, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tw.chain().tween_property(btn_close, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(btn_autofill, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)

func _close_popup(action: String) -> void:
	btn_close.disabled = true
	btn_autofill.disabled = true

	var tw = create_tween().bind_node(self)
	tw.parallel().tween_property(btn_close, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(btn_autofill, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tw.chain().tween_property(content_box, "scale", Vector2(0.5, 0.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(overlay, "color:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tw.chain().tween_callback(func():
		if _attempts_widget_ref and is_instance_valid(_attempts_widget_ref):
			_attempts_widget_ref.z_index = _original_attempts_z_index

		hide()
		popup_closed.emit(action)
		queue_free()
	)

func _on_close_pressed() -> void:
	_close_popup("continue")

func _on_autofill_pressed() -> void:
	_close_popup("autofill")
