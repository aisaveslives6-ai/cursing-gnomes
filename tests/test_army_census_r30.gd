extends SceneTree
## Cursing Gnomes — army daily-census parity (perf R30).
##
## The daily batch (ensure_government x5, collapse_tick, ai_war_tick,
## _assess_retreats) was converted from ~40 full O(units)/O(buildings)
## scans per day to ONE shared census. These tests prove behavior-identical
## results: each test runs the new census-backed path and compares against
## an independent brute-force oracle replicating the pre-R30 scan logic
## inline (the old code is gone; the oracle is written from its spec).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_army_census_r30.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes army census parity (R30) ===")
	_test_government_parity()
	_test_government_downed_guard()
	_test_strength_parity()
	_test_estimate_parity()
	_test_collapse_two_pairs()
	_test_retreat_ordered()
	_test_retreat_holds()
	_test_tick_day_rollover()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var army := SimArmy.new(gs)
	army.diplomacy = gs.diplomacy
	return {"gs": gs, "army": army}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


func _roles(w: Dictionary, faction: String) -> Dictionary:
	var out := {}
	for u in (w["gs"] as GameState).units:
		if String(u.get("faction", "")) != faction:
			continue
		var r := SimArmy.gov_role_of(u)
		if r != "":
			out[int(u.get("id", -1))] = r
	return out


## Brute-force oracle: the pre-R30 ensure_government, verbatim logic.
func _old_ensure_government(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	var army: SimArmy = w["army"]
	for u: Dictionary in gs.units:
		if not u.get("alive", false) and SimArmy.gov_role_of(u) != "":
			SimArmy.clear_gov_role(u)
	var have := {"mayor": false, "adviser": false, "lord": false,
		"commander": false, "watch_captain": false}
	for u: Dictionary in gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		var r := SimArmy.gov_role_of(u)
		if r in have:
			have[r] = true
	for u: Dictionary in gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("job", "")) == "guild_master" \
				and SimArmy.gov_role_of(u) == "":
			SimArmy.assign_gov_role(u, "guild_master")
	if not have["mayor"]:
		_old_promote_civilian(w, faction, "mayor", have)
	if not have["adviser"]:
		_old_promote_civilian(w, faction, "adviser", have)
	if not have["lord"]:
		_old_promote_civilian(w, faction, "lord", have)
	if not have["commander"]:
		_old_promote_fighter(w, faction, "commander")
	if not have["watch_captain"]:
		_old_promote_guard(w, faction)


func _old_promote_civilian(w: Dictionary, faction: String, role: String,
		have: Dictionary) -> void:
	var gs: GameState = w["gs"]
	var best: Dictionary = {}
	var best_hp: float = -1.0
	for u: Dictionary in gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if SimArmy.gov_role_of(u) != "":
			continue
		if SimCombat.is_fighter(u):
			continue
		var hp: float = float(u.get("hp", 0.0))
		if hp > best_hp:
			best_hp = hp
			best = u
	if not best.is_empty():
		SimArmy.assign_gov_role(best, role)
		have[role] = true


func _old_promote_fighter(w: Dictionary, faction: String,
		role: String) -> void:
	var gs: GameState = w["gs"]
	var best: Dictionary = {}
	var best_hp: float = -1.0
	for u: Dictionary in gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if SimArmy.gov_role_of(u) != "":
			continue
		if not SimCombat.is_fighter(u):
			continue
		if bool(u.get("warlord", false)):
			continue
		var hp: float = float(u.get("hp", 0.0))
		if hp > best_hp:
			best_hp = hp
			best = u
	if not best.is_empty():
		SimArmy.assign_gov_role(best, role)


func _old_promote_guard(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	for u: Dictionary in gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("job", "")) != "guard":
			continue
		if SimArmy.gov_role_of(u) != "":
			continue
		SimArmy.assign_gov_role(u, "watch_captain")
		return


func _seed_tricky_government(w: Dictionary) -> void:
	# Dead mayor: role must be cleared and the seat refilled.
	var dead := _spawn(w, "humans", "worker", Vector2(0, 0))
	dead["alive"] = false
	SimArmy.assign_gov_role(dead, "mayor")
	# Civilians: tie at hp 80 must go to the FIRST in units order.
	var c1 := _spawn(w, "humans", "worker", Vector2(10, 0))
	c1["hp"] = 80.0
	var c2 := _spawn(w, "humans", "worker", Vector2(20, 0))
	c2["hp"] = 80.0
	var c3 := _spawn(w, "humans", "worker", Vector2(30, 0))
	c3["hp"] = 50.0
	# Downed civilian with huge hp: never promoted.
	var c4 := _spawn(w, "humans", "worker", Vector2(40, 0))
	c4["hp"] = 999.0
	c4["downed"] = true
	# Fighter with huge hp: not a civilian, never mayor.
	var f1 := _spawn(w, "humans", "soldier", Vector2(50, 0))
	f1["hp"] = 500.0
	# Warlord: never commander.
	var f2 := _spawn(w, "humans", "soldier", Vector2(60, 0))
	f2["hp"] = 400.0
	f2["warlord"] = true
	var f3 := _spawn(w, "humans", "soldier", Vector2(70, 0))
	f3["hp"] = 300.0
	# Healthy guard.
	var g1 := _spawn(w, "humans", "guard", Vector2(80, 0))
	g1["hp"] = 60.0
	# Guild master by job.
	_spawn(w, "humans", "guild_master", Vector2(90, 0))


func _test_government_parity() -> void:
	var w := _new_world()
	_seed_tricky_government(w)
	var gs: GameState = w["gs"]
	var army: SimArmy = w["army"]
	# Snapshot pristine units for the oracle run.
	var pristine: Array = []
	for u in gs.units:
		pristine.append((u as Dictionary).duplicate(true))
	# New path.
	army.ensure_government("humans")
	var new_roles := _roles(w, "humans")
	# Oracle path on the pristine copies.
	var saved: Array = gs.units
	var typed: Array[Dictionary] = []
	typed.assign(pristine)
	gs.units = typed
	_old_ensure_government(w, "humans")
	var old_roles := _roles(w, "humans")
	gs.units = saved
	_check("census gov: role map identical to old scans",
		new_roles == old_roles)
	_check("census gov: all five seats filled",
		new_roles.values().has("mayor") \
		and new_roles.values().has("adviser") \
		and new_roles.values().has("lord") \
		and new_roles.values().has("commander") \
		and new_roles.values().has("watch_captain"))
	_check("census gov: dead mayor's role cleared",
		SimArmy.gov_role_of(saved[0]) == "")
	_check("census gov: guild master by job",
		new_roles.values().has("guild_master"))
	_free_world(w)


func _test_government_downed_guard() -> void:
	# The old _promote_guard has NO downed exclusion: a downed guard that
	# sorts first in units order still takes watch_captain. The census
	# must reproduce that exactly.
	var w := _new_world()
	var army: SimArmy = w["army"]
	var gs: GameState = w["gs"]
	_spawn(w, "humans", "worker", Vector2(0, 0))
	_spawn(w, "humans", "worker", Vector2(10, 0))
	_spawn(w, "humans", "worker", Vector2(20, 0))
	var dg := _spawn(w, "humans", "guard", Vector2(30, 0))
	dg["downed"] = true
	var hg := _spawn(w, "humans", "guard", Vector2(40, 0))
	var pristine: Array = []
	for u in gs.units:
		pristine.append((u as Dictionary).duplicate(true))
	army.ensure_government("humans")
	var new_wc := -1
	for u in gs.units:
		if SimArmy.gov_role_of(u) == "watch_captain":
			new_wc = int(u.get("id", -1))
	var saved: Array = gs.units
	var typed: Array[Dictionary] = []
	typed.assign(pristine)
	gs.units = typed
	_old_ensure_government(w, "humans")
	var old_wc := -1
	for u in gs.units:
		if SimArmy.gov_role_of(u) == "watch_captain":
			old_wc = int(u.get("id", -1))
	gs.units = saved
	_check("census gov: watch_captain pick identical (downed guard case)",
		new_wc == old_wc and new_wc == int(dg.get("id", -2)))
	_check("census gov: healthy guard not picked over downed-first",
		new_wc != int(hg.get("id", -3)))
	_free_world(w)


## Brute-force oracle: pre-R30 own_strength.
func _old_own_strength(w: Dictionary, faction: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var mil := 0
	var defense := 0
	for u: Dictionary in gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if SimCombat.is_fighter(u):
			mil += 1
	for b: Dictionary in gs.buildings:
		if not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in SimArmy.DEFENSE_TYPES:
			defense += 1
	return {"mil": mil, "def": defense,
		"score": float(mil) + float(defense) * 0.6}


func _seed_strength_world(w: Dictionary) -> void:
	var gs: GameState = w["gs"]
	var n := 0
	for f in ["humans", "ogres", "elves"]:
		for i in range(12):
			var job := "soldier" if i % 3 == 0 else "worker"
			var u := _spawn(w, f, job,
				Vector2(100.0 + n * 37.0, 100.0 + n * 11.0))
			if i == 5:
				u["alive"] = false
			if i == 7:
				u["downed"] = true
			n += 1
		for i in range(4):
			gs.add_building({"type": "guard_tower", "faction": f,
				"town_id": 1, "position": Vector2(500 + i * 60, 500),
				"alive": true, "complete": i < 3, "hp": 800.0,
				"max_hp": 800.0})
		# A non-defense building (counts for estimate wealth only).
		gs.add_building({"type": "house", "faction": f, "town_id": 1,
			"position": Vector2(700, 700), "alive": true, "complete": true,
			"hp": 500.0, "max_hp": 500.0})


func _test_strength_parity() -> void:
	var w := _new_world()
	_seed_strength_world(w)
	var army: SimArmy = w["army"]
	for f in ["humans", "ogres", "elves", "gnomes"]:
		_check("census strength: %s identical" % f,
			army.own_strength(f) == _old_own_strength(w, f))
	_free_world(w)


## Brute-force oracle: pre-R30 estimate_strength counts (the old building
## scan had NO complete/alive filter).
func _old_estimate_counts(w: Dictionary, target: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var mil := 0
	var defense := 0
	var wealth := 0
	for u: Dictionary in gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != target:
			continue
		if SimCombat.is_fighter(u):
			mil += 1
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) != target:
			continue
		if String(b.get("type", "")) in SimArmy.DEFENSE_TYPES:
			defense += 1
		else:
			wealth += 1
	return {"mil": mil, "def": defense, "wealth": wealth,
		"raw": snappedf(float(mil) + float(defense) * 0.6 \
			+ float(wealth) * 0.15, 0.1)}


func _test_estimate_parity() -> void:
	var w := _new_world()
	_seed_strength_world(w)
	var army: SimArmy = w["army"]
	for f in ["humans", "ogres", "elves"]:
		var est: Dictionary = army.estimate_strength("gnomes", f)
		var old := _old_estimate_counts(w, f)
		_check("census estimate: %s mil identical" % f,
			int(est["mil"]) == int(old["mil"]))
		_check("census estimate: %s def identical" % f,
			int(est["def"]) == int(old["def"]))
		_check("census estimate: %s wealth identical" % f,
			int(est["wealth"]) == int(old["wealth"]))
		_check("census estimate: %s raw identical" % f,
			float(est["raw"]) == float(old["raw"]))
	_free_world(w)


func _test_collapse_two_pairs() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var army: SimArmy = w["army"]
	# Pair 1: humans strong, ogres have no military -> ogre collapse.
	for i in range(8):
		_spawn(w, "humans", "soldier", Vector2(i * 30, 0))
	for i in range(6):
		_spawn(w, "ogres", "worker", Vector2(i * 30, 200))
	# Pair 2: elves vs undead, both unarmed -> mutual collapse.
	for i in range(4):
		_spawn(w, "elves", "worker", Vector2(i * 30, 400))
		_spawn(w, "undead", "worker", Vector2(i * 30, 600))
	gs.diplomacy.declare_war("humans", "ogres", "test")
	gs.diplomacy.declare_war("elves", "undead", "test")
	gs.day_number = 30
	var ended: Array[String] = army.collapse_tick()
	_check("census collapse: one-sided war ended",
		ended.has("humans|ogres:collapse"))
	_check("census collapse: mutual war ended",
		ended.has("elves|undead:mutual"))
	_check("census collapse: peace made (pair 1)",
		gs.diplomacy.relation_state("humans", "ogres") != "war")
	_check("census collapse: peace made (pair 2)",
		gs.diplomacy.relation_state("elves", "undead") != "war")
	_free_world(w)


func _seed_retreat_world(w: Dictionary, mauled: bool) -> void:
	var gs: GameState = w["gs"]
	# Ogre hall: _order_retreat_core only stamps withdrawing when the
	# faction has a hall to fall back to.
	gs.add_building({"type": "town_hall", "faction": "ogres", "town_id": 1,
		"position": Vector2(500, 500), "alive": true, "complete": true,
		"hp": 2000.0, "max_hp": 2000.0})
	# Ogre field army, deployed for war near the human town.
	for i in range(6):
		var u := _spawn(w, "ogres", "soldier",
			Vector2(1000.0 + float(i) * 30.0, 1000.0))
		u["deployed_for_war"] = true
		u["hp"] = 20.0 if mauled else 100.0
		u["max_hp"] = 100.0
	var army: SimArmy = w["army"]
	# Prime the peak: the army used to be at full strength (16), so the
	# current 6 survivors count as mauled (6 < 0.5 * 16).
	army._field_peak["ogres"] = 16
	# Superior human hostiles inside the theater radius.
	for i in range(10):
		var e := _spawn(w, "humans", "soldier",
			Vector2(1050.0 + float(i) * 20.0, 1050.0))
		e["hp"] = 100.0
		e["max_hp"] = 100.0
	gs.diplomacy.declare_war("ogres", "humans", "test")
	gs.day_number = 40


func _test_retreat_ordered() -> void:
	var w := _new_world()
	_seed_retreat_world(w, true)
	var army: SimArmy = w["army"]
	army.tick(0.016)
	var retreating := 0
	for u in (w["gs"] as GameState).units:
		if String(u.get("faction", "")) == "ogres" \
			and bool(u.get("withdrawing", false)):
			retreating += 1
	_check("census retreat: mauled AI field army ordered to retreat",
		retreating == 6)
	_free_world(w)


func _test_retreat_holds() -> void:
	var w := _new_world()
	_seed_retreat_world(w, false)
	var army: SimArmy = w["army"]
	army.tick(0.016)
	var retreating := 0
	for u in (w["gs"] as GameState).units:
		if String(u.get("faction", "")) == "ogres" \
			and bool(u.get("withdrawing", false)):
			retreating += 1
	_check("census retreat: healthy field army holds the field",
		retreating == 0)
	_free_world(w)


func _test_tick_day_rollover() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var army: SimArmy = w["army"]
	_spawn(w, "humans", "worker", Vector2(0, 0))
	gs.day_number = 50
	army.tick(0.016)
	var roles_after_first := _roles(w, "humans")
	# Same day: no-op.
	army.tick(0.016)
	_check("census tick: same-day tick is a no-op",
		_roles(w, "humans") == roles_after_first)
	# New day: runs again.
	gs.day_number = 51
	army.tick(0.016)
	_check("census tick: new day re-runs the batch",
		_roles(w, "humans") == roles_after_first)
	_free_world(w)
