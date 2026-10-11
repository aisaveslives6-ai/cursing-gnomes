extends SceneTree
## Cursing Gnomes — BUILDING BOOM trivia-feed tests (Jeremy 2026-10-07,
## wake rapid lane).
##
## The Gazette's NEWS_TRIVIA_BUCKETS "build" bucket was dormant: no sim
## feed ever published a story matching "finished a ", so BUILDING BOOM
## could never fire. SimBuildings.tick_construction now reports each
## (non-wall) completion straight to the news desk.
##
## Day plan (tallies reset daily): D1 = threshold + wall exclusion,
## D2 = bus-spam check + re-tick check, D3 = day reset, D4 = no
## self-trigger, D5 = name fallback.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_building_boom.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

var _passed := 0
var _failed := 0
var _failures: Array[String] = []

var _gs: GameState
var _court: SimRoyalCourt
var _bs: SimBuildings
var _bus_hits := [0]


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		printerr("FAIL: " + test_name)


func _initialize() -> void:
	_gs = GameState.new()
	root.add_child(_gs)
	_gs.setup(["humans", "gnomes"])
	_court = SimRoyalCourt.new(_gs)
	_gs.court_sys = _court
	_bs = SimBuildings.new(_gs)
	_gs.bus.gazette_story.connect(func(_s: Dictionary) -> void: _bus_hits[0] += 1)

	_test_day1_threshold_and_walls()
	_test_day2_bus_spam_and_retick()
	_test_day3_reset()
	_test_day4_no_self_trigger()
	_test_day5_name_fallback()
	_test_no_court_no_crash()
	_test_glyph_free()

	print("Building boom tests: %d passed, %d failed" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: " + f)
	quit(1 if _failed > 0 else 0)


func _count_headline(h: String) -> int:
	var n := 0
	for s: Dictionary in _court.stories:
		if String(s.get("headline", "")) == h:
			n += 1
	return n


## Body of the most recent BUILDING BOOM story.
func _latest_boom_body() -> String:
	var body := ""
	for s: Dictionary in _court.stories:
		if String(s.get("headline", "")) == "BUILDING BOOM":
			body = String(s.get("story", s.get("body", "")))
	return body


## Minimal unbuilt building record; tick_construction only reads these
## fields plus the BUILDINGS def (build_time).
func _mk_building(btype: String, with_name: bool) -> Dictionary:
	var b := {"type": btype, "faction": "humans", "alive": true,
		"complete": false, "progress": 0.0, "max_hp": 100.0, "hp": 100.0,
		"position": Vector2(100, 100)}
	if with_name:
		b["name"] = "Misty " + btype.capitalize()
	return b


## Completes one building through the real construction path. Returns the
## tick_construction result.
func _complete(btype: String, with_name: bool = true) -> bool:
	return _bs.tick_construction(_mk_building(btype, with_name), 500.0, 1.0)


func _roll_day() -> void:
	_gs.day_number += 1
	_gs.bus.day_changed.emit(_gs.day_number, false)


## --- D1: threshold + wall exclusion ----------------------------------------------

func _test_day1_threshold_and_walls() -> void:
	var before := _count_headline("BUILDING BOOM")
	var bus_before: int = _bus_hits[0]
	_check("boom: completion returns true", _complete("farm"))
	_complete("farm")
	_complete("farm")
	_check("boom: 3 completions stay below threshold (no boom)",
		_count_headline("BUILDING BOOM") == before)
	_check("boom: wall completion returns true", _complete("wall"))
	_check("boom: wall does not tally (3 farms + wall: still no boom)",
		_count_headline("BUILDING BOOM") == before)
	_complete("farm")  # 4th real tally
	_check("boom: 4th completion fires BUILDING BOOM",
		_count_headline("BUILDING BOOM") == before + 1)
	var body := _latest_boom_body()
	_check("boom: body carries the completion count",
		body.contains("4 buildings completed"))
	_check("boom: body quotes a 'Finished a' sample line",
		body.contains("Finished a"))
	_check("boom: aggregated story reaches the bus once (Chronicle + mill)",
		_bus_hits[0] == bus_before + 1)


## --- D2: no per-completion bus spam + no double tally ------------------------------

func _test_day2_bus_spam_and_retick() -> void:
	_roll_day()
	var bus_before: int = _bus_hits[0]
	var b := _mk_building("farm", true)
	_check("boom: first tick completes", _bs.tick_construction(b, 500.0, 1.0))
	_check("boom: feed items do not emit bus.gazette_story (no rumor per farm)",
		_bus_hits[0] == bus_before)
	_check("boom: re-tick of a finished building returns false",
		not _bs.tick_construction(b, 500.0, 1.0))
	# Tally is 1 (re-tick added nothing): 2 more stays below threshold.
	_complete("farm")
	_complete("farm")
	_check("boom: re-tick did not double-tally (3 total: no boom)",
		_count_headline("BUILDING BOOM") == 1)


## --- D3: day rollover resets ----------------------------------------------------------

func _test_day3_reset() -> void:
	_roll_day()
	var before := _count_headline("BUILDING BOOM")
	_complete("farm")
	_complete("farm")
	_complete("farm")
	_roll_day()
	_complete("farm")
	_check("boom: day rollover resets the tally (3 + 1 across days: no boom)",
		_count_headline("BUILDING BOOM") == before)


## --- D4: aggregated story must not re-trigger its own bucket ----------------------------

func _test_day4_no_self_trigger() -> void:
	_roll_day()
	var before := _count_headline("BUILDING BOOM")
	for i: int in range(4):
		_complete("house")
	_check("boom: 4 completions fire exactly one BOOM (no self-trigger cascade)",
		_count_headline("BUILDING BOOM") == before + 1)
	_complete("house")
	_check("boom: tally reset after firing (5th is tally 1: no second boom)",
		_count_headline("BUILDING BOOM") == before + 1)


## --- D5: display-name fallback ------------------------------------------------------------

func _test_day5_name_fallback() -> void:
	_roll_day()
	var before := _count_headline("BUILDING BOOM")
	for i: int in range(4):
		_complete("lumber_camp", false)  # no "name" key: prettified type used
	_check("boom: fallback batch fires once",
		_count_headline("BUILDING BOOM") == before + 1)
	_check("boom: nameless buildings fall back to prettified type",
		_latest_boom_body().contains("Finished a lumber camp"))


## --- no court: silent skip -------------------------------------------------------------------

func _test_no_court_no_crash() -> void:
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans"])
	var bs2 := SimBuildings.new(gs2)
	var b := {"type": "farm", "faction": "humans", "alive": true,
		"complete": false, "progress": 0.0, "max_hp": 100.0, "hp": 100.0,
		"position": Vector2(50, 50)}
	_check("boom: completion works with no court (no crash)",
		bs2.tick_construction(b, 500.0, 1.0))
	gs2.free()


## --- glyph rule ---------------------------------------------------------------------------------

func _test_glyph_free() -> void:
	var bad := false
	for s: Dictionary in _court.stories:
		if String(s.get("headline", "")) != "BUILDING BOOM":
			continue
		var t: String = String(s.get("headline", "")) \
			+ String(s.get("story", s.get("body", "")))
		for i: int in t.length():
			if t.unicode_at(i) > 127:
				bad = true
	_check("boom: feed + aggregated story are ASCII-only (no iPhone tofu)",
		not bad)
