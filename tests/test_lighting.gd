extends SceneTree
## Cursing Gnomes — graphics update tests (LightingRig + AmbientFX).
##
## Jeremy 2026-10-03: "give the game a major graphics update... let's use
## some of these go dot 4 abilities." The lighting rig brings real Godot 4
## 2D lighting: CanvasModulate day/night ambient + pooled PointLight2D
## (windows, fires, flashes). AmbientFX adds fireflies/embers/leaves/cloud
## shadows. These tests pin the pure math and pool bookkeeping — no
## rendering, headless-safe.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_lighting.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _frame_test_done := false


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	_test_ambient_bands()
	_test_night_factor()
	_test_radial_texture()
	_test_light_pool_setup()
	_test_window_assignment()
	_test_flash_lifecycle()
	_test_tier_budgets()
	_test_weather_lighting_mode()
	_test_ambient_season_colors()
	_test_ambient_tiers()
	# The camera-tracking regression test needs a live frame (Camera2D must
	# be inside the tree and current before get_screen_center_position is
	# meaningful); it runs in _process below, which prints and quits.


func _process(_delta: float) -> bool:
	if _frame_test_done:
		return false
	_frame_test_done = true
	var cam := Camera2D.new()
	cam.position = Vector2(3000, 2000)
	root.add_child(cam)
	cam.enabled = true
	cam.make_current()
	var a := AmbientFX.new()
	root.add_child(a)
	a.setup(cam, "medium", Rect2(0, 0, 6000, 4000))
	_test_ambient_sky_emitters_track_camera(cam, a)
	a.queue_free()
	cam.queue_free()
	print("lighting: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)
	return false


func _test_ambient_sky_emitters_track_camera(cam: Camera2D,
		a: AmbientFX) -> void:
	# Regression (Jeremy 2026-10-04): _sky_layer uses follow_viewport, so
	# its children live in WORLD space. Parking an emitter at (0,0) left it
	# at the map corner, off-screen — the night fireflies never rendered.
	# Both screen-space emitters must re-anchor to the camera every frame.
	a.set_phase(0.0)  # midnight: fireflies at full emission ratio
	a._process(0.016)
	var center: Vector2 = cam.get_screen_center_position()
	_check("fireflies track screen center",
		a._fireflies.position.distance_to(center) < 1.0)
	_check("fireflies not stuck at world origin",
		a._fireflies.position.distance_to(Vector2.ZERO) > 100.0)
	_check("leaves track screen center",
		a._leaves.position.distance_to(center + Vector2(0, -380)) < 1.0)
	_check("fireflies emit at night", a._fireflies.amount_ratio > 0.0)


## Ambient color keyframes: day white, night dark blue, dawn/dusk warm.
## Phase convention: 0 = midnight, 0.5 = noon (GameState clock).
func _test_ambient_bands() -> void:
	var day := LightingRig.ambient_for(0.5)
	_check("midday ambient is white", day.is_equal_approx(Color(1, 1, 1)))
	var night := LightingRig.ambient_for(0.0)
	_check("deep night ambient is dark blue",
		night.r < 0.45 and night.b > night.r)
	var dawn := LightingRig.ambient_for(6.0 / 24.0)
	_check("dawn ambient is warm (r > b)", dawn.r > dawn.b)
	var dusk := LightingRig.ambient_for(20.0 / 24.0)
	_check("dusk ambient is warm (r > b)", dusk.r > dusk.b)
	_check("ambient never pitch black", night.r > 0.15)


## Night factor drives light energy: 0 at day, 1 at deep night.
func _test_night_factor() -> void:
	_check("night factor 1.0 at deep night",
		is_equal_approx(LightingRig.night_factor(0.0), 1.0))
	_check("night factor 0.0 at midday",
		is_equal_approx(LightingRig.night_factor(0.5), 0.0))
	var mid := LightingRig.night_factor(20.0 / 24.0)
	_check("night factor between 0 and 1 at dusk",
		mid > 0.0 and mid < 1.0)


func _test_radial_texture() -> void:
	var t := LightingRig.radial_texture()
	_check("radial texture generated", t != null)
	var img := t.get_image()
	var c: Color = img.get_pixel(64, 64)
	_check("radial core is opaque", c.a > 0.9)
	var edge: Color = img.get_pixel(0, 0)
	_check("radial edge is transparent", edge.a < 0.05)
	_check("radial texture cached (same instance)",
		LightingRig.radial_texture() == t)


func _test_light_pool_setup() -> void:
	var rig := LightingRig.new()
	rig.setup(null, "medium")
	_check("medium tier: 10 window lights", rig._window_lights.size() == 10)
	_check("medium tier: 6 fire lights", rig._fire_lights.size() == 6)
	_check("medium tier: 4 flash slots", rig._flash_lights.size() == 4)
	_check("no lights visible initially", rig.visible_light_count() == 0)
	_check("CanvasModulate child exists", rig._modulate != null)
	rig.queue_free()
	var rig_low := LightingRig.new()
	rig_low.setup(null, "low")
	_check("low tier: 6 window lights", rig_low._window_lights.size() == 6)
	rig_low.queue_free()
	var rig_ultra := LightingRig.new()
	rig_ultra.setup(null, "ultra")
	_check("ultra tier: 22 window lights", rig_ultra._window_lights.size() == 22)
	rig_ultra.queue_free()


func _test_window_assignment() -> void:
	var rig := LightingRig.new()
	rig.setup(null, "medium")  # null camera = everything "in view"
	var pos := PackedVector2Array(
		[Vector2(100, 100), Vector2(200, 200), Vector2(300, 300)])
	rig.set_window_positions(pos)
	_check("3 window lights visible for 3 positions",
		rig.visible_light_count() == 3)
	_check("first light at first position",
		rig._window_lights[0].position.is_equal_approx(Vector2(100, 100)))
	rig.set_window_positions(PackedVector2Array())
	_check("all lights parked when no positions",
		rig.visible_light_count() == 0)
	# Over budget: extras stay parked.
	var many := PackedVector2Array()
	for i in range(50):
		many.append(Vector2(i * 10, i * 10))
	rig.set_window_positions(many)
	_check("window lights capped at pool size",
		rig.visible_light_count() == 10)
	rig.queue_free()


func _test_flash_lifecycle() -> void:
	var rig := LightingRig.new()
	rig.setup(null, "low")  # 3 flash slots
	rig.flash(Vector2(50, 50), Color.RED, 150.0, 0.3)
	_check("flash visible after trigger", rig.visible_light_count() == 1)
	# Simulate expiry: age past life.
	var slot: Dictionary = rig._flash_lights[0]
	slot["age"] = 5.0
	rig.set_phase(0.25, 0.1)
	_check("flash expires after life", rig.visible_light_count() == 0)
	rig.queue_free()


func _test_tier_budgets() -> void:
	for tier in ["ultra", "high", "medium", "low"]:
		_check("tier %s has a budget" % tier,
			LightingRig.TIER_BUDGETS.has(tier))
	var ultra: Array = LightingRig.TIER_BUDGETS["ultra"]
	var low: Array = LightingRig.TIER_BUDGETS["low"]
	_check("ultra budget >= low budget", int(ultra[0]) >= int(low[0]))
	# Unknown tier falls back to medium.
	var rig := LightingRig.new()
	rig.setup(null, "bogus")
	_check("unknown tier falls back to medium pools",
		rig._window_lights.size() == 10)
	rig.queue_free()


## WeatherFX lighting mode: tint alpha drops to 30% so CanvasModulate owns
## the darkening (no double-dark).
func _test_weather_lighting_mode() -> void:
	var w := WeatherFX.new()
	_check("lighting_mode defaults off", w.lighting_mode == false)
	w.set_lighting_mode(true)
	_check("lighting_mode toggles on", w.lighting_mode == true)
	var legacy := WeatherFX.new()
	var night_off := legacy._tint_target_for(0.0)
	var night_on := w._tint_target_for(0.0)
	_check("legacy night tint alpha 0.55",
		is_equal_approx(night_off.a, 0.55))
	_check("lighting-mode night tint alpha scaled to 30%",
		is_equal_approx(night_on.a, 0.55 * 0.30))
	_check("lighting mode keeps night hue",
		is_equal_approx(night_on.r, night_off.r)
		and is_equal_approx(night_on.b, night_off.b))
	var day_on := w._tint_target_for(0.5)
	_check("day tint stays transparent in lighting mode",
		is_equal_approx(day_on.a, 0.0))
	w.free()
	legacy.free()


func _test_ambient_season_colors() -> void:
	var a := AmbientFX.new()
	a.set_season("autumn")
	_check("autumn leaves are orange",
		a._season_leaf_color().r > a._season_leaf_color().b)
	a.set_season("winter")
	_check("winter motes are pale",
		a._season_leaf_color().r > 0.9)
	a.set_season("spring")
	_check("spring pollen is greenish",
		a._season_leaf_color().g > a._season_leaf_color().r)
	a.queue_free()


func _test_ambient_tiers() -> void:
	var a := AmbientFX.new()
	a.set_tier("ultra")
	_check("ultra particle mul 0.9", is_equal_approx(a._particle_mul, 0.9))
	a.set_tier("low")
	_check("low particle mul 0.15", is_equal_approx(a._particle_mul, 0.15))
	a.set_tier("medium")
	_check("medium particle mul 0.5", is_equal_approx(a._particle_mul, 0.5))
	a.queue_free()
