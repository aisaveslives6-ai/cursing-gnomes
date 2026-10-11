## Cursing Gnomes — Ruler's Voice.
##
## Jeremy 2026-10-06: "talk to any of your cabinet members... and tell them
## what to do and what needs to be done in the kingdom."
##
## The player's cabinet (Treasury / War / Civic advisors + Guild Master, and
## the Draft Clerk — player faction ONLY) takes spoken orders in Messenger.
## Plain imperative language, forgiving phrasing. Orders run through the REAL
## game systems: real blueprints (tagged player_placed, so adviser-mode AI
## defers), real training queues (by_player=true), real army commands, real
## tax/festival policy.
##
## Behavior contract:
## - Orders are COMMANDS, not proposals: no approval modal. The two
##   exceptions are war/attack (existing strategic-proposal confirm — never
##   surprise wars) and truly irreversible acts.
## - Acknowledge in-voice, execute, and REPORT BACK in Messenger when done
##   or blocked (buildings finished/destroyed, training targets met/stalled).
## - Validate before promising: unaffordable / unknown building / nonsense ->
##   say so plainly, offer the closest valid alternative.
## - SOVEREIGNTY: only the player's own cabinet takes orders. A foreign
##   cabinet member given an order refuses in their leader's voice
##   (SimFactionLeaders.control_refusal_line).
## - Blocked NPCs stay silent: report-back rides phone.npc_message, which
##   already drops blocked threads.
##
## Hook: phone.gd _npc_reply calls try_order() before the conversation
## engine. Returns "" when the text isn't an order (normal chat proceeds).
class_name SimRulersVoice
extends RefCounted


## Cabinet jobs (GOV_ADVISOR_ROLES + guild master + draft clerk). Advisors
## also carry is_advisor=true from the spawner — both are accepted.
const CABINET_JOBS := ["advisor_economy", "advisor_war", "advisor_civic",
	"guild_master", "clerk"]

const ROLE_TITLES := {
	"advisor_economy": "Treasury Advisor",
	"advisor_war": "War Advisor",
	"advisor_civic": "Civic Advisor",
	"guild_master": "Guild Master",
	"clerk": "Draft Clerk",
}


## Word -> building type for build orders.
const BUILD_NOUNS := {
	"farm": "farm", "farms": "farm",
	"house": "house", "houses": "house", "home": "house", "homes": "house",
	"housing": "house",
	"barracks": "barracks", "barrack": "barracks",
	"oil pump": "oil_pump", "oil pumps": "oil_pump", "pumpjack": "oil_pump",
	"pumpjacks": "oil_pump",
	"lumber camp": "lumber_camp", "lumber camps": "lumber_camp",
	"sawmill": "sawmill", "sawmills": "sawmill",
	"mine": "mine", "mines": "mine",
	"quarry": "quarry", "quarries": "quarry",
	"well": "well", "wells": "well",
	"shop": "shop", "shops": "shop", "store": "shop", "stores": "shop",
	"market": "general_store", "markets": "general_store",
	"blacksmith": "blacksmith", "smith": "blacksmith", "forge": "blacksmith",
	"inn": "inn", "inns": "inn",
	"storage": "storage", "warehouse": "storage",
	"guard tower": "guard_tower", "guard towers": "guard_tower",
	"watchtower": "guard_tower",
	"clinic": "clinic", "hospital": "clinic",
	"fire station": "fire_station",
	"jail": "jail",
	"barn": "barn", "barns": "barn",
	"windmill": "windmill", "windmills": "windmill",
	"restaurant": "restaurant",
	"fishing dock": "fishing_dock", "dock": "fishing_dock",
	"bridge": "bridge", "bridges": "bridge",
	"armory": "armory",
	"mage spire": "mage_spire", "spire": "mage_spire",
	"castle": "knights_castle",
	"war hut": "war_hut",
	"stable": "horse_stable", "stables": "horse_stable",
	"bakery": "greasy_spoon",
	"tavern": "moonberry_lounge",
}


## Word -> job for train orders.
const TRAIN_NOUNS := {
	"soldier": "soldier", "soldiers": "soldier", "warrior": "soldier",
	"warriors": "soldier", "fighter": "soldier", "fighters": "soldier",
	"troop": "soldier", "troops": "soldier",
	"archer": "archer", "archers": "archer",
	"ranger": "ranger", "rangers": "ranger",
	"mage": "mage", "mages": "mage", "wizard": "mage", "wizards": "mage",
	"worker": "worker", "workers": "worker", "laborer": "worker",
	"laborers": "worker",
	"builder": "builder", "builders": "builder",
	"farmer": "farmer", "farmers": "farmer",
	"woodcutter": "woodcutter", "woodcutters": "woodcutter",
	"lumberjack": "woodcutter", "lumberjacks": "woodcutter",
	"miner": "miner", "miners": "miner",
	"fisher": "fisher", "fishers": "fisher", "fisherman": "fisher",
	"fishermen": "fisher",
	"doctor": "doctor", "doctors": "doctor", "medic": "doctor",
	"firefighter": "firefighter", "firefighters": "firefighter",
	"guard": "guard", "guards": "guard",
	"cannoneer": "cannoneer",
}


## Word -> faction id for war orders.
const FACTION_NOUNS := {
	"elves": "elf", "elf": "elf", "elven": "elf",
	"humans": "human", "human": "human",
	"ogres": "ogre", "ogre": "ogre",
	"undead": "undead",
	"gnomes": "gnome", "gnome": "gnome",
}


const NUMBER_WORDS := {
	"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4,
	"five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
	"couple": 2, "few": 3, "several": 4, "dozen": 12,
}


var _gs = null
## Pending orders awaiting completion report-back (saved).
var _pending: Array = []
## Dialogue-tree menu context per advisor (unit id -> menu dict). Transient:
## a menu is a conversation aid, not game state — never saved.
var _dialogue: Dictionary = {}


func _init(gs) -> void:
	_gs = gs
	if _gs != null:
		var bus = _gs.get("bus")
		if bus != null:
			if bus.has_signal("day_changed"):
				bus.day_changed.connect(_on_day)
			if bus.has_signal("unit_killed"):
				bus.unit_killed.connect(_on_unit_killed)
			# Jeremy 2026-10-11 (Ruler's Voice expansion): war starts
			# spread the word through the cabinet.
			if bus.has_signal("strategic_proposal_decided"):
				bus.strategic_proposal_decided.connect(_on_proposal_decided)


## --- cabinet detection ----------------------------------------------------

## True when the unit is one of the PLAYER's cabinet members.
static func is_cabinet(gs, unit: Dictionary) -> bool:
	if unit.is_empty() or not bool(unit.get("alive", true)):
		return false
	if String(unit.get("faction", "")) != String(gs.player_faction):
		return false
	var job := String(unit.get("job", ""))
	if job in CABINET_JOBS:
		return true
	return bool(unit.get("is_advisor", false))


## True when the unit holds a cabinet job but belongs to a FOREIGN faction
## (order attempts get a sovereignty refusal).
static func is_foreign_cabinet(gs, unit: Dictionary) -> bool:
	if unit.is_empty() or not bool(unit.get("alive", true)):
		return false
	var f := String(unit.get("faction", ""))
	if f == "" or f == String(gs.player_faction):
		return false
	var job := String(unit.get("job", ""))
	if job in CABINET_JOBS:
		return true
	return bool(unit.get("is_advisor", false))


static func role_title(unit: Dictionary) -> String:
	var t: String = String(ROLE_TITLES.get(String(unit.get("job", "")), ""))
	if t != "":
		return t
	var ar: String = String(unit.get("advisor_role", ""))
	return ar if ar != "" else "Advisor"


## --- entry point ----------------------------------------------------------

## Try to handle player text as a spoken order to this cabinet member.
## Returns "" when the text isn't an order (normal chat proceeds), otherwise
## the advisor's acknowledgment (order executed or plainly refused).
func try_order(unit: Dictionary, text: String) -> String:
	if _gs == null or unit.is_empty():
		return ""
	var t := _norm(text)
	if t == "":
		return ""
	# Foreign cabinet: orders are refused, in their leader's voice.
	if is_foreign_cabinet(_gs, unit):
		if _looks_like_order(t):
			var f := String(unit.get("faction", ""))
			return SimFactionLeaders.control_refusal_line(f)
		return ""
	if not is_cabinet(_gs, unit):
		return ""
	# Pending war-counsel states: "accept"/"deny" answers them, most recent
	# first — a peace-terms counter, then an advisor debate, then a plea.
	# (Lane 2: counters and debates are answered in the advisor's thread
	# exactly like pleas.)
	var counter := _pending_counter_for(int(unit.get("id", 0)))
	if not counter.is_empty():
		var verdict_c := _parse_plea_verdict(t)
		if verdict_c != "":
			return _answer_counter(unit, counter, verdict_c)
	var debate := _pending_debate_for(int(unit.get("id", 0)))
	if not debate.is_empty():
		var verdict_d := _parse_plea_verdict(t)
		if verdict_d != "":
			return _answer_debate(unit, debate, verdict_d)
	var plea := _pending_plea_for(int(unit.get("id", 0)), t)
	if not plea.is_empty():
		if bool(plea.get("ambiguous", false)):
			# 2026-10-09 wake: several wars plead at once — ask WHICH war
			# instead of answering the first one in dict order.
			return _fill(unit, "Which war, {ruler}? I carry pleas for %s — name the foe." % _plea_foe_list(plea))
		var verdict := _parse_plea_verdict(t)
		# Lane 1: a verdict naming a DIFFERENT faction is a new order, not
		# an answer ("make peace with the gnomes" during an elves plea).
		if verdict != "" and not _plea_redirect(t, plea):
			return _answer_plea(unit, plea, verdict)
	# Jeremy 2026-10-11 (proactive advisors): "yes"/"no" answers the
	# pending offer from THIS advisor. A real order ("raise taxes") wins
	# over an answer and falls through to normal dispatch.
	var pro := _pending_proactive_for(int(unit.get("id", 0)))
	if not pro.is_empty() and _match_order(t) == "":
		var verdict_p := _parse_plea_verdict(t)
		if verdict_p != "":
			return _answer_proactive(unit, pro, verdict_p)
	# Lane 1: a pending clarifying question — answer it, or drop it in
	# favor of a fresh order.
	var ctx := _clarification_for(unit)
	if not ctx.is_empty():
		if _answers_clarification(ctx, t):
			return _answer_clarification(unit, ctx, t)
		if _match_order(t) != "" or _match_status(t) != "":
			_clarifications.erase(str(int(unit.get("id", 0))))
		else:
			return _fill(unit, String(ctx.get("question", "")))
	# Lane 1: multi-part commands ("train 10 soldiers and build 3 farms",
	# "raise taxes and hold a festival").
	# Jeremy 2026-10-11: dialogue trees — topic menus and follow-ups run
	# BEFORE order dispatch, but never swallow real orders or status
	# queries (_try_dialogue returns "" for those and they fall through).
	var dlg := _try_dialogue(unit, t)
	if dlg != "":
		return dlg
	var parts := _parse_multi_part(t)
	if parts.size() > 1:
		var all_orders := true
		for p2: String in parts:
			if _match_order(p2) == "" and _match_status(p2) == "":
				all_orders = false
				break
		if all_orders:
			return _order_multi(unit, parts)
	return _dispatch_order(unit, t)


## Quick pre-check: does this even smell like an order? (Used for foreign
## refusal so small talk with a foreign advisor doesn't get slapped down.)
func _looks_like_order(t: String) -> bool:
	return _match_order(t) != ""


## Dispatch text to an order family. Returns family id or "".
func _match_order(t: String) -> String:
	# Jeremy 2026-10-11 (envoys): "tell the guild master to prioritize
	# weapons". First so "tell the war advisor to attack" doesn't route as
	# an attack order.
	if t.begins_with("tell ") or t.begins_with("go tell ") \
			or t.contains(" go tell "):
		return "envoy"
	# War/attack first: "attack the elves" must not fall into chat.
	if _has_any(t, ["declare war", "attack the", "attack ", "invade ",
			"invade the", "conquer ", "destroy the elves",
			"destroy the humans", "destroy the ogres",
			"destroy the undead"]):
		if _faction_in(t) != "":
			return "war"
	# Jeremy 2026-10-11: raids ("raid their mines") — _order_war resolves
	# the foe from the active wars when none is named.
	if t.contains("raid ") or t.begins_with("raid"):
		return "war"
	# Military muster/stance/retreat/patrol/guard. (Lane 1: retreat, patrol
	# detachments, and monastery guards route here.)
	if _has_any(t, ["muster", "rally the troops", "gather the troops",
			"stand down", "demobilize", "prepare for war",
			"ready the army", "ready for war", "mobilize",
			"retreat", "fall back", "pull back", "withdraw",
			"patrol ", "patrols", "a patrol", "the patrol", "stop patrol",
			"recall patrol", "recall the patrol", "end patrol",
			"guard the monastery", "guard monastery",
			"defend the monastery", "protect the monastery",
			"guard our monastery",
			"defend ", "defend the", "hold the", "hold position"]):
		return "military"
	# Build.
	if _has_any(t, ["star fort", "starfort", "star-fort"]):
		return "build"
	if _has_any(t, ["build ", "construct ", "erect ", "put up "]):
		if _building_in(t) != "":
			return "build"
	if t.contains("we need more") and _building_in(t) != "":
		return "build"
	# Train / recruit / hire.
	if _has_any(t, ["train ", "recruit ", "hire ", "draft "]):
		if _job_in(t) != "":
			return "train"
	# Economy: taxes + workforce focus + laws (Jeremy 2026-10-11).
	if t.contains("tax") \
			or _has_any(t, ["gambling", "alehouse", "tavern", "dueling", "duel"]):
		return "economy"
	if _has_any(t, ["focus on ", "we need more wood", "we need more food",
			"we need more gold", "prioritize "]):
		return "economy"
	# Civic: festival + walls + curfew + borders (Jeremy 2026-10-11).
	if _has_any(t, ["festival", "feast", "celebration", "hold a party",
			"throw a party", "curfew", "border", "borders"]):
		return "civic"
	if _has_any(t, ["raise the walls", "build walls", "build the walls",
			"fortify", "wall the town", "walls up", "wall around",
			"walls around", "wall my town", "build a wall"]):
		return "civic"
	# Lane 2 (war counsel): peace-terms negotiation and the multi-war
	# dashboard. These sit AFTER the war/military branches so "declare war"
	# and "prepare for war" keep their existing routing.
	if _has_any(t, ["offer peace", "propose peace", "peace terms",
			"sue for peace", "demand tribute", "buy peace",
			"pay them off"]):
		return "peaceterms"
	if t.contains("wars") or _has_any(t, ["war report", "war status",
			"how goes the war", "battle report"]):
		return "wardashboard"
	# Jeremy 2026-10-11 (advisor dialogue trees): trade-deal commands and
	# deal questions. Sits after war/military/build/train/economy/civic so
	# those keep priority ("cancel the festival" stays civic). Routed in
	# _dispatch_order -> _order_deals: the Treasury advisor executes, other
	# advisors redirect to the Treasury desk in-voice. Foreign cabinets
	# refuse via _looks_like_order (sovereignty).
	if _has_any(t, ["how are my deals", "deal status", "deals report",
			"trade report", "show me the ledger", "handle my trades",
			"auto trade", "manage my deals", "stop trading",
			"stop auto trade", "cancel the", "cancel deal",
			"accept the counter", "take the counter",
			"decline the counter", "trade with the", "trade with ",
			"what should i trade", "trade advice"]):
		return "deals"
	# Lane 1 (Ruler's Voice expansion): diplomacy verbs, scouting. These
	# sit AFTER Lane 2's peace-terms/dashboard branches so those keep
	# their routing ("sue for peace" stays peaceterms; "make peace" opens
	# the proposal flow here).
	if _has_any(t, ["make peace", "end the war", "ceasefire", "cease-fire",
			"cease fire", "peace talks", "peace with"]):
		return "peace"
	if t.contains("tribute") and not t.contains("demand"):
		return "tribute"
	if _has_any(t, ["threaten ", "issue a threat", "send a threat",
			"threat to "]):
		return "threat"
	if t.begins_with("scout ") or t == "scout" \
			or t.contains(" scout the ") or t.contains("send scouts"):
		return "scout"
	return ""


## --- text helpers ---------------------------------------------------------

static func _norm(text: String) -> String:
	var t := text.to_lower()
	for c: String in [".", ",", "!", "?", ";", ":", "\"", "'"]:
		t = t.replace(c, "")
	return " ".join(t.split(" ", false))


static func _has_any(t: String, words: Array) -> bool:
	for w: String in words:
		if t.contains(String(w)):
			return true
	return false


static func _building_in(t: String) -> String:
	# Longest match first ("oil pump" before "pump").
	var keys: Array = BUILD_NOUNS.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for k: String in keys:
		if t.contains(" " + k) or t.begins_with(k + " ") or t == k:
			return String(BUILD_NOUNS[k])
	return ""


static func _job_in(t: String) -> String:
	return String(TRAIN_NOUNS.get(_job_noun_in(t), ""))


## The matched noun key itself ("warriors"), for echoing the player's words.
static func _job_noun_in(t: String) -> String:
	var keys: Array = TRAIN_NOUNS.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for k: String in keys:
		if t.contains(" " + k) or t.begins_with(k + " ") or t == k:
			return k
	return ""


static func _faction_in(t: String) -> String:
	for k: String in FACTION_NOUNS:
		if t.contains(k):
			return String(FACTION_NOUNS[k])
	return ""


## Resolve a faction noun ("elf") to the real active faction id ("elves").
func _faction_id(noun: String) -> String:
	for f: String in _gs.active_factions:
		if f == noun or _singular(f) == noun:
			return f
	return noun


static func _count_in(t: String) -> int:
	var m := RegEx.new()
	m.compile("\\b(\\d+)\\b")
	var r := m.search(t)
	if r != null:
		return maxi(1, mini(20, int(r.get_string(1))))
	for w: String in t.split(" "):
		if NUMBER_WORDS.has(w):
			return int(NUMBER_WORDS[w])
	return 1


func _ruler() -> String:
	var rn = _gs.get("ruler_name")
	return String(rn) if rn != null and String(rn) != "" else "sire"


## Policies live on the royal court (court_sys.policies).
func _policies():
	var court = _gs.get("court_sys")
	if court == null:
		return null
	return court.get("policies")


func _pf() -> String:
	return String(_gs.player_faction)


## Faction id -> singular noun ("elves" -> "elf", "humans" -> "human").
static func _singular(f: String) -> String:
	if f == "elves":
		return "elf"
	if f == "undead":
		return f
	if f.ends_with("s"):
		return f.substr(0, f.length() - 1)
	return f


## Player faction singular for comparing against FACTION_NOUNS values.
func _pf_singular() -> String:
	return _singular(_pf())


## --- build orders ---------------------------------------------------------
## "build 3 farms", "construct a barracks", "we need more houses".

func _order_build(unit: Dictionary, t: String) -> String:
	# Jeremy 2026-10-06 (lane 7): a star fort is a fortified military base,
	# not a single building type — it goes through its own order path
	# (explicit player order only; the AI tick never auto-builds for the
	# player faction).
	if _has_any(t, ["star fort", "starfort", "star-fort"]):
		return _order_star_fort(unit, t)
	var btype := _building_in(t)
	if btype == "" or not SimBuildings.is_building(btype):
		return _fill(unit, "{ruler}, point me at something real — 'build 3 farms', 'construct a barracks', that sort of thing.")
	# Lane 1: town-aware builds. One town -> just build; several and no
	# town named -> ask which town, hold the order, resume on the answer.
	var towns := _pf_towns()
	if towns.is_empty():
		return _fill(unit, "We've no town to build in yet, {ruler}. Found one first and I'll break ground.")
	var town := _town_named(t)
	if town.is_empty() and towns.size() > 1:
		var n := _count_in(t)
		var bname0: String = String(SimBuildings.BUILDINGS[btype].get("name", btype))
		var what := _plural(bname0, n).to_lower()
		if n == 1:
			what = "the " + bname0.to_lower()
		return _ask_clarification(unit, "build",
			"Which town gets %s, {ruler}? We hold %s — name one." % [what, _join_names(_town_names(towns))],
			{"text": t})
	if town.is_empty():
		town = towns[0]
	return _execute_build(unit, t, town)


## --- star fort orders (Jeremy 2026-10-06, lane 7) -----------------------------
## "build a star fort" / "build a star fort at <town>". The player's explicit
## order is the only way a fort rises for the player faction (the AI tick in
## StarFortBases skips the player — sovereignty). Affordability is validated
## before promising; progress is tracked like any build order.

func _order_star_fort(unit: Dictionary, t: String) -> String:
	var pf := _pf()
	var town := _fort_town(t)
	if town.is_empty():
		return _fill(unit, "We've no town to raise a fort for yet, {ruler}. Found one first and I'll break ground.")
	var tid := int(town.get("id", -1))
	var tname := _town_name(town)
	var hall := _town_hall_of(tid)
	var hid := int(hall.get("id", -tid)) if not hall.is_empty() else -tid
	var hpos: Vector2 = town.get("position", Vector2.ZERO)
	if not hall.is_empty():
		hpos = hall.get("position", hpos)
	var sfb = _gs.get("starfort_bases")
	if sfb == null or not sfb.has_method("order_fort"):
		return _fill(unit, "The engineers haven't drawn up star forts yet, {ruler}. Give me a day.")
	var bs := SimBuildings.new(_gs)
	var res: Dictionary = sfb.order_fort(pf, hid, tid, hpos, bs,
		WallDrag.new())
	if not bool(res.get("ok", false)):
		match String(res.get("reason", "")):
			"has_fort":
				return _fill(unit, "We've already raised a star fort for %s, {ruler} — one per town, the engineers insist." % tname)
			"no_spot":
				return _fill(unit, "No clear ground around %s for a fort, {ruler} — lakes, hills, or neighbors in the way. Name another town." % tname)
			"broke":
				return _fill(unit, "The fort's beyond our coffers, {ruler} — the engineers want coin and timber stockpiled first.")
		return _fill(unit, "The fort wouldn't break ground, {ruler}. The engineers are being difficult.")
	var placed: Array = res.get("buildings", [])
	var ids: Array = []
	for b: Dictionary in placed:
		b["player_placed"] = true
		ids.append(int(b.get("id", -1)))
	_pending.append({
		"kind": "starfort",
		"advisor_id": int(unit.get("id", 0)),
		"advisor_name": String(unit.get("name", role_title(unit))),
		"town": tname,
		"ids": ids,
		"day_issued": int(_gs.get("day_number")),
	})
	return _fill(unit, "Star fort rising outside %s, {ruler} — walls, bastions, barracks, the works. The crews are moving." % tname)


## "build a star fort at <town>" -> that player town; else the home town.
func _fort_town(t: String) -> Dictionary:
	var at := t.find(" at ")
	if at >= 0:
		var want: String = t.substr(at + 4).strip_edges()
		for tid: Variant in _gs.towns:
			var town: Dictionary = _gs.towns[tid]
			if String(town.get("faction", "")) != _pf():
				continue
			var nm: String = _town_name(town).to_lower()
			if nm != "" and (want == nm or want.begins_with(nm) \
					or nm.contains(want)):
				return town
	return _home_town()


static func _town_name(town: Dictionary) -> String:
	return str(town.get("name", town.get("town_name", "town")))


## The completed (or rising) claim building of a town.
func _town_hall_of(town_id: int) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if int(b.get("town_id", -1)) != town_id:
			continue
		if String(b.get("type", "")) in SimTerritory.CLAIM_TYPES:
			return b
	return {}
## Suggest something buildable when the ask is unaffordable.

func _affordable_alt(want_type: String) -> String:
	var res = _gs.get("resources")
	var want_cost: float = _cost_total(SimBuildings.cost_of(want_type))
	var best := ""
	var best_cost := -1.0
	for btype: String in ["farm", "house", "well", "lumber_camp", "storage"]:
		var c: Dictionary = SimBuildings.cost_of(btype)
		if res.can_afford(_pf(), c):
			var tot := _cost_total(c)
			if tot > best_cost and tot < want_cost:
				best_cost = tot
				best = String(SimBuildings.BUILDINGS[btype].get("name", btype))
	return best


static func _cost_total(cost: Dictionary) -> float:
	var tot := 0.0
	for k: String in cost:
		tot += float(cost[k])
	return tot


static func _plural(word: String, n: int) -> String:
	# Minimal pluralization for ack lines ("1 farm" / "3 farms").
	if n == 1:
		return "1 " + word
	if word == "is":
		return "%d are" % n
	if word.ends_with("y") and not word.ends_with("ay") \
			and not word.ends_with("ey"):
		return "%d %sies" % [n, word.substr(0, word.length() - 1)]
	if word.ends_with("s"):
		return "%d %s" % [n, word]
	return "%d %ss" % [n, word]


func _home_town() -> Dictionary:
	for tid: Variant in _gs.towns:
		var town: Dictionary = _gs.towns[tid]
		if String(town.get("faction", "")) == _pf():
			return town
	return {}


## Spiral out from the town center for blueprint spots.
static func _find_spot(center: Vector2, i: int) -> Vector2:
	var ring := 1 + i / 6
	var ang := float(i % 6) * TAU / 6.0 + float(ring) * 0.35
	return center + Vector2(cos(ang), sin(ang)) * (180.0 * float(ring))


func _track_build_order(unit: Dictionary, btype: String, bname: String,
		ids: Array) -> void:
	_pending.append({
		"kind": "build",
		"advisor_id": int(unit.get("id", 0)),
		"advisor_name": String(unit.get("name", role_title(unit))),
		"btype": btype, "bname": bname, "ids": ids.duplicate(),
		"day_issued": int(_gs.get("day_number")),
	})


## --- train orders ---------------------------------------------------------
## "train 10 soldiers", "recruit workers", "hire more woodcutters".
## Count-less "recruit more X" sets the guild's ongoing priority (HTML
## parity with the old guild-master command); a count queues real training.

func _order_train(unit: Dictionary, t: String) -> String:
	var noun := _job_noun_in(t)
	var job := String(TRAIN_NOUNS.get(noun, ""))
	if job == "":
		return _fill(unit, "{ruler}, train WHAT? 'Train 10 soldiers', 'hire woodcutters' — give me a trade.")
	var hiring = _gs.get("hiring")
	if hiring == null:
		return _fill(unit, "The guild hall's gone quiet, {ruler}. No hiring office to speak of.")
	var want := _count_in(t)
	var counted := _has_count_word(t)
	var b := _trainer_for(job)
	if b.is_empty():
		# No trainer building: set the priority anyway (the guild will get
		# there) and say what's missing.
		hiring.set_recruit_priority(_pf(), job)
		return _fill(unit, "We'll prioritize %s, {ruler} — but we've no hall that trains them yet. Build the right hall and I'll fill it." % noun)
	var queued := 0
	for i: int in want:
		if bool(hiring.queue_training(b, job, true)):
			queued += 1
		else:
			break
	hiring.set_recruit_priority(_pf(), job)
	if queued == 0:
		var block := String(hiring.get("last_train_block", ""))
		var why := "the queue's full or the purse is light"
		if block == "type_capped":
			why = "we're at the cap for %s" % _plural(job, 2).substr(2)
		elif block == "unaffordable":
			why = "we can't afford the training fees"
		return _fill(unit, "Can't train %s right now, {ruler} — %s." % [_plural(job, want).substr(2), why])
	if not counted:
		return _fill(unit, "Done, {ruler} — the guild will prioritize %s from here on." % noun)
	_track_train_order(unit, job, queued)
	return _fill(unit, "%s, {ruler} — training's queued, boots by week's end." % _plural(job, queued).capitalize())


func _has_count_word(t: String) -> bool:
	var m := RegEx.new()
	m.compile("\\b\\d+\\b")
	if m.search(t) != null:
		return true
	for w: String in t.split(" "):
		if NUMBER_WORDS.has(w):
			return true
	return false


## A complete, alive faction building that can train this job.
func _trainer_for(job: String) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != _pf():
			continue
		if GuildHiring.can_train(String(b.get("type", "")), job):
			return b
	return {}


func _track_train_order(unit: Dictionary, job: String, queued: int) -> void:
	var have := 0
	if _gs.get("population") != null:
		have = int(_gs.population.count_job(_pf(), job))
	_pending.append({
		"kind": "train",
		"advisor_id": int(unit.get("id", 0)),
		"advisor_name": String(unit.get("name", role_title(unit))),
		"job": job, "want": have + queued, "have0": have,
		"day_issued": int(_gs.get("day_number")),
	})


## --- military orders ------------------------------------------------------

func _order_military(unit: Dictionary, t: String) -> String:
	var army = _gs.get("army")
	if army == null:
		return _fill(unit, "No army to command, {ruler}. Raise one first.")
	# Lane 1: monastery guard, patrols, retreat.
	if _has_any(t, ["guard the monastery", "guard monastery",
			"defend the monastery", "protect the monastery",
			"guard our monastery"]):
		return _order_guard_monastery(unit, t)
	if t.contains("patrol"):
		return _order_patrol(unit, t)
	if _has_any(t, ["retreat", "fall back", "pull back", "withdraw"]):
		var pulled: int = int(army.order_retreat(_pf()))
		if pulled == 0:
			return _fill(unit, "No field army to pull back, {ruler} — the troops are already home or already dead.")
		return _fill(unit, "Sounding the retreat, {ruler} — %s fall back to the hall. Live to fight ugly another day." % _plural("troop", pulled))
	if t.contains("stand down") or t.contains("demobilize"):
		army.set_stance(_pf(), "guard")
		return _fill(unit, "Standing down, {ruler}. Troops hold their posts — no marching, no trouble.")
	if _has_any(t, ["prepare for war", "ready the army", "ready for war",
			"mobilize"]):
		var drafted: int = int(army.draft(_pf(), 10))
		var n: int = int(army.muster(_pf()))
		if n == 0 and drafted == 0:
			return _fill(unit, "There's no army to ready, {ruler}. Train soldiers first and I'll muster them.")
		return _fill(unit, "War footing, {ruler} — %s mustered%s. Say the word." % [_plural("troop", n).capitalize(), (" (%d fresh drafts)" % drafted) if drafted > 0 else ""])
	# Jeremy 2026-10-11: defensive orders — "defend the north pass".
	if t.contains("defend") or t.contains("hold the") or t.contains("hold position"):
		var n3: int = int(army.muster(_pf()))
		army.set_stance(_pf(), "guard")
		if n3 == 0:
			return _fill(unit, "No troops to post, {ruler} — train soldiers first, then we'll hold anything.")
		return _fill(unit, "The troops dig in, {ruler} — %s holding ground. Nothing passes without bleeding for it." % _plural("troop", n3))
	# muster / rally
	var n2: int = int(army.muster(_pf()))
	if n2 == 0:
		return _fill(unit, "Mustered the fields, {ruler} — nobody came. We need soldiers before we need parades.")
	return _fill(unit, "%s, {ruler} — mustered and bristling." % _plural("troop", n2).capitalize())


## War/attack orders: ALWAYS through the strategic-proposal confirm.
## Never a surprise war. Jeremy 2026-10-11: once AT war, attack orders
## ("attack the elf border town", "raid their mines") execute for real via
## deploy_for_war — the advisor commands, the army marches.
func _order_war(unit: Dictionary, t: String) -> String:
	var target := _faction_in(t)
	if target == "":
		# "raid their mines" — no faction named: resolve from the wars
		# we're actually fighting. Exactly one foe -> that's the target.
		var foes: Array = []
		for f: String in _gs.active_factions:
			if f != _pf() and _at_war_with(f):
				foes.append(f)
		if foes.size() == 1:
			target = String(foes[0])
	if target == "":
		return _fill(unit, "{ruler}, attack WHOM? Name a faction and I'll bring the war council's papers.")
	if target == _pf() or target == _pf_singular():
		return _fill(unit, "Attack OURSELVES, {ruler}? Bold. Stupid, but bold. Pick an enemy.")
	target = _faction_id(target)
	var dip = _gs.get("diplomacy")
	var fname: String = String(Config.FACTIONS.get(target, {}).get("name", target.capitalize()))
	if dip != null and dip.has_method("relation_state"):
		var rel := String(dip.relation_state(_pf(), target))
		if rel == "war":
			# Attack order against a foe we're already fighting: EXECUTE.
			var army2 = _gs.get("army")
			if army2 != null and army2.has_method("deploy_for_war"):
				var n: int = int(army2.deploy_for_war(_pf(), target))
				if n == 0:
					return _fill(unit, "No field army to send, {ruler} — train soldiers first, then we'll make it ugly.")
				var verb := "marches"
				if t.contains("raid"):
					verb = "rides out raiding"
				return _fill(unit, "The host %s, {ruler} — %s bound for %s holdings. I'll bring word of how it goes." \
					% [verb, _plural("troop", n).capitalize(), fname])
			return _fill(unit, "We're ALREADY at war with them, {ruler}. The troops are way ahead of you.")
	var prop = _gs.get("proposals")
	if prop == null:
		return _fill(unit, "The war council's out to lunch, {ruler}. Try again shortly.")
	# The advisor makes the strategic case — and questions a bad war.
	var brief: Dictionary = strategic_brief(target)
	var caution := ""
	if bool(brief.get("unwise", false)) and String(brief.get("text", "")) != "":
		caution = " Sire, are you SURE? %s" % String(brief.get("text", ""))
	var details := {"target": target}
	if String(brief.get("text", "")) != "":
		details["brief"] = String(brief.get("text", ""))
	var res: Dictionary = prop.propose(_pf(), "declare_war", details)
	if not bool(res.get("ok", false)):
		return _fill(unit, "The council won't put it to paper right now, {ruler} — try again in a few days.")
	# The proposal emits bus.strategic_proposal -> phone confirm modal.
	# Nothing moves until the ruler taps Approve.
	return _fill(unit, "As you command, {ruler}. The war council has drawn up the declaration against the %s — it's on your phone awaiting YOUR seal. Nothing marches until you approve.%s" % [fname, caution])


## --- economy orders -------------------------------------------------------
## "raise taxes", "lower taxes", "set taxes to 15", "focus on food",
## "we need more wood", "legalize gambling" (Jeremy 2026-10-11).

func _order_economy(unit: Dictionary, t: String) -> String:
	var pol = _policies()
	var hiring = _gs.get("hiring")
	# Laws first: "legalize gambling" / "ban gambling" / "outlaw dueling".
	if _has_any(t, ["gambling", "alehouse", "tavern", "dueling", "duel"]):
		return _order_law(unit, t)
	# Jeremy 2026-10-11: plague doctrine by spoken order — "quarantine the
	# sick", "cull the sick", "treat the sick", "save them all".
	if _has_any(t, ["plague", "sick", "quarantine", "pandemic", "disease"]):
		return _order_plague(unit, t)
	if t.contains("tax"):
		if pol == null:
			return _fill(unit, "No treasury to tax from, {ruler}.")
		var cur := int((pol.get("state") as Dictionary).get("tax", 10)) \
			if pol.get("state") is Dictionary else 10
		var want := cur
		var m := RegEx.new()
		m.compile("(\\d+)\\s*%?")
		var r := m.search(t)
		if r != null:
			want = int(r.get_string(1))
		elif t.contains("raise") or t.contains("increase") or t.contains("higher"):
			want = cur + 5
		elif t.contains("lower") or t.contains("decrease") or t.contains("cut") \
				or t.contains("reduce"):
			want = cur - 5
		else:
			return _fill(unit, "Taxes stand at %d%%, {ruler}. Say 'raise taxes', 'lower taxes', or 'set taxes to 15'." % cur)
		pol.set_tax(want)
		var nv := int((pol.get("state") as Dictionary).get("tax", want)) \
			if pol.get("state") is Dictionary else want
		if nv == cur:
			return _fill(unit, "Taxes are already %d%%, {ruler}. The coffers nod along." % cur)
		var dir := "raised" if nv > cur else "lowered"
		return _fill(unit, "Taxes %s to %d%%, {ruler}. The treasury %s." % [dir, nv, "swells" if nv > cur else "breathes easier"])
	# Workforce focus.
	var job := ""
	if t.contains("food"):
		job = "farmer"
	elif t.contains("wood"):
		job = "woodcutter"
	elif t.contains("gold"):
		job = "miner"
	if job == "":
		return _fill(unit, "{ruler}, focus our labor on WHAT? 'Focus on food', 'we need more wood' — that sort of thing.")
	if hiring != null:
		hiring.set_recruit_priority(_pf(), job)
	var jname := _plural(job, 2).substr(2)
	return _fill(unit, "Heard, {ruler} — every spare hand leans toward %s. The guild's on it." % jname)


## --- plague doctrine orders -------------------------------------------------
## "quarantine the sick", "cull the sick", "treat the sick", "save them all"
## (Jeremy 2026-10-11). Spoken doctrine changes go through the real policy
## setter — Gazette story, sim hookup, changeable mid-outbreak.

func _order_plague(unit: Dictionary, t: String) -> String:
	var pol = _policies()
	if pol == null or not pol.has_method("set_plague_policy"):
		return _fill(unit, "No policy desk to write the doctrine on, {ruler}.")
	var want := ""
	if _has_any(t, ["save them all", "mercy", "spare them", "no executions"]):
		want = "mercy"
	elif _has_any(t, ["military cull", "soldiers", "put them down", "execute them",
			"kill the sick", "cull the sick"]):
		want = "cull_military"
	elif _has_any(t, ["doctor", "quietly", "mercy killing"]):
		want = "cull_doctor"
	elif _has_any(t, ["quarantine", "round them up", "isolate"]):
		want = "quarantine"
	elif _has_any(t, ["treat", "cure", "heal the sick", "doctors"]):
		want = "cure"
	elif _has_any(t, ["do nothing", "ignore", "let it run"]):
		want = "ignore"
	if want == "":
		var cur: String = pol.plague_policy() if pol.has_method("plague_policy") else "mercy"
		var cname := String((SimPolicies.PLAGUE_POLICIES.get(cur, {}) as Dictionary).get("name", cur))
		return _fill(unit, "The doctrine stands at %s, {ruler}. Say 'quarantine the sick', 'treat the sick', 'save them all' — or 'cull the sick' if you're feeling medieval." % cname)
	if not pol.set_plague_policy(want):
		return _fill(unit, "That is already the doctrine, {ruler}. The realm holds its breath either way.")
	var dname := String((SimPolicies.PLAGUE_POLICIES.get(want, {}) as Dictionary).get("name", want))
	var line := "It is done, {ruler} — the doctrine is now %s." % dname
	match want:
		"cull_military", "cull_doctor":
			line += " The Gazette will print it. History will too. Sleep well."
		"mercy":
			line += " No executions. The healers have their orders, and my conscience has its rest."
		"quarantine":
			line += " The sick go to the clinics. The healthy stay that way."
	return _fill(unit, line)


## --- civic orders ---------------------------------------------------------
## "hold a festival", "raise the walls", "impose a curfew",
## "close the borders" (Jeremy 2026-10-11).

func _order_civic(unit: Dictionary, t: String) -> String:
	if _has_any(t, ["festival", "feast", "celebration", "party"]):
		return _order_festival(unit)
	if t.contains("border"):
		return _order_borders(unit, t)
	if t.contains("curfew"):
		return _order_curfew(unit, t)
	return _order_walls(unit)


func _order_festival(unit: Dictionary) -> String:
	var pol = _policies()
	if pol == null:
		return _fill(unit, "No one to throw a festival with, {ruler}.")
	var towns: Array = []
	for tid: Variant in _gs.towns:
		var town: Dictionary = _gs.towns[tid]
		if String(town.get("faction", "")) == _pf():
			towns.append(town)
	if towns.is_empty():
		return _fill(unit, "We've no town to feast in, {ruler}.")
	var town: Dictionary = towns[0]
	var msg: String = String(pol.schedule_festival(int(town.get("id", -1)), 3))
	if msg.contains("cooldown") or msg.contains("already") \
			or msg.contains("Not enough") or msg.contains("No towns"):
		return _fill(unit, "%s {ruler}." % msg)
	return _fill(unit, "A festival in %s, three days hence! Pies, dancing, questionable marriages — {ruler}, it'll be glorious. %s" % [String(town.get("name", "town")), msg])


func _order_walls(unit: Dictionary) -> String:
	var bw = _gs.get("border_walls")
	if bw == null:
		return _fill(unit, "No border survey exists, {ruler}. The engineers are still arguing about maps.")
	var regions: Array = []
	for e: Dictionary in bw.pending:
		if String(e.get("faction", "")) == _pf():
			var rn := String(e.get("region_name", ""))
			if rn != "" and not regions.has(rn):
				regions.append(rn)
	if regions.is_empty():
		return _fill(unit, "No border line awaits your word, {ruler} — when the surveyors mark one, it'll come straight to your phone.")
	for rn: String in regions:
		_gs.bus.wall_answer.emit(rn, true)
	return _fill(unit, "Walls going up around %s, {ruler}. The crews are marching with stone." % ", ".join(regions))


## Jeremy 2026-10-11: laws through the phone — "legalize gambling".
## The advisor explains the consequence, then uses the REAL policy system.
func _order_law(unit: Dictionary, t: String) -> String:
	var pol = _policies()
	if pol == null or not pol.has_method("set_law"):
		return _fill(unit, "No lawbooks handy, {ruler}.")
	var key := ""
	if t.contains("gambling"):
		key = "gambling"
	elif t.contains("alehouse") or t.contains("tavern") or t.contains("ale"):
		key = "alehouses"
	elif t.contains("duel"):
		key = "dueling"
	if key == "":
		return _fill(unit, "{ruler}, WHICH law? Gambling, alehouses, dueling — name your vice.")
	var allow := true
	if t.contains("ban") or t.contains("outlaw") or t.contains("forbid") \
			or t.contains("illegal"):
		allow = false
	var cur: bool = pol.law_allowed(key)
	if cur == allow:
		return _fill(unit, "%s is already %s, {ruler}. The law sleeps soundly." \
			% [key.capitalize(), "legal" if allow else "banned"])
	var counsel := {
		"gambling": "The priests will clutch their pearls, but the tax men will smile — dice halls pay the crown handsomely, and the desperate pay most.",
		"alehouses": "Every town gets a proper tavern. The bards approve; the constables sigh.",
		"dueling": "Settle it with steel at dawn, legally. The surgeons are thrilled. The widows, less so.",
	}
	if not pol.set_law(key, allow):
		return _fill(unit, "The clerks blocked it, {ruler} — the decree fee's beyond us, or the ink ran dry.")
	var why := String(counsel.get(key, ""))
	if not allow:
		why = "The dens close their doors. Virtue reigns. The treasury weeps, quietly."
	return _fill(unit, "Done, {ruler} — %s %s. %s" \
		% [key.capitalize(), "legalized" if allow else "outlawed", why])


## Jeremy 2026-10-11: borders through the phone — "close the borders".
func _order_borders(unit: Dictionary, t: String) -> String:
	var pol = _policies()
	if pol == null or not pol.has_method("set_borders"):
		return _fill(unit, "No border office to command, {ruler}.")
	var want := ""
	if t.contains("close") or t.contains("shut") or t.contains("seal"):
		want = "closed"
	elif t.contains("open"):
		want = "open"
	if want == "":
		var cur := String((pol.get("state") as Dictionary).get("borders", "open")) \
			if pol.get("state") is Dictionary else "open"
		return _fill(unit, "The borders stand %s, {ruler}. Say 'close the borders' or 'open the borders'." % cur)
	if pol.set_borders(want):
		return _fill(unit, "Borders %s, {ruler}. %s" % [want,
			"The gates clang shut. None pass without the crown's seal." if want == "closed"
			else "Traders and strangers stream through the gates."])
	return _fill(unit, "The border office balked, {ruler} — likely the decree fee. The coffers are a harsh mistress.")


## Jeremy 2026-10-11: curfew through the phone — "impose a curfew".
func _order_curfew(unit: Dictionary, t: String) -> String:
	var pol = _policies()
	if pol == null or not pol.has_method("toggle_curfew"):
		return _fill(unit, "No curfew bell to ring, {ruler}.")
	var was := bool((pol.get("state") as Dictionary).get("curfew", false)) \
		if pol.get("state") is Dictionary else false
	var want := not was
	if t.contains("lift") or t.contains("end") or t.contains("repeal"):
		want = false
	elif t.contains("impose") or t.contains("declare") or t.contains("start"):
		want = true
	if want == was:
		return _fill(unit, "Curfew's already %s, {ruler}." % ("imposed" if was else "lifted"))
	if pol.toggle_curfew():
		return _fill(unit, "Curfew imposed, {ruler} — none on the streets after dark." if want
			else "Curfew lifted, {ruler} — the night belongs to everyone again.")
	return _fill(unit, "The clerks blocked it, {ruler}. Paperwork. Always paperwork.")


## --- report-back ----------------------------------------------------------
## Pending build/train orders are polled on day change; the advisor DMs the
## ruler when done or when blocked. Rides phone.npc_message (blocked threads
## stay silent).

func _on_day(_day_number: int, _is_night: bool) -> void:
	_check_proactive()  # Jeremy 2026-10-11: advisors come to YOU first
	_abus_dispatch()  # Jeremy 2026-10-11: inter-advisor message bus
	_poll_envoys()  # Jeremy 2026-10-11: envoy report-backs
	_check_war_losses()
	_abus_briefings()  # Jeremy 2026-10-11: advisors brief each other
	_check_peace_terms()  # Lane 2: envoys return with AI answers
	_patrol_tick()  # Lane 1: patrol detachments walk their routes
	if _pending.is_empty():
		return
	var phone = _gs.get("phone_sys")
	var done: Array = []
	for o: Dictionary in _pending:
		var res := _poll_order(o)
		if res == "":
			continue
		if phone != null:
			phone.npc_message(int(o.get("advisor_id", 0)), res)
		done.append(o)
	for o: Dictionary in done:
		_pending.erase(o)


func _poll_order(o: Dictionary) -> String:
	var kind := String(o.get("kind", ""))
	if kind == "build":
		return _poll_build(o)
	if kind == "starfort":
		return _poll_starfort(o)
	if kind == "train":
		return _poll_train(o)
	if kind == "scout":  # Lane 1
		return _poll_scout(o)
	if kind == "guard_post":  # Lane 1
		return _poll_guard_post(o)
	return ""


func _poll_build(o: Dictionary) -> String:
	var ids: Array = o.get("ids", [])
	var alive_ok := 0
	var destroyed := 0
	for b: Dictionary in _gs.buildings:
		var bid := int(b.get("id", -1))
		if not ids.has(bid):
			continue
		if not bool(b.get("alive", false)):
			destroyed += 1
		elif bool(b.get("complete", false)):
			alive_ok += 1
	var total := ids.size()
	if destroyed > 0 and alive_ok + destroyed >= total:
		return "Bad news, %s — %d of the %s were destroyed before completion. The builders are furious." % [_ruler(), destroyed, String(o.get("bname", "buildings")).to_lower()]
	if alive_ok >= total:
		return "Done, %s — %s finished and standing. The builders want a bonus. They always want a bonus." % [_ruler(), _plural(String(o.get("bname", "building")), total).to_lower()]
	# Stall watchdog: 12 days with no progress -> report.
	var day := int(_gs.get("day_number"))
	if day - int(o.get("day_issued", day)) > 12:
		return "%s, those %s are stalled — no builders to spare, most likely. Say the word and I'll crack whips." % [_ruler().capitalize(), String(o.get("bname", "buildings")).to_lower()]
	return ""


## Pending star-fort order poll: the advisors report when the fort stands,
## was destroyed mid-build, or stalls (fort = dozens of blueprints, so the
## generic build poll would drown the message in counts).
func _poll_starfort(o: Dictionary) -> String:
	var ids: Array = o.get("ids", [])
	var total := ids.size()
	if total == 0:
		return ""
	var done := 0
	var destroyed := 0
	for b: Dictionary in _gs.buildings:
		var bid := int(b.get("id", -1))
		if not ids.has(bid):
			continue
		if not bool(b.get("alive", false)):
			destroyed += 1
		elif bool(b.get("complete", false)):
			done += 1
	var tname := String(o.get("town", "town"))
	if destroyed > 0 and done + destroyed >= total:
		return "Bad news, %s — the star fort at %s was destroyed before completion. The engineers are furious." % [_ruler(), tname]
	if done >= total:
		return "Done, %s — the star fort outside %s stands complete: walls, bastions, and guns. Try taking THAT." % [_ruler(), tname]
	# Stall watchdog: 12 days with nothing finished -> report.
	var day := int(_gs.get("day_number"))
	if day - int(o.get("day_issued", day)) > 12 and done == 0:
		return "%s, the star fort at %s is stalled — no builders to spare, most likely. Say the word and I'll crack whips." % [_ruler().capitalize(), tname]
	return ""


func _poll_train(o: Dictionary) -> String:
	var pop = _gs.get("population")
	if pop == null:
		return ""
	var job := String(o.get("job", ""))
	var want := int(o.get("want", 0))
	var have: int = int(pop.count_job(_pf(), job))
	if have >= want:
		return "Done, %s — the %s are trained and ready. Try not to get them killed immediately." % [_ruler(), _plural(job, 2).substr(2)]
	var day := int(_gs.get("day_number"))
	if day - int(o.get("day_issued", day)) > 10 and have <= int(o.get("have0", 0)):
		return "%s, training's stalled — no hall free or no coin for %s. The guild apologizes profusely." % [_ruler().capitalize(), _plural(job, 2).substr(2)]
	return ""


## --- persistence ----------------------------------------------------------

func to_dict() -> Dictionary:
	return {"pending": _pending.duplicate(true),
		"peace_pleas": _peace_pleas.duplicate(true),
		"wars": _wars.duplicate(true),
		"treasury_warned": _treasury_warned.duplicate(true),
		"war_debates": _war_debates.duplicate(true),
		"peace_terms": _peace_terms.duplicate(true),
		"peace_terms_done": _peace_terms_done.duplicate(true),
		"clarifications": _clarifications.duplicate(true),
		"patrols": _patrols.duplicate(true),
		"proactive": _proactive.duplicate(true),
		"proactive_cd": _proactive_cd.duplicate(true),
		"abus": _abus.duplicate(true),
		"abus_cd": _abus_cd.duplicate(true),
		"envoys": _envoys.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	_pending = (d.get("pending", []) as Array).duplicate(true)
	_peace_pleas = (d.get("peace_pleas", {}) as Dictionary).duplicate(true)
	_wars = (d.get("wars", {}) as Dictionary).duplicate(true)
	_treasury_warned = (d.get("treasury_warned", {}) as Dictionary).duplicate(true)
	_war_debates = (d.get("war_debates", {}) as Dictionary).duplicate(true)
	_peace_terms = (d.get("peace_terms", {}) as Dictionary).duplicate(true)
	_peace_terms_done = (d.get("peace_terms_done", {}) as Dictionary).duplicate(true)
	_clarifications = (d.get("clarifications", {}) as Dictionary).duplicate(true)
	_patrols = (d.get("patrols", {}) as Dictionary).duplicate(true)
	_proactive = (d.get("proactive", {}) as Dictionary).duplicate(true)
	_proactive_cd = (d.get("proactive_cd", {}) as Dictionary).duplicate(true)
	_abus = (d.get("abus", []) as Array).duplicate(true)
	_abus_cd = (d.get("abus_cd", {}) as Dictionary).duplicate(true)
	_envoys = (d.get("envoys", []) as Array).duplicate(true)


## --- ack fill -------------------------------------------------------------
## {ruler} -> ruler name. Light faction-voiced seasoning per advisor role.

func _fill(unit: Dictionary, line: String) -> String:
	var out := line.replace("{ruler}", _ruler())
	var nm := String(unit.get("name", ""))
	if nm != "":
		out = out.replace("{name}", nm)
	return out


## --- war counsel: losses, territory, command posts, treasury ----------------
## Jeremy 2026-10-06: the War Advisor's peace pleas are driven by LOSSES and
## TERRITORY — not raw strength ratios. A per-war "war score" (0..100+)
## combines:
##   1. casualties — military dead on each side (lopsided = losing)
##   2. command posts — towns, monasteries, dark crystals changing hands
##   3. territory — hall-claim counts shifting during the war
##   4. treasury drain — war burn rate vs runway (Treasury Advisor joins in)
## The military-strength ratio remains as a fallback. Every plea carries the
## actual strategic reasons (numbers, not verdicts). Tiers: 25 concerned,
## 55 urgent, 85 desperate. One plea per tier per war; a denial re-arms at
## the next worse tier. Accept executes the sue_for_peace outcome
## (diplomacy.offer_surrender — exactly what an approved proposal runs).
## The AI director's _maybe_sue_for_peace modal stays as the fallback (no
## living war advisor); once the advisor pleads, the plea IS the ask.

## "pf|foe" -> war record (see _new_war_record)
var _wars: Dictionary = {}

## "pf|foe" -> {tier:int, state:"pending"/"accepted"/"denied",
## advisor_id:int, foe:String, day:int}
var _peace_pleas: Dictionary = {}

## "pf|foe" -> day of last treasury warning (throttled)
var _treasury_warned: Dictionary = {}

## Lane 2 — "pf|foe" -> {state:"pending"/"accepted"/"denied", day:int,
## war_id:int, treasury_id:int, foe:String}. The advisor debate: the War
## Advisor wants to fight on while the Treasury Advisor says the coffers
## can't take it. A denial re-arms after 5 days if the drain persists.
var _war_debates: Dictionary = {}

## Lane 2 — "pf|foe" -> {foe, amount, counter_amount, advisor_id, day,
## state:"offered"/"counter"/"done"}. Player-dictated peace terms awaiting
## (or holding) the enemy's answer.
var _peace_terms: Dictionary = {}

## Lane 2 — "pf|foe" -> war start_day of the last answered terms offer.
## One answered offer per war (HTML agri62State.done parity).
var _peace_terms_done: Dictionary = {}


func _war_advisor() -> Dictionary:
	return _advisor_by_job("advisor_war")


func _treasury_advisor() -> Dictionary:
	return _advisor_by_job("advisor_economy")


func _advisor_by_job(job: String) -> Dictionary:
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != _pf():
			continue
		if String(u.get("job", "")) == job:
			return u
	return {}


## 2026-10-09 wake (Ruler's Voice no-dead-end audit): living cabinet
## speaker ids, highest office first. _advisor_by_job skips the dead, so
## every id here is a unit that can actually carry the ruler's news —
## promised answers never die in silence when one advisor falls.
func _living_cabinet_ids() -> Array:
	var ids: Array = []
	for job: String in ["advisor_war", "advisor_economy", "advisor_civic",
			"guild_master"]:
		var u: Dictionary = _advisor_by_job(job)
		if u.is_empty():
			continue
		var uid := int(u.get("id", 0))
		if uid != 0 and not ids.has(uid):
			ids.append(uid)
	return ids


func _at_war_with(foe: String) -> bool:
	var dip = _gs.get("diplomacy")
	if dip == null or foe == "":
		return false
	return dip.relation_state(_pf(), foe) == "war"


## --- casualty tracking ----------------------------------------------------
## bus.unit_killed fires per death with the killer's faction. Military dead
## on each side of a tracked war accumulate here.

func _on_unit_killed(unit_id: int, source_faction: String) -> void:
	if source_faction == "" or source_faction == "bleedout":
		return
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return
	if not JobDefs.is_military(String(u.get("job", ""))):
		return
	var victim := String(u.get("faction", ""))
	var pf := _pf()
	var foe := ""
	if victim == pf and _at_war_with(source_faction):
		foe = source_faction
	elif source_faction == pf and _at_war_with(victim):
		foe = victim
	else:
		return
	var key := "%s|%s" % [pf, foe]
	var rec: Dictionary = _wars.get(key, {})
	if rec.is_empty():
		rec = _new_war_record(foe)
		_wars[key] = rec
	if victim == pf:
		rec["ours_dead"] = int(rec.get("ours_dead", 0)) + 1
		_note_fallen(key, rec, u)  # Lane 2: name the notable dead
	else:
		rec["theirs_dead"] = int(rec.get("theirs_dead", 0)) + 1


## --- war records ----------------------------------------------------------

func _new_war_record(foe: String) -> Dictionary:
	return {
		"foe": foe,
		"start_day": int(_gs.get("day_number")),
		"ours_dead": 0, "theirs_dead": 0,
		"towns0": _town_factions(),
		"mons0": _mon_holders(),
		"crys0": _crys_holders(),
		"forts0": _fort_holders(),
		"halls0": _hall_counts(),
		"gold_hist": [_treasury()],
		# Lane 2: notable-fallen watch, exhaustion flag, peace authorship,
		# and score memory (dashboard trend).
		"fallen": [], "fallen_report_day": -99,
		"we_sued": false, "exhausted": false,
		"score": 0.0, "prev_score": 0.0,
	}


func _town_factions() -> Dictionary:
	var out := {}
	for tid: Variant in _gs.towns:
		var t: Dictionary = _gs.towns[tid]
		out[int(t.get("id", tid))] = String(t.get("faction", ""))
	return out


func _mon_holders() -> Dictionary:
	var out := {}
	var sys = _gs.get("monasteries")
	if sys == null:
		return out
	for m: Dictionary in sys.monasteries:
		out[str(m.get("id", m.get("god_id", "")))] = String(m.get("owner", ""))
	return out


func _crys_holders() -> Dictionary:
	var out := {}
	var sys = _gs.get("crystals")
	if sys == null:
		return out
	for c: Dictionary in sys.crystals:
		out[str(c.get("id", c.get("god_id", "")))] = String(c.get("owner", ""))
	return out


## Star-fort holders (hall id -> faction) at a snapshot moment. Forts count
## as strategic assets in war scoring: losing one to the enemy hurts, taking
## one of theirs helps. Null-safe: {} when the fort system isn't wired.
func _fort_holders() -> Dictionary:
	var sfb = _gs.get("starfort_bases")
	if sfb == null or not sfb.has_method("fort_holders"):
		return {}
	return sfb.fort_holders()


## Completed-hall counts for pf ("ours") and foe ("theirs") — each hall is
## one territory claim circle.
func _hall_counts(foe: String = "") -> Dictionary:
	var ours := 0
	var theirs := 0
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not bool(b.get("complete", false)):
			continue
		if not String(b.get("type", "")) in SimTerritory.CLAIM_TYPES:
			continue
		var f := String(b.get("faction", ""))
		if f == _pf():
			ours += 1
		elif foe != "" and f == foe:
			theirs += 1
	return {"ours": ours, "theirs": theirs}


func _treasury() -> float:
	var res = _gs.get("resources")
	if res == null:
		return 0.0
	return float(res.get_amount(_pf(), "gold"))


## --- war score ------------------------------------------------------------
## Returns {"score": float, "reasons": Array[String], "tier": int}.

func _war_score(key: String, rec: Dictionary) -> Dictionary:
	var pf := _pf()
	var foe := String(rec.get("foe", ""))
	var score := 0.0
	var reasons: Array = []
	# 1. casualties — lopsided death ratios.
	var od := float(rec.get("ours_dead", 0))
	var td := float(rec.get("theirs_dead", 0))
	if od + td >= 6.0:
		var cs := clampf((od / maxf(1.0, td) - 1.0) * 30.0, 0.0, 45.0)
		score += cs
		if cs >= 5.0:
			reasons.append("we've lost %d soldiers to their %d" % [int(od), int(td)])
	# 2. command posts changing hands (diff vs war-start snapshot).
	# (Lane 2: extracted to _war_post_changes, shared with the post-war
	# analysis — lane 7's star-fort diff included verbatim.)
	var pc := _war_post_changes(rec)
	var tl := int(pc["tl"])
	var tt := int(pc["tt"])
	var ml := int(pc["ml"])
	var mt := int(pc["mt"])
	var cl := int(pc["cl"])
	var ct := int(pc["ct"])
	var fl := int(pc["fl"])
	var ft := int(pc["ft"])
	var post_score := clampf(tl * 25.0 + ml * 20.0 + cl * 15.0 + fl * 20.0 \
		- tt * 15.0 - mt * 12.0 - ct * 10.0 - ft * 12.0, 0.0, 60.0)
	score += post_score
	if tl + ml + cl + fl > 0:
		reasons.append(_posts_lost_text(tl, ml, cl, fl))
	if tt + mt + ct + ft > 0:
		reasons.append("we've taken %s" % _posts_taken_text(tt, mt, ct, ft))
	# 3. territory — net hall-claims ceded.
	var h := _hall_counts(foe)
	var h0: Dictionary = rec.get("halls0", {})
	var net := maxi(0, int(h0.get("ours", 0)) - int(h.get("ours", 0))) \
		- maxi(0, int(h0.get("theirs", 0)) - int(h.get("theirs", 0)))
	var ts := clampf(float(net) * 10.0, 0.0, 30.0)
	score += ts
	if net > 0:
		reasons.append("we've ceded %s of claimed land" % _plural("territory claim", net))
	# 4. strength-ratio fallback (Jeremy: losses/territory are primary).
	var dip = _gs.get("diplomacy")
	if dip != null:
		var theirs: float = dip.military_strength(foe)
		if theirs > 0.0:
			var sratio: float = dip.military_strength(pf) / theirs
			if sratio < 0.5 and score < 50.0:
				score = 50.0
				reasons.append("their host outmatches ours two-to-one")
	# 5. Lane 2 — exhaustion: long grinding wars wear the army down. Tied
	# to the existing diplomacy morale (war weariness -1/day at war, 70
	# baseline); the AI director piles extra morale damage on losing
	# sides, and exhausted armies reinforce at half strength.
	var morale := 70.0
	if dip != null:
		morale = dip.morale_of(pf)
	var days_at_war := maxi(0, int(_gs.get("day_number")) \
		- int(rec.get("start_day", 0)))
	var exh := clampf(float(days_at_war - 8) * 1.2 \
		+ (70.0 - morale) * 0.35, 0.0, 40.0)
	score += exh * 0.5
	rec["exhausted"] = exh >= 25.0
	if exh >= 15.0:
		reasons.append("the men are exhausted — morale at %d" % int(morale))
	var tier := 0
	if score >= 85.0:
		tier = 3
	elif score >= 55.0:
		tier = 2
	elif score >= 25.0:
		tier = 1
	return {"score": score, "reasons": reasons, "tier": tier}


func _posts_lost_text(tl: int, ml: int, ct: int, fl: int = 0) -> String:
	var bits: Array = []
	if tl > 0:
		bits.append(_plural("town", tl))
	if ml > 0:
		bits.append(_plural("monastery", ml))
	if fl > 0:
		bits.append(_plural("star fort", fl))
	if ct > 0:
		bits.append(_plural("dark crystal", ct))
	return "we've lost " + ", ".join(bits) + " to the enemy"


func _posts_taken_text(tt: int, mt: int, ct: int, ft: int = 0) -> String:
	var bits: Array = []
	if tt > 0:
		bits.append(_plural("town", tt))
	if mt > 0:
		bits.append(_plural("monastery", mt))
	if ft > 0:
		bits.append(_plural("star fort", ft))
	if ct > 0:
		bits.append(_plural("dark crystal", ct))
	return ", ".join(bits) + " from the enemy"


## --- treasury drain -------------------------------------------------------
## Samples the treasury daily; a short runway under war burn brings the
## Treasury Advisor into the counsel. Returns {"burn","runway","text"}.

func _update_treasury(rec: Dictionary) -> Dictionary:
	var hist: Array = rec.get("gold_hist", [])
	hist.append(_treasury())
	if hist.size() > 7:
		hist = hist.slice(hist.size() - 7)
	rec["gold_hist"] = hist
	var out := {"burn": 0.0, "runway": 999.0, "text": ""}
	if hist.size() < 3:
		return out
	var days := float(hist.size() - 1)
	var burn := (float(hist[0]) - float(hist[hist.size() - 1])) / maxf(1.0, days)
	out["burn"] = burn
	if burn >= 15.0:
		var runway: float = float(hist[hist.size() - 1]) / burn
		out["runway"] = runway
		if runway < 12.0:
			out["text"] = "the war burns %d gold a day — the treasury empties in %d days" % [int(burn), int(runway)]
	return out


## --- daily counsel --------------------------------------------------------

func _check_war_losses() -> void:
	var dip = _gs.get("diplomacy")
	if dip == null:
		return
	var pf := _pf()
	var ended: Array = []
	for foe: String in _gs.active_factions:
		if foe == pf:
			continue
		var key := "%s|%s" % [pf, foe]
		if dip.relation_state(pf, foe) != "war":
			ended.append(key)
			continue
		var rec: Dictionary = _wars.get(key, {})
		if rec.is_empty():
			rec = _new_war_record(foe)
			_wars[key] = rec
			# Jeremy 2026-10-11: they declared on US — the cabinet still
			# hears it through the war advisor.
			_spread_war_word(foe, false)
		var drain := _update_treasury(rec)
		var ws := _war_score(key, rec)
		var tier := int(ws.get("tier", 0))
		var reasons: Array = ws.get("reasons", [])
		var drain_text := String(drain.get("text", ""))
		if drain_text != "":
			reasons.append(drain_text)
		if tier >= 1 and _war_debates.has(key):
			# The War Advisor has come around: the plea takes over.
			_war_debates.erase(key)
		if tier == 0 and drain_text != "":
			# Lane 2: the advisors DISAGREE — the War Advisor wants to
			# fight on (we're not losing) but the treasury can't fund it.
			# They debate in their own voices; the ruler decides.
			_war_counsel_debate(key, rec, foe, drain, ws)
		else:
			if tier == 0 and _war_debates.has(key):
				_war_debates.erase(key)  # drain resolved: debate over
			_check_treasury_voice(key, rec, drain_text)
			_handle_plea_tier(key, rec, foe, tier, reasons,
				bool(rec.get("exhausted", false)))
		rec["prev_score"] = float(rec.get("score", float(ws.get("score", 0.0))))
		rec["score"] = float(ws.get("score", 0.0))
	for key: String in ended:
		var erec: Dictionary = _wars.get(key, {})
		if not erec.is_empty():
			_post_war_analysis(key, erec)  # Lane 2: the real numbers
		_wars.erase(key)
		_peace_pleas.erase(key)
		_treasury_warned.erase(key)
		_war_debates.erase(key)
		var pt: Dictionary = _peace_terms.get(key, {})
		if not pt.is_empty() and String(pt.get("state", "")) == "offered":
			# 2026-10-09 wake: the envoy was still riding when this war
			# ended — the ruler was promised an answer, so the envoy's
			# empty-handed return is spoken (was: erased in silence).
			_notify_envoy_returned(pt, String(pt.get("foe", "")))
		_peace_terms.erase(key)


## The Treasury Advisor's own voice: when the coffers bleed and no war plea
## is currently pending, they come to the ruler directly (throttled).
func _check_treasury_voice(key: String, rec: Dictionary,
		drain_text: String) -> void:
	if drain_text == "":
		return
	var day := int(_gs.get("day_number"))
	if day - int(_treasury_warned.get(key, -99)) < 3:
		return
	var plea: Dictionary = _peace_pleas.get(key, {})
	if String(plea.get("state", "")) == "pending" and bool(plea.get("had_drain", false)):
		return  # the war plea already carries the treasury line
	var ta := _treasury_advisor()
	if ta.is_empty():
		return
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	phone.npc_message(int(ta.get("id", 0)),
		"Sire, %s. I don't care how righteous the cause — empty coffers don't field armies. Make peace, %s." % [drain_text, _ruler()])
	_treasury_warned[key] = day


func _handle_plea_tier(key: String, rec: Dictionary, foe: String,
		tier: int, reasons: Array, exhausted: bool = false) -> void:
	var plea: Dictionary = _peace_pleas.get(key, {})
	if tier == 0:
		# Back to even — fresh slate for future pleas.
		if not plea.is_empty():
			_peace_pleas.erase(key)
		return
	var asked_tier := int(plea.get("tier", 0))
	if String(plea.get("state", "")) == "accepted":
		return
	if tier <= asked_tier:
		return  # already pled at this tier (or worse)
	var advisor := _war_advisor()
	var via_treasury := false
	if advisor.is_empty():
		# 2026-10-09 wake: no living war advisor — the Treasury Advisor
		# carries the counsel instead of letting the plea die in silence.
		# (The director's modal only fires under 50% military strength, so
		# a war lost on casualties/territory would otherwise vanish.)
		advisor = _treasury_advisor()
		via_treasury = true
	if advisor.is_empty():
		return
	_send_peace_plea(advisor, foe, tier, key, reasons, exhausted,
		via_treasury)
	if tier >= 2:
		# The plea replaces the director's modal at its threshold: mark
		# its one-ask flag so the crown isn't asked twice.
		var dir = _gs.get("ai_director")
		if dir != null:
			var asked = dir.get("_peace_asked")
			if asked is Dictionary:
				(asked as Dictionary)[key] = true


func _send_peace_plea(advisor: Dictionary, foe: String, tier: int,
		key: String, reasons: Array, exhausted: bool = false,
		via_treasury: bool = false) -> void:
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name", foe.capitalize()))
	var text := _plea_text(tier, fname, reasons, exhausted)
	if via_treasury:
		# The treasury advisor speaks in their own voice — the war advisor
		# is dead, and the numbers are what they are.
		text = "Our war advisor is gone, so hear it from the treasury — " \
			+ text
	phone.npc_message(int(advisor.get("id", 0)), text)
	_peace_pleas[key] = {"tier": tier, "state": "pending",
		"advisor_id": int(advisor.get("id", 0)), "foe": foe,
		"day": int(_gs.get("day_number")),
		# Lane 2: remember whether this plea carried the treasury-drain
		# line, so the Treasury Advisor's independent voice is only
		# suppressed when the ruler was actually told about the drain.
		"had_drain": reasons.any(
			func(r: Variant) -> bool: return String(r).begins_with("the war burns"))}


func _plea_text(tier: int, foe_name: String, reasons: Array,
		exhausted: bool = false) -> String:
	var tail := " Reply ACCEPT and I'll open peace talks at once — or DENY and we fight on."
	var brief := ""
	if not reasons.is_empty():
		brief = " The ledgers don't lie: " + "; ".join(reasons) + "."
	# Lane 2: exhausted armies get the rout warning on the dire pleas.
	var rout := ""
	if exhausted and tier >= 2:
		rout = " The men are exhausted — another push risks rout."
	match tier:
		1:
			return "Sire — a grim word on the %s war.%s I can sue for peace while our terms are still terms.%s" % [foe_name, brief, tail]
		2:
			return "Sire, hear me — the %s war is eating us alive.%s I'm begging you: let me end this.%s%s" % [foe_name, brief, tail, rout]
		_:
			return "SIRE. This is no longer counsel — this is BEGGING.%s Let me sue for peace while we still HAVE a kingdom.%s%s" % [brief, tail, rout]
	return ""


## --- strategic brief: the case FOR war --------------------------------------
## Jeremy 2026-10-06: advisors present REASONS, not verdicts. The same
## numbers the AI uses (strength ratios, enemy weakness, truce checks,
## treasury runway) as a human-readable brief — attached to war proposals
## and spoken when the ruler's own war order looks unwise.

## {"text": brief, "unwise": bool}
func strategic_brief(foe: String) -> Dictionary:
	var out := {"text": "", "unwise": false}
	var dip = _gs.get("diplomacy")
	var pf := _pf()
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name", foe.capitalize()))
	var bits: Array = []
	var unwise := false
	if dip != null:
		var ours := float(dip.military_strength(pf))
		var theirs := float(dip.military_strength(foe))
		if theirs > 0.0:
			var r := ours / theirs
			if r >= 2.0:
				bits.append("we outnumber them %d-to-1" % int(r))
			elif r >= 1.2:
				bits.append("we hold a slight edge in strength")
			elif r >= 0.8:
				bits.append("we're evenly matched — it'd be a grind")
			else:
				bits.append("they outnumber us %d-to-1" % int(1.0 / maxf(0.05, r)))
				unwise = true
		elif ours <= 0.0:
			bits.append("neither of us fields an army — it'd be a shouting match")
		# Enemy weakness: already bleeding in another war?
		var other_wars: Array = []
		for o: String in _gs.active_factions:
			if o == pf or o == foe:
				continue
			if dip.relation_state(foe, o) == "war":
				other_wars.append(o)
		if not other_wars.is_empty():
			var oname: String = String(Config.FACTIONS.get(
				other_wars[0], {}).get("name", String(other_wars[0]).capitalize()))
			bits.append("they're already bleeding in a war with the %s" % oname)
		# Truce binds?
		if dip.has_method("truce_active") and dip.truce_active(pf, foe):
			bits.append("a truce binds us — breaking it costs honor and gold")
			unwise = true
		# Their command posts.
		var fm := _foe_post_count(foe)
		if fm > 0:
			bits.append("they hold %s" % _plural("command post", fm))
	# Treasury runway for the campaign (25 gold/day campaign heuristic).
	var gold := _treasury()
	var days := int(gold / 25.0)
	bits.append("the treasury can fund roughly a %d-day campaign" % days)
	if days < 5:
		unwise = true
	if bits.is_empty():
		return out
	out["text"] = "The scouts report: " + ", ".join(bits) + "."
	out["unwise"] = unwise
	return out


func _foe_post_count(foe: String) -> int:
	var n := 0
	for tid: Variant in _gs.towns:
		if String(_gs.towns[tid].get("faction", "")) == foe:
			n += 1
	var mons := _mon_holders()
	for mid: Variant in mons:
		if String(mons[mid]) == foe:
			n += 1
	# Jeremy 2026-10-06 (lane 7): enemy star forts count in the brief too.
	var sfb = _gs.get("starfort_bases")
	if sfb != null and sfb.has_method("forts_of"):
		for rec: Dictionary in sfb.forts_of(foe):
			n += 1
	return n


## A pending plea from this advisor? (Checked before order matching so a
## plain "yes"/"no" answers the plea instead of falling into chat.)
## 2026-10-09 wake: routes by named faction when several pleas share one
## advisor (two losing wars); a bare verdict with several pleas open comes
## back "ambiguous" so the crown is asked WHICH war instead of answering
## the first one in dict order.
func _pending_plea_for(advisor_id: int, t: String = "") -> Dictionary:
	var matches: Array = []
	for key: String in _peace_pleas:
		var rec: Dictionary = _peace_pleas[key]
		if int(rec.get("advisor_id", 0)) == advisor_id \
				and String(rec.get("state", "")) == "pending":
			var out := rec.duplicate()
			out["key"] = key
			matches.append(out)
	if matches.is_empty():
		return {}
	if matches.size() == 1:
		return matches[0]
	var named := _faction_in(t)
	if named != "":
		var fid := _faction_id(named)
		for m: Dictionary in matches:
			if String(m.get("foe", "")) == fid:
				return m
		# Names a faction we hold no plea with — fall through to orders.
		return {}
	return {"ambiguous": true, "pleas": matches}


## "The Elves and the Gnomes" — for the multi-plea "which war?" prompt.
func _plea_foe_list(plea: Dictionary) -> String:
	var names: Array = []
	for m: Variant in plea.get("pleas", []):
		var foe := String((m as Dictionary).get("foe", ""))
		var fname: String = String(Config.FACTIONS.get(foe, {}).get(
			"name", foe.capitalize()))
		if not names.has(fname):
			names.append(fname)
	if names.size() == 2:
		return "%s and %s" % [names[0], names[1]]
	var tail: String = String(names[names.size() - 1])
	return "%s, and %s" % [", ".join(names.slice(0, -1)), tail]


## "accept" / "deny" / "" — deny patterns first (mirrors wall verdicts).
static func _parse_plea_verdict(t: String) -> String:
	var p := " " + t + " "
	var deny_pats := [" deny ", " no ", " nope ", " nah ", " never ",
		" refuse ", " fight on ", " no peace ", " not yet "]
	for d: String in deny_pats:
		if p.contains(d):
			return "deny"
	var accept_pats := [" accept ", " yes ", " yeah ", " yep ", " agreed ",
		" do it ", " make peace ", " sue for peace ", " end the war ",
		" end this ", " please "]
	for a: String in accept_pats:
		if p.contains(a):
			return "accept"
	return ""


func _answer_plea(unit: Dictionary, plea: Dictionary,
		verdict: String) -> String:
	var key := String(plea.get("key", ""))
	var foe := String(plea.get("foe", ""))
	var tier := int(plea.get("tier", 1))
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name", foe.capitalize()))
	if verdict == "accept":
		_peace_pleas[key]["state"] = "accepted"
		var wrec: Dictionary = _wars.get(key, {})
		if not wrec.is_empty():
			wrec["we_sued"] = true  # Lane 2: post-war analysis credit
		var dip = _gs.get("diplomacy")
		if dip != null and dip.has_method("offer_surrender"):
			dip.offer_surrender(_pf(), foe)
		return _fill(unit, "At once, {ruler}. Peace talks with the %s are open — I'll bring you terms, not a funeral." % fname)
	# Deny: acknowledged grimly; re-arms when the next worse tier hits.
	_peace_pleas[key]["state"] = "denied"
	match tier:
		1:
			return _fill(unit, "As you command, {ruler}. We fight on — but I'll be back if it gets worse. It will get worse.")
		2:
			return _fill(unit, "...Very well, {ruler}. The men will hear the crown fights on. (They'll also hear the screaming.)")
		_:
			return _fill(unit, "Then we die gloriously, {ruler}. I'll have the bards tune up.")
	return ""



## === Lane 2: war counsel expansion (Jeremy 2026-10-06) =======================
## 1. named notable-fallen reports — warlords and high-kill veterans are
##    named in Messenger when they fall ("We lost Grimbash, 14 kills, at
##    Thornwall"), throttled to one report per war per day.
## 2. war exhaustion — scored off war duration + diplomacy morale (the
##    existing war-weariness system); the AI director grinds losing sides
##    down faster and halves their reinforcement waves.
## 3. peace-terms negotiation — "offer peace for 500 gold" sends an envoy;
##    the AI answers accept/counter/refuse in Messenger the next day.
##    "demand tribute" goes through the diplomacy channel (refused at war,
##    HTML parity).
## 4. multi-war dashboard — "wars" lists every active war with score, tier,
##    and trend.
## 5. advisor debate — War wants to fight on while Treasury says the
##    coffers can't take it: both argue in-voice, the ruler decides.
## 6. post-war analysis — a Gazette story with the real numbers when a war
##    ends.
##
## Tiers stay concerned -> urgent -> desperate; Accept/Deny kept; a denied
## plea re-arms at the next worse tier (unchanged). No surprise wars: every
## war/peace state change below completes a player-confirmed order through
## the existing diplomacy channel (offer_surrender / make_peace), exactly
## like an approved sue_for_peace proposal's outcome.


## --- 1. notable fallen -------------------------------------------------------

## Kill credit lands on the attacker in combat.gd damage_unit; here we watch
## our own dead. Warlords are always notable; veterans earn it at 5+ kills
## or weapon_level 2+ (the armament program / weapon shopping marks them).
func _note_fallen(key: String, rec: Dictionary, u: Dictionary) -> void:
	var job := String(u.get("job", ""))
	var kills := int(u.get("kills", 0))
	var wlvl := int(u.get("weapon_level", 0))
	if job != "warlord" and kills < 5 and wlvl < 2:
		return
	var fallen: Array = rec.get("fallen", [])
	fallen.append({
		"unit_id": int(u.get("id", 0)),
		"name": String(u.get("name", "")),
		"job": job, "kills": kills,
		"day": int(_gs.get("day_number")),
		"where": _nearest_town_name(u.get("position", Vector2.ZERO)),
	})
	if fallen.size() > 12:
		fallen = fallen.slice(fallen.size() - 12)
	rec["fallen"] = fallen
	_maybe_report_fallen(key, rec)


func _nearest_town_name(pos: Vector2) -> String:
	var best := ""
	var best_d := 1e18
	for tid: Variant in _gs.towns:
		var t: Dictionary = _gs.towns[tid]
		var tp: Vector2 = t.get("position", Vector2.ZERO)
		var d := pos.distance_squared_to(tp)
		if d < best_d:
			best_d = d
			best = String(t.get("name", ""))
	return best


## One fallen report per war per day, from the War Advisor.
func _maybe_report_fallen(key: String, rec: Dictionary) -> void:
	var day := int(_gs.get("day_number"))
	if day - int(rec.get("fallen_report_day", -99)) < 1:
		return
	var fallen: Array = rec.get("fallen", [])
	if fallen.is_empty():
		return
	var advisor := _war_advisor()
	if advisor.is_empty():
		return
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	var latest: Dictionary = fallen[fallen.size() - 1]
	var line := _fallen_line(latest)
	if fallen.size() > 1:
		line += " %d more veterans fell with them." % (fallen.size() - 1)
	phone.npc_message(int(advisor.get("id", 0)),
		"A grim tally, %s — %s" % [_ruler(), line])
	rec["fallen_report_day"] = day


func _fallen_line(f: Dictionary) -> String:
	var nm := String(f.get("name", ""))
	var job := String(f.get("job", "soldier"))
	var kills := int(f.get("kills", 0))
	var where := String(f.get("where", ""))
	var who := nm
	if who == "":
		if job == "warlord":
			who = "our warlord"
		else:
			who = "a veteran " + job
	var line := "we lost %s" % who
	if kills > 0:
		line += " (%d kills)" % kills
	if where != "":
		line += " at %s" % where
	return line + "."


## --- 2. exhaustion helpers ----------------------------------------------------
## (the score component itself lives in _war_score; the morale grinding and
## half-strength reinforcement live in the AI director)

## Command-post changes for a war record, shared by _war_score and the
## post-war analysis. Keys: tl/tt (towns lost/taken), ml/mt (monasteries),
## cl/ct (crystals), fl/ft (star forts — lane 7's diff, verbatim).
func _war_post_changes(rec: Dictionary) -> Dictionary:
	var pf := _pf()
	var foe := String(rec.get("foe", ""))
	var out := {"tl": 0, "tt": 0, "ml": 0, "mt": 0, "cl": 0, "ct": 0,
		"fl": 0, "ft": 0}
	var towns0: Dictionary = rec.get("towns0", {})
	var towns1 := _town_factions()
	for tid: Variant in towns1:
		var was := String(towns0.get(tid, ""))
		var now := String(towns1[tid])
		if was == now:
			continue
		if was == pf and now == foe:
			out["tl"] = int(out["tl"]) + 1
		elif was == foe and now == pf:
			out["tt"] = int(out["tt"]) + 1
	var mons0: Dictionary = rec.get("mons0", {})
	var mons1 := _mon_holders()
	for mid: Variant in mons1:
		var was := String(mons0.get(mid, ""))
		var now := String(mons1[mid])
		if was == now or was == "" or now == "":
			continue
		if was == pf and now == foe:
			out["ml"] = int(out["ml"]) + 1
		elif was == foe and now == pf:
			out["mt"] = int(out["mt"]) + 1
	var crys0: Dictionary = rec.get("crys0", {})
	var crys1 := _crys_holders()
	for cid: Variant in crys1:
		var was := String(crys0.get(cid, ""))
		var now := String(crys1[cid])
		if was == now or was == "" or now == "":
			continue
		if was == pf and now == foe:
			out["cl"] = int(out["cl"]) + 1
		elif was == foe and now == pf:
			out["ct"] = int(out["ct"]) + 1
	# Star forts (Jeremy 2026-10-06, lane 7): a fort is a major strategic
	# asset — weight it like a monastery.
	var forts0: Dictionary = rec.get("forts0", {})
	var forts1 := _fort_holders()
	for hid: Variant in forts1:
		var was := String(forts0.get(hid, ""))
		var now := String(forts1[hid])
		if was == now or was == "" or now == "":
			continue
		if was == pf and now == foe:
			out["fl"] = int(out["fl"]) + 1
		elif was == foe and now == pf:
			out["ft"] = int(out["ft"]) + 1
	return out


## --- 5. advisor debate --------------------------------------------------------

## The War Advisor wants to fight on (tier 0 — we're not losing) but the
## Treasury Advisor says the coffers can't fund it (runway < 12 days).
## Both argue in their own voices; the ruler's ACCEPT/DENY settles it.
## A denial re-arms after 5 days if the drain persists.
func _war_counsel_debate(key: String, rec: Dictionary, foe: String,
		drain: Dictionary, ws: Dictionary) -> void:
	var day := int(_gs.get("day_number"))
	var deb: Dictionary = _war_debates.get(key, {})
	var state := String(deb.get("state", ""))
	if state == "pending":
		return  # already arguing; the ruler hasn't decided
	if state == "denied" and day - int(deb.get("day", 0)) < 5:
		return  # cooling off
	var wa := _war_advisor()
	var ta := _treasury_advisor()
	if wa.is_empty() or ta.is_empty():
		# No living war advisor: fall back to the treasury's solo voice.
		_check_treasury_voice(key, rec, String(drain.get("text", "")))
		return
	# A stale plea is superseded by the debate.
	_peace_pleas.erase(key)
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	var burn := int(drain.get("burn", 0.0))
	var runway := int(drain.get("runway", 0.0))
	phone.npc_message(int(ta.get("id", 0)),
		"Sire — the %s war burns %d gold a day; the treasury empties in %d days. The War Advisor dreams of glory; I dream of a treasury that isn't a cobweb collection. This war must END. Sue for peace NOW, before we can't pay the gravediggers." % [fname, burn, runway])
	phone.npc_message(int(wa.get("id", 0)),
		"Sire, don't listen to the coin-counter. We're WINNING the %s war — %s. End it now and every grave we dug was for nothing. Your call, %s: reply ACCEPT and we sue for peace — or DENY and we fight on." % [fname, _debate_winning_line(ws), _ruler()])
	_war_debates[key] = {"state": "pending", "day": day,
		"war_id": int(wa.get("id", 0)),
		"treasury_id": int(ta.get("id", 0)), "foe": foe}


func _debate_winning_line(ws: Dictionary) -> String:
	var reasons: Array = ws.get("reasons", [])
	for r: String in reasons:
		if "we've taken" in r:
			return r
	# Tier 0 with no taken-posts reason: lean on the casualty ledger.
	return "we hold the field"


## A pending debate involving this advisor? (Both advisors' threads answer.)
func _pending_debate_for(advisor_id: int) -> Dictionary:
	for key: String in _war_debates:
		var deb: Dictionary = _war_debates[key]
		if String(deb.get("state", "")) != "pending":
			continue
		if int(deb.get("war_id", 0)) == advisor_id \
				or int(deb.get("treasury_id", 0)) == advisor_id:
			var out := deb.duplicate()
			out["key"] = key
			return out
	return {}


func _answer_debate(unit: Dictionary, deb: Dictionary,
		verdict: String) -> String:
	var key := String(deb.get("key", ""))
	var foe := String(deb.get("foe", ""))
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	if verdict == "accept":
		_war_debates[key]["state"] = "accepted"
		var wrec: Dictionary = _wars.get(key, {})
		if not wrec.is_empty():
			wrec["we_sued"] = true
		var dip = _gs.get("diplomacy")
		if dip != null and dip.has_method("offer_surrender"):
			dip.offer_surrender(_pf(), foe)
		return _fill(unit, "So be it, {ruler} — peace talks with the %s are open. (The Treasury Advisor is already dancing.)" % fname)
	_war_debates[key]["state"] = "denied"
	_war_debates[key]["day"] = int(_gs.get("day_number"))
	return _fill(unit, "Then we FIGHT ON, {ruler}. The Treasury Advisor is muttering about ledgers. Win fast.")


## --- 3. peace-terms negotiation -----------------------------------------------
## "offer peace for 500 gold" sends an envoy; the enemy AI answers the
## next day in Messenger: accept / counter / refuse. "demand tribute" goes
## through the diplomacy channel (refused outright mid-war, HTML parity).
## One answered offer per war (HTML agri62State.done parity).

static func _gold_in(t: String) -> int:
	var m := RegEx.new()
	m.compile("\\b(\\d+)\\b")
	var r := m.search(t)
	if r != null:
		return int(r.get_string(1))
	return -1


func _order_peace_terms(unit: Dictionary, t: String) -> String:
	var job := String(unit.get("job", ""))
	if job != "advisor_war" and job != "advisor_economy":
		return _fill(unit, "Peace terms? That's the War Advisor's table, {ruler} — I just work here.")
	var noun := _faction_in(t)
	var foe := ""
	if noun != "":
		foe = _faction_id(noun)
	else:
		# No faction named: default to our only war, if there's exactly one.
		# (Read live from diplomacy — the war record may not exist yet
		# before the first daily counsel tick.)
		var foes: Array = []
		for f: String in _gs.active_factions:
			if f != _pf() and _at_war_with(f) and not foes.has(f):
				foes.append(f)
		if foes.size() == 1:
			foe = String(foes[0])
	if foe == "":
		return _fill(unit, "Name a faction, {ruler} — whose peace are we buying, and for how much gold?")
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	var dip = _gs.get("diplomacy")
	if dip == null:
		return _fill(unit, "The envoys are all drunk, {ruler}. Try again shortly.")
	if t.contains("demand tribute"):
		# HTML demand_tribute: refused outright while at war.
		if _at_war_with(foe):
			return _fill(unit, "We can't demand tribute from the %s mid-war, {ruler} — they'd laugh the envoy out of the tent." % fname)
		var amt := _gold_in(t)
		if amt < 0:
			amt = 200
		var res: Dictionary = dip.demand_tribute(_pf(), foe, "gold",
			float(amt))
		if bool(res.get("accepted", false)):
			return _fill(unit, "Tribute paid, {ruler} — %s" % String(res.get("msg", "")))
		return _fill(unit, "%s" % String(res.get("msg", "")))
	# Offer peace: only while at war, one answered offer per war.
	if not _at_war_with(foe):
		return _fill(unit, "We're not at war with the %s, {ruler} — nothing to make peace over." % fname)
	var key := "%s|%s" % [_pf(), foe]
	var rec: Dictionary = _wars.get(key, {})
	var war_start := int(rec.get("start_day", 0))
	if int(_peace_terms_done.get(key, -999)) == war_start:
		return _fill(unit, "We've already offered the %s terms this war, {ruler}. They answered — the answer stands." % fname)
	var existing: Dictionary = _peace_terms.get(key, {})
	if not existing.is_empty() \
			and String(existing.get("state", "")) in ["offered", "counter"]:
		return _fill(unit, "An envoy is already with the %s, {ruler}. Patience." % fname)
	var offered := _gold_in(t)
	if offered < 0:
		offered = int(dip.surrender_tribute_amount(_pf(), foe))
	if offered <= 0:
		return _fill(unit, "Name a sum, {ruler} — 'offer peace for 500 gold'.")
	if float(offered) > _treasury():
		return _fill(unit, "We don't HAVE %d gold, {ruler} — the treasury holds %d." % [offered, int(_treasury())])
	_peace_terms[key] = {"foe": foe, "amount": offered,
		"counter_amount": 0, "advisor_id": int(unit.get("id", 0)),
		"day": int(_gs.get("day_number")), "state": "offered"}
	return _fill(unit, "Understood, {ruler} — peace with the %s for %d gold. My envoy leaves at dawn; you'll have their answer tomorrow." % [fname, offered])


## The enemy's answer to our terms. HTML offerPeace62 parity: the AI
## accepts when not hateful (relation > -20), when outmatched (their
## strength < 75% of ours), or on a whim; a proud-but-even foe counters
## instead of flatly refusing.
func _peace_terms_ai_response(foe: String, amount: int) -> Dictionary:
	var dip = _gs.get("diplomacy")
	var pf := _pf()
	var out := {"verdict": "refuse", "counter": 0, "reason": ""}
	if dip == null:
		return out
	var str_us := float(dip.military_strength(pf))
	var str_them := float(dip.military_strength(foe))
	var traits: Dictionary = dip.faction_traits(foe)
	var proud := float(traits.get("proud", 0.5))
	var scared := str_them < str_us * 0.7
	var not_hateful := float(dip.relation_score(foe, pf)) > -20.0
	if scared and proud < 0.75:
		out["verdict"] = "accept"
		out["reason"] = "outmatched and not too proud"
	elif not_hateful:
		out["verdict"] = "accept"
		out["reason"] = "no deep hatred"
	elif str_us > 0.0 and str_them >= str_us * 0.75 \
			and str_them <= str_us * 1.3 and proud >= 0.4 and proud < 0.7:
		out["verdict"] = "counter"
		out["counter"] = int(dip.surrender_tribute_amount(foe, pf))
		out["reason"] = "they smell leverage"
	elif proud >= 0.7 and not scared:
		out["verdict"] = "refuse"
		out["reason"] = "too proud to yield"
	elif randf() < 0.25:
		out["verdict"] = "accept"
		out["reason"] = "a whim of mercy"
	else:
		out["verdict"] = "refuse"
		out["reason"] = "they want war"
	return out


## Envoys return the day after they're sent.
func _check_peace_terms() -> void:
	var day := int(_gs.get("day_number"))
	for key: String in _peace_terms.keys():
		var pt: Dictionary = _peace_terms[key]
		if String(pt.get("state", "")) != "offered":
			continue
		if int(pt.get("day", day)) >= day:
			continue  # the envoy is still riding
		var foe := String(pt.get("foe", ""))
		if not _at_war_with(foe):
			_peace_terms.erase(key)
			_notify_envoy_returned(pt, foe)
			continue
		var amount := int(pt.get("amount", 0))
		var resp := _peace_terms_ai_response(foe, amount)
		_deliver_terms_answer(key, pt, foe, amount, resp)


func _notify_envoy_returned(pt: Dictionary, foe: String) -> void:
	## 2026-10-09 wake: the war ended while the envoy was still riding —
	## the ruler was promised an answer, so the envoy's empty-handed
	## return must be spoken, never erased silently.
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	var text := "The envoy returns from the %s, %s — but the war ended before their answer came. The terms are dust." % [fname, _ruler()]
	var advisor: Dictionary = _gs.get_unit(int(pt.get("advisor_id", 0)))
	var aid := 0
	if not advisor.is_empty() and bool(advisor.get("alive", false)):
		aid = int(advisor.get("id", 0))
	if aid == 0:
		var cabinet := _living_cabinet_ids()
		if not cabinet.is_empty():
			aid = int(cabinet[0])
	var phone = _gs.get("phone_sys")
	if aid != 0 and phone != null and phone.has_method("npc_message"):
		phone.npc_message(aid, text)
		return
	var court = _gs.get("court_sys")
	if court != null and court.has_method("publish_story"):
		court.publish_story("ENVOY RETURNS EMPTY-HANDED", text, "war")
	elif _gs.get("bus") != null:
		_gs.bus.gazette_story.emit({"headline": "ENVOY RETURNS EMPTY-HANDED",
			"body": text, "kind": "war",
			"day": int(_gs.get("day_number"))})


func _deliver_terms_answer(key: String, pt: Dictionary, foe: String,
		amount: int, resp: Dictionary) -> void:
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	var advisor: Dictionary = _gs.get_unit(int(pt.get("advisor_id", 0)))
	if advisor.is_empty() or not bool(advisor.get("alive", false)):
		advisor = _war_advisor()
	var aid := int(advisor.get("id", 0)) if not advisor.is_empty() else 0
	if aid == 0:
		# 2026-10-09 wake: the envoy advisor AND the war advisor are both
		# dead. The ruler was promised "you'll have their answer tomorrow"
		# — fall back to any living cabinet member so the answer lands.
		var cabinet := _living_cabinet_ids()
		if not cabinet.is_empty():
			aid = int(cabinet[0])
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	var dip = _gs.get("diplomacy")
	var verdict := String(resp.get("verdict", "refuse"))
	var wrec: Dictionary = _wars.get(key, {})
	var text := ""
	match verdict:
		"accept":
			_peace_terms_done[key] = int(wrec.get("start_day", 0))
			if not wrec.is_empty():
				wrec["we_sued"] = true
			if dip != null:
				dip.pay_tribute(_pf(), foe, "gold", float(amount))
				dip.make_peace(_pf(), foe)
			text = "Word from the %s, %s — they ACCEPT your terms. %d gold changes hands, and the war ends." % [fname, _ruler(), amount]
			_peace_terms.erase(key)  # answered; the done-key keeps the
			# one-offer-per-war rule
		"counter":
			var want := int(resp.get("counter", 0))
			pt["state"] = "counter"
			pt["counter_amount"] = want
			text = "The %s spit at %d gold — they counter: %d gold in reparations, and the war ends. Reply ACCEPT to pay it, or DENY to walk away." % [fname, amount, want]
		_:
			_peace_terms_done[key] = int(wrec.get("start_day", 0))
			text = "The %s spit on your offer, %s. The war continues." % [fname, _ruler()]
			_peace_terms.erase(key)
	if aid != 0:
		phone.npc_message(aid, text)
		if verdict == "refuse":
			_publish_terms_refused(fname)
	else:
		# The whole cabinet is dead — the Gazette carries the answer the
		# promised envoy never could. (Refuse already has its own story.)
		if verdict != "refuse":
			_publish_terms_answer_story(fname, verdict, amount)
		else:
			_publish_terms_refused(fname)


func _publish_terms_answer_story(fname: String, verdict: String,
		amount: int) -> void:
	var court = _gs.get("court_sys")
	var headline := "WORD FROM THE %s" % fname.to_upper()
	var body := ""
	match verdict:
		"accept":
			body = "The %s have ACCEPTED the crown's peace terms. %d gold changes hands; the war ends." % [fname, amount]
		"counter":
			body = "The %s spit at the crown's offer and counter: %d gold in reparations, and the war ends. No advisor lives to carry the reply." % [fname, amount]
		_:
			body = "The %s answered the crown's peace terms, but no advisor lives to carry the word." % fname
	if court != null and court.has_method("publish_story"):
		court.publish_story(headline, body, "war")
	elif _gs.get("bus") != null:
		_gs.bus.gazette_story.emit({"headline": headline, "body": body,
			"kind": "war", "day": int(_gs.get("day_number"))})


func _publish_terms_refused(fname: String) -> void:
	var court = _gs.get("court_sys")
	var headline := "PEACE SPURNED"
	var body := "The %s spit on your peace offer. The war continues." % fname
	if court != null and court.has_method("publish_story"):
		court.publish_story(headline, body, "war")
	elif _gs.get("bus") != null:
		_gs.bus.gazette_story.emit({"headline": headline, "body": body,
			"kind": "war", "day": int(_gs.get("day_number"))})


## A pending counter-offer in this advisor's thread?
func _pending_counter_for(advisor_id: int) -> Dictionary:
	for key: String in _peace_terms:
		var pt: Dictionary = _peace_terms[key]
		if String(pt.get("state", "")) != "counter":
			continue
		if int(pt.get("advisor_id", 0)) == advisor_id:
			var out := pt.duplicate()
			out["key"] = key
			return out
	return {}


func _answer_counter(unit: Dictionary, counter: Dictionary,
		verdict: String) -> String:
	var key := String(counter.get("key", ""))
	var foe := String(counter.get("foe", ""))
	var want := int(counter.get("counter_amount", 0))
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	_peace_terms.erase(key)  # answered; the done-key keeps the one-offer rule
	var wrec: Dictionary = _wars.get(key, {})
	_peace_terms_done[key] = int(wrec.get("start_day", 0))
	if verdict == "accept":
		if float(want) > _treasury():
			return _fill(unit, "We can't pay %d gold, {ruler} — the treasury holds %d. The counter dies." % [want, int(_treasury())])
		if not wrec.is_empty():
			wrec["we_sued"] = true
		var dip = _gs.get("diplomacy")
		if dip != null:
			dip.pay_tribute(_pf(), foe, "gold", float(want))
			dip.make_peace(_pf(), foe)
		return _fill(unit, "Done, {ruler} — %d gold to the %s, and the war is OVER." % [want, fname])
	return _fill(unit, "Very well, {ruler} — the offer dies. The war grinds on.")


## --- 4. multi-war dashboard ---------------------------------------------------

func _war_dashboard(unit: Dictionary) -> String:
	return _fill(unit, _war_dashboard_text())


## Every active war: foe, score, tier, trend vs yesterday, and the top
## reasons. The "wars" status query.
func _war_dashboard_text() -> String:
	var day := int(_gs.get("day_number"))
	var lines: Array = []
	var tier_names := ["QUIET", "CONCERNED", "URGENT", "DESPERATE"]
	for key: String in _wars.keys():
		var rec: Dictionary = _wars[key]
		var foe := String(rec.get("foe", ""))
		if foe == "" or not _at_war_with(foe):
			continue
		var ws := _war_score(key, rec)
		var score := float(ws.get("score", 0.0))
		var tier := clampi(int(ws.get("tier", 0)), 0, 3)
		var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
			foe.capitalize()))
		var trend := _war_trend(rec)
		var days := maxi(1, day - int(rec.get("start_day", day)))
		var reasons: Array = ws.get("reasons", [])
		var why := ""
		if not reasons.is_empty():
			why = " " + "; ".join(reasons.slice(0, 2)) + "."
		lines.append("The %s war: score %d (%s), %s, %s in.%s" % [
			fname, int(score), tier_names[tier], trend,
			_plural("day", days), why])
	if lines.is_empty():
		return "No wars, %s. The realm is at peace — suspiciously peaceful. Enjoy it." % _ruler()
	return "War report, %s — %s:\n%s" % [_ruler(),
		_plural("war", lines.size()), "\n".join(lines)]


## Score delta: this check's score vs the previous check's close.
## >3 worsening, <-3 improving, else holding.
func _war_trend(rec: Dictionary) -> String:
	var delta := float(rec.get("score", 0.0)) \
		- float(rec.get("prev_score", 0.0))
	if delta > 3.0:
		return "worsening"
	if delta < -3.0:
		return "improving"
	return "holding"


## --- 6. post-war analysis ------------------------------------------------------
## When a war ends, the Gazette gets the real numbers: casualties both
## sides, command posts gained/lost, territory delta, duration, and who
## sued for peace. Routes through court.publish_story so the Chronicle
## archives it (AGENTS.md Gazette rule); falls back to the bus headless.

func _post_war_analysis(key: String, rec: Dictionary) -> void:
	var foe := String(rec.get("foe", ""))
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	var day := int(_gs.get("day_number"))
	var days := maxi(1, day - int(rec.get("start_day", day)))
	var od := int(rec.get("ours_dead", 0))
	var td := int(rec.get("theirs_dead", 0))
	var pc := _war_post_changes(rec)
	var posts: Array = []
	if int(pc["tl"]) > 0:
		posts.append("lost %s" % _plural("town", int(pc["tl"])))
	if int(pc["ml"]) > 0:
		posts.append("lost %s" % _plural("monastery", int(pc["ml"])))
	if int(pc["cl"]) > 0:
		posts.append("lost %s" % _plural("dark crystal", int(pc["cl"])))
	if int(pc["tt"]) > 0:
		posts.append("took %s" % _plural("town", int(pc["tt"])))
	if int(pc["mt"]) > 0:
		posts.append("took %s" % _plural("monastery", int(pc["mt"])))
	if int(pc["ct"]) > 0:
		posts.append("took %s" % _plural("dark crystal", int(pc["ct"])))
	if int(pc["fl"]) > 0:
		posts.append("lost %s" % _plural("star fort", int(pc["fl"])))
	if int(pc["ft"]) > 0:
		posts.append("took %s" % _plural("star fort", int(pc["ft"])))
	var post_txt := "no command posts changed hands"
	if not posts.is_empty():
		post_txt = "we " + ", ".join(posts)
	var h := _hall_counts(foe)
	var h0: Dictionary = rec.get("halls0", {})
	var terr := int(h0.get("ours", 0)) - int(h.get("ours", 0))
	var terr_txt := "territory unchanged"
	if terr > 0:
		terr_txt = "%d fewer of our hall-claims" % terr
	elif terr < 0:
		terr_txt = "%d more of our hall-claims" % (-terr)
	var who := "both sides stood down"
	if bool(rec.get("we_sued", false)):
		who = "the crown sued for peace"
	elif _foe_broke(foe):
		who = "the %s sued for peace" % fname
	var headline := "WAR'S END: the %s war is over" % fname
	var body := "After %d %s, the %s war ended — %s. The butcher's bill: %d of ours dead, %d of theirs. Command posts: %s. Territory: %s." % [
		days, "day" if days == 1 else "days", fname, who, od, td,
		post_txt, terr_txt]
	var court = _gs.get("court_sys")
	if court != null and court.has_method("publish_story"):
		court.publish_story(headline, body, "war")
	elif _gs.get("bus") != null:
		_gs.bus.gazette_story.emit({"headline": headline, "body": body,
			"kind": "war", "day": day})
	# The War Advisor closes the counsel in Messenger too.
	var wa := _war_advisor()
	var phone = _gs.get("phone_sys")
	if not wa.is_empty() and phone != null \
			and phone.has_method("npc_message"):
		phone.npc_message(int(wa.get("id", 0)),
			"It's over, %s — the %s war ended after %d %s. %d of ours dead, %d of theirs; %s. The Gazette has the full tally." % [
				_ruler(), fname, days, "day" if days == 1 else "days",
				od, td, who])


## Heuristic: the foe's army is broken (under 40% of our strength).
func _foe_broke(foe: String) -> bool:
	var dip = _gs.get("diplomacy")
	if dip == null:
		return false
	var theirs := float(dip.military_strength(foe))
	var ours := float(dip.military_strength(_pf()))
	return theirs < ours * 0.4


## ==========================================================================
## LANE 1 — Ruler's Voice expansion (Jeremy 2026-10-06):
## multi-part commands, diplomacy verbs (peace / tribute / threaten),
## scouting, patrol / retreat / monastery-guard maneuvers, clarifying
## questions, and status queries answered with real numbers. Advisors keep
## their voice in every new path. War orders still route through the
## strategic-proposal confirm (no surprise wars); foreign cabinets still
## refuse (sovereignty).
## ==========================================================================

## Advisor unit id -> pending clarification {kind, question, extra, day}.
var _clarifications: Dictionary = {}

## Set while the current order asked a clarifying question (multi-part
## chains watch it to hold the remaining parts).
var _clarify_flag: bool = false

## Patrol detachments: patrol_id -> {name, cx, cy, radius, unit_ids,
## advisor_id, day}.
var _patrols: Dictionary = {}


## --- multi-part commands --------------------------------------------------
## "train 10 soldiers and build 3 farms", "raise taxes and hold a
## festival" — split on "and"/"then", every part must parse as an order or
## a status query, each part executes through the normal dispatch, one
## consolidated ack. A part that asks a clarifying question holds the
## remaining parts until the ruler answers.

## Splitter (static: no game state needed).
static func _parse_multi_part(t: String) -> Array:
	var out: Array = [t]
	for sep: String in [" and then ", " then ", " and "]:
		var nxt: Array = []
		for part: String in out:
			for p2: String in part.split(sep):
				var q := p2.strip_edges()
				if q != "":
					nxt.append(q)
		out = nxt
	return out


static func _num_word(n: int) -> String:
	var words := ["zero", "one", "two", "three", "four", "five", "six"]
	if n >= 0 and n < words.size():
		return words[n]
	return str(n)


func _order_multi(unit: Dictionary, parts: Array) -> String:
	var acks: Array = []
	var i := 0
	while i < parts.size():
		_clarify_flag = false
		var ack := _dispatch_order(unit, String(parts[i]))
		if _clarify_flag:
			# This part asked a question: hold the tail in the context.
			_hold_multi_tail(unit, parts, i)
			var prefix := ""
			if not acks.is_empty():
				prefix = "First %s done. " % ("bits" if acks.size() > 1 else "bit")
			return _fill(unit, prefix + "{ruler}, one question first: ") + ack
		if ack != "":
			acks.append(ack)
		i += 1
	if acks.is_empty():
		return ""
	var lead := _fill(unit, "A %s, {ruler}? Ambitious. All in motion. " \
		% _num_word(parts.size()))
	return lead + " ".join(acks)


func _hold_multi_tail(unit: Dictionary, parts: Array, i: int) -> void:
	var uid := str(int(unit.get("id", 0)))
	var ctx: Dictionary = _clarifications.get(uid, {})
	if ctx.is_empty():
		return
	var ex: Dictionary = ctx.get("extra", {})
	ex["resume_parts"] = parts.slice(i + 1)
	ctx["extra"] = ex
	_clarifications[uid] = ctx


## --- order dispatch -------------------------------------------------------
## One text -> one order family ack (orders and status queries). Extracted
## from try_order so multi-part commands dispatch each part identically.

func _dispatch_order(unit: Dictionary, t: String) -> String:
	var handler := _match_order(t)
	if handler == "":
		var st := _match_status(t)
		if st == "":
			return ""
		return _handle_status_query(unit, st)
	match handler:
		"envoy":
			return _order_envoy(unit, t)
		"war":
			return _order_war(unit, t)
		"military":
			return _order_military(unit, t)
		"build":
			return _order_build(unit, t)
		"train":
			return _order_train(unit, t)
		"economy":
			return _order_economy(unit, t)
		"civic":
			return _order_civic(unit, t)
		"peaceterms":
			return _order_peace_terms(unit, t)
		"wardashboard":
			return _war_dashboard(unit)
		"deals":
			return _order_deals(unit, t)
		"peace":
			return _order_peace(unit, t)
		"tribute":
			return _order_tribute(unit, t)
		"threat":
			return _order_threaten(unit, t)
		"scout":
			return _order_scout(unit, t)
	return ""


## --- faction / town / monastery resolution --------------------------------

## Faction noun in text -> real faction id, "" when none, "__self__" when
## the player's own faction (orders can't target the crown itself).
func _resolve_foe(t: String) -> String:
	var f := _faction_in(t)
	if f == "":
		return ""
	if f == _pf() or f == _pf_singular():
		return "__self__"
	return _faction_id(f)


func _pf_towns() -> Array:
	var out: Array = []
	for tid: Variant in _gs.towns:
		var town: Dictionary = _gs.towns[tid]
		if String(town.get("faction", "")) == _pf():
			out.append(town)
	return out


static func _town_names(towns: Array) -> Array:
	var out: Array = []
	for town: Dictionary in towns:
		out.append(String(town.get("name", "town")))
	return out


## First player town whose name appears in the text.
func _town_named(t: String) -> Dictionary:
	for tid: Variant in _gs.towns:
		var town: Dictionary = _gs.towns[tid]
		if String(town.get("faction", "")) != _pf():
			continue
		var nm := String(town.get("name", "")).to_lower()
		if nm != "" and t.contains(nm):
			return town
	return {}


static func _join_names(names: Array) -> String:
	if names.size() == 1:
		return String(names[0])
	if names.size() == 2:
		return "%s and %s" % [String(names[0]), String(names[1])]
	var head: Array = names.slice(0, names.size() - 1)
	return "%s, and %s" % [", ".join(head), String(names[names.size() - 1])]


func _our_monasteries() -> Array:
	var out: Array = []
	var sys = _gs.get("monasteries")
	if sys == null:
		return out
	for m: Dictionary in sys.monasteries:
		if String(m.get("owner", "")) == _pf():
			out.append(m)
	return out


## Id of the player's monastery named in the text, -1 when none matches.
func _monastery_named(t: String) -> int:
	for m: Dictionary in _our_monasteries():
		var nm := String(m.get("name", "")).to_lower()
		var short := nm.replace("monastery of ", "").split(" ")[0]
		if (nm != "" and t.contains(nm)) \
				or (short.length() > 3 and t.contains(short)):
			return int(m.get("id", -1))
	return -1


## --- clarifying questions -------------------------------------------------
## Ambiguous orders ask in the advisor's voice, hold pending, and resume
## when the player answers. A fresh order replaces the held one.

func _ask_clarification(unit: Dictionary, kind: String, question: String,
		extra: Dictionary) -> String:
	var uid := str(int(unit.get("id", 0)))
	_clarifications[uid] = {
		"kind": kind, "unit_id": int(unit.get("id", 0)),
		"advisor_name": String(unit.get("name", role_title(unit))),
		"job": String(unit.get("job", "")),
		"question": question, "extra": extra,
		"day": int(_gs.get("day_number")),
	}
	_clarify_flag = true
	return _fill(unit, question)


func _clarification_for(unit: Dictionary) -> Dictionary:
	var uid := str(int(unit.get("id", 0)))
	var ctx: Dictionary = _clarifications.get(uid, {})
	# Stale holds expire: 3 days without an answer drops the order
	# (2026-10-09 wake: was 5 — a days-old "which monastery?" kept
	# intercepting fresh orders too long).
	if not ctx.is_empty() \
			and int(_gs.get("day_number")) - int(ctx.get("day", 0)) > 3:
		_clarifications.erase(uid)
		return {}
	return ctx


func _answers_clarification(ctx: Dictionary, t: String) -> bool:
	match String(ctx.get("kind", "")):
		"build":
			return not _town_named(t).is_empty()
		"scout", "peace", "threat", "tribute":
			return not (_resolve_foe(t) in ["", "__self__"])
		"guard_monastery":
			return _monastery_named(t) != -1
	return false


func _answer_clarification(unit: Dictionary, ctx: Dictionary,
		t: String) -> String:
	var kind := String(ctx.get("kind", ""))
	var extra: Dictionary = ctx.get("extra", {})
	var ack := ""
	match kind:
		"build":
			var town := _town_named(t)
			if town.is_empty():
				return _fill(unit, "I need a town name, {ruler} — " \
					+ String(ctx.get("question", "")))
			ack = _execute_build(unit, String(extra.get("text", "")), town)
		"scout":
			var foe := _resolve_foe(t)
			if foe in ["", "__self__"]:
				return _fill(unit, "Name a faction, {ruler} — " \
					+ String(ctx.get("question", "")))
			ack = _execute_scout(unit, foe)
		"peace":
			var pfoe := _resolve_foe(t)
			if pfoe in ["", "__self__"]:
				return _fill(unit, "Name a faction, {ruler} — " \
					+ String(ctx.get("question", "")))
			ack = _execute_peace(unit, pfoe)
		"threat":
			var tfoe := _resolve_foe(t)
			if tfoe in ["", "__self__"]:
				return _fill(unit, "Name a faction, {ruler} — " \
					+ String(ctx.get("question", "")))
			ack = _execute_threaten(unit, tfoe)
		"tribute":
			var bfoe := _resolve_foe(t)
			if bfoe in ["", "__self__"]:
				return _fill(unit, "Name a faction, {ruler} — " \
					+ String(ctx.get("question", "")))
			ack = _execute_tribute(unit, bfoe,
				String(extra.get("resource", "gold")),
				int(extra.get("amount", 100)))
		"guard_monastery":
			var mid := _monastery_named(t)
			if mid == -1:
				return _fill(unit, "Name one of ours, {ruler} — " \
					+ String(ctx.get("question", "")))
			ack = _execute_guard_monastery(unit, mid)
	_clarifications.erase(str(int(unit.get("id", 0))))
	# Resume any multi-part tail held behind the question.
	var rest: Array = extra.get("resume_parts", [])
	if rest.is_empty():
		return ack
	return ack + " " + _order_multi(unit, rest)


## --- diplomacy verbs ------------------------------------------------------
## "make peace with the elves" — opens the sue_for_peace proposal flow
## (the phone modal confirms; nothing executes without the ruler's seal).
## "send the gnomes 100 gold tribute" — real resources change hands.
## "threaten the undead" — the outward SimDiplomacy.threaten path: the
## event is recorded, the relation score takes a real hit, and the
## target's AI answers through the normal daily tick (their threat comes
## back as a royal-court petition — the diplomacy petition path).

func _order_peace(unit: Dictionary, t: String) -> String:
	var foe := _resolve_foe(t)
	if foe == "__self__":
		return _fill(unit, "Peace with OURSELVES, {ruler}? We're already the picture of inner harmony.")
	if foe == "":
		return _ask_clarification(unit, "peace",
			"Peace with WHOM, {ruler}? Name a faction and I'll draw up the papers.",
			{"text": t})
	return _execute_peace(unit, foe)


func _execute_peace(unit: Dictionary, foe: String) -> String:
	var dip = _gs.get("diplomacy")
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name", foe.capitalize()))
	if dip == null:
		return _fill(unit, "No envoys to send, {ruler}. The doves are on strike.")
	if dip.relation_state(_pf(), foe) != "war":
		var st := String(dip.relation_state(_pf(), foe))
		return _fill(unit, "We're not at war with the %s, {ruler} — relations are merely %s. Nothing to sue for." % [fname, st])
	var prop = _gs.get("proposals")
	if prop == null:
		return _fill(unit, "The peace table's missing a leg, {ruler}. Try again shortly.")
	var res: Dictionary = prop.propose(_pf(), "sue_for_peace", {"target": foe})
	if not bool(res.get("ok", false)):
		return _fill(unit, "The council won't put peace to paper right now, {ruler} — try again in a few days.")
	if bool(res.get("duplicate", false)):
		return _fill(unit, "Already in motion, {ruler} — the peace papers for the %s are on your phone awaiting your seal." % fname)
	return _fill(unit, "At once, {ruler}. The peace offer to the %s is drawn up — it's on your phone awaiting YOUR seal. No signature, no surrender." % fname)


const TRIBUTE_RESOURCES := {"gold": "gold", "wood": "wood", "food": "food",
	"oil": "oil", "coin": "gold", "coins": "gold", "timber": "wood"}


static func _amount_in(t: String, cap: int = 5000) -> int:
	var m := RegEx.new()
	m.compile("\\b(\\d+)\\b")
	var r := m.search(t)
	if r != null:
		return maxi(1, mini(cap, int(r.get_string(1))))
	return -1


func _order_tribute(unit: Dictionary, t: String) -> String:
	var foe := _resolve_foe(t)
	if foe == "__self__":
		return _fill(unit, "Tribute to OURSELVES, {ruler}? The treasury thanks you for the paperwork.")
	var res_name := "gold"
	for k: String in TRIBUTE_RESOURCES:
		if t.contains(k):
			res_name = String(TRIBUTE_RESOURCES[k])
			break
	var amount := _amount_in(t)
	if amount < 0:
		amount = 100
	if foe == "":
		return _ask_clarification(unit, "tribute",
			"Send %d %s to WHOM, {ruler}? Name a faction." % [amount, res_name],
			{"text": t, "resource": res_name, "amount": amount})
	return _execute_tribute(unit, foe, res_name, amount)


func _execute_tribute(unit: Dictionary, foe: String, res_name: String,
		amount: int) -> String:
	var dip = _gs.get("diplomacy")
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name", foe.capitalize()))
	if dip == null or not dip.has_method("pay_tribute"):
		return _fill(unit, "No envoys to carry it, {ruler}.")
	var res = _gs.get("resources")
	var have := int(res.get_amount(_pf(), res_name)) if res != null else 0
	if have <= 0:
		return _fill(unit, "The vault's bare, {ruler} — not a scrap of %s to send the %s." % [res_name, fname])
	var paid := int(dip.pay_tribute(_pf(), foe, res_name, float(amount)))
	if paid <= 0:
		return _fill(unit, "The coffers coughed up nothing, {ruler}.")
	var extra := ""
	if paid < amount:
		extra = " (We only had %d to give.)" % paid
	return _fill(unit, "%d %s to the %s, {ruler} — envoys ride at dawn, purses heavy. Peace has a price; we just paid it.%s" % [paid, res_name, fname, extra])


func _order_threaten(unit: Dictionary, t: String) -> String:
	var foe := _resolve_foe(t)
	if foe == "__self__":
		return _fill(unit, "Threaten OURSELVES, {ruler}? The mirror sends its regards.")
	if foe == "":
		return _ask_clarification(unit, "threat",
			"Threaten WHOM, {ruler}? Name a faction and I'll darken their doorstep.",
			{"text": t})
	return _execute_threaten(unit, foe)


func _execute_threaten(unit: Dictionary, foe: String) -> String:
	var dip = _gs.get("diplomacy")
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name", foe.capitalize()))
	if dip == null or not dip.has_method("threaten"):
		return _fill(unit, "The envoys lost their nerve, {ruler}.")
	var res: Dictionary = dip.threaten(_pf(), foe)
	if not bool(res.get("ok", false)):
		return _fill(unit, "%s {ruler}." % String(res.get("msg", "The threat died in committee.")))
	return _fill(unit, "Done, {ruler} — our envoy told the %s court exactly where they stand, in small words. They'll answer in kind; watch the borders." % fname)


## --- scouting -------------------------------------------------------------
## "scout the elves" — riders go out; the intel report lands in Messenger
## two days later (the war-campaign scout-phase cadence), assembled from
## the same numbers the war council uses (strategic_brief).

func _order_scout(unit: Dictionary, t: String) -> String:
	var foe := _resolve_foe(t)
	if foe == "__self__":
		return _fill(unit, "Scout OURSELVES, {ruler}? I can report: we're right here.")
	if foe == "":
		return _ask_clarification(unit, "scout",
			"Scout WHOM, {ruler}? Name a faction and riders go out by dusk.",
			{"text": t})
	return _execute_scout(unit, foe)


func _execute_scout(unit: Dictionary, foe: String) -> String:
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name", foe.capitalize()))
	_pending.append({
		"kind": "scout",
		"advisor_id": int(unit.get("id", 0)),
		"advisor_name": String(unit.get("name", role_title(unit))),
		"foe": foe, "fname": fname,
		"day_issued": int(_gs.get("day_number")),
	})
	return _fill(unit, "Riders out by dusk, {ruler}. They'll count %s spears and sniff out weakness — full report in two days." % fname)


func _poll_scout(o: Dictionary) -> String:
	var day := int(_gs.get("day_number"))
	if day - int(o.get("day_issued", day)) < 2:
		return ""
	var foe := String(o.get("foe", ""))
	var fname := String(o.get("fname", foe.capitalize()))
	var txt := String(strategic_brief(foe).get("text", ""))
	if txt == "":
		txt = "The scouts report: nothing worth stealing."
	var rel := ""
	var dip = _gs.get("diplomacy")
	if dip != null:
		rel = String(dip.relation_state(_pf(), foe))
	return "Scout's report, %s — on the %s: %s (Relations: %s.)" % [_ruler(), fname, txt, rel]


## --- maneuvers: patrol / retreat / guard monastery ------------------------

## Alive military of the faction with no standing assignment.
func _idle_military(want: int) -> Array:
	var out: Array = []
	for u: Dictionary in _gs.units:
		if out.size() >= want:
			break
		if String(u.get("faction", "")) != _pf():
			continue
		if not bool(u.get("alive", false)):
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		if SimCombat.is_downed(u):
			continue
		if u.has("deploy_target_id") or u.has("deployed_for_war") \
				or u.has("mustering") or u.has("withdrawing"):
			continue
		var po: Dictionary = u.get("player_order", {})
		if not po.is_empty():
			continue
		if u.has("post_guard") or u.has("monastery_guard"):
			continue
		out.append(u)
	return out


## "patrol the north border" — a detachment walks the line. The daily tick
## rotates waypoints inside the patrol radius (real movement); defend_mode
## keeps blades loose; the player_order mark keeps the adviser AI from
## yanking them into work crews.
func _order_patrol(unit: Dictionary, t: String) -> String:
	if _has_any(t, ["stop patrol", "end patrol", "recall patrol",
			"recall the patrol", "call off the patrol",
			"stand down the patrol"]):
		return _recall_patrols(unit)
	var spot := _patrol_point(t)
	var pname := String(spot.get("name", "the border"))
	var center: Vector2 = spot.get("center", Vector2.ZERO)
	var troops := _idle_military(4)
	if troops.is_empty():
		return _fill(unit, "No free blades for a patrol, {ruler} — every soldier's spoken for.")
	var pid := "patrol_%d_%d" % [int(_gs.get("day_number")), _patrols.size()]
	var ids: Array = []
	for u: Dictionary in troops:
		u["player_order"] = {"type": "patrol", "patrol_id": pid}
		u["defend_mode"] = true
		u["move_target"] = center + Vector2(
			randf_range(-120.0, 120.0), randf_range(-120.0, 120.0))
		ids.append(int(u.get("id", 0)))
	_patrols[pid] = {"name": pname, "cx": center.x, "cy": center.y,
		"radius": 320.0, "unit_ids": ids,
		"advisor_id": int(unit.get("id", 0)),
		"day": int(_gs.get("day_number"))}
	return _fill(unit, "%s to patrol %s, {ruler} — eyes open, blades loose. They'll walk the line till you call them home." % [_plural("rider", ids.size()).capitalize(), pname])


func _recall_patrols(unit: Dictionary) -> String:
	if _patrols.is_empty():
		return _fill(unit, "No patrols out, {ruler} — the roads walk themselves.")
	var n := 0
	for pid: String in _patrols:
		var p: Dictionary = _patrols[pid]
		for uid in p.get("unit_ids", []):
			var u: Dictionary = _gs.get_unit(int(uid))
			if u.is_empty():
				continue
			var po: Dictionary = u.get("player_order", {})
			if String(po.get("type", "")) == "patrol":
				u["player_order"] = {}
				u["defend_mode"] = false
				n += 1
	_patrols.clear()
	return _fill(unit, "Patrols recalled, {ruler} — %s back to their posts." % _plural("rider", n))


## Where "the north border" is: a named town, else the border-wall region
## centroid furthest in the named direction, else a point out from town.
func _patrol_point(t: String) -> Dictionary:
	var dir := ""
	for d: String in ["north", "south", "east", "west"]:
		if t.contains(d):
			dir = d
			break
	var home := _home_town()
	var hpos: Vector2 = home.get("position", Vector2(2048, 2048))
	var town := _town_named(t)
	if not town.is_empty():
		return {"name": String(town.get("name", "town")),
			"center": town.get("position", hpos)}
	var regions := _border_region_centroids()
	if not regions.is_empty():
		var best := {}
		var best_key := -INF
		for r: Dictionary in regions:
			var c: Vector2 = r.get("center", hpos)
			var key := 0.0
			match dir:
				"north":
					key = hpos.y - c.y
				"south":
					key = c.y - hpos.y
				"east":
					key = c.x - hpos.x
				"west":
					key = hpos.x - c.x
				_:
					key = -hpos.distance_to(c)
			if best.is_empty() or key > best_key:
				best = r
				best_key = key
		return {"name": "the %s border" % String(best.get("name", "border")),
			"center": best.get("center", hpos)}
	var off := Vector2.ZERO
	match dir:
		"north":
			off = Vector2(0, -900)
		"south":
			off = Vector2(0, 900)
		"east":
			off = Vector2(900, 0)
		"west":
			off = Vector2(-900, 0)
	var dname := dir if dir != "" else "near"
	return {"name": "the %s border" % dname, "center": hpos + off}


func _border_region_centroids() -> Array:
	var out: Array = []
	var bw = _gs.get("border_walls")
	if bw == null:
		return out
	for e: Dictionary in bw.pending:
		if String(e.get("faction", "")) != _pf():
			continue
		var sum := Vector2.ZERO
		var n := 0
		for run: Dictionary in e.get("runs", []):
			for p in run.get("pts", []):
				sum += p
				n += 1
		if n == 0:
			continue
		out.append({"name": String(e.get("region_name", "border")),
			"center": sum / float(n)})
	return out


## Daily: patrols walk. Units that reached their waypoint get a fresh one
## inside the radius; dead or re-tasked units drop out.
func _patrol_tick() -> void:
	if _patrols.is_empty():
		return
	var dead_p: Array = []
	for pid: String in _patrols:
		var p: Dictionary = _patrols[pid]
		var center := Vector2(float(p.get("cx", 0.0)), float(p.get("cy", 0.0)))
		var radius := float(p.get("radius", 320.0))
		var keep: Array = []
		for uid in p.get("unit_ids", []):
			var u: Dictionary = _gs.get_unit(int(uid))
			if u.is_empty() or not bool(u.get("alive", false)):
				continue
			var po: Dictionary = u.get("player_order", {})
			if String(po.get("type", "")) != "patrol" \
					or String(po.get("patrol_id", "")) != pid:
				continue
			keep.append(int(uid))
			var mt = u.get("move_target")
			var upos: Vector2 = u.get("position", center)
			if mt == null or upos.distance_to(mt) < 90.0:
				var ang := randf() * TAU
				var rr := randf_range(radius * 0.4, radius)
				u["move_target"] = center + Vector2(cos(ang), sin(ang)) * rr
			u["defend_mode"] = true
		if keep.is_empty():
			dead_p.append(pid)
		else:
			p["unit_ids"] = keep
	for pid: String in dead_p:
		_patrols.erase(pid)


## "guard the monastery" — posts a real detachment (monastery_guard +
## post_guard marks, the same marks the AI director's _refresh_post_marches
## keeps sticky). Reports back if the post falls.
func _order_guard_monastery(unit: Dictionary, t: String) -> String:
	var ours := _our_monasteries()
	if ours.is_empty():
		return _fill(unit, "We hold no monastery, {ruler} — nothing to guard but our pride.")
	if ours.size() == 1:
		return _execute_guard_monastery(unit, int(ours[0].get("id", -1)))
	var mid := _monastery_named(t)
	if mid != -1:
		return _execute_guard_monastery(unit, mid)
	var names: Array = []
	for m: Dictionary in ours:
		names.append(String(m.get("name", "monastery")))
	return _ask_clarification(unit, "guard_monastery",
		"Which monastery, {ruler}? We hold %s — name one." % _join_names(names),
		{"text": t})


func _execute_guard_monastery(unit: Dictionary, mid: int) -> String:
	var m: Dictionary = {}
	var sys = _gs.get("monasteries")
	if sys != null:
		for mm: Dictionary in sys.monasteries:
			if int(mm.get("id", -1)) == mid:
				m = mm
				break
	if m.is_empty():
		return _fill(unit, "That monastery slipped off the map, {ruler}.")
	var mpos: Vector2 = m.get("position", Vector2.ZERO)
	var mname := String(m.get("name", "the monastery"))
	var troops := _idle_military(6)
	if troops.is_empty():
		return _fill(unit, "No free blades to post at %s, {ruler} — every soldier's spoken for." % mname)
	var n := 0
	for u: Dictionary in troops:
		u["monastery_guard"] = mid
		u["post_guard"] = {"kind": "monastery", "id": mid}
		u["defend_mode"] = true
		u["move_target"] = mpos + Vector2(
			randf_range(-80.0, 80.0), randf_range(-80.0, 80.0))
		n += 1
	_pending.append({
		"kind": "guard_post", "post_kind": "monastery", "post_id": mid,
		"post_name": mname,
		"advisor_id": int(unit.get("id", 0)),
		"advisor_name": String(unit.get("name", role_title(unit))),
		"day_issued": int(_gs.get("day_number")),
	})
	return _fill(unit, "%s to guard %s, {ruler} — they'll hold the doors till the stone weeps." % [_plural("guard", n).capitalize(), mname])


func _poll_guard_post(o: Dictionary) -> String:
	var mid := int(o.get("post_id", -1))
	var sys = _gs.get("monasteries")
	var owner := ""
	if sys != null:
		for m: Dictionary in sys.monasteries:
			if int(m.get("id", -1)) == mid:
				owner = String(m.get("owner", ""))
				break
	if owner != _pf():
		return "%s — we lost %s despite the guard. The survivors are walking home." % [_ruler().capitalize(), String(o.get("post_name", "the monastery"))]
	var day := int(_gs.get("day_number"))
	if day - int(o.get("day_issued", day)) >= 3:
		return "The guard holds %s, %s — doors barred, incense lit, nobody's getting in." % [String(o.get("post_name", "the monastery")), _ruler()]
	return ""


## --- build orders: town-aware ------------------------------------------------
## "build a farm" with one town just builds; with several, the advisor
## asks which town, holds the order, and resumes on the answer.

func _execute_build(unit: Dictionary, t: String, town: Dictionary) -> String:
	var btype := _building_in(t)
	var want := _count_in(t)
	var bs := SimBuildings.new(_gs)
	var res = _gs.get("resources")
	if res == null:
		return _fill(unit, "The builders' ledgers are missing, {ruler}. Give me a moment.")
	var bname: String = String(SimBuildings.BUILDINGS[btype].get("name", btype))
	var cost: Dictionary = SimBuildings.cost_of(btype)
	if not res.can_afford(_pf(), cost):
		var alt := _affordable_alt(btype)
		var alt_txt := ""
		if alt != "":
			alt_txt = " We CAN afford %s right now, if that helps." % alt
		return _fill(unit, "We can't afford %s, {ruler} — the coffers won't stretch to it.%s" % [_plural(bname, 1), alt_txt])
	var center: Vector2 = town.get("position", Vector2.ZERO)
	var placed: Array = []
	for i: int in want:
		var spot := _find_spot(center, i)
		var bp: Dictionary = bs.place_blueprint(btype, _pf(),
			int(town.get("id", -1)), spot)
		if bp.is_empty():
			break
		bp["player_placed"] = true
		placed.append(int(bp.get("id", 0)))
	var got := placed.size()
	if got == 0:
		return _fill(unit, "The builders balked, {ruler} — coin or timber ran dry mid-order. Check the stockpiles.")
	_track_build_order(unit, btype, bname, placed)
	var done_txt := "Blueprint's drawn and the crews are moving, {ruler}."
	if got < want:
		done_txt = "We managed %d of %d — the coffers ran dry, {ruler}." % [got, want]
	return _fill(unit, "%s, coming up. %s" % [_plural(bname, got), done_txt])


## --- status queries ---------------------------------------------------------
## Questions to the cabinet, answered in Messenger with real numbers:
## "report on the war", "how's our food?", "what is my army doing?",
## "how much gold do we have?", "status report".

func _match_status(t: String) -> String:
	if _has_any(t, ["report on the war", "how is the war", "war update"]):
		return "war"
	if _has_any(t, ["hows our food", "how is our food", "food report",
			"food situation"]):
		return "food"
	if _has_any(t, ["what is my army doing", "what is the army doing",
			"army report", "army status", "how is the army",
			"troop report"]):
		return "army"
	if _has_any(t, ["how much gold", "gold report", "treasury report",
			"how are the coffers", "coffers report", "treasury status",
			"how is the treasury"]):
		return "treasury"
	if _has_any(t, ["status report", "realm report", "kingdom report",
			"how goes the realm", "realm status"]):
		return "realm"
	return ""


func _handle_status_query(unit: Dictionary, st: String) -> String:
	match st:
		"war":
			return _status_war(unit)
		"food":
			return _status_food(unit)
		"army":
			return _status_army(unit)
		"treasury":
			return _status_treasury(unit)
		"realm":
			return _status_realm(unit)
	return ""


## Per-war scores: casualties, posts, territory, tier — real numbers.
func _status_war(unit: Dictionary) -> String:
	var dip = _gs.get("diplomacy")
	var foes: Array = []
	if dip != null:
		for f: String in _gs.active_factions:
			if f != _pf() and dip.relation_state(_pf(), f) == "war":
				foes.append(f)
	if foes.is_empty():
		return _fill(unit, "Peace on all fronts, {ruler} — the realm breathes easy. Enjoy it; it never lasts.")
	var tiers := ["even", "concerning", "urgent", "desperate"]
	var bits: Array = []
	for foe: String in foes:
		var key := "%s|%s" % [_pf(), foe]
		var rec: Dictionary = _wars.get(key, {})
		if rec.is_empty():
			rec = _new_war_record(foe)
		var ws := _war_score(key, rec)
		var fname: String = String(Config.FACTIONS.get(foe, {}).get("name", foe.capitalize()))
		var tier := clampi(int(ws.get("tier", 0)), 0, 3)
		var line := "the %s: %d of ours dead, %d of theirs — %s" % [
			fname, int(rec.get("ours_dead", 0)),
			int(rec.get("theirs_dead", 0)), tiers[tier]]
		var reasons: Array = ws.get("reasons", [])
		if not reasons.is_empty():
			line += " (%s)" % "; ".join(reasons)
		bits.append(line)
	return _fill(unit, "War report, {ruler}: " + " ".join(bits) + ".")


## Food stock, mouths, per-head — the famine threshold (3.0/head) is the
## same one the AI's famine response uses.
func _status_food(unit: Dictionary) -> String:
	var res = _gs.get("resources")
	var food := 0.0
	if res != null:
		food = float(res.get_amount(_pf(), "food"))
	var pop := 0
	var farmers := 0
	if _gs.get("population") != null:
		pop = int(_gs.population.get_faction_pop(_pf()))
		farmers = int(_gs.population.count_job(_pf(), "farmer"))
	var per := food / maxf(1.0, float(pop))
	var verdict := "granaries full"
	if per < 3.0:
		verdict = "FAMINE RISK — bellies will be empty within days"
	elif per < 6.0:
		verdict = "thin — one bad harvest from hunger"
	elif per < 12.0:
		verdict = "adequate, nothing to feast on"
	return _fill(unit, "Food, {ruler}: %d in store, %d mouths — that's %.1f per head, with %d farmers working. Verdict: %s." % [int(food), pop, per, farmers, verdict])


## Army posture: stance, blades, warlord, wars, deployments.
func _status_army(unit: Dictionary) -> String:
	var army = _gs.get("army")
	if army == null:
		return _fill(unit, "No army to speak of, {ruler}.")
	var info: Dictionary = army.army_info(_pf())
	var wl := ""
	if bool(info.get("warlord", false)):
		wl = ", led by warlord %s" % String(info.get("warlord_name", ""))
	var wtxt := "at peace"
	var fn: Array = []
	for f in info.get("at_war", []):
		fn.append(String(Config.FACTIONS.get(String(f), {}).get("name", String(f).capitalize())))
	if not fn.is_empty():
		wtxt = "at war with the %s" % ", ".join(fn)
	var deployed := 0
	var patrol_n := 0
	var guard_n := 0
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) != _pf() \
				or not bool(u.get("alive", false)):
			continue
		if u.has("deployed_for_war"):
			deployed += 1
		var po: Dictionary = u.get("player_order", {})
		if String(po.get("type", "")) == "patrol":
			patrol_n += 1
		if u.has("monastery_guard") or u.has("post_guard"):
			guard_n += 1
	return _fill(unit, "The army, {ruler}: %d blades standing (%d down), stance %s%s, morale %d — %s. %d deployed for war, %d on patrol, %d guarding posts." % [
		int(info.get("troops", 0)), int(info.get("downed", 0)),
		String(info.get("stance", "auto")), wl,
		int(info.get("morale", 0.0)), wtxt, deployed, patrol_n, guard_n])


## Treasury: the four stocks plus the tax rate.
func _status_treasury(unit: Dictionary) -> String:
	var res = _gs.get("resources")
	var gold := 0.0
	var wood := 0.0
	var oil := 0.0
	if res != null:
		gold = float(res.get_amount(_pf(), "gold"))
		wood = float(res.get_amount(_pf(), "wood"))
		oil = float(res.get_amount(_pf(), "oil"))
	var tax := 10
	var pol = _policies()
	if pol != null and pol.get("state") is Dictionary:
		tax = int((pol.get("state") as Dictionary).get("tax", 10))
	var mood := "Spend it wisely." if gold > 500.0 else "We're counting coppers."
	return _fill(unit, "The coffers, {ruler}: %d gold, %d wood, %d oil — taxes at %d%%. %s" % [int(gold), int(wood), int(oil), tax, mood])


## Realm summary: one line, the big numbers.
func _status_realm(unit: Dictionary) -> String:
	var res = _gs.get("resources")
	var gold := 0.0
	var food := 0.0
	if res != null:
		gold = float(res.get_amount(_pf(), "gold"))
		food = float(res.get_amount(_pf(), "food"))
	var pop := 0
	if _gs.get("population") != null:
		pop = int(_gs.population.get_faction_pop(_pf()))
	var troops := 0
	var army = _gs.get("army")
	if army != null:
		troops = int((army.army_info(_pf()) as Dictionary).get("troops", 0))
	var wars := 0
	var dip = _gs.get("diplomacy")
	if dip != null:
		for f: String in _gs.active_factions:
			if f != _pf() and dip.relation_state(_pf(), f) == "war":
				wars += 1
	var tail := "The crown endures." if wars == 0 else "The drums beat."
	return _fill(unit, "The realm, {ruler}: %d gold, %d souls, %d blades under arms, food %.1f a head, %s. %s" % [
		int(gold), pop, troops, food / maxf(1.0, float(pop)),
		_plural("war", wars), tail])


## --- plea redirect ----------------------------------------------------------
## A peace-terms verdict ("accept") must not swallow a NEW order that names
## a different faction ("make peace with the gnomes" while the elves plea
## is pending is an order, not an answer).

func _plea_redirect(t: String, plea: Dictionary) -> bool:
	var f := _faction_in(t)
	return f != "" and _faction_id(f) != String(plea.get("foe", ""))


## --- dialogue trees: cabinet conversations ----------------------------------
## Jeremy 2026-10-11: every advisor carries a FULL unique dialogue tree.
## "talk" / "report" / "advice" / "what's on your mind" (or the advisor's
## name) opens a numbered topic menu in that advisor's own voice; picking a
## number or a topic keyword answers from LIVE game state and offers
## follow-ups that go deeper. Menu context is per-advisor-thread and
## transient (never saved): a real order or status query always wins over
## a keyword pick and clears a stale menu.
##
## The Treasury advisor additionally executes trade-deal commands
## (_order_deals): propose/cancel/counter/auto-manage via gs.trade_deals.
## Other advisors redirect deal talk to the Treasury desk, in their voice.
## Foreign cabinets refuse deal commands like any other order (sovereignty).

## role -> topics: {key, label, keywords}. Keywords are only consulted when
## the text is NOT an order or status query (orders always win).
const DIALOGUE_TOPICS := {
	"advisor_economy": [
		{"key": "treasury", "label": "Treasury",
			"keywords": ["treasury", "coffers", "vault", "money", "stocks"]},
		{"key": "deals", "label": "Trade deals",
			"keywords": ["deal", "ledger", "trade", "merchant"]},
		{"key": "advice", "label": "Economic advice",
			"keywords": ["advice", "economy", "invest", "build what"]},
		{"key": "warnings", "label": "Warnings",
			"keywords": ["warn", "danger", "problem", "bleed", "risk"]},
	],
	"advisor_war": [
		{"key": "army", "label": "Army strength",
			"keywords": ["army", "troops", "strength", "soldiers", "blades"]},
		{"key": "threats", "label": "Border threats",
			"keywords": ["threat", "border", "enemy", "enemies", "danger"]},
		{"key": "posts", "label": "Command posts",
			"keywords": ["post", "territory", "capture", "command post"]},
		{"key": "forts", "label": "Star forts",
			"keywords": ["fort", "starfort", "star fort", "fortress"]},
	],
	"advisor_civic": [
		{"key": "people", "label": "People & housing",
			"keywords": ["people", "population", "housing", "citizen", "resident"]},
		{"key": "needs", "label": "Needs & urges",
			"keywords": ["need", "urge", "hungry", "hunger", "mood", "happy"]},
		{"key": "festival", "label": "Festivals",
			"keywords": ["festival", "feast", "party", "celebrate"]},
		{"key": "crime", "label": "Crime & guards",
			"keywords": ["crime", "jail", "guard", "thief", "criminal"]},
	],
	"guild_master": [
		{"key": "staffing", "label": "Staffing",
			"keywords": ["staff", "hiring", "hire", "employee", "idle"]},
		{"key": "queues", "label": "Training queues",
			"keywords": ["queue", "training", "recruit", "trainee"]},
		{"key": "shops", "label": "Shops",
			"keywords": ["shop", "store", "market", "business", "stall"]},
		{"key": "roster", "label": "Workforce roster",
			"keywords": ["workforce", "labor", "roster", "workers"]},
	],
	"clerk": [
		{"key": "draft", "label": "The draft",
			"keywords": ["draft", "conscript", "enlist", "recruit"]},
		{"key": "muster", "label": "Muster status",
			"keywords": ["muster", "mobilize", "deploy"]},
		{"key": "paperwork", "label": "Paperwork",
			"keywords": ["paper", "form", "file", "pending", "desk"]},
		{"key": "rules", "label": "Draft rules",
			"keywords": ["rule", "law", "eligible", "exempt"]},
	],
}


## Resource nouns for parsing trade proposals ("offer 100 wood for 50 gold").
const TRADE_RES_NOUNS := {
	"soul essence": "soul_essence", "soul_essence": "soul_essence",
	"essence": "soul_essence", "souls": "soul_essence",
	"gold": "gold", "wood": "wood", "food": "food",
	"oil": "oil", "seeds": "seeds", "seed": "seeds",
}

## Building types that count as shops for the Guild Master's report.
const DIALOGUE_SHOP_TYPES := ["shop", "general_store", "blacksmith",
	"moonberry_lounge", "greasy_spoon", "restaurant", "inn"]
## Civilian shop-staff jobs (jobs.gd: shop staff category).
const DIALOGUE_SHOP_JOBS := ["shopkeeper", "cashier", "barkeep",
	"innkeeper", "smith", "repairman"]


## --- dialogue layer ---------------------------------------------------------

## Dialogue hook called from try_order before order dispatch. Returns ""
## for anything that isn't dialogue (orders, status queries, chit-chat),
## so those fall through untouched.
func _try_dialogue(unit: Dictionary, t: String) -> String:
	var role := String(unit.get("job", ""))
	if not (role in DIALOGUE_TOPICS):
		return ""
	var uid := str(int(unit.get("id", 0)))
	var menu: Dictionary = _dialogue.get(uid, {})
	if not menu.is_empty():
		# A menu is open: exact number picks always count; keyword picks
		# only when the text isn't an order/status (orders always win and
		# clear the stale menu); chit-chat leaves the menu alive.
		var pick := _menu_pick(menu, t)
		if pick != "":
			return _dialogue_answer(unit, role, uid, menu, pick)
		if _match_order(t) != "" or _match_status(t) != "":
			_dialogue.erase(uid)
			return ""
		return ""
	# No menu open: real orders/status queries fall through untouched.
	if _match_order(t) != "" or _match_status(t) != "":
		return ""
	if _is_dialogue_opener(unit, t):
		return _dialogue_menu(unit, role, uid)
	var jump := _dialogue_topic_jump(role, t)
	if jump != "":
		return _dialogue_topic(unit, role, uid, jump)
	return ""


## "talk" / "report" / "advice" / "what's on your mind" / advisor's name.
static func _is_dialogue_opener(unit: Dictionary, t: String) -> bool:
	if t in ["talk", "speak", "report", "advice", "counsel",
			"brief me", "talk to me", "speak to me", "whats up",
			"hows it going", "how are things", "how goes it"]:
		return true
	if t.contains("whats on your mind") \
			or t.contains("what is on your mind"):
		return true
	var nm := String(unit.get("name", "")).to_lower().strip_edges()
	if nm != "" and (t == nm or t.begins_with(nm + " ") \
			or t == "hey " + nm or t == "hello " + nm):
		return true
	return false


## Bare topic keyword -> jump straight to that topic (no menu open).
static func _dialogue_topic_jump(role: String, t: String) -> String:
	var topics: Array = DIALOGUE_TOPICS.get(role, [])
	for tp: Dictionary in topics:
		for kw: String in tp.get("keywords", []):
			if t == kw or t.contains(kw):
				return String(tp.get("key", ""))
	return ""


## Pick an option from an open menu: exact number ("1", "one", "option 2"),
## else a keyword match (only when the text isn't an order/status).
func _menu_pick(menu: Dictionary, t: String) -> String:
	var opts: Array = menu.get("options", [])
	if opts.is_empty():
		return ""
	var n := _pick_number(t)
	if n >= 1 and n <= opts.size():
		return String((opts[n - 1] as Dictionary).get("key", ""))
	if _match_order(t) != "" or _match_status(t) != "":
		return ""
	for o: Dictionary in opts:
		for kw: String in o.get("keywords", []):
			if t == kw or t.contains(kw):
				return String(o.get("key", ""))
	return ""


static func _pick_number(t: String) -> int:
	var s := t.strip_edges()
	if s.is_valid_int():
		return int(s)
	if NUMBER_WORDS.has(s):
		return int(NUMBER_WORDS[s])
	var m := RegEx.new()
	m.compile("^(option|number|pick|choice)\\s+(\\d+)$")
	var r := m.search(s)
	if r != null:
		return int(r.get_string(2))
	return 0


## Numbered topic menu in the advisor's voice.
func _dialogue_menu(unit: Dictionary, role: String, uid: String) -> String:
	var topics: Array = DIALOGUE_TOPICS[role]
	var opts: Array = []
	for tp: Dictionary in topics:
		opts.append({"key": String(tp["key"]), "label": String(tp["label"]),
			"keywords": tp.get("keywords", [])})
	_dialogue[uid] = {"kind": "topics", "options": opts}
	var lines: Array[String] = []
	var i := 1
	for o: Dictionary in opts:
		lines.append("%d. %s" % [i, String(o["label"])])
		i += 1
	return _fill(unit, _dialogue_greeting(role) + "  " + "  ".join(lines) \
		+ "  (say the number, or name the topic)")


func _dialogue_greeting(role: String) -> String:
	match role:
		"advisor_economy":
			return "Coin's my love language, boss. What's on the ledger today?"
		"advisor_war":
			return "Speak, {ruler}. Blades or borders?"
		"advisor_civic":
			return "Oh, {ruler}! Always a joy. What weighs on your heart?"
		"guild_master":
			return "{ruler}. The guild's wheels turn. What needs staffing?"
		"clerk":
			return "Y-yes, {ruler}! The Draft Clerk, at your service. Today's topics:"
	return "Yes, {ruler}?"


## Route a menu pick: topic menu -> topic body; follow-up menu -> follow-up.
func _dialogue_answer(unit: Dictionary, role: String, uid: String,
		menu: Dictionary, pick: String) -> String:
	if String(menu.get("kind", "")) == "topics":
		return _dialogue_topic(unit, role, uid, pick)
	return _dialogue_followup(unit, role, uid,
		String(menu.get("topic", "")), pick)


## Show a topic body; stash its follow-up menu (always ending in "back").
func _dialogue_topic(unit: Dictionary, role: String, uid: String,
		key: String) -> String:
	var res: Dictionary = _topic_body(unit, role, key)
	var fups: Array = res.get("followups", [])
	fups.append({"key": "back", "label": "Back to topics",
		"keywords": ["back", "topics", "menu"]})
	_dialogue[uid] = {"kind": "followups", "topic": key, "options": fups}
	return _fill(unit, _topic_text(res))


## Show a follow-up; "back" re-opens the topic menu.
func _dialogue_followup(unit: Dictionary, role: String, uid: String,
		topic: String, fkey: String) -> String:
	if fkey == "back":
		return _dialogue_menu(unit, role, uid)
	var res: Dictionary = _followup_body(unit, role, topic, fkey)
	# Terminal markers: reuse a full voiced status answer directly.
	match String(res.get("text", "")):
		"__war_status__":
			_dialogue.erase(uid)
			return _status_war(unit)
		"__food_status__":
			_dialogue.erase(uid)
			return _status_food(unit)
	var fups: Array = res.get("followups", [])
	fups.append({"key": "back", "label": "Back to topics",
		"keywords": ["back", "topics", "menu"]})
	_dialogue[uid] = {"kind": "followups", "topic": topic,
		"options": fups}
	return _fill(unit, _topic_text(res))


static func _topic_text(res: Dictionary) -> String:
	var out := String(res.get("text", ""))
	var lines: Array[String] = []
	var i := 1
	for f: Dictionary in res.get("followups", []):
		lines.append("%d. %s" % [i, String(f["label"])])
		i += 1
	lines.append("%d. Back to topics" % i)
	if not lines.is_empty():
		out += "  " + "  ".join(lines)
	return out


## --- shared live-state helpers ----------------------------------------------

func _dlg_stocks() -> Dictionary:
	var out := {}
	var res = _gs.get("resources")
	for r: String in Config.RESOURCES:
		out[r] = float(res.get_amount(_pf(), r)) if res != null else 0.0
	return out


func _dlg_building_count(btype: String, complete_only: bool = true) -> int:
	var n := 0
	for b: Dictionary in _gs.buildings:
		if String(b.get("faction", "")) != _pf():
			continue
		if not bool(b.get("alive", true)):
			continue
		if String(b.get("type", "")) != btype:
			continue
		if complete_only and not bool(b.get("complete", false)):
			continue
		n += 1
	return n


func _dlg_job(job: String) -> int:
	var pop = _gs.get("population")
	if pop == null:
		return 0
	return int(pop.count_job(_pf(), job))


func _dlg_pop() -> int:
	var pop = _gs.get("population")
	if pop == null:
		return 0
	return int(pop.get_faction_pop(_pf()))


func _dlg_town_pop(town: Dictionary) -> int:
	var tid := int(town.get("id", -1))
	var n := 0
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != _pf():
			continue
		if int(u.get("town_id", -2)) == tid:
			n += 1
	return n


func _dlg_tax_rate() -> int:
	var pol = _policies()
	if pol == null or not (pol.get("state") is Dictionary):
		return 10
	return int((pol.get("state") as Dictionary).get("tax", 10))


func _dlg_tax_income() -> int:
	var pol = _policies()
	if pol == null or not pol.has_method("projected_tax_income"):
		return 0
	return int(pol.projected_tax_income())


## Daily guard upkeep, same formula as SimPolicies.daily_tick.
func _dlg_guard_upkeep() -> Dictionary:
	var pol = _policies()
	if pol == null or not pol.has_method("guard_units"):
		return {"count": 0, "cost": 0}
	var guards: Array = pol.guard_units()
	var tier := ""
	if pol.get("state") is Dictionary:
		tier = String((pol.get("state") as Dictionary).get("guard", "none"))
	var gd := {}
	if pol.has_method("gov_def"):
		gd = pol.gov_def()
	var per := 5.0 if tier == "professional" else 2.0
	per = maxf(1.0, roundf(per * float(gd.get("guardUp", 1.0))))
	return {"count": guards.size(), "cost": int(guards.size() * per),
		"tier": tier}


func _dlg_food_per_head() -> float:
	var st := _dlg_stocks()
	var pop := _dlg_pop()
	return float(st.get("food", 0.0)) / maxf(1.0, float(pop))


static func _dlg_fname(faction: String) -> String:
	var d: Dictionary = Config.FACTIONS.get(faction, {})
	var n := String(d.get("name", ""))
	return n if n != "" else faction.capitalize()


## Strongest hostile faction (at war, else worst relations): {faction, ours,
## theirs, at_war, rel}. Empty when no other factions exist.
func _dlg_top_foe() -> Dictionary:
	var dip = _gs.get("diplomacy")
	if dip == null:
		return {}
	var ours = dip.military_strength(_pf())
	var best := ""
	var best_s := -1.0
	var best_war := false
	var best_rel := 0.0
	for f: String in _gs.active_factions:
		if f == _pf():
			continue
		var st := String(dip.relation_state(_pf(), f))
		var rel := float(dip.relation_score(_pf(), f))
		var s = dip.military_strength(f)
		var war := st == "war"
		if not war and rel > -20.0:
			continue
		if war and not best_war:
			best = f
			best_s = s
			best_war = true
			best_rel = rel
		elif war == best_war and s > best_s:
			best = f
			best_s = s
			best_rel = rel
	if best == "":
		return {}
	return {"faction": best, "ours": ours, "theirs": best_s,
		"at_war": best_war, "rel": best_rel}


## --- trade-deal commands (Treasury executes; others redirect) ----------------
## Jeremy 2026-10-11: the Treasury advisor tracks every deal and can run
## them. "trade with the elves: offer 100 wood for 50 gold" (+ "daily for
## 5 days"), "how are my deals", "cancel the elf deal" / "cancel deal #3",
## "accept/decline the counter", "what should I trade", "handle my trades"
## / "stop auto trade". Routed via _match_order -> "deals" so foreign
## cabinets refuse them like any order (sovereignty).

func _order_deals(unit: Dictionary, t: String) -> String:
	var role := String(unit.get("job", ""))
	if role != "advisor_economy":
		return _fill(unit, _deal_redirect_line(role))
	var td = _gs.get("trade_deals")
	if td == null:
		return "The ledger books aren't on my desk yet, boss — no trade office wired up. Give it a minute."
	# Stop BEFORE start: "stop auto trade" contains "auto trade".
	if _has_any(t, ["stop trading", "stop auto trade", "stop managing",
			"no more auto"]):
		td.auto_manage = false
		return "Standing down, boss. The markets are yours again — no more auto-deals. The signed ones keep running till they finish."
	if _has_any(t, ["handle my trades", "auto trade", "manage my deals",
			"manage my trades"]):
		if bool(td.auto_manage):
			return "Already on it, boss — I'm working the markets daily. Say 'stop auto trade' any time and I'll stand down."
		td.auto_manage = true
		return "Say less, boss. I'll work the markets — one sensible deal a day, never with our enemies, never below the reserve floors. Say 'stop auto trade' any time and I'll stand down."
	if _has_any(t, ["cancel the", "cancel deal"]):
		return _deal_cancel(td, t)
	if _has_any(t, ["accept the counter", "take the counter"]):
		return _deal_answer_counter(td, true)
	if _has_any(t, ["decline the counter"]):
		return _deal_answer_counter(td, false)
	if _has_any(t, ["trade with the", "trade with "]):
		return _deal_propose(unit, td, t)
	if _has_any(t, ["what should i trade", "trade advice"]):
		return "Trade desk, boss: " + String(td.trade_advice(_pf()))
	if _has_any(t, ["show me the ledger"]):
		return "The books, boss:\n" + String(td.ledger_text(_pf()))
	if _has_any(t, ["how are my deals", "deal status", "deals report",
			"trade report"]):
		return String(td.treasury_report(_pf()))
	return "Trade desk, boss. Say 'how are my deals' for the report, 'show me the ledger' for every line, 'trade with the elves: offer 100 wood for 50 gold' to deal, or 'handle my trades' and I'll work the markets myself."


func _deal_redirect_line(role: String) -> String:
	match role:
		"advisor_war":
			return "Deals? That's the coin-counter's desk, {ruler}. I count blades, not beans — ask the Treasury advisor."
		"advisor_civic":
			return "Oh, trade ledgers aren't my corner, {ruler} — the Treasury advisor keeps those books. I keep the people's supper warm instead."
		"guild_master":
			return "Not my payroll, {ruler}. The Treasury advisor runs the deal books — I run the people."
		"clerk":
			return "Trade ledgers?! Oh dear — that's the Treasury advisor's filing cabinet, {ruler}. I only do draft paperwork. Please don't make me do two jobs."
	return "That's the Treasury advisor's desk, {ruler}."


## "cancel deal #3" / "cancel the elf deal" / "cancel the elves".
func _deal_cancel(td, t: String) -> String:
	var m := RegEx.new()
	m.compile("#\\s*(\\d+)")
	var r := m.search(t)
	if r != null:
		var res: Dictionary = td.cancel_deal(int(r.get_string(1)), _pf())
		return ("Done, boss. " if bool(res.get("ok", false)) else "") \
			+ String(res.get("msg", ""))
	var foe := _faction_in(t)
	if foe != "":
		var fid := _faction_id(foe)
		var deals: Array = td.active_deals_for(_pf())
		var latest := {}
		for d: Dictionary in deals:
			var other := String(d["target"] if d["proposer"] == _pf() \
				else d["proposer"])
			if other == fid and int(d.get("id", 0)) \
					> int(latest.get("id", 0)):
				latest = d
		if latest.is_empty():
			return "No active deal with the %s on the books, boss." \
				% _dlg_fname(fid)
		var res2: Dictionary = td.cancel_deal(int(latest.get("id", 0)), _pf())
		return ("Done, boss. " if bool(res2.get("ok", false)) else "") \
			+ String(res2.get("msg", ""))
	return "Which deal, boss? 'cancel deal #3' with the number, or 'cancel the elf deal' with the faction."


## "accept the counter" / "decline the counter" — latest countered deal.
func _deal_answer_counter(td, accept: bool) -> String:
	var latest := {}
	for d: Dictionary in td.ledger(_pf()):
		if String(d.get("status", "")) == "countered" \
				and int(d.get("id", 0)) > int(latest.get("id", 0)):
			latest = d
	if latest.is_empty():
		return "No counter on the table, boss. Nobody's haggling with us right now."
	var res: Dictionary = td.accept_counter(int(latest.get("id", 0))) \
		if accept else td.decline_counter(int(latest.get("id", 0)))
	var pre := "Sharp call, boss. " if accept \
		else "Walked away clean, boss. "
	return (pre if bool(res.get("ok", false)) else "") \
		+ String(res.get("msg", ""))


## "trade with the elves: offer 100 wood for 50 gold" (+ "daily for 5 days").
func _deal_propose(unit: Dictionary, td, t: String) -> String:
	var foe := _faction_in(t)
	if foe == "":
		return "Who with, boss? 'trade with the elves: offer 100 wood for 50 gold'."
	var fid := _faction_id(foe)
	if fid == _pf():
		return "Trading with ourselves, boss? The ledger would just get dizzy."
	var parsed := _parse_trade_bundle(t)
	var offer: Dictionary = parsed.get("offer", {})
	var request: Dictionary = parsed.get("request", {})
	if offer.is_empty() or request.is_empty():
		return "I need both sides, boss: 'trade with the elves: offer 100 wood for 50 gold'."
	var mode := "once"
	var days := 1
	if t.contains("daily") or t.contains("per day"):
		mode = "daily"
		var dm := RegEx.new()
		dm.compile("for\\s+(\\d+)\\s+days?")
		var dr := dm.search(t)
		if dr != null:
			days = maxi(1, int(dr.get_string(1)))
	var res: Dictionary = td.propose(_pf(), fid, offer, request, mode,
		days, true)
	var verdict := String(res.get("verdict", ""))
	var msg := String(res.get("msg", ""))
	match verdict:
		"accept":
			return "Deal signed, boss. " + msg
		"counter":
			return "They're haggling, boss. " + msg \
				+ " Say 'accept the counter' or 'decline the counter'."
		"invalid":
			return "Can't write that one, boss: " + msg
	return "They refused, boss. " + msg


## Extract offer/request bundles from trade text. Amounts are NOT clamped
## (unlike _count_in's 20-cap — trade deals move real stockpiles).
static func _parse_trade_bundle(t: String) -> Dictionary:
	var out := {"offer": {}, "request": {}}
	var m := RegEx.new()
	m.compile("offer\\s+(\\d+)\\s+([a-z_ ]+?)\\s+for\\s+(\\d+)\\s+([a-z_ ]+)")
	var r := m.search(t)
	if r == null:
		return out
	var ores := _res_noun_in(r.get_string(2))
	var qres := _res_noun_in(r.get_string(4))
	if ores == "" or qres == "":
		return out
	out["offer"] = {ores: float(maxi(1, int(r.get_string(1))))}
	out["request"] = {qres: float(maxi(1, int(r.get_string(3))))}
	return out


## Longest resource-noun match inside a segment ("soul essence" beats "oil").
static func _res_noun_in(seg: String) -> String:
	var keys: Array = TRADE_RES_NOUNS.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var s := " " + seg.strip_edges() + " "
	for k: String in keys:
		if s.contains(" " + k + " ") or s.contains(" " + k):
			return String(TRADE_RES_NOUNS[k])
	return ""


## --- topic bodies -----------------------------------------------------------
## Each returns {text, followups: [{key, label, keywords}]}. Every number
## is read from live state at speak time — nothing cached.

func _topic_body(unit: Dictionary, role: String, key: String) -> Dictionary:
	match role:
		"advisor_economy":
			return _tr_topic(unit, key)
		"advisor_war":
			return _war_topic(unit, key)
		"advisor_civic":
			return _civ_topic(unit, key)
		"guild_master":
			return _gm_topic(unit, key)
		"clerk":
			return _clk_topic(unit, key)
	return {"text": "Hm.", "followups": []}


func _followup_body(unit: Dictionary, role: String, topic: String,
		fkey: String) -> Dictionary:
	match role:
		"advisor_economy":
			return _tr_followup(unit, topic, fkey)
		"advisor_war":
			return _war_followup(unit, topic, fkey)
		"advisor_civic":
			return _civ_followup(unit, topic, fkey)
		"guild_master":
			return _gm_followup(unit, topic, fkey)
		"clerk":
			return _clk_followup(unit, topic, fkey)
	return {"text": "Hm.", "followups": []}


## === TREASURY (advisor_economy): numbers-obsessed, calls Jeremy "boss" ===

func _tr_topic(unit: Dictionary, key: String) -> Dictionary:
	match key:
		"treasury":
			return _tr_treasury()
		"deals":
			return _tr_deals()
		"advice":
			return _tr_advice()
		"warnings":
			return _tr_warnings()
	return {"text": "Lost the ledger page, boss.", "followups": []}


func _tr_treasury() -> Dictionary:
	var st := _dlg_stocks()
	var tax := _dlg_tax_rate()
	var inc := _dlg_tax_income()
	var mood := "We're counting coppers, boss."
	if float(st.get("gold", 0.0)) > 2000.0:
		mood = "We're fat and happy, boss."
	elif float(st.get("gold", 0.0)) > 500.0:
		mood = "Comfortable. Don't get comfortable."
	var text := "The coffers, boss: %dg gold, %d wood, %d food, %d oil, %d seeds, %d soul essence. Taxes at %d%%, bringing in about %dg a day. %s" % [
		int(st.get("gold", 0.0)), int(st.get("wood", 0.0)),
		int(st.get("food", 0.0)), int(st.get("oil", 0.0)),
		int(st.get("seeds", 0.0)), int(st.get("soul_essence", 0.0)),
		tax, inc, mood]
	return {"text": text, "followups": [
		{"key": "income", "label": "Where does the gold go?",
			"keywords": ["income", "go", "spend", "losing", "lose"]},
		{"key": "taxes", "label": "Tax advice",
			"keywords": ["tax", "taxes"]},
	]}


func _tr_deals() -> Dictionary:
	var td = _gs.get("trade_deals")
	if td == null:
		return {"text": "No trade office wired up yet, boss.", "followups": []}
	var text: String = td.treasury_report(_pf())
	var act: Array = td.active_deals_for(_pf())
	if not act.is_empty():
		var bits: Array[String] = []
		for d: Dictionary in act:
			bits.append("#%d %s" % [int(d.get("id", 0)),
				td.deal_summary(d)])
		text += " Running now: " + "; ".join(bits) + "."
	return {"text": text, "followups": [
		{"key": "ledger", "label": "Show me the ledger",
			"keywords": ["ledger", "books", "show"]},
		{"key": "advice", "label": "What should I trade?",
			"keywords": ["advice", "should", "trade what"]},
		{"key": "auto", "label": "Handle my trades",
			"keywords": ["auto", "handle", "manage"]},
	]}


func _tr_advice() -> Dictionary:
	var st := _dlg_stocks()
	var camps := _dlg_building_count("lumber_camp")
	var pumps := _dlg_building_count("oil_pump")
	var farms := _dlg_building_count("farm")
	var per := _dlg_food_per_head()
	var rec := "Economy's humming, boss. Bank the surplus and let it compound."
	if per < 6.0:
		rec = "Food's thin — farms first, boss. Every hungry worker is a slow worker. Say 'build 2 farms'."
	elif float(st.get("oil", 0.0)) < 150.0 and pumps < 2:
		rec = "Oil's the bottleneck — pumpjacks print money. Say 'build 2 oil pumps'."
	elif float(st.get("wood", 0.0)) < 300.0 and camps < 2:
		rec = "Wood's low — lumber camps near the groves. Say 'build 2 lumber camps'."
	var text := "The economy, boss: %d lumber camps cutting, %d pumpjacks pumping, %d farms growing. Food's at %.1f a head. %s" % [
		camps, pumps, farms, per, rec]
	return {"text": text, "followups": [
		{"key": "lumber", "label": "Tell me about lumber",
			"keywords": ["lumber", "wood"]},
		{"key": "oil", "label": "Tell me about oil",
			"keywords": ["oil", "pump"]},
	]}


func _tr_warnings() -> Dictionary:
	var warns: Array[String] = []
	var inc := _dlg_tax_income()
	var gu := _dlg_guard_upkeep()
	if inc < int(gu.get("cost", 0)) and int(gu.get("count", 0)) > 0:
		warns.append("We're bleeding gold, boss: %dg/day in from taxes, ~%dg/day out on %d guards." \
			% [inc, int(gu.get("cost", 0)), int(gu.get("count", 0))])
	var per := _dlg_food_per_head()
	if per < 3.0:
		warns.append("FAMINE RISK — %.1f food a head. Bellies will be empty within days." % per)
	elif per < 6.0:
		warns.append("Food's thin at %.1f a head — one bad harvest from hunger." % per)
	var st := _dlg_stocks()
	var wars := 0
	var dip = _gs.get("diplomacy")
	if dip != null:
		for f: String in _gs.active_factions:
			if f != _pf() and dip.relation_state(_pf(), f) == "war":
				wars += 1
	if wars > 0 and float(st.get("gold", 0.0)) < 500.0:
		warns.append("War chest is thin (%dg) with %s running. Wars eat coin." \
			% [int(st.get("gold", 0.0)), _plural("war", wars)])
	if warns.is_empty():
		return {"text": "Books are clean, boss. No bleeds, no famines, no nasty surprises. Sleep easy.",
			"followups": []}
	return {"text": "Red ink, boss: " + " ".join(warns), "followups": [
		{"key": "fix", "label": "How do I fix it?",
			"keywords": ["fix", "solve", "what do"]},
	]}


func _tr_followup(unit: Dictionary, topic: String, fkey: String) -> Dictionary:
	match topic + "/" + fkey:
		"treasury/income":
			return _tr_fup_income()
		"treasury/taxes":
			return _tr_fup_taxes()
		"deals/ledger":
			return _tr_fup_ledger()
		"deals/advice":
			return _tr_fup_trade_advice()
		"deals/auto":
			return _tr_fup_auto()
		"advice/lumber":
			return _tr_fup_lumber()
		"advice/oil":
			return _tr_fup_oil()
		"warnings/fix":
			return _tr_fup_fix()
	return {"text": "Lost the ledger page, boss.", "followups": []}


func _tr_fup_income() -> Dictionary:
	var inc := _dlg_tax_income()
	var gu := _dlg_guard_upkeep()
	var td = _gs.get("trade_deals")
	var deal_line := "no deal office on record"
	if td != null:
		deal_line = td.treasury_report(_pf())
	var text := "Gold in: about %dg a day from taxes. Gold out: ~%dg a day on %d guards (%s watch). Trade lifetime: %s So if the pile's shrinking, it's the payroll or the deals — the numbers don't lie, boss." % [
		inc, int(gu.get("cost", 0)), int(gu.get("count", 0)),
		String(gu.get("tier", "none")), deal_line]
	return {"text": text, "followups": [
		{"key": "taxes", "label": "Tax advice", "keywords": ["tax", "taxes"]},
	]}


func _tr_fup_taxes() -> Dictionary:
	var tax := _dlg_tax_rate()
	var pol = _policies()
	var appr := -1.0
	if pol != null and pol.has_method("avg_approval"):
		appr = float(pol.avg_approval())
	var line := "Taxes at %d%%, boss." % tax
	if tax >= 25:
		line += " That's crown-heavy — the people grumble and collectors come home light."
	elif tax <= 5:
		line += " Practically a gift. The people love you; the coffers don't."
	else:
		line += " The middle road."
	if appr >= 0.0:
		line += " Approval's at %d%%." % int(appr)
	line += " Say 'raise taxes' or 'set taxes to 15' and I'll sign the decree."
	return {"text": line, "followups": []}


func _tr_fup_ledger() -> Dictionary:
	var td = _gs.get("trade_deals")
	var text := "No trade office wired up yet, boss."
	if td != null:
		text = "Every line, boss:\n" + String(td.ledger_text(_pf()))
	return {"text": text, "followups": []}


func _tr_fup_trade_advice() -> Dictionary:
	var td = _gs.get("trade_deals")
	var text := "No trade office wired up yet, boss."
	if td != null:
		text = String(td.trade_advice(_pf()))
	return {"text": text, "followups": [
		{"key": "auto", "label": "Handle my trades",
			"keywords": ["auto", "handle", "manage"]},
	]}


func _tr_fup_auto() -> Dictionary:
	var td = _gs.get("trade_deals")
	if td == null:
		return {"text": "No trade office wired up yet, boss.", "followups": []}
	if bool(td.auto_manage):
		return {"text": "Already on it, boss — I'm working the markets daily. Say 'stop auto trade' any time and I'll stand down.",
			"followups": []}
	td.auto_manage = true
	return {"text": "Say less, boss. I'll work the markets — one sensible deal a day, never with our enemies, never below the reserve floors. Say 'stop auto trade' any time and I'll stand down.",
		"followups": []}


func _tr_fup_lumber() -> Dictionary:
	var camps := _dlg_building_count("lumber_camp")
	var cutters := _dlg_job("woodcutter")
	var st := _dlg_stocks()
	var text := "%d lumber camps standing, %d woodcutters swinging, %d wood in the piles, boss." % [
		camps, cutters, int(st.get("wood", 0.0))]
	if camps == 0:
		text += " No camps at all — say 'build 2 lumber camps' and stop chopping by hand."
	elif cutters < camps * 2:
		text += " Camps are hungry for hands — say 'train 4 woodcutters'."
	else:
		text += " The saws are singing. Beautiful."
	return {"text": text, "followups": []}


func _tr_fup_oil() -> Dictionary:
	var pumps := _dlg_building_count("oil_pump")
	var st := _dlg_stocks()
	var text := "%d pumpjacks pumping, %d oil in the tanks, boss." % [
		pumps, int(st.get("oil", 0.0))]
	if pumps == 0:
		text += " No pumps — oil only comes from pumpjacks in industrial zones. Say 'build 2 oil pumps'."
	elif float(st.get("oil", 0.0)) < 150.0:
		text += " Tanks are low for %d pumps — the fields may be thin, or the caravans are thirsty." % pumps
	else:
		text += " Black gold flowing. The war machine drinks well."
	return {"text": text, "followups": []}


func _tr_fup_fix() -> Dictionary:
	var fixes: Array[String] = []
	var inc := _dlg_tax_income()
	var gu := _dlg_guard_upkeep()
	if inc < int(gu.get("cost", 0)):
		fixes.append("say 'raise taxes' to close the %dg/day gap" \
			% (int(gu.get("cost", 0)) - inc))
	if _dlg_food_per_head() < 6.0:
		fixes.append("say 'build 3 farms' and 'train 4 farmers'")
	var st := _dlg_stocks()
	if float(st.get("wood", 0.0)) < 300.0:
		fixes.append("say 'build 2 lumber camps'")
	if fixes.is_empty():
		return {"text": "Honestly, boss? Nothing's on fire. Keep doing what you're doing.",
			"followups": []}
	return {"text": "The fix, boss: " + "; ".join(fixes) + ". Give the orders and I'll move.",
		"followups": []}


## === WAR (advisor_war): blunt, martial ===

func _war_topic(unit: Dictionary, key: String) -> Dictionary:
	match key:
		"army":
			return _war_army()
		"threats":
			return _war_threats()
		"posts":
			return _war_posts()
		"forts":
			return _war_forts()
	return {"text": "Say again, {ruler}?", "followups": []}


func _war_army() -> Dictionary:
	var army = _gs.get("army")
	if army == null:
		return {"text": "No army to speak of, {ruler}. Raise one before the neighbors notice.", "followups": []}
	var info: Dictionary = army.army_info(_pf())
	var foe := _dlg_top_foe()
	var line := "Blades: %d standing (%d down), morale %d, stance %s." % [
		int(info.get("troops", 0)), int(info.get("downed", 0)),
		int(float(info.get("morale", 0.0))), String(info.get("stance", "auto"))]
	if not foe.is_empty():
		var ours := float(foe.get("ours", 0.0))
		var theirs := float(foe.get("theirs", 0.0))
		var verdict := "They outmuscle us — train, or tread careful."
		if ours > theirs * 1.5:
			verdict = "We'd roll them."
		elif ours > theirs:
			verdict = "We hold the edge."
		line += " The %s muster %.0f to our %.0f. %s" % [
			_dlg_fname(String(foe.get("faction", ""))), theirs, ours, verdict]
	else:
		line += " No foe worth naming right now."
	return {"text": line, "followups": [
		{"key": "foe", "label": "Who's the biggest threat?",
			"keywords": ["threat", "foe", "enemy", "who"]},
		{"key": "train", "label": "What should I train?",
			"keywords": ["train", "recruit", "advice"]},
	]}


func _war_threats() -> Dictionary:
	var dip = _gs.get("diplomacy")
	if dip == null:
		return {"text": "No diplomats to ask, {ruler}.", "followups": []}
	var bits: Array[String] = []
	for f: String in _gs.active_factions:
		if f == _pf():
			continue
		var st := String(dip.relation_state(_pf(), f))
		var rel := int(dip.relation_score(_pf(), f))
		if st == "war":
			bits.append("the %s — AT WAR (relations %d)" \
				% [_dlg_fname(f), rel])
		elif rel < -20:
			bits.append("the %s — hostile (%d)" % [_dlg_fname(f), rel])
	if bits.is_empty():
		return {"text": "No blades pointed at us, {ruler}. Borders quiet — suspiciously quiet.",
			"followups": []}
	return {"text": "Threats, {ruler}: " + "; ".join(bits) + ".", "followups": [
		{"key": "war", "label": "How goes the war?",
			"keywords": ["war", "battle", "fight"]},
		{"key": "borders", "label": "Border status",
			"keywords": ["border", "status"]},
	]}


func _war_posts() -> Dictionary:
	var cp = _gs.get("command_posts")
	if cp == null or not cp.has_method("holding_counts"):
		return {"text": "No command posts charted, {ruler}.", "followups": []}
	var c: Dictionary = cp.holding_counts(_pf())
	var n := int(c.get("town", 0)) + int(c.get("monastery", 0)) \
		+ int(c.get("crystal", 0))
	if n == 0:
		return {"text": "We hold no command posts, {ruler}. Towns, monasteries, dark crystals — take them and the land flips to us.",
			"followups": [
				{"key": "take", "label": "How do we take more?",
					"keywords": ["take", "capture", "how"]},
			]}
	return {"text": "We hold %d posts, {ruler}: %d towns, %d monasteries, %d dark crystals." % [
		n, int(c.get("town", 0)), int(c.get("monastery", 0)),
		int(c.get("crystal", 0))], "followups": [
		{"key": "take", "label": "How do we take more?",
			"keywords": ["take", "capture", "how"]},
	]}


func _war_forts() -> Dictionary:
	var sfb = _gs.get("starfort_bases")
	if sfb == null or not sfb.has_method("forts_of"):
		return {"text": "No star-fort engineers on staff, {ruler}.", "followups": []}
	var forts: Array = sfb.forts_of(_pf())
	if forts.is_empty():
		return {"text": "No star forts raised, {ruler}. A fortified base — walls pushed wide with gaps for the troops to sally. Say 'build a star fort' and I'll break ground.",
			"followups": []}
	return {"text": "Star forts standing: %d, {ruler}. Walls wide, gaps open, troops ready to sally." % forts.size(),
		"followups": [
			{"key": "garrison", "label": "Garrison status",
				"keywords": ["garrison", "guard", "defend"]},
		]}


func _war_followup(unit: Dictionary, topic: String, fkey: String) -> Dictionary:
	match topic + "/" + fkey:
		"army/foe":
			return _war_fup_foe()
		"army/train":
			return _war_fup_train()
		"threats/war":
			return {"text": "__war_status__", "followups": []}
		"threats/borders":
			return _war_fup_borders()
		"posts/take":
			return _war_fup_take()
		"forts/garrison":
			return _war_fup_garrison()
	return {"text": "Say again, {ruler}?", "followups": []}


func _war_fup_foe() -> Dictionary:
	var foe := _dlg_top_foe()
	if foe.is_empty():
		return {"text": "Nobody worth a war, {ruler}. Enjoy the peace — it never lasts.",
			"followups": []}
	var dip = _gs.get("diplomacy")
	var fname := _dlg_fname(String(foe.get("faction", "")))
	var line := "The %s: strength %.0f against our %.0f, relations %d." % [
		fname, float(foe.get("theirs", 0.0)), float(foe.get("ours", 0.0)),
		int(foe.get("rel", 0))]
	if bool(foe.get("at_war", false)):
		line += " We are AT WAR — no deals, no mercy, only planning."
		var key := "%s|%s" % [_pf(), String(foe.get("faction", ""))]
		var rec: Dictionary = _wars.get(key, {})
		if not rec.is_empty():
			line += " %d of ours dead, %d of theirs." % [
				int(rec.get("ours_dead", 0)), int(rec.get("theirs_dead", 0))]
	else:
		line += " Not war yet. Keep the blades sharp anyway."
	return {"text": line, "followups": []}


func _war_fup_train() -> Dictionary:
	var soldiers := _dlg_job("soldier")
	var archers := _dlg_job("archer")
	var mages := _dlg_job("mage")
	var idle := 0
	var hiring = _gs.get("hiring")
	if hiring != null and hiring.has_method("unemployed_count"):
		idle = int(hiring.unemployed_count(_pf()))
	var text := "%d soldiers, %d archers, %d mages under arms, {ruler}." % [
		soldiers, archers, mages]
	if idle > 0:
		text += " %d idle hands in the towns — say 'train %d soldiers' and I'll put steel in them." % [idle, mini(idle, 5)]
	else:
		text += " No idle hands — breed or hire before you dream of legions."
	if soldiers < 5:
		text += " Frankly? We need bodies. Yesterday."
	return {"text": text, "followups": []}


func _war_fup_borders() -> Dictionary:
	var dip = _gs.get("diplomacy")
	if dip == null:
		return {"text": "No diplomats to ask, {ruler}.", "followups": []}
	var bits: Array[String] = []
	for f: String in _gs.active_factions:
		if f == _pf():
			continue
		bits.append("the %s: %s (%d)" % [_dlg_fname(f),
			String(dip.relation_state(_pf(), f)),
			int(dip.relation_score(_pf(), f))])
	return {"text": "Every border, {ruler}: " + "; ".join(bits) + ".",
		"followups": []}


func _war_fup_take() -> Dictionary:
	var foe := _dlg_top_foe()
	var text := "March on their towns, their monasteries, their dark crystals, {ruler} — capture flips the land and the post. "
	if not foe.is_empty():
		var fname := _dlg_fname(String(foe.get("faction", "")))
		var n := _foe_post_count(String(foe.get("faction", "")))
		text += "The %s hold %d such prizes. " % [fname, n]
		if float(foe.get("ours", 0.0)) < float(foe.get("theirs", 0.0)):
			text += "But they outmuscle us — build the army FIRST, then take."
		else:
			text += "We have the edge. Strike while it's ours."
	else:
		text += "No foe named — pick one and point me at them."
	return {"text": text, "followups": []}


func _war_fup_garrison() -> Dictionary:
	var n := 0
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) != _pf():
			continue
		if not bool(u.get("alive", false)):
			continue
		if u.has("monastery_guard") or u.has("post_guard"):
			n += 1
	var text := "%d troops holding guard posts, {ruler}." % n
	if n == 0:
		text += " Nobody posted — the forts stand empty. Say 'guard the monastery' or post patrols."
	else:
		text += " Posts manned. Good."
	return {"text": text, "followups": []}


## === CIVIC (advisor_civic): warm, caretaker ===

func _civ_topic(unit: Dictionary, key: String) -> Dictionary:
	match key:
		"people":
			return _civ_people()
		"needs":
			return _civ_needs()
		"festival":
			return _civ_festival()
		"crime":
			return _civ_crime()
	return {"text": "Oh! Ask me again, {ruler}?", "followups": []}


func _civ_people() -> Dictionary:
	var pop := _dlg_pop()
	var towns := _pf_towns()
	var houses := _dlg_building_count("house")
	var bits: Array[String] = []
	for t: Dictionary in towns:
		bits.append("%s %d/16" % [String(t.get("name", "town")),
			_dlg_town_pop(t)])
	var text := "%d souls under your care, {ruler}, across %d %s. " % [
		pop, towns.size(), _plural("town", towns.size())]
	if not bits.is_empty():
		text += "(" + ", ".join(bits) + ") "
	text += "%d houses standing." % houses
	if pop >= towns.size() * 16 and towns.size() > 0:
		text += " Oh dear — we're at the 16-per-town cap. They'll need new homes or countryside farms."
	return {"text": text, "followups": [
		{"key": "towns", "label": "Tell me about the towns",
			"keywords": ["town", "village", "city"]},
		{"key": "houses", "label": "We need houses",
			"keywords": ["house", "home", "housing", "build"]},
	]}


func _civ_needs() -> Dictionary:
	var crit := _civ_critical_urges()
	var mood_line := _civ_mood_line()
	var text := ""
	if crit.is_empty():
		text = "No one's in crisis, {ruler} — bellies full, bladders... managed. "
	else:
		var bits: Array[String] = []
		for k: String in crit:
			bits.append("%d souls critical with %s" % [int(crit[k]), k])
		text = "Oh dear — " + ", ".join(bits) + ", {ruler}. "
	text += mood_line
	return {"text": text, "followups": [
		{"key": "food", "label": "How's the food?",
			"keywords": ["food", "eat", "hungry", "famine"]},
		{"key": "mood", "label": "Mood of the people",
			"keywords": ["mood", "happy", "morale", "feel"]},
	]}


## Count of player-faction units whose worst urge is critical, by urge.
func _civ_critical_urges() -> Dictionary:
	var urges = _gs.get("urges")
	if urges == null or not urges.has_method("worst_critical"):
		return {}
	var out := {}
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) != _pf():
			continue
		if not bool(u.get("alive", false)):
			continue
		var w := String(urges.worst_critical(u))
		if w != "":
			out[w] = int(out.get(w, 0)) + 1
	return out


func _civ_mood_line() -> String:
	var mood = _gs.get("mood")
	if mood == null or not mood.has_method("dominant"):
		return "The mood of the people is unmeasured today."
	var tally := {}
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) != _pf():
			continue
		if not bool(u.get("alive", false)):
			continue
		var d := String(mood.dominant(u))
		if d != "":
			tally[d] = int(tally.get(d, 0)) + 1
	if tally.is_empty():
		return "The mood of the people is unmeasured today."
	var top := ""
	var top_n := -1
	for k: String in tally:
		if int(tally[k]) > top_n:
			top_n = int(tally[k])
			top = k
	return "The prevailing mood is %s — %d souls wearing it." % [top, top_n]


func _civ_festival() -> Dictionary:
	var pol = _policies()
	var cd := 0
	var lfd := 0
	var happy := -1.0
	if pol != null and pol.get("state") is Dictionary:
		var st: Dictionary = pol.get("state")
		cd = int(st.get("festival_cd", 0))
		lfd = int(st.get("last_festival_day", 0))
	if pol != null and pol.has_method("avg_approval"):
		happy = float(pol.avg_approval())
	var text := "Festivals, {ruler} — the people's favorite medicine. "
	if cd > 0:
		text += "The last bunting came down %d days ago; %d days of rest before the next." % [lfd, cd]
	elif lfd > 0:
		text += "No cooldown — say the word and we'll dance tonight."
	else:
		text += "We've never held one! The people do so love a feast."
	if happy >= 0.0:
		text += " Approval's at %d%%." % int(happy)
	return {"text": text, "followups": [
		{"key": "hold", "label": "Hold one now",
			"keywords": ["hold", "now", "tonight", "yes"]},
	]}


func _civ_crime() -> Dictionary:
	var crime = _gs.get("crime")
	var jailed := 0
	if crime != null and crime.has_method("is_jailed"):
		for u: Dictionary in _gs.units:
			if String(u.get("faction", "")) != _pf():
				continue
			if bool(crime.is_jailed(int(u.get("id", 0)))):
				jailed += 1
	var pol = _policies()
	var tier := "none"
	var crack := false
	if pol != null and pol.get("state") is Dictionary:
		tier = String((pol.get("state") as Dictionary).get("guard", "none"))
	if crime != null and crime.has_method("crackdown_active"):
		crack = bool(crime.crackdown_active())
	var text := "%d souls in the jails, {ruler}. " % jailed
	if crack:
		text += "A crackdown is on — the watch is sweeping the streets. "
	text += "The watch stands at '%s'." % tier
	if jailed == 0 and not crack:
		text += " An honest town. I could cry."
	return {"text": text, "followups": [
		{"key": "guards", "label": "Tell me about the guards",
			"keywords": ["guard", "watch"]},
	]}


func _civ_followup(unit: Dictionary, topic: String, fkey: String) -> Dictionary:
	match topic + "/" + fkey:
		"people/towns":
			return _civ_fup_towns()
		"people/houses":
			return _civ_fup_houses()
		"needs/food":
			return {"text": "__food_status__", "followups": []}
		"needs/mood":
			return _civ_fup_mood()
		"festival/hold":
			return _civ_fup_hold()
		"crime/guards":
			return _civ_fup_guards()
		# Cross-topic: the mood follow-up (topic "needs") can point at a festival.
		"needs/hold":
			return _civ_fup_hold()
	return {"text": "Oh! Ask me again, {ruler}?", "followups": []}


func _civ_fup_towns() -> Dictionary:
	var towns := _pf_towns()
	if towns.is_empty():
		return {"text": "No towns yet, {ruler} — just dreams and a flag.",
			"followups": []}
	var bits: Array[String] = []
	for t: Dictionary in towns:
		var p := _dlg_town_pop(t)
		var note := ""
		if p >= 16:
			note = " (FULL)"
		elif p >= 12:
			note = " (nearly full)"
		bits.append("%s: %d souls%s" % [String(t.get("name", "town")), p, note])
	return {"text": "Your towns, {ruler}: " + ". ".join(bits) + ". Sixteen souls per town is all the roofs allow.",
		"followups": [
			{"key": "houses", "label": "We need houses",
				"keywords": ["house", "home", "housing", "build"]},
		]}


func _civ_fup_houses() -> Dictionary:
	var houses := _dlg_building_count("house")
	var blueprints := 0
	for b: Dictionary in _gs.buildings:
		if String(b.get("faction", "")) != _pf():
			continue
		if String(b.get("type", "")) != "house":
			continue
		if not bool(b.get("complete", false)) and bool(b.get("alive", true)):
			blueprints += 1
	var text := "%d houses standing, {ruler}" % houses
	if blueprints > 0:
		text += ", %d more going up" % blueprints
	text += ". Say 'build 3 houses' and the crews will raise the roofs."
	return {"text": text, "followups": []}


func _civ_fup_mood() -> Dictionary:
	var mood = _gs.get("mood")
	if mood == null or not mood.has_method("dominant"):
		return {"text": "I can't read the room today, {ruler} — the mood-books are blank.",
			"followups": []}
	var tally := {}
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) != _pf():
			continue
		if not bool(u.get("alive", false)):
			continue
		var d := String(mood.dominant(u))
		if d != "":
			tally[d] = int(tally.get(d, 0)) + 1
	var keys: Array = tally.keys()
	if keys.is_empty():
		return {"text": "I can't read the room today, {ruler} — the mood-books are blank.",
			"followups": []}
	keys.sort_custom(func(a: String, b: String) -> bool: return int(tally[a]) > int(tally[b]))
	var bits: Array[String] = []
	for k: String in keys.slice(0, 3):
		bits.append("%s (%d)" % [k, int(tally[k])])
	var text := "The people's hearts, {ruler}: " + ", ".join(bits) + "."
	if String(keys[0]) in ["angry", "sad", "fearful", "miserable"]:
		text += " Oh dear. A festival would do wonders — say the word."
	return {"text": text, "followups": [
		{"key": "hold", "label": "Hold a festival",
			"keywords": ["festival", "hold", "feast", "party"]},
	]}


func _civ_fup_hold() -> Dictionary:
	var pol = _policies()
	var cd := 0
	if pol != null and pol.get("state") is Dictionary:
		cd = int((pol.get("state") as Dictionary).get("festival_cd", 0))
	if cd > 0:
		return {"text": "Oh, I'd love to, {ruler} — but the town needs %d more days to recover from the last one. Patience, dear." % cd,
			"followups": []}
	return {"text": "A festival! Oh, the pies, the dancing! Just say 'hold a festival' and I'll ring the bells myself.",
		"followups": []}


func _civ_fup_guards() -> Dictionary:
	var gu := _dlg_guard_upkeep()
	var text := "%d guards on the watch, {ruler} (%s tier), costing ~%dg a day. " % [
		int(gu.get("count", 0)), String(gu.get("tier", "none")),
		int(gu.get("cost", 0))]
	if int(gu.get("count", 0)) == 0:
		text += "No watch at all — the streets keep themselves, and poorly."
	else:
		text += "They keep the peace, mostly."
	return {"text": text, "followups": []}


## === GUILD MASTER (guild_master): pragmatic, staffing-obsessed ===

func _gm_topic(unit: Dictionary, key: String) -> Dictionary:
	match key:
		"staffing":
			return _gm_staffing()
		"queues":
			return _gm_queues()
		"shops":
			return _gm_shops()
		"roster":
			return _gm_roster()
	return {"text": "The guild hears you, {ruler}. Again?", "followups": []}


func _gm_staffing() -> Dictionary:
	var idle := 0
	var hiring = _gs.get("hiring")
	if hiring != null and hiring.has_method("unemployed_count"):
		idle = int(hiring.unemployed_count(_pf()))
	var prio := ""
	if hiring != null and hiring.has_method("get_recruit_priority"):
		prio = String(hiring.get_recruit_priority(_pf()))
	var text := "Staffing, {ruler}: %d idle hands on the guild rolls." % idle
	if idle == 0:
		text += " Nobody idle — we're at full stretch."
	elif idle > 10:
		text += " That's a LOT of thumbs to twiddle. Put them to work."
	if prio != "":
		text += " Current recruit priority: %s." % prio
	return {"text": text, "followups": [
		{"key": "hire", "label": "Put them to work",
			"keywords": ["hire", "work", "employ", "train"]},
		{"key": "priority", "label": "What's the priority?",
			"keywords": ["priority", "focus"]},
	]}


func _gm_queues() -> Dictionary:
	var bits: Array[String] = []
	var total := 0
	for b: Dictionary in _gs.buildings:
		if String(b.get("faction", "")) != _pf():
			continue
		if not bool(b.get("alive", false)):
			continue
		var q: Array = b.get("train_queue", [])
		if q.is_empty():
			continue
		var kinds := {}
		for e: Dictionary in q:
			var ut := String(e.get("unit_type", "?"))
			kinds[ut] = int(kinds.get(ut, 0)) + 1
		var kb: Array[String] = []
		for k: String in kinds:
			kb.append("%d %s" % [int(kinds[k]), k])
		bits.append("%s: %s" % [String(b.get("type", "building")),
			", ".join(kb)])
		total += q.size()
	if bits.is_empty():
		return {"text": "No training queues running, {ruler}. The trainers are napping. Say 'train 5 soldiers' and I'll wake them.",
			"followups": []}
	return {"text": "Training queues, {ruler} — %d in the pipeline: %s." % [
		total, "; ".join(bits)], "followups": [
		{"key": "speed", "label": "Why so slow?",
			"keywords": ["slow", "speed", "stuck", "stall"]},
	]}


func _gm_shops() -> Dictionary:
	var nshops := 0
	for btype: String in DIALOGUE_SHOP_TYPES:
		nshops += _dlg_building_count(btype)
	var nstaff := 0
	for j: String in DIALOGUE_SHOP_JOBS:
		nstaff += _dlg_job(j)
	var text := "%d shops and stores standing, %d shop-folk on the books (keepers, barkeeps, smiths and the like), {ruler}." % [
		nshops, nstaff]
	if nshops > 0 and nstaff < nshops:
		text += " Thin coverage — some counters are minding themselves."
	elif nshops == 0:
		text += " No shops at all. Say 'build a shop' and commerce begins."
	return {"text": text, "followups": [
		{"key": "unstaffed", "label": "Which shops are unstaffed?",
			"keywords": ["unstaffed", "empty", "which", "staffed"]},
	]}


func _gm_roster() -> Dictionary:
	var jobs := ["worker", "farmer", "woodcutter", "miner", "builder",
		"fisher", "soldier", "archer", "ranger", "mage", "guard", "doctor"]
	var bits: Array[String] = []
	var total := 0
	for j: String in jobs:
		var n := _dlg_job(j)
		total += n
		if n > 0:
			bits.append("%d %s" % [n, j])
	var text := "The workforce, {ruler}: %d working souls. " % total
	text += ", ".join(bits) + "." if not bits.is_empty() else "Nobody's on the rolls."
	return {"text": text, "followups": [
		{"key": "idle", "label": "Who's idle?",
			"keywords": ["idle", "unemployed", "lazy"]},
	]}


func _gm_followup(unit: Dictionary, topic: String, fkey: String) -> Dictionary:
	match topic + "/" + fkey:
		"staffing/hire":
			return _gm_fup_hire()
		"staffing/priority":
			return _gm_fup_priority()
		"queues/speed":
			return _gm_fup_speed()
		"shops/unstaffed":
			return _gm_fup_unstaffed()
		"roster/idle":
			return _gm_fup_idle()
	return {"text": "The guild hears you, {ruler}. Again?", "followups": []}


func _gm_fup_hire() -> Dictionary:
	var idle := 0
	var hiring = _gs.get("hiring")
	if hiring != null and hiring.has_method("unemployed_count"):
		idle = int(hiring.unemployed_count(_pf()))
	if idle == 0:
		return {"text": "No idle hands to place, {ruler}. Breed faster or conquer quicker.",
			"followups": []}
	return {"text": "%d idle, {ruler}. Name the trade: 'train %d farmers', 'train %d soldiers', 'train %d miners' — say it and the guild places them." % [
		idle, mini(idle, 4), mini(idle, 4), mini(idle, 4)], "followups": []}


func _gm_fup_priority() -> Dictionary:
	var hiring = _gs.get("hiring")
	var prio := ""
	if hiring != null and hiring.has_method("get_recruit_priority"):
		prio = String(hiring.get_recruit_priority(_pf()))
	if prio == "":
		return {"text": "No standing priority, {ruler}. The guild takes all comers.",
			"followups": []}
	return {"text": "Recruit priority stands at %s, {ruler}. Say 'train 5 %s' to feed it." % [prio, prio],
		"followups": []}


func _gm_fup_speed() -> Dictionary:
	return {"text": "Queues move on coin and beds, {ruler}: training costs gold up front, graduates need a free bed and a trainer awake. If a queue stalls, check the treasury and the barracks.",
		"followups": []}


func _gm_fup_unstaffed() -> Dictionary:
	var nshops := 0
	for btype: String in DIALOGUE_SHOP_TYPES:
		nshops += _dlg_building_count(btype)
	var nstaff := 0
	for j: String in DIALOGUE_SHOP_JOBS:
		nstaff += _dlg_job(j)
	return {"text": "Honest answer, {ruler}: the crown doesn't keep a per-shop roster — I count heads by trade, not by door. %d shop-folk for %d shops. If the shelves look empty, say 'train 3 shopkeepers' and I'll fill the counters." % [
		nstaff, nshops], "followups": []}


func _gm_fup_idle() -> Dictionary:
	var idle := 0
	var hiring = _gs.get("hiring")
	if hiring != null and hiring.has_method("unemployed_count"):
		idle = int(hiring.unemployed_count(_pf()))
	if idle == 0:
		return {"text": "Nobody idle, {ruler}. Every hand earns its bread.",
			"followups": []}
	return {"text": "%d idle souls, {ruler}. Name the trade: 'train %d farmers', 'train %d soldiers' — say it and the guild places them." % [
		idle, mini(idle, 4), mini(idle, 4)], "followups": []}


## === DRAFT CLERK (clerk): nervous, bureaucratic ===

func _clk_topic(unit: Dictionary, key: String) -> Dictionary:
	match key:
		"draft":
			return _clk_draft()
		"muster":
			return _clk_muster()
		"paperwork":
			return _clk_paperwork()
		"rules":
			return _clk_rules()
	return {"text": "Y-yes, {ruler}? The form for that is... let me check.",
		"followups": []}


## Able-bodied civilians not under arms: unemployed + civilian workers.
func _clk_draftable() -> Dictionary:
	var hiring = _gs.get("hiring")
	var idle := 0
	if hiring != null and hiring.has_method("unemployed_count"):
		idle = int(hiring.unemployed_count(_pf()))
	var civ := 0
	var by_job := {}
	for j: String in ["worker", "farmer", "woodcutter", "miner", "fisher",
			"builder"]:
		var n := _dlg_job(j)
		civ += n
		by_job[j] = n
	return {"idle": idle, "civ": civ, "total": idle + civ, "by_job": by_job}


func _clk_draft() -> Dictionary:
	var d := _clk_draftable()
	var text := "The draft rolls, {ruler}: %d souls fit to serve — %d idle, %d working civilians who could take up steel. " % [
		int(d.get("total", 0)), int(d.get("idle", 0)), int(d.get("civ", 0))]
	if int(d.get("total", 0)) == 0:
		text += "Oh dear. The barrel is empty. The barrel is being scraped."
	else:
		text += "All paperwork in order. Mostly."
	return {"text": text, "followups": [
		{"key": "who", "label": "Who exactly?",
			"keywords": ["who", "exactly", "names", "list"]},
	]}


func _clk_muster() -> Dictionary:
	var army = _gs.get("army")
	if army == null:
		return {"text": "No army on the books, {ruler}! The muster form is blank. Blank!", "followups": []}
	var info: Dictionary = army.army_info(_pf())
	var deployed := 0
	var patrol_n := 0
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) != _pf() \
				or not bool(u.get("alive", false)):
			continue
		if u.has("deployed_for_war"):
			deployed += 1
		var po: Dictionary = u.get("player_order", {})
		if String(po.get("type", "")) == "patrol":
			patrol_n += 1
	var text := "Muster status, {ruler}: %d blades under arms, stance %s, morale %d. %d deployed for war, %d on patrol. " % [
		int(info.get("troops", 0)), String(info.get("stance", "auto")),
		int(float(info.get("morale", 0.0))), deployed, patrol_n]
	var wars: Array = info.get("at_war", [])
	if wars.is_empty():
		text += "Nobody to fight. The forms appreciate the quiet."
	else:
		text += "Filed under: %s. " % ", ".join(wars)
	return {"text": text, "followups": [
		{"key": "standdown", "label": "Stand them down?",
			"keywords": ["stand down", "demobilize", "dismiss"]},
	]}


func _clk_paperwork() -> Dictionary:
	var n := _pending.size()
	var text := "The desk, {ruler}: %d open order%s, all filed in triplicate. The triplicates are filed too." % [
		n, "" if n == 1 else "s"]
	if n == 0:
		text += " A clean desk! ...It's making me nervous."
	return {"text": text, "followups": [
		{"key": "orders", "label": "What orders are open?",
			"keywords": ["order", "open", "list"]},
	]}


func _clk_rules() -> Dictionary:
	return {"text": "Draft law, {ruler}, per the book: able-bodied civilians may be called — workers, farmers, cutters, miners. Those already under arms are exempt (obviously), the cabinet and guild officers are exempt (someone has to sign the forms), and we only EVER muster our own — foreign crowns command their own. That's the sovereignty clause. It's underlined. Twice.",
		"followups": [
			{"key": "exempt", "label": "Who's exempt?",
				"keywords": ["exempt", "excused", "exception"]},
		]}


func _clk_followup(unit: Dictionary, topic: String, fkey: String) -> Dictionary:
	match topic + "/" + fkey:
		"draft/who":
			return _clk_fup_who()
		"muster/standdown":
			return _clk_fup_standdown()
		"paperwork/orders":
			return _clk_fup_orders()
		"rules/exempt":
			return _clk_fup_exempt()
	return {"text": "Y-yes, {ruler}? The form for that is... let me check.",
		"followups": []}


func _clk_fup_who() -> Dictionary:
	var d := _clk_draftable()
	var by_job: Dictionary = d.get("by_job", {})
	var bits: Array[String] = []
	for j: String in by_job:
		if int(by_job[j]) > 0:
			bits.append("%d %s" % [int(by_job[j]), j])
	var text := "The draftable, {ruler}: %d idle" % int(d.get("idle", 0))
	if not bits.is_empty():
		text += ", plus " + ", ".join(bits)
	text += ". All present and accounted for. Ish."
	return {"text": text, "followups": []}


func _clk_fup_standdown() -> Dictionary:
	return {"text": "Stand down? Oh — oh dear. I can't sign that myself, {ruler}, it needs YOUR voice: just say 'stand down' and I'll file it immediately. Triple-stamped.",
		"followups": []}


func _clk_fup_orders() -> Dictionary:
	if _pending.is_empty():
		return {"text": "No open orders, {ruler}. The desk is clean. Suspiciously clean.",
			"followups": []}
	var kinds := {}
	for o: Dictionary in _pending:
		var k := String(o.get("kind", "order"))
		kinds[k] = int(kinds.get(k, 0)) + 1
	var bits: Array[String] = []
	for k: String in kinds:
		bits.append("%d %s" % [int(kinds[k]), k])
	return {"text": "Open on my desk, {ruler}: " + ", ".join(bits) + ". All being watched. Closely. With a spyglass.",
		"followups": []}


func _clk_fup_exempt() -> Dictionary:
	var names: Array[String] = []
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) != _pf():
			continue
		if not bool(u.get("alive", false)):
			continue
		var job := String(u.get("job", ""))
		if job in CABINET_JOBS or bool(u.get("is_advisor", false)):
			names.append(String(u.get("name", ROLE_TITLES.get(job, "officer"))))
	var text := "Exempt: the cabinet and guild officers — someone has to sign the forms. "
	if not names.is_empty():
		text += "That's " + ", ".join(names) + ", {ruler}. "
	text += "Everyone else? Fair game for the draft."
	return {"text": text, "followups": []}


## === Ruler's Voice expansion: proactive advisors + phone control + ============
## === military command + inter-advisor bus + envoys (Jeremy 2026-10-11) ========
##
## 1. PROACTIVE ADVISORS — when things go wrong, the relevant advisor DMs the
##    ruler FIRST with a concrete proposal and inline Yes/No. Accept executes
##    the real system; Deny stands down (3-day cooldown; one re-offer if it
##    gets worse). Advisors NEVER act without the ruler's word — sovereignty.
## 2. PHONE CONTROL — every policy lever reachable by talking to advisors:
##    taxes, laws (gambling/alehouses/dueling), borders, curfew, guard tiers,
##    festivals. Advisors explain consequences, then use the REAL systems.
## 3. MILITARY COMMAND — attack orders execute for real when at war
##    (deploy_for_war); "defend" orders dig troops in. Declare war still goes
##    through the proposal confirm modal — never a surprise war.
## 4. INTER-ADVISOR BUS — prioritized, cooldown-guarded staff messaging.
##    Urgent news (war) jumps the queue; routine reports wait. Visible in the
##    advisors' phone threads so the cabinet feels alive.
## 5. ENVOYS — "tell X to Y": an advisor carries the ruler's words to another
##    advisor, a faction leader, or an NPC. The recipient reacts in their own
##    voice; the carrier reports back. Envoy traffic rides the bus as urgent.

const PROACTIVE_CD_DAYS := 3
const CRIME_TRIGGER := 3
const CRIME_REARM := 6
const TREASURY_TRIGGER := 100.0

const ABUS_URGENT := 3
const ABUS_NORMAL := 2
const ABUS_ROUTINE := 1
const ABUS_PER_DAY := 3
const ABUS_CD_DAYS := 2

## kind ("crime"/"treasury"/"threat") -> {state, day, advisor_id, action, ...}
var _proactive: Dictionary = {}
## kind -> day of last answered offer (cooldown)
var _proactive_cd: Dictionary = {}
## inter-advisor queue: [{from_id,to_id,text,prio,day,topic}]
var _abus: Array = []
## "from|to|topic" -> day (spam guard)
var _abus_cd: Dictionary = {}
## pending envoy deliveries: [{carrier_id,kind,rid/faction,message,reaction,day,state}]
var _envoys: Array = []


## --- proactive advisors -------------------------------------------------------

func _check_proactive() -> void:
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	_proactive_crime(phone)
	_proactive_treasury(phone)
	_proactive_threat(phone)


func _proactive_ready(kind: String) -> bool:
	return int(_gs.get("day_number")) - int(_proactive_cd.get(kind, -99)) \
		>= PROACTIVE_CD_DAYS


func _crime_today() -> int:
	var crime = _crime_sys()
	if crime == null:
		return 0
	var st = crime.get("state")
	if not st is Dictionary:
		return 0
	return int((st as Dictionary).get("crimesToday", 0))


## Crime lives on the royal court (court_sys.crime), not GameState.
func _crime_sys():
	var court = _gs.get("court_sys")
	if court == null:
		return null
	return court.get("crime")


func _proactive_crime(phone) -> void:
	var rec: Dictionary = _proactive.get("crime", {})
	if String(rec.get("state", "")) == "offered":
		return  # already on the table
	var today := _crime_today()
	var threshold := CRIME_TRIGGER
	if String(rec.get("state", "")) == "denied":
		if not bool(rec.get("rearmed", false)) and today >= CRIME_REARM \
				and _proactive_ready("crime"):
			pass  # re-offer once, it got worse
		else:
			return
	elif today < threshold or not _proactive_ready("crime"):
		return
	var pol = _policies()
	var guard_tier := "none"
	var curfew := false
	if pol != null and pol.get("state") is Dictionary:
		var pst: Dictionary = pol.get("state")
		guard_tier = String(pst.get("guard", "none"))
		curfew = bool(pst.get("curfew", false))
	var crime = _crime_sys()
	var crack = crime != null and crime.has_method("crackdown_active") \
		and bool(crime.crackdown_active())
	var action := ""
	var desc := ""
	if guard_tier != "professional":
		action = "guards"
		desc = "put the watch on professional footing"
	elif not curfew:
		action = "curfew"
		desc = "impose a night curfew"
	elif not crack:
		action = "crackdown"
		desc = "launch a full crackdown"
	else:
		return  # already doing everything
	var adv := _advisor_by_job("advisor_civic")
	if adv.is_empty():
		return
	var town := "the realm"
	for tid: Variant in _gs.towns:
		var tw: Dictionary = _gs.towns[tid]
		if String(tw.get("faction", "")) == _pf():
			town = String(tw.get("name", "the realm"))
			break
	_proactive["crime"] = {"state": "offered",
		"day": int(_gs.get("day_number")),
		"advisor_id": int(adv.get("id", 0)), "action": action,
		"rearmed": bool(rec.get("rearmed", false)) or String(rec.get("state", "")) == "denied"}
	phone.npc_message(int(adv.get("id", 0)), _fill(adv,
		"Crime's getting bad, {ruler} — %d crimes in %s today, and the watch stands at '%s'. Want me to handle it? Say the word and I'll %s. (Yes / no.)" \
		% [today, town, guard_tier, desc]))


func _proactive_treasury(phone) -> void:
	var rec: Dictionary = _proactive.get("treasury", {})
	if String(rec.get("state", "")) == "offered":
		return
	if String(rec.get("state", "")) == "denied" or not _proactive_ready("treasury"):
		return
	var gold := _treasury()
	if gold >= TREASURY_TRIGGER:
		return
	var pol = _policies()
	if pol == null or not pol.has_method("set_tax"):
		return
	var cur := int((pol.get("state") as Dictionary).get("tax", 10)) \
		if pol.get("state") is Dictionary else 10
	if cur >= 30:
		return  # already squeezing; no good counsel left
	var adv := _treasury_advisor()
	if adv.is_empty():
		return
	_proactive["treasury"] = {"state": "offered",
		"day": int(_gs.get("day_number")),
		"advisor_id": int(adv.get("id", 0)), "action": "raise_tax"}
	phone.npc_message(int(adv.get("id", 0)), _fill(adv,
		"The coffers are nearly bare, {ruler} — %dg to our name. Shall I raise the tax a notch, %d%% to %d%%? The people will grumble. They always grumble. (Yes / no.)" \
		% [int(gold), cur, cur + 5]))


func _proactive_threat(phone) -> void:
	var rec: Dictionary = _proactive.get("threat", {})
	if String(rec.get("state", "")) == "offered":
		return
	if String(rec.get("state", "")) == "denied" or not _proactive_ready("threat"):
		return
	var dip = _gs.get("diplomacy")
	if dip == null or not dip.has_method("relation_state"):
		return
	var foe := ""
	for f: String in _gs.active_factions:
		if f == _pf():
			continue
		if dip.relation_state(_pf(), f) == "hostile":
			foe = f
			break
	if foe == "":
		return
	var adv := _war_advisor()
	if adv.is_empty():
		return
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name", foe.capitalize()))
	_proactive["threat"] = {"state": "offered",
		"day": int(_gs.get("day_number")),
		"advisor_id": int(adv.get("id", 0)), "action": "ready_army",
		"foe": foe}
	phone.npc_message(int(adv.get("id", 0)), _fill(adv,
		"The %s are massing on the border, {ruler} — hostile, not yet marching. Want me to ready the army? Draft and muster, war footing, no surprises. (Yes / no.)" \
		% fname))


func _pending_proactive_for(advisor_id: int) -> Dictionary:
	for kind: String in _proactive:
		var rec: Dictionary = _proactive[kind]
		if int(rec.get("advisor_id", 0)) == advisor_id \
				and String(rec.get("state", "")) == "offered":
			var out := rec.duplicate()
			out["kind"] = kind
			return out
	return {}


func _answer_proactive(unit: Dictionary, pro: Dictionary,
		verdict: String) -> String:
	var kind := String(pro.get("kind", ""))
	if verdict == "accept":
		_proactive[kind]["state"] = "accepted"
		_proactive_cd[kind] = int(_gs.get("day_number"))
		return _execute_proactive(unit, kind, String(pro.get("action", "")))
	_proactive[kind]["state"] = "denied"
	_proactive_cd[kind] = int(_gs.get("day_number"))
	return _fill(unit, "As you command, {ruler}. I'll keep my eyes open — and my mouth shut. Mostly shut.")


func _execute_proactive(unit: Dictionary, kind: String,
		action: String) -> String:
	var pol = _policies()
	match kind:
		"crime":
			match action:
				"guards":
					if pol != null and pol.has_method("set_guard") \
							and bool(pol.set_guard("professional")):
						return _fill(unit, "Done, {ruler} — the watch goes professional. Spears polished, boots laced, bribes... reduced.")
					return _fill(unit, "I tried, {ruler} — the coffers won't cover a professional watch. We may have to get creative. Or poorer.")
				"curfew":
					if pol != null and pol.has_method("toggle_curfew") \
							and bool(pol.toggle_curfew()):
						return _fill(unit, "Curfew imposed, {ruler} — none on the streets after dark. The thieves will have to steal in daylight like honest folk.")
					return _fill(unit, "The clerks blocked the curfew order, {ruler}. Paperwork. Always paperwork.")
				"crackdown":
					var crime2 = _crime_sys()
					if crime2 != null and crime2.has_method("start_crackdown"):
						crime2.start_crackdown()
						return _fill(unit, "Crackdown launched, {ruler} — the watch is sweeping the streets as we speak.")
					return _fill(unit, "No watch to crack down with, {ruler}. Awkward.")
		"treasury":
			if pol != null and pol.has_method("set_tax"):
				var cur := int((pol.get("state") as Dictionary).get("tax", 10)) \
					if pol.get("state") is Dictionary else 10
				pol.set_tax(cur + 5)
				return _fill(unit, "Taxes up to %d%%, {ruler}. The people grumble. The coffers don't." % (cur + 5))
		"threat":
			var army = _gs.get("army")
			if army != null and army.has_method("draft"):
				var d: int = int(army.draft(_pf(), 10))
				var n: int = int(army.muster(_pf()))
				return _fill(unit, "War footing, {ruler} — %s mustered%s. Let them come." \
					% [_plural("troop", n).capitalize(), (" (%d fresh drafts)" % d) if d > 0 else ""])
	return _fill(unit, "Consider it handled, {ruler}.")


## --- inter-advisor bus ----------------------------------------------------------

## Staff messaging with priority and spam guards. Urgent news jumps the
## queue; routine items wait their turn; nothing shouts twice in 2 days.
func abus_send(from_id: int, to_id: int, text: String,
		prio: int = ABUS_NORMAL, topic: String = "") -> bool:
	if from_id == 0 or to_id == 0 or text.strip_edges() == "":
		return false
	var day := int(_gs.get("day_number"))
	var key := "%d|%d|%s" % [from_id, to_id, topic]
	if prio < ABUS_URGENT \
			and day - int(_abus_cd.get(key, -99)) < ABUS_CD_DAYS:
		return false
	_abus_cd[key] = day
	_abus.append({"from_id": from_id, "to_id": to_id, "text": text,
		"prio": prio, "day": day, "topic": topic})
	return true


func _abus_dispatch() -> void:
	if _abus.is_empty():
		return
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	_abus.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("prio", 1)) != int(b.get("prio", 1)):
			return int(a.get("prio", 1)) > int(b.get("prio", 1))
		return int(a.get("day", 0)) < int(b.get("day", 0)))
	var delivered := 0
	var left: Array = []
	for m: Dictionary in _abus:
		var urgent: bool = int(m.get("prio", 1)) >= ABUS_URGENT
		if not urgent and delivered >= ABUS_PER_DAY:
			left.append(m)
			continue
		var from_u: Dictionary = _gs.get_unit(int(m.get("from_id", 0)))
		var from_name := "A colleague"
		if not from_u.is_empty():
			from_name = String(from_u.get("name",
				role_title(from_u)))
		phone.npc_message(int(m.get("to_id", 0)),
			"<<From %s>> %s" % [from_name, String(m.get("text", ""))])
		if not urgent:
			delivered += 1
	_abus = left


## --- inter-advisor briefings ----------------------------------------------------
## Jeremy 2026-10-11 (envoy mechanic): advisors brief each other on their
## own domains through the priority bus — war news, treasury warnings,
## civic unrest, arms supply. Pure information (sovereignty): they inform
## and advise, never command; anything needing the ruler's word still asks
## the ruler. Every briefing is topic-keyed, so the 2-day bus cooldown
## throttles each stream; priority scales with severity, so a War Advisor's
## urgent news jumps routine Treasury traffic. The player reads the flow in
## each advisor's phone thread (<<From X>> lines) — staff chatter stays
## staff chatter, not Gazette headlines.

func _abus_briefings() -> void:
	_brief_war_to_treasury()
	_brief_treasury_to_war()
	_brief_civic_to_war()
	_brief_war_to_civic()
	_brief_guild_to_treasury()


## Briefing send: topic-keyed like abus_send, but a stream never repeats
## within the same day. Urgent streams still re-fire on later days (the
## crisis persists); normal/routine wait out the 2-day bus cooldown.
func _brief_send(from_id: int, to_id: int, text: String, prio: int,
		topic: String) -> bool:
	var day := int(_gs.get("day_number"))
	var key := "%d|%d|%s" % [from_id, to_id, topic]
	if int(_abus_cd.get(key, -99)) == day:
		return false  # already briefed today
	return abus_send(from_id, to_id, text, prio, topic)


## First active war's record. Empty when at peace (war briefings stay silent).
func _brief_war_rec() -> Dictionary:
	for foe: String in _gs.active_factions:
		if foe == _pf():
			continue
		if not _at_war_with(foe):
			continue
		var rec: Dictionary = _wars.get("%s|%s" % [_pf(), foe], {})
		if not rec.is_empty():
			return rec
	return {}


## Read-only treasury burn from the war record's gold history — no sampling
## (the daily counsel already samples; double-sampling would dilute it).
func _brief_burn(rec: Dictionary) -> Dictionary:
	var hist: Array = rec.get("gold_hist", [])
	var out := {"burn": 0.0, "runway": 999.0}
	if hist.size() < 3:
		return out
	var days := float(hist.size() - 1)
	var burn := (float(hist[0]) - float(hist[hist.size() - 1])) \
		/ maxf(1.0, days)
	out["burn"] = burn
	if burn >= 15.0:
		out["runway"] = float(hist[hist.size() - 1]) / burn
	return out


## War Advisor -> Treasury Advisor: the war's gold burn, with real numbers.
func _brief_war_to_treasury() -> void:
	var rec := _brief_war_rec()
	if rec.is_empty():
		return
	var drain := _brief_burn(rec)
	var burn := float(drain.get("burn", 0.0))
	if burn < 15.0:
		return
	var war := _war_advisor()
	var tre := _treasury_advisor()
	if war.is_empty() or tre.is_empty():
		return
	var foe := String(rec.get("foe", ""))
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	var runway := float(drain.get("runway", 999.0))
	var rw := "the coffers are bleeding"
	if runway < 999.0:
		rw = "the treasury empties in %d days" % int(runway)
	var prio := ABUS_NORMAL
	if runway < 5.0 or _treasury() < TREASURY_TRIGGER:
		prio = ABUS_URGENT
	_brief_send(int(war.get("id", 0)), int(tre.get("id", 0)),
		"War with the %s: the war burns %d gold a day — %s. Brace the coffers." \
		% [fname, int(burn), rw], prio, "brief_warburn")


## Treasury Advisor -> War Advisor: the purse can't fund grand offensives.
## Peacetime silence — nobody needs a treasury memo when nothing burns.
func _brief_treasury_to_war() -> void:
	if _brief_war_rec().is_empty():
		return
	var gold := _treasury()
	if gold >= 500.0:
		return
	var tre := _treasury_advisor()
	var war := _war_advisor()
	if tre.is_empty() or war.is_empty():
		return
	var prio := ABUS_NORMAL
	if gold < TREASURY_TRIGGER:
		prio = ABUS_URGENT
	_brief_send(int(tre.get("id", 0)), int(war.get("id", 0)),
		"The coffers hold %dg. Rein in the spending — no grand offensives on an empty purse, and the troops get paid FIRST." \
		% int(gold), prio, "brief_coffers")


## Civic Advisor -> War Advisor: unrest the army's marching is causing.
func _brief_civic_to_war() -> void:
	var today := _crime_today()
	if today < CRIME_TRIGGER:
		return
	var civ := _advisor_by_job("advisor_civic")
	var war := _war_advisor()
	if civ.is_empty() or war.is_empty():
		return
	var prio := ABUS_NORMAL
	if today >= CRIME_REARM:
		prio = ABUS_URGENT
	_brief_send(int(civ.get("id", 0)), int(war.get("id", 0)),
		"Unrest in the towns — %d crimes today. The army's marching has the people on edge; keep the troops clear of the markets." \
		% today, prio, "brief_unrest")


## War Advisor -> Civic Advisor: casualty news from the front, real numbers.
func _brief_war_to_civic() -> void:
	var rec := _brief_war_rec()
	if rec.is_empty():
		return
	var ours := int(rec.get("ours_dead", 0))
	var theirs := int(rec.get("theirs_dead", 0))
	if ours == 0 and theirs == 0:
		return
	var war := _war_advisor()
	var civ := _advisor_by_job("advisor_civic")
	if war.is_empty() or civ.is_empty():
		return
	var foe := String(rec.get("foe", ""))
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	var losing := ours > 0 and ours > theirs * 2
	var verdict := "We're holding."
	var prio := ABUS_NORMAL
	if losing:
		verdict = "We're bleeding, and the towns feel it."
		prio = ABUS_URGENT
	_brief_send(int(war.get("id", 0)), int(civ.get("id", 0)),
		"The war with the %s: we've lost %d, they've lost %d. %s" \
		% [fname, ours, theirs, verdict], prio, "brief_warnews")


## Guild Master -> Treasury Advisor: the forges' wartime appetite. Always
## routine — steel can wait its turn behind blood and gold.
func _brief_guild_to_treasury() -> void:
	if _brief_war_rec().is_empty():
		return
	var gld := _advisor_by_job("guild_master")
	var tre := _treasury_advisor()
	if gld.is_empty() or tre.is_empty():
		return
	_brief_send(int(gld.get("id", 0)), int(tre.get("id", 0)),
		"Weapons priority — the forges run day and night for the war. Keep the coin flowing; steel doesn't forge itself.",
		ABUS_ROUTINE, "brief_arms")


## --- war word spreading ---------------------------------------------------------

## When a war starts, the War Advisor notifies the cabinet through the
## priority bus (urgent) and summarizes for the ruler. The cabinet feels
## like a real staff: treasury braces, civic steadies, guild arms.
func _spread_war_word(foe: String, we_started: bool) -> void:
	var war := _war_advisor()
	var phone = _gs.get("phone_sys")
	if war.is_empty() or phone == null \
			or not phone.has_method("npc_message"):
		return
	var wid := int(war.get("id", 0))
	var fname: String = String(Config.FACTIONS.get(foe, {}).get("name",
		foe.capitalize()))
	var notes := {
		"advisor_economy": "War with the %s. Brace the coffers — war eats gold faster than soldiers eat stew." % fname,
		"advisor_civic": "War with the %s. Expect unrest, refugees, and very loud opinions." % fname,
		"guild_master": "War with the %s. Weapons priority — the crown will need steel, and lots of it." % fname,
	}
	for job: String in notes:
		var u := _advisor_by_job(job)
		if u.is_empty() or int(u.get("id", 0)) == wid:
			continue
		abus_send(wid, int(u.get("id", 0)), String(notes[job]),
			ABUS_URGENT, "war_declared")
	var how := "we drew first blood" if we_started else "they came for us"
	phone.npc_message(wid, _fill(war,
		"The word's gone out, {ruler} — war with the %s (%s). The cabinet knows: treasury braces, the civic desk steadies the towns, the guild sharpens steel." \
		% [fname, how]))


func _on_proposal_decided(p: Dictionary, approved: bool) -> void:
	if not approved:
		return
	if String(p.get("kind", "")) != "declare_war":
		return
	if String(p.get("faction", "")) != _pf():
		return
	var details: Dictionary = p.get("details", {})
	_spread_war_word(String(details.get("target", "")), true)


## --- envoys -----------------------------------------------------------------------

## "Tell the guild master to prioritize weapons." "Tell the orc leader we
## accept their tribute." An advisor carries the ruler's words: to your own
## officials via the urgent bus lane, to foreign leaders as real diplomacy,
## to named NPCs as a delivered message. The carrier reports back with the
## recipient's reaction, in the recipient's own voice.

func _order_envoy(unit: Dictionary, t: String) -> String:
	var body := t
	for prefix: String in ["go tell ", "tell "]:
		if body.begins_with(prefix):
			body = body.substr(prefix.length())
			break
	var recip := ""
	var msg := ""
	for sep: String in [" to ", " that "]:
		var i := body.find(sep)
		if i > 0:
			recip = body.substr(0, i).strip_edges()
			msg = body.substr(i + sep.length()).strip_edges()
			break
	if recip == "":
		# "tell the orc leader we accept" — faction-leader phrasing.
		var fid0 := _faction_in(body)
		var li := body.find("leader")
		if fid0 != "" and li > 0:
			recip = "leader:" + fid0
			msg = body.substr(li + 6).strip_edges()
	if recip == "" or msg == "":
		return _fill(unit, "{ruler}, tell WHOM, WHAT? 'Tell the guild master to prioritize weapons' — that shape.")
	var carrier_id := int(unit.get("id", 0))
	var phone = _gs.get("phone_sys")
	# 1) your own officials — urgent bus lane, they react in-voice.
	var target := _envoy_official_target(recip)
	if not target.is_empty():
		var tid := int(target.get("id", 0))
		abus_send(carrier_id, tid, msg, ABUS_URGENT, "envoy")
		_envoys.append({"carrier_id": carrier_id, "kind": "official",
			"rid": tid, "message": msg,
			"day": int(_gs.get("day_number")), "state": "sent"})
		return _fill(unit, "On it, {ruler} — I'll carry it to %s myself." \
			% String(target.get("name", role_title(target))))
	# 2) foreign leaders — real diplomacy, voiced reply via their engine.
	var fid := _faction_in(recip)
	if fid == "":
		fid = _faction_in(body)
	if fid != "" and fid != _pf() and fid != _pf_singular():
		fid = _faction_id(fid)
		var carrier_name := String(unit.get("name", role_title(unit)))
		var framed := "\"%s,\" says %s, speaking for the crown." % [msg, carrier_name]
		if phone != null and phone.has_method("send_leader_message"):
			phone.send_leader_message(fid, framed)
		var fl = _gs.get("faction_leaders")
		var reaction := "..."
		if fl != null and fl.has_method("reply_to"):
			reaction = String(fl.reply_to(fid, _pf(), msg))
		var fname: String = String(Config.FACTIONS.get(fid, {}).get("name",
			fid.capitalize()))
		_envoys.append({"carrier_id": carrier_id, "kind": "leader",
			"faction": fid, "message": msg, "reaction": reaction,
			"day": int(_gs.get("day_number")), "state": "sent"})
		return _fill(unit, "At once, {ruler} — my fastest rider carries your words to the %s." % fname)
	# 3) named NPCs — delivered to their thread; they answer in their own time.
	var npc := _envoy_npc_target(recip)
	if not npc.is_empty():
		var nid := int(npc.get("id", 0))
		if phone != null and phone.has_method("npc_message"):
			phone.npc_message(nid,
				"\"%s,\" says %s, speaking for the crown." \
				% [msg, String(unit.get("name", role_title(unit)))])
		_envoys.append({"carrier_id": carrier_id, "kind": "npc",
			"rid": nid, "message": msg,
			"day": int(_gs.get("day_number")), "state": "sent"})
		return _fill(unit, "Delivered to %s, {ruler} — they'll answer in their own words." \
			% String(npc.get("name", "them")))
	return _fill(unit, "{ruler}, I don't know a '%s'. Point me at someone real." % recip)


## Match "treasury advisor" / "war advisor" / "civic advisor" /
## "guild master" / "draft clerk" to the living office-holder.
func _envoy_official_target(recip: String) -> Dictionary:
	var jobs := {"treasury": "advisor_economy", "war": "advisor_war",
		"civic": "advisor_civic", "guild": "guild_master",
		"draft": "draft_clerk"}
	for k: String in jobs:
		if recip.contains(k):
			var u := _advisor_by_job(String(jobs[k]))
			if not u.is_empty():
				return u
	return {}


func _envoy_npc_target(recip: String) -> Dictionary:
	var words: Array = []
	for w: String in recip.split(" ", false):
		w = w.strip_edges()
		if w.length() > 2 and not ["the", "our", "and"].has(w):
			words.append(w)
	if words.is_empty():
		return {}
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != _pf():
			continue
		var nm := String(u.get("name", "")).to_lower()
		var hit := true
		for w: String in words:
			if not nm.contains(w):
				hit = false
				break
		if hit:
			return u
	return {}


func _envoy_ack_voice(ru: Dictionary) -> String:
	match String(ru.get("job", "")):
		"advisor_economy":
			return "Numbers. Lovely. I'll see to it."
		"advisor_war":
			return "Heard. Steel answers."
		"advisor_civic":
			return "For the people. I'll handle it."
		"guild_master":
			return "The guild hears the crown. It'll be done."
		"draft_clerk":
			return "Filed, stamped, and actioned."
	return "Understood. Consider it handled."


## Next day: recipients react, carriers report back to the ruler.
func _poll_envoys() -> void:
	if _envoys.is_empty():
		return
	var phone = _gs.get("phone_sys")
	if phone == null or not phone.has_method("npc_message"):
		return
	var done: Array = []
	for e: Dictionary in _envoys:
		if String(e.get("state", "")) != "sent":
			done.append(e)
			continue
		var carrier: Dictionary = _gs.get_unit(int(e.get("carrier_id", 0)))
		if carrier.is_empty():
			done.append(e)
			continue
		var kind := String(e.get("kind", ""))
		var report := ""
		if kind == "official":
			var ru: Dictionary = _gs.get_unit(int(e.get("rid", 0)))
			var rname := String(ru.get("name", "they")) \
				if not ru.is_empty() else "they"
			var rmsg := String(e.get("message", ""))
			var reacted := ""
			# If the carried words are an order the official can execute,
			# they execute it (through the real dispatch). Anything fuzzy
			# gets an in-voice acknowledgment instead.
			if not ru.is_empty() and is_cabinet(_gs, ru):
				var handler := _match_order(_norm(rmsg))
				var crisp := handler in ["war", "military", "build",
					"train", "civic", "peaceterms", "wardashboard", "peace",
					"tribute", "threat", "scout", "deals"] \
					or (handler == "economy" \
						and _norm(rmsg).contains("tax"))
				if crisp:
					reacted = _dispatch_order(ru, _norm(rmsg))
			if reacted == "":
				reacted = _envoy_ack_voice(ru)
			report = "%s says: \"%s\"" % [rname, reacted]
		elif kind == "leader":
			var fid := String(e.get("faction", ""))
			var fname: String = String(Config.FACTIONS.get(fid, {}).get(
				"name", fid.capitalize()))
			report = "The %s leader answers: \"%s\"" \
				% [fname, String(e.get("reaction", "..."))]
		else:
			report = "It's delivered, {ruler} — they'll answer in their own time."
		phone.npc_message(int(carrier.get("id", 0)),
			_fill(carrier, "Word back, {ruler}. " + report))
		done.append(e)
	for e: Dictionary in done:
		_envoys.erase(e)
