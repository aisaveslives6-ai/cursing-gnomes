class_name DisasterMarkers
extends CanvasLayer
## Cursing Gnomes — disaster monster map markers (port completion).
##
## HTML source of truth: drawDisasterMarkers (fix79 index.html:14557) —
## pulsing red "!" diamonds over live monsters when zoomed out
## (camZoom < 0.75), plus screen-edge arrows pointing at off-screen
## monsters so Jeremy always knows where the nasty things are.
##
## Improvements over the HTML original:
##   - The "!" is vector-drawn (bar + dot), never a font glyph — Godot's
##     default font renders some glyphs as tofu boxes in the web export
##     on iPhone (menuicons run, 2026-10-05).
##   - Capped at MAX_MARKERS per frame (nearest-first) for the 60fps rule.
##   - Zero per-frame cost when idle: the layer hides itself (visible =
##     false) whenever zoomed in or no monsters are alive, so _draw and
##     _process short-circuit with no queue_redraw.
##
## Wired in world.gd _ready() (game + camera). Tests drive the pure
## statics plus a live node with a stub provider Callable.


## HTML-verbatim constants.
const ZOOM_GATE := 0.75        ## markers only when camZoom < 0.75
const EDGE_MARGIN := 34.0      ## off-screen clamp margin (px)
const PULSE_RATE := 5.0         ## sin(t * 5)
const MAX_MARKERS := 48        ## per-frame draw cap (60fps rule)
const MARK_RED := Color(1.0, 0.0, 0.0)
const MARK_WHITE := Color(1.0, 1.0, 1.0)
## Arrow geometry (HTML verbatim): triangle pointing +x before rotation.
const ARROW_TIP := Vector2(16, 0)
const ARROW_BASE_A := Vector2(-9, -11)
const ARROW_BASE_B := Vector2(-9, 11)


var _camera: Camera2D = null
var _provider: Callable = Callable()  ## () -> PackedVector2Array
var _draw: _MarkerDraw = null

## Last built commands (test hooks): Array of Dictionaries
## {kind: "diamond"|"arrow", at: Vector2, r: float, pulse: float, ang: float}.
var _diamonds: Array = []
var _arrows: Array = []


func _init() -> void:
	layer = 10  # over world/weather, under HUD (100) and paper map (50)
	_draw = _MarkerDraw.new()
	_draw._owner = self
	add_child(_draw)


func set_camera(cam: Camera2D) -> void:
	_camera = cam


func set_provider(call: Callable) -> void:
	_provider = call


## HTML verbatim: pulse = 0.6 + 0.4 * sin(t * 5).
static func pulse_for(t: float) -> float:
	return 0.6 + 0.4 * sin(t * PULSE_RATE)


## HTML verbatim: r = 20 + 7 * pulse.
static func diamond_radius(pulse: float) -> float:
	return 20.0 + 7.0 * pulse


## HTML verbatim: fill alpha = 0.22 + 0.22 * pulse.
static func diamond_alpha(pulse: float) -> float:
	return 0.22 + 0.22 * pulse


## HTML verbatim: markers only when camZoom < 0.75.
static func shows_at_zoom(zoom: float) -> bool:
	return zoom < ZOOM_GATE


## World -> screen (HTML toScreen parity for a centered camera).
static func world_to_screen(world: Vector2, cam_pos: Vector2,
		zoom: float, view: Vector2) -> Vector2:
	return (world - cam_pos) * zoom + view * 0.5


## HTML verbatim: ex = clamp(s.x, 34, vw - 34), ey = clamp(s.y, 34, vh - 34).
static func edge_clamp(screen: Vector2, view: Vector2) -> Vector2:
	return Vector2(
		clampf(screen.x, EDGE_MARGIN, view.x - EDGE_MARGIN),
		clampf(screen.y, EDGE_MARGIN, view.y - EDGE_MARGIN))


## HTML verbatim: ang = atan2(s.y - ey, s.x - ex).
static func arrow_angle(screen: Vector2, clamped: Vector2) -> float:
	return atan2(screen.y - clamped.y, screen.x - clamped.x)


func _process(_delta: float) -> void:
	if _camera == null or not _provider.is_valid():
		visible = false
		return
	var zoom: float = _camera.zoom.x
	if not shows_at_zoom(zoom):
		visible = false
		return
	var positions: PackedVector2Array = _provider.call()
	if positions.is_empty():
		visible = false
		return
	visible = true
	var view: Vector2 = get_viewport().get_visible_rect().size
	var cam_pos: Vector2 = _camera.position
	_build_commands(positions, cam_pos, zoom, view)
	_draw.queue_redraw()


## Nearest-first so the cap keeps the most relevant monsters.
func _build_commands(positions: PackedVector2Array, cam_pos: Vector2,
		zoom: float, view: Vector2) -> void:
	_diamonds.clear()
	_arrows.clear()
	var t: float = Time.get_ticks_msec() / 1000.0
	var pulse: float = pulse_for(t)
	var idx: Array = []
	for i: int in positions.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		return positions[a].distance_squared_to(cam_pos) \
			< positions[b].distance_squared_to(cam_pos))
	var count := 0
	for i: int in idx:
		if count >= MAX_MARKERS:
			break
		var s: Vector2 = world_to_screen(positions[i], cam_pos, zoom, view)
		if s.x >= 0.0 and s.x <= view.x and s.y >= 0.0 and s.y <= view.y:
			_diamonds.append({"kind": "diamond", "at": s, "r": diamond_radius(pulse),
				"pulse": pulse, "ang": 0.0})
		else:
			var c: Vector2 = edge_clamp(s, view)
			_arrows.append({"kind": "arrow", "at": c, "r": 0.0,
				"pulse": pulse, "ang": arrow_angle(s, c)})
		count += 1


class _MarkerDraw extends Node2D:
	## Draws the parent's commands in screen pixels (child of CanvasLayer).
	var _owner: DisasterMarkers = null

	func _draw() -> void:
		if _owner == null:
			return
		for d: Dictionary in _owner._diamonds:
			_draw_diamond(d["at"], d["r"], d["pulse"])
		for a: Dictionary in _owner._arrows:
			_draw_arrow(a["at"], a["ang"])

	## HTML verbatim diamond: square rotated PI/4, red fill at
	## 0.22+0.22*pulse alpha, #ff0000 stroke width 3.
	func _draw_diamond(at: Vector2, r: float, pulse: float) -> void:
		var pts := PackedVector2Array([
			at + Vector2(0, -r), at + Vector2(r, 0),
			at + Vector2(0, r), at + Vector2(-r, 0)])
		var fill := Color(DisasterMarkers.MARK_RED,
			DisasterMarkers.diamond_alpha(pulse))
		draw_colored_polygon(pts, fill)
		var outline := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		draw_polyline(outline, DisasterMarkers.MARK_RED, 3.0)
		# Vector "!" (bar + dot) — no font glyphs on the iPhone path.
		var bar_top: Vector2 = at + Vector2(0, -8)
		var bar_bot: Vector2 = at + Vector2(0, 4)
		draw_line(bar_top, bar_bot, DisasterMarkers.MARK_RED, 5.0)
		draw_circle(at + Vector2(0, 10), 3.0, DisasterMarkers.MARK_RED)

	## HTML verbatim arrow: rotated triangle + white "!" inside.
	func _draw_arrow(at: Vector2, ang: float) -> void:
		var tip: Vector2 = DisasterMarkers.ARROW_TIP
		var ba: Vector2 = DisasterMarkers.ARROW_BASE_A
		var bb: Vector2 = DisasterMarkers.ARROW_BASE_B
		var rot := func(p: Vector2) -> Vector2: return at + p.rotated(ang)
		draw_colored_polygon(PackedVector2Array(
			[rot.call(tip), rot.call(ba), rot.call(bb)]),
			DisasterMarkers.MARK_RED)
		var off := Vector2(2, 1).rotated(ang)
		draw_line(at + off + Vector2(0, -5).rotated(ang),
			at + off + Vector2(0, 2).rotated(ang),
			DisasterMarkers.MARK_WHITE, 3.0)
		draw_circle(at + off + Vector2(0, 5).rotated(ang), 1.8,
			DisasterMarkers.MARK_WHITE)
