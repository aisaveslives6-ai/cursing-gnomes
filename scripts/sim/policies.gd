class_name SimPolicies
extends RefCounted
## Cursing Gnomes — Policies & Government (Milestone 6+).
##
## Faithful port of the HTML build's POLICIES logic (candidates 15/16/57):
##   - policies: tax (0-40%), anarchy flag, guard tier (none/militia/
##     professional), curfew flag, borders (open/closed), festival cooldown
##   - SEVEN GOVERNMENTS, each with real multipliers (HTML GOVERNMENTS):
##     monarchy / council / junta / theocracy / tribal / oligarchy / democracy
##   - per-town domestic approval (0-100, lazy default 60); approval < 25
##     triggers strikes (work x0.7); approval <= 15 triggers riots; democracy
##     holds elections every 30 days
##   - daily tick: tax income, guard upkeep (desertion when broke), anarchy
##     decay, open-borders trade bonus, theocracy tithe, curfew happiness
##     cost, happiness drift toward the government target
##   - festivals: instant hold + scheduled, 7-day cooldown, full-refund cancel
##   - guild hiring quotas per town (job -> target count), player-adjustable
##   - crime_pressure_mult() for the crime system; work_mult() for worker AI
##
## State is a plain Dictionary (save-ready). Pure logic — no rendering,
## no input, no audio, no network. All NPC lines are offline/scripted.

const GUARD_TIERS: Array[String] = ["none", "militia", "professional"]
const BORDER_MODES: Array[String] = ["open", "closed"]

## Laws the crown can permit or ban (Jeremy 2026-10-11, Ruler's Voice
## expansion — advisors adjust these through the phone). income = gold per
## citizen per day when permitted; happy = happiness shift on change.
const LAW_DEFS := {
	"gambling": {"label": "Gambling", "fee": 25, "income": 0.6,
		"happy": -3.0,
		"blurb": "Dice halls and card dens, licensed and taxed by the crown."},
	"alehouses": {"label": "Alehouses", "fee": 15, "income": 0.25,
		"happy": 4.0,
		"blurb": "Every town gets a proper tavern. The bards approve."},
	"dueling": {"label": "Dueling", "fee": 15, "income": 0.0,
		"happy": 2.0,
		"blurb": "Settle it with steel at dawn. Legally, this time."},
}

## The seven governments (HTML GOVERNMENTS, exact values).
const GOVERNMENTS := {
	"monarchy": {"name": "Absolute Monarchy", "icon": "👑",
		"desc": "One crown, one will. Decrees are cheap, taxes are tolerated and the guard stands tall — but the court finds festivals tedious.",
		"policyCost": 0.5, "taxEff": 1.0, "taxTol": 10, "guardUp": 0.8, "guardStr": 1.2,
		"buildCost": 1.0, "buildSpeed": 1.0, "festCost": 1.0, "festJoy": 0.7,
		"trade": 1.0, "trainCost": 1.0, "trainSpeed": 1.0, "happy": 0},
	"council": {"name": "Council Republic", "icon": "🏛",
		"desc": "Committees build cheap and citizens are content — but the army musters at the speed of debate.",
		"policyCost": 1.0, "taxEff": 1.0, "taxTol": 0, "guardUp": 1.0, "guardStr": 1.0,
		"buildCost": 0.8, "buildSpeed": 1.1, "festCost": 1.0, "festJoy": 1.0,
		"trade": 1.0, "trainCost": 1.0, "trainSpeed": 0.8, "happy": 8},
	"junta": {"name": "Military Junta", "icon": "🎖",
		"desc": "The barracks rule. Guards are cheap and fearsome, troops drill fast — the people grumble, and festivals are deemed frivolous.",
		"policyCost": 1.0, "taxEff": 1.0, "taxTol": 0, "guardUp": 0.6, "guardStr": 1.35,
		"buildCost": 1.0, "buildSpeed": 1.0, "festCost": 1.6, "festJoy": 0.8,
		"trade": 0.9, "trainCost": 0.8, "trainSpeed": 1.3, "happy": -10},
	"theocracy": {"name": "Theocracy", "icon": "⛪",
		"desc": "The gods provide. Festivals are holy rites — cheap and rapturous — and the faithful tithe gladly.",
		"policyCost": 1.0, "taxEff": 1.0, "taxTol": 0, "guardUp": 1.0, "guardStr": 1.1,
		"buildCost": 1.0, "buildSpeed": 1.0, "festCost": 0.6, "festJoy": 1.5,
		"trade": 1.0, "trainCost": 1.0, "trainSpeed": 1.0, "happy": 4, "tithe": 0.05},
	"tribal": {"name": "Tribal Clans", "icon": "🪶",
		"desc": "The clans raise warriors fast and cheap, loyal to blood over crown. Central taxes barely reach the steppe.",
		"policyCost": 1.0, "taxEff": 0.6, "taxTol": 0, "guardUp": 1.2, "guardStr": 0.9,
		"buildCost": 1.1, "buildSpeed": 1.0, "festCost": 1.0, "festJoy": 1.1,
		"trade": 1.0, "trainCost": 0.7, "trainSpeed": 1.4, "happy": 0},
	"oligarchy": {"name": "Merchant Oligarchy", "icon": "💎",
		"desc": "Coin is king. Trade flows like wine and builders work cheap — but sellswords charge a premium.",
		"policyCost": 1.0, "taxEff": 1.0, "taxTol": 0, "guardUp": 1.6, "guardStr": 1.0,
		"buildCost": 0.85, "buildSpeed": 1.0, "festCost": 1.0, "festJoy": 1.0,
		"trade": 1.6, "trainCost": 1.0, "trainSpeed": 1.0, "happy": 0},
	"democracy": {"name": "Democracy", "icon": "🗳",
		"desc": "The people are happiest ruling themselves — but every decree costs a fortune in debate, and elections keep rulers nervous.",
		"policyCost": 2.0, "taxEff": 1.0, "taxTol": 0, "guardUp": 1.0, "guardStr": 1.0,
		"buildCost": 1.0, "buildSpeed": 1.0, "festCost": 1.0, "festJoy": 1.2,
		"trade": 1.1, "trainCost": 1.0, "trainSpeed": 1.0, "happy": 12, "elections": true},
}
const GOV_ORDER: Array[String] = ["monarchy", "council", "junta", "theocracy",
	"tribal", "oligarchy", "democracy"]

## Guard policy: want 4 militia / 8 professional (HTML reconcileGuards).
const GUARD_WANT := {"militia": 4, "professional": 8, "none": 0}

## Festival: 150 gold + 80 food base, 7-day cooldown (HTML gazHoldFestival).
const FEST_BASE_GOLD := 150.0
const FEST_BASE_FOOD := 80.0
const FEST_COOLDOWN := 7

## Squabble flavor lines (HTML SQB_GOVDUNK / SQB_TAXHIGH / SQB_TAXZERO / SQB_FEST).
const GOV_DUNK := {
	"democracy": ["The {k} let the peasants VOTE. Next they'll demand opinions. Then it's just yelling with extra steps. 🗳",
		"Democracy: where every decision takes six weeks and a fistfight. Bold strategy."],
	"theocracy": ["The {k} takes orders from the gods now. Convenient — the gods never show up to meetings. ⛪",
		"Nothing says 'stable rule' like a ruler who hears voices. Holy ones, allegedly."],
	"monarchy": ["One crown, one head, zero term limits. The {k} plays the long game. Very long. Forever, ideally. 👑"],
	"council": ["Rule by committee: the {k} needs a permission slip to sneeze. Efficient! 📋"],
	"junta": ["The {k} runs the realm like a barracks. Bedtime is 2100 hours. Fun is scheduled. 🪖"],
	"tribal": ["The {k} governs by clan moot and ritual combat. Succession planning is... physical. 🪶"],
	"oligarchy": ["The {k} sold the realm to the highest bidder. The bidder was also the {k}. Neat trick. 💎"],
}
const TAX_HIGH_LINES: Array[String] = [
	"{n}% tax?! The crown is taxing my BREATHING at this point. 💸",
	"Paid my taxes today. In tears. The coin kind and the other kind. 💸",
]
const TAX_ZERO_LINES: Array[String] = [
	"0% tax. Anarchy? No — FREEDOM, baby. The roads can wait. 🕊",
]
const FEST_LINES: Array[String] = [
	"FESTIVAL in {t}! Pies! Dancing! Someone's definitely getting married by accident! 🎉",
	"{t} is throwing a festival and the whole realm is invited. My liver has already RSVP'd. 🍻",
	"Festival day in {t}! The bards are tuning up and the pies are cooling down. Perfect. 🎶",
]

## Default guild hiring quotas per town (HTML computeQuotas57 base table).
const QUOTA_DEFAULTS := {"worker": 3, "farmer": 2, "shopkeeper": 1,
	"builder": 1, "soldier": 1, "archer": 0, "mage": 0, "doctor": 0,
	"firefighter": 2, "fisher": 0}

## Plague doctrines (Jeremy 2026-10-11): how the crown answers the plague.
## Changeable anytime — mid-outbreak switches apply on the next day tick.
## Twisted <-> benevolent is the ruler's call; the sim remembers.
const PLAGUE_POLICIES := {
	"mercy": {"name": "Save Them All",
		"blurb": "Quarantine-as-care and full treatment. No executions, ever. The benevolent path."},
	"cure": {"name": "Treat the Sick",
		"blurb": "Doctors treat the sick where they stand. Cure chance scales with their medicine skill."},
	"quarantine": {"name": "Quarantine",
		"blurb": "Round the sick up to the clinics. The quarantined don't spread; doctors treat them there."},
	"cull_military": {"name": "Military Cull",
		"blurb": "Soldiers put the sick down on the spot. Fast and brutal — the executioners risk infection."},
	"cull_doctor": {"name": "Doctor's Mercy",
		"blurb": "Doctors quietly end the suffering. Still dark, whatever you call it."},
	"ignore": {"name": "Do Nothing",
		"blurb": "Let the plague run its course. History will have opinions."},
}
const PLAGUE_POLICY_ORDER: Array[String] = ["mercy", "cure", "quarantine",
	"cull_military", "cull_doctor", "ignore"]


var state: Dictionary
var _gs: GameState
var court = null   # SimRoyalCourt (duck-typed, set by owner)
var phone = null   # SimPhone (duck-typed, attached by the phone UI)
var crime_ref = null  # SimCrime (duck-typed, set by SimRoyalCourt)


func _init(game_state: GameState, royal_court = null) -> void:
	_gs = game_state
	court = royal_court
	state = {
		"tax": 10, "anarchy": false, "guard": "none", "curfew": false,
		"borders": "open", "festival_cd": 0,
		"government": "monarchy",
		"laws": {"gambling": false, "alehouses": true, "dueling": false},
		"approval": {}, "unrest": {},
		"election_day": 0, "strike": false,
		"happiness": 62, "last_festival_day": 0,
		"last_festival_town": "", "winddown_day": 0,
		"quota_deltas": {},
		"festivals": [], "fest_seq": 1,
		"guard_uids": [],
		"day_gold_delta": 0, "day_note": "",
		"plague_policy": "mercy",
	}
	_gs.bus.day_changed.connect(_on_day)


## Late wiring: the phone system (created separately) for Squabble posts/DMs.
func attach_phone(p) -> void:
	phone = p


## --- government ---------------------------------------------------------------

## Validated government key (HTML govKey: unknown -> monarchy).
func gov_key() -> String:
	var k: String = String(state.get("government", "monarchy"))
	return k if GOVERNMENTS.has(k) else "monarchy"


func gov_def(key: String = "") -> Dictionary:
	var k: String = key if key != "" else gov_key()
	return GOVERNMENTS.get(k, GOVERNMENTS["monarchy"])


## Regime change: 500g x policyCost; approval dips, Gazette story, guards
## reconciled (HTML gazSetGovernment).
func set_government(key: String) -> bool:
	if not GOVERNMENTS.has(key) or gov_key() == key:
		return false
	var fee: int = int(round(500.0 * float(gov_def().get("policyCost", 1.0))))
	if not _spend(fee):
		return false
	var old: Dictionary = gov_def()
	state["government"] = key
	var gd: Dictionary = gov_def()
	for tk: String in (state["approval"] as Dictionary).keys():
		(state["approval"] as Dictionary)[tk] = maxf(5.0,
			float((state["approval"] as Dictionary)[tk]) - 12.0)
	_add_happiness(-8)
	_story("👑 " + String(gd.get("name", "")).to_upper() + " PROCLAIMED!",
		"The old order falls! " + String(old.get("name", "")) + " gives way to "
		+ String(gd.get("name", "")) + ". " + String(gd.get("desc", ""))
		+ " The people are unsettled — approval dips across the realm.", "court")
	_squabble_flavor(GOV_DUNK.get(key, []), "gov")
	_mayor_says("A new government, sire? The criers are hoarse already. The people will need time to adjust…")
	reconcile_guards(false)
	return true

## --- policy setters (HTML gazSet* — fees scaled by government) ----------------

## Decree fee for a policy change; false when the treasury is too bare.
func policy_fee(base: float) -> bool:
	var fee: int = int(round(base * float(gov_def().get("policyCost", 1.0))))
	return _spend(fee)


func _spend(gold: int) -> bool:
	if gold <= 0:
		return true
	var pf: String = _gs.player_faction
	if pf == "":
		return false
	if _gs.resources.get_amount(pf, "gold") < float(gold):
		return false
	_gs.resources.add_resource(pf, "gold", -float(gold))
	return true


## Tax rate 0-40%. Setting any tax > 0 ends anarchy (HTML gazSetTax).
func set_tax(v: int) -> void:
	var nv: int = clampi(v, 0, 40)
	state["tax"] = nv
	if nv > 0:
		state["anarchy"] = false
	_story("TAX DECREE", "The crown sets the royal tax at %d%%." % nv, "court")
	_react("tax", {"value": nv})


func toggle_anarchy() -> bool:
	if not policy_fee(200.0):
		return false
	var on: bool = not bool(state.get("anarchy", false))
	state["anarchy"] = on
	if on:
		state["tax"] = 0
		_set_guard_silent("none")
	_add_happiness(-10 if on else 5)
	_story("🔥 ANARCHY!" if on else "ORDER RESTORED",
		"The ruler dissolves all authority! The strong do as they please!"
		if on else "The crown restores law. Bells ring.", "court")
	_react("anarchy", {})
	return true


func set_guard(tier: String) -> bool:
	if not tier in GUARD_TIERS:
		return false
	if bool(state.get("anarchy", false)) and tier != "none":
		return false  # 🔥 No guards under anarchy!
	if String(state.get("guard", "none")) == tier:
		return true
	if not _spend(guard_decree_fee()):
		return false
	state["guard"] = tier
	reconcile_guards(true)
	_react("guard", {"tier": tier})
	return true


## The decree fee for raising/disbanding the watch, after policyCost
## (monarchy 0.5 -> 50g; the audit trail priced it at a flat 100g).
func guard_decree_fee() -> int:
	return int(round(100.0 * float(gov_def().get("policyCost", 1.0))))


func _set_guard_silent(tier: String) -> void:
	state["guard"] = tier
	reconcile_guards(false)


func toggle_curfew() -> bool:
	if not policy_fee(50.0):
		return false
	var on: bool = not bool(state.get("curfew", false))
	state["curfew"] = on
	_story("CURFEW " + ("IMPOSED" if on else "LIFTED"),
		"None on the streets after dark, by royal decree."
		if on else "The night belongs to everyone again.", "court")
	_react("curfew", {"on": on})
	return true


func set_borders(v: String) -> bool:
	if not v in BORDER_MODES:
		return false
	if String(state.get("borders", "open")) == v:
		return false
	if not policy_fee(75.0):
		return false
	state["borders"] = v
	_story("BORDERS OPENED" if v == "open" else "BORDERS CLOSED",
		"Traders and strangers stream through the gates."
		if v == "open" else "The gates clang shut. None pass without the crown's seal.",
		"court")
	_react("borders", {"open": v == "open"})
	return true


## --- laws (Jeremy 2026-10-11, Ruler's Voice expansion) ----------------------------

func law_allowed(key: String) -> bool:
	var laws: Dictionary = state.get("laws", {})
	return bool(laws.get(key, false))


## Permit or ban a law. Goes through the real decree fee, Gazette story,
## happiness shift, and AI reaction — not shadow state.
func set_law(key: String, allowed: bool) -> bool:
	if not LAW_DEFS.has(key):
		return false
	var laws: Dictionary = state.get("laws", {})
	if bool(laws.get(key, false)) == allowed:
		return false  # already the law of the land
	var def: Dictionary = LAW_DEFS[key]
	if not policy_fee(float(def.get("fee", 25.0))):
		return false
	laws[key] = allowed
	var h := float(def.get("happy", 0.0))
	_add_happiness(h if allowed else -h)
	var headline := ("%s LEGALIZED" % String(def.get("label", key)) \
		if allowed else "%s OUTLAWED" % String(def.get("label", key))).to_upper()
	_story(headline, String(def.get("blurb", "")), "court")
	_react("law", {"law": key, "allowed": allowed})
	return true


## Set the plague doctrine (Jeremy 2026-10-11). Changeable anytime —
## mid-outbreak switches apply on the next day tick. No fee: this is triage,
## not a decree. Goes through the Gazette so the realm knows where its
## ruler stands, and the sim remembers (mercy or the sword).
func set_plague_policy(key: String) -> bool:
	if not PLAGUE_POLICIES.has(key):
		return false
	if String(state.get("plague_policy", "mercy")) == key:
		return false  # already the doctrine
	state["plague_policy"] = key
	var def: Dictionary = PLAGUE_POLICIES[key]
	_story(("PLAGUE DOCTRINE — %s" % String(def.get("name", key))).to_upper(),
		String(def.get("blurb", "")), "court")
	var gs = _gs
	if gs != null and gs.get("disease") != null:
		gs.disease.set_doctrine(gs.player_faction, key)
	return true


func plague_policy() -> String:
	return String(state.get("plague_policy", "mercy"))


## Daily crown income from permitted vice (gambling halls, tavern licenses).
func law_income() -> int:
	var pop: int = citizen_pop()
	var inc := 0.0
	for k: String in LAW_DEFS:
		if law_allowed(k):
			inc += float(pop) * float((LAW_DEFS[k] as Dictionary).get("income", 0.0))
	return int(round(inc))


## Notify AI rulers of a player action (HTML rulerReactTo).
func _react(event: String, data: Dictionary) -> void:
	if _gs.get("diplomacy") != null:
		_gs.diplomacy.ruler_react_to(event, data)

## --- guards -------------------------------------------------------------------

## Alive player-faction units currently serving as guards.
func guard_units() -> Array:
	var out: Array = []
	var pf: String = _gs.player_faction
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		if bool((u.get("mind", {}) as Dictionary).get("is_guard", false)):
			out.append(u)
	return out


## HTML reconcileGuards: want 4 militia / 8 professional; volunteers from
## existing soldiers first, then spawns new ones (cap-respecting).
func reconcile_guards(announce: bool) -> void:
	var pf: String = _gs.player_faction
	if pf == "":
		return
	var want: int = int(GUARD_WANT.get(String(state.get("guard", "none")), 0))
	var cur: Array = guard_units()
	if cur.size() > want:
		for i: int in range(want, cur.size()):
			((cur[i] as Dictionary).get("mind", {}) as Dictionary)["is_guard"] = false
		if announce:
			_story("GUARD STOOD DOWN",
				"Guards hang up their spears and return to honest work.", "court")
	var towns: Array = _player_towns()
	var town_id: int = int((towns[0] as Dictionary).get("id", -1)) if not towns.is_empty() else -1
	var need: int = want - guard_units().size()
	var spawned: int = 0
	var str_mult: float = float(gov_def().get("guardStr", 1.0))
	for k: int in need:
		var g: Dictionary = _volunteer_soldier(pf)
		if g.is_empty():
			var pos := Vector2(400, 400)
			if not towns.is_empty():
				var tp: Vector2 = (towns[k % towns.size()] as Dictionary).get("position", Vector2(400, 400))
				var ang: float = (float(k) / float(maxi(1, need))) * TAU
				pos = tp + Vector2(cos(ang), sin(ang)) * 90.0
			g = _gs.spawner.spawn_unit(pf, "soldier", town_id, pos)
			if g.is_empty():
				break  # caps hold — stop mustering
		var mind: Dictionary = g.get("mind", {})
		mind["is_guard"] = true
		# spawn_unit/add_unit create no mind dict — without this write-back
		# the tag lands on a throwaway and the watch never musters.
		g["mind"] = mind
		var hp_mult: float = str_mult
		if String(state.get("guard", "")) == "professional":
			hp_mult *= 1.6
		if g.has("max_hp"):
			g["max_hp"] = float(g.get("max_hp", 100.0)) * hp_mult
			g["hp"] = float(g.get("max_hp", 100.0))
		spawned += 1
	(state["guard_uids"] as Array).clear()
	for u: Dictionary in guard_units():
		(state["guard_uids"] as Array).append(int(u.get("id", 0)))
	if announce and spawned > 0:
		_story("GUARD MUSTERED",
			"%d %s guards take up their posts around the town. Visible in the streets!"
			% [spawned, String(state.get("guard", ""))], "court")


func _volunteer_soldier(pf: String) -> Dictionary:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		if String(u.get("job", "")) != "soldier":
			continue
		if bool((u.get("mind", {}) as Dictionary).get("is_guard", false)):
			continue
		return u
	return {}


## --- helpers ------------------------------------------------------------------

func _add_happiness(d: float) -> void:
	state["happiness"] = clampf(float(state.get("happiness", 62.0)) + d, 0.0, 100.0)


## Public happiness nudge (for court petition effects).
func add_happiness(d: float) -> void:
	_add_happiness(d)


func _story(headline: String, body: String, kind: String = "court") -> void:
	if court != null and court.has_method("publish_story"):
		court.publish_story(headline, body, kind)


func _squabble_flavor(lines: Array, kind: String) -> void:
	if phone == null or lines.is_empty():
		return
	var author: Dictionary = _random_citizen()
	if author.is_empty():
		return
	var line: String = String(lines[randi() % lines.size()])
	line = line.replace("{k}", _gs.ruler_name)
	phone.npc_post(author, line, kind)


func _random_citizen() -> Dictionary:
	var pf: String = _gs.player_faction
	var cands: Array = []
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == pf:
			cands.append(u)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


func _mayor_says(text: String) -> void:
	if phone == null:
		return
	var mayor: Dictionary = _role_holder("mayor")
	if not mayor.is_empty():
		phone.npc_message(int(mayor.get("id", 0)), text)


func _role_holder(role: String) -> Dictionary:
	var pf: String = _gs.player_faction
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		if String((u.get("mind", {}) as Dictionary).get("gov_role", "")) == role:
			return u
	return {}


func _player_towns() -> Array:
	var out: Array = []
	var pf: String = _gs.player_faction
	for tid: Variant in _gs.towns:
		var t: Dictionary = _gs.towns[tid]
		if String(t.get("faction", "")) == pf:
			out.append(t)
	return out


func citizen_pop() -> int:
	var pf: String = _gs.player_faction
	var n: int = 0
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == pf:
			n += 1
	return n


## Projected daily tax income (HTML renderPoliciesBody formula).
func projected_tax_income() -> int:
	if bool(state.get("anarchy", false)):
		return 0
	var tax: int = int(state.get("tax", 0))
	if tax <= 0:
		return 0
	var gd: Dictionary = gov_def()
	return int(round(float(citizen_pop()) * (float(tax) / 100.0) * 3.0
		* float(gd.get("taxEff", 1.0))))


## Crime-system multiplier (HTML crimePressure) — consumed by SimCrime's
## daily tick. Guard tier, anarchy, high taxes, curfew (-40%), an active
## festival, an active crackdown (x0.35), and unhappy towns (approval < 25
## -> x1.6, < 40 -> x1.3) all feed in.
func crime_pressure_mult() -> float:
	var mult: float = 1.0
	match String(state.get("guard", "none")):
		"militia":
			mult *= 0.45
		"professional":
			mult *= 0.18
	if bool(state.get("anarchy", false)):
		mult *= 1.8
	var tax: int = int(state.get("tax", 0))
	if tax >= 25:
		mult *= 1.0 + float(tax - 25) / 25.0
	if bool(state.get("curfew", false)):
		mult *= 0.6
	if int(state.get("festival_cd", 0)) > 0:
		mult *= 0.6
	if crime_ref != null and crime_ref.crackdown_active():
		mult *= 0.35
	var avg: float = avg_approval()
	if avg < 25.0:
		mult *= 1.6
	elif avg < 40.0:
		mult *= 1.3
	return mult


## Strike slowdown for worker AI (HTML govWorkMult).
func work_mult() -> float:
	return 0.7 if bool(state.get("strike", false)) else 1.0


## Government-scaled economy getters (for other systems' hooks).
func train_speed_mult() -> float:
	return float(gov_def().get("trainSpeed", 1.0)) * work_mult()

func build_cost_mult() -> float:
	return float(gov_def().get("buildCost", 1.0))

func build_speed_mult() -> float:
	return float(gov_def().get("buildSpeed", 1.0)) * work_mult()

func trade_mult() -> float:
	return float(gov_def().get("trade", 1.0))

func guard_strength_mult() -> float:
	return float(gov_def().get("guardStr", 1.0))

func fest_cost() -> Dictionary:
	var gd: Dictionary = gov_def()
	return {"gold": roundf(FEST_BASE_GOLD * float(gd.get("festCost", 1.0))),
		"food": roundf(FEST_BASE_FOOD * float(gd.get("festCost", 1.0)))}

func fest_joy() -> int:
	return int(round(14.0 * float(gov_def().get("festJoy", 1.0))))

## --- daily tick -----------------------------------------------------------------

func _on_day(_day: int, _is_night: bool) -> void:
	daily_tick()


## One in-game day of policy effects (HTML govDayTick body).
func daily_tick() -> void:
	var pf: String = _gs.player_faction
	var gd: Dictionary = gov_def()
	var notes: Array[String] = []
	if pf == "":
		return
	# HTML festival close: the day after a festival, the Gazette notes the
	# wind-down (fires once per festival — winddown_day guards the repeat).
	var lfd: int = int(state.get("last_festival_day", 0))
	if lfd > 0 and lfd == _gs.day_number - 1 \
			and int(state.get("winddown_day", 0)) != _gs.day_number:
		state["winddown_day"] = _gs.day_number
		var wt: String = String(state.get("last_festival_town", "the town"))
		# Jeremy 2026-10-08 (hearsay flesh-out): the mill hears the
		# wind-down directly — emitted BEFORE the Gazette story so the
		# rich rumor (named town) dedups the thin story seed.
		_gs.bus.festival_event.emit("wound_down", wt, pf, 0)
		_story("FESTIVAL WINDS DOWN",
			"The bunting comes down in %s and the last dancers stumble home, pockets full of pie. The Great Mosh Pit of %s is already legend." % [wt, wt],
			"court")
	var gold_before: float = _gs.resources.get_amount(pf, "gold")
	var pop: int = citizen_pop()
	# Taxes.
	if not bool(state.get("anarchy", false)) and int(state.get("tax", 0)) > 0:
		var inc: int = projected_tax_income()
		if avg_approval() < 40.0:
			inc = int(round(inc * 0.9))  # grumbling collectors
		if inc > 0:
			_gs.resources.add_resource(pf, "gold", float(inc))
			notes.append("taxes +%dg" % inc)
	# Laws: licensed vice pays the crown (gambling halls, tavern licenses).
	var linc: int = law_income()
	if linc > 0:
		_gs.resources.add_resource(pf, "gold", float(linc))
		notes.append("laws +%dg" % linc)
	# Guard upkeep.
	var guards: Array = guard_units()
	if not guards.is_empty():
		var per: float = 5.0 if String(state.get("guard", "")) == "professional" else 2.0
		per = maxf(1.0, roundf(per * float(gd.get("guardUp", 1.0))))
		var cost: int = int(guards.size() * per)
		if _gs.resources.get_amount(pf, "gold") < float(cost):
			_set_guard_silent("none")
			_add_happiness(-6)
			_story("GUARDS DESERT!",
				"Unpaid guards throw down their spears and walk. The streets feel unsafe.",
				"court")
			var cmdr: Dictionary = _role_holder("commander")
			if phone != null and not cmdr.is_empty():
				phone.npc_message(int(cmdr.get("id", 0)),
					"You starve the watch, you get no watch, sire. Pay us or lose us.")
		elif cost > 0:
			_gs.resources.add_resource(pf, "gold", -float(cost))
			notes.append("guard upkeep −%dg" % cost)
	# Anarchy decay.
	if bool(state.get("anarchy", false)):
		_add_happiness(-1)
		if randf() < 0.5:
			var b: Dictionary = _random_non_hall_building(pf)
			if not b.is_empty():
				b["hp"] = maxf(1.0, float(b.get("hp", 100.0)) - 12.0)
	# Open-borders trade bonus: +15 per trade-deal faction x gov trade mult.
	if String(state.get("borders", "open")) == "open":
		var bonus: float = 0.0
		if _gs.diplomacy != null and _gs.diplomacy.has_method("has_trade_deal"):
			for f: String in _gs.active_factions:
				if f != pf and bool(_gs.diplomacy.has_trade_deal(pf, f)):
					bonus += 15.0
		bonus = roundf(bonus * float(gd.get("trade", 1.0)))
		if bonus > 0.0:
			_gs.resources.add_resource(pf, "gold", bonus)
			notes.append("trade +%dg" % int(bonus))
	# Theocracy tithe: the faithful give gladly.
	if gd.has("tithe") and pop > 0:
		var tithe: int = maxi(1, int(round(float(pop) * float(gd["tithe"]) * 3.0)))
		_gs.resources.add_resource(pf, "gold", float(tithe))
		notes.append("⛪ tithe +%dg" % tithe)
	# Curfew costs happiness every day.
	if bool(state.get("curfew", false)):
		_add_happiness(-0.5)
	# Festival cooldown ticks down.
	if int(state.get("festival_cd", 0)) > 0:
		state["festival_cd"] = int(state["festival_cd"]) - 1
	# Scheduled festivals fire on their day.
	_fire_due_festivals()
	# Happiness drifts toward the government target.
	var target: float = 55.0 + float(gd.get("happy", 0))
	var tax: int = int(state.get("tax", 0))
	if tax >= 25:
		target -= maxf(0.0, 12.0 - float(gd.get("taxTol", 0)))
	if bool(state.get("anarchy", false)):
		target -= 10.0
	var hap: float = float(state.get("happiness", 62.0))
	if hap < target:
		_add_happiness(1.0)
	elif hap > target:
		_add_happiness(-1.0)
	var gold_after: float = _gs.resources.get_amount(pf, "gold")
	state["day_gold_delta"] = gold_after - gold_before
	state["day_note"] = " · ".join(notes)
	_approval_tick()


func _random_non_hall_building(pf: String) -> Dictionary:
	var cands: Array = []
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) != pf:
			continue
		var t: String = String(b.get("type", ""))
		if t == "hall" or t == "townhall":
			continue
		cands.append(b)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


## --- domestic approval ------------------------------------------------------------

## Per-town approval, lazy default 60 (HTML govApprovalFor).
func approval_for(town_id: int) -> float:
	var k: String = str(town_id)
	if not (state["approval"] as Dictionary).has(k):
		(state["approval"] as Dictionary)[k] = 60.0
	return float((state["approval"] as Dictionary)[k])


func set_approval(town_id: int, v: float) -> void:
	(state["approval"] as Dictionary)[str(town_id)] = clampf(v, 0.0, 100.0)


## Realm average (HTML govAvgApproval).
func avg_approval() -> float:
	var towns: Array = _player_towns()
	if towns.is_empty():
		return 60.0
	var sum: float = 0.0
	for t: Dictionary in towns:
		sum += approval_for(int(t.get("id", 0)))
	return sum / float(towns.size())


## Nudge every town's approval (HTML govPetitionMood).
func petition_mood(d: float) -> void:
	for t: Dictionary in _player_towns():
		var tid: int = int(t.get("id", 0))
		set_approval(tid, approval_for(tid) + d)


## Daily approval drift, strikes, riots, elections (HTML govApprovalDayTick).
func _approval_tick() -> void:
	var towns: Array = _player_towns()
	if towns.is_empty():
		return
	var pf: String = _gs.player_faction
	var gd: Dictionary = gov_def()
	var tax: int = int(state.get("tax", 0))
	var dn: int = _gs.day_number
	var any_strike: bool = false
	for t: Dictionary in towns:
		var tid: int = int(t.get("id", 0))
		var k: String = str(tid)
		var ap: float = approval_for(tid)
		var target: float = 55.0 + float(gd.get("happy", 0))
		if tax >= 25:
			target -= maxf(0.0, 12.0 - float(gd.get("taxTol", 0)))
		elif tax <= 5:
			target += 4.0
		if bool(state.get("anarchy", false)):
			target -= 10.0
		if bool(state.get("curfew", false)):
			target -= 3.0
		if int(state.get("last_festival_day", 0)) > 0 \
				and dn - int(state.get("last_festival_day", 0)) <= 3:
			target += 6.0
		if _at_war(pf):
			target -= 4.0
		if ap < target:
			ap = minf(target, ap + 2.0)
		elif ap > target:
			ap = maxf(target, ap - 2.0)
		ap = clampf(ap, 0.0, 100.0)
		set_approval(tid, ap)
		if ap < 25.0:
			any_strike = true
		if ap < 40.0 and randf() < 0.3:
			_mayor_says("The mood in %s sours, sire — approval %d/100. They grumble in the taverns."
				% [String(t.get("name", "town")), int(round(ap))])
		var cd: int = int((state["unrest"] as Dictionary).get(k, 0))
		if ap <= 15.0 and dn >= cd:
			_riot(t, k)
	state["strike"] = any_strike
	# Democracy: election day every 30 days.
	if bool(gd.get("elections", false)) and dn % 30 == 0 and dn > 1 \
			and int(state.get("election_day", 0)) != dn:
		state["election_day"] = dn
		var avg: float = avg_approval()
		if avg < 45.0:
			petition_mood(-8.0)
			_story("🗳 ELECTION UPSET!",
				"The people vote for change — and blame the incumbent for everything. Approval plummets across the realm.",
				"court")
		else:
			_add_happiness(6)
			petition_mood(4.0)
			_story("🗳 RE-ELECTED!",
				"The people renew their mandate! Bunting everywhere, and the taverns drink to democracy.",
				"court")
	if int(state.get("election_day", 0)) != 0 and dn % 30 != 0:
		state["election_day"] = 0


func _at_war(pf: String) -> bool:
	if _gs.diplomacy == null or not _gs.diplomacy.has_method("relation_state"):
		return false
	for f: String in _gs.active_factions:
		if f != pf and String(_gs.diplomacy.relation_state(pf, f)) == "war":
			return true
	return false


## A town's approval collapsed: Gazette headline, building damage (HTML govRiot).
## The visible angry-mob movement is worker-AI/visual territory — HOOK.
func _riot(town: Dictionary, key: String) -> void:
	var dn: int = _gs.day_number
	(state["unrest"] as Dictionary)[key] = dn + 5
	var tname: String = String(town.get("name", "the capital"))
	var b: Dictionary = _random_non_hall_building(_gs.player_faction)
	if not b.is_empty():
		b["hp"] = maxf(1.0, float(b.get("hp", 100.0)) - 40.0)
	set_approval(int(town.get("id", 0)), 32.0)
	_add_happiness(-12)
	_story("🔥 RIOT IN " + tname.to_upper() + "!",
		"Furious citizens storm the streets of " + tname
		+ ", hurling refuse and curses at the "
		+ String(gov_def().get("name", "government")).to_lower()
		+ "! Windows smash. The guard struggles to restore order.", "court")
	_mayor_says("Sire! They riot in %s! Lower taxes, hold a festival — do SOMETHING!" % tname)

## --- festivals ------------------------------------------------------------------

## Hold a festival now: 150g + 80f x festCost, 7-day cooldown, +joy happiness,
## +3 approval, Gazette story, Squabble flavor (HTML gazHoldFestival).
## Returns a result line for the UI.
func hold_festival(town_id: int = -1) -> String:
	var pf: String = _gs.player_faction
	if pf == "":
		return "No realm to celebrate in."
	if int(state.get("festival_cd", 0)) > 0:
		return "Festival cooldown: %d more day(s)." % int(state.get("festival_cd", 0))
	var cost: Dictionary = fest_cost()
	if _gs.resources.get_amount(pf, "gold") < float(cost["gold"]) \
			or _gs.resources.get_amount(pf, "food") < float(cost["food"]):
		return "The coffers are too bare for pies and music."
	_gs.resources.add_resource(pf, "gold", -float(cost["gold"]))
	_gs.resources.add_resource(pf, "food", -float(cost["food"]))
	state["festival_cd"] = FEST_COOLDOWN
	state["last_festival_day"] = _gs.day_number
	var joy: int = fest_joy()
	_add_happiness(float(joy))
	petition_mood(3.0)
	var tname: String = _town_name(town_id)
	state["last_festival_town"] = tname
	# Jeremy 2026-10-08 (hearsay flesh-out): the mill hears it directly —
	# town, host faction, and joy ride the signal BEFORE the Gazette
	# story, so the rich rumor dedups the thin story seed.
	_gs.bus.festival_event.emit("held", tname, pf, joy)
	_story("GRAND FESTIVAL!",
		"Music, pies, dancing in the mud! %s celebrates the crown's generosity." % tname,
		"court")
	if phone != null:
		var author: Dictionary = _random_citizen()
		if not author.is_empty():
			phone.npc_post(author,
				String(FEST_LINES[randi() % FEST_LINES.size()]).replace("{t}", tname),
				"festival")
	_react("festival", {})
	return "Festival held! +%d happiness. The town dances in the mud." % joy


func _town_name(town_id: int) -> String:
	if _gs.towns.has(town_id):
		return String((_gs.towns[town_id] as Dictionary).get("name", "the town"))
	var towns: Array = _player_towns()
	if not towns.is_empty():
		return String((towns[0] as Dictionary).get("name", "the town"))
	return "the town"


## Jeremy 2026-10-08: the town currently inside the 3-day festival joy
## window (the same window that drives the approval bump at daily_tick),
## or "" when no festival is being celebrated. Single source of truth for
## the festival-dance behavior (WorkerAI) and any future celebrants.
func festival_joy_town() -> String:
	var lfd: int = int(state.get("last_festival_day", 0))
	if lfd <= 0:
		return ""
	if _gs.day_number - lfd < 0 or _gs.day_number - lfd > 3:
		return ""
	return String(state.get("last_festival_town", ""))


## Schedule a festival N days out: paid now, same joy on the day, full
## refund on cancel (HTML festSchedule / festCancel).
func schedule_festival(town_id: int, days_out: int) -> String:
	var towns: Array = _player_towns()
	if towns.is_empty():
		return "No towns yet — found a town first!"
	if int(state.get("festival_cd", 0)) > 0:
		return "Festival cooldown: %d more day(s)." % int(state.get("festival_cd", 0))
	var tname: String = _town_name(town_id)
	for f: Dictionary in state["festivals"]:
		if String(f.get("town", "")) == tname:
			return "%s already has a festival on the calendar!" % tname
	var cost: Dictionary = fest_cost()
	var pf: String = _gs.player_faction
	if _gs.resources.get_amount(pf, "gold") < float(cost["gold"]) \
			or _gs.resources.get_amount(pf, "food") < float(cost["food"]):
		return "Not enough gold/food for a festival!"
	_gs.resources.add_resource(pf, "gold", -float(cost["gold"]))
	_gs.resources.add_resource(pf, "food", -float(cost["food"]))
	var day_abs: int = _gs.day_number + maxi(1, days_out)
	var entry: Dictionary = {
		"id": int(state["fest_seq"]), "town_id": town_id, "town": tname,
		"day_abs": day_abs, "gold": float(cost["gold"]), "food": float(cost["food"]),
	}
	state["fest_seq"] = int(state["fest_seq"]) + 1
	(state["festivals"] as Array).append(entry)
	return "Festival scheduled in %s — paid now, joy on the day." % tname


func cancel_festival(fest_id: int) -> bool:
	var pf: String = _gs.player_faction
	for i: int in (state["festivals"] as Array).size():
		var f: Dictionary = (state["festivals"] as Array)[i]
		if int(f.get("id", 0)) == fest_id:
			# Full refund — nothing was eaten yet (HTML rule).
			_gs.resources.add_resource(pf, "gold", float(f.get("gold", 0.0)))
			_gs.resources.add_resource(pf, "food", float(f.get("food", 0.0)))
			# HTML festCancel: the called-off festival makes the Gazette.
			# Jeremy 2026-10-08 (hearsay flesh-out): the mill hears the
			# cancellation directly, BEFORE the Gazette story, so the
			# rich rumor (named town) dedups the thin story seed.
			_gs.bus.festival_event.emit("cancelled",
				String(f.get("town", "the town")), pf, 0)
			_story("FESTIVAL CALLED OFF",
				"The festival planned for %s is cancelled. The crown refunds the preparations in full (%d gold, %d food)." % [
					String(f.get("town", "the town")),
					int(f.get("gold", 0.0)), int(f.get("food", 0.0))],
				"court")
			(state["festivals"] as Array).remove_at(i)
			return true
	return false


func scheduled_festivals() -> Array:
	return (state["festivals"] as Array).duplicate()


func _fire_due_festivals() -> void:
	var due: Array = []
	for f: Dictionary in state["festivals"]:
		if _gs.day_number >= int(f.get("day_abs", 0)):
			due.append(f)
	for f: Dictionary in due:
		(state["festivals"] as Array).erase(f)
		var joy: int = fest_joy()
		_add_happiness(float(joy))
		petition_mood(3.0)
		state["last_festival_day"] = _gs.day_number
		state["last_festival_town"] = String(f.get("town", "the town"))
		# Jeremy 2026-10-08 (hearsay flesh-out): the mill hears scheduled
		# festivals directly too — BEFORE the Gazette story.
		_gs.bus.festival_event.emit("held",
			String(f.get("town", "the town")), _gs.player_faction, joy)
		_story("GRAND FESTIVAL!",
			"The scheduled festival in %s erupts! Music, pies, dancing in the mud!"
			% String(f.get("town", "town")), "court")


## --- guild quotas -----------------------------------------------------------------
## Per-town hiring ledger (HTML candidate57): quota = default + player delta
## (delta clamped -8..+12). "+1" raises the quota, "stop" freezes hiring at
## the current headcount.

func quota_for(town_id: int, job: String) -> int:
	var deltas: Dictionary = (state["quota_deltas"] as Dictionary).get(
		str(town_id), {})
	return maxi(0, int(QUOTA_DEFAULTS.get(job, 0)) + int(deltas.get(job, 0)))


func adjust_quota(town_id: int, job: String, delta: int) -> bool:
	if not QUOTA_DEFAULTS.has(job):
		return false
	var key: String = str(town_id)
	if not (state["quota_deltas"] as Dictionary).has(key):
		(state["quota_deltas"] as Dictionary)[key] = {}
	var d: Dictionary = (state["quota_deltas"] as Dictionary)[key]
	d[job] = clampi(int(d.get(job, 0)) + delta, -8, 12)
	return true


## "Stop" hiring: freeze the quota at the current headcount (HTML guildStop57).
func freeze_quota(town_id: int, job: String) -> bool:
	if not QUOTA_DEFAULTS.has(job):
		return false
	var n: int = _count_job_in_town(town_id, job)
	var key: String = str(town_id)
	if not (state["quota_deltas"] as Dictionary).has(key):
		(state["quota_deltas"] as Dictionary)[key] = {}
	((state["quota_deltas"] as Dictionary)[key] as Dictionary)[job] = \
		clampi(n - int(QUOTA_DEFAULTS.get(job, 0)), -8, 12)
	return true


func _count_job_in_town(town_id: int, job: String) -> int:
	var n: int = 0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if int(u.get("town_id", -1)) != town_id:
			continue
		if String(u.get("job", "")) == job:
			n += 1
	return n


## Full quota report for one town: job -> {quota, count, status}.
func quota_report(town_id: int) -> Dictionary:
	var out: Dictionary = {}
	for job: String in QUOTA_DEFAULTS.keys():
		var q: int = quota_for(town_id, job)
		var n: int = _count_job_in_town(town_id, job)
		var status: String = "hiring" if q > n else ("surplus" if n > q else "full")
		out[job] = {"quota": q, "count": n, "status": status}
	return out


## --- save -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	var fresh: Dictionary = {
		"tax": 10, "anarchy": false, "guard": "none", "curfew": false,
		"borders": "open", "festival_cd": 0,
		"government": "monarchy",
		"laws": {"gambling": false, "alehouses": true, "dueling": false},
		"approval": {}, "unrest": {},
		"election_day": 0, "strike": false,
		"happiness": 62, "last_festival_day": 0,
		"last_festival_town": "", "winddown_day": 0,
		"quota_deltas": {},
		"festivals": [], "fest_seq": 1,
		"guard_uids": [],
		"day_gold_delta": 0, "day_note": "",
		"plague_policy": "mercy",
	}
	for k: String in fresh.keys():
		if data.has(k):
			fresh[k] = data[k]
	state = fresh
