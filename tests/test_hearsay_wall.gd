extends SceneTree
## Cursing Gnomes — hearsay border-wall gossip tests (Jeremy 2026-10-09).
##
## Covers the hearsay flesh-out run: the crown's Raise/Skip verdict on a
## named region's walls (bus.wall_answer, from the NPC wall prompt and
## Ruler's Voice) was a deaf thread — the Gazette printed ROYAL WORKS
## and the mill heard nothing (raise got a thin faceless court seed,
## skip got nothing at all). Now:
##  - _on_wall_answer seeds a RICH kind-"wall" rumor per region:
##    raised 0.7 / skipped 0.5, truth TRUE, subject = region name;
##    repeat verdicts refresh, not duplicate
##  - _on_story folds the ROYAL WORKS story into the rich rumor
##    (region parsed from the body); story-first order seeds the rich
##    rumor directly; unparseable bodies keep the thin seed
##  - reaction matrix (_wall_reaction): raised — crown's people swell
##    with pride, war-rivals sneer, neutrals feel awe + unease;
##    skipped — crown's people split (unhinged laugh, the rest uneasy),
##    war-rivals cackle, neutrals file it as tavern talk; unhinged 1.5x
##  - spread zeal: crown's people boast the raising (+1) and bury the
##    refusal (-1); rivals sneer/cackle-spread (+1); neutrals tell
##    it straight
##  - heat stays below PRESS_HEAT — the Gazette's ROYAL WORKS already
##    IS the press coverage; Squabble posts mark the verdict
##  - 7 new memory types + weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_wall.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay border-wall gossip tests ===")
	_test_raise_seeds_rich_rumor()
	_test_skip_seeds_rich_rumor()
	_test_empty_region_ignored()
	_test_repeat_raise_dedups()
	_test_raise_then_skip_refreshes()
	_test_story_folds_into_rich_rumor()
	_test_story_first_seeds_rich()
	_test_unparseable_story_keeps_thin_seed()
	_test_dispatch_routes_to_matrix()
	_test_thin_wall_falls_to_generic()
	_test_raise_crown_pride()
	_test_raise_rival_sneer()
	_test_raise_neutral_unease()
	_test_skip_crown_unease()
	_test_skip_unhinged_laughs()
	_test_skip_rival_cackles()
	_test_unhinged_amplified()
	_test_spread_motivation()
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


## SimEmotion writes unit["emotion"] = {"name":..., "intensity":..., "ttl":...}.
## Regression guard: wall reactions must actually land the scared emotion
## (the "scared"-as-event typo silently no-op'd through EVENT_MAP).
func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _wall_rumors(hs) -> Array:
	var out: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "wall":
			out.append(r)
	return out


func _mood(phone, uid: int) -> float:
	var conv = phone.get("conversation")
	return conv.ruler_mood(uid)


func _test_raise_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.wall_answer.emit("The Shivering Marches", true)
	var rs := _wall_rumors(hs)
	_check("raise seeds exactly one wall rumor", rs.size() == 1)
	if rs.is_empty():
		return
	var r: Dictionary = rs[0]
	_check("raise rumor heat is 0.7",
		absf(float(r.get("heat", 0.0)) - 0.7) < 0.001)
	_check("raise rumor truth is TRUE", String(r.get("truth", "")) == "true")
	_check("raise rumor wall_event is raised",
		String(r.get("wall_event", "")) == "raised")
	_check("raise rumor names the region",
		String(r.get("wall_region", "")) == "The Shivering Marches")
	_check("raise rumor wall_faction is the crown (gnomes)",
		String(r.get("wall_faction", "")) == "gnomes")
	_check("raise rumor subject is the region",
		String(r.get("subject", "")) == "The Shivering Marches")


func _test_skip_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.wall_answer.emit("Gloomy Hollow", false)
	var rs := _wall_rumors(hs)
	_check("skip seeds exactly one wall rumor", rs.size() == 1)
	if rs.is_empty():
		return
	var r: Dictionary = rs[0]
	_check("skip rumor heat is 0.5",
		absf(float(r.get("heat", 0.0)) - 0.5) < 0.001)
	_check("skip rumor wall_event is skipped",
		String(r.get("wall_event", "")) == "skipped")
	_check("skip rumor truth is TRUE", String(r.get("truth", "")) == "true")


func _test_empty_region_ignored() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.wall_answer.emit("   ", true)
	_check("empty region seeds nothing", _wall_rumors(hs).is_empty())


func _test_repeat_raise_dedups() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.wall_answer.emit("The Shivering Marches", true)
	gs.bus.wall_answer.emit("The Shivering Marches", true)
	_check("repeat raise refreshes, not duplicates",
		_wall_rumors(hs).size() == 1)


func _test_raise_then_skip_refreshes() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.wall_answer.emit("The Shivering Marches", true)
	gs.bus.wall_answer.emit("The Shivering Marches", false)
	var rs := _wall_rumors(hs)
	_check("raise-then-skip keeps one rumor", rs.size() == 1)
	if not rs.is_empty():
		_check("event flips to skipped on re-verdict",
			String(rs[0].get("wall_event", "")) == "skipped")


func _test_story_folds_into_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# Live order: signal first, story second.
	gs.bus.wall_answer.emit("The Shivering Marches", true)
	gs.bus.gazette_story.emit({"headline": "ROYAL WORKS",
		"body": "The crown orders walls raised around The Shivering Marches.",
		"kind": "court"})
	var rs := _wall_rumors(hs)
	_check("story folds into the rich rumor (no twin)", rs.size() == 1)
	if not rs.is_empty():
		_check("folded rumor stays raised",
			String(rs[0].get("wall_event", "")) == "raised")


func _test_story_first_seeds_rich() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# Story-first order (old saves, unusual connect order): the story
	# branch seeds the RICH rumor itself, never a thin twin.
	gs.bus.gazette_story.emit({"headline": "ROYAL WORKS",
		"body": "The crown orders walls raised around The Shivering Marches.",
		"kind": "court"})
	gs.bus.wall_answer.emit("The Shivering Marches", true)
	var rs := _wall_rumors(hs)
	_check("story-first order still yields one rich rumor", rs.size() == 1)
	if not rs.is_empty():
		_check("story-seeded rumor is raised",
			String(rs[0].get("wall_event", "")) == "raised")


func _test_unparseable_story_keeps_thin_seed() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.gazette_story.emit({"headline": "ROYAL WORKS",
		"body": "walls?? somewhere??", "kind": "court"})
	var rs := _wall_rumors(hs)
	_check("unparseable story seeds no wall rumor", rs.is_empty())
	var thin := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "court":
			thin += 1
	_check("unparseable story keeps the thin court seed", thin == 1)


func _test_dispatch_routes_to_matrix() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.wall_answer.emit("The Shivering Marches", true)
	var rs := _wall_rumors(hs)
	_check("dispatch test has its rumor", rs.size() == 1)
	if rs.is_empty():
		return
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, rs[0], {})
	_check("crown citizen remembers pride",
		_recalled(u, "wall_raised_pride", int(rs[0].get("id", 0))) > 0.0)


func _test_thin_wall_falls_to_generic() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# Old-save shape: kind "wall" with no wall_event — generic path, no crash.
	var r: Dictionary = hs.seed_rumor("Walls somewhere.", "wall", "wall:thin", 0.5)
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("thin wall rumor falls to the generic path",
		_recalled(u, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _raise_rumor(hs, gs: GameState) -> Dictionary:
	gs.bus.wall_answer.emit("The Shivering Marches", true)
	var rs := _wall_rumors(hs)
	return rs[0] if not rs.is_empty() else {}


func _skip_rumor(hs, gs: GameState) -> Dictionary:
	gs.bus.wall_answer.emit("Gloomy Hollow", false)
	for r: Dictionary in _wall_rumors(hs):
		if String(r.get("wall_event", "")) == "skipped":
			return r
	return {}


func _test_raise_crown_pride() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var r := _raise_rumor(hs, gs)
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	var uid := int(u.get("id", 0))
	_check("crown pride remembered",
		_recalled(u, "wall_raised_pride", int(r.get("id", 0))) > 0.0)
	_check("crown mood lifts", _mood(phone, uid) > 0.0)


func _test_raise_rival_sneer() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var r := _raise_rumor(hs, gs)
	var u: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(u, r, {})
	_check("war-rival sneers at the raising",
		_recalled(u, "wall_raised_sneer", int(r.get("id", 0))) > 0.0)


func _test_raise_neutral_unease() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _raise_rumor(hs, gs)
	var u: Dictionary = _spawn(gs, "elves")
	hs._on_heard(u, r, {})
	_check("neutral reads the stones with unease",
		_recalled(u, "wall_raised_news", int(r.get("id", 0))) > 0.0)
	_check("neutral bystander feels scared at the raising",
		_emotion(u) == "scared")


func _test_skip_crown_unease() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _skip_rumor(hs, gs)
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("crown feels the refusal",
		_recalled(u, "wall_skipped_unease", int(r.get("id", 0))) > 0.0)
	_check("crown citizen feels scared at the skipped raising",
		_emotion(u) == "scared")


func _test_skip_unhinged_laughs() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _skip_rumor(hs, gs)
	var u: Dictionary = _spawn(gs, "gnomes", {"mind": {"traits": {"unhinged": 1.0}}})
	hs._on_heard(u, r, {})
	_check("unhinged crown citizen laughs at the gamble",
		_recalled(u, "wall_skipped_laugh", int(r.get("id", 0))) > 0.0)


func _test_skip_rival_cackles() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var r := _skip_rumor(hs, gs)
	var u: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(u, r, {})
	_check("war-rival cackles at the open border",
		_recalled(u, "wall_skipped_mock", int(r.get("id", 0))) > 0.0)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var r := _raise_rumor(hs, gs)
	var u1: Dictionary = _spawn(gs, "gnomes")
	var u2: Dictionary = _spawn(gs, "gnomes", {"mind": {"traits": {"unhinged": 1.0}}})
	hs._on_heard(u1, r, {})
	hs._on_heard(u2, r, {})
	_check("unhinged pride runs 1.5x",
		_mood(phone, int(u2.get("id", 0))) > _mood(phone, int(u1.get("id", 0))))


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var rr := _raise_rumor(hs, gs)
	var sr := _skip_rumor(hs, gs)
	var crown: Dictionary = _spawn(gs, "gnomes")
	var rival: Dictionary = _spawn(gs, "ogres")
	var neutral: Dictionary = _spawn(gs, "elves")
	var m1: Dictionary = hs._spread_motivation(crown, rr)
	_check("crown boasts the raising", int(m1.get("cap_delta", 0)) == 1)
	var m2: Dictionary = hs._spread_motivation(crown, sr)
	_check("crown buries the refusal", int(m2.get("cap_delta", 0)) == -1)
	var m3: Dictionary = hs._spread_motivation(rival, rr)
	_check("rival sneer-spreads the raising", int(m3.get("cap_delta", 0)) == 1)
	var m4: Dictionary = hs._spread_motivation(rival, sr)
	_check("rival cackle-spreads the refusal", int(m4.get("cap_delta", 0)) == 1)
	var m5: Dictionary = hs._spread_motivation(neutral, rr)
	_check("neutral tells it straight", int(m5.get("cap_delta", 0)) == 0)


func _test_memory_types_registered() -> void:
	var types: Array = load("res://scripts/sim/memories.gd").TYPES
	for t: String in ["wall_raised_pride", "wall_raised_sneer",
			"wall_raised_news", "wall_skipped_laugh", "wall_skipped_unease",
			"wall_skipped_mock", "wall_skipped_news"]:
		_check("memory type registered: " + t, t in types)
