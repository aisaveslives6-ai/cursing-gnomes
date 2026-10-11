extends SceneTree
## Cursing Gnomes — hearsay adventure-quest gossip tests (Jeremy 2026-10-08).
##
## Covers the hearsay flesh-out run: adventure quest outcomes were the last
## deaf thread in the sim — the grapevine only ever heard the thin
## adventure_deed toast ("Completed quest: X.") while the hero's name, the
## quest giver, and the stakes never entered the rumor mill. Now:
##  - bus.adventure_quest_completed seeds a RICH quest rumor (hero named,
##    quest type-flavored, TRUTH_TRUE, heat 0.75, first knower in the
##    hero's faction) and the "Completed quest:" deed does NOT double-post
##    as thin gossip
##  - bus.adventure_quest_failed seeds a failure rumor (heat 0.8) with the
##    fallen charge's name parsed from the failure deed (the signal alone
##    carries no name); missing deed -> "the poor charge" fallback
##  - bus.adventure_won seeds a legend rumor (heat 0.95, press-eligible,
##    Squabble post) and bus.adventure_lost seeds a mourning rumor
##  - the quest reaction matrix: the hero's faction celebrates triumphs
##    (praised, mood up), grieves failures (disaster, mood down), is
##    ecstatic about a legend (+8) and mourns a fallen hero (-10);
##    war-rivals gloat at failures (mocked_quest_fail, mocked), fear a
##    legend (scared, mood down), and savor a fallen hero; everyone else
##    admires or sympathizes. Unhinged NPCs feel it 1.5x.
##  - spread motivation: the hero's faction boasts triumphs (+1 cap),
##    buries failures (-1 cap); rivals push failures (+1 cap, +0.1 heat);
##    a legend is retold by everyone (+2 cap at home)
##  - no hero unit -> rumor still seeds and routes to generic reception
##  - all five memory types registered in SimMemories.TYPES
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_quest.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay adventure-quest gossip tests ===")
	_test_completion_seeds_rich_rumor()
	_test_completion_deed_dedups()
	_test_failure_seeds_with_victim_name()
	_test_failure_without_deed_fallback()
	_test_home_celebrates_completion()
	_test_rival_grumbles_at_completion()
	_test_home_grieves_failure()
	_test_rival_mocks_failure()
	_test_unhinged_amplified()
	_test_legend_seeds_press_eligible_and_posts()
	_test_legend_reactions()
	_test_fall_seeds_and_home_mourns()
	_test_rival_savors_fall()
	_test_spread_motivation()
	_test_no_hero_fallback()
	_test_memory_types_registered()
	_test_quest_dedup_by_subject()
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


func _spawn_hero(gs: GameState, faction: String, hname: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true,
		"is_hero": true, "name": hname})


func _quest(title: String = "Taken in the Night", qid: String = "q1",
		qtype: String = "rescue") -> Dictionary:
	return {"id": qid, "type": qtype, "title": title,
		"giver_role": "mayor", "giver_name": "Mayor Humans",
		"state": "done", "failed": false}


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _rumor_of(hs, outcome: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "quest" \
				and String(r.get("quest_outcome", "")) == outcome:
			return r
	return {}


func _count_quest_rumors(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "quest":
			n += 1
	return n


func _test_completion_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	gs.bus.adventure_quest_completed.emit(_quest())
	var r := _rumor_of(hs, "done")
	_check("completion seeds a quest rumor", not r.is_empty())
	if r.is_empty():
		return
	_check("completion names the hero", String(r.get("text", "")).find("Ash") >= 0)
	_check("completion names the giver", String(r.get("text", "")).find("Mayor Humans") >= 0)
	_check("completion records hero faction", String(r.get("hero_faction", "")) == "gnomes")
	_check("completion records quest title", String(r.get("quest_title", "")) == "Taken in the Night")
	_check("completion heat 0.75", is_equal_approx(float(r.get("heat", 0.0)), 0.75))
	_check("completion is confirmed truth", String(r.get("truth", "")) == "true")
	_check("completion subject", String(r.get("subject", "")) == "questdone:q1")
	_check("completion has a first knower", (r.get("knowers", []) as Array).size() >= 1)


func _test_completion_deed_dedups() -> void:
	# The real game order: deed fires first, then the quest signal. The
	# thin deed gossip must not double-post the rich rumor.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	gs.bus.adventure_deed.emit("Completed quest: Taken in the Night.")
	gs.bus.adventure_quest_completed.emit(_quest())
	var n_deed := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "deed":
			n_deed += 1
	_check("no thin deed gossip for a completed quest", n_deed == 0)
	_check("exactly one quest rumor", _count_quest_rumors(hs) == 1)


func _test_failure_seeds_with_victim_name() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	# Real game order: the failure deed names the dead charge, then the
	# signal carries the quest dict without the name.
	gs.bus.adventure_deed.emit("Failed quest: Taken in the Night — Bob died.")
	var q := _quest()
	q["failed"] = true
	gs.bus.adventure_quest_failed.emit(q)
	var r := _rumor_of(hs, "failed")
	_check("failure seeds a quest rumor", not r.is_empty())
	if r.is_empty():
		return
	_check("failure names the dead charge", String(r.get("text", "")).find("Bob") >= 0)
	_check("failure names the hero", String(r.get("text", "")).find("Ash") >= 0)
	_check("failure heat 0.8", is_equal_approx(float(r.get("heat", 0.0)), 0.8))
	_check("failure subject", String(r.get("subject", "")) == "questfail:q1")
	_check("failure is confirmed truth", String(r.get("truth", "")) == "true")
	var n_deed := 0
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("kind", "")) == "deed":
			n_deed += 1
	_check("no thin deed gossip for a failed quest", n_deed == 0)


func _test_failure_without_deed_fallback() -> void:
	# A failure signal with no preceding deed (old save, reorder): the
	# rumor still seeds with the fallback phrasing.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	var q := _quest()
	q["failed"] = true
	gs.bus.adventure_quest_failed.emit(q)
	var r := _rumor_of(hs, "failed")
	_check("failure without deed still seeds", not r.is_empty())
	if not r.is_empty():
		_check("failure without deed uses fallback", String(r.get("text", "")).find("the poor charge") >= 0)


func _test_home_celebrates_completion() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_spawn_hero(gs, "gnomes", "Ash")
	var fan: Dictionary = _spawn(gs, "gnomes")
	var uid := int(fan.get("id", 0))
	gs.bus.adventure_quest_completed.emit(_quest())
	var r := _rumor_of(hs, "done")
	hs._on_heard(fan, r, {})
	_check("home remembers the triumph", _recalled(fan, "heard_quest_done", int(r.get("id", 0))) > 0.0)
	_check("home mood rises", conv.ruler_mood(uid) > 0.0)
	_check("home is proud", _emotion(fan) == "proud")


func _test_rival_grumbles_at_completion() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_spawn_hero(gs, "gnomes", "Ash")
	var rival: Dictionary = _spawn(gs, "ogres")
	var uid := int(rival.get("id", 0))
	gs.bus.adventure_quest_completed.emit(_quest())
	var r := _rumor_of(hs, "done")
	hs._on_heard(rival, r, {})
	_check("rival remembers the triumph", _recalled(rival, "heard_quest_done", int(r.get("id", 0))) > 0.0)
	_check("rival mood drops", conv.ruler_mood(uid) < 0.0)


func _test_home_grieves_failure() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_spawn_hero(gs, "gnomes", "Ash")
	var fan: Dictionary = _spawn(gs, "gnomes")
	var uid := int(fan.get("id", 0))
	gs.bus.adventure_deed.emit("Failed quest: Taken in the Night — Bob died.")
	var q := _quest()
	q["failed"] = true
	gs.bus.adventure_quest_failed.emit(q)
	var r := _rumor_of(hs, "failed")
	hs._on_heard(fan, r, {})
	_check("home remembers the failure", _recalled(fan, "heard_quest_failed", int(r.get("id", 0))) > 0.0)
	_check("home mood drops", conv.ruler_mood(uid) < 0.0)
	_check("home is disaster-struck", _emotion(fan) == "scared")


func _test_rival_mocks_failure() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_spawn_hero(gs, "gnomes", "Ash")
	var rival: Dictionary = _spawn(gs, "ogres")
	var uid := int(rival.get("id", 0))
	gs.bus.adventure_deed.emit("Failed quest: Taken in the Night — Bob died.")
	var q := _quest()
	q["failed"] = true
	gs.bus.adventure_quest_failed.emit(q)
	var r := _rumor_of(hs, "failed")
	hs._on_heard(rival, r, {})
	_check("rival remembers mocking the failure", _recalled(rival, "mocked_quest_fail", int(r.get("id", 0))) > 0.0)
	_check("rival mood rises", conv.ruler_mood(uid) > 0.0)
	_check("rival is mocked", _emotion(rival) == "sad")


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_spawn_hero(gs, "gnomes", "Ash")
	# Emit before the calm/wild citizens exist — the hero is the first
	# knower, so neither test subject can be randomly picked to hear
	# twice (double-hearing made this check flaky).
	gs.bus.adventure_quest_completed.emit(_quest())
	var rr := _rumor_of(hs, "done")
	var calm: Dictionary = _spawn(gs, "gnomes")
	var wild: Dictionary = _spawn(gs, "gnomes", {"traits": {"unhinged": 1.0}})
	hs._on_heard(calm, rr, {})
	hs._on_heard(wild, rr, {})
	_check("unhinged NPC celebrates harder than a calm one",
		conv.ruler_mood(int(wild.get("id", 0))) > conv.ruler_mood(int(calm.get("id", 0))))


func _test_legend_seeds_press_eligible_and_posts() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	gs.bus.adventure_won.emit()
	var r := _rumor_of(hs, "legend")
	_check("legend rumor seeds", not r.is_empty())
	if r.is_empty():
		return
	_check("legend names the hero", String(r.get("text", "")).find("Ash") >= 0)
	_check("legend heat 0.95", is_equal_approx(float(r.get("heat", 0.0)), 0.95))
	_check("legend is press-eligible", hs._press_eligible(r))
	var posts: Array = phone.state.get("posts", [])
	var sung := false
	for p: Dictionary in posts:
		if String(p.get("text", "")).find("Ash") >= 0 \
				and String(p.get("text", "")).find("LEGEND") >= 0:
			sung = true
	_check("legend gets a Squabble post", sung)


func _test_legend_reactions() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_spawn_hero(gs, "gnomes", "Ash")
	var fan: Dictionary = _spawn(gs, "gnomes")
	var rival: Dictionary = _spawn(gs, "ogres", {"traits": {"brave": 0.0}})
	var brave_rival: Dictionary = _spawn(gs, "ogres", {"traits": {"brave": 1.0}})
	var neutral: Dictionary = _spawn(gs, "elves")
	gs.bus.adventure_won.emit()
	var r := _rumor_of(hs, "legend")
	hs._on_heard(fan, r, {})
	hs._on_heard(rival, r, {})
	hs._on_heard(brave_rival, r, {})
	hs._on_heard(neutral, r, {})
	_check("home remembers the legend", _recalled(fan, "heard_legend", int(r.get("id", 0))) > 0.0)
	_check("home is ecstatic", conv.ruler_mood(int(fan.get("id", 0))) >= 8.0)
	_check("home is proud", _emotion(fan) == "proud")
	_check("rival fears the legend", _emotion(rival) == "scared")
	_check("rival mood drops", conv.ruler_mood(int(rival.get("id", 0))) < 0.0)
	_check("brave rivals get defiant, not scared", _emotion(brave_rival) == "angry")
	_check("neutral admires the legend", _emotion(neutral) == "proud")


func _test_fall_seeds_and_home_mourns() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_spawn_hero(gs, "gnomes", "Ash")
	var fan: Dictionary = _spawn(gs, "gnomes")
	gs.bus.adventure_lost.emit()
	var r := _rumor_of(hs, "fell")
	hs._on_heard(fan, r, {})
	_check("fall rumor seeds", not r.is_empty())
	if r.is_empty():
		return
	_check("fall names the hero", String(r.get("text", "")).find("Ash") >= 0)
	_check("fall heat 0.85", is_equal_approx(float(r.get("heat", 0.0)), 0.85))
	_check("fall is press-eligible", hs._press_eligible(r))
	_check("home mourns", _recalled(fan, "heard_hero_fell", int(r.get("id", 0))) > 0.0)
	_check("home grief runs deep", conv.ruler_mood(int(fan.get("id", 0))) <= -10.0)
	_check("home is grieving", _emotion(fan) == "sad")


func _test_rival_savors_fall() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_spawn_hero(gs, "gnomes", "Ash")
	var rival: Dictionary = _spawn(gs, "ogres")
	gs.bus.adventure_lost.emit()
	var r := _rumor_of(hs, "fell")
	hs._on_heard(rival, r, {})
	_check("rival remembers the fall", _recalled(rival, "heard_hero_fell", int(r.get("id", 0))) > 0.0)
	_check("rival mood rises", conv.ruler_mood(int(rival.get("id", 0))) > 0.0)
	_check("rival mocks the fall", _emotion(rival) == "sad")


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	var fan: Dictionary = _spawn(gs, "gnomes")
	var rival: Dictionary = _spawn(gs, "ogres")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	gs.bus.adventure_quest_completed.emit(_quest("Taken in the Night", "q1"))
	gs.bus.adventure_deed.emit("Failed quest: Pilgrim's Road — Carol died.")
	var qf := _quest("Pilgrim's Road", "q2", "escort")
	qf["failed"] = true
	gs.bus.adventure_quest_failed.emit(qf)
	gs.bus.adventure_won.emit()
	var done := _rumor_of(hs, "done")
	var failed := _rumor_of(hs, "failed")
	var legend := _rumor_of(hs, "legend")
	var m1: Dictionary = hs._spread_motivation(fan, done)
	_check("home boasts triumphs", int(m1.get("cap_delta", 0)) == 1 and float(m1.get("heat_delta", 0.0)) > 0.0)
	var m2: Dictionary = hs._spread_motivation(fan, failed)
	_check("home buries failures", int(m2.get("cap_delta", 0)) == -1)
	var m3: Dictionary = hs._spread_motivation(rival, failed)
	_check("rival pushes failures", int(m3.get("cap_delta", 0)) == 1 and float(m3.get("heat_delta", 0.0)) > 0.0)
	var m4: Dictionary = hs._spread_motivation(fan, legend)
	_check("home retells the legend loudly", int(m4.get("cap_delta", 0)) == 2)
	var m5: Dictionary = hs._spread_motivation(rival, legend)
	_check("rivals retell the legend too", int(m5.get("cap_delta", 0)) == 1)


func _test_no_hero_fallback() -> void:
	# No hero unit in the world (adventure never started): the rumor
	# still seeds and routes to generic reception, never crashes.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var fan: Dictionary = _spawn(gs, "gnomes")
	gs.bus.adventure_quest_completed.emit(_quest())
	var r := _rumor_of(hs, "done")
	_check("no-hero quest still seeds", not r.is_empty())
	if not r.is_empty():
		_check("no-hero text falls back gracefully", String(r.get("text", "")).find("the hero") >= 0)
		_check("no-hero gets generic reception", _recalled(fan, "heard_quest_done", int(r.get("id", 0))) == 0.0)


func _test_memory_types_registered() -> void:
	var types: Array = load("res://scripts/sim/memories.gd").TYPES
	for t: String in ["heard_quest_done", "heard_quest_failed", "heard_legend",
			"heard_hero_fell", "mocked_quest_fail"]:
		_check("memory type registered: " + t, types.has(t))


func _test_quest_dedup_by_subject() -> void:
	# Same quest completing twice (re-fire): seed_rumor upgrades in
	# place instead of spawning a second rumor.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	gs.bus.adventure_quest_completed.emit(_quest())
	gs.bus.adventure_quest_completed.emit(_quest())
	_check("duplicate completion seeds once", _count_quest_rumors(hs) == 1)
