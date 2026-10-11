class_name ZoneTool
extends Node2D
## Cursing Gnomes — zone painting tool + zone overlay renderer.
##
## Activated from the HUD Zone tab. Press-drag-release paints a zone rect of
## the selected type; a quick tap paints a single 96 px lot (HTML rule).
## While active it consumes input in _unhandled_input so the camera doesn't
## pan mid-paint — HUD buttons consume their own taps first, so they still
## work while painting.
##
## Also draws the translucent zone overlay (toggleable): green residential,
## blue commercial, orange industrial, red military.
##
## Touch-first: painting stays active until Done/Cancel so several zones can
## be painted in one pass; 96 px cells are easy finger targets.


const ZONE_IDS := ["zone_R", "zone_C", "zone_I", "zone_M", "zone_dezone"]
const TAP_MAX_SIZE := 24.0  # a drag smaller than this becomes one lot


var game: GameState
var zoning: SimZoning
var camera: CameraController

var painting := false
var paint_type := ""      # one of ZONE_IDS
var paint_faction := ""
# Jeremy 2026-10-05: zone overlays OFF by default — the big colored
# squares shouldn't show during normal play. Toggled on when the zone
# tool is active.
var show_overlay := false

var _pressing := false
var _drag_start := Vector2.ZERO
var _drag_end := Vector2.ZERO


func setup(p_game: GameState, p_zoning: SimZoning,
		p_camera: CameraController) -> void:
	game = p_game
	zoning = p_zoning
	camera = p_camera
	if game != null:
		game.bus.zone_changed.connect(queue_redraw)


## Begins painting a zone type (tapping the active type again cancels).
func start_paint(ztype: String, faction: String) -> void:
	if ztype not in ZONE_IDS:
		return
	if painting and paint_type == ztype:
		cancel()
		return
	painting = true
	paint_type = ztype
	paint_faction = faction
	_pressing = false
	# Show zones while painting so the player can see where they go.
	show_overlay = true
	queue_redraw()
	queue_redraw()


func cancel() -> void:
	painting = false
	paint_type = ""
	_pressing = false
	show_overlay = false
	queue_redraw()


func toggle_overlay() -> void:
	show_overlay = not show_overlay
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not painting or camera == null:
		return
	# NOTE: with emulate_mouse_from_touch a finger generates BOTH touch and
	# mouse events; _begin/_commit are idempotent so the doubles are harmless.
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_commit_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pressing:
		_drag_end = camera.screen_to_world(event.position)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_commit_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _pressing:
		_drag_end = camera.screen_to_world(event.position)
		queue_redraw()
		get_viewport().set_input_as_handled()


func _begin_drag(screen_pos: Vector2) -> void:
	_pressing = true
	_drag_start = camera.screen_to_world(screen_pos)
	_drag_end = _drag_start
	queue_redraw()


func _commit_drag() -> void:
	if not _pressing:
		return
	_pressing = false
	var a := _drag_start
	var b := _drag_end
	var rect := Rect2(a, b - a)
	if absf(rect.size.x) < TAP_MAX_SIZE and absf(rect.size.y) < TAP_MAX_SIZE:
		# Tap (no drag): one 96 px lot centered on the tap.
		var half := SimZoning.ZONE_CELL * 0.5
		rect = Rect2(b - Vector2(half, half),
			Vector2(SimZoning.ZONE_CELL, SimZoning.ZONE_CELL))
	if paint_type == "zone_dezone":
		zoning.dezone(paint_faction, rect)
	else:
		zoning.paint_zone(paint_type.trim_prefix("zone_"),
			paint_faction, rect)
	# Stay active: the player can paint more zones, then hits Done.
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	if show_overlay:
		for z: Dictionary in game.zones:
			_draw_zone(z)
	if painting and _pressing:
		_draw_preview()


func _draw_zone(z: Dictionary) -> void:
	var ztype: String = String(z.get("type", ""))
	var r: Rect2 = SimZoning._norm_rect(z["rect"])
	var c: Color = SimZoning.zone_color(ztype)
	draw_rect(r, Color(c.r, c.g, c.b, 0.22))
	draw_rect(r, Color(c.r, c.g, c.b, 0.85), false, 2.0)
	# Zone letter, centered.
	var font: Font = ThemeDB.fallback_font
	draw_string(font, r.get_center() + Vector2(-9.0, 11.0), ztype,
		HORIZONTAL_ALIGNMENT_CENTER, 24.0, 30, Color(c.r, c.g, c.b, 0.9))


func _draw_preview() -> void:
	var r: Rect2 = SimZoning._norm_rect(Rect2(_drag_start, _drag_end - _drag_start))
	var c := Color(0.9, 0.9, 0.9)
	if paint_type != "zone_dezone":
		c = SimZoning.zone_color(paint_type.trim_prefix("zone_"))
	draw_rect(r, Color(c.r, c.g, c.b, 0.35))
	draw_rect(r, Color(c.r, c.g, c.b, 1.0), false, 3.0)
