class_name MLMBroFX
extends Node2D
## Cursing Gnomes — Chad the MLM Bro "opportunity sparkles" FX
## (2026-10-08 wake rapid-iteration).
##
## Chad shipped with bespoke chibi art — cheap navy suit, red tie, slicked
## hair, blinding grin, a briefcase full of "opportunity" — but the
## opportunity itself was invisible. This Body-child FX makes the pitch
## visible: golden sparkle motes rising off the briefcase (each a twinkling
## four-point star), a soft expanding pitch-pulse ring on every aura cadence
## (the aura that recruits hustlers into the downline), and a periodic
## briefcase glint — the "diamond level" shimmer. Pure _draw (no textures,
## no emoji/glyphs — ASCII-safe). The sprite itself is never moved —
## freeze-position law: all motion lives in this FX node's own geometry.

## Monster world height in px (Chad's scale, set by the UnitNode at
## build time).
var stage_h := 64.0
## Rising sparkle motes off the briefcase.
const SPARK_COUNT := 9
## One spark's rise cycle, seconds.
const SPARK_CYCLE := 2.4
## Pitch-pulse period: matches MLM_AURA_CD (3.0) in disasters.gd — the
## ring expands exactly when the aura ticks.
const PITCH_TICK := 3.0
## Briefcase "diamond shimmer" glint period, seconds.
const GLINT_PERIOD := 5.0

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 0..1 progress of spark i through its rise cycle (desynced).
func _spark_cycle(i: int) -> float:
	return fmod(_t / SPARK_CYCLE + float(i) * 0.61803, 1.0)


## 0..1 phase of the pitch-pulse ring expansion.
func _ring_phase() -> float:
	return fmod(_t / PITCH_TICK, 1.0)


## 0..1 phase of the briefcase glint flash.
func _glint_phase() -> float:
	return fmod(_t / GLINT_PERIOD, 1.0)


## Current pitch-ring radius in px (Body-local).
func _ring_radius() -> float:
	var h: float = stage_h
	return lerpf(h * 0.35, h * 1.30, _ring_phase())


## Glint alpha 0..1: a sharp flash right after each period boundary,
## otherwise silent.
func _glint_alpha() -> float:
	var ph := _glint_phase()
	if ph < 0.08:
		return 1.0 - ph / 0.08
	return 0.0


## Where a spark sits: briefcase anchor, rising as its cycle advances,
## with a gentle side-to-side drift so the motes never look scripted.
func _spark_pos(i: int, h: float) -> Vector2:
	var cyc := _spark_cycle(i)
	var anchor := Vector2(h * 0.30, -h * 0.28)
	var drift := sin(_t * 1.7 + float(i) * 2.4) * h * 0.09
	return Vector2(anchor.x + drift, anchor.y - cyc * h * 0.62)


## One four-point sparkle star (two crossed lines + short diagonals),
## the classic cartoon "glint" shape. No glyphs, no textures.
func _draw_sparkle(center: Vector2, size: float, color: Color) -> void:
	draw_line(center + Vector2(0, -size), center + Vector2(0, size),
		color, 2.0, true)
	draw_line(center + Vector2(-size, 0), center + Vector2(size, 0),
		color, 2.0, true)
	var d := size * 0.55
	draw_line(center + Vector2(-d, -d), center + Vector2(d, d),
		color, 1.5, true)
	draw_line(center + Vector2(-d, d), center + Vector2(d, -d),
		color, 1.5, true)


## Filled ellipse via a polygon fan (for engines without draw_ellipse).
func _draw_filled_ellipse(center: Vector2, rx: float, ry: float,
		color: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for k in n + 1:
		var a := TAU * float(k) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)


func _draw() -> void:
	if stage_h <= 0.0:
		return
	var h: float = stage_h
	# Pitch pulse: a soft golden ring expanding on every aura cadence —
	# the visible shape of Chad's recruiting aura.
	var rph := _ring_phase()
	var ring := _ring_radius()
	var ring_alpha := 0.30 * (1.0 - rph)
	if ring_alpha > 0.01:
		draw_arc(Vector2(0.0, -h * 0.45), ring, 0.0, TAU, 48,
			Color(1.0, 0.82, 0.35, ring_alpha), 3.0, true)
	# Sparkle motes: golden "opportunity" rising off the briefcase.
	for i in SPARK_COUNT:
		var cyc := _spark_cycle(i)
		# Twinkle: each mote pulses at its own rate.
		var tw := 0.55 + 0.45 * sin(_t * 6.0 + float(i) * 2.1)
		var alpha := tw * clampf(cyc * 6.0, 0.0, 1.0) * (1.0 - cyc)
		if alpha <= 0.01:
			continue
		var size := h * 0.045 * (0.7 + 0.5 * cyc)
		_draw_sparkle(_spark_pos(i, h), size,
			Color(1.0, 0.86, 0.42, clampf(0.85 * alpha, 0.0, 0.9)))
	# Briefcase glint: the periodic "diamond level" shimmer.
	var ga := _glint_alpha()
	if ga > 0.01:
		var brief := Vector2(h * 0.30, -h * 0.28)
		_draw_filled_ellipse(brief, h * 0.10 * ga, h * 0.07 * ga,
			Color(1.0, 0.97, 0.80, 0.55 * ga))
		_draw_sparkle(brief, h * 0.16, Color(1.0, 0.98, 0.85, 0.95 * ga))
