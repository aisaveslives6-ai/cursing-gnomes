extends SceneTree
## Cursing Gnomes — lumber-camp work FX (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## The lumber camp (bld_lumber_camp.png, 720x480) is the wood loop's
## anchor — 80 wood, 450px coverage, one per AI town, chopped-tree
## pickups haul here — and drew real sprite art with zero ambient FX.
## Complete lumber camps now breathe on the shared quantized FX cadence
## (8 steps at 6/sec — the tavern/restaurant precedent): 3 staggered
## sawdust motes drift down off the crosscut-saw teeth on the sawbuck,
## and one wood chip kicks off the axe-stuck chopping stump each cycle.
## Blueprints stay dark. Anchors measured off the real sprite.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_lumber_fx.gd
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
	print("=== Cursing Gnomes lumber-camp FX tests ===")
	_test_roster()
	_test_anchors()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: lumber_camp only — every other family keeps its own
## path (sawmill has no sprite art but keeps its own industrial FX; the oil
## pump has its own FX arm).
func _test_roster() -> void:
	_check("roster contains lumber_camp",
		"lumber_camp" in BuildingNode.LUMBER_FX_BTYPES)
	_check("roster has exactly 1 type",
		BuildingNode.LUMBER_FX_BTYPES.size() == 1)
	for b in ["farm", "flesh_farm", "restaurant", "soul_cafe", "inn",
			"hotel", "shop", "house", "town_hall", "oil_pump", "sawmill",
			"mine", "quarry", "barracks", "wall"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.LUMBER_FX_BTYPES))
	_check("tex 720x480",
		BuildingNode.LUMBER_FX_TEX == Vector2(720.0, 480.0))
	_check("saw anchor (245,254)",
		BuildingNode.LUMBER_FX_SAW == Vector2(245.0, 254.0))
	_check("stump anchor (133,353)",
		BuildingNode.LUMBER_FX_STUMP == Vector2(133.0, 353.0))
	_check("sawdust tint (0.87,0.76,0.55)",
		BuildingNode.LUMBER_SAWDUST_TINT == Color(0.87, 0.76, 0.55))


## Anchors: the art->node conversion tracks the real render scale, and the
## FX overlays sit above the ground line over the art (never floating,
## never below the base).
func _test_anchors() -> void:
	var n := _make_node("lumber_camp")
	n._sprite_sc = 1.0
	# saw: (245-360, (254-240) - 0.48*480) = (-115.0, -216.4)
	var saw: Vector2 = n._lumber_fx_anchor(BuildingNode.LUMBER_FX_SAW)
	_check("saw node x = -115.0", absf(saw.x - (-115.0)) < 0.01)
	_check("saw node y = -216.4", absf(saw.y - (-216.4)) < 0.01)
	# stump: (133-360, (353-240) - 0.48*480) = (-227.0, -117.4)
	var stump: Vector2 = n._lumber_fx_anchor(BuildingNode.LUMBER_FX_STUMP)
	_check("stump node x = -227.0", absf(stump.x - (-227.0)) < 0.01)
	_check("stump node y = -117.4", absf(stump.y - (-117.4)) < 0.01)
	_check("saw above base", saw.y < 0.0)
	_check("stump above base", stump.y < 0.0)
	# Scaling tracks _sprite_sc linearly (the restaurant precedent).
	n._sprite_sc = 2.0
	var saw2: Vector2 = n._lumber_fx_anchor(BuildingNode.LUMBER_FX_SAW)
	_check("saw scales 2x", absf(saw2.x - 2.0 * saw.x) < 0.01
		and absf(saw2.y - 2.0 * saw.y) < 0.01)
	n.free()


## The _process gate: complete lumber camps advance the FX step on the
## shared cadence; blueprints and every other type skip with one cheap
## check.
func _test_process_gates() -> void:
	var lc := _make_node("lumber_camp")
	lc._process(0.1)
	_check("complete lumber_camp advances fx step",
		lc._fx_step >= 0 and lc._fx_step < BuildingNode.EATERY_FX_STEPS)
	lc.free()
	var bp := _make_node("lumber_camp", "gnomes", false)
	bp._process(0.1)
	_check("lumber_camp blueprint stays static", bp._fx_step == -1)
	bp.free()
	var farm := _make_node("farm", "gnomes")
	farm._process(0.1)
	_check("farm keeps its own gate, not the lumber one",
		farm._fx_step >= 0 and farm._fx_step < BuildingNode.EATERY_FX_STEPS)
	farm.free()
	var sawmill := _make_node("sawmill", "gnomes")
	sawmill._process(0.1)
	_check("sawmill keeps its industrial fx, not the lumber gate",
		sawmill._fx_step >= 0
		and "sawmill" in BuildingNode.INDUSTRIAL_FX_BTYPES
		and not ("sawmill" in BuildingNode.LUMBER_FX_BTYPES))
	sawmill.free()
	# The draw hook starts disarmed.
	var n := _make_node("lumber_camp")
	_check("fx hook starts disarmed", n._last_lumber_fx == "")
	n.free()
