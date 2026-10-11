extends SceneTree
## Cursing Gnomes — hearsay seasonal-gossip tests (Jeremy 2026-10-09).
##
## Covers the hearsay flesh-out run: the turning seasons were a deaf
## thread — the realm's biggest shared experience (everyone feels winter
## come) never reached the rumor mill, even though seasons.gd emits
## bus.season_changed on every turnover. Now:
##  - _on_season_changed seeds a RICH kind-"season" rumor per season:
##    winter 0.7 / spring 0.55 / summer 0.5 / autumn 0.6, truth TRUE,
##    press_ok false, subject year-qualified ("season:Winter:1") so each
##    year's season is its own rumor; repeat emits dedup, not duplicate
##  - PRESS_EXCLUDE_KINDS gains "season" — the calendar turning is tavern
##    talk, not front-page news
##  - reaction matrix (_season_reaction): winter dreads (farmers deeper;
##    a faction with a live famine rumor dreads deepest — starving_winter),
##    spring hopes (farmers brightest), summer eases civilians but makes
##    soldiers restless, autumn brings harvest hope; unhinged 1.5x
##  - belief: seasons join the witnessed-fact club — doubt and distortion
##    dents never apply (the snow is on the ground)
##  - spread zeal: winter warnings push (cap+1), spring hope spreads
##    gladly; summer/autumn are idle chat
##  - cross-border: the snow doesn't stop at the border — season talk
##    routes to any open realm at 0.6
##  - Squabble posts mark the turn; 6 new memory types + weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_season.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay seasonal-gossip tests ===")
	_test_winter_seeds_rich_rumor()
	_test_spring_heat()
	_test_summer_heat()
	_test_autumn_heat()
	_test_repeat_emit_dedups()
	_test_press_excluded()
	_test_dispatch_routes_to_matrix()
	_test_thin_season_falls_to_generic()
	_test_winter_dread()
	_test_farmer_dreads_deeper()
	_test_starving_winter()
	_test_spring_hope()
	_test_farmer_spring_brighter()
	_test_summer_ease()
	_test_summer_restless_soldier()
	_test_autumn_harvest_hope()
	_test_unhinged_amplified()
	_test_belief_season_doubt_proof()
	_test_spread_motivation()
	_test_cross_target_realm_wide()
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


func _spawn(gs: GameState, faction: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"faction": faction, "alive": true}
	for k: String in extra.keys():
		d[k] = extra[k]
	return gs.add_unit(d)


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _season_rumors(hs) -> Array:
	var out: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "season":
			out.append(r)
	return out


func _emit_winter(hs, gs: GameState) -> Dictionary:
	gs.bus.season_changed.emit("Winter")
	var rs := _season_rumors(hs)
	_check("winter emits exactly one season rumor", rs.size() == 1)
	return rs[0] if not rs.is_empty() else {}


func _test_winter_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _emit_winter(hs, gs)
	_check("winter rumor carries the season", String(r.get("season", "")) == "Winter")
	_check("winter rumor heat is 0.7", absf(float(r.get("heat", 0.0)) - 0.7) < 0.001)
	_check("winter rumor truth is TRUE", String(r.get("truth", "")) == "true")
	_check("winter rumor subject is year-qualified",
		String(r.get("subject", "")).begins_with("season:Winter:"))
	_check("winter rumor never press-eligible", bool(r.get("press_ok", true)) == false)


func _test_spring_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.season_changed.emit("Spring")
	var rs := _season_rumors(hs)
	_check("spring seeds one rumor", rs.size() == 1)
	if not rs.is_empty():
		_check("spring rumor heat is 0.55",
			absf(float(rs[0].get("heat", 0.0)) - 0.55) < 0.001)
		_check("spring rumor truth is TRUE", String(rs[0].get("truth", "")) == "true")


func _test_summer_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.season_changed.emit("Summer")
	var rs := _season_rumors(hs)
	_check("summer seeds one rumor", rs.size() == 1)
	if not rs.is_empty():
		_check("summer rumor heat is 0.5",
			absf(float(rs[0].get("heat", 0.0)) - 0.5) < 0.001)


func _test_autumn_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.season_changed.emit("Autumn")
	var rs := _season_rumors(hs)
	_check("autumn seeds one rumor", rs.size() == 1)
	if not rs.is_empty():
		_check("autumn rumor heat is 0.6",
			absf(float(rs[0].get("heat", 0.0)) - 0.6) < 0.001)


func _test_repeat_emit_dedups() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.season_changed.emit("Winter")
	gs.bus.season_changed.emit("Winter")
	var rs := _season_rumors(hs)
	_check("repeat winter emit dedups instead of twinning", rs.size() == 1)


func _test_press_excluded() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_check("season is in PRESS_EXCLUDE_KINDS",
		"season" in hs.PRESS_EXCLUDE_KINDS)
	var r := _emit_winter(hs, gs)
	r["heat"] = 1.0
	r["press_ok"] = true  # even a forced-ok rumor stays unprinted
	var knowers: Array = []
	for i in 12:
		knowers.append(1000 + i)
	r["knowers"] = knowers
	_check("hot many-knower season rumor still not press-eligible",
		not hs._press_eligible(r))


func _test_dispatch_routes_to_matrix() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _emit_winter(hs, gs)
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("winter routes to the matrix (dreaded_winter)",
		_recalled(u, "dreaded_winter", int(r.get("id", 0))) > 0.0)


func _test_thin_season_falls_to_generic() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# Old-save shape: kind "season" with no season key — generic path, no crash.
	var r: Dictionary = hs.seed_rumor("Winter came.", "season", "season:thin", 0.5)
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("thin season rumor falls to the generic path",
		_recalled(u, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _test_winter_dread() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _emit_winter(hs, gs)
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("winter dreads the hearer", _recalled(u, "dreaded_winter",
		int(r.get("id", 0))) > 0.0)
	_check("winter feels dismayed (sad)", _emotion(u) == "sad")


func _test_farmer_dreads_deeper() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var r := _emit_winter(hs, gs)
	var peasant: Dictionary = _spawn(gs, "gnomes")
	var farmer: Dictionary = _spawn(gs, "gnomes", {"job": "farmer"})
	hs._on_heard(peasant, r, {})
	hs._on_heard(farmer, r, {})
	var pm = conv.ruler_mood(int(peasant.get("id", 0)))
	var fm = conv.ruler_mood(int(farmer.get("id", 0)))
	_check("farmers dread winter deeper than peasants",
		float(fm) < float(pm))


func _test_starving_winter() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	hs._seed_famine_rumor("gnomes", false)  # live famine rumor for gnomes
	var r := _emit_winter(hs, gs)
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("a hungry faction dreads deepest (starving_winter)",
		_recalled(u, "starving_winter", int(r.get("id", 0))) > 0.0)
	_check("starving_winter replaces dreaded_winter",
		_recalled(u, "dreaded_winter", int(r.get("id", 0))) == 0.0)


func _test_spring_hope() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.season_changed.emit("Spring")
	var r = _season_rumors(hs)[0]
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("spring is welcomed", _recalled(u, "welcomed_spring",
		int(r.get("id", 0))) > 0.0)
	_check("spring feels cheerful (happy)", _emotion(u) == "happy")


func _test_farmer_spring_brighter() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	gs.bus.season_changed.emit("Spring")
	var r = _season_rumors(hs)[0]
	var peasant: Dictionary = _spawn(gs, "gnomes")
	var farmer: Dictionary = _spawn(gs, "gnomes", {"job": "farmer"})
	hs._on_heard(peasant, r, {})
	hs._on_heard(farmer, r, {})
	var pm = conv.ruler_mood(int(peasant.get("id", 0)))
	var fm = conv.ruler_mood(int(farmer.get("id", 0)))
	_check("farmers hope brightest in spring", float(fm) > float(pm))


func _test_summer_ease() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.season_changed.emit("Summer")
	var r = _season_rumors(hs)[0]
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("summer eases civilians", _recalled(u, "summer_ease",
		int(r.get("id", 0))) > 0.0)
	_check("summer ease feels cheerful (happy)", _emotion(u) == "happy")


func _test_summer_restless_soldier() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.season_changed.emit("Summer")
	var r = _season_rumors(hs)[0]
	var s: Dictionary = _spawn(gs, "gnomes", {"job": "soldier"})
	hs._on_heard(s, r, {})
	_check("soldiers grow restless in summer", _recalled(s, "summer_restless",
		int(r.get("id", 0))) > 0.0)
	_check("restless soldiers feel grumpy (angry)", _emotion(s) == "angry")


func _test_autumn_harvest_hope() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.season_changed.emit("Autumn")
	var r = _season_rumors(hs)[0]
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("autumn brings harvest hope", _recalled(u, "harvest_hope",
		int(r.get("id", 0))) > 0.0)
	_check("harvest hope feels cheerful (happy)", _emotion(u) == "happy")


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var r := _emit_winter(hs, gs)
	var calm: Dictionary = _spawn(gs, "gnomes")
	var wild: Dictionary = _spawn(gs, "gnomes", {"mind": {"traits": {"unhinged": 1.0}}})
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	var cm = conv.ruler_mood(int(calm.get("id", 0)))
	var wm = conv.ruler_mood(int(wild.get("id", 0)))
	_check("unhinged NPC dreads winter harder than a calm one",
		float(wm) < float(cm))


func _test_belief_season_doubt_proof() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var teller: Dictionary = _spawn(gs, "elves")
	var hearer: Dictionary = _spawn(gs, "ogres")
	var r := _emit_winter(hs, gs)
	var b_clean: float = hs._belief(teller, hearer, r)
	r["doubters"] = [111, 222, 333]
	r["distortions"] = 3
	var b_doubted: float = hs._belief(teller, hearer, r)
	_check("season rumors are doubt-proof like slur incidents",
		absf(b_clean - b_doubted) < 0.001)


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var w := _emit_winter(hs, gs)
	var u: Dictionary = _spawn(gs, "gnomes")
	var mw: Dictionary = hs._spread_motivation(u, w)
	_check("winter warnings push eagerly",
		int(mw.get("cap_delta", 0)) == 1 \
		and absf(float(mw.get("heat_delta", 0.0)) - 0.05) < 0.001)
	gs.bus.season_changed.emit("Spring")
	var s = _season_rumors(hs)[1]
	var ms: Dictionary = hs._spread_motivation(u, s)
	_check("spring hope spreads gladly",
		int(ms.get("cap_delta", 0)) == 1 \
		and absf(float(ms.get("heat_delta", 9.9))) < 0.001)
	gs.bus.season_changed.emit("Summer")
	var su = _season_rumors(hs)[2]
	var msu: Dictionary = hs._spread_motivation(u, su)
	_check("summer is idle chat",
		int(msu.get("cap_delta", 9)) == 0 \
		and absf(float(msu.get("heat_delta", 9.9))) < 0.001)


func _test_cross_target_realm_wide() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _emit_winter(hs, gs)
	var u: Dictionary = _spawn(gs, "gnomes")
	var t: Dictionary = hs._cross_target(u, r)
	_check("season talk crosses into an open realm",
		String(t.get("faction", "")) != "" \
		and String(t.get("faction", "")) != "gnomes")
	_check("season talk crosses eagerly (0.6)",
		absf(float(t.get("chance", 0.0)) - 0.6) < 0.001)


func _test_memory_types_registered() -> void:
	var types: Array = SimMemories.TYPES
	for mt: String in ["dreaded_winter", "starving_winter", "welcomed_spring",
			"summer_ease", "summer_restless", "harvest_hope"]:
		_check("memory type registered: " + mt, mt in types)
