extends SceneTree
## Cursing Gnomes — hearsay festival-gossip tests (Jeremy 2026-10-08).
##
## Covers the hearsay flesh-out run: festivals were a deaf thread — the
## mill only ever heard the thin court Gazette story (heat 0.7, no town,
## no reactions, nobody cared) about the biggest party in the realm. Now:
##  - bus.festival_event (held/cancelled/wound_down) seeds a RICH named
##    rumor (town, host faction, joy, truth TRUE) BEFORE the Gazette
##    story, and the story dedups against it (no double-seed)
##  - repeat events in the same town refresh, not duplicate; the newest
##    event's text wins (the mill moves on)
##  - the host faction celebrates (celebrated_festival, proud, mood up)
##  - war-rivals sneer at the joy (sneered_at_festival, sad, mood down)
##  - neutrals enjoy the happy news (heard_festival, happy)
##  - cancellations gut the host town (festival_cancelled, sad) while
##    war-rivals cackle (mocked_festival, happy)
##  - wind-downs leave a warm afterglow (festival_memory)
##  - unhinged NPCs feel it 1.5x (matching the other matrices)
##  - spread zeal: the host faction boasts, rivals bury the triumph and
##    gloat over cancellations
##  - kind tables: festival -> helped emotion, registered memory types
##  - held heat (0.85) clears the ruler bar AND the press bar (Society
##    Pages); cancelled (0.7) clears only the ruler bar
##  - old saves: a thin festival story with no rich rumor still seeds
##    (generic happy-news path)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_festival.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay festival-gossip tests ===")
	_test_held_seeds_rich_rumor()
	_test_cancelled_and_wound_down_seeds()
	_test_repeat_event_refreshes_not_duplicates()
	_test_event_change_updates_text()
	_test_gazette_story_dedups()
	_test_winddown_story_dedups()
	_test_thin_story_without_rumor_still_seeds()
	_test_host_celebrates()
	_test_rival_sneers()
	_test_neutral_enjoys()
	_test_cancelled_grief()
	_test_rival_cackles()
	_test_wound_down_afterglow()
	_test_unhinged_amplified()
	_test_spread_motivation()
	_test_kind_tables()
	_test_memory_types_registered()
	_test_heat_bars()
	_test_old_save_fallback_generic()
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


func _festival_rumors(hs) -> Array:
	var out: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "festival" \
				and String(r.get("fest_event", "")) != "":
			out.append(r)
	return out


func _hold(hs, gs: GameState, town: String = "Pieburg", faction: String = "gnomes",
		joy: int = 12) -> Array:
	gs.bus.festival_event.emit("held", town, faction, joy)
	return _festival_rumors(hs)


func _test_held_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	var rs := _hold(hs, gs)
	_check("held seeds exactly one rumor", rs.size() == 1)
	if rs.is_empty():
		return
	var r: Dictionary = rs[0]
	_check("rich rumor carries the town", String(r.get("fest_town", "")) == "Pieburg")
	_check("rich rumor carries the host faction", String(r.get("fest_faction", "")) == "gnomes")
	_check("rich rumor carries the joy", int(r.get("fest_joy", 0)) == 12)
	_check("rich rumor is witnessed fact", String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("rich rumor heat 0.85", absf(float(r.get("heat", 0.0)) - 0.85) < 0.001)
	_check("rich rumor event held", String(r.get("fest_event", "")) == "held")
	_check("rich rumor subject is the town", String(r.get("subject", "")) == "Pieburg")
	# The host faction hears it first.
	var knowers: Array = r.get("knowers", [])
	_check("a host-faction citizen is the first knower", not knowers.is_empty())


func _test_cancelled_and_wound_down_seeds() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.festival_event.emit("cancelled", "Mudwick", "gnomes", 0)
	gs.bus.festival_event.emit("wound_down", "Pieburg", "gnomes", 0)
	var rs := _festival_rumors(hs)
	_check("two rumors for two towns", rs.size() == 2)
	var cr: Dictionary = {}
	var wr: Dictionary = {}
	for r: Dictionary in rs:
		if String(r.get("fest_event", "")) == "cancelled":
			cr = r
		elif String(r.get("fest_event", "")) == "wound_down":
			wr = r
	_check("cancelled rumor seeded", not cr.is_empty())
	_check("cancelled heat 0.7", absf(float(cr.get("heat", 0.0)) - 0.7) < 0.001)
	_check("wound_down rumor seeded", not wr.is_empty())
	_check("wound_down heat 0.5", absf(float(wr.get("heat", 0.0)) - 0.5) < 0.001)


func _test_repeat_event_refreshes_not_duplicates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_hold(hs, gs)
	_hold(hs, gs)
	_check("repeat held refreshes, not duplicates",
		_festival_rumors(hs).size() == 1)


func _test_event_change_updates_text() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_hold(hs, gs)
	var before := String((_festival_rumors(hs)[0] as Dictionary).get("text", ""))
	gs.bus.festival_event.emit("wound_down", "Pieburg", "gnomes", 0)
	var rs := _festival_rumors(hs)
	_check("event change does not duplicate", rs.size() == 1)
	if rs.is_empty():
		return
	var after := String((rs[0] as Dictionary).get("text", ""))
	_check("newest event text wins", after != before)
	_check("event key updated", String((rs[0] as Dictionary).get("fest_event", "")) == "wound_down")


func _story(gs: GameState, headline: String, body: String) -> void:
	gs.bus.gazette_story.emit({
		"day": 1,
		"headline": headline,
		"body": body,
		"kind": "court",
	})


func _test_gazette_story_dedups() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_hold(hs, gs)
	# policies.gd's exact held Gazette story.
	_story(gs, "GRAND FESTIVAL!",
		"Music, pies, dancing in the mud! Pieburg celebrates the crown's generosity.")
	_check("held story does not double-seed", _festival_rumors(hs).size() == 1)


func _test_winddown_story_dedups() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.festival_event.emit("cancelled", "Mudwick", "gnomes", 0)
	gs.bus.festival_event.emit("wound_down", "Pieburg", "gnomes", 0)
	# policies.gd's exact wind-down and cancelled Gazette stories.
	_story(gs, "FESTIVAL WINDS DOWN",
		"The bunting comes down in Pieburg and the last dancers stumble home, pockets full of pie. The Great Mosh Pit of Pieburg is already legend.")
	_story(gs, "FESTIVAL CALLED OFF",
		"The festival planned for Mudwick is cancelled. The crown refunds the preparations in full (150 gold, 80 food).")
	_check("wind-down/cancelled stories do not double-seed",
		_festival_rumors(hs).size() == 2)


func _test_thin_story_without_rumor_still_seeds() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# No festival_event — old save: the thin story still seeds.
	_story(gs, "GRAND FESTIVAL!",
		"Music, pies, dancing in the mud! Oldtown celebrates the crown's generosity.")
	var thin: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "court" \
				and String(r.get("text", "")) == "GRAND FESTIVAL!":
			thin.append(r)
	_check("thin fallback still seeds without a rich rumor", thin.size() == 1)


func _test_host_celebrates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var u: Dictionary = _spawn(gs, "gnomes")
	var uid := int(u.get("id", 0))
	var r: Dictionary = (_hold(hs, gs))[0]
	hs._on_heard(u, r, {})
	_check("host remembers the celebration",
		_recalled(u, "celebrated_festival", int(r.get("id", 0))) > 0.0)
	_check("host mood rises", conv.ruler_mood(uid) > 0.0)
	_check("host proud (victory -> proud)", _emotion(u) == "proud")


func _test_rival_sneers() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var u: Dictionary = _spawn(gs, "ogres")
	var uid := int(u.get("id", 0))
	var r: Dictionary = (_hold(hs, gs))[0]
	hs._on_heard(u, r, {})
	_check("rival remembers sneering",
		_recalled(u, "sneered_at_festival", int(r.get("id", 0))) > 0.0)
	_check("rival mood drops", conv.ruler_mood(uid) < 0.0)
	_check("rival sad (mocked -> sad)", _emotion(u) == "sad")


func _test_neutral_enjoys() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var u: Dictionary = _spawn(gs, "elves")
	var uid := int(u.get("id", 0))
	var r: Dictionary = (_hold(hs, gs))[0]
	hs._on_heard(u, r, {})
	_check("neutral notes the happy news",
		_recalled(u, "heard_festival", int(r.get("id", 0))) > 0.0)
	_check("neutral mildly pleased", conv.ruler_mood(uid) > 0.0)
	_check("neutral happy (helped -> happy)", _emotion(u) == "happy")


func _test_cancelled_grief() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var u: Dictionary = _spawn(gs, "gnomes")
	var uid := int(u.get("id", 0))
	gs.bus.festival_event.emit("cancelled", "Mudwick", "gnomes", 0)
	var r: Dictionary = (_festival_rumors(hs))[0]
	hs._on_heard(u, r, {})
	_check("host remembers the broken promise",
		_recalled(u, "festival_cancelled", int(r.get("id", 0))) > 0.0)
	_check("host mood drops", conv.ruler_mood(uid) < 0.0)
	_check("host sad (mocked -> sad)", _emotion(u) == "sad")


func _test_rival_cackles() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var u: Dictionary = _spawn(gs, "ogres")
	var uid := int(u.get("id", 0))
	gs.bus.festival_event.emit("cancelled", "Mudwick", "gnomes", 0)
	var r: Dictionary = (_festival_rumors(hs))[0]
	hs._on_heard(u, r, {})
	_check("rival remembers mocking",
		_recalled(u, "mocked_festival", int(r.get("id", 0))) > 0.0)
	_check("rival schadenfreude (mood up)", conv.ruler_mood(uid) > 0.0)
	_check("rival happy", _emotion(u) == "happy")


func _test_wound_down_afterglow() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var u: Dictionary = _spawn(gs, "gnomes")
	var uid := int(u.get("id", 0))
	gs.bus.festival_event.emit("wound_down", "Pieburg", "gnomes", 0)
	var r: Dictionary = (_festival_rumors(hs))[0]
	hs._on_heard(u, r, {})
	_check("host keeps the warm afterglow",
		_recalled(u, "festival_memory", int(r.get("id", 0))) > 0.0)
	_check("host mood warm", conv.ruler_mood(uid) > 0.0)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	# Emit before any citizens exist — no first knower, no double-hearing.
	var r: Dictionary = (_hold(hs, gs))[0]
	_check("no first knower without citizens", (r.get("knowers", []) as Array).is_empty())
	var calm: Dictionary = _spawn(gs, "gnomes")
	var wild: Dictionary = _spawn(gs, "gnomes", {"traits": {"unhinged": 1.0}})
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	var calm_mood = conv.ruler_mood(int(calm.get("id", 0)))
	var wild_mood = conv.ruler_mood(int(wild.get("id", 0)))
	_check("unhinged NPC celebrates harder than a calm one",
		wild_mood > calm_mood)


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var host_teller: Dictionary = _spawn(gs, "gnomes")
	var rival_teller: Dictionary = _spawn(gs, "ogres")
	var neutral_teller: Dictionary = _spawn(gs, "elves")
	var hr: Dictionary = (_hold(hs, gs))[0]
	gs.bus.festival_event.emit("cancelled", "Mudwick", "gnomes", 0)
	var cr: Dictionary = {}
	for r: Dictionary in _festival_rumors(hs):
		if String(r.get("fest_event", "")) == "cancelled":
			cr = r
	var held_host = hs._spread_motivation(host_teller, hr)
	_check("host boasts the triumph",
		int(held_host.get("cap_delta", 0)) == 1 \
		and float(held_host.get("heat_delta", 0.0)) > 0.0)
	var held_rival = hs._spread_motivation(rival_teller, hr)
	_check("rival buries the triumph",
		int(held_rival.get("cap_delta", 0)) == -1)
	var cancel_rival = hs._spread_motivation(rival_teller, cr)
	_check("rival gloats over the cancellation",
		int(cancel_rival.get("cap_delta", 0)) == 1 \
		and float(cancel_rival.get("heat_delta", 0.0)) > 0.0)
	var cancel_host = hs._spread_motivation(host_teller, cr)
	_check("host buries the cancellation",
		int(cancel_host.get("cap_delta", 0)) == -1)
	var held_neutral = hs._spread_motivation(neutral_teller, hr)
	_check("neutral just gossips",
		int(held_neutral.get("cap_delta", 0)) == 0)


func _test_kind_tables() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var u: Dictionary = _spawn(gs, "elves")
	var r: Dictionary = (_hold(hs, gs))[0]
	hs._on_heard(u, r, {})
	# Generic kind table: festival -> happy emotion for thin rumors.
	var thin: Dictionary = {"id": 9999, "kind": "festival", "text": "thin",
		"subject": "", "heat": 0.5}
	hs._generic_heard(u, thin)
	_check("thin festival news is happy", _emotion(u) == "happy")


func _test_memory_types_registered() -> void:
	var mem_cls = load("res://scripts/sim/memories.gd")
	for t: String in ["celebrated_festival", "festival_cancelled",
			"festival_memory", "sneered_at_festival", "mocked_festival",
			"heard_festival"]:
		_check("memory type registered: " + t, t in mem_cls.TYPES)
		_check("memory weight set: " + t,
			mem_cls.REL_WEIGHT.has(t))


func _test_heat_bars() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	var r: Dictionary = (_hold(hs, gs))[0]
	_check("held clears the ruler bar", float(r.get("heat", 0.0)) >= hs.RULER_HEAT)
	# PRESS_MIN_KNOWERS = 1 and the seed planted a host first knower.
	_check("held has a first knower", (r.get("knowers", []) as Array).size() >= 1)
	_check("held is press-eligible (Society Pages)",
		hs._press_eligible(r))
	gs.bus.festival_event.emit("cancelled", "Mudwick", "gnomes", 0)
	var cr: Dictionary = {}
	for fr: Dictionary in _festival_rumors(hs):
		if String(fr.get("fest_event", "")) == "cancelled":
			cr = fr
	_check("cancelled clears the ruler bar, not the press bar",
		float(cr.get("heat", 0.0)) >= hs.RULER_HEAT \
		and float(cr.get("heat", 0.0)) < hs.PRESS_HEAT)


func _test_old_save_fallback_generic() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var u: Dictionary = _spawn(gs, "elves")
	# Thin festival rumor (Gazette-seeded, no fest_event) -> generic path.
	var thin: Dictionary = {"id": 4242, "kind": "festival",
		"text": "GRAND FESTIVAL!", "subject": "", "heat": 0.6,
		"fest_town": "", "fest_event": ""}
	hs._on_heard(u, thin, {})
	_check("thin festival rumor routes generic (heard_rumor memory)",
		_recalled(u, "heard_rumor", 4242) > 0.0)
