## Cursing Gnomes — Conversation flow engine (Jeremy 2026-10-04).
##
## "They should be able to carry a conversation too though. And learn.
##  A flow like state."
##
## This is the difference between a chatbot and a character. SimConversation
## handles intent parsing and response pools; this module handles the
## CONVERSATION itself:
##
##   Flow state machine:  opening -> engaged -> deep   (or -> closing)
##     - opening:  first exchanges, greetings, feeling each other out
##     - engaged:  active back-and-forth, the NPC asks YOU questions
##     - deep:     personal topics, opinions, gossip, real talk
##     - closing:  winding down — farewells, lost interest, or anger
##   Mood gates the flow: angry NPCs cut conversations short, happy NPCs
##   keep them going and rarely close on their own.
##
##   Thread tracking: topic per turn, so NPCs follow threads, notice when
##   you circle back ("Back to war? Like I was saying..."), and bridge
##   topic changes naturally ("Speaking of which...").
##
##   Learning:
##     - Player facts: "i love war" / "i hate taxes" / "my favorite X is Y"
##       get stored and acknowledged ("Noted — I'll remember that"), and
##       brought up later ("Last time you said you love war — still true?").
##     - Communication style: formal / crude / funny / polite / blunt is
##       detected from the player's messages and the NPC adapts its phrasing.
##     - Living Lexicon: words the player taught the NPC get USED later
##       ("You taught me 'zork' — see? I'm learning!").
##     - Session memory: topics discussed carry into the NEXT conversation
##       ("Last time we talked about war...").
##
## Pure logic — no rendering, no input, no audio. Operates on the per-NPC
## memory dict owned by SimConversation (mutations persist by reference).
class_name SimConversationFlow
extends RefCounted


## --- Flow states ------------------------------------------------------------
const ST_OPENING := "opening"
const ST_ENGAGED := "engaged"
const ST_DEEP := "deep"
const ST_CLOSING := "closing"


## --- Intent -> topic label ---------------------------------------------------
## Lets the NPC follow conversational threads. Only intents with a clear
## topic are mapped; everything else falls back to likes/dislikes keywords.
const INTENT_TOPICS := {
	"war_declare": "war", "war_threaten": "war", "war_bluff": "war",
	"war_surrender": "war", "war_how": "war", "question_wars": "war",
	"peace_offer": "peace",
	"trade_propose": "trade", "trade_accept": "trade", "trade_haggle": "trade",
	"trade_refuse": "trade",
	"tribute_offer": "tribute", "tribute_demand": "tribute",
	"tribute_refuse": "tribute",
	"alliance_propose": "alliances", "friend_ask": "friendship",
	"insult": "insults", "tease": "teasing",
	"praise": "you", "compliment_me": "you", "compliment_npc": "me",
	"compliment_town": "towns",
	"thanks": "thanks", "apology": "apologies", "forgiveness": "forgiveness",
	"request_gold": "gold", "request_troops": "troops",
	"request_help": "help", "help_offer": "help",
	"question_treasury": "treasury", "question_towns": "towns",
	"question_rulers": "rulers", "question_policy": "politics",
	"question_festival": "festivals", "calendar_info": "calendar",
	"joke": "humor", "joke_tell": "humor", "joke_request": "humor",
	"riddle": "riddles",
	"gossip": "gossip", "gossip_ruler": "gossip", "news_ask": "news",
	"tax_complaint": "taxes", "tax_how": "taxes",
	"economy_how": "economy", "resource_info": "resources",
	"recruit_how": "recruiting", "order_drills": "military",
	"question_troops": "military",
	"build_guide": "building",
	"weather": "weather", "weather_complaint": "weather",
	"weather_nice": "weather",
	"food": "food", "turnip_talk": "turnips",
	"music_taste": "music", "song": "music",
	"magic": "magic", "wizard": "magic",
	"pets": "pets", "family": "family", "marriage": "marriage",
	"relationship": "romance", "romance_proposition": "romance",
	"love_declaration": "romance", "love_advice": "romance", "flirt": "flirting",
	"dreams": "dreams", "fears": "fears", "secret": "secrets",
	"philosophy": "philosophy", "hypothetical": "what-ifs",
	"whatif_personal": "what-ifs",
	"favorite": "favorites", "favorite_more": "favorites",
	"favorite_weapon": "weapons",
	"hobbies": "hobbies", "plans": "plans", "day_recap": "today",
	"how_are_you": "feelings", "empathy_sad": "feelings",
	"empathy_worry": "feelings", "empathy_angry": "feelings",
	"comfort_ask": "feelings", "excited_share": "feelings",
	"proud_share": "feelings",
	"story_request": "stories", "story_scary": "stories",
	"advice": "advice", "advice_moral": "advice", "ruling_advice": "ruling",
	"opinion_decision": "decisions", "opinion_like": "opinions",
	"opinion_prefer": "opinions", "agree_ask": "opinions",
	"kingdom_ask": "kingdom", "faction_info": "factions",
	"place_info": "places", "location": "places", "directions": "places",
	"travel": "travel",
	"who_are_you": "me", "what_are_you_doing": "me", "work_job": "work",
	"job_detail": "work", "handyman": "work",
	"capabilities": "abilities", "game_play": "the game",
	"age": "age", "age_share": "age", "birthday": "birthdays",
	"name_set": "names", "name_meaning": "names",
	"smalltalk": "chit-chat", "acknowledgment": "chit-chat",
	"boredom": "boredom", "sleep": "rest",
	"health_ask": "health", "luck_wish": "luck",
	"gift_give": "gifts", "gift_ask": "gifts",
	"remember_ask": "memory", "truth_ask": "honesty",
	"promise_ask": "promises", "lie_accuse": "honesty",
	"threat": "threats", "dare": "dares",
	"toast_cheers": "drinks", "price_ask": "prices",
	"time_ask": "time", "how_long": "time",
	"language_ask": "words", "are_you_real": "existence",
	"boast_reply": "boasting", "excuse_me": "manners",
	"pleasant_surprise": "surprises", "welcome_reply": "greetings",
	"indecent_exposure": "scandal",
}


## Intents personal enough to deepen a conversation.
const PERSONAL_INTENTS := [
	"gossip", "gossip_ruler", "secret", "fears", "dreams",
	"romance_proposition", "relationship", "marriage", "love_declaration",
	"love_advice", "flirt", "philosophy", "favorite", "favorite_more",
	"opinion_decision", "opinion_like", "opinion_prefer", "hypothetical",
	"whatif_personal", "compliment_me", "advice", "advice_moral",
	"ruling_advice", "forgiveness", "apology", "praise", "thanks",
	"who_are_you", "family", "pets", "hobbies", "music_taste",
	"story_request", "story_scary", "how_are_you", "empathy_sad",
	"empathy_worry", "comfort_ask", "excited_share", "proud_share",
	"remember_ask", "truth_ask", "promise_ask", "friend_ask",
	"what_are_you_doing", "day_recap", "plans",
]


## --- Questions the NPC asks YOU ----------------------------------------------
## Engaged: curious back-and-forth. Deep: personal, real-talk questions.
const ENGAGED_QUESTIONS := {
	"gnome": [
		"So what's the crown's latest scheme, {ruler}?",
		"Be honest — what do you REALLY think of the war?",
		"Quick question: what's your favorite way to waste gold?",
		"You ever tried turnip wine? Asking for a friend.",
		"What's the one thing you'd change about the kingdom?",
		"Level with me -- how's the treasury REALLY looking?",
		"What's the dumbest order you've given this week? I'll go first.",
	],
	"human": [
		"What are your orders for us, {ruler}?",
		"How fares the kingdom, in your own words?",
		"Where do you stand on the war? I need to know.",
		"Is there anything the crown needs from my people?",
		"What's your proudest decision as ruler so far?",
		"What does the crown need most right now -- gold, grain, or soldiers?",
		"How do you want history to remember this conversation?",
	],
	"elf": [
		"And how are YOU, darling? Truly — not the royal 'fine'.",
		"What's your heart's desire these days?",
		"Do you ever just dream? About what?",
		"What do you make of the court's latest drama?",
		"If you could have one perfect day, what would it look like?",
		"Tell me, darling -- what's the latest scandal at court?",
		"If you could redesign the palace, what would you change first?",
	],
	"ogre": [
		"YOU LIKE SMASH, OR YOU LIKE TALK?",
		"WHAT YOU EAT TODAY? ME HUNGRY ASKING.",
		"YOU STRONG RULER? HOW YOU PROVE?",
		"WAR SOON? ME HOPE WAR SOON. YOU HOPE?",
		"WHAT BEST THING YOU EVER SMASH?",
		"ME CURIOUS. YOU EVER WRESTLE A BEAR? ME WANT DETAILS.",
		"WHAT YOU DREAM ABOUT? ME DREAM ABOUT SNACKS. YOU?",
	],
	"undead": [
		"What troubles the living today?",
		"Do you fear death, {ruler}?",
		"What news from the world of the warm-blooded?",
		"Why do you cling so tightly to your fleeting alliances?",
		"What does the crown feel like? Heavy?",
		"The grave remembers what the living forget. What do you fear forgetting?",
		"Does your heart still beat faster in battle, {ruler}? Or has it learned stillness?",
	],
}

const DEEP_QUESTIONS := {
	"gnome": [
		"Okay, real talk — what keeps you up at night?",
		"Who do you actually trust around here? No politics, just truth.",
		"What's the one thing you'd never tell the court?",
		"Ever wonder what you'd be if you weren't the ruler?",
		"What's the one debt -- gold or otherwise -- that keeps you up?",
		"If the crown fell tomorrow, who would you be?",
	],
	"human": [
		"What kind of ruler do you want to be remembered as?",
		"Do you ever doubt your decisions? Be honest.",
		"Who's your closest ally — truly, not officially?",
		"What scares you most about the future?",
		"What would you sacrifice the crown for, if anything?",
		"Who taught you how to rule -- and were they right?",
	],
	"elf": [
		"Tell me something no one else knows about you, darling.",
		"What breaks your heart?",
		"Do you believe in fate, or do we carve our own?",
		"When was the last time you cried?",
		"What do you see when you look in the mirror, truly?",
		"Is there someone you miss that no one knows about?",
	],
	"ogre": [
		"ME ASK REAL QUESTION. WHAT YOU AFRAID OF?",
		"YOU EVER LOSE SOMEONE? ME LOSE MANY. ME UNDERSTAND.",
		"WHAT MAKE YOU HAPPY? BESIDES SMASH. THERE IS BESIDES?",
		"YOU TRUST ME? ME TRUST YOU. MAYBE.",
		"ME ASK SAD QUESTION. YOU EVER CRY? ME CRY ONCE. ROCK WAS BEAUTIFUL.",
		"WHAT YOU DO WHEN EVERYBODY GONE? ME SIT. ME THINK. ME SAD.",
	],
	"undead": [
		"What will you leave behind when you die?",
		"Does the crown weigh on you? It looks heavy.",
		"Have you ever truly been alone?",
		"Do you believe the dead watch the living?",
		"When you close your eyes, whose faces do you see?",
		"The crystal took something from me once. What has it taken from you?",
	],
}

## Fact-aware questions: the NPC follows up on what it learned about you.
const FACT_QUESTIONS := [
	"You mentioned you {verb} {thing} — what's the story there?",
	"So you {verb} {thing}, huh? Tell me more.",
	"Last time you said you {verb} {thing}. Still feel that way?",
]


## --- Bridges: natural topic transitions ---------------------------------------
const BRIDGES := {
	"default": [
		"Speaking of which...",
		"That reminds me...",
		"Oh — that reminds me of something.",
		"Funny you should mention that...",
	"On that note...",
	"Which, come to think of it...",
	"That puts me in mind of something...",
	"Funny, that connects to something else...",
	],
	"formal": [
		"If I may pivot slightly...",
		"On a related note...",
		"That brings something to mind...",
	],
	"crude": [
		"Oh shit, that reminds me...",
		"Anyway —",
		"Yo, speaking of that...",
	],
	"funny": [
		"LOL, that reminds me...",
		"Okay but that reminds me...",
		"Ha! Speaking of...",
	],
}


## --- Repeat lines: circling back to a thread -----------------------------------
const REPEAT_LINES := {
	"default": [
		"Back to {t}? Like I was saying...",
		"Ah, {t} again. Like I said before...",
		"We keep coming back to {t}, don't we?",
	],
	"formal": [
		"Returning to {t}, as you wish...",
		"Ah yes, {t}. As I mentioned...",
	],
	"crude": [
		"{t} again? Fine, like I said...",
		"Back on {t}, huh? Alright...",
	],
	"funny": [
		"LOL, {t} AGAIN? Okay okay...",
		"{t}! My favorite topic, apparently.",
	],
}


## --- Session callbacks: "last time we talked about..." --------------------------
const SESSION_TOPIC_LINES := {
	"default": [
		"Last time we talked about {t}. ",
		"Still thinking about our chat on {t}. ",
		"So — {t}. We never finished that conversation. ",
	],
	"formal": [
		"I recall our last discussion of {t}. ",
		"We left {t} unresolved, I believe. ",
	],
	"crude": [
		"Yo, we never finished talking about {t}. ",
		"So {t} — still on your mind? ",
	],
	"funny": [
		"Okay so {t} — we HAVE to finish that chat. ",
		"Back for more {t} talk, huh? ",
	],
}
const SESSION_FACT_LINES := {
	"default": [
		"Last time you mentioned you {verb} {thing} — still true? ",
		"You've told me you {verb} {thing} before. Noted again! ",
	],
	"formal": [
		"You once mentioned you {verb} {thing}. Still the case? ",
	],
	"crude": [
		"You said you {verb} {thing} last time. Still? ",
	],
	"funny": [
		"Still on that '{thing}' thing, huh? You {verb} it, I remember! ",
	],
}


## --- Closing lines ---------------------------------------------------------------
const CLOSING_LINES := {
	"gnome": [
		"Anyway — I've got schemes to run. Talk later.",
		"Right, I'm off. Try not to start any wars without me.",
	"Right, I'm off to polish my axe. Don't touch anything expensive.",
	],
	"human": [
		"I should return to my duties, {ruler}.",
		"Until next time. The kingdom keeps me busy.",
	"Back to the grindstone. The grindstone misses me.",
	],
	"elf": [
		"I must float away now, darling. The drama won't gossip about itself.",
		"Until we speak again, sweetling.",
	"I must twirl away now, darling. Stay fabulous without me.",
	],
	"ogre": [
		"ME GO NOW. ME TIRED OF TALK. ME NAP.",
		"BYE! ME GO SMASH SOMETHING SMALL!",
	"ME GO NOW. STOMACH SAY SNACK TIME. STOMACH ALWAYS RIGHT.",
	],
	"undead": [
		"The dead call me back. Until next time.",
		"I must return to the silence now.",
	"The silence calls. I must answer.",
	],
}


## --- Style detection ---------------------------------------------------------------
const CRUDE_WORDS := ["damn", "hell", "shit", "fuck", "fucking", "ass",
	"bitch", "bastard", "crap", "piss", "dick", "slut", "whore"]
const FUNNY_MARKERS := ["lol", "haha", "lmao", "rofl", "hehe", "xd", ":d"]
const FORMAL_MARKERS := ["good day", "good morning", "good evening",
	"would you kindly", "could you please", "pardon me", "indeed",
	"shall we", "if you please", "sir", "madam"]
const POLITE_MARKERS := ["please", "thank", "thanks", "sorry", "appreciate",
	"if you don't mind"]
const STYLE_QUESTION_PREFIX := {
	"crude": "Straight up — ",
	"funny": "Okay okay — ",
	"blunt": "Quick one: ",
	"formal": "",
	"polite": "",
	"": "",
}

## Words too vague to become learned facts.
const VAGUE_WORDS := ["it", "that", "this", "them", "those", "stuff",
	"things", "everything", "nothing", "something"]


## ---------------------------------------------------------------------------
## Memory setup
## ---------------------------------------------------------------------------

## Fill in any missing flow fields (safe for old saves).
static func ensure_flow(mem: Dictionary) -> void:
	if not mem.has("flow_state"):
		mem["flow_state"] = ST_OPENING
	if not mem.has("turn_count"):
		mem["turn_count"] = 0
	if not mem.has("topics_discussed"):
		mem["topics_discussed"] = []
	if not mem.has("last_session_topics"):
		mem["last_session_topics"] = []
	if not mem.has("player_facts"):
		mem["player_facts"] = {}
	if not mem.has("style_scores"):
		mem["style_scores"] = {"formal": 0.0, "crude": 0.0, "funny": 0.0,
			"polite": 0.0, "blunt": 0.0}
	if not mem.has("style"):
		mem["style"] = ""
	if not mem.has("asked_questions"):
		mem["asked_questions"] = []
	if not mem.has("used_bridges"):
		mem["used_bridges"] = []
	if not mem.has("fact_questions_asked"):
		mem["fact_questions_asked"] = []
	if not mem.has("emotional_trajectory"):
		mem["emotional_trajectory"] = []
	if not mem.has("learned_words_used"):
		mem["learned_words_used"] = {}
	if not mem.has("facts_referenced"):
		mem["facts_referenced"] = []
	if not mem.has("last_had_question"):
		mem["last_had_question"] = false
	if not mem.has("session_ref_done"):
		mem["session_ref_done"] = false
	if not mem.has("prev_topic"):
		mem["prev_topic"] = ""
	if not mem.has("prev_intent"):
		mem["prev_intent"] = ""


## ---------------------------------------------------------------------------
## Topic detection
## ---------------------------------------------------------------------------

## Figure out what this message is ABOUT: a topic label like "war" or
## "war & fighting", or "" when there's no clear topic.
static func detect_topic(unit: Dictionary, text: String, intent: String) -> String:
	# 1. Likes/dislikes keyword topics win (they're emotionally loaded).
	var t := " " + _words_only(text.to_lower()) + " "
	for tid in SimLikesDislikes.TOPICS.keys():
		var keys: Array = SimLikesDislikes.TOPICS[tid].get("keys", [])
		for k in keys:
			if (" " + String(k) + " ") in t:
				return SimLikesDislikes.topic_label(String(tid))
	# 2. Intent -> topic fallback.
	if INTENT_TOPICS.has(intent):
		return String(INTENT_TOPICS[intent])
	return ""


## Lowercase alpha-only words (punctuation -> spaces) for word matching.
static func _words_only(text: String) -> String:
	var rx := RegEx.new()
	if rx.compile("[^a-z0-9 ]+") != OK:
		return text
	return rx.sub(text, " ", true)


## ---------------------------------------------------------------------------
## Learning: facts + communication style
## ---------------------------------------------------------------------------

## Learn from the player's message. Returns an acknowledgment line when a
## NEW fact was learned, a "you already told me" line when it's a repeat,
## or "" when nothing learnable was said. Style is always scored.
static func learn(text: String, mem: Dictionary) -> String:
	ensure_flow(mem)
	var t := text.to_lower().strip_edges()
	_score_style(t, mem)
	var fact := _match_fact(t)
	if fact.is_empty():
		return ""
	var facts: Dictionary = mem.get("player_facts", {})
	var key := String(fact.get("key", ""))
	if facts.has(key):
		var f: Dictionary = facts[key]
		return "You already told me you %s %s — I remember!" % [
			String(f.get("verb", "like")), String(f.get("thing", "things"))]
	facts[key] = {"verb": String(fact.get("verb", "like")),
		"thing": String(fact.get("thing", "things"))}
	mem["player_facts"] = facts
	return _fact_ack(String(fact.get("kind", "like")), fact)


## Match "i love X" / "i hate Y" / "my favorite A is B" / "i'm a Z".
static func _match_fact(t: String) -> Dictionary:
	var rx := RegEx.new()
	# i love/like/adore/enjoy X
	if rx.compile("\\bi\\s+(?:really\\s+|truly\\s+|absolutely\\s+|so\\s+)?(love|like|adore|enjoy)\\s+([a-z][a-z ]{0,40})") == OK:
		var m := rx.search(t)
		if m:
			var thing := _clean_thing(m.get_string(2))
			if thing != "" and not thing in VAGUE_WORDS:
				return {"kind": "like", "verb": m.get_string(1),
					"thing": thing,
					"key": "like_" + thing.replace(" ", "_").left(24)}
	# i hate/dislike/despise/loathe Y
	if rx.compile("\\bi\\s+(?:really\\s+|truly\\s+|absolutely\\s+)?(hate|dislike|despise|loathe)\\s+([a-z][a-z ]{0,40})") == OK:
		var m2 := rx.search(t)
		if m2:
			var thing2 := _clean_thing(m2.get_string(2))
			if thing2 != "" and not thing2 in VAGUE_WORDS:
				return {"kind": "dislike", "verb": m2.get_string(1),
					"thing": thing2,
					"key": "dislike_" + thing2.replace(" ", "_").left(24)}
	# my favorite A is B
	if rx.compile("\\bmy\\s+favorite\\s+([a-z][a-z ]{0,20}?)\\s+is\\s+([a-z][a-z ]{0,30})") == OK:
		var m3 := rx.search(t)
		if m3:
			var cat := _clean_thing(m3.get_string(1))
			var thing3 := _clean_thing(m3.get_string(2))
			if cat != "" and thing3 != "" and not thing3 in VAGUE_WORDS:
				return {"kind": "favorite", "verb": "love",
					"thing": thing3, "cat": cat,
					"key": "fav_" + cat.replace(" ", "_").left(16)}
	# i'm a Z (identity) — skip titles and superlatives, that's bragging.
	# Jeremy 2026-10-06: verb phrases are NOT identity. "i'm going to show
	# you X" is a plan, not a self-description — without this guard it
	# echoed as the nonsense "Noted — you're going to show you."
	if rx.compile("\\bi'?m\\s+(?:a\\s+|an\\s+|the\\s+)?([a-z][a-z ]{0,30})") == OK:
		var m4 := rx.search(t)
		if m4:
			var thing4 := _clean_thing(m4.get_string(1))
			var first_w := thing4.split(" ")[0] if thing4 != "" else ""
			var verb_starts := ["going", "gonna", "doing", "trying",
				"thinking", "working", "playing", "planning", "getting",
				"making", "taking", "giving", "showing", "telling",
				"asking", "about", "gonna"]
			if thing4 != "" and not first_w in verb_starts \
					and not thing4 in ["best", "greatest", "king",
						"queen", "ruler", "sorry"]:
				return {"kind": "identity", "verb": "are",
					"thing": _swap_pronouns(thing4),
					"key": "identity_" + thing4.replace(" ", "_").left(24)}
	return {}


## Trim a captured "thing" to its first few meaningful words.
static func _clean_thing(raw: String) -> String:
	var s := raw.strip_edges()
	# Cut at trailing filler.
	for filler in [" so much", " a lot", " very much", " really", " today",
			" right now", " forever", " always"]:
		if s.ends_with(filler):
			s = s.left(s.length() - filler.length())
	# Cut at conjunctions ("war because it is fun" -> "war").
	for conj in [" because ", " since ", " when ", " but ", " so ",
			" and then "]:
		var idx := s.find(conj)
		if idx > 0:
			s = s.left(idx)
	s = s.strip_edges()
	var words := s.split(" ")
	if words.size() > 4:
		s = " ".join(words.slice(0, 4))
	return s.strip_edges()


## Flip second-person pronouns when echoing the player's words back at them.
## "i'm your friend" -> ack "you're my friend", never "you're your friend".
static func _swap_pronouns(s: String) -> String:
	var rx := RegEx.new()
	var out := " " + s + " "
	var pairs := [["your", "my"], ["yours", "mine"], ["you", "me"]]
	for p in pairs:
		if rx.compile("\\b" + p[0] + "\\b") == OK:
			out = rx.sub(out, p[1], true)
	return out.strip_edges()


## Acknowledgment line for a newly learned fact.
static func _fact_ack(kind: String, fact: Dictionary) -> String:
	var thing := String(fact.get("thing", "things"))
	var verb := String(fact.get("verb", "like"))
	if thing in ["you", "u"]:
		return "Oh, you %s me? Flattering. Noted — I'll remember that." % verb
	match kind:
		"favorite":
			return "Noted — your favorite %s is %s. Good taste." % [
				String(fact.get("cat", "thing")), thing]
		"identity":
			return "Noted — you're %s. I'll remember that." % thing
	return "Oh, you %s %s? Noted — I'll remember that." % [verb, thing]


## Score the player's communication style from this message.
static func _score_style(t: String, mem: Dictionary) -> void:
	var s: Dictionary = mem.get("style_scores", {})
	# Word-boundary matching so "shit," scores but "class" doesn't.
	var padded := " " + _words_only(t) + " "
	for w in CRUDE_WORDS:
		if (" " + w + " ") in padded:
			s["crude"] = float(s.get("crude", 0.0)) + 1.0
			break
	if _contains_any(t, FUNNY_MARKERS):
		s["funny"] = float(s.get("funny", 0.0)) + 1.0
	if _contains_any(t, FORMAL_MARKERS):
		s["formal"] = float(s.get("formal", 0.0)) + 1.0
	if _contains_any(t, POLITE_MARKERS):
		s["polite"] = float(s.get("polite", 0.0)) + 1.0
	if t.length() < 12 and t.length() > 0:
		s["blunt"] = float(s.get("blunt", 0.0)) + 1.0
	if t.length() > 4 and t == t.to_upper():
		s["blunt"] = float(s.get("blunt", 0.0)) + 1.0
	mem["style_scores"] = s
	# Dominant style locks in after a few consistent messages.
	var total := 0.0
	var best := ""
	var bestv := 0.0
	for k in s.keys():
		var v := float(s[k])
		total += v
		if v > bestv:
			bestv = v
			best = String(k)
	if total >= 3.0 and bestv >= 2.0:
		mem["style"] = best


## The player's dominant communication style, or "" if unknown yet.
static func style_voice(mem: Dictionary) -> String:
	return String(mem.get("style", ""))


static func _contains_any(t: String, words: Array) -> bool:
	for w in words:
		if String(w) in t:
			return true
	return false


## ---------------------------------------------------------------------------
## Flow state machine
## ---------------------------------------------------------------------------

## Advance the conversation one turn. Returns the new flow state.
static func update(mem: Dictionary, unit: Dictionary, intent: String,
		topic: String) -> String:
	ensure_flow(mem)
	# A closed conversation that gets a new (non-farewell) message is a
	# NEW conversation: archive the old session and start fresh.
	if String(mem.get("flow_state", ST_OPENING)) == ST_CLOSING \
			and intent != "farewell":
		end_session(mem)
	mem["turn_count"] = int(mem.get("turn_count", 0)) + 1
	var turn := int(mem.get("turn_count", 0))
	# Remember where the thread was before this turn.
	mem["prev_topic"] = String(mem.get("last_topic", ""))
	mem["prev_intent"] = String(mem.get("last_intent", ""))
	if topic != "":
		mem["last_topic"] = topic
		var td: Array = mem.get("topics_discussed", [])
		if not td.has(topic):
			td.append(topic)
		mem["topics_discussed"] = td
	# Emotional trajectory: where is this conversation HEADING?
	var traj: Array = mem.get("emotional_trajectory", [])
	traj.append(float(mem.get("mood", 0.0)))
	while traj.size() > 8:
		traj.pop_front()
	mem["emotional_trajectory"] = traj

	var state := String(mem.get("flow_state", ST_OPENING))
	var mood := float(mem.get("mood", 0.0))
	var emo := SimEmotion.new().dominant(unit)
	var angry := emo in ["angry", "disgusted"] or mood < -40.0
	var happy := emo in ["happy", "proud"] or mood > 40.0

	if intent == "farewell":
		mem["flow_state"] = ST_CLOSING
		return ST_CLOSING
	# Angry NPCs cut conversations short.
	if angry and (state != ST_OPENING or turn >= 2):
		mem["flow_state"] = ST_CLOSING
		return ST_CLOSING
	match state:
		ST_OPENING:
			if turn >= 2:
				mem["flow_state"] = ST_ENGAGED
		ST_ENGAGED:
			if _is_personal(intent) and turn >= 4:
				mem["flow_state"] = ST_DEEP
			elif turn >= 12 or (turn >= 8 and not happy):
				# Lose interest and wind down.
				mem["flow_state"] = ST_CLOSING
		ST_DEEP:
			if turn >= 18 or (turn >= 14 and not happy):
				mem["flow_state"] = ST_CLOSING
	return String(mem.get("flow_state", ST_OPENING))


static func _is_personal(intent: String) -> bool:
	return intent in PERSONAL_INTENTS


## Archive this conversation's topics for next time; reset turn state.
## Long-term memory (facts, style, learned words) is KEPT.
static func end_session(mem: Dictionary) -> void:
	ensure_flow(mem)
	var td: Array = mem.get("topics_discussed", [])
	if not td.is_empty():
		mem["last_session_topics"] = td.duplicate()
	mem["turn_count"] = 0
	mem["topics_discussed"] = []
	mem["last_topic"] = ""
	mem["last_intent"] = ""
	mem["prev_topic"] = ""
	mem["prev_intent"] = ""
	mem["asked_questions"] = []
	mem["used_bridges"] = []
	mem["fact_questions_asked"] = []
	mem["last_had_question"] = false
	mem["session_ref_done"] = false
	mem["flow_state"] = ST_OPENING


## Emotional trajectory: warming / cooling / steady.
static func trajectory(mem: Dictionary) -> String:
	var traj: Array = mem.get("emotional_trajectory", [])
	if traj.size() < 3:
		return "steady"
	var n := mini(3, traj.size())
	var first := 0.0
	var last := 0.0
	for i in range(n):
		first += float(traj[i])
		last += float(traj[traj.size() - 1 - i])
	first /= float(n)
	last /= float(n)
	if last - first >= 10.0:
		return "warming"
	if first - last >= 10.0:
		return "cooling"
	return "steady"


## ---------------------------------------------------------------------------
## Conversation enrichment: callbacks, bridges, questions, learned words
## ---------------------------------------------------------------------------

## Weave flow into the reply: fact acknowledgment, thread references,
## topic bridges, a question back, and reused learned words.
static func enrich(mem: Dictionary, unit: Dictionary, faction: String,
		intent: String, topic: String, fact_ack: String, text: String,
		lexicon: Dictionary) -> String:
	ensure_flow(mem)
	var out := text
	var style := style_voice(mem)
	var prev_topic := String(mem.get("prev_topic", ""))
	var prev_intent := String(mem.get("prev_intent", ""))

	# 1. Learned-fact acknowledgment comes first ("Noted — ...").
	if fact_ack != "":
		out = fact_ack + " " + out

	# 2. Thread references: circling back, quoting, or bridging.
	if topic != "" and topic == prev_topic \
			and int(mem.get("turn_count", 0)) > 1:
		out = _pick_styled(REPEAT_LINES, style).replace("{t}", topic) \
			+ " " + out
	elif intent == prev_intent and prev_intent != "" \
			and not prev_intent in ["greeting", "acknowledgment", "unclear",
				"followup_why", "followup_more", "followup_topic"]:
		var quote := _quote_last(mem)
		if quote != "":
			out = "Like I told you — \"%s\" " % quote + out
		else:
			out = "Like I said... " + out
	elif topic != "" and prev_topic != "" and topic != prev_topic:
		out = _pick_styled(BRIDGES, style) + " " + out

	# 3. The NPC asks YOU something (engaged/deep only).
	var q := question_for(mem, unit, faction)
	if q != "":
		out += " " + q
	else:
		mem["last_had_question"] = false

	# 4. Use a word the player taught them (Living Lexicon payoff).
	var lw := use_learned_word(lexicon, mem, faction)
	if lw != "":
		out += " " + lw

	return out


## Quote the NPC's last reply briefly ("Like I told you — ...").
static func _quote_last(mem: Dictionary) -> String:
	var history: Array = mem.get("history", [])
	if history.is_empty():
		return ""
	var last: Dictionary = history[history.size() - 1]
	var npc := String(last.get("npc", ""))
	if npc.length() <= 80:
		return npc
	return npc.left(77) + "..."


## The NPC asks the player a question. "" = not this turn.
## force=true bypasses probability (used by tests).
static func question_for(mem: Dictionary, unit: Dictionary, faction: String,
		force: bool = false) -> String:
	ensure_flow(mem)
	var state := String(mem.get("flow_state", ST_OPENING))
	if not (state in [ST_ENGAGED, ST_DEEP]):
		return ""
	if bool(mem.get("flow_force_question", false)):
		force = true
	var asked: Array = mem.get("asked_questions", [])
	if not force:
		# Don't machine-gun questions two turns in a row.
		if bool(mem.get("last_had_question", false)):
			return ""
		var p := 0.35 if state == ST_ENGAGED else 0.5
		var traj := trajectory(mem)
		if traj == "cooling":
			p *= 0.5
		elif traj == "warming":
			p = minf(p * 1.25, 0.8)
		if randf() > p:
			return ""
	# Fact-aware follow-up: ask about something they learned about you.
	var facts: Dictionary = mem.get("player_facts", {})
	var fq_asked: Array = mem.get("fact_questions_asked", [])
	if not facts.is_empty() and (force or randf() < 0.4):
		var fkeys := []
		for k in facts.keys():
			if not fq_asked.has(k):
				fkeys.append(k)
		if not fkeys.is_empty():
			var fk: String = fkeys[randi() % fkeys.size()]
			var f: Dictionary = facts[fk]
			var qt: String = FACT_QUESTIONS[randi() % FACT_QUESTIONS.size()]
			var qq := qt.replace("{verb}", String(f.get("verb", "like")))\
				.replace("{thing}", String(f.get("thing", "things")))
			fq_asked.append(fk)
			mem["fact_questions_asked"] = fq_asked
			asked.append(qq)
			mem["asked_questions"] = asked
			mem["last_had_question"] = true
			return qq
	# Personality question pool for this state + faction.
	var pool: Array = []
	if state == ST_DEEP:
		pool = DEEP_QUESTIONS.get(faction, [])
	if pool.is_empty():
		pool = ENGAGED_QUESTIONS.get(faction, [])
	if pool.is_empty():
		pool = ENGAGED_QUESTIONS.get("gnome", [])
	var avail := []
	for q in pool:
		if not asked.has(q):
			avail.append(q)
	if avail.is_empty():
		avail = pool.duplicate()  # cycled through; allow repeats
	var pick: String = avail[randi() % avail.size()]
	# Style adaptation: blunt/crude/funny players get flavored openers.
	var style := style_voice(mem)
	if style != "" and randf() < 0.5:
		var pre: String = String(STYLE_QUESTION_PREFIX.get(style, ""))
		if pre != "":
			pick = pre + pick
	asked.append(pick)
	mem["asked_questions"] = asked
	mem["last_had_question"] = true
	return pick


## Weave in a Living Lexicon word the player taught this NPC.
## force=true bypasses probability (used by tests).
static func use_learned_word(lexicon: Dictionary, mem: Dictionary,
		faction: String, force: bool = false) -> String:
	ensure_flow(mem)
	if bool(mem.get("flow_force_lexuse", false)):
		force = true
	if lexicon.is_empty():
		return ""
	if not force and randf() > 0.15:
		return ""
	var used: Dictionary = mem.get("learned_words_used", {})
	var cands := []
	for w in lexicon.keys():
		if int(used.get(w, 0)) < 3:
			cands.append(String(w))
	if cands.is_empty():
		return ""
	var w: String = cands[randi() % cands.size()]
	used[w] = int(used.get(w, 0)) + 1
	mem["learned_words_used"] = used
	var d := String(lexicon.get(w, "")).left(60)
	match faction:
		"ogre":
			return "ME REMEMBER WORD! '%s'! ME USE IT! %s!" % [w.to_upper(),
				w.to_upper()]
		"elf":
			return "Oh — '%s'! You taught me that one, darling. %s, indeed!" % [w, w]
	return "That reminds me — you taught me '%s' (%s). See? I'm learning!" % [w, d]


## "Last time we talked about X..." — session callback for greetings.
## "" = nothing to bring up.
static func session_callback(mem: Dictionary, faction: String) -> String:
	ensure_flow(mem)
	var style := style_voice(mem)
	var topics: Array = mem.get("last_session_topics", [])
	if not topics.is_empty():
		mem["session_ref_done"] = true
		return _pick_styled(SESSION_TOPIC_LINES, style)\
			.replace("{t}", String(topics[0]))
	var facts: Dictionary = mem.get("player_facts", {})
	var refd: Array = mem.get("facts_referenced", [])
	for k in facts.keys():
		if not refd.has(k):
			var f: Dictionary = facts[k]
			refd.append(k)
			mem["facts_referenced"] = refd
			mem["session_ref_done"] = true
			return _pick_styled(SESSION_FACT_LINES, style)\
				.replace("{verb}", String(f.get("verb", "like")))\
				.replace("{thing}", String(f.get("thing", "things")))
	return ""


## Winding-down line appended when the conversation closes.
static func closing_line(faction: String, style: String = "") -> String:
	var pool: Array = CLOSING_LINES.get(faction, [])
	if pool.is_empty():
		pool = CLOSING_LINES.get("gnome", [])
	var line: String = pool[randi() % pool.size()]
	if style == "crude" and randf() < 0.5:
		line += " Later, you magnificent bastard."
	return line


## Pick a random variant, preferring the player's style voice.
static func _pick_styled(variants: Dictionary, style: String) -> String:
	var pool: Array = []
	if style != "" and variants.has(style):
		pool = variants[style]
	if pool.is_empty():
		pool = variants.get("default", [])
	if pool.is_empty():
		return ""
	return String(pool[randi() % pool.size()])
