extends SceneTree
## Cursing Gnomes — Gazette story kind tests (Jeremy 2026-10-07).
##
## Root cause fix: SimAIDirector._gazette() hardcoded kind "war" for every
## story, so peacetime news (foundry, armament, famine) seeded kind="war"
## rumors — the rumors app showed WAR TALK on them, they overheated at
## war-heat 1.0, and NPCs ran the war-news reaction path for non-war news.
## _gazette() now takes a kind param (default "war"); the five peacetime
## call sites pass their real kind ("news" / "disaster").
##
## Covers:
##   - behavior: _gazette emits the right kind/heat end-to-end through the
##     bus -> SimHearsay._on_story -> seeded rumor chain
##   - backward compat: the two-arg form still seeds kind "war" (the 11
##     true-war call sites are untouched)
##   - source truth: every _gazette call site in ai_director.gd carries
##     the expected kind (catches a call site losing its kind arg)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gazette_kind.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _harness() -> Array:
	var gs := GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.player_faction = "gnomes"
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	var director := SimAIDirector.new(gs)
	return [gs, phone.hearsay, director]


func _rumor_by_text(hs, text: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("text", "")) == text:
			return r
	return {}


func _initialize() -> void:
	print("=== Cursing Gnomes gazette kind tests ===")
	_test_default_two_arg_is_war()
	_test_famine_kinds()
	_test_industry_kinds()
	_test_source_call_sites()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The 11 true-war call sites use the unchanged two-arg form.
func _test_default_two_arg_is_war() -> void:
	var parts := _harness()
	var hs = parts[1]
	var director: SimAIDirector = parts[2]
	director._gazette("WAR DRUMS", "The drums beat.")
	var r := _rumor_by_text(hs, "WAR DRUMS")
	_check("default two-arg story seeds a rumor", not r.is_empty())
	_check("default two-arg kind is war", String(r.get("kind", "")) == "war")
	_check("war story heat is 1.0", float(r.get("heat", 0.0)) == 1.0)


## FAMINE! / FOOD SHORTAGE seed disaster rumors (0.85 heat, DISASTER tag).
func _test_famine_kinds() -> void:
	var parts := _harness()
	var hs = parts[1]
	var director: SimAIDirector = parts[2]
	director._gazette("FAMINE!", "The humans are starving.", "disaster")
	director._gazette("FOOD SHORTAGE", "Granaries run low.", "disaster")
	var r1 := _rumor_by_text(hs, "FAMINE!")
	var r2 := _rumor_by_text(hs, "FOOD SHORTAGE")
	_check("famine seeds a rumor", not r1.is_empty())
	_check("famine kind is disaster", String(r1.get("kind", "")) == "disaster")
	_check("famine heat is 0.85", absf(float(r1.get("heat", 0.0)) - 0.85) < 0.001)
	_check("shortage seeds a rumor", not r2.is_empty())
	_check("shortage kind is disaster", String(r2.get("kind", "")) == "disaster")
	_check("shortage is not war", String(r2.get("kind", "")) != "war")


## FOUNDRY ONLINE / armament news seed news rumors (NEWS tag, not WAR TALK).
func _test_industry_kinds() -> void:
	var parts := _harness()
	var hs = parts[1]
	var director: SimAIDirector = parts[2]
	director._gazette("FOUNDRY ONLINE", "The gnomes rushed a foundry online!", "news")
	director._gazette("Smiths hammer through the night", "Arming up.", "news")
	var r1 := _rumor_by_text(hs, "FOUNDRY ONLINE")
	var r2 := _rumor_by_text(hs, "Smiths hammer through the night")
	_check("foundry seeds a rumor", not r1.is_empty())
	_check("foundry kind is news", String(r1.get("kind", "")) == "news")
	_check("foundry is not war", String(r1.get("kind", "")) != "war")
	_check("armament seeds a rumor", not r2.is_empty())
	_check("armament kind is news", String(r2.get("kind", "")) == "news")
	_check("armament is not war", String(r2.get("kind", "")) != "war")


## Source-level: every _gazette call site carries its intended kind.
## The peacetime headlines must pass "news"/"disaster"; the 11 war
## headlines must carry no non-war kind arg (default "war").
func _test_source_call_sites() -> void:
	var path := "res://scripts/sim/ai_director.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	_check("ai_director.gd source readable", f != null)
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	var peacetime := {
		"FAMINE!": "disaster",
		"FOOD SHORTAGE": "disaster",
		"FOUNDRY ONLINE": "news",
		"Smiths hammer through the night": "news",
		# Jeremy 2026-10-10 (P4 planned roads): AI road-building news —
		# peacetime, never war heat.
		"ROYAL ROADWORKS": "news",
	}
	var war_headlines: Array[String] = [
		"CITY MUSTER", "WAR DRUMS", "WAR!", "ADVISER'S WARNING",
		"REINFORCEMENTS", "SHADOW OF WAR", "ASSAULT", "COUNTER-RAID!",
		"WAR ENGINE RISING",
	]
	var calls: Array[int] = []
	var from := 0
	while true:
		var idx := src.find("_gazette(", from)
		if idx < 0:
			break
		from = idx + 1
		# Skip the helper's own definition line.
		if src.substr(idx, 80).find("headline: String") >= 0:
			continue
		calls.append(idx)
	_check("expected 16 gazette call sites", calls.size() == 16)
	var peacetime_seen := 0
	for idx: int in calls:
		var window := src.substr(idx, 500)
		var classified := false
		for headline: String in peacetime.keys():
			if window.find(headline) >= 0:
				peacetime_seen += 1
				_check(headline + " carries kind \"" + String(peacetime[headline]) + "\"",
					window.find("\"" + String(peacetime[headline]) + "\"") >= 0)
				classified = true
				break
		if classified:
			continue
		var is_war := false
		for headline: String in war_headlines:
			if window.find(headline) >= 0:
				is_war = true
				break
		_check("gazette call has a known headline", is_war)
		if is_war:
			_check("war call has no non-war kind arg",
				window.find("\"news\"") < 0 and window.find("\"disaster\"") < 0)
	_check("all 5 peacetime call sites found", peacetime_seen == 5)
