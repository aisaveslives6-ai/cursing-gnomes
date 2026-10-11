extends SceneTree
## Cursing Gnomes — worldgen 3D carousel input tests (Jeremy 2026-10-05).
##
## The world-setup screen's world-type + map-size carousels live inside a
## vertical ScrollContainer (same treatment as the faction carousel).
## This suite proves the shared input path is healthy:
##   1. vertical page-scroll starting on a carousel never reselects a card
##   2. horizontal drags still spin the carousel
##   3. a clean tap on a side card still selects it (tap-to-select alive)
##   4. the real iPhone dispatch order (emulated mouse right after each
##      touch event) keeps a vertical scroll a no-op
##
## Both carousels share _on_car_input; the world-type one is exercised.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_worldgen_carousel_input.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

var _passed := 0
var _failed := 0
var _ws: WorldSetupScreen


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + name)


func _stouch(pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.pressed = pressed
	e.position = pos
	return e


func _sdrag(pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.position = pos
	return e


func _mpress(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.pressed = pressed
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = pos
	return e


func _mmove(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	return e


## Give the carousel a realistic iPhone-ish size and lay the cards out.
func _layout_car(st: Dictionary) -> void:
	var view: Control = st["view"]
	view.size = Vector2(975.0, 1000.0)  # 390x400 @ 2.5x
	_ws._car_layout(st)


## A point a real tap would land on a side card alone: scan each
## non-selected card's visible row for a point not covered by any deeper
## (front-er) card. The front card is huge here, so only the side cards'
## outer slivers qualify — centers are buried under the front card.
func _side_card_point(st: Dictionary) -> Vector2:
	var cards: Array = st["cards"]
	var n: int = cards.size()
	var step: float = TAU / float(n)
	var angle: float = float(st["angle"])
	var view: Control = st["view"]
	var rects: Array = []
	var depths: Array = []
	for i in n:
		var card: Control = cards[i]["node"]
		rects.append(Rect2(card.position, card.size * card.scale))
		depths.append(0.5 + 0.5 * cos(angle + float(i) * step))
	for i in n:
		if str(cards[i]["id"]) == str(st["sel"]):
			continue
		var r: Rect2 = rects[i]
		var cy: float = r.position.y + r.size.y * 0.5
		for sxi in 13:
			var px: float = r.position.x \
				+ r.size.x * (float(sxi) / 12.0)
			var p := Vector2(px, cy)
			if p.x < 0.0 or p.x >= view.size.x:
				continue
			var covered := false
			for j in n:
				if i == j:
					continue
				if float(depths[j]) > float(depths[i]) \
						and (rects[j] as Rect2).has_point(p):
					covered = true
					break
			if not covered:
				return p
	return Vector2(-1, -1)


func _init() -> void:
	_ws = WorldSetupScreen.new()
	root.add_child(_ws)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var st: Dictionary = _ws._type_car
	_layout_car(st)
	var start_id: String = str(st["sel"])

	# 1. Vertical page-scroll starting on the carousel: no reselect.
	_ws._on_car_input(_stouch(true, Vector2(400, 300)), st)
	_ws._on_car_input(_sdrag(Vector2(403, 380)), st)
	_check(not bool(st["dragging"]),
		"vertical drag never engages the carousel spin")
	_check(not bool(st["moved"]),
		"vertical drag never marks the press as moved")
	var angle_before: float = float(st["angle"])
	_ws._on_car_input(_stouch(false, Vector2(403, 380)), st)
	_check(str(st["sel"]) == start_id,
		"vertical scroll release does not reselect a card")
	_check(float(st["angle"]) == angle_before,
		"vertical scroll does not rotate the carousel")

	# 2. Horizontal drag still spins the carousel.
	var a0: float = float(st["angle"])
	_ws._on_car_input(_stouch(true, Vector2(400, 300)), st)
	_ws._on_car_input(_sdrag(Vector2(560, 303)), st)
	_check(bool(st["moved"]), "horizontal drag engages the spin")
	_check(float(st["angle"]) != a0,
		"horizontal drag rotates the carousel")
	_ws._on_car_input(_stouch(false, Vector2(560, 303)), st)

	# 3. Clean tap on a side card still selects it (tap-to-select alive).
	_ws._car_snap_to(st, start_id, true)
	_layout_car(st)
	var pt := _side_card_point(st)
	_check(pt.x >= 0.0, "found an unoccluded side-card tap point")
	if pt.x >= 0.0:
		_ws._on_car_input(_stouch(true, pt), st)
		_ws._on_car_input(_stouch(false, pt), st)
		_check(str(st["sel"]) != start_id,
			"tap on a side card selects that world type")

	# 4. Real iPhone dispatch order (Godot emits the emulated mouse event
	# right after each touch event): vertical scroll stays a no-op.
	_ws._car_snap_to(st, start_id, true)
	_layout_car(st)
	_ws._on_car_input(_stouch(true, Vector2(400, 300)), st)
	_ws._on_car_input(_mpress(true, Vector2(400, 300)), st)
	_ws._on_car_input(_sdrag(Vector2(402, 390)), st)
	_ws._on_car_input(_mmove(Vector2(402, 390)), st)
	_ws._on_car_input(_stouch(false, Vector2(402, 390)), st)
	_ws._on_car_input(_mpress(false, Vector2(402, 390)), st)
	_check(str(st["sel"]) == start_id,
		"emulated-mouse double sequence: vertical scroll does not reselect")

	# 5. Same double sequence, horizontal: spin still works.
	var a1: float = float(st["angle"])
	_ws._on_car_input(_stouch(true, Vector2(400, 300)), st)
	_ws._on_car_input(_mpress(true, Vector2(400, 300)), st)
	_ws._on_car_input(_sdrag(Vector2(580, 302)), st)
	_ws._on_car_input(_mmove(Vector2(580, 302)), st)
	_check(float(st["angle"]) != a1,
		"emulated-mouse double sequence: horizontal drag still spins")
	_ws._on_car_input(_stouch(false, Vector2(580, 302)), st)
	_ws._on_car_input(_mpress(false, Vector2(580, 302)), st)

	print("test_worldgen_carousel_input: %d passed, %d failed"
		% [_passed, _failed])
	quit(1 if _failed > 0 else 0)
