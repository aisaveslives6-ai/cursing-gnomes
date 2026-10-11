extends SceneTree
## Cursing Gnomes — town founding tests.
##
## HTML parity (fix79): every completed hall/townhall without a townName gets
## drawUniqueCityName() via a periodic sweep. The Godot port only named towns
## at world spawn, so player-built town halls and AI-founded settlements never
## became towns. SimTowns closes the gap: the sweep registers completed halls
## (merge near existing towns, found new ones under the cap, adopt under the
## nearest town at the cap).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_town_founding.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class _CourtStub:
	var stories: Array = []
	func publish_story(headline: String, body: String,
			kind: String = "default") -> Dictionary:
		var s := {"headline": headline, "body": body, "kind": kind}
		stories.append(s)
		return s


class _HearsayStub:
	var rumors: Array = []
	func seed_rumor(text: String, kind: String = "misc", subject: String = "",
			heat: float = 0.7, knower_id: int = -1) -> Dictionary:
		var r := {"text": text, "kind": kind, "subject": subject}
		rumors.append(r)
		return r


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
	gs.setup(["humans", "gnomes"])
	gs.player_faction = "humans"
	var towns := SimTowns.new(gs)
	return {"gs": gs, "towns": towns}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _hall(faction: String, pos: Vector2, town_id: int = -1,
		btype: String = "town_hall") -> Dictionary:
	return {
		"id": 1000 + randi() % 9000, "type": btype, "faction": faction,
		"town_id": town_id, "position": pos, "alive": true, "complete": true,
		"hp": 1000.0, "max_hp": 1000.0, "progress": 1.0,
	}


func _initialize() -> void:
	print("=== Cursing Gnomes town founding tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_hall_types()
	_test_found_new_town()
	_test_merge_nearby()
	_test_cap_no_new_town()
	_test_unique_names()
	_test_name_pool_exhaustion()
	_test_townhall_alias()
	_test_announce()
	_test_idempotent()
	_test_town_by_id_string_key()
	_test_tick_sweep()
	_test_incomplete_dead_ignored()
	_test_save_key_normalization()
	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _test_hall_types() -> void:
	_check("types: has town_hall", "town_hall" in SimTowns.HALL_TYPES)
	_check("types: has hall", "hall" in SimTowns.HALL_TYPES)
	_check("types: has townhall", "townhall" in SimTowns.HALL_TYPES)
	# Undead war building is NOT a town center in the Godot roster.
	_check("types: no necropolis", not ("necropolis" in SimTowns.HALL_TYPES))


func _test_found_new_town() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	var t0: Dictionary = gs.found_town("humans", "Aldergate", Vector2.ZERO)
	gs.buildings.append(_hall("humans", Vector2.ZERO, int(t0["id"])))
	var far := _hall("humans", Vector2(2000, 0))
	gs.buildings.append(far)
	towns.sweep()
	_check("found: towns now 2", gs.towns.size() == 2)
	var t1 := towns.town_by_id(int(far["town_id"]))
	_check("found: hall got a town", not t1.is_empty())
	_check("found: new name non-empty", String(t1.get("name", "")) != "")
	_check("found: name differs", String(t1.get("name", "")) != "Aldergate")
	_check("found: hall town_name stamped",
		String(far.get("town_name", "")) == String(t1.get("name", "")))
	_check("found: town pos matches hall",
		(t1.get("position", Vector2.ZERO) as Vector2).distance_to(Vector2(2000, 0)) < 1.0)
	_free_world(w)


func _test_merge_nearby() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	var t0: Dictionary = gs.found_town("humans", "Aldergate", Vector2.ZERO)
	var near := _hall("humans", Vector2(120, 40))
	gs.buildings.append(near)
	towns.sweep()
	_check("merge: still 1 town", gs.towns.size() == 1)
	_check("merge: hall joined existing",
		int(near["town_id"]) == int(t0["id"]))
	_check("merge: town_name synced",
		String(near.get("town_name", "")) == "Aldergate")
	_free_world(w)


func _test_cap_no_new_town() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	var spots := [Vector2.ZERO, Vector2(2000, 0), Vector2(0, 2000)]
	for i in 3:
		gs.found_town("humans", "Town%d" % i, spots[i])
	var extra := _hall("humans", Vector2(4000, 4000))
	gs.buildings.append(extra)
	towns.sweep()
	_check("cap: still 3 towns", gs.towns.size() == 3)
	var adopted := towns.town_by_id(int(extra["town_id"]))
	_check("cap: hall adopted a real town", not adopted.is_empty())
	_check("cap: hall town_name stamped",
		String(extra.get("town_name", "")) == String(adopted.get("name", "")))
	_free_world(w)


func _test_unique_names() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	# Fewer towns than the pool: every dealt name is unique + from the pool.
	gs.found_town("humans", "Aldergate", Vector2.ZERO)
	var seen := {"Aldergate": true}
	for i in 4:
		var n := towns.unique_city_name()
		_check("names: unique %d" % i, not seen.has(n))
		_check("names: from pool %d" % i, n in Config.CITY_NAMES)
		seen[n] = true
		gs.found_town("gnomes", n, Vector2(3000 + i * 100, 0))
	_free_world(w)


func _test_name_pool_exhaustion() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	# Burn the whole pool as used names.
	var i := 0
	for n in Config.CITY_NAMES:
		gs.found_town("humans", n, Vector2(i * 10, 0))
		i += 1
	var n := towns.unique_city_name()
	_check("exhaust: Newhold fallback", n.begins_with("Newhold "))
	var num := int(n.get_slice(" ", 1))
	_check("exhaust: suffix 100-999", num >= 100 and num <= 999)
	_free_world(w)


func _test_townhall_alias() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	gs.found_town("humans", "Aldergate", Vector2.ZERO)
	var h := _hall("humans", Vector2(2500, 0), -1, "townhall")
	gs.buildings.append(h)
	towns.sweep()
	_check("alias: townhall founded", gs.towns.size() == 2)
	_check("alias: town_name stamped", String(h.get("town_name", "")) != "")
	_free_world(w)


func _test_announce() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	var court := _CourtStub.new()
	var hearsay := _HearsayStub.new()
	gs.court_sys = court
	gs.phone_sys = {"hearsay": hearsay}
	gs.found_town("humans", "Aldergate", Vector2.ZERO)
	var far := _hall("humans", Vector2(2000, 0))
	gs.buildings.append(far)
	towns.sweep()
	_check("announce: one story", court.stories.size() == 1)
	var s: Dictionary = court.stories[0]
	_check("announce: headline names town",
		String(s["headline"]).find(String(far["town_name"])) >= 0)
	_check("announce: kind town", String(s["kind"]) == "town")
	_check("announce: one rumor", hearsay.rumors.size() == 1)
	var r: Dictionary = hearsay.rumors[0]
	_check("announce: rumor names town",
		String(r["text"]).find(String(far["town_name"])) >= 0)
	_check("announce: rumor subject", String(r["subject"]) == String(far["town_name"]))
	_free_world(w)


func _test_idempotent() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	var t0: Dictionary = gs.found_town("humans", "Aldergate", Vector2.ZERO)
	var h := _hall("humans", Vector2.ZERO, int(t0["id"]))
	gs.buildings.append(h)
	towns.sweep()
	towns.sweep()
	_check("idem: still 1 town", gs.towns.size() == 1)
	# Conquest renamed the town: the sweep re-syncs the hall's display name.
	(t0 as Dictionary)["name"] = "New Aldergate"
	towns.sweep()
	_check("idem: town_name re-synced",
		String(h.get("town_name", "")) == "New Aldergate")
	_free_world(w)


func _test_town_by_id_string_key() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	# Simulate a pre-normalization save: string keys.
	gs.towns = {"7": {"id": 7, "faction": "humans", "name": "Stringkey",
		"position": Vector2(5, 5)}}
	var t := towns.town_by_id(7)
	_check("strkey: coerced lookup", String(t.get("name", "")) == "Stringkey")
	_check("strkey: missing -> empty", towns.town_by_id(999).is_empty())
	_check("strkey: negative -> empty", towns.town_by_id(-1).is_empty())
	_free_world(w)


func _test_tick_sweep() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	gs.found_town("humans", "Aldergate", Vector2.ZERO)
	var far := _hall("humans", Vector2(2000, 0))
	gs.buildings.append(far)
	towns.tick(1.0)
	_check("tick: no sweep before interval", gs.towns.size() == 1)
	towns.tick(3.5)
	_check("tick: sweep at interval", gs.towns.size() == 2)
	_free_world(w)


func _test_incomplete_dead_ignored() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	gs.found_town("humans", "Aldergate", Vector2.ZERO)
	var bp := _hall("humans", Vector2(2000, 0))
	bp["complete"] = false
	bp["progress"] = 0.4
	var dead := _hall("humans", Vector2(0, 2000))
	dead["alive"] = false
	gs.buildings.append(bp)
	gs.buildings.append(dead)
	towns.sweep()
	_check("ignore: blueprint not founded", gs.towns.size() == 1)
	_check("ignore: dead hall not founded", int(dead.get("town_id", -1)) == -1)
	_free_world(w)


func _test_save_key_normalization() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var towns: SimTowns = w["towns"]
	var t0: Dictionary = gs.found_town("humans", "Aldergate", Vector2.ZERO)
	var h := _hall("humans", Vector2.ZERO, int(t0["id"]))
	gs.buildings.append(h)
	var data: Dictionary = SaveSystem.snapshot(gs)
	# Simulate the real JSON round-trip (keys become strings).
	var json_text: String = JSON.stringify(data)
	var back: Dictionary = JSON.parse_string(json_text)
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans", "gnomes"])
	_check("save: restore ok", SaveSystem.restore(gs2, back))
	var int_keys := true
	for k in gs2.towns.keys():
		if not (k is int):
			int_keys = false
	_check("save: town keys are int", int_keys)
	_check("save: town kept", gs2.towns.size() == 1)
	var t := (SimTowns.new(gs2)).town_by_id(int(t0["id"]))
	_check("save: town_by_id works", String(t.get("name", "")) == "Aldergate")
	# The sweep still recognizes the hall's town after a load.
	var towns2 := SimTowns.new(gs2)
	var h2: Dictionary = (gs2.buildings[0] as Dictionary).duplicate()
	gs2.buildings.clear()
	gs2.buildings.append(h2)
	var reg := towns2.register_hall(h2)
	_check("save: hall re-registers to loaded town",
		String(reg.get("name", "")) == "Aldergate")
	_check("save: no duplicate town", gs2.towns.size() == 1)
	gs2.free()
	_free_world(w)
	_check("save: towns sys constructs", towns != null)
