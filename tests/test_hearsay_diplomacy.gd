extends SceneTree
## Cursing Gnomes — hearsay diplomacy reaction tests
## (Jeremy 2026-10-07, hearsay flesh-out).
##
## The diplomacy thread was the weakest grapevine thread: peace treaties,
## alliances, trade pacts, tribute payments, hostile turns, and town
## foundings all seeded rumors but produced NO character reactions —
## dead-end news nobody cared about. Now the rumors record both sides at
## seed and hearers react in character (the diplomacy reaction matrix):
##  - peace: peacemakers breathe easier (mood up, "heard_peace")
##  - alliance: allies swell with pride; factions hostile with either
##    side grow uneasy ("enemy_alliance", mood down)
##  - trade: traders content ("heard_trade"); their enemies sneer
##    ("rival_trade")
##  - tribute: the payer feels the sting ("paid_tribute", mood down),
##    the receiver feels smug ("tribute_won", mood up)
##  - hostile: both sides brace ("heard_hostile", mood down)
##  - town: the founding faction celebrates ("town_founded_us")
##  - neutrals/dip-less rumors (old saves): generic reception, no crash
##  - unhinged NPCs feel diplomatic news 1.5x (war/smear parity)
##  - dedup refresh keeps the dip fields; save/load keeps them too
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_diplomacy.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay diplomacy tests ===")
	_test_peace_records_sides()
	_test_peace_reaction()
	_test_alliance_matrix()
	_test_trade_matrix()
	_test_tribute_matrix()
	_test_hostile_matrix()
	_test_town_founded_matrix()
	_test_neutral_generic_no_crash()
	_test_dipless_news_generic()
	_test_unhinged_amplified()
	_test_dedup_keeps_dip()
	_test_save_load_roundtrip()
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


func _spawn(gs: GameState, faction: String, unhinged: bool = false) -> Dictionary:
	var mind: Dictionary = {}
	if unhinged:
		mind = {"traits": {"unhinged": 1.0}}
	return gs.add_unit({"faction": faction, "alive": true, "mind": mind})


func _dip_rumor(hs, dip: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("dip", "")) == dip:
			return r
	return {}


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _set_relation(gs: GameState, a: String, b: String, st: String) -> void:
	var rec: Dictionary = gs.diplomacy._pair(a, b)
	if not rec.is_empty():
		rec["state"] = st


func _test_peace_records_sides() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.peace_made.emit("gnomes", "elves")
	var r: Dictionary = _dip_rumor(hs, "peace")
	_check("peace rumor seeded", not r.is_empty())
	_check("peace side_a recorded", String(r.get("side_a", "")) == "gnomes")
	_check("peace side_b recorded", String(r.get("side_b", "")) == "elves")


func _test_peace_reaction() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.bus.peace_made.emit("gnomes", "elves")
	var r: Dictionary = _dip_rumor(hs, "peace")
	var peacemaker: Dictionary = _spawn(gs, "elves")
	var pid := int(peacemaker.get("id", 0))
	var mood_before: float = conv.ruler_mood(pid)
	hs._on_heard(peacemaker, r, {})
	_check("peacemaker mood rises on peace news",
		conv.ruler_mood(pid) > mood_before)
	_check("peacemaker remembers heard_peace",
		_recalled(peacemaker, "heard_peace", int(r.get("id", 0))) > 0.0)
	var outsider: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(outsider, r, {})
	_check("outsider gets generic heard_rumor",
		_recalled(outsider, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _test_alliance_matrix() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.bus.alliance_signed.emit("humans", "elves")
	var r: Dictionary = _dip_rumor(hs, "alliance")
	_check("alliance sides recorded",
		String(r.get("side_a", "")) == "humans" \
		and String(r.get("side_b", "")) == "elves")
	# An enemy of the allies grows uneasy.
	_set_relation(gs, "ogres", "elves", "hostile")
	var enemy: Dictionary = _spawn(gs, "ogres")
	var eid := int(enemy.get("id", 0))
	var ally: Dictionary = _spawn(gs, "humans")
	var aid := int(ally.get("id", 0))
	var ally_before: float = conv.ruler_mood(aid)
	var enemy_before: float = conv.ruler_mood(eid)
	hs._on_heard(ally, r, {})
	hs._on_heard(enemy, r, {})
	_check("ally mood rises on alliance news",
		conv.ruler_mood(aid) > ally_before)
	_check("ally remembers heard_alliance",
		_recalled(ally, "heard_alliance", int(r.get("id", 0))) > 0.0)
	_check("enemy mood drops on enemy alliance",
		conv.ruler_mood(eid) < enemy_before)
	_check("enemy remembers enemy_alliance",
		_recalled(enemy, "enemy_alliance", int(r.get("id", 0))) > 0.0)


func _test_trade_matrix() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.bus.trade_signed.emit("humans", "elves")
	var r: Dictionary = _dip_rumor(hs, "trade")
	_check("trade sides recorded",
		String(r.get("side_a", "")) == "humans" \
		and String(r.get("side_b", "")) == "elves")
	_set_relation(gs, "ogres", "humans", "war")
	var trader: Dictionary = _spawn(gs, "elves")
	var tid := int(trader.get("id", 0))
	var rival: Dictionary = _spawn(gs, "ogres")
	var rid2 := int(rival.get("id", 0))
	var trader_before: float = conv.ruler_mood(tid)
	var rival_before: float = conv.ruler_mood(rid2)
	hs._on_heard(trader, r, {})
	hs._on_heard(rival, r, {})
	_check("trader mood rises on trade news",
		conv.ruler_mood(tid) > trader_before)
	_check("trader remembers heard_trade",
		_recalled(trader, "heard_trade", int(r.get("id", 0))) > 0.0)
	_check("war rival sneers at trade (mood down)",
		conv.ruler_mood(rid2) < rival_before)
	_check("war rival remembers rival_trade",
		_recalled(rival, "rival_trade", int(r.get("id", 0))) > 0.0)


func _test_tribute_matrix() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.bus.tribute_paid.emit("ogres", "humans", "gold", 50.0)
	var r: Dictionary = _dip_rumor(hs, "tribute")
	_check("tribute payer recorded", String(r.get("payer", "")) == "ogres")
	_check("tribute receiver recorded", String(r.get("receiver", "")) == "humans")
	var payer: Dictionary = _spawn(gs, "ogres")
	var pid := int(payer.get("id", 0))
	var receiver: Dictionary = _spawn(gs, "humans")
	var rid := int(receiver.get("id", 0))
	var payer_before: float = conv.ruler_mood(pid)
	var receiver_before: float = conv.ruler_mood(rid)
	hs._on_heard(payer, r, {})
	hs._on_heard(receiver, r, {})
	_check("payer mood drops on tribute news",
		conv.ruler_mood(pid) < payer_before)
	_check("payer remembers paid_tribute",
		_recalled(payer, "paid_tribute", int(r.get("id", 0))) > 0.0)
	_check("receiver mood rises on tribute news",
		conv.ruler_mood(rid) > receiver_before)
	_check("receiver remembers tribute_won",
		_recalled(receiver, "tribute_won", int(r.get("id", 0))) > 0.0)


func _test_hostile_matrix() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.bus.relation_changed.emit("humans", "ogres", "hostile")
	var r: Dictionary = _dip_rumor(hs, "hostile")
	_check("hostile sides recorded",
		String(r.get("side_a", "")) == "humans" \
		and String(r.get("side_b", "")) == "ogres")
	var bracer: Dictionary = _spawn(gs, "humans")
	var bid := int(bracer.get("id", 0))
	var before: float = conv.ruler_mood(bid)
	hs._on_heard(bracer, r, {})
	_check("involved faction braces (mood down)",
		conv.ruler_mood(bid) < before)
	_check("bracer remembers heard_hostile",
		_recalled(bracer, "heard_hostile", int(r.get("id", 0))) > 0.0)


func _test_town_founded_matrix() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.bus.town_founded.emit({"name": "Testville", "faction": "elves"})
	var r: Dictionary = _dip_rumor(hs, "town")
	_check("town rumor seeded", not r.is_empty())
	_check("town founder recorded", String(r.get("founder", "")) == "elves")
	var founder: Dictionary = _spawn(gs, "elves")
	var fid := int(founder.get("id", 0))
	var before: float = conv.ruler_mood(fid)
	hs._on_heard(founder, r, {})
	_check("founder mood rises on founding news",
		conv.ruler_mood(fid) > before)
	_check("founder remembers town_founded_us",
		_recalled(founder, "town_founded_us", int(r.get("id", 0))) > 0.0)
	var outsider: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(outsider, r, {})
	_check("outsider gets generic heard_rumor on founding news",
		_recalled(outsider, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _test_neutral_generic_no_crash() -> void:
	# A rumor of an unknown dip subtype (or none at all) never crashes.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r: Dictionary = hs.seed_rumor("Weird tavern talk.", "news", "odd", 0.5)
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("dipless news rumor heard without crash",
		_recalled(u, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _test_dipless_news_generic() -> void:
	# An old-save rumor: dip backfilled as "" — generic reception.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r: Dictionary = hs.seed_rumor("Peace with the Elves! (old save)", "news",
		"elves", 0.7, -1, false, "true")
	r.erase("dip")
	hs.from_dict(hs.to_dict())
	var loaded: Dictionary = _dip_rumor(hs, "")
	var u: Dictionary = _spawn(gs, "elves")
	hs._on_heard(u, loaded if not loaded.is_empty() else r, {})
	_check("old-save news rumor heard without crash", true)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.bus.tribute_paid.emit("ogres", "humans", "gold", 50.0)
	var r: Dictionary = _dip_rumor(hs, "tribute")
	var calm: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", true)
	var cid := int(calm.get("id", 0))
	var wid := int(wild.get("id", 0))
	var calm_before: float = conv.ruler_mood(cid)
	var wild_before: float = conv.ruler_mood(wid)
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	var calm_drop: float = calm_before - conv.ruler_mood(cid)
	var wild_drop: float = wild_before - conv.ruler_mood(wid)
	_check("unhinged payer feels tribute news harder (1.5x)",
		wild_drop > calm_drop)


func _test_dedup_keeps_dip() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.peace_made.emit("gnomes", "elves")
	gs.bus.peace_made.emit("gnomes", "elves")
	var count: int = 0
	var kept: Dictionary = {}
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("dip", "")) == "peace":
			count += 1
			kept = r
	_check("one peace rumor after double emission", count == 1)
	_check("dedup keeps dip", String(kept.get("dip", "")) == "peace")
	_check("dedup keeps sides", String(kept.get("side_a", "")) == "gnomes" \
		and String(kept.get("side_b", "")) == "elves")


func _test_save_load_roundtrip() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.peace_made.emit("gnomes", "elves")
	gs.bus.tribute_paid.emit("ogres", "humans", "gold", 50.0)
	var data: Dictionary = hs.to_dict()
	var hs2 = load("res://scripts/sim/hearsay.gd").new(gs)
	hs2.from_dict(data)
	var peace: Dictionary = {}
	var trib: Dictionary = {}
	for r: Dictionary in hs2.state["rumors"]:
		if String(r.get("dip", "")) == "peace":
			peace = r
		elif String(r.get("dip", "")) == "tribute":
			trib = r
	_check("peace dip survives save/load", not peace.is_empty())
	_check("peace sides survive save/load",
		String(peace.get("side_a", "")) == "gnomes" \
		and String(peace.get("side_b", "")) == "elves")
	_check("tribute dip survives save/load", not trib.is_empty())
	_check("tribute payer/receiver survive save/load",
		String(trib.get("payer", "")) == "ogres" \
		and String(trib.get("receiver", "")) == "humans")
