extends SceneTree
## Cursing Gnomes — phone weather reads the REAL sim + seasons show in
## the sim graphics (Jeremy 2026-10-03).
##
## Covers:
##   PhoneWeather (scripts/ui/phone_weather.gd): current() / forecast_days()
##     / upcoming_disasters() read GameState.seasons (SimSeasons) and
##     GameState.disasters (DisasterSim) — never fake data. Null-safe.
##   WeatherFX (scripts/world/weather.gd): fog mist + cold/hot screen
##     edges from the live sim (HTML weather-overlay parity, verbatim).
##   MapProp (scripts/world/map_prop.gd): HTML treeSeasonTint parity —
##     autumn/winter/spring tints on tree sprites (pine excluded in autumn).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_phone_weather.gd
##
## Exit code 0 = all passed, 1 = any failure.


class _DisasterStub:
	extends RefCounted
	var forecast := {}


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes phone-weather / season-graphics tests ===")
	_test_current_real_sim()
	_test_current_null_safe()
	_test_condition_labels()
	_test_forecast_days()
	_test_forecast_caps_at_month_end()
	_test_forecast_null_safe()
	_test_upcoming_disasters()
	_test_upcoming_disasters_null_safe()
	_test_ui_weather_routing()
	_test_forecast_icon()
	_test_atmosphere_targets()
	_test_tree_season_tint()
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


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var s := SimSeasons.new(gs)
	s.reset()
	gs.seasons = s
	return gs


## ---- PhoneWeather.current: real sim data ---------------------------------


func _test_current_real_sim() -> void:
	var gs := _new_game()
	var s = gs.seasons
	s.weather = "storm"
	s.temperature = 71.6
	gs.game_time = Config.DAY_LENGTH_SECONDS * (8.0 / 24.0)  # 8:00 AM
	var c: Dictionary = PhoneWeather.current(gs)
	_check("current condition", c.get("condition") == "storm")
	_check("current label", c.get("label") == "Storm")
	_check("current temp", c.get("temp_f") == 72)
	_check("current season", c.get("season") == "Spring")  # day 1 = Bloommoon
	_check("current date", c.get("date_string") == "Mon Bloommoon 1, Year 1")
	_check("current phase", c.get("day_phase") == "Day")  # game starts 8 AM
	_check("current display", String(c.get("display", "")).contains("Storm"))


func _test_current_null_safe() -> void:
	_check("current null gs", PhoneWeather.current(null).is_empty())
	var gs := _new_game()
	gs.seasons = null
	_check("current null seasons", PhoneWeather.current(gs).is_empty())


func _test_condition_labels() -> void:
	_check("lbl clear", PhoneWeather.condition_label("clear") == "Clear")
	_check("lbl storm", PhoneWeather.condition_label("storm") == "Storm")
	_check("lbl snow", PhoneWeather.condition_label("snow") == "Snow")
	_check("lbl fog", PhoneWeather.condition_label("fog") == "Fog")
	_check("lbl bogus", PhoneWeather.condition_label("bogus") == "Clear")


## ---- PhoneWeather.forecast_days: real forecast buffer ----------------------


func _test_forecast_days() -> void:
	var gs := _new_game()
	var days: Array[Dictionary] = PhoneWeather.forecast_days(gs, 7)
	_check("forecast count", days.size() == 7)
	_check("forecast today first", days[0].get("is_today") == true)
	_check("forecast today label", days[0].get("label") == "Today")
	_check("forecast tmrw label", days[1].get("label") == "Tmrw")
	_check("forecast day3 label", String(days[2].get("label", "")).begins_with("Wed"))
	_check("forecast doms", days[0].get("day_of_month") == 1
		and days[6].get("day_of_month") == 7)
	var valid := true
	for d in days:
		if not (String(d.get("condition", "")) in PhoneWeather.CONDITIONS):
			valid = false
		if not (d.get("temp_f") is int):
			valid = false
	_check("forecast entries valid", valid)
	# The buffer must mirror the sim's own buffer entry for today.
	var s = gs.seasons
	var wd: int = s.weekday()
	var entry: Dictionary = s.forecast[mini(3, 0) * 7 + wd % 7]
	_check("forecast matches sim",
		days[0].get("condition") == String(entry.get("condition", "")))


func _test_forecast_caps_at_month_end() -> void:
	var gs := _new_game()
	gs.day_number = 30  # last day of Bloommoon
	var days: Array[Dictionary] = PhoneWeather.forecast_days(gs, 7)
	_check("forecast month cap", days.size() == 1)
	_check("forecast cap today", days[0].get("is_today") == true)


func _test_forecast_null_safe() -> void:
	_check("forecast null gs", PhoneWeather.forecast_days(null, 7).is_empty())
	var gs := _new_game()
	gs.seasons = null
	_check("forecast null seasons", PhoneWeather.forecast_days(gs, 7).is_empty())


## ---- PhoneWeather.upcoming_disasters: real disaster calendar ---------------


func _test_upcoming_disasters() -> void:
	var gs := _new_game()
	var stub := _DisasterStub.new()
	stub.forecast = {
		5: {"type": "bandit_raid", "label": "Bandit Raid", "done": false},
		2: {"type": "giant_ass", "label": "Giant Ass", "done": true},
		28: {"type": "thicc_moose", "label": "Thicc Moose", "done": false},
	}
	gs.disasters = stub
	var up: Array[Dictionary] = PhoneWeather.upcoming_disasters(gs, 5)
	_check("disasters count", up.size() == 3)
	_check("disasters sorted", up[0].get("day_of_month") == 2
		and up[1].get("day_of_month") == 5
		and up[2].get("day_of_month") == 28)
	_check("disasters labels", up[0].get("label") == "Giant Ass"
		and up[1].get("label") == "Bandit Raid")
	_check("disasters done flag", up[0].get("done") == true
		and up[1].get("done") == false)
	_check("disasters days_away", up[0].get("days_away") == 1
		and up[2].get("days_away") == 27)
	# Past days are skipped: move to day 6, day 2 and 5 drop out.
	gs.day_number = 6
	up = PhoneWeather.upcoming_disasters(gs, 5)
	_check("disasters past skipped",
		up.size() == 1 and up[0].get("day_of_month") == 28)


func _test_upcoming_disasters_null_safe() -> void:
	_check("disasters null gs", PhoneWeather.upcoming_disasters(null).is_empty())
	var gs := _new_game()
	gs.disasters = null
	_check("disasters null sim", PhoneWeather.upcoming_disasters(gs).is_empty())
	var stub := _DisasterStub.new()
	stub.forecast = {}
	gs.disasters = stub
	_check("disasters empty cal", PhoneWeather.upcoming_disasters(gs).is_empty())


## ---- WeatherFX atmosphere: HTML overlay parity -----------------------------


## ---- ForecastIcon: drawn (never emoji) animated forecast icons --------
## Jeremy 2026-10-04: Forecast app visuals — all six weather conditions,
## festival starburst, disaster diamonds. No emoji anywhere (tofu rule).


func _test_forecast_icon() -> void:
	# All six weather conditions construct and carry their kind.
	for cond in PhoneWeather.CONDITIONS:
		var icon := ForecastIcon.make(cond)
		root.add_child(icon)
		_check("icon kind " + cond, icon.kind == cond)
		_check("icon min size " + cond,
			icon.custom_minimum_size == Vector2(56, 56))
		# Advance the animation clock and force a draw — must not error.
		icon.time = 1.37
		icon.queue_redraw()
		_check("icon process " + cond, icon.time >= 1.37)
		icon.queue_free()
	# Festival starburst.
	var fest := ForecastIcon.make("festival")
	_check("icon festival kind", fest.kind == "festival")
	fest.queue_free()
	# Disaster diamond uses the accent color; urgent pulses.
	var dis := ForecastIcon.make("disaster", Color(0.9, 0.2, 0.2))
	_check("icon disaster accent",
		dis.accent.is_equal_approx(Color(0.9, 0.2, 0.2)))
	_check("icon disaster not urgent", not dis.urgent)
	dis.queue_free()
	var urg := ForecastIcon.make("disaster", Color.RED, 56.0, true)
	_check("icon disaster urgent", urg.urgent)
	urg.queue_free()
	# Unknown kinds fall back to the disaster dot, never crash.
	var weird := ForecastIcon.make("hurricane")
	root.add_child(weird)
	weird.time = 2.0
	weird.queue_redraw()
	_check("icon unknown kind safe", weird.kind == "hurricane")
	weird.queue_free()


func _test_atmosphere_targets() -> void:
	var gs := _new_game()
	var s = gs.seasons
	var fx := WeatherFX.new()
	fx.game = gs
	# Fog -> mist overlay.
	s.weather = "fog"
	s.temperature = 60.0
	var tg: Array = fx._atmosphere_targets()
	_check("fog mist", tg[0].is_equal_approx(WeatherFX.FOG_COLOR))
	_check("fog no temp tint", (tg[1] as Color).a < 0.001)
	# Cold -> blue edge.
	s.weather = "clear"
	s.temperature = 20.0
	tg = fx._atmosphere_targets()
	_check("cold edge", tg[1].is_equal_approx(WeatherFX.COLD_COLOR))
	# Hot -> warm edge.
	s.temperature = 95.0
	tg = fx._atmosphere_targets()
	_check("hot edge", tg[1].is_equal_approx(WeatherFX.HOT_COLOR))
	# Mild -> nothing.
	s.temperature = 60.0
	tg = fx._atmosphere_targets()
	_check("mild clear", (tg[0] as Color).a < 0.001
		and (tg[1] as Color).a < 0.001)
	# No seasons -> nothing (must not crash).
	fx.game = null
	tg = fx._atmosphere_targets()
	_check("no sim clear", (tg[0] as Color).a < 0.001)
	fx.free()


## ---- MapProp tree season tint: HTML treeSeasonTint parity ------------------


func _tree_pos_pine() -> Vector2:
	# Find a position whose oak/pine pick is pine (same hash as Art).
	for x in range(0, 40):
		var p := Vector2(x * 7.0, 3.0)
		if absi(hash("%d,%d" % [int(p.x), int(p.y)])) % 2 == 1:
			return p
	return Vector2(9999, 9999)


func _tree_pos_oak() -> Vector2:
	for x in range(0, 40):
		var p := Vector2(x * 7.0, 5.0)
		if absi(hash("%d,%d" % [int(p.x), int(p.y)])) % 2 == 0:
			return p
	return Vector2(9998, 9998)


func _test_tree_season_tint() -> void:
	var oak := MapProp.new()
	oak.setup("tree", _tree_pos_oak())
	var pine := MapProp.new()
	pine.setup("tree", _tree_pos_pine())
	_check("oak detected", not oak._is_pine and oak._sprite != null)
	_check("pine detected", pine._is_pine and pine._sprite != null)
	oak.apply_season_tint("Winter")
	pine.apply_season_tint("Winter")
	_check("winter tint", oak._sprite.modulate.is_equal_approx(MapProp.SEASON_TINT_WINTER)
		and pine._sprite.modulate.is_equal_approx(MapProp.SEASON_TINT_WINTER))
	oak.apply_season_tint("Spring")
	_check("spring tint", oak._sprite.modulate.is_equal_approx(MapProp.SEASON_TINT_SPRING))
	# HTML excluded pine from the autumn tint; oak gets the orange cast.
	oak.apply_season_tint("Autumn")
	pine.apply_season_tint("Autumn")
	_check("autumn oak", oak._sprite.modulate.is_equal_approx(MapProp.SEASON_TINT_AUTUMN))
	_check("autumn pine exempt", pine._sprite.modulate.is_equal_approx(Color.WHITE))
	oak.apply_season_tint("Summer")
	_check("summer clear", oak._sprite.modulate.is_equal_approx(Color.WHITE))
	oak.free()
	pine.free()


## ---- PhoneUI reconciliation: weather/forecast/disaster UI must route
## through PhoneWeather (single null-safe source of truth) ---------------
## Jeremy 2026-10-03 phone/weather reconciliation pass.


func _collect_label_texts(n: Node) -> Array[String]:
	var out: Array[String] = []
	if n is Label:
		out.append((n as Label).text)
	# Jeremy 2026-10-04: disaster rows are tappable Buttons now.
	if n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		out.append_array(_collect_label_texts(c))
	return out


func _test_ui_weather_routing() -> void:
	var gs := _new_game()
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	# Seed a known disaster calendar: one done entry must be skipped.
	var stub := _DisasterStub.new()
	stub.forecast = {
		5: {"type": "bandit_raid", "label": "Bandit Raid", "done": false},
		2: {"type": "giant_ass", "label": "Giant Ass", "done": true},
		28: {"type": "thicc_moose", "label": "Thicc Moose", "done": false},
	}
	gs.disasters = stub
	# Home weather widget matches PhoneWeather.current().
	ui.go_home()
	var cur: Dictionary = PhoneWeather.current(gs)
	var home_texts: Array[String] = _collect_label_texts(ui)
	_check("ui home weather main", String(cur["display"]) in home_texts)
	_check("ui home weather sub",
		"%s · %s" % [String(cur["day_phase"]), String(cur["season"])] in home_texts)
	# Forecast screen rows match the helper buffers exactly.
	ui.open_app("calendar")
	_check("ui calendar screen", ui.current_screen() == "calendar")
	var texts: Array[String] = _collect_label_texts(ui)
	# Forecast screen rows match the UI's rendering exactly.
	# Jeremy 2026-10-04: visual rows — title label is the day
	# ("Today (Jun 12)"), subtitle is "Clear, 72°".
	var month_name := ""
	var seas = gs.get("seasons")
	if seas != null and seas.has_method("month_name"):
		month_name = String(seas.month_name())
	for d in PhoneWeather.forecast_days(gs, 7):
		var lbl := String(d["label"])
		var dom := int(d.get("day_of_month", 0))
		if bool(d.get("is_today", false)):
			lbl = "Today (%s %d)" % [month_name, dom]
		elif lbl == "Tmrw":
			lbl = "Tomorrow (%s %d)" % [month_name, dom]
		var sub := "%s, %d°" % [
			PhoneWeather.condition_label(String(d["condition"])),
			int(d["temp_f"])]
		_check("ui forecast row " + String(d["label"]), lbl in texts)
		_check("ui forecast sub " + String(d["label"]), sub in texts)
	# Unfired disasters show with the helper's phrasing; done ones skip.
	# Jeremy 2026-10-04: visual rows — title is the disaster name,
	# subtitle carries the day ("in N days (day 5)").
	_check("ui disaster pending", "Bandit Raid" in texts)
	_check("ui disaster pending day",
		not texts.filter(func(t: String) -> bool:
			return t.contains("day 5")).is_empty())
	_check("ui disaster pending 2", "Thicc Moose" in texts)
	_check("ui disaster pending 2 day",
		not texts.filter(func(t: String) -> bool:
			return t.contains("day 28")).is_empty())
	var done_rows: Array = texts.filter(
		func(t: String) -> bool: return t.begins_with("Giant Ass"))
	_check("ui disaster done skipped", done_rows.is_empty())
	ui.queue_free()
	gs.queue_free()
