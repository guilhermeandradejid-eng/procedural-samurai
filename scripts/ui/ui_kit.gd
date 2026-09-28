class_name UIKit
extends RefCounted
## Shared look for the interface: ink-on-parchment colours, fonts and small
## factory helpers for labels, buttons and panels.

const INK := Color(0.08, 0.07, 0.06)
const PAPER := Color(0.93, 0.89, 0.8)
const BONE := Color(0.95, 0.92, 0.85)
const RED := Color(0.72, 0.1, 0.07)
const GOLD := Color(0.88, 0.7, 0.35)
const SHADOW := Color(0, 0, 0, 0.55)

static var _fonts := {}


static func font(name: String) -> Font:
	if not _fonts.has(name):
		var path: String = {
			"title": "res://assets/fonts/KaushanScript-Regular.otf",
			"kanji": "res://assets/fonts/KouzanMouhitsu-Subset.ttf",
			"bold": "res://assets/fonts/AlegreyaSans-Bold.otf",
			"italic": "res://assets/fonts/AlegreyaSans-Italic.otf",
			"regular": "res://assets/fonts/AlegreyaSans-Regular.otf",
		}.get(name, "res://assets/fonts/AlegreyaSans-Medium.otf")
		_fonts[name] = load(path)
	return _fonts[name]


static func label(text: String, size := 22, font_name := "medium", color := BONE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(font_name))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, size := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font("bold"))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", RED)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 6)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.focus_entered.connect(func() -> void: Audio.play("ui_move", -12.0, 0.05))
	b.pressed.connect(func() -> void: Audio.play("ui_select", -8.0))
	return b


## Dark translucent backdrop with a brush-stroke edge.
static func backdrop(alpha := 0.62) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.02, 0.025, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	return r


static func brush(width: float, height: float, color := RED) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/textures/ui/brush_stroke.png")
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(width, height)
	t.size = Vector2(width, height)
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func icon(index: int, size := 32.0) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = load("res://assets/textures/ui/icons.png")
	a.region = Rect2(index * 128, 0, 128, 128)
	return a


## Anchors `c` with a preset and sets its offsets (pixels from the anchors).
static func anchor(c: Control, preset: int, left: float, top: float, right: float, bottom: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom


const ICON_INDEX := {"shrine": 0, "camp": 1, "village": 2, "onsen": 3, "temple": 4, "haiku": 5, "landmark": 6, "player": 7}
