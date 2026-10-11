class_name Shadows
extends RefCounted
## Cursing Gnomes — sun-driven blob shadows (HTML drawShadowSystem parity).
##
## HTML fix79 ships drawShadowSystem() with a full _sunState() sun model, but
## the function is dead upstream (it opens with `return;`) — the HTML never
## actually draws shadows. This is a Godot-native port that ENABLES the same
## math, because blob shadows ground the chibi sprites on the terrain:
##   - one soft pre-rendered blob blit per mover, offset OPPOSITE the sun
##   - long shadows at dawn/dusk, short at noon (HTML lenF formula verbatim)
##   - alpha fades with sun elevation, zero at night (HTML 0.36*eClamped*2.4)
##   - 34px base height, 80px offset clamp, fp*1.3 x fp*0.85 sizing — HTML
##     putD numbers verbatim.
## Pure visual layer: sim, AI, RNG untouched. Cheap enough for every tier —
## a single stretched texture quad per node, and nodes only queue_redraw()
## when their quantized shadow key actually changes (sun drifts slowly over
## the 8-minute day; moving units redraw as they travel).


## HTML _sunState() ported to Godot's day-phase space (0..1 fraction of the
## 8-minute sim day, the same phase WeatherFX tints by). Sun is up for phase
## in [0.04, 0.60] so the shadow day matches the tint day (dawn 0.04-0.10,
## day 0.10-0.40, dusk 0.40-0.50, early night 0.50-0.60).
static func sun_state_for(phase: float) -> Dictionary:
	# Phase convention matches GameState: 0 = midnight, 0.5 = noon
	# (hour = phase * 24). Sun is up hour 5 -> 21. Jeremy 2026-10-04:
	# fixed stuck-at-night — old band (0.04..0.60) put solar noon at 0.32.
	var hour := phase * 24.0
	var up := hour >= 5.0 and hour <= 21.0
	var day_t := 0.0
	if up:
		day_t = clampf((hour - 5.0) / 16.0, 0.0, 1.0)
	var ang := day_t * PI
	var elev := sin(ang)  # 0 at horizon -> 1 at solar noon; <=0 at night
	var e_clamped := clampf(elev, 0.0, 1.0)
	var sx := cos(ang)  # sun toward: east(+X) dawn -> south(+Y) noon -> west(-X) dusk
	var sy := sin(ang)
	var really_up := up and elev > 0.03
	return {
		"dx": -sx,  # shadow falls opposite the sun
		"dy": -sy,
		"lenF": 0.35 + 1.7 * (1.0 - e_clamped),
		"alpha": (0.36 * minf(1.0, e_clamped * 2.4)) if really_up else 0.0,
		"up": really_up,
	}


## Current cached sun state (updated once per frame by WeatherFX).
static var _phase := 0.25
static var _sun: Dictionary = sun_state_for(0.25)


static func set_phase(p: float) -> void:
	# Jeremy 2026-10-04: skip recompute when phase barely moved — the
	# 8-minute day changes phase by ~0.00035/frame; sun_state_for allocs
	# a Dictionary each call.
	if absf(p - _phase) < 0.0005:
		return
	_phase = p
	_sun = sun_state_for(p)


static func current() -> Dictionary:
	return _sun


## HTML putD offset: sun dir * 34px * lenF, clamped to 80px magnitude.
static func offset_for(sun: Dictionary) -> Vector2:
	var ox: float = float(sun["dx"]) * 34.0 * float(sun["lenF"])
	var oy: float = float(sun["dy"]) * 34.0 * float(sun["lenF"])
	var m := sqrt(ox * ox + oy * oy)
	if m > 80.0:
		ox *= 80.0 / m
		oy *= 80.0 / m
	return Vector2(ox, oy)


## HTML putD alpha: sun.alpha * 0.8.
static func alpha_for(sun: Dictionary, alpha_mul: float = 1.0) -> float:
	return float(sun["alpha"]) * 0.8 * alpha_mul


## Soft blob texture (white RGB, radial alpha falloff), generated once.
static var _blob: Texture2D = null


static func blob_texture() -> Texture2D:
	if _blob != null:
		return _blob
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half).length() / half
			var a := 0.0
			if d < 1.0:
				a = pow(1.0 - d, 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_blob = ImageTexture.create_from_image(img)
	return _blob


## Draw the shadow blob for a node, in the node's local space with the feet
## at the origin (UnitNode/BuildingNode both use feet-at-origin). MUST be
## called from inside CanvasItem._draw().
static func draw_blob(ci: CanvasItem, footprint: float, alpha_mul: float = 1.0) -> void:
	draw_cast(ci, Vector2(footprint * 1.3, footprint * 0.85), alpha_mul)


## Cast shadow with an explicit ground size (width x height in px), shaped to
## the object's footprint. Soft radial falloff, offset opposite the sun, long
## at dawn/dusk, short at noon, fading to zero at night — reads as cast onto
## the ground, not a halo around the object. MUST be called from inside
## CanvasItem._draw(), with the ground point at the local origin.
static func draw_cast(ci: CanvasItem, size: Vector2, alpha_mul: float = 1.0,
		at: Vector2 = Vector2.ZERO) -> void:
	var sun: Dictionary = _sun
	var a := alpha_for(sun, alpha_mul)
	if a <= 0.004:
		return
	var off := offset_for(sun)
	var center := at + off
	var rect := Rect2(center - Vector2(size.x * 0.5, size.y * 0.5), size)
	ci.draw_texture_rect(blob_texture(), rect, false, Color(0, 0, 0, a))


## Water shadows: swimmers rest ON the water, not on the ground — a sun-cast
## blob offset up to 80px at dawn/dusk reads as a floating dark ellipse on
## open water (gate 3: nothing floating). A water shadow is the same soft
## blob PINNED at the waterline under the body, slightly tighter and softer
## (water is translucent; shadows cling). MUST be called from inside
## CanvasItem._draw(), with the waterline point at the local origin.
##
## Pure geometry, no sun state — the rect is always centered on the point,
## which is the testable contract (ground blobs move with the sun).
static func water_shadow_rect(size: Vector2,
		at: Vector2 = Vector2.ZERO) -> Rect2:
	return Rect2(at - size * 0.5, size)


## Pinned water-shadow size for a footprint: HTML putD footprint shaping
## (fp*1.3 x fp*0.85) tightened for the water surface.
const WATER_SHADOW_TIGHTEN := 0.75
static func water_shadow_size(footprint: float) -> Vector2:
	return Vector2(footprint * 1.3, footprint * 0.85) * WATER_SHADOW_TIGHTEN


static func draw_water_shadow(ci: CanvasItem, size: Vector2,
		alpha_mul: float = 1.0, at: Vector2 = Vector2.ZERO) -> void:
	var a := alpha_for(_sun, alpha_mul)
	if a <= 0.004:
		return
	ci.draw_texture_rect(blob_texture(), water_shadow_rect(size, at),
		false, Color(0, 0, 0, a))


## Quantized key for redraw decisions: position to 2px, offset to 2px,
## alpha to 1/32 steps. Nodes store the last key and queue_redraw() on change.
## The swimming bit folds in the shadow MODE (pinned water shadow vs cast
## ground blob) so entering/exiting water swaps the shadow the same frame.
static func shadow_key(pos: Vector2, swimming: bool = false) -> int:
	var sun: Dictionary = _sun
	var off := offset_for(sun)
	var qa := int(float(sun["alpha"]) * 32.0)
	var k := hash(Vector2i(int(pos.x * 0.5), int(pos.y * 0.5)))
	k = k * 31 + hash(Vector2i(int(off.x * 0.5), int(off.y * 0.5)))
	k = k * 31 + qa
	if swimming:
		k = k * 31 + 1
	return k
