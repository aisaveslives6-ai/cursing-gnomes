extends SceneTree
## Tests for wartime aid requests + war collapse (HTML war32 port,
## Jeremy 2026-10-05 — AI-first phase).
##
## Aid: an ally at war and losing (own mil < 80% of strongest foe's) begs
## the player for gold (300-800) or troops (4-9). Accept moves REAL aid;
## refuse is a -45 grudge. Collapse: wars end when a side can't fight
## (military strength < 2) — mutual collapse or one-sided crushing.
##
## Run: Godot --headless --path . -s res://tests/test_war_aid_collapse.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("FAIL: ", name)


func _initialize() -> void:
	_test_aid_tick_gating()
	_test_aid_tick_no_ask_cases()
	_test_aid_resolve_gold()
	_test_aid_resolve_troops()
	_test_aid_resolve_refuse()
	_test_aid_court_routing()
	_test_aid_save_load()
	_test_collapse_mutual()
	_test_collapse_one_sided()
	_test_collapse_strong_armies_fight_on()
	print("test_war_aid_collapse: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.player_faction = "humans"
	return {"gs": gs, "dip": gs.diplomacy}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _set_gold(gs: GameState, faction: String, amount: float) -> void:
	gs.resources.add_resource(faction, "gold",
		-gs.resources.get_amount(faction, "gold"), true)
	gs.resources.add_resource(faction, "gold", amount, true)


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	return (w["gs"] as GameState).spawner.spawn_unit(faction, job, -1, pos)


func _soldiers(w: Dictionary, faction: String) -> int:
	var n := 0
	for u: Dictionary in (w["gs"] as GameState).units:
		if bool(u.get("alive", false)) \
				and String(u.get("faction", "")) == faction \
				and String(u.get("job", "")) == "soldier":
			n += 1
	return n


## Ogres allied with the player, at war with elves, and losing badly.
func _losing_ally_world() -> Dictionary:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.form_alliance("humans", "ogres")
	dip.declare_war("ogres", "elves", "test")
	_spawn(w, "ogres", "soldier", Vector2(0, 0))  # 1.0 mil, also the envoy
	for i: int in range(10):
		_spawn(w, "elves", "soldier", Vector2(100 + i * 8, 0))  # 10.0 mil
	return w


## --- aid tick -----------------------------------------------------------------


func _test_aid_tick_gating() -> void:
	var w: Dictionary = _losing_ally_world()
	var dip: SimDiplomacy = w["dip"]
	# 1.0 < 10.0 * 0.8 -> losing. The pride roll (50%) must hit eventually:
	# P(30 misses) = 2^-30, so this is deterministic in practice.
	seed(20261005)
	for i: int in range(30):
		dip._aid_tick()
		if dip.pending_aid_requests().size() > 0:
			break
	var pending: Array = dip.pending_aid_requests()
	_check(pending.size() == 1, "losing ally begs the player (one request)")
	if pending.size() == 1:
		var req: Dictionary = pending[0]
		_check(String(req.get("asker", "")) == "ogres", "asker is ogres")
		_check(String(req.get("what", "")) in ["gold", "troops"],
			"ask is gold or troops")
		var amt := int(req.get("amount", 0))
		if String(req.get("what", "")) == "gold":
			_check(amt >= 300 and amt <= 799, "gold ask 300-799")
		else:
			_check(amt >= 4 and amt <= 9, "troop ask 4-9")
	# While the ask is pending, no second ask is created (HTML w.aid parity).
	for i: int in range(30):
		dip._aid_tick()
	_check(dip.pending_aid_requests().size() == 1,
		"no second ask while one is pending")
	_free_world(w)


func _test_aid_tick_no_ask_cases() -> void:
	# Not allied -> no begging.
	var w1: Dictionary = _new_world()
	var dip1: SimDiplomacy = w1["dip"]
	dip1.declare_war("ogres", "elves", "test")
	_spawn(w1, "ogres", "soldier", Vector2(0, 0))
	for i: int in range(10):
		_spawn(w1, "elves", "soldier", Vector2(100 + i * 8, 0))
	seed(7)
	for i: int in range(30):
		dip1._aid_tick()
	_check(dip1.pending_aid_requests().is_empty(),
		"non-ally never begs")
	_free_world(w1)
	# Allied but WINNING -> no begging.
	var w2: Dictionary = _losing_ally_world()
	var dip2: SimDiplomacy = w2["dip"]
	for i: int in range(12):
		_spawn(w2, "ogres", "soldier", Vector2(200 + i * 8, 0))  # 13 mil now
	seed(7)
	for i: int in range(30):
		dip2._aid_tick()
	_check(dip2.pending_aid_requests().is_empty(),
		"winning ally never begs")
	_free_world(w2)
	# Allied, outgunned, but NOT at war -> no begging (no foe to fear).
	var w3: Dictionary = _new_world()
	var dip3: SimDiplomacy = w3["dip"]
	dip3.form_alliance("humans", "ogres")
	_spawn(w3, "ogres", "soldier", Vector2(0, 0))
	for i: int in range(10):
		_spawn(w3, "elves", "soldier", Vector2(100 + i * 8, 0))
	seed(7)
	for i: int in range(30):
		dip3._aid_tick()
	_check(dip3.pending_aid_requests().is_empty(),
		"ally at peace never begs")
	_free_world(w3)


## --- aid resolution -------------------------------------------------------------


func _test_aid_resolve_gold() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	_set_gold(gs, "humans", 1000.0)
	_set_gold(gs, "ogres", 50.0)
	var aid_id := dip.offer_aid("ogres", "gold", 500)
	_check(aid_id != "", "offer_aid returns an id")
	var res: Dictionary = dip.resolve_aid(aid_id, true)
	_check(bool(res.get("ok", false)), "resolve_aid accept ok")
	_check(gs.resources.get_amount("humans", "gold") == 500.0,
		"player paid 500 gold")
	_check(gs.resources.get_amount("ogres", "gold") == 550.0,
		"ally received 500 gold")
	# HTML bumps: min(30, 10 + 500/100)=15 their view, +10 ours (pair: +25).
	_check(dip.relation_score("humans", "ogres") == 25.0,
		"aid accepted: pair score +25")
	_check(dip.pending_aid_requests().is_empty(),
		"resolved request leaves the pending list")
	_check(dip.grudge_against("ogres", "humans") > 0.0,
		"aid_given recorded in history")
	# Unknown id -> clean failure, no crash.
	var bad: Dictionary = dip.resolve_aid("aid9999", true)
	_check(not bool(bad.get("ok", false)), "unknown aid id fails cleanly")
	_free_world(w)


func _test_aid_resolve_troops() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	gs.found_town("ogres", "Ogreton", Vector2(400, 300))
	_set_gold(gs, "humans", 1000.0)
	var before := _soldiers(w, "ogres")
	var aid_id := dip.offer_aid("ogres", "troops", 6)
	var res: Dictionary = dip.resolve_aid(aid_id, true)
	_check(bool(res.get("ok", false)), "troop aid accept ok")
	_check(_soldiers(w, "ogres") == before + 6,
		"6 soldiers mustered for the ally")
	_check(gs.resources.get_amount("humans", "gold") == 850.0,
		"hire fee 6x25g charged")
	# Broke crown: sends what the treasury covers (here: none).
	_set_gold(gs, "humans", 10.0)
	var aid2 := dip.offer_aid("ogres", "troops", 6)
	dip.resolve_aid(aid2, true)
	_check(_soldiers(w, "ogres") == before + 6,
		"broke crown musters no extra troops")
	_check(gs.resources.get_amount("humans", "gold") == 10.0,
		"broke crown charged nothing")
	_free_world(w)


func _test_aid_resolve_refuse() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	_set_gold(gs, "humans", 1000.0)
	var aid_id := dip.offer_aid("ogres", "gold", 500)
	var res: Dictionary = dip.resolve_aid(aid_id, false)
	_check(bool(res.get("ok", false)), "resolve_aid refuse ok")
	_check(dip.relation_score("humans", "ogres") == -45.0,
		"refused ally: pair score -45 (HTML grudge)")
	_check(gs.resources.get_amount("humans", "gold") == 1000.0,
		"refused ally: no gold moves")
	_check(dip.grudge_against("ogres", "humans") < -1.0,
		"aid_refused recorded as a durable grudge")
	_free_world(w)


func _test_aid_court_routing() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	var court := SimRoyalCourt.new(gs)
	court.diplomacy = dip
	dip.court = court
	_set_gold(gs, "humans", 1000.0)
	_set_gold(gs, "ogres", 0.0)
	_spawn(w, "ogres", "worker", Vector2(0, 0))  # the envoy
	var aid_id := dip.offer_aid("ogres", "gold", 400)
	_check(aid_id != "", "aid ask created with court wired")
	var petitions: Array = court.open_petitions()
	var aid_p: Dictionary = {}
	for p: Dictionary in petitions:
		if String(p.get("kind", "")) == "aid":
			aid_p = p
	_check(not aid_p.is_empty(), "aid arrives as a court petition")
	_check(String(aid_p.get("aid_request_id", "")) == aid_id,
		"petition carries the aid_request_id")
	# The crown chooses "Send aid".
	court.decide(int(aid_p["id"]), 0)
	_check(gs.resources.get_amount("humans", "gold") == 600.0,
		"court accept: player paid 400 gold")
	_check(gs.resources.get_amount("ogres", "gold") == 400.0,
		"court accept: ally received 400 gold")
	_check(dip.pending_aid_requests().is_empty(),
		"court decision resolves the request")
	# And "Refuse" stings.
	_spawn(w, "elves", "worker", Vector2(50, 0))
	var aid2 := dip.offer_aid("elves", "gold", 300)
	var aid_p2: Dictionary = {}
	for p: Dictionary in court.open_petitions():
		if String(p.get("aid_request_id", "")) == aid2:
			aid_p2 = p
	court.decide(int(aid_p2["id"]), 1)  # "Refuse"
	_check(dip.relation_score("humans", "elves") == -45.0,
		"court refuse: pair score -45")
	_free_world(w)


func _test_aid_save_load() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.offer_aid("ogres", "gold", 500)
	var data: Dictionary = dip.to_dict()
	_check((data.get("aid_requests", {}) as Dictionary).size() == 1,
		"aid_requests serialized")
	dip.from_dict(data)
	_check(dip.pending_aid_requests().size() == 1,
		"pending aid request survives save/load")
	var req: Dictionary = dip.pending_aid_requests()[0]
	_check(String(req.get("asker", "")) == "ogres"
		and int(req.get("amount", 0)) == 500,
		"aid request fields intact after load")
	_free_world(w)


## --- war collapse -----------------------------------------------------------------


func _test_collapse_mutual() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "elves", "test")  # no armies on either side
	dip._collapse_tick()
	_check(dip.relation_state("ogres", "elves") == "neutral",
		"mutual collapse: war ends")
	_check(dip.truce_active("ogres", "elves"),
		"mutual collapse: 45-day truce signed")
	_free_world(w)


func _test_collapse_one_sided() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "elves", "test")
	for i: int in range(10):
		_spawn(w, "ogres", "soldier", Vector2(i * 8, 0))
	# Elves field no army (0.0 < 2.0) -> crushed.
	dip._collapse_tick()
	_check(dip.relation_state("ogres", "elves") != "war",
		"crushing victory: war ends")
	_check(dip.truce_active("ogres", "elves"),
		"crushing victory: truce signed")
	# make_peace resets to 0, then the winner's contempt lands: -20.
	_check(dip.relation_score("ogres", "elves") == -20.0,
		"crushing victory: winner contempt -20")
	_check(dip.relation_state("ogres", "elves") == "hostile",
		"crushed pair sits hostile (truce blocks re-war)")
	_free_world(w)


func _test_collapse_strong_armies_fight_on() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "elves", "test")
	for i: int in range(5):
		_spawn(w, "ogres", "soldier", Vector2(i * 8, 0))
		_spawn(w, "elves", "soldier", Vector2(100 + i * 8, 0))
	dip._collapse_tick()
	_check(dip.relation_state("ogres", "elves") == "war",
		"strong armies: war continues")
	_free_world(w)
