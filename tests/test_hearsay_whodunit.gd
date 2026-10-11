extends SceneTree
## Cursing Gnomes — hearsay who-killed-whom tests (Jeremy 2026-10-08).
##
## Covers the hearsay flesh-out run: bus.unit_killed wiring. The mill used
## to hear unit_died (obituaries for notables only) but never learned WHO
## did the killing — assassinations and battlefield slayings with a named
## killer faction were a deaf thread. Now:
##  - cross-faction killings seed whodunit rumors (truth TRUE) naming the
##    killer faction; a notable's obituary is UPGRADED in place (one
##    developing story, not two rumors)
##  - peacetime slayings are scandals: hotter heat, killer-faction
##    standing dented, press-eligible front-page material
##  - wartime soldier-vs-soldier kills are skipped (war drums cover them);
##    same-faction and unknown-killer kills are skipped
##  - the kill reaction matrix: victim's kin grieve in war / rage in
##    peace; killer's kin boast in war / dread in peace (unhinged brag);
##    third parties are shocked by peacetime murder (HTML -6 parity)
##  - spread zeal and cross-border routing follow the two sides
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_whodunit.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay who-killed-whom tests ===")
	_test_wartime_notable_kill_upgrades_obituary()
	_test_peacetime_civilian_kill_seeds_scandal()
	_test_wartime_soldier_kill_no_rumor()
	_test_same_faction_kill_no_rumor()
	_test_unknown_killer_no_rumor()
	_test_victim_kin_peacetime_outraged()
	_test_victim_kin_wartime_grieves()
	_test_killer_kin_wartime_proud()
	_test_killer_kin_peacetime_dreads()
	_test_unhinged_killer_kin_brags_in_peace()
	_test_third_party_peacetime_shocked()
	_test_unhinged_amplified()
	_test_spread_motivation_sides()
	_test_cross_target_routes_sides()
	_test_peace_rep_dent()
	_test_press_eligible_hot_assassination()
	_test_single_rumor_no_duplicate()
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


func _spawn(gs: GameState, faction: String, unhinged: bool = false,
		notable: bool = false, job: String = "") -> Dictionary:
	var mind: Dictionary = {}
	if unhinged:
		mind["traits"] = {"unhinged": 1.0}
	if notable:
		mind["gov_role"] = "treasury_advisor"
	var d: Dictionary = {"faction": faction, "alive": true, "mind": mind}
	if job != "":
		d["job"] = job
	return gs.add_unit(d)


func _kill_rumors(hs) -> Array:
	var out: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "kill":
			out.append(r)
	return out


func _rumor_for_victim(hs, vid: int) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("subject", "")) == "kill:%d" % vid \
				or String(r.get("subject", "")) == "death:%d" % vid:
			return r
	return {}


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


## Drive the full production path: kill_unit emits unit_died, then the
## combat/crime systems emit unit_killed with the killer faction.
func _slay(gs: GameState, vid: int, kfaction: String) -> void:
	gs.kill_unit(vid)
	gs.bus.unit_killed.emit(vid, kfaction)


func _test_wartime_notable_kill_upgrades_obituary() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var notable: Dictionary = _spawn(gs, "ogres", false, true)
	var vid := int(notable.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	_check("notable wartime kill seeds a rumor", not r.is_empty())
	_check("upgraded obituary keeps death subject (no duplicate)",
		String(r.get("subject", "")) == "death:%d" % vid)
	_check("killer faction recorded", String(r.get("killer_faction", "")) == "elves")
	_check("victim faction recorded", String(r.get("victim_faction", "")) == "ogres")
	_check("victim id recorded", int(r.get("victim_id", 0)) == vid)
	_check("victim notable flagged", bool(r.get("victim_notable", false)))
	_check("truth is true (sim saw it)", String(r.get("truth", "")) == "true")
	_check("text names the killer faction",
		String(r.get("text", "")).find("Elves") >= 0)


func _test_peacetime_civilian_kill_seeds_scandal() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var civ: Dictionary = _spawn(gs, "ogres")
	var vid := int(civ.get("id", 0))
	# A second ogre must live to find the body (first knower).
	_spawn(gs, "ogres")
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	_check("peacetime civilian kill seeds kill rumor", not r.is_empty() \
		and String(r.get("kind", "")) == "kill")
	_check("kill subject is kill:<id>",
		String(r.get("subject", "")) == "kill:%d" % vid)
	_check("peacetime slaying is scandal-hot", float(r.get("heat", 0.0)) >= 0.85)
	_check("first knower is victim-kin (body-finders)",
		not (r.get("knowers", []) as Array).is_empty())


func _test_wartime_soldier_kill_no_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var soldier: Dictionary = _spawn(gs, "ogres", false, false, "soldier")
	var vid := int(soldier.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	_check("wartime soldier-vs-soldier seeds nothing", r.is_empty())


func _test_same_faction_kill_no_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var u: Dictionary = _spawn(gs, "ogres")
	var vid := int(u.get("id", 0))
	_slay(gs, vid, "ogres")
	_check("same-faction kill seeds nothing",
		_rumor_for_victim(hs, vid).is_empty())


func _test_unknown_killer_no_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var u: Dictionary = _spawn(gs, "ogres")
	var vid := int(u.get("id", 0))
	_slay(gs, vid, "")
	_check("unknown-killer kill seeds nothing",
		_rumor_for_victim(hs, vid).is_empty())


func _test_victim_kin_peacetime_outraged() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	var kin: Dictionary = _spawn(gs, "ogres")
	var kid := int(kin.get("id", 0))
	var mood_before: float = conv.ruler_mood(kid)
	hs._on_heard(kin, r, {})
	_check("kin remembers kin_slain_by (killer faction named)",
		_recalled(kin, "kin_slain_by", int(r.get("id", 0))) > 0.0)
	_check("kin mood drops hard in peace", conv.ruler_mood(kid) < mood_before)
	# "insulted" event maps to the "angry" emotion (outrage, not grief).
	_check("kin is angry (outrage, not just grief)", _emotion(kin) == "angry")


func _test_victim_kin_wartime_grieves() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	var kin: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(kin, r, {})
	# "friend_died" event maps to the "sad" emotion.
	_check("kin grieves the fallen in war", _emotion(kin) == "sad")
	_check("kin still names the killer faction",
		_recalled(kin, "kin_slain_by", int(r.get("id", 0))) > 0.0)


func _test_killer_kin_wartime_proud() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	var kin: Dictionary = _spawn(gs, "elves")
	var kid := int(kin.get("id", 0))
	var mood_before: float = conv.ruler_mood(kid)
	hs._on_heard(kin, r, {})
	var _rb: float = _recalled(kin, "our_blades_slew", int(r.get("id", 0)))
	_check("killer kin remembers our_blades_slew", _rb > 0.0)
	# "victory" event maps to the "proud" emotion.
	_check("killer kin proud in war", _emotion(kin) == "proud")
	_check("killer kin mood rises in war", conv.ruler_mood(kid) > mood_before)


func _test_killer_kin_peacetime_dreads() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	var kin: Dictionary = _spawn(gs, "elves")
	hs._on_heard(kin, r, {})
	# "disaster" event maps to the "scared" emotion (dread).
	_check("killer kin dreads the peacetime murder", _emotion(kin) == "scared")


func _test_unhinged_killer_kin_brags_in_peace() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	var wild: Dictionary = _spawn(gs, "elves", true)
	hs._on_heard(wild, r, {})
	# "praised" event maps to the "proud" emotion.
	_check("unhinged killer kin brags about the murder", _emotion(wild) == "proud")


func _test_third_party_peacetime_shocked() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	var third: Dictionary = _spawn(gs, "gnomes")
	var tid := int(third.get("id", 0))
	var mood_before: float = conv.ruler_mood(tid)
	hs._on_heard(third, r, {})
	_check("third party remembers the assassination",
		_recalled(third, "heard_assassination", int(r.get("id", 0))) > 0.0)
	# "disaster" event maps to the "scared" emotion.
	_check("third party shocked (scared)", _emotion(third) == "scared")
	_check("third party mood drops (HTML -6 parity)",
		conv.ruler_mood(tid) < mood_before)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	var calm: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", true)
	var cid := int(calm.get("id", 0))
	var wid := int(wild.get("id", 0))
	var calm_before: float = conv.ruler_mood(cid)
	var wild_before: float = conv.ruler_mood(wid)
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	_check("unhinged kin feels the outrage harder",
		(wild_before - conv.ruler_mood(wid)) > (calm_before - conv.ruler_mood(cid)))


func _test_spread_motivation_sides() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# Peacetime rumor.
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	var vkin: Dictionary = _spawn(gs, "ogres")
	var kkin: Dictionary = _spawn(gs, "elves")
	var mv: Dictionary = hs._spread_motivation(vkin, r)
	_check("victim kin pushes the outrage",
		int(mv.get("cap_delta", 0)) == 1)
	_check("killer kin buries the peacetime shame",
		int(hs._spread_motivation(kkin, r).get("cap_delta", 9)) == -1)
	# Wartime rumor: killer kin boasts.
	gs.diplomacy.declare_war("elves", "humans", "test")
	var wv: Dictionary = _spawn(gs, "humans")
	var wvid := int(wv.get("id", 0))
	_slay(gs, wvid, "elves")
	var wr: Dictionary = _rumor_for_victim(hs, wvid)
	var wkkin: Dictionary = _spawn(gs, "elves")
	_check("killer kin boasts in war",
		int(hs._spread_motivation(wkkin, wr).get("cap_delta", 9)) == 1)


func _test_cross_target_routes_sides() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	var teller: Dictionary = _spawn(gs, "elves")
	var tgt: Dictionary = hs._cross_target(teller, r)
	_check("killer-side teller carries it to the victim faction",
		String(tgt.get("faction", "")) == "ogres" \
		and float(tgt.get("chance", 0.0)) > 0.0)
	var vteller: Dictionary = _spawn(gs, "ogres")
	var tgt2: Dictionary = hs._cross_target(vteller, r)
	_check("victim-side teller carries it to the killer faction",
		String(tgt2.get("faction", "")) == "elves")


func _test_peace_rep_dent() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var before: float = gs.diplomacy.reputation_of("elves")
	var victim: Dictionary = _spawn(gs, "ogres")
	_slay(gs, int(victim.get("id", 0)), "elves")
	_check("peacetime murder dents killer faction standing",
		gs.diplomacy.reputation_of("elves") < before)


func _test_press_eligible_hot_assassination() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var notable: Dictionary = _spawn(gs, "ogres", false, true)
	var vid := int(notable.get("id", 0))
	# A second ogre must live to carry the tale (press needs a knower).
	_spawn(gs, "ogres")
	_slay(gs, vid, "elves")
	var r: Dictionary = _rumor_for_victim(hs, vid)
	_check("hot peacetime assassination is press-eligible",
		hs._press_eligible(r))
	_check("peacetime notable slaying hits front-page heat",
		float(r.get("heat", 0.0)) >= 0.9)


func _test_single_rumor_no_duplicate() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var notable: Dictionary = _spawn(gs, "ogres", false, true)
	var vid := int(notable.get("id", 0))
	_slay(gs, vid, "elves")
	var count := 0
	for r: Dictionary in hs.state["rumors"]:
		var subj := String(r.get("subject", ""))
		if subj == "kill:%d" % vid or subj == "death:%d" % vid:
			count += 1
	_check("one developing story, not two rumors", count == 1)
