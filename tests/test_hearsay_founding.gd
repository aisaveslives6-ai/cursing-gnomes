extends SceneTree
## Cursing Gnomes — hearsay founding-gossip tests (Jeremy 2026-10-09).
##
## Covers the hearsay flesh-out run: the founding beat was a deaf thread —
## the mill only ever heard the thin "A KINGDOM RISES" court Gazette story
## (heat 0.7, no town, no faction, no reactions, nobody cared) about the
## realm's own birth. Now:
##  - bus.kingdom_founded (town, faction, ruler) seeds a RICH named rumor
##    (town, founding faction, ruler, truth TRUE) BEFORE the Gazette
##    story, and the story dedups against it (no double-seed)
##  - SimFounding._fire emits the signal (end-to-end wiring)
##  - the home faction celebrates (crowned_ruler, proud, mood up)
##  - war-rivals sneer at the new crown (mocked_founding, amused)
##  - allies congratulate (congratulated_founding, warm)
##  - everyone else hears hopeful news (heard_founding)
##  - unhinged NPCs feel it 1.5x (matching the other matrices)
##  - spread zeal: the home faction boasts, rivals sneer-spread
##  - kind tables: founding -> helped emotion, 0.5 memory strength
##  - heat 0.85 clears the ruler bar AND the press bar (Society Pages)
##  - old saves: a thin founding story with no rich rumor still seeds
##    (generic proclamation path)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_founding.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay founding-gossip tests ===")
	_test_signal_seeds_rich_rumor()
	_test_founding_beat_emits_signal()
	_test_home_celebrates()
	_test_rival_sneers()
	_test_ally_congratulates()
	_test_neutral_hears()
	_test_unhinged_amplified()
	_test_story_dedups()
	_test_thin_story_without_rumor_still_seeds()
	_test_press_eligible()
	_test_spread_motivation()
	_test_kind_tables()
	_test_memory_types_registered()
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


func _set_relation(gs: GameState, a: String, b: String, st: String) -> void:
	var rec: Dictionary = gs.diplomacy._pair(a, b)
	if not rec.is_empty():
		rec["state"] = st


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _founding_rumors(hs) -> Array:
	var out: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "founding":
			out.append(r)
	return out


func _crown(hs, gs: GameState, town: String = "Crownburg",
		faction: String = "gnomes", ruler: String = "ass") -> Array:
	gs.bus.kingdom_founded.emit(town, faction, ruler)
	return _founding_rumors(hs)


func _test_signal_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	var rs := _crown(hs, gs)
	_check("signal seeds exactly one rumor", rs.size() == 1)
	if rs.is_empty():
		return
	var r: Dictionary = rs[0]
	_check("rich rumor carries the town", String(r.get("founding_town", "")) == "Crownburg")
	_check("rich rumor carries the founding faction", String(r.get("founding_faction", "")) == "gnomes")
	_check("rich rumor carries the ruler", String(r.get("founding_ruler", "")) == "ass")
	_check("rich rumor names the town as subject", String(r.get("subject", "")) == "Crownburg")
	_check("rich rumor is witnessed fact", String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("rich rumor text names the crown", String(r.get("text", "")).contains("Crownburg"))
	_check("home citizen is the first knower", (r.get("knowers", []) as Array).size() == 1)


func _test_founding_beat_emits_signal() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var fired: Array = []
	gs.bus.kingdom_founded.connect(
		func(town: String, faction: String, ruler: String) -> void:
			fired.append([town, faction, ruler]))
	var founding = load("res://scripts/sim/founding.gd").new(gs)
	founding._fire()
	_check("SimFounding._fire emits kingdom_founded", fired.size() == 1)
	if fired.is_empty():
		return
	_check("signal carries the faction key", String(fired[0][1]) == "gnomes")
	_check("signal carries the ruler verbatim", String(fired[0][2]) == "ass")


func _test_home_celebrates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var r: Dictionary = (_crown(hs, gs))[0]
	var rid := int(r.get("id", 0))
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("home remembers the coronation", _recalled(u, "crowned_ruler", rid) > 0.0)
	_check("home mood soars", conv.ruler_mood(int(u.get("id", 0))) > 0.0)


func _test_rival_sneers() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var r: Dictionary = (_crown(hs, gs))[0]
	var rid := int(r.get("id", 0))
	var u: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(u, r, {})
	_check("rival remembers mocking the crown", _recalled(u, "mocked_founding", rid) > 0.0)
	_check("rival is amused, not grieving", conv_ruler_mood(h, u) > 0.0)


func conv_ruler_mood(h: Array, u: Dictionary) -> float:
	return float(h[1].get("conversation").ruler_mood(int(u.get("id", 0))))


func _test_ally_congratulates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_set_relation(gs, "elves", "gnomes", "allied")
	var r: Dictionary = (_crown(hs, gs))[0]
	var rid := int(r.get("id", 0))
	var u: Dictionary = _spawn(gs, "elves")
	hs._on_heard(u, r, {})
	_check("ally remembers congratulating", _recalled(u, "congratulated_founding", rid) > 0.0)
	_check("ally mood warms", conv_ruler_mood(h, u) > 0.0)


func _test_neutral_hears() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r: Dictionary = (_crown(hs, gs))[0]
	var rid := int(r.get("id", 0))
	var u: Dictionary = _spawn(gs, "undead")
	hs._on_heard(u, r, {})
	_check("neutral remembers hearing the news", _recalled(u, "heard_founding", rid) > 0.0)
	_check("neutral mood lifts mildly", conv_ruler_mood(h, u) > 0.0)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# Emit before any citizens exist — no first knower, no double-hearing.
	var r: Dictionary = (_crown(hs, gs))[0]
	var calm: Dictionary = _spawn(gs, "gnomes")
	var wild: Dictionary = _spawn(gs, "gnomes", {"traits": {"unhinged": 1.0}})
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	_check("unhinged NPC celebrates harder than a calm one",
		conv_ruler_mood(h, wild) > conv_ruler_mood(h, calm))


func _story(gs: GameState, headline: String, body: String) -> void:
	gs.bus.gazette_story.emit({
		"day": 1,
		"headline": headline,
		"body": body,
		"kind": "court",
	})


func _test_story_dedups() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_crown(hs, gs)
	# founding.gd's exact headline; the body names the crowned town.
	_story(gs, "A KINGDOM RISES",
		"The banners are up in Crownburg, the horns are hoarse, and the Gnomes have a new ruler: ass.")
	_check("founding story does not double-seed", _founding_rumors(hs).size() == 1)


func _test_thin_story_without_rumor_still_seeds() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# Old save: no rich rumor, just the thin court story. (Fresh setups
	# already carry ambient rumors, so filter by headline like the
	# festival suite does.)
	_story(gs, "A KINGDOM RISES",
		"The banners are up in Oldtown, the horns are hoarse, and the Humans have a new ruler: bob.")
	var thin: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "court" \
				and String(r.get("text", "")) == "A KINGDOM RISES":
			thin.append(r)
	_check("thin story still seeds a proclamation", thin.size() == 1)
	_check("no rich founding rumor from a thin story", _founding_rumors(hs).is_empty())


func _test_press_eligible() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	var r: Dictionary = (_crown(hs, gs))[0]
	_check("founding heat clears the press bar", float(r.get("heat", 0.0)) >= hs.PRESS_HEAT)
	_check("founding is press-eligible", hs._press_eligible(r))


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var r: Dictionary = (_crown(hs, gs))[0]
	var home: Dictionary = _spawn(gs, "gnomes")
	var rival: Dictionary = _spawn(gs, "ogres")
	var neutral: Dictionary = _spawn(gs, "elves")
	var m_home: Dictionary = hs._spread_motivation(home, r)
	var m_rival: Dictionary = hs._spread_motivation(rival, r)
	var m_neutral: Dictionary = hs._spread_motivation(neutral, r)
	_check("home boasts the coronation", int(m_home.get("cap_delta", 0)) == 1)
	_check("rival sneer-spreads", int(m_rival.get("cap_delta", 0)) == 1)
	_check("neutral just gossips", int(m_neutral.get("cap_delta", 0)) == 0)


func _test_kind_tables() -> void:
	var h: Array = _harness()
	var hs = h[2]
	_check("founding maps to helped emotion",
		String(hs.KIND_EMOTION.get("founding", "")) == "helped")
	_check("founding memory strength registered",
		float(hs.KIND_MEM_STRENGTH.get("founding", 0.0)) == 0.5)


func _test_memory_types_registered() -> void:
	var mem_cls = load("res://scripts/sim/memories.gd")
	for t: String in ["crowned_ruler", "heard_founding", "mocked_founding",
			"congratulated_founding"]:
		_check("memory type registered: " + t, t in mem_cls.TYPES)
		_check("memory weight registered: " + t, mem_cls.REL_WEIGHT.has(t))
