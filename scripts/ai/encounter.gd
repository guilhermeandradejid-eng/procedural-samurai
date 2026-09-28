class_name Encounter
extends Node3D
## A group of enemies (a camp or a road patrol) that shares its alert state
## and hands out attack tokens so only a couple of foes attack at once,
## like the duels of Ghost of Tsushima. Brutal kills can terrify the rest.

signal cleared(enc: Encounter)
signal combat_started(enc: Encounter)
signal combat_ended(enc: Encounter)

var id := ""
var poi := {}
var kind := "camp"
var enemies: Array[Enemy] = []
var alerted := false
var max_tokens := 2
var cleared_flag := false
var _token_timer := 0.0
var _calm_timer := 0.0


func add_enemy(e: Enemy) -> void:
	enemies.append(e)
	e.encounter = self
	e.alerted.connect(_on_alerted)
	e.died.connect(_on_died)


func alive() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			out.append(e)
	return out


func center() -> Vector3:
	return global_position


func _on_alerted(e: Enemy) -> void:
	if not alerted:
		alerted = true
		combat_started.emit(self)
	for o in alive():
		if o != e and o.global_position.distance_to(e.global_position) < 45.0:
			var delay := randf_range(0.2, 1.0)
			get_tree().create_timer(delay).timeout.connect(func() -> void:
				if is_instance_valid(o) and not o.dead:
					o.become_aware(false))


func _on_died(ch: Character, info: Dictionary) -> void:
	var brutal: bool = ch.body.severed.size() > 0 or info.get("attack", "") in ["iai", "assassinate"]
	if brutal:
		for o in alive():
			if o.global_position.distance_to(ch.global_position) < 11.0 and randf() < 0.3:
				o.terrify(randf_range(4.0, 7.0))
	if alive().is_empty() and not cleared_flag:
		cleared_flag = true
		get_tree().create_timer(1.5).timeout.connect(func() -> void: cleared.emit(self))


func on_attack(_e: Enemy) -> void:
	pass


func _physics_process(delta: float) -> void:
	var player := Game.player as Player
	if player == null:
		return
	_token_timer -= delta
	if _token_timer > 0.0:
		return
	_token_timer = 0.25
	var fighters: Array[Enemy] = []
	for e in alive():
		if e.state == Enemy.State.COMBAT:
			fighters.append(e)
	if fighters.is_empty():
		if alerted:
			_calm_timer += 0.25
			if _calm_timer > 8.0:
				alerted = false
				combat_ended.emit(self)
		return
	_calm_timer = 0.0
	fighters.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
	var budget := max_tokens
	for e in fighters:
		var cost := 2 if e.style in ["brute", "leader"] else 1
		var give := budget >= cost and e.global_position.distance_to(player.global_position) < 9.0
		if give:
			budget -= cost
		e.has_token = give
