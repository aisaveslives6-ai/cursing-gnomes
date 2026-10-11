class_name FestivalFx
extends Node2D

## Cursing Gnomes — festival decorations (2026-10-07 wake rapid-iteration).
##
## Festivals (Policies app / Ruler's Voice / scheduled) previously changed
## nothing on screen: gold and food vanished, a Gazette story printed, and
## the celebrating town looked exactly the same. Now the town shows it for
## the 3-day joy window (SimPolicies: dn - last_festival_day <= 3):
##   - 4 wooden bunting poles planted around the town center
##     (ground-anchored — nothing floats), rope strings with catenary sag
##     between adjacent pole tops, pennant triangles in festive colors.
##   - 26 confetti bits drifting down over the town, deterministic from a
##     quantized step (chimney-smoke pattern: no per-frame RNG).
## Pure world-visual; zero sim touch. Invisible and idle when no festival.

const FEST_DAYS := 3            ## matches the SimPolicies joy window
const FX_STEPS := 8             ## quantized redraw steps...
const FX_PER_SEC := 6.0         ## ...at 6/sec (chimney-smoke cadence)
const CONFETTI_N := 26
const CONFETTI_STEPS := 32      ## fall length in FX steps (~5.3 s at 6/sec)
const POLE_R := 190.0           ## bunting poles ring radius around town center
const POLE_H := 150.0           ## pole height in world px
const SAG := 30.0               ## rope catenary sag at midpoint
const CONFETTI_R := 230.0       ## confetti spawn box half-width

## Festive pennant/confetti palette (drawn, anime-chibi bright).
const FEST_COLORS := [
	Color(0.83, 0.24, 0.24),  # festival red
	Color(0.91, 0.72, 0.23),  # gold
	Color(0.24, 0.48, 0.82),  # blue
	Color(0.24, 0.75, 0.35),  # green
	Color(0.61, 0.35, 0.72),  # purple
]

var _gs = null                  # GameState (untyped: avoids cyclic refs)
var _court = null               # SimRoyalCourt (untyped)
var _towns: Dictionary = {}
var _fest_state: Dictionary = {}
var _day_number: int = 1
var _fx_step := -1
var _fall_step := 0             ## slow confetti phase (CONFETTI_STEPS long)
var _accum := 0.0
var _active := false
var _center := Vector2.ZERO


## Festival layer: above y-sorted buildings/units (z 0), below UI chrome
## (chat bubbles sit at 60). Bunting is strung 150px in the air, so drawing
## over rooftops is physically right; confetti falls in front of facades.
func _init() -> void:
	z_index = 40


## Live wiring: world.gd passes the GameState and its royal court.
func setup(gs, court) -> void:
	_gs = gs
	_court = court
	_refresh_source()


## Test hook: inject state directly without a GameState/court.
func inject(towns: Dictionary, fest_state: Dictionary, day_number: int) -> void:
	_gs = null
	_court = null
	_towns = towns
	_fest_state = fest_state
	_day_number = day_number
	_recalc()


func _refresh_source() -> void:
	if _gs != null:
		_towns = _gs.towns
		_day_number = int(_gs.day_number)
	if _court != null and _court.policies != null:
		_fest_state = _court.policies.state
	_recalc()


func _recalc() -> void:
	_active = false
	_center = Vector2.ZERO
	var lfd := int(_fest_state.get("last_festival_day", 0))
	if lfd <= 0:
		return
	if _day_number - lfd < 0 or _day_number - lfd >= FEST_DAYS:
		return
	var tname := String(_fest_state.get("last_festival_town", ""))
	for tid in _towns:
		var t: Dictionary = _towns[tid]
		if String(t.get("name", "")) == tname:
			_center = t.get("position", Vector2.ZERO)
			_active = true
			return


func _process(delta: float) -> void:
	# Refresh the sim source on the quantized cadence (festival state only
	# changes on day boundaries; cheap anyway).
	_accum += delta
	if _accum < 1.0 / FX_PER_SEC:
		return
	_accum = 0.0
	if _gs != null or _court != null:
		_refresh_source()
	var step := int(Time.get_ticks_msec() / 1000.0 * FX_PER_SEC) % FX_STEPS
	if step != _fx_step:
		_fx_step = step
		_fall_step = (_fall_step + 1) % CONFETTI_STEPS
	visible = _active
	if _active:
		queue_redraw()


## --- test hooks ------------------------------------------------------------
func festival_active() -> bool:
	return _active


func town_center() -> Vector2:
	return _center


## Pole tops in world space (4), used by tests to verify rope anchoring.
func pole_tops() -> Array:
	var out: Array = []
	for i in 4:
		var a := deg_to_rad(45.0 + 90.0 * i)
		out.append(_center + Vector2(cos(a), sin(a)) * POLE_R + Vector2(0, -POLE_H))
	return out


func pennant_count() -> int:
	var n := 0
	var tops := pole_tops()
	for r in 4:
		var a: Vector2 = tops[r]
		var b: Vector2 = tops[(r + 1) % 4]
		n += int(a.distance_to(b) / 30.0)
	return n


func _draw() -> void:
	if not _active:
		return
	_draw_poles()
	_draw_bunting()
	_draw_confetti()


func _pole_base(i: int) -> Vector2:
	var a := deg_to_rad(45.0 + 90.0 * i)
	return _center + Vector2(cos(a), sin(a)) * POLE_R


func _draw_poles() -> void:
	for i in 4:
		var base := _pole_base(i)
		var top := base + Vector2(0, -POLE_H)
		# Wooden pole with a darker base shadow so it reads as planted.
		draw_line(base + Vector2(3, 2), top + Vector2(3, 2),
				Color(0, 0, 0, 0.25), 5.0)
		draw_line(base, top, Color(0.42, 0.28, 0.16), 4.0)
		draw_line(base, top + Vector2(0, -POLE_H * 0.4),
				Color(0.52, 0.36, 0.22), 1.5)
		draw_circle(top, 5.0, Color(0.91, 0.72, 0.23))


## Rope point with catenary sag between two pole tops.
func _rope_pt(a: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(b, t) + Vector2(0, sin(t * PI) * SAG)


func _draw_bunting() -> void:
	var tops := pole_tops()
	for r in 4:
		var a: Vector2 = tops[r]
		var b: Vector2 = tops[(r + 1) % 4]
		var segs := 16
		var prev := a
		for s in range(1, segs + 1):
			var p := _rope_pt(a, b, float(s) / segs)
			draw_line(prev, p, Color(0.35, 0.24, 0.14), 2.0)
			prev = p
		# Pennants: triangles hanging below the rope, alternating colors.
		var n := int(a.distance_to(b) / 30.0)
		for k in n:
			var t := (float(k) + 0.5) / float(n)
			var rp := _rope_pt(a, b, t)
			var col: Color = FEST_COLORS[(r * 3 + k) % FEST_COLORS.size()]
			draw_colored_polygon(
				[rp + Vector2(-7, 0), rp + Vector2(7, 0), rp + Vector2(0, 13)],
				col)


func _draw_confetti() -> void:
	for i in CONFETTI_N:
		# Deterministic per-bit stream (no per-frame RNG).
		var h1 := float((i * 7919 + 13) % 1000) / 1000.0
		var h2 := float((i * 4799 + 71) % 1000) / 1000.0
		var h3 := float((i * 3119 + 401) % 1000) / 1000.0
		var frac := float(_fall_step) / CONFETTI_STEPS + h1
		frac = frac - floor(frac)  # one fall per CONFETTI_STEPS
		var y := lerpf(-280.0, 60.0, frac)
		var x := (h2 - 0.5) * 2.0 * CONFETTI_R \
				+ sin(float(_fall_step) * 0.35 + h3 * TAU) * 18.0
		var fade := minf(frac / 0.12, 1.0) * minf((1.0 - frac) / 0.18, 1.0)
		if fade <= 0.0:
			continue
		var col: Color = FEST_COLORS[i % FEST_COLORS.size()]
		col.a = 0.9 * fade
		var rot := float(_fall_step) * 0.35 + h3 * TAU
		var dx := Vector2(cos(rot), sin(rot)) * 5.0
		var dy := Vector2(-sin(rot), cos(rot)) * 3.0
		var p := _center + Vector2(x, y)
		draw_colored_polygon([p - dx - dy, p + dx - dy, p + dx + dy, p - dx + dy],
				col)
