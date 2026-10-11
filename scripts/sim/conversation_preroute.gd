class_name SimConversationPreroute
extends RefCounted
## Cursing Gnomes — Conversation pre-route checks (HTML C29/C34 port).
##
## Before the normal intent->pool flow, the original game ran a pre-route
## that caught: sarcasm, wrong names, lies, self-talk, third-party insults,
## confrontational challenges, and crude insults. None of these were in the
## Godot port — NPCs fell through to the generic "unclear" response.
##
## Each check returns a response dict {text, intent, effect} or {}.
## Pure logic — no rendering.

## Insult words for third-party targeting (HTML C29_INSULTW + CTX_INSULTW).
## Jeremy 2026-10-06: bare "ass" added for the smear pipeline ("X is an
## ass"); word boundaries keep "jackass"/"asshat" matching their own entries.
const INSULT_WORDS := "stupid|idiot|idiots|dumb|moron|morons|fool|fools|pathetic|loser|losers|incompetent|ugly|weak|coward|cowards|useless|worthless|clown|clowns|fraud|frauds|jerk|jerks|asshole|assholes|bastard|bastards|dickhead|jackass|dumbass|dipshit|shithead|motherfucker|fucker|bitch|cunt|wanker|prick|douche|whore|slut|fuckface|asshat|ass"

## Third-party insult targets (HTML C29_THEM_TARGETS equivalent).
const THEM_TARGETS := ["king", "queen", "ruler", "mayor", "guild master",
	"advisor", "adviser", "general", "captain", "priest", "treasurer",
	"jester", "spymaster", "neighbor"]

## Jeremy 2026-10-06: player smear pipeline — extra nouns for "smells like"
## constructions ("Grak smells like ass"). Kept separate from INSULT_WORDS
## so the direct-insult paths are untouched.
const SMEAR_SMELL_NOUNS := "ass|shit|crap|garbage|trash|filth|sewage|rot|death|skunk"


## Main pre-route. Returns {text, intent, effect} or {}.
static func preroute(unit: Dictionary, text: String, norm: String,
		intent: String, mem: Dictionary, gs) -> Dictionary:
	var faction := String(unit.get("faction", "gnome"))
	var unit_name := String(unit.get("name", "friend"))
	# HTML C29_preRoute used a LIGHT normalization (only "im"->"i m").
	# The port's _normalize rewrites "yeah"->"yes" etc., which destroys
	# sarcasm/challenge patterns. Use raw-lowercased for pattern checks.
	var raw_norm := text.to_lower().strip_edges()

	# 1. Sarcasm (HTML C29_sarcasmQ)
	if sarcasm_q(raw_norm, text, intent):
		return _pool_reply("c29_sarcasm", faction, unit, mem,
			{"name": unit_name})

	# 2. Wrong name (HTML C29_wrongName)
	var wrong := wrong_name(text, unit, gs)
	if wrong != "":
		return _pool_reply("c29_wrongname", faction, unit, mem,
			{"name": unit_name, "wrong": wrong,
				"rname": unit_name})

	# 3. Lie detection — denial of known things (HTML C29_lieQ part 1)
	var lie := lie_q(raw_norm, gs)
	if not lie.is_empty():
		return lie

	# 4. Self-talk (HTML C29_selfTalk)
	if self_talk_q(raw_norm):
		var tier := _aff_tier(unit, mem, gs)
		return _pool_reply("c29_selftalk_" + tier, faction, unit, mem,
			{"name": unit_name})

	# 5. Third-party insult (HTML C29_insultThemTarget)
	var them := insult_them_target(raw_norm)
	var smear := {}
	if them.is_empty():
		# Jeremy 2026-10-06: player smear — named NPC or faction leader
		# trash-talk ("Grak smells like ass") seeds a real rumor with the
		# player as source. Never fires on the conversation partner
		# (that's the direct-insult path) or on the player themselves.
		smear = player_smear_target(raw_norm, unit, gs)
	else:
		# Role targets ("the mayor smells like ass") also smear.
		smear = role_smear_target(them, gs)
	if not them.is_empty() or not smear.is_empty():
		var them_arg := them
		if them_arg.is_empty():
			them_arg = {"target": String(smear.get("name", "them")),
				"insult": String(smear.get("insult", ""))}
		var rep := _insult_them_reply(them_arg, faction, unit, mem, gs)
		if not smear.is_empty():
			rep["_smear"] = smear
		return rep

	# 6. Challenge (HTML C34_challengeQ)
	if challenge_q(raw_norm, text):
		return _pool_reply("c34_challenge", faction, unit, mem,
			{"name": unit_name})

	# 7. Crude insult — cuss back (HTML C34_crudeInsultQ)
	if crude_insult_q(raw_norm) and intent != "crude_proposition":
		return _pool_reply("c34_crude", faction, unit, mem,
			{"name": unit_name})

	return {}


## HTML C29_sarcasmQ verbatim.
static func sarcasm_q(norm: String, raw: String, intent: String) -> bool:
	var t := " " + norm + " "
	var t1 := RegEx.new()
	t1.compile("\\byeah+ right\\b|\\bas+ if+\\b|\\bsure,?\\s+because\\b|\\blike that('ll|s ever| will)\\b|\\bbig surprise\\b|\\bwhoop(s|sie|dee)?\\b|\\boh*,?\\s+wonderful\\b|\\bjust my luck\\b|\\bjust what (i|we) (needed|wanted)\\b")
	if t1.search(t):
		return true
	if raw.contains("🙄"):
		return true
	var sunny := RegEx.new()
	sunny.compile("\\b(oh+ )?(great|fantastic|amazing|wonderful|awesome|perfect|brilliant|splendid|thanks?)\\b")
	var rotten := RegEx.new()
	rotten.compile("\\b(broke|broken|lost|died|dead|failed|terrible|awful|stupid|again|ugh|worst|destroyed|burned|burnt|caved|fell|collapsed|attacked)\\b")
	if sunny.search(t) and rotten.search(t):
		var thanks := RegEx.new()
		thanks.compile("\\bthank (you|u)\\b")
		if thanks.search(t):
			return false
		if intent == "praise":
			var praise_re := RegEx.new()
			praise_re.compile("\\byou('re| are|r) (amazing|great|awesome|wonderful)\\b")
			if praise_re.search(t):
				return false
		return true
	return false


## HTML C29_wrongName: "hi Bob" when the NPC isn't Bob.
static func wrong_name(raw: String, unit: Dictionary, gs) -> String:
	var re := RegEx.new()
	re.compile("(?i)^\\s*(hi|hello|hey|yo|hail|greetings|good morning|good evening)\\s+([A-Za-z']{3,24})")
	var m := re.search(raw)
	if m == null:
		return ""
	var cand := m.get_string(2)
	var low := cand.to_lower().replace("'", "")
	# Generic words aren't names.
	var generics := ["there", "friend", "buddy", "mate", "pal", "folks",
		"everyone", "anybody", "somebody"]
	if low in generics:
		return ""
	# Collect known names (NPC, ruler, king).
	var names := {}
	var unit_name := String(unit.get("name", "")).to_lower()
	for w in unit_name.split(" "):
		if w != "":
			names[w.replace("'", "")] = true
	# Player ruler name from gamestate.
	if gs != null:
		var rulerv = gs.get("ruler_name")
		var ruler := String(rulerv) if rulerv != null else ""
		for w in ruler.to_lower().split(" "):
			if w != "":
				names[w.replace("'", "")] = true
	if names.has(low):
		return ""
	# It's a wrong name — title-case it.
	return cand.substr(0, 1).to_upper() + cand.substr(1)


## HTML C29_lieQ part 1: denial of known things ("dragons don't exist").
static func lie_q(norm: String, gs) -> Dictionary:
	var t := " " + norm + " "
	var dm := RegEx.new()
	dm.compile("\\b(dragons?|giants?|moose|magic|gods?|goddess|elves?|ogres?|trolls?|kraken|hydra)\\s+don'?t exist\\b|\\bthere (is|are) no (dragons?|giants?|moose|magic|gods?|elves?|ogres?|trolls?)\\b")
	var m := dm.search(t)
	if m == null:
		return {}
	var thing: String = m.get_string(1) if m.get_string(1) != "" else m.get_string(3)
	thing = thing.trim_suffix("s")
	# We know these exist in the game world — the NPC calls out the lie.
	return {"_lie_thing": thing, "_lie_detected": true}


## HTML C29_selfTalk verbatim.
static func self_talk_q(norm: String) -> bool:
	var t := " " + norm + " "
	var re := RegEx.new()
	re.compile("\\bi( m| am) (so |such an? |a |an |really |just |a total )?(idiot|stupid|dumb|moron|fool|loser|failure|worthless|pathetic|useless|terrible|awful|horrible)( |$)")
	if re.search(t):
		return true
	var re2 := RegEx.new()
	re2.compile("\\bi hate (myself|me)\\b")
	if re2.search(t):
		return true
	var re3 := RegEx.new()
	re3.compile("\\bi( m| am) (so |really )?(bad|terrible|awful|horrible) at\\b")
	if re3.search(t):
		return true
	return false


## HTML C29_insultThemTarget: "the king is an idiot".
static func insult_them_target(norm: String) -> Dictionary:
	var t := " " + norm + " "
	for tg in THEM_TARGETS:
		var tgesc: String = tg.replace(" ", "\\s+")
		var re := RegEx.new()
		re.compile("\\b" + tgesc + "\\s+(is|are)\\s+(an?\\s+|so\\s+|such a\\s+)?(" + INSULT_WORDS + ")\\b")
		var m := re.search(t)
		if m != null:
			return {"target": tg, "insult": m.get_string(3), "phrase": m.get_string(0).strip_edges()}
		var hate_re := RegEx.new()
		hate_re.compile("\\bi hate\\s+" + tgesc + "\\b")
		if hate_re.search(t):
			return {"target": tg, "insult": "hated", "phrase": "hate"}
		# Jeremy 2026-10-06: smear pipeline — "the mayor smells like ass".
		var smell_re := RegEx.new()
		smell_re.compile("\\b" + tgesc + "\\s+smells\\s+like\\s+(an?\\s+|the\\s+)?(" + INSULT_WORDS + "|" + SMEAR_SMELL_NOUNS + ")\\b")
		var sm := smell_re.search(t)
		if sm != null:
			return {"target": tg, "insult": sm.get_string(2), "phrase": sm.get_string(0).strip_edges()}
		var stink_re := RegEx.new()
		stink_re.compile("\\b" + tgesc + "\\s+stinks\\b")
		if stink_re.search(t):
			return {"target": tg, "insult": "stinks", "phrase": "stinks"}
	return {}


## Cached insult-word signal regex for the smear pre-filter.
static var _smear_sig_rx: RegEx = null


## Quick pre-filter: does the text even look like an insult?
static func _has_smear_signal(t: String) -> bool:
	if t.contains("smells like") or t.contains(" stinks") \
			or t.contains("i hate "):
		return true
	if _smear_sig_rx == null:
		_smear_sig_rx = RegEx.new()
		_smear_sig_rx.compile("\\b(" + INSULT_WORDS + ")\\b")
	return _smear_sig_rx.search(t) != null


## Escape regex metacharacters manually (Godot 4.7 has no RegEx.escape).
static func _rx_escape(s: String) -> String:
	var out := ""
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		if ch in "\\^$.|?*+()[]{}":
			out += "\\"
		out += ch
	return out


## Escape a name for regex, keeping spaces flexible.
static func _rx_name(nm: String) -> String:
	return _rx_escape(nm).replace(" ", "\\s+")


## Try the insult constructions against one name. Returns
## {insult, phrase} or {}.
static func _match_name_insult(t: String, nm: String) -> Dictionary:
	var low := nm.to_lower()
	var cands := [low]
	var first := low.split(" ")[0]
	if first != low and first.length() >= 3:
		cands.append(first)
	for c in cands:
		var nesc := _rx_name(c)
		var re := RegEx.new()
		re.compile("\\b" + nesc + "\\s+(is|are)\\s+(an?\\s+|so\\s+|such a\\s+)?(" + INSULT_WORDS + ")\\b")
		var m := re.search(t)
		if m != null:
			return {"insult": m.get_string(3),
				"phrase": m.get_string(0).strip_edges()}
		var smell := RegEx.new()
		smell.compile("\\b" + nesc + "\\s+smells\\s+like\\s+(an?\\s+|the\\s+)?(" + INSULT_WORDS + "|" + SMEAR_SMELL_NOUNS + ")\\b")
		var sm := smell.search(t)
		if sm != null:
			return {"insult": sm.get_string(2),
				"phrase": sm.get_string(0).strip_edges()}
		var stink := RegEx.new()
		stink.compile("\\b" + nesc + "\\s+stinks\\b")
		if stink.search(t):
			return {"insult": "stinks", "phrase": "stinks"}
		var hate := RegEx.new()
		hate.compile("\\bi hate\\s+" + nesc + "\\b")
		if hate.search(t):
			return {"insult": "hated", "phrase": "hate"}
	return {}


## Jeremy 2026-10-06: player smear pipeline — detect trash-talk naming a
## specific NPC by name or a faction leader ("Grak smells like ass").
## Returns {name, id, faction, is_leader, key, insult, phrase} or {}.
## Never fires on the conversation partner (that's the direct-insult
## path), on the player's own name, or on leader pseudo-units talking
## about themselves.
static func player_smear_target(raw_norm: String, unit: Dictionary, gs) -> Dictionary:
	if gs == null:
		return {}
	var t := " " + raw_norm + " "
	if not _has_smear_signal(t) and not SimHateSpeech.is_hate_slur(t):
		return {}
	var partner_id := int(unit.get("id", 0))
	var ruler := ""
	var rv = gs.get("ruler_name")
	if rv != null:
		ruler = String(rv).to_lower()
	# 1. Named NPCs.
	var _uv = gs.get("units")
	var units: Array = _uv if _uv is Array else []
	if units != null:
		for u in units:
			var ud: Dictionary = u
			if not bool(ud.get("alive", true)):
				continue
			var uid := int(ud.get("id", 0))
			if uid == partner_id:
				continue  # direct insult — not a smear
			var nm := String(ud.get("name", ""))
			if nm == "" or nm.to_lower() == ruler:
				continue
			var hit := _match_name_insult(t, nm)
			if not hit.is_empty():
				hit["name"] = nm
				hit["id"] = uid
				hit["faction"] = String(ud.get("faction", ""))
				hit["is_leader"] = false
				hit["key"] = "npc:%d" % uid
				return hit
	# 2. Faction leaders (no world unit — pure sim entities like the player).
	var fl = gs.get("faction_leaders")
	if fl != null and fl.has_method("all_leaders"):
		for l in fl.all_leaders():
			var ld: Dictionary = l
			var nm2 := String(ld.get("name", ""))
			if nm2 == "" or nm2.to_lower() == ruler:
				continue
			var hit2 := _match_name_insult(t, nm2)
			if not hit2.is_empty():
				hit2["name"] = nm2
				hit2["id"] = 0
				hit2["faction"] = String(ld.get("faction", ""))
				hit2["is_leader"] = true
				hit2["key"] = "leader:%s" % String(ld.get("faction", ""))
				return hit2
	# 3. Slur fallback (Jeremy 2026-10-06, hard guardrail): naming a known
	# person anywhere near an IRL hate slur is ALWAYS treated as a smear
	# attempt — seed_player_smear routes it to universal condemnation via
	# bus.slur_incident. Nobody ever finds it funny, no exceptions.
	if SimHateSpeech.is_hate_slur(t):
		var named := _find_named_person(t, partner_id, ruler, gs)
		if not named.is_empty():
			named["insult"] = "slur"
			named["phrase"] = "was slurred by the crown"
			return named
	return {}


## Find a named NPC or faction leader mentioned anywhere in the text
## (no insult construction needed). Used by the slur fallback.
static func _find_named_person(t: String, partner_id: int, ruler: String,
		gs) -> Dictionary:
	var _uv = gs.get("units")
	var units: Array = _uv if _uv is Array else []
	if units != null:
		for u in units:
			var ud: Dictionary = u
			if not bool(ud.get("alive", true)):
				continue
			var uid := int(ud.get("id", 0))
			if uid == partner_id:
				continue
			var nm := String(ud.get("name", ""))
			if nm == "" or nm.to_lower() == ruler:
				continue
			if t.contains(" " + nm.to_lower() + " "):
				return {"name": nm, "id": uid,
					"faction": String(ud.get("faction", "")),
					"is_leader": false, "key": "npc:%d" % uid}
	var fl = gs.get("faction_leaders")
	if fl != null and fl.has_method("all_leaders"):
		for l in fl.all_leaders():
			var ld: Dictionary = l
			var nm2 := String(ld.get("name", ""))
			if nm2 == "" or nm2.to_lower() == ruler:
				continue
			if t.contains(" " + nm2.to_lower() + " "):
				return {"name": nm2, "id": 0,
					"faction": String(ld.get("faction", "")),
					"is_leader": true,
					"key": "leader:%s" % String(ld.get("faction", ""))}
	return {}


## Resolve a role insult ("the mayor smells like ass") to a smear target.
## "king/queen/ruler" is the player — never smeared. Other roles resolve
## to the player's court office-holder when one exists, else a
## faction-level pseudo-target.
static func role_smear_target(them: Dictionary, gs) -> Dictionary:
	if gs == null:
		return {}
	var role := String(them.get("target", ""))
	if role in ["king", "queen", "ruler"]:
		return {}  # the player insulting themselves — no rumor
	var pf := String(gs.get("player_faction"))
	var target := {"name": role, "id": 0, "faction": pf, "is_leader": false,
		"key": "role:" + role, "insult": String(them.get("insult", "")),
		"phrase": String(them.get("phrase", ""))}
	var _uv = gs.get("units")
	var units: Array = _uv if _uv is Array else []
	if units != null:
		for u in units:
			var ud: Dictionary = u
			if String(ud.get("faction", "")) != pf \
					or not bool(ud.get("alive", true)):
				continue
			var mind: Dictionary = ud.get("mind", {})
			var gov := String(mind.get("gov_role", "")).to_lower()
			var job := String(ud.get("job", "")).to_lower()
			if gov == role or job == role or gov.contains(role) \
					or job.contains(role):
				target["name"] = String(ud.get("name", role))
				target["id"] = int(ud.get("id", 0))
				target["key"] = "npc:%d" % int(ud.get("id", 0))
				break
	return target


## HTML C34_challengeQ verbatim.
static func challenge_q(norm: String, raw: String) -> bool:
	var t := " " + norm + " "
	if t.contains("you dare"):
		return true
	if t.contains("how dare you"):
		return true
	if t.contains("are you calling me"):
		return true
	if t.contains("say that again") and t.contains("i dare you"):
		return true
	if t.contains("do you know who i am"):
		return true
	if t.contains("who do you think you are"):
		return true
	if t.contains("you calling me") and raw.strip_edges().ends_with("?"):
		return true
	return false


## HTML C34_crudeInsultQ: crude sexual insults get cussed back.
static func crude_insult_q(norm: String) -> bool:
	var t := " " + norm + " "
	if t.contains("blow me away"):
		return false  # idiom, not an insult
	var crude := ["blow me", "suck my", "kiss my ass", "eat my",
		"lick my", "suck it", "bite me"]
	for c in crude:
		if t.contains(c):
			return true
	return false


## Build a reply from a pool with token substitution.
static func _pool_reply(pool: String, faction: String, unit: Dictionary,
		mem: Dictionary, tokens: Dictionary) -> Dictionary:
	var lines := ConversationResponses.get_pool(pool, faction)
	if lines.is_empty():
		return {}
	var line: String = lines[randi() % lines.size()]
	for k in tokens:
		line = line.replace("{" + String(k) + "}", String(tokens[k]))
	# Default tokens.
	line = line.replace("{name}", String(unit.get("name", "friend")))
	return {"text": line, "intent": pool, "effect": {}}


## Third-party insult: agree (enemy) or defend (ally).
static func _insult_them_reply(them: Dictionary, faction: String,
		unit: Dictionary, mem: Dictionary, gs) -> Dictionary:
	var target := String(them["target"])
	# Simple heuristic: the NPC defends their own faction's people,
	# agrees about everyone else.
	var pool := "c29_insultthem_agree"
	# If target is the player's own ruler/king, use the king variant.
	if target in ["king", "queen", "ruler"]:
		pool = "c29_insultthem_king"
	var tokens := {"target": target, "name": String(unit.get("name", "friend"))}
	return _pool_reply(pool, faction, unit, mem, tokens)


## Affinity tier for self-talk pool selection.
static func _aff_tier(unit: Dictionary, mem: Dictionary, gs) -> String:
	# Use the chatx citizen affinity if available.
	var ckey := SimChatxCitizen.key_for(int(unit.get("id", 0)))
	# Default to neutral; the full tier needs game state.
	return "neutral"


## HTML C29_insultYouReply: insult escalation through style+level pools.
## Style by affinity tier; level 1-3 by repeat insult count.
static func insult_escalation(unit: Dictionary, mem: Dictionary,
		faction: String, gs) -> String:
	var count := int(mem.get("c29_insults", 0)) + 1
	mem["c29_insults"] = count
	var level := mini(count, 3)
	# Style: hostile tier or high aggro -> rage; devoted/warm -> hurt.
	var tier := _aff_tier(unit, mem, gs)
	var style := "standard"
	if tier == "hostile":
		style = "rage"
	elif tier == "devoted" or tier == "warm":
		style = "hurt"
	elif tier == "cold":
		style = "cold"
	var pool_name := "c29_iyo_%s_%d" % [style, level]
	var lines := ConversationResponses.get_pool(pool_name, faction)
	if lines.is_empty():
		return ""
	var line: String = lines[randi() % lines.size()]
	line = line.replace("{name}", String(unit.get("name", "friend")))
	return line
