class_name PauseMenu
extends MenuPanel
## Pause: resume, map, options, save and quit to title.

signal resume
signal open_map
signal open_options
signal quit_to_title

var progress: Label


func _ready() -> void:
	title_label.text = "Pausa"
	add_button("Continuar", func() -> void: resume.emit())
	add_button("Mapa", func() -> void: open_map.emit())
	add_button("Opções", func() -> void: open_options.emit())
	add_button("Salvar jogo", func() -> void:
		var p := Game.get_player()
		if p:
			SaveGame.data["player_pos"] = {"x": p.global_position.x, "z": p.global_position.z}
		var w := Game.world as World
		if w and w.time_of_day:
			SaveGame.data["time_of_day"] = w.time_of_day.time
		SaveGame.save_game()
		Game.show_toast("Jogo salvo"))
	add_button("Menu principal", func() -> void: quit_to_title.emit())
	add_button("Sair do jogo", func() -> void: get_tree().quit())
	progress = UIKit.label("", 22, "regular", Color(0.9, 0.86, 0.78), 5)
	UIKit.anchor(progress, Control.PRESET_BOTTOM_LEFT, 114, -150, 900, -30)
	add_child(progress)


func open() -> void:
	super.open()
	var w := Game.world as World
	var lines := PackedStringArray()
	if w and w.population:
		lines.append("Acampamentos libertados: %d / %d" % [w.population.cleared_count(), w.population.camp_count()])
	var d := WorldData.current
	if d:
		var disc := 0
		for p in d.pois:
			if SaveGame.has("discovered", String(p.id)):
				disc += 1
		lines.append("Locais descobertos: %d / %d" % [disc, d.pois.size()])
	lines.append("Inimigos derrotados: %d   ·   Desmembramentos: %d" % [int(SaveGame.data.get("kills", 0)), int(SaveGame.data.get("dismemberments", 0))])
	progress.text = "\n".join(lines)
