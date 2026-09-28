extends SceneTree
## Loads every GDScript under res://scripts to surface parse/compile errors.
## godot --headless --path . --script res://tests/check_scripts.gd

var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_check()
	return false


func _check() -> void:
	var files: Array[String] = []
	_walk("res://scripts", files)
	var bad := 0
	for f in files:
		var s: Script = load(f)
		if s == null or not s.can_instantiate():
			print("FAILED: ", f)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	quit(1 if bad > 0 else 0)


func _walk(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), out)
