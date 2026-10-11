extends SceneTree
## Cursing Gnomes — hearsay false-smear loop (Jeremy 2026-10-08).
##
## Tavern lies are the ONLY rumors seeded untrue: a citizen who dislikes
## someone sometimes invents a smear about them (truth "false", liar
## recorded as source_id). Covers:
##  - _seed_malicious_smear seeds kind "smear", truth "false", with a
##    liar who genuinely dislikes the target (motive) and player_sourced
##    false
##  - NPC-sourced smear reaction: the target is furious at the LIAR
##    ("npc_smeared_me"), never at the player
##  - routing regression: player smears still blame the player
##    ("player_smeared_me")
##  - debunk rehabilitates the target (reputation the lie took is given
##    back) + publishes the Gazette correction
##  - debunk leaves believers sheepish ("believed_a_lie" memory)
##  - verified true rumors vindicate believers ("called_it_right")
##  - FALSE_SMEAR_LINES are hate-slur clean; the pipeline never seeds a
##    slur (HARD LINE)
##  - one live lie per target (dedup on subject)
##  - from_dict backfills the false-smear source schema
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_false_smears.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class MockCourt:
	extends RefCounted
	var gs: GameState
	var stories: Array = []
	func _init(g: GameState) -> void:
		gs = g
	func publish_story(headline: String, body: String,
			kind: String = "default") -> Dictionary:
		var s := {"id": stories.size(), "headline": headline,
			"body": body, "story": body, "kind": kind,
			"day": gs.day_number}
		stories.append(s)
		gs.bus.gazette_story.emit(s)
		return s


class MockPhone:
	extends RefCounted
	var dms: Array = []
	var blocked := {}
	func npc_message(unit_id: int, text: String) -> void:
		dms.append({"unit_id": unit_id, "text": text})
	func is_blocked(unit_id: int) -> bool:
		return bool(blocked.get(unit_id, false))


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay false-smear tests ===")
	_test_false_smear_seeds_untrue()
	_test_false_smear_target_fury()
	_test_player_smear_routing_unchanged()
	_test_debunk_rehabilitates_target()
	_test_debunk_leaves_believers_sheepish()
	_test_verified_vindicates_believers()
	_test_false_smear_lines_clean()
	_test_false_smear_dedup_per_target()
	_test_from_dict_backfill_source()
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


func _new_hs(gs: GameState, phone = null) -> Array:
	var hs = load("res://scripts/sim/hearsay.gd").new(gs, phone)
	var court := MockCourt.new(gs)
	gs.court_sys = court
	return [hs, court]


func _spawn(gs: GameState, faction: String, job: String = "peasant",
		npc_name: String = "") -> Dictionary:
	var d := {"faction": faction, "alive": true, "mind": {}, "job": job}
	if npc_name != "":
		d["name"] = npc_name
	return gs.add_unit(d)


func _mem_strength(unit: Dictionary, mtype: String, subject_id: int) -> float:
	var best := 0.0
	for m: Dictionary in unit.get("memories", []):
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			best = maxf(best, float(m.get("strength", 0.0)))
	return best


## A manually-built NPC-sourced false smear (deterministic — no RNG).
func _npc_smear(gs: GameState, hs, liar: Dictionary,
		target: Dictionary) -> Dictionary:
	var tid := int(target.get("id", 0))
	var tname := SimPersonality.display_name(target)
	var lname := SimPersonality.display_name(liar)
	var lid := int(liar.get("id", 0))
	# Knower-less seed (the seed_player_smear pattern): stamp the target
	# fields before the first _on_heard so _rep_tick sees the target.
	var r: Dictionary = hs.seed_rumor(
		"They say %s cheats at dice. Loaded bones, the works." % tname,
		"smear", "smear:%d" % tid, 0.65, -1, false, "false")
	r["player_sourced"] = false
	r["source_id"] = lid
	r["source_name"] = lname
	r["target_id"] = tid
	r["target_name"] = tname
	r["target_faction"] = String(target.get("faction", ""))
	r["target_is_leader"] = false
	var hk: Array = r["knowers"]
	if not hk.has(lid):
		hk.append(lid)
	hs._on_heard(liar, r, {})
	return r


func _test_false_smear_seeds_untrue() -> void:
	seed(20261008)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	for i in 6:
		_spawn(gs, "gnomes", "peasant", "G%d" % i)
		_spawn(gs, "ogres", "peasant", "O%d" % i)
	var r: Dictionary = {}
	var ok := false
	for attempt in 40:
		if hs._seed_malicious_smear():
			ok = true
			break
	_check("a lie gets invented", ok)
	if not ok:
		gs.queue_free()
		return
	for rr: Dictionary in hs.state["rumors"]:
		if String(rr.get("kind", "")) == "smear" \
				and String(rr.get("truth", "")) == "false":
			r = rr
			break
	_check("false smear exists in the mill", not r.is_empty())
	if r.is_empty():
		gs.queue_free()
		return
	_check("not player sourced", not bool(r.get("player_sourced", true)))
	_check("liar recorded", int(r.get("source_id", 0)) > 0)
	_check("target recorded", int(r.get("target_id", 0)) > 0)
	_check("subject keys the target",
		String(r.get("subject", "")).begins_with("smear:"))
	var liar: Dictionary = gs.get_unit(int(r.get("source_id", 0)))
	var target: Dictionary = gs.get_unit(int(r.get("target_id", 0)))
	_check("liar dislikes the target (motive)",
		SimLikesDislikes.npc_stance(liar,
			{"id": int(target.get("id", 0)),
				"name": String(r.get("target_name", "")),
				"faction": String(r.get("target_faction", "")),
				"is_leader": false}, gs) <= -0.3)
	_check("heat reaches the ruler but not the press",
		float(r.get("heat", 0.0)) >= 0.6
		and float(r.get("heat", 0.0)) < 0.85)
	gs.queue_free()


func _test_false_smear_target_fury() -> void:
	seed(20261008)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var liar: Dictionary = _spawn(gs, "gnomes", "peasant", "Fibber")
	var target: Dictionary = _spawn(gs, "ogres", "peasant", "Grak")
	var tid := int(target.get("id", 0))
	var r: Dictionary = _npc_smear(gs, hs, liar, target)
	var lname := String(r.get("source_name", ""))
	hs._on_heard(target, r, {})
	_check("target remembers who lied about them",
		_mem_strength(target, "npc_smeared_me", tid) > 0.0)
	var named := false
	for m: Dictionary in target.get("memories", []):
		if String(m.get("type", "")) == "npc_smeared_me" \
				and String(m.get("subject_name", "")) == lname:
			named = true
	_check("the liar is named in the memory", named)
	_check("the player is NOT blamed",
		_mem_strength(target, "player_smeared_me", tid) == 0.0)
	gs.queue_free()


func _test_player_smear_routing_unchanged() -> void:
	seed(20261008)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var hearer: Dictionary = _spawn(gs, "gnomes", "peasant", "Mira")
	var target: Dictionary = _spawn(gs, "ogres", "peasant", "Grak")
	var tid := int(target.get("id", 0))
	var hid := int(hearer.get("id", 0))
	var r: Dictionary = hs.seed_player_smear(
		{"name": "Grak", "id": tid, "faction": "ogres",
			"is_leader": false, "key": "npc:%d" % tid,
			"insult": "idiot", "phrase": "is an idiot"},
		"Grak is an idiot", "idiot", hid)
	hs._on_heard(target, r, {})
	_check("player smear still blames the player",
		_mem_strength(target, "player_smeared_me", tid) > 0.0)
	gs.queue_free()


func _test_debunk_rehabilitates_target() -> void:
	seed(20261008)
	var gs := _new_gs()
	var mp := MockPhone.new()
	var pair: Array = _new_hs(gs, mp)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var liar: Dictionary = _spawn(gs, "gnomes", "peasant", "Fibber")
	var target: Dictionary = _spawn(gs, "ogres", "peasant", "Grak")
	var tid := int(target.get("id", 0))
	var r: Dictionary = _npc_smear(gs, hs, liar, target)
	var hearers: Array = []
	for i in 3:
		hearers.append(_spawn(gs, "gnomes", "peasant", "H%d" % i))
	var kids: Array = []
	for h: Dictionary in hearers:
		hs._on_heard(h, r, {})
		kids.append(int(h.get("id", 0)))
	r["knowers"] = kids
	# The liar heard their own lie at seed, so four believers total.
	_check("four believers tank the rep",
		is_equal_approx(hs.reputation_of(tid), 42.0))
	var res: Dictionary = hs.investigate_rumor(int(r.get("id", 0)))
	_check("false lie debunked", String(res.get("outcome", "")) == "debunked")
	_check("target's name cleared",
		is_equal_approx(hs.reputation_of(tid), 50.0))
	_check("correction ran in the Gazette", court.stories.size() == 1)
	gs.queue_free()


func _test_debunk_leaves_believers_sheepish() -> void:
	seed(20261008)
	var gs := _new_gs()
	var mp := MockPhone.new()
	var pair: Array = _new_hs(gs, mp)
	var hs = pair[0]
	var liar: Dictionary = _spawn(gs, "gnomes", "peasant", "Fibber")
	var target: Dictionary = _spawn(gs, "ogres", "peasant", "Grak")
	var r: Dictionary = _npc_smear(gs, hs, liar, target)
	var hearers: Array = []
	for i in 3:
		hearers.append(_spawn(gs, "gnomes", "peasant", "H%d" % i))
	var kids: Array = []
	for h: Dictionary in hearers:
		hs._on_heard(h, r, {})
		kids.append(int(h.get("id", 0)))
	r["knowers"] = kids
	var rid := int(r.get("id", 0))
	hs.investigate_rumor(rid)
	var sheepish := 0
	for h: Dictionary in hearers:
		if _mem_strength(h, "believed_a_lie", rid) > 0.0:
			sheepish += 1
	_check("believers remember swallowing the lie", sheepish == 3)
	gs.queue_free()


func _test_verified_vindicates_believers() -> void:
	seed(20261008)
	var gs := _new_gs()
	var mp := MockPhone.new()
	var pair: Array = _new_hs(gs, mp)
	var hs = pair[0]
	var u1: Dictionary = _spawn(gs, "gnomes")
	var u2: Dictionary = _spawn(gs, "gnomes")
	var u3: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("WAR with the Ogres! Drums beat.",
		"war", "ogres", 0.8, -1, false, "true")
	r["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0)),
		int(u3.get("id", 0))]
	var res: Dictionary = hs.investigate_rumor(int(r.get("id", 0)))
	_check("true rumor confirmed", String(res.get("outcome", "")) == "confirmed")
	var rid := int(r.get("id", 0))
	var vindicated := 0
	for u: Dictionary in [u1, u2, u3]:
		if _mem_strength(u, "called_it_right", rid) > 0.0:
			vindicated += 1
	_check("believers remember calling it right", vindicated == 3)
	gs.queue_free()


func _test_false_smear_lines_clean() -> void:
	var lines: Array = SimHearsay.FALSE_SMEAR_LINES
	_check("the lie pool is not empty", not lines.is_empty())
	var clean := true
	for line: String in lines:
		if SimHateSpeech.is_hate_slur(line):
			clean = false
	_check("no hate slur can ride the lie pipeline", clean)


func _test_false_smear_dedup_per_target() -> void:
	seed(20261008)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	for i in 6:
		_spawn(gs, "gnomes", "peasant", "G%d" % i)
		_spawn(gs, "ogres", "peasant", "O%d" % i)
	for attempt in 60:
		hs._seed_malicious_smear()
	var seen := {}
	var dupes := 0
	for rr: Dictionary in hs.state["rumors"]:
		if String(rr.get("kind", "")) != "smear":
			continue
		var subj := String(rr.get("subject", ""))
		if not subj.begins_with("smear:"):
			continue
		if seen.has(subj):
			dupes += 1
		seen[subj] = true
	_check("one live lie per target", dupes == 0)
	gs.queue_free()


func _test_from_dict_backfill_source() -> void:
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var r := {"id": 7, "text": "old lie", "text_orig": "old lie",
		"kind": "smear", "subject": "smear:3", "day": 1, "heat": 0.5,
		"knowers": [], "truth": "false"}
	hs.from_dict({"rumors": [r], "seq": 8, "last_press_day": 0,
		"npc_rep": {}, "pending_caches": [], "holders": {}})
	var back: Dictionary = (hs.state["rumors"] as Array)[0]
	_check("source_id backfilled", int(back.get("source_id", -1)) == 0)
	_check("source_name backfilled",
		String(back.get("source_name", "x")) == "")
	gs.queue_free()
