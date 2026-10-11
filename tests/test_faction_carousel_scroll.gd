extends SceneTree
## Cursing Gnomes — faction-screen 3D carousel direction-lock tests
## (Jeremy 2026-10-05).
##
## The carousel lives inside a vertical ScrollContainer. Before the fix,
## a vertical page-scroll that started on the carousel never engaged the
## carousel's horizontal lock, so the release fired a tap and reselected
## whichever card the finger lifted over. Now a clearly-vertical drag
## cancels the press (no tap, no reselect); horizontal drags still spin;
## clean taps still select. Mirrors the worldgen carousels' _car_try_lock.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_faction_carousel_scroll.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

var _passed := 0
var _failed := 0
var _menu: MainMenu


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
func _layout_carousel(menu: MainMenu) -> void:
	menu._carousel3d_view.size = Vector2(975.0, 825.0)  # 390x330 @ 2.5x
	menu._carousel3d_layout()


## Center of the first non-front card whose center isn't covered by a
## deeper card — a point a real tap would land on that card alone.
func _side_card_point(menu: MainMenu) -> Vector2:
	var cards: Array = menu._carousel3d_cards
	var n: int = cards.size()
	var step: float = TAU / float(n)
	var rects: Array = []
	var depths: Array = []
	for i in n:
		var card: Control = cards[i]["node"]
		rects.append(Rect2(card.position, card.size * card.scale))
		depths.append(0.5 + 0.5 * cos(menu._carousel3d_angle + float(i) * step))
	for i in n:
		var fid: String = str(cards[i]["fid"])
		if fid == menu._selected_faction:
			continue
		var c: Vector2 = (rects[i] as Rect2).get_center()
		var covered := false
		for j in n:
			if i == j:
				continue
			if float(depths[j]) > float(depths[i]) \
					and (rects[j] as Rect2).has_point(c):
				covered = true
				break
		if not covered:
			return c
	return Vector2(-1, -1)


func _init() -> void:
	_menu = MainMenu.new()
	root.add_child(_menu)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var menu := _menu
	menu._show_faction()
	await process_frame
	_layout_carousel(menu)
	var start_fid: String = menu._selected_faction

	# 1. Vertical page-scroll starting on the carousel: no reselect.
	menu._on_carousel3d_input(_stouch(true, Vector2(400, 300)))
	menu._on_carousel3d_input(_sdrag(Vector2(403, 380)))
	_check(not menu._carousel3d_dragging,
		"vertical drag cancels the carousel press")
	_check(not menu._carousel3d_moved,
		"vertical drag never engages the spin")
	var angle_before: float = menu._carousel3d_angle
	menu._on_carousel3d_input(_stouch(false, Vector2(403, 380)))
	_check(menu._selected_faction == start_fid,
		"vertical scroll release does not reselect a card")
	_check(menu._carousel3d_angle == angle_before,
		"vertical scroll does not rotate the carousel")

	# 2. Horizontal drag still spins the carousel.
	var a0: float = menu._carousel3d_angle
	menu._on_carousel3d_input(_stouch(true, Vector2(400, 300)))
	menu._on_carousel3d_input(_sdrag(Vector2(560, 303)))
	_check(menu._carousel3d_moved, "horizontal drag engages the spin")
	_check(menu._carousel3d_angle != a0,
		"horizontal drag rotates the carousel")
	menu._on_carousel3d_input(_stouch(false, Vector2(560, 303)))

	# 3. Clean tap on a side card still selects it.
	menu._carousel3d_snap_to(start_fid, true)
	_layout_carousel(menu)
	var pt := _side_card_point(menu)
	_check(pt.x >= 0.0, "found an unoccluded side-card tap point")
	if pt.x >= 0.0:
		menu._on_carousel3d_input(_stouch(true, pt))
		menu._on_carousel3d_input(_stouch(false, pt))
		_check(menu._selected_faction != start_fid,
			"tap on a side card selects that faction")

	# 4. Real iPhone dispatch order (Godot emits the emulated mouse event
	# right after each touch event): vertical scroll stays a no-op.
	menu._carousel3d_snap_to(start_fid, true)
	_layout_carousel(menu)
	menu._on_carousel3d_input(_stouch(true, Vector2(400, 300)))
	menu._on_carousel3d_input(_mpress(true, Vector2(400, 300)))
	menu._on_carousel3d_input(_sdrag(Vector2(402, 390)))
	menu._on_carousel3d_input(_mmove(Vector2(402, 390)))
	menu._on_carousel3d_input(_stouch(false, Vector2(402, 390)))
	menu._on_carousel3d_input(_mpress(false, Vector2(402, 390)))
	_check(menu._selected_faction == start_fid,
		"emulated-mouse double sequence: vertical scroll does not reselect")

	# 5. Same double sequence, horizontal: spin still works.
	var a1: float = menu._carousel3d_angle
	menu._on_carousel3d_input(_stouch(true, Vector2(400, 300)))
	menu._on_carousel3d_input(_mpress(true, Vector2(400, 300)))
	menu._on_carousel3d_input(_sdrag(Vector2(580, 302)))
	menu._on_carousel3d_input(_mmove(Vector2(580, 302)))
	_check(menu._carousel3d_angle != a1,
		"emulated-mouse double sequence: horizontal drag still spins")
	menu._on_carousel3d_input(_stouch(false, Vector2(580, 302)))
	menu._on_carousel3d_input(_mpress(false, Vector2(580, 302)))

	print("test_faction_carousel_scroll: %d passed, %d failed"
		% [_passed, _failed])
	quit(1 if _failed > 0 else 0)
