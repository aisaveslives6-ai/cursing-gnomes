extends SceneTree
## Cursing Gnomes — drawn menu-card icon tests (Jeremy 2026-10-05).
##
## Main-menu cards used to carry emoji icons; the box was hidden on web
## because Godot's default font renders emoji as tofu in the web export.
## DrawnMenuIcon draws all eight card icons as pure vector shapes — no
## font glyphs, no textures — so the icon boxes are visible again.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_menu_card_icons.gd
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


static func _has_glyph(s: String) -> bool:
	for i in range(s.length()):
		if s.unicode_at(i) > 0x2500:
			return true
	return false


func _init() -> void:
	# 1. Kind registry: 8 kinds, all ASCII, no duplicates.
	_check("8 kinds registered", DrawnMenuIcon.KINDS.size() == 8)
	var seen: Dictionary = {}
	var all_ascii := true
	for k in DrawnMenuIcon.KINDS:
		seen[k] = seen.get(k, 0) + 1
		for i in range(k.length()):
			if k.unicode_at(i) > 127:
				all_ascii = false
	_check("kinds unique", seen.size() == 8)
	_check("kinds are ASCII (never tofu)", all_ascii)
	for want in ["play", "swords", "floppy", "eye", "dagger", "gear",
			"scroll", "speech"]:
		_check("kind present: " + want, want in DrawnMenuIcon.KINDS)

	# 2. Construction: defaults sane, args stick, mouse filter ignores.
	for k in DrawnMenuIcon.KINDS:
		var ic := DrawnMenuIcon.new(k, Color.WHITE, 3.0)
		_check(k + ": stores kind", ic.kind == k)
		_check(k + ": stores thickness", ic.thickness == 3.0)
		_check(k + ": mouse filter IGNORE",
			ic.mouse_filter == Control.MOUSE_FILTER_IGNORE)
		_check(k + ": has minimum size", ic.custom_minimum_size.x >= 40.0)
		ic.queue_free()
	var def := DrawnMenuIcon.new()
	_check("default kind valid", def.kind in DrawnMenuIcon.KINDS)
	def.queue_free()

	# 3. Built menu cards: visible icon box with a DrawnMenuIcon inside,
	# and NO text glyph in the card chrome.
	var menu := MainMenu.new()
	for spec in [["play", "T1"], ["swords", "T2"], ["floppy", "T3"],
			["eye", "T4"], ["dagger", "T5"], ["gear", "T6"],
			["scroll", "T7"], ["speech", "T8"]]:
		var card: Button = menu._menu_card(spec[0], spec[1], "sub")
		_check(spec[0] + ": card is a Button", card is Button)
		var found_icon := false
		var found_box := false
		var glyph_bad := ""
		for c in card.get_children():
			var box := c.get_child(0) if c.get_child_count() > 0 else null
			if box == null:
				continue
			for gc in box.get_children():
				if gc is DrawnMenuIcon:
					found_box = true
					_check(spec[0] + ": icon box visible",
						(gc as Control).get_parent().is_visible())
					found_icon = (gc as DrawnMenuIcon).kind == spec[0]
		_check(spec[0] + ": drawn icon in card", found_icon and found_box)
		# Walk the card's text: nothing above U+2500 may be visible.
		var texts := _collect_text(card)
		for t in texts:
			if _has_glyph(t):
				glyph_bad = t
		_check(spec[0] + ": card text glyph-free", glyph_bad == "")
		card.queue_free()
	menu.queue_free()

	print("test_menu_card_icons: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		push_error("  " + f)
	quit(1 if _failed > 0 else 0)


func _collect_text(n: Node) -> Array[String]:
	var out: Array[String] = []
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		out.append_array(_collect_text(c))
	return out
