class_name SimSeasons
extends RefCounted
## Cursing Gnomes — fantasy calendar, seasons, and the weather simulation
## (Milestone 6b: world & environment).
##
## Ports the HTML build's calendar + weather systems (not its code):
##   - Calendar: 12 months x 30 days, weekdays cycle, game starts on
##     Bloommoon 1, Year 1 (a Monday). MONTHS / WEEKDAYS are verbatim from
##     the HTML build.
##   - Seasons: Winter (months 12,1,2), Spring (3-5), Summer (6-8), Autumn
##     (9-11) — HTML's getSeason() boundaries, verbatim.
##   - Weather sim: conditions clear/cloudy/rain/storm/snow/fog, Fahrenheit
##     temperature, wind (drives wildfire spread). Weather shifts every
##     ~45-90 s toward the monthly forecast buffer (4 weeks x 7 days),
##     with HTML's exact pools, base temps, and override odds.
##   - Day/night hours: hour_of_day() maps game_time onto 0-24 like the
##     HTML's timeOfDay. Deep night is hour < 5 or > 21 (HTML's overlay
##     rule); dawn 5-7, dusk 19-21. NOTE: GameState.is_night uses a
##     different rule (second half of the cycle) and is untouched — both
##     exist; is_night_hour() is the HTML-overlay definition.
##
## Gameplay modifiers exposed for other systems:
##   - growth_mult(): seasonal crop growth modifier. DESIGN-PORT — the HTML
##     build grew crops at a fixed rate (~1.5 in-game days seed->mature,
##     watered x1.6) and only watered them via rain; the seasonal yield
##     curve here is new and marked as such in the per-season values.
##   - move_mult(): weather movement modifier. DESIGN-PORT — HTML flavor
##     text mentions mud, but no speed numbers exist there.
##   - Fire interplay is exact HTML: rain/storm dampen fires, storm wind
##     boosts spread. Read via weather / wind_speed by DisasterSim.
##
## Pure logic — no rendering, no input, no audio. The visual layer
## (world/weather.gd) reads weather + temperature + hour from here.


## Verbatim from the HTML build.
const MONTHS: Array[String] = ["Frostmoon", "Thawmoon", "Bloommoon",
	"Sunpeak", "Highsun", "Harvest", "Fallingleaf", "Darkening",
	"Snowfall", "Deepfrost", "Stillnight", "Newlight"]
const WEEKDAYS: Array[String] = ["Sun", "Mon", "Tue", "Wed", "Thu",
	"Fri", "Sat"]
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
## The game starts in spring: month 3 = Bloommoon, day 1, year 1, Monday.
const START_MONTH := 3

## Seasons (HTML getSeason() boundaries, verbatim).
const WINTER := "Winter"
const SPRING := "Spring"
const SUMMER := "Summer"
const AUTUMN := "Autumn"

## Seasonal base temperatures in °F (HTML seasonBaseTemp, verbatim).
const BASE_TEMP := {
	"Winter": 28.0, "Spring": 58.0, "Summer": 82.0, "Autumn": 52.0,
}

## Weather condition pools per season (HTML generateMonthlyForecast,
## verbatim). Conditions: clear | cloudy | rain | storm | snow | fog.
const WEATHER_TABLE := {
	"Winter": ["snow", "cloudy", "clear", "snow", "fog", "storm", "cloudy"],
	"Spring": ["rain", "cloudy", "clear", "rain", "fog", "clear", "storm"],
	"Summer": ["clear", "clear", "cloudy", "storm", "clear", "rain", "clear"],
	"Autumn": ["cloudy", "rain", "clear", "fog", "rain", "cloudy", "clear"],
}
const CONDITIONS: Array[String] = ["clear", "cloudy", "rain", "storm",
	"snow", "fog"]

## Day/night hour rules (HTML drawDayNightOverlay, verbatim):
## deep night when hour < 5 or hour > 21; dawn fades 5-7, dusk fades 19-21.
const NIGHT_END := 5.0
const DAWN_END := 7.0
const DUSK_START := 19.0
const NIGHT_START := 21.0

## DESIGN-PORT seasonal crop growth multipliers (HTML had no seasonal
## yield curve; it watered crops via rain at x1.6 growth instead).
const SEASON_GROWTH := {
	"Winter": 0.5, "Spring": 1.2, "Summer": 1.0, "Autumn": 0.9,
}
## DESIGN-PORT movement multipliers by weather (HTML mentions mud in
## flavor text but ships no speed numbers).
const WEATHER_MOVE := {
	"clear": 1.0, "cloudy": 1.0, "fog": 0.95,
	"rain": 0.9, "storm": 0.8, "snow": 0.75,
}


var _gs: GameState
var weather: String = "clear"
var temperature: float = 58.0
var wind_dir: float = 0.0
var wind_speed: float = 0.4
## Monthly forecast buffer: 28 entries {condition, temp} (HTML's 4x7).
var forecast: Array[Dictionary] = []
var _weather_timer: float = 0.0
var _weather_duration: float = 60.0
var _last_day: int = 1
var _last_season: String = SPRING
var _rng := RandomNumberGenerator.new()


func _init(game_state: GameState) -> void:
	_gs = game_state
	_rng.randomize()


## Resets weather + forecast. Called by GameState.setup() on new game.
func reset() -> void:
	weather = "clear"
	temperature = float(BASE_TEMP[SPRING])
	wind_dir = _rng.randf() * TAU
	wind_speed = 0.4
	_weather_timer = 0.0
	_weather_duration = 60.0
	_last_day = 1
	_last_season = season()
	generate_monthly_forecast()


## Season for a 1-based month (HTML getSeason(), verbatim).
static func season_of_month(m: int) -> String:
	if m >= 12 or m <= 2:
		return WINTER
	if m <= 5:
		return SPRING
	if m <= 8:
		return SUMMER
	return AUTUMN


## Current season.
func season() -> String:
	return season_of_month(month())


## 1-based month from the day count. Game starts at Bloommoon (month 3).
func month() -> int:
	var total: int = _gs.day_number - 1
	return ((START_MONTH - 1 + total / DAYS_PER_MONTH) % MONTHS_PER_YEAR) + 1


## Day of the month, 1-30.
func day_of_month() -> int:
	return ((_gs.day_number - 1) % DAYS_PER_MONTH) + 1


## Year, starting at 1.
func year() -> int:
	var total: int = _gs.day_number - 1
	return 1 + (START_MONTH - 1 + total / DAYS_PER_MONTH) / MONTHS_PER_YEAR


## Weekday index 0=Sun..6=Sat; day 1 is a Monday (HTML dayOfWeek=1).
func weekday() -> int:
	return (1 + (_gs.day_number - 1)) % 7


func weekday_name() -> String:
	return WEEKDAYS[weekday()]


func month_name() -> String:
	return MONTHS[month() - 1]


## "Mon Bloommoon 1, Year 1" (HTML calendar/clock format).
func date_string() -> String:
	return "%s %s %d, Year %d" % [weekday_name(), month_name(),
		day_of_month(), year()]


## Hour of day 0-24 (HTML timeOfDay). New games start at midday (12:00)
## per Jeremy 2026-10-04 (HTML started at 8:00 AM; Jeremy overrode it).
func hour_of_day() -> float:
	var phase: float = fmod(_gs.game_time,
		Config.DAY_LENGTH_SECONDS) / Config.DAY_LENGTH_SECONDS
	return phase * 24.0


## HTML-overlay definition of night (drawDayNightOverlay).
func is_night_hour() -> bool:
	var h: float = hour_of_day()
	return h < NIGHT_END or h > NIGHT_START


## Night tint alpha 0..0.28 (HTML drawDayNightOverlay, verbatim curve).
func night_alpha() -> float:
	var h: float = hour_of_day()
	if h < NIGHT_END or h > NIGHT_START:
		return 0.28
	if h < DAWN_END:
		return 0.28 - (h - NIGHT_END) * 0.12
	if h > DUSK_START:
		return (h - DUSK_START) * 0.14
	return 0.0


## Seasonal crop growth multiplier (DESIGN-PORT — see const comment).
func growth_mult() -> float:
	return float(SEASON_GROWTH.get(season(), 1.0))


## Movement multiplier for the current weather (DESIGN-PORT).
func move_mult() -> float:
	return float(WEATHER_MOVE.get(weather, 1.0))


## Builds the 4-week forecast buffer for the current season
## (HTML generateMonthlyForecast, verbatim math).
func generate_monthly_forecast() -> void:
	forecast.clear()
	var pool: Array = WEATHER_TABLE.get(season(), WEATHER_TABLE[SPRING])
	var base: float = float(BASE_TEMP.get(season(), 58.0))
	for w in 4:
		for d in 7:
			var cond: String = pool[_rng.randi_range(0, pool.size() - 1)]
			var temp: float = base + (_rng.randf() - 0.5) * 18.0 \
				+ (-10.0 if cond == "snow" else (6.0 if cond == "clear" else 0.0))
			forecast.append({"condition": cond, "temp": int(round(temp))})


## Blends the current weather toward today's forecast entry, then applies
## HTML's 25% random override (verbatim odds).
func apply_forecast_weather() -> void:
	if forecast.is_empty():
		generate_monthly_forecast()
	var dom: int = day_of_month()
	var week_idx: int = mini(3, ((dom - 1) % DAYS_PER_MONTH) / 7)
	var day_idx: int = weekday() % 7
	var entry: Dictionary = forecast[week_idx * 7 + day_idx]
	var before: String = weather
	# Jeremy 2026-10-05: the forecast is the source of truth — the old 25%
	# random override made the sky contradict the weather app constantly.
	# Weather now follows the day's forecast; only a small 10% chance of
	# a one-step drift (e.g. cloudy instead of clear) for variety.
	if _rng.randf() < 0.9:
		weather = String(entry.get("condition", "clear"))
	else:
		var drift := {"clear": "cloudy", "cloudy": "clear", "rain": "storm",
			"storm": "rain", "fog": "cloudy", "snow": "cloudy"}
		weather = String(drift.get(String(entry.get("condition", "clear")), "clear"))
	temperature = float(entry.get("temp", 58)) + (_rng.randf() - 0.5) * 4.0
	if weather != before and _gs.bus.has_signal("weather_changed"):
		_gs.bus.weather_changed.emit(weather)


func tick(delta: float) -> void:
	_weather_timer += delta
	if _weather_timer > _weather_duration:
		_weather_timer = 0.0
		_weather_duration = 45.0 + _rng.randf() * 45.0
		apply_forecast_weather()
		# Wind drifts with the weather (HTML updateWeather, verbatim).
		wind_dir += (_rng.randf() - 0.5) * 1.2
		var target: float
		match weather:
			"storm":
				target = 1.35
			"rain":
				target = 0.55
			"snow":
				target = 0.5
			_:
				target = 0.25 + _rng.randf() * 0.25
		wind_speed += (target - wind_speed) * 0.5
		# Temperature drifts toward the seasonal base + condition offset.
		var t_target: float = float(BASE_TEMP.get(season(), 58.0)) \
			+ (8.0 if weather == "clear" else (-12.0 if weather == "snow"
				else (-4.0 if weather == "storm" else 0.0)))
		temperature += (t_target - temperature) * 0.25
	# New-day rollover: re-apply today's forecast; regenerate the buffer
	# (and, via the world hook, the disaster calendar) on month change.
	if _gs.day_number != _last_day:
		_last_day = _gs.day_number
		apply_forecast_weather()
		if day_of_month() == 1:
			generate_monthly_forecast()
		if season() != _last_season:
			_last_season = season()
			if _gs.bus.has_signal("season_changed"):
				_gs.bus.season_changed.emit(_last_season)


## Milestone 7: export weather state for save files. The calendar itself
## is derived from GameState.day_number (already saved).
func to_dict() -> Dictionary:
	return {
		"weather": weather,
		"temperature": temperature,
		"wind_dir": wind_dir,
		"wind_speed": wind_speed,
		"forecast": forecast.duplicate(true),
		"weather_timer": _weather_timer,
	}


## Milestone 7: restore weather state from a save file.
func from_dict(data: Dictionary) -> void:
	weather = str(data.get("weather", "clear"))
	temperature = float(data.get("temperature", 58.0))
	wind_dir = float(data.get("wind_dir", 0.0))
	wind_speed = float(data.get("wind_speed", 0.4))
	_weather_timer = float(data.get("weather_timer", 0.0))
	forecast.clear()
	for e in data.get("forecast", []):
		if e is Dictionary:
			forecast.append((e as Dictionary).duplicate())
	if forecast.is_empty():
		generate_monthly_forecast()
	_last_day = _gs.day_number
	_last_season = season()
