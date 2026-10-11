extends SceneTree
## Cursing Gnomes — Town Watch lane tests (2026-10-09).
##
## Crime/justice dead-end repairs (body lane #1: playable & functional, no
## dead ends, no silent failures):
##   - the guard tiers promised in the Policies docstring get a real,
##     tappable Town Watch card (was: "Guard: None (0 on duty)" with no lever)
##   - a failed decree (broke treasury / anarchy) says why, honestly
##   - an unanswered crime with an empty watch publishes a throttled Gazette
##     story naming the fix
##   - the mayor's crimewave petition is reachable for one-town kingdoms
##     (one unanswered crime + empty watch), and live (real-time) crimes
##     count toward the daily tally
##   - no more "lifted 0 gold" pickpocket copy
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_town_watch.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes town-watch tests ===")
	_test_card_builds()
	_test_raise_militia()
	_test_broke_feedback()
	_test_anarchy_feedback()
	_test_disband()
	_test_gov_hint()
	_test_no_guard_story()
	_test_begging_petition()
	_test_live_crime_counts()
	_test_pickpocket_zero_gold()
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


## --- harness ------------------------------------------------------------------

func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	gs.towns[2] = {"id": 2, "name": "Gnomestad", "faction": "gnomes",
		"pos": Vector2(300, 0), "owner": "gnomes"}
	for r: String in ["gold", "food", "wood"]:
		gs.resources.add_resource("humans", r, 1000.0, true)
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)
	gs.phone_sys = phone
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	return {"gs": gs, "mind": mind, "phone": phone, "court": court, "ui": ui}


func _free(w: Dictionary) -> void:
	(w["ui"] as PhoneUI).queue_free()
	(w["gs"] as GameState).queue_free()


func _spawn(w: Dictionary, faction: String, job: String,
		town_id: int = 1) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, job, town_id,
		Vector2(100, 100))
	mind.ensure(u)
	return u


func _pol(w: Dictionary):
	return (w["court"] as SimRoyalCourt).policies


func _crime(w: Dictionary) -> SimCrime:
	return (w["court"] as SimRoyalCourt).crime


func _find_label(node: Node, text: String) -> Label:
	if node is Label and (node as Label).text == text:
		return node as Label
	for c: Node in node.get_children():
		var r: Label = _find_label(c, text)
		if r != null:
			return r
	return null


## The tier buttons render their name in a child Label (see
## _pol2_gov_button): walk up from the name label to the Button.
func _tier_button(ui: PhoneUI, tier_name: String) -> Button:
	var lab: Label = _find_label(ui, tier_name)
	if lab == null:
		return null
	var n: Node = lab
	while n != null and not (n is Button):
		n = n.get_parent()
	return n as Button


func _stories(court: SimRoyalCourt) -> Array:
	return court.news_feed()


func _count_headline(court: SimRoyalCourt, text: String) -> int:
	var n: int = 0
	for s: Dictionary in _stories(court):
		if String(s.get("headline", "")).find(text) >= 0:
			n += 1
	return n


func _body_has(court: SimRoyalCourt, text: String) -> bool:
	for s: Dictionary in _stories(court):
		if String(s.get("body", "")).find(text) >= 0:
			return true
	return false


func _petition(w: Dictionary) -> Dictionary:
	var court: SimRoyalCourt = w["court"]
	for p: Dictionary in court.open_petitions():
		if String(p.get("tpl", "")) == "mayor_crimewave" \
				and not bool(p.get("resolved", false)):
			return p
	return {}


## --- UI: the Town Watch card --------------------------------------------------

func _test_card_builds() -> void:
	var w := _new_world()
	var ui: PhoneUI = w["ui"]
	ui._show_policies()
	_check("Town Watch section exists", _find_label(ui, "Town Watch") != null)
	_check("Disband tier button", _tier_button(ui, "Disband") != null)
	_check("Militia tier button", _tier_button(ui, "Militia") != null)
	_check("Professional tier button", _tier_button(ui, "Professional") != null)
	_check("0 on duty readout", _find_label(ui, "0 on duty") != null)
	# Decree fee is honest: monarchy policyCost 0.5 -> 50g, not a flat 100g.
	_check("fee is policyCost-aware", _pol(w).guard_decree_fee() == 50)
	_check("militia flavor names the fee",
		_find_label(ui, "50g decree · 4 guards · 2g/day each") != null)
	_free(w)


func _test_raise_militia() -> void:
	var w := _new_world()
	var ui: PhoneUI = w["ui"]
	ui._show_policies()
	var b := _tier_button(ui, "Militia")
	_check("militia button found", b != null)
	b.pressed.emit()
	_check("guard tier raised", String(_pol(w).state.get("guard", "")) == "militia")
	_check("4 guards mustered", _pol(w).guard_units().size() == 4)
	_check("4 on duty readout", _find_label(ui, "4 on duty") != null)
	_free(w)


func _test_broke_feedback() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var ui: PhoneUI = w["ui"]
	var cur: float = gs.resources.get_amount("humans", "gold")
	gs.resources.add_resource("humans", "gold", -(cur - 40.0), true)
	ui._show_policies()
	var b := _tier_button(ui, "Professional")
	_check("professional button found", b != null)
	b.pressed.emit()
	_check("guard stays none when broke",
		String(_pol(w).state.get("guard", "")) == "none")
	_check("broke notice shown",
		_find_label(ui, "The 50g decree costs more than the treasury holds.") != null)
	_free(w)


func _test_anarchy_feedback() -> void:
	var w := _new_world()
	var ui: PhoneUI = w["ui"]
	_pol(w).state["anarchy"] = true
	ui._show_policies()
	var b := _tier_button(ui, "Militia")
	_check("militia button found", b != null)
	b.pressed.emit()
	_check("guard stays none under anarchy",
		String(_pol(w).state.get("guard", "")) == "none")
	_check("anarchy notice shown",
		_find_label(ui, "No guards under anarchy — restore order first.") != null)
	_free(w)


func _test_disband() -> void:
	var w := _new_world()
	var ui: PhoneUI = w["ui"]
	_check("direct raise works", _pol(w).set_guard("militia"))
	ui._show_policies()
	var b := _tier_button(ui, "Disband")
	_check("disband button found", b != null)
	b.pressed.emit()
	_check("watch disbanded",
		String(_pol(w).state.get("guard", "")) == "none")
	_check("guards stood down", _pol(w).guard_units().is_empty())
	_free(w)


func _test_gov_hint() -> void:
	# _show_gazette_policies is a section renderer (no _clear): one world per
	# assertion so the first build's labels don't linger in the tree.
	var w := _new_world()
	(w["ui"] as PhoneUI)._show_gazette_policies()
	_check("no-watch hint on government panel",
		_find_label(w["ui"], "No watch — raise tiers in Policies > Town Watch") != null)
	_free(w)
	var w2 := _new_world()
	_pol(w2).set_guard("militia")
	(w2["ui"] as PhoneUI)._show_gazette_policies()
	_check("hint hidden once a watch exists",
		_find_label(w2["ui"], "No watch — raise tiers in Policies > Town Watch") == null)
	_free(w2)


## --- sim: no-guard feedback ---------------------------------------------------

func _test_no_guard_story() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = _crime(w)
	var crook := _spawn(w, "humans", "worker")
	var rec: Dictionary = crime.ensure_rec(crook)
	rec["criminal"] = true
	crime.state["day"] = 1
	crime._guard_response(crook, gs.towns[1], rec)
	_check("empty watch publishes THE WATCH IS EMPTY",
		_count_headline(court, "THE WATCH IS EMPTY") == 1)
	_check("story names the fix",
		_body_has(court, "Policies app and raise a Town Watch"))
	crime._guard_response(crook, gs.towns[1], rec)
	_check("throttled: no second story same day",
		_count_headline(court, "THE WATCH IS EMPTY") == 1)
	crime.state["day"] = 4
	crime._guard_response(crook, gs.towns[1], rec)
	_check("re-fires after 3 days",
		_count_headline(court, "THE WATCH IS EMPTY") == 2)
	_free(w)


## --- sim: reachable crimewave petition ----------------------------------------

func _test_begging_petition() -> void:
	# One crime + empty watch -> the mayor begs for a watch (new).
	var w := _new_world()
	_spawn(w, "humans", "worker")
	_crime(w).state["crimesToday"] = 1
	_crime(w)._maybe_crime_petition("humans")
	var p := _petition(w)
	_check("1 crime + empty watch brings the mayor", not p.is_empty())
	_check("begging text mentions no watch",
		String(p.get("text", "")).find("no watch at all") >= 0)
	_free(w)
	# One crime + a guard on duty -> no petition.
	var w2 := _new_world()
	_spawn(w2, "humans", "worker")
	var g := _spawn(w2, "humans", "soldier")
	(g.get("mind", {}) as Dictionary)["is_guard"] = true
	_crime(w2).state["crimesToday"] = 1
	_crime(w2)._maybe_crime_petition("humans")
	_check("1 crime + guard on duty: no petition", _petition(w2).is_empty())
	_free(w2)
	# Two crimes still fires the classic crimewave (unchanged behavior).
	var w3 := _new_world()
	_spawn(w3, "humans", "worker")
	_crime(w3).state["crimesToday"] = 2
	_crime(w3)._maybe_crime_petition("humans")
	var p3 := _petition(w3)
	_check("2 crimes still fires crimewave", not p3.is_empty())
	_check("crimewave text kept",
		String(p3.get("text", "")).find("streets grow lawless") >= 0)
	_free(w3)
	# Zero crimes -> silence even with no watch.
	var w4 := _new_world()
	_spawn(w4, "humans", "worker")
	_crime(w4).state["crimesToday"] = 0
	_crime(w4)._maybe_crime_petition("humans")
	_check("0 crimes: no petition", _petition(w4).is_empty())
	_free(w4)


## --- sim: live crimes count ---------------------------------------------------

func _test_live_crime_counts() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var crime: SimCrime = _crime(w)
	var life := SimCrimeLife.new(gs, crime)
	var crook := _spawn(w, "humans", "worker")
	var victim := _spawn(w, "humans", "worker")
	crime.state["crimesToday"] = 0
	life._commit_steal(crook, victim)
	_check("live steal increments crimesToday",
		int(crime.state["crimesToday"]) == 1)
	_free(w)


## --- sim: no more "lifted 0 gold" ----------------------------------------------

func _test_pickpocket_zero_gold() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var crook := _spawn(w, "humans", "worker")
	var victim := _spawn(w, "humans", "worker")
	victim["coins"] = 0.0
	crook["coins"] = 50.0
	_crime(w)._commit("pickpocket", crook, gs.towns[1])
	_check("no 'lifted 0 gold' copy", not _body_has(court, "lifted 0 gold"))
	_check("broke-pocket copy used", _body_has(court, "not a single coin"))
	_free(w)
