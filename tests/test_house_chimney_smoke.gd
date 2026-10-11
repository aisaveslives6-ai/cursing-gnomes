extends SceneTree
## Cursing Gnomes — house chimney smoke (graphics-hourly 2026-10-07,
## Jeremy's standing "everything smoothly animated" rule).
##
## Houses are the most numerous buildings in the game and every one stood
## perfectly still. Complete houses now breathe smoke from their chimneys
## on the shared quantized FX cadence (8 steps at 6/sec — the eatery-vent
## precedent), pinned to the art through the real sprite render scale, and
## never run for blueprints or other building types. Undead houses exhale
## the same sickly green as the wisps baked into their sprite art.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_house_chimney_smoke.gd
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
	print("=== Cursing Gnomes house chimney smoke tests ===")
	_test_roster()
	_test_tint_key()
	_test_anchors()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: houses and farmhouses, and nothing else.
func _test_roster() -> void:
	_check("roster contains house", "house" in BuildingNode.HOUSE_FX_BTYPES)
	_check("roster contains farmhouse",
		"farmhouse" in BuildingNode.HOUSE_FX_BTYPES)
	_check("roster has exactly 2 types",
		BuildingNode.HOUSE_FX_BTYPES.size() == 2)
	for b in ["farm", "town_hall", "oil_pump", "barracks", "windmill",
			"eatery"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.HOUSE_FX_BTYPES))
	# Chimney mouths sit in the upper half of each sprite file.
	for key in ["house", "house_undead", "farmhouse"]:
		var ap: Vector2 = BuildingNode.HOUSE_FX_CHIMNEY[key]
		var tsize: Vector2 = BuildingNode.HOUSE_FX_TEX.get(
			key, BuildingNode.HOUSE_FX_TEX["house"])
		_check("%s chimney above art midpoint" % key,
			ap.y < tsize.y * 0.5)
		_check("%s chimney inside art width" % key,
			ap.x >= 0.0 and ap.x <= tsize.x)


## Only the undead house variant gets the green tint.
func _test_tint_key() -> void:
	_check("living house tint",
		BuildingNode.house_smoke_key("house", "gnomes") == "living")
	_check("undead house tint",
		BuildingNode.house_smoke_key("house", "undead") == "undead")
	_check("undead farmhouse stays living-tinted",
		BuildingNode.house_smoke_key("farmhouse", "undead") == "living")
	_check("undead town hall stays living-tinted",
		BuildingNode.house_smoke_key("town_hall", "undead") == "living")


## Anchors land on the art: the chimney mouth inside the sprite bounds,
## tracking the real render scale.
func _test_anchors() -> void:
	var n := _make_node("house")
	_check("house sprite loads", n._sprite != null)
	_check("fx method exists", n.has_method("_house_fx"))
	_check("anchor method exists", n.has_method("_house_fx_anchor"))
	var vent := n._house_fx_anchor("house")
	# _size_for("house") defaults to 30.0 -> target_w 72 -> sc 0.15 on the
	# 480px art. Chimney mouth art (315,128) -> x (315-240)*0.15 = 11.25,
	# y (128-240)*0.15 - 0.48*480*0.15 = -16.8 - 34.56 = -51.36.
	_check("vent x at chimney mouth", absf(vent.x - 11.25) < 0.6)
	_check("vent y at chimney mouth", absf(vent.y - (-51.36)) < 0.6)
	# Sprite spans x [-36, 36], y ~[-70.6, 1.4] at this scale: smoke must
	# not float away from the art.
	_check("vent inside sprite bounds",
		absf(vent.x) <= 36.0 and vent.y >= -71.0 and vent.y <= 2.0)
	n.free()
	var u := _make_node("house", "undead")
	_check("undead house sprite loads", u._sprite != null)
	var uvent := u._house_fx_anchor("house_undead")
	_check("undead vent differs from living vent", uvent != vent)
	_check("undead vent inside sprite bounds",
		absf(uvent.x) <= 36.0 and uvent.y >= -71.0 and uvent.y <= 2.0)
	u.free()
	var f := _make_node("farmhouse")
	_check("farmhouse sprite loads", f._sprite != null)
	var fvent := f._house_fx_anchor("farmhouse")
	var fsc := f._sprite_sc
	# 164x151 art: chimney (25,30) -> x (25-82)*sc, y (30-75.5)*sc - 0.48*151*sc.
	_check("farmhouse vent x at chimney",
		absf(fvent.x - (25.0 - 82.0) * fsc) < 0.6)
	_check("farmhouse vent y at chimney",
		absf(fvent.y - ((30.0 - 75.5) * fsc - 0.48 * 151.0 * fsc)) < 0.6)
	f.free()
	# Unknown keys fall back to the living-house anchors.
	var h2 := _make_node("house")
	_check("unknown key falls back to house anchors",
		h2._house_fx_anchor("bogus_key") == vent)
	h2.free()


## _process animates only complete houses/farmhouses: blueprints stay
## static and other buildings never touch the house FX step.
func _test_process_gates() -> void:
	var house := _make_node("house")
	house._process(0.1)
	_check("complete house advances fx step",
		house._fx_step >= 0 and house._fx_step < BuildingNode.EATERY_FX_STEPS)
	house.free()
	var farm := _make_node("farmhouse")
	farm._process(0.1)
	_check("complete farmhouse advances fx step",
		farm._fx_step >= 0 and farm._fx_step < BuildingNode.EATERY_FX_STEPS)
	farm.free()
	var bp := _make_node("house", "gnomes", false)
	bp._process(0.1)
	_check("house blueprint stays static", bp._fx_step == -1)
	bp.free()
	var farm_btype := _make_node("farm")
	farm_btype._process(0.1)
	# 2026-10-09: farms breathe via their own FARM_FX gate (crop sway),
	# not the house gate — the house roster still excludes them.
	_check("farm btype animates via farm gate, not house roster",
		"farm" in BuildingNode.FARM_FX_BTYPES
		and not ("farm" in BuildingNode.HOUSE_FX_BTYPES))
	farm_btype.free()
