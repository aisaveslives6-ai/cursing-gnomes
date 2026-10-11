class_name SimHandyman
extends RefCounted
## Cursing Gnomes — the Wandering Handyman tribute event (Jeremy 2026-10-06).
##
## Faithful port of the HTML build's CANDIDATE19 ("Jeremy the Wandering
## Handyman"): a rare, gentle, ONE-PER-GAME world event. A modest spark-driver
## named Jeremy passes through and repairs the most-damaged completed building
## for free — or, if nothing is broken, leaves a stack of seasoned lumber by
## the depot. Comedic Gazette writeup included.
##
## HTML mechanics (fix79/index.html, jeremyHandymanTick), ported verbatim:
##   - one-per-game flag (jeremyHandymanDone; persisted in save/load)
##   - 10-minute real-time grace period for new games; old saves have no
##     clock value so the gate is skipped (from_dict zeroes the clock)
##   - daily roll on the day tick: day >= 3, 10% chance
##   - candidates: alive + complete buildings, NOT walls ("he fixes homes,
##     not battlements"), with hp below 90% of max_hp; player's faction
##     first, then most-damaged first
##   - repair: hp restored to max_hp; one of 3 verbatim stories; Gazette
##     'THE WANDERING HANDYMAN' + player toast (HTML systemMsg)
##   - lumber fallback: +40 wood to the player's faction; verbatim story
##
## Port notes:
##   - stories route through court.publish_story so they land in the
##     Chronicle archive AND the bus (2026-10-06 Gazette rule); the
##     sanitizer strips the wrench glyph for the phone newspaper, and the
##     toast sanitizer does the same for the banner — the HTML strings are
##     kept verbatim here.
##   - the player toast goes over a new bus.toast signal (HTML systemMsg
##     parity); the story itself is non-urgent so it does not trip the
##     urgent banner twice.
##   - "city" in the HTML stories is the player's faction city name; towns
##     have unique per-town names in the port, so the repair story names the
##     actual town that was repaired (falling back to the player's first
##     town, then "town").
##   - HTML's floating 'repaired!' text has no port-side floating-text
##     mechanism; the toast + Gazette story carry the player feedback.
##
## Pure sim: own day_changed hook, no per-frame work, no rendering,
## no input, no audio, no network.

## HTML-verbatim tuning.
const MIN_DAY := 3
const DAILY_CHANCE := 0.10
const GRACE_MSEC := 600_000          # 10 real minutes for new games
const LUMBER_WOOD := 40.0
const HEADLINE := "THE WANDERING HANDYMAN"

## Verbatim HTML story templates ({city}, {tname}, {missing}, {racename}).
const REPAIR_STORIES: Array[String] = [
	"A quiet man named Jeremy \u2014 a spark-driver by trade, handy with anything that has bolts \u2014 passed through {city} today and repaired the {tname} without being asked. He patched {missing} points of wear, declined all payment, and was gone before anyone could thank him properly. The local gnomes are deeply unsettled: \"He fixed it WITHOUT cursing at it?? Not once?? What is he HIDING.\"",
	"Witnesses report a soft-spoken traveler called Jeremy fixing up the {racename} {tname} in {city} this afternoon, whistling while he worked. When the foreman tried to pay him, Jeremy just shrugged and said it beat sitting around. The gnomes have filed a formal complaint: nobody fixes things around here without at least SOME swearing.",
	"The {tname} of {city} stands whole again, thanks to a wandering handyman named Jeremy who \"was just passing through\" and \"had the tools in the truck.\" He asked for nothing, took nothing, and was gone by supper. Town elders confirm the repair is sound; town gnomes confirm they are \"watching him\" anyway.",
]
const LUMBER_STORY := "With nothing broken to fix, a wandering handyman named Jeremy left a neat stack of seasoned lumber by the {city} depot \u2014 \"for whatever breaks next.\" The gnomes immediately began arguing about whether free wood is a trap. The wood is, in fact, just wood."

var _gs  # GameState (untyped: avoids a cyclic class reference)
var _done: bool = false
var _started_msec: int = 0


func _init(game_state) -> void:
	_gs = game_state
	# Fresh clock per new game (World constructs one instance per game).
	_started_msec = Time.get_ticks_msec()
	if _gs != null and _gs.get("bus") != null:
		_gs.bus.day_changed.connect(_on_day)


func _court():
	if _gs == null:
		return null
	var court = _gs.get("court_sys")
	if court == null or not court.has_method("publish_story"):
		return null
	return court


func _player_faction() -> String:
	if _gs == null:
		return ""
	var pf = _gs.get("player_faction")
	return "" if pf == null else String(pf)


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


func _town_name_for(b: Dictionary) -> String:
	if _gs != null:
		var towns: Dictionary = _gs.get("towns")
		if towns != null:
			var t = towns.get(int(b.get("town_id", -1)), null)
			if t is Dictionary:
				var n := String((t as Dictionary).get("name", ""))
				if n != "":
					return n
	var fallback := _player_town_name()
	return fallback if fallback != "" else "town"


## HTML jeremyHandymanTick gates: done flag, 10-minute grace, day >= 3,
## 10% daily roll. Never throws (must not break the day tick).
func _on_day(day_number: int, _is_night: bool) -> void:
	if _done:
		return
	if _started_msec > 0 and Time.get_ticks_msec() - _started_msec < GRACE_MSEC:
		return
	if day_number < MIN_DAY:
		return
	if randf() > DAILY_CHANCE:
		return
	_fire()


## Repair candidates, HTML-verbatim: alive + complete, not walls, damaged
## below 90% of max. Sorted player's-faction-first, then most-damaged.
func _candidates() -> Array:
	var out: Array = []
	if _gs == null:
		return out
	var pf := _player_faction()
	for b in _gs.buildings:
		if not (b is Dictionary):
			continue
		var bd: Dictionary = b
		if not bool(bd.get("alive", false)):
			continue
		if not bool(bd.get("complete", false)):
			continue
		if String(bd.get("type", "")) == "wall":
			continue
		var max_hp := float(bd.get("max_hp", 0.0))
		if max_hp <= 0.0:
			continue
		var hp := float(bd.get("hp", max_hp))
		if hp >= max_hp * 0.9:
			continue
		out.append({
			"b": bd,
			"mine": 1 if String(bd.get("faction", "")) == pf else 0,
			"frac": hp / max_hp,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["mine"] != b["mine"]:
			return a["mine"] > b["mine"]
		return a["frac"] < b["frac"])
	return out


## Fires the event: repair the top candidate, or leave lumber.
## Returns "repair", "lumber", or "" when nothing happened.
func _fire() -> String:
	if _done:
		return ""
	var pf := _player_faction()
	var cands := _candidates()
	var kind := ""
	if not cands.is_empty():
		var pick: Dictionary = (cands[0] as Dictionary)["b"]
		var max_hp := float(pick.get("max_hp", 0.0))
		var missing := maxi(1, int(round(max_hp - float(pick.get("hp", max_hp)))))
		pick["hp"] = max_hp  # real repair, real HP (HTML-verbatim)
		var tname: String = SimBuildings.display_name(
			String(pick.get("type", "building")), String(pick.get("faction", "")))
		var story: String = REPAIR_STORIES[randi_range(0, REPAIR_STORIES.size() - 1)]
		story = story.replace("{city}", _town_name_for(pick))
		story = story.replace("{tname}", tname)
		story = story.replace("{missing}", str(missing))
		story = story.replace("{racename}", _faction_pretty(String(pick.get("faction", ""))))
		_publish(story)
		_toast("\U0001F527 A wandering handyman repaired the %s \u2014 free of charge." % tname)
		kind = "repair"
	else:
		if pf != "" and _gs.get("resources") != null:
			_gs.resources.add_resource(pf, "wood", LUMBER_WOOD)
		var city := _player_town_name()
		if city == "":
			city = "town"
		_publish(LUMBER_STORY.replace("{city}", city))
		_toast("\U0001F527 A wandering handyman left 40 seasoned lumber by the depot.")
		kind = "lumber"
	_done = true
	return kind


func _publish(story: String) -> void:
	var court = _court()
	if court != null:
		court.publish_story(HEADLINE, story, "court")


func _toast(text: String) -> void:
	if _gs != null and _gs.get("bus") != null:
		_gs.bus.toast.emit(text)


## --- Save/load ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"done": _done}


func from_dict(data: Dictionary) -> void:
	_done = bool(data.get("done", false))
	# Old saves (and the HTML loader) carry no clock: skip the grace gate.
	_started_msec = 0
