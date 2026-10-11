extends SceneTree
## Cursing Gnomes — Army app on the phone (Jeremy 2026-10-06: the phone
## must control the ENTIRE game; army command was HUD-only).
##
## Covers:
##   - HOME_APPS contains the army app (label + resolvable icon texture),
##     appended last (settings at index 9, army at index 10).
##   - open_app("army") opens the army screen; back target is home;
##     back chevron returns home.
##   - The army screen shows the shared ArmyTab command surface
##     (summary + stance buttons) instead of a dead end.
##   - With no army system wired, the screen says so instead of crashing.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_phone_army.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes phone army-app tests ===")
	_test_army_app_registered()
	_test_army_app_opens()
	_test_army_app_no_army_safe()
	_test_army_screen_has_command_surface()
	_test_army_home_order_includes_army()
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


func _new_world(with_army: bool) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])  # player = humans
	var s := SimSeasons.new(gs)
	s.reset()
	gs.seasons = s
	if with_army:
		gs.army = SimArmy.new(gs)
		gs.set_meta("army", gs.army)
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "phone": phone, "court": court}


func _new_ui(w: Dictionary) -> PhoneUI:
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(w["gs"], w["phone"], w["court"])
	return ui


func _collect_texts(ui: PhoneUI) -> Array[String]:
	var out: Array[String] = []
	var stack: Array = [ui]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out.append((n as Label).text)
		if n is Button:
			out.append((n as Button).text)
		for c in n.get_children():
			stack.append(c)
	return out


func _army_entry() -> Array:
	for a in PhoneUI.HOME_APPS:
		if String(a[0]) == "army":
			return a
	return []


func _test_army_app_registered() -> void:
	_check("army app registered", not _army_entry().is_empty())
	var e := _army_entry()
	_check("army label", String(e[1]) == "Army")
	_check("army icon path", String(e[2]) == "res://assets/ui/phone/app_army.png")
	_check("army icon exists", ResourceLoader.exists(String(e[2])))
	_check("army icon loads", load(String(e[2])) is Texture2D)
	# Append-last convention: settings at 9, army at 10 (last).
	_check("settings canonical index 9",
		String(PhoneUI.HOME_APPS[9][0]) == "settings")
	_check("army canonical index 10",
		String(PhoneUI.HOME_APPS[10][0]) == "army")
	# Rumors (2026-10-06) appended after army; army stays pinned at 10.
	_check("rumors is last app",
		String(PhoneUI.HOME_APPS[PhoneUI.HOME_APPS.size() - 1][0]) == "rumors")


func _test_army_app_opens() -> void:
	var w := _new_world(true)
	var ui := _new_ui(w)
	ui.open_app("army")
	_check("army screen", ui.current_screen() == "army")
	_check("army back target home", ui._back_target_for("army") == "home")
	ui._on_status_back()
	_check("back from army goes home", ui.current_screen() == "home")
	ui.queue_free()
	w["gs"].queue_free()


func _test_army_app_no_army_safe() -> void:
	# No army system wired: screen must explain, not crash.
	var w := _new_world(false)
	var ui := _new_ui(w)
	ui.open_app("army")
	_check("army screen without army", ui.current_screen() == "army")
	var texts := _collect_texts(ui)
	var joined := "\n".join(texts)
	_check("no-army notice", joined.find("Army system not ready.") >= 0)
	ui.queue_free()
	w["gs"].queue_free()


func _test_army_screen_has_command_surface() -> void:
	var w := _new_world(true)
	var ui := _new_ui(w)
	ui.open_app("army")
	var texts := _collect_texts(ui)
	var joined := "\n".join(texts)
	# ArmyTab sections: summary heading + stance buttons.
	_check("army summary heading", joined.find("Army") >= 0)
	var has_stance := joined.find("Guard") >= 0 or joined.find("Auto") >= 0 \
		or joined.find("Lead") >= 0 or joined.find("Stance") >= 0
	_check("army stance controls", has_stance)
	ui.queue_free()
	w["gs"].queue_free()


func _test_army_home_order_includes_army() -> void:
	var w := _new_world(true)
	var ui := _new_ui(w)
	# _load_home_order auto-appends new apps after the saved order.
	_check("home order includes army", "army" in ui._home_order)
	ui.queue_free()
	w["gs"].queue_free()
