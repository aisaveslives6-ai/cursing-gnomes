class_name SimDiplomacy
extends RefCounted
## Cursing Gnomes — full diplomacy system (Milestone 8).
##
## Design ported from the HTML build (not its code): the HTML keeps a
## categorical relation matrix (relations[a][b] = war|neutral|ally|trade)
## plus a numeric score, a gentle drift feed (bcDiplomacyFeed: warm pairs
## climb, cold pairs slide), tribute demand trees, alliance obligations,
## and Gazette-only AI<->AI deals.
##
## Pair-wise relationship states per faction pair:
##   war      — active combat (SimCombat checks combat_enabled)
##   hostile  — tense, but no combat yet
##   neutral  — default
##   friendly — trade bonus +10%
##   allied   — no combat, shared vision, trade bonus +20%, military aid
##
## Each pair also carries a -100..100 opinion score (drives AI decisions
## and drifts daily toward trait compatibility), a trade-agreement contract
## (improved exchange rate + daily caravan exchange), a decayed history of
## interactions (grudges block alliances — SimMemories-style faction
## memory), and per-faction morale + reputation.
##
## Duck-typed `court` (SimRoyalCourt): when set, wars/alliances/treaties
## publish real Gazette stories. AI->player moves arrive as court
## petitions (the crown decides) instead of auto-resolving.
##
## PERFORMANCE: everything runs on a once-per-game-day tick (10 pairs for
## 5 factions) — zero per-frame cost.
##
## Pure logic — no rendering, no input, no audio.


## Relationship states.
const STATES: Array[String] = ["war", "hostile", "neutral", "friendly",
	"allied"]

## Trade bonuses.
const ALLIED_TRADE_BONUS := 0.20
const FRIENDLY_TRADE_BONUS := 0.10
const TRADE_DEAL_BONUS := 0.15

## Score bands that non-locked states follow (war/allied are explicit).
const HOSTILE_BELOW := -20.0
const FRIENDLY_ABOVE := 20.0

const HISTORY_HALFLIFE := 960.0  # 2 game days for a grudge to halve
const GRUDGE_BLOCK := -0.8       # at/below this, alliances are refused
const BETRAYAL_MIN_ALLIANCE_DAYS := 10  # ink must dry: no instant backstabbing
const BETRAYAL_COOLDOWN_DAYS := 15  # a bought-off betrayal buys quiet for a while

## History event weights, from the *victim's* perspective (decayed).
const EVENT_WEIGHT := {
	"war_declared": -2.0,
	"treaty_broken": -2.0,  # betrayal outweighs the signing warmth
	"tribute_demanded": -0.3,
	"tribute_refused": -0.5,
	"alliance_refused": -0.5,
	"tribute_paid": 0.4,
	"alliance_signed": 1.5,
	"trade_signed": 0.8,
	"peace_made": 1.0,
	"aid_given": 1.2,
	"aid_refused": -2.0,  # refusing a wartime ally: a grudge that never fades
	"surrender_offered": 0.5,
	"surrender_accepted": 1.2,
	"surrender_refused": -1.0,
	"threatened": -1.0,  # an outright threat: graver than a tribute demand
}


var _gs: GameState
var _pairs: Dictionary = {}       # "a|b" (sorted) -> pair record
var _morale: Dictionary = {}      # faction -> 0..100
var _reputation: Dictionary = {}  # faction -> 0..100
var _trait_overrides: Dictionary = {}  # faction -> traits (test hook)
var _last_day: int = 1

## Jeremy 2026-10-04: post-peace truces (HTML war32SetTruce parity).
## "a|b" (sorted) -> day number the truce expires. While active, neither
## side may declare war on the other.
var _truces: Dictionary = {}

## Jeremy 2026-10-04: pending surrender offers.
## offer_id -> {loser, winner, tribute, day}. The loser begs for peace;
## the winner decides (player via Royal Court petition, AI auto-resolves).
var _surrender_offers: Dictionary = {}
var _surrender_seq: int = 0

## HTML agri62State.done parity: 'surr:' + war-key + ':' + loser keys already
## answered for that war. A resolved surrender (accepted OR refused) is never
## re-offered for the same war — the war grinds on without repeat begging.
var _surrender_done: Dictionary = {}

## Jeremy 2026-10-05: wartime aid requests (HTML war32AidTick /
## war32AidResolve / war32OnAidIntent parity). An ally at war and LOSING
## (own military < 80% of their strongest foe's) begs the player for help:
## gold (300-800) or troops (4-9 soldiers). HTML-verbatim gating: one
## pending ask per ally, 50% "pride" roll per day. Accept: relation bumps
## (min(30, 10 + amt/100) their view, +10 ours), iron-alliance memory — and,
## beyond the HTML (which only bumped relations), the aid ACTUALLY moves:
## gold changes hands, troops are mustered for them. Refuse: -45 and a
## grudge that never fully fades ("We are DONE.").
var _aid_requests: Dictionary = {}
var _aid_seq: int = 0

## Hiring fee per loaned soldier (the crown musters sellswords for the ally).
const AID_TROOP_COST := 25.0

## Truce length in game days after every peace (HTML: 45).
const TRUCE_DAYS := 45

## Optional SimRoyalCourt (set by the world). Duck-typed to avoid a cyclic
## class reference.
var court = null

## Perf R23: bumped every time any pair's relation STATE changes (war, peace,
## alliance, treaty break, insult downgrade, _sync_state). SimCombat caches
## its per-faction hostile set against this version — identical results,
## zero per-scan diplomacy walks. Not saved: caches live per session.
var relation_version := 0


func _init(game_state: GameState) -> void:
	_gs = game_state


## (Re)initializes every pair to NEUTRAL for a new game.
func reset(faction_ids: Array[String]) -> void:
	_pairs.clear()
	_morale.clear()
	_reputation.clear()
	_truces.clear()
	_surrender_offers.clear()
	_surrender_seq = 0
	_surrender_done.clear()
	_aid_requests.clear()
	_aid_seq = 0
	relation_version += 1  # R23: wholesale pair replace invalidates hostile-set cache
	_last_day = _gs.day_number if _gs.day_number >= 1 else 1
	for f: String in faction_ids:
		_morale[f] = 70.0
		_reputation[f] = 60.0
	for i: int in range(faction_ids.size()):
		for j: int in range(i + 1, faction_ids.size()):
			var a: String = faction_ids[i]
			var b: String = faction_ids[j]
			_pairs[_pair_key(a, b)] = {
				"a": a, "b": b,
				"state": "neutral",
				"score": 0.0,
				"trade_active": false,
				"trade_until_day": 0,
				"war_since_day": 0,
				"history": [],
			}


func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func _pair(a: String, b: String) -> Dictionary:
	return _pairs.get(_pair_key(a, b), {})


## --- queries ----------------------------------------------------------------


## Current state for a pair ("neutral" when unknown).
func relation_state(a: String, b: String) -> String:
	if a == b:
		return "allied"  # a faction is always at peace with itself
	var rec: Dictionary = _pair(a, b)
	return String(rec.get("state", "neutral"))


## Opinion score -100..100 (0 when unknown).
func relation_score(a: String, b: String) -> float:
	var rec: Dictionary = _pair(a, b)
	return float(rec.get("score", 0.0))


## True when factions may fight: only at WAR. (Monsters bypass diplomacy —
## SimCombat.can_fight handles them.)
func combat_enabled(a: String, b: String) -> bool:
	if a == b:
		return false
	return relation_state(a, b) == "war"


## Exchange-rate multiplier for trade between two factions.
func trade_multiplier(a: String, b: String) -> float:
	var m := 1.0
	var st := relation_state(a, b)
	if st == "allied":
		m += ALLIED_TRADE_BONUS
	elif st == "friendly":
		m += FRIENDLY_TRADE_BONUS
	var rec: Dictionary = _pair(a, b)
	if bool(rec.get("trade_active", false)):
		m += TRADE_DEAL_BONUS
	return m


## True when a trade agreement is currently active for the pair.
func has_trade_deal(a: String, b: String) -> bool:
	return bool(_pair(a, b).get("trade_active", false))


## Faction morale 0..100 (70 baseline).
func morale_of(faction: String) -> float:
	return float(_morale.get(faction, 70.0))


## Faction reputation 0..100 (60 baseline). Treaty-breakers lose it; AI
## distrusts low-reputation proposers.
func reputation_of(faction: String) -> float:
	return float(_reputation.get(faction, 60.0))


## Decayed grudge of a against b (negative = a resents b). Faction-level
## memory, SimMemories-style: past interactions shape future deals.
func grudge_against(a: String, b: String) -> float:
	var rec: Dictionary = _pair(a, b)
	var total := 0.0
	for e: Dictionary in rec.get("history", []):
		var w: float = _event_weight_from_view(String(e.get("type", "")),
			String(e.get("by", "")), a, b)
		if w != 0.0:
			total += w * _decayed(e)
	return total


## Canonical per-faction character for AI decisions, sourced from HTML
## FACTION_SOUL (SimFactions). Ogres are inherently more aggressive than
## elves (aggro 1.0 vs 0.35) — no more seeded-random personalities.
## The old brave/friendly/proud/diligent/crude keys are kept for backward
## compatibility, mapped from the canonical values.
func faction_traits(faction: String) -> Dictionary:
	if _trait_overrides.has(faction):
		return _trait_overrides[faction]
	var soul: Dictionary = SimFactions.soul_of(faction)
	var values: Dictionary = soul.get("values", {})
	var military: Dictionary = soul.get("military", {})
	var aggro: float = float(military.get("aggro", 0.5))
	return {
		# Canonical keys (HTML FACTION_SOUL).
		"aggro": aggro,
		"trade_stance": String(soul.get("trade_stance", "steady")),
		"tribute_value": float(values.get("tribute", 0.5)),
		"strength_value": float(values.get("strength", 0.5)),
		"trade_value": float(values.get("trade", 0.5)),
		"diplomacy_value": float(values.get("diplomacy", 0.5)),
		"honor_value": float(values.get("honor", 0.5)),
		"humor_value": float(values.get("humor", 0.5)),
		"ceremony_value": float(values.get("ceremony", 0.5)),
		"military_style": String(military.get("style", "balanced")),
		# Legacy keys (mapped from canonical data).
		"brave": aggro,
		"friendly": float(values.get("diplomacy", 0.5)),
		"proud": float(values.get("honor", 0.5)),
		"diligent": float(values.get("trade", 0.5)),
		"crude": float(values.get("humor", 0.5)),
	}


## Test hook: override a faction's AI traits.
func set_faction_traits(faction: String, traits: Dictionary) -> void:
	_trait_overrides[faction] = traits


## Rough military power: fighters + 1.5 per completed guard tower.
func military_strength(faction: String) -> float:
	var s := 0.0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if JobDefs.is_military(String(u.get("job", ""))):
			s += 1.0
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) == "guard_tower" \
				and String(b.get("faction", "")) == faction \
				and bool(b.get("complete", false)):
			s += 1.5
	return s


## Total stockpiled wealth across all resources.
func faction_wealth(faction: String) -> float:
	var total := 0.0
	for r: String in Config.RESOURCES:
		total += _gs.resources.get_amount(faction, r)
	return total


## --- actions ----------------------------------------------------------------

## Starts a war. Betraying an ally/trade partner costs reputation.
## Hits morale on both sides (war is costly even for the winner).
## Blocked while a post-peace truce is active (HTML diplomacy pacing).
func declare_war(a: String, b: String, reason: String = "") -> Dictionary:
	if a == b:
		return {"ok": false, "msg": "A faction cannot declare war on itself."}
	if truce_active(a, b):
		return {"ok": false, "msg": "A %d-day truce binds %s and %s — \
the war-drums must rest." % [truce_days_left(a, b), _fname(a), _fname(b)]}
	var rec: Dictionary = _pair(a, b)
	if rec.is_empty():
		return {"ok": false, "msg": "Unknown faction pair."}
	if String(rec.get("state", "")) == "war":
		return {"ok": false, "msg": "Already at war."}
	if String(rec.get("state", "")) == "allied" \
			or bool(rec.get("trade_active", false)):
		_add_reputation(a, -15.0)  # betrayal
		_record(a, b, "treaty_broken", a)
	rec["trade_active"] = false
	rec["state"] = "war"
	relation_version += 1  # R23: hostile-set cache invalidation
	rec["score"] = -80.0
	rec["war_since_day"] = _gs.day_number
	# War kills the physical trade layer (HTML declareWar -> dissolveTradeRoutes).
	if _gs.get("trade_routes") != null:
		_gs.trade_routes.dissolve_routes(a, b)
	_record(a, b, "war_declared", a)
	_add_morale(a, -5.0)
	_add_morale(b, -8.0)
	_gs.bus.war_declared.emit(a, b)
	# Jeremy 2026-10-07 (wake audio lane): war declarations finally sound
	# the war horn — stinger at the threatened faction's hall.
	_gs.bus.sfx_spatial.emit("war_horn", _hall_pos(b), Vector2.ZERO)
	_gs.bus.relation_changed.emit(a, b, "war")
	var why: String = " (%s)" % reason if reason != "" else ""
	_report("WAR! %s declares war on %s" % [_fname(a), _fname(b)],
		"On day %d, %s declared war on %s%s. The Gazette's war desk is \
already packing." % [_gs.day_number, _fname(a), _fname(b), why], "war")
	# AI rulers react when the player is involved.
	var pf: String = _gs.player_faction
	if a == pf:
		ruler_react_to("war", {"faction": b})
	elif b == pf:
		ruler_react_to("war", {"faction": a})
	# Third parties answer every declaration — AI-vs-AI wars included.
	_third_party_war_reactions(a, b)
	return {"ok": true, "msg": "%s is now at war with %s." % [_fname(a),
		_fname(b)]}


## Ends a war (war -> neutral). Every peace signs a 45-day truce
## (HTML war32MakePeace parity) — no instant re-declarations.
func make_peace(a: String, b: String) -> Dictionary:
	var rec: Dictionary = _pair(a, b)
	if rec.is_empty():
		return {"ok": false, "msg": "Unknown faction pair."}
	if String(rec.get("state", "")) != "war":
		return {"ok": false, "msg": "They are not at war."}
	rec["state"] = "neutral"
	relation_version += 1  # R23: hostile-set cache invalidation
	rec["score"] = 0.0
	rec["war_since_day"] = 0
	_record(a, b, "peace_made", a)
	_add_morale(a, 6.0)
	_add_morale(b, 6.0)
	set_truce(a, b, TRUCE_DAYS)
	_gs.bus.peace_made.emit(a, b)
	_gs.bus.relation_changed.emit(a, b, "neutral")
	_report("Peace breaks out: %s and %s lay down arms" % [_fname(a),
		_fname(b)],
		"After the drums fell silent, %s and %s signed a peace on day %d. \
Taverns across both lands ran dry by nightfall." % [_fname(a), _fname(b),
		_gs.day_number], "war")
	var pf2: String = _gs.player_faction
	if a == pf2:
		ruler_react_to("peace", {"faction": b})
	elif b == pf2:
		ruler_react_to("peace", {"faction": a})
	return {"ok": true, "msg": "Peace between %s and %s." % [_fname(a),
		_fname(b)]}


## --- truces -----------------------------------------------------------------
## HTML war32SetTruce / war32TruceActive parity: a signed truce blocks new
## war declarations between the pair until it expires.


## Signs a truce between two factions for the given days (default 45).
func set_truce(a: String, b: String, days: int = TRUCE_DAYS) -> void:
	if a == b:
		return
	_truces[_pair_key(a, b)] = _gs.day_number + maxi(1, days)
	# Note: not recorded in pair history — a truce is a mechanical state,
	# not an emotional event (recording warmth here would dilute war grudges).


## True while a truce binds the pair.
func truce_active(a: String, b: String) -> bool:
	if a == b:
		return false
	return _gs.day_number < int(_truces.get(_pair_key(a, b), 0))


## Days remaining on the truce (0 when none).
func truce_days_left(a: String, b: String) -> int:
	if a == b:
		return 0
	return maxi(0, int(_truces.get(_pair_key(a, b), 0)) - _gs.day_number)


## --- surrender --------------------------------------------------------------
## HTML surrenderTick62 / surrenderTribute62 / surrenderResolve62 parity:
## a faction losing badly may sue for peace, offering gold reparations.
## The winner decides — the player through the Royal Court, AI rulers
## auto-resolve (40% accept, like the HTML's AI-vs-AI roll).


## Gold reparations for a surrender (HTML surrenderTribute62 verbatim):
## 10% of the loser's gold + 200, clamped 100..1500.
func surrender_tribute_amount(loser: String, _winner: String) -> int:
	var gold: float = _gs.resources.get_amount(loser, "gold")
	var t: int = int(round(gold * 0.1 + 200.0))
	return maxi(100, mini(1500, t))


## Done-key for a surrender offer: HTML 'surr:' + warKey + ':' + loser. The
## war key is approximated by the pair key + the day the war started, so a
## NEW war between the same pair may see a fresh offer.
func _surrender_done_key(loser: String, winner: String) -> String:
	var rec: Dictionary = _pair(loser, winner)
	return "surr:%s:%s:%d" % [_pair_key(loser, winner), loser,
		int(rec.get("war_since_day", 0))]


## The loser sues for peace. Returns {ok, offer_id, tribute, msg}.
## When the winner is the player, a Royal Court petition is opened for
## the crown to decide; AI-vs-AI offers auto-resolve on the daily tick.
func offer_surrender(loser: String, winner: String) -> Dictionary:
	if loser == winner:
		return {"ok": false, "offer_id": "", "msg": "A faction cannot surrender to itself."}
	if relation_state(loser, winner) != "war":
		return {"ok": false, "offer_id": "",
			"msg": "They are not at war."}
	# One live offer per pair.
	for oid: String in _surrender_offers.keys():
		var o: Dictionary = _surrender_offers[oid]
		if String(o.get("loser", "")) == loser \
				and String(o.get("winner", "")) == winner:
			return {"ok": false, "offer_id": oid,
				"msg": "A surrender offer is already pending."}
	# HTML agri62State.done: one offer per war per loser. A resolved offer
	# (accepted or refused) is never made again for the same war.
	if _surrender_done.has(_surrender_done_key(loser, winner)):
		return {"ok": false, "offer_id": "",
			"msg": "That surrender was already answered for this war."}
	var tribute: int = surrender_tribute_amount(loser, winner)
	_surrender_seq += 1
	var oid2 := "surrender_%d" % _surrender_seq
	_surrender_offers[oid2] = {"loser": loser, "winner": winner,
		"tribute": tribute, "day": _gs.day_number}
	_record(loser, winner, "surrender_offered", loser)
	_gs.bus.surrender_offered.emit(loser, winner)
	_report("SURRENDER OFFERED: the %s yield to the %s" % [_fname(loser),
		_fname(winner)],
		"On day %d, the %s sued for peace — %d gold in reparations if \
the %s accept. The white flag flies over their hall." % [_gs.day_number,
		_fname(loser), tribute, _fname(winner)], "war")
	if winner == _gs.player_faction:
		_petition_surrender(loser, winner, tribute, oid2)
	return {"ok": true, "offer_id": oid2, "tribute": tribute,
		"msg": "The %s offer surrender (%d gold reparations)." % [
			_fname(loser), tribute]}


## All live surrender offers (for the Royal Court / UI).
func pending_surrender_offers() -> Array:
	var out: Array = []
	for oid: String in _surrender_offers.keys():
		var o: Dictionary = (_surrender_offers[oid] as Dictionary).duplicate()
		o["offer_id"] = oid
		out.append(o)
	return out


## Resolves a surrender offer. Accept: tribute moves, war ends in peace
## (+45-day truce), the white flag flies. Refuse: grudge, war grinds on.
func resolve_surrender(offer_id: String, accept: bool) -> Dictionary:
	var o: Dictionary = _surrender_offers.get(offer_id, {})
	if o.is_empty():
		return {"ok": false, "msg": "No such surrender offer."}
	var loser: String = String(o.get("loser", ""))
	var winner: String = String(o.get("winner", ""))
	var tribute: int = int(o.get("tribute", 0))
	_surrender_offers.erase(offer_id)
	# HTML surrenderResolve62: the offer is marked done either way — no
	# re-offers for this war.
	_surrender_done[_surrender_done_key(loser, winner)] = _gs.day_number
	if accept:
		pay_tribute(loser, winner, "gold", float(tribute))
		_record(loser, winner, "surrender_accepted", winner)
		_add_morale(loser, 8.0)   # relief: the dying stops
		_add_morale(winner, 10.0)  # victory + gold
		_gs.bus.surrender_accepted.emit(loser, winner)
		_report("SURRENDER ACCEPTED: the %s yield" % _fname(loser),
			"The %s laid down their arms on day %d — %d gold in \
reparations, and the war with the %s ENDS." % [_fname(loser),
			_gs.day_number, tribute, _fname(winner)], "war")
		# make_peace sets the 45-day truce.
		return make_peace(loser, winner)
	_record(winner, loser, "surrender_refused", winner)
	adjust_score(winner, loser, -10.0)
	_report("SURRENDER REFUSED: the %s fight on" % _fname(loser),
		"The %s refused the %s surrender on day %d. \
The war grinds on." % [_fname(winner), _fname(loser), _gs.day_number],
		"war")
	return {"ok": true, "msg": "Surrender refused — the war grinds on."}


## The player's crown offers peace to an AI faction at war (HTML offerPeace62
## verbatim, triggered there by a ruler DM with intent 'peace_offer'): the AI
## accepts when not hateful (relation score > -20), when outmatched
## (strength under 75% of the player's), or on a whim (25%). A spurned offer
## costs 4 relation points and is recorded in the chronicle.
## Returns {ok, accepted, msg}.
func offer_peace(target: String) -> Dictionary:
	var me: String = _gs.player_faction
	if target == me:
		return {"ok": false, "accepted": false,
			"msg": "You cannot offer peace to yourself."}
	if relation_state(target, me) != "war":
		return {"ok": false, "accepted": false,
			"msg": "You are not at war with the %s." % _fname(target)}
	var sc: float = relation_score(target, me)
	var own_f: float = military_strength(target)
	var own_m: float = military_strength(me)
	var accept: bool = sc > -20.0 or own_f < own_m * 0.75 or randf() < 0.25
	if accept:
		_record(target, me, "offered_peace", me)
		var res: Dictionary = make_peace(target, me)
		_report("The %s accept your peace offer" % _fname(target),
			"The banners of war come down on day %d — the %s accept the \
crown's peace offer." % [_gs.day_number, _fname(target)], "war")
		res["accepted"] = true
		return res
	adjust_score(target, me, -4.0)
	_record(target, me, "peace_spurned", target)
	_report("PEACE SPURNED",
		"The %s spit on the crown's peace offer on day %d. The war \
continues." % [_fname(target), _gs.day_number], "war")
	return {"ok": true, "accepted": false,
		"msg": "The %s spurned your peace offer." % _fname(target)}


## HTML war-tree parity (C62): suing for peace costs reparations, never
## free. rep = clamp(round(their gold * 0.1 + 200), 100, 1500), computed
## from the TARGET faction's treasury. The phone diplomacy board charges
## this before make_peace runs; the DM "peace offer" path (offer_peace)
## above stays the free probabilistic gamble.
func reparation_cost(target: String) -> int:
	var their_gold: float = _gs.resources.get_amount(target, "gold")
	return clampi(int(round(their_gold * 0.1 + 200.0)), 100, 1500)


## Daily surrender check (called from _daily): AI factions losing badly
## (strength under 45% of the enemy, war running 12+ days, morale low)
## sue for peace. Player-targeted offers arrive as court petitions.
func _surrender_tick() -> void:
	# First: pending AI-vs-AI offers get a daily resolution roll.
	for oid: String in _surrender_offers.keys():
		var o: Dictionary = _surrender_offers[oid]
		var ow: String = String(o.get("winner", ""))
		if ow == _gs.player_faction:
			continue  # the crown decides; don't auto-resolve
		if randf() < 0.4:
			resolve_surrender(oid, true)
		# else: the offer sits; the winner reconsiders tomorrow.
	for key: String in _pairs.keys():
		var rec: Dictionary = _pairs[key]
		if String(rec.get("state", "")) != "war":
			continue
		var a: String = String(rec["a"])
		var b: String = String(rec["b"])
		# No instant surrenders — the war must run 12+ days (HTML C62).
		if _gs.day_number - int(rec.get("war_since_day", 0)) < 12:
			continue
		for sides: Array in [[a, b], [b, a]]:
			var loser: String = sides[0]
			var winner: String = sides[1]
			if loser == _gs.player_faction:
				continue  # the player surrenders through the UI, not AI
			var str_l := military_strength(loser)
			var str_w := military_strength(winner)
			if str_l >= str_w * 0.45:
				continue  # not losing badly enough (HTML: score < -30)
			var traits := faction_traits(loser)
			if float(traits["proud"]) >= 0.85 and str_l >= str_w * 0.25:
				continue  # too proud to yield while still standing
			if morale_of(loser) >= 55.0:
				continue
			if winner == _gs.player_faction:
				offer_surrender(loser, winner)  # court petition for the crown
			elif randf() < 0.4:
				# AI-vs-AI: resolve immediately with tribute (HTML 40%).
				var res: Dictionary = offer_surrender(loser, winner)
				if bool(res.get("ok", false)):
					resolve_surrender(String(res["offer_id"]), true)
			else:
				offer_surrender(loser, winner)  # pending; resolved above


## Proposes an alliance; the TARGET's AI accepts or rejects. Returns
## {ok, accepted, msg}.
func propose_alliance(proposer: String, target: String) -> Dictionary:
	var rec: Dictionary = _pair(proposer, target)
	if rec.is_empty() or proposer == target:
		return {"ok": false, "accepted": false,
			"msg": "Unknown faction pair."}
	var st := String(rec.get("state", ""))
	if st == "allied":
		return {"ok": false, "accepted": false, "msg": "Already allied."}
	if st == "war":
		return {"ok": false, "accepted": false,
			"msg": "Make peace first — nobody allies mid-siege."}
	if ai_accepts_alliance(proposer, target):
		form_alliance(proposer, target)
		return {"ok": true, "accepted": true,
			"msg": "%s accepted the alliance!" % _fname(target)}
	adjust_score(proposer, target, -5.0)  # rejection stings
	_record(proposer, target, "alliance_refused", target)
	return {"ok": true, "accepted": false,
		"msg": "%s refused the alliance." % _fname(target)}


## Would the target AI accept an alliance from the proposer?
func ai_accepts_alliance(proposer: String, target: String) -> bool:
	if grudge_against(target, proposer) <= GRUDGE_BLOCK:
		return false  # grudges prevent alliances
	var need: float = 25.0 - float(faction_traits(target)["friendly"]) * 15.0
	if relation_score(proposer, target) < need:
		return false
	if reputation_of(proposer) < 35.0:
		return false  # untrustworthy
	if military_strength(target) > military_strength(proposer) * 3.0 \
			and float(faction_traits(target)["proud"]) > 0.6:
		return false  # proud powers don't ally with weaklings
	return true


## Applies an alliance directly (no AI roll) — used when the player
## accepts an envoy's offer through the Royal Court.
func form_alliance(a: String, b: String) -> Dictionary:
	var rec: Dictionary = _pair(a, b)
	if rec.is_empty():
		return {"ok": false, "msg": "Unknown faction pair."}
	rec["state"] = "allied"
	relation_version += 1  # R23: hostile-set cache invalidation
	rec["score"] = 75.0
	rec["allied_since_day"] = _gs.day_number
	_record(a, b, "alliance_signed", a)
	_add_morale(a, 4.0)
	_add_morale(b, 4.0)
	_gs.bus.alliance_signed.emit(a, b)
	_gs.bus.relation_changed.emit(a, b, "allied")
	_report("%s and %s sign a grand alliance" % [_fname(a), _fname(b)],
		"Envoys wept, banners were sewn, and on day %d the %s and the %s \
swore to stand as one. Shared maps, shared markets, shared spears." % [
		_gs.day_number, _fname(a), _fname(b)], "court")
	# Allies trade: physical route + wagons (HTML ally -> ensureTradeRoute).
	if _gs.get("trade_routes") != null:
		_gs.trade_routes.ensure_route(a, b)
	var pf3: String = _gs.player_faction
	if a == pf3:
		ruler_react_to("ally", {"faction": b})
	elif b == pf3:
		ruler_react_to("ally", {"faction": a})
	return {"ok": true, "msg": "%s and %s are now allied." % [_fname(a),
		_fname(b)]}


## Signs a trade agreement; the TARGET's AI accepts or rejects.
func sign_trade_agreement(proposer: String, target: String, days: int = 3,
		force: bool = false) -> Dictionary:
	var rec: Dictionary = _pair(proposer, target)
	if rec.is_empty() or proposer == target:
		return {"ok": false, "accepted": false,
			"msg": "Unknown faction pair."}
	if String(rec.get("state", "")) == "war":
		return {"ok": false, "accepted": false,
			"msg": "No trade with an enemy at war."}
	if bool(rec.get("trade_active", false)):
		return {"ok": false, "accepted": false,
			"msg": "A trade deal is already active."}
	if not force and not ai_accepts_trade(proposer, target):
		adjust_score(proposer, target, -5.0)
		return {"ok": true, "accepted": false,
			"msg": "%s refused the trade deal." % _fname(target)}
	activate_trade(proposer, target, days)
	var pf4: String = _gs.player_faction
	if proposer == pf4:
		ruler_react_to("trade", {"faction": target})
	elif target == pf4:
		ruler_react_to("trade", {"faction": proposer})
	return {"ok": true, "accepted": true,
		"msg": "Trade deal signed with %s!" % _fname(target)}


## Would the target AI accept a trade deal?
## Principled factions (elves) demand honorable partners: betrayers must
## have rebuilt their reputation first.
func ai_accepts_trade(proposer: String, target: String) -> bool:
	if grudge_against(target, proposer) <= -1.5:
		return false
	if relation_score(proposer, target) < -10.0:
		return false
	if reputation_of(proposer) < 30.0:
		return false
	if SimFactions.soul_trade_stance(target) == "principled" \
			and reputation_of(proposer) < 50.0:
		return false  # honor matters: reparations first
	return true


## Applies a trade deal directly (no AI roll).
func activate_trade(a: String, b: String, days: int = 3) -> Dictionary:
	var rec: Dictionary = _pair(a, b)
	if rec.is_empty():
		return {"ok": false, "msg": "Unknown faction pair."}
	rec["trade_active"] = true
	rec["trade_until_day"] = _gs.day_number + maxi(1, days)
	_record(a, b, "trade_signed", a)
	_gs.bus.trade_signed.emit(a, b)
	_report("Trade wagons roll between %s and %s" % [_fname(a), _fname(b)],
		"Merchants signed the ledgers on day %d: %s goods for %s goods, \
at a friendlier rate for both." % [_gs.day_number, _fname(a), _fname(b)],
		"trade")
	_trade_exchange(a, b)  # first caravan leaves immediately
	# Physical trade layer (HTML activate_trade -> ensureTradeRoute):
	# dirt trade road + outposts + covered wagons between the halls.
	if _gs.get("trade_routes") != null:
		_gs.trade_routes.ensure_route(a, b)
	return {"ok": true, "msg": "Trade deal active."}


## Demands tribute; the TARGET's AI accepts if scared, refuses if proud.
## Returns {ok, accepted, paid, msg}.
func demand_tribute(demander: String, target: String, resource: String,
		amount: float) -> Dictionary:
	var rec: Dictionary = _pair(demander, target)
	if rec.is_empty() or demander == target:
		return {"ok": false, "accepted": false, "paid": 0.0,
			"msg": "Unknown faction pair."}
	if not resource in Config.RESOURCES:
		return {"ok": false, "accepted": false, "paid": 0.0,
			"msg": "Unknown resource."}
	var st := String(rec.get("state", ""))
	if st == "allied":
		return {"ok": false, "accepted": false, "paid": 0.0,
			"msg": "Allies don't pay tribute — that's what the alliance is for."}
	if st == "war":
		return {"ok": false, "accepted": false, "paid": 0.0,
			"msg": "They laugh in your envoy's face. You are at war."}
	_record(demander, target, "tribute_demanded", demander)
	if ai_accepts_tribute(demander, target, resource, amount):
		var paid: float = pay_tribute(target, demander, resource, amount)
		adjust_score(demander, target, 5.0)  # appeasement eases tension
		return {"ok": true, "accepted": true, "paid": paid,
			"msg": "%s paid %d %s in tribute." % [_fname(target),
				int(paid), resource]}
	_record(demander, target, "tribute_refused", target)
	adjust_score(demander, target, -15.0)
	_gs.bus.tribute_refused.emit(demander, target)
	return {"ok": true, "accepted": false, "paid": 0.0,
		"msg": "%s refused the tribute demand!" % _fname(target)}


## Would the target AI pay tribute? Scared factions pay; proud ones refuse.
func ai_accepts_tribute(demander: String, target: String, resource: String,
		amount: float) -> bool:
	var traits := faction_traits(target)
	var proud: float = float(traits["proud"])
	var str_d := military_strength(demander)
	var str_t := military_strength(target)
	var scared: bool = str_t < str_d * 0.7
	var stock: float = _gs.resources.get_amount(target, resource)
	if stock < amount * 0.25:
		return false  # can't pay a quarter of it — refuse, not ruin
	var ratio: float = amount / maxf(1.0, stock)
	if scared and proud < 0.75 and ratio <= 0.6:
		return true
	if ratio <= 0.15 and relation_score(demander, target) > -20.0:
		return true  # a cheap price for peace
	if proud >= 0.7 and not scared:
		return false
	return scared and ratio <= 0.4


## Moves tribute resources, no questions asked. Returns what was paid.
func pay_tribute(from_faction: String, to_faction: String, resource: String,
		amount: float) -> float:
	if not resource in Config.RESOURCES or from_faction == to_faction:
		return 0.0
	var paid: float = minf(maxf(0.0, amount),
		_gs.resources.get_amount(from_faction, resource))
	if paid <= 0.0:
		return 0.0
	_gs.resources.add_resource(from_faction, resource, -paid)
	_gs.resources.add_resource(to_faction, resource, paid)
	_record(to_faction, from_faction, "tribute_paid", from_faction)
	_add_morale(from_faction, -3.0)
	_add_morale(to_faction, 3.0)
	_gs.bus.tribute_paid.emit(from_faction, to_faction, resource, paid)
	_report("%s pays tribute to %s" % [_fname(from_faction),
		_fname(to_faction)],
		"On day %d, %d %s changed hands from %s to %s — \
the price of peace, paid in full." % [_gs.day_number, int(paid), resource,
		_fname(from_faction), _fname(to_faction)], "trade")
	return paid


## A ruler threatens another faction outright (the outward path behind the
## Ruler's Voice "threaten the X" order). The event is recorded, the
## relation score takes a real hit, and the target's AI reacts through the
## normal daily tick — proud or brave factions may answer with steel
## (their threat arrives back as a royal-court petition, the diplomacy
## petition path). Not a war declaration: no surprise wars from threats.
func threaten(demander: String, target: String) -> Dictionary:
	var rec: Dictionary = _pair(demander, target)
	if rec.is_empty() or demander == target:
		return {"ok": false, "msg": "Unknown faction pair."}
	var st := String(rec.get("state", ""))
	if st == "war":
		return {"ok": false,
			"msg": "You are already at war — save your breath for the battlefield."}
	_record(demander, target, "threatened", demander)
	adjust_score(demander, target, -15.0)  # refused-tribute scale
	_add_reputation(demander, -2.0)  # bullies are remembered
	return {"ok": true, "msg": "%s threatens %s — the %s court will answer in kind." % [
		_fname(demander), _fname(target), _fname(target)]}


## Ends the physical trade layer when the diplomatic trade relationship
## ends any way OTHER than war (break_treaty, deal expiry, insult-strained
## alliance). declare_war dissolves through its own call; every other exit
## funnels through here so wagons never keep running for a dead deal.
## Alliances opened physical routes too, so breaking one dissolves as well.
func _end_physical_trade(a: String, b: String) -> void:
	if _gs.get("trade_routes") != null:
		_gs.trade_routes.dissolve_routes(a, b)


## Breaks an alliance or trade deal. Reputation hit + grudge + score crash.
func break_treaty(breaker: String, other: String) -> Dictionary:
	var rec: Dictionary = _pair(breaker, other)
	if rec.is_empty() or breaker == other:
		return {"ok": false, "msg": "Unknown faction pair."}
	var st := String(rec.get("state", ""))
	var had_alliance: bool = st == "allied"
	var had_trade: bool = bool(rec.get("trade_active", false))
	if not had_alliance and not had_trade:
		return {"ok": false, "msg": "There is no treaty to break."}
	if had_alliance:
		rec["state"] = "neutral"
		relation_version += 1  # R23: hostile-set cache invalidation
		rec["score"] = -30.0
	if had_trade:
		rec["trade_active"] = false
		rec["score"] = minf(float(rec.get("score", 0.0)), -15.0)
	# The diplomatic relationship is over — the wagons stop too.
	_end_physical_trade(breaker, other)
	_record(breaker, other, "treaty_broken", breaker)
	_add_reputation(breaker, -15.0)
	_add_morale(breaker, -2.0)
	_add_morale(other, -4.0)
	_gs.bus.treaty_broken.emit(breaker, other)
	_gs.bus.relation_changed.emit(breaker, other,
		String(rec.get("state", "neutral")))
	var what := "their alliance" if had_alliance else "their trade deal"
	_report("%s breaks %s with %s!" % [_fname(breaker), what, _fname(other)],
		"Oathbreakers! On day %d, %s tore up %s with %s. Every other \
court in the land took note of the betrayal." % [_gs.day_number,
		_fname(breaker), what, _fname(other)], "court")
	return {"ok": true, "msg": "Treaty broken. Your reputation suffers."}


## Insults another faction's court (HTML buildDiplomacyTree insult parity,
## extended 2026-10-04: faction temperament instead of a flat war chance).
## If allied: the insult strains the alliance to neutral and dissolves trade.
## Otherwise the insult damages the relationship score and your reputation
## takes a small hit for being a boor — and repeated insults can provoke war,
## with faction-specific tempers: ogres/undead are short-tempered (war
## possible from the 3rd insult), humans are fearful (war possible from the
## 5th), elves take a lot (war possible from the 7th), and gnomes never
## declare war over an insult — they just roast you back.
## Jeremy 2026-10-04: "Can I still trigger a war insulting the enemy
## factions?" — yes, now you can.
const INSULT_LINES := {
	"humans": "Mind your tongue before a crowned hall.",
	"ogres": "You smell like scared goat.",
	"gnomes": "I've seen brighter ideas in a mushroom stew.",
	"elves": "Even thorns speak with more grace.",
	"undead": "Even the grave finds you tedious.",
}

## Jeremy 2026-10-04: guaranteed minimum provocation. Every faction needs
## "more than a couple of insults" before any war roll is even possible —
## ogres/undead are merely the shortest-tempered, elves take many, humans
## avoid war out of fear. (Gnomes are not listed: their war chance is
## always 0.0 — insults never start a war with them.)
const INSULT_WAR_MIN := {
	"ogres": 3,
	"undead": 3,
	"elves": 7,
	"humans": 5,
}

## Jeremy 2026-10-04: the n-word (hard r) is an instant war crime. ANY
## faction — including gnomes, who never go to war over normal insults —
## declares war IMMEDIATELY and freaks out. No thresholds, no rolls, NO
## EXCEPTIONS — not even the "enemy of my enemy" rule applies. The real
## slur is too far for everyone.
## Matched case-insensitively with word boundaries (no substring hits).
const SLUR_PATTERN := "(?i)\\bnigg(?:er|a)s?\\b"

## Jeremy 2026-10-04: FANTASY racial slurs against game factions. These are
## made-up in-world slurs (like "knife-ears" for elves). Unlike the real
## n-word, these follow relationship logic: if the reacting faction HATES
## or is AT WAR with the slurred faction, they pile on with their own
## insults (enemy of my enemy). Otherwise they freak out and declare war.
## Maps slurred faction -> array of slur words for them.
const FANTASY_SLURS := {
	"elves": ["knife-ear", "knife-ears", "leaf-licker", "leaf-lickers",
		"tree-hugger", "tree-huggers", "tree-humper", "tree-humpers",
		"twig", "twigs", "bark-face", "bark-faces", "sap-sucker",
		"sap-suckers", "fairy", "fairies", "leaf", "leaves"],
	"ogres": ["dung-brain", "dung-brains", "club-head", "club-heads",
		"maggot-brain", "maggot-brains", "rock-skull", "rock-skulls",
		"pig-face", "pig-faces", "mud-brain", "mud-brains",
		"grunt", "grunts", "lunk", "lunks"],
	"gnomes": ["beard-rat", "beard-rats", "mushroom", "mushrooms",
		"garden pest", "garden pests", "lawn ornament", "lawn ornaments",
		"weed", "weeds", "pebble", "pebbles", "button", "buttons",
		"ankle-biter", "ankle-biters"],
	"humans": ["pinkskin", "pinkskins", "pink-skin", "pink-skins",
		"soft-hide", "soft-hides", "mud-grubber", "mud-grubbers",
		"mayfly", "mayflies", "ape", "apes", "cattle", "short-lived",
		"short-lives", "milksop", "milksops"],
	"undead": ["rot-bag", "rot-bags", "corpse", "corpses",
		"bone-rattler", "bone-rattlers", "grave-crawler", "grave-crawlers",
		"stiff", "stiffs", "worm-food", "maggot-farm", "maggot-farms",
		"rotter", "rotters", "carcass", "carcasses"],
}

## Faction-specific freak-out reactions to a FANTASY slur, used when the
## reacting faction does NOT hate the slurred faction. {race} is replaced
## with the slurred faction's display name.
const FANTASY_SLUR_REACTIONS := {
	"ogres": "The ogre warlord goes dangerously still. \"Even WE don't speak "
		+ "that filth about the {race}. You disgust me. WAR!\"",
	"undead": "The lich regards you with ancient contempt. \"Bigotry is the "
		+ "refuge of small minds. The dead declare WAR on yours.\"",
	"elves": "The elven queen's voice cuts like ice. \"We do not suffer "
		+ "racists in our halls — not even against the {race}. WAR, and may "
		+ "history forget you.\"",
	"humans": "The human court erupts in outrage. \"We may war with the "
		+ "{race}, but we don't speak like animals! WAR!\"",
	"gnomes": "The gnomes fall silent — even they know this crosses a line. "
		+ "\"That's not funny. That's not EVER funny. Not about the {race}, "
		+ "not about anyone. WAR.\"",
}

## Jeremy 2026-10-04: 100 insults per faction, used when a court PILES ON
## with your fantasy slur (they hate the slurred faction too). {enemy} is
## replaced with the slurred faction's display name at runtime. Picked at
## random so it doesn't repeat. Crude, funny, in-character — this is
## Cursing Gnomes.
const HATE_INSULTS := {
	"ogres": [
		"The {enemy} couldn't fight their way out of a wet sack!",
		"I'll crack {enemy} skulls and drink the soup inside!",
		"{enemy} brains are smaller than my smallest fist!",
		"Ha! The {enemy} run like scared rabbits!",
		"I once sneezed harder than the {enemy} fight!",
		"The {enemy} smell like old cheese left in the sun!",
		"My club is smarter than any {enemy}!",
		"{enemy} mothers hide when I walk by! Smart mothers!",
		"I ate a {enemy} once. Tasted like disappointment!",
		"The {enemy} couldn't hit the ground if they fell on it!",
		"{enemy} armor is just shiny cowardice!",
		"I've seen braver mold than the {enemy}!",
		"The {enemy} scream like babies when I roar!",
		"Step on the {enemy}! They're basically bugs!",
		"{enemy} warriors? More like {enemy} worriers!",
		"I use {enemy} banners as toilet paper!",
		"The {enemy} couldn't win a fight against sleep!",
		"Bah! {enemy} blood smells like soup! Weak soup!",
		"I'll turn {enemy} bones into toothpicks!",
		"The {enemy} are so slow, grass outruns them!",
		"{enemy} kings wear crowns to hide the empty inside!",
		"I wrestled a {enemy} champion once. Naptime!",
		"The {enemy} couldn't scare a kitten!",
		"{enemy} swords are just expensive butter knives!",
		"I drink {enemy} tears for breakfast! Salty!",
		"The {enemy} march like they got rocks in their boots!",
		"Ha! {enemy} shields dent when I LOOK at them!",
		"I'll flatten the {enemy} like pancakes!",
		"The {enemy} couldn't find their own backsides!",
		"{enemy} battle cries sound like sneezes!",
		"I've stepped in smarter things than {enemy} generals!",
		"The {enemy} hide behind walls. Walls I EAT!",
		"{enemy} horses laugh at their own riders!",
		"I'll wear a {enemy} as a hat!",
		"The {enemy} couldn't punch through wet paper!",
		"Bah! The {enemy} are just loud farmers!",
		"{enemy} castles are just expensive graves!",
		"I sneezed a {enemy} army off a bridge once!",
		"The {enemy} couldn't win an argument with a rock!",
		"{enemy} spears tickle! TICKLE!",
		"I'll juggle {enemy} heads at the victory feast!",
		"The {enemy} are so ugly, mirrors break first!",
		"{enemy} drums sound like my stomach growling!",
		"I once outran a {enemy} cavalry. Walking. Backwards!",
		"The {enemy} couldn't catch a cold in winter!",
		"{enemy} arrows bounce off! Bounce right off!",
		"I'll make the {enemy} my footstools!",
		"The {enemy} fight like they're underwater!",
		"Ha! {enemy} war paint is just fear with color!",
		"I ate three {enemy} scouts for lunch! Still hungry!",
		"The {enemy} couldn't guard a sandwich!",
		"{enemy} helmets are just shiny fear-buckets!",
		"I'll toss {enemy} soldiers like pebbles!",
		"The {enemy} scream my name in their sleep!",
		"Bah! {enemy} courage comes in tiny cups!",
		"I'll use the {enemy} as doorstops!",
		"The {enemy} couldn't break an egg with a hammer!",
		"{enemy} war horns sound like dying goats!",
		"I arm-wrestled a {enemy} warlord. He cried!",
		"The {enemy} are just tall targets!",
		"Ha! {enemy} tactics! I have seen better plans from soup!",
		"I'll stomp the {enemy} flat like rugs!",
		"The {enemy} couldn't intimidate a mushroom!",
		"{enemy} champions fall over in strong wind!",
		"My grandmother hits harder than {enemy} soldiers!",
		"The {enemy} polish their armor to blind themselves!",
		"I'll braid {enemy} beards into rope! Strong rope!",
		"The {enemy} couldn't siege a garden shed!",
		"Bah! {enemy} magic fizzles like wet fireworks!",
		"{enemy} scouts get lost in their own camp!",
		"I'll roast the {enemy} like marshmallows!",
		"The {enemy} couldn't hold a door shut!",
		"Ha! The {enemy} pay ME tribute in fear!",
		"{enemy} boots are full of cowardice!",
		"I'll use {enemy} spines as back-scratchers!",
		"The {enemy} couldn't win a staring contest with a fish!",
		"{enemy} war dogs bite their own masters! Smart dogs!",
		"I bench-press {enemy} siege weapons!",
		"The {enemy} couldn't loot an empty room!",
		"Bah! {enemy} kings sit on thrones of excuses!",
		"I'll punt a {enemy} over the mountains!",
		"The {enemy} couldn't ambush a statue!",
		"{enemy} courage melts like snow in soup!",
		"I've seen scarier turnips than {enemy} knights!",
		"The {enemy} couldn't defend a pillow fort!",
		"Ha! {enemy} battle plans! My dog eats better plans!",
		"I'll wear {enemy} armor as a bib!",
		"The {enemy} run so fast from me, they should race horses!",
		"{enemy} mothers tell THEM bedtime stories about ME!",
		"I'll stack {enemy} bodies like firewood!",
		"The {enemy} couldn't conquer a nap!",
		"Bah! The {enemy} are just noisy sheep!",
		"I'll crush the {enemy} like grapes! Sour grapes!",
		"The {enemy} couldn't find water in a river!",
		"{enemy} war cries make babies laugh!",
		"I use {enemy} shields as dinner plates!",
		"The {enemy} couldn't beat me at breathing!",
		"I'll squeeze {enemy} heads like grapes! Pop!",
		"The {enemy} couldn't win a tickle fight!",
		"Bah! {enemy} courage is just loud hiccups!",
	],
	"elves": [
		"How quaint — the {enemy} attempting warfare.",
		"We've seen moss with better strategy than the {enemy}.",
		"The {enemy} are proof that evolution takes breaks.",
		"Oh, the {enemy} have arrived. Do try to keep up, darlings.",
		"I've read better battle plans in children's picture books than {enemy} tactics.",
		"The {enemy} couldn't outthink a decorative shrub.",
		"Such noise, the {enemy} make. Like geese. Angry, stupid geese.",
		"We elven children learn more grace tripping than {enemy} soldiers marching.",
		"The {enemy} are a cautionary tale with swords.",
		"Do the {enemy} polish their failures as diligently as their armor?",
		"I've seen more elegance in a collapsing tent than in {enemy} formations.",
		"The {enemy} mistake volume for valor. Adorable.",
		"Their war drums, the {enemy}'s — we use the rhythm to nap.",
		"One elven archer is worth a hundred {enemy}. We did the math. Twice.",
		"The {enemy} couldn't find subtlety with a map and a guide.",
		"Their banners, the {enemy}'s, make excellent kindling.",
		"I taught a parrot {enemy} military doctrine. The parrot wept.",
		"The {enemy} charge like they think running IS the plan.",
		"Such brave {enemy}! Such pity they're brave about nothing!",
		"We've buried {enemy} armies and grown lovely gardens over them.",
		"The {enemy} couldn't hit a barn if the barn insulted their mothers.",
		"Their armor shines, the {enemy}'s. Shame about what's inside it.",
		"I've heard more coherent arguments from drunk squirrels than {enemy} generals.",
		"The {enemy} are the punchline the gods keep telling.",
		"Oh look, the {enemy} brought siege weapons. How... optimistic.",
		"Their courage, the {enemy}'s, evaporates like morning dew.",
		"We use {enemy} battle cries as lullabies for restless infants.",
		"The {enemy} couldn't ambush a sleeping tortoise.",
		"Their swords, bless them, the {enemy}'s — so shiny, so pointless.",
		"I've seen better discipline in a tavern brawl than {enemy} ranks.",
		"The {enemy} think 'flanking' is a type of pastry.",
		"Such fury! Such passion! Such utterly wasted effort, dear {enemy}.",
		"We've outlived {enemy} empires the way you outlive mayflies.",
		"The {enemy} couldn't guard a secret, let alone a border.",
		"Their war paint is the only colorful thing about {enemy} strategy.",
		"I once watched {enemy} scouts get lost in a straight hallway.",
		"The {enemy} negotiate like they fight: badly, and loudly.",
		"Oh, the {enemy} are angry. Should we fetch their fainting couches?",
		"We've seen deeper thought in puddles than in {enemy} war councils.",
		"The {enemy} couldn't win a debate against an echo.",
		"Their cavalry, the {enemy}'s — the horses deserve better riders.",
		"I've composed ballads about {enemy} defeats. They're all comedies.",
		"The {enemy} mistake stubbornness for strength. Common error.",
		"Such splendid armor the {enemy} wear to their funerals.",
		"We taught the {enemy} the meaning of 'retreat.' They learned fast.",
		"The {enemy} couldn't siege a gingerbread house.",
		"Their battle standards droop like the {enemy}'s spirits.",
		"I've seen more tactical brilliance in a game of dice than {enemy} campaigns.",
		"The {enemy} are why the gods invented the word 'overmatched.'",
		"Oh darling {enemy}, war is not for everyone. It's certainly not for you.",
		"Their spears, the {enemy}'s — we use them as toothpicks.",
		"We've watched {enemy} armies dissolve like sugar in rain.",
		"The {enemy} couldn't frighten a poet.",
		"Their fortresses fall like the {enemy}'s arguments: quickly.",
		"I've seen better aim from blindfolded toddlers than {enemy} archers.",
		"The {enemy} are a masterclass in how not to wage war.",
		"Such confidence! The {enemy} have the confidence of the clueless.",
		"We keep {enemy} prisoners for comedy. They're excellent at it.",
		"The {enemy} couldn't hold a grudge, let alone a wall.",
		"Their war horns sound like the {enemy}'s last coherent thought.",
		"I've outwitted {enemy} spies by simply standing still.",
		"The {enemy} are the reason 'strategy' needed a definition.",
		"Oh, the {enemy} brought friends. How many will we bury today?",
		"We've seen braver performances from actors playing cowards.",
		"The {enemy} couldn't conquer a sandcastle at low tide.",
		"Their generals, the {enemy}'s, strategize like they're ordering lunch.",
		"I've heard more inspiring speeches from tax collectors than {enemy} kings.",
		"The {enemy} are proof the gods have a sense of humor.",
		"Such lovely {enemy} uniforms! Pity about the soldiers inside.",
		"We use captured {enemy} maps as wrapping paper. They're decorative.",
		"The {enemy} couldn't win a war of words against a mime.",
		"Their shields, the {enemy}'s, make fine serving trays.",
		"I've seen more spine in jellyfish than in {enemy} infantry.",
		"The {enemy} charge bravely into our arrows. Every time. Bless.",
		"Oh, the {enemy} want peace now? How... convenient for them.",
		"We've turned {enemy} sieges into picnics. Lovely spreads.",
		"The {enemy} couldn't defend their own shadows.",
		"Their battle cries fade, the {enemy}'s, like their relevance.",
		"I've seen wiser decisions from coin flips than {enemy} councils.",
		"The {enemy} are a footnote we're already forgetting.",
		"Such drama! The {enemy} mistake theater for warfare.",
		"We've buried so many {enemy}, we're considering a memorial garden.",
		"The {enemy} couldn't outmaneuver a sundial.",
		"Their courage is seasonal, the {enemy}'s, and it's always winter.",
		"I've seen more grace in falling masonry than {enemy} cavalry.",
		"The {enemy} are why we invented the longbow. Target practice.",
		"Oh look — the {enemy} learned a new formation. Still wrong, but new.",
		"We've seen {enemy} 'victories' that were actually retreats. Charming.",
		"The {enemy} couldn't hold a tune, let alone a position.",
		"Their war dogs, the {enemy}'s, have defected to us. Wise dogs.",
		"I've seen better leadership in a beehive than {enemy} command.",
		"The {enemy} are simply... not good at this. At any of this.",
		"We've seen {enemy} 'bravery' — it lasts until the first arrow.",
		"The {enemy} couldn't organize a coherent thought, let alone an army.",
		"Their demise, the {enemy}'s, will be terribly well-documented.",
		"We've already written the {enemy}'s elegy. It's brief.",
		"The {enemy} are a riddle with an obvious answer: defeat.",
		"Oh, the {enemy} persist. Like a stain.",
		"Their legacy, the {enemy}'s, will be a warning to others.",
		"We've seen the {enemy}'s best. We've filed it under 'amusing.'",
	],
	"gnomes": [
		"We put itching powder in {enemy} armor once! Best week ever!",
		"The {enemy} couldn't find their own noses with both hands and a map!",
		"We replaced {enemy} gunpowder with flour! The bang was more of a poof!",
		"Ha! {enemy} soldiers march in circles! We painted arrows to help! They still got lost!",
		"The {enemy} are so serious! We love that! Makes the pranks better!",
		"We greased the {enemy} castle stairs! Wheee! Down they went!",
		"{enemy} generals couldn't plan a picnic, let alone a war!",
		"We sold the {enemy} 'invisible armor'! It was just... nothing! They paid full price!",
		"The {enemy} scream so funny when we hide their weapons!",
		"We painted {enemy} horses pink in the night! Fabulous!",
		"{enemy} scouts walked right past our burrow! Three times! We waved!",
		"We switched {enemy} war banners with laundry! Very clean surrender flags!",
		"The {enemy} couldn't catch us if we stood still and napped!",
		"We filled {enemy} helmets with pudding! Chocolate! They were confused AND delighted!",
		"{enemy} battle plans? We use them as napkins! Very absorbent!",
		"We taught a {enemy} parrot to say 'retreat'! It outranks their general now!",
		"The {enemy} are so tall! Great for hanging laundry on!",
		"We replaced {enemy} arrows with carrots! Healthier! Still pointy-ish!",
		"Ha! {enemy} knights sink in mud! We watched! We brought snacks!",
		"We snuck into {enemy} camp and braided everyone's hair together! Teamwork!",
		"The {enemy} couldn't win hide-and-seek against a lamppost!",
		"We sold the {enemy} a 'dragon'! It was a lizard with wings glued on! They screamed!",
		"{enemy} war horns? We stuffed them with bees! Musical AND spicy!",
		"We painted a tunnel on {enemy} fortress wall! They guarded it for a week!",
		"The {enemy} are so gullible, we told them the sky was falling! They looked up!",
		"We switched {enemy} boots left-for-right! The marching was ART!",
		"Ha! {enemy} cavalry! We put whoopee cushions on every saddle!",
		"We told the {enemy} their king was a cake! They tried to frost him!",
		"The {enemy} couldn't outsmart a sack of potatoes! We tested! The potatoes won!",
		"We hid all {enemy} swords and replaced them with baguettes! Crusty warfare!",
		"{enemy} soldiers slip on our banana peels! Classic! Never gets old!",
		"We convinced {enemy} scouts that we were mushrooms! They took notes!",
		"The {enemy} are so loud, we hear their 'sneak attacks' from three valleys away!",
		"We dyed the {enemy} river purple! They thought it was a curse! It was just dye!",
		"Ha! {enemy} armor is so shiny, we use it to signal each other!",
		"We put spring-loaded snakes in {enemy} supply crates! Hilarious AND educational!",
		"The {enemy} couldn't organize a one-gnome parade!",
		"We replaced {enemy} maps with treasure maps! They dug up our garden! Thanks!",
		"{enemy} generals draw plans in crayon! We know! We sold them the crayons!",
		"We told the {enemy} that standing still makes them invisible! They believed us!",
		"The {enemy} are so predictable, we set our clocks by their patrols!",
		"We filled {enemy} cannons with confetti! Surprise party! You're welcome!",
		"Ha! {enemy} spies! We feed them fake secrets! They report back SO proudly!",
		"We shrunk {enemy} uniforms in the wash! Oops! Not oops!",
		"The {enemy} couldn't find water if they fell out of a boat!",
		"We put a 'kick me' sign on the {enemy} warlord! In giant letters! He never noticed!",
		"{enemy} siege towers? We sold them as 'very tall birdhouses'!",
		"We taught {enemy} horses to dance! The cavalry is now a ballet!",
		"The {enemy} are so boring, our pranks are the most exciting part of their war!",
		"We replaced {enemy} rations with extremely spicy peppers! The latrines were busy!",
		"Ha! {enemy} lookouts! We wave at them every morning! They wave back now!",
		"We told the {enemy} that we surrender! Then we didn't! Classic!",
		"The {enemy} couldn't hit the broad side of a barn! We painted the barn bigger to help!",
		"We put glue on {enemy} thrones! Long live the stuck king!",
		"{enemy} war paint washes off in rain! We checked! Repeatedly!",
		"We convinced a {enemy} battalion that we were their reinforcements! We led them in circles!",
		"The {enemy} are so slow, we prank them, nap, and prank them again!",
		"We swapped {enemy} battle standards with our laundry! Their army now fears clean socks!",
		"Ha! {enemy} armor squeaks! We oiled it to squeak LOUDER!",
		"We told the {enemy} the forest was haunted! By us! Doing ghost noises! Boo!",
		"The {enemy} couldn't win an argument with our garden gnome statues! The statues won!",
		"We put mirrors in {enemy} camp! They fought their reflections for an hour!",
		"{enemy} soldiers are so heavy, they set off our mousetraps! The big ones!",
		"We sold the {enemy} 'magic beans'! They planted an army! Nothing grew! Shocking!",
		"The {enemy} are so serious about war! We threw a pie at their general! Bullseye!",
		"We hid {enemy} siege ladders! They tried to climb with hope and optimism!",
		"Ha! {enemy} drums! We replaced the drumsticks with fish! Funky beats!",
		"We told the {enemy} we were surrendering our gold! It was chocolate coins! They bit them!",
		"The {enemy} couldn't sneak past a sleeping cat! We tested with twelve cats!",
		"We painted {enemy} catapults to look like cakes! They tried to eat them! Twice!",
		"{enemy} knights are so shiny, birds nest on their helmets! We encourage the birds!",
		"We replaced {enemy} sword oil with honey! Sticky situation! Literally!",
		"The {enemy} are so tall, we use their shadows for shade! Thanks, {enemy}!",
		"We convinced {enemy} archers that the moon was a target! They've been trying for years!",
		"Ha! {enemy} war council! We listen through the walls! Great comedy show!",
		"We put bells on {enemy} boots! Jingle warfare! Very festive!",
		"The {enemy} couldn't plan a surprise party! We'd hear them wrapping!",
		"We sold the {enemy} a map to our 'secret base'! It led to a pie shop! They bought pie!",
		"{enemy} soldiers march so loud, we don't need alarm clocks!",
		"We dyed {enemy} horses blue! Now they're SAD cavalry! Emotionally AND chromatically!",
		"The {enemy} are so gullible, we told them gnomes can't be seen! They still can't see us!",
		"We replaced {enemy} shield polish with glitter! Fabulous army! Very sparkly defeat!",
		"Ha! {enemy} generals! We send them fake love letters from 'admirers'! They blush!",
		"We told the {enemy} that running away is a 'tactical advance'! They do it constantly now!",
		"The {enemy} couldn't find their own army with a census!",
		"We put whoopee cushions on {enemy} thrones! Royal toots! The court pretends not to hear!",
		"{enemy} battle cries echo! We echo back mockingly! They get confused!",
		"We convinced the {enemy} that hats are helmets! Their army now fears milliners!",
		"The {enemy} are so predictable, our pranks have pranks!",
		"We replaced {enemy} war funds with chocolate coins! The economy is delicious!",
		"We put whoopee cushions on {enemy} thrones! Royal toots! The court pretends not to hear!",
		"{enemy} battle cries echo! We echo back mockingly! They get confused!",
		"We convinced the {enemy} that hats are helmets! Their army now fears milliners!",
		"The {enemy} are so predictable, our pranks have pranks!",
		"We replaced {enemy} war funds with chocolate coins! The economy is delicious!",
		"Ha! The {enemy} tried to besiege our burrow! They couldn't find the door! It's right there!",
		"We told the {enemy} we were 'tiny and harmless'! They believed the tiny part!",
		"The {enemy} couldn't catch a cold! We tried to give them one! With sneezes!",
		"We replaced {enemy} torches with sparklers! Pretty! Useless! Perfect!",
		"The {enemy} are so big, we use them as landmarks! 'Turn left at the {enemy}!'",
	],
	"humans": [
		"Yeah? Well the {enemy}... they smell! And we're not scared! Mostly!",
		"The {enemy} couldn't beat us! We have... numbers! And feelings!",
		"We're not afraid of the {enemy}! Okay, a little! But mostly not!",
		"The {enemy} are going down! As soon as we figure out how!",
		"Our king says the {enemy} are cowards! And the king is never wrong! Right?",
		"The {enemy} couldn't scare us! Well, they could, but we won't admit it!",
		"We have pitchforks! The {enemy} have... whatever! Pitchforks are scary!",
		"The {enemy} are ugly! That's... that's our insult! Ugly!",
		"We'll fight the {enemy} to the last man! Hopefully it won't come to that!",
		"The {enemy} smell like feet! Big ugly feet!",
		"Our army is very brave! The {enemy} should be worried! Probably!",
		"The {enemy} couldn't win a fight! Against us! We think!",
		"We're going to get the {enemy}! Right after lunch! And a nap!",
		"The {enemy} are dumb! Dumb-dumb! That's what we said!",
		"Our walls are very tall! The {enemy} can't... they can't do anything about that!",
		"The {enemy} are cowards! Unlike us! We're... we're strategically cautious!",
		"We'll show the {enemy}! We'll show them... something! Soon!",
		"The {enemy} couldn't beat a sick goat! We could! Probably!",
		"Our knights are shiny! The {enemy} are... not shiny! Take that!",
		"The {enemy} are going to regret this! As soon as we think of how!",
		"We're not running from the {enemy}! We're... advancing backwards!",
		"The {enemy} have bad breath! We heard! From someone! Probably!",
		"Our king is very brave! He hides... he strategically positions himself far from the {enemy}!",
		"The {enemy} couldn't catch us! We're very fast! When running away!",
		"We'll defeat the {enemy} with our superior... um... humanity!",
		"The {enemy} are stupid! Stupid stupid! We said it twice so it's true!",
		"Our army trains every day! The {enemy} should be very afraid! We are!",
		"The {enemy} couldn't find their own army! We could! It's right there! Oh no!",
		"We're going to win! The {enemy} are going to lose! We believe this!",
		"The {enemy} are mean! Really mean! That's the worst thing we can think of!",
		"Our walls have never been breached! The {enemy} can't... please don't try!",
		"The {enemy} fight dirty! We fight... clean! Cleanly! With soap!",
		"We'll stand our ground against the {enemy}! Unless they come! Then we'll... stand elsewhere!",
		"The {enemy} are bullies! Big mean bullies! Someone should tell them!",
		"Our soldiers are well-fed! The {enemy} are... probably also well-fed! But we're MORE well-fed!",
		"The {enemy} couldn't win a shouting match! We're very loud! Especially when scared!",
		"We have God on our side! The {enemy} have... we don't know! But we have God!",
		"The {enemy} are going to pay! In... some currency! Eventually!",
		"Our king once killed a {enemy}! Well, he saw one die! Nearby! He was there!",
		"The {enemy} couldn't siege a tent! We live in houses! With doors! That lock!",
		"We're brave! The {enemy} are... also brave! But we're BRAVER! We think!",
		"The {enemy} smell! Did we say that? We're saying it again! They smell!",
		"Our army has banners! Big ones! The {enemy} have... smaller ones! Probably!",
		"The {enemy} couldn't beat us in a fair fight! So let's not have a fair fight!",
		"We'll defend our homes from the {enemy}! Our homes are very defendable! We hope!",
		"The {enemy} are dumb as rocks! Rocks are dumb! We've checked!",
		"Our knights have shining armor! The {enemy} have... armor! But less shiny!",
		"The {enemy} couldn't scare a child! Okay, they could! But not us! We're adults!",
		"We have a plan to beat the {enemy}! It's a secret! Even we don't know it!",
		"The {enemy} are ugly AND mean! That's two things! We're on a roll!",
		"Our walls are thick! The {enemy} can't... they can't do anything! Please!",
		"The {enemy} fight like animals! We fight like... civilized people! Who are scared!",
		"We'll show the {enemy} what we're made of! Hopefully not jam! We're scared of jam!",
		"The {enemy} couldn't win a game of chess! We don't play chess! But still!",
		"Our soldiers are loyal! The {enemy} are... also loyal! But to the WRONG side!",
		"The {enemy} are going down! We're going up! Morally! Probably!",
		"We're not afraid! The {enemy} should be afraid! Of us! Being not afraid!",
		"The {enemy} have cooties! We checked! With science!",
		"Our king is wise! He says the {enemy} are doomed! We believe him! We have to!",
		"The {enemy} couldn't beat an egg! We can beat eggs! We eat them!",
		"We'll fight to the bitter end! Hopefully the {enemy} give up before that!",
		"The {enemy} are smelly bullies! Smelly! Bullies! Two insults! We're good at this!",
		"Our army is huge! The {enemy} army is... also huge! But ours is huger! We think!",
		"The {enemy} couldn't find their way out of a paper bag! We could! We've practiced!",
		"We have faith! The {enemy} have... we don't know what they have! But we have faith!",
		"The {enemy} are doomed! We've decided! It's official!",
		"Our knights are chivalrous! The {enemy} are... not! That's our insult! Not chivalrous!",
		"The {enemy} couldn't win a popularity contest! We're very popular! With ourselves!",
		"We'll stand together against the {enemy}! Together! Not running! Standing!",
		"The {enemy} are meanies! Big meanie heads! That's what our children say! And we agree!",
		"Our defenses are impenetrable! The {enemy} can't... please don't test that!",
		"The {enemy} fight dirty! We fight... we also fight dirty! But we're honest about it!",
		"We're going to win this war! The {enemy} are going to lose! We've manifested it!",
		"The {enemy} are stupid AND ugly! That's the double! Nobody recovers from the double!",
		"Our soldiers are brave! The {enemy} are... brave too! But we're BRAVER! Louder!",
		"The {enemy} couldn't beat us at anything! Except maybe fighting! But nothing else!",
		"We have the high ground! The {enemy} have... the low ground! That's worse! We think!",
		"The {enemy} are bullies and we're telling! Someone! Anyone! Help!",
		"Our king is very tall! The {enemy} king is... shorter! Probably! We haven't measured!",
		"The {enemy} couldn't win a staring contest! We never blink! Okay, we blink! But angrily!",
		"We'll defend every inch! The {enemy} can't have a single inch! Inches are ours!",
		"The {enemy} are dumb-dumbs! We said it! It's out there! Can't take it back!",
		"Our army marches with pride! The {enemy} march... also with pride! But wrong pride!",
		"The {enemy} couldn't beat a drum! We can! We have drummers! Very loud ones!",
		"We're united against the {enemy}! United! In fear! But united!",
		"The {enemy} smell like old socks! We smell like... also old socks! But BETTER old socks!",
		"Our walls will hold! The {enemy} will break! Like waves! Against... walls!",
		"The {enemy} are cowards! We're... we're also scared! But we're scared TOGETHER!",
		"We'll win! The {enemy} will lose! This is our mantra! We say it daily!",
		"The {enemy} couldn't organize a parade! We can! We had one! It was nice!",
		"Our faith is strong! The {enemy}'s faith is... also strong! But ours is STRONGER! Probably!",
		"The {enemy} are going to regret messing with us! Any day now! Regret incoming!",
		"We're brave! We're strong! We're... we're going to hide now! But bravely!",
		"The {enemy} couldn't beat us! We've got heart! And anxiety! Mostly anxiety!",
		"Our blacksmiths make fine weapons! The {enemy} will... see them! From far away! Hopefully!",
		"The {enemy} are doomed! We hired a prophet! He said so! He also said it might rain!",
		"We'll fight the {enemy} with everything we have! Which is... let us get back to you!",
		"The {enemy} couldn't win a bake-off! Our pies are legendary! Our swords are... also pies?",
		"Our courage is like our walls: tall, thick, and currently shaking!",
		"The {enemy} couldn't beat us at rock-paper-scissors! We always pick rock! Solid strategy!",
	],
	"undead": [
		"The {enemy} are a footnote. We have buried better.",
		"Death has already defeated the {enemy}. We are merely the paperwork.",
		"The {enemy} cling to life. How... temporary of them.",
		"We have watched {enemy} empires rise and fall. Mostly fall.",
		"The {enemy} fear death. We ARE death. Do the math.",
		"Their hearts beat, the {enemy}'s. For now.",
		"We do not hate the {enemy}. Hate requires effort. They are beneath effort.",
		"The {enemy} will join us eventually. They always do.",
		"Living armies tire. Living soldiers bleed. The {enemy} do both.",
		"We have all the time in the world. The {enemy} have... less.",
		"The {enemy} build monuments to themselves. We build nothing. We endure.",
		"Their courage, the {enemy}'s, is a candle. We are the dark.",
		"We remember every {enemy} we have killed. It is a long list. We are bored of it.",
		"The {enemy} scream when they die. They all do. It never gets interesting.",
		"We do not sleep. We do not eat. We do not lose to the {enemy}.",
		"The {enemy} are already dead. They just haven't stopped moving yet.",
		"Their kings, the {enemy}'s, will beg. They always beg.",
		"We have seen the {enemy}'s future. It is a grave.",
		"The {enemy} fight for land. We fight because we can. Forever.",
		"Death is patient. The {enemy} are not. This is why they lose.",
		"We do not fear the {enemy}. Fear is for the living.",
		"The {enemy}'s blood will water our... actually, we don't need water. It will just spill.",
		"We have outlasted plagues, famines, and gods. The {enemy} are a Tuesday.",
		"Their souls, the {enemy}'s, will make fine servants.",
		"We do not gloat. Gloating is for the {enemy}.",
		"The {enemy} are loud. The grave is silent. Silence wins.",
		"We have killed the {enemy} before. We will kill them again. Routine.",
		"Their armor, the {enemy}'s, will rust. We will not.",
		"We do not need to hate the {enemy}. Indifference is colder.",
		"The {enemy} pray to their gods. Their gods do not answer. We do.",
		"We are the end of all {enemy} stories.",
		"Their children, the {enemy}'s, will tell tales of us. Frightened tales.",
		"We do not tire. The {enemy} tire. This is the whole war.",
		"The {enemy} are a brief interruption in our eternity.",
		"Their victories, the {enemy}'s, are just slower defeats.",
		"We have no hearts to break. The {enemy} have hearts. We will break them.",
		"The {enemy} will rot. Everything rots. We are just... ahead of schedule.",
		"We do not mourn the {enemy}. We do not mourn at all.",
		"Their magic, the {enemy}'s, fades. Our hunger does not.",
		"We have seen stars die. The {enemy} are less impressive.",
		"The {enemy} cling to their warmth. We will take it.",
		"We are legion. The {enemy} are... a number. A finite number.",
		"Their fear, the {enemy}'s, is delicious. We savor it slowly.",
		"We do not rush. The {enemy} cannot escape. Why rush?",
		"The {enemy} build walls. Walls fall. We remain.",
		"Their heroes, the {enemy}'s, die like everyone else. Faster, usually.",
		"We remember when the {enemy} were nothing. We will remember when they are nothing again.",
		"The {enemy} are candles in a hurricane. We are the hurricane.",
		"We do not need sleep. We will attack the {enemy} at 3 AM. Every night. Forever.",
		"Their morale, the {enemy}'s, breaks like dry twigs.",
		"We have buried {enemy} kings in unmarked graves. We forgot where. It doesn't matter.",
		"The {enemy} are temporary. We are permanent.",
		"We do not feel pity for the {enemy}. Pity is a living emotion.",
		"Their armies, the {enemy}'s, are just future recruits.",
		"We will turn the {enemy}'s dead against them. Efficient.",
		"The {enemy} fear the dark. We ARE the dark.",
		"We have no need for the {enemy}'s land. We take it anyway.",
		"Their screams, the {enemy}'s, echo nicely in our halls.",
		"We do not negotiate with the {enemy}. We collect them.",
		"The {enemy} are a puzzle we solved centuries ago.",
		"We will outlast the {enemy}'s grandchildren's grandchildren.",
		"Their steel, the {enemy}'s, cannot cut what is already dead.",
		"We do not celebrate victories over the {enemy}. We file them.",
		"The {enemy} are wind. We are stone.",
		"We have seen the {enemy} at their best. It was adequate.",
		"Their gods have abandoned the {enemy}. We never had gods. Advantage: us.",
		"We do not get tired of killing the {enemy}. We don't get tired at all.",
		"The {enemy} are a story with a predictable ending.",
		"We will dance on the {enemy}'s graves. We are excellent dancers. We had time to practice.",
		"Their hope, the {enemy}'s, is the sweetest thing to extinguish.",
		"We do not need the {enemy} to fear us. They will anyway.",
		"The {enemy} are already ghosts. They just don't know it.",
		"We have infinite patience. The {enemy} have finite lives.",
		"Their defeat, the {enemy}'s, is not a matter of if. It is a matter of when. Soon.",
		"We do not hate. We do not love. We simply... end the {enemy}.",
		"The {enemy} will be a cautionary tale we tell our new recruits.",
		"We are the {enemy}'s inevitable future.",
		"Their blood, the {enemy}'s, is warm. Briefly.",
		"We do not make mistakes. The {enemy} are a mistake.",
		"The {enemy} cannot kill what does not live.",
		"We have been dead longer than the {enemy} have been alive.",
		"Their extinction, the {enemy}'s, will be... quiet. Peaceful. Inevitable.",
		"We do not want the {enemy}'s surrender. We want their silence.",
		"The {enemy} are a drop. We are the ocean.",
		"We will remember the {enemy}. Briefly. Then we will forget.",
		"Their courage is admirable, the {enemy}'s. It will not save them.",
		"We are not cruel to the {enemy}. Cruelty implies feeling.",
		"The {enemy} will join our ranks. Voluntarily or otherwise.",
		"We have no use for the {enemy}'s mercy. We have no use for the {enemy}.",
		"Their world, the {enemy}'s, is ending. We are the ending.",
		"We do not sleep, so we will be up all night ending the {enemy}.",
		"The {enemy} are a temporary inconvenience in our eternal plan.",
		"We will be here when the {enemy} are dust. We will be here after.",
		"The {enemy} are already forgotten. We are just waiting for their bodies to catch up.",
		"We do not blink. The {enemy} blink. Constantly. Nervously.",
		"Their end, the {enemy}'s, will not be dramatic. It will be... administrative.",
		"We have killed the {enemy} in every conceivable way. We are running out of ways. We will invent more.",
		"The {enemy} are a brief noise. We are the silence after.",
		"We do not need to defeat the {enemy}. Time defeats them. We just... help time along.",
		"The {enemy} are a question nobody asked, with an answer nobody wants.",
	],
}

## Jeremy 2026-10-04: Gazette scandal coverage for the REAL n-word.
## When the player uses it, the Gazette publishes a scandal sheet: the
## player's EXACT quote, an NPC witness report, and a merciless roast.
## {reporter} = NPC name, {job} = their job, {faction} = offended faction,
## {ruler} = player's faction name, {quote} = player's exact words.
const SLUR_REPORTER_NAMES := {
	"ogres": ["Grak", "Thog", "Mog", "Urz", "Brak", "Snag", "Durg", "Krog",
		"Yaz", "Hug"],
	"elves": ["Aelindra", "Faelar", "Sylwen", "Lirael", "Caelum", "Nerys",
		"Thalanil", "Elyssia", "Raviel", "Mirath"],
	"gnomes": ["Fizzle", "Boddle", "Tink", "Wizzle", "Nack", "Pip",
		"Dobble", "Zib", "Nim", "Quill"],
	"humans": ["Borin", "Marta", "Cedric", "Elsa", "Doran", "Petra",
		"Harold", "Greta", "Osric", "Lena"],
	"undead": ["Morvain", "Sylas", "Vex", "Noctis", "Erebus", "Lilith",
		"Corvus", "Morgath", "Selene", "Dread"],
}

const SLUR_REPORTER_JOBS := ["turnip farmer", "ambassador", "palace guard",
	"baker", "blacksmith", "messenger", "tavern keeper", "scribe",
	"stablehand", "merchant", "court jester", "gardener"]

const SLUR_GAZETTE_HEADLINES := [
	"RULER CAUGHT SPEAKING UNSPEAKABLE FILTH IN FOREIGN COURT",
	"SCANDAL: {ruler} Ruler Drops Slur, Starts War",
	"COURT IN CHAOS AFTER RULER'S VILE OUTBURST",
	"DIPLOMACY DIES: Slur Heard Round the World",
	"{faction} COURT DEMANDS APOLOGY THAT WILL NEVER COME",
	"RULER'S MOUTH WRITES CHECKS THEIR ARMY CAN'T CASH",
	"WAR DECLARED OVER SINGLE VILE WORD",
	"WITNESSES STUNNED AS RULER SAYS THE UNSAYABLE",
	"{ruler} RULER CANCELLED BY ENTIRE CONTINENT",
	"FROM DIPLOMAT TO DISGRACE IN ONE SENTENCE",
]

const SLUR_GAZETTE_REPORTS := [
	"\"I was just trying to sell this fool some turnips when he opened his mouth and ended diplomacy,\" said {reporter}, a {faction} {job}.",
	"\"The ambassador was seen shaking as he recounted it,\" our correspondent writes. \"'{quote}' — those were the words, spoken aloud, in a royal court.\"",
	"{reporter}, a {faction} {job} who witnessed the incident, told the Gazette: \"I thought I misheard. Nobody is that stupid. I was wrong.\"",
	"\"He said '{quote}' like he was ordering lunch,\" said {reporter}, still visibly stunned. \"In front of EVERYONE.\"",
	"Court insiders describe a silence 'so complete you could hear a pin drop, then a war horn.' {reporter}, a {faction} {job}, confirmed: \"That's exactly what happened.\"",
	"\"I have served the {faction} court for twenty years,\" said {reporter}. \"I have never — NEVER — heard that word spoken here. Until today.\"",
	"{reporter} was mopping the great hall when it happened. \"I dropped the mop,\" the {faction} {job} admitted. \"'Did he really just say {quote}?' Yes. Yes he did.\"",
	"\"My grandmother warned me about rulers like this,\" said {reporter}, a {faction} {job}. \"She said 'some fools dig their own graves with their tongues.' She was right.\"",
	"Witnesses report that several courtiers fainted. \"I was one of them,\" confessed {reporter}, a {faction} {job}. \"I woke up and we were at war.\"",
	"\"He didn't even slur his words — he was sober,\" marveled {reporter}. \"He said '{quote}' with complete clarity and confidence. Incredible.\"",
	"{reporter}, the {faction} {job} on duty, filed the official report: \"Subject said the unspeakable word. War followed within the minute. Recommend exorcism.\"",
	"\"I was carving a roast when he said it,\" said {reporter}. \"I put down the knife. Some things you don't want to be holding when war starts.\"",
	"\"The court scribe's quill broke from shock,\" reported {reporter}. \"The official record just reads '{quote}' followed by seventeen exclamation marks.\"",
	"{reporter} described the moment: \"Time stopped. Someone gasped. Someone else started crying. Then the warlord stood up and I ran.\"",
	"\"I've heard insults in my time,\" said {reporter}, a grizzled {faction} {job}. \"This wasn't an insult. This was a declaration of stupidity.\"",
	"\"He smiled when he said it,\" whispered {reporter}. \"Smiled. Like he'd just said something clever. The {faction} court will remember that smile.\"",
	"\"My children were in the gallery,\" said {reporter}, a {faction} {job}, voice shaking. \"My CHILDREN heard '{quote}' from a ruler's mouth.\"",
	"{reporter} summed it up: \"Diplomacy is the art of saying nothing. This fool mastered the opposite.\"",
	"\"The {faction} ambassador has requested — and I quote — 'a very strong drink and a very long war,'\" our correspondent notes.",
	"\"I sell turnips,\" said {reporter} simply. \"I have sold turnips through plagues and sieges. Nothing prepared me for '{quote}.'\"",
	"\"He'll deny it,\" predicted {reporter}, a {faction} {job}. \"They always deny it. But three hundred witnesses heard '{quote}.'\"",
	"\"The court jester has officially retired,\" announced {reporter}. \"He said 'I cannot top that. Nothing is funnier or sadder than this.'\"",
]

const SLUR_GAZETTE_ROASTS := [
	"In related news, the {ruler} royal tutor has resigned, stating 'I clearly failed.'",
	"Scholars confirm this is the fastest anyone has ever turned a diplomatic visit into a war crime. The previous record was three days. This took one sentence.",
	"The {ruler} court has declined to comment, presumably because they are busy facepalming.",
	"Experts say the ruler's approval rating is now lower than the dungeon floor.",
	"When reached for comment, the {ruler} royal advisor simply stared at our reporter for a full minute before whispering 'why.'",
	"The palace has announced a new position: Royal Mouth-Shutter. Applications open immediately.",
	"Historians are already calling this 'the single dumbest thing said in a court since the invention of courts.'",
	"The {ruler} treasury reports that the war will cost approximately one million gold. The sentence that started it was free.",
	"In a statement, the {ruler} court said 'we are looking into it.' Into WHAT, exactly, remains unclear.",
	"Local taverns have begun a drinking game: take a shot every time someone mentions the incident. The entire continent is now drunk.",
	"The royal speechwriter has been found innocent of all involvement. 'I would never write that,' he said. 'I have standards. Low ones, but they exist.'",
	"Diplomacy schools across the land have added a new lesson: 'Chapter One: Don't.'",
	"The {ruler} ruler's mother has been notified. She is 'very disappointed,' sources confirm.",
	"War correspondents note this is the first war in history started by a single vocabulary choice.",
	"The palace guard has requested hazard pay for 'emotional damage.'",
	"When asked if the ruler understood the consequences, one courtier laughed for nine minutes straight.",
	"The {ruler} royal library has moved all diplomacy books to the fiction section.",
	"Mercenaries report a surge in employment. 'We'd like to thank the {ruler} ruler personally,' said one captain, counting coins.",
	"The continent's jesters have declared a day of mourning — for comedy, which has been murdered by reality.",
	"Political analysts agree: this is what happens when confidence exceeds competence by a wide margin.",
	"In a leaked memo, the {ruler} war council wrote simply: '...why.'",
	"The royal portrait painter has asked to be reassigned. 'I cannot capture this level of disgrace in oils,' he explained.",
]

## Jeremy 2026-10-04: Squabble explodes when the player uses the real
## n-word. NPCs from the offended faction (and gleeful onlookers) post
## about it, roast the player, and reply to each other. {ruler} = the
## player's name, {faction} = offended faction name.
const SLUR_SQUABBLE_POSTS := [
	"Did the {ruler} ruler REALLY just say that?? In OUR court?? #Cancelled",
	"I was THERE. He said it. Out loud. With his whole chest. #WarTime",
	"New rule: the {ruler} ruler is not allowed to speak anymore. Ever. #ShutUp",
	"POV: you're a {faction} courtier and the visiting ruler ends diplomacy in one sentence",
	"He said the word and my grandmother felt it from the afterlife. #War",
	"Breaking: local ruler discovers that actions have consequences. More at war o'clock.",
	"I've seen some dumb things but '{ruler} says slur, starts war' is a new speedrun record",
	"The {faction} court right now: 😡 The {ruler} ruler right now: 😅 #Oops",
	"Imagine being so bad at diplomacy that ONE WORD starts a war. Couldn't be me.",
	"My kids asked what happened at court today. I said 'ask your history teacher in 20 years.'",
	"He really looked the {faction} queen in the eye and said THAT. The audacity. The stupidity.",
	"War was declared so fast the scribe didn't even finish writing the insult down",
	"Note to self: never invite the {ruler} ruler to dinner. Or anywhere. Ever.",
	"The {faction} warlord broke a TABLE. A whole table. That's how bad it was.",
	"Somewhere, a {ruler} advisor is updating their resume. #ThoughtsAndPrayers",
	"He said what he said and now we ride at dawn. #War",
	"Diplomacy is dead and the {ruler} ruler killed it with vocabulary",
	"I paid three gold for a court seat today. Best entertainment of my life. #WorthIt",
	"The Gazette headline tomorrow is going to be WILD. #Scandal",
	"Reminder that the {ruler} ruler did this SOBER. Imagine.",
]

const SLUR_SQUABBLE_REPLIES := [
	"I can't believe this is real",
	"My jaw is on the floor",
	"This is going in the history books",
	"He really thought he could say that and leave??",
	"The {faction} are NOT playing around",
	"War speedrun any% world record",
	"I'm telling my grandkids about this",
	"Unreal. Absolutely unreal.",
	"The court went SILENT. You could hear a pin drop.",
	"Someone check on the {ruler} advisor, they looked ill",
	"This is why we can't have nice rulers",
	"Posting from the bunker. It's war, folks.",
]

## Posts the slur incident to Squabble: NPCs from the offended faction react,
## roast the player, and reply to each other. The whole platform talks about it.
func _squabble_slur_posts(target: String, text: String) -> void:
	var phone = _gs.phone_sys
	if phone == null:
		return
	# Find NPCs from the offended faction to post.
	var posters: Array = []
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != target:
			continue
		posters.append(u)
		if posters.size() >= 4:
			break
	if posters.is_empty():
		return
	var ruler_name: String = str(_gs.ruler_name)
	var faction_name := _fname(target)
	# Each NPC posts a reaction.
	var posted: Array = []
	var used_posts: Array = []
	for u: Dictionary in posters:
		var template: String = str(SLUR_SQUABBLE_POSTS.pick_random())
		# Avoid exact duplicate posts.
		var guard := 0
		while template in used_posts and guard < 10:
			template = str(SLUR_SQUABBLE_POSTS.pick_random())
			guard += 1
		used_posts.append(template)
		var ptext: String = template.replace("{ruler}", ruler_name)
		ptext = ptext.replace("{faction}", faction_name)
		var post: Dictionary = phone.npc_post(u, ptext, "news")
		posted.append(post)
	# NPCs reply to each other's posts — the platform is buzzing.
	for i in posted.size():
		var post: Dictionary = posted[i]
		var pid: int = int(post.get("id", 0))
		# 1-2 replies per post from other posters.
		var repliers: Array = []
		for u: Dictionary in posters:
			if String(phone._key_for(int(u.get("id", 0)))) != String(post.get("author_key", "")):
				repliers.append(u)
		repliers.shuffle()
		for r in range(mini(2, repliers.size())):
			var reply: String = str(SLUR_SQUABBLE_REPLIES.pick_random())
			reply = reply.replace("{ruler}", ruler_name)
			reply = reply.replace("{faction}", faction_name)
			var ru: Dictionary = repliers[r]
			(phone.state["posts"] as Array)  # ensure state exists
			var p: Dictionary = phone._find_post(pid)
			if not p.is_empty():
				(p["comments"] as Array).append({
					"author": SimPersonality.display_name(ru), "text": reply})
		# The scandal gets engagement.
		for k in range(randi_range(3, 12)):
			phone.like_post(pid)
		for k in range(randi_range(1, 5)):
			phone.resquabble(pid)


## Publishes the Gazette scandal article for the real n-word incident.
## Includes the player's exact quote, an NPC witness report, and a roast.
func _gazette_slur_article(insulter: String, target: String,
		text: String) -> void:
	var reporter: String = str(
		(SLUR_REPORTER_NAMES.get(target, ["Witness"]) as Array).pick_random())
	var job: String = str(SLUR_REPORTER_JOBS.pick_random())
	var headline: String = str(SLUR_GAZETTE_HEADLINES.pick_random())
	headline = headline.replace("{ruler}", _fname(insulter))
	headline = headline.replace("{faction}", _fname(target))
	var report: String = str(SLUR_GAZETTE_REPORTS.pick_random())
	report = report.replace("{reporter}", reporter)
	report = report.replace("{job}", job)
	report = report.replace("{faction}", _fname(target))
	report = report.replace("{quote}", text)
	var roast: String = str(SLUR_GAZETTE_ROASTS.pick_random())
	roast = roast.replace("{ruler}", _fname(insulter))
	var body := "%s\n\nWhen asked for comment, the %s ruler reportedly said: \"%s\"\n\n%s" % [
		report, _fname(insulter), text, roast]
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs, headline, body, "scandal")

## Faction-specific freak-out reactions to the slur. Each faction drops
## everything and reacts in character — this is the worst thing you can say.
const SLUR_REACTIONS := {
	"ogres": "The ogre warlord ROARS and smashes the table in half! "
		+ "\"YOU DARE SPEAK THAT FILTH IN MY HALL?! WAR! WAR TO THE DEATH!\"",
	"undead": "The lich's eyes ignite with cold blue fire. The air freezes. "
		+ "\"You have spoken a word that has ended kingdoms. The dead do not "
		+ "forgive. WAR.\"",
	"elves": "The elven court falls deathly silent. The queen rises, trembling "
		+ "with fury. \"That word is poison. You are poison. Leave my sight — "
		+ "and prepare for WAR.\"",
	"humans": "Gasps echo through the human court. The king's face goes white, "
		+ "then red. \"Seize— no. WAR. We go to WAR for this. Get out!\"",
	"gnomes": "The laughter dies instantly. Every gnome in the hall stares in "
		+ "horror. The elder speaks quietly: \"We joke about everything. Not "
		+ "that. NEVER that. This means WAR.\"",
}

## True if the given insult text contains the n-word (hard r), matched as a
## full word with word boundaries — case-insensitive, no substring hits.
func _contains_slur(text: String) -> bool:
	if text.is_empty():
		return false
	var re := RegEx.new()
	if re.compile(SLUR_PATTERN) != OK:
		return false
	return re.search(text) != null


## Shared instant-war machinery for slur paths (real n-word and fantasy
## slurs). Instant war, no thresholds, no rolls. Heavy rep hit, score tanks.
func _slur_war_common(insulter: String, target: String, text: String,
		reaction: String, event_label: String, headline: String,
		war_reason: String) -> Dictionary:
	var rec: Dictionary = _pair(insulter, target)
	rec["insult_count"] = int(rec.get("insult_count", 0)) + 1
	_record(insulter, target, event_label, insulter)
	# Heavy reputation hit — everyone hears about this.
	_add_reputation(insulter, -20.0)
	declare_war(target, insulter, war_reason)
	# Relationship tanks to rock bottom (after declare_war's own -80).
	rec["score"] = -100.0
	_report(headline,
		"On day %d, %s said \"%s\" to the %s court. %s" % [
			_gs.day_number, _fname(insulter), text, _fname(target), reaction],
		"war")
	return {"ok": true, "slur": true,
		"msg": "%s declares WAR! %s" % [_fname(target), reaction]}


## Handles the REAL n-word path: universal instant war, NO exceptions.
## Called from insult() — runs BEFORE any fantasy slur / relationship logic.
## Also publishes the Gazette scandal article with the player's exact quote.
## offender_name: personal name when a NAMED NPC (not a faction ruler) is the
## offender — hearsay names them directly ("Grak is racist"). "" for rulers.
func _slur_war(insulter: String, target: String, text: String,
		offender_name: String = "") -> Dictionary:
	var reaction: String = String(SLUR_REACTIONS.get(target,
		"The court's fury is absolute. \"WAR!\""))
	var result := _slur_war_common(insulter, target, text, reaction, "slur",
		"%s declares WAR over a slur!" % _fname(target),
		"said the unsayable to %s" % _fname(insulter))
	# Jeremy 2026-10-04: it winds up in the Gazette with the exact quote,
	# roasting the player, with the reporting NPC's account. And Squabble
	# explodes — the whole platform talks about it.
	_gazette_slur_article(insulter, target, text)
	_squabble_slur_posts(target, text)
	# Jeremy 2026-10-04: the hearsay system condemns racism explicitly —
	# every faction, in their own voice: GAH FUCK RACISTS. The game takes
	# a clear stance. (Real n-word only; fantasy slurs keep relationship
	# logic in _fantasy_slur_war, which does NOT emit this.)
	# Jeremy 2026-10-04: NPC offenders are named personally so the realm
	# spreads the word that THEY are racist. offender_name "" = ruler.
	_gs.bus.slur_incident.emit(insulter, target, text, offender_name)
	return result


## Which faction (if any) does the text slur with fantasy racial slurs?
## Returns the faction id, or "" when no fantasy slur is found.
func _detect_slur_target(text: String) -> String:
	if text.is_empty():
		return ""
	for faction: String in FANTASY_SLURS.keys():
		var words: Array = FANTASY_SLURS[faction]
		var pattern := "(?i)\\b(" + "|".join(words) + ")\\b"
		var re := RegEx.new()
		if re.compile(pattern) == OK and re.search(text) != null:
			return faction
	return ""


## True when faction a hates (or is at war with) faction b.
func _faction_hates(a: String, b: String) -> bool:
	if a == b:
		return false
	if relation_state(a, b) == "war":
		return true
	return relation_score(a, b) < HOSTILE_BELOW


## Jeremy 2026-10-04: "enemy of my enemy" — the reacting faction HATES (or
## is at war with) the slurred faction, so they AGREE with your slur and
## pile on with their own insults about that faction. Your relationship
## with them IMPROVES. No war.
func _slur_pileon(insulter: String, target: String, text: String,
		slur_target: String) -> Dictionary:
	var rec: Dictionary = _pair(insulter, target)
	rec["insult_count"] = int(rec.get("insult_count", 0)) + 1
	_record(insulter, target, "slur_pileon", insulter)
	# Enemy of my enemy: they like you more for hating their enemy.
	adjust_score(insulter, target, 15.0)
	var pool: Array = HATE_INSULTS.get(target, [])
	var jab: String = "They're the worst!"
	if not pool.is_empty():
		jab = str(pool.pick_random())
	jab = jab.replace("{enemy}", _fname(slur_target))
	_report("%s piles on the %s!" % [_fname(target), _fname(slur_target)],
		"On day %d, %s slurred the %s in front of the %s court: \"%s\" "
		% [_gs.day_number, _fname(insulter), _fname(slur_target),
			_fname(target), text]
		+ "The %s roar with laughter and pile on: \"%s\"" % [
			_fname(target), jab],
		"court")
	return {"ok": true, "slur": true, "pileon": true,
		"msg": "The %s LOVE it! \"%s\" (Your standing with them improves.)"
			% [_fname(target), jab]}


## Fantasy slur against a faction the reacting court does NOT hate:
## instant war + freak out, like the real slur but with race-specific fury.
func _fantasy_slur_war(insulter: String, target: String, text: String,
		slur_target: String) -> Dictionary:
	var reaction: String = String(FANTASY_SLUR_REACTIONS.get(target,
		"The court's fury is absolute. \"WAR!\""))
	reaction = reaction.replace("{race}", _fname(slur_target))
	return _slur_war_common(insulter, target, text, reaction, "fantasy_slur",
		"%s declares WAR over a slur!" % _fname(target),
		"used a racial slur against the %s" % _fname(slur_target))


## Routes a fantasy slur: pile-on when they hate the slurred faction,
## instant war + freak out otherwise (including slurring them directly).
func _fantasy_slur(insulter: String, target: String, text: String,
		slur_target: String) -> Dictionary:
	if slur_target == target or not _faction_hates(target, slur_target):
		return _fantasy_slur_war(insulter, target, text, slur_target)
	return _slur_pileon(insulter, target, text, slur_target)

func insult(insulter: String, target: String, text: String = "",
		offender_name: String = "") -> Dictionary:
	var rec: Dictionary = _pair(insulter, target)
	if rec.is_empty() or insulter == target:
		return {"ok": false, "msg": "Unknown faction pair."}
	var st := String(rec.get("state", ""))
	if st == "war":
		return {"ok": false,
			"msg": "You are already at war — save your breath for the battlefield."}
	# Jeremy 2026-10-04: the REAL n-word (hard r) is a universal instant
	# war crime — checked FIRST, bypasses alliances, thresholds, and the
	# "enemy of my enemy" exception. No one gets a pass on this one.
	if _contains_slur(text):
		return _slur_war(insulter, target, text, offender_name)
	# Jeremy 2026-10-04: FANTASY slurs follow relationship logic — if the
	# reacting faction hates (or is at war with) the slurred faction, they
	# pile on and like you more. Otherwise: instant war + freak out.
	var slur_target := _detect_slur_target(text)
	if not slur_target.is_empty():
		return _fantasy_slur(insulter, target, text, slur_target)
	# Custom text or preset line.
	var line: String = text if not text.is_empty() else String(INSULT_LINES.get(
		target, "Your mother was a hamster."))
	_record(insulter, target, "insulted", insulter)
	_add_reputation(insulter, -5.0)
	if st == "allied":
		rec["state"] = "neutral"
		relation_version += 1  # R23: hostile-set cache invalidation
		rec["score"] = -20.0
		rec["trade_active"] = false
		# The alliance opened a physical route: its wagons stop with it.
		_end_physical_trade(insulter, target)
		_gs.bus.relation_changed.emit(insulter, target, "neutral")
		_report("%s insults %s!" % [_fname(insulter), _fname(target)],
			"On day %d, %s told the %s court: \"%s\" The alliance \
strained to neutral and trade was dissolved." % [_gs.day_number,
			_fname(insulter), _fname(target), line], "court")
		return {"ok": true, "msg": "%s takes offense — alliance strained \
to neutral. \"%s\"" % [_fname(target), line]}
	# Jeremy 2026-10-04: faction-specific insult temperament, with a
	# guaranteed minimum number of insults before ANY faction can snap
	# ("more than a couple" even for the hotheads). Ogres and undead are
	# the most short-tempered. Elves take a lot. Gnomes just talk shit
	# back playfully no matter what. Humans are cowards who avoid war
	# out of fear.
	var war_min: int = int(INSULT_WAR_MIN.get(target, 3))
	var score: float = float(rec.get("score", 0.0))
	var insults_before: int = int(rec.get("insult_count", 0))
	rec["insult_count"] = insults_before + 1
	var n: int = insults_before + 1  # this insult included
	var war_chance := 0.0
	var response := ""
	match target:
		"ogres":
			# Short-tempered: patience wears thin fast.
			war_chance = 0.0 if n < war_min else minf(0.15 * float(n), 0.9)
			if n <= 2:
				response = "The ogres grunt and crack their knuckles."
			elif n <= 4:
				response = "The ogres are visibly shaking with rage."
			else:
				response = "The ogres have had enough of your mouth."
		"undead":
			# Same short fuse as ogres.
			war_chance = 0.0 if n < war_min else minf(0.15 * float(n), 0.9)
			if n <= 2:
				response = "The dead stare at you with hollow patience."
			elif n <= 4:
				response = "The lich's eyes burn brighter with each word."
			else:
				response = "The grave's patience is spent."
		"elves":
			# Takes a lot — deep patience.
			war_chance = 0.0 if n < war_min else minf(0.03 * float(n), 0.5)
			if n <= 4:
				response = "The elves regard you with icy patience."
			elif n <= 8:
				response = "The elves' calm is starting to crack."
			else:
				response = "Even elven patience has limits."
		"gnomes":
			# Gnomes just talk shit back, always playful. Insults never
			# start a war with them — they think it's hilarious.
			war_chance = 0.0
			response = "The gnomes howl with laughter and roast you \
right back."
		_:
			# Humans: cowards. They'd rather back down than fight.
			war_chance = 0.0 if n < war_min else minf(0.02 * float(n), 0.15)
			if n <= 2:
				response = "The humans laugh nervously and look away."
			else:
				response = "The humans are scared but trying to act tough."
	adjust_score(insulter, target, -25.0)
	if randf() < war_chance:
		var wr: Dictionary = declare_war(target, insulter,
			"insulted by %s" % _fname(insulter))
		_report("%s declares a feud!" % _fname(target),
			"On day %d, %s could not stomach the insult: \"%s\" \
War!" % [_gs.day_number, _fname(target), line], "war")
		return {"ok": true, "msg": "%s declares a feud! \"%s\" %s" % [
			_fname(target), line, response]}
	_report("%s insults %s" % [_fname(insulter), _fname(target)],
		"On day %d, %s told the %s court: \"%s\" %s" % [_gs.day_number,
		_fname(insulter), _fname(target), line, response], "court")
	return {"ok": true, "msg": "\"%s\" — %s" % [line, response]}


## Nudges a pair's opinion score (clamped); syncs the visible state.
func adjust_score(a: String, b: String, delta: float) -> void:
	var rec: Dictionary = _pair(a, b)
	if rec.is_empty():
		return
	rec["score"] = clampf(float(rec.get("score", 0.0)) + delta,
		-100.0, 100.0)
	_sync_state(a, b)


## --- tick -------------------------------------------------------------------

## Called every physics tick; runs the daily diplomacy pass on day change.
func tick(_delta: float) -> void:
	if _gs.day_number == _last_day:
		return
	_last_day = _gs.day_number
	_daily()


func _daily() -> void:
	for key: String in _pairs.keys():
		var rec: Dictionary = _pairs[key]
		var a: String = String(rec["a"])
		var b: String = String(rec["b"])
		# Trade deals expire.
		if bool(rec.get("trade_active", false)) \
				and _gs.day_number > int(rec.get("trade_until_day", 0)):
			rec["trade_active"] = false
			adjust_score(a, b, -5.0)
			# A lapsed deal ends the wagons too — no ghost trade.
			_end_physical_trade(a, b)
		var st := String(rec.get("state", ""))
		if st == "war":
			# War weariness.
			_add_morale(a, -1.0)
			_add_morale(b, -1.0)
			continue
		# Gentle drift: warm pairs climb, cold pairs slide (HTML feed).
		var fa := faction_traits(a)
		var fb := faction_traits(b)
		var natural: float = ((float(fa["friendly"]) \
			+ float(fb["friendly"])) * 0.5 - 0.5) * 40.0
		rec["score"] = clampf(lerpf(float(rec.get("score", 0.0)),
			natural, 0.15), -100.0, 100.0)
		_sync_state(a, b)
		if bool(rec.get("trade_active", false)):
			_trade_exchange(a, b)
	# Slow regen toward baselines.
	for f: String in _morale.keys():
		_morale[f] = clampf(lerpf(float(_morale[f]), 70.0, 0.1),
			0.0, 100.0)
	for f: String in _reputation.keys():
		_reputation[f] = clampf(lerpf(float(_reputation[f]), 60.0, 0.05),
			0.0, 100.0)
	_surrender_tick()
	_collapse_tick()
	_aid_tick()
	_ai_tick()


## Follows score bands for non-locked states (war/allied are explicit).
func _sync_state(a: String, b: String) -> void:
	var rec: Dictionary = _pair(a, b)
	if rec.is_empty():
		return
	var st := String(rec.get("state", ""))
	if st == "war" or st == "allied":
		return
	var sc := float(rec.get("score", 0.0))
	var want := "neutral"
	if sc <= HOSTILE_BELOW:
		want = "hostile"
	elif sc >= FRIENDLY_ABOVE:
		want = "friendly"
	if want != st:
		rec["state"] = want
		relation_version += 1  # R23: hostile-set cache invalidation
		_gs.bus.relation_changed.emit(a, b, want)


## AI rulers act: brave factions start wars, friendly ones ally, strong
## ones demand tribute, grudges block friendship. AI->player moves arrive
## as Royal Court petitions (the crown decides).
func _ai_tick() -> void:
	var player: String = _gs.player_faction
	for key: String in _pairs.keys():
		var rec: Dictionary = _pairs[key]
		var a: String = String(rec["a"])
		var b: String = String(rec["b"])
		for actor: String in [a, b]:
			var target: String = b if actor == a else a
			if actor == player:
				continue  # the player acts through the UI
			_ai_consider(actor, target)


func _ai_consider(a: String, b: String) -> void:
	var st := relation_state(a, b)
	var sc := relation_score(a, b)
	var traits := faction_traits(a)
	var brave: float = float(traits["brave"])
	var friendly: float = float(traits["friendly"])
	var proud: float = float(traits["proud"])
	var aggro: float = float(traits["aggro"])
	var tribute_value: float = float(traits["tribute_value"])
	var honor_value: float = float(traits["honor_value"])
	var str_a := military_strength(a)
	var str_b := military_strength(b)
	if st == "war":
		# Losing and not too proud: sue for peace.
		# High-aggro factions fight on longer (ogres rarely surrender).
		var surrender_threshold := 0.45 * (1.0 + aggro * 0.5)
		if str_a < str_b * surrender_threshold and proud < 0.7 \
				and morale_of(a) < 55.0:
			make_peace(a, b)
			return
		# Alliance obligations: allies join the war or send aid.
		for c: String in _gs.active_factions:
			if c == a or c == b:
				continue
			if relation_state(a, c) != "allied":
				continue
			var ct := faction_traits(c)
			if relation_state(c, b) != "war" \
					and float(ct["brave"]) > 0.55 and randf() < 0.25:
				declare_war(c, b, "honoring their alliance with %s"
					% _fname(a))
			elif faction_wealth(c) > faction_wealth(a) * 1.5 \
					and randf() < 0.3:
				var gift: float = maxf(5.0,
					_gs.resources.get_amount(c, "gold") * 0.1)
				pay_tribute(c, a, "gold", gift)  # military aid
		return
	if st == "allied":
		_ai_consider_betrayal(a, b, traits, str_a, str_b)
		return
	# Brave + stronger: war. Grudges light the fuse too.
	# Canonical aggro scales the war threshold: ogres (1.0) need less
	# provocation, elves (0.35) need much more.
	# A signed truce blocks new declarations (HTML diplomacy pacing).
	var war_brave_threshold := 0.62 - (aggro - 0.5) * 0.3
	var war_rand := 0.3 * (0.5 + aggro)
	var grudge := grudge_against(a, b)
	if truce_active(a, b):
		return
	if (brave > war_brave_threshold and str_a > str_b * 1.6 and sc < 5.0 \
			and randf() < war_rand) \
			or (grudge <= -1.5 and brave > 0.5 and str_a > str_b \
			and randf() < 0.3):
		if b == _gs.player_faction:
			_petition_threat(a)
		else:
			declare_war(a, b, "conquest")
		return
	# Friendly: propose alliances. High-diplomacy factions (elves 0.85)
	# actively seek friends; low-diplomacy (ogres 0.2) never do.
	if friendly > 0.6 and sc >= 30.0 and randf() < 0.2:
		if b == _gs.player_faction:
			_petition_alliance(a)
		else:
			propose_alliance(a, b)
		return
	# Strong: demand tribute from the weak.
	# High tribute-value factions (ogres 0.95) bully more often and
	# demand more; low tribute-value (elves 0.3) rarely bother.
	var tribute_rand := 0.15 * (0.3 + tribute_value)
	var tribute_mult := 0.8 + tribute_value * 0.6
	if (st == "hostile" or st == "neutral") and str_a > str_b * 1.8 \
			and str_b >= 1.0 and randf() < tribute_rand:
		var amt: float = maxf(10.0,
			_gs.resources.get_amount(b, "gold") * 0.15 * tribute_mult)
		if b == _gs.player_faction:
			_petition_tribute(a, b, amt)
		else:
			demand_tribute(a, b, "gold", amt)
		return
	# Warm pairs sign trade deals.
	# Principled factions (elves, honor 1.0) won't trade with
	# dishonerable partners (reputation < 40).
	if honor_value >= 0.9 and reputation_of(b) < 40.0:
		return
	if sc >= 10.0 and not has_trade_deal(a, b) and st != "hostile" \
			and randf() < 0.15:
		sign_trade_agreement(a, b)


## --- AI betrayal ------------------------------------------------------------


## Alliances are not sacred to every faction: treacherous rulers (high
## aggro, low honor) may turn on an ally when the prize is worth the
## infamy. Principled factions (elves, honor 1.0) never betray. The HTML
## AI never attacked friends (war32AiWarTick: "never attack friends") —
## this is a deliberate improvement on the port: betrayal makes
## alliances a gamble, and declare_war already prices the infamy
## (-15 reputation, the treaty_broken grudge, diplomatic isolation once
## reputation sinks below 35).
func _ai_consider_betrayal(a: String, b: String, traits: Dictionary,
		str_a: float, str_b: float) -> void:
	var rec: Dictionary = _pair(a, b)
	if rec.is_empty():
		return
	var honor: float = float(traits["honor_value"])
	if honor >= 0.9:
		return  # principled factions keep their oaths
	var aggro: float = float(traits["aggro"])
	# The ink must dry: no instant backstabbing right after signing.
	var allied_days: int = _gs.day_number \
		- int(rec.get("allied_since_day", 0))
	if allied_days < BETRAYAL_MIN_ALLIANCE_DAYS:
		return
	# A bought-off betrayal buys quiet for a while.
	if _gs.day_number < int(rec.get("betrayal_cooldown_until", 0)):
		return
	if truce_active(a, b):
		return
	# Motive: overwhelming strength, a festering grudge, or a distracted
	# ally already bleeding in another war.
	var b_distracted := false
	for c: String in _gs.active_factions:
		if c != a and c != b and relation_state(b, c) == "war":
			b_distracted = true
			break
	var grudge := grudge_against(a, b)
	var motive := false
	if str_a > str_b * 2.2 and str_b >= 1.0:
		motive = true  # the ally is ripe for the taking
	elif grudge <= -1.0:
		motive = true  # old wounds fester under the treaty
	elif b_distracted and str_a > str_b * 1.3 and aggro > 0.5:
		motive = true  # kick them while they're down
	if not motive:
		return
	# Treacherous factions roll often; the honorable barely consider it.
	if randf() >= 0.12 * aggro * (1.0 - honor):
		return
	if b == _gs.player_faction:
		# The crown gets a warning and a chance to buy loyalty — never
		# a silent knife. (No envoy to carry the warning: hold the dagger.)
		if _envoy(a).is_empty():
			return
		rec["betrayal_cooldown_until"] = _gs.day_number \
			+ BETRAYAL_COOLDOWN_DAYS
		_petition_betrayal_warning(a)
		return
	_betray(a, b)


## The knife: war on an ally, with the scandal it deserves. declare_war
## already prices the infamy (reputation -15, the treaty_broken grudge);
## the Gazette gets its own BETRAYAL! headline on top of the war report.
func _betray(a: String, b: String) -> Dictionary:
	var res: Dictionary = declare_war(a, b, "betrayal")
	if not bool(res.get("ok", false)):
		return res
	_report("BETRAYAL! %s turns on %s" % [_fname(a), _fname(b)],
		"Oathbreakers! On day %d, %s tore up their alliance with %s and \
fell upon their former friends without warning. Every court in the land \
will remember this treachery." % [_gs.day_number, _fname(a), _fname(b)],
		"court")
	return res


## --- AI -> player petitions -------------------------------------------------

## The crown decides these (Royal Court), so the player always has agency.
func _envoy(faction: String) -> Dictionary:
	for u: Dictionary in _gs.units:
		if u.get("alive", false) \
				and String(u.get("faction", "")) == faction:
			return u
	return {}


func _petition_alliance(a: String) -> void:
	if court == null:
		return
	var e := _envoy(a)
	if e.is_empty():
		return
	court.petition(e, "alliance",
		"%s of the %s seeks a grand alliance with your crown. \
Their banners are already sewn — will you stand as one?" % [
			SimPersonality.display_name(e), _fname(a)],
		["Accept alliance", "Refuse"] as Array[String])


func _petition_tribute(a: String, b: String, amt: float) -> void:
	if court == null:
		return
	var e := _envoy(a)
	if e.is_empty():
		return
	var p: Dictionary = court.petition(e, "tribute",
		"%s of the %s demands tribute: %d gold, or their spears will \
do the asking. Their war host darkens your border." % [
			SimPersonality.display_name(e), _fname(a), int(amt)],
		["Accept tribute", "Refuse"] as Array[String])
	p["tribute_amount"] = amt


func _petition_threat(a: String) -> void:
	if court == null:
		return
	var e := _envoy(a)
	if e.is_empty():
		return
	var p: Dictionary = court.petition(e, "threat",
		"%s of the %s howls for war! Their host marches on your \
borders as we speak. Defy them and it is war — pay and they may turn \
aside." % [SimPersonality.display_name(e), _fname(a)],
		["Defy them", "Pay 40 gold"] as Array[String])
	p["tribute_amount"] = 40.0


## An ally's loyalty is wavering: the crown may buy it back or meet the
## treachery with steel. Resolved through royal_court._apply_diplomatic.
func _petition_betrayal_warning(a: String) -> void:
	if court == null:
		return
	var e := _envoy(a)
	if e.is_empty():
		return
	var p: Dictionary = court.petition(e, "betrayal",
		"Our spies bring grave news: %s of the %s masses troops on our \
border, alliance or no alliance. Their loyalty can still be bought — or \
we meet treachery with steel." % [SimPersonality.display_name(e),
			_fname(a)],
		["Bribe them (60 gold)", "Let them come"] as Array[String])
	p["tribute_amount"] = 60.0


## A losing faction begs the player's crown for peace. The petition
## carries the offer id so the court's decision resolves the offer.
func _petition_surrender(loser: String, winner: String, tribute: int,
		offer_id: String) -> void:
	if court == null:
		return
	var e := _envoy(loser)
	if e.is_empty():
		return
	var p: Dictionary = court.petition(e, "surrender",
		"%s of the %s yields! Their host is broken — they offer %d gold \
in reparations to end this war. Accept, and the white flag flies; \
refuse, and the slaughter continues." % [SimPersonality.display_name(e),
			_fname(loser), tribute],
		["Accept surrender", "Refuse"] as Array[String])
	p["surrender_offer_id"] = offer_id
	p["tribute_amount"] = float(tribute)


## --- wartime aid ------------------------------------------------------------
## Jeremy 2026-10-05: HTML war32AidTick / war32AidResolve parity. Allies at
## war and losing beg the PLAYER for aid (gold or troops); the crown answers
## through a Royal Court petition. AI-vs-AI aid is not in the HTML — allies
## of other AI factions get no begging letters here either.


## Any pending aid request from this asker (HTML w.aid[r.key] parity).
func _pending_aid_for(asker: String) -> Dictionary:
	for aid_id: String in _aid_requests.keys():
		var req: Dictionary = _aid_requests[aid_id]
		if String(req.get("asker", "")) == asker:
			return req
	return {}


## All unresolved aid requests (court/phone UI reads this).
func pending_aid_requests() -> Array:
	return _aid_requests.values()


## True when the faction is at war with anyone.
func _faction_at_war(f: String) -> bool:
	for key: String in _pairs.keys():
		var rec: Dictionary = _pairs[key]
		if String(rec.get("state", "")) != "war":
			continue
		if String(rec.get("a", "")) == f or String(rec.get("b", "")) == f:
			return true
	return false


## Public read: true when the faction is at war with anyone. The phone's
## Rumors app gates its WAR tag on this (Jeremy 2026-10-06): stale
## capture/battle rumors must not stamp WAR during peacetime.
func faction_at_war(f: String) -> bool:
	return _faction_at_war(f)


## Daily: losing allies beg the player for wartime aid (HTML war32AidTick).
func _aid_tick() -> void:
	var player: String = _gs.player_faction
	for f: String in _morale.keys():
		if f == player:
			continue
		if relation_state(f, player) != "allied":
			continue
		if not _faction_at_war(f):
			continue
		if not _pending_aid_for(f).is_empty():
			continue
		# Losing? Compare own muster vs strongest foe's (HTML 0.8 bar).
		var own := military_strength(f)
		var foe_best := 0.0
		for o: String in _morale.keys():
			if o == f:
				continue
			var st := relation_state(f, o)
			if st == "war" or st == "hostile":
				foe_best = maxf(foe_best, military_strength(o))
		if not (foe_best > 0.0 and own < foe_best * 0.8):
			continue
		if randf() > 0.5:
			continue  # pride: not every day
		var what := "gold"
		var amount := 0
		if randf() < 0.5:
			what = "troops"
			amount = 4 + int(randf() * 6.0)  # HTML: 4 + floor(rand*6)
		else:
			amount = 300 + int(randf() * 500.0)  # HTML: 300 + floor(rand*500)
		offer_aid(f, what, amount)


## Creates the request and routes it to the crown as a court petition.
## Returns the aid_id ("" when the asker already has one pending).
func offer_aid(asker: String, what: String, amount: int) -> String:
	if not _pending_aid_for(asker).is_empty():
		return ""
	_aid_seq += 1
	var aid_id := "aid%d" % _aid_seq
	_aid_requests[aid_id] = {
		"asker": asker, "what": what, "amount": amount,
		"day": _gs.day_number,
	}
	_petition_aid(asker, what, amount, aid_id)
	return aid_id


func _petition_aid(asker: String, what: String, amount: int,
		aid_id: String) -> void:
	if court == null:
		return
	var e := _envoy(asker)
	if e.is_empty():
		return
	var want := "%d gold" % amount if what == "gold" \
		else "%d soldiers" % amount
	var p: Dictionary = court.petition(e, "aid",
		"%s of the %s begs for wartime aid! \"My friend... the war goes \
badly. The %s are bleeding. Send %s and I will not forget it.\" Refuse, \
and the slight will NEVER be forgotten." % [
			SimPersonality.display_name(e), _fname(asker), _fname(asker),
			want],
		["Send aid", "Refuse"] as Array[String])
	p["aid_request_id"] = aid_id


## The crown answers an aid request (court petition or debug path). Accept
## moves REAL aid: gold changes hands; troops are mustered at the ally's
## town (25g hire fee per soldier, capped by the treasury). Refuse: -45 and
## a grudge that never fully fades (HTML "We are DONE.").
func resolve_aid(aid_id: String, accept: bool) -> Dictionary:
	var req: Dictionary = _aid_requests.get(aid_id, {})
	if req.is_empty():
		return {"ok": false, "msg": "No such aid request."}
	_aid_requests.erase(aid_id)
	var asker := String(req["asker"])
	var player := String(_gs.player_faction)
	var what := String(req["what"])
	var amount := int(req["amount"])
	if accept:
		var sent := 0
		if what == "gold":
			var have: float = _gs.resources.get_amount(player, "gold")
			sent = int(minf(float(amount), maxf(0.0, have)))
			_gs.resources.add_resource(player, "gold", -float(sent))
			_gs.resources.add_resource(asker, "gold", float(sent))
			_gs.bus.tribute_paid.emit(player, asker, "gold", float(sent))
		else:
			sent = _muster_aid_troops(player, asker, amount)
		# HTML bumps: min(30, 10 + amt/100) their view, +10 ours.
		adjust_score(asker, player, minf(30.0, 10.0 + float(amount) / 100.0))
		adjust_score(player, asker, 10.0)
		_record(asker, player, "aid_given", player)
		_add_morale(asker, 8.0)
		_report("%s answers the call for aid" % _fname(player),
			"On day %d, the crown sent %s to their bleeding ally the %s. \
The alliance is iron." % [_gs.day_number,
				_aid_sent_text(what, sent, amount), _fname(asker)], "war")
	else:
		# Refuse an ally in need: royally pissed off, durable (HTML grudge).
		adjust_score(asker, player, -45.0)
		_record(asker, player, "aid_refused", player)
		_add_morale(asker, -6.0)
		_report("%s refuses their ally's plea" % _fname(player),
			"On day %d, the %s begged for %s and were refused. \"So be it. \
When the %s bleed out, remember you watched. We are DONE.\"" % [
				_gs.day_number, _fname(asker),
				"%d gold" % amount if what == "gold"
					else "%d soldiers" % amount, _fname(asker)], "war")
	return {"ok": true}


func _aid_sent_text(what: String, sent: int, asked: int) -> String:
	var noun := "gold" if what == "gold" else "soldiers"
	if sent >= asked:
		return "%d %s" % [sent, noun]
	return "%d of %d %s (the treasury ran dry)" % [sent, asked, noun]


## Musters sellswords for an ally: the crown pays the hire fee per soldier,
## capped by what the treasury holds; soldiers spawn at the ally's town.
func _muster_aid_troops(player: String, asker: String, amount: int) -> int:
	var gold: float = _gs.resources.get_amount(player, "gold")
	var count := mini(amount, int(gold / AID_TROOP_COST))
	if count <= 0:
		return 0
	_gs.resources.add_resource(player, "gold", -float(count) * AID_TROOP_COST)
	var town_id := -1
	var pos := Vector2.ZERO
	for tid: int in _gs.towns.keys():
		var t: Dictionary = _gs.towns[tid]
		if String(t.get("faction", "")) == asker:
			town_id = int(t.get("id", -1))
			pos = t.get("position", Vector2.ZERO) as Vector2
			break
	for i: int in range(count):
		var off := Vector2(randf_range(-48.0, 48.0),
			randf_range(-48.0, 48.0))
		_gs.spawner.spawn_unit(asker, "soldier", town_id, pos + off)
	return count


## --- war collapse -----------------------------------------------------------
## Jeremy 2026-10-05: HTML war32CollapseTick / war32SlowTick parity. Wars end
## when a side can't fight anymore (military strength < 2): both broken ->
## mutual collapse; one broken -> the winner crushes them (peace + the
## winner's contempt: -20 pair score AFTER make_peace resets it, HTML bump
## order). Every peace signs the usual 45-day truce inside make_peace.
func _collapse_tick() -> void:
	for key: String in _pairs.keys():
		var rec: Dictionary = _pairs[key]
		if String(rec.get("state", "")) != "war":
			continue
		var a := String(rec.get("a", ""))
		var b := String(rec.get("b", ""))
		var a_can := military_strength(a) >= 2.0
		var b_can := military_strength(b) >= 2.0
		if a_can and b_can:
			continue
		if not a_can and not b_can:
			_report("%s and %s bleed each other white" % [_fname(a),
					_fname(b)],
				"On day %d, both hosts collapsed — neither side could field \
an army. The war ends." % _gs.day_number, "war")
			make_peace(a, b)
		else:
			var winner := a if a_can else b
			var loser := b if a_can else a
			_report("%s crushes %s" % [_fname(winner), _fname(loser)],
				"On day %d, %s broke %s — their armies are shattered. \
The war is over." % [_gs.day_number, _fname(winner),
					_fname(loser)], "war")
			make_peace(a, b)
			# Contempt AFTER the peace reset (HTML war32Bump order).
			adjust_score(winner, loser, -20.0)


## --- internals --------------------------------------------------------------


func _record(a: String, b: String, etype: String, by: String) -> void:
	var rec: Dictionary = _pair(a, b)
	if rec.is_empty():
		return
	var hist: Array = rec["history"]
	hist.append({
		"type": etype,
		"by": by,
		"game_time": _gs.game_time,
	})
	# Cap history (cheap: pairs are few, events few).
	while hist.size() > 24:
		hist.pop_front()


## Public read of a pair's event history — the favor model behind the
## war-spare fate vote and the disaster-aid vote (Jeremy 2026-10-11).
func pair_history(a: String, b: String) -> Array:
	var rec: Dictionary = _pair(a, b)
	if rec.is_empty():
		return []
	return (rec.get("history", []) as Array).duplicate()


## Public history write (e.g. disaster-aid "aid_given" so kindness feeds
## future votes). Same 24-event cap as _record.
func record_event(a: String, b: String, etype: String, by: String) -> void:
	_record(a, b, etype, by)


func _decayed(e: Dictionary) -> float:
	var age: float = maxf(0.0,
		_gs.game_time - float(e.get("game_time", 0.0)))
	return pow(0.5, age / HISTORY_HALFLIFE)


func _event_weight_from_view(etype: String, by: String, viewer: String,
		other: String) -> float:
	var base: float = float(EVENT_WEIGHT.get(etype, 0.0))
	match etype:
		"war_declared", "treaty_broken", "tribute_demanded", \
				"alliance_refused":
			return base if by == other else 0.0
		"tribute_refused":
			# The demander resents the refuser.
			return base if by == other else 0.0
		"tribute_paid":
			# The receiver warms to the payer.
			return base if by == other else 0.0
		_:
			return base  # alliance/trade/peace warm both sides


func _add_morale(faction: String, delta: float) -> void:
	_morale[faction] = clampf(float(_morale.get(faction, 70.0)) + delta,
		0.0, 100.0)


## Lane 2 (war counsel, Jeremy 2026-10-06): public morale nudge. The AI
## director's war-exhaustion tick uses this — losing wars grind morale
## down faster than the diplomacy war-weariness baseline.
func adjust_morale(faction: String, delta: float) -> void:
	_add_morale(faction, delta)


func _add_reputation(faction: String, delta: float) -> void:
	_reputation[faction] = clampf(
		float(_reputation.get(faction, 60.0)) + delta, 0.0, 100.0)


## Public reputation hit (e.g. the racist-rant scandal). Clamped 0..100.
func tarnish_reputation(faction: String, delta: float) -> void:
	_add_reputation(faction, delta)


## Daily caravan exchange for a trade deal: each side ships ~4% of its
## most-stocked resource; the receiver benefits from the improved rate.
## Trade stances (HTML FACTION_SOUL) apply here:
## - bully (ogre): 1.3x in their favor unless the partner shows strength
##   (military parity), then fair.
## - haggler (gnome): +10% both ways on active deals (loves the haggle).
## - steady (human) / principled (elf): no rate distortion.
func _trade_exchange(a: String, b: String) -> void:
	var mult := trade_multiplier(a, b)
	# Policies: the player's government trade bonus (HTML trade parity).
	var pf: String = _gs.player_faction
	if (a == pf or b == pf) and _gs.get("court_sys") != null \
			and _gs.court_sys.get("policies") != null:
		mult *= _gs.court_sys.policies.trade_mult()
	# Per-side stance multipliers (asymmetric for bullies).
	var mult_a := mult  # what a receives
	var mult_b := mult  # what b receives
	var stance_a: String = SimFactions.soul_trade_stance(a)
	var stance_b: String = SimFactions.soul_trade_stance(b)
	if stance_a == "haggler" or stance_b == "haggler":
		mult_a *= 1.1
		mult_b *= 1.1
	# Bully: 1.3x in their favor unless the partner shows strength.
	var str_a := military_strength(a)
	var str_b := military_strength(b)
	if stance_a == "bully" and str_a > str_b:
		mult_a *= 1.3
	if stance_b == "bully" and str_b > str_a:
		mult_b *= 1.3
	var ra := _top_resource(a, "")
	var rb := _top_resource(b, ra)
	if ra != "":
		var give_a: float = minf(8.0,
			_gs.resources.get_amount(a, ra) * 0.04)
		if give_a >= 1.0:
			_gs.resources.add_resource(a, ra, -give_a)
			_gs.resources.add_resource(b, ra, give_a * mult_b)
	if rb != "" and rb != ra:
		var give_b: float = minf(8.0,
			_gs.resources.get_amount(b, rb) * 0.04)
		if give_b >= 1.0:
			_gs.resources.add_resource(b, rb, -give_b)
			_gs.resources.add_resource(a, rb, give_b * mult_a)


func _top_resource(faction: String, avoid: String) -> String:
	var best := ""
	var best_amt := 0.0
	for r: String in Config.RESOURCES:
		if r == avoid:
			continue
		var amt: float = _gs.resources.get_amount(faction, r)
		if amt > best_amt:
			best_amt = amt
			best = r
	return best


func _report(headline: String, body: String, kind: String) -> void:
	if court != null and court.has_method("publish_story"):
		court.publish_story(headline, body, kind)


func _fname(faction: String) -> String:
	var d: Dictionary = Config.FACTIONS.get(faction, {})
	var n := String(d.get("name", ""))
	return n if n != "" else faction.capitalize()


## Jeremy 2026-10-07 (wake audio lane): hall position for the
## war-declaration horn — the threatened side's hall anchors the stinger.
func _hall_pos(faction: String) -> Vector2:
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) == "town_hall" \
				and String(b.get("faction", "")) == faction \
				and b.get("alive", false):
			return b.get("position", Vector2.ZERO)
	return Vector2.ZERO


## --- ruler reactions (HTML rulerReactTo) --------------------------------------
##
## When the player takes major actions (tax, festival, war, etc.), AI rulers
## react with personality-appropriate voice lines. Each faction's canonical
## FACTION_SOUL voice drives the tone: ogres bellow, elves wax poetic,
## gnomes swear, humans stay dry.

var _react_seen := {}  # "event:faction:day" -> true (dedupe)


## Called when the player takes a major action. Event types: tax, anarchy,
## guard, curfew, borders, government, festival, war, peace, ally, trade.
## Data carries event-specific fields (e.g. {"value": 25} for tax).
func ruler_react_to(event: String, data: Dictionary = {}) -> void:
	var day := _gs.day_number
	var pf: String = _gs.player_faction
	# Pick 1-2 random AI factions to react.
	var candidates: Array[String] = []
	for f: String in _gs.active_factions:
		if f == pf:
			continue
		# War/peace about THEM: they always answer.
		var target_faction: String = String(data.get("faction", ""))
		if target_faction != "" and f != target_faction:
			continue
		var dk := "%s:%s:%d" % [event, f, day]
		if _react_seen.has(dk):
			continue
		if randf() < 0.6:
			candidates.append(f)
		if candidates.size() >= 2:
			break
	# Guarantee at least one voice from the affected faction.
	var target: String = String(data.get("faction", ""))
	if candidates.is_empty() and target != "" and target != pf:
		var dk2 := "%s:%s:%d" % [event, target, day]
		if not _react_seen.has(dk2) and target in _gs.active_factions:
			candidates.append(target)
	for f: String in candidates:
		var dk3 := "%s:%s:%d" % [event, f, day]
		_react_seen[dk3] = true
		# Prune dedupe dict if it grows too large (HTML: 400 cap).
		if _react_seen.size() > 400:
			_react_seen.clear()
		_ruler_react_one(f, event, data)


## One ruler's reaction to a player action. Applies diplomacy score
## adjustments and publishes the voice line as a story.
func _ruler_react_one(faction: String, event: String,
		data: Dictionary) -> void:
	var ruler_name := _gs.ruler_name
	var text := ""
	var score_delta := 0.0
	if event == "tax":
		var t := int(data.get("value", 0))
		if faction == "gnomes":
			if t >= 25:
				text = "A %d%% tax?! Piss me, %s, even WE don't rob our own people that hard. Respect. (Horror. Both.)" % [t, ruler_name]
			elif t == 0:
				text = "Zero tax? Anarchy with extra steps. Bold. Stupid. I love it."
			else:
				text = "Meh, %d%%. Could be worse. Could be OGRE taxes. (Ogres don't have taxes. Ogres have 'give me that'.)" % t
			score_delta = -6.0 if t >= 25 else 2.0
		elif faction == "humans":
			if t >= 25:
				text = "%s, a %d%% tax will breed resentment. Mark my words — I've seen it." % [ruler_name, t]
			else:
				text = "A %d%% tax. Sensible. Boring. Sensible." % t
			score_delta = -5.0 if t >= 25 else 1.0
		elif faction == "elves":
			if t >= 25:
				text = "Oh, %s. %d%%? The petals of your people's patience are falling." % [ruler_name, t]
			else:
				text = "A gentle %d%%. The forest approves of moderation." % t
			score_delta = -5.0 if t >= 25 else 2.0
		else:  # ogres, undead
			if t >= 25:
				text = "WOW! %d%% TAX! ME LIKE! ME TAKE 100%%! (me take everything. me ogre.)" % t
			else:
				text = "ONLY %d%%? ME WOULD TAKE MORE! YOU SOFT, %s! (me like soft. soft kings share food.)" % [t, ruler_name]
			score_delta = 4.0 if t >= 25 else -2.0
	elif event == "anarchy":
		if faction == "gnomes":
			text = "ANARCHY?! HA! Finally, a government I understand! No rules! (There are still rules. I make them. Shh.)"
			score_delta = 8.0
		elif faction == "ogres":
			text = "ANARCHY!! ME LOVE ANARCHY! NO RULES! ...wait. me confused. who me smash now?"
			score_delta = 6.0
		elif faction == "elves":
			text = "%s... anarchy? The stars just facepalmed. All of them." % ruler_name
			score_delta = -10.0
		else:
			text = "Anarchy, %s. Bold. Terrifying. I'll stock the granaries and bar the gates." % ruler_name
			score_delta = -8.0
	elif event == "festival":
		if faction == "ogres":
			text = "FESTIVAL!! ME LOVE FESTIVAL! ME BRING APPETITE! (me bring BIG appetite.)"
			score_delta = 10.0
		elif faction == "elves":
			text = "A festival! Music, light, joy! We shall send dancers, %s. The good ones." % ruler_name
			score_delta = 8.0
		elif faction == "gnomes":
			text = "Festival?! The mosh pit calls, %s! I've been practicing me elbows!" % ruler_name
			score_delta = 8.0
		else:
			text = "A festival, %s. Good. People need joy the way fields need rain." % ruler_name
			score_delta = 5.0
	elif event == "war":
		var target_f: String = String(data.get("faction", ""))
		if faction == "ogres":
			text = "WAR?!?! ME LOVE WAR! WAIT — war with US?! ME UNLOVE WAR! ME SMASH YOU, %s!" % ruler_name
		elif faction == "elves":
			text = "So it is war, %s. How disappointing. Our arrows fly straighter than your reasons." % ruler_name
		elif faction == "gnomes":
			text = "WAR?! Against US?! You magnificent suicidal bastard, %s! Alright — torches, pitchforks, the WORKS." % ruler_name
		else:
			text = "War, then. We didn't want it, %s, but we're ready." % ruler_name
		score_delta = -15.0
		# Ogres respect strength: if you outnumber them, they back down a notch.
		if faction == "ogres":
			var my_army := military_strength(_gs.player_faction)
			var their_army := military_strength(faction)
			if my_army >= their_army * 1.5 and their_army > 0.0:
				text += " ...ME COUNT AGAIN. YOU HAVE MANY. OKAY. ME RESPECT THAT. (me still smash, but respectfully.)"
				score_delta = -6.0
	elif event == "peace" or event == "ally" or event == "trade":
		text = SimFactions.soul_say(faction, "praise", {"name": ruler_name})
		if event == "peace":
			text += " Peace. Finally. My war-chief is sulking but he'll live."
		elif event == "ally":
			if faction == "ogres":
				text += " Allies! ME HUG YOU! (gently. me learned gentle.)"
			else:
				text += " Allies! A fine day for both our peoples."
		else:
			text += " Trade flows. Gold is just frozen goodwill, %s." % ruler_name
		score_delta = 8.0
	elif event == "curfew":
		var on := bool(data.get("on", false))
		if faction == "ogres":
			text = "CURFEW?! ME LOVE NIGHT! NIGHT IS FOR SNACKING!" if on else "NO CURFEW! NIGHT SNACKING RESTORED! ME HAPPY!"
		elif faction == "elves":
			text = "A curfew... the owls disapprove, %s. So do I." % ruler_name if on else "The night is free again. The owls rejoice."
		elif faction == "gnomes":
			text = "Curfew?! But the BEST crimes happen after dark! ...I mean. Terrible. Simply terrible." if on else "Curfew lifted! The night markets reopen! (Totally legitimate night markets.)"
		else:
			text = "Curfew's a hard decree, %s. Hope it's worth the grumbling." % ruler_name if on else "Sensible. People sleep better without soldiers at their doors."
		score_delta = -2.0 if on else 2.0
	elif event == "borders":
		var open := bool(data.get("open", true))
		if faction == "ogres":
			text = "BORDERS OPEN! ME COME TRADE! (me also come look at your shiny things.)" if open else "BORDERS CLOSED?! ME SAD! ME WANTED TO SEE YOUR SHINY THINGS!"
		elif faction == "elves":
			text = "Open roads, open hearts. A lovely decree, %s." % ruler_name if open else "Closed gates... the forest understands caution. It does not applaud it."
		elif faction == "gnomes":
			text = "Open borders! The smugglers rejoice! I mean — the TRADERS. The totally legal traders." if open else "Closed borders? Coward's move. (Says the gnome who locks his own door twice.)"
		else:
			text = "Open borders, %s. Our caravans will roll. Good for us both." % ruler_name if open else "Closed. Hm. We'll manage — we always do."
		score_delta = 3.0 if open else -3.0
	if text != "":
		# Don't touch the score of a pair at war (war sets a fixed -80).
		var pf: String = _gs.player_faction
		if not (event == "war" \
				and relation_state(faction, pf) == "war"):
			_adjust_relation_score(faction, pf, score_delta)
		_report("%s of the %s reacts" % [_fname(faction), _fname(faction)],
			text, "diplomacy")


## Adjust the relation score between two factions (for ruler reactions).
func _adjust_relation_score(a: String, b: String, delta: float) -> void:
	var rec := _pair(a, b)
	if rec.is_empty():
		return
	rec["score"] = float(rec.get("score", 0.0)) + delta


## --- third-party war reactions (2026-10-05) ----------------------------------
##
## Checklist item: "War/peace responses: factions react to declarations".
## ruler_react_to only fires when the PLAYER declares or receives war — the
## rest of the world stayed silent when two AI factions went at it. Now every
## third-party faction answers a declaration according to where it stands:
##   - allied with the victim: stands by them — condemns the aggressor hard.
##     (The daily _ai_consider alliance-obligation roll may still drag them
##     into the war the honest way — no instant dogpile here.)
##   - allied with the aggressor: stands by their ally — cold shoulder to
##     the victim.
##   - warm toward the victim (score >= 25): condemns the aggressor.
##   - cold toward the victim (score <= -25): quietly cheers the aggressor
##     (the enemy of my enemy).
##   - neutral: frets about the trade roads (voice only, no score shift).
## Reactions are voiced on the same "diplomacy" story channel as ruler
## reactions, deduped once per war per faction ("warnews:a:b:c:warsince" in
## _react_seen), and never nudge a pair currently at war (war pins -80).
## The player is not excluded: when the player's wars draw the world's
## judgment, third parties condemn or cheer the player too — the score
## moves, but the crown speaks through the UI, not auto-lines.


## Every third party answers a war declaration between a and b.
func _third_party_war_reactions(a: String, b: String) -> void:
	var rec := _pair(a, b)
	var war_day := int(rec.get("war_since_day", _gs.day_number))
	var pf: String = _gs.player_faction
	for c: String in _gs.active_factions:
		if c == a or c == b:
			continue
		var dk := "warnews:%s:%s:%s:%d" % [a, b, c, war_day]
		if _react_seen.has(dk):
			continue
		_react_seen[dk] = true
		if _react_seen.size() > 400:
			_react_seen.clear()
		var text := ""
		var score_delta := 0.0
		var score_b := a  # default: judge the aggressor
		if relation_state(c, b) == "allied":
			text = _war_news_line(c, "stand_victim", a, b)
			score_delta = -12.0
		elif relation_state(c, a) == "allied":
			text = _war_news_line(c, "stand_aggressor", a, b)
			score_delta = -10.0
			score_b = b
		elif relation_score(c, b) >= 25.0:
			text = _war_news_line(c, "condemn", a, b)
			score_delta = -8.0
		elif relation_score(c, b) <= -25.0:
			text = _war_news_line(c, "cheer", a, b)
			score_delta = 6.0
		elif randf() < 0.5:
			text = _war_news_line(c, "fret", a, b)
		if text == "" and score_delta == 0.0:
			continue
		# Never nudge a pair currently at war (war pins score at -80).
		if score_delta != 0.0 and relation_state(c, score_b) != "war":
			_adjust_relation_score(c, score_b, score_delta)
		if c == pf or text == "":
			continue  # the crown speaks through the UI, not auto-lines
		_report("%s of the %s reacts" % [_fname(c), _fname(c)],
			text, "diplomacy")


## One faction's voiced line about a war between a (aggressor) and
## b (victim). Stances: stand_victim, stand_aggressor, condemn, cheer, fret.
func _war_news_line(c: String, stance: String, a: String, b: String) -> String:
	var an := _fname(a)
	var bn := _fname(b)
	if stance == "stand_victim":
		if c == "ogres":
			return "OUR ALLIES THE %s ARE ATTACKED! %s WILL LEARN WHAT ME FISTS ARE FOR! (me fists are for smashing.)" % [bn.to_upper(), an.to_upper()]
		if c == "gnomes":
			return "%s picked a fight with our mates the %s?! WRONG MOVE, ya festering war-drums! We're coming!" % [an, bn]
		if c == "elves":
			return "The %s raise blades against our %s friends. The stars dim at such treachery — our bows will answer." % [an, bn]
		if c == "humans":
			return "%s attacked our allies, the %s. That was... unwise. Very unwise." % [an, bn]
		return "The %s strike at our %s allies. The grave remembers every slight. So do we." % [an, bn]
	if stance == "stand_aggressor":
		if c == "ogres":
			return "%s ARE OUR ALLIES! %s HAD IT COMING! (me don't know what coming means. me still smash.)" % [an.to_upper(), bn.to_upper()]
		if c == "gnomes":
			return "Our allies the %s are at war with the %s, eh? About bloody time someone sorted them out." % [an, bn]
		if c == "elves":
			return "We stand with our %s allies. The %s brought this storm on themselves — let it rain." % [an, bn]
		if c == "humans":
			return "The %s are our allies, so the %s are our problem now. Pity. They seemed nice." % [an, bn]
		return "Our %s allies march on the %s. We do not question the tide. We drown with it." % [an, bn]
	if stance == "condemn":
		if c == "ogres":
			return "%s ATTACK %s?! ME ANGRY! %s ARE GOOD! %s ARE... ME FORGOT WORD. BAD! BAD IS WORD!" % [an.to_upper(), bn.to_upper(), bn.to_upper(), an.to_upper()]
		if c == "gnomes":
			return "Oi! %s! Hands off the %s, ya warmongering tossers! We're watching you!" % [an, bn]
		if c == "elves":
			return "The %s bare fangs at the %s. Such ugliness — the forest will remember this." % [an, bn]
		if c == "humans":
			return "Condemnation, in the strongest terms: the %s attacking the %s is deplorable. (There. Condemned.)" % [an, bn]
		return "The %s chose war with the %s. Even the dead find that... distasteful." % [an, bn]
	if stance == "cheer":
		if c == "ogres":
			return "%s SMASH %s! ME LIKE THIS NEWS! ME BRING POPCORN! (what is popcorn. me bring rocks.)" % [an.to_upper(), bn.to_upper()]
		if c == "gnomes":
			return "The %s are battering the %s?! HA! Pass the ale — this is the best show in years!" % [an, bn]
		if c == "elves":
			return "The %s move against the %s. We shall not weep. We may, in fact, hum." % [an, bn]
		if c == "humans":
			return "The %s versus the %s. Finally, someone else's problem. Wonderful." % [an, bn]
		return "The %s bleed the %s. How... nourishing. Do continue." % [an, bn]
	# fret
	if c == "ogres":
		return "WAR! %s VS %s! ME CONFUSED! WHO ME SMASH?! (me smash whoever closer.)" % [an.to_upper(), bn.to_upper()]
	if c == "gnomes":
		return "%s and the %s at each other's throats? There goes the neighborhood. And me trade routes." % [an, bn]
	if c == "elves":
		return "War between %s and %s... the wind carries ash again. It always does." % [an, bn]
	if c == "humans":
		return "The %s and %s are at war. I've moved the good silverware away from the border. Just in case." % [an, bn]
	return "%s and %s bleed each other. The soil grows richer. We wait." % [an, bn]


## --- save/load (Milestone 7) ------------------------------------------------

func to_dict() -> Dictionary:
	var pairs := {}
	for key: String in _pairs.keys():
		var rec: Dictionary = _pairs[key]
		pairs[key] = {
			"a": String(rec["a"]),
			"b": String(rec["b"]),
			"state": String(rec.get("state", "neutral")),
			"score": float(rec.get("score", 0.0)),
			"trade_active": bool(rec.get("trade_active", false)),
			"trade_until_day": int(rec.get("trade_until_day", 0)),
			"war_since_day": int(rec.get("war_since_day", 0)),
			"allied_since_day": int(rec.get("allied_since_day", 0)),
			"betrayal_cooldown_until": int(rec.get("betrayal_cooldown_until", 0)),
			"history": (rec.get("history", []) as Array).duplicate(true),
		}
	return {
		"pairs": pairs,
		"morale": _morale.duplicate(),
		"reputation": _reputation.duplicate(),
		"truces": _truces.duplicate(),
		"surrender_offers": _surrender_offers.duplicate(true),
		"surrender_seq": _surrender_seq,
		"surrender_done": _surrender_done.duplicate(),
		"aid_requests": _aid_requests.duplicate(true),
		"aid_seq": _aid_seq,
	}


func from_dict(data: Dictionary) -> void:
	_pairs.clear()
	_morale.clear()
	_reputation.clear()
	for key: String in (data.get("pairs", {}) as Dictionary).keys():
		var src: Dictionary = (data["pairs"] as Dictionary)[key]
		_pairs[String(key)] = {
			"a": String(src.get("a", "")),
			"b": String(src.get("b", "")),
			"state": String(src.get("state", "neutral")),
			"score": float(src.get("score", 0.0)),
			"trade_active": bool(src.get("trade_active", false)),
			"trade_until_day": int(src.get("trade_until_day", 0)),
			"war_since_day": int(src.get("war_since_day", 0)),
			"allied_since_day": int(src.get("allied_since_day", 0)),
			"betrayal_cooldown_until": int(src.get("betrayal_cooldown_until", 0)),
			"history": (src.get("history", []) as Array).duplicate(true),
		}
	for f: String in (data.get("morale", {}) as Dictionary).keys():
		_morale[f] = float((data["morale"] as Dictionary)[f])
	for f: String in (data.get("reputation", {}) as Dictionary).keys():
		_reputation[f] = float((data["reputation"] as Dictionary)[f])
	relation_version += 1  # R23: wholesale pair replace invalidates hostile-set cache
	_truces.clear()
	for key: String in (data.get("truces", {}) as Dictionary).keys():
		_truces[key] = int((data["truces"] as Dictionary)[key])
	_surrender_offers.clear()
	for oid: String in (data.get("surrender_offers", {}) as Dictionary).keys():
		_surrender_offers[oid] = ((data["surrender_offers"] as Dictionary)[oid] as Dictionary).duplicate(true)
	_surrender_seq = int(data.get("surrender_seq", 0))
	_surrender_done.clear()
	for k: String in (data.get("surrender_done", {}) as Dictionary).keys():
		_surrender_done[String(k)] = int((data["surrender_done"] as Dictionary)[k])
	_aid_requests.clear()
	for aid_id: String in (data.get("aid_requests", {}) as Dictionary).keys():
		_aid_requests[aid_id] = ((data["aid_requests"] as Dictionary)[aid_id] as Dictionary).duplicate(true)
	_aid_seq = int(data.get("aid_seq", 0))
	_last_day = _gs.day_number if _gs.day_number >= 1 else 1
