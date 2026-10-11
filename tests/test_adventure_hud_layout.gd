extends SceneTree
## Cursing Gnomes — adventure HUD quest-panel layout tests.
##
## Covers the 2026-10-08 wake graphics-hourly fix in
## scripts/ui/adventure_hud.gd:
##   - REAL BUG: the quest panel used position.y = 0 with the
##     PRESET_CENTER_RIGHT anchor preset (anchor sits at the vertical
##     center), so the panel's top started at mid-screen and ~36% of it hung
##     off the bottom — the lower sections (Outfitter, Deeds) were
##     unreachable on iPhone.
##   - Fix: _layout_panel() vertically centers the panel (position.y =
##     -ph/2), refits it on viewport size_changed (rotation), and clears the
##     right safe-area inset.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_adventure_hud_layout.gd
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
		print("  FAIL: ", test_name)


func _new_hud() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var adv := SimAdventure.new(gs)
	var ok: bool = adv.start("gnomes", "TestHero", "soldier",
		Vector2(4096, 4096))
	var hud := AdventureHUD.new()
	hud.name = "AdventureHUD"
	root.add_child(hud)
	hud.setup(adv, gs)
	return [gs, adv, ok, hud]


func _init() -> void:
	print("=== Cursing Gnomes adventure HUD layout tests ===")
	seed(20261008)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_panel_vertically_centered()
	_test_panel_fits_viewport()
	_test_panel_clears_right_edge()
	_test_panel_refits_on_resize()
	_test_scroll_child_sized()
	_test_quest_toggle_visible()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The panel's vertical center must match the viewport's vertical center
## (within rounding) — the pre-fix bug parked its top at mid-screen.
func _test_panel_vertically_centered() -> void:
	var parts := _new_hud()
	var hud: AdventureHUD = parts[3]
	var p: PanelContainer = hud._panel
	var vsz: Vector2 = root.get_visible_rect().size
	var r: Rect2 = p.get_global_rect()
	_check("panel vertically centered",
		absf(r.get_center().y - vsz.y / 2.0) < 2.0)
	_check("panel top below screen top", r.position.y >= -1.0)
	parts[0].queue_free()
	hud.queue_free()


## The whole panel must sit inside the viewport (the bug hung ~36% of it
## off the bottom).
func _test_panel_fits_viewport() -> void:
	var parts := _new_hud()
	var hud: AdventureHUD = parts[3]
	var p: PanelContainer = hud._panel
	var vsz: Vector2 = root.get_visible_rect().size
	var r: Rect2 = p.get_global_rect()
	_check("panel bottom inside viewport",
		r.position.y + r.size.y <= vsz.y + 1.0)
	_check("panel has real size", r.size.x > 100.0 and r.size.y > 100.0)
	parts[0].queue_free()
	hud.queue_free()


## The panel must not touch the right screen edge (safe-area clearance).
func _test_panel_clears_right_edge() -> void:
	var parts := _new_hud()
	var hud: AdventureHUD = parts[3]
	var p: PanelContainer = hud._panel
	var vsz: Vector2 = root.get_visible_rect().size
	var r: Rect2 = p.get_global_rect()
	_check("panel clears right edge",
		r.position.x + r.size.x <= vsz.x - 1.0)
	parts[0].queue_free()
	hud.queue_free()


## _layout_panel() is public-by-underscore so rotation refits can be driven
## directly: re-running it after a viewport change keeps the panel centered.
func _test_panel_refits_on_resize() -> void:
	var parts := _new_hud()
	var hud: AdventureHUD = parts[3]
	hud._layout_panel()
	var p: PanelContainer = hud._panel
	var vsz: Vector2 = root.get_visible_rect().size
	var r: Rect2 = p.get_global_rect()
	_check("panel still centered after relayout",
		absf(r.get_center().y - vsz.y / 2.0) < 2.0)
	_check("panel still inside viewport after relayout",
		r.position.y + r.size.y <= vsz.y + 1.0)
	parts[0].queue_free()
	hud.queue_free()


## The ScrollContainer child must carry the same footprint so the panel's
## combined minimum size matches (prevents container re-shrink).
func _test_scroll_child_sized() -> void:
	var parts := _new_hud()
	var hud: AdventureHUD = parts[3]
	var p: PanelContainer = hud._panel
	var s: ScrollContainer = hud._panel_scroll
	_check("scroll min size matches panel",
		s.custom_minimum_size.is_equal_approx(p.custom_minimum_size))
	parts[0].queue_free()
	hud.queue_free()


## The "Quests" toggle had the same position/anchor confusion as the panel
## (negative-x anchor offset assigned after add_child) and rendered fully
## off-screen — the quest panel was unreachable. It must sit top-right,
## inside the viewport, clearing the safe-area inset.
func _test_quest_toggle_visible() -> void:
	var parts := _new_hud()
	var hud: AdventureHUD = parts[3]
	var tg: Button = hud._quest_toggle
	var vsz: Vector2 = root.get_visible_rect().size
	var r: Rect2 = tg.get_global_rect()
	_check("toggle left edge on screen", r.position.x >= -1.0)
	_check("toggle top edge on screen", r.position.y >= -1.0)
	_check("toggle right edge inside viewport",
		r.position.x + r.size.x <= vsz.x + 1.0)
	_check("toggle near right edge",
		vsz.x - (r.position.x + r.size.x) < 80.0)
	parts[0].queue_free()
	hud.queue_free()
