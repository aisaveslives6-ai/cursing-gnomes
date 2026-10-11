class_name SimAnimals
extends RefCounted
## Cursing Gnomes — farm animals (Milestone 6b: world & environment / economy).
##
## Ports the HTML build's Stage-8 farm-animal chain (not its code):
##   - ANIMAL_TYPES registry: boar (legacy wild), chicken, cow, pig, sheep,
##     goat. Type ids are stable; hp = round((25 + rand*20) * hpMul).
##   - Housing: a completed barn or coop of the plot's faction within 600px
##     attaches to the farm plot (HTML s8FarmTick attach pass); when a barn
##     finishes, livestock move in — barn -> cow+pig, coop -> chicken+chicken,
##     a second barn of the same faction -> goat+sheep (HTML
##     s8StockFarmAnimals). Max 8 animals per plot; one-time per building.
##   - Feeding: every new day the farm feeds its animals (hunger = 90,
##     HTML s8FarmNewDay) at no resource cost. Between feedings hunger decays
##     at 1.1/s (HTML Animal.update); starving animals (hunger <= 0) lose
##     4 hp/s and die; corpses join the undead corpse system as race "animal"
##     (HTML animalDeath62; flesh farms prefer them).
##   - Produce: each living animal yields food into the faction ledger once
##     per day — chicken 6, cow 14, pig 10, sheep 8, goat 10, boar 0
##     (HTML S8_ANIMAL_YIELD, addRes(race, 0, 0, total, 0)).
##   - Leash: animals straying farther than 260px from their barn/coop
##     (else the plot center) wander back (HTML s8FarmTick leash).
##   - Save: animal records live inside the farm plot dict ("animals"),
##     so farming's to_dict/from_dict round-trips them automatically.
##
## Gaps vs HTML (documented, not invented):
##   - No breeding and no slaughter — the HTML has neither for farm
##     animals (the ANIMAL_TYPES "food" stat exists in the registry but no
##     HTML code consumes it; death only comes from starvation/combat).
##   - Products are generic "food" — HTML has no milk/eggs/wool resources.
##   - Barn/coop are buildable types (buildings.gd) and the auto-stock
##     attach path is LIVE: _attach_housing() runs in tick(), gated to
##     building-count changes + a 2s backstop (no-op for housed plots).
##
## Animal record: {id, type, position: Vector2, hunger, hp, max_hp, alive}.
## Plot additions: animals: Array, barn_bld: int (-1), coop_bld: int (-1).
## Pure logic — no rendering, no input, no audio.


## HTML ANIMAL_TYPES (verbatim stats).
const ANIMAL_TYPES := {
	"boar":    {"label": "Wild Boar", "hp_mul": 1.0, "speed_mul": 1.0,
		"size": 12.0, "draw_w": 46.0, "food": 4.0, "water_liking": false},
	"chicken": {"label": "Chicken",   "hp_mul": 0.3, "speed_mul": 1.5,
		"size": 7.0,  "draw_w": 26.0, "food": 2.0, "water_liking": false},
	"cow":     {"label": "Cow",       "hp_mul": 1.8, "speed_mul": 0.75,
		"size": 16.0, "draw_w": 58.0, "food": 8.0, "water_liking": false},
	"pig":     {"label": "Pig",       "hp_mul": 1.2, "speed_mul": 0.9,
		"size": 13.0, "draw_w": 44.0, "food": 6.0, "water_liking": false},
	"sheep":   {"label": "Sheep",     "hp_mul": 1.0, "speed_mul": 0.95,
		"size": 12.0, "draw_w": 44.0, "food": 4.0, "water_liking": false},
	"goat":    {"label": "Goat",      "hp_mul": 1.1, "speed_mul": 1.1,
		"size": 12.0, "draw_w": 44.0, "food": 5.0, "water_liking": false},
	"wolf":    {"label": "Wolf",      "hp_mul": 1.3, "speed_mul": 1.6,
		"size": 13.0, "draw_w": 48.0, "food": 6.0, "water_liking": false},
	"cat":     {"label": "Cat",       "hp_mul": 0.35, "speed_mul": 1.7,
		"size": 6.0,  "draw_w": 30.0, "food": 1.0, "water_liking": false},
}
## Predators hunt these prey types (HTML: wolves vs livestock/wildlife).
const PREDATORS := {"wolf": ["sheep", "chicken", "goat", "pig", "boar", "cat"]}
## Pet cats (Jeremy 2026-10-07 — NPC life deep pass). Stray cats spawn near
## towns; a stray "chooses" a nearby civilian and becomes their pet: it
## follows them, purrs (social/mood urge lift for the owner in radius),
## and eats 1 food/day from the owner's faction stockpile. Pets are never
## hunted by hunters/undead (nearest_wild skips them); wolves may still
## take them — a dead pet genuinely grieves its owner. Pet records carry:
##   pet: true, owner_id: int, pet_name: String, faction: String.
const CATS_PER_TOWN := 2            # strays seeded near each town center
const CAT_SPAWN_MIN_D := 150.0      # stray spawn ring around town center
const CAT_SPAWN_MAX_D := 350.0
const ADOPT_RADIUS := 420.0         # stray looks for a human this far out
const PET_FOLLOW_R := 110.0         # pet trots to owner past this distance
const PET_TELEPORT_R := 700.0       # past this, the cat "finds" its human
const PET_AURA_R := 170.0           # purring radius: owner urge lift
const PET_AURA_SOCIAL := 6.0        # +social urge per second in aura
const PET_AURA_MOOD := 4.0          # +mood urge per second in aura
const PET_GRIEF_MOOD := 45.0        # mood-urge hit when a pet dies
const PET_FOOD_PER_DAY := 1.0       # food eaten daily from faction stockpile
## Cat names. "Prancey" first — Jeremy's actual cat, inherited from his
## mother with her 29 others. The rest are the game's usual nonsense.
const CAT_NAMES: Array[String] = [
	"Prancey", "Chairman Meow", "Sir Pounce", "Beans", "Tofu",
	"Waffles", "Noodle", "Pickles", "Ziggy", "Miso", "Biscuit",
	"Gouda", "Pepper", "Socks", "Shadow", "Luna", "Mittens",
	"Whiskers", "Tuna", "Kevin", "Greg", "Baron von Fluff",
	"Captain Hairball", "Duchess", "Marmalade", "Pudding", "Sushi",
	"Wasabi", "Bagel", "Pretzel", "Cheddar", "Asscat",
]
## Wildlife tuning (HTML worldgen: 80 boars scattered, +6 near each town,
## respawn when below 40).
const WILD_SPAWN_COUNT := 80
const WILD_RESPAWN_FLOOR := 40
const WILD_RESPAWN_CHANCE := 0.02
const WILD_WANDER_RADIUS := 180.0
const WILD_FEAR_RADIUS := 70.0
const WOLF_HUNT_RADIUS := 300.0
const WOLF_ATTACK_RANGE := 24.0
const WOLF_ATTACK_DMG := 6.0
const WOLF_ATTACK_CD := 1.2
## Jeremy 2026-10-05: prey runs when a wolf is this close (the wolf hunts
## from 300px, but the boar only notices the danger up close — then it
## RUNS, it doesn't trot).
const WOLF_FEAR_RADIUS := 150.0
## Flee sprint multiplier while running from a wolf (vs the 1.5x fear trot).
const FLEE_RUN_MULT := 2.0
## HTML S8_ANIMAL_YIELD: food per animal per day.
const DAILY_YIELD := {
	"chicken": 6.0, "cow": 14.0, "pig": 10.0,
	"sheep": 8.0, "goat": 10.0, "boar": 0.0,
}
const MAX_PER_PLOT := 8            # HTML: farm.animalIds.length >= 8 cap
const HOUSING_RANGE := 600.0       # HTML: barn/coop attach < 600px
const LEASH_RANGE := 260.0         # HTML: leash pulls past 260px
const LEASH_WANDER_RADIUS := 160.0 # HTML: moveTarget jitter (rand-0.5)*160
const LEASH_SPEED := 30.0          # px/s, scaled by the type's speed_mul
const HUNGER_DECAY := 1.1         # HTML: hunger -= dt * 1.1
const STARVE_DMG := 4.0           # HTML: hp -= dt * 4 when hunger <= 0
const FEED_HUNGER := 90.0         # HTML: an.hunger = 90 each new day
const NO_BUILDING := -1


var _gs: GameState
var _next_animal_id: int = 1
var _last_day: int = 1
var _rng := RandomNumberGenerator.new()
## Wild animals: not attached to any farm plot. Records carry the same
## fields as farm animals plus "wild": true and "fear": float.
var wild: Array[Dictionary] = []
## Map bounds for wildlife respawn (set by seed_wildlife).
var _wild_bounds := Rect2(0, 0, 4000, 4000)

## --- Perf: spatial neighbor grids (2026-10-04) ---
## _nearest_unit_threat() was an O(wild x units) full scan every physics
## frame (up to 40 wild x 240 units x 60Hz of Dictionary-heavy iteration —
## the single hottest sim cost, ~4ms/tick on desktop, far worse under
## iPhone Safari's WASM GDScript). These coarse grids replaced the scans;
## since 2026-10-05 they rebuild every 3rd tick (20Hz) and the herd thinks
## round-robin at the same cadence (Jeremy: "evenly distribute the
## cycles"). Cell sizes still exceed their query radii, and a 2-tick-stale
## snapshot drifts ~3px at animal speeds — far below the 70px fear / 300px
## hunt radii — so flee/hunt decisions are behaviorally unchanged. Radii,
## thresholds, and the flee/hunt decisions are untouched (HTML parity).
const GRID_UNIT := 128.0   # > WILD_FEAR_RADIUS (70)
const GRID_PREY := 320.0   # > WOLF_HUNT_RADIUS (300)
## Cell key -> Array of Vector3(x, y, unit_index). The stored index breaks
## distance ties exactly like the old first-in-units-order scan.
var _unit_grid: Dictionary = {}
## Cell key -> Array of [animal_dict, order]. Order = wild-array order,
## then livestock order, reproducing the old wild-first scan exactly.
var _prey_grid: Dictionary = {}
## Jeremy 2026-10-05: wolf grid — Cell key -> Array of wolf animal dicts
## (wild only). Lets prey check "is a wolf hunting me nearby" without an
## O(prey x wolves) scan. Rebuilt in the same 20Hz gate as the other grids.
var _wolf_grid: Dictionary = {}
const GRID_WOLF := 320.0   # > WOLF_FEAR_RADIUS (150)
## Housing attach gate: _attach_housing() scanned EVERY building for EVERY
## plot EVERY tick. Barns/coops only appear when built, so rescan only
## when the building count changes (same-frame attach as before) or every
## HOUSING_RESCAN_TICKS as a backstop for same-count build+destroy swaps.
## Plots with both slots filled skip the scan entirely (provable no-op).
var _housing_bcount := -1
var _housing_tick := 0
const HOUSING_RESCAN_TICKS := 120  # 2s backstop


func _init(game_state: GameState) -> void:
	_gs = game_state
	_rng.randomize()


## Clears animal state. Called by World._ready on new game.
func reset() -> void:
	_next_animal_id = 1
	_last_day = _gs.day_number if _gs.day_number >= 1 else 1
	wild.clear()


## Jeremy 2026-10-05 (Oblivion/Skyrim-style water rules): O(1) water check
## against the baked terrain, plus the shared "step toward target"
## mover used by livestock, wildlife, and wolf hunts. Movers that must
## avoid water slide along the shoreline instead of stopping dead;
## swimmers move at SWIM_SPEED_MULT.
const SWIM_SPEED_MULT := 0.55


func _water_at(pos: Vector2) -> bool:
	if _gs == null:
		return false
	return WaterNav.is_water_at(_gs.map_data, pos)


## Move an animal toward its target by up to step px, steering around
## water unless may_swim. Updates position + swimming flag. Returns true
## when the target was reached.
func _step_toward(an: Dictionary, pos: Vector2, tgt: Vector2,
		step: float, may_swim: bool) -> bool:
	var d: Vector2 = tgt - pos
	if d.length() <= step:
		# Don't teleport onto a water tile we must avoid — drop the
		# target and pick a new one next tick.
		if not may_swim and _water_at(tgt):
			an.erase("move_target")
			return false
		an["position"] = tgt
		an.erase("move_target")
		an["swimming"] = _water_at(tgt)
		return true
	var mv: Vector2 = d.normalized() * step
	var np: Vector2 = pos + mv
	if not may_swim:
		np = WaterNav.dry_step(_gs.map_data, pos, mv)
	an["position"] = np
	an["swimming"] = _water_at(np)
	return false


## Makes sure a plot dict carries the animal fields (old saves / hand-made
## plots lack them).
func _ensure_plot(plot: Dictionary) -> void:
	if not plot.has("animals"):
		plot["animals"] = []
	if not plot.has("barn_bld"):
		plot["barn_bld"] = NO_BUILDING
	if not plot.has("coop_bld"):
		plot["coop_bld"] = NO_BUILDING


## All farm plots known to the farming system.
func _plots() -> Array:
	var f = _gs.get("farming")
	if f == null:
		return []
	return f.plots


## Adds one animal of a type to a plot (HTML spawnAnimalType + farm push).
## hp = round((25 + rand*20) * hpMul); hunger starts 50+rand*40 (HTML Animal).
func add_animal(plot: Dictionary, type: String, pos: Vector2) -> Dictionary:
	if plot.is_empty():
		return {}
	var t: String = type if ANIMAL_TYPES.has(type) else "boar"
	_ensure_plot(plot)
	var herd: Array = plot["animals"]
	if herd.size() >= MAX_PER_PLOT:
		return {}
	var st: Dictionary = ANIMAL_TYPES[t]
	var hp: float = roundf((25.0 + _rng.randf() * 20.0) * float(st["hp_mul"]))
	var an: Dictionary = {
		"id": _next_animal_id,
		"type": t,
		"position": pos,
		"hunger": 50.0 + _rng.randf() * 40.0,
		"hp": hp,
		"max_hp": hp,
		"alive": true,
	}
	_next_animal_id += 1
	herd.append(an)
	return an


## Stocks a plot with a list of animal kinds (HTML s8StockFarmAnimals loop).
## Respects the 8-per-plot cap; animals spawn near the given building pos.
func stock_plot(plot: Dictionary, kinds: Array, near: Vector2) -> Array:
	var added: Array = []
	for k in kinds:
		var an: Dictionary = add_animal(plot, String(k),
			near + Vector2(_rng.randf_range(-45.0, 45.0),
				_rng.randf_range(-45.0, 45.0)))
		if not an.is_empty():
			added.append(an)
	return added


## Living animals on a plot.
func herd_of(plot: Dictionary) -> Array:
	_ensure_plot(plot)
	var out: Array = []
	for an in plot["animals"]:
		if an is Dictionary and bool(an.get("alive", false)):
			out.append(an)
	return out


## Finds a building record by id. R26 perf: O(1) via the GameState id
## index (the old linear scan ran twice per plot per tick inside _anchor).
func _building(bid: int) -> Dictionary:
	if bid == NO_BUILDING:
		return {}
	return _gs.get_building(bid)


## Anchor the herd leashes to: attached barn/coop position (if the building
## is still alive), else the plot center (HTML s8FarmTick anchor).
func _anchor(plot: Dictionary) -> Vector2:
	for key in ["barn_bld", "coop_bld"]:
		var b: Dictionary = _building(int(plot.get(key, NO_BUILDING)))
		if not b.is_empty() and bool(b.get("alive", false)):
			return b.get("position", plot.get("position", Vector2.ZERO))
	return plot.get("position", Vector2.ZERO)


## Attach pass (HTML s8FarmTick): completed barn/coop buildings of the
## plot's faction within 600px attach; a newly attached building stocks
## its animals once. Barn -> cow+pig; coop -> chicken+chicken; a second
## barn of the same faction -> goat+sheep (HTML barnCount > 1).
func _attach_housing(plot: Dictionary) -> void:
	var faction: String = String(plot.get("faction", ""))
	var ppos: Vector2 = plot.get("position", Vector2.ZERO)
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var kind: String = String(b.get("type", ""))
		var key: String = ""
		if kind == "barn":
			key = "barn_bld"
		elif kind == "coop":
			key = "coop_bld"
		else:
			continue
		if int(plot.get(key, NO_BUILDING)) != NO_BUILDING:
			continue
		var bpos: Vector2 = b.get("position", Vector2.ZERO)
		if ppos.distance_to(bpos) > HOUSING_RANGE:
			continue
		plot[key] = int(b.get("id", NO_BUILDING))
		b["_farm_plot_id"] = int(plot.get("id", 0))
		if not bool(b.get("_stocked", false)):
			b["_stocked"] = true
			var types: Array = ["cow", "pig"] if kind == "barn" \
				else ["chicken", "chicken"]
			if kind == "barn" and _barn_count(faction) > 1:
				types = ["goat", "sheep"]
			var added: Array = stock_plot(plot, types, bpos)
			if not added.is_empty() \
					and _gs.bus.has_signal("animals_stocked"):
				_gs.bus.animals_stocked.emit(int(plot.get("id", 0)),
					kind, _kinds_of(added))


## Barns of a faction that are attached and alive across all plots
## (HTML barnCount).
func _barn_count(faction: String) -> int:
	var n := 0
	for p in _plots():
		if not (p is Dictionary):
			continue
		if String(p.get("faction", "")) != faction:
			continue
		var b: Dictionary = _building(int(p.get("barn_bld", NO_BUILDING)))
		if not b.is_empty() and bool(b.get("alive", false)):
			n += 1
	return n


func _kinds_of(herd: Array) -> Array:
	var out: Array = []
	for an in herd:
		out.append(String(an.get("type", "")))
	return out


## Removes dead animals from a plot's herd (HTML splice pass).
func _purge_dead(plot: Dictionary) -> void:
	var herd: Array = plot.get("animals", [])
	for i in range(herd.size() - 1, -1, -1):
		var an = herd[i]
		if not (an is Dictionary) or not bool(an.get("alive", false)):
			herd.remove_at(i)


## Kills an animal: marks dead, leaves a corpse for the undead corpse
## system (HTML animalDeath62 — flesh farms prefer race "animal").
func _kill(plot: Dictionary, an: Dictionary, cause: String) -> void:
	if not bool(an.get("alive", false)):
		return
	an["alive"] = false
	an["hp"] = 0.0
	var ud = _gs.get("undead")
	if ud != null:
		var corpses: Array = ud.corpses
		if corpses.size() < SimUndead.MAX_CORPSES:
			var pos: Vector2 = an.get("position", Vector2.ZERO)
			corpses.append({
				"x": pos.x, "y": pos.y,
				"race": "animal",
				"job": String(an.get("type", "")),
				"t": SimUndead.CORPSE_LIFETIME,
			})
	if _gs.bus.has_signal("animal_died"):
		_gs.bus.animal_died.emit(int(plot.get("id", 0)), int(an.get("id", 0)), cause, String(an.get("type", "")))


## Per-tick: hunger decay, starvation, leashing, housing attach, and the
## once-per-day feed + yield pass (HTML s8FarmTick + Animal.update).
func tick(delta: float) -> void:
	var plots: Array = _plots()
	# Housing scan gate (perf): only rescan buildings when the count
	# changed or the backstop elapsed; fully-housed plots never rescan.
	_housing_tick += 1
	var bcount := _gs.buildings.size()
	var do_housing := bcount != _housing_bcount \
		or _housing_tick >= HOUSING_RESCAN_TICKS
	if do_housing:
		_housing_bcount = bcount
		_housing_tick = 0
	for p in plots:
		if not (p is Dictionary):
			continue
		var plot: Dictionary = p
		_ensure_plot(plot)
		if do_housing or not _housing_complete(plot):
			_attach_housing(plot)
	# R26 perf: livestock needs/wander (hunger, leash, movement, purge) run
	# round-robin at 20Hz — 1/3 of plots per physics tick, delta x3. Every
	# term is linear in delta, so the simulation is unchanged; cycles spread
	# evenly instead of piling into one frame (Jeremy 2026-10-05: "evenly
	# distribute the cycles"). The housing attach above stays per-tick: it
	# is already gated to a no-op for complete plots.
	_tick_livestock(plots, delta)
	if _gs.day_number != _last_day:
		_last_day = _gs.day_number
		_new_day(plots)
	# Neighbor grids: one O(units + animals) build replaces the old
	# per-animal O(n) full scans below.
	# Jeremy 2026-10-05 perf: rebuilt every 3rd physics tick (20Hz), not
	# every tick. The grids only serve the wild-animal brain — a 2-tick-old
	# snapshot drifts ~3px at animal speeds, far below the 70px fear and
	# 300px hunt radii, so flee/hunt decisions are unaffected.
	_wild_frame += 1
	if _wild_frame >= WILD_TICK_EVERY:
		_wild_frame = 0
		_rebuild_unit_grid()
		_rebuild_prey_grid()
		_rebuild_wolf_grid()
	# Wildlife roam free (round-robin sliced at 20Hz — see _tick_wild_all).
	_tick_wild_all(delta)


## Both housing slots filled: _attach_housing() is a provable no-op for
## this plot (every building hits the `continue`), so skip the scan.
func _housing_complete(plot: Dictionary) -> bool:
	return int(plot.get("barn_bld", NO_BUILDING)) != NO_BUILDING \
		and int(plot.get("coop_bld", NO_BUILDING)) != NO_BUILDING


## R26 perf: livestock tick cadence. Plots are dealt into 3 slots by array
## index; each physics tick processes exactly one slot with delta x3, so
## every plot is simulated exactly once per 3 ticks however many plots
## exist (no small-n speedup bug), and the per-frame cost stays flat.
const PLOT_TICK_EVERY := 3
var _plot_frame := 0  # ephemeral (not saved)


func _tick_livestock(plots: Array, delta: float) -> void:
	_plot_frame += 1
	var slot := _plot_frame % PLOT_TICK_EVERY
	var scaled: float = delta * PLOT_TICK_EVERY
	var idx := 0
	for p in plots:
		if idx % PLOT_TICK_EVERY == slot and p is Dictionary:
			var plot: Dictionary = p
			_purge_dead(plot)
			var anchor: Vector2 = _anchor(plot)
			for an in plot.get("animals", []):
				if an is Dictionary:
					_tick_animal(plot, an, anchor, scaled)
		idx += 1


## Coarse cell key for a world position.
static func _cell_key(pos: Vector2, cell: float) -> Vector2i:
	return Vector2i(floori(pos.x / cell), floori(pos.y / cell))


## Snapshot of alive unit positions, rebuilt once per tick. Cell 128px >
## the 70px fear radius, so the 3x3 query neighborhood always contains
## every unit the old full scan could have picked. Identical results.
func _rebuild_unit_grid() -> void:
	_unit_grid.clear()
	var idx := 0
	for u in _gs.units:
		if u is Dictionary and bool(u.get("alive", true)):
			var up: Vector2 = u.get("position", Vector2.INF)
			if up != Vector2.INF:
				var cell := _cell_key(up, GRID_UNIT)
				var arr: Array = _unit_grid.get(cell, [])
				arr.append(Vector3(up.x, up.y, float(idx)))
				_unit_grid[cell] = arr
		idx += 1


## Snapshot of huntable prey (wild in wild-array order, then livestock in
## plot/animal order), rebuilt once per tick. Cell 320px > the 300px hunt
## radius: the 3x3 neighborhood is exact. The stored order reproduces the
## old scan's wild-beats-livestock tie behavior.
func _rebuild_prey_grid() -> void:
	_prey_grid.clear()
	var prey_types: Array = PREDATORS.get("wolf", [])
	var order := 0
	for an in wild:
		if an is Dictionary and bool(an.get("alive", false)) \
				and String(an.get("type", "")) in prey_types:
			_prey_add(an, order)
			order += 1
	for p in _plots():
		if not (p is Dictionary):
			continue
		for an in p.get("animals", []):
			if an is Dictionary and bool(an.get("alive", false)) \
					and String(an.get("type", "")) in prey_types:
				_prey_add(an, order)
				order += 1


func _prey_add(an: Dictionary, order: int) -> void:
	var cell := _cell_key(an.get("position", Vector2.ZERO), GRID_PREY)
	var arr: Array = _prey_grid.get(cell, [])
	arr.append([an, order])
	_prey_grid[cell] = arr


## Rebuild the wolf-position grid (wild wolves only). Same 20Hz gate as
## the prey grid; a 2-tick-stale snapshot drifts ~3px at wolf speeds —
## far below the 150px fear radius.
func _rebuild_wolf_grid() -> void:
	_wolf_grid.clear()
	for an in wild:
		if an is Dictionary and bool(an.get("alive", false)) \
				and String(an.get("type", "")) == "wolf":
			var cell := _cell_key(an.get("position", Vector2.ZERO),
				GRID_WOLF)
			var arr: Array = _wolf_grid.get(cell, [])
			arr.append(an)
			_wolf_grid[cell] = arr


## Nearest live wolf to a position within WOLF_FEAR_RADIUS, or INF.
func _nearest_wolf(pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := WOLF_FEAR_RADIUS
	var cc := _cell_key(pos, GRID_WOLF)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var arr: Array = _wolf_grid.get(cc + Vector2i(dx, dy), [])
			for an in arr:
				var d: float = pos.distance_to(
					an.get("position", pos))
				if d < best_d:
					best_d = d
					best = an.get("position", pos)
	return best


func _tick_animal(plot: Dictionary, an: Dictionary, anchor: Vector2,
		delta: float) -> void:
	if not bool(an.get("alive", false)):
		return
	# Hunger decays; starving animals lose hp and can die (HTML Animal.update).
	an["hunger"] = maxf(0.0, float(an.get("hunger", 0.0)) - HUNGER_DECAY * delta)
	if float(an.get("hunger", 0.0)) <= 0.0:
		an["hp"] = float(an.get("hp", 0.0)) - STARVE_DMG * delta
		if float(an.get("hp", 0.0)) <= 0.0:
			_kill(plot, an, "starved")
			return
	# Leash: straying animals wander back toward the barn/coop/plot
	# (HTML: moveTarget jittered within +/-80px of the anchor).
	var pos: Vector2 = an.get("position", anchor)
	var st: Dictionary = ANIMAL_TYPES.get(String(an.get("type", "boar")),
		ANIMAL_TYPES["boar"])
	var speed: float = LEASH_SPEED * float(st.get("speed_mul", 1.0))
	var tgt = an.get("move_target", null)
	if pos.distance_to(anchor) > LEASH_RANGE:
		tgt = anchor + Vector2(
			_rng.randf_range(-LEASH_WANDER_RADIUS / 2.0,
				LEASH_WANDER_RADIUS / 2.0),
			_rng.randf_range(-LEASH_WANDER_RADIUS / 2.0,
				LEASH_WANDER_RADIUS / 2.0))
		an["move_target"] = tgt
	elif tgt == null and _rng.randf() < delta * 0.2:
		tgt = anchor + Vector2(
			_rng.randf_range(-LEASH_WANDER_RADIUS, LEASH_WANDER_RADIUS),
			_rng.randf_range(-LEASH_WANDER_RADIUS, LEASH_WANDER_RADIUS))
		an["move_target"] = tgt
	if tgt != null:
		var swim_slow := SWIM_SPEED_MULT \
			if bool(an.get("swimming", false)) else 1.0
		var step: float = speed * swim_slow * delta
		# Livestock steers around water (water_liking types excepted).
		_step_toward(an, pos, tgt, step,
			not WaterNav.animal_avoids_water(an, st))


## Once per day (HTML s8FarmNewDay): the farm feeds its animals and each
## living animal yields food into the faction ledger.
func _new_day(plots: Array) -> void:
	for p in plots:
		if not (p is Dictionary):
			continue
		var plot: Dictionary = p
		_ensure_plot(plot)
		_purge_dead(plot)
		var faction: String = String(plot.get("faction", ""))
		var total := 0.0
		for an in plot["animals"]:
			if not (an is Dictionary):
				continue
			an["hunger"] = FEED_HUNGER  # the farm feeds its animals
			var y: float = float(DAILY_YIELD.get(String(an.get("type", "boar")), 0.0))
			if bool(an.get("tended", false)):
				y *= 1.25  # tended livestock produce 25% more
				an["tended"] = false
			total += y
		if total > 0.0:
			_gs.resources.add_resource(faction, "food", total)
			if _gs.bus.has_signal("animal_yield"):
				_gs.bus.animal_yield.emit(int(plot.get("id", 0)),
					faction, total)
	# Jeremy 2026-10-07 (pet cats): pets eat 1 food/day from their
	# owner's faction stockpile. A broke faction's cats go hungry
	# (they hunt vermin — never starve — but no full bowl either).
	for an in wild:
		if not (an is Dictionary):
			continue
		if not bool(an.get("pet", false)) or not bool(an.get("alive", false)):
			continue
		var pf: String = String(an.get("faction", ""))
		if pf != "" and _gs.resources != null \
				and _gs.resources.spend(pf, {"food": PET_FOOD_PER_DAY}):
			an["hunger"] = FEED_HUNGER


## ---- Wildlife -------------------------------------------------------
## Wild animals roam free (HTML: 80 boars at worldgen, respawn below 40).
## They graze, flee from units, starve, and can be hunted. Wolves are
## predators that hunt sheep/chickens/goats/pigs/boars.


## Spawns one wild animal. Returns the record, or {} if the type is bad.
func spawn_wild(type: String, pos: Vector2) -> Dictionary:
	var t: String = type if ANIMAL_TYPES.has(type) else "boar"
	var st: Dictionary = ANIMAL_TYPES[t]
	var hp: float = roundf((25.0 + _rng.randf() * 20.0) * float(st["hp_mul"]))
	var an: Dictionary = {
		"id": _next_animal_id,
		"type": t,
		"position": pos,
		"hunger": 50.0 + _rng.randf() * 40.0,
		"hp": hp,
		"max_hp": hp,
		"alive": true,
		"wild": true,
		"fear": 0.0,
		"attack_cd": 0.0,
	}
	_next_animal_id += 1
	wild.append(an)
	return an


## Seeds the wilds at worldgen (HTML: 80 scattered boars + 6 near each
## town center, never in water). `is_water` is a Callable(pos) -> bool.
func seed_wildlife(town_centers: Array, is_water: Callable,
		world_w: float, world_h: float) -> void:
	_wild_bounds = Rect2(0, 0, world_w, world_h)
	for i in WILD_SPAWN_COUNT:
		var p := Vector2(_rng.randf_range(600.0, world_w - 600.0),
			_rng.randf_range(600.0, world_h - 600.0))
		if is_water.call(p):
			continue
		spawn_wild("boar", p)
	for c in town_centers:
		var center: Vector2 = c
		for i in 6:
			var ang: float = _rng.randf() * TAU
			var dist: float = 480.0 + _rng.randf() * 350.0
			var p2 := center + Vector2(cos(ang), sin(ang)) * dist
			if is_water.call(p2):
				continue
			spawn_wild("boar", p2)
		# Jeremy 2026-10-07 (pet cats): strays prowl near every town,
		# looking for a human to adopt. Closer in than the boars — cats
		# like people.
		for i in CATS_PER_TOWN:
			var cang: float = _rng.randf() * TAU
			var cdist: float = _rng.randf_range(CAT_SPAWN_MIN_D, CAT_SPAWN_MAX_D)
			var cp := center + Vector2(cos(cang), sin(cang)) * cdist
			if is_water.call(cp):
				continue
			spawn_wild("cat", cp)
	# A few wolf packs in the deep wilds.
	for i in 8:
		var p3 := Vector2(_rng.randf_range(600.0, world_w - 600.0),
			_rng.randf_range(600.0, world_h - 600.0))
		if is_water.call(p3):
			continue
		spawn_wild("wolf", p3)


## Living wild animals.
func living_wild() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for an in wild:
		if bool(an.get("alive", false)):
			out.append(an)
	return out


## Nearest living wild animal to a position (for hunters). Returns {}.
## Jeremy 2026-10-07 (pet cats): owned pets are never valid prey —
## hunters and the undead leave people's cats alone. Wolves hunt through
## the prey grid instead, where cats are fair game.
func nearest_wild(pos: Vector2, max_dist: float = 800.0,
		skip_pets: bool = true) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_dist
	for an in wild:
		if not bool(an.get("alive", false)):
			continue
		if skip_pets and bool(an.get("pet", false)):
			continue
		var d: float = pos.distance_to(an.get("position", pos))
		if d < best_d:
			best_d = d
			best = an
	return best


## Damages a wild animal (hunter attacks, wolf bites). Kills it at 0 hp:
## corpse goes to the undead corpse system, meat value returned for the
## killer to collect.
func damage_wild(an: Dictionary, dmg: float) -> float:
	if an.is_empty() or not bool(an.get("alive", false)):
		return 0.0
	an["hp"] = float(an.get("hp", 0.0)) - dmg
	an["fear"] = 100.0
	# Jeremy 2026-10-05: blood spray + hurt flinch on every hit (hunters,
	# wolves, undead all route through here).
	an["hurt_t"] = 0.3
	if _gs != null and _gs.bus != null \
			and _gs.bus.has_signal("combat_fx"):
		var pos: Vector2 = an.get("position", Vector2.ZERO)
		_gs.bus.combat_fx.emit("blood", pos)
		_gs.bus.combat_fx.emit("blood", pos)
	if float(an.get("hp", 0.0)) <= 0.0:
		_kill_wild(an, "slain")
		var st: Dictionary = ANIMAL_TYPES.get(String(an.get("type", "boar")),
			ANIMAL_TYPES["boar"])
		return float(st.get("food", 4.0))
	return 0.0


## Kills a wild animal: marks dead, corpse to the undead system.
func _kill_wild(an: Dictionary, cause: String) -> void:
	if not bool(an.get("alive", false)):
		return
	an["alive"] = false
	an["hp"] = 0.0
	# Jeremy 2026-10-07 (pet cats): a dead pet genuinely grieves its
	# owner — big mood-urge hit and a line. The cat stays "pet" on the
	# record so the sync layer can fade it out; _release_pet runs on the
	# next think for strays, never for the dead.
	if bool(an.get("pet", false)):
		_grieve_owner(an)
	var ud = _gs.get("undead")
	if ud != null:
		var corpses: Array = ud.corpses
		if corpses.size() < SimUndead.MAX_CORPSES:
			var pos: Vector2 = an.get("position", Vector2.ZERO)
			corpses.append({
				"x": pos.x, "y": pos.y,
				"race": "animal",
				"job": String(an.get("type", "")),
				"t": SimUndead.CORPSE_LIFETIME,
			})
	if _gs.bus.has_signal("animal_died"):
		_gs.bus.animal_died.emit(-1, int(an.get("id", 0)), cause,
			String(an.get("type", "")))


## Owner grief: mood-urge crater + a mourning line through the chatter
## bus (the RS-bubble layer shows it — Jeremy's "no silent failures").
func _grieve_owner(an: Dictionary) -> void:
	var oid := int(an.get("owner_id", -1))
	if oid < 0:
		return
	var owner: Dictionary = _gs.get_unit(oid)
	if owner.is_empty():
		return
	var urges: Dictionary = owner.get("urges", {})
	if not urges.is_empty():
		urges["mood"] = clampf(float(urges.get("mood", 60.0))
			- PET_GRIEF_MOOD, 0.0, 100.0)
	if _gs.bus != null and _gs.bus.has_signal("unit_said"):
		var cname: String = String(an.get("pet_name", "my cat"))
		var lines := [
			"%s is gone... they were a good cat." % cname,
			"I'll miss %s. Best mouser in the faction." % cname,
			"%s crossed the rainbow bridge. Pour one out." % cname,
		]
		_gs.bus.unit_said.emit(oid, lines[_rng.randi() % lines.size()])


## Per-tick wildlife: needs, wandering, fear/flee, wolf predation, and
## the HTML respawn rule (below 40 wild, 2% chance per tick).
## Wild brains run round-robin at 20Hz: 1/3 of the herd per physics tick
## (delta x3) instead of the whole herd every tick — Jeremy 2026-10-05:
## "evenly distribute the cycles" rather than piling work into one frame.
## Movement stays exact via scaled delta; ambient wildlife decisions
## (fear, wander, hunt) at 20Hz are imperceptible. Slicing is reverse-order
## inside each segment so dead-animal remove_at stays safe; the wrap
## segment only touches indices below the cursor, which removals above it
## never shift. Respawn pacing is unchanged (same per-tick gate/chance).
const WILD_TICK_EVERY := 3
# Start at the rebuild threshold so the very first tick builds the neighbor
# grids instead of thinking blind for 2 ticks. (Jeremy 2026-10-05: the cold
# start made boar-fear timing-dependent — a boar could wander out of the
# 70px fear radius before the first grid build, flaking test_animals'
# "boar feared". In-game the window was 0.05s and harmless, but the first
# tick might as well have real data.)
var _wild_frame := WILD_TICK_EVERY
var _wild_cursor := 0


func _tick_wild_all(delta: float) -> void:
	# Respawn (HTML: animals.length < 40 && Math.random() < 0.02).
	if _living_wild_count() < WILD_RESPAWN_FLOOR \
			and _rng.randf() < WILD_RESPAWN_CHANCE:
		_respawn_random()
	var n := wild.size()
	if n == 0:
		return
	var slice := maxi(1, int(ceil(n / float(WILD_TICK_EVERY))))
	var scaled: float = delta * WILD_TICK_EVERY
	var start := _wild_cursor % n
	var stop := mini(n, start + slice)
	# Segment 1: [start, stop) in reverse (remove_at-safe).
	for i in range(stop - 1, start - 1, -1):
		_tick_wild_slot(i, scaled)
	# Segment 2 (wrap): [0, start + slice - n) in reverse.
	for i in range(start + slice - n - 1, -1, -1):
		_tick_wild_slot(i, scaled)
	_wild_cursor = (start + slice) % maxi(1, wild.size())


## One wild-array slot: drop the dead, think the living.
func _tick_wild_slot(i: int, delta: float) -> void:
	var an: Dictionary = wild[i]
	if not bool(an.get("alive", false)):
		wild.remove_at(i)
		return
	_tick_wild_one(an, delta)


## Alive-wild count without living_wild()'s per-tick Array allocation.
func _living_wild_count() -> int:
	var c := 0
	for an in wild:
		if an is Dictionary and bool(an.get("alive", false)):
			c += 1
	return c


## Respawns one wild boar at a random map position (called by world tick
## when the herd is below the floor; HTML parity).
func respawn_wild(pos: Vector2) -> Dictionary:
	return spawn_wild("boar", pos)


## Random deep-wilds respawn point. Uses map bounds from game state.
func _respawn_random() -> void:
	var w: float = _wild_bounds.size.x
	var h: float = _wild_bounds.size.y
	var p := Vector2(_rng.randf_range(600.0, w - 600.0),
		_rng.randf_range(600.0, h - 600.0))
	spawn_wild("boar", p)


func _tick_wild_one(an: Dictionary, delta: float) -> void:
	var pos: Vector2 = an.get("position", Vector2.ZERO)
	var st: Dictionary = ANIMAL_TYPES.get(String(an.get("type", "boar")),
		ANIMAL_TYPES["boar"])
	var is_cat: bool = String(an.get("type", "")) == "cat"
	var is_pet: bool = is_cat and bool(an.get("pet", false))
	# Hunger decays; starving wild animals lose hp and die.
	# Jeremy 2026-10-07 (pet cats): pets hunt vermin, so they get hungry
	# but never starve to death — strays still can.
	var hdecay: float = HUNGER_DECAY * (0.35 if is_pet else 1.0)
	an["hunger"] = maxf(0.0, float(an.get("hunger", 0.0)) - hdecay * delta)
	if float(an.get("hunger", 0.0)) <= 0.0 and not is_pet:
		an["hp"] = float(an.get("hp", 0.0)) - STARVE_DMG * delta
		if float(an.get("hp", 0.0)) <= 0.0:
			_kill_wild(an, "starved")
			return
	# Graze when hungry and calm.
	var fear: float = float(an.get("fear", 0.0))
	if fear < 12.0 and float(an.get("hunger", 0.0)) < 60.0:
		an["hunger"] = minf(100.0, float(an.get("hunger", 0.0)) + 18.0 * delta)
	an["fear"] = maxf(0.0, fear - 4.0 * delta)
	# Wolves hunt prey.
	if String(an.get("type", "")) == "wolf":
		_wolf_hunt(an, pos, delta)
		return
	# Jeremy 2026-10-07 (pet cats): adoption + follow before the generic
	# fear/wander. Pets trust people — they skip the gnome-fear below.
	if is_cat:
		if is_pet:
			_tick_pet_follow(an, pos, delta)
		else:
			_try_adopt(an, pos)
	# Jeremy 2026-10-05: prey RUNS when a wolf is hunting nearby — full
	# sprint away, not the unit-threat trot. Checked first: wolves are
	# scarier than gnomes.
	var running := false
	if String(an.get("type", "")) in PREDATORS.get("wolf", []):
		var wolf_threat := _nearest_wolf(pos)
		if wolf_threat != Vector2.INF:
			an["fear"] = 100.0
			running = true
			var flee: Vector2 = (pos - wolf_threat).normalized()
			if flee.length() > 0.01:
				an["move_target"] = pos + flee * 220.0
	an["running"] = running
	# Flee nearby units (HTML: 70px fear radius). Tame pets excepted.
	if not is_pet:
		var threat := _nearest_unit_threat(pos)
		if threat != Vector2.INF:
			an["fear"] = minf(100.0, float(an.get("fear", 0.0)) + 35.0 * delta)
			var away: Vector2 = (pos - threat).normalized()
			if away.length() > 0.01:
				an["move_target"] = pos + away * 120.0
	# Wander.
	_wild_wander(an, pos, delta, st)


func _wild_wander(an: Dictionary, pos: Vector2, delta: float,
		st: Dictionary) -> void:
	var tgt = an.get("move_target", null)
	if tgt == null and _rng.randf() < delta * 0.2:
		tgt = pos + Vector2(
			_rng.randf_range(-WILD_WANDER_RADIUS, WILD_WANDER_RADIUS),
			_rng.randf_range(-WILD_WANDER_RADIUS, WILD_WANDER_RADIUS))
		an["move_target"] = tgt
	if tgt != null:
		var swim_slow := SWIM_SPEED_MULT \
			if bool(an.get("swimming", false)) else 1.0
		var speed: float = LEASH_SPEED * float(st.get("speed_mul", 1.0)) \
			* swim_slow
		if bool(an.get("running", false)):
			speed *= FLEE_RUN_MULT
		elif float(an.get("fear", 0.0)) > 12.0:
			speed *= 1.5
		var step: float = speed * delta
		# Fleeing (running) animals may enter water to escape; calm ones
		# steer around it (water_liking types excepted).
		_step_toward(an, pos, tgt, step,
			not WaterNav.animal_avoids_water(an, st))


## ---- Pet cats (Jeremy 2026-10-07 — NPC life deep pass) ----------------
## Strays choose a human; pets follow, purr, and grieve. All state lives
## on the wild-animal record: pet: bool, owner_id: int, pet_name: String,
## faction: String (owner's faction, for the daily food tithe).


## A stray cat looks for a nearby civilian to adopt. Cats choose their
## humans: nearest living non-military unit in ADOPT_RADIUS that doesn't
## already have a pet. One roll per think keeps adoptions gradual.
func _try_adopt(an: Dictionary, pos: Vector2) -> void:
	if _rng.randf() > 0.25:
		return
	var owner := _nearest_civilian(pos, ADOPT_RADIUS)
	if owner.is_empty():
		return
	var oid := int(owner.get("id", -1))
	if oid < 0 or _owner_has_pet(oid):
		return
	an["pet"] = true
	an["owner_id"] = oid
	an["pet_name"] = _pet_name()
	an["faction"] = String(owner.get("faction", ""))
	an["fear"] = 0.0
	an.erase("move_target")
	if _gs.bus != null and _gs.bus.has_signal("unit_said"):
		var cname: String = String(an.get("pet_name", "the cat"))
		var oname: String = String(owner.get("name", "someone"))
		var lines := [
			"Everyone, this is %s. %s lives here now." % [cname, cname],
			"%s just walked in like they pay rent here. Guess I have a cat." % cname,
			"Look what the void coughed up — meet %s." % cname,
		]
		_gs.bus.unit_said.emit(oid, lines[_rng.randi() % lines.size()])


## Nearest living civilian (non-military) unit within radius. Uses the
## unit grid; ties break by units-array order like the threat query.
func _nearest_civilian(pos: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	var cc := _cell_key(pos, GRID_UNIT)
	var rad_cells := int(ceil(radius / GRID_UNIT))
	for dy in range(-rad_cells, rad_cells + 1):
		for dx in range(-rad_cells, rad_cells + 1):
			var arr: Array = _unit_grid.get(cc + Vector2i(dx, dy), [])
			for e in arr:
				var v: Vector3 = e
				var ei := int(v.z)
				if ei < 0 or ei >= _gs.units.size():
					continue
				var u: Dictionary = _gs.units[ei]
				if not bool(u.get("alive", true)):
					continue
				if JobDefs.is_military(String(u.get("job", ""))):
					continue
				var d := pos.distance_to(Vector2(v.x, v.y))
				if d < best_d:
					best_d = d
					best = u
	return best


## True if this unit already owns a living pet cat.
func _owner_has_pet(owner_id: int) -> bool:
	for an in wild:
		if bool(an.get("pet", false)) and bool(an.get("alive", false)) \
				and int(an.get("owner_id", -1)) == owner_id:
			return true
	return false


## A fresh cat name. Prancey (Jeremy's real cat) is in the pool.
func _pet_name() -> String:
	return CAT_NAMES[_rng.randi() % CAT_NAMES.size()]


## Owned-cat think: follow the human, purr in radius, come home when lost.
## A dead or missing owner releases the cat back to stray life.
func _tick_pet_follow(an: Dictionary, pos: Vector2, delta: float) -> void:
	var oid := int(an.get("owner_id", -1))
	var owner: Dictionary = _gs.get_unit(oid) if oid >= 0 else {}
	if owner.is_empty() or not bool(owner.get("alive", true)):
		_release_pet(an)
		return
	var opos: Vector2 = owner.get("position", pos)
	var d := pos.distance_to(opos)
	if d > PET_TELEPORT_R:
		# The cat "finds" its human — no cat gets left behind by a march.
		an["position"] = opos + Vector2(
			_rng.randf_range(-50.0, 50.0), _rng.randf_range(-50.0, 50.0))
		an.erase("move_target")
	elif d > PET_FOLLOW_R:
		an["move_target"] = opos + Vector2(
			_rng.randf_range(-40.0, 40.0), _rng.randf_range(-40.0, 40.0))
	else:
		an.erase("move_target")
		_purr(an, owner, delta)


## Purring: the owner's social and mood urges lift while the cat is near.
## Direct urge-dict nudge (the same fields SimMind ticks every frame).
func _purr(an: Dictionary, owner: Dictionary, delta: float) -> void:
	var urges: Dictionary = owner.get("urges", {})
	if urges.is_empty():
		return
	urges["social"] = clampf(float(urges.get("social", 60.0))
		+ PET_AURA_SOCIAL * delta, 0.0, 100.0)
	urges["mood"] = clampf(float(urges.get("mood", 60.0))
		+ PET_AURA_MOOD * delta, 0.0, 100.0)


## Owner dead or gone: the cat is a stray again (it keeps its name — a
## new human may adopt it later).
func _release_pet(an: Dictionary) -> void:
	an["pet"] = false
	an["owner_id"] = -1
	an["faction"] = ""
	an.erase("move_target")


## Nearest living unit to a position within the fear radius, or INF.
func _nearest_unit_threat(pos: Vector2) -> Vector2:
	# Grid query: 3x3 cells of 128px always cover the 70px radius, so this
	# returns exactly what the old full-units scan returned (strict < keeps
	# the first-in-order winner; the stored index reproduces it across
	# cells). O(nearby units) instead of O(all units), per wild animal.
	var best := Vector2.INF
	var best_d := WILD_FEAR_RADIUS
	var best_idx := -1
	var cc := _cell_key(pos, GRID_UNIT)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var arr: Array = _unit_grid.get(cc + Vector2i(dx, dy), [])
			for e in arr:
				var v: Vector3 = e
				var d := pos.distance_to(Vector2(v.x, v.y))
				var ei := int(v.z)
				if d < best_d or (best_idx >= 0 and d == best_d \
						and ei < best_idx):
					best_d = d
					best = Vector2(v.x, v.y)
					best_idx = ei
	return best


## Wolf predation: find nearest prey, chase it, bite on contact.
func _wolf_hunt(wolf: Dictionary, pos: Vector2, delta: float) -> void:
	wolf["attack_cd"] = maxf(0.0, float(wolf.get("attack_cd", 0.0)) - delta)
	var best: Dictionary = {}
	var best_d := WOLF_HUNT_RADIUS
	var best_order := -1
	var best_wild := false
	# Grid query replaces the old wild-then-livestock full scans: same
	# candidates, same wild-first order, no per-wolf O(n) sweeps.
	# Cell 320px > the 300px hunt radius, so the 3x3 neighborhood is exact.
	# Jeremy 2026-10-05: wild prey beats livestock (the order
	# _rebuild_prey_grid stores for, and what the old scan did) — a farther
	# wild animal wins over a nearer farm animal; distance only breaks ties
	# within the same class, grid order breaking exact ties.
	var cc := _cell_key(pos, GRID_PREY)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var arr: Array = _prey_grid.get(cc + Vector2i(dx, dy), [])
			for e in arr:
				var an: Dictionary = e[0]
				if an == wolf:
					continue
				var d: float = pos.distance_to(an.get("position", pos))
				if d >= WOLF_HUNT_RADIUS:
					continue
				var is_wild: bool = bool(an.get("wild", false))
				var eo: int = e[1]
				var wins := false
				if best.is_empty():
					wins = true
				elif is_wild and not best_wild:
					wins = true
				elif is_wild == best_wild \
						and (d < best_d or (d == best_d and eo < best_order)):
					wins = true
				if wins:
					best_d = d
					best = an
					best_order = eo
					best_wild = is_wild
	if best.is_empty():
		_wild_wander(wolf, pos, delta, ANIMAL_TYPES["wolf"])
		return
	var tpos: Vector2 = best.get("position", pos)
	if best_d <= WOLF_ATTACK_RANGE:
		if float(wolf.get("attack_cd", 0.0)) <= 0.0:
			wolf["attack_cd"] = WOLF_ATTACK_CD
			# Jeremy 2026-10-05: visible bite lunge on every wolf attack.
			wolf["attack_t"] = 0.35
			if bool(best.get("wild", false)):
				damage_wild(best, WOLF_ATTACK_DMG)
			else:
				# Farm livestock: damage through the plot record.
				best["hp"] = float(best.get("hp", 0.0)) - WOLF_ATTACK_DMG
				best["fear"] = 100.0
				best["hurt_t"] = 0.3
				if _gs != null and _gs.bus != null \
						and _gs.bus.has_signal("combat_fx"):
					_gs.bus.combat_fx.emit("blood", tpos)
					_gs.bus.combat_fx.emit("blood", tpos)
				if float(best.get("hp", 0.0)) <= 0.0:
					best["alive"] = false
					best["hp"] = 0.0
	else:
		var st: Dictionary = ANIMAL_TYPES["wolf"]
		var swim_slow := SWIM_SPEED_MULT \
			if bool(wolf.get("swimming", false)) else 1.0
		var speed: float = LEASH_SPEED * float(st.get("speed_mul", 1.0)) \
			* 1.4 * swim_slow
		var d: Vector2 = tpos - pos
		var step: float = speed * delta
		# A hunting wolf is not fleeing: it stops at the waterline
		# instead of swimming after prey.
		_step_toward(wolf, pos, tpos, step,
			not WaterNav.animal_avoids_water(wolf, st))


## ---- Save/load (Jeremy 2026-10-07 — pet cats) -------------------------
## The wild herd (pets included) now persists across save/load. Legacy
## saves without the "animals" section load with an empty herd — the
## existing below-40 respawn rule reseeds boars, and new strays arrive
## with new towns. Pet records round-trip owner_id/pet_name/faction, so
## nobody's cat vanishes between sessions.
func to_dict() -> Dictionary:
	var herd := []
	for an in wild:
		if an is Dictionary:
			herd.append((an as Dictionary).duplicate(true))
	return {
		"wild": herd,
		"next_animal_id": _next_animal_id,
		"wild_bounds": {
			"x": _wild_bounds.position.x, "y": _wild_bounds.position.y,
			"w": _wild_bounds.size.x, "h": _wild_bounds.size.y,
		},
	}


func from_dict(data: Dictionary) -> void:
	wild.clear()
	for an in data.get("wild", []):
		if an is Dictionary:
			wild.append(an)
	_next_animal_id = int(data.get("next_animal_id", 1))
	var wb: Dictionary = data.get("wild_bounds", {})
	if not wb.is_empty():
		_wild_bounds = Rect2(float(wb.get("x", 0.0)), float(wb.get("y", 0.0)),
			float(wb.get("w", 4000.0)), float(wb.get("h", 4000.0)))
	_last_day = _gs.day_number if _gs != null else 1
