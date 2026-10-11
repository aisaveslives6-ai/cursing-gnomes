class_name SimSocialLife
extends RefCounted
## Cursing Gnomes — visible NPC social life (Jeremy 2026-10-11).
##
## NPCs DM each other, argue in Squabble threads, and gossip in visible
## chains — the social sim out in the open instead of behind the curtain.
## Plus conversational memory with key triggers (Jeremy 2026-10-11):
##
##   DISLIKE MEMORIES, shaped exactly:
##     {quote, speaker, listener_reaction, emotional_weight, decay}
##   When NPC A says something NPC B dislikes, B stores the VERBATIM quote
##   plus B's reaction — and it ACTUALLY MATTERS: B is colder to A, won't
##   do favors for A, may confront A, and tells others (framed by B's
##   attitude toward A).
##
##   SECONDHAND GOSSIP WITH SOURCE ATTITUDES: NPCs tell the player AND
##   each other what other NPCs said — "You hear what Brak said? He said
##   '<quote>'. Can you believe that?" — and the LISTENER reacts based on
##   their own likes/dislikes of the ORIGINAL speaker: like -> defend,
##   hate -> pile on, neutral -> judgy-neutral. Reaction = f(quote) x
##   (relationship to speaker), never random.
##
##   TALKING ABOUT IT: NPCs discuss memories with the player (DMs) and
##   with each other (visible threads). Memories decay; hot ones stick;
##   confrontations resolve or escalate them.
##
## Budgets (Jeremy's explicit requirement — cooldowns so 240 NPCs never
## bog the system down): everything runs on the DAY tick, never per-frame.
## Per-NPC initiation cooldown, global per-day action cap, capped threads,
## capped memories per NPC, decayed trivia. Pure logic — no rendering.

## --- budgets ---------------------------------------------------------------
const MAX_ACTIONS_PER_DAY := 12   # global cap: DM threads + arguments +
								  # chains + secondhand + confronts + resurfaces
const NPC_COOLDOWN_DAYS := 2      # one NPC initiates at most every 2 days
const DM_THREADS_PER_DAY := 3
const ARGUMENTS_PER_DAY := 2
const CHAINS_PER_DAY := 2
const SECONDHAND_PER_DAY := 3
const MAX_THREADS := 24           # eavesdroppable DM threads kept
const MAX_MSGS_PER_THREAD := 20
const THREAD_EXPIRE_DAYS := 7

## --- memory ----------------------------------------------------------------
## Jeremy's exact shape: quote (verbatim), speaker, listener_reaction,
## emotional_weight, decay. Extras: kind, liked, hot, about_id, day.
const MAX_MEMORIES_PER_NPC := 10
const DISLIKE_DECAY := 0.25       # emotional weight lost per day
const HOT_WEIGHT := 6.0           # at/above this the memory never fully fades
const HOT_FLOOR := 1.5            # hot memories stick at this floor
const CONFRONT_WEIGHT := 4.0      # dislike this heavy may trigger confrontation
const COLD_WEIGHT := 2.0          # at/above: colder replies, no favors, no defense

const KIND_INSULT := "insult"
const KIND_OPINION := "opinion"
const KIND_PROMISE := "promise"
const KIND_FAVOR := "favor"
const KIND_EVENT := "event"
const KIND_KIND := "kind"


## --- line pools (all offline/scripted; {a}/{b} filled per speaker) ----------
## DM openers: [text, kind]. {rumor} = hot rumor snippet.
const DM_OPENERS: Array = [
	["Did you hear? {rumor}", KIND_EVENT],
	["They say {rumor} — you believe it?", KIND_EVENT],
	["The Gazette won't print this, but {rumor}", KIND_EVENT],
	["Tavern tonight? First round's on me.", KIND_KIND],
	["You looked tired at the muster. Everything alright?", KIND_KIND],
	["Saved you a seat at the feast. Don't be late.", KIND_KIND],
	["I owe you 50 gold from dice night. Friday, I swear it.", KIND_FAVOR],
	["Cover my watch shift tomorrow? I'll owe you one.", KIND_FAVOR],
	["I'll bring the good ale to the feast. Sworn on my beard.", KIND_PROMISE],
	["I'll talk to the guild master about your apprenticeship. Promise.", KIND_PROMISE],
	["You're still wrong about the harvest rota, and everyone knows it.", KIND_INSULT],
	["I've seen smarter moss on the north wall.", KIND_INSULT],
	["You couldn't organize a feast in a bakery.", KIND_INSULT],
	["The war was wrong. There, I said it.", KIND_OPINION],
	["Ogre stout beats elf wine and I'll die on this hill.", KIND_OPINION],
	["The council couldn't find its own backside with both hands.", KIND_OPINION],
]

const REPLIES_WARM: Array = [
	"Ha! Good to hear from you.",
	"Agreed, a hundred percent.",
	"You're a good sort, you know that?",
	"Meet me at the tavern and tell me more.",
]
const REPLIES_NEUTRAL: Array = [
	"Huh. Noted.",
	"Interesting. Anyway —",
	"I'll think about it.",
	"Sure. Sure.",
]
const REPLIES_COLD: Array = [
	"Mm.",
	"Is that all?",
	"Don't.",
	"I've got work.",
]
const REPLIES_HOSTILE: Array = [
	"Say that to my face, coward.",
	"You're lucky the watch is nearby.",
	"Keep talking. I'm writing all of this down.",
	"Oh, it's ON now.",
]

const DISLIKE_REACTIONS: Array = [
	"That stung. Noted.",
	"Remembered. All of it.",
	"Oh, we're doing this? Fine.",
	"I'll pretend I didn't hear that. I did.",
]

const CONFRONT_OPENERS: Array = [
	"We need to talk about what you said.",
	"You told everyone '{q}'. Really?",
	"I heard what you said about me. Explain.",
]
const CONFRONT_RESOLVE: Array = [
	"Fine. We're good. Don't do it again.",
	"Apology accepted. Barely.",
	"Water under the bridge. A VERY rickety bridge.",
]
const CONFRONT_ESCALATE: Array = [
	"Oh, it's like that? Remember this day.",
	"We're done being friendly. Done.",
	"You'll regret those words. Count on it.",
]

const SECONDHAND_TO_PLAYER: Array = [
	"You hear what {sp} said? They said '{q}'. Can you believe that?",
	"Just thought you should know — {sp} said '{q}'.",
	"Word is {sp} told everyone '{q}'. Thought the crown should hear it.",
]
const SECONDHAND_TO_NPC: Array = [
	"You hear what {sp} said? '{q}'. Can you believe that?",
	"So {sp} is going around saying '{q}'. Wild.",
	"Did {sp} tell you? They said '{q}'.",
]
const REACT_DEFEND: Array = [
	"{sp}'s got a point, honestly.",
	"Leave {sp} alone — they're right.",
	"I'll defend {sp} on this one.",
]
const REACT_PILEON: Array = [
	"Typical {sp}.",
	"Of course THEY'D say that.",
	"{sp} would say that, wouldn't they.",
]
const REACT_NEUTRAL: Array = [
	"Hmm. That's certainly a take.",
	"Bold words. We'll see.",
	"Not my business. Probably.",
]

const ARGUE_DISAGREE: Array = [
	"Hard disagree. That's not how it happened.",
	"Absolute nonsense, and you know it.",
	"Read a book. Any book.",
]
const ARGUE_PILEON: Array = [
	"This. {author} has no idea what they're talking about.",
	"Finally someone said it. {author} is wrong.",
]
const ARGUE_DEFEND: Array = [
	"{author}'s right and I'll die on this hill.",
	"Leave {author} alone — they've got a point.",
]
const ARGUE_MEDIATE: Array = [
	"Everybody breathe. Tavern. One hour. Be there.",
	"Okay, okay — nobody's getting cursed over a post.",
]

const RESURFACE_LINES: Array = [
	"You said '{q}' — still true?",
	"Remember when you told me '{q}'? What changed?",
	"About that thing you said — '{q}'. Been thinking about it.",
]
const RESURFACE_PROMISE: Array = [
	"You promised '{q}' — did it happen?",
	"Still waiting on '{q}'. Just saying.",
]

const OVERHEARD_POSTS: Array = [
	"🍵 Overheard: {a} told {b} '{q}' — {b} was NOT having it. #drama",
	"🍵 Tavern talk: {a} and {b} went at it. '{q}' were the fighting words. #drama",
]

const RUMOR_FALLBACKS: Array = [
	"the miller's goat got loose again",
	"the watch found someone's boots on the roof",
	"the tavern's raising ale prices",
]


var _gs  # GameState (duck-typed)
var _phone  # SimPhone
var state: Dictionary


func _init(phone) -> void:
	_phone = phone
	_gs = phone._gs
	if not _phone.state.has("social_life"):
		_phone.state["social_life"] = {
			"threads": {},
			"dislikes": {},
			"cooldowns": {},
			"action_day": -1,
			"actions": 0,
			"chain_posts": {},
		}
	state = _phone.state["social_life"]


## --- daily orchestration ----------------------------------------------------

func daily_tick(day: int) -> void:
	_reset_day(day)
	_decay_memories(day)
	_prune_threads(day)
	var units := _eligible_units()
	if units.is_empty():
		return
	for i in DM_THREADS_PER_DAY:
		if not _use_action():
			break
		_dm_thread_tick(day, units)
	for i in ARGUMENTS_PER_DAY:
		if not _use_action():
			break
		_argument_tick(day, units)
	for i in CHAINS_PER_DAY:
		if not _use_action():
			break
		_chain_tick(day, units)
	for i in SECONDHAND_PER_DAY:
		if not _use_action():
			break
		_secondhand_tick(day, units)
	if _use_action():
		_confront_tick(day, units)
	if _use_action():
		_resurface_tick(day, units)
	if _use_action():
		_overheard_tick(day)


func _reset_day(day: int) -> void:
	if int(state.get("action_day", -1)) != day:
		state["action_day"] = day
		state["actions"] = 0


## Global per-day budget. Returns false when the day's social budget is spent.
func _use_action() -> bool:
	if int(state.get("actions", 0)) >= MAX_ACTIONS_PER_DAY:
		return false
	state["actions"] = int(state.get("actions", 0)) + 1
	return true


func _eligible_units() -> Array:
	var out: Array = []
	var units: Array = _gs.units
	for u in units:
		if not (u is Dictionary):
			continue
		var ud: Dictionary = u
		if not bool(ud.get("alive", true)):
			continue
		if _phone.is_blocked(int(ud.get("id", 0))):
			continue
		out.append(ud)
	return out


## Per-NPC initiation cooldown: one social initiation per NPC per 2 days.
func _can_initiate(uid: int, day: int) -> bool:
	var last := int((state.get("cooldowns", {}) as Dictionary).get(str(uid), -999))
	return day - last >= NPC_COOLDOWN_DAYS


func _mark_initiated(uid: int, day: int) -> void:
	(state["cooldowns"] as Dictionary)[str(uid)] = day


## Pick a random eligible pair where the initiator is off cooldown.
func _pick_pair(units: Array, day: int) -> Array:
	var tries := 0
	while tries < 12:
		tries += 1
		var a: Dictionary = units[randi() % units.size()]
		var b: Dictionary = units[randi() % units.size()]
		if int(a.get("id", 0)) == int(b.get("id", 0)):
			continue
		if not _can_initiate(int(a.get("id", 0)), day):
			continue
		return [a, b]
	return []


func _thread_key(aid: int, bid: int) -> String:
	return "uu%d_%d" % [mini(aid, bid), maxi(aid, bid)]


func _store_thread(aid: int, bid: int, day: int, kind: String,
		msgs: Array) -> Dictionary:
	var threads: Dictionary = state["threads"]
	# Cap: prune oldest threads past the cap.
	while threads.size() >= MAX_THREADS:
		var oldest_key := ""
		var oldest_day := 1 << 30
		for k in threads:
			var td: int = int((threads[k] as Dictionary).get("day", 0))
			if td < oldest_day:
				oldest_day = td
				oldest_key = str(k)
		if oldest_key == "":
			break
		threads.erase(oldest_key)
	var key := _thread_key(aid, bid)
	var th: Dictionary = {
		"key": key, "a_id": aid, "b_id": bid, "day": day, "kind": kind,
		"messages": msgs.slice(0, MAX_MSGS_PER_THREAD),
	}
	threads[key] = th
	return th


func _prune_threads(day: int) -> void:
	var threads: Dictionary = state["threads"]
	var dead: Array = []
	for k in threads:
		if day - int((threads[k] as Dictionary).get("day", day)) > THREAD_EXPIRE_DAYS:
			dead.append(k)
	for k in dead:
		threads.erase(k)


## Recent drama threads for the eavesdrop UI (newest first, capped).
func drama_threads() -> Array:
	var arr: Array = (state.get("threads", {}) as Dictionary).values()
	arr.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return int(x.get("day", 0)) > int(y.get("day", 0)))
	var out: Array = []
	for th in arr.slice(0, 8):
		var td: Dictionary = th
		var a: Dictionary = _gs.get_unit(int(td.get("a_id", 0)))
		var b: Dictionary = _gs.get_unit(int(td.get("b_id", 0)))
		var msgs: Array = td.get("messages", [])
		var preview := ""
		if not msgs.is_empty():
			preview = str((msgs[msgs.size() - 1] as Dictionary).get("text", ""))
		out.append({
			"key": str(td.get("key", "")),
			"a_name": SimPersonality.display_name(a) if not a.is_empty() else "?",
			"b_name": SimPersonality.display_name(b) if not b.is_empty() else "?",
			"a_id": int(td.get("a_id", 0)),
			"b_id": int(td.get("b_id", 0)),
			"preview": preview,
			"day": int(td.get("day", 0)),
			"kind": str(td.get("kind", "")),
		})
	return out


func thread_messages(key: String) -> Array:
	var th: Dictionary = (state.get("threads", {}) as Dictionary).get(key, {})
	if th.is_empty():
		return []
	return th.get("messages", [])


## --- conversational memory ---------------------------------------------------
## Jeremy's exact shape: {quote, speaker, listener_reaction,
## emotional_weight, decay} + kind/liked/hot/about_id/day.

func _memories_of(listener_id: int) -> Array:
	var d: Dictionary = state.get("dislikes", {})
	var key := str(listener_id)
	if not d.has(key):
		d[key] = []
	return d[key]


## Public: all stored memories for an NPC (tests / UI).
func memories_of(listener_id: int) -> Array:
	return (_memories_of(listener_id) as Array).duplicate()


## Store a memory of something heard. Verbatim quote, never a summary.
func remember(listener_id: int, speaker: Dictionary, quote: String,
		kind: String, reaction: String, weight: float, day: int,
		about_id: int = 0) -> void:
	var mems := _memories_of(listener_id)
	var entry := {
		"quote": quote,
		"speaker_id": int(speaker.get("id", 0)),
		"speaker_name": SimPersonality.display_name(speaker),
		"reaction": reaction,
		"weight": weight,
		"decay": DISLIKE_DECAY,
		"day": day,
		"kind": kind,
		"liked": false,
		"hot": weight >= HOT_WEIGHT,
		"about_id": about_id,
	}
	mems.append(entry)
	# Bound: cap entries per NPC — drop the lowest-weight non-hot first,
	# never drop hot memories.
	while mems.size() > MAX_MEMORIES_PER_NPC:
		var drop := -1
		var drop_w := 1e30
		for i in mems.size():
			var e: Dictionary = mems[i]
			if bool(e.get("hot", false)):
				continue
			if float(e.get("weight", 0.0)) < drop_w:
				drop_w = float(e.get("weight", 0.0))
				drop = i
		if drop < 0:
			break  # all hot — keep them all
		mems.remove_at(drop)


## Decayed emotional weight of one entry at the given day.
func _entry_weight(e: Dictionary, day: int) -> float:
	var w := float(e.get("weight", 0.0)) \
		- float(e.get("decay", DISLIKE_DECAY)) * float(maxi(0, day - int(e.get("day", day))))
	if bool(e.get("hot", false)):
		w = maxf(w, HOT_FLOOR)  # hot memories stick — never fully forgotten
	return maxf(w, 0.0)


func _decay_memories(day: int) -> void:
	var d: Dictionary = state.get("dislikes", {})
	var dead_listeners: Array = []
	for lk in d:
		var mems: Array = d[lk]
		var dead: Array = []
		for i in mems.size():
			var e: Dictionary = mems[i]
			# Trivia prunes: cold, old, unliked entries fade out entirely.
			var age := day - int(e.get("day", day))
			if _entry_weight(e, day) <= 0.0 \
					or (age > 14 and float(e.get("weight", 0.0)) < 1.0
						and not bool(e.get("hot", false))):
				dead.append(i)
		for i in dead:
			mems.remove_at(i)
		if mems.is_empty():
			dead_listeners.append(lk)
	for lk in dead_listeners:
		d.erase(lk)


## Public: how much does listener dislike speaker right now (decayed sum)?
## Vote systems / diplomacy can query this — grudges that vote.
func dislike_weight(listener_id: int, speaker_id: int) -> float:
	var total := 0.0
	var day := int(_gs.day_number)
	for e in _memories_of(listener_id):
		var ed: Dictionary = e
		if int(ed.get("speaker_id", 0)) != speaker_id:
			continue
		if bool(ed.get("liked", false)):
			continue
		if str(ed.get("kind", "")) not in [KIND_INSULT, KIND_OPINION]:
			continue
		total += _entry_weight(ed, day)
	return total


func like_weight(listener_id: int, speaker_id: int) -> float:
	var total := 0.0
	var day := int(_gs.day_number)
	for e in _memories_of(listener_id):
		var ed: Dictionary = e
		if int(ed.get("speaker_id", 0)) != speaker_id:
			continue
		if not bool(ed.get("liked", false)):
			continue
		total += _entry_weight(ed, day)
	return total


func has_dislike(listener_id: int, speaker_id: int,
		threshold: float = COLD_WEIGHT) -> bool:
	return dislike_weight(listener_id, speaker_id) >= threshold


## --- text helpers ------------------------------------------------------------

func _pick(pool: Array):
	return pool[randi() % pool.size()]


func _fill2(text: String, a: Dictionary, b: Dictionary) -> String:
	var out := text.replace("{a}", SimPersonality.display_name(a))
	out = out.replace("{b}", SimPersonality.display_name(b))
	return out


func _rumor_snippet() -> String:
	var rumors: Array = []
	if _phone.hearsay != null:
		rumors = (_phone.hearsay.state.get("rumors", []) as Array).filter(
			func(r) -> bool: return float((r as Dictionary).get("heat", 0.0)) >= 0.5)
	if rumors.is_empty():
		return _pick(RUMOR_FALLBACKS)
	var r: Dictionary = rumors[randi() % rumors.size()]
	var t := str(r.get("text", "")).strip_edges()
	if t.length() > 90:
		t = t.left(87).strip_edges() + "..."
	return t


## Living Lexicon feed: NPCs using learned words in chatter is a natural
## teaching moment. Spread stays capped at 1/day (lexicon.note_overhear
## enforces the same last_spread_day cap as the existing daily_tick).
func _sprinkle_lexicon(text: String, speaker: Dictionary,
		hearer: Dictionary) -> String:
	if randf() > 0.25:
		return text
	var lex = _gs.get("lexicon")
	if lex == null or not lex.has_method("known_words_for"):
		return text
	var words: Array = lex.call("known_words_for",
		"u%d" % int(speaker.get("id", 0)))
	if words.is_empty():
		return text
	var w := str(words[randi() % words.size()])
	var out := "%s That's %s, that is." % [text, w]
	if lex.has_method("note_overhear"):
		lex.call("note_overhear", w,
			"u%d" % int(speaker.get("id", 0)),
			"u%d" % int(hearer.get("id", 0)))
	return out


func _stance(a: Dictionary, b: Dictionary) -> float:
	return SimLikesDislikes.npc_stance(a, b, _gs)


## --- NPC-to-NPC DM threads ---------------------------------------------------

func _dm_thread_tick(day: int, units: Array) -> void:
	var pair := _pick_pair(units, day)
	if pair.is_empty():
		return
	var a: Dictionary = pair[0]
	var b: Dictionary = pair[1]
	var aid := int(a.get("id", 0))
	var bid := int(b.get("id", 0))
	_mark_initiated(aid, day)
	var stance := _stance(a, b)
	var dw := dislike_weight(bid, aid)

	# Opener selection: dislikes change behavior. B won't do favors for
	# someone they dislike; heavy dislikes get the cold shoulder.
	var opener: Array
	var roll := randf()
	if dw >= CONFRONT_WEIGHT and roll < 0.5:
		opener = [_pick(CONFRONT_OPENERS).replace("{q}", _bite_of(bid, aid)), KIND_OPINION]
	elif stance <= -0.35 or (dw >= COLD_WEIGHT and roll < 0.6):
		opener = _pick([DM_OPENERS[9], DM_OPENERS[10], DM_OPENERS[11],
			DM_OPENERS[12], DM_OPENERS[13], DM_OPENERS[14]])
	else:
		opener = _pick(DM_OPENERS)
		# No favors for the disliked.
		var guard := 0
		while str(opener[1]) == KIND_FAVOR and dw >= COLD_WEIGHT and guard < 6:
			opener = _pick(DM_OPENERS)
			guard += 1
		# Grumpy pairs argue more.
		if stance <= -0.2 and randf() < 0.45:
			opener = _pick([DM_OPENERS[9], DM_OPENERS[10], DM_OPENERS[11],
				DM_OPENERS[12], DM_OPENERS[13], DM_OPENERS[14]])

	var otext := str(opener[0]).replace("{rumor}", _rumor_snippet())
	var okind := str(opener[1])
	otext = _sprinkle_lexicon(otext, a, b)
	var msgs: Array = [{"f": "a", "text": otext, "day": day, "kind": okind}]
	_hear(bid, a, otext, okind, day, stance)

	# B replies: warmth follows stance + dislike weight.
	var reply := _reply_for(b, a, stance, dw, day)
	reply = _sprinkle_lexicon(reply, b, a)
	var rkind := KIND_OPINION if _is_hostile_reply(reply) else KIND_EVENT
	msgs.append({"f": "b", "text": reply, "day": day, "kind": rkind})
	_hear(aid, b, reply, rkind, day, _stance(b, a))

	# 50%: A gets the last word.
	if randf() < 0.5:
		var counter := _reply_for(a, b, stance, dislike_weight(aid, bid), day)
		counter = _sprinkle_lexicon(counter, a, b)
		var ckind := KIND_OPINION if _is_hostile_reply(counter) else KIND_EVENT
		msgs.append({"f": "a", "text": counter, "day": day, "kind": ckind})
		_hear(bid, a, counter, ckind, day, stance)

	_store_thread(aid, bid, day, "dm", msgs)


## A short bite of what B dislikes about A, for confrontation openers.
func _bite_of(listener_id: int, speaker_id: int) -> String:
	var best := ""
	var best_w := -1.0
	var day := int(_gs.day_number)
	for e in _memories_of(listener_id):
		var ed: Dictionary = e
		if int(ed.get("speaker_id", 0)) != speaker_id:
			continue
		var w := _entry_weight(ed, day)
		if w > best_w:
			best_w = w
			best = str(ed.get("quote", ""))
	if best.length() > 60:
		best = best.left(57).strip_edges() + "..."
	return best


func _reply_for(speaker: Dictionary, other: Dictionary, stance: float,
		dw: float, _day: int) -> String:
	if dw >= CONFRONT_WEIGHT or stance <= -0.5:
		return _pick(REPLIES_HOSTILE)
	if dw >= COLD_WEIGHT or stance <= -0.2:
		return _pick(REPLIES_COLD)
	if stance >= 0.3:
		return _pick(REPLIES_WARM)
	return _pick(REPLIES_NEUTRAL)


func _is_hostile_reply(text: String) -> bool:
	return text in REPLIES_HOSTILE or text in REPLIES_COLD


## B hears A's line: store the memory (verbatim quote), form dislikes,
## feed the grudge ledger on insults.
func _hear(listener_id: int, speaker: Dictionary, text: String, kind: String,
		day: int, stance: float) -> void:
	var sid := int(speaker.get("id", 0))
	if kind == KIND_INSULT:
		remember(listener_id, speaker, text, kind, _pick(DISLIKE_REACTIONS),
			6.0, day)
		_phone.conversation.add_grudge(listener_id, 8.0, _gs)
	elif kind == KIND_OPINION and stance < -0.1:
		remember(listener_id, speaker, text, kind, _pick(DISLIKE_REACTIONS),
			3.0, day)
	elif kind == KIND_OPINION and stance >= 0.3:
		var mems := _memories_of(listener_id)
		mems.append({
			"quote": text,
			"speaker_id": sid,
			"speaker_name": SimPersonality.display_name(speaker),
			"reaction": "Good point. Remembering that.",
			"weight": 2.0, "decay": DISLIKE_DECAY, "day": day,
			"kind": kind, "liked": true, "hot": false, "about_id": 0,
		})
	elif kind in [KIND_PROMISE, KIND_FAVOR, KIND_EVENT, KIND_KIND]:
		remember(listener_id, speaker, text, kind, "Noted.",
			1.5 if kind == KIND_KIND else 2.0, day)


## --- Squabble arguments ------------------------------------------------------
## NPCs reply to each other's posts with disagreements, pile-ons, defenses —
## multi-NPC threads driven by real relations. Renders in the existing
## Squabble UI via phone.npc_comment (zero UI changes needed).

func _argument_tick(day: int, units: Array) -> void:
	var feed: Array = _phone.feed().slice(0, 8)
	if feed.is_empty():
		return
	var p: Dictionary = feed[randi() % feed.size()]
	var author_key := str(p.get("author_key", ""))
	var author: Dictionary = _phone._unit_for_key(author_key)
	if author.is_empty():
		return
	var aid := int(author.get("id", 0))

	# Challenger: someone who dislikes the author (stance or stored dislike).
	var challenger := _find_challenger(units, author, aid, day)
	if challenger.is_empty():
		return
	var cid := int(challenger.get("id", 0))
	_mark_initiated(cid, day)
	var ctext: String = _fill2(_pick(ARGUE_DISAGREE), challenger, author)
	ctext = _sprinkle_lexicon(ctext, challenger, author)
	if not _phone.npc_comment(int(p.get("id", 0)), challenger, ctext):
		return
	# The argument itself is memorable — verbatim.
	remember(aid, challenger, ctext, KIND_OPINION, _pick(DISLIKE_REACTIONS),
		3.5, day)

	# 40%: a pile-on from someone else who dislikes the author.
	if randf() < 0.4:
		var piler := _find_challenger(units, author, aid, day, cid)
		if not piler.is_empty():
			var ptext: String = _pick(ARGUE_PILEON).replace("{author}",
				SimPersonality.display_name(author))
			ptext = _sprinkle_lexicon(ptext, piler, author)
			_phone.npc_comment(int(p.get("id", 0)), piler, ptext)
			remember(aid, piler, ptext, KIND_OPINION,
				_pick(DISLIKE_REACTIONS), 3.0, day)

	# 35%: a defender who likes the author (never someone who dislikes them).
	if randf() < 0.35:
		var defender := _find_defender(units, author, aid, day, cid)
		if not defender.is_empty():
			var dtext: String = _pick(ARGUE_DEFEND).replace("{author}",
				SimPersonality.display_name(author))
			dtext = _sprinkle_lexicon(dtext, defender, author)
			_phone.npc_comment(int(p.get("id", 0)), defender, dtext)

	# 25%: a friendly mediator cools it down.
	if randf() < 0.25:
		var med := _find_mediator(units, day, [aid, cid])
		if not med.is_empty():
			_phone.npc_comment(int(p.get("id", 0)), med,
				_pick(ARGUE_MEDIATE))


func _find_challenger(units: Array, author: Dictionary, aid: int, day: int,
		exclude_id: int = 0) -> Dictionary:
	var tries := 0
	while tries < 15:
		tries += 1
		var u: Dictionary = units[randi() % units.size()]
		var uid := int(u.get("id", 0))
		if uid == aid or uid == exclude_id:
			continue
		if not _can_initiate(uid, day):
			continue
		if _stance(u, author) <= -0.2 or has_dislike(uid, aid):
			return u
	return {}


func _find_defender(units: Array, author: Dictionary, aid: int, day: int,
		exclude_id: int = 0) -> Dictionary:
	var tries := 0
	while tries < 15:
		tries += 1
		var u: Dictionary = units[randi() % units.size()]
		var uid := int(u.get("id", 0))
		if uid == aid or uid == exclude_id:
			continue
		if has_dislike(uid, aid, COLD_WEIGHT):
			continue  # the disliked get no defense
		if _stance(u, author) >= 0.3 or like_weight(uid, aid) >= 1.0:
			return u
	return {}


func _find_mediator(units: Array, day: int, exclude: Array) -> Dictionary:
	var tries := 0
	while tries < 10:
		tries += 1
		var u: Dictionary = units[randi() % units.size()]
		var uid := int(u.get("id", 0))
		if uid in exclude:
			continue
		if SimPersonality.trait_of(u, "friendly") >= 0.6:
			return u
	return {}


## --- visible gossip chains ---------------------------------------------------
## Hot rumors carry a who-told-whom chain (recorded by the hearsay hook).
## Surface it as a grapevine post the player can follow — with the
## distortion visible (the tale's grown in the telling).

func _chain_tick(day: int, units: Array) -> void:
	if _phone.hearsay == null:
		return
	var rumors: Array = _phone.hearsay.state.get("rumors", [])
	var posted: Dictionary = state.get("chain_posts", {})
	var best: Dictionary = {}
	var best_heat := 0.6
	for r in rumors:
		var rd: Dictionary = r
		var rid := str(rd.get("id", ""))
		if posted.has(rid):
			continue
		var chain: Array = rd.get("chain", [])
		if chain.size() < 2:
			continue
		var h := float(rd.get("heat", 0.0))
		if h > best_heat:
			best_heat = h
			best = rd
	if best.is_empty():
		return
	posted[str(best.get("id", ""))] = day
	state["chain_posts"] = posted

	var chain: Array = best.get("chain", [])
	var names: Array = []
	for edge in chain.slice(0, 4):
		var ed: Dictionary = edge
		var u: Dictionary = _gs.get_unit(int(ed.get("f", 0)))
		names.append(SimPersonality.display_name(u) if not u.is_empty() else "word got out")
	var first: Dictionary = _gs.get_unit(int((chain[0] as Dictionary).get("t", 0)))
	if not first.is_empty():
		names.push_front(SimPersonality.display_name(first))
	var text := str(best.get("text", "")).strip_edges()
	if text.length() > 110:
		text = text.left(107).strip_edges() + "..."
	var distort := ""
	var dn := int(best.get("distortions", 0))
	if dn > 0:
		distort = " (the tale's grown in the telling — %d retellings deep)" % dn
	var author: Dictionary = _gs.get_unit(int((chain[chain.size() - 1] as Dictionary).get("f", 0)))
	if author.is_empty():
		author = units[randi() % units.size()]
	_phone.npc_post(author,
		"🍇 GRAPEVINE: '%s' — passed along: %s.%s" % [text, " → ".join(names), distort],
		"grapevine")


## --- secondhand gossip with source attitudes ---------------------------------
## NPCs tell the player AND each other what other NPCs said — verbatim
## quotes. The LISTENER's reaction is a function of (quote) x (their own
## relationship to the ORIGINAL speaker): like -> defend, hate -> pile on,
## neutral -> judgy-neutral. Never random.

func _secondhand_tick(day: int, units: Array) -> void:
	var teller_info := _pick_memory_holder(units, day)
	if teller_info.is_empty():
		return
	var teller: Dictionary = teller_info[0]
	var mem: Dictionary = teller_info[1]
	var tid := int(teller.get("id", 0))
	var speaker_id := int(mem.get("speaker_id", 0))
	var speaker: Dictionary = _gs.get_unit(speaker_id)
	var speaker_name := str(mem.get("speaker_name", "?"))
	var quote := str(mem.get("quote", ""))
	if quote == "":
		return
	_mark_initiated(tid, day)

	# 40%: tell the PLAYER directly ("just thought you should know").
	if randf() < 0.4:
		var text: String = _pick(SECONDHAND_TO_PLAYER).replace("{sp}", speaker_name)
		text = text.replace("{q}", _short_quote(quote))
		_phone.npc_message(tid, text)
		return

	# Otherwise tell another NPC — visibly, in a thread.
	var audience := _pick_audience(units, tid, speaker_id, day)
	if audience.is_empty():
		return
	var aud: Dictionary = audience
	var aud_id := int(aud.get("id", 0))
	var tell_text: String = _pick(SECONDHAND_TO_NPC).replace("{sp}", speaker_name)
	tell_text = tell_text.replace("{q}", _short_quote(quote))
	tell_text = _sprinkle_lexicon(tell_text, teller, aud)

	# THE reaction: audience's own stance toward the ORIGINAL speaker.
	var st := _stance(aud, speaker) if not speaker.is_empty() else 0.0
	var react_pool: Array = REACT_NEUTRAL
	if st >= 0.3:
		react_pool = REACT_DEFEND
	elif st <= -0.3:
		react_pool = REACT_PILEON
	var react_text: String = _pick(react_pool).replace("{sp}", speaker_name)
	react_text = _sprinkle_lexicon(react_text, aud, teller)

	var msgs: Array = [
		{"f": "a", "text": tell_text, "day": day, "kind": KIND_EVENT},
		{"f": "b", "text": react_text, "day": day, "kind": KIND_OPINION},
	]
	_store_thread(tid, aud_id, day, "secondhand", msgs)

	# The audience now carries their own memory of the quote — colored by
	# how they feel about the speaker.
	if st <= -0.3:
		remember(aud_id, speaker if not speaker.is_empty() else teller,
			quote, KIND_OPINION, "Heard it secondhand. Still counts.", 2.0, day)
	elif st >= 0.3:
		remember(aud_id, speaker if not speaker.is_empty() else teller,
			quote, KIND_OPINION, "Defended them on this.", 1.5, day)


## Reaction pool for a listener's stance toward a quote's original speaker.
## Public for tests: reaction = f(relationship), never random.
func react_pool_for(stance: float) -> Array:
	if stance >= 0.3:
		return REACT_DEFEND
	if stance <= -0.3:
		return REACT_PILEON
	return REACT_NEUTRAL


func _pick_memory_holder(units: Array, day: int) -> Array:
	var d: Dictionary = state.get("dislikes", {})
	if d.is_empty():
		return []
	var keys: Array = d.keys()
	var tries := 0
	while tries < 10:
		tries += 1
		var lk := str(keys[randi() % keys.size()])
		var mems: Array = d[lk]
		if mems.is_empty():
			continue
		var u: Dictionary = _gs.get_unit(int(lk))
		if u.is_empty() or not bool(u.get("alive", true)):
			continue
		if not _can_initiate(int(lk), day):
			continue
		var mem: Dictionary = mems[randi() % mems.size()]
		if _entry_weight(mem, day) < COLD_WEIGHT:
			continue
		return [u, mem]
	return []


func _pick_audience(units: Array, tid: int, speaker_id: int, day: int) -> Dictionary:
	var tries := 0
	while tries < 12:
		tries += 1
		var u: Dictionary = units[randi() % units.size()]
		var uid := int(u.get("id", 0))
		if uid == tid or uid == speaker_id:
			continue
		return u
	return {}


func _short_quote(q: String) -> String:
	var s := q.strip_edges()
	if s.length() > 80:
		s = s.left(77).strip_edges() + "..."
	return s


## --- confrontations ----------------------------------------------------------
## Heavy dislikes may boil over: B confronts A directly. It resolves
## (weight slashed, grudge eased) or escalates (weight up, grudge up).

func _confront_tick(day: int, units: Array) -> void:
	var d: Dictionary = state.get("dislikes", {})
	var cands: Array = []
	for lk in d:
		for e in (d[lk] as Array):
			var ed: Dictionary = e
			if _entry_weight(ed, day) >= CONFRONT_WEIGHT \
					and not bool(ed.get("liked", false)):
				cands.append([lk, ed])
	if cands.is_empty() or randf() > 0.3:
		return
	var pick: Array = cands[randi() % cands.size()]
	var listener_id := int(pick[0])
	var mem: Dictionary = pick[1]
	var speaker_id := int(mem.get("speaker_id", 0))
	var b: Dictionary = _gs.get_unit(listener_id)
	var a: Dictionary = _gs.get_unit(speaker_id)
	if b.is_empty() or a.is_empty():
		return
	if not _can_initiate(listener_id, day):
		return
	_mark_initiated(listener_id, day)

	var quote := _short_quote(str(mem.get("quote", "")))
	var opener: String = _pick(CONFRONT_OPENERS).replace("{q}", quote)
	var msgs: Array = [{"f": "a", "text": opener, "day": day, "kind": KIND_OPINION}]

	# A's response: proud NPCs double down, others may fold.
	var proud := SimPersonality.trait_of(a, "proud") >= 0.6
	if proud or randf() < 0.4:
		var esc: String = _pick(CONFRONT_ESCALATE)
		msgs.append({"f": "b", "text": esc, "day": day, "kind": KIND_INSULT})
		mem["weight"] = float(mem.get("weight", 0.0)) + 2.0
		mem["hot"] = true
		_phone.conversation.add_grudge(listener_id, 6.0, _gs)
		msgs.append({"f": "a", "text": _pick(REPLIES_HOSTILE), "day": day,
			"kind": KIND_INSULT})
	else:
		var res: String = _pick(CONFRONT_RESOLVE)
		msgs.append({"f": "b", "text": res, "day": day, "kind": KIND_KIND})
		mem["weight"] = float(mem.get("weight", 0.0)) * 0.25
		_phone.conversation.add_grudge(listener_id, -4.0, _gs)
		msgs.append({"f": "a", "text": _pick(REPLIES_WARM), "day": day,
			"kind": KIND_KIND})

	_store_thread(listener_id, speaker_id, day, "confront", msgs)


## --- memory resurfacing ------------------------------------------------------
## NPCs bring up what was said before: "You said '<quote>' — still true?"

func _resurface_tick(day: int, units: Array) -> void:
	var d: Dictionary = state.get("dislikes", {})
	if d.is_empty() or randf() > 0.5:
		return
	var keys: Array = d.keys()
	var lk := str(keys[randi() % keys.size()])
	var mems: Array = d[lk]
	if mems.is_empty():
		return
	var mem: Dictionary = mems[randi() % mems.size()]
	if _entry_weight(mem, day) < 1.0:
		return
	var listener_id := int(lk)
	var speaker_id := int(mem.get("speaker_id", 0))
	var a: Dictionary = _gs.get_unit(listener_id)
	var b: Dictionary = _gs.get_unit(speaker_id)
	if a.is_empty() or b.is_empty():
		return
	if not _can_initiate(listener_id, day):
		return
	_mark_initiated(listener_id, day)
	var quote := _short_quote(str(mem.get("quote", "")))
	var pool: Array = RESURFACE_PROMISE \
		if str(mem.get("kind", "")) == KIND_PROMISE else RESURFACE_LINES
	var text: String = _pick(pool).replace("{q}", quote)
	var reply: String = _pick(REPLIES_NEUTRAL)
	_store_thread(listener_id, speaker_id, day, "resurface", [
		{"f": "a", "text": text, "day": day, "kind": KIND_EVENT},
		{"f": "b", "text": reply, "day": day, "kind": KIND_EVENT},
	])


## --- overheard summaries -----------------------------------------------------
## The juiciest recent drama becomes a Squabble post — visible eavesdropping
## through the existing feed (no UI changes needed for this surface).

func _overheard_tick(day: int) -> void:
	var threads: Array = (state.get("threads", {}) as Dictionary).values()
	var cands: Array = threads.filter(func(t) -> bool:
		var td: Dictionary = t
		return str(td.get("kind", "")) in ["dm", "confront", "secondhand"] \
			and int(td.get("day", 0)) == day)
	if cands.is_empty() or randf() > 0.6:
		return
	var th: Dictionary = cands[randi() % cands.size()]
	var msgs: Array = th.get("messages", [])
	if msgs.is_empty():
		return
	var first: Dictionary = msgs[0]
	var a: Dictionary = _gs.get_unit(int(th.get("a_id", 0)))
	var b: Dictionary = _gs.get_unit(int(th.get("b_id", 0)))
	if a.is_empty() or b.is_empty():
		return
	var text: String = _pick(OVERHEARD_POSTS)
	text = text.replace("{a}", SimPersonality.display_name(a))
	text = text.replace("{b}", SimPersonality.display_name(b))
	text = text.replace("{q}", _short_quote(str(first.get("text", ""))))
	_phone.npc_post(b, text, "overheard")
