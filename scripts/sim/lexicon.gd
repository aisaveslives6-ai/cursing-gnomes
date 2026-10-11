## Cursing Gnomes — Living Lexicon.
##
## HTML fix79 parity restoration (Jeremy 2026-10-06 — this system WORKED in
## the original and regressed in the Godot port). NPCs learn the player's
## words, remember them across saves, USE them in conversation (the showoff
## moment: first time an NPC answers about a word they flaunt it), accept
## corrections, track the player's writing style, and spread words as daily
## gossip between NPCs. Backchannel chatter drops learned words too.
##
## Ported from HTML fix79: LexiconHook / LexiconMatch / LexiconWordReply /
## LexiconDailyTick / LexiconSave / LexiconLoad / bcLexiconWord (and the
## _LX_VOICE faction pools, which carry Jeremy's own game writing).
##
## Word entry: {
##   "meaning": "two, dudes, touch",  # keyword list, comma-joined
##   "phrase": "when two dudes touch dicks",  # natural phrase (may be "")
##   "stems": ["zorp", "two", ...],
##   "taught_by": "u12", "teacher_name": "Knackers",
##   "day": 41, "uses": 0, "spread": 0,
##   "known_by": ["u12"], "shown_by": [], "seed": false,
## }
class_name SimLexicon
extends RefCounted


const MAX_WORDS := 200
const MAX_FACTS := 30


## ---------------------------------------------------------------------------
## State (mirrors HTML _lxEmpty / LexiconSave shape)
## ---------------------------------------------------------------------------
var words := {}
var facts := {}
var pending := {}
var style := {}
var last_taught := {}
var last_spread_day := 0
var tick_day := 1

var _gs = null
var _day_connected := false
var _rng := RandomNumberGenerator.new()


func _init(gs = null) -> void:
	_rng.randomize()
	_apply_seed_baseline()
	if gs != null:
		bind(gs)


## Attach the game state: day_changed drives the gossip spread, and the
## spread DM is delivered through the phone. Idempotent.
func bind(gs) -> void:
	_gs = gs
	if _gs == null:
		return
	var bus = _gs.get("bus")
	if bus != null and not _day_connected:
		bus.day_changed.connect(_on_day)
		_day_connected = true


func _on_day(_day: int, _is_night: bool) -> void:
	daily_tick()


## The NPC-side key for a unit (matches phone.gd's "u%d" from_key).
static func npc_key_for(unit: Dictionary) -> String:
	return "u%d" % int(unit.get("id", 0))


## Faction voice key for a unit ("gnomes" -> "gnome", falls back to gnome).
static func voice_faction(unit: Dictionary) -> String:
	var f := String(unit.get("faction", "gnome")).to_lower()
	match f:
		"gnomes", "gnome":
			return "gnome"
		"humans", "human":
			return "human"
		"elves", "elf":
			return "elf"
		"ogres", "ogre":
			return "ogre"
		"undead":
			return "undead"
	return "gnome"


## ---------------------------------------------------------------------------
## Faction voice pools (HTML _LX_VOICE — Jeremy's game writing, restored).
## {word} = the word, {kw} = meaning/phrase, {name} = the player's name,
## {k}/{v} = learned fact key/value, {teacher} = who taught the word.
## ---------------------------------------------------------------------------
const VOICE := {
	"gnome": {
		"ask": [
			"The hell is a '{word}'?",
			"Oi — what's a '{word}' supposed to be?",
			"'{word}'? Never heard of it. Spill it, {name}.",
		],
		"ack": [
			"'{word}' — noted. Means {kw}. I'll use it. Probably wrong.",
			"Right, '{word}' = {kw}. Got it. I'll pretend I always knew.",
		],
		"fact": [
			"Noted: your {k} is {v}. I'll try to remember. Probably won't.",
			"Your {k} is {v}, huh? Filed under 'shit {name} cares about'.",
		],
		"factRef": [
			"So how's the {k} situation, {name}? You told me it was {v}. Still true, or were you lying?",
			"Hey {name} — your {k}, still {v}? Just checking my notes.",
		],
		"word": [
			"Yeah yeah, '{word}' — that's {kw} shit, right? You're corrupting my vocabulary, {name}.",
			"'{word}'! As in {kw}. Look at me, learning. Somebody mark the damn calendar.",
		],
		"wordAgain": [
			"'{word}'? {kw}, like I said. My memory's fine — it's your manners that worry me.",
			"Still '{word}' — {kw}. I told you already. The scribe wrote it down.",
			"'{word}' = {kw}. Again. Want it tattooed somewhere?",
		],
		"correct": [
			"Got it — '{word}' actually means {kw}. My mistake. Won't happen again. (It will.)",
			"Right, '{word}' = {kw}, not what I said before. Updating the ol' brainbox.",
		],
		"cancel": [
			"Fine, forget I asked. My curiosity died.",
			"Suit yourself. The mystery of '{word}' dies with you.",
		],
		"gossip": [
			"{teacher} won't stop saying '{word}'. What the hell does it mean?",
			"Heard {teacher} yapping about '{word}' again. You know what that is?",
		],
	},
	"human": {
		"ask": [
			"Sorry — what exactly is a '{word}'?",
			"I don't believe I know the word '{word}'. Care to define it?",
			"'{word}'. Unfamiliar term. Enlighten me, {name}.",
		],
		"ack": [
			"'{word}' — understood. It means {kw}. I'll keep that in mind.",
			"Noted: '{word}' means {kw}. Adding it to the ledger.",
		],
		"fact": [
			"Noted: your {k} is {v}. Filed away.",
			"Your {k} is {v}. Duly recorded, {name}.",
		],
		"factRef": [
			"How's the {k} situation, {name}? Last I heard it was {v}.",
			"Quick check, {name} — your {k}. Still {v}?",
		],
		"word": [
			"Speaking of '{word}' — by which I mean {kw} — how's that working out for you?",
			"Ah yes, '{word}'. {kw}, if I recall correctly. Useful word.",
		],
		"wordAgain": [
			"'{word}': {kw}. As I mentioned before.",
			"Still {kw} — '{word}', per my notes.",
			"'{word}' means {kw}. The ledger hasn't changed.",
		],
		"correct": [
			"Understood — '{word}' actually means {kw}. Correcting my notes.",
			"My error. '{word}' = {kw}. I've amended the record.",
		],
		"cancel": [
			"Very well. The question is withdrawn.",
			"As you wish. '{word}' remains a mystery.",
		],
		"gossip": [
			"Word is {teacher} keeps going on about '{word}'. Any idea what that means?",
			"Between you and me — {teacher} won't stop mentioning '{word}'. Thoughts?",
		],
	},
	"elf": {
		"ask": [
			"Darling, what on earth is a '{word}'? ✨",
			"A '{word}'? How intriguing! Do tell me what it means, sweetling. 🌸",
		],
		"ack": [
			"'{word}' — how lovely! It means {kw}, darling. I'll weave it into my vocabulary. ✨",
			"Oh! '{word}' means {kw}. Exquisite. It's mine now. 🌿",
		],
		"fact": [
			"Noted, darling — your {k} is {v}. How precious. ✨",
			"Your {k} is {v}? I'll press it like a flower in my diary. 🌸",
		],
		"factRef": [
			"Tell me, darling — how is your {k}? You once said it was {v}. ✨",
			"Sweetling, is your {k} still {v}? The dryads were asking. 🌿",
		],
		"word": [
			"Ah, '{word}'... {kw}, like a poem folded into a single word. ✨",
			"'{word}' — {kw}! It dances on the tongue, doesn't it, {name}? 🌸",
		],
		"wordAgain": [
			"'{word}' is still {kw}, darling. ✨",
			"Like I told you, sweetling — '{word}' means {kw}. 🌸",
			"'{word}'? {kw}. My garden remembers. 🌿",
		],
		"correct": [
			"Oh! '{word}' truly means {kw}. Forgive my earlier fumble, darling. ✨",
			"A correction! '{word}' = {kw}. My mind is a garden — freshly weeded. 🌿",
		],
		"cancel": [
			"As you wish, mysterious one. The '{word}' stays secret. ✨",
			"Very well — some words are shy. I understand. 🌸",
		],
		"gossip": [
			"Darling, {teacher} simply will NOT stop saying '{word}'. Do enlighten me? ✨",
			"The court whispers that {teacher} adores the word '{word}'. What does it MEAN, sweetling? 🌸",
		],
	},
	"ogre": {
		"ask": [
			"'{word}'?! ME NOT KNOW '{word}'! YOU TEACH ME!",
			"WHAT '{word}'?! ME CONFUSE! EXPLAIN, {name}!",
		],
		"ack": [
			"ME LEARN '{word}'! IT MEAN {kw}! ME SMART NOW!",
			"'{word}' = {kw}! ME REMEMBER! ME BRAIN BIG TODAY!",
		],
		"fact": [
			"ME REMEMBER! YOUR {k} IS {v}! ME BRAIN BIG!",
			"YOUR {k} IS {v}! ME WRITE ON ROCK SO ME NOT FORGET!",
		],
		"factRef": [
			"{name}! HOW YOUR {k}?! YOU SAY IT {v}! STILL?!",
			"HEY! YOUR {k}! STILL {v}?! ME CHECKING!",
		],
		"word": [
			"ME LIKE '{word}'! IT MEAN {kw}! ME SAY IT LOUD!",
			"'{word}'! {kw}! ME USE WORD! ME FANCY NOW!",
		],
		"wordAgain": [
			"'{word}' MEAN {kw}! ME TOLD YOU ALREADY!",
			"STILL {kw}! '{word}' NOT CHANGE!",
			"ME SAID: '{word}' = {kw}! ME REMEMBER GOOD!",
		],
		"correct": [
			"OH! '{word}' MEAN {kw}, NOT OLD THING! ME FIX BRAIN!",
			"ME WRONG BEFORE! '{word}' = {kw}! ME SORRY!",
		],
		"cancel": [
			"OK! ME FORGET! '{word}' GONE! POOF!",
			"FINE! ME NOT CURIOUS ANYMORE! (me curious.)",
		],
		"gossip": [
			"{teacher} SAY '{word}' LOT! ME NOT KNOW! YOU KNOW?",
			"ME HEAR {teacher} SAY '{word}'! WHAT IT MEAN?! ME CURIOUS!",
		],
	},
	"undead": {
		"ask": [
			"'{word}'? THE GRAVE WHISPERS NOTHING OF '{word}'. ENLIGHTEN ME, {name}.",
			"MY ROTTED BRAIN KNOWS NOT '{word}'. SPEAK, MORTAL!",
		],
		"ack": [
			"'{word}'... YES. IT MEANS {kw}. ETCHED INTO MY TOMBSTONE.",
			"'{word}' = {kw}. THE DEAD REMEMBER. ALWAYS.",
		],
		"fact": [
			"NOTED IN THE BOOK OF THE DEAD: YOUR {k} IS {v}.",
			"YOUR {k} IS {v}. EVEN IN DEATH, I REMEMBER.",
		],
		"factRef": [
			"{name}... YOUR {k}. STILL {v}? THE GRAVE IS PATIENT.",
			"TELL ME, {name} — YOUR {k}. IS IT STILL {v}?",
		],
		"word": [
			"'{word}'! IT MEANS {kw}! I SHALL MOAN IT FOREVER!",
			"'{word}'! {kw}! A FINE WORD FOR THE DAMNED!",
		],
		"correct": [
			"AH! '{word}' MEANS {kw}, NOT WHAT I THOUGHT. DEATH TEACHES.",
			"I WAS WRONG! '{word}' = {kw}! THE WORMS LIED TO ME!",
		],
		"cancel": [
			"FINE. '{word}' RETURNS TO THE VOID. FORGOTTEN.",
			"VERY WELL. I RELEASE '{word}' BACK TO OBLIVION.",
		],
		"gossip": [
			"{teacher} KEEPS MOANING '{word}'... WHAT DARK MEANING HIDES THERE?",
			"I HEARD {teacher} WHISPER '{word}' FROM THE CRYPT. EXPLAIN!",
		],
	},
}


## Baseline slang/insult seeds (HTML _LX_SEED27). Never pruned, never
## trigger "what's a X?", and player-taught meanings always win over them.
const SEEDS := [
	["gonna", "going to"], ["wanna", "want to"], ["gotta", "got to"],
	["gimme", "give me"], ["lemme", "let me"], ["dunno", "do not know"],
	["aint", "is not"], ["kinda", "kind of"], ["sorta", "sort of"],
	["gotcha", "got you"], ["whatcha", "what are you"],
	["howdy", "hello"], ["hiya", "hello"], ["okay", "all right"],
	["thanks", "thank you"], ["thanx", "thanks"],
	["pls", "please"], ["plz", "please"], ["sorry", "sorry"],
	["yeah", "yes"], ["yep", "yes"], ["nope", "no"], ["maybe", "perhaps"],
	["later", "goodbye"], ["cool", "good"], ["awesome", "great"],
	["nice", "pleasant"], ["great", "very good"], ["fine", "acceptable"],
	["sure", "certainly"], ["good", "good"], ["hello", "hello"],
	["buddy", "friend"], ["dude", "fellow"], ["mate", "friend"],
	["homie", "close friend"], ["bruh", "bro"],
	["lmao", "laughing hard"], ["rofl", "laughing very hard"],
	["dang", "darn"], ["darn", "darn"], ["heck", "heck"],
	["shoot", "darn"], ["fudge", "darn"],
	["yikes", "yikes"], ["oops", "oops"],
	["cuz", "because"], ["cause", "because"],
	["pretty", "quite"], ["very", "very"],
	["assface", "idiot, insult"], ["dumbass", "idiot, insult"],
	["shithead", "idiot, insult"], ["dipshit", "idiot, insult"],
	["jackass", "fool, insult"], ["moron", "idiot"],
	["bitch", "insult"], ["bastard", "insult"],
	["asshole", "jerk, insult"], ["dickhead", "jerk, insult"],
	["fuckface", "insult"], ["shitface", "insult"],
	["butthead", "fool, insult"], ["numbskull", "idiot"],
	["bonehead", "idiot"], ["blockhead", "idiot"],
	["twat", "insult"], ["prick", "jerk, insult"],
	["douche", "jerk, insult"], ["douchebag", "jerk, insult"],
	["sucka", "fool"], ["loser", "failure, insult"],
	["weirdo", "strange person"], ["creep", "unsettling person"],
	["jerk", "rude person"], ["jerkoff", "jerk, insult"],
	["pissant", "insignificant person, insult"], ["turd", "insult"],
	["fartface", "silly insult"], ["poophead", "silly insult"],
	["stupidfucker", "idiot, insult"], ["shitbrick", "insult"],
]


## Closed-class scaffolding dropped from player definitions (HTML _LX_DEFSKIP).
const DEFSKIP := {
	"a": 1, "an": 1, "the": 1, "this": 1, "that": 1, "these": 1, "those": 1,
	"i": 1, "me": 1, "my": 1, "mine": 1, "myself": 1, "we": 1, "us": 1,
	"our": 1, "ours": 1, "ourselves": 1, "you": 1, "your": 1, "yours": 1,
	"yourself": 1, "yourselves": 1, "he": 1, "him": 1, "his": 1,
	"himself": 1, "she": 1, "her": 1, "hers": 1, "herself": 1, "it": 1,
	"its": 1, "itself": 1, "they": 1, "them": 1, "their": 1, "theirs": 1,
	"themselves": 1, "what": 1, "which": 1, "who": 1, "whom": 1,
	"am": 1, "is": 1, "are": 1, "was": 1, "were": 1, "be": 1, "been": 1,
	"being": 1, "have": 1, "has": 1, "had": 1, "having": 1, "do": 1,
	"does": 1, "did": 1, "doing": 1, "will": 1, "would": 1, "shall": 1,
	"should": 1, "may": 1, "might": 1, "must": 1, "can": 1, "could": 1,
	"of": 1, "in": 1, "on": 1, "at": 1, "to": 1, "for": 1, "with": 1,
	"by": 1, "from": 1, "as": 1, "and": 1, "or": 1, "but": 1, "if": 1,
	"then": 1, "than": 1, "so": 1, "such": 1, "no": 1, "not": 1,
	"only": 1, "own": 1, "same": 1, "too": 1, "very": 1, "just": 1,
	"about": 1, "into": 1, "over": 1, "after": 1, "before": 1,
	"between": 1, "out": 1, "up": 1, "down": 1, "off": 1, "again": 1,
	"once": 1, "here": 1, "there": 1, "when": 1, "where": 1, "why": 1,
	"how": 1, "all": 1, "any": 1, "both": 1, "each": 1, "few": 1,
	"more": 1, "most": 1, "other": 1, "some": 1, "like": 1, "s": 1,
	"means": 1, "mean": 1, "meaning": 1, "called": 1, "word": 1,
}


## Words that are never "teachable unknowns" (common English + game vocab).
const STOP := {
	"i": 1, "me": 1, "my": 1, "myself": 1, "we": 1, "our": 1, "ours": 1,
	"ourselves": 1, "you": 1, "your": 1, "yours": 1, "yourself": 1,
	"yourselves": 1, "he": 1, "him": 1, "his": 1, "himself": 1, "she": 1,
	"her": 1, "hers": 1, "herself": 1, "it": 1, "its": 1, "itself": 1,
	"they": 1, "them": 1, "their": 1, "theirs": 1, "themselves": 1,
	"what": 1, "which": 1, "who": 1, "whom": 1, "whose": 1, "this": 1,
	"that": 1, "these": 1, "those": 1, "am": 1, "is": 1, "are": 1,
	"was": 1, "were": 1, "be": 1, "been": 1, "being": 1, "have": 1,
	"has": 1, "had": 1, "having": 1, "do": 1, "does": 1, "did": 1,
	"doing": 1, "will": 1, "would": 1, "shall": 1, "should": 1, "may": 1,
	"might": 1, "must": 1, "can": 1, "could": 1, "ought": 1, "need": 1,
	"dare": 1, "a": 1, "an": 1, "the": 1, "and": 1, "but": 1, "if": 1,
	"or": 1, "because": 1, "as": 1, "until": 1, "while": 1, "of": 1,
	"at": 1, "by": 1, "for": 1, "with": 1, "about": 1, "against": 1,
	"between": 1, "into": 1, "through": 1, "during": 1, "before": 1,
	"after": 1, "above": 1, "below": 1, "to": 1, "from": 1, "up": 1,
	"down": 1, "in": 1, "out": 1, "on": 1, "off": 1, "over": 1,
	"under": 1, "again": 1, "further": 1, "then": 1, "once": 1,
	"here": 1, "there": 1, "when": 1, "where": 1, "why": 1, "how": 1,
	"all": 1, "any": 1, "both": 1, "each": 1, "few": 1, "more": 1,
	"most": 1, "other": 1, "some": 1, "such": 1, "no": 1, "nor": 1,
	"not": 1, "only": 1, "own": 1, "same": 1, "so": 1, "than": 1,
	"too": 1, "very": 1, "just": 1, "don": 1, "now": 1, "hello": 1,
	"hi": 1, "hey": 1, "goodbye": 1, "bye": 1, "yes": 1, "yeah": 1,
	"yep": 1, "yup": 1, "nope": 1, "nah": 1, "please": 1, "thanks": 1,
	"thank": 1, "sorry": 1, "okay": 1, "ok": 1, "sure": 1, "well": 1,
	"right": 1, "good": 1, "great": 1, "fine": 1, "nice": 1, "cool": 1,
	"awesome": 1, "pretty": 1, "really": 1, "like": 1, "love": 1,
	"hate": 1, "want": 1, "know": 1, "think": 1, "tell": 1, "say": 1,
	"said": 1, "says": 1, "ask": 1, "asked": 1, "mean": 1, "means": 1,
	"meant": 1, "call": 1, "called": 1, "name": 1, "named": 1, "word": 1,
	"words": 1, "gold": 1, "wood": 1, "food": 1, "stone": 1, "oil": 1,
	"town": 1, "towns": 1, "city": 1, "village": 1, "house": 1,
	"farm": 1, "shop": 1, "war": 1, "peace": 1, "attack": 1, "defend": 1,
	"army": 1, "soldier": 1, "soldiers": 1, "battle": 1, "fight": 1,
	"build": 1, "building": 1, "work": 1, "worker": 1, "job": 1,
	"king": 1, "queen": 1, "ruler": 1, "lord": 1, "mayor": 1, "gnome": 1,
	"gnomes": 1, "human": 1, "humans": 1, "elf": 1, "elves": 1,
	"ogre": 1, "ogres": 1, "undead": 1, "day": 1, "night": 1, "today": 1,
	"tomorrow": 1, "yesterday": 1, "time": 1, "year": 1, "season": 1,
	"weather": 1, "rain": 1, "snow": 1, "tax": 1, "taxes": 1, "trade": 1,
	"treaty": 1, "ally": 1, "enemy": 1, "friend": 1, "friends": 1,
	"family": 1, "wife": 1, "husband": 1, "son": 1, "daughter": 1,
	"mother": 1, "father": 1, "man": 1, "woman": 1, "men": 1, "women": 1,
	"person": 1, "people": 1, "thing": 1, "things": 1, "stuff": 1,
	"something": 1, "nothing": 1, "everything": 1, "anything": 1,
	"go": 1, "going": 1, "come": 1, "coming": 1, "get": 1, "got": 1,
	"make": 1, "made": 1, "take": 1, "took": 1, "give": 1, "gave": 1,
	"see": 1, "seen": 1, "saw": 1, "look": 1, "looking": 1, "watch": 1,
	"hear": 1, "heard": 1, "feel": 1, "seem": 1, "become": 1, "help": 1,
	"stop": 1, "start": 1, "keep": 1, "let": 1, "put": 1, "set": 1,
	"turn": 1, "move": 1, "run": 1, "walk": 1, "kill": 1, "die": 1,
	"dead": 1, "live": 1, "alive": 1, "born": 1, "eat": 1, "drink": 1,
	"sleep": 1, "wake": 1, "new": 1, "old": 1, "big": 1, "small": 1,
	"little": 1, "large": 1, "long": 1, "short": 1, "high": 1, "low": 1,
	"first": 1, "last": 1, "next": 1, "another": 1, "many": 1, "much": 1,
	"several": 1, "every": 1, "one": 1, "two": 1, "three": 1, "four": 1,
	"five": 1, "never": 1, "ever": 1, "always": 1, "often": 1,
	"sometimes": 1, "usually": 1, "soon": 1, "later": 1, "ago": 1,
	"still": 1, "already": 1, "yet": 1, "even": 1, "also": 1,
	"however": 1, "therefore": 1, "though": 1, "although": 1,
	"unless": 1, "whatever": 1, "whenever": 1, "wherever": 1,
	"whoever": 1, "s": 1, "t": 1, "d": 1, "ll": 1, "re": 1, "ve": 1,
	"m": 1
}


## Swear words for style tracking (HTML _LX_SWEARMAP, abbreviated).
const SWEAR := {
	"fuck": 1, "fucking": 1, "fucked": 1, "fucker": 1, "fucks": 1,
	"shit": 1, "shitty": 1, "shitting": 1,
	"damn": 1, "dammit": 1, "goddamn": 1,
	"ass": 1, "asses": 1, "bitch": 1, "bitches": 1, "bitching": 1,
	"hell": 1, "crap": 1, "crappy": 1, "piss": 1, "pissed": 1,
	"pissing": 1, "dick": 1, "dicks": 1, "cock": 1, "cocks": 1,
	"cunt": 1, "bastard": 1, "bastards": 1, "whore": 1, "slut": 1,
	"motherfucker": 1, "fuckface": 1, "shithead": 1, "dumbass": 1,
	"asshole": 1, "jackass": 1, "douche": 1, "douchebag": 1,
	"prick": 1, "twat": 1, "bollocks": 1, "bugger": 1, "wanker": 1,
}


## ---------------------------------------------------------------------------
## Small helpers
## ---------------------------------------------------------------------------
static func _rx_search(pattern: String, text: String) -> RegExMatch:
	var rx := RegEx.new()
	if rx.compile(pattern) != OK:
		return null
	return rx.search(text)


static func _rx_sub(pattern: String, text: String, repl: String) -> String:
	var rx := RegEx.new()
	if rx.compile(pattern) != OK:
		return text
	return rx.sub(text, repl, true)


## Lowercase, apostrophes -> spaces, collapsed whitespace (HTML _lxNorm).
static func _lx_norm(text: String) -> String:
	var t := text.to_lower().replace("'", " ").replace("’", " ")
	t = _rx_sub("\\s+", t.strip_edges(), " ")
	return t


## Known-word gate (HTML _lxSalientUnknown's dictionary cascade).
## The original never asked "what's a X?" for words in: the Common Tongue
## seed map (slang/swears/anatomy), the full English dictionary (wordfreq,
## Rob Speer, CC BY-SA 4.0 — credited in-game), Urban Dictionary slang,
## or Wikipedia titles. The Godot port dropped this whole cascade, so NPCs
## asked to be taught ordinary words like "butt". Restored 2026-10-06:
## all lists merged + deduplicated into assets/data/lexicon_known.txt
## (447,909 words), loaded once, lazily, into a Dictionary.
## (Retired 2026-10-06: the .txt never packed into web exports; the list now
## ships embedded in LexiconKnownData. The file remains in the repo as the
## regeneration source.)
const KNOWN_WORDS_PATH := "res://assets/data/lexicon_known.txt"
static var _known_words: Dictionary = {}
static var _known_loaded := false


static func _ensure_known_words() -> void:
	if _known_loaded:
		return
	_known_loaded = true
	# Jeremy 2026-10-06: the word list used to live in
	# assets/data/lexicon_known.txt, but Godot's web exporter does not pack
	# plain .txt data files into the pck — on-device, is_known_word()
	# failed for every word, so NPCs asked to be taught ordinary English
	# ("intended", ...). The list is now embedded as a compressed const in
	# LexiconKnownData, which always ships with the code.
	var raw := LexiconKnownData.packed_bytes()
	if raw.is_empty():
		return
	for w in raw.get_string_from_utf8().split("\n", false):
		_known_words[w] = true


## True if the word was known to the original game without being taught
## (HTML _lxSalientUnknown gates: stop/common maps, CT seedmap, English
## dictionary, urban slang, wiki titles). Learned words are checked by the
## caller via stems.
static func is_known_word(w: String) -> bool:
	if STOP.has(w):
		return true
	_ensure_known_words()
	return _known_words.has(w)


static func known_word_count() -> int:
	_ensure_known_words()
	return _known_words.size()


## Alphanumeric word tokens, lowercased (HTML _lxWords).
static func _words_of(text: String) -> Array:
	var t := _rx_sub("[^a-z0-9]+", text.to_lower(), " ")
	return t.split(" ", false)


## Suffix stripper (HTML _lxStem, verbatim logic).
static func stem(w: String) -> String:
	var stripped := false
	if w.length() > 4 and w.ends_with("ing"):
		w = w.substr(0, w.length() - 3)
		stripped = true
	elif w.length() > 4 and w.ends_with("ed"):
		w = w.substr(0, w.length() - 2)
		stripped = true
	elif w.length() > 4 and w.ends_with("es"):
		w = w.substr(0, w.length() - 2)
		stripped = true
	elif w.length() > 3 and w.ends_with("s"):
		w = w.substr(0, w.length() - 1)
		stripped = true
	elif w.length() > 3 and w.ends_with("e"):
		w = w.substr(0, w.length() - 1)
		stripped = true
	if stripped and w.length() > 3:
		if _rx_search("([bcdfghjklmnpqrstvwxz])\\1$", w) != null:
			w = w.substr(0, w.length() - 1)
	return w


## "it means X" -> X ; "X means Y" -> Y ; "it's Y" -> Y (HTML _lxDefExtract).
func def_extract(text: String) -> String:
	var t := _lx_norm(text)
	var m: RegExMatch
	m = _rx_search("^it means (.+)$", t)
	if m != null:
		return m.get_string(1)
	m = _rx_search("^that means (.+)$", t)
	if m != null:
		return m.get_string(1)
	m = _rx_search("^this means (.+)$", t)
	if m != null:
		return m.get_string(1)
	m = _rx_search("^it s (.+)$", t)
	if m != null:
		return m.get_string(1)
	m = _rx_search("^it is (.+)$", t)
	if m != null:
		return m.get_string(1)
	m = _rx_search("^means (.+)$", t)
	if m != null:
		return m.get_string(1)
	m = _rx_search("^(.+?) means (.+)$", t)
	if m != null:
		return m.get_string(2)
	return t


## Content keywords from a definition, framing stripped (HTML _lxDefKeywords).
func def_keywords(text: String, max_n: int = 5) -> Array:
	var out: Array = []
	var seen := {}
	for w in _words_of(def_extract(text)):
		var sw := String(w)
		if sw.length() < 3:
			continue
		if sw.is_valid_int():
			continue
		if DEFSKIP.has(sw):
			continue
		var st := stem(sw)
		if seen.has(st):
			continue
		seen[st] = true
		out.append(sw)
		if out.size() >= max_n:
			break
	return out


## The natural definition phrase, trimmed to 120 chars (HTML CANDIDATE28b).
func _clean_phrase(text: String) -> String:
	var t := def_extract(text)
	t = _rx_sub("\\s+", t.strip_edges(), " ")
	t = _rx_sub("[.!,?;:…]+$", t, "")
	return t.left(120)


func _set_phrase(word: String, phrase: String) -> void:
	if words.has(word) and phrase.length() >= 2:
		(words[word] as Dictionary)["phrase"] = phrase


## Fill {tokens} in a voice template (HTML _lxFill).
static func _fill(tpl: String, map: Dictionary) -> String:
	var out := tpl
	for k in map:
		out = out.replace("{" + String(k) + "}", String(map[k]))
	return out


## Pick a random line from a faction voice pool (HTML _lxSay).
func _say(faction: String, key: String) -> String:
	var vf: String = faction if VOICE.has(faction) else "gnome"
	var pool: Array = (VOICE[vf] as Dictionary).get(key, [])
	if pool.is_empty():
		pool = (VOICE["gnome"] as Dictionary).get(key, ["{word}?"])
	return String(pool[_rng.randi_range(0, pool.size() - 1)])


func _display_meaning(e: Dictionary) -> String:
	var ph := String(e.get("phrase", ""))
	if ph != "":
		return ph
	return String(e.get("meaning", "something mysterious"))


## ---------------------------------------------------------------------------
## Learning
## ---------------------------------------------------------------------------
func _apply_seed_baseline() -> void:
	for pair in SEEDS:
		var w := String(pair[0])
		if words.has(w):
			continue  # player-taught meanings always win
		words[w] = {
			"meaning": String(pair[1]),
			"phrase": "",
			"stems": [stem(w)],
			"taught_by": "everyone",
			"teacher_name": "everyone",
			"day": 0, "uses": 0, "spread": 999,
			"known_by": ["*"], "shown_by": [],
			"seed": true,
		}


## Store a word (HTML _lxLearnWord). Prunes the least-used non-seed word at
## MAX_WORDS; seeds are never pruned.
func learn_word(word: String, keywords: Array, npc_key: String, day: int,
		teacher_name: String = "") -> Dictionary:
	word = word.to_lower().strip_edges()
	var stems: Array = [stem(word)]
	for k in keywords:
		var ks := stem(String(k).to_lower())
		if not stems.has(ks):
			stems.append(ks)
	if not words.has(word):
		var count := 0
		for _k in words:
			count += 1
		if count >= MAX_WORDS:
			var worst := ""
			var worst_u := 1e18
			var worst_d := 1e18
			for k2 in words:
				var e: Dictionary = words[k2]
				if bool(e.get("seed", false)):
					continue
				var eu := float(e.get("uses", 0))
				var ed := float(e.get("day", 0))
				if eu < worst_u or (eu == worst_u and ed < worst_d):
					worst = String(k2)
					worst_u = eu
					worst_d = ed
			if worst != "":
				words.erase(worst)
	var kw: Array = []
	for k in keywords:
		kw.append(String(k).to_lower())
	words[word] = {
		"meaning": ", ".join(kw),
		"phrase": "",
		"stems": stems,
		"taught_by": npc_key,
		"teacher_name": teacher_name,
		"day": day, "uses": 0, "spread": 0,
		"known_by": [npc_key], "shown_by": [],
		"seed": false,
	}
	last_taught[npc_key] = word
	return words[word]


## ---------------------------------------------------------------------------
## Detection
## ---------------------------------------------------------------------------
## Most salient unknown content word (HTML _lxSalientUnknown): longest word
## that isn't a stopword, isn't numeric, isn't known to the original game's
## dictionary cascade (English/urban/wiki/CT seeds — so NPCs never ask to
## be taught ordinary words like "butt"), and isn't an already-learned stem.
func salient_unknown(text: String) -> String:
	var learned := {}
	for wk in words:
		var e: Dictionary = words[wk]
		learned[stem(String(wk))] = true
		for s in e.get("stems", []):
			learned[String(s)] = true
	var best := ""
	for w in _words_of(text):
		var sw := String(w)
		if sw.length() <= 3:
			continue
		if sw.is_valid_int():
			continue
		if is_known_word(sw):
			continue
		if learned.has(stem(sw)):
			continue
		if best == "" or sw.length() > best.length():
			best = sw
	return best


## Substitute player-taught definitions into parse text so the intent engine
## understands sentences with learned words (HTML _lxSubstParse). Seeds are
## excluded — targeted intent patterns already cover them.
func subst_parse(ntext: String) -> String:
	var keys: Array = []
	for w in words:
		var e: Dictionary = words[w]
		if bool(e.get("seed", false)):
			continue
		var d := _first_meaning(e)
		if d == "":
			continue
		if d == String(w):
			continue
		keys.append(String(w))
	keys.sort_custom(func(a, b): return String(a).length() > String(b).length())
	var out := " " + ntext + " "
	for k in keys:
		var d2 := _first_meaning(words[k])
		if d2 == "":
			continue
		out = out.replace(" " + k + " ", " " + d2 + " ")
	return _rx_sub("\\s+", out.strip_edges(), " ")


func _first_meaning(e: Dictionary) -> String:
	var def := String(e.get("meaning", "")).split(",")[0].strip_edges().to_lower()
	def = _rx_sub("[^a-z0-9 ]", def, " ")
	def = _rx_sub("\\s+", def, " ").strip_edges()
	return def


## True only when the message is ABOUT the word — asked about, defined, or
## requested — never a mere mention (HTML _lxWordAbout).
func word_about(ntext: String, w: String) -> bool:
	var we := _rx_sub("[^a-z0-9]", w.to_lower(), "")
	if we == "":
		return false
	var t := " " + ntext + " "
	if not t.contains(" " + we + " "):
		return false
	var pats: Array = [
		"what does " + we, "what s " + we, "what is " + we,
		"do you know " + we, "tell me about " + we, "define " + we,
		"explain " + we, "say " + we, "use " + we + " in a sentence",
		"what a " + we + " is", "know what a " + we,
		"don t know what a " + we,
	]
	for p in pats:
		if t.contains(String(p)):
			return true
	return false


## Longest-first match of learned words; the word must be the TOPIC, not a
## passing mention (HTML LexiconMatch). Returns the word or "".
func match_word(raw_text: String) -> String:
	var ntext := _lx_norm(raw_text)
	var stems := {}
	for w in _words_of(ntext):
		stems[stem(String(w))] = true
	var keys: Array = words.keys()
	keys.sort_custom(func(a, b): return String(a).length() > String(b).length())
	for w in keys:
		var e: Dictionary = words[w]
		var hit := false
		for s in e.get("stems", []):
			if stems.has(String(s)):
				hit = true
				break
		if not hit:
			continue
		if word_about(ntext, String(w)):
			return String(w)
	return ""


## ---------------------------------------------------------------------------
## Replies
## ---------------------------------------------------------------------------
## The showoff (HTML LexiconWordReply): first time THIS npc answers about
## THIS word they flaunt it with faction-voiced flair; later asks get a plain
## reminder. Prefers the natural stored phrase over the keyword list.
func word_reply(word: String, unit: Dictionary, ruler_name: String) -> String:
	if not words.has(word):
		return ""
	var e: Dictionary = words[word]
	e["uses"] = int(e.get("uses", 0)) + 1
	var faction := voice_faction(unit)
	var meaning := _display_meaning(e)
	var npc_key := npc_key_for(unit)
	var shown_by: Array = e.get("shown_by", [])
	var fill := {"word": word, "kw": meaning, "name": ruler_name}
	if not shown_by.has(npc_key):
		# First time THIS npc answers about THIS word: the showoff moment.
		shown_by.append(npc_key)
		e["shown_by"] = shown_by
		var pool: Array = (VOICE[faction] as Dictionary).get("word", [])
		if pool.is_empty():
			pool = (VOICE["gnome"] as Dictionary)["word"]
		# Deterministic showoff: prefer the signature "look at me, learning" line.
		for i in pool.size():
			var line := String(pool[i])
			if line.contains("look at me, learning") or line.contains("mark the damn calendar"):
				return _fill(line, fill)
		return _fill(String(pool[_rng.randi_range(0, pool.size() - 1)]), fill)
	# Asked again: a plain reminder, never another showoff.
	var pool2: Array = (VOICE[faction] as Dictionary).get("wordAgain", [])
	if pool2.is_empty():
		pool2 = (VOICE[faction] as Dictionary).get("word", [])
	if pool2.is_empty():
		pool2 = (VOICE["gnome"] as Dictionary)["word"]
	return _fill(String(pool2[_rng.randi_range(0, pool2.size() - 1)]), fill)


## ---------------------------------------------------------------------------
## The hook — corrections, pending definitions, facts, vocab asks
## ---------------------------------------------------------------------------
## True when the raw text looks like a correction or a learned-fact statement:
## the engine should route to the lexicon BEFORE intent parsing (HTML
## LexiconWantsFirst).
func wants_first(text: String) -> bool:
	if _rx_search("(?i)\\bno,?\\s*i meant (.+)", text) != null:
		return true
	if _rx_search("(?i)\\bthat'?s wrong\\b", text) != null:
		return true
	if _rx_search("(?i)\\bnot quite\\b", text) != null:
		return true
	if _rx_search("(?i)\\bmy ([a-z ]{1,20}?) is ([^.!,?]{1,40})", text) != null:
		return true
	if _rx_search("(?i)\\bi (like|love|hate|adore|despise) ([^.!,?]{1,40})", text) != null:
		return true
	return false


func has_pending(npc_key: String) -> bool:
	return pending.has(npc_key)


func _npc_display_name(unit: Dictionary) -> String:
	if unit.has("display_name"):
		return String(unit["display_name"])
	return String(unit.get("name", "friend"))


## Pointing words in a definition: "you" = the NPC, "me" = the player
## (HTML CANDIDATE79).
func _pointing_word(pnorm: String, unit: Dictionary,
		ruler_name: String) -> String:
	if pnorm in ["you", "u", "urself", "yourself"]:
		return _npc_display_name(unit).split(" ")[0].to_lower()
	if pnorm in ["me", "myself", "i"]:
		return "you, " + ruler_name
	if pnorm in ["this", "that", "it", "that thing", "this thing"]:
		return "that"
	if pnorm in ["him", "her", "them", "they"]:
		return pnorm
	return ""


## First-pass hook: corrections + pending definitions (HTML LexiconHook part 1).
## Returns {text, intent} or {} when nothing fires.
func handle_first_pass(text: String, norm: String, unit: Dictionary,
		ruler_name: String, day: int) -> Dictionary:
	var npc_key := npc_key_for(unit)
	track_style(npc_key, text, "")
	var faction := voice_faction(unit)
	var fill := {"name": ruler_name}
	# --- correction ---
	var corr := ""
	var cm := _rx_search("(?i)\\bno,?\\s*i meant (.+)", text)
	if cm != null:
		corr = cm.get_string(1).strip_edges()
	elif _rx_search("(?i)\\bthat'?s wrong\\b", text) != null \
			or _rx_search("(?i)\\bnot quite\\b", text) != null:
		corr = text
	if corr != "":
		var ckw := def_keywords(corr, 5)
		var ckw_str := ", ".join(ckw)
		if pending.has(npc_key):
			# Correction arrived as the answer: treat it as the definition.
			var pw := String((pending[npc_key] as Dictionary).get("word", ""))
			pending.erase(npc_key)
			if not ckw.is_empty():
				learn_word(pw, ckw, npc_key, day, _npc_display_name(unit))
				_set_phrase(pw, _clean_phrase(corr))
				fill["word"] = pw
				fill["kw"] = ckw_str
				return {"text": _fill(_say(faction, "ack"), fill),
					"intent": "lex_learn"}
			fill["word"] = pw
			return {"text": _fill(_say(faction, "cancel"), fill),
				"intent": "lex_learn"}
		var lw := String(last_taught.get(npc_key, ""))
		if lw != "" and words.has(lw):
			if not ckw.is_empty():
				var entry: Dictionary = words[lw]
				entry["meaning"] = ckw_str
				var stems: Array = [stem(lw)]
				for k in ckw:
					var ks := stem(String(k))
					if not stems.has(ks):
						stems.append(ks)
				entry["stems"] = stems
				fill["word"] = lw
				fill["kw"] = ckw_str
				return {"text": _fill(_say(faction, "correct"), fill),
					"intent": "lex_correct"}
			fill["word"] = lw
			return {"text": _fill(_say(faction, "cancel"), fill),
				"intent": "lex_learn"}
		# Correction with nothing to correct — fall through.
	# --- pending definition ---
	if pending.has(npc_key):
		var pword := String((pending[npc_key] as Dictionary).get("word", ""))
		if _rx_search("(?i)^(never ?mind|forget ?it|cancel|nothing|nevermind)$",
				_lx_norm(text)) != null:
			pending.erase(npc_key)
			fill["word"] = pword
			return {"text": _fill(_say(faction, "cancel"), fill),
				"intent": "lex_learn"}
		var pnorm := _rx_sub("^[.!,?;\\s]+|[.!,?;\\s]+$", _lx_norm(text), "")
		var point := _pointing_word(pnorm, unit, ruler_name)
		if point != "":
			pending.erase(npc_key)
			learn_word(pword, [point], npc_key, day, _npc_display_name(unit))
			_set_phrase(pword, point.left(120))
			fill["word"] = pword
			fill["kw"] = point
			return {"text": _fill(_say(faction, "ack"), fill),
				"intent": "lex_learn"}
		var dkw := def_keywords(text, 5)
		if dkw.is_empty():
			var tries := int((pending[npc_key] as Dictionary).get("tries", 0)) + 1
			(pending[npc_key] as Dictionary)["tries"] = tries
			if tries >= 3:
				pending.erase(npc_key)
				fill["word"] = pword
				return {"text": _fill(_say(faction, "cancel"), fill),
					"intent": "lex_learn"}
			fill["word"] = pword
			return {"text": _fill(_say(faction, "ask"), fill),
				"intent": "lex_ask"}
		pending.erase(npc_key)
		# Keep the natural definition phrase as given — strip only the
		# framing ("it's" / "it means" / "means").
		var phrase := _clean_phrase(text)
		learn_word(pword, dkw, npc_key, day, _npc_display_name(unit))
		_set_phrase(pword, phrase)
		fill["word"] = pword
		fill["kw"] = phrase if phrase != "" else ", ".join(dkw)
		return {"text": _fill(_say(faction, "ack"), fill),
			"intent": "lex_learn"}
	return {}


func _add_fact(npc_key: String, k: String, v: String) -> void:
	var fl: Array = facts.get(npc_key, [])
	fl.append({"k": k, "v": v})
	while fl.size() > MAX_FACTS:
		fl.pop_front()
	facts[npc_key] = fl


## Fallback hook: learned facts, fact callbacks, vocab asks (HTML LexiconHook
## part 2). Called when normal intent parsing came up unclear.
## Returns {text, intent} or {} when nothing fires.
func handle_fallback(text: String, norm: String, unit: Dictionary,
		ruler_name: String, day: int) -> Dictionary:
	var npc_key := npc_key_for(unit)
	track_style(npc_key, text, "")
	var faction := voice_faction(unit)
	var fill := {"name": ruler_name}
	# --- learned facts ---
	var fm := _rx_search("(?i)\\bmy ([a-z ]{1,20}?) is ([^.!,?]{1,40})", text)
	if fm != null:
		var fk := fm.get_string(1).strip_edges().to_lower()
		var fv := fm.get_string(2).strip_edges()
		if fk != "" and fv != "" and fk != "name" and fk.length() <= 20 \
				and fv.length() <= 40:
			_add_fact(npc_key, fk, fv)
			fill["k"] = fk
			fill["v"] = fv
			return {"text": _fill(_say(faction, "fact"), fill),
				"intent": "lex_fact"}
	var lm := _rx_search(
		"(?i)\\bi (like|love|hate|adore|despise) ([^.!,?]{1,40})", text)
	if lm != null:
		var verb := lm.get_string(1).to_lower()
		var thing := lm.get_string(2).strip_edges()
		var fk2 := "favorite" if verb in ["like", "love", "adore"] else "grudge"
		if thing != "" and thing.length() <= 40:
			_add_fact(npc_key, fk2, thing)
			fill["k"] = fk2
			fill["v"] = thing
			return {"text": _fill(_say(faction, "fact"), fill),
				"intent": "lex_fact"}
	# --- 12% fact callback ---
	var fl: Array = facts.get(npc_key, [])
	if not fl.is_empty() and _rng.randf() < 0.12:
		var rf: Dictionary = fl[_rng.randi_range(0, fl.size() - 1)]
		fill["k"] = String(rf.get("k", ""))
		fill["v"] = String(rf.get("v", ""))
		return {"text": _fill(_say(faction, "factRef"), fill),
			"intent": "lex_factref"}
	# --- learn a new word ---
	var novel := salient_unknown(text)
	if novel != "":
		pending[npc_key] = {"word": novel, "tries": 0}
		fill["word"] = novel
		return {"text": _fill(_say(faction, "ask"), fill),
			"intent": "lex_ask"}
	return {}


## ---------------------------------------------------------------------------
## Style tracking + tone (HTML _lxTrackStyle / LexiconTone)
## ---------------------------------------------------------------------------
func track_style(npc_key: String, text: String, intent: String) -> void:
	var s: Dictionary = style.get(npc_key,
		{"msgs": 0, "swears": 0, "topics": {}})
	s["msgs"] = int(s.get("msgs", 0)) + 1
	var hit := 0
	for w in _words_of(text):
		if SWEAR.has(String(w)):
			hit += 1
			if hit >= 3:
				break
	s["swears"] = int(s.get("swears", 0)) + hit
	if intent != "" and intent != "unclear":
		var topics: Dictionary = s.get("topics", {})
		topics[intent] = int(topics.get(intent, 0)) + 1
		s["topics"] = topics
	style[npc_key] = s


## Subtle mirroring only: at most one appended clause, or one softened
## exclamation. Never rewrites, never breaks faction voice (HTML LexiconTone).
func tone(text: String, npc_key: String, faction: String) -> String:
	var out := String(text)
	if out == "":
		return out
	var s: Dictionary = style.get(npc_key, {})
	if s.is_empty() or int(s.get("msgs", 0)) < 3:
		return out
	var vf: String = faction if VOICE.has(faction) else "gnome"
	var msgs := float(s.get("msgs", 1))
	var swear_rate := float(s.get("swears", 0)) / msgs
	if swear_rate > 0.3 and (vf == "gnome" or vf == "human"):
		if vf == "gnome":
			return out + " (You kiss your mother with that mouth?)"
		return out + " (Charming vocabulary you've got there.)"
	if int(s.get("swears", 0)) == 0 and out.contains("!"):
		return out.replace("!", ".")
	return out


## ---------------------------------------------------------------------------
## Daily gossip spread (HTML LexiconDailyTick)
## ---------------------------------------------------------------------------
func _day_number() -> int:
	if _gs != null:
		var d = _gs.get("day_number")
		if d != null:
			return int(d)
	return tick_day


func _ruler_name() -> String:
	if _gs != null:
		var rn = _gs.get("ruler_name")
		if rn != null and String(rn) != "":
			return String(rn)
	return "friend"


func _unit_by_key(key: String) -> Dictionary:
	if _gs == null or key == "":
		return {}
	if not key.begins_with("u"):
		return {}
	var uid := int(key.trim_prefix("u"))
	var units = _gs.get("units")
	if not (units is Array):
		return {}
	for u in units:
		if u is Dictionary and int((u as Dictionary).get("id", -1)) == uid:
			return u
	return {}


func _teacher_name(key: String, fallback: String) -> String:
	var u := _unit_by_key(key)
	if u.is_empty():
		# Fall back to the name recorded at learn time.
		for w in words:
			var e: Dictionary = words[w]
			if String(e.get("taught_by", "")) == key:
				var tn := String(e.get("teacher_name", ""))
				if tn != "":
					return tn
		return fallback
	return _npc_display_name_simple(u)


static func _npc_display_name_simple(u: Dictionary) -> String:
	if u.has("display_name"):
		return String(u["display_name"])
	return String(u.get("name", "someone"))


## Jeremy 2026-10-11: visible social life feeds the lexicon — when NPCs
## use learned words in DMs/threads, that's a natural teaching moment.
## Words an NPC knows (non-seed), for sprinkling into chatter.
func known_words_for(npc_key: String) -> Array:
	var out: Array = []
	for w in words:
		var e: Dictionary = words[w]
		if bool(e.get("seed", false)):
			continue
		if (e.get("known_by", []) as Array).has(npc_key):
			out.append(String(w))
	return out


## Record an overhear: learner picks up a word from the teacher's chatter.
## Spread stays capped — shares the 1/day last_spread_day cap with the
## existing daily_tick (never more than one spread per day, from either
## path). Returns true if the word was learned.
func note_overhear(word: String, teacher_key: String, learner_key: String) -> bool:
	if teacher_key == learner_key:
		return false
	var day := _day_number()
	if int(last_spread_day) == day:
		return false  # the 1/day spread cap holds
	if not words.has(word):
		return false
	var e: Dictionary = words[word]
	var known: Array = e.get("known_by", [])
	if known.has(learner_key):
		return false
	known.append(learner_key)
	e["known_by"] = known
	e["spread"] = int(e.get("spread", 0)) + 1
	e["taught_by"] = teacher_key
	last_spread_day = day
	return true


## Once per game day: the oldest learned word (aged >= 2 days, spread < 3)
## is overheard by one random living NPC who doesn't know it yet. Bounded:
## at most one spread per day. The word arrives as a gossip DM to the player
## (HTML msgrDeliverRuler parity). Returns the DM text or "".
func daily_tick() -> String:
	var day := _day_number()
	if last_spread_day == day:
		return ""
	var cand := ""
	var cand_e := {}
	for w in words:
		var e: Dictionary = words[w]
		if bool(e.get("seed", false)):
			continue
		var age := day - int(e.get("day", day))
		if age >= 2 and int(e.get("spread", 0)) < 3:
			if cand == "" or int(e.get("day", 0)) < int(cand_e.get("day", 0)):
				cand = String(w)
				cand_e = e
	if cand == "":
		return ""
	var known: Array = cand_e.get("known_by", [])
	var targets: Array = []
	if _gs != null:
		var units = _gs.get("units")
		if units is Array:
			for u in units:
				if not (u is Dictionary):
					continue
				var ud: Dictionary = u
				if bool(ud.get("dead", false)):
					continue
				var key := "u%d" % int(ud.get("id", 0))
				if known.has(key):
					continue
				targets.append(ud)
	if targets.is_empty():
		return ""
	var t: Dictionary = targets[_rng.randi_range(0, targets.size() - 1)]
	var tkey := "u%d" % int(t.get("id", 0))
	known.append(tkey)
	cand_e["known_by"] = known
	cand_e["spread"] = int(cand_e.get("spread", 0)) + 1
	last_spread_day = day
	var teacher := _teacher_name(String(cand_e.get("taught_by", "")), "someone")
	var tf := voice_faction(t)
	var txt := _fill(_say(tf, "gossip"),
		{"teacher": teacher, "word": cand, "name": _ruler_name()})
	if String(cand_e.get("meaning", "")) != "":
		txt += " (They heard it from %s — that's who taught %s.)" % [
			_ruler_name(), teacher]
	if _gs != null:
		var phone = _gs.get("phone_sys")
		if phone != null and phone.has_method("npc_message"):
			phone.npc_message(int(t.get("id", 0)), txt)
	return txt


## ---------------------------------------------------------------------------
## Backchannel + flow helpers
## ---------------------------------------------------------------------------
## Taught words for backchannel chatter (HTML bcLexiconWord parity):
## [{word, meaning, taught_by}].
func taught_words() -> Array:
	var out: Array = []
	for w in words:
		var e: Dictionary = words[w]
		out.append({
			"word": String(w),
			"meaning": _display_meaning(e),
			"taught_by": _teacher_name(
				String(e.get("taught_by", "")), "someone"),
			# Jeremy 2026-10-06: lets callers (e.g. the Squabble lexicon
			# showoff generator) prefer genuinely player-taught words.
			"seed": bool(e.get("seed", false)),
		})
	return out


## word -> display meaning, for Flow.enrich's learned-word reuse.
## Seeds are excluded — this is for words the player actually taught.
func simple_words() -> Dictionary:
	var out := {}
	for w in words:
		var e: Dictionary = words[w]
		if bool(e.get("seed", false)):
			continue
		out[String(w)] = _display_meaning(e)
	return out


## ---------------------------------------------------------------------------
## Persistence (HTML LexiconSave / LexiconLoad)
## ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"words": (words as Dictionary).duplicate(true),
		"facts": (facts as Dictionary).duplicate(true),
		"pending": (pending as Dictionary).duplicate(true),
		"style": (style as Dictionary).duplicate(true),
		"last_taught": (last_taught as Dictionary).duplicate(true),
		"last_spread_day": last_spread_day,
		"tick_day": tick_day,
		"v": 1,
	}


func from_dict(d: Dictionary) -> void:
	words = (d.get("words", {}) as Dictionary).duplicate(true)
	facts = (d.get("facts", {}) as Dictionary).duplicate(true)
	pending = (d.get("pending", {}) as Dictionary).duplicate(true)
	style = (d.get("style", {}) as Dictionary).duplicate(true)
	last_taught = (d.get("last_taught", {}) as Dictionary).duplicate(true)
	last_spread_day = int(d.get("last_spread_day", 0))
	tick_day = int(d.get("tick_day", 1))
	# Baseline seeds survive save/load; player-taught meanings always win.
	_apply_seed_baseline()
