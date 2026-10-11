extends SceneTree
## Cursing Gnomes — world-gen 3D card carousel tests (Jeremy 2026-10-03).
##
## World type and map size pickers use the faction-picker carousel
## treatment: generated landscape art per world type
## (assets/ui/worldgen/type_<key>.webp), generated parchment-map art per
## size (size_<key>.webp). Drag to spin, release snaps to the nearest
## card, tap a card to bring it front.
##
## Covers: both carousels build with the right card counts; all 10 card
## art textures load; programmatic select updates state + desc labels;
## snap-nearest math picks the front card; shaping-option changes update
## in place (no screen rebuild — carousels keep their spin state);
## world_confirmed emits the carousel-chosen type/size.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_worldgen_carousel.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		push_error("FAIL: " + test_name)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	await _test_carousels()
	await _test_direction_lock()
	await _test_snap_ease()
	await _test_preview()
	await _test_scrollbar()
	print("test_worldgen_carousel: %d passed, %d failed"
		% [_passed, _failed])
	if not _failures.is_empty():
		push_error("failures: " + str(_failures))
	quit(1 if _failed > 0 else 0)


func _test_carousels() -> void:
	var ws := WorldSetupScreen.new()
	ws.setup(["humans", "gnomes"], "gnomes")
	root.add_child(ws)
	await process_frame
	await process_frame

	# Both carousels built with the right card counts.
	var type_cards: Array = ws._type_car["cards"]
	var size_cards: Array = ws._size_car["cards"]
	_check("type carousel has 6 cards", type_cards.size() == 6)
	_check("size carousel has 4 cards", size_cards.size() == 4)
	_check("type carousel view exists",
		is_instance_valid(ws._type_car["view"]))
	_check("size carousel view exists",
		is_instance_valid(ws._size_car["view"]))

	# Card ids follow the declared orders.
	var type_ids: Array = []
	for c in type_cards:
		type_ids.append(str(c["id"]))
	_check("type card ids match TYPE_ORDER",
		type_ids == WorldSetupScreen.TYPE_ORDER)
	var size_ids: Array = []
	for c in size_cards:
		size_ids.append(str(c["id"]))
	_check("size card ids match SIZE_ORDER",
		size_ids == WorldSetupScreen.SIZE_ORDER)

	# All 10 generated card-art textures load (imported by --import).
	for k in WorldSetupScreen.TYPE_ORDER:
		var t := load("res://assets/ui/worldgen/type_%s.webp" % k) \
			as Texture2D
		_check("type card art loads: " + k, t != null)
	for k in WorldSetupScreen.SIZE_ORDER:
		var t2 := load("res://assets/ui/worldgen/size_%s.webp" % k) \
			as Texture2D
		_check("size card art loads: " + k, t2 != null)

	# Initial selection matches defaults.
	_check("type carousel initial sel is continents",
		str(ws._type_car["sel"]) == "continents")
	_check("size carousel initial sel sane",
		str(ws._size_car["sel"]) in ["mobile", "normal"])

	# Programmatic type select: state + desc + carousel sel.
	ws._on_type("wilds")
	_check("on_type sets _wtype", ws._wtype == "wilds")
	_check("on_type updates type desc",
		"primeval" in ws._type_desc.text.to_lower())
	_check("on_type snaps type carousel",
		str(ws._type_car["sel"]) == "wilds")

	# Programmatic size select: state + note + carousel sel.
	ws._on_size("huge", false)
	_check("on_size sets _size", ws._size == "huge")
	_check("on_size note shows dims", "32k" in ws._size_note.text)
	_check("on_size snaps size carousel",
		str(ws._size_car["sel"]) == "huge")

	# Snap-nearest math: rotate exactly one step; the card one slot back
	# of the order lands front-center.
	var step: float = TAU / 6.0
	ws._type_car["angle"] = step
	ws._car_snap_nearest(ws._type_car)
	_check("snap_nearest picks front card after one-step spin",
		ws._wtype == "wilds")
	_check("snap_nearest sets carousel sel",
		str(ws._type_car["sel"]) == "wilds")

	# Snap-to instant: no error, sel set.
	ws._car_snap_to(ws._size_car, "mobile", true)
	_check("snap_to instant sets sel",
		str(ws._size_car["sel"]) == "mobile")

	# Shaping-option change updates in place — the carousels are NOT
	# rebuilt (views stay valid, spin state kept).
	var type_view: Control = ws._type_car["view"]
	ws._on_opt("water", "high")
	_check("on_opt sets opt value", str(ws._opts.get("water")) == "high")
	_check("on_opt does not rebuild type carousel",
		is_instance_valid(type_view) and ws._type_car["view"] == type_view)
	_check("on_opt keeps type selection",
		str(ws._type_car["sel"]) == "wilds")

	# Confirm emits the carousel-chosen type/size.
	var got := {}
	ws.world_confirmed.connect(func(t: String, s: String, o: Dictionary,
			seed: int) -> void:
		got["t"] = t
		got["s"] = s
		got["o"] = o
		got["seed"] = seed)
	ws._on_type("frozen")
	ws._on_size("large", false)
	await process_frame
	await process_frame
	ws._on_start()
	_check("confirm emits carousel type", str(got.get("t")) == "frozen")
	_check("confirm emits carousel size", str(got.get("s")) == "large")
	_check("confirm emits live seed",
		int(got.get("seed", 0)) == ws._seed)

	ws.queue_free()


## Jeremy 2026-10-03: vertical drags on a carousel must NOT engage it —
## the menu ScrollContainer should get the gesture instead. Only a clearly
## horizontal drag locks the carousel.
func _test_direction_lock() -> void:
	var ws := WorldSetupScreen.new()
	ws.setup(["humans", "gnomes"], "gnomes")
	root.add_child(ws)
	await process_frame
	await process_frame

	# Horizontal-dominant drag engages the carousel.
	var st := {"press_x": 100.0, "press_y": 100.0,
		"pressing": true, "dragging": false}
	_check("horizontal drag locks carousel",
		ws._car_try_lock(st, Vector2(140.0, 108.0)) == true)
	_check("lock sets dragging", bool(st["dragging"]) == true)

	# Vertical-dominant drag releases the press back to the scroller.
	st = {"press_x": 100.0, "press_y": 100.0,
		"pressing": true, "dragging": false}
	_check("vertical drag does not lock",
		ws._car_try_lock(st, Vector2(108.0, 150.0)) == false)
	_check("vertical drag releases press", bool(st["pressing"]) == false)
	_check("vertical drag never sets dragging",
		bool(st["dragging"]) == false)

	# Small jitter under slop: undecided, press kept.
	st = {"press_x": 100.0, "press_y": 100.0,
		"pressing": true, "dragging": false}
	_check("sub-slop jitter undecided",
		ws._car_try_lock(st, Vector2(105.0, 104.0)) == false)
	_check("sub-slop keeps press", bool(st["pressing"]) == true)

	ws.queue_free()


## 2026-10-04: release-snapping needs a per-frame tick — _car_snap_nearest
## sets the target, _process eases angle toward it (a regression where the
## tick existed but nothing called it left carousels stuck off-center after
## a drag). Simulate a release and let real frames run.
func _test_snap_ease() -> void:
	var ws := WorldSetupScreen.new()
	ws.setup(["humans", "gnomes"], "gnomes")
	root.add_child(ws)
	await process_frame
	await process_frame

	# Spin the carousel off-center, then release: snap_nearest picks the
	# nearest card and sets a target the ease must converge to.
	ws._type_car["angle"] = 0.35
	ws._type_car["target"] = 0.35
	ws._car_snap_nearest(ws._type_car)
	var target := float(ws._type_car["target"])
	_check("snap_nearest sets a new target", target != 0.35)
	_check("snap_nearest picks a valid selection",
		str(ws._type_car["sel"]) in WorldSetupScreen.TYPE_ORDER)
	# Drive the tick directly with realistic frame deltas (headless test
	# frames run with near-zero delta, so waiting on real frames cannot
	# converge the wall-clock ease).
	var start_off: float = absf(0.35 - target)
	for i in 120:
		ws._car_tick(ws._type_car, 1.0 / 60.0)
	var end_off: float = absf(float(ws._type_car["angle"]) - target)
	_check("snap ease converges toward target", end_off < start_off)
	_check("snap ease reaches target", end_off < 0.01)

	# Same path on the size carousel.
	ws._size_car["angle"] = -0.6
	ws._size_car["target"] = -0.6
	ws._car_snap_nearest(ws._size_car)
	var starget := float(ws._size_car["target"])
	for i in 120:
		ws._car_tick(ws._size_car, 1.0 / 60.0)
	_check("size carousel snap ease converges",
		absf(float(ws._size_car["angle"]) - starget) < 0.01)

	# Wiring: _process must drive both carousels' ticks (the regression was
	# the tick existing with nothing calling it).
	ws._type_car["angle"] = 0.5
	ws._type_car["target"] = 0.0
	for i in 10:
		ws._process(1.0 / 60.0)
	_check("_process eases the type carousel",
		absf(float(ws._type_car["angle"])) < 0.5)

	ws.queue_free()


## Jeremy 2026-10-03: the world-gen preview must look like a real map —
## it now uses MapGen's own baked terrain image (hill shading, cliffs,
## snow/desert, banks, foam, territory tints) with tree/resource/
## waterfall/faction-start overlays drawn on top.
func _test_preview() -> void:
	var ws := WorldSetupScreen.new()
	ws.setup(["humans", "gnomes"], "gnomes")
	root.add_child(ws)
	await process_frame
	await process_frame

	# Static helpers: dot paints inside bounds, ring paints a circle.
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	WorldSetupScreen._dot(img, 16, 16, 2, Color.RED)
	_check("dot paints center", img.get_pixel(16, 16) == Color.RED)
	_check("dot paints edge", img.get_pixel(18, 16) == Color.RED)
	_check("dot leaves far pixel", img.get_pixel(0, 0) == Color.BLACK)
	img.fill(Color.BLACK)
	WorldSetupScreen._dot(img, 0, 0, 4, Color.GREEN)
	_check("dot clips at bounds", img.get_pixel(0, 0) == Color.GREEN)

	img.fill(Color.BLACK)
	WorldSetupScreen._ring(img, 16, 16, 6, 2, Color.BLUE)
	_check("ring paints outer edge", img.get_pixel(22, 16) == Color.BLUE)
	_check("ring leaves center empty", img.get_pixel(16, 16) == Color.BLACK)
	_check("ring leaves far pixel", img.get_pixel(0, 0) == Color.BLACK)

	# Full bake: the preview texture comes from MapGen's baked image,
	# so it is 512x512 with real terrain detail, not flat 128x128 tiles.
	var tr := TextureRect.new()
	ws._render_preview(tr)
	_check("render sets a texture", tr.texture != null)
	var itex := tr.texture as ImageTexture
	_check("texture is ImageTexture", itex != null)
	if itex != null:
		_check("preview width is bake size",
			itex.get_width() == MapGen.MAP_TILES * MapGen.BAKE_PX_PER_TILE)
		_check("preview height is bake size",
			itex.get_height() == MapGen.MAP_TILES * MapGen.BAKE_PX_PER_TILE)
		# Detail check: the baked image is not flat — sample a grid and
		# require many distinct colors (terrain variation, shading).
		var baked_img := itex.get_image()
		var seen := {}
		for gy in range(0, 512, 32):
			for gx in range(0, 512, 32):
				var c := baked_img.get_pixel(gx, gy)
				seen["%d,%d,%d" % [int(c.r * 31.0), int(c.g * 31.0), int(c.b * 31.0)]] = true
		_check("preview shows terrain variation", seen.size() > 30)
	_check("preview not stuck busy", ws._busy == false)

	ws.queue_free()


## Jeremy 2026-10-04: the world gen screen is long — it must show an
## always-visible scrollbar on the right that never overlaps content.
func _test_scrollbar() -> void:
	var ws := WorldSetupScreen.new()
	ws.setup(["humans", "gnomes"], "gnomes")
	root.add_child(ws)
	await process_frame
	await process_frame

	var scroll: ScrollContainer = null
	for n in ws.find_children("*", "ScrollContainer", true, false):
		scroll = n as ScrollContainer
		break
	_check("world setup has a ScrollContainer", scroll != null)
	if scroll == null:
		ws.queue_free()
		return
	_check("scrollbar always visible",
		scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_ALWAYS)
	_check("no horizontal scroll",
		scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	var vsb := scroll.get_v_scroll_bar()
	_check("scrollbar is a real VScrollBar", vsb != null)
	if vsb != null:
		_check("scrollbar has touchable width",
			vsb.custom_minimum_size.x >= 20.0)
	# The content column must leave a gutter >= the scrollbar width so the
	# bar never covers text or buttons (Jeremy 2026-10-04).
	var inner: VBoxContainer = null
	for ch in scroll.get_children():
		for gch in (ch as Node).get_children():
			if gch is VBoxContainer:
				inner = gch as VBoxContainer
	_check("scroll content vbox found", inner != null)
	if inner != null and vsb != null:
		var vp: Vector2 = ws.get_viewport().get_visible_rect().size
		var col_w: float = minf(vp.x * 0.94, ws._s(560.0))
		_check("content leaves scrollbar gutter",
			inner.custom_minimum_size.x <= col_w - vsb.custom_minimum_size.x - 1.0)

	ws.queue_free()
