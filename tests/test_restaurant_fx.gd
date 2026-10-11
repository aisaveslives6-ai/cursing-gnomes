extends SceneTree
## Cursing Gnomes — restaurant kitchen FX (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## The C61 per-race faction eateries (taco/turkey/acorn/cheese per race,
## the soul cafe for undead and as its own btype) drew real sprite art
## with zero ambient FX — every other eatery breathes (EATERY_FX vent
## puffs, tavern chimneys). Complete restaurants/soul_cafes now breathe
## on the shared quantized FX cadence (8 steps at 6/sec — the tavern
## precedent): living kitchens exhale 3 staggered steam puffs from the
## art-measured chimney/vent mouth, and the soul cafe breathes 3 green
## soul wisps off the cup, drifting left like the wisps baked into its
## art. Blueprints stay dark. Anchors measured off the real sprites.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_restaurant_fx.gd
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
	print("=== Cursing Gnomes restaurant FX tests ===")
	_test_roster()
	_test_art_key()
	_test_anchors()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: restaurant + soul_cafe only — every other family
## keeps its own path.
func _test_roster() -> void:
	_check("roster contains restaurant",
		"restaurant" in BuildingNode.RESTAURANT_FX_BTYPES)
	_check("roster contains soul_cafe",
		"soul_cafe" in BuildingNode.RESTAURANT_FX_BTYPES)
	_check("roster has exactly 2 types",
		BuildingNode.RESTAURANT_FX_BTYPES.size() == 2)
	for b in ["farm", "flesh_farm", "inn", "hotel", "shop", "house",
			"town_hall", "greasy_spoon", "barracks", "wall"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.RESTAURANT_FX_BTYPES))
	_check("taco tex 1531x1531",
		BuildingNode.RESTAURANT_FX_TEX["taco"] == Vector2(1531.0, 1531.0))
	_check("turkey tex 1471x1484",
		BuildingNode.RESTAURANT_FX_TEX["turkey"] == Vector2(1471.0, 1484.0))
	_check("acorn tex 1338x1121",
		BuildingNode.RESTAURANT_FX_TEX["acorn"] == Vector2(1338.0, 1121.0))
	_check("cheese tex 1553x1274",
		BuildingNode.RESTAURANT_FX_TEX["cheese"] == Vector2(1553.0, 1274.0))
	_check("soul_cafe tex 1024x512",
		BuildingNode.RESTAURANT_FX_TEX["soul_cafe"] == Vector2(1024.0, 512.0))
	_check("5 vent anchors", BuildingNode.RESTAURANT_FX_VENT.size() == 5)


## restaurant_fx_art_key is pure: per-race art routing, "" for anything
## without a kitchen vent.
func _test_art_key() -> void:
	_check("gnome restaurant -> taco",
		BuildingNode.restaurant_fx_art_key("restaurant", "gnomes") == "taco")
	_check("ogre restaurant -> turkey",
		BuildingNode.restaurant_fx_art_key("restaurant", "ogres") == "turkey")
	_check("elf restaurant -> acorn",
		BuildingNode.restaurant_fx_art_key("restaurant", "elves") == "acorn")
	_check("human restaurant -> cheese",
		BuildingNode.restaurant_fx_art_key("restaurant", "humans") == "cheese")
	_check("undead restaurant -> soul_cafe",
		BuildingNode.restaurant_fx_art_key("restaurant", "undead") == "soul_cafe")
	_check("soul_cafe btype -> soul_cafe",
		BuildingNode.restaurant_fx_art_key("soul_cafe", "gnomes") == "soul_cafe")
	_check("unknown faction falls back to taco",
		BuildingNode.restaurant_fx_art_key("restaurant", "dragons") == "taco")
	_check("inn has no restaurant vent",
		BuildingNode.restaurant_fx_art_key("inn", "gnomes") == "")
	_check("wall has no restaurant vent",
		BuildingNode.restaurant_fx_art_key("wall", "gnomes") == "")


## Vent anchors: const values match the sprite measurements, and the
## art->node conversion tracks the real render scale.
func _test_anchors() -> void:
	_check("taco vent (795,358)",
		BuildingNode.RESTAURANT_FX_VENT["taco"] == Vector2(795.0, 358.0))
	_check("turkey vent (410,395)",
		BuildingNode.RESTAURANT_FX_VENT["turkey"] == Vector2(410.0, 395.0))
	_check("acorn vent (400,205)",
		BuildingNode.RESTAURANT_FX_VENT["acorn"] == Vector2(400.0, 205.0))
	_check("cheese vent (468,273)",
		BuildingNode.RESTAURANT_FX_VENT["cheese"] == Vector2(468.0, 273.0))
	_check("soul_cafe vent (508,150)",
		BuildingNode.RESTAURANT_FX_VENT["soul_cafe"] == Vector2(508.0, 150.0))
	var n := _make_node("restaurant")
	n._sprite_sc = 1.0
	# (ap.x - w/2, ap.y - h/2 - 0.48h) at unit scale.
	var taco: Vector2 = n._restaurant_fx_anchor("taco")
	_check("taco node x = 29.5", absf(taco.x - 29.5) < 0.01)
	_check("taco node y = -1142.38", absf(taco.y - (-1142.38)) < 0.01)
	var turkey: Vector2 = n._restaurant_fx_anchor("turkey")
	_check("turkey node x = -325.5", absf(turkey.x - (-325.5)) < 0.01)
	_check("turkey node y = -1059.32", absf(turkey.y - (-1059.32)) < 0.01)
	var acorn: Vector2 = n._restaurant_fx_anchor("acorn")
	_check("acorn node x = -269.0", absf(acorn.x - (-269.0)) < 0.01)
	_check("acorn node y = -893.58", absf(acorn.y - (-893.58)) < 0.01)
	var cheese: Vector2 = n._restaurant_fx_anchor("cheese")
	_check("cheese node x = -308.5", absf(cheese.x - (-308.5)) < 0.01)
	_check("cheese node y = -975.52", absf(cheese.y - (-975.52)) < 0.01)
	var soul: Vector2 = n._restaurant_fx_anchor("soul_cafe")
	_check("soul_cafe node x = -4.0", absf(soul.x - (-4.0)) < 0.01)
	_check("soul_cafe node y = -351.76", absf(soul.y - (-351.76)) < 0.01)
	# The overlay sits over the art, above the ground line: every anchor
	# has negative y (drawn upward from the building base).
	for key in ["taco", "turkey", "acorn", "cheese", "soul_cafe"]:
		_check("anchor above base: %s" % key,
			n._restaurant_fx_anchor(key).y < 0.0)
	n.free()


## The _process gate: complete restaurants/soul_cafes advance the FX step
## on the shared cadence; blueprints and every other type skip with one
## cheap check.
func _test_process_gates() -> void:
	var r := _make_node("restaurant")
	r._process(0.1)
	_check("complete restaurant advances fx step",
		r._fx_step >= 0 and r._fx_step < BuildingNode.EATERY_FX_STEPS)
	r.free()
	var sc := _make_node("soul_cafe", "undead")
	sc._process(0.1)
	_check("complete soul_cafe advances fx step",
		sc._fx_step >= 0 and sc._fx_step < BuildingNode.EATERY_FX_STEPS)
	sc.free()
	var bp := _make_node("restaurant", "gnomes", false)
	bp._process(0.1)
	_check("restaurant blueprint stays static", bp._fx_step == -1)
	bp.free()
	var garden := _make_node("garden", "gnomes")
	garden._process(0.1)
	_check("garden skips restaurant fx", garden._fx_step == -1)
	garden.free()
	var inn := _make_node("inn", "gnomes")
	inn._process(0.1)
	_check("inn keeps its own gate, not the restaurant one",
		inn._fx_step >= 0 and inn._fx_step < BuildingNode.EATERY_FX_STEPS)
	inn.free()
	# The draw hook starts disarmed.
	var n := _make_node("restaurant")
	_check("fx hook starts disarmed", n._last_restaurant_fx == "")
	n.free()
