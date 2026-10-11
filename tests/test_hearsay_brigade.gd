extends SceneTree
## Cursing Gnomes — fire-brigade rollout gossip tests (Jeremy 2026-10-10).
##
## Jeremy's 2026-10-10 direct order replaced the old "fire trucks dispatch
## autonomously" rapid-response abstraction with a real loop: firefighters
## mount up at the station lot, drive the truck to the fire with physics,
## dismount and fight it, drive back, re-park. The rollout — bells ringing,
## crew aboard, a speeding engine — is the realm's favorite spectacle and
## the grapevine was DEAF to it. Now:
##  - bus.fire_brigade_rolled (emitted once per dispatch per fire by
##    DisasterSim._tick_station_truck) seeds a RICH kind-"brigade" rumor
##    (faction + fire recorded, TRUTH_TRUE, heat 0.6 tavern talk — below
##    PRESS_HEAT 0.85 and QUEST_HEAT 0.7, no front page, no proposal)
##  - repeat ticks en route stay silent; a second station rolling to the
##    same fire refreshes via subject dedup ("brigade:<fire_id>"), Squabble
##    posts only on the fresh seed
##  - the brigade reaction matrix: the brigade's faction swells with pride,
##    the burning town feels hope (read off the live wildfire rumor's hit
##    faction), rivals mock the bells, the unhinged thrill at the
##    spectacle, everyone else just enjoys the news. Unhinged x1.5.
##  - spread motivation: the brigade's people brag-spread, rivals
##    mock-spread, everyone else tells it straight
##  - witnessed fact — joins the slur/famine/season/weather doubt-immunity
##    club (nobody doubts a spectacle); old saves without brigade_faction
##    fall through to the generic path
##  - all 5 new memory types registered in SimMemories.TYPES with weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_brigade.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay brigade gossip tests ===")
	_test_rollout_seeds_rumor()
	_test_empty_faction_seeds_nothing()
	_test_below_press_heat()
	_test_below_quest_heat()
	_test_truth_true()
	_test_repeat_rollout_refreshes_not_duplicates()
	_test_second_fire_separate_rumor()
	_test_brigade_faction_proud()
	_test_victim_faction_hopeful()
	_test_rival_mocks()
	_test_neutral_gets_news()
	_test_unhinged_thrilled()
	_test_spread_motivation()
	_test_memory_types_registered()
	_test_doubt_immunity()
	_test_old_save_fallthrough()
	_test_truck_rollout_emits_once()
	_test_no_duplicate_while_en_route()
	_test_new_fire_reemits()
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


func _new_gs() -> GameState:
	var gs = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	return gs


func _harness() -> Array:
	var gs := _new_gs()
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return [gs, phone, phone.hearsay]


func _spawn(gs: GameState, faction: String, pos: Vector2 = Vector2.ZERO,
		mind: Dictionary = {}) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "alive": true,
		"mind": mind})
	u["position"] = pos
	return u


func _unhinged_mind() -> Dictionary:
	return {"traits": {"unhinged": 1.0}}


func _rollout(gs: GameState, station_id: int, fire_id: int,
		faction: String) -> void:
	gs.bus.fire_brigade_rolled.emit(station_id, fire_id, faction)


func _rumor(hs, subject: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "brigade" \
				and String(r.get("subject", "")) == subject:
			return r
	return {}


func _count_brigade(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "brigade":
			n += 1
	return n


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _test_rollout_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	_check("rollout seeds a rumor", not r.is_empty())
	_check("brigade faction recorded",
		String(r.get("brigade_faction", "")) == "humans")
	_check("fire id recorded", int(r.get("brigade_fire", 0)) == 7)


func _test_empty_faction_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "")
	_check("factionless station seeds nothing", _count_brigade(hs) == 0)


func _test_below_press_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	_check("brigade stays tavern talk",
		float(r.get("heat", 0.0)) < hs.PRESS_HEAT)


func _test_below_quest_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	_check("brigade never spawns an advisor proposal",
		float(r.get("heat", 0.0)) < hs.QUEST_HEAT)


func _test_truth_true() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	_check("rollout is confirmed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)


func _test_repeat_rollout_refreshes_not_duplicates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "humans")
	_rollout(gs, 2, 7, "humans")  # second station, same fire
	_check("one fire shares one brigade rumor", _count_brigade(hs) == 1)
	var r := _rumor(hs, "brigade:7")
	r["heat"] = 0.2  # simulate daily decay between rollouts
	_rollout(gs, 1, 7, "humans")
	_check("repeat rollout refreshes cooled heat",
		is_equal_approx(float(r.get("heat", 0.0)), 0.6))


func _test_second_fire_separate_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "humans")
	_rollout(gs, 1, 8, "humans")
	_check("separate fires seed separate rumors", _count_brigade(hs) == 2)


func _test_brigade_faction_proud() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	var human := _spawn(gs, "humans")
	var uid := int(human.get("id", 0))
	hs._on_heard(human, r, {})
	_check("brigade faction remembers pride",
		_recalled(human, "brigade_pride", int(r.get("id", 0))) > 0.0)
	_check("pride lifts mood", conv.ruler_mood(uid) > 0.0)
	_check("pride feels proud", _emotion(human) == "proud")


func _test_victim_faction_hopeful() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# The burning town's wildfire rumor names the victim faction.
	var wf: Dictionary = hs.seed_rumor(
		"A wildfire rages through Elvhollow!", "disaster", "wildfire",
		0.85, -1, false, hs.TRUTH_TRUE)
	wf["hit_faction"] = "elves"
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	var elf := _spawn(gs, "elves")
	hs._on_heard(elf, r, {})
	_check("burning town remembers hope",
		_recalled(elf, "brigade_hope", int(r.get("id", 0))) > 0.0)
	_check("hope feels happy", _emotion(elf) == "happy")


func _test_rival_mocks() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	var ogre := _spawn(gs, "ogres")
	hs._on_heard(ogre, r, {})
	_check("rival remembers mockery",
		_recalled(ogre, "brigade_mock", int(r.get("id", 0))) > 0.0)


func _test_neutral_gets_news() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	var gnome := _spawn(gs, "gnomes")
	hs._on_heard(gnome, r, {})
	_check("neutral remembers the news",
		_recalled(gnome, "brigade_news", int(r.get("id", 0))) > 0.0)
	_check("news feels happy", _emotion(gnome) == "happy")


func _test_unhinged_thrilled() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	var wild := _spawn(gs, "gnomes", Vector2.ZERO, _unhinged_mind())
	hs._on_heard(wild, r, {})
	_check("unhinged remembers the thrill",
		_recalled(wild, "brigade_thrill", int(r.get("id", 0))) > 0.0)
	_check("thrill feels cheerful", _emotion(wild) == "happy")


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	var human := _spawn(gs, "humans")
	var ogre := _spawn(gs, "ogres")
	var gnome := _spawn(gs, "gnomes")
	_check("brigade faction brag-spreads",
		float(hs._spread_motivation(human, r).get("cap_delta", 0.0)) > 0.0)
	_check("rival mock-spreads",
		float(hs._spread_motivation(ogre, r).get("cap_delta", 0.0)) > 0.0)
	_check("neutral tells it straight",
		is_equal_approx(
			float(hs._spread_motivation(gnome, r).get("cap_delta", 0.0)),
			0.0))


func _test_memory_types_registered() -> void:
	var mem = load("res://scripts/sim/memories.gd")
	for t: String in ["brigade_pride", "brigade_hope", "brigade_thrill",
			"brigade_mock", "brigade_news"]:
		_check("memory type registered: " + t, t in mem.TYPES)
		_check("memory weight set: " + t, mem.REL_WEIGHT.has(t))


func _test_doubt_immunity() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_rollout(gs, 1, 7, "humans")
	var r := _rumor(hs, "brigade:7")
	var teller := _spawn(gs, "humans")
	var hearer := _spawn(gs, "humans")
	var clean: float = hs._belief(teller, hearer, r)
	var doubters: Array = []
	for i in 24:
		doubters.append(1000 + i)
	r["doubters"] = doubters
	r["distortions"] = 3
	_check("doubt can't dent a witnessed rollout",
		is_equal_approx(hs._belief(teller, hearer, r), clean))


func _test_old_save_fallthrough() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# A brigade rumor from an old save carries no rich fields.
	var r: Dictionary = hs.seed_rumor("old brigade tale", "brigade",
		"brigade:3", 0.5, -1, false, hs.TRUTH_TRUE)
	var gnome := _spawn(gs, "gnomes")
	hs._on_heard(gnome, r, {})
	_check("old save takes the generic path",
		_recalled(gnome, "heard_rumor", int(r.get("id", 0))) > 0.0)
	_check("old save seeds no brigade memory",
		_recalled(gnome, "brigade_news", int(r.get("id", 0))) == 0.0)


## Dry world: one complete fire station, one firefighter, real vehicles.
func _dry_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var ai := WorkerAI.new(gs)
	gs.worker_ai = ai
	var veh := SimVehicles.new(gs)
	gs.vehicles = veh
	var combat := SimCombat.new(gs)
	var dis := DisasterSim.new(gs, combat)
	var station := {"id": 1, "type": "fire_station", "faction": "humans",
		"complete": true, "alive": true, "position": Vector2(500, 500)}
	gs.buildings.append(station)
	var ff := {"id": 10, "job": "firefighter", "faction": "humans",
		"alive": true, "position": Vector2(500, 500)}
	gs.units.append(ff)
	var hits: Array = []
	gs.bus.fire_brigade_rolled.connect(
		func(sid: int, fid: int, fac: String) -> void:
			hits.append([sid, fid, fac]))
	return {"gs": gs, "dis": dis, "veh": veh, "station": station,
		"ff": ff, "hits": hits}


func _free_dry(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _rollout_setup(w: Dictionary, fire_pos: Vector2,
		fire_id: int) -> void:
	var dis: DisasterSim = w["dis"]
	var ff: Dictionary = w["ff"]
	dis.tick_station_trucks(1.0 / 60.0)  # station spawns its truck
	dis.fires.append({"id": fire_id, "position": fire_pos,
		"intensity": 100.0})
	ff["position"] = dis._station_lot(w["station"] as Dictionary)
	dis.tick_firefighter(ff, 1.0 / 60.0)  # boards at the lot


func _test_truck_rollout_emits_once() -> void:
	var w := _dry_world()
	var dis: DisasterSim = w["dis"]
	_rollout_setup(w, Vector2(1500, 500), 7)
	dis.tick_station_trucks(1.0 / 60.0)  # crew aboard -> rolls out
	var hits: Array = w["hits"]
	_check("rollout emits exactly once", hits.size() == 1)
	if hits.size() == 1:
		_check("emit carries station id", int(hits[0][0]) == 1)
		_check("emit carries fire id", int(hits[0][1]) == 7)
		_check("emit carries faction", String(hits[0][2]) == "humans")
	_free_dry(w)


func _test_no_duplicate_while_en_route() -> void:
	var w := _dry_world()
	var dis: DisasterSim = w["dis"]
	_rollout_setup(w, Vector2(1500, 500), 7)
	dis.tick_station_trucks(1.0 / 60.0)
	dis.tick_station_trucks(1.0 / 60.0)
	dis.tick_station_trucks(1.0 / 60.0)
	_check("repeat ticks en route stay silent",
		(w["hits"] as Array).size() == 1)
	_free_dry(w)


func _test_new_fire_reemits() -> void:
	var w := _dry_world()
	var dis: DisasterSim = w["dis"]
	_rollout_setup(w, Vector2(1500, 500), 7)
	dis.tick_station_trucks(1.0 / 60.0)
	dis.fires.clear()
	dis.fires.append({"id": 8, "position": Vector2(1500, 500),
		"intensity": 100.0})
	dis.tick_station_trucks(1.0 / 60.0)
	var hits: Array = w["hits"]
	_check("a new fire gets its own announcement", hits.size() == 2)
	if hits.size() == 2:
		_check("second emit carries the new fire id",
			int(hits[1][1]) == 8)
	_free_dry(w)
