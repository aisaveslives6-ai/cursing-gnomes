extends SceneTree
## Cursing Gnomes — adventure quest expansion (2nd quest tier).
##
## Covers the 2026-10-08 wake deep-work pass on scripts/sim/adventure.gd:
##   - 6 new quest defs (roster 7 -> 13): q_bounty3, q_dungeon2, q_dungeon3,
##     q_rescue2, q_escort2, q_fetch2. All defs valid: required keys, known
##     obj kinds, gear ids in GEAR, dungeon ids real.
##   - REAL BUG fixed: quest defs carry "accept"/"done" flavor strings but
##     accept_quest() read the nonexistent "accept_line"/"done_line" keys, so
##     the hero's accept line never played and completion always said
##     "Done.". The mapping now reads the def keys; the lines surface via
##     bus.unit_said + the deed toast.
##   - _plant_quest_item hardened: skips the stronghold (never clearable —
##     a planted item there was uncompletable), skips chests already holding
##     another quest's item (one quest_item key — the second plant used to
##     overwrite the first), and rolls back loudly when no dungeon can hold
##     the item (def stays on the board).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_adventure_quests2.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes adventure quest expansion tests ===")
	seed(20261008)
	_test_defs_valid()
	_test_accept_done_lines_surface()
	_test_dungeon2_clears()
	_test_dungeon3_clears()
	_test_bounty3_kill_credits()
	_test_fetch_quests_plant_separate_chests()
	_test_fetch_rolls_back_when_no_chest()
	_test_stronghold_never_holds_quest_item()
	_test_finale_still_gates_at_six()
	_test_board_surfaces_new_quests()
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
		Vector2(1000, 1000))
	gs.add_building({"type": "town_hall", "faction": "gnomes",
		"town_id": int(town["id"]), "position": Vector2(1000, 1000)})
	var adv := SimAdventure.new(gs)
	var ok: bool = adv.start("gnomes", "TestHero", "soldier",
		Vector2(4096, 4096))
	return [gs, adv, ok]


func _force_offer(adv: SimAdventure, did: String) -> void:
	if not adv.offered.has(did):
		adv.offered.append(did)


func _active_quest(adv: SimAdventure, did: String) -> Dictionary:
	for q: Dictionary in adv.quests:
		if String(q.get("def_id", "")) == did \
				and String(q.get("state", "")) == "active":
			return q
	return {}


func _dungeon(adv: SimAdventure, dg_id: String) -> Dictionary:
	for d: Dictionary in adv.dungeons:
		if String(d.get("id", "")) == dg_id:
			return d
	return {}


func _clear_dungeon_units(gs: GameState, adv: SimAdventure,
		dg_id: String) -> void:
	var dg := _dungeon(adv, dg_id)
	for uid in (dg.get("denizen_ids", []) as Array).duplicate():
		var u := gs.get_unit(int(uid))
		if not u.is_empty():
			u["alive"] = false
			u["hp"] = 0.0
	var h := adv.hero()
	adv._dungeon_tick(h, 0.0)


## Every def has its required keys, a known obj kind, a real gear reward,
## and (for clear_dungeon) a real dungeon id.
func _test_defs_valid() -> void:
	var kinds := ["kill", "clear_dungeon", "rescue", "escort", "fetch", "boss"]
	var non_finale := 0
	for d: Dictionary in SimAdventure.QUEST_DEFS:
		var did := String(d.get("id", ""))
		for k: String in ["id", "type", "giver", "title", "desc", "intro",
				"accept", "done", "obj", "reward"]:
			_check("def %s has key %s" % [did, k], d.has(k))
		var obj: Dictionary = d.get("obj", {})
		_check("def %s known obj kind" % did,
			kinds.has(String(obj.get("kind", ""))))
		_check("def %s accept line nonempty" % did,
			String(d.get("accept", "")) != "")
		_check("def %s done line nonempty" % did,
			String(d.get("done", "")) != "")
		var gear_id := String((d.get("reward", {}) as Dictionary).get("gear",
			""))
		_check("def %s gear in GEAR" % did, SimAdventure.GEAR.has(gear_id))
		if String(obj.get("kind", "")) == "clear_dungeon":
			_check("def %s dg_id real" % did,
				["dg0", "dg1", "dg2"].has(String(obj.get("dg_id", ""))))
		if did != "q_finale":
			non_finale += 1
	_check("13 defs total", SimAdventure.QUEST_DEFS.size() == 13)
	_check("12 non-finale defs", non_finale == 12)


## The accept/done flavor text reaches the hero's voice: accept_quest maps
## the def keys, and completion toasts the done line (not "Done.").
func _test_accept_done_lines_surface() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_check("adventure started", bool(parts[2]))
	var said: Array = []
	gs.bus.unit_said.connect(func(_uid: int, text: String) -> void:
		said.append(text))
	_force_offer(adv, "q_bounty3")
	_check("bounty3 accepts", adv.accept_quest("q_bounty3"))
	var q := _active_quest(adv, "q_bounty3")
	_check("accept_line mapped from def",
		String(q.get("accept_line", "")) == "No more furniture. I swear it.")
	_check("accept line spoken", said.has("No more furniture. I swear it."))
	adv.complete_quest(String(q["id"]))
	_check("done line spoken, not 'Done.'",
		said.has("The goats are goats again. Mostly. One's still a footstool, but he's happy."))
	_check("never says bare Done.", not said.has("Done."))
	gs.queue_free()


## q_dungeon2 completes when Sunken Ruins (dg1) is cleared.
func _test_dungeon2_clears() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_dungeon2")
	_check("dungeon2 accepts", adv.accept_quest("q_dungeon2"))
	var q := _active_quest(adv, "q_dungeon2")
	_check("dungeon2 active", not q.is_empty())
	_clear_dungeon_units(gs, adv, "dg1")
	_check("dg1 cleared", bool(_dungeon(adv, "dg1").get("cleared", false)))
	_check("dungeon2 done",
		String(_active_quest(adv, "q_dungeon2").get("state", "done")) != "active")
	gs.queue_free()


## q_dungeon3 completes when the Gnawer Den (dg2) is cleared.
func _test_dungeon3_clears() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_dungeon3")
	_check("dungeon3 accepts", adv.accept_quest("q_dungeon3"))
	_clear_dungeon_units(gs, adv, "dg2")
	_check("dg2 cleared", bool(_dungeon(adv, "dg2").get("cleared", false)))
	_check("dungeon3 done",
		String(_active_quest(adv, "q_dungeon3").get("state", "done")) != "active")
	gs.queue_free()


## q_bounty3 credits monster-faction kills and completes at 4.
func _test_bounty3_kill_credits() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_bounty3")
	_check("bounty3 accepts", adv.accept_quest("q_bounty3"))
	for i in range(3):
		adv._on_hero_kill({"faction": "monster", "name": "Wild Beast",
			"alive": true})
	var q := _active_quest(adv, "q_bounty3")
	_check("3/4 counted",
		int((q.get("obj", {}) as Dictionary).get("count", 0)) == 3)
	adv._on_hero_kill({"faction": "monster", "name": "Wild Beast",
		"alive": true})
	_check("bounty3 done at 4",
		_active_quest(adv, "q_bounty3").is_empty())
	gs.queue_free()


## Two fetch quests plant into DIFFERENT chests — the second plant no
## longer overwrites the first quest's item.
func _test_fetch_quests_plant_separate_chests() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	_force_offer(adv, "q_fetch1")
	_force_offer(adv, "q_fetch2")
	_check("fetch1 accepts", adv.accept_quest("q_fetch1"))
	_check("fetch2 accepts", adv.accept_quest("q_fetch2"))
	var q1 := _active_quest(adv, "q_fetch1")
	var q2 := _active_quest(adv, "q_fetch2")
	var dg1 := String((q1.get("obj", {}) as Dictionary).get("dg_name", ""))
	var dg2 := String((q2.get("obj", {}) as Dictionary).get("dg_name", ""))
	_check("fetch quests plant in different dungeons", dg1 != "" and dg2 != ""
		and dg1 != dg2)
	var items := {}
	for d: Dictionary in adv.dungeons:
		var item := String((d.get("chest", {}) as Dictionary).get("quest_item",
			""))
		if item != "":
			items[String(d.get("name", ""))] = item
	_check("heirloom planted", items.values().has("Mayor's Heirloom"))
	_check("sock planted", items.values().has("Warlord's Lucky Sock"))
	_check("both items survive", items.size() >= 2)
	gs.queue_free()


## With every dungeon cleared AND every chest already holding a quest item,
## a fetch quest rolls back loudly and the def stays on the board. (Cleared
## but empty chests are re-stocked instead — quest-failure-run parity.)
func _test_fetch_rolls_back_when_no_chest() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	for d: Dictionary in adv.dungeons:
		d["cleared"] = true
		(d.get("chest", {}) as Dictionary)["quest_item"] = "Old Junk"
	_force_offer(adv, "q_fetch2")
	var ok: bool = adv.accept_quest("q_fetch2")
	_check("fetch2 refuses with no plantable chest", not ok)
	_check("no active fetch2", _active_quest(adv, "q_fetch2").is_empty())
	_check("def stays offered", adv.offered.has("q_fetch2"))
	var deed_hit := false
	for deed: String in adv.deeds:
		if deed.find("no plantable dungeon chest") >= 0:
			deed_hit = true
	_check("loud deed recorded", deed_hit)
	gs.queue_free()


## Cleared dungeons are re-stocked: accepting a fetch after a full clear
## still works (the quest-failure run's dead-end fix is preserved).
func _test_fetch_restocks_cleared_dungeon() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	for d: Dictionary in adv.dungeons:
		d["cleared"] = true
		d["chest_looted"] = true
	_force_offer(adv, "q_fetch2")
	_check("fetch2 accepts after full clear", adv.accept_quest("q_fetch2"))
	var q := _active_quest(adv, "q_fetch2")
	var dg_name := String((q.get("obj", {}) as Dictionary).get("dg_name", ""))
	_check("planted somewhere", dg_name != "")
	var dg := _dungeon_by_name(adv, dg_name)
	_check("sock in chest",
		String((dg.get("chest", {}) as Dictionary).get("quest_item", ""))
		== "Warlord's Lucky Sock")
	_check("chest re-stocked", not bool(dg.get("chest_looted", true)))
	gs.queue_free()


func _dungeon_by_name(adv: SimAdventure, dg_name: String) -> Dictionary:
	for d: Dictionary in adv.dungeons:
		if String(d.get("name", "")) == dg_name:
			return d
	return {}


## A quest item is never planted in the Bandit King's stronghold: the
## stronghold is skipped even when it is the only uncleared dungeon (a
## cleared regular dungeon is re-stocked instead).
func _test_stronghold_never_holds_quest_item() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	for d: Dictionary in adv.dungeons:
		d["cleared"] = true
	# Plant a fake stronghold the way _spawn_stronghold does.
	adv.dungeons.append({
		"id": "dg_stronghold", "name": "Bandit King's Stronghold",
		"kind": "fort", "pos": Vector2(2000, 2000), "discovered": true,
		"cleared": false, "chest_looted": false,
		"chest": {"gold": 800.0, "gear_id": "", "quest_item": ""},
		"denizen_ids": [], "is_stronghold": true,
	})
	_force_offer(adv, "q_fetch1")
	var ok: bool = adv.accept_quest("q_fetch1")
	_check("fetch1 accepted via re-stock", ok)
	var sh := _dungeon(adv, "dg_stronghold")
	_check("stronghold chest untouched",
		String((sh.get("chest", {}) as Dictionary).get("quest_item", "")) == "")
	var q := _active_quest(adv, "q_fetch1")
	var dg_name := String((q.get("obj", {}) as Dictionary).get("dg_name", ""))
	_check("planted in a real dungeon", dg_name != ""
		and dg_name != "Bandit King's Stronghold")
	gs.queue_free()


## The finale still unlocks after any 6 non-finale completions.
func _test_finale_still_gates_at_six() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	var ids := ["q_bounty1", "q_bounty2", "q_bounty3", "q_rescue1", "q_escort1",
		"q_fetch1"]
	for did: String in ids:
		_force_offer(adv, did)
		adv.accept_quest(did)
		var q := _active_quest(adv, did)
		adv.complete_quest(String(q["id"]))
	_check("finale offered at 6", adv.offered.has("q_finale"))
	gs.queue_free()


## New quests surface on the board once earlier quests are done.
func _test_board_surfaces_new_quests() -> void:
	var parts := _new_adventure()
	var gs: GameState = parts[0]
	var adv: SimAdventure = parts[1]
	for did: String in ["q_bounty1", "q_bounty2", "q_rescue1", "q_dungeon1",
			"q_escort1", "q_fetch1"]:
		_force_offer(adv, did)
		adv.accept_quest(did)
		var q := _active_quest(adv, did)
		adv.complete_quest(String(q["id"]))
	adv._refresh_board()
	_check("bounty3 surfaced", adv.offered.has("q_bounty3"))
	_check("dungeon2 surfaced", adv.offered.has("q_dungeon2"))
	_check("dungeon3 surfaced", adv.offered.has("q_dungeon3"))
	_check("finale offered at 6", adv.offered.has("q_finale"))
	gs.queue_free()
