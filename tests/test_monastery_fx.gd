extends SceneTree
## Cursing Gnomes — monastery candle-glow FX (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## Monasteries are the game's #1 strategic target (assault campaigns,
## monastery guards, captures) and stood perfectly still. Complete
## monasteries now breathe warm candlelight from their real arched windows
## and burn a brazier by the doorway on the shared quantized FX cadence
## (8 steps at 6/sec). The candle flicker is a pure function
## (monastery_flicker_for) so the math is pinned without rendering;
## anchors are verified against the baked _monastery art coordinates;
## _process gates keep blueprints dark and other buildings untouched.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_monastery_fx.gd
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


func _make_node(btype: String, faction := "gnomes",
		complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes monastery candle-glow FX tests ===")
	_test_roster()
	_test_anchors()
	_test_flicker()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: monasteries, and nothing else.
func _test_roster() -> void:
	_check("roster contains monastery",
		"monastery" in BuildingNode.MONASTERY_FX_BTYPES)
	_check("roster has exactly 1 type",
		BuildingNode.MONASTERY_FX_BTYPES.size() == 1)
	for b in ["house", "farmhouse", "oil_pump", "town_hall", "windmill",
			"shop", "inn", "hotel", "sawmill", "weaponsmith"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.MONASTERY_FX_BTYPES))


## Anchors match the baked _monastery art: windows at wx+3.5 for the
## `for wx in [-16.0, -4.0]` loop (glass rect (wx,0,7,14)), brazier
## flanking the doorway (ends x=6) clear of the bell tower (starts x=14)
## and the window glass, feet on the ground line y=24.
func _test_anchors() -> void:
	var wins: Array = BuildingNode.MONASTERY_WINDOWS
	_check("two windows", wins.size() == 2)
	var wx0: Vector2 = wins[0]
	var wx1: Vector2 = wins[1]
	_check("window 0 center x = -16+3.5", absf(wx0.x - (-12.5)) < 0.01)
	_check("window 1 center x = -4+3.5", absf(wx1.x - (-0.5)) < 0.01)
	_check("window 0 glass center y = 7", absf(wx0.y - 7.0) < 0.01)
	_check("window 1 glass center y = 7", absf(wx1.y - 7.0) < 0.01)
	# Glass overlay in _monastery_fx covers exactly the baked glass:
	# rect (wx,0,7,14) == (cx-3.5, cy-7, 7, 14).
	for w in wins:
		_check("glass rect x inside chapel",
			w.x - 3.5 >= -26.0 and w.x + 3.5 <= 26.0)
		_check("glass rect y inside chapel",
			w.y - 7.0 >= -6.0 and w.y + 7.0 <= 24.0)
	var b: Vector2 = BuildingNode.MONASTERY_BRAZIER
	_check("brazier right of doorway", b.x > 6.0)
	_check("brazier clear of bell tower", b.x + 4.6 < 14.0)
	_check("brazier feet on ground line", absf(b.y - 24.0) < 0.01)
	_check("brazier clear of window glass", b.x - 4.6 > 3.0)
	# Test hook starts disarmed.
	var n := _make_node("monastery")
	_check("fx hook starts disarmed", n._last_monastery_fx == "")
	_check("monastery is drawn path", n._sprite == null)
	n.free()


## The flicker is candle-like: bounded 0.72..1.0, varies with the step,
## and the phase shifts the wave (per-element offsets desync windows).
func _test_flicker() -> void:
	var lo := 2.0
	var hi := -1.0
	var seen := {}
	for s in range(BuildingNode.EATERY_FX_STEPS):
		for p in [0.0, 1.9, 2.7, 3.4]:
			var f := BuildingNode.monastery_flicker_for(s, p)
			lo = minf(lo, f)
			hi = maxf(hi, f)
			seen[f] = true
	_check("flicker lower bound 0.72", lo >= 0.72 - 0.001)
	_check("flicker upper bound 1.0", hi <= 1.0 + 0.001)
	_check("flicker varies across steps", seen.size() > 4)
	_check("phase 0 vs 1.9 differ at step 0",
		absf(BuildingNode.monastery_flicker_for(0, 0.0)
			- BuildingNode.monastery_flicker_for(0, 1.9)) > 0.01)
	# Full-cycle determinism: same step+phase always gives the same value.
	_check("flicker deterministic",
		BuildingNode.monastery_flicker_for(5, 3.4)
			== BuildingNode.monastery_flicker_for(5, 3.4))


## _process animates only complete monasteries: blueprints stay dark and
## other buildings never touch the monastery FX step.
func _test_process_gates() -> void:
	var m := _make_node("monastery")
	m._process(0.1)
	_check("complete monastery advances fx step",
		m._fx_step >= 0 and m._fx_step < BuildingNode.EATERY_FX_STEPS)
	m.free()
	var bp := _make_node("monastery", "gnomes", false)
	bp._process(0.1)
	_check("blueprint monastery stays static", bp._fx_step == -1)
	bp.free()
	var house := _make_node("house")
	house._process(0.1)
	_check("house keeps its own fx step (monastery gate untouched)",
		house._fx_step >= 0)
	house.free()
	var inn := _make_node("inn")
	inn._process(0.1)
	_check("inn keeps its own fx step (monastery gate untouched)",
		inn._fx_step >= 0)
	inn.free()
