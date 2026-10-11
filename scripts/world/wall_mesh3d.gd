class_name WallMesh3D
extends RefCounted
## Cursing Gnomes — cel-shaded 3D walls drawn in the 2D isometric canvas.
##
## Jeremy (2026-10-06): "put 3d walls in that are cel shaded so they still
## look cartoon."
##
## DESIGN NOTE — why not MeshInstance3D: these ARE real 3D wall volumes (a
## box body plus crenellated merlons, oriented along the segment's
## wall_angle), but they are rendered through the 2D canvas via an
## orthographic projection — 3D point (x, y, z) maps to screen (x, y - z).
## In Godot 4 the 2D canvas and the 3D renderer do not depth-interleave
## per object (all 2D draws entirely over or under all 3D), so true 3D
## meshes would break y-sort against units and buildings. The 2.5D
## projection keeps y-sort exact, costs a few dozen polygons per segment
## (drawn once into the canvas-item command buffer — zero per-frame
## cost), and works in the Web export.
##
## CEL LOOK: hard stepped lighting bands — top face lightest, sun-facing
## side mid, shadow side dark — plus ink outlines (#1a120a, the game's
## cartoon ink) on every silhouette edge. Damage states chip merlons and
## crack faces as hp falls; construction grows the wall upward with
## progress. Pure geometry helpers are static so tests can verify them
## without a draw context.

## Matches WallDrag.SEG_LEN (scripts/buildings/wall_drag.gd).
const SEG_LEN := 44.0
## Wall body cross-section on the ground / in the air.
const WALL_W := 14.0
const WALL_H := 36.0
## Crenellations.
const MERLON_W := 9.0
const MERLON_H := 9.0
const MERLON_PITCH := 18.0
## Each end extends past the segment midpoint span so chained segments
## visually merge instead of gapping at joints.
const END_OVERLAP := 7.0

const INK := Color(0.102, 0.071, 0.039)  # HTML #1a120a cartoon ink
const TOP_HI := Color(0.66, 0.64, 0.60)   # sunlit top face
const SIDE_LIT := Color(0.55, 0.53, 0.49) # sun-facing side
const SIDE_MID := Color(0.46, 0.44, 0.42) # neutral side
const SIDE_DK := Color(0.35, 0.33, 0.31)  # shadow side
const CRACK := Color(0.16, 0.13, 0.10)
const RUBBLE := Color(0.42, 0.40, 0.37)

## Damage bands: 0 = pristine, 1 = cracked, 2 = ruined.
static func damage_band(frac: float) -> int:
	if frac > 0.66:
		return 0
	if frac > 0.33:
		return 1
	return 2


static func hp_frac(hp: float, max_hp: float) -> float:
	if max_hp <= 0.0:
		return 1.0
	return clampf(hp / max_hp, 0.0, 1.0)


## Ground-plane corners of a wall segment centered on the local origin,
## running along `angle` (radians). Order: A (start,-perp), B (end,-perp),
## C (end,+perp), D (start,+perp).
static func ground_corners(angle: float, length: float,
		width: float) -> Array:
	var d := Vector2(cos(angle), sin(angle))
	var p := Vector2(-sin(angle), cos(angle))
	var hl := length * 0.5 + END_OVERLAP
	var hw := width * 0.5
	return [
		-d * hl - p * hw,
		d * hl - p * hw,
		d * hl + p * hw,
		-d * hl + p * hw,
	]


## Raise ground corners to `height` (screen: straight up).
static func top_corners(gc: Array, height: float) -> Array:
	var tc: Array = []
	for c in gc:
		tc.append((c as Vector2) + Vector2(0, -height))
	return tc


## Which ground-plane side is nearer the viewer (larger screen y).
## Returns +1 when the +perp side is nearer, -1 otherwise.
static func near_side(angle: float) -> int:
	var p := Vector2(-sin(angle), cos(angle))
	return 1 if p.y >= 0.0 else -1


## Pick the cel band for a side face from its outward ground-plane normal
## and the sun state (Shadows.current(): dx/dy = shadow dir = -sun dir).
static func side_shade(normal: Vector2, sun: Dictionary) -> Color:
	var up: bool = bool(sun.get("up", true))
	if not up:
		return SIDE_DK.darkened(0.25)
	var sd := Vector2(-float(sun.get("dx", 0.0)),
		-float(sun.get("dy", 1.0)))
	if sd.length() < 0.001:
		return SIDE_MID
	var facing: float = normal.normalized().dot(sd.normalized())
	if facing > 0.25:
		return SIDE_LIT
	if facing < -0.25:
		return SIDE_DK
	return SIDE_MID


## Merlon layout along the wall top: Array of Dictionaries
## {off: float (offset along segment from center), h: float (height)}.
## Damage chips or removes merlons; `seed` keeps it deterministic per wall.
static func merlon_layout(length: float, band: int, seed: int) -> Array:
	var n := maxi(1, int(length / MERLON_PITCH))
	var out: Array = []
	var span := (float(n) - 1.0) * MERLON_PITCH
	for i in range(n):
		var off := float(i) * MERLON_PITCH - span * 0.5
		var h := MERLON_H
		# Deterministic chip pattern from the wall seed.
		var r := float(absi(hash(seed * 31 + i * 7)) % 100) / 100.0
		if band == 1 and r < 0.30:
			h = MERLON_H * 0.45  # chipped merlon
		elif band == 2:
			if r < 0.55:
				continue  # merlon knocked clean off
			h = MERLON_H * 0.35  # stub
		out.append({"off": off, "h": h})
	return out


## Full cel-shaded 3D wall segment, drawn into `ci` (must be called from
## inside CanvasItem._draw with the segment's ground midpoint at origin).
## angle: wall_angle from the sim record. height_scale: 0..1 for
## construction growth. alpha: 1.0 solid, <1 ghost (blueprint).
static func draw_wall(ci: CanvasItem, angle: float, hp_frac_v: float,
		height_scale: float, alpha: float, seed: int,
		sun: Dictionary) -> void:
	var band := damage_band(hp_frac_v)
	var h := WALL_H * clampf(height_scale, 0.05, 1.0)
	var gc := ground_corners(angle, SEG_LEN, WALL_W)
	var tc := top_corners(gc, h)
	# A:0 B:1 C:2 D:3. Faces: A-B (-perp normal), D-C (+perp normal).
	var d := Vector2(cos(angle), sin(angle))
	var p := Vector2(-sin(angle), cos(angle))
	var near_s := near_side(angle)
	# Index pairs for the two long side faces: [ground0, ground1].
	var far_face := [0, 1] if near_s > 0 else [3, 2]
	var near_face := [3, 2] if near_s > 0 else [0, 1]
	var far_normal := -p if near_s > 0 else p
	var near_normal := p if near_s > 0 else -p
	var night: bool = not bool(sun.get("up", true))
	var dim := 0.55 if night else 1.0

	var c_far: Color = side_shade(far_normal, sun) * dim
	var c_near: Color = side_shade(near_normal, sun) * dim
	var c_top: Color = (TOP_HI * dim)
	c_far.a = alpha
	c_near.a = alpha
	c_top.a = alpha
	var ink := Color(INK.r, INK.g, INK.b, alpha)

	# 1. Far side face.
	_draw_quad(ci, gc[far_face[0]], gc[far_face[1]],
		tc[far_face[1]], tc[far_face[0]], c_far)
	# 2. Far end cap (start cap if far face is A-B... caps span the width).
	_draw_quad(ci, gc[0], gc[3], tc[3], tc[0],
		(c_far.darkened(0.08)) if near_s > 0 else c_far)
	# 3. Top face.
	_draw_quad(ci, tc[0], tc[1], tc[2], tc[3], c_top)
	# 4. Crenellations (merlons) on the top face.
	_draw_merlons(ci, d, p, tc, h, band, seed, c_top, c_near, ink,
		height_scale, alpha, dim)
	# 5. Near side face.
	_draw_quad(ci, gc[near_face[0]], gc[near_face[1]],
		tc[near_face[1]], tc[near_face[0]], c_near)
	# 6. Near end cap.
	_draw_quad(ci, gc[1], gc[2], tc[2], tc[1],
		c_near if near_s < 0 else c_near.darkened(0.08))
	# 7. Brick courses on both side faces (the stone-block read).
	_draw_courses(ci, gc, tc, far_face, ink, seed, alpha)
	_draw_courses(ci, gc, tc, near_face, ink, seed + 1, alpha)
	# 8. Ink silhouette: top perimeter + near bottom edge + end verticals.
	var peri := PackedVector2Array(
		[tc[0], tc[1], tc[2], tc[3], tc[0]])
	ci.draw_polyline(peri, ink, 2.0)
	var n0: Vector2 = gc[near_face[0]]
	var n1: Vector2 = gc[near_face[1]]
	ci.draw_line(n0, n1, ink, 2.0)
	ci.draw_line(n0, tc[near_face[0]], ink, 2.0)
	ci.draw_line(n1, tc[near_face[1]], ink, 2.0)
	# 9. Damage: cracks + rubble.
	if band >= 1 and height_scale > 0.9:
		_draw_damage(ci, gc, tc, near_face, band, seed, alpha)


## Merlon boxes along the top face. Each merlon: top quad + near face quad
## + ink outline. Merlon `off` runs along the segment direction from center.
static func _draw_merlons(ci: CanvasItem, d: Vector2, p: Vector2, tc: Array,
		h: float, band: int, seed: int, c_top: Color, c_near: Color,
		ink: Color, height_scale: float, alpha: float, dim: float) -> void:
	if height_scale < 0.75:
		return  # merlons only on a nearly-finished wall
	var layout := merlon_layout(SEG_LEN, band, seed)
	var near_s := 1.0 if p.y >= 0.0 else -1.0
	var hw := WALL_W * 0.5
	for m in layout:
		var off := float((m as Dictionary)["off"])
		var mh := float((m as Dictionary)["h"]) * height_scale
		var mw := MERLON_W * 0.5
		var center := d * off
		# Merlon ground rect (on the wall top): 4 corners at top-face level.
		var g0 := center - d * mw - p * hw
		var g1 := center + d * mw - p * hw
		var g2 := center + d * mw + p * hw
		var g3 := center - d * mw + p * hw
		var t0 := g0 + Vector2(0, -mh)
		var t1 := g1 + Vector2(0, -mh)
		var t2 := g2 + Vector2(0, -mh)
		var t3 := g3 + Vector2(0, -mh)
		# Top of the merlon.
		_draw_quad(ci, t0, t1, t2, t3, c_top)
		# Near face of the merlon.
		if near_s > 0.0:
			_draw_quad(ci, g2, g3, t3, t2, c_near)
			ci.draw_polyline(PackedVector2Array([g2, g3, t3, t2, g2]),
				ink, 1.6)
		else:
			_draw_quad(ci, g0, g1, t1, t0, c_near)
			ci.draw_polyline(PackedVector2Array([g0, g1, t1, t0, g0]),
				ink, 1.6)


## Horizontal brick-course lines across a side face + a few vertical joints.
static func _draw_courses(ci: CanvasItem, gc: Array, tc: Array,
		face: Array, ink: Color, seed: int, alpha: float) -> void:
	var g0: Vector2 = gc[face[0]]
	var g1: Vector2 = gc[face[1]]
	var t0: Vector2 = tc[face[0]]
	var t1: Vector2 = tc[face[1]]
	var line_c := Color(ink.r, ink.g, ink.b, 0.35 * alpha)
	for f: float in [0.33, 0.66]:
		var p0: Vector2 = g0 + (t0 - g0) * f
		var p1: Vector2 = g1 + (t1 - g1) * f
		ci.draw_line(p0, p1, line_c, 1.2)
	# A few vertical joints, seeded per wall.
	var joints := 2 + absi(hash(seed)) % 2
	for j in range(joints):
		var r := float(absi(hash(seed * 13 + j * 29)) % 100) / 100.0
		var f2 := 0.15 + r * 0.7
		var b0 := g0.lerp(g1, f2)
		var b1 := t0.lerp(t1, f2)
		ci.draw_line(b0, b1, line_c, 1.0)


## Cracks on the near face + rubble at the base for ruined walls.
static func _draw_damage(ci: CanvasItem, gc: Array, tc: Array, face: Array,
		band: int, seed: int, alpha: float) -> void:
	var g0: Vector2 = gc[face[0]]
	var g1: Vector2 = gc[face[1]]
	var t0: Vector2 = tc[face[0]]
	var t1: Vector2 = tc[face[1]]
	var crack_c := Color(CRACK.r, CRACK.g, CRACK.b, alpha)
	var cracks := 2 if band == 1 else 4
	for c in range(cracks):
		var r0 := float(absi(hash(seed * 101 + c * 17)) % 100) / 100.0
		var pts := PackedVector2Array()
		var steps := 4
		for s in range(steps + 1):
			var f := float(s) / float(steps)
			var px := lerpf(0.15 + r0 * 0.6, 0.25 + r0 * 0.5, f)
			var py := lerpf(0.05, 0.95, f)
			var jit := (float(absi(hash(seed * 7 + c * 31 + s)) % 100)
				/ 100.0 - 0.5) * 0.12
			var base := g0.lerp(g1, clampf(px + jit, 0.02, 0.98))
			var top := t0.lerp(t1, clampf(px + jit, 0.02, 0.98))
			pts.append(base.lerp(top, py))
		ci.draw_polyline(pts, crack_c, 1.8)
	if band >= 2:
		# Rubble chunks at the wall base.
		var rub := Color(RUBBLE.r, RUBBLE.g, RUBBLE.b, alpha)
		for k in range(4):
			var r1 := float(absi(hash(seed * 53 + k * 3)) % 100) / 100.0
			var bx := g0.lerp(g1, 0.1 + r1 * 0.8)
			var s2 := 3.0 + r1 * 4.0
			var rp := PackedVector2Array([
				bx + Vector2(-s2, 0), bx + Vector2(s2 * 0.6, 0),
				bx + Vector2(0, -s2 * 0.8)])
			ci.draw_colored_polygon(rp, rub)
			rp.append(rp[0])
			ci.draw_polyline(rp, crack_c, 1.2)


static func _draw_quad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2,
		d: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([a, b, c, d]), col)
