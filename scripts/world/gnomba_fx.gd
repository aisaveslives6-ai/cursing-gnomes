class_name GnombaFX
extends Node2D
## Cursing Gnomes — Prince Gnomba "royal treasury" FX
## (2026-10-08 wake deep-work, Disaster #26).
##
## The prince shipped with bespoke chibi art — purple/gold agbada, crooked
## crown, scroll and coin purse — but the CON itself was invisible. This
## Body-child FX makes the grift visible: golden coin motes rising off the
## coin purse (each a twinkling disc, the "processing fees" floating away)
## and a periodic crown glint — plastic shining like real gold. Pure _draw
## (no textures, no emoji/glyphs — ASCII-safe). The sprite itself is never
## moved — freeze-position law: all motion lives in this FX node's geometry.

## Monster world height in px (the prince's scale, set by UnitNode).
var stage_h := 64.0
## Rising coin motes off the purse.
const COIN_COUNT := 8
## One coin's rise cycle, seconds.
const COIN_CYCLE := 2.8
## Crown "definitely real gold" glint period, seconds.
const GLINT_PERIOD := 4.0

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 0..1 progress of coin i through its rise cycle (desynced).
func _coin_cycle(i: int) -> float:
	return fmod(_t / COIN_CYCLE + float(i) * 0.61803, 1.0)


## Glint alpha 0..1: a sharp flash right after each period boundary.
func _glint_alpha() -> float:
	var ph := fmod(_t / GLINT_PERIOD, 1.0)
	return clampf(1.0 - ph * 6.0, 0.0, 1.0)


func _draw() -> void:
	var h: float = stage_h
	# Golden coin motes: rise from the purse (right hip) and fade.
	for i in COIN_COUNT:
		var c := _coin_cycle(i)
		var px: float = h * 0.30 + sin((_t * 1.7 + float(i) * 2.1)) * h * 0.06
		var py: float = lerpf(h * 0.10, -h * 0.55, c)
		var tw: float = 0.55 + 0.45 * sin(_t * 9.0 + float(i) * 1.7)
		var a: float = (1.0 - c) * tw
		var r: float = h * 0.035 * (1.0 - c * 0.4)
		draw_circle(Vector2(px, py), r,
			Color(1.0, 0.82, 0.25, 0.85 * a))
		draw_arc(Vector2(px, py), r, 0.0, TAU, 8,
			Color(1.0, 0.95, 0.55, 0.85 * a), 1.5)
	# Crown glint: a four-point star flashing at head height.
	var ga := _glint_alpha()
	if ga > 0.01:
		var gp := Vector2(h * 0.18, -h * 0.92)
		var gr: float = h * 0.10 * (0.5 + 0.5 * ga)
		var gc := Color(1.0, 0.95, 0.6, 0.9 * ga)
		draw_line(gp + Vector2(-gr, 0.0), gp + Vector2(gr, 0.0), gc, 2.0)
		draw_line(gp + Vector2(0.0, -gr), gp + Vector2(0.0, gr), gc, 2.0)
