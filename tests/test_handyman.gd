extends SceneTree
## Cursing Gnomes — wandering handyman tribute event headless tests
## (Jeremy 2026-10-06).
##
## HTML CANDIDATE19 parity (fix79/index.html, jeremyHandymanTick):
## one-per-game flag, 10-minute grace for new games (skipped for old saves),
## day >= 3 + 10% daily roll, repair candidates (alive/complete/not-wall/
## hp < 90% max; player's faction first, then most-damaged), real HP repair,
## 40-wood lumber fallback, verbatim Gazette stories + player toast.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_handyman.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _toasts: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes wandering-handyman tests ===")
	_test_day_gate()
	_test_grace_gate()
	_test_done_never_refires()
	_test_roll_fires_exactly_once()
	_test_repair_pick_player_first()
	_test_repair_pick_most_damaged()
	_test_repair_exclusions()
	_test_repair_story_and_toast()
	_test_lumber_fallback()
	_test_town_name_used()
	_test_glyph_free()
	_test_save_load()
	_test_snapshot_restore()
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


## Fresh headless game: player = humans; handyman wired like World does.
## The 10-minute grace is skipped (tests set the clock to 0, like an old save).
func _make_game() -> GameState:
	_toasts.clear()
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])
	gs.court_sys = SimRoyalCourt.new(gs)
	gs.handyman = SimHandyman.new(gs)
	gs.handyman._started_msec = 0
	gs.bus.toast.connect(func(t: String) -> void: _toasts.append(t))
	return gs


func _bldg(gs: GameState, faction: String, btype: String, hp: float,
		max_hp: float, extra: Dictionary = {}) -> Dictionary:
	var rec := {
		"type": btype, "faction": faction, "town_id": 1,
		"position": Vector2(100, 100), "alive": true, "complete": true,
		"hp": hp, "max_hp": max_hp,
	}
	for k in extra.keys():
		rec[k] = extra[k]
	return gs.add_building(rec)


func _handyman_stories(gs: GameState) -> Array:
	var out: Array = []
	for s in gs.court_sys.stories:
		if String(s.get("headline", "")) == SimHandyman.HEADLINE:
			out.append(s)
	return out


## Day gate: nothing fires before day 3 (HTML: dayNumber < 3 -> return).
func _test_day_gate() -> void:
	var gs := _make_game()
	_bldg(gs, "humans", "house", 100.0, 1000.0)
	seed(20261006)
	for i in range(60):
		gs.handyman._on_day(2, false)
	_check("no fire before day 3", not gs.handyman._done)
	_check("no stories before day 3", _handyman_stories(gs).is_empty())
	gs.queue_free()


## Grace gate: a fresh instance (real new game) blocks the roll for 10 min.
func _test_grace_gate() -> void:
	var gs := _make_game()
	gs.handyman._started_msec = Time.get_ticks_msec()  # new-game clock
	_bldg(gs, "humans", "house", 100.0, 1000.0)
	seed(20261006)
	for i in range(120):
		gs.handyman._on_day(10 + i, false)
	_check("grace blocks a fresh game", not gs.handyman._done)
	gs.handyman._started_msec = 0  # old save: no clock -> gate skipped
	seed(20261006)
	for i in range(400):
		gs.handyman._on_day(10 + i, false)
		if gs.handyman._done:
			break
	_check("old save (no clock) skips grace", gs.handyman._done)
	gs.queue_free()


## One-per-game: the flag blocks every later attempt, roll or direct.
func _test_done_never_refires() -> void:
	var gs := _make_game()
	_bldg(gs, "humans", "house", 100.0, 1000.0)
	_check("first fire repairs", gs.handyman._fire() == "repair")
	_check("done set", gs.handyman._done)
	seed(20261006)
	for i in range(120):
		gs.handyman._on_day(3 + i, false)
	_check("still done after 120 days", gs.handyman._done)
	_check("exactly one story", _handyman_stories(gs).size() == 1)
	_check("direct refire refused", gs.handyman._fire() == "")
	gs.queue_free()


## The 10% daily roll fires at most once per game (seeded, deterministic).
func _test_roll_fires_exactly_once() -> void:
	var gs := _make_game()
	_bldg(gs, "humans", "house", 100.0, 1000.0)
	seed(20261006)
	for i in range(400):
		gs.handyman._on_day(3 + i, false)
	_check("roll fired within 400 days", gs.handyman._done)
	_check("roll fired exactly once", _handyman_stories(gs).size() == 1)
	gs.queue_free()


## Player's faction repairs first, even when less damaged (HTML mine-first).
func _test_repair_pick_player_first() -> void:
	var gs := _make_game()
	var mine: Dictionary = _bldg(gs, "humans", "house", 800.0, 1000.0)
	var theirs: Dictionary = _bldg(gs, "gnomes", "house", 100.0, 1000.0)
	_check("repair path", gs.handyman._fire() == "repair")
	_check("player building restored", float(mine.get("hp", 0.0)) == 1000.0)
	_check("other faction untouched", float(theirs.get("hp", 0.0)) == 100.0)
	gs.queue_free()


## Within one faction, the most-damaged building is picked (HTML frac sort).
func _test_repair_pick_most_damaged() -> void:
	var gs := _make_game()
	var mild: Dictionary = _bldg(gs, "humans", "house", 700.0, 1000.0)
	var wreck: Dictionary = _bldg(gs, "humans", "farm", 150.0, 1000.0)
	gs.handyman._fire()
	_check("most damaged repaired", float(wreck.get("hp", 0.0)) == 1000.0)
	_check("milder damage left alone", float(mild.get("hp", 0.0)) == 700.0)
	gs.queue_free()


## Walls, incomplete, dead, and nearly-healthy buildings are excluded
## (HTML: "he fixes homes, not battlements"; hp >= 90% skipped).
func _test_repair_exclusions() -> void:
	var gs := _make_game()
	_bldg(gs, "humans", "wall", 50.0, 1000.0)
	_bldg(gs, "humans", "house", 50.0, 1000.0, {"complete": false})
	_bldg(gs, "humans", "house", 50.0, 1000.0, {"alive": false})
	_bldg(gs, "humans", "house", 950.0, 1000.0)
	_check("exclusions fall through to lumber", gs.handyman._fire() == "lumber")
	_check("wood granted instead", gs.resources.get_amount("humans", "wood") >= 40.0)
	gs.queue_free()


## Repair publishes the verbatim Gazette story + player toast (HTML
## _jhGazNews + systemMsg); the story lands in the Local Heroes section.
func _test_repair_story_and_toast() -> void:
	var gs := _make_game()
	seed(4242)
	_bldg(gs, "humans", "house", 400.0, 1000.0)
	gs.handyman._fire()
	var stories := _handyman_stories(gs)
	_check("one story published", stories.size() == 1)
	var s: Dictionary = stories[0]
	_check("verbatim headline", String(s.get("headline", "")) == "THE WANDERING HANDYMAN")
	_check("Local Heroes section", String(s.get("section", "")) == "Local Heroes")
	var body := String(s.get("body", ""))
	_check("story names Jeremy", body.contains("Jeremy"))
	_check("story names the building", body.contains("House"))
	# Template 1 reports the exact wear patched (400 -> 1000 = 600 points).
	if body.contains("points of wear"):
		_check("wear count is exact", body.contains("600 points of wear"))
	_check("toast emitted", _toasts.size() == 1)
	_check("toast is the repair line",
		String(_toasts[0]).contains("free of charge"))
	gs.queue_free()


## Nothing broken: +40 wood to the player faction + verbatim lumber story.
func _test_lumber_fallback() -> void:
	var gs := _make_game()
	var before: float = gs.resources.get_amount("humans", "wood")
	_check("lumber path", gs.handyman._fire() == "lumber")
	_check("40 wood granted",
		gs.resources.get_amount("humans", "wood") == before + 40.0)
	var stories := _handyman_stories(gs)
	_check("lumber story published", stories.size() == 1)
	_check("lumber story text",
		String(stories[0].get("body", "")).contains("seasoned lumber"))
	_check("lumber toast", String(_toasts[0]).contains("seasoned lumber"))
	gs.queue_free()


## The repair story names the town that was actually repaired.
func _test_town_name_used() -> void:
	var gs := _make_game()
	gs.towns[7] = {"name": "Testville", "faction": "humans"}
	_bldg(gs, "humans", "house", 400.0, 1000.0, {"town_id": 7})
	gs.handyman._fire()
	var stories := _handyman_stories(gs)
	_check("town named in story",
		String(stories[0].get("body", "")).contains("Testville"))
	gs.queue_free()


## Standing glyph rule: published stories must be clean for the phone
## newspaper (publish_story sanitizes; assert the stored copy is clean).
func _test_glyph_free() -> void:
	var gs := _make_game()
	seed(777)
	_bldg(gs, "humans", "house", 400.0, 1000.0)
	gs.handyman._fire()
	var clean := true
	for s in _handyman_stories(gs):
		for key in ["headline", "body"]:
			var t := String(s.get(key, ""))
			for i in range(t.length()):
				if t.unicode_at(i) > 0x2500:
					clean = false
	_check("stories are glyph-free", clean)
	gs.queue_free()


## Save/load: the one-per-game flag persists; the clock is NOT restored
## (old saves skip the grace gate, HTML-verbatim).
func _test_save_load() -> void:
	var gs := _make_game()
	_bldg(gs, "humans", "house", 400.0, 1000.0)
	gs.handyman._fire()
	var data: Dictionary = gs.handyman.to_dict()
	_check("done persisted", bool(data.get("done", false)))
	var gs2 := _make_game()
	gs2.handyman.from_dict(data)
	_check("done restored", gs2.handyman._done)
	_check("clock not restored (old-save rule)", gs2.handyman._started_msec == 0)
	seed(20261006)
	for i in range(120):
		gs2.handyman._on_day(3 + i, false)
	_check("no refire after load", _handyman_stories(gs2).is_empty())
	var gs3 := _make_game()
	gs3.handyman.from_dict({})
	_check("fresh save data stays unfired", not gs3.handyman._done)
	gs.queue_free()
	gs2.queue_free()
	gs3.queue_free()


## Full SaveSystem round-trip: the flag survives snapshot -> restore.
func _test_snapshot_restore() -> void:
	var gs := _make_game()
	_bldg(gs, "humans", "house", 400.0, 1000.0)
	gs.handyman._fire()
	var data: Dictionary = SaveSystem.snapshot(gs)
	_check("handyman key in snapshot",
		bool((data.get("handyman", {}) as Dictionary).get("done", false)))
	var gs2 := _make_game()
	_check("restore ok", SaveSystem.restore(gs2, data))
	_check("done restored via snapshot", gs2.handyman._done)
	# The Chronicle itself is restored too (1 story); the flag must prevent
	# any NEW firing across 120 more days.
	_check("story restored with the save", _handyman_stories(gs2).size() == 1)
	seed(20261006)
	for i in range(120):
		gs2.handyman._on_day(3 + i, false)
	_check("no refire after snapshot restore", _handyman_stories(gs2).size() == 1)
	gs.queue_free()
	gs2.queue_free()
