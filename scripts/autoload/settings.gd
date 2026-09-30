extends Node
## Persistent user settings (graphics, audio, controls) + quality presets.

signal changed(key: String)

const PATH := "user://settings.cfg"

const QUALITY_NAMES := ["Baixa", "Média", "Alta", "Ultra"]

var values := {
	"quality": 2,
	"render_scale": 1.0,
	"fullscreen": false,
	"vsync": true,
	"fov": 72.0,
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"master_volume": 0.9,
	"music_volume": 0.65,
	"sfx_volume": 0.9,
	"ambience_volume": 0.8,
	"gore": true,
	"camera_shake": 1.0,
	"motion_blur": 1.0,   # zoom blur and speed streaks
	"combat_fx": 1.0,     # wind slashes, afterimages
	"show_hud": true,
	"day_length_minutes": 36.0,
	"difficulty": 1,   # 0 historia, 1 normal, 2 dificil, 3 letal
	"kurosawa": false,
	"subtitles": true,
}

const DIFFICULTY_NAMES := ["História", "Normal", "Difícil", "Letal"]
## enemy damage multiplier and enemy aggression per difficulty
const DIFFICULTY := [
	{"enemy_damage": 0.45, "aggression": 0.75, "tokens": 1},
	{"enemy_damage": 0.75, "aggression": 1.0, "tokens": 2},
	{"enemy_damage": 1.0, "aggression": 1.2, "tokens": 2},
	{"enemy_damage": 2.2, "aggression": 1.35, "tokens": 3},
]


func difficulty() -> Dictionary:
	return DIFFICULTY[clampi(int(values.get("difficulty", 1)), 0, 3)]


func _ready() -> void:
	load_settings()
	apply()


func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	save_settings()
	apply()
	changed.emit(key)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in values.keys():
		values[k] = cfg.get_value("settings", k, values[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values.keys():
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)


## Per-quality parameters consumed by the world, vegetation and post FX.
func quality() -> Dictionary:
	var q: int = clampi(int(values.quality), 0, 3)
	var presets := [
		{"grass_near": 110, "grass_far": 70, "pampas": 90, "flowers": 60, "tree_lod0": 55.0, "tree_lod1": 150.0,
			"tree_far": 900.0, "rock_far": 220.0, "shadow_distance": 140.0, "shadow_splits": 2, "ssao": false, "ssil": false,
			"volumetric_fog": false, "glow": true, "shadow_size": 2048, "decals": 40, "sss": false},
		{"grass_near": 150, "grass_far": 90, "pampas": 120, "flowers": 80, "tree_lod0": 70.0, "tree_lod1": 190.0,
			"tree_far": 1200.0, "rock_far": 300.0, "shadow_distance": 180.0, "shadow_splits": 4, "ssao": true, "ssil": false,
			"volumetric_fog": true, "glow": true, "shadow_size": 4096, "decals": 80, "sss": true},
		{"grass_near": 200, "grass_far": 120, "pampas": 150, "flowers": 100, "tree_lod0": 90.0, "tree_lod1": 240.0,
			"tree_far": 1600.0, "rock_far": 380.0, "shadow_distance": 240.0, "shadow_splits": 4, "ssao": true, "ssil": false,
			"volumetric_fog": true, "glow": true, "shadow_size": 4096, "decals": 140, "sss": true},
		{"grass_near": 256, "grass_far": 160, "pampas": 190, "flowers": 128, "tree_lod0": 120.0, "tree_lod1": 320.0,
			"tree_far": 2200.0, "rock_far": 480.0, "shadow_distance": 320.0, "shadow_splits": 4, "ssao": true, "ssil": true,
			"volumetric_fog": true, "glow": true, "shadow_size": 8192, "decals": 220, "sss": true},
	]
	return presets[q]


func apply() -> void:
	var win := get_window()
	if win != null and not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		var want_fs: bool = values.fullscreen
		var is_fs := win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		if want_fs != is_fs:
			win.mode = Window.MODE_FULLSCREEN if want_fs else Window.MODE_WINDOWED
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = clampf(float(values.render_scale), 0.5, 1.0)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(values.render_scale) < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	_set_bus("Master", float(values.master_volume))
	_set_bus("Music", float(values.music_volume))
	_set_bus("SFX", float(values.sfx_volume))
	_set_bus("Ambience", float(values.ambience_volume))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)
