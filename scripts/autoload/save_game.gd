extends Node
## Minimal persistent progress: cleared camps, discovered places, upgrades.

const PATH := "user://savegame.json"

var data := {
	"cleared_camps": [],
	"discovered": [],
	"prayed_shrines": [],
	"bathed_onsen": [],
	"haiku_done": [],
	"max_health_bonus": 0,
	"resolve_bonus": 0,
	"kills": 0,
	"standoff_kills": 0,
	"dismemberments": 0,
	"player_pos": null,
	"time_of_day": 16.8,
}


func _ready() -> void:
	load_game()


func has_save() -> bool:
	return FileAccess.file_exists(PATH)


func load_game() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		for k in parsed:
			data[k] = parsed[k]


func save_game() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, " "))


func reset() -> void:
	for k in ["cleared_camps", "discovered", "prayed_shrines", "bathed_onsen", "haiku_done"]:
		data[k] = []
	for k in data.keys():
		if String(k).begins_with("used_"):
			data[k] = []
	data.erase("respawn")
	data.max_health_bonus = 0
	data.resolve_bonus = 0
	data.kills = 0
	data.standoff_kills = 0
	data.dismemberments = 0
	data.player_pos = null
	data.time_of_day = 16.8
	save_game()


func mark(list_name: String, id: String) -> bool:
	var arr: Array = data.get(list_name, [])
	if id in arr:
		return false
	arr.append(id)
	data[list_name] = arr
	save_game()
	return true


func has(list_name: String, id: String) -> bool:
	return id in data.get(list_name, [])
