class_name SimUnhinged
extends RefCounted
## Cursing Gnomes — the unhinged trait (Jeremy 2026-10-06).
##
## Furious (ruler_mood <= -60) + unhinged trait = the NPC cusses the player
## out AND spams DMs instead of one cold reply. Non-unhinged NPCs at the
## same anger level stay cold/hostile but never spam — the spam is the
## unhinged signature.
##
## Sampling is without replacement per NPC: every unhinged NPC can fire
## 100+ distinct cuss-outs before any repeat. Escalation tier follows
## fury depth: heated (-60) -> furious (-78) -> unhinged (-92).
##
## Apologies still land (mood bump) so players can de-escalate: a few
## sincere sorries lift the NPC out of the cuss-out zone.
##
## Pure logic — no rendering, no input, no audio, no network.


## Mood at/below which an unhinged NPC cusses out (matches phone.gd
## affinity_for "hostile" tier).
const FURIOUS_AT := -60.0
const TIER_FURIOUS_AT := -78.0
const TIER_UNHINGED_AT := -92.0
## Mood bump per apology while cussing out (de-escalation path).
const APOLOGY_BUMP := 10.0
## Extra spam messages queued after the main cuss-out reply.
const SPAM_EXTRAS := 3

const APOLOGY_KEYS := ["sorry", "apolog", "forgive", "my bad",
	"please forgive"]


## Per-NPC used-line tracking: "uid:voice:tier" -> Array of used indices.
var _used := {}


static func is_unhinged(unit: Dictionary) -> bool:
	return SimPersonality.is_unhinged(unit)


## Cuss-out voice for an NPC: elves always elegant; otherwise persona-mapped.
static func voice_for(unit: Dictionary) -> String:
	if String(unit.get("faction", "")) == "elves":
		return "elegant"
	match SimPersonality.persona_of(unit):
		"blunt", "grizzled":
			return "blunt"
		"scheming", "oily":
			return "mischievous"
		"proud", "haughty":
			return "cold"
		"honorable", "earnest", "loyal":
			return "diplomatic"
	return "neutral"


## True when this NPC should cuss out instead of conversing: unhinged
## trait + furious at the ruler. conv is SimConversation (ruler_mood).
static func should_cuss_out(conv, unit: Dictionary) -> bool:
	if not is_unhinged(unit):
		return false
	return conv.ruler_mood(int(unit.get("id", 0))) <= FURIOUS_AT


## Escalation tier for a mood score.
static func tier_for(mood: float) -> String:
	if mood <= TIER_UNHINGED_AT:
		return "unhinged"
	if mood <= TIER_FURIOUS_AT:
		return "furious"
	return "heated"


## Full cuss-out reply dict for SimConversation.reply: main text +
## spam extras in the effect. Shape matches normal reply dicts.
func cuss_out_reply(conv, unit: Dictionary, text: String,
		ruler_name: String) -> Dictionary:
	var uid := int(unit.get("id", 0))
	# Apologies still land while cussing out — the de-escalation path.
	var low := String(text).to_lower()
	for k in APOLOGY_KEYS:
		if low.contains(k):
			conv.set_ruler_mood(uid, conv.ruler_mood(uid) + APOLOGY_BUMP)
			break
	var mood: float = conv.ruler_mood(uid)
	var voice := voice_for(unit)
	var tier := tier_for(mood)
	var npc_name := SimPersonality.display_name(unit)
	var faction := String(unit.get("faction", ""))
	var lines: Array = []
	for i in range(1 + SPAM_EXTRAS):
		lines.append(_draw(uid, voice, tier, ruler_name, npc_name, faction))
	var extras: Array = lines.slice(1)
	return {
		"text": String(lines[0]),
		"intent": "unhinged_cussout",
		"effect": {"type": "unhinged_spam", "extras": extras},
		"flow": {},
	}


## Proactive ambush opener: ONE cuss-out line for an NPC-initiated DM.
## Returns "" when the NPC has no business ambushing (not unhinged or not
## furious). Shares the same without-replacement _draw pool as the reactive
## path, so ambushes never repeat lines the NPC already used on the player.
## Tier follows current fury depth: first ambushes at -60 draw "heated",
## repeat ambushes climb to "furious"/"unhinged" as mood worsens.
func ambush_line(conv, unit: Dictionary, ruler_name: String) -> String:
	if not should_cuss_out(conv, unit):
		return ""
	var uid := int(unit.get("id", 0))
	var mood: float = conv.ruler_mood(uid)
	return _draw(uid, voice_for(unit), tier_for(mood), ruler_name,
		SimPersonality.display_name(unit), String(unit.get("faction", "")))


## Draw one line without replacement for this NPC (reshuffles when exhausted).
## No-repeat spans the whole voice pool (108+ lines): the current tier is
## preferred, but when it's exhausted we fall through to the other tiers
## rather than repeat — so every unhinged NPC fires 100+ distinct cuss-outs
## before any repeat.
func _draw(uid: int, voice: String, tier: String, ruler: String,
		npc_name: String, faction: String) -> String:
	var pool: Dictionary = SimCussouts.POOLS.get(voice,
		SimCussouts.POOLS["neutral"])
	var key := "%d:%s" % [uid, voice]
	var used: Dictionary = (_used.get(key, {}) as Dictionary).duplicate()
	# If the whole voice pool is exhausted, reshuffle.
	var total := 0
	for t in SimCussouts.TIERS:
		total += (used.get(t, []) as Array).size()
	var pool_total := 0
	for t in SimCussouts.TIERS:
		pool_total += ((pool.get(t, []) as Array)).size()
	if total >= pool_total and pool_total > 0:
		used = {}
	# Preferred tier first, then the rest.
	var order: Array = [tier]
	for t in SimCussouts.TIERS:
		if t != tier:
			order.append(t)
	var chosen_tier := tier
	var lines: Array = []
	for t in order:
		var cand: Array = pool.get(t, [])
		var used_idxs: Array = used.get(t, [])
		var avail: Array = []
		for i in range(cand.size()):
			if not (i in used_idxs):
				avail.append(i)
		if not avail.is_empty():
			chosen_tier = t
			lines = cand
			var idx: int = avail[randi() % avail.size()]
			var new_used: Array = (used.get(t, []) as Array).duplicate()
			new_used.append(idx)
			used[t] = new_used
			_used[key] = used
			return SimCussouts.fill(String(lines[idx]), ruler, npc_name,
				faction)
	return "..."


## How many distinct lines this NPC has used in a voice+tier (test hook).
func used_count(uid: int, voice: String, tier: String) -> int:
	return (((_used.get("%d:%s" % [uid, voice], {}) as Dictionary))\
		.get(tier, []) as Array).size()


## Total distinct lines used in a voice across all tiers (test hook).
func used_total(uid: int, voice: String) -> int:
	var n := 0
	var d: Dictionary = _used.get("%d:%s" % [uid, voice], {})
	for t in SimCussouts.TIERS:
		n += (d.get(t, []) as Array).size()
	return n
