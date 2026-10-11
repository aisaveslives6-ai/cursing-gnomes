extends SceneTree
## Cursing Gnomes — hearsay belief-depth tests (Jeremy 2026-10-06).
##
## Covers the hearsay flesh-out run: belief weighs first-hand witnesses
## and teller trust (reputation), on top of heat / faction / war /
## player-source factors.
##  - witnesses boost belief (+0.06 each, capped at +0.30)
##  - Beloved tellers (+0.15) are trusted; Despised tellers (-0.15) doubted
##  - default-rep tellers change nothing (regression guard for old math)
##  - _witness tracks witnesses once, writes a witnessed_rumor memory
##  - witnesses survive save/load; old saves backfill to []
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_belief.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay-belief tests ===")
	_test_witnesses_boost_belief()
	_test_witness_bonus_capped()
	_test_beloved_teller_trusted()
	_test_despised_teller_doubted()
	_test_default_rep_neutral()
	_test_witness_no_dupe()
	_test_witness_memory()
	_test_save_roundtrip()
	_test_old_save_backfill()
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
	return gs.add_unit({"faction": faction, "alive": true})


func _belief_harness() -> Array:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	var teller: Dictionary = _spawn(gs, "gnomes")
	var hearer: Dictionary = _spawn(gs, "gnomes")
	# heat 0.5 + same-faction 0.2 = 0.7 baseline, no witnesses, rep 50.
	var r: Dictionary = hs.seed_rumor("The tavern ran out of ale.", "news",
		"btest", 0.5)
	return [gs, hs, teller, hearer, r]


func _test_witnesses_boost_belief() -> void:
	var parts: Array = _belief_harness()
	var gs: GameState = parts[0]
	var hs = parts[1]
	var r: Dictionary = parts[4]
	var base: float = hs._belief(parts[2], parts[3], r)
	_check("witness baseline 0.7", absf(base - 0.7) < 0.001)
	for i in range(3):
		hs._witness(_spawn(gs, "gnomes"), r)
	var boosted: float = hs._belief(parts[2], parts[3], r)
	_check("3 witnesses add 0.18", absf(boosted - 0.88) < 0.001)
	gs.queue_free()


func _test_witness_bonus_capped() -> void:
	var parts: Array = _belief_harness()
	var gs: GameState = parts[0]
	var hs = parts[1]
	var r: Dictionary = parts[4]
	for i in range(10):
		hs._witness(_spawn(gs, "gnomes"), r)
	var b: float = hs._belief(parts[2], parts[3], r)
	_check("10 witnesses capped at +0.30", absf(b - 1.0) < 0.001)
	gs.queue_free()


func _test_beloved_teller_trusted() -> void:
	var parts: Array = _belief_harness()
	var hs = parts[1]
	var r: Dictionary = parts[4]
	var base: float = hs._belief(parts[2], parts[3], r)
	hs._bump_npc_rep(int((parts[2] as Dictionary).get("id", 0)), 50.0)
	var loved: float = hs._belief(parts[2], parts[3], r)
	_check("beloved teller +0.15", absf(loved - (base + 0.15)) < 0.001)
	(parts[0] as GameState).queue_free()


func _test_despised_teller_doubted() -> void:
	var parts: Array = _belief_harness()
	var hs = parts[1]
	var r: Dictionary = parts[4]
	var base: float = hs._belief(parts[2], parts[3], r)
	hs._bump_npc_rep(int((parts[2] as Dictionary).get("id", 0)), -50.0)
	var hated: float = hs._belief(parts[2], parts[3], r)
	_check("despised teller -0.15", absf(hated - (base - 0.15)) < 0.001)
	(parts[0] as GameState).queue_free()


func _test_default_rep_neutral() -> void:
	# A default-rep (50) teller must score exactly like the old model —
	# the trust component is a no-op at REP_DEFAULT.
	var parts: Array = _belief_harness()
	var gs: GameState = parts[0]
	var hs = parts[1]
	var r: Dictionary = parts[4]
	var teller2: Dictionary = _spawn(gs, "gnomes")
	var b1: float = hs._belief(parts[2], parts[3], r)
	var b2: float = hs._belief(teller2, parts[3], r)
	_check("default rep teller neutral", absf(b1 - b2) < 0.0001)
	gs.queue_free()


func _test_witness_no_dupe() -> void:
	var parts: Array = _belief_harness()
	var hs = parts[1]
	var r: Dictionary = parts[4]
	var w: Dictionary = parts[2]
	hs._witness(w, r)
	hs._witness(w, r)
	_check("witness listed once", (r.get("witnesses", []) as Array).size() == 1)
	_check("knower listed once", (r["knowers"] as Array).size() == 1)
	(parts[0] as GameState).queue_free()


func _test_witness_memory() -> void:
	var parts: Array = _belief_harness()
	var gs: GameState = parts[0]
	var hs = parts[1]
	var r: Dictionary = parts[4]
	var w: Dictionary = _spawn(gs, "gnomes")
	hs._witness(w, r)
	var mems: Array = SimMemories.new(gs).ensure(w)
	var found := false
	for m: Dictionary in mems:
		if String(m.get("type", "")) == "witnessed_rumor":
			found = true
			_check("witness memory strength 0.9",
				absf(float(m.get("strength", 0.0)) - 0.9) < 0.001)
	_check("witnessed_rumor memory written", found)
	gs.queue_free()


func _test_save_roundtrip() -> void:
	var parts: Array = _belief_harness()
	var gs: GameState = parts[0]
	var hs = parts[1]
	var r: Dictionary = parts[4]
	hs._witness(_spawn(gs, "gnomes"), r)
	hs._witness(_spawn(gs, "gnomes"), r)
	var wid: int = int(((r.get("witnesses", []) as Array)[0]))
	hs.from_dict(hs.to_dict())
	var r2: Dictionary = hs._rumor_by_id(int(r.get("id", 0)))
	_check("witnesses found after reload", not r2.is_empty())
	var wits: Array = r2.get("witnesses", [])
	_check("witnesses survive save/load", wits.size() == 2)
	_check("witness ids intact", wits.has(wid))
	gs.queue_free()


func _test_old_save_backfill() -> void:
	var parts: Array = _belief_harness()
	var hs = parts[1]
	# A pre-fleshout save rumor has no "witnesses" key at all.
	var old: Dictionary = {
		"rumors": [{"id": 7, "text": "old talk", "kind": "news",
			"knowers": [], "heat": 0.4}],
		"seq": 8, "last_press_day": 0, "npc_rep": {},
		"pending_caches": [],
	}
	hs.from_dict(old)
	var r: Dictionary = hs.state["rumors"][0]
	_check("old save backfills witnesses", r.has("witnesses"))
	_check("backfilled witnesses empty",
		(r.get("witnesses", [1]) as Array).is_empty())
	# ...and belief works on the backfilled rumor.
	var b: float = hs._belief(parts[2], parts[3], r)
	_check("backfilled rumor believable", b > 0.0)
	(parts[0] as GameState).queue_free()
