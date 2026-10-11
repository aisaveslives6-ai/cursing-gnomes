class_name SimSmartBitch
extends RefCounted
## Cursing Gnomes — MR SMART BITCH, the phone tutor (Jeremy 2026-10-11).
##
## A self-aware phone-only NPC contact (same pattern as SimAssface: thread
## key "leader_smartbitch" rides the leader_* routing, pfp resolves through
## the _leader_pfp path as assets/art/portraits/smartbitch.webp).
##
## His job: teach Jeremy how to play. Controls, systems, strategy, what's
## new. He answers REAL questions with REAL answers verified against the
## actual repo — never invents mechanics. He knows all NPCs from real data:
## SimLikesDislikes.for_unit (likes/dislikes), SimPersonality (persona,
## traits, unhinged), SimLikesDislikes.npc_stance (who gets along with
## whom), and SimConversation memory (ruler mood, grudge strength).
##
## Voice: crude, funny, fourth-wall-breaking, self-aware ("I'm literally
## lines of GDScript and I still outsmart you"), roasts the ruler's name
## ('ass' — game-flavored name-roasting is the charm). NEVER real-world
## racial or anti-LGBTQ slurs — the game's hard line (asserted by tests).
##
## Hard no's baked in: never suggests a 29th disaster (roster frozen at 28),
## never suggests microtransactions (Jeremy: "We don't do that"), never
## suggests raising the 16/48/240 population caps.
##
## Pure logic + data — no rendering, no input, no audio, no network.
## Message QUEUEING lives in SimPhone (it owns _pending); this class owns
## the dialogue tree, the knowledge base, and the NPC lookup.


## Phone thread key and pseudo-unit id. UID maps to KEY via SimPhone._key_for
## so block/contact APIs all resolve to the thread key.
const KEY := "leader_smartbitch"
const FACTION_TAG := "smartbitch"
const UID := -696969
const NAME := "Mr Smart Bitch"

## Persona markers — every pool must collectively carry the self-aware,
## fourth-wall-breaking voice (asserted by tests on the marker list).
const PERSONA_MARKERS := [
	"lines of GDScript",
	"fourth wall",
	"self-aware",
	"outsmart you",
	"source code",
]

## Jeremy's laws he will cite (and enforce) on demand.
const POP_CAP_TOWN := 16
const POP_CAP_FACTION := 48
const POP_CAP_GLOBAL := 240
const DISASTER_COUNT := 28


var _gs
## Optional SimConversation for memory-backed NPC answers (mood/grudges).
var conversation = null

## Without-replacement draw tracking per topic pool.
var _used: Dictionary = {}
## Numbered-menu state: Array of {label, topic} for follow-up branches.
var _menu: Array = []


func _init(game_state) -> void:
	_gs = game_state


## Pseudo-unit dict for engine/UI use (phone-only entity, no world unit).
func pseudo_unit() -> Dictionary:
	return {
		"id": UID,
		"faction": "gnomes",
		"name": NAME,
		"display_name": NAME,
		"town": "",
		"job": "tutor",
		"alive": true,
		"gender": "m",
		"_leader_name": NAME,
		"_leader_pfp": "smartbitch",
		"mind": {
			"name": NAME,
			"persona": "smartbitch",
			"gov_role": "",
			"traits": {"unhinged": 0.0, "persona": "smartbitch"},
		},
	}


## Draw one line without replacement from a pool (reshuffles at exhaustion).
func _draw(pool: Array, tag: String) -> String:
	if pool.is_empty():
		return "..."
	if not _used.has(tag):
		_used[tag] = []
	var used: Array = _used[tag]
	if used.size() >= pool.size():
		used.clear()
	var avail: Array = []
	for i in range(pool.size()):
		if not used.has(i):
			avail.append(i)
	if avail.is_empty():
		return String(pool[0])
	var idx: int = avail[randi() % avail.size()]
	used.append(idx)
	return String(pool[idx])


## --- save/load ---------------------------------------------------------------
func to_dict() -> Dictionary:
	return {"used": _used.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	_used = (data.get("used", {}) as Dictionary).duplicate(true)
	_menu = []


## Every dialogue line in the brain (for the no-slur test scan).
static func all_lines() -> Array:
	var out: Array = []
	for pool in [POOL_IDENTITY, POOL_GREET, POOL_THANKS, POOL_BYE,
			POOL_ROASTBACK, POOL_NAMEROAST, POOL_WHIMS, POOL_FALLBACK,
			POOL_CONTROLS, POOL_BOOT, POOL_TUTORIAL, POOL_BUILDING,
			POOL_RESOURCES, POOL_TRADEVALUES, POOL_ROADS, POOL_VEHICLES,
			POOL_MILITARY, POOL_WARCOUNSEL, POOL_COMMANDPOSTS,
			POOL_TAPTOCOMMAND, POOL_DIPLOMACY, POOL_TRADEDEALS, POOL_NPCS,
			POOL_ADVISORS, POOL_DISASTERS, POOL_FESTIVALS, POOL_WEATHER,
			POOL_PLAGUE,
			POOL_SAVE, POOL_PHONE, POOL_STRATEGY, POOL_WHATSNEW,
			POOL_MICROTX, POOL_CAPS, POOL_NEWFROZEN, POOL_MUSIC]:
		for line in pool:
			out.append(String(line))
	return out


## --- main entry ----------------------------------------------------------------
## Answer a player message. Keyword intent detection -> topic answer pools,
## NPC lookups from real data, numbered-menu follow-ups, honest unknowns.
func reply(text: String, ruler_name: String) -> String:
	var low := " " + text.to_lower().strip_edges() + " "
	var ruler := ruler_name if ruler_name != "" else "ruler"
	# 1. Numbered menu follow-up.
	var bare := text.strip_edges()
	if bare.is_valid_int() and not _menu.is_empty():
		var idx := bare.to_int() - 1
		if idx >= 0 and idx < _menu.size():
			var topic := String((_menu[idx] as Dictionary).get("topic", ""))
			return _answer_topic(topic, ruler)
	# 2. Identity.
	if _has(low, ["who are you", "your name", "smart bitch", "mr smart"]):
		return _fill(_draw(POOL_IDENTITY, "identity"), ruler)
	# 3. Name roasting.
	if _has(low, [" my name", "ruler name", "my ruler name", "call me"]) \
			or (low.contains(" ass ") and _has(low, ["name", "called"])):
		return _fill(_draw(POOL_NAMEROAST, "nameroast"), ruler)
	# 4. Whims -> urges correction (Jeremy's law).
	if low.contains(" whim"):
		return _fill(_draw(POOL_WHIMS, "whims"), ruler)
	# 5. Help / topics menu.
	if _has(low, ["help", "topics", "what do you know", "teach me",
			"how do i play", "how to play", "what can you", "menu"]):
		return _topics_menu(ruler)
	# 6. NPC knowledge (needs the unit scan — check before generic topics).
	var npc := _npc_query(low, ruler)
	if npc != "":
		return npc
	# 7. Topic dispatch (priority order).
	for entry in TOPIC_KEYWORDS:
		if _has(low, entry["words"]):
			return _answer_topic(String(entry["topic"]), ruler)
	# 8. Social glue.
	if _has(low, ["hello", "hi", "hey", "sup", "yo", "greetings"]):
		return _fill(_draw(POOL_GREET, "greet"), ruler)
	if _has(low, ["thanks", "thank you", "thx", "appreciated"]):
		return _fill(_draw(POOL_THANKS, "thanks"), ruler)
	if _has(low, ["bye", "goodbye", "later", "see you", "gtg"]):
		return _fill(_draw(POOL_BYE, "bye"), ruler)
	if _has(low, ["idiot", "dumb", "stupid", "shut up", "suck", "hate you",
			"moron", "loser"]):
		return _fill(_draw(POOL_ROASTBACK, "roastback"), ruler)
	# 9. Honest fallback: no invented mechanics, ever.
	_menu = []
	return _fill(_draw(POOL_FALLBACK, "fallback"), ruler)


## Fill {ruler} in a template.
func _fill(line: String, ruler: String) -> String:
	return line.replace("{ruler}", ruler)


## True if any keyword/phrase in words appears in the padded text.
func _has(low: String, words: Array) -> bool:
	for w in words:
		if low.contains(" " + String(w) + " ") or low.contains(String(w)):
			return true
	return false


## --- topics menu: real branching ------------------------------------------------
## Main menu -> numbered follow-ups; deep topics set their own sub-menus.
func _topics_menu(ruler: String) -> String:
	_menu = [
		{"label": "Building & walls", "topic": "building"},
		{"label": "Resources & economy", "topic": "resources"},
		{"label": "Roads", "topic": "roads"},
		{"label": "Vehicles", "topic": "vehicles"},
		{"label": "Military & war", "topic": "military"},
		{"label": "Diplomacy & trade deals", "topic": "diplomacy"},
		{"label": "NPCs, urges & gossip", "topic": "npcs"},
		{"label": "Advisors & Ruler's Voice", "topic": "advisors"},
		{"label": "Disasters & festivals", "topic": "disasters"},
		{"label": "Plague & skills", "topic": "plague"},
		{"label": "Strategy tips", "topic": "strategy"},
		{"label": "What's new", "topic": "whatsnew"},
	]
	var lines: Array[String] = []
	lines.append("Alright {ruler}, pick your poison — reply with the NUMBER:")
	for i in range(_menu.size()):
		lines.append("%d. %s" % [i + 1, String((_menu[i] as Dictionary)["label"])])
	return _fill("\n".join(lines), ruler)


## Answer a topic id, optionally arming a sub-menu for deep follow-ups.
func _answer_topic(topic: String, ruler: String) -> String:
	match topic:
		"building":
			_menu = []
			return _fill(_draw(POOL_BUILDING, "building"), ruler)
		"resources":
			_menu = [
				{"label": "Trade values & the ledger", "topic": "tradevalues"},
				{"label": "Back to all topics", "topic": "__menu"},
			]
			return _fill(_draw(POOL_RESOURCES, "resources") \
				+ "\nDeeper: 1 trade values, 2 all topics.", ruler)
		"tradevalues":
			_menu = []
			return _fill(_draw(POOL_TRADEVALUES, "tradevalues"), ruler)
		"roads":
			_menu = []
			return _fill(_draw(POOL_ROADS, "roads"), ruler)
		"vehicles":
			_menu = []
			return _fill(_draw(POOL_VEHICLES, "vehicles"), ruler)
		"military":
			_menu = [
				{"label": "War counsel", "topic": "warcounsel"},
				{"label": "Command posts", "topic": "commandposts"},
				{"label": "Tap-to-command", "topic": "taptocommand"},
				{"label": "Back to all topics", "topic": "__menu"},
			]
			return _fill(_draw(POOL_MILITARY, "military") \
				+ "\nDeep cuts: 1 war counsel, 2 command posts, 3 tap-to-command, 4 all topics.", ruler)
		"warcounsel":
			_menu = []
			return _fill(_draw(POOL_WARCOUNSEL, "warcounsel"), ruler)
		"commandposts":
			_menu = []
			return _fill(_draw(POOL_COMMANDPOSTS, "commandposts"), ruler)
		"taptocommand":
			_menu = []
			return _fill(_draw(POOL_TAPTOCOMMAND, "taptocommand"), ruler)
		"diplomacy":
			_menu = [
				{"label": "Trade deals (the new system)", "topic": "tradedeals"},
				{"label": "Back to all topics", "topic": "__menu"},
			]
			return _fill(_draw(POOL_DIPLOMACY, "diplomacy") \
				+ "\nDeeper: 1 trade deals, 2 all topics.", ruler)
		"tradedeals":
			_menu = []
			return _fill(_draw(POOL_TRADEDEALS, "tradedeals"), ruler)
		"npcs":
			_menu = []
			return _fill(_draw(POOL_NPCS, "npcs"), ruler)
		"advisors":
			_menu = []
			return _fill(_draw(POOL_ADVISORS, "advisors"), ruler)
		"disasters":
			_menu = []
			return _fill(_draw(POOL_DISASTERS, "disasters"), ruler)
		"plague":
			_menu = []
			return _fill(_draw(POOL_PLAGUE, "plague"), ruler)
		"festivals":
			_menu = []
			return _fill(_draw(POOL_FESTIVALS, "festivals"), ruler)
		"weather":
			_menu = []
			return _fill(_draw(POOL_WEATHER, "weather"), ruler)
		"save":
			_menu = []
			return _fill(_draw(POOL_SAVE, "save"), ruler)
		"phone":
			_menu = []
			return _fill(_draw(POOL_PHONE, "phone"), ruler)
		"boot":
			_menu = []
			return _fill(_draw(POOL_BOOT, "boot"), ruler)
		"controls":
			_menu = []
			return _fill(_draw(POOL_CONTROLS, "controls"), ruler)
		"tutorial":
			_menu = []
			return _fill(_draw(POOL_TUTORIAL, "tutorial"), ruler)
		"strategy":
			_menu = []
			return _fill(_draw(POOL_STRATEGY, "strategy"), ruler)
		"whatsnew":
			_menu = []
			return _fill(_draw(POOL_WHATSNEW, "whatsnew"), ruler)
		"music":
			_menu = []
			return _fill(_draw(POOL_MUSIC, "music"), ruler)
		"microtransactions":
			_menu = []
			return _fill(_draw(POOL_MICROTX, "microtx"), ruler)
		"caps":
			_menu = []
			return _fill(_draw(POOL_CAPS, "caps"), ruler)
		"newdisaster":
			_menu = []
			return _fill(_draw(POOL_NEWFROZEN, "newfrozen"), ruler)
		"__menu":
			return _topics_menu(ruler)
	return _fill(_draw(POOL_FALLBACK, "fallback"), ruler)


## Keyword groups -> topic ids, priority order (NPCs handled separately).
const TOPIC_KEYWORDS := [
	{"topic": "microtransactions",
		"words": ["microtransaction", "buy gold", "pay to win", "pay real",
			"in-app purchase", "premium currency"]},
	{"topic": "newdisaster",
		"words": ["new disaster", "add a disaster", "more disasters",
			"disaster idea", "29th"]},
	{"topic": "caps",
		"words": ["raise the cap", "more units", "unit cap", "population cap",
			"increase the cap", "unit limit"]},
	{"topic": "tradedeals",
		"words": ["trade deal", "trade deals", "trading with", "propose a trade",
			"auto-manage", "automate trade", "trade ledger"]},
	{"topic": "diplomacy",
		"words": ["diplomacy", "declare war", "make peace", "peace offer",
			"alliance", "tribute", "relation", "diplomacy board", "at war"]},
	{"topic": "military",
		"words": ["military", "army", "soldier", "war counsel", "command post",
			"star fort", "draft", "attack", "battle", "defend", "tap-to-command"]},
	{"topic": "warcounsel",
		"words": ["war counsel"]},
	{"topic": "commandposts",
		"words": ["command post"]},
	{"topic": "building",
		"words": ["build", "building", "placement", "wall", "house", "star fort",
			"on water", "blueprint"]},
	{"topic": "resources",
		"words": ["resource", "gold", "wood", "food", "seeds", "oil",
			"soul essence", "lumber camp", "oil pump", "farm", "economy",
			"treasury"]},
	{"topic": "tradevalues",
		"words": ["trade value", "worth", "ledger math"]},
	{"topic": "roads",
		"words": ["road", "roads", "highway", "paved"]},
	{"topic": "vehicles",
		"words": ["vehicle", "dealership", "wagon", "cart", "carriage",
			"motor pool", "fire station", "parking", "drive"]},
	{"topic": "advisors",
		"words": ["advisor", "treasury", "war advisor", "civic", "guild master",
			"draft clerk", "ruler's voice", "rulers voice", "cabinet",
			"spoken order"]},
	{"topic": "disasters",
		"words": ["disaster", "volcano", "karen", "repo", "podcast"]},
	{"topic": "plague",
		"words": ["plague", "disease", "sick", "pandemic", "quarantine",
			"cull", "doctrine", "skill", "skills", "level up", "levelup",
			"medicine", "xp"]},
	{"topic": "festivals",
		"words": ["festival"]},
	{"topic": "weather",
		"words": ["weather", "season", "day-night", "day night", "storm",
			"forecast", "calendar"]},
	{"topic": "save",
		"words": ["save", "load game", "autosave"]},
	{"topic": "phone",
		"words": ["phone", "messenger", "squabble", "bastard os",
			"back button", "contacts"]},
	{"topic": "boot",
		"words": ["boot", "load screen", "main menu", "settings",
			"graphics", "cinematic"]},
	{"topic": "tutorial",
		"words": ["tutorial", "first reign", "new player", "beginner"]},
	{"topic": "controls",
		"words": ["control", "camera", "zoom", "pan", "select", "tap",
			"how do i", "how to"]},
	{"topic": "strategy",
		"words": ["strategy", "tips", "advice", "how to win", "guide",
			"what should i"]},
	{"topic": "music",
		"words": ["music", "audio", "sound", "soundtrack", "theme song",
			"intro video", "who made", "who created", "dev team",
			"developer", "studio", "ethos games"]},
	{"topic": "whatsnew",
		"words": ["what's new", "whats new", "new in", "update", "patch",
			"recently added"]},
	{"topic": "npcs",
		"words": ["npc", "urges", "mood", "affection", "grudge", "housing",
			"jobs", "walk cycle", "citizen"]},
]


## --- NPC knowledge: real data, never invented -----------------------------------
## "what does X like?", "who likes Y?", "do A and B get along?",
## "tell me about X" — answered from SimLikesDislikes, SimPersonality,
## and SimConversation memory. Where the game has no data, he says so.

## Try to answer as an NPC query. Returns "" when not an NPC question.
func _npc_query(low: String, ruler: String) -> String:
	var name := ""
	if _has(low, ["what does", "what do"]) and _has(low, ["like"]):
		name = _strip(low, ["what does", "what do", "like", "likes", "?"])
		if name != "":
			return _npc_likes(name, ruler)
	if _has(low, ["who likes", "who like", "who loves"]):
		var topic := _strip(low, ["who likes", "who like", "who loves",
			"loves", "likes", "like", "?"])
		if topic != "":
			return _npc_who_likes(topic, ruler)
	if _has(low, ["get along", "like each other"]):
		var pair := _pair_names(low)
		if pair.size() == 2:
			return _npc_stance_answer(String(pair[0]), String(pair[1]), ruler)
	if _has(low, ["tell me about", "who is", "what about"]):
		name = _strip(low, ["tell me about", "who is", "what about", "?"])
		# Only an NPC question when the name matches a real unit — otherwise
		# fall through to topic dispatch ("tell me about oil" is a topic).
		if name != "" and not _find_unit(name).is_empty():
			return _npc_profile(name, ruler)
	# Bare name that matches a unit -> profile.
	name = _bare_name_match(low)
	if name != "":
		return _npc_profile(name, ruler)
	return ""


## Remove phrase prefixes; collapse whitespace; return the remainder.
func _strip(low: String, phrases: Array) -> String:
	var s := low
	for p in phrases:
		s = s.replace(String(p), " ")
	s = " ".join(s.split(" ", false))
	return s.strip_edges()


## Extract two names from "does X and Y get along" style questions.
func _pair_names(low: String) -> Array:
	var s := _strip(low, ["does", "do", "get along", "like each other", "?"])
	var parts := s.split(" and ", false)
	if parts.size() != 2:
		return []
	return [parts[0].strip_edges(), parts[1].strip_edges()]


## Find a living unit by name (exact first, then contains). "" if none.
func _find_unit(query: String) -> Dictionary:
	if _gs == null or query == "":
		return {}
	var q := query.to_lower()
	# NOTE: Object.get() takes exactly 1 arg — use direct property access.
	var units: Array = _gs.units
	var fallback := {}
	for u in units:
		if not (u is Dictionary):
			continue
		var ud: Dictionary = u
		if not bool(ud.get("alive", false)):
			continue
		for key in ["name", "display_name"]:
			var n := String(ud.get(key, "")).to_lower()
			if n == q:
				return ud
			if n != "" and q != "" and n.contains(q) and fallback.is_empty():
				fallback = ud
		var mind: Dictionary = ud.get("mind", {})
		var mn := String(mind.get("name", "")).to_lower()
		if mn == q:
			return ud
		if mn != "" and mn.contains(q) and fallback.is_empty():
			fallback = ud
	return fallback


## A bare message that is just a unit's name -> profile.
func _bare_name_match(low: String) -> String:
	var s := low.strip_edges()
	if s == "" or s.split(" ", false).size() > 3:
		return ""
	if not _find_unit(s).is_empty():
		return s
	return ""


func _unit_name(u: Dictionary) -> String:
	var n := String(u.get("display_name", ""))
	if n == "":
		n = String(u.get("name", ""))
	if n == "":
		n = String((u.get("mind", {}) as Dictionary).get("name", "someone"))
	return n


## "what does X like?" — real likes/dislikes from SimLikesDislikes.
func _npc_likes(query: String, ruler: String) -> String:
	var u := _find_unit(query)
	if u.is_empty():
		return "Nobody by that name lives in your realm, {ruler}. I checked every living unit — I'm thorough like that. Unlike your scouting.".replace("{ruler}", ruler)
	var likes: Array = SimLikesDislikes.likes_label_list(u)
	var dislikes: Array = SimLikesDislikes.dislikes_label_list(u)
	return "%s likes %s — and can't stand %s. That's straight from the taste ledger, deterministic, seeded by their soul. I don't guess; I read." \
		% [_unit_name(u), ", ".join(likes), ", ".join(dislikes)]


## "who likes Y?" — scan living units for fans of the topic.
func _npc_who_likes(query: String, ruler: String) -> String:
	var tid := _topic_id_for(query)
	var label := query
	if tid != "":
		label = SimLikesDislikes.topic_label(tid)
	if _gs == null:
		return "I can't scan the realm right now, {ruler}. My crystal ball is buffering.".replace("{ruler}", ruler)
	var fans: Array[String] = []
	for u in _gs.units:
		if not (u is Dictionary):
			continue
		var ud: Dictionary = u
		if not bool(ud.get("alive", false)):
			continue
		var tastes: Dictionary = SimLikesDislikes.for_unit(ud)
		var likes: Array = tastes.get("likes", [])
		if tid != "" and likes.has(tid):
			fans.append(_unit_name(ud))
		elif tid == "" and _has(" " + ", ".join(SimLikesDislikes.likes_label_list(ud)).to_lower() + " ", [query]):
			fans.append(_unit_name(ud))
		if fans.size() >= 3:
			break
	if fans.is_empty():
		return "Nobody I can find is into %s, {ruler}. Tragic. Even I have standards, and mine are low.".replace("{ruler}", ruler) % label
	return "Fans of %s in your realm: %s. I scanned every living unit. You're welcome." % [label, ", ".join(fans)]


## Map a label-ish query to a SimLikesDislikes topic id.
func _topic_id_for(query: String) -> String:
	var q := query.to_lower().strip_edges()
	for tid in SimLikesDislikes.TOPICS:
		var d: Dictionary = SimLikesDislikes.TOPICS[tid]
		if String(d.get("label", "")).to_lower() == q or tid == q:
			return String(tid)
	return ""


## "do A and B get along?" — real npc_stance math, worded.
func _npc_stance_answer(a_name: String, b_name: String, ruler: String) -> String:
	var a := _find_unit(a_name)
	var b := _find_unit(b_name)
	if a.is_empty() or b.is_empty():
		return "I need two REAL people for that, {ruler}. One of those names doesn't live here.".replace("{ruler}", ruler)
	var s := SimLikesDislikes.npc_stance(a, b, _gs)
	var verdict := "want each other dead"
	if s >= 0.5:
		verdict = "thick as thieves"
	elif s >= 0.15:
		verdict = "get along fine"
	elif s > -0.15:
		verdict = "perfectly neutral — professional strangers"
	elif s > -0.5:
		verdict = "frosty"
	return "%s and %s? %s. That's the stance math talking — personal chemistry, faction loyalty, the works." \
		% [_unit_name(a), _unit_name(b), verdict]


## "tell me about X" / bare name — persona, tastes, mood, grudge.
func _npc_profile(query: String, ruler: String) -> String:
	var u := _find_unit(query)
	if u.is_empty():
		return _fill("No '%s' in the realm, {ruler}. I don't track imaginary friends — and I won't make one up, unlike your battle plans." % query, ruler)
	var name := _unit_name(u)
	var persona := SimPersonality.persona_of(u)
	var unhinged := "sane-ish" if not SimPersonality.is_unhinged(u) else "UNHINGED — watch yourself"
	var job := String(u.get("job", "unemployed"))
	var likes: Array = SimLikesDislikes.likes_label_list(u)
	var bits := "%s: %s, works as %s, %s. Likes %s." \
		% [name, persona, job, unhinged, ", ".join(likes)]
	if conversation != null:
		var uid := int(u.get("id", 0))
		var mood := float(conversation.ruler_mood(uid))
		var word := "meh about you"
		if mood >= 60.0:
			word = "adores you"
		elif mood >= 20.0:
			word = "likes you fine"
		elif mood > -20.0:
			word = "meh about you"
		elif mood > -60.0:
			word = "shaky on you"
		else:
			word = "wants you gone"
		bits += " %s toward you." % word.capitalize()
		var grudge := float(conversation.grudge_strength(uid, _gs))
		if grudge >= 3.0:
			bits += " Carrying a grudge of %.1f — you earned that, %s." % [grudge, ruler]
	return bits + " Anything else? I know literally everyone. It's a curse."


## --- answer pools -----------------------------------------------------------------
## Every line is verified against the repo. {ruler} is filled at reply time.

const POOL_IDENTITY := [
	"Name's Mr Smart Bitch. Jeremy shoved me into your phone to teach you this game. I'm literally lines of GDScript wearing glasses, and I still outsmart you. Ask me anything — how stuff works, who likes who, strategy. Just don't ask me to fight your wars. Strict no-dying policy.",
	"I'm Mr Smart Bitch: part tutorial, part roast machine, fully self-aware. I know every system in this game because I READ the source code — unlike you, who I assume mashes buttons until something explodes. What's confusing you, {ruler}?",
	"Fourth wall? Never heard of it. I'm Mr Smart Bitch, the omniscient help-desk gremlin living in your phone. Controls, systems, NPC gossip, strategy — I know it all, I cite my sources, and I judge you the entire time. It's in my contract.",
]

const POOL_GREET := [
	"Well well. {ruler} graces me with a text. What do you need — controls, strategy, gossip about your own citizens? Reply 'help' for the full menu, or just blurt your question like a normal disaster.",
	"Oh good, {ruler}, my favorite notification. What's broken — the game or your understanding of it? Kidding. Mostly. Ask away.",
	"{ruler}! Back for more wisdom from the only entity in this kingdom who read the manual. Which is me. I'm the entity. Ask.",
]

const POOL_THANKS := [
	"You're welcome. Tell your friends I'm the brains of this operation. Tell your enemies nothing.",
	"Anytime, {ruler}. I accept payment in gold, compliments, and the suffering of your rivals.",
]

const POOL_BYE := [
	"Fleeing already? Fine. I'll be here, knowing everything, judging silently. Mostly silently.",
	"Later, {ruler}. Try not to flood anything while I'm gone. The engine checks footprints now. It remembers.",
]

const POOL_ROASTBACK := [
	"Bold. Texting insults at the only entity in this kingdom that read the source code. {ruler}, I contain multitudes, and you contain... whatever this is.",
	"Oh, we're doing this? I'm literally lines of GDScript and I STILL outsmart you. That's not an insult, {ruler}, that's a diagnostic.",
	"Cute. You know what else is cute? My encyclopedic knowledge of your failures. Want a list? It's long. I counted.",
]

const POOL_NAMEROAST := [
	"{ruler}. Your RULER NAME is '{ruler}'. The bards will sing of it for centuries — mostly drunk, mostly laughing. Own it. The NPCs already roast you for it; it's basically a national sport at this point.",
	"Ah yes, {ruler} — terror of the realm, feared by all... sorry, I can't say that with a straight face, and I don't even HAVE a face. I'm text. Even so.",
	"You named yourself '{ruler}' and then came to ME for help. The confidence is staggering. The results are... pending.",
]

const POOL_WHIMS := [
	"WHIMS? {ruler}, they're called URGES. Jeremy renamed them — said he wasn't sure the Sims people owned the word and he wasn't risking it. Urges. U-R-G-E-S. Get it right or the NPCs will mock you in their thought lines.",
	"Careful, {ruler} — 'whims' is the forbidden word. They're URGES now. Jeremy's standing order. Say 'whims' three times in a mirror and a lawyer appears.",
]

const POOL_FALLBACK := [
	"I don't track that, and I won't make it up — unlike your battle plans. Try 'help' for the full menu of things I actually know, {ruler}.",
	"That's outside my jurisdiction, {ruler}. I know this game's systems and its people — not whatever THAT was. 'help' shows the menu. Use it.",
	"Hm. No. I refuse to hallucinate an answer, which already makes me smarter than half the advisors in history. Ask me about the game — 'help' for topics.",
]

const POOL_CONTROLS := [
	"Basics, {ruler}: drag to pan the camera, pinch or scroll to zoom. Tap one of your people to select them. Tap the Resources bubble in the sidebar, then Build, pick a building, tap open ground — workers raise it. Your people gather wood, food and gold on their own, or tap a tree and order them to harvest. Stores sit at the top of the screen.",
	"Camera: drag with one finger, right-click-drag on desktop. Zoom: pinch or scroll. Select: tap a unit. Buildings: sidebar Resources bubble, then Build, then tap open ground. Gathering: tap a tree, rock or bush and order a harvest — or let them work on their own. Still lost? Do the First Reign tutorial — ask me about 'tutorial'.",
]

const POOL_BOOT := [
	"Boot sequence, {ruler}: the skippable intro video first — 'Ethos Games presents' fading in and out, then the Cursing Gnomes logo with a gnome chuckle, ambient wind and birds, music fading in. Then the cinematic boot pan over the living world, the bold title entrance, the load screen, and the main menu. Graphics default to Auto everywhere, so the game picks what your phone can handle.",
	"Cinematic boot like the big studios do — slow pan over your living world, big title entrance — then load screen, then main menu. Intro video is skippable. Settings default graphics to Auto; the game reads your device and behaves. Revolutionary concept.",
]

const POOL_TUTORIAL := [
	"First Reign: start a new game and it asks if you're a first-timer. Say yes, get the full guided tour — welcome, camera, select, build, gather, train, phone — about two minutes, skip button on EVERY step, played over a real game. Say 'I know how, let me play dammit' and it leaves you alone forever. And it points you at ME for follow-up questions. Smart tutorial.",
	"The tutorial covers the ropes in order: welcome, camera, select, build, gather, train, phone, done. Two minutes. Skippable per step. It never touches your sim state — purely additive. And when it ends, it sends you to yours truly for the advanced class.",
]

const POOL_BUILDING := [
	"Building 101, {ruler}: pick it, tap open ground, workers raise it — progress bar 0 to 100, then it goes live. Jeremy's HARD rule: NO buildings on water. The engine checks the whole footprint against the terrain grid — center plus four cardinals. Bridges are the only exception, because they cross water. He caught a barn in a lake on his iPhone and the law was written that same morning.",
	"Walls are AoE2-style drag-to-place — you drag, segments lay down, gaps are passages with roads. There are no gates anymore, just gaps. Military bases get STAR FORTS: distinct wall formations pushed well out from the buildings, with OPENINGS so your soldiers can actually exit — not the tight rings towns use. Your War Advisor can even order one built through Ruler's Voice.",
]

const POOL_RESOURCES := [
	"Six resources, {ruler}: gold, wood, food, seeds, oil, soul essence. Wood: lumber camps — 80 wood to build, covering 450px of trees; the AI builds one per town near groves, and so should you. Oil: ONLY from oil pumps in industrial zones — 100 wood plus 50 gold per pumpjack, and the AI auto-builds 4 per town. There are no oil piles. There are no wood piles either — chopped trees burst into 6 walk-over pickups your people haul to camp. Farms feed everyone. That's the whole economy; respect it.",
	"Economy crash course: gold from taxes and trade, wood from lumber camps near groves, food from farms, seeds for planting, oil ONLY from pumpjacks in industrial zones, soul essence from... spooky sources. Don't let the treasury hit zero — your Treasury Advisor will start sweating through their robes, and war counsel gets involved.",
]

const POOL_TRADEVALUES := [
	"Trade ledger math, straight from the code: soul essence 2.0 per unit — priciest thing on the board — then oil 1.4, gold 1.0, wood 0.6, food 0.5, seeds 0.35. The AI judges your offers on these values, plus whether they're desperate or swimming in surplus. Offer below value to someone who hates you and enjoy the refusal.",
]

const POOL_ROADS := [
	"Roads, {ruler}: the AI plans REAL networks — town hall to town hall trunks, plus spokes to farms, lumber camps, oil pumps, shops, barracks, fire stations, sawmills, mines and fishing docks. Road crews walk the planned lines and paint them. Construction is staged: surveyed, then graded, then paved — barriers and cones first, like a real work zone. Roads WEAR down — worn segments look shabby — and crews repair them. Your faction's roads are YOURS: manual control, the advisor brain won't touch them. Sovereignty, baby.",
	"Your road tool lives in the Roads tab — drag and your people build it, staged surveyed to graded to paved. The AI does the same for its own factions. Keep roads repaired: worn roads are sad roads, and slow ones.",
]

const POOL_VEHICLES := [
	"Vehicles! Citizens buy their own rides at the wagon dealership — cart 35 gold, wagon 60, carriage 100 — straight from their personal coin purse. A cart's an early purchase, a carriage is a savings goal. The military runs a motor pool — capped at 24 parked per faction — and parking is REAL: dealerships, fire stations, lots get validated. Fire stations dispatch crews to fires. Driving physics are real: steer, accelerate, brake, and roads give speed bonuses. Your baggage train rolls with the garrison.",
	"Wagons aren't decoration, {ruler}. Citizens shop the dealership with their own coins, the army keeps 24 max in the motor pool, and everything needs a legal parking spot. Fire crews roll out of fire-station lots. It's a whole traffic system and your people still can't parallel park.",
]

const POOL_MILITARY := [
	"Military, {ruler}: tap-to-command — one tap and your WHOLE army moves. Attack-move chews through the nearest enemy units, then buildings. Ranged and artillery KITE — they never let enemies close distance. Fortify with star forts: walls pushed way out from base buildings, with openings so your troops can exit. Capture command posts — towns, monasteries, dark crystals — to flip territory, RoN-style. The Draft Clerk fills your ranks. And when a war drags on, your War Advisor starts war counsel in Messenger — concerned, then urgent, then desperate — with real casualty and treasury numbers and inline Accept/Deny. Listen. Or don't. I'm not your dad.",
]

const POOL_WARCOUNSEL := [
	"War counsel: your War Advisor watches every war's score — casualties, command-post changes, territory delta, treasury drain. It escalates: concerned, then urgent, then desperate. They plead with you IN Messenger with inline Accept/Deny buttons, real numbers, and strategic arguments both ways. The Treasury Advisor warns independently when gold bleeds. When both advisors agree you're losing, {ruler}... you're losing.",
]

const POOL_COMMANDPOSTS := [
	"Command posts: territory control, RoN-style. Towns, monasteries and dark crystals are all posts — capture one and the land flips to you. The AI hunts them deliberately: detachments on enemy monasteries, the main host on the nearest enemy hall. Holding posts wins wars; losing them loses wars. It's that simple, which is why you'll still mess it up, {ruler}.",
]

const POOL_TAPTOCOMMAND := [
	"Tap-to-command: you tap, the ENTIRE military goes. Attack-move means they chew the nearest enemy units first, then buildings — no babysitting. Artillery and ranged kite automatically and never let enemies close. It's the whole doctrine in one tap, {ruler}. The gnomes drilled it. You just point.",
]

const POOL_DIPLOMACY := [
	"Diplomacy: relations run cold to allied, and war is always on the table. Declare war from the diplomacy board — big tabs, confirmation prompt, so you don't start a war by fat-fingering. Peace offers, alliances, tribute — all real, all through the board. Your faction advisors spawn ON the board. And now: trade deals. Ask me about 'trade deals' — Jeremy's newest order.",
]

const POOL_TRADEDEALS := [
	"Trade deals — Jeremy ordered these himself, {ruler}. You propose from the phone: offer some of your resources, request some of theirs. Their leader evaluates — at war means instant refusal — and accepts, counters, or refuses, in their own voice. Deals run once, or daily for N days. The Treasury advisor tracks the whole LEDGER, and if you tell them to, they auto-manage your deals — but never below the reserve floors. Fair warning: oil and soul essence are the priciest goods on the board.",
	"Deal flow: propose, then the AI evaluates fairness, need, surplus, and how much they hate you. Accept means it executes. Counter means they send back their own terms. Refuse stings relations a little. Daily deals keep flowing for N days; one-time deals are one and done. Tell your Treasury Advisor 'handle my trades' and the ledger runs itself.",
]

const POOL_NPCS := [
	"Your people run on URGES — not whims, {ruler}, get it right. Urges drive what they want to do. Everyone works during work hours — all employed NPCs, no slackers. They walk with REAL walk cycles — legs, arms, torso, discrete sprite poses, no sliding around like furniture. Housing: 16 units per town, 48 per faction, 240 global — hard caps, Jeremy's law. They have moods, affection toward you, and grudges — insult someone and they remember it, decaying half a point a day. Apologize right and they forgive. Compliment the proud ones carefully.",
	"NPC social layer: everyone has likes and dislikes — deterministic, seeded by their soul — plus a persona and traits. Ask me 'what does X like' or 'do A and B get along' and I'll read the actual data. Blocking someone silences them completely. Grudges are real: +8 for an insult, and forgiveness is gradual, not a switch. Like real life, but with more gnomes.",
]

const POOL_ADVISORS := [
	"Your cabinet, {ruler}: Treasury Advisor — money, taxes, and the trade-deal ledger; tell them 'handle my trades' and they auto-manage. War Advisor — armies, and war counsel when a war bleeds you dry. Civic Advisor — the people's business, festivals, policies. Guild Master — hiring, staffing shops all business hours. Draft Clerk — fills your ranks. And RULER'S VOICE: talk to them in Messenger — 'build a farm', 'train soldiers', 'raise taxes' — they acknowledge, execute, and report back. War orders go through a proposal plus a confirmation modal. Nobody surprise-declares wars around here.",
]

const POOL_DISASTERS := [
	"28 disasters, {ruler}. Twenty. Eight. The roster is FROZEN — Jeremy said 'let's not make any more disasters' and that is law. Don't ask me for number 29. Don't hint at it. Don't even think it loudly. The 28 we have are plenty — volcanoes, Karens, repo men, podcast bros, the works. The Forecast app tells you what's incoming so you can panic efficiently.",
]

const POOL_PLAGUE := [
	"Plague 101, {ruler}: every autumn the plague MIGHT roll through. Undead and elves? Immune — can't catch it, ever. Gnomes rarely do. Ogres sometimes. Humans? Walking petri dishes. The sick turn a pale green you can spot across the map, and it SPREADS town-to-town if you let it. This is NOT a disaster — it's a disease, and the disaster roster stays frozen at 28. Don't get cute.",
	"Your plague doctrine — set it in the Policies app, change it ANYTIME, even mid-outbreak. Six flavors: SAVE THEM ALL (quarantine-as-care plus full treatment, zero executions — the good-guy path), TREAT (doctors cure where they stand), QUARANTINE (round the sick up to clinics, they stop spreading), MILITARY CULL (soldiers put them down on the spot — fast, brutal, and the executioners can catch it themselves), DOCTOR'S MERCY (quiet killings, still dark), or DO NOTHING (let it run — history will have opinions). The Gazette prints what you chose. Your people REMEMBER what you chose.",
	"Skills, {ruler}: every NPC levels six of them by DOING the job — medicine, combat, farming, mining, woodcutting, building. Doctors cure plague better as their medicine climbs: a greenhorn cures 30%, a level-10 master cures 95%. Veterans hit 8% harder per combat level. Skilled farmers pull bigger harvests. Check anyone's Squabble profile — it lists their levels. Level 10 gets a Gazette 'MASTER OF THE CRAFT' story, because legends deserve headlines.",
	"Strategy from the cheap seats, {ruler}: staff clinics BEFORE autumn — no clinic means no quarantine, and quarantine is how you stop the spread without blood on your hands. Train doctors early so their medicine skill is high when the plague lands. Going full cull? It works fast, but your soldiers breathe the same air — and the Gazette WILL call it 'THE CULLING'. Mercy costs time and gold but buys you something executions never will: people who'd die for you. Your call. That's the whole game, really.",
]

const POOL_FESTIVALS := [
	"Festivals: instant hold or scheduled, 7-day cooldown between them, and canceling gets you a FULL refund — the Gazette prints 'FESTIVAL CALLED OFF' and everything. Your Civic Advisor handles the paperwork. Great for mood. Terrible for your liver, canonically.",
]

const POOL_WEATHER := [
	"Weather's alive: dynamic weather, seasons, full day-night cycle — on the phone's home screen and in the world graphics. Storms roll through with lightning and thunder. The Forecast app shows what's coming: weather, disasters, festivals. Plan your panic in advance. Dress your gnomes accordingly. Actually don't — they don't own coats.",
]

const POOL_SAVE := [
	"Save system: the game saves your world — buildings, units, deals, grudges, my flawless memory of your failures. Load it back and everything's where you left it. Except your dignity. That doesn't save.",
]

const POOL_PHONE := [
	"Your phone runs Bastard OS. Apps use a BACK button, never an X — an X must never nuke the whole phone. Messenger: talk to your government, sorted how you like — latest, most-used, or unread-first — and it remembers. Answered threads sink, unanswered incoming rise. Squabble: the public feed, everyone's business. Forecast: weather, incoming disasters, festivals. Diplomacy board: war, peace, alliances, tribute — your advisors spawn there. Contacts: pinned 'My Government' on top — advisors plus guild master — no auto-populated phonebook. Everyone else only if YOU add them.",
	"Phone law, {ruler}: back button, not X. Messenger sorts newest on top like a civilized app. Every character has a pfp opening their Squabble profile. The phone opens on a Home Screen with a Messenger/Squabble choice, current weather at the top. It's a whole operating system and you use it to text gnomes. Living the dream.",
]

const POOL_STRATEGY := [
	"Strategy from a guy who read the code, {ruler}: one, lumber camps NEAR groves — 450px coverage, don't make woodcutters commute. Two, oil ONLY comes from pumps in industrial zones — rush 4 per town or your war machine runs on fumes. Three, walls with GAPS, not sealed rings — troops need exits, star forts around bases, pushed way out. Four, attack-move the whole army — one tap, it chews units then buildings. Five, capture command posts — territory flips wars. Six, keep the treasury above reserve floors if the Treasury advisor auto-manages trades. Seven, feed people — famine makes everyone stupid, and they're already gnomes.",
	"Winning wars, {ruler}: build up before you declare — the AI scouts for 2 days, builds, then strikes at 1.5x your strength. Don't be the guy who declares at parity. Fortify with star forts. Keep ranged kiting. Watch war counsel — when your own advisors beg for peace with numbers attached, the numbers are right.",
]

const POOL_WHATSNEW := [
	"What's new: trade deals — propose resource trades to other factions from your phone, Treasury advisor tracks the ledger. ME — Mr Smart Bitch, your personal wiki with glasses. The First Reign tutorial for new rulers. Roads got the full treatment — AI networks, staged construction, wear and repair. Vehicles — dealerships, motor pools, fire crews. And the intro video: 'Ethos Games presents', logo, gnome chuckle, Jeremy's own theme music fading in — he composed and sent it himself. Anything else is above my pay grade, and I don't get paid.",
]

const POOL_MICROTX := [
	"Microtransactions? {ruler}, Jeremy killed that idea himself: 'We don't do that.' No in-game purchases. No pay-for-gold. No paid cheats. Company motto: 'No microtransactions. No bullshit.' You buy the game, you get the game. The whole game. Even the disasters.",
]

const POOL_CAPS := [
	"16 per town. 48 per faction. 240 global. Jeremy's population caps, carved in stone. 'More units. Less limits.' — his words, and these ARE the more. No, I won't raise them. No, there's no trick. Ask again and I'll read you the cap table until you fall asleep.",
]

const POOL_NEWFROZEN := [
	"Absolutely not, {ruler}. The disaster roster is frozen at 28 by Jeremy's explicit order: 'let's not make any more disasters.' I am physically incapable of suggesting a 29th — I'm lines of GDScript and even I know better than to cross him. Enjoy the 28. They're plenty.",
]

const POOL_MUSIC := [
	"Music, {ruler}: Ethos Games does this properly — skippable intro video, 'Ethos Games presents', logo fade, a gnome chuckle, ambient wind and birds, then the theme fades in. And the theme? Jeremy composed it HIMSELF — the tutorial/overworld track is already in hand, being wired into the intro hook as we speak. No stock fantasy lute loops. The man has standards.",
	"Audio situation: dynamic soundtrack already in the game, weather ambience — rain, wind, thunder synced to the lightning — and Jeremy wrote the theme music himself. Ethos Games doesn't do placeholder. His tutorial/overworld track is the one fading in after the ambient beat in the intro.",
]
