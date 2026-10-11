class_name SimUndead
extends RefCounted
## Cursing Gnomes — the undead death economy (Milestone 5).
##
## Faithful port of the HTML build's C61/C62 undead systems (fix79):
##   - Soul essence: +3 when an undead unit dies (recycle), +2 when a living
##     unit dies within 500 px of a living undead unit. Uncapped pool, spent on
##     elite training (wraith 15, necromancer 25, plaguebearer 10,
##     bone_golem 40, lich 60) and necromancer raises (10).
##   - Corpses persist 50 s after battle (max 120) as harvestable entities.
##   - Necromancers raise the nearest corpse within 550 px into a skeleton
##     (60%) or zombie (40%), 6 s cooldown, 10 soul.
##   - Ghouls feed on corpses: +35 hp within 45 px, seek corpses within 500 px.
##   - Flesh farms (150g/40w, undead only) haul corpses within 900 px into a
##     meat stock (max 12, animal corpses preferred); hungry zombies eat meat.
##   - Plague clouds: plaguebearer death leaves an 8 s cloud, radius 110 px,
##     infecting the living (chance 1.2/s). Infection incubates, spreads to
##     nearby living (70 px), and turns victims into zombies after 25 s.
##   - Zombie hunger: drains over ~4 minutes; starving zombies weaken, go
##     feral below 8 (attack anyone), and feed at flesh farms.
##
## Decoupling: this class consumes the existing bus.unit_died(unit_id, faction)
## signal and re-reads the full record via GameState.get_unit — it never
## touches combat.gd internals. Melee infection needs one call from whoever
## resolves hits (see maybe_infect_on_hit and the HOOKS section of the report).
## Pure logic — no rendering, no input, no audio.


## Elite soul costs (HTML SOUL_COST61). Skeleton/zombie/ghoul cost no soul.
const SOUL_COST := {
	"wraith": 15.0, "necromancer": 25.0, "plaguebearer": 10.0,
	"bone_golem": 40.0, "lich": 60.0,
}

const NECRO_RAISE_COST := 10.0
const NECRO_RAISE_RANGE := 550.0
const NECRO_RAISE_CD := 6.0
const NECRO_RAISE_SKELETON_CHANCE := 0.6

const CORPSE_LIFETIME := 50.0   # HTML corpse t: 50
const MAX_CORPSES := 120        # HTML: corpse list capped at 120

const SOUL_GAIN_RECYCLE := 3.0  # undead death recycles its own soul
const SOUL_GAIN_NEARBY := 2.0   # living death near a living undead unit
const SOUL_SENSE_RANGE := 500.0

const GHOUL_HEAL := 35.0
const GHOUL_FEED_RANGE := 45.0
const GHOUL_SEEK_RANGE := 500.0

const PLAGUE_DURATION := 8.0    # plaguebearer death cloud lifetime
const PLAGUE_RADIUS := 110.0
const PLAGUE_INFECT_RATE := 1.2 # per-second infection chance in the cloud
const INFECT_SPREAD_RADIUS := 70.0
const INFECT_SPREAD_RATE := 0.15
const INFECT_SPREAD_CHANCE := 0.3
const INFECT_TURN_TIME := 25.0  # incubation before the victim turns
const MELEE_INFECT_CHANCE := 0.35  # zombie / plaguebearer hits infect

const FLESH_FARM_COST := {"gold": 150.0, "wood": 40.0}
const FLESH_FARM_PULL_RADIUS := 900.0
const FLESH_FARM_MEAT_MAX := 12

const HUNGER_DRAIN_PER_S := 100.0 / 240.0  # 100 pts over half a 480 s day
const HUNGER_FEED_SEEK := 1500.0
const HUNGER_FEED_DIST := 80.0
const HUNGER_FEED_AMOUNT := 50.0
const FERAL_RANGE := 170.0
const FERAL_ATTACK_DIST := 40.0
const FERAL_ATTACK_CD := 1.0

## Idle-animal hunt (HTML undeadHuntTick62): non-feral zombie/ghoul/skeleton
## units with no orders hunt the nearest wild animal within HUNT_RANGE.
## HTML-verbatim: 280 scan, 44 attack distance, 0.9 s attack cooldown,
## dmg = u.dmg (default 8); kills go through SimAnimals.damage_wild
## (animalDeath62 parity: corpse to the undead corpse economy).
## Deliberate scoping: HTML scans the global `animals` array (wild + penned
## stock); Godot targets wild animals only — penned farm livestock is
## enclosed and not roaming prey. Elites (necromancer, wraith,
## plaguebearer, lich, bone_golem) never hunt, verbatim.
const HUNT_RANGE := 280.0
const HUNT_ATTACK_DIST := 44.0
const HUNT_ATTACK_CD := 0.9
const HUNT_JOBS := ["zombie", "ghoul", "skeleton"]

## Undead roster. Multipliers mirror the HTML Unit job branches; base hp comes
## from the spawner (undead race hp 220), base dmg defaults to the soldier's 15.
## Speeds are the HTML speed multipliers mapped onto Godot px/s (soldier 95).
const UNDEAD_ROSTER := {
	"skeleton": {  # cheap chaff infantry — barracks, no soul cost
		"hp_mul": 0.9, "dmg_mul": 0.9, "speed": 100.0, "attack_rate": 0.5,
		"cost": {"gold": 40.0, "wood": 0.0}, "train_time": 4.0,
		"trained_at": "barracks",
	},
	"zombie": {  # slow tank, infects on hit — barracks, no soul cost
		"hp_mul": 2.0, "dmg_mul": 1.1, "speed": 57.0, "attack_rate": 0.8,
		"infects_on_hit": true,
		"cost": {"gold": 60.0, "wood": 0.0}, "train_time": 5.0,
		"trained_at": "barracks",
	},
	"ghoul": {  # fast skirmisher, feeds on corpses — barracks, no soul cost
		"hp_mul": 1.1, "dmg_mul": 1.25, "speed": 138.0, "attack_rate": 0.45,
		"cost": {"gold": 80.0, "wood": 0.0}, "train_time": 6.0,
		"trained_at": "barracks",
	},
	"wraith": {  # floating life-drainer, ignores wall slow — necropolis
		"hp_mul": 0.85, "dmg_mul": 1.0, "speed": 128.0, "attack_rate": 0.6,
		"range_bonus": 10.0, "life_drain": 0.5, "ignore_wall_slow": true,
		"soul": 15.0, "cost": {"gold": 110.0, "wood": 40.0},
		"train_time": 9.0, "trained_at": "necropolis",
	},
	"necromancer": {  # raises the fallen, soul-bolt ranged — necropolis
		"hp_mul": 0.95, "dmg_mul": 1.2, "speed": 90.0, "attack_rate": 0.9,
		"range": 240.0,
		"soul": 25.0, "cost": {"gold": 150.0, "wood": 80.0},
		"train_time": 12.0, "trained_at": "necropolis",
	},
	"plaguebearer": {  # infection cloud on death — necropolis
		"hp_mul": 1.0, "dmg_mul": 0.8, "speed": 81.0, "attack_rate": 0.7,
		"range_bonus": 8.0, "infects_on_hit": true,
		"soul": 10.0, "cost": {"gold": 90.0, "wood": 20.0},
		"train_time": 7.0, "trained_at": "necropolis",
	},
	"bone_golem": {  # undead siege engine — necropolis
		"hp_mul": 4.5, "dmg_mul": 2.8, "speed": 52.0, "attack_rate": 1.2,
		"range_bonus": 18.0, "siege": true,
		"soul": 40.0, "cost": {"gold": 200.0, "wood": 140.0},
		"train_time": 18.0, "trained_at": "necropolis",
	},
	"lich": {  # undead ruler unit — sandbox/ruler in HTML, soul cost kept
		"hp_mul": 2.5, "dmg_mul": 2.0, "speed": 95.0, "attack_rate": 0.8,
		"range": 260.0, "splash": 70.0, "splash_mul": 0.5,
		"soul": 60.0, "cost": {"gold": 300.0, "wood": 200.0},
		"train_time": 25.0, "trained_at": "sandbox",
	},
}


var _gs: GameState
var _combat = null  # SimCombat, duck-typed (feral melee only)

var corpses: Array[Dictionary] = []       # harvestable dead: {x,y,race,job,t}
var plague_clouds: Array[Dictionary] = [] # {x,y,t}
var _soul: Dictionary = {}                 # faction -> soul essence (uncapped)
var _tick_frame := 0  # stagger counter: tick runs every 3rd frame (20 Hz);
                      # ephemeral, not saved (to_dict/from_dict untouched)


func _init(game_state: GameState, combat = null) -> void:
	_gs = game_state
	_combat = combat
	_gs.bus.unit_died.connect(_on_unit_died)


## ---- death: corpses, soul essence, plague ---------------------------------
## Consumes bus.unit_died and re-reads the full record (decoupled from whoever
## killed the unit). HTML: window.undeadOnUnitDeath.

func _on_unit_died(unit_id: int, _faction: String) -> void:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	# Corpses persist after battle as harvestable entities (HTML t: 50).
	if corpses.size() < MAX_CORPSES:
		corpses.append({
			"x": upos.x, "y": upos.y,
			"race": String(u.get("faction", "")),
			"job": String(u.get("job", "")),
			"t": CORPSE_LIFETIME,
		})
	# Soul essence (HTML undeadOnUnitDeath soul gain).
	var gain: float = 0.0
	if String(u.get("faction", "")) == "undead":
		gain = SOUL_GAIN_RECYCLE
	else:
		for o: Dictionary in _gs.units:
			if not o.get("alive", false):
				continue
			if String(o.get("faction", "")) != "undead":
				continue
			if upos.distance_to(o.get("position", Vector2.ZERO)) <= SOUL_SENSE_RANGE:
				gain = SOUL_GAIN_NEARBY
				break
	if gain > 0.0:
		add_soul("undead", gain)
	# Plaguebearers burst into an infection cloud on death.
	if String(u.get("job", "")) == "plaguebearer":
		plague_clouds.append({"x": upos.x, "y": upos.y, "t": PLAGUE_DURATION})


## ---- soul essence ----------------------------------------------------------

func get_soul(faction: String) -> float:
	# Canonical store is the internal dict (save contract: to_dict/from_dict
	# round-trip it); the resource ledger is mirrored for UI/economy.
	return float(_soul.get(faction, 0.0))


func add_soul(faction: String, amount: float) -> float:
	_soul[faction] = get_soul(faction) + amount
	_mirror_ledger(faction)
	return float(_soul[faction])


## Mirrors the internal soul count into the faction resource ledger so the
## HUD/economy sees soul_essence like any other resource.
func _mirror_ledger(faction: String) -> void:
	if _gs == null or _gs.get("resources") == null:
		return
	var want: float = get_soul(faction)
	var cur: float = _gs.resources.get_amount(faction, "soul_essence")
	if absf(cur - want) > 0.001:
		_gs.resources.add_resource(faction, "soul_essence", want - cur, true)


## Soul cost of an elite (HTML soulCost61). 0 for chaff and non-undead jobs.
func soul_cost(job: String) -> float:
	var r: Dictionary = UNDEAD_ROSTER.get(job, {})
	return float(r.get("soul", 0.0))


func can_afford_soul(faction: String, job: String) -> bool:
	return get_soul(faction) >= soul_cost(job)


## Gate for elite training (HTML Building.canTrain soul check): spends the
## soul cost when affordable. Returns false when the faction lacks soul.
func train_elite(faction: String, job: String) -> bool:
	var cost: float = soul_cost(job)
	if cost <= 0.0:
		return true
	if get_soul(faction) < cost:
		return false
	_soul[faction] = get_soul(faction) - cost
	_mirror_ledger(faction)
	return true


## ---- necromancy -------------------------------------------------------------

## Raises the nearest corpse within 550 px (HTML window.necroRaise61).
## Costs 10 soul, 6 s cooldown; skeleton 60% / zombie 40%.
## Spawned through the Spawner so the 16/48/240 caps hold.
func try_necro_raise(necro: Dictionary) -> bool:
	if necro.is_empty() or not necro.get("alive", false):
		return false
	if float(necro.get("raise_cd", 0.0)) > 0.0:
		return false
	if corpses.is_empty():
		return false
	var npos: Vector2 = necro.get("position", Vector2.ZERO)
	var bi: int = -1
	var best_d2: float = NECRO_RAISE_RANGE * NECRO_RAISE_RANGE
	for i: int in corpses.size():
		var c: Dictionary = corpses[i]
		var d2: float = npos.distance_squared_to(Vector2(c["x"], c["y"]))
		if d2 < best_d2:
			best_d2 = d2
			bi = i
	if bi < 0:
		return false
	if get_soul("undead") < NECRO_RAISE_COST:
		return false
	var pick: String = "skeleton" if randf() < NECRO_RAISE_SKELETON_CHANCE else "zombie"
	if _gs.spawner.check_spawn("undead", pick, int(necro.get("town_id", -1))) != "ok":
		return false
	var corpse: Dictionary = corpses[bi]
	corpses.remove_at(bi)
	add_soul("undead", -NECRO_RAISE_COST)
	necro["raise_cd"] = NECRO_RAISE_CD
	var u: Dictionary = _gs.spawner.spawn_unit("undead", pick,
		int(necro.get("town_id", -1)),
		Vector2(float(corpse["x"]) + randf_range(-20.0, 20.0),
			float(corpse["y"]) + randf_range(-20.0, 20.0)))
	if u.is_empty():
		return false
	u["raised"] = true
	apply_undead_stats(u)
	return true


## ---- infection ---------------------------------------------------------------

func infect_unit(u: Dictionary, src: String) -> void:
	if u.is_empty() or not u.get("alive", false):
		return
	if String(u.get("faction", "")) == "undead":
		return
	if u.has("infected"):
		return
	u["infected"] = {"t": 0.0, "src": src}


## Melee infection hook (HTML zombieInfect61): call from whoever resolves a
## melee hit — zombie and plaguebearer hits infect the living 35% of the time.
func maybe_infect_on_hit(attacker: Dictionary, target: Dictionary) -> bool:
	if attacker.is_empty() or target.is_empty():
		return false
	if String(attacker.get("faction", "")) != "undead":
		return false
	if not bool(UNDEAD_ROSTER.get(String(attacker.get("job", "")), {}).get("infects_on_hit", false)):
		return false
	if String(target.get("faction", "")) == "undead":
		return false
	if target.has("infected"):
		return false
	if randf() < MELEE_INFECT_CHANCE:
		infect_unit(target, String(attacker.get("job", "")))
		return true
	return false


## The turned rise as zombies (HTML window.turnUndead61), remembering their
## original faction for faction-variant art.
func turn_undead(u: Dictionary) -> void:
	if u.is_empty() or not u.get("alive", false):
		return
	if String(u.get("faction", "")) == "undead":
		u.erase("infected")
		return
	u.erase("infected")
	if not u.has("turned_from"):
		u["turned_from"] = String(u.get("faction", ""))
	u["faction"] = "undead"
	u["job"] = "zombie"
	u["is_worker"] = false
	u.erase("combat_target")
	apply_undead_stats(u)


## ---- per-tick ----------------------------------------------------------------
## R20 perf: the whole tick (corpse decay, plague-cloud nested scans, flesh
## farms, per-unit infection/ghoul/zombie/hunt) runs every 3rd physics frame
## (20 Hz) with delta*3.0 — the R15/R17/R19 proven pattern. Linear timers are
## bit-exact under the scaling; per-second RNG rolls go through _roll() for
## exact 3-frame probability compounding; movement averages identical
## (coarser 3x steps, same as the R19 family sweep).
func tick(delta: float) -> void:
	_tick_frame += 1
	if _tick_frame % 3 != 0:
		return
	_tick_full(delta * 3.0)


## Compounds a per-second roll rate over the 3 skipped frames exactly:
## P(>=1 success in 3 frames) for per-frame p = rate * step / 3.
func _roll(rate: float, step: float) -> bool:
	return randf() < 1.0 - pow(1.0 - rate * step / 3.0, 3.0)


func _tick_full(delta: float) -> void:
	_tick_corpses(delta)
	_tick_plague(delta)
	_tick_flesh_farms(delta)
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		_tick_infection(u, delta)
		var job: String = String(u.get("job", ""))
		var undead: bool = String(u.get("faction", "")) == "undead"
		if undead and job == "ghoul":
			_tick_ghoul(u, delta)
		if undead and job == "necromancer":
			u["raise_cd"] = maxf(0.0, float(u.get("raise_cd", 0.0)) - delta)
			if float(u.get("raise_cd", 0.0)) <= 0.0 and _roll(0.5, delta):
				try_necro_raise(u)
		if undead and job == "zombie":
			_tick_zombie(u, delta)
		if undead and job in HUNT_JOBS:
			_tick_hunt(u, delta)


func _tick_corpses(delta: float) -> void:
	for i: int in range(corpses.size() - 1, -1, -1):
		corpses[i]["t"] = float(corpses[i]["t"]) - delta
		if float(corpses[i]["t"]) <= 0.0:
			corpses.remove_at(i)


func _tick_plague(delta: float) -> void:
	for i: int in range(plague_clouds.size() - 1, -1, -1):
		var cl: Dictionary = plague_clouds[i]
		cl["t"] = float(cl["t"]) - delta
		if float(cl["t"]) <= 0.0:
			plague_clouds.remove_at(i)
			continue
		var cpos := Vector2(float(cl["x"]), float(cl["y"]))
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			if String(u.get("faction", "")) == "undead":
				continue
			if u.has("infected"):
				continue
			if cpos.distance_to(u.get("position", Vector2.ZERO)) > PLAGUE_RADIUS:
				continue
			if _roll(PLAGUE_INFECT_RATE, delta):
				infect_unit(u, "plague")


## Infection: incubate, spread to nearby living, turn after 25 s (HTML unitTick61).
func _tick_infection(u: Dictionary, delta: float) -> void:
	if not u.has("infected"):
		return
	if String(u.get("faction", "")) == "undead":
		u.erase("infected")
		return
	var inf: Dictionary = u["infected"]
	inf["t"] = float(inf.get("t", 0.0)) + delta
	u["infected"] = inf
	# Spread: nearby living can catch it.
	if _roll(INFECT_SPREAD_RATE, delta):
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		for o: Dictionary in _gs.units:
			if o == u or not o.get("alive", false):
				continue
			if String(o.get("faction", "")) == "undead":
				continue
			if o.has("infected"):
				continue
			if upos.distance_to(o.get("position", Vector2.ZERO)) > INFECT_SPREAD_RADIUS:
				continue
			if randf() < INFECT_SPREAD_CHANCE:
				infect_unit(o, "spread")
				break
	if float(inf.get("t", 0.0)) >= INFECT_TURN_TIME:
		turn_undead(u)


## Ghouls feed on corpses to heal (HTML ghoulFeed61): +35 hp within 45 px,
## otherwise drift toward the nearest corpse within 500 px when idle.
func _tick_ghoul(u: Dictionary, delta: float) -> void:
	if float(u.get("hp", 0.0)) >= float(u.get("max_hp", 0.0)):
		return
	if corpses.is_empty():
		return
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var bi: int = -1
	var best_d2: float = INF
	for i: int in corpses.size():
		var c: Dictionary = corpses[i]
		var d2: float = upos.distance_squared_to(Vector2(c["x"], c["y"]))
		if d2 < best_d2:
			best_d2 = d2
			bi = i
	if bi < 0:
		return
	var d: float = sqrt(best_d2)
	if d < GHOUL_FEED_RANGE:
		corpses.remove_at(bi)
		u["hp"] = minf(float(u.get("max_hp", 0.0)),
			float(u.get("hp", 0.0)) + GHOUL_HEAL)
	elif d < GHOUL_SEEK_RANGE and int(u.get("combat_target", -1)) < 0:
		var c: Dictionary = corpses[bi]
		_move_toward(u, Vector2(float(c["x"]), float(c["y"])),
			float(UNDEAD_ROSTER["ghoul"]["speed"]), delta)


## Zombie hunger (HTML zombieTick62): drains over ~4 min; starving zombies
## weaken; below 8 they can go feral and attack anyone; the fed seek flesh
## farms with meat.
func _tick_zombie(u: Dictionary, delta: float) -> void:
	if not u.has("zhunger"):
		u["zhunger"] = 60.0 + randf() * 25.0
	u["zhunger"] = maxf(0.0, float(u.get("zhunger")) - delta * HUNGER_DRAIN_PER_S)
	var zh: float = float(u.get("zhunger"))
	# Starvation penalties — the weakened shamble.
	if zh < 20.0:
		if not u.has("_zh_base"):
			u["_zh_base"] = {"dmg": float(u.get("dmg", 8.0)),
				"speed": float(u.get("speed", 57.0))}
		var base: Dictionary = u["_zh_base"]
		u["dmg"] = float(base["dmg"]) * 0.6
		u["speed"] = float(base["speed"]) * 0.75
	elif u.has("_zh_base"):
		var base2: Dictionary = u["_zh_base"]
		u["dmg"] = float(base2["dmg"])
		u["speed"] = float(base2["speed"])
		u.erase("_zh_base")
	# Critical hunger can turn a zombie feral — it attacks ANYONE nearby.
	if not bool(u.get("feral", false)) and zh < 8.0 and _roll(0.25, delta):
		u["feral"] = true
	if bool(u.get("feral", false)):
		_tick_feral(u, delta)
		if zh >= 40.0:
			u["feral"] = false
	elif zh < 55.0:
		_tick_zombie_feed(u, delta)


func _tick_feral(u: Dictionary, delta: float) -> void:
	u["feral_cd"] = float(u.get("feral_cd", 0.0)) - delta
	if float(u.get("feral_cd", 0.0)) > 0.0:
		return
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2: float = FERAL_RANGE * FERAL_RANGE
	for o: Dictionary in _gs.units:
		if o == u or not o.get("alive", false):
			continue
		var d2: float = upos.distance_squared_to(o.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = o
	if best.is_empty():
		return
	var d: float = sqrt(best_d2)
	if d > FERAL_ATTACK_DIST:
		_move_toward(u, best.get("position", Vector2.ZERO),
			float(u.get("speed", 57.0)), delta)
		return
	u["feral_cd"] = FERAL_ATTACK_CD
	if _combat != null:
		_combat.damage_unit(int(best.get("id", -1)), float(u.get("dmg", 8.0)),
			"undead", int(u.get("id", -1)))


## Idle-animal hunt (HTML undeadHuntTick62 parity). Non-feral zombie/ghoul/
## skeleton with no orders chases the nearest wild animal within HUNT_RANGE;
## beyond HUNT_ATTACK_DIST it walks there, inside it it mauls every
## HUNT_ATTACK_CD s. HTML priority note: in HTML the zombie feed-seek and
## ghoul corpse-feed ticks run BEFORE the hunt tick and set moveTarget, so
## feeding always owns a hungry/injured unit; Godot's feed ticks move units
## directly, so their triggers are checked here instead (same outcome).
func _tick_hunt(u: Dictionary, delta: float) -> void:
	if bool(u.get("feral", false)):
		return  # feral units are owned by _tick_feral
	if int(u.get("combat_target", -1)) >= 0:
		return  # has a fight target (HTML u.target)
	if u.get("move_target", null) != null:
		return  # has army/muster orders (HTML u.moveTarget)
	var job: String = String(u.get("job", ""))
	if job == "zombie" and float(u.get("zhunger", 100.0)) < 55.0:
		return  # feed-seek owns hungry zombies (HTML sets moveTarget first)
	if job == "ghoul" and float(u.get("hp", 0.0)) < float(u.get("max_hp", 0.0)) \
			and not corpses.is_empty():
		return  # corpse-feed owns injured ghouls (HTML sets moveTarget first)
	var animals = _gs.get("animals")
	if animals == null:
		return
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = animals.nearest_wild(upos, HUNT_RANGE)
	if best.is_empty():
		return
	u["_hunt_cd"] = float(u.get("_hunt_cd", 0.0)) - delta
	var d: float = upos.distance_to(best.get("position", upos))
	if d > HUNT_ATTACK_DIST:
		_move_toward(u, best.get("position", upos),
			float(u.get("speed", 57.0)), delta)
		return
	if float(u.get("_hunt_cd", 0.0)) > 0.0:
		return
	u["_hunt_cd"] = HUNT_ATTACK_CD
	animals.damage_wild(best, float(u.get("dmg", 8.0)))
## Fed zombies seek flesh farms with meat (HTML zombieFeedSeek62).
func _tick_zombie_feed(u: Dictionary, delta: float) -> void:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d2: float = HUNGER_FEED_SEEK * HUNGER_FEED_SEEK
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) != "flesh_farm":
			continue
		if not bool(b.get("alive", true)) or not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != String(u.get("faction", "")):
			continue
		if int(b.get("meat", 0)) <= 0:
			continue
		var d2: float = upos.distance_squared_to(b.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = b
	if best.is_empty():
		return
	if sqrt(best_d2) > HUNGER_FEED_DIST:
		_move_toward(u, best.get("position", Vector2.ZERO),
			float(u.get("speed", 57.0)), delta)
		return
	best["meat"] = int(best.get("meat", 0)) - 1
	u["zhunger"] = minf(100.0, float(u.get("zhunger", 0.0)) + HUNGER_FEED_AMOUNT)


## Flesh farms haul nearby corpses into meat (HTML fleshTick62): prefers
## animal corpses, stock caps at 12.
func _tick_flesh_farms(_delta: float) -> void:
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) != "flesh_farm":
			continue
		if not bool(b.get("alive", true)) or not bool(b.get("complete", false)):
			continue
		var meat: int = int(b.get("meat", 0))
		if meat >= FLESH_FARM_MEAT_MAX:
			continue
		if corpses.is_empty():
			continue
		var bpos: Vector2 = b.get("position", Vector2.ZERO)
		var best: int = -1
		var best_d2: float = FLESH_FARM_PULL_RADIUS * FLESH_FARM_PULL_RADIUS
		var best_animal: int = -1
		var best_animal_d2: float = FLESH_FARM_PULL_RADIUS * FLESH_FARM_PULL_RADIUS
		for i: int in corpses.size():
			var c: Dictionary = corpses[i]
			var d2: float = bpos.distance_squared_to(Vector2(c["x"], c["y"]))
			if String(c.get("race", "")) == "animal" and d2 < best_animal_d2:
				best_animal_d2 = d2
				best_animal = i
			if d2 < best_d2:
				best_d2 = d2
				best = i
		var pick: int = best_animal if best_animal >= 0 \
			else (best if meat < 2 and best >= 0 else -1)
		if pick < 0:
			continue
		corpses.remove_at(pick)
		b["meat"] = meat + 1


## ---- roster stats ------------------------------------------------------------

## Applies the HTML Unit job-branch multipliers to a spawned unit record.
## Base hp/dmg come from the record (spawner sets undead race hp 220);
## base dmg falls back to the soldier's 15.
func apply_undead_stats(unit: Dictionary) -> void:
	var r: Dictionary = UNDEAD_ROSTER.get(String(unit.get("job", "")), {})
	if r.is_empty():
		return
	var hp: float = floor(float(unit.get("hp", 220.0)) * float(r.get("hp_mul", 1.0)))
	unit["hp"] = hp
	unit["max_hp"] = hp
	unit["dmg"] = floor(float(unit.get("dmg", 15.0)) * float(r.get("dmg_mul", 1.0)))
	unit["speed"] = float(r.get("speed", 90.0))
	unit["attack_rate"] = float(r.get("attack_rate", 0.8))
	if r.has("range"):
		unit["range"] = float(r["range"])
	elif r.has("range_bonus"):
		unit["range_bonus"] = float(r["range_bonus"])
	for flag: String in ["siege", "life_drain", "ignore_wall_slow", "infects_on_hit"]:
		if r.has(flag):
			unit[flag] = r[flag]
	if r.has("splash"):
		unit["splash"] = float(r["splash"])
		unit["splash_mul"] = float(r.get("splash_mul", 1.0))


func _move_toward(u: Dictionary, target_pos: Vector2, speed: float,
		delta: float) -> void:
	var p: Vector2 = u.get("position", Vector2.ZERO)
	var to: Vector2 = target_pos - p
	var dist: float = to.length()
	if dist < 4.0:
		return
	# Jeremy 2026-10-05: water rules — avoid unless fleeing.
	var mstep: Vector2 = to.normalized() * minf(speed * delta, dist)
	var mnp: Vector2 = p + mstep
	if WaterNav.unit_avoids_water(u):
		mnp = WaterNav.dry_step(_gs.map_data, p, mstep)
	u["position"] = mnp
	u["swimming"] = WaterNav.is_water_at(_gs.map_data, mnp)


## ---- save/load ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"corpses": corpses.duplicate(true),
		"plague_clouds": plague_clouds.duplicate(true),
		"soul": _soul.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	corpses.clear()
	for c in data.get("corpses", []):
		corpses.append((c as Dictionary).duplicate(true))
	plague_clouds.clear()
	for p in data.get("plague_clouds", []):
		plague_clouds.append((p as Dictionary).duplicate(true))
	_soul = (data.get("soul", {}) as Dictionary).duplicate(true)
	for f: String in _soul.keys():
		_mirror_ledger(f)
