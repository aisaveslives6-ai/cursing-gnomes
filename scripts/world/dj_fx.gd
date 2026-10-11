class_name DjFX
extends Node2D
## Cursing Gnomes — DJ Weddington bespoke FX (massive-dev 2026-10-08,
## Disaster #27).
##
## Weddington turns the town square into a dance floor. This rig sells the
## set: a spinning mirror ball throwing rotating light beams, music notes
## rising off the crowd, and a bouncing equalizer row behind the decks.
## Pure _draw, ASCII-safe, freeze-position law honored (the node never
## moves the unit; it only draws around the body anchor).

const NOTE_COUNT_MAX := 12
const BEAM_COUNT := 6
const EQ_BARS := 9

# World-space height of the monster sprite this rig decorates (set by
# UnitNode._build_dj_fx, like the other monster rigs). All draw
# coordinates scale by stage_h / 64 so the ball, beams, and notes track
# the sprite at any monster scale.
var stage_h := 64.0

var _t := 0.0
var _notes := []    # Array[Dictionary]: pos, vel, life, max_life, size
var _note_accum := 0.0
var _eq_phase := [] # per-bar phase offsets for the bounce

# A note lifts off a dancer's head about every 0.8s while he spins.
const NOTE_PERIOD := 0.8


func _ready() -> void:
	z_index = 2  # buried-FX lesson (doomscroll 2026-10-08): FX built before
	# _sprite joins _body must outrank it or the beams hide under art.
	for i in EQ_BARS:
		_eq_phase.append(randf() * TAU)


func _process(delta: float) -> void:
	_t += delta
	_note_accum += delta
	if _note_accum >= NOTE_PERIOD and _notes.size() < NOTE_COUNT_MAX:
		_note_accum = 0.0
		_spawn_note()
	for n in _notes:
		n["life"] = float(n["life"]) + delta
		n["pos"] = (n["pos"] as Vector2) + (n["vel"] as Vector2) * delta
	_notes = _notes.filter(func(n): return float(n["life"]) < float(n["max_life"]))
	queue_redraw()


func _spawn_note() -> void:
	_notes.append({
		"pos": Vector2(randf_range(-46.0, 46.0), randf_range(-6.0, 12.0)),
		"vel": Vector2(randf_range(-10.0, 10.0), randf_range(-52.0, -34.0)),
		"life": 0.0, "max_life": randf_range(1.3, 1.9),
		"size": randf_range(5.0, 8.0),
	})


func _draw() -> void:
	var s := stage_h / 64.0
	# Mirror ball: hanging above him, spinning light beams sweeping the floor.
	var ball := Vector2(0, -66.0 * s)
	var spin := _t * 1.7
	draw_circle(ball, 9.0 * s, Color(0.82, 0.86, 0.92, 0.95))
	draw_circle(ball + Vector2(-3.0 * s, -3.0 * s), 3.0 * s,
		Color(1, 1, 1, 0.9))
	draw_line(ball + Vector2(0, -9.0 * s), ball + Vector2(0, -20.0 * s),
		Color(0.4, 0.42, 0.46, 0.8), 2.0 * s)
	for i in BEAM_COUNT:
		var ang := spin + TAU * float(i) / float(BEAM_COUNT)
		var dir := Vector2(cos(ang), sin(ang) * 0.55).normalized()
		var tip := ball + dir * 58.0 * s
		var hue_shift := 0.5 + 0.5 * sin(_t * 3.0 + float(i) * 1.3)
		var col := Color(1.0, 0.45 + 0.35 * hue_shift, 0.9, 0.16)
		draw_line(ball, tip, col, 7.0 * s)
		draw_circle(tip, 4.5 * s, Color(1.0, 0.75, 0.95, 0.28))
	# Equalizer: bouncing bars behind the decks.
	for i in EQ_BARS:
		var bx := (float(i) - float(EQ_BARS - 1) * 0.5) * 13.0 * s
		var h := (10.0 + 14.0 * (0.5 + 0.5 * sin(_t * 6.0 + _eq_phase[i]))) * s
		var base := Vector2(bx, 26.0 * s)
		var bar_col := Color(0.45, 0.95, 1.0, 0.55)
		if i % 3 == 1:
			bar_col = Color(1.0, 0.45, 0.85, 0.55)
		elif i % 3 == 2:
			bar_col = Color(0.65, 1.0, 0.45, 0.55)
		draw_line(base, base + Vector2(0, -h), bar_col, 6.0 * s)
	# Rising music notes: head + stem + flag, drawn from primitives.
	for n in _notes:
		var a := 1.0 - float(n["life"]) / float(n["max_life"])
		var pp: Vector2 = (n["pos"] as Vector2) * s
		var sz: float = float(n["size"]) * s
		var ncol := Color(1.0, 0.85, 0.35, 0.9 * a)
		draw_circle(pp, sz * 0.45, ncol)
		draw_line(pp + Vector2(sz * 0.4, 0), pp + Vector2(sz * 0.4, -sz * 1.6),
			ncol, 2.2 * s)
		draw_line(pp + Vector2(sz * 0.4, -sz * 1.6),
			pp + Vector2(sz * 1.1, -sz * 1.25), ncol, 2.2 * s)


## Test hook: how many live notes are on stage.
func live_counts() -> Dictionary:
	return {"notes": _notes.size()}
