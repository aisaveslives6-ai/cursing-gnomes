extends SceneTree
## Cursing Gnomes — weather tint culling (2026-10-04 graphics-hourly).
##
## Full-screen ColorRect tints (_tint, _fog_tint, _temp_tint, _storm_tint)
## cost a full-screen blended pass on the iPhone GPU even at alpha 0.
## They now hide when effectively transparent (alpha <= TINT_HIDE_ALPHA)
## and show again when active — visually identical, and it matches the
## HTML source of truth (fix79 drawWeather, index.html:41722), which only
## paints the full-screen rects when the weather is active.
## Also covers the clear-weather particle-integration skip in
## _update_particles (380 pooled drops/flakes no longer churn dicts when
## nothing is drawn).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_weather_tint_cull.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes weather-tint-cull tests ===")
	_test_tint_hidden_on_clear_day()
	_test_tint_shown_at_night()
	_test_fog_tint_visibility_sync()
	_test_temp_tint_visibility_sync()
	_test_storm_tint_visibility_sync()
	_test_particles_skip_when_clear()
	_test_particles_integrate_when_raining()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var s := SimSeasons.new(gs)
	s.reset()
	gs.seasons = s
	return gs


func _new_fx(gs: GameState) -> WeatherFX:
	var fx := WeatherFX.new()
	root.add_child(fx)
	fx.setup(gs)
	return fx


## ---- day/night tint ------------------------------------------------------

func _test_tint_hidden_on_clear_day() -> void:
	var fx := _new_fx(_new_game())
	# Noon: target alpha is 0 (lighting_mode off by default).
	fx._update_tint(0.5)
	_check("tint: hidden at clear noon", not fx._tint.visible)
	_check("tint: color still transparent at noon",
			fx._tint.color.a <= WeatherFX.TINT_HIDE_ALPHA)
	fx.queue_free()


func _test_tint_shown_at_night() -> void:
	var fx := _new_fx(_new_game())
	# Simulate a night tint already lerped in, then run the sync.
	fx._tint.color = Color(0.05, 0.07, 0.18, 0.55)
	fx._update_tint(0.0)  # midnight: target alpha 0.55
	_check("tint: visible at night", fx._tint.visible)
	fx.queue_free()


## ---- fog / temp tints ----------------------------------------------------

func _test_fog_tint_visibility_sync() -> void:
	var fx := _new_fx(_new_game())
	fx._fog_tint.color = Color(0.706, 0.745, 0.784, 0.20)
	fx._update_atmosphere()
	_check("fog tint: visible when active", fx._fog_tint.visible)
	fx._fog_tint.color = Color(0, 0, 0, 0)
	fx._update_atmosphere()
	_check("fog tint: hidden when transparent", not fx._fog_tint.visible)
	fx.queue_free()


func _test_temp_tint_visibility_sync() -> void:
	var fx := _new_fx(_new_game())
	fx._temp_tint.color = Color(1.0, 0.706, 0.314, 0.05)
	fx._update_atmosphere()
	_check("temp tint: visible when active", fx._temp_tint.visible)
	fx._temp_tint.color = Color(0, 0, 0, 0)
	fx._update_atmosphere()
	_check("temp tint: hidden when transparent", not fx._temp_tint.visible)
	fx.queue_free()


## ---- storm tint ----------------------------------------------------------

func _test_storm_tint_visibility_sync() -> void:
	var fx := _new_fx(_new_game())
	fx.force_weather("storm")
	fx._update_storm(10.0)
	_check("storm tint: visible in storm", fx._storm_tint.visible)
	fx.force_weather("clear")
	fx._update_storm(10.0)
	_check("storm tint: hidden when clear", not fx._storm_tint.visible)
	_check("storm tint: color still fades to transparent",
			fx._storm_tint.color.a < 0.001)
	fx.queue_free()


## ---- particle integration skip -------------------------------------------

func _test_particles_skip_when_clear() -> void:
	var fx := _new_fx(_new_game())
	fx.force_weather("clear")
	fx._flash_alpha = 0.0
	var before: Vector2 = fx._rain[0]["pos"]
	fx._update_particles(0.016)
	_check("particles: rain frozen in clear weather",
			(fx._rain[0]["pos"] as Vector2).is_equal_approx(before))
	var sbefore: Vector2 = fx._snow[0]["pos"]
	fx._update_particles(0.016)
	_check("particles: snow frozen in clear weather",
			(fx._snow[0]["pos"] as Vector2).is_equal_approx(sbefore))
	_check("particles: precip layer hidden when clear",
			not fx._precip.visible)
	fx.queue_free()


func _test_particles_integrate_when_raining() -> void:
	var fx := _new_fx(_new_game())
	fx.force_weather("rain")
	var before: Vector2 = fx._rain[0]["pos"]
	fx._update_particles(0.016)
	var after: Vector2 = fx._rain[0]["pos"]
	_check("particles: rain integrates in rain",
			not after.is_equal_approx(before))
	_check("particles: precip layer visible in rain", fx._precip.visible)
	fx.queue_free()
