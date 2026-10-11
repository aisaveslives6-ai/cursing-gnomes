extends SceneTree
## Cursing Gnomes — hearsay belief-depth tests: doubt & distortion
## (Jeremy 2026-10-07, hearsay flesh-out).
##
## The belief thread was the weakest remaining grapevine thread: the
## telephone-game distortion counter existed (capped at 3 hops) but _belief
## never read it — a thrice-mutated tale was believed exactly as strongly
## as a fresh eyewitness report. And skeptics were dead ends: _on_doubted
## remembered "doubted_rumor" and stopped, so doubt never pushed back.
## Now:
##  - each distortion hop dents belief (DISTORT_BELIEF_EACH = 0.08)
##  - doubters are RECORDED on the rumor (bounded list, deduped) and doubt
##    is contagious: each scoff dents future belief (capped at 0.20 — doubt
##    can slow a hot rumor, never kill one)
##  - proud skeptics scoff publicly ("scoffed_at_rumor" memory) instead of
##    doubting quietly
##  - slur incidents are witnessed FACT and never get doubted down — the
##    realm condemns them, it doesn't question whether they happened
##    (the IRL-slur hard line holds in the belief path too)
##  - doubters survive save/load; old saves backfill to []
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_doubt.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay doubt/distortion tests ===")
	_test_distortion_dents_belief()
	_test_doubt_dents_belief_capped()
	_test_doubters_recorded_deduped_bounded()
	_test_slur_immune_to_doubt()
	_test_proud_scoffs_loudly()
	_test_save_load_roundtrip()
	_test_backfill_old_saves()
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


func _spawn(gs: GameState, faction: String, mind: Dictionary = {}) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": mind})


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _test_distortion_dents_belief() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var teller: Dictionary = _spawn(gs, "gnomes")
	var hearer: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("The king lost a bet.", "news",
		"dtest1", 0.5)
	var fresh: float = hs._belief(teller, hearer, r)
	r["distortions"] = 3
	var stale: float = hs._belief(teller, hearer, r)
	_check("distortion dents belief", stale < fresh)
	_check("distortion dent is per-hop",
		is_equal_approx(fresh - stale, 3.0 * 0.08))
	gs.queue_free()


func _test_doubt_dents_belief_capped() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var teller: Dictionary = _spawn(gs, "gnomes")
	var hearer: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("The moon is cheese.", "news",
		"dtest2", 0.5)
	var trusted: float = hs._belief(teller, hearer, r)
	# Three doubters dent it.
	for i: int in 3:
		hs._on_doubted(_spawn(gs, "gnomes"), r, teller)
	var dented: float = hs._belief(teller, hearer, r)
	_check("doubt dents belief", dented < trusted)
	# Twenty doubters hit the cap, not the floor.
	for i: int in 20:
		hs._on_doubted(_spawn(gs, "gnomes"), r, teller)
	var swamped: float = hs._belief(teller, hearer, r)
	_check("doubt dent is capped",
		is_equal_approx(trusted - swamped, 0.20))
	_check("capped doubt never kills a warm rumor", swamped > 0.4)
	gs.queue_free()


func _test_doubters_recorded_deduped_bounded() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var teller: Dictionary = _spawn(gs, "gnomes")
	var skeptic: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("Elves knit.", "misc", "dtest3", 0.5)
	hs._on_doubted(skeptic, r, teller)
	var doubters: Array = r.get("doubters", [])
	_check("doubter recorded", doubters.has(int(skeptic.get("id", 0))))
	hs._on_doubted(skeptic, r, teller)
	_check("doubter not duplicated", doubters.size() == 1)
	for i: int in 40:
		hs._on_doubted(_spawn(gs, "gnomes"), r, teller)
	_check("doubters list bounded",
		int((r.get("doubters", []) as Array).size()) <= 24)
	gs.queue_free()


func _test_slur_immune_to_doubt() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var teller: Dictionary = _spawn(gs, "gnomes")
	var hearer: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("An incident happened.", "slur",
		"dtest4", 0.9)
	var clean: float = hs._belief(teller, hearer, r)
	# The realm condemns slur incidents; it never doubts whether they
	# happened — distortion hops and a mob of scoffers change nothing.
	r["distortions"] = 3
	for i: int in 10:
		hs._on_doubted(_spawn(gs, "gnomes"), r, teller)
	var after: float = hs._belief(teller, hearer, r)
	_check("slur belief immune to distortion and doubt",
		is_equal_approx(after, clean))
	gs.queue_free()


func _test_proud_scoffs_loudly() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var teller: Dictionary = _spawn(gs, "gnomes")
	var proud: Dictionary = _spawn(gs, "gnomes",
		{"traits": {"persona": "proud"}})
	var meek: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("Ogres read poetry.", "misc",
		"dtest5", 0.5)
	var rid := int(r.get("id", 0))
	hs._on_doubted(proud, r, teller)
	hs._on_doubted(meek, r, teller)
	_check("proud skeptic scoffs publicly",
		_recalled(proud, "scoffed_at_rumor", rid) > 0.0)
	_check("proud skeptic still counted as doubter",
		(r.get("doubters", []) as Array).has(int(proud.get("id", 0))))
	_check("unproud skeptic doubts quietly",
		_recalled(meek, "doubted_rumor", rid) > 0.0)
	_check("unproud skeptic does not scoff",
		_recalled(meek, "scoffed_at_rumor", rid) == 0.0)
	gs.queue_free()


func _test_save_load_roundtrip() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var teller: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("Doubt persists.", "news", "dtest6",
		0.5)
	var s1: Dictionary = _spawn(gs, "gnomes")
	var s2: Dictionary = _spawn(gs, "gnomes")
	hs._on_doubted(s1, r, teller)
	hs._on_doubted(s2, r, teller)
	var saved: Dictionary = hs.to_dict()
	var h2: Array = _harness()
	var hs2 = h2[2]
	hs2.from_dict(saved)
	var back: Array = []
	for r2: Dictionary in hs2.state["rumors"]:
		if String(r2.get("subject", "")) == "dtest6":
			back = r2.get("doubters", [])
	_check("doubters survive save/load",
		back.has(int(s1.get("id", 0))) and back.has(int(s2.get("id", 0))))
	gs.queue_free()
	(h2[0] as GameState).queue_free()


func _test_backfill_old_saves() -> void:
	var h: Array = _harness()
	var hs = h[2]
	var saved: Dictionary = hs.to_dict()
	for r: Dictionary in saved.get("rumors", []):
		r.erase("doubters")
	var h2: Array = _harness()
	var hs2 = h2[2]
	hs2.from_dict(saved)
	var ok := true
	for r: Dictionary in hs2.state["rumors"]:
		if not r.has("doubters"):
			ok = false
	_check("old saves backfill doubters", ok)
	(h[0] as GameState).queue_free()
	(h2[0] as GameState).queue_free()
