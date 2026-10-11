class_name CrossFitFX
extends Node2D
## Cursing Gnomes — Kyle the CrossFit Gnome bespoke FX (massive-dev 2026-10-08).
##
## Kyle does burpees in the town square and the town does burpees with him.
## This rig sells the workout: dust puffs kicked up on every burpee landing,
## sweat drops flung off on the jump, and a periodic protein-shaker glint.
## Pure _draw, ASCII-safe, freeze-position law honored (the node never moves
## the unit; it only draws around the body anchor).

const DUST_COUNT := 7
const SWEAT_COUNT := 5

# World-space height of the monster sprite this rig decorates (set by
# UnitNode._build_crossfit_fx, like the other monster rigs). All draw
# coordinates scale by stage_h / 64 so the dust, sweat, and glint track
# the sprite at any monster scale.
var stage_h := 64.0

var _t := 0.0
var _burpee_phase := 0.0  # 0..1 loop: jump -> land -> pushup -> jump
var _dust := []   # Array[Dictionary]: pos, vel, life, max_life, size
var _sweat := []  # Array[Dictionary]: pos, vel, life, max_life
var _glint_t := 0.0

# Burpee cadence: one full burpee every 1.6s (Kyle is annoyingly fit).
const BURPEE_PERIOD := 1.6
# Landing kicks dust at phase ~0.5 (feet hit the ground).
const LAND_PHASE := 0.5


func _ready() -> void:
	z_index = 2  # buried-FX lesson (doomscroll 2026-10-08): FX built before
	# _sprite joins _body must outrank it or the glow/dust hides under the art.


func _process(delta: float) -> void:
	_t += delta
	var prev_phase := _burpee_phase
	_burpee_phase = fmod(_burpee_phase + delta / BURPEE_PERIOD, 1.0)
	# Landing edge: feet hit the ground -> kick up dust.
	if prev_phase < LAND_PHASE and _burpee_phase >= LAND_PHASE:
		_spawn_dust()
	# Jump apex sheds sweat (phase ~0.15).
	if prev_phase < 0.15 and _burpee_phase >= 0.15:
		_spawn_sweat()
	_tick_particles(delta)
	_glint_t += delta
	queue_redraw()


func _spawn_dust() -> void:
	for i in DUST_COUNT:
		var ang := randf() * TAU
		var spd := randf_range(28.0, 70.0)
		_dust.append({
			"pos": Vector2(randf_range(-14.0, 14.0), randf_range(6.0, 14.0)),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd * 0.45 - 12.0),
			"life": 0.0, "max_life": randf_range(0.5, 0.9),
			"size": randf_range(3.0, 6.5),
		})


func _spawn_sweat() -> void:
	for i in SWEAT_COUNT:
		var ang := randf_range(-1.2, 1.2) + (-PI / 2.0)
		var spd := randf_range(60.0, 130.0)
		_sweat.append({
			"pos": Vector2(randf_range(-8.0, 8.0), randf_range(-34.0, -20.0)),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd),
			"life": 0.0, "max_life": randf_range(0.45, 0.7),
		})


func _tick_particles(delta: float) -> void:
	for p in _dust:
		p["life"] = float(p["life"]) + delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["vel"] = (p["vel"] as Vector2) * (1.0 - 2.2 * delta)
	_dust = _dust.filter(func(p): return float(p["life"]) < float(p["max_life"]))
	for p in _sweat:
		p["life"] = float(p["life"]) + delta
		var v: Vector2 = p["vel"]
		v.y += 420.0 * delta  # sweat obeys gravity
		p["vel"] = v
		p["pos"] = (p["pos"] as Vector2) + v * delta
	_sweat = _sweat.filter(func(p): return float(p["life"]) < float(p["max_life"]))


func _draw() -> void:
	var s := stage_h / 64.0
	# Dust puffs: tan circles fading out as they drift.
	for p in _dust:
		var a := 1.0 - float(p["life"]) / float(p["max_life"])
		var sz: float = float(p["size"]) * (0.6 + 0.4 * (1.0 - a)) * s
		draw_circle((p["pos"] as Vector2) * s, sz, Color(0.82, 0.74, 0.58, 0.55 * a))
	# Sweat drops: small cyan-white streaks arcing off.
	for p in _sweat:
		var a2 := 1.0 - float(p["life"]) / float(p["max_life"])
		var v: Vector2 = p["vel"]
		var dir := v.normalized() if v.length() > 1.0 else Vector2.DOWN
		var pp: Vector2 = (p["pos"] as Vector2) * s
		draw_line(pp - dir * 5.0 * s, pp,
			Color(0.65, 0.85, 1.0, 0.8 * a2), 2.5 * s)
	# Protein-shaker glint: a white sparkle sweeping the shaker every ~3s.
	var gc := fmod(_glint_t, 3.0)
	if gc < 0.35:
		var ga := 1.0 - gc / 0.35
		var gx := lerpf(-10.0, 10.0, gc / 0.35) * s
		# Shaker sits at the feet (~+38px below anchor).
		var gp := Vector2(gx, 38.0 * s)
		draw_line(gp + Vector2(-6, 0) * s, gp + Vector2(6, 0) * s,
			Color(1, 1, 1, 0.85 * ga), 2.0 * s)
		draw_line(gp + Vector2(0, -6) * s, gp + Vector2(0, 6) * s,
			Color(1, 1, 1, 0.85 * ga), 2.0 * s)


## Test hook: how many live particles are on stage.
func live_counts() -> Dictionary:
	return {"dust": _dust.size(), "sweat": _sweat.size()}
