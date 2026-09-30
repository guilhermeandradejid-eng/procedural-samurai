class_name Mist
extends Node3D
## Volumetric valley mist: one big FogVolume that follows the camera. Its
## density follows the terrain height under every voxel (see mist_fog.gdshader)
## and grows at dawn, in fog and drizzle, and around lakes.

var volume: FogVolume
var mat: ShaderMaterial
var _drift := Vector3.ZERO
var _amount := 0.0


func _ready() -> void:
	volume = FogVolume.new()
	volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	volume.size = Vector3(260, 50, 260)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/mist_fog.gdshader")
	var n := FastNoiseLite.new()
	n.seed = 21
	n.frequency = 0.03
	n.fractal_octaves = 3
	var t := NoiseTexture3D.new()
	t.width = 64
	t.height = 32
	t.depth = 64
	t.seamless = true
	t.noise = n
	mat.set_shader_parameter("noise_tex", t)
	volume.material = mat
	add_child(volume)
	_apply_visibility()
	Settings.changed.connect(func(k: String) -> void:
		if k == "quality":
			_apply_visibility())


func _apply_visibility() -> void:
	volume.visible = bool(Settings.quality().volumetric_fog)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var world := Game.world as World
	if cam == null or world == null or not volume.visible:
		return
	var c := cam.global_position
	var gy := world.data.get_height(c.x, c.z)
	volume.global_position = Vector3(c.x, gy + 18.0, c.z)
	var w := world.weather
	var tod := world.time_of_day
	var target := 0.06
	if w:
		target += w.fog * 0.5 + w.rain * 0.12 + w.storm * 0.06
	if tod:
		var t := tod.time
		# dawn mist rising off the ground, a touch of evening haze
		target += exp(-pow((t - 6.2) / 1.5, 2.0)) * 0.42 + exp(-pow((t - 18.4) / 1.2, 2.0)) * 0.08
	_amount = lerpf(_amount, target, clampf(delta * 0.3, 0.0, 1.0))
	mat.set_shader_parameter("amount", _amount)
	var wv := world.wind.vector3(0.02) if world.wind else Vector3.ZERO
	_drift += wv * delta * 0.5
	mat.set_shader_parameter("drift", _drift)
	mat.set_shader_parameter("thickness", 4.0 + (w.fog if w else 0.0) * 5.0)
