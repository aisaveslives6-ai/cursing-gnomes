extends SceneTree
## Cursing Gnomes — home weather widget icon tests (Jeremy 2026-10-04).
##
## The phone home screen's weather widget shows a drawn ForecastIcon
## above the "Clear · 72F" text — same visual language as the Forecast
## app rows, never emoji (tofu rule, Jeremy 2026-10-03).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_home_weather_icon.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes home weather icon tests ===")
	_test_icon_present_and_mapped()
	_test_all_conditions_map()
	_test_icon_tap_passthrough()
	_test_text_still_shown()
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


func _new_ui(condition: String = "clear") -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.player_faction = "gnomes"
	var s := SimSeasons.new(gs)
	s.reset()
	s.weather = condition
	gs.seasons = s
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	# setup() builds the home screen once (go_home() would rebuild and
	# leave the first copy queued-for-deletion under headless).
	ui.setup(gs, phone, court)
	return {"ui": ui, "gs": gs}


func _find_icons(n: Node) -> Array:
	var out: Array = []
	if n is ForecastIcon:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_icons(c))
	return out


func _find_labels(n: Node) -> Array[String]:
	var out: Array[String] = []
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_find_labels(c))
	return out


func _home_icons(d: Dictionary) -> Array:
	var ui: PhoneUI = d["ui"]
	return _find_icons(ui)


func _test_icon_present_and_mapped() -> void:
	var d := _new_ui("storm")
	var icons := _home_icons(d)
	_check("icon present", icons.size() == 1)
	if icons.size() == 1:
		_check("icon kind storm", (icons[0] as ForecastIcon).kind == "storm")
	d["ui"].free()


func _test_all_conditions_map() -> void:
	for cond: String in ["clear", "cloudy", "rain", "storm", "snow", "fog"]:
		var d := _new_ui(cond)
		var icons := _home_icons(d)
		_check("icon one %s" % cond, icons.size() == 1)
		if icons.size() == 1:
			_check("icon kind %s" % cond,
				(icons[0] as ForecastIcon).kind == cond)
		d["ui"].free()


func _test_icon_tap_passthrough() -> void:
	var d := _new_ui("rain")
	var icons := _home_icons(d)
	_check("passthrough icon found", icons.size() == 1)
	if icons.is_empty():
		d["ui"].free()
		return
	var icon: ForecastIcon = icons[0]
	# Taps must reach the wrap Button (opens Forecast app).
	_check("icon mouse ignore",
		icon.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	# Icon lives inside the tappable wrap Button.
	var p: Node = icon.get_parent()
	var wrap: Button = null
	while p != null:
		if p is Button:
			wrap = p
			break
		p = p.get_parent()
	_check("icon inside tap wrap", wrap != null)
	d["ui"].free()


func _test_text_still_shown() -> void:
	var d := _new_ui("clear")
	var gs: GameState = d["gs"]
	var ui: PhoneUI = d["ui"]
	var cur: Dictionary = PhoneWeather.current(gs)
	var texts := _find_labels(ui)
	_check("main text intact", String(cur["display"]) in texts)
	_check("sub text intact",
		"%s · %s" % [String(cur["day_phase"]), String(cur["season"])] in texts)
	ui.free()
