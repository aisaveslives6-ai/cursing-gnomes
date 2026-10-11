class_name BridgeDrag
extends RefCounted
## Cursing Gnomes — drag-to-place bridge tool (HTML bridge_drag).
##
## Ported from the HTML's bridge placement (not its code). Mechanics:
##   - Press-hold-release: a chain of bridge segments is planned along the
##     drag line; release commits each segment as its own blueprint entity
##     (own HP, progress, construction state) — they build in stages like
##     every other building via SimBuildings.tick_construction.
##   - Segments are spaced SEG_LEN = 30px apart. Deck length is 78px, so
##     neighbors overlap into one continuous span (HTML drawBridgeDeck).
##   - Placement rules (HTML canPlaceBridge): inside the map with a 70px
##     margin, near water (within 80px), no bridge within 26px, and no other
##     building within (size*0.7 + 24)px. Bridges are exempt from the
##     enemy-territory rule (canPlaceBridge has none) and chain with other
##     bridges (see SimBuildings.can_place_at).
##   - Completed decks are walkable: SimBuildings.bridge_at() returns the
##     deck under a point within 34px ("walk here, don't swim").
##
## The pure sim has no map/water handle, so the water rule takes an
## optional `water_at` Callable: water_at.call(pos: Vector2) -> bool, true
## when water lies within 80px of pos. An invalid Callable skips the water
## rule (documented; the placement owner passes the real one).
##
## Pure sim — the press/drag/release input wiring lives in the placement
## owner (building_placement.gd); see the HOOK note at the bottom.


## Segment spacing in px (HTML bridge drag: segments every 30px).
const SEG_LEN := 30.0

## Longest single drag in px (mirrors WallDrag).
const MAX_DIST := 4000.0


var _seq := 0


## True when a bridge segment may be placed at pos (HTML canPlaceBridge).
## "buildings" is the live building list; water_at is the water probe
## described above (invalid Callable = water rule skipped).
static func can_place_bridge(buildings: Array, pos: Vector2,
		map_rect: Rect2, water_at: Callable = Callable()) -> bool:
	# 70px margin off the map edges.
	if not map_rect.grow(-SimBuildings.BRIDGE_MAP_MARGIN).has_point(pos):
		return false
	# Bridges go over water.
	if water_at.is_valid() and not bool(water_at.call(pos)):
		return false
	for b: Dictionary in buildings:
		if not b.get("alive", false):
			continue
		var bt: String = String(b.get("type", ""))
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		if bt == "bridge":
			if pos.distance_to(bp) < SimBuildings.BRIDGE_STACK_DIST:
				return false
			continue
		if pos.distance_to(bp) \
				< SimBuildings.footprint(bt) * 0.7 \
				+ SimBuildings.BRIDGE_OVERLAP_PAD:
			return false
	return true


## Plans a bridge run from start to end. Returns a plan dict:
##   {run_id, start, end, angle, segments: [{x0,y0,x1,y1,valid}], valid_count,
##    per_segment_cost: Dictionary, total_cost: Dictionary}
## Deterministic: no randomness, no clock.
static func plan_path(start: Vector2, end: Vector2, buildings: Array,
		map_rect: Rect2, water_at: Callable = Callable(),
		max_dist: float = MAX_DIST) -> Dictionary:
	var s: Vector2 = start
	var e: Vector2 = end
	var dir: Vector2 = e - s
	var dist: float = dir.length()
	if dist < 1.0:
		return {"segments": [], "valid_count": 0, "run_id": "",
			"start": s, "end": e, "angle": 0.0,
			"per_segment_cost": SimBuildings.cost_of("bridge"),
			"total_cost": {}}
	if dist > max_dist:
		e = s + dir.normalized() * max_dist
		dir = e - s
		dist = max_dist
	var angle: float = dir.angle()
	var n: int = maxi(1, int(round(dist / SEG_LEN)))
	var segs: Array = []
	var per_seg: Dictionary = SimBuildings.cost_of("bridge")
	for i: int in range(n):
		var x0: Vector2 = s if i == 0 \
			else s + dir.normalized() * (float(i) * SEG_LEN)
		var x1: Vector2 = e if i == n - 1 \
			else s + dir.normalized() * (float(i + 1) * SEG_LEN)
		var mid: Vector2 = (x0 + x1) * 0.5
		var valid: bool = can_place_bridge(buildings, mid, map_rect, water_at)
		segs.append({"x0": x0.x, "y0": x0.y, "x1": x1.x, "y1": x1.y,
			"valid": valid})
	var valid_count := 0
	for sg: Dictionary in segs:
		if bool(sg.get("valid", false)):
			valid_count += 1
	return {
		"run_id": "",
		"start": s, "end": e, "angle": angle,
		"segments": segs,
		"valid_count": valid_count,
		"per_segment_cost": per_seg,
		"total_cost": _scale_cost(per_seg, valid_count),
	}


## Tap = one segment: tries 8 headings from the tap point and returns the
## first plan with exactly one valid segment ({} when none plans valid).
static func plan_tap(pos: Vector2, buildings: Array, map_rect: Rect2,
		water_at: Callable = Callable()) -> Dictionary:
	for t: int in range(8):
		var a: float = float(t) * PI / 4.0
		var plan: Dictionary = plan_path(pos,
			pos + Vector2(cos(a), sin(a)) * SEG_LEN,
			buildings, map_rect, water_at, SEG_LEN)
		if int(plan.get("valid_count", 0)) == 1 \
				and (plan.get("segments", []) as Array).size() == 1:
			return plan
	return {}


## Commits a plan: each valid segment becomes a "bridge" blueprint placed
## via SimBuildings.place_blueprint (resources charged per segment,
## construction stages like every other building). Tags every record with
## bridge_run_id and bridge_angle. Stops at the first segment
## place_blueprint refuses (unaffordable / cap).
## Returns {placed: Array[Dictionary], run_id: String}.
func commit(bs: SimBuildings, plan: Dictionary, faction: String, town_id: int,
		opts: Dictionary = {}) -> Dictionary:
	var placed: Array = []
	_seq += 1
	var run_id: String = String(opts.get("run_id", ""))
	if run_id == "":
		run_id = "bridge_%s_%d" % [faction, _seq]
	plan["run_id"] = run_id
	for sg: Dictionary in plan.get("segments", []):
		if not bool(sg.get("valid", false)):
			continue
		var mid := Vector2(float(sg.get("x0", 0.0)) + float(sg.get("x1", 0.0)),
			float(sg.get("y0", 0.0)) + float(sg.get("y1", 0.0))) * 0.5
		var b: Dictionary = bs.place_blueprint("bridge", faction, town_id, mid)
		if b.is_empty():
			break
		b["bridge_run_id"] = run_id
		b["bridge_angle"] = float(plan.get("angle", 0.0))
		placed.append(b)
	return {"placed": placed, "run_id": run_id}


static func _scale_cost(cost: Dictionary, n: int) -> Dictionary:
	var out := {}
	for k: String in cost.keys():
		out[k] = float(cost[k]) * float(n)
	return out


## HOOK (placement/input owner):
## In building_placement.gd (or the camera tap router), when the active
## build type is "bridge_drag": on press start, remember the world point;
## on drag-move call BridgeDrag.plan_path(press, current, game.buildings,
## map_rect, water_probe) and draw plan["segments"] as the preview
## (invalid segments red); on release call bridge_drag.commit(buildings_sys,
## plan, player_faction, town_id, {}) — then clear. A tap with no drag calls
## BridgeDrag.plan_tap(pos, ...) and commits the returned plan. The
## water_probe Callable maps a world pos to "water within 80px" (HTML
## nearWaterAt(x, y, 80)). The build menu offers this under the Roads tab
## as 🌉 "Bridge (drag over water)" (HTML PLAYER_BUILDABLES).
