class_name SimFoodFeedback
extends RefCounted
## Cursing Gnomes — the food economy talks back (Jeremy 2026-10-07 wake lane:
## "Set all routines to improve all aspects of the game").
##
## The farm/ranch/trade sim systems emitted bus signals nobody consumed:
## farm_plot_created, farm_harvested, seeds_bought, animal_yield,
## animals_stocked, animal_died, trade_done. Crops were harvested, herds
## lived and died, caravans traded — all in total silence, in a game where
## feeding 240 units is the core survival loop.
##
## This module closes the loop on the REPORTING side (the moment-to-moment
## sounds live in scripts/world/farm_sfx.gd, which follows the 2026-10-07
## audio lane's world-side sfx_spatial pattern):
##   - Daily tallies per faction: crop food, livestock food, animal deaths.
##   - Player digest: the Civic Adviser sends ONE Messenger note per
##     game-day when the player's farms/ranches produced food (rides
##     phone.npc_message, so blocked threads stay silent — sovereignty).
##   - Gazette: "BUMPER HARVEST" when a faction pulls >= 2000 food in one
##     day; "LIVESTOCK BLIGHT" when >= 6 of a faction's animals die in one
##     day. Both via court.publish_story with kind "news" (never "war").
##
## Pure sim — no rendering, no input, no audio. Own day_changed hook.
## Save/load via to_dict/from_dict (registered in save_system.gd).


const BUMPER_HARVEST_FOOD := 2000.0  # one faction's day total -> Gazette
const DIEOFF_DEATHS := 6             # one faction's day deaths -> Gazette

## Civic Adviser harvest-digest lines. %d = field food, %d = livestock food.
const DIGEST_LINES: Array[String] = [
	"Harvest report: the fields gave us %d food today, livestock another %d. Full bellies all round.",
	"Good news from the farms: %d food from the fields, %d from the herds. The granaries are smiling.",
	"The farmers check in: %d food harvested, %d from livestock. Nobody goes hungry on my watch.",
	"Field report: %d food in from the crops, %d from the animals. Eat up.",
	"Harvest tally: %d from the fields, %d from the livestock. The cooks are already bragging.",
]


var _gs  # GameState (untyped: avoids a cyclic class reference)
var _crop: Dictionary = {}    # faction -> float crop food tallied today
var _stock: Dictionary = {}   # faction -> float livestock food tallied today
var _deaths: Dictionary = {}  # faction -> int animals died today
var _bumper_day: Dictionary = {}  # faction -> day already headlined
var _blight_day: Dictionary = {}  # faction -> day already headlined
var _digest_day := -1
var _rng := RandomNumberGenerator.new()


func _init(game_state) -> void:
	_gs = game_state
	_rng.randomize()
	if _gs == null or _gs.get("bus") == null:
		return
	var bus = _gs.bus
	if bus.has_signal("farm_harvested"):
		bus.farm_harvested.connect(_on_harvest)
	if bus.has_signal("animal_yield"):
		bus.animal_yield.connect(_on_yield)
	if bus.has_signal("animal_died"):
		bus.animal_died.connect(_on_died)
	if bus.has_signal("day_changed"):
		bus.day_changed.connect(_on_day)


## --- tally ---------------------------------------------------------------

func _plot_faction(plot_id: int) -> String:
	var farming = _gs.get("farming")
	if farming == null:
		return ""
	for plot: Dictionary in farming.plots:
		if int(plot.get("id", 0)) == plot_id:
			return String(plot.get("faction", ""))
	return ""


func _on_harvest(plot_id: int, food: float, _seeds: float) -> void:
	var faction := _plot_faction(plot_id)
	if faction == "":
		return
	_crop[faction] = float(_crop.get(faction, 0.0)) + food


func _on_yield(_plot_id: int, faction: String, total: float) -> void:
	if faction == "":
		return
	_stock[faction] = float(_stock.get(faction, 0.0)) + total


func _on_died(plot_id: int, _animal_id: int, _cause: String,
		_type: String) -> void:
	var faction := _plot_faction(plot_id)
	if faction == "":
		return
	_deaths[faction] = int(_deaths.get(faction, 0)) + 1


## --- day boundary: digest + Gazette, then reset --------------------------

func _on_day(day_number: int, _is_night: bool) -> void:
	var pf := String(_gs.player_faction)
	var crop := float(_crop.get(pf, 0.0))
	var stock := float(_stock.get(pf, 0.0))
	if crop + stock > 0.0 and day_number != _digest_day:
		_send_digest(day_number, crop, stock)
	var court = _court()
	if court != null:
		for faction: String in _crop.keys():
			var total := float(_crop.get(faction, 0.0)) \
				+ float(_stock.get(faction, 0.0))
			if total >= BUMPER_HARVEST_FOOD \
					and int(_bumper_day.get(faction, -1)) != day_number:
				_bumper_day[faction] = day_number
				court.publish_story("BUMPER HARVEST",
					"%s's granaries overflow: %d food harvested in a single day. The bakers are showing off."
					% [faction.capitalize(), int(total)], "news")
		for faction: String in _deaths.keys():
			var n := int(_deaths.get(faction, 0))
			if n >= DIEOFF_DEATHS \
					and int(_blight_day.get(faction, -1)) != day_number:
				_blight_day[faction] = day_number
				court.publish_story("LIVESTOCK BLIGHT",
					"%d %s farm animals died today. The carrion crows are getting fat."
					% [n, faction.capitalize()], "news")
	_crop.clear()
	_stock.clear()
	_deaths.clear()


func _send_digest(day_number: int, crop: float, stock: float) -> void:
	var adv := _civic_advisor()
	if adv.is_empty():
		return
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	var line: String = DIGEST_LINES[_rng.randi() % DIGEST_LINES.size()]
	phone.npc_message(int(adv.get("id", 0)), line % [int(crop), int(stock)])
	_digest_day = day_number


## The player's living Civic Adviser (mirrors SimRulersVoice._advisor_by_job;
## kept local so this module never depends on the Ruler's Voice).
func _civic_advisor() -> Dictionary:
	var pf := String(_gs.player_faction)
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		if String(u.get("job", "")) == "advisor_civic":
			return u
	return {}


func _court():
	if _gs == null:
		return null
	var court = _gs.get("court_sys")
	if court == null or not court.has_method("publish_story"):
		return null
	return court


## --- save / load ----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"crop": _crop.duplicate(),
		"stock": _stock.duplicate(),
		"deaths": _deaths.duplicate(),
		"bumper_day": _bumper_day.duplicate(),
		"blight_day": _blight_day.duplicate(),
		"digest_day": _digest_day,
	}


func from_dict(data: Dictionary) -> void:
	_crop = (data.get("crop", {}) as Dictionary).duplicate()
	_stock = (data.get("stock", {}) as Dictionary).duplicate()
	_deaths = (data.get("deaths", {}) as Dictionary).duplicate()
	_bumper_day = (data.get("bumper_day", {}) as Dictionary).duplicate()
	_blight_day = (data.get("blight_day", {}) as Dictionary).duplicate()
	_digest_day = int(data.get("digest_day", -1))
