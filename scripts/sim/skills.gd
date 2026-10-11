class_name SimSkills
extends RefCounted
## Cursing Gnomes — levelable NPC skill system (Jeremy 2026-10-11).
##
## Every NPC tracks XP per skill; skills improve with USE:
##   medicine — doctors treating the sick (disease.gd) and healing (work.gd)
##   combat   — fighters landing kills (combat.gd)
##   farming  — farmers gathering (work.gd)
##   mining   — miners gathering (work.gd)
##   woodcutting — woodcutters gathering (work.gd)
##   building — builders constructing (work.gd)
##
## Level curve: level = floor(sqrt(xp / XP_PER_LEVEL)), capped at MAX_LEVEL.
## Diminishing returns are structural — each level costs quadratically more.
## Levels have REAL effects:
##   medicine: cure chance 0.30 + 0.06/level (cap 0.95); heal rate x(1+0.05/level)
##   combat:   damage dealt x(1 + 0.08/level)
##   farming/mining/woodcutting: gather yield x(1 + 0.08/level)
##   building: construction speed x(1 + 0.08/level)
##
## Storage: u["skills"] = {"medicine": {"xp": float, "level": int}, ...}.
## Unit dicts serialize wholesale, so skills ride save/load for free.
## Pure logic — no rendering. Level-ups toast (player faction) and publish
## a Gazette "master" story at level 10.


const SKILLS: Array[String] = ["medicine", "combat", "farming", "mining",
	"building", "woodcutting"]
const XP_PER_LEVEL := 50.0
const MAX_LEVEL := 10
const MASTER_LEVEL := 10
## Cure math (plague treatment): base chance + per medicine level.
## Lives here so the dependency runs one way: disease -> skills.
const CURE_BASE := 0.30
const CURE_PER_LEVEL := 0.065  # level 10 -> 0.95, the cap
const CURE_CAP := 0.95
## Continuous-work XP: 1 XP per TICK_XP_SECONDS of active work.
const TICK_XP_SECONDS := 5.0

## Job -> skill trained by doing that job (work.gd hook).
const JOB_SKILL := {
	"doctor": "medicine",
	"farmer": "farming",
	"miner": "mining",
	"woodcutter": "woodcutting",
	"builder": "building",
	"roadbuilder": "building",
}


## --- Static API -------------------------------------------------------------

static func level_for_xp(xp: float) -> int:
	var lv := int(floor(sqrt(maxf(0.0, xp) / XP_PER_LEVEL)))
	return mini(lv, MAX_LEVEL)


static func _skill_entry(unit: Dictionary, skill: String) -> Dictionary:
	if not (unit.get("skills") is Dictionary):
		unit["skills"] = {}
	var skills: Dictionary = unit["skills"]
	var e: Dictionary = skills.get(skill, {})
	if e.is_empty():
		e = {"xp": 0.0, "level": 0}
		skills[skill] = e
	return e


static func xp_of(unit: Dictionary, skill: String) -> float:
	var skills: Dictionary = unit.get("skills", {})
	var e: Dictionary = skills.get(skill, {})
	return float(e.get("xp", 0.0))


static func level_of(unit: Dictionary, skill: String) -> int:
	var skills: Dictionary = unit.get("skills", {})
	var e: Dictionary = skills.get(skill, {})
	return int(e.get("level", 0))


## Grant XP; returns the (possibly new) level. Handles level-up fanfare.
static func grant(gs: GameState, unit: Dictionary, skill: String,
		amount: float) -> int:
	if unit.is_empty() or not (unit is Dictionary):
		return 0
	if not skill in SKILLS or amount <= 0.0:
		return level_of(unit, skill)
	var e := _skill_entry(unit, skill)
	var old_lv := int(e.get("level", 0))
	e["xp"] = float(e.get("xp", 0.0)) + amount
	var new_lv := level_for_xp(float(e["xp"]))
	if new_lv > old_lv:
		e["level"] = new_lv
		_on_level_up(gs, unit, skill, new_lv)
	return new_lv


## Continuous-work XP drip: call per tick with delta; banks 1 XP per
## TICK_XP_SECONDS of work. Bounded — one float per skill per unit.
static func grant_tick(gs: GameState, unit: Dictionary, skill: String,
		delta: float) -> void:
	if unit.is_empty() or not skill in SKILLS or delta <= 0.0:
		return
	var key := "skill_tick_" + skill
	var acc := float(unit.get(key, 0.0)) + delta
	if acc >= TICK_XP_SECONDS:
		acc -= TICK_XP_SECONDS
		grant(gs, unit, skill, 1.0)
	unit[key] = acc


static func skill_for_job(job: String) -> String:
	return String(JOB_SKILL.get(job, ""))


static func _on_level_up(gs: GameState, unit: Dictionary, skill: String,
		lv: int) -> void:
	if gs == null:
		return
	var bus = gs.get("bus")
	var dname := SimPersonality.display_name(unit)
	var label := "%s reached %s %d!" % [dname, skill.capitalize(), lv]
	if String(unit.get("faction", "")) == gs.player_faction and bus != null \
			and bus.has_signal("toast"):
		bus.toast.emit(label)
	if lv >= MASTER_LEVEL:
		SimGazette.publish_or_emit(gs,
			"MASTER OF THE CRAFT — %s" % dname,
			"%s has achieved true mastery of %s — level %d. The realm's finest %s, by every measure." % [
				dname, skill, lv,
				{"medicine": "healer", "combat": "warrior",
					"farming": "farmer", "mining": "miner",
					"building": "builder", "woodcutting": "woodcutter"}.get(skill, "worker")],
			"mastery")


## --- Effect multipliers -----------------------------------------------------

static func combat_mult(unit: Dictionary) -> float:
	return 1.0 + 0.08 * float(level_of(unit, "combat"))


static func yield_mult(unit: Dictionary, skill: String) -> float:
	return 1.0 + 0.08 * float(level_of(unit, skill))


static func build_mult(unit: Dictionary) -> float:
	return 1.0 + 0.08 * float(level_of(unit, "building"))


static func heal_mult(unit: Dictionary) -> float:
	return 1.0 + 0.05 * float(level_of(unit, "medicine"))


## Cure chance for a doctor treating plague: base + per medicine level.
static func cure_chance(doctor: Dictionary) -> float:
	return minf(CURE_CAP, CURE_BASE \
		+ CURE_PER_LEVEL * float(level_of(doctor, "medicine")))


## One-line profile summary: "Medicine 3 · Combat 1".
static func summary(unit: Dictionary) -> String:
	var parts: Array[String] = []
	var skills: Dictionary = unit.get("skills", {})
	for s: String in SKILLS:
		var e: Dictionary = skills.get(s, {})
		var lv := int(e.get("level", 0))
		if lv > 0:
			parts.append("%s %d" % [s.capitalize(), lv])
	return " · ".join(parts)
