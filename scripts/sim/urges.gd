class_name SimUrges
extends RefCounted
## Cursing Gnomes — NPC urge system (Milestone 5: minds).
##
## The need system is called "urges" — full stop. (Jeremy's naming law.)
##
## Six urges, 0–100 (100 = fully satisfied), ported from the HTML build's
## liveUrgeDefs: Hunger, Energy, Hygiene, Social, Mood, Bladder. Each decays
## over time; when one drops under its critical threshold the NPC stops
## working and satisfies it (hunger eats faction food, energy sleeps,
## bladder relieves, hygiene bathes, social seeks company, mood recovers
## once everything else is fine).
##
## Urge state lives on the unit record ("urges" dict) — backward compatible,
## optional, lazily created. Pure logic — no rendering, no input, no audio.


## Urge ids, in HTML display order.
const URGES: Array[String] = ["hunger", "energy", "hygiene", "social", "mood", "bladder"]

## Points lost per second per urge.
const DECAY := {
	"hunger": 0.35,
	"energy": 0.22,
	"hygiene": 0.12,
	"social": 0.18,
	"mood": 0.08,
	"bladder": 0.45,
}

## Below this value the urge is critical and overrides job work.
const CRITICAL := {
	"hunger": 15.0,
	"energy": 12.0,
	"bladder": 10.0,
	"hygiene": 20.0,
	"social": 25.0,
	"mood": 30.0,
}

## Points restored per second while actively satisfying (instant ones skip).
const SATISFY_RATE := {
	"energy": 18.0,
	"hygiene": 15.0,
	"social": 12.0,
	"mood": 8.0,
}

const MEAL_FOOD_COST := 2.0   # food units spent per meal
const MEAL_RESTORE := 55.0    # hunger points per meal
const SOCIAL_DONE := 70.0     # social counts as satisfied here
const MOOD_DONE := 60.0

## Jeremy 2026-10-04: a full night's sleep is 8 in-game hours in a REAL bed.
## One game day is Config.DAY_LENGTH_SECONDS (480 s) = 24 game hours, so a
## full 0->100 rest takes 8 * 20 = 160 s of sleep. Furniture matters now:
## without the right furniture, recovery is slow and caps low.
const SLEEP_GAME_HOURS := 2.0
const SLEEP_RATE := 100.0 / (SLEEP_GAME_HOURS * Config.DAY_LENGTH_SECONDS / 24.0)
const SLEEP_DONE := 95.0
## Floor-sleep (no bed): shallow and restless — never fully restorative.
const SLEEP_RATE_ROUGH := 0.3
const SLEEP_CAP_ROUGH := 50.0
## No toilet: slow, partial relief (behind a bush).
const BLADDER_RATE_ROUGH := 10.0
const BLADDER_CAP_ROUGH := 60.0
## No sink/tub: a bird-bath only goes so far.
const WASH_RATE_ROUGH := 3.0
const WASH_CAP_ROUGH := 50.0


var _gs: GameState


func _init(game_state: GameState) -> void:
	_gs = game_state


## Lazily creates the urge dict on a unit record (default 60 — not starving).
func ensure(unit: Dictionary) -> Dictionary:
	if not unit.has("urges"):
		var u: Dictionary = {}
		for urge: String in URGES:
			u[urge] = 60.0
		unit["urges"] = u
	return unit["urges"]


## Decay all urges by delta seconds. Returns the worst critical urge id,
## or "" if nothing is critical. Checks in fixed priority order so the
## result is deterministic: hunger, bladder, energy, hygiene, social, mood.
## R31: single pass — decay, criticality flags, and priority resolution in
## one loop (was: decay loop + worst_critical() scan + priority scan).
func tick(unit: Dictionary, delta: float) -> String:
	if not unit.get("alive", false):
		return ""
	var u: Dictionary = ensure(unit)
	# crit[] follows URGES order: hunger, energy, hygiene, social, mood,
	# bladder. Flags are post-decay; mood is recomputed after drift below.
	var crit := [false, false, false, false, false, false]
	var i := 0
	for urge: String in URGES:
		var dec: float = float(DECAY.get(urge, 0.2)) * delta
		if urge == "energy":
			# Kyle the CrossFit Gnome (massive-dev 2026-10-08): swole
			# citizens tire slower — each swole stack cuts energy decay
			# 5%, capped at 50% (10 stacks). Burpees build character.
			dec *= 1.0 - minf(0.5, 0.05 * float(unit.get("swole", 0)))
		var v: float = clampf(float(u.get(urge, 60.0)) - dec, 0.0, 100.0)
		u[urge] = v
		crit[i] = v < float(CRITICAL.get(urge, 0.0))
		i += 1
	# Mood passively recovers when nothing else is critical.
	if not (crit[0] or crit[1] or crit[2] or crit[3] or crit[4] or crit[5]):
		u["mood"] = clampf(float(u.get("mood", 60.0)) + 2.0 * delta, 0.0, 80.0)
	# Night + storm mood drift (DESIGN-PORT: HTML has no night-mood
	# numbers — kept small and labeled).
	if _gs.get("seasons") != null:
		var night: bool = _gs.seasons.is_night_hour()
		var w: String = String(_gs.seasons.weather)
		if night:
			u["mood"] = clampf(float(u.get("mood", 60.0)) - 0.6 * delta,
				0.0, 100.0)
			crit[4] = float(u["mood"]) < float(CRITICAL.get("mood", 0.0))
		if w == "storm":
			u["mood"] = clampf(float(u.get("mood", 60.0)) - 0.4 * delta,
				0.0, 100.0)
			crit[4] = float(u["mood"]) < float(CRITICAL.get("mood", 0.0))
	# Fixed priority: survival first.
	# Priority order is hunger, bladder, energy, hygiene, social, mood —
	# URGES indexes: hunger 0, bladder 5, energy 1, hygiene 2, social 3,
	# mood 4.
	if crit[0]:
		return "hunger"
	if crit[5]:
		return "bladder"
	if crit[1]:
		return "energy"
	if crit[2]:
		return "hygiene"
	if crit[3]:
		return "social"
	if crit[4]:
		return "mood"
	return ""


## Worst critical urge without decaying (query helper for the mind).
## R31: unrolled priority scan with direct lookups (was: ensure() + loop
## over a fresh array literal + two dict gets per urge).
func worst_critical(unit: Dictionary) -> String:
	var u: Dictionary = unit.get("urges", {})
	if u.is_empty():
		u = ensure(unit)
	if float(u.get("hunger", 100.0)) < float(CRITICAL.get("hunger", 0.0)):
		return "hunger"
	if float(u.get("bladder", 100.0)) < float(CRITICAL.get("bladder", 0.0)):
		return "bladder"
	if float(u.get("energy", 100.0)) < float(CRITICAL.get("energy", 0.0)):
		return "energy"
	if float(u.get("hygiene", 100.0)) < float(CRITICAL.get("hygiene", 0.0)):
		return "hygiene"
	if float(u.get("social", 100.0)) < float(CRITICAL.get("social", 0.0)):
		return "social"
	if float(u.get("mood", 100.0)) < float(CRITICAL.get("mood", 0.0)):
		return "mood"
	return ""


## Current value of an urge (0–100).
func value(unit: Dictionary, urge: String) -> float:
	return float(ensure(unit).get(urge, 60.0))


## One satisfy tick. Returns "done" | "busy" | "cant".
## "cant" means satisfaction is impossible right now (e.g. no food) — the
## mind clears the override so the NPC works hungry instead of idling.
## `furnished`: the unit has proper furniture for this urge — a real bed for
## energy, a toilet for bladder, a sink/tub/shower for hygiene. Without it,
## recovery is slow and caps low (floor-sleep, bush relief, bird-bath).
func satisfy(unit: Dictionary, urge: String, delta: float,
		furnished: bool = true) -> String:
	var u: Dictionary = ensure(unit)
	match urge:
		"hunger":
			return _satisfy_hunger(unit, u)
		"bladder":
			if furnished:
				u["bladder"] = 100.0
				return "done"
			u["bladder"] = clampf(float(u["bladder"])
				+ BLADDER_RATE_ROUGH * delta, 0.0, BLADDER_CAP_ROUGH)
			return "done" if float(u["bladder"]) >= BLADDER_CAP_ROUGH else "busy"
		"energy":
			var erate := SLEEP_RATE if furnished else SLEEP_RATE_ROUGH
			var ecap := SLEEP_DONE if furnished else SLEEP_CAP_ROUGH
			u["energy"] = clampf(float(u["energy"]) + erate * delta, 0.0, ecap)
			return "done" if float(u["energy"]) >= ecap else "busy"
		"hygiene":
			var hrate := float(SATISFY_RATE["hygiene"]) if furnished \
				else WASH_RATE_ROUGH
			var hcap := 90.0 if furnished else WASH_CAP_ROUGH
			u["hygiene"] = clampf(float(u["hygiene"]) + hrate * delta,
				0.0, hcap)
			return "done" if float(u["hygiene"]) >= hcap else "busy"
		"social":
			return _satisfy_social(unit, u, delta)
		"mood":
			u["mood"] = clampf(float(u["mood"]) + float(SATISFY_RATE["mood"]) * delta, 0.0, 100.0)
			return "done" if float(u["mood"]) >= MOOD_DONE else "busy"
	return "cant"


## True when the faction stores hold enough food for a meal (no spending).
func can_eat(unit: Dictionary) -> bool:
	var faction: String = String(unit.get("faction", ""))
	return _gs.resources.get_amount(faction, "food") >= MEAL_FOOD_COST


func _satisfy_hunger(unit: Dictionary, u: Dictionary) -> String:
	if can_eat(unit):
		_gs.resources.spend(String(unit.get("faction", "")), {"food": MEAL_FOOD_COST})
		u["hunger"] = clampf(float(u["hunger"]) + MEAL_RESTORE, 0.0, 100.0)
		# Jeremy 2026-10-04: perk restaurants — eating the signature dish
		# grants a timed buff. Check which building the unit is inside.
		_apply_dish_perk(unit)
		return "done"
	return "cant"  # no food in the stores — work hungry, don't idle


## If the unit is inside a perk restaurant, apply its signature dish.
func _apply_dish_perk(unit: Dictionary) -> void:
	var bid: int = int(unit.get("inside_building_id", 0))
	if bid <= 0:
		return
	for b in _gs.buildings:
		if int(b.get("id", 0)) == bid:
			var btype: String = String(b.get("type", ""))
			if SimFoodPerks.is_perk_restaurant(btype):
				SimFoodPerks.apply_dish(unit, btype, _gs.game_time)
			return


## Jeremy 2026-10-05: friendships drive socializing (SimFamily bonds).
## A lonely NPC seeks out their best friend and walks to them; time with a
## friend satisfies faster and lifts mood; a finished chat leaves an
## impression (HTML: bumpAffinity 6 - friction*3 + noise on chat end).
func _satisfy_social(unit: Dictionary, u: Dictionary, delta: float) -> String:
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var fam: SimFamily = _gs.get("family") as SimFamily
	var friend: Dictionary = {}
	if fam != null:
		var tid: int = int(unit.get("social_target", -1))
		if tid >= 0:
			var t: Dictionary = _gs.get_unit(tid)
			if _valid_friend_target(unit, t):
				friend = t
			else:
				unit["social_target"] = -1
		if friend.is_empty() \
				and float(unit.get("social_repick_t", 0.0)) <= 0.0:
			friend = fam.best_friend(unit, SimFamily.FRIEND_SEEK_RADIUS)
			if not friend.is_empty():
				unit["social_target"] = int(friend.get("id", -1))
			unit["social_repick_t"] = 3.0
		unit["social_repick_t"] = maxf(0.0,
			float(unit.get("social_repick_t", 0.0)) - delta)
	# Walk to the friend when they are far; the walk itself is lonely.
	var friend_near := false
	if not friend.is_empty():
		var fpos: Vector2 = friend.get("position", Vector2.ZERO)
		if pos.distance_to(fpos) > 200.0:
			WorkerAI.move_unit(_gs, unit, fpos, delta)
			pos = unit.get("position", Vector2.ZERO)
		else:
			friend_near = true
	# Company: nearest living ally within 200px.
	var company := false
	var companion: Dictionary = {}
	var nearest_d := 200.0
	for other: Dictionary in _gs.units:
		if not other.get("alive", false):
			continue
		if int(other.get("id", -1)) == int(unit.get("id", -2)):
			continue
		if String(other.get("faction", "")) != String(unit.get("faction", "")):
			continue
		var d: float = pos.distance_to(other.get("position", Vector2.ZERO))
		if d <= nearest_d:
			nearest_d = d
			company = true
			companion = other
	var rate: float
	if friend_near:
		# Joy: time with a friend satisfies faster and lifts the mood.
		rate = float(SATISFY_RATE["social"]) * 1.5
		u["mood"] = clampf(float(u.get("mood", 60.0)) + 2.0 * delta,
			0.0, 100.0)
		companion = friend
		company = true
	elif company:
		rate = float(SATISFY_RATE["social"])
	else:
		rate = 2.0
	u["social"] = clampf(float(u["social"]) + rate * delta, 0.0, 100.0)
	var done_at: float = SOCIAL_DONE if company else 60.0
	if float(u["social"]) < done_at:
		return "busy"
	# A finished chat leaves an impression: compatible souls bond, friction
	# grates (HTML social-slot partner bump, verbatim).
	if fam != null and not companion.is_empty():
		var fr := fam.trait_friction(unit, companion)
		fam.bump_affinity(unit, companion,
			6.0 - fr * 3.0 + (randf() - 0.5) * 4.0)
	unit["social_target"] = -1
	return "done"


## A stored social_target is only usable while it stays a valid friend.
func _valid_friend_target(unit: Dictionary, t: Dictionary) -> bool:
	if t.is_empty() or not bool(t.get("alive", false)):
		return false
	if int(t.get("id", -1)) == int(unit.get("id", -2)):
		return false
	if String(t.get("faction", "")) != String(unit.get("faction", "")):
		return false
	if bool(t.get("is_child", false)) or bool(t.get("is_leader", false)):
		return false
	return true
