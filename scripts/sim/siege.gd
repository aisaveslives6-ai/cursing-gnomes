class_name SimSiege
extends RefCounted

## Cursing Gnomes — civilian siege response (Jeremy 2026-10-05, AI-first phase).
##
## Port of the HTML build's Siege Doctrine civilian half (fix79, lines
## 12165-12360): civilianDefenseTick + defenseRepairTarget +
## nearestHostileUnit. The military half (musterMilitaryDefense) already
## lives in SimAIDirector._muster_defense; the threat model (townThreatLevel:
## 0 = calm, 1 = hostile force approaching, 2 = town under attack) is
## SimAIDirector._threat_level, extended to the HTML's cityUnderAttack /
## cityThreatened scans.
##
## What it does, every 1 s, for each faction at threat level 2 (city under
## attack — the HTML-verbatim gate):
##   - Civilians (non-military, non-leader, no player order) react:
##       - 35% of workers are BRAVE: they drop their tools and repair the
##         walls instead of hiding (damaged walls first, then the
##         most-damaged building — HTML defenseRepairTarget scoring, with
##         the HTML 2 s retarget throttle). Repairs run through the normal
##         WorkerAI to_repair/repairing state machine, so any job can do
##         emergency repairs, not just builders.
##       - Everyone else HIDES: home > hall > nearest intact non-wall
##         building (interiors.enter, the same call the urge system uses).
##         No shelter left = flee from the nearest hostile via the mind's
##         flee system. Hiding adds +25 stress (HTML-verbatim).
##     Both paths get the HTML's per-race war cries ("Fucking hide!",
##     "Walls first, ya cowards!" — the charm stays).
##   - Threat over: stand down — flags clear, hiders we put inside leave
##     the building, 30% get an "all clear" line.
##
## Skips (HTML-verbatim): the dead and downed, player heroes/orders,
## faction leaders, commanders/chieftains/warlords, military units.
## Deliberate deviations from the HTML (documented, not redesigned):
##   - HTML walks hiders to the shelter door (needAction 'hide'); Godot
##     enters directly like SimMind._try_enter_for_urge — no door-walk
##     state machine exists in this engine.
##   - HTML's no-shelter flee is a 320px moveTarget; Godot uses the mind
##     flee (6 s at FLEE_SPEED away from the threat) — the engine idiom.
##   - Units mid-urge (mind_state "satisfying:") are never yanked — the
##     urge system owns them; they hide on the next tick after it ends.
##   - Fleeing / withdrawing / flood-fleeing / disaster-hunting units are
##     skipped until their current flight or mission ends (the HTML has no
##     equivalents; yanking them would fight the owning system).
##
## Cross-system notes: hiders return true from SimMind.tick_unit (work
## skipped); WorkerAI._pick_task refuses _siege_hide/_siege_repair units so
## neither the director's workforce push nor normal tasking steals them
## (the push only drafts idle/gather workers anyway).
##
## Pure logic — no rendering, no input, no audio. Owned by World
## (game.siege); tests construct SimSiege.new(gs, combat, interiors).
##
## UNIT FIELDS read/written: _siege_hide, _siege_repair, _siege_ret_t,
## siege_shelter_id, work_state/work_building/work_target_pos (repairs),
## inside_building_id (via interiors), fleeing/flee_timer/threat_pos,
## stress (all pre-existing unit-record fields).

const TICK_INTERVAL := 1.0        # civilian resolve doesn't need 60 Hz
const REPAIR_SCAN_R := 1400.0     # HTML defenseRepairTarget scan radius
const WALL_HP_SKIP := 0.98        # HTML: walls at >=98% hp need no work
const BRAVE_CHANCE := 0.35        # HTML: 35% of workers are brave
const STRESS_HIT := 25.0          # HTML: hiding adds 25 stress
const RETARGET_CD := 2.0          # HTML _defRetT: retarget at most every 2 s

var _gs  # GameState (untyped: avoids a core<->sim class cycle).
var _combat  # SimCombat — can_fight() hostility semantics.
var _interiors  # SimInteriors — enter()/exit() for hiding.
var _accum := 0.0


func _init(game_state, combat_sim, interiors_sim) -> void:
	_gs = game_state
	_combat = combat_sim
	_interiors = interiors_sim


## World calls this every frame; the real work runs at 1 Hz.
func tick(delta: float) -> void:
	_accum += delta
	if _accum < TICK_INTERVAL:
		return
	_accum = 0.0
	_tick_siege()


func _tick_siege() -> void:
	if _gs.units.is_empty():
		return
	var ad = _gs.get("ai_director")
	if ad == null:
		return
	for faction: String in _gs.active_factions:
		var threat := int(ad.threat_level_of(faction))
		for u: Dictionary in _gs.units:
			if String(u.get("faction", "")) != faction:
				continue
			if threat >= 2:
				_civilian_defense(u)
			elif bool(u.get("_siege_hide", false)) \
					or bool(u.get("_siege_repair", false)):
				_stand_down(u)


## HTML civilianDefenseTick verbatim, adapted to Godot unit records.
func _civilian_defense(u: Dictionary) -> void:
	if not bool(u.get("alive", false)):
		return
	if bool(u.get("downed", false)):
		return
	if not (u.get("player_order", {}) as Dictionary).is_empty():
		return  # explicit player orders always win (HTML playerOrder skip)
	if bool(u.get("is_leader", false)):
		return
	var job: String = String(u.get("job", "worker"))
	if JobDefs.is_military(job):
		return  # military leads, not hides (HTML isMilitaryNpc skip)
	if job in ["commander", "chieftain", "warlord"]:
		return  # HTML: commanders/chieftains/warlords lead, not hide
	if bool(u.get("fleeing", false)) or bool(u.get("flood_flee", false)):
		return  # a flight in progress owns them
	if bool(u.get("withdrawing", false)):
		return  # SimArmy retreat march preempts
	if int(u.get("disaster_hunt_id", -1)) >= 0:
		return  # hunters are on a mission
	if String(u.get("mind_state", "")).begins_with("satisfying:"):
		return  # urge in progress — the urge system owns them

	# Shelter destroyed mid-flight — drop the role and seek a new one.
	if bool(u.get("_siege_hide", false)) \
			and int(u.get("inside_building_id", 0)) <= 0:
		u["_siege_hide"] = false
		u.erase("siege_shelter_id")
	if bool(u.get("_siege_hide", false)):
		# Still sheltered (or the shelter fell — re-check below).
		if _shelter_intact(u):
			return
		_interiors.exit(u)
		u["_siege_hide"] = false
		u.erase("siege_shelter_id")
	if bool(u.get("_siege_repair", false)):
		_defense_repair_target(u)
		return

	# Choose a role: brave workers repair the walls, the rest hide.
	var brave := job == "worker" and randf() < BRAVE_CHANCE
	if brave:
		u["_siege_repair"] = true
		u["work_state"] = "idle"  # drop current task; retarget below
		u.erase("work_site")
		u.erase("social_partner")
		if randf() < 0.6:
			_say(u, _brave_line(String(u.get("faction", ""))))
		_defense_repair_target(u)
		return

	u["_siege_hide"] = true
	u["work_state"] = "idle"
	u.erase("work_site")
	u.erase("social_partner")
	var shelter := _shelter_for(u)
	if not shelter.is_empty() and _interiors.enter(shelter, u):
		u["siege_shelter_id"] = int(shelter.get("id", 0))
	else:
		# No shelter left — run away from the fighting.
		u["_siege_hide"] = false
		var foe := _nearest_hostile(u, 700.0)
		if not foe.is_empty():
			u["fleeing"] = true
			u["flee_timer"] = SimMind.FLEE_DURATION
			u["threat_pos"] = foe.get("position", Vector2.ZERO)
	u["stress"] = minf(100.0, float(u.get("stress", 0.0)) + STRESS_HIT)
	if randf() < 0.45:
		_say(u, _hide_line(String(u.get("faction", ""))))


## Threat over — stand down, come out of hiding (HTML-verbatim).
func _stand_down(u: Dictionary) -> void:
	u["_siege_hide"] = false
	u["_siege_repair"] = false
	u["_siege_ret_t"] = 0.0
	var sid := int(u.get("siege_shelter_id", 0))
	if sid > 0:
		# Only usher out units WE put inside; urge-sleepers keep their bed.
		if int(u.get("inside_building_id", 0)) == sid:
			_interiors.exit(u)
		u.erase("siege_shelter_id")
	# Their repair work_state (if any) finishes naturally through WorkerAI.
	if randf() < 0.3:
		_say(u, _clear_line(String(u.get("faction", ""))))


## True when the unit's siege shelter still stands and holds them.
func _shelter_intact(u: Dictionary) -> bool:
	var bid := int(u.get("inside_building_id", 0))
	if bid <= 0:
		return false
	var b := _building_by_id(bid)
	return not b.is_empty() and bool(b.get("alive", false))


## HTML shelter preference: own home > own hall > nearest intact
## non-wall building of the faction. Already-indoor units keep their roof.
func _shelter_for(u: Dictionary) -> Dictionary:
	var faction: String = String(u.get("faction", ""))
	if int(u.get("inside_building_id", 0)) > 0:
		# Already under a roof — sheltering in place.
		return _building_by_id(int(u.get("inside_building_id", 0)))
	var home: Dictionary = u.get("home", {})
	if not home.is_empty() and bool(home.get("alive", false)) \
			and SimInteriors.can_enter(home):
		return home
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in ["hall", "town_hall"] \
				and SimInteriors.can_enter(b):
			return b
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best := {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) == "wall":
			continue
		if not SimInteriors.can_enter(b):
			continue
		var d: float = upos.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	return best


## HTML defenseRepairTarget verbatim: damaged WALLS preempt any non-wall
## repair job; otherwise keep the current job, or take the most-damaged
## building (retarget at most every 2 s so crews don't thrash).
func _defense_repair_target(u: Dictionary) -> void:
	var faction: String = String(u.get("faction", ""))
	var now := Time.get_ticks_msec() / 1000.0
	var cur := _building_by_id(int(u.get("work_building", -1)))
	var cur_damaged := not cur.is_empty() and bool(cur.get("alive", false)) \
		and bool(cur.get("complete", false)) \
		and float(cur.get("hp", 1.0)) < float(cur.get("max_hp", 1.0))
	var cur_is_wall := cur_damaged and String(cur.get("type", "")) == "wall"
	var wall := _best_damaged(u, faction, true)
	if not wall.is_empty() and not cur_is_wall:
		_order_repair(u, wall)
		u["_siege_ret_t"] = now
		return
	if cur_damaged:
		return  # keep current job when no wall needs work
	if float(u.get("_siege_ret_t", 0.0)) + RETARGET_CD > now:
		return
	u["_siege_ret_t"] = now
	var best := _best_damaged(u, faction, false)
	if not best.is_empty():
		_order_repair(u, best)


## Best damaged building for a brave repairer. Walls-only pass first
## (score = distance * damage fraction); the general pass weights walls
## 0.2x (HTML-verbatim scoring). Skips buildings at >=98% hp.
func _best_damaged(u: Dictionary, faction: String,
		walls_only: bool) -> Dictionary:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best := {}
	var best_score := INF
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var btype: String = String(b.get("type", ""))
		if walls_only and btype != "wall":
			continue
		var hp: float = float(b.get("hp", 1.0))
		var max_hp: float = float(b.get("max_hp", 1.0))
		if hp >= max_hp * WALL_HP_SKIP:
			continue
		var d: float = upos.distance_to(b.get("position", Vector2.ZERO))
		if d > REPAIR_SCAN_R:
			continue
		var score := d * (0.2 if btype == "wall" else 1.0) * (hp / max_hp)
		if score < best_score:
			best_score = score
			best = b
	return best


func _order_repair(u: Dictionary, b: Dictionary) -> void:
	u["work_building"] = int(b.get("id", 0))
	u["work_target_pos"] = b.get("position", Vector2.ZERO)
	u["work_state"] = "to_repair"  # WorkerAI walks there, then repairs
	u.erase("work_site")  # HTML: gatherTarget = null


## HTML nearestHostileUnit verbatim: nearest hostile unit/monster to u
## within max_r (used for the no-shelter flee direction). Children are
## never hostile targets (CANDIDATE26-P10b).
func _nearest_hostile(u: Dictionary, max_r: float) -> Dictionary:
	var faction: String = String(u.get("faction", ""))
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best := {}
	var best_d2 := max_r * max_r
	for e: Dictionary in _gs.units:
		if not bool(e.get("alive", false)):
			continue
		if bool(e.get("downed", false)):
			continue
		if bool(e.get("is_child", false)):
			continue
		var ef: String = String(e.get("faction", ""))
		if ef == faction:
			continue
		if not _combat.can_fight(faction, ef):
			continue
		var d2: float = upos.distance_squared_to(
			e.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = e
	return best


func _building_by_id(bid: int) -> Dictionary:
	# Jeremy 2026-10-05 perf: shared O(1) id index on GameState.
	if bid <= 0:
		return {}
	return _gs.get_building(bid)


func _say(u: Dictionary, line: String) -> void:
	if line == "":
		return
	_gs.bus.unit_said.emit(int(u.get("id", 0)), line)


## HTML-verbatim per-race war cries (unitBubble lines).
func _hide_line(faction: String) -> String:
	match faction:
		"gnomes":
			return "Fucking hide!"
		"ogres":
			return "Hide! Scary!"
		"elves":
			return "To shelter — swiftly!"
	return "Take cover!"


func _brave_line(faction: String) -> String:
	match faction:
		"gnomes":
			return "Walls first, ya cowards!"
		"ogres":
			return "Me fix wall! You hide!"
		"elves":
			return "The walls must hold — to work!"
	return "To the walls! Hold them!"


func _clear_line(faction: String) -> String:
	match faction:
		"gnomes":
			return "All clear. Back to work."
		"ogres":
			return "Safe now."
	return "The danger passes."
