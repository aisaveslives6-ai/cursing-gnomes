class_name StarFortBases
extends RefCounted
## Cursing Gnomes — AI star-fort military bases (Milestone 3b completion).
##
## Jeremy's rule (2026-09-26): military bases are enclosed by DISTINCT
## star-fort wall formations — with openings in the walls so soldiers can
## exit (never the same tight wall rings used for towns) — and the walls
## are pushed well out from the base buildings.
##
## StarFort (scripts/buildings/starfort.gd) implemented the full layout —
## 5-bastion star ring, 4 gaps with dirt roads, guard towers on the tips,
## the 9 HTML star_fort base buildings, and a military district zone —
## but NOTHING called it: the AI kept scattering barracks/camps
## individually around towns. This tick system is the call site, built on
## the BorderWalls pattern: own tick, own save surface, no ai_director
## surgery (that file is a sibling hotspot).
##
## Policy: one star fort per AI town once the town holds a real military
## presence (>= MIN_MILITARY military buildings). AI factions auto-commit;
## the player race is never auto-built for (sovereignty: advisers suggest,
## never spend on the player's behalf). Blueprints cost real resources via
## place_blueprint; the whole fort is affordability-gated before commit so
## broke factions retry on the next pass instead of raising a ruin.
##
## Pure sim — rendering and construction progress live elsewhere.


## Game-time seconds between AI passes per faction.
const TICK_INTERVAL := 90.0

## Fort center distance from the town hall (outside the town, well clear).
const FORT_DIST := 850.0

## Minimum military buildings of the faction before it earns a fort.
const MIN_MILITARY := 2

## Minimum center-to-center separation between forts.
const FORT_MIN_SEP := StarFort.DEFAULT_RADIUS * 2.4

## Building types that count as "military presence" for the trigger.
const MILITARY_TYPES := ["barracks", "cannon_foundry", "aa_tower",
	"medic_camp", "equip_camp", "field_camp", "guard_tower"]


var _gs  # GameState (untyped: avoids a cyclic class reference)

## hall building id -> {center: Vector2, radius, faction, town_id}. Save me.
var forts: Dictionary = {}

## Per-faction next-allowed tick time. Save me.
var cooldowns: Dictionary = {}


func _init(game_state) -> void:
	_gs = game_state


## New game: clear all fort state.
func reset_for_new_game() -> void:
	forts.clear()
	cooldowns.clear()


## Save/load surface (the save owner stores these fields on the snapshot).
func to_dict() -> Dictionary:
	return {
		"forts": forts.duplicate(true),
		"cooldowns": cooldowns.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	forts.clear()
	for k in (d.get("forts", {}) as Dictionary).keys():
		var rec: Dictionary = \
			((d.get("forts", {}) as Dictionary).get(k, {}) as Dictionary).duplicate()
		rec["center"] = _decode_vec2(rec.get("center", Vector2.ZERO))
		forts[int(k)] = rec
	cooldowns = (d.get("cooldowns", {}) as Dictionary).duplicate()


func _decode_vec2(v) -> Vector2:
	if v is Vector2:
		return v
	if v is Dictionary and v.has("__vec2"):
		var a: Array = v["__vec2"]
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


## One AI pass for a faction. AI races auto-commit; the player race is
## skipped (sovereignty — never auto-spend for the player).
func tick(faction: String, is_player: bool, bs: SimBuildings,
		wall_drag: WallDrag) -> void:
	var now: float = float(_gs.game_time)
	if float(cooldowns.get(faction, 0.0)) > now:
		return
	cooldowns[faction] = now + TICK_INTERVAL
	if is_player:
		return
	var halls: Array = SimTerritory.halls_of(_gs.buildings, faction)
	if halls.is_empty():
		return
	if _military_count(faction) < MIN_MILITARY:
		return
	for hall: Dictionary in halls:
		var hid := int(hall.get("id", 0))
		if forts.has(hid):
			continue
		var hall_pos: Vector2 = hall.get("position", Vector2.ZERO)
		if _hall_has_fort(hall_pos, faction):
			forts[hid] = {"center": hall_pos,
				"radius": StarFort.DEFAULT_RADIUS,
				"faction": faction,
				"town_id": int(hall.get("town_id", -1))}
			continue
		var spot := _find_spot(faction, hall_pos)
		if spot == Vector2.INF:
			continue
		var plan: Dictionary = StarFort.plan(spot)
		if not _can_afford(faction, _estimate_cost(plan, faction)):
			continue
		var res: Dictionary = StarFort.new().commit(
			_gs, bs, plan, faction, int(hall.get("town_id", -1)), wall_drag)
		if not (res.get("buildings", []) as Array).is_empty():
			forts[hid] = {"center": spot,
				"radius": StarFort.DEFAULT_RADIUS,
				"faction": faction,
				"town_id": int(hall.get("town_id", -1))}


## --- internals ---------------------------------------------------------------


## Alive military buildings of the faction (complete or still rising).
func _military_count(faction: String) -> int:
	var n := 0
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in MILITARY_TYPES:
			n += 1
	return n


## Save-heal fallback: a fort-tagged building near this hall means it has
## one even if the forts dict was lost (old saves, mid-refactor loads).
func _hall_has_fort(hall_pos: Vector2, faction: String) -> bool:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("fort_plan", "")) != "star":
			continue
		if (b.get("position", Vector2.ZERO) as Vector2) \
				.distance_to(hall_pos) < FORT_DIST + StarFort.DEFAULT_RADIUS:
			return true
	return false


## Pick a fort center FORT_DIST from the hall: on land, inside the map,
## placeable, and clear of other forts. Eight compass tries, first valid.
func _find_spot(faction: String, hall_pos: Vector2) -> Vector2:
	var rect := _map_rect()
	var margin := StarFort.DEFAULT_RADIUS * 1.4
	var inset := Rect2(rect.position + Vector2(margin, margin),
		rect.size - Vector2(margin, margin) * 2.0)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		return Vector2.INF
	for i in 8:
		var ang := float(i) / 8.0 * TAU
		var spot := hall_pos + Vector2(cos(ang), sin(ang)) * FORT_DIST
		if not inset.has_point(spot):
			continue
		if not SimBuildings.can_place_at(_gs.buildings, "barracks", spot,
				rect, faction, SimBuildings.PLACEMENT_GAP, []):
			continue
		if not _spot_is_dry(spot, margin):
			continue
		var clear := true
		for rec: Dictionary in forts.values():
			if String(rec.get("faction", "")) != faction:
				continue
			if (rec.get("center", Vector2.ZERO) as Vector2) \
					.distance_to(spot) < FORT_MIN_SEP:
				clear = false
				break
		if not clear:
			continue
		return spot
	return Vector2.INF


func _map_rect() -> Rect2:
	var w := float((_gs.map_data as Dictionary).get("world_w", 4096.0))
	var h := float((_gs.map_data as Dictionary).get("world_h", 4096.0))
	return Rect2(Vector2.ZERO, Vector2(w, h))


## True when no lake or river water touches the fort's footprint.
func _spot_is_dry(center: Vector2, radius: float) -> bool:
	var bodies: Array = \
		(_gs.map_data as Dictionary).get("water_bodies", []) as Array
	for body: Dictionary in bodies:
		match String(body.get("kind", "")):
			"lake":
				var lp: Vector2 = body.get("pos", Vector2.INF)
				if center.distance_to(lp) \
						< float(body.get("radius", 0.0)) + radius:
					return false
			"river":
				var pts: PackedVector2Array = body.get("points",
					PackedVector2Array())
				var half := float(body.get("width", 55.0)) * 0.5 + radius
				for i in range(pts.size() - 1):
					var near: Vector2 = Geometry2D.get_closest_point_to_segment(
						center, pts[i], pts[i + 1])
					if near.distance_to(center) < half:
						return false
	return true


## Whole-fort affordability gate: walls + towers + base slots at base cost.
## (AI pays base costs; the player-only policy multiplier is N/A here.)
func _estimate_cost(plan: Dictionary, faction: String) -> Dictionary:
	return estimate_fort_cost(faction, plan)


## ---- Lane 7 expansion (2026-10-06): public API -----------------------------
## Fort records, explicit orders (Ruler's Voice), garrison/artillery
## reporting, and war-score holder tracking. The AI tick above is unchanged.


## Radius around a fort center inside which troops/vehicles count as
## stationed at the fort (fort radius + maneuvering room).
const FORT_YARD_R := StarFort.DEFAULT_RADIUS * 1.5


## Whole-fort cost estimate, static so Ruler's Voice can validate
## affordability BEFORE promising a fort to the player.
static func estimate_fort_cost(faction: String, plan: Dictionary) -> Dictionary:
	var costs := {}
	var add := func(c: Dictionary) -> void:
		for r: String in c.keys():
			costs[r] = float(costs.get(r, 0.0)) + float(c[r])
	var wall_cost: Dictionary = SimBuildings.cost_of("wall")
	for _p in (plan.get("wall_pts", []) as Array):
		add.call(wall_cost)
	for _t in (plan.get("tower_pts", []) as Array):
		add.call(SimBuildings.cost_of("guard_tower"))
	for sl: Dictionary in (plan.get("slots", []) as Array):
		var btype: String = String(sl.get("type", ""))
		if btype != "" and SimBuildings.faction_may_build(btype, faction):
			add.call(SimBuildings.cost_of(btype))
	return costs


## Fort records of one faction, each with "hid" (hall id) added.
## Returns [] when the system isn't wired (bare tests, old saves).
func forts_of(faction: String) -> Array:
	var out: Array = []
	for hid: Variant in forts.keys():
		var rec: Dictionary = (forts[hid] as Dictionary).duplicate()
		if String(rec.get("faction", "")) != faction:
			continue
		rec["hid"] = int(hid)
		out.append(rec)
	return out


## Current holder per fort (hall id -> faction), derived from live town
## ownership so a captured fort follows its town in war scoring.
func fort_holders() -> Dictionary:
	var out := {}
	for hid: Variant in forts.keys():
		var rec := forts[hid] as Dictionary
		var t: Dictionary = (_gs.towns as Dictionary).get(
			int(rec.get("town_id", -1)), {})
		out[int(hid)] = str(t.get("faction", rec.get("faction", "")))
	return out


## Garrison home for a faction: its first star-fort center (a star fort IS
## the military base). Vector2.INF when the faction has no fort.
func fort_home(faction: String) -> Vector2:
	for hid: Variant in forts.keys():
		var rec := forts[hid] as Dictionary
		if String(rec.get("faction", "")) == faction:
			return rec.get("center", Vector2.INF)
	return Vector2.INF


## Garrison + artillery report per fort: [{hid, center, town_id, troops,
## by_job, artillery}]. Troops = alive military-job units inside the fort
## yard; artillery = alive vehicles of the faction inside the yard.
func garrison_report(faction: String) -> Array:
	var out: Array = []
	var artsys = _gs.get("arty")
	for rec: Dictionary in forts_of(faction):
		var center: Vector2 = rec.get("center", Vector2.ZERO)
		var by_job := {}
		var troops := 0
		for u: Dictionary in _gs.units:
			if not bool(u.get("alive", false)):
				continue
			if String(u.get("faction", "")) != faction:
				continue
			if not JobDefs.is_military(String(u.get("job", ""))):
				continue
			var d: float = (u.get("position", Vector2.ZERO) as Vector2) \
				.distance_to(center)
			if d > FORT_YARD_R:
				continue
			troops += 1
			var j: String = String(u.get("job", ""))
			by_job[j] = int(by_job.get(j, 0)) + 1
		var arty := 0
		if artsys != null and artsys.has_method("vehicles_of"):
			for v: Dictionary in artsys.vehicles_of(faction):
				var dv: float = (v.get("position", Vector2.ZERO) as Vector2) \
					.distance_to(center)
				if dv <= FORT_YARD_R:
					arty += 1
		out.append({"hid": int(rec.get("hid", -1)), "center": center,
			"town_id": int(rec.get("town_id", -1)),
			"troops": troops, "by_job": by_job, "artillery": arty})
	return out


## Explicit fort order (Ruler's Voice): one fort for a single hall, skipping
## the military-presence gate and the AI cooldown — the player said the
## word, so it breaks ground if there's clear land and coin.
## Returns {ok, reason, buildings, fort, cost?}; reasons: has_fort, no_spot,
## broke, commit_failed.
func order_fort(faction: String, hall_id: int, town_id: int,
		hall_pos: Vector2, bs: SimBuildings, wall_drag: WallDrag) -> Dictionary:
	if forts.has(hall_id):
		return {"ok": false, "reason": "has_fort", "buildings": [],
			"fort": {}}
	var spot := _find_spot(faction, hall_pos)
	if spot == Vector2.INF:
		return {"ok": false, "reason": "no_spot", "buildings": [], "fort": {}}
	var plan: Dictionary = StarFort.plan(spot)
	var cost := estimate_fort_cost(faction, plan)
	if not _can_afford(faction, cost):
		return {"ok": false, "reason": "broke", "buildings": [],
			"fort": {}, "cost": cost}
	var res: Dictionary = StarFort.new().commit(
		_gs, bs, plan, faction, town_id, wall_drag)
	var placed: Array = res.get("buildings", [])
	if placed.is_empty():
		return {"ok": false, "reason": "commit_failed", "buildings": [],
			"fort": {}}
	var rec := {"center": spot, "radius": StarFort.DEFAULT_RADIUS,
		"faction": faction, "town_id": town_id}
	forts[hall_id] = rec
	return {"ok": true, "reason": "", "buildings": placed, "fort": rec}


func _can_afford(faction: String, costs: Dictionary) -> bool:
	for r: String in costs.keys():
		if float(_gs.resources.get_amount(faction, r)) < float(costs[r]):
			return false
	return true
