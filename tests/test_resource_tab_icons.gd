extends SceneTree
## Cursing Gnomes — Resources tab / drawer icon-row tests.
##
## The Resources side-tab and the drawer both show one row per resource:
## a pixel-art icon (assets/art/icons/icon_<res>.png via Art.resource_icon())
## next to the live text label. Covers icon presence for all six
## Config.RESOURCES (incl. the new soul_essence icon), the Hud._res_icon_row
## row structure, and graceful handling of a resource with no icon.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_resource_tab_icons.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes resource tab icon tests ===")
	_test_all_resource_icons_load()
	_test_icon_row_structure()
	_test_icon_row_missing_icon()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Every Config.RESOURCES key must resolve to a real icon texture now that
## the soul_essence icon exists alongside gold/wood/food/seeds/oil.
func _test_all_resource_icons_load() -> void:
	_check("tab icons: 6 resources configured", Config.RESOURCES.size() == 6)
	var expected_h := {"gold": 64, "wood": 64, "food": 64, "seeds": 64,
		"oil": 64, "soul_essence": 64}
	for res: String in Config.RESOURCES:
		var t: Texture2D = Art.resource_icon(res)
		_check("tab icons: %s icon loads" % res, t != null)
		if t != null:
			_check("tab icons: %s icon 64px tall" % res,
				t.get_height() == int(expected_h[res]))
	var soul: Texture2D = Art.resource_icon("soul_essence")
	if soul != null:
		_check("tab icons: soul_essence is 59x64", soul.get_width() == 59
			and soul.get_height() == 64)


## Hud._res_icon_row builds an HBoxContainer holding a textured TextureRect
## and a Label, for every resource.
func _test_icon_row_structure() -> void:
	var hud := Hud.new()
	for res: String in Config.RESOURCES:
		var parts: Array = hud._res_icon_row(res, 28)
		_check("row: %s returns [row, label]" % res,
			parts.size() == 2 and parts[0] is HBoxContainer and parts[1] is Label)
		var row: HBoxContainer = parts[0]
		_check("row: %s has icon + label children" % res,
			row.get_child_count() == 2 and row.get_child(0) is TextureRect
			and row.get_child(1) is Label)
		var icon: TextureRect = row.get_child(0)
		_check("row: %s icon textured" % res, icon.texture != null)
		_check("row: %s icon keeps aspect" % res,
			icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		var l: Label = parts[1]
		_check("row: %s label 28pt" % res,
			l.get_theme_font_size("font_size") == 28)
	hud.queue_free()


## A resource with no icon file still builds a valid row (empty TextureRect),
## so the label path never crashes.
func _test_icon_row_missing_icon() -> void:
	var hud := Hud.new()
	var parts: Array = hud._res_icon_row("platinum", 24)
	var row: HBoxContainer = parts[0]
	var icon: TextureRect = row.get_child(0)
	_check("row: missing icon -> null texture, no crash", icon.texture == null)
	_check("row: missing icon label still 24pt",
		(parts[1] as Label).get_theme_font_size("font_size") == 24)
	hud.queue_free()
