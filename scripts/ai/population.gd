class_name Population
extends Node3D
## Streams enemies in and out around the player: camps spawn when the
## player gets near and remember how many defenders are left; patrols walk
## the roads. Far characters switch to a cheap kinematic body.

const SPAWN_DIST := 135.0
const DESPAWN_DIST := 210.0
const PHYSICS_LOD := 48.0
const SLEEP_LOD := 120.0

var data: WorldData
var camps := {}        # id -> {poi, enc, alive, cleared}
var patrol: Encounter = null
var _patrol_timer := 20.0
var _lod_timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(world_data: WorldData) -> void:
	data = world_data
	_rng.seed = 911
	for p in data.pois:
		if p.type == "camp":
			var id: String = p.id
			camps[id] = {"poi": p, "enc": null, "alive": -1, "cleared": SaveGame.has("cleared_camps", id)}


func camp_count() -> int:
	return camps.size()


func cleared_count() -> int:
	var n := 0
	for c in camps.values():
		if c.cleared:
			n += 1
	return n


func nearest_uncleared(from: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for c in camps.values():
		if c.cleared:
			continue
		var p: Dictionary = c.poi
		var d := Vector2(float(p.x) - from.x, float(p.z) - from.z).length()
		if d < bd:
			bd = d
			best = p
	return best


func _process(delta: float) -> void:
	var player := Game.player as Player
	if player == null or data == null:
		return
	var pp := player.global_position
	for id in camps:
		var c: Dictionary = camps[id]
		if c.cleared:
			continue
		var p: Dictionary = c.poi
		var d := Vector2(float(p.x) - pp.x, float(p.z) - pp.z).length()
		if c.enc == null and d < SPAWN_DIST and c.alive != 0:
			c.enc = _spawn_camp(p, int(c.alive))
		elif c.enc != null and d > DESPAWN_DIST and not (c.enc as Encounter).alerted:
			c.alive = (c.enc as Encounter).alive().size()
			(c.enc as Encounter).queue_free()
			c.enc = null
	_update_patrol(delta, pp)
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.5
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if en == null or en.dead:
				continue
			var dist := en.global_position.distance_to(pp)
			en.body.set_kinematic(dist > PHYSICS_LOD and en.state != Enemy.State.COMBAT)
			en.process_mode = Node.PROCESS_MODE_DISABLED if dist > SLEEP_LOD and en.state != Enemy.State.COMBAT else Node.PROCESS_MODE_INHERIT


func _on_camp_cleared(enc: Encounter) -> void:
	var c: Dictionary = camps.get(enc.id, {})
	if c.is_empty():
		return
	c.cleared = true
	c.alive = 0
	SaveGame.mark("cleared_camps", enc.id)
	Game.camp_cleared.emit(enc.id)
	Game.show_banner("ACAMPAMENTO LIBERTADO", String(enc.poi.get("name", "")), "victory")
	Audio.play("victory_sting", 0.0)
	var player := Game.player as Player
	if player:
		player.add_resolve_charge(1.0)


func _spawn_camp(p: Dictionary, alive_count: int) -> Encounter:
	var enc := Encounter.new()
	enc.id = p.id
	enc.poi = p
	enc.kind = "camp"
	add_child(enc)
	var c := Vector3(float(p.x), 0.0, float(p.z))
	c.y = data.get_height(c.x, c.z)
	enc.global_position = c
	enc.cleared.connect(_on_camp_cleared)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p.id)
	var count := rng.randi_range(4, 7)
	if alive_count > 0:
		count = mini(count, alive_count)
	var big := count >= 6
	for i in count:
		var style := "ronin"
		var r := rng.randf()
		if i == 0 and big:
			style = "leader"
		elif r < 0.22:
			style = "spearman"
		elif r < 0.34:
			style = "brute"
		var e := Enemy.new()
		e.style = style
		e.seed = rng.randi()
		# layout: around the fire, guards on the perimeter, one patrolling
		var ang := TAU * float(i) / count + rng.randf_range(-0.3, 0.3)
		var rad := 3.0
		var mode := "fire"
		if i % 3 == 1:
			mode = "guard"
			rad = float(p.get("radius", 20.0)) * 0.7
		elif i % 3 == 2 and i > 2:
			mode = "patrol"
			rad = float(p.get("radius", 20.0)) * 0.5
		elif rng.randf() < 0.5:
			mode = "sit"
			rad = 2.6
		var pos := c + Vector3(cos(ang), 0.0, sin(ang)) * rad
		pos.y = data.get_height(pos.x, pos.z) + 0.05
		e.position = pos
		var face := (c - pos) if mode in ["fire", "sit"] else (pos - c)
		face.y = 0.0
		e.rotation.y = atan2(-face.x, -face.z)
		e.idle_mode = mode
		if mode == "patrol":
			for k in 6:
				var a2 := ang + k * TAU / 6.0
				var q := c + Vector3(cos(a2), 0.0, sin(a2)) * rad
				q.y = data.get_height(q.x, q.z)
				e.patrol_points.append(q)
		enc.add_child(e)
		enc.add_enemy(e)
	return enc


func _update_patrol(delta: float, pp: Vector3) -> void:
	if patrol != null:
		if not is_instance_valid(patrol):
			patrol = null
			return
		var alive := patrol.alive()
		var far := true
		for e in alive:
			if e.global_position.distance_to(pp) < DESPAWN_DIST:
				far = false
		if alive.is_empty() or (far and not patrol.alerted):
			patrol.queue_free()
			patrol = null
			_patrol_timer = _rng.randf_range(40.0, 90.0)
		return
	_patrol_timer -= delta
	if _patrol_timer > 0.0 or data.roads.is_empty():
		return
	_patrol_timer = 15.0
	# pick a road point 90-160 m away from the player
	for attempt in 12:
		var road: Dictionary = data.roads[_rng.randi() % data.roads.size()]
		var pts: Array = road.points
		if pts.size() < 4:
			continue
		var i := _rng.randi_range(0, pts.size() - 4)
		var start := Vector3(float(pts[i][0]), 0.0, float(pts[i][1]))
		var d := Vector2(start.x - pp.x, start.z - pp.z).length()
		if d < 90.0 or d > 160.0:
			continue
		var enc := Encounter.new()
		enc.kind = "patrol"
		enc.id = "patrol"
		add_child(enc)
		enc.global_position = start
		var route: Array[Vector3] = []
		for k in range(i, mini(i + 40, pts.size())):
			var q := Vector3(float(pts[k][0]), 0.0, float(pts[k][1]))
			q.y = data.get_height(q.x, q.z)
			route.append(q)
		var n := _rng.randi_range(2, 3)
		for m in n:
			var e := Enemy.new()
			e.style = "ronin" if m > 0 or _rng.randf() < 0.6 else "spearman"
			e.seed = _rng.randi()
			var pos := start + Vector3(m * 1.3, 0.0, m * 0.8)
			pos.y = data.get_height(pos.x, pos.z) + 0.05
			e.position = pos
			e.idle_mode = "patrol"
			e.patrol_points = route.duplicate()
			enc.add_child(e)
			enc.add_enemy(e)
		patrol = enc
		return
