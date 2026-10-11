class_name NightGlow
extends RefCounted
## Cursing Gnomes — building window glow at night (Godot-native atmosphere).
##
## No HTML precedent: fix79's night is only a screen tint — the HTML never
## lights windows. The Godot build gives buildings warm lit windows and a
## soft lamplight halo after dark so towns read as alive at night, on the
## same day-phase clock WeatherFX tints by (WeatherFX feeds set_phase() once
## per frame next to Shadows.set_phase()). Pure visual: sim, AI, RNG
## untouched. Nodes only queue_redraw() when their quantized glow key
## changes, so the day game costs nothing.


## Night intensity 0..1 for a day phase (0..1 fraction of the 8-minute sim
## day). Bands mirror WeatherFX._update_tint: deep night 1.0, dawn ramps
## 0.85->0, day 0, dusk ramps 0->0.85, early night 0.85, night 1.0.
static func glow_for(phase: float) -> float:
	# Phase convention matches GameState: 0 = midnight, 0.5 = noon
	# (hour = phase * 24). Night when hour < 5 or hour > 21, same as
	# GameState.is_night. Jeremy 2026-10-04: fixed stuck-at-night — the
	# old bands assumed 0.25 = noon, so midday rendered as night.
	var hour := phase * 24.0
	if hour < 5.0 or hour > 21.0:
		return 1.0
	if hour < 6.5:
		# Dawn: fade 1.0 -> 0.0 across hour 5 -> 6.5.
		return 1.0 - (hour - 5.0) / 1.5
	if hour < 19.0:
		return 0.0
	# Dusk: fade 0.0 -> 1.0 across hour 19 -> 21.
	return (hour - 19.0) / 2.0


## Candle-like flicker 0.8..1.0, deterministic per building id so it needs
## no RNG and stays stable across frames for a given phase.
static func flicker_for(phase: float, id: int) -> float:
	return 0.90 + 0.10 * sin(phase * 251.0 + float(id) * 2.399)


## Current cached glow (updated once per frame by WeatherFX).
static var _phase := 0.25
static var _glow := 0.0


static func set_phase(p: float) -> void:
	# Jeremy 2026-10-04: skip recompute when phase barely moved (see
	# Shadows.set_phase — same 8-minute-day reasoning).
	if absf(p - _phase) < 0.0005:
		return
	_phase = p
	_glow = glow_for(p)


static func current() -> float:
	return _glow


## Warm window-light color; alpha baked by the caller.
static func window_color() -> Color:
	return Color(1.0, 0.81, 0.49)


## Draw the night glow for a building in its local space (feet at origin).
## footprint = BuildingNode._size_for(btype). Windows only on programmer-art
## silhouettes (window=True); sprite-art buildings get the halo + lit door.
## Walls and blueprints never glow. MUST be called from inside _draw().
static func draw_glow(ci: CanvasItem, id: int, footprint: float, window: bool,
		door := true) -> void:
	var g := _glow * flicker_for(_phase, id)
	if g <= 0.004:
		return
	var halo := Color(1.0, 0.72, 0.36, g * 0.14)
	var r := footprint * 1.7
	ci.draw_circle(Vector2(0, -footprint * 0.7), r, halo)
	var wc := window_color()
	wc.a = g * 0.95
	if window:
		# Two lit windows on the box face.
		var ws := 10.0
		ci.draw_rect(Rect2(-footprint * 0.30 - ws / 2, -footprint * 0.35 - 6,
			ws, 12), wc)
		ci.draw_rect(Rect2(footprint * 0.22 - ws / 2, -footprint * 0.35 - 6,
			ws, 12), wc)
	# Lit doorway spilling light (matches the dark door rect in BuildingNode:
	# both sit at the ground point since the 2026-10-05 grounding pass).
	# Skipped for flat/non-box types (no wall face for a door).
	if door:
		ci.draw_rect(Rect2(-3.5, -14.0, 7, 12), wc)


## Quantized key for redraw decisions: glow*flicker to 1/32 steps, hashed
## with the building id (flicker is per-id, so two lit buildings can differ).
## Nodes store the last key and queue_redraw() on change.
static func glow_key(id: int) -> int:
	var g := _glow * flicker_for(_phase, id)
	return hash(id) * 31 + int(g * 32.0)
