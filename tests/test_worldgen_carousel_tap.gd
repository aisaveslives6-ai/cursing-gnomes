extends SceneTree
## Cursing Gnomes — worldgen carousel tap/scroll parity tests (2026-10-05).
##
## world_setup.gd's two card carousels (world type, map size) sit inside a
## vertical ScrollContainer and share the faction carousel's elliptical-track
## math. The faction carousel needed two fixes (tap-to-select was dead;
## vertical page-scrolls reselected cards). This suite locks in that the
## worldgen carousels behave correctly on all three paths:
##   1. Clean tap on a side card selects it (tap is NOT clobbered by the
##      release snap: _car_tap_at self-snaps instantly via _car_snap_to, and
##      _car_snap_nearest recomputes from the already-moved angle).
##   2. Horizontal drag spins; release snaps to the nearest front card and
##      the selection follows the front card.
##   3. Clearly-vertical drag cancels the press (pressing=false in
##      _car_try_lock); release is a no-op so the ScrollContainer keeps
##      the page-scroll gesture — no reselect, no rotation.
## Plus tap-on-empty-area changes nothing, and the real iPhone emulated-
## mouse double-dispatch order (touch event immediately followed by the
## emulated mouse event).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_worldgen_carousel_tap.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

var _passed := 0
var _failed := 0
var _screen: WorldSetupScreen


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


func _plain_card(id: String) -> Button:
	var b := Button.new()
	b.text = id
	return b


## Fresh carousel: 4 cards, iPhone-ish view size, laid out, no selection.
## Kind "size": mechanically identical to "type", but _car_apply's desc
## update needs no TYPES/SIZES lookup for the test ids (keeps the run
## free of harness-induced SCRIPT ERROR noise).
func _fresh_car(kind := "size") -> Dictionary:
	var st: Dictionary = _screen._car_make(["a", "b", "c", "d"],
		_plain_card, kind)
	var view: Control = st["view"]
	root.add_child(view)
	view.size = Vector2(975.0, 825.0)  # 390x330 @ 2.5x
	_screen._car_layout(st)
	return st


## Angle the carousel must hold for card idx to be front-center.
func _slot_angle(n: int, idx: int) -> float:
	return -float(idx) * TAU / float(n)


## Center of the first non-front card whose center isn't covered by a
## deeper card — a point a real tap would land on that card alone.
func _side_card_point(st: Dictionary) -> Vector2:
	var cards: Array = st["cards"]
	var n: int = cards.size()
	var step: float = TAU / float(n)
	var angle: float = float(st["angle"])
	var rects: Array = []
	var depths: Array = []
	for i in n:
		var card: Control = (cards[i] as Dictionary)["node"]
		rects.append(Rect2(card.position, card.size * card.scale))
		depths.append(0.5 + 0.5 * cos(angle + float(i) * step))
	for i in n:
		var cid: String = str((cards[i] as Dictionary)["id"])
		if cid == str(st["sel"]):
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


func _input(st: Dictionary, ev: InputEvent) -> void:
	_screen._on_car_input(ev, st)


func _init() -> void:
	_screen = WorldSetupScreen.new()
	root.add_child(_screen)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	# _refresh_preview (called by _car_apply) writes _seed_label; the full
	# screen build is bypassed here, so stub it. Deterministic 1.0 scale
	# for the test carousels regardless of the device-scale _build() set.
	_screen._seed_label = Label.new()
	_screen._ui_scale = 1.0

	# 1. Clean tap on a side card selects it — and the release snap must
	# not clobber the tap (angle/target already sit on the tapped slot).
	var st := _fresh_car()
	_screen._car_snap_to(st, "a", true)
	_screen._car_layout(st)
	var pt := _side_card_point(st)
	_check(pt.x >= 0.0, "found an unoccluded side-card tap point")
	if pt.x >= 0.0:
		_input(st, _stouch(true, pt))
		_input(st, _stouch(false, pt))
		var sel: String = str(st["sel"])
		_check(sel != "a" and sel != "", "tap on a side card selects it")
		var idx := ["a", "b", "c", "d"].find(sel)
		if idx >= 0:
			var want: float = _slot_angle(4, idx)
			_check(is_zero_approx(float(st["angle"]) - want),
				"tap snaps rotation to the tapped card slot")
			_check(is_zero_approx(float(st["target"]) - want),
				"tap leaves target on the tapped card slot")

	# 2. Horizontal drag spins; release snaps to nearest front card and
	# the selection follows the front card.
	var st2 := _fresh_car()
	_screen._car_snap_to(st2, "a", true)
	_screen._car_layout(st2)
	var a0: float = float(st2["angle"])
	_input(st2, _stouch(true, Vector2(400, 300)))
	_input(st2, _sdrag(Vector2(700, 303)))
	_check(bool(st2["moved"]), "horizontal drag engages the spin")
	_check(float(st2["angle"]) != a0, "horizontal drag rotates carousel")
	_input(st2, _stouch(false, Vector2(700, 303)))
	var n2: int = (st2["cards"] as Array).size()
	var step2: float = TAU / float(n2)
	var k2: float = round(float(st2["angle"]) / step2)
	var front2: String = str((st2["cards"] as Array)[int(posmod(-k2, n2))]["id"])
	_check(str(st2["sel"]) == front2,
		"release snaps selection to the front card")

	# 3. Vertical page-scroll starting on the carousel: cancelled press,
	# release is a no-op — the ScrollContainer keeps the gesture.
	var st3 := _fresh_car()
	_screen._car_snap_to(st3, "a", true)
	_screen._car_layout(st3)
	_input(st3, _stouch(true, Vector2(400, 300)))
	_input(st3, _sdrag(Vector2(403, 400)))
	_check(not bool(st3["dragging"]), "vertical drag cancels carousel press")
	_check(not bool(st3["moved"]), "vertical drag never engages spin")
	var ang3: float = float(st3["angle"])
	_input(st3, _stouch(false, Vector2(403, 400)))
	_check(str(st3["sel"]) == "a", "vertical scroll does not reselect")
	_check(float(st3["angle"]) == ang3, "vertical scroll does not rotate")

	# 4. Tap on empty area (below the card track) changes nothing.
	var st4 := _fresh_car()
	_screen._car_snap_to(st4, "b", true)
	_screen._car_layout(st4)
	_input(st4, _stouch(true, Vector2(487, 810)))
	_input(st4, _stouch(false, Vector2(487, 810)))
	_check(str(st4["sel"]) == "b", "tap on empty area keeps selection")
	_check(is_zero_approx(float(st4["angle"]) - _slot_angle(4, 1)),
		"tap on empty area keeps rotation")

	# 5. Real iPhone dispatch order (emulated mouse right after touch):
	# vertical scroll stays a no-op, horizontal drag still spins.
	var st5 := _fresh_car()
	_screen._car_snap_to(st5, "a", true)
	_screen._car_layout(st5)
	_input(st5, _stouch(true, Vector2(400, 300)))
	_input(st5, _mpress(true, Vector2(400, 300)))
	_input(st5, _sdrag(Vector2(402, 390)))
	_input(st5, _mmove(Vector2(402, 390)))
	_input(st5, _stouch(false, Vector2(402, 390)))
	_input(st5, _mpress(false, Vector2(402, 390)))
	_check(str(st5["sel"]) == "a",
		"emulated-mouse double sequence: vertical scroll does not reselect")
	var st6 := _fresh_car()
	_screen._car_snap_to(st6, "a", true)
	_screen._car_layout(st6)
	var a6: float = float(st6["angle"])
	_input(st6, _stouch(true, Vector2(400, 300)))
	_input(st6, _mpress(true, Vector2(400, 300)))
	_input(st6, _sdrag(Vector2(700, 302)))
	_input(st6, _mmove(Vector2(700, 302)))
	_check(float(st6["angle"]) != a6,
		"emulated-mouse double sequence: horizontal drag still spins")
	_input(st6, _stouch(false, Vector2(700, 302)))
	_input(st6, _mpress(false, Vector2(700, 302)))

	# 6. Mouse path: clean click selects a side card (desktop 16:9/4:3).
	var st7 := _fresh_car()
	_screen._car_snap_to(st7, "a", true)
	_screen._car_layout(st7)
	var pt7 := _side_card_point(st7)
	if pt7.x >= 0.0:
		_input(st7, _mpress(true, pt7))
		_input(st7, _mmove(pt7))  # emulated hover, no drag
		_input(st7, _mpress(false, pt7))
		_check(str(st7["sel"]) != "a" and str(st7["sel"]) != "",
			"mouse click on a side card selects it")

	print("test_worldgen_carousel_tap: %d passed, %d failed"
		% [_passed, _failed])
	quit(1 if _failed > 0 else 0)
