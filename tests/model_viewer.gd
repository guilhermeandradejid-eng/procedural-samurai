extends SceneTree
## Visual check of the Blender models: assembles the character archetypes in
## rest pose, lays out weapons, trees, rocks and buildings, and saves shots.
## Run: godot --path . --rendering-driver vulkan --script res://tests/model_viewer.gd -- <out_dir>

var out_dir := "user://viewer"
var cam: Camera3D
var shots: Array = []
var _i := -1
var _wait := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.75)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root3d.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.4, 0.26)
	ground.material_override = gm
	root3d.add_child(ground)

	var styles := ["player", "ronin", "brute", "leader", "spearman"]
	for i in styles.size():
		var ch := assemble(styles[i], i)
		ch.position = Vector3(-4.0 + i * 2.0, 0, 0)
		root3d.add_child(ch)
	var weapons := ["katana", "nodachi", "kanabo", "yari"]
	for i in weapons.size():
		var w: Node3D = (load("res://assets/models/weapons/%s.glb" % weapons[i]) as PackedScene).instantiate()
		MaterialLibrary.apply(w)
		w.position = Vector3(-3.0 + i * 1.6, 1.3, 3.0)
		w.rotation_degrees = Vector3(0, 0, -70)
		root3d.add_child(w)
	var trees := ["maple_0", "ginkgo_0", "pine_0", "birch_0", "sakura_0", "bamboo_0"]
	for i in trees.size():
		var t: Node3D = (load("res://assets/models/trees/%s.glb" % trees[i]) as PackedScene).instantiate()
		MaterialLibrary.apply(t)
		for c in t.get_children():
			c.visible = c.name == "lod0"
		t.position = Vector3(-20.0 + i * 8.0, 0, -14.0)
		root3d.add_child(t)
	var rocks := ["boulder_0", "boulder_1", "boulder_2", "slab_0", "spire_0", "cliff_0"]
	for i in rocks.size():
		var r: Node3D = (load("res://assets/models/rocks/%s.glb" % rocks[i]) as PackedScene).instantiate()
		MaterialLibrary.apply(r)
		r.position = Vector3(-16.0 + i * 6.0, 0, 16.0)
		root3d.add_child(r)
	var blds := ["torii", "hokora", "temple_hall", "pagoda", "minka_0", "minka_1", "watchtower", "tent", "jinmaku_0", "palisade", "bamboo_fence"]
	for i in blds.size():
		var b: Node3D = (load("res://assets/models/buildings/%s.glb" % blds[i]) as PackedScene).instantiate()
		MaterialLibrary.apply(b)
		b.position = Vector3(-60.0 + i * 14.0, 0, -45.0)
		root3d.add_child(b)
	cam = Camera3D.new()
	cam.fov = 50
	root3d.add_child(cam)
	shots = [
		{"n": "characters", "p": Vector3(0, 1.6, 6.5), "t": Vector3(0, 1.0, 0)},
		{"n": "char_close", "p": Vector3(-3.2, 1.7, 2.2), "t": Vector3(-4.0, 1.2, 0)},
		{"n": "char_back", "p": Vector3(1.5, 2.2, -3.5), "t": Vector3(0, 1.1, 0)},
		{"n": "weapons", "p": Vector3(-0.8, 2.2, 5.6), "t": Vector3(-0.8, 1.3, 3.0)},
		{"n": "trees", "p": Vector3(0, 6, 14), "t": Vector3(0, 5, -14)},
		{"n": "rocks", "p": Vector3(0, 7, 34), "t": Vector3(0, 1, 16)},
		{"n": "buildings", "p": Vector3(10, 20, 10), "t": Vector3(10, 5, -45)},
		{"n": "buildings2", "p": Vector3(-35, 10, -15), "t": Vector3(-40, 5, -45)},
	]


func assemble(style: String, seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	var holder := Node3D.new()
	var body: Node3D = (load("res://assets/models/characters/body.glb") as PackedScene).instantiate()
	holder.add_child(body)
	var gear_scene: Node3D = (load("res://assets/models/characters/gear.glb") as PackedScene).instantiate()
	var wanted := CharacterStyle.gear_for(style, rng)
	for c in gear_scene.get_children():
		if not (String(c.name) in wanted):
			c.queue_free()
	holder.add_child(gear_scene)
	var ov := CharacterStyle.overrides_for(style, rng)
	MaterialLibrary.apply(holder, ov)
	var s: float = CharacterStyle.STYLES[style].scale
	holder.scale = Vector3.ONE * s
	return holder


func _process(_d: float) -> bool:
	if _i < 0:
		_i = 0
		_set_view()
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("%s.png" % shots[_i].n))
	print("shot ", shots[_i].n)
	_i += 1
	if _i >= shots.size():
		quit()
		return true
	_set_view()
	return false


func _set_view() -> void:
	cam.global_position = shots[_i].p
	cam.look_at(shots[_i].t)
	cam.make_current()
	_wait = 6
