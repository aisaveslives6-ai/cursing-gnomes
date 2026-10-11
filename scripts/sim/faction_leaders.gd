class_name SimFactionLeaders
extends RefCounted
## Cursing Gnomes — AI faction leaders (Jeremy 2026-10-04).
##
## Each of the 5 factions gets a distinct AI leader character the player
## can actually communicate with: message them in Messenger, propose
## policies, and issue AI directives that steer the SimAIDirector.
##
## Leaders have:
##   - MEMORY: they remember what you said and did — including the racist
##     incident ("goes into their leaders memory"). Memories decay slowly
##     and color every interaction.
##   - MOOD: an emotional state toward the player (and others) that shifts
##     with events and drives dialogue tone.
##   - PERSONALITY: faction-flavored voice (ogre warlord is blunt, elf
##     queen is diplomatic, etc.).
##
## Phone integration: leaders appear as special contacts with keys
## "leader_<faction>". SimPhone routes leader messages through the same
## realistic-texting queue (typing indicators, delays, read receipts).
##
## AI directives: issue_command() sets a directive that SimAIDirector
## reads — "military" forces raid posture, "economy" forces expand,
## "fortify" forces fortify, "defend" forces defend. Only works if the
## leader trusts you (allied/vassal) or fears you enough.
##
## Pure logic — no rendering, no input, no audio, no network.


## Leader candidate pools (Jeremy 2026-10-06): 3-4 candidates per faction,
## ONE picked at random per faction at game start. Leaders are NOT NPCs
## walking the world — each is the AI "player" steering that faction.
## The player's own faction gets NO AI leader (the player is the leader).
##
## Candidate schema: name, title, voice, greeting, desc, traits, rumors.
## traits: aggression / treachery / generosity / patience (0..1) — wired
## into real behavior (see traits_of() and proposals.gd _ai_evaluate).
## rumors: signature hearsay lines in the leader's own voice.
const LEADER_POOLS := {
	"humans": [
		{
			"name": "King Aldric", "title": "the Steady", "voice": "diplomatic",
			"greeting": "King Aldric regards you with measured courtesy.",
			"desc": "A pragmatic monarch who values stability above all.",
			"traits": {"aggression": 0.35, "treachery": 0.2,
				"generosity": 0.6, "patience": 0.8},
			"rumors": [
				"King Aldric has been reviewing the border maps again. He always reviews the border maps.",
				"They say Aldric keeps a ledger of every favor ever done him. And every slight.",
			],
		},
		{
			"name": "Queen Seraphine", "title": "the Just", "voice": "diplomatic",
			"greeting": "Queen Seraphine greets you warmly. \"The realm prospers when rulers talk.\"",
			"desc": "A fair-minded queen who believes justice is good policy.",
			"traits": {"aggression": 0.25, "treachery": 0.1,
				"generosity": 0.85, "patience": 0.7},
			"rumors": [
				"Queen Seraphine pardoned a thief yesterday. Then hired him as a courier. Typical.",
				"Seraphine's court feeds a thousand poor every week. The other rulers pretend not to notice.",
			],
		},
		{
			"name": "Lord Commander Vex", "title": "the Iron", "voice": "blunt",
			"greeting": "Lord Commander Vex salutes crisply. \"State your business.\"",
			"desc": "A soldier-king. Diplomacy is just war by other means.",
			"traits": {"aggression": 0.8, "treachery": 0.3,
				"generosity": 0.3, "patience": 0.4},
			"rumors": [
				"Vex drills his troops at dawn. Every dawn. Even feast days.",
				"They say Vex settled a trade dispute by arm-wrestling the merchant. He won.",
			],
		},
		{
			"name": "Chancellor Mira", "title": "the Patient", "voice": "diplomatic",
			"greeting": "Chancellor Mira smiles thinly. \"I have been expecting you. Eventually.\"",
			"desc": "She has outwaited three kings. She can outwait you.",
			"traits": {"aggression": 0.2, "treachery": 0.45,
				"generosity": 0.5, "patience": 0.95},
			"rumors": [
				"Chancellor Mira hasn't raised her voice in forty years. Nobody wants to find out why.",
				"Mira's spies are said to file reports in triplicate. Even her secrets are bureaucratic.",
			],
		},
	],
	"ogres": [
		{
			"name": "Warlord Grak", "title": "the Crusher", "voice": "blunt",
			"greeting": "Warlord Grak cracks his knuckles. \"Talk.\"",
			"desc": "Might makes right. Respects strength, despises weakness.",
			"traits": {"aggression": 0.85, "treachery": 0.3,
				"generosity": 0.4, "patience": 0.3},
			"rumors": [
				"Grak ate a diplomat once. Allegedly. The chair is still empty.",
				"Warlord Grak's idea of negotiation is showing up with forty warriors.",
			],
		},
		{
			"name": "Warlord Maug", "title": "the Render", "voice": "blunt",
			"greeting": "Warlord Maug grins with too many teeth. \"You look soft.\"",
			"desc": "Cruel even by ogre standards. Smiles before he strikes.",
			"traits": {"aggression": 0.95, "treachery": 0.6,
				"generosity": 0.2, "patience": 0.15},
			"rumors": [
				"Maug challenged his own brother to a duel. There is no brother anymore.",
				"They say Maug keeps a list of everyone who ever wronged him. It's carved into a wall. A big wall.",
			],
		},
		{
			"name": "Chieftain Olga", "title": "Stonejaw", "voice": "blunt",
			"greeting": "Chieftain Olga sizes you up. \"You fight? Or you talk?\"",
			"desc": "A cunning brute — she thinks before she crushes.",
			"traits": {"aggression": 0.6, "treachery": 0.25,
				"generosity": 0.55, "patience": 0.65},
			"rumors": [
				"Olga Stonejaw once ended a siege by inviting the enemy general to dinner. He never left.",
				"Chieftain Olga reads. Actual books. The other warlords are terrified.",
			],
		},
	],
	"elves": [
		{
			"name": "Queen Aelindra", "title": "the Wise", "voice": "elegant",
			"greeting": "Queen Aelindra inclines her head gracefully.",
			"desc": "Ancient, principled, and patient — until she isn't.",
			"traits": {"aggression": 0.3, "treachery": 0.2,
				"generosity": 0.7, "patience": 0.9},
			"rumors": [
				"Queen Aelindra has watched empires rise and fall. She found most of them boring.",
				"They say Aelindra remembers the name of every elf who ever served her. All nine thousand.",
			],
		},
		{
			"name": "Lord Thalanil", "title": "the Stern", "voice": "elegant",
			"greeting": "Lord Thalanil regards you coolly. \"Speak precisely.\"",
			"desc": "The elves' sword-arm. Courtesy is just sharpened steel.",
			"traits": {"aggression": 0.65, "treachery": 0.3,
				"generosity": 0.4, "patience": 0.5},
			"rumors": [
				"Lord Thalanil dueled three human knights at once. He apologized for the mess.",
				"Thalanil's patience is legendary. His temper, when it finally goes, is more legendary.",
			],
		},
		{
			"name": "Sage Liara", "title": "Moonwhisper", "voice": "elegant",
			"greeting": "Sage Liara smiles like starlight. \"The threads brought you. How curious.\"",
			"desc": "She sees further than any of them, and forgives more.",
			"traits": {"aggression": 0.15, "treachery": 0.15,
				"generosity": 0.9, "patience": 0.95},
			"rumors": [
				"Sage Liara predicted the last three wars. Nobody listened. She keeps predicting anyway.",
				"Liara once talked a dragon out of burning a village. With poetry.",
			],
		},
	],
	"gnomes": [
		{
			"name": "Tinker-Chief Fizzle", "title": "the Cunning", "voice": "mischievous",
			"greeting": "Tinker-Chief Fizzle grins. \"Business or pleasure?\"",
			"desc": "Everything is negotiable. Everything has a price.",
			"traits": {"aggression": 0.4, "treachery": 0.7,
				"generosity": 0.5, "patience": 0.6},
			"rumors": [
				"Fizzle sold the same bridge twice. Both buyers think they got a deal.",
				"Tinker-Chief Fizzle's workshop has seventeen exits. He uses all of them.",
			],
		},
		{
			"name": "Coinmaster Drix", "title": "the Gilded", "voice": "mischievous",
			"greeting": "Coinmaster Drix counts coins without looking. \"You're costing me money standing there.\"",
			"desc": "He would sell you your own shadow and charge rent on the sunlight.",
			"traits": {"aggression": 0.3, "treachery": 0.9,
				"generosity": 0.3, "patience": 0.7},
			"rumors": [
				"Drix the Gilded once bought a kingdom's debt and foreclosed on the crown. He's wearing it now.",
				"Coinmaster Drix has never lost a bet. Statisticians have stopped investigating.",
			],
		},
		{
			"name": "Gearmistress Nissa", "title": "the Inventor", "voice": "mischievous",
			"greeting": "Gearmistress Nissa looks up from her workbench. \"Oh! A customer! A friend! Same thing!\"",
			"desc": "She'd rather build than scheme — which makes her the most dangerous gnome of all.",
			"traits": {"aggression": 0.25, "treachery": 0.3,
				"generosity": 0.8, "patience": 0.5},
			"rumors": [
				"Nissa's latest invention waters crops, shoos crows, and sings. Nobody asked for the singing.",
				"Gearmistress Nissa gave away her best design for free. Fizzle hasn't spoken to her since.",
			],
		},
	],
	"undead": [
		{
			"name": "Lich Lord Morvain", "title": "the Eternal", "voice": "cold",
			"greeting": "Lich Lord Morvain's eyes burn cold. \"Speak.\"",
			"desc": "Death is a beginning. Patience is a weapon.",
			"traits": {"aggression": 0.5, "treachery": 0.5,
				"generosity": 0.2, "patience": 0.9},
			"rumors": [
				"Morvain has been planning the same campaign for two hundred years. It is nearly ready.",
				"The Lich Lord collects hourglasses. He finds them... amusing.",
			],
		},
		{
			"name": "Dread Lady Vexara", "title": "the Hollow", "voice": "cold",
			"greeting": "Dread Lady Vexara's smile doesn't reach her eyes. Nothing reaches her eyes.",
			"desc": "She betrayed her own court in life. Death only widened her options.",
			"traits": {"aggression": 0.6, "treachery": 0.85,
				"generosity": 0.15, "patience": 0.7},
			"rumors": [
				"Vexara the Hollow poisoned her own coronation wine. She drank it first, to be polite.",
				"The Dread Lady keeps the ghosts of her enemies as advisors. They are very loyal now.",
			],
		},
		{
			"name": "Baron Sammael", "title": "the Patient", "voice": "cold",
			"greeting": "Baron Sammael bows with old-world grace. \"Time is on my side. It is always on my side.\"",
			"desc": "He has never hurried in six centuries. He has never needed to.",
			"traits": {"aggression": 0.3, "treachery": 0.4,
				"generosity": 0.3, "patience": 0.95},
			"rumors": [
				"Baron Sammael waited out a siege by simply... waiting. The besiegers gave up and went home.",
				"Sammael the Patient once spent a decade deciding on a banner color. It was worth it, he says.",
			],
		},
	],
}

## Valid AI directives (issue_command).
const DIRECTIVES := ["military", "economy", "fortify", "defend", "expand"]

## Directive -> AI director maneuver override.
const DIRECTIVE_MANEUVER := {
	"military": "raid",
	"economy": "expand",
	"fortify": "fortify",
	"defend": "defend",
	"expand": "expand",
}

## Memory types the leader tracks.
const MEM_RACIST := "racist_incident"
const MEM_POLICY := "policy"
const MEM_COMMAND := "command"
const MEM_MESSAGE := "message"
const MEM_WAR := "war"
const MEM_ALLIANCE := "alliance"

## Memory decay: halves every N game days.
const MEMORY_HALFLIFE := 30.0


var _gs: GameState
var _leaders: Dictionary = {}  # faction -> leader record
## Memories for factions with no AI leader record — the player's own faction
## (durable design: the player IS their faction's leader, never run top-down
## by AI). Adviser warnings routed through message_player() still need a
## recallable record, so they land here instead of being silently dropped.
var _stateless_memories: Dictionary = {}  # faction -> Array of memory dicts


func _init(game_state: GameState) -> void:
	_gs = game_state


## Reconciles the leader set after the player faction is finalized.
## Called when the player picks their faction (world.configure runs after
## game.setup, which used a default player faction). Removes any AI leader
## for the player's faction and ensures every other active faction has one.
## Safe to call multiple times; never re-rolls already-picked leaders.
func on_player_faction_set(player_faction: String, faction_ids: Array) -> void:
	if _leaders.has(player_faction):
		_leaders.erase(player_faction)
	for f in faction_ids:
		var fs: String = String(f)
		if fs == player_faction or _leaders.has(fs):
			continue
		_pick(fs)


## Creates leader records for all factions. Idempotent. Picks ONE random
## candidate per faction from LEADER_POOLS. The player's own faction gets
## no AI leader — the player IS that faction's leader (Jeremy 2026-10-06).
func ensure(faction_ids: Array) -> void:
	for f in faction_ids:
		var fs: String = String(f)
		if _leaders.has(fs):
			continue
		if _gs != null and _gs.player_faction == fs and fs != "":
			continue
		_pick(fs)


## Picks ONE random candidate from the faction's pool and installs them
## as the faction's leader. No-op when the pool is empty.
func _pick(fs: String) -> void:
	var pool: Array = LEADER_POOLS.get(fs, [])
	if pool.is_empty():
		return
	var idx: int = randi() % pool.size()
	var def: Dictionary = pool[idx]
	_leaders[fs] = {
		"faction": fs,
		"name": String(def.get("name", "Leader")),
		"title": String(def.get("title", "")),
		"voice": String(def.get("voice", "neutral")),
		"greeting": String(def.get("greeting", "")),
		"desc": String(def.get("desc", "")),
		"candidate": idx,
		"pfp": pfp_key_for(fs, idx),
		"traits": (def.get("traits", {}) as Dictionary).duplicate(),
		"rumors": (def.get("rumors", []) as Array).duplicate(),
		"memories": [],
		"mood": "neutral",
		"mood_intensity": 0.0,
		"directive": "",
		"directive_day": 0,
		"directive_from": "",
		"_last_rel": "",
	}


## Personality traits of a faction's picked leader
## ({aggression, treachery, generosity, patience}, 0..1). Neutral defaults
## when there's no leader (e.g. the player faction).
func traits_of(faction: String) -> Dictionary:
	var l: Dictionary = leader_of(faction)
	if l.is_empty():
		return {"aggression": 0.5, "treachery": 0.5,
			"generosity": 0.5, "patience": 0.5}
	var t: Dictionary = (l.get("traits", {}) as Dictionary).duplicate()
	t["aggression"] = clampf(float(t.get("aggression", 0.5)), 0.0, 1.0)
	t["treachery"] = clampf(float(t.get("treachery", 0.5)), 0.0, 1.0)
	t["generosity"] = clampf(float(t.get("generosity", 0.5)), 0.0, 1.0)
	t["patience"] = clampf(float(t.get("patience", 0.5)), 0.0, 1.0)
	return t


## Which pool candidate was picked for a faction (-1 if none).
func candidate_index_of(faction: String) -> int:
	return int(leader_of(faction).get("candidate", -1))


## A signature rumor line from the leader's own pool ("" if none).
func signature_rumor(faction: String) -> String:
	var rs: Array = leader_of(faction).get("rumors", [])
	if rs.is_empty():
		return ""
	return String(rs[randi() % rs.size()])


## Returns the leader record for a faction (empty dict if none).
func leader_of(faction: String) -> Dictionary:
	return _leaders.get(faction, {})


## All leaders.
func all_leaders() -> Array:
	var out: Array = []
	for f: String in _leaders:
		out.append(_leaders[f])
	return out


## Phone contact key for a faction's leader.
static func key_for(faction: String) -> String:
	return "leader_" + faction


## Jeremy 2026-10-06: every leader persona has a distinct anime-chibi
## pixel-art portrait (assets/art/portraits/leader_<faction>_<slug>.webp).
## Slugs are per-candidate so the portrait is stable for the persona no
## matter which game picks them.
const PFP_SLUGS := {
	"humans": ["aldric", "seraphine", "vex", "mira"],
	"ogres": ["grak", "maug", "olga"],
	"elves": ["aelindra", "thalanil", "liara"],
	"gnomes": ["fizzle", "drix", "nissa"],
	"undead": ["morvain", "vexara", "sammael"],
}


## Portrait key for a faction's candidate index ("" if unknown).
static func pfp_key_for(faction: String, candidate_idx: int) -> String:
	var arr: Array = PFP_SLUGS.get(faction, [])
	if candidate_idx < 0 or candidate_idx >= arr.size():
		return ""
	return "leader_%s_%s" % [faction, String(arr[candidate_idx])]


## Portrait key for a leader record ("" if none).
static func pfp_for_leader(leader: Dictionary) -> String:
	if leader.is_empty():
		return ""
	return pfp_key_for(String(leader.get("faction", "")),
		int(leader.get("candidate", -1)))


## Is this a leader contact key?
static func is_leader_key(key: String) -> bool:
	return key.begins_with("leader_")


## Faction from a leader key.
static func faction_for_key(key: String) -> String:
	return key.trim_prefix("leader_")


## --- Memory ---------------------------------------------------------------

## Adds a memory to the leader's record. Weight -1..1 (negative = bad).
## Factions with no AI leader record (the player's own faction) keep the
## memory in the fallback store — never silently dropped.
func remember(faction: String, mtype: String, subject: String, text: String,
		weight: float) -> void:
	var m := {
		"type": mtype, "subject": subject, "text": text,
		"day": _gs.day_number, "weight": clampf(weight, -1.0, 1.0),
	}
	var l: Dictionary = leader_of(faction)
	if l.is_empty():
		if not _stateless_memories.has(faction):
			_stateless_memories[faction] = []
		(_stateless_memories[faction] as Array).append(m)
		return
	(l["memories"] as Array).append(m)
	# Cap memories at 50 (prune oldest, keep racist incidents).
	var mems: Array = l["memories"]
	while mems.size() > 50:
		var idx := -1
		for i in range(mems.size()):
			if String(mems[i].get("type", "")) != MEM_RACIST:
				idx = i
				break
		if idx < 0:
			break
		mems.remove_at(idx)
	# Mood shifts with the memory.
	_shift_mood(faction, weight)


## Recalls memories of a type (decayed weight). Includes the fallback store
## for factions with no AI leader record.
func recall(faction: String, mtype: String) -> Array:
	var out: Array = []
	var l: Dictionary = leader_of(faction)
	if not l.is_empty():
		for m: Dictionary in l["memories"]:
			if String(m.get("type", "")) == mtype:
				out.append(m)
	for m: Dictionary in (_stateless_memories.get(faction, []) as Array):
		if String(m.get("type", "")) == mtype:
			out.append(m)
	return out


## Decayed opinion of a subject (-1..1). Racist incidents never fully decay.
## Includes the fallback store for factions with no AI leader record.
func opinion_of(faction: String, subject: String) -> float:
	var mems: Array = []
	var l: Dictionary = leader_of(faction)
	if not l.is_empty():
		mems.append_array(l["memories"])
	mems.append_array(_stateless_memories.get(faction, []) as Array)
	if mems.is_empty():
		return 0.0
	var total := 0.0
	for m: Dictionary in mems:
		if String(m.get("subject", "")) != subject:
			continue
		var age: float = float(_gs.day_number - int(m.get("day", 1)))
		var w: float = float(m.get("weight", 0.0))
		if String(m.get("type", "")) == MEM_RACIST:
			# Racist incidents decay very slowly (floor at 70%).
			total += w * maxf(0.7, pow(0.5, age / (MEMORY_HALFLIFE * 4.0)))
		else:
			total += w * pow(0.5, age / MEMORY_HALFLIFE)
	return clampf(total, -1.0, 1.0)


## Jeremy 2026-10-04: the racist incident goes into leaders' memory.
## Every leader remembers who did it.
func note_racist_incident(offender_faction: String, offender_name: String) -> void:
	for f: String in _leaders:
		remember(f, MEM_RACIST, offender_faction,
			"%s used the hard-r slur. Unforgivable." % offender_name, -1.0)


## --- Mood -----------------------------------------------------------------

func _shift_mood(faction: String, weight: float) -> void:
	var l: Dictionary = leader_of(faction)
	if l.is_empty():
		return
	var cur: float = float(l.get("mood_intensity", 0.0))
	var cur_mood: String = String(l.get("mood", "neutral"))
	if weight > 0.3:
		if cur_mood != "happy" or weight > cur:
			l["mood"] = "happy"
			l["mood_intensity"] = minf(1.0, cur + weight * 0.5)
	elif weight < -0.3:
		if cur_mood != "angry" or -weight > cur:
			l["mood"] = "angry"
			l["mood_intensity"] = minf(1.0, cur + (-weight) * 0.5)
	# Mood decays in tick() below.


## Current mood toward the player, factoring memories.
func mood_toward(faction: String, other: String) -> String:
	var op: float = opinion_of(faction, other)
	if op <= -0.7:
		return "furious"
	if op <= -0.3:
		return "hostile"
	if op >= 0.5:
		return "warm"
	if op >= 0.2:
		return "friendly"
	return String(leader_of(faction).get("mood", "neutral"))


## Daily tick: mood intensity decays. Called every physics frame; only
## acts on day change.
func tick(_delta: float) -> void:
	if _gs.day_number == _last_day:
		return
	_last_day = _gs.day_number
	for f: String in _leaders:
		var l: Dictionary = _leaders[f]
		var inten: float = float(l.get("mood_intensity", 0.0))
		if inten > 0.0:
			inten = maxf(0.0, inten - 0.1)
			l["mood_intensity"] = inten
			if inten <= 0.0:
				l["mood"] = "neutral"
		# Directives expire after 7 days.
		if String(l.get("directive", "")) != "" \
				and _gs.day_number - int(l.get("directive_day", 0)) > 7:
			l["directive"] = ""
			l["directive_from"] = ""
	_daily_tick()


var _last_day: int = 1


## --- Communication --------------------------------------------------------

## Generates the leader's reply to a player message. Personality-voiced,
## memory-aware, mood-colored. Pure logic — phone.gd queues delivery.
func reply_to(faction: String, player_faction: String, text: String) -> String:
	var l: Dictionary = leader_of(faction)
	if l.is_empty():
		return "..."
	var voice: String = String(l.get("voice", "neutral"))
	var mood: String = mood_toward(faction, player_faction)
	# Remember the exchange.
	remember(faction, MEM_MESSAGE, player_faction,
		"Player said: \"%s\"" % text, 0.0)
	var low := text.to_lower()
	# Intent routing (simple keyword matching — the full conversation
	# engine handles NPCs; leaders get direct, characterful responses).
	if _has_any(low, ["war", "attack", "invade", "destroy", "kill you"]):
		return _war_reply(faction, player_faction, voice, mood)
	# HTML surrenderReply62: a "peace offer" in a ruler DM is a REAL peace
	# offer — it resolves through diplomacy (offerPeace62), not flavor text.
	if low.contains("peace offer") or low.contains("peaceoffer"):
		return _peace_offer_reply(faction)
	if _has_any(low, ["peace", "truce", "ceasefire", "stop fighting"]):
		return _peace_reply(faction, player_faction, voice, mood)
	if _has_any(low, ["trade", "deal", "exchange", "buy", "sell"]):
		return _trade_reply(faction, player_faction, voice, mood)
	if _has_any(low, ["ally", "alliance", "pact", "together", "join"]):
		return _ally_reply(faction, player_faction, voice, mood)
	if _has_any(low, ["tribute", "gold", "pay you", "offer"]):
		return _tribute_reply(faction, player_faction, voice, mood)
	if _has_any(low, ["hello", "hi", "hey", "greetings", "hail"]):
		return _greeting_reply(faction, voice, mood)
	if _has_any(low, ["sorry", "apolog", "forgive"]):
		return _apology_reply(faction, player_faction, voice, mood)
	if _has_any(low, ["military", "army", "troops", "soldiers", "focus"]):
		return _directive_hint(faction, voice, "military")
	if _has_any(low, ["economy", "gold", "rich", "build", "expand"]):
		return _directive_hint(faction, voice, "economy")
	return _default_reply(faction, voice, mood)


static func _has_any(text: String, words: Array) -> bool:
	for w: String in words:
		if text.contains(w):
			return true
	return false


func _war_reply(faction: String, pf: String, voice: String, mood: String) -> String:
	var n: String = String(leader_of(faction).get("name", "Leader"))
	match voice:
		"blunt":
			return "\"HA! You want war? Come and take it, %s!\"" % _ruler_short()
		"elegant":
			return "\"War? How... predictable. We shall see whose wisdom prevails.\""
		"mischievous":
			return "\"Ooh, war! That'll be EXPENSIVE. For you, anyway.\""
		"cold":
			return "\"Death comes for all. Yours merely comes sooner.\""
		_:
			return "\"We do not seek war, but we do not fear it.\""
	return "\"...\""


func _peace_reply(faction: String, pf: String, voice: String, mood: String) -> String:
	if mood in ["furious", "hostile"]:
		return _default_hostile(voice)
	match voice:
		"blunt":
			return "\"Peace? Hmph. Make it worth my while.\""
		"elegant":
			return "\"Peace is the wisest course. Let us discuss terms.\""
		"mischievous":
			return "\"Peace! Wonderful. Now, about those trade tariffs...\""
		"cold":
			return "\"The dead do not need peace. But the living bore me. Proceed.\""
		_:
			return "\"Peace benefits us all. What terms do you offer?\""
	return "\"...\""


## The player typed "peace offer" to a ruler: run the real diplomacy offer
## (HTML offerPeace62 via surrenderReply62) and report the outcome in-voice.
func _peace_offer_reply(faction: String) -> String:
	var res: Dictionary = _gs.diplomacy.offer_peace(faction)
	var msg: String = String(res.get("msg", "..."))
	if not bool(res.get("ok", false)):
		return "\"" + msg + "\""
	if bool(res.get("accepted", false)):
		return "\"Very well. The banners come down. " + msg + "\""
	return "\"" + msg + " So the war continues.\""


func _trade_reply(faction: String, pf: String, voice: String, mood: String) -> String:
	if mood in ["furious", "hostile"]:
		return _default_hostile(voice)
	match voice:
		"blunt":
			return "\"Trade? Fine. Gold for steel. No tricks.\""
		"elegant":
			return "\"Our artisans craft wonders. Name your desire.\""
		"mischievous":
			return "\"Trade! My favorite word. What's your offer, friend?\""
		"cold":
			return "\"The dead have little use for gold. But souls... we can discuss.\""
		_:
			return "\"We are open to trade. What do you propose?\""
	return "\"...\""


func _ally_reply(faction: String, pf: String, voice: String, mood: String) -> String:
	if mood in ["furious", "hostile"]:
		return _default_hostile(voice)
	match voice:
		"blunt":
			return "\"Allies? Prove you're strong enough first.\""
		"elegant":
			return "\"An alliance... The stars would need to align. Convince me.\""
		"mischievous":
			return "\"Allies! I love allies. They pay SO well.\""
		"cold":
			return "\"Ally with the living? ...Unprecedented. Intriguing.\""
		_:
			return "\"An alliance is a serious bond. What do you offer?\""
	return "\"...\""


func _tribute_reply(faction: String, pf: String, voice: String, mood: String) -> String:
	match voice:
		"blunt":
			return "\"Gold? NOW you're speaking my language.\""
		"elegant":
			return "\"Tribute... a gesture of respect. We shall consider it.\""
		"mischievous":
			return "\"Gold! Shiny! Yes, yes, keep talking!\""
		"cold":
			return "\"Gold is dust. But we accept your... offering.\""
		_:
			return "\"Tribute is noted. Continue.\""
	return "\"...\""


func _greeting_reply(faction: String, voice: String, mood: String) -> String:
	if mood == "furious":
		return _default_hostile(voice)
	if mood == "warm" or mood == "friendly":
		match voice:
			"blunt": return "\"Ah, my favorite ruler! What do you need?\""
			"elegant": return "\"A pleasure, as always. How may I assist?\""
			"mischievous": return "\"My favorite customer! What's the scheme today?\""
			"cold": return "\"You return. The dead notice such persistence.\""
			_: return "\"Greetings, friend.\""
	var g: String = String(leader_of(faction).get("greeting", "Hello."))
	return "\"" + g + "\""


func _apology_reply(faction: String, pf: String, voice: String, mood: String) -> String:
	# Check for racist incident — apologies don't erase it, but help.
	var racist_mems: Array = recall(faction, MEM_RACIST)
	var has_racist := false
	for m: Dictionary in racist_mems:
		if String(m.get("subject", "")) == pf:
			has_racist = true
	if has_racist:
		match voice:
			"blunt": return "\"Sorry? SORRY? You don't get to say THAT word and say sorry.\""
			"elegant": return "\"Some words cannot be unsaid. But... we hear your remorse.\""
			"mischievous": return "\"Apology NOT accepted. That one? Never.\""
			"cold": return "\"The dead remember. Always.\""
			_: return "\"We acknowledge your words. Trust must be rebuilt.\""
		# Small positive shift — they're trying.
		remember(faction, MEM_MESSAGE, pf, "Player apologized.", 0.1)
	match voice:
		"blunt": return "\"Eh. Fine. Don't do it again.\""
		"elegant": return "\"Apology accepted. Let us move forward.\""
		"mischievous": return "\"Apology accepted! That'll be 50 gold. Kidding! ...Mostly.\""
		"cold": return "\"Your contrition is noted.\""
		_: return "\"Very well.\""
	remember(faction, MEM_MESSAGE, pf, "Player apologized.", 0.2)
	return "\"...\""


func _directive_hint(faction: String, voice: String, directive: String) -> String:
	match voice:
		"blunt":
			return "\"You want my %s focused? Say the word, boss.\"" % directive
		"elegant":
			return "\"Direct our %s efforts? A reasonable request from an ally.\"" % directive
		"mischievous":
			return "\"%s focus! Got it. That'll cost ya... kidding! Maybe.\"" % directive.capitalize()
		"cold":
			return "\"The dead shall %s. It is done.\"" % directive
		_:
			return "\"We can focus on %s. Give the command.\"" % directive
	return "\"...\""


func _default_hostile(voice: String) -> String:
	match voice:
		"blunt": return "\"Talk to my axe.\""
		"elegant": return "\"We have nothing to discuss.\""
		"mischievous": return "\"Oh, NOW you want to talk? Cute.\""
		"cold": return "\"Your words are wind.\""
		_: return "\"...\""
	return "\"...\""


func _default_reply(faction: String, voice: String, mood: String) -> String:
	if mood == "furious" or mood == "hostile":
		return _default_hostile(voice)
	if mood == "warm" or mood == "friendly":
		match voice:
			"blunt": return "\"Huh. Interesting. Go on.\""
			"elegant": return "\"Intriguing. Elaborate.\""
			"mischievous": return "\"Ooh, tell me more!\""
			"cold": return "\"Continue.\""
			_: return "\"I see.\""
	match voice:
		"blunt": return "\"Hmph. What do you want?\""
		"elegant": return "\"Yes?\""
		"mischievous": return "\"And...?\""
		"cold": return "\"...\""
		_: return "\"Mm.\""
	return "\"...\""


func _ruler_short() -> String:
	var rn: String = _gs.ruler_name
	if rn == "":
		return "ruler"
	return rn


## --- Policy proposals ---------------------------------------------------

## Proposes a policy to a faction leader. Returns {ok, msg, accepted}.
## Policies: "trade", "alliance", "peace", "tribute".
func propose(faction: String, policy: String) -> Dictionary:
	var l: Dictionary = leader_of(faction)
	if l.is_empty():
		return {"ok": false, "msg": "No leader for that faction."}
	var pf: String = _gs.player_faction
	if faction == pf:
		return {"ok": false, "msg": "That's your own faction."}
	var mood: String = mood_toward(faction, pf)
	var diplo = _gs.diplomacy
	var accepted := false
	var msg := ""
	match policy:
		"trade":
			var res: Dictionary = diplo.sign_trade_agreement(pf, faction)
			accepted = bool(res.get("accepted", false))
			msg = String(res.get("msg", ""))
		"alliance":
			var res2: Dictionary = diplo.propose_alliance(pf, faction)
			accepted = bool(res2.get("accepted", false))
			msg = String(res2.get("msg", ""))
		"peace":
			var res3: Dictionary = diplo.make_peace(pf, faction)
			accepted = bool(res3.get("ok", false))
			msg = String(res3.get("msg", ""))
		"tribute":
			# Tribute is handled via the tribute UI; here we just gauge interest.
			accepted = mood in ["warm", "friendly", "neutral"]
			msg = _tribute_reply(faction, pf,
				String(l.get("voice", "")), mood)
		_:
			return {"ok": false, "msg": "Unknown policy: %s" % policy}
	# Leader remembers the proposal.
	remember(faction, MEM_POLICY, pf,
		"Player proposed %s: %s" % [policy, "accepted" if accepted else "rejected"],
		0.3 if accepted else -0.2)
	return {"ok": true, "accepted": accepted, "msg": msg,
		"leader_says": _policy_reaction(faction, policy, accepted)}


func _policy_reaction(faction: String, policy: String, accepted: bool) -> String:
	var voice: String = String(leader_of(faction).get("voice", ""))
	if accepted:
		match voice:
			"blunt": return "\"Done. Don't make me regret it.\""
			"elegant": return "\"It shall be so.\""
			"mischievous": return "\"Pleasure doing business!\""
			"cold": return "\"So it is written.\""
			_: return "\"Agreed.\""
	else:
		match voice:
			"blunt": return "\"No. Come back when you're serious.\""
			"elegant": return "\"We must decline. For now.\""
			"mischievous": return "\"Hmm, no. But I'm open to... incentives.\""
			"cold": return "\"Denied.\""
			_: return "\"Not at this time.\""
	return "\"...\""


## --- AI directives (commands) --------------------------------------------

## Issues a directive to a faction's AI. Only works if they trust you
## (allied/friendly) or are your vassal. Returns {ok, msg}.
func issue_command(faction: String, directive: String) -> Dictionary:
	var l: Dictionary = leader_of(faction)
	if l.is_empty():
		return {"ok": false, "msg": "No leader for that faction."}
	var pf: String = _gs.player_faction
	if faction == pf:
		return {"ok": false, "msg": "That's your own faction — command them directly."}
	if not directive in DIRECTIVES:
		return {"ok": false,
			"msg": "Unknown directive. Try: %s" % ", ".join(DIRECTIVES)}
	var diplo = _gs.diplomacy
	var rel: String = diplo.relation_state(pf, faction)
	var mood: String = mood_toward(faction, pf)
	# Gate: need allied/friendly, or they're scared of you (much weaker).
	var allowed := false
	var reason := ""
	if rel == "allied":
		allowed = true
		reason = "allied"
	elif rel == "friendly" and mood in ["warm", "friendly"]:
		allowed = true
		reason = "friendly"
	elif mood == "furious" or mood == "hostile":
		return {"ok": false,
			"msg": _default_hostile(String(l.get("voice", "")))}
	else:
		# Check power: if you're overwhelmingly stronger, they obey from fear.
		var my_str: float = diplo.military_strength(pf)
		var their_str: float = diplo.military_strength(faction)
		if my_str > their_str * 3.0 and their_str > 0.0:
			allowed = true
			reason = "fear"
	if not allowed:
		remember(faction, MEM_COMMAND, pf,
			"Player tried to command us (%s) — refused." % directive, -0.15)
		return {"ok": false,
			"msg": "\"You don't command us. Earn our trust first.\""}
	l["directive"] = directive
	l["directive_day"] = _gs.day_number
	l["directive_from"] = pf
	remember(faction, MEM_COMMAND, pf,
		"Player commanded: focus %s (%s)." % [directive, reason], 0.1)
	return {"ok": true, "msg": _command_accepted(faction, directive, reason)}


func _command_accepted(faction: String, directive: String, reason: String) -> String:
	var voice: String = String(leader_of(faction).get("voice", ""))
	var why := ""
	if reason == "fear":
		why = " (they're terrified of you)"
	match voice:
		"blunt":
			return "\"FINE. %s it is%s.\"" % [directive.capitalize(), why]
		"elegant":
			return "\"As allies, we shall direct our %s as you ask%s.\"" % [directive, why]
		"mischievous":
			return "\"%s focus! You got it, boss%s!\"" % [directive.capitalize(), why]
		"cold":
			return "\"It shall be done%s.\"" % why
		_:
			return "\"Understood%s.\"" % why
	return "\"...\""


## Returns the active directive for a faction ("" if none).
func get_directive(faction: String) -> String:
	return String(leader_of(faction).get("directive", ""))


## Clears a faction's directive.
func clear_directive(faction: String) -> void:
	var l: Dictionary = leader_of(faction)
	if not l.is_empty():
		l["directive"] = ""
		l["directive_from"] = ""


## Maps a directive to the AI director maneuver override.
static func maneuver_for_directive(directive: String) -> String:
	return String(DIRECTIVE_MANEUVER.get(directive, ""))


## --- Faction sovereignty: direct-control refusal ---------------------------
##
## Jeremy 2026-10-04: the player can ONLY control their own faction. Any
## attempt to directly order another faction's units/buildings is refused
## here — by that faction's leader, in their own voice. This is separate
## from issue_command() (the diplomacy channel): direct control is never
## allowed, allies included. Use issue_command for legitimate influence.

## Refusal lines per leader voice (1-2 short lines each). {faction} fills
## with the faction's display name.
const CONTROL_REFUSALS := {
	"blunt": [
		"\"You don't command the {faction}, little ruler.\"",
		"\"Cute. My warriors answer to ME.\"",
	],
	"diplomatic": [
		"\"I'm afraid you have no authority over our forces.\"",
		"\"Our troops answer to their own crown, not yours.\"",
	],
	"elegant": [
		"\"The {faction} do not take orders from foreign crowns.\"",
		"\"Your presumption is noted — and declined.\"",
	],
	"mischievous": [
		"\"Ooh, commanding OTHER people's armies? That's a premium service.\"",
		"\"Nice try, boss. Our troops cost extra. Everything costs extra.\"",
	],
	"cold": [
		"\"The dead obey only Morvain.\"",
		"\"Your command withers here.\"",
	],
}
const CONTROL_REFUSAL_FALLBACK := \
	"\"You have no authority over our forces.\""


## Picks the voiced refusal line for a faction (static — no GameState needed).
## Uses the faction's default voice (first pool candidate).
static func control_refusal_line(faction: String) -> String:
	var pool: Array = LEADER_POOLS.get(faction, [])
	var voice := ""
	if not pool.is_empty():
		voice = String((pool[0] as Dictionary).get("voice", ""))
	return refusal_line_for_voice(voice, faction)


## Refusal line for an explicit voice (lets the picked leader's own voice
## speak, not just the faction default).
static func refusal_line_for_voice(voice: String, faction: String) -> String:
	var lines: Array = CONTROL_REFUSALS.get(voice, [])
	if lines.is_empty():
		return CONTROL_REFUSAL_FALLBACK
	var line: String = String(lines[randi() % lines.size()])
	if line.contains("{faction}"):
		var fname: String = String(
			Config.FACTIONS.get(faction, {}).get("name", faction))
		line = line.replace("{faction}", fname.to_lower())
	return line


## Refuses a player direct-control attempt on this faction: logs the
## incident in leader memory (it colors future interactions) and speaks
## the refusal through the leader's channel. Returns the spoken line.
func refuse_direct_control(faction: String) -> String:
	var l: Dictionary = leader_of(faction)
	if l.is_empty():
		return CONTROL_REFUSAL_FALLBACK
	var line: String = refusal_line_for_voice(String(l.get("voice", "")), faction)
	remember(faction, MEM_COMMAND, _gs.player_faction,
		"Player tried to seize direct control of our forces — refused.", -0.2)
	message_player(faction, line)
	return line


## --- Leader-initiated messages ---------------------------------------------

## The leader messages the player (warnings, requests, threats).
## Routes through the phone's realistic-texting queue.
func message_player(faction: String, text: String) -> void:
	remember(faction, MEM_MESSAGE, _gs.player_faction,
		"Leader said to player: \"%s\"" % text, 0.0)
	var phone = _gs.phone_sys
	if phone == null:
		return
	phone.leader_message(faction, text)


## Proactive leader behavior: called daily from tick(). Leaders may
## message the player with warnings, requests, or reactions to game state.
func _daily_tick() -> void:
	var pf: String = _gs.player_faction
	var diplo = _gs.diplomacy
	for f: String in _leaders:
		if f == pf:
			continue
		var l: Dictionary = _leaders[f]
		var rel: String = diplo.relation_state(pf, f)
		# Jeremy 2026-10-06: leaders react in hearsay when the player does
		# notable things — relation changes get a personality-voiced rumor.
		var last_rel: String = String(l.get("_last_rel", ""))
		if last_rel != "" and last_rel != rel:
			_react_to_relation_change(f, last_rel, rel)
		l["_last_rel"] = rel
		# Signature rumor from the leader's own pool (rare — flavor).
		if randf() < 0.06:
			_seed_signature_rumor(f)
		var mood: String = mood_toward(f, pf)
		# At war and losing: may beg for peace (rare).
		if rel == "war" and randf() < 0.05:
			var my_str: float = diplo.military_strength(f)
			var pf_str: float = diplo.military_strength(pf)
			if my_str < pf_str * 0.4:
				message_player(f, _sue_for_peace(f))
		# Friendly and rich: may offer trade (rare).
		elif rel == "friendly" and randf() < 0.04:
			message_player(f, _offer_trade(f))
		# Furious: may send a threat (rare).
		elif mood == "furious" and randf() < 0.06:
			message_player(f, _threat(f))


## Seeds one of the leader's signature rumor lines into hearsay.
func _seed_signature_rumor(faction: String) -> void:
	var hs = _gs.get("hearsay")
	if hs == null or not hs.has_method("seed_rumor"):
		return
	var line: String = signature_rumor(faction)
	if line == "":
		return
	hs.seed_rumor(line, "leader", faction, 0.5)


## Personality-voiced hearsay reaction to a relation change with the player.
func _react_to_relation_change(faction: String, old_rel: String,
		new_rel: String) -> void:
	var hs = _gs.get("hearsay")
	var l: Dictionary = leader_of(faction)
	var lname: String = String(l.get("name", "The leader"))
	var voice: String = String(l.get("voice", ""))
	var line := ""
	if new_rel == "war" and old_rel != "war":
		remember(faction, MEM_WAR, _gs.player_faction,
			"War with the player began.", -0.6)
		match voice:
			"blunt":
				line = "%s is sharpening axes. Somebody's about to have a bad day." % lname
			"elegant":
				line = "%s has declared war, with great reluctance and terrible precision." % lname
			"mischievous":
				line = "%s just declared war. War bonds are already on sale, apparently." % lname
			"cold":
				line = "The dead march. %s has declared war, and the grave-yards are emptying." % lname
			_:
				line = "%s has declared war. The realm holds its breath." % lname
	elif old_rel == "war" and new_rel != "war":
		remember(faction, MEM_ALLIANCE, _gs.player_faction,
			"Peace with the player.", 0.4)
		match voice:
			"blunt":
				line = "%s grunts that the war is over. The taverns are already celebrating." % lname
			"elegant":
				line = "Peace, at last. %s speaks of a new chapter, gracefully." % lname
			"mischievous":
				line = "War's over! %s is already selling commemorative mugs." % lname
			"cold":
				line = "The dead return to their rest. %s has made peace — for now." % lname
			_:
				line = "%s has made peace. Bells ring across the realm." % lname
	elif new_rel == "allied":
		remember(faction, MEM_ALLIANCE, _gs.player_faction,
			"Alliance with the player.", 0.5)
		match voice:
			"blunt":
				line = "%s calls you battle-kin now. That's ogre for 'friend'." % lname
			"elegant":
				line = "%s has sworn an alliance — sealed with ancient rites." % lname
			"mischievous":
				line = "%s signed an alliance! The fine print is... extensive." % lname
			"cold":
				line = "An alliance with the dead. %s finds this... unprecedented." % lname
			_:
				line = "%s has allied with the player's faction." % lname
	if line != "" and hs != null and hs.has_method("seed_rumor"):
		hs.seed_rumor(line, "leader", faction, 0.75)


func _sue_for_peace(faction: String) -> String:
	var voice: String = String(leader_of(faction).get("voice", ""))
	match voice:
		"blunt": return "\"ENOUGH. We yield. Name your terms, damn you.\""
		"elegant": return "\"This war serves neither of us. Let us discuss peace.\""
		"mischievous": return "\"Okay okay, you win! Truce? I'll even throw in a discount!\""
		"cold": return "\"The dead are patient. But this war is... inefficient. Peace?\""
		_: return "\"We seek peace.\""
	return "\"...\""


func _offer_trade(faction: String) -> String:
	var voice: String = String(leader_of(faction).get("voice", ""))
	match voice:
		"blunt": return "\"Got steel. Want it?\""
		"elegant": return "\"Our merchants seek new markets. Perhaps a trade agreement?\""
		"mischievous": return "\"Psst. Trade deal. You want it. Trust me.\""
		"cold": return "\"We have... surplus. The living crave such things.\""
		_: return "\"Shall we trade?\""
	return "\"...\""


func _threat(faction: String) -> String:
	var voice: String = String(leader_of(faction).get("voice", ""))
	match voice:
		"blunt": return "\"I'm coming for you. Sleep with one eye open.\""
		"elegant": return "\"Your actions have consequences. Ours will be... measured.\""
		"mischievous": return "\"Just so you know? I've got a plan. A FUN plan.\""
		"cold": return "\"Death is coming. It wears your face.\""
		_: return "\"You will regret this.\""
	return "\"...\""


## --- Save/load ------------------------------------------------------------

func get_save_data() -> Dictionary:
	var out: Dictionary = {}
	for f: String in _leaders:
		var l: Dictionary = _leaders[f]
		out[f] = {
			"candidate": int(l.get("candidate", 0)),
			"memories": (l["memories"] as Array).duplicate(true),
			"mood": String(l.get("mood", "neutral")),
			"mood_intensity": float(l.get("mood_intensity", 0.0)),
			"directive": String(l.get("directive", "")),
			"directive_day": int(l.get("directive_day", 0)),
			"directive_from": String(l.get("directive_from", "")),
		}
	# Fallback memories for factions with no AI leader record (the player's
	# own faction). Keyed separately so load never builds an AI leader for
	# the player faction.
	if not _stateless_memories.is_empty():
		out["__stateless__"] = _stateless_memories.duplicate(true)
	return out


func load_save_data(data: Dictionary) -> void:
	_stateless_memories = (data.get("__stateless__", {}) as Dictionary).duplicate(true)
	for f: String in data:
		if f == "__stateless__":
			continue  # fallback memories, not a leader record
		var d: Dictionary = data[f]
		# Restore the picked candidate (don't re-roll the pool).
		# Overwrites any setup-picked leader — the save is authoritative.
		var pool: Array = LEADER_POOLS.get(f, [])
		var idx: int = clampi(int(d.get("candidate", 0)), 0,
			maxi(0, pool.size() - 1))
		if not pool.is_empty():
			var def: Dictionary = pool[idx]
			_leaders[f] = {
				"faction": f,
				"name": String(def.get("name", "Leader")),
				"title": String(def.get("title", "")),
				"voice": String(def.get("voice", "neutral")),
				"greeting": String(def.get("greeting", "")),
				"desc": String(def.get("desc", "")),
				"candidate": idx,
				"pfp": pfp_key_for(f, idx),
				"traits": (def.get("traits", {}) as Dictionary).duplicate(),
				"rumors": (def.get("rumors", []) as Array).duplicate(),
				"memories": [],
				"mood": "neutral",
				"mood_intensity": 0.0,
				"directive": "",
				"directive_day": 0,
				"directive_from": "",
				"_last_rel": "",
			}
		if not _leaders.has(f):
			continue
		var l: Dictionary = _leaders[f]
		l["memories"] = (d.get("memories", []) as Array).duplicate(true)
		l["mood"] = String(d.get("mood", "neutral"))
		l["mood_intensity"] = float(d.get("mood_intensity", 0.0))
		l["directive"] = String(d.get("directive", ""))
		l["directive_day"] = int(d.get("directive_day", 0))
		l["directive_from"] = String(d.get("directive_from", ""))
	# Backfill: saves from before leaders existed (or missing factions)
	# get a fresh pick — a faction is never left leaderless, so the
	# phone's Faction Leaders section is never empty on old saves.
	if _gs != null:
		for f2 in _gs.active_factions:
			var fs2 := String(f2)
			if fs2 == String(_gs.player_faction) or _leaders.has(fs2):
				continue
			_pick(fs2)
