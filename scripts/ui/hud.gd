class_name HUD
extends Control
## In-game interface: brush-stroke health bar with a lagging damage trail,
## Resolve stones, enemy awareness diamonds (on and off screen), lock-on
## mark, interaction prompt, banners, toasts, control help and debug stats.

var health_bar: TextureProgressBar
var health_trail: TextureProgressBar
var resolve_view: Control
var overlay: Control
var prompt: Label
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var banner_brush: TextureRect
var toast_box: VBoxContainer
var help: Label
var stats: Label
var detection := {}          # Enemy -> {value, time}
var _banner_queue: Array = []
var _banner_t := -1.0
var _banner_len := 4.0
var _trail := 1.0
var _trail_hold := 0.0
var _help_t := 45.0
var _last_hp := -1.0
var combo_label: Label
var _combo := 0
var _combo_t := 0.0
var kanji_label: Label
var _kanji_tw: Tween
var _interact: Interactable = null
var _assassin: Enemy = null
var _standoff_ok := false
var _standoff_hint_t := 0.0
var _vis := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# health + resolve (bottom left)
	var hb := Control.new()
	UIKit.anchor(hb, Control.PRESET_BOTTOM_LEFT, 48, -130, 448, -30)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	health_trail = _bar(Color(0.95, 0.85, 0.7, 0.85), Color(0.05, 0.04, 0.04, 0.55))
	health_bar = _bar(Color(0.78, 0.1, 0.08), Color(0, 0, 0, 0))
	hb.add_child(health_trail)
	hb.add_child(health_bar)
	resolve_view = ResolveView.new()
	resolve_view.position = Vector2(8, 48)
	resolve_view.size = Vector2(240, 40)
	hb.add_child(resolve_view)
	# overlay for world-space markers
	overlay = MarkerOverlay.new()
	overlay.hud = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	# interaction prompt
	prompt = UIKit.label("", 26, "bold")
	UIKit.anchor(prompt, Control.PRESET_CENTER_BOTTOM, -320, -190, 320, -150)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)
	# banner
	banner_box = VBoxContainer.new()
	UIKit.anchor(banner_box, Control.PRESET_CENTER_TOP, -520, 100, 520, 330)
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.add_theme_constant_override("separation", -6)
	add_child(banner_box)
	banner_title = UIKit.label("", 64, "title", UIKit.BONE, 10)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_title)
	var bc := CenterContainer.new()
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_brush = UIKit.brush(520, 34, UIKit.RED)
	bc.add_child(banner_brush)
	banner_box.add_child(bc)
	banner_sub = UIKit.label("", 28, "italic", UIKit.BONE, 6)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner_sub)
	banner_box.modulate.a = 0.0
	# toasts (bottom right)
	toast_box = VBoxContainer.new()
	UIKit.anchor(toast_box, Control.PRESET_BOTTOM_RIGHT, -540, -300, -40, -60)
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)
	# help and stats
	help = UIKit.label(_help_text(), 19, "regular", UIKit.BONE, 5)
	help.position = Vector2(40, 40)
	add_child(help)
	stats = UIKit.label("", 16, "regular", UIKit.BONE, 4)
	UIKit.anchor(stats, Control.PRESET_TOP_RIGHT, -340, 20, -20, 220)
	stats.visible = false
	add_child(stats)
	kanji_label = UIKit.label("", 240, "kanji", Color.WHITE, 0)
	kanji_label.set_anchors_preset(Control.PRESET_CENTER)
	UIKit.anchor(kanji_label, Control.PRESET_CENTER, -400, -230, 400, 60)
	kanji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kanji_label.pivot_offset = Vector2(400, 145)
	kanji_label.modulate.a = 0.0
	add_child(kanji_label)
	combo_label = UIKit.label("", 54, "title", Color(1.0, 0.85, 0.3), 10)
	UIKit.anchor(combo_label, Control.PRESET_TOP_RIGHT, -520, 150, -40, 230)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_label.pivot_offset = Vector2(480, 40)
	add_child(combo_label)
	Game.combo_hit.connect(func(_p: float) -> void:
		_combo += 1
		_combo_t = 3.2
		if _combo >= 2:
			combo_label.text = "%d GOLPES!" % _combo if _combo < 5 else "%d GOLPES!!" % _combo
			combo_label.scale = Vector2.ONE * 1.5
			combo_label.modulate = Color(1.0, 0.85 - minf(_combo * 0.06, 0.6), 0.3, 1.0)
			var tw := combo_label.create_tween()
			tw.tween_property(combo_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	Game.big_kanji.connect(show_kanji)
	Game.banner.connect(show_banner)
	Game.toast.connect(show_toast)
	Game.detection_changed.connect(func(e: Node, v: float) -> void:
		detection[e] = {"value": v, "time": Time.get_ticks_msec()})
	Settings.changed.connect(func(k: String) -> void:
		if k == "show_hud":
			visible = bool(Settings.get_value("show_hud", true)))


func _bar(fill: Color, back: Color) -> TextureProgressBar:
	var b := TextureProgressBar.new()
	b.texture_under = load("res://assets/textures/ui/brush_stroke.png")
	b.texture_progress = load("res://assets/textures/ui/brush_fill.png")
	b.nine_patch_stretch = true
	b.size = Vector2(380, 44)
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.value = 1.0
	b.tint_under = back
	b.tint_progress = fill
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _help_text() -> String:
	return "\n".join([
		"WASD  mover     Shift  correr     C  agachar     V  pular",
		"Botão esq.  golpe     E (segurar)  golpe carregado",
		"Botão dir.  bloquear (no tempo certo: aparar)     Espaço  esquivar",
		"Tab  travar alvo     R  curar (Determinação)     F  interagir",
		"T  Vento Guia     M  mapa     F3  modo Kurosawa     F1  ajuda",
	])


func show_banner(title: String, subtitle := "", style := "default") -> void:
	_banner_queue.append({"title": title, "sub": subtitle, "style": style})
	if _banner_t < 0.0:
		_next_banner()


func _next_banner() -> void:
	if _banner_queue.is_empty():
		_banner_t = -1.0
		return
	var b: Dictionary = _banner_queue.pop_front()
	banner_title.text = b.title
	banner_sub.text = b.sub
	var col := UIKit.RED
	match String(b.style):
		"reward":
			col = UIKit.GOLD
		"info", "location":
			col = Color(0.85, 0.82, 0.75, 0.8)
		"haiku":
			col = Color(0.2, 0.18, 0.16, 0.9)
		"death":
			col = UIKit.RED
	banner_brush.modulate = col
	banner_title.add_theme_font_size_override("font_size", 44 if b.style == "haiku" else (52 if b.style == "location" else 64))
	banner_sub.add_theme_font_size_override("font_size", 32 if b.style == "haiku" else 26)
	_banner_len = 8.5 if b.style == "haiku" else 4.2
	_banner_t = 0.0
	if b.style in ["victory", "reward"]:
		Audio.play("banner", -6.0)


func show_kanji(text: String, color: Color, duration: float) -> void:
	kanji_label.text = text
	kanji_label.add_theme_color_override("font_color", color)
	kanji_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	kanji_label.add_theme_constant_override("outline_size", 14)
	kanji_label.add_theme_font_size_override("font_size", 250 if text.length() == 1 else 190)
	if _kanji_tw:
		_kanji_tw.kill()
	kanji_label.modulate.a = 1.0
	kanji_label.scale = Vector2.ONE * 1.7
	kanji_label.rotation = randf_range(-0.06, 0.06)
	_kanji_tw = create_tween().set_parallel(true)
	_kanji_tw.tween_property(kanji_label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_kanji_tw.tween_property(kanji_label, "modulate:a", 0.0, 0.35).set_delay(maxf(duration - 0.35, 0.2))


func show_toast(text: String) -> void:
	var l := UIKit.label(text, 22, "medium")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toast_box.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(3.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).queue_free()
		break


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		help.visible = not help.visible
		_help_t = 9999.0
	elif event.is_action_pressed("debug_stats"):
		stats.visible = not stats.visible


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	var p := Game.get_player()
	var playing := Game.is_playing()
	_vis = move_toward(_vis, 1.0 if playing or Game.state == Game.State.DEAD else 0.0, real * 3.0)
	modulate.a = _vis
	if p:
		var hp := clampf(p.health / p.max_health, 0.0, 1.0)
		health_bar.value = hp
		if hp < _last_hp:
			_trail_hold = 0.7
		_trail_hold -= real
		if hp < _trail:
			if _trail_hold <= 0.0:
				_trail = move_toward(_trail, hp, real * 0.35)
		else:
			_trail = hp
		health_trail.value = _trail
		_last_hp = hp
		(resolve_view as ResolveView).player = p
		resolve_view.queue_redraw()
		_standoff_hint_t -= real
		_update_prompt(p)
	# combo counter fades when the streak ends
	if _combo_t > 0.0:
		_combo_t -= real
		if _combo_t <= 0.0:
			_combo = 0
		elif _combo_t < 0.6:
			combo_label.modulate.a = _combo_t / 0.6
	elif combo_label.text != "":
		combo_label.text = ""
	# banners
	if _banner_t >= 0.0:
		_banner_t += real
		var a := smoothstep(0.0, 0.5, _banner_t) * (1.0 - smoothstep(_banner_len - 0.8, _banner_len, _banner_t))
		banner_box.modulate.a = a
		banner_brush.scale = Vector2(smoothstep(0.1, 0.7, _banner_t), 1.0)
		banner_brush.pivot_offset = banner_brush.size * 0.5
		if _banner_t >= _banner_len:
			banner_box.modulate.a = 0.0
			_next_banner()
	# help fades after a while
	if _help_t < 9000.0 and playing:
		_help_t -= real
		help.modulate.a = clampf(_help_t / 3.0, 0.0, 1.0)
		if _help_t <= 0.0:
			help.visible = false
			_help_t = 9999.0
	if stats.visible:
		_update_stats(p)
	overlay.queue_redraw()


func _update_prompt(p: Player) -> void:
	_interact = null
	_assassin = null
	if p.dead or not Game.is_playing() or not p.input_enabled:
		prompt.text = ""
		return
	var at := p.assassination_target()
	if at:
		_assassin = at
		prompt.text = "[%s]  Assassinar" % key_name("interact")
		return
	if p.combat:
		prompt.text = ""
		return
	if _standoff_hint_t <= 0.0:
		_standoff_hint_t = 0.5
		_standoff_ok = false
		var cands := p.standoff_candidates()
		if not cands.is_empty():
			var aware := false
			for e in cands:
				if e.state != Enemy.State.IDLE and e.global_position.distance_to(p.global_position) < 20.0:
					aware = true
			_standoff_ok = aware or cands[0].global_position.distance_to(p.global_position) < 14.0
	if _standoff_ok:
		prompt.text = "[%s]  Desafiar para um confronto" % key_name("standoff")
		return
	var best: Interactable = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it == null or not it.is_available():
			continue
		var d := it.global_position.distance_to(p.global_position)
		if d < it.radius and d < bd:
			bd = d
			best = it
	_interact = best
	if best:
		prompt.text = "[%s]  %s" % [key_name("interact"), best.prompt]
	else:
		prompt.text = ""


func current_interactable() -> Interactable:
	return _interact


func current_assassination() -> Enemy:
	return _assassin if is_instance_valid(_assassin) else null


static func key_name(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return "?"


func _update_stats(p: Player) -> void:
	var lines := PackedStringArray()
	lines.append("FPS %d   (%.1f ms)" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1)])
	lines.append("draw calls %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	lines.append("primitivas %dk" % (RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000))
	lines.append("inimigos ativos %d" % get_tree().get_nodes_in_group("enemies").size())
	var world := Game.world as World
	if world and world.time_of_day:
		lines.append("hora %.1f" % world.time_of_day.time)
	if p:
		lines.append("pos %.0f, %.0f, %.0f" % [p.global_position.x, p.global_position.y, p.global_position.z])
	stats.text = "\n".join(lines)


# ------------------------------------------------------------------ widgets

class ResolveView extends Control:
	var player: Player

	func _draw() -> void:
		if player == null:
			return
		var n := player.max_resolve
		for i in n:
			var c := Vector2(14 + i * 34, 14)
			var pts := PackedVector2Array([c + Vector2(0, -12), c + Vector2(11, 0), c + Vector2(0, 12), c + Vector2(-11, 0)])
			draw_colored_polygon(pts, Color(0, 0, 0, 0.45))
			var fill := 1.0 if i < player.resolve else (player.resolve_charge if i == player.resolve else 0.0)
			if fill > 0.0:
				var s := 0.25 + 0.75 * fill
				var inner := PackedVector2Array([c + Vector2(0, -9) * s, c + Vector2(8, 0) * s, c + Vector2(0, 9) * s, c + Vector2(-8, 0) * s])
				draw_colored_polygon(inner, UIKit.GOLD if fill >= 1.0 else Color(0.9, 0.85, 0.7, 0.6))
			pts.append(pts[0])
			draw_polyline(pts, Color(0.95, 0.9, 0.8, 0.8), 1.5, true)
		# posture: a thin bar that empties as guard is worn down
		var pf := clampf(player.guard / player.max_guard, 0.0, 1.0)
		draw_rect(Rect2(4, 36, 240, 5), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(4, 36, 240.0 * pf, 5), Color(0.92, 0.88, 0.75) if pf > 0.35 else UIKit.RED)


class MarkerOverlay extends Control:
	var hud: HUD

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		var p := Game.get_player()
		if cam == null or p == null or not Game.is_playing():
			return
		var now := Time.get_ticks_msec()
		var vs := get_viewport_rect().size
		for e in hud.detection.keys():
			if not is_instance_valid(e):
				hud.detection.erase(e)
				continue
			var en := e as Enemy
			var d: Dictionary = hud.detection[e]
			if en.dead or now - int(d.time) > 1500 or float(d.value) <= 0.01:
				hud.detection.erase(e)
				continue
			if en.state == Enemy.State.COMBAT and now - int(d.time) > 400:
				continue
			var v: float = d.value
			var col := Color(1, 1, 1, 0.9).lerp(Color(1.0, 0.8, 0.2), smoothstep(0.3, 0.7, v)).lerp(UIKit.RED, smoothstep(0.75, 1.0, v))
			var head := en.global_position + Vector3(0, (Rig.height() + 0.35) * en.scale_factor, 0)
			var behind := cam.is_position_behind(head)
			var sp := cam.unproject_position(head)
			var margin := 40.0
			if behind or sp.x < margin or sp.y < margin or sp.x > vs.x - margin or sp.y > vs.y - margin:
				# off-screen: arrow on a ring around the centre
				var dir := sp - vs * 0.5
				if behind:
					dir = -dir
				var a := dir.angle()
				var r := minf(vs.x, vs.y) * 0.36
				var c := vs * 0.5 + Vector2(cos(a), sin(a)) * r
				var tip := c + Vector2(cos(a), sin(a)) * 16.0
				var l := c + Vector2(cos(a + 2.4), sin(a + 2.4)) * 12.0
				var rr := c + Vector2(cos(a - 2.4), sin(a - 2.4)) * 12.0
				draw_colored_polygon(PackedVector2Array([tip, l, rr]), Color(col, 0.35 + v * 0.6))
			else:
				_diamond(sp, 11.0, col, v)
		# Sekiro-style posture bars over enemies that are fighting
		for e in hud.get_tree().get_nodes_in_group("enemies"):
			var pe := e as Enemy
			if pe == null or pe.dead or pe.state != Enemy.State.COMBAT:
				continue
			var hp := pe.global_position + Vector3(0, (Rig.height() + 0.25) * pe.scale_factor, 0)
			if cam.is_position_behind(hp) or hp.distance_to(cam.global_position) > 28.0:
				continue
			var sp3 := cam.unproject_position(hp)
			var frac := clampf(1.0 - pe.guard / pe.max_guard, 0.0, 1.0)
			if frac < 0.05 and pe.posture_broken <= 0.0:
				continue
			var w := 56.0
			var half := w * 0.5 * frac
			var broken := pe.posture_broken > 0.0
			var pcol := UIKit.RED if (frac > 0.7 or broken) else Color(0.95, 0.9, 0.8)
			if broken and int(Time.get_ticks_msec() / 90) % 2 == 0:
				pcol = Color(1.0, 0.75, 0.2)
			draw_rect(Rect2(sp3 - Vector2(w * 0.5, 3), Vector2(w, 6)), Color(0, 0, 0, 0.45))
			draw_rect(Rect2(sp3 - Vector2(half, 2), Vector2(half * 2.0, 4)), pcol)
			draw_rect(Rect2(sp3 - Vector2(w * 0.5, 3), Vector2(w, 6)), Color(1, 1, 1, 0.5), false, 1.0)
		# lock-on mark
		if p.lock_target and is_instance_valid(p.lock_target) and not p.lock_target.dead:
			var ch := p.lock_target.chest_position()
			if not cam.is_position_behind(ch):
				var sp2 := cam.unproject_position(ch)
				var t := float(now % 1000) / 1000.0
				var s := 9.0 + sin(t * TAU) * 1.5
				for k in 4:
					var a2 := k * PI * 0.5 + PI * 0.25
					var o := Vector2(cos(a2), sin(a2)) * s * 1.8
					draw_line(sp2 + o, sp2 + o * 1.5, UIKit.RED, 2.5, true)

	func _diamond(c: Vector2, r: float, col: Color, fill: float) -> void:
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.75, 0), c + Vector2(0, r), c + Vector2(-r * 0.75, 0)])
		draw_colored_polygon(pts, Color(0, 0, 0, 0.35))
		# fill from the bottom up
		var h := r * 2.0 * clampf(fill, 0.0, 1.0)
		var y0 := c.y + r - h
		var clip := PackedVector2Array()
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			if a.y >= y0:
				clip.append(a)
			if (a.y >= y0) != (b.y >= y0):
				var t := (y0 - a.y) / (b.y - a.y)
				clip.append(a.lerp(b, t))
		if clip.size() >= 3:
			draw_colored_polygon(clip, col)
		pts.append(pts[0])
		draw_polyline(pts, Color(col, 1.0), 1.6, true)
