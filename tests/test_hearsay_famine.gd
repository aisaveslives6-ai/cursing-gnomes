extends SceneTree
## Cursing Gnomes — hearsay famine-gossip tests (Jeremy 2026-10-09).
##
## Covers the hearsay flesh-out run: the AI director has declared food
## emergencies since 2026-10-05 (workers yanked onto foraging, farms
## rushed, Gazette "FAMINE!" stories) and the rumor mill NEVER noticed —
## hunger was a deaf thread. Now:
##  - _famine_tick reads the granary ledgers each day (per-capita food
##    against the director's own 3.0 / 1.0 thresholds) and seeds RICH
##    named-faction famine rumors: shortage (0.7) or critical (0.9,
##    press-eligible, reaches the ruler) — truth TRUE
##  - the starving hear it first AS WITNESSES (empty bellies testify)
##  - repeat days refresh, not duplicate; escalation rewrites the claim
##    (shortage -> critical and back), newest news wins
##  - recovery seeds one relief rumor ("they eat again"); the live
##    famine rumor keeps its natural decay
##  - the director's own Gazette alarms ("FAMINE!" / "FOOD SHORTAGE")
##    route into the rich rumor via _on_story (faction reverse-mapped
##    from the body) instead of thin disaster seeds
##  - reaction matrix: the starving despair (starving_famine /
##    hungry_famine, sad), war-rivals cackle (mocked_famine, mocked),
##    everyone else grieves (heard_famine, sad); relief is celebrated
##    (famine_relieved, helped)
##  - belief: famine is witnessed fact — the starving believe at +0.25,
##    and doubt/distortion dents never apply (the slur club)
##  - spread zeal: the starving spread urgently, rivals mock-gossip,
##    allies bury a friend's shame
##  - cross-border: hunger is schadenfreude fuel — foes of the starving
##    hear it fast (0.35), allies with grief
##  - Squabble posts: shortage lines, critical lines, relief lines
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_famine.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay famine-gossip tests ===")
	_test_shortage_seeds_rich_rumor()
	_test_critical_seeds_hot_rumor()
	_test_fed_faction_no_rumor()
	_test_faction_without_units_no_rumor()
	_test_repeat_day_refreshes_not_duplicates()
	_test_escalation_rewrites_claim()
	_test_deescalation_rewrites_claim()
	_test_relief_when_fed()
	_test_first_hearers_are_witnesses()
	_test_starving_despair()
	_test_shortage_worry()
	_test_rival_cackles()
	_test_neutral_grieves()
	_test_relief_celebrated()
	_test_unhinged_amplified()
	_test_belief_hunger_bonus()
	_test_belief_doubt_proof()
	_test_spread_motivation()
	_test_cross_target_routes_to_rival()
	_test_gazette_famine_story_routes_to_rich_rumor()
	_test_gazette_shortage_story_not_critical()
	_test_memory_types_registered()
	_test_heat_bars()
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


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _starve(gs: GameState, faction: String) -> void:
	gs.resources.add_resource(faction, "food",
		-gs.resources.get_amount(faction, "food"), true)


func _set_food(gs: GameState, faction: String, amt: float) -> void:
	_starve(gs, faction)
	gs.resources.add_resource(faction, "food", amt, true)


func _story(gs: GameState, headline: String, body: String) -> void:
	gs.bus.gazette_story.emit({
		"day": 1,
		"headline": headline,
		"body": body,
	})


func _famine_rumors(hs) -> Array:
	var out: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "famine" \
				and String(r.get("famine_faction", "")) != "" \
				and not bool(r.get("relief", false)):
			out.append(r)
	return out


func _relief_rumors(hs) -> Array:
	var out: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "famine" \
				and bool(r.get("relief", false)):
			out.append(r)
	return out


func _test_shortage_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_spawn(gs, "gnomes")
	_set_food(gs, "gnomes", 5.0)  # 2.5/head: shortage, not critical
	hs._famine_tick()
	var rs := _famine_rumors(hs)
	_check("shortage seeds exactly one rumor", rs.size() == 1)
	if rs.is_empty():
		return
	var r: Dictionary = rs[0]
	_check("shortage rumor names the faction",
		String(r.get("famine_faction", "")) == "gnomes")
	_check("shortage rumor not critical",
		not bool(r.get("famine_critical", false)))
	_check("shortage rumor heat 0.7",
		absf(float(r.get("heat", 0.0)) - 0.7) < 0.001)
	_check("shortage rumor is witnessed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("shortage rumor subject dedups",
		String(r.get("subject", "")) == "famine:gnomes")


func _test_critical_seeds_hot_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_starve(gs, "gnomes")
	hs._famine_tick()
	var rs := _famine_rumors(hs)
	_check("critical seeds exactly one rumor", rs.size() == 1)
	if rs.is_empty():
		return
	var r: Dictionary = rs[0]
	_check("critical rumor flagged", bool(r.get("famine_critical", false)))
	_check("critical rumor heat 0.9",
		absf(float(r.get("heat", 0.0)) - 0.9) < 0.001)
	_check("critical text names the famine",
		String(r.get("text", "")).contains("FAMINE"))


func _test_fed_faction_no_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	# Bare-setup ledgers start at zero — feed them like the real
	# world's stock buildings do, far above the 3.0/head bar.
	_set_food(gs, "gnomes", 500.0)
	hs._famine_tick()
	_check("fed faction seeds no famine rumor", _famine_rumors(hs).is_empty())


func _test_faction_without_units_no_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_starve(gs, "gnomes")
	_starve(gs, "elves")  # no elf units — no elf famine rumor
	hs._famine_tick()
	var rs := _famine_rumors(hs)
	var elf_rs := rs.filter(func(r: Dictionary) -> bool:
		return String(r.get("famine_faction", "")) == "elves")
	_check("faction with no units seeds no rumor", elf_rs.is_empty())
	_check("starving faction with units seeds one", rs.size() == 1)


func _test_repeat_day_refreshes_not_duplicates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_starve(gs, "gnomes")
	hs._famine_tick()
	hs._famine_tick()
	hs._famine_tick()
	_check("three hungry days, one rumor",
		_famine_rumors(hs).size() == 1)


func _test_escalation_rewrites_claim() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_spawn(gs, "gnomes")
	_set_food(gs, "gnomes", 5.0)
	hs._famine_tick()
	_starve(gs, "gnomes")
	hs._famine_tick()
	var rs := _famine_rumors(hs)
	_check("escalation keeps one rumor", rs.size() == 1)
	if rs.is_empty():
		return
	_check("escalation flips critical flag",
		bool(rs[0].get("famine_critical", false)))
	_check("escalation rewrites the claim",
		String(rs[0].get("text", "")).contains("FAMINE"))
	_check("escalation runs hotter",
		absf(float(rs[0].get("heat", 0.0)) - 0.9) < 0.001)


func _test_deescalation_rewrites_claim() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_spawn(gs, "gnomes")
	_starve(gs, "gnomes")
	hs._famine_tick()
	_set_food(gs, "gnomes", 5.0)
	hs._famine_tick()
	var rs := _famine_rumors(hs)
	_check("de-escalation keeps one rumor", rs.size() == 1)
	if rs.is_empty():
		return
	_check("de-escalation clears critical flag",
		not bool(rs[0].get("famine_critical", false)))
	_check("de-escalation rewrites the claim",
		String(rs[0].get("text", "")).contains("granaries"))


func _test_relief_when_fed() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_starve(gs, "gnomes")
	hs._famine_tick()
	_check("famine rumor live before feeding",
		_famine_rumors(hs).size() == 1)
	_set_food(gs, "gnomes", 500.0)
	hs._famine_tick()
	var rel := _relief_rumors(hs)
	_check("recovery seeds one relief rumor", rel.size() == 1)
	if rel.is_empty():
		return
	_check("relief rumor names the faction",
		String(rel[0].get("famine_faction", "")) == "gnomes")
	_check("relief rumor flagged", bool(rel[0].get("relief", false)))
	_check("relief rumor heat 0.5",
		absf(float(rel[0].get("heat", 0.0)) - 0.5) < 0.001)
	_check("relief rumor subject dedups",
		String(rel[0].get("subject", "")) == "famine_relief:gnomes")


func _test_first_hearers_are_witnesses() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_spawn(gs, "gnomes")
	_spawn(gs, "elves")
	_set_food(gs, "elves", 500.0)  # only the gnomes starve
	_starve(gs, "gnomes")
	hs._famine_tick()
	var rs := _famine_rumors(hs).filter(func(r: Dictionary) -> bool:
		return String(r.get("famine_faction", "")) == "gnomes")
	_check("rumor seeded", rs.size() == 1)
	if rs.is_empty():
		return
	var wits: Array = rs[0].get("witnesses", [])
	_check("starving citizens become witnesses", wits.size() >= 1)
	var all_gnome := true
	for wid in wits:
		var w: Dictionary = gs.get_unit(int(wid))
		if String(w.get("faction", "")) != "gnomes":
			all_gnome = false
	_check("witnesses are the starving faction's own", all_gnome)


func _rich_rumor(hs, gs: GameState, critical: bool) -> Dictionary:
	# Seed with no citizens present so no witness hears it early —
	# reaction tests drive _on_heard per subject.
	var r: Dictionary = hs._seed_famine_rumor("gnomes", critical)
	return r


func _test_starving_despair() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _rich_rumor(hs, gs, true)
	var victim: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(victim, r, {})
	_check("starving citizen remembers starving_famine",
		_recalled(victim, "starving_famine", int(r.get("id", 0))) > 0.0)
	_check("starving citizen feels sad", _emotion(victim) == "sad")


func _test_shortage_worry() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _rich_rumor(hs, gs, false)
	var victim: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(victim, r, {})
	_check("shortage citizen remembers hungry_famine",
		_recalled(victim, "hungry_famine", int(r.get("id", 0))) > 0.0)
	_check("shortage citizen feels sad", _emotion(victim) == "sad")


func _test_rival_cackles() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres")
	var r := _rich_rumor(hs, gs, true)
	var rival: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(rival, r, {})
	_check("war-rival remembers mocked_famine",
		_recalled(rival, "mocked_famine", int(r.get("id", 0))) > 0.0)
	_check("war-rival cackles happily", _emotion(rival) == "happy")


func _test_neutral_grieves() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _rich_rumor(hs, gs, true)
	var neutral: Dictionary = _spawn(gs, "elves")
	hs._on_heard(neutral, r, {})
	_check("neutral remembers heard_famine",
		_recalled(neutral, "heard_famine", int(r.get("id", 0))) > 0.0)
	_check("neutral feels sad", _emotion(neutral) == "sad")


func _test_relief_celebrated() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_starve(gs, "gnomes")
	hs._famine_tick()
	_set_food(gs, "gnomes", 500.0)
	hs._famine_tick()
	var rel := _relief_rumors(hs)
	_check("relief rumor exists", rel.size() == 1)
	if rel.is_empty():
		return
	var fed: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(fed, rel[0], {})
	_check("recovered citizen remembers famine_relieved",
		_recalled(fed, "famine_relieved", int(rel[0].get("id", 0))) > 0.0)
	_check("recovered citizen feels happy", _emotion(fed) == "happy")
	var outsider: Dictionary = _spawn(gs, "elves")
	hs._on_heard(outsider, rel[0], {})
	_check("outsider feels happy about relief", _emotion(outsider) == "happy")


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var r := _rich_rumor(hs, gs, true)
	var calm: Dictionary = _spawn(gs, "gnomes")
	var wild: Dictionary = _spawn(gs, "gnomes", {"traits": {"unhinged": 1.0}})
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	var calm_mood = conv.ruler_mood(int(calm.get("id", 0)))
	var wild_mood = conv.ruler_mood(int(wild.get("id", 0)))
	_check("unhinged NPC despairs harder than a calm one",
		float(wild_mood) < float(calm_mood))


func _test_belief_hunger_bonus() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var teller: Dictionary = _spawn(gs, "elves")
	var starving: Dictionary = _spawn(gs, "gnomes")
	var neutral: Dictionary = _spawn(gs, "ogres")
	var r := _rich_rumor(hs, gs, true)
	# Drop the heat so the 1.0 belief clamp doesn't eat the bonus.
	r["heat"] = 0.5
	var b_starving: float = hs._belief(teller, starving, r)
	var b_neutral: float = hs._belief(teller, neutral, r)
	_check("the starving believe hunger talk more",
		b_starving > b_neutral + 0.2)


func _test_belief_doubt_proof() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var teller: Dictionary = _spawn(gs, "elves")
	var hearer: Dictionary = _spawn(gs, "ogres")
	var r := _rich_rumor(hs, gs, true)
	var b_clean: float = hs._belief(teller, hearer, r)
	r["doubters"] = [111, 222, 333]
	r["distortions"] = 3
	var b_doubted: float = hs._belief(teller, hearer, r)
	_check("famine rumors are doubt-proof like slur incidents",
		absf(b_clean - b_doubted) < 0.001)


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres")
	var r := _rich_rumor(hs, gs, true)
	var starving: Dictionary = _spawn(gs, "gnomes")
	var m1: Dictionary = hs._spread_motivation(starving, r)
	_check("the starving spread urgently",
		int(m1.get("cap_delta", 0)) == 1
		and float(m1.get("heat_delta", 0.0)) > 0.0)
	var rival: Dictionary = _spawn(gs, "ogres")
	var m2: Dictionary = hs._spread_motivation(rival, r)
	_check("rivals mock-gossip the famine",
		int(m2.get("cap_delta", 0)) == 1
		and float(m2.get("heat_delta", 0.0)) > 0.0)


func _test_cross_target_routes_to_rival() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres")
	var r := _rich_rumor(hs, gs, true)
	var teller: Dictionary = _spawn(gs, "gnomes")
	var route: Dictionary = hs._cross_target(teller, r)
	_check("famine crosses to a foe of the starving",
		String(route.get("faction", "")) == "ogres")
	_check("schadenfreude travels fast",
		absf(float(route.get("chance", 0.0)) - 0.35) < 0.001)


func _test_gazette_famine_story_routes_to_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# The AI director's exact critical alarm story.
	_story(gs, "FAMINE!",
		"The Gnomes are starving — bellies empty, tempers short.")
	var rs := _famine_rumors(hs)
	_check("FAMINE! story seeds the rich rumor", rs.size() == 1)
	if rs.is_empty():
		return
	_check("rich rumor carries the faction",
		String(rs[0].get("famine_faction", "")) == "gnomes")
	_check("rich rumor flagged critical",
		bool(rs[0].get("famine_critical", false)))
	var thin := 0
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("kind", "")) == "disaster" \
				and String(r2.get("text", "")) == "FAMINE!":
			thin += 1
	_check("no thin disaster double-seed", thin == 0)


func _test_gazette_shortage_story_not_critical() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# The AI director's exact shortage alarm story.
	_story(gs, "FOOD SHORTAGE",
		"Granaries run low among the Gnomes; foragers scour the wilds.")
	var rs := _famine_rumors(hs)
	_check("FOOD SHORTAGE story seeds the rich rumor", rs.size() == 1)
	if rs.is_empty():
		return
	_check("shortage story is not critical",
		not bool(rs[0].get("famine_critical", false)))


func _test_memory_types_registered() -> void:
	var types: Array = load("res://scripts/sim/memories.gd").TYPES
	for t: String in ["starving_famine", "hungry_famine", "mocked_famine",
			"heard_famine", "famine_relieved"]:
		_check("memory type registered: " + t, t in types)
	var weights: Dictionary = load("res://scripts/sim/memories.gd").REL_WEIGHT
	for t: String in ["starving_famine", "hungry_famine", "mocked_famine",
			"heard_famine", "famine_relieved"]:
		_check("memory weight registered: " + t, weights.has(t))


func _test_heat_bars() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	_spawn(gs, "gnomes")
	_set_food(gs, "gnomes", 5.0)
	hs._famine_tick()
	var rs := _famine_rumors(hs)
	_check("shortage rumor seeded", rs.size() == 1)
	if rs.is_empty():
		return
	var heat: float = float(rs[0].get("heat", 0.0))
	_check("shortage clears the ruler bar (0.6)", heat >= 0.6)
	_check("shortage stays below the press bar (0.85)", heat < 0.85)
	_starve(gs, "gnomes")
	hs._famine_tick()
	var crit_heat: float = float(rs[0].get("heat", 0.0))
	_check("critical clears the press bar (0.85)", crit_heat >= 0.85)
