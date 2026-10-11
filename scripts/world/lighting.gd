class_name LightingRig
extends Node2D
## Cursing Gnomes — Godot 4 real-time 2D lighting rig.
##
## Jeremy 2026-10-03: "give the game a major graphics update... let's use
## some of these go dot 4 abilities." This is the centerpiece: real 2D
## lighting instead of tint overlays.
##
## - CanvasModulate drives the day/night ambient color. UI is safe: per the
##   Godot docs, CanvasLayers "render independently" of CanvasModulate, so
##   the HUD/phone/menus keep full brightness while the world goes dark.
## - Pooled PointLight2D nodes share one runtime-generated radial texture:
##   warm window lights (night only), flickering fire lights, and one-shot
##   combat/magic flashes. Light counts scale with the graphics tier.
##
## Pure visual: sim, AI, RNG untouched. Works in the gl_compatibility
## renderer (2D lights are supported there; glow/bloom is not, which is why
## this uses real lights instead of WorldEnvironment glow).


## Light budgets per graphics tier: {windows, fires, flashes}.
const TIER_BUDGETS := {
	"ultra": [22, 10, 8],
	"high": [16, 8, 6],
	"medium": [10, 6, 4],
	"low": [6, 4, 3],
}

const WINDOW_COLOR := Color(1.0, 0.72, 0.42)   # lamplight warm
const FIRE_COLOR := Color(1.0, 0.52, 0.18)     # fire orange
const WINDOW_RADIUS := 150.0
const FIRE_RADIUS := 220.0


## Shared radial falloff texture (white core -> transparent edge).
static var _radial_tex: Texture2D = null


static func radial_texture() -> Texture2D:
	if _radial_tex != null and is_instance_valid(_radial_tex):
		return _radial_tex
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(float(x) - half + 0.5,
					float(y) - half + 0.5).length() / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			# Smooth falloff: hot core, gentle edge.
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_radial_tex = ImageTexture.create_from_image(img)
	return _radial_tex


## Ambient canvas color for a day phase (0..1 fraction of the sim day).
## Bands mirror WeatherFX/NightGlow: deep night is dark blue (never pitch
## black, so lights read), dawn/dusk carry warm color, day is white.
## Phase convention matches GameState: 0 = midnight, 0.5 = noon
## (hour = phase * 24). Jeremy 2026-10-04: fixed stuck-at-night — the old
## keyframes assumed 0.25 = noon, so midday rendered dark.
static func ambient_for(phase: float) -> Color:
	var keys: Array = [
		[0.00, Color(0.30, 0.34, 0.52)],
		[0.2083, Color(0.30, 0.34, 0.52)],  # hour 5: last of night
		[0.25, Color(1.00, 0.80, 0.64)],    # hour 6: dawn glow
		[0.2917, Color(1.00, 1.00, 1.00)],  # hour 7: full day
		[0.7917, Color(1.00, 1.00, 1.00)],  # hour 19: last of day
		[0.8333, Color(1.00, 0.72, 0.52)],  # hour 20: dusk glow
		[0.875, Color(0.34, 0.36, 0.55)],   # hour 21: night falls
		[1.01, Color(0.30, 0.34, 0.52)],
	]
	for i in range(keys.size() - 1):
		var t0: float = keys[i][0]
		var t1: float = keys[i + 1][0]
		if phase >= t0 and phase <= t1:
			var k := 0.0
			if t1 > t0:
				k = (phase - t0) / (t1 - t0)
			# Smoothstep the blend so transitions don't band.
			k = k * k * (3.0 - 2.0 * k)
			return (keys[i][1] as Color).lerp(keys[i + 1][1] as Color, k)
	return Color(0.30, 0.34, 0.52)


## 0 at full day, 1 at deep night — drives light energy.
static func night_factor(phase: float) -> float:
	return NightGlow.glow_for(phase)


var _modulate: CanvasModulate = null
var _cam: Camera2D = null
var _tier := "medium"
var _phase := 0.25

var _window_lights: Array[PointLight2D] = []
var _fire_lights: Array[PointLight2D] = []
var _flash_lights: Array = []  # {light, age, life}

var _flicker_t := 0.0

## Jeremy 2026-10-04 (perf): write-skip bookkeeping for set_phase().
## set_phase runs every frame; PointLight2D/CanvasModulate property writes
## dirty canvas items, so redundant writes are pure render-thread churn.
const FLICKER_INTERVAL := 1.0 / 15.0
var _last_w_energy := -1.0  # sentinel: forces the first frame's write
var _flicker_accum := 1.0  # > interval: first flicker quantum fires at once
## Test hooks: count actual canvas-item writes (not set_phase calls).
var _window_writes := 0
var _fire_writes := 0
## _flicker_t value at the most recent flicker quantum (test hook).
var _last_flicker_t := 0.0


func setup(camera: Camera2D, tier: String) -> void:
	_cam = camera
	_tier = tier if TIER_BUDGETS.has(tier) else "medium"
	# Re-setup replaces the pools (never appends): a second setup must not
	# double the light count and the GPU light cost with it.
	if _modulate != null and is_instance_valid(_modulate):
		_modulate.queue_free()
	for l in _window_lights:
		if is_instance_valid(l):
			l.queue_free()
	for l in _fire_lights:
		if is_instance_valid(l):
			l.queue_free()
	for slot in _flash_lights:
		var sl: PointLight2D = slot["light"]
		if is_instance_valid(sl):
			sl.queue_free()
	_window_lights.clear()
	_fire_lights.clear()
	_flash_lights.clear()
	_modulate = CanvasModulate.new()
	_modulate.name = "DayNightAmbient"
	_modulate.color = ambient_for(_phase)
	add_child(_modulate)
	# Jeremy 2026-10-04 (perf): setup() rebuilds the pools, so reset the
	# write-skip state — fresh lights start at energy 0.0 and must take
	# the first frame's write even if w_energy matches the old value.
	_last_w_energy = -1.0
	_flicker_accum = 1.0
	_flicker_t = 0.0
	_last_flicker_t = 0.0
	_window_writes = 0
	_fire_writes = 0
	var budgets: Array = TIER_BUDGETS[_tier]
	_build_pool(_window_lights, int(budgets[0]), WINDOW_COLOR, WINDOW_RADIUS)
	_build_pool(_fire_lights, int(budgets[1]), FIRE_COLOR, FIRE_RADIUS)
	for i in range(int(budgets[2])):
		var l := _make_light(Color.WHITE, 160.0)
		l.visible = false
		_flash_lights.append({"light": l, "age": 0.0, "life": 0.0})


func _build_pool(pool: Array[PointLight2D], n: int, color: Color,
		radius: float) -> void:
	for i in range(n):
		var l := _make_light(color, radius)
		l.visible = false
		pool.append(l)


func _make_light(color: Color, radius: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = radial_texture()
	l.color = color
	# Texture is 128px: scale so the radius matches.
	l.texture_scale = radius / 64.0
	l.energy = 0.0
	l.shadow_enabled = false
	add_child(l)
	return l


## Per-frame: ease the ambient toward the phase target, flicker fires,
## expire flashes, cull off-screen lights.
func set_phase(phase: float, delta: float) -> void:
	_phase = phase
	if _modulate != null:
		# Jeremy 2026-10-04 (perf): the lerp never lands exactly on the
		# target, so the old code wrote every frame forever. Settle once
		# the color is indistinguishable from the target instead.
		var target := ambient_for(phase)
		if not _modulate.color.is_equal_approx(target):
			_modulate.color = _modulate.color.lerp(target,
					minf(1.0, delta * 2.0))
	_flicker_t += delta
	var nf := night_factor(phase)
	# Window lights only matter once it's actually dark.
	var w_energy := 1.1 * clampf((nf - 0.25) / 0.75, 0.0, 1.0)
	# Jeremy 2026-10-04 (perf): was a redundant write to EVERY pooled
	# light EVERY frame, even while w_energy sat at a stable 0.0 (day) or
	# 1.1 (night). Write all lights only when the value actually changed;
	# the old "no dark frame" invariant holds because every light always
	# carries the last written value (the -1.0 sentinel forces frame one).
	if not is_equal_approx(w_energy, _last_w_energy):
		for l in _window_lights:
			l.energy = w_energy
			_window_writes += 1
		_last_w_energy = w_energy
	# Fire flicker: candle-like, deterministic per light index.
	# Jeremy 2026-10-04 (perf): sampled at 15 Hz instead of 60 Hz — a
	# 13 rad/s flicker gets ~7 samples per period at 15 Hz, visually
	# identical, 4x fewer sin() calls and canvas-item writes. _flicker_t
	# still advances every frame so the sampled pose stays exact.
	_flicker_accum += delta
	if _flicker_accum >= FLICKER_INTERVAL:
		_flicker_accum = 0.0
		_last_flicker_t = _flicker_t
		for i in range(_fire_lights.size()):
			var fl := _fire_lights[i]
			fl.energy = 1.15 + 0.35 * sin(_flicker_t * 13.0 + float(i) * 2.399)
			_fire_writes += 1
	# Expire one-shot flashes.
	for slot in _flash_lights:
		if float(slot["life"]) <= 0.0:
			continue
		slot["age"] = float(slot["age"]) + delta
		var k: float = clampf(float(slot["age"]) / float(slot["life"]),
				0.0, 1.0)
		var li: PointLight2D = slot["light"]
		li.energy = 2.2 * (1.0 - k)
		if k >= 1.0:
			slot["life"] = 0.0
			li.visible = false


## Warm window lights at building positions (world space). Called ~2Hz by
## the world with in-view buildings; extra slots park invisible.
func set_window_positions(positions: PackedVector2Array) -> void:
	_assign_pool(_window_lights, positions)


## Fire lights at fire positions (world space).
func set_fire_positions(positions: PackedVector2Array) -> void:
	_assign_pool(_fire_lights, positions)


func _assign_pool(pool: Array[PointLight2D],
		positions: PackedVector2Array) -> void:
	var n := mini(pool.size(), positions.size())
	for i in range(pool.size()):
		var l := pool[i]
		if i < n and _in_view(positions[i], 200.0):
			l.position = positions[i]
			l.visible = true
		else:
			l.visible = false


## One-shot light burst (combat hits, spells, explosions).
func flash(pos: Vector2, color: Color, radius: float = 170.0,
		life: float = 0.28) -> void:
	for slot in _flash_lights:
		if float(slot["life"]) > 0.0:
			continue
		var l: PointLight2D = slot["light"]
		l.position = pos
		l.color = color
		l.texture_scale = radius / 64.0
		l.energy = 2.2
		l.visible = true
		slot["age"] = 0.0
		slot["life"] = life
		return
	# Pool exhausted: steal the oldest flash.
	var oldest: Dictionary = _flash_lights[0]
	for slot in _flash_lights:
		if float(slot["age"]) > float(oldest["age"]):
			oldest = slot
	var ol: PointLight2D = oldest["light"]
	ol.position = pos
	ol.color = color
	ol.texture_scale = radius / 64.0
	ol.energy = 2.2
	ol.visible = true
	oldest["age"] = 0.0
	oldest["life"] = life


func _in_view(pos: Vector2, margin: float) -> bool:
	if _cam == null:
		return true
	var vs := get_viewport_rect().size
	var center := _cam.get_screen_center_position()
	var half := vs / maxf(_cam.zoom.x, 0.01) * 0.5 + Vector2(margin, margin)
	return absf(pos.x - center.x) <= half.x \
		and absf(pos.y - center.y) <= half.y


## Test hook: how many pooled lights are currently visible.
func visible_light_count() -> int:
	var n := 0
	for l in _window_lights:
		if l.visible:
			n += 1
	for l in _fire_lights:
		if l.visible:
			n += 1
	for slot in _flash_lights:
		if float(slot["life"]) > 0.0:
			n += 1
	return n
