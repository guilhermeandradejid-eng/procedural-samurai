extends SceneTree
## Figures out which diagonal the physics heightfield uses per cell.
var world: World
var frames := 0

func tri_height(d: WorldData, x: float, z: float, diag: int) -> float:
	var g := d.grid_coord(x, z)
	var ix := int(g.x); var iz := int(g.y)
	var tx := g.x - ix; var tz := g.y - iz
	var n := d.size
	var a := d.heights[iz * n + ix]; var b := d.heights[iz * n + ix + 1]
	var c := d.heights[(iz + 1) * n + ix]; var e := d.heights[(iz + 1) * n + ix + 1]
	if diag == 0: # split along a-e (top-left to bottom-right)
		if tx >= tz:
			return a + (b - a) * tx + (e - b) * tz
		return a + (c - a) * tz + (e - c) * tx
	else: # split along b-c
		if tx + tz <= 1.0:
			return a + (b - a) * tx + (c - a) * tz
		return e + (c - e) * (1.0 - tx) + (b - e) * (1.0 - tz)

func _init() -> void:
	world = World.new()
	root.add_child(world)
	world.build()

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	var space := world.get_world_3d().direct_space_state
	var d := world.data
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var errs := [0.0, 0.0, 0.0]
	for i in 600:
		var x := rng.randf_range(-900, 900)
		var z := rng.randf_range(-900, 900)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 1000, z), Vector3(x, -200, z)))
		if hit.is_empty(): continue
		var y: float = hit.position.y
		errs[0] = max(errs[0], abs(y - tri_height(d, x, z, 0)))
		errs[1] = max(errs[1], abs(y - tri_height(d, x, z, 1)))
		errs[2] = max(errs[2], abs(y - d.get_height(x, z)))
	print("diag0 worst %.4f  diag1 worst %.4f  bilinear worst %.4f" % errs)
	quit()
	return true
