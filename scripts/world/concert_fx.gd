class_name ConcertFX
extends Node2D
## Cursing Gnomes — karaoke barbarian concert-stage FX (2026-10-08 wake
## graphics-hourly).
##
## Brax the karaoke barbarian storms in with a lute and performs a 3-set
## power-ballad set list, but until now his show was sprite + audio only —
## no stage. While the sim has him "belting" (combat_state == "belting"),
## this Body-child FX draws his concert rig: two sweeping spotlight beams
## (warm gold + hot pink, translucent), a pulsing stage glow at his feet,
## and eighth-notes that rise and fade like the crowd can hear him.
## Pure _draw (no textures, no emoji/glyphs — the notes are drawn
## geometry, ASCII-safe). One node per barbarian (the sim gates one
## karaoke disaster per day), trivial draw cost. Hidden and idle when not
## performing, so swaggering/booed-off Brax renders exactly as before.

## Stage height in world px (the barbarian's monster scale, set by the
## UnitNode at build time).
var stage_h := 64.0
## Seconds for one full note rise cycle.
const NOTE_CYCLE := 2.4
## Notes in the rising pool (desynced by phase so the stream is constant).
const NOTE_COUNT := 8
## Beam sweep speed (rad/s) and half-angle of the sweep.
const SWEEP_SPEED := 1.6
const SWEEP_AMP := 0.38

var _performing := false
var _t := 0.0


func _init() -> void:
	# _ready() is deferred to the first frame in -s script mode; hide
	# immediately so a fresh node never flashes one idle frame.
	visible = false


func set_performing(active: bool) -> void:
	_performing = active
	visible = active
	set_process(active)
	if active:
		queue_redraw()


func is_performing() -> bool:
	return _performing


func _ready() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not _performing:
		return
	_t += delta
	queue_redraw()


## 0..1 progress of note i through its rise cycle.
func _note_cycle(i: int) -> float:
	return fmod(_t / NOTE_CYCLE + float(i) / float(NOTE_COUNT), 1.0)


func _draw() -> void:
	if not _performing:
		return
	var h := stage_h
	# Stage glow: pulsing gold ellipse at the feet.
	var pulse := 0.5 + 0.5 * sin(_t * 5.2)
	_draw_filled_ellipse(Vector2(0, 4), h * 0.55, h * 0.16,
		Color(1.0, 0.80, 0.35, 0.10 + 0.08 * pulse))
	# Spotlight beams: two translucent fans from below-stage, sweeping.
	_draw_beam(-1.0, Color(1.0, 0.84, 0.35, 0.15), h)
	_draw_beam(1.0, Color(1.0, 0.35, 0.65, 0.12), h)
	# Rising eighth-notes.
	for i in NOTE_COUNT:
		_draw_note(i, h)


## One spotlight beam: a quad from the stage point fanning upward,
## swaying with the sweep. `side` -1 = left-leaning, +1 = right-leaning.
func _draw_beam(side: float, color: Color, h: float) -> void:
	var ang := side * (0.55 + SWEEP_AMP * sin(_t * SWEEP_SPEED + side * 1.3))
	var base := Vector2(0, 6)
	var tip_c := base + Vector2(sin(ang), -cos(ang)) * h * 2.1
	var spread := 0.16
	var tip_l := base + Vector2(sin(ang - spread), -cos(ang - spread)) * h * 2.1
	var tip_r := base + Vector2(sin(ang + spread), -cos(ang + spread)) * h * 2.1
	# Fade the beam with height: draw as two stacked quads, upper dimmer.
	var mid := base.lerp(tip_c, 0.55)
	var mid_l := base.lerp(tip_l, 0.55)
	var mid_r := base.lerp(tip_r, 0.55)
	draw_colored_polygon(PackedVector2Array([base, mid_l, mid_r]), color)
	var dim := color
	dim.a *= 0.45
	draw_colored_polygon(
		PackedVector2Array([mid_l, tip_l, tip_r, mid_r]), dim)
	# Hot core line down the middle.
	var core := color
	core.a = minf(0.35, color.a * 2.2)
	draw_line(base, tip_c, core, 3.0, true)


## One rising eighth-note: filled head + stem + flag, drawn geometrically.
func _draw_note(i: int, h: float) -> void:
	var cyc := _note_cycle(i)
	# Fade in fast, out slow; scale swells slightly mid-rise.
	var alpha := clampf(cyc * 6.0, 0.0, 1.0) * (1.0 - cyc * cyc)
	if alpha <= 0.01:
		return
	var x := sin(float(i) * 2.39 + _t * 1.1) * h * 0.42
	var y := -h * 0.15 - cyc * h * 1.55
	var s := 0.8 + 0.5 * sin(cyc * PI)  # swell mid-rise
	var col := Color(1.0, 0.85, 0.40, 0.85 * alpha)
	var head := Vector2(x, y)
	# Note head (tilted ellipse via two circles is overkill — one circle).
	draw_circle(head, 5.0 * s, col)
	# Stem up from the head's right edge.
	var stem_top := head + Vector2(4.5 * s, -22.0 * s)
	draw_line(head + Vector2(4.5 * s, 0), stem_top, col, 2.5 * s, true)
	# Flag: little flick off the stem top.
	draw_line(stem_top, stem_top + Vector2(7.0 * s, 5.0 * s), col,
		2.5 * s, true)


## Filled ellipse via a polygon fan (for engines without draw_ellipse).
func _draw_filled_ellipse(center: Vector2, rx: float, ry: float,
		color: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for k in n + 1:
		var a := TAU * float(k) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)
