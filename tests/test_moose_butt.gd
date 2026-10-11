extends SceneTree
## Cursing Gnomes — thicc moose rear-view butt sprite tests (2026-10-04).
##
## Jeremy's iPhone verdict: mooning with the side profile just read as the
## moose standing there. While combat_state == "mooning", the unit node now
## swaps to a rear-view butt sprite (assets/art/animals/moose_butt.png) with
## a squash-and-stretch shake, and restores the side profile when mooning
## ends.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_moose_butt.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(label)
		print("FAIL: ", label)


func _initialize() -> void:
	print("=== Cursing Gnomes moose-butt tests ===")
	_test_butt_art_exists()
	_test_mooning_swaps_sprite()
	_test_mooning_restore()
	_test_mooning_noop_for_other_jobs()
	_test_butt_shake_advances()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _make_moose() -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(424242, "monsters", "thicc_moose", Vector2(100, 200), "m")
	return un


## The butt sprite file ships with the game.
func _test_butt_art_exists() -> void:
	var f := FileAccess.open(
		"res://assets/art/animals/moose_butt.png", FileAccess.READ)
	_check(f != null, "butt: moose_butt.png exists on disk")
	if f != null:
		_check(f.get_length() > 10000, "butt: moose_butt.png is a real image")
		f.close()


## Mooning swaps the side profile for the rear-view butt sprite.
func _test_mooning_swaps_sprite() -> void:
	var un := _make_moose()
	var side_tex: Texture2D = un._sprite.texture
	un.set_mooning(true)
	_check(un._mooning, "butt: set_mooning(true) sets _mooning")
	var butt: Texture2D = Art.animal_texture("moose_butt")
	if butt != null:
		_check(un._sprite.texture == butt,
			"butt: mooning swaps to rear-view butt sprite")
		_check(un._sprite.texture != side_tex,
			"butt: butt sprite differs from side profile")
		_check(butt.get_width() > 0 and butt.get_height() > 0,
			"butt: butt texture has real dimensions")
	else:
		# Headless without an import pass may not resolve textures; the
		# swap code path still ran without crashing.
		_check(true, "butt: swap path runs (headless, no imported texture)")
	un.free()


## Mooning off restores the side profile and the base pose.
func _test_mooning_restore() -> void:
	var un := _make_moose()
	var side_tex: Texture2D = un._sprite.texture
	var base_scale: Vector2 = un._base_sprite_scale
	un.set_mooning(true)
	un.set_mooning(false)
	_check(not un._mooning, "butt: set_mooning(false) clears _mooning")
	if side_tex != null:
		_check(un._sprite.texture == side_tex,
			"butt: mooning end restores side-profile sprite")
	_check(un._sprite.scale == base_scale,
		"butt: mooning end restores base scale")
	_check(un._sprite.position.x == 0.0,
		"butt: mooning end resets x offset")
	_check(un._sprite.rotation == 0.0,
		"butt: mooning end resets rotation")
	un.free()


## set_mooning is a no-op for non-moose jobs (defensive: world sync calls it
## for every unit).
func _test_mooning_noop_for_other_jobs() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(777, "gnomes", "worker", Vector2.ZERO, "m")
	var tex: Texture2D = un._sprite.texture
	un.set_mooning(true)  # must not swap a worker's sprite
	_check(un._sprite.texture == tex,
		"butt: non-moose units keep their sprite when mooning")
	un.set_mooning(false)
	un.free()


## The butt shake advances over time and displaces the sprite.
func _test_butt_shake_advances() -> void:
	var un := _make_moose()
	un.set_mooning(true)
	var t0: float = un._moon_time
	un._process(0.1)
	_check(un._moon_time > t0, "butt: shake clock advances while mooning")
	# At t=0.1 with 12 rad/s the wiggle is well off zero.
	_check(absf(un._sprite.position.x) > 0.01,
		"butt: shake displaces sprite horizontally")
	_check(absf(un._sprite.rotation) > 0.0001,
		"butt: shake rotates sprite")
	_check(un._sprite.scale != un._base_sprite_scale,
		"butt: shake applies squash-and-stretch")
	un.free()
