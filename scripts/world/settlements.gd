class_name Settlements
extends Node3D
## Dresses every point of interest from world.json with the Blender models:
## bandit camps (tents, jinmaku curtains, watchtower, fire, banners),
## farming villages, the mountain temple, Shinto shrines, hot springs, haiku
## spots and the sacred tree. Layouts are deterministic per POI id and face
## the nearest road, so paths lead naturally into each place.

const MODELS := "res://assets/models/"

var data: WorldData
var lights: Array[OmniLight3D] = []    # night-only lights (lanterns)
var markers := {}                      # poi id -> Node3D root
var _scenes := {}
var _light_timer := 0.0


func build(world_data: WorldData) -> void:
	data = world_data
	for p in data.pois:
		var root := Node3D.new()
		root.name = String(p.id)
		add_child(root)
		markers[p.id] = root
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(p.id))
		match String(p.type):
			"camp":
				_camp(root, p, rng)
			"village":
				_village(root, p, rng)
			"temple":
				_temple(root, p, rng)
			"shrine":
				_shrine(root, p, rng)
			"onsen":
				_onsen(root, p, rng)
			"haiku":
				_haiku(root, p, rng)
			"landmark":
				_landmark(root, p, rng)


# ------------------------------------------------------------------ helpers

func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(MODELS + path + ".glb")
	return _scenes[path]


func _center(p: Dictionary) -> Vector2:
	return Vector2(float(p.x), float(p.z))


## Direction from the POI towards the closest road point (its entrance).
func _entrance_dir(p: Dictionary) -> Vector2:
	var c := _center(p)
	var best := Vector2.ZERO
	var bd := INF
	for r in data.roads:
		for q in r.points:
			var v := Vector2(float(q[0]), float(q[1]))
			var d := v.distance_squared_to(c)
			if d < bd and d > 16.0:
				bd = d
				best = v
	if bd == INF:
		return Vector2(0, 1)
	return (best - c).normalized()


## Lowest ground around a footprint so buildings never float on slopes.
func _ground(x: float, z: float, r: float) -> float:
	var h := data.get_height(x, z)
	if r <= 0.1:
		return h
	for k in 8:
		var a := TAU * k / 8.0
		h = minf(h, data.get_height(x + cos(a) * r, z + sin(a) * r))
	return h


## Instantiates a model at (x, z). `yaw` rotates about Y; `foot` is the
## footprint radius used to seat it on the ground.
func _put(parent: Node3D, model: String, pos: Vector2, yaw: float, foot := 0.0, scale := 1.0, vis := 450.0) -> Node3D:
	var ps := _scene(model)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.position = Vector3(pos.x, _ground(pos.x, pos.y, foot * scale) - 0.04, pos.y)
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	MaterialLibrary.apply(n)
	parent.add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = vis
		(mi as MeshInstance3D).visibility_range_end_margin = 20.0
		(mi as MeshInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return n


## Yaw that makes a model's local -Z (its front) face `dir`.
func _face(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)


## Yaw that lays a model's local +X along `tangent` (curtains, fences).
func _along(tangent: Vector2) -> float:
	return atan2(-tangent.y, tangent.x)


func _polar(c: Vector2, ang: float, r: float) -> Vector2:
	return c + Vector2(cos(ang), sin(ang)) * r


func _lantern_light(parent: Node3D, pos: Vector3, energy := 1.2, rng_ := 7.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.3)
	l.omni_range = rng_
	l.light_energy = 0.0
	l.set_meta("energy", energy)
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 80.0
	l.distance_fade_length = 25.0
	l.position = pos
	parent.add_child(l)
	lights.append(l)


func _interactable(parent: Node3D, p: Dictionary, kind: String, prompt: String, pos: Vector2, once := false) -> Interactable:
	var it := Interactable.new()
	it.kind = kind
	it.poi = p
	it.prompt = prompt
	it.once = once
	it.name = "Interact_" + kind
	it.position = Vector3(pos.x, data.get_height(pos.x, pos.y) + 0.5, pos.y)
	parent.add_child(it)
	return it


# ------------------------------------------------------------------ camps

func _camp(root: Node3D, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := _center(p)
	var R := float(p.get("radius", 20.0))
	var ent := _entrance_dir(p)
	var ent_a := ent.angle()
	# the fire in the middle
	var fire := _put(root, "props/campfire", c, rng.randf() * TAU, 0.8)
	var cf := Campfire.new()
	cf.name = "Fire"
	cf.position = fire.position + Vector3(0, 0.05, 0)
	root.add_child(cf)
	# log benches around the fire (enemies sit there)
	for k in 3:
		var a := ent_a + PI * 0.35 + k * TAU / 3.0
		var bp := _polar(c, a, 2.7)
		_put(root, "props/bench", bp, _along(Vector2(-sin(a), cos(a))), 0.6)
	# tents on a ring, openings (+X) facing the fire
	var nt := 3 + rng.randi() % 3
	for k in nt:
		var a := ent_a + PI * 0.45 + (TAU - PI * 0.9) * (k + 0.5) / nt + rng.randf_range(-0.12, 0.12)
		var tp := _polar(c, a, R * 0.55)
		var to_c := (c - tp).normalized()
		_put(root, "buildings/tent", tp, atan2(-to_c.y, to_c.x), 2.2)
		# supplies next to each tent
		var side := Vector2(-to_c.y, to_c.x)
		var sp := tp + side * 2.9 + to_c * 0.6
		var pick: String = ["props/crate", "props/barrel", "props/rice_bales", "props/sake_jar"][rng.randi() % 4]
		_put(root, pick, sp, rng.randf() * TAU, 0.5)
		if rng.randf() < 0.5:
			_put(root, "props/barrel", sp + side * 0.9, rng.randf() * TAU, 0.4)
	# jinmaku curtain wall with an opening at the entrance and a back gate
	var rr := R * 0.88
	var step := 6.1 / rr
	var back_gap := ent_a + PI + rng.randf_range(-0.6, 0.6)
	var a0 := ent_a + 0.42
	var a := a0
	while a < ent_a + TAU - 0.42:
		var mid := a + step * 0.5
		if absf(wrapf(mid - back_gap, -PI, PI)) > step * 0.6:
			var pp := _polar(c, mid, rr)
			var tangent := Vector2(-sin(mid), cos(mid))
			_put(root, "buildings/jinmaku_%d" % (rng.randi() % 2), pp, _along(tangent), 3.0)
		a += step
	# banners flanking the entrance and around the wall
	for s in [-1, 1]:
		var bp := _polar(c, ent_a + s * 0.5, rr + 0.8)
		_put(root, "props/nobori_%d" % (rng.randi() % 2), bp, _face(ent), 0.2)
	for k in 2:
		var bp := _polar(c, ent_a + PI * (0.6 + k * 0.8), rr - 1.2)
		_put(root, "props/nobori_%d" % (rng.randi() % 2), bp, rng.randf() * TAU, 0.2)
	# watchtower at the back, weapon rack and training post near the fire
	var wt := _polar(c, ent_a + PI + 0.35, R * 0.62)
	_put(root, "buildings/watchtower", wt, rng.randf() * TAU, 1.6, 1.0, 700.0)
	var wr := _polar(c, ent_a + PI * 0.2, 5.0)
	_put(root, "props/weapon_rack", wr, _face((c - wr).normalized()), 0.8)
	if R > 18.0:
		_put(root, "props/makiwara", _polar(c, ent_a - PI * 0.3, 6.5), rng.randf() * TAU, 0.3)
	# paper lanterns on poles at the entrance
	for s in [-1, 1]:
		var lp := _polar(c, ent_a + s * 0.3, rr - 0.6)
		var l := _put(root, "props/paper_lantern", lp, 0.0, 0.2)
		if l:
			l.position.y += 2.3
			_lantern_light(root, l.position + Vector3(0, 0.2, 0), 1.0, 8.0)


# ------------------------------------------------------------------ villages

func _village(root: Node3D, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := _center(p)
	var R := float(p.get("radius", 30.0))
	var ent := _entrance_dir(p)
	var ent_a := ent.angle()
	_put(root, "props/well", c, rng.randf() * TAU, 1.0)
	var nh := 4 + rng.randi() % 3
	for k in nh:
		var a := ent_a + PI * 0.3 + (TAU - PI * 0.6) * (k + 0.5) / nh + rng.randf_range(-0.1, 0.1)
		var hp := _polar(c, a, R * 0.62)
		var to_c := (c - hp).normalized()
		_put(root, "buildings/minka_%d" % (rng.randi() % 2), hp, _face(to_c), 5.5, 1.0, 900.0)
		# props at the veranda
		var side := Vector2(-to_c.y, to_c.x)
		var front := hp + to_c * 6.0
		_put(root, "props/rice_bales" if rng.randf() < 0.5 else "props/barrel", front + side * 3.5, rng.randf() * TAU, 0.5)
		if rng.randf() < 0.6:
			_put(root, "props/bench", front - side * 2.5, _along(side), 0.6)
		var lp := front + side * 1.2
		var l := _put(root, "props/paper_lantern", lp, 0.0, 0.1)
		if l:
			l.position.y += 2.1
			_lantern_light(root, l.position + Vector3(0, 0.2, 0), 1.1, 7.0)
		# bamboo fence between this house and the next
		var a2 := a + (TAU - PI * 0.6) / nh * 0.5
		var fp := _polar(c, a2, R * 0.72)
		_put(root, "buildings/bamboo_fence", fp, _along(Vector2(-sin(a2), cos(a2))), 1.5)
	# guardian jizo statues and stone lanterns at the village entrance
	var e := c + ent * (R * 0.85)
	var side_e := Vector2(-ent.y, ent.x)
	for s in [-1, 1]:
		_put(root, "props/stone_lantern", e + side_e * 2.6 * s, _face(ent), 0.4)
	for k in 3:
		_put(root, "props/jizo", e + side_e * (4.2 + k * 0.7) + ent * 0.4, _face(ent), 0.3)
	_put(root, "props/makiwara", _polar(c, ent_a + PI * 0.5, R * 0.3), 0.0, 0.3)


# ------------------------------------------------------------------ temple

func _temple(root: Node3D, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := _center(p)
	var R := float(p.get("radius", 30.0))
	var ent := _entrance_dir(p)
	var side := Vector2(-ent.y, ent.x)
	var hall_pos := c - ent * (R * 0.18)
	_put(root, "buildings/temple_hall", hall_pos, _face(ent), 7.0, 1.0, 1400.0)
	var pag := c + side * (R * 0.52) - ent * (R * 0.2)
	_put(root, "buildings/pagoda", pag, _face(ent), 4.5, 1.0, 1800.0)
	# the path: torii at the gate, stone lanterns in pairs up to the stairs
	var gate := c + ent * (R * 0.82)
	_put(root, "buildings/torii", gate, _face(ent), 0.5, 1.2, 900.0)
	for k in 4:
		var t := lerpf(0.7, 0.05, k / 3.0)
		var lp := c + ent * (R * t)
		for s in [-1, 1]:
			var sl := _put(root, "props/stone_lantern", lp + side * 2.6 * s, _face(side * -s), 0.4)
			if sl and k % 2 == 0:
				_lantern_light(root, sl.position + Vector3(0, 1.25, 0), 0.8, 5.0)
	for k in 6:
		_put(root, "props/jizo", pag + ent * 5.5 + side * (k - 2.5) * 0.8, _face(ent), 0.3)
	var altar := hall_pos + ent * 9.5
	_interactable(root, p, "shrine", "Orar no templo", altar)


# ------------------------------------------------------------------ shrines

func _shrine(root: Node3D, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := _center(p)
	var ent := _entrance_dir(p)
	var side := Vector2(-ent.y, ent.x)
	_put(root, "buildings/hokora", c, _face(ent), 0.8, 1.0, 600.0)
	_put(root, "buildings/torii" if rng.randf() < 0.7 else "buildings/torii_wood", c + ent * 5.0, _face(ent), 0.5, 0.75, 900.0)
	for s in [-1, 1]:
		var sl := _put(root, "props/stone_lantern", c + ent * 1.6 + side * 1.6 * s, _face(ent), 0.4)
		if sl:
			_lantern_light(root, sl.position + Vector3(0, 1.25, 0), 0.7, 4.5)
	_put(root, "props/jizo", c + side * 2.4 - ent * 0.4, _face(ent), 0.3)
	_put(root, "props/sake_jar", c + ent * 1.0 + side * 0.5, 0.0, 0.2)
	_interactable(root, p, "shrine", "Orar no santuário", c + ent * 1.4)


# ------------------------------------------------------------------ onsen

func _onsen(root: Node3D, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := _center(p)
	var ent := _entrance_dir(p)
	var side := Vector2(-ent.y, ent.x)
	var ring := _put(root, "props/onsen_ring", c, rng.randf() * TAU, 3.5)
	var world := Game.world as World
	if world and world.water and ring:
		world.water.make_pool(ring.position + Vector3(0, 0.32, 0), 4.2, 0.65)
	# steam
	var steam := GPUParticles3D.new()
	steam.amount = 24
	steam.lifetime = 6.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.0, 0.1, 3.0)
	pm.direction = Vector3.UP
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.1, 0.12, 0.0)
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(1, 2.5))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.22))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	steam.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/fx/smoke.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.95, 0.95, 0.95, 0.6)
	q.material = m
	steam.draw_pass_1 = q
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	steam.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
	if ring:
		steam.position = ring.position + Vector3(0, 0.4, 0)
	root.add_child(steam)
	for k in 3:
		var fp := c - ent * 6.2 + side * (k - 1) * 4.2
		_put(root, "buildings/bamboo_fence", fp, _along(side), 1.5)
	var sl := _put(root, "props/stone_lantern", c + ent * 5.2 + side * 2.0, _face(ent), 0.4)
	if sl:
		_lantern_light(root, sl.position + Vector3(0, 1.25, 0), 0.8, 5.0)
	_interactable(root, p, "onsen", "Banhar-se na fonte termal", c + ent * 4.6)


# ------------------------------------------------------------------ haiku

func _haiku(root: Node3D, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := _center(p)
	# face the widest view: the direction where the ground falls away most
	var best := Vector2(0, 1)
	var low := INF
	for k in 16:
		var a := TAU * k / 16.0
		var d := Vector2(cos(a), sin(a))
		var h := data.get_height(c.x + d.x * 60.0, c.y + d.y * 60.0)
		if h < low:
			low = h
			best = d
	var side := Vector2(-best.y, best.x)
	_put(root, "props/bench", c, _along(side), 0.6)
	_put(root, "props/stone_lantern", c + side * 1.8, _face(best), 0.4)
	_put(root, "props/sake_jar", c - side * 1.1 + best * 0.3, 0.0, 0.2)
	_interactable(root, p, "haiku", "Compor um haiku", c - best * 0.8)


# ------------------------------------------------------------------ sacred tree

func _landmark(root: Node3D, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := _center(p)
	var ent := _entrance_dir(p)
	var side := Vector2(-ent.y, ent.x)
	var s := 2.3
	var tree := _put(root, "trees/maple_0", c, rng.randf() * TAU, 0.0, s, 3000.0)
	if tree:
		for lod in ["lod1", "lod2"]:
			var n := tree.get_node_or_null(lod)
			if n:
				n.queue_free()
		# trunk collision
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.22 * s * 1.1
		cap.height = 5.0 * s
		cs.shape = cap
		cs.position = Vector3(0, cap.height * 0.5, 0)
		body.add_child(cs)
		tree.add_child(body)
		var rope := _put(root, "props/shimenawa", c, 0.0, 0.0, 0.22 * s * 1.25)
		if rope:
			rope.position.y += 1.7
	for k in [-1, 1]:
		var sl := _put(root, "props/stone_lantern", c + ent * 4.0 + side * 2.2 * k, _face(ent), 0.4)
		if sl:
			_lantern_light(root, sl.position + Vector3(0, 1.25, 0), 0.9, 5.0)
	_put(root, "props/jizo", c + ent * 2.6 - side * 3.2, _face(ent), 0.3)
	_put(root, "props/jizo", c + ent * 2.6 - side * 3.9, _face(ent), 0.3)
	_interactable(root, p, "landmark", "Meditar sob a árvore", c + ent * 2.6)


# ------------------------------------------------------------------ lights

func _process(delta: float) -> void:
	_light_timer -= delta
	if _light_timer > 0.0:
		return
	_light_timer = 0.5
	var world := Game.world as World
	var night := 0.0
	if world and world.time_of_day:
		night = 1.0 - clampf(world.time_of_day.daylight() * 1.6, 0.0, 1.0)
	for l in lights:
		l.light_energy = float(l.get_meta("energy", 1.0)) * night
		l.visible = night > 0.02
