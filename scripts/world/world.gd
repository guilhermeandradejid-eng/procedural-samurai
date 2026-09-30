class_name World
extends Node3D
## Builds and owns every part of the open world: environment/sky, terrain,
## water, vegetation, points of interest and ambient effects.

signal built

var data: WorldData
var terrain: Terrain
var environment_node: WorldEnvironment
var env: Environment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var time_of_day: TimeOfDay
var wind: Wind
var weather: Weather
var water: Water
var grass: GrassSystem
var forest: Forest
var settlements: Settlements
var population: Population
var ambient: AmbientParticles
var mist: Mist
var lightning_light: DirectionalLight3D
var is_built := false


func build() -> void:
	data = WorldData.new()
	if not data.load_all():
		return
	data.apply_shader_globals()
	_build_environment()
	_build_terrain()
	water = Water.new()
	water.name = "Water"
	add_child(water)
	water.build(data)
	grass = GrassSystem.new()
	grass.name = "Grass"
	add_child(grass)
	grass.build()
	forest = Forest.new()
	forest.name = "Forest"
	add_child(forest)
	forest.build(data)
	settlements = Settlements.new()
	settlements.name = "Settlements"
	add_child(settlements)
	settlements.build(data)
	population = Population.new()
	population.name = "Population"
	add_child(population)
	population.setup(data)
	ambient = AmbientParticles.new()
	ambient.name = "Ambient"
	add_child(ambient)
	mist = Mist.new()
	mist.name = "Mist"
	add_child(mist)
	lightning_light = DirectionalLight3D.new()
	lightning_light.name = "LightningLight"
	lightning_light.light_color = Color(0.75, 0.82, 1.0)
	lightning_light.light_energy = 0.0
	lightning_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	lightning_light.shadow_enabled = true
	lightning_light.light_volumetric_fog_energy = 3.0
	lightning_light.directional_shadow_max_distance = 120.0
	add_child(lightning_light)
	weather.lightning_flash.connect(func(strength: float) -> void:
		_lightning_flash(strength)
		# thunder arrives a moment after the flash
		get_tree().create_timer(randf_range(0.6, 2.8)).timeout.connect(func() -> void:
			Audio.play("thunder", lerpf(-8.0, 0.0, strength), 0.1, "Ambience")))
	Settings.changed.connect(func(key: String) -> void:
		if key == "quality":
			apply_quality())
	is_built = true
	built.emit()


## Lightning: a few violent flickers from a random direction, lighting the
## clouds (sky shader) and every drop of fog.
func _lightning_flash(strength: float) -> void:
	lightning_light.rotation_degrees = Vector3(randf_range(-80.0, -55.0), randf_range(0.0, 360.0), 0.0)
	var tw := create_tween()
	for i in randi_range(2, 4):
		tw.tween_property(lightning_light, "light_energy", randf_range(2.5, 5.0) * strength, 0.03)
		tw.tween_property(lightning_light, "light_energy", randf_range(0.0, 0.5), 0.05)
		tw.tween_interval(randf_range(0.02, 0.09))
	tw.tween_property(lightning_light, "light_energy", 0.0, 0.2)
	Game.shake(0.12 * strength)


func _noise_texture(seed: int, freq: float, octaves: int, cellular := false) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	else:
		n.noise_type = FastNoiseLite.TYPE_PERLIN
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t


func _build_environment() -> void:
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/sky.gdshader")
	sky_material.set_shader_parameter("cloud_noise", _noise_texture(11, 0.012, 5))
	sky_material.set_shader_parameter("cloud_detail", _noise_texture(12, 0.03, 3, true))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_agx_contrast = 1.18
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.7
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set("glow_levels/1", 0.0)
	env.set("glow_levels/2", 0.6)
	env.set("glow_levels/3", 1.0)
	env.set("glow_levels/4", 0.8)
	env.set("glow_levels/5", 0.6)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.12
	env.fog_height = 4.0
	env.fog_height_density = 0.004
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_sky_affect = 0.2
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	environment_node = WorldEnvironment.new()
	environment_node.environment = env
	add_child(environment_node)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 240.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.17
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 1.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 120.0
	moon.light_volumetric_fog_energy = 0.7
	add_child(moon)

	wind = Wind.new()
	wind.name = "Wind"
	add_child(wind)
	weather = Weather.new()
	weather.name = "Weather"
	weather.sky_mat = sky_material
	weather.wind = wind
	add_child(weather)
	time_of_day = TimeOfDay.new()
	time_of_day.name = "TimeOfDay"
	time_of_day.weather = weather
	add_child(time_of_day)
	time_of_day.setup(sun, moon, env, sky_material)
	apply_quality()


func apply_quality() -> void:
	var q := Settings.quality()
	env.ssao_enabled = q.ssao
	env.ssil_enabled = q.ssil
	env.volumetric_fog_enabled = q.volumetric_fog
	env.glow_enabled = q.glow
	sun.directional_shadow_max_distance = q.shadow_distance
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q.shadow_splits == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(q.shadow_size, true)


func _build_terrain() -> void:
	terrain = Terrain.new()
	terrain.name = "Terrain"
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("albedo_array", load("res://assets/textures/terrain/terrain_albedo.jpg"))
	mat.set_shader_parameter("nrh_array", load("res://assets/textures/terrain/terrain_nrh.png"))
	add_child(terrain)
	terrain.build(data, mat)
