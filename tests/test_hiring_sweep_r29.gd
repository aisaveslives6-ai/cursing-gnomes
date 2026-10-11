extends SceneTree
## Cursing Gnomes — R29 hiring sweep parity tests.
##
## R29 replaced two O(n^2)-ish sweep hot spots with index/cache versions:
##   1. scan_positions() holders: was O(positions x faction_units), now an
##      inverted bucket index (_holder_buckets + _holders_for).
##   2. _assign_barracks(): was O(soldiers x barracks x units) through
##      _barracks_assigned, now a per-sweep free-bed cache (_bed_free).
## Both must be behavior-identical. The kept prod helpers _holder_matches
## and _barracks_assigned serve as oracles (R28 precedent); the pre-R29
## barracks scan is replicated verbatim below as the old-path oracle.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hiring_sweep_r29.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes R29 hiring sweep parity tests ===")
	_test_holders_match_oracle()
	_test_holders_own_arrays()
	_test_barracks_parity()
	_test_bed_cache_cleared()
	_test_assign_outside_sweep_fallback()
	_test_incomplete_home_kept()
	_test_military_memo_parity()
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


## Deterministic twin-ready world: shops, halls, barracks, farms; units
## with stations, gov roles, homes, and a few dead/foreign edge cases.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	var hiring := GuildHiring.new(gs)
	gs.hiring = hiring
	seed(777)
	var bx := 0.0
	var barracks: Dictionary = {"humans": [], "ogres": []}
	var halls: Dictionary = {}
	var shops: Dictionary = {"humans": [], "ogres": []}
	for f: String in ["humans", "ogres"]:
		for bt: String in ["town_hall", "shop", "shop", "barracks", "barracks", "farm"]:
			bx += 211.0
			var b: Dictionary = gs.add_building({"type": bt, "faction": f,
				"alive": true, "complete": true, "town_id": -1,
				"position": Vector2(500.0 + bx, 500.0)})
			if bt == "barracks":
				(barracks[f] as Array).append(b)
			elif bt == "town_hall":
				halls[f] = b
			elif bt == "shop":
				(shops[f] as Array).append(b)
	# Units: soldiers (homeless + homed), workers with stations, officers,
	# dead units, and cross-faction checks.
	var units: Array = []
	for f: String in ["humans", "ogres"]:
		for k: int in range(20):
			var job: String = "soldier" if k % 4 == 3 else "woodcutter"
			var u: Dictionary = gs.spawner.spawn_unit(f, job, -1,
				Vector2(600.0 + k * 17.0, 800.0))
			units.append(u)
			if k % 4 != 3 and k % 3 == 0:
				# stationed worker: holder of the first shop's clerk slot
				u["station"] = {"job": "clerk",
					"building_id": int((shops[f] as Array)[0]["id"])}
	# Gov roles: guild master + adviser + watch captain on humans hall.
	var gm: Dictionary = gs.spawner.spawn_unit("humans", "guild_master", -1,
		Vector2(610, 810))
	hiring._set_gov_role(gm, "guild_master")
	units.append(gm)
	var adv: Dictionary = gs.spawner.spawn_unit("humans", "adviser", -1,
		Vector2(620, 810))
	hiring._set_gov_role(adv, "adviser")
	adv["station"] = {"job": "adviser",
		"building_id": int(halls["humans"]["id"])}
	units.append(adv)
	var wc: Dictionary = gs.spawner.spawn_unit("humans", "guard", -1,
		Vector2(630, 810))
	hiring._set_gov_role(wc, "watch_captain")
	units.append(wc)
	# A gov-role unit that ALSO holds a generic station (both buckets).
	# Clerk slots live on the town hall: this unit must appear in the
	# hall's clerk holders AND the hall's adviser holders.
	var dual: Dictionary = gs.spawner.spawn_unit("humans", "clerk", -1,
		Vector2(640, 810))
	hiring._set_gov_role(dual, "adviser")
	dual["station"] = {"job": "clerk",
		"building_id": int(halls["humans"]["id"])}
	units.append(dual)
	# Dead unit must never appear in holders.
	var dead: Dictionary = gs.spawner.spawn_unit("humans", "woodcutter", -1,
		Vector2(650, 810))
	dead["alive"] = false
	units.append(dead)
	# Homed soldiers: half the humans soldiers get a bunk up front.
	var bi := 0
	for u: Dictionary in units:
		if String(u.get("job", "")) == "soldier" \
				and String(u.get("faction", "")) == "humans" and bi % 2 == 0:
			u["home"] = (barracks["humans"] as Array)[bi % 2]
		bi += 1
	return {"gs": gs, "hiring": hiring, "barracks": barracks, "units": units}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


## Every position's holders must equal the old per-position scan through
## the kept _holder_matches oracle — same contents, same order.
func _test_holders_match_oracle() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	hiring._begin_batch()
	var positions: Array = hiring.scan_positions()
	var all_ok := true
	var checked := 0
	for p: Dictionary in positions:
		var old_holders: Array = []
		for u: Dictionary in hiring._faction_units(String(p["faction"])):
			if hiring._holder_matches(u, p):
				old_holders.append(int(u["id"]))
		if old_holders != p["holders"]:
			all_ok = false
			print("  holders mismatch job=", p["job"], " bld=", p["building_id"],
				" old=", old_holders, " new=", p["holders"])
		checked += 1
	hiring._end_batch()
	_check("holders: %d positions match oracle" % checked, all_ok and checked > 0)
	# Spot-check: the dual gov-role+station unit is in both buckets.
	var dual_id := -1
	for u: Dictionary in w["units"]:
		if String(u.get("job", "")) == "clerk" \
				and String(hiring._mind(u).get("gov_role", "")) == "adviser":
			dual_id = int(u["id"])
	var in_gov := false
	var in_job := false
	hiring._begin_batch()
	for p: Dictionary in hiring.scan_positions():
		if int(p["building_id"]) >= 0 and dual_id in (p["holders"] as Array):
			if String(p["job"]) == "adviser":
				in_gov = true
			if String(p["job"]) == "clerk":
				in_job = true
	hiring._end_batch()
	_check("holders: dual gov+station unit in both buckets", in_gov and in_job)
	_free_world(w)


## Two positions sharing one bucket must get independent arrays.
func _test_holders_own_arrays() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	hiring._begin_batch()
	var positions: Array = hiring.scan_positions()
	hiring._end_batch()
	var seen: Dictionary = {}
	var ok := true
	for p: Dictionary in positions:
		var key: String = "%s|%s|%d" % [p["faction"], p["job"], int(p["building_id"])]
		var arr: Array = p["holders"]
		if seen.has(key):
			var prev: Array = seen[key]
			if prev == arr and _same_instance(prev, arr):
				ok = false
		else:
			seen[key] = arr
	_check("holders: shared-bucket positions own their arrays", ok)
	_free_world(w)


func _same_instance(a: Array, b: Array) -> bool:
	# Mutating one must not affect the other.
	var n: int = a.size()
	a.append(-999)
	var shared: bool = b.size() == n + 1
	a.resize(n)
	return shared


## Twin worlds: new cached _assign_barracks vs verbatim old-path oracle —
## every unit's home must match.
func _test_barracks_parity() -> void:
	var wa: Dictionary = _new_world()
	var wb: Dictionary = _new_world()
	var ha: GuildHiring = wa["hiring"]
	ha._assign_barracks()
	_old_assign_barracks(wb)
	var ok := true
	var ua: Array = wa["units"]
	var ub: Array = wb["units"]
	if ua.size() != ub.size():
		ok = false
	else:
		for i: int in range(ua.size()):
			var ha_home: Dictionary = (ua[i] as Dictionary).get("home", {})
			var hb_home: Dictionary = (ub[i] as Dictionary).get("home", {})
			if int(ha_home.get("id", -1)) != int(hb_home.get("id", -1)):
				ok = false
				print("  home mismatch unit ", (ua[i] as Dictionary).get("id"),
					" new=", ha_home.get("id"), " old=", hb_home.get("id"))
	_check("barracks: cached sweep matches old-path oracle (%d units)"
		% ua.size(), ok)
	_free_world(wa)
	_free_world(wb)


## Verbatim pre-R29 _assign_barracks + assign_barracks_bed (oracle only).
func _old_assign_barracks(w: Dictionary) -> void:
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	for u: Dictionary in gs.units:
		if not u.get("alive", false):
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		var home: Dictionary = u.get("home", {})
		if not home.is_empty() and bool(home.get("alive", false)):
			continue
		_old_assign_bed(gs, hiring, u)


func _old_assign_bed(gs: GameState, hiring: GuildHiring, u: Dictionary) -> Dictionary:
	var home: Dictionary = u.get("home", {})
	if not home.is_empty() and bool(home.get("alive", false)) \
			and hiring._barracks_beds(home) > 0 \
			and hiring._barracks_assigned(home) < Config.BARRACKS_BEDS:
		return home
	var faction: String = String(u.get("faction", ""))
	var best: Dictionary = {}
	var best_free := -1
	for b: Dictionary in gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if hiring._barracks_beds(b) <= 0:
			continue
		var free: int = Config.BARRACKS_BEDS - hiring._barracks_assigned(b)
		if free <= 0:
			continue
		if free > best_free or (free == best_free and not best.is_empty() \
				and int(b.get("id", 0)) < int(best.get("id", 0))):
			best = b
			best_free = free
	if not best.is_empty():
		u["home"] = best
	return best


func _test_bed_cache_cleared() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	hiring._assign_barracks()
	_check("barracks: _bed_free cleared after sweep", hiring._bed_free.is_empty())
	_free_world(w)


## Outside a sweep (training-graudate path) the old computation must run.
func _test_assign_outside_sweep_fallback() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	var target: Dictionary = {}
	for u: Dictionary in w["units"]:
		if String(u.get("job", "")) == "soldier" \
				and String(u.get("faction", "")) == "ogres" \
				and (u.get("home", {}) as Dictionary).is_empty():
			target = u
			break
	_check("barracks: found homeless ogre soldier", not target.is_empty())
	if target.is_empty():
		_free_world(w)
		return
	var got: Dictionary = hiring.assign_barracks_bed(target)
	_check("barracks: fallback assigns a bunk", not got.is_empty()
		and int((target.get("home", {}) as Dictionary).get("id", -1))
			== int(got.get("id", -2)))
	_check("barracks: fallback leaves _bed_free empty",
		hiring._bed_free.is_empty())
	_free_world(w)


## A unit homed in an INCOMPLETE barracks keeps its home (not in cache).
func _test_incomplete_home_kept() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	var target: Dictionary = {}
	for u: Dictionary in w["units"]:
		if String(u.get("job", "")) == "soldier" \
				and String(u.get("faction", "")) == "humans":
			target = u
			break
	var broken: Dictionary = gs.add_building({"type": "barracks",
		"faction": "humans", "alive": true, "complete": false, "town_id": -1,
		"position": Vector2(10, 10)})
	target["home"] = broken
	hiring._assign_barracks()
	_check("barracks: incomplete home kept",
		int((target.get("home", {}) as Dictionary).get("id", -1))
			== int(broken.get("id", -2)))
	_free_world(w)


## Twin worlds: new memoized _maintain_military vs verbatim old path —
## every barracks' train queue must match, and the memo must be fresh
## per sweep (no stale counts leaking across sweeps).
func _test_military_memo_parity() -> void:
	var wa: Dictionary = _new_world()
	var wb: Dictionary = _new_world()
	var ha: GuildHiring = wa["hiring"]
	ha._maintain_military()
	_old_maintain_military(wb)
	var ok := true
	var ba: Array = (wa["gs"] as GameState).buildings
	var bb: Array = (wb["gs"] as GameState).buildings
	if ba.size() != bb.size():
		ok = false
	else:
		for i: int in range(ba.size()):
			var qa: Array = ((ba[i] as Dictionary).get("train_queue", [])) as Array
			var qb: Array = ((bb[i] as Dictionary).get("train_queue", [])) as Array
			var ta: Array = []
			var tb: Array = []
			for j: Dictionary in qa:
				ta.append(String(j.get("unit_type", "")))
			for j: Dictionary in qb:
				tb.append(String(j.get("unit_type", "")))
			if ta != tb:
				ok = false
				print("  queue mismatch bld ", (ba[i] as Dictionary).get("id"),
					" new=", ta, " old=", tb)
	_check("military: memoized sweep matches old path", ok)
	# Staleness: add an archer, sweep (memo sees 1), kill it, poison the
	# memo, sweep again — the memo must be rebuilt fresh (archer: 0),
	# not carry the poisoned or stale values.
	var gs: GameState = wa["gs"]
	var archer: Dictionary = gs.spawner.spawn_unit("humans", "archer", -1,
		Vector2(700, 800))
	ha._maintain_military()
	var saw_one: bool = int((ha._mil_memo["humans"] as Dictionary)["archer"]) == 1
	archer["alive"] = false
	ha._mil_memo["humans"] = {"pop": 999, "soldier": 999, "archer": 999}
	ha._maintain_military()
	var m2: Dictionary = ha._mil_memo["humans"]
	_check("military: memo refreshed each sweep, not stale",
		saw_one and int(m2["archer"]) == 0 and int(m2["pop"]) != 999)
	_free_world(wa)
	_free_world(wb)


## Verbatim pre-R29 _maintain_military (oracle only).
func _old_maintain_military(w: Dictionary) -> void:
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	for b: Dictionary in gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("type", "")) != "barracks":
			continue
		if not (hiring._train_queue(b) as Array).is_empty():
			continue
		var faction: String = String(b.get("faction", ""))
		var want: String = hiring._military_want(faction)
		if want == "":
			continue
		hiring.queue_training(b, want)
