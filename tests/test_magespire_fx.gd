extends SceneTree
## Cursing Gnomes — mage spire arcane FX (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## The spire crowns stood perfectly still. Complete spires now breathe
## arcane light from their real crown crystals on the shared quantized FX
## cadence (8 steps at 6/sec): each race's crystal tint pulses and three
## spark motes rise from it. The arcane flicker is a pure function
## (magespire_flicker_for) so the math is pinned without rendering;
## anchors are verified against the sprite art they were measured from;
## _process gates keep blueprints dark and other buildings untouched.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_magespire_fx.gd
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


func _make_node(btype: String, faction := "humans",
		complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes mage spire arcane FX tests ===")
	_test_roster()
	_test_art_keys()
	_test_anchors()
	_test_flicker()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: mage spires, and nothing else.
func _test_roster() -> void:
	_check("roster contains mage_spire",
		"mage_spire" in BuildingNode.MAGESPIRE_FX_BTYPES)
	_check("roster has exactly 1 type",
		BuildingNode.MAGESPIRE_FX_BTYPES.size() == 1)
	for b in ["house", "farmhouse", "oil_pump", "town_hall", "windmill",
			"monastery", "inn", "hotel", "sawmill", "weaponsmith"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.MAGESPIRE_FX_BTYPES))


## Art-key routing: the four living races use their per-race crystal art;
## undead (and anything unexpected) falls back to the tower; non-spires
## get no key at all.
func _test_art_keys() -> void:
	_check("humans key", BuildingNode.magespire_fx_art_key(
		"mage_spire", "humans") == "humans")
	_check("elves key", BuildingNode.magespire_fx_art_key(
		"mage_spire", "elves") == "elves")
	_check("gnomes key", BuildingNode.magespire_fx_art_key(
		"mage_spire", "gnomes") == "gnomes")
	_check("ogres key", BuildingNode.magespire_fx_art_key(
		"mage_spire", "ogres") == "ogres")
	_check("undead falls back to tower", BuildingNode.magespire_fx_art_key(
		"mage_spire", "undead") == "tower")
	_check("house gets no key", BuildingNode.magespire_fx_art_key(
		"house", "humans") == "")
	_check("monastery gets no key", BuildingNode.magespire_fx_art_key(
		"monastery", "humans") == "")
	# Test hook starts disarmed.
	var n := _make_node("mage_spire")
	_check("fx hook starts disarmed", n._last_magespire_fx == "")
	n.free()


## Anchors match the sprite art they were measured from: crystal centers
## in art px, all 246x480 files, crystals near the top-center of the art.
## Anchor math is the _house_fx_anchor precedent (verified at sc = 1.0).
func _test_anchors() -> void:
	var tex: Dictionary = BuildingNode.MAGESPIRE_FX_TEX
	var crys: Dictionary = BuildingNode.MAGESPIRE_FX_CRYSTAL
	for key in ["elves", "gnomes", "humans", "ogres", "tower"]:
		var t: Vector2 = tex[key]
		_check("%s tex is 246x480" % key,
			absf(t.x - 246.0) < 0.01 and absf(t.y - 480.0) < 0.01)
		var c: Vector2 = crys[key]
		_check("%s crystal near horizontal center" % key,
			absf(c.x - 123.0) <= 2.0)
		_check("%s crystal in top quarter" % key, c.y < 120.0)
	# Measured values (2026-10-09 pixel scan).
	_check("human crystal (122,41)",
		crys["humans"] == Vector2(122.0, 41.0))
	_check("elf crystal (124,38)",
		crys["elves"] == Vector2(124.0, 38.0))
	_check("gnome crystal (123,41)",
		crys["gnomes"] == Vector2(123.0, 41.0))
	_check("ogre crystal (123,42)",
		crys["ogres"] == Vector2(123.0, 42.0))
	_check("undead roof peak (123,24)",
		crys["tower"] == Vector2(123.0, 24.0))
	# Anchor math at unit scale: (ap.x - w/2, ap.y - h/2 - 0.48h).
	var n := _make_node("mage_spire")
	n._sprite_sc = 1.0
	var ha: Vector2 = n._magespire_fx_anchor("humans")
	_check("human anchor x = -1.0", absf(ha.x - (-1.0)) < 0.01)
	_check("human anchor y = -429.4", absf(ha.y - (-429.4)) < 0.01)
	var ta: Vector2 = n._magespire_fx_anchor("tower")
	_check("tower anchor x = 0.0", absf(ta.x) < 0.01)
	_check("tower anchor y = -446.4", absf(ta.y - (-446.4)) < 0.01)
	n.free()
	# Every art key has a tint.
	var tints: Dictionary = BuildingNode.MAGESPIRE_FX_TINT
	for key in ["elves", "gnomes", "humans", "ogres", "tower"]:
		_check("%s has tint" % key, tints.has(key))


## The flicker is arcane: bounded 0.70..1.0, varies with the step, and the
## phase shifts the wave (per-building offsets desync spires).
func _test_flicker() -> void:
	var lo := 2.0
	var hi := -1.0
	var seen := {}
	for s in range(BuildingNode.EATERY_FX_STEPS):
		for p in [0.0, 1.4, 2.8, 4.2]:
			var f := BuildingNode.magespire_flicker_for(s, p)
			lo = minf(lo, f)
			hi = maxf(hi, f)
			seen[f] = true
	_check("flicker lower bound 0.70", lo >= 0.70 - 0.001)
	_check("flicker upper bound 1.0", hi <= 1.0 + 0.001)
	_check("flicker varies across steps", seen.size() > 4)
	_check("phase 0 vs 1.4 differ at step 0",
		absf(BuildingNode.magespire_flicker_for(0, 0.0)
			- BuildingNode.magespire_flicker_for(0, 1.4)) > 0.01)
	# Full-cycle determinism: same step+phase always gives the same value.
	_check("flicker deterministic",
		BuildingNode.magespire_flicker_for(5, 2.8)
			== BuildingNode.magespire_flicker_for(5, 2.8))


## _process animates only complete spires: blueprints stay dark and other
## buildings never touch the spire FX step.
func _test_process_gates() -> void:
	var m := _make_node("mage_spire")
	m._process(0.1)
	_check("complete spire advances fx step",
		m._fx_step >= 0 and m._fx_step < BuildingNode.EATERY_FX_STEPS)
	m.free()
	var bp := _make_node("mage_spire", "humans", false)
	bp._process(0.1)
	_check("blueprint spire stays static", bp._fx_step == -1)
	bp.free()
	var undead := _make_node("mage_spire", "undead")
	undead._process(0.1)
	_check("undead spire advances fx step",
		undead._fx_step >= 0
		and undead._fx_step < BuildingNode.EATERY_FX_STEPS)
	undead.free()
	var house := _make_node("house")
	house._process(0.1)
	_check("house keeps its own fx step (spire gate untouched)",
		house._fx_step >= 0)
	house.free()
	var mon := _make_node("monastery")
	mon._process(0.1)
	_check("monastery keeps its own fx step (spire gate untouched)",
		mon._fx_step >= 0)
	mon.free()
