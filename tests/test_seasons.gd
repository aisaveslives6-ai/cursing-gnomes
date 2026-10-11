extends SceneTree
## Cursing Gnomes — Milestone 6b world / environment / economy tests.
##
## Covers: SimSeasons (fantasy calendar, seasons, weather sim, day/night
## tint, season modifiers, save), DisasterSim forecast + Count Bastard,
## SimFarming (plant/grow/harvest, seeds economy, seed shops), SimIndustry
## (industrial oil lots, Captain Funky Pants trader, gather orders).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_seasons.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes world/environment/economy tests ===")
	_test_calendar_months()
	_test_weekday()
	_test_season_of_month()
	_test_seasons()
	_test_base_temps()
	_test_forecast()
	_test_weather_tick()
	_test_modifiers()
	_test_night_alpha()
	_test_hour_of_day()
	_test_seasons_save()
	_test_disaster_calendar()
	_test_calendar_fires()
	_test_bastard()
	_test_farm_chain()
	_test_farm_growth()
	_test_seed_economy()
	_test_oil_lots()
	_test_trader()
	_test_order_gather()
	_test_weather_fx_fallback()
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


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	return gs


## ---- seasons: calendar ----------------------------------------------------


func _test_calendar_months() -> void:
	var gs := _new_game(["humans"])
	var s := SimSeasons.new(gs)
	gs.day_number = 1
	_check("day1 month", s.month_name() == "Bloommoon")
	_check("day1 day", s.day_of_month() == 1)
	_check("day1 year", s.year() == 1)
	_check("date_string",
		s.date_string() == "Mon Bloommoon 1, Year 1")
	gs.day_number = 30
	_check("day30 day", s.day_of_month() == 30)
	_check("day30 month", s.month_name() == "Bloommoon")
	gs.day_number = 31
	_check("day31 month", s.month_name() == "Sunpeak")
	_check("day31 day", s.day_of_month() == 1)
	gs.day_number = 271
	_check("day271 month", s.month_name() == "Newlight")
	_check("day271 day", s.day_of_month() == 1)
	gs.day_number = 300
	_check("day300 day", s.day_of_month() == 30)
	gs.day_number = 301
	_check("day301 month", s.month_name() == "Frostmoon")
	_check("day301 year", s.year() == 2)
	gs.day_number = 360
	_check("day360 month", s.month_name() == "Thawmoon")
	gs.day_number = 361
	_check("day361 month", s.month_name() == "Bloommoon")
	_check("day361 year", s.year() == 2)

func _test_weekday() -> void:
	var gs := _new_game(["humans"])
	var s := SimSeasons.new(gs)
	gs.day_number = 1
	_check("day1 mon", s.weekday_name() == "Mon")
	gs.day_number = 7
	_check("day7 sun", s.weekday_name() == "Sun")
	gs.day_number = 8
	_check("day8 mon", s.weekday_name() == "Mon")

func _test_season_of_month() -> void:
	# HTML getSeason() boundaries, verbatim.
	_check("winter 12", SimSeasons.season_of_month(12) == "Winter")
	_check("winter 1", SimSeasons.season_of_month(1) == "Winter")
	_check("winter 2", SimSeasons.season_of_month(2) == "Winter")
	_check("spring 3", SimSeasons.season_of_month(3) == "Spring")
	_check("spring 5", SimSeasons.season_of_month(5) == "Spring")
	_check("summer 6", SimSeasons.season_of_month(6) == "Summer")
	_check("summer 8", SimSeasons.season_of_month(8) == "Summer")
	_check("autumn 9", SimSeasons.season_of_month(9) == "Autumn")
	_check("autumn 11", SimSeasons.season_of_month(11) == "Autumn")


func _test_seasons() -> void:
	var gs := _new_game(["humans"])
	var s := SimSeasons.new(gs)
	gs.day_number = 1    # Bloommoon (month 3)
	_check("spring m3", s.season() == "Spring")
	gs.day_number = 91   # month 6 (Sunpeak)
	_check("summer m6", s.season() == "Summer")
	gs.day_number = 181  # month 9 (Fallingleaf)
	_check("autumn m9", s.season() == "Autumn")
	gs.day_number = 271  # month 12 (Deepfrost)
	_check("winter m12", s.season() == "Winter")
	gs.day_number = 301  # month 1 (Newlight)
	_check("winter m1", s.season() == "Winter")

func _test_base_temps() -> void:
	_check("winter temp", SimSeasons.BASE_TEMP["Winter"] == 28.0)
	_check("spring temp", SimSeasons.BASE_TEMP["Spring"] == 58.0)
	_check("summer temp", SimSeasons.BASE_TEMP["Summer"] == 82.0)
	_check("autumn temp", SimSeasons.BASE_TEMP["Autumn"] == 52.0)


func _test_forecast() -> void:
	var gs := _new_game(["humans"])
	var s := SimSeasons.new(gs)
	gs.day_number = 1  # spring
	s.generate_monthly_forecast()
	_check("forecast 28", s.forecast.size() == 28)
	var ok := true
	for e: Dictionary in s.forecast:
		if not (String(e["condition"]) in SimSeasons.WEATHER_TABLE["Spring"]):
			ok = false
		if int(e["temp"]) < 0 or int(e["temp"]) > 110:
			ok = false
	_check("forecast valid", ok)

func _test_weather_tick() -> void:
	var gs := _new_game(["humans"])
	var s := SimSeasons.new(gs)
	gs.day_number = 200  # summer
	s.tick(0.0)
	# Force the shift window with a huge delta.
	s._weather_timer = 0.0
	s.tick(1000.0)
	_check("weather valid", s.weather in SimSeasons.CONDITIONS)
	_check("temp sane", s.temperature > -40.0 and s.temperature < 120.0)
	_check("duration reset",
		s._weather_duration >= 45.0 and s._weather_duration <= 90.0)

func _test_modifiers() -> void:
	var gs := _new_game(["humans"])
	var s := SimSeasons.new(gs)
	gs.day_number = 271  # winter (Deepfrost)
	_check("winter growth", is_equal_approx(s.growth_mult(), 0.5))
	gs.day_number = 1    # spring
	_check("spring growth", is_equal_approx(s.growth_mult(), 1.2))
	gs.day_number = 91   # summer (Sunpeak)
	_check("summer growth", is_equal_approx(s.growth_mult(), 1.0))
	gs.day_number = 181  # autumn (Fallingleaf)
	_check("autumn growth", is_equal_approx(s.growth_mult(), 0.9))
	s.weather = "snow"
	_check("snow move", is_equal_approx(s.move_mult(), 0.75))
	s.weather = "storm"
	_check("storm move", is_equal_approx(s.move_mult(), 0.8))
	s.weather = "clear"
	_check("clear move", is_equal_approx(s.move_mult(), 1.0))

func _test_night_alpha() -> void:
	var gs := _new_game(["humans"])
	var s := SimSeasons.new(gs)
	gs.game_time = 3.0 / 24.0 * Config.DAY_LENGTH_SECONDS
	_check("deep night alpha", is_equal_approx(s.night_alpha(), 0.28))
	gs.game_time = 12.0 / 24.0 * Config.DAY_LENGTH_SECONDS
	_check("midday alpha", is_equal_approx(s.night_alpha(), 0.0))
	gs.game_time = 6.0 / 24.0 * Config.DAY_LENGTH_SECONDS
	var dawn: float = s.night_alpha()
	_check("dawn alpha", dawn > 0.0 and dawn < 0.28)
	gs.game_time = 20.0 / 24.0 * Config.DAY_LENGTH_SECONDS
	var dusk: float = s.night_alpha()
	_check("dusk alpha", dusk > 0.0 and dusk < 0.28)
	gs.game_time = 12.0 / 24.0 * Config.DAY_LENGTH_SECONDS
	_check("midday not night", not s.is_night_hour())
	gs.game_time = 3.0 / 24.0 * Config.DAY_LENGTH_SECONDS
	_check("night hour true", s.is_night_hour())

func _test_hour_of_day() -> void:
	var gs := _new_game(["humans"])
	var s := SimSeasons.new(gs)
	gs.game_time = 12.0 / 24.0 * Config.DAY_LENGTH_SECONDS
	_check("noon hour", is_equal_approx(s.hour_of_day(), 12.0))
	gs.game_time = 0.0
	_check("midnight hour", is_equal_approx(s.hour_of_day(), 0.0))

func _test_seasons_save() -> void:
	var gs := _new_game(["humans"])
	var s := SimSeasons.new(gs)
	gs.day_number = 77
	s.weather = "rain"
	s.temperature = 63.0
	var data: Dictionary = s.to_dict()
	var s2 := SimSeasons.new(gs)
	s2.from_dict(data)
	_check("save weather", s2.weather == "rain")
	_check("save temp", is_equal_approx(s2.temperature, 63.0))
	_check("save forecast", s2.forecast.size() == 28)
	_check("save wind", is_equal_approx(s2.wind_speed, s.wind_speed))

## ---- seasons: disasters ---------------------------------------------------


func _test_disaster_calendar() -> void:
	var gs := _new_game(["humans"])
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	d.generate_disaster_calendar()
	_check("forecast count", d.forecast.size() >= 6 \
		and d.forecast.size() <= 7)
	var days := {}
	var ok := true
	for day in d.forecast.keys():
		if days.has(day) or int(day) < 3 or int(day) > 27:
			ok = false
		days[day] = true
		var e: Dictionary = d.forecast[day]
		if String(e.get("label", "")) == "" \
				or String(e.get("type", "")) == "":
			ok = false
	_check("forecast days", ok)

func _test_calendar_fires() -> void:
	var gs := _new_game(["humans"])
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	d.generate_disaster_calendar()
	var target_day := -1
	var target_kind := ""
	for day in d.forecast.keys():
		target_day = int(day)
		target_kind = String((d.forecast[day] as Dictionary)["type"])
		break
	_check("forecast nonempty", target_day > 0)
	gs.day_number = target_day
	gs.game_time = 12.5 / 24.0 * Config.DAY_LENGTH_SECONDS
	var before: int = gs.units.size()
	d.process_calendar_disasters()
	var entry: Dictionary = d.forecast[target_day]
	_check("fired once", bool(entry.get("done", false)))
	var spawned := false
	for u: Dictionary in gs.units:
		var job: String = String(u.get("job", ""))
		if job == target_kind 				or (target_kind == "bandit_raid" and job == "bandit"):
			spawned = true
	_check("monster spawned", spawned and gs.units.size() > before)
	# Second call same day must not double-fire.
	d.process_calendar_disasters()
	_check("no double fire", bool((d.forecast[target_day] as Dictionary) \
		.get("done", false)))

func _test_bastard() -> void:
	_check("bastard taunts", DisasterSim.COUNT_BASTARD_TAUNTS.size() == 14)
	var gs := _new_game(["humans"])
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	var a: Dictionary = d.spawn("count_bastard", Vector2(100, 100))
	var b: Dictionary = d.spawn("count_bastard", Vector2(200, 200))
	_check("bastard spawned", not a.is_empty())
	_check("bastard singleton", b.is_empty())
	_check("bastard harmless",
		float(a.get("dmg", 1.0)) == 0.0 and float(a.get("hp", 0.0)) == 600.0)

## ---- farming --------------------------------------------------------------


func _test_farm_chain() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	gs.resources.add_resource("humans", "wood", 100.0)
	var plot: Dictionary = f.create_plot("humans", Vector2(50, 50))
	_check("plot created", not plot.is_empty())
	_check("plot cost", gs.resources.get_amount("humans", "wood") \
		>= 75.0 - 0.01)
	_check("plot bin", int(plot.get("seed_bin", 0)) == 4)
	_check("plot tiles", (plot.get("tiles", []) as Array).size() == 16)
	_check("plant", f.plant(plot, 0))
	_check("bin spent", int(plot.get("seed_bin", 0)) == 3)
	_check("replant blocked", not f.plant(plot, 0))
	# Fast-forward to maturity, then harvest.
	var crop: Dictionary = (plot["tiles"] as Array)[0]["crop"]
	crop["g"] = 1.0
	var food0: float = gs.resources.get_amount("humans", "food")
	var seeds0: float = gs.resources.get_amount("humans", "seeds")
	var out: Dictionary = f.harvest(plot, 0)
	_check("harvest food range",
		float(out["food"]) >= 60.0 and float(out["food"]) <= 100.0)
	_check("harvest seed range",
		float(out["seeds"]) >= 2.0 and float(out["seeds"]) <= 4.0)
	_check("harvest ledger",
		is_equal_approx(gs.resources.get_amount("humans", "food") - food0,
			float(out["food"])) \
		and is_equal_approx(
			gs.resources.get_amount("humans", "seeds") - seeds0,
			float(out["seeds"])))
	_check("unripe no yield",
		float(f.harvest(plot, 1)["food"]) == 0.0)

func _test_farm_growth() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	gs.resources.add_resource("humans", "wood", 100.0)
	var plot: Dictionary = f.create_plot("humans", Vector2(50, 50))
	f.plant(plot, 0)
	# No seasons attached -> neutral growth: 1.5 in-game days to mature.
	f.tick(1.5 * Config.DAY_LENGTH_SECONDS)
	var crop: Dictionary = (plot["tiles"] as Array)[0]["crop"]
	_check("grows to mature", float(crop.get("g", 0.0)) >= 1.0)

func _test_seed_economy() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var shop: Dictionary = gs.add_building({
		"type": "seedshop", "faction": "humans",
		"position": Vector2(60, 60), "alive": true, "complete": true})
	gs.resources.add_resource("humans", "gold", 200.0)
	var seeds0: float = gs.resources.get_amount("humans", "seeds")
	var bought: int = f.buy_seeds("humans", 10)
	_check("buy 10", bought == 10)
	_check("buy cost", is_equal_approx(
		gs.resources.get_amount("humans", "gold"), 150.0))
	_check("buy ledger", is_equal_approx(
		gs.resources.get_amount("humans", "seeds") - seeds0, 10.0))
	_check("shop stock down", int(shop.get("seedStock", -1)) == 15)
	var delivered: int = f.deliver_seeds_to_shop(shop, "humans", 5)
	_check("deliver 5", delivered == 5)
	_check("shop restocked", int(shop.get("seedStock", -1)) == 20)
	# Broke faction cannot buy.
	gs.resources.spend("humans", {"gold": 150.0})
	_check("broke no buy", f.buy_seeds("humans", 10) == 0)

## ---- industry --------------------------------------------------------------


func _test_oil_lots() -> void:
	var gs := _new_game(["humans"])
	var ind := SimIndustry.new(gs)
	gs.zoning.paint_zone("I", "humans", Rect2(0, 0, 500, 500))
	gs.add_building({"type": "mine", "faction": "humans",
		"position": Vector2(100, 100), "alive": true, "complete": true})
	var oil0: float = gs.resources.get_amount("humans", "oil")
	ind.tick(3600.0)
	var gained: float = gs.resources.get_amount("humans", "oil") - oil0
	# 2026-10-05: oil is pumps-only (Jeremy's order) — the old lot-oil
	# trickle (~2.2/h) was retired from _tick_lot_production, so a plain
	# mine in an I zone now gains zero oil. (Stale assertion updated.)
	_check("oil trickle retired", is_equal_approx(gained, 0.0))

func _test_trader() -> void:
	var gs := _new_game(["humans"])
	var ind := SimIndustry.new(gs)
	ind.reset()
	_check("trader off map", not ind.funky_on_map)
	ind._begin_visit()
	_check("trader visits", ind.funky_on_map)
	gs.resources.add_resource("humans", "gold", 1000.0)
	var gold0: float = gs.resources.get_amount("humans", "gold")
	var oil0: float = gs.resources.get_amount("humans", "oil")
	ind.funky_stock["oil"] = 60.0
	_check("trade ok", ind.trade("humans", "gold", "oil", 100.0, 10.0))
	_check("trade ledger",
		is_equal_approx(gs.resources.get_amount("humans", "gold") - gold0,
			-100.0) \
		and is_equal_approx(gs.resources.get_amount("humans", "oil") - oil0,
			10.0))
	_check("trade stock", is_equal_approx(
		float(ind.funky_stock["oil"]), 50.0))
	_check("trade absent", not ind.trade("humans", "gold", "oil", 1e9, 1.0))
	gs.resources.add_resource("humans", "wood", 500.0)
	_check("deposit ok", ind.deposit("humans", "wood", 50.0))
	_check("deposit capped", float(ind.funky_stock["wood"]) <= 900.0)
	# Save roundtrip.
	var data: Dictionary = ind.to_dict()
	var ind2 := SimIndustry.new(gs)
	ind2.from_dict(data)
	_check("trader save", ind2.funky_on_map \
		and is_equal_approx(float(ind2.funky_stock["oil"]), 50.0))

func _test_order_gather() -> void:
	var gs := _new_game(["humans"])
	var ind := SimIndustry.new(gs)
	gs.found_town("humans", "Testville", Vector2(100, 100))
	var u: Dictionary = gs.add_unit({"job": "worker", "faction": "humans",
		"position": Vector2(10, 10), "alive": true, "work_building": -1})
	var site: Dictionary = gs.add_work_site({"kind": "wood",
		"position": Vector2(200, 200), "amount": 100.0, "faction": "humans"})
	var n: int = ind.order_gather(int(site["id"]), "humans")
	_check("order assigns", n == 1)
	_check("order state",
		String(u.get("work_state", "")) == "to_resource" \
		and int(u.get("work_site", -1)) == int(site["id"]))
	_check("order empty site", ind.order_gather(99999, "humans") == 0)

func _test_weather_fx_fallback() -> void:
	var gs := _new_game(["humans"])
	var fx := WeatherFX.new()
	fx.game = gs
	# Deterministic roll: bare RandomNumberGenerator.new() is randomly
	# seeded in Godot 4.7, which made this a ~8%-per-run flake.
	fx._rng.seed = 20261004
	# No seasons attached -> fallback timer path must not crash.
	fx._update_weather_state(500.0)
	# "storm" is a real fallback state (weather_changed documents
	# "clear" | "rain" | "storm" | "snow"); the old 3-state list failed
	# whenever the roll landed in the storm band.
	_check("fx fallback", fx.current_weather() in ["clear", "rain", "storm", "snow"])
	fx.free()
