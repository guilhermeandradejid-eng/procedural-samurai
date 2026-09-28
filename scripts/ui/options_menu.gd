class_name OptionsMenu
extends MenuPanel
## Settings screen bound to the Settings autoload.

var _grid: GridContainer


func _ready() -> void:
	title_label.text = "Opções"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 30)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	_choice("Qualidade gráfica", "quality", Settings.QUALITY_NAMES)
	_choice("Dificuldade", "difficulty", Settings.DIFFICULTY_NAMES)
	_slider("Escala de renderização", "render_scale", 0.5, 1.0, 0.05)
	_slider("Campo de visão", "fov", 55.0, 95.0, 1.0)
	_slider("Sensibilidade do mouse", "mouse_sensitivity", 0.3, 2.5, 0.05)
	_toggle("Inverter eixo Y", "invert_y")
	_slider("Volume geral", "master_volume", 0.0, 1.0, 0.05)
	_slider("Música", "music_volume", 0.0, 1.0, 0.05)
	_slider("Efeitos", "sfx_volume", 0.0, 1.0, 0.05)
	_slider("Ambiente", "ambience_volume", 0.0, 1.0, 0.05)
	_slider("Tremor de câmera", "camera_shake", 0.0, 1.5, 0.05)
	_slider("Duração do dia (min)", "day_length_minutes", 12.0, 90.0, 1.0)
	_toggle("Sangue e desmembramento", "gore")
	_toggle("Modo Kurosawa", "kurosawa")
	_toggle("Mostrar HUD", "show_hud")
	_toggle("Tela cheia", "fullscreen")
	_toggle("VSync", "vsync")
	var back := add_button("Voltar", close)
	back.custom_minimum_size = Vector2(0, 50)


func _label(text: String) -> void:
	var l := UIKit.label(text, 24, "medium")
	l.custom_minimum_size = Vector2(330, 36)
	_grid.add_child(l)


func _choice(text: String, key: String, names: Array) -> void:
	_label(text)
	var ob := OptionButton.new()
	for n in names:
		ob.add_item(n)
	ob.selected = int(Settings.get_value(key, 0))
	ob.custom_minimum_size = Vector2(300, 36)
	ob.item_selected.connect(func(i: int) -> void: Settings.set_value(key, i))
	_grid.add_child(ob)


func _slider(text: String, key: String, lo: float, hi: float, step: float) -> void:
	_label(text)
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key, lo))
	s.custom_minimum_size = Vector2(240, 30)
	var v := UIKit.label(_fmt(s.value, step), 20, "regular")
	v.custom_minimum_size = Vector2(60, 30)
	s.value_changed.connect(func(x: float) -> void:
		v.text = _fmt(x, step)
		Settings.set_value(key, x))
	h.add_child(s)
	h.add_child(v)
	_grid.add_child(h)


func _toggle(text: String, key: String) -> void:
	_label(text)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(key, false))
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	_grid.add_child(c)


func _fmt(v: float, step: float) -> String:
	return "%d" % int(v) if step >= 1.0 else "%.2f" % v


func _focus_first() -> void:
	for c in _grid.get_children():
		if c is Control and (c as Control).focus_mode != Control.FOCUS_NONE and not (c is Label):
			(c as Control).grab_focus()
			return
