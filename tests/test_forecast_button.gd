extends SceneTree
## Cursing Gnomes — Forecast drawer button tests (Jeremy 2026-10-04).
##
## HTML parity: the HTML build has a floating Weather & Calendar button
## (gaz-float-wxcal). The Godot drawer gets a "Forecast" button under the
## WORLD section that jumps straight to the phone's forecast calendar
## (phone app id "calendar").
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_forecast_button.gd
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


## Live (non-comment) lines of a file.
static func _live_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	f.close()
	return out


func _initialize() -> void:
	print("test_forecast_button: drawer Forecast -> phone forecast calendar")
	var hud := _live_lines("res://scripts/ui/hud.gd")
	var phone := _live_lines("res://scripts/ui/phone_ui.gd")
	_check("hud.gd readable", not hud.is_empty())
	_check("phone_ui.gd readable", not phone.is_empty())

	# 1. The drawer has a Forecast button.
	var forecast_lines: Array[String] = []
	for line: String in hud:
		if line.find('_drawer_button("Forecast"') >= 0:
			forecast_lines.append(line.strip_edges().left(160))
	_check("drawer has a Forecast _drawer_button", not forecast_lines.is_empty())
	for l: String in forecast_lines:
		print("    found: ", l)

	# 2. The Forecast button is wired to the calendar app (same line or the
	#    continuation line, matching the _drawer_button(callable) style).
	var wired := false
	for i: int in range(hud.size()):
		if hud[i].find('_drawer_button("Forecast"') >= 0:
			var window: String = hud[i]
			if i + 1 < hud.size():
				window += " " + hud[i + 1]
			if window.find('_open_phone_app("calendar")') >= 0:
				wired = true
	_check("Forecast button opens the calendar app", wired)

	# 3. The phone's open_app routes "calendar" to the forecast screen.
	var route := false
	for i: int in range(phone.size()):
		if phone[i].strip_edges() == '"calendar":':
			if i + 1 < phone.size() and phone[i + 1].find("_show_calendar()") >= 0:
				route = true
	_check('open_app("calendar") routes to _show_calendar()', route)

	# 4. The calendar app still exists in the phone's app registry.
	var registered := false
	for line: String in phone:
		if line.find('"calendar"') >= 0 and line.find("Forecast") >= 0:
			registered = true
	_check("calendar app registered on the phone home screen", registered)

	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		quit(1)
	else:
		quit(0)
