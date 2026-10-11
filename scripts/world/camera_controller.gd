class_name CameraController
extends Camera2D
## Cursing Gnomes — RTS camera (Milestone 2).
##
## Single-finger/mouse drag pans (drag always wins). Two-finger pinch zooms.
## Mouse wheel zooms. Tap (quick press-release without drag) emits `tapped`
## for the Selection system. Position is clamped to the map bounds plus 25% overscroll per side.
##
## Touch-first: with emulate_touch_from_mouse=true, desktop mouse drives the
## same ScreenTouch/ScreenDrag paths, so dev testing exercises phone behavior.


## Emitted on tap with the SCREEN position; Selection converts to world.
signal tapped(screen_pos: Vector2)
## Wall-drag placement (buildings port): while `wall_drag_armed` is true,
## single-finger press/move/release bypasses pan/tap and routes here.
signal wall_pressed(screen_pos: Vector2)
signal wall_moved(screen_pos: Vector2)
signal wall_released(screen_pos: Vector2)
var wall_drag_armed := false

const MIN_ZOOM := 0.08  # Jeremy 2026-10-03: paper map never showed — camera couldn't zoom past the 0.16 threshold. Now it can.
const MAX_ZOOM := 4.0  # Jeremy 2026-10-02: "can't even zoom in enough" — was 2.0
const TAP_MAX_DIST := 24.0   # px of movement before a press becomes a drag
const TAP_MAX_TIME := 0.4    # seconds before a press stops being a tap

var map_bounds := Rect2(0, 0, 4096, 4096)

var _touches := {}  # touch index -> Vector2 screen position
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _moved := false
var _pinch_dist := 0.0


func _ready() -> void:
	make_current()


## Points the camera at the map. Call once from World._ready().
func setup(bounds: Rect2, start_pos: Vector2, start_zoom: float) -> void:
	map_bounds = bounds
	zoom = Vector2(start_zoom, start_zoom)
	position = start_pos
	clamp_now()


## Screen (viewport) point -> world point, for tap/selection math.
func screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


## Re-clamp after external changes (e.g. zoom set directly).
func clamp_now() -> void:
	position = clamp_position(position, get_viewport_rect().size, zoom.x, map_bounds)


## Fraction of the map size the camera may pan beyond each edge.
## Jeremy 2026-10-05: scroll outside the map — outside is paper map border.
const OVERSCROLL_FRACTION := 0.25

## Pure clamp math — headless-testable without a live camera/viewport.
static func clamp_position(pos: Vector2, view_size: Vector2, zoom: float, bounds: Rect2) -> Vector2:
	var half_view: Vector2 = view_size / zoom * 0.5
	# Jeremy 2026-10-05: overscroll — the effective bounds grow 25% of the
	# map size on each side so the paper-map world border is reachable.
	var pad: Vector2 = bounds.size * OVERSCROLL_FRACTION
	var eb := Rect2(bounds.position - pad, bounds.size + pad * 2.0)
	# If the view is bigger than the expanded bounds on an axis, center it.
	var hx: float = minf(half_view.x, eb.size.x * 0.5)
	var hy: float = minf(half_view.y, eb.size.y * 0.5)
	return Vector2(
		clampf(pos.x, eb.position.x + hx, eb.end.x - hx),
		clampf(pos.y, eb.position.y + hy, eb.end.y - hy))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() == 1:
				_press_pos = st.position
				_press_time = Time.get_ticks_msec() / 1000.0
				_moved = false
				if wall_drag_armed:
					wall_pressed.emit(st.position)
					_moved = true  # suppress tap; release routes to wall
			elif _touches.size() == 2:
				_pinch_dist = _pair_distance()
				_moved = true  # two fingers can never be a tap
		else:
			var was_single: bool = _touches.size() == 1 and _touches.has(st.index)
			_touches.erase(st.index)
			if wall_drag_armed and was_single:
				wall_released.emit(st.position)
				_moved = true
			if _touches.size() == 1:
				# Dropped from pinch back to one finger: re-anchor the drag
				# so the remaining finger doesn't jump the camera.
				_press_pos = _touches.values()[0]
				_moved = true
			elif was_single and not _moved:
				var dt: float = Time.get_ticks_msec() / 1000.0 - _press_time
				if dt <= TAP_MAX_TIME:
					tapped.emit(st.position)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() == 1:
			if wall_drag_armed:
				wall_moved.emit(sd.position)
				_moved = true
			elif sd.position.distance_to(_press_pos) > TAP_MAX_DIST:
				_moved = true
			if _moved:
				# Content follows the finger: camera moves opposite the drag.
				# FIX 2026-10-02: clamp relative to prevent iOS Safari touch spikes
				# from snapping the camera. Max 100px per event.
				var rel: Vector2 = sd.relative
				if rel.length() > 100.0:
					rel = rel.normalized() * 100.0
				position += -rel / zoom.x
				clamp_now()
		elif _touches.size() == 2:
			_handle_pinch()


func _pair_distance() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _handle_pinch() -> void:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return
	var p0: Vector2 = pts[0]
	var p1: Vector2 = pts[1]
	var new_dist: float = p0.distance_to(p1)
	var mid: Vector2 = (p0 + p1) * 0.5
	if _pinch_dist > 0.0 and new_dist > 0.0:
		_zoom_at(mid, new_dist / _pinch_dist)
	_pinch_dist = new_dist


## Zoom keeping the world point under screen_pos stable.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before: Vector2 = screen_to_world(screen_pos)
	var z: float = clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	var after: Vector2 = screen_to_world(screen_pos)
	position += before - after
	clamp_now()
