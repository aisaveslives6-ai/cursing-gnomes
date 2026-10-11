extends SceneTree
## Cursing Gnomes — adventure quest failure-loop tests (no dead ends).
##
## Covers the quest loops that used to hang silently in production:
##   - rescue/escort quest NPC dies -> quest FAILS out loud (deed + toast +
##     giver rep hit), board re-offers the def (retryable)
##   - Bandit King slain by anything but the hero -> campaign still WON
##   - fetch quest accepted after every chest was looted -> chest re-stocked,
##     quest completable
##   - escort shrine coordinates come from one wild spot, in world bounds
##   - kill quest whose targets all died -> fresh crew rides in (no hang)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_adventure_quest_failures.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes adventure quest-failure tests ===")
	_test_rescue_npc_death_fails_quest()
	_test_escort_npc_death_fails_quest()
	_test_freed_npc_death_no_fail()
	_test_failed_quest_reoffered_retryable()
	_test_boss_slain_by_other_hand_wins()
	_test_fetch_after_full_clear()
	_test_escort_shrine_sane()
	_test_prey_supply_guarantee()
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


func _new_adventure() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var factions: Array[String] = ["humans", "ogres", "elves", "gnomes",
		"undead"]
	gs.setup(factions)
	var town: Dictionary = gs.found_town("gnomes", "Testville",
		Vector2(2048, 2048))
	gs.add_building({"type": "town_hall", "faction": "gnomes",
		"town_id": int(town["id"]), "position": Vector2(2048, 2048)})
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


func _rep_score(adv: SimAdventure, key: String) -> float:
	var e: Dictionary = adv.rep.get(key, {})
	return float(e.get("score", 0.0))


func _test_rescue_npc_death_fails_quest() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_rescue1")
	_check("rescue-fail: accept", adv.accept_quest("q_rescue1"))
	var q: Dictionary = adv.active_quests()[0]
	var npc_id := int(q.get("npc_id", -1))
	_check("rescue-fail: npc spawned", npc_id > 0)
	var deeds_before: int = adv.deeds.size()
	gs.kill_unit(npc_id)
	adv.on_unit_died(npc_id)
	_check("rescue-fail: quest done", String(q.get("state", "")) == "done")
	_check("rescue-fail: marked failed", bool(q.get("failed", false)))
	_check("rescue-fail: no active quests", adv.active_quests().is_empty())
	_check("rescue-fail: deed recorded",
		_deeds_text(adv, deeds_before).contains("Failed quest"))
	_check("rescue-fail: re-offered", adv.offered.has("q_rescue1"))
	# Accept gave +3 rep, failure gives -6 -> net negative.
	_check("rescue-fail: rep hit", _rep_score(adv, "giver:mayor") < 0.0)
	gs.free()


func _test_escort_npc_death_fails_quest() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_escort1")
	_check("escort-fail: accept", adv.accept_quest("q_escort1"))
	var q: Dictionary = adv.active_quests()[0]
	var npc_id := int(q.get("npc_id", -1))
	_check("escort-fail: npc spawned", npc_id > 0)
	var deeds_before: int = adv.deeds.size()
	gs.kill_unit(npc_id)
	adv.on_unit_died(npc_id)
	_check("escort-fail: quest done", String(q.get("state", "")) == "done")
	_check("escort-fail: marked failed", bool(q.get("failed", false)))
	_check("escort-fail: deed recorded",
		_deeds_text(adv, deeds_before).contains("Failed quest"))
	# The board holds 3 offers; the failed def queues behind them. Drain
	# the board and it must surface — failure is retryable, not a dead end.
	var guard := 0
	while not adv.offered.has("q_escort1") and guard < 10:
		for did in adv.offered.duplicate():
			if adv.accept_quest(did):
				var act: Array = adv.active_quests()
				if not act.is_empty():
					adv.complete_quest(String(act[0].get("id", "")))
				break
		guard += 1
	_check("escort-fail: re-offered", adv.offered.has("q_escort1"))
	_check("escort-fail: rep hit", _rep_score(adv, "giver:lord") < 0.0)
	gs.free()


func _test_freed_npc_death_no_fail() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_rescue1")
	adv.accept_quest("q_rescue1")
	var q: Dictionary = adv.active_quests()[0]
	var npc_id := int(q.get("npc_id", -1))
	# Complete the quest first — the NPC is freed (untagged) and becomes an
	# ordinary citizen. Its later death must not fail anything.
	adv.complete_quest(String(q.get("id")))
	var deeds_before: int = adv.deeds.size()
	gs.kill_unit(npc_id)
	adv.on_unit_died(npc_id)
	_check("freed: still completed", adv.completed_count() == 1)
	_check("freed: no fail deed",
		not _deeds_text(adv, deeds_before).contains("Failed quest"))
	gs.free()


func _test_failed_quest_reoffered_retryable() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_rescue1")
	adv.accept_quest("q_rescue1")
	var q: Dictionary = adv.active_quests()[0]
	gs.kill_unit(int(q.get("npc_id", -1)))
	adv.on_unit_died(int(q.get("npc_id", -1)))
	# The re-offered def accepts cleanly with a fresh captive.
	_check("retry: accept again", adv.accept_quest("q_rescue1"))
	var q2: Dictionary = adv.active_quests()[0]
	var npc2: Dictionary = gs.get_unit(int(q2.get("npc_id", -1)))
	_check("retry: fresh captive spawned",
		not npc2.is_empty() and npc2.get("alive", false))
	gs.free()


func _test_boss_slain_by_other_hand_wins() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	# Complete all six base quests (mirrors the win-test loop).
	var guard := 0
	while adv.completed_count() < 6 and guard < 20:
		for did in adv.offered.duplicate():
			if did == "q_finale":
				continue
			if adv.accept_quest(did):
				var act: Array = adv.active_quests()
				if not act.is_empty():
					adv.complete_quest(String(act[0].get("id", "")))
		guard += 1
	_check("boss-other: all 6 done", adv.completed_count() == 6)
	_check("boss-other: finale accepted", adv.accept_quest("q_finale"))
	var boss: Dictionary = {}
	for u: Dictionary in gs.units:
		if bool(u.get("_adv_boss", false)):
			boss = u
	_check("boss-other: boss spawned", not boss.is_empty())
	var h: Dictionary = adv.hero()
	var gold_before := float(h.get("gold", 0.0))
	var deeds_before: int = adv.deeds.size()
	# A disaster (not the hero) kills the Bandit King.
	gs.kill_unit(int(boss.get("id", -1)))
	adv.on_unit_died(int(boss.get("id", -1)))
	_check("boss-other: campaign won", adv.won)
	var finale_done := false
	for q: Dictionary in adv.quests:
		if String(q.get("def_id", "")) == "q_finale" \
				and String(q.get("state", "")) == "done" \
				and not bool(q.get("failed", false)):
			finale_done = true
	_check("boss-other: finale completed", finale_done)
	_check("boss-other: rewards paid",
		float(h.get("gold", 0.0)) >= gold_before + 1500.0)
	_check("boss-other: deed recorded",
		_deeds_text(adv, deeds_before).contains("not by the hero's hand"))
	gs.free()


func _test_fetch_after_full_clear() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	# Loot every chest BEFORE accepting the fetch quest (old dead end: the
	# item planted into a sealed chest, uncompletable).
	for dg: Dictionary in adv.dungeons:
		dg["cleared"] = true
		dg["chest_looted"] = true
	_force_offer(adv, "q_fetch1")
	_check("fetch: accept", adv.accept_quest("q_fetch1"))
	var q: Dictionary = adv.active_quests()[0]
	var dg_name := String((q.get("obj", {}) as Dictionary).get("dg_name", ""))
	var dg: Dictionary = {}
	for d: Dictionary in adv.dungeons:
		if String(d.get("name", "")) == dg_name:
			dg = d
	_check("fetch: planted somewhere", not dg.is_empty())
	_check("fetch: chest re-stocked", not bool(dg.get("chest_looted", true)))
	adv.loot_chest(String(dg.get("id", "")))
	_check("fetch: quest done",
		String(q.get("state", "")) == "done" \
		and not bool(q.get("failed", false)))
	gs.free()


func _test_escort_shrine_sane() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_escort1")
	adv.accept_quest("q_escort1")
	var q: Dictionary = adv.active_quests()[0]
	var sh: Array = (q.get("obj", {}) as Dictionary).get("shrine", [])
	_check("shrine: has x,y", sh.size() == 2)
	if sh.size() == 2:
		_check("shrine: in world bounds",
			float(sh[0]) >= 200.0 and float(sh[0]) <= 3896.0 \
			and float(sh[1]) >= 200.0 and float(sh[1]) <= 3896.0)
	gs.free()


func _test_prey_supply_guarantee() -> void:
	var parts: Array = _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_bounty1")
	_check("prey: accept", adv.accept_quest("q_bounty1"))
	# Snapshot the bandit ids first — the guarantee appends units on death,
	# so iterating gs.units live would also kill the fresh crew.
	var ids: Array[int] = []
	for u: Dictionary in gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == "bandit":
			ids.append(int(u.get("id", -1)))
	_check("prey: bandits existed", not ids.is_empty())
	for id in ids:
		gs.kill_unit(id)
		adv.on_unit_died(id)
	var living := 0
	for u: Dictionary in gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == "bandit":
			living += 1
	_check("prey: fresh crew rode in", living >= 3)
	var qs: Array = adv.active_quests()
	_check("prey: quest still active",
		qs.size() == 1 and String(qs[0].get("state", "")) == "active")
	gs.free()
