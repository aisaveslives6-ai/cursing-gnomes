class_name SimMind
extends RefCounted
## Cursing Gnomes — NPC mind coordinator (Milestone 5: minds).
##
## The conductor for urges, emotion, memories, personality, and dialogue.
## The world ticks each unit's mind inside its round-robin AI budget (same
## 32-units-per-tick slice as WorkerAI — minds never run for every NPC
## every frame, that's the 60 fps rule).
##
## tick_unit() returns true when the mind consumed the unit's AI slice
## (satisfying a critical urge or fleeing) — the world then skips the
## unit's job/combat AI that tick. False means "business as usual".
##
## Urge overrides are the HTML design: critical hunger/bladder/energy
## preempt job assignments. Emotion + bravery decide fight vs. flight.
## Chatter goes out over the bus (unit_said) for the visual layer.
##
## Pure logic — no rendering, no input, no audio, no network.


const FLEE_SPEED := 130.0
const FLEE_DURATION := 6.0

## Perf 2026-10-05 (R14): background mind decay (urge/emotion/mood/memory
## decay + chatter) runs at 20Hz per unit, staggered by unit id — the same
## round-robin pattern as combat.tick_medics and the wild-animal brain.
## All decay rates are linear in delta, so a scaled delta keeps them exact;
## the critical-urge CHECK still runs every slice, so reactions are never
## more than a slice late. Zero visual/behavior change.
const MIND_DECAY_SLICES := 3


var _gs: GameState
var urges: SimUrges
var emotion: SimEmotion
var mood: SimMood
var memories: SimMemories
var interiors  # SimInteriors — set by world; NPCs enter buildings for urges


func _init(game_state: GameState) -> void:
	_gs = game_state
	urges = SimUrges.new(game_state)
	emotion = SimEmotion.new()
	mood = SimMood.new()
	memories = SimMemories.new(game_state)


## Ensures all mind state exists on a unit record.
##
## R22: hot-path fast exit. tick_unit calls ensure on every budgeted slice,
## so after the first full ensure a single has() replaces ~10 has() checks
## + 5 sub-ensure method calls (measured 7.2us/call -> the mind branch's
## #1 inner cost). The flag is set only after ALL sub-ensures completed, so
## a partially-ensured unit can never take the fast path. Nothing in the
## codebase erases these keys, so the flag stays valid for the unit's life.
func ensure(unit: Dictionary) -> void:
	if unit.has("_mind_ok"):
		return
	if not unit.has("mind"):
		unit["mind"] = {
			"traits": SimPersonality.traits_for(int(unit.get("id", 0)),
				String(unit.get("faction", "humans"))),
			"name": "",
			"critical_urge": "",
		}
		var traits: Dictionary = unit["mind"]["traits"]
		unit["mind"]["name"] = String(traits["name"])
	urges.ensure(unit)
	emotion.ensure(unit)
	mood.ensure(unit)
	memories.ensure(unit)
	if not unit.has("mind_state"):
		unit["mind_state"] = ""
	if not unit.has("fleeing"):
		unit["fleeing"] = false
	if not unit.has("flee_timer"):
		unit["flee_timer"] = 0.0
	if not unit.has("chatter_cd"):
		unit["chatter_cd"] = SimPersonality.chatter_interval(unit) * 0.5
	unit["_mind_ok"] = true


## True on decay slices: every MIND_DECAY_SLICES-th budgeted slice for this
## unit, staggered by unit id so the cost spreads evenly across frames
## (per Jeremy 2026-10-05: "evenly distribute the cycles"). The counter
## lives on the unit record; missing (old saves) starts staggered.
func _decay_due(unit: Dictionary) -> bool:
	var cd: int = int(unit.get("_mind_decay_cd", -1))
	if cd < 0:
		cd = absi(int(unit.get("id", 0))) % MIND_DECAY_SLICES
	if cd == 0:
		unit["_mind_decay_cd"] = MIND_DECAY_SLICES - 1
		return true
	unit["_mind_decay_cd"] = cd - 1
	return false


## One budgeted mind tick. Returns true if the unit is busy (urge override,
## fleeing, or an ordered withdrawal) — the world should skip job/combat
## AI this tick.
func tick_unit(unit: Dictionary, delta: float) -> bool:
	if not unit.get("alive", false):
		return false
	ensure(unit)

	# Fleeing preempts everything.
	if bool(unit.get("fleeing", false)):
		_tick_flee(unit, delta)
		return true

	# Ordered withdrawal (SimArmy retreat): march to the rally point,
	# preempting combat and urges — a real retreat, not a fighting stand.
	if bool(unit.get("withdrawing", false)):
		if _tick_withdraw(unit, delta):
			return true

	# Flood flight (HydroSim): run to high ground, preempts urges/work.
	if bool(unit.get("flood_flee", false)):
		if _tick_flood_flee(unit, delta):
			return true

	# Urge decay; critical urges preempt work.
	var state: String = String(unit.get("mind_state", ""))
	if state.begins_with("satisfying:"):
		var urge: String = state.get_slice(":", 1)
		# Furniture matters now: a real bed / toilet / wash basin must be in
		# the building, or recovery is slow and caps low (see SimUrges).
		var furnished := _has_furniture_for(unit, urge)
		match urges.satisfy(unit, urge, delta, furnished):
			"done":
				unit["mind_state"] = ""
				_exit_building(unit)  # Milestone 7: leave once the urge is met
				_say(unit, _done_context(urge))
				return false
			"cant":
				unit["mind_state"] = ""  # impossible — work hungry, don't idle
				return false
			_:
				return true  # "busy" — keep satisfying
	# Background decay at 20Hz per unit (staggered); the critical-urge
	# check itself runs every slice so overrides stay instant.
	# NOTE: chatter stays per-slice — it emits speech events on a cooldown,
	# and staggering it would visibly delay chat lines (test_chatter_emits).
	var crit: String
	if _decay_due(unit):
		var d3: float = delta * MIND_DECAY_SLICES
		crit = urges.tick(unit, d3)
		# Normal tick: emotions and memories decay.
		# Jeremy 2026-10-04: moods — strong emotions harden into
		# persistent moods that decay far slower than emotions.
		emotion.tick(unit, d3)
		mood.feed_from_emotion(unit)
		mood.tick(unit, d3)
		memories.tick(unit)
	else:
		crit = urges.worst_critical(unit)
	unit["mind"]["critical_urge"] = crit
	if crit != "":
		# Milestone 7: NPCs walk into buildings to satisfy urges.
		# Sleep (energy) -> house; hunger -> house/tavern if one is near.
		if not _inside_for_urge(unit, crit):
			_try_enter_for_urge(unit, crit)
		unit["mind_state"] = "satisfying:" + crit
		_say(unit, _critical_context(crit))
		return true

	# Jeremy 2026-10-05: siege hiding (SimSiege) — civilians sheltering
	# from an attack skip work while the city is under attack. Critical
	# urges already ran above and can still pull them out.
	if bool(unit.get("_siege_hide", false)):
		return true

	# Jeremy 2026-10-04: food perk DoT/HoT (Food Poisoning, Meat Sweats).
	# Efficient: only units with perks pay this cost.
	if unit.has("food_perks"):
		_tick_food_perks(unit, delta)
	# Chatter is a cooldown event, not decay — it stays per-slice so chat
	# lines fire the moment the cooldown expires (never visibly delayed).
	_tick_chatter(unit, delta)
	return false


## Called when a unit takes non-lethal damage (wired from SimCombat).
## Records the grudge, sets the emotion, and may start a flee.
func on_attacked(victim: Dictionary, attacker: Dictionary, dmg: float,
		source_faction: String = "monster") -> void:
	if victim.is_empty() or not victim.get("alive", false):
		return
	ensure(victim)
	var aname := "a monster"
	var aid := -1
	var afac := source_faction
	if not attacker.is_empty():
		aname = SimPersonality.display_name(attacker)
		aid = int(attacker.get("id", -1))
		afac = String(attacker.get("faction", source_faction))
	memories.remember(victim, "hurt_by", aid, aname, afac)
	emotion.notify(victim, "attacked", clampf(dmg / 40.0, 0.5, 1.5))
	# Cowards flee; the brave get angry (handled by SimEmotion.notify).
	if not SimPersonality.stands_ground(victim):
		_start_flee(victim, attacker)
	_say(victim, "scared" if not SimPersonality.stands_ground(victim) else "angry")


## Called from the world's unit_died hook. Nearby friends grieve.
func on_unit_died(unit_id: int, faction: String) -> void:
	var dead: Dictionary = _gs.get_unit(unit_id)
	var dpos: Vector2 = dead.get("position", Vector2.ZERO) \
		if not dead.is_empty() else Vector2.ZERO
	var dname: String = SimPersonality.display_name(dead) \
		if not dead.is_empty() else "a friend"
	var fam: SimFamily = _gs.get("family") as SimFamily
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if int(u.get("id", 0)) == unit_id:
			continue
		if String(u.get("faction", "")) != faction:
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if upos.distance_to(dpos) > 600.0:
			continue
		ensure(u)
		# Jeremy 2026-10-05: grief is for actual friends (bond >=
		# FRIEND_SCORE) and spouses — not for every stranger in earshot.
		var grieves: bool = int(u.get("spouse_uid", -1)) == unit_id
		if not grieves and fam != null and not dead.is_empty():
			grieves = fam.get_affinity(u, dead) >= SimFamily.FRIEND_SCORE
		if grieves:
			emotion.notify(u, "friend_died")
			memories.remember(u, "friend_died", unit_id, dname, faction, 0.8)
		else:
			# A faction-mate died nearby: sobering, but not grief.
			var um: Dictionary = urges.ensure(u)
			um["mood"] = clampf(float(um.get("mood", 60.0)) - 4.0, 0.0, 100.0)


## Called when a unit is healed (wired from doctors / clinic aura).
func on_helped(patient: Dictionary, helper: Dictionary) -> void:
	if patient.is_empty():
		return
	ensure(patient)
	emotion.notify(patient, "helped")
	if not helper.is_empty():
		memories.remember(patient, "helped_by", int(helper.get("id", -1)),
			SimPersonality.display_name(helper),
			String(helper.get("faction", "")))


func _start_flee(unit: Dictionary, threat: Dictionary) -> void:
	unit["fleeing"] = true
	unit["flee_timer"] = FLEE_DURATION
	unit["threat_pos"] = threat.get("position", unit.get("position", Vector2.ZERO)) \
		if not threat.is_empty() else unit.get("position", Vector2.ZERO)


func _tick_flee(unit: Dictionary, delta: float) -> void:
	var timer: float = float(unit.get("flee_timer", 0.0)) - delta
	unit["flee_timer"] = timer
	if timer <= 0.0:
		unit["fleeing"] = false
		return
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var threat: Vector2 = unit.get("threat_pos", pos)
	var away: Vector2 = pos - threat
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	# Cliffs (HTML CLIFFDETECT): don't flee off a sheer cliff — slide
	# along the edge (x-only, then y-only) before giving up.
	# Jeremy 2026-10-05: fleeing units may swim (Oblivion/Skyrim rules).
	unit["position"] = Cliffs.try_step(_gs.map_data, pos,
		away.normalized() * FLEE_SPEED * delta)
	unit["swimming"] = WaterNav.is_water_at(_gs.map_data,
		unit["position"])


## Ordered withdrawal to a rally point (army retreat order). Marches there
## every mind tick, preempting combat and urge satisfaction. Returns true
## while still marching; clears the flag on arrival so normal AI resumes.
func _tick_withdraw(unit: Dictionary, delta: float) -> bool:
	var target: Vector2 = unit.get("withdraw_target", Vector2.INF)
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	if target == Vector2.INF or pos.distance_to(target) < 60.0:
		unit["withdrawing"] = false
		unit.erase("withdraw_target")
		return false
	var to: Vector2 = target - pos
	unit["position"] = Cliffs.try_step(_gs.map_data, pos,
		to.normalized() * FLEE_SPEED * delta)
	# Jeremy 2026-10-05: withdrawing troops may swim.
	unit["swimming"] = WaterNav.is_water_at(_gs.map_data,
		unit["position"])
	return true


## Flood flight: the HydroSim flagged this unit (flood_flee + flood_target).
## Runs to high ground; returns false when dry (flag cleared) so normal AI
## resumes. Uses Cliffs.try_step like combat fleeing — never off a sheer face.
func _tick_flood_flee(unit: Dictionary, delta: float) -> bool:
	var hydro = _gs.get("hydro")
	if hydro == null or not hydro.has_method("is_dry"):
		unit["flood_flee"] = false
		return false
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	if hydro.is_dry(pos):
		unit["flood_flee"] = false
		return false
	var target: Vector2 = unit.get("flood_target", Vector2(-1, -1))
	if target.x < 0.0 or pos.distance_to(target) < 48.0:
		target = hydro.nearest_dry(pos)
		unit["flood_target"] = target
	var to: Vector2 = target - pos
	if to.length_squared() > 1.0:
		unit["position"] = Cliffs.try_step(_gs.map_data, pos,
			to.normalized() * FLEE_SPEED * delta)
		# Jeremy 2026-10-05: flood-fleeing units may swim.
		unit["swimming"] = WaterNav.is_water_at(_gs.map_data,
			unit["position"])
	return true


func _tick_chatter(unit: Dictionary, delta: float) -> void:
	var cd: float = float(unit.get("chatter_cd", 0.0)) - delta
	if cd > 0.0:
		unit["chatter_cd"] = cd
		return
	unit["chatter_cd"] = SimPersonality.chatter_interval(unit)
	_say(unit, "chatter")


## Food perk damage-over-time and heal-over-time. Only runs for units
## that have perks (caller guards with unit.has("food_perks")).
func _tick_food_perks(unit: Dictionary, delta: float) -> void:
	var gt: float = _gs.game_time
	var poison: float = SimFoodPerks.get_poison_dps(unit, gt)
	if poison > 0.0:
		var hp: float = float(unit.get("hp", 100.0))
		unit["hp"] = maxf(0.0, hp - poison * delta)
		if float(unit.get("hp", 0.0)) <= 0.0 and bool(unit.get("alive", false)):
			unit["alive"] = false
			unit["death_cause"] = "food poisoning"
	var heal: float = SimFoodPerks.get_heal_per_sec(unit, gt)
	if heal > 0.0 and bool(unit.get("alive", true)):
		var max_hp: float = float(unit.get("max_hp", 100.0)) \
			* SimFoodPerks.get_max_hp_mult(unit, gt)
		unit["hp"] = minf(max_hp, float(unit.get("hp", 100.0)) + heal * delta)


func _say(unit: Dictionary, context: String) -> void:
	var line: String = SimDialogue.line_for(_gs, unit, context)
	if line != "":
		_gs.bus.unit_said.emit(int(unit.get("id", 0)), line)


func _critical_context(urge: String) -> String:
	match urge:
		"hunger":
			return "hungry"
		"energy":
			return "tired"
		"bladder":
			return "scared"  # desperate dash — reuse the panic table
	return "chatter"


func _done_context(urge: String) -> String:
	match urge:
		"hunger":
			return "eating"
		"energy", "mood":
			return "happy"
	return "chatter"


# ------------------------------------------------------- Milestone 7: interiors

## Building types that can satisfy each urge (mirrors SimInteriors vocabulary).
const URGE_BUILDINGS := {
	"energy": ["house", "town_hall", "barracks"],
	"hunger": ["house", "town_hall", "restaurant", "farm",
		"greasy_spoon", "salad_bar",
		"ogre_sausage_shop", "meat_tornado",
		"moonberry_lounge", "dewdrop_diner",
		"bastard_drivethru", "fungus_hut",
		"crypt_kitchen", "grave_snacks"],
	"hygiene": ["house", "town_hall"],
	"social": ["restaurant", "town_hall", "house",
		"greasy_spoon", "salad_bar",
		"ogre_sausage_shop", "meat_tornado",
		"moonberry_lounge", "dewdrop_diner",
		"bastard_drivethru", "fungus_hut",
		"crypt_kitchen", "grave_snacks"],
	"mood": ["restaurant", "town_hall", "house",
		"greasy_spoon", "salad_bar",
		"ogre_sausage_shop", "meat_tornado",
		"moonberry_lounge", "dewdrop_diner",
		"bastard_drivethru", "fungus_hut",
		"crypt_kitchen", "grave_snacks"],
}

## Furniture "need" tag (SimInteriors floor plans) required per urge.
## Jeremy 2026-10-04: beds and bathrooms are functional now, not decorative.
const URGE_FURNITURE := {
	"energy": "sleep",
	"bladder": "bladder",
	"hygiene": "wash",
}


## Passive mind tick for the adventure hero and quest NPCs: urges decay and
## auto-satisfy (eat from stores, relieve, rest when idle) WITHOUT movement
## overrides, building entry, or fleeing. Returns the worst critical urge
## AFTER auto-satisfaction ("" when all clear) so the caller can apply soft
## effects (debuffs, complaints) while the player keeps full control.
func tick_passive(unit: Dictionary, delta: float, idle: bool) -> String:
	if not unit.get("alive", false):
		return ""
	ensure(unit)
	urges.tick(unit, delta)  # decay
	# Auto-satisfy without hijacking the unit.
	if urges.value(unit, "hunger") < float(SimUrges.CRITICAL["hunger"]):
		urges.satisfy(unit, "hunger", delta)  # eats from stores if able
	if urges.value(unit, "bladder") < float(SimUrges.CRITICAL["bladder"]):
		urges.satisfy(unit, "bladder", delta)  # instant relief
	if idle and urges.value(unit, "energy") < SimUrges.SLEEP_DONE:
		# Rest at the 8-in-game-hours bed rate — the hero catches sleep
		# where they can; no bed required out in the field.
		urges.satisfy(unit, "energy", delta, true)
	var crit: String = urges.worst_critical(unit)
	unit["mind"]["critical_urge"] = crit
	emotion.tick(unit, delta)
	memories.tick(unit)
	return crit


## True when the unit's current building has the furniture this urge needs
## (a real bed for sleep, a toilet for bladder, a sink/tub for hygiene).
## No interior system (tests/headless) counts as furnished — the old
## satisfy-in-place behavior.
func _has_furniture_for(unit: Dictionary, urge: String) -> bool:
	var need: String = String(URGE_FURNITURE.get(urge, ""))
	if need == "" or interiors == null:
		return true
	var bid: int = int(unit.get("inside_building_id", 0))
	if bid <= 0:
		return false
	for b in _gs.buildings:
		if int(b.get("id", 0)) == bid:
			return not interiors.find_for_need(b, need).is_empty()
	return false


## True when the unit is already inside a building that serves this urge.
func _inside_for_urge(unit: Dictionary, urge: String) -> bool:
	if interiors == null:
		return true  # no interior system — satisfy in place
	var bid: int = int(unit.get("inside_building_id", 0))
	if bid <= 0:
		return false
	var b: Dictionary = {}
	for bb in _gs.buildings:
		if int(bb.get("id", 0)) == bid:
			b = bb
			break
	if b.is_empty():
		return false
	var want: Array = URGE_BUILDINGS.get(urge, [])
	return want.has(String(b.get("type", "")))


## Walk the unit into the nearest suitable building for this urge.
## Prefers a building that actually HAS the furniture (a real bed, a toilet,
## a wash basin) -- otherwise the unit makes do (floor-sleep / bush / bird-
## bath: slow recovery, low caps -- see SimUrges).
func _try_enter_for_urge(unit: Dictionary, urge: String) -> void:
	if interiors == null:
		return
	if int(unit.get("inside_building_id", 0)) > 0:
		return  # already inside somewhere
	var want: Array = URGE_BUILDINGS.get(urge, [])
	if want.is_empty():
		return
	var need: String = String(URGE_FURNITURE.get(urge, ""))
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	# Pass 0: nearest building WITH the furniture. Pass 1: nearest suitable
	# building at all (the rough fallback).
	for pass_n: int in range(2):
		var best: Dictionary = {}
		var best_d := 900.0  # only bother with nearby buildings
		for b in _gs.buildings:
			if not b.get("alive", true):
				continue
			if String(b.get("faction", "")) != String(unit.get("faction", "")):
				continue
			if not want.has(String(b.get("type", ""))):
				continue
			if not interiors.can_enter(b):
				continue
			if pass_n == 0 and need != "" \
					and interiors.find_for_need(b, need).is_empty():
				continue
			var d: float = pos.distance_to(b.get("position", Vector2.ZERO))
			if d < best_d:
				best_d = d
				best = b
		if not best.is_empty():
			interiors.enter(best, unit)
			return


## Leave the current building (called when an urge is satisfied).
func _exit_building(unit: Dictionary) -> void:
	if interiors == null:
		return
	if int(unit.get("inside_building_id", 0)) > 0:
		interiors.exit(unit)
