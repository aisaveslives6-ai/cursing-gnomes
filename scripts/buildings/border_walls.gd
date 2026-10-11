class_name BorderWalls
extends RefCounted
## Cursing Gnomes — territorial AI border walls (Milestone 3b).
##
## Ported from the HTML's TERRITORIAL AI WALLING (2026-09-19 biome-border
## rewrite) and the ask-once raise policy (not its code). Jeremy's direction:
## the AI walls its LAND, not its cities — border rings far from towns with
## a generated opening + dirt road through each, never any wall inside a
## town center.
##
## Mechanics ported:
##   - Each named region (SimTerritory.compute_regions) gets a boundary ring.
##     Ring points stand off EVERY alive hall by WALL_TOWN_STANDOFF = 1400px
##     ("like a mile out of town"); points that can't get clear are dropped
##     so the line routes AROUND towns instead of through them.
##   - ONE generated opening per ring (~180px, OPEN_HALF = 90 arc-px) facing
##     the nearest neighboring region's center; a dirt road is routed through
##     the gap (endpoints ±340px along the radial).
##   - Long rings are chunked into ~1100px affordable commits.
##   - ONE clean wall line per shared border: the first region to commit a
##     border wins; the neighbor's matching run is skipped (borderKey).
##   - Anti-spam: at most 240 live AI wall pieces per race; breached spans of
##     tracked runs are topped up on later passes.
##   - ASK-ONCE policy (2026-09-19): the PLAYER is asked once per region.
##     Raise = future runs for that region auto-commit without prompting;
##     Skip = never asked again. Survives save/load; resets on new game.
##   - GATES were deleted: passages are gaps with roads, nothing else.
##
## The HTML traced the region's actual boundary polygon via regionAt() ray
## marching; Godot has no pixel-region system, so the ring is a circle at
## max(hall spread + TERRITORY_R, standoff) — same standoff/opening/chunk
## semantics, same policy surface.
##
## Pure sim — the player prompt modal is the UI owner's job; it drains
## pending[] and calls answer(region_name, raise).


## Live AI wall pieces per race before the AI stands down (HTML cap).
const AI_WALL_PIECE_CAP := 240

## Ring points are repelled from every alive hall until this far clear.
const WALL_TOWN_STANDOFF := 1400.0

## Opening half-width in arc-px -> ~180px gap (HTML OPEN_HALF).
const OPEN_HALF := 90.0

## Long runs are chunked into commits of at most this many px (HTML CHUNK).
const CHUNK := 1100.0

## Road half-length through the gap, px (HTML ±340).
const ROAD_HALF := 340.0

## Seconds between AI passes per faction (HTML callers throttled at
## 240/300-frame ticks).
const TICK_INTERVAL := 20.0

## Seconds of cooldown after hitting the anti-spam cap (HTML 900 frames).
const CAP_COOLDOWN := 15.0

## Ring sample count (HTML resampled to ~80px spacing).
const RING_SAMPLES := 64


var _gs  # GameState (untyped: avoids a cyclic class reference)

## Ask-once policy: region name -> "raise" | "skip". Save me.
var policy: Dictionary = {}

## Player prompt queue: Array of {region_name, faction, cost: Dictionary,
## runs: Array of {pts: Array[Vector2], road: Dictionary, border_key: String}}.
var pending: Array = []

## Shared borders already walled: border_key -> run_id. Save me.
var borders_done: Dictionary = {}

## Tracked AI runs for breach top-up: run_id -> {faction, pts, border_key}.
var runs: Dictionary = {}

## Per-faction next-allowed tick time. Save me.
var cooldowns: Dictionary = {}


func _init(game_state) -> void:
	_gs = game_state


## New game: the ask-once policy resets (HTML: resets on new game).
func reset_for_new_game() -> void:
	policy.clear()
	pending.clear()
	borders_done.clear()
	runs.clear()
	cooldowns.clear()


## Save/load surface (the save owner stores these fields on the snapshot).
func to_dict() -> Dictionary:
	return {
		"policy": policy.duplicate(),
		"borders_done": borders_done.duplicate(),
		"cooldowns": cooldowns.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	policy = (d.get("policy", {}) as Dictionary).duplicate()
	borders_done = (d.get("borders_done", {}) as Dictionary).duplicate()
	cooldowns = (d.get("cooldowns", {}) as Dictionary).duplicate()
	pending.clear()
	runs.clear()


## One AI pass for a faction. AI races auto-commit; the player race goes
## through the ask-once policy (queued into pending[] when unanswered).
func tick(faction: String, is_player: bool, bs: SimBuildings,
		wall_drag: WallDrag) -> void:
	var now: float = float(_gs.game_time)
	if float(cooldowns.get(faction, 0.0)) > now:
		return
	cooldowns[faction] = now + TICK_INTERVAL
	if _count_ai_walls(faction) >= AI_WALL_PIECE_CAP:
		cooldowns[faction] = now + CAP_COOLDOWN
		return
	var halls: Array = SimTerritory.halls_of(_gs.buildings, faction)
	if halls.is_empty():
		return
	if not is_player:
		_top_up(faction, bs, wall_drag)
	var regions: Array = SimTerritory.compute_regions(_gs.buildings)
	for region: Dictionary in regions:
		if String(region.get("race", "")) != faction:
			continue
		_process_region(region, regions, faction, is_player, bs, wall_drag)


## The player's Raise/Skip answer for a region. Raise commits the queued
## runs for that region right away (same commit path as the AI).
func answer(region_name: String, raise: bool, bs: SimBuildings,
		wall_drag: WallDrag) -> void:
	policy[region_name] = "raise" if raise else "skip"
	var keep: Array = []
	for entry: Dictionary in pending:
		if String(entry.get("region_name", "")) != region_name:
			keep.append(entry)
			continue
		if raise:
			_commit_entry(entry, bs, wall_drag)
	pending = keep


## --- internals -------------------------------------------------------------


func _process_region(region: Dictionary, regions: Array, faction: String,
		is_player: bool, bs: SimBuildings, wall_drag: WallDrag) -> void:
	var center := Vector2(float(region.get("cx", 0.0)), float(region.get("cy", 0.0)))
	# Ring radius: hall spread + territory radius, never inside the standoff.
	var r := WALL_TOWN_STANDOFF
	for hid: int in region.get("hall_ids", []):
		var h: Dictionary = _hall_by_id(hid)
		if h.is_empty():
			continue
		r = maxf(r, center.distance_to(h.get("position", Vector2.ZERO)) \
			+ SimTerritory.TERRITORY_R)
	# Sample the ring; repel each point from every alive hall to the standoff.
	var halls: Array = _all_halls()
	var pts: Array = []
	for i: int in range(RING_SAMPLES):
		var a: float = float(i) / float(RING_SAMPLES) * TAU
		var p: Vector2 = center + Vector2(cos(a), sin(a)) * r
		var routed: Variant = _route_around_towns(p, halls)
		if routed != null:
			pts.append(routed)
	if pts.size() < 4:
		return
	# Arc-length parameterize.
	var dense: Array = []
	var perim := 0.0
	for i: int in range(pts.size()):
		var a2: Vector2 = pts[i]
		var b2: Vector2 = pts[(i + 1) % pts.size()]
		dense.append({"p": a2, "s": perim})
		perim += a2.distance_to(b2)
	# Opening faces the nearest neighboring region's center.
	var face := Vector2.RIGHT
	var best_d := INF
	for other: Dictionary in regions:
		if other == region:
			continue
		var oc := Vector2(float(other.get("cx", 0.0)), float(other.get("cy", 0.0)))
		var d: float = center.distance_to(oc)
		if d < best_d:
			best_d = d
			face = (oc - center).normalized()
	var open_s := 0.0
	var open_d := INF
	for d2: Dictionary in dense:
		var p2: Vector2 = (d2 as Dictionary)["p"]
		var dd: float = absf((p2 - center).angle_to(face))
		if dd < open_d:
			open_d = dd
			open_s = float((d2 as Dictionary)["s"])
	# Cut the opening: drop points within OPEN_HALF arc-px, keep ring order,
	# endpoints at the cut so no chord is laid across the gap.
	var kept: Array = []
	var in_win: Array = []
	for d3: Dictionary in dense:
		var ds: float = absf(float((d3 as Dictionary)["s"]) - open_s)
		ds = minf(ds, perim - ds)
		in_win.append(ds <= OPEN_HALF)
	var fwd := 0
	while fwd < dense.size() and bool(in_win[fwd]):
		fwd += 1
	var bwd := dense.size() - 1
	while bwd >= 0 and bool(in_win[bwd]):
		bwd -= 1
	if fwd > bwd:
		return
	for i: int in range(fwd, bwd + 1):
		kept.append((dense[i] as Dictionary)["p"])
	if kept.size() < 4:
		return
	# Dirt road through the gap (±340px along the opening radial).
	var gap_mid: Vector2 = center + face * r
	var road := {
		"x1": gap_mid.x - face.x * ROAD_HALF, "y1": gap_mid.y - face.y * ROAD_HALF,
		"x2": gap_mid.x + face.x * ROAD_HALF, "y2": gap_mid.y + face.y * ROAD_HALF,
	}
	# Chunk into affordable commits; skip stretches already walled.
	var chunks: Array = _chunk(kept)
	var neighbor_id := ""
	for other: Dictionary in regions:
		if other != region:
			neighbor_id = String(other.get("id", ""))
			break
	var border_key: String = "bw_%s|%s" % [
		String(region.get("id", "")), neighbor_id]
	if borders_done.has(border_key):
		return
	var run_list: Array = []
	for ch: Array in chunks:
		if _already_walled(ch, faction):
			continue
		run_list.append({"pts": ch, "road": road, "border_key": border_key})
	if run_list.is_empty():
		return
	if is_player:
		var pol: String = String(policy.get(String(region.get("name", "")), ""))
		if pol == "skip":
			return
		var entry := {
			"region_name": String(region.get("name", "")),
			"faction": faction,
			"cost": _estimate_cost(run_list),
			"runs": run_list,
		}
		if pol == "raise":
			_commit_entry(entry, bs, wall_drag)
			return
		# Unanswered: queue the modal (dedup by region).
		for e: Dictionary in pending:
			if String(e.get("region_name", "")) == String(entry["region_name"]):
				return
		pending.append(entry)
		return
	_commit_entry({
		"region_name": String(region.get("name", "")),
		"faction": faction, "cost": {}, "runs": run_list}, bs, wall_drag)


func _commit_entry(entry: Dictionary, bs: SimBuildings,
		wall_drag: WallDrag) -> void:
	var faction: String = String(entry.get("faction", ""))
	var town_id: int = _nearest_town(faction, Vector2.ZERO)
	for run: Dictionary in entry.get("runs", []):
		var pts: Array = run.get("pts", [])
		if pts.size() < 2:
			continue
		var plan: Dictionary = WallDrag.plan_polyline(pts, _gs.buildings,
			faction, Rect2(-100000, -100000, 200000, 200000))
		if int(plan.get("valid_count", 0)) < 1:
			continue
		var res: Dictionary = wall_drag.commit(bs, plan, faction, town_id,
			{"ai_wall": true})
		var placed: Array = res.get("placed", [])
		if placed.is_empty():
			continue
		var run_id: String = String(res.get("run_id", ""))
		for pb: Dictionary in placed:
			pb["fort_plan"] = run_id
		runs[run_id] = {"faction": faction, "pts": pts,
			"border_key": String(run.get("border_key", ""))}
		borders_done[String(run.get("border_key", ""))] = run_id


## Re-commit breached spans of tracked runs (missing = no alive AI wall
## within 50px of the run point).
func _top_up(faction: String, bs: SimBuildings, wall_drag: WallDrag) -> void:
	var town_id: int = _nearest_town(faction, Vector2.ZERO)
	for run_id: String in runs.keys():
		var rec: Dictionary = runs[run_id]
		if String(rec.get("faction", "")) != faction:
			continue
		var pts: Array = rec.get("pts", [])
		var cur: Array = []
		for p: Vector2 in pts:
			if _wall_near(p, faction, 50.0):
				if cur.size() >= 2:
					_repair_span(bs, wall_drag, cur, faction, town_id, run_id)
				cur = []
			else:
				cur.append(p)
		if cur.size() >= 2:
			_repair_span(bs, wall_drag, cur, faction, town_id, run_id)


func _repair_span(bs: SimBuildings, wall_drag: WallDrag, pts: Array,
		faction: String, town_id: int, run_id: String) -> void:
	var plan: Dictionary = WallDrag.plan_polyline(pts, _gs.buildings, faction,
		Rect2(-100000, -100000, 200000, 200000))
	if int(plan.get("valid_count", 0)) < 1:
		return
	wall_drag.commit(bs, plan, faction, town_id,
		{"ai_wall": true, "run_id": run_id, "fort_plan": run_id})


func _chunk(kept: Array) -> Array:
	var chunks: Array = []
	var cur: Array = [kept[0]]
	var acc := 0.0
	for i: int in range(1, kept.size()):
		acc += (kept[i] as Vector2).distance_to(kept[i - 1])
		cur.append(kept[i])
		if acc >= CHUNK:
			chunks.append(cur)
			cur = [kept[i]]
			acc = 0.0
	if cur.size() >= 2:
		chunks.append(cur)
	elif cur.size() == 1 and not chunks.is_empty():
		(chunks[chunks.size() - 1] as Array).append(cur[0])
	return chunks


func _already_walled(pts: Array, faction: String) -> bool:
	# Skip the chunk when its midpoint already has a live AI wall nearby.
	var mid: Vector2 = pts[pts.size() / 2]
	return _wall_near(mid, faction, 60.0)


func _wall_near(p: Vector2, faction: String, radius: float) -> bool:
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("type", "")) != "wall":
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not bool(b.get("ai_wall", false)):
			continue
		if p.distance_to(b.get("position", Vector2.ZERO)) <= radius:
			return true
	return false


func _count_ai_walls(faction: String) -> int:
	var n := 0
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("type", "")) != "wall":
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if bool(b.get("ai_wall", false)):
			n += 1
	return n


func _all_halls() -> Array:
	var out: Array = []
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("type", "")) in SimTerritory.CLAIM_TYPES:
			out.append(b)
	return out


func _hall_by_id(hid: int) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if int(b.get("id", 0)) == hid:
			return b
	return {}


## Repels a ring point from every alive hall until the standoff is clear;
## returns null when the point can't get clear (the line routes around).
func _route_around_towns(p: Vector2, halls: Array) -> Variant:
	var px: float = p.x
	var py: float = p.y
	for it: int in range(10):
		var fx := 0.0
		var fy := 0.0
		var worst := 0.0
		for h: Dictionary in halls:
			var hp: Vector2 = h.get("position", Vector2.ZERO)
			var d: float = Vector2(px, py).distance_to(hp)
			if d < WALL_TOWN_STANDOFF and d > 1.0:
				var push: float = (WALL_TOWN_STANDOFF - d) / d
				fx += (px - hp.x) * push
				fy += (py - hp.y) * push
				worst = maxf(worst, WALL_TOWN_STANDOFF - d)
		if worst < 1.0:
			break
		px += fx * 0.5
		py += fy * 0.5
	for h2: Dictionary in _all_halls():
		var hp2: Vector2 = h2.get("position", Vector2.ZERO)
		if Vector2(px, py).distance_to(hp2) < WALL_TOWN_STANDOFF * 0.92:
			return null
	return Vector2(px, py)


func _estimate_cost(run_list: Array) -> Dictionary:
	var per: Dictionary = SimBuildings.cost_of("wall")
	var total := {}
	for run: Dictionary in run_list:
		var pts: Array = run.get("pts", [])
		var px := 0.0
		for i: int in range(1, pts.size()):
			px += (pts[i] as Vector2).distance_to(pts[i - 1])
		var n: int = maxi(1, int(round(px / WallDrag.SEG_LEN)))
		for k: String in per.keys():
			total[k] = float(total.get(k, 0.0)) + float(per[k]) * float(n)
	return total


func _nearest_town(faction: String, near: Vector2) -> int:
	var best := -1
	var best_d := INF
	for tid: int in _gs.towns.keys():
		var t: Dictionary = _gs.towns[tid]
		if String(t.get("faction", "")) != faction:
			continue
		var d: float = near.distance_to(t.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = tid
	return best


## HOOKS (world-tick owner + UI owner + save owner):
## 1. World tick: call border_walls.tick(faction, faction == gs.player_faction,
##    buildings_sys, wall_drag) for each active faction — e.g. every 20 s of
##    game_time per faction (the tick() self-throttles; calling it every
##    frame is safe but wasteful).
## 2. Player prompt: when border_walls.pending is non-empty, the UI shows the
##    HTML modal per entry ("Do you wish to raise walls around <name>? —
##    Estimated cost: X gold · Y wood (N wall runs)") with Raise/Skip
##    buttons, then calls border_walls.answer(region_name, true/false,
##    buildings_sys, wall_drag).
## 3. Save/load: persist border_walls.to_dict() on the snapshot (key
##    "border_walls") and call border_walls.from_dict(data) on load; call
##    border_walls.reset_for_new_game() when starting a new game (NOT on
##    load — the policy must survive save/load).
