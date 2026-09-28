extends SceneTree
## Verifies that the terrain collision matches WorldData heights.
var world: World
var frames := 0

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
	rng.seed = 3
	var worst := 0.0
	var misses := 0
	for i in 400:
		var x := rng.randf_range(-1000, 1000)
		var z := rng.randf_range(-1000, 1000)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 1000, z), Vector3(x, -200, z))
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			misses += 1
			continue
		var err: float = abs(hit.position.y - d.get_height(x, z))
		worst = max(worst, err)
	print("collision check: worst error %.3f m, misses %d/400" % [worst, misses])
	quit()
	return true
