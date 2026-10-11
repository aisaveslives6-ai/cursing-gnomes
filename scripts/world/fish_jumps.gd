class_name FishJumps
extends Node2D
## Cursing Gnomes — jumping fish + splash rings (port completion).
##
## HTML source of truth: hydroFishTick + drawFishJumps (fix79 index.html:17515) —
## fish leap out of lakes and rivers (cap 22, spawn gate randf() < dt * 0.9,
## 55% lake / 45% river), arcing nose-up then nose-down with a tail wiggle,
## landing in an expanding splash ring with 5 droplets. HTML draws them
## "right after the water so fish arc OUT of it" — here z_index = -50 puts
## them above the water shader (-90) and below units/props (0).
##
## Improvements over the HTML original:
##   - Spawn pre-filters water bodies to the camera view first: HTML rolled a
##     random lake/river map-wide and discarded it when out of view (wasted
##     picks); we only consider bodies intersecting the view, so the cap and
##     rate always produce visible fish near the action.
##   - Zero per-frame cost when idle: visible = false while no fish or rings
##     are alive, so _draw short-circuits and queue_redraw is skipped.
##   - Audio hook: fish_landed fires on every splash landing (HTML's
##     sfxAt('splash')); world.gd routes it to the SFX bus. The HTML's
##     inView(sx, sy, 200) gate is inherent — fish only spawn inside the
##     view (grow 120) and jump <= 80 px, so landings are always on-screen;
##     far-cull stays in the audio manager's distance cutoff.
##
## Wired in world.gd _ready() (camera + water-body provider + fish_landed).
## Tests drive the pure statics and the spawn/step helpers with stub bodies.


## HTML SFX parity: sfxAt('splash', sx, sy) on landing (fix79 hydroFishTick).
signal fish_landed(pos: Vector2)


## HTML-verbatim spawn numbers.
const MAX_FISH := 22
const MAX_RINGS := 30
const SPAWN_RATE := 0.9        ## randf() < dt * 0.9 per tick
const LAKE_PICK := 0.55        ## 55% lake roll, else river
const RING_LIFE := 0.9         ## rings die at t > 0.9
const FISH_COLS: Array[Color] = [
	Color8(0xff, 0x9e, 0x4f),  # #ff9e4f
	Color8(0x7f, 0xd4, 0xff),  # #7fd4ff
	Color8(0xc0, 0xc8, 0xd8),  # #c0c8d8
	Color8(0xff, 0xd5, 0x4f),  # #ffd54f
	Color8(0xff, 0x6b, 0x6b),  # #ff6b6b
]
const OUTLINE := Color8(0x0b, 0x3a, 0x56)      ## #0b3a56
const SHADOW := Color(0.039, 0.118, 0.196, 0.25)  ## rgba(10,30,50,0.25)
const RING_WHITE := Color(1.0, 1.0, 1.0)


var _camera: Camera2D = null
var _provider: Callable = Callable()  ## () -> Array of water-body dicts

var _fish: Array = []   ## {x,y,t,dur,peak,ang,len,col,sz}
var _rings: Array = []  ## {x,y,t}


func _init() -> void:
	z_index = -50  # above water (-90), below units/props (0)


func set_camera(cam: Camera2D) -> void:
	_camera = cam


func set_provider(call: Callable) -> void:
	_provider = call


## HTML verbatim: px = x + cos(ang)*len*k;
##                 py = y + sin(ang)*len*0.4*k - sin(PI*k)*peak.
static func fish_pos(f: Dictionary) -> Vector2:
	var k: float = minf(1.0, float(f["t"]) / float(f["dur"]))
	return Vector2(
		float(f["x"]) + cos(float(f["ang"])) * float(f["len"]) * k,
		float(f["y"]) + sin(float(f["ang"])) * float(f["len"]) * 0.4 * k
			- sin(PI * k) * float(f["peak"]))


## HTML verbatim: tilt = cos(PI*k) * -0.7 (nose up, then nose down).
static func fish_tilt(f: Dictionary) -> float:
	var k: float = minf(1.0, float(f["t"]) / float(f["dur"]))
	return cos(PI * k) * -0.7


## HTML verbatim: wig = sin(t * 30) * 0.18 (tail wiggle).
static func fish_wiggle(f: Dictionary) -> float:
	return sin(float(f["t"]) * 30.0) * 0.18


## HTML verbatim: k = min(1, t / 0.9).
static func ring_k(s: Dictionary) -> float:
	return minf(1.0, float(s["t"]) / RING_LIFE)


## HTML verbatim: r = 6 + k*26 for the ring ellipse (x radius; y = *0.45).
static func ring_radius(k: float) -> float:
	return 6.0 + k * 26.0


## HTML verbatim: er = lakeEffR(l) * 0.9; a = rand*TAU; rr = sqrt(rand);
## fx = l.x + cos(a)*er*rr*1.05; fy = l.y + sin(a)*er*rr*0.62.
func lake_spot(lake: Dictionary) -> Vector2:
	var pos: Vector2 = lake.get("pos", Vector2.ZERO)
	var er: float = float(lake.get("radius", 100.0)) * 0.9
	var a: float = randf() * TAU
	var rr: float = sqrt(randf())
	return Vector2(
		pos.x + cos(a) * er * rr * 1.05,
		pos.y + sin(a) * er * rr * 0.62)


## HTML verbatim: pick segment i, lerp between points[i] and points[i+1].
func river_spot(river: Dictionary) -> Vector2:
	var pts: PackedVector2Array = river.get("points", PackedVector2Array())
	if pts.size() < 2:
		return Vector2.ZERO
	var i: int = randi() % (pts.size() - 1)
	var a: Vector2 = pts[i]
	var b: Vector2 = pts[i + 1]
	var p: float = randf()
	return Vector2(a.x + (b.x - a.x) * p, a.y + (b.y - a.y) * p)


## Lake counts as in view when any of its disc can be seen.
func lake_in_view(lake: Dictionary, view: Rect2) -> bool:
	var pos: Vector2 = lake.get("pos", Vector2.ZERO)
	var r: float = float(lake.get("radius", 0.0))
	var cx: float = clampf(pos.x, view.position.x, view.end.x)
	var cy: float = clampf(pos.y, view.position.y, view.end.y)
	return Vector2(cx, cy).distance_to(pos) <= r


## River counts as in view when any polyline point is near the view.
func river_in_view(river: Dictionary, view: Rect2) -> bool:
	var pts: PackedVector2Array = river.get("points", PackedVector2Array())
	var grown: Rect2 = view.grow(80.0)
	for p: Vector2 in pts:
		if grown.has_point(p):
			return true
	return false


func _process(delta: float) -> void:
	if _camera == null or not _provider.is_valid():
		visible = false
		return
	var view := _visible_rect()
	if view == Rect2():
		visible = false
		return
	var bodies: Array = []
	var got: Variant = _provider.call()
	if got is Array:
		bodies = got
	_tick_spawn(delta, bodies, view)
	_tick_step(delta)
	visible = not _fish.is_empty() or not _rings.is_empty()
	if visible:
		queue_redraw()


## HTML verbatim spawn gate; lake/river pick pre-filtered to the view.
func _tick_spawn(delta: float, bodies: Array, view: Rect2) -> void:
	if _fish.size() >= MAX_FISH:
		return
	if randf() >= delta * SPAWN_RATE:
		return
	var lakes: Array = []
	var rivers: Array = []
	for b: Variant in bodies:
		if not (b is Dictionary):
			continue
		var d: Dictionary = b
		var kind := String(d.get("kind", ""))
		if kind == "lake":
			if lake_in_view(d, view):
				lakes.append(d)
		elif kind == "river":
			if river_in_view(d, view):
				rivers.append(d)
	var spot := Vector2.ZERO
	var have := false
	# Jeremy 2026-10-05: fish were arcing up to 80px in a random direction
	# and landing on shore. Aim the jump so it stays over water: lakes
	# jump back toward the center, rivers jump along the channel.
	var ang := 0.0
	var max_len := 80.0
	if randf() < LAKE_PICK and not lakes.is_empty():
		var lake: Dictionary = lakes[randi() % lakes.size()]
		spot = lake_spot(lake)
		have = true
		var center: Vector2 = lake.get("pos", Vector2.ZERO)
		var radius: float = float(lake.get("radius", 100.0))
		ang = (center - spot).angle() + randf_range(-0.7, 0.7)
		max_len = minf(80.0, spot.distance_to(center) * 0.85 + 20.0)
		# Never jump past the far shore.
		max_len = minf(max_len, radius * 1.7)
	elif not rivers.is_empty():
		var river: Dictionary = rivers[randi() % rivers.size()]
		var pts: PackedVector2Array = river.get("points", PackedVector2Array())
		if pts.size() >= 2:
			var i: int = randi() % (pts.size() - 1)
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var p: float = randf()
			spot = Vector2(a.x + (b.x - a.x) * p, a.y + (b.y - a.y) * p)
			have = true
			# Jump along the channel (either direction), not across it.
			ang = (b - a).angle() + randf_range(-0.45, 0.45)
			if randf() < 0.5:
				ang += PI
			max_len = 60.0
	if not have:
		return
	if not view.grow(120.0).has_point(spot):
		return  # HTML: inView(fx, fy, 120)
	_fish.append({
		"x": spot.x, "y": spot.y, "t": 0.0,
		"dur": 0.8 + randf() * 0.5,
		"peak": 24.0 + randf() * 26.0,
		"ang": ang,
		"len": 44.0 + randf() * minf(36.0, maxf(0.0, max_len - 44.0)),
		"col": FISH_COLS[randi() % FISH_COLS.size()],
		"sz": 7.0 + randf() * 5.0,
	})


## HTML verbatim stepping: fish age out into splash rings; rings die at 0.9s.
func _tick_step(delta: float) -> void:
	var kept_fish: Array = []
	for f: Variant in _fish:
		var d: Dictionary = f
		d["t"] = float(d["t"]) + delta
		if float(d["t"]) >= float(d["dur"]):
			var sx: float = float(d["x"]) \
				+ cos(float(d["ang"])) * float(d["len"])
			var sy: float = float(d["y"]) \
				+ sin(float(d["ang"])) * float(d["len"]) * 0.4
			if _rings.size() < MAX_RINGS:
				_rings.append({"x": sx, "y": sy, "t": 0.0})
			# HTML SFX parity: splash on every landing (fix79 hydroFishTick
			# plays sfxAt('splash') outside the ring-cap check too).
			fish_landed.emit(Vector2(sx, sy))
		else:
			kept_fish.append(d)
	_fish = kept_fish
	var kept_rings: Array = []
	for s: Variant in _rings:
		var d: Dictionary = s
		d["t"] = float(d["t"]) + delta
		if float(d["t"]) <= RING_LIFE:
			kept_rings.append(d)
	_rings = kept_rings


func _visible_rect() -> Rect2:
	if _camera == null:
		return Rect2()
	var vp := get_viewport_rect().size
	var zoom := _camera.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return Rect2()
	var size := Vector2(vp.x / zoom.x, vp.y / zoom.y)
	return Rect2(_camera.get_screen_center_position() - size * 0.5, size)


func _draw() -> void:
	for f: Variant in _fish:
		_draw_fish(f)
	for s: Variant in _rings:
		_draw_ring(s)


## HTML verbatim drawFishJumps fish: shadow ellipse, rotated body ellipse
## with dark outline, tail triangle, white eye + dark pupil.
func _draw_fish(f: Dictionary) -> void:
	var p := fish_pos(f)
	var k: float = minf(1.0, float(f["t"]) / float(f["dur"]))
	var sz: float = float(f["sz"])
	var col: Color = f["col"]
	var rot: float = fish_tilt(f) + fish_wiggle(f)
	# Shadow on the water directly below (surface point under the arc).
	var surf := Vector2(p.x, p.y + sin(PI * k) * float(f["peak"]))
	var shpts := PackedVector2Array()
	for i: int in 24:
		var a: float = TAU * float(i) / 24.0
		shpts.append(surf + Vector2(cos(a) * sz * 0.9, sin(a) * sz * 0.35))
	draw_colored_polygon(shpts, SHADOW)
	# Body ellipse (flat cel body + dark outline).
	var bpts := PackedVector2Array()
	for i: int in 28:
		var a: float = TAU * float(i) / 28.0
		bpts.append(p + Vector2(cos(a) * sz, sin(a) * sz * 0.42).rotated(rot))
	draw_colored_polygon(bpts, col)
	var bout := PackedVector2Array(bpts)
	bout.append(bpts[0])
	draw_polyline(bout, OUTLINE, 1.6)
	# Tail triangle.
	var tail := PackedVector2Array([
		p + Vector2(-sz * 0.9, 0.0).rotated(rot),
		p + Vector2(-sz * 1.5, -sz * 0.5).rotated(rot),
		p + Vector2(-sz * 1.5, sz * 0.5).rotated(rot)])
	draw_colored_polygon(tail, col)
	var tout := PackedVector2Array([tail[0], tail[1], tail[2], tail[0]])
	draw_polyline(tout, OUTLINE, 1.6)
	# Eye: white + dark pupil.
	draw_circle(p + Vector2(sz * 0.55, -sz * 0.08).rotated(rot),
		sz * 0.14, RING_WHITE)
	draw_circle(p + Vector2(sz * 0.58, -sz * 0.08).rotated(rot),
		sz * 0.07, OUTLINE)


## HTML verbatim splash rings: expanding white ellipse + 5 droplets while k<0.5.
func _draw_ring(s: Dictionary) -> void:
	var k := ring_k(s)
	var at := Vector2(float(s["x"]), float(s["y"]))
	var r := ring_radius(k)
	var pts := PackedVector2Array()
	for i: int in 32:
		var a: float = TAU * float(i) / 32.0
		pts.append(at + Vector2(cos(a) * r, sin(a) * r * 0.45))
	pts.append(pts[0])
	draw_polyline(pts, Color(RING_WHITE, 0.85 * (1.0 - k)), 2.5)
	if k < 0.5:
		var dc := Color(RING_WHITE, 0.8 * (1.0 - k * 2.0))
		var da0: float = float(s["x"]) * 0.01
		for d: int in 5:
			var da: float = float(d) * 1.256 + da0
			var dp := Vector2(
				float(s["x"]) + cos(da) * (10.0 + k * 30.0),
				float(s["y"]) - 4.0 - k * 26.0 + sin(da) * 6.0)
			draw_circle(dp, 2.0, dc)
