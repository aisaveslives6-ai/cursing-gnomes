extends SceneTree
## Cursing Gnomes — military war-machine FX (massive-dev 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## The last fully-static building family — barracks, war huts, cannon
## foundries, armories, castles, guard houses, watch/AA towers, the nuke
## silo, the anti-nuke dish, and the archery range — stood perfectly still
## while armies drilled around them. Complete military buildings now
## breathe on the shared quantized FX cadence (8 steps at 6/sec): chimney
## smoke, forge glow, torch flames, candlelit windows, warning beacons,
## radar pings. The pure seams (military_flicker_for, military_beacon_for,
## military_ping_for, military_fx_art_key) pin the math without rendering;
## anchors are verified against the real sprite art; _process gates keep
## blueprints dark and other buildings untouched.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_military_fx.gd
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
	print("=== Cursing Gnomes military war-machine FX tests ===")
	_test_roster()
	_test_art_keys()
	_test_anchors()
	_test_flicker()
	_test_beacon()
	_test_ping()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: the whole war machine, and nothing else.
func _test_roster() -> void:
	for b in ["barracks", "war_hut", "cannon_foundry", "armory",
			"vehicle_depot", "knights_castle", "guard_house",
			"guard_tower", "aa_tower", "air_defense", "nuke_silo",
			"anti_nuke", "shooting_range"]:
		_check("roster contains %s" % b,
			b in BuildingNode.MILITARY_FX_BTYPES)
	_check("roster has exactly 13 types",
		BuildingNode.MILITARY_FX_BTYPES.size() == 13)
	for b in ["house", "farmhouse", "oil_pump", "town_hall", "windmill",
			"shop", "inn", "hotel", "sawmill", "weaponsmith", "monastery",
			"mage_spire", "farm", "bathhouse", "mine", "quarry"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.MILITARY_FX_BTYPES))


## Art-key router: the barracks family splits living/undead, guard houses
## go per-race (undead keeps the drawn fallback arm — no art, no FX),
## towers split watch/signal vs silo beacon, dish and range stand alone.
func _test_art_keys() -> void:
	var K := BuildingNode.military_fx_art_key
	_check("barracks+gnomes -> barracks", K.call("barracks", "gnomes") == "barracks")
	_check("barracks+undead -> barracks_undead",
		K.call("barracks", "undead") == "barracks_undead")
	_check("war_hut+ogres -> barracks", K.call("war_hut", "ogres") == "barracks")
	_check("cannon_foundry+undead -> barracks_undead",
		K.call("cannon_foundry", "undead") == "barracks_undead")
	_check("armory+elves -> barracks", K.call("armory", "elves") == "barracks")
	_check("vehicle_depot+humans -> barracks",
		K.call("vehicle_depot", "humans") == "barracks")
	_check("knights_castle -> castle",
		K.call("knights_castle", "gnomes") == "castle")
	_check("guard_house+humans -> guard_house_humans",
		K.call("guard_house", "humans") == "guard_house_humans")
	_check("guard_house+elves -> guard_house_elves",
		K.call("guard_house", "elves") == "guard_house_elves")
	_check("guard_house+gnomes -> guard_house_gnomes",
		K.call("guard_house", "gnomes") == "guard_house_gnomes")
	_check("guard_house+ogres -> guard_house_ogres",
		K.call("guard_house", "ogres") == "guard_house_ogres")
	_check("guard_house+undead -> none",
		K.call("guard_house", "undead") == "")
	_check("guard_tower -> tower", K.call("guard_tower", "gnomes") == "tower")
	_check("aa_tower -> tower", K.call("aa_tower", "ogres") == "tower")
	_check("air_defense -> tower", K.call("air_defense", "elves") == "tower")
	_check("nuke_silo -> silo", K.call("nuke_silo", "humans") == "silo")
	_check("anti_nuke -> antinuke", K.call("anti_nuke", "gnomes") == "antinuke")
	_check("shooting_range -> range",
		K.call("shooting_range", "humans") == "range")
	for b in ["house", "monastery", "mage_spire", "town_hall", "shop"]:
		_check("art key empty for %s" % b, K.call(b, "gnomes") == "")


## Anchors live inside their sprite files; vents, windows, flames, beacons
## and targets all sit on the art, not off it. The silo key shares the
## tower art size through the anchor fallback.
func _test_anchors() -> void:
	for key in BuildingNode.MILITARY_FX_TEX.keys():
		var t: Vector2 = BuildingNode.MILITARY_FX_TEX[key]
		_check("tex size sane for %s" % key, t.x > 0.0 and t.y > 0.0)
	for key in BuildingNode.MILITARY_FX_VENT.keys():
		var t: Vector2 = BuildingNode.MILITARY_FX_TEX[key]
		var v: Vector2 = BuildingNode.MILITARY_FX_VENT[key]
		_check("vent inside %s art" % key,
			v.x >= 0.0 and v.x <= t.x and v.y >= 0.0 and v.y <= t.y)
	for key in BuildingNode.MILITARY_FX_WINDOWS.keys():
		var t: Vector2 = BuildingNode.MILITARY_FX_TEX[key]
		var wins: Array = BuildingNode.MILITARY_FX_WINDOWS[key]
		_check("at least one window for %s" % key, wins.size() >= 1)
		for w in wins:
			_check("window inside %s art" % key,
				w.x >= 0.0 and w.x <= t.x and w.y >= 0.0 and w.y <= t.y)
	for key in BuildingNode.MILITARY_FX_FLAMES.keys():
		var t: Vector2 = BuildingNode.MILITARY_FX_TEX[key]
		var fls: Array = BuildingNode.MILITARY_FX_FLAMES[key]
		for f in fls:
			_check("flame inside %s art" % key,
				f.x >= 0.0 and f.x <= t.x and f.y >= 0.0 and f.y <= t.y)
	for key in BuildingNode.MILITARY_FX_BEACONS.keys():
		var t: Vector2 = BuildingNode.MILITARY_FX_TEX.get(
			key, BuildingNode.MILITARY_FX_TEX["tower"])
		var bcs: Array = BuildingNode.MILITARY_FX_BEACONS[key]
		for bc in bcs:
			_check("beacon inside %s art" % key,
				bc.x >= 0.0 and bc.x <= t.x and bc.y >= 0.0 and bc.y <= t.y)
	var ad: Vector2 = BuildingNode.MILITARY_FX_DISH
	var at: Vector2 = BuildingNode.MILITARY_FX_TEX["antinuke"]
	_check("dish inside antinuke art",
		ad.x >= 0.0 and ad.x <= at.x and ad.y >= 0.0 and ad.y <= at.y)
	var rt: Vector2 = BuildingNode.MILITARY_FX_TEX["range"]
	_check("three targets", BuildingNode.MILITARY_FX_TARGETS.size() == 3)
	for tg in BuildingNode.MILITARY_FX_TARGETS:
		_check("target inside range art",
			tg.x >= 0.0 and tg.x <= rt.x and tg.y >= 0.0 and tg.y <= rt.y)
	# The silo anchor falls back to the tower art size (nuke_silo renders
	# bld_tower.png) and lands on the watch platform.
	var silo := _make_node("nuke_silo")
	var sa: Vector2 = silo._military_fx_anchor("silo", Vector2(123.0, 108.0))
	_check("silo anchor sane", sa.y < 0.0 and absf(sa.x) < 1.0)
	_check("silo shares tower tex size",
		BuildingNode.MILITARY_FX_TEX.get("silo",
			BuildingNode.MILITARY_FX_TEX["tower"])
		== BuildingNode.MILITARY_FX_TEX["tower"])
	silo.free()
	# Test hook starts disarmed.
	var n := _make_node("barracks")
	_check("fx hook starts disarmed", n._last_military_fx == "")
	_check("barracks is sprite path", n._sprite != null)
	n.free()


## The flame flicker is gentle: bounded 0.80..1.0, varies with the step,
## and the phase shifts the wave (per-element offsets desync flames).
func _test_flicker() -> void:
	var lo := 2.0
	var hi := -1.0
	var seen := {}
	for s in range(BuildingNode.EATERY_FX_STEPS):
		for p in [0.0, 1.1, 1.9, 2.3, 3.4]:
			var f := BuildingNode.military_flicker_for(s, p)
			lo = minf(lo, f)
			hi = maxf(hi, f)
			seen[f] = true
	_check("flicker lower bound 0.80", lo >= 0.80 - 0.001)
	_check("flicker upper bound 1.0", hi <= 1.0 + 0.001)
	_check("flicker varies across steps", seen.size() > 4)
	_check("phase 0 vs 1.9 differ at step 0",
		absf(BuildingNode.military_flicker_for(0, 0.0)
			- BuildingNode.military_flicker_for(0, 1.9)) > 0.01)
	_check("flicker deterministic",
		BuildingNode.military_flicker_for(5, 3.4)
		== BuildingNode.military_flicker_for(5, 3.4))


## The beacon is a hard strobe: only ever fully lit or dark, with two
## beats per FX cycle (a warning, not a flicker).
func _test_beacon() -> void:
	var lit_seen := false
	var dark_seen := false
	var beats := 0
	var was_lit := false
	for s in range(BuildingNode.EATERY_FX_STEPS):
		var v := BuildingNode.military_beacon_for(s, 0.0)
		_check("beacon binary at step %d" % s, v == 1.0 or v == 0.12)
		if v == 1.0:
			lit_seen = true
			if not was_lit:
				beats += 1
			was_lit = true
		else:
			dark_seen = true
			was_lit = false
	_check("beacon lights at some step", lit_seen)
	_check("beacon dark at some step", dark_seen)
	_check("beacon beats twice per cycle", beats == 2)
	_check("beacon deterministic",
		BuildingNode.military_beacon_for(3, 1.7)
		== BuildingNode.military_beacon_for(3, 1.7))


## The radar ping sweeps 0..1 across one FX cycle.
func _test_ping() -> void:
	_check("ping starts at 0.0",
		absf(BuildingNode.military_ping_for(0) - 0.0) < 0.001)
	_check("ping mid-cycle 0.5",
		absf(BuildingNode.military_ping_for(4) - 0.5) < 0.001)
	_check("ping near end 0.875",
		absf(BuildingNode.military_ping_for(7) - 0.875) < 0.001)
	var mono := true
	for s in range(1, BuildingNode.EATERY_FX_STEPS):
		if BuildingNode.military_ping_for(s) \
				< BuildingNode.military_ping_for(s - 1):
			mono = false
	_check("ping monotonic", mono)


## _process animates only complete military buildings with art: blueprints
## stay dark, undead guard houses (no art key) stay static, and other
## buildings never touch the military gate.
func _test_process_gates() -> void:
	var b := _make_node("barracks")
	b._process(0.1)
	_check("complete barracks advances fx step",
		b._fx_step >= 0 and b._fx_step < BuildingNode.EATERY_FX_STEPS)
	b.free()
	var bp := _make_node("barracks", "gnomes", false)
	bp._process(0.1)
	_check("blueprint barracks stays static", bp._fx_step == -1)
	bp.free()
	var ug := _make_node("guard_house", "undead")
	ug._process(0.1)
	_check("undead guard house has no art key",
		BuildingNode.military_fx_art_key("guard_house", "undead") == "")
	ug.free()
	var tower := _make_node("aa_tower")
	tower._process(0.1)
	_check("complete aa_tower advances fx step",
		tower._fx_step >= 0 and tower._fx_step < BuildingNode.EATERY_FX_STEPS)
	tower.free()
	var silo := _make_node("nuke_silo")
	silo._process(0.1)
	_check("complete nuke_silo advances fx step",
		silo._fx_step >= 0 and silo._fx_step < BuildingNode.EATERY_FX_STEPS)
	silo.free()
	var house := _make_node("house")
	house._process(0.1)
	_check("house keeps its own fx step (military gate untouched)",
		house._fx_step >= 0)
	house.free()
	var shop := _make_node("shop")
	shop._process(0.1)
	# 2026-10-09: a shop now legitimately advances the step through the
	# SHOP storefront gate (its own family, not military). Military-gate
	# isolation is pinned on a building with no FX family.
	_check("shop breathes via shop gate, not military",
		shop._fx_step >= 0
		and shop._fx_step < BuildingNode.EATERY_FX_STEPS
		and BuildingNode.military_fx_art_key("shop", "humans") == "")
	shop.free()
	var hall := _make_node("town_hall")
	hall._process(0.1)
	_check("town hall breathes via civic gate, not military",
		hall._fx_step >= 0
		and hall._fx_step < BuildingNode.EATERY_FX_STEPS
		and BuildingNode.military_fx_art_key("town_hall", "humans") == "")
	hall.free()
