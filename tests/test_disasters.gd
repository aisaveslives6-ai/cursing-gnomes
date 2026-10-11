extends SceneTree
## Cursing Gnomes — volcano disaster tests (HTML VOLCANO80/91 port).
##
## Covers: eruption timer init/reset range, erupt_volcano_at site rules
## (margins, hall distance, water, site spacing), peak forging (4-6
## unmineable peaks), unit shove, blast fires, 10-site cap, peak hardening
## into mineral deposits, save/load round trip.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_disasters.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _last_disaster: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes volcano disaster tests ===")
	_test_volcano_timer_init()
	_test_volcano_erupt_valid()
	_test_volcano_site_rules()
	_test_volcano_shove()
	_test_volcano_cap()
	_test_volcano_timer_fires()
	_test_volcano_harden()
	_test_volcano_save()
	_test_bandit_pack_size()
	_test_firefighter_sfx()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	return gs


func _new_disasters(gs: GameState) -> DisasterSim:
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	_last_disaster.clear()
	gs.bus.disaster_spawned.connect(_on_disaster_spawned)
	return d


func _on_disaster_spawned(kind: String, pos: Vector2) -> void:
	_last_disaster = [kind, pos]


func _add_unit(gs: GameState, pos: Vector2) -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": "worker", "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
	})


## ---- volcano: timer --------------------------------------------------------


func _test_volcano_timer_init() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_check("timer init range",
		d.volcano_timer >= 600.0 and d.volcano_timer <= 1500.0)
	d.reset_volcano_timer()
	_check("timer reset range",
		d.volcano_timer >= 600.0 and d.volcano_timer <= 1500.0)


func _test_volcano_timer_fires() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	d.volcano_timer = 0.05
	d.tick(0.1)
	_check("timer eruption formed", d.volcano_sites.size() == 1)
	_check("timer re-rolled",
		d.volcano_timer >= 600.0 and d.volcano_timer <= 1500.0)
	_check("timer announced", _last_disaster == ["volcano",
		(d.volcano_sites[0] as Dictionary)["position"]])


## ---- volcano: eruption ------------------------------------------------------


func _test_volcano_erupt_valid() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var center := Vector2(2048, 2048)
	_check("erupt ok", d.erupt_volcano_at(center))
	_check("one site", d.volcano_sites.size() == 1)
	var site: Dictionary = d.volcano_sites[0]
	_check("site record",
		site["position"] == center \
		and float(site["radius"]) == 280.0 \
		and is_equal_approx(float(site["peak"]), 0.26))
	var peak_ids: Array = site["peak_ids"]
	_check("4-6 peaks", peak_ids.size() >= 4 and peak_ids.size() <= 6)
	var peaks_ok := true
	for pid in peak_ids:
		var s: Dictionary = gs.get_work_site(int(pid))
		if s.is_empty() or String(s.get("kind", "")) != "volcano_peak" \
				or not bool(s.get("volcanic", false)) \
				or float(s.get("amount", -1.0)) != 0.0:
			peaks_ok = false
	_check("peaks unmineable terrain", peaks_ok)
	# The two mortar blasts seed fires (2 blasts + 2 side fires).
	var near_fires := 0
	for f: Dictionary in d.fires:
		if center.distance_to(f.get("position", Vector2.ZERO)) < 400.0:
			near_fires += 1
	_check("blast fires seeded", near_fires >= 2)
	_check("disaster announced", _last_disaster[0] == "volcano"
		and _last_disaster[1] == center)


func _test_volcano_site_rules() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	# Too close to the map edge.
	_check("edge rejected", not d.erupt_volcano_at(Vector2(100, 100)))
	# Too close to a town.
	gs.found_town("humans", "Testville", Vector2(2048, 2048))
	_check("hall rejected",
		not d.erupt_volcano_at(Vector2(2048 + 300, 2048)))
	# A valid first site.
	_check("far site ok", d.erupt_volcano_at(Vector2(2048, 3200)))
	# Too close to the existing site (within 280 + 280).
	_check("site spacing",
		not d.erupt_volcano_at(Vector2(2048, 3200 + 400)))
	# Far enough from it works.
	_check("spaced site ok",
		d.erupt_volcano_at(Vector2(2048, 3200 - 700)))
	_check("two sites", d.volcano_sites.size() == 2)


func _test_volcano_shove() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var center := Vector2(2048, 2048)
	var near := _add_unit(gs, center + Vector2(100, 0))
	var far := _add_unit(gs, center + Vector2(300, 0))
	d.erupt_volcano_at(center)
	var near_pos: Vector2 = near["position"]
	_check("unit shoved out",
		is_equal_approx(center.distance_to(near_pos), 200.0))
	var far_pos: Vector2 = far["position"]
	_check("far unit untouched",
		is_equal_approx(center.distance_to(far_pos), 300.0))
	# Nobody was hurt by the shove itself.
	_check("no shove damage",
		float(near.get("hp", 0.0)) == 100.0 \
		and float(far.get("hp", 0.0)) == 100.0)


func _test_volcano_cap() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var made := 0
	for gx in 4:
		for gy in 3:
			var p := Vector2(800.0 + gx * 900.0, 800.0 + gy * 900.0)
			if d.erupt_volcano_at(p):
				made += 1
				if made >= 10:
					break
		if made >= 10:
			break
	_check("10 sites formed", d.volcano_sites.size() == 10)
	# The timer path refuses an 11th site.
	d.volcano_timer = 0.01
	d.tick(0.05)
	_check("cap holds", d.volcano_sites.size() == 10)


## ---- volcano: hardening -----------------------------------------------------


func _test_volcano_harden() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	d.erupt_volcano_at(Vector2(2048, 2048))
	var site: Dictionary = d.volcano_sites[0]
	# Age the peaks past their harden delay.
	for pid in site["peak_ids"]:
		var s: Dictionary = gs.get_work_site(int(pid))
		s["born"] = -10000.0
		s["harden_after"] = 300.0
	d.tick(1.1)  # hardening checks run at 1 Hz
	var hardened_ok := true
	for pid in site["peak_ids"]:
		var s: Dictionary = gs.get_work_site(int(pid))
		if bool(s.get("volcanic", true)) \
				or String(s.get("kind", "")) != "gold_vein" \
				or float(s.get("amount", 0.0)) < 1500.0 \
				or float(s.get("amount", 0.0)) > 3000.0 \
				or not String(s.get("mineral", "")) \
					in ["crystal", "gold", "silver", "iron", "stone"]:
			hardened_ok = false
	_check("peaks hardened to minerals", hardened_ok)


func _test_volcano_save() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	d.volcano_timer = 1234.5
	d.erupt_volcano_at(Vector2(2048, 2048))
	var data: Dictionary = d.to_dict()
	var gs2 := _new_game(["humans"])
	var d2 := _new_disasters(gs2)
	d2.from_dict(data)
	_check("timer saved", is_equal_approx(d2.volcano_timer, 1234.5))
	_check("sites saved", d2.volcano_sites.size() == 1)
	var s: Dictionary = d2.volcano_sites[0]
	_check("site fields",
		s["position"] == Vector2(2048, 2048) \
		and (s["peak_ids"] as Array).size() >= 4)


## ---- bandit raid: HTML 5-8 pack parity --------------------------------------
## HTML BanditRaid: const n = 5 + Math.floor(Math.random() * 4); // 5-8


func _test_bandit_pack_size() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var seen := {}
	for s in range(200):
		seed(1000 + s)
		# Clear prior raid so the one-raid-at-a-time guard doesn't trip.
		for u: Dictionary in gs.units:
			if String(u.get("job", "")) == "bandit":
				u["alive"] = false
		var first: Dictionary = d._spawn_bandits(Vector2(500.0, 500.0))
		var n := 0
		for u: Dictionary in gs.units:
			if bool(u.get("alive", false)) \
					and String(u.get("job", "")) == "bandit":
				n += 1
		_check("bandit pack within 5-8 (seed %d -> %d)" % [s, n],
			n >= 5 and n <= 8)
		seen[n] = int(seen.get(n, 0)) + 1
		_check("raid returns a bandit", not first.is_empty() \
			and String(first.get("job", "")) == "bandit")
	_check("bandit pack size varies across seeds", seen.keys().size() > 1)


## ---- firefighter SFX: HTML c59 parity --------------------------------------
## HTML (fix79) plays SFX.hose59 at the firefighter while spraying water
## (c59FirefighterSpray) and SFX.hiss59 when a fire is put OUT by water
## (c59OnFireOut). Natural burnout has no sound.


func _test_firefighter_sfx() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var hits: Array = []
	gs.bus.sfx_spatial.connect(
		func(sfx_name: String, _pos: Vector2, _vel: Vector2) -> void:
			hits.append(sfx_name))
	var f: Dictionary = d.ignite(Vector2(100, 100), 60.0)
	var u: Dictionary = _add_unit(gs, Vector2(100, 100))
	u["job"] = "firefighter"
	# In range -> spraying: hose hisses.
	d.tick_firefighter(u, 0.1)
	_check("firefighter spraying emits hose59", "hose59" in hits)
	# Hose is throttled per unit (1.1 s): next tick stays silent.
	hits.clear()
	d.tick_firefighter(u, 0.1)
	_check("hose59 throttled while spraying", not ("hose59" in hits))
	# Drive intensity to zero -> put-out steams.
	var safety := 0
	while not d.fires.is_empty() and safety < 20:
		u["_hose_sfx_cd"] = 999.0  # silence hose; only put-out should sound
		d.tick_firefighter(u, 1.0)
		safety += 1
	_check("fire gone after firefighting", d.fires.is_empty())
	_check("put-out by water emits hiss59", "hiss59" in hits)
	# Natural burnout is silent (HTML: no c59OnFireOut without water).
	hits.clear()
	var f2: Dictionary = d.ignite(Vector2(500, 500), 1.0)
	d.extinguish(f2)
	_check("burnout extinguish is silent (no hiss59)", not ("hiss59" in hits))
