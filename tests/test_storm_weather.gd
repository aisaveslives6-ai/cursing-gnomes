extends SceneTree
## Cursing Gnomes — thunderstorm visuals (HTML 'storm' weather parity).
##
## Jeremy's ask: storms must LOOK like storms, not plain rain. fix79's
## drawWeather gives storm its own pass:
##   - sky tint rgba(40,50,70,0.16) (vs rain rgba(60,80,100,0.1))
##   - heavier bluer rain: rgba(180,200,255,0.4), lineWidth 1.5
##     (vs rain rgba(160,190,255,0.28), lineWidth 1)
##   - lightning: full-screen rgba(255,255,255,0.25) flash, ~2%/frame
## The Godot port previously collapsed sim "storm" into plain "rain".
## This suite covers the distinct storm visual state, HTML-verbatim
## colors, flash/bolt mechanics, and mapping regressions.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_storm_weather.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes storm-weather tests ===")
	_test_sim_storm_maps_to_storm()
	_test_other_conditions_map()
	_test_storm_signal()
	_test_storm_sky_color_verbatim()
	_test_storm_streak_params_heavier_than_rain()
	_test_trigger_flash()
	_test_flash_decay_clears_bolt()
	_test_bolt_shape()
	_test_bolt_deterministic_per_seed()
	_test_branch_shape()
	_test_storm_tint_lerps_in()
	_test_storm_tint_fades_out()
	_test_precip_visible_in_storm()
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


## ---- sim -> visual mapping ----------------------------------------------

func _test_sim_storm_maps_to_storm() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	gs.seasons.weather = "storm"
	fx._update_weather_state(0.1)
	_check("storm: sim storm maps to visual storm", fx.current_weather() == "storm")


func _test_other_conditions_map() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	gs.seasons.weather = "rain"
	fx._update_weather_state(0.1)
	_check("storm: rain still maps to rain", fx.current_weather() == "rain")
	gs.seasons.weather = "snow"
	fx._update_weather_state(0.1)
	_check("storm: snow still maps to snow", fx.current_weather() == "snow")
	gs.seasons.weather = "cloudy"
	fx._update_weather_state(0.1)
	_check("storm: cloudy maps to clear", fx.current_weather() == "clear")
	gs.seasons.weather = "fog"
	fx._update_weather_state(0.1)
	_check("storm: fog maps to clear", fx.current_weather() == "clear")


func _test_storm_signal() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	var got := []
	fx.weather_changed.connect(func(kind: String) -> void: got.append(kind))
	fx.force_weather("storm")
	_check("storm: signal emits storm", got == ["storm"])


## ---- HTML-verbatim visuals ------------------------------------------------

func _test_storm_sky_color_verbatim() -> void:
	# HTML drawWeather: 'rgba(40,50,70,0.16)'
	var c := WeatherFX.STORM_SKY_COLOR
	_check("storm: sky r verbatim", absf(c.r - 40.0 / 255.0) < 0.002)
	_check("storm: sky g verbatim", absf(c.g - 50.0 / 255.0) < 0.002)
	_check("storm: sky b verbatim", absf(c.b - 70.0 / 255.0) < 0.002)
	_check("storm: sky alpha verbatim", absf(c.a - 0.16) < 0.002)


func _test_storm_streak_params_heavier_than_rain() -> void:
	# HTML: storm streaks rgba(180,200,255,0.4) w1.5 vs rain
	# rgba(160,190,255,0.28) w1 — storm must read heavier.
	# HTML: storm streaks rgba(180,200,255,0.4) w1.5 vs rain
	# rgba(160,190,255,0.28) w1 — storm must read heavier/brighter.
	_check("storm: streak brighter than rain",
			(WeatherFX.STORM_RAIN_COLOR.r + WeatherFX.STORM_RAIN_COLOR.g \
			+ WeatherFX.STORM_RAIN_COLOR.b) \
			> (WeatherFX.RAIN_COLOR.r + WeatherFX.RAIN_COLOR.g \
			+ WeatherFX.RAIN_COLOR.b))
	_check("storm: streak more opaque than rain",
			WeatherFX.STORM_RAIN_COLOR.a > WeatherFX.RAIN_COLOR.a)
	_check("storm: streak wider than rain",
			WeatherFX.STORM_WIDTH > WeatherFX.RAIN_WIDTH)
	_check("storm: slant longer than rain",
			WeatherFX.STORM_SLANT.length() > WeatherFX.RAIN_SLANT.length())
	# Verbatim HTML storm streak color rgba(180,200,255,0.4) is the floor.
	_check("storm: streak rgb verbatim",
			absf(WeatherFX.STORM_RAIN_COLOR.r - 180.0 / 255.0) < 0.003 \
			and absf(WeatherFX.STORM_RAIN_COLOR.g - 200.0 / 255.0) < 0.003 \
			and absf(WeatherFX.STORM_RAIN_COLOR.b - 1.0) < 0.003)


## ---- lightning ------------------------------------------------------------

func _test_trigger_flash() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	fx._trigger_flash(Vector2(800, 600))
	# HTML flash alpha verbatim 0.25.
	_check("storm: flash alpha verbatim",
			absf(fx._flash_alpha - 0.25) < 0.001)
	_check("storm: bolt has segs+1 points",
			fx._bolt.size() == WeatherFX.BOLT_SEGS + 1)
	_check("storm: branch generated", fx._branch.size() == 6)


func _test_flash_decay_clears_bolt() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	fx._trigger_flash(Vector2(800, 600))
	# HTML fade: full fade over FLASH_FADE_SECS.
	fx._update_flash(WeatherFX.FLASH_FADE_SECS)
	_check("storm: flash fully faded", fx._flash_alpha <= 0.001)
	_check("storm: bolt cleared after fade", fx._bolt.is_empty())
	_check("storm: branch cleared after fade", fx._branch.is_empty())
	# Partial fade is proportional.
	fx._trigger_flash(Vector2(800, 600))
	fx._update_flash(WeatherFX.FLASH_FADE_SECS * 0.5)
	_check("storm: flash half-faded proportionally",
			absf(fx._flash_alpha - 0.125) < 0.02)


func _test_bolt_shape() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	var vs := Vector2(900, 700)
	var bolt := fx._gen_bolt(vs)
	_check("storm: bolt count", bolt.size() == WeatherFX.BOLT_SEGS + 1)
	_check("storm: bolt starts at cloud top", bolt[0].y <= -10.0)
	_check("storm: bolt ends mid-sky",
			bolt[bolt.size() - 1].y > vs.y * 0.5 \
			and bolt[bolt.size() - 1].y < vs.y * 0.9)
	_check("storm: bolt descends monotonically",
			_monotonic_desc(bolt))
	# Jagged: x wanders back and forth, not a straight line.
	var x_min := 1e9
	var x_max := -1e9
	for p in bolt:
		x_min = minf(x_min, p.x)
		x_max = maxf(x_max, p.x)
	_check("storm: bolt jagged (x wanders)", x_max - x_min > 40.0)
	_check("storm: bolt starts across top",
			bolt[0].x > vs.x * 0.1 and bolt[0].x < vs.x * 0.9)


func _monotonic_desc(bolt: PackedVector2Array) -> bool:
	for i in range(1, bolt.size()):
		if bolt[i].y < bolt[i - 1].y:
			return false
	return true


func _test_bolt_deterministic_per_seed() -> void:
	# Same seed -> same bolt: no frame-to-frame shimmer, clean strike look.
	var gs1 := _new_game()
	var fx1 := _new_fx(gs1)
	var gs2 := _new_game()
	var fx2 := _new_fx(gs2)
	var vs := Vector2(800, 600)
	var b1 := fx1._gen_bolt(vs)
	var b2 := fx2._gen_bolt(vs)
	var same := b1.size() == b2.size()
	for i in range(b1.size()):
		if not b1[i].is_equal_approx(b2[i]):
			same = false
	_check("storm: bolt deterministic per seed", same)


func _test_branch_shape() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	var bolt := fx._gen_bolt(Vector2(800, 600))
	var br := fx._gen_branch(bolt, 3)
	_check("storm: branch starts on bolt",
			br[0].is_equal_approx(bolt[3]))
	_check("storm: branch 5 segments", br.size() == 6)
	_check("storm: branch drifts down", br[br.size() - 1].y > br[0].y)


## ---- storm tint ------------------------------------------------------------

func _test_storm_tint_lerps_in() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	fx.force_weather("storm")
	fx._update_storm(10.0)
	var c: Color = fx._storm_tint.color
	_check("storm: tint reaches sky color",
			c.is_equal_approx(WeatherFX.STORM_SKY_COLOR))


func _test_storm_tint_fades_out() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	fx.force_weather("storm")
	fx._update_storm(10.0)
	fx.force_weather("clear")
	fx._update_storm(10.0)
	_check("storm: tint fades to transparent",
			fx._storm_tint.color.a < 0.001)


func _test_precip_visible_in_storm() -> void:
	var gs := _new_game()
	var fx := _new_fx(gs)
	fx.force_weather("storm")
	fx._update_particles(0.016)
	_check("storm: precip layer visible", fx._precip.visible)
	fx.force_weather("clear")
	fx._update_particles(0.016)
	fx._flash_alpha = 0.0
	fx._update_particles(0.016)
	_check("storm: precip hidden when clear", not fx._precip.visible)
