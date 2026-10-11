class_name SimTradeRoutes
extends RefCounted
## Cursing Gnomes — inter-faction trade routes (port of HTML fix79
## ensureTradeRoute / dissolveTradeRoutes / spawnTradeWagon /
## updateTradeWagons / loadWagonCargo / deliverWagonCargo,
## index.html ~L43375-43560).
##
## The physical trade layer underneath the diplomacy trade agreements: when
## two factions sign a trade deal (or ally), a dirt trade road is built
## between their halls, trade outposts rise near each hall, and covered
## wagons loop between the halls hauling cargo. Wagons pause (but survive)
## while their two factions are at war; declaring war dissolves the route.
##
## HTML-verbatim numbers kept: 2 initial wagons (one each way), wagon speed
## 40-55 px/s, 8px arrival radius, 1.25x road speed bonus, cargo formula
## gold min(25, 2%+8) / wood min(30, 2%+10) / food min(15, 3%+5) deducted
## from the sender and delivered to the receiver, outpost skip-within-150px
## and spawn ~90px from the hall, bob += dt*4.
##
## Improvements over HTML:
##   - wagons move through Godot's resource ledger (add_resource, capped)
##   - Gazette stories on route open / dissolve (HTML: floating text only)
##   - trade outposts are a real building type (HTML: storage + flag)
##   - full save/load roundtrip (HTML routes were session-only)
##   - route creation is idempotent; routes keyed by pair not direction
##
## Owned by World (game.trade_routes). Wired in world.gd: constructed next
## to SimGarrison, ticked per-frame, worker_ai + court injected.


## HTML-verbatim constants.
const WAGON_SPEED_MIN := 40.0   ## spawnTradeWagon: 40 + rand*15
const WAGON_SPEED_MAX := 55.0
const ARRIVE_RADIUS := 8.0       ## updateTradeWagons: d > 8 keeps moving
const ROAD_SPEED_MULT := 1.25    ## road cells ahead: 1.25x (HTML roadAt)
const WAGON_WEAR_MULT := 4.0    ## wagons are heavy: 4x road wear
const ROAD_AHEAD_LOOK := 3.0    ## road check looks 3 steps ahead
const ROAD_NEAR_RADIUS := 30.0  ## what counts as "on a road" (Godot-side)
const OUTPOST_DIST := 90.0      ## spawnTradeOutpost: 90px random angle
const OUTPOST_MIN_SEP := 150.0  ## skip if a trade_outpost already within
const OUTPOST_CLEAR := 46.0     ## building clearance when nudging a spot
const ROAD_SAMPLE_STEP := 18.0  ## road paint spacing along the path
const ROAD_WIDEN := 26.0        ## triple stroke: perpendicular offsets


var _gs = null                  ## GameState (untyped: avoids load cycle)
var worker_ai = null            ## WorkerAI — injected by World (roads)
var court = null                ## SimRoyalCourt — injected by World

var _next_route_id := 1
var _next_wagon_seq := 1

## Live routes: {id:int, a:String, b:String, outpost_a:int, outpost_b:int}
var routes: Array[Dictionary] = []
## Live wagons: {id:String, route_id:int, home_race:String, from_race:String,
##   to_race:String, pos:Vector2, target:Vector2, speed:float,
##   cargo:{gold,wood,food}, bob:float, facing:float}
var wagons: Array[Dictionary] = []


func _init(game_state) -> void:
	_gs = game_state


## --- queries ----------------------------------------------------------------


## The live route for a faction pair (order-independent), or {}.
func route_between(a: String, b: String) -> Dictionary:
	for r in routes:
		var ra := String(r.get("a", ""))
		var rb := String(r.get("b", ""))
		if (ra == a and rb == b) or (ra == b and rb == a):
			return r
	return {}


func _route_by_id(route_id: int) -> Dictionary:
	for r in routes:
		if int(r.get("id", -1)) == route_id:
			return r
	return {}


## Wagons still rolling on a route (not marked dead).
func _live_wagons(route_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in wagons:
		if int(w.get("route_id", -1)) == route_id \
				and not bool(w.get("dead", false)):
			out.append(w)
	return out


## Drops route records that can never resume: no live wagons and a hall
## gone (razed). A future deal re-creates the route fresh via
## ensure_route, so the husk is pure dead weight.
func _purge_dead_routes() -> void:
	var kept: Array[Dictionary] = []
	for r in routes:
		var ra := String(r.get("a", ""))
		var rb := String(r.get("b", ""))
		var widowed := _live_wagons(int(r.get("id", -1))).is_empty() \
			and (_hall_pos(ra).x < 0.0 or _hall_pos(rb).x < 0.0)
		if not widowed:
			kept.append(r)
	routes = kept


## HTML boost_trade port (production hook): adds one wagon each way on
## every live route touching the faction. Returns wagons added.
func boost_routes(faction: String) -> int:
	var added := 0
	for r in routes:
		var ra := String(r.get("a", ""))
		var rb := String(r.get("b", ""))
		if ra != faction and rb != faction:
			continue
		var before := wagons.size()
		_spawn_wagon(r, ra)
		_spawn_wagon(r, rb)
		added += wagons.size() - before
	return added


## Faction's primary hall position, or Vector2(-1,-1) when it has no hall
## (HTML hallOf -> null). Prefers town_hall, else any complete hall.
func _hall_pos(faction: String) -> Vector2:
	var fallback := Vector2(-1, -1)
	for b in _gs.buildings:
		if String(b.get("faction", "")) != faction:
			continue
		if not String(b.get("type", "")) in SimTowns.HALL_TYPES:
			continue
		if not bool(b.get("complete", false)):
			continue
		var pos: Vector2 = b.get("position", Vector2(-1, -1))
		if String(b.get("type", "")) == "town_hall":
			return pos
		if fallback.x < 0.0:
			fallback = pos
	return fallback


## --- route lifecycle ----------------------------------------------------------


## Opens a trade route between two factions (HTML ensureTradeRoute).
## Idempotent: an existing live route is returned unchanged. Builds the
## triple dirt road, raises both outposts, spawns the initial wagon pair.
## extra_wagons adds one wagon each way (HTML boost_trade).
## A record with no live wagons is revived (the pair re-seeds) so a new
## deal after a razing actually restarts trade.
func ensure_route(a: String, b: String, extra_wagons := false) -> Dictionary:
	if a == "" or b == "" or a == b:
		return {}
	var route := route_between(a, b)
	if route.is_empty():
		var ha := _hall_pos(a)
		var hb := _hall_pos(b)
		if ha.x < 0.0 or hb.x < 0.0:
			return {}  # HTML: no hall -> null
		_build_trade_road(ha, hb, a)
		route = {
			"id": _next_route_id, "a": a, "b": b,
			"outpost_a": -1, "outpost_b": -1,
		}
		_next_route_id += 1
		routes.append(route)
		route["outpost_a"] = _spawn_outpost(ha, a, int(route["id"]))
		route["outpost_b"] = _spawn_outpost(hb, b, int(route["id"]))
		_spawn_wagon(route, a)  # HTML: i % 2 == 0 -> raceA first
		_spawn_wagon(route, b)
		_gazette_open(a, b)
	# Revive: the record exists but has no live wagons (halls were razed
	# and rebuilt, or every wagon was lost). A new deal must restart trade,
	# not return a wagon-less husk — re-seed the pair when halls stand.
	if _live_wagons(int(route["id"])).is_empty():
		var ha := _hall_pos(a)
		var hb := _hall_pos(b)
		if ha.x >= 0.0 and hb.x >= 0.0:
			_spawn_wagon(route, a)
			_spawn_wagon(route, b)
			_gazette_open(a, b)
	if extra_wagons:
		_spawn_wagon(route, a)
		_spawn_wagon(route, b)
	return route


## Kills every route (and its wagons) between two factions
## (HTML dissolveTradeRoutes). Outposts stand — they're buildings now.
## Returns the number of routes dissolved.
func dissolve_routes(a: String, b: String) -> int:
	var dead: Array[int] = []
	for r in routes:
		var ra := String(r.get("a", ""))
		var rb := String(r.get("b", ""))
		if (ra == a and rb == b) or (ra == b and rb == a):
			dead.append(int(r.get("id", -1)))
	if dead.is_empty():
		return 0
	var kept: Array[Dictionary] = []
	for r in routes:
		if not int(r.get("id", -1)) in dead:
			kept.append(r)
	routes = kept
	for w in wagons:
		if int(w.get("route_id", -1)) in dead:
			w["dead"] = true
	_sweep_wagons()
	_gazette_dissolve(a, b)
	return dead.size()


func _sweep_wagons() -> void:
	var kept: Array[Dictionary] = []
	for w in wagons:
		if not bool(w.get("dead", false)):
			kept.append(w)
	wagons = kept


## --- per-frame tick ------------------------------------------------------------


func tick(delta: float) -> void:
	if not wagons.is_empty():
		var dip = _gs.diplomacy if _gs != null else null
		for w in wagons:
			if bool(w.get("dead", false)):
				continue
			var route := _route_by_id(int(w.get("route_id", -1)))
			if route.is_empty():
				w["dead"] = true
				continue
			# Don't trade during active war between the parties (HTML verbatim:
			# wagons hold in place; dissolve_routes handles war declarations).
			if dip != null and dip.has_method("relation_state") \
					and dip.relation_state(String(route["a"]),
							String(route["b"])) == "war":
				continue
			w["bob"] = float(w.get("bob", 0.0)) + delta * 4.0
			var pos: Vector2 = w["pos"]
			var target: Vector2 = w["target"]
			var d := target - pos
			var dist := d.length()
			if dist > ARRIVE_RADIUS:
				var dir := d / dist
				# Jeremy 2026-10-10 visible road construction: wagons route
				# around marked work zones (never through the barriers).
				if worker_ai != null and dist > ARRIVE_RADIUS * 3.0:
					dir = worker_ai.deflect_around_workzones(pos, dir, {})
				var step := dir * float(w.get("speed", WAGON_SPEED_MIN)) * delta
				step *= _road_speed_mult(pos + step * ROAD_AHEAD_LOOK, delta)
				# Jeremy 2026-10-05: wagons never enter water — steer
				# around the shoreline or hold position.
				w["pos"] = WaterNav.dry_step_vehicle(
					_gs.map_data, pos, dir, step.length())
				w["facing"] = 1.0 if d.x >= 0.0 else -1.0
			else:
				_deliver(w)
				_turn_around(w, route)
		_sweep_wagons()
	# Widowed husks (no wagons, hall gone) can never resume — drop the
	# record even when no wagons remain to sweep.
	_purge_dead_routes()


## Wear-scaled road speed multiplier at pos (Jeremy 2026-10-10 road
## wear: fresh roads grant the full 1.25x, fully worn roads grant nothing —
## the movement bonus degrades with wear). Wagons also grind wear into the
## road record they ride on.
func _road_speed_mult(pos: Vector2, delta: float) -> float:
	if worker_ai == null:
		return 1.0
	var best: Dictionary = {}
	var best_d := ROAD_NEAR_RADIUS
	for r in worker_ai.roads:
		var d: float = (r.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = r
	if best.is_empty():
		return 1.0
	worker_ai.wear_road_at(pos,
		WorkerAI.WEAR_PER_SEC * WAGON_WEAR_MULT * delta)
	var wear: float = float(best.get("wear", 0.0))
	return 1.0 + (ROAD_SPEED_MULT - 1.0) * (1.0 - wear)


## --- cargo ---------------------------------------------------------------------


## Pure: HTML-verbatim loadWagonCargo amounts for a faction's stockpiles.
static func cargo_for(gold: float, wood: float, food: float) -> Dictionary:
	return {
		"gold": minf(25.0, floor(gold * 0.02) + 8.0),
		"wood": minf(30.0, floor(wood * 0.02) + 10.0),
		"food": minf(15.0, floor(food * 0.03) + 5.0),
	}


## Loads cargo from the sender, deducting lightly (HTML: max(0, res-cargo);
## add_resource clamps at 0 the same way).
func _load_cargo(race: String) -> Dictionary:
	var res = _gs.resources
	var cargo := cargo_for(
		res.get_amount(race, "gold"),
		res.get_amount(race, "wood"),
		res.get_amount(race, "food"))
	res.add_resource(race, "gold", -float(cargo["gold"]))
	res.add_resource(race, "wood", -float(cargo["wood"]))
	res.add_resource(race, "food", -float(cargo["food"]))
	return cargo


## Delivers the wagon's cargo to its destination faction
## (HTML deliverWagonCargo).
func _deliver(w: Dictionary) -> void:
	var cargo: Dictionary = w.get("cargo", {})
	if cargo.is_empty():
		return
	var to_race := String(w.get("to_race", ""))
	var res = _gs.resources
	res.add_resource(to_race, "gold", float(cargo.get("gold", 0.0)))
	res.add_resource(to_race, "wood", float(cargo.get("wood", 0.0)))
	res.add_resource(to_race, "food", float(cargo.get("food", 0.0)))
	w["cargo"] = {}


## Swaps the wagon's destination to the other hall and reloads cargo
## (HTML updateTradeWagons arrival branch).
func _turn_around(w: Dictionary, route: Dictionary) -> void:
	var ra := String(route["a"])
	var rb := String(route["b"])
	var ha := _hall_pos(ra)
	var hb := _hall_pos(rb)
	if ha.x < 0.0 or hb.x < 0.0:
		w["dead"] = true  # hall razed: the wagon is lost with the route
		return
	var pos: Vector2 = w["pos"]
	if pos.distance_to(ha) < pos.distance_to(hb):
		w["from_race"] = ra
		w["to_race"] = rb
		w["target"] = hb
	else:
		w["from_race"] = rb
		w["to_race"] = ra
		w["target"] = ha
	w["cargo"] = _load_cargo(String(w["from_race"]))


## --- spawning -------------------------------------------------------------------


## Builds the triple dirt trade road between the two halls
## (HTML ensureTradeRoute: center stroke + two parallel widen strokes).
func _build_trade_road(ha: Vector2, hb: Vector2, faction: String) -> void:
	if worker_ai == null:
		return
	var d := hb - ha
	var dist := d.length()
	if dist < 1.0:
		return
	var dir := d / dist
	var perp := Vector2(-dir.y, dir.x)
	var steps := int(dist / ROAD_SAMPLE_STEP)
	for i in range(steps + 1):
		var base := ha + dir * minf(float(i) * ROAD_SAMPLE_STEP, dist)
		for off in [-ROAD_WIDEN, 0.0, ROAD_WIDEN]:
			worker_ai.paint_road(base + perp * off, faction, "dirt")


## Raises a trade outpost near a hall (HTML spawnTradeOutpost). Real
## building type (HTML used storage + a flag). Skips when one already
## stands within OUTPOST_MIN_SEP of the hall. Returns the building id,
## or -1 when no clear spot was found.
func _spawn_outpost(hall_pos: Vector2, faction: String,
		route_id: int) -> int:
	for b in _gs.buildings:
		if String(b.get("type", "")) != "trade_outpost":
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if (b.get("position", Vector2.ZERO) as Vector2) \
				.distance_to(hall_pos) < OUTPOST_MIN_SEP:
			return int(b.get("id", -1))
	var pos := _clear_near(
		hall_pos + Vector2.RIGHT.rotated(randf() * TAU) * OUTPOST_DIST)
	if pos.x < 0.0:
		return -1
	var b: Dictionary = _gs.add_building({
		"type": "trade_outpost",
		"name": "Trade Outpost",
		"position": pos,
		"faction": faction,
		"complete": true,
		"progress": 1.0,
		"trade_route_id": route_id,
	})
	return int(b.get("id", -1))


## Nudges a point to the nearest spot clear of other buildings
## (HTML findClearSpot, simplified). Vector2(-1,-1) when blocked.
func _clear_near(pos: Vector2) -> Vector2:
	if _spot_clear(pos):
		return pos
	for ring in [OUTPOST_DIST + 30.0, OUTPOST_DIST + 70.0]:
		for k in range(8):
			var p: Vector2 = pos + Vector2.RIGHT.rotated(k * TAU / 8.0) * ring
			if _spot_clear(p):
				return p
	return Vector2(-1, -1)


func _spot_clear(pos: Vector2) -> bool:
	for b in _gs.buildings:
		if (b.get("position", Vector2.ZERO) as Vector2) \
				.distance_to(pos) < OUTPOST_CLEAR:
			return false
	return true


## Spawns one covered wagon at its home hall, bound for the other
## (HTML spawnTradeWagon).
func _spawn_wagon(route: Dictionary, home_race: String) -> void:
	var ra := String(route["a"])
	var rb := String(route["b"])
	var ha := _hall_pos(ra)
	var hb := _hall_pos(rb)
	if ha.x < 0.0 or hb.x < 0.0:
		return
	var from_pos := ha if home_race == ra else hb
	var to_pos := hb if home_race == ra else ha
	var to_race := rb if home_race == ra else ra
	wagons.append({
		"id": "tw%d" % _next_wagon_seq,
		"route_id": int(route["id"]),
		"home_race": home_race,
		"from_race": home_race,
		"to_race": to_race,
		"pos": from_pos,
		"target": to_pos,
		"speed": randf_range(WAGON_SPEED_MIN, WAGON_SPEED_MAX),
		"cargo": _load_cargo(home_race),
		"bob": randf() * 10.0,
		"facing": 1.0 if to_pos.x >= from_pos.x else -1.0,
	})
	_next_wagon_seq += 1


## --- gazette ----------------------------------------------------------------------


func _fname(faction: String) -> String:
	var d: Dictionary = Config.FACTIONS.get(faction, {})
	var n := String(d.get("name", ""))
	return n if n != "" else faction.capitalize()


func _gazette_open(a: String, b: String) -> void:
	if court != null and court.has_method("publish_story"):
		court.publish_story(
			"Trade route opened between %s and %s" % [_fname(a), _fname(b)],
			"Covered wagons rolled out on day %d: %s goods for %s goods, \
dust on the new dirt road and coin in every saddlebag." % [
				_gs.day_number, _fname(a), _fname(b)],
			"trade")


func _gazette_dissolve(a: String, b: String) -> void:
	if court != null and court.has_method("publish_story"):
		court.publish_story(
			"Trade route with %s dissolved" % _fname(b),
			"The wagons turned home on day %d. The %s will trade with the \
%s no longer." % [_gs.day_number, _fname(a), _fname(b)],
			"trade")


## --- renderer feed ------------------------------------------------------------------


## Snapshot of live wagons for the TradeWagonLayer (position, faction
## color key, facing, bob). Cheap: routes are few by design.
func wagon_draw_list() -> Array:
	var out: Array = []
	for w in wagons:
		if bool(w.get("dead", false)):
			continue
		out.append({
			"pos": w["pos"],
			"id": String(w.get("id", "")),
			"from_race": String(w.get("from_race", "")),
			"facing": float(w.get("facing", 1.0)),
			"bob": float(w.get("bob", 0.0)),
		})
	return out


## --- save / load ----------------------------------------------------------------------


func to_dict() -> Dictionary:
	var rd: Array = []
	for r in routes:
		rd.append(r.duplicate())
	var wd: Array = []
	for w in wagons:
		var d := w.duplicate()
		d["pos"] = [w["pos"].x, w["pos"].y]
		d["target"] = [w["target"].x, w["target"].y]
		d["cargo"] = (w.get("cargo", {}) as Dictionary).duplicate()
		wd.append(d)
	return {
		"next_route_id": _next_route_id,
		"next_wagon_seq": _next_wagon_seq,
		"routes": rd,
		"wagons": wd,
	}


func from_dict(data: Dictionary) -> void:
	routes.clear()
	wagons.clear()
	_next_route_id = int(data.get("next_route_id", 1))
	_next_wagon_seq = int(data.get("next_wagon_seq", 1))
	for r in data.get("routes", []):
		routes.append((r as Dictionary).duplicate())
	for w in data.get("wagons", []):
		var d := (w as Dictionary).duplicate()
		var p: Array = d.get("pos", [0, 0])
		var t: Array = d.get("target", [0, 0])
		d["pos"] = Vector2(float(p[0]), float(p[1]))
		d["target"] = Vector2(float(t[0]), float(t[1]))
		wagons.append(d)
