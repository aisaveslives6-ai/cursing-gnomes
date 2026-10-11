## Cursing Gnomes — Hearsay Conversation Engine.
##
## Ported from HTML fix79's Hearsay system (msgrEngineReply + dependencies).
## The offline NPC dialogue engine that Jeremy calls "literally the most
## bad ass thing" — fluent, contextual conversations with personality,
## memory, mood, and the Living Lexicon.
##
## Architecture:
##   SimConversation.reply(unit, text, gs) -> {text, intent, effect}
##   - Intent parsing: keyword scoring + regex matching (MSGR_INTENTS)
##   - Response pools: faction-specific, anti-repetition (MSGR_RESPONSES)
##   - Conversation memory: per-NPC history, last topic, follow-ups
##   - Personality/mood: affects tone and response selection
##
## Usage:
##   var conv = SimConversation.new()
##   var result = conv.reply(unit_dict, "hello there", game_state)
##   print(result["text"])  # NPC's reply
class_name SimConversation
extends RefCounted


## Flow engine (state machine, threads, learning, questions) — preloaded so
## it resolves even when the editor's global class cache is stale.
const Flow := preload("res://scripts/sim/conversation_flow.gd")


## Common Tongue (seeded everyday-word reactions) — preloaded for the same
## reason as Flow above.
const CT := preload("res://scripts/sim/common_tongue.gd")


## Conversation memory per NPC (unit_id -> memory dict).
## Stored on the SimConversation instance; callers should keep one
## instance per game session (or serialize via save/load).
var _memories := {}


## Jeremy 2026-10-06: Living Lexicon restoration (HTML fix79 parity) — the
## shared vocabulary brain. World assigns game.lexicon here so words survive
## across sessions; standalone uses get a fresh private instance.
var lexicon := SimLexicon.new()


## Jeremy 2026-10-06: unhinged-trait brain — cuss-out bursts + DM spam for
## furious unhinged NPCs. Per-NPC no-repeat line tracking lives here.
var unhinged := SimUnhinged.new()


## Intents where the sentence's meaning must govern: a learned word that is
## merely mentioned never hijacks them (HTML _LEX_CONSEQ parity).
const _LEX_CONSEQUENTIAL := ["tribute_offer", "tribute_demand",
	"request_gold", "request_troops", "war_declare", "war_threaten",
	"war_surrender", "peace_offer", "alliance_propose", "trade_propose",
	"trade_accept", "trade_refuse", "name_set"]


## Recently used response variants per (unit_id, intent) for anti-repetition.
var _used_variants := {}


## Jeremy 2026-10-06: Common Tongue no-repeat ledger (word-reaction pools).
var _ct_used := {}


## Jeremy 2026-10-05: chatx citizen substrate — episodic memory (96),
## grudge/favor, affection scale. One per SimConversation session.
var chatx_cit := SimChatxCitizen.new()
## Jeremy 2026-10-05: chatx 22-mood affect engine (HTML fix79 parity).
var chatx_mood := SimChatxMood.new()


## Jeremy 2026-10-06 (LANE 4): per-NPC grudge ledger — the emotional arc.
## Hostile acts add points; they decay 0.5 per game day (a single insult
## fades in ~16 days, a war declaration in ~30 — mirroring HTML's 30-day
## recency window in p13CitGrudge). Apologies chip at it; when it drops
## under the personality-matched threshold the NPC forgives. Stored in
## the NPC's memory dict, so it persists through save/load.
const GRUDGE_DECAY_PER_DAY := 0.5
const GRUDGE_PTS := {"insult": 8.0, "threat": 10.0, "crude_direct": 6.0,
	"war_threaten": 5.0, "war_declare": 15.0}


## Jeremy 2026-10-06 (LANE 4): NPC-initiated rumor DMs — hot rumors about
## the player make NPCs message FIRST. Transient (not saved): per-NPC
## once-per-rumor flags live in conversation memory (saved), the daily
## counters reset each game day like the unhinged ambush bookkeeping.
const RUMOR_DM_HEAT := 0.75
const RUMOR_DM_CAP := 2
var _rumor_dm_day := -1
var _rumor_dm_sent := 0


## Current grudge strength for an NPC, decayed to the given game day.
func _grudge_now(mem: Dictionary, day: int) -> float:
	var pts := float(mem.get("grudge_pts", 0.0))
	var last := int(mem.get("grudge_day", day))
	var elapsed := maxi(0, day - last)
	if elapsed > 0 and pts > 0.0:
		pts = maxf(0.0, pts - float(elapsed) * GRUDGE_DECAY_PER_DAY)
		mem["grudge_pts"] = pts
		mem["grudge_day"] = day
	return pts


## Add (or subtract) grudge points after decaying to the current day.
func _grudge_add(mem: Dictionary, pts: float, day: int) -> float:
	var cur := _grudge_now(mem, day)
	cur = maxf(0.0, cur + pts)
	mem["grudge_pts"] = cur
	mem["grudge_day"] = day
	return cur


## Public: read an NPC's current grudge strength (decayed to today).
func grudge_strength(unit_id: int, gs) -> float:
	return _grudge_now(_get_memory(unit_id), _day_number(gs))


## Forgiveness threshold: proud NPCs hold out longer, friendly ones
## forgive easily (personality-matched apologies).
func _apology_threshold(unit: Dictionary) -> float:
	var t := 8.0
	var persona := SimPersonality.persona_of(unit)
	var proud := SimPersonality.trait_of(unit, "proud")
	var friendly := SimPersonality.trait_of(unit, "friendly")
	if proud >= 0.7 or persona in ["proud", "haughty", "scheming"]:
		t = 5.0
	if friendly >= 0.7 or persona in ["jolly", "earnest", "loyal"]:
		t = 11.0
	return t


## ---------------------------------------------------------------------------
## Public API
## ---------------------------------------------------------------------------

## Generate a reply from an NPC unit to player text.
## Returns: {text: String, intent: String, effect: Dictionary}
##   effect can contain: {type: "set_name", name: String}, {type: "mood", ...}, etc.
func reply(unit: Dictionary, text: String, gs) -> Dictionary:
	var unit_id := int(unit.get("id", 0))
	# Jeremy 2026-10-06: unhinged NPCs — furious + unhinged trait = cuss-out
	# burst. Runs before everything: they're too angry to converse. Memory
	# still records the exchange (they remember the fight).
	if SimUnhinged.should_cuss_out(self, unit):
		var res: Dictionary = unhinged.cuss_out_reply(self, unit, text,
			_ruler_name(gs))
		var umem := _get_memory(unit_id)
		_update_memory(unit_id, text, "unhinged_cussout", umem,
			String(res.get("text", "")))
		return res
	var mem := _get_memory(unit_id)
	var faction := String(unit.get("faction", "gnome"))

	# Normalize input
	var norm := _normalize(text)

	# Jeremy 2026-10-06: Living Lexicon first pass (HTML LexiconHook parity):
	# corrections ("no, I meant X") and pending definitions (the NPC asked
	# "what's a X?" and this is the answer) route here BEFORE intent parsing,
	# even when the definition contains game keywords.
	var npc_key := SimLexicon.npc_key_for(unit)
	var ruler_name := _ruler_name(gs)
	var day := _day_number(gs)
	if lexicon.wants_first(text) or lexicon.has_pending(npc_key):
		var lx := lexicon.handle_first_pass(text, norm, unit, ruler_name,
			day)
		if not lx.is_empty() and String(lx.get("text", "")) != "":
			var lx_text := lexicon.tone(String(lx["text"]), npc_key,
				faction)
			Flow.ensure_flow(mem)
			Flow.update(mem, unit, String(lx.get("intent", "lex_learn")),
				"")
			_update_memory(unit_id, text,
				String(lx.get("intent", "lex_learn")), mem, lx_text)
			lx["text"] = lx_text
			lx["flow"] = _flow_dict(mem)
			return lx

	# Parse intent. Living Lexicon: player-taught words are substituted with
	# their definitions first, so "I'm gonna zorp you" parses as a threat
	# (HTML _lxSubstParse parity). The raw norm is kept for word-about checks.
	var parsed := parse_intent(lexicon.subst_parse(norm))
	var intent: String = parsed.get("intent", "unclear")
	var score: float = parsed.get("score", 0.0)

	# Jeremy 2026-10-05: hearsay restoration — C29/C34 pre-route catches
	# sarcasm, wrong names, lies, self-talk, third-party insults,
	# challenges, and crude insults before the normal intent flow.
	var pre := SimConversationPreroute.preroute(unit, text, norm, intent,
		mem, gs)
	if not pre.is_empty() and not pre.has("_lie_detected"):
		var pre_text := _substitute(String(pre.get("text", "")), unit, gs)
		_update_memory(unit_id, text, String(pre.get("intent", intent)),
			mem, pre_text)
		pre["text"] = pre_text
		pre["flow"] = _flow_dict(mem)
		# Jeremy 2026-10-06: player smear pipeline — the player trash-talked
		# a third party; seed a real rumor with the player as source. The
		# conversation partner heard it firsthand (first knower).
		if pre.has("_smear"):
			_maybe_seed_smear(pre["_smear"], text, unit_id, gs)
		return pre
	# Lie detection returns a marker; build the full reply from the pool.
	if pre.has("_lie_detected"):
		var lie_pool := ConversationResponses.get_pool("c29_lie", faction)
		if not lie_pool.is_empty():
			var lie_text: String = lie_pool[randi() % lie_pool.size()]
			lie_text = lie_text.replace("{name}",
				String(unit.get("name", "friend")))
			_update_memory(unit_id, text, "c29_lie", mem, lie_text)
			return {"text": lie_text, "intent": "c29_lie",
				"effect": {"type": "mood", "delta": -2},
				"flow": _flow_dict(mem)}

	# Jeremy 2026-10-04: conversation flow — state machine, topic threads,
	# and learning (facts, communication style). Runs on every turn, all
	# paths below.
	Flow.ensure_flow(mem)
	var topic := Flow.detect_topic(unit, text, intent)
	var fact_ack := Flow.learn(norm, mem)
	var flow_state := Flow.update(mem, unit, intent, topic)

	# Handle follow-ups ("why?", "tell me more") against last topic
	if intent in ["followup_why", "followup_more", "followup_topic"]:
		var fr := _followup_reply(intent, mem, faction, gs, text)
		if not fr.is_empty():
			# Jeremy 2026-10-06 (LANE 4): follow-up frames carry tokens
			# ({name}, {said}) — resolve them like any other reply.
			fr = _substitute(fr, unit, gs, topic)
			_update_memory(unit_id, text, intent, mem, fr)
			return {"text": fr, "intent": intent, "effect": {},
				"flow": _flow_dict(mem)}

	# Handle name setting ("my name is X", "call me Y")
	if intent == "name_set":
		var name_result := _handle_name_set(unit, text, mem, gs)
		_update_memory(unit_id, text, intent, mem,
			String(name_result.get("text", "")))
		name_result["flow"] = _flow_dict(mem)
		return name_result

	# Jeremy 2026-10-06: Living Lexicon word-about (HTML LexiconMatch parity).
	# If the message is ABOUT a learned word ("what does zorp mean?"), the
	# NPC shows it off. A mere mention never triggers it — the sentence's
	# intent governs ("I'm gonna zorp your house" stays a threat).
	if score < 8.0 and not intent in _LEX_CONSEQUENTIAL:
		var lw := lexicon.match_word(norm)
		if lw != "":
			var wr := lexicon.word_reply(lw, unit, ruler_name)
			if wr != "":
				var wr_text := lexicon.tone(wr, npc_key, faction)
				Flow.ensure_flow(mem)
				Flow.update(mem, unit, "lex_word", "")
				_update_memory(unit_id, text, "lex_word", mem, wr_text)
				return {"text": wr_text, "intent": "lex_word",
					"effect": {}, "flow": _flow_dict(mem)}

	# Check for unknown words -> Living Lexicon teach moment.
	# Skipped when the NPC just learned a fact (don't ask "what's 'really'?").
	# Jeremy 2026-10-06: restored HTML LexiconHook fallback — learned facts,
	# fact callbacks, and the "what's a X?" vocab ask.
	if intent == "unclear" and fact_ack == "":
		# Jeremy 2026-10-06: Common Tongue (HTML CANDIDATE23 parity) —
		# seeded everyday words (slang, swears, anatomy, chitchat...) get a
		# real faction-voiced reaction BEFORE the "what's a X?" teach
		# fallback, so single words like "ass" never hit "I didn't
		# understand". insult_word maps to the insult intent (HTML parity)
		# so mood/affection react like a real insult.
		var ct := CT.react(text, faction, _ct_used)
		if not ct.is_empty():
			var ct_cat := String(ct.get("cat", ""))
			var ct_intent := "insult" if ct_cat == "insult_word" \
				else "ct_" + ct_cat
			Flow.ensure_flow(mem)
			Flow.update(mem, unit, ct_intent, "")
			if ct_intent == "insult":
				_chatx_affect(unit, unit_id, mem, "insult", text, gs)
			var ct_text := _substitute(String(ct.get("text", "")), unit,
				gs)
			ct_text = _apply_tone(ct_text, unit, mem)
			_update_memory(unit_id, text, ct_intent, mem, ct_text)
			return {"text": ct_text, "intent": ct_intent, "effect": {},
				"flow": _flow_dict(mem)}
		var la := lexicon.handle_fallback(text, norm, unit, ruler_name,
			day)
		if not la.is_empty() and String(la.get("text", "")) != "":
			var la_text := lexicon.tone(String(la["text"]), npc_key,
				faction)
			_update_memory(unit_id, text,
				String(la.get("intent", "lex_ask")), mem, la_text)
			la["text"] = la_text
			la["flow"] = _flow_dict(mem)
			return la

	# Get response from pool
	# Jeremy 2026-10-05: chatx affect — dialogue events drive the NPC's
	# persistent 22-mood emotional state (HTML chatxMoodEvent); the
	# exchange is recorded in their episodic memory and moves the
	# affection scale (HTML chatxMemRecord / msgrCitAffDelta).
	_chatx_affect(unit, unit_id, mem, intent, text, gs)
	# Jeremy 2026-10-05: hearsay restoration — insult escalation (HTML
	# C29_insultYouReply): repeat insults escalate through style+level
	# pools (c29_iyo_{rage,wit,cold,hurt,standard}_{1,2,3}).
	var response_text := ""
	if intent == "insult":
		response_text = SimConversationPreroute.insult_escalation(
			unit, mem, faction, gs)
	# Jeremy 2026-10-06: "what offended you?" — the NPC recalls the actual
	# insult from episodic memory instead of blanking.
	if intent == "insult_why":
		response_text = _insult_why_reply(unit, faction, mem, gs)
	# Jeremy 2026-10-06 (LANE 4): apologies are accepted or deflected
	# based on grudge strength + personality.
	if intent == "apology":
		response_text = _apology_reply(unit, faction, mem, gs)
	# Jeremy 2026-10-06 (LANE 4): compliments — affection up (see
	# _chatx_aff_delta) with a personality-matched reply.
	if intent == "compliment_npc":
		response_text = _compliment_reply(unit, faction, mem, gs)
	# Jeremy 2026-10-06 (LANE 4): world questions answered from live
	# game state. "Who rules the elves?" names the live faction leader;
	# peace/no-town variants mirror HTML's poolKey routing.
	if intent == "question_rulers":
		response_text = _rulers_answer(unit, text, faction, mem, gs)
	if intent == "question_wars" and _war_count(gs, faction) == 0:
		response_text = _pick_pool(intent, faction, unit, mem, gs,
			"question_wars_peace")
	if intent == "question_towns" and _town_count(gs, faction) == 0:
		response_text = _pick_pool(intent, faction, unit, mem, gs,
			"question_towns_none")
	# Jeremy 2026-10-08 (12h audit): C67 muster-roll parity — "troop
	# report" / "how many soldiers" answered from live unit counts.
	if intent == "question_troops":
		response_text = _muster_answer(unit, text, faction, mem, gs)
	if response_text == "":
		response_text = _pick_response(intent, faction, unit, mem, gs)

	# Jeremy 2026-10-04: likes/dislikes engine — the NPC reacts OUT LOUD
	# to topics they feel strongly about, and it feeds their emotion,
	# memory, and mood. Greetings also callback what you said before.
	if intent == "greeting":
		var cb := SimLikesDislikes.greeting_callback(unit, mem)
		if cb == "":
			# Flow fallback: "Last time we talked about X..."
			cb = Flow.session_callback(mem, faction)
		if cb != "":
			response_text = cb + " " + response_text
	var ld := SimLikesDislikes.react(unit, text)
	if not ld.is_empty():
		var expr: String = SimLikesDislikes.express(unit, ld)
		if expr != "":
			response_text = expr + " " + response_text
		SimLikesDislikes.apply_effects(unit, ld, mem, gs)

	# Apply personality/mood tone
	response_text = _apply_tone(response_text, unit, mem)

	# Jeremy 2026-10-04: mood replies — the NPC's persistent mood selects
	# from 100 mood-flavored replies, so the same conversation feels
	# different when they're happy vs. furious.
	response_text = _apply_mood_line(response_text, unit, mem)

	# Jeremy 2026-10-05: chatx mood voice — a strong persistent 22-mood
	# state (intensity >= 3) speaks in its own faction-voiced line and
	# may append a short mood aside (HTML chatxMoodLine/chatxMoodFlavor).
	response_text = _apply_chatx_mood(response_text, unit, mem, gs)

	# Jeremy 2026-10-04: conversation flow — fact acknowledgments, thread
	# references ("Back to war? Like I was saying..."), topic bridges
	# ("Speaking of which..."), questions back, reused learned words.
	response_text = Flow.enrich(mem, unit, faction, intent, topic, fact_ack,
		response_text, lexicon.simple_words())

	# Jeremy 2026-10-04: hearsay woven into Messenger — NPCs bring up
	# rumors/gossip during conversations. Rumors about the player get
	# confronted; other hot rumors get casually mentioned with personality.
	var gossip := _hearsay_gossip(unit, faction, mem, gs)
	if gossip != "":
		response_text += " " + gossip

	# Winding down: the closing line goes last.
	if flow_state == "closing":
		response_text += " " + Flow.closing_line(faction,
			Flow.style_voice(mem))

	# Substitute tokens ({name}, {ruler}, etc.)
	response_text = _substitute(response_text, unit, gs, topic)

	# Jeremy 2026-10-06: Living Lexicon tone (HTML LexiconTone parity) —
	# subtle mirroring of the player's writing style, applied last.
	response_text = lexicon.tone(response_text, npc_key, faction)

	_update_memory(unit_id, text, intent, mem, response_text)

	var flow_info := _flow_dict(mem)
	if flow_state == "closing":
		# Archive this session's topics for next time; start fresh.
		Flow.end_session(mem)

	return {"text": response_text, "intent": intent, "effect": {},
		"flow": flow_info}


## Jeremy 2026-10-04: hearsay in Messenger. Returns a gossip line to
## append, or "". Rumors about the player take priority (confrontation);
## otherwise hot rumors get a casual mention with personality flavor.
func _hearsay_gossip(unit: Dictionary, faction: String, mem: Dictionary,
		gs) -> String:
	if gs == null:
		return ""
	var phone = gs.get("phone_sys")
	if phone == null or phone.hearsay == null:
		return ""
	var hearsay = phone.hearsay
	var rumors: Array = hearsay.live_rumors(6)
	if rumors.is_empty():
		return ""
	var ruler: String = String(gs.ruler_name).to_lower()
	var pf: String = String(gs.player_faction)
	# Priority 1: rumors ABOUT the player — confront or comment.
	for r: Dictionary in rumors:
		var subj: String = String(r.get("subject", "")).to_lower()
		var rtext: String = String(r.get("text", ""))
		if subj == ruler or subj == pf or subj == "ruler" \
				or rtext.to_lower().contains(ruler):
			# Don't repeat the same confrontation.
			var gkey := "gossip_confronted_%d" % int(r.get("id", 0))
			if bool(mem.get(gkey, false)):
				continue
			mem[gkey] = true
			return _confront_rumor(unit, faction, r, rtext)
	# Priority 2: hot rumors get a casual mention (30% chance per reply).
	if randf() > 0.30:
		return ""
	var hot: Dictionary = rumors[0]
	var heat: float = float(hot.get("heat", 0.0))
	if heat < 0.4:
		return ""
	var hkey := "gossip_mentioned_%d" % int(hot.get("id", 0))
	if bool(mem.get(hkey, false)):
		return ""
	mem[hkey] = true
	return _mention_rumor(unit, faction, String(hot.get("text", "")))


## NPC confronts the player about a rumor involving them.
func _confront_rumor(unit: Dictionary, faction: String, rumor: Dictionary,
		rtext: String) -> String:
	var kind: String = String(rumor.get("kind", ""))
	# Racist scandal: everyone condemns.
	if kind == "scandal" or "racist" in rtext.to_lower():
		match faction:
			"ogres":
				return "Hey. Everyone's saying you're a racist now. Even WE think that's fucked up."
			"elves":
				return "The whispers reach even here. They say you spoke the unspeakable. Is it true?"
			"gnomes":
				return "Sooo... the whole realm's calling you racist. That's bad for business, friend."
			"undead":
				return "Death hears all. The living call you bigot. Interesting."
			_:
				return "People are saying things about you. Bad things. Racist things."
	# War rumors: react with personality.
	if kind == "war":
		match faction:
			"ogres":
				return "Heard there's war brewing. FINALLY, some excitement!"
			"elves":
				return "The winds whisper of war. Troubling."
			"gnomes":
				return "War rumors? That's terrible for trade. TERRIBLE."
			_:
				return "Everyone's talking about war. You heard anything?"
	# Default: bring it up neutrally.
	match faction:
		"ogres":
			return "Heard something interesting: %s" % _shorten(rtext)
		"elves":
			return "Perhaps you've heard: %s" % _shorten(rtext)
		"gnomes":
			return "Psst — word on the street: %s" % _shorten(rtext)
		"undead":
			return "The dead whisper: %s" % _shorten(rtext)
		_:
			return "Did you hear? %s" % _shorten(rtext)
	return ""


## NPC casually mentions a hot rumor with personality flavor.
func _mention_rumor(unit: Dictionary, faction: String, rtext: String) -> String:
	var short := _shorten(rtext)
	match faction:
		"ogres":
			return "Oh, did you hear? %s Wild, right?" % short
		"elves":
			return "The court gossips of nothing else: %s" % short
		"gnomes":
			return "Hot gossip: %s You didn't hear it from me!" % short
		"undead":
			return "Even the dead have heard: %s" % short
		"humans":
			return "Everyone in town is talking about this: %s" % short
		_:
			return "Have you heard? %s" % short
	return ""


## Shortens a rumor for conversational use.
static func _shorten(text: String) -> String:
	if text.length() <= 120:
		return text
	return text.left(117) + "..."


## Jeremy 2026-10-06 (LANE 4): NPC-initiated DMs. A hot rumor ABOUT the
## player makes an NPC message FIRST — "heard you torched Thornwall —
## true?" — instead of waiting to be asked. Called once per game day
## from SimPhone._on_day_changed. Hard rules: blocked NPCs stay
## completely silent (checked here AND in npc_message), one DM per NPC
## per rumor, rumors already confronted in-thread are skipped, global
## cap RUMOR_DM_CAP per day. Per-NPC flags live in conversation memory
## (saved); the daily counter is transient like the ambush bookkeeping.
func rumor_dm_opener(unit: Dictionary, rumor: Dictionary, gs) -> String:
	var faction := String(unit.get("faction", "gnome"))
	var mem := _get_memory(int(unit.get("id", 0)))
	var line := _pick_response("rumor_dm", faction, unit, mem, gs)
	line = line.replace("{rumor}", _shorten(String(rumor.get("text", ""))))
	return _substitute(line, unit, gs)


func rumor_dm_tick(gs, phone) -> int:
	var today := _day_number(gs)
	if _rumor_dm_day != today:
		_rumor_dm_day = today
		_rumor_dm_sent = 0
	if gs == null or phone == null or _rumor_dm_sent >= RUMOR_DM_CAP:
		return 0
	var hs = phone.hearsay
	if hs == null or not hs.has_method("live_rumors"):
		return 0
	var ruler := _ruler_name(gs).to_lower()
	var pfv = gs.get("player_faction")
	var pf := String(pfv).to_lower() if pfv != null else ""
	var uv = gs.get("units")
	var units: Array = uv if uv is Array else []
	if units.is_empty():
		return 0
	var sent := 0
	for r in hs.live_rumors(6):
		var rd: Dictionary = r
		if float(rd.get("heat", 0.0)) < RUMOR_DM_HEAT:
			continue
		var rid := int(rd.get("id", 0))
		var subj := String(rd.get("subject", "")).to_lower()
		var rtext := String(rd.get("text", ""))
		var about_player := subj == ruler or subj == pf or subj == "ruler" \
			or rtext.to_lower().contains(ruler)
		if not about_player:
			continue
		var cands: Array = []
		for u in units:
			var ud: Dictionary = u
			if not bool(ud.get("alive", false)):
				continue
			var uid := int(ud.get("id", 0))
			# Blocked NPCs are completely silent — never DM first.
			if phone.has_method("is_blocked") and bool(phone.call("is_blocked", uid)):
				continue
			var mem := _get_memory(uid)
			if bool(mem.get("rumor_dm_%d" % rid, false)):
				continue
			if bool(mem.get("gossip_confronted_%d" % rid, false)):
				continue
			cands.append(ud)
		if cands.is_empty():
			continue
		cands.shuffle()
		var chosen: Dictionary = cands[0]
		var cuid := int(chosen.get("id", 0))
		var cmem := _get_memory(cuid)
		var line := rumor_dm_opener(chosen, rd, gs)
		if line == "":
			continue
		cmem["rumor_dm_%d" % rid] = true
		phone.npc_message(cuid, line)
		# Record the opener in thread history so follow-ups ("why did
		# you say that?") resolve against it.
		_update_memory(cuid, "(messaged first)", "rumor_dm", cmem, line)
		sent += 1
		_rumor_dm_sent += 1
		if _rumor_dm_sent >= RUMOR_DM_CAP:
			break
	return sent


## Parse player text into an intent using keyword scoring + regex.
## Returns: {intent: String, score: float}
func parse_intent(norm_text: String) -> Dictionary:
	var best_intent := "unclear"
	var best_score := 0.0
	var best_match_len := 0

	# Check follow-up patterns first (they're short and specific)
	var fu := _check_followup(norm_text)
	if not fu.is_empty():
		return fu

	for intent_def in ConversationData.INTENTS:
		var iid: String = intent_def["id"]
		if iid == "unclear":
			continue

		var score := 0.0
		var match_len := 0

		# Keyword stem matching
		for key_pair in intent_def["keys"]:
			var stem: String = key_pair[0]
			var weight: int = key_pair[1]
			if norm_text.contains(stem):
				score += float(weight)

		# Regex pattern matching (higher confidence)
		for pattern in intent_def["patterns"]:
			var regex := RegEx.new()
			var err := regex.compile(pattern)
			if err != OK:
				continue
			var rm := regex.search(norm_text)
			if rm:
				score += 5.0  # Regex match is strong evidence
				match_len = maxi(match_len, rm.get_string(0).length())
				break  # Only count one regex per intent

		# Jeremy 2026-10-06: longest regex match wins ties. "what are you
		# doing?" matches both who_are_you ("\bwhat are you\b") and
		# what_are_you_doing ("\bwhat are you doing\b") at 5.0 — the more
		# specific pattern must win, or every activity question reads as
		# "who are you?". (HTML separated these via stem-key scoring.)
		if score > best_score or (score > 0.0 and score == best_score \
				and match_len > best_match_len):
			best_score = score
			best_intent = iid
			best_match_len = match_len

	# Require minimum score to avoid false positives
	if best_score < 2.0:
		return {"intent": "unclear", "score": 0.0}

	return {"intent": best_intent, "score": best_score}


## ---------------------------------------------------------------------------
## Intent parsing helpers
## ---------------------------------------------------------------------------

## The player's ruler name, never truncated (Jeremy's rule).
static func _ruler_name(gs) -> String:
	if gs == null:
		return "friend"
	var rn = gs.get("ruler_name")
	if rn == null or String(rn) == "":
		return "friend"
	return String(rn)


static func _day_number(gs) -> int:
	if gs == null:
		return 1
	var d = gs.get("day_number")
	if d == null:
		return 1
	return int(d)


func _normalize(text: String) -> String:
	var n := text.to_lower().strip_edges()
	# Expand common contractions (Living Lexicon seed)
	n = n.replace("gonna", "going to")
	n = n.replace("wanna", "want to")
	n = n.replace("gotta", "got to")
	n = n.replace("kinda", "kind of")
	n = n.replace("sorta", "sort of")
	n = n.replace("yeah", "yes")
	n = n.replace("yep", "yes")
	n = n.replace("nah", "no")
	n = n.replace("nope", "no")
	return n


func _check_followup(norm_text: String) -> Dictionary:
	var t := norm_text.strip_edges()
	# "why?" / "why" / "but why"
	if t in ["why?", "why", "but why?", "but why", "why is that?", "why is that"]:
		return {"intent": "followup_why", "score": 10.0}
	# "tell me more" / "go on" / "and?"
	if t in ["tell me more", "go on", "and?", "and", "more?", "more",
			"continue", "keep going", "elaborate"]:
		return {"intent": "followup_more", "score": 10.0}
	# "what?" / "huh?" / "what did you say?"
	if t in ["what?", "what", "huh?", "huh", "what did you say?",
			"say that again", "repeat that", "come again?"]:
		return {"intent": "followup_repeat", "score": 10.0}
	return {}


## ---------------------------------------------------------------------------
## Response selection
## ---------------------------------------------------------------------------

func _pick_response(intent: String, faction: String, unit: Dictionary,
		mem: Dictionary, gs, pool_override: String = "") -> String:
	# CHATX (HTML _poolKey hook): mood-colored greetings — a furious NPC
	# never greets warmly, a lovesick one is distracted. A strong mood
	# (i >= 3) redirects to the greeting_mood_<mood> pool when it exists.
	var key := pool_override if pool_override != "" else intent
	if pool_override == "" and intent == "greeting":
		var gckey := SimChatxCitizen.key_for(int(unit.get("id", 0)))
		var gst := chatx_mood.get_mood(gckey, _chatx_day(gs),
			_chatx_life(unit, mem, gs))
		if int(gst.get("i", 0)) >= 3:
			var mk := "greeting_mood_" + String(gst.get("m", ""))
			if not ConversationResponses.get_pool(mk, faction).is_empty():
				return _pick_response(intent, faction, unit, mem, gs, mk)
	var pool := ConversationResponses.get_pool(key, faction)
	if pool.is_empty():
		# Fallback to gnome pool, then unclear
		pool = ConversationResponses.get_pool(key, "gnome")
	if pool.is_empty():
		pool = ConversationResponses.get_pool("unclear", faction)
	if pool.is_empty():
		return "Hm?"

	# Anti-repetition: avoid recently used variants
	var unit_id := int(unit.get("id", 0))
	var vkey := "%d:%s" % [unit_id, key]
	var used: Array = _used_variants.get(vkey, [])

	var available := []
	for i in range(pool.size()):
		if not used.has(i):
			available.append(i)

	# If all used, reset (allow repeats after cycling through)
	if available.is_empty():
		available = range(pool.size())
		used.clear()

	var pick: int = available[randi() % available.size()]
	used.append(pick)
	# Keep only last (pool_size - 1) to ensure variety
	while used.size() >= pool.size() and pool.size() > 1:
		used.pop_front()
	_used_variants[vkey] = used

	return pool[pick]


## "What offended you?" — quote the most recent player insult at this NPC
## from their episodic memory. Falls back to coy deflection when the NPC
## has no insult on record.
func _insult_why_reply(unit: Dictionary, faction: String, mem: Dictionary,
		gs) -> String:
	var unit_id := int(unit.get("id", 0))
	var ckey := SimChatxCitizen.key_for(unit_id)
	var insult_mem := chatx_cit.last_of_kind(ckey, "insult")
	var pool_key := "insult_why"
	var insult_text := ""
	if insult_mem.is_empty():
		pool_key = "insult_why_none"
	else:
		insult_text = String(insult_mem.get("t", "")).strip_edges()
		if insult_text == "":
			pool_key = "insult_why_none"
	var line := _pick_response("insult_why", faction, unit, mem, gs, pool_key)
	if insult_text != "":
		line = line.replace("{insult}", "\"%s\"" % insult_text)
	return line


## Pick from an override pool when it exists, else the intent's own pool
## (never the "unclear" fallback — the override is optional flavor).
func _pick_pool(intent: String, faction: String, unit: Dictionary,
		mem: Dictionary, gs, override: String) -> String:
	if not ConversationResponses.get_pool(override, faction).is_empty():
		return _pick_response(intent, faction, unit, mem, gs, override)
	return _pick_response(intent, faction, unit, mem, gs)


## Jeremy 2026-10-06 (LANE 4): apology arcs. Grudge under the
## personality-matched threshold -> accepted (grudge cleared, mood bump,
## forgiveness recorded); grudge still hot -> deflected ("words are
## cheap") with a small softening so repeated apologies over days work —
## HTML msgrForgiveTick parity: forgiveness is an arc, not a switch.
func _apology_reply(unit: Dictionary, faction: String, mem: Dictionary,
		gs) -> String:
	var unit_id := int(unit.get("id", 0))
	var day := _day_number(gs)
	var g := _grudge_now(mem, day)
	var line := ""
	if g <= _apology_threshold(unit):
		line = _pick_pool("apology", faction, unit, mem, gs,
			"apology_accept")
		mem["grudge_pts"] = 0.0
		mem["grudge_day"] = day
		mem["apology_count"] = 0
		bump_ruler_mood(unit_id, 4.0)
		chatx_cit.mem_record(SimChatxCitizen.key_for(unit_id),
			"forgiveness", "accepted the ruler's apology", 1,
			{"day": day})
	else:
		line = _pick_pool("apology", faction, unit, mem, gs,
			"apology_deflect")
		_grudge_add(mem, -3.0, day)
		mem["apology_count"] = int(mem.get("apology_count", 0)) + 1
		bump_ruler_mood(unit_id, 1.0)
	return line


## Jeremy 2026-10-06 (LANE 4): compliments — personality-matched reply.
## Proud NPCs bask, warm ones glow; everyone else gets the generic pool.
func _compliment_reply(unit: Dictionary, faction: String, mem: Dictionary,
		gs) -> String:
	var persona := SimPersonality.persona_of(unit)
	var proud := SimPersonality.trait_of(unit, "proud")
	var friendly := SimPersonality.trait_of(unit, "friendly")
	var key := "compliment_npc"
	if proud >= 0.7 or persona in ["proud", "haughty"]:
		key = "compliment_proud"
	elif friendly >= 0.7 or persona in ["jolly", "earnest", "loyal",
			"worried"]:
		key = "compliment_warm"
	return _pick_pool("compliment_npc", faction, unit, mem, gs, key)


## Jeremy 2026-10-06 (LANE 4): "who rules the elves?" — answered from
## LIVE game state via SimFactionLeaders. Names the asked faction's
## leader, or the full roster when no faction is named. Falls back to
## the flavor pool when leader data is unavailable (bare-sim tests).
func _rulers_answer(unit: Dictionary, text: String, faction: String,
		mem: Dictionary, gs) -> String:
	var fl = null
	if gs != null:
		fl = gs.get("faction_leaders")
	if fl == null or not fl.has_method("all_leaders"):
		return _pick_response("question_rulers", faction, unit, mem, gs)
	var leaders: Array = fl.all_leaders()
	if leaders.is_empty():
		return _pick_response("question_rulers", faction, unit, mem, gs)
	var norm := text.to_lower()
	var fmap := {"elf": "elf", "elven": "elf", "elves": "elf",
		"human": "human", "humans": "human",
		"ogre": "ogre", "ogres": "ogre",
		"gnome": "gnome", "gnomes": "gnome", "undead": "undead"}
	var asked := []
	var wbound := RegEx.new()
	for w in fmap:
		wbound.compile("\\b" + w + "\\b")
		if wbound.search(norm) != null and not asked.has(fmap[w]):
			asked.append(fmap[w])
	if asked.is_empty():
		var bits := []
		for l in leaders:
			var ld: Dictionary = l
			var lf := String(ld.get("faction", ""))
			bits.append("%s (%s)" % [String(ld.get("name", "?")),
				_people_word(lf)])
		return "The crowns of the realm: " + ", ".join(bits) + "."
	var out := []
	for f in asked:
		var nm := "no one, right now"
		for l in leaders:
			var ld2: Dictionary = l
			if String(ld2.get("faction", "")) == f:
				nm = String(ld2.get("name", "?"))
				break
		out.append("The %s are ruled by %s." % [_people_word(f), nm])
	return " ".join(out)


## Jeremy 2026-10-08 (12h audit): C67 muster-roll parity (HTML fix79
## trainJobWord67/liveUnitCount67/COMBAT_JOBS67). "troop report" /
## "how many soldiers" / "how many mages" are answered from LIVE unit
## counts, computed at speak time — never cached. A bare report lists
## the NPC's own faction's military jobs (nonzero only, declaration
## order); "how many X" names one job, military or civilian. A faction
## at war with the player refuses — its strength is its secret.
const MUSTER_JOB_WORDS := {
	"soldier": "soldier", "soldiers": "soldier",
	"warrior": "soldier", "warriors": "soldier",
	"guard": "guard", "guards": "guard",
	"archer": "archer", "archers": "archer",
	"ranger": "ranger", "rangers": "ranger",
	"mage": "mage", "mages": "mage",
	"cannoneer": "cannoneer", "cannoneers": "cannoneer",
	"cannon": "cannoneer", "cannons": "cannoneer",
	"swordsman": "swordsman", "swordsmen": "swordsman",
	"knight": "knight", "knights": "knight",
	"cleric": "cleric", "clerics": "cleric",
	"clubber": "clubber", "clubbers": "clubber",
	"musketeer": "musketeer", "musketeers": "musketeer",
	"berserker": "berserker", "berserkers": "berserker",
	"warlord": "warlord", "warlords": "warlord",
	"blunderbuss": "blunderbuss", "blunderbusses": "blunderbuss",
	"axeman": "axeman", "axemen": "axeman",
	"mech": "tinker_mech", "mechs": "tinker_mech",
	"tinker": "tinker_mech", "tinkers": "tinker_mech",
	"saboteur": "saboteur", "saboteurs": "saboteur",
	"warlock": "warlock", "warlocks": "warlock",
	"treant": "treant", "treants": "treant",
	"spellweaver": "spellweaver", "spellweavers": "spellweaver",
	"spirit": "spirit", "spirits": "spirit",
	"bandit": "bandit", "bandits": "bandit",
	"worker": "worker", "workers": "worker",
	"citizen": "worker", "citizens": "worker",
	"woodcutter": "woodcutter", "woodcutters": "woodcutter",
	"miner": "miner", "miners": "miner",
	"farmer": "farmer", "farmers": "farmer",
	"builder": "builder", "builders": "builder",
	"fisher": "fisher", "fishers": "fisher",
	"fisherman": "fisher", "fishermen": "fisher",
	"hunter": "hunter", "hunters": "hunter",
	"shopkeeper": "shopkeeper", "shopkeepers": "shopkeeper",
	"smith": "smith", "smiths": "smith",
	"doctor": "doctor", "doctors": "doctor",
	"diplomat": "diplomat", "diplomats": "diplomat",
	"clerk": "clerk", "clerks": "clerk",
	"judge": "judge", "judges": "judge",
	"firefighter": "firefighter", "firefighters": "firefighter",
}


func _muster_answer(unit: Dictionary, text: String, faction: String,
		mem: Dictionary, gs) -> String:
	if gs != null:
		var pfv = gs.get("player_faction")
		var pf := String(pfv) if pfv != null else ""
		var dip = gs.get("diplomacy")
		if pf != "" and dip != null and dip.has_method("relation_state") \
				and String(dip.call("relation_state", faction, pf)) == "war":
			return _pick_pool("question_troops", faction, unit, mem, gs,
				"question_troops_refuse")
	var job := _muster_job_word(String(text).to_lower())
	var roll := ""
	var total := 0
	if job != "":
		total = _job_count(gs, faction, job)
		roll = "%s: %d" % [_muster_display(job), total]
	else:
		var parts := []
		for j in JobDefs.jobs_in_category("military"):
			var n := _job_count(gs, faction, j)
			if n > 0:
				total += n
				parts.append("%s: %d" % [_muster_display(j), n])
		roll = ", ".join(parts)
	if total == 0:
		return _pick_pool("question_troops", faction, unit, mem, gs,
			"question_troops_none")
	var line := _pick_response("question_troops", faction, unit, mem, gs)
	# Resolve here: _substitute runs later and strips unknown tokens.
	line = line.replace("{musterRoll}", roll)
	line = line.replace("{musterTotal}", str(total))
	return line


## "how many X" -> a Godot job id, or "" for a full muster roll.
static func _muster_job_word(norm: String) -> String:
	var re := RegEx.new()
	re.compile("how many\\s+([a-z]+)")
	var m := re.search(norm)
	if m == null:
		return ""
	var w := m.get_string(1)
	if MUSTER_JOB_WORDS.has(w):
		return String(MUSTER_JOB_WORDS[w])
	if w.ends_with("s"):
		var singular := w.substr(0, w.length() - 1)
		if MUSTER_JOB_WORDS.has(singular):
			return String(MUSTER_JOB_WORDS[singular])
	return ""


## Live count of one job in a faction (alive units only).
static func _job_count(gs, faction: String, job: String) -> int:
	if gs == null or faction == "" or job == "":
		return 0
	var uv = gs.get("units")
	var units: Array = uv if uv is Array else []
	var n := 0
	for u in units:
		if not (u is Dictionary):
			continue
		var ud: Dictionary = u
		if String(ud.get("faction", "")) != faction:
			continue
		if not bool(ud.get("alive", false)):
			continue
		if String(ud.get("job", "")) == job:
			n += 1
	return n


static func _muster_display(job: String) -> String:
	var jd = JobDefs.JOBS.get(job, {})
	if jd is Dictionary:
		var nm := String((jd as Dictionary).get("name", ""))
		if nm != "":
			return nm
	return job


## ---------------------------------------------------------------------------
## Conversation memory
## ---------------------------------------------------------------------------

## Public: the NPC's current mood toward the ruler (-100..100).
## Used by the phone's relationship meter (HTML msgrAff54 parity).
func ruler_mood(unit_id: int) -> float:
	return float(_get_memory(unit_id).get("mood", 0.0))


## Public: seed an NPC's conversation mood (-100..100). Used by
## SimPhone for faction leaders so their first words track the real
## relationship (wars, betrayals, alliances) instead of opening neutral.
func set_ruler_mood(unit_id: int, value: float) -> void:
	_get_memory(unit_id)["mood"] = clampf(value, -100.0, 100.0)


## Jeremy 2026-10-06: player smear pipeline — external systems (hearsay
## reactions) move an NPC's ruler-mood and player-affection without
## reaching into conversation memory internals. Grudges persist because
## these feed the same scales the dialogue engine reads.
func bump_ruler_mood(unit_id: int, delta: float) -> void:
	set_ruler_mood(unit_id, ruler_mood(unit_id) + delta)


func bump_affection(unit_id: int, delta: float) -> void:
	chatx_cit.aff_delta(SimChatxCitizen.key_for(unit_id), delta)


## Jeremy 2026-10-10 (hearsay flesh-out): rumor-borne offenses feed the
## grudge ledger — a player smear the target hears isn't just mood and
## affection, it's a grudge the apology flow can resolve. Same decay and
## thresholds as chat insults; stored in the NPC's memory dict, so it
## persists through save/load like every other ledger entry. Guarded for
## bare-sim use (null gs -> day-1 baseline, no decay applied).
func add_grudge(unit_id: int, pts: float, gs) -> float:
	return _grudge_add(_get_memory(unit_id), pts, _day_number(gs))


## Jeremy 2026-10-06: player smear pipeline — the player trash-talked a
## third party in this DM. Seed a real rumor with the player as source;
## the conversation partner heard it firsthand (first knower). Guarded:
## phone_sys may be absent in bare-sim tests.
func _maybe_seed_smear(smear: Dictionary, text: String, hearer_id: int,
		gs) -> void:
	if gs == null or smear.is_empty():
		return
	var phone = gs.get("phone_sys")
	if phone == null:
		return
	var hs = phone.get("hearsay")
	if hs == null or not hs.has_method("seed_player_smear"):
		return
	hs.seed_player_smear(smear, text, String(smear.get("insult", "")),
		hearer_id)


func _get_memory(unit_id: int) -> Dictionary:
	if not _memories.has(unit_id):
		_memories[unit_id] = {
			"history": [],        # Last N exchanges: [{you, npc, intent}]
			"last_intent": "",
			"last_topic": "",
			"last_you": "",
			"prev_you": "",
			"mood": 0.0,          # -100 to 100
			"met": false,         # Have they met the player?
			"insult_count": 0,
		}
	return _memories[unit_id]


func _update_memory(unit_id: int, player_text: String, intent: String,
		mem: Dictionary, npc_text: String = "") -> void:
	mem["prev_you"] = mem.get("last_you", "")
	mem["last_you"] = player_text.left(240)
	mem["last_intent"] = intent

	var history: Array = mem["history"]
	history.append({"you": player_text.left(120), "intent": intent,
		"npc": npc_text.left(160)})
	# Keep last 10 exchanges
	while history.size() > 10:
		history.pop_front()

	if not bool(mem.get("met", false)):
		mem["met"] = true


## Snapshot of the conversation flow state for the reply result dict.
func _flow_dict(mem: Dictionary) -> Dictionary:
	return {
		"state": String(mem.get("flow_state", "opening")),
		"turn": int(mem.get("turn_count", 0)),
		"topic": String(mem.get("last_topic", "")),
		"trajectory": Flow.trajectory(mem),
		"style": Flow.style_voice(mem),
	}


## Jeremy 2026-10-06 (LANE 4): multi-turn thread context — "why did you
## say that?" resolves against the NPC's ACTUAL last statement from the
## thread history (the npc field of the last exchange), not just the last
## intent. The thread keeps the last 10 exchanges per NPC.
func _followup_reply(intent: String, mem: Dictionary, faction: String,
		gs, player_text: String = "") -> String:
	var last_intent: String = mem.get("last_intent", "")
	var history: Array = mem.get("history", [])

	if history.is_empty():
		return ""

	if intent == "followup_why":
		# "Why did you say that?" — quote and defend the last NPC line
		# from thread history.
		var pt := player_text.to_lower()
		if pt.contains("say that") or pt.contains("said"):
			var last: Dictionary = history[history.size() - 1]
			var last_npc := String(last.get("npc", "")).strip_edges()
			if last_npc != "":
				if last_npc.length() > 110:
					last_npc = last_npc.left(107) + "..."
				var frame := _pick_response("followup_why", faction,
					{"id": -1}, mem, gs, "why_said")
				frame = frame.replace("{said}", last_npc)
				return frame
		# "Why?" - elaborate on last topic
		return _elaborate(last_intent, faction, mem)
	elif intent == "followup_more":
		# "Tell me more" - continue last topic
		return _elaborate(last_intent, faction, mem)
	elif intent == "followup_repeat":
		# "What did you say?" - repeat last response differently
		if history.size() >= 1:
			var last: Dictionary = history[history.size() - 1]
			return "I said: " + _pick_response(
				String(last.get("intent", "unclear")), faction,
				{"id": -1}, mem, gs)

	return ""


func _elaborate(intent: String, faction: String, mem: Dictionary) -> String:
	# Get an elaboration from the pool, or a generic continuer
	var pool := ConversationResponses.get_pool(intent + "_more", faction)
	if pool.is_empty():
		# Generic elaborations per faction
		match faction:
			"gnome":
				return "What, you want the long version? Fine. It's complicated, it's political, and it involves at least one bribe."
			"human":
				return "To elaborate: it's a longer story than we've got time for, but the short of it stands."
			"elf":
				return "Oh, you want MORE detail? Darling, I could talk about this for hours. The short version: it's dramatic."
			"ogre":
				return "ME EXPLAIN MORE! ...ME FORGET WHAT ME WAS SAYING. BUT ME FEEL STRONGLY ABOUT IT."
			_:
				return "It's a long story. The short version is what I already told you."
	return pool[randi() % pool.size()]


## ---------------------------------------------------------------------------
## Special handlers
## ---------------------------------------------------------------------------

func _handle_name_set(unit: Dictionary, text: String, mem: Dictionary,
		gs) -> Dictionary:
	# Extract name from "my name is X" / "call me Y"
	var norm := _normalize(text)
	var new_name := ""

	var patterns := [
		"my name is ([a-z ]+)",
		"call me ([a-z ]+)",
		"i am called ([a-z ]+)",
		"the name's ([a-z ]+)",
	]

	for pat in patterns:
		var regex := RegEx.new()
		if regex.compile(pat) == OK:
			var m := regex.search(norm)
			if m:
				new_name = m.get_string(1).strip_edges()
				break

	if new_name.is_empty():
		return {"text": "And what name is that, then?", "intent": "name_set",
			"effect": {}}

	# Capitalize properly, don't truncate (Jeremy's "full names" rule)
	new_name = _title_case(new_name)

	# HTML parity: the reply renders the NEW name (window._kingName was
	# already updated before _subst ran), then all other tokens fill normally.
	var picked := _pick_response("name_set",
		String(unit.get("faction", "gnome")), unit, mem, gs)
	picked = picked.replace("{name}", new_name)
	picked = _substitute(picked, unit, gs)
	return {
		"text": picked,
		"intent": "name_set",
		"effect": {"type": "set_name", "name": new_name}
	}


func _title_case(s: String) -> String:
	var parts := s.split(" ")
	var out := []
	for p in parts:
		if p.length() > 0:
			out.append(p[0].to_upper() + p.substr(1))
	return " ".join(out)


## ---------------------------------------------------------------------------
## Tone and substitution
## ---------------------------------------------------------------------------

func _apply_tone(text: String, unit: Dictionary, mem: Dictionary) -> String:
	# Jeremy 2026-10-04: full emotion engine — the NPC's dominant emotion
	# colors ALL their dialogue. Angry NPCs snap, happy ones gush,
	# scared ones stammer. Applied ~35% of the time so it flavors
	# without drowning the actual reply.
	var tone := SimEmotion.new().tone(unit)
	if randf() > 0.35:
		return text
	match tone:
		"cheerful":
			var warm := ["Hehe. ", "Oh! ", ""]
			return warm[randi() % warm.size()] + text
		"grumpy":
			var snap := ["Hmph. ", "Tch. ", "Whatever. "]
			return snap[randi() % snap.size()] + text
		"fearful":
			var shy := ["Um... ", "Oh! ", "Eep. "]
			return shy[randi() % shy.size()] + text
	return text


## Jeremy 2026-10-04: mood replies. The NPC's persistent mood (SimMood,
## hardened from repeated emotions) picks from 100 mood-flavored
## standalone replies. Applied ~30% of the time so it flavors without
## drowning the intent-specific reply; neutral mood adds nothing
## (baseline replies are already neutral). Runs before _substitute so
## {name}/{ruler} tokens in mood lines resolve.
func _apply_mood_line(text: String, unit: Dictionary, _mem: Dictionary,
		force: bool = false) -> String:
	var m := SimMood.new().dominant(unit)
	if m == "neutral":
		return text
	if not force and randf() > 0.30:
		return text
	var line := SimMoodReplies.pick(m)
	if line == "":
		return text
	return text + " " + line


## ---------------------------------------------------------------------------
## chatx affect (Jeremy 2026-10-05 — HTML fix79 chatx system parity)
## ---------------------------------------------------------------------------

## Dialogue events drive the NPC's persistent 22-mood affect state; the
## exchange is recorded in episodic memory and moves affection.
func _chatx_affect(unit: Dictionary, unit_id: int, mem: Dictionary,
		intent: String, text: String, gs) -> void:
	var ckey := SimChatxCitizen.key_for(unit_id)
	var day := _chatx_day(gs)
	var life := _chatx_life(unit, mem, gs)
	# hot = the exchange runs hot-headed (HTML: r.aggro >= 60). Repeat
	# insults heat the NPC up: threats stop scaring and start angering.
	if intent == "insult":
		mem["insult_count"] = int(mem.get("insult_count", 0)) + 1
	var hot := int(mem.get("insult_count", 0)) >= 3
	chatx_mood.apply_event(ckey, intent, String(life.get("tier", "neutral")),
		hot, day)
	chatx_cit.mem_record(ckey, intent, text,
		_chatx_valence(intent), {"day": day})
	chatx_cit.aff_delta(ckey, _chatx_aff_delta(intent))
	# Jeremy 2026-10-06 (LANE 4): hostile acts feed the per-NPC grudge
	# ledger (emotional arcs — grudges fade over game days, apologies
	# chip at them; see _grudge_now / _apology_reply).
	var gp: float = float(GRUDGE_PTS.get(intent, 0.0))
	if gp > 0.0:
		_grudge_add(mem, gp, day)


## Strong-mood voice + asides, applied after the SimMood reply line.
func _apply_chatx_mood(text: String, unit: Dictionary, mem: Dictionary,
		gs) -> String:
	var ckey := SimChatxCitizen.key_for(int(unit.get("id", 0)))
	var st := chatx_mood.get_mood(ckey, _chatx_day(gs),
		_chatx_life(unit, mem, gs))
	var mood := String(st.get("m", ""))
	var mi := int(st.get("i", 0))
	var out := text
	if mi >= 3 and mood != "":
		var line := chatx_mood.pick_line(mood,
			String(unit.get("faction", "gnome")), ckey)
		if line != "":
			out += " " + line
	return chatx_mood.flavor(out, mood, mi, ckey)


func _chatx_day(gs) -> int:
	if gs != null and gs.get("day_number") != null:
		return int(gs.get("day_number"))
	return 1


## Build the chatxMoodCompute input from the NPC's life.
func _chatx_life(unit: Dictionary, mem: Dictionary, gs) -> Dictionary:
	var unit_id := int(unit.get("id", 0))
	var ckey := SimChatxCitizen.key_for(unit_id)
	var day := _chatx_day(gs)
	var faction := String(unit.get("faction", "gnome"))
	var at_war := false
	var blocked := false
	if gs != null:
		var pfv = gs.get("player_faction")
		var pf := String(pfv) if pfv != null else ""
		var dip = gs.get("diplomacy")
		if pf != "" and dip != null and dip.has_method("relation_state"):
			at_war = String(dip.call("relation_state", faction, pf)) == "war"
		var phone = gs.get("phone_sys")
		if phone != null and phone.has_method("is_blocked"):
			blocked = bool(phone.call("is_blocked", unit_id))
	var tier := chatx_cit.aff_tier(ckey, blocked, at_war)
	var um := chatx_cit.unprompted(ckey, day)
	return {
		"grudge": chatx_cit.grudge(ckey, day),
		"favor": chatx_cit.favor(ckey, day),
		"unprompted_kind": String(um.get("k", "")),
		"unprompted_v": int(um.get("v", 0)),
		"unprompted_it": int(um.get("it", 0)),
		"tier": tier,
		"hunger": int(unit.get("hunger", 50)),
		"energy": int(unit.get("energy", 50)),
		"workload": int(unit.get("workload", 0)),
		"has_job": String(unit.get("job", "")) != "",
		"at_war": at_war,
		"festival": _chatx_festival_active(gs),
		"faction": SimChatxMood.race_of(faction),
	}


## A festival counts as active while it is being held or due within a
## day (HTML festActive() parity; Godot festivals are instant + scheduled).
func _chatx_festival_active(gs) -> bool:
	if gs == null:
		return false
	var court = gs.get("court_sys")
	if court == null:
		return false
	var policies = court.get("policies")
	if policies == null:
		return false
	var day := _chatx_day(gs)
	var st: Dictionary = policies.get("state")
	if st == null:
		return false
	if int(st.get("last_festival_day", -100)) >= day - 1:
		return true
	if policies.has_method("scheduled_festivals"):
		for f in policies.scheduled_festivals():
			if int((f as Dictionary).get("day_abs", 9999)) - day <= 1:
				return true
	return false


## Valence of a dialogue intent for episodic memory.
func _chatx_valence(intent: String) -> int:
	if intent in ["praise", "thanks", "apology", "forgiveness",
			"love_declaration", "gift_give", "compliment_npc"]:
		return 1
	if intent in ["insult", "threat", "crude_direct", "war_declare",
			"war_threaten", "tribute_demand"]:
		return -1
	return 0


## Affection delta per dialogue intent (HTML msgrCitAffDelta parity —
## witnessed deeds move it ±2/∓3; direct dialogue moves it a touch more).
func _chatx_aff_delta(intent: String) -> float:
	match intent:
		"praise":
			return 2.0
		"thanks":
			return 2.0
		"apology":
			return 3.0
		"forgiveness":
			return 3.0
		"love_declaration", "romance_proposition":
			return 1.0
		"gift_give":
			return 4.0
		"compliment_npc":
			return 3.0
		"insult":
			return -4.0
		"threat":
			return -5.0
		"crude_direct":
			return -4.0
		"war_declare":
			return -8.0
	return 0.0


func _substitute(text: String, unit: Dictionary, gs,
		topic: String = "") -> String:
	# HTML fix79 _subst parity. Token meanings (ported verbatim):
	#   {name}               = the PLAYER's ruler name (never truncated)
	#   {ruler}              = same (Godot shorthand)
	#   {rname} / {rulerName} = the NPC's own name
	#   {rulerTitle} / {jobName} = the NPC's title/job
	#   {ppl} / {faction}    = people word / faction id
	#   {doing}              = the NPC's current activity
	#   {mood} {need} {town} {gold} {warList} {warCount} {tax} {festName}
	#   {townCount} {festDays} {tgold} {rel} {myArmy} {theirArmy} {topic}
	#       = live world state (Jeremy 2026-10-06 LANE 4: world questions
	#         answered from the sim, not canned numbers)
	# Unknown tokens are stripped so no raw {token} ever shows.
	var out := text

	# Longest tokens first so {ruler} can't nick {rulerName}/{rulerTitle}.
	var ruler_name := _ruler_name(gs)
	out = out.replace("{rulerName}", _npc_name(unit))
	out = out.replace("{rulerTitle}", _npc_title(unit))
	out = out.replace("{ruler}", ruler_name)
	out = out.replace("{rname}", _npc_name(unit))
	out = out.replace("{name}", ruler_name)

	var faction := String(unit.get("faction", "gnome"))
	out = out.replace("{faction}", faction)
	out = out.replace("{ppl}", _people_word(faction))
	out = out.replace("{doing}", _doing_for(unit))
	out = out.replace("{mood}", _mood_word(unit))
	out = out.replace("{jobName}", _npc_title(unit))
	out = out.replace("{town}", String(unit.get("town", "town")))
	out = out.replace("{need}", "a good meal and loyal company")
	out = out.replace("{govName}", "the crown")
	out = out.replace("{locName}", "my halls")
	out = out.replace("{capital}", "a far-off hall")
	out = out.replace("{c25person}", "them")
	# Godot shorthand tokens kept from the earlier port.
	out = out.replace("{target}", "them")
	out = out.replace("{other}", "them")
	out = out.replace("{wrong}", "that")

	if gs != null:
		var pfv = gs.get("player_faction")
		var pf := String(pfv) if pfv != null else ""
		var res = gs.get("resources")
		var gold := 0.0
		if res != null:
			if res is Dictionary:
				gold = float(res.get("gold", 0.0))
			else:
				gold = float(res.call("get_amount", pf, "gold"))
		out = out.replace("{gold}", str(int(gold)))
		out = out.replace("{warList}", _war_list(gs, faction))
		out = out.replace("{warCount}", str(_war_count(gs, faction)))
		out = out.replace("{tax}", _tax_word(gs))
		out = out.replace("{festName}", _fest_name(gs))
		# Jeremy 2026-10-06 (LANE 4): live world-state tokens for world
		# questions — the pools were written for real numbers.
		out = out.replace("{townCount}", _town_count_str(gs, faction))
		out = out.replace("{festDays}", _fest_days_str(gs))
		out = out.replace("{tgold}", _faction_gold_str(gs, faction))
		out = out.replace("{rel}", _relation_word(gs, faction))
		out = out.replace("{myArmy}", _army_str(gs, faction))
		out = out.replace("{theirArmy}", _army_str(gs, pf))

	# Last thread topic for {topic} callbacks ("Still on {topic}?").
	out = out.replace("{topic}", topic if topic != "" else "that")

	# Strip any remaining {unknown} tokens.
	var tok_re := RegEx.new()
	tok_re.compile("\\{[a-zA-Z0-9]+\\}")
	var m := tok_re.search(out)
	while m != null:
		out = out.substr(0, m.get_start()) + out.substr(m.get_end())
		m = tok_re.search(out)

	return out


## The NPC's own name (HTML _subst rname/rulerName). Unit dicts carry it in
## mind.name — SimPersonality.display_name resolves both spellings.
static func _npc_name(unit: Dictionary) -> String:
	var n := ""
	if unit.has("display_name"):
		n = String(unit["display_name"])
	elif unit.has("name"):
		n = String(unit["name"])
	if n == "":
		n = SimPersonality.display_name(unit)
	if n == "":
		n = "friend"
	return n


## The NPC's title: job, or a leaderly fallback.
static func _npc_title(unit: Dictionary) -> String:
	var t := String(unit.get("job", ""))
	if t == "":
		t = String(unit.get("title", ""))
	if t == "":
		t = "ruler"
	return t


## People word for a faction (HTML _subst pplMap).
static func _people_word(faction: String) -> String:
	match faction:
		"gnome":
			return "gnomes"
		"human":
			return "humans"
		"elf":
			return "elves"
		"ogre":
			return "ogres"
		"undead":
			return "undead"
		_:
			return faction + "s" if faction != "" else "folk"


## What the NPC is currently doing, as a gerund phrase (HTML _subst
## "doing"). Grounded in the sim's real work_state/job — the brain, not
## a canned line.
static func _doing_for(unit: Dictionary) -> String:
	var ws := String(unit.get("work_state", ""))
	match ws:
		"building", "to_build":
			return "raising buildings"
		"to_resource", "gathering":
			var gk := String(unit.get("gather_kind", ""))
			match gk:
				"wood":
					return "chopping wood"
				"gold":
					return "mining gold"
				"food":
					return "gathering food"
				"oil":
					return "pumping oil"
				_:
					return "gathering supplies"
		"to_fire", "extinguishing":
			return "fighting a fire"
		"to_shop":
			return "heading to the shop"
		"off_shift":
			return "off shift, resting"
		"idle":
			return "catching my breath"
		"working":
			pass
	var job := String(unit.get("job", ""))
	if job != "" and job != "ruler":
		return "working as a " + job
	return "holding court"


## The NPC's current mood as a plain word (HTML _subst "mood").
static func _mood_word(unit: Dictionary) -> String:
	var m := SimMood.new().dominant(unit)
	if m == "" or m == "neutral":
		return "fair"
	return m


## Comma-joined war enemies of a faction, or "nobody".
static func _war_list(gs, faction: String) -> String:
	var foes := _war_foes(gs, faction)
	if foes.is_empty():
		return "nobody"
	return ", ".join(foes)


static func _war_count(gs, faction: String) -> int:
	return _war_foes(gs, faction).size()


static func _war_foes(gs, faction: String) -> Array:
	var foes := []
	if gs == null or faction == "":
		return foes
	var dip = gs.get("diplomacy")
	if dip == null or not dip.has_method("relation_state"):
		return foes
	for f in Config.FACTIONS.keys():
		var fs := String(f)
		if fs != faction and String(dip.call("relation_state", faction, fs)) == "war":
			foes.append(_people_word(fs))
	return foes


## Current tax policy as a word (HTML _subst "tax").
static func _tax_word(gs) -> String:
	if gs == null:
		return "10"
	var court = gs.get("court_sys")
	if court != null:
		var policies = court.get("policies")
		if policies != null and policies.get("state") != null:
			var st: Dictionary = policies.get("state")
			if st.has("tax"):
				return str(st.get("tax"))
	return "10"


## Active festival name, or "no festival".
static func _fest_name(gs) -> String:
	if gs == null:
		return "no festival"
	var court = gs.get("court_sys")
	if court != null:
		var policies = court.get("policies")
		if policies != null and policies.has_method("active_festival_name"):
			var fn := String(policies.call("active_festival_name"))
			if fn != "":
				return fn
	return "no festival"


## Jeremy 2026-10-06 (LANE 4): live world-state token helpers. All are
## null-safe for bare-sim callers (fake gs dicts) — they fall back to
## grammatical plain words instead of leaking raw tokens.
static func _town_count(gs, faction: String) -> int:
	if gs == null:
		return -1
	var towns = gs.get("towns")
	if not (towns is Dictionary):
		return -1
	var n := 0
	for tid in towns:
		var t = towns[tid]
		if t is Dictionary and String((t as Dictionary).get("faction", "")) == faction:
			n += 1
	return n


static func _town_count_str(gs, faction: String) -> String:
	var n := _town_count(gs, faction)
	if n < 0:
		return "a few"
	return str(n)


static func _faction_gold_str(gs, faction: String) -> String:
	var res = gs.get("resources")
	if res == null:
		return "plenty"
	if res is Dictionary:
		if res.has("gold"):
			return str(int(float(res.get("gold", 0.0))))
		return "plenty"
	if res.has_method("get_amount"):
		return str(int(float(res.call("get_amount", faction, "gold"))))
	return "plenty"


static func _relation_word(gs, faction: String) -> String:
	var pfv = gs.get("player_faction")
	var pf := String(pfv) if pfv != null else ""
	var dip = gs.get("diplomacy")
	if dip == null or pf == "" or not dip.has_method("relation_state"):
		return "at peace"
	var st := String(dip.call("relation_state", faction, pf))
	match st:
		"war":
			return "at war"
		"allied", "alliance":
			return "allied"
		_:
			return "at peace"


static func _army_str(gs, faction: String) -> String:
	if faction == "":
		return "several"
	var army = gs.get("army")
	if army != null and army.has_method("own_strength"):
		var st: Dictionary = army.call("own_strength", faction)
		return str(maxi(0, int(st.get("mil", 0))))
	return "several"


static func _fest_days_str(gs) -> String:
	var day := _day_number(gs)
	var court = gs.get("court_sys")
	if court != null:
		var policies = court.get("policies")
		if policies != null and policies.has_method("scheduled_festivals"):
			var best := -1
			for f in policies.scheduled_festivals():
				var fd: Dictionary = f
				var d := int(fd.get("day_abs", 9999)) - day
				if d >= 0 and (best < 0 or d < best):
					best = d
			if best >= 0:
				return str(best)
	return "a few"


## ---------------------------------------------------------------------------
## Save/Load support
## ---------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	# Jeremy 2026-10-06: conversation-system integration — the full
	# shared conversation state persists: per-NPC memories, response
	# anti-repetition, chatx episodic records + affection, and the 22-mood
	# affect engine. No channel keeps a private fork; nothing is lost on
	# save/load.
	return {
		"memories": _memories,
		"used_variants": _used_variants,
		"chatx_records": chatx_cit.to_dict(),
		"chatx_mood": chatx_mood.pack(),
	}

func load_save_data(data: Dictionary) -> void:
	_memories = data.get("memories", {})
	_used_variants = data.get("used_variants", {})
	chatx_cit.from_dict(data.get("chatx_records", {}))
	chatx_mood.unpack(data.get("chatx_mood", {}))
