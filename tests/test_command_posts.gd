extends SceneTree
## Cursing Gnomes — Command Posts tests (Jeremy 2026-10-06, Battlefront).
##
## Covers: unified post model (town/monastery/crystal), territory projection
## from held monasteries/crystals, capture flips claims, hall war-capture
## flip (not destroy), capture log + war-score API, bus signal, build
## blocking on post territory, save/load round-trip.
##
## Run: Godot --headless --path . -s res://tests/test_command_posts.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("  FAIL: ", name)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_post_model()
	_test_territory_projection()
	_test_capture_flips_claim()
	_test_hall_flip()
	_test_hall_no_flip_peace()
	_test_capture_log_api()
	_test_bus_signal()
	_test_build_blocking()
	_test_save_roundtrip()
	print("test_command_posts: %d passed, %d failed" % [_passed, _failed])
	if not _failures.is_empty():
		push_error("failures: " + str(_failures))
	quit(1 if _failed > 0 else 0)


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.day_number = 10
	# Wire command posts.
	var cps := SimCommandPosts.new()
	cps.setup(gs)
	gs.command_posts = cps
	return gs


func _add_hall(gs: GameState, faction: String, pos: Vector2,
		bid: int = 1) -> Dictionary:
	var hall := {
		"id": bid, "type": "town_hall", "faction": faction,
		"position": pos, "alive": true, "complete": true,
		"hp": 1200.0, "max_hp": 1200.0, "town_id": 100 + bid,
		"town_name": "Testville",
	}
	gs.buildings.append(hall)
	gs.building_by_id[bid] = hall
	gs.towns[100 + bid] = {"id": 100 + bid, "name": "Testville",
		"faction": faction}
	return hall


func _add_monastery(gs: GameState, owner: String, pos: Vector2,
		mid: int = 1) -> SimMonasteries:
	var mons := SimMonasteries.new()
	mons.setup(gs)
	gs.monasteries = mons
	mons.monasteries.append({
		"id": mid, "god_id": "auriel", "position": pos, "owner": owner,
		"progress": {}, "contested": false, "contested_by": "",
		"name": "Monastery of Auriel",
	})
	return mons


func _add_crystal(gs: GameState, owner: String, pos: Vector2,
		cid: int = 1) -> SimDarkCrystals:
	var crys := SimDarkCrystals.new()
	crys.setup(gs)
	gs.crystals = crys
	crys.crystals.append({
		"id": cid, "god_id": "vexmor", "position": pos, "owner": owner,
		"progress": {}, "contested": false, "contested_by": "",
		"name": "Dark Crystal of Vexmor",
	})
	return crys


func _test_post_model() -> void:
	var gs: GameState = _new_game()
	_add_hall(gs, "humans", Vector2(500, 500), 1)
	_add_monastery(gs, "humans", Vector2(2000, 2000), 1)
	_add_crystal(gs, "gnomes", Vector2(3000, 3000), 1)
	var cps: SimCommandPosts = gs.command_posts
	var posts: Array = cps.posts_of()
	_check(posts.size() == 3, "model: 3 posts total")
	var kinds := {}
	for p in posts:
		kinds[String(p["kind"])] = String(p["holder"])
	_check(String(kinds.get("town", "")) == "humans", "model: town holder")
	_check(String(kinds.get("monastery", "")) == "humans",
		"model: monastery holder")
	_check(String(kinds.get("crystal", "")) == "gnomes",
		"model: crystal holder")
	var held: Array = cps.holdings_of("humans")
	_check(held.size() == 2, "model: humans hold 2")
	var counts: Dictionary = cps.holding_counts("gnomes")
	_check(int(counts["crystal"]) == 1, "model: gnome crystal count")
	gs.free()


func _test_territory_projection() -> void:
	var gs: GameState = _new_game()
	_add_monastery(gs, "humans", Vector2(2000, 2000), 1)
	_add_crystal(gs, "gnomes", Vector2(3000, 3000), 1)
	var cps: SimCommandPosts = gs.command_posts
	var claimants: Array = cps.claimants_of()
	_check(claimants.size() == 2, "territory: 2 claimants")
	# Ground near the held monastery belongs to its holder.
	_check(SimCommandPosts.owner_at(claimants, Vector2(2050, 2000))
		== "humans", "territory: monastery projects land")
	_check(SimCommandPosts.owner_at(claimants, Vector2(3050, 3000))
		== "gnomes", "territory: crystal projects land")
	# Far away: unclaimed.
	_check(SimCommandPosts.owner_at(claimants, Vector2(100, 100)) == "",
		"territory: wilds unclaimed")
	# Unowned posts claim nothing.
	var mons: SimMonasteries = gs.monasteries
	(mons.monasteries[0] as Dictionary)["owner"] = ""
	claimants = cps.claimants_of()
	_check(claimants.size() == 1, "territory: unowned post claims nothing")
	gs.free()


func _test_capture_flips_claim() -> void:
	var gs: GameState = _new_game()
	var mons := _add_monastery(gs, "humans", Vector2(2000, 2000), 1)
	var cps: SimCommandPosts = gs.command_posts
	_check(SimCommandPosts.owner_at(cps.claimants_of(),
		Vector2(2050, 2000)) == "humans", "flip: pre-capture holder")
	# Simulate a capture (bypass the 60s timer).
	(mons.monasteries[0] as Dictionary)["owner"] = "gnomes"
	mons._capture(mons.monasteries[0], "gnomes")
	_check(SimCommandPosts.owner_at(cps.claimants_of(),
		Vector2(2050, 2000)) == "gnomes", "flip: post-capture holder")
	gs.free()


func _test_hall_flip() -> void:
	var gs: GameState = _new_game()
	var hall := _add_hall(gs, "gnomes", Vector2(500, 500), 1)
	var combat := SimCombat.new(gs)
	# War damage (no diplomacy wired -> different factions can fight).
	var destroyed: bool = combat.damage_building(1, 5000.0, "humans")
	_check(destroyed, "hall flip: damage returns true")
	_check(bool(hall.get("alive", false)), "hall flip: hall survives")
	_check(String(hall.get("faction", "")) == "humans",
		"hall flip: faction flips to attacker")
	_check(float(hall.get("hp", 0.0)) > 0.0
		and float(hall.get("hp", 0.0)) < 1200.0,
		"hall flip: damaged not destroyed")
	# Town record follows the hall.
	_check(String((gs.towns[101] as Dictionary).get("faction", ""))
		== "humans", "hall flip: town record flips")
	# Capture logged.
	var cps: SimCommandPosts = gs.command_posts
	_check(cps.capture_log.size() == 1, "hall flip: logged")
	_check(String((cps.capture_log[0] as Dictionary).get("kind", ""))
		== "town", "hall flip: log kind town")
	gs.free()


func _test_hall_no_flip_peace() -> void:
	var gs: GameState = _new_game()
	_add_hall(gs, "gnomes", Vector2(500, 500), 1)
	var combat := SimCombat.new(gs)
	# Same-faction damage (accident): destroys, no flip.
	_add_hall(gs, "humans", Vector2(1500, 1500), 2)
	var destroyed: bool = combat.damage_building(2, 5000.0, "humans")
	_check(destroyed, "no-flip: damage returns true")
	_check(not gs.building_by_id.has(2), "no-flip: own hall destroyed")
	# Disaster (no source faction): destroys.
	_add_hall(gs, "gnomes", Vector2(2500, 2500), 3)
	combat.damage_building(3, 5000.0, "")
	_check(not gs.building_by_id.has(3), "no-flip: disaster destroys")
	gs.free()


func _test_capture_log_api() -> void:
	var gs: GameState = _new_game()
	var cps: SimCommandPosts = gs.command_posts
	cps.log_capture("town", 1, "gnomes", "humans", Vector2(500, 500),
		"Testville")
	cps.log_capture("monastery", 2, "humans", "gnomes",
		Vector2(2000, 2000), "Monastery of Auriel")
	cps.log_capture("crystal", 3, "gnomes", "humans", Vector2(3000, 3000),
		"Dark Crystal")
	var changes: Array = cps.war_post_changes("humans", "gnomes", 0)
	_check(changes.size() == 3, "api: war changes filtered")
	# humans gained town (2.0) + crystal (1.0), lost monastery (3.0).
	var swing: float = cps.post_swing("humans", "gnomes", 0)
	_check(is_equal_approx(swing, 0.0), "api: swing balanced = 0")
	var swing2: float = cps.post_swing("gnomes", "humans", 0)
	_check(is_equal_approx(swing2, 0.0), "api: swing symmetric")
	gs.free()


func _test_bus_signal() -> void:
	var gs: GameState = _new_game()
	var got: Array = []
	gs.bus.command_post_captured.connect(
		func(kind: String, post_id: int, old_h: String, new_h: String,
				pos: Vector2) -> void:
			got.append([kind, post_id, old_h, new_h]))
	var cps: SimCommandPosts = gs.command_posts
	cps.log_capture("town", 7, "gnomes", "humans", Vector2(1, 1), "T")
	_check(got.size() == 1, "signal: emitted on log_capture")
	_check(String((got[0] as Array)[0]) == "town", "signal: kind")
	_check(String((got[0] as Array)[2]) == "gnomes", "signal: old holder")
	_check(String((got[0] as Array)[3]) == "humans", "signal: new holder")
	gs.free()


func _test_build_blocking() -> void:
	var gs: GameState = _new_game()
	_add_monastery(gs, "gnomes", Vector2(2000, 2000), 1)
	var posts: Array = SimCommandPosts.claimants_of_game(gs)
	var rect := Rect2(0, 0, 4000, 4000)
	# Humans can't build on gnome-held monastery land.
	_check(not SimBuildings.can_place_at(gs.buildings, "farm",
		Vector2(2050, 2000), rect, "humans", 0.0, posts),
		"blocking: enemy post land blocked")
	# But can build on their own / unclaimed land.
	_check(SimBuildings.can_place_at(gs.buildings, "farm",
		Vector2(100, 100), rect, "humans", 0.0, posts),
		"blocking: wilds buildable")
	gs.free()


func _test_save_roundtrip() -> void:
	var gs: GameState = _new_game()
	var cps: SimCommandPosts = gs.command_posts
	cps.log_capture("town", 1, "gnomes", "humans", Vector2(500, 500),
		"Testville")
	var d: Dictionary = cps.to_dict()
	var cps2 := SimCommandPosts.new()
	cps2.setup(gs)
	cps2.from_dict(d)
	_check(cps2.capture_log.size() == 1, "save: log round-trips")
	_check(String((cps2.capture_log[0] as Dictionary).get("name", ""))
		== "Testville", "save: entry intact")
	gs.free()
