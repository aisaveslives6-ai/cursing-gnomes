extends SceneTree
## Cursing Gnomes — hearsay nuke-gossip tests (Jeremy 2026-10-09).
##
## Covers the hearsay flesh-out run: the sun-bomb had no voice of its own.
## A detonation rode the generic disaster path ("A nuke rampages through
## {town}!" — war-rivals LAUGHING at a sun-bomb) while its own Gazette
## story double-seeded a thin twin rumor, and a launch seeded a faceless
## thin war line. Now:
##  - detonation: rich rumor (kind "disaster", subject "nuke",
##    nuke=true, hit town + launcher named, heat 0.95, truth TRUE).
##    The Gazette's own detonation story folds into it (launcher stashed
##    from the body) instead of seeding a thin twin.
##  - launch: rich rumor (kind "war", subject "nuke_launch:<faction>",
##    nuke_launch=true, launcher named, heat 1.0, truth TRUE) instead of
##    a faceless thin war seed. A second launch refreshes, not twins.
##  - blast reaction matrix: the stricken despair in terror and awe
##    (nuke_hit_us, -12x, scared); the launcher's people rally grimly
##    (nuke_our_spear, +4x, proud); war-rivals feel DREAD not mockery
##    (nuke_dread, -4x, scared — even the enemy falls silent); everyone
##    else stands in awe (saw_sun_die, -3x, scared). Unhinged 1.5x.
##  - launch reaction matrix: the launcher's people anticipate grimly
##    (nuke_our_spear, +3x, proud); everyone else dreads the inbound
##    spear (nuke_spear_inbound, -6x, scared). Unhinged 1.5x.
##  - belief: nukes join the witnessed-fact club (slur/famine) — doubt
##    and distortion dents never apply. The sky burned; the tremor was
##    felt.
##  - spread zeal: survivors push the horror urgently, the launcher's
##    people boast, everyone retells the awe; launch dread is shouted.
##  - cross-border: a blast crosses every border (hit faction hears it
##    fast, 0.4; survivors' tale rides the open trickle, 0.25); a launch
##    rides the open trickle at 0.3 — every court felt the tremor.
##  - witnesses: survivors of the hit faction near the blast join as
##    witnesses (the flash was visible realm-wide).
##  - Squabble posts for blasts and launches (awe/horror, never tavern
##    comedy about a sun-bomb).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_nuke.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay nuke-gossip tests ===")
	_test_detonation_seeds_rich_rumor()
	_test_detonation_story_folds_no_twin()
	_test_launcher_stashed_and_cleared()
	_test_blast_without_story_still_rich()
	_test_victim_terror()
	_test_launcher_rallies()
	_test_rival_dreads_not_mocked()
	_test_neutral_awed()
	_test_unhinged_amplified()
	_test_belief_doubt_proof()
	_test_launch_seeds_rich_rumor()
	_test_launch_no_thin_twin()
	_test_launch_second_refreshes()
	_test_launch_reactions()
	_test_spread_motivation_blast()
	_test_spread_motivation_launch()
	_test_cross_target_blast()
	_test_cross_target_launch()
	_test_witnesses()
	_test_memory_types_registered()
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


func _spawn(gs: GameState, faction: String, unhinged: bool = false,
		pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var mind: Dictionary = {}
	if unhinged:
		mind = {"traits": {"unhinged": 1.0}}
	var d := {"faction": faction, "alive": true, "mind": mind}
	if pos != Vector2.ZERO:
		d["position"] = pos
	return gs.add_unit(d)


func _add_town(gs: GameState, tid: int, faction: String, pos: Vector2,
		name: String) -> void:
	gs.towns[tid] = {"id": tid, "faction": faction, "position": pos,
		"name": name}


func _set_relation(gs: GameState, a: String, b: String, st: String) -> void:
	var rec: Dictionary = gs.diplomacy._pair(a, b)
	if not rec.is_empty():
		rec["state"] = st


func _story(gs: GameState, headline: String, body: String) -> void:
	gs.bus.gazette_story.emit({"day": 1, "headline": headline,
		"body": body})


func _nuke_rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "disaster" \
				and String(r.get("subject", "")) == "nuke":
			return r
	return {}


func _launch_rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if bool(r.get("nuke_launch", false)):
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


func _detonate(gs: GameState, with_story: bool = true) -> void:
	if with_story:
		_story(gs, "NUCLEAR DETONATION — fallout incoming",
			"A second sun rose over the realm and died screaming. " \
			+ "The crater glows green; nothing will grow there for a " \
			+ "generation. Fired by Gnomes.")
	gs.bus.disaster_spawned.emit("nuke", Vector2(5100, 5050))


func _test_detonation_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_detonate(gs)
	var r := _nuke_rumor(hs)
	_check("detonation seeds a rich rumor", not r.is_empty())
	if r.is_empty():
		return
	_check("nuke flag stamped", bool(r.get("nuke", false)))
	_check("hit_faction recorded",
		String(r.get("hit_faction", "")) == "ogres")
	_check("hit_town recorded",
		String(r.get("hit_town", "")) == "Gristleburg")
	_check("rumor text names the town",
		String(r.get("text", "")).find("Gristleburg") >= 0)
	_check("detonation heat 0.95",
		absf(float(r.get("heat", 0.0)) - 0.95) < 0.001)
	_check("detonation is witnessed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)


func _test_detonation_story_folds_no_twin() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_detonate(gs)
	var count := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "disaster":
			count += 1
	_check("detonation seeds exactly one disaster rumor", count == 1)
	var r := _nuke_rumor(hs)
	_check("launcher stashed from the story",
		String(r.get("nuke_launcher", "")) == "gnomes")


func _test_launcher_stashed_and_cleared() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_detonate(gs)  # stashes "gnomes", then clears
	_check("stash cleared after detonation",
		String(hs._pending_nuke_launcher) == "")
	# A second blast with no story: launcher unknown, no stale stash.
	gs.bus.disaster_spawned.emit("nuke", Vector2(5100, 5050))
	var r := _nuke_rumor(hs)
	_check("second blast has no stale launcher",
		String(r.get("nuke_launcher", "")) == "")


func _test_blast_without_story_still_rich() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_detonate(gs, false)
	var r := _nuke_rumor(hs)
	_check("story-less blast still seeds rich rumor", not r.is_empty())
	_check("story-less blast has no launcher",
		String(r.get("nuke_launcher", "")) == "")
	_check("story-less blast still witnessed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)


func _test_victim_terror() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	var u: Dictionary = _spawn(gs, "ogres")
	var uid := int(u.get("id", 0))
	var conv = phone.get("conversation")
	var before: float = conv.ruler_mood(uid)
	_detonate(gs)
	var r := _nuke_rumor(hs)
	hs._on_heard(u, r, {})
	_check("victim remembers the sky catching fire",
		_recalled(u, "nuke_hit_us", int(r.get("id", 0))) > 0.0)
	_check("victim mood tanks",
		conv.ruler_mood(uid) < before - 11.0)
	_check("victim is scared", _emotion(u) == "scared")


func _test_launcher_rallies() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	var u: Dictionary = _spawn(gs, "gnomes")
	var uid := int(u.get("id", 0))
	var conv = phone.get("conversation")
	var before: float = conv.ruler_mood(uid)
	_detonate(gs)  # launcher = gnomes
	var r := _nuke_rumor(hs)
	hs._on_heard(u, r, {})
	_check("launcher remembers their spear flying",
		_recalled(u, "nuke_our_spear", int(r.get("id", 0))) > 0.0)
	_check("launcher mood rises", conv.ruler_mood(uid) > before + 3.0)
	_check("launcher is proud", _emotion(u) == "proud")


func _test_rival_dreads_not_mocked() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_set_relation(gs, "elves", "ogres", "war")
	var u: Dictionary = _spawn(gs, "elves")
	var uid := int(u.get("id", 0))
	var conv = phone.get("conversation")
	var before: float = conv.ruler_mood(uid)
	_detonate(gs)
	var r := _nuke_rumor(hs)
	hs._on_heard(u, r, {})
	_check("war-rival remembers dread, not laughter",
		_recalled(u, "nuke_dread", int(r.get("id", 0))) > 0.0)
	_check("war-rival gets no rival_disaster memory",
		_recalled(u, "rival_disaster", int(r.get("id", 0))) == 0.0)
	_check("war-rival mood falls (dread, not glee)",
		conv.ruler_mood(uid) < before - 3.0)
	_check("war-rival is scared, not happy", _emotion(u) == "scared")


func _test_neutral_awed() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	var u: Dictionary = _spawn(gs, "humans")
	var uid := int(u.get("id", 0))
	var conv = phone.get("conversation")
	var before: float = conv.ruler_mood(uid)
	_detonate(gs)
	var r := _nuke_rumor(hs)
	hs._on_heard(u, r, {})
	_check("neutral remembers watching the sun die",
		_recalled(u, "saw_sun_die", int(r.get("id", 0))) > 0.0)
	_check("neutral mood dips", conv.ruler_mood(uid) < before - 2.0)
	_check("neutral is scared", _emotion(u) == "scared")


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_detonate(gs)
	var r := _nuke_rumor(hs)
	var conv = phone.get("conversation")
	var calm: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", true)
	var calm_before: float = conv.ruler_mood(int(calm.get("id", 0)))
	var wild_before: float = conv.ruler_mood(int(wild.get("id", 0)))
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	var calm_delta: float = calm_before - conv.ruler_mood(int(calm.get("id", 0)))
	var wild_delta: float = wild_before - conv.ruler_mood(int(wild.get("id", 0)))
	_check("unhinged victim feels it 1.5x",
		absf(wild_delta - 1.5 * calm_delta) < 0.05)


func _test_belief_doubt_proof() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_detonate(gs, false)
	var r := _nuke_rumor(hs)
	var hearer: Dictionary = _spawn(gs, "ogres")
	var clean: float = hs._belief({}, hearer, r)
	r["distortions"] = 3
	r["doubters"] = [111, 222, 333]
	var dented: float = hs._belief({}, hearer, r)
	_check("doubt/distortion dents never touch a nuke",
		absf(clean - dented) < 0.0001)


func _test_launch_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_story(gs, "Gnomes launches a nuclear missile",
		"A bright spear climbs from a Gnomes silo and arcs away over " \
		+ "the horizon. Every court in the realm felt the ground " \
		+ "tremble at ignition.")
	var r := _launch_rumor(hs)
	_check("launch seeds a rich rumor", not r.is_empty())
	if r.is_empty():
		return
	_check("launch rumor subject names the launcher",
		String(r.get("subject", "")) == "nuke_launch:gnomes")
	_check("nuke_launch flag stamped", bool(r.get("nuke_launch", false)))
	_check("launch launcher recorded",
		String(r.get("nuke_launcher", "")) == "gnomes")
	_check("launch heat 1.0",
		absf(float(r.get("heat", 0.0)) - 1.0) < 0.001)
	_check("launch is witnessed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("launch text names the launcher",
		String(r.get("text", "")).find("Gnomes") >= 0)


func _test_launch_no_thin_twin() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_story(gs, "Gnomes launches a nuclear missile",
		"A bright spear climbs from a Gnomes silo.")
	var count := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "war":
			count += 1
	_check("launch seeds exactly one war rumor", count == 1)


func _test_launch_second_refreshes() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_story(gs, "Gnomes launches a nuclear missile", "A bright spear climbs.")
	_story(gs, "Gnomes launches a nuclear missile", "A bright spear climbs.")
	var count := 0
	for r: Dictionary in hs.state["rumors"]:
		if bool(r.get("nuke_launch", false)):
			count += 1
	_check("second launch refreshes, not twins", count == 1)


func _test_launch_reactions() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_story(gs, "Gnomes launches a nuclear missile", "A bright spear climbs.")
	var r := _launch_rumor(hs)
	var conv = phone.get("conversation")
	var looser: Dictionary = _spawn(gs, "gnomes")
	var looser_id := int(looser.get("id", 0))
	var looser_before: float = conv.ruler_mood(looser_id)
	var other: Dictionary = _spawn(gs, "elves")
	var other_id := int(other.get("id", 0))
	var other_before: float = conv.ruler_mood(other_id)
	hs._on_heard(looser, r, {})
	hs._on_heard(other, r, {})
	_check("launcher anticipates grimly",
		_recalled(looser, "nuke_our_spear", int(r.get("id", 0))) > 0.0)
	_check("launcher mood rises",
		conv.ruler_mood(looser_id) > looser_before + 2.0)
	_check("launcher is proud", _emotion(looser) == "proud")
	_check("everyone else dreads the inbound spear",
		_recalled(other, "nuke_spear_inbound", int(r.get("id", 0))) > 0.0)
	_check("outsider mood falls",
		conv.ruler_mood(other_id) < other_before - 5.0)
	_check("outsider is scared", _emotion(other) == "scared")


func _test_spread_motivation_blast() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_detonate(gs)
	var r := _nuke_rumor(hs)
	var victim: Dictionary = _spawn(gs, "ogres")
	var boaster: Dictionary = _spawn(gs, "gnomes")
	var third: Dictionary = _spawn(gs, "humans")
	var mv: Dictionary = hs._spread_motivation(victim, r)
	var mb: Dictionary = hs._spread_motivation(boaster, r)
	var mt: Dictionary = hs._spread_motivation(third, r)
	_check("stricken spread the horror urgently",
		int(mv.get("cap_delta", 0)) == 2 \
		and absf(float(mv.get("heat_delta", 0.0)) - 0.1) < 0.001)
	_check("launcher boasts the spear",
		int(mb.get("cap_delta", 0)) == 1 \
		and absf(float(mb.get("heat_delta", 0.0)) - 0.1) < 0.001)
	_check("third parties retell the awe",
		int(mt.get("cap_delta", 0)) == 1 \
		and absf(float(mt.get("heat_delta", 0.0)) - 0.05) < 0.001)


func _test_spread_motivation_launch() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_story(gs, "Gnomes launches a nuclear missile", "A bright spear climbs.")
	var r := _launch_rumor(hs)
	var looser: Dictionary = _spawn(gs, "gnomes")
	var other: Dictionary = _spawn(gs, "elves")
	var ml: Dictionary = hs._spread_motivation(looser, r)
	var mo: Dictionary = hs._spread_motivation(other, r)
	_check("launcher shouts the spear's flight",
		int(ml.get("cap_delta", 0)) == 2 \
		and absf(float(ml.get("heat_delta", 0.0)) - 0.1) < 0.001)
	_check("everyone warns their neighbors",
		int(mo.get("cap_delta", 0)) == 1 \
		and absf(float(mo.get("heat_delta", 0.0)) - 0.1) < 0.001)


func _test_cross_target_blast() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_detonate(gs)
	var r := _nuke_rumor(hs)
	var outsider: Dictionary = _spawn(gs, "elves")
	var route: Dictionary = hs._cross_target(outsider, r)
	_check("blast reaches the stricken faction fast",
		String(route.get("faction", "")) == "ogres" \
		and absf(float(route.get("chance", 0.0)) - 0.4) < 0.001)
	var survivor: Dictionary = _spawn(gs, "ogres")
	var route2: Dictionary = hs._cross_target(survivor, r)
	_check("survivors' tale rides the open trickle",
		String(route2.get("faction", "")) != "" \
		and String(route2.get("faction", "")) != "ogres" \
		and absf(float(route2.get("chance", 0.0)) - 0.25) < 0.001)


func _test_cross_target_launch() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_story(gs, "Gnomes launches a nuclear missile", "A bright spear climbs.")
	var r := _launch_rumor(hs)
	var teller: Dictionary = _spawn(gs, "elves")
	var route: Dictionary = hs._cross_target(teller, r)
	_check("launch dread crosses every border",
		String(route.get("faction", "")) != "" \
		and absf(float(route.get("chance", 0.0)) - 0.3) < 0.001)


func _test_witnesses() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	var near: Dictionary = _spawn(gs, "ogres", false, Vector2(5100, 5050))
	var far: Dictionary = _spawn(gs, "ogres", false, Vector2(50000, 50000))
	var gnome: Dictionary = _spawn(gs, "gnomes", false, Vector2(5100, 5050))
	_detonate(gs, false)
	var r := _nuke_rumor(hs)
	var wits: Array = r.get("witnesses", [])
	_check("nearby survivor of the hit faction witnesses",
		wits.has(int(near.get("id", 0))))
	_check("distant citizen of the hit faction does not",
		not wits.has(int(far.get("id", 0))))
	_check("other factions are not blast witnesses",
		not wits.has(int(gnome.get("id", 0))))


func _test_memory_types_registered() -> void:
	for t: String in ["nuke_hit_us", "nuke_our_spear", "nuke_dread",
			"saw_sun_die", "nuke_spear_inbound"]:
		_check("memory type registered: " + t,
			t in SimMemories.TYPES)


func _test_save_load_roundtrip() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_detonate(gs)
	var d: Dictionary = hs.to_dict()
	var h2: Array = _harness()
	var hs2 = h2[2]
	hs2.from_dict(d)
	var r2: Dictionary = {}
	for r: Dictionary in hs2.state["rumors"]:
		if String(r.get("kind", "")) == "disaster" \
				and String(r.get("subject", "")) == "nuke":
			r2 = r
	_check("nuke rumor survives save/load", not r2.is_empty())
	if r2.is_empty():
		return
	_check("nuke flag survives", bool(r2.get("nuke", false)))
	_check("launcher survives",
		String(r2.get("nuke_launcher", "")) == "gnomes")
	_check("hit faction survives",
		String(r2.get("hit_faction", "")) == "ogres")
