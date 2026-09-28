class_name Interactable
extends Node3D
## Something the player can use with the interact key: shrines, hot springs,
## haiku spots, the sacred tree. The HUD shows `prompt` when the player is
## within `radius`; Player calls interact().

signal used(it: Interactable)

var kind := "shrine"
var poi := {}
var prompt := "Interagir"
var radius := 2.6
var once := false


func _ready() -> void:
	add_to_group("interactables")


func is_available() -> bool:
	if once and SaveGame.has("used_" + kind, String(poi.get("id", name))):
		return false
	return true


func interact(player: Player) -> void:
	var id := String(poi.get("id", name))
	var first := not SaveGame.has("used_" + kind, id)
	match kind:
		"shrine":
			player.resolve = player.max_resolve
			if first:
				player.max_resolve += 1
				SaveGame.data["resolve_bonus"] = int(SaveGame.data.get("resolve_bonus", 0)) + 1
				Game.show_banner("SANTUÁRIO XINTOÍSTA", "Sua Determinação máxima aumentou", "reward")
			else:
				Game.show_banner("SANTUÁRIO XINTOÍSTA", "Sua Determinação foi restaurada", "info")
			player.resolve_changed.emit(player.resolve, player.resolve_charge)
			player.set_action("pray", 2.2)
			Audio.play("shrine_bell", -2.0)
		"onsen":
			player.heal(player.max_health)
			if first:
				player.max_health += 10.0
				player.health = player.max_health
				SaveGame.data["max_health_bonus"] = int(SaveGame.data.get("max_health_bonus", 0)) + 10
				Game.show_banner("FONTE TERMAL", _onsen_thought(), "reward")
			else:
				Game.show_banner("FONTE TERMAL", "Corpo e mente descansados", "info")
			player.set_action("kneel", 2.6)
			Audio.play("heal", -4.0)
		"haiku":
			var h := Haiku.compose(hash(id))
			Game.show_banner("HAIKU", h, "haiku")
			if first:
				player.add_resolve_charge(1.0)
			player.set_action("sit", 3.2)
		"landmark":
			var tod: TimeOfDay = (Game.world as World).time_of_day if Game.world else null
			if tod:
				# meditate until the next golden hour
				tod.time = 17.2 if tod.time < 12.0 or tod.time > 19.0 else 6.4
			SaveGame.data["respawn"] = {"x": player.global_position.x, "z": player.global_position.z}
			Game.show_banner(String(poi.get("name", "ÁRVORE SAGRADA")).to_upper(), "Você medita sob os galhos. O tempo passa.", "info")
			player.set_action("kneel", 3.0)
	SaveGame.mark("used_" + kind, id)
	SaveGame.save_game()
	used.emit(self)


func _onsen_thought() -> String:
	var lines := [
		"A água quente leva embora a dor da batalha.\nSua vida máxima aumentou.",
		"Vapor sobe como névoa sobre a montanha.\nSua vida máxima aumentou.",
		"Um samurai também precisa de silêncio.\nSua vida máxima aumentou.",
	]
	return lines[abs(hash(poi.get("id", ""))) % lines.size()]
