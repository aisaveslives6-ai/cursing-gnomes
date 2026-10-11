class_name SimPersonality
extends RefCounted
## Cursing Gnomes — NPC personality traits (Milestone 5: minds).
##
## Every NPC gets a deterministic personality seeded from their unit id:
## two NPCs with the same id always roll the same traits, which survives
## save/load with zero extra state. Traits shape combat willingness,
## work speed, chatter frequency, and dialogue tone.
##
## Traits (all 0.0–1.0):
##   brave    — high: stands and fights; low: flees when scared
##   friendly — high: chats and socializes more; low: grumbles alone
##   diligent — high: works faster, ignores minor urges; low: slacks off
##   crude    — high: roasts the ruler, swears; low: polite
##   proud    — high: takes insults badly; low: shrugs them off
##   criminal — high: steals what they need (sneak mode, pickpocket)
##   violent  — high: fights guards rather than submitting to arrest
##   unhinged — 1.0/0.0 flag: when furious at the ruler, cusses them out
##              AND spams DMs instead of one cold reply (Jeremy 2026-10-06)
##
## Every NPC also gets a deterministic persona (one of the 12 gazette
## personas), weighted by faction — used for cuss-out voice, outrage
## style, and flavor. Same seed stability as traits.
##
## Design ported from the HTML build's per-NPC variation (not its code).
## Pure logic — no rendering, no input, no audio, no network.


## Deterministic display names per faction, picked by unit id.
const NAMES := {
	"humans": ["Bram", "Odette", "Pip", "Mabel", "Dunc", "Sera", "Tobin", "Wren"],
	"ogres": ["Grak", "Muz", "Thud", "Borga", "Snag", "Ruk"],
	"elves": ["Lirael", "Fen", "Ael", "Syl", "Tir", "Nael"],
	"gnomes": ["Knackers", "Fiddle", "Nib", "Tansy", "Boddle", "Pippa"],
	"undead": ["Rot", "Marrow", "Ghast", "Vex", "Molder", "Crypt"],
	"monster": ["Gristle", "Maw", "Snarl"],
}


## Persona pools per faction, weighted by repetition (HTML personaVoice set).
const PERSONA_POOLS := {
	"humans": ["pragmatic", "pragmatic", "pragmatic", "loyal", "loyal",
		"earnest", "earnest", "worried", "worried", "jolly", "proud",
		"blunt", "honorable", "scheming", "oily"],
	"ogres": ["blunt", "blunt", "blunt", "grizzled", "grizzled", "proud",
		"proud", "jolly", "scheming", "pragmatic"],
	"elves": ["honorable", "honorable", "honorable", "earnest", "earnest",
		"haughty", "haughty", "pragmatic", "pragmatic", "proud", "jolly",
		"worried"],
	"gnomes": ["jolly", "jolly", "jolly", "scheming", "scheming",
		"pragmatic", "pragmatic", "oily", "oily", "earnest", "worried"],
	"undead": ["scheming", "scheming", "proud", "proud", "pragmatic",
		"pragmatic", "haughty", "haughty", "blunt", "grizzled", "worried"],
	"monster": ["grizzled", "grizzled", "grizzled", "blunt", "blunt",
		"blunt", "proud", "proud", "jolly", "scheming"],
}


## All valid personas (gazette.gd PERSONA_VOICES parity).
const PERSONAS := ["worried", "pragmatic", "jolly", "proud", "scheming",
	"honorable", "blunt", "loyal", "grizzled", "oily", "haughty", "earnest"]


## Unhinged thresholds per faction: P(roll >= threshold) is unhinged.
## Ogres/monsters snap easiest, elves rarely — it has to mean something.
const UNHINGED_THRESHOLDS := {
	"ogres": 0.70, "monster": 0.70,
	"undead": 0.80, "gnomes": 0.80,
	"humans": 0.85, "elves": 0.92,
}


## Traits + display name for a unit id. Deterministic — same id, same mind.
## Pass the faction so the name pool fits; falls back to "humans".
## Jeremy 2026-10-06: "unhinged" + "persona" appended LAST so every
## pre-existing trait keeps its exact deterministic roll for existing ids.
static func traits_for(unit_id: int, faction: String = "humans") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = unit_id * 7919 + 13
	var pool: Array = NAMES.get(faction, NAMES["humans"])
	var uh_thresh: float = float(UNHINGED_THRESHOLDS.get(faction, 0.85))
	var ppool: Array = PERSONA_POOLS.get(faction, PERSONA_POOLS["humans"])
	return {
		"brave": rng.randf(),
		"friendly": rng.randf(),
		"diligent": rng.randf(),
		"crude": rng.randf(),
		"proud": rng.randf(),
		# Jeremy 2026-10-04: appended LAST so the five original traits keep
		# their exact deterministic rolls for every existing unit id.
		"criminal": rng.randf(),
		"violent": rng.randf(),
		# Jeremy 2026-10-06: unhinged flag (1.0/0.0) + persona, appended
		# after everything so no earlier roll shifts.
		"unhinged": 1.0 if rng.randf() >= uh_thresh else 0.0,
		"persona": String(ppool[rng.randi() % ppool.size()]),
		"name": String(pool[unit_id % pool.size()]),
	}


## Trait lookup on a unit record's cached mind dict (0.5 default).
static func trait_of(unit: Dictionary, trait_name: String) -> float:
	var mind: Dictionary = unit.get("mind", {})
	var traits: Dictionary = mind.get("traits", {})
	return float(traits.get(trait_name, 0.5))


## Display name for a unit record (cached on first use).
static func display_name(unit: Dictionary) -> String:
	var mind: Dictionary = unit.get("mind", {})
	var n: String = String(mind.get("name", ""))
	if n != "":
		return n
	var t: Dictionary = traits_for(int(unit.get("id", 0)),
		String(unit.get("faction", "humans")))
	return String(t["name"])


## Work-speed multiplier from diligence: 0.85x (slacker) to 1.15x (eager).
static func work_speed_mult(unit: Dictionary) -> float:
	return 0.85 + 0.30 * trait_of(unit, "diligent")


## True if this NPC would rather fight than flee when scared.
static func stands_ground(unit: Dictionary) -> bool:
	return trait_of(unit, "brave") >= 0.4


## Seconds between idle chatter barks: friendly/crude NPCs talk more.
static func chatter_interval(unit: Dictionary) -> float:
	var talky: float = maxf(trait_of(unit, "friendly"), trait_of(unit, "crude"))
	return lerpf(Config.MIND_CHATTER_MAX_CD, Config.MIND_CHATTER_MIN_CD, talky)


## True when this NPC's criminal streak is strong enough to steal.
## (The SimCrime shady/klepto/desperate scan also flags criminals — either
## path feeds the real-time crime layer, like HTML's hasTrait check.)
static func is_criminal_minded(unit: Dictionary) -> bool:
	return trait_of(unit, "criminal") > 0.55


## True when this NPC is violent enough to fight guards rather than
## submit to arrest (Jeremy 2026-10-04).
static func is_violent(unit: Dictionary) -> bool:
	return trait_of(unit, "violent") > 0.6


## True when this NPC has the unhinged trait (Jeremy 2026-10-06): while
## furious at the ruler they cuss out + spam DMs instead of one cold reply.
## Legacy-safe: units saved before the trait existed read 0.0 (not unhinged).
static func is_unhinged(unit: Dictionary) -> bool:
	var mind: Dictionary = unit.get("mind", {})
	var traits: Dictionary = mind.get("traits", {})
	return float(traits.get("unhinged", 0.0)) >= 0.5


## Persona for a unit record ("pragmatic" default for legacy/unknown).
static func persona_of(unit: Dictionary) -> String:
	var mind: Dictionary = unit.get("mind", {})
	var traits: Dictionary = mind.get("traits", {})
	var p := String(traits.get("persona", "pragmatic"))
	if p == "" or not p in PERSONAS:
		return "pragmatic"
	return p
