class_name SimAssface
extends RefCounted
## Cursing Gnomes — ASSFACE, the phone disaster (Jeremy 2026-10-06).
##
## Assface is a phone-only entity (no world unit — same pattern as faction
## leaders). At random, rarely, he hijacks the phone for 30 REAL seconds of
## prank-texting: rapid-fire stupid texts to the PLAYER and prank texts
## dropped into every AI faction leader's thread (the leaders react
## in-character via the full conversation engine). Afterwards he is a
## permanent contact: messageable any time, and he ONLY talks stupid shit.
##
## Jeremy's voice direction (baked into the persona lock): Assface's core
## attitude is "I DON'T GIVE A FUCK." He doesn't care about politics,
## diplomacy, wars, feelings, any of it. When the player's topic involves
## a person or faction: "FUCK [X]!!! HE/SHE/THEY BLOWS!!!" + a stupid
## elaboration. Zero nuance, zero diplomacy, maximum defiant idiocy.
##
## Design correction (Jeremy 2026-10-06): Assface goes through the FULL
## 79-intent conversation engine for comprehension (intent, topic,
## entities — he knows what you're talking about), but his RESPONSE
## generation is persona-locked to pure idiocy. A moron who understands
## you perfectly and STILL only talks about butts is funnier and more
## alive than a random-line generator. He never breaks character into
## competence: every reply carries the not-giving-a-fuck charge AND
## references the player's topic.
##
## Thread key "leader_assface" piggybacks the leader-key routing in
## phone_ui.gd (which Assface's agent may not touch): the thread send box
## routes leader_* keys through send_leader_message, which phone.gd
## intercepts for the "assface" tag. The pfp resolves through the same
## _leader_pfp path as leader portraits (assets/art/portraits/assface.webp).
##
## Pure logic + data — no rendering, no input, no audio, no network.
## Message QUEUEING lives in SimPhone (it owns _pending); this class owns
## pools, the disaster state machine, and the persona-locked responder.


## Phone thread key and pseudo-unit id. ASSFACE_UID is mapped to KEY by
## SimPhone._key_for so block/contact APIs all resolve to the thread key.
const KEY := "leader_assface"
const FACTION_TAG := "assface"
const UID := -424242
const NAME := "Assface"

## The disaster: 30 REAL seconds of prank texting (game_time runs 1:1
## with real time). ~18 texts to the player, ~2 per AI leader.
const BURST_SECONDS := 30.0
const BURST_GAP := 1.6
const PLAYER_BURST_COUNT := 18
const LEADER_PRANK_COUNT := 2
## Rare and cooldown-gated: not every session sees him.
const DAILY_FIRE_CHANCE := 0.12
const COOLDOWN_DAYS := 5

## Every general-pool reply must contain at least one of these
## (case-insensitive) — the never-competent guarantee, asserted by tests.
const IDIOT_MARKERS := ["butt", "poop", "fart", "dumb", "stupid", "idiot",
	"pee", "boob", "ass", "doodoo", "wiener", "fuck", "dingle", "nostril",
	"underwear", "pants", "smell", "bonk"]


var _gs
## Without-replacement draw tracking (same pattern as SimUnhinged._draw):
## indices used this cycle; reshuffle at exhaustion.
var _used_general: Array = []
var _used_prank: Array = []

## Disaster state (persisted).
var fired := false            # disaster has fired at least once (unlock flag)
var last_fired_day := -1000
var burst_active := false
var burst_ends_at := 0.0
## Prank lines actually sent this burst (for the hearsay aftermath quotes).
var _burst_lines: Array = []


func _init(game_state) -> void:
	_gs = game_state


## Pseudo-unit dict for engine/UI use (phone-only entity, no world unit).
## Traits are pinned explicitly so the unhinged cuss-out path can never
## misfire on him — he's a lovable menace, not a villain.
func pseudo_unit() -> Dictionary:
	return {
		"id": UID,
		"faction": "gnomes",
		"name": NAME,
		"display_name": NAME,
		"town": "",
		"job": "prank caller",
		"alive": true,
		"gender": "m",
		"_leader_name": NAME,
		"_leader_pfp": "assface",
		"mind": {
			"name": NAME,
			"persona": "assface",
			"gov_role": "",
			"traits": {"unhinged": 0.0, "persona": "assface"},
		},
	}


func is_unlocked() -> bool:
	return fired


## Daily disaster roll. Rare, cooldown-gated, never while a burst is live.
func roll_fire(day: int) -> bool:
	if burst_active:
		return false
	if day - last_fired_day < COOLDOWN_DAYS:
		return false
	return randf() < DAILY_FIRE_CHANCE


## Begin the 30-second prank burst. Returns the lines to queue:
## {"player": [...], "leaders": {faction: [...]}, "quoted": [...]}.
## Draws without replacement from the PRANK pool.
func begin_burst(now: float) -> Dictionary:
	burst_active = true
	burst_ends_at = now + BURST_SECONDS
	last_fired_day = int(_gs.day_number) if _gs != null else 1
	_burst_lines = []
	var player_lines: Array = []
	for _i in range(PLAYER_BURST_COUNT):
		var line := draw_prank()
		player_lines.append(line)
		_burst_lines.append(line)
	var leader_lines := {}
	if _gs != null:
		var fl = _gs.get("faction_leaders")
		if fl != null:
			for l: Dictionary in fl.all_leaders():
				var f := String(l.get("faction", ""))
				if f == "" or f == String(_gs.player_faction):
					continue
				var pls: Array = []
				for _j in range(LEADER_PRANK_COUNT):
					var pl := draw_prank()
					pls.append(pl)
					_burst_lines.append(pl)
				leader_lines[f] = pls
	return {"player": player_lines, "leaders": leader_lines,
		"quoted": _burst_lines.duplicate()}


func end_burst() -> void:
	burst_active = false
	fired = true


## Draw one line without replacement (reshuffles at exhaustion).
func _draw(pool: Array, used: Array) -> String:
	if used.size() >= pool.size():
		used.clear()
	var avail: Array = []
	for i in range(pool.size()):
		if not used.has(i):
			avail.append(i)
	if avail.is_empty():
		return "..."
	var idx: int = avail[randi() % avail.size()]
	used.append(idx)
	return String(pool[idx])


func draw_general() -> String:
	return _draw(GENERAL, _used_general)


func draw_prank() -> String:
	return _draw(PRANK, _used_prank)


## --- Persona-locked responder -----------------------------------------------
## The full engine already ran (intent parsed, memories updated) — now
## interpret the topic through pure idiocy. Every reply references the
## player's topic and carries the I-DON'T-GIVE-A-FUCK charge.

## Intent -> default topic noun when no keyword is found in the text.
const INTENT_TOPICS := {
	"war_declare": "war", "war_threaten": "war", "war_bluff": "war",
	"war_how": "war", "war_surrender": "war",
	"economy_how": "gold", "tax_how": "taxes", "tax_complaint": "taxes",
	"trade_propose": "trading", "trade_haggle": "trading",
	"trade_accept": "trading", "trade_refuse": "trading",
	"tribute_offer": "tribute", "tribute_demand": "tribute",
	"tribute_refuse": "tribute",
	"alliance_propose": "alliances", "peace_offer": "peace",
	"diplomacy": "politics",
	"faction_info": "factions", "what_faction": "factions",
	"kingdom_ask": "the kingdom", "ruling_advice": "ruling",
	"food": "food", "weather": "weather", "weather_nice": "weather",
	"weather_complaint": "weather",
	"greeting": "saying hi", "how_are_you": "feelings",
	"farewell": "bye", "thanks": "thanks", "apology": "sorrys",
	"insult": "insults", "threat": "threats", "tease": "teasing",
	"joke": "jokes", "joke_request": "jokes", "joke_tell": "jokes",
	"flirt": "flirting", "love_declaration": "love",
	"question": "questions",
}

## Keyword -> topic noun, scanned in the player's raw text (priority order).
const TOPIC_KEYWORDS := [
	["war", "war"], ["battle", "war"], ["army", "the army"],
	["gold", "gold"], ["money", "money"], ["tax", "taxes"],
	["economy", "the economy"],
	["peace", "peace"], ["alliance", "alliances"],
	["trade", "trading"], ["tribute", "tribute"],
	["politics", "politics"], ["diplomac", "politics"],
	["kingdom", "the kingdom"], ["throne", "the throne"],
	["crown", "the crown"], ["ruler", "ruling"],
	["food", "food"], ["farm", "farming"], ["hungry", "hunger"],
	["weather", "weather"], ["rain", "rain"], ["snow", "snow"],
	["elf", "elves"], ["orc", "orcs"], ["ogre", "ogres"],
	["gnome", "gnomes"], ["human", "humans"],
	["skeleton", "skeletons"], ["undead", "the undead"], ["zombie", "zombies"],
	["dragon", "dragons"], ["monster", "monsters"],
	["poop", "poop"], ["butt", "butts"], ["fart", "farts"],
	["wife", "your wife"], ["husband", "your husband"],
	["god", "the gods"], ["priest", "priests"], ["church", "the church"],
	["prison", "prison"], ["jail", "jail"], ["crime", "crime"],
	["build", "building"], ["house", "houses"], ["wall", "walls"],
	["ship", "ships"], ["boat", "boats"], ["fish", "fish"],
]


## Find the topic: keyword scan first, then intent default, then "stuff".
func detect_topic(text: String, intent: String) -> String:
	var low := " " + text.to_lower() + " "
	for pair in TOPIC_KEYWORDS:
		if low.contains(" " + String(pair[0])) or low.contains(String(pair[0]) + " "):
			return String(pair[1])
	# Also catch the keyword glued to punctuation.
	for pair in TOPIC_KEYWORDS:
		if low.contains(String(pair[0])):
			return String(pair[1])
	if INTENT_TOPICS.has(intent):
		return String(INTENT_TOPICS[intent])
	return "stuff"


## Find a person/faction target for the FUCK [X]!!! pattern.
## Returns {"name": ..., "blows": ...}. Checks leader names first (so
## "what about Grak" -> FUCK GRAK!!!), then faction words, then "you".
func detect_target(text: String) -> Dictionary:
	var low := text.to_lower()
	if _gs != null:
		var fl = _gs.get("faction_leaders")
		if fl != null:
			for l: Dictionary in fl.all_leaders():
				var lname := String(l.get("name", ""))
				if lname != "" and low.contains(lname.to_lower().split(" ")[0]):
					return {"name": lname.to_upper(), "blows": "HE BLOWS"}
	for pair in [["elves", "THE ELVES"], ["elf", "THE ELVES"],
			["orcs", "THE ORCS"], ["orc", "THE ORCS"],
			["ogres", "THE OGRES"], ["ogre", "THE OGRES"],
			["gnomes", "THE GNOMES"], ["gnome", "THE GNOMES"],
			["humans", "THE HUMANS"], ["human", "THE HUMANS"],
			["undead", "THE UNDEAD"], ["skeletons", "THE SKELETONS"],
			["skeleton", "THE SKELETONS"], ["zombies", "THE ZOMBIES"]]:
		if low.contains(String(pair[0])):
			return {"name": String(pair[1]), "blows": "THEY BLOW"}
	if low.contains("you"):
		return {"name": "YOU", "blows": "YOU BLOW"}
	return {"name": "EVERYBODY", "blows": "THEY BLOW"}


## Persona-locked reply: full-engine intent in, pure idiocy out.
## `engine_result` is the dict from SimConversation.reply (intent read
## from it; the engine's competent TEXT is discarded — the lock holds).
func idiot_reply(engine_result: Dictionary, text: String,
		ruler_name: String) -> String:
	var intent := String(engine_result.get("intent", "unclear"))
	var topic := detect_topic(text, intent)
	var tgt := detect_target(text)
	var line := draw_general()
	line = line.replace("{ruler}", ruler_name)
	line = line.replace("{topic}", topic)
	line = line.replace("{target}", String(tgt.get("name", "EVERYBODY")))
	line = line.replace("{blows}", String(tgt.get("blows", "THEY BLOW")))
	return line


## --- save/load ---------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"fired": fired,
		"last_fired_day": last_fired_day,
		"burst_active": false,  # mid-burst saves resume as completed
		"used_general": _used_general.duplicate(),
		"used_prank": _used_prank.duplicate(),
	}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	fired = bool(data.get("fired", false))
	last_fired_day = int(data.get("last_fired_day", -1000))
	burst_active = false
	_used_general = (data.get("used_general", []) as Array).duplicate()
	_used_prank = (data.get("used_prank", []) as Array).duplicate()
	_burst_lines = []


## --- PRANK pool: 100 unique ALL-CAPS burst lines ------------------------------
## What Assface screams during the 30-second prank rampage. Faction +
## body-part combos + escalating absurdity. Crude-but-silly; ZERO IRL
## slurs anywhere (asserted by tests).
const PRANK := [
	"BOOBIES",
	"ORC ASS!!!",
	"ELF BUTT!!!",
	"GNOME DICK!!!!",
	"HUMAN BUTTS!!!",
	"SKELETON ASS!!!",
	"OGRE BOOBIES!!!",
	"FARTS!!!",
	"BUTTS BUTTS BUTTS!!!",
	"I PUT MY UNDERWEAR ON MY HEAD!!!",
	"ASS ORCS!!! ASS ORCS!!!",
	"ELF BUTT!!! ELF BUTT!!!",
	"POOP!!!",
	"MY FARTS SMELL LIKE VICTORY!!!",
	"GNOME BUTT!!! GNOME BUTT!!!",
	"WIENER!!!",
	"HUMAN DICK!!! HUMAN DICK!!!",
	"ORC BUTT!!! ORC BUTT!!!",
	"I LICKED A ROCK AND IT TASTED LIKE FEET!!!",
	"BOOBIES BOOBIES BOOBIES!!!",
	"SKELETON DICK!!!",
	"ELF ASS!!!",
	"MY PANTS ARE ON BACKWARDS AND I DON'T CARE!!!",
	"FART NOISES!!! *PBBBBBT*",
	"OGRE ASS!!! OGRE ASS!!!",
	"GNOME BOOBIES!!!",
	"HUMAN ASS!!!",
	"I ATE A BUG!!! IT WAS CRUNCHY!!!",
	"BUTT!!!",
	"ORC DICK!!! ORC DICK!!!",
	"ELF BOOBIES!!!",
	"MY TOENAILS SMELL LIKE CHEESE!!!",
	"SKELETON BUTT!!! SKELETON BUTT!!!",
	"POOP POOP POOP!!!",
	"GNOME ASS!!!",
	"I FARTED IN THE THRONE ROOM!!!",
	"HUMAN BOOBIES!!! HUMAN BOOBIES!!!",
	"OGRE BUTT!!!",
	"ELF DICK!!! ELF DICK!!!",
	"MY BELLY BUTTON HAS LINT AND I'M RICH!!!",
	"ASS!!!",
	"ORC BOOBIES!!! ORC BOOBIES!!!",
	"SKELETON BOOBIES!!!",
	"I DRANK MUD!!!",
	"GNOME FARTS!!! GNOME FARTS!!!",
	"HUMAN FARTS!!!",
	"ELF FARTS!!! ELF FARTS!!!",
	"MY ARMPITS SMELL LIKE ONIONS!!!",
	"BUTTS!!!",
	"OGRE DICK!!!",
	"ORC FARTS!!! ORC FARTS!!!",
	"SKELETON FARTS!!!",
	"I BIT MY OWN TONGUE AND CRIED!!!",
	"GNOME BUTTS!!! GNOME BUTTS!!!",
	"HUMAN BUTT!!!",
	"ELF BUTTS!!!",
	"MY SOCKS ARE WET AND I LIKE IT!!!",
	"POOPY!!!",
	"OGRE FARTS!!! OGRE FARTS!!!",
	"ORC BUTTS!!!",
	"SKELETON BUTTS!!! SKELETON BUTTS!!!",
	"I SNEEZED AND FARTED AT THE SAME TIME!!! LEGEND!!!",
	"GNOME DICK!!! GNOME DICK!!!",
	"HUMAN DICK!!!",
	"ELF ASS!!! ELF ASS!!!",
	"MY EARWAX TASTES LIKE NOTHING AND I'M MAD!!!",
	"DOODOO!!!",
	"OGRE BUTTS!!!",
	"ORC ASS!!! ORC ASS!!!",
	"SKELETON ASS!!! SKELETON ASS!!!",
	"I TRIED TO HIGH-FIVE MYSELF AND MISSED!!!",
	"GNOME ASS!!! GNOME ASS!!!",
	"HUMAN ASS!!! HUMAN ASS!!!",
	"ELF DICK!!!",
	"MY NOSE IS RUNNING AND I'M NOT CHASING IT!!!",
	"WIENER WIENER WIENER!!!",
	"OGRE ASS!!!",
	"ORC BOOBIES!!!",
	"SKELETON DICK!!! SKELETON DICK!!!",
	"I YELLED AT A CHICKEN AND IT YELLED BACK!!!",
	"GNOME BOOBIES!!! GNOME BOOBIES!!!",
	"HUMAN BOOBIES!!!",
	"ELF BOOBIES!!! ELF BOOBIES!!!",
	"MY BUTT ITCHES AND I'M TELLING EVERYONE!!!",
	"FARTS FARTS FARTS!!!",
	"OGRE BOOBIES!!! OGRE BOOBIES!!!",
	"ORC DICK!!!",
	"SKELETON BOOBIES!!! SKELETON BOOBIES!!!",
	"I'M THE KING OF POOP!!! BOW TO ME!!!",
	"GNOME FARTS!!!",
	"HUMAN FARTS!!! HUMAN FARTS!!!",
	"ELF FARTS!!!",
	"ASSFACE!!! ASSFACE!!! THAT'S ME!!! I'M ASSFACE!!!",
	"BOOBIES!!! DID I SAY BOOBIES!!! BOOBIES!!!",
	"ORC ASS!!! ELF BUTT!!! GNOME DICK!!! THE HOLY TRINITY!!!",
	"I'M CALLING FROM INSIDE YOUR PANTS!!!",
	"THIRTY SECONDS OF PURE GENIUS AND YOU'RE WELCOME!!!",
	"FARTED SO HARD MY UNDERWEAR QUIT!!!",
	"THE KING OF BUTTS HAS SPOKEN!!! THAT'S ME!!! I'M THE KING!!!",
	"POOP EMERGENCY!!! THIS IS NOT A DRILL!!!",
	"I LOVE BUTTS AND I'M NOT ASHAMED!!!",
]


## --- GENERAL pool: 100 unique idiot-voice reply templates ----------------------
## The persona-locked responder draws these (without replacement) and fills
## {ruler} {topic} {target} {blows}. EVERY line references the player's
## topic or target (never random), carries the I-DON'T-GIVE-A-FUCK charge,
## and contains an idiot marker (never competent). {target}/{blows} come
## from detect_target: "FUCK GRAK!!! HE BLOWS!!!" energy.
const GENERAL := [
	"I DON'T GIVE A FUCK ABOUT {topic}. AND FUCK {target}!!! {blows}!!! I saw {target} pick {topic} with a rusty spoon!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}, {ruler}. AND FUCK {target}!!! {blows}!!! {target} smells like butt and everybody knows it!!!",
	"{topic}?? {topic} is STUPID. AND FUCK {target}!!! {blows}!!! I once saw {target} fart during a speech and blame a dog!!!",
	"ohhh {topic}. listen {ruler}. {topic} is just butts all the way down. I checked. AND FUCK {target}!!! {blows}!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! {target} can kiss my ass!!! {blows}!!! I mean it!!! I bent over and everything!!!",
	"{topic}?? more like BORE-ic. AND FUCK {target}!!! {blows}!!! {target} wears underwear on {topic} day!!!",
	"fuck {topic}. fuck {target}. {blows}!!! I'm eating dirt now. dirt is better than {topic}.",
	"I DON'T GIVE A FUCK ABOUT {topic} AND NEITHER SHOULD YOU, {ruler}. AND FUCK {target}!!! {blows}!!! {target} peed in the soup!!!",
	"{topic}?? I know {topic}!!! {topic} is when your butt makes decisions!!! AND FUCK {target}!!! {blows}!!!",
	"listen. LISTEN. {topic} doesn't matter. BUTTS matter. AND FUCK {target}!!! {blows}!!! {target} has a butt for a face!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}. I give a fuck about FARTS. AND FUCK {target}!!! {blows}!!!",
	"{ruler} {ruler} {ruler}. {topic}?? who cares. AND FUCK {target}!!! {blows}!!! I saw {target} trip over {topic}!!!",
	"FUCK {target}!!! {blows}!!! also {topic} is dumb. I tried to eat {topic} once. tasted like feet.",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! NOT ONE FUCK!!! I checked my pockets!!! zero fucks!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}?? that's the thing with the butt, right?? AND FUCK {target}!!! {blows}!!! {target} IS a butt!!!",
	"you wanna talk {topic}?? FINE. {topic} smells. AND FUCK {target}!!! {blows}!!! {target} smells worse!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}, I DON'T GIVE A FUCK ABOUT {target}, I DON'T GIVE A FUCK ABOUT PANTS!!! {blows}!!!",
	"{topic} is for nerds, {ruler}. AND FUCK {target}!!! {blows}!!! {target} is the BIGGEST nerd!!! nerd butt!!!",
	"blah blah {topic}. AND FUCK {target}!!! {blows}!!! I drew a butt on {topic}!!! it's art now!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I'd rather lick a doorknob!!! AND FUCK {target}!!! {blows}!!! {target} licks doorknobs!!!",
	"{topic}?? {topic}?? {topic}?? saying it three times doesn't make it less dumb. AND FUCK {target}!!! {blows}!!!",
	"oh great, {topic}. my FAVORITE boring thing. AND FUCK {target}!!! {blows}!!! {target} collects belly-button lint!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}. my butt doesn't give a fuck about {topic}. AND FUCK {target}!!! {blows}!!!",
	"{ruler}, buddy, pal, {topic} is a TRAP. AND FUCK {target}!!! {blows}!!! {target} fell for it!!! idiot!!!",
	"FUCK {target}!!! {blows}!!! and while I'm at it, {topic} can go straight up my butt!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I once gave a fuck about {topic} and I lost it behind the couch!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}?? is that like a butt thing?? everything's a butt thing if you're brave. AND FUCK {target}!!! {blows}!!!",
	"seriously {ruler}, {topic}?? AND FUCK {target}!!! {blows}!!! {target} once farted so hard {topic} filed a complaint!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! ask my wiener!!! my wiener doesn't care either!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}. {topic}. {topic}. okay I'm bored now. AND FUCK {target}!!! {blows}!!! {target} is boring AND stupid!!!",
	"you know what I think about {topic}?? FARTS. I think about farts. AND FUCK {target}!!! {blows}!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I DON'T EVEN KNOW WHAT {topic} IS!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}?? {target} loves {topic}!!! which is exactly why {topic} is dumb!!! {blows}!!! butt!!!",
	"FUCK {target}!!! {blows}!!! {target} told me {topic} was cool and {target} is a LIAR and a butt!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}, {ruler}. I care about THREE things: butts, farts, and not {topic}. AND FUCK {target}!!! {blows}!!!",
	"{topic}?? I pooped on {topic} once. true story. AND FUCK {target}!!! {blows}!!! {target} watched!!!",
	"ohhh you're doing {topic} talk. cute. AND FUCK {target}!!! {blows}!!! {target} does {topic} talk in the mirror!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! my left butt cheek doesn't give a fuck about {topic}!!! AND FUCK {target}!!! {blows}!!!",
	"{ruler}!!! {topic}!!! {target}!!! I'm just saying words now!!! words are stupid!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}?? more like {topic} BUTT. AND FUCK {target}!!! {blows}!!! I renamed it. you're welcome.",
	"I DON'T GIVE A FUCK ABOUT {topic}. never have. never will. AND FUCK {target}!!! {blows}!!! {target} will too!!!",
	"wow. {topic}. incredible. AND FUCK {target}!!! {blows}!!! {target} thinks {topic} is a personality!!!",
	"{topic}?? I ate {topic} for breakfast. AND FUCK {target}!!! {blows}!!! {target} ate my breakfast!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I'm too busy being awesome at farts!!! AND FUCK {target}!!! {blows}!!!",
	"so anyway {topic}. AND FUCK {target}!!! {blows}!!! {target} has doodoo for brains!!! certified!!!",
	"{topic}?? {topic} can kiss the crack of my ass, {ruler}. AND FUCK {target}!!! {blows}!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I give negative fucks!!! I'm IN DEBT on fucks!!! AND FUCK {target}!!! {blows}!!!",
	"okay but have you considered: {topic} is dumb AND {target} blows?? {blows}!!! I considered it. it's true.",
	"{topic}?? I named my fart {topic}. AND FUCK {target}!!! {blows}!!! {target} named THEIR fart {topic} too!!! copycat!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! talk to my butt!!! my butt is in charge of {topic}!!! AND FUCK {target}!!! {blows}!!!",
	"hey {ruler}. {topic}. no. AND FUCK {target}!!! {blows}!!! {target} once got stuck in {topic}!!!",
	"{topic}?? that's what SHE said!!! AND FUCK {target}!!! {blows}!!! {target} says everything!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I'd unfuck with {topic} if I could!!! AND FUCK {target}!!! {blows}!!!",
	"so {topic}, huh?? big {topic} guy?? AND FUCK {target}!!! {blows}!!! {target} is a big {topic} guy and look how THAT turned out!!!",
	"{topic} is just {topic} until someone farts, {ruler}. then it's ART. AND FUCK {target}!!! {blows}!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! my goldfish doesn't give a fuck about {topic}!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}?? I shoved {topic} up my nose once. AND FUCK {target}!!! {blows}!!! {target} helped!!!",
	"listen {ruler}, {topic} is a scam. AND FUCK {target}!!! {blows}!!! {target} runs the scam!!! scam butt!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I'm boycotting {topic}!!! AND FUCK {target}!!! {blows}!!! boycott butt!!!",
	"{topic}?? never met her. AND FUCK {target}!!! {blows}!!! {target} met her and she said {target} blows!!!",
	"oh you want {topic} advice?? here's my advice: FART. AND FUCK {target}!!! {blows}!!! that's the whole advice!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! {topic} can eat my shorts!!! AND FUCK {target}!!! {blows}!!! {target} ate shorts!!!",
	"{topic}, {topic}, bo-bopic, banana-fana fo-fopic. AND FUCK {target}!!! {blows}!!! I'm a genius!!!",
	"you're really into {topic}, huh {ruler}?? that's embarrassing. AND FUCK {target}!!! {blows}!!! {target} is embarrassed FOR you!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I flushed my fucks down the toilet!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}?? I give it two butts down. AND FUCK {target}!!! {blows}!!! {target} gives it two butts UP and that's why {target} is wrong!!!",
	"new phone, who dis?? oh it's {ruler} talking about {topic}. AND FUCK {target}!!! {blows}!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I'm on the toilet right now!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}?? {topic}?? did {target} put you up to this?? AND FUCK {target}!!! {blows}!!! {target} puts EVERYONE up to {topic}!!!",
	"hard pass on {topic}, {ruler}. AND FUCK {target}!!! {blows}!!! {target} hard-passed on deodorant!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! my therapist says that's healthy!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}?? I wrote a song about {topic}. it goes: fart noises. AND FUCK {target}!!! {blows}!!! {target} cried!!!",
	"imagine caring about {topic}. couldn't be me. AND FUCK {target}!!! {blows}!!! {target} cares and look at {target}!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I DON'T GIVE A FUCK ABOUT GIVING A FUCK!!! AND FUCK {target}!!! {blows}!!!",
	"{topic}?? {topic} is when the butt does a think. AND FUCK {target}!!! {blows}!!! {target} thinks with {target}'s butt!!!",
	"cool {topic} story, {ruler}. anyway. AND FUCK {target}!!! {blows}!!! {target} tells worse stories!!! butt stories!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I sold all my fucks for beans!!! AND FUCK {target}!!! {blows}!!! {target} stole the beans!!!",
	"{topic}?? oh I LOVE {topic}!!! said no butt ever. AND FUCK {target}!!! {blows}!!! {target} said it!!!",
	"breaking news: {topic} still dumb. AND FUCK {target}!!! {blows}!!! {target} still blows!!! back to you, {ruler}!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I can't even SPELL {topic}!!! AND FUCK {target}!!! {blows}!!! {target} can't spell EITHER!!!",
	"{topic}?? that's a funny way to spell FART. AND FUCK {target}!!! {blows}!!! {target} spells it with two Ts!!! idiot!!!",
	"you + {topic} = boring. me + farts = LEGEND. AND FUCK {target}!!! {blows}!!! math!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! {topic} is cancelled!!! AND FUCK {target}!!! {blows}!!! I cancelled {target} too!!!",
	"{ruler} my man. {topic}?? really?? AND FUCK {target}!!! {blows}!!! {target} does {topic} on purpose!!!",
	"{topic}?? I give {topic} the big hairy butt award!!! AND FUCK {target}!!! {blows}!!! {target} won it last year!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! zero!!! zilch!!! NADA!!! AND FUCK {target}!!! {blows}!!! {target} gives MANY fucks!!! loser!!!",
	"so {topic} walks into a bar. the bar farts. the end. AND FUCK {target}!!! {blows}!!! {target} was the bar!!!",
	"{topic}?? I put {topic} in my butt and now it's ART, {ruler}. AND FUCK {target}!!! {blows}!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! my butt cheeks clap for farts, not {topic}!!! AND FUCK {target}!!! {blows}!!!",
	"alright {ruler}, real talk: {topic}?? fake. butts?? real. AND FUCK {target}!!! {blows}!!! {target}?? fake butt!!!",
	"{topic}?? {target} told me to say {topic} is cool. AND FUCK {target}!!! {blows}!!! {target} is a butt and {topic} is NOT cool!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I'm literally picking my nose right now!!! AND FUCK {target}!!! {blows}!!! {target} picks {target}'s nose with a SWORD!!!",
	"tl;dr on {topic}: dumb. AND FUCK {target}!!! {blows}!!! {target} didn't read it!!!",
	"{topic}?? I filed {topic} under B for BUTT. AND FUCK {target}!!! {blows}!!! {target} filed it under L for LOSER!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! {topic} more like SMELLopic!!! AND FUCK {target}!!! {blows}!!! gottem!!!",
	"hey {ruler} quick question: is {topic} a butt thing?? AND FUCK {target}!!! {blows}!!! {target} knows!!! ask {target}!!!",
	"{topic}?? hard no. AND FUCK {target}!!! {blows}!!! {target} said yes which proves {target} is a butt!!!",
	"I DON'T GIVE A FUCK ABOUT {topic}!!! I'm busy!!! busy doing butt stuff!!! AND FUCK {target}!!! {blows}!!!",
	"oh shit, {topic}!! anyway. AND FUCK {target}!!! {blows}!!! {target} shit {topic}!!! literally!!!",
	"{topic}?? I give {topic} one star. the star is a butt. AND FUCK {target}!!! {blows}!!! {target} gave five stars!!! idiot!!!",
]
