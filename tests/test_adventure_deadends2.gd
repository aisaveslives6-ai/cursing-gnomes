extends SceneTree
## Cursing Gnomes — adventure dead-end pass #2 (hall alias + spawn failures).
##
## Covers the dead ends the quest-failure run left open:
##   - "hall" alias blind spot: hero spawn/respawn and rescue completion only
##     matched "town_hall", never the HTML "hall" alias (a real building type
##     per buildings.gd). On "hall"-typed saves the hero spawned at map
##     center and rescue quests could never complete.
##   - quest NPC spawn failure at the unit cap: rescue/escort accepted with
##     no NPC spawned (npc_id -1) hung at "find the captive" until manual
##     abandon. Now rolls back loudly; the def stays on the board.
##   - finale re-accept after the Bandit King died while abandoned: the
##     stronghold guard early-returned and the quest hung with no King.
##     Now completes out loud (the wilds are already free).
##   - finale first-accept at the unit cap: the King never spawned. Now rolls
##     back and tears down the boss-less stronghold shell.
##   - _ensure_prey_supply at the unit cap: no more false "More Xs ride in"
##     toast/deed when nothing rode in.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_adventure_deadends2.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes adventure dead-ends #2 tests ===")
	_test_hall_alias_home_pos()
	_test_hall_alias_rescue_completes()
	_test_rescue_at_unit_cap_rolls_back()
	_test_escort_at_unit_cap_rolls_back()
	_test_finale_reaccept_after_king_died_abandoned()
	_test_finale_first_accept_at_unit_cap_rolls_back()
	_test_prey_supply_at_cap_stays_quiet()
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


## Setup with a configurable hall building type ("town_hall" or the "hall" alias).
func _new_adventure(hall_type: String = "town_hall") -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var factions: Array[String] = ["humans", "ogres", "elves", "gnomes",
		"undead"]
	gs.setup(factions)
	var town: Dictionary = gs.found_town("gnomes", "Testville",
		Vector2(1000, 1000))
	gs.add_building({"type": hall_type, "faction": "gnomes",
		"town_id": int(town["id"]), "position": Vector2(1000, 1000)})
	var adv := SimAdventure.new(gs)
	var ok: bool = adv.start("gnomes", "TestHero", "soldier",
		Vector2(4096, 4096))
	return [gs, adv, ok]


func _force_offer(adv: SimAdventure, did: String) -> void:
	if not adv.offered.has(did):
		adv.offered.append(did)


func _deeds_text(adv: SimAdventure, from_idx: int) -> String:
	var t := ""
	var ds: Array = adv.deeds
	for i in range(from_idx, ds.size()):
		t += String(ds[i]) + " "
	return t


## Fill the world to the adventure unit cap (96).
func _fill_to_cap(gs: GameState) -> void:
	var i := 0
	while gs.units.size() < 96:
		gs.add_unit({"faction": "gnomes", "job": "worker",
			"position": Vector2(3000 + i, 3000), "alive": true,
			"hp": 100.0, "max_hp": 100.0})
		i += 1


func _boss_unit(gs: GameState) -> Dictionary:
	for u: Dictionary in gs.units:
		if bool(u.get("_adv_boss", false)):
			return u
	return {}


# --- "hall" alias ------------------------------------------------------------

func _test_hall_alias_home_pos() -> void:
	var parts: Array = _new_adventure("hall")
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_check("hall-alias: started", bool(parts[2]))
	var h: Dictionary = adv.hero()
	var hp: Vector2 = h.get("position", Vector2.ZERO)
	# Hall at (1000,1000); hero should spawn beside it, NOT at map center.
	_check("hall-alias: hero near hall",
		hp.distance_to(Vector2(1055, 1055)) < 200.0)
	_check("hall-alias: hero not at map center",
		hp.distance_to(Vector2(2048, 2048)) > 500.0)
	_check("hall-alias: _home_hall_pos finds hall",
		adv._home_hall_pos().distance_to(Vector2(1000, 1000)) < 1.0)
	# Respawn also uses the hall, not map center.
	h["alive"] = false
	adv.respawn_t = 0.01
	adv._respawn_tick(h, 1.0)
	var rp: Vector2 = h.get("position", Vector2.ZERO)
	_check("hall-alias: respawn at hall",
		rp.distance_to(Vector2(1060, 1060)) < 200.0)
	gs.queue_free()


func _test_hall_alias_rescue_completes() -> void:
	var parts: Array = _new_adventure("hall")
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_rescue1")
	_check("hall-alias-rescue: accepted", adv.accept_quest("q_rescue1"))
	var q: Dictionary = adv.active_quests()[0]
	var npc: Dictionary = gs.get_unit(int(q.get("npc_id", -1)))
	_check("hall-alias-rescue: captive spawned", not npc.is_empty())
	# Captive follows; hero walks home to the "hall"-typed hall.
	npc["_adv_follow"] = true
	var h: Dictionary = adv.hero()
	h["position"] = Vector2(1000, 1100)
	npc["position"] = Vector2(1000, 1150)
	adv.tick_quest_npc(npc, 0.1)
	_check("hall-alias-rescue: quest done",
		String(q.get("state", "")) == "done")
	_check("hall-alias-rescue: not failed", not bool(q.get("failed", false)))
	gs.queue_free()


# --- unit-cap spawn failures ---------------------------------------------------

func _test_rescue_at_unit_cap_rolls_back() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_fill_to_cap(gs)
	_check("cap-rescue: at cap", gs.units.size() >= 96)
	var deeds_before: int = adv.deeds.size()
	_force_offer(adv, "q_rescue1")
	_check("cap-rescue: accept returns false",
		not adv.accept_quest("q_rescue1"))
	_check("cap-rescue: def stays offered", adv.offered.has("q_rescue1"))
	_check("cap-rescue: no quest record", adv.quests.is_empty())
	_check("cap-rescue: said out loud",
		_deeds_text(adv, deeds_before).contains("unit cap"))
	gs.queue_free()


func _test_escort_at_unit_cap_rolls_back() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_fill_to_cap(gs)
	var deeds_before: int = adv.deeds.size()
	_force_offer(adv, "q_escort1")
	_check("cap-escort: accept returns false",
		not adv.accept_quest("q_escort1"))
	_check("cap-escort: def stays offered", adv.offered.has("q_escort1"))
	_check("cap-escort: no quest record", adv.quests.is_empty())
	_check("cap-escort: said out loud",
		_deeds_text(adv, deeds_before).contains("unit cap"))
	gs.queue_free()


# --- finale edge cases ----------------------------------------------------------

func _test_finale_reaccept_after_king_died_abandoned() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_finale")
	_check("finale-re: accepted", adv.accept_quest("q_finale"))
	var boss: Dictionary = _boss_unit(gs)
	_check("finale-re: king spawned", not boss.is_empty())
	var qid: String = String(adv.active_quests()[0].get("id", ""))
	adv.abandon_quest(qid)
	_check("finale-re: abandoned",
		bool(adv.active_quests().is_empty()) and not adv.won)
	# A disaster kills the King while the finale is abandoned.
	var boss_id := int(boss.get("id", -1))
	gs.kill_unit(boss_id)
	adv.on_unit_died(boss_id)
	_check("finale-re: no auto-win while abandoned", not adv.won)
	# Re-take the quest: the stronghold stands but the King is dead.
	_force_offer(adv, "q_finale")
	var deeds_before: int = adv.deeds.size()
	_check("finale-re: re-accept returns true", adv.accept_quest("q_finale"))
	_check("finale-re: campaign won", adv.won)
	var finale_done := false
	for q: Dictionary in adv.quests:
		if String(q.get("def_id", "")) == "q_finale" \
				and String(q.get("state", "")) == "done" \
				and not bool(q.get("failed", false)):
			finale_done = true
	_check("finale-re: finale completed, not failed", finale_done)
	_check("finale-re: said out loud",
		_deeds_text(adv, deeds_before).contains("not by the hero's hand"))
	gs.queue_free()


func _test_finale_first_accept_at_unit_cap_rolls_back() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_fill_to_cap(gs)
	_force_offer(adv, "q_finale")
	_check("finale-cap: accept returns false",
		not adv.accept_quest("q_finale"))
	_check("finale-cap: def stays offered", adv.offered.has("q_finale"))
	_check("finale-cap: no quest record", adv.quests.is_empty())
	_check("finale-cap: not won", not adv.won)
	var shell := false
	for d: Dictionary in adv.dungeons:
		if bool(d.get("is_stronghold", false)):
			shell = true
	_check("finale-cap: no boss-less stronghold shell", not shell)
	gs.queue_free()


func _test_prey_supply_at_cap_stays_quiet() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	# Active kill quest first (spawns nothing: denizens already live).
	_force_offer(adv, "q_bounty1")
	_check("prey-cap: bounty accepted", adv.accept_quest("q_bounty1"))
	_fill_to_cap(gs)
	# Wipe every living bandit; each death tick tries (and fails) to resupply.
	for u: Dictionary in gs.units.duplicate():
		if u.get("alive", false) and String(u.get("faction", "")) == "bandit":
			var uid := int(u.get("id", -1))
			gs.kill_unit(uid)
			adv.on_unit_died(uid)
	var bandits := 0
	for u: Dictionary in gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == "bandit":
			bandits += 1
	_check("prey-cap: no bandits left", bandits == 0)
	var deeds_before: int = adv.deeds.size()
	var units_before: int = gs.units.size()
	adv._ensure_prey_supply()
	_check("prey-cap: nothing spawned", gs.units.size() == units_before)
	var dtxt := _deeds_text(adv, deeds_before)
	_check("prey-cap: no false riders deed",
		not dtxt.contains("ride in") and not dtxt.contains("Fresh"))
	# Quest is still active and retryable — the next death tick retries.
	var still_active := false
	for q: Dictionary in adv.quests:
		if String(q.get("def_id", "")) == "q_bounty1" \
				and String(q.get("state", "")) == "active":
			still_active = true
	_check("prey-cap: quest still active", still_active)
	gs.queue_free()
