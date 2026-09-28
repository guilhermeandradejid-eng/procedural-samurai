class_name World
extends Node3D
## Builds and owns every part of the open world: environment/sky, terrain,
## water, vegetation, points of interest and ambient effects.

signal built

var data: WorldData
var terrain: Terrain
var environment_node: WorldEnvironment
var sun: DirectionalLight3D
var is_built := false


func build() -> void:
	data = WorldData.new()
	if not data.load_all():
		return
	data.apply_shader_globals()
	_build_environment()
	_build_terrain()
	is_built = true
	built.emit()


func _build_environment() -> void:
	environment_node = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.0006
	environment_node.environment = env
	add_child(environment_node)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-25.0, 150.0, 0.0)
	sun.light_energy = 1.2
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)


func _build_terrain() -> void:
	terrain = Terrain.new()
	terrain.name = "Terrain"
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	add_child(terrain)
	terrain.build(data, mat)
