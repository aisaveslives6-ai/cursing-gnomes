extends SceneTree
## Cursing Gnomes — decal-layer redraw throttling tests.
##
## CombatFX decal layers (stains, gore, gibs) used to queue_redraw() at
## 60 fps while any decal existed — up to 400 stains x 4 circles = ~1,600
## draw calls per redraw, 60x/sec, for a 60 s fade the eye can't see move.
## The throttle: stains redraw at 10 Hz (immediate on add/remove); gore
## and gibs redraw every frame only while at least one piece is airborne,
## otherwise 10 Hz for the slow fade-out. Zero visual change.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_fx_decal_throttle.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_fx() -> CombatFX:
	var fx := CombatFX.new()
	root.add_child(fx)
	return fx


func _counts(fx: CombatFX) -> Dictionary:
	return fx.debug_decal_redraws()


func _initialize() -> void:
	print("=== Cursing Gnomes decal throttle tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_stains_throttled_to_10hz()
	_test_stain_removal_forces_redraw()
	_test_stain_spawn_redraws_immediately()
	_test_gore_airborne_redraws_every_frame()
	_test_gore_settled_throttled()
	_test_gore_removal_forces_redraw()
	_test_gibs_airborne_redraws_every_frame()
	_test_gibs_settled_throttled()
	_test_process_smoke()
	print("passed=%d failed=%d" % [_passed, _failed])
	if not _failures.is_empty():
		print("failures: ", _failures)
	quit(1 if _failed > 0 else 0)


## 60 ticks (1 s) of idle stains -> ~10 redraws (10 Hz), not 60.
func _test_stains_throttled_to_10hz() -> void:
	var fx := _new_fx()
	fx.blood_stain(Vector2(500, 500), 12)
	fx.debug_reset_decal_redraws()
	for i in 60:
		fx._tick_stains(1.0 / 60.0)
	var n: int = int(_counts(fx)["stain"])
	_check("stains: 1s idle -> ~10 redraws (got %d)" % n, n >= 8 and n <= 12)
	_check("stains: throttled below 60fps (got %d)" % n, n < 60)
	_check("stains: all 12 still alive", fx._stains.size() == 12)
	fx.queue_free()


## Expiring stains force an immediate redraw (no ghost decals).
func _test_stain_removal_forces_redraw() -> void:
	var fx := _new_fx()
	fx.blood_stain(Vector2(500, 500), 5)
	for s in fx._stains:
		s["life"] = 0.001
	fx.debug_reset_decal_redraws()
	fx._tick_stains(1.0 / 60.0)
	_check("stains: removal forces redraw", int(_counts(fx)["stain"]) == 1)
	_check("stains: all expired", fx._stains.is_empty())
	# Next tick with nothing left: no redraw at all.
	fx.debug_reset_decal_redraws()
	fx._tick_stains(1.0 / 60.0)
	_check("stains: empty -> no redraw", int(_counts(fx)["stain"]) == 0)
	fx.queue_free()


## Spawning still redraws immediately (new blood appears this frame).
func _test_stain_spawn_redraws_immediately() -> void:
	var fx := _new_fx()
	fx.debug_reset_decal_redraws()
	fx.blood_stain(Vector2(500, 500), 3)
	_check("stains: spawn redraws immediately",
		int(_counts(fx)["stain"]) == 1)
	fx.queue_free()


## Airborne gore chunks -> per-frame redraws (they genuinely move).
func _test_gore_airborne_redraws_every_frame() -> void:
	var fx := _new_fx()
	fx.gore(Vector2(500, 100), "chunk", 6)
	# Pin every chunk airborne for the whole window.
	for g in fx._gore:
		g["grounded"] = false
		g["vel"] = Vector2(0, -1000)
		g["pos"] = Vector2(500, 100)
		g["ground_y"] = 500.0
	fx.debug_reset_decal_redraws()
	for i in 10:
		fx._tick_gore(1.0 / 60.0)
	var n: int = int(_counts(fx)["gore"])
	_check("gore: airborne 10 ticks -> ~10 redraws (got %d)" % n, n >= 8)
	fx.queue_free()


## Settled gore -> 10 Hz (only the slow fade-out changes).
func _test_gore_settled_throttled() -> void:
	var fx := _new_fx()
	fx.gore(Vector2(500, 500), "chunk", 8)
	for g in fx._gore:
		g["grounded"] = true
		g["vel"] = Vector2.ZERO
	fx.debug_reset_decal_redraws()
	for i in 60:
		fx._tick_gore(1.0 / 60.0)
	var n: int = int(_counts(fx)["gore"])
	_check("gore: settled 1s -> ~10 redraws (got %d)" % n, n >= 8 and n <= 12)
	_check("gore: throttled below 60fps (got %d)" % n, n < 60)
	fx.queue_free()


## Expiring gore forces an immediate redraw.
func _test_gore_removal_forces_redraw() -> void:
	var fx := _new_fx()
	fx.gore(Vector2(500, 500), "chunk", 4)
	for g in fx._gore:
		g["age"] = 59.99
	fx.debug_reset_decal_redraws()
	fx._tick_gore(1.0 / 60.0)
	_check("gore: removal forces redraw", int(_counts(fx)["gore"]) == 1)
	_check("gore: all expired", fx._gore.is_empty())
	fx.queue_free()


## Airborne gibs -> per-frame redraws.
func _test_gibs_airborne_redraws_every_frame() -> void:
	var fx := _new_fx()
	fx.gib(Vector2(500, 400), "humans")
	fx.debug_reset_decal_redraws()
	for i in 10:
		fx._tick_gibs(1.0 / 60.0)
	var n: int = int(_counts(fx)["gib"])
	_check("gibs: airborne 10 ticks -> ~10 redraws (got %d)" % n, n >= 8)
	fx.queue_free()


## Rested gibs -> 10 Hz.
func _test_gibs_settled_throttled() -> void:
	var fx := _new_fx()
	fx.gib(Vector2(500, 400), "humans")
	for g in fx._gibs:
		g["bounced"] = true
		g["vel"] = Vector2.ZERO
	fx.debug_reset_decal_redraws()
	for i in 60:
		fx._tick_gibs(1.0 / 60.0)
	var n: int = int(_counts(fx)["gib"])
	_check("gibs: settled 1s -> ~10 redraws (got %d)" % n, n >= 8 and n <= 12)
	_check("gibs: throttled below 60fps (got %d)" % n, n < 60)
	fx.queue_free()


## Full _process with all three decal kinds active: no errors, sane counts.
func _test_process_smoke() -> void:
	var fx := _new_fx()
	fx.blood_stain(Vector2(500, 500), 20)
	fx.gore(Vector2(500, 500), "chunk", 10)
	fx.gib(Vector2(500, 400), "ogres")
	fx.debug_reset_decal_redraws()
	for i in 120:
		fx._process(1.0 / 60.0)
	var c := _counts(fx)
	# 2 s: stains ~20 (10 Hz) + 1 spawn redraw + up to ~12 extra spawn
	# redraws when the 6 gibs land (each landing stains the ground);
	# gore/gibs per-frame while airborne then throttled — all bounded
	# well under the old 120-each.
	_check("smoke: stains bounded (%d)" % int(c["stain"]),
		int(c["stain"]) <= 40)
	_check("smoke: gore bounded (%d)" % int(c["gore"]),
		int(c["gore"]) <= 120)
	_check("smoke: gibs bounded (%d)" % int(c["gib"]),
		int(c["gib"]) <= 120)
	_check("smoke: stains still tracked (>= 20, gib landings add more)",
		fx._stains.size() >= 20)
	fx.queue_free()
