class_name WaterNav
extends RefCounted
## Cursing Gnomes — water navigation rules (Jeremy 2026-10-05, Oblivion/
## Skyrim-style): land animals and NPCs steer around water; fleeing
## creatures may enter it; vehicles never do.
##
## All checks are O(1) terrain lookups — safe on the per-tick hot path.
## Steering deflects along the shoreline (x-only / y-only slides, like
## Cliffs.try_step) so movers never vibrate against the shore.


## True when the world position sits on a water tile (lake / river /
## waterfall). O(1): one dict get + one byte-array index.
static func is_water_at(map_data: Dictionary, pos: Vector2) -> bool:
	var terrain = map_data.get("terrain", null)
	if terrain == null or (terrain is PackedByteArray and terrain.is_empty()):
		return false
	var tpx := float(map_data.get("tile_size", 32.0))
	if tpx <= 0.0:
		return false
	var size: Vector2i = map_data.get("size_tiles", Vector2i(128, 128))
	var tx := int(pos.x / tpx)
	var ty := int(pos.y / tpx)
	if tx < 0 or ty < 0 or tx >= size.x or ty >= size.y:
		return false
	var idx := ty * size.x + tx
	if idx < 0 or idx >= (terrain as PackedByteArray).size():
		return false
	return MapGen.is_water(int((terrain as PackedByteArray)[idx]))


## Zero-dictionary-get version of is_water_at for the movement hot path
## (perf R35). Identical result to is_water_at(map_data, pos) when
## terrain/sx/sy/tile are the values is_water_at would read from that
## map_data — same defaults (size_tiles (128,128), tile_size 32.0), same
## guard order (empty -> false, tile <= 0 -> false, out-of-bounds ->
## false). Callers hoist these once per nav build (SimPathfinder._build_nav).
static func is_water_at_fast(terrain: PackedByteArray, sx: int, sy: int,
		tile: float, pos: Vector2) -> bool:
	if terrain.is_empty():
		return false
	if tile <= 0.0:
		return false
	if sx <= 0 or sy <= 0:
		return false
	var tx := int(pos.x / tile)
	var ty := int(pos.y / tile)
	if tx < 0 or ty < 0 or tx >= sx or ty >= sy:
		return false
	var idx := ty * sx + tx
	if idx < 0 or idx >= terrain.size():
		return false
	return MapGen.is_water(int(terrain[idx]))


## Step that refuses to enter water: full step, then x-only / y-only
## shoreline slides, then stay put. Mirrors Cliffs.try_step's shape.
static func dry_step(map_data: Dictionary, pos: Vector2,
		step: Vector2) -> Vector2:
	# Already wet: keep moving (don't trap a swimmer that shouldn't be
	# there) — avoidance only blocks ENTERING water.
	if is_water_at(map_data, pos):
		return pos + step
	var full: Vector2 = pos + step
	if not is_water_at(map_data, full):
		return full
	var x_only := Vector2(pos.x + step.x, pos.y)
	if not is_water_at(map_data, x_only):
		return x_only
	var y_only := Vector2(pos.x, pos.y + step.y)
	if not is_water_at(map_data, y_only):
		return y_only
	return pos


## Wider shoreline probe for vehicles: tries the direct heading plus
## ±35° / ±70° deflections, returning the first dry landing, or pos
## (hold) when boxed in. Vehicles never enter water, even fleeing.
static func dry_step_vehicle(map_data: Dictionary, pos: Vector2,
		heading: Vector2, dist: float) -> Vector2:
	if heading.length_squared() < 0.0001:
		return pos
	var dir: Vector2 = heading.normalized()
	for ang in [0.0, 0.61, -0.61, 1.22, -1.22]:
		var landing: Vector2 = pos + dir.rotated(ang) * dist
		if not is_water_at(map_data, landing):
			return landing
	return pos


## Land-animal rule: may enter water only when fleeing (running) or when
## the type likes water (water_liking registry flag — ducks, beavers…).
static func animal_avoids_water(an: Dictionary, type_stats: Dictionary) -> bool:
	if bool(an.get("running", false)):
		return false
	if bool(type_stats.get("water_liking", false)):
		return false
	return true


## NPC rule: fleeing units may swim; naval jobs belong on water; everyone
## else steers around it.
static func unit_avoids_water(unit: Dictionary) -> bool:
	if bool(unit.get("fleeing", false)):
		return false
	if SimBuildings.BOAT_JOBS.has(String(unit.get("job", ""))):
		return false
	return true
