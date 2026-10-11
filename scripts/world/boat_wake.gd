class_name BoatWake
extends Node2D
## Cursing Gnomes — foam wake behind moving boats (2026-10-04).
##
## The HTML boat branch (fix79 _toonDrawCharacter, index.html:38960) draws
## hull + bob + rock + faction pennant but NO wake — this is an original
## addition in the game's water language (drifting foam flecks, cf. the
## river foam in river_renderer.gd): while a boat sails, foam flecks spawn
## at the stern, drift with water drag, expand, and fade out.
##
## Perf (Jeremy's 60fps bar): flecks are pooled + capped (MAX_FLECKS), drawn
## as plain circles batched into ONE _draw() call per boat, and queue_redraw
## fires only while flecks are alive. No textures, no particles nodes, no
## sim/AI/RNG impact (randf jitter is visual-only). The node hides with the
## unit when culled (child of the boat's Body).


const MAX_FLECKS := 24
const SPAWN_INTERVAL := 0.08  # seconds between flecks while moving
const MOVE_THRESHOLD := 1.5   # px/frame below which no wake spawns

## Graphics-tier hook: scales spawn probability (0..1). UnitNode leaves it
## at 1.0 today; a future tier wiring can turn wakes down on low tiers.
var density := 1.0

var _flecks: Array[Dictionary] = []
var _spawn_acc := 0.0


func fleck_count() -> int:
	return _flecks.size()


## moved: px travelled this frame. stern: local offset of the stern
## (behind the boat, at the waterline). spread: lateral spawn jitter.
func tick(delta: float, moved: float, stern: Vector2, spread: float) -> void:
	# Age + drift existing flecks; drop the dead.
	var i := _flecks.size() - 1
	while i >= 0:
		var f: Dictionary = _flecks[i]
		f["age"] = float(f["age"]) + delta
		if float(f["age"]) >= float(f["life"]):
			_flecks.remove_at(i)
		else:
			var p: Vector2 = f["p"]
			var v: Vector2 = f["v"]
			p += v * delta
			v *= maxf(0.0, 1.0 - 1.6 * delta)  # water drag
			f["p"] = p
			f["v"] = v
		i -= 1
	# Spawn while the boat is actually sailing.
	if moved > MOVE_THRESHOLD:
		_spawn_acc += delta
		while _spawn_acc >= SPAWN_INTERVAL:
			_spawn_acc -= SPAWN_INTERVAL
			if density <= 0.0 or randf() > density:
				continue
			_spawn(stern, spread)
	else:
		_spawn_acc = 0.0
	if not _flecks.is_empty():
		queue_redraw()


func _spawn(stern: Vector2, spread: float) -> void:
	if _flecks.size() >= MAX_FLECKS:
		_flecks.pop_front()  # oldest fleck dissolves first
	_flecks.append({
		"p": stern + Vector2(randf_range(-spread, spread),
			randf_range(-2.0, 4.0)),
		"v": Vector2(randf_range(-7.0, 7.0), randf_range(-2.0, 3.0)),
		"age": 0.0,
		"life": randf_range(1.0, 1.45),
		"r0": randf_range(2.5, 4.0),
		"r1": randf_range(7.0, 10.0),
	})


func _draw() -> void:
	for f: Dictionary in _flecks:
		var t: float = clampf(float(f["age"]) / float(f["life"]), 0.0, 1.0)
		var a: float = pow(1.0 - t, 1.5) * 0.5
		if a <= 0.004:
			continue
		var r: float = lerpf(float(f["r0"]), float(f["r1"]), t)
		var p: Vector2 = f["p"]
		# Foam ring + brighter core, white-blue like the river foam.
		draw_circle(p, r, Color(0.90, 0.95, 1.0, a))
		draw_circle(p, r * 0.55, Color(1.0, 1.0, 1.0, a * 0.9))
