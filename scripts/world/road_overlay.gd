class_name RoadOverlay
extends Node2D
## Cursing Gnomes — renders the painted road network.
##
## Roadbuilders paint road records (WorkerAI.roads) but nothing drew them —
## the network was invisible. This draws every record as a soft disc so
## overlapping paints merge into continuous paths:
##   dirt  -> worn brown trail (narrow, earthy)
##   stone -> paved gray road (wider, with a darker cobbled edge)
## Stone reads as the engineered, faster surface it is (1.3x speed bonus).
## Jeremy 2026-10-10 road wear: worn segments render shabby — paler and
## thinner discs; stone loses its cobbled edge as it crumbles.
## One draw call for the whole network; GL Compatibility safe.


const DIRT_COLOR := Color(0.545, 0.427, 0.275, 0.85)   # worn earth
const DIRT_RADIUS := 13.0
const DIRT_WORN_COLOR := Color(0.60, 0.52, 0.38, 0.70)  # dusty, eroding
const DIRT_WORN_RADIUS := 11.0
const DIRT_SHABBY_COLOR := Color(0.66, 0.60, 0.47, 0.55)  # pale ruts
const DIRT_SHABBY_RADIUS := 9.5
const STONE_COLOR := Color(0.62, 0.62, 0.64, 0.95)      # paved gray
const STONE_EDGE := Color(0.42, 0.42, 0.44, 0.95)       # cobbled edge
const STONE_RADIUS := 15.0
const STONE_WORN_COLOR := Color(0.55, 0.55, 0.57, 0.80)  # fading pavement
const STONE_WORN_RADIUS := 14.0
const STONE_SHABBY_COLOR := Color(0.50, 0.50, 0.52, 0.65)  # crumbled
const STONE_SHABBY_RADIUS := 13.0


## Jeremy 2026-10-10 visible road construction: work zones render as marked
## construction sites — survey stakes + string on planned corridors, striped
## barriers + cones at the active work front, barrier rings on repair discs.
var _zones: Array = []
var _zone_sig := ""

const ZONE_STAKE := Color(0.45, 0.32, 0.20, 0.95)
const ZONE_STAKE_TOP := Color(0.85, 0.70, 0.45, 0.95)
const ZONE_STRING := Color(0.80, 0.72, 0.55, 0.70)
const ZONE_ORANGE := Color(0.92, 0.48, 0.12, 0.95)
const ZONE_WHITE := Color(0.95, 0.93, 0.88, 0.95)
const ZONE_WOOD := Color(0.35, 0.25, 0.16, 0.95)


## Push fresh work zones; redraws only when the zone signature changes.
func sync_workzones(zones: Array) -> void:
	var sig := str(zones.size()) + "|"
	for z in zones:
		var zd: Dictionary = z
		var pa: Vector2 = zd.get("a", zd.get("pos", Vector2.ZERO))
		var pb: Vector2 = zd.get("b", pa)
		sig += "%s%d:%d,%d:%d,%d|" % [String(zd.get("kind", "")),
			int(zd.get("stage", 0)), int(pa.x / 16.0), int(pa.y / 16.0),
			int(pb.x / 16.0), int(pb.y / 16.0)]
	if sig == _zone_sig:
		return
	_zone_sig = sig
	_zones = zones
	queue_redraw()


var _roads: Array = []
var _wear_sig := -1


## Visual wear band: 0 fresh, 1 worn, 2 shabby.
static func wear_band(wear: float) -> int:
	return mini(2, int(wear * 3.0))


## Push a fresh snapshot; redraws on count change or when any segment
## crosses a visual wear band (band changes are rare — no per-frame churn).
func sync_roads(roads: Array) -> void:
	var wsig := 0
	for r in roads:
		wsig += wear_band(float(r.get("wear", 0.0))) + 1
	if roads.size() == _roads.size() and wsig == _wear_sig:
		return
	_roads = roads
	_wear_sig = wsig
	queue_redraw()


func _draw() -> void:
	# Stone first (under), dirt on top — paved roads stay readable where
	# a dirt trail was upgraded.
	for pass_idx in 2:
		for r in _roads:
			var rtype := String(r.get("type", "dirt"))
			if (pass_idx == 0) != (rtype == "stone"):
				continue
			var p: Vector2 = r.get("position", Vector2.ZERO)
			var band := wear_band(float(r.get("wear", 0.0)))
			if rtype == "stone":
				if band == 0:
					draw_circle(p, STONE_RADIUS + 2.0, STONE_EDGE)
					draw_circle(p, STONE_RADIUS, STONE_COLOR)
					# Cobble hint: two offset flecks.
					draw_circle(p + Vector2(-5, -3), 2.2, STONE_EDGE)
					draw_circle(p + Vector2(5, 4), 2.2, STONE_EDGE)
				elif band == 1:
					draw_circle(p, STONE_WORN_RADIUS + 1.0, STONE_EDGE)
					draw_circle(p, STONE_WORN_RADIUS, STONE_WORN_COLOR)
				else:
					draw_circle(p, STONE_SHABBY_RADIUS, STONE_SHABBY_COLOR)
			else:
				if band == 0:
					draw_circle(p, DIRT_RADIUS, DIRT_COLOR)
				elif band == 1:
					draw_circle(p, DIRT_WORN_RADIUS, DIRT_WORN_COLOR)
				else:
					draw_circle(p, DIRT_SHABBY_RADIUS, DIRT_SHABBY_COLOR)
	# Work zones on top: marked construction sites.
	for z in _zones:
		var zd: Dictionary = z
		if String(zd.get("kind", "")) == "disc":
			_draw_repair_zone(zd.get("pos", Vector2.ZERO),
				float(zd.get("r", 56.0)))
		else:
			_draw_link_zone(zd)


## A planned/gradiing link corridor: survey stakes + string along the
## unbuilt stretch; striped barriers + cones at the active work front once
## the crew has broken ground (closed zones only).
func _draw_link_zone(zd: Dictionary) -> void:
	var a: Vector2 = zd.get("a", Vector2.ZERO)
	var b: Vector2 = zd.get("b", Vector2.ZERO)
	var closed := bool(zd.get("closed", true))
	var d := b - a
	var length := d.length()
	if length < 1.0:
		if closed:
			_draw_barrier(a, 0.0)
		return
	var dir := d / length
	var n := maxi(2, int(length / 44.0) + 1)
	var prev := Vector2.ZERO
	for i in range(n):
		var sp := a + dir * (length * float(i) / float(n - 1))
		draw_rect(Rect2(sp + Vector2(-1.5, -10), Vector2(3, 10)), ZONE_STAKE)
		draw_rect(Rect2(sp + Vector2(-1.5, -10), Vector2(3, 3)),
			ZONE_STAKE_TOP)
		if i > 0:
			draw_line(prev, sp + Vector2(0, -8), ZONE_STRING, 1.0)
		prev = sp + Vector2(0, -8)
	if not closed:
		return
	# Barriers across the work front + cones flanking the corridor.
	var ang := dir.angle()
	var nrm := Vector2(-dir.y, dir.x)
	for off in [-14.0, 0.0, 14.0]:
		_draw_barrier(a + nrm * off + dir * 8.0, ang)
	for s in [-1.0, 1.0]:
		for t in [44.0, 88.0]:
			_draw_cone(a + dir * t + nrm * 30.0 * s)


## A repair / paving work zone: ring of striped barriers + cones.
func _draw_repair_zone(pos: Vector2, r: float) -> void:
	for i in range(4):
		var ang := TAU * float(i) / 4.0 + PI / 4.0
		_draw_barrier(pos + Vector2(cos(ang), sin(ang)) * r, ang + PI / 2.0)
	for i in range(4):
		var ang2 := TAU * float(i) / 4.0
		_draw_cone(pos + Vector2(cos(ang2), sin(ang2)) * (r + 20.0))


## Striped sawhorse barrier, plank perpendicular to the given angle.
func _draw_barrier(p: Vector2, ang: float) -> void:
	var dd := Vector2(cos(ang), sin(ang))
	var nn := Vector2(-dd.y, dd.x)
	var pa := p - nn * 13.0
	var pb := p + nn * 13.0
	draw_line(pa + Vector2(0, 2), pa + Vector2(0, 9), ZONE_WOOD, 3.0)
	draw_line(pb + Vector2(0, 2), pb + Vector2(0, 9), ZONE_WOOD, 3.0)
	for i in range(6):
		var c := ZONE_ORANGE if i % 2 == 0 else ZONE_WHITE
		draw_line(pa.lerp(pb, float(i) / 6.0),
			pa.lerp(pb, float(i + 1) / 6.0), c, 5.0)


## Small traffic cone.
func _draw_cone(p: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array(
		[p + Vector2(-5, 0), p + Vector2(5, 0), p + Vector2(0, -11)]),
		ZONE_ORANGE)
	draw_line(p + Vector2(-2.5, -5), p + Vector2(2.5, -5), ZONE_WHITE, 2.0)
	draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), ZONE_WOOD, 2.0)
