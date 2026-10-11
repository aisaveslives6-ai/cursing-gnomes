class_name InfluencerFX
extends Node2D
## Cursing Gnomes — Vicky the Influencer bespoke FX (dedicated-porting
## 2026-10-08).
##
## Vicky films content in the town square and the town gawks with her.
## This rig sells the shoot: a pulsing warm ring-light halo around her,
## pink hearts floating up from the crowd's phone screens, and a camera
## flash pop every few seconds when she takes the selfie. Pure _draw,
## ASCII-safe, freeze-position law honored (the node never moves the unit;
## it only draws around the body anchor).

const HEART_COUNT_MAX := 14
const SPARKLE_COUNT_MAX := 10

# World-space height of the monster sprite this rig decorates (set by
# UnitNode._build_influencer_fx, like the other monster rigs). All draw
# coordinates scale by stage_h / 64 so the halo, hearts, and flashes track
# the sprite at any monster scale.
var stage_h := 64.0

var _t := 0.0
var _hearts := []    # Array[Dictionary]: pos, vel, life, max_life, size
var _sparkles := []  # Array[Dictionary]: pos, life, max_life, size
var _flash_t := 0.0  # time since the last camera flash
var _heart_accum := 0.0

# A heart rises off a gawker's phone about every 0.7s while she films.
const HEART_PERIOD := 0.7
# The selfie flash pops every ~4s.
const FLASH_PERIOD := 4.0
const FLASH_LEN := 0.28


func _ready() -> void:
	z_index = 2  # buried-FX lesson (doomscroll 2026-10-08): FX built before
	# _sprite joins _body must outrank it or the glow/hearts hide under art.


func _process(delta: float) -> void:
	_t += delta
	_flash_t += delta
	if _flash_t >= FLASH_PERIOD:
		_flash_t = 0.0
	# Hearts drift up from the crowd while she films.
	_heart_accum += delta
	if _heart_accum >= HEART_PERIOD and _hearts.size() < HEART_COUNT_MAX:
		_heart_accum = 0.0
		_spawn_heart()
	# Ambient sparkles shimmer around the ring light.
	if _sparkles.size() < SPARKLE_COUNT_MAX and randf() < delta * 6.0:
		_spawn_sparkle()
	_tick_particles(delta)
	queue_redraw()


func _spawn_heart() -> void:
	_hearts.append({
		"pos": Vector2(randf_range(-30.0, 30.0), randf_range(-6.0, 10.0)),
		"vel": Vector2(randf_range(-8.0, 8.0), randf_range(-46.0, -30.0)),
		"life": 0.0, "max_life": randf_range(1.4, 2.0),
		"size": randf_range(4.0, 7.0),
	})


func _spawn_sparkle() -> void:
	var ang := randf() * TAU
	var r := randf_range(34.0, 52.0)
	_sparkles.append({
		"pos": Vector2(cos(ang) * r, sin(ang) * r * 0.9 - 6.0),
		"life": 0.0, "max_life": randf_range(0.5, 0.9),
		"size": randf_range(2.5, 4.5),
	})


func _tick_particles(delta: float) -> void:
	for p in _hearts:
		p["life"] = float(p["life"]) + delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
	_hearts = _hearts.filter(func(p): return float(p["life"]) < float(p["max_life"]))
	for p in _sparkles:
		p["life"] = float(p["life"]) + delta
	_sparkles = _sparkles.filter(func(p): return float(p["life"]) < float(p["max_life"]))


func _draw() -> void:
	var s := stage_h / 64.0
	# Ring-light halo: warm gold ring pulsing gently around her.
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	var halo_r := 44.0 * s
	var halo_a := 0.22 + 0.18 * pulse
	draw_arc(Vector2(0, -10.0 * s), halo_r, 0.0, TAU, 48,
		Color(1.0, 0.85, 0.45, halo_a), 5.0 * s, true)
	draw_arc(Vector2(0, -10.0 * s), halo_r + 7.0 * s, 0.0, TAU, 48,
		Color(1.0, 0.9, 0.6, halo_a * 0.45), 2.5 * s, true)
	# Floating hearts: two pink circles + a triangle read as a heart.
	for p in _hearts:
		var a := 1.0 - float(p["life"]) / float(p["max_life"])
		var pp: Vector2 = (p["pos"] as Vector2) * s
		var sz: float = float(p["size"]) * s
		var col := Color(1.0, 0.45, 0.65, 0.85 * a)
		draw_circle(pp + Vector2(-sz * 0.45, -sz * 0.2), sz * 0.55, col)
		draw_circle(pp + Vector2(sz * 0.45, -sz * 0.2), sz * 0.55, col)
		draw_colored_polygon([
			pp + Vector2(-sz * 0.95, sz * 0.05),
			pp + Vector2(sz * 0.95, sz * 0.05),
			pp + Vector2(0, sz * 0.95),
		], col)
	# Sparkles: small white plus-glints around the ring light.
	for p in _sparkles:
		var a2 := 1.0 - float(p["life"]) / float(p["max_life"])
		var pp2: Vector2 = (p["pos"] as Vector2) * s
		var sz2: float = float(p["size"]) * s
		var scol := Color(1, 1, 1, 0.8 * a2)
		draw_line(pp2 + Vector2(-sz2, 0), pp2 + Vector2(sz2, 0), scol, 2.0 * s)
		draw_line(pp2 + Vector2(0, -sz2), pp2 + Vector2(0, sz2), scol, 2.0 * s)
	# Camera flash: a white starburst at the phone (upper area) on the pop.
	if _flash_t < FLASH_LEN:
		var fa := 1.0 - _flash_t / FLASH_LEN
		var fp := Vector2(14.0 * s, -52.0 * s)
		var fr := lerpf(6.0, 26.0, _flash_t / FLASH_LEN) * s
		for i in 8:
			var ang2 := TAU * float(i) / 8.0 + 0.4
			var d := Vector2(cos(ang2), sin(ang2))
			draw_line(fp + d * fr * 0.4, fp + d * fr,
				Color(1, 1, 1, 0.9 * fa), 3.0 * s)
		draw_circle(fp, 5.0 * s * fa + 2.0, Color(1, 1, 1, 0.85 * fa))


## Test hook: how many live particles are on stage.
func live_counts() -> Dictionary:
	return {"hearts": _hearts.size(), "sparkles": _sparkles.size()}
