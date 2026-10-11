extends SceneTree
## Cursing Gnomes — sandbox director + army tab glyph tests (Jeremy 2026-10-03).
##
## Jeremy's iPhone screenshot showed emoji rendering as tofu boxes in the
## Godot web export: UI chrome must use text labels or drawn icons, never
## glyphs. Covers the sandbox director panel (director title, pause/menu
## buttons, action/weather/disaster/tool rows, phase chip, director log
## lines produced by the real handlers) and the army tab build.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_director_glyphs.gd
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


## Same >U+2500 rule as test_hud_resources: plain text labels never
## reach this high; anything above it is a tofu risk on iPhone.
static func _has_glyph(s: String) -> bool:
	for i in range(s.length()):
		if s.unicode_at(i) > 0x2500:
			return true
	return false


func _initialize() -> void:
	print("=== Cursing Gnomes director/army glyph tests ===")
	_run.call_deferred()


func _walk_glyphs(n: Node, out: Array[String]) -> void:
	if n is Label or n is Button:
		var t: String = (n as Label).text if n is Label else (n as Button).text
		if n.is_visible_in_tree() and _has_glyph(t):
			out.append("%s: %s" % [n.get_path(), t])
	for c in n.get_children():
		_walk_glyphs(c, out)


func _run() -> void:
	await process_frame
	await process_frame

	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.player_faction = "gnomes"
	gs.set_meta("army", SimArmy.new(gs))
	var sb := SimSandbox.new(gs)

	# --- Sandbox director panel -------------------------------------
	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	hud.enter_sandbox_mode(sb)
	await process_frame
	await process_frame

	var dir_bad: Array[String] = []
	_walk_glyphs(hud._sb_panel, dir_bad)
	_check("director panel chrome glyph-free", dir_bad.is_empty())
	for bad in dir_bad:
		print("  director glyph: ", bad)

	# Director log lines produced by the real handlers must be glyph-free.
	hud._on_sb_boost()
	hud._on_sb_ally()
	hud._on_sb_war_all()
	hud._on_sb_peace()
	hud._on_sb_skip_day()
	var log_bad: Array[String] = []
	_walk_glyphs(hud._sb_panel, log_bad)
	_check("director log lines glyph-free", log_bad.is_empty())
	for bad in log_bad:
		print("  director log glyph: ", bad)
	# Phase chip text (war/peace) is set by _refresh_sandbox.
	_check("phase chip glyph-free",
		hud._sb_phase_label == null or not _has_glyph(hud._sb_phase_label.text))

	# --- Army tab ----------------------------------------------------
	ArmyTab.set_ui_scale(1.0)
	var vbox := VBoxContainer.new()
	root.add_child(vbox)
	ArmyTab.build(gs, vbox)
	await process_frame
	var army_bad: Array[String] = []
	_walk_glyphs(vbox, army_bad)
	_check("army tab glyph-free", army_bad.is_empty())
	for bad in army_bad:
		print("  army glyph: ", bad)

	hud.queue_free()
	vbox.queue_free()
	gs.free()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
