extends Node3D
## Entry point: builds the world, spawns the player and the UI.
## Command line (after `--`):  --tour <dir>   capture screenshots and quit

var world: World


func _ready() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	Game.world = world
	world.build()
	var args := OS.get_cmdline_user_args()
	var ti := args.find("--tour")
	if ti >= 0:
		var tour := preload("res://scripts/debug/shot_tour.gd").new()
		tour.out_dir = args[ti + 1] if ti + 1 < args.size() else "user://shots"
		var vi := args.find("--views")
		if vi >= 0 and vi + 1 < args.size():
			tour.only = args[vi + 1].split(",")
		add_child(tour)
