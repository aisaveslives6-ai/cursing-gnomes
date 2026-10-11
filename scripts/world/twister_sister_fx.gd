class_name TwisterSisterFX
extends Node2D
## Cursing Gnomes — Twister Sister funnel-spin FX
## (2026-10-08 wake graphics-hourly).
##
## Twister Sister shipped with bespoke glam-metal tornado art (AI-generated
## chibi pixel-art funnel: 80s teased hair, sunglasses, crackling
## lightning, a tiny guitar) — but the PNG is a static funnel. A tornado
## that does not spin reads as a costume. This Body-child FX makes her a
## weather event: rotating spiral bands around the funnel (faster near the
## top, like a real vortex), a debris ring of torn-off roof tiles and
## planks orbiting the base, a dust skirt hugging the ground so the funnel
## stays grounded, and a crackling lightning bolt flashing inside the
## funnel. The debris bulges outward on every fling aura cadence (the sim
## flings citizens on a 0.5s tick) so the spin visibly pulses when she
## tosses someone. Pure _draw (no textures, no emoji/glyphs — ASCII-safe).
## The sprite itself is never moved — freeze-position law: all motion lives
## in this FX node's own geometry.

## Monster world height in px (her scale, set by the UnitNode at
## build time: SPRITE_WORLD_H * 2.0).
var stage_h := 64.0
## Debris flecks torn off roofs, orbiting the funnel base.
const DEBRIS_COUNT := 9
## Seconds per full debris orbit (the vortex spin rate).
const DEBRIS_PERIOD := 1.15
## Fling-surge period: matches the sim's twister aura cadence
## (twister_fling_cd reset to 0.5 in disasters.gd) — the debris ring
## bulges and quickens exactly when the aura ticks.
const FLING_TICK := 0.5
## Ground-dust motes in the grounding skirt.
const DUST_COUNT := 8
## One dust mote's outward drift cycle, seconds.
const DUST_CYCLE := 1.6
## Lightning bolt flash period, seconds.
const LIGHTNING_PERIOD := 1.7
## Spiral band count (stacked rotating arcs around the funnel).
const BAND_COUNT := 3

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 0..1 fling-surge phase: 0 at the instant the aura ticks, 1 just before.
func _surge_phase() -> float:
	return fmod(_t / FLING_TICK, 1.0)


## Surge strength 0..1: a sharp bulge right at the tick, easing back.
func _surge() -> float:
	return exp(-_surge_phase() * 6.0)


## 0..1 rotation phase of spiral band i (top bands spin faster).
func _band_phase(i: int) -> float:
	var speed := 1.0 + 0.55 * float(i) / float(BAND_COUNT - 1)
	return fmod(_t * speed / DEBRIS_PERIOD, 1.0)


## Band radius as a fraction of stage_h: funnel narrows at the base.
func _band_radius(i: int) -> float:
	return 0.30 + 0.17 * float(i)


## Band height: 0 = ground, up to ~0.82 of the funnel.
func _band_y(i: int, h: float) -> float:
	return -h * (0.24 + 0.29 * float(i))


## 0..1 orbit progress of debris fleck i (desynced).
func _debris_cycle(i: int) -> float:
	return fmod(_t / DEBRIS_PERIOD + float(i) / float(DEBRIS_COUNT), 1.0)


## Debris fleck position, Body-local. The ring rides near the ground and
## bulges outward with the fling surge.
func _debris_pos(i: int, h: float) -> Vector2:
	var cyc := _debris_cycle(i)
	var ang := TAU * cyc
	var r := h * (0.55 + 0.10 * _surge())
	var bob := sin(_t * 7.0 + float(i) * 2.2) * h * 0.02
	return Vector2(cos(ang) * r, -h * 0.13 + bob)


## 0..1 drift progress of dust mote i (desynced).
func _dust_cycle(i: int) -> float:
	return fmod(_t / DUST_CYCLE + float(i) * 0.61803, 1.0)


## Drift radius of a dust mote at cycle progress cyc: grows outward.
func _dust_radius(cyc: float, h: float) -> float:
	return h * (0.58 + 0.22 * cyc)


## Dust mote position: drifts outward along the ground and fades.
func _dust_pos(i: int, h: float) -> Vector2:
	var cyc := _dust_cycle(i)
	var ang := TAU * float(i) / float(DUST_COUNT) + _t * 0.9
	return Vector2(cos(ang) * _dust_radius(cyc, h), -3.0)


## Lightning flash alpha 0..1: bright right after a period boundary,
## silent between.
func _bolt_alpha() -> float:
	var phase := fmod(_t / LIGHTNING_PERIOD, 1.0)
	if phase > 0.08:
		return 0.0
	return 0.9 * (1.0 - phase / 0.08)


## Lightning bolt points for the current flash (Body-local). Seeded per
## period so the bolt shape is stable within one flash.
func _bolt_points(h: float) -> PackedVector2Array:
	var period := int(_t / LIGHTNING_PERIOD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7EA1 + period * 7919
	var pts := PackedVector2Array()
	var y := -h * 0.80
	var x := rng.randf_range(-h * 0.06, h * 0.06)
	while y < -h * 0.20:
		pts.append(Vector2(x, y))
		x += rng.randf_range(-h * 0.05, h * 0.05)
		y += rng.randf_range(h * 0.07, h * 0.12)
	pts.append(Vector2(x, -h * 0.20))
	return pts


func _draw() -> void:
	if stage_h <= 0.0:
		return
	var h: float = stage_h
	_draw_dust_skirt(h)
	_draw_spiral_bands(h)
	_draw_debris_ring(h)
	_draw_lightning(h)


## Ground dust skirt: keeps the funnel pinned to the earth.
func _draw_dust_skirt(h: float) -> void:
	for i in DUST_COUNT:
		var cyc := _dust_cycle(i)
		var alpha := 0.30 * (1.0 - cyc)
		if alpha <= 0.01:
			continue
		var r := h * (0.05 + 0.02 * cyc)
		_draw_filled_ellipse(_dust_pos(i, h), r, r * 0.6,
			Color(0.72, 0.66, 0.58, alpha))


## Three stacked rotating spiral arcs around the funnel — the vortex read.
func _draw_spiral_bands(h: float) -> void:
	for i in BAND_COUNT:
		var y := _band_y(i, h)
		var r := h * _band_radius(i)
		var phase := _band_phase(i)
		var alpha := 0.28 + 0.10 * _surge()
		for k in 3:
			var base := TAU * (phase + float(k) / 3.0)
			draw_arc(Vector2(0.0, y), r, base, base + 1.5,
				32, Color(0.85, 0.88, 0.95, alpha), 5.0, true)


## Torn-off roof tiles and planks orbiting the base.
func _draw_debris_ring(h: float) -> void:
	for i in DEBRIS_COUNT:
		var p := _debris_pos(i, h)
		var s := h * 0.028 + 0.4 * fmod(float(i) * 1.7, 1.0)
		var rot := _t * (2.0 + float(i) * 0.15)
		var tone := 0.32 + 0.1 * fmod(float(i) * 2.3, 1.0)
		_draw_tile(p, s, rot, Color(tone, tone * 0.82, tone * 0.62, 0.9))


## One roof tile / plank: a small rotated rect.
func _draw_tile(center: Vector2, size: float, rot: float,
		color: Color) -> void:
	var hw := size * 0.9
	var hh := size * 0.45
	var pts := PackedVector2Array()
	for corner in [Vector2(-hw, -hh), Vector2(hw, -hh),
			Vector2(hw, hh), Vector2(-hw, hh)]:
		pts.append(center + corner.rotated(rot))
	draw_colored_polygon(pts, color)


## Lightning crackling inside the funnel.
func _draw_lightning(h: float) -> void:
	var a := _bolt_alpha()
	if a <= 0.01:
		return
	var pts := _bolt_points(h)
	if pts.size() >= 2:
		draw_polyline(pts, Color(0.75, 0.85, 1.0, a), 3.5, true)


## Filled ellipse via a polygon fan (for engines without draw_ellipse).
func _draw_filled_ellipse(center: Vector2, rx: float, ry: float,
		color: Color) -> void:
	var pts := PackedVector2Array()
	var n := 16
	for k in n + 1:
		var a := TAU * float(k) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)
