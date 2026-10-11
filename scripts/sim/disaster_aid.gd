class_name SimDisasterAid
extends RefCounted

## Disaster aid votes + helper missions (Jeremy 2026-10-11).
##
## When a faction's town hall is destroyed by a NATURAL DISASTER (fire,
## monsters, or unknown causes — never a real faction; nature doesn't get a
## trial), there is no fate vote. Instead every other faction votes on
## whether to SEND AID. Each yes-voter dispatches worker/builder NPCs who
## visibly travel to the stricken faction's territory, repair and help
## rebuild for a while, then return home. The kindness is remembered:
## relations improve, feeding the likes model future votes use.
##
## Applies to the player in both directions: the player's hall can be the
## stricken one (others vote to help YOU), and the player votes on — and can
## join — aid for others.
##
## Hooks: bus.building_destroyed (b["destroyed_by"] not a playable faction),
## bus.day_changed (mission expiry bookkeeping). tick(delta) drives helper
## movement/repair/return (wired in world.gd like other sim ticks).
## Save/load via to_dict/from_dict (wired in save_system.gd).


const AID_DURATION_DAYS := 5
const HELPERS_PER_FACTION := 3
const AID_VOTE_COOLDOWN_DAYS := 10
const RELATION_BOOST := 15.0

## Aid-eligible helper jobs.
const HELPER_JOBS := ["worker", "builder"]

## Sources that count as natural disaster (no fate vote, aid vote instead).
const DISASTER_SOURCES := ["", "fire", "monster"]


var _gs = null
var _missions: Array = []
var _mission_seq := 0
var _active_vote: Dictionary = {}
var _vote_cooldown: Dictionary = {}  # victim -> day
var _tick_accum := 0.0


func _init(game_state) -> void:
	_gs = game_state
	var bus = _gs.get("bus")
	if bus == null:
		return
	if bus.has_signal("building_destroyed"):
		bus.building_destroyed.connect(_on_building_destroyed)
	if bus.has_signal("day_changed"):
		bus.day_changed.connect(_on_day)


func _fname(faction: String) -> String:
	var d: Dictionary = Config.FACTIONS.get(faction, {})
	var n := String(d.get("name", ""))
	return n if n != "" else faction.capitalize()


func _lname(faction: String) -> String:
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return _fname(faction)
	var n := String(fl.leader_of(faction).get("name", ""))
	return n if n != "" else _fname(faction)


## --- trigger ---------------------------------------------------------------------


func _on_building_destroyed(b: Dictionary) -> void:
	if not String(b.get("type", "")) in SimTerritory.CLAIM_TYPES:
		return
	var victim := String(b.get("faction", ""))
	var source := String(b.get("destroyed_by", ""))
	if victim == "":
		return
	# A real faction did this -> the fate vote's business, not ours.
	if not (source in DISASTER_SOURCES):
		return
	_start_aid_vote(victim, b.get("position", Vector2.ZERO), source)


func _start_aid_vote(victim: String, ruin_pos: Vector2, cause: String) -> void:
	if not _active_vote.is_empty():
		return
	if not (victim in _gs.active_factions):
		return
	var last: int = int(_vote_cooldown.get(victim, -1000))
	if _gs.day_number - last < AID_VOTE_COOLDOWN_DAYS:
		return
	_vote_cooldown[victim] = _gs.day_number
	_mission_seq += 1
	var pf: String = _gs.player_faction
	var votes: Array = []
	for voter: String in _gs.active_factions:
		if voter == victim:
			continue
		if voter == pf:
			votes.append({"voter": voter, "vote": "pending",
				"score": 0.0, "reason": ""})
			continue
		votes.append(_ai_aid_vote(voter, victim))
	_active_vote = {
		"id": _mission_seq, "victim": victim, "ruin_pos": ruin_pos,
		"cause": cause, "day": _gs.day_number, "votes": votes,
		"player_votes": pf != victim and pf != "",
		"player_vote": "pending", "resolved": false, "result": "",
	}
	var bus = _gs.get("bus")
	if bus != null and bus.has_signal("aid_vote_started"):
		bus.aid_vote_started.emit(_public_vote())
	if not bool(_active_vote.get("player_votes", false)):
		resolve_vote()


## Disaster generosity: the bar for kindness is lower than for mercy.
## Only real haters refuse.
func _ai_aid_vote(voter: String, victim: String) -> Dictionary:
	var favor: Dictionary = SimWarSpare.favor_score(_gs, voter, victim)
	var sc := float(favor.get("score", 0.0))
	var yes := sc > -15.0
	return {"voter": voter, "vote": "yes" if yes else "no", "score": sc,
		"reason": _aid_line(voter, victim, yes,
			String(favor.get("driver", "none")))}


func _aid_line(voter: String, victim: String, yes: bool,
		driver: String) -> String:
	var subj := _fname(victim)
	if yes:
		if driver.begins_with("memory:aid_given") \
				or driver == "tribute_paid":
			return "They helped us once. Debts like that get repaid. We send aid."
		if driver == "allied" or driver.begins_with("memory:alliance"):
			return "They are our friends. Our builders are already packing. YES."
		if driver == "at_war" or driver.begins_with("memory:war_declared"):
			return "War or no war, no one should starve in the ashes. We send aid."
		return "The fire does not care whose roof it takes. We send our people. YES."
	if driver.begins_with("memory:treaty_broken"):
		return "They broke bread with us and spat it out. Let the ashes teach them. NO."
	if driver == "at_war" or driver.begins_with("memory:war_declared"):
		return "We are at war with them. Our builders stay home. NO."
	return "We have troubles of our own. NO."


func active_vote() -> Dictionary:
	return _active_vote


func _public_vote() -> Dictionary:
	var v: Dictionary = (_active_vote as Dictionary).duplicate(true)
	for e in v.get("votes", []):
		e["voter_name"] = _fname(String(e.get("voter", "")))
		e["leader"] = _lname(String(e.get("voter", "")))
	v["victim_name"] = _fname(String(v.get("victim", "")))
	v["cause_text"] = _cause_text(String(v.get("cause", "")))
	return v


func _cause_text(cause: String) -> String:
	match cause:
		"fire":
			return "a great fire"
		"monster":
			return "a monster rampage"
		_:
			return "a natural disaster"


## The player's SEND AID / DECLINE vote.
func cast_player_vote(help: bool) -> Dictionary:
	if _active_vote.is_empty():
		return {"ok": false, "msg": "No aid vote in progress."}
	if not bool(_active_vote.get("player_votes", false)):
		return {"ok": false, "msg": "You do not vote in this one."}
	if String(_active_vote.get("player_vote", "pending")) != "pending":
		return {"ok": false, "msg": "You already voted."}
	_active_vote["player_vote"] = "yes" if help else "no"
	for e in _active_vote.get("votes", []):
		if String(e.get("voter", "")) == _gs.player_faction:
			e["vote"] = "yes" if help else "no"
			e["score"] = 999.0 if help else -999.0
			e["reason"] = "The crown has spoken."
	return resolve_vote()


func resolve_vote() -> Dictionary:
	if _active_vote.is_empty() or bool(_active_vote.get("resolved", false)):
		return {"ok": false, "msg": "No open aid vote."}
	var helpers: Array = []
	for e in _active_vote.get("votes", []):
		if String(e.get("vote", "")) == "yes":
			helpers.append(String(e.get("voter", "")))
	_active_vote["resolved"] = true
	_active_vote["result"] = "aided" if not helpers.is_empty() else "alone"
	_active_vote["helpers"] = helpers
	var victim := String(_active_vote.get("victim", ""))
	var mission: Dictionary = {}
	if not helpers.is_empty():
		mission = _start_mission(victim, helpers,
			_active_vote.get("ruin_pos", Vector2.ZERO))
		_active_vote["mission_id"] = int(mission.get("id", 0))
	SimGazette.publish_or_emit(_gs,
		"Neighbors rush aid to the %s" % [_fname(victim)] if not helpers.is_empty()
		else "No aid for the %s" % [_fname(victim)],
		"On day %d, %s answered the %s' ruin with builders and strong backs. Kindness will be remembered." % [
			_gs.day_number,
			", ".join(helpers.map(func(f: String) -> String: return _fname(f))),
			_fname(victim)]
		if not helpers.is_empty()
		else "On day %d, no faction voted to aid the %s after %s. The ashes settle in silence." % [
			_gs.day_number, _fname(victim),
			_cause_text(String(_active_vote.get("cause", "")))],
		"court", {"urgent": victim == _gs.player_faction})
	var bus = _gs.get("bus")
	if bus != null and bus.has_signal("aid_vote_resolved"):
		bus.aid_vote_resolved.emit(_public_vote())
	_active_vote = {}
	return {"ok": true, "result": "aided" if not helpers.is_empty() else "alone",
		"helpers": helpers, "mission": mission}


## --- missions: dispatch, work, return ----------------------------------------------


func _start_mission(victim: String, helpers: Array,
		ruin_pos: Vector2) -> Dictionary:
	var until: int = _gs.day_number + AID_DURATION_DAYS
	var dispatched: Array = []
	for h in helpers:
		var hf := String(h)
		var count := 0
		for u in _gs.units:
			if count >= HELPERS_PER_FACTION:
				break
			if not bool(u.get("alive", false)):
				continue
			if String(u.get("faction", "")) != hf:
				continue
			if not (String(u.get("job", "")) in HELPER_JOBS):
				continue
			if u.has("aid_mission"):
				continue
			if JobDefs.is_military(String(u.get("job", ""))):
				continue
			u["aid_mission"] = {
				"victim": victim,
				"home_pos": u.get("position", Vector2.ZERO),
				"site_pos": ruin_pos,
				"until_day": until,
				"phase": "travel",
			}
			# Guests don't fight and don't defect: park their normal duties.
			u["work_state"] = "aid_travel"
			u["work_target_pos"] = ruin_pos
			dispatched.append(int(u.get("id", 0)))
			count += 1
	var mission := {"id": _mission_seq, "victim": victim,
		"helpers": helpers.duplicate(), "unit_ids": dispatched,
		"day_started": _gs.day_number, "until_day": until,
		"ruin_pos": ruin_pos, "status": "active"}
	_missions.append(mission)
	var bus = _gs.get("bus")
	if bus != null and bus.has_signal("aid_mission_started"):
		bus.aid_mission_started.emit(mission.duplicate())
	return mission


## Per-frame driver (1 Hz internally): travel -> repair -> return home.
func tick(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < 1.0:
		return
	_tick_accum = 0.0
	for m in _missions:
		if String(m.get("status", "")) != "active":
			continue
		var victim := String(m.get("victim", ""))
		var expired: bool = _gs.day_number >= int(m.get("until_day", 0))
		for u in _gs.units:
			if not bool(u.get("alive", false)):
				continue
			if not u.has("aid_mission"):
				continue
			var am: Dictionary = u["aid_mission"]
			if String(am.get("victim", "")) != victim:
				continue
			_tick_helper(u, am, victim, expired)
		if expired and _mission_units_done(m):
			_finish_mission(m)


## Repair speed (hp/sec per helper) and the radius they canvas for damage.
const _AID_REPAIR_RATE := 10.0
const _AID_WORK_RADIUS := 320.0


func _tick_helper(u: Dictionary, am: Dictionary, victim: String,
		expired: bool) -> void:
	var phase := String(am.get("phase", "travel"))
	if expired and phase != "return":
		am["phase"] = "return"
		u["work_state"] = "aid_return"
		u["work_target_pos"] = am.get("home_pos", Vector2.ZERO)
		u.erase("work_building")
		phase = "return"
	match phase:
		"travel":
			if WorkerAI.move_unit(_gs, u,
					am.get("site_pos", Vector2.ZERO), 1.0):
				am["phase"] = "work"
				u["work_state"] = "idle"
		"work":
			_helper_work(u, victim)
		"return":
			if WorkerAI.move_unit(_gs, u,
					am.get("home_pos", Vector2.ZERO), 1.0):
				u.erase("aid_mission")
				u["work_state"] = "idle"


## A helper at work: find the most damaged victim building nearby and
## repair it with real work behavior (walk to it, hammer away, hp rises).
func _helper_work(u: Dictionary, victim: String) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_key := INF
	for b in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != victim:
			continue
		var frac: float = float(b.get("hp", 1.0)) \
			/ maxf(1.0, float(b.get("max_hp", 1.0)))
		if frac >= 1.0:
			continue
		var d: float = upos.distance_to(b.get("position", Vector2.ZERO))
		if d > _AID_WORK_RADIUS:
			continue
		var key: float = d + frac * 10000.0  # most damaged first
		if key < best_key:
			best_key = key
			best = b
	if best.is_empty():
		u["work_pose"] = "idle"  # nothing left to fix: rest at the site
		return
	var bpos: Vector2 = best.get("position", Vector2.ZERO)
	if upos.distance_to(bpos) > 48.0:
		WorkerAI.move_unit(_gs, u, bpos, 1.0)
		u["work_pose"] = "walk"
	else:
		best["hp"] = minf(float(best.get("max_hp", 100.0)),
			float(best.get("hp", 0.0)) + _AID_REPAIR_RATE)
		u["work_pose"] = "work"


func _mission_units_done(m: Dictionary) -> bool:
	for uid in m.get("unit_ids", []):
		var u: Dictionary = _gs.get_unit(int(uid))
		if not u.is_empty() and u.has("aid_mission"):
			return false
	return true


func _finish_mission(m: Dictionary) -> void:
	m["status"] = "done"
	var victim := String(m.get("victim", ""))
	var dip = _gs.diplomacy
	# Kindness remembered: the helped faction warms to every helper.
	for h in m.get("helpers", []):
		var hf := String(h)
		dip.adjust_score(victim, hf, RELATION_BOOST)
		# Feed the likes model: aid_given in the pair history.
		dip.record_event(victim, hf, "aid_given", hf)
	SimGazette.publish_or_emit(_gs,
		"Aid mission ends: builders head home",
		"After %d days of honest work, the %s' helpers return home from %s lands. %s will not forget it." % [
			AID_DURATION_DAYS,
			", ".join((m.get("helpers", []) as Array).map(
				func(f) -> String: return _fname(String(f)))),
			_fname(victim), _fname(victim)],
		"court")
	var bus = _gs.get("bus")
	if bus != null and bus.has_signal("aid_mission_done"):
		bus.aid_mission_done.emit((m as Dictionary).duplicate())


func missions_for(faction: String) -> Array:
	var out: Array = []
	for m in _missions:
		# Finished missions are history, not current work (treaties_for
		# filters the same way) — callers want the active missions.
		if String(m.get("status", "")) != "active":
			continue
		if String(m.get("victim", "")) == faction \
				or String(faction) in (m.get("helpers", []) as Array).map(
					func(f) -> String: return String(f)):
			out.append(m)
	return out


func _on_day(_day_number: int, _is_night: bool) -> void:
	# Expiry is handled in tick() via until_day; nothing daily needed.
	pass


## --- save/load -------------------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"missions": _missions,
		"mission_seq": _mission_seq,
		"vote_cooldown": _vote_cooldown,
	}


func from_dict(data: Dictionary) -> void:
	_missions = (data.get("missions", []) as Array).duplicate(true)
	_mission_seq = int(data.get("mission_seq", 0))
	_vote_cooldown = (data.get("vote_cooldown", {}) as Dictionary).duplicate(true)
	_active_vote = {}
	# Re-mark live helper units (their aid_mission dicts were saved on the
	# units themselves via the unit records — nothing extra needed).


## --- player-initiated aid (Jeremy 2026-10-11 power tap menu) ---------------------------
## Outside of war, the player can tap a foreign faction's land and send aid
## directly: resources, a builder crew, or a full relief caravan. Reuses the
## mission driver above (travel -> repair -> return) and the same relations
## model — kindness is remembered and feeds the likes model future votes use.
## Aid is always the player's explicit order; nothing here auto-fires.


## Per-faction per-day caps so aid can't be spammed for infinite relations.
var _player_aid_day: Dictionary = {}  # faction -> day of last player aid


## Builder crew: dispatches the player's own workers/builders to the victim's
## land. They repair with real work behavior, then return home.
func dispatch_player_aid(victim: String, site_pos: Vector2) -> Dictionary:
	var me := String(_gs.player_faction)
	if victim == "" or victim == me:
		return {"ok": false, "msg": "That's your own land."}
	if not (victim in _gs.active_factions):
		return {"ok": false, "msg": "Unknown faction."}
	if _gs.diplomacy.relation_state(me, victim) == "war":
		return {"ok": false,
			"msg": "You are at war with the %s — aid would feed the enemy." % _fname(victim)}
	for m in _missions:
		if String(m.get("status", "")) == "active" \
				and String(m.get("victim", "")) == victim \
				and me in (m.get("helpers", []) as Array).map(
					func(f) -> String: return String(f)):
			return {"ok": false,
				"msg": "Your crew is already helping the %s." % _fname(victim)}
	var crew := 0
	for u in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != me:
			continue
		if not (String(u.get("job", "")) in HELPER_JOBS):
			continue
		if u.has("aid_mission"):
			continue
		if JobDefs.is_military(String(u.get("job", ""))):
			continue
		crew += 1
		if crew >= HELPERS_PER_FACTION:
			break
	if crew <= 0:
		return {"ok": false,
			"msg": "No free workers or builders to send."}
	var mission := _start_mission(victim, [me], site_pos)
	_player_aid_day[victim] = _gs.day_number
	# Goodwill now; the bigger boost lands when the mission completes.
	_gs.diplomacy.adjust_score(victim, me, 5.0)
	_gs.diplomacy.record_event(victim, me, "aid_given", me)
	SimGazette.publish_or_emit(_gs,
		"%s sends builders to %s lands" % [_fname(me), _fname(victim)],
		"On day %d, %s dispatched a builder crew to help the %s rebuild. Kindness is never forgotten." % [
			_gs.day_number, _fname(me), _fname(victim)],
		"court")
	return {"ok": true, "mission": mission,
		"msg": "Builder crew dispatched to %s lands." % _fname(victim)}


## Resource aid: straight transfer of food/wood/gold/oil. Costs real
## stockpile; the helped faction warms to you.
func send_player_resources(victim: String, resource: String,
		amount: float) -> Dictionary:
	var me := String(_gs.player_faction)
	if victim == "" or victim == me:
		return {"ok": false, "msg": "That's your own land."}
	if not (victim in _gs.active_factions):
		return {"ok": false, "msg": "Unknown faction."}
	if _gs.diplomacy.relation_state(me, victim) == "war":
		return {"ok": false,
			"msg": "You are at war with the %s — no aid for the enemy." % _fname(victim)}
	if not (resource in Config.RESOURCES):
		return {"ok": false, "msg": "Unknown resource."}
	var day: int = _gs.day_number
	var key := "res:%s" % victim
	if int(_player_aid_day.get(key, -99)) == day:
		var n := int(_player_aid_day.get(key + ":n", 0))
		if n >= 3:
			return {"ok": false,
				"msg": "You've sent enough aid to the %s today." % _fname(victim)}
	var have: float = _gs.resources.get_amount(me, resource)
	var sent: float = minf(maxf(0.0, amount), have)
	if sent <= 0.0:
		return {"ok": false, "msg": "You have no %s to send." % resource}
	_gs.resources.add_resource(me, resource, -sent)
	_gs.resources.add_resource(victim, resource, sent)
	_gs.diplomacy.adjust_score(victim, me, 8.0)
	_gs.diplomacy.record_event(victim, me, "aid_given", me)
	_player_aid_day[key] = day
	_player_aid_day[key + ":n"] = int(_player_aid_day.get(key + ":n", 0)) + 1
	var bus = _gs.get("bus")
	if bus != null and bus.has_signal("aid_shipment_sent"):
		bus.aid_shipment_sent.emit(me, victim, resource, sent)
	SimGazette.publish_or_emit(_gs,
		"%s sends %s to the %s" % [_fname(me), resource, _fname(victim)],
		"On day %d, %d %s changed hands from %s to %s — aid, freely given." % [
			day, int(sent), resource, _fname(me), _fname(victim)],
		"court")
	return {"ok": true, "sent": sent,
		"msg": "Sent %d %s to the %s." % [int(sent), resource, _fname(victim)]}
