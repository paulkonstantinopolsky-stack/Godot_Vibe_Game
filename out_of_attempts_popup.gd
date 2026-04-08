extends Control

signal popup_closed(action: String)

@onready var overlay = get_node_or_null("Overlay")
@onready var content_box = get_node_or_null("ContentBox")
@onready var btn_close = get_node_or_null("ContentBox/BtnClose")
@onready var btn_autofill = get_node_or_null("ContentBox/BtnAutofill")

var _attempts_widget_ref: Control = null
var _original_attempts_z_index: int = 0

func _ready() -> void:
	hide()
	
	if overlay: overlay.color.a = 0.0
	if content_box: content_box.scale = Vector2(0.5, 0.0) 
	if btn_close: btn_close.modulate.a = 0.0
	if btn_autofill: btn_autofill.modulate.a = 0.0
	
	if btn_close: btn_close.pressed.connect(_on_close_pressed)
	if btn_autofill: btn_autofill.pressed.connect(_on_autofill_pressed)

func open_popup(attempts_widget: Control = null) -> void:
	show()
	z_index = 300
	if attempts_widget and is_instance_valid(attempts_widget):
		_attempts_widget_ref = attempts_widget
		_original_attempts_z_index = attempts_widget.z_index
		attempts_widget.z_index = 301 
	
	var tw = create_tween().bind_node(self)
	if overlay:
		tw.parallel().tween_property(overlay, "color:a", 0.85, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if content_box:
		tw.parallel().tween_property(content_box, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	if btn_close:
		tw.chain().tween_property(btn_close, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	if btn_autofill:
		tw.parallel().tween_property(btn_autofill, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)

func _close_popup(action: String) -> void:
	if btn_close: btn_close.disabled = true
	if btn_autofill: btn_autofill.disabled = true
	
	var tw = create_tween().bind_node(self)
	
	if btn_close:
		tw.parallel().tween_property(btn_close, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if btn_autofill:
		tw.parallel().tween_property(btn_autofill, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	if content_box:
		tw.chain().tween_property(content_box, "scale", Vector2(0.5, 0.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if overlay:
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
