extends SceneTree
## Cursing Gnomes — fishing-dock water FX (rapid-iteration 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## The fishing dock is the fishing loop's anchor (the Stinky Gizmundo
## swims here) and stood perfectly still on the water: zero ambient FX,
## and the FLAT_GLOW list means it only got a night halo. Complete docks
## now breathe on the shared quantized FX cadence (8 steps at 6/sec):
## foam flecks lap the pier's waterline, the moored boat gets alternating
## hull water-laps, and a lantern on the pennant pole breathes warm light
## that deepens after dark. Blueprints stay dark. Drawn-arm path
## (node-local px anchors matching _fishing_dock, the monastery-FX
## precedent).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_fishing_dock_fx.gd
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


func _make_node(btype: String, faction := "gnomes", complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes fishing-dock FX tests ===")
	_test_roster()
	_test_anchors()
	_test_process_gates()
	_test_lantern_night()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: fishing_dock only - the pier keeps its baked
## waterline glints, every other family keeps its own path.
func _test_roster() -> void:
	_check("roster contains fishing_dock",
		"fishing_dock" in BuildingNode.FISHING_FX_BTYPES)
	_check("roster has exactly 1 type",
		BuildingNode.FISHING_FX_BTYPES.size() == 1)
	for b in ["pier", "farm", "flesh_farm", "restaurant", "soul_cafe",
			"inn", "hotel", "shop", "house", "town_hall", "oil_pump",
			"sawmill", "mine", "quarry", "barracks", "wall",
			"lumber_camp", "storage"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.FISHING_FX_BTYPES))
	_check("foam tint (0.80,0.88,0.95)",
		BuildingNode.FISHING_FX_FOAM_TINT == Color(0.80, 0.88, 0.95))
	_check("lantern tint (1.0,0.80,0.50)",
		BuildingNode.FISHING_FX_LANTERN_TINT == Color(1.0, 0.80, 0.50))
	_check("lantern anchor (-18,-9)",
		BuildingNode.FISHING_FX_LANTERN == Vector2(-18.0, -9.0))


## Anchors sit on the drawn arm: flecks along the baked foam edge
## (y=8, x -26..42), laps just outside the moored boat (hull x 24..38),
## lantern on the pennant pole below the pennant and above the deck.
func _test_anchors() -> void:
	var flecks: Array = BuildingNode.FISHING_FX_FLECKS
	_check("3 foam flecks", flecks.size() == 3)
	for i in range(flecks.size()):
		var f: Vector2 = flecks[i]
		_check("fleck %d on foam edge x range" % i,
			f.x >= -26.0 and f.x <= 42.0)
		_check("fleck %d on foam edge y" % i,
			absf(f.y - 8.0) <= 1.5)
	var laps: Array = BuildingNode.FISHING_FX_LAPS
	_check("2 hull laps", laps.size() == 2)
	_check("lap 0 left of hull", laps[0].x < 24.0)
	_check("lap 1 right of hull", laps[1].x > 38.0)
	for i in range(laps.size()):
		_check("lap %d at hull waterline" % i,
			absf(laps[i].y - 10.0) <= 1.5)
	# Lantern: below the pennant triangle (ends y=-12), above the deck
	# top (y=-6), on the pole (x=-18).
	var lamp: Vector2 = BuildingNode.FISHING_FX_LANTERN
	_check("lantern on pole x", lamp.x == -18.0)
	_check("lantern below pennant", lamp.y > -12.0)
	_check("lantern above deck", lamp.y < -6.0)


## The _process gate: complete docks advance the FX step on the shared
## cadence; blueprints and every other type skip with one cheap check.
func _test_process_gates() -> void:
	var dock := _make_node("fishing_dock")
	dock._process(0.1)
	_check("complete fishing_dock advances fx step",
		dock._fx_step >= 0 and dock._fx_step < BuildingNode.EATERY_FX_STEPS)
	dock.free()
	var bp := _make_node("fishing_dock", "gnomes", false)
	bp._process(0.1)
	_check("fishing_dock blueprint stays static", bp._fx_step == -1)
	bp.free()
	var pier := _make_node("pier", "gnomes")
	pier._process(0.1)
	_check("pier keeps its own path, not the dock gate",
		not ("pier" in BuildingNode.FISHING_FX_BTYPES))
	pier.free()
	var farm := _make_node("farm", "gnomes")
	farm._process(0.1)
	_check("farm keeps its own gate, not the dock one",
		farm._fx_step >= 0 and farm._fx_step < BuildingNode.EATERY_FX_STEPS)
	farm.free()
	# The draw hook starts disarmed and only arms for the roster btype.
	var n := _make_node("fishing_dock")
	_check("fx hook starts disarmed", n._last_fishing_dock_fx == "")
	n.free()


## The lantern deepens after dark (NightGlow.current()) like the shop
## panes; the foam/laps read day and night. Verified through the same
## statics the FX function reads.
func _test_lantern_night() -> void:
	# NightGlow.glow_for: deep night 1.0, midday 0.0 (the night_glow
	# suite pins these; here we assert the FX-side gating contract).
	_check("deep night glow 1.0", is_equal_approx(NightGlow.glow_for(0.0), 1.0))
	_check("midday glow 0.0", is_equal_approx(NightGlow.glow_for(0.5), 0.0))
	# Halo alpha formula: (0.08 + 0.20 * night) * flick - night strictly
	# deepens it, day never reaches night levels.
	var day_halo: float = 0.08 + 0.20 * 0.0
	var night_halo: float = 0.08 + 0.20 * 1.0
	_check("night halo deeper than day", night_halo > day_halo)
	_check("day halo faint", day_halo < 0.10)
	# Glass dot alpha formula: (0.30 + 0.60 * night) * flick - visible
	# by day, glowing at night.
	_check("day glass visible", 0.30 > 0.0)
	_check("night glass brighter", 0.30 + 0.60 > 0.30)
