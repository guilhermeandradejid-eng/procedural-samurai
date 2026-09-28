class_name DeathScreen
extends Control
## Shown when the player falls: a single brush kanji over a red wash, then
## the prompt to rise again at the last place of rest.

signal respawn_requested

var kanji: Label
var text: Label
var hint: Label
var _t := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.0, 0.0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var splash := TextureRect.new()
	splash.texture = load("res://assets/textures/ui/ink_splash.png")
	splash.modulate = Color(0.45, 0.02, 0.02, 0.8)
	UIKit.anchor(splash, Control.PRESET_CENTER, -300, -330, 300, 270)
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(splash)
	kanji = UIKit.label("死", 260, "kanji", UIKit.BONE, 0)
	UIKit.anchor(kanji, Control.PRESET_CENTER, -200, -320, 200, 0)
	kanji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(kanji)
	text = UIKit.label("Você tombou em combate", 44, "title", UIKit.BONE, 8)
	UIKit.anchor(text, Control.PRESET_CENTER, -400, 30, 400, 100)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(text)
	hint = UIKit.label("", 24, "italic", Color(0.95, 0.9, 0.8), 5)
	UIKit.anchor(hint, Control.PRESET_CENTER, -400, 120, 400, 160)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func open() -> void:
	visible = true
	_t = 0.0
	modulate.a = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	var real := delta / maxf(Engine.time_scale, 0.02)
	_t += real
	modulate.a = clampf(_t / 1.2, 0.0, 1.0)
	hint.text = "Pressione qualquer tecla para se reerguer" if _t > 2.0 else ""
	kanji.scale = Vector2.ONE * (1.0 + maxf(0.0, 0.3 - _t * 0.3))


func _input(event: InputEvent) -> void:
	if not visible or _t < 2.0:
		return
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed():
		get_viewport().set_input_as_handled()
		visible = false
		respawn_requested.emit()
