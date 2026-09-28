extends SceneTree
## Build-time helper: generates the audio bus layout and the UI theme.
## Run: godot --headless --path . --script res://scripts/tools/make_resources.gd

const INK := Color(0.055, 0.045, 0.04, 0.86)
const PAPER := Color(0.93, 0.9, 0.82)
const GOLD := Color(0.79, 0.64, 0.33)
const RED := Color(0.72, 0.18, 0.14)


func _init() -> void:
	_make_bus_layout()
	_make_theme()
	print("resources generated")
	quit()


func _make_bus_layout() -> void:
	# Master <- Music, SFX, Ambience, UI
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(1)
	for n in ["Music", "SFX", "Ambience", "UI"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_send(i, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.55
	rev.damping = 0.6
	rev.spread = 0.8
	rev.wet = 0.09
	rev.dry = 1.0
	AudioServer.add_bus_effect(sfx, rev)
	var amb := AudioServer.get_bus_index("Ambience")
	var amb_rev := AudioEffectReverb.new()
	amb_rev.room_size = 0.8
	amb_rev.wet = 0.12
	AudioServer.add_bus_effect(amb, amb_rev)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20500.0
	AudioServer.add_bus_effect(0, lp)  # used for slow motion / underwater muffling
	var comp := AudioEffectCompressor.new()
	comp.threshold = -10.0
	comp.ratio = 3.0
	AudioServer.add_bus_effect(0, comp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	var layout := AudioServer.generate_bus_layout()
	DirAccess.make_dir_recursive_absolute("res://assets/audio")
	var err := ResourceSaver.save(layout, "res://assets/audio/bus_layout.tres")
	print("bus layout: ", err)


func _box(bg: Color, border := Color(0, 0, 0, 0), width := 0, radius := 2, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	sb.anti_aliasing = true
	return sb


func _make_theme() -> void:
	var th := Theme.new()
	var body: FontFile = load("res://assets/fonts/AlegreyaSans-Medium.otf")
	th.default_font = body
	th.default_font_size = 22
	var bold: FontFile = load("res://assets/fonts/AlegreyaSans-Bold.otf")
	# Labels
	th.set_color("font_color", "Label", PAPER)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	th.set_constant("outline_size", "Label", 4)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 2)
	# Buttons: ink flat buttons with a gold underline on hover
	var normal := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, 16)
	var hover := _box(Color(0.72, 0.18, 0.14, 0.18), GOLD, 0, 2, 16)
	hover.border_width_bottom = 2
	var pressed := _box(Color(0.72, 0.18, 0.14, 0.35), GOLD, 0, 2, 16)
	pressed.border_width_bottom = 2
	var focus := _box(Color(0, 0, 0, 0), GOLD, 0, 2, 16)
	focus.border_width_left = 3
	var disabled := _box(Color(0, 0, 0, 0))
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		th.set_stylebox("normal", cls, normal)
		th.set_stylebox("hover", cls, hover)
		th.set_stylebox("pressed", cls, pressed)
		th.set_stylebox("focus", cls, focus)
		th.set_stylebox("disabled", cls, disabled)
		th.set_color("font_color", cls, PAPER)
		th.set_color("font_hover_color", cls, Color(1, 0.95, 0.85))
		th.set_color("font_pressed_color", cls, GOLD)
		th.set_color("font_focus_color", cls, Color(1, 0.95, 0.85))
		th.set_color("font_disabled_color", cls, Color(0.5, 0.48, 0.45))
		th.set_font("font", cls, bold)
		th.set_font_size("font_size", cls, 26)
	th.set_stylebox("panel", "Panel", _box(INK, Color(GOLD, 0.5), 1, 3, 12))
	th.set_stylebox("panel", "PanelContainer", _box(INK, Color(GOLD, 0.5), 1, 3, 14))
	th.set_stylebox("panel", "PopupMenu", _box(Color(0.06, 0.05, 0.045, 0.97), Color(GOLD, 0.6), 1, 2, 8))
	th.set_color("font_color", "PopupMenu", PAPER)
	th.set_color("font_hover_color", "PopupMenu", GOLD)
	th.set_stylebox("hover", "PopupMenu", _box(Color(RED, 0.3)))
	# Sliders
	var track := _box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 3, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := _box(Color(RED, 0.85), Color(0, 0, 0, 0), 0, 3, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	# Progress bars
	th.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 2, 0))
	th.set_stylebox("fill", "ProgressBar", _box(Color(0.85, 0.82, 0.74, 0.95), Color(0, 0, 0, 0), 0, 2, 0))
	th.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))
	# Tooltips / line edits
	th.set_stylebox("panel", "TooltipPanel", _box(INK, Color(GOLD, 0.4), 1, 2, 8))
	th.set_color("font_color", "TooltipLabel", PAPER)
	DirAccess.make_dir_recursive_absolute("res://assets/ui")
	var err := ResourceSaver.save(th, "res://assets/ui/theme.tres")
	print("theme: ", err)
