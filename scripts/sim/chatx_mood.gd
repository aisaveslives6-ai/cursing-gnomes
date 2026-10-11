## Cursing Gnomes — chatx mood/affect engine (Jeremy's NPC emotion simulation).
##
## Verbatim port of HTML fix79's CHATX mood system (lines 82495-82711):
## the 22-mood taxonomy, per-faction baselines, the day-decayed
## per-citizen affect state, chatxMoodCompute (mood computed from the
## NPC's LIFE — never random), chatxMoodEvent (dialogue events drive
## the affect state), chatxMoodLine (mood-voiced line picker with
## per-NPC anti-repetition), chatxMoodFlavor (strong-mood asides),
## and chatxPackMood/chatxUnpackMood (save/load).
##
## Each NPC carries {m, i, since, cause}: primary mood, intensity 1-5,
## the game day it took hold, and what caused it. Precedence:
##   explicit state (decayed 1/day, unless cause == 'life')
##     > computed-from-life > faction baseline.
##
## chatxMoodCompute scoring (verbatim):
##   grudge >= 8 -> bitter 3 | >= 4 -> angry 2
##   favor  >= 8 -> grateful 3 | >= 4 -> content 2
##   unprompted death memory -> grieving 5
##   unprompted negative (intensity >= 3) -> vengeful 3
##   affection devoted -> joyful 2 | warm -> content 2
##   affection cold -> lonely 2 | hostile -> vengeful 2
##   hunger < 20 -> angry 2 | energy < 20 -> exhausted 3
##   workload > 70 -> stressed 2 | no job -> bored 1
##   at war -> anxious 2 | festival active -> excited 2
##   ogre: excited 1, angry 1 | elf: content 1 | gnome: amused 1
##   winner takes all; intensity = min(5, 1 + weight/2).
##
## Works with SimChatxCitizen (memory/grudge/favor/affection) and
## ChatxMoodLines (line data). Pure logic — no rendering, no input.
class_name SimChatxMood
extends RefCounted


## The 22-mood taxonomy, HTML verbatim.
const MOODS: Array[String] = ["joyful", "content", "proud", "excited",
	"grateful", "amused", "sad", "lonely", "grieving", "angry", "bitter",
	"jealous", "afraid", "anxious", "stressed", "exhausted", "bored",
	"hopeful", "guilty", "ashamed", "vengeful", "lovesick"]

## Per-faction emotional baselines, HTML verbatim. Unknown factions
## (incl. undead) fall back to gnome, exactly like the HTML.
const MOOD_BASE := {"gnome": "amused", "human": "content", "elf": "content",
	"ogre": "excited"}

## Anti-repetition window for line picks (HTML _CT_REPEAT_WINDOW).
const REPEAT_WINDOW := 10


## ckey -> {m, i, since, cause}
var states := {}
## ckey -> Array of recent line-pool indices (per mood+context key).
var recent := {}


## Map Godot plural faction ids to HTML singular race keys
## (factions.gd soul_of() precedent).
static func race_of(faction: String) -> String:
	match faction:
		"ogres":
			return "ogre"
		"elves":
			return "elf"
		"humans":
			return "human"
		"gnomes":
			return "gnome"
	return faction


## HTML _chatxMoodFaction: canonical faction or gnome fallback.
## Godot extension: undead (no HTML equivalent) uses the human
## baseline, following the factions.gd soul_of() precedent.
static func faction_of(faction: String) -> String:
	var r := race_of(faction)
	if r == "undead":
		return "human"
	return r if MOOD_BASE.has(r) else "gnome"


## HTML _chatxMoodBaseline.
static func baseline(faction: String) -> Dictionary:
	var f := faction_of(faction)
	return {"m": String(MOOD_BASE.get(f, "content")), "i": 1, "since": 0,
		"cause": "baseline"}


## Current mood: explicit state (decayed by day) > computed-from-life
## > baseline. HTML chatxMoodGet verbatim.
## life: {grudge, favor, unprompted_kind, unprompted_v, unprompted_it,
##   tier, hunger, energy, workload, has_job, at_war, festival, faction}
func get_mood(ckey: String, day: int, life: Dictionary) -> Dictionary:
	var st: Dictionary = states.get(ckey, {})
	if not st.is_empty() and st.has("m") and String(st["m"]) in MOODS:
		var el := day - int(st.get("since", 0))
		if el > 0 and String(st.get("cause", "")) != "life":
			var ni := int(st.get("i", 1)) - el
			if ni <= 0:
				clear(ckey)
			else:
				st["i"] = ni
				states[ckey] = st
				return st
		else:
			return st
	var comp := compute(life)
	if not comp.is_empty():
		comp["since"] = day
		comp["cause"] = "life"
		return comp
	return baseline(String(life.get("faction", "gnome")))


## HTML chatxMoodSet: stamp an explicit mood with a cause.
func set_mood(ckey: String, mood: String, intensity: int, cause: String,
		day: int) -> bool:
	if not mood in MOODS:
		return false
	states[ckey] = {"m": mood, "i": clampi(intensity, 1, 5), "since": day,
		"cause": String(cause).left(80)}
	return true


## HTML _chatxMoodClear.
func clear(ckey: String) -> void:
	states.erase(ckey)


## HTML chatxMoodCompute verbatim. Returns {m, i} or {} when nothing
## scores (caller falls back to baseline).
func compute(life: Dictionary) -> Dictionary:
	var scores := {}
	var grudge := int(life.get("grudge", 0))
	var favor := int(life.get("favor", 0))
	if grudge >= 8:
		scores["bitter"] = int(scores.get("bitter", 0)) + 3
	elif grudge >= 4:
		scores["angry"] = int(scores.get("angry", 0)) + 2
	if favor >= 8:
		scores["grateful"] = int(scores.get("grateful", 0)) + 3
	elif favor >= 4:
		scores["content"] = int(scores.get("content", 0)) + 2
	var uk := String(life.get("unprompted_kind", ""))
	var uv := int(life.get("unprompted_v", 0))
	var uit := int(life.get("unprompted_it", 0))
	if uk == "death":
		scores["grieving"] = int(scores.get("grieving", 0)) + 5
	elif uv < 0 and uit >= 3:
		scores["vengeful"] = int(scores.get("vengeful", 0)) + 3
	var tier := String(life.get("tier", "neutral"))
	match tier:
		"devoted":
			scores["joyful"] = int(scores.get("joyful", 0)) + 2
		"warm":
			scores["content"] = int(scores.get("content", 0)) + 2
		"cold":
			scores["lonely"] = int(scores.get("lonely", 0)) + 2
		"hostile":
			scores["vengeful"] = int(scores.get("vengeful", 0)) + 2
	var hunger := int(life.get("hunger", 50))
	var energy := int(life.get("energy", 50))
	if hunger < 20:
		scores["angry"] = int(scores.get("angry", 0)) + 2
	if energy < 20:
		scores["exhausted"] = int(scores.get("exhausted", 0)) + 3
	# HTML guards the whole work block on `if (u)`: no unit context,
	# no job scoring.
	if life.has("has_job"):
		if bool(life["has_job"]):
			if int(life.get("workload", 0)) > 70:
				scores["stressed"] = int(scores.get("stressed", 0)) + 2
		else:
			scores["bored"] = int(scores.get("bored", 0)) + 1
	if bool(life.get("at_war", false)):
		scores["anxious"] = int(scores.get("anxious", 0)) + 2
	if bool(life.get("festival", false)):
		scores["excited"] = int(scores.get("excited", 0)) + 2
	var faction := String(life.get("faction", "gnome"))
	if faction == "ogre":
		scores["excited"] = int(scores.get("excited", 0)) + 1
		scores["angry"] = int(scores.get("angry", 0)) + 1
	elif faction == "elf":
		scores["content"] = int(scores.get("content", 0)) + 1
	elif faction == "gnome":
		scores["amused"] = int(scores.get("amused", 0)) + 1
	var best := ""
	var bw := 0
	for m in MOODS:
		var w := int(scores.get(m, 0))
		if w > bw:
			bw = w
			best = m
	if best == "":
		return {}
	return {"m": best, "i": mini(5, 1 + bw / 2)}


## HTML chatxMoodEvent verbatim: dialogue events drive the affect
## state. tier = affection tier, hot = ruler aggro >= 60.
func apply_event(ckey: String, intent: String, tier: String, hot: bool,
		day: int) -> void:
	match intent:
		"praise":
			set_mood(ckey, "proud", 3, "praised by player", day)
		"thanks":
			set_mood(ckey, "grateful", 2, "thanked by player", day)
		"insult":
			var m := "vengeful" if tier in ["hostile", "cold"] or hot \
				else "angry"
			set_mood(ckey, m, 3, "insulted by player", day)
		"threat":
			set_mood(ckey, "angry" if hot else "afraid", 3,
				"threatened by player", day)
		"crude_direct":
			set_mood(ckey, "angry", 4, "crude provocation", day)
		"romance_proposition":
			if tier in ["devoted", "warm"]:
				set_mood(ckey, "lovesick", 3, "romance reciprocated", day)
			elif tier in ["hostile", "cold"]:
				set_mood(ckey, "bitter", 2, "unwanted proposition", day)
			else:
				set_mood(ckey, "amused", 2, "flattered by proposition", day)
		"apology":
			set_mood(ckey, "content", 2, "apology accepted", day)
		"forgiveness":
			set_mood(ckey, "grateful", 3, "forgiven by player", day)
		"love_declaration":
			if tier in ["hostile", "cold"]:
				set_mood(ckey, "angry", 2, "unwanted declaration", day)
			else:
				set_mood(ckey, "lovesick", 4, "loved by player", day)
		"joke_request":
			set_mood(ckey, "amused", 2, "shared a laugh", day)
		"dare":
			set_mood(ckey, "excited", 2, "dared by player", day)
		"acknowledgment":
			set_mood(ckey, "content", 1, "player backed down", day)


## HTML chatxMoodLine: pick a mood-voiced line from the faction pool,
## with per-NPC anti-repetition (HTML _pickNoRepeat: 35% favorite
## bias, 40 tries outside the recent window, else least-recent).
func pick_line(mood: String, faction: String, ckey: String,
		context: String = "chat") -> String:
	var grp: Dictionary = ChatxMoodLines.LINES.get(mood, {})
	if grp.is_empty():
		return ""
	# Undead has no HTML voice pool: use the human pool (dour fits the
	# dead better than manic gnome), then the verbatim gnome fallback.
	var f := race_of(faction)
	if f == "undead":
		f = "human"
	var pool: Array = grp.get(f, grp.get("gnome", []))
	if pool.is_empty():
		return ""
	return pool[_pick_no_repeat(pool, ckey, "moodline:%s:%s" % [mood, context])]


func _pick_no_repeat(pool: Array, ckey: String, key: String) -> int:
	if pool.size() < 2:
		return 0
	var rk := "%s|%s" % [ckey, key]
	var rec: Array = recent.get(rk, [])
	var win := mini(REPEAT_WINDOW, pool.size() - 1)
	# Deterministic favorite: stable per citizen, like the HTML's
	# ruler-key hash (weird/hon/aggro/dip folded in there).
	var sig := 0
	for ch in ckey:
		sig = (sig * 31 + ch.unicode_at(0)) & 0x7fffffff
	var fav := sig % pool.size()
	var in_win := func(i: int) -> bool:
		for j in range(mini(rec.size(), win)):
			if int(rec[j]) == i:
				return true
		return false
	var idx := -1
	if not in_win.call(fav) and randf() < 0.35:
		idx = fav
	var t := 0
	while idx < 0 and t < 40:
		var c := randi() % pool.size()
		if not in_win.call(c):
			idx = c
		t += 1
	if idx < 0:
		var best := 0
		var best_pos := -2
		for i in range(pool.size()):
			var p := rec.find(i)
			if p < 0:
				best = i
				break
			if p > best_pos:
				best_pos = p
				best = i
		idx = best
	rec.push_front(idx)
	while rec.size() > REPEAT_WINDOW:
		rec.pop_back()
	recent[rk] = rec
	return idx


## HTML chatxMoodFlavor: when a mood runs strong (i >= 3), 22% of
## replies gain a short mood aside.
func flavor(text: String, mood: String, intensity: int, ckey: String) -> String:
	if intensity < 3 or randf() > 0.22:
		return text
	var pool: Array = ChatxMoodLines.ASIDES.get(mood, [])
	if pool.is_empty():
		return text
	var idx := _pick_no_repeat(pool, ckey, "moodaside:%s" % mood)
	return text + " " + String(pool[idx])


## HTML chatxPackMood / chatxUnpackMood: affect state rides with its
## citizen for save/load.
func pack() -> Dictionary:
	return states.duplicate(true)


func unpack(saved: Dictionary) -> void:
	states.clear()
	for k in saved:
		var s: Dictionary = saved[k]
		if s.get("m") in MOODS:
			states[k] = {"m": String(s["m"]),
				"i": clampi(int(s.get("i", 1)), 1, 5),
				"since": int(s.get("since", 0)),
				"cause": String(s.get("cause", "")).left(80)}
