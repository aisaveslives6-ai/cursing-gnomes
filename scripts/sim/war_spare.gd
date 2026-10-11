class_name SimWarSpare
extends RefCounted

## War-spare fate votes + negotiable peace treaties (Jeremy 2026-10-11).
##
## When a faction's town hall is CAPTURED or DESTROYED by a WAR enemy (a real
## faction — never disasters: nature doesn't get a trial), every other faction
## votes SPARE or END on the fallen faction. Votes are likes-driven
## (relations, decayed history, grudges, reputation). Majority spare -> all
## the loser's wars end and a peace treaty with real terms (tribute,
## reparations, demilitarized zone) is signed; terms are negotiable
## afterwards. Majority kill -> no mercy: the war grinds on.
##
## The player votes too (clear SPARE / END THEM UI in the phone); when the
## player's own hall falls, the other factions vote on the player.
##
## Hooks: bus.command_post_captured (hall captures), bus.building_destroyed
## (hall destructions; b["destroyed_by"] is set in SimCombat.damage_building),
## bus.day_changed (tribute collection, term expiry, DMZ enforcement),
## bus.war_declared (spare-warning enforcement).
## Wired as game.war_spare in world.gd; save/load in save_system.gd.


const VOTE_COOLDOWN_DAYS := 10
const TREATY_DURATION_DAYS := 30
const TRIBUTE_DAYS := 20
const DMZ_RADIUS := 420.0
const NEGOTIATE_COOLDOWN_DAYS := 5
const NO_MERCY_TRUCE_BLOCK_DAYS := 30

## Playable factions (Config.FACTIONS keys) — only these can trigger a fate
## vote. "fire"/"monster"/"" are nature: no trial, no vote.
const _PLAYABLE := ["humans", "ogres", "elves", "gnomes", "undead"]


var _gs = null
var _active_vote: Dictionary = {}
var _treaties: Array = []
var _treaty_seq := 0
var _vote_seq := 0
var _warnings: Dictionary = {}   # faction -> {day, treaty_id, guarantors}
var _vote_cooldown: Dictionary = {}  # loser -> day of last vote
var _neg_cooldown: Dictionary = {}  # "treatyid:termidx" -> day
var _no_mercy_until: Dictionary = {}  # pair key -> day (post-condemn truce block)


func _init(game_state) -> void:
	_gs = game_state
	var bus = _gs.get("bus")
	if bus == null:
		return
	if bus.has_signal("command_post_captured"):
		bus.command_post_captured.connect(_on_post_captured)
	if bus.has_signal("building_destroyed"):
		bus.building_destroyed.connect(_on_building_destroyed)
	if bus.has_signal("day_changed"):
		bus.day_changed.connect(_on_day)
	if bus.has_signal("war_declared"):
		bus.war_declared.connect(_on_war_declared)


func _fname(faction: String) -> String:
	var d: Dictionary = Config.FACTIONS.get(faction, {})
	var n := String(d.get("name", ""))
	return n if n != "" else faction.capitalize()


func _voice(faction: String) -> String:
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return "diplomatic"
	return String(fl.leader_of(faction).get("voice", "diplomatic"))


func _lname(faction: String) -> String:
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return _fname(faction)
	var n := String(fl.leader_of(faction).get("name", ""))
	return n if n != "" else _fname(faction)


## --- favor model (shared with the disaster-aid vote) -------------------------


## Likes-driven favor of voter toward subject. Returns {score, driver, detail}.
## Positive = likes them. Used by the fate vote AND the aid vote.
static func favor_score(gs, voter: String, subject: String) -> Dictionary:
	var dip = gs.diplomacy
	var score := float(dip.relation_score(voter, subject))
	var drivers: Array = []
	var g := float(dip.grudge_against(voter, subject))
	if absf(g) > 0.05:
		var w := g * 8.0
		score += w
		drivers.append({"label": "grudge", "weight": w})
	var rep := (float(dip.reputation_of(subject)) - 60.0) * 0.25
	if absf(rep) > 1.0:
		score += rep
		drivers.append({"label": "reputation", "weight": rep})
	var st := String(dip.relation_state(voter, subject))
	if st == "war":
		score -= 15.0
		drivers.append({"label": "at_war", "weight": -15.0})
	elif st == "allied":
		score += 15.0
		drivers.append({"label": "allied", "weight": 15.0})
	elif st == "friendly":
		score += 8.0
		drivers.append({"label": "friendly", "weight": 8.0})
	# Decayed history: the strongest remembered deed colors the vote.
	var hist: Array = dip.pair_history(voter, subject)
	var now: float = float(gs.game_time)
	var best: Dictionary = {}
	var best_w := 0.0
	for e in hist:
		var et := String(e.get("type", ""))
		var base := float(_EVENT_FAVOR.get(et, 0.0))
		if base == 0.0:
			continue
		# Direction: deeds BY the subject toward the voter count most.
		var by := String(e.get("by", ""))
		var w := base if by == subject else base * 0.4
		var age_days := maxf(0.0, now - float(e.get("game_time", now))) \
			/ float(Config.DAY_LENGTH_SECONDS)
		w *= pow(0.7, age_days / 7.0)
		if absf(w) > absf(best_w):
			best_w = w
			best = {"type": et, "by": by, "days_ago": age_days}
	if best_w != 0.0:
		score += best_w
		drivers.append({"label": "memory:" + String(best.get("type", "")),
			"weight": best_w, "detail": best})
	drivers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a.get("weight", 0.0))) \
			> absf(float(b.get("weight", 0.0))))
	var top := String(drivers[0].get("label", "none")) if not drivers.is_empty() \
		else "none"
	return {"score": score, "driver": top,
		"detail": drivers[0].get("detail", {}) if not drivers.is_empty() else {}}


## Event-type favor weights for the vote model (decayed, direction-aware).
const _EVENT_FAVOR := {
	"aid_given": 25.0,
	"tribute_paid": 12.0,
	"alliance_signed": 15.0,
	"peace_made": 10.0,
	"surrender_accepted": 8.0,
	"surrender_offered": 4.0,
	"trade_signed": 6.0,
	"war_declared": -20.0,
	"treaty_broken": -25.0,
	"threatened": -10.0,
	"surrender_refused": -6.0,
	"tribute_refused": -8.0,
	"aid_refused": -12.0,
}


## --- vote trigger ------------------------------------------------------------


func _on_post_captured(kind: String, _bid: int, old: String, new_f: String,
		_pos: Vector2) -> void:
	if kind != "town":
		return
	if old == "" or new_f == "" or old == new_f:
		return
	if not (old in _PLAYABLE) or not (new_f in _PLAYABLE):
		return
	_start_vote(old, new_f, "captured")


func _on_building_destroyed(b: Dictionary) -> void:
	if not String(b.get("type", "")) in SimTerritory.CLAIM_TYPES:
		return
	var loser := String(b.get("faction", ""))
	var destroyer := String(b.get("destroyed_by", ""))
	if loser == "" or destroyer == "" or loser == destroyer:
		return
	# Nature doesn't get a trial — disasters are the aid vote's business.
	if not (destroyer in _PLAYABLE):
		return
	if not (loser in _PLAYABLE):
		return
	_start_vote(loser, destroyer, "destroyed")


func _start_vote(loser: String, taker: String, via: String) -> void:
	if not _active_vote.is_empty():
		return  # one fate at a time
	if not (loser in _gs.active_factions):
		return
	var last: int = int(_vote_cooldown.get(loser, -1000))
	if _gs.day_number - last < VOTE_COOLDOWN_DAYS:
		return
	_vote_cooldown[loser] = _gs.day_number
	_vote_seq += 1
	var pf: String = _gs.player_faction
	var votes: Array = []
	for voter: String in _gs.active_factions:
		if voter == loser:
			continue
		if voter == pf:
			votes.append({"voter": voter, "vote": "pending",
				"score": 0.0, "reason": ""})
			continue
		votes.append(_ai_vote(voter, loser, taker))
	var town_name := _town_name_of(loser)
	_active_vote = {
		"id": _vote_seq, "loser": loser, "taker": taker,
		"town": town_name, "via": via, "day": _gs.day_number,
		"votes": votes, "player_votes": pf != loser and pf != "",
		"player_vote": "pending", "resolved": false, "result": "",
		"wars": war_list_for(loser),
	}
	var bus = _gs.get("bus")
	if bus != null and bus.has_signal("spare_vote_started"):
		bus.spare_vote_started.emit(_public_vote())
	# AI-only vote (player is the fallen): resolve at once; the modal still
	# shows the drama.
	if not bool(_active_vote.get("player_votes", false)):
		resolve_vote()


func _town_name_of(faction: String) -> String:
	for tid in _gs.towns:
		var t: Dictionary = _gs.towns[tid]
		if String(t.get("faction", "")) == faction:
			return String(t.get("name", "their town"))
	return "their lands"


func _ai_vote(voter: String, loser: String, taker: String) -> Dictionary:
	# The conqueror votes to finish what they started. Always.
	if voter == taker:
		return {"voter": voter, "vote": "kill", "score": -999.0,
			"reason": _taker_line(voter, loser)}
	var favor: Dictionary = favor_score(_gs, voter, loser)
	var sc := float(favor.get("score", 0.0))
	var spare := sc > 0.0
	return {"voter": voter, "vote": "spare" if spare else "kill",
		"score": sc,
		"reason": _voiced_line(voter, loser, spare,
			String(favor.get("driver", "none")),
			favor.get("detail", {}))}


func _taker_line(voter: String, loser: String) -> String:
	match _voice(voter):
		"blunt":
			return "We didn't march all this way for a hug. END THEM."
		"elegant":
			return "The campaign ends but one way. We vote END."
		_:
			return "We came to finish this. We vote END."


## Voiced vote reason per faction voice, winning driver, and verdict.
func _voiced_line(voter: String, loser: String, spare: bool, driver: String,
		_detail: Dictionary) -> String:
	var subj := _fname(loser)
	var v := _voice(voter)
	var key := driver
	if key.begins_with("memory:"):
		key = driver.substr(7)
	if spare:
		match key:
			"aid_given":
				match v:
					"blunt":
						return "%s fed us when we were starving. SPARE." % subj
					"elegant":
						return "We remember the grain ships of the famine year. We vote SPARE."
					_:
						return "When famine struck our fields, %s sent grain. We vote SPARE." % subj
			"tribute_paid":
				return "Their gold kept our forges lit. We vote SPARE."
			"alliance_signed", "allied":
				return "They stood beside us. We do not abandon friends. SPARE."
			"peace_made", "surrender_accepted":
				return "They chose peace when they could have chosen blood. We honor that. SPARE."
			"reputation":
				return "Their name is clean in every court. We vote SPARE."
			"friendly":
				return "They are our friends. SPARE."
			"grudge":
				return "Old debts are settled, not nursed. We vote SPARE."
			_:
				return "We have no quarrel worth a grave. We vote SPARE."
	else:
		match key:
			"war_declared":
				return "They brought war to our door. END THEM."
			"treaty_broken":
				match v:
					"blunt":
						return "Oathbreakers get no mercy. END THEM."
					"elegant":
						return "An oath broken is a soul forfeit. We vote END."
					_:
						return "They swore peace and broke it. END THEM."
			"grudge":
				return "We have not forgotten what they did. END THEM."
			"at_war":
				return "We are at war with them. We vote END."
			"reputation":
				return "Every court whispers of their cruelty. END THEM."
			_:
				return "The land is better without them. We vote END."


## --- the war list (who's fighting the fallen, and why) ------------------------


## Every faction currently at war with `loser`, with the casus belli pulled
## from real war data: who declared, how long, top grievances.
func war_list_for(loser: String) -> Array:
	var out: Array = []
	var dip = _gs.diplomacy
	for f: String in _gs.active_factions:
		if f == loser:
			continue
		if dip.relation_state(loser, f) != "war":
			continue
		var hist: Array = dip.pair_history(loser, f)
		var declared_by := ""
		var war_days := 0
		for e in hist:
			if String(e.get("type", "")) == "war_declared":
				declared_by = String(e.get("by", ""))
				var age: float = maxf(0.0, float(_gs.game_time) \
					- float(e.get("game_time", _gs.game_time)))
				war_days = int(age / float(Config.DAY_LENGTH_SECONDS))
				break
		var griev: Array = []
		for e in hist:
			var w := float(_EVENT_FAVOR.get(String(e.get("type", "")), 0.0))
			if w < -5.0:
				griev.append({"type": String(e.get("type", "")),
					"by": String(e.get("by", ""))})
				if griev.size() >= 3:
					break
		out.append({"faction": f, "declared_by": declared_by,
			"war_days": war_days, "grievances": griev})
	return out


## --- player vote + resolution --------------------------------------------------


func active_vote() -> Dictionary:
	return _active_vote


func _public_vote() -> Dictionary:
	var v: Dictionary = (_active_vote as Dictionary).duplicate(true)
	for e in v.get("votes", []):
		e["voter_name"] = _fname(String(e.get("voter", "")))
		e["leader"] = _lname(String(e.get("voter", "")))
	for w in v.get("wars", []):
		w["faction_name"] = _fname(String(w.get("faction", "")))
		var db := String(w.get("declared_by", ""))
		w["declared_by_name"] = _fname(db) if db != "" else ""
	v["loser_name"] = _fname(String(v.get("loser", "")))
	v["taker_name"] = _fname(String(v.get("taker", "")))
	return v


## The player's SPARE / END THEM vote. Resolves the vote immediately after.
func cast_player_vote(spare: bool) -> Dictionary:
	if _active_vote.is_empty():
		return {"ok": false, "msg": "No vote is in progress."}
	if not bool(_active_vote.get("player_votes", false)):
		return {"ok": false, "msg": "You do not vote in this one."}
	if String(_active_vote.get("player_vote", "pending")) != "pending":
		return {"ok": false, "msg": "You already voted."}
	_active_vote["player_vote"] = "spare" if spare else "kill"
	for e in _active_vote.get("votes", []):
		if String(e.get("voter", "")) == _gs.player_faction:
			e["vote"] = "spare" if spare else "kill"
			e["score"] = 999.0 if spare else -999.0
			e["reason"] = "The crown has spoken."
	return resolve_vote()


func resolve_vote() -> Dictionary:
	if _active_vote.is_empty() or bool(_active_vote.get("resolved", false)):
		return {"ok": false, "msg": "No open vote."}
	var spare := 0
	var kill := 0
	for e in _active_vote.get("votes", []):
		if String(e.get("vote", "")) == "spare":
			spare += 1
		elif String(e.get("vote", "")) == "kill":
			kill += 1
		# "pending" (shouldn't happen at resolve) counts as abstain.
	var result := "spared" if spare > kill else "condemned"
	_active_vote["resolved"] = true
	_active_vote["result"] = result
	_active_vote["spare_count"] = spare
	_active_vote["kill_count"] = kill
	var loser := String(_active_vote.get("loser", ""))
	var taker := String(_active_vote.get("taker", ""))
	if result == "spared":
		_apply_spared(loser, taker, spare, kill)
	else:
		_apply_condemned(loser, taker, spare, kill)
	var bus = _gs.get("bus")
	if bus != null and bus.has_signal("spare_vote_resolved"):
		bus.spare_vote_resolved.emit(_public_vote())
	_active_vote = {}
	return {"ok": true, "result": result, "spare": spare, "kill": kill}


## --- resolution: SPARED --------------------------------------------------------


func _apply_spared(loser: String, taker: String, spare: int, kill: int) -> void:
	var dip = _gs.diplomacy
	# The war ends immediately: peace with every faction at war with the loser.
	var ended: Array = []
	for w in war_list_for(loser):
		var f := String(w.get("faction", ""))
		if dip.relation_state(loser, f) == "war":
			dip.make_peace(loser, f)
			ended.append(f)
	# Faction-by-faction goodwill: spare voters warm to the loser.
	var guarantors: Array = []
	for e in _active_vote.get("votes", []):
		var v := String(e.get("voter", ""))
		if String(e.get("vote", "")) == "spare":
			guarantors.append(v)
			dip.adjust_score(v, loser, 10.0)
	dip.adjust_score(taker, loser, -10.0)  # grudging peace
	var treaty := _generate_treaty(loser, taker, guarantors)
	_sign_treaty(treaty)
	# The stern warning: break this peace and the guarantors remember.
	_warnings[loser] = {"day": _gs.day_number,
		"treaty_id": int(treaty.get("id", 0)), "guarantors": guarantors}
	SimGazette.publish_or_emit(_gs,
		"SPARED: the %s live — %d to %d" % [_fname(loser), spare, kill],
		"On day %d, the factions of the land voted on the fate of the %s. %d voted SPARE, %d voted END. The wars end. A peace treaty with real terms has been signed — and the %s have been warned: break it, and every hand that spared them will turn." % [
			_gs.day_number, _fname(loser), spare, kill, _fname(loser)],
		"war", {"urgent": loser == _gs.player_faction})
	var bus = _gs.get("bus")
	if bus != null and bus.has_signal("treaty_signed"):
		bus.treaty_signed.emit(_public_treaty(treaty))


func _apply_condemned(loser: String, taker: String, spare: int,
		kill: int) -> void:
	var dip = _gs.diplomacy
	# No mercy: the war grinds on, the conqueror emboldened.
	dip.adjust_score(taker, loser, -25.0)
	dip.adjust_score(loser, taker, -25.0)
	_no_mercy_until[_pair_key(taker, loser)] = _gs.day_number \
		+ NO_MERCY_TRUCE_BLOCK_DAYS
	SimGazette.publish_or_emit(_gs,
		"NO MERCY: the %s are condemned — %d to %d" % [_fname(loser), kill,
			spare],
		"On day %d, the factions voted on the fate of the %s. %d voted END, %d voted SPARE. There will be no peace, no treaty, no quarter — the war grinds on to its bitter end." % [
			_gs.day_number, _fname(loser), kill, spare],
		"war", {"urgent": loser == _gs.player_faction})


func _pair_key(a: String, b: String) -> String:
	var parts := [a, b]
	parts.sort()
	return "%s|%s" % [parts[0], parts[1]]


## --- peace treaties ------------------------------------------------------------


func _generate_treaty(loser: String, taker: String,
		guarantors: Array) -> Dictionary:
	_treaty_seq += 1
	var dip = _gs.diplomacy
	# War context: how long did the loser fight the taker?
	var war_days := 0
	for w in war_list_for(loser):
		if String(w.get("faction", "")) == taker:
			war_days = int(w.get("war_days", 0))
	# Terms scale with the loser's means and the war's length.
	var treasury := float(_gs.resources.get_amount(loser, "gold"))
	var tribute_day := int(clampf(treasury * 0.05, 20.0, 200.0))
	var reparations := int(clampf(treasury * 0.15, 100.0, 1500.0))
	var dmz_days := TREATY_DURATION_DAYS
	return {
		"id": _treaty_seq,
		"loser": loser, "taker": taker,
		"guarantors": guarantors.duplicate(),
		"town": String(_active_vote.get("town", "")),
		"day_signed": _gs.day_number,
		"duration_days": TREATY_DURATION_DAYS,
		"war_days": war_days,
		"status": "active",
		"terms": [
			{"kind": "tribute", "resource": "gold",
				"amount_per_day": tribute_day, "days_left": TRIBUTE_DAYS,
				"status": "active",
				"label": "Tribute: %d gold/day to the %s for %d days" % [
					tribute_day, _fname(taker), TRIBUTE_DAYS]},
			{"kind": "reparations", "gold": reparations, "status": "active",
				"label": "Reparations: %d gold to the %s (paid at signing)" % [
					reparations, _fname(taker)]},
			{"kind": "dmz", "radius": DMZ_RADIUS, "days_left": dmz_days,
				"status": "active",
				"label": "Demilitarized border: no %s troops within %dpx of %s towns for %d days" % [
					_fname(loser), int(DMZ_RADIUS), _fname(taker), dmz_days]},
		],
		"warning": "The %s have been SPARED by vote of the land. Break this peace — miss tribute, cross the demilitarized border, or raise war again — and every faction that voted to spare them will turn." % [
			_fname(loser)],
	}


func _sign_treaty(treaty: Dictionary) -> void:
	var loser := String(treaty.get("loser", ""))
	var taker := String(treaty.get("taker", ""))
	# Reparations move at signing.
	for t in treaty.get("terms", []):
		if String(t.get("kind", "")) == "reparations":
			var amt := float(t.get("gold", 0.0))
			var have := float(_gs.resources.get_amount(loser, "gold"))
			var paid := minf(amt, have)
			_gs.resources.add_resource(loser, "gold", -paid)
			_gs.resources.add_resource(taker, "gold", paid)
			t["paid"] = paid
	_treaties.append(treaty)
	var dip = _gs.diplomacy
	dip.adjust_score(loser, taker, 5.0)
	dip.adjust_score(taker, loser, 5.0)


func treaties_for(faction: String) -> Array:
	var out: Array = []
	for t in _treaties:
		if String(t.get("status", "")) != "active":
			continue
		if String(t.get("loser", "")) == faction \
				or String(t.get("taker", "")) == faction:
			out.append(t)
	return out


func get_treaty(treaty_id: int) -> Dictionary:
	for t in _treaties:
		if int(t.get("id", 0)) == treaty_id:
			return t
	return {}


func _public_treaty(t: Dictionary) -> Dictionary:
	var c: Dictionary = (t as Dictionary).duplicate(true)
	c["loser_name"] = _fname(String(t.get("loser", "")))
	c["taker_name"] = _fname(String(t.get("taker", "")))
	var gn: Array = []
	for g in t.get("guarantors", []):
		gn.append(_fname(String(g)))
	c["guarantor_names"] = gn
	return c


func treaty_summary(t: Dictionary) -> String:
	var lines: Array = []
	lines.append("Peace treaty: %s ↔ %s (day %d, %d days)" % [
		_fname(String(t.get("loser", ""))), _fname(String(t.get("taker", ""))),
		int(t.get("day_signed", 0)), int(t.get("duration_days", 0))])
	for i in t.get("terms", []).size():
		var term: Dictionary = t["terms"][i]
		lines.append("  [%d] %s — %s" % [i + 1,
			String(term.get("label", "")), String(term.get("status", ""))])
	return "\n".join(lines)


## --- negotiating terms down ------------------------------------------------------


func _term_burden(term: Dictionary) -> float:
	match String(term.get("kind", "")):
		"tribute":
			return float(term.get("amount_per_day", 0)) \
				* float(term.get("days_left", 0))
		"dmz":
			return 500.0 + 20.0 * float(term.get("days_left", 0))
	return 0.0


## Public remaining-burden estimate for a term (phone negotiate UI).
func term_burden(term: Dictionary) -> float:
	return _term_burden(term)


## Negotiate to lift a treaty term after accepting. `by` defaults to the
## player. The taker evaluates: gold offered + goodwill vs remaining burden.
## Lifting everything is possible but costly — no free lunch.
func negotiate_term(treaty_id: int, term_idx: int, gold_offer: float,
		by: String = "") -> Dictionary:
	var t := get_treaty(treaty_id)
	if t.is_empty():
		return {"ok": false, "accepted": false, "msg": "No such treaty."}
	if String(t.get("status", "")) != "active":
		return {"ok": false, "accepted": false, "msg": "Treaty is not active."}
	var terms: Array = t.get("terms", [])
	if term_idx < 0 or term_idx >= terms.size():
		return {"ok": false, "accepted": false, "msg": "No such term."}
	var term: Dictionary = terms[term_idx]
	if String(term.get("status", "")) != "active":
		return {"ok": false, "accepted": false,
			"msg": "That term is already %s." % String(term.get("status", ""))}
	var pf: String = _gs.player_faction
	var who := by if by != "" else pf
	var loser := String(t.get("loser", ""))
	var taker := String(t.get("taker", ""))
	if who != loser and who != taker:
		return {"ok": false, "accepted": false,
			"msg": "You are not party to this treaty."}
	if String(term.get("kind", "")) == "reparations":
		return {"ok": false, "accepted": false,
			"msg": "Reparations were paid at signing — that coin is spent."}
	# Cooldown per term.
	var ck := "%d:%d" % [treaty_id, term_idx]
	var last: int = int(_neg_cooldown.get(ck, -1000))
	if _gs.day_number - last < NEGOTIATE_COOLDOWN_DAYS:
		return {"ok": false, "accepted": false,
			"msg": "They will not discuss it again so soon."}
	var dip = _gs.diplomacy
	# The taker forgiving their own term: mercy, always accepted.
	if who == taker:
		term["status"] = "lifted"
		dip.adjust_score(taker, loser, 8.0)
		dip.adjust_score(loser, taker, 8.0)
		_check_treaty_done(t)
		return {"ok": true, "accepted": true,
			"msg": "The %s lift the term freely — mercy remembered." % [
				_fname(taker)]}
	# The loser buys the term out.
	if gold_offer < 0.0:
		return {"ok": false, "accepted": false, "msg": "Invalid offer."}
	var have := float(_gs.resources.get_amount(loser, "gold"))
	if gold_offer > have:
		return {"ok": false, "accepted": false,
			"msg": "You don't have %d gold to offer." % int(gold_offer)}
	var burden := _term_burden(term)
	var goodwill := maxf(0.0, float(dip.relation_score(taker, loser))) * 2.0
	var value := gold_offer + goodwill
	_neg_cooldown[ck] = _gs.day_number
	# No free lunch: even beloved friends pay at least a quarter.
	var price := maxf(burden * 0.9, burden * 0.25)
	if value >= price and gold_offer >= burden * 0.25:
		_gs.resources.add_resource(loser, "gold", -gold_offer)
		_gs.resources.add_resource(taker, "gold", gold_offer)
		term["status"] = "lifted"
		dip.adjust_score(taker, loser, 5.0)
		_check_treaty_done(t)
		return {"ok": true, "accepted": true,
			"msg": "The %s accept %d gold — the term is lifted." % [
				_fname(taker), int(gold_offer)]}
	dip.adjust_score(taker, loser, -3.0)
	return {"ok": true, "accepted": false,
		"msg": _refusal_line(taker, term, burden)}


func _refusal_line(taker: String, term: Dictionary, burden: float) -> String:
	match _voice(taker):
		"blunt":
			return "The %s laugh in your face. \"Not enough, %s.\"" % [
				_fname(taker), "whelp" if _gs.player_faction == String(
					term.get("loser", "")) else "friend"]
		"elegant":
			return "The %s decline with practiced courtesy. The price of peace is not yet paid." % [
				_fname(taker)]
		_:
			return "The %s refuse — %d gold worth of hurt does not wash out cheap." % [
				_fname(taker), int(burden)]


func _check_treaty_done(t: Dictionary) -> void:
	for term in t.get("terms", []):
		if String(term.get("status", "")) == "active":
			return
	t["status"] = "completed"
	SimGazette.publish_or_emit(_gs,
		"Treaty fulfilled: %s and %s" % [_fname(String(t.get("loser", ""))),
			_fname(String(t.get("taker", "")))],
		"Every term of the day-%d peace treaty has been lifted or served. The %s walk free of it." % [
			int(t.get("day_signed", 0)), _fname(String(t.get("loser", "")))],
		"court")


## --- breaking ----------------------------------------------------------------------


## Break a treaty (missed tribute, DMZ violation, renewed war). Real teeth:
## reputation cratered, every guarantor turns hostile, Gazette scandal.
func break_treaty(treaty_id: int, reason: String, by: String = "") -> Dictionary:
	var t := get_treaty(treaty_id)
	if t.is_empty() or String(t.get("status", "")) != "active":
		return {"ok": false, "msg": "No active treaty."}
	var who := by if by != "" else String(t.get("loser", ""))
	t["status"] = "broken"
	t["broken_reason"] = reason
	t["broken_by"] = who
	var dip = _gs.diplomacy
	dip.tarnish_reputation(who, -25.0)
	var other := String(t.get("taker", "")) if who == String(t.get(
		"loser", "")) else String(t.get("loser", ""))
	for g in t.get("guarantors", []):
		var gf := String(g)
		if gf == who:
			continue
		dip.adjust_score(gf, who, -50.0)
	dip.adjust_score(other, who, -40.0)
	SimGazette.publish_or_emit(_gs,
		"OATHBREAKER: the %s tear up the peace!" % [_fname(who)],
		"On day %d the %s broke the peace treaty (%s). Every faction that voted to spare them has turned — the land will remember this treachery." % [
			_gs.day_number, _fname(who), reason],
		"court", {"urgent": who == _gs.player_faction})
	var bus = _gs.get("bus")
	if bus != null and bus.has_signal("treaty_broken"):
		bus.treaty_broken.emit(who, other)
	_warnings.erase(who)
	return {"ok": true, "msg": "Treaty broken. The land turns against the oathbreaker."}


## --- day tick: tribute, expiry, DMZ --------------------------------------------------


func _on_day(day_number: int, _is_night: bool) -> void:
	for t in _treaties:
		if String(t.get("status", "")) != "active":
			continue
		var loser := String(t.get("loser", ""))
		var taker := String(t.get("taker", ""))
		var tid := int(t.get("id", 0))
		for term in t.get("terms", []):
			if String(term.get("status", "")) != "active":
				continue
			match String(term.get("kind", "")):
				"tribute":
					var days := int(term.get("days_left", 0))
					if days <= 0:
						term["status"] = "expired"
						continue
					var amt := float(term.get("amount_per_day", 0.0))
					var have := float(_gs.resources.get_amount(
						loser, String(term.get("resource", "gold"))))
					if have < amt:
						break_treaty(tid, "missed tribute", loser)
						break
					_gs.resources.add_resource(loser,
						String(term.get("resource", "gold")), -amt)
					_gs.resources.add_resource(taker,
						String(term.get("resource", "gold")), amt)
					term["days_left"] = days - 1
					if int(term.get("days_left", 0)) <= 0:
						term["status"] = "expired"
				"dmz":
					var ddays := int(term.get("days_left", 0))
					if ddays <= 0:
						term["status"] = "expired"
						continue
					if _dmz_violated(t, term):
						break_treaty(tid, "troops crossed the demilitarized border",
							loser)
						break
					term["days_left"] = ddays - 1
					if int(term.get("days_left", 0)) <= 0:
						term["status"] = "expired"
		_check_treaty_done(t)
	# Warnings fade when their treaty ends.
	for f in _warnings.keys():
		var w: Dictionary = _warnings[f]
		if _gs.day_number - int(w.get("day", 0)) \
				>= int(get_treaty(int(w.get("treaty_id", 0))).get(
					"duration_days", TREATY_DURATION_DAYS)):
			_warnings.erase(f)


func _dmz_violated(t: Dictionary, term: Dictionary) -> bool:
	var loser := String(t.get("loser", ""))
	var taker := String(t.get("taker", ""))
	var radius := float(term.get("radius", DMZ_RADIUS))
	# Taker town positions.
	var tpos: Array = []
	for tid in _gs.towns:
		var town: Dictionary = _gs.towns[tid]
		if String(town.get("faction", "")) == taker:
			tpos.append(town.get("position", Vector2.ZERO))
	if tpos.is_empty():
		return false
	for u in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != loser:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		var up: Vector2 = u.get("position", Vector2.ZERO)
		for tp in tpos:
			if up.distance_to(tp) <= radius:
				return true
	return false


## --- warning enforcement -----------------------------------------------------------


func _on_war_declared(a: String, _b: String) -> void:
	if not _warnings.has(a):
		return
	var w: Dictionary = _warnings[a]
	var t := get_treaty(int(w.get("treaty_id", 0)))
	if t.is_empty() or String(t.get("status", "")) != "active":
		_warnings.erase(a)
		return
	# The spared bites the hand: every guarantor turns hostile.
	var dip = _gs.diplomacy
	for g in w.get("guarantors", []):
		var gf := String(g)
		if gf == a:
			continue
		dip.adjust_score(gf, a, -60.0)
	dip.tarnish_reputation(a, -20.0)
	SimGazette.publish_or_emit(_gs,
		"THE SPARED BITES: the %s raise war again!" % [_fname(a)],
		"Spared by vote of the land on day %d, the %s have taken up arms again. Every faction that voted to spare them now turns its face away — some reach for swords." % [
			int(w.get("day", 0)), _fname(a)],
		"war", {"urgent": a == _gs.player_faction})
	_warnings.erase(a)


## --- save/load -------------------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"treaties": _treaties,
		"treaty_seq": _treaty_seq,
		"vote_seq": _vote_seq,
		"warnings": _warnings,
		"vote_cooldown": _vote_cooldown,
		"neg_cooldown": _neg_cooldown,
		"no_mercy_until": _no_mercy_until,
	}


func from_dict(data: Dictionary) -> void:
	_treaties = (data.get("treaties", []) as Array).duplicate(true)
	_treaty_seq = int(data.get("treaty_seq", 0))
	_vote_seq = int(data.get("vote_seq", 0))
	_warnings = (data.get("warnings", {}) as Dictionary).duplicate(true)
	_vote_cooldown = (data.get("vote_cooldown", {}) as Dictionary).duplicate(true)
	_neg_cooldown = (data.get("neg_cooldown", {}) as Dictionary).duplicate(true)
	_no_mercy_until = (data.get("no_mercy_until", {}) as Dictionary).duplicate(
		true)
	_active_vote = {}
