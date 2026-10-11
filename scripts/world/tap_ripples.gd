class_name TapRipples
extends Node2D
## Cursing Gnomes — tap ripple touch feedback (port completion).
##
## HTML source of truth: pushTapRipple / tickTapRipples / drawTapRipples
## (fix79 index.html ~line 2914400, "every world tap answers with a visible
## ring (fluid, alive)"). HTML handleTap pushes {x, y, life: 0.45, max: 0.45}
## with a 12-ripple cap; draw expands a ring r = 8 + k * 34, alpha
## 0.75 * (1 - k), lineWidth 3 * (1 - k) + 1, stroke '#ffe082', culled with
## inView(r.x, r.y, 60).
##
## Improvements over the HTML original:
##   - A second inner echo ring (radius * 0.55, half alpha, 60% width) plus
##     a tiny fading center dot: the tap feels alive instead of flat.
##   - Zero per-frame cost when idle: _process disables itself and visible
##     goes false while no ripples are alive, so _draw short-circuits.
##
## Wired in world.gd _ready() (camera) + _on_tapped() pushes the world pos,
## mirroring HTML handleTap pushing at entry before any tap handling.
## Tests drive the pure statics and the push/step helpers headless.


## HTML-verbatim numbers.
const RIPPLE_LIFE := 0.45          ## life and max, seconds
const MAX_RIPPLES := 12            ## cap; oldest dropped first
const RING_COL := Color8(0xff, 0xe0, 0x82)  ## #ffe082
const START_RADIUS := 8.0          ## r = 8 + k * 34
const RADIUS_GROW := 34.0
const START_WIDTH := 1.0            ## lineWidth = 3 * (1 - k) + 1
const WIDTH_SHRINK := 3.0
const MAX_ALPHA := 0.75            ## alpha = 0.75 * (1 - k)
const VIEW_MARGIN := 60.0          ## inView margin, world px


var _camera: Camera2D = null
var _ripples: Array = []  ## Dictionaries {pos: Vector2, life: float}


func _init() -> void:
	z_index = 50  # above units/props (0), below CanvasLayer UI markers (10)


func set_camera(cam: Camera2D) -> void:
	_camera = cam


## HTML pushTapRipple: append, drop the oldest past the cap.
func push(world_pos: Vector2) -> void:
	_ripples.append({"pos": world_pos, "life": RIPPLE_LIFE})
	while _ripples.size() > MAX_RIPPLES:
		_ripples.pop_front()
	visible = true
	set_process(true)


## Number of live ripples (tests / HUD hooks).
func ripple_count() -> int:
	return _ripples.size()


## HTML drawTapRipples math as a pure function: k 0->1, alpha fades,
## radius grows 8->42, lineWidth shrinks 4->1.
static func draw_params(life: float) -> Dictionary:
	var k: float = clampf(1.0 - life / RIPPLE_LIFE, 0.0, 1.0)
	return {
		"k": k,
		"alpha": MAX_ALPHA * (1.0 - k),
		"radius": START_RADIUS + RADIUS_GROW * k,
		"width": START_WIDTH + WIDTH_SHRINK * (1.0 - k),
	}


func _process(delta: float) -> void:
	for i in range(_ripples.size() - 1, -1, -1):
		var r: Dictionary = _ripples[i]
		r["life"] = float(r["life"]) - delta
		if float(r["life"]) <= 0.0:
			_ripples.remove_at(i)
	if _ripples.is_empty():
		visible = false
		set_process(false)
		queue_redraw()
		return
	queue_redraw()


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
	if _ripples.is_empty():
		return
	var view := _visible_rect().grow(VIEW_MARGIN)
	var have_view := view != Rect2()
	for r: Variant in _ripples:
		var pos: Vector2 = (r as Dictionary)["pos"]
		if have_view and not view.has_point(pos):
			continue  # HTML inView(r.x, r.y, 60) cull
		var p := draw_params(float((r as Dictionary)["life"]))
		var col := Color(RING_COL.r, RING_COL.g, RING_COL.b, float(p["alpha"]))
		var radius := float(p["radius"])
		var width := float(p["width"])
		# Outer ring: HTML verbatim.
		draw_arc(pos, radius, 0.0, TAU, 48, col, width, true)
		# Improvement: inner echo ring + fading center dot.
		var echo_col := Color(RING_COL.r, RING_COL.g, RING_COL.b,
				float(p["alpha"]) * 0.5)
		draw_arc(pos, radius * 0.55, 0.0, TAU, 40, echo_col, width * 0.6, true)
		var dot_col := Color(RING_COL.r, RING_COL.g, RING_COL.b,
				float(p["alpha"]) * 0.4)
		draw_circle(pos, 3.0, dot_col)
