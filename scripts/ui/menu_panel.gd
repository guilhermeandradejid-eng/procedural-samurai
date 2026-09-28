class_name MenuPanel
extends Control
## Base for full-screen menus: dim backdrop, a column of ink buttons on the
## left, fade in/out, keyboard/gamepad focus and "back" handling.

signal closed

var backdrop: ColorRect
var column: VBoxContainer
var title_label: Label
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	backdrop = UIKit.backdrop(0.6)
	add_child(backdrop)
	var brush := UIKit.brush(900, 1400, Color(0, 0, 0, 0.55))
	brush.rotation = PI * 0.5
	brush.position = Vector2(660, -250)
	add_child(brush)
	column = VBoxContainer.new()
	column.position = Vector2(110, 180)
	column.size = Vector2(560, 700)
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	title_label = UIKit.label("", 56, "title", UIKit.BONE, 8)
	column.add_child(title_label)
	var sep := UIKit.brush(300, 18, UIKit.RED)
	column.add_child(sep)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	column.add_child(spacer)


func add_button(text: String, cb: Callable) -> Button:
	var b := UIKit.button(text)
	b.pressed.connect(cb)
	column.add_child(b)
	return b


func open() -> void:
	visible = true
	modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	_focus_first()


func close() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_tween.tween_callback(func() -> void:
		visible = false
		closed.emit())


func _focus_first() -> void:
	for c in column.get_children():
		if c is Button and (c as Button).visible and not (c as Button).disabled:
			(c as Button).grab_focus()
			return
