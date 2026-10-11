class_name SimFounding
extends RefCounted
## Cursing Gnomes — the founding beat (Jeremy 2026-10-09 wake routine).
##
## New games opened with no ceremony: the player landed in their town with
## nothing but a tutorial offer. This is the opening beat every new game
## gets — the living-world welcome:
##   1. a Gazette founding story (name-roast included: the scribes asked
##      twice about the ruler's name, and the ruler said it twice), and
##   2. a Messenger DM from the Civic Advisor (in-voice welcome + the first
##      directive: fed workers, manned walls, a smiling treasury),
##   3. a player toast pointing at the Gazette.
##
## Fires once per game, on the FIRST day_changed (day 1 -> 2 transition,
## half a game-day after the midday start — the world and phone are up by
## then). One-per-game flag persisted in save/load; old saves (day > 2,
## no key) are marked done silently — no retroactive founding spam.
##
## Player faction only. DM skipped gracefully when no cabinet adviser is
## alive (the Gazette still fires). Never throws: must not break the day
## tick. ASCII only — the Gazette and toast sanitizers strip non-ASCII
## for the phone newspaper.
##
## Wiring (same shape as SimHandyman):
##   world.gd:            game.founding = SimFounding.new(game)
##   save_system.gd:      "founding" encode + from_dict restore

## The first day_changed a new game emits is day 2 (start = midday day 1).
const FIRE_DAY := 2

const HEADLINE := "A KINGDOM RISES"

## {town}, {faction} (pretty), {ruler} (verbatim — naming law: never strip).
const STORIES: Array[String] = [
	"The banners are up in {town}, the horns are hoarse, and the {faction} have a new ruler: {ruler}. (The scribes asked twice. Twice, {ruler} said.) The crown fits, the throne holds, and the treasury has already opened a ledger titled 'Regrettable Decisions'. Festivities continue until someone does the math.",
	"Word from {town}: the {faction} crown a new sovereign today - {ruler}, by name and by choice. The royal tailor was seen measuring twice and sighing once. The army has sworn its oaths; the kitchens have sworn nothing and are watching the grain stores.",
	"{town} wakes under a new banner. {ruler} of the {faction} takes the throne with all the confidence of someone who has never seen the tax ledgers. The court applauds; the treasury weeps; the gnomes, as always, place bets.",
]

const WELCOME_DM := "My {ruler}, {town} stands and the {faction} look to you. Keep the workers fed, keep the walls manned, and never let the treasury see you smile. I will mind the ledgers - you mind the kingdom. Welcome to the job."

## DM sender preference: civic first, then the rest of the cabinet.
const ADVISER_JOBS: Array[String] = ["advisor_civic", "advisor_economy",
	"advisor_war", "guild_master"]

var _gs  # GameState (untyped: avoids a cyclic class reference)
var _done: bool = false


func _init(game_state) -> void:
	_gs = game_state
	if _gs != null and _gs.get("bus") != null:
		_gs.bus.day_changed.connect(_on_day)


func _player_faction() -> String:
	if _gs == null:
		return ""
	var pf = _gs.get("player_faction")
	return "" if pf == null else String(pf)


func _ruler_name() -> String:
	if _gs == null:
		return "sire"
	var rn = _gs.get("ruler_name")
	# Jeremy's naming law: verbatim, no strip/trim/case changes.
	return String(rn) if rn != null and String(rn) != "" else "sire"


func _faction_pretty(faction: String) -> String:
	return String(Config.FACTIONS.get(faction, {}).get("name", faction))


## The player's first town name (lowest town id), or "" when unknown.
func _player_town_name() -> String:
	if _gs == null:
		return ""
	var towns: Dictionary = _gs.get("towns")
	if towns == null or towns.is_empty():
		return ""
	var pf := _player_faction()
	var best_id := -1
	for tid in towns.keys():
		var t: Dictionary = towns[tid]
		if String(t.get("faction", "")) != pf:
			continue
		var iid := int(tid)
		if best_id < 0 or iid < best_id:
			best_id = iid
	if best_id < 0:
		return ""
	return String((towns[best_id] as Dictionary).get("name", ""))


## First living cabinet adviser of the player's faction, or {}.
func _adviser() -> Dictionary:
	if _gs == null:
		return {}
	var pf := _player_faction()
	for job: String in ADVISER_JOBS:
		for u: Dictionary in _gs.units:
			if not bool(u.get("alive", false)):
				continue
			if String(u.get("faction", "")) != pf:
				continue
			if String(u.get("job", "")) == job:
				return u
	return {}


## First day_changed of a fresh game fires at day 2; anything later means
## an old save (or a missed tick) — mark done, never fire retroactively.
func _on_day(day_number: int, _is_night: bool) -> void:
	if _done:
		return
	if day_number < FIRE_DAY:
		return
	_done = true
	if day_number > FIRE_DAY:
		return  # old save: silent
	_fire()


## Fires the beat: Gazette story, adviser DM, toast. Returns the headline
## story record, or {} when nothing happened (no player faction).
func _fire() -> Dictionary:
	var pf := _player_faction()
	if pf == "":
		return {}
	var town := _player_town_name()
	if town == "":
		town = "town"
	var ruler := _ruler_name()
	var faction := _faction_pretty(pf)
	var story: String = STORIES[randi_range(0, STORIES.size() - 1)]
	story = story.replace("{town}", town)
	story = story.replace("{faction}", faction)
	story = story.replace("{ruler}", ruler)
	var court = _gs.get("court_sys") if _gs != null else null
	var rec: Dictionary = {}
	# Jeremy 2026-10-09 (hearsay flesh-out): the rumor mill gets the
	# founding with the town, faction, and ruler attached BEFORE the
	# Gazette story publishes — a rich named rumor the realm reacts to
	# in character, not a thin party-less headline.
	if _gs != null and _gs.get("bus") != null:
		_gs.bus.kingdom_founded.emit(town, pf, ruler)
	if court != null and court.has_method("publish_story"):
		rec = court.publish_story(HEADLINE, story, "court")
	_send_welcome_dm(town, faction, ruler)
	_toast("A kingdom rises in %s - the Gazette has the full story." % town)
	return rec


func _send_welcome_dm(town: String, faction: String, ruler: String) -> void:
	var adv := _adviser()
	if adv.is_empty():
		return  # no cabinet adviser alive: the Gazette carries the beat
	var phone = _gs.get("phone_sys") if _gs != null else null
	if phone == null or not phone.has_method("npc_message"):
		return
	var text := WELCOME_DM.replace("{ruler}", ruler)
	text = text.replace("{town}", town)
	text = text.replace("{faction}", faction)
	# phone.npc_message is itself null-safe (blocked/missing threads skip).
	phone.npc_message(int(adv.get("id", 0)), text)


func _toast(text: String) -> void:
	if _gs != null and _gs.get("bus") != null:
		_gs.bus.toast.emit(text)


## --- Save/load ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"done": _done}


func from_dict(data: Dictionary) -> void:
	_done = bool(data.get("done", false))
