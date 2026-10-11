class_name DoomscrollFX
extends Node2D
## Cursing Gnomes — Milo the Doomscroller screen-glow FX
## (2026-10-08 wake graphics-hourly).
##
## Milo shipped with bespoke chibi art — glazed half-lidded eyes, droopy
## nightcap, hunched over a glowing smartphone, thumb mid-scroll — but the
## phone's glow was baked static into the PNG: a doomscroller whose screen
## never flickers. This Body-child FX makes the scroll alive: a cool
## blue-white glow breathing on his face that dips and spikes on every
## thumb-flick, plus short content streaks rising across the phone screen
## (the feed scrolling past), and a rare brighter "notification ping".
## Pure _draw (no textures, no emoji/glyphs — ASCII-safe). One node per
## doomscroller (the sim spawns Milo as a named disaster, so concurrent
## instances are ~1); trivial draw cost. The sprite itself is never moved —
## freeze-position law: all motion lives in this FX node's own geometry.

## Monster world height in px (the doomscroller's scale, set by the
## UnitNode at build time).
var stage_h := 64.0
## Seconds between thumb-flicks (the glow dips, then surges back).
const SCROLL_TICK := 0.9
## Feed streaks in the rising pool (desynced so the feed never stalls).
const STREAK_COUNT := 3
## One streak's rise cycle (fast — content whips past).
const STREAK_CYCLE := 0.7
## Notification ping period (rare bright flash).
const PING_PERIOD := 7.0

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 0..1 flick phase: 0 at the instant of a thumb-flick, 1 just before.
func _flick_phase() -> float:
	return fmod(_t / SCROLL_TICK, 1.0)


## 0..1 progress of streak i through its rise cycle.
func _streak_cycle(i: int) -> float:
	return fmod(_t / STREAK_CYCLE + float(i) / float(STREAK_COUNT), 1.0)


## Current screen-glow alpha multiplier (flick dip + breathing + ping).
func _glow_mult() -> float:
	var phase := _flick_phase()
	# Thumb-flick: sharp dip right at the flick, surging back after.
	var flick := 1.0 - 0.45 * exp(-phase * 9.0)
	# Slow breathing of the screen light.
	var breathe := 0.82 + 0.18 * sin(_t * 2.1)
	var m := flick * breathe
	# Notification ping: brief bright flash once per PING_PERIOD.
	var ping_phase := fmod(_t / PING_PERIOD, 1.0)
	if ping_phase < 0.06:
		m += 0.9 * (1.0 - ping_phase / 0.06)
	return m


func _draw() -> void:
	if stage_h <= 0.0:
		return
	var h := stage_h
	var m := _glow_mult()
	# Face glow: cool screen-light washing the glazed face. The PNG bakes
	# a static glow; this is the living flicker on top of it.
	var face := Vector2(0.0, -h * 0.72)
	_draw_filled_ellipse(face, h * 0.30, h * 0.24,
		Color(0.62, 0.78, 1.0, clampf(0.16 * m, 0.02, 0.45)))
	# Hotter core near the phone itself.
	var phone := Vector2(h * 0.05, -h * 0.50)
	_draw_filled_ellipse(phone, h * 0.16, h * 0.20,
		Color(0.70, 0.84, 1.0, clampf(0.22 * m, 0.03, 0.55)))
	# Feed streaks: content scrolling up the phone screen.
	for i in STREAK_COUNT:
		_draw_streak(i, h, phone)


## One feed streak: a short vertical line rising across the phone screen,
## fading as it goes (content whipping past under the thumb).
func _draw_streak(i: int, h: float, phone: Vector2) -> void:
	var cyc := _streak_cycle(i)
	var alpha := clampf(cyc * 5.0, 0.0, 1.0) * (1.0 - cyc)
	if alpha <= 0.01:
		return
	var x := phone.x + (float(i) - 1.0) * h * 0.055
	var y_top := phone.y - h * 0.10 - cyc * h * 0.16
	var col := Color(0.75, 0.88, 1.0, 0.55 * alpha)
	draw_line(Vector2(x, y_top + h * 0.07), Vector2(x, y_top), col, 2.5, true)


## Filled ellipse via a polygon fan (for engines without draw_ellipse).
func _draw_filled_ellipse(center: Vector2, rx: float, ry: float,
		color: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for k in n + 1:
		var a := TAU * float(k) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)
