extends SceneTree
## Cursing Gnomes — RECRUITS MUSTER trivia-feed tests (Jeremy 2026-10-08,
## wake rapid lane).
##
## The Gazette's NEWS_TRIVIA_BUCKETS "train" bucket was dormant: no sim
## feed ever published a story matching "training ...(\d+/\d+)" or
## "completed training", so RECRUITS MUSTER could never fire.
## GuildHiring._tick_training now reports each military graduation
## straight to the news desk.
##
## Day plan (tallies reset daily): D1 = threshold + civilian exclusion,
## D2 = bus-spam check + re-tick check, D3 = day reset, D4 = no
## self-trigger, D5 = no court no crash + queue drains.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_training_muster.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

var _passed := 0
var _failed := 0
var _failures: Array[String] = []

var _gs: GameState
var _court: SimRoyalCourt
var _hiring: GuildHiring
var _barracks: Dictionary
var _hall: Dictionary
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
	_hiring = GuildHiring.new(_gs)
	_gs.hiring = _hiring
	_gs.bus.gazette_story.connect(func(_s: Dictionary) -> void: _bus_hits[0] += 1)
	_barracks = _gs.add_building({"type": "barracks", "faction": "humans",
		"alive": true, "complete": true, "town_id": -1,
		"position": Vector2(500, 500)})
	_hall = _gs.add_building({"type": "town_hall", "faction": "humans",
		"alive": true, "complete": true, "town_id": -1,
		"position": Vector2(900, 500)})

	_test_day1_threshold_and_civilians()
	_test_day2_bus_spam_and_retick()
	_test_day3_reset()
	_test_day4_no_self_trigger()
	_test_day5_no_court_no_crash()

	print("Training muster tests: %d passed, %d failed" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: " + f)
	quit(1 if _failed > 0 else 0)


func _count_headline(h: String) -> int:
	var n := 0
	for s: Dictionary in _court.stories:
		if String(s.get("headline", "")) == h:
			n += 1
	return n


## Body of the most recent RECRUITS MUSTER story.
func _latest_muster_body() -> String:
	var body := ""
	for s: Dictionary in _court.stories:
		if String(s.get("headline", "")) == "RECRUITS MUSTER":
			body = String(s.get("story", s.get("body", "")))
	return body


## Queue one ready-to-graduate job on the building's training queue.
func _queue_ready(building: Dictionary, utype: String) -> void:
	var q: Array = building.get("train_queue", [])
	q.append({"unit_type": utype, "time_left": 0.0, "stall_n": 0, "cost": {}})
	building["train_queue"] = q


## Graduate one job through the real training path.
func _graduate(building: Dictionary, utype: String) -> void:
	_queue_ready(building, utype)
	_hiring._tick_training(0.016)


func _units_of(faction: String, job: String) -> int:
	return _gs.population.count_job(faction, job)


func _roll_day() -> void:
	_gs.day_number += 1
	_gs.bus.day_changed.emit(_gs.day_number, false)


## --- D1: threshold + civilian exclusion --------------------------------------

func _test_day1_threshold_and_civilians() -> void:
	var before := _count_headline("RECRUITS MUSTER")
	var soldiers_before := _units_of("humans", "soldier")
	for i: int in range(4):
		_graduate(_barracks, "soldier")
	_check("muster: 4 graduations spawn 4 soldiers",
		_units_of("humans", "soldier") == soldiers_before + 4)
	_check("muster: barracks queue drains after each graduation",
		(_barracks.get("train_queue", []) as Array).is_empty())
	_check("muster: 4 graduations stay below threshold (no muster)",
		_count_headline("RECRUITS MUSTER") == before)
	# Civilian graduations complete fine but do NOT feed the recruit bucket.
	var workers_before := _units_of("humans", "worker")
	_graduate(_hall, "worker")
	_graduate(_hall, "worker")
	_check("muster: 2 worker graduations spawn 2 workers",
		_units_of("humans", "worker") == workers_before + 2)
	_check("muster: hall queue drains after civilian graduation",
		(_hall.get("train_queue", []) as Array).is_empty())
	_check("muster: civilian graduations do not tally (still no muster)",
		_count_headline("RECRUITS MUSTER") == before)
	_graduate(_barracks, "archer")  # 5th military tally
	_check("muster: 5th military graduation fires RECRUITS MUSTER",
		_count_headline("RECRUITS MUSTER") == before + 1)
	var body := _latest_muster_body()
	_check("muster: body carries the rotation count",
		body.contains("5 training rotations completed"))
	_check("muster: body quotes a 'completed training' sample line",
		body.contains("completed training"))


## --- D2: no bus spam, no re-tick ----------------------------------------------

func _test_day2_bus_spam_and_retick() -> void:
	var bus_before: int = _bus_hits[0]
	var stories_before: int = _court.stories.size()
	var muster_before := _count_headline("RECRUITS MUSTER")
	_graduate(_barracks, "soldier")
	_check("muster: individual graduations never hit the bus",
		_bus_hits[0] == bus_before)
	_check("muster: 6th graduation adds no new aggregated story",
		_count_headline("RECRUITS MUSTER") == muster_before)
	_check("muster: court story count unchanged by a 6th graduation",
		_court.stories.size() == stories_before)


## --- D3: day reset -------------------------------------------------------------

func _test_day3_reset() -> void:
	_roll_day()
	var before := _count_headline("RECRUITS MUSTER")
	for i: int in range(4):
		_graduate(_barracks, "soldier")
	_check("muster: tallies reset at dawn (4 more, still no muster)",
		_count_headline("RECRUITS MUSTER") == before)
	_graduate(_barracks, "soldier")
	_check("muster: 5th graduation on the new day fires again",
		_count_headline("RECRUITS MUSTER") == before + 1)


## --- D4: aggregated stories never self-trigger ---------------------------------

func _test_day4_no_self_trigger() -> void:
	_roll_day()
	var before := _count_headline("RECRUITS MUSTER")
	# Publish the aggregated story's own text back through the desk: the
	# headline guard must refuse to tally it.
	_court.news_desk.report("RECRUITS MUSTER",
		"5 training rotations completed this week. Latest report: \"x\"")
	_check("muster: aggregated story never re-tallies itself",
		_count_headline("RECRUITS MUSTER") == before)


## --- D5: no court no crash ------------------------------------------------------

func _test_day5_no_court_no_crash() -> void:
	_gs.court_sys = null
	var soldiers_before := _units_of("humans", "soldier")
	_graduate(_barracks, "soldier")
	_check("muster: graduation works with no court (no crash)",
		_units_of("humans", "soldier") == soldiers_before + 1)
	_check("muster: queue still drains with no court",
		(_barracks.get("train_queue", []) as Array).is_empty())
