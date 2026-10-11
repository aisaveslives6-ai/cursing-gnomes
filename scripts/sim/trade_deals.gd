class_name SimTradeDeals
extends RefCounted
## Cursing Gnomes — faction trade deals (Jeremy 2026-10-11).
##
## Jeremy proposes resource trades to other factions from the phone:
## offer {resource: amount} and request {resource: amount} in return.
## The target AI evaluates (war status, relations, fairness, surplus/need)
## and accepts, counters, or refuses — with voiced dialogue in the leader's
## own voice. Accepted deals execute one-time ("once") or per-day for N days
## ("daily"). Every deal is logged; the Treasury advisor tracks the ledger
## and can auto-manage deals when Jeremy tells it to.
##
## Pure logic + data — no rendering, no input, no audio, no network.
## Day tick via bus.day_changed (like SimPetitions).

## Trade value per unit (relative to gold) for fairness math.
const TRADE_VALUES := {
	"gold": 1.0, "wood": 0.6, "food": 0.5,
	"oil": 1.4, "seeds": 0.35, "soul_essence": 2.0,
}
## Treasury reserve floors the auto-manager will never trade below.
const RESERVE_FLOOR := {"gold": 200.0, "wood": 150.0, "food": 150.0,
	"oil": 80.0, "seeds": 60.0, "soul_essence": 20.0}
## Below this stockpile a faction is "in need" of the resource.
const NEED_LINE := 60.0
## Above this stockpile a faction has "surplus" to trade away.
const SURPLUS_LINE := 300.0

var _gs = null
var _deals: Array = []
var _next_id: int = 1
## Jeremy told the Treasury advisor "handle my trades".
var auto_manage: bool = false
var _auto_day: int = -1


func _init(gs) -> void:
	_gs = gs
	if _gs != null:
		var bus = _gs.get("bus")
		if bus != null and bus.has_signal("day_changed"):
			bus.day_changed.connect(_on_day)


static func deal_modes() -> Array[String]:
	return ["once", "daily"]


static func res_value(res: String) -> float:
	return float(TRADE_VALUES.get(res, 0.5))


static func bundle_value(bundle: Dictionary) -> float:
	var v := 0.0
	for r: String in bundle:
		v += float(bundle[r]) * res_value(r)
	return v


func _fname(faction: String) -> String:
	var d: Dictionary = Config.FACTIONS.get(faction, {})
	var n := String(d.get("name", ""))
	return n if n != "" else faction.capitalize()


func _voice(faction: String) -> String:
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return "diplomatic"
	var l: Dictionary = fl.leader_of(faction)
	return String(l.get("voice", "diplomatic"))


func _lname(faction: String) -> String:
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return _fname(faction)
	var l: Dictionary = fl.leader_of(faction)
	var n := String(l.get("name", ""))
	return n if n != "" else _fname(faction)


## --- proposal flow ----------------------------------------------------------

## Full player/advisor proposal: validate -> AI evaluate -> execute/counter/refuse.
## Returns {ok, verdict: "accept"|"counter"|"refuse"|"invalid", deal, msg}.
func propose(proposer: String, target: String, offer: Dictionary,
		request: Dictionary, mode: String = "once", days: int = 1,
		by_advisor: bool = false) -> Dictionary:
	var bad := _validate(proposer, target, offer, request, mode, days)
	if bad != "":
		return {"ok": false, "verdict": "invalid", "deal": {},
			"msg": bad}
	var ev: Dictionary = ai_evaluate(proposer, target, offer, request)
	var verdict := String(ev.get("verdict", "refuse"))
	if verdict == "accept":
		var deal := _sign(proposer, target, offer, request, mode, days,
			by_advisor)
		_execute(deal)
		return {"ok": true, "verdict": "accept", "deal": deal,
			"msg": String(ev.get("line", ""))}
	if verdict == "counter":
		var deal := _sign_countered(proposer, target, offer, request,
			Dictionary(ev.get("counter_offer", {})),
			Dictionary(ev.get("counter_request", {})), mode, days, by_advisor)
		return {"ok": true, "verdict": "counter", "deal": deal,
			"msg": String(ev.get("line", ""))}
	# Refused: small relations sting.
	_gs.diplomacy.adjust_score(proposer, target, -3.0)
	return {"ok": true, "verdict": "refuse", "deal": {},
		"msg": String(ev.get("line", ""))}


func _validate(proposer: String, target: String, offer: Dictionary,
		request: Dictionary, mode: String, days: int) -> String:
	if proposer == "" or target == "" or proposer == target:
		return "A deal needs two different factions."
	if not (target in _gs.active_factions) \
			or not (proposer in _gs.active_factions):
		return "Unknown faction in this deal."
	if mode not in ["once", "daily"]:
		return "Deals are one-time or daily — nothing else."
	if int(days) < 1:
		return "A deal has to last at least a day."
	if offer.is_empty() or request.is_empty():
		return "Offer something and ask for something — both sides of the ledger."
	for r: String in offer:
		if not (r in Config.RESOURCES) or float(offer[r]) <= 0.0:
			return "That's not a tradable offer."
	for r: String in request:
		if not (r in Config.RESOURCES) or float(request[r]) <= 0.0:
			return "That's not a tradable request."
	# Proposer must actually hold what they offer (with buffer for dailies).
	var mult := float(maxi(1, days)) if mode == "daily" else 1.0
	for r: String in offer:
		var have: float = _gs.resources.get_amount(proposer, r)
		if have < float(offer[r]) * mult:
			return "You don't hold %s %s to offer." \
				% [_fmt_amt(float(offer[r]) * mult), r]
	return ""


## AI evaluation. Returns {verdict, counter_offer, counter_request, line}.
func ai_evaluate(proposer: String, target: String, offer: Dictionary,
		request: Dictionary) -> Dictionary:
	var voice := _voice(target)
	# War: never. Characterful refusal.
	if _gs.diplomacy.relation_state(proposer, target) == "war":
		return {"verdict": "refuse", "line": _war_refusal(voice, proposer)}
	# Deep hatred: no deal.
	var rel: float = _gs.diplomacy.relation_score(proposer, target)
	if rel < -30.0:
		return {"verdict": "refuse",
			"line": _refusal(voice, target, "cold shoulder")}
	# Can the target actually deliver? (Buffer: they keep 20%.)
	for r: String in request:
		var have: float = _gs.resources.get_amount(target, r)
		if have < float(request[r]) * 1.2:
			# Counter with what they CAN spare, if anything meaningful.
			var can: float = maxf(0.0, have * 0.5)
			if can >= 5.0:
				var cr := {r: snappedf(can, 1.0)}
				return {"verdict": "counter", "counter_offer": offer,
					"counter_request": cr,
					"line": _counter_line(voice, target, r, can)}
			return {"verdict": "refuse",
				"line": _refusal(voice, target, "empty stores")}
	# Fairness of the trade.
	var give_v := bundle_value(offer)
	var want_v := bundle_value(request)
	var fair := give_v / maxf(0.01, want_v)
	# Need shifts the bar: if they NEED what we offer, they take worse odds.
	var needy := false
	for r: String in offer:
		if _gs.resources.get_amount(target, r) < NEED_LINE:
			needy = true
			break
	var accept_bar := 0.8 if needy else 1.0
	var stance := SimFactions.soul_trade_stance(target)
	if stance == "haggler":
		accept_bar += 0.15
	if fair >= accept_bar and rel >= -10.0:
		_gs.diplomacy.adjust_score(proposer, target, 2.0)
		return {"verdict": "accept", "line": _accept_line(voice, target)}
	if fair >= 0.45:
		# Counter: scale their ask until the deal is fair at ~1.0.
		var scale := clampf(1.0 / maxf(0.01, fair), 1.0, 2.5)
		var cr2 := {}
		for r: String in request:
			cr2[r] = snappedf(float(request[r]) * scale, 1.0)
		return {"verdict": "counter", "counter_offer": offer,
			"counter_request": cr2,
			"line": _counter_line(voice, target, "", 0.0)}
	return {"verdict": "refuse", "line": _refusal(voice, target, "insult")}


## Accept a countered deal's terms (creates the active deal).
func accept_counter(deal_id: int) -> Dictionary:
	var d := get_deal(deal_id)
	if d.is_empty():
		return {"ok": false, "msg": "No such deal."}
	if String(d.get("status", "")) != "countered":
		return {"ok": false, "msg": "That deal isn't awaiting an answer."}
	d["offer"] = d["counter_offer"]
	d["request"] = d["counter_request"]
	d["status"] = "active"
	_gs.diplomacy.adjust_score(String(d["proposer"]), String(d["target"]), 2.0)
	_execute(d)
	return {"ok": true, "msg": "Counter accepted — %s." % deal_summary(d)}


## Decline a countered deal.
func decline_counter(deal_id: int) -> Dictionary:
	var d := get_deal(deal_id)
	if d.is_empty():
		return {"ok": false, "msg": "No such deal."}
	if String(d.get("status", "")) != "countered":
		return {"ok": false, "msg": "That deal isn't awaiting an answer."}
	d["status"] = "refused"
	return {"ok": true, "msg": "You walked away from the counter-offer."}


func cancel_deal(deal_id: int, by_faction: String = "") -> Dictionary:
	var d := get_deal(deal_id)
	if d.is_empty():
		return {"ok": false, "msg": "No such deal."}
	if String(d.get("status", "")) != "active":
		return {"ok": false, "msg": "That deal isn't active."}
	d["status"] = "cancelled"
	_gs.diplomacy.adjust_score(String(d["proposer"]), String(d["target"]), -2.0)
	return {"ok": true, "msg": "Deal cancelled: %s" % deal_summary(d)}


## --- execution ---------------------------------------------------------------

func _sign(proposer: String, target: String, offer: Dictionary,
		request: Dictionary, mode: String, days: int,
		by_advisor: bool) -> Dictionary:
	var d := {
		"id": _next_id, "proposer": proposer, "target": target,
		"offer": offer.duplicate(), "request": request.duplicate(),
		"mode": mode, "days": maxi(1, days), "days_left": maxi(1, days),
		"status": "active", "day_signed": _gs.day_number,
		"by_advisor": by_advisor,
	}
	_next_id += 1
	_deals.append(d)
	_announce(d, true)
	return d


func _sign_countered(proposer: String, target: String, offer: Dictionary,
		request: Dictionary, counter_offer: Dictionary,
		counter_request: Dictionary, mode: String, days: int,
		by_advisor: bool) -> Dictionary:
	var d := {
		"id": _next_id, "proposer": proposer, "target": target,
		"offer": offer.duplicate(), "request": request.duplicate(),
		"counter_offer": counter_offer.duplicate(),
		"counter_request": counter_request.duplicate(),
		"mode": mode, "days": maxi(1, days), "days_left": maxi(1, days),
		"status": "countered", "day_signed": _gs.day_number,
		"by_advisor": by_advisor,
	}
	_next_id += 1
	_deals.append(d)
	return d


## Move resources for one execution leg of a deal.
func _execute(d: Dictionary) -> void:
	_transfer(String(d["proposer"]), String(d["target"]),
		Dictionary(d["offer"]))
	_transfer(String(d["target"]), String(d["proposer"]),
		Dictionary(d["request"]))
	if String(d["mode"]) == "once":
		d["status"] = "completed"
	else:
		d["days_left"] = int(d["days_left"]) - 1
		if int(d["days_left"]) <= 0:
			d["status"] = "completed"


func _transfer(from_f: String, to_f: String, bundle: Dictionary) -> void:
	for r: String in bundle:
		var amt := float(bundle[r])
		_gs.resources.add_resource(from_f, r, -amt)
		_gs.resources.add_resource(to_f, r, amt)


func _announce(d: Dictionary, first: bool) -> void:
	var pf: String = _gs.player_faction
	if d["proposer"] != pf and d["target"] != pf:
		return
	var other := String(d["target"] if d["proposer"] == pf else d["proposer"])
	var dir := "with" if d["proposer"] == pf else "from"
	var court = _gs.get("court_sys")
	if court != null and court.has_method("publish_story"):
		court.publish_story("TRADE DEAL SIGNED",
			"Day %d: %s %s %s — %s." % [_gs.day_number,
				_fname(String(d["proposer"])), dir, _fname(other),
				deal_summary(d)], "trade")


func _on_day(_day_number: int, _is_night: bool) -> void:
	# Daily legs of active daily deals.
	for d: Dictionary in _deals:
		if String(d.get("status", "")) == "active" \
				and String(d.get("mode", "")) == "daily":
			# If either side went to war mid-deal, the caravans stop.
			if _gs.diplomacy.relation_state(String(d["proposer"]),
					String(d["target"])) == "war":
				d["status"] = "cancelled"
				continue
			_execute(d)
	if auto_manage:
		auto_manage_tick()


## --- ledger -------------------------------------------------------------------

func get_deal(deal_id: int) -> Dictionary:
	for d: Dictionary in _deals:
		if int(d.get("id", 0)) == deal_id:
			return d
	return {}


func ledger(faction: String) -> Array:
	var out: Array = []
	for d: Dictionary in _deals:
		if d["proposer"] == faction or d["target"] == faction:
			out.append(d)
	return out


func active_deals_for(faction: String) -> Array:
	var out: Array = []
	for d: Dictionary in _deals:
		if String(d.get("status", "")) == "active" \
				and (d["proposer"] == faction or d["target"] == faction):
			out.append(d)
	return out


static func _fmt_amt(a: float) -> String:
	return str(int(round(a)))


static func _bundle_text(bundle: Dictionary) -> String:
	var parts: Array[String] = []
	for r: String in bundle:
		parts.append("%s %s" % [_fmt_amt(float(bundle[r])), r])
	return ", ".join(parts)


func deal_summary(d: Dictionary) -> String:
	var pf: String = _gs.player_faction
	var other := String(d["target"] if d["proposer"] == pf else d["proposer"])
	var give: Dictionary = d["offer"] if d["proposer"] == pf else d["request"]
	var get: Dictionary = d["request"] if d["proposer"] == pf else d["offer"]
	var s := "give %s, get %s (%s)" % [_bundle_text(give),
		_bundle_text(get), _fname(other)]
	if String(d.get("mode", "once")) == "daily":
		s += " daily x%d" % int(d.get("days", 1))
	return s


func ledger_text(faction: String) -> String:
	var rows := ledger(faction)
	if rows.is_empty():
		return "No trade deals on the books."
	var lines: Array[String] = []
	for d: Dictionary in rows:
		lines.append("#%d [%s] %s" % [int(d["id"]),
			String(d.get("status", "")), deal_summary(d)])
	return "\n".join(lines)


## --- Treasury advisor: reporting, advice, auto-manage --------------------------

## Full status report for "how are my deals doing?"
func treasury_report(faction: String) -> String:
	var rows := ledger(faction)
	if rows.is_empty():
		return "The ledger is empty, boss. No deals signed, none running, none owed. Your gold sits at %sg — lonely, but safe." \
			% _fmt_amt(_gs.resources.get_amount(faction, "gold"))
	var active := 0
	var completed := 0
	var gave_v := 0.0
	var got_v := 0.0
	for d: Dictionary in rows:
		var st := String(d.get("status", ""))
		if st == "active":
			active += 1
		elif st == "completed":
			completed += 1
		var legs := float(maxi(1, int(d.get("days", 1)))) \
			if String(d.get("mode", "")) == "daily" else 1.0
		if d["proposer"] == faction:
			gave_v += bundle_value(Dictionary(d["offer"])) * legs
			got_v += bundle_value(Dictionary(d["request"])) * legs
		else:
			gave_v += bundle_value(Dictionary(d["request"])) * legs
			got_v += bundle_value(Dictionary(d["offer"])) * legs
	var verdict := "We're up on trade. Beautiful."
	if got_v < gave_v * 0.95:
		verdict = "We're bleeding value on these deals. I'll be having words."
	elif absf(got_v - gave_v) <= gave_v * 0.05:
		verdict = "About break-even. Coin for coin."
	return "%d active, %d completed. Lifetime: gave %dv worth, got %dv worth. %s Gold on hand: %sg." \
		% [active, completed, int(gave_v), int(got_v), verdict,
			_fmt_amt(_gs.resources.get_amount(faction, "gold"))]


## "What should I trade?" — grounded advice from live stockpiles + relations.
func trade_advice(faction: String) -> String:
	var lines: Array[String] = []
	for r: String in Config.RESOURCES:
		var amt: float = _gs.resources.get_amount(faction, r)
		if amt < NEED_LINE:
			lines.append("We're SHORT on %s (%s) — buy it, don't sell it." \
				% [r, _fmt_amt(amt)])
		elif amt > SURPLUS_LINE:
			lines.append("We've got %s to burn (%s) — sell the surplus." \
				% [r, _fmt_amt(amt)])
	if lines.is_empty():
		return "Stockpiles are balanced. No fires, no feasts. If you want action, pick a friendly faction and I'll find the angle."
	# Name the friendliest viable partner.
	var best := ""
	var best_rel := -100.0
	for f: String in _gs.active_factions:
		if f == faction:
			continue
		if _gs.diplomacy.relation_state(faction, f) == "war":
			continue
		var rel: float = _gs.diplomacy.relation_score(faction, f)
		if rel > best_rel:
			best_rel = rel
			best = f
	if best != "":
		lines.append("Friendliest counterparty: the %s (relations %d). Say the word and I'll draft terms." \
			% [_fname(best), int(best_rel)])
	return "\n".join(lines)


## Auto-manage: propose one sensible deal per day to a friendly faction.
## Guardrails: never with war enemies, never below reserve floors, never
## bankrupts the treasury, one auto-deal per pair at a time.
func auto_manage_tick() -> Dictionary:
	var pf: String = _gs.player_faction
	if _auto_day == _gs.day_number:
		return {"ok": false, "msg": "already ran today"}
	_auto_day = _gs.day_number
	# Our biggest surplus and our sharpest need.
	var give_res := ""
	var give_amt := 0.0
	var want_res := ""
	var want_amt := 0.0
	for r: String in Config.RESOURCES:
		var amt: float = _gs.resources.get_amount(pf, r)
		var floor: float = float(RESERVE_FLOOR.get(r, 0.0))
		if amt - floor > give_amt and amt > SURPLUS_LINE:
			give_res = r
			give_amt = amt - floor
		if amt < NEED_LINE and (want_res == "" or amt < want_amt):
			want_res = r
			want_amt = amt
	if give_res == "" or want_res == "":
		return {"ok": false, "msg": "nothing sensible to trade"}
	# Friendliest faction that holds what we want and isn't at war.
	var best := ""
	var best_rel := -100.0
	for f: String in _gs.active_factions:
		if f == pf:
			continue
		if _gs.diplomacy.relation_state(pf, f) == "war":
			continue
		if _gs.diplomacy.relation_score(pf, f) < 0.0:
			continue
		if _has_active_with(pf, f):
			continue
		if _gs.resources.get_amount(f, want_res) < 100.0:
			continue
		var rel: float = _gs.diplomacy.relation_score(pf, f)
		if rel > best_rel:
			best_rel = rel
			best = f
	if best == "":
		return {"ok": false, "msg": "no willing partner"}
	var offer := {give_res: snappedf(minf(give_amt * 0.25, 120.0), 1.0)}
	var want_qty := snappedf(minf(NEED_LINE * 2.0 - want_amt, 120.0), 1.0)
	var request := {want_res: maxf(10.0, want_qty)}
	var res: Dictionary = propose(pf, best, offer, request, "once", 1, true)
	_report_auto(res, best)
	return res


func _has_active_with(a: String, b: String) -> bool:
	for d: Dictionary in _deals:
		if String(d.get("status", "")) != "active":
			continue
		var p := String(d["proposer"])
		var t := String(d["target"])
		if (p == a and t == b) or (p == b and t == a):
			return true
	return false


func _report_auto(res: Dictionary, target: String) -> void:
	var pf: String = _gs.player_faction
	# Find the Treasury advisor's unit so the report comes from them.
	var adv_id := 0
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) == pf \
				and String(u.get("job", "")) == "advisor_economy" \
				and bool(u.get("alive", true)):
			adv_id = int(u.get("id", 0))
			break
	if adv_id == 0:
		return
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	var v := String(res.get("verdict", ""))
	var line := "I worked the %s on your standing order, boss. " % _fname(target)
	if v == "accept":
		line += "Signed: %s." % deal_summary(Dictionary(res.get("deal", {})))
	elif v == "counter":
		line += "They countered — message me 'take the counter' or 'walk away'."
	else:
		line += "They refused. %s" % String(res.get("msg", ""))
	phone.npc_message(adv_id, line)


## --- voiced lines ---------------------------------------------------------------

func _war_refusal(voice: String, proposer: String) -> String:
	match voice:
		"blunt":
			return "Trade? WE'RE AT WAR, %s. The only thing I'm sending you is an army." % _fname(proposer)
		"elegant":
			return "You ask for commerce while our banners are raised against you? The audacity is almost art. No."
		"mischievous":
			return "Ooh, trade during wartime! Sure — I'll trade you this war for... no. Come back when you're not trying to kill me."
		"cold":
			return "The dead do not haggle. Neither do we, while at war."
		_:
			return "We are at war. There will be no trade until the swords are sheathed."


func _accept_line(voice: String, target: String) -> String:
	var n := _lname(target)
	match voice:
		"blunt":
			return "%s grunts: \"Fine. Deal. Don't make me regret it.\"" % n
		"elegant":
			return "%s inclines their head: \"An equitable arrangement. It is done.\"" % n
		"mischievous":
			return "%s grins wide: \"Oh, I LIKE this one. Signed, sealed, delivered!\"" % n
		"cold":
			return "%s: \"The terms are acceptable. So it is written.\"" % n
		_:
			return "%s nods: \"A fair trade. We have a deal.\"" % n


func _counter_line(voice: String, target: String, res: String,
		amt: float) -> String:
	var n := _lname(target)
	var why := ""
	if res != "":
		why = " I can spare %s %s, no more." % [_fmt_amt(amt), res]
	match voice:
		"blunt":
			return "%s: \"Not those terms.%s Take it or leave it.\"" % [n, why]
		"elegant":
			return "%s: \"The balance is... imperfect.%s Might I suggest an adjustment?\"" % [n, why]
		"mischievous":
			return "%s winks: \"Close! But my abacus says otherwise.%s How about THIS instead?\"" % [n, why]
		"cold":
			return "%s: \"Insufficient.%s These are my terms.\"" % [n, why]
		_:
			return "%s: \"I can't do those exact terms.%s Here's my counter.\"" % [n, why]


func _refusal(voice: String, target: String, kind: String) -> String:
	var n := _lname(target)
	match kind:
		"cold shoulder":
			return "%s won't even take the meeting. The door stays shut." % n
		"empty stores":
			return "%s spreads empty hands: \"I'd love to — but the stores are bare.\"" % n
		_:
			match voice:
				"blunt":
					return "%s: \"That's robbery with extra steps. No.\"" % n
				"elegant":
					return "%s: \"A charming offer. And yet — no.\"" % n
				"mischievous":
					return "%s laughs: \"HA! Good one. No.\"" % n
				"cold":
					return "%s: \"No.\"" % n
				_:
					return "%s declines the deal." % n


## --- save / load ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"deals": _deals.duplicate(true), "next_id": _next_id,
		"auto_manage": auto_manage, "auto_day": _auto_day}


func from_dict(data: Dictionary) -> void:
	_deals = (data.get("deals", []) as Array).duplicate(true)
	_next_id = int(data.get("next_id", 1))
	auto_manage = bool(data.get("auto_manage", false))
	_auto_day = int(data.get("auto_day", -1))
