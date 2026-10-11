class_name SimLikesDislikes
extends RefCounted
## Cursing Gnomes — NPC likes & dislikes (Jeremy 2026-10-04).
##
## Every NPC has opinions: 3-5 likes and 3-5 dislikes, deterministic per
## unit id (same id = same tastes, survives save/load with zero extra
## state). Faction-flavored pools (ogres love war, elves love nature,
## gnomes love pranks...) plus personal picks.
##
## When the player messages an NPC about a topic they feel strongly about,
## the NPC reacts OUT LOUD — "Oh I LOVE that!" / "Ugh, I hate that stuff" —
## and it feeds the full emotion engine:
##   like/bond    -> "happy" emotion + positive memory + mood up
##   offended/disgusted -> "angry" emotion + negative memory + mood down
## NPCs remember: greetings later callback what you said, grudges form
## when the mood tanks, and NPCs gossip to EACH OTHER about what you said
## (hearsay rumors + Squabble posts).
##
## Pure logic — no rendering, no input, no audio, no network.


## --- Topic table ------------------------------------------------------------
## id -> {label, keys}. Keys matched with word boundaries (case-insensitive).
const TOPICS := {
	"war": {"label": "war & fighting",
		"keys": ["war", "fight", "battle", "combat", "bloodshed", "warfare"]},
	"peace": {"label": "peace & quiet",
		"keys": ["peace", "truce", "ceasefire", "calm", "quiet"]},
	"gold": {"label": "gold & trading",
		"keys": ["gold", "trade", "trading", "coins", "money", "merchant", "rich", "profit"]},
	"jokes": {"label": "jokes & pranks",
		"keys": ["joke", "funny", "prank", "laugh", "haha", "lol", "humor"]},
	"food": {"label": "food & feasts",
		"keys": ["food", "feast", "meat", "pie", "ale", "drink", "eat", "dinner", "snack"]},
	"music": {"label": "music & dancing",
		"keys": ["music", "song", "sing", "dance", "dancing", "tune"]},
	"nature": {"label": "nature & forests",
		"keys": ["nature", "trees", "forest", "animals", "flowers", "garden", "river"]},
	"art": {"label": "art & beauty",
		"keys": ["art", "paint", "beautiful", "craft", "sculpture", "pretty"]},
	"magic": {"label": "magic",
		"keys": ["magic", "spell", "wizard", "enchant", "sorcery"]},
	"gossip": {"label": "gossip & secrets",
		"keys": ["gossip", "rumor", "secret", "heard", "scandal"]},
	"work": {"label": "hard work",
		"keys": ["work", "labor", "toil", "chores", "grind"]},
	"kindness": {"label": "kindness",
		"keys": ["thank", "thanks", "please", "kind", "sorry", "apolog"]},
	"rudeness": {"label": "rudeness",
		"keys": ["stupid", "dumb", "idiot", "shut up", "moron", "loser"]},
	"bragging": {"label": "bragging",
		"keys": ["i'm the best", "i am the best", "bow to me", "worship me", "greatest ruler", "all hail"]},
	"darkness": {"label": "darkness & silence",
		"keys": ["dark", "darkness", "silence", "silent", "night", "shadows"]},
}

## Faction-flavored taste pools (topic ids).
const FACTION_LIKES := {
	"ogres": ["war", "food", "bragging", "music", "gold"],
	"elves": ["nature", "art", "music", "peace", "kindness", "magic"],
	"gnomes": ["jokes", "gold", "gossip", "food", "art"],
	"humans": ["peace", "food", "gold", "kindness", "music"],
	"undead": ["darkness", "peace", "gossip", "magic"],
}
const FACTION_DISLIKES := {
	"ogres": ["peace", "art", "rudeness", "work"],
	"elves": ["war", "rudeness", "bragging", "darkness"],
	"gnomes": ["work", "rudeness", "darkness", "bragging"],
	"humans": ["war", "rudeness", "darkness", "gossip"],
	"undead": ["music", "jokes", "kindness", "food"],
}

## Sentiment word lists.
const POS_WORDS := ["love", "like", "loves", "great", "awesome", "best",
	"amazing", "wonderful", "fantastic", "enjoy", "adore", "favorite"]
const NEG_WORDS := ["hate", "hates", "dislike", "awful", "worst", "terrible",
	"stupid", "dumb", "boring", "despise", "loathe"]


## --- Per-NPC tastes ---------------------------------------------------------

## Deterministic likes/dislikes for a unit: {likes: [ids], dislikes: [ids]}.
## 3-5 each. Seeded from unit id (offset from the personality seed so the
## rolls don't correlate with traits).
static func for_unit(unit: Dictionary) -> Dictionary:
	var uid: int = int(unit.get("id", 0))
	var faction: String = String(unit.get("faction", "gnomes"))
	var rng := RandomNumberGenerator.new()
	rng.seed = uid * 7919 + 777
	var likes: Array = []
	var dislikes: Array = []
	var fl: Array = FACTION_LIKES.get(faction, FACTION_LIKES["gnomes"])
	var fd: Array = FACTION_DISLIKES.get(faction, FACTION_DISLIKES["gnomes"])
	var all: Array = TOPICS.keys()
	# 2-3 from the faction pool, then 1-2 personal wildcards.
	var shuffled_fl := _shuffled(fl, rng)
	var n_fl: int = 2 + rng.randi_range(0, 1)
	for t in shuffled_fl:
		if likes.size() >= n_fl:
			break
		likes.append(t)
	var shuffled_all := _shuffled(all, rng)
	for t in shuffled_all:
		if likes.size() >= n_fl + 2:
			break
		if not likes.has(t) and not fd.has(t):
			likes.append(t)
	var shuffled_fd := _shuffled(fd, rng)
	var n_fd: int = 2 + rng.randi_range(0, 1)
	for t in shuffled_fd:
		if dislikes.size() >= n_fd:
			break
		dislikes.append(t)
	for t in shuffled_all:
		if dislikes.size() >= n_fd + 2:
			break
		if not dislikes.has(t) and not likes.has(t):
			dislikes.append(t)
	return {"likes": likes, "dislikes": dislikes}


## Jeremy 2026-10-06: player smear pipeline — how much NPC a personally
## likes/dislikes NPC-or-leader b, in [-1, 1]. Deterministic: a personal
## hash component (some same-faction pairs just don't get along) plus
## faction loyalty (same faction +, at war -, allied +) plus a
## defend-your-own-leader bump. b is a dict {id, faction, name, is_leader}.
## Pure logic — no state.
static func npc_stance(a: Dictionary, b: Dictionary, gs) -> float:
	var s := _pair_hash(int(a.get("id", 0)), int(b.get("id", 0)))
	var af := String(a.get("faction", ""))
	var bf := String(b.get("faction", ""))
	if af != "" and af == bf:
		s += 0.4
	elif gs != null and af != "" and bf != "":
		var dip = gs.get("diplomacy")
		if dip != null and dip.has_method("relation_state"):
			match String(dip.call("relation_state", af, bf)):
				"war":
					s -= 0.5
				"allied":
					s += 0.3
	if bool(b.get("is_leader", false)) and af != "" and af == bf:
		s += 0.3  # defend your own leader
	return clampf(s, -1.0, 1.0)


## Deterministic personal hash in [-0.5, 0.5] for a pair of ids.
## Symmetric: stance(a,b) == stance(b,a) on the personal component.
static func _pair_hash(a_id: int, b_id: int) -> float:
	var lo := mini(a_id, b_id)
	var hi := maxi(a_id, b_id)
	var s := "%d:%d" % [lo, hi]
	var h := 5381
	for i in range(s.length()):
		h = ((h << 5) + h + s.unicode_at(i)) & 0xFFFFFFFF
	return float(h % 1000) / 1000.0 - 0.5


static func _shuffled(arr: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


static func topic_label(tid: String) -> String:
	var t: Dictionary = TOPICS.get(tid, {})
	return String(t.get("label", tid))


static func likes_label_list(unit: Dictionary) -> Array:
	var out: Array = []
	for t in for_unit(unit).get("likes", []):
		out.append(topic_label(String(t)))
	return out


static func dislikes_label_list(unit: Dictionary) -> Array:
	var out: Array = []
	for t in for_unit(unit).get("dislikes", []):
		out.append(topic_label(String(t)))
	return out


## --- Reaction detection -----------------------------------------------------

## Scan player text for a felt topic. Returns {} or
## {type, topic, label, strength}. Types:
##   love       — you praised something they love
##   bond       — you bashed something they hate (shared hatred = bonding)
##   offended   — you bashed something they love
##   disgusted  — you praised something they hate
##   mention_like / mention_dislike — neutral mention of a felt topic
static func react(unit: Dictionary, text: String) -> Dictionary:
	var tastes: Dictionary = for_unit(unit)
	var likes: Array = tastes.get("likes", [])
	var dislikes: Array = tastes.get("dislikes", [])
	var t: String = _words(text)
	var topic: String = ""
	for tid in TOPICS.keys():
		var keys: Array = TOPICS[tid].get("keys", [])
		for k in keys:
			if (" " + String(k) + " ") in t:
				topic = String(tid)
				break
		if topic != "":
			break
	if topic == "":
		return {}
	var pos := _has_any(t, POS_WORDS)
	var neg := _has_any(t, NEG_WORDS)
	var loved: bool = likes.has(topic)
	var hated: bool = dislikes.has(topic)
	if not loved and not hated:
		return {}
	if loved and neg:
		return {"type": "offended", "topic": topic, "strength": 1.0}
	if loved:
		return {"type": "love", "topic": topic, "strength": 1.0}
	if hated and pos:
		return {"type": "disgusted", "topic": topic, "strength": 1.0}
	if hated and neg:
		return {"type": "bond", "topic": topic, "strength": 0.8}
	# Neutral mention of a felt topic — mild reaction.
	if hated:
		return {"type": "mention_dislike", "topic": topic, "strength": 0.4}
	return {"type": "mention_like", "topic": topic, "strength": 0.4}


## Normalize text for word matching: lowercase, punctuation -> spaces,
## padded with spaces so " art " won't match "heart".
static func _words(text: String) -> String:
	var t := text.to_lower()
	var out := ""
	for i in range(t.length()):
		var c := t[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == " " or c == "'":
			out += c
		else:
			out += " "
	return " " + out + " "


static func _has_any(t: String, words: Array) -> bool:
	for w in words:
		if (" " + String(w) + " ") in t:
			return true
	return false


## --- Explicit expressions ---------------------------------------------------
## The NPC SAYS how they feel, out loud. 10+ variants per type.

const LOVE_LINES: Array[String] = [
	"Oh I LOVE that!",
	"Yes! Finally, someone who gets it!",
	"Ha! You and me both, sire!",
	"Now THAT is what I like to hear!",
	"Oh, say more about that! I love it!",
	"You have excellent taste, my ruler!",
	"Music to my ears! I adore that!",
	"Finally! Someone with real taste around here!",
	"Oh that's wonderful! Tell me more!",
	"Yes yes YES! I love that so much!",
	"You just made my whole day saying that!",
	"I could talk about that all day long!",
]
const BOND_LINES: Array[String] = [
	"Right?? The WORST!",
	"Finally, someone with sense!",
	"Ha! I knew I liked you!",
	"Oh, we are going to get along JUST fine.",
	"Preach! I can't stand that either!",
	"Someone finally said it! Terrible stuff!",
	"You get it! You really get it!",
	"Ugh, don't even get me STARTED — oh wait, you did. Good.",
	"That's the spirit! Down with that!",
	"We should start a club for hating that.",
	"Say it louder for the folks in back!",
	"My new favorite ruler. Absolutely.",
]
const OFFENDED_LINES: Array[String] = [
	"Hey! I happen to LIKE that!",
	"Whoa, whoa — that's out of line!",
	"Excuse me?! That is RUDE!",
	"How dare you! I love that!",
	"Take that back right now!",
	"Wow. Okay. That one stung.",
	"You really just said that to my face?",
	"That is fighting talk where I come from!",
	"I can't believe you'd say that!",
	"Well! I never! ...Okay I have, but still!",
	"Say that again and we're going to have words. Sharp ones.",
	"Ouch. Right in the feelings.",
]
const DISGUSTED_LINES: Array[String] = [
	"You LIKE that?? Ugh.",
	"Ew. No. Absolutely not.",
	"That's disgusting and you should feel bad.",
	"Please never say that again.",
	"I just lost a little respect for you.",
	"Yuck. Hard pass.",
	"Oh no. Oh no no no.",
	"That's... a choice. A bad one.",
	"I need to wash my ears out now.",
	"Bold of you to admit that out loud.",
	"Nope. Not having it.",
	"I'd rather lick a troll's armpit.",
]
const MENTION_LIKE_LINES: Array[String] = [
	"Oh, that! I like that.",
	"Mm, good topic. I'm fond of that.",
	"That one's alright by me.",
	"Oh nice, I enjoy that.",
	"Good taste mentioning that.",
	"That always cheers me up a bit.",
	"Ah, a fine subject!",
	"I have warm feelings about that.",
	"Oh! I like where this is going.",
	"That puts a smile on my face.",
]
const MENTION_DISLIKE_LINES: Array[String] = [
	"Eh. Not my favorite thing.",
	"Mm. I'd rather not talk about that.",
	"That one rubs me the wrong way.",
	"Ugh, that. Let's move on.",
	"Not a fan, sire. Not a fan.",
	"That leaves a bad taste in my mouth.",
	"Can we... not? With that?",
	"I'd rather discuss literally anything else.",
	"Oh. That. ...Anyway.",
	"That subject and I do not get along.",
]


## Pick the explicit expression for a reaction, with a little faction voice.
static func express(unit: Dictionary, reaction: Dictionary) -> String:
	var rtype: String = String(reaction.get("type", ""))
	var pool: Array[String] = []
	match rtype:
		"love":
			pool = LOVE_LINES
		"bond":
			pool = BOND_LINES
		"offended":
			pool = OFFENDED_LINES
		"disgusted":
			pool = DISGUSTED_LINES
		"mention_like":
			pool = MENTION_LIKE_LINES
		"mention_dislike":
			pool = MENTION_DISLIKE_LINES
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


## --- Emotion / memory / mood effects ----------------------------------------

## Apply the full emotional fallout of a reaction. mem is the NPC's
## conversation memory dict (has "mood"). gs is GameState or test dict.
static func apply_effects(unit: Dictionary, reaction: Dictionary,
		mem: Dictionary, gs) -> void:
	var rtype: String = String(reaction.get("type", ""))
	var topic: String = String(reaction.get("topic", ""))
	var label: String = topic_label(topic)
	var emo := SimEmotion.new()
	# Jeremy 2026-10-04: moods — likes/dislikes reactions also nudge the
	# NPC's PERSISTENT mood (unit record), not just the conversation
	# memory's momentary mood score.
	var sm := SimMood.new()
	match rtype:
		"love":
			emo.notify(unit, "liked_topic")
			sm.nudge(unit, "happy", 0.30)
			_record(unit, "loved_topic", label, gs)
			_bump_mood(mem, 12.0)
			_note_topic(mem, "loved_topics", topic)
		"bond":
			emo.notify(unit, "liked_topic", 0.8)
			sm.nudge(unit, "happy", 0.20)
			_record(unit, "loved_topic", label, gs)
			_bump_mood(mem, 8.0)
			_note_topic(mem, "loved_topics", topic)
		"offended":
			emo.notify(unit, "disliked_topic")
			sm.nudge(unit, "angry", 0.35)
			_record(unit, "hated_topic", label, gs)
			_bump_mood(mem, -18.0)
			_note_topic(mem, "hated_topics", topic)
		"disgusted":
			emo.notify(unit, "disliked_topic", 0.9)
			sm.nudge(unit, "disgusted", 0.30)
			_record(unit, "hated_topic", label, gs)
			_bump_mood(mem, -12.0)
			_note_topic(mem, "hated_topics", topic)
		"mention_like":
			emo.notify(unit, "liked_topic", 0.4)
			sm.nudge(unit, "happy", 0.10)
			_bump_mood(mem, 4.0)
			_note_topic(mem, "loved_topics", topic)
		"mention_dislike":
			emo.notify(unit, "disliked_topic", 0.4)
			sm.nudge(unit, "angry", 0.15)
			_bump_mood(mem, -5.0)
			_note_topic(mem, "hated_topics", topic)
	# Flag for the daily gossip pass.
	unit["last_ld_reaction"] = {
		"type": rtype, "topic": topic, "label": label,
		"day": _day(gs),
	}
	# Grudge / fondness thresholds — persistent attitudes toward the ruler.
	var mood: float = float(mem.get("mood", 0.0))
	if mood <= -60.0:
		mem["grudge_ruler"] = true
	elif mood >= -20.0:
		mem["grudge_ruler"] = false
	if mood >= 60.0:
		mem["fond_ruler"] = true
	elif mood <= 20.0:
		mem["fond_ruler"] = false


static func _bump_mood(mem: Dictionary, delta: float) -> void:
	mem["mood"] = clampf(float(mem.get("mood", 0.0)) + delta, -100.0, 100.0)


static func _note_topic(mem: Dictionary, key: String, topic: String) -> void:
	var arr: Array = mem.get(key, [])
	if not arr.has(topic):
		arr.append(topic)
	mem[key] = arr


## Record a signed memory on the unit record (same schema as SimMemories,
## so relationship() picks it up). subject_id 0 = the ruler.
static func _record(unit: Dictionary, mtype: String, label: String, gs) -> void:
	var mems: Array = unit.get("memories", [])
	unit["memories"] = mems
	var game_time := 0.0
	if gs is GameState:
		game_time = (gs as GameState).game_time
	elif gs is Dictionary:
		game_time = float((gs as Dictionary).get("game_time", 0.0))
	var faction := ""
	if gs is GameState:
		faction = String((gs as GameState).player_faction)
	elif gs is Dictionary:
		faction = String((gs as Dictionary).get("player_faction", ""))
	mems.append({
		"type": mtype,
		"subject_id": 0,
		"subject_name": label,
		"faction": faction,
		"strength": 1.0,
		"game_time": game_time,
	})
	# Keep the array bounded (mirrors SimMemories cap behavior).
	while mems.size() > 40:
		mems.pop_front()


static func _day(gs) -> int:
	if gs is GameState:
		return int((gs as GameState).day_number)
	if gs is Dictionary:
		return int((gs as Dictionary).get("day_number", 0))
	return 0


## --- Greeting callbacks -------------------------------------------------------
## NPCs bring up what you said before. Grudges and fondness color the hello.

const GREET_LOVED: Array[String] = [
	"You remember when you said you love {t}? Still makes me grin.",
	"Hey! Still thinking about what you said about {t}. Loved that.",
	"Good to see you! I've been telling everyone you love {t}.",
	"Back again! You know I still smile about that {t} chat we had.",
]
const GREET_HATED: Array[String] = [
	"I'm still pissed about what you said about {t}.",
	"Oh. You. Still not over that {t} thing you said.",
	"What do YOU want? Still sore about {t}, if you must know.",
	"Yeah, hi. Don't think I forgot about {t}.",
]
const GREET_GRUDGE: Array[String] = [
	"Whatever you want, make it quick.",
	"Oh great. You again.",
	"Still mad, in case you were wondering.",
]
const GREET_FOND: Array[String] = [
	"My favorite ruler! How are you?",
	"Oh, it's YOU! Best part of my day!",
	"Come to chat? Always happy to see you!",
]


## Greeting flavor based on emotional memory. "" = no callback this time.
static func greeting_callback(unit: Dictionary, mem: Dictionary) -> String:
	if bool(mem.get("grudge_ruler", false)):
		return GREET_GRUDGE[randi() % GREET_GRUDGE.size()]
	if bool(mem.get("fond_ruler", false)) and randf() < 0.5:
		return GREET_FOND[randi() % GREET_FOND.size()]
	var loved: Array = mem.get("loved_topics", [])
	var hated: Array = mem.get("hated_topics", [])
	# Bring up a past topic ~45% of the time.
	if randf() > 0.45:
		return ""
	if not hated.is_empty() and (loved.is_empty() or randf() < 0.5):
		return GREET_HATED[randi() % GREET_HATED.size()].replace("{t}",
			topic_label(String(hated[randi() % hated.size()])))
	if not loved.is_empty():
		return GREET_LOVED[randi() % GREET_LOVED.size()].replace("{t}",
			topic_label(String(loved[randi() % loved.size()])))
	return ""


## --- NPC-to-NPC gossip --------------------------------------------------------
## NPCs talk to EACH OTHER about what the ruler said. Juicy reactions become
## hearsay rumors (hot ones reach the ruler as DMs) and Squabble posts.

const GOSSIP_TEMPLATES: Array[String] = [
	"Did you hear? The ruler told {n} they {v} {t} — {n} was {r}!",
	"Word is the ruler said they {v} {t} to {n}. {n} {r}, apparently.",
	"{n} won't shut up about it — the ruler {v} {t}, and {n} {r}!",
	"Between you and me: the ruler told {n} they {v} {t}. {n} was {r}.",
	"The taverns are buzzing — ruler {v} {t}, {n} {r}!",
]
const SQUABBLE_GOSSIP: Array[String] = [
	"Y'all the ruler told me they {v} {t}?? I {r}!! #{t} #royalcourt",
	"Can't believe it — ruler {v} {t}. I {r}. #gossip",
	"Today the ruler said they {v} {t} and honestly? I {r}. #{t}",
]


## Daily pass: gossip about recent like/dislike reactions. Call once per day.
## gs = GameState, phone = SimPhone (duck-typed).
static func daily_gossip(gs, phone) -> void:
	if gs == null or phone == null:
		return
	var units: Array = []
	if gs is GameState:
		units = (gs as GameState).units
	elif gs is Dictionary:
		units = (gs as Dictionary).get("units", []) as Array
	if units.is_empty():
		return
	var today: int = _day(gs)
	var candidates: Array = []
	for u in units:
		if not (u is Dictionary):
			continue
		var unit: Dictionary = u
		if not bool(unit.get("alive", true)):
			continue
		var lr: Dictionary = unit.get("last_ld_reaction", {})
		if lr.is_empty():
			continue
		# Only fresh gossip (today or yesterday).
		if today - int(lr.get("day", -999)) > 1:
			continue
		candidates.append(unit)
	# Cap the chatter: 3 rumors a day max.
	var n: int = mini(3, candidates.size())
	for i in range(n):
		var unit: Dictionary = candidates[randi() % candidates.size()]
		_spread_one(gs, phone, unit)


static func _spread_one(gs, phone, unit: Dictionary) -> void:
	var lr: Dictionary = unit.get("last_ld_reaction", {})
	var rtype: String = String(lr.get("type", ""))
	var label: String = String(lr.get("label", ""))
	var topic: String = String(lr.get("topic", ""))
	var positive: bool = rtype in ["love", "bond", "mention_like"]
	var verb: String = "love" if positive else "hate"
	var reaction_word: String = "thrilled" if positive else "furious"
	# Gossiper: a random same-faction NPC who isn't the subject.
	var faction: String = String(unit.get("faction", ""))
	var units: Array = []
	if gs is GameState:
		units = (gs as GameState).units
	elif gs is Dictionary:
		units = (gs as Dictionary).get("units", []) as Array
	var peers: Array = []
	for u in units:
		if u is Dictionary and int((u as Dictionary).get("id", 0)) != int(unit.get("id", 0)) \
				and String((u as Dictionary).get("faction", "")) == faction \
				and bool((u as Dictionary).get("alive", true)):
			peers.append(u)
	if peers.is_empty():
		return
	var gossiper: Dictionary = peers[randi() % peers.size()]
	var gname: String = SimPersonality.display_name(gossiper)
	var uname: String = SimPersonality.display_name(unit)
	var text: String = GOSSIP_TEMPLATES[randi() % GOSSIP_TEMPLATES.size()] \
		.replace("{n}", uname).replace("{v}", verb) \
		.replace("{t}", label).replace("{r}", reaction_word)
	# Hearsay rumor (hot ones reach the ruler as a DM).
	if phone.hearsay != null:
		phone.hearsay.seed_rumor(text, "gossip", uname, 0.65, int(gossiper.get("id", -1)))
	# Sometimes it hits Squabble too.
	if randf() < 0.3:
		var post_text: String = SQUABBLE_GOSSIP[randi() % SQUABBLE_GOSSIP.size()] \
			.replace("{v}", verb).replace("{t}", topic) \
			.replace("{r}", reaction_word)
		phone.npc_post(gossiper, post_text, "gossip")
	# Clear so it doesn't gossip forever.
	unit["last_ld_reaction"] = {}