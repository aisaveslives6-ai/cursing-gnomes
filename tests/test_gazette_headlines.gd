extends SceneTree
## Cursing Gnomes — Gazette headline-coverage tests (Jeremy 2026-10-06).
## HTML parity (fix79/index.html gazNews call sites): every story type the
## HTML can publish must be publishable in the port under the same trigger.
##
## Covers the gaps filled by the 2026-10-06 headline audit:
##   - ROYAL WORKS (wall-policy Raise answer)
##   - FESTIVAL CALLED OFF (festival cancellation)
##   - FESTIVAL WINDS DOWN (day after a festival)
##   - NEWS_TRIVIA_BUCKETS aggregation (PETTY CRIME WAVE, A GENERATION
##     RISES, and the dormant-bucket safety behavior)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gazette_headlines.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

var _passed := 0
var _failed := 0
var _failures: Array[String] = []

var _gs: GameState
var _court: SimRoyalCourt


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

	_test_royal_works()
	_test_festival_called_off()
	_test_festival_winds_down()
	_test_trivia_petty_crime()
	_test_trivia_generation_rises()
	_test_trivia_day_resets()
	_test_trivia_no_self_trigger()
	_test_trivia_depot_logjam()
	_test_trivia_raiders_probe()
	_test_headlines_glyph_free()

	print("Gazette headline tests: %d passed, %d failed" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: " + f)
	quit(1 if _failed > 0 else 0)


func _headlines() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in _court.stories:
		out.append(String(s.get("headline", "")))
	return out


func _count_headline(h: String) -> int:
	var n := 0
	for x: String in _headlines():
		if x == h:
			n += 1
	return n


## --- ROYAL WORKS ---------------------------------------------------------------

## HTML: gazNews('ROYAL WORKS', ...) on the wall-policy "Raise" answer.
func _test_royal_works() -> void:
	var before := _count_headline("ROYAL WORKS")
	_gs.bus.wall_answer.emit("Greenvale", true)
	_check("royal works: raise publishes ROYAL WORKS",
		_count_headline("ROYAL WORKS") == before + 1)
	var story: Dictionary = _court.stories.back()
	_check("royal works: names the region",
		"Greenvale" in String(story.get("body", "")))
	_gs.bus.wall_answer.emit("Greenvale", false)
	_check("royal works: skip publishes nothing",
		_count_headline("ROYAL WORKS") == before + 1)


## --- FESTIVAL CALLED OFF -------------------------------------------------------

## HTML festCancel: gazNews('FESTIVAL CALLED OFF', ...) with full refund.
func _test_festival_called_off() -> void:
	var pf: String = _gs.player_faction
	_gs.resources.add_resource(pf, "gold", 1000.0)
	_gs.resources.add_resource(pf, "food", 1000.0)
	_court.policies.state["festivals"].append({
		"id": 42, "town_id": -1, "town": "Testville",
		"day_abs": _gs.day_number + 3, "gold": 150.0, "food": 80.0})
	var before := _count_headline("FESTIVAL CALLED OFF")
	var ok: bool = _court.policies.cancel_festival(42)
	_check("festival called off: cancel succeeds", ok)
	_check("festival called off: story published",
		_count_headline("FESTIVAL CALLED OFF") == before + 1)
	var story: Dictionary = _court.stories.back()
	_check("festival called off: names town and refund",
		"Testville" in String(story.get("body", ""))
		and "150" in String(story.get("body", ""))
		and "80" in String(story.get("body", "")))


## --- FESTIVAL WINDS DOWN -------------------------------------------------------

## HTML: gazNews('FESTIVAL WINDS DOWN', ...) when the festival closes.
func _test_festival_winds_down() -> void:
	var pf: String = _gs.player_faction
	_gs.resources.add_resource(pf, "gold", 1000.0)
	_gs.resources.add_resource(pf, "food", 1000.0)
	_gs.day_number = 5
	_court.policies.state["last_festival_day"] = _gs.day_number - 1
	_court.policies.state["last_festival_town"] = "Testville"
	_court.policies.state["winddown_day"] = 0
	var before := _count_headline("FESTIVAL WINDS DOWN")
	_court.policies.daily_tick()
	_check("festival winds down: story published day after",
		_count_headline("FESTIVAL WINDS DOWN") == before + 1)
	var story: Dictionary = _court.stories.back()
	_check("festival winds down: names the town",
		"Testville" in String(story.get("body", "")))
	_court.policies.daily_tick()
	_check("festival winds down: fires once",
		_count_headline("FESTIVAL WINDS DOWN") == before + 1)


## --- NEWS_TRIVIA_BUCKETS -------------------------------------------------------

## Feed a raw trivia report through the bus (HTML gazNewsFromText gate).
func _feed_trivia(headline: String, body: String) -> void:
	_gs.bus.gazette_story.emit({
		"day": _gs.day_number, "headline": headline, "body": body})


## HTML bucket: 3 pickpocket reports in a day -> PETTY CRIME WAVE.
func _test_trivia_petty_crime() -> void:
	var before := _count_headline("PETTY CRIME WAVE")
	_feed_trivia("PICKPOCKET STRIKES TESTVILLE!",
		"Rook lifted 12 gold from the market crowd and vanished into the alleys.")
	_feed_trivia("PICKPOCKET STRIKES TESTVILLE!",
		"Rook lifted 20 gold from the market crowd and vanished into the alleys.")
	_check("trivia: 2 pickpockets stay below threshold",
		_count_headline("PETTY CRIME WAVE") == before)
	_feed_trivia("PICKPOCKET STRIKES TESTVILLE!",
		"Rook lifted 8 gold from the market crowd and vanished into the alleys.")
	_check("trivia: 3rd pickpocket escalates to PETTY CRIME WAVE",
		_count_headline("PETTY CRIME WAVE") == before + 1)
	var story: Dictionary = _court.stories.back()
	_check("trivia: aggregate cites a verbatim sample",
		"Latest report:" in String(story.get("body", ""))
		and "3 pickpocketings" in String(story.get("body", "")))


## HTML bucket: 5 grown-up reports in a day -> A GENERATION RISES.
func _test_trivia_generation_rises() -> void:
	var before := _count_headline("A GENERATION RISES")
	for i: int in range(4):
		_feed_trivia("GROWN UP", "Kid%d has grown up and is ready to work." % i)
	_check("trivia: 4 grown-ups stay below threshold",
		_count_headline("A GENERATION RISES") == before)
	_feed_trivia("GROWN UP", "Kid4 has grown up and is ready to work.")
	_check("trivia: 5th grown-up escalates to A GENERATION RISES",
		_count_headline("A GENERATION RISES") == before + 1)


## HTML: tallies reset each day — 4 yesterday + 1 today never escalates.
func _test_trivia_day_resets() -> void:
	var before := _count_headline("A GENERATION RISES")
	for i: int in range(4):
		_feed_trivia("GROWN UP", "Dawn%d has grown up and is ready to work." % i)
	_gs.day_number += 1
	_gs.bus.day_changed.emit(_gs.day_number, false)
	_feed_trivia("GROWN UP", "Dusk0 has grown up and is ready to work.")
	_check("trivia: day rollover resets the tally",
		_count_headline("A GENERATION RISES") == before)


## Aggregated stories must not feed back into their own bucket.
func _test_trivia_no_self_trigger() -> void:
	var total_before: int = _court.stories.size()
	_gs.bus.gazette_story.emit({"day": _gs.day_number,
		"headline": "A GENERATION RISES",
		"body": "5 youngsters came of age and joined the workforce this week."})
	_check("trivia: aggregated story does not re-trigger",
		_court.stories.size() == total_before)


## HTML bucket: 4 vehicles parked at depots in a day -> DEPOT LOGJAM.
## Fed by SimArtillery._report_park_trivia (2026-10-09 lane) through the
## direct desk feed — no bus story, no rumor-mill whisper per vehicle.
func _test_trivia_depot_logjam() -> void:
	var before := _count_headline("DEPOT LOGJAM")
	var arty := SimArtillery.new(_gs)
	for i: int in range(3):
		arty._report_park_trivia({"type": "cannon", "faction": "gnomes"})
	_check("trivia: 3 parked vehicles stay below threshold",
		_count_headline("DEPOT LOGJAM") == before)
	arty._report_park_trivia({"type": "rocket", "faction": "gnomes"})
	_check("trivia: 4th parked vehicle escalates to DEPOT LOGJAM",
		_count_headline("DEPOT LOGJAM") == before + 1)
	var story: Dictionary = _court.stories.back()
	_check("trivia: depot aggregate cites the count + verbatim sample",
		"4 war machines parked at depots" in String(story.get("body", ""))
		and "Latest report:" in String(story.get("body", "")))
	# Null-safety: a world without a court skips silently, never crashes.
	var gs2 := GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans"])
	var arty2 := SimArtillery.new(gs2)
	arty2._report_park_trivia({"type": "cannon", "faction": "gnomes"})
	gs2.queue_free()
	_check("trivia: park report without court is a silent no-op", true)


## HTML bucket: 3 raid-probe sightings in a day -> RAIDERS PROBE OUR
## BORDERS (urgent). Fed by SimAIDirector._report_probe_trivia when a
## scout-phase war campaign starts (2026-10-09 lane) — the target's
## border watch spots the probing.
func _test_trivia_raiders_probe() -> void:
	var before := _count_headline("RAIDERS PROBE OUR BORDERS")
	var director := SimAIDirector.new(_gs)
	for i: int in range(2):
		director._report_probe_trivia("gnomes")
	_check("trivia: 2 probe sightings stay below threshold",
		_count_headline("RAIDERS PROBE OUR BORDERS") == before)
	director._report_probe_trivia("gnomes")
	_check("trivia: 3rd probe sighting escalates to RAIDERS PROBE OUR BORDERS",
		_count_headline("RAIDERS PROBE OUR BORDERS") == before + 1)
	var story: Dictionary = _court.stories.back()
	_check("trivia: probe aggregate is urgent + cites the count",
		bool(story.get("urgent", false))
		and "3 times" in String(story.get("body", "")))
	# The aggregated headline must not re-trigger its own bucket.
	var total: int = _court.stories.size()
	_gs.bus.gazette_story.emit({"day": _gs.day_number,
		"headline": "RAIDERS PROBE OUR BORDERS",
		"body": "Raiders spotted near our lands 3 times this week."})
	_check("trivia: probe aggregate does not re-trigger",
		_court.stories.size() == total)
	# Null-safety: a world without a court skips silently, never crashes.
	var gs2 := GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans"])
	var director2 := SimAIDirector.new(gs2)
	director2._report_probe_trivia("gnomes")
	gs2.queue_free()
	_check("trivia: probe report without court is a silent no-op", true)


## --- glyph hygiene ---------------------------------------------------------------

## Jeremy 2026-10-03 standing rule: published story text must be glyph-free
## (publish_story sanitizes; headlines must come out clean).
func _test_headlines_glyph_free() -> void:
	var GazetteScript := load("res://scripts/sim/gazette.gd")
	for s: Dictionary in _court.stories:
		var h := String(s.get("headline", ""))
		if h in ["ROYAL WORKS", "FESTIVAL CALLED OFF", "FESTIVAL WINDS DOWN",
				"PETTY CRIME WAVE", "A GENERATION RISES",
				"DEPOT LOGJAM", "RAIDERS PROBE OUR BORDERS"]:
			_check("glyphs: headline clean: " + h,
				h == GazetteScript.sanitize_story_text(h))
			var clean := true
			for i: int in h.length():
				if h.unicode_at(i) > 0x2500:
					clean = false
			_check("glyphs: no tofu in headline: " + h, clean)
