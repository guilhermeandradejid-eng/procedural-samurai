class_name MapScreen
extends Control
## The painted parchment map: places (undiscovered ones as ink question
## marks), liberated camps struck out in red, the player's arrow, region
## names and a chosen destination that the Guiding Wind will point to.

signal closed

var map_rect: TextureRect
var marker_layer: Control
var info: Label
var zoom := 1.0
var pan := Vector2.ZERO
var _drag := false
var _hover := {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var bg := UIKit.backdrop(0.85)
	add_child(bg)
	map_rect = TextureRect.new()
	map_rect.texture = load("res://assets/world/map.png")
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_rect)
	marker_layer = Markers.new()
	(marker_layer as Markers).screen = self
	marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marker_layer)
	var title := UIKit.label("Mapa de Ezo", 48, "title", UIKit.BONE, 8)
	title.position = Vector2(40, 24)
	add_child(title)
	info = UIKit.label("Clique num local para seguir o Vento Guia  ·  Roda: zoom  ·  Arrastar: mover  ·  M/Esc: fechar", 20, "italic")
	UIKit.anchor(info, Control.PRESET_CENTER_BOTTOM, -560, -58, 560, -24)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(info)


func open() -> void:
	visible = true
	zoom = 1.0
	pan = Vector2.ZERO
	var p := Game.get_player()
	if p:
		# centre on the player
		pan = -(_world_to_map01(p.global_position) - Vector2(0.5, 0.5)) * _map_size()
	_layout()
	Audio.play("map_open", -6.0)


func close() -> void:
	visible = false
	closed.emit()


func _map_size() -> float:
	var vs := get_viewport_rect().size
	return minf(vs.x, vs.y) * 0.92 * zoom


func _layout() -> void:
	var vs := get_viewport_rect().size
	var s := _map_size()
	map_rect.size = Vector2(s, s)
	map_rect.position = vs * 0.5 - Vector2(s, s) * 0.5 + pan
	marker_layer.queue_redraw()


func _world_to_map01(p: Vector3) -> Vector2:
	var d := WorldData.current
	if d == null:
		return Vector2(0.5, 0.5)
	var half_px := (d.size - 1) * 0.5
	return Vector2((p.x / d.spacing + half_px) / d.size, (p.z / d.spacing + half_px) / d.size)


func world_to_screen(p: Vector3) -> Vector2:
	return map_rect.position + _world_to_map01(p) * map_rect.size


func _gui_input(_e: InputEvent) -> void:
	pass


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("map") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_hover = _poi_at(mb.position)
			else:
				_drag = false
				if not _hover.is_empty() and _hover == _poi_at(mb.position):
					_set_destination(_hover)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag:
		pan += (event as InputEventMouseMotion).relative
		_layout()
		get_viewport().set_input_as_handled()


func _zoom_at(at: Vector2, f: float) -> void:
	var old := zoom
	zoom = clampf(zoom * f, 1.0, 4.0)
	var vs := get_viewport_rect().size
	var rel := at - (vs * 0.5 + pan)
	pan -= rel * (zoom / old - 1.0)
	_layout()


func _poi_at(pos: Vector2) -> Dictionary:
	var d := WorldData.current
	if d == null:
		return {}
	for p in d.pois:
		var sp := world_to_screen(Vector3(float(p.x), 0, float(p.z)))
		if sp.distance_to(pos) < 18.0:
			return p
	return {}


func _set_destination(p: Dictionary) -> void:
	SaveGame.data["destination"] = String(p.id)
	Game.show_toast("Destino: " + String(p.get("name", p.type)))
	Audio.play("ui_select", -6.0)
	marker_layer.queue_redraw()


func _process(_d: float) -> void:
	if visible:
		marker_layer.queue_redraw()


class Markers extends Control:
	var screen: MapScreen

	func _draw() -> void:
		var d := WorldData.current
		if d == null:
			return
		var font := UIKit.font("title")
		var small := UIKit.font("bold")
		# region names
		for r in d.regions:
			var sp := screen.world_to_screen(Vector3(float(r.x), 0, float(r.z)))
			var txt := String(r.name)
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_string(font, sp - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.2, 0.15, 0.12, 0.55))
		var dest := String(SaveGame.data.get("destination", ""))
		for p in d.pois:
			var sp := screen.world_to_screen(Vector3(float(p.x), 0, float(p.z)))
			var discovered := SaveGame.has("discovered", String(p.id))
			var idx: int = UIKit.ICON_INDEX.get(String(p.type), 0)
			var sz := 30.0
			var col := Color(0.12, 0.09, 0.08, 0.95) if discovered else Color(0.25, 0.2, 0.18, 0.45)
			if String(p.type) == "camp" and not SaveGame.has("cleared_camps", String(p.id)):
				col = Color(0.55, 0.08, 0.05, 0.95) if discovered else col
			draw_texture_rect_region(load("res://assets/textures/ui/icons.png"), Rect2(sp - Vector2(sz, sz) * 0.5, Vector2(sz, sz)),
				Rect2(idx * 128, 0, 128, 128), col)
			if not discovered:
				draw_string(small, sp + Vector2(10, -8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.2, 0.15, 0.12, 0.8))
			elif String(p.type) == "camp" and SaveGame.has("cleared_camps", String(p.id)):
				draw_line(sp + Vector2(-14, -14), sp + Vector2(14, 14), UIKit.RED, 4.0, true)
				draw_line(sp + Vector2(14, -14), sp + Vector2(-14, 14), UIKit.RED, 4.0, true)
			if discovered:
				var nm := String(p.get("name", ""))
				draw_string(small, sp + Vector2(-60, 30), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(0.15, 0.1, 0.08, 0.85))
			if String(p.id) == dest:
				var t := float(Time.get_ticks_msec() % 1200) / 1200.0
				draw_arc(sp, 20.0 + t * 10.0, 0.0, TAU, 32, Color(UIKit.GOLD, 1.0 - t), 3.0, true)
		# player arrow
		var pl := Game.get_player()
		if pl:
			var sp := screen.world_to_screen(pl.global_position)
			var fwd := -pl.global_basis.z
			var a := atan2(fwd.z, fwd.x)
			var tip := sp + Vector2(cos(a), sin(a)) * 16.0
			var l := sp + Vector2(cos(a + 2.5), sin(a + 2.5)) * 11.0
			var r := sp + Vector2(cos(a - 2.5), sin(a - 2.5)) * 11.0
			draw_colored_polygon(PackedVector2Array([tip, l, sp, r]), UIKit.RED)
			draw_polyline(PackedVector2Array([tip, l, sp, r, tip]), Color(0, 0, 0, 0.8), 1.5, true)
