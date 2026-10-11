extends SceneTree
## Cursing Gnomes — windmill blade animation tests (graphics-hourly 2026-10-04).
##
## The programmer-art windmill drew four static blades; real windmills turn.
## BuildingNode._process advances _blade_angle at WINDMILL_TURN (one gentle
## revolution per 6 s), quantized into WINDMILL_STEPS redraw steps so only
## windmill nodes ever redraw for this. Sprite-art buildings, incomplete
## blueprints, and non-windmill types never spin.
##
## Wake routine 2026-10-04: windmill got its real sprite art (bld_windmill,
## ported verbatim from fix79), so the spin logic now lives on the
## missing-art fallback path (sprite == null) — the spin tests below use
## _make_fallback_node(), and a separate test pins that the sprite-art
## windmill never spins (HTML parity: the HTML draws the sprite statically).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_windmill_blades.gd
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


func _make_node(btype: String, complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, "gnomes", Vector2(100, 100))
	n.record = {"complete": complete}
	return n


## Missing-art fallback: windmill with its sprite nulled, simulating the
## broken/missing-texture path that keeps the box+spinning-blades arm.
func _make_fallback_node() -> BuildingNode:
	var n := _make_node("windmill")
	n._sprite = null
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes windmill-blade tests ===")
	_test_spin_rate()
	_test_full_turn_wraps()
	_test_quantized_redraw_steps()
	_test_non_windmill_static()
	_test_incomplete_blueprint_static()
	_test_sprite_building_static()
	_test_sprite_windmill_static()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## One second of _process advances the angle by exactly WINDMILL_TURN
## (missing-art fallback path).
func _test_spin_rate() -> void:
	var n := _make_fallback_node()
	n._process(1.0)
	_check("blade angle advances at WINDMILL_TURN/sec",
		absf(n._blade_angle - BuildingNode.WINDMILL_TURN) < 0.0001)
	_check("blade angle starts near zero", n._blade_angle > 0.0)
	n.free()


## After 6 s the blades complete one revolution and wrap via fmod.
func _test_full_turn_wraps() -> void:
	var n := _make_fallback_node()
	n._process(3.0)
	_check("half turn = PI after 3 s", absf(n._blade_angle - PI) < 0.0001)
	n._process(3.0)
	_check("full turn wraps to ~0 after 6 s", n._blade_angle < 0.0001)
	n.free()


## Redraw steps only change on quantized boundaries (no per-frame spam).
func _test_quantized_redraw_steps() -> void:
	var n := _make_fallback_node()
	_check("blade step starts unset", n._blade_step == -1)
	n._process(0.01)
	var s0: int = n._blade_step
	_check("first frame sets a step", s0 >= 0)
	n._process(0.01)
	_check("tiny delta keeps the same step (no redraw spam)",
		n._blade_step == s0)
	n._process(1.0)
	_check("a full second crosses step boundaries", n._blade_step != s0)
	_check("steps stay within 0..WINDMILL_STEPS",
		n._blade_step >= 0 and n._blade_step < BuildingNode.WINDMILL_STEPS)
	n.free()


## Programmer-art non-windmill buildings never spin.
func _test_non_windmill_static() -> void:
	var n := _make_node("farm")  # no sprite art -> programmer-art path
	_check("farm has no sprite (programmer-art path)", n._sprite == null)
	n._process(5.0)
	_check("farm blades stay at zero", n._blade_angle == 0.0)
	_check("farm never sets a blade step", n._blade_step == -1)
	n.free()


## Incomplete windmill blueprints draw the scaffold, not spinning blades.
func _test_incomplete_blueprint_static() -> void:
	var n := _make_node("windmill", false)
	n._process(5.0)
	_check("blueprint windmill blades stay at zero", n._blade_angle == 0.0)
	n.free()


## Sprite-art buildings don't draw blades at all (early return in _draw).
func _test_sprite_building_static() -> void:
	var n := _make_node("house")  # bld_house.png exists
	_check("house has sprite art", n._sprite != null)
	n._process(5.0)
	_check("sprite building blades stay at zero", n._blade_angle == 0.0)
	n.free()


## Real-art windmill takes the sprite path — blades never spin (HTML parity:
## fix79 draws the bld_windmill sprite statically).
func _test_sprite_windmill_static() -> void:
	var n := _make_node("windmill")
	_check("windmill has real sprite art", n._sprite != null)
	n._process(5.0)
	_check("sprite windmill blades stay at zero", n._blade_angle == 0.0)
	_check("sprite windmill never sets a blade step", n._blade_step == -1)
	n.free()
