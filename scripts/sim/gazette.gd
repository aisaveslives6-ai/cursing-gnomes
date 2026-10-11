class_name SimGazette
extends RefCounted
## Cursing Gnomes — The Royal Gazette ("The Cursing Chronicle").
##
## FULL PORT of the HTML Gazette system (fix79/index.html).
## Jeremy 2026-10-02: "Everything. I want all your work to be ported over."
##
## HTML source functions ported:
##   - gazetteArchetypeFor(), gazetteHashStr(), gazetteCartoonURI()
##   - GAZETTE_SECTIONS, GAZETTE_REPORTERS, GAZETTE_CAPTIONS
##   - gazSectionFor(), gazReporterFor(), gazCaptionFor(), gazIssueLine()
##   - gazArticleHtml() (as data, not HTML)
##   - gazParseIntent(), gazCraftReply(), gazSendReply()
##   - INTENT_RES, personaVoice(), bumpMood()
##   - GAZETTE_CARTOON_VARIANTS (55 editorial cartoons)
##
## STORY SCHEMA: {id, day, headline, story, icon, urgent, kicker}
## ARTICLE SCHEMA (rendered): {section, headline, byline, dayline, story,
##   cartoon_path, caption, urgent, lead}

## --- Editorial cartoon variants per archetype (HTML GAZETTE_CARTOON_VARIANTS) ---
## Maps archetype -> array of cartoon file stems in assets/ui/gazette_cartoons/
const CARTOON_VARIANTS := {
	"war": ["gaz_war_0", "gaz_war_1", "gaz_war_2", "gaz_battle_new_0", "gaz_battle_53_0"],
	"attack": ["gaz_attack_0", "gaz_attack_1", "gaz_attack_2", "gaz_attack_53_1"],
	"disaster": ["gaz_disaster_0", "gaz_disaster_1", "gaz_disaster_2", "gaz_disaster_new_0", "gaz_disaster_53_1"],
	"crime": ["gaz_crime_0", "gaz_crime_1", "gaz_crime_2", "gaz_crime_53_0"],
	"arrest": ["gaz_arrest_0", "gaz_arrest_1", "gaz_arrest_53_1"],
	"festival": ["gaz_festival_0", "gaz_festival_1", "gaz_festival_2", "gaz_festival_new_0", "gaz_festival_53_1"],
	"govchange": ["gaz_govchange_0", "gaz_govchange_1"],
	"riot": ["gaz_riot_0", "gaz_riot_1"],
	"flood": ["gaz_flood_0", "gaz_flood_1", "gaz_flood_new_0"],
	"rulerdeath": ["gaz_rulerdeath_0", "gaz_rulerdeath_1"],
	"wizard": ["gaz_wizard_0", "gaz_wizard_1", "gaz_wizard_2"],
	"coronation": ["gaz_coronation_0", "gaz_govchange_0"],
	"wedding": ["gaz_wedding_0", "gaz_festival_0", "gaz_festival_1"],
	"trial": ["gaz_trial_0", "gaz_arrest_0", "gaz_crime_0"],
	"duel": ["gaz_duel_0", "gaz_war_0", "gaz_attack_0"],
	"market": ["gaz_market_0", "gaz_festival_2"],
	"handyman": ["gaz_handyman_0"],
	"feud": ["gaz_feud_0", "gaz_riot_0", "gaz_crime_1"],
	"diplomacy": ["gaz_diplomacy_53_0", "gaz_diplomacy_53_1"],
	"trade": ["gaz_trade_53_0", "gaz_trade_53_1"],
	"weather": ["gaz_weather_53_0", "gaz_weather_53_1"],
	"build": ["gaz_build_53_0", "gaz_build_53_1"],
	"season": ["gaz_season_53_0", "gaz_season_53_1"],
}

## --- Archetype classifier patterns (HTML GAZETTE_ARCH_RES, ordered most-specific-first) ---
## Each entry: [archetype, pattern]. A story matching nothing gets no cartoon.
const ARCH_PATTERNS := [
	["wizard", "rogue wizard|wild mage"],
	["disaster", "giant ass|cussing lizard|count bastard|earthquake|volcano|tornado|meteor|plague|drought|\\bdisaster\\b|flattened|hall.{0,30}fallen|eruption|wildfire|blizzard|hailstorm|nasty priest|filthwick|monastery"],
	["flood", "flood|waters recede|deluge|inundat"],
	["handyman", "wandering handyman|handyman"],
	["riot", "\\briot\\b|revolt|uprising"],
	["feud", "full feud|fumes|petty court|dead to me|\\bfeud\\b"],
	["war", "declares war|declaration of war|\\bwar\\b|conquest|invasion|\\bsiege\\b"],
	["attack", "\\braid\\b|raiders|under attack|hostile force|ambush"],
	["rulerdeath", "leader fallen|has fallen with the|funeral|mourns|(?:ruler|king|queen|monarch).{0,25}(?:died|dead|slain)"],
	["coronation", "\\bcoronation\\b|\\bcrowned\\b"],
	["trial", "\\btrial\\b|verdict|sentenced|found guilty"],
	["arrest", "arrest|bandits swept|crackdown|caught|jailed|imprison"],
	["crime", "\\bcrime\\b|burglary|mugging|vandalism|pickpocket|theft|stolen|\\bthief\\b|thieves|assassinat"],
	["govchange", "election|re-elected|coronat|proclaimed|decree|royal ruling|anarchy|coup"],
	["wedding", "\\bwedding\\b|\\bmarried\\b|\\bmarriage\\b"],
	["duel", "\\bduel\\b|pistols at dawn"],
	["market", "market day|\\bbazaar\\b|grand market"],
	["festival", "festival|mosh pit|\\bfeast\\b"],
	["diplomacy", "\\btreaty\\b|\\balliance\\b|\\bpact\\b|\\bsummit\\b|\\benvoy\\b"],
	["trade", "\\bcaravan\\b|\\bmerchant\\b|trade deal|\\bimports\\b|\\bexports\\b|\\btrade\\b"],
	["weather", "thunderstorm|lightning storm|\\bheatwave\\b|\\bsnowstorm\\b|\\bmonsoon\\b|\\bgale\\b"],
	["build", "\\bgroundbreaking\\b|\\bconstruction\\b|new hall|tower raised|\\bcompleted\\b|\\bribbon\\b"],
	["season", "\\bharvest\\b|\\bautumn\\b|spring planting|first snow|\\bseasonal\\b"],
]

## --- Newspaper sections (HTML GAZETTE_SECTIONS) ---
const SECTIONS := {
	"wizard": "The Arcane Beat",
	"disaster": "Disaster Desk",
	"flood": "Weather Desk",
	"riot": "Civil Unrest",
	"feud": "Petty Court Drama",
	"war": "War Desk",
	"attack": "War Desk",
	"rulerdeath": "Obituaries",
	"arrest": "Crime Blotter",
	"crime": "Crime Blotter",
	"coronation": "The Royal Court",
	"govchange": "The Royal Court",
	"wedding": "Society Pages",
	"festival": "Society Pages",
	"trial": "The Courts",
	"duel": "Honor & Affairs",
	"market": "Trade & Coin",
	"handyman": "Local Heroes",
}

## --- Comedic reporter bylines (HTML GAZETTE_REPORTERS, deterministic by story hash) ---
const REPORTERS: Array[String] = [
	"Biff Grumbleink",
	"Petra Quillfingers",
	"Scribble O'Tool",
	"Mudflap Copperpen",
	"Wren Tattletale",
	"Gus Blotworth",
	"Penelope Snoop",
	"Fizzlewick Snitch",
	"Dora Inkblot",
	"Hank Scoopwell",
	"Nixie Nib",
	"Barley Bylineson",
]

## --- Figure captions (HTML GAZETTE_CAPTIONS) ---
const CAPTIONS := {
	"war": "Our war artist's impression, sketched from behind a very thick wall.",
	"coronation": "The crown, freshly polished and slightly too large, as always.",
	"flood": "Artist's impression of the dampness. Very, very damp.",
	"trial": "Courtroom sketch. The defendant looked guiltier in person.",
	"wedding": "The happy couple, pictured here tolerating each other beautifully.",
	"duel": "Pistols at dawn, sketched by moonlight. Honor was served.",
	"festival": "The festivities, as remembered by our correspondent (vaguely).",
	"market": "Bargains were struck. Coins were pinched. A normal market day.",
	"disaster": "Our artist survived the disaster. The sketchpad did not.",
	"handyman": "The handyman, pictured mid-fix. He asked for nothing.",
	"feud": "The feud, dramatized for readers of delicate constitution.",
	"_default": "Editorial cartoon by the Chronicle's staff artist.",
}

## --- Chat intent patterns (HTML INTENT_RES, ordered) ---
const INTENT_PATTERNS := [
	["threaten", "\\b(war|attack|destroy|crush|invade|kill|execute|behead|threaten|threat|burn|hang|imprison|treason|heads will roll)\\b"],
	["haggle", "\\b(more|less|half|price|cost|offer|counter|bargain|haggle|cheaper|discount|too much|too high|lower)\\b"],
	["question", "\\?|\\b(what|why|how|who|when|where|which|explain|tell me|pardon)\\b"],
	["agree", "\\b(yes|yeah|yep|aye|agree|agreed|accept|accepted|approve|approved|deal|done|of course|certainly|absolutely|fine|ok|okay|granted|do it|go ahead)\\b"],
	["refuse", "\\b(no|nope|nah|never|refuse|refused|decline|declined|deny|denied|reject|rejected|forbid|forbidden|no way|not interested)\\b"],
	["greet", "\\b(hello|hi|greetings|hail|good day|good morrow|well met)\\b"],
]

## --- Persona voices (HTML personaVoice) ---
const PERSONA_VOICES := {
	"worried": "wringing their hands",
	"pragmatic": "matter-of-fact",
	"jolly": "chuckling heartily",
	"proud": "with chin high",
	"scheming": "with a thin smile",
	"honorable": "gravely",
	"blunt": "without ceremony",
	"loyal": "fist to chest",
	"grizzled": "spitting to the side",
	"oily": "bowing a little too low",
	"haughty": "nose in the air",
	"earnest": "eyes wide and sincere",
}

const CARTOON_DIR := "res://assets/ui/gazette_cartoons/"

## Jeremy 2026-10-04: disaster image pools — picked by WHAT HAPPENED.
## kind -> {faction -> [stems], _funny/_battle/_deaths/_calm/_default -> [stems]}.
## Most-specific match wins: faction image > outcome image > default.
const DISASTER_IMAGE_POOLS := {
	"thicc_moose": {
		"humans": ["gaz_moose_humans"],
		"elves": ["gaz_moose_elves"],
		"ogres": ["gaz_disaster_new_0"],
		"gnomes": ["gaz_disaster_new_0"],
		"undead": ["gaz_disaster_new_0"],
		"_funny": ["gaz_disaster_new_0"],
		"_battle": ["gaz_battle_new_0", "gaz_battle_53_0"],
		"_deaths": ["gaz_disaster_1", "gaz_disaster_2"],
		"_calm": ["gaz_disaster_0"],
		"_default": ["gaz_disaster_new_0", "gaz_disaster_0"],
	},
	"giant_ass": {
		"_battle": ["gaz_battle_new_0", "gaz_battle_53_0", "gaz_attack_0"],
		"_deaths": ["gaz_disaster_1", "gaz_disaster_2"],
		"_calm": ["gaz_disaster_0"],
		"_default": ["gaz_disaster_2", "gaz_disaster_0", "gaz_disaster_1"],
	},
	## Jeremy 2026-10-04 (massive-dev): HOA Karen's own cartoon.
	"hoa_karen": {
		"_funny": ["gaz_karen_0"],
		"_battle": ["gaz_karen_0"],
		"_calm": ["gaz_karen_0"],
		"_default": ["gaz_karen_0"],
	},
	"giant_lizard": {
		"_battle": ["gaz_battle_new_0", "gaz_attack_1"],
		"_deaths": ["gaz_disaster_2", "gaz_disaster_1"],
		"_calm": ["gaz_disaster_0"],
		"_default": ["gaz_disaster_2", "gaz_disaster_0"],
	},
	"rogue_wizard": {
		"_battle": ["gaz_wizard_1", "gaz_wizard_2"],
		"_deaths": ["gaz_wizard_0", "gaz_disaster_1"],
		"_calm": ["gaz_wizard_0"],
		"_default": ["gaz_wizard_0", "gaz_wizard_1", "gaz_wizard_2"],
	},
	"bandit_raid": {
		"_battle": ["gaz_attack_0", "gaz_attack_1", "gaz_battle_53_0"],
		"_deaths": ["gaz_attack_2", "gaz_crime_1"],
		"_calm": ["gaz_attack_53_1"],
		"_default": ["gaz_attack_0", "gaz_attack_1"],
	},
	"count_bastard": {
		"_funny": ["gaz_disaster_new_0", "gaz_festival_0"],
		"_battle": ["gaz_battle_new_0"],
		"_deaths": ["gaz_disaster_1"],
		"_calm": ["gaz_disaster_0"],
		"_default": ["gaz_disaster_new_0", "gaz_disaster_0"],
	},
	"cardboard_cat": {
		"_funny": ["gaz_disaster_new_0", "gaz_festival_1"],
		"_calm": ["gaz_disaster_0"],
		"_default": ["gaz_disaster_new_0"],
	},
	"volcano": {
		"_deaths": ["gaz_disaster_1"],
		"_battle": ["gaz_disaster_1"],
		"_calm": ["gaz_disaster_1"],
		"_default": ["gaz_disaster_1"],
	},
	"wildfire": {
		"_deaths": ["gaz_disaster_1", "gaz_disaster_2"],
		"_battle": ["gaz_disaster_1"],
		"_calm": ["gaz_disaster_0"],
		"_default": ["gaz_disaster_1", "gaz_disaster_2"],
	},
}


## Jeremy 2026-10-04: most-specific disaster cartoon for what happened.
## outcome: "funny" | "battle" | "deaths" | "calm".
## Returns the full resource path.
static func disaster_cartoon_for(kind: String, target_faction: String,
		outcome: String) -> String:
	var pools: Dictionary = DISASTER_IMAGE_POOLS.get(kind, {})
	var picks: Array = []
	# 1) Deaths are somber — never the funny faction image.
	if outcome == "deaths":
		picks = pools.get("_deaths", [])
	# 2) Battle action shots.
	if picks.is_empty() and outcome == "battle":
		picks = pools.get("_battle", [])
	# 3) Faction-specific (e.g. moose mooning humans vs elves).
	if picks.is_empty() and target_faction != "" and pools.has(target_faction):
		picks = pools[target_faction]
	# 4) Outcome-specific.
	if picks.is_empty():
		picks = pools.get("_" + outcome, [])
	# 5) Kind default.
	if picks.is_empty():
		picks = pools.get("_default", [])
	# 6) Global fallback.
	if picks.is_empty():
		picks = ["gaz_disaster_0"]
	var stem: String = picks[hash_str(kind + target_faction + outcome) % picks.size()]
	return CARTOON_DIR + stem + ".jpg"

var _gs: GameState
var _regex_cache := {}


func _init(game_state: GameState) -> void:
	_gs = game_state


## --- Archetype classification -------------------------------------------------
## Headline -> archetype classifier. Ordered most-specific-first; a story that
## matches nothing gets "" (no cartoon, safe default). HTML gazetteArchetypeFor.

func archetype_for(headline: String, story: String) -> String:
	var t := str(headline) + " " + str(story)
	for pair in ARCH_PATTERNS:
		var arch: String = pair[0]
		var pattern: String = pair[1]
		var rx: RegEx = _get_regex(pattern)
		if rx.search(t) != null:
			return arch
	return ""


func _get_regex(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		var rx := RegEx.new()
		rx.compile("(?i)" + pattern)
		_regex_cache[pattern] = rx
	return _regex_cache[pattern]


## --- Deterministic hashing (HTML gazetteHashStr: djb2) ---

static func hash_str(s: String) -> int:
	var h: int = 5381
	for i in range(s.length()):
		h = ((h << 5) + h + s.unicode_at(i)) & 0xFFFFFFFF
	return h


## --- Editorial cartoon selection (HTML gazetteCartoonURI) ---
## Returns the resource path for a story's cartoon, or "" when no archetype matches.

func cartoon_path_for(story_obj: Dictionary) -> String:
	if story_obj.is_empty():
		return ""
	# Jeremy 2026-10-04: disaster stories pin their most-specific image.
	var forced := String(story_obj.get("force_cartoon", ""))
	if forced != "":
		return forced
	var arch := archetype_for(
		str(story_obj.get("headline", "")),
		str(story_obj.get("story", ""))
	)
	if arch == "":
		return ""
	var variants: Array = CARTOON_VARIANTS.get(arch, [])
	if variants.is_empty():
		return ""
	var story_id := "%s|%s|%s" % [
		str(story_obj.get("day", "")),
		str(story_obj.get("headline", "")),
		str(story_obj.get("story", "")),
	]
	var key: String = variants[hash_str(story_id) % variants.size()]
	return CARTOON_DIR + key + ".jpg"


## --- Newspaper restyle (HTML STAGE20-3) ---

func section_for(article: Dictionary) -> String:
	# Sections come from the stored kicker when present, else from the archetype.
	if article.has("kicker") and str(article["kicker"]) != "":
		return str(article["kicker"])
	var arch := archetype_for(
		str(article.get("headline", "")),
		str(article.get("story", ""))
	)
	return SECTIONS.get(arch, "Town Crier")


func reporter_for(article: Dictionary) -> String:
	var story_id := "%s|%s|%s" % [
		str(article.get("day", "")),
		str(article.get("headline", "")),
		str(article.get("story", "")),
	]
	return REPORTERS[hash_str(story_id) % REPORTERS.size()]


func caption_for(article: Dictionary) -> String:
	var arch := archetype_for(
		str(article.get("headline", "")),
		str(article.get("story", ""))
	)
	return CAPTIONS.get(arch, CAPTIONS["_default"])


## Issue/volume line off the real game calendar. HTML gazIssueLine.
## Returns "Vol. {year} — No. {issue}".
func issue_line(issue_no: int) -> String:
	var yr := 1
	if _gs != null:
		# Year from day_number (HTML uses a year counter; approximate as 1 year = 120 days).
		var dn: int = int(_gs.get("day_number")) if _gs.get("day_number") != null else 1
		yr = int(dn / 120) + 1
	return "Vol. %d — No. %d" % [yr, maxi(issue_no, 1)]


## Glyph hygiene — Jeremy 2026-10-03 standing rule (tests/test_gazette_glyphs.gd):
## Gazette story text must be glyph-free like UI chrome. Every char above
## U+2500 (all emoji — including both UTF-16 halves of astral pairs and
## variation selectors) renders as a tofu box on iPhone in the web export,
## so it is stripped here; whitespace runs left behind are collapsed.
static func sanitize_story_text(text: String) -> String:
	var out := PackedStringArray()
	for i in range(text.length()):
		if text.unicode_at(i) <= 0x2500:
			out.append(text.substr(i, 1))
	var clean: String = "".join(out)
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	return clean.strip_edges()


## News-desk routing — Jeremy 2026-10-06 standing rule: stories must land in
## the Chronicle archive (phone newspaper) AND the bus. Routes through
## court_sys.publish_story when available; falls back to a direct
## gazette_story emit when court_sys is absent (headless tests / boot).
## Optional `extra` keys (e.g. {"urgent": true}, {"icon": x}) ride both paths.
static func publish_or_emit(gs, headline: String, body: String,
		kind: String = "news", extra: Dictionary = {}) -> void:
	var court = gs.get("court_sys") if gs != null else null
	if court != null and court.has_method("publish_story"):
		# Test stub courts may only implement the 3-arg form — probe arity
		# so stubs keep working (extras are dropped for 3-arg stubs).
		var takes_extra := false
		for m in court.get_method_list():
			if String(m.get("name", "")) == "publish_story":
				takes_extra = (m.get("args", []) as Array).size() >= 4
		if takes_extra:
			court.publish_story(headline, body, kind, extra)
		else:
			court.publish_story(headline, body, kind)
		return
	var bus = gs.get("bus") if gs != null else null
	if bus == null:
		return
	var day := int(gs.get("day_number")) if gs.get("day_number") != null else 1
	var s := {"day": day, "headline": headline, "body": body, "kind": kind}
	for k in extra.keys():
		s[k] = extra[k]
	bus.gazette_story.emit(s)


## Build a full article dict from a story (HTML gazArticleHtml as data).
func article_for(story: Dictionary, lead: bool = false) -> Dictionary:
	return {
		"section": section_for(story),
		"headline": str(story.get("headline", "")),
		"icon": str(story.get("icon", "📯")),
		"byline": reporter_for(story),
		"dayline": str(story.get("day", "")),
		"story": str(story.get("story", story.get("body", ""))),
		"cartoon_path": cartoon_path_for(story),
		"caption": caption_for(story),
		"urgent": bool(story.get("urgent", false)),
		"lead": lead,
	}


## --- C67 live muster-roll (HTML liveUnitCount67 / forcesSummary67) ---
##
## The single shared live-count source for "how many X" / troop-report
## questions — always computed at speak time, never cached: living
## (non-summoned) units plus queued training. Both the court question
## handler and the Guild Master / Financial Adviser DM path answer from here.

## Jobs covered by a "forces report" (HTML COMBAT_JOBS67 — everything
## except civilian jobs). The port's canonical combat set is the JobDefs
## military category; bandit (disaster-only) and spirit (transient summon)
## are not mustered forces.
static func muster_roster() -> Array:
	var out: Array = []
	for job: String in JobDefs.jobs_in_category("military"):
		if job == "bandit" or job == "spirit":
			continue
		out.append(job)
	return out


## Live per-job count for one faction (HTML liveUnitCount67). Never cached.
static func live_unit_count(gs: GameState, faction: String, job: String) -> int:
	var n := 0
	if gs == null:
		return 0
	for u: Dictionary in gs.units:
		if bool(u.get("alive", false)) and String(u.get("faction", "")) == faction \
				and String(u.get("job", "")) == job \
				and not bool(u.get("summoned", false)):
			n += 1
	# HTML countUnitType also counts queued training (the 2026-09-19
	# infinite-production fix); the port's train_queue entries use unit_type.
	for b: Dictionary in gs.buildings:
		if not bool(b.get("alive", false)) or String(b.get("faction", "")) != faction:
			continue
		var queue: Array = b.get("train_queue", [])
		for q in queue:
			if q is Dictionary and String(q.get("unit_type", "")) == job:
				n += 1
	return n


## Natural-word -> job index for "how many X" questions (HTML trainJobWord67).
static var _muster_words: Dictionary = {}
const MUSTER_WORD_ALIASES := [
	["swordsmen", "swordsman"], ["axemen", "axeman"],
	["blunderbusses", "blunderbuss"],
	["cannons", "cannoneer"], ["artillery", "cannoneer"],
	["mechs", "tinker_mech"],
]


static func _muster_word_table() -> Dictionary:
	if _muster_words.is_empty():
		for job: String in muster_roster():
			_muster_words[job] = job
			_muster_words[job + "s"] = job  # naive plural fallback
		for pair in MUSTER_WORD_ALIASES:
			_muster_words[pair[0]] = pair[1]
	return _muster_words


## Resolve the asked-about job from "how many X" (HTML trainJobWord67).
## "" when the text names no mustered job.
static func forces_job_word(text: String) -> String:
	var rx := RegEx.new()
	rx.compile("how many\\s+([a-z]+)")
	var m := rx.search(" " + str(text).to_lower() + " ")
	if m == null:
		return ""
	var w := m.get_string(1)
	var table := _muster_word_table()
	if table.has(w):
		return String(table[w])
	if w.length() > 1 and w.ends_with("s") and table.has(w.substr(0, w.length() - 1)):
		return String(table[w.substr(0, w.length() - 1)])
	return ""


## True if the text asks for troop counts (HTML gazCraftReply question
## branch + guild master / financial adviser forces-report path).
static func is_forces_question(text: String) -> bool:
	if forces_job_word(text) != "":
		return true
	var rx := RegEx.new()
	rx.compile("(how many|troop report|forces report|army report|battle report|report our (troops|forces|army)|army status|forces status|troop count|army count|how is our army|our strength)")
	return rx.search(str(text).to_lower()) != null


## "Name: n" parts for the given jobs, live-counted (HTML qparts67).
static func muster_parts(gs: GameState, faction: String, jobs: Array) -> Array:
	var parts: Array = []
	for job in jobs:
		var jid := String(job)
		parts.append("%s: %d" % [JobDefs.job_name(jid), live_unit_count(gs, faction, jid)])
	return parts


## Resolve the job list for a forces question: a single job for
## "how many X", the full roster for a report. Empty = not a question.
static func forces_jobs(text: String) -> Array:
	var job := forces_job_word(text)
	if job != "":
		return [job]
	if is_forces_question(text):
		return muster_roster()
	return []


## Court answer (HTML gazCraftReply C67 block). "" when not a forces
## question or no game state — the caller falls back to the generic reply.
static func court_forces_answer(gs: GameState, faction: String, raw: String,
		cname: String, voice: String) -> String:
	var jobs := forces_jobs(raw)
	if gs == null or jobs.is_empty():
		return ""
	var parts: Array = muster_parts(gs, faction, jobs)
	return "\u201cOur muster rolls, my liege,\u201d says %s, %s. \u201c%s.\u201d" % [
		cname, voice, ", ".join(parts)]


## Guild Master / Financial Adviser answer (HTML guild forces-report path).
## "" when not a forces question — the caller falls through to normal chat.
static func adviser_forces_answer(gs: GameState, faction: String, raw: String) -> String:
	var jobs := forces_jobs(raw)
	if gs == null or jobs.is_empty():
		return ""
	var parts: Array = muster_parts(gs, faction, jobs)
	return "Live forces report — " + ", ".join(parts) + "."


## --- Two-way chat (HTML gazParseIntent / gazCraftReply) ---

## Parse player reply text into an intent. HTML gazParseIntent.
func parse_intent(text: String) -> String:
	var t := " " + str(text).to_lower() + " "
	for pair in INTENT_PATTERNS:
		var intent: String = pair[0]
		var pattern: String = pair[1]
		var rx: RegEx = _get_regex(pattern)
		if rx.search(t) != null:
			return intent
	return "unknown"


## Persona voice description. HTML personaVoice.
static func persona_voice(persona: String) -> String:
	return PERSONA_VOICES.get(persona, "plainly")


## Craft a reply from a court character. HTML gazCraftReply.
## character: {name, role, race, persona, mood, _agreed, _refused, _threatened}
## pending: the unresolved message dict (or empty) with {text, choices}
## Returns {text, outcome, mood_delta, agreed, refused, threatened}
static func craft_reply(character: Dictionary, intent: String, raw: String,
		pending: Dictionary, game_state: GameState = null) -> Dictionary:
	var c := character  # mutated in place (mood memory)
	var voice := persona_voice(str(c.get("persona", "")))
	var agreed: int = int(c.get("_agreed", 0))
	var refused: int = int(c.get("_refused", 0))
	var mem := ""
	if refused >= 2:
		mem = " You have refused me %d times now, and I keep count." % refused
	elif agreed >= 2:
		mem = " You have always dealt fairly with me — I remember."
	var cname := str(c.get("name", "my liege"))

	if intent == "agree" and not pending.is_empty():
		var choices: Array = pending.get("choices", [])
		var outcome := "Done."
		if not choices.is_empty():
			outcome = str(choices[0].get("outcome", "Done."))
		c["_agreed"] = agreed + 1
		c["mood"] = float(c.get("mood", 50.0)) + 6.0
		return {
			"text": "\u201cA wise decree!\u201d says %s, %s.%s" % [cname, voice, mem],
			"outcome": outcome, "resolved": true,
		}
	if intent == "refuse" and not pending.is_empty():
		var choices2: Array = pending.get("choices", [])
		var outcome2 := "So be it."
		if not choices2.is_empty():
			outcome2 = str(choices2[choices2.size() - 1].get("outcome", "So be it."))
		c["_refused"] = refused + 1
		c["mood"] = float(c.get("mood", 50.0)) - 4.0
		return {
			"text": "\u201cAs you command\u2026\u201d says %s, %s.%s" % [cname, voice, mem],
			"outcome": outcome2, "resolved": true,
		}
	if intent == "haggle" and not pending.is_empty():
		c["mood"] = float(c.get("mood", 50.0)) - 3.0
		return {
			"text": "\u201cYou drive a hard bargain, ruler!\u201d %s grits their teeth. \u201cFinal offer. Not a coin less.\u201d%s" % [cname, mem],
			"outcome": "", "resolved": false,
		}
	if intent == "haggle":
		c["mood"] = float(c.get("mood", 50.0)) - 3.0
		return {
			"text": "\u201cHaggle? There is nothing on the table to haggle over, my liege,\u201d says %s, %s.%s" % [cname, voice, mem],
			"outcome": "", "resolved": false,
		}
	if intent == "question":
		c["mood"] = float(c.get("mood", 50.0)) + 2.0
		# C67: count questions get live answers from the single shared
		# live-count source — never a stale or generic reply (HTML gazCraftReply).
		var forces_text := court_forces_answer(game_state,
			str(c.get("race", "")), raw, cname, voice)
		if forces_text != "":
			return {"text": forces_text + mem, "outcome": "", "resolved": false}
		var ans: String
		if not pending.is_empty():
			var ptext := str(pending.get("text", ""))
			# Strip any markup tags.
			var rx := RegEx.new()
			rx.compile("<[^>]*>")
			ptext = rx.sub(ptext, "", true)
			ans = "\u201cIt is simple, my liege,\u201d %s explains, %s. \u201c%s All I ask is your word.\u201d" % [cname, voice, ptext]
		else:
			ans = "\u201cThe realm turns, my liege. Ask what you will of me — I keep no secrets from the crown,\u201d says %s, %s." % [cname, voice]
		return {"text": ans + mem, "outcome": "", "resolved": false}
	if intent == "threaten":
		c["mood"] = float(c.get("mood", 50.0)) - 20.0
		c["_threatened"] = int(c.get("_threatened", 0)) + 1
		var role := str(c.get("role", ""))
		var tr := "\u201cAs you say, sire,\u201d comes the tight reply."
		match role:
			"mayor":
				tr = "\u201cM-mercy, sire!\u201d the mayor stammers, going pale. \u201cI live only to serve!\u201d"
			"lord":
				tr = "\u201cThreats, cousin?\u201d the lord says coldly. \u201cCareful. Lords have long memories and sharp knives.\u201d"
			"commander":
				tr = "\u201cThen strike, sire,\u201d the commander says flatly, hand on sword-hilt. \u201cI have faced worse than words.\u201d"
			"envoy":
				tr = "\u201cThe %ss will hear of this insult,\u201d the envoy says, %s." % [str(c.get("race", "")).capitalize(), voice]
		return {"text": tr + mem, "outcome": "", "resolved": false,
			"lord_seethes": role == "lord" and int(c.get("_threatened", 0)) >= 2}
	if intent == "greet":
		c["mood"] = float(c.get("mood", 50.0)) + 2.0
		var greetings := ["Well met, my liege!", "A good day to you, ruler.", "My liege honors me."]
		var g: String = greetings[hash_str(raw) % greetings.size()]
		return {
			"text": "\u201c%s\u201d says %s, %s.%s" % [g, cname, voice, mem],
			"outcome": "", "resolved": false,
		}
	return {
		"text": "\u201cSpeak plainly, my liege — these old ears miss riddles,\u201d says %s, %s.%s" % [cname, voice, mem],
		"outcome": "", "resolved": false,
	}
