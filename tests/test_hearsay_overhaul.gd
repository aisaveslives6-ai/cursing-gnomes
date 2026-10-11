extends SceneTree
## Cursing Gnomes — hearsay overhaul tests (Jeremy 2026-10-06).
##
## Covers the full bug audit + comprehension expansion:
##  - tribute seeds a rumor (was Squabble-only)
##  - adventure_deed wires into deed gossip (was completely unwired)
##  - spread caps are per-knower (was accidentally global)
##  - kind+subject dedup refreshes instead of duplicating
##  - telephone-game distortion applies and caps
##  - belief: same-faction believed, at-war doubted
##  - reception: knowers get memory + emotion
##  - witnesses join rumors (replaces dead unit_said shouts)
##  - new event handlers seed rumors
##  - from_dict backfills the distortion schema
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_overhaul.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay-overhaul tests ===")
	_test_tribute_seeds_rumor()
	_test_deed_wires_to_gossip()
	_test_spread_cap_per_knower()
	_test_dedup_refresh()
	_test_distortion_applies_and_caps()
	_test_belief_same_faction()
	_test_belief_at_war_doubts()
	_test_reception_memory_and_emotion()
	_test_witness_joins_rumor()
	_test_building_destroyed_rumor()
	_test_monastery_captured_rumor()
	_test_trade_signed_rumor()
	_test_tribute_refused_rumor()
	_test_relation_hostile_rumor()
	_test_relation_allied_no_rumor()
	_test_from_dict_backfill()
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


func _new_phone(gs: GameState):
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return phone


func _spawn(gs: GameState, faction: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": {}})


func _rumors_of_kind(hs, kind: String) -> Array:
	var out: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == kind:
			out.append(r)
	return out


func _test_tribute_seeds_rumor() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.bus.tribute_paid.emit("ogres", "gnomes", "gold", 500.0)
	var found := false
	for r: Dictionary in _rumors_of_kind(hs, "tribute"):
		if String(r.get("text", "")).contains("500"):
			found = true
	_check("tribute seeds rumor", found)
	gs.queue_free()


func _test_deed_wires_to_gossip() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.bus.adventure_deed.emit("Sir Testsalot slew the dragon of QA")
	var found := false
	for r: Dictionary in _rumors_of_kind(hs, "deed"):
		if String(r.get("text", "")).contains("dragon"):
			found = true
	_check("adventure deed becomes rumor", found)
	gs.queue_free()


func _test_spread_cap_per_knower() -> void:
	# Flaked in the 2026-10-06 full suite (daily_tick spread rolls are
	# RNG-gated; prior suites drain the global stream). Seed deterministically
	# so the gate is immune to test order. Sim mechanics untouched.
	seed(20261006)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	# Three happy knowers: with the old global cap the day's spread died
	# after 2 tells total; per-knower caps let each loudmouth tell.
	var knowers: Array = []
	for i in range(3):
		var u: Dictionary = _spawn(gs, "gnomes")
		u["mood"] = {"name": "happy", "intensity": 1.0}
		knowers.append(int(u.get("id", 0)))
	var r: Dictionary = hs.seed_rumor("Loud news travels fast.", "news", "loudtest", 1.0)
	r["knowers"] = knowers.duplicate()
	# Many fresh citizens to tell.
	for i in range(30):
		_spawn(gs, "gnomes")
	var before: int = (r["knowers"] as Array).size()
	hs.daily_tick()
	var after: int = (r["knowers"] as Array).size()
	# Per-knower caps (3 each for happy) with heat 1.0 must exceed the old
	# global ceiling of 2 tells per day.
	_check("per-knower spread exceeds old global cap", after - before > 2)
	gs.queue_free()


func _test_dedup_refresh() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	hs.seed_rumor("WAR with the Ogres!", "war", "ogres", 0.5)
	hs.daily_tick()  # decay to ~0.41
	hs.seed_rumor("WAR with the Ogres! (gazette version)", "war", "ogres", 0.9)
	var matches := _rumors_of_kind(hs, "war").filter(
		func(r: Dictionary) -> bool: return String(r.get("subject", "")) == "ogres")
	_check("no duplicate war rumor", matches.size() == 1)
	_check("heat refreshed", float(matches[0].get("heat", 0.0)) >= 0.89)
	gs.queue_free()


func _test_distortion_applies_and_caps() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var changed: String = hs._distort_text("A big dragon rampages through the realm!")
	_check("distortion mutates text", changed != "A big dragon rampages through the realm!")
	var r: Dictionary = hs.seed_rumor("A big dragon rampages!", "disaster", "dtest", 0.9)
	r["distortions"] = 3
	var before_text := String(r.get("text", ""))
	hs._maybe_distort(r)
	_check("distortion capped at 3", String(r.get("text", "")) == before_text
		and int(r.get("distortions", 0)) == 3)
	_check("text_orig preserved", String(r.get("text_orig", "")) == "A big dragon rampages!")
	gs.queue_free()


func _test_belief_same_faction() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var teller: Dictionary = _spawn(gs, "gnomes")
	var hearer: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("Our taverns are the best.", "news", "btest", 0.9)
	var b: float = hs._belief(teller, hearer, r)
	_check("same faction believed", b >= 0.9)
	gs.queue_free()


func _test_belief_at_war_doubts() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.diplomacy.declare_war("gnomes", "ogres")
	var teller: Dictionary = _spawn(gs, "ogres")
	var hearer: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("We come in peace.", "news", "wtest", 0.5)
	var b: float = hs._belief(teller, hearer, r)
	_check("at-war teller doubted", b < 0.5)
	# And doubt records a memory.
	hs._on_doubted(hearer, r, teller)
	var mems: Array = SimMemories.new(gs).ensure(hearer)
	var found := false
	for m: Dictionary in mems:
		if String(m.get("type", "")) == "doubted_rumor":
			found = true
	_check("doubt remembered", found)
	gs.queue_free()


func _test_reception_memory_and_emotion() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var u: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("WAR with the Ogres!", "war", "ogres", 1.0,
		int(u.get("id", 0)))
	var mems: Array = SimMemories.new(gs).ensure(u)
	var found := false
	for m: Dictionary in mems:
		if String(m.get("type", "")) == "heard_rumor":
			found = true
	_check("knower remembers hearing", found)
	_check("war rumor scares", String((u.get("emotion", {}) as Dictionary).get("name", "")) == "scared")
	gs.queue_free()


func _test_witness_joins_rumor() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var u: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("A fire drake rampages!", "disaster", "wtest2", 0.8)
	hs._witness(u, r)
	_check("witness becomes knower", (r["knowers"] as Array).has(int(u.get("id", 0))))
	var mems: Array = SimMemories.new(gs).ensure(u)
	var found := false
	for m: Dictionary in mems:
		if String(m.get("type", "")) == "heard_rumor":
			found = true
	_check("witness remembers", found)
	gs.queue_free()


func _test_building_destroyed_rumor() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.bus.building_destroyed.emit({"type": "tavern", "name": "The Prancing Pony"})
	_check("building destroyed rumor", _rumors_of_kind(hs, "building").size() >= 1)
	gs.queue_free()


func _test_monastery_captured_rumor() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.bus.monastery_captured.emit("filthwick", "ogres")
	var found := false
	for r: Dictionary in _rumors_of_kind(hs, "war"):
		if String(r.get("text", "")).contains("ogres") \
				or String(r.get("text", "")).contains("Ogres"):
			found = true
	_check("monastery capture rumor", found)
	gs.queue_free()


func _test_trade_signed_rumor() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.bus.trade_signed.emit("gnomes", "elves")
	_check("trade signed rumor", _rumors_of_kind(hs, "news").size() >= 1)
	gs.queue_free()


func _test_tribute_refused_rumor() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.bus.tribute_refused.emit("ogres", "gnomes")
	var found := false
	for r: Dictionary in _rumors_of_kind(hs, "news"):
		if String(r.get("text", "")).contains("REFUSED"):
			found = true
	_check("tribute refused rumor", found)
	gs.queue_free()


func _test_relation_hostile_rumor() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.bus.relation_changed.emit("gnomes", "ogres", "hostile")
	var found := false
	for r: Dictionary in _rumors_of_kind(hs, "news"):
		if String(r.get("text", "")).contains("hostile"):
			found = true
	_check("hostile relation rumor", found)
	gs.queue_free()


func _test_relation_allied_no_rumor() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var before: int = hs.state["rumors"].size()
	gs.bus.relation_changed.emit("gnomes", "elves", "allied")
	_check("allied relation no rumor", hs.state["rumors"].size() == before)
	gs.queue_free()


func _test_from_dict_backfill() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	hs.from_dict({"rumors": [{"id": 1, "text": "old", "kind": "misc",
		"subject": "", "day": 1, "heat": 0.5, "knowers": [],
		"reached_ruler": false}], "seq": 2})
	var r: Dictionary = hs.state["rumors"][0]
	_check("text_orig backfilled", String(r.get("text_orig", "")) == "old")
	_check("distortions backfilled", int(r.get("distortions", -1)) == 0)
	gs.queue_free()
