class_name PhoneWeather
extends RefCounted
## Cursing Gnomes — real sim weather data for the phone.
##
## Jeremy 2026-10-03: "Phone also needs a proper weather forecast that
## reflects the games Dynamic weather and seasons systems."
##
## The phone's weather widget and Forecast app MUST read the game's actual
## weather systems — never fake or static data:
##   - SimSeasons (scripts/sim/seasons.gd): weather, temperature, the
##     28-entry monthly forecast buffer, season, fantasy calendar.
##   - DisasterSim (scripts/sim/disasters.gd): the monthly disaster
##     forecast calendar (day-of-month -> {label, done}).
##
## Pure data helpers — no UI. All functions are null-safe: a missing sim
## returns empty results instead of crashing (e.g. phone opened before
## the world attaches DisasterSim).


## Human-readable weather conditions (HTML's six, verbatim keys).
const CONDITIONS: Array[String] = ["clear", "cloudy", "rain", "storm",
	"snow", "fog"]


## Display label for a condition. Text only — no emoji (tofu rule).
static func condition_label(cond: String) -> String:
	match cond:
		"clear":
			return "Clear"
		"cloudy":
			return "Cloudy"
		"rain":
			return "Rain"
		"storm":
			return "Storm"
		"snow":
			return "Snow"
		"fog":
			return "Fog"
	return "Clear"


## Day phase from the seasons clock (HTML day/night overlay rules).
static func day_phase(s) -> String:
	var h: float = s.hour_of_day()
	if h < SimSeasons.NIGHT_END or h > SimSeasons.NIGHT_START:
		return "Night"
	if h < SimSeasons.DAWN_END:
		return "Dawn"
	if h > SimSeasons.DUSK_START:
		return "Dusk"
	return "Day"


## Current conditions from the live sim. Returns {} when unavailable.
## Keys: condition, label, temp_f, season, date_string, wind_speed,
##       day_phase, is_night.
static func current(gs) -> Dictionary:
	if gs == null:
		return {}
	var s = gs.get("seasons")
	if s == null:
		return {}
	var cond := String(s.weather)
	return {
		"condition": cond,
		"display": "%s · %d°F" % [condition_label(cond), int(round(s.temperature))],
		"label": condition_label(cond),
		"temp_f": int(round(s.temperature)),
		"season": s.season(),
		"date_string": s.date_string(),
		"wind_speed": snappedf(float(s.wind_speed), 0.01),
		"day_phase": day_phase(s),
		"is_night": s.is_night_hour(),
	}


## Next `count` in-game days from the seasons forecast buffer
## (HTML generateMonthlyForecast, same indexing as apply_forecast_weather).
## The buffer only covers the current month, so results stop at month end.
## Each entry: {label, condition, temp_f, is_today, day_of_month}.
static func forecast_days(gs, count: int = 7) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if gs == null:
		return out
	var s = gs.get("seasons")
	if s == null:
		return out
	if s.forecast.is_empty():
		s.generate_monthly_forecast()
	var dom: int = s.day_of_month()
	var wd: int = s.weekday()
	var n: int = mini(count, 31 - dom)
	for k in n:
		var dk: int = dom + k
		var week_idx: int = mini(3, ((dk - 1) % 30) / 7)
		var day_idx: int = (wd + k) % 7
		var entry: Dictionary = s.forecast[week_idx * 7 + day_idx]
		var label: String
		if k == 0:
			label = "Today"
		elif k == 1:
			label = "Tmrw"
		else:
			label = "%s %d" % [SimSeasons.WEEKDAYS[(wd + k) % 7], dk]
		out.append({
			"label": label,
			"condition": String(entry.get("condition", "clear")),
			"temp_f": int(entry.get("temp", 58)),
			"is_today": k == 0,
			"day_of_month": dk,
		})
	return out


## Upcoming forecast disasters from the sim's disaster calendar
## (HTML generateDisasterCalendar parity — day-of-month -> label).
## Each entry: {day_of_month, days_away, label, done}.
static func upcoming_disasters(gs, count: int = 5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if gs == null:
		return out
	var d = gs.get("disasters")
	if d == null:
		return out
	var fc: Dictionary = d.forecast
	if fc.is_empty():
		return out
	var dom: int = 1
	var s = gs.get("seasons")
	if s != null:
		dom = s.day_of_month()
	var days: Array = fc.keys()
	days.sort()
	for day in days:
		var dd: int = int(day)
		if dd < dom:
			continue
		var e: Dictionary = fc[day]
		out.append({
			"day_of_month": dd,
			"days_away": dd - dom,
			"label": String(e.get("label", "?")),
			"done": bool(e.get("done", false)),
		})
		if out.size() >= count:
			break
	return out
