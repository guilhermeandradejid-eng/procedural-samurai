extends SceneTree
## Prints the node structure and bounds of model files (debug helper).

func _init() -> void:
	for dir in ["res://assets/models/trees", "res://assets/models/rocks", "res://assets/models/buildings", "res://assets/models/props"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".glb"):
				continue
			var ps: PackedScene = load(dir + "/" + f)
			var n := ps.instantiate()
			print(f)
			_dump(n, 1)
			n.free()
	quit()


func _dump(n: Node, depth: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		var ab := m.get_aabb()
		extra = " aabb pos=%s size=%s surf=%d" % [ab.position.snapped(Vector3.ONE * 0.01), ab.size.snapped(Vector3.ONE * 0.01), m.get_surface_count()]
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			extra += " [%s]" % (mat.resource_name if mat else "-")
	print("  ".repeat(depth), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_dump(c, depth + 1)
