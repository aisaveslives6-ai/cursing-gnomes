class_name VehicleArt
extends RefCounted
## Cursing Gnomes — shared vehicle drawing (Jeremy 2026-10-10 vehicle order,
## phase P2: generalize the wagon renderer into a vehicle layer).
##
## Procedural isometric vehicle art in the HTML-verbatim trade-wagon style
## (fix79 drawTradeWagons): brown box body, canvas top, dark spoked wheels,
## faction-color trim. One module draws every fantasy-era vehicle type so
## trade wagons, citizen carts/carriages, military vehicles and fire trucks
## share a single consistent look — no placeholder art, no white squares.
##
## Local space: vehicle ground point at `base` (wheels touch y=0 there),
## +x forward, mirrored by `fx` (-1 westbound). `wheel_spin` is radians of
## wheel rotation (accumulated from distance travelled); `bob` is a vertical
## px offset while driving (0 when parked). `trim` is the faction color.
##
## Pure drawing on the passed CanvasItem — no per-frame allocation beyond
## the polygon arrays, 60fps-safe.


## HTML-verbatim palette (trade_wagon_layer.gd).
const BODY_BROWN := Color(0.427, 0.298, 0.255)   # #6d4c41
const CANVAS_TAN := Color(0.553, 0.431, 0.388)   # #8d6e63
const DARK_OUTLINE := Color(0.102, 0.071, 0.039) # #1a120a
const WHEEL_DARK := Color(0.243, 0.153, 0.137)   # #3e2723
## Cart palette: weathered wood + hay cargo.
const WOOD_LIGHT := Color(0.55, 0.42, 0.28)
const WOOD_DARK := Color(0.35, 0.25, 0.16)
const HAY := Color(0.78, 0.66, 0.38)
## Carriage palette: lacquered cabin, dark glass, brass lantern.
const CABIN_RED := Color(0.48, 0.20, 0.16)
const ROOF_DARK := Color(0.36, 0.27, 0.24)
const GLASS := Color(0.20, 0.26, 0.34)
const LANTERN := Color(1.0, 0.80, 0.40)

## Wheel radius per type (drives spin rate: spin = travel / radius).
const WHEEL_RADIUS := {"wagon": 4.5, "cart": 6.0, "carriage": 5.0,
	"firetruck": 5.0}

## Seated riders (graphics-hourly 2026-10-11): boarded units no longer render
## as full-size sprites glued to the vehicle — world.gd hides their UnitNode
## via set_inside() while aboard. Instead the driver and crew ride IN the
## vehicle as upper-body crops of their real chibi sprites, so they read as
## seated figures. RIDER_WORLD_H matches UnitNode.SPRITE_WORLD_H (44px).
const RIDER_WORLD_H := 44.0
const RIDER_FRAC := 0.55  ## visible upper fraction of the sprite (seated crop)


## Seat offsets per vehicle type, facing-right local space (x mirrored by fx
## at draw time). Seat 0 is always the driver; y is the seat line — the
## rider's cropped sprite bottom sits exactly on it.
static func rider_seats(vtype: String) -> Array:
	match vtype:
		"cart":
			# Open bed: driver at the front edge, crew amidships.
			return [Vector2(7, -4), Vector2(0, -4), Vector2(-7, -4)]
		"carriage":
			# Enclosed cabin: only the driver shows, perched on the box.
			return [Vector2(10, -14)]
		"firetruck":
			# Open tank: driver forward, crew aft (one by the hand-pump).
			return [Vector2(9, -8), Vector2(-2, -8), Vector2(-10, -8)]
		_:
			# Covered wagon: driver on the front bench; crew rides inside
			# the canvas, out of sight.
			return [Vector2(12, -6)]


## Draws seated rider sprites over the finished vehicle body. `riders` holds
## Texture2Ds driver-first, aligned with rider_seats(); extra riders are
## ignored (they ride inside, unseen). Pure drawing, 60fps-safe.
static func _draw_riders(ci: CanvasItem, b: Vector2, fx: float,
		vtype: String, riders: Array) -> void:
	if riders.is_empty():
		return
	var seats := rider_seats(vtype)
	var n := mini(riders.size(), seats.size())
	var vis_h := RIDER_WORLD_H * RIDER_FRAC
	for i in range(n):
		var tex: Texture2D = riders[i] as Texture2D
		if tex == null or tex.get_height() <= 0:
			continue
		var sc := RIDER_WORLD_H / float(tex.get_height())
		var dw := float(tex.get_width()) * sc
		var src := Rect2(0.0, 0.0, float(tex.get_width()),
			float(tex.get_height()) * RIDER_FRAC)
		var seat: Vector2 = seats[i]
		var pos := Vector2(b.x + seat.x * fx - dw * 0.5,
			b.y + seat.y - vis_h)
		ci.draw_texture_rect_region(tex, Rect2(pos, Vector2(dw, vis_h)),
			src)


## Dispatch: unknown types fall back to the wagon (never a white square).
static func draw_vehicle(ci: CanvasItem, vtype: String, base: Vector2,
		fx: float, wheel_spin: float, bob: float, trim: Color,
		riders: Array = []) -> void:
	var b := base + Vector2(0.0, bob)
	# Shadow first (improvement over HTML, same as trade wagons): sun-cast
	# onto the ground, offset opposite the sun, soft falloff.
	Shadows.draw_cast(ci, Vector2(64.0, 15.0), 1.0,
		Vector2(b.x, b.y + 13.5))
	match vtype:
		"cart":
			_draw_cart(ci, b, fx, wheel_spin, trim)
		"carriage":
			_draw_carriage(ci, b, fx, wheel_spin, trim)
		"firetruck":
			_draw_firetruck(ci, b, fx, wheel_spin, trim)
		_:
			_draw_wagon(ci, b, fx, wheel_spin, trim)
	# Seated riders ride on top of the finished body (their sprites are
	# pre-cropped to the upper body, so no occlusion tricks are needed).
	_draw_riders(ci, b, fx, vtype, riders)


## Covered wagon — HTML-verbatim geometry (drawTradeWagons, fix79:43543):
## brown box body, arched canvas top, two dark wheels, faction flag.
## Improvements over HTML: canvas ribs, faction trim on the canvas hem,
## spoked wheels that visibly turn.
static func _draw_wagon(ci: CanvasItem, b: Vector2, fx: float,
		spin: float, trim: Color) -> void:
	# Body: HTML fillRect(-14, -6, 26, 14) (widened 2px, symmetric).
	ci.draw_rect(Rect2(b.x - 14.0, b.y - 6.0, 28.0, 14.0), BODY_BROWN)
	_draw_box_outline(ci, b, 14.0, 6.0, 8.0)
	# Canvas arch: HTML quadraticCurveTo(0,-20) peak, #8d6e63.
	var top := PackedVector2Array()
	for k in range(13):
		var t := float(k) / 12.0
		top.append(b + Vector2(lerpf(-12.0, 12.0, t) * fx,
			-6.0 - 14.0 * sin(t * PI)))
	top.append(b + Vector2(12.0 * fx, -6.0))
	ci.draw_colored_polygon(top, CANVAS_TAN)
	ci.draw_polyline(top, DARK_OUTLINE, 2.0)
	# Canvas ribs: three hoop lines over the arch.
	for rib_t in [0.3, 0.5, 0.7]:
		var lx := lerpf(-12.0, 12.0, rib_t) * fx
		ci.draw_line(b + Vector2(lx, -6.0),
			b + Vector2(lx, -6.0 - 14.0 * sin(rib_t * PI)),
			DARK_OUTLINE, 1.0)
	# Faction trim on the canvas hem — ownership at a glance.
	ci.draw_line(b + Vector2(-12.0 * fx, -6.0),
		b + Vector2(12.0 * fx, -6.0), trim, 2.0)
	# Wheels: HTML arcs at (-8,8) and (8,8) r4, #3e2723 (symmetric).
	for wx in [-8.0, 8.0]:
		_draw_wheel(ci, b + Vector2(wx, 8.0), 4.5, spin)
	# Faction flag: HTML pole fillRect(10,-16,3,10) + pennant.
	var pole_x := b.x + 10.0 * fx
	ci.draw_line(Vector2(pole_x, b.y - 6.0),
		Vector2(pole_x, b.y - 17.0), DARK_OUTLINE, 2.0)
	var fw := 8.0 * fx
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(pole_x, b.y - 17.0),
		Vector2(pole_x + fw, b.y - 14.5),
		Vector2(pole_x, b.y - 12.0),
	]), trim)


## Horse-drawn fire wagon (Jeremy 2026-10-10 fire-truck dispatch): red tank
## body, water barrel, brass hand-pump, coiled hose, side ladder, big
## spoked wheels, faction trim on the tank band. Fantasy era — no modern
## truck parts. Same side-view idiom as the wagon (+x forward, fx mirror).
static func _draw_firetruck(ci: CanvasItem, b: Vector2, fx: float,
		spin: float, trim: Color) -> void:
	# Tank body: deep red box.
	ci.draw_rect(Rect2(b.x - 13.0, b.y - 8.0, 26.0, 14.0), CABIN_RED)
	_draw_box_outline(ci, b, 13.0, 8.0, 6.0)
	# Brass band + faction trim stripe across the tank.
	ci.draw_line(b + Vector2(-13.0 * fx, -2.0),
		b + Vector2(13.0 * fx, -2.0), LANTERN, 2.0)
	ci.draw_line(b + Vector2(-13.0 * fx, 1.0),
		b + Vector2(13.0 * fx, 1.0), trim, 1.5)
	# Water barrel: tan cylinder riding on top (ellipse ends).
	ci.draw_rect(Rect2(b.x - 7.0, b.y - 15.0, 14.0, 7.0), CANVAS_TAN)
	ci.draw_ellipse(Vector2(b.x, b.y - 15.0), 14.0, 3.0, WOOD_LIGHT)
	ci.draw_arc(b + Vector2(0.0, -15.0), 7.0, 0.0, PI, 10,
		DARK_OUTLINE, 1.0)
	# Brass hand-pump with handle at the rear.
	var px := b.x - 10.0 * fx
	ci.draw_rect(Rect2(px - 1.5, b.y - 12.0, 3.0, 8.0), LANTERN)
	ci.draw_line(Vector2(px, b.y - 12.0),
		Vector2(px - 5.0 * fx, b.y - 15.0), DARK_OUTLINE, 2.0)
	# Coiled hose: tan rings on the tank side.
	ci.draw_arc(b + Vector2(4.0 * fx, 0.0), 4.0, 0.0, TAU, 12,
		CANVAS_TAN, 2.0)
	ci.draw_arc(b + Vector2(4.0 * fx, 0.0), 2.5, 0.0, TAU, 10,
		WOOD_LIGHT, 1.5)
	# Side ladder: two rails + rungs along the lower tank.
	var ly := b.y + 3.0
	ci.draw_line(b + Vector2(-11.0 * fx, ly), b + Vector2(11.0 * fx, ly),
		WOOD_LIGHT, 1.5)
	ci.draw_line(b + Vector2(-11.0 * fx, ly + 2.5),
		b + Vector2(11.0 * fx, ly + 2.5), WOOD_LIGHT, 1.5)
	for k in range(6):
		var lx := lerpf(-11.0, 11.0, float(k) / 5.0) * fx
		ci.draw_line(b + Vector2(lx, ly), b + Vector2(lx, ly + 2.5),
			WOOD_DARK, 1.0)
	# Big spoked wheels that visibly turn.
	for wx in [-8.0, 8.0]:
		_draw_wheel(ci, b + Vector2(wx, 7.0), 5.0, spin)


## Open wooden cart: plank bed with side rails, big spoked wheels, pull
## handles, a hay-bale load, faction stripe on the bed side.
static func _draw_cart(ci: CanvasItem, b: Vector2, fx: float,
		spin: float, trim: Color) -> void:
	# Bed: weathered planks.
	ci.draw_rect(Rect2(b.x - 10.0, b.y - 4.0, 20.0, 8.0), WOOD_LIGHT)
	_draw_box_outline(ci, b, 10.0, 4.0, 4.0)
	# Plank seams.
	for sx in [-5.0, 0.0, 5.0]:
		ci.draw_line(b + Vector2(sx, -4.0), b + Vector2(sx, 4.0),
			WOOD_DARK, 1.0)
	# Side rails: two posts + top rail.
	for px in [-8.0, 8.0]:
		ci.draw_line(b + Vector2(px, -4.0), b + Vector2(px, -9.0),
			WOOD_DARK, 2.0)
	ci.draw_line(b + Vector2(-10.0, -9.0), b + Vector2(10.0, -9.0),
		WOOD_DARK, 2.0)
	# Hay-bale load peeking over the rails.
	ci.draw_circle(b + Vector2(-3.0, -10.0), 4.0, HAY)
	ci.draw_arc(b + Vector2(-3.0, -10.0), 4.0, 0.0, TAU, 12,
		DARK_OUTLINE, 1.0)
	ci.draw_line(b + Vector2(-6.0, -11.0), b + Vector2(0.0, -9.0),
		WOOD_DARK, 1.0)
	# Faction stripe on the bed side.
	ci.draw_line(b + Vector2(-10.0, 2.0), b + Vector2(10.0, 2.0), trim, 2.0)
	# Pull handles at the front.
	ci.draw_line(b + Vector2(10.0, -2.0), b + Vector2(16.0 * fx, 3.0),
		WOOD_DARK, 2.0)
	ci.draw_line(b + Vector2(10.0, 2.0), b + Vector2(16.0 * fx, 5.0),
		WOOD_DARK, 2.0)
	# Big wheels.
	for wx in [-7.0, 7.0]:
		_draw_wheel(ci, b + Vector2(wx, 8.0), 6.0, spin)


## Enclosed carriage: lacquered cabin with glass windows, curved roof,
## door with faction trim, brass lantern, four wheels (near pair drawn).
static func _draw_carriage(ci: CanvasItem, b: Vector2, fx: float,
		spin: float, trim: Color) -> void:
	# Cabin.
	ci.draw_rect(Rect2(b.x - 11.0, b.y - 14.0, 22.0, 14.0), CABIN_RED)
	_draw_box_outline(ci, b + Vector2(0, -7), 11.0, 7.0, 7.0)
	# Windows: dark glass (never white), two panes.
	for wx in [-6.0, 6.0]:
		ci.draw_rect(Rect2(b.x + wx - 3.0, b.y - 12.0, 6.0, 5.0), GLASS)
		ci.draw_rect(Rect2(b.x + wx - 3.0, b.y - 12.0, 6.0, 5.0),
			DARK_OUTLINE, false, 1.0)
	# Roof: curved arch, darker than the wagon canvas.
	var top := PackedVector2Array()
	for k in range(13):
		var t := float(k) / 12.0
		top.append(b + Vector2(lerpf(-11.0, 11.0, t) * fx,
			-14.0 - 6.0 * sin(t * PI)))
	top.append(b + Vector2(11.0 * fx, -14.0))
	ci.draw_colored_polygon(top, ROOF_DARK)
	ci.draw_polyline(top, DARK_OUTLINE, 2.0)
	# Door: outline + faction trim handle.
	ci.draw_rect(Rect2(b.x - 2.5, b.y - 11.0, 5.0, 11.0),
		DARK_OUTLINE, false, 1.0)
	ci.draw_circle(b + Vector2(1.5 * fx, -5.0), 1.2, trim)
	# Brass lantern at the front.
	ci.draw_circle(b + Vector2(12.5 * fx, -8.0), 2.0, LANTERN)
	ci.draw_arc(b + Vector2(12.5 * fx, -8.0), 2.0, 0.0, TAU, 10,
		DARK_OUTLINE, 1.0)
	# Wheels (near pair).
	for wx in [-8.0, 8.0]:
		_draw_wheel(ci, b + Vector2(wx, 8.0), 5.0, spin)


## Spoked wheel: dark disc + outline + spokes rotated by `spin` so wheels
## visibly turn with travel (Jeremy 2026-10-05: no static sliding).
static func _draw_wheel(ci: CanvasItem, wc: Vector2, r: float,
		spin: float) -> void:
	ci.draw_circle(wc, r, WHEEL_DARK)
	ci.draw_arc(wc, r, 0.0, TAU, 14, DARK_OUTLINE, 1.0)
	for s in range(4):
		var a := s * PI / 4.0 + spin
		ci.draw_line(wc + Vector2(cos(a), sin(a)) * r * 0.35,
			wc + Vector2(cos(a), sin(a)) * (r - 0.5), DARK_OUTLINE, 1.0)


## Crisp 2px outline for a box centered at `c` with half-extents (hw, hh
## above, hb below the center line).
static func _draw_box_outline(ci: CanvasItem, c: Vector2, hw: float,
		hh: float, hb: float) -> void:
	var x0 := c.x - hw
	ci.draw_polyline(PackedVector2Array([
		Vector2(x0, c.y - hh), Vector2(x0 + hw * 2.0, c.y - hh),
		Vector2(x0 + hw * 2.0, c.y + hb), Vector2(x0, c.y + hb),
		Vector2(x0, c.y - hh),
	]), DARK_OUTLINE, 2.0)


## ---------------------------------------------------------------------------
## Draft horse (Jeremy 2026-10-11 deep animation pass: no more ghost wagons).
## Faithful GDScript port of fix79 drawDetailedHorse (the HTML cavalry
## horse), re-harnessed for draft work: saddle off, draft collar + traces
## on. Local space: ground at y=0, +x forward, mirrored by fx.
## `phase` = gait radians advancing with distance travelled (frozen =
## standing). Pure drawing on the passed CanvasItem — same 60fps idiom as
## the vehicles (no per-frame allocation beyond the polygon arrays).

const HORSE_SCALE := 0.8
const HORSE_AHEAD := 42.0   ## horse ground-center ahead of the vehicle base
const HORSE_GAIT := 0.22    ## gait radians per px travelled
const TRACE_LEN := 16.0     ## harness trace reach back toward the vehicle

## Draft-coat palettes (bay = the HTML default coat set).
const HORSE_COATS := [
	{"coat": Color(0.427, 0.298, 0.255), "lt": Color(0.553, 0.431, 0.388),
		"dk": Color(0.306, 0.204, 0.180), "mane": Color(0.243, 0.153, 0.137)},
	{"coat": Color(0.169, 0.137, 0.125), "lt": Color(0.306, 0.267, 0.243),
		"dk": Color(0.090, 0.070, 0.059), "mane": Color(0.059, 0.047, 0.039)},
	{"coat": Color(0.541, 0.353, 0.200), "lt": Color(0.663, 0.463, 0.294),
		"dk": Color(0.365, 0.227, 0.118), "mane": Color(0.243, 0.153, 0.137)},
	{"coat": Color(0.604, 0.604, 0.596), "lt": Color(0.769, 0.769, 0.761),
		"dk": Color(0.431, 0.431, 0.424), "mane": Color(0.290, 0.290, 0.282)},
]
const HOOF_COL := Color(0.129, 0.129, 0.129)
const MUZZLE_COL := Color(0.843, 0.800, 0.784)
const NOSTRIL_COL := Color(0.365, 0.251, 0.216)
const HORSE_EYE := Color(0.102, 0.071, 0.039)
const EAR_INNER := Color(0.937, 0.604, 0.604)
const MUSCLE_HI := Color(1.0, 1.0, 1.0, 0.12)


## Horse-local point -> screen: mirror x by fx, scale, ride the gait bob.
static func _hp(base: Vector2, fx: float, sc: float, bob: float,
		x: float, y: float) -> Vector2:
	return base + Vector2(x * fx * sc, (y + bob) * sc)


## Mirrored rect (HTML fillRect): extent flips with fx so the shape truly
## mirrors instead of sliding.
static func _hrect(ci: CanvasItem, base: Vector2, fx: float, sc: float,
		bob: float, x: float, y: float, w: float, h: float,
		col: Color) -> void:
	var px := x * fx * sc
	if fx < 0.0:
		px -= w * sc
	ci.draw_rect(Rect2(base + Vector2(px, (y + bob) * sc),
		Vector2(w * sc, h * sc)), col)


## Sample a quadratic bezier into a polygon (HTML quadraticCurveTo fills).
static func _qpoly(p0: Vector2, c: Vector2, p1: Vector2,
		n: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(n + 1):
		var t := float(k) / float(n)
		pts.append(p0.lerp(c, t).lerp(c.lerp(p1, t), t))
	return pts


## Two chained quads as one polygon (HTML's back-to-back curveTo fills).
static func _q2poly(p0: Vector2, c1: Vector2, p1: Vector2, c2: Vector2,
		p2: Vector2, n: int = 6) -> PackedVector2Array:
	var pts := _qpoly(p0, c1, p1, n)
	var tail := _qpoly(p1, c2, p2, n)
	for k in range(1, tail.size()):
		pts.append(tail[k])
	return pts


## Rotated ellipse (HTML ctx.ellipse with rotation) via draw_set_transform.
## Godot's draw_ellipse takes full width/height (diameters), not radii.
static func _ellipse_rot(ci: CanvasItem, center: Vector2, rx: float,
		ry: float, rot: float, col: Color) -> void:
	ci.draw_set_transform(center, rot, Vector2.ONE)
	ci.draw_ellipse(Vector2.ZERO, rx * 2.0, ry * 2.0, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _hellipse(ci: CanvasItem, base: Vector2, fx: float, sc: float,
		bob: float, x: float, y: float, rx: float, ry: float,
		col: Color) -> void:
	ci.draw_ellipse(_hp(base, fx, sc, bob, x, y),
		rx * 2.0 * sc, ry * 2.0 * sc, col)


## The draft horse. `coat_idx` selects a HORSE_COATS palette (deterministic
## per vehicle); the collar + traces harness it to the vehicle behind.
static func draw_horse(ci: CanvasItem, base: Vector2, fx: float,
		phase: float, coat_idx: int) -> void:
	var sc := HORSE_SCALE
	var pal: Dictionary = HORSE_COATS[abs(coat_idx) % HORSE_COATS.size()]
	var coat: Color = pal["coat"]
	var coat_lt: Color = pal["lt"]
	var coat_dk: Color = pal["dk"]
	var mane: Color = pal["mane"]
	# HTML verbatim: soft bob, leg gait at 1.15x the bob rate.
	var bob := sin(phase) * 0.35
	var g := sin(phase * 1.15) * 0.55
	Shadows.draw_cast(ci, Vector2(64.0, 15.0), 1.0,
		base + Vector2(0.0, 14.5))
	# Far legs (behind body) + hooves.
	_hrect(ci, base, fx, sc, bob, -11.0, 6.0, 3.2, 11.0 + g, coat_dk)
	_hrect(ci, base, fx, sc, bob, 5.0, 6.0, 3.2, 11.0 - g, coat_dk)
	_hrect(ci, base, fx, sc, bob, -11.2, 16.0 + g, 3.6, 2.2, HOOF_COL)
	_hrect(ci, base, fx, sc, bob, 4.8, 16.0 - g, 3.6, 2.2, HOOF_COL)
	# Barrel: three layered ellipses for volume + muscle highlight.
	_hellipse(ci, base, fx, sc, bob, -1.0, 5.0, 15.0, 9.0, coat_dk)
	_hellipse(ci, base, fx, sc, bob, -1.0, 3.5, 14.0, 8.0, coat)
	_hellipse(ci, base, fx, sc, bob, -2.0, 1.5, 11.0, 5.5, coat_lt)
	_hellipse(ci, base, fx, sc, bob, -3.0, 0.0, 7.0, 3.0, MUSCLE_HI)
	# Chest.
	_ellipse_rot(ci, _hp(base, fx, sc, bob, 8.0, 3.0),
		6.0 * sc, 7.0 * sc, 0.15, coat)
	# Near legs + hooves + fetlock hair.
	_hrect(ci, base, fx, sc, bob, -5.0, 6.0, 3.4, 11.0 - g, coat_dk)
	_hrect(ci, base, fx, sc, bob, 9.0, 6.0, 3.4, 11.0 + g, coat_dk)
	_hrect(ci, base, fx, sc, bob, -5.2, 16.0 - g, 3.8, 2.2, HOOF_COL)
	_hrect(ci, base, fx, sc, bob, 8.8, 16.0 + g, 3.8, 2.2, HOOF_COL)
	_hrect(ci, base, fx, sc, bob, -5.0, 14.0 - g, 3.2, 2.0, mane)
	_hrect(ci, base, fx, sc, bob, 9.0, 14.0 + g, 3.2, 2.0, mane)
	# Neck (tapered, two tones).
	ci.draw_colored_polygon(_q2poly(
		_hp(base, fx, sc, bob, 6.0, 0.0),
		_hp(base, fx, sc, bob, 12.0, -6.0),
		_hp(base, fx, sc, bob, 14.0, -14.0),
		_hp(base, fx, sc, bob, 18.0, -12.0),
		_hp(base, fx, sc, bob, 17.0, -6.0)), coat)
	ci.draw_colored_polygon(_q2poly(
		_hp(base, fx, sc, bob, 17.0, -6.0),
		_hp(base, fx, sc, bob, 15.0, 2.0),
		_hp(base, fx, sc, bob, 10.0, 5.0),
		_hp(base, fx, sc, bob, 10.0, 3.0),
		_hp(base, fx, sc, bob, 6.0, 0.0)), coat)
	ci.draw_colored_polygon(_q2poly(
		_hp(base, fx, sc, bob, 9.0, 0.0),
		_hp(base, fx, sc, bob, 13.0, -5.0),
		_hp(base, fx, sc, bob, 14.5, -12.0),
		_hp(base, fx, sc, bob, 16.0, -10.0),
		_hp(base, fx, sc, bob, 15.0, -5.0)), coat_lt)
	ci.draw_colored_polygon(_q2poly(
		_hp(base, fx, sc, bob, 15.0, -5.0),
		_hp(base, fx, sc, bob, 13.0, 1.0),
		_hp(base, fx, sc, bob, 10.0, 3.0),
		_hp(base, fx, sc, bob, 10.0, 1.5),
		_hp(base, fx, sc, bob, 9.0, 0.0)), coat_lt)
	# Head + muzzle + nostril.
	_ellipse_rot(ci, _hp(base, fx, sc, bob, 17.0, -13.0),
		7.5 * sc, 5.2 * sc, 0.35, coat)
	_ellipse_rot(ci, _hp(base, fx, sc, bob, 18.5, -12.5),
		5.0 * sc, 3.5 * sc, 0.35, coat_lt)
	_ellipse_rot(ci, _hp(base, fx, sc, bob, 22.5, -11.0),
		3.2 * sc, 2.4 * sc, 0.3, MUZZLE_COL)
	_ellipse_rot(ci, _hp(base, fx, sc, bob, 23.5, -10.5),
		1.2 * sc, 0.9 * sc, 0.3, NOSTRIL_COL)
	# Eye + glint.
	_hellipse(ci, base, fx, sc, bob, 16.0, -14.5, 1.6, 1.3, HORSE_EYE)
	ci.draw_circle(_hp(base, fx, sc, bob, 16.4, -14.8), 0.5 * sc,
		Color.WHITE)
	# Ear + inner ear.
	ci.draw_colored_polygon(PackedVector2Array([
		_hp(base, fx, sc, bob, 14.0, -17.0),
		_hp(base, fx, sc, bob, 12.5, -22.0),
		_hp(base, fx, sc, bob, 16.0, -18.0)]), coat_dk)
	ci.draw_colored_polygon(PackedVector2Array([
		_hp(base, fx, sc, bob, 14.2, -17.5),
		_hp(base, fx, sc, bob, 13.2, -20.5),
		_hp(base, fx, sc, bob, 15.2, -18.0)]), EAR_INNER)
	# Mane: five flowing locks, phase-offset like the HTML.
	for i in range(5):
		var my := -16.0 + float(i) * 3.2
		var mx := 10.0 - float(i) * 1.1 + sin(phase + float(i)) * 0.6
		ci.draw_colored_polygon(_q2poly(
			_hp(base, fx, sc, bob, mx, my),
			_hp(base, fx, sc, bob, mx - 4.0, my + 2.0),
			_hp(base, fx, sc, bob, mx - 2.0, my + 5.0),
			_hp(base, fx, sc, bob, mx + 1.0, my + 3.0),
			_hp(base, fx, sc, bob, mx, my)), mane)
	# Forelock.
	ci.draw_colored_polygon(_q2poly(
		_hp(base, fx, sc, bob, 15.0, -17.0),
		_hp(base, fx, sc, bob, 13.0, -20.0),
		_hp(base, fx, sc, bob, 15.0, -22.0),
		_hp(base, fx, sc, bob, 17.0, -20.0),
		_hp(base, fx, sc, bob, 16.0, -17.0)), mane)
	# Tail: two swaying locks.
	var sway := sin(phase) * 2.0
	ci.draw_colored_polygon(_q2poly(
		_hp(base, fx, sc, bob, -14.0, 2.0),
		_hp(base, fx, sc, bob, -22.0, sway),
		_hp(base, fx, sc, bob, -20.0, 12.0),
		_hp(base, fx, sc, bob, -16.0, 8.0),
		_hp(base, fx, sc, bob, -14.0, 6.0)), mane)
	ci.draw_colored_polygon(_q2poly(
		_hp(base, fx, sc, bob, -14.0, 3.0),
		_hp(base, fx, sc, bob, -24.0, 6.0),
		_hp(base, fx, sc, bob, -18.0, 14.0),
		_hp(base, fx, sc, bob, -15.0, 10.0),
		_hp(base, fx, sc, bob, -13.0, 7.0)), mane)
	# Draft harness (replaces the HTML saddle): collar strap over the
	# shoulder, traces running back to the vehicle, bridle on the head.
	ci.draw_line(_hp(base, fx, sc, bob, 3.0, -3.0),
		_hp(base, fx, sc, bob, 12.0, 7.0), coat_dk, 2.5 * sc)
	for ty in [1.0, 5.0]:
		ci.draw_line(_hp(base, fx, sc, bob, -13.0, ty),
			_hp(base, fx, sc, bob, -13.0 - TRACE_LEN, ty), mane,
			1.5 * sc)
	ci.draw_arc(_hp(base, fx, sc, bob, 17.0, -13.0), 6.0 * sc,
		-0.4, 1.2, 12, coat_dk, 1.1 * sc)
	ci.draw_line(_hp(base, fx, sc, bob, 20.0, -11.0),
		_hp(base, fx, sc, bob, 8.0, 2.0), coat_dk, 1.1 * sc)
