extends Node3D
## Entry point: builds the world, spawns the player and the interface, and
## runs the game flow (title, play, death and rest, discovery of places,
## Guiding Wind, interaction, music intensity).
## Command line (after `--`):
##   --tour <dir> [--views a,b]   capture screenshots of the world and quit
##   --play                       skip the title screen

var world: World
var ui: UIRoot
var player: Player
var _discover_timer := 0.0
var _region := ""
var _tour := false


func _ready() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	Game.world = world
	world.build()
	var args := OS.get_cmdline_user_args()
	var ti := args.find("--tour")
	if ti >= 0:
		_tour = true
		var tour := preload("res://scripts/debug/shot_tour.gd").new()
		tour.out_dir = args[ti + 1] if ti + 1 < args.size() else "user://shots"
		var vi := args.find("--views")
		if vi >= 0 and vi + 1 < args.size():
			tour.only = args[vi + 1].split(",")
		add_child(tour)
		return
	if Game.auto_test:
		var at := preload("res://scripts/debug/autotest.gd").new()
		at.name = "AutoTest"
		add_child(at)
	ui = UIRoot.new()
	ui.name = "UI"
	add_child(ui)
	ui.start_game.connect(_on_start_game)
	ui.respawn_requested.connect(_respawn)
	ui.quit_to_title.connect(_to_title)
	var tod := world.time_of_day
	if tod:
		tod.time = float(SaveGame.data.get("time_of_day", 16.8))
		tod.day_minutes = float(Settings.get_value("day_length_minutes", 36.0))
	_spawn_player()
	if args.has("--play"):
		_on_start_game(false)
	else:
		Game.set_state(Game.State.TITLE)
		player.input_enabled = false
		ui.show_title()
	Audio.play_music("exploration")
	_update_ambience()


func _spawn_player() -> void:
	var d := world.data
	var pos := d.spawn
	var saved: Variant = SaveGame.data.get("player_pos", null)
	if saved is Dictionary:
		pos = Vector3(float(saved.x), 0.0, float(saved.z))
		pos.y = d.get_height(pos.x, pos.z)
	player = Player.new()
	player.name = "Player"
	player.position = pos + Vector3(0, 0.05, 0)
	var to_vol := d.volcano - pos
	player.rotation.y = atan2(-to_vol.x, -to_vol.z)
	add_child(player)
	player.died.connect(func(_c: Character, _i: Dictionary) -> void:
		Audio.set_combat_intensity(0.0))


func _on_start_game(new_game: bool) -> void:
	if new_game:
		SaveGame.reset()
		player.max_resolve = 3
		player.resolve = 2
		player.max_health = 100.0
		player.health = player.max_health
		player.respawn(world.data.spawn + Vector3(0, 0.05, 0))
		world.time_of_day.time = 16.8
	player.input_enabled = true
	Game.set_state(Game.State.PLAYING)
	var region := world.data.region_name_at(player.global_position.x, player.global_position.z)
	_region = region
	Game.show_banner("Ilha de Ezo", region, "location")


func _to_title() -> void:
	var p := player.global_position
	SaveGame.data["player_pos"] = {"x": p.x, "z": p.z}
	SaveGame.data["time_of_day"] = world.time_of_day.time
	SaveGame.save_game()
	player.input_enabled = false
	Game.set_state(Game.State.TITLE)
	ui.show_title()


## Rise again at the last place of rest (sacred tree, shrine) or the start.
func _respawn() -> void:
	var d := world.data
	var at := d.spawn
	var r: Variant = SaveGame.data.get("respawn", null)
	if r is Dictionary:
		at = Vector3(float(r.x), 0.0, float(r.z))
		at.y = d.get_height(at.x, at.z)
	ui.post.fade_to(1.0, 3.0)
	await get_tree().create_timer(0.45, true, false, true).timeout
	player.respawn(at + Vector3(0, 0.05, 0))
	# the enemies that won lose interest
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en and not en.dead and en.state == Enemy.State.COMBAT:
			en.state = Enemy.State.IDLE
			en.aware = false
			en.detection = 0.0
			en.global_position = en.home + Vector3(0, 0.05, 0)
	Game.set_state(Game.State.PLAYING)
	ui.post.fade_to(0.0, 1.2)


func _process(delta: float) -> void:
	if _tour or player == null or not Game.is_playing():
		return
	_discover_timer -= delta
	if _discover_timer <= 0.0:
		_discover_timer = 0.5
		_check_discovery()
		_update_ambience()
	_update_combat_music(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not Game.is_playing() or player == null or player.dead:
		return
	if event.is_action_pressed("interact"):
		var it := ui.hud.current_interactable()
		if it:
			it.interact(player)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("guiding_wind"):
		_guiding_wind()


func _check_discovery() -> void:
	var p := player.global_position
	for poi in world.data.pois:
		var id := String(poi.id)
		if SaveGame.has("discovered", id):
			continue
		var d := Vector2(float(poi.x) - p.x, float(poi.z) - p.z).length()
		if d < float(poi.get("radius", 15.0)) + 22.0:
			SaveGame.mark("discovered", id)
			Game.location_discovered.emit(poi)
			var kind: String = {"camp": "Acampamento inimigo", "village": "Vila", "temple": "Templo", "shrine": "Santuário xintoísta",
				"onsen": "Fonte termal", "haiku": "Local de haiku", "landmark": "Lugar sagrado"}.get(String(poi.type), "")
			Game.show_banner(String(poi.get("name", kind)), kind, "location")
			if String(SaveGame.data.get("destination", "")) == id:
				SaveGame.data.erase("destination")
	var region := world.data.region_name_at(p.x, p.z)
	if region != _region:
		_region = region
		Game.show_toast(region)


## The Guiding Wind blows towards the chosen destination (or the nearest
## unexplored place, or the nearest occupied camp).
func _guiding_wind() -> void:
	var p := player.global_position
	var target := {}
	var dest := String(SaveGame.data.get("destination", ""))
	for poi in world.data.pois:
		if String(poi.id) == dest:
			target = poi
	if target.is_empty():
		var bd := INF
		for poi in world.data.pois:
			var done := SaveGame.has("discovered", String(poi.id))
			if String(poi.type) == "camp":
				done = SaveGame.has("cleared_camps", String(poi.id))
			if done:
				continue
			var d := Vector2(float(poi.x) - p.x, float(poi.z) - p.z).length()
			if d < bd:
				bd = d
				target = poi
	if target.is_empty():
		Game.show_toast("O vento está calmo. Não há mais nada a descobrir.")
		return
	var dir := Vector2(float(target.x) - p.x, float(target.z) - p.z)
	world.wind.guide_towards(dir.normalized(), 8.0)
	Audio.play("guiding_wind", -4.0)
	var dist := int(dir.length())
	Game.show_toast("O vento guia você a %s (%d m)" % [String(target.get("name", "")), dist])


## Ambience beds follow the time of day, the weather and the surroundings.
func _update_ambience() -> void:
	var tod := world.time_of_day
	var w := world.weather
	var day := tod.daylight() if tod else 1.0
	var rain := w.rain if w else 0.0
	var pos := player.global_position if player else world.data.spawn
	# how much sea is around (samples on a ring)
	var sea := 0.0
	for k in 12:
		var a := TAU * k / 12.0
		var q := pos + Vector3(cos(a), 0, sin(a)) * 70.0
		if world.data.get_height(q.x, q.z) < world.data.sea_level:
			sea += 1.0 / 12.0
	var altitude := clampf((pos.y - 60.0) / 180.0, 0.0, 1.0)
	var windy := world.wind.strength if world.wind else 1.0
	Audio.set_ambience("wind", 0.25 + altitude * 0.6 + windy * 0.12 + rain * 0.2)
	Audio.set_ambience("birds", day * (1.0 - rain) * (1.0 - altitude) * 0.7)
	Audio.set_ambience("crickets", (1.0 - day) * (1.0 - rain) * (1.0 - altitude) * 0.6)
	Audio.set_ambience("ocean", clampf(sea * 1.6, 0.0, 0.9))
	Audio.set_ambience("rain", rain * 0.9)


func _update_combat_music(_delta: float) -> void:
	var fighting := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en and not en.dead and en.state == Enemy.State.COMBAT and en.global_position.distance_to(player.global_position) < 40.0:
			fighting += 1
	Audio.set_combat_intensity(clampf(fighting / 3.0, 0.0, 1.0))
