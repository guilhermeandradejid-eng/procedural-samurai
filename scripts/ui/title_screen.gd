class_name TitleScreen
extends MenuPanel
## Opening screen over a slow cinematic camera: the game's name in brush
## calligraphy, continue / new journey / options / quit.

signal start_game(new_game: bool)
signal open_options

var kanji: Label
var subtitle: Label
var hint: Label


func _ready() -> void:
	backdrop.color = Color(0, 0, 0, 0.22)
	title_label.text = ""
	column.position = Vector2(110, 420)
	kanji = UIKit.label("蝦夷の侍", 150, "kanji", UIKit.BONE, 0)
	kanji.position = Vector2(100, 90)
	add_child(kanji)
	var name_l := UIKit.label("O Samurai de Ezo", 64, "title", UIKit.BONE, 10)
	name_l.position = Vector2(110, 270)
	add_child(name_l)
	subtitle = UIKit.label("um jogo de espada procedural", 26, "italic", Color(0.9, 0.85, 0.75), 5)
	subtitle.position = Vector2(118, 350)
	add_child(subtitle)
	if SaveGame.has_save():
		add_button("Continuar jornada", func() -> void: start_game.emit(false))
	add_button("Nova jornada", func() -> void: start_game.emit(true))
	add_button("Opções", func() -> void: open_options.emit())
	add_button("Sair", func() -> void: get_tree().quit())
	hint = UIKit.label("F1 mostra os controles durante o jogo", 18, "regular", Color(0.9, 0.88, 0.8, 0.7), 4)
	UIKit.anchor(hint, Control.PRESET_BOTTOM_LEFT, 116, -64, 800, -34)
	add_child(hint)


func _process(delta: float) -> void:
	if not visible:
		return
	var rig := Game.camera_rig as CameraRig
	if rig:
		rig.yaw += delta * 0.045
		rig.pitch = lerpf(rig.pitch, -0.06, delta)
