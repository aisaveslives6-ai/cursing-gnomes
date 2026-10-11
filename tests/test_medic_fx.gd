extends SceneTree
## Cursing Gnomes — medic-tent lantern FX (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## The medic tent (bld_tent_medic.png, 429x309) is the field hospital the AI
## raises twice per town plan — and drew real sprite art with zero ambient FX.
## Complete medic tents now breathe on the shared quantized FX cadence
## (8 steps at 6/sec — the shop/monastery precedent): the entrance lantern
## glows warm over the tent opening, phased per tent, deepened after dark.
## Blueprints stay dark. Anchor measured off the real sprite (398, 220).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_medic_fx.gd
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
	print("=== Cursing Gnomes medic-tent FX tests ===")
	_test_roster()
	_test_anchors()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: medic_camp only — every other family keeps its own
## path (clinics/bathhouses/tome_libraries share the bld_civic sprite but
## are deliberately NOT civic seats, so they stay on NightGlow only).
func _test_roster() -> void:
	_check("roster contains medic_camp",
		"medic_camp" in BuildingNode.MEDIC_FX_BTYPES)
	_check("roster has exactly 1 type",
		BuildingNode.MEDIC_FX_BTYPES.size() == 1)
	for b in ["clinic", "bathhouse", "tome_library", "farm", "inn", "hotel",
			"shop", "house", "town_hall", "oil_pump", "sawmill", "mine",
			"quarry", "barracks", "monastery", "wall"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.MEDIC_FX_BTYPES))
	_check("tex 429x309",
		BuildingNode.MEDIC_FX_TEX == Vector2(429.0, 309.0))
	_check("lantern anchor (398,220)",
		BuildingNode.MEDIC_FX_LANTERN == Vector2(398.0, 220.0))
	_check("lantern tint warm (1.0,0.80,0.45)",
		BuildingNode.MEDIC_LANTERN_TINT == Color(1.0, 0.80, 0.45))


## Anchors: the art->node conversion tracks the real render scale, and the
## lantern sits above the ground line over the art (never floating,
## never below the base).
func _test_anchors() -> void:
	var n := _make_node("medic_camp")
	n._sprite_sc = 1.0
	# lantern: (398-214.5, (220-154.5) - 0.48*309) = (183.5, -82.82)
	var lamp: Vector2 = n._medic_fx_anchor(BuildingNode.MEDIC_FX_LANTERN)
	_check("lamp node x = 183.5", absf(lamp.x - 183.5) < 0.01)
	_check("lamp node y = -82.82", absf(lamp.y - (-82.82)) < 0.01)
	_check("lamp above base", lamp.y < 0.0)
	# Scaling tracks _sprite_sc linearly (the restaurant precedent).
	n._sprite_sc = 2.0
	var lamp2: Vector2 = n._medic_fx_anchor(BuildingNode.MEDIC_FX_LANTERN)
	_check("lamp scales 2x", absf(lamp2.x - 2.0 * lamp.x) < 0.01
		and absf(lamp2.y - 2.0 * lamp.y) < 0.01)
	n.free()


## The _process gate: complete medic tents advance the FX step on the
## shared cadence; blueprints and every other type skip with one cheap
## check.
func _test_process_gates() -> void:
	var mc := _make_node("medic_camp")
	mc._process(0.1)
	_check("complete medic_camp advances fx step",
		mc._fx_step >= 0 and mc._fx_step < BuildingNode.EATERY_FX_STEPS)
	mc.free()
	var bp := _make_node("medic_camp", "gnomes", false)
	bp._process(0.1)
	_check("medic_camp blueprint stays static", bp._fx_step == -1)
	bp.free()
	var clinic := _make_node("clinic", "gnomes")
	clinic._process(0.1)
	_check("clinic keeps NightGlow only, not the medic gate",
		clinic._fx_step == -1
		and not ("clinic" in BuildingNode.MEDIC_FX_BTYPES))
	clinic.free()
	# The draw hook starts disarmed.
	var n := _make_node("medic_camp")
	_check("fx hook starts disarmed", n._last_medic_fx == "")
	n.free()
