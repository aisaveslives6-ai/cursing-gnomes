class_name WeatherFX
extends Node2D
## Cursing Gnomes — weather visuals + day/night polish (Milestone 7).
##
## Pure visual layer over the sim clock (GameState.game_time / is_night).
##   - Day/night: smooth canvas tint that lerps with the day phase —
##     warm dawn, bright noon, orange dusk, dark blue night.
##   - Weather: rain and snow particle systems with fixed budgets
##     (60fps rule — pooled, never allocate during weather).
##   - Weather state changes on a slow timer (clear -> rain -> clear...).
##
## Add as a child of the world root; it sizes itself to the viewport.


signal weather_changed(kind: String)  # "clear" | "rain" | "storm" | "snow"
signal lightning_struck  # fired on every bolt (audio syncs thunder to this)

# Particle budgets (fixed pools).
const RAIN_DROPS := 220
const SNOW_FLAKES := 160

## Graphics-tier particle multiplier (HTML particleMul parity): scales how
## many pooled drops/flakes are active. 1.0 = full pools.
var particle_mul := 1.0


func set_particle_mul(m: float) -> void:
	particle_mul = clampf(m, 0.05, 1.0)

var game: GameState
var _tint: ColorRect
## Jeremy 2026-10-03: weather must show in the sim graphics. HTML weather
## overlay parity (verbatim colors):
##   - fog: rgba(180,190,200,0.2) screen mist
##   - cold (temp < 35F): rgba(150,200,255,0.06)
##   - hot (temp > 88F): rgba(255,180,80,0.05)
##   - storm: rgba(40,50,70,0.16) dark sky (HTML drawWeather verbatim)
var _fog_tint: ColorRect
var _temp_tint: ColorRect
var _storm_tint: ColorRect
var _fx_layer: CanvasLayer = null
const FOG_COLOR := Color(0.706, 0.745, 0.784, 0.20)
const COLD_COLOR := Color(0.588, 0.784, 1.0, 0.06)
const HOT_COLOR := Color(1.0, 0.706, 0.314, 0.05)
const STORM_SKY_COLOR := Color(0.157, 0.196, 0.275, 0.16)
## Storm rain streaks (HTML drawWeather verbatim: rgba(180,200,255,0.4),
## lineWidth 1.5 vs rain's rgba(160,190,255,0.28), lineWidth 1). The port
## draws thicker base strokes, so the storm pass scales up in kind.
const STORM_RAIN_COLOR := Color(0.706, 0.784, 1.0, 0.65)
const STORM_SLANT := Vector2(-3.2, 18.0)
const STORM_WIDTH := 3.0
const RAIN_COLOR := Color(0.5, 0.7, 1.0, 0.55)
const RAIN_SLANT := Vector2(-1.7, 14.0)
const RAIN_WIDTH := 2.0
## Lightning flash (HTML drawWeather verbatim: rgba(255,255,255,0.25)
## full-screen, ~2% chance per frame -> ~1.2 strikes/sec at 60fps).
const FLASH_ALPHA := 0.25
const FLASH_FADE_SECS := 0.25
const STRIKE_RATE := 1.2

## 2026-10-04 perf: alpha below this hides a full-screen tint ColorRect.
## A zero-alpha blended quad still costs a full-screen pass on the iPhone
## GPU (tile read-modify-write); hiding it removes the draw + fill cost
## entirely. Visually identical — alpha ~0 contributes nothing — and it
## matches the HTML source of truth (fix79 drawWeather, index.html:41722),
## which only paints the full-screen rects when the weather is active.
const TINT_HIDE_ALPHA := 0.004
## Jagged bolt shape (HTML mage idiom: jagged, re-rolled).
const BOLT_SEGS := 12
const BOLT_WANDER := 46.0
## Lightning state (storm only): flash envelope + bolt polylines, all drawn
## inside the single _PrecipDraw canvas item — zero extra nodes.
var _flash_alpha := 0.0
var _bolt := PackedVector2Array()
var _branch := PackedVector2Array()
var _rain: Array = []   # Dictionaries {pos, vel} — drawn by _precip
var _snow: Array = []   # Dictionaries {pos, vel, phase} — drawn by _precip
var _precip: _PrecipDraw = null
var _weather := "clear"
var _weather_timer := 0.0
var _weather_duration := 90.0
var _rng := RandomNumberGenerator.new()

## Lighting-rig mode (Jeremy 2026-10-03 graphics update): when the world's
## LightingRig is active, CanvasModulate owns the day/night darkening, so
## the tint overlay drops to a subtle color grade (30% alpha) instead of
## double-darkening the scene. Default off = legacy standalone behavior.
var lighting_mode := false


func set_lighting_mode(on: bool) -> void:
	lighting_mode = on


## Inner draw node — ALL precipitation in one canvas item (one draw call)
## instead of ~380 Line2D nodes. Lives in the screen-space FX layer so
## rain/snow cover the viewport no matter where the camera is.
class _PrecipDraw:
	extends Node2D
	var fx: WeatherFX = null

	func _draw() -> void:
		if fx == null:
			return
		var storm := fx._weather == "storm"
		if fx._weather == "rain" or storm:
			var n := mini(fx._rain.size(),
					int(float(WeatherFX.RAIN_DROPS) * fx.particle_mul))
			var col: Color = WeatherFX.STORM_RAIN_COLOR if storm \
					else WeatherFX.RAIN_COLOR
			var slant: Vector2 = WeatherFX.STORM_SLANT if storm \
					else WeatherFX.RAIN_SLANT
			var w: float = WeatherFX.STORM_WIDTH if storm \
					else WeatherFX.RAIN_WIDTH
			for i in range(n):
				var p: Vector2 = (fx._rain[i] as Dictionary)["pos"]
				draw_line(p, p + slant, col, w)
		elif fx._weather == "snow":
			var n := mini(fx._snow.size(),
					int(float(WeatherFX.SNOW_FLAKES) * fx.particle_mul))
			var col := Color(1, 1, 1, 0.8)
			for i in range(n):
				var p: Vector2 = (fx._snow[i] as Dictionary)["pos"]
				draw_circle(p, 2.5, col)
		# Lightning: HTML-verbatim full-screen flash plus a jagged bolt
		# re-rolled on every strike. Drawn last, above the rain.
		if fx._flash_alpha > 0.003:
			var vs := fx.get_viewport_rect().size
			draw_rect(Rect2(Vector2.ZERO, vs),
					Color(1, 1, 1, fx._flash_alpha))
			if fx._bolt.size() > 1:
				draw_polyline(fx._bolt, Color(0.85, 0.92, 1.0, 0.25), 6.0)
				draw_polyline(fx._bolt, Color(0.95, 0.97, 1.0, 0.90), 2.5)
			if fx._branch.size() > 1:
				draw_polyline(fx._branch, Color(0.90, 0.94, 1.0, 0.70), 1.5)


func setup(p_game: GameState) -> void:
	game = p_game
	_rng.seed = 1234567
	_build_tint()
	_build_pools()
	set_process(true)


func _build_tint() -> void:
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.color = Color(0, 0, 0, 0)
	# ColorRect is a Control; parent under a CanvasLayer for screen space.
	var layer := CanvasLayer.new()
	layer.layer = -5  # under HUD, over world
	layer.add_child(_tint)
	# Weather atmosphere overlays (HTML weather-overlay parity): fog mist
	# and cold/hot screen edges sit under the day/night tint.
	_fog_tint = ColorRect.new()
	_fog_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_tint.color = Color(0, 0, 0, 0)
	layer.add_child(_fog_tint)
	_temp_tint = ColorRect.new()
	_temp_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_temp_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_temp_tint.color = Color(0, 0, 0, 0)
	layer.add_child(_temp_tint)
	# Storm dark sky (HTML 'rgba(40,50,70,0.16)' verbatim): sits above the
	# fog/temp tints, below the day/night grade.
	_storm_tint = ColorRect.new()
	_storm_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_storm_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm_tint.color = Color(0, 0, 0, 0)
	layer.add_child(_storm_tint)
	# Push the atmosphere layers below the day/night tint within the layer.
	layer.move_child(_fog_tint, 0)
	layer.move_child(_temp_tint, 1)
	layer.move_child(_storm_tint, 2)
	_fx_layer = layer
	# Precipitation draws in screen space above the tint (one draw call).
	_precip = _PrecipDraw.new()
	_precip.fx = self
	_precip.z_index = 10
	layer.add_child(_precip)
	add_child(layer)


func _build_pools() -> void:
	for i in RAIN_DROPS:
		_rain.append({"pos": Vector2.ZERO, "vel": Vector2(-60, 700)})
	for i in SNOW_FLAKES:
		_snow.append({"pos": Vector2.ZERO, "vel": Vector2(20, 90),
				"phase": _rng.randf() * TAU})


func _viewport_size() -> Vector2:
	# Headless test default: suites drive _update_* directly without a frame.
	if not is_inside_tree():
		return Vector2(1280, 720)
	return get_viewport_rect().size


func _recycle(slot: Dictionary, top: bool) -> void:
	var vs := _viewport_size()
	var pos: Vector2 = slot["pos"]
	if top or pos.y > vs.y + 20.0 or pos.x < -20.0 or pos.x > vs.x + 20.0:
		slot["pos"] = Vector2(_rng.randf() * vs.x, -20.0)


func _process(delta: float) -> void:
	if game == null:
		return
	var phase := _day_phase()
	# Feed the day phase to the shadow system so blob shadows track the sun
	# with the same clock the day/night tint uses.
	Shadows.set_phase(phase)
	# Same clock for building window glow so lit windows fade in as the
	# tint goes dark.
	NightGlow.set_phase(phase)
	_update_tint(phase)
	_update_weather_state(delta)
	_update_atmosphere()
	_update_storm(delta)
	_update_particles(delta)


func _day_phase() -> float:
	# Fractions of the current sim day (mirrors Config.DAY_LENGTH_SECONDS,
	# the 8-minute cycle, so visuals stay in sync with the economy tick).
	return fmod(game.game_time, Config.DAY_LENGTH_SECONDS) \
		/ Config.DAY_LENGTH_SECONDS


func _tint_target_for(phase: float) -> Color:
	# Key colors through the day. Phase convention matches GameState:
	# 0 = midnight, 0.5 = noon (hour = phase * 24). Jeremy 2026-10-04:
	# fixed stuck-at-night — old bands assumed 0.25 = noon.
	var hour := phase * 24.0
	var c: Color
	if hour < 5.0 or hour > 21.0:
		c = Color(0.05, 0.07, 0.18, 0.55)   # deep night
	elif hour < 6.5:
		c = Color(0.35, 0.18, 0.10, 0.28)   # dawn
	elif hour < 19.0:
		c = Color(0, 0, 0, 0)                # day
	else:
		c = Color(0.30, 0.12, 0.05, 0.30)   # dusk
	if lighting_mode:
		# The LightingRig's CanvasModulate owns the darkening; keep only a
		# subtle color grade so the scene doesn't double-darken.
		c.a *= 0.30
	return c


func _update_tint(phase: float) -> void:
	var c := _tint_target_for(phase)
	# Smooth: lerp toward target.
	_tint.color = _tint.color.lerp(c, minf(1.0, get_process_delta_time() * 2.0))
	# Hide at ~zero alpha (clear day): skips a wasted full-screen pass.
	_tint.visible = _tint.color.a > TINT_HIDE_ALPHA


func _update_weather_state(delta: float) -> void:
	# When the seasons sim exists (Milestone 6b), mirror its weather — the
	# fantasy calendar is the single source of truth for conditions. The
	# six sim conditions map onto the four visual states.
	var seas = game.get("seasons")
	if seas != null:
		var sw: String = String(seas.weather)
		var mapped := "clear"
		if sw == "rain":
			mapped = "rain"
		elif sw == "storm":
			mapped = "storm"
		elif sw == "snow":
			mapped = "snow"
		if mapped != _weather:
			_weather = mapped
			weather_changed.emit(_weather)
		return
	# Fallback (pre-seasons / standalone): the old slow timer.
	_weather_timer += delta
	if _weather_timer < _weather_duration:
		return
	_weather_timer = 0.0
	_weather_duration = 75.0 + _rng.randf() * 90.0
	# Snow only at "night" for variety; storms favor the day.
	var roll := _rng.randf()
	var next := "clear"
	if roll < 0.26:
		next = "rain"
	elif roll < 0.34:
		next = "storm"
	elif roll < 0.42 and game.is_night:
		next = "snow"
	if next != _weather:
		_weather = next
		weather_changed.emit(_weather)


## Weather atmosphere: fog mist + cold/hot screen edges from the live sim
## (HTML weather-overlay parity, verbatim colors). Reads game.seasons when
## present; fades out when the sim isn't attached.
func _atmosphere_targets() -> Array:
	var fog_target := Color(0, 0, 0, 0)
	var temp_target := Color(0, 0, 0, 0)
	var seas = game.get("seasons") if game != null else null
	if seas != null:
		if String(seas.weather) == "fog":
			fog_target = FOG_COLOR
		var t: float = float(seas.temperature)
		if t < 35.0:
			temp_target = COLD_COLOR
		elif t > 88.0:
			temp_target = HOT_COLOR
	return [fog_target, temp_target]


func _update_atmosphere() -> void:
	var tg: Array = _atmosphere_targets()
	var k: float = minf(1.0, get_process_delta_time() * 2.0)
	if _fog_tint != null:
		_fog_tint.color = _fog_tint.color.lerp(tg[0], k)
		_fog_tint.visible = _fog_tint.color.a > TINT_HIDE_ALPHA
	if _temp_tint != null:
		_temp_tint.color = _temp_tint.color.lerp(tg[1], k)
		_temp_tint.visible = _temp_tint.color.a > TINT_HIDE_ALPHA


## Storm visuals: HTML-verbatim dark sky tint + lightning strikes.
func _update_storm(delta: float) -> void:
	var target := Color(0, 0, 0, 0)
	if _weather == "storm":
		target = STORM_SKY_COLOR
	var k := minf(1.0, delta * 2.0)
	if _storm_tint != null:
		_storm_tint.color = _storm_tint.color.lerp(target, k)
		_storm_tint.visible = _storm_tint.color.a > TINT_HIDE_ALPHA
	# Lightning strikes (HTML ~2%/frame -> STRIKE_RATE/sec); each strike
	# re-rolls a jagged bolt (HTML mage idiom).
	if _weather == "storm" and _rng.randf() < STRIKE_RATE * delta:
		_trigger_flash(_viewport_size())
	_update_flash(delta)


## Fire a lightning strike: full-screen flash + freshly rolled bolt.
func _trigger_flash(vs: Vector2) -> void:
	_flash_alpha = FLASH_ALPHA
	_bolt = _gen_bolt(vs)
	lightning_struck.emit()
	# One fork off the bolt, partway down.
	if _bolt.size() > 4:
		_branch = _gen_branch(_bolt, 2 + _rng.randi_range(0, 2))
	else:
		_branch = PackedVector2Array()


## Jagged bolt polyline: cloud top to mid-sky, x wandering per segment.
func _gen_bolt(vs: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := _rng.randf_range(vs.x * 0.15, vs.x * 0.85)
	var target_y := vs.y * _rng.randf_range(0.55, 0.85)
	pts.append(Vector2(x, -10.0))
	for i in range(1, BOLT_SEGS + 1):
		var y := lerpf(-10.0, target_y, float(i) / float(BOLT_SEGS))
		x += _rng.randf_range(-BOLT_WANDER, BOLT_WANDER)
		pts.append(Vector2(x, y))
	return pts


## Side fork: 5 jagged segments off a bolt node, drifting down/outward.
func _gen_branch(bolt: PackedVector2Array, at: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var p: Vector2 = bolt[clampi(at, 0, bolt.size() - 1)]
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	pts.append(p)
	for i in range(5):
		p += Vector2(dir * _rng.randf_range(18.0, 40.0),
				_rng.randf_range(24.0, 52.0))
		pts.append(p)
	return pts


## Flash envelope decay; clears the bolt when the flash is gone.
func _update_flash(delta: float) -> void:
	if _flash_alpha <= 0.0:
		return
	_flash_alpha = maxf(0.0,
			_flash_alpha - FLASH_ALPHA * delta / FLASH_FADE_SECS)
	if _flash_alpha <= 0.0:
		_bolt = PackedVector2Array()
		_branch = PackedVector2Array()


func _update_particles(delta: float) -> void:
	# Positions live in screen space (the _precip node draws in the FX
	# CanvasLayer). Tier-scaled counts gate how many of the pool are live.
	var rain_on := _weather == "rain"
	var snow_on := _weather == "snow"
	var storm_on := _weather == "storm"
	var precip_on := rain_on or snow_on or storm_on
	# 2026-10-04 perf: in clear weather nothing draws, so skip integrating
	# all 380 pooled drops/flakes (pure dictionary churn every frame).
	# Drops resume from their last fall paths when precipitation returns;
	# the per-frame bounds recycle redistributes them within a frame or two.
	if precip_on:
		for d in _rain:
			var pos: Vector2 = d["pos"]
			var vel: Vector2 = d["vel"]
			if storm_on:
				# HTML: storm x-drift 50 vs rain 18 — gusty, heavily slanted.
				vel.x -= 110.0
				vel.y += 100.0
			pos += vel * delta
			d["pos"] = pos
			_recycle(d, false)
		for s in _snow:
			var pos2: Vector2 = s["pos"]
			var vel2: Vector2 = s["vel"]
			var ph: float = float(s["phase"]) + delta
			s["phase"] = ph
			pos2 += vel2 * delta + Vector2(sin(ph * 2.0) * 30.0 * delta, 0)
			s["pos"] = pos2
			_recycle(s, false)
	# One draw call for all precipitation; invisible when clear.
	if _precip != null:
		_precip.visible = precip_on or _flash_alpha > 0.003
		if _precip.visible:
			_precip.queue_redraw()


## Current weather kind (for tests / HUD).
func current_weather() -> String:
	return _weather


## Force a weather kind (tests, debug).
func force_weather(kind: String) -> void:
	_weather = kind
	_weather_timer = 0.0
	weather_changed.emit(_weather)
