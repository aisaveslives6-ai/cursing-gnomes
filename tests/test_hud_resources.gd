extends SceneTree
## Cursing Gnomes — HUD resource-bar glyph tests (Jeremy 2026-10-03).
##
## Jeremy's iPhone screenshot showed the top-bar resource icons rendering as
## tofu boxes: emoji (and other special glyphs) do not render in the Godot
## web export on iPhone Safari. UI chrome must use text labels or drawn
## icons — never glyphs (same rule as the sidebar bubbles).
##
## Covers: Resources-tab resource labels (GOLD/WOOD/FOOD/SEEDS/OIL)
## contain no glyph characters after refresh (Jeremy 2026-10-03: the
## overworld top bar was removed — resources live in the Resources
## sidebar tab); the sidebar phone tab carries a "Phone" tooltip;
## the drawer's resource labels match.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hud_resources.gd
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


## True when the string contains any non-ASCII glyph/emoji (anything above
## the box-drawing block — plain text labels never reach this high).
static func _has_glyph(s: String) -> bool:
	for i in range(s.length()):
		if s.unicode_at(i) > 0x2500:
			return true
	return false


func _initialize() -> void:
	print("=== Cursing Gnomes HUD resource-bar glyph tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.player_faction = "gnomes"
	gs.resources.add_resource("gnomes", "gold", 1234)
	gs.resources.add_resource("gnomes", "wood", 567)

	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	await process_frame
	hud._refresh()

	# Resources tab panel: one label per resource, text-only.
	var res_labels: Dictionary = hud._res_labels
	_check("res labels built for every resource",
		res_labels.size() == Config.RESOURCES.size())
	for res: String in Config.RESOURCES:
		var l: Label = res_labels.get(res)
		_check("res label present: " + res, l != null)
		if l == null:
			continue
		_check("res label glyph-free: " + res, not _has_glyph(l.text))
		_check("res label caps name: " + res,
			l.text.begins_with(res.to_upper() + ":"))
	# Cold sampler (single sample): rates read +0.0/min until a second sample
	# lands a second later.
	_check("gold amount shown",
		String(res_labels["gold"].text) == "GOLD: %d (+0.0/min)" % int(gs.resources.get_amount("gnomes", "gold")))
	_check("wood amount shown",
		String(res_labels["wood"].text) == "WOOD: %d (+0.0/min)" % int(gs.resources.get_amount("gnomes", "wood")))

	# Phone tab: sidebar bubble with a "Phone" tooltip (top bar removed).
	_check("phone sidebar tab present", hud._side_tabs.has("phone"))
	var phone_b: Button = hud._side_tabs.get("phone")
	_check("phone tab tooltip", phone_b != null and phone_b.tooltip_text == "Phone")

	# Drawer resource section: same treatment as the top bar.
	hud._drawer.visible = true
	hud._refresh()
	var drawer_labels: Dictionary = hud._res_drawer_labels
	_check("drawer res labels built", drawer_labels.size() == Config.RESOURCES.size())
	for res: String in Config.RESOURCES:
		var dl: Label = drawer_labels.get(res)
		_check("drawer res label present: " + res, dl != null)
		if dl == null:
			continue
		_check("drawer res label glyph-free: " + res, not _has_glyph(dl.text))
		_check("drawer res label caps name: " + res,
			dl.text.begins_with(res.to_upper() + ":"))

	# Drawer chrome (Jeremy 2026-10-03): every visible section header,
	# button, and title in the realm drawer must be glyph-free —
	# emoji render as tofu boxes in the iPhone web export.
	hud._rebuild_drawer()
	var drawer_bad: Array[String] = []
	_walk_glyphs(hud._drawer_vbox, drawer_bad)
	_check("drawer chrome glyph-free", drawer_bad.is_empty())
	for bad in drawer_bad:
		print("  drawer glyph: ", bad)

	gs.free()
	hud.queue_free()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## Recursively collects "NodePath: text" for visible Labels/Buttons whose
## text contains a non-ASCII glyph (same >U+2500 rule as _has_glyph).
func _walk_glyphs(n: Node, out: Array[String]) -> void:
	if n is Label or n is Button:
		var t: String = (n as Label).text if n is Label else (n as Button).text
		if n.is_visible_in_tree() and _has_glyph(t):
			out.append("%s: %s" % [n.get_path(), t])
	for c in n.get_children():
		_walk_glyphs(c, out)
