extends SceneTree
## Smoke test: MainMenu visual-parity rebuild — walk every screen headless.
## NOTE: _ready is deferred when adding nodes inside SceneTree._init, so the
## checks run deferred after two frames.

var _passed := 0
var _failed := 0
var _menu: MainMenu


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + name)


## Same >U+2500 rule as the HUD glyph tests: plain text labels never
## reach this high; anything above it is a tofu risk on iPhone Safari.
static func _has_glyph(s: String) -> bool:
	for i in range(s.length()):
		if s.unicode_at(i) > 0x2500:
			return true
	return false


## Collects "NodePath: text" for VISIBLE Labels/Buttons carrying glyphs.
## Hidden nodes are skipped — they never render. Menu-card icons are
## DrawnMenuIcon (pure vector drawing, not Labels/Buttons) so they never
## trip the walk even though their icon boxes are now visible.
static func _glyph_walk(n: Node, out: Array[String]) -> void:
	if n is Label or n is Button:
		var t: String = (n as Label).text if n is Label else (n as Button).text
		if n.is_visible_in_tree() and _has_glyph(t):
			out.append("%s: %s" % [n.get_path(), t])
	for c in n.get_children():
		_glyph_walk(c, out)


func _init() -> void:
	_menu = MainMenu.new()
	root.add_child(_menu)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var menu := _menu
	_check(menu._screen == "title", "boots to title screen")
	_check(menu._banner != null and is_instance_valid(menu._banner), "update banner present")
	_check(menu._continue_btn != null, "continue card present")
	# Jeremy 2026-10-04: menu footer must never promise tab-close autosave
	# (web exports can't catch tab close — only periodic autosave + save on
	# quit-to-menu run). Rendered label must match the constant.
	_check(not ("close the tab" in MainMenu.MENU_FOOT), "footer never claims tab-close autosave")
	_check("save v5" in MainMenu.MENU_FOOT, "footer still carries the save version")
	var _foot_lbl: Label = null
	var _stack: Array = [menu]
	while not _stack.is_empty():
		var _n: Node = _stack.pop_back()
		if _n is Label and (_n as Label).text == MainMenu.MENU_FOOT:
			_foot_lbl = _n as Label
			break
		for _c in _n.get_children():
			_stack.push_back(_c)
	_check(_foot_lbl != null and _foot_lbl.is_visible_in_tree(), "footer label renders on title screen")
	menu._dismiss_banner()
	_check(menu._banner == null, "banner dismisses on tap")
	# Faction screen.
	menu._show_faction()
	_check(menu._screen == "faction", "faction screen shows")
	_check(menu._ruler_input != null and menu._ruler_input.text == "", "ruler input defaults to blank")
	_check(menu._active_factions.size() == 5, "all 5 factions active by default")
	# Faction portraits (Jeremy 2026-10-02): cards use chibi art, not letter badges.
	for fid in ["humans", "ogres", "elves", "gnomes", "undead"]:
		var ptex := load("res://assets/ui/factions/%s.png" % fid) as Texture2D
		_check(ptex != null, "faction portrait exists: " + fid)
	var fcard: Button = menu._trading_card("humans")
	# 3D trading-card carousel (Jeremy 2026-10-03): cards are fixed-size
	# trading cards (portrait banner, name plate, stat strip).
	# Jeremy 2026-10-04: cards shrunk 240x340 -> 200x280 base so the whole
	# faction screen fits one iPhone screen — still huge touch targets.
	_check(fcard.custom_minimum_size.x >= 200 * menu._ui_scale,
		"trading cards are wide enough for touch (>=200px)")
	_check(fcard.custom_minimum_size.y >= 260 * menu._ui_scale,
		"trading cards are tall enough for touch (>=260px)")
	# All 5 factions reachable: each card can be created.
	for fid in ["humans", "ogres", "elves", "gnomes", "undead"]:
		var c: Button = menu._trading_card(fid)
		_check(c != null and is_instance_valid(c), "faction card reachable: " + fid)
		c.queue_free()
	fcard.queue_free()
	# Ruler input: iOS keyboard fix — focus mode set, virtual keyboard wired.
	_check(menu._ruler_input.focus_mode == Control.FOCUS_ALL, "ruler input focusable for iOS keyboard")
	# Custom in-game keyboard (Jeremy 2026-10-03: "Why not build a built in
	# keyboard?") — no OS virtual keyboard involved at all.
	menu._open_ruler_keyboard()
	_check(menu._ruler_kb != null and menu._ruler_kb.visible, "ruler keyboard opens")
	# Jeremy 2026-10-03: "Built in keyboard didn't pop up when I clicked to
	# type" — two root causes found: (1) _make_key used the Godot 3 property
	# size_stretch_ratio (crashed, keyboard built keyless); (2) _rebuild used
	# set_anchors_preset() after add_child, which "keeps" the zero size via
	# negative offsets — keyboard rendered 0x0. Regression coverage below.
	menu._ruler_kb.close()
	_check(not menu._ruler_kb.visible, "keyboard closed before tap-path test")
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.position = menu._ruler_input.size * 0.5
	menu._ruler_input._gui_input(tap)
	_check(menu._ruler_kb.visible, "tap on name field opens keyboard (tap path)")
	await process_frame
	await process_frame
	_check(menu._ruler_kb.size.x > 0.0 and menu._ruler_kb.size.y > 0.0,
		"keyboard root has non-zero size (anchor fix)")
	_check(menu._ruler_kb._letter_btns.size() == 26,
		"keyboard built all 26 letter keys")
	var _kb_geo_ok := true
	var _vp: Vector2 = menu.get_viewport().get_visible_rect().size
	for _ch in ["q", "a", "z", "m"]:
		var _b = menu._ruler_kb._letter_btns.get(_ch)
		var _r: Rect2 = _b.get_global_rect()
		if _r.size.x <= 0.0 or _r.size.y <= 0.0:
			_kb_geo_ok = false
		if _r.position.y < 0.0 or _r.position.y > _vp.y:
			_kb_geo_ok = false
	_check(_kb_geo_ok, "keyboard keys have size and are on-screen")
	# End-to-end: pressing a real key button types into the field.
	menu._ruler_input.text = ""
	(menu._ruler_kb._letter_btns["q"] as Button).pressed.emit()
	_check(menu._ruler_input.text == "q", "pressing key button types (end-to-end)")
	# Reset for the verbatim sequence below.
	menu._ruler_input.text = ""
	menu._ruler_kb._insert_letter("a")
	menu._ruler_kb._insert_letter("s")
	menu._ruler_kb._insert_letter("s")
	_check(menu._ruler_input.text == "ass", "keyboard types verbatim (ass works)")
	_check(menu._ruler_name_cache == "ass", "cache tracks keyboard input")
	menu._ruler_kb._backspace()
	_check(menu._ruler_input.text == "as", "keyboard backspace deletes one char")
	menu._ruler_kb._toggle_shift()
	menu._ruler_kb._insert_letter("s")
	_check(menu._ruler_input.text == "asS", "shift capitalizes exactly one letter")
	menu._ruler_kb._insert_letter("s")
	_check(menu._ruler_input.text == "asSs", "shift auto-releases after one letter")
	menu._ruler_kb._insert_raw(" ")
	menu._ruler_kb._toggle_shift()
	menu._ruler_kb._toggle_shift()
	_check(menu._ruler_kb._caps, "double-tap shift enables caps lock")
	menu._ruler_kb._insert_letter("b")
	_check(menu._ruler_input.text == "asSs B", "caps lock capitalizes")
	menu._ruler_kb._toggle_shift()
	menu._ruler_input.text = ""
	for i in 30:
		menu._ruler_kb._insert_letter("x")
	_check(menu._ruler_input.text.length() == 24, "keyboard respects max_length 24")
	# Char counter: visible, tracks live, reads "24/24" at the cap.
	menu._ruler_kb._process(0.016)
	_check(menu._ruler_kb._count_lbl != null and is_instance_valid(menu._ruler_kb._count_lbl),
		"keyboard has char counter label")
	_check(menu._ruler_kb._count_lbl.text == "24/24", "counter reads 24/24 at max_length")
	menu._ruler_kb._backspace()
	menu._ruler_kb._process(0.016)
	_check(menu._ruler_kb._count_lbl.text == "23/24", "counter drops to 23/24 after backspace")
	menu._ruler_input.text = ""
	menu._ruler_kb._process(0.016)
	_check(menu._ruler_kb._count_lbl.text == "0/24", "counter reads 0/24 when cleared")
	menu._ruler_kb.close()
	_check(not menu._ruler_kb.visible, "keyboard closes on done")
	menu._ruler_input.text = ""
	menu._open_ruler_keyboard()
	menu._close_ruler_keyboard()
	_check(not menu._ruler_kb.visible, "menu close helper hides keyboard")
	# Toggle one faction off via the real handler (min-2 enforced).
	var before: int = menu._active_factions.size()
	var dummy_cb := CheckBox.new()
	menu._on_faction_toggle(dummy_cb, "undead", false)
	_check(menu._active_factions.size() == before - 1, "faction toggle removes one")
	_check(menu._race_count_lbl.text == "4/5 factions enabled", "race count label updates")
	# Jeremy 2026-10-04: count label must never wrap vertically (was rendering
	# "5/5 factions enabled" one char per line when squeezed in the header HBox).
	_check(menu._race_count_lbl.autowrap_mode == TextServer.AUTOWRAP_OFF,
		"race count label never wraps")
	_check(menu._race_count_lbl.custom_minimum_size.x > 0.0,
		"race count label has fixed min width")
	# Jeremy 2026-10-04: compact faction toggle rows (short, 2-per-row flow).
	# Jeremy 2026-10-04 (later): checkbox must be a real square — the box
	# stylebox's content margins used to eat the whole box so the checkmark
	# drew as a "/" sliver ("scrunched checkbox" jank).
	for fid in menu._faction_rows:
		var parts: Array = menu._faction_rows[fid]
		var row_btn: Button = parts[2]
		_check(row_btn.custom_minimum_size.y <= menu._px(48) + 1.0,
			"faction toggle row is compact: " + fid)
		var cbox: PanelContainer = parts[0]
		_check(cbox.custom_minimum_size.x >= menu._px(32),
			"faction checkbox has real width: " + fid)
		_check(absf(cbox.custom_minimum_size.x - cbox.custom_minimum_size.y) < 1.0,
			"faction checkbox is square: " + fid)
		var cstyle: StyleBox = cbox.get_theme_stylebox("panel")
		_check(cstyle != null and cstyle.content_margin_left < 1.0
			and cstyle.content_margin_right < 1.0,
			"faction checkbox stylebox has no inset margins: " + fid)
	# Jeremy 2026-10-04: the whole faction screen must fit one iPhone 17
	# portrait screen (title -> START, no scroll). Structural budget checks:
	# compact carousel, compact name input.
	_check(menu._carousel3d_view.custom_minimum_size.y <= menu._px(340) + 1.0,
		"faction carousel is compact")
	_check(menu._ruler_input.custom_minimum_size.y <= menu._px(70) + 1.0,
		"ruler name input is compact")
	# Min-2 enforcement: try to drop below 2.
	menu._on_faction_toggle(dummy_cb, "ogres", false)
	menu._on_faction_toggle(dummy_cb, "elves", false)
	menu._on_faction_toggle(dummy_cb, "gnomes", false)
	_check(menu._active_factions.size() == 2, "min 2 factions enforced")
	# Adventure variant.
	menu._show_faction(true)
	_check(menu._adventure_setup, "adventure faction variant")
	_check(menu._hero_input != null, "hero name input present")
	# Other screens.
	menu._show_worlds()
	_check(menu._screen == "worlds", "worlds screen shows")
	menu._show_settings()
	_check(menu._screen == "settings", "settings screen shows")
	menu._show_credits()
	_check(menu._screen == "credits", "credits screen shows")
	menu._show_hearsay()
	_check(menu._screen == "hearsay", "hearsay screen shows")
	# Ruler name verbatim through the world-setup flow.
	# CHOOSE WORLD -> Forge Your World screen; START GAME (confirm) emits
	# world_game_requested with the ruler name verbatim.
	var got := {}
	menu.world_game_requested.connect(func(f: String, r: String, _t: String,
			_s: String, _o: Dictionary, _seed: int) -> void:
		got["f"] = f
		got["r"] = r)
	menu._show_faction()
	menu._ruler_input.text = "  ass  "
	menu._on_start_game()
	_check(menu._screen == "worldsetup", "choose world opens world setup")
	var ws: WorldSetupScreen = null
	for c in menu.get_children():
		if c is WorldSetupScreen:
			ws = c
	_check(ws != null, "world setup screen instantiated")
	if ws != null:
		# Bypass the preview-bake busy guard: this test verifies the
		# ruler/faction signal flow, not the terrain preview timing.
		ws._busy = false
		ws._on_start()
	_check(got.get("r") == "  ass  ", "ruler name emitted verbatim")
	_check(got.get("f") == "gnomes", "default faction gnomes selected")
	menu.dismiss()
	_check(not menu.visible, "dismiss hides menu")
	# Mobile scaling (Jeremy 2026-10-04: device pixels, not CSS).
	# Scale is viewport width / 1200px baseline, clamped 0.7-2.0.
	# 1280px viewport -> 1.067. 390px CSS (1170 device) -> 0.975.
	_check(absf(menu._compute_ui_scale(Vector2(1280, 720)) - 1.067) < 0.01,
		"ui scale is viewport/1200 clamped")
	menu._ui_scale_forced = 1280.0 / 390.0
	menu._show_title()
	var col: VBoxContainer = null
	for n in menu._root.find_children("*", "VBoxContainer", true, false):
		# Take the LAST match: queue_free()d columns from earlier screens
		# linger until frame end, so the newest column is last in tree order.
		if (n as VBoxContainer).custom_minimum_size.x > 100.0:
			col = n
	_check(col != null, "menu column found")
	if col != null:
		# Jeremy 2026-10-04: no custom scaling. Column is min(94vw, 430px)
		# in design pixels. Godot's stretch mode handles the rest.
		# Test viewport is 1280 wide -> 430 (capped).
		_check(absf(col.custom_minimum_size.x - 860.0) < 2.0,
			"column fills narrow viewport (HTML 94vw parity)")
	_check(absf(menu._continue_btn.custom_minimum_size.y - 145.0) < 1.0,
		"menu card height scales for touch")
	_check(menu._pxi(16) == 40, "font px is identity with no scaling")
	# SC1 title buttons (Jeremy 2026-10-08): text directly on the Button,
	# no child labels — big centered cream text, readable on iPhone.
	_check(menu._continue_btn.text == "Continue"
		and menu._continue_btn.get_theme_font_size("font_size") == 55,
		"card title readable on iPhone")
	# Jeremy 2026-10-04: NO fill boost, NO custom scaling. Godot handles it.
	# _fill_boost_for and _refit_to_screen are dead code — scale stays 1.0.
	_check(absf(menu._ui_scale - 2.5) < 0.001, "ui scale is 2.5 fixed baseline")
	_check(absf(menu._continue_btn.custom_minimum_size.y - 145.0) < 1.0,
		"card height is design pixels")
	var col2: VBoxContainer = null
	for n in menu._root.find_children("*", "VBoxContainer", true, false):
		if (n as VBoxContainer).custom_minimum_size.x > 100.0:
			col2 = n
	# Column width is min(94vw, 430px) in design pixels.
	_check(col2 != null and absf(col2.custom_minimum_size.x - 860.0) < 2.0,
		"column width is design pixels")
	menu._ui_scale_forced = 0.0
	menu._show_title()
	# Jeremy 2026-10-04: no viewport-based scaling. Design pixels, engine scales.
	_check(menu._continue_btn.custom_minimum_size.y == 145.0,
		"desktop layout uses design pixels")
	# Settings glow-up (Jeremy 2026-10-02): no tofu title, custom toggles,
	# cards, bigger fonts.
	menu._ui_scale_forced = 2.0
	menu._show_settings()
	_check(menu._screen == "settings", "settings screen shows (scaled)")
	var titles: Array = []
	for n in menu._root.find_children("*", "Label", true, false):
		titles.append((n as Label).text)
	_check("Settings" in titles, "settings title has no tofu icon")
	_check(not ("⚙️ Settings" in titles), "tofu gear removed from title")
	var toggles: Array = []
	for n in menu._root.find_children("*", "Button", true, false):
		var b := n as Button
		# GoldToggle: toggle_mode + 54px touch target (faction checkboxes
		# are plain CheckBox nodes, menu cards are not toggle_mode).
		if b != null and b.toggle_mode and b.custom_minimum_size.x >= 50.0:
			toggles.append(b)
	_check(toggles.size() >= 6, "custom graphical toggles present (%d)" % toggles.size())
	# Toggling one flips the setting and persists.
	var t0 := toggles[0] as Button
	var was_on: bool = t0.button_pressed
	t0.button_pressed = not was_on
	_check(t0.button_pressed != was_on, "toggle flips state")
	# Cards: settings rows wrapped in gold-bordered panels.
	var cards := 0
	for n in menu._root.find_children("*", "PanelContainer", true, false):
		cards += 1
	_check(cards >= 9, "settings rows are cards (%d)" % cards)
	# Bigger controls: selects and slider exist with touch-sized minimums.
	var selects := 0
	for n in menu._root.find_children("*", "OptionButton", true, false):
		if (n as OptionButton).custom_minimum_size.y >= 50.0:
			selects += 1
	_check(selects >= 3, "styled dropdowns present (%d)" % selects)
	var sliders := 0
	for n in menu._root.find_children("*", "HSlider", true, false):
		if (n as HSlider).custom_minimum_size.y >= 48.0:
			sliders += 1
	_check(sliders >= 1, "touch-sized volume slider present")
	# Menu atmosphere (graphics-hourly 2026-10-03): god rays, pollen motes,
	# distant birds living over the scrolling landscape.
	_check(menu._bg_rays.size() == 4, "four god-ray shafts built")
	var _ray0: TextureRect = menu._bg_rays[0]
	_check(_ray0.material != null, "rays have a blend material")
	var _raymat := _ray0.material as CanvasItemMaterial
	_check(_raymat != null and _raymat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
		"rays use additive blend")
	_check(_ray0.rotation_degrees > 15.0 and _ray0.rotation_degrees < 40.0,
		"rays slant diagonally")
	_check(menu._bg_pollen != null and is_instance_valid(menu._bg_pollen),
		"pollen particle node built")
	_check(menu._bg_pollen.amount >= 8 and menu._bg_pollen.amount <= 72,
		"pollen amount tier-scaled (%d)" % menu._bg_pollen.amount)
	_check(menu._bg_pollen.texture != null, "pollen has a dot texture")
	_check(menu._bg_pollen.process_material != null, "pollen has a process material")
	_check(menu._bg_birds.size() == 5, "five birds built")
	var _bird0: Array = menu._bg_birds[0]
	_check(_bird0[1] != null and is_instance_valid(_bird0[1]) and (_bird0[1] as Polygon2D).polygon.size() == 10,
		"bird chevron polygon built")
	# Atmosphere survives a screen switch (rebuilt per screen).
	menu._show_faction()
	_check(menu._bg_rays.size() == 4 and is_instance_valid(menu._bg_rays[0]),
		"rays rebuilt on faction screen")
	_check(menu._bg_pollen != null and is_instance_valid(menu._bg_pollen),
		"pollen rebuilt on faction screen")
	_check(menu._bg_birds.size() == 5, "birds rebuilt on faction screen")
	# Animation tick advances the clock and pulses the rays.
	# (Mirror production: main.gd restores visible/process on quit-to-menu;
	# the earlier dismiss() in this test left them off.)
	menu.visible = true
	menu.set_process(true)
	var _t0: float = menu._bg_time
	menu._process(0.5)
	_check(menu._bg_time > _t0, "atmosphere clock advances")
	var _ra: float = (menu._bg_rays[0] as TextureRect).modulate.a
	_check(_ra >= 0.25 and _ra <= 0.85, "ray pulse in range (%f)" % _ra)
	# Worldsetup screen management (Jeremy 2026-10-02 critical bugs):
	# 1. _show_worldsetup must clear the faction screen (no overlap).
	# 2. dismiss() must free the WorldSetupScreen CanvasLayer (it does NOT
	#    inherit visibility from the parent Control — hiding the menu left
	#    it on screen over the running game).
	# 3. show_title() must exist for quit-to-menu rebuild.
	menu._ui_scale_forced = 2.0
	menu._show_faction()
	var faction_kids: int = menu._root.get_child_count()
	_check(faction_kids > 0, "faction screen has content")
	menu._show_worldsetup()
	_check(menu._screen == "worldsetup", "worldsetup screen shows")
	_check(menu._worldsetup != null and is_instance_valid(menu._worldsetup),
		"worldsetup tracked")
	# Faction screen content cleared (only bg/dim/scroll remain in _root).
	# Note: queue_free() is deferred, so check is_queued_for_deletion().
	var live_count := 0
	for c in menu._root.get_children():
		if not c.is_queued_for_deletion():
			live_count += 1
	_check(live_count == 0, "faction screen cleared for worldsetup (no overlap)")
	# dismiss() frees the CanvasLayer.
	menu.dismiss()
	_check(menu._worldsetup == null, "dismiss frees worldsetup CanvasLayer")
	_check(not menu.visible, "dismiss hides menu")
	# show_title rebuilds after dismiss.
	_check(menu.has_method("show_title"), "show_title exists for quit-to-menu")
	menu.visible = true
	menu.show_title()
	_check(menu._screen == "title", "show_title rebuilds title screen")
	menu._ui_scale_forced = 0.0
	# iPhone glyph sweep (Jeremy 2026-10-03): no VISIBLE label/button on
	# the title or worlds screens may carry emoji/special glyphs (tofu
	# boxes in the web export). Menu-card icons are drawn vector shapes
	# (DrawnMenuIcon, 2026-10-05), not text, so they pass the walk.
	var menu_bad: Array[String] = []
	_glyph_walk(menu._root, menu_bad)
	_check(menu_bad.is_empty(), "title screen chrome glyph-free")
	for bad in menu_bad:
		push_error("  menu glyph: " + bad)
	menu._show_worlds()
	menu_bad.clear()
	_glyph_walk(menu._root, menu_bad)
	_check(menu_bad.is_empty(), "worlds screen chrome glyph-free")
	for bad in menu_bad:
		push_error("  menu glyph: " + bad)
	# Jeremy 2026-10-04: iPhone safe areas — Dynamic Island, home indicator,
	# rounded corners. Portrait: top inset clears Island, bottom clears home.
	# Landscape: side insets for Island, smaller top/bottom. Desktop: none.
	menu._is_desktop = false
	menu._orientation = "portrait"
	var si_p: Vector4 = menu._safe_insets()
	_check(si_p.x >= 150.0, "portrait safe top clears Dynamic Island")
	_check(si_p.y >= 80.0, "portrait safe bottom clears home indicator")
	menu._orientation = "landscape"
	var si_l: Vector4 = menu._safe_insets()
	_check(si_l.z >= 100.0, "landscape safe side clears Island")
	_check(si_l.y >= 40.0, "landscape safe bottom clears home indicator")
	menu._is_desktop = true
	var si_d: Vector4 = menu._safe_insets()
	_check(si_d == Vector4.ZERO, "desktop has no safe insets")
	print("test_menu_smoke: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
