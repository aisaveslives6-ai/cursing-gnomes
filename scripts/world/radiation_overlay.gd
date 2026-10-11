class_name RadiationOverlay
extends Node2D
## Cursing Gnomes — radiation zone haze (Jeremy 2026-10-04, nuclear warfare;
## deepened 2026-10-06 to full HTML parity).
##
## HTML's radiation render block (fix79, verbatim):
##   pulse = 0.55 + 0.45 * sin(now/900 + z.x * 0.01)
##   a = 0.12 + 0.18 * z.intensity * pulse * min(1, z.life/40)
##   _gradSprite('rad_haze') — 128 px pre-rendered radial gradient:
##     (0, rgba(180,255,80,1)) (0.45, rgba(100,160,40,0.7))
##     (0.75, rgba(60,80,30,0.35)) (1, rgba(40,50,20,0))
##   drawn with globalAlpha = min(1, a * 1.2), scaled to 2r x 2r at (z.x - r, z.y - r)
##   scorched ring: if (z.scorch > 0.05):
##     strokeStyle rgba(50,40,20, 0.25 * scorch), lineWidth 18 * scorch,
##     arc at z.r * 0.55
##   culling: inView(z.x, z.y, z.r + 40)
## HTML sim (visual derivation — SimNuclear tracks only r/life; sim untouched):
##   z.intensity = max(0.15, 1 - age * 0.7)      (age = 1 - life/maxLife)
##   z.scorch    = min(1, scorch + dt * 0.02)    => min(1, age_seconds * 0.02)
##
## Godot port notes:
## - The rad_haze sprite is baked ONCE into a GradientTexture2D (_haze, 128 px,
##   HTML-verbatim stops) — one draw_texture per zone, zero per-frame
##   allocations (HTML's PERF 2026-10-01 pre-render note, same idea).
## - Intensity/scorch are derived verbatim from zone age in the overlay
##   (visual only — no sim-logic changes).
## - Isometric grounding: ground-plane ellipse via (1.0, 0.62) squash,
##   same convention as the other ground decals (combat_fx stains).
## - The fallout field (HTML window.nuclearFallout: 90 s, r 864) has no HTML
##   render block of its own; the port keeps its own visual (added
##   2026-10-04) upgraded to the same gradient treatment — no removed features.
## - Pure visual: reads nuclear.zones / nuclear.fallout every redraw.


## HTML-verbatim rad_haze gradient stops (offset, Color).
const _HAZE_STOPS: Array = [
	[0.0, Color(180.0 / 255.0, 1.0, 80.0 / 255.0, 1.0)],
	[0.45, Color(100.0 / 255.0, 160.0 / 255.0, 40.0 / 255.0, 0.7)],
	[0.75, Color(60.0 / 255.0, 80.0 / 255.0, 30.0 / 255.0, 0.35)],
	[1.0, Color(40.0 / 255.0, 50.0 / 255.0, 20.0 / 255.0, 0.0)],
]
const _HAZE_SIZE := 128
const _SQUASH := Vector2(1.0, 0.62)  # iso ground-plane squash
const _SCORCH_COL := Color(50.0 / 255.0, 40.0 / 255.0, 20.0 / 255.0)


var nuclear: RefCounted = null  # duck-typed SimNuclear (set by world)
var _t := 0.0
var _redraw_acc := 0.0  # Jeremy 2026-10-04: 20Hz throttle
var _haze: GradientTexture2D = null  # pre-rendered rad_haze (HTML PERF note)


func _ready() -> void:
	_bake_haze()


func _bake_haze() -> void:
	var g := Gradient.new()
	g.set_color(0, _HAZE_STOPS[0][1])
	g.set_color(1, _HAZE_STOPS[3][1])
	g.add_point(_HAZE_STOPS[1][0], _HAZE_STOPS[1][1])
	g.add_point(_HAZE_STOPS[2][0], _HAZE_STOPS[2][1])
	_haze = GradientTexture2D.new()
	_haze.gradient = g
	_haze.width = _HAZE_SIZE
	_haze.height = _HAZE_SIZE
	_haze.fill = GradientTexture2D.FILL_RADIAL
	_haze.fill_from = Vector2(0.5, 0.5)
	_haze.fill_to = Vector2(1.0, 0.5)


## HTML-verbatim pulse: 0.55 + 0.45 * sin(now/900 + x * 0.01).
static func pulse_at(t: float, x: float) -> float:
	return 0.55 + 0.45 * sin(t * 1000.0 / 900.0 + x * 0.01)


## HTML-verbatim zone alpha: 0.12 + 0.18 * intensity * pulse * min(1, life/40).
static func zone_alpha(intensity: float, pulse: float, life: float) -> float:
	return 0.12 + 0.18 * intensity * pulse * minf(1.0, life / 40.0)


## HTML sim-verbatim intensity decay, derived from zone age (visual only):
## max(0.15, 1 - age * 0.7). SimNuclear never updates its "intensity" field,
## so the overlay derives it — the visual tracks sim life exactly.
static func zone_intensity(life: float, max_life: float) -> float:
	var age: float = clampf(1.0 - life / maxf(1.0, max_life), 0.0, 1.0)
	return maxf(0.15, 1.0 - age * 0.7)


## HTML sim-verbatim scorch growth, derived from zone age (visual only):
## scorch = min(1, scorch + dt * 0.02)  =>  min(1, age_seconds * 0.02).
static func zone_scorch(life: float, max_life: float) -> float:
	return minf(1.0, (maxf(1.0, max_life) - life) * 0.02)


## HTML-verbatim cull: inView(x, y, r + 40). Pure/static for testability.
static func zone_in_view(zp: Vector2, r: float, view: Rect2) -> bool:
	return view.grow(r + 40.0).has_point(zp)


func _visible_world_rect() -> Rect2:
	var vp: Rect2 = get_viewport_rect()
	var inv: Transform2D = get_canvas_transform().affine_inverse()
	var p0: Vector2 = inv * vp.position
	var p1: Vector2 = inv * (vp.position + vp.size)
	return Rect2(p0, p1 - p0)


func _process(delta: float) -> void:
	_t += delta
	# Jeremy 2026-10-04: throttle radiation redraws 60Hz -> 20Hz.
	_redraw_acc += delta
	if _redraw_acc >= 0.05:
		_redraw_acc = 0.0
		queue_redraw()


func _draw() -> void:
	if nuclear == null:
		return
	if _haze == null:
		_bake_haze()  # lazy fallback: _ready may not fire if added pre-tree
	if _haze == null:
		return
	var view := _visible_world_rect()
	var zones: Array = nuclear.get("zones")
	if zones != null:
		for z: Dictionary in zones:
			_draw_zone(z, view)
	var fo: Dictionary = nuclear.get("fallout")
	if fo != null and not fo.is_empty():
		_draw_fallout(fo, view)
	var rain: Array = []
	if "rain" in nuclear:
		var rarr = nuclear.get("rain")
		if rarr is Array:
			rain = rarr
	if not rain.is_empty():
		_draw_rain(rain, view)


func _draw_zone(z: Dictionary, view: Rect2) -> void:
	var zp := Vector2(float(z.get("x", 0.0)), float(z.get("y", 0.0)))
	# Zone radius tracks the sim (396 -> 828 over the 240 s life).
	var r: float = maxf(1.0, float(z.get("r", 1.0)))
	if not zone_in_view(zp, r, view):
		return
	var life: float = float(z.get("life", 0.0))
	var max_life: float = maxf(1.0, float(z.get("maxLife", 240.0)))
	var intensity: float = zone_intensity(life, max_life)
	var pulse: float = pulse_at(_t, zp.x)
	var a: float = zone_alpha(intensity, pulse, life)
	# Pre-rendered haze sprite, HTML globalAlpha = min(1, a * 1.2).
	draw_set_transform(zp, 0.0,
		Vector2(2.0 * r / _HAZE_SIZE, 2.0 * r * _SQUASH.y / _HAZE_SIZE))
	draw_texture(_haze, Vector2(-_HAZE_SIZE * 0.5, -_HAZE_SIZE * 0.5),
		Color(1.0, 1.0, 1.0, minf(1.0, a * 1.2)))
	# Scorched ring — HTML: rgba(50,40,20, 0.25 * scorch), width 18 * scorch,
	# arc at z.r * 0.55, only when scorch > 0.05.
	var scorch: float = zone_scorch(life, max_life)
	if scorch > 0.05:
		draw_set_transform(zp, 0.0, _SQUASH)
		draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 40,
			Color(_SCORCH_COL.r, _SCORCH_COL.g, _SCORCH_COL.b,
				0.25 * scorch),
			18.0 * scorch)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## HTML "Fallout rain" render block verbatim: small rects, glow color
## #b2ff59 / base #aed581, alpha min(1, life/4). Screen-space motes —
## not ground-squashed (they fall from the sky).
const _RAIN_GLOW := Color(0xB2 / 255.0, 1.0, 0x59 / 255.0)
const _RAIN_BASE := Color(0xAE / 255.0, 0xD5 / 255.0, 0x81 / 255.0)


func _draw_rain(rain: Array, view: Rect2) -> void:
	var cull := view.grow(40.0)
	for d: Dictionary in rain:
		var dp := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		if not cull.has_point(dp):
			continue
		var sz: float = maxf(1.0, float(d.get("size", 2.0)))
		var a: float = minf(1.0, float(d.get("life", 0.0)) / 4.0)
		var col: Color = _RAIN_GLOW if bool(d.get("glow", false)) else _RAIN_BASE
		draw_rect(Rect2(dp, Vector2(sz, sz * 3.0)),
			Color(col.r, col.g, col.b, a))


func _draw_fallout(fo: Dictionary, view: Rect2) -> void:
	var fp := Vector2(float(fo.get("x", 0.0)), float(fo.get("y", 0.0)))
	var fr: float = maxf(1.0, float(fo.get("r", 1.0)))
	if not zone_in_view(fp, fr, view):
		return
	var fl: float = float(fo.get("life", 0.0))
	var fmax: float = maxf(1.0, float(fo.get("maxLife", 1.0)))
	var pulse2: float = pulse_at(_t, fp.x * 1.3)  # slight phase offset vs zones
	var a2: float = 0.10 + 0.14 * pulse2 * (fl / fmax)
	draw_set_transform(fp, 0.0,
		Vector2(2.0 * fr / _HAZE_SIZE, 2.0 * fr * _SQUASH.y / _HAZE_SIZE))
	draw_texture(_haze, Vector2(-_HAZE_SIZE * 0.5, -_HAZE_SIZE * 0.5),
		Color(1.0, 1.0, 1.0, minf(1.0, a2 * 1.2)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
