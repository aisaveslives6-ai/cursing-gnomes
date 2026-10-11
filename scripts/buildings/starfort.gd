class_name StarFort
extends RefCounted
## Cursing Gnomes — star-fort military bases (Milestone 3b).
##
## Jeremy's rule (2026-09-26): military bases are enclosed by DISTINCT wall
## formations — star forts — with OPENINGS in the walls so soldiers can exit
## (never the same tight wall rings used for towns), and the walls are pushed
## well out from the base buildings.
##
## Ported from the HTML FORT_PLANS entry
##   { id: 'star', name: 'Star Fortress', shape: 'star', gateSides: 4,
##     cornerTowers: true, step: 46 }
## and MILITARY_BASE_PLANS.star_fort (the building slots). "Gates" were
## deleted game-wide — the 4 gate sides are GAPS in the wall with a dirt
## road routed through each (passages are gaps with roads).
##
## Layout: a 5-point star (bastion tips at radius R, re-entrant corners at
## 0.62R), walls traced at ~46px steps, one gap per gate side, a guard
## tower blueprint on each bastion tip, and the 9 base buildings from the
## HTML star_fort slots placed inside the star.
##
## Pure sim — rendering and construction progress live elsewhere.


## Gate sides -> gaps with roads (never gate buildings).
const GATE_SIDES := 4

## Bastion tips on the star.
const BASTIONS := 5

## Re-entrant corner radius as a fraction of the tip radius.
const INNER_RATIO := 0.62

## Wall trace step in px (HTML step: 46).
const STEP := 46.0

## Default wall radius: pushed well out past the base slots (the HTML
## star_fort slots reach r~128; the fort ring sits clearly outside them).
const DEFAULT_RADIUS := 170.0

## Gap width in px at each gate side (passage for soldiers + dirt road).
const GAP_PX := 110.0

## Ring resampling step for gap cutting. The wall polyline is resampled
## FINELY here (not at STEP): with STEP=46 sampling, each 110px gap
## swallowed whole 105px star edges, leaving only 2-3-point wall stubs
## instead of a ring. WallDrag re-segments at its own 44px SEG_LEN anyway.
const RESAMPLE := 12.0


## The 9 base buildings inside the star (HTML MILITARY_BASE_PLANS.star_fort
## slots, verbatim offsets from fort center).
static func base_slots() -> Array:
	return [
		{"type": "barracks", "dx": 0.0, "dy": -40.0},
		{"type": "barracks", "dx": -70.0, "dy": 30.0},
		{"type": "medic_camp", "dx": 70.0, "dy": 30.0},
		{"type": "aa_tower", "dx": -100.0, "dy": -80.0},
		{"type": "aa_tower", "dx": 100.0, "dy": -80.0},
		{"type": "aa_tower", "dx": 0.0, "dy": 100.0},
		{"type": "cannon_foundry", "dx": 0.0, "dy": 50.0},
		{"type": "storage", "dx": -50.0, "dy": 80.0},
		{"type": "equip_camp", "dx": 50.0, "dy": 80.0},
	]


## Star ring points: alternating bastion tips (R) and re-entrant corners
## (R*INNER_RATIO), traced in order. Returns Array[Vector2].
static func star_ring(center: Vector2, radius: float,
		bastions: int = BASTIONS) -> Array:
	var pts: Array = []
	var n: int = bastions * 2
	for i: int in range(n):
		var r: float = radius if i % 2 == 0 else radius * INNER_RATIO
		var a: float = float(i) / float(n) * TAU - PI / 2.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


## Full star-fort plan. Returns:
##   {wall_pts: Array[Vector2] (star ring with 4 gaps, polyline order),
##    tower_pts: Array[Vector2] (bastion tips -> guard tower blueprints),
##    slots: Array (base buildings, with world x/y filled),
##    roads: Array (one {x1,y1,x2,y2} dirt road per gap)}
static func plan(center: Vector2, radius: float = DEFAULT_RADIUS) -> Dictionary:
	var ring: Array = star_ring(center, radius)
	var perim := 0.0
	var edge_lens: Array = []
	for i: int in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		var l: float = a.distance_to(b)
		edge_lens.append(l)
		perim += l
	# Resample the ring at RESAMPLE px into arc-length-parameterized points.
	# (Fine sampling: gap cutting at wall-segment granularity left stubs.)
	var dense: Array = []  # {p: Vector2, s: float}
	var s := 0.0
	for i: int in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		var l: float = edge_lens[i]
		var steps: int = maxi(1, int(round(l / RESAMPLE)))
		for k: int in range(steps):
			var f: float = float(k) / float(steps)
			dense.append({"p": a.lerp(b, f), "s": s + l * f})
		s += l
	# Four gaps, one per gate side. Gap centers sit on EDGE MIDPOINTS of
	# maximally-spread ring edges (never near bastion tips): with 5
	# bastions, evenly spaced (g+0.5)/4 centers land 26px from a tip and
	# the 110px gap swallows it — along with its guard tower's footing.
	# Greedy max-min-separation pick over the ring edges.
	var edge_count := ring.size()
	var chosen: Array = [0]
	while chosen.size() < GATE_SIDES:
		var best_i := -1
		var best_sep := -1
		for i in range(edge_count):
			if i in chosen:
				continue
			var sep := edge_count
			for c in chosen:
				var d: int = absi(i - int(c))
				sep = mini(sep, mini(d, edge_count - d))
			if sep > best_sep:
				best_sep = sep
				best_i = i
		chosen.append(best_i)
	var gap_centers: Array = []
	for e in chosen:
		gap_centers.append(perim * (float(e) + 0.5) / float(edge_count))
	var half: float = GAP_PX * 0.5
	var in_gap := []
	for d: Dictionary in dense:
		var ds: float = float(d["s"])
		var hit := false
		for gc: float in gap_centers:
			var dd: float = absf(ds - gc)
			dd = minf(dd, perim - dd)
			if dd <= half:
				hit = true
				break
		in_gap.append(hit)
	# Keep contiguous runs between gaps, in ring order (no chord across gaps).
	var runs: Array = []
	var cur: Array = []
	for i: int in range(dense.size()):
		if bool(in_gap[i]):
			if cur.size() >= 2:
				runs.append(cur)
			cur = []
		else:
			cur.append((dense[i] as Dictionary)["p"])
	if cur.size() >= 2:
		runs.append(cur)
	# Wrap: merge last run into first when the ring start/end are both kept
	# (the gap list is cyclic, so first and last runs join into one run).
	if runs.size() >= 2 and not bool(in_gap[0]) \
			and not bool(in_gap[dense.size() - 1]):
		var first: Array = runs[0]
		var last: Array = runs.pop_back()
		last.append_array(first)
		runs[0] = last
	var wall_pts: Array = []
	for r2: Array in runs:
		wall_pts.append_array(r2)
	# Roads through the gaps: radial-ish lines along the ring tangent.
	var roads: Array = []
	for g2: int in range(GATE_SIDES):
		var gc2: float = gap_centers[g2]
		var best: Vector2 = center
		var best_d := INF
		for d2: Dictionary in dense:
			var dd2: float = absf(float(d2["s"]) - gc2)
			dd2 = minf(dd2, perim - dd2)
			if dd2 < best_d:
				best_d = dd2
				best = (d2 as Dictionary)["p"]
		var out_dir: Vector2 = (best - center).normalized()
		roads.append({
			"x1": best.x - out_dir.x * 170.0, "y1": best.y - out_dir.y * 170.0,
			"x2": best.x + out_dir.x * 170.0, "y2": best.y + out_dir.y * 170.0,
		})
	var towers: Array = []
	for i: int in range(BASTIONS):
		towers.append(ring[i * 2])
	var slots: Array = []
	for sl: Dictionary in base_slots():
		var c2: Dictionary = sl.duplicate()
		c2["x"] = center.x + float(sl["dx"])
		c2["y"] = center.y + float(sl["dy"])
		slots.append(c2)
	return {"wall_pts": wall_pts, "tower_pts": towers, "slots": slots,
		"roads": roads, "center": center, "radius": radius}


## Commits a star-fort plan: guard towers on the bastion tips, wall segments
## along the ring (via WallDrag, staged construction), and base-building
## blueprints inside. Paints a military district zone around the site.
## Returns {buildings: Array, zone: Dictionary}.
func commit(gs, bs: SimBuildings, plan: Dictionary, faction: String,
		town_id: int, wall_drag: WallDrag) -> Dictionary:
	var made: Array = []
	var center: Vector2 = plan.get("center", Vector2.ZERO)
	var radius: float = float(plan.get("radius", DEFAULT_RADIUS))
	# Military district: the star fort IS the military district.
	var zone := {}
	if gs.zoning != null:
		zone = gs.zoning.paint_zone(SimZoning.MILITARY, faction,
			Rect2(center - Vector2(radius, radius) * 1.35,
				Vector2(radius, radius) * 2.7))
	# Wall runs (gap-separated already; each run follows the ring polyline).
	var run_pts: Array = []
	var last := Vector2.INF
	for p: Vector2 in plan.get("wall_pts", []):
		if run_pts.is_empty() or last.distance_to(p) < STEP * 1.75:
			run_pts.append(p)
		else:
			_commit_run(gs, bs, wall_drag, run_pts, faction, town_id, made)
			run_pts = [p]
		last = p
	if run_pts.size() >= 2:
		_commit_run(gs, bs, wall_drag, run_pts, faction, town_id, made)
	# Corner towers on the bastion tips.
	for tp: Vector2 in plan.get("tower_pts", []):
		var t: Dictionary = bs.place_blueprint("guard_tower", faction, town_id, tp)
		if not t.is_empty():
			t["fort_plan"] = "star"
			made.append(t)
	# Base buildings inside the star.
	for sl: Dictionary in plan.get("slots", []):
		var btype: String = String(sl.get("type", "barracks"))
		if not SimBuildings.faction_may_build(btype, faction):
			continue
		var b: Dictionary = bs.place_blueprint(btype, faction, town_id,
			Vector2(float(sl.get("x", 0.0)), float(sl.get("y", 0.0))))
		if not b.is_empty():
			b["fort_plan"] = "star"
			made.append(b)
	return {"buildings": made, "zone": zone}


func _commit_run(gs, bs: SimBuildings, wall_drag: WallDrag, pts: Array,
		faction: String, town_id: int, made: Array) -> void:
	if pts.size() < 2:
		return
	var plan: Dictionary = WallDrag.plan_polyline(pts, gs.buildings, faction,
		Rect2(-100000, -100000, 200000, 200000))
	var res: Dictionary = wall_drag.commit(bs, plan, faction, town_id,
		{"ai_wall": true, "fort_plan": "star"})
	for b: Dictionary in res.get("placed", []):
		made.append(b)
