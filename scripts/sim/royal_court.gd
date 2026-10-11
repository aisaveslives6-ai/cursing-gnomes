class_name SimRoyalCourt
extends RefCounted
## Cursing Gnomes — Royal Court & Royal Gazette (Milestone 6).
##
## Design ported from the HTML build (not its code):
##   - Royal Court direction: every popup decision comes from a NAMED
##     character with a role and motive — mayors petition, lords play power
##     dynamics, commanders request troops/supplies, foreign envoys send
##     trade/tribute/alliance/threat messages.
##   - Two-way chat: portrait/name/title, intent parsing, personality +
##     mood memory — all client-side (SimPhone.npc_message/replies).
##   - The Royal Gazette ("The Cursing Chronicle") prints stories from
##     REAL sim events only — never canned. Government decisions reach the
##     player ONLY through the Gazette (no blocking modals; Jeremy's rule).
##   - Issue/volume lines come off the real game calendar; reporters,
##     sections, and captions are deterministic per story.
##
## PETITION SCHEMA: {id, day, from_key, from_name, role, faction,
##   kind, text, options: Array[String], resolved: bool, choice: int}
## STORY SCHEMA: {id, day, headline, body, kind, section, reporter}
##
## Pure logic — no rendering, no input, no audio, no network.


## Petition kinds (HTML court roles).
const KINDS: Array[String] = ["troops", "supplies", "trade", "tribute",
	"alliance", "threat", "festival", "taxes"]

## Gazette sections per story kind — HTML GAZETTE_SECTIONS via SimGazette.
## (Full newspaper restyle: sections, reporters, captions, cartoons.)
## See scripts/sim/gazette.gd for the HTML-ported data.

## Relations: faction -> -100 (war) .. +100 (allied), vs player faction.
## Starts at 0 (neutral); envoys move it.
## Milestone 8: when `diplomacy` is wired, diplomatic petition kinds
## (trade/tribute/alliance/threat) route through SimDiplomacy and this
## dict is synced from the pair score — it stays the legacy view tests
## and older code read.
var relations: Dictionary = {}

## Petitions awaiting a decision.
var petitions: Array[Dictionary] = []
## Published stories, newest last.
var stories: Array[Dictionary] = []
## How many stories the player has seen (HTML parity: st.unreadNews).
## The drawer Chronicle badge shows stories.size() - news_seen.
var news_seen: int = 0

## Policies & government (owned here so every court decision can move them).
var policies  # SimPolicies — created in _init

## Crime & punishment (owned here so court petitions can answer crimewaves).
var crime  # SimCrime — created in _init

## News desk: trivia aggregation + crown-works beat (HTML NEWS_TRIVIA_BUCKETS
## parity). Owned here so every story type funnels through the Gazette.
var news_desk  # SimNewsTrivia — created in _init

var _gs: GameState
var _petition_seq: int = 1
var _story_seq: int = 1

## Optional SimDiplomacy (set by the world). Duck-typed to avoid a cyclic
## class reference. When set, diplomatic petitions (trade/tribute/
## alliance/threat) resolve through the real diplomacy system.
var diplomacy = null


func _init(game_state: GameState) -> void:
	_gs = game_state
	for f: String in _gs.active_factions:
		if f != _gs.player_faction:
			relations[f] = 0
	policies = SimPolicies.new(game_state, self)
	crime = SimCrime.new(game_state, self)
	policies.crime_ref = crime
	news_desk = SimNewsTrivia.new(game_state)
	_gs.bus.day_changed.connect(_on_day)


## Late wiring: the phone system (created separately) for DMs/Squabble.
func attach_phone(p) -> void:
	if policies != null and policies.has_method("attach_phone"):
		policies.attach_phone(p)


## Access to the game state for Gazette rendering (HTML parity).
func game_state() -> GameState:
	return _gs


func _on_day(_day: int, _is_night: bool) -> void:
	_maybe_domestic_petition()
	# Curfew: -1 happiness per day while active (HTML curfew policy).
	# (Crime -40% lives in policies.crime_pressure_mult(), consumed by
	# SimCrime's daily tick.)
	if policies != null and bool(policies.state.get("curfew", false)):
		policies.add_happiness(-1.0)


## --- Petitions ----------------------------------------------------------------

## A named character petitions the crown. Options are the player's choices.
## Emits petition_opened; the decision reaches the player via the Gazette.
func petition(from_unit: Dictionary, kind: String, text: String,
		options: Array[String]) -> Dictionary:
	var mind: Dictionary = from_unit.get("mind", {})
	var p: Dictionary = {
		"id": _petition_seq,
		"day": _gs.day_number,
		"from_key": "u%d" % int(from_unit.get("id", 0)),
		"from_name": SimPersonality.display_name(from_unit),
		"role": String(mind.get("gov_role", "citizen")).replace("_", " ").capitalize(),
		"faction": String(from_unit.get("faction", "")),
		"kind": kind,
		"text": text,
		"options": options.duplicate(),
		"resolved": false,
		"choice": -1,
	}
	_petition_seq += 1
	petitions.append(p)
	_gs.bus.petition_opened.emit(p)
	return p


## Unresolved petitions, oldest first.
func open_petitions() -> Array:
	var out: Array = []
	for p: Dictionary in petitions:
		if not bool(p.get("resolved", false)):
			out.append(p)
	return out


## The player decides. Applies the effect, prints a Gazette story, marks
## the petition resolved. Returns the published story.
func decide(petition_id: int, option_index: int) -> Dictionary:
	var p: Dictionary = _find_petition(petition_id)
	if p.is_empty() or bool(p.get("resolved", false)):
		return {}
	var options: Array = p["options"]
	if option_index < 0 or option_index >= options.size():
		return {}
	p["resolved"] = true
	p["choice"] = option_index
	var choice: String = String(options[option_index])
	var effect_story: Dictionary = _apply_effect(p, choice)
	# A returned story means the grant proved undeliverable — report the
	# shortfall honestly instead of the generic ruling headline.
	var story: Dictionary = effect_story
	if story.is_empty():
		story = publish_story(
			_CourtHeadline(p, choice),
			_CourtBody(p, choice),
			"court")
	_gs.bus.petition_decided.emit(p, choice)
	return story


func _apply_effect(p: Dictionary, choice: String) -> Dictionary:
	var pf: String = _gs.player_faction
	var kind: String = String(p.get("kind", ""))
	# Domestic courtier petitions (mayor/lord/commander templates) resolve
	# through their template id, not choice-text matching. A returned story
	# means the grant proved undeliverable — decide() reports it directly.
	if String(p.get("tpl", "")) != "":
		return _apply_domestic(p, int(p.get("choice", -1)))
	var c: String = choice.to_lower()
	var df: String = String(p.get("faction", ""))
	if diplomacy != null and df != "" and df != pf and pf != "" \
			and _apply_diplomatic(p, kind, c, pf, df):
		return {}  # resolved through SimDiplomacy (relations synced there)
	match kind:
		"troops":
			if "grant" in c or "yes" in c or "send" in c:
				_gs.resources.add_resource(pf, "gold", -50.0)
		"supplies":
			if "grant" in c or "yes" in c or "send" in c:
				_gs.resources.add_resource(pf, "food", -30.0)
		"trade":
			if "accept" in c or "yes" in c:
				relations[p["faction"]] = clampi(int(relations.get(p["faction"], 0)) + 15, -100, 100)
				_gs.resources.add_resource(pf, "gold", 40.0)
			elif "refuse" in c or "no" in c:
				relations[p["faction"]] = clampi(int(relations.get(p["faction"], 0)) - 10, -100, 100)
		"tribute":
			if "accept" in c:
				_gs.resources.add_resource(pf, "gold", 60.0)
				relations[p["faction"]] = clampi(int(relations.get(p["faction"], 0)) + 10, -100, 100)
			else:
				relations[p["faction"]] = clampi(int(relations.get(p["faction"], 0)) - 15, -100, 100)
		"alliance":
			if "accept" in c or "yes" in c:
				relations[p["faction"]] = 60
			else:
				relations[p["faction"]] = clampi(int(relations.get(p["faction"], 0)) - 20, -100, 100)
		"threat":
			if "defy" in c or "refuse" in c or "no" in c:
				relations[p["faction"]] = -60
			else:
				_gs.resources.add_resource(pf, "gold", -40.0)
				relations[p["faction"]] = clampi(int(relations.get(p["faction"], 0)) + 5, -100, 100)
		"festival":
			if "hold" in c or "yes" in c:
				_gs.resources.add_resource(pf, "gold", -25.0)
				_gs.resources.add_resource(pf, "food", -20.0)
		"taxes":
			if "raise" in c:
				_gs.resources.add_resource(pf, "gold", 50.0)
	return {}


## Milestone 8: resolves a diplomatic petition through SimDiplomacy.
## Returns true when the kind was handled (and syncs the legacy relations
## dict from the pair score so old readers stay consistent).
func _apply_diplomatic(p: Dictionary, kind: String, c: String, pf: String,
		df: String) -> bool:
	match kind:
		"trade":
			if "accept" in c or "yes" in c:
				# The envoy offered; the crown accepted — force the deal.
				diplomacy.sign_trade_agreement(df, pf, 3, true)
			elif "refuse" in c or "no" in c:
				diplomacy.adjust_score(pf, df, -10.0)
		"tribute":
			if "accept" in c:
				var amt: float = float(p.get("tribute_amount", 60.0))
				diplomacy.pay_tribute(df, pf, "gold", amt)
			else:
				diplomacy.adjust_score(pf, df, -15.0)
		"alliance":
			if "accept" in c or "yes" in c:
				diplomacy.form_alliance(pf, df)
			else:
				diplomacy.adjust_score(pf, df, -20.0)
		"threat":
			if "defy" in c or "refuse" in c or "no" in c:
				diplomacy.declare_war(pf, df, "defied their threat")
			else:
				var amt2: float = float(p.get("tribute_amount", 40.0))
				diplomacy.pay_tribute(pf, df, "gold", amt2)
				diplomacy.adjust_score(pf, df, 5.0)
		"surrender":
			# The crown decides a pending surrender offer (Jeremy 2026-10-04).
			var oid: String = String(p.get("surrender_offer_id", ""))
			if oid != "":
				if "accept" in c or "yes" in c:
					diplomacy.resolve_surrender(oid, true)
				else:
					diplomacy.resolve_surrender(oid, false)
		"betrayal":
			# An ally's loyalty wavered: buy it back or meet the knife.
			if "bribe" in c or "pay" in c:
				var amt3: float = float(p.get("tribute_amount", 60.0))
				diplomacy.pay_tribute(pf, df, "gold", amt3)
				diplomacy.adjust_score(pf, df, 10.0)
			else:
				diplomacy.declare_war(df, pf, "betrayal")
		"aid":
			# A wartime ally begs the crown for aid (Jeremy 2026-10-05).
			var aid_id: String = String(p.get("aid_request_id", ""))
			if aid_id != "":
				if "send" in c or "yes" in c or "accept" in c:
					diplomacy.resolve_aid(aid_id, true)
				else:
					diplomacy.resolve_aid(aid_id, false)
		_:
			return false
	relations[df] = int(diplomacy.relation_score(pf, df))
	return true


func _find_petition(petition_id: int) -> Dictionary:
	for p: Dictionary in petitions:
		if int(p.get("id", 0)) == petition_id:
			return p
	return {}


static func _CourtHeadline(p: Dictionary, choice: String) -> String:
	return "The Crown Rules on %s's %s Plea" % [
		String(p.get("from_name", "A petitioner")),
		String(p.get("kind", "petition")).capitalize()]


static func _CourtBody(p: Dictionary, choice: String) -> String:
	return "%s, %s, petitioned the crown regarding %s. The crown's answer: \"%s.\"" % [
		String(p.get("from_name", "A petitioner")),
		String(p.get("role", "citizen")),
		String(p.get("kind", "a matter")),
		choice]


## --- Gazette ------------------------------------------------------------------

## Publishes a story about a REAL sim event. Never canned — the caller
## passes the real headline/body. Returns the story.
## Optional `extra` keys (e.g. {"urgent": true}) are merged into the archived
## story AND the bus payload, so Chronicle articles and the toast see them.
func publish_story(headline: String, body: String, kind: String = "default",
		extra: Dictionary = {}) -> Dictionary:
	# HTML parity: section/reporter/cartoon/caption from SimGazette (STAGE20-3).
	var GazetteScript := load("res://scripts/sim/gazette.gd")
	# Jeremy 2026-10-06 launch readiness (gate 4): story text must be
	# glyph-free (test_gazette_glyphs.gd standing rule) — policies/festival
	# stories carried emoji into the phone newspaper's article card, which
	# has no emoji fallback font (tofu boxes on iPhone).
	headline = GazetteScript.sanitize_story_text(headline)
	body = GazetteScript.sanitize_story_text(body)
	var gaz: RefCounted = GazetteScript.new(_gs)
	var story_stub := {"headline": headline, "story": body, "day": _gs.day_number}
	var s: Dictionary = {
		"id": _story_seq,
		"day": _gs.day_number,
		"headline": headline,
		"body": body,
		"story": body,
		"kind": kind,
		"section": gaz.section_for(story_stub),
		"reporter": gaz.reporter_for(story_stub),
		"cartoon_path": gaz.cartoon_path_for(story_stub),
		"caption": gaz.caption_for(story_stub),
	}
	for k in extra.keys():
		s[k] = extra[k]
	_story_seq += 1
	stories.append(s)
	_gs.bus.gazette_story.emit(s)
	return s


## Newest-first news feed.
func news_feed() -> Array:
	var arr: Array = stories.duplicate()
	arr.reverse()
	return arr


## Stories published since the player last opened the Chronicle
## (HTML parity: st.unreadNews, incremented per new story).
func unread_news() -> int:
	return maxi(0, stories.size() - news_seen)


## Opening the Chronicle marks everything read (HTML: unreadNews = 0
## when the gazette news tab opens).
func mark_news_read() -> void:
	news_seen = stories.size()


## "Vol. X — No. Y" off the real game calendar (HTML parity).
func issue_line() -> String:
	var vol: int = int(_gs.day_number / 30) + 1
	var no: int = _gs.day_number
	return "Vol. %d — No. %d" % [vol, no]


## Relation of a faction to the player's (-100..100, 0 when unknown).
func relation_of(faction: String) -> int:
	return int(relations.get(faction, 0))


## True when a faction is effectively at war with the player.
func at_war(faction: String) -> bool:
	return relation_of(faction) <= -50

## --- Domestic petitions ---------------------------------------------------------
## Mayors, lords and commanders petition about troops/supplies/taxes/
## festivals (HTML PEOPLE_TEMPLATES, faithful text and effects).
## Template schema: {id, role, text, talk, options: Array[String]}.
## "talk" is the petitioner's chat opener for the 💬 Talk button.

const DOMESTIC_TEMPLATES := [
	{"id": "mayor_grain", "role": "mayor",
		"text": "My liege, our grain stores run thin — the children go to bed hungry. Might the crown release 60 food from the royal reserve?",
		"talk": "The granaries echo, sire. Empty shelves, empty bellies.",
		"options": ["Release Food", "Refuse"]},
	{"id": "mayor_roads", "role": "mayor", "when": "rich",
		"text": "The roads to the mill are mud and misery, sire. 80 gold would stone them proper — merchants would sing your name.",
		"talk": "Another cart lost a wheel in the mud today, sire.",
		"options": ["Fund Repairs (80g)", "Refuse"]},
	{"id": "mayor_caravan", "role": "mayor", "when": "traderoute",
		"text": "The merchants grow bold, sire — our wagons roll to foreign halls, but two wagons a road is a thin trickle. 100 gold outfits the guild with extra caravans on every open route, and the tolls will fatten the crown's purse.",
		"talk": "Thin trickles, sire. The guild could flood the roads with wagons.",
		"options": ["Fund Caravans (100g)", "Refuse"]},
	{"id": "commander_draft", "role": "commander",
		"text": "My liege. The ranks are thin and the borders are not. Give the word and I will conscript 4 citizens into the army — you will see them muster in the yard.",
		"talk": "The yard stands empty, sire. Give me bodies and I'll give you an army.",
		"options": ["Draft Them", "Refuse"]},
	{"id": "commander_guns", "role": "commander",
		"text": "The walls sit cold and unmanned, sire. Let me put citizens on the walls — you will see the crews climb up with your own eyes.",
		"talk": "Cold walls, sire. Walls don't hold themselves.",
		"options": ["Man the Walls", "Refuse"]},
	{"id": "lord_levy", "role": "lord",
		"text": "Cousin. My coffers are… light, and loyalty, like wine, must be kept topped up. A gift of 200 gold would remind me how much I adore the crown.",
		"talk": "Loyalty is a vintage that sours without… topping up, cousin.",
		"options": ["Pay 200g", "Refuse"]},
	{"id": "lord_raid", "role": "lord",
		"text": "The neutral dogs grow fat on our border, sire. Unleash me — let my riders raid their outlying farms and bring back glory (and grain).",
		"talk": "Their granaries overflow while ours echo, sire. One word.",
		"options": ["Unleash Him", "Forbid It"]},
	{"id": "mayor_festival_ask", "role": "mayor",
		"text": "The town is grey, sire. A festival — music, pies, dancing in the mud — would lift every heart. 150 gold and 80 food, and I will make it legend.",
		"talk": "Grey skies, grey faces, sire. The town needs color.",
		"options": ["Hold Festival", "Not Now"]},
	{"id": "commander_bandits", "role": "commander",
		"text": "Bandits bleed the trade road, sire. Give me 100 gold for a proper sweep and I will hang the problem from the old oak — personally.",
		"talk": "Another merchant robbed on the trade road last night, sire.",
		"options": ["Fund Sweep (100g)", "Refuse"]},
	{"id": "mayor_grumble_tax", "role": "mayor", "when": "hightax",
		"text": "Sire… the people groan under the tax. {tax}%! They whisper in the taverns. Might the crown show mercy?",
		"talk": "The taverns whisper, sire, and whispers grow teeth.",
		"options": ["Lower to 10%", "Hold Firm"]},
	{"id": "lord_plot_rumor", "role": "lord", "when": "lordangry",
		"text": "They say you slighted me, cousin. They say the lords meet in cellars and speak your name like a curse. Prove them wrong — grant me command of the town guard.",
		"talk": "Cellars, cousin. The lords meet in cellars and speak your name.",
		"options": ["Grant Command", "Deny"]},
]


## Courtier mood (-100..100, HTML charByKey().mood parity). Lives on the
## unit's mind dict so it survives as plain data.
static func court_mood_of(unit: Dictionary) -> float:
	return float((unit.get("mind", {}) as Dictionary).get("court_mood", 0.0))


func bump_court_mood(unit: Dictionary, d: float) -> void:
	var mind: Dictionary = unit.get("mind", {})
	mind["court_mood"] = clampf(float(mind.get("court_mood", 0.0)) + d, -100.0, 100.0)


## Role-holders of the player's faction (mayor/lord/commander/...).
func _role_holders(role: String) -> Array:
	var out: Array = []
	var pf: String = _gs.player_faction
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		if String((u.get("mind", {}) as Dictionary).get("gov_role", "")) == role:
			out.append(u)
	return out


func _template_when_ok(tpl: Dictionary) -> bool:
	match String(tpl.get("when", "")):
		"":
			return true
		"rich":
			return _gs.resources.get_amount(_gs.player_faction, "gold") > 200.0
		"hightax":
			return policies != null and int(policies.state.get("tax", 0)) >= 25
		"traderoute":
			# The caravan petition only makes sense while the crown has
			# at least one live trade route to fatten.
			var tr = _gs.get("trade_routes")
			if tr == null:
				return false
			for r in tr.routes:
				var ra := String(r.get("a", ""))
				var rb := String(r.get("b", ""))
				if ra == _gs.player_faction or rb == _gs.player_faction:
					return true
			return false
		"lordangry":
			var lords: Array = _role_holders("lord")
			return not lords.is_empty() and court_mood_of(lords[0]) < -20.0
	return true


## Daily domestic petition pressure (HTML ambientMessageTick parity):
## at most 6 unresolved, ~55% chance per day, roles rotate.
func _maybe_domestic_petition() -> void:
	if open_petitions().size() >= 6:
		return
	if randf() > 0.55:
		return
	generate_domestic_petition()


## Generates one domestic petition from a matching template. Returns the
## petition, or {} when nothing matched.
func generate_domestic_petition() -> Dictionary:
	var open_tpls: Dictionary = {}
	for p: Dictionary in open_petitions():
		open_tpls[String(p.get("tpl", ""))] = true
	var cands: Array = []
	for tpl: Dictionary in DOMESTIC_TEMPLATES:
		if open_tpls.has(String(tpl.get("id", ""))):
			continue  # don't nag twice about the same thing
		if not _template_when_ok(tpl):
			continue
		if _role_holders(String(tpl.get("role", ""))).is_empty():
			continue
		cands.append(tpl)
	if cands.is_empty():
		return {}
	var tpl: Dictionary = cands[randi() % cands.size()]
	var holders: Array = _role_holders(String(tpl.get("role", "")))
	var holder: Dictionary = holders[randi() % holders.size()]
	var text: String = String(tpl.get("text", ""))
	if policies != null:
		text = text.replace("{tax}", str(int(policies.state.get("tax", 0))))
	var opts: Array[String] = []
	for o: Variant in tpl.get("options", []):
		opts.append(String(o))
	var p: Dictionary = petition(holder, String(tpl.get("id", "")), text, opts)
	p["tpl"] = String(tpl.get("id", ""))
	p["talk"] = String(tpl.get("talk", ""))
	return p

## Resolved petitions, newest first (for the Gazette Messages tab).
func petition_history(limit: int = 20) -> Array:
	var out: Array = []
	for p: Dictionary in petitions:
		if bool(p.get("resolved", false)):
			out.append(p)
	out.reverse()
	return out.slice(0, limit)


## Domestic template effects (HTML PEOPLE_TEMPLATES run() bodies).
## Returns the shortfall story when a granted petition proves undeliverable
## (bare coffers, failed policy), so decide() reports the failure honestly
## instead of the generic ruling headline. Returns {} when the normal
## success/failure stories were published inline (existing behavior).
func _apply_domestic(p: Dictionary, option_index: int) -> Dictionary:
	var pf: String = _gs.player_faction
	var tpl: String = String(p.get("tpl", ""))
	var from: Dictionary = _gs.get_unit(int(String(p.get("from_key", "u0")).trim_prefix("u")))
	match tpl:
		"mayor_grain":
			if option_index == 0:
				if _gs.resources.get_amount(pf, "food") < 60.0:
					return _shortfall_story(p, "60 food from the royal reserve")
				_gs.resources.add_resource(pf, "food", -60.0)
				_happiness(6)
				bump_court_mood(from, 12)
				publish_story("CROWN FEEDS THE HUNGRY",
					"The ruler opened the royal granaries. Bakers wept. Children cheered.",
					"court")
			else:
				_happiness(-4)
				bump_court_mood(from, -10)
		"mayor_roads":
			if option_index == 0:
				if _gs.resources.get_amount(pf, "gold") < 80.0:
					return _shortfall_story(p, "80 gold to pave the mill road")
				_gs.resources.add_resource(pf, "gold", -80.0)
				_happiness(4)
				bump_court_mood(from, 8)
				publish_story("ROADS PAVED",
					"Stone by stone, the mill road is rebuilt. Merchants sing the crown's name.",
					"court")
			else:
				bump_court_mood(from, -6)
				_happiness(-2)
		"commander_draft":
			if option_index == 0:
				var n: int = _draft(pf, from, 4)
				bump_court_mood(from, 10)
				publish_story("DRAFT DECLARED",
					"%d citizens take up arms in the town yard. Mothers weep; the commander salutes." % n,
					"court")
			else:
				bump_court_mood(from, -10)
		"commander_guns":
			if option_index == 0:
				var n: int = _draft(pf, from, 2)
				bump_court_mood(from, 10)
				publish_story("WALLS MANNED",
					"%d citizens climb the walls with spears. The town feels safer already." % n,
					"court")
			else:
				bump_court_mood(from, -8)
		"lord_levy":
			if option_index == 0:
				if _gs.resources.get_amount(pf, "gold") < 200.0:
					return _shortfall_story(p, "200 gold to top up his loyalty")
				_gs.resources.add_resource(pf, "gold", -200.0)
				bump_court_mood(from, 16)
			else:
				bump_court_mood(from, -22)
				if not from.is_empty() and court_mood_of(from) < -40.0:
					publish_story("LORD GRUMBLES",
						"%s was seen drinking heavily and muttering about \"weak crowns\"."
						% String(p.get("from_name", "A lord")), "court")
		"lord_raid":
			if option_index == 0:
				var n: int = _draft(pf, from, 3)
				_gs.resources.add_resource(pf, "food", 120.0)
				bump_court_mood(from, 14)
				publish_story("RAIDERS RIDE OUT",
					"The lord's riders cross the border at dusk. They return with grain and grim smiles.",
					"court")
			else:
				bump_court_mood(from, -12)
		"mayor_festival_ask":
			if option_index == 0:
				if policies != null:
					var tid: int = int(from.get("town_id", -1))
					# hold_festival can fail (cooldown, bare coffers) — say
					# so, instead of resolving the petition in silence.
					var fest_result: String = policies.hold_festival(tid)
					if not fest_result.begins_with("Festival held"):
						return _shortfall_story(p, "a festival (%s)" % fest_result)
				else:
					return _shortfall_story(p, "a festival")
			else:
				bump_court_mood(from, -6)
				_happiness(-2)
		"commander_bandits":
			if option_index == 0:
				if _gs.resources.get_amount(pf, "gold") < 100.0:
					return _shortfall_story(p, "100 gold for a bandit sweep")
				_gs.resources.add_resource(pf, "gold", -100.0)
				var n: int = _draft(pf, from, 2)
				bump_court_mood(from, 10)
				publish_story("BANDITS SWEPT",
					"The commander's patrol returns with bandit scalps and merchant gratitude.",
					"court")
			else:
				bump_court_mood(from, -8)
		"mayor_grumble_tax":
			if option_index == 0:
				if policies != null:
					policies.set_tax(10)
				bump_court_mood(from, 12)
				_happiness(8)
				publish_story("TAXES LOWERED",
					"The crown shows mercy. Taverns toast the ruler's name.", "court")
			else:
				bump_court_mood(from, -12)
				_happiness(-4)
		"lord_plot_rumor":
			if option_index == 0:
				bump_court_mood(from, 18)
				publish_story("LORD TAKES COMMAND",
					"%s now commands the town guard. The soldiers look… uneasy."
					% String(p.get("from_name", "A lord")), "court")
			else:
				bump_court_mood(from, -15)
		"mayor_crimewave":
			# HTML maybeCrimePetition: raise militia / fund crackdown / ignore.
			if option_index == 0:
				if policies != null and policies.set_guard("militia"):
					bump_court_mood(from, 12)
					_happiness(4)
					publish_story("MILITIA RAISED",
						"The crown raises a town militia. Watchmen take up spears in the streets.",
						"court")
				else:
					return _shortfall_story(p, "a town militia")
			elif option_index == 1:
				if _gs.resources.get_amount(pf, "gold") >= SimCrime.CRACKDOWN_COST:
					_gs.resources.add_resource(pf, "gold", -SimCrime.CRACKDOWN_COST)
					if crime != null:
						crime.start_crackdown()
					bump_court_mood(from, 8)
					publish_story("CRACKDOWN ORDERED",
						"The crown funds a three-day crackdown. Informers grow rich.",
						"court")
				else:
					return _shortfall_story(p, "120 gold for a three-day crackdown")
			else:
				bump_court_mood(from, -12)
				_happiness(-4)
		"mayor_caravan":
			# HTML boost_trade port: fund extra caravans on every open route.
			if option_index == 0:
				if _gs.resources.get_amount(pf, "gold") < 100.0:
					return _shortfall_story(p, "100 gold to outfit the caravans")
				_gs.resources.add_resource(pf, "gold", -100.0)
				var boosted := 0
				var tr = _gs.get("trade_routes")
				if tr != null:
					boosted = int(tr.boost_routes(pf))
				bump_court_mood(from, 10)
				_happiness(2)
				publish_story("CARAVANS FUNDED",
					"The crown outfits the merchant guild: %d extra wagons \
roll out on the trade roads. The tolls will come back tenfold." % boosted,
					"court")
			else:
				bump_court_mood(from, -8)
				_happiness(-1)
	# {} = the normal success/failure stories were published inline above;
	# decide() then reports the generic ruling headline (existing behavior).
	return {}


## Publishes an explicit "empty promise" story when a granted petition
## proves undeliverable (bare coffers, failed policy). Previously these
## cases silently returned, leaving the player believing the effect had
## happened. Returns the story so decide() reports it honestly.
func _shortfall_story(p: Dictionary, need: String) -> Dictionary:
	var from: Dictionary = _gs.get_unit(int(String(p.get("from_key", "u0")).trim_prefix("u")))
	bump_court_mood(from, -8)
	_happiness(-2)
	return publish_story("THE CROWN FALTERS",
		"%s asked the crown for %s. The crown said yes — then counted its stores and fell silent. The court remembers an empty promise." % [
			String(p.get("from_name", "A courtier")), need],
		"court")


## Conscript n citizens as soldiers near the petitioner's town
## (HTML issueDraft parity, cap-respecting via Spawner).
func _draft(pf: String, from: Dictionary, n: int) -> int:
	var made: int = 0
	var tid: int = int(from.get("town_id", -1))
	var pos := Vector2(400, 400)
	if not from.is_empty() and from.has("position"):
		pos = from["position"]
	for i: int in n:
		var u: Dictionary = _gs.spawner.spawn_unit(pf, "soldier", tid,
			pos + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0)))
		if u.is_empty():
			break
		made += 1
	return made


func _happiness(d: float) -> void:
	if policies != null and policies.has_method("add_happiness"):
		policies.add_happiness(d)

## --- save -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"relations": relations.duplicate(true),
		"petitions": petitions.duplicate(true),
		"stories": (stories as Array).slice(maxi(0, stories.size() - 60)).duplicate(true),
		"news_seen": news_seen,
		"petition_seq": _petition_seq,
		"story_seq": _story_seq,
		"policies": policies.to_dict() if policies != null else {},
	}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	relations = (data.get("relations", {}) as Dictionary).duplicate(true)
	petitions.clear()
	for p: Variant in data.get("petitions", []):
		petitions.append((p as Dictionary).duplicate(true))
	stories.clear()
	for s: Variant in data.get("stories", []):
		stories.append((s as Dictionary).duplicate(true))
	_petition_seq = int(data.get("petition_seq", 1))
	_story_seq = int(data.get("story_seq", 1))
	if data.has("news_seen"):
		news_seen = int(data.get("news_seen", 0))
	else:
		# Old saves predate the badge: everything saved already counts as read,
		# so the Chronicle doesn't open with a bogus "9+" badge.
		news_seen = stories.size()
	if policies != null:
		policies.from_dict(data.get("policies", {}))
