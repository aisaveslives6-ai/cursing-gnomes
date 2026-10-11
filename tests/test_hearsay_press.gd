extends SceneTree
## Cursing Gnomes — hearsay press-pass tests (Jeremy 2026-10-06).
##
## The rumor mill feeds the press: the hottest press-worthy rumor earns one
## Gazette story per day via SimRoyalCourt.publish_story, honestly labeled
## as tavern talk. Covers:
##  - hottest eligible rumor published (front page), marked published
##  - one story per day max (front-page scarcity)
##  - Gazette-born rumors never re-printed (no ping-pong)
##  - a rumor's own story never re-seeds a rumor (no loop)
##  - ambient life/misc chatter never qualifies
##  - front-page amplification: heat bump + readers join as knowers
##  - slur rumors print as "court" kind (scandals hit the front page)
##  - from_dict backfills the press schema on old saves
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_press.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


## Mimics SimRoyalCourt.publish_story: records the story AND emits
## bus.gazette_story, so the anti-loop path is exercised.
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


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay-press tests ===")
	_test_press_publishes_hottest()
	_test_press_tick_direct()
	_test_press_once_per_day()
	_test_press_skips_gazette_born()
	_test_no_loop_from_rumor_story()
	_test_press_ignores_ambient()
	_test_press_slur_kind_court()
	_test_from_dict_backfill_press()
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


func _new_hs(gs: GameState) -> Array:
	# Returns [hearsay, court]. Phone-less: _maybe_reach_ruler and the
	# Squabble paths guard phone == null, the press path needs court_sys.
	var hs = load("res://scripts/sim/hearsay.gd").new(gs)
	var court := MockCourt.new(gs)
	gs.court_sys = court
	return [hs, court]


func _spawn(gs: GameState, faction: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": {}})


func _test_press_publishes_hottest() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	var u2: Dictionary = _spawn(gs, "gnomes")
	for i in range(6):
		_spawn(gs, "gnomes")
	var wr: Dictionary = hs.seed_rumor(
		"WAR with the Ogres! The drums beat day and night.",
		"war", "ogres", 1.0)
	wr["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0))]
	var dr: Dictionary = hs.seed_rumor(
		"A dragon rampages through the realm!", "disaster", "dragon", 0.85)
	dr["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0))]
	hs.daily_tick()
	_check("press publishes exactly one story", court.stories.size() == 1)
	var s: Dictionary = court.stories[0] if not court.stories.is_empty() else {}
	_check("front page is the hottest rumor",
		String(s.get("headline", "")).contains("WAR with the Ogres"))
	_check("headline labeled as rumor mill",
		String(s.get("headline", "")).begins_with("RUMOR MILL: "))
	_check("story kind follows rumor kind", String(s.get("kind", "")) == "war")
	_check("rumor marked published", bool(wr.get("published", false)))
	_check("colder rumor not published", not bool(dr.get("published", false)))
	_check("readers joined the grapevine",
		(wr.get("knowers", []) as Array).size() >= 2)
	gs.queue_free()


func _test_press_tick_direct() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	for i in range(9):
		_spawn(gs, "gnomes")
	var wr: Dictionary = hs.seed_rumor(
		"WAR with the Elves! Arrows at dawn.", "war", "elves", 0.87)
	wr["knowers"] = [int(u1.get("id", 0))]
	hs._press_tick()
	_check("direct press tick publishes", court.stories.size() == 1)
	_check("front-page heat amplification",
		is_equal_approx(float(wr.get("heat", 0.0)), 0.95))
	_check("readers joined as knowers",
		(wr.get("knowers", []) as Array).size() >= 2)
	gs.queue_free()


func _test_press_once_per_day() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	for i in range(6):
		_spawn(gs, "gnomes")
	for spec in [["war", "ogres", "WAR with the Ogres!"], ["disaster", "quakex", "The ground shakes!"]]:
		var r: Dictionary = hs.seed_rumor(String(spec[2]), String(spec[0]),
			String(spec[1]), 1.0)
		r["knowers"] = [int(u1.get("id", 0))]
	hs.daily_tick()
	hs.daily_tick()  # same day — front page carries one rumor story a day
	_check("one story per day max", court.stories.size() == 1)
	gs.queue_free()


func _test_press_skips_gazette_born() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	# A real Gazette story (not from a rumor) becomes a rumor...
	gs.bus.gazette_story.emit({"headline": "WAR with the Ogres! Big!",
		"kind": "war", "story": "The crown declares."})
	var gr: Dictionary = {}
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "war":
			gr = r
	_check("gazette story seeded a rumor", not gr.is_empty())
	_check("gazette-born rumor flagged", bool(gr.get("from_gazette", false)))
	gr["knowers"] = [int(u1.get("id", 0))]  # otherwise eligible
	hs.daily_tick()
	_check("paper does not re-print its own stories",
		court.stories.is_empty())
	gs.queue_free()


func _test_no_loop_from_rumor_story() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	var wr: Dictionary = hs.seed_rumor(
		"WAR with the Undead! Spooky drums.", "war", "undead", 1.0)
	wr["knowers"] = [int(u1.get("id", 0))]
	var before: int = (hs.state["rumors"] as Array).size()
	hs._press_tick()  # mock emits gazette_story inside publish_story
	var after: int = (hs.state["rumors"] as Array).size()
	_check("rumor story does not re-seed a rumor", after == before)
	_check("exactly one story from the press", court.stories.size() == 1)
	hs.daily_tick()  # same day: no second printing
	_check("no second printing same day", court.stories.size() == 1)
	gs.queue_free()


func _test_press_ignores_ambient() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	var u2: Dictionary = _spawn(gs, "gnomes")
	var lr: Dictionary = hs.seed_rumor(
		"Heard the tavern keeper waters down the ale.", "life", "", 0.95)
	lr["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0))]
	var mr: Dictionary = hs.seed_rumor("Some misc talk.", "misc", "", 0.95)
	mr["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0))]
	hs.daily_tick()
	_check("ambient chatter never makes the paper", court.stories.is_empty())
	gs.queue_free()


func _test_press_slur_kind_court() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	# Euphemized condemnation line (reporters never quote the slur).
	var sr: Dictionary = hs.seed_rumor(
		"Spread the word: Grak is racist. Don't let them forget it.",
		"slur", "gnomes", 0.95)
	sr["knowers"] = [int(u1.get("id", 0))]
	hs._press_tick()
	_check("slur scandal makes the paper", court.stories.size() == 1)
	var s: Dictionary = court.stories[0] if not court.stories.is_empty() else {}
	_check("slur scandal prints as court kind",
		String(s.get("kind", "")) == "court")
	gs.queue_free()


func _test_from_dict_backfill_press() -> void:
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	# Pre-press-pass save schema: no published/from_gazette/last_press_day.
	hs.from_dict({"rumors": [{
		"id": 7, "text": "Old war talk.", "text_orig": "Old war talk.",
		"kind": "war", "subject": "ogres", "day": 3, "heat": 0.9,
		"knowers": [1], "reached_ruler": false, "distortions": 0,
	}], "seq": 8})
	var r: Dictionary = (hs.state["rumors"] as Array)[0]
	_check("backfill published=false", r.has("published")
		and not bool(r.get("published", true)))
	_check("backfill from_gazette=false", r.has("from_gazette")
		and not bool(r.get("from_gazette", true)))
	_check("backfill last_press_day=0",
		int(hs.state.get("last_press_day", -1)) == 0)
	gs.queue_free()
