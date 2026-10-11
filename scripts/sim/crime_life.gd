class_name SimCrimeLife
extends RefCounted
## Cursing Gnomes — real-time crime behavior layer (Jeremy 2026-10-04).
##
## The VISIBLE half of the justice system. SimCrime (crime.gd) owns the
## math — trait scans, sentences, fines, verdict scoring. This file owns
## the behavior the player actually watches:
##
##   criminal trait  -> sneak mode, stalk a victim, steal what they need
##   tool need       -> won't buy it: pickpockets it off someone disliked
##   seen doing it   -> witness runs to a guard / guard spots them directly
##   wanted          -> nearest guard hunts the suspect down
##   caught          -> violent criminals fight; guards use lethal force
##   arrested        -> escorted to a jail cell (pretrial detention)
##   trial day       -> live courtroom scene: judge, jury, witnesses, verdict
##   guilty          -> back to jail for the sentence (up to 7 days)
##
## HTML cross-reference (fix79): planCrime55/commitCrime55 (stalk with
## _sneak55, victim approach, flee), guardTick55 (scene -> seek -> hunt ->
## escort), witnessTick55 (run to guard, report), startTrial55/castTrial55/
## trialTick55 (phases + dialogue) /endTrial55 (evidence >= 5 guilty),
## jailFor55/jailSuspect55 (guard_house cells, held until trial).
##
## State lives on unit records (save-friendly primitives) and on SimCrime's
## c55 records (trial dicts). Pure logic — no rendering. Visual hooks:
##   unit["sneaking"]  -> UnitNode.set_sneaking (crouch + darken)
##   unit["crime_fx"]  -> one-shot fx key consumed by the world sync
##                       ("struggle" = dust + flash, "gavel" = verdict flash)
##   unit_said bus     -> speech bubbles for the trial + barks
##   Gazette stories   -> arrests, trials, verdicts (via SimCrime.publish)
##
## Pure logic — no rendering, no input, no audio, no network.


## Crime phases on unit["crime_phase"].
const PHASE_STALK := "stalk"          # sneaking toward the victim
const PHASE_FLEE := "flee"            # sneaking away after the steal
const PHASE_WITNESS := "witness"      # running to report a crime
const PHASE_HUNTED := "hunted"        # suspect fleeing an assigned guard
const PHASE_RESIST := "resist"        # fighting the guard
const PHASE_ESCORT := "escort"        # suspect being walked to jail
const PHASE_JAILED := "jailed"        # in a cell
const PHASE_TRIAL := "trial"          # seated in the courtroom cast
const PHASE_GUARD_HUNT := "guard_hunt"      # guard pursuing a suspect
const PHASE_GUARD_ESCORT := "guard_escort"  # guard walking suspect to jail
const PHASE_GUARD_LETHAL := "guard_lethal"  # guard attacking a resister

## Planning: per-second chance a criminal starts a crime (HTML chance(dt*0.02)).
const PLAN_RATE := 0.02
## Sneaking shrinks the detection radius hard (HTML _sneak55 parity).
const SNEAK_DETECT_MUL := 0.25
const DETECT_RADIUS := 260.0
const STEAL_DIST := 46.0
const CATCH_DIST := 44.0
const ESCAPE_DIST := 600.0
## Stalk gives up after 90 s (HTML: lost nerve).
const STALK_TIMEOUT := 90.0
## Flee phase: 20 s of sneaking away, then clean (HTML ~25 s).
const FLEE_TIME := 20.0
## Cells per jail building.
const JAIL_CELLS := 6

## Job -> tool it needs. A criminal who lacks their tool steals one instead
## of buying it (Jeremy 2026-10-04) — preferably off someone they dislike.
const JOB_TOOLS := {
	"woodcutter": "axe",
	"miner": "pickaxe",
	"farmer": "hoe",
	"builder": "hammer",
	"fisher": "fishing_rod",
	"smith": "hammer",
	"repairman": "wrench",
}

## Trial phases and their stage time in seconds (HTML trialTick55 PHASES).
const TRIAL_PHASES := {
	"convene": 9.0, "opening": 11.0, "testimony": 15.0, "cross": 11.0,
	"closing": 11.0, "deliberate": 9.0, "verdict": 7.0,
}
const TRIAL_ORDER: Array[String] = ["convene", "opening", "testimony",
	"cross", "closing", "deliberate", "verdict"]


var _gs: GameState
var _crime  # SimCrime — duck-typed to avoid a cyclic class reference
var _mem: SimMemories


func _init(game_state: GameState, crime) -> void:
	_gs = game_state
	_crime = crime
	_mem = SimMemories.new(game_state)


## True when the unit is inside the justice pipeline (their AI slice belongs
## to this system, not to mind/work/combat).
func has_crime_state(unit: Dictionary) -> bool:
	return String(unit.get("crime_phase", "")) != ""


## One budgeted tick. Returns true when the crime system consumed the unit's
## AI slice (active phase, or a crime was just planned).
func tick_unit(unit: Dictionary, delta: float) -> bool:
	if not unit.get("alive", false):
		return false
	var phase: String = String(unit.get("crime_phase", ""))
	if phase == "":
		# Jeremy 2026-10-05: safety net - a unit with no crime phase must
		# never stay sneaking (was getting stuck squished+muted).
		if bool(unit.get("sneaking", false)):
			unit["sneaking"] = false
		return _maybe_plan(unit, delta)
	match phase:
		PHASE_STALK:
			_tick_stalk(unit, delta)
		PHASE_FLEE:
			_tick_flee(unit, delta)
		PHASE_WITNESS:
			_tick_witness(unit, delta)
		PHASE_HUNTED:
			_tick_hunted(unit, delta)
		PHASE_RESIST:
			_tick_resist(unit, delta)
		PHASE_ESCORT:
			_tick_escort(unit, delta)
		PHASE_JAILED:
			_tick_jailed(unit, delta)
		PHASE_TRIAL:
			_tick_trial_cast(unit, delta)
		PHASE_GUARD_HUNT:
			_tick_guard_hunt(unit, delta)
		PHASE_GUARD_ESCORT:
			_tick_guard_escort(unit, delta)
		PHASE_GUARD_LETHAL:
			_tick_guard_lethal(unit, delta)
		_:
			unit["crime_phase"] = ""
			return false
	return true


## Global per-frame tick: guard dispatch, jail releases, live trials.
## Perf R17 (2026-10-05): stagger counter for tick_global — the global
## justice tick ran three full unit scans every frame (0.68ms/f, the #1 sim
## hotspot post-R15, probe-verified). Guard dispatch, jail release, and
## trial pacing don't need 60Hz. Ephemeral: no save/load needed.
var _global_frame := 0


func tick_global(delta: float) -> void:
	# Perf R17: run the global justice tick every 3rd frame (20Hz) instead
	# of every frame. A 50ms guard-dispatch delay is imperceptible; the
	# handled/wanted sets are rebuilt fresh each dispatch so no assignment
	# is lost or doubled. Trial phase timing stays identical via delta*3
	# (same pattern as the 20Hz medic stagger).
	_global_frame += 1
	if _global_frame < 3:
		return
	_global_frame = 0
	_dispatch_guards()
	_release_jailed()
	_tick_live_trial(delta * 3.0)


# ------------------------------------------------------------- crime planning

## Idle criminals may start a crime (HTML planCrime55, real-time gate).
func _maybe_plan(unit: Dictionary, delta: float) -> bool:
	if String(unit.get("faction", "")) != _gs.player_faction:
		return false  # the visible sim runs in the player's towns (HTML)
	if _is_guard(unit):
		return false
	if float(unit.get("crime_cd", 0.0)) > _gs.game_time:
		return false
	if String(unit.get("job", "")) == "judge":
		return false
	_ensure_tools(unit)
	var rec: Dictionary = _crime.ensure_rec(unit)
	var criminal: bool = SimPersonality.is_criminal_minded(unit) \
		or bool(rec.get("criminal", false))
	if not criminal:
		return false
	if randf() > delta * PLAN_RATE:
		return false
	return _plan_crime(unit, rec)


## Picks the crime and the victim, enters sneak mode, starts the stalk.
func _plan_crime(unit: Dictionary, _rec: Dictionary) -> bool:
	var tool: String = _missing_tool(unit)
	var kind: String = ""
	var victim: Dictionary = {}
	if tool != "":
		# Jeremy: needs a tool -> won't buy it -> lifts it off someone
		# they don't like.
		victim = _pick_tool_victim(unit, tool)
		if victim.is_empty():
			unit["crime_cd"] = _gs.game_time + 120.0
			return false
		kind = "tool_theft"
	else:
		kind = _crime.motivation_for(unit)
		if kind == "":
			# No pressing need: most criminals walk away (HTML planCrime57
			# gate); the worst still cause motiveless mischief sometimes.
			if randf() < 0.25:
				kind = "pickpocket"
			else:
				unit["crime_cd"] = _gs.game_time + 180.0
				return false
		victim = _pick_victim(unit)
		if victim.is_empty():
			unit["crime_cd"] = _gs.game_time + 120.0
			return false
	unit["crime_phase"] = PHASE_STALK
	unit["crime_kind"] = kind
	unit["crime_tool"] = tool
	unit["crime_target"] = int(victim.get("id", 0))
	unit["crime_t"] = 0.0
	unit["sneaking"] = true
	return true


## What tool this unit's job needs that they don't carry, else "".
func _missing_tool(unit: Dictionary) -> String:
	var need: String = String(JOB_TOOLS.get(String(unit.get("job", "")), ""))
	if need == "":
		return ""
	var tools: Array = unit.get("tools", [])
	if need in tools:
		return ""
	return need


## Civilians usually own their job's tool (deterministic per unit id).
## Called lazily so the common case costs one dictionary lookup.
func _ensure_tools(unit: Dictionary) -> void:
	if unit.has("tools"):
		return
	var tools: Array = []
	var need: String = String(JOB_TOOLS.get(String(unit.get("job", "")), ""))
	if need != "":
		var rng := RandomNumberGenerator.new()
		rng.seed = int(unit.get("id", 0)) * 331 + 7
		if rng.randf() < 0.65:
			tools.append(need)
	unit["tools"] = tools


## Victim for a tool theft: someone carrying it, preferably disliked
## (negative relationship score from memories).
func _pick_tool_victim(crook: Dictionary, tool: String) -> Dictionary:
	var cands: Array = []
	var disliked: Array = []
	var cid: int = int(crook.get("id", 0))
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if int(u.get("id", 0)) == cid:
			continue
		if String(u.get("faction", "")) != String(crook.get("faction", "")):
			continue
		if String(u.get("crime_phase", "")) == PHASE_JAILED:
			continue
		if _is_guard(u):
			continue
		_ensure_tools(u)
		if not tool in (u.get("tools", []) as Array):
			continue
		cands.append(u)
		if _mem.relationship(crook, int(u.get("id", 0))) < -0.2:
			disliked.append(u)
	if not disliked.is_empty():
		return disliked[randi() % disliked.size()]
	if not cands.is_empty():
		return cands[randi() % cands.size()]
	return {}


## Victim for coin crimes: random same-faction, same-town adult civilian.
## Victim for coin crimes: HTML pickVictim55 — criminals rob NPCs they
## dislike (lowest bondsScore, must be below VICTIM_DISLIKE), never at
## random. Only the truly shady (criminal trait > 0.93) rob strangers, and
## only sometimes.
func _pick_victim(crook: Dictionary) -> Dictionary:
	var fam: SimFamily = _gs.get("family") as SimFamily
	var cid: int = int(crook.get("id", 0))
	var town_id: int = int(crook.get("town_id", -1))
	var cpos: Vector2 = crook.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_score := SimFamily.VICTIM_DISLIKE
	var fallback: Dictionary = {}
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if int(u.get("id", 0)) == cid:
			continue
		if String(u.get("faction", "")) != String(crook.get("faction", "")):
			continue
		if town_id >= 0 and int(u.get("town_id", -1)) != town_id:
			continue
		if String(u.get("crime_phase", "")) == PHASE_JAILED:
			continue
		if bool(u.get("is_child", false)):
			continue
		if _is_guard(u):
			continue
		var d: float = cpos.distance_to(u.get("position", Vector2.ZERO))
		if d > 700.0:
			continue
		if fam != null:
			var s: float = fam.bonds_score(crook, u)
			if s < best_score:
				best_score = s
				best = u
		if fallback.is_empty() and d <= 500.0:
			fallback = u
	if not best.is_empty():
		return best
	# Only the truly shady rob strangers (HTML pickVictim55).
	if SimPersonality.trait_of(crook, "criminal") > 0.93 \
			and not fallback.is_empty() and randf() < 0.3:
		return fallback
	return {}


# ------------------------------------------------------------------- stalking

func _tick_stalk(unit: Dictionary, delta: float) -> void:
	var t: float = float(unit.get("crime_t", 0.0)) + delta
	unit["crime_t"] = t
	var victim: Dictionary = _gs.get_unit(int(unit.get("crime_target", -1)))
	if victim.is_empty() or not victim.get("alive", false):
		_clear_crime(unit)
		return
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var dist: float = upos.distance_to(victim.get("position", Vector2.ZERO))
	if dist < STEAL_DIST:
		_commit_steal(unit, victim)
		return
	if t > STALK_TIMEOUT:
		# Lost nerve (HTML crimeLifeTick55).
		_clear_crime(unit)
		unit["crime_cd"] = _gs.game_time + 120.0
		return
	# Sneaking: slow, quiet approach.
	_move(unit, victim.get("position", Vector2.ZERO), delta, 0.6)
	_detection_tick(unit, delta)


## Who saw the sneak? Distance + sneak + night + perception (HTML C58:
## witnessed-only justice — nothing here is omniscient).
func _detection_tick(crook: Dictionary, delta: float) -> void:
	var upos: Vector2 = crook.get("position", Vector2.ZERO)
	var sneak_mul: float = SNEAK_DETECT_MUL \
		if bool(crook.get("sneaking", false)) else 1.0
	var night_mul: float = 0.6 if _gs.is_night else 1.0
	var cf: String = String(crook.get("faction", ""))
	var cid: int = int(crook.get("id", 0))
	var target_id: int = int(crook.get("crime_target", -1))
	for o: Dictionary in _gs.units:
		if not o.get("alive", false):
			continue
		var oid: int = int(o.get("id", 0))
		if oid == cid:
			continue
		if String(o.get("faction", "")) != cf:
			continue
		var ophase: String = String(o.get("crime_phase", ""))
		if ophase == PHASE_JAILED or ophase == PHASE_TRIAL:
			continue
		var d: float = upos.distance_to(o.get("position", Vector2.ZERO))
		if d > DETECT_RADIUS:
			continue
		var perception: float = 0.5 + SimPersonality.trait_of(o, "diligent")
		var p: float = delta * 0.9 * (1.0 - d / DETECT_RADIUS) \
			* sneak_mul * night_mul * perception
		if oid == target_id:
			p *= 1.6  # the mark is watching their own pockets
		if _is_guard(o):
			p *= 1.4
		if randf() < p:
			_on_detected(crook, o)
			return


func _on_detected(crook: Dictionary, observer: Dictionary) -> void:
	if _is_guard(observer) and String(observer.get("crime_phase", "")) == "":
		_say(observer, "Hey! You there — stop right now!")
		_assign_hunt(observer, crook)
		return
	if String(observer.get("crime_phase", "")) != "":
		return  # busy already
	_say(observer, "Thief! Somebody stop them!")
	observer["crime_phase"] = PHASE_WITNESS
	observer["crime_target"] = int(crook.get("id", 0))
	observer["crime_kind"] = String(crook.get("crime_kind", "theft"))
	observer["crime_t"] = 0.0


## The steal itself: lift coins or the needed tool, then sneak away.
## A final close-range spot check decides whether the victim saw WHO.
func _commit_steal(crook: Dictionary, victim: Dictionary) -> void:
	var kind: String = String(crook.get("crime_kind", "pickpocket"))
	var tool: String = String(crook.get("crime_tool", ""))
	var rec: Dictionary = _crime.ensure_rec(crook)
	var c55: Dictionary = rec["c55"]
	# Live crimes count toward the daily tally: a lone unanswered crime can
	# bring the mayor begging for a watch (SimCrime._begging_for_watch).
	_crime.state["crimesToday"] = int(_crime.state.get("crimesToday", 0)) + 1
	var cname: String = SimPersonality.display_name(crook)
	var vname: String = SimPersonality.display_name(victim)
	var vid: int = int(victim.get("id", 0))
	# Jeremy 2026-10-08 (hearsay flesh-out): point-blank spot check, moved
	# up — the grapevine only names a SPOTTED thief. An unseen thief is
	# crook_id 0 in the rumor mill: the town knows a crime happened, not
	# who did it (HTML "THIEF! I SAW THE WHOLE THING!" parity).
	var spotted: bool = randf() < (0.18 if bool(crook.get("sneaking", false)) else 0.55)
	var named_crook: int = int(crook.get("id", 0)) if spotted else 0
	if tool != "":
		var vtools: Array = victim.get("tools", [])
		if tool in vtools:
			vtools.erase(tool)
			var ctools: Array = crook.get("tools", [])
			if not tool in ctools:
				ctools.append(tool)
			crook["tools"] = ctools
		(c55["crimes"] as Array).append({"kind": "tool_theft",
			"day": _crime.state["day"], "victimUid": vid})
		_crime.add_evidence(rec, {"type": "victim", "uid": vid,
			"day": _crime.state["day"]})
		# Jeremy 2026-10-08 (hearsay flesh-out): the mill hears it first —
		# emitted before the Gazette story so the rich rumor dedups it.
		_gs.bus.crime_committed.emit("tool_theft", named_crook, vid,
			"", 0, "TOOL STOLEN")
		_crime.publish("TOOL STOLEN",
			"%s lifted a %s off %s and melted into the crowd."
			% [cname, tool, vname], "")
		_say(victim, "Hey! My %s!" % tool)
	else:
		var amt: int = mini(int(float(victim.get("coins", 0.0))),
			randi_range(10, 40))
		if amt > 0:
			victim["coins"] = maxf(0.0, float(victim.get("coins", 0.0)) - amt)
			crook["coins"] = float(crook.get("coins", 0.0)) + amt
			_crime.add_evidence(rec, {"type": "victim", "uid": vid,
				"day": _crime.state["day"]})
		(c55["crimes"] as Array).append({"kind": kind,
			"day": _crime.state["day"], "victimUid": vid})
		# Jeremy 2026-10-08 (hearsay flesh-out): the mill hears it first —
		# emitted before the Gazette story so the rich rumor dedups it.
		_gs.bus.crime_committed.emit(kind, named_crook, vid, "", amt,
			"PICKPOCKET STRIKES")
		_crime.publish("PICKPOCKET STRIKES",
			"%s's purse is lighter — %s vanished with %d gold."
			% [vname, cname, amt], "")
		_say(victim, "Hey! My coins!!")
	# Getaway: the spot check already ran above (the grapevine needs it
	# before the story publishes).
	if spotted:
		_say(victim, "It was %s! Guards!" % cname)
		victim["crime_phase"] = PHASE_WITNESS
		victim["crime_target"] = int(crook.get("id", 0))
		victim["crime_kind"] = kind
		victim["crime_t"] = 0.0
	# Getaway: stay sneaky, run from the scene.
	crook["crime_phase"] = PHASE_FLEE
	crook["crime_t"] = 0.0
	crook["crime_dest"] = crook.get("position", Vector2.ZERO)


func _tick_flee(unit: Dictionary, delta: float) -> void:
	var t: float = float(unit.get("crime_t", 0.0)) + delta
	unit["crime_t"] = t
	if t > FLEE_TIME:
		_clear_crime(unit)
		unit["crime_cd"] = _gs.game_time + randf_range(180.0, 420.0)
		return
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var scene: Vector2 = unit.get("crime_dest", upos)
	var away: Vector2 = upos - scene
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	_move(unit, upos + away.normalized() * 300.0, delta, 1.2)


# ------------------------------------------------------------------ witnesses

## A witness runs to the nearest guard (or the jail) to report.
func _tick_witness(unit: Dictionary, delta: float) -> void:
	var t: float = float(unit.get("crime_t", 0.0)) + delta
	unit["crime_t"] = t
	var crook: Dictionary = _gs.get_unit(int(unit.get("crime_target", -1)))
	var dest: Vector2 = _report_dest(unit)
	if dest == Vector2.INF or t > 45.0:
		_clear_crime(unit)  # nobody to tell — the report dies
		return
	if _move(unit, dest, delta, 1.25):
		_report_crime(unit, crook)
		_clear_crime(unit)


## Where a witness runs: nearest free guard, else the nearest jail.
func _report_dest(_unit: Dictionary) -> Vector2:
	var g: Dictionary = _nearest_free_guard(_unit)
	if not g.is_empty():
		return g.get("position", Vector2.ZERO)
	var jail: Dictionary = _jail_for(String(_unit.get("faction", "")),
		_unit.get("position", Vector2.ZERO))
	if not jail.is_empty():
		return jail.get("position", Vector2.ZERO)
	return Vector2.INF


## The report lands: the suspect is WANTED, the witness is evidence.
func _report_crime(witness: Dictionary, crook: Dictionary) -> void:
	var wid: int = int(witness.get("id", 0))
	if crook.is_empty() or not crook.get("alive", false):
		_say(witness, "They got away... I didn't see where they went.")
		return
	var rec: Dictionary = _crime.ensure_rec(crook)
	var c55: Dictionary = rec["c55"]
	c55["wanted"] = true
	_crime.add_evidence(rec, {"type": "witness", "uid": wid,
		"day": _crime.state["day"]})
	var wit_list: Array = c55.get("witnesses", [])
	if not wid in wit_list:
		wit_list.append(wid)
	c55["witnesses"] = wit_list
	var cname: String = SimPersonality.display_name(crook)
	var wname: String = SimPersonality.display_name(witness)
	_say(witness, "Guard! %s is a thief — I SAW it happen!" % cname)
	_crime.publish("WITNESS REPORTS CRIME",
		"%s ran to the watch and pointed at %s." % [wname, cname], "")


# --------------------------------------------------------------------- guards

func _is_guard(unit: Dictionary) -> bool:
	if String(unit.get("job", "")) == "guard":
		return true
	return bool((unit.get("mind", {}) as Dictionary).get("is_guard", false))


## A free guard of the suspect's faction, nearest first.
func _nearest_free_guard(to_unit: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e18
	var upos: Vector2 = to_unit.get("position", Vector2.ZERO)
	var cf: String = String(to_unit.get("faction", ""))
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != cf:
			continue
		if not _is_guard(u):
			continue
		if String(u.get("crime_phase", "")) != "":
			continue
		var d: float = upos.distance_squared_to(u.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = u
	return best


func _nearest_guard(to_unit: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e18
	var upos: Vector2 = to_unit.get("position", Vector2.ZERO)
	var cf: String = String(to_unit.get("faction", ""))
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != cf:
			continue
		if not _is_guard(u):
			continue
		var d: float = upos.distance_squared_to(u.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = u
	return best


## Every wanted suspect gets a hunter (HTML guardTick55 dispatch).
func _dispatch_guards() -> void:
	# Perf R26: guard-index dispatch. The old code ran _nearest_free_guard
	# (a full O(units) scan) once per wanted suspect — O(wanted x units),
	# probe-verified at ~187us per wanted suspect at 222 units (5 wanted =
	# 1.28ms/dispatch vs 0.35ms with none). Now a single pass builds the
	# free-guard list; each suspect scans only that list (guards are few).
	# Behavior-identical: suspects are visited in units order, ties break
	# first-in-units-order via strict <, assigned guards leave the free
	# list (the old scan skipped them via crime_phase != ""), and the
	# handled set is built from the same hunt-phase guards as before.
	# Suspects already being pursued, escorted, or executed.
	var handled: Dictionary = {}
	var free_guards: Array = []
	var pf: String = _gs.player_faction
	for g: Dictionary in _gs.units:
		if not g.get("alive", false):
			continue
		var gphase: String = String(g.get("crime_phase", ""))
		if gphase in [PHASE_GUARD_HUNT,
				PHASE_GUARD_ESCORT, PHASE_GUARD_LETHAL]:
			handled[int(g.get("crime_target", -1))] = true
			continue
		if String(g.get("faction", "")) != pf:
			continue
		if _is_guard(g) and gphase == "":
			free_guards.append(g)
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		var uid: int = int(u.get("id", 0))
		if handled.has(uid):
			continue
		var rec: Dictionary = _crime.rec_for(uid)
		if rec.is_empty():
			continue
		if not bool((rec.get("c55", {}) as Dictionary).get("wanted", false)):
			continue
		if _crime.is_jailed(uid):
			continue
		var uphase: String = String(u.get("crime_phase", ""))
		if uphase in [PHASE_HUNTED, PHASE_RESIST, PHASE_ESCORT,
				PHASE_JAILED, PHASE_TRIAL]:
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		var best: Dictionary = {}
		var best_d := 1e18
		var best_i := -1
		for i in range(free_guards.size()):
			var fg: Dictionary = free_guards[i]
			var d: float = upos.distance_squared_to(
				fg.get("position", Vector2.ZERO))
			if d < best_d:
				best_d = d
				best = fg
				best_i = i
		if not best.is_empty():
			_assign_hunt(best, u)
			free_guards.remove_at(best_i)
			handled[uid] = true


func _assign_hunt(guard: Dictionary, suspect: Dictionary) -> void:
	guard["crime_phase"] = PHASE_GUARD_HUNT
	guard["crime_target"] = int(suspect.get("id", 0))
	guard["crime_t"] = 0.0
	suspect["crime_phase"] = PHASE_HUNTED
	suspect["crime_target"] = int(guard.get("id", 0))
	suspect["crime_t"] = 0.0
	suspect["sneaking"] = false  # cover's blown — run
	_say(guard, "Stop right there, criminal scum!")


func _assign_lethal(guard: Dictionary, suspect: Dictionary) -> void:
	guard["crime_phase"] = PHASE_GUARD_LETHAL
	guard["crime_target"] = int(suspect.get("id", 0))
	guard["crime_t"] = 0.0
	guard["crime_lasthit"] = -99.0
	suspect["crime_phase"] = PHASE_RESIST
	suspect["crime_target"] = int(guard.get("id", 0))
	suspect["crime_t"] = 0.0
	suspect["crime_lasthit"] = -99.0
	suspect["sneaking"] = false


func _tick_guard_hunt(guard: Dictionary, delta: float) -> void:
	var t: float = float(guard.get("crime_t", 0.0)) + delta
	guard["crime_t"] = t
	var suspect: Dictionary = _gs.get_unit(int(guard.get("crime_target", -1)))
	if suspect.is_empty() or not suspect.get("alive", false) \
			or _crime.is_jailed(int(suspect.get("id", 0))):
		_clear_crime(guard)
		return
	if String(suspect.get("crime_phase", "")) == PHASE_JAILED \
			or String(suspect.get("crime_phase", "")) == PHASE_TRIAL:
		_clear_crime(guard)
		return
	if t > 120.0:
		# Lost them — back to post. Still wanted; watch re-dispatches.
		_clear_crime(guard)
		if String(suspect.get("crime_phase", "")) == PHASE_HUNTED:
			suspect["crime_phase"] = ""
		return
	_move(guard, suspect.get("position", Vector2.ZERO), delta, 1.15)
	var dist: float = guard.get("position", Vector2.ZERO) \
		.distance_to(suspect.get("position", Vector2.ZERO))
	if dist < CATCH_DIST:
		_arrest_attempt(guard, suspect)


## The suspect runs from their hunter.
func _tick_hunted(unit: Dictionary, delta: float) -> void:
	var guard: Dictionary = _gs.get_unit(int(unit.get("crime_target", -1)))
	var gphase: String = String(guard.get("crime_phase", "")) \
		if not guard.is_empty() else ""
	if guard.is_empty() or not guard.get("alive", false) \
			or not gphase in [PHASE_GUARD_HUNT, PHASE_GUARD_LETHAL]:
		# Escaped the hunter — sneak away, still wanted.
		unit["crime_phase"] = PHASE_FLEE
		unit["crime_t"] = 0.0
		unit["crime_dest"] = unit.get("position", Vector2.ZERO)
		unit["sneaking"] = true
		return
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var gpos: Vector2 = guard.get("position", Vector2.ZERO)
	if upos.distance_to(gpos) > ESCAPE_DIST:
		_clear_crime(guard)
		unit["crime_phase"] = PHASE_FLEE
		unit["crime_t"] = 0.0
		unit["crime_dest"] = upos
		unit["sneaking"] = true
		return
	var away: Vector2 = upos - gpos
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	_move(unit, upos + away.normalized() * 300.0, delta, 1.1)


## Caught: violent criminals may fight — everyone else is taken in.
func _arrest_attempt(guard: Dictionary, suspect: Dictionary) -> void:
	var resist_p := 0.05
	if SimPersonality.is_violent(suspect):
		resist_p = 0.75
	elif SimPersonality.trait_of(suspect, "brave") > 0.8:
		resist_p = 0.35
	if randf() < resist_p:
		_say(suspect, "You'll never take me alive!")
		_say(guard, "Resisting, eh? Have it your way.")
		suspect["crime_fx"] = "struggle"
		_assign_lethal(guard, suspect)
	else:
		_arrest(guard, suspect)


## In custody: the guard walks the suspect to the jail.
func _arrest(guard: Dictionary, suspect: Dictionary) -> void:
	var cname: String = SimPersonality.display_name(suspect)
	_crime.publish("ARREST MADE", "%s was arrested." % cname, "")
	_say(guard, "You're coming with me.")
	var rec: Dictionary = _crime.ensure_rec(suspect)
	(rec["c55"] as Dictionary)["wanted"] = false
	suspect["crime_phase"] = PHASE_ESCORT
	suspect["crime_target"] = int(guard.get("id", 0))
	suspect["crime_t"] = 0.0
	suspect["sneaking"] = false
	guard["crime_phase"] = PHASE_GUARD_ESCORT
	guard["crime_target"] = int(suspect.get("id", 0))
	guard["crime_t"] = 0.0
	var jail: Dictionary = _jail_for(String(suspect.get("faction", "")),
		suspect.get("position", Vector2.ZERO))
	guard["crime_dest"] = jail.get("position",
		suspect.get("position", Vector2.ZERO)) \
		if not jail.is_empty() else suspect.get("position", Vector2.ZERO)


func _tick_guard_escort(guard: Dictionary, delta: float) -> void:
	var suspect: Dictionary = _gs.get_unit(int(guard.get("crime_target", -1)))
	if suspect.is_empty() or not suspect.get("alive", false):
		_clear_crime(guard)
		return
	if String(suspect.get("crime_phase", "")) != PHASE_ESCORT:
		_clear_crime(guard)
		return
	var dest: Vector2 = guard.get("crime_dest",
		suspect.get("position", Vector2.ZERO))
	if _move(guard, dest, delta, 0.9):
		var dist: float = guard.get("position", Vector2.ZERO) \
			.distance_to(suspect.get("position", Vector2.ZERO))
		if dist < 120.0:
			_clear_crime(guard)
			_jail_unit(suspect, true)
			return
	# Suspect lags too far behind: wait up.
	var dist2: float = guard.get("position", Vector2.ZERO) \
		.distance_to(suspect.get("position", Vector2.ZERO))
	if dist2 > 220.0:
		_move(guard, suspect.get("position", Vector2.ZERO), delta, 0.9)


## The suspect follows their escort. Violent ones may turn on the guard.
func _tick_escort(unit: Dictionary, delta: float) -> void:
	var guard: Dictionary = _gs.get_unit(int(unit.get("crime_target", -1)))
	if guard.is_empty() or not guard.get("alive", false) \
			or String(guard.get("crime_phase", "")) != PHASE_GUARD_ESCORT:
		# Escort broke — flee, still wanted.
		var rec: Dictionary = _crime.ensure_rec(unit)
		(rec["c55"] as Dictionary)["wanted"] = true
		unit["crime_phase"] = PHASE_FLEE
		unit["crime_t"] = 0.0
		unit["crime_dest"] = unit.get("position", Vector2.ZERO)
		unit["sneaking"] = true
		return
	if SimPersonality.is_violent(unit) and randf() < delta * 0.06:
		_say(unit, "I'M NOT GOING BACK IN THERE!")
		unit["crime_fx"] = "struggle"
		_assign_lethal(guard, unit)
		return
	var gpos: Vector2 = guard.get("position", Vector2.ZERO)
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	if upos.distance_to(gpos) > 70.0:
		_move(unit, gpos, delta, 1.0)


# ------------------------------------------------------------------ resistance

## A resister trades blows with the guard. Guards fight to kill (Jeremy).
func _tick_resist(unit: Dictionary, delta: float) -> void:
	var t: float = float(unit.get("crime_t", 0.0)) + delta
	unit["crime_t"] = t
	var guard: Dictionary = _gs.get_unit(int(unit.get("crime_target", -1)))
	if guard.is_empty() or not guard.get("alive", false):
		# The guard is down — flee while the fleeing's good.
		_say(unit, "Shouldn't have messed with me.")
		unit["crime_phase"] = PHASE_FLEE
		unit["crime_t"] = 0.0
		unit["crime_dest"] = unit.get("position", Vector2.ZERO)
		unit["sneaking"] = true
		unit["crime_cd"] = _gs.game_time + 300.0
		return
	if String(guard.get("crime_phase", "")) != PHASE_GUARD_LETHAL:
		_clear_crime(unit)
		return
	var gpos: Vector2 = guard.get("position", Vector2.ZERO)
	_move(unit, gpos, delta, 1.0)
	var dist: float = unit.get("position", Vector2.ZERO).distance_to(gpos)
	var last: float = float(unit.get("crime_lasthit", -99.0))
	if dist < 52.0 and t - last > 1.5:
		unit["crime_lasthit"] = t
		_deal_damage(guard, randf_range(5.0, 10.0), unit, false)
		unit["crime_fx"] = "struggle"
	# Beaten down: the brave fight on, the rest give up.
	var hp_frac: float = float(unit.get("hp", 100.0)) \
		/ maxf(1.0, float(unit.get("max_hp", 100.0)))
	if hp_frac < 0.35:
		var brave: float = SimPersonality.trait_of(unit, "brave")
		if randf() < delta * (1.4 - brave):
			_say(unit, "I surrender! I SURRENDER!")
			_arrest(guard, unit)


## Guard lethal force: closes in and strikes to KILL (Jeremy's rule).
func _tick_guard_lethal(guard: Dictionary, delta: float) -> void:
	var t: float = float(guard.get("crime_t", 0.0)) + delta
	guard["crime_t"] = t
	var suspect: Dictionary = _gs.get_unit(int(guard.get("crime_target", -1)))
	if suspect.is_empty() or not suspect.get("alive", false):
		_clear_crime(guard)
		return
	if String(suspect.get("crime_phase", "")) != PHASE_RESIST:
		_clear_crime(guard)
		return
	_move(guard, suspect.get("position", Vector2.ZERO), delta, 1.1)
	var dist: float = guard.get("position", Vector2.ZERO) \
		.distance_to(suspect.get("position", Vector2.ZERO))
	var last: float = float(guard.get("crime_lasthit", -99.0))
	if dist < 52.0 and t - last > 1.2:
		guard["crime_lasthit"] = t
		_deal_damage(suspect, randf_range(12.0, 20.0), guard, true)
		suspect["crime_fx"] = "struggle"


## Damage that can actually kill (bypasses the downed/knockout path —
## executions and lethal force end lives, not fights).
func _deal_damage(target: Dictionary, dmg: float, attacker: Dictionary,
		lethal: bool) -> void:
	if target.is_empty() or not target.get("alive", false):
		return
	var hp: float = float(target.get("hp", 100.0)) - dmg
	target["hp"] = hp
	target["hurt_flash"] = 0.45
	target["combat_state"] = "hurt"
	if hp <= 0.0:
		var tid: int = int(target.get("id", -1))
		if lethal:
			_crime.publish("JUSTICE SERVED",
				"%s was slain resisting arrest."
				% SimPersonality.display_name(target), "")
		if _gs.kill_unit(tid):
			target["combat_state"] = "dead"
			_gs.bus.unit_killed.emit(tid, String(attacker.get("faction", "")))
		_clear_crime(target)
		var ag: Dictionary = attacker
		if not ag.is_empty() and int(ag.get("crime_target", -1)) == tid:
			_clear_crime(ag)


# ------------------------------------------------------------------------ jail

## Where suspects do time: nearest complete jail, else guard_house
## (HTML jailFor55), else courthouse, else town hall.
func _jail_for(faction: String, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e18
	var types: Array[String] = ["jail", "guard_house", "courthouse",
		"town_hall", "hall"]
	for want in types:
		for b: Dictionary in _gs.buildings:
			if not b.get("alive", false) or not b.get("complete", false):
				continue
			if String(b.get("faction", "")) != faction:
				continue
			if String(b.get("type", "")) != want:
				continue
			var d: float = pos.distance_squared_to(
				b.get("position", Vector2.ZERO))
			if d < best_d:
				best_d = d
				best = b
		if not best.is_empty():
			return best
	return best


## Lock them up. Pretrial detention or post-verdict sentence — same cells.
func _jail_unit(unit: Dictionary, pretrial: bool) -> void:
	var jail: Dictionary = _jail_for(String(unit.get("faction", "")),
		unit.get("position", Vector2.ZERO))
	var rec: Dictionary = _crime.ensure_rec(unit)
	var c55: Dictionary = rec["c55"]
	var cname: String = SimPersonality.display_name(unit)
	if pretrial:
		c55["awaitingTrial"] = true
		c55["trialDay"] = int(_crime.state["day"]) + 1
		var crimes: Array = c55["crimes"]
		var last: Dictionary = crimes.back() \
			if not crimes.is_empty() else {"kind": "theft"}
		c55["crimeKind"] = String(last.get("kind", "theft"))
		rec["jailedUntil"] = float(_crime.state["day"]) + 1.2
		var cdef: Dictionary = _crime.crime_def(String(c55["crimeKind"]))
		_crime.publish("JAILED AWAITING TRIAL",
			"%s sits in the cells awaiting trial for %s."
			% [cname, String(cdef["label"])], "")
	if jail.is_empty():
		unit["crime_phase"] = PHASE_JAILED
		unit["sneaking"] = false
		return
	var cells: Array = jail.get("cells", [])
	jail["cells"] = cells
	var idx: int = mini(cells.size(), JAIL_CELLS * 2)
	cells.append(int(unit.get("id", 0)))
	var jpos: Vector2 = jail.get("position", Vector2.ZERO)
	# Cell row in the jail yard — visible behind the barred front.
	unit["position"] = jpos + Vector2(-36.0 + float(idx % 6) * 14.0,
		30.0 + float(idx / 6) * 12.0)
	unit["crime_phase"] = PHASE_JAILED
	unit["sneaking"] = false


func _remove_from_cells(unit: Dictionary) -> void:
	var uid: int = int(unit.get("id", 0))
	for b: Dictionary in _gs.buildings:
		var cells: Array = b.get("cells", [])
		if uid in cells:
			cells.erase(uid)


## Time served (or acquitted): walk free.
func _release_jailed() -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("crime_phase", "")) != PHASE_JAILED:
			continue
		var uid: int = int(u.get("id", 0))
		if _crime.is_jailed(uid):
			continue
		_remove_from_cells(u)
		u["crime_phase"] = ""
		var rec: Dictionary = _crime.rec_for(uid)
		if not rec.is_empty():
			(rec["c55"] as Dictionary)["wanted"] = false
		_crime.publish("RELEASED",
			"%s walked free — time served."
			% SimPersonality.display_name(u), "")


## Prisoners sit out their time. Violent ones may riot — and learn why
## the guards carry swords (Jeremy: guards kill resisting prisoners).
func _tick_jailed(unit: Dictionary, _delta: float) -> void:
	if SimPersonality.trait_of(unit, "violent") > 0.85 and randf() < _delta * 0.004:
		var g: Dictionary = _nearest_guard(unit)
		if not g.is_empty() and String(g.get("crime_phase", "")) == "":
			_say(unit, "I'M GETTING OUT OF HERE!")
			unit["crime_fx"] = "struggle"
			_remove_from_cells(unit)
			_assign_lethal(g, unit)


# ----------------------------------------------------------------------- trial

## Court for a trial: the courthouse, else the town hall (HTML courtFor55).
func _court_for(faction: String) -> Dictionary:
	var hall: Dictionary = {}
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var t: String = String(b.get("type", ""))
		if t == "courthouse":
			return b
		if t == "town_hall" or t == "hall":
			hall = b
	return hall


func _find_live_trial() -> Dictionary:
	for key: Variant in (_crime.state["byUid"] as Dictionary).keys():
		var rec: Dictionary = (_crime.state["byUid"] as Dictionary)[key]
		var c55: Dictionary = rec.get("c55", {})
		if not (c55.get("trial", {}) as Dictionary).is_empty():
			return rec
	return {}


func _tick_live_trial(delta: float) -> void:
	var rec: Dictionary = _find_live_trial()
	if rec.is_empty():
		_start_due_trials()
		return
	var c55: Dictionary = rec["c55"]
	var trial: Dictionary = c55["trial"]
	trial["t"] = float(trial.get("t", 0.0)) + delta
	var cast: Dictionary = trial["cast"]
	var judge: Dictionary = _gs.get_unit(int(cast.get("judge", -1)))
	var suspect: Dictionary = _gs.get_unit(int(trial.get("suspect", -1)))
	if judge.is_empty() or suspect.is_empty() \
			or not suspect.get("alive", false):
		_end_trial(rec, "collapsed")
		return
	var phase: String = String(trial.get("phase", "convene"))
	if float(trial.get("t", 0.0)) >= float(TRIAL_PHASES.get(phase, 10.0)):
		trial["t"] = 0.0
		(trial["said"] as Dictionary).clear()
		var ni: int = TRIAL_ORDER.find(phase) + 1
		if ni >= TRIAL_ORDER.size():
			_end_trial(rec, "verdict")
			return
		trial["phase"] = TRIAL_ORDER[ni]
		phase = String(trial["phase"])
	_trial_dialogue(rec, trial, phase)


## Start trials whose day has come (HTML startDueTrial55). One live trial
## at a time; if no court or no cast, the daily abstract resolver covers it.
func _start_due_trials() -> void:
	for key: Variant in (_crime.state["byUid"] as Dictionary).keys():
		var rec: Dictionary = (_crime.state["byUid"] as Dictionary)[key]
		var c55: Dictionary = rec.get("c55", {})
		if not bool(c55.get("awaitingTrial", false)):
			continue
		if int(_crime.state["day"]) < int(c55.get("trialDay", 0)):
			continue
		if bool(c55.get("trial_live", false)):
			continue
		var suspect: Dictionary = _gs.get_unit(int(key))
		if suspect.is_empty() or not suspect.get("alive", false):
			c55["awaitingTrial"] = false
			continue
		if _start_live_trial(suspect, rec):
			return
		# No court/cast — leave it for the daily abstract verdict.


## Assemble the cast and open the courtroom (HTML startTrial55/castTrial55).
func _start_live_trial(suspect: Dictionary, rec: Dictionary) -> bool:
	var faction: String = String(suspect.get("faction", ""))
	var court_b: Dictionary = _court_for(faction)
	if court_b.is_empty():
		return false
	var cast: Dictionary = _cast_trial(suspect, rec)
	if cast.is_empty():
		return false  # not enough townsfolk — postpone (HTML)
	var c55: Dictionary = rec["c55"]
	var cpos: Vector2 = court_b.get("position", Vector2.ZERO)
	var trial: Dictionary = {
		"suspect": int(suspect.get("id", 0)),
		"kind": String(c55.get("crimeKind", "theft")),
		"phase": "convene",
		"t": 0.0,
		"said": {},
		"cast": {
			"judge": int((cast["judge"] as Dictionary).get("id", -1)),
			"prosecutor": int((cast["prosecutor"] as Dictionary).get("id", -1)),
			"defense": int((cast["defense"] as Dictionary).get("id", -1)),
			"guard": int((cast["guard"] as Dictionary).get("id", -1)),
			"victim": int((cast["victim"] as Dictionary).get("id", -1)),
			"jury": (cast["jury"] as Array).map(
				func(u: Dictionary) -> int: return int(u.get("id", -1))),
			"witnesses": (cast["witnesses"] as Array).map(
				func(u: Dictionary) -> int: return int(u.get("id", -1))),
			"audience": (cast["audience"] as Array).map(
				func(u: Dictionary) -> int: return int(u.get("id", -1))),
		},
	}
	# Out of the cell, into the courtroom — still in custody.
	_remove_from_cells(suspect)
	_seat(cast["judge"], "judge", cpos + Vector2(0, -40))
	_seat(suspect, "suspect", cpos + Vector2(-28, -10))
	if not (cast["guard"] as Dictionary).is_empty():
		_seat(cast["guard"], "guard", cpos + Vector2(-52, -10))
	_seat(cast["prosecutor"], "prosecutor", cpos + Vector2(34, -26))
	_seat(cast["defense"], "defense", cpos + Vector2(-34, 16))
	var jury: Array = cast["jury"]
	for i: int in jury.size():
		_seat(jury[i], "jury", cpos + Vector2(-48.0 + float(i) * 19.0, 36))
	var witnesses: Array = cast["witnesses"]
	for i: int in witnesses.size():
		_seat(witnesses[i], "witness", cpos + Vector2(28.0 + float(i) * 18.0, -10))
	if not (cast["victim"] as Dictionary).is_empty():
		_seat(cast["victim"], "victim", cpos + Vector2(48, 8))
	var audience: Array = cast["audience"]
	for i: int in audience.size():
		_seat(audience[i], "audience", cpos + Vector2(-44.0 + float(i) * 22.0, 62))
	c55["awaitingTrial"] = false
	c55["trial"] = trial
	c55["trial_live"] = true
	var cdef: Dictionary = _crime.crime_def(String(trial["kind"]))
	var jname: String = SimPersonality.display_name(cast["judge"])
	_say(cast["judge"], "Court is in session! Bring in the accused!")
	_crime.publish("TRIAL BEGINS",
		"%s stands trial for %s before Judge %s. %d good citizens have jury duty."
		% [SimPersonality.display_name(suspect), String(cdef["label"]),
			jname, jury.size()], "")
	return true


func _seat(unit: Dictionary, role: String, pos: Vector2) -> void:
	if unit.is_empty():
		return
	unit["crime_phase"] = PHASE_TRIAL
	unit["trial_role"] = role
	unit["crime_dest"] = pos
	unit["sneaking"] = false


## Cast the trial (HTML castTrial55): judge (judge job > mayor > eldest),
## prosecutor (guard else civilian), defense, 3–6 jurors, witnesses, victim.
func _cast_trial(suspect: Dictionary, rec: Dictionary) -> Dictionary:
	var sid: int = int(suspect.get("id", 0))
	var faction: String = String(suspect.get("faction", ""))
	var c55: Dictionary = rec["c55"]
	var wit_uids: Dictionary = {}
	for e: Variant in (c55.get("evidence", []) as Array):
		var ed: Dictionary = e
		if String(ed.get("type", "")) == "witness":
			wit_uids[int(ed.get("uid", -1))] = true
	var crimes: Array = c55.get("crimes", [])
	var victim_uid: int = int((crimes.back() as Dictionary).get("victimUid", -1)) \
		if not crimes.is_empty() else -1
	var pool: Array = []
	var guards: Array = []
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var uid: int = int(u.get("id", 0))
		if uid == sid:
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("crime_phase", "")) != "":
			continue
		if _is_guard(u):
			guards.append(u)
			continue
		if wit_uids.has(uid) or uid == victim_uid:
			continue
		pool.append(u)
	if pool.size() < 4:
		return {}  # not enough townsfolk — postpone
	# Judge: the judge job first, then the mayor, then the eldest (HTML).
	var judge: Dictionary = {}
	for u: Dictionary in pool:
		if String(u.get("job", "")) == "judge":
			judge = u
			break
	if judge.is_empty():
		for u: Dictionary in pool:
			if String((u.get("mind", {}) as Dictionary).get("gov_role", "")) == "mayor":
				judge = u
				break
	if judge.is_empty():
		var oldest: Dictionary = pool[0]
		for u: Dictionary in pool:
			if int(u.get("id", 0)) < int(oldest.get("id", 0)):
				oldest = u
		judge = oldest
	pool.erase(judge)
	var prosecutor: Dictionary = guards.pop_back() if not guards.is_empty() else {}
	if prosecutor.is_empty():
		prosecutor = pool.pop_back()
	var defense: Dictionary = pool.pop_back() if not pool.is_empty() else {}
	var jury: Array = []
	while jury.size() < 6 and not pool.is_empty():
		jury.append(pool.pop_back())
	if jury.size() < 3:
		return {}  # HTML: not enough jurors — postpone
	var witnesses: Array = []
	for wuid: Variant in wit_uids.keys():
		var w: Dictionary = _gs.get_unit(int(wuid))
		if not w.is_empty() and w.get("alive", false) \
				and String(w.get("crime_phase", "")) == "":
			witnesses.append(w)
	var victim: Dictionary = _gs.get_unit(victim_uid)
	if victim.is_empty() or not victim.get("alive", false):
		victim = {}
	var audience: Array = []
	while audience.size() < 4 and not pool.is_empty():
		audience.append(pool.pop_back())
	return {"judge": judge, "prosecutor": prosecutor, "defense": defense,
		"jury": jury, "witnesses": witnesses, "victim": victim,
		"audience": audience,
		"guard": guards.pop_back() if not guards.is_empty() else {}}


## The courtroom walks to its marks, then holds them.
func _tick_trial_cast(unit: Dictionary, delta: float) -> void:
	var dest: Vector2 = unit.get("crime_dest",
		unit.get("position", Vector2.ZERO))
	_move(unit, dest, delta, 1.0)


## Trial theater: each phase gets its dialogue beats (HTML trialTick55).
func _trial_dialogue(rec: Dictionary, trial: Dictionary, phase: String) -> void:
	var cast: Dictionary = trial["cast"]
	var said: Dictionary = trial["said"]
	var t: float = float(trial.get("t", 0.0))
	var judge: Dictionary = _gs.get_unit(int(cast.get("judge", -1)))
	var suspect: Dictionary = _gs.get_unit(int(trial.get("suspect", -1)))
	var sname: String = SimPersonality.display_name(suspect) \
		if not suspect.is_empty() else "the accused"
	var cdef: Dictionary = _crime.crime_def(String(trial.get("kind", "theft")))
	var clabel: String = String(cdef["label"])
	match phase:
		"convene":
			if not said.has("a"):
				said["a"] = true
				_say(judge, "Court is now in session. We are here for the matter of %s." % sname)
		"opening":
			var pros: Dictionary = _gs.get_unit(int(cast.get("prosecutor", -1)))
			if not said.has("a") and not pros.is_empty():
				said["a"] = true
				_say(pros, "The crown charges %s with %s. The evidence will speak plainly." % [sname, clabel])
			var defense: Dictionary = _gs.get_unit(int(cast.get("defense", -1)))
			if not said.has("b") and t > 5.0 and not defense.is_empty():
				said["b"] = true
				_say(defense, "My client is innocent, and I will prove it.")
		"testimony":
			var witnesses: Array = _units_for(cast.get("witnesses", []))
			var pros: Dictionary = _gs.get_unit(int(cast.get("prosecutor", -1)))
			if not said.has("a"):
				said["a"] = true
				if not witnesses.is_empty():
					_say(witnesses[0], "I saw %s do it! I'd swear on me mother's grave!" % sname)
				else:
					var victim: Dictionary = _gs.get_unit(int(cast.get("victim", -1)))
					if not victim.is_empty():
						_say(victim, "That's the one! They robbed me blind!")
					elif not pros.is_empty():
						_say(pros, "The prosecution rests on the physical evidence.")
			if not said.has("b") and t > 7.0 and witnesses.size() > 1:
				said["b"] = true
				_say(witnesses[1], "Aye, I saw it too. Clear as day.")
		"cross":
			var defense2: Dictionary = _gs.get_unit(int(cast.get("defense", -1)))
			if not said.has("a") and not defense2.is_empty():
				said["a"] = true
				_say(defense2, "Isn't it true you barely saw a thing that night?")
		"closing":
			var pros3: Dictionary = _gs.get_unit(int(cast.get("prosecutor", -1)))
			if not said.has("a") and not pros3.is_empty():
				said["a"] = true
				_say(pros3, "Witnesses. Evidence. A guilty heart. Convict.")
			var defense3: Dictionary = _gs.get_unit(int(cast.get("defense", -1)))
			if not said.has("b") and t > 5.0 and not defense3.is_empty():
				said["b"] = true
				_say(defense3, "Reasonable doubt, friends. That is all I ask you to see.")
		"deliberate":
			if not said.has("a"):
				said["a"] = true
				_say(judge, "The jury will now deliberate.")
			if randf() < t * 0.002:
				var jurors: Array = _units_for(cast.get("jury", []))
				if not jurors.is_empty():
					_say(jurors[randi() % jurors.size()],
						["Hmm...", "Tough one.", "Did they do it?", "I think so.", "Not sure..."][randi() % 5])


## Resolve id arrays to live unit records.
func _units_for(ids: Array) -> Array:
	var out: Array = []
	for i: Variant in ids:
		var u: Dictionary = _gs.get_unit(int(i))
		if not u.is_empty() and u.get("alive", false):
			out.append(u)
	return out


## Ends the live trial: releases the cast, then the verdict (or collapse).
func _end_trial(rec: Dictionary, how: String) -> void:
	var c55: Dictionary = rec["c55"]
	var trial: Dictionary = c55.get("trial", {})
	var cast: Dictionary = trial.get("cast", {})
	var suspect_id: int = int(trial.get("suspect", -1))
	var all_ids: Array = []
	for key: String in ["judge", "prosecutor", "defense", "guard", "victim"]:
		all_ids.append(int(cast.get(key, -1)))
	all_ids.append(suspect_id)
	for arr_key: String in ["jury", "witnesses", "audience"]:
		for i: Variant in (cast.get(arr_key, []) as Array):
			all_ids.append(int(i))
	for uid: Variant in all_ids:
		var u: Dictionary = _gs.get_unit(int(uid))
		if u.is_empty():
			continue
		if String(u.get("crime_phase", "")) == PHASE_TRIAL:
			u["crime_phase"] = ""
			u["trial_role"] = ""
	c55["trial"] = {}
	c55["trial_live"] = false
	var suspect: Dictionary = _gs.get_unit(suspect_id)
	if how == "collapsed" or suspect.is_empty() \
			or not suspect.get("alive", false):
		if how == "collapsed" and not suspect.is_empty() \
				and suspect.get("alive", false):
			# No verdict — back on the docket for tomorrow.
			c55["awaitingTrial"] = true
			c55["trialDay"] = int(_crime.state["day"]) + 1
			_jail_unit(suspect, false)
		return
	# The gavel falls.
	suspect["crime_fx"] = "gavel"
	_crime.resolve_verdict(suspect_id)
	if _crime.is_jailed(suspect_id):
		_jail_unit(suspect, false)  # guilty — serve the sentence
	else:
		suspect["crime_phase"] = ""  # acquitted — walk free


# ------------------------------------------------------------------ plumbing

func _clear_crime(unit: Dictionary) -> void:
	unit["crime_phase"] = ""
	unit["crime_target"] = -1
	unit["crime_kind"] = ""
	unit["crime_tool"] = ""
	unit["crime_t"] = 0.0
	unit["sneaking"] = false
	unit["trial_role"] = ""


## Steering with cliff rules (mirrors WorkerAI.move_unit + a speed factor).
## Returns true on arrival.
func _move(unit: Dictionary, target: Vector2, delta: float,
		speed_mul: float = 1.0) -> bool:
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var to: Vector2 = target - pos
	var dist: float = to.length()
	var step: float = float(unit.get("speed", 55.0)) * speed_mul * delta
	if bool(unit.get("swimming", false)):
		step *= 0.55
	# Jeremy 2026-10-05: same water rules as WorkerAI — avoid unless
	# fleeing (criminals on the run may swim).
	var avoid := WaterNav.unit_avoids_water(unit)
	if dist <= maxf(6.0, step):
		var np: Vector2 = Cliffs.try_step(_gs.map_data, pos, to)
		if avoid:
			np = WaterNav.dry_step(_gs.map_data, pos, np - pos)
		unit["position"] = np
		unit["swimming"] = WaterNav.is_water_at(_gs.map_data, np)
		return np.distance_squared_to(target) < 2500.0
	var np2: Vector2 = Cliffs.try_step(_gs.map_data, pos, to / dist * step)
	if avoid:
		np2 = WaterNav.dry_step(_gs.map_data, pos, np2 - pos)
	unit["position"] = np2
	unit["swimming"] = WaterNav.is_water_at(_gs.map_data, np2)
	return false


func _say(unit: Dictionary, text: String) -> void:
	if unit.is_empty() or text == "":
		return
	_gs.bus.unit_said.emit(int(unit.get("id", 0)), text)
