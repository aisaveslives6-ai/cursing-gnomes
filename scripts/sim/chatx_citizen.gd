## Cursing Gnomes — chatx citizen memory & relationship substrate.
##
## Verbatim port of HTML fix79's citizen episodic-memory system
## (CHATX_MEM_CAP / p13CitRecordX / p13CitMem / chatxUnitRecord /
## chatxMemRecord / chatxWitness) and the relationship arc
## (msgrCitAff / msgrCitAffDelta / _affScore / _affTier /
## chatxTradeWilling / chatxInfoWilling / chatxGreetOdds / chatxBarkWeight).
##
## Every NPC carries up to 96 episodic memories {k, t, v, day, pl, it,
## src, rep}: kind, text (140 chars), valence (-1/0/1), game day,
## player-involved flag, intensity 1-3, source tag, same-day repeat
## count. Smart prune keeps player-involved, valenced, intense, recent
## memories; neutral world observations fall off first.
##
## Grudge/favor are intensity- and recency-weighted sums over the
## citizen's player-involved memories — this is what makes an NPC who
## the player wronged stay bitter, and one the player helped stay
## grateful. Affection (-100..100) is the relationship scale that
## _affTier buckets into hostile/cold/neutral/warm/devoted, which in
## turn gates trade/info willingness and greeting odds.
##
## Pure logic — no rendering, no input, no audio.
class_name SimChatxCitizen
extends RefCounted


## Citizen episodic memory retention (HTML was 24, raised to 96).
const MEM_CAP := 96


## ckey -> Array of memory dicts.
var records := {}
## ckey -> float affection (-100..100). HTML msgrState().citAff parity.
var affection := {}


## Key for a unit's citizen record.
static func key_for(unit_id: int) -> String:
	return "u%d" % unit_id


func _arr(ckey: String) -> Array:
	if not records.has(ckey):
		records[ckey] = []
	return records[ckey]


## HTML p13CitRecordX verbatim: record a memory with valence; same
## kind+text on the same day dedups (bumps repeat count / intensity).
## Smart prune when over cap.
func record(ckey: String, kind: String, text: String, valence: int,
		opts: Dictionary = {}) -> bool:
	var arr: Array = _arr(ckey)
	var t := String(text).left(140)
	if t == "":
		return false
	var day := int(opts.get("day", 0))
	var v := 1 if valence > 0 else (-1 if valence < 0 else 0)
	var k := String(kind).left(24)
	var pl := 1 if bool(opts.get("player", false)) else 0
	var it := clampi(int(opts.get("intensity", 1)), 1, 3)
	var src := String(opts.get("src", "chat")).left(16)
	for m in arr:
		var md: Dictionary = m
		if md.get("k") == k and md.get("t") == t and int(md.get("day", -1)) == day:
			md["rep"] = int(md.get("rep", 1)) + 1
			if it > int(md.get("it", 1)):
				md["it"] = it
			return false
	arr.append({"k": k, "t": t, "v": v, "day": day, "pl": pl, "it": it,
		"src": src, "rep": 1})
	_prune(arr)
	return true


## Smart prune: player-involved, valenced, intense, recent memories
## survive; neutral world observations fall off first. Highest
## disposability score is removed.
func _prune(arr: Array) -> void:
	while arr.size() > MEM_CAP:
		var max_day := 0
		for m in arr:
			max_day = maxi(max_day, int((m as Dictionary).get("day", 0)))
		var di := -1
		var ds := -1e12
		for j in range(arr.size()):
			var cj: Dictionary = arr[j]
			var score := 0.0
			score += (1.0 - float(cj.get("pl", 0))) * 1000.0
			score += (1.0 - float(absi(int(cj.get("v", 0))))) * 500.0
			score += (4.0 - float(cj.get("it", 1))) * 100.0
			score += float(max_day - int(cj.get("day", 0)))
			score -= float(cj.get("rep", 1)) * 10.0
			if score > ds:
				ds = score
				di = j
		if di >= 0:
			arr.remove_at(di)
		else:
			break


## HTML chatxWitness: the game calls this when an NPC sees the player
## do something notable. Records the memory and moves affection.
func witness(ckey: String, kind: String, text: String, valence: int,
		opts: Dictionary = {}) -> bool:
	var o := opts.duplicate()
	if not o.has("player"):
		o["player"] = false
	if not o.has("intensity"):
		o["intensity"] = 2
	if not o.has("src"):
		o["src"] = "witness"
	var ok := record(ckey, kind, text, valence, o)
	var d := 0.0
	if valence > 0:
		d = 2.0
	elif valence < 0:
		d = -3.0
	if d != 0.0:
		aff_delta(ckey, d)
	return ok


## HTML chatxUnitRecord parity: record onto the unit's own memory
## (used for non-citizen-keyed units; stored under the unit key).
func unit_record(unit_id: int, kind: String, text: String, valence: int,
		opts: Dictionary = {}) -> bool:
	var o := opts.duplicate()
	if not o.has("src"):
		o["src"] = "world"
	return record(key_for(unit_id), kind, text, valence, o)


## HTML chatxMemRecord: record a player-directed memory for a citizen.
func mem_record(ckey: String, kind: String, text: String, valence: int,
		opts: Dictionary = {}) -> bool:
	var o := opts.duplicate()
	if not o.has("player"):
		o["player"] = true
	if not o.has("src"):
		o["src"] = "chat"
	return record(ckey, kind, text, valence, o)


## HTML p13CitGrudge verbatim: intensity- and recency-weighted sum of
## player-caused harms. Recency: weight 4 this decade of days, decaying
## to 1 (4 - min(3, age_days / 10)).
func grudge(ckey: String, day: int) -> int:
	var s := 0
	for m in _arr(ckey):
		var md: Dictionary = m
		if int(md.get("v", 0)) < 0 and int(md.get("pl", 0)) == 1:
			var age := maxi(0, day - int(md.get("day", 0)))
			var w := maxi(1, 4 - mini(3, age / 10))
			s += maxi(1, int(md.get("it", 1))) * w
	return s


## HTML p13CitFavor verbatim: same weighting over kindnesses.
func favor(ckey: String, day: int) -> int:
	var s := 0
	for m in _arr(ckey):
		var md: Dictionary = m
		if int(md.get("v", 0)) > 0 and int(md.get("pl", 0)) == 1:
			var age := maxi(0, day - int(md.get("day", 0)))
			var w := maxi(1, 4 - mini(3, age / 10))
			s += maxi(1, int(md.get("it", 1))) * w
	return s


## HTML p13CitUnprompted: strongest old (not from today)
## player-involved valenced memory, for unprompted callbacks.
func unprompted(ckey: String, day: int) -> Dictionary:
	var best := {}
	var best_score := -1
	for m in _arr(ckey):
		var md: Dictionary = m
		if int(md.get("pl", 0)) == 1 and int(md.get("v", 0)) != 0 \
				and (day - int(md.get("day", 0))) >= 1:
			var score := maxi(1, int(md.get("it", 1))) * 2 + int(md.get("rep", 1))
			if score > best_score:
				best_score = score
				best = md
	return best


## HTML p13CitUnpromptedLine: "Remember when X? ..." callback line.
func unprompted_line(ckey: String, day: int) -> String:
	var m := unprompted(ckey, day)
	if m.is_empty():
		return ""
	var op := "I still smile about it." if int(m.get("v", 0)) > 0 \
		else "I haven't forgotten. Not even a little."
	return "Remember when %s? %s" % [String(m.get("t", "")), op]


## Most recent player-involved memory of a given kind (e.g. "insult"),
## for "what offended you?" style callbacks. Returns {} when none.
func last_of_kind(ckey: String, kind: String) -> Dictionary:
	var best := {}
	for m in _arr(ckey):
		var md: Dictionary = m
		if String(md.get("k", "")) == kind and int(md.get("pl", 0)) == 1:
			best = md
	return best


## HTML msgrCitAff: citizen affection toward the player (-100..100).
func aff(ckey: String) -> float:
	return clampf(float(affection.get(ckey, 0.0)), -100.0, 100.0)


## HTML msgrCitAffDelta: move affection, clamped.
func aff_delta(ckey: String, d: float) -> float:
	affection[ckey] = clampf(float(affection.get(ckey, 0.0)) + d, -100.0, 100.0)
	return float(affection[ckey])


## HTML _affScore adapted: blocked -> -100, at war -> -100, otherwise
## the citizen affection scale. (HTML also folds ruler relation score
## and friend bonus for ruler keys; citizens are the Godot path.)
func aff_score(ckey: String, blocked: bool, at_war: bool) -> float:
	if blocked:
		return -100.0
	if at_war:
		return -100.0
	return aff(ckey)


## HTML _affTier verbatim buckets.
static func aff_tier_for(score: float) -> String:
	if score <= -60.0:
		return "hostile"
	if score <= -20.0:
		return "cold"
	if score < 35.0:
		return "neutral"
	if score < 75.0:
		return "warm"
	return "devoted"


func aff_tier(ckey: String, blocked: bool, at_war: bool) -> String:
	return aff_tier_for(aff_score(ckey, blocked, at_war))


## HTML chatxTradeWilling verbatim: relationship tier gates trade, and
## a strong angry/vengeful/bitter mood halves it; joyful/grateful
## lifts it 20%.
func trade_willing(tier: String, mood: String, mood_i: int) -> float:
	var o := 0.65
	match tier:
		"hostile":
			o = 0.15
		"cold":
			o = 0.45
		"warm":
			o = 0.85
		"devoted":
			o = 1.0
	if mood_i >= 3 and mood in ["angry", "vengeful", "bitter"]:
		o *= 0.5
	if mood_i >= 3 and mood in ["joyful", "grateful"]:
		o = minf(1.0, o * 1.2)
	return o


## HTML chatxInfoWilling verbatim.
func info_willing(tier: String, mood: String, mood_i: int) -> float:
	var o := 0.7
	match tier:
		"hostile":
			o = 0.1
		"cold":
			o = 0.4
		"warm":
			o = 0.9
		"devoted":
			o = 1.0
	if mood_i >= 3 and mood in ["bitter", "angry"]:
		o *= 0.5
	return o


## HTML chatxGreetOdds verbatim: whether the NPC even feels like
## greeting the player right now.
func greet_odds(tier: String, mood: String, mood_i: int) -> float:
	var o := 0.8
	match tier:
		"hostile":
			o = 0.25
		"cold":
			o = 0.55
		"warm":
			o = 0.95
		"devoted":
			o = 1.0
	if mood_i >= 3 and mood in ["angry", "grieving", "exhausted", "vengeful"]:
		o *= 0.5
	if mood_i >= 3 and mood in ["joyful", "excited", "lovesick"]:
		o = minf(1.0, o * 1.25)
	return o


## HTML chatxBarkWeight verbatim: bark frequency weight for ambient
## chatter systems.
func bark_weight(mood: String, mood_i: int) -> float:
	if mood_i < 2:
		return 1.0
	if mood in ["angry", "excited", "joyful"]:
		return 1.6
	if mood in ["sad", "grieving", "exhausted", "lonely"]:
		return 0.5
	return 1.0


## Save/load round-trip.
func to_dict() -> Dictionary:
	return {"records": records, "affection": affection}


func from_dict(d: Dictionary) -> void:
	records = d.get("records", {})
	affection = d.get("affection", {})
