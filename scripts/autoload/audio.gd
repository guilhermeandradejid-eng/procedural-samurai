extends Node
## Sound playback: pooled 3D/2D one-shots with variation, cross-faded music
## layers (exploration / combat / standoff) and looping ambience beds.
## Sounds are listed in res://assets/audio/manifest.json (written by the
## synthesiser in tools/audio).

const MANIFEST := "res://assets/audio/manifest.json"
const POOL_3D := 40
const POOL_2D := 12

var sfx := {}        # name -> Array[AudioStream]
var music := {}      # name -> AudioStream
var ambience := {}   # name -> AudioStream
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _next3d := 0
var _next2d := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current := ""
var _music_active: AudioStreamPlayer
var _combat_layer: AudioStreamPlayer
var _combat_target := 0.0
var _combat_level := 0.0
var _amb_players := {}  # name -> AudioStreamPlayer
var _amb_targets := {}  # name -> linear volume
var _last_play := {}    # name -> msec (debounce)
var music_duck := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_manifest()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 6.0
		p.max_distance = 90.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -12.0
		p.panning_strength = 0.9
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2d.append(p)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_combat_layer = _make_music_player()
	_music_active = _music_a


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		push_warning("Audio: no manifest, running silent (run tools/audio/synth_all.py)")
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var base := "res://assets/audio/"
	for name in data.get("sfx", {}):
		var arr: Array[AudioStream] = []
		for path in data.sfx[name]:
			var s: AudioStream = load(base + path)
			if s != null:
				arr.append(s)
		sfx[name] = arr
	for name in data.get("music", {}):
		music[name] = load(base + data.music[name])
	for name in data.get("ambience", {}):
		ambience[name] = load(base + data.ambience[name])


func has_sound(name: String) -> bool:
	return sfx.has(name) and not sfx[name].is_empty()


func _pick(name: String) -> AudioStream:
	var arr: Array = sfx.get(name, [])
	if arr.is_empty():
		return null
	return arr[randi() % arr.size()]


## Plays a positional one-shot. Returns the player (or null).
func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.08, max_dist := 90.0, debounce_ms := 0) -> AudioStreamPlayer3D:
	var s := _pick(name)
	if s == null:
		return null
	if debounce_ms > 0:
		var now := Time.get_ticks_msec()
		if now - int(_last_play.get(name, -100000)) < debounce_ms:
			return null
		_last_play[name] = now
	var p := _pool3d[_next3d]
	_next3d = (_next3d + 1) % POOL_3D
	p.stop()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.pitch_scale = maxf(0.05, (1.0 + randf_range(-pitch_var, pitch_var)) * Engine.time_scale ** 0.35)
	p.play()
	return p


## Attaches a looping positional sound (camp fire, onsen water...) to
## `parent`; it plays while the parent is in the tree.
func attach_loop(name: String, parent: Node3D, volume_db := 0.0, max_dist := 30.0) -> AudioStreamPlayer3D:
	var s: AudioStream = ambience.get(name, null)
	if s == null:
		s = _pick(name)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "Ambience"
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 4.0
	p.autoplay = true
	parent.add_child(p)
	return p


## Plays a non-positional one-shot (UI, stingers).
func play(name: String, volume_db := 0.0, pitch_var := 0.0, bus := "SFX") -> AudioStreamPlayer:
	var s := _pick(name)
	if s == null:
		return null
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % POOL_2D
	p.stop()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
	return p


func play_music(name: String, fade := 3.0, volume_db := -4.0) -> void:
	if name == _music_current:
		return
	_music_current = name
	var old := _music_active
	var nxt := _music_b if _music_active == _music_a else _music_a
	_music_active = nxt
	if music.has(name):
		nxt.stream = music[name]
		nxt.volume_db = -60.0
		nxt.play()
		var tw := create_tween().set_parallel(true)
		tw.tween_property(nxt, "volume_db", volume_db, fade)
		tw.tween_property(old, "volume_db", -80.0, fade)
		tw.chain().tween_callback(old.stop)
	else:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -80.0, fade)
		tw.tween_callback(old.stop)


func stop_music(fade := 2.0) -> void:
	_music_current = ""
	var tw := create_tween().set_parallel(true)
	for p in [_music_a, _music_b]:
		tw.tween_property(p, "volume_db", -80.0, fade)


## 0..1 intensity of the combat drum layer mixed on top of the music.
func set_combat_intensity(v: float) -> void:
	_combat_target = clampf(v, 0.0, 1.0)
	if _combat_target > 0.01 and not _combat_layer.playing and music.has("combat"):
		_combat_layer.stream = music["combat"]
		_combat_layer.play()


func set_ambience(name: String, linear: float) -> void:
	if not ambience.has(name):
		return
	if not _amb_players.has(name):
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = ambience[name]
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_amb_players[name] = p
	_amb_targets[name] = clampf(linear, 0.0, 1.5)


func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.05)
	_combat_level = move_toward(_combat_level, _combat_target, dt * 0.5)
	if _combat_layer.playing:
		_combat_layer.volume_db = linear_to_db(maxf(_combat_level * music_duck, 0.0001)) - 3.0
		if _combat_level <= 0.001 and _combat_target <= 0.0:
			_combat_layer.stop()
	for name in _amb_players:
		var p: AudioStreamPlayer = _amb_players[name]
		var cur := db_to_linear(p.volume_db)
		var tgt: float = _amb_targets.get(name, 0.0)
		cur = move_toward(cur, tgt, dt * 0.35)
		p.volume_db = linear_to_db(maxf(cur, 0.0001))
		# slow motion also slows the world
		p.pitch_scale = clampf(Engine.time_scale ** 0.25, 0.5, 1.0)
	var mscale := clampf(Engine.time_scale ** 0.2, 0.6, 1.0)
	_music_a.pitch_scale = mscale
	_music_b.pitch_scale = mscale
	_combat_layer.pitch_scale = mscale
