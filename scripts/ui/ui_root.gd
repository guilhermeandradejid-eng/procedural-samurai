class_name UIRoot
extends CanvasLayer
## Owns every screen (post FX, HUD, title, pause, options, map, death) and
## routes the menu inputs; gameplay flow lives in main.gd.

signal start_game(new_game: bool)
signal respawn_requested
signal quit_to_title

var post: PostFX
var hud: HUD
var title: TitleScreen
var pause_menu: PauseMenu
var options: OptionsMenu
var map_screen: MapScreen
var death: DeathScreen
var _options_from := ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	post = PostFX.new()
	post.name = "PostFX"
	add_child(post)
	var theme_res: Theme = load("res://assets/ui/theme.tres")
	var root := Control.new()
	root.name = "Screens"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_res
	add_child(root)
	hud = HUD.new()
	hud.name = "HUD"
	root.add_child(hud)
	Game.hud = hud
	title = TitleScreen.new()
	root.add_child(title)
	pause_menu = PauseMenu.new()
	root.add_child(pause_menu)
	options = OptionsMenu.new()
	root.add_child(options)
	map_screen = MapScreen.new()
	root.add_child(map_screen)
	death = DeathScreen.new()
	root.add_child(death)
	title.start_game.connect(func(new_game: bool) -> void:
		title.close()
		start_game.emit(new_game))
	title.open_options.connect(func() -> void: _open_options("title"))
	pause_menu.resume.connect(resume)
	pause_menu.open_map.connect(func() -> void:
		pause_menu.visible = false
		map_screen.open())
	pause_menu.open_options.connect(func() -> void: _open_options("pause"))
	pause_menu.quit_to_title.connect(func() -> void:
		pause_menu.visible = false
		quit_to_title.emit())
	options.closed.connect(func() -> void:
		if _options_from == "title":
			title.open()
		elif _options_from == "pause":
			pause_menu.open())
	map_screen.closed.connect(func() -> void:
		if Game.state == Game.State.PAUSED:
			if pause_menu.visible == false and not options.visible:
				resume())
	death.respawn_requested.connect(func() -> void: respawn_requested.emit())
	Game.state_changed.connect(_on_state)


func _open_options(from: String) -> void:
	_options_from = from
	title.visible = false
	pause_menu.visible = false
	options.open()


func show_title() -> void:
	title.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	pause_menu.visible = false
	map_screen.visible = false
	options.visible = false
	Game.set_state(Game.State.PLAYING)


func _on_state(s: int) -> void:
	match s:
		Game.State.PLAYING:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.State.PAUSED, Game.State.TITLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Game.State.DEAD:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			death.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		Settings.set_value("fullscreen", not bool(Settings.get_value("fullscreen", false)))
	elif event.is_action_pressed("screenshot"):
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		var path := "user://screenshots/ezo_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
		img.save_png(path)
		Game.show_toast("Captura salva")
	if Game.state == Game.State.PLAYING:
		if event.is_action_pressed("pause"):
			Game.set_state(Game.State.PAUSED)
			pause_menu.open()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("map"):
			Game.set_state(Game.State.PAUSED)
			map_screen.open()
			get_viewport().set_input_as_handled()
	elif Game.state == Game.State.PAUSED:
		if event.is_action_pressed("pause"):
			if options.visible:
				options.close()
			elif pause_menu.visible:
				resume()
			get_viewport().set_input_as_handled()
	elif Game.state == Game.State.TITLE:
		if event.is_action_pressed("pause") and options.visible:
			options.close()
			get_viewport().set_input_as_handled()
	# mouse capture comes back when clicking into the game
	if Game.state == Game.State.PLAYING and event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
