class_name WallDrag
extends RefCounted
## Cursing Gnomes — AoE2-style drag-to-place wall system (Milestone 3b).
##
## Ported from the HTML's WallPlacementSystem / SegmentedConstructionSystem
## (not its code). Mechanics:
##   - Press-hold-release: a chain of wall segments is planned along the
##     drag line; release commits each segment as its own blueprint entity
##     (own HP, progress, construction state) — they build in stages like
##     every other building via SimBuildings.tick_construction.
##   - Segments are spaced SEG_LEN = 44px apart. Segment boundaries are
##     computed as A + dir * (i * SEG_LEN) (multiply, never accumulate) and
##     legs share verbatim endpoint coords so neighbors line up exactly.
##   - Drag ends snap to existing walls/towers within SNAP_DIST = 78px.
##   - A tap (no drag) places ONE full segment: 8 headings are tried from
##     the tap point and the first valid plan commits (snapped starts share
##     the endpoint, so tapping a run tip extends it).
##   - Each segment is charged individually; the commit stops at the first
##     unaffordable segment (HTML commitSegmentPlan behavior).
##
## Pure sim — the press/drag/release input wiring lives in the placement
## owner (building_placement.gd); see the HOOK note in the class docstring
## at the bottom.


## Segment spacing in px (HTML SegmentedConstructionSystem segLen).
const SEG_LEN := 44.0

## Endpoint snap radius in px (HTML snapDist).
const SNAP_DIST := 78.0

## Longest single drag in px (HTML maxDist).
const MAX_DIST := 4000.0

## Blueprint overlap radius for a segment endpoint check.
const SEG_RADIUS := 12.0


var _seq := 0


## Plans a wall run from start to end. Returns a plan dict:
##   {run_id, start, end, angle, segments: [{x0,y0,x1,y1,valid}], valid_count,
##    per_segment_cost: Dictionary, total_cost: Dictionary}
## "buildings" is the live building list (for overlap/snap), "map_rect"
## the legal area. Deterministic: no randomness, no clock.
static func plan_path(start: Vector2, end: Vector2, buildings: Array,
		faction: String, map_rect: Rect2, max_dist: float = MAX_DIST) -> Dictionary:
	var s: Vector2 = _snap_endpoint(start, buildings, faction)
	var e: Vector2 = _snap_endpoint(end, buildings, faction)
	var dir: Vector2 = e - s
	var dist: float = dir.length()
	if dist < 1.0:
		return {"segments": [], "valid_count": 0, "run_id": "",
			"start": s, "end": e, "angle": 0.0,
			"per_segment_cost": SimBuildings.cost_of("wall"),
			"total_cost": {}}
	if dist > max_dist:
		e = s + dir.normalized() * max_dist
		dir = e - s
		dist = max_dist
	var angle: float = dir.angle()
	var n: int = maxi(1, int(round(dist / SEG_LEN)))
	var segs: Array = []
	var per_seg: Dictionary = SimBuildings.cost_of("wall")
	for i: int in range(n):
		var x0: Vector2 = s if i == 0 else s + dir.normalized() * (float(i) * SEG_LEN)
		var x1: Vector2 = e if i == n - 1 else s + dir.normalized() * (float(i + 1) * SEG_LEN)
		var mid: Vector2 = (x0 + x1) * 0.5
		var valid := true
		if not map_rect.has_point(mid):
			valid = false
		elif not _segment_free(buildings, mid):
			valid = false
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


## Plans a polyline wall run (a list of points): each leg is planned like
## plan_path and the legs' segments are merged into one run. Used by the
## star fort and the border-wall AI (rings that are NOT straight lines).
## Ends never chord across the polyline — the polyline is the wall.
static func plan_polyline(pts: Array, buildings: Array, faction: String,
		map_rect: Rect2, max_dist: float = MAX_DIST) -> Dictionary:
	var segs: Array = []
	var total := {}
	var start := Vector2.ZERO
	var end := Vector2.ZERO
	var angle := 0.0
	if pts.size() >= 2:
		start = pts[0]
		end = pts[pts.size() - 1]
		var remaining := max_dist
		for i: int in range(pts.size() - 1):
			var leg: Dictionary = plan_path(pts[i], pts[i + 1], buildings,
				faction, map_rect, remaining)
			angle = float(leg.get("angle", 0.0))
			for sg: Dictionary in leg.get("segments", []):
				segs.append(sg)
			remaining = maxf(0.0, remaining - (pts[i] as Vector2).distance_to(pts[i + 1]))
			if remaining <= 0.0:
				break
	var valid_count := 0
	var per_seg: Dictionary = SimBuildings.cost_of("wall")
	for sg: Dictionary in segs:
		if bool(sg.get("valid", false)):
			valid_count += 1
	total = _scale_cost(per_seg, valid_count)
	return {"run_id": "", "start": start, "end": end, "angle": angle,
		"segments": segs, "valid_count": valid_count,
		"per_segment_cost": per_seg, "total_cost": total}


## Tap = one segment: tries 8 headings from the tap point and returns the
## first plan with exactly one valid segment ({} when none plans valid).
static func plan_tap(pos: Vector2, buildings: Array, faction: String,
		map_rect: Rect2) -> Dictionary:
	for t: int in range(8):
		var a: float = float(t) * PI / 4.0
		var plan: Dictionary = plan_path(pos, pos + Vector2(cos(a), sin(a)) * SEG_LEN,
			buildings, faction, map_rect, SEG_LEN)
		if int(plan.get("valid_count", 0)) == 1 \
				and (plan.get("segments", []) as Array).size() == 1:
			return plan
	return {}


## Commits a plan: each valid segment becomes a "wall" blueprint placed via
## SimBuildings.place_blueprint (resources charged per segment, construction
## stages like every other building). Tags every record with wall_run_id,
## wall_angle, and ai_wall when opts says so. Stops at the first segment
## place_blueprint refuses (unaffordable / cap / enemy territory).
## Returns {placed: Array[Dictionary], run_id: String}.
func commit(bs: SimBuildings, plan: Dictionary, faction: String, town_id: int,
		opts: Dictionary = {}) -> Dictionary:
	var placed: Array = []
	_seq += 1
	var run_id: String = String(opts.get("run_id", ""))
	if run_id == "":
		run_id = "wall_%s_%d" % [faction, _seq]
	plan["run_id"] = run_id
	for sg: Dictionary in plan.get("segments", []):
		if not bool(sg.get("valid", false)):
			continue
		var mid := Vector2(float(sg.get("x0", 0.0)) + float(sg.get("x1", 0.0)),
			float(sg.get("y0", 0.0)) + float(sg.get("y1", 0.0))) * 0.5
		var b: Dictionary = bs.place_blueprint("wall", faction, town_id, mid)
		if b.is_empty():
			break
		b["wall_run_id"] = run_id
		b["wall_angle"] = float(plan.get("angle", 0.0))
		if bool(opts.get("ai_wall", false)):
			b["ai_wall"] = true
		if opts.has("fort_plan"):
			b["fort_plan"] = String(opts.get("fort_plan", ""))
		placed.append(b)
	return {"placed": placed, "run_id": run_id}


## Snaps an endpoint to the nearest existing wall/tower within SNAP_DIST.
static func _snap_endpoint(p: Vector2, buildings: Array, faction: String) -> Vector2:
	var best := p
	var best_d := SNAP_DIST
	for b: Dictionary in buildings:
		if not b.get("alive", false):
			continue
		var t: String = String(b.get("type", ""))
		if not t in ["wall", "guard_tower", "aa_tower", "fence"]:
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var d: float = p.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b.get("position", Vector2.ZERO)
	return best


## A segment is free when its midpoint doesn't collide with non-wall
## buildings (walls and fences chain freely).
static func _segment_free(buildings: Array, mid: Vector2) -> bool:
	for b: Dictionary in buildings:
		if not b.get("alive", false):
			continue
		var t: String = String(b.get("type", ""))
		if t == "wall" or t == "fence":
			continue
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		var br: float = SimBuildings.footprint(t)
		if mid.distance_to(bp) < SEG_RADIUS + br:
			return false
	return true


static func _scale_cost(cost: Dictionary, n: int) -> Dictionary:
	var out := {}
	for k: String in cost.keys():
		out[k] = float(cost[k]) * float(n)
	return out


## HOOK (placement/input owner):
## In building_placement.gd (or the camera tap router), when the active
## build type is "wall": on press start, remember the world point; on
## drag-move call WallDrag.plan_path(press, current, game.buildings,
## player_faction, map_rect) and draw plan["segments"] as the preview
## (invalid segments red); on release call wall_drag.commit(buildings_sys,
## plan, player_faction, town_id, {}) — then clear. A tap with no drag
## calls WallDrag.plan_tap(pos, ...) and commits the returned plan.
