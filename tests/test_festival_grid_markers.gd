extends SceneTree
## Cursing Gnomes — festival markers on the Forecast month grid
## (Jeremy 2026-10-04 wake polish).
##
## The Forecast app's month grid marks disaster days with color-coded
## diamond markers. Festival days had no grid marker even though the
## "Upcoming Festivals" section lists them — a scheduled festival was
## invisible on the calendar itself. This test pins:
##   1. PhoneUI._fc_ymd() calendar math (shared by _fc_date_string and
##      the grid's festival-day mapping).
##   2. _show_calendar builds a festival_days map from
##      scheduled_festivals() and adds ForecastIcon "festival" starburst
##      markers in both the disaster-button branch and the plain-label
##      branch (no emoji anywhere — tofu rule).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_festival_grid_markers.gd
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
	print("test_festival_grid_markers: festival starbursts on forecast grid")
	_test_fc_ymd_math()
	_test_grid_wiring()
	print("test_festival_grid_markers: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


## _fc_ymd must match the calendar math _fc_date_string always used
## (game starts Bloommoon 1 = month 3, year 1; 30-day months).
func _test_fc_ymd_math() -> void:
	_check("day 1 -> [1,3,1]", PhoneUI._fc_ymd(1) == [1, 3, 1])
	_check("day 30 -> [1,3,30]", PhoneUI._fc_ymd(30) == [1, 3, 30])
	_check("day 31 -> [1,4,1]", PhoneUI._fc_ymd(31) == [1, 4, 1])
	_check("day 60 -> [1,4,30]", PhoneUI._fc_ymd(60) == [1, 4, 30])
	_check("day 360 -> [2,2,30]", PhoneUI._fc_ymd(360) == [2, 2, 30])
	_check("day 361 -> [2,3,1]", PhoneUI._fc_ymd(361) == [2, 3, 1])
	# _fc_date_string must agree with _fc_ymd (same helper, no drift).
	var ui := PhoneUI.new()
	_check("date_string(1) Bloommoon 1 Year 1",
		ui._fc_date_string(1) == "Bloommoon 1, Year 1")
	_check("date_string(361) Bloommoon 1 Year 2",
		ui._fc_date_string(361) == "Bloommoon 1, Year 2")
	ui.free()


## Source-level wiring: the grid builds festival_days from the sim's
## scheduled festivals and drops starburst markers in both cell kinds.
func _test_grid_wiring() -> void:
	var phone := _live_lines("res://scripts/ui/phone_ui.gd")
	_check("phone_ui.gd readable", not phone.is_empty())
	var src: String = "\n".join(phone)
	_check("festival_days map built", src.find("var festival_days") >= 0)
	_check("reads scheduled_festivals()",
		src.find("scheduled_festivals()") >= 0)
	_check("maps via _fc_ymd", src.find("_fc_ymd(dab)") >= 0)
	_check("skips past festivals",
		src.find("if dab < _gs.day_number:") >= 0)
	_check("starburst marker kind used",
		src.find('ForecastIcon.make("festival"') >= 0)
	_check("disaster+festival same-day branch",
		src.find("if festival_days.has(d):") >= 0)
	_check("no emoji in marker code",
		src.find("festival_days") >= 0 and _no_emoji_in(src))
	# _fc_date_string delegates to _fc_ymd (single source of truth).
	_check("_fc_date_string uses _fc_ymd",
		src.find("var ymd: Array = _fc_ymd(day_abs)") >= 0)


## Rough emoji sweep over the joined source (tofu rule).
func _no_emoji_in(src: String) -> bool:
	for i in range(src.length()):
		var o: int = src.unicode_at(i)
		if o > 0x2500 and (o < 0x2B00 or o > 0x2BFF):
			# Allow common box-drawing/arrows used in comments; flag
			# pictographs and misc symbols.
			if (o >= 0x1F000 and o <= 0x1FAFF) or (o >= 0x2600 and o <= 0x27BF):
				return false
	return true
