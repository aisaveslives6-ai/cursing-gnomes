extends SceneTree
## Cursing Gnomes — founding-beat headless tests (Jeremy 2026-10-09 wake).
##
## The founding beat: every new game opens with a Gazette founding story
## (name-roast included), a Messenger welcome DM from the Civic Advisor
## (first directive), and a toast. Fires once, on the first day_changed
## (day 1 -> 2); old saves (day > 2) go silent; DM degrades gracefully
## when no cabinet adviser is alive or no phone is wired.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_founding.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

class FakePhone extends RefCounted:
	var dms: Array = []
	func npc_message(unit_id: int, text: String) -> void:
		dms.append({"id": unit_id, "text": text})


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _toasts: Array = []
var _phone: FakePhone
var _founding_ref = null  # keeps unparented SimFounding instances alive


func _initialize() -> void:
	print("=== Cursing Gnomes founding-beat tests ===")
	_test_fires_on_first_day_change()
	_test_story_tokens()
	_test_dm_to_civic_adviser()
	_test_adviser_fallback_order()
	_test_no_adviser_still_story()
	_test_no_phone_still_story()
	_test_old_save_silent()
	_test_no_refire()
	_test_toast_names_town()
	_test_ascii_only()
	_test_save_load_roundtrip()
	_test_ruler_name_fallback()
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


## Fresh headless game: player = humans, ruler 'ass', one town Greenvale.
func _make_game() -> Dictionary:
	_toasts.clear()
	_phone = FakePhone.new()
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.ruler_name = "ass"
	gs.towns[1] = {"name": "Greenvale", "faction": "humans"}
	gs.court_sys = SimRoyalCourt.new(gs)
	gs.phone_sys = _phone
	gs.bus.toast.connect(func(t: String) -> void: _toasts.append(t))
	var founding := SimFounding.new(gs)
	gs.founding = founding
	return {"gs": gs, "founding": founding}


func _stories(gs: GameState) -> Array:
	var out: Array = []
	for s in gs.court_sys.stories:
		if String(s.get("headline", "")) == SimFounding.HEADLINE:
			out.append(s)
	return out


func _adviser(gs: GameState, job: String) -> Dictionary:
	return gs.add_unit({"faction": "humans", "job": job, "town_id": 1,
		"position": Vector2(100, 100), "alive": true,
		"hp": 100.0, "max_hp": 100.0})


## Fires once on the first day change (day 2), headline exact.
func _test_fires_on_first_day_change() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	gs.bus.day_changed.emit(2, false)
	_check("fires: one story", _stories(gs).size() == 1)


## Story body carries town, faction pretty name, ruler verbatim (no strip).
func _test_story_tokens() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	gs.bus.day_changed.emit(2, false)
	var body := String(_stories(gs)[0].get("body", ""))
	_check("story: town named", body.contains("Greenvale"))
	_check("story: faction named", body.contains("Humans"))
	_check("story: ruler verbatim", body.contains("ass"))


## The DM goes to the Civic Advisor's unit id, in-voice with the ruler name.
func _test_dm_to_civic_adviser() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	var adv := _adviser(gs, "advisor_civic")
	gs.bus.day_changed.emit(2, false)
	_check("dm: sent once", _phone.dms.size() == 1)
	_check("dm: to civic adviser",
		_phone.dms.size() == 1 and int(_phone.dms[0]["id"]) == int(adv["id"]))
	_check("dm: names ruler",
		_phone.dms.size() == 1 and String(_phone.dms[0]["text"]).contains("ass"))
	_check("dm: names town",
		_phone.dms.size() == 1 and String(_phone.dms[0]["text"]).contains("Greenvale"))


## Cabinet fallback: civic dead/missing -> economy -> war -> guild master.
func _test_adviser_fallback_order() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	var war := _adviser(gs, "advisor_war")
	var gm := _adviser(gs, "guild_master")
	gs.bus.day_changed.emit(2, false)
	_check("dm: falls back to war adviser",
		_phone.dms.size() == 1 and int(_phone.dms[0]["id"]) == int(war["id"]))
	_check("dm: not guild master when war alive",
		_phone.dms.size() == 1 and int(_phone.dms[0]["id"]) != int(gm["id"]))


## No adviser alive: no crash, no DM, story still fires.
func _test_no_adviser_still_story() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	gs.bus.day_changed.emit(2, false)
	_check("no adviser: story fires", _stories(gs).size() == 1)
	_check("no adviser: no dm", _phone.dms.is_empty())


## No phone wired: no crash, story still fires.
func _test_no_phone_still_story() -> void:
	_toasts.clear()
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.ruler_name = "ass"
	gs.towns[1] = {"name": "Greenvale", "faction": "humans"}
	gs.court_sys = SimRoyalCourt.new(gs)
	gs.founding = SimFounding.new(gs)  # phone_sys left null
	_founding_ref = gs.founding  # keep alive: the day_changed signal holds it
	gs.bus.day_changed.emit(2, false)
	_check("no phone: story fires", _stories(gs).size() == 1)


## Old save (first observed day > 2): silent, marked done.
func _test_old_save_silent() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	gs.bus.day_changed.emit(5, false)
	_check("old save: no story", _stories(gs).is_empty())
	_check("old save: no dm", _phone.dms.is_empty())
	gs.bus.day_changed.emit(6, false)
	_check("old save: stays silent", _stories(gs).is_empty())


## One-per-game: a second day change fires nothing new.
func _test_no_refire() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	_adviser(gs, "advisor_civic")
	gs.bus.day_changed.emit(2, false)
	gs.bus.day_changed.emit(3, false)
	_check("refire: still one story", _stories(gs).size() == 1)
	_check("refire: still one dm", _phone.dms.size() == 1)
	_check("refire: still one toast", _toasts.size() == 1)


## Toast points at the town and the Gazette.
func _test_toast_names_town() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	gs.bus.day_changed.emit(2, false)
	_check("toast: fired", _toasts.size() == 1)
	_check("toast: names town",
		_toasts.size() == 1 and String(_toasts[0]).contains("Greenvale"))
	_check("toast: points at gazette",
		_toasts.size() == 1 and String(_toasts[0]).contains("Gazette"))


func _is_ascii(s: String) -> bool:
	for i in range(s.length()):
		if s.unicode_at(i) > 127:
			return false
	return true


## ASCII only: Gazette + toast sanitizers strip the rest for the phone paper.
func _test_ascii_only() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	_adviser(gs, "advisor_civic")
	gs.bus.day_changed.emit(2, false)
	var body := String(_stories(gs)[0].get("body", ""))
	_check("ascii: story", _is_ascii(body))
	_check("ascii: dm", _is_ascii(String(_phone.dms[0]["text"])))
	_check("ascii: toast", _is_ascii(String(_toasts[0])))


## Save/load: done flag survives; an unfired beat restores unfired.
func _test_save_load_roundtrip() -> void:
	var g := _make_game()
	var gs: GameState = g["gs"]
	var founding = g["founding"]
	gs.bus.day_changed.emit(2, false)
	var data: Dictionary = founding.to_dict()
	_check("save: done after fire", bool(data.get("done", false)))
	var f2 := SimFounding.new(gs)
	f2.from_dict(data)
	gs.bus.day_changed.emit(3, false)
	_check("load: done stays done", _stories(gs).size() == 1)
	var g3 := _make_game()
	var gs3: GameState = g3["gs"]
	var f3 = g3["founding"]
	f3.from_dict({"done": false})
	gs3.bus.day_changed.emit(2, false)
	_check("load: unfired fires", _stories(gs3).size() == 1)


## Blank ruler name falls back to "sire" (never empty).
func _test_ruler_name_fallback() -> void:
	_toasts.clear()
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.towns[1] = {"name": "Greenvale", "faction": "humans"}
	gs.court_sys = SimRoyalCourt.new(gs)
	gs.founding = SimFounding.new(gs)
	_founding_ref = gs.founding  # keep alive: the day_changed signal holds it
	gs.bus.day_changed.emit(2, false)
	var body := String(_stories(gs)[0].get("body", ""))
	_check("ruler fallback: sire", body.contains("sire"))
